import Foundation
import GRDB
import OnyxCore

/// Everything the Today screen draws that is not the arrangement, built in one
/// read from the mirror.
///
/// ── ONE BUILD, FOUR CARDS ────────────────────────────────────────────────────
/// The web dashboard ran nine hooks with nine caches and nine invalidation
/// lists. Here the tiles are the widget snapshot (`WidgetSnapshotBuilder`, the
/// same payload the Home Screen draws — one implementation, two surfaces), and
/// the three cards under the grid derive from windows the snapshot already
/// needed or from a couple of extra table reads. The whole thing is rebuilt
/// after any commit; on a phone-sized mirror it is a few milliseconds.
public struct TodayFeed: Sendable, Equatable {
    public var snapshot: OnyxSnapshot
    /// The coach headline — scored readiness made aware of the plan.
    public var readiness: ReadinessResult?
    /// The phase, as three numbers: the rate, the arrival and the week's ledger.
    ///
    /// ── REBOUND IN W12 ──────────────────────────────────────────────────────
    /// This used to be built here from a 28-day read of `daily_logs.weight_kg`,
    /// while the widget snapshot built its own weight series from the
    /// `body_composition` ledger — two regressions over two different sets of
    /// readings, printing one rate each, on the same screen the moment the
    /// Trajectory tile landed. It is now `snapshot.trajectory.board`: one fit,
    /// one arrival date, one pace, drawn by the row and by the tile.
    public var goalBoard: GoalBoard
    public var weekSoFar: WeekSoFarSummary
    /// The week's sets on the body, against what the plan asked for.
    ///
    /// The `muscle` tile draws this by FAMILY and against the week's own
    /// busiest family, which answers "where did the week go". It cannot answer
    /// "is the week done", because a family bar has no target behind it. That
    /// second question is what the tile's sheet is for, and it needs the
    /// landmark-level counts and the landmark-level targets the widget payload
    /// has never carried.
    public var muscleFocus: MuscleFocusSummary
    /// The week-complete CTA fires on the first day of a new week, once every
    /// training day the previous week asked for was logged.
    public var weeklySummaryReady: Bool
    /// Last week's start, for the CTA's destination.
    public var lastWeekStart: String

    /// The Mega Widget's sentence (W7) — the payload's, not a second one.
    ///
    /// Computed and not stored, for the reason `volumeByFamily` is: the tile
    /// on the Home Screen reads `snapshot.coach` and the tile in this grid
    /// reads the same field through the same snapshot. A second copy on this
    /// struct is a second thing that can go stale.
    public var coach: String? { snapshot.coach }

    public init(snapshot: OnyxSnapshot, readiness: ReadinessResult?, goalBoard: GoalBoard, weekSoFar: WeekSoFarSummary, weeklySummaryReady: Bool, lastWeekStart: String, muscleFocus: MuscleFocusSummary = MuscleFocusSummary()) {
        self.snapshot = snapshot
        self.readiness = readiness
        self.goalBoard = goalBoard
        self.weekSoFar = weekSoFar
        self.weeklySummaryReady = weeklySummaryReady
        self.lastWeekStart = lastWeekStart
        self.muscleFocus = muscleFocus
    }
}

public struct WeekSoFarSummary: Sendable, Equatable {
    public var weekStart: String
    public var weekNumber: Int
    /// Days elapsed including today, 1…7.
    public var dayOfWeek: Int
    public var current: WeekTotals
    public var previous: WeekTotals
    public var change: WeekChange?
    public var sessionTarget: Int

    public init(weekStart: String, weekNumber: Int, dayOfWeek: Int, current: WeekTotals, previous: WeekTotals, change: WeekChange?, sessionTarget: Int) {
        self.weekStart = weekStart
        self.weekNumber = weekNumber
        self.dayOfWeek = dayOfWeek
        self.current = current
        self.previous = previous
        self.change = change
        self.sessionTarget = sessionTarget
    }
}

public struct TodayFeedBuilder: Sendable {
    public let database: AppDatabase
    public let userId: String
    public let timeZone: TimeZone

    /// Four weeks: long enough that the weight regression has twenty-odd
    /// readings to fit, short enough that a rate is about THIS phase. The
    /// Insight Coach wanted two months for its correlations; it is gone (§W5.3)
    /// and so is the read.
    static let windowDays = 28

    public init(database: AppDatabase, userId: String, timeZone: TimeZone = .current) {
        self.database = database
        self.userId = userId
        self.timeZone = timeZone
    }

    public func build(now: Date = Date()) throws -> TodayFeed {
        let widgets = WidgetSnapshotBuilder(database: database, userId: userId, timeZone: timeZone)
        let snapshot = try widgets.build(scope: .full, now: now)
        let today = snapshot.date

        // The plan, resolved the way the snapshot resolved it, for "is this a
        // training day" over last week.
        let rows = try widgets.fetch(date: today, trendFrom: today)
        let goals = rows.goals
        let schedule = rows.schedule
        let programId = schedule.programId

        let weekStart = WeekWindow(containing: today, startDay: Week.startDay(fromEndDay: goals?.weekEndDay), today: today).start
        let lastWeekStart = ISODate.addDays(weekStart, -7) ?? weekStart
        let lastWeekEnd = ISODate.addDays(weekStart, -1) ?? weekStart
        let windowFrom = ISODate.addDays(today, -Self.windowDays) ?? today

        let user = Column("user_id") == userId
        let (weekCur, weekPrev, lastWeekLogged, weekSets, volumeOverrides) = try database.writer.read { db in
            // Sessions with their volume, the same way the snapshot totals them.
            let sessions = try WorkoutSession.filter(user && Column("date") >= windowFrom && Column("date") <= today)
                .order(Column("date")).fetchAll(db)
            let ids = sessions.map(\.id)
            let sets = ids.isEmpty ? [] : try WorkoutSet.filter(ids.contains(Column("session_id"))).fetchAll(db)
            var setsBySession: [String: [WorkoutSet]] = [:]
            for s in sets { setsBySession[s.sessionId, default: []].append(s) }
            let isBodyweight = try SessionEditing.bodyweightResolver(db)
            let volumes = try sessions.map { session in
                (session, WidgetSnapshotBuilder.volume(
                    setsBySession[session.id] ?? [],
                    bodyWeightKg: try SessionEditing.bodyWeightKg(db, userId: session.userId, on: session.date),
                    isBodyweight: isBodyweight
                ))
            }
            let nights = try SleepSessionRow.filter(user).order(Column("start_time").desc).limit(30).fetchAll(db)
            let scores = try DailyScoreRow.filter(user && Column("date") >= lastWeekStart && Column("date") <= today).fetchAll(db)
            func totals(_ from: String, _ to: String) -> WeekTotals {
                let inRange = { (iso: String) in iso >= from && iso <= to }
                let wk = volumes.filter { inRange($0.0.date) }
                let sl = nights.filter { inRange(LogicalDay.iso($0.startTime, calendar: self.calendar)) }
                    .map { Double($0.durationMin) }.filter { $0 > 0 }
                let sc = scores.filter { inRange($0.date) }.map { Double($0.score) }
                let mean = { (xs: [Double]) -> Double? in xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
                return WeekTotals(volumeKg: wk.reduce(0) { $0 + $1.1 }, sessions: wk.count, sleepMin: mean(sl), score: mean(sc))
            }
            let logged = Set(sessions.filter { $0.date >= lastWeekStart && $0.date <= lastWeekEnd }.map(\.date))
            // THIS week's sets, for the muscle focus. The 28-day read above is
            // already in hand; narrowing it costs a filter rather than a query.
            let weekSessionIds = Set(sessions.filter { $0.date >= weekStart && $0.date <= today }.map(\.id))
            let weekSets = sets.filter { weekSessionIds.contains($0.sessionId) }
            let overrides = try PlanPhaseVolumeRow
                .filter(user && Column("plan_id") == programId && Column("phase") == schedule.phase.rawValue)
                .fetchAll(db)
            return (
                totals(weekStart, today), totals(lastWeekStart, lastWeekEnd), logged, weekSets,
                Dictionary(overrides.map { ($0.muscle, $0.targetSets) }, uniquingKeysWith: { _, last in last })
            )
        }

        let base = snapshot.readiness.flatMap { r in
            ReadinessResult.Level(rawValue: r.level).map { ReadinessResult(level: $0, label: r.label, color: r.color, reason: r.reason) }
        }
        let readiness = ScheduleReadiness.apply(base, ScheduleReadinessContext(
            dayLabel: snapshot.workout.isRestDay ? nil : snapshot.workout.label,
            workoutToday: snapshot.workout.logged,
            contextMode: goals?.contextMode ?? "normal",
            // Both were constants inside `ScheduleReadiness` until this wave:
            // a hardcoded July fortnight and a hardcoded plan name. The rows
            // answer now — a `reentry` override the athlete can set on any
            // date, and the label of whichever plan owns today.
            reentry: Schedule.isReentry(schedule, today),
            programLabel: Schedule.planLabel(owning: today, in: schedule)
        ))

        // The snapshot is built at `.full` scope above, so the trajectory is
        // always there; the empty board is the shape a build with no readings
        // and no phase goals would produce anyway.
        let goalBoard = snapshot.trajectory?.board ?? GoalBoard()

        let weekSoFar = WeekSoFarSummary(
            weekStart: weekStart,
            weekNumber: Int(Week.number(ofWeekStart: weekStart, anchor: schedule.weekZeroStart)),
            dayOfWeek: ((ISODate.dayNumber(today) ?? 0) - (ISODate.dayNumber(weekStart) ?? 0)) + 1,
            current: weekCur,
            previous: weekPrev,
            change: WeekSoFar.biggestChange(weekCur, weekPrev),
            sessionTarget: snapshot.week.sessionTarget ?? Schedule.sessionTargetIn(schedule)
        )
        let weeklySummaryReady = today == weekStart
            && WeekReady.isComplete(weekStart: lastWeekStart, today: today)
            && WeekReady.isReady(weekStart: lastWeekStart, logged: lastWeekLogged, today: lastWeekEnd) {
                Schedule.isTrainingDayIn(schedule, $0)
            }

        let muscleFocus = Self.muscleFocus(
            weekStart: weekStart, sets: weekSets, names: rows.exerciseNames,
            phase: schedule.phase, overrides: volumeOverrides
        )

        return TodayFeed(
            snapshot: snapshot, readiness: readiness, goalBoard: goalBoard,
            weekSoFar: weekSoFar, weeklySummaryReady: weeklySummaryReady, lastWeekStart: lastWeekStart,
            muscleFocus: muscleFocus
        )
    }

    /// The week's weighted sets per landmark, against the week's targets.
    ///
    /// ── ONE ACCUMULATOR, THREE SURFACES (F7) ────────────────────────────────
    /// A primary mover earns a full set, a secondary earns half, and a muscle
    /// never earns both for one set — `MuscleCredit.weightedSets`, which the
    /// widget tile and the Trends atlas card also call. Before W3 each of the
    /// three counted the week for itself, in a different currency, at a
    /// different grain, off a different week start; the tile and the sheet it
    /// opened could show a different number for the same session, and did.
    ///
    /// A ghost set counts for nothing, here as everywhere. Warm-ups DO count —
    /// see `MuscleDistribution`, which states the same rule for a live session.
    ///
    /// `public` since W1a: the Week Wrapped sheet is the FOURTH surface, and it
    /// is built in `Features/Workout`, outside this module. Widening the
    /// visibility is the whole point of having one accumulator — a fourth
    /// caller that cannot reach it writes a fourth counter instead, which is
    /// the state this function was created to end.
    public static func muscleFocus(
        weekStart: String, sets: [WorkoutSet], names: [String: String],
        phase: ProgramPhase, overrides: [String: Int]
    ) -> MuscleFocusSummary {
        let credit = MuscleCredit.weightedSets(
            exerciseNames: sets
                .filter { $0.setType != "ghost" }
                .compactMap { names[$0.exerciseId] }
                .filter { !$0.isEmpty }
        )
        // The targets are `plan_phase_volume` rows and nothing else since W2:
        // a muscle with no row has no target, and the sheet says 0 rather than
        // borrowing another athlete's MEV.
        let rows = LandmarkMuscle.allCases.map { muscle in
            MuscleFocusRow(
                muscle: muscle,
                // One decimal: the credit is halves, and a raw Double prints
                // 8.500000000000002 often enough to matter.
                sets: ((credit[muscle] ?? 0) * 10).rounded() / 10,
                target: overrides[muscle.rawValue] ?? 0
            )
        }
        return MuscleFocusSummary(weekStart: weekStart, rows: rows)
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }
}
