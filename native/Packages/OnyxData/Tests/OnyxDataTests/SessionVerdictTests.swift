import Foundation
import Testing
import GRDB
import OnyxCore
@testable import OnyxData

/// Train's last-session verdict line (Precision B2, decision Q18): one line
/// that says what the last session of this split did against the one before
/// it — "+2.5 kg on 3 lifts · 2 PR · 4.4 t".
@Suite("Session verdict")
struct SessionVerdictTests {
    private let user = "u1"

    private func session(_ conn: Database, id: String, date: String, dayKey: String = "upper_b",
                         prCount: Int? = nil, volume: Double? = nil) throws {
        var row = WorkoutSession(id: id, userId: user, dayKey: dayKey, date: date,
                                 startedAt: LogicalDay.date(fromISO: date)!)
        row.endedAt = row.startedAt?.addingTimeInterval(3600)
        row.prCount = prCount
        row.totalVolumeKg = volume
        try row.insert(conn)
    }

    private func set(_ conn: Database, _ session: String, _ exercise: String, _ index: Int,
                     _ weight: Double, _ reps: Int, type: String = "working",
                     side: String? = nil, pair: String? = nil) throws {
        var row = WorkoutSet(id: "\(session)-\(exercise)-\(index)\(side ?? "")", sessionId: session,
                             exerciseId: exercise, setIndex: index, weightKg: weight, reps: reps, setType: type)
        row.side = side
        row.pairId = pair
        try row.insert(conn)
    }

    private func seededTwoSessions() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try db.writer.write { conn in
            for (id, name) in [("bench", "Chest Press"), ("row", "Seated Cable Row"),
                               ("curl", "Preacher Curl"), ("fly", "Pec Deck")] {
                try Exercise(id: id, name: name).insert(conn)
            }
            // The session before: the baseline.
            try session(conn, id: "a", date: "2026-09-11")
            try set(conn, "a", "bench", 1, 40, 10)
            try set(conn, "a", "row", 1, 50, 8)
            try set(conn, "a", "curl", 1, 20, 12)
            try set(conn, "a", "fly", 1, 45, 12)
            // The last session: bench and row +2.5 kg, curl more reps at the
            // same load, fly unchanged — and a heavier warm-up that is not
            // evidence of anything.
            try session(conn, id: "b", date: "2026-09-18", prCount: 2, volume: 4412)
            try set(conn, "b", "bench", 0, 60, 3, type: "warmup")
            try set(conn, "b", "bench", 1, 42.5, 10)
            try set(conn, "b", "row", 1, 52.5, 8)
            try set(conn, "b", "curl", 1, 20, 13)
            try set(conn, "b", "fly", 1, 45, 12)
            // Another split in between must not become the comparison.
            try session(conn, id: "x", date: "2026-09-15", dayKey: "lower_a")
            try set(conn, "x", "bench", 1, 90, 5)
        }
        return db
    }

    @Test("two seeded sessions: load gains, rep gains, records and tonnage in one line")
    func verdictOnTwoSessions() throws {
        let db = try seededTwoSessions()
        let verdict = try #require(try db.sessionVerdict(sessionId: "b", userId: user))
        #expect(verdict.loadGains == [2.5, 2.5])
        #expect(verdict.repLifts == 1)
        #expect(verdict.heldLifts == 1)
        #expect(verdict.lighterLifts == 0)
        #expect(verdict.line == "+2.5 kg on 2 lifts · +reps on 1 lift · 2 PRs · 4.4 t")
    }

    @Test("zero progress reads as held, never as a loss")
    func heldWording() {
        let tops = ["a": SessionVerdict.Top(weightKg: 40, reps: 10),
                    "b": SessionVerdict.Top(weightKg: 30, reps: 12),
                    "c": SessionVerdict.Top(weightKg: 20, reps: 12),
                    "d": SessionVerdict.Top(weightKg: 10, reps: 15),
                    "e": SessionVerdict.Top(weightKg: 0, reps: 20)]
        let verdict = SessionVerdict.build(current: tops, previous: tops, prCount: 0, tonnageKg: 4400)
        #expect(verdict.line == "Held 5 lifts · 4.4 t")
    }

    @Test("a lighter lift is said, and different gains read as a range")
    func lighterAndRange() {
        let previous = ["a": SessionVerdict.Top(weightKg: 40, reps: 10),
                        "b": SessionVerdict.Top(weightKg: 30, reps: 10),
                        "c": SessionVerdict.Top(weightKg: 20, reps: 10)]
        let current = ["a": SessionVerdict.Top(weightKg: 42.5, reps: 10),
                       "b": SessionVerdict.Top(weightKg: 35, reps: 8),
                       "c": SessionVerdict.Top(weightKg: 17.5, reps: 12)]
        let verdict = SessionVerdict.build(current: current, previous: previous, prCount: 1, tonnageKg: 3100)
        #expect(verdict.line == "+2.5–5 kg on 2 lifts · 1 lighter · 1 PR · 3.1 t")
    }

    @Test("no session before it: records and tonnage only")
    func firstOfSplit() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try db.writer.write { conn in
            try Exercise(id: "bench", name: "Chest Press").insert(conn)
            try session(conn, id: "only", date: "2026-09-18", prCount: 0, volume: 1200)
            try set(conn, "only", "bench", 1, 40, 10)
        }
        let verdict = try #require(try db.sessionVerdict(sessionId: "only", userId: user))
        #expect(verdict.line == "1.2 t")
    }

    @Test("a unilateral pair competes at its weaker side")
    func pairIsWeakerSide() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try db.writer.write { conn in
            try Exercise(id: "lat", name: "Single Arm Lateral Raise").insert(conn)
            try session(conn, id: "a", date: "2026-09-11", volume: 100)
            try set(conn, "a", "lat", 1, 10, 12, side: "L", pair: "p1")
            try set(conn, "a", "lat", 1, 10, 12, side: "R", pair: "p1")
            try session(conn, id: "b", date: "2026-09-18", volume: 100)
            // One side heavier: the pair is still a 10 kg set.
            try set(conn, "b", "lat", 1, 12.5, 12, side: "L", pair: "p2")
            try set(conn, "b", "lat", 1, 10, 12, side: "R", pair: "p2")
        }
        let verdict = try #require(try db.sessionVerdict(sessionId: "b", userId: user))
        #expect(verdict.line == "Held 1 lift · 0.1 t")
    }
}
