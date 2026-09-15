import Foundation
import Testing
@testable import OnyxCore

/// Claims that must hold in Swift for the same reasons they hold in TypeScript.
///
/// The golden vectors prove the port agrees with its source. These prove the
/// source's own rules survived translation as rules — so that editing a constant
/// in `Battery.swift` alone fails here, rather than silently producing a model
/// that is internally consistent and wrong.
@Suite("Domain invariants")
struct InvariantTests {

    // MARK: Battery

    @Test("the drain budget stays strictly under the charge budget — the rule v6 broke")
    func drainBudgetUnderChargeBudget() {
        // v6's arithmetic reached 104.2 against a 100-point charge, so a leg day
        // hit the floor before bedtime no matter how well you slept. The reading
        // that should be most informative had no dynamic range at all.
        #expect(Battery.maxTotalDrain < 100 - Battery.defaults.floor)
    }

    @Test("v9: timeMax 35 + activityCap 12 + workoutMax 32 + loadCap 8 + wellnessCap 6 = 93 < 100")
    func v9BudgetIsNinetyThree() {
        let d = Battery.defaults
        #expect(d.timeMax == 35 && d.activityCap == 12 && d.workoutMax == 32 && d.loadCap == 8 && d.wellnessCap == 6)
        #expect(Battery.maxTotalDrain == 93)
        #expect(Battery.maxTotalDrain < 100)
        // The lowest a perfect night can start is a full 100 (v9 retired the
        // onset penalty on the charge); the floor stays out of reach even then.
        #expect(100 - Battery.maxTotalDrain > d.floor)
        // The per-day ceilings are what the budget is checked against.
        #expect(Battery.workoutMaxByDay.values.max() == d.workoutMax)
        #expect(Battery.workoutMaxByDay["legs_a"] == 32 && Battery.workoutMaxByDay["cb_a"] == 24 && Battery.workoutMaxByDay["arms"] == 16)
    }

    @Test("the load and wellness drains never exceed their caps and never recharge")
    func v9DrainsStayInBand() {
        let worstLoad = Battery.loadDrain(ScoringInputs(acwr: 9, strainZ: 9))
        #expect(worstLoad == Battery.defaults.loadCap)
        let lightLoad = Battery.loadDrain(ScoringInputs(acwr: 0.5, strainZ: -2))
        #expect(lightLoad == 0)
        let worstWellness = Battery.wellnessDrain(ScoringInputs(sleepHours: 0, domsSeverity: 3, sleepOnsetTrouble: true, fatigueLevel: 5))
        #expect(worstWellness == Battery.defaults.wellnessCap)
        let quiet = Battery.wellnessDrain(ScoringInputs(sleepHours: 8, sleepGoalHours: 8, sleepOnsetTrouble: false))
        #expect(quiet == 0)
        let unanswered = Battery.wellnessDrain(ScoringInputs(sleepHours: 0))
        #expect(unanswered == 0)
        for level in [-1.0, 0, 0.5, 1, 2, 3, 4, 5, 6, 99] {
            let term = Battery.wellnessParts(ScoringInputs(sleepHours: 0, fatigueLevel: level)).fatigue ?? 0
            #expect(term >= 0 && term <= 1, "fatigue item out of band at level \(level)")
        }
    }

    @Test("a missing z is neutral, never a penalty")
    func missingZIsNeutral() {
        let bare = ScoringInputs(sleepHours: 8, deepMinutes: 60, remMinutes: 90)
        var zero = bare
        zero.hrvZ = 0
        zero.rhrZ = 0
        #expect(Battery.sleepQualityParts(bare) == Battery.sleepQualityParts(zero))
        #expect(Battery.zQuality(nil) == Battery.defaults.zNeutral)
        // And v8's seven-day baselines no longer move the charge.
        var v8 = bare
        v8.hrvMs = 30
        v8.hrvBaseline = 60
        v8.restingHR = 70
        v8.baselineHR = 52
        #expect(Battery.computeBattery(bare) == Battery.computeBattery(v8))
    }

    @Test("maintenance can only ever lower a drain, never raise the worst case")
    func maintenanceOnlyLowers() {
        #expect(Battery.maintenanceDrainFactor < 1)
        #expect(Battery.maintenanceRelMin < Battery.defaults.relMin)

        // Concretely, for every day type.
        for dayKey in Battery.workoutMaxByDay.keys {
            #expect(
                Battery.workoutMaxFor(dayKey: dayKey, maintenance: true)
                    < Battery.workoutMaxFor(dayKey: dayKey, maintenance: false)
            )
        }
    }

    @Test("time drain is monotonic and spans exactly 0 to timeMax")
    func timeDrainIsMonotonic() {
        #expect(Battery.timeDrain(hoursAwake: 0) == 0)
        expectClose(
            Battery.timeDrain(hoursAwake: Battery.defaults.maxAwake),
            Battery.defaults.timeMax,
            "an 18-hour day costs the full time budget"
        )

        var previous = -Double.infinity
        for step in 0...180 {
            let value = Battery.timeDrain(hoursAwake: Double(step) / 10)
            #expect(value >= previous, "time drain went backwards at hour \(Double(step) / 10)")
            previous = value
        }

        // Clamped at both ends: a negative or over-long day must not escape.
        #expect(Battery.timeDrain(hoursAwake: -5) == 0)
        expectClose(
            Battery.timeDrain(hoursAwake: 48),
            Battery.defaults.timeMax,
            "an over-long day is clamped, not extrapolated"
        )
    }

    @Test("the battery never leaves its band, on any input in the exported grid")
    func batteryStaysInBand() throws {
        let fixture = try GoldenFixture<
            BatteryGoldenTests.BatteryInput, BatteryGoldenTests.BatteryExpected
        >.load("battery")

        for c in fixture.cases {
            let state = Battery.computeBattery(c.input.inputs, hoursAwake: c.input.hoursAwakeArg)
            #expect(state.currentPct >= Battery.defaults.floor, "below the floor — \(c.name)")
            #expect(state.currentPct <= 100, "above 100 — \(c.name)")
            #expect(state.morningCharge >= Battery.defaults.wakeMin, "wake charge below wakeMin — \(c.name)")
            #expect(state.morningCharge <= 100, "wake charge above 100 — \(c.name)")
        }
    }

    @Test("no recharge term exists: adding intake can never raise the battery")
    func noRechargeTerm() {
        // The protein/water bug: eating breakfast used to make the battery jump.
        // Drain-only means nutrition is not an input to this model at all, so
        // varying it must change nothing.
        let base = ScoringInputs(sleepHours: 7, deepMinutes: 60, hoursAwake: 10)
        var fed = base
        fed.calories = 2400
        fed.proteinG = 190
        fed.waterMl = 3200

        #expect(Battery.computeBattery(base) == Battery.computeBattery(fed))
    }

    // MARK: Stress (Phase 3 E3)

    @Test("stress: a missing term is neutral — excluded, renormalised — and nothing answered is no reading")
    func stressMissingTermsNeutral() {
        #expect(Stress.breakdown(StressInputs()).index == nil)
        #expect(Stress.breakdown(StressInputs()).weightSum == 0)
        // One term alone at +2 is the full 90, whichever term it is.
        #expect(Stress.index(StressInputs(hrvZ: -2)) == 90)
        #expect(Stress.index(StressInputs(fragZ: 2)) == 90)
        #expect(Stress.index(StressInputs(fatigueDayMean: 5)) == 90)
        #expect(Stress.index(StressInputs(acwr: 2, strainZ: 2)) == 90)
        // Non-finite is missing, never a number.
        #expect(Stress.breakdown(StressInputs(hrvZ: .nan, rhrZ: .infinity)).terms.auto.answered == 0)
    }

    @Test("stress: load is never negative and never above the clamp")
    func stressLoadNeverNegative() {
        for acwr in [nil, 0, 0.5, 1.0, 1.29, 1.3, 1.65, 2.0, 3.0, 9.0] as [Double?] {
            for strainZ in [nil, -9, -2, -1, 0, 1, 2, 9] as [Double?] {
                let t = Stress.breakdown(StressInputs(acwr: acwr, strainZ: strainZ)).terms.load
                if acwr == nil && strainZ == nil { #expect(t.z == nil); continue }
                let z = t.z ?? -1
                #expect(z >= 0 && z <= 2, "load z out of band at acwr \(String(describing: acwr)) strainZ \(String(describing: strainZ))")
                #expect(t.acwrTerm >= 0 && t.strainTerm >= 0)
            }
        }
        #expect(Stress.loadParts(acwr: 1.3, strainZ: nil).acwrTerm == 0)
        #expect(Stress.loadParts(acwr: 2.0, strainZ: nil).acwrTerm == 2)
        #expect(Stress.loadParts(acwr: 3.0, strainZ: nil).acwrTerm == 2)
    }

    @Test("stress: S stays in [10, 90], is an integer, and 50 is Baseline")
    func stressStaysInBand() {
        let grid: [Double?] = [nil, -9, -2, -1, 0, 1, 2, 9]
        for hrv in grid { for rhr in grid { for frag in grid { for fatigue in [nil, -5, 1, 3, 5, 99] as [Double?] {
            let b = Stress.breakdown(StressInputs(hrvZ: hrv, rhrZ: rhr, fragZ: frag, sleepOnsetTrouble: true, fatigueDayMean: fatigue, acwr: 9, strainZ: 9))
            guard let s = b.index else { continue }
            #expect(s >= Stress.constants.min && s <= Stress.constants.max)
            #expect(s == s.rounded())
        } } } }
        #expect(Stress.band(50) == .baseline)
        #expect(Stress.band(30) == .baseline && Stress.band(29) == .calm)
        #expect(Stress.band(62) == .elevated && Stress.band(63) == .high)
        #expect(Stress.band(75) == .high && Stress.band(76) == .overreached)
        #expect(Stress.breakdown(StressInputs(hrvZ: 0, rhrZ: 0, fragZ: 0, sleepOnsetTrouble: false, fatigueDayMean: 3, acwr: 1, strainZ: 0)).index == 50)
    }

    @Test("stress: Battery.breakdown is mathematically isolated — no stress input reaches it, the budget is still 93")
    func batteryIsolatedFromStress() {
        let inputs = ScoringInputs(
            sleepHours: 7, deepMinutes: 60, remMinutes: 90, hrvZ: -1, rhrZ: 1, acwr: 1.5, strainZ: 1,
            sleepOnsetTrouble: true, fatigueLevel: 4, hoursAwake: 10
        )
        let before = Battery.breakdown(inputs)
        for s in [
            StressInputs(),
            StressInputs(hrvZ: 0, rhrZ: 0, fragZ: 0, sleepOnsetTrouble: false, fatigueDayMean: 3, acwr: 1, strainZ: 0),
            StressInputs(hrvZ: -2, rhrZ: 2, fragZ: 2, sleepOnsetTrouble: true, fatigueDayMean: 5, acwr: 2, strainZ: 2),
        ] {
            _ = Stress.breakdown(s)
            #expect(Battery.breakdown(inputs) == before)
        }
        #expect(Battery.maxTotalDrain == 93)
        // The type itself carries nothing the index reads that the battery does not: the
        // two share `hrvZ`/`rhrZ`/`acwr`/`strainZ`/onset by design, and `fragZ` and
        // `fatigueDayMean` exist on `StressInputs` only. A compile-time fact, stated.
        let mirror = Mirror(reflecting: inputs)
        #expect(!mirror.children.contains { $0.label == "fragZ" || $0.label == "fatigueDayMean" })
    }

    @Test("stress: fragmentation — a duration-only night is a hole, a still night with stages is a real zero")
    func fragmentationRule() {
        #expect(Stress.fragmentationRatio(.init(awakeMin: 0, asleepMin: 420, deepMin: 0, remMin: 0)) == nil)
        #expect(Stress.fragmentationRatio(.init(awakeMin: 0, asleepMin: 420, deepMin: 60, remMin: 90)) == 0)
        #expect(Stress.fragmentationRatio(.init(awakeMin: 42, asleepMin: 420)) == 0.1)
        #expect(Stress.fragmentationRatio(.init(awakeMin: 42, asleepMin: 0)) == nil)
        #expect(Fatigue.dayMean([:]) == nil)
        #expect(Fatigue.dayMean([.waking: 1, .pre: 3, .post: 5]) == 3)
    }

    // MARK: Vitals gates

    @Test("hrv: an artifact is a reading far outside the athlete's own band, judged by median and MAD")
    func hrvArtifactGate() {
        // A month of nights around 60 ms, spread ±6.
        let history: [Double] = [58, 61, 55, 64, 60, 57, 63, 59, 66, 54, 62, 60, 58, 65]
        #expect(VitalsGate.hrvArtifact(64, history: history) == nil, "inside the band")
        #expect(VitalsGate.hrvArtifact(40, history: history) == nil, "a rough night is not an artifact")
        #expect(VitalsGate.hrvArtifact(95, history: history) == nil, "a rebound after a deload is not an artifact either")
        #expect(VitalsGate.hrvArtifact(180, history: history) != nil, "three times the median is a strap")
        #expect(VitalsGate.hrvArtifact(12, history: history) != nil)
        // Too little history to know the band: only the physiologic bounds bite.
        #expect(VitalsGate.hrvArtifact(180, history: [60, 62]) == nil)
        #expect(VitalsGate.hrvArtifact(2, history: [60, 62]) != nil)
        #expect(VitalsGate.hrvArtifact(400, history: []) != nil)
        // A flat history (MAD 0) still has a band — half the median — so a
        // rough night passes and a doubled reading does not.
        #expect(VitalsGate.hrvArtifact(35, history: Array(repeating: 60, count: 10)) == nil)
        #expect(VitalsGate.hrvArtifact(25, history: Array(repeating: 60, count: 10)) != nil)
        #expect(VitalsGate.hrvArtifact(115, history: Array(repeating: 60, count: 10)) == nil)
        #expect(VitalsGate.hrvArtifact(130, history: Array(repeating: 60, count: 10)) != nil)
    }

    @Test("body: the percentages a scale can report have physiologic bounds")
    func bodyPercentBounds() {
        #expect(VitalsGate.bodyFatArtifact(18.2) == nil && VitalsGate.bodyFatArtifact(1.5) != nil && VitalsGate.bodyFatArtifact(71) != nil)
        #expect(VitalsGate.musclePercentArtifact(41) == nil && VitalsGate.musclePercentArtifact(9) != nil && VitalsGate.musclePercentArtifact(85.1) != nil)
        // A lean InBody reading. Muscle % is lean SOFT TISSUE, not skeletal
        // muscle, and the old 70 ceiling refused this one.
        #expect(VitalsGate.musclePercentArtifact(80.2) == nil && VitalsGate.musclePercentArtifact(77.6) == nil)
        #expect(VitalsGate.visceralFatArtifact(6) == nil && VitalsGate.visceralFatArtifact(0) != nil && VitalsGate.visceralFatArtifact(31) != nil)
        #expect(VitalsGate.bodyFatArtifact(.nan) != nil)
    }

    // MARK: One-rep max

    @Test("unloaded work has no estimate — nil, never zero")
    func unloadedWorkHasNoEstimate() {
        // The exact shape that printed "1RM 0" beside a Reverse Crunch 0 kg × 17
        // and flattened the movement's entire progress chart.
        #expect(OneRepMax.estimate(weight: 0, reps: 17) == nil)
        #expect(OneRepMax.estimate(weight: 0, reps: 1) == nil)
        #expect(OneRepMax.estimate(weight: -12, reps: 5) == nil)
        #expect(OneRepMax.estimate(weight: .nan, reps: 5) == nil)
        #expect(OneRepMax.estimate(weight: .infinity, reps: 5) == nil)
    }

    @Test("a single rep returns the load itself")
    func singleRepIsTheLoad() {
        // Brzycki at one rep is `36/36`, so this falls out of the formula
        // rather than being special-cased — which is why the special case Epley
        // needed could be deleted rather than ported.
        #expect(OneRepMax.estimate(weight: 142.5, reps: 1) == 142.5)
    }

    @Test("the formula refuses the rep counts it cannot answer for")
    func repDomainIsRefusedNotExtrapolated() {
        // `37 − reps` is zero at 37 and negative above it, so an unguarded
        // Brzycki reports a NEGATIVE one-rep max for a 40-rep set — and an
        // absurd one well below that (a 30-rep set estimates at five times the
        // load, which would stand as a permanent record no set could beat).
        #expect(OneRepMax.estimate(weight: 25, reps: 16) != nil, "the ceiling itself is answered")
        #expect(OneRepMax.estimate(weight: 25, reps: 17) == nil)
        #expect(OneRepMax.estimate(weight: 25, reps: 37) == nil, "the singularity")
        #expect(OneRepMax.estimate(weight: 25, reps: 40) == nil, "past it, where the sign flips")
        #expect(OneRepMax.estimate(weight: 25, reps: 0) == nil, "a set of no reps is not a set")
        #expect(OneRepMax.estimate(weight: 25, reps: .nan) == nil)
    }

    @Test("the Hammer Curl session that reported one PR where it should have reported two")
    func hammerCurlTopSetHasAnEstimate() {
        // 2026-09-15. Hammer Curl is programmed 10–12; the session was
        // 20 kg × 10 then 25 kg × 8. The top set was BELOW the programmed floor,
        // so the old `e1rmEligible` refused it the e1RM axis — the deck awarded
        // Heaviest and nothing else while every other app reported a best
        // estimated 1RM too. Both sets now carry one, and the heavier set's is
        // the higher, which is what makes the axis winnable.
        let opener = OneRepMax.estimate(weight: 20, reps: 10)
        let top = OneRepMax.estimate(weight: 25, reps: 8)
        #expect(opener == 26.67)
        #expect(top == 31.03)
        #expect((top ?? 0) > (opener ?? 0))
    }

    // MARK: Energy

    @Test("TDEE is all-or-nothing: a missing component yields nil, not a partial total")
    func tdeeIsAllOrNothing() {
        // A null propagates; a zero lies. A day with no active-energy sync must
        // not report a 400 kcal larger deficit than it earned.
        #expect(Energy.tdee(bmr: nil, active: 400, intakeKcal: 1900) == nil)
        #expect(Energy.tdee(bmr: 1500, active: nil, intakeKcal: 1900) == nil)
        #expect(Energy.tdee(bmr: 1500, active: 400, intakeKcal: nil) == nil)
        #expect(Energy.tdee(bmr: 1500, active: 400, intakeKcal: 1900) != nil)
    }

    @Test("TEF is included, and it is not a rounding error")
    func tefIsMaterial() {
        // ~200 kcal/day on a ~1900 kcal intake — a fifth of a kilo of fat a week
        // that `BMR + active` credited to nothing.
        let tef = try! #require(Energy.tef(intakeKcal: 1900))
        #expect(tef > 190 && tef < 210)
    }

    // MARK: Rounding

    @Test("jsRound follows JavaScript's rule, not Swift's")
    func jsRoundMatchesJavaScript() {
        // Math.round rounds a half towards POSITIVE INFINITY. Swift's rounded()
        // rounds away from zero. They differ on every negative half, which is
        // precisely the input a hand-written test grid never contains.
        #expect(jsRound(2.5) == 3)
        #expect(jsRound(-2.5) == -2)
        #expect(jsRound(0.5) == 1)
        #expect(jsRound(-0.5) == 0)
        #expect(jsRound(1.4999999) == 1)

        // The divergence, stated as the assertion that would have caught it.
        #expect(jsRound(-2.5) != (-2.5).rounded())
    }
}
