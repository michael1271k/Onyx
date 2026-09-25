import Foundation
import Testing
import GRDB
import OnyxCore
import OnyxData
import OnyxUI
@testable import Onyx

/// A set that is two rows, and a set that carries more than one tag.
///
/// ── WHY THESE TWO ARE ONE SUITE ─────────────────────────────────────────────
/// They are the two halves of the same sheet and they share one hazard: both
/// change what a SET IS, and every count in the app is downstream of that. A
/// pair scored as two sets nearly doubles a session's tonnage, and a tag list
/// that reorders itself turns every sync into an edit. Neither fails loudly.
@MainActor
@Suite("Unilateral sets and set quality")
struct UnilateralAndQualityTests {

    /// Delts & Arms — the one ONYX-5 day that prescribes a unilateral movement
    /// (`Single Arm Lateral Raise`) beside seven bilateral ones, so both halves
    /// of every rule below are on the same deck.
    private func armsDay() -> LoggerModel {
        LoggerModel(day: PlanTemplates.day("onyx5", "arms"), phase: .bulk)
    }

    private func unilateral(_ model: LoggerModel) -> LoggerModel.ExerciseState? {
        model.exercises.first { model.canSplit($0) }
    }

    // MARK: - What may be split

    @Test("the four the founder named all match, and a barbell press does not")
    func catalogueMatches() {
        // Splitting a BILATERAL set logs the session at half its size, so the
        // gate is the feature. These four are the founder's own examples.
        for name in [
            "Side Plank", "Single Arm Cable Crossover",
            "Single Arm Triceps Pushdown", "Single Arm Lateral Raise",
        ] {
            #expect(Unilateral.isUnilateral(name), "\(name) must offer Split L/R")
        }
        for name in ["Barbell Bench Press", "Lat Pulldown", "Seated Cable Row (Wide Grip)"] {
            #expect(!Unilateral.isUnilateral(name), "\(name) must NOT offer Split L/R")
        }
    }

    @Test("a unilateral movement opens already split, a bilateral one does not")
    func decksOpenSplit() {
        let model = armsDay()
        guard let split = unilateral(model) else {
            Issue.record("no unilateral movement on Delts & Arms")
            return
        }
        #expect(split.rows.allSatisfy { $0.pairId != nil }, "every row is half of a pair")
        #expect(Set(split.rows.compactMap(\.side)) == ["left", "right"])
        // Two rows, ONE set. This is the assertion the whole feature rests on.
        #expect(split.rows.count == 2 * LoggerModel.physical(split.rows))

        #expect(split.name == "Single Arm Lateral Raise")
        for other in model.exercises where !model.canSplit(other) {
            #expect(other.rows.allSatisfy { $0.pairId == nil }, "\(other.name) must not open split")
        }
    }

    // MARK: - The two spellings a side can arrive in

    /// ── THE "SETS JUMP BY 2" REPORT ─────────────────────────────────────────
    /// The deck writes `left`/`right`; Postgres holds `L`/`R`. Every rule that
    /// folds a pair reads the first vocabulary, so a session restored with the
    /// second came back as two rows that were not a pair: numbered 3 and 4
    /// where one set was performed, and weighed twice by `SessionVolume`.
    @Test("a pair folds whichever vocabulary its side arrived in")
    func sideVocabularyFolds() {
        for (left, right) in [("left", "right"), ("L", "R"), ("l", "r")] {
            let pair = "pair-\(left)"
            let rows = [
                LoggerModel.SetRow(weightKg: 20, reps: 10, isDone: true, side: left, pairId: pair),
                LoggerModel.SetRow(weightKg: 20, reps: 10, isDone: true, side: right, pairId: pair),
            ]
            #expect(LoggerModel.groups(rows).count == 1, "\(left)/\(right) is ONE set")
            #expect(LoggerModel.physical(rows) == 1)
            #expect(rows.map(\.sideLabel) == ["L", "R"])
        }
    }

    /// The normalisation itself, at the door it is applied in
    /// (`LoggerModel.restoreLoggedSets`). Both vocabularies in, one out.
    @Test("restoring normalises a side to the local spelling")
    func restoreNormalisesSide() {
        #expect(SyncTranslation.localSide("L") == "left")
        #expect(SyncTranslation.localSide("R") == "right")
        #expect(SyncTranslation.localSide("left") == "left")
        #expect(SyncTranslation.localSide("right") == "right")
        // A side nobody recognises is no side at all — a set shown whole rather
        // than half a pair drawn from a value this app cannot read.
        #expect(SyncTranslation.localSide("middle") == nil)
        #expect(SyncTranslation.localSide(nil) == nil)
    }

    /// The stepper's hold retracts the coarse step it took on touch-down and
    /// puts the fine one on instead (`StepControl`). That correction is only
    /// correct while the fine step is genuinely the smaller of the two — a
    /// constant edit that inverted them would make a hold jump UP by 1.25 kg on
    /// the way down.
    @Test("the fine load step is smaller than the coarse one")
    func loadStepsOrdered() {
        #expect(Ceilings.loadStepFineKg < Ceilings.loadStepKg)
        #expect(Ceilings.loadStepKg == Ceilings.loadStepFineKg * 2)
    }

    // MARK: - Splitting and merging by hand

    @Test("splitting a logged set replaces it with two sides that carry its numbers")
    func splitCarriesTheSet() {
        let model = armsDay()
        guard let exercise = model.exercises.first(where: {
            !model.canSplit($0) && !$0.rows.contains(where: \.isCardio)
        }) else {
            Issue.record("no bilateral movement on Delts & Arms")
            return
        }
        let row = exercise.rows[0]
        row.weightKg = 60
        row.reps = 10
        model.toggleDone(row, in: exercise)
        let before = exercise.volumeKg()

        model.splitSet(row, in: exercise)

        let sides = exercise.rows.filter { $0.pairId != nil }
        #expect(sides.count == 2)
        #expect(sides.allSatisfy { $0.weightKg == 60 && $0.reps == 10 })
        // A closure, not `\.isDone`: the `#expect` macro expands a key-path
        // `allSatisfy` into a call it then thinks can throw, and the error names
        // the generated file rather than this line.
        #expect(sides.allSatisfy { $0.isDone }, "a set that was logged stays logged")
        #expect(Set(sides.compactMap(\.sideLabel)) == ["L", "R"])
        // The two sides are one set at the weaker side, so a set that was
        // 600 kg whole is 600 kg split. If this ever reads 1200 the pair has
        // stopped collapsing and every chart downstream is wrong.
        #expect(exercise.volumeKg() == before)
        #expect(exercise.workingSets == 1)
    }

    @Test("merging keeps the weaker side, and never invents tonnage")
    func mergeTakesTheWeakerSide() {
        let model = armsDay()
        guard let exercise = model.exercises.first(where: {
            !model.canSplit($0) && !$0.rows.contains(where: \.isCardio)
        }) else {
            Issue.record("no bilateral movement on Delts & Arms")
            return
        }
        let row = exercise.rows[0]
        row.weightKg = 20
        row.reps = 12
        model.splitSet(row, in: exercise)

        // A genuinely weaker left arm — which is the only reason to split at all.
        let sides = exercise.rows.filter { $0.pairId != nil }
        let pairId = sides[0].pairId!
        sides[0].weightKg = 18
        sides[0].reps = 9
        sides[0].rpe = 9.5
        sides[1].rpe = 8
        for side in sides { model.toggleDone(side, in: exercise) }
        let split = exercise.volumeKg()

        model.mergeSet(pairId: pairId, in: exercise)

        let merged = exercise.rows.first { $0.pairId == nil && $0.isDone }
        #expect(merged?.weightKg == 18, "the weaker load survives")
        #expect(merged?.reps == 9, "and the shorter set")
        #expect(merged?.rpe == 9.5, "but the HARDER rating — that is what it cost")
        #expect(merged?.side == nil)
        // 18 × 9 either way: the pair was already scored at its weaker side, so
        // un-splitting cannot change what the session weighed.
        #expect(exercise.volumeKg() == split)
    }

    @Test("a set already split is not split again")
    func splitIsIdempotent() {
        let model = armsDay()
        guard let exercise = unilateral(model) else {
            Issue.record("no unilateral movement on Delts & Arms")
            return
        }
        let before = exercise.rows.count
        model.splitSet(exercise.rows[0], in: exercise)
        #expect(exercise.rows.count == before, "a side is not half of a side")
    }

    // MARK: - How a pair is DRAWN, in the ledger

    /// The fixture `session-pairs-merged` is shot from, through the real
    /// pipeline: rows out of the store, `SessionAnalysis.detailSet`,
    /// `SessionDetail.toRows`, and then the row view's own decision. Building
    /// `DetailRow`s by hand would test a shape the app never assembles.
    private func pairRows() throws -> [SetRow] {
        let environment = HistoryPreviews.environment()
        let sets = try environment.database.historySets(sessionId: HistoryPreviews.pairShapes)
        let rows = SessionDetail.toRows(sets.map(SessionAnalysis.detailSet))
        // `.pair` is what the card resolves to when ANY row on it is a pair,
        // and the merge decision is per row inside that table — so the layout
        // has to be the card's, not the default.
        return rows.map { SetRow(row: $0, timed: false, layout: .pair) }
    }

    /// ── THE LEDGER HONOURS ALL THREE CASES (§W1 E) ──────────────────────────
    /// `SetPairLayout.resolve` has defined them since it was written and only
    /// the LOGGER consumed it. The session page hard-coded two value lines for
    /// every pair, so a set both arms performed identically printed
    /// `5kg × 12` twice to say nothing twice.
    @Test("the four pair shapes, and what the session page does with each")
    func ledgerHonoursEveryPairShape() throws {
        let rows = try pairRows()
        // Four pairs, four rows. A pair is ONE set everywhere it is counted and
        // this is where it is drawn; eight rows here would mean the fold broke.
        #expect(rows.count == 4)

        // 1 · load, reps and rating all agree → ONE line, one word, no L/R.
        #expect(rows[0].pairLayout == .effortSplit)
        #expect(rows[0].splitsValues == false, "one value line")
        #expect(rows[0].splitEfforts == nil, "one effort reading")

        // 2 · same numbers, different ratings → one value line, `L 8 · R 9`.
        #expect(rows[1].pairLayout == .effortSplit)
        #expect(rows[1].splitsValues == false)
        let second = try #require(rows[1].splitEfforts)
        #expect(second.0 == 8)
        #expect(second.1 == 9)

        // 3 · the reps differ and the right side was NEVER rated. Both facts
        // have to survive: two value lines, and `L 8 · R —` rather than a
        // lone `L 8` that would read as the set's own rating.
        #expect(rows[2].pairLayout == .valueSplit)
        #expect(rows[2].splitsValues)
        let third = try #require(rows[2].splitEfforts)
        #expect(third.0 == 8)
        #expect(third.1 == nil, "an unrated side is an em-dash, never a blank")

        // 4 · the reps differ and the ratings agree → two value lines and ONE
        // effort glyph, centred against the pair rather than against the left.
        #expect(rows[3].pairLayout == .valueSplit)
        #expect(rows[3].splitsValues)
        #expect(rows[3].splitEfforts == nil)
    }

    /// A pair with one side logged is not a comparison — it is a set, and the
    /// rule says so itself: "a group of one is `unified` by definition".
    @Test("one side is an ordinary set, and never an L with no R")
    func oneSideIsUnified() {
        #expect(SetPairLayout.resolve(weights: [5], reps: [12], rpes: [8]) == .unified)
    }

    /// ── WHY THE MERGE ALSO ASKS THE STRING ──────────────────────────────────
    /// `resolve` reads load, reps and effort. A cardio pair is told apart by
    /// `duration_sec` and `distance_km`, which are none of the three — both
    /// sides store `weight_kg 0, reps 0` — so the rule alone would call two
    /// bouts of different lengths identical and the row would print one of
    /// them. `SetRow.splitsValues` asks `fmt` as well for exactly this.
    @Test("the rule alone would merge two different bouts")
    func cardioIsNotTheRulesToDecide() {
        #expect(SetPairLayout.resolve(weights: [0, 0], reps: [0, 0], rpes: [nil, nil]) == .effortSplit)
    }

    /// The merge is a RENDERING change. If this number ever moves, it is not.
    @Test("drawing a pair as one row changes no tonnage")
    func mergeMovesNoNumber() throws {
        let environment = HistoryPreviews.environment()
        let sets = try environment.database.historySets(sessionId: HistoryPreviews.pairShapes)
        #expect(sets.count == 8, "four pairs, two rows each, in the store")
        // Scored ONCE per pair, at the weaker side: 12, 12, 11 and 10 reps at
        // 5 kg. Eight rows summed whole would be 450.
        #expect(SessionVolume.sessionVolumeKg(sets.map(SessionAnalysis.volumeSet)) == 5 * (12 + 12 + 11 + 10))
    }

    /// ── AND THE LEAK THE LOGGER USED TO HAVE (§W1 F) ────────────────────────
    /// Rating one arm of a pair wrote to that row alone, and `SetPatch` cannot
    /// write a null back — so a side skipped at the moment of rating stayed
    /// null for good. The card now carries the unrated sibling into the picker
    /// with the tapped side, which is the same seed `splitSet` already writes.
    @Test("rating one side of a pair seeds the sibling that has none")
    func ratingOneSideSeedsTheOther() throws {
        let model = armsDay()
        guard let exercise = unilateral(model) else {
            Issue.record("no unilateral movement on Delts & Arms")
            return
        }
        // ONE pair — the group a set box is drawn from, not every row of the
        // movement: three prescribed sets are three pairs and six rows.
        let sides = try #require(LoggerModel.groups(exercise.rows).first)
        #expect(sides.count == 2)
        #expect(sides.allSatisfy { $0.rpe == nil }, "a fresh pair opens unrated")

        // What the sheet is handed when the LEFT side is tapped.
        #expect(SetRowView.effortTargets(tapping: sides[0], in: sides).map(\.id)
                == [sides[0].id, sides[1].id], "both rows, the tapped one first")

        // Once the right side holds a rating of its own, it is nobody's seed.
        sides[1].rpe = 9
        #expect(SetRowView.effortTargets(tapping: sides[0], in: sides).map(\.id)
                == [sides[0].id], "a rated sibling is left alone")
    }

    // MARK: - Several tags on one set

    @Test("tags accumulate, withdraw one at a time, and store in canonical order")
    func qualitiesAreASet() {
        let model = armsDay()
        let exercise = model.exercises.first { !$0.rows.contains(where: \.isCardio) }!
        let row = exercise.rows[0]

        model.setQuality(.partialRom, on: row, in: exercise)
        model.setQuality(.momentum, on: row, in: exercise)
        #expect(row.qualities == [.momentum, .partialRom], "declaration order, not tap order")
        // Which is the point: `SessionEditing.amendSet` compares the stored
        // string to decide whether an amend changed anything. A list that
        // reordered itself would seed the event log on every tap.
        #expect(SetQuality.join(row.qualities) == "momentum+partial_rom")

        // Tapping a chosen one withdraws just that one.
        model.setQuality(.momentum, on: row, in: exercise)
        #expect(row.qualities == [.partialRom])
        // And nil clears the lot.
        model.setQuality(nil, on: row, in: exercise)
        #expect(row.qualities.isEmpty)
        #expect(SetQuality.join(row.qualities) == nil, "absence is NULL, not an empty string")
    }

    @Test("one tag is byte-identical to what this app has always written")
    func oneTagIsUnchanged() {
        // The whole reason the column did not have to change shape. Every row
        // already in Postgres parses, and every row this build writes for a
        // single tag is a value the OLD CHECK constraint would have accepted.
        for quality in SetQuality.allCases {
            #expect(SetQuality.join([quality]) == quality.rawValue)
            #expect(SetQuality.parse(quality.rawValue) == [quality])
        }
        #expect(SetQuality.parse(nil).isEmpty)
        #expect(SetQuality.parse("").isEmpty)
        // A key from a newer client is dropped rather than failing the row.
        #expect(SetQuality.parse("momentum+invented") == [.momentum])
        // And a value written out of order still reads correctly.
        #expect(SetQuality.parse("partial_rom+momentum") == [.momentum, .partialRom])
    }

    // MARK: - The rest nudge

    @Test("a nudge moves this rest and leaves the plan alone")
    func nudgeIsForThisSetOnly() {
        let model = armsDay()
        // A real prescription, not the treadmill's zero: `startRest` accepts a
        // 0 and a rest that is already over is not one this test can nudge.
        guard let exercise = model.exercises.first(where: { ($0.plan.restSec ?? 0) > 60 }),
              let prescribed = exercise.plan.restSec
        else {
            Issue.record("no movement on Delts & Arms prescribes a rest")
            return
        }
        model.startRest(for: exercise)
        model.adjustRest(by: 15)
        #expect(model.restDuration == TimeInterval(prescribed) + 15)

        // The next set is prescribed by the PLAN again. A longer breather after
        // set 3 is a fact about set 3, not a standing amendment to the block.
        model.startRest(for: exercise)
        #expect(model.restDuration == TimeInterval(prescribed))
        #expect(exercise.plan.restSec == prescribed, "the plan itself never moved")
    }

    @Test("pulling the clock past now ends the rest rather than counting backwards")
    func nudgeCannotGoNegative() {
        let model = armsDay()
        guard let exercise = model.exercises.first(where: { ($0.plan.restSec ?? 0) > 60 }) else {
            Issue.record("no movement on Delts & Arms prescribes a rest")
            return
        }
        model.startRest(for: exercise)
        for _ in 0..<40 { model.adjustRest(by: -15) }
        #expect(model.restEndsAt == nil)
        #expect(model.restingExercise == nil, "and the card stops claiming to be resting")
    }
}
