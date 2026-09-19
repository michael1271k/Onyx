import Foundation
import GRDB
import OnyxCore
import os

/// The cascade as one read, N days in memory, one write (W2, decision 17).
///
/// ── WHAT THE OLD PATH COST ──────────────────────────────────────────────────
/// `refreshDailyScore` ran ~fifteen queries per day, five of them over a
/// forty-nine-day window, and the cascade called it up to forty-nine times in
/// forty-nine transactions. That is ~700 queries and 49 commits for one edit
/// three weeks ago — every commit reloading the widgets and waking the watch
/// bridge on the way.
///
/// ── AND WHAT THIS IS NOT ────────────────────────────────────────────────────
/// A second scoring rule. Every number here comes out of the SAME domain
/// functions the per-day path called (`Score.daily`, `Battery.computeBattery`,
/// `Readiness.signals`, `Fatigue.foldRows`, `Maintenance.isMaintenanceDate`,
/// `Context.*`, `DayPlan.resolve`), fed the same rows selected by the same
/// rules. `RescoreParityTests` pins the sixty-day output of this path to the
/// vector the per-day path produced before it was deleted; a row that moves
/// there is a rule that changed, not an optimisation.
///
/// ── THE ONE RULE THAT HAD TO BE RESTATED ────────────────────────────────────
/// The per-day path read "the last six sessions of this day key before the
/// date" and "the last fourteen nights before the date" with `LIMIT`, and the
/// readiness window with a `BETWEEN`. In memory those are slices of one
/// preloaded, ordered array — the same rows in the same order, because the
/// loads below sort exactly as the old queries did and take the same prefix.
struct ScoringWindow {
    let userId: String
    let todayISO: String

    // ── Account-wide, read once ─────────────────────────────────────────────
    let goals: UserGoalRow?
    let schedule: ScheduleContext
    let profiles: [TargetProfileRow]
    let periods: [LeverPeriodRow]
    let ladder: LeverLadder
    let phases: [PhaseDef]
    let dayTargets: [String: DailyTargetRow]

    // ── Dated rows over [first − 48 d, last] ────────────────────────────────
    let metrics: [String: DailyMetricRow]
    /// Every `daily_logs` row dated on or before the window's end, NEWEST
    /// first — `scoringInputs` read `ORDER BY date DESC LIMIT 8` and the
    /// prefix has to be the same prefix.
    let logs: [DailyLogRow]
    /// Every night the user has, in ROWID order — the scan order every one of
    /// the old queries met them in. `ORDER BY duration_min DESC` broke a tie
    /// by that order (SQLite's sorter is stable on scan order), and the
    /// readiness fold had no ORDER BY at all.
    let nights: [SleepSessionRow]
    let nutrition: [String: NutritionEntryRow]
    let waterMl: [String: Double]
    /// Rows, not millilitres: the ghost guard asks whether ANYTHING was
    /// logged, and a 0 ml row is a row.
    let waterRows: [String: Int]
    let supplementCount: [String: Int]
    /// Every session, in rowid order — `hardest` and `dayKey` read the day's
    /// sessions in that order, and `max(by:)` keeps the FIRST of a tie.
    let sessions: [WorkoutSession]
    let setsBySession: [String: [WorkoutSet]]
    let prCount: [String: Int]
    let fatigue: [String: [FatigueRow]]
    let doms: [String: [DomsLogRow]]
    let cardio: [CardioLogRow]

    /// Read everything `dates` can need, in the caller's read transaction.
    static func load(_ db: Database, userId: String, dates: [String], todayISO: String) throws -> ScoringWindow {
        guard let first = dates.first, let last = dates.last else {
            throw DatabaseError(message: "ScoringWindow.load: empty range")
        }
        let user = Column("user_id") == userId
        // The readiness series behind the FIRST day reaches 48 days before it.
        let start = AppDatabase.readinessHistoryStart(first)
        let span = user && Column("date") >= start && Column("date") <= last

        let goals = try UserGoalRow.filter(user).fetchOne(db)
        let schedule = try AppDatabase.scheduleContext(db, userId: userId, goals: .some(goals))
        let profiles = try TargetProfileRow.filter(user).order(Column("sort")).fetchAll(db)
        let periods = try LeverPeriodRow.filter(user).order(Column("starts_on")).fetchAll(db)
        let ladder = try AppDatabase.leverLadder(db, userId: userId, goals: .some(goals))
        let phases = try AppDatabase.planCatalogue(db, userId: userId).phases
        let dayTargets = Dictionary(
            try DailyTargetRow.filter(user && Column("date") >= first && Column("date") <= last).fetchAll(db)
                .map { ($0.date, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // `fetchOne` on a (user, date) filter is the first row the scan finds;
        // keeping the first per date reproduces it.
        let metrics = Dictionary(
            try DailyMetricRow.filter(span).order(Column.rowID).fetchAll(db).map { ($0.date, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let logs = try DailyLogRow.filter(user && Column("date") <= last)
            .order(Column("date").desc, Column.rowID).fetchAll(db)
        let nights = try SleepSessionRow.filter(user).order(Column.rowID).fetchAll(db)
        let nutrition = Dictionary(
            try NutritionEntryRow.filter(span && Column("meal_type") == "daily").order(Column.rowID).fetchAll(db)
                .map { ($0.date, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var waterMl: [String: Double] = [:]
        var waterRows: [String: Int] = [:]
        for row in try WaterIntakeRow.filter(span).fetchAll(db) {
            waterMl[row.date, default: 0] += row.amountMl
            waterRows[row.date, default: 0] += 1
        }
        var supplementCount: [String: Int] = [:]
        for row in try Row.fetchAll(
            db, sql: "SELECT date, count(*) AS n FROM supplement_log WHERE user_id = ? AND date >= ? AND date <= ? GROUP BY date",
            arguments: [userId, start, last]
        ) { supplementCount[row["date"]] = row["n"] }

        // Every session ROW (one per workout, cheap) but only the SETS a day
        // in `dates` can read: its own sessions and the six prior of its day
        // key. Loading every set the user ever logged for one day's score is
        // what the widget extension cannot afford.
        let sessions = try WorkoutSession.filter(user).order(Column.rowID).fetchAll(db)
        var wanted: Set<String> = []
        for date in dates {
            let own = sessions.filter { $0.date == date }
            for s in own { wanted.insert(s.id) }
            guard !own.isEmpty else { continue }
            let dayKey = own.first(where: { $0.dayKey != nil })?.dayKey
            for s in priorSessions(sessions, before: date, dayKey: dayKey) { wanted.insert(s.id) }
        }
        var setsBySession: [String: [WorkoutSet]] = [:]
        if !wanted.isEmpty {
            for set in try WorkoutSet
                .filter(wanted.contains(Column("session_id")))
                .filter(sql: "session_id IN (SELECT id FROM workout_sessions WHERE user_id = ?)", arguments: [userId])
                .order(Column.rowID).fetchAll(db) {
                setsBySession[set.sessionId, default: []].append(set)
            }
        }
        var prCount: [String: Int] = [:]
        for row in try Row.fetchAll(
            db, sql: "SELECT achieved_on AS d, count(*) AS n FROM personal_records WHERE user_id = ? AND achieved_on >= ? AND achieved_on <= ? GROUP BY achieved_on",
            arguments: [userId, first, last]
        ) { prCount[row["d"]] = row["n"] }
        var fatigue: [String: [FatigueRow]] = [:]
        for row in try FatigueLogRow.filter(span).order(Column.rowID).fetchAll(db) {
            fatigue[row.date, default: []].append(FatigueRow(slot: row.slot, level: row.level))
        }
        var doms: [String: [DomsLogRow]] = [:]
        for row in try DomsLogRow.filter(span).order(Column.rowID).fetchAll(db) {
            doms[row.date, default: []].append(row)
        }
        let cardio = try CardioLogRow.filter(span).order(Column.rowID).fetchAll(db)

        return ScoringWindow(
            userId: userId, todayISO: todayISO,
            goals: goals, schedule: schedule, profiles: profiles, periods: periods,
            ladder: ladder, phases: phases, dayTargets: dayTargets,
            metrics: metrics, logs: logs, nights: nights, nutrition: nutrition,
            waterMl: waterMl, waterRows: waterRows, supplementCount: supplementCount,
            sessions: sessions, setsBySession: setsBySession, prCount: prCount,
            fatigue: fatigue, doms: doms, cardio: cardio
        )
    }

    // MARK: - One day, in memory

    /// What one day scores against — `refreshDailyScore`'s `DayPlan` and
    /// `scoringInputs` together, off the preloaded rows.
    ///
    /// `nil` is the ghost guard, unchanged: a past day with nothing under it
    /// gets no row.
    func inputs(
        for date: String, hoursAwake: Double, isToday: Bool, isRestDay: Bool, supplements: ScoringSupplements
    ) -> ScoringInputs? {
        let metrics = metrics[date]
        let sleep = night(for: date)
        let nutrition = nutrition[date]
        let waterMl = waterMl[date] ?? 0
        let supplementCount = supplementCount[date] ?? 0
        let sessions = sessions.filter { $0.date == date }

        // ORDER BY date DESC LIMIT 8, then the day's own row out of the eight.
        let trailingLogs = Array(logs.lazy.filter { $0.date <= date }.prefix(8))
        let todayLog = trailingLogs.first { $0.date == date }
        let trail = trailingLogs.filter { $0.date != date }
        let hrvBaseline = AppDatabase.mean(trail.compactMap(\.hrvMs))
        let rhrBaseline = AppDatabase.mean(trail.compactMap { $0.avgRestHeartRate.map(Double.init) })

        let fatigueLevel = Fatigue.latest(
            Fatigue.foldRows(fatigue[date] ?? [], isTraining: !isRestDay || !sessions.isEmpty)
        )?.level

        let signals = Readiness.signals(readinessHistory(date))
        let domsSeverity = AppDatabase.foldDomsSeverity(doms[date] ?? [])

        let hasAnything = metrics != nil || sleep != nil || nutrition != nil
            || (waterRows[date] ?? 0) > 0 || supplementCount > 0 || !sessions.isEmpty || todayLog != nil
        if !isToday && date != todayISO && !hasAnything { return nil }

        let daySets = sessions.flatMap { setsBySession[$0.id] ?? [] }
        let counted = AppDatabase.countSets(daySets)
        let sessionVolumeKg = AppDatabase.volume(daySets)
        let prCount = prCount[date] ?? 0

        let hardest = sessions.max { ($0.durationMin ?? 0) < ($1.durationMin ?? 0) }
        let dayKey = sessions.first(where: { $0.dayKey != nil })?.dayKey

        var trailingAvgVolumeKg = 0.0
        if !sessions.isEmpty {
            let prior = Self.priorSessions(self.sessions, before: date, dayKey: dayKey)
            let candidates = prior
                .map { (date: $0.date, volume: AppDatabase.volume(setsBySession[$0.id] ?? [])) }
                .filter { $0.volume > 0 }
            let fullEffort = candidates.filter {
                !Maintenance.isMaintenanceDate($0.date, today: todayISO, ladder: ladder, phases: phases)
            }
            let trailing = (fullEffort.isEmpty ? candidates : fullEffort).map(\.volume)
            trailingAvgVolumeKg = trailing.isEmpty ? 0 : trailing.reduce(0, +) / Double(trailing.count)
        }

        let stamped = Context.fromDayLabel(todayLog?.nutritionException)
        let setting = Context.fromSetting(goals?.contextMode)
        let effectiveMode: ContextMode = stamped != .normal
            ? stamped
            : Context.rangeCovers(setting, since: goals?.contextSince, date: date, today: todayISO) ? setting : .normal

        let g = goals
        let resolved = supplements.goals ?? ResolvedGoals(
            calorie: Double(g?.calorieGoal ?? 0),
            protein: Double(g?.proteinGoalG ?? 0),
            carbs: Double(g?.carbsGoalG ?? 0),
            fat: Double(g?.fatGoalG ?? 0),
            steps: Double(g?.stepsGoal ?? 0)
        )

        var inputs = ScoringInputs()
        inputs.sleepHours = sleep.map { Double($0.durationMin) / 60 } ?? 0
        inputs.deepMinutes = Double(sleep?.deepMin ?? 0)
        inputs.remMinutes = Double(sleep?.remMin ?? 0)
        inputs.sleepGoalHours = g?.sleepGoalHours ?? 8
        if let sleep, let window = NightWindow.range(date) {
            let inBed = sleep.endTime.timeIntervalSince(sleep.startTime) / 3600
            inputs.sleepInBedHours = inBed > 0 ? inBed : nil
            let latency = sleep.onsetTime.map { max(0, $0.timeIntervalSince(sleep.startTime) / 60) }
            inputs.sleepLatencyMin = latency
            inputs.sleepAwakeMin = sleep.awakeMin.map { max(0, Double($0) - (latency ?? 0)) }
            inputs.sleepAwakenings = sleep.awakenings.map(Double.init)
            let usual = AppDatabase.median(bedtimeOffsets(before: date, limit: 14))
            inputs.sleepBedtimeDeltaMin = usual.map { sleep.startTime.timeIntervalSince(window.from) / 60 - $0 }
        }

        inputs.calories = nutrition?.calories ?? 0
        inputs.proteinG = nutrition?.proteinG ?? 0
        inputs.carbsG = nutrition?.carbsG ?? 0
        inputs.fatG = nutrition?.fatG ?? 0
        inputs.calorieGoal = resolved.calorie
        inputs.proteinGoalG = resolved.protein
        inputs.carbsGoalG = resolved.carbs
        inputs.fatGoalG = resolved.fat
        inputs.nutritionException = effectiveMode != .normal
            || ExceptionDay.isException(todayLog?.nutritionException)

        inputs.steps = Double(metrics?.steps ?? 0)
        inputs.activeCal = Double(metrics?.activeCal ?? 0)
        inputs.stepsGoal = resolved.steps
        inputs.activeCalGoal = Double(g?.activeCalGoal ?? 0)

        inputs.workoutLogged = !sessions.isEmpty
        inputs.isRestDay = isRestDay
        inputs.newPRsToday = Double(prCount)
        inputs.sessionVolumeKg = sessionVolumeKg
        inputs.trailingAvgVolumeKg = trailingAvgVolumeKg
        inputs.sessionRpe = hardest?.sessionRpe
        inputs.sessionDayKey = hardest?.dayKey ?? dayKey
        inputs.isMaintenance = supplements.isMaintenance
        inputs.plannedExercises = supplements.plannedExercises
        inputs.plannedSets = supplements.plannedSets.map { max(0, $0 - Double(counted.ghostSets)) }
        inputs.loggedExercises = Double(counted.exercises)
        inputs.sessionSets = Double(counted.workingSets)
        inputs.failureSets = Double(counted.failureSets)

        inputs.waterMl = waterMl
        inputs.waterGoalMl = Double(g?.waterGoalMl ?? 0)

        inputs.restingHR = metrics?.restHr.map(Double.init)
            ?? todayLog?.avgRestHeartRate.map(Double.init)
        inputs.baselineHR = rhrBaseline
        inputs.hrvMs = todayLog?.hrvMs
        inputs.hrvBaseline = hrvBaseline
        inputs.sleepOnsetTrouble = todayLog?.sleepOnsetTrouble == true
        inputs.fatigueLevel = fatigueLevel.map(Double.init)
        inputs.hrvZ = signals.hrv.z
        inputs.rhrZ = signals.rhr.z
        inputs.acwr = signals.load.acwr
        inputs.strainZ = signals.load.strainZ
        inputs.domsSeverity = domsSeverity

        inputs.contextMode = Context.scoringContext(for: effectiveMode).rawValue
        inputs.isCurrentDay = isToday || date == todayISO
        inputs.hoursAwake = hoursAwake
        inputs.localHour = min(23, 7 + hoursAwake.rounded())
        return inputs
    }

    /// `WHERE user_id = ? AND date < ? [AND day_key = ?] ORDER BY date DESC
    /// LIMIT 6`, which SQLite answers by walking the `date` index BACKWARDS —
    /// so two sessions on one date come out newest-rowid first. `sorted` is
    /// stable, so reversing the rowid-ordered array first reproduces that tie
    /// order. It matters exactly once: a double-session day sitting on the
    /// six-session boundary, which the parity vector's last day is.
    static func priorSessions(_ sessions: [WorkoutSession], before date: String, dayKey: String?) -> [WorkoutSession] {
        var prior = sessions.filter { $0.date < date }
        if let dayKey { prior = prior.filter { $0.dayKey == dayKey } }
        return Array(prior.reversed().sorted { $0.date > $1.date }.prefix(6))
    }

    /// What `date` is graded against — the plan the athlete is running and
    /// the lever in force — resolved the way the widget resolves it.
    func plan(for date: String) -> DayPlan {
        DayPlan.resolve(
            goals: goals, schedule: schedule, profiles: profiles, periods: periods,
            dayTarget: dayTargets[date], date: date, todayISO: todayISO
        )
    }

    /// The night that ends on `date`'s morning: longest in the window, first
    /// in rowid order on a tie — `ORDER BY duration_min DESC LIMIT 1` over a
    /// table scan, which is what the old query was.
    private func night(for date: String) -> SleepSessionRow? {
        guard let window = NightWindow.range(date) else { return nil }
        var best: SleepSessionRow?
        for n in nights where n.startTime >= window.from && n.startTime < window.to {
            if let held = best, held.durationMin >= n.durationMin { continue }
            best = n
        }
        return best
    }

    /// `AppDatabase.bedtimeOffsets(before:limit:)` over the preloaded nights:
    /// `ORDER BY start_time DESC LIMIT 14`, ties in scan (rowid) order —
    /// `sorted` is stable over the rowid-ordered array.
    private func bedtimeOffsets(before date: String, limit: Int) -> [Double] {
        guard let window = NightWindow.range(date) else { return [] }
        return nights
            .filter { $0.startTime < window.from }
            .sorted { $0.startTime > $1.startTime }
            .prefix(limit)
            .compactMap { row in
                NightWindow.range(NightWindow.nightOf(row.startTime)).map { row.startTime.timeIntervalSince($0.from) / 60 }
            }
    }

    /// The 49-day series behind `date`, from the preloaded rows — the same
    /// assembly `AppDatabase.readinessHistory(_:userId:date:)` does over one
    /// query per table.
    func readinessHistory(_ date: String) -> ReadinessHistory {
        let dates = AppDatabase.readinessHistoryDates(date)
        let start = dates.first ?? date
        let inWindow = { (d: String) in d >= start && d <= date }
        return AppDatabase.readinessHistory(
            dates: dates,
            logs: logs.filter { inWindow($0.date) },
            metrics: metrics.values.filter { inWindow($0.date) },
            sessions: sessions.filter { inWindow($0.date) },
            cardio: cardio.filter { inWindow($0.date) },
            nights: nights
        )
    }
}

// MARK: - The door

public extension AppDatabase {

    private static let signposter = OSSignposter(subsystem: "app.onyx.perf", category: "rescore")

    /// Score every day in `dates` — one read, one compute, one write.
    ///
    /// `force` is the cascade's word: a sealed past day is rewritten. Without
    /// it a finalized row is left alone (`THE FREEZE` in `DailyScoreStore`),
    /// which is what the sync's "today and yesterday" refresh wants.
    ///
    /// Returns the rows written, by date. A day with nothing under it writes
    /// nothing and is absent, as before.
    @discardableResult
    func rescoreWindow(
        userId: String,
        dates: [String],
        now: Date = Date(),
        calendar: Calendar = .current,
        force: Bool = false
    ) throws -> [String: DailyScoreRow] {
        guard !dates.isEmpty else { return [:] }
        let state = Self.signposter.beginInterval("rescore.run", id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval("rescore.run", state) }

        let todayISO = LogicalDayISO.string(now, calendar: calendar)
        let window = try writer.read { db in
            try ScoringWindow.load(db, userId: userId, dates: dates, todayISO: todayISO)
        }

        struct Computed {
            var date: String
            var isToday: Bool
            var parts: ScoreComponents
            var batteryPct: Int
        }
        var computed: [Computed] = []
        for date in dates {
            let isToday = date == todayISO
            let hoursAwake = isToday ? Battery.hoursAwake(at: now, calendar: calendar) : Battery.defaults.maxAwake
            let plan = window.plan(for: date)
            guard let inputs = window.inputs(
                for: date, hoursAwake: hoursAwake, isToday: isToday,
                isRestDay: !plan.isTraining, supplements: plan.supplements
            ) else { continue }
            let parts = Score.daily(inputs)
            guard let total = parts.totalScore else { continue }
            func i(_ v: Double?) -> Int? { v.map { Int($0.rounded()) } }
            let battery = Battery.computeBattery(inputs, hoursAwake: hoursAwake)
            computed.append(Computed(
                date: date, isToday: isToday,
                parts: ScoreComponents(
                    total: Int(total.rounded()), sleep: i(parts.sleepScore), nutrition: i(parts.nutritionScore),
                    activity: i(parts.activityScore), workout: i(parts.workoutScore), recovery: i(parts.recoveryScore)
                ),
                batteryPct: Int(battery.currentPct.rounded())
            ))
        }
        guard !computed.isEmpty else { return [:] }

        return try writer.write { db in
            let existing = Dictionary(
                try DailyScoreRow
                    .filter(Column("user_id") == userId && dates.contains(Column("date")))
                    .fetchAll(db).map { ($0.date, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var written: [String: DailyScoreRow] = [:]
            for day in computed {
                if let row = try Self.upsertDailyScore(
                    db, userId: userId, date: day.date, existing: existing[day.date],
                    parts: day.parts, batteryPct: day.batteryPct, isToday: day.isToday, force: force, now: now
                ) {
                    written[day.date] = row
                }
            }
            return written
        }
    }
}
