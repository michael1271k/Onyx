import Foundation
import Observation
import OnyxCore
import OnyxData

/// Everything the You tab reads and writes.
///
/// ── ONE MODEL FOR FOUR SCREENS, AND WHY ─────────────────────────────────────
/// The hub, the levers, the plan and the body targets are four views of the SAME
/// two rows: `user_goals` and the `(plan, phase)` override. The web app gave each
/// page its own hook over its own react-query cache, and the recurring bug there
/// is two of them disagreeing — the hub showing "Baseline · 1,955" while the
/// levers page, one navigation away, shows the rung you just changed it to.
///
/// One model observing one stream cannot do that. Every screen reads the same
/// published value, and a write anywhere redraws all of them because GRDB's
/// observation fires, not because someone remembered to invalidate a key.
///
/// ── AND WHY IT PATCHES RATHER THAN SAVES ────────────────────────────────────
/// Each method below changes the fields it names and nothing else. The web app's
/// `save()` spread twelve fields on every call, which is why flipping Reduce
/// Motion rewrote the calorie target — a real bug, reachable from a toggle.
@MainActor
@Observable
final class SettingsModel {

    private let database: AppDatabase
    let userId: String

    /// The logical day. Held rather than computed per call so that every
    /// resolution in one render agrees — a lever that changed at the cutoff
    /// hour must not make half the screen say one thing and half another.
    private(set) var today: String = LogicalDay.today()

    private(set) var goals: UserGoalRow?
    private(set) var phaseGoals: PlanPhaseGoalRow?
    /// Muscle name → stored weekly set target. Absent means "the program's own".
    private(set) var volumeOverrides: [String: Int] = [:]

    /// The last write that failed, for the one banner every screen shows.
    private(set) var failure: String?

    init(database: AppDatabase, userId: String) {
        self.database = database
        self.userId = userId
    }

    // MARK: - Reading

    private var isObserving = false

    /// Subscribe. Called from `.task`, cancelled with the view.
    ///
    /// One loop, not a task group: the goals row is the ONLY thing this method
    /// waits on, and the two subscriptions that depend on it are restarted from
    /// inside it rather than raced beside it.
    ///
    /// ── EVERY SCREEN CALLS IT, AND ONLY ONE SUBSCRIPTION EXISTS ─────────────
    /// The four screens share one model, and any of them can be the first one
    /// on screen — a deep link, or the screenshot harness, opens Levers with no
    /// hub above it. So each calls this from its own `.task` and the guard makes
    /// the rest no-ops. Without it, Levers opened on its own would render the
    /// SCHEDULE's answer for a user whose row simply had not been read yet,
    /// which is a different rung with different numbers.
    ///
    /// The flag is cleared on the way out, so when the owning view goes away the
    /// next screen's `.task` takes over the subscription rather than nobody
    /// holding it.
    func observe() async {
        guard !isObserving else { return }
        isObserving = true
        // The two dependent subscriptions are started from inside this call but
        // live in their own tasks, so they are reaped HERE — when the owning
        // view's `.task` is cancelled — rather than left running against a store
        // nobody is showing. Signing out tears the tab down; without this, two
        // observations of the previous user's database would outlive it.
        defer {
            isObserving = false
            phaseGoalsTask?.cancel()
            volumeTask?.cancel()
            phaseStreamKey = ""
        }
        today = LogicalDay.today()
        do {
            // The target snapshot, not the goals row alone: it carries the
            // goals row AND the catalogue (decks, plans, phases) AND the
            // ladder (rungs, periods), and it ticks when any of them changes —
            // a plan switched here, a routine edited on the web, a rung
            // pulled from another device.
            for try await snap in database.targetSnapshotStream(userId: userId) {
                goals = snap.goals
                schedule = snap.schedule
                ladder = snap.ladder
                // The plan and phase can change under us — from this screen, or
                // from a realtime push of an edit made on the web — and the
                // override rows are KEYED on them, so their subscriptions are
                // restarted rather than filtered.
                restartPhaseStreams()
            }
        } catch {
            report(error)
        }
    }

    /// The live catalogue with the selection applied, and the rungs.
    private(set) var schedule = ScheduleContext(programId: "", phase: .cut)
    private(set) var ladder = LeverLadder.empty

    private var phaseGoalsTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var phaseStreamKey = ""

    private func restartPhaseStreams() {
        let plan = planId
        let phaseKey = phase.rawValue
        // Cheap guard, and a necessary one: every goals row that arrives would
        // otherwise tear down and rebuild two observations, which is two
        // needless queries per keystroke saved.
        guard phaseStreamKey != "\(plan)|\(phaseKey)" else { return }
        phaseStreamKey = "\(plan)|\(phaseKey)"

        phaseGoalsTask?.cancel()
        volumeTask?.cancel()

        // ── CLEARED, NOT LEFT STANDING ──────────────────────────────────────
        // These two are keyed on the plan and phase that just changed, so the
        // values in hand belong to the OLD key until the new stream's first
        // yield. Publishing them across that gap shows the previous phase's
        // body targets and set targets — and a stepper tapped in that window
        // writes one of them back under the new key.
        phaseGoals = nil
        volumeOverrides = [:]

        phaseGoalsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let rows = database.planPhaseGoalsStream(userId: userId, planId: plan, phase: phaseKey)
                for try await row in rows { phaseGoals = row }
            } catch {
                report(error)
            }
        }
        volumeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let maps = database.planPhaseVolumeStream(userId: userId, planId: plan, phase: phaseKey)
                for try await map in maps { volumeOverrides = map }
            } catch {
                report(error)
            }
        }
    }

    /// What the banner says.
    ///
    /// ── CANCELLATION IS NOT A FAILURE ───────────────────────────────────────
    /// An `AsyncThrowingStream` throws `CancellationError` when its consumer is
    /// cancelled, and `restartPhaseStreams` cancels both on every plan or phase
    /// change. Reported verbatim, that meant switching plan — the one
    /// destructive action in the tab — reliably painted "CancellationError()"
    /// underneath it, which reads as "the switch failed".
    ///
    /// And nothing else is reported verbatim either. `String(describing:)` on a
    /// GRDB error is a stack trace shown to somebody who wanted to change their
    /// step goal.
    private func report(_ error: any Error) {
        if error is CancellationError { return }
        failure = "That change could not be saved on this device."
    }

    // MARK: - Derived

    /// The active plan, normalised. Unknown and absent both land on the live
    /// block rather than on nothing — a settings screen with no plan selected
    /// can offer no correct answer at all.
    var planId: String { schedule.programId }

    var plan: PlanInfo {
        schedule.plans.first { $0.id == planId } ?? PlanInfo(id: planId, label: planId, blurb: "")
    }

    /// The picker's list — live plans first, legacy last.
    var plans: [PlanInfo] { Programs.pickerOrder(schedule.plans) }

    /// The ladder's ordered rungs — what the Levers screen lists.
    var rungs: [NutritionLever] { ladder.deficit }

    /// `maintenance` is not a training phase and never was; a stored one reads
    /// back as cut, in one place, for the same reason the TypeScript narrows it
    /// in two.
    var phase: ProgramPhase {
        ProgramPhase.stored(goals?.activePhase ?? goals?.goalPreset)
    }

    /// The rung in force TODAY — schedule, stored selection, or an expired
    /// release falling back to the schedule.
    var leverInForce: String? {
        Levers.leverForDate(today, today: today, in: ladder)
    }

    /// Non-nil when a rung HOLDS the five numbers, which is what makes the
    /// targets read-only. `custom` and no selection are both nil.
    var heldBy: NutritionLever? {
        Levers.lever(byId: leverInForce, in: ladder)
    }

    /// Is a release rung on, and not yet expired?
    var isMaintenanceOn: Bool {
        heldBy?.kind == .release
    }

    /// The release rung this account has, if any — what "Maintenance week"
    /// switches on. Nil means the ladder has no release and the toggle hides.
    var releaseRung: NutritionLever? {
        ladder.rungs.first { $0.kind == .release }
    }

    /// The five numbers the user's own row holds, before any rung.
    var ownGoals: LeverGoals {
        LeverGoals(
            calorie: Double(goals?.calorieGoal ?? 0),
            protein: goals?.proteinGoalG.map(Double.init),
            carbs: goals?.carbsGoalG.map(Double.init),
            fat: goals?.fatGoalG.map(Double.init),
            steps: goals?.stepsGoal.map(Double.init)
        )
    }

    /// The five numbers actually in force — the rung's when one holds, yours
    /// otherwise. This is what every screen displays.
    var shownGoals: LeverGoals {
        Levers.applyLever(ownGoals, leverInForce, in: ladder)
    }

    /// Atwater energy of the shown triple, and its distance from the shown
    /// calories. A gap only means something when the numbers are the user's own:
    /// the rungs are asserted exact by their own vectors.
    var atwaterGap: Double? {
        guard heldBy == nil,
              let p = shownGoals.protein, let c = shownGoals.carbs, let f = shownGoals.fat
        else { return nil }
        return Levers.atwaterKcal(proteinG: p, carbsG: c, fatG: f) - shownGoals.calorie
    }

    /// A body destination: the override when the user set one, the phase preset
    /// otherwise. `nil` is a real answer and is never rendered as zero.
    var targetWeightKg: Double? { phaseGoals?.targetWeightKg ?? preset.targetWeightKg }
    var targetBodyFatPct: Double? { phaseGoals?.targetBodyFatPct ?? preset.targetBodyFatPct }
    var targetMuscleMassKg: Double? { phaseGoals?.targetMuscleMassKg ?? preset.targetMuscleMassKg }

    /// The phase's goals — the `plan_phase_goals` row, as a value. No compiled
    /// preset since W2: a plan with no row aims at nothing until one is written.
    var preset: PhaseGoals { phaseGoals.map(PhaseGoals.init) ?? .empty(phase) }

    /// The weekly set target for a muscle — the `plan_phase_volume` row, or 0.
    func volumeTarget(_ muscle: LandmarkMuscle) -> Int {
        volumeOverrides[muscle.rawValue] ?? 0
    }

    var volumeTotal: Int {
        LandmarkMuscle.allCases.reduce(0) { $0 + volumeTarget($1) }
    }

    /// The goals row of ANOTHER plan and phase — what the picker previews
    /// before the switch. A plain read: the picker is a transient sheet.
    func goals(for planId: String, phase: ProgramPhase) -> PhaseGoals {
        ((try? database.phaseGoals(userId: userId, planId: planId, phase: phase)) ?? nil) ?? .empty(phase)
    }

    /// The weekly set total another plan and phase prescribe.
    func volumeTotal(for planId: String, phase: ProgramPhase) -> Double {
        ((try? database.volumeTargets(userId: userId, planId: planId, phase: phase)) ?? [:]).values.reduce(0, +)
    }

    /// Re-read the logical day.
    ///
    /// An app left open across the cutoff hour otherwise resolves the rung in
    /// force, and the expiry that CLOSES a release, against yesterday.
    func refreshToday() {
        today = LogicalDay.today()
    }

    /// The deck a plan trains — its `routines` rows. Nil when the rows do not
    /// describe one, and deliberately not another plan's: a screen that shows
    /// the wrong plan's sessions is worse than one that says it has none.
    func deck(for planId: String) -> Program? {
        schedule.program(id: planId).flatMap { $0.days.isEmpty ? nil : $0 }
    }

    // MARK: - Writing

    /// Every write funnels through here so that one failure path exists, and so
    /// that a screen never has to think about the outbox.
    ///
    /// ── THE LOCAL EDIT LANDS FIRST, THEN THE STORE ──────────────────────────
    /// `patch` applies the change to the published row immediately; `body`
    /// persists it and the observation confirms it a runloop hop later. Without
    /// the first half, every control reads a value that is one hop stale: two
    /// quick taps on a stepper both read the same number and produce +1 instead
    /// of +2, and a toggle visibly snaps back before settling.
    private func write(
        patch: (inout UserGoalRow) -> Void = { _ in },
        save: @escaping @Sendable () throws -> Void
    ) {
        if goals != nil { patch(&goals!) }
        do {
            try save()
            failure = nil
        } catch {
            report(error)
        }
    }

    func setUnitSystem(_ value: String) {
        write(patch: { $0.unitSystem = value }) { [database, userId] in
            try database.editUserGoals(userId: userId) { $0.unitSystem = value }
        }
    }

    /// `week_end_day` 0 (Sunday) means the week STARTS on Monday; anything else
    /// means Sunday. The column is the end day, the control asks for the start
    /// day, and the inversion lives here rather than in the view.
    func setWeekStartDay(_ startDay: Int) {
        let endDay = startDay == 1 ? 0 : 6
        write(patch: { $0.weekEndDay = endDay }) { [database, userId] in
            try database.editUserGoals(userId: userId) { $0.weekEndDay = endDay }
        }
    }

    func setTrackRpe(_ value: Bool) {
        write(patch: { $0.trackRpe = value }) { [database, userId] in
            try database.editUserGoals(userId: userId) { $0.trackRpe = value }
        }
    }

    /// Choose a rung.
    ///
    /// ── A RUNG IS A LAYER, NOT AN EDIT ──────────────────────────────────────
    /// Only `active_lever` moves. The five numbers underneath stay exactly as
    /// they were, which is what lets "My own numbers" put them back untouched.
    /// The web app wrote the rung's figures INTO the goals row as well, so a
    /// release destroyed the deficit numbers it was a break from.
    /// `nil` is "my own numbers" — stored as `custom`, never as NULL: NULL
    /// means "no selection", which falls through to the schedule, and the
    /// schedule may well be the rung the user just turned off.
    func pickLever(_ id: String?) {
        let stored = id ?? "custom"
        let isRelease = Levers.lever(byId: id, in: ladder)?.kind == .release
        let own = ownGoals
        write(patch: { row in
            row.activeLever = stored
            if !isRelease { row.maintenanceUntil = nil }
        }) { [database, userId, today] in
            try database.editUserGoals(userId: userId) { row in
                row.activeLever = stored
                // Selecting a deficit rung while a release is still dated would
                // leave an expiry hanging over a rung that cannot expire. The
                // web app has this exact gap and gets away with it because the
                // expiry check reads `kind == .release`; leaving it set is still
                // a lie in the row.
                if !isRelease { row.maintenanceUntil = nil }
            }
            // The schedule is rows now (`lever_periods`), and a rung coming on
            // — or off — is an event the past must keep. The live numbers pin
            // whichever keyless stretch this change closes.
            try database.recordLeverChange(userId: userId, profileKey: id, ownGoals: own, today: today)
        }
    }

    /// Turn the release on with an end date, or off.
    ///
    /// Off writes `custom`, never `nil`: `nil` means "no selection", which falls
    /// through to the SCHEDULE — and the schedule may well be the rung the user
    /// just turned off.
    func setMaintenance(on: Bool, endsOn: String?) {
        guard let release = releaseRung else { return }
        let stored = on ? release.id : "custom"
        let own = ownGoals
        write(patch: { row in
            row.activeLever = stored
            row.maintenanceUntil = on ? endsOn : nil
        }) { [database, userId, today] in
            try database.editUserGoals(userId: userId) { row in
                row.activeLever = stored
                row.maintenanceUntil = on ? endsOn : nil
            }
            try database.recordLeverChange(userId: userId, profileKey: on ? release.id : nil, ownGoals: own, today: today)
        }
    }

    /// The default end date offered when the release is switched on: the end of
    /// the deload block the date falls in, or the Saturday of its week.
    func defaultMaintenanceEnd() -> String {
        if let span = Maintenance.span(for: today, phases: schedule.phases) { return span.end }
        guard let date = LogicalDay.date(fromISO: today) else { return today }
        let weekday = Calendar.current.component(.weekday, from: date) - 1  // 0 = Sunday
        return ISODate.addDays(today, 6 - weekday) ?? today
    }

    /// Save the five macro numbers.
    ///
    /// Writes BOTH tables, on purpose: the scorer and the widget snapshot read
    /// `user_goals` and know nothing about plan-phase rows, while the plan pages
    /// read the override. Writing one and not the other is how the two came to
    /// disagree on the web.
    ///
    /// Typing a number IS choosing "my own numbers" — a figure you typed that a
    /// rung then overrode would be a control that does nothing.
    func saveGoals(kcal: Double?, protein: Double?, carbs: Double?, fat: Double?, steps: Double?) {
        write(patch: { $0.activeLever = "custom" }) { [database, userId, planId, phase] in
            try database.editUserGoals(userId: userId) { row in
                row.calorieGoal = kcal.map { Int($0) }
                row.proteinGoalG = protein.map { Int($0) }
                row.carbsGoalG = carbs.map { Int($0) }
                row.fatGoalG = fat.map { Int($0) }
                row.stepsGoal = steps.map { Int($0) }
                row.activeLever = "custom"
            }
            try database.editPlanPhaseGoals(userId: userId, planId: planId, phase: phase.rawValue) { row in
                row.kcal = kcal.map { Int($0) }
                row.proteinG = protein.map { Int($0) }
                row.carbsG = carbs.map { Int($0) }
                row.fatG = fat.map { Int($0) }
                row.stepsGoal = steps.map { Int($0) }
            }
        }
    }

    /// Recovery and activity. These belong to the person, not to the plan phase,
    /// so they are editable whether or not a rung holds the macros.
    func saveRecovery(activeCalGoal: Double?, sleepHours: Double?, waterMl: Double?) {
        write { [database, userId] in
            try database.editUserGoals(userId: userId) { row in
                row.activeCalGoal = activeCalGoal.map { Int($0) }
                row.sleepGoalHours = sleepHours
                row.waterGoalMl = waterMl.map { Int($0) }
            }
        }
    }

    /// The three destinations. `nil` clears the override and the preset shows
    /// through again — blank means "no target of my own", never zero.
    func saveBodyTargets(weightKg: Double?, bodyFatPct: Double?, muscleMassKg: Double?) {
        write { [database, userId, planId, phase] in
            try database.editPlanPhaseGoals(userId: userId, planId: planId, phase: phase.rawValue) { row in
                row.targetWeightKg = weightKg
                row.targetBodyFatPct = bodyFatPct
                row.targetMuscleMassKg = muscleMassKg
            }
            try database.editUserGoals(userId: userId) { row in
                row.targetWeightKg = weightKg
                row.targetBodyFatPct = bodyFatPct
                row.targetMuscleMassKg = muscleMassKg
            }
        }
    }

    func setVolumeTarget(_ muscle: LandmarkMuscle, sets: Int) {
        let clamped = max(0, sets)
        // Published before the write, for the same reason the goal patches are:
        // a stepper held down reads this value on every repeat, and reading it
        // one runloop hop stale turns five presses into one.
        volumeOverrides[muscle.rawValue] = clamped
        write { [database, userId, planId, phase] in
            try database.setPlanPhaseVolume(
                userId: userId, planId: planId, phase: phase.rawValue,
                muscle: muscle.rawValue, targetSets: clamped
            )
        }
    }

    /// Switch plan and phase. The one destructive action in the tab.
    ///
    /// It writes the goals of the new phase, the plan and phase themselves, the
    /// date the phase started, and the dated plan registry the charts label eras
    /// from. All five, or the app and the charts describe different weeks.
    func activate(planId newPlanId: String, phase newPhase: ProgramPhase) {
        let startedOn = today
        write { [database, userId] in
            // The phase's own row, if the plan has one; an empty goal set
            // otherwise, which writes zeros the screens already read as unset.
            let goals = try database.phaseGoals(userId: userId, planId: newPlanId, phase: newPhase) ?? .empty(newPhase)
            try database.editUserGoals(userId: userId) { row in
                row.calorieGoal = Int(goals.calorieGoal)
                row.proteinGoalG = goals.proteinGoalG.map { Int($0) }
                row.carbsGoalG = goals.carbsGoalG.map { Int($0) }
                row.fatGoalG = goals.fatGoalG.map { Int($0) }
                row.stepsGoal = Int(goals.stepsGoal)
                row.targetWeightKg = goals.targetWeightKg
                row.targetBodyFatPct = goals.targetBodyFatPct
                row.targetMuscleMassKg = goals.targetMuscleMassKg
                row.activePlan = newPlanId
                row.activeProgram = newPlanId
                row.activePhase = newPhase.rawValue
                row.goalPreset = newPhase.rawValue
                row.phaseStartedOn = startedOn
            }
            try database.activatePlanRow(
                userId: userId, programId: newPlanId, startedOn: startedOn
            )
        }
    }
}
