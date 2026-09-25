import Foundation
import Testing
@testable import OnyxCore

// Precision E3: a program's goal — the five kinds, the arithmetic each one
// runs, and the implied weekly rate judged against the safe band. Every number
// is hand-computed.

@Suite("Precision E3 · program goal kinds")
struct ProgramGoalKindTests {

    /// The wire format the CHECK constraint in `precision-e-programs.sql` names.
    @Test func rawValuesAreTheWireFormat() {
        #expect(ProgramGoal.allCases.map(\.rawValue) == ["bulk", "cut", "recomp", "muscle_mass", "body_fat"])
    }

    @Test func eachKindTrainsInOneDirection() {
        #expect(ProgramGoal.bulk.phase == .bulk)
        #expect(ProgramGoal.muscleMass.phase == .bulk)
        #expect(ProgramGoal.cut.phase == .cut)
        #expect(ProgramGoal.bodyFat.phase == .cut)
        // Recomp holds the scale still, which trains on the cut's volume — the
        // rule `StartingGoal.maintain` already states.
        #expect(ProgramGoal.recomp.phase == .cut)
    }

    /// bulk/muscle → Onyx 5, cut/body fat → Onyx 4, recomp → PPL (brief E3).
    @Test func recommendedTemplates() {
        #expect(ProgramGoal.bulk.recommendedTemplateId == "onyx5")
        #expect(ProgramGoal.muscleMass.recommendedTemplateId == "onyx5")
        #expect(ProgramGoal.cut.recommendedTemplateId == "onyx4")
        #expect(ProgramGoal.bodyFat.recommendedTemplateId == "onyx4")
        #expect(ProgramGoal.recomp.recommendedTemplateId == "ppl")
    }

    @Test func everyKindExplainsItself() {
        for goal in ProgramGoal.allCases {
            #expect(!goal.label.isEmpty)
            #expect(!goal.blurb.isEmpty)
        }
    }

    /// An unknown string on the wire is no goal, never a crash — `PlanInfo` is
    /// in the watch's context and one bad row must not fail the whole decode.
    @Test func planInfoReadsAnUnknownKindAsNoGoal() throws {
        let info = PlanInfo(id: "p", label: "P", blurb: "", goalKind: "shred")
        #expect(info.goal == nil)
        let known = PlanInfo(id: "p", label: "P", blurb: "", goalKind: "body_fat")
        #expect(known.goal == .bodyFat)
        // Old JSON (no goal keys) still decodes.
        let old = try JSONDecoder().decode(PlanInfo.self, from: Data(#"{"id":"a","label":"A","blurb":"","isLegacy":false,"sort":0}"#.utf8))
        #expect(old.goal == nil)
        #expect(old.goalTarget == nil)
    }
}

@Suite("Precision E3 · the goal target on the wire")
struct ProgramGoalTargetTests {

    @Test func roundTripsInSnakeCase() throws {
        let target = ProgramGoalTarget(
            targetWeightKg: 72, targetBodyFatPct: nil, targetMuscleMassKg: nil,
            weeklyRateKg: -0.42, horizonWeeks: 12, startWeightKg: 77
        )
        let text = target.encoded()
        #expect(text.contains("\"target_weight_kg\":72"))
        #expect(text.contains("\"horizon_weeks\":12"))
        #expect(!text.contains("target_body_fat_pct"), "nil stays out of the object")
        #expect(ProgramGoalTarget.decode(text) == target)
    }

    @Test func garbageDecodesToNil() {
        #expect(ProgramGoalTarget.decode("not json") == nil)
    }
}

@Suite("Precision E3 · targets per goal")
struct ProgramGoalTargetsTests {

    /// Bulk and muscle mass eat like a bulk; cut and body fat like a cut —
    /// the 27/37 kcal/kg basis W5 already ships, unchanged.
    @Test func directionalGoalsReuseTheOnboardingTable() {
        for weight in [55.0, 80.0, 110.0] {
            #expect(StartingTargetsBuilder.build(weightKg: weight, programGoal: .bulk)
                    == StartingTargetsBuilder.build(weightKg: weight, goal: .bulk))
            #expect(StartingTargetsBuilder.build(weightKg: weight, programGoal: .muscleMass)
                    == StartingTargetsBuilder.build(weightKg: weight, goal: .bulk))
            #expect(StartingTargetsBuilder.build(weightKg: weight, programGoal: .cut)
                    == StartingTargetsBuilder.build(weightKg: weight, goal: .cut))
            #expect(StartingTargetsBuilder.build(weightKg: weight, programGoal: .bodyFat)
                    == StartingTargetsBuilder.build(weightKg: weight, goal: .cut))
        }
    }

    /// Recomp = maintenance energy (33 kcal/kg) with the cut's protein (2.2
    /// g/kg); fat at maintenance's 0.9. At 80 kg: protein 176, fat 72, budget
    /// 2,640 → carbs (2640 − 704 − 648) / 4 = 322 → 2,640 kcal exactly.
    @Test func recompIsMaintenanceWithTheCutsProtein() {
        let t = StartingTargetsBuilder.build(weightKg: 80, programGoal: .recomp)
        #expect(t.proteinG == 176)
        #expect(t.fatG == 72)
        #expect(t.carbsG == 322)
        #expect(t.kcal == 2_640)
        #expect(t.fiberG == 37)  // 2640 / 1000 × 14 = 36.96
        let maintain = StartingTargetsBuilder.build(weightKg: 80, goal: .maintain)
        #expect(t.proteinG > maintain.proteinG)
        #expect(t.kcal == maintain.kcal, "same energy, different split")
    }

    @Test func everyGoalsMacrosAddUp() {
        for goal in ProgramGoal.allCases {
            for weight in stride(from: 40.0, through: 160.0, by: 5) {
                let t = StartingTargetsBuilder.build(weightKg: weight, programGoal: goal)
                #expect(t.atwaterKcal == t.kcal, "\(goal) at \(weight) kg")
            }
        }
    }

    /// Bands in kg/week at 80 kg: cut −0.56…−0.32, bulk +0.16…+0.32, recomp
    /// ±0.08 (±0.1 % of bodyweight — the scale's weekly noise, not a direction).
    @Test func safeBandsPerGoal() {
        let cut = StartingTargetsBuilder.weeklyRate(weightKg: 80, programGoal: .cut)
        #expect(cut.min == -0.56 && cut.max == -0.32)
        #expect(StartingTargetsBuilder.weeklyRate(weightKg: 80, programGoal: .bodyFat) == cut)
        let bulk = StartingTargetsBuilder.weeklyRate(weightKg: 80, programGoal: .bulk)
        #expect(bulk.min == 0.16 && bulk.max == 0.32)
        #expect(StartingTargetsBuilder.weeklyRate(weightKg: 80, programGoal: .muscleMass) == bulk)
        let recomp = StartingTargetsBuilder.weeklyRate(weightKg: 80, programGoal: .recomp)
        #expect(recomp.min == -0.08 && recomp.max == 0.08)
    }
}

@Suite("Precision E3 · the implied weekly rate")
struct ImpliedRateTests {

    /// 80 → 74 kg in 12 weeks = −0.5 kg/wk: inside the cut's −0.56…−0.32.
    @Test func weightGoalInsideTheBand() throws {
        let plan = try #require(GoalPace.plan(
            goal: .cut, now: BodyNow(weightKg: 80),
            target: ProgramGoalTarget(targetWeightKg: 74, horizonWeeks: 12)
        ))
        #expect(plan.targetWeightKg == 74)
        #expect(plan.weeklyRateKg == -0.5)
        #expect(plan.verdict == .inside)
    }

    /// 80 → 70 in 8 weeks = −1.25/wk: faster than a cut should go.
    @Test func tooFastACut() throws {
        let plan = try #require(GoalPace.plan(
            goal: .cut, now: BodyNow(weightKg: 80),
            target: ProgramGoalTarget(targetWeightKg: 70, horizonWeeks: 8)
        ))
        #expect(plan.weeklyRateKg == -1.25)
        #expect(plan.verdict == .fast)
    }

    /// 80 → 79 in 20 weeks = −0.05/wk: a cut that barely moves.
    @Test func tooSlowACut() throws {
        let plan = try #require(GoalPace.plan(
            goal: .cut, now: BodyNow(weightKg: 80),
            target: ProgramGoalTarget(targetWeightKg: 79, horizonWeeks: 20)
        ))
        #expect(plan.verdict == .slow)
    }

    @Test func aBulkPastItsCeilingIsFast() throws {
        let plan = try #require(GoalPace.plan(
            goal: .bulk, now: BodyNow(weightKg: 80),
            target: ProgramGoalTarget(targetWeightKg: 86, horizonWeeks: 10)
        ))
        #expect(plan.weeklyRateKg == 0.6)
        #expect(plan.verdict == .fast)
    }

    /// Lean mass held: 80 kg at 20 % is 64 kg lean; at 15 % that is
    /// 64 / 0.85 = 75.29 kg. Over 12 weeks: −0.39 kg/wk, inside.
    @Test func bodyFatConvertsAtConstantLeanMass() throws {
        let plan = try #require(GoalPace.plan(
            goal: .bodyFat, now: BodyNow(weightKg: 80, bodyFatPct: 20),
            target: ProgramGoalTarget(targetBodyFatPct: 15, horizonWeeks: 12)
        ))
        #expect(plan.targetWeightKg == 75.29)
        #expect(plan.weeklyRateKg == -0.39)
        #expect(plan.verdict == .inside)
    }

    /// Muscle added on top of everything else — a lower bound on the scale's
    /// move. 34 → 36 kg of muscle over 10 weeks = +0.2 kg/wk.
    @Test func muscleMassConvertsAsAddedMuscle() throws {
        let plan = try #require(GoalPace.plan(
            goal: .muscleMass, now: BodyNow(weightKg: 80, muscleMassKg: 34),
            target: ProgramGoalTarget(targetMuscleMassKg: 36, horizonWeeks: 10)
        ))
        #expect(plan.targetWeightKg == 82)
        #expect(plan.weeklyRateKg == 0.2)
        #expect(plan.verdict == .inside)
    }

    @Test func recompHoldsTheScale() throws {
        let still = try #require(GoalPace.plan(
            goal: .recomp, now: BodyNow(weightKg: 80),
            target: ProgramGoalTarget(targetWeightKg: 80, horizonWeeks: 12)
        ))
        #expect(still.weeklyRateKg == 0)
        #expect(still.verdict == .inside)
        let drifting = try #require(GoalPace.plan(
            goal: .recomp, now: BodyNow(weightKg: 80),
            target: ProgramGoalTarget(targetWeightKg: 83, horizonWeeks: 12)
        ))
        #expect(drifting.verdict == .fast)
    }

    /// No number to start from, no reading to convert, or no horizon: nothing
    /// is implied, and nothing is drawn.
    @Test func missingInputsImplyNothing() {
        #expect(GoalPace.plan(goal: .cut, now: BodyNow(weightKg: nil),
                              target: ProgramGoalTarget(targetWeightKg: 74, horizonWeeks: 12)) == nil)
        #expect(GoalPace.plan(goal: .bodyFat, now: BodyNow(weightKg: 80),
                              target: ProgramGoalTarget(targetBodyFatPct: 15, horizonWeeks: 12)) == nil)
        #expect(GoalPace.plan(goal: .cut, now: BodyNow(weightKg: 80),
                              target: ProgramGoalTarget(targetWeightKg: 74, horizonWeeks: nil)) == nil)
        #expect(GoalPace.plan(goal: .cut, now: BodyNow(weightKg: 80),
                              target: ProgramGoalTarget(targetWeightKg: 74, horizonWeeks: 0)) == nil)
    }

    /// A mistyped 700 kg must not be graded against the band `weeklyRate`
    /// clamps to 300 kg — two weight bases on one line (invariant audit).
    @Test func aWeightOutsideTheRangeImpliesNothing() {
        #expect(GoalPace.plan(goal: .cut, now: BodyNow(weightKg: 700),
                              target: ProgramGoalTarget(targetWeightKg: 650, horizonWeeks: 12)) == nil)
        #expect(GoalPace.plan(goal: .bulk, now: BodyNow(weightKg: 12),
                              target: ProgramGoalTarget(targetWeightKg: 14, horizonWeeks: 12)) == nil)
    }
}
