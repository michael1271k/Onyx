import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// Precision Lane C (Q12, seam 3): ONE baseline basis for the live deck and
/// the close path, the guard at the recorder, and the founder's Wide Grip.
@Suite("PR recorder — one basis, the guard, the Wide Grip")
struct PrBasisTests {

    private let user = "u1"
    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    private func records(_ db: AppDatabase) throws -> [PersonalRecordRow] {
        try db.writer.read { conn in
            try PersonalRecordRow.order(Column("exercise_key"), Column("axis")).fetchAll(conn)
        }
    }

    private func session(_ db: AppDatabase, id: String, date: String, key: String, name: String,
                         sets: [(Double, Int, String?)]) throws {
        try db.writer.write { conn in
            try Exercise(id: "ex-\(key)", name: name, slug: key).save(conn)
            let start = LogicalDay.date(fromISO: date)!
            try WorkoutSession(id: id, userId: user, dayKey: "cb_b", date: date, startedAt: start).insert(conn)
            for (i, s) in sets.enumerated() {
                try WorkoutSet(id: "\(id)-\(i)", sessionId: id, exerciseId: key, setIndex: i + 1,
                               weightKg: s.0, reps: s.1, setType: s.2 ?? "normal", est1rmKg: nil, foldOrder: i).insert(conn)
            }
        }
    }

    @Test("the live deck and the close path read the same bar: a standing record this device holds no set for")
    func liveAndCloseAgree() throws {
        let db = try store()
        try db.writer.write { conn in
            try Exercise(id: "ex-curl", name: "Seated Leg Curl", slug: "onyx-seated-leg-curl").save(conn)
            let old = LogicalDay.date(fromISO: "2026-08-01")!
            try WorkoutSession(id: "s-old", userId: user, dayKey: "legs_a", date: "2026-08-01",
                               startedAt: old, endedAt: old.addingTimeInterval(3600)).insert(conn)
            // The visible half: 50 × 11 = 550.
            try WorkoutSet(id: "old-1", sessionId: "s-old", exerciseId: "onyx-seated-leg-curl",
                           setIndex: 1, weightKg: 50, reps: 11).insert(conn)
            // The ledger's standing record, set by a session this device never pulled.
            try PersonalRecordRow(userId: user, exerciseKey: "Seated Leg Curl", axis: "volume",
                                  value: 700, sessionId: "s-remote", achievedOn: "2026-08-15").insert(conn)
            let today = LogicalDay.date(fromISO: "2026-09-25")!
            try WorkoutSession(id: "s-live", userId: user, dayKey: "legs_a", date: "2026-09-25", startedAt: today).insert(conn)
            try WorkoutSet(id: "live-1", sessionId: "s-live", exerciseId: "onyx-seated-leg-curl",
                           setIndex: 1, weightKg: 47.5, reps: 13).insert(conn)   // 617.5
        }
        let program = Program(id: "", label: "", days: [])
        let live = try db.livePrBaselines(
            userId: user, exerciseIds: ["onyx-seated-leg-curl"], excluding: "s-live", dayKey: "legs_a", program: program)
        let close = try db.writer.read { conn in
            try PrRecorder.baselines(
                conn, userId: user, exerciseIds: ["onyx-seated-leg-curl"], excluding: "s-live", date: "2026-09-25",
                dayKey: "legs_a", program: program, name: try PrRecorder.nameResolver(conn))
        }
        #expect(live == close)
        #expect(close.bestSetVolume.first { $0.key == "onyx-seated-leg-curl" }?.value == 700)

        _ = try db.closeSession(id: "s-live")
        #expect(try records(db).first { $0.axis == "volume" }?.value == 700, "617.5 is not a record against 700 — on the close path too")
    }

    @Test("a floor-only key is beatable at close — the onboarding 1RM floor")
    func floorOnlyBeatable() throws {
        let db = try store()
        try db.writer.write { conn in
            try PersonalRecordRow(userId: user, exerciseKey: "Hack Squat", axis: "weight",
                                  value: 100, sessionId: nil, achievedOn: "2026-08-10").insert(conn)
        }
        try session(db, id: "s1", date: "2026-09-25", key: "onyx-hack-squat", name: "Hack Squat", sets: [(105, 5, nil)])
        _ = try db.closeSession(id: "s1")
        let weight = try #require(try records(db).first { $0.axis == "weight" })
        #expect(weight.value == 105 && weight.sessionId == "s1" && weight.floorValue == 100)
    }

    @Test("a first-ever exercise files nothing, even when its second set out-lifts its first")
    func firstSessionIsBaseline() throws {
        let db = try store()
        try session(db, id: "s1", date: "2026-09-25", key: "onyx-hack-squat", name: "Hack Squat", sets: [(100, 8, nil), (110, 8, nil)])
        let closed = try #require(try db.closeSession(id: "s1"))
        #expect(try records(db).isEmpty)
        #expect(closed.prCount == 0)
    }

    @Test("a replay over a first-ever two-set session files nothing either (the guard reaches every door)")
    func replayHonoursTheGuard() throws {
        let db = try store()
        try session(db, id: "s1", date: "2026-09-25", key: "onyx-hack-squat", name: "Hack Squat", sets: [(100, 8, nil), (110, 8, nil)])
        try db.writer.write { conn in
            try conn.execute(sql: "UPDATE workout_sessions SET ended_at = started_at WHERE id = 's1'")
            _ = try PrRecorder.replay(conn, userId: user, exerciseKey: "Hack Squat")
        }
        #expect(try records(db).isEmpty, "the second set of a first-ever session is a baseline on the replay path too")
        try db.writer.write { conn in _ = try PrRecorder.recomputeAll(conn, userId: user) }
        #expect(try records(db).isEmpty)
    }

    @Test("a rebuild starts from the asserted floors and replaces a stale ledger row")
    func recomputeStartsFromFloors() throws {
        let db = try store()
        try session(db, id: "s1", date: "2026-09-01", key: "onyx-hack-squat", name: "Hack Squat", sets: [(100, 8, nil)])
        _ = try db.closeSession(id: "s1")
        try session(db, id: "s2", date: "2026-09-08", key: "onyx-hack-squat", name: "Hack Squat", sets: [(110, 8, nil)])
        _ = try db.closeSession(id: "s2")
        // A stale row from an older formula, filed by s1: nothing a session
        // can beat, and a record s1 no longer earns.
        try db.writer.write { conn in
            try PersonalRecordRow(userId: user, exerciseKey: "Hack Squat", axis: "e1rm",
                                  value: 999, reps: 8, weightKg: 100, sessionId: "s1", achievedOn: "2026-09-01").save(conn)
        }
        _ = try db.recomputeAllPrs(userId: user)
        let e1rm = try #require(try records(db).first { $0.axis == "e1rm" })
        #expect(e1rm.value == 136.55 && e1rm.sessionId == "s2", "110 × 36/29 by s2, not the stale 999")
        let weight = try #require(try records(db).first { $0.axis == "weight" })
        #expect(weight.value == 110 && weight.sessionId == "s2")
    }

    /// The founder's Seated Cable Row (Wide Grip), 2026-09-24, at the recorder:
    /// the history holds Epley-era `est_1rm_kg` (42.5 × 12 stored as 59.5), the
    /// ledger shows 59.50, and the engine's bar is Brzycki's 61.2 anyway.
    @Test("Thursday's 50 × 7 files Weight and leaves the e1RM row alone")
    func wideGripAtClose() throws {
        let db = try store()
        let key = "onyx-seated-cable-row-wide-grip"
        let name = "Seated Cable Row (Wide Grip)"
        let history: [(String, String, [(Double, Int, Double)])] = [
            ("h1", "2026-08-27", [(42.5, 12, 59.5), (42.5, 10, 56.7)]),
            ("h2", "2026-09-10", [(42.5, 12, 59.5), (42.5, 10, 56.7)]),
            ("h3", "2026-09-17", [(42.5, 12, 61.2), (42.5, 11, 58.85)]),
        ]
        try db.writer.write { conn in
            try Exercise(id: "2c397ee9", name: name, slug: key).save(conn)
            for (id, date, sets) in history {
                let start = LogicalDay.date(fromISO: date)!
                try WorkoutSession(id: id, userId: user, dayKey: "cb_b", date: date,
                                   startedAt: start, endedAt: start.addingTimeInterval(3600)).insert(conn)
                for (i, s) in sets.enumerated() {
                    try WorkoutSet(id: "\(id)-\(i)", sessionId: id, exerciseId: key, setIndex: i + 1,
                                   weightKg: s.0, reps: s.1, est1rmKg: s.2, foldOrder: i).insert(conn)
                }
            }
            for (axis, value, reps, kg, sid, on) in [("e1rm", 59.5, 12, 42.5, "h1", "2026-08-27"), ("volume", 510.0, 12, 42.5, "h1", "2026-08-27"), ("weight", 42.5, 12, 42.5, "h1", "2026-08-27")] {
                try PersonalRecordRow(userId: user, exerciseKey: name, axis: axis, value: value, reps: reps,
                                      weightKg: kg, sessionId: sid, achievedOn: on).insert(conn)
            }
            let thu = LogicalDay.date(fromISO: "2026-09-24")!
            try WorkoutSession(id: "s-thu", userId: user, dayKey: "cb_b", date: "2026-09-24", startedAt: thu).insert(conn)
            try WorkoutSet(id: "t-0", sessionId: "s-thu", exerciseId: key, setIndex: 1, weightKg: 50, reps: 7, foldOrder: 0).insert(conn)
            try WorkoutSet(id: "t-1", sessionId: "s-thu", exerciseId: key, setIndex: 2, weightKg: 42.5, reps: 12, foldOrder: 1).insert(conn)
        }
        let closed = try #require(try db.closeSession(id: "s-thu"))
        #expect(closed.prCount == 1)
        let rows = try records(db)
        let weight = try #require(rows.first { $0.axis == "weight" })
        #expect(weight.value == 50 && weight.sessionId == "s-thu" && weight.achievedOn == "2026-09-24")
        let e1rm = try #require(rows.first { $0.axis == "e1rm" })
        #expect(e1rm.value == 59.5 && e1rm.sessionId == "h1", "no e1RM row was written: 60.0 < 61.2")
        #expect(rows.first { $0.axis == "volume" }?.value == 510)
    }
}
