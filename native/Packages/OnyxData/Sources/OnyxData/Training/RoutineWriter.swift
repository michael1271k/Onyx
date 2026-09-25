import Foundation
import GRDB
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Writing `routines` — the half D1 designed and nothing had yet used.
//
// W2 built the whole read side: the row, the mirror entry, the payload codec,
// `Program.from(routines:plans:)`, and a `push:` closure in the generated
// catalogue. What it never built was a single call site that ENQUEUES one. The
// rows arrived from the seed SQL and the phone could read them and nothing else.
//
// The routine builder is the first writer, and onboarding is the second — both
// come through here, because a day written two ways is a day that drifts.
//
// ── THE PAYLOAD IS THE PRESCRIPTION, NEVER THE ANATOMY ──────────────────────
// `Routines.swift` states the rule and it is repeated here because this is
// where it would be broken: what a movement TRAINS is resolved from
// `MuscleMap` at read time, so the payload carries the name, the sets, the reps,
// the rest and the seed load — and no muscle lists. A payload that carried its
// own would be a second copy of the anatomy that looks right until either copy
// is nudged.
//
// ── AND THE `exerciseId` IS RESOLVED HERE, NOT AT LOG TIME ──────────────────
// D3: the payload carries the catalogue uuid so the logger can stamp it on every
// set without a lookup. Resolving it at SAVE time means a movement whose name
// the catalogue cannot place fails in a routine editor — where there is a person
// looking at it who can fix the name — rather than at upload time three days
// later, where the failure is a red badge on a finished session.
// ─────────────────────────────────────────────────────────────────────────────

public extension AppDatabase {

    /// Upsert one routine day and queue it.
    ///
    /// `updatedAt` is `localWriteTimestamp` (`.distantPast`) like every other
    /// local write, so inventing a day cannot drag the delta cursor forward and
    /// hide the server's own newer rows on the next pull.
    func saveRoutineDay(userId: String, _ day: RoutineDay) throws {
        try writer.write { db in try Self.saveRoutineDay(db, userId: userId, day) }
    }

    /// A whole program in one transaction — onboarding's seed, and the
    /// builder's "duplicate day" once it has renumbered `sort`.
    ///
    /// One transaction because half a program is worse than none: a five-day
    /// split that lost its Friday looks like a four-day split and the schedule
    /// will happily call Friday a rest day.
    func saveRoutineDays(userId: String, _ days: [RoutineDay]) throws {
        try writer.write { db in
            for day in days { try Self.saveRoutineDay(db, userId: userId, day) }
        }
    }

    static func saveRoutineDay(_ db: Database, userId: String, _ day: RoutineDay) throws {
        var row = RoutineRow(
            userId: userId,
            programId: day.programId,
            dayKey: day.dayKey,
            label: day.label,
            sub: day.sub,
            weekday: day.weekday,
            accent: day.accent,
            sort: day.sort,
            payload: JSONText(raw: day.payload.encoded()),
            updatedAt: Self.localWriteTimestamp,
            notes: day.notes
        )
        row.updatedAt = Self.localWriteTimestamp
        try row.save(db)
        try Self.enqueueRowUpsert(
            table: RoutineRow.databaseTableName,
            id: Self.rowID([userId, day.programId, day.dayKey]),
            in: db
        )
    }

    /// Remove a day from a program, locally and on the server.
    ///
    /// A deleted day is NOT the same as a day with no exercises: the schedule
    /// reads a missing day as a rest day and an empty one as a session with
    /// nothing in it, and the logger will happily open the second.
    func deleteRoutineDay(userId: String, programId: String, dayKey: String) throws {
        try writer.write { db in
            try RoutineRow
                .filter(Column("user_id") == userId
                        && Column("program_id") == programId
                        && Column("day_key") == dayKey)
                .deleteAll(db)
            try Self.enqueueRowDelete(
                table: RoutineRow.databaseTableName,
                key: ["user_id": userId, "program_id": programId, "day_key": dayKey],
                in: db
            )
        }
    }

    /// Every `day_key` this account has ever logged a session against.
    ///
    /// A deleted routine day keeps its sessions — the delete only takes it out
    /// of the schedule — so its key is still SPOKEN FOR. A builder that minted
    /// keys from the live days alone would let a re-added day adopt a deleted
    /// one's history.
    func loggedDayKeys(userId: String) throws -> Set<String> {
        try writer.read { db in
            try Set(String.fetchAll(
                db,
                sql: "SELECT DISTINCT day_key FROM workout_sessions WHERE user_id = ? AND day_key IS NOT NULL",
                arguments: [userId]
            ))
        }
    }

    /// Every routine day of one program, in the order the logger reads them.
    func routineDays(userId: String, programId: String) throws -> [RoutineDay] {
        try writer.read { db in
            try RoutineRow
                .filter(Column("user_id") == userId && Column("program_id") == programId)
                .fetchAll(db)
                .map(RoutineDay.init)
                .sorted { ($0.sort, $0.weekday, $0.dayKey) < ($1.sort, $1.weekday, $1.dayKey) }
        }
    }
}

// MARK: - Resolving a payload against the catalogue

public extension RoutinePayload {

    /// Fill in every `exerciseId` the catalogue can name, and report what it
    /// could not.
    ///
    /// Deliberately NON-throwing: a routine with one unresolvable movement is
    /// still a routine worth saving, and refusing the whole day would mean a
    /// person could not write down a movement their catalogue has not caught up
    /// with yet. The set falls back to the legacy slug at log time exactly as it
    /// always has (D3), and the editor shows the warning.
    func resolving(_ index: ExerciseIndex) -> (payload: RoutinePayload, unresolved: [String]) {
        var out = self
        var unresolved: [String] = []
        for i in out.exercises.indices {
            if let existing = out.exercises[i].exerciseId, !existing.isEmpty { continue }
            do {
                out.exercises[i].exerciseId = try index.id(forName: out.exercises[i].name)
            } catch {
                unresolved.append(out.exercises[i].name)
            }
        }
        return (out, unresolved)
    }
}
