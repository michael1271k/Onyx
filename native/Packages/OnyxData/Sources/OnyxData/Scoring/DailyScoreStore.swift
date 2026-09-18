import Foundation
import GRDB
import OnyxCore

/// The five component scores plus the total, as `daily_scores` holds them.
///
/// The arithmetic that produces them is `lib/scoring/score.ts` — 443 loc, the
/// largest un-vectored surface in the map and Track D's item 1. It is NOT
/// ported here and must not be: this package owns where a score is stored and
/// when it may be rewritten; it does not own what a score is. Re-deriving it in
/// the sync layer would be a second implementation of the one number the whole
/// app is about.
public struct ScoreComponents: Sendable, Equatable {
    public var total: Int
    public var sleep: Int?
    public var nutrition: Int?
    public var activity: Int?
    public var workout: Int?
    public var recovery: Int?

    public init(
        total: Int, sleep: Int? = nil, nutrition: Int? = nil,
        activity: Int? = nil, workout: Int? = nil, recovery: Int? = nil
    ) {
        self.total = total
        self.sleep = sleep
        self.nutrition = nutrition
        self.activity = activity
        self.workout = workout
        self.recovery = recovery
    }
}

public extension AppDatabase {

    /// The oldest day this user has a stored score for — where a whole-history
    /// cascade starts. nil when nothing has been scored.
    func earliestScoredDate(userId: String) throws -> String? {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT MIN(date) FROM daily_scores WHERE user_id = ?", arguments: [userId])
        }
    }

    /// `bedtimeOffsets` for a caller outside the builder's read — the
    /// regularity baseline's input, newest first.
    func bedtimeOffsets(userId: String, before date: String, limit: Int = 14) throws -> [Double] {
        try writer.read { try Self.bedtimeOffsets($0, userId: userId, before: date, limit: limit) }
    }

    /// Compute and store one day's score.
    ///
    /// ── THE FREEZE ──────────────────────────────────────────────────────────
    /// A past day is SEALED the first time it is computed after its own
    /// midnight. Today accumulates and is recomputed on every call; a past day
    /// whose row is already `finalized` is immutable, so re-ingesting old data
    /// can never rewrite a snapshot. `force` — an explicit edit or delete of
    /// that day's data — bypasses it, which is the only way a correction reaches
    /// a sealed day.
    ///
    /// ── AND WHY `computed_at` IS WRITTEN EXPLICITLY ─────────────────────────
    /// The column defaults to `now()` on INSERT and there is no update trigger
    /// for it, so on the upsert-UPDATE path it kept the timestamp of the very
    /// first computation. A column named "computed at" that really meant "first
    /// computed at" made every staleness check — the widget's especially — see
    /// every row as ancient forever.
    ///
    /// `components` is a closure rather than a stored dependency because there
    /// is exactly one implementation of it in the whole app and it lives in
    /// another package. See `ScoreComponents`.
    @discardableResult
    func writeDailyScore(
        userId: String,
        date: String,
        inputs: ScoringInputs,
        hoursAwake: Double,
        isToday: Bool,
        force: Bool = false,
        now: Date = Date(),
        components: (ScoringInputs) -> ScoreComponents?
    ) throws -> DailyScoreRow? {
        if !isToday && !force,
           let existing = try dailyScore(userId: userId, date: date), existing.finalized {
            return nil
        }
        // No underlying data at all leaves the day BLANK rather than writing a
        // fake zero. A zero is a claim that the day was bad; an absent row is
        // the truth, which is that nothing is known about it.
        guard let parts = components(inputs) else { return nil }
        let battery = Battery.computeBattery(inputs, hoursAwake: hoursAwake)

        return try writer.write { db in
            var row = try DailyScoreRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .fetchOne(db)
                ?? DailyScoreRow(
                    id: newOnyxID(), userId: userId, date: date,
                    score: parts.total, computedAt: now, finalized: !isToday
                )
            row.score = parts.total
            row.sleepScore = parts.sleep
            row.nutritionScore = parts.nutrition
            row.activityScore = parts.activity
            row.workoutScore = parts.workout
            row.recoveryScore = parts.recovery
            row.batteryPct = Int(battery.currentPct.rounded())
            row.computedAt = now
            // Past days are sealed on this write; today stays live.
            row.finalized = !isToday
            try row.save(db)
            try Self.enqueueRowUpsert(table: DailyScoreRow.databaseTableName, id: row.id, in: db)
            return row
        }
    }

    func dailyScore(userId: String, date: String) throws -> DailyScoreRow? {
        try writer.read { db in
            try DailyScoreRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .fetchOne(db)
        }
    }
}
