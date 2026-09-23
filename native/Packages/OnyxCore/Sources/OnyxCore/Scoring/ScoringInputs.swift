import Foundation

/// A day's raw signals, exactly as `ScoringInputs` in the web app's `lib/scoring/types.ts`.
///
/// ── EVERY OPTIONAL IS OPTIONAL FOR A REASON ─────────────────────────────────
/// The TypeScript original distinguishes "absent" from "zero" in several places
/// and the distinction is load-bearing: `sessionRpe` absent means *the session
/// happened and was not rated* (74 Notion-era sessions), which falls back to
/// `Battery.defaults.defaultRpe`, whereas `sessionRpe == 0` would mean an
/// effortless session. Modelling either as a plain `Double` collapses two
/// different facts into one number, so they stay `Double?` here.
///
/// Decoding mirrors the JSON the golden-vector exporter emits, which is the
/// TypeScript object shape verbatim.
public struct ScoringInputs: Codable, Sendable, Equatable {
    // MARK: Sleep
    public var sleepHours: Double
    public var deepMinutes: Double
    public var remMinutes: Double
    public var sleepGoalHours: Double

    // MARK: Nutrition
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var calorieGoal: Double
    public var proteinGoalG: Double
    public var carbsGoalG: Double
    public var fatGoalG: Double
    public var nutritionException: Bool?

    // MARK: Activity
    public var steps: Double
    public var activeCal: Double
    public var stepsGoal: Double
    public var activeCalGoal: Double

    // MARK: Workout
    public var workoutLogged: Bool
    public var isRestDay: Bool
    public var newPRsToday: Double
    public var sessionVolumeKg: Double
    /// Average volume of recent sessions **of the same programme day**. Zero when
    /// there is no baseline yet, which `workoutDrain` reads as "assume typical".
    public var trailingAvgVolumeKg: Double
    /// CR-10 the session was logged with. `nil` ≠ `0` — see the type note above.
    public var sessionRpe: Double?
    public var splitDay: String?
    /// The programme day (`cb_a` | `legs_a` | `arms` | `cb_b` | `legs_b`).
    /// Distinct from `splitDay`, which is coarser and drains nothing.
    public var sessionDayKey: String?
    /// Inside a planned maintenance / deload week. Lowers the workout drain
    /// ceiling and the relative floor, and nothing else.
    public var isMaintenance: Bool?

    public var plannedExercises: Double?
    public var loggedExercises: Double?
    public var plannedSets: Double?
    public var sessionSets: Double?
    public var failureSets: Double?

    // MARK: Recovery
    public var waterMl: Double
    public var waterGoalMl: Double

    // MARK: Heart
    public var restingHR: Double?
    public var baselineHR: Double?
    public var hrvMs: Double?
    public var hrvBaseline: Double?

    // MARK: Readiness v9
    // The scalars `Readiness.signals` resolved from 49 days of history BEFORE
    // this object was built, so the battery stays a pure function of one day.
    // `nil` means "not enough history" and every reader degrades to neutral.
    /// 7-day rolling ln-HRV against the 42-day baseline, in SDs, ±2. Positive is good.
    public var hrvZ: Double?
    /// The same for resting HR. Positive is BAD.
    public var rhrZ: Double?
    /// EWMA acute (7 d) over chronic (28 d) sRPE load.
    public var acwr: Double?
    /// This week's Foster strain against the rolling strains before it, ±2.
    public var strainZ: Double?
    /// Mean severity of the day's `doms_logs` rows, 0 ... 3. Nil when none.
    public var domsSeverity: Double?

    /// `daily_logs.sleep_onset_trouble`. Battery v9 reads it as a wellness
    /// item; `nil` means the question was never asked.
    public var sleepOnsetTrouble: Bool?
    /// The LATEST fatigue slot logged today, 1 (Fresh) ... 5 (Empty). Battery
    /// v9's wellness drain reads it; the day score still does not.
    public var fatigueLevel: Double?

    // MARK: Context
    public var contextMode: String?
    public var hoursAwake: Double?
    public var isCurrentDay: Bool?
    public var localHour: Double?

    // MARK: Sleep v2 (W3) — optional-and-last
    // Each is a term of `Score.sleep`; `nil` drops the term and the rest
    // renormalise. A legacy row (or fixture) that carries none of them scores
    // on duration alone, which is exactly the v1 number.
    /// `end_time − start_time` — the bed window. Efficiency's denominator.
    public var sleepInBedHours: Double?
    /// `onset_time − start_time`. Zero credit at 90 min.
    public var sleepLatencyMin: Double?
    /// Awake minutes AFTER falling asleep — `awake_min` less the latency.
    public var sleepAwakeMin: Double?
    /// Merged awake intervals ≥ 5 min after onset. Read only beside
    /// `sleepAwakeMin`; nil beside a number multiplies by 1.
    public var sleepAwakenings: Double?
    /// Tonight's bedtime minus the median of the last 14 nights, in minutes.
    /// nil under five nights of history.
    public var sleepBedtimeDeltaMin: Double?

    // MARK: Wrist coverage (App Store W6) — optional-and-last
    /// Minutes of the night window the watch was off the wrist — a raw fact,
    /// derived on the phone from gaps in the heart-rate series. Every decision
    /// made from it is `WristCoverage`'s. Nil (every golden vector, every day
    /// before W6, a phone with no watch) is the v9 arithmetic, unchanged.
    public var offWristMin: Double?

    public init(
        sleepHours: Double = 0,
        deepMinutes: Double = 0,
        remMinutes: Double = 0,
        sleepGoalHours: Double = 8,
        calories: Double = 0,
        proteinG: Double = 0,
        carbsG: Double = 0,
        fatG: Double = 0,
        calorieGoal: Double = 0,
        proteinGoalG: Double = 0,
        carbsGoalG: Double = 0,
        fatGoalG: Double = 0,
        nutritionException: Bool? = nil,
        steps: Double = 0,
        activeCal: Double = 0,
        stepsGoal: Double = 10_000,
        activeCalGoal: Double = 500,
        workoutLogged: Bool = false,
        isRestDay: Bool = false,
        newPRsToday: Double = 0,
        sessionVolumeKg: Double = 0,
        trailingAvgVolumeKg: Double = 0,
        sessionRpe: Double? = nil,
        splitDay: String? = nil,
        sessionDayKey: String? = nil,
        isMaintenance: Bool? = nil,
        plannedExercises: Double? = nil,
        loggedExercises: Double? = nil,
        plannedSets: Double? = nil,
        sessionSets: Double? = nil,
        failureSets: Double? = nil,
        waterMl: Double = 0,
        waterGoalMl: Double = 3000,
        restingHR: Double? = nil,
        baselineHR: Double? = nil,
        hrvMs: Double? = nil,
        hrvBaseline: Double? = nil,
        hrvZ: Double? = nil,
        rhrZ: Double? = nil,
        acwr: Double? = nil,
        strainZ: Double? = nil,
        domsSeverity: Double? = nil,
        sleepOnsetTrouble: Bool? = nil,
        fatigueLevel: Double? = nil,
        contextMode: String? = nil,
        hoursAwake: Double? = nil,
        isCurrentDay: Bool? = nil,
        localHour: Double? = nil,
        sleepInBedHours: Double? = nil,
        sleepLatencyMin: Double? = nil,
        sleepAwakeMin: Double? = nil,
        sleepAwakenings: Double? = nil,
        sleepBedtimeDeltaMin: Double? = nil,
        offWristMin: Double? = nil
    ) {
        self.sleepHours = sleepHours
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.sleepGoalHours = sleepGoalHours
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.calorieGoal = calorieGoal
        self.proteinGoalG = proteinGoalG
        self.carbsGoalG = carbsGoalG
        self.fatGoalG = fatGoalG
        self.nutritionException = nutritionException
        self.steps = steps
        self.activeCal = activeCal
        self.stepsGoal = stepsGoal
        self.activeCalGoal = activeCalGoal
        self.workoutLogged = workoutLogged
        self.isRestDay = isRestDay
        self.newPRsToday = newPRsToday
        self.sessionVolumeKg = sessionVolumeKg
        self.trailingAvgVolumeKg = trailingAvgVolumeKg
        self.sessionRpe = sessionRpe
        self.splitDay = splitDay
        self.sessionDayKey = sessionDayKey
        self.isMaintenance = isMaintenance
        self.plannedExercises = plannedExercises
        self.loggedExercises = loggedExercises
        self.plannedSets = plannedSets
        self.sessionSets = sessionSets
        self.failureSets = failureSets
        self.waterMl = waterMl
        self.waterGoalMl = waterGoalMl
        self.restingHR = restingHR
        self.baselineHR = baselineHR
        self.hrvMs = hrvMs
        self.hrvBaseline = hrvBaseline
        self.hrvZ = hrvZ
        self.rhrZ = rhrZ
        self.acwr = acwr
        self.strainZ = strainZ
        self.domsSeverity = domsSeverity
        self.sleepOnsetTrouble = sleepOnsetTrouble
        self.fatigueLevel = fatigueLevel
        self.contextMode = contextMode
        self.hoursAwake = hoursAwake
        self.isCurrentDay = isCurrentDay
        self.localHour = localHour
        self.sleepInBedHours = sleepInBedHours
        self.sleepLatencyMin = sleepLatencyMin
        self.sleepAwakeMin = sleepAwakeMin
        self.sleepAwakenings = sleepAwakenings
        self.sleepBedtimeDeltaMin = sleepBedtimeDeltaMin
        self.offWristMin = offWristMin
    }
}

/// `ReadinessResult` from the web app's `lib/scoring/types.ts`.
public struct ReadinessResult: Codable, Sendable, Equatable {
    public enum Level: String, Codable, Sendable {
        case trainHard = "train_hard"
        case trainLight = "train_light"
        case rest
    }

    public var level: Level
    public var label: String
    /// An Onyx palette hex. Carried as a string because the fixture compares it
    /// literally — a colour that drifts between platforms is a real defect, and
    /// parsing it into a colour type here would hide exactly that.
    public var color: String
    public var reason: String

    public init(level: Level, label: String, color: String, reason: String) {
        self.level = level
        self.label = label
        self.color = color
        self.reason = reason
    }
}

/// Clamp, matching the TypeScript `clamp` helper's argument order.
@inlinable
func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    Swift.max(lo, Swift.min(hi, v))
}
