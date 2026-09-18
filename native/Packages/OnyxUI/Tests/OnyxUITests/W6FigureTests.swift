#if os(iOS)
import Testing
import SwiftUI
import OnyxCore
@testable import OnyxUI

/// The W6 figures' arithmetic, stated where a screenshot cannot state it.
///
/// ── WHAT A SHOT CANNOT CATCH ────────────────────────────────────────────────
/// The contact sheet reviews layout, and layout is most of what these views
/// are. Three of them also DECIDE something — where on a dial the night began,
/// how many glasses a goal is worth, which muscle is furthest behind — and an
/// off-by-one-hour arc or a glass rounded the wrong way looks exactly as
/// plausible as the right answer in a PNG. Those three are here.
@Suite("W6 figures")
struct W6FigureTests {

    // ── ChargeArc ───────────────────────────────────────────────────────────

    @Test("the arc starts where the night did, on a 24-hour dial")
    func chargeArcTurn() {
        // Midnight is the top; noon is halfway round; 23:41 is almost back.
        #expect(ChargeArc.turn("00:00") == 0)
        #expect(ChargeArc.turn("12:00") == 0.5)
        #expect(abs(ChargeArc.turn("23:41") - 1421.0 / 1440) < 1e-12)
        // A 24-hour dial, not a 12-hour one: an evening bedtime and a morning
        // one must not land on the same angle.
        #expect(ChargeArc.turn("07:00") != ChargeArc.turn("19:00"))
    }

    @Test("an unreadable or absent bedtime starts at the top, never at random")
    func chargeArcFallback() {
        for bad in [nil, "", "not a time", "24:00", "12:60", "12", "12:00:00"] {
            #expect(ChargeArc.turn(bad) == 0, "\(bad ?? "nil")")
        }
    }

    // ── GlassArc ────────────────────────────────────────────────────────────

    @Test("the goal decides how many segments, and a glass is 250 ml")
    func glassArcSegments() {
        // 3 L is twelve glasses; 1 900 ml is seven of them, and the eighth
        // part-drunk is NOT one — a segment is a glass.
        let three = GlassArc.segments(ml: 1900, goalMl: 3000)
        #expect(three?.total == 12)
        #expect(three?.filled == 7)
        // The brief's eight segments are what a 2 L goal comes to.
        #expect(GlassArc.segments(ml: 0, goalMl: 2000)?.total == 8)
        // Over the goal fills the arc and never wraps it.
        #expect(GlassArc.segments(ml: 9000, goalMl: 2000)?.filled == 8)
        // No goal is no segments — there is nothing to be a fraction of.
        #expect(GlassArc.segments(ml: 1900, goalMl: nil) == nil)
        #expect(GlassArc.segments(ml: 1900, goalMl: 0) == nil)
        // No reading with a goal is an empty arc, not an absent one.
        #expect(GlassArc.segments(ml: nil, goalMl: 2000)?.filled == 0)
        // A goal past the clamp draws sixteen, not sixty.
        #expect(GlassArc.segments(ml: 0, goalMl: 15_000)?.total == GlassArc.maxSegments)
    }

    // ── HeatStrip ───────────────────────────────────────────────────────────

    private func muscle(_ name: String, _ sets: Double, _ target: Int) -> OnyxSnapshot.MuscleVolume {
        OnyxSnapshot.MuscleVolume(muscle: name, sets: sets, target: target)
    }

    // `MuscleLadder`, never `HeatStrip`: reaching into a `View` from a
    // nonisolated test hung the host until the harness timed it out — see
    // `MuscleLadder`'s own note. That is how this file first failed.
    @Test("the ladder runs from most covered to least, and names its tail")
    func heatStripOrder() {
        let week = [
            muscle("Side delts", 3, 9),      // 0.33 — the tail
            muscle("Chest", 12, 12),         // 1.00
            muscle("Triceps", 11, 10),       // 1.10 — over
            muscle("Quads", 8, 10),          // 0.80
        ]
        #expect(MuscleLadder.rows(week).map(\.muscle) == ["Triceps", "Chest", "Quads", "Side delts"])
        #expect(MuscleLadder.laggard(week)?.muscle == "Side delts")
    }

    @Test("a muscle the plan never asked for is not a gap")
    func heatStripDropsUnplanned() {
        // Adductors at 0/0 is what the phase asks of it, and a cell at zero
        // beside fifteen full ones would read as the thing to fix.
        let week = [muscle("Chest", 12, 12), muscle("Adductors", 0, 0)]
        #expect(MuscleLadder.rows(week).map(\.muscle) == ["Chest"])
        // A week that met everything has no tail to name.
        #expect(MuscleLadder.laggard(week) == nil)
    }

    @Test("coverage is uncapped, so past target and at target are different facts")
    func heatStripCoverage() {
        #expect(MuscleLadder.coverage(muscle("Triceps", 11, 10)) == 1.1)
        #expect(MuscleLadder.coverage(muscle("Chest", 12, 12)) == 1)
        // No target and some work done is "covered": there was nothing to miss.
        #expect(MuscleLadder.coverage(muscle("Forearms", 4, 0)) == 1)
        #expect(MuscleLadder.coverage(muscle("Forearms", 0, 0)) == 0)
    }

    // ── Record.margin ───────────────────────────────────────────────────────

    @Test("a record reports a margin only over a bar it actually cleared")
    func recordMargin() {
        func record(_ value: Double, previous: Double?, axis: String = "weight") -> OnyxSnapshot.Record {
            OnyxSnapshot.Record(exercise: "Back Squat", axis: axis, value: value,
                                achievedOn: "2026-09-03", previous: previous)
        }
        #expect(record(105, previous: 100).margin == 5)
        #expect(record(105, previous: 100).marginText == "+5.0 kg")
        // Nothing before it: "first on the board", never a manufactured gain.
        #expect(record(105, previous: nil).margin == nil)
        #expect(record(105, previous: nil).marginText == nil)
        // A compiled floor ABOVE a logged record is no gain, not a negative one.
        #expect(record(105, previous: 110).margin == nil)
        #expect(record(105, previous: 105).margin == nil)
        // Each axis in its own units.
        #expect(record(18, previous: 16, axis: "reps").marginText == "+2 reps")
        #expect(record(780, previous: 735, axis: "volume").marginText == "+45 kg")
        #expect(record(60, previous: 45, axis: "seconds").marginText == "+15s")
        // Half a kilo is still a record; rounding it to "+0" would say otherwise.
        #expect(record(30.5, previous: 30).marginText == "+0.5 kg")
    }

    // ── VitalSpec.lead ──────────────────────────────────────────────────────

    @Test("the most deviant reading leads, measured in its own full scale")
    func vitalLead() {
        // Resting HR is 3 under an 8-point scale (0.375); HRV is 5 over a
        // 20-point one (0.25). The raw numbers say HRV; the scales say the
        // heart, which is the reading with something to report.
        let vitals = OnyxSnapshot.Vitals(
            hrvMs: OnyxSnapshot.Vital(value: 54, baseline: 49),
            restingBpm: OnyxSnapshot.Vital(value: 52, baseline: 55))
        #expect(VitalSpec.lead(vitals).label == VitalSpec.restingBpm.label)
        #expect(VitalSpec.ranked(vitals).first?.label == VitalSpec.restingBpm.label)
        // Direction is not part of it: a reading five milliseconds DOWN is as
        // much a fact about the night as one five up.
        let down = OnyxSnapshot.Vitals(
            hrvMs: OnyxSnapshot.Vital(value: 44, baseline: 49),
            restingBpm: OnyxSnapshot.Vital(value: 55, baseline: 55))
        #expect(VitalSpec.lead(down).label == VitalSpec.hrv.label)
        // A reading with no baseline is not a deviation of zero, and a night
        // with no baselines at all falls back to HRV rather than to nothing.
        #expect(VitalSpec.deviation(.hrv, OnyxSnapshot.Vitals(hrvMs: OnyxSnapshot.Vital(value: 54))) == nil)
        #expect(VitalSpec.lead(nil).label == VitalSpec.hrv.label)
        // All five are ranked, none dropped.
        #expect(VitalSpec.ranked(vitals).count == VitalSpec.all.count)
    }

    // ── MacroRemainder ──────────────────────────────────────────────────────

    @Test("the fuel faces say what is LEFT, in one wording")
    func macroRemainder() {
        #expect(MacroRemainder.text(128, 170) == "42 g left")
        #expect(MacroRemainder.text(170, 170) == "met")
        #expect(MacroRemainder.text(182, 170) == "+12 g over")
        // A goal with no intake still says what the day is asking for.
        #expect(MacroRemainder.text(nil, 170) == "170 g left")
        // Nothing to be left OF without a goal.
        #expect(MacroRemainder.text(128, nil) == nil)
    }
}
#endif
