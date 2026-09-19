import Foundation
import GRDB
import OnyxCore

/// Builds the widget payload from the local store — the port of the deleted
/// `GET /api/widget/snapshot` route onto the App Group GRDB file.
///
/// ── WHAT CHANGED AND WHAT DID NOT ────────────────────────────────────────────
/// The route's bearer token, timezone query and edge cache are gone: the
/// extension opens the file `AppDatabase.readOnly(folderURL:)` and asks the
/// store whose data it is (`knownUserId`). Every derivation is the same code
/// the route called — `WidgetDerive`, `Schedule`, `Levers`, `Score`, `Battery`
/// — so a tile and the app can never disagree about a number.
///
/// Every field stays optional where the route returned null. Nil renders as
/// "—"; an invented zero renders as a lie.
public struct WidgetSnapshotBuilder: Sendable {
    public let database: AppDatabase
    public let userId: String
    public let timeZone: TimeZone

    public init(database: AppDatabase, userId: String, timeZone: TimeZone = .current) {
        self.database = database
        self.userId = userId
        self.timeZone = timeZone
    }

    // The route's windows, unchanged.
    static let volumeWeeks = 8
    static let calendarDays = Streak.windowDays
    static let trendDays = 7
    static let vitalsBaselineDays = 14
    static let performanceHistoryDays = 35
    static let ledgerLimit = 40
    /// How far the Body tile's deltas reach back.
    static let bodyCompDays = 30
    /// How many days the fatigue stack draws.
    static let batteryStackDays = 14
    /// How many days of signed energy balance the Deficit face draws (W6).
    /// Seven and not the ledger's eight weeks: the face is a week of days, and
    /// the eight weeks are still carried whole beside it in `deficit`.
    static let deficitDayCount = 7
    /// How many days the Week Rings tile draws, and how many the stress
    /// sparkline does. Seven is a week; fourteen is what `StressSeries`
    /// already builds everywhere else, and a second window here would be a
    /// second answer to "the fortnight".
    static let weekRingDays = 7
    static let stressSeriesDays = 14

    /// One session with the figures the route read off `workout_sessions`
    /// columns; the local table has none, so they come from the sets.
    struct SessionTotals {
        let session: WorkoutSession
        let volumeKg: Double
        let sets: Int
        let prs: Int
        var date: String { session.date }
    }

    struct Rows {
        var goals: UserGoalRow?
        /// The plan, phase, overrides, layout AND the catalogue — one assembly
        /// (`AppDatabase.scheduleContext`), so the widget, the feed and the
        /// watch cannot resolve the plan differently.
        var schedule: ScheduleContext
        var overrides: [String: String] { schedule.overrides }
        var layout: DayLayout { schedule.layout }
        /// `target_profiles` and `lever_periods`, for the rung in force.
        var profiles: [TargetProfileRow]
        var periods: [LeverPeriodRow]
        var dayTarget: DailyTargetRow?
        var storedScore: DailyScoreRow?
        var logs: [DailyLogRow]
        var metrics: [DailyMetricRow]
        var sleep: [SleepSessionRow]
        var nutrition: [NutritionEntryRow]
        var water: [WaterIntakeRow]
        var weights: [BodyCompositionRow]
        var sessions: [SessionTotals]
        var sets: [WorkoutSet]
        var exerciseNames: [String: String]
        var ledger: [PersonalRecordRow]
        var cardio: [CardioLogRow]
        // ── The W12 window ──────────────────────────────────────────────────
        // Eight weeks of logs and meals, read SEPARATELY from `logs` and
        // `nutrition` rather than by widening those. `vitalsSlice` reads every
        // row it is handed to build a fortnight's baseline, so widening the
        // shared array would silently re-baseline every vital on the Home
        // Screen against two months. Two extra reads of ~56 small rows is the
        // cheaper mistake.
        var ledgerLogs: [DailyLogRow]
        var ledgerNutrition: [NutritionEntryRow]
        /// This phase's per-muscle set targets, keyed by `LandmarkMuscle.rawValue`
        /// — the `plan_phase_volume` rows. The tile grades against these, which
        /// is what makes it the same reading as the sheet it opens.
        var phaseVolume: [String: Int]
        /// The phase's own rate band and target weight — the `plan_phase_goals`
        /// row. No compiled fallback since W2: no row, no destination.
        var phaseGoals: PlanPhaseGoalRow?
        /// TODAY's soreness ratings — what the Soreness tile paints.
        var doms: [DomsLogRow]
        /// Minutes past each night window's UTC noon for the fortnight BEFORE
        /// tonight, newest first — `bedtimeOffsets`, the same array the
        /// regularity term takes its median of. Read here rather than
        /// separately so the tile's "usual bedtime" and the score's baseline
        /// can never be two different fortnights.
        var bedtimeOffsets: [Double]
    }

    public func build(scope: OnyxScope, now: Date = Date()) throws -> OnyxSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = LogicalDay.iso(now, calendar: calendar)

        let wantsLifestyle = scope == .lifestyle || scope == .full
        let wantsPerformance = scope == .performance || scope == .full
        let wantsTraining = scope == .training || scope == .full
        let wantsBody = scope == .body || scope == .full

        let trendFrom = ISODate.addDays(date, -(Self.trendDays - 1)) ?? date
        let rows = try fetch(date: date, trendFrom: trendFrom)
        let goals = rows.goals

        let weekStartDay = Week.startDay(fromEndDay: goals?.weekEndDay)
        let week = WeekWindow(containing: date, startDay: weekStartDay, today: date)
        let weekStart = week.start
        let prevWeekStart = ISODate.addDays(weekStart, -7) ?? weekStart

        // ── The plan the user is ACTUALLY running ─────────────────────────
        // Stored layout and overrides, never a default plan (see the
        // "Server-side plan resolution" rule): a widget that guesses from the
        // weekday announces the wrong session after every swap.
        let schedule = rows.schedule
        let programId = schedule.programId
        let program = Schedule.programForContext(schedule, date).program
        func prescribed(_ dayKey: String?) -> (exercises: Int, sets: Int)? {
            guard let dayKey, let day = program.day(key: dayKey) else { return nil }
            return (day.exercises(for: schedule.phase).count, max(1, day.plannedSets(for: schedule.phase)))
        }
        // The deck's muscles in deck order, each named once — what the Today
        // tile washes itself with (W6). The PLAN's movements and not the
        // session's sets: the wash is what the day is ABOUT, and it has to be
        // right at 07:00 on a day nothing has been logged on. `primary` only,
        // and no credit arithmetic — this reaches no accumulator, it picks two
        // hues (`MuscleMap.cardioMovers`' header states the same boundary).
        func deckMuscles(_ dayKey: String?) -> [String]? {
            guard let dayKey, let day = program.day(key: dayKey) else { return nil }
            var out: [LandmarkMuscle] = []
            for exercise in day.exercises(for: schedule.phase) {
                for muscle in MuscleMap.primaryLandmarks(exercise.name) where !out.contains(muscle) {
                    out.append(muscle)
                }
            }
            return out.isEmpty ? nil : out.map(\.rawValue)
        }

        // ── The targets this day is graded against ────────────────────────
        //
        // Hoisted since W4: the Week Rings tile grades six PAST days as well
        // as today, and each of those has its own lever rung and its own
        // context. Only today's `daily_targets` row is loaded, so a past day
        // resolves off the ladder — which is what `batteryStackSlice` already
        // does for the same reason (`dayTarget: d == date ? … : nil`).
        let targets = TargetSnapshot(
            goals: goals, dailyTargets: rows.dayTarget.map { [$0.date: $0] } ?? [:], profiles: rows.profiles,
            overrides: rows.overrides, periods: rows.periods, schedule: schedule
        )
        let resolved = targets.targets(for: date, today: date)
        let resolvedGoals = resolved.goals

        // ── Today, picked out of the week ─────────────────────────────────
        let log = rows.logs.first { $0.date == date }
        let metrics = rows.metrics.first { $0.date == date }
        let water = rows.water.filter { $0.date == date }
        let nutri = rows.nutrition.first { $0.date == date }
        // Ordered by duration descending, so the first row inside tonight's
        // window is the longest — the one the detail face wants.
        let sleep = rows.sleep.first { Night.nightOf(Self.iso($0.startTime)) == date }

        let allSessions = rows.sessions
        let weekSessions = allSessions.filter { $0.date >= weekStart }
        let prevSessions = allSessions.filter { $0.date >= prevWeekStart && $0.date < weekStart }
        let todaySessions = allSessions.filter { $0.date == date }

        // Weigh-ins de-duplicated by VALUE, so a re-synced identical reading
        // is not a fresh weigh-in.
        let weighIns = rows.weights.compactMap { r in Format.validWeight(r.weightKg).map { (date: r.date, kg: $0) } }
        let latest = weighIns.first
        let previous = weighIns.first { r in latest.map { abs(r.kg - $0.kg) >= 0.05 } ?? false }
        let weightSeries = WidgetDerive.trendPoints(weighIns.map { DatedValue(date: $0.date, value: $0.kg) }, limit: 14)

        let day = Schedule.scheduleDayIn(schedule, date)
        let isTraining = Schedule.isTrainingDayIn(schedule, date)
        let planned = prescribed(day?.dayKey)

        // The last time THIS split was trained. Today's own session excluded:
        // comparing a session to itself is not a target.
        let lastVolumeKg: Double? = day?.dayKey.flatMap { key in
            allSessions.filter { $0.session.dayKey == key && $0.date < date }
                .max { $0.date < $1.date }
                .map { $0.volumeKg.rounded() }
        }

        // ── Keep the score honest before answering ────────────────────────
        // `battery_pct` decays with hours awake, so the mirrored row is wrong
        // within an hour of being written. Recomputed here, today only, off
        // the same inputs the app scores with; the stored row is the fallback.
        let hoursAwake = Battery.hoursAwake(at: now, calendar: calendar)
        let live = try liveScore(
            date: date, hoursAwake: hoursAwake, isRestDay: !isTraining,
            todaySessions: todaySessions, allSessions: allSessions,
            goals: goals, resolvedGoals: resolvedGoals,
            schedule: schedule, ladder: TargetSnapshot(goals: goals, profiles: rows.profiles, periods: rows.periods, schedule: schedule).ladder,
            prescribed: prescribed
        )
        let stored = rows.storedScore
        let battery = live?.battery ?? stored?.batteryPct
        let score = live?.total ?? stored?.score
        let scores = OnyxSnapshot.Scores(
            sleep: live?.components.sleepScore ?? stored?.sleepScore.map(Double.init),
            nutrition: live?.components.nutritionScore ?? stored?.nutritionScore.map(Double.init),
            activity: live?.components.activityScore ?? stored?.activityScore.map(Double.init),
            workout: live?.components.workoutScore ?? stored?.workoutScore.map(Double.init),
            recovery: live?.components.recoveryScore ?? stored?.recoveryScore.map(Double.init)
        )

        // ── The calendar ──────────────────────────────────────────────────
        // Union of the streak's trailing window and the current month, so a
        // month grid has its back half and the streak keeps its 42 days.
        let trailingStart = ISODate.addDays(date, -(Self.calendarDays - 1)) ?? date
        let windowStart = min(ISODate.monthStart(date), trailingStart)
        let windowEnd = max(ISODate.lastDayOfMonth(date), date)
        var calendarWindow: [String] = []
        var d = windowStart
        while d <= windowEnd { calendarWindow.append(d); d = ISODate.addDays(d, 1) ?? windowEnd + "z" }
        let calendarSessions = allSessions.map { CalendarSession(date: $0.date, volumeKg: $0.volumeKg) }
        let calendarGrid = WidgetDerive.calendarDays(calendarWindow, sessions: calendarSessions) { iso in
            let sd = Schedule.scheduleDayIn(schedule, iso)
            return ScheduledDay(dayKey: sd?.dayKey, scheduled: Schedule.isTrainingDayIn(schedule, iso), label: sd?.label)
        }

        // Two sessions in a day sum for tonnage and counts; RPE and duration
        // take the longer one, because averaging two efforts describes neither.
        let longest = todaySessions.max { ($0.session.durationMin ?? 0) < ($1.session.durationMin ?? 0) }

        let context: OnyxSnapshot.DayContext? = {
            let mode = Context.fromDayLabel(log?.nutritionException)
            guard mode != .normal, let meta = Context.meta[mode] else { return nil }
            return OnyxSnapshot.DayContext(mode: mode.rawValue, label: meta.label)
        }()

        let streak = Streak.programDayCount(date, startISO: schedule.planStartISO)

        // ── The scoped slices ─────────────────────────────────────────────
        let stepsTrend: [OnyxSnapshot.Point]? = wantsLifestyle ? Self.points(stepsTrend(rows, date: date)) : nil
        let vitals: OnyxSnapshot.Vitals? = wantsLifestyle ? vitalsSlice(rows.logs, date: date) : nil
        let performance = wantsPerformance ? performanceSlice(rows, date: date, weekStart: weekStart) : nil
        let volumeTrend: [OnyxSnapshot.Point]? = wantsTraining || wantsPerformance
            ? Self.points(WidgetDerive.weeklyVolume(calendarSessions, weekStartOfDate: { Week.start(of: $0, startDay: weekStartDay) }, limit: Self.volumeWeeks))
            : nil
        let cardio: OnyxSnapshot.Cardio? = wantsTraining ? cardioSlice(rows.cardio, date: date, weekStart: weekStart) : nil
        let body: OnyxSnapshot.Body? = wantsBody ? bodySlice(rows.weights) : nil
        let readiness: OnyxSnapshot.Readiness? = {
            guard wantsBody, let battery else { return nil }
            let r = Readiness.compute(sleepScore: scores.sleep, recoveryScore: scores.recovery, batteryPct: Double(battery))
            return OnyxSnapshot.Readiness(level: r.level.rawValue, label: r.label, color: r.color, reason: r.reason)
        }()

        // ── The W12 series ────────────────────────────────────────────────
        // Each is the whole output of one `OnyxCore/Charts` builder. The tile
        // draws it and the app's Today grid draws the same object, so a face on
        // the Home Screen and a face in the app cannot report different weeks.
        let historyStart = ISODate.addDays(weekStart, -7 * (Self.volumeWeeks - 1)) ?? weekStart
        let consistency: Consistency? = wantsTraining
            ? ConsistencySeries.build(
                consistencyDays(from: historyStart, to: date, schedule: schedule, sessions: allSessions),
                endingOn: date, weeks: Self.volumeWeeks, startDay: weekStartDay
            )
            : nil
        let ledgerWindow = wantsLifestyle ? ledgerDays(rows) : []
        let deficit: DeficitLedger? = wantsLifestyle
            ? DeficitLedgerSeries.build(
                ledgerWindow, endingOn: date, weeks: Self.volumeWeeks, startDay: weekStartDay
            )
            : nil
        // The same window's last seven days, one signed balance each — the W6
        // Deficit face's diverging bars. `dayBalanceKcal` is the ledger's own
        // rule, so the bars and the weekly reconciliation above them cannot
        // disagree about what a day came to. A day with no ROW at all still
        // gets a bar position with a nil value: seven bars, always, or the
        // weekday under bar four stops naming bar four.
        let deficitDays: [OnyxSnapshot.DayBalance]? = wantsLifestyle
            ? {
                let byDate = Dictionary(
                    ledgerWindow.map { ($0.date, DeficitLedgerSeries.dayBalanceKcal($0)) },
                    uniquingKeysWith: { _, last in last }
                )
                return (0..<Self.deficitDayCount).reversed().map { back in
                    let d = ISODate.addDays(date, -back) ?? date
                    return OnyxSnapshot.DayBalance(d: d, kcal: byDate[d] ?? nil)
                }
            }()
            : nil
        // ── ONE SET OF READINGS ─────────────────────────────────────────
        // `BodyVitals.readings` is what Pulse, Body trends and the History
        // capsules already merge: `daily_logs` first, the deliberate weigh-in
        // ledger over the top. The Weight face's own `trend` reads the ledger
        // alone, which is right for a face that says "what the scale said" and
        // wrong for a REGRESSION — a month of Health-synced mornings is most of
        // the line, and fitting without them is a rate computed from a third of
        // the data. Both series come from here so the tile, the Goal Board row
        // and the Body screens cannot report three different rates.
        //
        // ── AND THE WINDOW IS THE LEDGER'S, NOT "THE LAST 30 ROWS" ──────
        // `rows.weights` is `limit(30)` with no date bound, because the Weight
        // face needs the latest reading however old it is. A REGRESSION fitted
        // over the same rows is a different thing: weigh-ins are sparse by
        // protocol — every second or third morning, none on a trip — so thirty
        // scans can reach back six months and straddle two phases. Least
        // squares gives those distant points enormous leverage, and the rate,
        // the pace verdict and the ETA that come out of it print on the Today
        // Goal Board row AND the Trajectory tile: one number, consistently
        // wrong, which is worse than two that disagree.
        //
        // `TodayFeedBuilder` bounded its own fit to 28 days for exactly this
        // reason before W12 rebound it here. The bound is `historyStart` now —
        // the same eight weeks `ledgerLogs`, the deficit ledger and the
        // consistency grid already walk — so every W12 series reads one window.
        let bodyReadings = wantsBody
            ? BodyVitals.readings(ledger: rows.weights, logs: rows.ledgerLogs).filter { $0.date >= historyStart }
            : []
        let trajectory: Trajectory? = wantsBody
            ? {
                let phaseGoals = rows.phaseGoals.map(PhaseGoals.init)
                return TrajectorySeries.build(
                    bodyReadings.map { GoalBoard.Reading(date: $0.date, weightKg: $0.weight) },
                    today: date,
                    targetWeightKg: phaseGoals?.targetWeightKg,
                    rateMinKgWk: phaseGoals?.rateMinKgWk,
                    rateMaxKgWk: phaseGoals?.rateMaxKgWk,
                    energy: ledgerDays(rows).filter { $0.date >= weekStart }.map {
                        GoalBoard.EnergyDay(
                            date: $0.date, intakeKcal: $0.intakeKcal,
                            tdeeKcal: Energy.tdee(bmr: $0.bmrKcal, active: $0.activeKcal, intakeKcal: $0.intakeKcal)
                        )
                    }
                )
            }()
            : nil
        let batteryStack: [BatteryStackDay]? = wantsBody
            ? try batteryStackSlice(rows, date: date, now: now, calendar: calendar)
            : nil
        // ── The W7 sentence ───────────────────────────────────────────────
        //
        // ── AND WHY IT IS `.full` AND NOT `wantsBody` ─────────────────────
        // Only the Mega tile draws it, `.daily` is a dashboard tile, and the
        // Today grid is the one caller that builds at `.full`. Gating on
        // `wantsBody` would also catch `scope == .body` — a Home Screen family
        // — and make the widget EXTENSION pay a 49-day `readinessHistory`
        // (five table scans), a plan resolution and a training-day read on
        // every timeline refresh, for a string no Home Screen face renders, in
        // the process with the tightest memory and time budget in the app.
        // Widen this the day a widget draws the sentence, not before.
        //
        // `stressInputs` is the one read that carries BOTH remaining
        // dimensions — it already folds `Readiness.signals` for the ACWR and
        // the day's own rows for the index — and it is handed `rows.schedule`
        // so a context `fetch` has already resolved is not resolved twice.
        //
        // The debt comes off `ledgerLogs`, which the ledger and the
        // consistency grid have already read: eight weeks of `daily_logs`,
        // narrowed here to the bank's own fortnight. No read of its own.
        let coach: String? = scope == .full ? {
            let stress = try? database.writer.read { db in
                try AppDatabase.stressInputs(db, userId: userId, date: date, schedule: rows.schedule)
            }
            // ── NO GOAL, NO DEBT ────────────────────────────────────────────
            // Not `?? 8`. The sleep ARC on this same tile draws against
            // `sleep.goalMin`, which is nil when the athlete has set no goal
            // (see the `sleep:` block below) — so an assumed eight hours here
            // would put a ring with no target and no progress directly above a
            // sentence claiming three hours of debt against one. Debt is a
            // shortfall, and a shortfall needs something to fall short OF.
            let bank: SleepDebt? = goals?.sleepGoalHours.map { goalHours in
                let debtFrom = ISODate.addDays(date, -(SleepDebt.windowDays - 1)) ?? date
                return SleepDebt.compute(
                    nights: rows.ledgerLogs
                        .filter { $0.date >= debtFrom && $0.date <= date }
                        .map { SleepDebtNight(date: $0.date, sleepMinutes: $0.sleepMinutes.map(Double.init)) },
                    goalHours: goalHours,
                    weekAgo: ISODate.addDays(date, -7) ?? date
                )
            }
            return CoachSentence.sentence(CoachSentence.Inputs(
                batteryPct: battery.map(Double.init),
                acwr: stress?.acwr,
                stress: stress.flatMap { Stress.breakdown($0).band },
                // `SleepDebt.minimumNights` and not a 3 spelled here: Pulse's
                // gauge applies the same floor, and one short night out of one
                // is not a bank on either surface.
                sleepDebtHours: bank.flatMap { $0.nights >= SleepDebt.minimumNights ? $0.debtHours : nil }
            ))
        }() : nil

        // ── The sprint's W4 faces ─────────────────────────────────────────
        //
        // `.full` and `.body` — the two scopes that already resolve the day's
        // score, so the reads these add sit beside reads that have happened
        // anyway rather than on top of a lifestyle refresh.
        let weekRings: [OnyxSnapshot.WeekRingDay]? = wantsBody
            ? weekRingsSlice(rows, date: date, targets: targets, sessions: allSessions)
            : nil
        let soreness: [OnyxSnapshot.SorenessRegion]? = wantsBody
            ? Self.sorenessRegions(rows.doms)
            : nil
        // ponytail: `stressSeries` is fourteen `readinessHistory` reads, the
        // same cost `batteryStackSlice` above already pays for its fourteen
        // `scoringInputs`. The documented upgrade is the one
        // `StressInputsBuilder`'s own header names — `daily_scores.stress_index`
        // written by the scorer — not a cache here.
        let stress: OnyxSnapshot.StressFace? = wantsBody
            ? {
                let series = (try? database.stressSeries(userId: userId, endingOn: date, limit: Self.stressSeriesDays)) ?? []
                return OnyxSnapshot.StressFace(index: series.last { $0.d == date }?.index, series14: series)
            }()
            : nil

        let bodyComp: [BodyCompMetric]? = wantsBody
            ? BodyCompSeries.build(
                bodyReadings.map {
                    BodyCompReadingIn(
                        date: $0.date, weightKg: $0.weight, fatPct: $0.fatPct,
                        skeletalMuscleKg: $0.skeletalMuscle, leanSoftTissueKg: $0.leanSoftTissue,
                        fatFreeMassKg: $0.fatFreeMass
                    )
                },
                endingOn: date, days: Self.bodyCompDays
            )
            : nil

        return OnyxSnapshot(
            date: date,
            generatedAt: Self.iso(now),
            scope: scope.rawValue,
            battery: battery,
            score: score,
            sleep: OnyxSnapshot.Sleep(
                minutes: sleep?.durationMin ?? log?.sleepMinutes,
                deepMin: sleep?.deepMin, remMin: sleep?.remMin, coreMin: sleep?.coreMin, awakeMin: sleep?.awakeMin,
                score: sleep?.sleepScore,
                startTime: sleep.map { Self.iso($0.startTime) },
                endTime: sleep.map { Self.iso($0.endTime) },
                goalMin: goals?.sleepGoalHours.map { Int(($0 * 60).rounded()) },
                // Seven nights bucketed by `nightOf`, never by the start date.
                trend: wantsBody ? Self.points(WidgetDerive.dailySeries(
                    rows.sleep.map { DatedValue(date: Night.nightOf(Self.iso($0.startTime)), value: Double($0.durationMin)) },
                    limit: Self.trendDays, combine: .max
                )) : nil,
                // Unscoped, like `startTime` beside it: it is one short string
                // off an array already read, the Bedtime face is a Small on
                // every surface, and a tile that reads "—" because the scope
                // was narrow is a tile that looks broken.
                medianBedtime: medianBedtime(rows, date: date)
            ),
            weight: OnyxSnapshot.Weight(
                kg: latest?.kg,
                deltaKg: zip2(latest, previous).map { (($0.kg - $1.kg) * 100).rounded() / 100 },
                measuredOn: latest?.date,
                targetKg: goals?.targetWeightKg,
                prevWeekMeanKg: WidgetDerive.meanBetween(weightSeries, from: prevWeekStart, to: weekStart),
                trend: wantsLifestyle || wantsBody ? Self.points(weightSeries) : nil
            ),
            macros: OnyxSnapshot.Macros(
                kcal: nutri?.calories,
                kcalGoal: resolvedGoals.calorie == 0 ? nil : resolvedGoals.calorie,
                proteinG: nutri?.proteinG, proteinGoalG: resolvedGoals.protein,
                carbsG: nutri?.carbsG, carbsGoalG: resolvedGoals.carbs,
                fatG: nutri?.fatG, fatGoalG: resolvedGoals.fat,
                kcalTrend: wantsLifestyle ? Self.points(WidgetDerive.dailySeries(
                    rows.nutrition.map { DatedValue(date: $0.date, value: $0.calories) }, limit: Self.trendDays
                )) : nil
            ),
            water: OnyxSnapshot.Water(
                // `WaterTruth` and not the rule that used to be written out
                // here: the Nutrition tab read `daily_logs.water_ml` alone and
                // this line preferred the ledger, so the tab and the tile could
                // print different litres for the same day (W1, F2).
                ml: WaterTruth.ml(log: log?.waterMl, ledger: water.map(\.amountMl)),
                goalMl: goals?.waterGoalMl.map(Double.init),
                trend: wantsLifestyle ? Self.points(WidgetDerive.dailySeries(
                    rows.water.map { DatedValue(date: $0.date, value: $0.amountMl) }, limit: Self.trendDays
                )) : nil
            ),
            steps: OnyxSnapshot.Steps(
                count: metrics?.steps ?? log?.steps,
                goal: resolvedGoals.steps.map { Int($0) },
                distanceM: log?.distanceM,
                activeKcal: metrics?.activeCal.map(Double.init) ?? log?.activeEnergy,
                trend: stepsTrend
            ),
            workout: OnyxSnapshot.Workout(
                label: day?.label ?? "Rest",
                dayKey: day?.dayKey,
                logged: weekSessions.contains { $0.date == date },
                isRestDay: !isTraining,
                // Null, never 0: on a training day a zero reads as "nothing
                // to do", the one thing it cannot mean.
                plannedExercises: planned?.exercises,
                plannedSets: planned?.sets,
                lastVolumeKg: lastVolumeKg,
                // Nil on a rest day rather than an empty array: nothing is
                // planned and the wash draws nothing, which is a real answer.
                muscles: isTraining ? deckMuscles(day?.dayKey) : nil
            ),
            week: {
                let t = Self.totals(weekSessions)
                return OnyxSnapshot.Week(sessions: t.sessions, volumeKg: t.volumeKg, prs: t.prs, sets: t.sets,
                                          sessionTarget: Schedule.sessionTargetIn(schedule))
            }(),
            weekPrev: Self.totals(prevSessions),
            records: performance?.records,
            e1rm: performance?.e1rm,
            muscleFocus: performance?.muscleFocus,
            today: todaySessions.isEmpty ? nil : OnyxSnapshot.Today(
                durationMin: longest?.session.durationMin.map { Int($0.rounded()) },
                sessionRpe: longest?.session.sessionRpe,
                volumeKg: todaySessions.reduce(0) { $0 + $1.volumeKg },
                setCount: todaySessions.reduce(0) { $0 + $1.sets },
                prCount: todaySessions.reduce(0) { $0 + $1.prs },
                // Summed like volume, and nil rather than 0 when no session
                // carried a figure — `calories_burned` is null until HealthKit
                // or `SessionMetrics` fills it, and a bout that cost nothing is
                // not a bout.
                caloriesKcal: {
                    let all = todaySessions.compactMap { $0.session.caloriesBurned }
                    return all.isEmpty ? nil : Double(all.reduce(0, +))
                }(),
                avgBpm: longest?.session.avgBpm
            ),
            streak: OnyxSnapshot.Streak(current: streak, best: streak),
            context: context,
            cardio: cardio,
            calendar: wantsTraining ? calendarGrid.map {
                OnyxSnapshot.CalendarDay(d: $0.d, dayKey: $0.dayKey, label: $0.label, scheduled: $0.scheduled, logged: $0.logged, volumeKg: $0.volumeKg)
            } : nil,
            volumeTrend: volumeTrend,
            body: body,
            scores: wantsBody ? scores : nil,
            readiness: readiness,
            vitals: vitals,
            consistency: consistency,
            deficit: deficit,
            trajectory: trajectory,
            batteryStack: batteryStack,
            bodyComp: bodyComp,
            coach: coach,
            weekRings: weekRings,
            soreness: soreness,
            stress: stress,
            deficitDays: deficitDays
        )
    }

    // MARK: - Reads

    /// Every table the payload draws on, in one read. Eight weeks of this
    /// athlete's sessions is ~40 rows; the wide read is cheaper than the
    /// round trips and every derived figure is guaranteed to agree.
    func fetch(date: String, trendFrom: String) throws -> Rows {
        let user = Column("user_id") == userId
        return try database.writer.read { db in
            let goals = try UserGoalRow.filter(user).fetchOne(db)
            let weekStartDay = Week.startDay(fromEndDay: goals?.weekEndDay)
            let weekStart = Week.start(of: date, startDay: weekStartDay)
            let weekEndExclusive = ISODate.addDays(weekStart, 7) ?? date
            let historyStart = ISODate.addDays(weekStart, -7 * (Self.volumeWeeks - 1)) ?? weekStart
            let calendarStart = ISODate.addDays(date, -(Self.calendarDays - 1)) ?? date
            let sessionsFrom = min(historyStart, calendarStart)
            // ONE assembly of the plan, the phase and the catalogue — the
            // same value every other reader resolves.
            let schedule = try AppDatabase.scheduleContext(db, userId: userId, goals: .some(goals))
            let programId = schedule.programId
            let phase = schedule.phase

            let sessions = try WorkoutSession
                .filter(user && Column("date") >= sessionsFrom && Column("date") < weekEndExclusive)
                .fetchAll(db)
            let ids = sessions.map(\.id)
            let sets = ids.isEmpty ? [] : try WorkoutSet.filter(ids.contains(Column("session_id"))).fetchAll(db)
            let ledger = try PersonalRecordRow.filter(user).fetchAll(db)
            var prsBySession: [String: Int] = [:]
            for r in ledger { if let s = r.sessionId { prsBySession[s, default: 0] += 1 } }
            var setsBySession: [String: [WorkoutSet]] = [:]
            for s in sets { setsBySession[s.sessionId, default: []].append(s) }
            let totals = sessions.map { s in
                let own = setsBySession[s.id] ?? []
                return SessionTotals(session: s, volumeKg: Self.volume(own), sets: Self.committedSets(own), prs: prsBySession[s.id] ?? 0)
            }

            let vitalsFrom = ISODate.addDays(date, -(Self.vitalsBaselineDays - 1)) ?? date
            let sleepFrom = NightWindow.range(trendFrom)?.from
            let sleepTo = NightWindow.range(date)?.to
            let cardioFrom = ISODate.addDays(date, -13) ?? date
            // The ledger and the consistency grid both walk `volumeWeeks` weeks
            // back from the start of this week — the same span the volume trend
            // already reads sessions over.
            let ledgerFrom = historyStart

            return Rows(
                goals: goals,
                schedule: schedule,
                profiles: try TargetProfileRow.filter(user).order(Column("sort")).fetchAll(db),
                periods: try LeverPeriodRow.filter(user).order(Column("starts_on")).fetchAll(db),
                dayTarget: try DailyTargetRow.filter(user && Column("date") == date).fetchOne(db),
                storedScore: try DailyScoreRow.filter(user && Column("date") == date).fetchOne(db),
                logs: try DailyLogRow.filter(user && Column("date") >= vitalsFrom && Column("date") <= date).fetchAll(db),
                metrics: try DailyMetricRow.filter(user && Column("date") >= trendFrom && Column("date") <= date).fetchAll(db),
                sleep: sleepFrom == nil || sleepTo == nil ? [] : try SleepSessionRow
                    .filter(user && Column("start_time") >= sleepFrom! && Column("start_time") < sleepTo!)
                    .order(Column("duration_min").desc)
                    .fetchAll(db),
                nutrition: try NutritionEntryRow
                    .filter(user && Column("date") >= trendFrom && Column("date") <= date && Column("meal_type") == "daily")
                    .fetchAll(db),
                water: try WaterIntakeRow.filter(user && Column("date") >= trendFrom && Column("date") <= date).fetchAll(db),
                weights: try BodyCompositionRow.filter(user).order(Column("date").desc).limit(30).fetchAll(db),
                sessions: totals,
                sets: sets,
                // ── THE CATALOGUE, PLUS THE SLUGS THE PHONE WRITES ──────────
                // `exercises` holds server uuids only. A set logged on the phone
                // is stamped `onyx-<slug>` (`LoggerModel.exerciseId`) and keeps
                // that id for as long as the session has local events, which is
                // forever for the device that logged it. Naming only the
                // catalogue dropped every phone-logged set from muscle credit —
                // "Side delts 0/7" after an Upper B was exactly this. The same
                // chain `LoggerModel.restoreLoggedSets` already walks.
                exerciseNames: try {
                    let exercises = try Exercise.fetchAll(db)
                    return Dictionary(
                        exercises.map { ($0.id, $0.name) } + ExerciseSlug.nameBySlug(exercises).map { ($0.key, $0.value) },
                        uniquingKeysWith: { a, _ in a }
                    )
                }(),
                ledger: ledger,
                cardio: try CardioLogRow
                    .filter(user && Column("date") >= cardioFrom && Column("date") <= date)
                    .order(Column("created_at").asc)
                    .fetchAll(db),
                ledgerLogs: try DailyLogRow
                    .filter(user && Column("date") >= ledgerFrom && Column("date") <= date)
                    .order(Column("date"))
                    .fetchAll(db),
                ledgerNutrition: try NutritionEntryRow
                    .filter(user && Column("date") >= ledgerFrom && Column("date") <= date && Column("meal_type") == "daily")
                    .fetchAll(db),
                phaseVolume: Dictionary(
                    try PlanPhaseVolumeRow
                        .filter(user && Column("plan_id") == programId && Column("phase") == phase.rawValue)
                        .fetchAll(db)
                        .map { ($0.muscle, $0.targetSets) },
                    uniquingKeysWith: { _, last in last }
                ),
                phaseGoals: try PlanPhaseGoalRow
                    .filter(user && Column("plan_id") == programId
                            && Column("phase") == phase.rawValue)
                    .fetchOne(db),
                doms: try DomsLogRow.filter(user && Column("date") == date).fetchAll(db),
                bedtimeOffsets: try AppDatabase.bedtimeOffsets(db, userId: userId, before: date, limit: Self.vitalsBaselineDays)
            )
        }
    }

    // MARK: - Score

    struct LiveScore {
        let total: Int
        let battery: Int
        let components: OnyxCore.ScoreComponents
    }

    /// `refreshTodayScore` without the write: the same inputs the app scores
    /// with (`scoringInputs`), the same supplements `computeForDate` resolved.
    /// Nil when the scorer has nothing to say, so the stored row answers.
    func liveScore(
        date: String, hoursAwake: Double, isRestDay: Bool,
        todaySessions: [SessionTotals], allSessions: [SessionTotals],
        goals: UserGoalRow?, resolvedGoals: LeverGoals,
        schedule: ScheduleContext, ladder: LeverLadder,
        prescribed: (String?) -> (exercises: Int, sets: Int)?
    ) throws -> LiveScore? {
        let dayKey = todaySessions.first { $0.session.dayKey != nil }?.session.dayKey
        let planned = prescribed(dayKey)
        let supplements = ScoringSupplements(
            goals: ResolvedGoals(
                calorie: resolvedGoals.calorie, protein: resolvedGoals.protein ?? 0, carbs: resolvedGoals.carbs ?? 0,
                fat: resolvedGoals.fat ?? 0, steps: resolvedGoals.steps ?? Double(goals?.stepsGoal ?? 0)
            ),
            isMaintenance: Maintenance.isMaintenanceDate(date, today: date, ladder: ladder, phases: schedule.phases),
            plannedExercises: planned.map { Double($0.exercises) },
            plannedSets: planned.map { Double($0.sets) }
        )
        guard let inputs = try database.scoringInputs(
            userId: userId, date: date, hoursAwake: hoursAwake, isRestDay: isRestDay,
            todayISO: date, isToday: true, supplements: supplements
        ) else { return nil }

        let components = Score.daily(inputs)
        guard let total = components.totalScore else { return nil }
        let battery = Battery.computeBattery(inputs, hoursAwake: hoursAwake)
        return LiveScore(total: Int(total.rounded()), battery: Int(battery.currentPct.rounded()), components: components)
    }

    // MARK: - The W12 series

    /// One row per day of the consistency window: what the plan asked for, and
    /// whether a session landed.
    ///
    /// ── WHY THE SCHEDULE IS ONLY CONSULTED FROM WEEK 0 ────────────────────
    /// `Schedule.scheduleDayIn` answers with the ACTIVE programme's layout and
    /// has no memory of what was running last spring. Before Week 0 the block
    /// was PPL — six days, different splits, none of them in the current plan —
    /// and asking today's schedule about those weeks does not fail, it answers
    /// confidently and wrongly. The strip would fill with missed days that were
    /// never scheduled. `HistoryWeeks.isPlannable` draws the same line.
    func consistencyDays(
        from: String, to: String, schedule: ScheduleContext, sessions: [SessionTotals]
    ) -> [ConsistencyDayIn] {
        let logged = Set(sessions.map(\.date))
        var out: [ConsistencyDayIn] = []
        var d = from
        while d <= to {
            let plannable = Schedule.isPlannable(d, in: schedule)
            let day = plannable ? Schedule.scheduleDayIn(schedule, d) : nil
            out.append(ConsistencyDayIn(
                date: d,
                dayKey: day?.dayKey,
                scheduled: plannable && Schedule.isTrainingDayIn(schedule, d),
                logged: logged.contains(d)
            ))
            guard let next = ISODate.addDays(d, 1) else { break }
            d = next
        }
        return out
    }

    /// The ledger window's days, intake joined onto expenditure by date.
    func ledgerDays(_ rows: Rows) -> [DeficitDayIn] {
        var calories: [String: Double] = [:]
        for m in rows.ledgerNutrition { calories[m.date] = m.calories }
        return rows.ledgerLogs.map { l in
            DeficitDayIn(
                date: l.date,
                intakeKcal: calories[l.date],
                bmrKcal: l.bmr,
                activeKcal: l.activeEnergy,
                // `validWeight` is what stops a carried-forward zero entering
                // the reconciliation as a fourteen-kilo overnight loss.
                weightKg: Format.validWeight(l.weightKg)
            )
        }
    }

    /// A fortnight of battery breakdowns.
    ///
    /// ── WHY THIS RE-SCORES RATHER THAN READING A COLUMN ───────────────────
    /// `daily_scores` stores `battery_pct` and nothing behind it: the five
    /// drains are computed at render time and thrown away. Recomputing them is
    /// the only way to draw the stack at all, and it is the same call
    /// `refreshDailyScore` makes — including its rule that a FINISHED day is
    /// scored as a finished day (`hoursAwake` pinned to `maxAwake`), so a
    /// fortnight of bands does not shift under the wall clock.
    ///
    /// ponytail: fourteen `scoringInputs` reads per snapshot. If the extension
    /// ever runs short of its memory or time budget, the fix is a
    /// `battery_breakdown` jsonb column written by `DailyScoreWriter`, not a
    /// cache here.
    func batteryStackSlice(_ rows: Rows, date: String, now: Date, calendar: Calendar) throws -> [BatteryStackDay] {
        var days: [BatteryStackDayIn] = []
        var d = ISODate.addDays(date, -(Self.batteryStackDays - 1)) ?? date
        while d <= date {
            let plan = DayPlan.resolve(
                goals: rows.goals, schedule: rows.schedule, profiles: rows.profiles, periods: rows.periods,
                dayTarget: d == date ? rows.dayTarget : nil, date: d, todayISO: date
            )
            let hoursAwake = d == date ? Battery.hoursAwake(at: now, calendar: calendar) : Battery.defaults.maxAwake
            let inputs = try database.scoringInputs(
                userId: userId, date: d, hoursAwake: hoursAwake, isRestDay: !plan.isTraining,
                todayISO: date, isToday: d == date, supplements: plan.supplements
            )
            // ── AN UNSCORED DAY DRAWS NOTHING, NOT A NEUTRAL BATTERY ──────
            // `Battery.breakdown` degrades every missing term to its NEUTRAL
            // value rather than to nil, so empty inputs still return a morning
            // charge near 55 and a clock drain — a real-looking column for a
            // day `daily_scores` has no row for, on a tile sitting beside faces
            // that render the same day as "—". `scoringInputs` only returns nil
            // for a PAST day with nothing at all, so a travel day carrying one
            // hand-entered weight was enough to invent one.
            //
            // Gate on the condition the snapshot's own battery uses (see
            // `liveScore`, and `refreshDailyScore` before it): a day is scored
            // everywhere or nowhere.
            let scored = inputs.flatMap { Score.daily($0).totalScore == nil ? nil : $0 }
            let breakdown = scored.map { Battery.breakdown($0, hoursAwake: hoursAwake) }
            days.append(BatteryStackDayIn(
                date: d,
                batteryPct: breakdown.map { jsRound($0.currentPct) },
                breakdown: breakdown
            ))
            guard let next = ISODate.addDays(d, 1) else { break }
            d = next
        }
        return BatteryStackSeries.build(days, endingOn: date, limit: Self.batteryStackDays)
    }

    // MARK: - Slices

    /// Seven days of step counts, the HealthKit mirror winning over the log.
    func stepsTrend(_ rows: Rows, date: String) -> [TrendPoint] {
        let from = ISODate.addDays(date, -6) ?? date
        var byDate: [String: Double?] = [:]
        var order: [String] = []
        for r in rows.logs where r.date >= from {
            if byDate[r.date] == nil { order.append(r.date) }
            byDate[r.date] = r.steps.map(Double.init)
        }
        for r in rows.metrics where r.steps != nil {
            if byDate[r.date] == nil { order.append(r.date) }
            byDate[r.date] = r.steps.map(Double.init)
        }
        return WidgetDerive.trendPoints(order.map { DatedValue(date: $0, value: byDate[$0] ?? nil) }, limit: 7)
    }

    /// Records, 1RM movement and the week's sets per LANDMARK against target.
    func performanceSlice(_ rows: Rows, date: String, weekStart: String) -> (records: [OnyxSnapshot.Record], e1rm: [OnyxSnapshot.E1rm], muscleFocus: [OnyxSnapshot.MuscleVolume]) {
        let since = ISODate.addDays(date, -Self.performanceHistoryDays) ?? date
        let weekEnd = ISODate.addDays(weekStart, 7) ?? date
        let dayOf = Dictionary(rows.sessions.map { ($0.session.id, $0.date) }, uniquingKeysWith: { a, _ in a })
        // A set whose exercise or session cannot be named is a set nothing
        // can say anything true about — dropped rather than attributed to "".
        let sets: [WidgetSetRow] = rows.sets.compactMap { s in
            guard let day = dayOf[s.sessionId], day >= since, let name = rows.exerciseNames[s.exerciseId], !name.isEmpty
            else { return nil }
            return WidgetSetRow(exercise: name, day: day, weightKg: s.weightKg, reps: Double(s.reps), est1rmKg: s.est1rmKg, setType: s.setType)
        }
        let weekSets = sets.filter { $0.day >= weekStart && $0.day < weekEnd }
        let ledger = rows.ledger
            .sorted { $0.achievedOn > $1.achievedOn }
            .prefix(Self.ledgerLimit)
            .map { LedgerRow(exerciseKey: $0.exerciseKey, axis: $0.axis, value: $0.value, reps: $0.reps.map(Double.init), achievedOn: $0.achievedOn) }
        // ── THE MARGIN IS THE FLOOR THE RECORD CLEARED (W6) ─────────────────
        // `personal_records` is UNIQUE on (user_id, exercise_key, axis): one
        // standing row per lift per axis, and a beaten record is overwritten.
        // The bar it cleared survives in `floor_value`, which `PrRecorder
        // .carryFloor` maintains for exactly this reason. `OnyxSnapshot.Record
        // .previous` says the rest.
        //
        // Read off `rows.ledger` — every row this user owns, no date bound and
        // no limit — rather than off the forty-row window below it, and carried
        // here rather than through `WidgetDerive.topRecords`, which is pinned by
        // `widget-records.json`: the selection rule did not change.
        let floorByKey: [String: Double] = {
            var out: [String: Double] = [:]
            for row in rows.ledger {
                guard let floor = row.floorValue else { continue }
                out["\(row.exerciseKey)|\(row.axis)"] = floor
            }
            return out
        }()
        return (
            WidgetDerive.topRecords(Array(ledger), limit: 6).map {
                OnyxSnapshot.Record(
                    exercise: $0.exercise, axis: $0.axis, value: $0.value,
                    reps: $0.reps.map { Int($0) }, achievedOn: $0.achievedOn,
                    // `Record.margin` drops a floor that is not below the
                    // record, so a compiled bar ABOVE a logged mark reports no
                    // gain rather than a negative one.
                    previous: floorByKey["\($0.exercise)|\($0.axis)"]
                )
            },
            WidgetDerive.e1rmTrends(sets, asOf: date, limit: 5).map {
                OnyxSnapshot.E1rm(exercise: $0.exercise, kg: $0.kg, deltaKg: $0.deltaKg, trend: Self.points($0.trend))
            },
            // ── THE ONE ACCUMULATOR (F7) ────────────────────────────────────
            // The same call `TodayFeedBuilder.muscleFocus` makes, over the same
            // week, with the same ghost exclusion — so the tile and the sheet it
            // opens cannot disagree about how much work the week was. Every one
            // of the sixteen is present whether or not the week touched it: a
            // muscle that vanishes when untrained is the one you most need to
            // see, and the payload is what the figure paints.
            {
                let credit = MuscleCredit.weightedSets(
                    exerciseNames: weekSets.filter { $0.setType != "ghost" }.map(\.exercise)
                )
                return LandmarkMuscle.allCases.map { muscle in
                    OnyxSnapshot.MuscleVolume(
                        muscle: muscle.rawValue,
                        // One decimal: the credit is halves, and a raw Double
                        // prints 8.500000000000002 often enough to matter.
                        sets: ((credit[muscle] ?? 0) * 10).rounded() / 10,
                        target: rows.phaseVolume[muscle.rawValue] ?? 0
                    )
                }
            }()
        )
    }

    /// The last seven days, one row each: trained, fuel hit, sleep hit.
    ///
    /// ── WHAT EACH MARK MEANS, AND WHY ────────────────────────────────────
    /// `trained` is a session LOGGED, never one scheduled — `consistency` is
    /// the tile that grades against the plan, and two tiles disagreeing about
    /// a Tuesday is the split the one-accumulator rule exists to prevent.
    ///
    /// `fuelHit` is intake within a tenth of THAT day's calorie target. A band
    /// and not a floor: on a cut, eating three hundred under is not a better
    /// day than eating the target, and a one-sided rule would light the week
    /// brightest for the days that went worst. A day with nothing logged is a
    /// miss — see `WeekRingDay` for why that is a reading and not an
    /// invention.
    ///
    /// `sleepHit` is the night that ended that morning reaching the goal, off
    /// the same union the Sleep face draws (`sleep_sessions` first, the log's
    /// own minutes behind it). No goal set, no hit: a ring cannot be met
    /// against nothing.
    func weekRingsSlice(
        _ rows: Rows, date: String, targets: TargetSnapshot, sessions: [SessionTotals]
    ) -> [OnyxSnapshot.WeekRingDay] {
        let trained = Set(sessions.map(\.date))
        var intake: [String: Double] = [:]
        for n in rows.nutrition { intake[n.date] = (intake[n.date] ?? 0) + n.calories }
        // Sleep, bucketed by the night it ENDED on — never by `start_time`'s
        // own date, which files every pre-midnight bedtime under the evening.
        var slept: [String: Double] = [:]
        for row in rows.sleep {
            let night = Night.nightOf(Self.iso(row.startTime))
            slept[night] = max(slept[night] ?? 0, Double(row.durationMin))
        }
        for log in rows.logs {
            guard slept[log.date] == nil, let minutes = log.sleepMinutes else { continue }
            slept[log.date] = Double(minutes)
        }
        let sleepGoalMin = rows.goals?.sleepGoalHours.map { $0 * 60 }

        var out: [OnyxSnapshot.WeekRingDay] = []
        var d = ISODate.addDays(date, -(Self.weekRingDays - 1)) ?? date
        while d <= date {
            let goal = targets.targets(for: d, today: date).goals.calorie
            let kcal = intake[d]
            let fuelHit = goal > 0 && kcal.map { abs($0 - goal) <= goal * 0.1 } ?? false
            out.append(OnyxSnapshot.WeekRingDay(
                date: d,
                trained: trained.contains(d),
                fuelHit: fuelHit,
                sleepHit: zip2(slept[d], sleepGoalMin).map { $0 >= $1 } ?? false
            ))
            guard let next = ISODate.addDays(d, 1) else { break }
            d = next
        }
        return out
    }

    /// The day's ratings, folded to one severity per GROUP and expanded onto
    /// the atlas's landmarks.
    ///
    /// Max within a group and not a mean, for `foldDomsSeverity`'s own reason:
    /// "left quad severe, right quad fine" is a severe quad, and averaging it
    /// to moderate paints a day nobody had. A rating of None is dropped — the
    /// array is what is SORE, and the figure lights what is in it.
    static func sorenessRegions(_ rows: [DomsLogRow]) -> [OnyxSnapshot.SorenessRegion] {
        var peak: [String: Int] = [:]
        for row in rows where DomsMuscles.recognised.contains(row.muscleGroup) {
            peak[row.muscleGroup] = max(peak[row.muscleGroup] ?? 0, row.severity)
        }
        var byLandmark: [LandmarkMuscle: Int] = [:]
        for (group, severity) in peak where severity > 0 {
            for landmark in DomsMuscles.landmarks[group] ?? [] {
                byLandmark[landmark] = max(byLandmark[landmark] ?? 0, severity)
            }
        }
        // `allCases` order, so the face's list is the atlas's order however the
        // rows arrived — a dictionary's is not an order.
        return LandmarkMuscle.allCases.compactMap { landmark in
            byLandmark[landmark].map { OnyxSnapshot.SorenessRegion(landmark: landmark.rawValue, level: $0) }
        }
    }

    /// "23:30" — the usual bedtime as a LOCAL clock time.
    ///
    /// The offsets are minutes past each night window's UTC noon, so the
    /// median is a UTC instant and printing its hour raw would read three
    /// hours wrong on a phone in Jerusalem. Anchored on TONIGHT's window and
    /// rendered in the builder's own zone: a DST change moves every offset by
    /// sixty together and the median absorbs it within a fortnight.
    ///
    /// Nil under five nights — `median`'s own floor. "Usual" over four is a
    /// guess, and a guess printed as a baseline is worse than no baseline.
    func medianBedtime(_ rows: Rows, date: String) -> String? {
        guard let offset = AppDatabase.median(rows.bedtimeOffsets),
              let window = NightWindow.range(date) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = timeZone
        return f.string(from: window.from.addingTimeInterval(offset * 60))
    }

    /// Five overnight readings, each against its own fortnight baseline.
    func vitalsSlice(_ logs: [DailyLogRow], date: String) -> OnyxSnapshot.Vitals {
        func of(_ pick: (DailyLogRow) -> Double?) -> OnyxSnapshot.Vital {
            let b = WidgetDerive.vitalBlock(logs.map { DatedValue(date: $0.date, value: pick($0)) }, todayISO: date, trendLimit: Self.trendDays)
            return OnyxSnapshot.Vital(value: b.value, baseline: b.baseline, trend: Self.points(b.trend))
        }
        return OnyxSnapshot.Vitals(
            hrvMs: of { $0.hrvMs },
            restingBpm: of { $0.avgRestHeartRate.map(Double.init) },
            wristTempDeltaC: of { $0.wristTempDelta },
            bloodOxygenPct: of { $0.bloodOxygen },
            respiratoryRate: of { $0.respiratoryRate }
        )
    }

    func cardioSlice(_ rows: [CardioLogRow], date: String, weekStart: String) -> OnyxSnapshot.Cardio {
        let block = WidgetDerive.cardioBlock(
            rows.map { WidgetCardioRow(date: $0.date, kind: $0.kind, distanceM: $0.distanceM, durationMin: $0.durationMin) },
            today: date, weekStart: weekStart,
            zone2MinMinutes: Zone2.minMinutes, weekTarget: Zone2.weeklyTarget,
            paceOf: { CardioMetrics.paceMinPerKm(distanceM: $0, durationMin: $1) },
            trendDays: Self.trendDays
        )
        return OnyxSnapshot.Cardio(
            last: block.last.map {
                OnyxSnapshot.Cardio.Session(kind: $0.kind, date: $0.date, distanceM: $0.distanceM, durationMin: $0.durationMin, paceMinPerKm: $0.paceMinPerKm)
            },
            weekSessions: block.weekSessions, weekTarget: block.weekTarget,
            weekMinutes: Int(block.weekMinutes), trend: Self.points(block.trend)
        )
    }

    /// Field by field, not row by row: the newest muscle figure often lives on
    /// an older row than the newest weight, and `latestDelta` skips back to
    /// the previous DIFFERING reading because the table carries values forward.
    func bodySlice(_ rows: [BodyCompositionRow]) -> OnyxSnapshot.Body {
        func field(_ pick: (BodyCompositionRow) -> Double?) -> LatestDelta {
            WidgetDerive.latestDelta(WidgetDerive.trendPoints(rows.map { DatedValue(date: $0.date, value: pick($0)) }, limit: 30))
        }
        let fat = field { $0.bodyFatPct }, lean = field { $0.muscleMassKg }
        let skeletal = field { $0.skeletalMuscleMassKg }, ffm = field { $0.fatFreeMassKg }
        return OnyxSnapshot.Body(
            fatPct: fat.value, muscleKg: lean.value, smmKg: skeletal.value, ffmKg: ffm.value,
            fatPctDelta: fat.delta, muscleKgDelta: lean.delta, smmKgDelta: skeletal.delta, ffmKgDelta: ffm.delta,
            fatTrend: Self.points(WidgetDerive.trendPoints(rows.map { DatedValue(date: $0.date, value: $0.bodyFatPct) }, limit: 14))
        )
    }

    // MARK: - Helpers

    /// Counts are zero when nothing happened; tonnage is NIL.
    ///
    /// `reduce(0)` over no sessions is 0, and the faces printed "0.0 t" for it
    /// — on Monday morning, on a fresh install, and for the whole of the
    /// casing bug, which hid every synced session from the query behind it.
    /// That is this file's own rule broken at the top of the file: an invented
    /// zero renders as a lie.
    static func totals(_ rows: [SessionTotals]) -> OnyxSnapshot.WeekTotals {
        OnyxSnapshot.WeekTotals(
            sessions: rows.count,
            volumeKg: rows.isEmpty ? nil : rows.reduce(0) { $0 + $1.volumeKg }.rounded(),
            prs: rows.reduce(0) { $0 + $1.prs },
            sets: rows.reduce(0) { $0 + $1.sets }
        )
    }

    /// `sessionVolumeKg` over the local rows — a unilateral pair is one set.
    static func volume(_ sets: [WorkoutSet]) -> Double { AppDatabase.volume(sets) }


    /// `countCommittedSets`: solo sets plus distinct pairs. A ghost is a pencil
    /// mark, not a set.
    static func committedSets(_ sets: [WorkoutSet]) -> Int {
        var pairs = Set<String>()
        var solo = 0
        for s in sets where s.setType != "ghost" {
            if let p = s.pairId, !p.isEmpty { pairs.insert(p) } else { solo += 1 }
        }
        return solo + pairs.count
    }

    static func points(_ trend: [TrendPoint]) -> [OnyxSnapshot.Point] {
        trend.map { OnyxSnapshot.Point(d: $0.d, v: $0.v) }
    }

    /// `Date.toISOString()` — UTC, milliseconds, `Z`. A formatter per call:
    /// `ISO8601DateFormatter` is not Sendable and this runs a handful of times
    /// per build.
    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
