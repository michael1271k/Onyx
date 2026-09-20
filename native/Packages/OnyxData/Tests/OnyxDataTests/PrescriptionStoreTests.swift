import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

@Suite("Prescriptions — the store appends, and never overwrites")
struct PrescriptionStoreTests {
    private let user = "11111111-1111-1111-1111-111111111111"

    private func store() throws -> AppDatabase {
        try AppDatabase.inMemory(deviceId: "device-a")
    }

    @Test("a second paste for one movement is a second version, and the first survives")
    func appendingNeverOverwrites() throws {
        let db = try store()
        _ = try db.appendPrescriptions([
            Prescription(exercise: "RDL", loadKg: 30, sets: 3, repRange: "6–8", effectiveFrom: "2026-07-01"),
        ], userId: user)
        _ = try db.appendPrescriptions([
            Prescription(exercise: "RDL", loadKg: 40, sets: 3, repRange: "6–8", effectiveFrom: "2026-09-15"),
        ], userId: user)

        let all = try db.prescriptions(userId: user)
        #expect(all.count == 2)
        #expect(all.map(\.version) == [1, 2])
        #expect(all.map(\.loadKg) == [30, 40])
        // The instruction in force depends on the DAY, and the July one is
        // still there to answer for July.
        #expect(try db.currentPrescriptions(userId: user, on: "2026-09-20")["RDL"]?.loadKg == 40)
        #expect(try db.currentPrescriptions(userId: user, on: "2026-08-01")["RDL"]?.loadKg == 30)
    }

    @Test("the version is assigned by the STORE, whatever the draft claims")
    func theStoreOwnsTheOrdinal() throws {
        let db = try store()
        _ = try db.appendPrescriptions([
            Prescription(exercise: "RDL", loadKg: 30, effectiveFrom: "2026-07-01", version: 9),
        ], userId: user)
        // A draft's own `version` is ignored — the parser reads a block of text
        // and cannot know what the ledger already holds.
        #expect(try db.prescriptions(userId: user).first?.version == 1)
        // Two rows for one movement in ONE paste keep their order.
        _ = try db.appendPrescriptions([
            Prescription(exercise: "RDL", loadKg: 35, effectiveFrom: "2026-08-01"),
            Prescription(exercise: "RDL", loadKg: 40, effectiveFrom: "2026-09-01"),
        ], userId: user)
        #expect(try db.prescriptions(userId: user).map(\.version) == [1, 2, 3])
    }

    @Test("a ladder survives the round trip, and the name is canonicalised")
    func laddersAndNames() throws {
        let db = try store()
        _ = try db.appendPrescriptions([
            Prescription(
                exercise: "rdl", loadKg: 42.5, sets: 3, repRange: "8–12", rpeCap: 8,
                structure: .topsetBackoff, setLoads: [42.5, 37.5, 37.5],
                leadRule: .alternate, notes: "hinge", effectiveFrom: "2026-09-15"),
        ], userId: user)
        let p = try #require(try db.prescriptions(userId: user).first)
        #expect(p.setLoads == [42.5, 37.5, 37.5])
        #expect(p.structure == .topsetBackoff)
        #expect(p.leadRule == .alternate)
        #expect(p.rpeCap == 8)
        #expect(p.notes == "hinge")
        // `personal_records` keys on the canonical DISPLAY name, and so does
        // this — one movement, one key, across both tables.
        #expect(p.exercise == ExerciseAliases.canonicalName("rdl"))
    }

    @Test("a paste queues a push for every row it wrote")
    func theOutboxIsFed() throws {
        let db = try store()
        _ = try db.appendPrescriptions([
            Prescription(exercise: "RDL", loadKg: 40, effectiveFrom: "2026-09-15"),
            Prescription(exercise: "Lat Pulldown", loadKg: 50, effectiveFrom: "2026-09-15"),
        ], userId: user)
        // One item per row, keyed `row:<table>:<id>` — the shape every other
        // mirrored write queues.
        let keys = try db.read { conn in
            try String.fetchAll(conn, sql: "SELECT idempotency_key FROM outbox ORDER BY idempotency_key")
        }
        #expect(keys.count == 2)
        #expect(keys.allSatisfy { $0.hasPrefix("row:prescriptions:") })
    }
}
