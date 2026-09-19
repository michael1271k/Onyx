import Foundation
import GRDB

/// The device preferences that are also facts about the athlete.
///
/// ── WHY THIS IS NOT `@AppStorage` ───────────────────────────────────────────
/// The plan's line for Wave 2 item 6 is "`@AppStorage` for units, week start,
/// track-RPE, active plan/phase; mirrored to `user_goals` through the outbox
/// like `prefsSync.ts` did". Mirrored is the operative word, and the web had it
/// the right way round in its own comment: *the database row is the source of
/// truth; localStorage is only its per-device cache for synchronous reads.*
///
/// GRDB is already a synchronous local cache of that row — that is what the
/// mirror IS. Adding `@AppStorage` on top would be a THIRD copy of a value that
/// already has two, and the web's own bug list for `hydratePrefsFromDb` is what
/// happens when copies drift:
///
///   1. It read `active_program`, a pre-consolidation column, while the writer
///      wrote `active_plan` — and `active_program` still holds a plan id that
///      no longer exists.
///   2. It wrote the predecessor web app's `<brand>_active_program`
///      localStorage key, which the reader consulted only as a fallback
///      behind `<brand>_active_plan`, so any device that had used the plan
///      picker ignored the database value entirely. Neither key exists under
///      this app's name and neither is read any more — this records what the
///      bug WAS, and searching for a literal will not find one.
///   3. Phase was not carried at all: switching to bulk on the desktop left the
///      phone on cut, and phase drives the prescribed set counts — so the two
///      devices disagreed about the workout itself.
///
/// All three are the same failure. Here there is one row, one writer, and
/// `ValueObservation` pushes a change into every view that is drawing — which is
/// also what makes a preference set on the Watch appear on the phone without
/// anything having to know that a preference changed.
///
/// The legacy-column fallbacks survive, because the legacy columns are still
/// live and still hold values: `active_plan` falls back to `active_program`,
/// `active_phase` to `goal_preset`.
public struct Preferences: Sendable, Equatable {
    public var unitSystem: String
    public var reduceMotion: Bool
    public var trackRpe: Bool
    /// `metric`/`imperial` and the rest are free text server-side; the id is
    /// validated by the caller against `Program`, never adopted blind — a dead
    /// plan id (`onyx5`) is exactly what is still sitting in
    /// `active_program`.
    public var activePlan: String?
    public var activePhase: String?
    /// The day the athlete's week ENDS on, 0 = Sunday. The app thinks in week
    /// starts; the column stores the end.
    public var weekEndDay: Int?
    public var dayCutoffHour: Int
    public var timezone: String

    /// What a device with no row is graded and drawn against. Matches the
    /// column defaults, so a fresh install and a fresh row agree.
    public static let fallback = Preferences(
        unitSystem: "metric", reduceMotion: false, trackRpe: true,
        activePlan: nil, activePhase: nil, weekEndDay: nil,
        dayCutoffHour: 0, timezone: TimeZone.current.identifier
    )

    /// `week_end_day` 0 (Sunday) ⇒ the week starts Monday (1); anything else ⇒
    /// Sunday (0). The inverse of `weekStartDayFromEndDay`.
    public var weekStartDay: Int {
        weekEndDay == 0 ? 1 : 0
    }
}

public extension Preferences {
    init(_ row: UserGoalRow) {
        self.init(
            unitSystem: row.unitSystem,
            reduceMotion: row.reduceMotion,
            trackRpe: row.trackRpe,
            // Current column first, legacy second — and NEITHER is validated
            // here. Adopting a plan id is the caller's call, because only the
            // caller knows the live `PROGRAMS` list.
            activePlan: row.activePlan ?? row.activeProgram,
            // `goal_preset` is the older tag the macro presets still write, and
            // is a correct fallback for the same value.
            activePhase: row.activePhase ?? row.goalPreset,
            weekEndDay: row.weekEndDay,
            dayCutoffHour: row.dayCutoffHour,
            timezone: row.timezone
        )
    }
}

// MARK: - Reading and writing

public extension AppDatabase {

    /// The stored preferences, or the fallback.
    func preferences(userId: String) throws -> Preferences {
        guard let row = try userGoals(userId: userId) else { return .fallback }
        return Preferences(row)
    }

    /// A live sequence of them. What a settings screen binds to.
    func preferencesStream(userId: String) -> AsyncThrowingStream<Preferences, any Error> {
        stream(ValueObservation.tracking { db in
            try UserGoalRow.filter(Column("user_id") == userId).fetchOne(db)
                .map(Preferences.init) ?? .fallback
        })
    }

    /// The whole row, for the goals scoring needs as well as the preferences.
    func userGoals(userId: String) throws -> UserGoalRow? {
        try writer.read { db in
            try UserGoalRow.filter(Column("user_id") == userId).fetchOne(db)
        }
    }

    /// Change one or more preferences and queue the row.
    ///
    /// ── IT WRITES BOTH SPELLINGS, ON PURPOSE ────────────────────────────────
    /// `active_plan` AND `active_program`, `active_phase` AND `goal_preset`. The
    /// legacy columns are still read — by the macro presets, and by anything on
    /// the web that has not been retired yet — and leaving them holding a stale
    /// value is precisely how `active_program` came to name a plan that no
    /// longer exists. They stop being written when the readers are deleted in
    /// Wave 9, not before.
    ///
    /// The mutation and the queue item land in one transaction, so a preference
    /// cannot be set locally and then never leave the device.
    @discardableResult
    func updatePreferences(
        userId: String, now: Date = Date(), _ change: @Sendable (inout Preferences) -> Void
    ) throws -> Preferences {
        try writer.write { db in
            var row = try UserGoalRow.filter(Column("user_id") == userId).fetchOne(db)
                ?? UserGoalRow(
                    id: newOnyxID(), userId: userId, contextMode: "normal",
                    createdAt: now, updatedAt: Self.localWriteTimestamp,
                    autoLogSupplements: false,
                    activeProgram: "", dayCutoffHour: 0, unitSystem: "metric",
                    reduceMotion: false, timezone: TimeZone.current.identifier, trackRpe: true
                )

            var prefs = Preferences(row)
            change(&prefs)

            row.unitSystem = prefs.unitSystem
            row.reduceMotion = prefs.reduceMotion
            row.trackRpe = prefs.trackRpe
            row.weekEndDay = prefs.weekEndDay
            row.dayCutoffHour = prefs.dayCutoffHour
            row.timezone = prefs.timezone
            if let plan = prefs.activePlan {
                row.activePlan = plan
                row.activeProgram = plan
            }
            if let phase = prefs.activePhase {
                row.activePhase = phase
                row.goalPreset = phase
            }

            try row.save(db)
            try Self.enqueueRowUpsert(table: UserGoalRow.databaseTableName, id: row.id, in: db)
            return prefs
        }
    }
}
