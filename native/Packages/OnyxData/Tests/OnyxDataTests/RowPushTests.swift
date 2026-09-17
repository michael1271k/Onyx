import Foundation
import GRDB
import Supabase
import OnyxCore
import Testing
@testable import OnyxData

/// The write half of the mirror, recorded.
private actor RecordingPush: MirrorPushRemote {
    /// Table → the JSON bodies it was sent, in order.
    var sent: [(table: String, conflict: String, json: String, nulls: [String])] = []
    var deleted: [RowDeleteRef] = []
    var failing: Set<String> = []
    var errors: [String: any Error] = [:]
    func fail(_ table: String, with error: any Error) { errors[table] = error }

    func fail(_ table: String) { failing.insert(table) }

    func upsertRow<T: Encodable & Sendable>(_ row: T, table: String, conflict: String, nulls: [String]) async throws {
        if let error = errors[table] { throw error }
        if failing.contains(table) { throw URLError(.notConnectedToInternet) }
        let data = try OnyxJSON.encoder.encode(row)
        sent.append((table, conflict, String(decoding: data, as: UTF8.self), nulls))
    }

    func deleteRow(table: String, key: [String: String]) async throws {
        if failing.contains(table) { throw URLError(.notConnectedToInternet) }
        deleted.append(RowDeleteRef(table: table, key: key))
    }
}

/// The workout half, which these tests never exercise.
private struct IdleSyncRemote: SyncRemote {
    func exerciseCatalogue() async throws -> [RemoteExercise] { [] }
    func upsertSessions(_ rows: [RemoteSessionRow], ignoreDuplicates: Bool) async throws {}
    func upsertSets(_ rows: [RemoteSetRow]) async throws {}
    func deleteSets(ids: [String]) async throws {}
}

@Suite("Pushing a mirrored row")
struct RowPushTests {

    private let user = "u1"

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    private func engine(_ db: AppDatabase, _ push: RecordingPush) -> SyncEngine {
        SyncEngine(database: db, remote: IdleSyncRemote(), rows: push)
    }

    private func seedGoals(_ db: AppDatabase, calorieGoal: Int) throws {
        try db.writer.write { conn in
            try UserGoalRow(
                id: "g1", userId: user, calorieGoal: calorieGoal, contextMode: "normal",
                createdAt: Date(), updatedAt: Date(), autoLogSupplements: false,
                activeProgram: "helix5", dayCutoffHour: 0, unitSystem: "metric",
                reduceMotion: false, timezone: "Asia/Jerusalem", trackRpe: true
            ).save(conn)
        }
    }

    // MARK: The conflict target

    @Test("the conflict target is the NATURAL key wherever Postgres has one")
    func naturalKeys() throws {
        // Introspected from `pg_constraint`, not guessed. Upserting `daily_logs`
        // on `id` would insert a second row for a day the server already holds
        // under a different uuid, and then die on `daily_logs_user_id_date_key`
        // on every retry for the life of the install.
        func conflict(_ table: String) throws -> String {
            try #require(MirrorCatalogue.byName[table]).conflict
        }
        #expect(try conflict("daily_logs") == "user_id,date")
        #expect(try conflict("daily_metrics") == "user_id,date")
        #expect(try conflict("daily_scores") == "user_id,date")
        #expect(try conflict("nutrition_entries") == "user_id,date,meal_type")
        #expect(try conflict("user_goals") == "user_id")
        // Everything else has only its primary key.
        #expect(try conflict("water_intake") == "id")
        #expect(try conflict("sleep_sessions") == "id")
    }

    @Test("every mirrored table can be pushed")
    func catalogueIsComplete() {
        #expect(MirrorCatalogue.byName.count == MirrorCatalogue.tables.count)
    }

    // MARK: The waist (W3)

    @Test("a waist lands on the day, survives the mirror and rides the push")
    func waistRoundTrips() async throws {
        let db = try store()
        let date = "2026-09-17"
        try db.saveBodyMetrics(userId: user, date: date) {
            $0.weightKg = 64.8
            $0.waistCm = 81.5
        }

        // ── THE MIRROR ──────────────────────────────────────────────────────
        // `MirrorModels.swift` is GENERATED from `native/schema/supabase.json`,
        // so this is really a check that the column was added to the fixture and
        // the generator run — a hand-edited model would pass a compile and still
        // fail here on a fresh store, which creates its tables from that source.
        let log = try await db.writer.read { try DailyLogRow.fetchOne($0) }
        #expect(log?.waistCm == 81.5)

        // It is the DAY's column and not the ledger's: `body_composition` is the
        // HealthKit twin and HealthKit has no waist type.
        let ledger = try await db.writer.read { try BodyCompositionRow.fetchOne($0) }
        #expect(ledger?.weightKg == 64.8)

        // ── AND THE PUSH ────────────────────────────────────────────────────
        let push = RecordingPush()
        _ = try await engine(db, push).drain()
        let sent = await push.sent
        let day = try #require(sent.first { $0.table == "daily_logs" })
        #expect(day.json.contains("\"waist_cm\":81.5"), "\(day.json)")

        // A day with NO waist must not send the key at all — `encodeIfPresent`
        // is what keeps a merge from blanking a column, and a `"waist_cm":null`
        // in the body would erase a figure another device had written.
        let other = try store()
        try other.saveBodyMetrics(userId: user, date: date) { $0.weightKg = 64.8 }
        let quiet = RecordingPush()
        _ = try await engine(other, quiet).drain()
        let quietSent = await quiet.sent
        let quietDay = try #require(quietSent.first { $0.table == "daily_logs" })
        #expect(!quietDay.json.contains("waist_cm"), "\(quietDay.json)")
    }

    @Test("a day whose only reading is a waist still counts as a reading")
    func aWaistAloneIsAReading() throws {
        let db = try store()
        try db.saveBodyMetrics(userId: user, date: "2026-09-10") { $0.waistCm = 82.0 }
        // `latestBodyReading` is what pre-fills the InBody sheet. Before W3 its
        // `IS NOT NULL` list did not name this column, so a waist-only day was
        // invisible to the carry-forward and the next weigh-in opened blank.
        let carried = try db.latestBodyReading(userId: user, before: "2026-09-17")
        #expect(carried?.waistCm == 82.0)
    }

    // MARK: Draining

    @Test("the row is read at drain time, never carried in the payload")
    func payloadCarriesNoSnapshot() async throws {
        let db = try store()
        try seedGoals(db, calorieGoal: 1955)
        try db.enqueueRowUpsert(table: "user_goals", id: "g1")

        // Edited AFTER queuing. A queued snapshot would send the stale figure.
        try seedGoals(db, calorieGoal: 1885)

        let push = RecordingPush()
        let report = try await engine(db, push).drain()

        #expect(report.pushed == 1)
        let sent = await push.sent
        #expect(sent.count == 1)
        #expect(sent[0].table == "user_goals")
        #expect(sent[0].json.contains("\"calorie_goal\":1885"))
    }

    @Test("five edits before a signal are one upload")
    func editsCollapse() async throws {
        let db = try store()
        try seedGoals(db, calorieGoal: 1955)
        for _ in 0..<5 { try db.enqueueRowUpsert(table: "user_goals", id: "g1") }

        #expect(try db.pendingOutbox().count == 1)
        let push = RecordingPush()
        _ = try await engine(db, push).drain()
        #expect(await push.sent.count == 1)
    }

    @Test("a replay writes byte-identical bytes")
    func replayIsANoOp() async throws {
        let db = try store()
        try seedGoals(db, calorieGoal: 1955)
        try db.enqueueRowUpsert(table: "user_goals", id: "g1")

        let push = RecordingPush()
        _ = try await engine(db, push).drain()
        try db.enqueueRowUpsert(table: "user_goals", id: "g1")
        _ = try await engine(db, push).drain()

        let sent = await push.sent
        #expect(sent.count == 2)
        #expect(sent[0].json == sent[1].json)
    }

    @Test("the server's own timestamps are not sent")
    func timestampsAreStripped() throws {
        // `updated_at` is the DELTA CURSOR. A phone three minutes slow that
        // stamps a brand-new row in the past writes a row every other device's
        // `>= cursor` filter steps straight over — permanently.
        //
        // Stripping happens in `PostgRESTMirrorRemote`, which needs a live
        // client; what is asserted here is the fact it relies on — that both
        // columns are present in the encoded row and can therefore be removed.
        let row = UserGoalRow(
            id: "g1", userId: user, contextMode: "normal",
            createdAt: Date(), updatedAt: Date(), autoLogSupplements: false,
            activeProgram: "helix5", dayCutoffHour: 0, unitSystem: "metric",
            reduceMotion: false, timezone: "Asia/Jerusalem", trackRpe: true
        )
        let json = String(decoding: try OnyxJSON.encoder.encode(row), as: UTF8.self)
        #expect(json.contains("\"updated_at\""))
        #expect(json.contains("\"created_at\""))
    }

    @Test("a locally-written row cannot drag the delta cursor forward")
    func localWriteDoesNotMoveTheCursor() async throws {
        let db = try store()
        // A phone running fast: the ingest stamps "now" as the device sees it.
        let skewed = Date().addingTimeInterval(600)
        try db.ingest(HealthPayload(date: "2026-09-03", values: [.steps: 8000]), userId: user, now: skewed)

        // `MirrorPuller` sets each cursor to max(updated_at) read back out of
        // the LOCAL table, and asks the server for everything at or after it.
        // A device-stamped row here would push the cursor ten minutes into the
        // future, and every server row written in that window would be stepped
        // over and never pulled again.
        let maxima = db.maxTimestamp(table: "daily_logs", column: "updated_at")
        #expect(maxima == AppDatabase.localWriteTimestamp)
        #expect((maxima ?? .distantFuture) < Date())
    }

    @Test("a row deleted locally fails its item rather than vanishing")
    func missingRowIsRecorded() async throws {
        let db = try store()
        try db.enqueueRowUpsert(table: "user_goals", id: "ghost")

        let push = RecordingPush()
        let report = try await engine(db, push).drain()

        #expect(report.failed == 1)
        #expect(await push.sent.isEmpty)
        let item = try #require(try db.pendingOutbox().first)
        #expect(item.lastError?.contains("not in the local store") == true)
        // Kept, not dropped: the row it names was real when it was queued.
        #expect(item.attempts == 1)
    }

    @Test("a table the catalogue does not know is kept and explained")
    func unknownTableIsKept() async throws {
        let db = try store()
        try db.enqueueRowUpsert(table: "body_measurements", id: "x")

        let push = RecordingPush()
        let report = try await engine(db, push).drain()

        #expect(report.failed == 1)
        let item = try #require(try db.pendingOutbox().first)
        #expect(item.lastError?.contains("not in the mirror catalogue") == true)
    }

    @Test("one unreachable table does not abandon the rest of the batch")
    func failuresAreIsolated() async throws {
        let db = try store()
        try seedGoals(db, calorieGoal: 1955)
        try await db.writer.write { conn in
            try DailyMetricRow(
                id: "m1", userId: user, date: "2026-09-03", steps: 8000,
                createdAt: Date(), updatedAt: Date()
            ).insert(conn)
        }
        try db.enqueueRowUpsert(table: "user_goals", id: "g1")
        try db.enqueueRowUpsert(table: "daily_metrics", id: "m1")

        let push = RecordingPush()
        await push.fail("user_goals")
        let report = try await engine(db, push).drain()

        #expect(report.pushed == 1)
        #expect(report.failed == 1)
        #expect(await push.sent.map(\.table) == ["daily_metrics"])
    }

    /// Coverage, not a regression test: `pushRows` never acknowledged any error,
    /// so this passed before W1 too. The regression test for the PGRST205 drop
    /// is `SyncEngineTests.schemaCacheMissHoldsTheItem` (set_events), which
    /// fails on the pre-W1 `isMissingRelation`. Keep both.
    @Test("a PostgREST schema-cache miss on a mirrored row is held, attempts counted, nothing dropped")
    func schemaCacheMissIsHeld() async throws {
        let db = try store()
        try seedGoals(db, calorieGoal: 1955)
        try db.enqueueRowUpsert(table: "user_goals", id: "g1")

        let push = RecordingPush()
        await push.fail("user_goals", with: PostgrestError(
            details: nil, hint: nil, code: "PGRST205",
            message: "Could not find the table 'public.user_goals' in the schema cache"
        ))
        let report = try await engine(db, push).drain()

        #expect(report.pushed == 0 && report.failed == 1)
        let item = try #require(try db.pendingOutbox().first)
        #expect(item.attempts == 1)
        #expect(item.lastError?.contains("PGRST205") == true)
        #expect(item.nextAttemptAt != nil, "and it backs off rather than spinning")
    }

    @Test("nothing is left reserved after a drain")
    func nothingStrandedInFlight() async throws {
        let db = try store()
        try seedGoals(db, calorieGoal: 1955)
        try db.enqueueRowUpsert(table: "user_goals", id: "g1")

        let push = RecordingPush()
        await push.fail("user_goals")
        _ = try await engine(db, push).drain()

        // A row left `in_flight` is invisible to every future drain and comes
        // back only at the next cold launch — on a phone that is never
        // force-quit, that can be days.
        let stranded = try await db.writer.read { conn in
            try OutboxItem.filter(Column("status") == "in_flight").fetchCount(conn)
        }
        #expect(stranded == 0)
    }

    @Test("an engine with no push remote holds the items rather than losing them")
    func noRemoteKeepsTheWork() async throws {
        let db = try store()
        try seedGoals(db, calorieGoal: 1955)
        try db.enqueueRowUpsert(table: "user_goals", id: "g1")

        let engine = SyncEngine(database: db, remote: IdleSyncRemote())
        let report = try await engine.drain()

        #expect(report.failed == 1)
        #expect(try db.pendingOutbox().count == 1)
    }

    // MARK: Clears and deletes

    @Test("a cleared column is carried to the remote, and survives the collapse")
    func clearsAccumulate() async throws {
        let db = try store()
        try seedGoals(db, calorieGoal: 1955)
        try db.enqueueRowUpsert(table: "user_goals", id: "g1", nulls: ["active_lever"])
        // A later edit before a signal REPLACES the item — and must not lose
        // the clear, or the server keeps a lever the user released.
        try db.enqueueRowUpsert(table: "user_goals", id: "g1")

        let pending = try db.pendingOutbox()
        #expect(pending.count == 1)
        let ref = try OnyxJSON.decoder.decode(RowRef.self, from: pending[0].payload)
        #expect(ref.nulls == ["active_lever"])

        let push = RecordingPush()
        _ = try await engine(db, push).drain()
        #expect(await push.sent.first?.nulls == ["active_lever"])
    }

    @Test("an item queued by an earlier build, without `nulls`, still decodes")
    func legacyRowRefDecodes() throws {
        let ref = try OnyxJSON.decoder.decode(
            RowRef.self, from: Data(#"{"table":"user_goals","id":"g1"}"#.utf8)
        )
        #expect(ref == RowRef(table: "user_goals", id: "g1"))
    }

    @Test("a delete drains as a DELETE by key, and drops the pending upsert")
    func deleteDrains() async throws {
        let db = try store()
        try seedGoals(db, calorieGoal: 1955)
        try db.enqueueRowUpsert(table: "user_goals", id: "g1")
        try await db.writer.write { conn in
            try AppDatabase.enqueueRowDelete(table: "user_goals", key: ["id": "g1"], in: conn)
        }
        let pending = try db.pendingOutbox()
        #expect(pending.count == 1)
        #expect(pending[0].kind == SyncKind.rowDelete)

        let push = RecordingPush()
        let report = try await engine(db, push).drain()
        #expect(report.pushed == 1)
        #expect(await push.sent.isEmpty)
        #expect(await push.deleted == [RowDeleteRef(table: "user_goals", key: ["id": "g1"])])
        #expect(try db.pendingOutbox().isEmpty)
    }

    @Test("re-creating a deleted row supersedes the delete")
    func recreateSupersedesDelete() throws {
        let db = try store()
        try seedGoals(db, calorieGoal: 1955)
        try db.writer.write { conn in
            try AppDatabase.enqueueRowDelete(table: "user_goals", key: ["id": "g1"], in: conn)
        }
        try db.enqueueRowUpsert(table: "user_goals", id: "g1")
        let pending = try db.pendingOutbox()
        #expect(pending.count == 1)
        #expect(pending[0].kind == SyncKind.rowUpsert)
    }

    @Test("a composite delete is keyed the way its upsert is")
    func compositeDeleteKey() throws {
        // The two idempotency keys must agree on the id, or a delete cannot
        // find the upsert it is meant to supersede.
        let db = try store()
        try db.writer.write { conn in
            try AppDatabase.enqueueRowUpsert(
                table: "supplement_log", id: AppDatabase.rowID(["u1", "2026-09-03", "creatine"]), in: conn
            )
            try AppDatabase.enqueueRowDelete(
                table: "supplement_log",
                key: ["user_id": "u1", "date": "2026-09-03", "item_key": "creatine"],
                in: conn
            )
        }
        let pending = try db.pendingOutbox()
        #expect(pending.count == 1)
        #expect(pending[0].kind == SyncKind.rowDelete)
    }

    @Test("a delete addressed by half a key is refused, not guessed")
    func incompleteKeyIsRefused() throws {
        let db = try store()
        #expect(throws: RowPushError.self) {
            try db.writer.write { conn in
                try AppDatabase.enqueueRowDelete(
                    table: "supplement_log", key: ["user_id": "u1", "date": "2026-09-03"], in: conn
                )
            }
        }
    }
}

// MARK: - Preferences

@Suite("Preferences")
struct PreferencesTests {

    private let user = "u1"

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    @Test("with no row at all, the fallback stands")
    func fallback() throws {
        let db = try store()
        #expect(try db.preferences(userId: user) == .fallback)
    }

    @Test("the current columns win, and the legacy ones are the fallback")
    func legacyColumnsAreFallbacks() throws {
        let db = try store()
        try db.writer.write { conn in
            try UserGoalRow(
                id: "g1", userId: user, contextMode: "normal",
                // `onyx5` is the real dead value still sitting in
                // `active_program` — read alone, it names a plan that no longer
                // exists. Hydration read exactly this column for months.
                goalPreset: "bulk", createdAt: Date(), updatedAt: Date(),
                autoLogSupplements: false, activeProgram: "onyx5",
                dayCutoffHour: 0, unitSystem: "imperial", reduceMotion: true,
                timezone: "Asia/Jerusalem", activePlan: "helix5", trackRpe: false
            ).insert(conn)
        }
        let prefs = try db.preferences(userId: user)
        #expect(prefs.activePlan == "helix5", "the current column wins")
        #expect(prefs.activePhase == "bulk", "goal_preset is a correct fallback for active_phase")
        #expect(prefs.unitSystem == "imperial")
        #expect(prefs.reduceMotion)
        #expect(!prefs.trackRpe)
    }

    @Test("a phase change writes BOTH spellings and queues the row")
    func phaseWritesBothColumns() throws {
        let db = try store()
        try db.updatePreferences(userId: user) { $0.activePhase = "bulk" }

        let row = try #require(try db.userGoals(userId: user))
        // Leaving the legacy column stale is exactly how `active_program` came
        // to name a plan that no longer exists.
        #expect(row.activePhase == "bulk")
        #expect(row.goalPreset == "bulk")

        let queued = try #require(try db.pendingOutbox().first)
        #expect(queued.kind == SyncKind.rowUpsert)
        #expect(try SyncEngine.rowRef(of: queued).table == "user_goals")
    }

    @Test("the week start is derived from the end day the column stores")
    func weekStart() throws {
        let db = try store()
        // `week_end_day` 0 (Sunday) ⇒ the week starts Monday.
        try db.updatePreferences(userId: user) { $0.weekEndDay = 0 }
        #expect(try db.preferences(userId: user).weekStartDay == 1)
        try db.updatePreferences(userId: user) { $0.weekEndDay = 6 }
        #expect(try db.preferences(userId: user).weekStartDay == 0)
    }

    @Test("two changes before a drain are one queued row")
    func changesCollapse() throws {
        let db = try store()
        try db.updatePreferences(userId: user) { $0.trackRpe = false }
        try db.updatePreferences(userId: user) { $0.unitSystem = "imperial" }
        #expect(try db.pendingOutbox().count == 1)
        let prefs = try db.preferences(userId: user)
        #expect(!prefs.trackRpe)
        #expect(prefs.unitSystem == "imperial")
    }
}
