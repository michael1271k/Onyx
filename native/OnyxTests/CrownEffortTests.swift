import Foundation
import Testing
import GRDB
import OnyxCore
import OnyxData
import OnyxUI
@testable import Onyx

/// The wrist's Crown RPE on the phone's deck (overhaul A3, decision Q2): shown
/// at once, written only by a tick or a tap, and never onto an unticked set.
@MainActor
@Suite("Crown effort")
struct CrownEffortTests {

    private nonisolated static let sessionId = "crown-session"
    private nonisolated static let userId = "crown-user"
    private nonisolated static func armsDay() -> ProgramDay { PlanTemplates.day("onyx5", "arms") }

    private func liveModel() throws -> (LoggerModel, AppDatabase) {
        let store = try AppDatabase.inMemory(deviceId: "crown-test")
        try store.seedRows { db in
            try Exercise(id: "ex-lateral", name: "Single Arm Lateral Raise").insert(db)
            try WorkoutSession(
                id: Self.sessionId, userId: Self.userId, dayKey: Self.armsDay().key,
                date: LogicalDay.today(), startedAt: Date().addingTimeInterval(-600)
            ).insert(db)
        }
        let model = LoggerModel(day: Self.armsDay(), phase: .bulk, store: store, userId: Self.userId)
        model.attach()
        return (model, store)
    }

    private func pulse(_ row: LoggerModel.SetRow, _ rpe: Double) -> EffortPulse {
        EffortPulse(sessionId: Self.sessionId, exerciseId: "ex-lateral", setIndex: 1, rpe: rpe, setId: row.storeId)
    }

    @Test("a provisional rating reaches no event until the next tick, which writes it once")
    func provisionalIsNotPersistedUntilTheTick() throws {
        let (model, store) = try liveModel()
        #expect(model.sessionId == Self.sessionId)
        let card = try #require(model.exercises.first { $0.name == "Single Arm Lateral Raise" })
        while card.rows.count < 2 { model.addSet(to: card) }
        let first = card.rows[0], second = card.rows[1]
        for row in [first, second] { row.weightKg = 10; row.reps = 12 }
        #expect(model.toggleDone(first, in: card))
        let afterTick = try store.setEvents(sessionId: Self.sessionId).count

        // Five Crown detents: provisional ink, and not one event.
        for rpe in [7.5, 8, 8.5, 9, 9.5] { model.receiveEffort(pulse(first, rpe)) }
        #expect(try store.setEvents(sessionId: Self.sessionId).count == afterTick,
                "a provisional RPE must never reach set_events")
        #expect(model.provisional(for: first)?.rpe == 9.5)
        #expect(model.provisional(for: first)?.band == .veryHard)
        #expect(first.rpe == nil)

        // The next tick is the commit: one append for the new set, one amend.
        #expect(model.toggleDone(second, in: card))
        #expect(first.rpe == 9.5)
        #expect(model.provisional(for: first) == nil)
        #expect(try store.setEvents(sessionId: Self.sessionId).count == afterTick + 2)
    }

    @Test("an unticked set keeps its rating provisional; a stale one clears itself")
    func untickedAndStaleNeverCommit() throws {
        let (model, store) = try liveModel()
        let card = try #require(model.exercises.first { $0.name == "Single Arm Lateral Raise" })
        let row = card.rows[0]
        row.weightKg = 10; row.reps = 12
        let before = try store.setEvents(sessionId: Self.sessionId).count

        model.receiveEffort(pulse(row, 8.5))
        model.commitProvisional(row, in: card)
        #expect(row.rpe == nil, "an unticked set's RPE is not a fact")
        #expect(try store.setEvents(sessionId: Self.sessionId).count == before)

        let old = Date().addingTimeInterval(-(LoggerModel.provisionalLifetime + 1))
        model.receiveEffort(pulse(row, 9), now: old)
        #expect(model.provisional(for: row) == nil, "older than ten minutes is gone")

        // Another session's pulse is not this deck's.
        var foreign = pulse(row, 10)
        foreign.sessionId = "someone-else"
        model.receiveEffort(foreign)
        #expect(model.provisional(for: row) == nil)
    }
}
