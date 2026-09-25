import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Which plan you are running, in which direction, and what that direction is
// aiming at — the TYPES. The values are rows.
//
// ── WHAT LEFT THIS FILE IN W2 (2026-09-10) ───────────────────────────────────
// `Programs.all` (the three `PlanInfo`s), `Programs.goals` / `PhaseGoals.cut`
// / `.bulk` (the macro presets), `Programs.weeklySetTargets` (the per-muscle
// set targets) were the founder's numbers compiled into the package. They are
// `plans`, `plan_phase_goals` and `plan_phase_volume` rows now, seeded once by
// `w2-seed-founder.sql (git history)`, and every reader takes the rows. What stays
// here is the shape of a plan entry, the phase enum, the `PhaseGoals` value
// the rows decode into, and the one piece of id hygiene that is not data: the
// alias table for ids this app itself once wrote.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - The plan catalogue

/// One selectable plan, WITHOUT its deck — a `plans` row.
public struct PlanInfo: Identifiable, Codable, Equatable, Sendable {
    /// `plans.program_id`. The key every other plan table joins on.
    public let id: String
    public let label: String
    /// The one-line description under the plan's name in the picker.
    public let blurb: String
    /// A historical plan — still selectable so old sessions render correctly,
    /// but sorted below the live ones.
    public let isLegacy: Bool
    /// `plans.started_on` — the first day this plan owned. `Schedule` uses it
    /// to decide which plan a DATE belongs to; nil is a plan never started.
    public let startedOn: String?
    /// Picker order, lower first.
    public let sort: Int
    /// `plans.goal_kind`, as stored. A STRING and not a `ProgramGoal`: this
    /// value rides in the watch's `ScheduleContext`, and one row holding a
    /// kind this build does not know must read as "no goal", never fail the
    /// whole context's decode. `goal` is the typed reading.
    public let goalKind: String?
    /// `plans.goal_target` — where the goal is heading.
    public let goalTarget: ProgramGoalTarget?

    public init(
        id: String, label: String, blurb: String, isLegacy: Bool = false, startedOn: String? = nil, sort: Int = 0,
        goalKind: String? = nil, goalTarget: ProgramGoalTarget? = nil
    ) {
        self.id = id
        self.label = label
        self.blurb = blurb
        self.isLegacy = isLegacy
        self.startedOn = startedOn
        self.sort = sort
        self.goalKind = goalKind
        self.goalTarget = goalTarget
    }

    /// The program's goal, or nil — none set, or a kind this build does not know.
    public var goal: ProgramGoal? { goalKind.flatMap(ProgramGoal.init(rawValue:)) }
}

// MARK: - A program's goal (Precision E3)

/// What a program is FOR — `plans.goal_kind`. Five kinds, where onboarding's
/// `StartingGoal` has three: the two extra are the same two directions steered
/// by a different reading of the scale (muscle mass, body-fat percentage)
/// rather than by weight.
///
/// The raw values are the WIRE FORMAT the CHECK constraint in
/// `docs/sql/precision-e-programs.sql` names. Add, never rename.
public enum ProgramGoal: String, CaseIterable, Codable, Sendable {
    case bulk
    case cut
    case recomp
    case muscleMass = "muscle_mass"
    case bodyFat = "body_fat"

    public var label: String {
        switch self {
        case .bulk:       "Bulk"
        case .cut:        "Cut"
        case .recomp:     "Recomp"
        case .muscleMass: "Muscle mass"
        case .bodyFat:    "Body fat %"
        }
    }

    /// One line under the label: what the choice DOES, not what it is.
    public var blurb: String {
        switch self {
        case .bulk:       "Eat above maintenance and gain slowly. Train for the most productive volume."
        case .cut:        "Eat below maintenance to lose fat. Train to keep the muscle you have."
        case .recomp:     "Eat at maintenance with high protein. Lose fat and build muscle at a steady weight."
        case .muscleMass: "Add muscle to a figure your scale measures. A lean bulk aimed at muscle, not weight."
        case .bodyFat:    "Reach a body-fat percentage your scale measures. A cut steered by fat, not weight."
        }
    }

    /// The training phase it runs in — which `plan_phase_goals` and
    /// `plan_phase_volume` rows it reads. Recomp holds the scale still, which
    /// trains on the cut's volume: the rule `StartingGoal.maintain` states.
    public var phase: ProgramPhase {
        switch self {
        case .bulk, .muscleMass: .bulk
        case .cut, .bodyFat, .recomp: .cut
        }
    }

    /// The bundled template this goal suits (`plan-templates.json` ids):
    /// the five-day hybrid for building, the four-day split for cutting, the
    /// push/pull/legs rotation for a recomp's steady middle.
    public var recommendedTemplateId: String {
        switch self {
        case .bulk, .muscleMass: "onyx5"
        case .cut, .bodyFat:     "onyx4"
        case .recomp:            "ppl"
        }
    }
}

/// `plans.goal_target` — where the goal is heading and by when. Every key is
/// optional: which target matters follows the kind (a weight for bulk, cut
/// and recomp; a percentage for body fat; kilograms of muscle for muscle
/// mass), and the rest stay out of the object rather than arriving as zeros.
public struct ProgramGoalTarget: Codable, Equatable, Sendable {
    public var targetWeightKg: Double?
    public var targetBodyFatPct: Double?
    public var targetMuscleMassKg: Double?
    /// The implied rate when the goal was set, signed — the number the
    /// sheet showed, kept so a later reader need not re-derive it.
    public var weeklyRateKg: Double?
    public var horizonWeeks: Int?
    /// The weight the goal was set from — the other end of the rate.
    public var startWeightKg: Double?

    public init(
        targetWeightKg: Double? = nil, targetBodyFatPct: Double? = nil, targetMuscleMassKg: Double? = nil,
        weeklyRateKg: Double? = nil, horizonWeeks: Int? = nil, startWeightKg: Double? = nil
    ) {
        self.targetWeightKg = targetWeightKg; self.targetBodyFatPct = targetBodyFatPct
        self.targetMuscleMassKg = targetMuscleMassKg; self.weeklyRateKg = weeklyRateKg
        self.horizonWeeks = horizonWeeks; self.startWeightKg = startWeightKg
    }

    enum CodingKeys: String, CodingKey {
        case targetWeightKg = "target_weight_kg"
        case targetBodyFatPct = "target_body_fat_pct"
        case targetMuscleMassKg = "target_muscle_mass_kg"
        case weeklyRateKg = "weekly_rate_kg"
        case horizonWeeks = "horizon_weeks"
        case startWeightKg = "start_weight_kg"
    }

    public static func decode(_ json: String) -> ProgramGoalTarget? {
        try? JSONDecoder().decode(ProgramGoalTarget.self, from: Data(json.utf8))
    }

    public func encoded() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return String(decoding: (try? enc.encode(self)) ?? Data("{}".utf8), as: UTF8.self)
    }
}

public enum Programs {

    /// `planList()` — live plans first, legacy last, each group in `sort`
    /// order. A stable partition rather than one `sorted(by:)`, because
    /// Swift's sort is not stable and two plans with equal keys must keep the
    /// order the rows gave them.
    public static func pickerOrder(_ plans: [PlanInfo]) -> [PlanInfo] {
        let live = plans.filter { !$0.isLegacy }.sorted { $0.sort < $1.sort }
        let legacy = plans.filter(\.isLegacy).sorted { $0.sort < $1.sort }
        return live + legacy
    }

    /// Ids that no longer name a plan, and the plan that absorbed them.
    ///
    /// Onyx-4 used to ship as two plans, "Builder" and "Defender"; the 2026-09-05
    /// rename moved `apex51` / `axis4` / `axis5_hybrid`. A device that last
    /// synced before either still holds the old string, and a stale id must
    /// never dead-end a picker. This is id hygiene for strings THIS app wrote,
    /// not founder data, which is why it survives W2.
    private static let legacyPlanId: [String: String] = [
        "onyx4_builder": "onyx4",
        "onyx4_defender": "onyx4",
        "axis4_builder": "onyx4",
        "axis4_defender": "onyx4",
        "apex51": "onyx5",
        "axis4": "onyx4",
        "axis5_hybrid": "onyx5",
    ]

    /// The stored id with any alias resolved, or nil for an empty value. Says
    /// nothing about whether a plan of that id EXISTS — `resolvePlanId` does.
    public static func normalizePlanId(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return legacyPlanId[raw] ?? raw
    }

    /// The plan the stored selection names, when the catalogue has it.
    ///
    /// ── THE FALLBACK IS THE CATALOGUE'S, NOT A CONSTANT ─────────────────────
    /// `defaultPlanId = "onyx5"` used to stand in for a missing or unknown
    /// selection. With decks as rows, a selection the rows do not know falls
    /// to the plan marked active on the server, then to the first plan in
    /// picker order, and — for an account with no plans at all — to the
    /// stored string itself, so an empty catalogue resolves to an empty deck
    /// under the right name rather than to someone else's.
    public static func resolvePlanId(stored raw: String?, in plans: [PlanInfo], activeFallback: String? = nil) -> String {
        let known = Set(plans.map(\.id))
        if let id = normalizePlanId(raw), known.contains(id) { return id }
        if let active = activeFallback.flatMap(normalizePlanId), known.contains(active) { return active }
        if let first = pickerOrder(plans).first { return first.id }
        return normalizePlanId(raw) ?? ""
    }
}

// MARK: - Reading a stored phase

public extension ProgramPhase {

    /// Narrow a stored phase string — from `user_goals.active_phase`,
    /// `goal_preset`, or a mirrored preference — to one of the two directions.
    ///
    /// `maintenance` was deleted as a phase on 2026-08-30 — a week at
    /// maintenance calories is a nutrition LEVER applied on top of whichever
    /// direction the block is running, not a third direction. Rows written
    /// before that still hold the string; it resolves to the cut, which is the
    /// block it was always taken inside of.
    static func stored(_ raw: String?) -> ProgramPhase {
        raw == "bulk" ? .bulk : .cut
    }
}

// MARK: - Phase goals

/// What a phase is steering toward — a `plan_phase_goals` row, as a value.
///
/// Every field is a STARTING value that Settings seeds into `user_goals` and
/// the user then tunes. The optionals are optional because they genuinely do
/// not apply: a cut has no body-fat CEILING (it is walking away from one), and
/// a phase graded on calories alone has no macro target. `nil` here is "this
/// phase does not have that goal", and it must never arrive as `0`.
public struct PhaseGoals: Codable, Equatable, Sendable {
    public var phase: ProgramPhase
    public var label: String
    public var calorieGoal: Double
    public var proteinGoalG: Double?
    public var carbsGoalG: Double?
    public var fatGoalG: Double?
    public var fiberGoalG: Double?
    /// The band `fiberGoalG` sits inside.
    public var fiberMin: Double?
    public var fiberMax: Double?
    /// A cut leans on NEAT harder than a bulk does, so this moves with the phase.
    public var stepsGoal: Double
    public var targetWeightKg: Double?
    public var targetBodyFatPct: Double?
    public var targetMuscleMassKg: Double?
    /// Signed: negative on a cut, positive on a bulk.
    public var rateMinKgWk: Double?
    public var rateMaxKgWk: Double?
    /// Bulk only — the body-fat percentage at which the bulk ends.
    public var bodyFatCeilingPct: Double?

    public init(
        phase: ProgramPhase, label: String, calorieGoal: Double,
        proteinGoalG: Double? = nil, carbsGoalG: Double? = nil, fatGoalG: Double? = nil, fiberGoalG: Double? = nil,
        fiberMin: Double? = nil, fiberMax: Double? = nil, stepsGoal: Double,
        targetWeightKg: Double? = nil, targetBodyFatPct: Double? = nil, targetMuscleMassKg: Double? = nil,
        rateMinKgWk: Double? = nil, rateMaxKgWk: Double? = nil, bodyFatCeilingPct: Double? = nil
    ) {
        self.phase = phase; self.label = label; self.calorieGoal = calorieGoal
        self.proteinGoalG = proteinGoalG; self.carbsGoalG = carbsGoalG; self.fatGoalG = fatGoalG; self.fiberGoalG = fiberGoalG
        self.fiberMin = fiberMin; self.fiberMax = fiberMax; self.stepsGoal = stepsGoal
        self.targetWeightKg = targetWeightKg; self.targetBodyFatPct = targetBodyFatPct; self.targetMuscleMassKg = targetMuscleMassKg
        self.rateMinKgWk = rateMinKgWk; self.rateMaxKgWk = rateMaxKgWk; self.bodyFatCeilingPct = bodyFatCeilingPct
    }

    /// What a plan with no goals row shows: nothing to aim at, a label that
    /// says which direction, and zero calories — which every reader already
    /// treats as "unset" rather than as a fast.
    public static func empty(_ phase: ProgramPhase) -> PhaseGoals {
        PhaseGoals(phase: phase, label: phase.label, calorieGoal: 0, stepsGoal: 0)
    }
}
