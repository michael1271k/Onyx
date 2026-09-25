import Foundation
import GRDB
import Testing
import OnyxCore
@testable import OnyxData

@Suite("Training trends — one read, names joined, pairs collapsed")
struct TrainingTrendsStoreTests {
    private let user = "00000000-0000-0000-0000-000000000001"

    @Test("range is inclusive, sets carry their exercise name, a pair is one set and a ghost is nothing")
    func readShapesRows() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        try db.seedRows { db in
            try Exercise(id: "ex-press", name: "Leg Press").insert(db)
            try WorkoutSession(id: "in", userId: user, dayKey: "legs_a", date: "2026-09-01").insert(db)
            try WorkoutSession(id: "out", userId: user, dayKey: "legs_b", date: "2026-09-03").insert(db)
            try WorkoutSession(id: "other", userId: "someone-else", date: "2026-09-01").insert(db)
            try WorkoutSet(id: "a", sessionId: "in", exerciseId: "ex-press", setIndex: 0, weightKg: 100, reps: 10).insert(db)
            try WorkoutSet(id: "l", sessionId: "in", exerciseId: "ex-press", setIndex: 1, weightKg: 40, reps: 10, side: "left", pairId: "p").insert(db)
            try WorkoutSet(id: "r", sessionId: "in", exerciseId: "ex-press", setIndex: 2, weightKg: 50, reps: 8, side: "right", pairId: "p").insert(db)
            try WorkoutSet(id: "g", sessionId: "in", exerciseId: "ex-press", setIndex: 3, weightKg: 100, reps: 10, setType: "ghost").insert(db)
            try WorkoutSet(id: "x", sessionId: "out", exerciseId: "missing", setIndex: 0, weightKg: 60, reps: 10).insert(db)
        }

        let rows = try db.trainingTrendSessions(userId: user, from: "2026-09-01", to: "2026-09-02")
        #expect(rows.map(\.id) == ["in"])
        #expect(rows[0].sets.map(\.exerciseName) == ["Leg Press", "Leg Press", "Leg Press", "Leg Press"])
        // 100×10 + min(40,50)×min(10,8) — the ghost weighs nothing.
        #expect(rows[0].volumeKg == 1320)

        let all = try db.trainingTrendSessions(userId: user, from: "2026-09-01", to: "2026-09-03")
        #expect(all.map(\.id) == ["in", "out"])
        // An unknown exercise id is shown as itself, never dropped.
        #expect(all[1].sets.map(\.exerciseName) == ["missing"])
    }

    @Test("a bodyweight set weighs the athlete's weigh-in, as the close path stores it (Q13)")
    func bodyweightCredit() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        try db.seedRows { db in
            try Exercise(id: "ex-pull", name: "Pull Up").insert(db)
            try WorkoutSession(id: "s", userId: user, dayKey: "back", date: "2026-09-10").insert(db)
            try WorkoutSet(id: "p", sessionId: "s", exerciseId: "ex-pull", setIndex: 0, weightKg: 0, reps: 10).insert(db)
        }
        _ = try db.editDailyLog(userId: user, date: "2026-09-08") { $0.weightKg = 80 }

        let rows = try db.trainingTrendSessions(userId: user, from: "2026-09-10", to: "2026-09-10")
        #expect(rows.first?.volumeKg == 800)
    }
}
