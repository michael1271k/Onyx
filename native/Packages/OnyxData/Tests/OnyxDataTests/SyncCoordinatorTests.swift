import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// A remote that remembers the ORDER it was spoken to. Every fake here is one
/// actor so the sequence of push and pull is one list, not three.
private actor Wire: SyncRemote, MirrorPushRemote, MirrorRemote {
    var log: [String] = []
    var rows: [String: [[String: Any]]] = [:]
    var failure: (any Error)?
    var pullFailures: Set<String> = []
    /// While true every pull waits, so a test can line callers up behind one run.
    var held = false

    /// Set the first time a pull actually reaches the hold.
    ///
    /// `stopAbandons` used to sleep 30 ms and assume the run had parked itself
    /// on the wire by then. Under the full suite — forty suites in parallel on
    /// a machine also running xcodebuild — it sometimes had not, `stop()`
    /// landed before there was anything to abandon, and the test failed for
    /// reasons that had nothing to do with the coordinator. Waiting on the
    /// fact instead of on the clock is both faster and true.
    var parked: Set<String> = []

    func hold() { held = true }
    func release() { held = false }

    /// Suspend until a pull of THIS TABLE is parked on the hold.
    ///
    /// Naming the table is what makes the caller deterministic. `refresh` walks
    /// the catalogue in order and `stop()` only bites at the checkpoint after
    /// the group in flight, so "some pull is parked" left the test racing the
    /// scheduler for which group that was — passing when it happened to be
    /// `head`, failing when the run had already sailed into `rest`. Bounded, so
    /// a regression that never reaches the wire FAILS rather than hangs.
    func waitUntilParked(_ table: String) async {
        for _ in 0..<400 {
            if parked.contains(table) { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func put(_ table: String, _ objects: [[String: Any]]) { rows[table] = objects }
    func setFailure(_ error: (any Error)?) { failure = error }
    func failPulls(of tables: Set<String>) { pullFailures = tables }

    // SyncRemote
    func exerciseCatalogue() async throws -> [RemoteExercise] { [] }
    func upsertSessions(_ rows: [RemoteSessionRow], ignoreDuplicates: Bool) async throws { log.append("push:workout_sessions") }
    func upsertSets(_ rows: [RemoteSetRow]) async throws { log.append("push:workout_sets") }
    func deleteSets(ids: [String]) async throws {}

    // MirrorPushRemote
    func upsertRow<T: Encodable & Sendable>(_ row: T, table: String, conflict: String, nulls: [String]) async throws {
        if let failure { throw failure }
        log.append("push:\(table)")
    }
    func deleteRow(table: String, key: [String: String]) async throws {}

    // MirrorRemote
    func select<T: Decodable & Sendable>(_ type: T.Type, request: MirrorRequest) async throws -> [T] {
        if held { parked.insert(request.table) }
        while held { try await Task.sleep(for: .milliseconds(5)) }
        if let failure { throw failure }
        if pullFailures.contains(request.table) { throw Unreachable() }
        log.append("pull:\(request.table)")
        return try decode(rows[request.table] ?? [])
    }
    func selectIn<T: Decodable & Sendable>(_ type: T.Type, table: String, column: String, values: [String]) async throws -> [T] {
        log.append("pull:\(table)")
        return try decode(rows[table] ?? [])
    }
    /// Answered from the same canned table the pulls read, so "server count"
    /// and "what a pull would land" cannot disagree by accident.
    func count(table: String) async throws -> Int {
        if let failure { throw failure }
        if pullFailures.contains(table) { throw Unreachable() }
        return rows[table]?.count ?? 0
    }
    private func decode<T: Decodable>(_ objects: [[String: Any]]) throws -> [T] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([T].self, from: JSONSerialization.data(withJSONObject: objects))
    }
}

private struct Unreachable: Error {}

private struct ScriptedHealth: HealthReading {
    var isAvailable = true
    var steps: Double
    func requestAuthorization(read: [String]) async throws -> Bool { true }
    func quantity(_ identifier: String, reduce: HealthReduce, start: Date, end: Date) async throws -> Double? {
        identifier == "HKQuantityTypeIdentifierStepCount" ? steps : nil
    }
    func sleepSamples(start: Date, end: Date) async throws -> [SleepSample] { [] }
}

/// `.serialized` because two of these tests drive the coordinator through
/// deliberate suspensions — a held wire, a `stop()` timed against a run in
/// flight — and swift-testing otherwise runs them alongside thirty-nine other
/// suites on the same cooperative pool. Under that load the scheduler, not the
/// coordinator, decided which side of a checkpoint `stop()` landed on, and
/// `stopAbandons` failed perhaps two runs in five with nothing wrong. These
/// tests are cheap; the whole suite is well under a second.
@Suite("The sync coordinator", .serialized)
struct SyncCoordinatorTests {

    private let user = "u1"
    /// 2026-09-04 14:00 in the test calendar, so "today" and "yesterday" are
    /// fixed and `hoursAwake` is 7.
    private let now = Date(timeIntervalSince1970: 1_788_530_400)
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    private func coordinator(_ db: AppDatabase, _ wire: Wire, health: HealthSync? = nil) -> SyncCoordinator {
        SyncCoordinator(
            database: db,
            engine: SyncEngine(database: db, remote: wire, rows: wire),
            puller: MirrorPuller(database: db, remote: wire, userId: user, windowDays: nil),
            training: TrainingPuller(database: db, remote: wire, userId: user, windowDays: nil),
            health: health,
            userId: user,
            calendar: calendar,
            now: { [now] in now }
        )
    }

    /// Something for the outbox to push: a plan-phase goal, which is a mirrored
    /// row and goes out through the generic `row.upsert`.
    private func queueOneRow(_ db: AppDatabase) throws {
        try db.editPlanPhaseGoals(userId: user, planId: "onyx5", phase: "cut") { $0.kcal = 1885 }
    }

    // MARK: Order

    @Test("HealthKit is read, then the outbox is pushed, then every table is pulled")
    func order() async throws {
        let db = try store()
        let wire = Wire()
        let health = HealthSync(database: db, reader: ScriptedHealth(steps: 8_000), userId: user)
        try await coordinator(db, wire, health: health).syncNow(reason: .launch)

        let log = await wire.log
        // The health read wrote today's `daily_metrics`, and that write was
        // PUSHED before anything was pulled — the whole point of the order.
        let firstPush = try #require(log.firstIndex { $0.hasPrefix("push:") })
        let firstPull = try #require(log.firstIndex { $0.hasPrefix("pull:") })
        #expect(log[firstPush...].contains("push:daily_metrics"))
        #expect(firstPush < firstPull)
        #expect(log.contains("pull:workout_sessions"))
        #expect(log.contains("pull:exercises"))
        #expect(log.filter { $0.hasPrefix("pull:") }.count == MirrorCatalogue.tables.count + 2)
    }

    @Test("a reservation left by a killed process is returned and drained")
    func resetInFlightThenDrain() async throws {
        let db = try store()
        try queueOneRow(db)
        // Simulate the kill: claim it and never acknowledge.
        let claimed = try db.claimOutbox()
        #expect(claimed.count == 1)
        #expect(try db.pendingOutbox().isEmpty, "in-flight rows are invisible to a drain")

        let wire = Wire()
        try await coordinator(db, wire).syncNow(reason: .foreground)

        #expect(await wire.log.contains("push:plan_phase_goals"))
        #expect(try db.pendingOutbox().isEmpty)
        let left = try await db.writer.read { conn in try OutboxItem.fetchCount(conn) }
        #expect(left == 0, "acknowledged rows leave the queue")
    }

    @Test("the score rows the sync writes are pushed by the same sync")
    func scoreRowsDrain() async throws {
        let db = try store()
        try await db.writer.write { [now, user] conn in
            try DailyMetricRow(id: "m", userId: user, date: "2026-09-04", steps: 9_000, activeCal: nil, restHr: nil,
                               createdAt: now, updatedAt: now).insert(conn)
        }
        let wire = Wire()
        try await coordinator(db, wire).syncNow(reason: .pull)

        #expect(try db.dailyScore(userId: user, date: "2026-09-04") != nil)
        #expect(await wire.log.contains("push:daily_scores"))
        #expect(try db.pendingOutbox().isEmpty)
    }

    // MARK: State and ledger

    @Test("a successful run leaves the ledger stamped per table and the state idle")
    func ledger() async throws {
        let db = try store()
        let wire = Wire()
        let c = coordinator(db, wire)
        try await c.syncNow(reason: .launch)

        #expect(await c.state == .idle)
        let last = try await c.lastSync()
        #expect(last["daily_logs"] == now)
        #expect(last["workout_sessions"] == now)
        #expect(last["outbox"] == now)
        // 26 catalogue tables, sessions + exercises (no sets: nothing to pull them for), the outbox.
        #expect(last.count == MirrorCatalogue.tables.count + 2 + 1)
    }

    @Test("the server counts come back per table, and a table that errors is absent")
    func serverCounts() async throws {
        let db = try store()
        let wire = Wire()
        await wire.put("daily_logs", [[:], [:], [:]])
        await wire.failPulls(of: ["cardio_logs"])

        let counts = await coordinator(db, wire).serverCounts(tables: ["daily_logs", "water_intake", "cardio_logs"])

        #expect(counts["daily_logs"] == 3)
        // Nothing canned for it: the server genuinely holds none.
        #expect(counts["water_intake"] == 0)
        // The Doctor draws "—" for this one, never "0" — a count that could not
        // be taken is not a count of zero, and zero is the alarming answer.
        #expect(counts["cardio_logs"] == nil)
    }

    @Test("the ledger is append-only: a second sync adds rows, and max wins")
    func ledgerAppends() async throws {
        let db = try store()
        try db.recordSync(userId: user, table: "daily_logs", rows: 3, reason: "launch", at: now.addingTimeInterval(-3600))
        let wire = Wire()
        try await coordinator(db, wire).syncNow(reason: .foreground)
        let lines = try await db.writer.read { conn in
            try SyncStatusRow.filter(Column("table_name") == "daily_logs").fetchCount(conn)
        }
        #expect(lines == 2)
        #expect(try db.lastSync(userId: user)["daily_logs"] == now)
        #expect(try db.lastSync(userId: "someone-else").isEmpty)
    }

    @Test("a table that fails to pull fails the sync — after everything else ran")
    func partialFailure() async throws {
        let db = try store()
        try await db.writer.write { [now, user] conn in
            try DailyMetricRow(id: "m", userId: user, date: "2026-09-04", steps: 9_000, createdAt: now, updatedAt: now).insert(conn)
        }
        let wire = Wire()
        await wire.failPulls(of: ["doms_logs"])
        let c = coordinator(db, wire)
        await #expect(throws: SyncCoordinatorError.tablesFailed(["doms_logs": String(describing: Unreachable())])) {
            try await c.syncNow(reason: .launch)
        }
        guard case .failed = await c.state else { Issue.record("state should be failed"); return }
        // The other twenty-five still landed and were stamped.
        let last = try await c.lastSync()
        #expect(last["doms_logs"] == nil)
        #expect(last["daily_logs"] == now)
        // And today's score was still written.
        #expect(try db.dailyScore(userId: user, date: "2026-09-04") != nil)
    }

    @Test("the network being gone stops the run at the push")
    func offline() async throws {
        let db = try store()
        try queueOneRow(db)
        let wire = Wire()
        await wire.setFailure(Unreachable())
        let c = coordinator(db, wire)
        // The drainer swallows a per-row failure into its report; the pulls
        // then throw, which is what surfaces.
        await #expect(throws: (any Error).self) { try await c.syncNow(reason: .pull) }
        guard case .failed = await c.state else { Issue.record("state should be failed"); return }
        #expect(try db.pendingOutbox().isEmpty == false, "the row waits for the next drain")
    }

    // MARK: Coalescing

    @Test("a call while running is queued once; a third joins it")
    func coalesces() async throws {
        let db = try store()
        let wire = Wire()
        let c = coordinator(db, wire)
        await wire.hold()
        // ── THE SECOND CALLER MUST ARRIVE AFTER THE FIRST RUN HAS STARTED ───
        // All three used to be launched together and the test then waited for
        // one of them to park. That is a race the COORDINATOR is allowed to
        // win: `started` exists precisely so a caller arriving before the
        // current run has begun joins it rather than queueing behind it, so an
        // interleaving where `b` and `d` reach `syncNow` before `a` takes the
        // slot legitimately produces ONE run — and the test failed on it about
        // two runs in three.
        //
        // Parking `a` at the wire proves it has started. Only then are the
        // other two launched, which is the situation the test is named for.
        async let a: Void = c.syncNow(reason: .launch)
        await wire.waitUntilParked("daily_logs")
        async let b: Void = c.syncNow(reason: .foreground)
        async let d: Void = c.syncNow(reason: .pull)
        // Two actor hops, so that `b` and `d` land while `a` is still parked —
        // the queued-behind-a-running-sync path rather than the
        // arrived-after-it-finished one, which would count the same and prove
        // less.
        try await Task.sleep(for: .milliseconds(50))
        await wire.release()
        _ = try await (a, b, d)

        let runs = await wire.log.filter { $0 == "pull:daily_logs" }.count
        #expect(runs == 2, "one running, one queued, the third joined the queued one")
        #expect(await c.state == .idle)
        // And it is reusable afterwards: the handover left nothing dangling.
        try await c.syncNow(reason: .pull)
        #expect(await wire.log.filter { $0 == "pull:daily_logs" }.count == 3)
    }

    // MARK: Realtime

    @Test("a realtime note is a sync through the queue, without the HealthKit read")
    func realtimeRefresh() async throws {
        let db = try store()
        let wire = Wire()
        await wire.put("daily_metrics", [[
            "id": "m1", "user_id": user, "date": "2026-09-04", "steps": 12_000,
            "created_at": "2026-09-04T10:00:00Z", "updated_at": "2026-09-04T10:00:00Z",
        ]])
        let health = HealthSync(database: db, reader: ScriptedHealth(steps: 8_000), userId: user)
        let c = coordinator(db, wire, health: health)
        await c.refresh(table: "daily_metrics")

        let log = await wire.log
        #expect(log.contains("pull:daily_metrics"))
        #expect(!log.contains("push:daily_metrics"), "Apple was not read for a server-side change")
        #expect(try db.lastSync(userId: user)["daily_metrics"] == now)
        let stamped = try await db.writer.read { conn in
            try SyncStatusRow.filter(Column("table_name") == "daily_metrics").fetchOne(conn)?.reason
        }
        #expect(stamped == "realtime:daily_metrics")
        // The pulled row scored today, and the score went out.
        #expect(try db.dailyScore(userId: user, date: "2026-09-04") != nil)
        #expect(log.contains("push:daily_scores"))
    }

    @Test("stop abandons the run and refuses a late socket")
    func stopAbandons() async throws {
        let db = try store()
        let wire = Wire()
        await wire.hold()
        let c = coordinator(db, wire)
        let run = Task { try await c.syncNow(reason: .launch) }
        await wire.waitUntilParked("daily_logs")
        await c.stop()
        await wire.release()
        await #expect(throws: (any Error).self) { try await run.value }
        #expect(try db.lastSync(userId: user)["daily_logs"] == nil, "a cancelled run stamps nothing")
    }

    // MARK: Precision Lane C — the one-time doors

    /// `onyx.recount.sets.v1` (Q11) and `onyx.reingest.micros.v1` (Q15) run
    /// after the pull, once per user, remembered in the defaults they are
    /// handed. A harness with no defaults has no doors.
    @Test("the recount door runs once after the pull, and not again")
    func recountDoorRunsOnce() async throws {
        let db = try store()
        let wire = Wire()
        try await db.writer.write { conn in
            try Exercise(id: "ex-press", name: "Leg Press").insert(conn)
            let start = Date(timeIntervalSince1970: 1_788_000_000)
            try WorkoutSession(id: "s", userId: user, dayKey: "legs_a", date: "2026-08-29",
                               startedAt: start, endedAt: start.addingTimeInterval(3600),
                               totalVolumeKg: 1500, setCount: 2).insert(conn)   // the web's old rule: warm-up in
            try WorkoutSet(id: "w", sessionId: "s", exerciseId: "ex-press", setIndex: 1, weightKg: 50, reps: 10, setType: "warmup").insert(conn)
            try WorkoutSet(id: "n", sessionId: "s", exerciseId: "ex-press", setIndex: 2, weightKg: 100, reps: 10).insert(conn)
        }
        let suite = "onyx.tests.doors.\(UUID().uuidString)"
        let doors = UserDefaults(suiteName: suite)!
        let coordinator = SyncCoordinator(
            database: db,
            engine: SyncEngine(database: db, remote: wire, rows: wire),
            puller: MirrorPuller(database: db, remote: wire, userId: user, windowDays: nil),
            training: TrainingPuller(database: db, remote: wire, userId: user, windowDays: nil),
            userId: user, calendar: calendar, now: { [now] in now }, doors: { UserDefaults(suiteName: suite)! }
        )
        try await coordinator.syncNow(reason: .launch)
        let first = try #require(try db.session(id: "s"))
        let firstRow = first
        #expect(firstRow.totalVolumeKg == 1000 && firstRow.setCount == 2 && firstRow.workingSetCount == 1)
        #expect(doors.string(forKey: SyncCoordinator.recountDoor) == user)

        // Tamper, sync again: the door stays shut.
        try await db.writer.write { conn in
            try conn.execute(sql: "UPDATE workout_sessions SET total_volume_kg = 1500 WHERE id = 's'")
        }
        try await coordinator.syncNow(reason: .foreground)
        let tampered = try db.session(id: "s")?.totalVolumeKg
        #expect(tampered == 1500, "a door runs once")
    }

    @Test("the injected harness has no doors")
    func noDefaultsNoDoors() async throws {
        let db = try store()
        try await db.writer.write { conn in
            try Exercise(id: "ex-press", name: "Leg Press").insert(conn)
            let start = Date(timeIntervalSince1970: 1_788_000_000)
            try WorkoutSession(id: "s", userId: user, dayKey: "legs_a", date: "2026-08-29",
                               startedAt: start, endedAt: start.addingTimeInterval(3600),
                               totalVolumeKg: 1500, setCount: 2).insert(conn)
            try WorkoutSet(id: "w", sessionId: "s", exerciseId: "ex-press", setIndex: 1, weightKg: 50, reps: 10, setType: "warmup").insert(conn)
            try WorkoutSet(id: "n", sessionId: "s", exerciseId: "ex-press", setIndex: 2, weightKg: 100, reps: 10).insert(conn)
        }
        try await coordinator(db, Wire()).syncNow(reason: .launch)
        let untouched = try db.session(id: "s")?.totalVolumeKg
        #expect(untouched == 1500)
    }
}

// MARK: - Pagination

@Suite("Pagination")
struct PaginationTests {

    @Test("pages are asked for until a short one, and every row is kept")
    func untilShortPage() async throws {
        let served = Array(0..<2_277)
        let asked = Box<[(Int, Int)]>([])
        let all: [Int] = try await Pagination.all(pageSize: 1000) { from, to in
            asked.withLock { $0.append((from, to)) }
            return Array(served[min(from, served.count)..<min(to + 1, served.count)])
        }
        #expect(all == served)
        #expect(asked.withLock { $0 }.map { $0.0 } == [0, 1000, 2000])
        #expect(asked.withLock { $0 }.map { $0.1 } == [999, 1999, 2999])
    }

    @Test("an exact multiple asks for one empty page, never loses the last row")
    func exactMultiple() async throws {
        let served = Array(0..<2_000)
        let all: [Int] = try await Pagination.all(pageSize: 1000) { from, to in
            Array(served[min(from, served.count)..<min(to + 1, served.count)])
        }
        #expect(all.count == 2_000)
    }

    @Test("an in-list is chunked at 200")
    func chunks() {
        let ids = (0..<450).map(String.init)
        let chunks = Pagination.chunks(ids, size: Pagination.inListLimit)
        #expect(chunks.map(\.count) == [200, 200, 50])
        #expect(chunks.flatMap { $0 } == ids)
        #expect(Pagination.chunks([String](), size: 200).isEmpty)
    }
}

/// A lock for the page recorder above; `Mutex` from Synchronization needs
/// macOS 15 and the package floor is 14.
private final class Box<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}
