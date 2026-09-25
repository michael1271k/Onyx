import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The first set of numbers an account ever has.
//
// Onboarding asks for a bodyweight and a goal, and has to answer with four
// macros. Everything after this is the user's own — the Levers screen, the
// phase goals, a lever period — so this file's only job is to produce a
// defensible STARTING point that a person can recognise and then edit.
//
// ── WHY BODYWEIGHT MULTIPLIERS AND NOT MIFFLIN-ST JEOR ──────────────────────
// The usual BMR equations need sex, age and height. App Review guideline 5.1.1
// is explicit that an app may only REQUIRE personal data that is directly
// relevant to its core function, and it names sex and date of birth as commonly
// over-collected. Onyx does not need either to log a set, so onboarding does not
// ask, and an equation that cannot run without them is the wrong equation here.
//
// Kilocalories per kilogram of bodyweight is the coarser instrument and it is
// honest about being coarse: it lands within a few hundred kcal for most adults
// training three to five times a week, which is close enough for a first week,
// and week two is graded against the scale rather than against this number.
//
// ── THE FOUR NUMBERS ARE CONSISTENT BY CONSTRUCTION ─────────────────────────
// Protein and fat are set from bodyweight, carbohydrate takes the remainder,
// and then the kcal figure is RESTATED as the Atwater sum of the three rounded
// macros. The alternative — rounding each macro against a fixed kcal — leaves a
// gap of up to ~20 kcal, and the app already draws a warning when the macros do
// not add up (`SettingsModel.atwaterGap`). A seed that trips the app's own
// consistency check on day one is a seed that teaches the user to ignore it.
// ─────────────────────────────────────────────────────────────────────────────

/// What the athlete is trying to do, as onboarding asks it.
///
/// ── WHY THIS IS NOT A THIRD `ProgramPhase` ──────────────────────────────────
/// `ProgramPhase` is cut | bulk and is a TRAINING-VOLUME concept: it selects
/// the `plan_phase_volume` rows and each movement's `cutSets`. Maintenance is a
/// NUTRITION concept, and the app already models it that way — `active_lever` +
/// `maintenance_until` on `user_goals`, driven by `SettingsModel.setMaintenance`.
/// Adding a `.maintain` case to `ProgramPhase` would have meant a third set of
/// volume rows, a third column in every phase-keyed table and a rewrite of every
/// exhaustive switch, to express something the data model already says.
///
/// So maintaining trains on the cut's volume — hold what you have — and eats at
/// maintenance.
public enum StartingGoal: String, CaseIterable, Codable, Sendable {
    case cut
    case maintain
    case bulk

    public var label: String {
        switch self {
        case .cut:      "Lose fat"
        case .maintain: "Maintain"
        case .bulk:     "Build muscle"
        }
    }

    /// One line under the label. What the number will DO, not what it is.
    public var blurb: String {
        switch self {
        case .cut:      "Eat below maintenance. Train to keep the muscle you have."
        case .maintain: "Hold your weight. Train to keep what you have."
        case .bulk:     "Eat above maintenance. Train for the productive ceiling."
        }
    }

    /// The training phase this goal trains in. Maintaining holds at the cut's
    /// volume — see the type header.
    public var phase: ProgramPhase {
        self == .bulk ? .bulk : .cut
    }

    /// Kilocalories per kilogram of bodyweight per day, for someone lifting
    /// three to five times a week.
    var kcalPerKg: Double {
        switch self {
        case .cut:      27
        case .maintain: 33
        case .bulk:     37
        }
    }

    /// Grams of protein per kilogram. Highest on a cut, where protein is what
    /// defends lean mass in a deficit.
    var proteinPerKg: Double {
        switch self {
        case .cut:      2.2
        case .maintain: 2.0
        case .bulk:     1.8
        }
    }

    /// Grams of fat per kilogram. The floor is hormonal, not aesthetic, which
    /// is why even the cut does not go below roughly 0.8.
    var fatPerKg: Double {
        switch self {
        case .cut:      0.8
        case .maintain: 0.9
        case .bulk:     1.0
        }
    }
}

/// The four macros plus the two goals that ride with them.
public struct StartingTargets: Equatable, Sendable {
    public var kcal: Int
    public var proteinG: Int
    public var carbsG: Int
    public var fatG: Int
    /// Dietary fibre, from the kcal figure. Not a macro the app grades against
    /// a wall, but `plan_phase_goals` has the column and a blank one reads as
    /// "no opinion" forever.
    public var fiberG: Int
    public var stepsGoal: Int

    public init(kcal: Int, proteinG: Int, carbsG: Int, fatG: Int, fiberG: Int, stepsGoal: Int) {
        self.kcal = kcal; self.proteinG = proteinG; self.carbsG = carbsG
        self.fatG = fatG; self.fiberG = fiberG; self.stepsGoal = stepsGoal
    }

    /// Kilocalories the three macros actually account for. Equal to `kcal` for
    /// anything this file produces; the app's own gap warning reads the same
    /// arithmetic.
    public var atwaterKcal: Int {
        proteinG * 4 + carbsG * 4 + fatG * 9
    }
}

public enum StartingTargetsBuilder {

    /// Bodyweights this arithmetic is willing to answer for, in kilograms.
    ///
    /// Not a judgement about bodies — a guard against a typo. A mistyped `700`
    /// would seed a 23,000 kcal target and every screen in the app would grade
    /// against it until someone noticed.
    public static let weightRange: ClosedRange<Double> = 30...300

    /// Steps. One number for everyone, because the honest alternative is to ask
    /// for an activity level that nobody self-reports accurately.
    static let steps = 8_000

    /// Grams of fibre per 1,000 kcal — the FDA's reference intake, which is
    /// where the founder's own 30 g at 1,955 kcal came from.
    ///
    /// Public because the onboarding form does not ASK for fibre — four macro
    /// fields is already the most a first run should put on screen — so it has
    /// to re-derive the figure from whatever kcal the user ends up with, using
    /// this constant rather than a second copy of 14.
    public static let fiberPerThousandKcal: Double = 14

    /// The starting four for a bodyweight and a goal.
    ///
    /// `weightKg` outside `weightRange` is clamped rather than refused: the
    /// caller is an onboarding screen with a number field in it, and a clamp
    /// that produces a sane target the user can see and correct beats a nil
    /// that produces a blank screen.
    public static func build(weightKg: Double, goal: StartingGoal) -> StartingTargets {
        build(weightKg: weightKg, kcalPerKg: goal.kcalPerKg, proteinPerKg: goal.proteinPerKg, fatPerKg: goal.fatPerKg)
    }

    /// The starting four for a PROGRAM goal (Precision E3).
    ///
    /// The directional kinds are onboarding's own rows — muscle mass eats like
    /// a bulk, body fat like a cut. Recomp is the one new row: maintenance
    /// energy with the CUT's protein, because a recomp is a deficit's muscle
    /// defence at a surplus's scale — the protein is the whole mechanism.
    public static func build(weightKg: Double, programGoal goal: ProgramGoal) -> StartingTargets {
        switch goal {
        case .bulk, .muscleMass: build(weightKg: weightKg, goal: StartingGoal.bulk)
        case .cut, .bodyFat:     build(weightKg: weightKg, goal: StartingGoal.cut)
        case .recomp:
            build(
                weightKg: weightKg, kcalPerKg: StartingGoal.maintain.kcalPerKg,
                proteinPerKg: StartingGoal.cut.proteinPerKg, fatPerKg: StartingGoal.maintain.fatPerKg
            )
        }
    }

    private static func build(weightKg: Double, kcalPerKg: Double, proteinPerKg: Double, fatPerKg: Double) -> StartingTargets {
        let weight = min(max(weightKg, weightRange.lowerBound), weightRange.upperBound)

        let protein = (weight * proteinPerKg).rounded()
        let fat = (weight * fatPerKg).rounded()
        let budget = weight * kcalPerKg

        // Carbohydrate is the remainder, and the remainder can go negative for a
        // very light athlete on a cut once protein and fat are paid for. Zero
        // rather than negative, and the kcal figure below then honestly reports
        // the higher total that protein and fat alone already cost.
        let carbs = max(0, ((budget - protein * 4 - fat * 9) / 4).rounded())

        let kcal = Int(protein) * 4 + Int(carbs) * 4 + Int(fat) * 9
        let fiber = (Double(kcal) / 1000 * fiberPerThousandKcal).rounded()

        return StartingTargets(
            kcal: kcal,
            proteinG: Int(protein),
            carbsG: Int(carbs),
            fatG: Int(fat),
            fiberG: Int(fiber),
            stepsGoal: steps
        )
    }

    /// Where the scale should be heading, as a rate per week.
    ///
    /// Returned as a range because that is the shape `plan_phase_goals` stores
    /// (`rate_min_kg_wk` / `rate_max_kg_wk`) and because a single number invites
    /// a person to read a bad week as a failure. Percentages of bodyweight, not
    /// absolutes: 0.5 kg a week is a gentle cut at 100 kg and a brutal one at 50.
    public static func weeklyRate(weightKg: Double, goal: StartingGoal) -> (min: Double, max: Double) {
        let weight = min(max(weightKg, weightRange.lowerBound), weightRange.upperBound)
        func pct(_ value: Double) -> Double { ((weight * value / 100) * 100).rounded() / 100 }
        switch goal {
        case .cut:      return (min: -pct(0.7), max: -pct(0.4))
        case .maintain: return (min: 0, max: 0)
        case .bulk:     return (min: pct(0.2), max: pct(0.4))
        }
    }

    /// The safe band for a PROGRAM goal. Directional kinds take their
    /// direction's band. Recomp is ±0.1 % of bodyweight a week — not a
    /// direction but the scale's own weekly noise: `maintain`'s 0…0 would
    /// call a 50 g drift a failure.
    public static func weeklyRate(weightKg: Double, programGoal goal: ProgramGoal) -> (min: Double, max: Double) {
        switch goal {
        case .bulk, .muscleMass: return weeklyRate(weightKg: weightKg, goal: StartingGoal.bulk)
        case .cut, .bodyFat:     return weeklyRate(weightKg: weightKg, goal: StartingGoal.cut)
        case .recomp:
            let weight = min(max(weightKg, weightRange.lowerBound), weightRange.upperBound)
            let band = ((weight * 0.1 / 100) * 100).rounded() / 100
            return (min: -band, max: band)
        }
    }
}

// MARK: - Pace (Precision E3)

/// The readings a goal is set FROM — the latest weigh-in, prefilled and
/// editable. No sex, no age (the App Review note at the top of this file).
public struct BodyNow: Equatable, Sendable {
    public var weightKg: Double?
    public var bodyFatPct: Double?
    public var muscleMassKg: Double?

    public init(weightKg: Double?, bodyFatPct: Double? = nil, muscleMassKg: Double? = nil) {
        self.weightKg = weightKg; self.bodyFatPct = bodyFatPct; self.muscleMassKg = muscleMassKg
    }
}

/// What a target and a horizon imply, judged against the goal's safe band.
public struct GoalPlan: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        /// Within the band.
        case inside
        /// Past the band's far end — a cut that strips muscle, a bulk that is
        /// mostly fat, a recomp that is really a bulk or a cut.
        case fast
        /// Short of the band, or the wrong way — slower than the goal can show.
        case slow
    }

    /// The scale's destination, two decimals.
    public var targetWeightKg: Double
    /// Signed kg a week, two decimals — the figure drawn and the one judged.
    public var weeklyRateKg: Double
    public var bandMin: Double
    public var bandMax: Double
    public var verdict: Verdict
}

public enum GoalPace {

    /// The destination weight, the implied weekly rate and its verdict — or
    /// nil when there is nothing to start from, nothing to convert, or no
    /// horizon to divide by. Nothing implied is nothing drawn.
    ///
    /// ── WHY EVERY KIND LANDS ON A WEIGHT ────────────────────────────────────
    /// The safe band is a rate of SCALE weight, so each target is converted to
    /// one. Body fat holds lean mass constant: lean = w·(1 − bf), and the
    /// target weight is lean / (1 − target bf). Muscle mass adds the muscle to
    /// everything else held still — a LOWER bound on the scale's move, since a
    /// lean bulk carries some fat and water with it; the sheet says so.
    public static func plan(goal: ProgramGoal, now: BodyNow, target: ProgramGoalTarget) -> GoalPlan? {
        // Outside `weightRange` is a typo, not a body: `weeklyRate` would clamp
        // it to the range and the rate would be graded on a second weight.
        guard let weight = now.weightKg, StartingTargetsBuilder.weightRange.contains(weight),
              let weeks = target.horizonWeeks, weeks > 0 else { return nil }
        let destination: Double
        switch goal {
        case .bulk, .cut, .recomp:
            guard let t = target.targetWeightKg, t > 0 else { return nil }
            destination = t
        case .bodyFat:
            guard let bf = now.bodyFatPct, let tbf = target.targetBodyFatPct,
                  (0..<100).contains(bf), (0..<100).contains(tbf) else { return nil }
            destination = weight * (1 - bf / 100) / (1 - tbf / 100)
        case .muscleMass:
            guard let mm = now.muscleMassKg, let tmm = target.targetMuscleMassKg else { return nil }
            destination = weight + (tmm - mm)
        }
        let rate = round2((destination - weight) / Double(weeks))
        let band = StartingTargetsBuilder.weeklyRate(weightKg: weight, programGoal: goal)
        let verdict: GoalPlan.Verdict
        if rate < band.min {
            verdict = band.min < 0 ? .fast : .slow
        } else if rate > band.max {
            verdict = band.max > 0 ? .fast : .slow
        } else {
            verdict = .inside
        }
        return GoalPlan(
            targetWeightKg: round2(destination), weeklyRateKg: rate,
            bandMin: band.min, bandMax: band.max, verdict: verdict
        )
    }

    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
