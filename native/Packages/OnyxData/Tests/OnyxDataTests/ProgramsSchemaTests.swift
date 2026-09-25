import Foundation
import Testing
import GRDB
import OnyxCore
@testable import OnyxData

// Precision E1: three nullable columns — `plans.goal_kind`, `plans.goal_target`,
// `routines.notes`. The founder pastes the DDL; until then a server row has
// none of them and a push must not name them.

@Suite("Precision E1 · program goals on the wire")
struct ProgramsSchemaTests {

    private actor RecordingPush: MirrorPushRemote {
        var sent: [(table: String, json: String, nulls: [String])] = []
        func upsertRow<T: Encodable & Sendable>(_ row: T, table: String, conflict: String, nulls: [String]) async throws {
            sent.append((table, String(decoding: try OnyxJSON.encoder.encode(row), as: UTF8.self), nulls))
        }
        func deleteRow(table: String, key: [String: String]) async throws {}
    }

    private struct IdleSyncRemote: SyncRemote {
        func exerciseCatalogue() async throws -> [RemoteExercise] { [] }
        func upsertSessions(_ rows: [RemoteSessionRow], ignoreDuplicates: Bool) async throws {}
        func upsertSets(_ rows: [RemoteSetRow]) async throws {}
        func deleteSets(ids: [String]) async throws {}
    }

    @Test("a plans row from a server without the goal columns decodes, goal nil")
    func oldPlanRowDecodes() throws {
        let json = #"{"id":"p1","user_id":"u1","name":"Onyx-5","program_id":"onyx5","active":true,"started_on":"2026-07-15","blurb":"Five","is_legacy":false,"sort":0}"#
        let row = try OnyxJSON.decoder.decode(PlanRow.self, from: Data(json.utf8))
        #expect(row.programId == "onyx5")
        #expect(row.goalKind == nil)
        #expect(row.goalTarget == nil)
    }

    @Test("a plans row carrying a goal decodes the kind and the target object")
    func newPlanRowDecodes() throws {
        let json = #"{"id":"p1","user_id":"u1","name":"Cut","program_id":"cut","is_legacy":false,"sort":1,"goal_kind":"cut","goal_target":{"target_weight_kg":72,"horizon_weeks":12}}"#
        let row = try OnyxJSON.decoder.decode(PlanRow.self, from: Data(json.utf8))
        #expect(row.goalKind == "cut")
        let target = try #require(row.goalTarget.flatMap { ProgramGoalTarget.decode($0.raw) })
        #expect(target.targetWeightKg == 72)
        #expect(target.horizonWeeks == 12)
    }

    @Test("a routines row from a server without notes decodes")
    func oldRoutineRowDecodes() throws {
        let json = #"{"user_id":"u1","program_id":"onyx5","day_key":"cb_a","label":"Upper A","weekday":0,"accent":1,"sort":0,"payload":{"version":1,"exercises":[]},"updated_at":"2026-09-10T00:00:00+00:00"}"#
        let row = try OnyxJSON.decoder.decode(RoutineRow.self, from: Data(json.utf8))
        #expect(row.notes == nil)
        #expect(RoutineDay(row).notes == nil)
    }

    /// A fresh store gets the columns from the regenerated creates; this is the
    /// store already on the phone, built before them.
    @Test("v40 adds the three columns to a store built before them, and keeps its rows")
    func migrationAltersAnExistingStore() throws {
        let queue = try DatabaseQueue()
        var migrator = AppDatabase.migrator
        migrator.eraseDatabaseOnSchemaChange = false
        try migrator.migrate(queue, upTo: "v38.otherIngredients")
        try queue.write { db in
            try db.execute(sql: "ALTER TABLE plans DROP COLUMN goal_kind")
            try db.execute(sql: "ALTER TABLE plans DROP COLUMN goal_target")
            try db.execute(sql: "ALTER TABLE routines DROP COLUMN notes")
            try db.execute(sql: "INSERT INTO plans (id, user_id, name, program_id) VALUES ('p1', 'u1', 'Onyx-5', 'onyx5')")
        }
        try migrator.migrate(queue)
        let row = try queue.read { try PlanRow.fetchOne($0, key: "p1") }
        #expect(row?.programId == "onyx5")
        #expect(row?.goalKind == nil)
        let plans = try queue.read { try Set($0.columns(in: "plans").map(\.name)) }
        #expect(plans.isSuperset(of: ["goal_kind", "goal_target"]))
        #expect(try queue.read { try $0.columns(in: "routines").map(\.name) }.contains("notes"))
    }

    @Test("a plan with no goal pushes no goal keys (the DDL may not be pasted yet)")
    func nilGoalStaysOffTheWire() async throws {
        let db = try AppDatabase.inMemory(deviceId: "e1-push")
        let id = try db.createPlan(userId: "u1", name: "Blank")
        #expect(!id.isEmpty)
        let push = RecordingPush()
        _ = try await SyncEngine(database: db, remote: IdleSyncRemote(), rows: push).drain()
        let plan = try #require(await push.sent.first { $0.table == "plans" })
        #expect(!plan.json.contains("goal_kind"))
        #expect(!plan.json.contains("goal_target"))
        #expect(!plan.nulls.contains("goal_kind"))
    }
}
