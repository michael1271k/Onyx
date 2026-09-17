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

/// ── THE SHELF THE TRAIN TAB'S TOOLBAR OPENS (§W1 B–D) ───────────────────────
/// `train-library` and `train-library-open` photograph a sheet built from
/// `WorkoutWeek.library()`, which is a walk over every week of a block — a
/// screen a shot cannot review if the walk comes back empty, because an empty
/// shelf and a broken one look the same.
@MainActor
@Suite("Past Weeks library fixture")
struct PastWeeksLibraryFixtureTests {
    @Test("the shelf reaches two phase blocks, real week numbers, and the week the shot opens")
    func shelfHasBlocksAndNumbers() async throws {
        let environment = HistoryPreviews.environment()
        let week = WorkoutWeek(
            database: environment.database, userId: environment.userIdString,
            phase: .cut, seededToday: "2026-09-03", seededDayKey: "cb_a"
        )
        let library = await week.library()

        // Six weeks behind 30 August with something logged in them. The walk
        // stops at `Schedule.isPlannable`, which goes false the week before the
        // plan's own Week 0 — NOT at an eight-week cap, which is gone.
        #expect(library.weeks.count == 6)
        #expect(library.weeks.first?.weekStart == "2026-08-23", "newest first")
        #expect(library.weeks.last?.weekStart == "2026-07-12", "and it walks back to Week 0")

        // The label is the PROGRAMME's counter now — `Week 5`, not
        // `Week of Sun 16 Aug`, which is what this file hand-rolled before.
        let opened = try #require(library.weeks.first { $0.weekStart == "2026-08-16" })
        #expect(opened.label == "Week 5")
        #expect(opened.range == "16 – 22 Aug")
        #expect(opened.sessions == 5, "the one week in this seed that closed complete")
        #expect(!opened.muscles.isEmpty, "a banner says what the week was for")

        // Two blocks, two colours: the shelf's sections are only visible as
        // sections if more than one phase is on it.
        let kinds = Set(library.weeks.compactMap {
            Phases.span(for: $0.weekStart, in: library.phases)?.def.kind
        })
        #expect(kinds == [.peak, .cut])
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
