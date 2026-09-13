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
/// The cases that matter are the ones a table-only migration gets wrong: an
/// event-backed session, which reprojection rebuilds from the log; and a slug
/// two rows answer to, which must be refused rather than guessed at.
@Suite("Adopting catalogue ids")
struct CatalogueIdMigrationTests {

    private func database() throws -> AppDatabase {
        try AppDatabase.inMemory(deviceId: "d1")
    }

    private func snapshot(_ exercise: String, _ index: Int = 1) -> SetSnapshot {
        SetSnapshot(exerciseId: exercise, setIndex: index, weightKg: 60, reps: 8, setType: "normal")
    }

    private func seed(_ db: AppDatabase, _ work: (Database) throws -> Void) throws {
        try db.writer.write { conn in
            try WorkoutSession(id: "s1", userId: "u1", dayKey: "legs_a", date: "2026-09-07")
                .insert(conn)
            try work(conn)
        }
    }

    private func ids(in db: AppDatabase) throws -> [String] {
        try db.writer.read { conn in
            try String.fetchAll(conn, sql: "SELECT exercise_id FROM workout_sets ORDER BY set_index")
        }
    }

    private func adopt(_ db: AppDatabase) throws {
        try db.writer.write { try AppDatabase.adoptCatalogueIds($0) }
    }

    @Test("the server's own slug column answers first")
    func adoptsBySlugColumn() throws {
        let db = try database()
        try seed(db) { conn in
            try Exercise(id: "uuid-hack", name: "Hack Squat", slug: "helix5-hack-squat").insert(conn)
            try WorkoutSet(
                id: "set-1", sessionId: "s1", exerciseId: "helix5-hack-squat",
                setIndex: 1, weightKg: 60, reps: 8, setType: "normal"
            ).insert(conn)
        }

        try adopt(db)

        #expect(try ids(in: db) == ["uuid-hack"])
    }

    @Test("a shadow row keyed by the slug is resolved through its name")
    func adoptsByShadowRowName() throws {
        let db = try database()
        try seed(db) { conn in
            // The pair a real device holds: the row the pull created, and the
            // one an older build inserted so a slug-stamped set had a target.
            try Exercise(id: "uuid-pec-deck", name: "Pec Deck").insert(conn)
            try Exercise(id: "helix5-pec-deck", name: "Pec Deck").insert(conn)
            try WorkoutSet(
                id: "set-2", sessionId: "s1", exerciseId: "helix5-pec-deck",
                setIndex: 1, weightKg: 40, reps: 12, setType: "normal"
            ).insert(conn)
        }

        try adopt(db)

        #expect(try ids(in: db) == ["uuid-pec-deck"])
    }

    @Test("the append event is remapped too, so a reprojection keeps the new id")
    func remapsTheEventLog() throws {
        let db = try database()
        try seed(db) { conn in
            try Exercise(id: "uuid-hack", name: "Hack Squat", slug: "helix5-hack-squat").insert(conn)
        }
        _ = try db.appendSet(sessionId: "s1", snapshot("helix5-hack-squat"))

        try adopt(db)
        #expect(try ids(in: db) == ["uuid-hack"])

        // The gesture that used to undo it: any edit reprojects the session
        // from the log, and the log used to still say `helix5-hack-squat`.
        try db.reprojectAll()
        #expect(try ids(in: db) == ["uuid-hack"])
    }

    @Test("a slug two rows answer to is refused, not guessed at")
    func refusesAnAmbiguousSlug() throws {
        let db = try database()
        try seed(db) { conn in
            // `Crunch Machine` and `Crunch (Machine)` slug identically and
            // differ in `is_bodyweight`. Picking one merges the ladders.
            try Exercise(id: "uuid-a", name: "Crunch Machine", slug: "helix5-crunch-machine").insert(conn)
            try Exercise(id: "uuid-b", name: "Crunch (Machine)", slug: "helix5-crunch-machine").insert(conn)
            try WorkoutSet(
                id: "set-3", sessionId: "s1", exerciseId: "helix5-crunch-machine",
                setIndex: 1, weightKg: 57.5, reps: 10, setType: "normal"
            ).insert(conn)
        }

        try adopt(db)

        #expect(try ids(in: db) == ["helix5-crunch-machine"])
    }

    @Test("a shadow row whose name two catalogue rows share is refused as well")
    func refusesAnAmbiguousName() throws {
        let db = try database()
        try seed(db) { conn in
            try Exercise(id: "uuid-1", name: "Leg Press").insert(conn)
            try Exercise(id: "uuid-2", name: "leg press ").insert(conn)
            try Exercise(id: "helix5-leg-press", name: "Leg Press").insert(conn)
            try WorkoutSet(
                id: "set-4", sessionId: "s1", exerciseId: "helix5-leg-press",
                setIndex: 1, weightKg: 120, reps: 10, setType: "normal"
            ).insert(conn)
        }

        try adopt(db)

        #expect(try ids(in: db) == ["helix5-leg-press"])
    }

    @Test("a slug nothing claims keeps its id rather than losing the rep")
    func leavesAnUnresolvableSlugAlone() throws {
        let db = try database()
        try seed(db) { conn in
            try WorkoutSet(
                id: "set-5", sessionId: "s1", exerciseId: "helix5-movement-nothing-knows",
                setIndex: 1, weightKg: 20, reps: 20, setType: "normal"
            ).insert(conn)
        }

        try adopt(db)

        #expect(try ids(in: db) == ["helix5-movement-nothing-knows"])
    }

    @Test("a set already carrying the catalogue id is untouched, and running twice changes nothing")
    func isIdempotent() throws {
        let db = try database()
        try seed(db) { conn in
            try Exercise(id: "uuid-hack", name: "Hack Squat", slug: "helix5-hack-squat").insert(conn)
        }
        _ = try db.appendSet(sessionId: "s1", snapshot("uuid-hack", 1))
        _ = try db.appendSet(sessionId: "s1", snapshot("helix5-hack-squat", 2))

        try adopt(db)
        try adopt(db)

        #expect(try ids(in: db) == ["uuid-hack", "uuid-hack"])
    }
}
