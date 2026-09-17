import Foundation
import Testing
import GRDB
import OnyxCore
import OnyxData
@testable import Onyx

/// The identity a live set is judged under, and the bar it is judged against.
///
/// ── WHY THIS SUITE EXISTS ───────────────────────────────────────────────────
/// `refreshLivePrs` keys its candidates with `storedId`, which READS the
/// catalogue. `snapshot` keys the committed set with `storedIdCreatingCatalogueRow`,
/// which MINTS a catalogue row and rewrites the same index. So the first commit
/// of a movement the catalogue has never heard of moves the key out from under
/// the bar — slug going in, uuid coming out — and `PrEngine.detectSetPrs` awards
/// nothing against a key its index has no entry for ("a delta against nothing is
/// not a delta"). The deck showed no trophy on a set whose own session page, one
/// screen later, showed two.
///
/// It is not enough to widen the id set handed to `livePrBaselines`:
/// `PrRecorder.baselines` re-keys every gathered row to `keyByName[name(id)]`,
/// and `keyByName` uniques on FIRST — over a `Set`, whose order is a hash. Hand
/// it both the slug and the uuid for one movement and the bar lands under
/// whichever of the two the hash happened to visit first. The bar and the
/// candidate have to agree BY CONSTRUCTION, which means one resolved id per
/// card and a rebuild whenever that id moves.
@MainActor
@Suite("Live PR identity")
struct LivePrIdentityTests {

    /// `nonisolated` for the same reason `SessionEditModeTests` needs it — a
    /// `@Sendable` seeding closure cannot read a main-actor-isolated constant.
    private nonisolated static let userId = "00000000-0000-0000-0000-00000000000b"
    private nonisolated static let priorSession = "s-prior"

    /// A catalogue that is NOT empty and does NOT hold the deck's movement.
    ///
    /// Both halves are load-bearing. `storedIdCreatingCatalogueRow` refuses to
    /// mint into an EMPTY catalogue (an empty one means "not pulled yet"), so a
    /// store with no exercises never reproduces the flip. And the movement's own
    /// row has to be missing, or `catalogueIndex()` answers before the mint and
    /// the key never moves.
    ///
    /// The history is filed under `ExerciseSlug.id` — what a pre-W6 deck wrote
    /// into `workout_sets`, and what `nameBySlug` still resolves.
    private func store(historyKg: Double = 40) throws -> AppDatabase {
        let database = try AppDatabase.inMemory(deviceId: "live-pr-identity")
        try database.seedRows { db in
            // Present so the catalogue is non-empty; unrelated to the deck's
            // movement so the mint still has to happen.
            try Exercise(id: "ex-lat-pulldown", name: "Lat Pulldown").insert(db)
            // `LoggerModel.catalogueHasWarmupCardio` gates the opener on this
            // row, so a store without it builds a deck with no bout on it — and
            // the two order tests below would then be asserting nothing.
            try Exercise(id: "ex-treadmill", name: WarmupCardio.name).insert(db)
            let start = LogicalDay.date(fromISO: "2026-08-30")!.addingTimeInterval(17 * 3600)
            try WorkoutSession(
                id: Self.priorSession, userId: Self.userId, dayKey: "cb_a", date: "2026-08-30",
                startedAt: start, endedAt: start.addingTimeInterval(3600),
                durationMin: 60, sessionRpe: 7
            ).insert(db)
            let slug = ExerciseSlug.id("Chest Press")
            for (index, reps) in [10, 9, 8].enumerated() {
                try WorkoutSet(
                    id: "prior-\(index + 1)", sessionId: Self.priorSession, exerciseId: slug,
                    setIndex: index + 1, weightKg: historyKg, reps: reps, setType: "normal",
                    est1rmKg: OneRepMax.estimate(weight: historyKg, reps: Double(reps)),
                    exerciseOrder: 2, foldOrder: index
                ).insert(db)
            }
        }
        return database
    }

    private func liveDeck(_ database: AppDatabase) -> LoggerModel {
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "cb_a"), phase: .cut,
            store: database, userId: Self.userId, startedAt: Date()
        )
        model.attach()
        return model
    }

    private func chestPress(_ model: LoggerModel) throws -> LoggerModel.ExerciseState {
        try #require(model.exercises.first { $0.name == "Chest Press" })
    }

    /// Tick set 1 of a card at a load, and hand back the row that was ticked.
    @discardableResult
    private func tick(
        _ model: LoggerModel, _ exercise: LoggerModel.ExerciseState, kg: Double, reps: Int
    ) throws -> LoggerModel.SetRow {
        let row = try #require(exercise.rows.first)
        row.weightKg = kg
        row.reps = reps
        model.toggleDone(row, in: exercise)
        return row
    }

    @Test("a set that beats the bar lights on the FIRST tick, with the catalogue row minted mid-session")
    func firstTickAwardsAcrossTheMint() throws {
        let database = try store()
        let model = liveDeck(database)
        let press = try chestPress(model)

        // The catalogue has never heard of this movement, so the commit path is
        // about to mint a row for it and move the key.
        let cataloguedBefore = try database.exercises().contains { $0.name == "Chest Press" }
        #expect(cataloguedBefore == false)

        let row = try tick(model, press, kg: 100, reps: 8)

        // 100 kg against a 40 kg history is a weight record and an e1RM record.
        #expect(row.isRecord, "the first tick must be judged against the bar the deck opened with")
        #expect(model.recordCount >= 1)
        // …and the mint really did happen, so this test is exercising the flip
        // rather than passing because it never occurred.
        let cataloguedAfter = try database.exercises().contains { $0.name == "Chest Press" }
        #expect(cataloguedAfter)
    }

    @Test("a phase switch mid-session does not lose an already-awarded record")
    func phaseSwitchKeepsRecords() throws {
        let database = try store()
        let model = liveDeck(database)
        let press = try chestPress(model)
        try tick(model, press, kg: 100, reps: 8)
        let before = model.recordCount
        #expect(before >= 1)

        // `rebuildForPhase` replaces `exercises` wholesale. A bar keyed on the
        // old deck's ids, or a `prsThisSession` never recomputed, both show up
        // here as a trophy count that fell to zero on a switch.
        model.phase = .bulk

        #expect(model.recordCount == before)
        let rebuilt = try chestPress(model)
        #expect(rebuilt.rows.first?.isRecord == true)
    }

    /// The deck's answer and the ledger's answer, over the same session.
    ///
    /// `PrRecorder` recomputes PRs from `workout_sets` at close, and
    /// `SessionAnalysis` does it again from the rows when the session page is
    /// drawn. Both are allowed to be independent answers — but they must AGREE,
    /// or the finish sheet and the session page describe the same workout
    /// differently. They could not agree before this wave: the live deck was
    /// keyed on an identity the bar did not carry, so it counted zero on a
    /// session the close path filed two records for.
    ///
    /// Compared against `workout_sessions.pr_count`, which is what `recount`
    /// writes and what every later reader of this session derives from.
    @Test("the deck's recordCount matches the ledger's pr_count for the same session")
    func deckAgreesWithTheLedger() throws {
        let database = try store()
        let model = liveDeck(database)
        let press = try chestPress(model)
        try tick(model, press, kg: 100, reps: 8)
        let liveCount = model.recordCount
        #expect(liveCount >= 1)

        let sessionId = try #require(model.sessionId)
        let closed = try #require(try database.closeSession(id: sessionId))
        #expect(closed.prCount == liveCount)

        // …and re-opening it for an edit says the same number a third time.
        let edit = LoggerModel(
            day: PlanTemplates.day("onyx5", "cb_a"), phase: .cut,
            store: database, userId: Self.userId,
            startedAt: closed.startedAt ?? Date(), openingForEdit: true
        )
        edit.attach(editing: closed)
        #expect(edit.recordCount == liveCount)
    }

    // MARK: - The edit deck's order, and the bout on it

    /// An edit deck keeps the order the session was PERFORMED in.
    ///
    /// `SessionDetailView.editorDay` builds that order from `exercise_order`,
    /// which the phone has written for every set — including every cardio row —
    /// since `v16.exerciseOrder`. The live table agrees: of 8 cardio rows, 8
    /// carry `exercise_order = 0` and none is null. So the reported symptom,
    /// "the treadmill drops to the bottom on edit", was never about that column.
    ///
    /// It was `inDeckOrder`, one layer up. `storedDeckOrder` is
    /// `deckOrder(dayKey:)` — the template left by the MOST RECENT session on
    /// this day key, which on an edit is almost never the session being edited —
    /// and a movement that session did not contain gets no rank at all
    /// (`placed ?? (count + index)`), so it sorts last. The treadmill is the
    /// movement that happens to every time, because the opener prepends it
    /// rather than the program naming it.
    @Test("an edit deck keeps the performed order, with the treadmill in position 1")
    func editDeckKeepsPerformedOrder() throws {
        let database = try store()
        // A stored deck order from ANOTHER session on this day key — one that
        // did not walk. This is what used to outrank the session being edited.
        try database.seedRows { db in
            let payload = """
            {"exercises":[{"name":"Chest Press","order":0,"sets":[]},\
            {"name":"Incline DB Press","order":1,"sets":[]}]}
            """.replacingOccurrences(of: "\\\n", with: "")
            try RoutineTemplateRow(
                userId: Self.userId, dayKey: "cb_a",
                payload: JSONText(raw: payload), updatedAt: Date()
            ).insert(db)
        }

        // `editorDay`'s shape: the session's own performed order, treadmill first.
        var day = PlanTemplates.day("onyx5", "cb_a")
        let walked = ProgramExercise(WarmupCardio.name, sets: 1, wk1Kg: 0, reps: "5 min", restSec: 0)
        day.exercises = [walked] + day.exercises

        let edit = LoggerModel(
            day: day, phase: .cut, store: database, userId: Self.userId,
            startedAt: Date(), openingForEdit: true
        )
        #expect(edit.exercises.first?.name == WarmupCardio.name,
                "an edit deck must not be re-ranked against another session's deck order")

        // …and the live deck still IS re-ranked by it, which is the whole point
        // of the stored order. `Chest Press` is first in the template above.
        let live = LoggerModel(
            day: day, phase: .cut, store: database, userId: Self.userId, startedAt: Date()
        )
        #expect(live.exercises.first?.name == "Chest Press")
    }

    /// The opener is a proposal, and an edit is not.
    ///
    /// `withWarmupCardio` ran at `init`, before anything knew the deck was a
    /// re-opened session, and `attach(editing:)` deleted the card again if
    /// nobody had ticked it. `openingForEdit` moves the decision to where it is
    /// known, so the card is never minted.
    @Test("an edit deck does not mint a warm-up bout nobody walked")
    func editDeckDoesNotPrependTheOpener() throws {
        let database = try store()
        let edit = LoggerModel(
            day: PlanTemplates.day("onyx5", "cb_a"), phase: .cut,
            store: database, userId: Self.userId, startedAt: Date(), openingForEdit: true
        )
        #expect(edit.exercises.contains { $0.name == WarmupCardio.name } == false)

        // The live deck still opens with it.
        let live = LoggerModel(
            day: PlanTemplates.day("onyx5", "cb_a"), phase: .cut,
            store: database, userId: Self.userId, startedAt: Date()
        )
        #expect(live.exercises.first?.name == WarmupCardio.name)
    }

    /// The bout the deck opens with resolves a mover and reads as cardio.
    ///
    /// `Program.swift` read `MuscleMap.movers` and nothing else, so
    /// `plan.movers.primary` was empty for "Treadmill", `ExerciseCardView.family`
    /// was nil and the card drew no tag at all. `MuscleMap.dict` must never learn
    /// a treadmill — it is the input to `MuscleCredit.weightedSets` — so the
    /// separate `cardioMovers` table is read as a FALLBACK.
    @Test("the treadmill card resolves a cardio mover and reports its bout")
    func treadmillCardResolvesACardioMover() throws {
        let model = LoggerModel(day: PlanTemplates.day("onyx5", "cb_a"), phase: .cut)
        let bout = try #require(model.exercises.first { $0.name == WarmupCardio.name })
        #expect(bout.plan.movers.primary.isEmpty == false,
                "a bout with no mover draws no tag and colours no rail")
        let bouts = bout.rows.filter(\.isCardio)
        #expect(bouts.isEmpty == false)
        // …and `dict` still does not name it, which is the rule this fallback
        // exists to avoid breaking.
        #expect(MuscleMap.movers(WarmupCardio.name) == nil)
    }
}
