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

    // MARK: - The library's batch (Precision A1)

    @Test("the batch answers every name exactly as the single lookup does, in one read")
    func batchAgreesWithSingle() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try db.writer.write { conn in
            try Exercise(id: "uuid-1", name: name).insert(conn)
            try Exercise(id: "uuid-2", name: "Lateral Raise").insert(conn)
            try Exercise(id: "uuid-3", name: "Hack Squat").insert(conn)
            try session(conn, "a", "2026-09-01", dayKey: "push_a")
            try set(conn, "a1", in: "a", index: 1, 30, 12)
            try set(conn, "a2", in: "a", exercise: "uuid-2", index: 2, 10, 15)
            try set(conn, "a3", in: "a", exercise: "uuid-2", index: 3, 5, 20, type: "dropset")
            try session(conn, "b", "2026-09-08", dayKey: "pull_a")
            // The slug, the pair and the warm-up: every rule the single
            // lookup applies, crossed once.
            try set(conn, "b1", in: "b", exercise: ExerciseSlug.id(name), index: 1, 32.5, 11)
            try set(conn, "b2", in: "b", exercise: "uuid-2", index: 1, 12.5, 12, side: "left", pair: "p")
            try set(conn, "b3", in: "b", exercise: "uuid-2", index: 2, 10, 14, side: "right", pair: "p")
            try set(conn, "b4", in: "b", exercise: "uuid-3", index: 3, 60, 10, type: "warmup")
            try session(conn, "live", "2026-09-22", dayKey: "upper_a")
            try set(conn, "l1", in: "live", index: 1, 35, 10)
        }
        let names = [name, "Lateral Raise", "Hack Squat", "Never Lifted"]
        let batch = try db.lastWorkingSets(names: names, userId: user, excludingSession: "live")
        for n in names {
            #expect(batch[n] == (try db.lastWorkingSet(named: n, userId: user, excludingSession: "live")), "\(n)")
        }
        #expect(batch[name]?.weightKg == 32.5)
        #expect(batch["Lateral Raise"] == LastWorkingSet(weightKg: 10, reps: 12, date: "2026-09-08"), "the pair at its weaker side")
        #expect(batch["Hack Squat"] == nil, "warm-ups only is not evidence")
        #expect(batch["Never Lifted"] == nil)
    }

    @Test("recent is the last distinct movements, newest first, this account only")
    func recentNewestFirst() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try db.writer.write { conn in
            try Exercise(id: "uuid-1", name: name).insert(conn)
            try Exercise(id: "uuid-2", name: "Lateral Raise").insert(conn)
            try Exercise(id: "uuid-3", name: "Hack Squat").insert(conn)
            try Exercise(id: "uuid-4", name: "Leg Press").insert(conn)
            try session(conn, "old", "2026-09-01", dayKey: "legs_a")
            try set(conn, "o1", in: "old", exercise: "uuid-3", index: 1, 100, 10)
            try set(conn, "o2", in: "old", exercise: "uuid-4", index: 2, 200, 10)
            try session(conn, "new", "2026-09-08", dayKey: "upper_a")
            try set(conn, "n1", in: "new", index: 1, 30, 12)
            try set(conn, "n2", in: "new", exercise: "uuid-2", index: 2, 10, 15)
            // Hack Squat again, older than today's session but newer than
            // its first appearance: distinct means it is listed once.
            try session(conn, "mid", "2026-09-05", dayKey: "legs_b")
            try set(conn, "m1", in: "mid", exercise: "uuid-3", index: 1, 110, 8)
            try session(conn, "theirs", "2026-09-20", dayKey: "x", user: "u2")
            try set(conn, "t1", in: "theirs", exercise: "uuid-4", index: 1, 1, 1)
        }
        // Within a session the LAST movement performed is the most recent.
        #expect(try db.recentMovements(userId: user, limit: 10) == ["Lateral Raise", name, "Hack Squat", "Leg Press"])
        #expect(try db.recentMovements(userId: user, limit: 2) == ["Lateral Raise", name])
        #expect(try db.recentMovements(userId: user, limit: 10, excludingSession: "new") == ["Hack Squat", "Leg Press"])
    }
}
