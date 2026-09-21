import Foundation
import GRDB
import OnyxCore

/// Average heart rate and active energy for a lifting session.
///
/// ── MEASURED FIRST, ESTIMATED SECOND, STAMPED EITHER WAY ────────────────────
/// An `HKWorkout` overlapping the session is the watch's own record of it, and
/// the heart-rate average and active-energy sum over THAT interval are the
/// measured figures (`*_estimated = false`). Without one, `Estimates` fills
/// the gap from the athlete's own median kcal/min for the same day key, the
/// ACSM MET figure on bodyweight after that, and the last measured heart rate
/// for the same day key — and stamps every one of them `*_estimated = true`.
/// A port of the block in the web app's `lib/sessions/save.ts`, run on the device
/// instead of at save time, because the watch's workout can arrive after the
/// session was finished here.
///
/// A measured value is never overwritten; an estimated one is replaced by a
/// measurement the moment one exists. Sessions are revisited for
/// `lookbackDays` so a workout that syncs from the watch a day late still
/// lands.
///
/// ── AND ONLY OUR OWN WORKOUT IS A MEASUREMENT (Expansion W5) ────────────────
/// The overlapping workout used to be whichever lifting `HKWorkout` came first,
/// and Hevy writes one of the same type over the same hour — so a Hevy log was
/// adopted as the watch's measurement of the session, silently, for as long as
/// both apps were in use. `HealthReading.liftingOverlap` classifies by source:
/// our own workout (phone or watch) is measured; a foreign one is `.foreign`
/// and falls through to the estimate exactly as if no workout existed. The
/// compare card is what offers its numbers, and only on a tap (decision 7).
public extension HealthSync {

    /// Fill or upgrade the metrics of every session that ended in the window.
    /// Returns how many rows were written.
    @discardableResult
    func syncSessionMetrics(
        now: Date = Date(), calendar: Calendar = .current, lookbackDays: Int = 14
    ) async throws -> Int {
        let since = calendar.date(byAdding: .day, value: -lookbackDays, to: now) ?? now
        let candidates = try database.sessionsNeedingMetrics(userId: userId, endedAfter: since)
        var written = 0
        for session in candidates {
            guard let start = session.startedAt, let end = session.endedAt else { continue }

            var measuredBpm: Int?
            var measuredKcal: Int?
            if reader.isAvailable,
               let workout = await reader.liftingOverlap(start: start, end: end, ownBundleId: ownBundleId).own {
                let bpm = try? await reader.quantity(
                    "HKQuantityTypeIdentifierHeartRate", reduce: .average, start: workout.start, end: workout.end
                )
                // ── AN ESTIMATE IN HEALTH IS STILL AN ESTIMATE ──────────────
                // The phone's writer puts `Estimates`' kcal on its own workout
                // for the rings, flagged `energyEstimated`. Read back as a
                // measurement it would stamp itself `calories_estimated =
                // false` and become a sample the next estimate is drawn from.
                let kcal: Double? = workout.energyEstimated ? nil : try? await reader.quantity(
                    "HKQuantityTypeIdentifierActiveEnergyBurned", reduce: .sum, start: workout.start, end: workout.end
                )
                measuredBpm = Self.whole(bpm)
                measuredKcal = Self.whole(kcal)
            }

            var next = session
            if let measuredBpm {
                next.avgBpm = measuredBpm
                next.avgBpmEstimated = false
            } else if session.avgBpm == nil,
                      let bpm = Estimates.estimateAvgBpm(previousBpm: try database.lastMeasuredBpm(before: session)) {
                next.avgBpm = Self.whole(bpm)
                next.avgBpmEstimated = true
            }
            if let measuredKcal {
                next.caloriesBurned = measuredKcal
                next.caloriesEstimated = false
            } else if session.caloriesBurned == nil,
                      let estimate = Estimates.estimateCalories(
                        durationMin: session.durationMin,
                        samples: try database.kcalSamples(before: session, calendar: calendar),
                        bodyweightKg: try database.bodyweight(onOrBefore: session.date, userId: session.userId)
                      ) {
                next.caloriesBurned = Self.whole(estimate.kcal)
                next.caloriesEstimated = true
            }

            guard next != session else { continue }
            try Task.checkCancellation()
            try database.updateSessionMetrics(next)
            written += 1
        }
        return written
    }

    /// `Math.round`, then an `Int` that cannot trap. Nil for a non-positive
    /// reading — a zero heart rate is a missing one.
    private static func whole(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return Int(exactly: jsRound(value))
    }
}

// MARK: - The store's half

extension AppDatabase {

    /// Finished sessions in the window whose metrics are absent or estimated.
    /// A session with both figures measured has nothing left to learn.
    func sessionsNeedingMetrics(userId: String, endedAfter since: Date) throws -> [WorkoutSession] {
        try writer.read { db in
            try WorkoutSession
                .filter(Column("user_id") == userId)
                .filter(Column("ended_at") != nil && Column("ended_at") >= since)
                .filter(
                    Column("avg_bpm") == nil || Column("avg_bpm_estimated") == true
                        || Column("calories_burned") == nil || Column("calories_estimated") == true
                )
                .order(Column("started_at"))
                .fetchAll(db)
        }
    }

    /// Measured kcal/duration pairs from the last 40 sessions of the same day
    /// key inside `Estimates.kcalSampleWindowDays`. Same split, recent, and
    /// MEASURED — an estimate must never become the sample that justifies the
    /// next estimate.
    func kcalSamples(before session: WorkoutSession, calendar: Calendar) throws -> [KcalSample] {
        guard let dayKey = session.dayKey, let start = session.startedAt else { return [] }
        let from = calendar.date(byAdding: .day, value: -Estimates.kcalSampleWindowDays, to: start) ?? start
        return try writer.read { db in
            try WorkoutSession
                .filter(Column("user_id") == session.userId)
                .filter(Column("day_key") == dayKey)
                .filter(Column("started_at") < start && Column("started_at") >= from)
                .filter(Column("calories_estimated") == false)
                .filter(Column("calories_burned") != nil && Column("duration_min") != nil)
                .order(Column("started_at").desc)
                .limit(40)
                .fetchAll(db)
                .compactMap { row in
                    guard let kcal = row.caloriesBurned, let minutes = row.durationMin else { return nil }
                    return KcalSample(kcal: Double(kcal), durationMin: minutes)
                }
        }
    }

    /// The last MEASURED average heart rate for the same day key, if any.
    func lastMeasuredBpm(before session: WorkoutSession) throws -> Double? {
        guard let dayKey = session.dayKey, let start = session.startedAt else { return nil }
        return try writer.read { db in
            try WorkoutSession
                .filter(Column("user_id") == session.userId)
                .filter(Column("day_key") == dayKey)
                .filter(Column("started_at") < start)
                .filter(Column("avg_bpm_estimated") == false && Column("avg_bpm") != nil)
                .order(Column("started_at").desc)
                .fetchOne(db)?
                .avgBpm
                .map(Double.init)
        }
    }

    /// The most recent scale reading on or before a date.
    ///
    /// The MET fallback's, originally, and now also the weekly wrap's: the same
    /// question — "what did the scale last say by this day" — asked by two
    /// callers, one of which lives in the app target and needs it public.
    public func bodyweight(onOrBefore date: String, userId: String) throws -> Double? {
        try writer.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT weight_kg FROM body_composition WHERE user_id = ? AND date <= ? ORDER BY date DESC LIMIT 1",
                arguments: [userId, date]
            )
        }
    }

    /// Write the four metric columns and queue the session for push.
    func updateSessionMetrics(_ session: WorkoutSession) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    UPDATE workout_sessions
                       SET avg_bpm = ?, calories_burned = ?, avg_bpm_estimated = ?, calories_estimated = ?
                     WHERE id = ?
                    """,
                arguments: [
                    session.avgBpm, session.caloriesBurned,
                    session.avgBpmEstimated, session.caloriesEstimated, session.id,
                ]
            )
            try Self.enqueueSessionUpsert(sessionId: session.id, in: db)
        }
    }
}
