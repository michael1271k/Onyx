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

    public init(id: String, label: String, blurb: String, isLegacy: Bool = false, startedOn: String? = nil, sort: Int = 0) {
        self.id = id
        self.label = label
        self.blurb = blurb
        self.isLegacy = isLegacy
        self.startedOn = startedOn
        self.sort = sort
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
