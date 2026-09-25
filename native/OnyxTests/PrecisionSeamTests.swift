import Foundation
import Testing
import GRDB
import OnyxCore
import OnyxData
@testable import Onyx

/// Precision W-final, seams 1 and 2: the live deck counts and weighs a session
/// by the rules `closeSession` stores it by — `SessionCounts` for the two set
/// figures, `SessionVolume` with the athlete's body weight for tonnage. A deck
/// with its own rule is a header that disagrees with the row it wrote.
@MainActor
@Suite("Precision seams — the deck agrees with the close")
struct PrecisionSeamTests {

    nonisolated static let userId = "00000000-0000-0000-0000-0000000000f1"

    private nonisolated static let bout = WarmupCardio.Bout(
        name: "Treadmill", durationSec: 300, distanceKm: 0.37, inclinePct: 2
    )

    private func store(weightKg: Double?) throws -> AppDatabase {
        let database = try AppDatabase.inMemory(deviceId: "seam-test")
        try database.seedRows { db in
            try Exercise(id: "ex-pull", name: "Pull Up").insert(db)
            try Exercise(id: "ex-face", name: "Face Pull").insert(db)
            try WorkoutSession(
                id: "s-before", userId: Self.userId, dayKey: "push_a", date: "2026-09-01",
                startedAt: Date(timeIntervalSince1970: 1_788_000_000), endedAt: Date(timeIntervalSince1970: 1_788_003_600)
            ).insert(db)
            try WorkoutSet(id: "fp-1", sessionId: "s-before", exerciseId: "ex-face", setIndex: 1, weightKg: 30, reps: 12).insert(db)
        }
        if let weightKg {
            _ = try database.editDailyLog(userId: Self.userId, date: LogicalDay.today()) { $0.weightKg = weightKg }
        }
        return database
    }

    @Test("Sets and Working are SessionCounts over the deck's done rows — a pair once, a ghost never")
    func countsAreSessionCounts() {
        let card = LoggerModel.ExerciseState(
            plan: PlanTemplates.day("onyx5", "arms").exercises[0],
            rows: [
                .init(weightKg: 0, kind: .warmup, isDone: true, durationSec: 300, distanceKm: 0.4),
                .init(weightKg: 20, reps: 10, kind: .warmup, isDone: true),
                .init(weightKg: 40, reps: 8, isDone: true),
                .init(weightKg: 40, reps: 8, kind: .failure, isDone: true),
                .init(weightKg: 40, reps: 8, kind: .ghost, isDone: true),
                .init(weightKg: 40, reps: 8, isDone: false),
                // A half-written pair: the id without its sides. `set_count`
                // (`count(distinct coalesce(pair_id, id))`) counts it once.
                .init(weightKg: 15, reps: 12, isDone: true, pairId: "p-1"),
                .init(weightKg: 15, reps: 12, isDone: true, pairId: "p-1"),
            ]
        )
        let done = card.rows.filter(\.isDone).map(\.volumeSet)
        #expect(card.physicalSets == SessionCounts.total(done))
        #expect(card.workingSets == SessionCounts.working(done))
        #expect(card.physicalSets == 5)
        #expect(card.workingSets == 3)
    }

    @Test("a bodyweight set weighs the athlete on the deck, exactly as the close path stores it")
    func bodyweightCredit() throws {
        let database = try store(weightKg: 80)
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "arms"), phase: .bulk, store: database,
            userId: Self.userId, warmupBout: Self.bout
        )
        model.attach()
        let card = try #require(model.addExercise(named: "Pull Up"))
        let row = card.rows[0]
        row.weightKg = nil
        row.reps = 10
        #expect(model.toggleDone(row, in: card))

        #expect(model.totalVolumeKg == 800)
        let sessionId = try #require(model.sessionId)
        let stored = try database.read { db -> Double in
            let session = try #require(try WorkoutSession.fetchOne(db, key: sessionId))
            let sets = try WorkoutSet.filter(Column("session_id") == sessionId).fetchAll(db)
            return try SessionEditing.totals(db, session: session, sets: sets).volumeKg
        }
        #expect(stored == model.totalVolumeKg)
    }

    @Test("no weigh-in credits nothing, as before the parameter existed")
    func noWeighInNoCredit() throws {
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "arms"), phase: .bulk, store: try store(weightKg: nil),
            userId: Self.userId, warmupBout: Self.bout
        )
        model.attach()
        let card = try #require(model.addExercise(named: "Pull Up"))
        card.rows[0].weightKg = nil
        card.rows[0].reps = 10
        #expect(model.toggleDone(card.rows[0], in: card))
        #expect(model.totalVolumeKg == 0)
    }

    @Test("a first-ever movement's sets carry the quiet Baseline mark and no trophy; a known one does not (seam 3, Q12)")
    func baselineMark() throws {
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "arms"), phase: .bulk, store: try store(weightKg: 80),
            userId: Self.userId, warmupBout: Self.bout
        )
        model.attach()
        let fresh = try #require(model.addExercise(named: "Pull Up"))
        fresh.rows[0].weightKg = nil
        fresh.rows[0].reps = 12
        #expect(model.toggleDone(fresh.rows[0], in: fresh))
        #expect(fresh.isBaseline)
        #expect(!fresh.rows[0].isRecord)

        let known = try #require(model.addExercise(named: "Face Pull"))
        known.rows[0].weightKg = 35
        known.rows[0].reps = 12
        #expect(model.toggleDone(known.rows[0], in: known))
        #expect(!known.isBaseline)
        #expect(known.rows[0].isRecord, "35 × 12 beats the 30 × 12 on record")
    }
}
