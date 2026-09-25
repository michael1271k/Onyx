import Foundation
import GRDB
import OnyxCore
import OnyxData

/// Every week you have trained, and the days inside one of them (§5.9).
///
/// ── WHY THE WEEK IS THE UNIT ────────────────────────────────────────────────
/// The flat "every session, newest first" list this replaces answered one
/// question — what did I lift on the 1st — and the block is not run in
/// sessions. It is run in weeks: five sessions against a target of five, a
/// tonnage that should be climbing, a weight that should be falling, a phase
/// that turns over on a Sunday. A list of sessions cannot show a MISSED day,
/// because a day nothing happened on has no row; a week of seven cells can, and
/// that absence is most of what a training log is for.
///
/// ── AND WHY IT IS ONE PASS OVER EVERYTHING ──────────────────────────────────
/// Every read here is unfiltered and unranged, then folded by week in memory.
/// That is deliberate at this size — a few thousand sets, one weigh-in a day,
/// one score a day — and it is what lets every capsule agree with every other:
/// one `SessionAnalysis.summaries` walk replays the record book ONCE, in order,
/// so a PR counted in Week 5 is not counted again in Week 6. Paginating this
/// would mean replaying the ledger per page, which is the same walk plus a
/// chance to disagree with itself.
///
/// ponytail: whole-history scan on open, ~1 s detached at 60 sessions. If it
/// ever stops feeling instant, the fix is a ranged read in `OnyxData` (Track
/// E's package) rather than a cache here.
enum HistoryWeeks {

    // MARK: - Shapes

    /// One dot of a capsule's seven-dot strip.
    struct DayCell: Identifiable, Sendable, Equatable {
        var id: String { date }
        let date: String
        let initial: String
        /// The split this day was, or was going to be. `nil` is a rest day.
        let dayKey: String?
        let sessionId: String?
        let isFuture: Bool

        var isLogged: Bool { sessionId != nil }
        var isRest: Bool { dayKey == nil }
        /// Planned and not done — the state a session list cannot draw.
        var isMissed: Bool { !isLogged && !isRest && !isFuture }
    }

    struct Capsule: Identifiable, Sendable, Equatable {
        let window: WeekWindow
        var id: String { window.start }
        let cells: [DayCell]
        let sessions: Int
        let tonnageKg: Double
        let sets: Int
        let prCount: Int
        /// Week over week, from the last scale reading of each. Nil until two
        /// weeks have one — never rendered as 0.0, which reads as "no change".
        let weightDeltaKg: Double?
        let era: PhaseEra?
        /// `Cut W7`, when the week sits inside a defined phase.
        let phaseLabel: String?
        /// Was this week eaten at maintenance?
        ///
        /// ── THE LEVER AXIS, NOT `Maintenance.isMaintenanceDate` ─────────────
        /// That helper falls back to the PHASE when no lever claims the day,
        /// which would tag the Thailand and Transition weeks too — and those
        /// already say so in the pill beside this one ("Trans W1"). What is
        /// worth a second tag is the week the training did NOT change and the
        /// food did, which is exactly `Levers.leverForDate == .maintenanceWeek`
        /// (§W11: "Maintenance (from `Levers.leverForDate`)").
        ///
        /// A majority of the week, not any day of it: the schedule's rows are
        /// inclusive lower bounds and a rung that turns over mid-week would
        /// otherwise tag both weeks it touches.
        let isMaintenance: Bool
    }

    /// One row of `WeekDaysView`.
    struct DayRow: Identifiable, Sendable, Equatable {
        var id: String { date }
        let date: String
        let dayKey: String?
        /// `Chest & Back A`, or nil for a rest day.
        let label: String?
        let sessionId: String?
        let tonnageKg: Double
        let sets: Int
        let prCount: Int
        let durationMin: Double?
        let steps: Int?
        let sleepMinutes: Int?
        let isFuture: Bool

        var isLogged: Bool { sessionId != nil }
    }

    /// The 2×4 strip above the day rows. Every field optional: a week with no
    /// weigh-in has no delta, and printing a zero there is a claim.
    struct WeekVitals: Sendable, Equatable {
        var weightDeltaKg: Double?
        var fatDeltaPct: Double?
        var batteryMean: Double?
        var sleepScoreMean: Double?
        var sleepMeanMinutes: Double?
        var stepsMean: Double?
        var tonnageKg: Double = 0
        var sessions: Int = 0
        /// The week's MEAN scale reading — not its last, and not its delta.
        ///
        /// The delta beside it answers "which way", which is the question a cut
        /// is scanned for day to day. The mean answers "where", which is the
        /// one a week is scanned for: a fortnight of means is a trend a reader
        /// can hold, and a fortnight of last-readings is mostly water.
        var weightMeanKg: Double?
        /// Foster's weekly strain for this week, and the EWMA acute:chronic
        /// ratio as of its last day. Both from `Readiness.loadSignal`, which is
        /// the ONE public door to either — `fosterWeek` stays internal.
        var strain: Double?
        var acwr: Double?
    }

    struct WeekDetail: Sendable, Equatable {
        let window: WeekWindow
        var days: [DayRow] = []
        var vitals = WeekVitals()
        /// The weekly report covering this week, when one has been written.
        var report: ReportRow?
    }

    // MARK: - The list

    /// Every week from the first day anything was recorded to the week you are
    /// standing in, newest first.
    nonisolated static func capsules(
        database: AppDatabase, today: String = LogicalDay.today()
    ) -> [Capsule] {
        let context = scheduleContext(database: database)
        let goals = context.goals
        let startDay = WeekWindow.startDay(from: goals)
        // An empty string is not a selection — the same read `WeeklyExportBuilder`
        // makes, because `isLeverId("")` would say otherwise.

        let owner = database.localUserId()
        let sessions = (try? database.sessionHistory(userId: owner)) ?? []
        let ledger = (try? database.historySets(userId: owner)) ?? []
        let summaries = SessionAnalysis.summaries(sessions, ledger: ledger, in: context.analysis)
        let byDate = Dictionary(summaries.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let finishedIds = Set(sessions.filter { $0.endedAt != nil }.map(\.id))

        // The scale, folded to one reading a day, oldest first.
        let readings = BodyVitals.readings(ledger: bodyRows(database), logs: dailyLogs(database))
            .filter { $0.weight != nil }

        // `min()` over the dates, not `.first` of either array. `summaries` is
        // NEWEST first — it is what the reverse-chronological list was built
        // for — so reading its head as "the beginning of history" produced a
        // single capsule for the most recent week and silently dropped every
        // week before it.
        guard let earliest = (summaries.map(\.date) + readings.map(\.date)).min() else {
            return []
        }

        var out: [Capsule] = []
        var window = WeekWindow(containing: earliest, startDay: startDay)
        let last = WeekWindow(containing: today, startDay: startDay)
        var previousWeight: Double?

        while window.start <= last.start {
            let dates = window.days
            let plannable = isPlannable(window, in: context.schedule)
            let cells = dates.map { date -> DayCell in
                let summary = byDate[date]
                let planned = plannable ? Schedule.scheduleDayIn(context.schedule, date) : nil
                return DayCell(
                    date: date,
                    initial: WeekWindow.initial(date),
                    dayKey: summary?.dayKey ?? planned?.dayKey,
                    sessionId: summary.map(\.id).flatMap { finishedIds.contains($0) ? $0 : nil },
                    isFuture: date > today
                )
            }
            let weekSummaries = dates.compactMap { byDate[$0] }
            // Last reading of the week against the last reading of any earlier
            // week — not first-to-last within the week, which reports nothing
            // at all for the many weeks holding a single weigh-in.
            let weight = dates.compactMap { date in readings.last { $0.date == date }?.weight }.last
            let delta = (weight != nil && previousWeight != nil) ? weight! - previousWeight! : nil
            if let weight { previousWeight = weight }

            // The rung in force on each day, on the LEVER axis. `today` is a
            // parameter to `leverForDate` and never a clock, so a capsule
            // built for a screenshot says the same thing every run.
            let maintenanceDays = dates.filter {
                Maintenance.leverOn($0, today: today, ladder: context.ladder)
            }.count

            let phase = window.phase(in: context.schedule.phases)
            out.append(Capsule(
                window: window,
                cells: cells,
                sessions: weekSummaries.count,
                tonnageKg: weekSummaries.reduce(0) { $0 + $1.tonnageKg },
                sets: weekSummaries.reduce(0) { $0 + $1.totalSets },
                prCount: weekSummaries.reduce(0) { $0 + $1.prCount },
                weightDeltaKg: delta,
                era: phase?.era,
                phaseLabel: phase?.short,
                isMaintenance: maintenanceDays * 2 > dates.count
            ))
            guard let next = window.offset(byWeeks: 1) else { break }
            window = next
        }
        return out.reversed()
    }

    // MARK: - One week

    nonisolated static func detail(
        database: AppDatabase, window: WeekWindow, today: String = LogicalDay.today()
    ) -> WeekDetail {
        let context = scheduleContext(database: database)
        let owner = database.localUserId()
        let sessions = (try? database.sessionHistory(userId: owner)) ?? []
        let ledger = (try? database.historySets(userId: owner)) ?? []
        let byDate = Dictionary(
            SessionAnalysis.summaries(sessions, ledger: ledger, in: context.analysis).map { ($0.date, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let finishedIds = Set(sessions.filter { $0.endedAt != nil }.map(\.id))

        let dates = window.days
        let plannable = isPlannable(window, in: context.schedule)
        let range = Set(dates)
        let logs = dailyLogs(database).filter { range.contains($0.date) }
        let logsByDate = Dictionary(logs.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        let scores = dailyScores(database).filter { range.contains($0.date) }

        var out = WeekDetail(window: window)
        out.days = dates.map { date in
            let summary = byDate[date]
            let planned = plannable ? Schedule.scheduleDayIn(context.schedule, date) : nil
            let key = summary?.dayKey ?? planned?.dayKey
            return DayRow(
                date: date,
                dayKey: key,
                label: SessionAnalysis.dayLabel(key, in: context.schedule.activeProgram) ?? planned?.label,
                sessionId: summary.map(\.id).flatMap { finishedIds.contains($0) ? $0 : nil },
                tonnageKg: summary?.tonnageKg ?? 0,
                sets: summary?.totalSets ?? 0,
                prCount: summary?.prCount ?? 0,
                durationMin: summary?.durationMin,
                steps: logsByDate[date]?.steps,
                sleepMinutes: logsByDate[date]?.sleepMinutes,
                isFuture: date > today
            )
        }

        // ── The 2×4 ─────────────────────────────────────────────────────────
        // The two body deltas are the week's own span — first reading to last —
        // because this screen is about THIS week, unlike the capsule list where
        // week-over-week is the comparison being scanned.
        let readings = BodyVitals.readings(ledger: bodyRows(database), logs: logs)
            .filter { range.contains($0.date) }
        let weights = readings.compactMap(\.weight)
        let fats = readings.compactMap(\.fatPct)
        out.vitals.weightDeltaKg = weights.count >= 2 ? weights.last! - weights.first! : nil
        out.vitals.fatDeltaPct = fats.count >= 2 ? fats.last! - fats.first! : nil
        // No `>= 2` gate, deliberately, unlike the delta directly above it. The
        // gate up there is the DELTA's own correctness condition — one reading
        // cannot express a direction — and it is not a house rule that a figure
        // needs two readings. A mean of one weigh-in is that weigh-in, which is
        // a true statement about the week. `mean(_:)` is nil only on empty.
        out.vitals.weightMeanKg = mean(weights)
        out.vitals.batteryMean = mean(scores.compactMap { $0.batteryPct.map(Double.init) })
        out.vitals.sleepScoreMean = mean(scores.compactMap { $0.sleepScore.map(Double.init) })
        out.vitals.sleepMeanMinutes = mean(logs.compactMap { $0.sleepMinutes.map(Double.init) })
        out.vitals.stepsMean = mean(logs.compactMap { $0.steps.map(Double.init) })
        out.vitals.tonnageKg = out.days.reduce(0) { $0 + $1.tonnageKg }
        out.vitals.sessions = out.days.filter(\.isLogged).count

        // ── TRAINING LOAD, THROUGH THE BATTERY'S OWN SERIES ─────────────────
        // `AppDatabase.loadSignal` is a door onto `readinessHistory`, which is
        // the ONE place on the phone that turns rows into the 49-day series the
        // battery is scored from. A second series assembled here is how two
        // screens start disagreeing about the same fortnight.
        //
        // ── WHY THE ENDPOINT IS CLAMPED TO TODAY ───────────────────────────
        // `LoadSignal.strain` is Foster's over the series' last seven entries,
        // so ending on `window.end` is what makes it THIS week's strain. On a
        // week that has closed that is exactly right and it is what runs.
        //
        // On the LIVE week `window.end` is in the future, and `dailyLoads` is
        // explicit that "a date with nothing on it is a REAL zero". Ending
        // there would feed three or four zeros for days that have not happened
        // into both figures — and they do not merely thin out:
        //
        //   · strain is `weeklyLoad × monotony`, and monotony is `mean / sd`.
        //     Trailing zeros cut the mean and raise the sd, so the number falls
        //     by a different factor every day of the week. A running total like
        //     tonnage is comparable to itself mid-week; this is not.
        //   · the EWMA behind `acwr` decays the ACUTE side through every one of
        //     those zeros — `acute = 0 × λ + (1 − λ) × acute` — so a Wednesday
        //     would report a falling ratio off days that have not occurred.
        //
        // Reporting a shorter window beats reporting days that have not been
        // lived, so the live week reads to TODAY. That window crosses back into
        // last week, so it is no longer "this week's" strain and the hero says
        // as much — see `WeekHeroCard.liveNote`.
        //
        // What this does NOT do is make a low ratio impossible. A real rest day
        // inside the week decays the acute side exactly as an unlived one does,
        // and it should: that is a true reading about a week being rested
        // through. The clamp only stops the app inventing the input.
        //
        // ── AND WHY THIS ONE READ FILTERS ON `user_id` ─────────────────────
        // Against this file's own header, and on purpose. The rule up there is
        // about the TRAINING ledger, where the id in hand may not be the id the
        // rows were written under. This series is the READINESS domain's, it
        // has been filtered since v9, and the battery, the stress index and the
        // export all read it that way. An unfiltered copy would be a second
        // accumulator with different arithmetic, which is the thing the door
        // exists to prevent.
        //
        // The id comes from `localUserId()`, which reads `user_goals` and then
        // `plans` — NOT the ledger. So it is the right id whenever those rows
        // exist and were written under the same account as the sessions, which
        // is every real store and both preview seeds. It is NOT a guarantee:
        // a store holding sessions but no goals and no plan answers `""`, and
        // these two figures then come back empty while the tonnage and session
        // count beside them render from the unfiltered reads. That asymmetry is
        // the price of reading the battery's series instead of a second one,
        // and an empty load cell is a better failure than a disagreeing one.
        //
        // `min` guards the endpoint, and the `window.start <= today` test
        // guards the whole read: a future window would otherwise print today's
        // load figures under a future week's title with no note, since
        // `isCurrent` is false there and `liveNote` would not fire. No such
        // window is reachable from `capsules`, which stops at this week — this
        // is a fence around a gap, not a fix for a live defect.
        if window.start <= today,
           let load = try? database.loadSignal(userId: database.localUserId(), date: min(window.end, today)) {
            out.vitals.strain = load.strain
            out.vitals.acwr = load.acwr
        }

        // `period_start` is the week the report was written FOR. Any weekly row
        // whose span covers this window counts, because the web wrote some of
        // them against a Sunday start and some against a Monday one.
        out.report = (try? database.read { db in
            try ReportRow
                .filter(Column("period_start") <= window.end && Column("period_end") >= window.start)
                .order(Column("period_start").desc)
                .fetchOne(db)
        }) ?? nil

        return out
    }

    // MARK: - Reads

    /// The schedule as the plan resolves it, plus the goals row the week start
    /// comes from. Built exactly the way the Workout tab's This-week panel
    /// builds it — same overrides, same layout, same phase — so a day the panel
    /// calls Rest is a day History calls Rest.
    ///
    /// Nothing filters on `user_id`: the local store is ONE user's mirror, and
    /// filtering here silently answers "no sessions" whenever the id in hand is
    /// not the id the rows were written under — which is every preview, every
    /// screenshot, and any read that lands before auth resolves.
    private nonisolated static func scheduleContext(
        database: AppDatabase
    ) -> (schedule: ScheduleContext, goals: UserGoalRow?, ladder: LeverLadder, analysis: SessionAnalysis.Context) {
        let goals: UserGoalRow? = (try? database.read { db in try UserGoalRow.fetchOne(db) }) ?? nil
        let userId = database.localUserId()
        // One assembly of the plan, the phase and the catalogue
        // (`AppDatabase.scheduleContext`), shared with every other reader.
        let schedule = (try? database.scheduleContext(userId: userId)) ?? ScheduleContext(programId: "", phase: .cut)
        return (
            schedule,
            goals,
            (try? database.leverLadder(userId: userId)) ?? .empty,
            SessionAnalysis.Context(schedule: schedule, floors: (try? database.prFloors(userId: userId)) ?? [:])
        )
    }

    /// Can the schedule speak for this week?
    ///
    /// ── WHY A WEEK CAN HAVE NO PLANNED DAYS ─────────────────────────────────
    /// `Schedule.scheduleDayIn` owns a date by plan (W2), but the weekday
    /// LAYOUT applies to the active plan only — it has no memory of how last
    /// spring's block was laid out. Before Week 0 the block was PPL: six days,
    /// different splits, none of them in the active deck. Asking the current
    /// layout about those weeks does not fail, it answers confidently and
    /// wrongly, and the strip fills with hollow rings claiming
    /// five Onyx days were missed in a week the user actually trained six PPL
    /// ones.
    ///
    /// So the schedule is consulted from Week 0 forward and nowhere else. An
    /// earlier week draws what was LOGGED and leaves the rest blank, which is
    /// the whole of what this app can honestly say about it.
    private nonisolated static func isPlannable(_ window: WeekWindow, in schedule: ScheduleContext) -> Bool {
        Schedule.isPlannable(window.start, in: schedule)
    }

    private nonisolated static func dailyLogs(_ database: AppDatabase) -> [DailyLogRow] {
        (try? database.read { db in try DailyLogRow.order(Column("date")).fetchAll(db) }) ?? []
    }

    private nonisolated static func bodyRows(_ database: AppDatabase) -> [BodyCompositionRow] {
        (try? database.read { db in
            try BodyCompositionRow.order(Column("date"), Column("measured_at")).fetchAll(db)
        }) ?? []
    }

    private nonisolated static func dailyScores(_ database: AppDatabase) -> [DailyScoreRow] {
        (try? database.read { db in try DailyScoreRow.order(Column("date")).fetchAll(db) }) ?? []
    }

    /// Nil for an empty set rather than zero: a week with no scores has no mean,
    /// and 0 % battery is a reading somebody would act on.
    private nonisolated static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
