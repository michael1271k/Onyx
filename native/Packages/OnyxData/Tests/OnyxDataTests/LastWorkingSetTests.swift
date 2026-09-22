import Foundation
import Testing
import GRDB
import OnyxCore
@testable import OnyxData

/// The mid-session add's "last time" (W3): the most recent working set of one
/// movement, across every session and every day key — and ONLY that. The
/// day-scoped seed is untouched; `ProgressionQueueTests.seedAndVerdictAgree`
/// still holds it to its own day.
@Suite("Last working set")
struct LastWorkingSetTests {
    private let user = "u1"
    private let name = "Face Pull"

    private func session(_ conn: Database, _ id: String, _ date: String, dayKey: String, user: String? = nil) throws {
        try WorkoutSession(id: id, userId: user ?? self.user, dayKey: dayKey, date: date, startedAt: Date()).insert(conn)
    }

    private func set(
        _ conn: Database, _ id: String, in session: String, exercise: String = "uuid-1", index: Int,
        _ kg: Double, _ reps: Int, type: String = "normal", side: String? = nil, pair: String? = nil
    ) throws {
        try WorkoutSet(
            id: id, sessionId: session, exerciseId: exercise, setIndex: index,
            weightKg: kg, reps: reps, setType: type, side: side, pairId: pair
        ).insert(conn)
    }

    @Test("any day key; the last working set of the newest session that lifted it")
    func acrossDayKeys() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try db.writer.write { conn in
            try Exercise(id: "uuid-1", name: name).insert(conn)
            try session(conn, "old", "2026-09-01", dayKey: "push_a")
            try set(conn, "o1", in: "old", index: 1, 50, 8)
            try set(conn, "o2", in: "old", index: 2, 52.5, 6)
            // Newer, on another split, and warm-ups only: not evidence.
            try session(conn, "warm", "2026-09-10", dayKey: "legs_b")
            try set(conn, "w1", in: "warm", index: 1, 20, 10, type: "warmup")
        }
        let last = try #require(try db.lastWorkingSet(named: name, userId: user))
        #expect(last == LastWorkingSet(weightKg: 52.5, reps: 6, date: "2026-09-01"))
        #expect(last.label == "52.5kg × 6", "the Previous column's own spelling")
    }

    @Test("every id the movement answers to, matched by name")
    func acrossIds() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try db.writer.write { conn in
            try Exercise(id: "uuid-1", name: name).insert(conn)
            try session(conn, "web", "2026-09-01", dayKey: "push_a")
            try set(conn, "a", in: "web", index: 1, 30, 12)
            // Logged here before the catalogue resolved it: the slug.
            try session(conn, "phone", "2026-09-08", dayKey: "pull_a")
            try set(conn, "b", in: "phone", exercise: ExerciseSlug.id(name), index: 1, 32.5, 11)
        }
        #expect(try db.lastWorkingSet(named: name, userId: user)?.weightKg == 32.5)
    }

    @Test("the session being logged is not its own last time")
    func excludesTheLiveSession() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try db.writer.write { conn in
            try Exercise(id: "uuid-1", name: name).insert(conn)
            try session(conn, "before", "2026-09-01", dayKey: "push_a")
            try set(conn, "a", in: "before", index: 1, 30, 12)
            try session(conn, "live", "2026-09-22", dayKey: "upper_a")
            try set(conn, "b", in: "live", index: 1, 35, 10)
        }
        #expect(try db.lastWorkingSet(named: name, userId: user, excludingSession: "live")?.weightKg == 30)
        #expect(try db.lastWorkingSet(named: name, userId: user)?.weightKg == 35)
    }

    @Test("a drop set closing the session is not the set you walk up to")
    func dropSetIsNotLastTime() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try db.writer.write { conn in
            try Exercise(id: "uuid-1", name: name).insert(conn)
            try session(conn, "s", "2026-09-01", dayKey: "push_a")
            try set(conn, "a", in: "s", index: 1, 30, 10)
            try set(conn, "b", in: "s", index: 2, 30, 9)
            try set(conn, "c", in: "s", index: 3, 15, 12, type: "dropset")
        }
        let last = try #require(try db.lastWorkingSet(named: name, userId: user))
        #expect((last.weightKg, last.reps) == (30, 9))
    }

    @Test("a genuine L/R pair is one set, at its weaker side")
    func pairFolds() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try db.writer.write { conn in
            try Exercise(id: "uuid-1", name: name).insert(conn)
            try session(conn, "s", "2026-09-01", dayKey: "push_a")
            try set(conn, "l", in: "s", index: 1, 22.5, 12, side: "left", pair: "p")
            try set(conn, "r", in: "s", index: 2, 20, 10, side: "right", pair: "p")
        }
        let last = try #require(try db.lastWorkingSet(named: name, userId: user))
        #expect((last.weightKg, last.reps) == (20, 10))
    }

    @Test("another account's ledger, and a movement never lifted, answer nothing")
    func nothing() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try db.writer.write { conn in
            try Exercise(id: "uuid-1", name: name).insert(conn)
            try session(conn, "theirs", "2026-09-01", dayKey: "push_a", user: "u2")
            try set(conn, "a", in: "theirs", index: 1, 30, 12)
        }
        #expect(try db.lastWorkingSet(named: name, userId: user) == nil)
        #expect(try db.lastWorkingSet(named: "Hack Squat", userId: user) == nil)
    }
}
