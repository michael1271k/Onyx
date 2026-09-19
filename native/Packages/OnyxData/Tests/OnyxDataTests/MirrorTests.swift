import Foundation
import Testing
import GRDB
@testable import OnyxData

/// A server that answers a `MirrorRequest` from a canned table of rows.
///
/// It applies the filter it is given rather than ignoring it, because "did the
/// puller ask for the right range" is most of what these tests are about.
private actor FakeMirror: MirrorRemote {

    /// Table name → rows, as JSON objects.
    var rows: [String: [[String: Any]]] = [:]
    /// Every request seen, so a test can assert what was asked for.
    var requests: [MirrorRequest] = []
    var failure: (any Error)?

    func put(_ table: String, _ objects: [[String: Any]]) { rows[table] = objects }
    func setFailure(_ error: (any Error)?) { failure = error }

    func select<T: Decodable & Sendable>(_ type: T.Type, request: MirrorRequest) async throws -> [T] {
        requests.append(request)
        if let failure { throw failure }
        var objects = rows[request.table] ?? []
        if let since = request.since {
            objects = objects.filter { object in
                guard let value = object[since.column] as? String else { return true }
                return value >= since.value
            }
        }
        return try decode(objects)
    }

    func selectIn<T: Decodable & Sendable>(
        _ type: T.Type, table: String, column: String, values: [String]
    ) async throws -> [T] {
        if let failure { throw failure }
        let wanted = Set(values)
        let objects = (rows[table] ?? []).filter { wanted.contains(($0[column] as? String) ?? "") }
        return try decode(objects)
    }

    func count(table: String) async throws -> Int {
        if let failure { throw failure }
        return rows[table]?.count ?? 0
    }

    private func decode<T: Decodable>(_ objects: [[String: Any]]) throws -> [T] {
        let data = try JSONSerialization.data(withJSONObject: objects)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([T].self, from: data)
    }
}

private struct Unreachable: Error {}

/// ISO-8601 with fractional seconds, the way PostgREST renders a `timestamptz`.
private func iso(_ offsetSeconds: TimeInterval) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: Date(timeIntervalSince1970: 1_788_000_000 + offsetSeconds))
}

@Suite("The mirror")
struct MirrorTests {

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    private func puller(_ db: AppDatabase, _ remote: FakeMirror) -> MirrorPuller {
        MirrorPuller(database: db, remote: remote, userId: "u1")
    }

    private func table(_ name: String) throws -> MirrorTable {
        try #require(MirrorCatalogue.tables.first { $0.name == name })
    }

    // MARK: The window

    @Test("windowDays nil pulls a window table whole, and leaves delta alone")
    func windowRemoved() async throws {
        let db = try store()
        let remote = FakeMirror()
        let puller = MirrorPuller(database: db, remote: remote, userId: "u1", windowDays: nil)
        try await puller.refresh(try table("doms_logs"))
        try await puller.refresh(try table("daily_logs"))
        let requests = await remote.requests
        #expect(requests.count == 2)
        #expect(requests[0].table == "doms_logs")
        #expect(requests[0].since == nil, "no cap: the whole table, every time")
        #expect(requests[0].order == ["id"])
        // A delta table with no cursor yet is a full pull too; with one it is
        // still a delta — the window setting has no say over it.
        #expect(requests[1].since == nil)
        try db.setMirrorCursor(table: "daily_logs", to: Date(timeIntervalSince1970: 1_788_000_000), at: Date())
        try await puller.refresh(try table("daily_logs"))
        #expect(await remote.requests.last?.since?.column == "updated_at")
    }

    @Test("the pull is ordered by the primary key, composite or not")
    func orderIsThePrimaryKey() throws {
        #expect(try table("personal_records").order == ["user_id", "exercise_key", "axis"])
        #expect(try table("daily_logs").order == ["id"])
        try store().writer.read { conn in
            for table in MirrorCatalogue.tables {
                let columns = try conn.primaryKey(table.name).columns
                #expect(columns == table.order, "\(table.name)")
            }
        }
    }

    // MARK: The catalogue

    @Test("the catalogue covers the schema fixture, minus the three the logger owns")
    func catalogueIsComplete() {
        // 32 tables in the fixture since W2 (routines, plan_phases,
        // lever_periods, stress_logs); `workout_sessions`, `workout_sets` and
        // `exercises` are bespoke because they land in tables that already
        // exist locally in a different shape.
        #expect(MirrorCatalogue.tables.count == 29)
        let names = Set(MirrorCatalogue.tables.map(\.name))
        #expect(!names.contains("workout_sets"))
        // And the tape table is absent on purpose — ONYX does not do manual
        // limb measurement and the fields must not come back within reach.
        #expect(!names.contains("body_measurements"))
        // Dropped in W4: pulled, never written, zero readers on either side and
        // zero rows live. The server table goes with it.
        #expect(!names.contains("supplement_dose_overrides"))
        // As are the two Notion leftovers and the dying widget token table.
        #expect(names.isDisjoint(with: ["notion_credentials", "notion_exports", "widget_tokens"]))
    }

    @Test("every mirrored table exists in SQLite with the columns Postgres has")
    func migrationCreatedEveryTable() throws {
        let db = try store()
        try db.writer.read { conn in
            for table in MirrorCatalogue.tables {
                #expect(try conn.tableExists(table.name), "\(table.name) was not created")
            }
            // Spot-check a wide one, column for column against the fixture.
            let columns = try conn.columns(in: "daily_logs").map(\.name)
            #expect(columns.count == 52)
            #expect(columns.contains("sleep_onset_trouble"))
            #expect(columns.contains("estimated_waist_to_hip_ratio"))
            // The 51st, added by `v20.sleepInaccurate`. A fresh install runs the
            // mirror's create-table and then the ALTER, so this asserts the
            // migration ran on a database that never had the column — which is
            // the case an edited create-table would silently break.
            #expect(columns.contains("sleep_inaccurate"))
            // The 52nd, added by `v30.waistCm` (W3, 2026-09-17). The one tape
            // measurement in the app: a COLUMN on the day, not the
            // `body_measurements` table two lines up, which stays absent.
            #expect(columns.contains("waist_cm"))
        }
    }

    @Test("v6's read cache is gone, and the mirror's user_goals took its place")
    func v6TablesDropped() throws {
        let db = try store()
        try db.writer.read { conn in
            #expect(try !conn.tableExists("nutrition_days"))
            // Same NAME, different table: 31 columns keyed on `id`, not the
            // seven-column cache keyed on `user_id`.
            #expect(try conn.tableExists("user_goals"))
            let columns = try conn.columns(in: "user_goals").map(\.name)
            #expect(columns.contains("active_lever"))
            #expect(columns.contains("maintenance_until"))
        }
    }

    // MARK: Pulling

    @Test("a full pull lands rows the app can read back")
    func fullPullRoundTrips() async throws {
        let db = try store()
        let remote = FakeMirror()
        await remote.put("plans", [[
            "id": "p1", "user_id": "u1", "name": "ONYX-5",
            "program_id": "onyx5", "active": true, "started_on": "2026-07-15",
            "created_at": iso(0),
        ]])

        let count = try await puller(db, remote).refresh(try table("plans"))
        #expect(count == 1)

        let stored = try await db.writer.read { try PlanRow.fetchAll($0) }
        #expect(stored.count == 1)
        #expect(stored[0].name == "ONYX-5")
        #expect(stored[0].startedOn == "2026-07-15", "a `date` column stays yyyy-MM-dd text")
    }

    @Test("a delta pull asks for everything at or after the newest row it holds")
    func deltaUsesTheCursor() async throws {
        let db = try store()
        let remote = FakeMirror()
        let goals = try table("user_goals")
        func row(_ updated: String) -> [String: Any] {
            ["id": "g1", "user_id": "u1", "context_mode": "cut", "created_at": iso(0),
             "updated_at": updated, "auto_log_supplements": true, "active_program": "onyx5",
             "day_cutoff_hour": 0, "unit_system": "metric", "reduce_motion": false,
             "timezone": "Asia/Jerusalem", "track_rpe": true]
        }

        await remote.put("user_goals", [row(iso(100))])
        _ = try await puller(db, remote).refresh(goals)
        // First pull has no cursor and asks for the whole table.
        #expect(await remote.requests.last?.since == nil)

        // Second pull carries one, and it is the newest row's timestamp.
        _ = try await puller(db, remote).refresh(goals)
        let since = try #require(await remote.requests.last?.since)
        #expect(since.column == "updated_at")
        #expect(since.value == iso(100))
    }

    @Test("the cursor only ever moves forward")
    func cursorNeverGoesBackwards() async throws {
        let db = try store()
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        try db.setMirrorCursor(table: "user_goals", to: now, at: now)
        // An older value cannot win. A cursor that could move back would re-pull
        // the same range forever.
        try db.setMirrorCursor(table: "user_goals", to: now.addingTimeInterval(-3600), at: now)
        #expect(try db.mirrorCursor(table: "user_goals") == now)

        try db.setMirrorCursor(table: "user_goals", to: now.addingTimeInterval(60), at: now)
        #expect(try db.mirrorCursor(table: "user_goals") == now.addingTimeInterval(60))
    }

    @Test("an empty pull does not clear the cursor")
    func emptyPullKeepsTheCursor() async throws {
        let db = try store()
        let remote = FakeMirror()
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        try db.setMirrorCursor(table: "user_goals", to: now, at: now)

        await remote.put("user_goals", [])
        _ = try await puller(db, remote).refresh(try table("user_goals"))
        // Clearing it would re-download the whole table on the next refresh,
        // which on a metered connection is a sync becoming a download.
        #expect(try db.mirrorCursor(table: "user_goals") == now)
    }

    @Test("a windowed table asks for the trailing window, not the world")
    func windowedPull() async throws {
        let db = try store()
        let remote = FakeMirror()
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        await remote.put("daily_scores", [])

        let puller = MirrorPuller(database: db, remote: remote, userId: "u1", windowDays: 30)
        _ = try await puller.refresh(try table("daily_scores"), now: now)

        let since = try #require(await remote.requests.last?.since)
        #expect(since.column == "date")
        #expect(since.value == LogicalDayISO.string(
            Calendar.current.date(byAdding: .day, value: -30, to: now)!
        ))
    }

    @Test("a re-pull upserts rather than duplicating")
    func repullIsIdempotent() async throws {
        let db = try store()
        let remote = FakeMirror()
        await remote.put("plans", [[
            "id": "p1", "user_id": "u1", "name": "ONYX-5", "created_at": iso(0),
        ]])
        let plans = try table("plans")
        _ = try await puller(db, remote).refresh(plans)
        _ = try await puller(db, remote).refresh(plans)
        #expect(try await db.writer.read { try PlanRow.fetchCount($0) } == 1)
    }

    @Test("one failing table does not stop the other twenty-five")
    func failuresArePerTable() async throws {
        let db = try store()
        let remote = FakeMirror()
        await remote.setFailure(Unreachable())

        let report = await puller(db, remote).refresh()
        #expect(!report.isClean)
        #expect(report.failures.count == MirrorCatalogue.tables.count)
        #expect(report.tables == 0)
        // And nothing was written, so no cursor moved past a range that was
        // never actually read.
        #expect(try db.mirrorCursors().isEmpty)
    }

    @Test("a jsonb column round-trips through SQLite unchanged")
    func jsonbSurvives() async throws {
        let db = try store()
        let remote = FakeMirror()
        await remote.put("dashboard_layouts", [[
            "user_id": "u1",
            "layout": ["slots": ["battery", "readiness"], "cols": 2],
            "updated_at": iso(0),
        ]])
        _ = try await puller(db, remote).refresh(try table("dashboard_layouts"))

        let stored = try #require(await db.writer.read { try DashboardLayoutRow.fetchOne($0) })
        // Stored as canonical text, so the same server value is always the same
        // bytes — and the keys come back sorted, not in arrival order.
        #expect(stored.layout.raw == #"{"cols":2,"slots":["battery","readiness"]}"#)
    }

    @Test("a text[] column is JSON too, not a mangled string")
    func textArraySurvives() throws {
        // `exercises.muscle_groups` is the only one, and it is on a bespoke
        // table — but the type it uses is the mirror's, so pin the behaviour.
        let decoded = try JSONDecoder().decode(
            JSONText.self, from: Data(#"["chest","triceps"]"#.utf8)
        )
        #expect(decoded.raw == #"["chest","triceps"]"#)
    }

    @Test("nil stays nil — an untracked macro is not a zero")
    func nullsAreNotZeroes() async throws {
        let db = try store()
        let remote = FakeMirror()
        await remote.put("daily_logs", [[
            "id": "d1", "user_id": "u1", "date": "2026-09-02",
            "created_at": iso(0), "updated_at": iso(0),
            "nutrition_estimated": false, "sleep_onset_trouble": false,
            "steps": NSNull(), "protein_g": NSNull(),
        ]])
        _ = try await puller(db, remote).refresh(try table("daily_logs"))

        let stored = try #require(await db.writer.read { try DailyLogRow.fetchOne($0) })
        // A day with no intake recorded says nothing about adherence. Defaulting
        // it to 0 would grade an untracked day as a perfect deficit.
        #expect(stored.steps == nil)
        #expect(stored.proteinG == nil)
    }
}


// MARK: - The training trio

@Suite("Training pull")
struct TrainingPullerTests {

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    private func session(_ id: String, startedAt: String, updatedAt: String) -> [String: Any] {
        ["id": id, "user_id": "u1", "started_at": startedAt, "split_day": "legs",
         "day_key": "legs_a", "migrated_from_notion": false, "status": "complete",
         "created_at": startedAt, "updated_at": updatedAt,
         "calories_estimated": false, "avg_bpm_estimated": false]
    }

    private func set(_ id: String, session: String, number: Int, side: String? = nil) -> [String: Any] {
        var row: [String: Any] = [
            "id": id, "session_id": session, "exercise_id": "ex-1", "user_id": "u1",
            "set_number": number, "weight_kg": 100.0, "reps": 8,
            "created_at": "2026-09-02T09:00:00.000Z", "set_type": "normal",
        ]
        if let side { row["side"] = side }
        return row
    }

    @Test("a pulled session gets the `date` Postgres does not have")
    func dateIsDerivedOnTheWayIn() async throws {
        let db = try store()
        let remote = FakeMirror()
        await remote.put("workout_sessions", [session("s1", startedAt: iso(0), updatedAt: iso(0))])
        await remote.put("workout_sets", [])
        await remote.put("exercises", [])

        _ = try await TrainingPuller(database: db, remote: remote, userId: "u1").refresh()

        let stored = try #require(try db.session(id: "s1"))
        // `workout_sessions.date` is NOT NULL locally and absent server-side.
        // It is this derivation, in the device's calendar, or nothing.
        #expect(stored.date == SyncTranslation.sessionDate(for: Date(timeIntervalSince1970: 1_788_000_000)))
        #expect(stored.isPendingSync == false, "it came FROM the server")
    }

    @Test("pulled sets arrive translated — set_number becomes set_index, L becomes left")
    func setsAreTranslatedOnTheWayIn() async throws {
        let db = try store()
        let remote = FakeMirror()
        await remote.put("workout_sessions", [session("s1", startedAt: iso(0), updatedAt: iso(0))])
        await remote.put("workout_sets", [
            set("set-1", session: "s1", number: 1),
            set("set-2", session: "s1", number: 2, side: "L"),
        ])
        await remote.put("exercises", [["id": "ex-1", "name": "Hack Squat"]])

        _ = try await TrainingPuller(database: db, remote: remote, userId: "u1").refresh()

        let sets = try db.sets(sessionId: "s1")
        #expect(sets.count == 2)
        #expect(sets[0].setIndex == 1)
        #expect(sets[1].side == "left", "the server says L; the local vocabulary is left/right")
        #expect(sets.allSatisfy { !$0.isPendingSync })

        // The catalogue lands too, so the drainer can resolve a slug without a
        // second round trip once Wave 3 wires it up.
        #expect(try db.exercises().contains { $0.id == "ex-1" && $0.name == "Hack Squat" })
    }

    @Test("a movement merged away on the server stops being a second row in the library")
    func aMergedExerciseIsReconciledAway() async throws {
        // The `Lat Pulldown (Cable)` bug, end to end. `merge-exercise.mjs` (git history)
        // re-points the sets and deletes the row, and touches NOTHING the sets
        // pull has a delta on — so before this reconciliation the phone kept
        // both the dead catalogue row and the sets naming it, and the library
        // listed the movement twice.
        let db = try store()
        let remote = FakeMirror()
        let started = iso(0)

        func setRow(_ id: String, exercise: String) -> [String: Any] {
            ["id": id, "session_id": "s1", "exercise_id": exercise, "user_id": "u1",
             "set_number": 1, "weight_kg": 60.0, "reps": 10,
             "created_at": "2026-09-02T09:00:00.000Z", "set_type": "normal"]
        }

        await remote.put("workout_sessions", [session("s1", startedAt: started, updatedAt: started)])
        await remote.put("exercises", [
            ["id": "ex-keep", "name": "Lat Pulldown"],
            ["id": "ex-gone", "name": "Lat Pulldown (Cable)"],
        ])
        await remote.put("workout_sets", [
            setRow("set-1", exercise: "ex-keep"),
            setRow("set-2", exercise: "ex-gone"),
        ])

        _ = try await TrainingPuller(database: db, remote: remote, userId: "u1").refresh()
        #expect(try db.exercises().count == 2, "both rows exist before the merge")

        // The merge, server-side: the set moves, the row goes, and the SESSION
        // is deliberately left untouched — that is the whole trap.
        await remote.put("exercises", [["id": "ex-keep", "name": "Lat Pulldown"]])
        await remote.put("workout_sets", [
            setRow("set-1", exercise: "ex-keep"),
            setRow("set-2", exercise: "ex-keep"),
        ])

        _ = try await TrainingPuller(database: db, remote: remote, userId: "u1").refresh()

        let catalogue = try db.exercises()
        #expect(catalogue.map(\.id) == ["ex-keep"], "the merged-away row is gone")
        let sets = try db.sets(sessionId: "s1")
        #expect(sets.count == 2)
        #expect(sets.allSatisfy { $0.exerciseId == "ex-keep" }, "both sets moved to the surviving movement")
    }

    @Test("a catalogue row still named by a set is kept, dangling ids being worse than duplicates")
    func aReferencedOrphanSurvives() throws {
        let db = try store()
        // Straight at the store: the puller cannot produce this state, and the
        // guard is what stops it destroying a name if it ever could.
        try db.applyPulledExercises([RemoteExerciseRow(id: "ex-gone", name: "Lat Pulldown (Cable)")])
        #expect(try db.deleteUnreferencedExercises(ids: ["ex-gone"]) == 1)

        try db.applyPulledExercises([RemoteExerciseRow(id: "ex-gone", name: "Lat Pulldown (Cable)")])
        try db.writer.write { write in
            // `workout_sets.session_id` still has its foreign key — only the
            // one to `exercises` went in `v4`.
            try WorkoutSession(
                id: "s-x", userId: "u1", dayKey: "legs_a", date: "2026-09-02"
            ).insert(write)
            try WorkoutSet(
                id: "set-x", sessionId: "s-x", exerciseId: "ex-gone",
                setIndex: 1, weightKg: 60, reps: 10
            ).insert(write)
        }
        #expect(try db.deleteUnreferencedExercises(ids: ["ex-gone"]) == 0, "a set still names it")
        #expect(try db.exercises().contains { $0.id == "ex-gone" })
    }

    @Test("an empty catalogue pull is read as a failure, never as `everything was deleted`")
    func anEmptySnapshotDeletesNothing() throws {
        let db = try store()
        try db.applyPulledExercises([RemoteExerciseRow(id: "ex-1", name: "Hack Squat")])
        #expect(try db.exerciseIds(absentFrom: []).isEmpty)
    }

    @Test("a session this device LOGGED is never overwritten by the pull")
    func theEventLogWins() async throws {
        // The invariant the whole event-sourcing design rests on: `workout_sets`
        // is a fold over `set_events`, and a pulled row would be deleted by the
        // very next append — after looking, briefly, like it had worked.
        let db = try store()
        try await db.writer.write { conn in
            try WorkoutSession(id: "s1", userId: "u1", dayKey: "legs_a", date: "2026-09-02",
                               startedAt: Date(timeIntervalSince1970: 1_788_000_000)).insert(conn)
        }
        try db.appendSet(sessionId: "s1", setId: "mine", SetSnapshot(
            exerciseId: "onyx-hack-squat", setIndex: 1, weightKg: 102.5, reps: 9
        ))

        let remote = FakeMirror()
        await remote.put("workout_sessions", [session("s1", startedAt: iso(0), updatedAt: iso(0))])
        await remote.put("workout_sets", [set("stale", session: "s1", number: 1)])
        await remote.put("exercises", [])
        _ = try await TrainingPuller(database: db, remote: remote, userId: "u1").refresh()

        let sets = try db.sets(sessionId: "s1")
        #expect(sets.count == 1)
        #expect(sets[0].id == "mine", "the fold's row survived")
        #expect(sets[0].weightKg == 102.5)
    }

    @Test("a session with unsynced local work keeps its pending flag")
    func pendingFlagSurvivesThePull() async throws {
        let db = try store()
        try await db.writer.write { conn in
            try WorkoutSession(id: "s1", userId: "u1", dayKey: "legs_a", date: "2026-09-02",
                               startedAt: Date(timeIntervalSince1970: 1_788_000_000),
                               isPendingSync: true).insert(conn)
        }
        let remote = FakeMirror()
        await remote.put("workout_sessions", [session("s1", startedAt: iso(0), updatedAt: iso(0))])
        await remote.put("workout_sets", [])
        await remote.put("exercises", [])
        _ = try await TrainingPuller(database: db, remote: remote, userId: "u1").refresh()

        // The server's copy of the row is not evidence that THIS device's queued
        // events have landed. Clearing the flag here would hide the queue.
        #expect(try db.session(id: "s1")?.isPendingSync == true)
    }

    @Test("the cursor moves only after the sets have landed")
    func cursorWaitsForTheSets() async throws {
        let db = try store()
        let remote = FakeMirror()
        await remote.put("workout_sessions", [session("s1", startedAt: iso(0), updatedAt: iso(500))])
        await remote.put("workout_sets", [set("set-1", session: "s1", number: 1)])
        await remote.put("exercises", [])
        _ = try await TrainingPuller(database: db, remote: remote, userId: "u1").refresh()

        let cursor = try #require(try db.mirrorCursor(table: "workout_sessions"))
        #expect(abs(cursor.timeIntervalSince1970 - (1_788_000_000 + 500)) < 1)
    }
}

// MARK: - Realtime

private actor RecordingRefresher: MirrorRefreshing {
    var calls: [String?] = []
    func refresh(table: String?) async { calls.append(table) }
}

@Suite("Realtime coalescing")
struct MirrorCoalescerTests {

    private let window = Duration.milliseconds(20)

    /// Long enough for the debounce to fire, short enough not to slow the suite.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }

    @Test("a burst about one table is one refresh")
    func burstCollapses() async throws {
        // A session commit arrives as a session row plus thirty set rows. Without
        // a window that is thirty-one notifications and thirty-one refetches for
        // one logical event.
        let refresher = RecordingRefresher()
        let coalescer = MirrorCoalescer(refresher: refresher, window: window)
        for _ in 0..<30 { await coalescer.note("daily_logs") }
        try await settle()

        #expect(await refresher.calls == ["daily_logs"])
    }

    @Test("the training trio collapses to a single pull")
    func trainingTablesCollapse() async throws {
        let refresher = RecordingRefresher()
        let coalescer = MirrorCoalescer(refresher: refresher, window: window)
        await coalescer.note("workout_sessions")
        await coalescer.note("workout_sets")
        await coalescer.note("exercises")
        try await settle()

        // `nil` is the trio. Asking for `workout_sets` alone would be a query
        // with no cursor to use — a set edit is found through its session.
        #expect(await refresher.calls == [nil])
    }

    @Test("unrelated tables each get their own pull, and nothing else does")
    func distinctTablesEachRefresh() async throws {
        let refresher = RecordingRefresher()
        let coalescer = MirrorCoalescer(refresher: refresher, window: window)
        await coalescer.note("daily_logs")
        await coalescer.note("sleep_sessions")
        await coalescer.note("daily_logs")
        try await settle()

        let calls = await refresher.calls
        #expect(calls.count == 2)
        #expect(Set(calls.compactMap { $0 }) == ["daily_logs", "sleep_sessions"])
    }

    @Test("draining twice does not pull twice")
    func drainIsNotRepeated() async throws {
        let refresher = RecordingRefresher()
        let coalescer = MirrorCoalescer(refresher: refresher, window: window)
        await coalescer.note("plans")
        await coalescer.drain()
        await coalescer.drain()
        #expect(await refresher.calls == ["plans"])
        #expect(await coalescer.noted.isEmpty)
    }

    @Test("the subscription list is derived, so a table cannot fall off it")
    func subscriptionListIsDerived() {
        // The web app's list was hand-maintained and `schedule_overrides` was
        // missing from it, which is half of why a rest-day swap on the phone
        // never reached the laptop.
        let tables = Set(MirrorRealtime.tables)
        #expect(tables.count == MirrorCatalogue.tables.count + 3)
        #expect(tables.contains("schedule_overrides"))
        #expect(tables.isSuperset(of: MirrorRealtime.trainingTables))
    }
}
