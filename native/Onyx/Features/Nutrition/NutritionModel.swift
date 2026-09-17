import Foundation
import Observation
import OnyxCore
import OnyxData

/// Everything the Nutrition tab reads and writes, for ONE selected day.
///
/// ── THE TARGET IS RESOLVED FOR THE SELECTED DATE, NOT TODAY ─────────────────
/// A Tuesday opened on Friday is graded against the rung that was in force on
/// the Tuesday: `Levers.goalsForDate` reads the schedule for the past and the
/// stored selection for today-and-after, then the day's own `daily_targets` row
/// is laid on top. This is the same chain the You tab performs for today, with
/// the date as a parameter instead of a clock.
///
/// ── FIVE STREAMS AND THE RESOLVER ───────────────────────────────────────────
/// The goals row and the profiles come from `TargetResolver` — the one
/// instance `AppEnvironment` holds, so a lever pulled in Settings ticks this
/// tab through the same observation as every other reader (§6.2). Five streams
/// are keyed on the date (the flat day row, the entries, the water ledger, the
/// day target, the week) and are torn down and restarted when the day changes.
/// The values in hand belong to the previous day until the new streams' first
/// yield, so they are cleared rather than left standing across the gap.
@MainActor
@Observable
final class NutritionModel {

    private let database: AppDatabase
    let userId: String
    let targets: TargetResolver

    /// The logical day, held so one render resolves every rung the same way.
    private(set) var today: String = LogicalDay.today()
    /// The day on screen. Changes only through `select`, which restarts the
    /// per-date streams.
    private(set) var date: String

    private(set) var dailyLog: DailyLogRow?
    /// `nil` until the first yield — the loading state, which is not an empty
    /// day and must not be drawn as one.
    private(set) var entries: [NutritionEntryRow]?
    private(set) var water: [WaterIntakeRow] = []
    private(set) var dailyTarget: DailyTargetRow?
    /// What the supplement stack has delivered on this day. Read through
    /// `AppDatabase.stackCredit`, which owns the one resolution of "is this a
    /// training day" that Pulse and this tab must agree on.
    private(set) var stack: StackCredit = .empty
    /// The selected day and the six before it, oldest first — the adherence dots
    /// and the macros-vs-goal strip. Always seven entries once loaded; a day
    /// with nothing logged is present and untracked.
    private(set) var week: [NutritionDay] = []

    /// The last write that failed, for the one banner at the top.
    private(set) var failure: String?

    init(database: AppDatabase, userId: String, targets: TargetResolver, date: String = LogicalDay.today()) {
        self.database = database
        self.userId = userId
        self.targets = targets
        self.date = date
    }

    /// The goals row, off the resolver — water goal and the phase stamp.
    var goals: UserGoalRow? { targets.snapshot.goals }

    // MARK: - Reading

    private var isObserving = false
    private var dateTasks: [Task<Void, Never>] = []

    /// Subscribe. Called from `.task`, cancelled with the view. Re-entrant
    /// calls are no-ops; the child tasks are reaped when the owner's is.
    func observe() async {
        guard !isObserving else { return }
        isObserving = true
        defer {
            cancelDateTasks()
            isObserving = false
        }
        today = LogicalDay.today()
        restartDateStreams()
        // Park until the view goes away. `.task` cancels this, the `defer`
        // runs, and every child is reaped with it.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(300))
        }
    }

    func select(date newDate: String) {
        guard newDate != date else { return }
        date = newDate
        restartDateStreams()
    }

    /// Step a day. Never past today — a target for a day that has not happened
    /// is not a thing this screen grades.
    func shift(_ days: Int) {
        guard let next = ISODate.addDays(date, days), next <= today else { return }
        select(date: next)
    }

    var isToday: Bool { date == today }

    /// Re-read the logical day; an app left open across midnight otherwise
    /// resolves the rung against yesterday.
    func refreshToday() {
        today = LogicalDay.today()
    }

    private func restartDateStreams() {
        cancelDateTasks()
        dailyLog = nil
        entries = nil
        water = []
        dailyTarget = nil
        week = []
        // Before the guard: the credit is a READ, not a stream, so a model that
        // is only rendered — a preview, the shot loop — still shows the right
        // number rather than an empty stack.
        reloadStack()
        guard isObserving else { return }
        let date = self.date
        let weekStart = ISODate.addDays(date, -6) ?? date
        dateTasks = [
            track(database.dailyLogStream(userId: userId, date: date)) { [weak self] in self?.dailyLog = $0 },
            track(database.nutritionEntriesStream(userId: userId, date: date)) { [weak self] in self?.entries = $0 },
            track(database.waterIntakeStream(userId: userId, date: date)) { [weak self] in self?.water = $0 },
            track(database.dailyTargetStream(userId: userId, date: date)) { [weak self] in self?.dailyTarget = $0 },
            track(database.nutritionWeekStream(userId: userId, from: weekStart, to: date)) { [weak self] in self?.week = $0 },
            // The two tables that can move the stack's contribution within a
            // day. The credit itself is re-read rather than derived here, so
            // this tab and Pulse cannot disagree about the same date.
            track(database.customSupplementsStream(userId: userId)) { [weak self] _ in self?.reloadStack() },
            track(database.supplementLogStream(userId: userId, date: date)) { [weak self] _ in self?.reloadStack() },
        ]
    }

    /// Re-read the day's stack credit. Cheap: one pass over five small tables.
    private func reloadStack() {
        stack = (try? database.stackCredit(userId: userId, date: date, today: today)) ?? .empty
    }

    private func cancelDateTasks() {
        dateTasks.forEach { $0.cancel() }
        dateTasks = []
    }

    private func track<T: Sendable>(
        _ stream: AsyncThrowingStream<T, any Error>,
        _ apply: @escaping @MainActor (T) -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                for try await value in stream { apply(value) }
            } catch {
                self?.report(error, wrote: false)
            }
        }
    }

    /// Cancellation is not a failure: every day change cancels five streams.
    ///
    /// A read and a write fail differently and the banner has to say which:
    /// telling someone their change could not be saved when nothing was being
    /// saved sends them looking for an edit to redo.
    private func report(_ error: any Error, wrote: Bool = true) {
        if error is CancellationError { return }
        failure = wrote
            ? "That change could not be saved on this device."
            : "This day stopped updating. Reopen the tab to try again."
    }

    // MARK: - The target

    /// The day's override as the domain sees it, or `nil`. The model's OWN
    /// row rather than the resolver's: a save patches it first, so the sheet
    /// never snaps back for the one hop the observation takes.
    var dayTarget: DailyTarget? { dailyTarget.map(DailyTarget.init) }

    /// Everything the chain reads, with this model's day override.
    private var sources: TargetSources { targets.snapshot.sources(dayTarget: dayTarget) }

    /// The whole chain for the SELECTED date: own numbers → rung on that date
    /// → day override. Water and sleep ride along.
    var resolved: ResolvedTargets { Targets.resolve(sources, date: date, today: today) }

    var hasOverride: Bool { DailyTargets.hasTarget(dayTarget) }
    var tracksCarbs: Bool { DailyTargets.tracksCarbs(dayTarget) }
    var tracksFat: Bool { DailyTargets.tracksFat(dayTarget) }

    /// The user's own five numbers, before any rung. Same shape as the You tab.
    var ownGoals: LeverGoals { sources.own }

    /// The rung in force on the SELECTED date.
    var leverInForce: String? { resolved.leverId }

    /// Non-nil when a rung holds the numbers; `custom` and no selection are nil.
    var heldBy: NutritionLever? { Levers.lever(byId: leverInForce, in: targets.snapshot.ladder) }

    /// The rung's (or pinned history's) numbers for the date, before the override.
    var rungGoals: LeverGoals { Targets.resolve(targets.snapshot.sources(dayTarget: nil), date: date, today: today).goals }

    /// What the day is graded against. Untracked macros resolve to `nil`.
    var target: LeverGoals { resolved.goals }

    /// A zero calorie goal is an unset row, not a fast.
    var targetKcal: Double? { target.calorie > 0 ? target.calorie : nil }

    /// The user's saved profiles first, then the built-ins they have not
    /// replaced.
    var profiles: [TargetProfile] { Targets.profiles(stored: sources.profiles) }

    /// The profile the day's figures actually MATCH — not the stamp.
    var matchedProfile: TargetProfile? {
        TargetProfiles.byKey(profiles, resolved.profileKey)
    }

    /// Where the target came from, in one line.
    var provenance: String {
        if hasOverride {
            if let matched = matchedProfile { return "Day override · \(matched.label)" }
            if let stamped = TargetProfiles.byKey(profiles, dailyTarget?.profileKey) {
                return "Day override · \(stamped.label), edited"
            }
            return "Day override · Custom"
        }
        if let held = heldBy { return "\(held.label) · held by rung" }
        return "My own numbers"
    }

    // MARK: - Eaten

    struct Eaten: Equatable {
        var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
    }

    /// Summed over the day's rows, PLUS what the stack delivered. `nil` when
    /// nothing is logged — never a zero.
    ///
    /// ── WHY THE STACK IS IN HERE AND NOT ONLY IN THE GRID ───────────────────
    /// A powder is food. Five grams of psyllium husk is 17 kcal and 4.4 g of
    /// carbohydrate, and until this fold they reached the nutrient grid (which
    /// reads `stack.nutrients`) and nothing else — so the tab could show the
    /// fibre arriving while the calorie ring pretended the scoop had not
    /// happened. `StackCredit.macros` resolves them from the same doses under
    /// the same credit rule, so the two surfaces cannot disagree.
    ///
    /// ── AND WHY `nil` STILL MEANS WHAT IT MEANT ─────────────────────────────
    /// `entries == nil` is the LOADING state and stays `nil` whatever the stack
    /// says; a supplement total flashed under a ring that has not read the
    /// day's food yet is a wrong number, not an early one. Past that, a day
    /// with no food and a credited dose is no longer "nothing logged" — you
    /// consumed 17 kcal — so it resolves rather than staying blank.
    var eaten: Eaten? {
        // Still loading: whatever the stack says, a supplement total under a
        // ring that has not read the day's food yet is a wrong number.
        guard entries != nil else { return nil }
        let supplements = stack.macros
        guard var sum = eatenFood ?? (supplements.isZero ? nil : Eaten()) else { return nil }
        sum.kcal += supplements.kcal
        sum.protein += supplements.protein
        sum.carbs += supplements.carbs
        sum.fat += supplements.fat
        return sum
    }

    /// The day's FOOD ROWS alone — what `nutrition_entries` holds and what the
    /// edit sheet is allowed to write back.
    ///
    /// Separate from `eaten` because the edit sheet round-trips its own
    /// starting values: seeded from a stack-inclusive total, "Save" would
    /// commit the supplement's calories into a food row, and the next render
    /// would add the same scoop on top of the copy it had just made permanent.
    private var eatenFood: Eaten? {
        guard let entries, !entries.isEmpty else { return nil }
        return entries.reduce(into: Eaten()) { sum, row in
            sum.kcal += row.calories
            sum.protein += row.proteinG
            sum.carbs += row.carbsG
            sum.fat += row.fatG
        }
    }

    /// What is still owed on the day, or `nil` when there is no target to owe
    /// it against. Negative once the day is over.
    func remaining(_ eaten: Double?, _ target: Double?) -> Double? {
        guard let target, target > 0 else { return nil }
        return target - (eaten ?? 0)
    }

    /// The four figures the edit sheet starts from. All four, whatever the day
    /// grades: `nutrition_entries` has no nullable macro column, so correcting
    /// the day means stating all of it — "not graded" is about the scoring, not
    /// about whether the carbohydrate was eaten.
    /// FOOD only — `eatenFood`, never `eaten`. See that property for why a
    /// stack-inclusive seed here would make the supplement permanent.
    var macrosForEditing: MacroMath.Macros {
        let food = eatenFood
        return MacroMath.Macros(
            kcal: food?.kcal ?? 0,
            protein: food?.protein ?? 0,
            carbs: food?.carbs ?? 0,
            fat: food?.fat ?? 0
        )
    }

    /// Everything the day's rows say about micronutrients, summed.
    ///
    /// Fibre and protein keep their own columns; the other nine arrive as the
    /// `micros` JSON bundle the ingest writes. Keyed the way `NutrientTargets`
    /// keys them, which is the way `HealthKey` spells them — one vocabulary from
    /// HealthKit to the grid.
    var nutrients: [String: Double] {
        guard let entries else { return [:] }
        var out: [String: Double] = [:]
        for row in entries {
            out["protein", default: 0] += row.proteinG
            if let fiber = row.fiberG { out["fiber", default: 0] += fiber }
            guard let micros = row.micros,
                  let bundle = try? JSONDecoder().decode([String: Double].self, from: Data(micros.raw.utf8))
            else { continue }
            for (key, value) in bundle { out[key, default: 0] += value }
        }
        return out
    }

    // MARK: - Flags

    var exceptionReason: String? { ExceptionDay.reason(dailyLog?.nutritionException) }
    var isEstimated: Bool { dailyLog?.nutritionEstimated ?? false }

    /// The rung in force, as a chip reads it.
    var leverLabel: String { heldBy?.label ?? "My own numbers" }

    /// The day's SHAPE — a named profile, a hand-made override, or the rung's
    /// ordinary day. The chip states which, so the gauges above it never have to.
    var dayShapeLabel: String {
        if let matched = matchedProfile { return matched.label }
        if hasOverride { return "Custom day" }
        return "Standard day"
    }

    // MARK: - Water

    /// The day's water, by the ONE rule (`WaterTruth`).
    ///
    /// This read `daily_logs.water_ml` alone while `WidgetSnapshotBuilder`
    /// preferred the `water_intake` ledger, so the tab and the tile could print
    /// different litres for the same day and neither was wrong about what it
    /// read. Both call the same function now.
    var waterMl: Double? {
        WaterTruth.ml(log: dailyLog?.waterMl, ledger: water.map(\.amountMl))
    }

    /// What the water row prints.
    ///
    /// ── THE DASH WAS A CLAIM THE ROW COULD NOT MAKE ─────────────────────────
    /// `— / 3.0 L` says the day holds no water. On a day neither store has been
    /// written to, what is true is that nobody has been able to ask yet: the
    /// HealthKit read is pending, or it was denied and will stay pending. The
    /// sentence says which, and it replaces the whole figure rather than sitting
    /// beside it — the goal is not news while the numerator is unknown.
    ///
    /// On the MODEL and not in the row, because `WaterRow` is a `private struct`
    /// inside the tab file and nothing could assert on it. That is why the dash
    /// had no test to fail when it stopped being true (`WaterRowTests`).
    var waterFigures: String {
        if isAwaitingHealthWater { return "Waiting for Apple Health" }
        let amount = waterMl.map { "\(NutritionFormat.litres($0))" } ?? "—"
        guard let goal = waterGoalMl else { return "\(amount) L" }
        return "\(amount) / \(NutritionFormat.litres(goal)) L"
    }

    /// Nothing in either store, on a day the automatic ingest still covers.
    ///
    /// The row says "Waiting for Apple Health" rather than "—" here, because
    /// those are different claims: a dash says the day holds no water, and what
    /// is actually true is that nobody has been able to ask yet — the read is
    /// pending, or it was denied and will stay pending. Bounded to the window
    /// `syncCardioBouts` and `syncRecent` actually scan (today and yesterday),
    /// so a quiet Tuesday last March is not described as still loading.
    var isAwaitingHealthWater: Bool {
        guard waterMl == nil else { return false }
        return date >= NightWindow.previousDay(LogicalDay.today())
    }
    var waterGoalMl: Double? { resolved.waterMl }
    var isWaterManual: Bool { water.contains { ManualEntry.isManualWater($0.hkUuid) } }

    /// The day's macros were entered by hand, so HealthKit will not touch this
    /// date again — including its fibre and micronutrients. A one-way door has
    /// to be visible from the screen it was opened on.
    var isMacrosManual: Bool { entries?.contains { ManualEntry.isManualMacro($0.hkUuid) } ?? false }

    // MARK: - Writing

    /// One failure path for every write. The stream confirms a hop later; the
    /// callers patch the published value first where a snap-back would show.
    @discardableResult
    private func write<T>(_ save: () throws -> T) -> T? {
        do {
            let value = try save()
            failure = nil
            return value
        } catch {
            report(error)
            return nil
        }
    }

    /// The phase to stamp on a hand-entered row — the same resolution the
    /// HealthKit ingest performs, so a flagged day keeps the block's phase.
    func setManualMacros(kcal: Double, protein: Double, carbs: Double, fat: Double) {
        let phase = NutritionPhase.resolve(.init(
            calories: kcal,
            exception: dailyLog?.nutritionException,
            estimated: dailyLog?.nutritionEstimated,
            activePhase: goals?.goalPreset.flatMap(NutritionPhase.init(rawValue:))
        ))?.rawValue
        write {
            try database.setManualMacros(
                userId: userId, date: date,
                calories: kcal, proteinG: protein, carbsG: carbs, fatG: fat, phase: phase
            )
        }
    }

    /// `nil` un-marks the day; the column is named in `clearing` so the server
    /// clears it too rather than keeping "Event".
    func setException(_ reason: String?) {
        let value = ExceptionDay.reason(reason)
        let row = write {
            try database.editDailyLog(
                userId: userId, date: date, clearing: value == nil ? ["nutrition_exception"] : []
            ) { $0.nutritionException = value }
        }
        if let row { dailyLog = row }
    }

    func setEstimated(_ on: Bool) {
        let row = write {
            try database.editDailyLog(userId: userId, date: date) { $0.nutritionEstimated = on }
        }
        if let row { dailyLog = row }
    }

    /// Blank fields stay blank — "no opinion, ask the rung". An empty draft is
    /// a cleared override, not an all-nil row.
    func saveDailyTarget(
        kcal: Double?, protein: Double?, carbs: Double?, fat: Double?, steps: Double?,
        trackCarbs: Bool, trackFat: Bool, note: String?, profileKey: String?
    ) {
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let change: @Sendable (inout DailyTargetRow) -> Void = { row in
            row.kcal = kcal.map { Int($0.rounded()) }
            row.proteinG = protein.map { Int($0.rounded()) }
            row.carbsG = carbs.map { Int($0.rounded()) }
            row.fatG = fat.map { Int($0.rounded()) }
            row.stepsGoal = steps.map { Int($0.rounded()) }
            row.trackCarbs = trackCarbs
            row.trackFat = trackFat
            row.note = trimmedNote?.isEmpty == false ? trimmedNote : nil
            row.profileKey = profileKey
        }
        var local = dailyTarget ?? DailyTargetRow(userId: userId, date: date, updatedAt: Date(), trackCarbs: true, trackFat: true)
        change(&local)
        guard DailyTargets.hasTarget(DailyTarget(local)) else {
            clearDailyTarget()
            return
        }
        dailyTarget = local
        write { try database.setDailyTarget(userId: userId, date: date, change) }
    }

    func clearDailyTarget() {
        dailyTarget = nil
        write { try database.clearDailyTarget(userId: userId, date: date) }
    }

    /// Below `minWaterMl` the day would score as untracked rather than as a
    /// low day, so that is the floor — the honest way to blank a day is
    /// `clearWater`.
    static let minWaterMl: Double = 100

    func setWater(ml: Double) {
        let amount = max(Self.minWaterMl, ml.rounded())
        dailyLog?.waterMl = amount
        write { try database.setWaterOverride(userId: userId, date: date, ml: amount) }
    }

    /// One glass. The tap target on the water row, and the only write on this
    /// tab that takes no sheet — which is the point: logging water is the most
    /// repeated action here and it should cost one tap.
    static let glassMl: Double = 250

    /// ── A TAP ADDS; ONLY THE SHEET REPLACES ─────────────────────────────────
    /// This called `setWater`, which is the OVERRIDE — it replaced the day's
    /// ledger with one row carrying the manual sentinel, and that sentinel makes
    /// every later HealthKit sync decline the date's water without saying so.
    /// So one tap here, on the control the tab is designed around, permanently
    /// stopped Apple Health water from reaching this screen for that day.
    ///
    /// A glass is its own row in the ledger now, and the ingest adds the glasses
    /// to what Apple reports. See `AppDatabase.addWaterGlass`.
    ///
    /// ── THE LOCAL IS THE FIX, AND IT IS NOT A STYLE POINT ───────────────────
    /// This line was `dailyLog?.waterMl = (waterMl ?? 0) + ml`, and it killed
    /// the app on the FIRST tap of any day that already had a `daily_logs` row:
    ///
    ///     Simultaneous accesses to 0x…, but modification requires exclusive
    ///     access. Previous access (a modification) started at
    ///     NutritionModel.dailyLog.modify … Fatal access conflict detected.
    ///
    /// `dailyLog` is a stored property of an `@Observable` class, so it has a
    /// `_modify` accessor — and `a?.b = rhs` has to OPEN that exclusive access
    /// before evaluating `rhs`, because the assignment must short-circuit when
    /// `a` is nil. The right-hand side then called `waterMl`, whose getter
    /// reads `dailyLog` — a read inside an open exclusive modification, which
    /// Swift's dynamic exclusivity checking traps. Not a race: no second tap, no
    /// sheet, no concurrency. On an EMPTY day it survived one tap, because the
    /// optional chain short-circuited before the read — and died on the tap
    /// after the row was minted, which is what identified the mechanism.
    ///
    /// Reading first closes the access before the write opens one. Note the two
    /// siblings below are safe for the same reason and by accident: `setWater`
    /// assigns a local and `clearWater` a literal, so neither reads itself.
    func addWater(_ ml: Double = NutritionModel.glassMl) {
        let total = (waterMl ?? 0) + ml
        dailyLog?.waterMl = total
        write { try database.addWaterGlass(userId: userId, date: date, ml: ml) }
    }

    /// ── NO OPTIMISTIC NIL ───────────────────────────────────────────────────
    /// This assigned `dailyLog?.waterMl = nil` first. That is a claim the store
    /// no longer makes: clearing the override keeps HealthKit's row and the
    /// glasses, and re-derives the column from what is left. Blanking the
    /// published value here would show a day emptied that was not, until the
    /// observation landed and put the figure back — a flicker that reads as the
    /// button having deleted more than it did.
    ///
    /// The other three writers on this tab patch optimistically because their
    /// result is known before the write. This one's is not.
    func clearWater() {
        write { try database.clearWaterOverride(userId: userId, date: date) }
    }
}

// MARK: - Formatting

enum NutritionFormat {
    /// `1,420` — grouped, no decimals. Every kcal and gram figure on the tab.
    static func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// `1.8` — litres to one decimal, which is the precision of the thing.
    static func litres(_ ml: Double) -> String {
        (ml / 1000).formatted(.number.precision(.fractionLength(1)))
    }

    /// `Thu 3 Sep`, in the device's locale.
    static func dayTitle(_ iso: String) -> String {
        guard let date = LogicalDay.date(fromISO: iso) else { return iso }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// `M`, `T`, `W` — the strip's axis. Narrow rather than abbreviated: seven
    /// three-letter labels under seven 20 pt columns is a wall of text, and the
    /// dots are read as a shape, not as a table.
    static func weekdayNarrow(_ iso: String) -> String {
        guard let date = LogicalDay.date(fromISO: iso) else { return "" }
        return date.formatted(.dateTime.weekday(.narrow))
    }

    /// `535 left` or `195 over`. Which side of the target the day is on is the
    /// fact; the sign is how it is spelled, and a bare "−195" makes the reader
    /// do the work.
    static func remaining(_ value: Double, unit: String) -> String {
        value >= 0 ? "\(whole(value)) \(unit) left" : "\(whole(-value)) \(unit) over"
    }
}
