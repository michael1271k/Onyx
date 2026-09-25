import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// The e1RM axis, hand-computed.
//
// `pr-baselines.json`, `pr-session.json`, `live-prs.json`, `widget-e1rm.json`,
// `exercise-summary.json` and `e1rm-series.json` all carried e1RM expectations
// produced by Epley under the programmed-rep-floor gate. Both rules changed on
// 2026-09-15 and the fixtures were NOT regenerated — `GoldenVector`'s own header
// says why, and those files still pin every rule that did not change.
//
// This is the replacement specification for the one that did. Every number here
// is written out longhand, so it fails if the formula regresses.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("PR engine — the e1RM axis")
struct PrE1rmTests {

    private func candidate(_ key: String, _ kg: Double, _ reps: Double, setType: String? = nil) -> PrCandidateSet {
        PrCandidateSet(key: key, weightKg: kg, reps: reps, setType: setType)
    }

    private func history(_ key: String, _ rows: [(Double, Double)]) -> PrBaselines {
        PrEngine.buildBaselines(
            rows.map { BaselineSetRow(key: key, weightKg: $0.0, reps: $0.1) },
            isTimed: { _ in false }
        )
    }

    // MARK: The session that prompted the change

    @Test("Hammer Curl: a top set under the programmed floor now takes the e1RM axis")
    func hammerCurlAwardsBothAxes() {
        // 2026-09-15. Programmed 10–12. Logged 20 kg × 10 then 25 kg × 8, with
        // a history topping out below both. Onyx awarded Heaviest and nothing
        // else, because the top set's 8 reps was under the floor; Hevy, looking
        // at the same two sets, reported a best estimated 1RM as well.
        //
        // Brzycki by hand: 20 × 36/27 = 26.666… → 26.67. 25 × 36/29 = 31.034… →
        // 31.03. The bar below is 17.5 × 36/27 = 23.33 and 20 kg flat.
        let bar = history("Hammer Curl", [(17.5, 10), (17.5, 12)])
        let result = PrEngine.detectSessionPrs(
            [candidate("Hammer Curl", 20, 10), candidate("Hammer Curl", 25, 8)],
            bar
        )
        #expect(result.perSet[0].est1rm == 26.67, "20 × 36/27")
        #expect(result.perSet[1].est1rm == 31.03, "25 × 36/29")

        // Both sets clear the bar on both axes, and `supersedeWithinSession`
        // then hands each axis to the session's BEST claimant — so the opener
        // is superseded outright and the top set holds the pair. That is
        // existing, tested behaviour ("one ultimate record per axis per
        // exercise, per session") and is not what changed here.
        #expect(result.perSet[0].axes.isEmpty, "the opener is superseded by the top set")
        #expect(result.perSet[1].axes.contains(.weight), "25 kg beats 17.5")
        #expect(result.perSet[1].axes.contains(.e1rm), "31.03 beats 25.2 — the axis the floor used to hide")

        // The headline: TWO records for this movement, which is what the
        // comparison app reported for the same two sets and what Onyx reported
        // one of.
        #expect(result.axesByKey.map(\.key) == ["Hammer Curl"])
        #expect(Set(result.axesByKey[0].axes) == [.weight, .e1rm])
        #expect(result.prCount == 2)
    }

    @Test("the axis is judged against the session's own earlier sets, not only the history")
    func laterSetMustBeatTheEarlierOne() {
        // `absorbSet` folds each set back in, so three identical top sets do not
        // each claim the record. A lighter second set therefore wins nothing.
        let result = PrEngine.detectSessionPrs(
            [candidate("Curl", 25, 8), candidate("Curl", 20, 8)],
            history("Curl", [(15, 8)])
        )
        #expect(result.perSet[0].axes.contains(.e1rm))
        #expect(!result.perSet[1].axes.contains(.e1rm), "20 kg × 8 does not beat 25 kg × 8")
    }

    // MARK: Symmetry — the rule that stops a false record on the first session

    @Test("a row that can WIN the axis also raises the bar for it")
    func baselinesAndDetectionUseTheSameRule() {
        // The asymmetry this replaces was real in the other direction: under
        // the floor gate a sub-floor row could not set the bar, so the first
        // sub-floor set after the gate came off would have won against a
        // history that was never allowed to compete. Both sides are now
        // unconditional, and this is the test that holds them together.
        let bar = history("Press", [(100, 3)])   // 100 × 36/34 = 105.88
        #expect(bar.bestE1rm.first?.value == 105.88, "a 3-rep set sets the bar")

        let result = PrEngine.detectSessionPrs([candidate("Press", 100, 3)], bar)
        #expect(!result.perSet[0].axes.contains(.e1rm), "and the same set cannot then beat it")
    }

    @Test("a first-ever set is a data point, not a record")
    func emptyHistoryAwardsNothing() {
        let result = PrEngine.detectSessionPrs([candidate("New Lift", 60, 10)], .empty)
        #expect(result.perSet[0].axes.isEmpty)
        #expect(result.prCount == 0)
    }

    // MARK: The formula's domain, where the bound now lives

    @Test("past the rep ceiling there is no estimate, so there is no axis")
    func aboveTheCeilingNoAxisIsAwarded() {
        // The gate used to be the PROGRAMMED floor. What bounds the axis now is
        // the arithmetic: `37 − reps` goes to zero and then negative, and well
        // before that the estimate is nonsense. `OneRepMax.maxReps` is 16.
        let bar = history("Cable Row", [(40, 10)])
        let result = PrEngine.detectSessionPrs(
            [candidate("Cable Row", 40, 16), candidate("Cable Row", 40, 20)], bar
        )
        #expect(result.perSet[0].axes.contains(.e1rm), "sixteen reps is answered")
        #expect(result.perSet[0].est1rm == 68.57, "40 × 36/21 = 68.571…")
        #expect(!result.perSet[1].axes.contains(.e1rm), "twenty is not")
        #expect(result.perSet[1].est1rm == nil)
    }

    @Test("a set above the ceiling does not raise the bar either")
    func aboveTheCeilingSetsNoBar() {
        let bar = PrEngine.buildBaselines(
            [BaselineSetRow(key: "Cable Row", weightKg: 40, reps: 30)],
            isTimed: { _ in false }
        )
        #expect(bar.bestE1rm.isEmpty, "no estimate, so nothing to bump")
    }

    @Test("unloaded work has no e1RM axis at all")
    func unloadedWorkHasNoAxis() {
        let bar = history("Reverse Crunch", [(0, 15)])
        #expect(bar.bestE1rm.isEmpty)
        let result = PrEngine.detectSessionPrs([candidate("Reverse Crunch", 0, 17)], bar)
        #expect(!result.perSet[0].axes.contains(.e1rm))
        #expect(result.perSet[0].axes.contains(.reps), "reps ARE the record at zero load")
    }

    // MARK: Eligibility that did NOT change

    @Test("warm-ups, drop sets and ghosts still win nothing and still set no bar")
    func ineligibleTypesAreStillIneligible() {
        for type in ["warmup", "dropset", "ghost"] {
            let bar = PrEngine.buildBaselines(
                [BaselineSetRow(key: "Press", weightKg: 200, reps: 10, setType: type)],
                isTimed: { _ in false }
            )
            #expect(bar.bestE1rm.isEmpty, "\(type) sets no bar")

            let result = PrEngine.detectSessionPrs(
                [candidate("Press", 200, 10, setType: type)], history("Press", [(50, 10)])
            )
            #expect(result.perSet[0].axes.isEmpty, "\(type) wins nothing")
        }
    }

    @Test("a timed hold is still judged on duration alone")
    func timedWorkIsUnaffected() {
        let bar = PrEngine.buildBaselines(
            [BaselineSetRow(key: "Side Plank", weightKg: 0, reps: 45)],
            isTimed: { _ in true }
        )
        var set = candidate("Side Plank", 0, 60)
        set.timed = true
        let result = PrEngine.detectSessionPrs([set], bar)
        #expect(result.perSet[0].axes == [.reps], "duration rides in reps, and it is the only axis")
    }

    /// ── THE BAR IS THE FORMULA, NEVER THE STORED NUMBER (Lane C) ────────────
    /// `est_1rm_kg` was written by whichever formula the client had on the
    /// day: Epley until 2026-09-15, Brzycki since. Reading it with `||` built a
    /// bar from two formulas at once — LOW for reps above ten (a repeat of
    /// 42.5 × 12 "beat" its own Epley 59.5 with Brzycki 61.2) and HIGH below
    /// ten (an Epley 63.3 for 50 × 8 hid a Brzycki 62.07). The candidate side
    /// always computed; now the bar does too, and the stored column is a
    /// display cache and nothing more.
    @Test("a stored estimate is ignored; the bar is Brzycki over the row's load and reps")
    func storedEstimateIsIgnored() {
        let stored = PrEngine.buildBaselines(
            [BaselineSetRow(key: "Press", weightKg: 100, reps: 5, est1rm: 999)],
            isTimed: { _ in false }
        )
        #expect(stored.bestE1rm.first?.value == 112.5, "100 × 36/32, not the stored 999")

        let zero = PrEngine.buildBaselines(
            [BaselineSetRow(key: "Press", weightKg: 100, reps: 5, est1rm: 0)],
            isTimed: { _ in false }
        )
        #expect(zero.bestE1rm.first?.value == 112.5)
    }
}
