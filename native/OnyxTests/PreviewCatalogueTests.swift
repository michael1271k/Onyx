import Foundation
import Testing
import GRDB
import OnyxCore
import OnyxData
@testable import Onyx

/// The screenshot harness has no compiled deck to fall back on since W2: a
/// preview store that fails to seed photographs an empty plan. This is the
/// check that the seed lands.
@Suite("Preview catalogue")
struct PreviewCatalogueTests {
    @Test("the template decks, phases, rungs and periods land as rows")
    func seeds() throws {
        let db = try AppDatabase.inMemory(deviceId: "shot")
        PreviewCatalogue.seed(db)
        PreviewCatalogue.seedStack(db)
        let ctx = try db.scheduleContext(userId: PreviewCatalogue.userId)
        #expect(ctx.plans.count == 3)
        #expect(ctx.program(id: "onyx5")?.days.count == 5)
        #expect(ctx.phases.count == 8)
        #expect(ctx.weekZeroStart == "2026-07-12")
        let ladder = try db.leverLadder(userId: PreviewCatalogue.userId)
        #expect(ladder.rungs.count == 4)
        #expect(ladder.periods.count == 5)
        #expect(try db.phaseGoals(userId: PreviewCatalogue.userId, planId: "onyx5", phase: .cut)?.calorieGoal == 1955)
        #expect(try db.volumeTargets(userId: PreviewCatalogue.userId, planId: "onyx5", phase: .cut).values.reduce(0, +) == 93)
    }
}

/// The Top Lifts shot is the only picture of an arrow or a flame, and both are
/// drawn from a store: the fixture seeds one previous session of the same day,
/// and `LiveStatsView` reads it back through its environment. A fixture whose
/// query comes back empty photographs a card with no arrows on it and looks
/// exactly like a card whose arrows are broken.
@MainActor
@Suite("Live Stats fixture")
struct LiveStatsFixtureTests {
    @Test("the seeded previous session reaches TopLifts.previousBests")
    func fixtureFeedsTheArrows() throws {
        let fixture = LoggerModel.previewUpperBWithHistory()
        // `userId: ""` is what a preview passes — nothing is signed in, and the
        // store falls back to the one user its rows belong to.
        let history = try fixture.store.sessionsForSeed(
            dayKey: fixture.model.day.key, userId: ""
        )
        #expect(!history.sessions.isEmpty)
        // The live session is excluded exactly as the card excludes it — the
        // deck has already written today's row into this store, and a bar that
        // included it would be today's own numbers.
        let bests = TopLifts.previousBests(
            sessions: history.sessions.filter { $0.id != fixture.model.sessionId },
            sets: history.sets
        )
        // 47 kg last time, 49.5 kg today — the shot's one visible arrow.
        #expect(bests["Neutral-Grip Lat Pulldown"]?.kg == 47)
        #expect(bests["Chest Press"]?.kg == 40)
    }
}

@Suite("Settings model over the preview store")
struct SettingsModelPreviewTests {
    @MainActor @Test("the harness model sees the plans, the rungs and the goals")
    func modelSeesTheCatalogue() async throws {
        let model = PreviewHarness.seededModel()
        let task = Task { await model.observe() }
        defer { task.cancel() }
        for _ in 0..<100 where model.plans.isEmpty || model.goals == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.failure == nil, "\(model.failure ?? "")")
        #expect(model.plans.map(\.id) == ["onyx5", "onyx4", "ppl"])
        #expect(model.rungs.count == 3)
        #expect(model.goals?.calorieGoal == 1955)
        #expect(model.preset.calorieGoal == 1955)
        #expect(model.volumeTotal == 93)
    }
}
