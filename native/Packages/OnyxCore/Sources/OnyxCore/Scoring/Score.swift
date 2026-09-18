import Foundation

/// `ScoreComponents` from the web app's `lib/scoring/types.ts`.
///
/// Every sub-score is 0–100 **or nil**. nil means "no data / not applicable"
/// and is excluded from the composite — never a fake 0 or 100. That rule is the
/// spine of the whole scorer, and `expectClose` in the test target fails loudly
/// on a nil that should be a number or a number that should be nil.
public struct ScoreComponents: Codable, Sendable, Equatable {
    public var sleepScore: Double?
    public var nutritionScore: Double?
    public var activityScore: Double?
    /// nil on rest days, on travel, and while today's session is still pending.
    public var workoutScore: Double?
    /// nil when there is no sleep AND no heart data.
    public var recoveryScore: Double?
    /// nil when there is no water goal, or nothing logged yet.
    public var hydrationScore: Double?
    /// nil only if every component is nil.
    public var totalScore: Double?
    /// The live day with no sleep synced yet — the UI shows "Awaiting Sleep
    /// Data" rather than a composite built only from nutrition and activity.
    public var awaitingSleep: Bool

    public init(
        sleepScore: Double?, nutritionScore: Double?, activityScore: Double?,
        workoutScore: Double?, recoveryScore: Double?, hydrationScore: Double?,
        totalScore: Double?, awaitingSleep: Bool
    ) {
        self.sleepScore = sleepScore
        self.nutritionScore = nutritionScore
        self.activityScore = activityScore
        self.workoutScore = workoutScore
        self.recoveryScore = recoveryScore
        self.hydrationScore = hydrationScore
        self.totalScore = totalScore
        self.awaitingSleep = awaitingSleep
    }
}

/// `ScoringAlert` from the web app's `lib/scoring/types.ts`.
public struct ScoringAlert: Codable, Sendable, Equatable {
    public enum Severity: String, Codable, Sendable {
        case warn, danger, info
    }

    public var severity: Severity
    public var message: String

    public init(severity: Severity, message: String) {
        self.severity = severity
        self.message = message
    }
}

/// The daily score — a direct port of the web app's `lib/scoring/score.ts`.
///
/// The reasoning behind each formula lives in the TypeScript and is not
/// duplicated here. What IS repeated is the one rule a port loses most easily:
///
/// > **Missing is nil, never zero.** A night with no sleep record is unknown,
/// > not a 0. A day with nothing logged is unknown, not a 0. The composite
/// > drops nil parts and renormalises the rest.
///
/// Three real incidents in this codebase turned on exactly that distinction —
/// the 2026-08-04 recovery of 81 on four hours' sleep, the July-15 total of 81
/// on 3h14, and the "1RM 0" that flattened a chart for months. The golden
/// vectors in `ScoreGoldenTests` replay all three.
public enum Score {
    // MARK: Context

    /// In an emergency the penalties are strongly relaxed; illness and travel
    /// moderately. Anything else — including an absent context — is 1.0.
    static func penaltyMult(_ context: String?) -> Double {
        switch context {
        case "emergency": return 0.35
        case "illness": return 0.55
        case "travel": return 0.70
        default: return 1.0
        }
    }

    @inline(__always)
    static func clamp100(_ v: Double) -> Double { clamp(v, 0, 100) }

    // MARK: Sleep

    /// Sleep v2 (W3): five terms, each 0–100, weighted and renormalised over
    /// the terms that have data.
    ///
    /// | term | weight | quality `q` (clamped 0…1) |
    /// |---|---|---|
    /// | duration | 40 | the v1 curve: full within 0.5 h of goal, quadratic below |
    /// | efficiency | 20 | `(asleep ÷ in-bed − 0.75) / 0.25` |
    /// | latency | 15 | `1 − onset / 90` |
    /// | fragmentation | 10 | `(1 − awake / 90) × (1 − awakenings / 6)` |
    /// | regularity | 15 | `1 − |Δ bedtime| / 120` |
    ///
    /// ── WHY THIS EXISTS ─────────────────────────────────────────────────────
    /// v1 read duration alone, so a night in bed at 00:16 that fell asleep at
    /// 03:05 and woke at 10:30 scored 100: seven and a half hours asleep, and
    /// nothing about the three hours it took. That night is the reference case
    /// in `sleep-score-v2.json` and lands in the fifties.
    ///
    /// ── MISSING IS NIL, NEVER ZERO — PER TERM ───────────────────────────────
    /// A nil term DROPS and the rest renormalise (the composite's own rule). A
    /// night with only a duration — every row written before W3, and every v1
    /// fixture — is the v1 number exactly, so the goldens that carry no v2
    /// field did not move. `awakenings` is the one input read beside another:
    /// a count nobody took multiplies by 1, because an unknown count is not a
    /// calm night and not a broken one.
    ///
    /// Context relaxes every term's PENALTY (`100 − q·100`), not just the
    /// duration's — an emergency that excuses a short night excuses a broken
    /// one. Stage bonuses (+5 deep ≥ 90, +5 REM ≥ 90) sit on top, then
    /// `clamp100`. `Battery`, the Recovery term and the < 6 h composite cap all
    /// still read `sleepHours` and are untouched.
    public static func sleep(_ i: ScoringInputs) -> Double? {
        if i.sleepHours <= 0 { return nil }
        // `!inputs.sleepGoalHours` — a zero goal short-circuits to full credit.
        if i.sleepGoalHours == 0 { return 100 }
        let pMult = penaltyMult(i.contextMode)
        func term(_ q: Double) -> Double { clamp100(100 - (1 - clamp(q, 0, 1)) * 100 * pMult) }

        let diff = i.sleepHours - i.sleepGoalHours
        let tol = 0.5
        let duration: Double
        if diff >= -tol {
            duration = 100
        } else {
            let deficit = -diff - tol
            duration = clamp100(100 - (deficit * deficit * 18 + deficit * 8) * pMult)
        }

        var parts: [(v: Double, w: Double)] = [(duration, 40)]
        if let inBed = i.sleepInBedHours, inBed > 0 {
            parts.append((term((i.sleepHours / inBed - 0.75) / 0.25), 20))
        }
        if let latency = i.sleepLatencyMin {
            parts.append((term(1 - latency / 90), 15))
        }
        if let awake = i.sleepAwakeMin {
            let count = i.sleepAwakenings ?? 0
            parts.append((term(clamp(1 - awake / 90, 0, 1) * clamp(1 - count / 6, 0, 1)), 10))
        }
        if let delta = i.sleepBedtimeDeltaMin {
            parts.append((term(1 - abs(delta) / 120), 15))
        }
        let wSum = parts.reduce(0) { $0 + $1.w }
        let base = parts.reduce(0) { $0 + $1.v * ($1.w / wSum) }

        let deepBonus: Double = i.deepMinutes >= 90 ? 5 : 0
        let remBonus: Double = i.remMinutes >= 90 ? 5 : 0
        return clamp100(base + deepBonus + remBonus)
    }

    // MARK: Nutrition

    /// Protein counted twice, calories asymmetric (over-eating ×1.5), carbs and
    /// fat once each — and only the macros that have a goal. On a declared
    /// exception day protein is the only thing graded. Nothing logged is nil.
    public static func nutrition(_ i: ScoringInputs) -> Double? {
        if i.calories <= 0 { return nil }
        let pMult = penaltyMult(i.contextMode)

        // A zero goal divides by zero here exactly as the TypeScript does: the
        // error is infinite, the clamp lands it on 0, and no NaN can arise
        // because `calories > 0` is already established for the one term that
        // has no `goal > 0` guard.
        func pctError(_ actual: Double, _ goal: Double, asymmetric: Bool = false) -> Double {
            let err = (actual - goal) / goal
            if asymmetric && err > 0 { return err * 1.5 * 100 }
            return abs(err) * 100
        }

        if i.nutritionException == true {
            if !(i.proteinGoalG > 0) { return nil }
            return clamp100(100 - pctError(i.proteinG, i.proteinGoalG) * pMult)
        }

        var errors: [Double] = [pctError(i.calories, i.calorieGoal, asymmetric: true)]
        if i.proteinGoalG > 0 {
            errors.append(pctError(i.proteinG, i.proteinGoalG))
            errors.append(pctError(i.proteinG, i.proteinGoalG))
        }
        if i.carbsGoalG > 0 { errors.append(pctError(i.carbsG, i.carbsGoalG)) }
        if i.fatGoalG > 0 { errors.append(pctError(i.fatG, i.fatGoalG)) }

        let meanError = errors.reduce(0, +) / Double(errors.count)
        return clamp100(100 - meanError * pMult)
    }

    // MARK: Activity

    /// Half steps vs goal, half active kcal vs goal, each capped at 100. Illness
    /// and emergency are nil (activity was not asked of you); travel is not.
    public static func activity(_ i: ScoringInputs) -> Double? {
        if i.contextMode == "illness" || i.contextMode == "emergency" { return nil }
        if i.steps <= 0 && i.activeCal <= 0 { return nil }
        func score(_ actual: Double, _ goal: Double) -> Double {
            if goal == 0 { return 100 }
            let ratio = actual / goal
            if ratio >= 1 { return Swift.min(100, 100 + (ratio - 1) * 20) }
            return clamp100(ratio * 100)
        }
        return clamp100(0.5 * score(i.steps, i.stepsGoal) + 0.5 * score(i.activeCal, i.activeCalGoal))
    }

    // MARK: Workout

    /// completion 55 · coverage 15 · volume 18 · effort 12, missing parts
    /// dropped and the rest renormalised; PRs are +5 each, capped at 10, on top.
    /// Rest day or travel is nil. Unlogged is nil while today is still pending
    /// (before 21:00), otherwise 0 — genuinely missed.
    public static func workout(_ i: ScoringInputs) -> Double? {
        if i.contextMode == "travel" { return nil }
        if i.isRestDay { return nil }
        if !i.workoutLogged {
            let pending = (i.isCurrentDay ?? false) && (i.localHour ?? 24) < 21
            return pending ? nil : 0
        }

        var parts: [(v: Double, w: Double)] = [(100, 55)]

        if let planned = i.plannedExercises, planned > 0, let logged = i.loggedExercises {
            let ratio = logged / planned
            parts.append((clamp100(Swift.min(1, ratio) * 100), 15))
        }

        if i.trailingAvgVolumeKg > 0 {
            let ratio = i.sessionVolumeKg / i.trailingAvgVolumeKg
            let v: Double
            if ratio >= 1 {
                v = 100
            } else if ratio >= 0.9 {
                v = 70 + (ratio - 0.9) * 300
            } else if ratio >= 0.75 {
                v = 35 + (ratio - 0.75) * (35 / 0.15)
            } else {
                v = clamp100((ratio / 0.75) * 35)
            }
            parts.append((clamp100(v), 18))
        }

        var effort: [Double] = []
        if let failure = i.failureSets {
            effort.append(clamp100(Swift.min(1, failure / 2) * 100))
        }
        if let planned = i.plannedSets, planned > 0, let done = i.sessionSets {
            effort.append(clamp100(Swift.min(1, done / planned) * 100))
        }
        if !effort.isEmpty {
            parts.append((effort.reduce(0, +) / Double(effort.count), 12))
        }

        let wSum = parts.reduce(0) { $0 + $1.w }
        let earned = parts.reduce(0) { $0 + $1.v * ($1.w / wSum) }
        let prBonus = clamp(i.newPRsToday * 5, 0, 10)
        return clamp100(earned + prBonus)
    }

    // MARK: Hydration

    /// Water vs goal, capped at 100. No goal, or nothing logged, is nil.
    public static func hydration(_ i: ScoringInputs) -> Double? {
        if i.waterGoalMl <= 0 { return nil }
        if i.waterMl <= 0 { return nil }
        return clamp100((i.waterMl / i.waterGoalMl) * 100)
    }

    // MARK: Sleep as a recovery multiplier

    /// (deficit hours below the threshold, multiplier). Piecewise-linear
    /// between anchors, flat at the floor beyond the last.
    static let sleepDeficitAnchors: [(Double, Double)] = [
        (0, 1.00), (1, 0.85), (2, 0.66), (3, 0.48), (4, 0.34), (5, 0.22), (7, 0.10),
    ]

    /// Sleep GATES recovery rather than contributing to it. The threshold is
    /// `goal − 1h`, bounded to 5…7h. No sleep data is 1.0 — unknown, not a
    /// penalty. Context relaxes the gate toward 1.
    public static func sleepRecoveryMultiplier(
        sleepHours: Double,
        sleepGoalHours: Double?,
        contextMode: String?
    ) -> Double {
        if sleepHours <= 0 { return 1 }

        // `sleepGoalHours || 8` — absent or zero reads as eight.
        let goal: Double = (sleepGoalHours ?? 0) == 0 ? 8 : sleepGoalHours!
        let threshold = Swift.min(7, Swift.max(5, goal - 1))
        let deficit = threshold - sleepHours
        if deficit <= 0 { return 1 }

        var mult = sleepDeficitAnchors[sleepDeficitAnchors.count - 1].1
        for idx in 1..<sleepDeficitAnchors.count {
            let (d0, m0) = sleepDeficitAnchors[idx - 1]
            let (d1, m1) = sleepDeficitAnchors[idx]
            if deficit <= d1 {
                mult = m0 + ((deficit - d0) / (d1 - d0)) * (m1 - m0)
                break
            }
        }

        let relax = penaltyMult(contextMode)
        return mult + (1 - relax) * (1 - mult)
    }

    // MARK: Recovery

    /// 45% sleep quality + 30% resting HR vs baseline + 25% HRV vs baseline, over
    /// the parts that have data, then × the sleep multiplier. No physiological
    /// signal at all is nil.
    public static func recovery(_ i: ScoringInputs) -> Double? {
        let pMult = penaltyMult(i.contextMode)
        var parts: [(v: Double, w: Double)] = []

        if i.sleepHours > 0 {
            let ratio = i.sleepGoalHours != 0 ? Swift.min(1, i.sleepHours / i.sleepGoalHours) : 1
            let deepQ = i.deepMinutes >= 75 ? 1 : Swift.max(0, i.deepMinutes / 75)
            parts.append((clamp100((0.8 * ratio + 0.2 * deepQ) * 100), 0.45))
        }
        if let resting = i.restingHR, let baseline = i.baselineHR, baseline > 0 {
            let delta = resting - baseline
            parts.append((clamp100(100 - Swift.max(0, delta) * 4 * pMult), 0.30))
        }
        if let hrv = i.hrvMs, let baseline = i.hrvBaseline, baseline > 0 {
            let ratio = hrv / baseline
            parts.append((clamp100(100 - Swift.max(0, 1 - ratio) * 150 * pMult), 0.25))
        }

        if parts.isEmpty { return nil }
        let wSum = parts.reduce(0) { $0 + $1.w }
        let base = parts.reduce(0) { $0 + $1.v * $1.w } / wSum
        let mult = sleepRecoveryMultiplier(
            sleepHours: i.sleepHours, sleepGoalHours: i.sleepGoalHours, contextMode: i.contextMode
        )
        return clamp100(base * mult)
    }

    // MARK: Composite

    /// The weighted mean over ONLY the components that have data, renormalised;
    /// then the sleep gate (a short night hard-caps the day, relaxed by
    /// context); then `Math.round` on everything.
    public static func daily(_ i: ScoringInputs) -> ScoreComponents {
        // Insertion order matters: the renormalised sum is accumulated in this
        // order on both sides, and floating-point addition is not associative.
        let comps: [(key: String, value: Double?, weight: Double)] = [
            ("sleep", sleep(i), 0.25),
            ("nutrition", nutrition(i), 0.30),
            ("activity", activity(i), 0.20),
            ("workout", workout(i), 0.15),
            ("recovery", recovery(i), 0.10),
            ("hydration", hydration(i), 0.08),
        ]

        let active = comps.filter { $0.value != nil }
        let wSum = active.reduce(0) { $0 + $1.weight }
        var totalScore: Double? = active.isEmpty
            ? nil
            : clamp100(active.reduce(0) { $0 + $1.value! * ($1.weight / wSum) })

        if let total = totalScore, i.sleepHours > 0, i.sleepHours < 6 {
            let s = i.sleepHours
            let rawCap: Double = s >= 5 ? 45 + (s - 5) * 25
                : s >= 3 ? 25 + (s - 3) * 10
                : (s / 3) * 25
            let relax = penaltyMult(i.contextMode)
            let cap = clamp100(rawCap + (1 - relax) * (100 - rawCap))
            totalScore = Swift.min(total, cap)
        }

        func r(_ v: Double?) -> Double? { v.map(jsRound) }
        let awaitingSleep = (i.isCurrentDay ?? false) && i.sleepHours <= 0
        return ScoreComponents(
            sleepScore: r(comps[0].value),
            nutritionScore: r(comps[1].value),
            activityScore: r(comps[2].value),
            workoutScore: r(comps[3].value),
            recoveryScore: r(comps[4].value),
            hydrationScore: r(comps[5].value),
            totalScore: r(totalScore),
            awaitingSleep: awaitingSleep
        )
    }

    // MARK: Alerts

    /// An ordered list; the caller shows the top two or three.
    ///
    /// `hour` is the local hour (0–23). The TypeScript defaults it to the wall
    /// clock; here it is required so the caller — and the golden vectors — say
    /// which hour they mean.
    public static func alerts(_ i: ScoringInputs, battery: Double, hour: Double) -> [ScoringAlert] {
        var alerts: [ScoringAlert] = []
        let ctx = i.contextMode ?? "normal"

        if ctx != "emergency" {
            if !i.isRestDay && i.sleepHours < 6 {
                alerts.append(.init(
                    severity: .danger,
                    message: "Recovery indicators are too low — do not train today."
                ))
            }
            if let resting = i.restingHR, let baseline = i.baselineHR, resting > baseline + 7 {
                alerts.append(.init(
                    severity: .warn,
                    message: "Elevated resting HR — likely under-recovered. Consider a lighter session."
                ))
            }
        }

        if battery < 20 {
            alerts.append(.init(
                severity: .danger,
                message: "Energy reserves low — prioritize recovery and nutrition."
            ))
        }

        if hour >= 18 && i.proteinG < i.proteinGoalG * 0.70 {
            let remaining = jsRound(i.proteinGoalG - i.proteinG)
            alerts.append(.init(
                severity: .warn,
                message: "Protein is behind — eat ~\(jsIntegerString(remaining))g more before bed."
            ))
        }

        if i.sleepHours > 0 && i.sleepHours < 5.5 && ctx != "emergency" {
            alerts.append(.init(
                severity: .warn,
                message: "Only \(jsToFixed1(i.sleepHours))h sleep logged — aim for an earlier night tonight."
            ))
        }

        return alerts
    }
}
