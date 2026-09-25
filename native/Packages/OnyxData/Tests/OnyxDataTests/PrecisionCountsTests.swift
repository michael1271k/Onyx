import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// Precision Lane C: the stored aggregates on the Hevy basis (Q13) and the two
/// set figures (Q10), and the one-time recount that brings old rows to them.
@Suite("Session totals — Hevy basis and two set figures")
struct PrecisionCountsTests {

    private let user = "u1"
    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    /// A pull-up day: a treadmill bout, a loaded warm-up, three pull-ups at
    /// 0 kg, one weighted dip. Body weight 61.2 logged that morning.
    private func seed(_ db: AppDatabase, sessionDate: String = "2026-09-24", weighIn: String? = "2026-09-24") throws {
        try db.writer.write { conn in
            try Exercise(id: "ex-tread", name: "Treadmill").insert(conn)
            try Exercise(id: "ex-press", name: "Leg Press").insert(conn)
            // The catalogue flag is what the deck wrote; the name agrees.
            try Exercise(id: "ex-pull", name: "Pull-Up", isBodyweight: true).insert(conn)
            try Exercise(id: "ex-dip", name: "Dip", isBodyweight: true).insert(conn)
            let start = LogicalDay.date(fromISO: sessionDate)!
            try WorkoutSession(id: "s", userId: user, dayKey: "cb_b", date: sessionDate, startedAt: start).insert(conn)
            var bout = WorkoutSet(id: "b", sessionId: "s", exerciseId: "ex-tread", setIndex: 1, weightKg: 0, reps: 0, setType: "warmup", foldOrder: 0)
            bout.durationSec = 300
            try bout.insert(conn)
            try WorkoutSet(id: "w", sessionId: "s", exerciseId: "ex-press", setIndex: 1, weightKg: 60, reps: 15, setType: "warmup", foldOrder: 1).insert(conn)
            for i in 0..<3 {
                try WorkoutSet(id: "p\(i)", sessionId: "s", exerciseId: "ex-pull", setIndex: i + 1, weightKg: 0, reps: 8, foldOrder: 2 + i).insert(conn)
            }
            try WorkoutSet(id: "d", sessionId: "s", exerciseId: "ex-dip", setIndex: 1, weightKg: 10, reps: 6, foldOrder: 5).insert(conn)
            if let weighIn {
                let t = Date()
                try DailyLogRow(id: "dl", userId: user, date: weighIn, weightKg: 61.2, createdAt: t, updatedAt: t, nutritionEstimated: false, sleepOnsetTrouble: false).insert(conn)
            }
        }
    }

    @Test("closing a session stores the Hevy-basis tonnage and both set figures")
    func closeWritesTheThreeFigures() throws {
        let db = try store()
        try seed(db)
        let closed = try #require(try db.closeSession(id: "s"))
        // 3 × (61.2 × 8) + 10 × 6; the bout and the 60 × 15 warm-up weigh nothing.
        #expect(closed.totalVolumeKg == 1528.8)
        #expect(closed.setCount == 6, "bout + warm-up + 3 pull-ups + dip")
        #expect(closed.workingSetCount == 4)
    }

    @Test("the body weight is the latest reading on or before the session day")
    func bodyWeightOnOrBefore() throws {
        let earlier = try store()
        try seed(earlier, sessionDate: "2026-09-24", weighIn: "2026-09-20")
        #expect(try earlier.closeSession(id: "s")?.totalVolumeKg == 1528.8, "a reading four days old still stands")

        let later = try store()
        try seed(later, sessionDate: "2026-09-24", weighIn: "2026-09-25")
        #expect(try later.closeSession(id: "s")?.totalVolumeKg == 60, "tomorrow's weigh-in is not today's load")

        let none = try store()
        try seed(none, weighIn: nil)
        #expect(try none.closeSession(id: "s")?.totalVolumeKg == 60, "no reading, no credit")
    }

    @Test("the recount door rewrites rows stored under the old rule, pushes them, and is idempotent")
    func recountDoor() throws {
        let db = try store()
        try seed(db)
        _ = try db.closeSession(id: "s")
        // What the old rule (and the web) would have stored: warm-ups in, no
        // body weight, no working figure — and a drained outbox.
        try db.writer.write { conn in
            try conn.execute(sql: "UPDATE workout_sessions SET total_volume_kg = 960, set_count = 6, working_set_count = NULL WHERE id = 's'")
            try conn.execute(sql: "DELETE FROM outbox")
        }
        let changed = try db.recountSessionTotals(userId: user)
        #expect(changed == 1)
        let row = try #require(try db.session(id: "s"))
        #expect(row.totalVolumeKg == 1528.8 && row.setCount == 6 && row.workingSetCount == 4)
        let queued = try db.writer.read { conn in
            try Int.fetchOne(conn, sql: "SELECT count(*) FROM outbox WHERE idempotency_key = 'session:s'") ?? 0
        }
        #expect(queued == 1, "the corrected row reaches the server through the outbox")

        #expect(try db.recountSessionTotals(userId: user) == 0, "a second pass changes nothing")
    }

    @Test("a session whose sets this device never pulled is left alone")
    func recountSkipsSetlessSessions() throws {
        let db = try store()
        try db.writer.write { conn in
            try WorkoutSession(id: "web", userId: user, dayKey: "cb_a", date: "2026-09-01",
                               startedAt: Date(), endedAt: Date(), totalVolumeKg: 5000, setCount: 20).insert(conn)
        }
        #expect(try db.recountSessionTotals(userId: user) == 0)
        #expect(try db.session(id: "web")?.totalVolumeKg == 5000)
    }
}
