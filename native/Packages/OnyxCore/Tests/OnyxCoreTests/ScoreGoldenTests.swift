import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Score — the web app's `lib/scoring/score.ts`, replayed from `npm run golden`
//
// The component fixtures carry only the fields each function reads (the
// TypeScript takes a `Pick`), so each test builds the full `ScoringInputs`
// through the memberwise initialiser. The composite and the alerts are
// exported whole.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Score — the daily score and its components")
struct ScoreGoldenTests {
    struct SleepInput: Decodable {
        let sleepHours, deepMinutes, remMinutes, sleepGoalHours: Double
        let contextMode: String?
        let sleepInBedHours, sleepLatencyMin, sleepAwakeMin, sleepAwakenings, sleepBedtimeDeltaMin: Double?
    }

    /// `sleep-score-v2.json` — W3's hand-computed cases, never regenerated.
    /// The v1 fixture (a 1024-cell sweep exported from the TypeScript) was
    /// retired with the formula: a legacy input with no v2 field is still the
    /// v1 number, and one case here pins that.
    @Test("sleep score v2 matches, term for term")
    func sleepMatches() throws {
        let fixture = try GoldenFixture<SleepInput, Double?>.load("sleep-score-v2")
        #expect(fixture.cases.count >= 12)
        for c in fixture.cases {
            let i = ScoringInputs(
                sleepHours: c.input.sleepHours, deepMinutes: c.input.deepMinutes,
                remMinutes: c.input.remMinutes, sleepGoalHours: c.input.sleepGoalHours,
                contextMode: c.input.contextMode,
                sleepInBedHours: c.input.sleepInBedHours, sleepLatencyMin: c.input.sleepLatencyMin,
                sleepAwakeMin: c.input.sleepAwakeMin, sleepAwakenings: c.input.sleepAwakenings,
                sleepBedtimeDeltaMin: c.input.sleepBedtimeDeltaMin
            )
            expectClose(Score.sleep(i), c.expected, "computeSleepScore v2 — \(c.name)")
        }
    }

    struct NutritionInput: Decodable {
        let calories, proteinG, carbsG, fatG: Double
        let calorieGoal, proteinGoalG, carbsGoalG, fatGoalG: Double
        let nutritionException: Bool?
        let contextMode: String?
    }

    @Test("nutrition score matches, including the exception day and the zero-goal path")
    func nutritionMatches() throws {
        let fixture = try GoldenFixture<NutritionInput, Double?>.load("nutrition-score")
        #expect(fixture.cases.count > 1000)
        for c in fixture.cases {
            let i = ScoringInputs(
                calories: c.input.calories, proteinG: c.input.proteinG, carbsG: c.input.carbsG, fatG: c.input.fatG,
                calorieGoal: c.input.calorieGoal, proteinGoalG: c.input.proteinGoalG,
                carbsGoalG: c.input.carbsGoalG, fatGoalG: c.input.fatGoalG,
                nutritionException: c.input.nutritionException,
                contextMode: c.input.contextMode
            )
            expectClose(Score.nutrition(i), c.expected, "computeNutritionScore — \(c.name)")
        }
    }

    struct ActivityInput: Decodable {
        let steps, activeCal, stepsGoal, activeCalGoal: Double
        let contextMode: String?
    }

    @Test("activity score matches")
    func activityMatches() throws {
        let fixture = try GoldenFixture<ActivityInput, Double?>.load("activity-score")
        for c in fixture.cases {
            let i = ScoringInputs(
                steps: c.input.steps, activeCal: c.input.activeCal,
                stepsGoal: c.input.stepsGoal, activeCalGoal: c.input.activeCalGoal,
                contextMode: c.input.contextMode
            )
            expectClose(Score.activity(i), c.expected, "computeActivityScore — \(c.name)")
        }
    }

    struct WorkoutInput: Decodable {
        let workoutLogged, isRestDay: Bool
        let newPRsToday, sessionVolumeKg, trailingAvgVolumeKg: Double
        let contextMode: String?
        let isCurrentDay: Bool?
        let localHour: Double?
        let plannedExercises, loggedExercises, plannedSets, sessionSets, failureSets: Double?
    }

    @Test("workout score matches — pending, missed, and every drop-and-renormalise path")
    func workoutMatches() throws {
        let fixture = try GoldenFixture<WorkoutInput, Double?>.load("workout-score")
        for c in fixture.cases {
            let i = ScoringInputs(
                workoutLogged: c.input.workoutLogged, isRestDay: c.input.isRestDay,
                newPRsToday: c.input.newPRsToday, sessionVolumeKg: c.input.sessionVolumeKg,
                trailingAvgVolumeKg: c.input.trailingAvgVolumeKg,
                plannedExercises: c.input.plannedExercises, loggedExercises: c.input.loggedExercises,
                plannedSets: c.input.plannedSets, sessionSets: c.input.sessionSets,
                failureSets: c.input.failureSets,
                contextMode: c.input.contextMode,
                isCurrentDay: c.input.isCurrentDay, localHour: c.input.localHour
            )
            expectClose(Score.workout(i), c.expected, "computeWorkoutScore — \(c.name)")
        }
    }

    struct HydrationInput: Decodable { let waterMl, waterGoalMl: Double }

    @Test("hydration score matches")
    func hydrationMatches() throws {
        let fixture = try GoldenFixture<HydrationInput, Double?>.load("hydration-score")
        for c in fixture.cases {
            let i = ScoringInputs(waterMl: c.input.waterMl, waterGoalMl: c.input.waterGoalMl)
            expectClose(Score.hydration(i), c.expected, "computeHydrationScore — \(c.name)")
        }
    }

    struct MultiplierInput: Decodable {
        let sleepHours: Double
        let sleepGoalHours: Double?
        let contextMode: String?
    }

    @Test("the sleep-recovery multiplier matches on every anchor and beyond")
    func multiplierMatches() throws {
        let fixture = try GoldenFixture<MultiplierInput, Double>.load("sleep-recovery-multiplier")
        for c in fixture.cases {
            expectClose(
                Score.sleepRecoveryMultiplier(
                    sleepHours: c.input.sleepHours, sleepGoalHours: c.input.sleepGoalHours,
                    contextMode: c.input.contextMode
                ),
                c.expected,
                "sleepRecoveryMultiplier — \(c.name)"
            )
        }
    }

    struct RecoveryInput: Decodable {
        let sleepHours, deepMinutes, sleepGoalHours: Double
        let restingHR, baselineHR, hrvMs, hrvBaseline: Double?
        let contextMode: String?
    }

    @Test("recovery score matches — the 2026-08-04 night included")
    func recoveryMatches() throws {
        let fixture = try GoldenFixture<RecoveryInput, Double?>.load("recovery-score")
        #expect(fixture.cases.count > 1000)
        for c in fixture.cases {
            let i = ScoringInputs(
                sleepHours: c.input.sleepHours, deepMinutes: c.input.deepMinutes,
                sleepGoalHours: c.input.sleepGoalHours,
                restingHR: c.input.restingHR, baselineHR: c.input.baselineHR,
                hrvMs: c.input.hrvMs, hrvBaseline: c.input.hrvBaseline,
                contextMode: c.input.contextMode
            )
            expectClose(Score.recovery(i), c.expected, "computeRecoveryScore — \(c.name)")
        }
    }

    @Test("the composite matches, field by field, including the sleep gate")
    func dailyMatches() throws {
        let fixture = try GoldenFixture<ScoringInputs, ScoreComponents>.load("daily-score")
        #expect(fixture.cases.count > 100)
        for c in fixture.cases {
            let a = Score.daily(c.input)
            let e = c.expected
            expectClose(a.sleepScore, e.sleepScore, "sleepScore — \(c.name)")
            expectClose(a.nutritionScore, e.nutritionScore, "nutritionScore — \(c.name)")
            expectClose(a.activityScore, e.activityScore, "activityScore — \(c.name)")
            expectClose(a.workoutScore, e.workoutScore, "workoutScore — \(c.name)")
            expectClose(a.recoveryScore, e.recoveryScore, "recoveryScore — \(c.name)")
            expectClose(a.hydrationScore, e.hydrationScore, "hydrationScore — \(c.name)")
            expectClose(a.totalScore, e.totalScore, "totalScore — \(c.name)")
            #expect(a.awaitingSleep == e.awaitingSleep, "awaitingSleep — \(c.name)")
        }
    }

    struct AlertInput: Decodable {
        let sleepHours: Double
        let isRestDay: Bool
        let contextMode: String?
        let restingHR, baselineHR: Double?
        let proteinG, proteinGoalG, battery, hour: Double
    }

    @Test("the alerts match — order, severity and the exact sentence")
    func alertsMatch() throws {
        let fixture = try GoldenFixture<AlertInput, [ScoringAlert]>.load("alerts")
        #expect(fixture.cases.count > 500)
        for c in fixture.cases {
            let i = ScoringInputs(
                sleepHours: c.input.sleepHours, proteinG: c.input.proteinG,
                proteinGoalG: c.input.proteinGoalG, isRestDay: c.input.isRestDay,
                restingHR: c.input.restingHR, baselineHR: c.input.baselineHR,
                contextMode: c.input.contextMode
            )
            let actual = Score.alerts(i, battery: c.input.battery, hour: c.input.hour)
            #expect(actual == c.expected, "computeAlerts — \(c.name)")
        }
    }

    @Test("toFixed(1) decides a tie the ECMAScript way, not printf's")
    func toFixedTies() {
        #expect(jsToFixed1(5.25) == "5.3")
        #expect(jsToFixed1(4.05) == "4.0")
        #expect(jsToFixed1(5.45) == "5.5")
        #expect(jsToFixed1(3 + 14.0 / 60) == "3.2")
        #expect(jsToFixed1(0.95) == "0.9")
        #expect(jsToFixed1(9.96) == "10.0")
        #expect(jsToFixed1(2.5) == "2.5")
        #expect(jsToFixed1(-5.25) == "-5.3")
    }
}
