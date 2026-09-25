import Foundation
import Observation
import OnyxCore
import OnyxData

/// The three answers the goal sheet collects, and the one write at the end
/// (Precision E3).
///
/// ── NOTHING IS WRITTEN UNTIL SAVE ───────────────────────────────────────────
/// Onboarding's rule (`OnboardingModel`): three screens of state live here and
/// nowhere else until the last tap, so a sheet swiped away half-answered
/// leaves the program exactly as it was.
///
/// ── THE ARITHMETIC IS ONYXCORE'S ────────────────────────────────────────────
/// Macros: `StartingTargetsBuilder.build(weightKg:programGoal:)` — 27/33/37
/// kcal/kg, recomp at maintenance with the cut's protein. Pace:
/// `GoalPace.plan` against `weeklyRate(weightKg:programGoal:)`. No sex, no
/// age (App Review 5.1.1 — `StartingTargets`' header).
@MainActor
@Observable
final class GoalSetupModel: Identifiable {

    enum Step: Int, CaseIterable { case goal, now, targets }

    private let database: AppDatabase
    private let userId: String
    let programId: String
    let programLabel: String
    /// Saving also RUNS the goal when this is the program in force.
    let running: Bool
    let hasDays: Bool

    var step: Step = .goal

    // ── Step 1 ──────────────────────────────────────────────────────────────
    var goal: ProgramGoal {
        didSet {
            guard oldValue != goal else { return }
            // Each kind aims at a different reading — a new kind starts its
            // target over rather than carrying a weight into a percentage.
            if !targetTouched { proposeTarget() }
            if !targetsTouched { recomputeTargets() }
        }
    }

    // ── Step 2 ──────────────────────────────────────────────────────────────
    var weightKg: Double? { didSet { if weightKg != oldValue { weightChanged() } } }
    var bodyFatPct: Double?
    var muscleMassKg: Double?
    var bmr: Double?
    /// The weigh-in the four fields were read from, for the caption.
    private(set) var readingDate: String?

    var targetWeightKg: Double?
    var targetBodyFatPct: Double?
    var targetMuscleMassKg: Double?
    /// Moving the horizon re-proposes an untouched target, so the pace stays
    /// the band's middle rather than drifting out of it week by week.
    var horizonWeeks = 12 { didSet { if horizonWeeks != oldValue, !targetTouched { proposeTarget() } } }
    private(set) var targetTouched = false

    // ── Step 3 ──────────────────────────────────────────────────────────────
    var kcal: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    private(set) var targetsTouched = false
    /// The recommended template, accepted.
    var acceptTemplate = false

    var isSaving = false
    var failure: String?

    static let horizonRange = 2...104

    init(
        database: AppDatabase, userId: String, programId: String, programLabel: String,
        running: Bool, hasDays: Bool, current: PlanInfo?, today: String = LogicalDay.today()
    ) {
        self.database = database
        self.userId = userId
        self.programId = programId
        self.programLabel = programLabel
        self.running = running
        self.hasDays = hasDays
        self.goal = current?.goal ?? .cut

        // The latest weigh-in, TODAY INCLUDED — `latestBodyReading` is
        // strictly before its date, so it is asked about tomorrow.
        if let reading = try? database.latestBodyReading(
            userId: userId, before: ISODate.addDays(today, 1) ?? today
        ) {
            weightKg = reading.weightKg.map(Self.round1)
            bodyFatPct = reading.bodyFatPct.map(Self.round1)
            muscleMassKg = reading.skeletalMuscleMassKg.map(Self.round1)
            bmr = reading.bmr.map { $0.rounded() }
            readingDate = reading.date
        }

        // A goal already set is reopened as it was, not re-proposed.
        if let target = current?.goalTarget, current?.goal != nil {
            targetWeightKg = target.targetWeightKg
            targetBodyFatPct = target.targetBodyFatPct
            targetMuscleMassKg = target.targetMuscleMassKg
            horizonWeeks = target.horizonWeeks.map { min(max($0, Self.horizonRange.lowerBound), Self.horizonRange.upperBound) } ?? 12
            targetTouched = true
        } else {
            proposeTarget()
        }
        recomputeTargets()
        if running, let existing = try? database.phaseGoals(userId: userId, planId: programId, phase: goal.phase),
           existing.calorieGoal > 0, current?.goal == goal {
            // The running program's own numbers, when the goal is unchanged:
            // reopening the sheet must not quietly re-derive tuned macros.
            kcal = existing.calorieGoal
            proteinG = existing.proteinGoalG
            carbsG = existing.carbsGoalG
            fatG = existing.fatGoalG
        }
    }

    // MARK: - Derived

    var now: BodyNow { BodyNow(weightKg: weightKg, bodyFatPct: bodyFatPct, muscleMassKg: muscleMassKg) }

    var target: ProgramGoalTarget {
        switch goal {
        case .bulk, .cut, .recomp:
            ProgramGoalTarget(targetWeightKg: targetWeightKg, horizonWeeks: horizonWeeks)
        case .bodyFat:
            ProgramGoalTarget(targetBodyFatPct: targetBodyFatPct, horizonWeeks: horizonWeeks)
        case .muscleMass:
            ProgramGoalTarget(targetMuscleMassKg: targetMuscleMassKg, horizonWeeks: horizonWeeks)
        }
    }

    /// The implied pace and its verdict, or nil when there is nothing to
    /// start from or nothing to convert (`GoalPace.plan`).
    var pace: GoalPlan? { GoalPace.plan(goal: goal, now: now, target: target) }

    /// The ISO day the horizon ends on.
    func endDate(today: String = LogicalDay.today()) -> String? {
        ISODate.addDays(today, horizonWeeks * 7)
    }

    var targets: StartingTargets {
        let k = Int(kcal ?? 0)
        return StartingTargets(
            kcal: k, proteinG: Int(proteinG ?? 0), carbsG: Int(carbsG ?? 0), fatG: Int(fatG ?? 0),
            // Fibre tracks the kcal the user ends up with, as onboarding does.
            fiberG: Int((Double(k) / 1000 * StartingTargetsBuilder.fiberPerThousandKcal).rounded()),
            stepsGoal: StartingTargetsBuilder.build(weightKg: weightKg ?? 75, programGoal: goal).stepsGoal
        )
    }

    var atwaterGap: Int { targets.atwaterKcal - Int(kcal ?? 0) }

    /// The template this goal suits — nil when it is the program being set
    /// up (Onyx-4 is not a recommendation for Onyx-4).
    var recommended: PlanTemplates.TemplatePlan? {
        PlanTemplates.plans.first { $0.id == goal.recommendedTemplateId && $0.id != programId }
    }

    /// Step 2 needs a weight: every figure downstream is scaled from it.
    var canAdvance: Bool {
        switch step {
        case .now: weightKg.map(StartingTargetsBuilder.weightRange.contains) ?? false
        default: true
        }
    }

    // MARK: - Edits

    func markTargetTouched() { targetTouched = true }
    func markTargetsTouched() { targetsTouched = true }

    func recomputeTargets() {
        let t = StartingTargetsBuilder.build(weightKg: weightKg ?? 75, programGoal: goal)
        kcal = Double(t.kcal)
        proteinG = Double(t.proteinG)
        carbsG = Double(t.carbsG)
        fatG = Double(t.fatG)
        targetsTouched = false
    }

    /// A starting target, so the pace has something to show before a field
    /// is touched — and one the app will not then warn about: the MIDDLE of
    /// the goal's safe band, held for the horizon, from the reading in hand.
    /// Nothing when there is no reading to move from.
    private func proposeTarget() {
        targetWeightKg = nil; targetBodyFatPct = nil; targetMuscleMassKg = nil
        guard let w = weightKg, StartingTargetsBuilder.weightRange.contains(w) else { return }
        let band = StartingTargetsBuilder.weeklyRate(weightKg: w, programGoal: goal)
        let destination = w + (band.min + band.max) / 2 * Double(horizonWeeks)
        switch goal {
        case .bulk, .cut, .recomp:
            targetWeightKg = Self.round1(destination)
        case .bodyFat:
            // The weight the band arrives at, read back as a percentage at
            // constant lean mass — `GoalPace`'s conversion, inverted.
            targetBodyFatPct = bodyFatPct.map { bf in Self.round1((1 - w * (1 - bf / 100) / destination) * 100) }
        case .muscleMass:
            targetMuscleMassKg = muscleMassKg.map { Self.round1($0 + (destination - w)) }
        }
    }

    private func weightChanged() {
        if !targetTouched { proposeTarget() }
        if !targetsTouched { recomputeTargets() }
    }

    // MARK: - Navigation

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: - The write

    /// Save the goal to the program; run it when the program is running.
    /// Returns true when the sheet may close.
    func save(today: String = LogicalDay.today()) -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        var stored = target
        stored.weeklyRateKg = pace?.weeklyRateKg
        stored.startWeightKg = weightKg
        do {
            if acceptTemplate, let template = recommended {
                if hasDays {
                    // A program with days of its own is never overwritten: the
                    // template becomes a benched program of its own, carrying
                    // the same goal.
                    // Named for its goal — "Onyx-4 · Cut" — so it never reads as
                    // a second copy of a template the account already runs.
                    let id = try PlanTemplates.copy(
                        template, into: database, userId: userId, name: "\(template.label) · \(goal.label)",
                        goal: goal, goalTarget: stored
                    )
                    try database.applyProgramGoal(
                        userId: userId, programId: id, goal: goal, target: stored, targets: targets, weightKg: weightKg
                    )
                } else {
                    try PlanTemplates.fileMovements(template, into: database, userId: userId)
                    try database.writeDays(userId: userId, programId: programId, days: PlanTemplates.routineDays(template))
                }
            }
            try database.applyProgramGoal(
                userId: userId, programId: programId, goal: goal, target: stored, targets: targets, weightKg: weightKg
            )
            if running {
                // The existing phase switch, then "my own numbers": the macros
                // were just approved on screen, so no rung holds them
                // (`SettingsModel.saveGoals` makes the same call).
                try database.activateProgram(userId: userId, programId: programId, phase: goal.phase, startedOn: today)
                _ = try database.editUserGoals(userId: userId) { $0.activeLever = "custom" }
            }
            failure = nil
            return true
        } catch {
            failure = "Could not save the goal. \((error as? LocalizedError)?.errorDescription ?? "")"
            return false
        }
    }

    // MARK: - Words

    /// "Cut · 74 kg in 12 wk" — the goal row's value on the program editor
    /// and in Settings.
    static func summary(_ plan: PlanInfo) -> String {
        guard let goal = plan.goal else { return "Set a goal" }
        let t = plan.goalTarget
        let weeks = t?.horizonWeeks.map { " in \($0) wk" } ?? ""
        let figure: String? = switch goal {
        case .bulk, .cut, .recomp: t?.targetWeightKg.map { "\(kg($0)) kg" }
        case .bodyFat:             t?.targetBodyFatPct.map { "\(kg($0)) %" }
        case .muscleMass:          t?.targetMuscleMassKg.map { "\(kg($0)) kg muscle" }
        }
        return [goal.label, figure.map { $0 + weeks }].compactMap { $0 }.joined(separator: " · ")
    }

    static func kg(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}
