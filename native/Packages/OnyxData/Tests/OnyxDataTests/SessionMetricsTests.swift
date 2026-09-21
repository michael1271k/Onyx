import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// A watch that recorded some workouts, with a flat heart rate and energy rate.
private struct Watch: HealthReading {
    var isAvailable = true
    var workouts: [WorkoutSample] = []
    var bpm: Double? = 132.4
    var kcalPerMinute: Double = 8
    func requestAuthorization(read: [String]) async throws -> Bool { true }
    func quantity(_ identifier: String, reduce: HealthReduce, start: Date, end: Date) async throws -> Double? {
        switch identifier {
        case "HKQuantityTypeIdentifierHeartRate": return bpm
        case "HKQuantityTypeIdentifierActiveEnergyBurned": return kcalPerMinute * end.timeIntervalSince(start) / 60
        default: return nil
        }
    }
    func sleepSamples(start: Date, end: Date) async throws -> [SleepSample] { [] }
    func workouts(start: Date, end: Date) async throws -> [WorkoutSample] {
        workouts.filter { $0.end >= start && $0.start <= end }
    }
}

@Suite("Session metrics: measured from the watch, estimated without it")
struct SessionMetricsTests {

    private let user = "u1"
    private let now = Date(timeIntervalSince1970: 1_788_530_400)   // 2026-09-04 14:00 UTC
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    /// A finished 60-minute legs session `daysAgo` days back, at 09:00.
    @discardableResult
    private func seed(
        _ db: AppDatabase, id: String, daysAgo: Int, minutes: Double = 60, dayKey: String = "legs_a",
        avgBpm: Int? = nil, kcal: Int? = nil, bpmEstimated: Bool = false, kcalEstimated: Bool = false
    ) throws -> WorkoutSession {
        let start = calendar.date(byAdding: .day, value: -daysAgo, to: now)!.addingTimeInterval(-5 * 3600)
        let session = WorkoutSession(
            id: id, userId: user, dayKey: dayKey, date: LogicalDayISO.string(start, calendar: calendar),
            startedAt: start, endedAt: start.addingTimeInterval(minutes * 60), durationMin: minutes,
            avgBpm: avgBpm, caloriesBurned: kcal, avgBpmEstimated: bpmEstimated, caloriesEstimated: kcalEstimated
        )
        try db.writer.write { conn in try session.insert(conn) }
        return session
    }

    /// The app's own bundle id, as the test names it. A double's workout with
    /// no `sourceBundleId` is FOREIGN (W5) — so every "the watch's own
    /// workout" case below says whose it is.
    private static let own = "app.onyx.test"
    private func ownWorkout(_ s: WorkoutSession, startOffset: TimeInterval = 0, endOffset: TimeInterval = 0) -> WorkoutSample {
        .init(start: s.startedAt!.addingTimeInterval(startOffset), end: s.endedAt!.addingTimeInterval(endOffset),
              isLifting: true, sourceBundleId: Self.own, sourceName: "Onyx")
    }
    private func hevyWorkout(_ s: WorkoutSession) -> WorkoutSample {
        .init(start: s.startedAt!, end: s.endedAt!, isLifting: true, sourceBundleId: "com.hevy.app", sourceName: "Hevy")
    }

    private func sync(_ db: AppDatabase, _ reader: any HealthReading) async throws -> Int {
        try await HealthSync(database: db, reader: reader, userId: user, ownBundleId: Self.own)
            .syncSessionMetrics(now: now, calendar: calendar)
    }

    @Test("a lifting workout overlapping the session gives measured figures, flagged as such, and queues the push")
    func measured() async throws {
        let db = try store()
        let s = try seed(db, id: "s1", daysAgo: 1)
        // The watch was started three minutes late and stopped two early.
        let watch = Watch(workouts: [ownWorkout(s, startOffset: 180, endOffset: -120)])
        #expect(try await sync(db, watch) == 1)

        let row = try #require(try db.session(id: "s1"))
        #expect(row.avgBpm == 132)
        #expect(row.caloriesBurned == 440, "8 kcal/min over the WATCH's 55 minutes")
        #expect(row.avgBpmEstimated == false)
        #expect(row.caloriesEstimated == false)
        #expect(try db.pendingOutbox().contains { $0.kind == SyncKind.sessionUpsert })

        // Nothing left to learn: a second pass touches nothing.
        #expect(try await sync(db, watch) == 0)
    }

    @Test("a run or a walk in the same window is not the session")
    func nonLiftingWorkoutIgnored() async throws {
        let db = try store()
        let s = try seed(db, id: "s1", daysAgo: 1)
        var run = ownWorkout(s); run.isLifting = false
        let watch = Watch(workouts: [run])
        _ = try await sync(db, watch)
        let row = try #require(try db.session(id: "s1"))
        #expect(row.avgBpm == nil, "no measurement, and nothing to carry forward")
        #expect(row.caloriesBurned == nil, "no samples and no bodyweight: neither rule can fire")
    }

    // ── W5: provenance ──────────────────────────────────────────────────────

    @Test("a Hevy workout overlapping the session is never adopted as the measurement")
    func foreignWorkoutNotAdopted() async throws {
        let db = try store()
        let s = try seed(db, id: "s1", daysAgo: 1)
        // Only Hevy's record overlaps. Before W5 this was `.first(where:
        // \.isLifting)` and Hevy's 132 bpm landed here stamped measured.
        _ = try await sync(db, Watch(workouts: [hevyWorkout(s)]))
        let row = try #require(try db.session(id: "s1"))
        #expect(row.avgBpm == nil, "no own workout, no measured heart rate")
        #expect(row.caloriesBurned == nil, "and no samples to estimate from either")
        #expect(row.avgBpmEstimated == false && row.caloriesEstimated == false)
    }

    @Test("a Hevy workout beside an estimate leaves the estimate standing")
    func foreignWorkoutLeavesEstimate() async throws {
        let db = try store()
        let s = try seed(db, id: "s1", daysAgo: 1, avgBpm: 118, kcal: 400, bpmEstimated: true, kcalEstimated: true)
        #expect(try await sync(db, Watch(workouts: [hevyWorkout(s)])) == 0)
        let row = try #require(try db.session(id: "s1"))
        #expect(row.avgBpm == 118 && row.avgBpmEstimated, "still the estimate, still flagged")
        #expect(row.caloriesBurned == 400 && row.caloriesEstimated)
    }

    @Test("our own workout wins over Hevy's, whichever Health lists first")
    func ownWinsOverForeign() async throws {
        let db = try store()
        let s = try seed(db, id: "s1", daysAgo: 1)
        let watch = Watch(workouts: [hevyWorkout(s), ownWorkout(s, startOffset: 60, endOffset: -60)], bpm: 140)
        #expect(try await sync(db, watch) == 1)
        let row = try #require(try db.session(id: "s1"))
        #expect(row.avgBpm == 140 && row.avgBpmEstimated == false)
        #expect(row.caloriesBurned == 464, "8 kcal/min over OUR workout's 58 minutes, not Hevy's 60")
    }

    @Test("the phone's own estimated energy is not read back as a measurement")
    func estimatedEnergyNotLaundered() async throws {
        let db = try store()
        let s = try seed(db, id: "s1", daysAgo: 1)
        var own = ownWorkout(s); own.energyEstimated = true
        _ = try await sync(db, Watch(workouts: [own]))
        let row = try #require(try db.session(id: "s1"))
        #expect(row.avgBpm == 132 && row.avgBpmEstimated == false, "the rate is still the watch's")
        #expect(row.caloriesBurned == nil, "the energy on that workout is Onyx's own estimate: no samples, no bodyweight, nothing to write")
        #expect(row.caloriesEstimated == false)
    }

    @Test("a workout with no source at all is foreign, never own")
    func unsourcedIsForeign() async throws {
        let db = try store()
        let s = try seed(db, id: "s1", daysAgo: 1)
        _ = try await sync(db, Watch(workouts: [.init(start: s.startedAt!, end: s.endedAt!, isLifting: true)]))
        let row = try #require(try db.session(id: "s1"))
        #expect(row.avgBpm == nil, "a reader that cannot say whose it is does not get to call it ours")
    }

    @Test("without a workout, calories come from the personal median and heart rate from the last measured session")
    func estimatedFromOwnHistory() async throws {
        let db = try store()
        // Five measured legs sessions at 7, 8, 9, 10, 11 kcal/min → median 9.
        for (i, rate) in [7, 8, 9, 10, 11].enumerated() {
            try seed(db, id: "old\(i)", daysAgo: 10 + i, avgBpm: 120 + i, kcal: rate * 60)
        }
        // A measured session of ANOTHER day key must not be a sample.
        try seed(db, id: "upper", daysAgo: 3, dayKey: "upper_a", avgBpm: 150, kcal: 2000)
        // An ESTIMATED legs session must not be a sample either.
        try seed(db, id: "est", daysAgo: 2, avgBpm: 99, kcal: 999, bpmEstimated: true, kcalEstimated: true)
        try seed(db, id: "s1", daysAgo: 1, minutes: 50)

        _ = try await sync(db, Watch(workouts: []))

        let row = try #require(try db.session(id: "s1"))
        #expect(row.caloriesBurned == 450, "9 kcal/min × 50")
        #expect(row.caloriesEstimated)
        #expect(row.avgBpm == 120, "the most recent MEASURED legs session — old0, ten days ago")
        #expect(row.avgBpmEstimated)
    }

    @Test("below five samples the MET formula on bodyweight fills calories")
    func metFallback() async throws {
        let db = try store()
        try await db.writer.write { [now, user] conn in
            try conn.execute(
                sql: """
                    INSERT INTO body_composition (id, user_id, measured_at, date, weight_kg, created_at)
                    VALUES ('b1', ?, ?, '2026-09-01', 75, ?)
                    """,
                arguments: [user, now, now]
            )
        }
        try seed(db, id: "s1", daysAgo: 1, minutes: 60)
        _ = try await sync(db, Watch(workouts: []))
        let row = try #require(try db.session(id: "s1"))
        #expect(row.caloriesBurned == 473, "6.0 × 3.5 × 75 / 200 = 7.875 kcal/min × 60 = 472.5, rounded JavaScript's way")
        #expect(row.caloriesEstimated)
        #expect(row.avgBpm == nil)
    }

    @Test("an estimate is replaced by a measurement; a measurement is never replaced")
    func measurementWins() async throws {
        let db = try store()
        let s = try seed(db, id: "s1", daysAgo: 1, avgBpm: 118, kcal: 400, bpmEstimated: true, kcalEstimated: true)
        let measured = try seed(db, id: "s2", daysAgo: 2, avgBpm: 140, kcal: 600)
        let watch = Watch(workouts: [ownWorkout(s), ownWorkout(measured)], bpm: 131, kcalPerMinute: 10)
        #expect(try await sync(db, watch) == 1, "only the estimated one is a candidate")

        let upgraded = try #require(try db.session(id: "s1"))
        #expect(upgraded.avgBpm == 131 && upgraded.avgBpmEstimated == false)
        #expect(upgraded.caloriesBurned == 600 && upgraded.caloriesEstimated == false)
        let kept = try #require(try db.session(id: "s2"))
        #expect(kept.avgBpm == 140 && kept.caloriesBurned == 600)
    }

    @Test("an unfinished session, or one older than the window, is left alone")
    func windowAndOpenSessions() async throws {
        let db = try store()
        try seed(db, id: "old", daysAgo: 20)
        let open = WorkoutSession(id: "open", userId: user, dayKey: "legs_a", date: "2026-09-04", startedAt: now)
        try await db.writer.write { conn in try open.insert(conn) }
        let watch = Watch(workouts: [.init(start: now.addingTimeInterval(-86_400 * 30), end: now, isLifting: true, sourceBundleId: Self.own)])
        #expect(try await sync(db, watch) == 0)
    }

    @Test("the four columns ride the session wire row both ways")
    func wireRow() throws {
        let db = try store()
        let s = try seed(db, id: "s1", daysAgo: 1, avgBpm: 130, kcal: 500, kcalEstimated: true)
        let out = try SyncTranslation.sessionRow(s, now: now, calendar: calendar)
        let json = try JSONSerialization.jsonObject(with: OnyxJSON.encoder.encode(out)) as? [String: Any]
        #expect(json?["avg_bpm"] as? Int == 130)
        #expect(json?["calories_burned"] as? Int == 500)
        #expect(json?["avg_bpm_estimated"] as? Bool == false)
        #expect(json?["calories_estimated"] as? Bool == true)
        _ = db
    }
}
