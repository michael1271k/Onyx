import Foundation
import GRDB
import Testing
@testable import OnyxData

/// What `v23.catalogueIds` is for.
///
/// ── THE SPLIT IT CLOSES ─────────────────────────────────────────────────────
/// A set logged on the phone before W6 carried `helix5-<name-slug>`; the same
/// movement pulled from the server carried the catalogue's uuid. Every reader
/// that keys on `exercise_id` saw two movements — the summary drew the exercise
/// twice, the volume fold split its tonnage, and a PR was measured against half
/// its own history. The logger now resolves the catalogue row before it writes;
/// this brings what is already on disk to the same rule.
///
/// Both resolution paths are asserted, and so is the refusal: a slug that
/// answers to nothing keeps its id, because it is still a logged rep.
@Suite("Adopting catalogue ids")
struct CatalogueIdMigrationTests {

    private func database() throws -> AppDatabase {
        try AppDatabase.inMemory(deviceId: "d1")
    }

    private func set(_ id: String, exercise: String) -> WorkoutSet {
        WorkoutSet(
            id: id, sessionId: "s1", exerciseId: exercise,
            setIndex: 1, weightKg: 60, reps: 8, setType: "normal"
        )
    }

    private func seed(_ db: AppDatabase, _ work: (Database) throws -> Void) throws {
        try db.writer.write { conn in
            try WorkoutSession(id: "s1", userId: "u1", dayKey: "legs_a", date: "2026-09-07")
                .insert(conn)
            try work(conn)
        }
    }

    private func exerciseId(of setId: String, in db: AppDatabase) throws -> String? {
        try db.writer.read { conn in
            try String.fetchOne(
                conn, sql: "SELECT exercise_id FROM workout_sets WHERE id = ?", arguments: [setId]
            )
        }
    }

    @Test("the server's own slug column answers first")
    func adoptsBySlugColumn() throws {
        let db = try database()
        try seed(db) { conn in
            try Exercise(id: "uuid-hack", name: "Hack Squat", slug: "helix5-hack-squat").insert(conn)
            try set("set-1", exercise: "helix5-hack-squat").insert(conn)
        }

        try db.writer.write { try AppDatabase.adoptCatalogueIds($0) }

        #expect(try exerciseId(of: "set-1", in: db) == "uuid-hack")
    }

    @Test("a shadow row keyed by the slug is resolved through its name")
    func adoptsByShadowRowName() throws {
        let db = try database()
        try seed(db) { conn in
            // The pair a real device holds: the row the pull created, and the
            // one this app inserted so a slug-stamped set had a target.
            try Exercise(id: "uuid-pec-deck", name: "Pec Deck").insert(conn)
            try Exercise(id: "helix5-pec-deck", name: "Pec Deck").insert(conn)
            try set("set-2", exercise: "helix5-pec-deck").insert(conn)
        }

        try db.writer.write { try AppDatabase.adoptCatalogueIds($0) }

        #expect(try exerciseId(of: "set-2", in: db) == "uuid-pec-deck")
    }

    @Test("a slug nothing claims keeps its id rather than losing the rep")
    func leavesAnUnresolvableSlugAlone() throws {
        let db = try database()
        try seed(db) { conn in
            try set("set-3", exercise: "helix5-movement-nothing-knows").insert(conn)
        }

        try db.writer.write { try AppDatabase.adoptCatalogueIds($0) }

        #expect(try exerciseId(of: "set-3", in: db) == "helix5-movement-nothing-knows")
    }

    @Test("a set already carrying the catalogue uuid is untouched, and running twice changes nothing")
    func isIdempotent() throws {
        let db = try database()
        try seed(db) { conn in
            try Exercise(id: "uuid-hack", name: "Hack Squat", slug: "helix5-hack-squat").insert(conn)
            try set("set-4", exercise: "uuid-hack").insert(conn)
            try set("set-5", exercise: "helix5-hack-squat").insert(conn)
        }

        try db.writer.write { try AppDatabase.adoptCatalogueIds($0) }
        try db.writer.write { try AppDatabase.adoptCatalogueIds($0) }

        #expect(try exerciseId(of: "set-4", in: db) == "uuid-hack")
        #expect(try exerciseId(of: "set-5", in: db) == "uuid-hack")
    }
}
