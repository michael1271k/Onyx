import Foundation
import GRDB

/// The write path for everything the "You" tab edits.
///
/// ── WHY IT IS NOT `updatePreferences` ───────────────────────────────────────
/// `Preferences` is the eight scalars a settings SCREEN binds to — units, week
/// start, reduce motion, RPE, plan, phase, cutoff, timezone. The You tab edits
/// twenty more columns that are not preferences at all: five macro goals, three
/// body destinations, the active lever and its expiry, water, sleep, active
/// energy, and the per-muscle weekly set targets on a different table entirely.
/// Widening `Preferences` to hold them would make every toggle rewrite every
/// goal — which is precisely the web app's `save()` bug, where flipping Reduce
/// Motion rewrote the user's calorie target.
///
/// So this file patches. Each function reads the row, hands it to the caller to
/// change, writes it back and queues it — all inside ONE transaction, because a
/// row that is written locally and not queued is a row that never leaves the
/// phone, and that is the failure the outbox exists to make impossible.
///
/// ── AND WHY IT IS HERE AND NOT IN THE APP ───────────────────────────────────
/// `AppDatabase.writer` is internal on purpose: a view that can open its own
/// transaction can also forget to queue one. The API surface a screen gets is
/// "change these fields", never "here is the database".
public extension AppDatabase {

    // MARK: - user_goals

    /// A live sequence of the whole goals row. `nil` until the first write.
    func userGoalsStream(userId: String) -> AsyncThrowingStream<UserGoalRow?, any Error> {
        stream(ValueObservation.tracking { db in
            try UserGoalRow.filter(Column("user_id") == userId).fetchOne(db)
        })
    }

    /// Patch the goals row and queue it.
    ///
    /// The row is created if it does not exist yet — by `updatePreferences`,
    /// which already owns the shape of a brand-new row. Doing it there rather
    /// than repeating a twelve-field initialiser here means there is still
    /// exactly one answer to "what does a fresh `user_goals` row look like",
    /// and it costs one extra transaction once per install.
    @discardableResult
    func editUserGoals(
        userId: String, now: Date = Date(), _ change: @Sendable (inout UserGoalRow) -> Void
    ) throws -> UserGoalRow {
        if try userGoals(userId: userId) == nil {
            _ = try updatePreferences(userId: userId, now: now) { _ in }
        }
        return try writer.write { db in
            guard var row = try UserGoalRow.filter(Column("user_id") == userId).fetchOne(db) else {
                throw GoalsEditError.missingRow(table: UserGoalRow.databaseTableName)
            }
            change(&row)
            try row.save(db)
            try Self.enqueueRowUpsert(table: UserGoalRow.databaseTableName, id: row.id, in: db)
            return row
        }
    }

    // MARK: - plan_phase_goals

    /// The stored overrides for one (plan, phase). `nil` means "no overrides" —
    /// the caller falls back to the program's own preset, and MUST NOT read that
    /// as zeroes.
    func planPhaseGoalsStream(
        userId: String, planId: String, phase: String
    ) -> AsyncThrowingStream<PlanPhaseGoalRow?, any Error> {
        stream(ValueObservation.tracking { db in
            try PlanPhaseGoalRow
                .filter(Column("user_id") == userId
                        && Column("plan_id") == planId
                        && Column("phase") == phase)
                .fetchOne(db)
        })
    }

    /// Patch the (plan, phase) overrides and queue them.
    ///
    /// ── THE ID IS THE NATURAL KEY, NOT A UUID ───────────────────────────────
    /// This table has no `id` column on either side: Postgres resolves it by
    /// `(user_id, plan_id, phase)` and so does the local mirror. The outbox
    /// therefore names the row by that key, joined in primary-key order — see
    /// `AppDatabase.rowID`.
    @discardableResult
    func editPlanPhaseGoals(
        userId: String, planId: String, phase: String, now: Date = Date(),
        _ change: @Sendable (inout PlanPhaseGoalRow) -> Void
    ) throws -> PlanPhaseGoalRow {
        try writer.write { db in
            var row = try PlanPhaseGoalRow
                .filter(Column("user_id") == userId
                        && Column("plan_id") == planId
                        && Column("phase") == phase)
                .fetchOne(db)
                ?? PlanPhaseGoalRow(
                    userId: userId, planId: planId, phase: phase,
                    updatedAt: Self.localWriteTimestamp
                )
            change(&row)
            try row.save(db)
            try Self.enqueueRowUpsert(
                table: PlanPhaseGoalRow.databaseTableName,
                id: Self.rowID([userId, planId, phase]),
                in: db
            )
            return row
        }
    }

    // MARK: - plan_phase_volume

    /// Every stored weekly set target for one (plan, phase), by muscle name.
    ///
    /// A dictionary rather than rows because the caller draws sixteen landmarks
    /// whether or not the table holds sixteen rows — an absent muscle is the
    /// program's default, not a zero target.
    func planPhaseVolumeStream(
        userId: String, planId: String, phase: String
    ) -> AsyncThrowingStream<[String: Int], any Error> {
        stream(ValueObservation.tracking { db in
            let rows = try PlanPhaseVolumeRow
                .filter(Column("user_id") == userId
                        && Column("plan_id") == planId
                        && Column("phase") == phase)
                .fetchAll(db)
            return Dictionary(rows.map { ($0.muscle, $0.targetSets) }, uniquingKeysWith: { _, last in last })
        })
    }

    /// Set one muscle's weekly target and queue it.
    func setPlanPhaseVolume(
        userId: String, planId: String, phase: String, muscle: String, targetSets: Int,
        now: Date = Date()
    ) throws {
        try writer.write { db in
            var row = try PlanPhaseVolumeRow
                .filter(Column("user_id") == userId
                        && Column("plan_id") == planId
                        && Column("phase") == phase
                        && Column("muscle") == muscle)
                .fetchOne(db)
                ?? PlanPhaseVolumeRow(
                    userId: userId, planId: planId, phase: phase, muscle: muscle,
                    targetSets: targetSets, updatedAt: Self.localWriteTimestamp
                )
            row.targetSets = targetSets
            try row.save(db)
            try Self.enqueueRowUpsert(
                table: PlanPhaseVolumeRow.databaseTableName,
                id: Self.rowID([userId, planId, phase, muscle]),
                in: db
            )
        }
    }

    // MARK: - plans

    /// Point the active plan row at a program, and queue it.
    ///
    /// ── WHY THIS IS A SEPARATE TABLE FROM `user_goals.active_plan` ──────────
    /// `user_goals.active_plan` is what the app resolves the deck and the goals
    /// from. `plans` is the dated registry the charts read to label an era, and
    /// it carries `started_on`. Writing only the first would leave every chart
    /// still labelling this week with the previous program's name — a divergence
    /// nothing would surface until a report was read weeks later.
    ///
    /// ── ONE ROW PER PROGRAM SINCE W2 ────────────────────────────────────────
    /// `plans` used to hold one row per user whose `program_id` was rewritten
    /// on every switch. It holds one row per program now (the seed wrote the
    /// founder's three), and `Schedule.planId(owning:)` reads `started_on`
    /// across all of them to decide which plan a DATE belongs to. So a switch
    /// flips `active` — off the old row, on the new — and dates the new row
    /// only on its FIRST activation: a plan re-selected keeps the day it
    /// originally began, or every session under it would move to today.
    ///
    /// Does nothing when the registry has no row for the program: inventing
    /// one here would race the web's registry into two.
    func activatePlanRow(
        userId: String, programId: String, startedOn: String
    ) throws {
        try writer.write { db in
            try Self.activatePlanRow(db, userId: userId, programId: programId, startedOn: startedOn)
        }
    }

    /// The same, inside a caller's transaction — the seed runs the program it
    /// just wrote through this (Precision E2), so there is one rule for what
    /// "running" writes.
    static func activatePlanRow(
        _ db: Database, userId: String, programId: String, startedOn: String
    ) throws {
        let rows = try PlanRow.filter(Column("user_id") == userId).fetchAll(db)
        guard rows.contains(where: { $0.programId == programId }) else { return }
        for var row in rows {
            let wants = row.programId == programId
            var changed = false
            if (row.active ?? false) != wants { row.active = wants; changed = true }
            if wants, row.startedOn == nil { row.startedOn = startedOn; changed = true }
            guard changed else { continue }
            try row.save(db)
            try Self.enqueueRowUpsert(table: PlanRow.databaseTableName, id: row.id, in: db)
        }
    }
}

/// What can go wrong that is not a database error.
public enum GoalsEditError: Error, Equatable {
    /// A row this device just created is gone. Only reachable if something else
    /// deleted it between two transactions; carried rather than force-unwrapped
    /// so it reads as a bug report instead of a crash.
    case missingRow(table: String)
}
