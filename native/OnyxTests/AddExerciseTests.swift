import Foundation
import Testing
import GRDB
import OnyxCore
import OnyxData
@testable import Onyx

/// A movement added mid-session (W3): its card, its "last time", its place in
/// the log — and that adding it moves nothing on any card the day opened with.
@MainActor
@Suite("Add exercise mid-session")
struct AddExerciseTests {
    private nonisolated static let userId = "00000000-0000-0000-0000-00000000000b"
    private let added = "Face Pull"

    private func armsDay() -> ProgramDay { PlanTemplates.day("onyx5", "arms") }

    /// A Face Pull session on ANOTHER split, a week back: the only history the
    /// added card can have, and one the day-scoped seed cannot see.
    private func store() throws -> AppDatabase {
        let database = try AppDatabase.inMemory(deviceId: "add-test")
        try database.seedRows { db in
            try Exercise(id: "ex-face", name: "Face Pull").insert(db)
            try WorkoutSession(id: "s-push", userId: Self.userId, dayKey: "push_a", date: "2026-09-01", startedAt: Date()).insert(db)
            try WorkoutSet(id: "fp-1", sessionId: "s-push", exerciseId: "ex-face", setIndex: 1, weightKg: 30, reps: 12).insert(db)
            try WorkoutSet(id: "fp-2", sessionId: "s-push", exerciseId: "ex-face", setIndex: 2, weightKg: 32.5, reps: 10).insert(db)
        }
        return database
    }

    private func snapshot(_ model: LoggerModel) -> [String] {
        model.exercises.flatMap { card in
            card.rows.map { "\(card.name)|\($0.weightKg ?? -1)|\($0.reps ?? -1)|\($0.previous ?? "")" }
        }
    }

    @Test("it opens on its last working set from any split, and no other card moves")
    func opensOnTheNarrowLookup() throws {
        let day = armsDay()
        #expect(!day.exercises.contains { $0.name == added }, "the fixture needs a movement the day does not name")
        let model = LoggerModel(day: day, phase: .bulk, store: try store(), userId: Self.userId)
        model.attach()
        let before = snapshot(model)

        let card = try #require(model.addExercise(named: added))
        #expect(model.exercises.last?.id == card.id, "appended at the bottom")
        #expect(card.rows.count == 3, "the builder's own starting prescription")
        #expect(card.rows.allSatisfy { $0.weightKg == 32.5 && $0.reps == 10 && $0.previous == "32.5kg × 10" })
        #expect(model.lastTime(for: card)?.date == "2026-09-01")
        #expect(Array(snapshot(model).prefix(before.count)) == before, "the day's own cards read the seed exactly as before")

        #expect(model.addExercise(named: "face pull")?.id == card.id, "asking again goes to the card, never a second one")
        #expect(model.exercises.filter { $0.name == added }.count == 1)
    }

    @Test("its sets take the next exercise_order, and it survives a phase switch and a relaunch")
    func persistsLikeAnyCard() throws {
        let database = try store()
        let model = LoggerModel(day: armsDay(), phase: .bulk, store: database, userId: Self.userId)
        model.attach()
        let card = try #require(model.addExercise(named: added))
        let index = try #require(model.exercises.firstIndex { $0.id == card.id })
        #expect(model.toggleGroup([card.rows[0]], in: card))

        let sessionId = try #require(model.sessionId)
        let logged = try database.sets(sessionId: sessionId, userId: Self.userId)
        #expect(logged.map(\.exerciseOrder) == [index], "dense from 0: the next index, nothing restamped")

        model.phase = .cut
        #expect(model.exercises.contains { $0.name == added && $0.rows.contains(where: \.isDone) },
                "a phase switch rebuilds from the day, and the day holds it")
        // The seed is rebuilt on a phase switch — from the PROGRAM's day, so
        // the added card still reads its narrow "last time" afterwards.
        model.addSet(to: card)
        #expect(card.rows.last?.previous == "32.5kg × 10", "a set added after a phase switch keeps its Previous")

        // The app is killed and relaunched: a fresh model, rebuilt from the
        // PROGRAM, which does not name the movement.
        let relaunched = LoggerModel(day: armsDay(), phase: .bulk, store: database, userId: Self.userId)
        relaunched.attach()
        let back = try #require(relaunched.exercises.first { $0.name == added }, "the logged set comes back on its card")
        #expect(back.rows.filter(\.isDone).count == 1)
        #expect(LoggerModel.physical(back.rows) == 3, "with the blanks it still had")
        #expect(relaunched.lastTime(for: back)?.weightKg == 32.5, "last time is the session before, never this one")
    }
}
