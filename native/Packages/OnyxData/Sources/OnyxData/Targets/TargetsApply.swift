import Foundation
import GRDB
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// APPLYING A PASTED REPORT'S TARGETS (W7, decision 23).
//
// `TargetsBlockParser` reads the block. This decides what it WOULD change, and
// then changes it — two steps and not one, because the step between them is a
// human looking at a diff. A paste is the one write path in this app whose
// content nobody in this process typed.
//
// ── IT WRITES THROUGH THE EXISTING WRITERS AND NOWHERE ELSE ─────────────────
// `editUserGoals`, `editPlanPhaseGoals` and `recordLeverChange`. No new SQL, no
// second spelling of "save the goals": those three already keep the rules a
// goal edit has to keep — the row and its outbox item land in one transaction,
// both tables move together, and closing a keyless lever stretch pins the
// numbers it was graded against. A paste that wrote its own UPDATE would be a
// fourth writer and the first one allowed to forget.
// ─────────────────────────────────────────────────────────────────────────────

/// What a pasted block would do, one line per field.
public struct TargetsPlan: Sendable, Equatable, Identifiable {

    public struct Change: Sendable, Equatable, Identifiable {
        /// "Calories", "Protein", "Lever". Unique within a plan, so it is the id.
        public var field: String
        /// What the row holds now, or nil when nothing does.
        public var current: String?
        public var proposed: String
        /// False when the line is REPORTED but will not be written — an unknown
        /// rung, or a rung a typed number supersedes. A preview that showed
        /// only what it would do would leave a reader wondering where the
        /// other half of the block went.
        public var applies: Bool
        public var reason: String?
        /// This row is the rung and not a number.
        ///
        /// A flag rather than `field != "Lever"`: `field` is the label drawn on
        /// screen, and control flow keyed on user-facing copy turns a wording
        /// change into a write nobody asked for.
        public var isLever: Bool

        public var id: String { field }

        public init(
            field: String, current: String?, proposed: String,
            applies: Bool = true, reason: String? = nil, isLever: Bool = false
        ) {
            self.field = field
            self.current = current
            self.proposed = proposed
            self.applies = applies
            self.reason = reason
            self.isLever = isLever
        }
    }

    /// The date the block asked for, verbatim.
    public var weekStart: String
    /// Where the lever period actually starts. Always today.
    ///
    /// ── A PASTE CANNOT RE-GRADE THE PAST ────────────────────────────────────
    /// `lever_periods` decides which targets a DATE was graded against, and
    /// days already scored were scored against the rung that was in force.
    /// Back-dating a period would silently re-grade them — a report written on
    /// Monday about last week would change last week's adherence.
    ///
    /// ── AND IT CANNOT SCHEDULE THE FUTURE EITHER ────────────────────────────
    /// The first cut honoured a `weekStart` ahead of today. `invariant-auditor`
    /// showed what that costs: `recordLeverChange` PINS the open keyless
    /// stretch with the live numbers whenever it writes a row dated after it,
    /// so a period dated next Monday freezes today's targets at tap time and
    /// every edit made in between is ignored for grading — the exact failure
    /// `PlanCatalogue`'s own header says pinning early would cause.
    ///
    /// Fixing that inside `recordLeverChange` would give this app two answers
    /// to "when does a rung start". It has one: the Settings picker stamps
    /// today (`SettingsModel.pickLever`), and so does this. A block dated ahead
    /// applies now, and the preview says which date was asked for.
    public var effectiveFrom: String
    public var note: String?
    public var changes: [Change]
    /// The rung to select, or nil.
    public var leverKey: String?
    /// The numbers to write.
    public var goals: TargetsBlock.DailyTargets?

    public init(
        weekStart: String, effectiveFrom: String, note: String? = nil,
        changes: [Change], leverKey: String? = nil, goals: TargetsBlock.DailyTargets? = nil
    ) {
        self.weekStart = weekStart
        self.effectiveFrom = effectiveFrom
        self.note = note
        self.changes = changes
        self.leverKey = leverKey
        self.goals = goals
    }

    /// Nothing to write. A plan can have lines and still be empty — every one
    /// of them reported and none of them applying.
    public var isEmpty: Bool { !changes.contains(where: \.applies) }

    /// The report named a date other than the one this applies on.
    public var wasBackdated: Bool { effectiveFrom != weekStart }

    /// For `.sheet(item:)`. A plan is a value, and two plans that would do the
    /// same thing ARE the same sheet — re-previewing an unchanged paste must
    /// not shuffle a sheet that is already open.
    public var id: String {
        "\(weekStart)|\(effectiveFrom)|\(leverKey ?? "")|"
            + changes.map { "\($0.field):\($0.proposed):\($0.applies)" }.joined(separator: ",")
    }
}

public extension AppDatabase {

    /// What this block would change, against what the store holds now.
    ///
    /// A read, and only a read. Every decision the apply makes is made here, so
    /// the sheet the athlete approves is the thing that runs.
    func targetsPlan(
        for block: TargetsBlock, userId: String, today: String = LogicalDay.today()
    ) throws -> TargetsPlan {
        let goals = try userGoals(userId: userId)
        let ladder = try leverLadder(userId: userId)
        let proposed = block.dailyTargets
        var changes: [TargetsPlan.Change] = []

        // ── The rung ────────────────────────────────────────────────────────
        // First, because whether it applies depends on what the macros do.
        var leverKey: String?
        if let asked = block.levers?.first(where: { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let key = asked.key.trimmingCharacters(in: .whitespaces)
            let rung = Levers.lever(byId: key, in: ladder)
            let current = Levers.lever(byId: goals?.activeLever, in: ladder)?.label
                ?? (goals?.activeLever == "custom" ? "My own numbers" : nil)
            if rung == nil {
                changes.append(.init(
                    field: "Lever", current: current, proposed: key,
                    applies: false,
                    reason: "no rung with that key — a report cannot create one", isLever: true))
            } else if proposed?.hasMacros == true {
                changes.append(.init(
                    field: "Lever", current: current, proposed: rung!.label,
                    applies: false,
                    reason: "the numbers below replace it — typing a figure is choosing your own", isLever: true))
            } else if goals?.activeLever == key {
                // Already on it. Reported so the sheet is not empty for a block
                // that named the rung the athlete is already running.
                changes.append(.init(
                    field: "Lever", current: current, proposed: rung!.label,
                    applies: false, reason: "already in force", isLever: true))
            } else {
                leverKey = key
                changes.append(.init(field: "Lever", current: current, proposed: rung!.label, isLever: true))
            }
        }

        // ── The numbers ─────────────────────────────────────────────────────
        func line(_ field: String, _ current: Double?, _ next: Double?, _ unit: String, decimals: Int = 0) {
            guard let next else { return }
            let now = current.map { Self.figure($0, unit, decimals: decimals) }
            let then = Self.figure(next, unit, decimals: decimals)
            guard now != then else { return }
            changes.append(.init(field: field, current: now, proposed: then))
        }
        line("Calories", goals?.calorieGoal.map(Double.init), proposed?.kcal, "kcal")
        line("Protein", goals?.proteinGoalG.map(Double.init), proposed?.proteinG, "g")
        line("Carbs", goals?.carbsGoalG.map(Double.init), proposed?.carbsG, "g")
        line("Fat", goals?.fatGoalG.map(Double.init), proposed?.fatG, "g")
        line("Steps", goals?.stepsGoal.map(Double.init), proposed?.stepsGoal, "")
        line("Water", goals?.waterGoalMl.map(Double.init), proposed?.waterMl, "ml")
        line("Sleep", goals?.sleepGoalHours, proposed?.sleepHours, "h", decimals: 1)

        return TargetsPlan(
            weekStart: block.weekStart,
            effectiveFrom: today,
            note: block.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            changes: changes,
            leverKey: leverKey,
            goals: proposed
        )
    }

    /// Write the plan.
    ///
    /// ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────
    /// It does not rescore. `user_goals` is not a dated table, so W2's door at
    /// `AppDatabase.onCommit` does not hear this write — which is the same
    /// thing that is true of every goal edit made in the You tab, and the same
    /// answer: Settings → "Recompute history". Silently re-grading months of
    /// adherence because a report suggested a number is not a thing a paste
    /// should be allowed to do without being asked.
    func applyTargets(_ plan: TargetsPlan, userId: String, now: Date = Date()) throws {
        guard !plan.isEmpty else { return }
        let goals = plan.goals
        let writesNumbers = plan.changes.contains { $0.applies && !$0.isLever }

        if writesNumbers {
            let context = try scheduleContext(userId: userId)
            let planId = context.programId
            let phase = context.phase
            try editUserGoals(userId: userId, now: now) { row in
                if let v = goals?.kcal { row.calorieGoal = Self.whole(v) }
                if let v = goals?.proteinG { row.proteinGoalG = Self.whole(v) }
                if let v = goals?.carbsG { row.carbsGoalG = Self.whole(v) }
                if let v = goals?.fatG { row.fatGoalG = Self.whole(v) }
                if let v = goals?.stepsGoal { row.stepsGoal = Self.whole(v) }
                if let v = goals?.waterMl { row.waterGoalMl = Self.whole(v) }
                if let v = goals?.sleepHours { row.sleepGoalHours = v }
                // Typing a number IS choosing "my own numbers" — the rule
                // `SettingsModel.saveGoals` keeps, and a figure a rung then
                // overrode would be an instruction that did nothing.
                if goals?.hasMacros == true { row.activeLever = "custom" }
            }
            // Only the five the override holds, and only when one of them moved:
            // the plan-phase row has no water and no sleep, and writing it for a
            // water-only block would be a row with five nils in it.
            if goals?.hasMacros == true, !planId.isEmpty {
                try editPlanPhaseGoals(userId: userId, planId: planId, phase: phase.rawValue, now: now) { row in
                    if let v = goals?.kcal { row.kcal = Self.whole(v) }
                    if let v = goals?.proteinG { row.proteinG = Self.whole(v) }
                    if let v = goals?.carbsG { row.carbsG = Self.whole(v) }
                    if let v = goals?.fatG { row.fatG = Self.whole(v) }
                    if let v = goals?.stepsGoal { row.stepsGoal = Self.whole(v) }
                }
            }
        }

        // The rung, or the stretch that "my own numbers" opens. Both are a
        // `lever_periods` row, and both pin the keyless stretch they close —
        // which is the whole reason this goes through `recordLeverChange` and
        // not through an insert.
        // `calorie` is non-optional in `LeverGoals` and the four beside it are
        // not, so an absent calorie goal reads as 0 here. Against the house
        // rule, and deliberate: this is `SettingsModel.ownGoals` spelled again,
        // and the pin these numbers go into has to mean the same thing whether
        // the rung was changed in Settings or by a paste.
        let own = try userGoals(userId: userId).map { row in
            LeverGoals(
                calorie: Double(row.calorieGoal ?? 0),
                protein: row.proteinGoalG.map(Double.init),
                carbs: row.carbsGoalG.map(Double.init),
                fat: row.fatGoalG.map(Double.init),
                steps: row.stepsGoal.map(Double.init))
        } ?? LeverGoals(calorie: 0, protein: nil, carbs: nil, fat: nil, steps: nil)

        if let key = plan.leverKey {
            try editUserGoals(userId: userId, now: now) { $0.activeLever = key }
            try recordLeverChange(userId: userId, profileKey: key, ownGoals: own, today: plan.effectiveFrom)
        } else if goals?.hasMacros == true {
            try recordLeverChange(userId: userId, profileKey: nil, ownGoals: own, today: plan.effectiveFrom)
        }
    }

    /// ── THE SHEET ROUNDS, SO THE WRITE ROUNDS ──────────────────────────────
    /// `figure` below formats with `.fractionLength(0)`, which ROUNDS; the
    /// write used a truncating conversion. A block asking for 2100.6 kcal
    /// showed "2,101 kcal" on the sheet the athlete approved and wrote 2100 —
    /// and a value that rounded to the current figure produced no diff line at
    /// all while still writing one less. `invariant-auditor` found it. This is
    /// the one conversion, and it is the one the sheet displayed.
    ///
    /// It also CLAMPS. `TargetsBlockParser.validate` refuses a target over a
    /// million, so this is only reachable by a caller building a plan by hand
    /// — but `Int.init(Double)` TRAPS rather than throwing, and a trap on
    /// pasted, model-authored content is a crash on untrusted input.
    static func whole(_ v: Double?) -> Int? {
        v.map { Int(min(max($0.rounded(), 0), 1_000_000)) }
    }

    /// `2,100 kcal`, `170 g`, `10,000`, `8.0 h`. Grouped, because these are
    /// read side by side in a diff and 10000 next to 2100 is a column of digits
    /// rather than two numbers.
    static func figure(_ value: Double, _ unit: String, decimals: Int) -> String {
        // Round HERE, not in the formatter. `whole` above uses `.rounded()`,
        // which is half-away-from-zero; the formatter's own rule is half-even.
        // They agree everywhere except an exact `.5`, where the sheet said
        // "2,100 kcal" and the write stored 2101 — and if no other field moved
        // the diff line was suppressed as unchanged while the write still
        // happened. The block above says these two are one conversion; this is
        // what makes that true.
        let scale = pow(10.0, Double(decimals))
        let rounded = (value * scale).rounded() / scale
        let number = rounded.formatted(.number.precision(.fractionLength(decimals)).grouping(.automatic))
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

