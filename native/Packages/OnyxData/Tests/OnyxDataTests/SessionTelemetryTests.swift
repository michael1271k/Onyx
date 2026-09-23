import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// Expansion W5 — the heart-rate cache, the late window, and the phone's
// HKWorkout guard. A fake reader counts its reads; a real in-memory store
// holds the cache row.
// ─────────────────────────────────────────────────────────────────────────────

/// A Health store that answers with a scripted series and counts the asks.
private final class ScriptedHealth: HealthReading, @unchecked Sendable {
    var isAvailable = true
    var series: [HRSample] = []
    var workouts: [WorkoutSample] = []
    var activeKcal: Double?
    /// Apple's one-minute recovery sample, where it STARTS and what it says.
    var recovery: (at: Date, bpm: Double)?
    /// Ticks the observer stream yields; each one lets the actor re-read.
    var changes = 0
    /// What the store holds AFTER the first tick — the watch's samples
    /// landing during the late window.
    var arrivesOnChange: [HRSample]?
    private let lock = NSLock()
    private(set) var seriesReads = 0

    init(series: [HRSample] = []) { self.series = series }

    func requestAuthorization(read: [String]) async throws -> Bool { true }
    func quantity(_ identifier: String, reduce: HealthReduce, start: Date, end: Date) async throws -> Double? {
        if identifier == HealthCatalogue.heartRateRecoveryIdentifier {
            // `.strictStartDate`, as the real statistics query.
            return recovery.flatMap { $0.at >= start && $0.at < end ? $0.bpm : nil }
        }
        return identifier == "HKQuantityTypeIdentifierActiveEnergyBurned" ? activeKcal : nil
    }
    func sleepSamples(start: Date, end: Date) async throws -> [SleepSample] { [] }
    func workouts(start: Date, end: Date) async throws -> [WorkoutSample] {
        workouts.filter { $0.end >= start && $0.start <= end }
    }
    func heartRateSeries(start: Date, end: Date) async throws -> [HRSample] {
        lock.withLock { seriesReads += 1 }
        return series.filter { $0.at >= start && $0.at <= end }
    }
    func heartRateChanges(until: Date) -> AsyncStream<Void> {
        let n = changes
        if let late = arrivesOnChange { series = late }
        return AsyncStream { continuation in
            for _ in 0..<n { continuation.yield() }
            continuation.finish()
        }
    }
}

@Suite("Session telemetry — read at view time, cached after the first non-empty read")
struct SessionTelemetryTests {

    private static let own = "app.onyx.test"
    private let user = "u1"
    private let start = Date(timeIntervalSince1970: 1_788_530_400)   // 2026-09-04 14:00 UTC

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "phone") }

    /// A finished 30-minute session with two movements and a pause, all
    /// stamped by THIS device, so the timeline is: A commits at +5 and +10,
    /// pause +12 → +14, B commits at +20 and +25.
    private func seed(_ db: AppDatabase, id: String = "s1") throws -> WorkoutSession {
        let session = WorkoutSession(
            id: id, userId: user, dayKey: "upper_a", date: "2026-09-04",
            startedAt: start, endedAt: start.addingTimeInterval(30 * 60), durationMin: 28
        )
        try db.writer.write { conn in
            try session.insert(conn)
            try Exercise(id: "ex-a", name: "Chest Press").insert(conn)
            try Exercise(id: "ex-b", name: "Lat Pulldown").insert(conn)
        }
        let events: [(SetEvent.Body, TimeInterval)] = [
            (.append(.init(exerciseId: "ex-a", setIndex: 1, weightKg: 40, reps: 10)), 5 * 60),
            (.append(.init(exerciseId: "ex-a", setIndex: 2, weightKg: 40, reps: 10)), 10 * 60),
            (.pause, 12 * 60), (.resume, 14 * 60),
            (.append(.init(exerciseId: "ex-b", setIndex: 1, weightKg: 50, reps: 10)), 20 * 60),
            (.append(.init(exerciseId: "ex-b", setIndex: 2, weightKg: 50, reps: 10)), 25 * 60),
        ]
        try db.writer.write { conn in
            for (i, (body, offset)) in events.enumerated() {
                let setId: String
                if case .append = body { setId = "set-\(i)" } else { setId = id }
                try SetEvent(
                    id: "ev-\(i)", sessionId: id, setId: setId, deviceId: "phone", seq: Int64(i + 1),
                    createdAt: start.addingTimeInterval(offset), body: body
                ).insert(conn)
            }
        }
        return session
    }

    /// One sample a minute, rising through the session.
    private var series: [HRSample] {
        (0..<30).map { HRSample(at: start.addingTimeInterval(Double($0) * 60), bpm: 100 + $0) }
    }

    // MARK: App Store W6 — Apple's one-minute recovery

    @Test("the recovery Apple wrote a minute after the finish is read, and read again on a cached open")
    func recoveryAfterFinish() async throws {
        let db = try store()
        let session = try seed(db)
        let end = try #require(session.endedAt)
        let health = ScriptedHealth(series: series)
        health.recovery = (end.addingTimeInterval(60), 27.6)
        let telemetry = SessionTelemetry(database: db, reader: health, ownBundleId: Self.own)

        #expect(await telemetry.recoveryBpm(sessionId: "s1") == 28)
        // The series caches; the recovery never does — Apple may write it
        // after the first open — and the cached series does not wait for it.
        _ = await telemetry.reading(sessionId: "s1")
        #expect(try #require(await telemetry.reading(sessionId: "s1")).cached)
        #expect(await telemetry.recoveryBpm(sessionId: "s1") == 28)
    }

    @Test("a recovery outside the session's ten minutes is another workout's, and a live session has none")
    func recoveryWindow() async throws {
        let db = try store()
        let session = try seed(db)
        let end = try #require(session.endedAt)
        let health = ScriptedHealth(series: series)
        // A run finished twenty minutes later wrote its own.
        health.recovery = (end.addingTimeInterval(20 * 60), 31)
        let telemetry = SessionTelemetry(database: db, reader: health, ownBundleId: Self.own)
        #expect(await telemetry.recoveryBpm(sessionId: "s1") == nil)

        try await db.writer.write { conn in
            try WorkoutSession(id: "live", userId: user, dayKey: "upper_a", date: "2026-09-04", startedAt: start).insert(conn)
        }
        health.recovery = (Date().addingTimeInterval(30), 31)
        #expect(await telemetry.recoveryBpm(sessionId: "live") == nil)
    }

    @Test("the first read comes from Health, is segmented by the log, and lands in the cache")
    func firstReadCaches() async throws {
        let db = try store()
        try seed(db)
        let health = ScriptedHealth(series: series)
        let telemetry = SessionTelemetry(database: db, reader: health, ownBundleId: Self.own)

        let first = try #require(await telemetry.reading(sessionId: "s1"))
        #expect(first.cached == false)
        #expect(first.samples.count == 30)
        // A [0,10), B [10,12) then B [14,25): the pause splits the second.
        #expect(first.segments.map(\.exerciseId) == ["ex-a", "ex-b", "ex-b"])
        #expect(first.segments.map(\.continues) == [false, false, true])
        #expect(first.segments[0].avgBpm == 105, "100…109 over the first ten minutes: mean 104.5, Math.round → 105")
        #expect(first.maxBpm == 129)
        #expect(first.avgBpm != nil)
        #expect(health.seriesReads == 1)

        let row = try #require(try db.telemetryCache(sessionId: "s1"))
        #expect(row.samples?.count == 30)
        #expect(row.segments?.count == 3)
        #expect(row.source == "health")
    }

    @Test("a closed session's row takes the series' mean as measured — over a blank or an estimate, never over a measurement")
    func rowLearnsAverage() async throws {
        let db = try store()
        try seed(db)
        let telemetry = SessionTelemetry(database: db, reader: ScriptedHealth(series: series), ownBundleId: Self.own)
        let first = try #require(await telemetry.reading(sessionId: "s1"))
        let row = try #require(try await db.writer.read { try WorkoutSession.fetchOne($0, key: "s1") })
        #expect(row.avgBpm == first.avgBpm && row.avgBpm != nil)
        #expect(row.avgBpmEstimated == false)

        // A measured figure already on the row stands.
        let db2 = try store()
        var s2 = try seed(db2, id: "s2")
        s2.avgBpm = 150; s2.avgBpmEstimated = false
        try await db2.writer.write { [s2] conn in try s2.update(conn) }
        _ = await SessionTelemetry(database: db2, reader: ScriptedHealth(series: series), ownBundleId: Self.own).reading(sessionId: "s2")
        let kept = try #require(try await db2.writer.read { try WorkoutSession.fetchOne($0, key: "s2") })
        #expect(kept.avgBpm == 150)
    }

    @Test("the second read is the cache and Health is not asked again")
    func secondReadIsCacheHit() async throws {
        let db = try store()
        try seed(db)
        let health = ScriptedHealth(series: series)
        let telemetry = SessionTelemetry(database: db, reader: health, ownBundleId: Self.own)
        _ = await telemetry.reading(sessionId: "s1")
        let second = try #require(await telemetry.reading(sessionId: "s1"))
        #expect(second.cached)
        #expect(second.samples.count == 30)
        #expect(second.segments.count == 3)
        #expect(health.seriesReads == 1, "one read, ever")
    }

    @Test("an empty read is returned and NOT cached, so the next open asks again")
    func emptyReadNotCached() async throws {
        let db = try store()
        try seed(db)
        let health = ScriptedHealth(series: [])
        let telemetry = SessionTelemetry(database: db, reader: health, ownBundleId: Self.own)
        let first = try #require(await telemetry.reading(sessionId: "s1"))
        #expect(first.isEmpty && first.cached == false)
        #expect(try db.telemetryCache(sessionId: "s1") == nil)
        _ = await telemetry.reading(sessionId: "s1")
        #expect(health.seriesReads == 2)
    }

    @Test("prefetch keeps listening through the late window and caches when the watch's samples land")
    func prefetchLateArrival() async throws {
        let db = try store()
        try seed(db)
        let health = ScriptedHealth(series: [])
        health.changes = 3
        let telemetry = SessionTelemetry(database: db, reader: health, ownBundleId: Self.own)
        let landed = LateFlag()
        await telemetry.setOnLateArrival { id in landed.set(id) }
        // The samples arrive AFTER the first (empty) read, with the first tick.
        health.arrivesOnChange = series
        await telemetry.prefetch(sessionId: "s1", finishedAt: start.addingTimeInterval(30 * 60))
        #expect(try db.telemetryCache(sessionId: "s1")?.samples?.count == 30)
        #expect(landed.value == "s1")
        #expect(health.seriesReads == 2, "the empty first read, then exactly one refetch")
    }

    @Test("a LIVE session reads up to now and is never cached; an unknown one is nil")
    func liveReadsToNow() async throws {
        let db = try store()
        // Started a minute ago, not closed: the finish sheet's case.
        let open = WorkoutSession(id: "open", userId: user, dayKey: "upper_a", date: "2026-09-04",
                                  startedAt: Date().addingTimeInterval(-60))
        try await db.writer.write { conn in try open.insert(conn) }
        let live = [HRSample(at: Date().addingTimeInterval(-30), bpm: 120)]
        let telemetry = SessionTelemetry(database: db, reader: ScriptedHealth(series: live), ownBundleId: Self.own)
        let reading = try #require(await telemetry.reading(sessionId: "open"))
        #expect(reading.samples.count == 1 && reading.cached == false)
        #expect(try db.telemetryCache(sessionId: "open") == nil, "nothing about a live session is final")
        #expect(await telemetry.reading(sessionId: "nope") == nil)
    }

    @Test("the Hevy decision lives on the same row and does not count as a cached series")
    func hevyDecision() async throws {
        let db = try store()
        try seed(db)
        let health = ScriptedHealth(series: series)
        let telemetry = SessionTelemetry(database: db, reader: health, ownBundleId: Self.own)
        #expect(await telemetry.hevyDecision(sessionId: "s1") == nil)
        await telemetry.setHevyDecision(sessionId: "s1", .skip)
        #expect(await telemetry.hevyDecision(sessionId: "s1") == .skip)
        // The row exists with a null series: still a miss.
        let read = try #require(await telemetry.reading(sessionId: "s1"))
        #expect(read.cached == false && health.seriesReads == 1)
        // And caching the series keeps the decision.
        #expect(await telemetry.hevyDecision(sessionId: "s1") == .skip)
        await telemetry.setHevyDecision(sessionId: "s1", .use)
        #expect(await telemetry.hevyDecision(sessionId: "s1") == .use)
        #expect(try db.telemetryCache(sessionId: "s1")?.samples?.count == 30, "the decision write did not clear the series")
    }

    @Test("the cache row dies with its session")
    func cascadesWithSession() async throws {
        let db = try store()
        try seed(db)
        let telemetry = SessionTelemetry(database: db, reader: ScriptedHealth(series: series), ownBundleId: Self.own)
        _ = await telemetry.reading(sessionId: "s1")
        _ = try await db.writer.write { try WorkoutSession.deleteOne($0, key: "s1") }
        #expect(try db.telemetryCache(sessionId: "s1") == nil)
    }
}

/// A Sendable box for the late-arrival callback to write into.
private final class LateFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    func set(_ id: String) { lock.lock(); stored = id; lock.unlock() }
    var value: String? { lock.lock(); defer { lock.unlock() }; return stored }
}

// MARK: - The phone's HKWorkout guard

@Suite("WorkoutWriter — the phone writes only when nobody else has")
struct WorkoutWriterTests {

    private static let own = "app.onyx.test"
    private let start = Date(timeIntervalSince1970: 1_788_530_400)

    private func session(kcal: Int? = 420, estimated: Bool = true) -> WorkoutSession {
        WorkoutSession(
            id: "s1", userId: "u1", dayKey: "upper_a", date: "2026-09-04",
            startedAt: start, endedAt: start.addingTimeInterval(3600), durationMin: 60,
            caloriesBurned: kcal, caloriesEstimated: estimated
        )
    }

    private func event(device: String) -> SetEvent {
        SetEvent(sessionId: "s1", setId: "x", deviceId: device, seq: 1, createdAt: start,
                 body: .append(.init(exerciseId: "ex-a", setIndex: 1, weightKg: 40, reps: 10)))
    }

    private func decide(
        _ s: WorkoutSession, events: [SetEvent] = [], health: ScriptedHealth = ScriptedHealth()
    ) async -> WorkoutWriter.Decision {
        await WorkoutWriter.decide(session: s, events: events, localDeviceId: "phone", reader: health, ownBundleId: Self.own)
    }

    @Test("a phone-only session with nothing in Health writes its estimate, flagged")
    func writesEstimate() async {
        let d = await decide(session(), events: [event(device: "phone")])
        #expect(d == .write(energyKcal: 420, estimated: true))
    }

    @Test("a typed figure is written as the athlete's own")
    func writesUserEntered() async {
        let d = await decide(session(kcal: 500, estimated: false))
        #expect(d == .write(energyKcal: 500, estimated: false))
    }

    @Test("energy already in Health for the interval is not written twice")
    func energyAlreadyThere() async {
        let health = ScriptedHealth()
        health.activeKcal = 310
        let d = await decide(session(), health: health)
        #expect(d == .write(energyKcal: nil, estimated: false))
    }

    @Test("an event from another device means the watch ran the session: skip")
    func watchRan() async {
        let d = await decide(session(), events: [event(device: "phone"), event(device: "watch")])
        #expect(d == .skip(.watchRan))
    }

    @Test("a heart rate received from the wrist during the session means the watch ran it: skip")
    func watchWasLive() async {
        let d = await WorkoutWriter.decide(
            session: session(), events: [event(device: "phone")], localDeviceId: "phone",
            watchWasLive: true, reader: ScriptedHealth(), ownBundleId: Self.own
        )
        #expect(d == .skip(.watchRan))
    }

    @Test("our own workout already overlapping: skip")
    func ownExists() async {
        let health = ScriptedHealth()
        health.workouts = [.init(start: start, end: start.addingTimeInterval(3600), isLifting: true, sourceBundleId: Self.own)]
        let d = await decide(session(), health: health)
        #expect(d == .skip(.ownWorkoutExists))
    }

    @Test("a foreign strength workout overlapping: skip (decision 8)")
    func foreignOverlap() async {
        let health = ScriptedHealth()
        health.workouts = [.init(start: start.addingTimeInterval(300), end: start.addingTimeInterval(4000), isLifting: true,
                                 sourceBundleId: "com.hevy.app", sourceName: "Hevy")]
        let d = await decide(session(), health: health)
        #expect(d == .skip(.foreignOverlap))
    }

    @Test("a foreign CARDIO bout in the window is not an overlap")
    func foreignCardioIgnored() async {
        let health = ScriptedHealth()
        health.workouts = [.init(start: start, end: start.addingTimeInterval(1200), isLifting: false,
                                 sourceBundleId: "com.strava", sourceName: "Strava")]
        let d = await decide(session(), health: health)
        #expect(d == .write(energyKcal: 420, estimated: true))
    }

    @Test("no interval, nothing to write")
    func noInterval() async {
        var s = session(); s.endedAt = nil
        #expect(await decide(s) == .skip(.noInterval))
    }
}
