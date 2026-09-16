import Foundation
import GRDB
import OnyxCore

/// What the caller resolves that this store cannot: the plan and the lever.
///
/// ── WHAT USED TO BE HERE ────────────────────────────────────────────────────
/// `sessionVolumeKg` and `newPRsToday` were holes too, back when `volume.ts`
/// and `prEngine.ts` were unported. Both are read out of the store now —
/// `SessionVolume` over the day's sets, `personal_records` for the date — so a
/// caller can no longer hand in a tonnage that double-counts a unilateral pair.
///
///   · `goals` — `levers.ts` + `dailyTargets.ts`. The stored `user_goals`
///     figures are the BASELINE, and a lever moves them: scoring against the
///     baseline while the app displays Lever 1's 1,885 kcal is a 70-kcal
///     difference between the goal shown and the goal graded, every day,
///     invisibly. Left `nil`, the stored values are used and the day is graded
///     against the baseline — the pre-lever behaviour, wrong in a known
///     direction rather than in an unknown one. `DayPlan` resolves it.
public struct ScoringSupplements: Sendable, Equatable {
    public var goals: ResolvedGoals?
    /// Inside a planned maintenance / deload week (`maintenance.ts`). Lowers the
    /// workout-drain ceiling and the relative floor, and nothing else.
    public var isMaintenance: Bool
    /// The programme's prescription for the day (`prescribedFor`). `nil` drops
    /// the coverage component rather than inventing a plan.
    public var plannedExercises: Double?
    public var plannedSets: Double?

    public init(
        goals: ResolvedGoals? = nil,
        isMaintenance: Bool = false,
        plannedExercises: Double? = nil,
        plannedSets: Double? = nil
    ) {
        self.goals = goals
        self.isMaintenance = isMaintenance
        self.plannedExercises = plannedExercises
        self.plannedSets = plannedSets
    }
}

/// The day's targets after the lever and any day override have been applied.
public struct ResolvedGoals: Sendable, Equatable {
    public var calorie: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var steps: Double

    public init(calorie: Double, protein: Double, carbs: Double, fat: Double, steps: Double) {
        self.calorie = calorie
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.steps = steps
    }
}

// MARK: - Gathering

public extension AppDatabase {

    /// One day's `ScoringInputs`, read out of the local store.
    ///
    /// This is the data half of `computeForDate` — six queries that used to be
    /// six Supabase round trips from a Netlify function in UTC, and are now six
    /// reads off a file on the phone.
    ///
    /// `nil` is the GHOST GUARD: a past day with no underlying data at all must
    /// never get a score row. Trailing baselines and rest-day logic can
    /// otherwise fabricate one out of nothing, and a score-only "ghost day"
    /// pollutes every chart that reads the journey. Today accumulates live and
    /// is exempt.
    func scoringInputs(
        userId: String,
        date: String,
        hoursAwake: Double,
        isRestDay: Bool,
        todayISO: String,
        isToday: Bool = false,
        supplements: ScoringSupplements = ScoringSupplements()
    ) throws -> ScoringInputs? {
        try writer.read { db in
            let metrics = try DailyMetricRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .fetchOne(db)

            // ── THE NIGHT WINDOW, NOT THE CALENDAR DAY ──────────────────────
            // `start_time` is BEDTIME — the previous evening. Querying
            // `start_time >= date 00:00` matched NOTHING, so the scorer read
            // `sleepHours = 0` on every single day. That one bug produced
            // "Awaiting Sleep Data" beside a synced night, a 55 % wake battery,
            // and a July-15 score of 81 with the short-sleep gate never firing.
            // Longest session wins.
            let sleep = try NightWindow.range(date).flatMap { window in
                try SleepSessionRow
                    .filter(
                        Column("user_id") == userId
                            && Column("start_time") >= window.from
                            && Column("start_time") < window.to
                    )
                    .order(Column("duration_min").desc)
                    .fetchOne(db)
            }

            let nutrition = try NutritionEntryRow
                .filter(
                    Column("user_id") == userId && Column("date") == date
                        && Column("meal_type") == "daily"
                )
                .fetchOne(db)

            let water = try WaterIntakeRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .fetchAll(db)

            // ── SUPPLEMENTS ARE READ FOR PRESENCE, NOT FOR TICKS ────────────
            // The web counted `taken = true` rows, which made the score a
            // measure of how often the app was open after 22:00 rather than of
            // what was swallowed. Here the rows only answer "did anything happen
            // on this day", for the ghost guard.
            let supplementCount = try SupplementLogRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .fetchCount(db)

            let goals = try UserGoalRow.filter(Column("user_id") == userId).fetchOne(db)
            let sessions = try WorkoutSession
                .filter(Column("user_id") == userId && Column("date") == date)
                .fetchAll(db)

            // The trailing HRV / resting-HR baselines: seven days before this
            // one, for the RECOVERY SCORE (the battery reads the v9 z-signals
            // below instead). `nil` values are dropped rather than read as
            // zero — a missing reading degrades to "no baseline", never to a
            // wrong one.
            let trailingLogs = try DailyLogRow
                .filter(Column("user_id") == userId && Column("date") <= date)
                .order(Column("date").desc)
                .limit(8)
                .fetchAll(db)
            let todayLog = trailingLogs.first { $0.date == date }
            let trail = trailingLogs.filter { $0.date != date }
            let hrvBaseline = Self.mean(trail.compactMap(\.hrvMs))
            let rhrBaseline = Self.mean(trail.compactMap { $0.avgRestHeartRate.map(Double.init) })

            // ── THE DAY'S LATEST FATIGUE READING (a battery wellness item) ──
            // Folded as the tracker folds it — legacy keys filed by the kind of
            // day — and summarised by the LATEST slot, the tracker's own rule
            // for the day's one figure.
            let fatigueRows = try FatigueLogRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .fetchAll(db)
                .map { FatigueRow(slot: $0.slot, level: $0.level) }
            // `isRestDay` is the plan's word; a session logged on the day is
            // the athlete's, and it wins — the same rule `StressInputsBuilder`
            // resolves through `isTrainingDay`, inlined here because the
            // sessions are already in hand.
            let fatigueLevel = Fatigue.latest(
                Fatigue.foldRows(fatigueRows, isTraining: !isRestDay || !sessions.isEmpty)
            )?.level

            // ── READINESS v9: THE 49 DAYS BEHIND THE DAY ────────────────────
            // `readinessHistory` lays the rows on the calendar exactly as the
            // web's `readinessHistoryFor` does; the model is vector-proven.
            let signals = Readiness.signals(try Self.readinessHistory(db, userId: userId, date: date))
            // One number per RECOGNISED muscle — the max across its sides and
            // sub-regions — then the mean of those. Zeros included: a muscle
            // rated "not sore" is an answer. No rows is no answer.
            //
            // It was a mean over ROWS, which made the denominator grow with the
            // number of ways a complaint was described rather than with the
            // number of complaints. Laterality would have re-based every
            // historical battery score on that rule, and rows whose muscle_group
            // is not one of the ten — the demo seed writes 'Quadriceps' and
            // 'Lats' — were being counted despite never being readable as a
            // rating. The web applies the identical fold in
            // the web app's `lib/recovery/soreness.ts`; a golden vector pins the two.
            //
            // The store grew `side` and `sub_region` in W9 (`v28`), so a day
            // can now hold a left row and a right row for one muscle. Nothing
            // here changed and nothing here needed to: the fold takes the MAX
            // within a muscle, so a pair peaks exactly where the single
            // whole-muscle row at the same severity peaked, and the battery
            // cannot move because a rating was split in two.
            let domsSeverity = Self.foldDomsSeverity(
                try DomsLogRow.filter(Column("user_id") == userId && Column("date") == date)
                    .fetchAll(db)
            )

            let hasAnything = metrics != nil || sleep != nil || nutrition != nil
                || !water.isEmpty || supplementCount > 0 || !sessions.isEmpty || todayLog != nil
            if !isToday && date != todayISO && !hasAnything { return nil }

            // ── THE DAY'S SETS ──────────────────────────────────────────────
            // Scoped by the parent SESSION rather than by a set's own timestamp:
            // a back-dated session is written today, so filtering on the set
            // would miss it entirely.
            let daySets = try Self.sets(db, sessionIds: sessions.map(\.id))
            let counted = Self.countSets(daySets)

            // ── THE FORMER HOLES ────────────────────────────────────────────
            // Tonnage through `SessionVolume`, which scores a unilateral pair
            // ONCE at the weaker side. Records by the date they were achieved —
            // the ledger is the record of a PR, and the local set rows carry no
            // `is_pr` at all.
            let sessionVolumeKg = Self.volume(daySets)
            let prCount = try PersonalRecordRow
                .filter(Column("user_id") == userId && Column("achieved_on") == date)
                .fetchCount(db)

            // The day's principal session carries its character — the day key
            // feeds the workout score and the RPE feeds the battery, and on a
            // double-session day the second, lighter session's effort rating
            // should not describe the day.
            //
            // ── AND IT IS RANKED BY DURATION, NOT TONNAGE ───────────────────
            // The web ranked by `total_volume_kg`. The local session row has no
            // such column and cannot have one until `volume.ts` ports (Track D
            // item 5), so the longest session stands in. On a single-session day
            // — which is every day the programme prescribes — the two agree
            // exactly, because there is one candidate. They can differ only on a
            // double day, and duration is at least a fact this store actually
            // holds rather than a tonnage guessed from it.
            let hardest = sessions.max { ($0.durationMin ?? 0) < ($1.durationMin ?? 0) }
            let dayKey = sessions.first(where: { $0.dayKey != nil })?.dayKey

            // ── YOUR OWN NORMAL FOR THIS SPLIT ──────────────────────────────
            // The last six sessions of the same day key before this date, at
            // full effort — a maintenance week's lighter sessions would drag
            // the baseline down and make the next real week look like an
            // overreach. If EVERY candidate is a maintenance session the filter
            // is dropped rather than answering zero, which `workoutDrain`
            // reads as "no history, full charge". As `computeForDate` read it.
            var trailingAvgVolumeKg = 0.0
            if !sessions.isEmpty {
                var priorQuery = WorkoutSession
                    .filter(Column("user_id") == userId && Column("date") < date)
                if let dayKey { priorQuery = priorQuery.filter(Column("day_key") == dayKey) }
                let prior = try priorQuery.order(Column("date").desc).limit(6).fetchAll(db)
                let priorSets = try Self.sets(db, sessionIds: prior.map(\.id))
                var bySession: [String: [WorkoutSet]] = [:]
                for set in priorSets { bySession[set.sessionId, default: []].append(set) }
                let candidates = prior
                    .map { (date: $0.date, volume: Self.volume(bySession[$0.id] ?? [])) }
                    .filter { $0.volume > 0 }
                let ladder = try Self.leverLadder(db, userId: userId, goals: .some(goals))
                let phases = try Self.planCatalogue(db, userId: userId).phases
                let fullEffort = candidates.filter {
                    !Maintenance.isMaintenanceDate($0.date, today: todayISO, ladder: ladder, phases: phases)
                }
                let trailing = (fullEffort.isEmpty ? candidates : fullEffort).map(\.volume)
                trailingAvgVolumeKg = trailing.isEmpty ? 0 : trailing.reduce(0, +) / Double(trailing.count)
            }

            // ── THE DAY'S OWN CONTEXT ───────────────────────────────────────
            // The day's stamp first; the current setting only for a date its
            // range covers. Last Tuesday keeps the context it was lived in,
            // so re-scoring it today does not grade it against how you feel
            // now — which is what one global `context_mode` used to do.
            let stamped = Context.fromDayLabel(todayLog?.nutritionException)
            let setting = Context.fromSetting(goals?.contextMode)
            let effectiveMode: ContextMode = stamped != .normal
                ? stamped
                : Context.rangeCovers(setting, since: goals?.contextSince, date: date, today: todayISO) ? setting : .normal
            // ponytail: computeForDate also stamps the range's label onto the
            // day's row; that write lands with the context editor (2.6).

            let g = goals
            let resolved = supplements.goals ?? ResolvedGoals(
                calorie: Double(g?.calorieGoal ?? 0),
                // `0` is the preset's own convention for "no macro target":
                // score.ts counts a macro only when its goal is > 0.
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

            inputs.calories = nutrition?.calories ?? 0
            inputs.proteinG = nutrition?.proteinG ?? 0
            inputs.carbsG = nutrition?.carbsG ?? 0
            inputs.fatG = nutrition?.fatG ?? 0
            inputs.calorieGoal = resolved.calorie
            inputs.proteinGoalG = resolved.protein
            inputs.carbsGoalG = resolved.carbs
            inputs.fatGoalG = resolved.fat
            // A declared exception grades the day on protein alone. Read from
            // the DAY's own row, so back-filling the flag onto a past date and
            // recomputing gives that date the score it would have had if it had
            // been flagged at the time.
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
            // The prescription MINUS what was deliberately ghosted, floored at
            // zero: a set marked skipped on purpose is neither numerator nor
            // denominator, exactly as a prescribed rest day is neither.
            inputs.plannedSets = supplements.plannedSets.map { max(0, $0 - Double(counted.ghostSets)) }
            inputs.loggedExercises = Double(counted.exercises)
            inputs.sessionSets = Double(counted.workingSets)
            inputs.failureSets = Double(counted.failureSets)

            inputs.waterMl = water.reduce(0) { $0 + $1.amountMl }
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
            // Derived from `hoursAwake` on a 07:00 wake convention rather than
            // from a fixed zone, because the device's own hour is the only one
            // that means anything to the person living the day.
            inputs.localHour = min(23, 7 + hoursAwake.rounded())
            return inputs
        }
    }
}

// MARK: - Set arithmetic

extension AppDatabase {

    struct SetCounts {
        var exercises = 0
        var workingSets = 0
        var ghostSets = 0
        var failureSets = 0
    }

    static func sets(_ db: Database, sessionIds: [String]) throws -> [WorkoutSet] {
        guard !sessionIds.isEmpty else { return [] }
        return try WorkoutSet.filter(sessionIds.contains(Column("session_id"))).fetchAll(db)
    }

    static func countSets(_ rows: [WorkoutSet]) -> SetCounts {
        var counts = SetCounts()

        var exercises = Set<String>()
        var working = Set<String>()
        var ghosts = Set<String>()
        for row in rows {
            // ── GHOSTS LEAVE BOTH SIDES OF THE RATIO ────────────────────────
            // A ghost is a set the plan asked for that was deliberately not
            // done. Excluding it from the numerator while the prescription still
            // supplied the denominator graded a deliberate decision as an
            // incomplete session, and docked up to twelve points for it.
            guard Self.isWorkingSet(row.setType) else {
                if row.setType == "ghost" { ghosts.insert(row.pairId ?? row.id) }
                continue
            }
            exercises.insert(row.exerciseId)
            // Unilateral L/R sub-sets share a `pair_id` and are ONE set.
            working.insert(row.pairId ?? row.id)
            if row.setType == "failure" { counts.failureSets += 1 }
        }
        counts.exercises = exercises.count
        counts.workingSets = working.count
        counts.ghostSets = ghosts.count
        return counts
    }

    /// `isWorkingSet`, from `lib/training/setTags.ts`.
    ///
    /// One line, and it stays one line: "not a working set" was written as
    /// `setType !== 'warmup'` in roughly twenty places, so adding `ghost` meant
    /// finding all twenty and getting all twenty right. The ones that were
    /// missed failed silently and in the worst direction — a ghost became a
    /// baseline, and the coach paced against a set explicitly marked as not
    /// counting.
    static func isWorkingSet(_ setType: String?) -> Bool {
        setType != "warmup" && setType != "ghost"
    }

    /// `sessionVolumeKg` over local set rows: a unilateral pair scored once,
    /// at the weaker side. The widget builder reads through the same door.
    static func volume(_ sets: [WorkoutSet]) -> Double {
        SessionVolume.sessionVolumeKg(sets.map {
            VolumeSet(
                weightKg: $0.weightKg, reps: Double($0.reps),
                side: (try? SyncTranslation.side($0.side)) ?? nil, pairId: $0.pairId, setType: $0.setType
            )
        })
    }

    /// Mean severity over DISTINCT RECOGNISED muscles, max within each.
    ///
    /// A 1:1 port of `foldDomsSeverity` in the web app's `lib/recovery/soreness.ts`.
    /// Max rather than mean within a muscle, deliberately: "left quad severe,
    /// right quad fine" is a severe quad, and averaging it to moderate reports
    /// a day nobody had.
    static func foldDomsSeverity(_ rows: [DomsLogRow]) -> Double? {
        var peak: [String: Int] = [:]
        for row in rows where DomsMuscles.recognised.contains(row.muscleGroup) {
            peak[row.muscleGroup] = max(peak[row.muscleGroup] ?? 0, row.severity)
        }
        guard !peak.isEmpty else { return nil }
        return Double(peak.values.reduce(0, +)) / Double(peak.count)
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
