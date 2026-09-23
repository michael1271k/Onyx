import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// Two devices, one workout, and no link between them.
///
/// ── THE PROPERTY THIS FILE EXISTS FOR ───────────────────────────────────────
/// Appendix B of the migration plan claims "Supabase is the merge point.
/// WCSession is a latency optimisation and is never the source of truth."
/// Before Wave 10 that was false, and provably: the outbox reconciled only
/// `workout_sets` ROWS, and `TrainingPuller.applyPulledSets` refuses to write
/// pulled rows into any session that already has local events. So the phone
/// logged sets 1-3, the watch logged set 4, the server ended up holding all
/// four — and NEITHER device could adopt the other's. The workout was whole on
/// the server and permanently partial on both clients. `v17.adoptRepairedSessions`
/// is a hardcoded one-UUID migration that exists because of exactly this.
///
/// `set_events` on the server is the fix, and this is the test that says so.
/// The two stores never touch each other: everything goes device → fake server
/// → device, which is the claim.
///
/// ── AND THE SECOND HALF IS THE HALF THAT MATTERS ────────────────────────────
/// Propagating an APPEND is the easy direction, and a cheaper design (synthesise
/// events from unknown server rows) would pass the first assertion. It cannot
/// pass the void: a tombstone is executed against `workout_sets` as a DELETE, so
/// its only evidence is an absence — and a device cannot tell "the other device
/// voided it" from "the other device has not drained yet". `.void` is terminal
/// in the fold, so one wrong guess kills a set unresurrectably. A void has to
/// travel as a ROW, and `kind = 'void'` is that row.
@Suite("Watch convergence")
struct WatchConvergenceTests {

    // MARK: - A server that holds rows AND events

    /// Postgres's rules for the three tables this exercises, and nothing more.
    private actor Server: SyncRemote, MirrorRemote {
        var sessions: [String: RemoteSessionRow] = [:]
        var sets: [String: RemoteSetRow] = [:]
        /// `set_events`, keyed by the event's own id — `ON CONFLICT DO NOTHING`,
        /// because an event is immutable.
        var events: [String: RemoteSetEventRow] = [:]

        func exerciseCatalogue() async throws -> [RemoteExercise] {
            [RemoteExercise(id: "uuid-hack-squat", name: "Hack Squat")]
        }

        func upsertSessions(_ rows: [RemoteSessionRow], ignoreDuplicates: Bool) async throws {
            for row in rows {
                if ignoreDuplicates && sessions[row.id] != nil { continue }
                sessions[row.id] = row
            }
        }

        func upsertSets(_ rows: [RemoteSetRow]) async throws {
            for row in rows { sets[row.id] = row }
        }

        func deleteSets(ids: [String]) async throws {
            for id in ids { sets.removeValue(forKey: id) }
        }

        func upsertSetEvents(_ rows: [RemoteSetEventRow]) async throws {
            // The real table's conflict rule. An event already here is left
            // exactly as it is — nothing may rewrite history.
            for row in rows where events[row.id] == nil { events[row.id] = row }
        }

        // ── The read half ────────────────────────────────────────────────

        func select<T: Decodable & Sendable>(_ type: T.Type, request: MirrorRequest) async throws -> [T] {
            guard request.table == "workout_sessions" else { return [] }
            return try recode(Array(sessions.values))
        }

        func selectIn<T: Decodable & Sendable>(
            _ type: T.Type, table: String, column: String, values: [String]
        ) async throws -> [T] {
            let wanted = Set(values)
            switch table {
            case "workout_sets":
                return try recode(sets.values.filter { wanted.contains($0.sessionId) })
            case "set_events":
                return try recode(events.values.filter { wanted.contains($0.sessionId) })
            default:
                return []
            }
        }

        func count(table: String) async throws -> Int { 0 }

        /// Wipe the event table, leaving the rows — this database on the day
        /// before `wave-10-set-events.sql (git history)` was applied.
        func forgetEvents() { events.removeAll() }

        /// Encode then decode, so the values cross the same JSON boundary they
        /// would over PostgREST — which is what makes `RemoteSetEventRow`'s
        /// hand-written `encode(to:)` and `SetEvent.Body`'s `{kind, payload}`
        /// shape part of what is under test rather than bypassed.
        private func recode<Row: Encodable, T: Decodable>(_ rows: some Collection<Row>) throws -> [T] {
            let data = try OnyxJSON.encoder.encode(Array(rows))
            return try OnyxJSON.decoder.decode([T].self, from: data)
        }
    }

    // MARK: - Harness

    private func store(deviceId: String) throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: deviceId)
        try db.writer.write { conn in
            // TWO rows for one movement, and both are needed. A set logged on a
            // device carries `onyx-back-squat` (`ExerciseSlug.id`); the same
            // set pulled back down carries the CATALOGUE's uuid, because that is
            // what `SyncTranslation` sent. `workout_sets.exercise_id` has a
            // foreign key, so the local table has to hold both spellings or the
            // pull fails on the constraint — which is exactly the state a real
            // device is in until the exercise library reconciles them.
            try Exercise(id: ExerciseSlug.id("Hack Squat"), name: "Hack Squat").insert(conn)
            try Exercise(id: "uuid-hack-squat", name: "Hack Squat").insert(conn)
            try WorkoutSession(
                id: Self.sessionId, userId: Self.userId, dayKey: "legs_a", date: "2026-09-07"
            ).insert(conn)
        }
        return db
    }

    private static let sessionId = "11111111-1111-1111-1111-111111111111"
    private static let userId = "22222222-2222-2222-2222-222222222222"

    private func snapshot(_ index: Int, _ kg: Double) -> SetSnapshot {
        // The slug a device writes, not the catalogue uuid — `SyncEngine`
        // resolves one to the other through `ExerciseIndex`, and a snapshot
        // carrying the uuid would skip the translation this is meant to exercise.
        SetSnapshot(exerciseId: ExerciseSlug.id("Hack Squat"), setIndex: index, weightKg: kg, reps: 8)
    }

    /// One device's full sync: push what it has, then pull what it does not.
    private func sync(_ db: AppDatabase, _ server: Server) async throws {
        try await SyncEngine(database: db, remote: server).drain()
        try await TrainingPuller(
            database: db, remote: server, userId: Self.userId, windowDays: nil
        ).refresh()
    }

    private func setIds(_ db: AppDatabase) throws -> [String] {
        try db.sets(sessionId: Self.sessionId).map(\.id).sorted()
    }

    // MARK: - The claim

    @Test("two devices logging one session converge through the server alone")
    func devicesConvergeThroughSupabase() async throws {
        let phone = try store(deviceId: "phone")
        let watch = try store(deviceId: "watch")
        let server = Server()

        // The phone logs the first three sets.
        for index in 1...3 {
            try phone.appendSet(sessionId: Self.sessionId, snapshot(index, 100))
        }
        // The watch, out of range of the phone, logs the fourth.
        try watch.appendSet(sessionId: Self.sessionId, snapshot(4, 105))

        #expect(try setIds(phone).count == 3)
        #expect(try setIds(watch).count == 1)

        // Neither device is ever handed the other's events directly. This is
        // the whole point: `ingest` is reached only through the puller.
        try await sync(phone, server)
        try await sync(watch, server)
        try await sync(phone, server)

        let onPhone = try setIds(phone)
        let onWatch = try setIds(watch)
        #expect(onPhone.count == 4, "the phone is missing the watch's set")
        #expect(onWatch.count == 4, "the watch is missing the phone's sets")
        #expect(onPhone == onWatch, "the two devices folded different lists")
    }

    @Test("a void travels too — the half a row-only merge cannot do")
    func voidsPropagate() async throws {
        let phone = try store(deviceId: "phone")
        let watch = try store(deviceId: "watch")
        let server = Server()

        for index in 1...3 {
            try phone.appendSet(sessionId: Self.sessionId, snapshot(index, 100))
        }
        try await sync(phone, server)
        try await sync(watch, server)
        #expect(try setIds(watch).count == 3)

        // The watch deletes the middle set. A tombstone, not a delete.
        let doomed = try #require(try watch.sets(sessionId: Self.sessionId).dropFirst().first)
        try watch.voidSet(sessionId: Self.sessionId, setId: doomed.id)
        try await sync(watch, server)
        try await sync(phone, server)

        #expect(try setIds(phone).count == 2, "the phone resurrected a voided set")
        #expect(try setIds(phone) == (try setIds(watch)))
        #expect(try !setIds(phone).contains(doomed.id))
    }

    @Test("an amend on one device reaches the other")
    func amendsPropagate() async throws {
        let phone = try store(deviceId: "phone")
        let watch = try store(deviceId: "watch")
        let server = Server()

        try phone.appendSet(sessionId: Self.sessionId, snapshot(1, 100))
        try await sync(phone, server)
        try await sync(watch, server)

        let target = try #require(try watch.sets(sessionId: Self.sessionId).first)
        try watch.amendSet(sessionId: Self.sessionId, setId: target.id, SetPatch(weightKg: 112.5, rpe: 8.5))
        try await sync(watch, server)
        try await sync(phone, server)

        let landed = try #require(try phone.sets(sessionId: Self.sessionId).first)
        #expect(landed.weightKg == 112.5)
        #expect(landed.rpe == 8.5)
    }

    @Test("a second sync sends nothing new and changes nothing")
    func syncIsIdempotent() async throws {
        let phone = try store(deviceId: "phone")
        let server = Server()

        for index in 1...3 {
            try phone.appendSet(sessionId: Self.sessionId, snapshot(index, 100))
        }
        try await sync(phone, server)
        let after = try setIds(phone)
        let eventCount = await server.events.count

        try await sync(phone, server)
        try await sync(phone, server)

        #expect(try setIds(phone) == after)
        #expect(await server.events.count == eventCount, "a replay wrote new event rows")
    }

    /// ── THE TRIPWIRE FOR AN ECHO LOOP ───────────────────────────────────────
    /// `ingest` marks what it takes in as synced and queues nothing, which is
    /// the only reason pulling an event does not immediately re-push it. If that
    /// ever changes, this catches it: the watch's outbox must be empty after a
    /// pull that landed three of the phone's sets.
    @Test("pulled events are never re-queued for upload")
    func pulledEventsDoNotEcho() async throws {
        let phone = try store(deviceId: "phone")
        let watch = try store(deviceId: "watch")
        let server = Server()

        for index in 1...3 {
            try phone.appendSet(sessionId: Self.sessionId, snapshot(index, 100))
        }
        try await sync(phone, server)
        try await sync(watch, server)

        #expect(try setIds(watch).count == 3)
        #expect(try watch.outboxPendingCount() == 0, "the watch queued the phone's own events")
    }

    /// A session that straddles the day the server-side log was created: some
    /// sets exist only as rows, the rest as events. Ingesting the events alone
    /// would re-fold the session from the later half and the earlier sets would
    /// disappear from a workout that is complete on the server —
    /// `seedEventLogs` in the puller is what stops that.
    @Test("rows that predate the event log survive an event arriving")
    func seedsBeforeIngesting() async throws {
        let phone = try store(deviceId: "phone")
        let watch = try store(deviceId: "watch")
        let server = Server()

        // Two sets logged the old way: rows on the server, no events anywhere.
        for index in 1...2 {
            try phone.appendSet(sessionId: Self.sessionId, snapshot(index, 100))
        }
        try await sync(phone, server)
        await server.forgetEvents()

        // The watch adopts them as rows, then logs a third — which DOES produce
        // an event.
        try await sync(watch, server)
        #expect(try setIds(watch).count == 2)
        try watch.appendSet(sessionId: Self.sessionId, snapshot(3, 100))
        try await sync(watch, server)

        // The phone pulls. Its own log already has the first two, so the seed is
        // a no-op there — but the watch proves the direction that matters: three
        // sets, not one.
        try await sync(phone, server)
        #expect(try setIds(phone).count == 3, "the pre-log rows were folded away")
        #expect(try setIds(watch).count == 3)
    }

    // MARK: - The strand (W2, decision 15)

    @Test("a set the watch hands the phone over WCSession reaches the server")
    func watchSetsAreNotStranded() async throws {
        let phone = try store(deviceId: "phone")
        let watch = try store(deviceId: "watch")
        let server = Server()

        for index in 1...3 {
            try phone.appendSet(sessionId: Self.sessionId, snapshot(index, 100))
        }
        try await sync(phone, server)
        #expect(await server.sets.count == 3)

        // The wrist logs set 4 and hands it over the LINK, not the network —
        // exactly what `PhoneWatchBridge.receive(.events)` does.
        try watch.appendSet(sessionId: Self.sessionId, snapshot(4, 105))
        try phone.ingestFromWatch(try watch.setEvents(sessionId: Self.sessionId))
        #expect(try setIds(phone).count == 4)
        #expect(
            try phone.pendingOutbox(limit: 50).contains { $0.idempotencyKey.hasPrefix("set_event:") },
            "the wrist's event is queued on the phone without the phone touching the session"
        )
        // Handed over twice — WCSession redelivers — is still one event.
        try phone.ingestFromWatch(try watch.setEvents(sessionId: Self.sessionId))
        #expect(try setIds(phone).count == 4)

        // The phone's next drain carries the projection up.
        try await SyncEngine(database: phone, remote: server).drain()
        #expect(await server.sets.count == 4, "the watch's set never left the phone")
        #expect(await server.sets.values.contains { $0.weightKg == 105 })
    }

    // MARK: - The lifecycle (overhaul Lane A, decision Q1)
    //
    // The phone's finish used to reach the wrist ONLY down the queue, behind
    // the sets — on hardware whenever it drained, on a simulator never. These
    // three are the rules that let it travel faster without breaking that
    // order, and that stop a finished session being adopted twice.

    private static let start = Date(timeIntervalSince1970: 1_788_000_000)

    @Test("a messaged finish waits for the queue behind it, then closes over every set")
    func messagedFinishWaitsForTheQueue() async throws {
        let phone = try store(deviceId: "phone")
        let watch = try store(deviceId: "watch")
        for index in 1...3 {
            try phone.appendSet(sessionId: Self.sessionId, snapshot(index, 100))
        }
        // Only the first set's transfer has reached the wrist.
        let events = try phone.setEvents(sessionId: Self.sessionId)
        try watch.ingest(Array(events.prefix(1)))

        let closed = try #require(try phone.closeSession(id: Self.sessionId))
        let finish = SessionPulse(
            closed, phase: .finished, expectedEventCount: try phone.eventCount(sessionId: Self.sessionId)
        )
        #expect(finish.expectedEventCount == 3)
        #expect(try watch.finishIsReady(finish) == false, "two sets are still in the queue ahead of it")

        // The grace runs out on a queue that never drains (a simulator's) —
        // the wait returns and the banner still arrives.
        let began = Date()
        await watch.waitForFinish(finish, grace: 0.3)
        #expect(Date().timeIntervalSince(began) >= 0.3)

        // The queue drains: now it is ready, and the close covers all three.
        try watch.ingest(events)
        #expect(try watch.finishIsReady(finish))
        #expect(try watch.receiveSession(finish) == .closed)
        #expect(try setIds(watch).count == 3)
        // A finish with no count (an older phone, or the queued copy) never waits.
        #expect(try watch.finishIsReady(SessionPulse(closed, phase: .finished)))
    }

    @Test("a context that says finished retires a session whose pulse never arrived")
    func lifecycleRetiresAMissedFinish() throws {
        let watch = try store(deviceId: "watch")
        try watch.appendSet(sessionId: Self.sessionId, snapshot(1, 100))
        let live = try #require(try watch.liveSession(dayKey: "legs_a", date: "2026-09-07", userId: Self.userId))

        // The open arrived; the queued finish did not. The context says it.
        let word = SessionLifecycle(sessionId: Self.sessionId, phase: .finished, startedAt: Self.start,
                                    endedAt: Self.start.addingTimeInterval(3_000), date: "2026-09-07", dayKey: "legs_a")
        #expect(try watch.applyLifecycle(word, userId: Self.userId) == .closed)
        #expect(try watch.liveSession(dayKey: "legs_a", date: "2026-09-07", userId: Self.userId) == nil,
                "nothing live is left for rejoinLiveSession to adopt")
        #expect(try watch.session(id: Self.sessionId, userId: Self.userId)?.endedAt == word.endedAt)
        #expect(try setIds(watch).count == 1, "closed, not thrown away — the set stays")
        #expect(try watch.applyLifecycle(word, userId: Self.userId) == .unchanged, "idempotent")

        // A finished session the wrist NEVER saw: its open arrives after the
        // context did, by message or by queue, and must not become live.
        var other = live
        other.id = "33333333-3333-3333-3333-333333333333"
        other.startedAt = Self.start
        let retired = SessionLifecycle(sessionId: other.id, phase: .finished, startedAt: Self.start,
                                       endedAt: Self.start.addingTimeInterval(3_000))
        #expect(try watch.applyLifecycle(retired, userId: Self.userId) == .unchanged)
        #expect(try watch.isTombstoned(sessionId: other.id))
        #expect(try watch.receiveSession(SessionPulse(other, phase: .open)) == .unchanged)
        #expect(try watch.session(id: other.id, userId: Self.userId) == nil)

        // An open lifecycle changes nothing: joining is a tap, not a push.
        let open = SessionLifecycle(sessionId: "44444444-4444-4444-4444-444444444444", phase: .open, startedAt: Self.start)
        #expect(try watch.applyLifecycle(open, userId: Self.userId) == .unchanged)
        #expect(try watch.isTombstoned(sessionId: open.sessionId) == false)
    }

    @Test("two-a-day: after the banner, Start another opens a second session and the first stays closed")
    func startAnotherOpensASecondSession() throws {
        let phone = try store(deviceId: "phone")
        let watch = try store(deviceId: "watch")
        try phone.appendSet(sessionId: Self.sessionId, snapshot(1, 100))
        try watch.ingest(try phone.setEvents(sessionId: Self.sessionId))
        var first = try #require(try phone.closeSession(id: Self.sessionId))
        first.startedAt = Self.start
        #expect(try watch.receiveSession(SessionPulse(first, phase: .finished)) == .closed)

        var context = WatchContext(userId: Self.userId, today: "2026-09-07",
                                   schedule: ScheduleContext(programId: "onyx5", phase: .cut))
        context.session = SessionLifecycle(SessionPulse(first, phase: .finished))
        guard case .banner = WatchFrontDoor.resolve(context) else {
            Issue.record("a finished session today is the banner, not Start")
            return
        }

        // "Start another" is the ordinary open. The closed row is not live,
        // so a NEW row is made rather than the finished one re-adopted.
        let second = try watch.openSession(userId: Self.userId, dayKey: "legs_a", date: "2026-09-07")
        #expect(second.id != Self.sessionId)
        #expect(try phone.receiveSession(SessionPulse(second, phase: .open)) == .opened(superseded: nil),
                "the phone's finished session is no rival for the split")
        #expect(try phone.session(id: Self.sessionId, userId: Self.userId)?.endedAt != nil)

        // The phone now publishes the second as open; the wrist that started
        // it has adopted it, and one that has not is offered Join.
        let secondWord = try #require(SessionLifecycle(SessionPulse(second, phase: .open)))
        context.session = secondWord
        #expect(WatchFrontDoor.resolve(context) == .join(secondWord))
    }
}
