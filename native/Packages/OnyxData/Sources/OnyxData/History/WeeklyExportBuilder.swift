import Foundation
import GRDB
import OnyxCore

/// The rows behind one week's export, shaped into `WeeklyExportInput`.
///
/// A port of the FETCH half of `useWeeklyExport` (the web app's `lib/hooks/useWeeklyLoop.ts`:
/// `fetchRange`, `fetchTrendLedger`, `toDays`, `withNutrients`, `toSessions`,
/// `toBodyComp`, `toCardio`, `tonnageRows`, `weekPayload`). The string itself is
/// OnyxCore's `WeeklyExport.build`, vector-proven; the whole job here is
/// reading the same tables with the same filters, order and field mapping so
/// the same rows render the same bytes.
///
/// ── WHAT THE MIRROR DOES NOT HOLD ───────────────────────────────────────────
/// `workout_sets.is_pr / quality`, `workout_sessions.split_day /
/// total_volume_kg / set_count / avg_bpm / calories_burned`, `exercises.
/// muscle_groups` and the localStorage rest-target overrides are not mirrored.
/// (`exercise_order` WAS on that list. `v16.exerciseOrder` tracks it and
/// `applyPulledSets` brings the web's down, so the mirror holds it now — and
/// this builder READS it, as of v4.1. It did not, on the reasoning that "the
/// export orders its sets the way it always has and the vectors say so". The
/// vectors said so because they were generated from the same wrong order:
/// grouping by first appearance in `fold_order` puts a pulled session's
/// movements in the PULLER's arrival order, so the 2026-08-31 Upper A exported
/// with Face Pull first and Chest Press last. `SessionHistoryStore` had already
/// been fixed for exactly this in §U4.5; this was the last reader still
/// grouping the wrong way.)
/// Each is handled where it is read, and none is invented: volumes and set
/// counts are recomputed from the sets the way the web wrote them, PR lines are
/// reconstructed from the standing `personal_records` rows for the session, and
/// the rest target is the plan's own.
public struct WeeklyExportBuilder: Sendable {
    let database: AppDatabase
    let userId: String
    /// Wall clock for the timestamp strings the renderer reads "HH:MM" out of.
    ///
    /// ── THE PHONE'S OWN ZONE, NOT UTC ───────────────────────────────────────
    /// It defaulted to UTC, and the reason was byte parity: PostgREST handed
    /// the web `+00:00` strings and the web printed their hours as they stood,
    /// so the Swift port had to print the same. The web is gone (W6) and with
    /// it the only reader that needed the same bytes.
    ///
    /// What was left was a document that said an athlete in Asia/Jerusalem went
    /// to bed at 20:41 and woke at 04:02, and a 19:00 session stamped 16:00.
    /// Every timestamp in this document is now the wall clock the day actually
    /// happened on. Tests pin an explicit zone; nothing else passes one.
    let timeZone: TimeZone

    public init(database: AppDatabase, userId: String, timeZone: TimeZone = .current) {
        self.database = database
        self.userId = userId
        self.timeZone = timeZone
    }

    // MARK: - Entry

    public func input(weekStart: String, today: String = LogicalDay.today()) throws -> WeeklyExportInput {
        let weekEnd = ISODate.addDays(weekStart, 6) ?? weekStart
        let rows = try fetch(weekStart: weekStart, weekEnd: weekEnd)
        let ctx = rows.schedule
        let phase = ctx.phase
        let program = Schedule.programForContext(ctx, weekStart).program
        let goals = rows.goals

        let days = try withNutrients(try toDays(weekStart: weekStart, rows, ctx: ctx), rows)
        let sessions = try toSessions(rows, ctx: ctx, phase: phase)

        /* ── ONE PHYSICAL WALK IS ONE ROW ───────────────────────────────────
           `cardio_logs` accumulates duplicates: the HealthKit ingest can import
           the same `HKWorkout` again after a re-authorisation or a restore, and
           it keys on nothing that would stop it, so Friday exported 23 copies
           of one walk and Saturday 8. Every total in the document — bouts,
           minutes, kcal — was multiplied by however many times the import ran.

           Deduped on the three things that identify a bout PHYSICALLY: when it
           started, how long it lasted, how far it went. Two genuinely distinct
           walks that agree on all three are the same walk. The row kept is the
           first, so an id that other tables may reference survives. */
        var seenBouts = Set<String>()
        var dedupedCardio: [CardioLogRow] = []
        for c in rows.cardio {
            /* A row with NO start is never deduped. `cardio_logs.created_at` is
               nullable with no default, and a key built from three absences is
               the same key for every such row — a Monday cycle and a Friday
               swim would collapse into one, and the document would report the
               collapse as a duplicate removed. */
            guard let started = c.createdAt else { dedupedCardio.append(c); continue }
            // Date and kind ride in the key too: a bout is identified by what
            // it was and when, not by three numbers that can coincide.
            let key: String = [
                c.date, c.kind, String(started.timeIntervalSince1970),
                c.durationMin.map { String($0) } ?? "",
                c.distanceM.map { String($0) } ?? "",
            ].joined(separator: "|")
            if seenBouts.insert(key).inserted { dedupedCardio.append(c) }
        }

        var anomalies: [String] = []
        let removed = rows.cardio.count - dedupedCardio.count
        if removed > 0 { anomalies.append("duplicate cardio removed \(removed)") }
        // A night whose `daily_logs.sleep_minutes` was absent and whose
        // duration this builder rebuilt from `sleep_sessions`. Stated, because
        // a figure the document assembled is not a figure the watch reported.
        // A stored ZERO is what `sleepMinutesOf` treats as absent, so the
        // counter has to read it the same way or a rebuilt duration goes
        // unreported on exactly the nights the column was written badly.
        let loggedSleep = Dictionary(
            rows.logs.map { ($0.date, $0.sleepMinutes.flatMap { $0 > 0 ? $0 : nil }) },
            uniquingKeysWith: { _, b in b })
        let filledSleep = days.filter { d in
            d.sleepMin != nil && (loggedSleep[d.date] ?? nil) == nil
        }.count
        if filledSleep > 0 { anomalies.append("missing sleep durations filled \(filledSleep)") }

        let dates = days.map(\.date)
        let targetPeriods = Levers.leverPeriods(
            dates,
            today: today,
            fallback: LeverGoals(
                calorie: Double(goals?.calorieGoal ?? 0),
                protein: goals?.proteinGoalG.map(Double.init),
                carbs: goals?.carbsGoalG.map(Double.init),
                fat: goals?.fatGoalG.map(Double.init),
                steps: goals?.stepsGoal.map(Double.init)
            ),
            in: rows.ladder,
            dailyTargets: rows.dailyTargets.map(DailyTarget.init)
        )

        let sessionDateById = Dictionary(rows.sessions.map { ($0.id, $0.date) }, uniquingKeysWith: { _, b in b })
        let doms: [ExportDoms] = try Self.stableSorted(
            rows.doms.map { r in
                try make([
                    "date": r.date, "muscle": r.muscleGroup, "severity": Double(r.severity),
                    "sourceLabel": j(r.sourceDayKey.map { key in program.day(key: key)?.label ?? key }),
                    "sourceDate": j(r.sourceSessionId.flatMap { sessionDateById[$0] }),
                ])
            }
        ) { (a: ExportDoms, b: ExportDoms) in (a.date, a.muscle) < (b.date, b.muscle) }

        // The export folds each day the way the scorer does: a session logged
        // on the day makes it a training day, whatever the calendar said.
        let loggedDates = Set(rows.sessions.map(\.date))
        let fatigue: [ExportFatigue] = try Self.stableSorted(
            rows.fatigue.compactMap { r -> (date: String, key: FatigueSlot, level: Int)? in
                let isTraining = loggedDates.contains(r.date) || Schedule.isTrainingDayIn(ctx, r.date)
                guard let key = Fatigue.normalizeSlot(r.slot, isTraining: isTraining) else { return nil }
                return (r.date, key, r.level)
            }
        ) { a, b in
            a.date != b.date ? a.date < b.date
                : Fatigue.slots.firstIndex(of: a.key)! < Fatigue.slots.firstIndex(of: b.key)!
        }.map { r in
            try make([
                "date": r.date, "slot": r.key.label, "level": Double(r.level),
                "label": Fatigue.level(r.level)?.label ?? String(r.level),
            ])
        }

        /* THE HEAD ROW — self-reported psychological stress, an EVENT log.
           The slot is derived from the event's time, never chosen, so it
           passes through as stored. The word comes from `PsychStress.levels`
           for the same reason fatigue carries one: a bare 4 is not readable
           and a bare "Strained" cannot be compared.
           Ordered by date then by the order the day HAPPENED in — the same
           key `PsychStress.sorted` uses: a timed event by its minute of the
           day in the user's zone, a legacy row without a time at its slot's
           lower boundary, `created_at` breaking ties. A slot the vocabulary
           does not name sorts last rather than first. */
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func minute(_ r: StressLogRow) -> Int {
            if let at = r.loggedAt { return PsychStress.minuteOfDay(at, calendar: calendar) }
            return StressSlot(rawValue: r.slot)?.startMinutes ?? 24 * 60
        }
        let stressOrdered = Self.stableSorted(rows.stress) { a, b in
            if a.date != b.date { return a.date < b.date }
            if minute(a) != minute(b) { return minute(a) < minute(b) }
            return a.createdAt < b.createdAt
        }
        var stress: [ExportStress] = []
        for r in stressOrdered {
            let word: String = PsychStress.levels.first { $0.value == r.level }?.label ?? String(r.level)
            // `PsychStress.tags` drops anything the vocabulary does not know,
            // so a tag written by a newer build never reaches the document as
            // a word this one cannot explain.
            let raw = (try? JSONDecoder().decode([String].self, from: Data(r.tags.raw.utf8))) ?? []
            let tags: [String] = PsychStress.tags(raw).map { $0.rawValue }
            var row: [String: Any] = [:]
            row["date"] = r.date
            row["slot"] = r.slot
            row["time"] = j(r.loggedAt.map(clock))
            row["level"] = Double(r.level)
            row["label"] = word
            row["tags"] = tags
            row["note"] = j(r.note)
            stress.append(try make(row))
        }

        return try make([
            "weekStart": weekStart, "weekEnd": weekEnd,
            "weekLabel": Week.label(ofWeekStart: weekStart, anchor: ctx.weekZeroStart, phases: ctx.phases),
            "programLabel": Self.programLabel(ctx, weekStart: weekStart, phase: phase),
            "calorieGoal": j(goals?.calorieGoal.map(Double.init)),
            "proteinGoalG": j(goals?.proteinGoalG.map(Double.init)),
            "stepsGoal": j(goals?.stepsGoal.map(Double.init)),
            "sleepGoalHours": j(goals?.sleepGoalHours),
            "waterGoalMl": j(goals?.waterGoalMl.map(Double.init)),
            "phaseLabel": phase == .bulk ? "Bulk" : "Cut",
            "targetPeriods": targetPeriods.map(Self.encodeToJSON),
            "days": days.map(Self.encodeToJSON),
            "sessions": sessions.map(Self.encodeToJSON),
            "volumeByMuscle": volumeByMuscle(rows, phase: phase),
            "doms": doms.map(Self.encodeToJSON),
            "fatigue": fatigue.map(Self.encodeToJSON),
            "stress": stress.map(Self.encodeToJSON),
            "tonnageByMuscle": tonnageByMuscle(rows),
            "bodyComp": toBodyComp(rows, weekStart: weekStart),
            "cardio": dedupedCardio.map { c in
                [
                    "date": c.date, "kind": c.kind, "distanceM": j(c.distanceM), "durationMin": j(c.durationMin),
                    // Pre-migration rows only have `kcal`; it always held the ACTIVE figure.
                    "kcal": j(c.activeKcal ?? c.kcal), "totalKcal": j(c.totalKcal), "avgHr": j(c.avgHr), "effort": j(c.effort),
                    "elevationM": j(c.elevationM),
                    // The athlete's own wall clock, like every other timestamp
                    // in this payload. It was UTC — an `ISO8601DateFormatter`
                    // with no zone — while `stamp` two fields over was already
                    // local, so a bout and the session it sat beside disagreed
                    // about what time it was by three hours.
                    "startedAt": j(c.createdAt.map(stamp)),
                    "source": (c.fromHealthkit ?? false) ? "health" : "manual",
                ] as [String: Any]
            },
            "supplementProtocol": supplementStack(rows.customs),
            "ledger": ledger(rows, weekStart: weekStart, ctx: ctx).map(Self.encodeToJSON),
            // FORCED. `LeverLadder.rungs` is empty for this athlete — nothing
            // writes `target_profiles.kind`, so every profile defaults to `.day`
            // and `NutritionLever.init?` drops it — and a custom rung carries a
            // daily target with no anchor behind it. See the constant's own
            // comment in `WeeklyExport`.
            "leverBaselineKcal": WeeklyExport.leverBaselineKcal,
            "anomalies": anomalies,
        ])
    }

    // MARK: - The fetch

    /// The plan the user is RUNNING — stored layout and overrides, never a
    /// default (the "Server-side plan resolution" rule) — with the phase the
    /// week was run in.
    public func scheduleContext(weekStart: String) throws -> ScheduleContext {
        try database.read { db in
            try schedule(db, goals: try UserGoalRow.filter(Column("user_id") == userId).fetchOne(db), weekStart: weekStart)
        }
    }

    /// The context, with the PHASE the exported week ran under rather than
    /// the one selected today — a bulk week exported during a cut is a bulk.
    func schedule(_ db: Database, goals: UserGoalRow?, weekStart: String) throws -> ScheduleContext {
        var ctx = try AppDatabase.scheduleContext(db, userId: userId, goals: .some(goals))
        ctx.phase = Phases.weekPhase(weekStart: weekStart, in: ctx.phases)?.kind == .bulk ? .bulk : .cut
        return ctx
    }

    /// "Onyx-5 Cut" / "Push/Pull/Legs (legacy)" — the plan that owned the
    /// week, by its own name. Until W2 this compared the week against the
    /// compiled cut start.
    static func programLabel(_ ctx: ScheduleContext, weekStart: String, phase: ProgramPhase) -> String {
        let owner = Schedule.planId(owning: weekStart, in: ctx)
        let plan = ctx.plans.first { $0.id == owner }
        if plan?.isLegacy == true { return "\(plan!.label) (legacy)" }
        return "\(plan?.label ?? owner) \(phase == .cut ? "Cut" : "Bulk")"
    }

    /// When a session really ran, from the EVENT LOG rather than from the two
    /// columns on the session row.
    ///
    /// `workout_sessions.started_at` is stamped when `LoggerModel` is
    /// CONSTRUCTED and written on the first set commit; `ended_at` is stamped
    /// when the finish button is tapped. Neither is a set. A deck opened at
    /// 10:46 and finished at 17:12 around a workout performed at 19:00 exports
    /// as 10:46–17:12, which is what this fixes: `set_events.created_at` is
    /// when a set was actually committed, and the first and last of them are
    /// when the session actually ran.
    ///
    /// Empty for a PULLED session — `applyPulledSets` refuses any session that
    /// has local events, so a session logged on another device has none here
    /// and falls back to the stored columns.
    struct SessionSpan {
        var start: Date
        var end: Date
        /// First commit per SET id, for the performed order.
        var firstBySet: [String: Date]
    }

    struct Rows {
        var goals: UserGoalRow?
        var schedule: ScheduleContext
        var ladder: LeverLadder
        var profiles: [TargetProfile]
        var programId: String { schedule.programId }
        var overrides: [String: String] { schedule.overrides }
        var layout: DayLayout { schedule.layout }
        var logs: [DailyLogRow]
        var nutrition: [NutritionEntryRow]
        var sessions: [WorkoutSession]
        var sets: [HistorySetRow]
        /// Every set from Week 0 to the end of the exported week — the same
        /// rows the ledger's volumes come from. Read for "the last time this
        /// movement was performed", which is a question about history and
        /// cannot be answered from the week alone.
        var allSets: [HistorySetRow]
        var sessionDates: [String: String]
        var spans: [String: SessionSpan]
        var exercises: [String: Exercise]
        var water: [WaterIntakeRow]
        var supps: [SupplementLogRow]
        var doms: [DomsLogRow]
        var fatigue: [FatigueLogRow]
        var stress: [StressLogRow]
        var bodyLedger: [BodyCompositionRow]
        /// Fourteen days of scans ending at the week's end. The week's own rows
        /// are printed; these are what each one's bone and water are judged
        /// against, and a fortnight is the shortest window whose median a
        /// single bad scan cannot move.
        var bodyHistory: [BodyCompositionRow]
        var bodyHistoryLogs: [DailyLogRow]
        /// Six weeks of HRV readings, for `VitalsGate.hrvArtifact`. It wants
        /// the athlete's own prior band and says nothing at all under seven
        /// nights, so a week's worth would never flag anything.
        var hrvHistory: [(date: String, hrv: Double)]
        var cardio: [CardioLogRow]
        var prAxes: [PersonalRecordRow]
        var priorSessions: Int
        var sleep: [SleepSessionRow]
        var dailyTargets: [DailyTargetRow]
        /// The Derived block's stored figure, and the eight days of logs before
        /// the week for the recovery score's trailing baselines.
        var scores: [DailyScoreRow]
        var baselineLogs: [DailyLogRow]
        /// Readiness v9's Derived block: the signals behind each of the seven
        /// days, from the 49 days behind each — `readinessHistory`, the same
        /// door the scorer reads through.
        var readinessByDate: [String: ExportReadiness]
        var customs: [CustomSupplement]
        var volumeOverrides: [LandmarkMuscle: Double]
        /// Week 0 → the exported week, for the trend ledger.
        var ledgerLogs: [DailyLogRow]
        var ledgerNutrition: [NutritionEntryRow]
        var ledgerSessions: [WorkoutSession]
        var ledgerVolumeBySession: [String: Double]
        var ledgerWater: [WaterIntakeRow]
        var ledgerCardio: [CardioLogRow]
    }

    func fetch(weekStart: String, weekEnd: String) throws -> Rows {
        let user = Column("user_id") == userId
        let inWeek = user && Column("date") >= weekStart && Column("date") <= weekEnd
        return try database.read { db in
            let goals = try UserGoalRow.filter(user).fetchOne(db)
            let ctx = try schedule(db, goals: goals, weekStart: weekStart)
            let programId = ctx.programId
            let ladder = try AppDatabase.leverLadder(db, userId: userId, goals: .some(goals))
            let profiles = try TargetProfileRow.filter(user).order(Column("sort")).fetchAll(db).compactMap(TargetProfile.init)
            // The trend ledger runs from the plan's Week 0; with no dated
            // plan, from the exported week alone.
            let ledgerFrom = min(ctx.weekZeroStart ?? weekStart, weekStart)
            let inLedger = user && Column("date") >= ledgerFrom && Column("date") <= weekEnd
            /* "The last time this movement was performed" is a question about
               HISTORY and the ledger's window is the wrong one to borrow: with
               no dated plan `weekZeroStart` is nil, `ledgerFrom` collapses to
               the exported week, and every movement in it prints `first time
               logged` over years of training.
               ponytail: a flat 180 days, not an unbounded scan. A movement not
               touched in six months prints `first time logged`, which is close
               enough to true to be worth one bounded query. */
            let historyFrom = min(ledgerFrom, ISODate.addDays(weekStart, -180) ?? weekStart)

            let ledgerLogs = try DailyLogRow.filter(inLedger).order(Column("date")).fetchAll(db)
            let ledgerNutrition = try NutritionEntryRow.filter(inLedger && Column("meal_type") == "daily").order(Column("date"), Column("logged_at")).fetchAll(db)
            let ledgerWater = try WaterIntakeRow.filter(inLedger).order(Column("date"), Column("logged_at")).fetchAll(db)
            let ledgerCardio = try CardioLogRow.filter(inLedger).order(Column("date"), Column("created_at")).fetchAll(db)
            let ledgerSessions = try WorkoutSession.filter(inLedger).order(Column("date"), Column("started_at")).fetchAll(db)

            let sessions = ledgerSessions.filter { $0.date >= weekStart }
            let historySessions = try WorkoutSession
                .filter(user && Column("date") >= historyFrom && Column("date") <= weekEnd)
                .order(Column("date"), Column("started_at")).fetchAll(db)
            let ids = historySessions.map(\.id)
            let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let allSets: [HistorySetRow] = ids.isEmpty ? [] : try HistorySetRow.fetchAll(db, sql: """
                SELECT s.id, s.session_id, s.exercise_id,
                       COALESCE(e.name, es.name, s.exercise_id) AS exercise_name,
                       s.set_index, s.fold_order, s.weight_kg, s.reps, s.set_type,
                       s.side, s.pair_id, s.est_1rm_kg, s.rpe,
                       -- THE CARDIO AXES. `SessionHistoryStore.setSelect` has
                       -- always had these four and this hand-rolled copy of it
                       -- never did, so a treadmill warm-up — `weight_kg 0,
                       -- reps 0` and all of its measurement in here — decoded
                       -- as nil and rendered `W 0 reps`. They are Optional on
                       -- `HistorySetRow`, so the omission was silent.
                       s.duration_sec, s.incline, s.distance_km, s.elevation_m,
                       s.exercise_order, s.actual_rest_sec,
                       sess.date, sess.day_key
                FROM workout_sets s
                JOIN workout_sessions sess ON sess.id = s.session_id
                LEFT JOIN exercises e ON e.id = s.exercise_id
                LEFT JOIN exercises es ON es.slug = s.exercise_id
                WHERE s.session_id IN (\(marks))
                ORDER BY sess.date, sess.started_at, s.session_id, s.fold_order, s.set_index
                """, arguments: StatementArguments(ids))
            let weekIds = Set(sessions.map(\.id))
            let sets = allSets.filter { weekIds.contains($0.sessionId) }

            /* ── WHEN THE SESSION RAN, AND IN WHAT ORDER ────────────────────
               One pass over `set_events` answers both. `kind` is read as a
               string rather than decoding `SetEvent` because the body is a blob
               this query has no use for.

               APPENDS ONLY, AND ONLY AFTER THE SESSION OPENED. Two event rows
               are not a set being performed:

               · `SessionEditing.seedEventLog` back-fills a log for a session
                 that has rows and none, stamping EVERY row with
                 `loggedAt[id] ?? session.startedAt` — one identical instant for
                 the whole session. Left in, `firstAt` holds the same `Date` for
                 every movement, the sort falls through to its NAME tiebreak,
                 and the document prints a session in alphabetical order under
                 the word `performed`. That is the Face-Pull-first defect this
                 change exists to kill, with a stronger claim attached.
                 `AppDatabase.closeSession` already guards exactly this way
                 (`$0.createdAt > opened`); the guard is carried over here.

               · An `amend` is an EDIT. A set corrected from History the next
                 morning carries `Date()`, so a session that ran 19:00–20:30
                 would export `19:00–08:15` — and §7 cannot catch it, because an
                 end after a start is not an inconsistency. */
            struct EventRow: FetchableRecord, Decodable {
                var sessionId: String
                var setId: String
                var createdAt: Date
                enum CodingKeys: String, CodingKey {
                    case sessionId = "session_id", setId = "set_id", createdAt = "created_at"
                }
            }
            var spans: [String: SessionSpan] = [:]
            if !weekIds.isEmpty {
                let eventIds = Array(weekIds)
                let eventMarks = Array(repeating: "?", count: eventIds.count).joined(separator: ",")
                let events = try EventRow.fetchAll(db, sql: """
                    SELECT session_id, set_id, created_at FROM set_events
                    WHERE session_id IN (\(eventMarks)) AND kind = 'append'
                    ORDER BY created_at
                    """, arguments: StatementArguments(eventIds))
                let openedAt = Dictionary(
                    sessions.map { ($0.id, $0.startedAt ?? .distantPast) }, uniquingKeysWith: { a, _ in a })
                for e in events {
                    guard let opened = openedAt[e.sessionId], e.createdAt > opened else { continue }
                    if var span = spans[e.sessionId] {
                        span.start = Swift.min(span.start, e.createdAt)
                        span.end = Swift.max(span.end, e.createdAt)
                        if span.firstBySet[e.setId] == nil { span.firstBySet[e.setId] = e.createdAt }
                        spans[e.sessionId] = span
                    } else {
                        spans[e.sessionId] = SessionSpan(
                            start: e.createdAt, end: e.createdAt, firstBySet: [e.setId: e.createdAt])
                    }
                }
            }
            var volumeBySession: [String: Double] = [:]
            for (id, own) in Dictionary(grouping: allSets, by: \.sessionId) { volumeBySession[id] = Self.volume(own) }
            let exerciseIds = Array(Set(sets.map(\.exerciseId)))
            let exercises = exerciseIds.isEmpty ? [] : try Exercise.filter(exerciseIds.contains(Column("id"))).fetchAll(db)

            let phase = ctx.phase
            var volumeOverrides: [LandmarkMuscle: Double] = [:]
            for r in try PlanPhaseVolumeRow.filter(user && Column("plan_id") == programId && Column("phase") == phase.rawValue).fetchAll(db) {
                if let m = LandmarkMuscle(rawValue: r.muscle) { volumeOverrides[m] = Double(r.targetSets) }
            }

            let bodyFrom = ISODate.addDays(weekStart, -13) ?? weekStart
            let inBodyWindow = user && Column("date") >= bodyFrom && Column("date") <= weekEnd
            let hrvFrom = ISODate.addDays(weekStart, -42) ?? weekStart

            // Bedtimes: widened a day at the front, bucketed by `nightOf`.
            let sleepFrom = Self.utc("\(ISODate.addDays(weekStart, -1) ?? weekStart)T12:00:00Z")
            let sleepTo = Self.utc("\(ISODate.addDays(weekEnd, 1) ?? weekEnd)T12:00:00Z")

            return Rows(
                goals: goals, schedule: ctx, ladder: ladder, profiles: profiles,
                logs: ledgerLogs.filter { $0.date >= weekStart },
                nutrition: ledgerNutrition.filter { $0.date >= weekStart },
                sessions: sessions, sets: sets, allSets: allSets,
                sessionDates: Dictionary(historySessions.map { ($0.id, $0.date) }, uniquingKeysWith: { _, b in b }),
                spans: spans,
                exercises: Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
                water: ledgerWater.filter { $0.date >= weekStart },
                supps: try SupplementLogRow.filter(inWeek).order(Column("date"), Column("item_key")).fetchAll(db),
                doms: try DomsLogRow.filter(inWeek).order(Column("date"), Column("created_at")).fetchAll(db),
                fatigue: try FatigueLogRow.filter(inWeek).order(Column("date"), Column("created_at")).fetchAll(db),
                stress: try StressLogRow.filter(inWeek).order(Column("date"), Column("created_at")).fetchAll(db),
                bodyLedger: try BodyCompositionRow.filter(inWeek).order(Column("date"), Column("measured_at")).fetchAll(db),
                bodyHistory: try BodyCompositionRow.filter(inBodyWindow).order(Column("date"), Column("measured_at")).fetchAll(db),
                bodyHistoryLogs: try DailyLogRow.filter(inBodyWindow).order(Column("date")).fetchAll(db),
                hrvHistory: try DailyLogRow
                    .filter(user && Column("date") >= hrvFrom && Column("date") <= weekEnd)
                    .order(Column("date")).fetchAll(db)
                    .compactMap { r in r.hrvMs.map { (date: r.date, hrv: $0) } },
                cardio: ledgerCardio.filter { $0.date >= weekStart },
                prAxes: try PersonalRecordRow.filter(user && Column("achieved_on") >= weekStart && Column("achieved_on") <= weekEnd).fetchAll(db),
                priorSessions: try WorkoutSession.filter(user && Column("date") < weekStart).fetchCount(db),
                sleep: sleepFrom == nil || sleepTo == nil ? [] : try SleepSessionRow
                    .filter(user && Column("start_time") >= sleepFrom! && Column("start_time") < sleepTo!)
                    .order(Column("start_time")).fetchAll(db),
                dailyTargets: try DailyTargetRow.filter(inWeek).order(Column("date")).fetchAll(db),
                scores: try DailyScoreRow.filter(inWeek).fetchAll(db),
                baselineLogs: try DailyLogRow
                    .filter(user && Column("date") >= (ISODate.addDays(weekStart, -8) ?? weekStart) && Column("date") <= weekEnd)
                    .order(Column("date")).fetchAll(db),
                readinessByDate: Dictionary(uniqueKeysWithValues: try (0..<7).map { i in
                    let date = ISODate.addDays(weekStart, i) ?? weekStart
                    return (date, ExportReadiness(signals: Readiness.signals(try AppDatabase.readinessHistory(db, userId: userId, date: date))))
                }),
                customs: try CustomSupplementRow.filter(user).order(Column("created_at"), Column("id")).fetchAll(db).map(Self.custom),
                volumeOverrides: volumeOverrides,
                ledgerLogs: ledgerLogs, ledgerNutrition: ledgerNutrition, ledgerSessions: ledgerSessions,
                ledgerVolumeBySession: volumeBySession, ledgerWater: ledgerWater, ledgerCardio: ledgerCardio
            )
        }
    }

    // MARK: - Days

    static let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    func toDays(weekStart: String, _ d: Rows, ctx: ScheduleContext) throws -> [ExportDay] {
        // `new Map(rows.map(r => [r.date, r]))` — a later duplicate wins.
        var logs: [String: DailyLogRow] = [:]
        for r in d.logs { logs[r.date] = r }
        var nutri: [String: NutritionEntryRow] = [:]
        for r in d.nutrition { nutri[r.date] = r }
        var waterByDate: [String: Double] = [:]
        for w in d.water { waterByDate[w.date, default: 0] += w.amountMl }
        var sleepByDate: [String: SleepSessionRow] = [:]
        // Bucketed by the night a bedtime BELONGS to, on the UTC stamp the web reads.
        for r in d.sleep { sleepByDate[Night.nightOf(Self.utcStamp(r.startTime))] = r }
        var shapeByDate: [String: (label: String?, carbs: Bool, fat: Bool)] = [:]
        for r in d.dailyTargets {
            let label: String? = r.profileKey.map { key in
                d.profiles.first { $0.key == key }?.label ?? (key.prefix(1).uppercased() + key.dropFirst())
            }
            shapeByDate[r.date] = (label, r.trackCarbs, r.trackFat)
        }

        // The scorer's baselines, reproduced: the eight most recent logged days
        // up to and including the date, minus the date, averaged over the
        // readings that exist — `ScoringInputsBuilder`'s own window.
        var scoreByDate: [String: DailyScoreRow] = [:]
        for r in d.scores { scoreByDate[r.date] = r }
        func baselineOf(_ date: String, _ pick: (DailyLogRow) -> Double?) -> Double? {
            let trail = d.baselineLogs
                .filter { $0.date <= date }
                .sorted { $0.date > $1.date }
                .prefix(8)
                .filter { $0.date != date }
                .compactMap(pick)
            return trail.isEmpty ? nil : trail.reduce(0, +) / Double(trail.count)
        }

        /* ── THE NIGHT'S DURATION, WHEREVER IT IS ───────────────────────────
           `daily_logs.sleep_minutes` is the column this read, and it is absent
           on most nights — so the week's mean was an average of the one night
           that had one, while `sleep_sessions` sat right there carrying four
           stages for all seven. Three tiers: the logged figure, then the sleep
           session's own duration, then the stages summed.

           AWAKE IS NOT ADDED. Time in bed is not time asleep, and deep % and
           REM % downstream are fractions of the sleeping total. */
        func sleepMinutesOf(_ l: DailyLogRow?, _ sl: SleepSessionRow?) -> Double? {
            if let m = l?.sleepMinutes, m > 0 { return Double(m) }
            if let d = sl?.durationMin, d > 0 { return Double(d) }
            let stages = [sl?.deepMin, sl?.remMin, sl?.coreMin].compactMap { $0 }.filter { $0 > 0 }
            return stages.isEmpty ? nil : Double(stages.reduce(0, +))
        }

        /* ── A READING NO BODY PRODUCES ─────────────────────────────────────
           `VitalsGate.hrvArtifact` is the gate every ingest path already runs,
           and the export never asked it. A strap that slipped reports a NUMBER,
           and a number nobody questions sets the week's mean. The day is still
           printed with its figure; the week reports a second mean without it. */
        func hrvFlagOf(_ date: String, _ value: Double?) -> String? {
            guard let value else { return nil }
            let prior = d.hrvHistory.filter { $0.date < date }.map(\.hrv)
            return VitalsGate.hrvArtifact(value, history: prior)
        }

        return try (0..<7).map { i in
            let date = ISODate.addDays(weekStart, i) ?? weekStart
            let l = logs[date], nt = nutri[date], sl = sleepByDate[date], shape = shapeByDate[date]
            var fields: [String: Any] = [
                "date": date, "weekdayLabel": Self.weekdayLabels[i], "isTrainingDay": Schedule.isTrainingDayIn(ctx, date),
                "weightKg": j(l?.weightKg), "calories": j(nt?.calories), "proteinG": j(nt?.proteinG),
                "carbsG": j(nt?.carbsG), "fatG": j(nt?.fatG),
                "steps": j(l?.steps.map(Double.init)), "distanceM": j(l?.distanceM),
                "trainingMin": j(l?.trainingMinutes.map(Double.init)), "sleepMin": j(sleepMinutesOf(l, sl)),
                "deepMin": j(sl?.deepMin.map(Double.init)), "remMin": j(sl?.remMin.map(Double.init)),
                "restingHr": j(l?.avgRestHeartRate.map(Double.init)), "hrvMs": j(l?.hrvMs),
                "wristTempDeltaC": j(l?.wristTempDelta), "bloodOxygenPct": j(l?.bloodOxygen),
                "avgHr": j(l?.avgHeartRate.map(Double.init)), "respiratoryRate": j(l?.respiratoryRate), "vo2max": j(l?.vo2max),
                "daylightMin": j(l?.timeInDaylightMin.map(Double.init)), "exerciseMin": j(l?.exerciseMinutes.map(Double.init)),
                "standHours": j(l?.standHours.map(Double.init)), "standMin": j(l?.standingMinutes.map(Double.init)),
                "coreMin": j(sl?.coreMin.map(Double.init)), "awakeMin": j(sl?.awakeMin.map(Double.init)),
                "bedTime": j(sl.map { stamp($0.startTime) }), "wakeTime": j(sl.map { stamp($0.endTime) }),
                // A day with no row has never been reported on: `false`, as the
                // column's NOT NULL DEFAULT false says.
                // ── PRESENT ONLY WHEN TRUE ──────────────────────────────────
                // This was `?? false`, and the renderer prints a false as
                // "fell asleep easily" — so every night with no `daily_logs`
                // row at all claimed the athlete dropped straight off. That is
                // an assertion about a night nobody recorded, in a document
                // whose entire contract is that a gap is named and never
                // invented. Absent now means unrecorded and prints nothing;
                // the flag appears only when it was actually ticked.
                "sleepOnsetTrouble": l?.sleepOnsetTrouble == true ? true : NSNull(),
                "restingHrBaseline": j(baselineOf(date) { $0.avgRestHeartRate.map(Double.init) }),
                "hrvBaseline": j(baselineOf(date) { $0.hrvMs }),
                "batteryPct": j(scoreByDate[date]?.batteryPct.map(Double.init)),
                "readiness": try d.readinessByDate[date].map(Self.encodeToJSON) ?? NSNull(),
                "waterMl": j(waterByDate[date] ?? l?.waterMl),
                "supplementsTaken": NSNull(), "supplementsLog": [] as [Any],
                "activeKcal": j(l?.activeEnergy), "bmrKcal": j(l?.bmr),
                // Null is "As Planned" — resolved by the renderer, never stored.
                "weighInSkipReason": j((l?.weighinSkipReason?.isEmpty == false) ? l?.weighinSkipReason : nil),
                "nutritionException": j((l?.nutritionException?.isEmpty == false) ? l?.nutritionException : nil),
                "nutritionEstimated": l?.nutritionEstimated ?? false,
                "hrvFlag": j(hrvFlagOf(date, l?.hrvMs)),
                "targetProfile": j(shape?.label), "trackCarbs": shape?.carbs ?? true, "trackFat": shape?.fat ?? true,
            ]
            // Present ONLY when the night is disputed. `false` on every row is a
            // column of noise that says nothing happened six times a week, and the
            // reader has to scan it anyway to find the one row that matters.
            if l?.sleepInaccurate == true { fields["sleepInaccurate"] = true }
            return try make(fields)
        }
    }

    /// `withNutrients`: the day's micros (food and stack apart) and the
    /// adherence derived from the SCHEDULE — the protocol minus what was
    /// explicitly dropped, with the scheduled times.
    func withNutrients(_ days: [ExportDay], _ d: Rows) throws -> [ExportDay] {
        var nutriByDate: [String: NutritionEntryRow] = [:]
        for r in d.nutrition { nutriByDate[r.date] = r }
        var skippedByDate: [String: Set<String>] = [:]
        for s in d.supps where s.taken == false { skippedByDate[s.date, default: []].insert(s.itemKey) }
        var payloads: [String: [String: Double]] = [:]
        for c in d.customs { if let m = c.micros { payloads[Supplements.key(of: c)] = m } }

        return try days.map { day in
            let nt = nutriByDate[day.date]
            var food: [String: Double] = nt?.micros.flatMap(Self.numbers) ?? [:]
            food["fiber"] = nt?.fiberG
            food["protein"] = nt?.proteinG

            let training = day.isTrainingDay
            let weekday = ISODate.weekday(day.date) ?? 0
            // ── THE PROTOCOL AS IT STOOD ON THAT DAY ────────────────────────
            // `Supplements.active(_:on:)` was written for exactly this and was
            // called by neither builder. Without it an item archived on the
            // Wednesday is still "scheduled" on Thursday, Friday and Saturday —
            // inflating the denominator AND appearing in the taken list of
            // three days it had already left.
            let liveCustoms = Supplements.active(d.customs, on: day.date)
            let custom = Supplements.customSlotsForDate(liveCustoms, weekday: weekday, isTraining: training)
            let slots = Supplements.stackForDate(custom, isTraining: training, weekday: weekday)
            var doses: [String: String] = [:]
            for sl in slots { for i in sl.items { doses[i.key] = i.dose } }
            let skipped = skippedByDate[day.date] ?? []
            let scheduled = slots.flatMap { sl in sl.items.map { (key: $0.key, name: $0.name, time: sl.time) } }
            // ── FOUR STATES, RESOLVED AGAINST THE CLOCK ─────────────────────
            // `Supplements.doses` is the one function that knows the difference
            // between a dose that was taken, one that counts because its slot
            // has passed, one still ahead, and one refused. The export used to
            // collapse all four into "scheduled minus skipped", which asserts
            // that a 22:00 magnesium was taken at any hour you cared to export.
            //
            // A CLOSED day is over by definition, so `later` is empty in every
            // report the native app can produce. It is computed anyway: the web
            // can render a week in progress, and a pending dose rounded up into
            // an adherence figure is the same class of invented fact.
            let resolved = Supplements.doses(
                slots: slots,
                log: (d.supps.filter { $0.date == day.date })
                    .map { DoseLogEntry(itemKey: $0.itemKey, taken: $0.taken) },
                // `.past`, unconditionally. This builder only ever runs over a
                // CLOSED week — `WeekDaysView` gates the export on
                // `WeekReady.isComplete`, strictly after the week's last day —
                // so every day it renders is over, and reading a wall clock
                // here would make the same week export differently depending on
                // the hour it was shared. The web is the surface that can ask
                // about a live week, and it passes its own clock.
                clock: .past
            )
            let laterKeys = Set(resolved.filter { $0.state == .later }.map(\.key))
            let taken = scheduled.filter { !skipped.contains($0.key) && !laterKeys.contains($0.key) }

            /* ── THE STACK'S MICRONUTRIENTS, MERGED AND NOT CHOSEN ───────────
               This was `payloads[key] ?? supplementNutrients[key]`, and `??`
               short-circuits on a NON-NIL EMPTY dictionary. `custom_supplements.
               micros` is null on every seeded row, so the fallback carried the
               whole stack — until an item is edited in the app, or its `micros`
               decodes to nothing (a `{}`, a null value, a non-numeric), at
               which point `payloads[key]` is a present-but-empty map, the
               fallback is never consulted, and the item silently credits
               nothing. That is how the multivitamin's vitamin C and B12, the
               D3 + K2 and the magnesium glycinate all came out at zero against
               targets the stack was bought to meet.

               Merged now, the row's own payload winning PER MICRO, so a partial
               custom payload can only override what it actually states. */
            var stack: [String: Double] = [:]
            for item in taken {
                var payload = Self.supplementNutrients[item.key] ?? [:]
                payload.merge(payloads[item.key] ?? [:]) { _, own in own }
                guard !payload.isEmpty else { continue }
                let units = Self.doseUnits(doses[item.key])
                for (micro, amount) in payload { stack[micro, default: 0] += amount * units }
            }

            var out = try Self.encodeToJSON(day)
            out["nutrientsFood"] = food
            out["nutrientsStack"] = stack
            out["supplementsTaken"] = scheduled.isEmpty ? NSNull() : Double(taken.count)
            out["supplementsLog"] = taken.map { ["key": $0.key, "time": $0.time] }
            // ── THE SKIP IS NEVER FILTERED THROUGH THE SCHEDULE ─────────────
            // `scheduled.filter { skipped.contains($0.key) }` was the bug: a
            // refusal logged against an item the day's projection no longer
            // names was DELETED rather than reported. That is how Friday
            // 2026-09-04 came out as "9 of 9 — skipped: none logged" after
            // L-Citrulline was explicitly declined.
            //
            // The log is the evidence and the schedule is a projection of it,
            // so the evidence leads. A skip the protocol asked for is a miss; a
            // skip it did not ask for is still a fact, and it goes in its own
            // list so the renderer can say which is which.
            let plannedKeys = Set(scheduled.map(\.key))
            out["supplementsSkipped"] = scheduled.filter { skipped.contains($0.key) }.map(\.name)
            out["supplementsSkippedUnplanned"] = skipped
                .subtracting(plannedKeys)
                .sorted()
                .map { key in
                    // Named from the protocol wherever it still exists —
                    // including an ARCHIVED row, which is precisely the case
                    // that lands here. Only a key nothing names at all falls
                    // back to the key itself.
                    d.customs.first { Supplements.key(of: $0) == key }?.name ?? key
                }
            out["supplementsLater"] = scheduled.filter { laterKeys.contains($0.key) }.map(\.name)
            out["supplementsPlanned"] = Double(Supplements.count(isTraining: training, dbSlots: custom))
            return try make(out)
        }
    }

    // MARK: - Sessions

    static let axisOrder: [PrAxis] = [.weight, .reps, .volume, .e1rm]

    func toSessions(_ d: Rows, ctx: ScheduleContext, phase: ProgramPhase) throws -> [ExportSession] {
        var axesByKey: [String: Set<PrAxis>] = [:]
        var recordSetsByKey: [String: [(weightKg: Double?, reps: Double?)]] = [:]
        for r in d.prAxes {
            guard let sid = r.sessionId, let axis = PrAxis(rawValue: r.axis) else { continue }
            axesByKey["\(sid)::\(r.exerciseKey)", default: []].insert(axis)
            recordSetsByKey["\(sid)::\(r.exerciseKey)", default: []].append((r.weightKg, r.reps.map(Double.init)))
        }

        /* Chronological position of every session from Week 0 forward. The
           set query is ordered by `sess.date, sess.started_at`, so first
           appearance in it IS that order — no second query for it. */
        var sessionPos: [String: Int] = [:]
        for r in d.allSets where sessionPos[r.sessionId] == nil { sessionPos[r.sessionId] = sessionPos.count }

        /// The best working set of the last session before `pos` that performed
        /// this movement — heaviest tonnage, ties to the heavier load, which is
        /// `dedupePrs`' rule and therefore the same set the PR engine would pick.
        func previousBest(_ name: String, before pos: Int) -> (date: String, weightKg: Double, reps: Double)? {
            var best: HistorySetRow?
            var bestPos = -1
            for r in d.allSets where r.exerciseName == name && SetTags.isWorkingSet(r.setType) {
                guard let p = sessionPos[r.sessionId], p < pos else { continue }
                // A newer session replaces the candidate outright: "last time"
                // is one session, not the best set of every session before now.
                if p > bestPos { bestPos = p; best = nil }
                guard p == bestPos else { continue }
                if let cur = best {
                    let a = r.weightKg * Double(r.reps), b = cur.weightKg * Double(cur.reps)
                    if a > b || (a == b && r.weightKg > cur.weightKg) { best = r }
                } else {
                    best = r
                }
            }
            return best.map { (date: $0.date, weightKg: $0.weightKg, reps: Double($0.reps)) }
        }

        return try d.sessions.enumerated().map { sessionIndex, s in
            let program = Schedule.programForContext(ctx, s.date).program
            let mine = d.sets.filter { $0.sessionId == s.id }
            let span = d.spans[s.id]
            let pos = sessionPos[s.id] ?? Int.max
            // ── THE ORDER THE SESSION WAS PERFORMED IN ──────────────────────
            // `exercise_order` is the column a reorder writes and the number
            // both clients sort by; the query's `fold_order` is only the fold's
            // ARRIVAL tiebreak, which for a pulled session is the puller's
            // order and not the deck's. A movement with no index falls back to
            // its first-appearance position, exactly as `RoutineOrder.save`
            // does — the one existing reader that already had this right.
            //
            // `orderSource` records which of the two answered, so the renderer
            // can mark a fallback instead of presenting a guess as a record.
            /* ── PERFORMED ORDER, FROM THE LOG THAT HAS IT ──────────────────
               `exercise_order` is not a performed-order index and never was:
               `LoggerModel.deckOrder` writes the movement's position in the
               DECK, so a session that started with the third card still stamps
               that card 2. It is right for a reorder and wrong for a record of
               what happened, which is what this document is.

               `set_events.created_at` is when a set was actually committed, so
               the earliest commit per movement IS the order it was performed
               in — for every session ever logged on this phone, not only for
               ones logged after a migration. It is used first, `exercise_order`
               second for a PULLED session (which has no local events, by
               `applyPulledSets`' own rule), and first-appearance last.

               `orderSource` records which of the three answered so §7 can name
               a guess rather than presenting it as a record. */
            var firstAt: [String: Date] = [:]
            for r in mine {
                guard let at = span?.firstBySet[r.id] else { continue }
                if let cur = firstAt[r.exerciseName], cur <= at { continue }
                firstAt[r.exerciseName] = at
            }
            var indexByName: [String: Int] = [:]
            var loggedRank: [String: Int] = [:]
            var order: [String] = []
            var everyMovementIndexed = true
            for r in mine where loggedRank[r.exerciseName] == nil {
                if let n = r.exerciseOrder { indexByName[r.exerciseName] = n } else { everyMovementIndexed = false }
                loggedRank[r.exerciseName] = loggedRank.count
                order.append(r.exerciseName)
            }
            /* Every movement timed, and timed DISTINCTLY. Two movements sharing
               a first-commit instant cannot be ordered by it, and the sort's
               name tiebreak would present alphabetical order as a record. */
            let stamps = order.compactMap { firstAt[$0] }
            let everyMovementTimed = !order.isEmpty && stamps.count == order.count
                && Set(stamps).count == order.count
            if everyMovementTimed {
                order.sort { firstAt[$0]! < firstAt[$1]! }
            } else if everyMovementIndexed {
                order.sort { (indexByName[$0]!, loggedRank[$0]!) < (indexByName[$1]!, loggedRank[$1]!) }
            } else {
                /* PARTIALLY indexed is not indexed. `exercise_order ?? count`
                   mixed a deck position with a logged ordinal — `[A:3, B:nil,
                   C:1]` came out `B, C, A`, which is neither the deck's order
                   nor the log's, under a label claiming the log's. */
                order.sort { loggedRank[$0]! < loggedRank[$1]! }
            }
            let orderSource = everyMovementTimed ? "performed" : (everyMovementIndexed ? "index" : "logged")

            var byName: [String: [String: Any]] = [:]
            /// Every MEASURED gap, per movement. Unmeasured sets contribute
            /// nothing rather than a zero — a mean over "the sets we timed" is
            /// a fact, a mean that counts untimed sets as instant is not.
            var restsByName: [String: [Int]] = [:]
            for r in mine {
                if let rest = r.actualRestSec, rest > 0 {
                    restsByName[r.exerciseName, default: []].append(rest)
                }
                if byName[r.exerciseName] == nil {
                    let window = Ceilings.repWindow(for: r.exerciseName, dayKey: s.dayKey, program: program, phase: phase)
                    let rest = RestTargets.programRestSec(for: r.exerciseName, dayKey: s.dayKey, program: program, phase: phase)
                    // The landmarks the movement trains, resolved HERE and not
                    // in the renderer: `resolveMovers` reads the name
                    // dictionary first and falls back to the stored
                    // `exercises.muscle_groups`, and only this side holds the
                    // stored list. A renderer working from the name alone would
                    // silently ignore a movement the athlete reclassified.
                    // The plan's own row for this movement, where the plan
                    // names it at all. A substitution or an accessory added on
                    // the day has no prescription and prints none, rather than
                    // borrowing the rep window's numbers and calling them one.
                    let planned = s.dayKey.flatMap { program.day(key: $0) }?
                        .exercises.first { ExerciseAliases.canonicalName($0.name) == ExerciseAliases.canonicalName(r.exerciseName) }
                    let m = movers(r, d)
                    let primary = MuscleMap.landmarks(m.primary).map(\.displayName)
                    // A landmark already named as primary is not repeated as
                    // indirect: a cable row is `upper back` primary and `traps`
                    // secondary, and both fold to Upper back.
                    let secondary = MuscleMap.landmarks(m.secondary)
                        .map(\.displayName).filter { !primary.contains($0) }
                    byName[r.exerciseName] = [
                        "name": r.exerciseName, "sets": [] as [[String: Any]], "topKg": NSNull(),
                        "repWindow": j(window.map { "\(jsIntegerString($0.floor))–\(jsIntegerString($0.ceiling))" }),
                        // The override store is localStorage on the web and
                        // is not mirrored: the plan's target is the target.
                        "restTargetSec": j(rest), "restPlanSec": j(rest),
                        "primaryMuscles": primary, "secondaryMuscles": secondary,
                        // `ProgramExercise.isCompound` is a real field and the
                        // ONLY one this device holds — `exercises.is_compound`
                        // exists on the server and is not mirrored. Never
                        // guessed from the name: "Chest Press" would come out
                        // compound for having two words in it
                        // (`Exercises/Tags.swift`). Nil for a movement the plan
                        // does not name, and a nil is not a `false`.
                        "compound": j(planned?.isCompound),
                        "prescription": planned.map { p -> [String: Any] in
                            ["sets": Double(p.sets(for: phase)), "reps": p.reps, "loadKg": j(p.wk1Kg)]
                        } ?? NSNull(),
                        "previous": previousBest(r.exerciseName, before: pos).map { prev -> [String: Any] in
                            ["date": prev.date, "weightKg": prev.weightKg, "reps": prev.reps]
                        } ?? NSNull(),
                    ]
                }
                var e = byName[r.exerciseName]!
                var sets = e["sets"] as! [[String: Any]]
                sets.append([
                    "weightKg": r.weightKg, "reps": Double(r.reps),
                    "rpe": j(r.rpe.flatMap { $0.isFinite ? $0 : nil }),
                    "side": j(Self.lr(r.lr)),
                    "failure": r.setType == "failure", "warmup": r.setType == "warmup",
                    "ghost": r.setType == "ghost", "dropset": r.setType == "dropset",
                    // `quality` is not mirrored — "the question was never asked".
                    "quality": NSNull(), "pairId": j(r.pairId),
                    // A treadmill warm-up's whole measurement. Speed is not a
                    // column anywhere; the renderer derives it from the pair.
                    "durationSec": j(r.durationSec.map(Double.init)),
                    "distanceKm": j(r.distanceKm), "inclinePct": j(r.incline),
                ])
                e["sets"] = sets
                // Warm-ups must not define the top load; `|| null` zeroes out.
                if SetTags.isWorkingSet(r.setType) {
                    let top = max((e["topKg"] as? Double) ?? 0, r.weightKg)
                    e["topKg"] = top == 0 ? NSNull() : top
                }
                byName[r.exerciseName] = e
            }

            // The mean measured rest, folded in once the sets are all counted.
            // `jsRound` and not `rounded()`: every other figure in this builder
            // rounds the way JavaScript does, and byte parity is the gate.
            for (name, rests) in restsByName where !rests.isEmpty {
                byName[name]?["restActualSec"] =
                    jsRound(Double(rests.reduce(0, +)) / Double(rests.count))
            }

            let credits = PrEngine.volumeCredits(mine.map {
                VolumeCreditRow(weightKg: $0.weightKg, reps: Double($0.reps), pairId: $0.pairId, side: Self.lr($0.lr))
            })
            let creditByRow = Dictionary(zip(mine.map(\.id), credits), uniquingKeysWith: { a, _ in a })
            /* ── A SET TO FAILURE IS ONE RATED 10 ───────────────────────────
               This counted `set_type == 'failure'` alone — a separate tick the
               logger offers and the athlete almost never uses — so a session
               with six sets rated RPE 10 reported `0 sets to failure`, above a
               list of sets the reader can see every one of. The RPE dial is on
               every set and the tick is a second spelling of it, so either
               counts and neither is required.

               Keyed by `pairId ?? id`: a unilateral pair is examined per side
               and counted ONCE, or `failure_sets` would exceed `working_sets`
               for a session of single-arm work. */
            let failurePairs = Set(
                mine.filter { $0.setType == "failure" || $0.rpe == 10 }
                    .filter { SetTags.isWorkingSet($0.setType) || $0.setType == "failure" }
                    .map { $0.pairId ?? $0.id })

            // PR lines: `is_pr` is not mirrored, so the winning set is found by
            // the standing ledger row's own load × reps, then de-duplicated per
            // movement exactly as `dedupePrs` does (heaviest tonnage, ties to
            // the heavier load). A record since beaten has no ledger row and
            // prints no line here, where the web keeps its line with no axes.
            var best: [String: HistorySetRow] = [:]
            var prOrder: [String] = []
            for r in mine {
                guard let records = recordSetsByKey["\(s.id)::\(r.exerciseName)"],
                      records.contains(where: { $0.weightKg == r.weightKg && $0.reps == Double(r.reps) }) else { continue }
                let cur = best[r.exerciseName]
                let tonnage = r.weightKg * Double(r.reps)
                let better = cur == nil
                    || tonnage > cur!.weightKg * Double(cur!.reps)
                    || (tonnage == cur!.weightKg * Double(cur!.reps) && r.weightKg > cur!.weightKg)
                if better { if cur == nil { prOrder.append(r.exerciseName) }; best[r.exerciseName] = r }
            }
            let prs: [[String: Any]] = prOrder.map { name in
                let r = best[name]!
                let axes = axesByKey["\(s.id)::\(name)"] ?? []
                return [
                    "name": name, "weightKg": r.weightKg, "reps": Double(r.reps),
                    "axes": Self.axisOrder.filter { axes.contains($0) }.map(\.rawValue),
                    "volumeKg": j(creditByRow[r.id] ?? nil),
                    // `||` on the stored estimate: unloaded work stores 0.
                    "e1rmKg": j(r.est1rmKg.flatMap { $0 > 0 ? $0 : nil } ?? OneRepMax.estimate(weight: r.weightKg, reps: Double(r.reps))),
                ]
            }

            let label = s.dayKey.flatMap { program.day(key: $0)?.label }
                ?? (try? SyncTranslation.splitDay(forDayKey: s.dayKey)) ?? s.dayKey ?? "Session"
            return try make([
                "date": s.date,
                /* ── WHEN THE WORK HAPPENED, NOT WHEN THE SCREEN DID ────────
                   `started_at` is stamped when `LoggerModel` is CONSTRUCTED and
                   written on the first commit; `ended_at` when the finish
                   button is tapped. A deck opened at 10:46 and finished at
                   17:12 around a workout performed at 19:00 exported as
                   10:46–17:12. The first and last `set_events.created_at` are
                   the real span; a pulled session has no local events and keeps
                   the stored columns. */
                "startedAt": j((span?.start ?? s.startedAt).map(stamp)),
                "endedAt": j((span?.end ?? s.endedAt).map(stamp)),
                "sessionNumber": Double(d.priorSessions + sessionIndex + 1),
                "label": label,
                // Recomputed from the rows, as the web does (an L/R pair scores at
                // the weaker side). Nil, not 0, when there are no rows at all.
                "volumeKg": mine.isEmpty ? NSNull() : Self.volume(mine),
                "setCount": Double(Self.committedSets(mine)),
                "failureSets": Double(failurePairs.count),
                "durationMin": j(s.durationMin),
                // ── READ, NOT NULLED ────────────────────────────────────────
                // These were hardcoded `NSNull()` on the reasoning that
                // `workout_sessions.avg_bpm / calories_burned` are "not
                // mirrored". That is true of the PULL — the server's copy is
                // not brought down — and irrelevant here, because
                // `HealthSync.syncSessionMetrics` WRITES both columns on this
                // device: it finds the `HKWorkout` overlapping the session,
                // averages heart rate and sums active energy over the workout's
                // own interval, and stamps `*_estimated = false`. Without a
                // watch record it falls back to the athlete's own median
                // kcal/min and stamps `true`.
                //
                // So the figures were sitting in the row all along while every
                // export printed "avg HR no data · no data kcal" beside a day
                // whose activity ring was full.
                "avgBpm": j(s.avgBpm.map(Double.init)),
                "caloriesBurned": j(s.caloriesBurned.map(Double.init)),
                "caloriesEstimated": s.caloriesEstimated,
                "avgBpmEstimated": s.avgBpmEstimated,
                "sessionRpe": j(s.sessionRpe),
                "orderSource": orderSource,
                "exercises": order.map { byName[$0]! },
                "prs": prs,
            ])
        }
    }

    // MARK: - Weekly volume and tonnage

    /// `PROGRAM_TARGETS` — weekly set landmarks per phase (`landmarks.ts`).
    static let programTargets: [ProgramPhase: [LandmarkMuscle: Double]] = [
        .cut: [.chest: 11, .lats: 6, .upperBack: 4, .lowerBack: 1, .frontDelts: 4, .sideDelts: 7, .rearDelts: 2,
               .biceps: 8, .triceps: 6, .forearms: 4, .quads: 10, .hamstrings: 8, .glutes: 6, .adductors: 0,
               .calves: 6, .absCore: 10],
        .bulk: [.chest: 13, .lats: 8, .upperBack: 5, .lowerBack: 1, .frontDelts: 6, .sideDelts: 9, .rearDelts: 3,
                .biceps: 9, .triceps: 7, .forearms: 7, .quads: 12, .hamstrings: 9, .glutes: 7, .adductors: 2,
                .calves: 8, .absCore: 11],
    ]

    func movers(_ r: HistorySetRow, _ d: Rows) -> MoverTokens {
        let ex = d.exercises[r.exerciseId]
        let secondary = ex?.secondaryMuscles.flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
        let stored = (ex?.primaryMuscle.map { [$0] } ?? []) + secondary
        return MuscleMap.resolveMovers(r.exerciseName, stored: stored.isEmpty ? nil : stored)
    }

    /// `weeklyVolumeByMuscle`: a set credits each landmark ONCE, at the highest
    /// weight any of its tokens earned; a unilateral pair is one key.
    func volumeByMuscle(_ d: Rows, phase: ProgramPhase) -> [[String: Any]] {
        var targets = Self.programTargets[phase]!
        targets.merge(d.volumeOverrides) { _, o in o }
        var counted: [LandmarkMuscle: [String: Double]] = [:]
        for r in d.sets {
            let m = movers(r, d)
            let key = r.pairId ?? r.id
            for (tokens, weight) in [(m.secondary, MuscleCredit.secondarySetCredit), (m.primary, 1.0)] {
                for muscle in Set(tokens.compactMap(LandmarkMuscle.from(token:))) {
                    counted[muscle, default: [:]][key] = max(counted[muscle]?[key] ?? 0, weight)
                }
            }
        }
        let half = { (v: Double) in jsRound(v * 10) / 10 }
        return LandmarkMuscle.allCases.map { muscle in
            var direct = 0.0, indirect = 0.0
            for w in (counted[muscle] ?? [:]).values { if w >= 1 { direct += 1 } else { indirect += w } }
            return [
                "muscle": muscle.rawValue, "sets": half(direct + indirect), "target": targets[muscle] ?? 0,
                "directSets": direct, "indirectSets": half(indirect),
            ] as [String: Any]
        }
    }

    /// `tonnageRows` + `weeklyTonnageByMuscle`: collapsed per (session,
    /// exercise) BEFORE attribution, heaviest first. Over-sums on purpose.
    func tonnageByMuscle(_ d: Rows) -> [[String: Any]] {
        var order: [String] = []
        var groups: [String: [HistorySetRow]] = [:]
        for r in d.sets {
            let key = "\(r.sessionId)::\(r.exerciseName)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(r)
        }
        var total: [LandmarkMuscle: Double] = [:]
        for key in order {
            let sets = groups[key]!
            let volumeKg = Self.volume(sets)
            guard volumeKg.isFinite, volumeKg > 0 else { continue }
            let m = movers(sets[0], d)
            let primary = Set(m.primary.compactMap(LandmarkMuscle.from(token:)))
            for muscle in Set(m.secondary.compactMap(LandmarkMuscle.from(token:))) where !primary.contains(muscle) {
                total[muscle, default: 0] += volumeKg * MuscleCredit.secondarySetCredit
            }
            for muscle in primary { total[muscle, default: 0] += volumeKg }
        }
        let rows = LandmarkMuscle.allCases.compactMap { m -> (String, Double)? in
            guard let v = total[m], v > 0 else { return nil }
            return (m.rawValue, jsRound(v * 100) / 100)
        }
        return Self.stableSorted(rows) { $0.1 > $1.1 }.map { ["muscle": $0.0, "volumeKg": $0.1] as [String: Any] }
    }

    // MARK: - Body composition

    /// The middle value, or nil. Local because a median over two fields of a
    /// fortnight is not worth a dependency.
    static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let v = xs.sorted()
        let mid = v.count / 2
        return v.count % 2 == 1 ? v[mid] : (v[mid - 1] + v[mid]) / 2
    }

    /// How far a scan's bone mass may sit from the fortnight's median before the
    /// document stops believing it, in kg.
    ///
    /// Bone mineral does not move week to week — it is the most stable
    /// compartment a bioimpedance scale reports, and a jump in it is the
    /// scale's opinion of a different contact resistance, not the athlete's
    /// skeleton. Water is allowed a wider band because it genuinely moves with
    /// carbohydrate, salt and the hour of the morning; past 0.6 kg it is
    /// carrying the reading rather than describing it.
    static let boneAnomalyKg: Double = 0.10
    static let waterAnomalyKg: Double = 0.6

    /// Union of the ledger and daily_logs, daily_logs winning per FIELD.
    ///
    /// Merged over FOURTEEN DAYS and returned for the week: every row printed
    /// is judged against the fortnight behind it, and a fortnight is the
    /// shortest window whose median one bad scan cannot move.
    func toBodyComp(_ d: Rows, weekStart: String) -> [[String: Any]] {
        var merged: [String: [String: Double]] = [:]
        // `merged.set(date, {…})` — a later ledger row for a date REPLACES.
        for r in d.bodyHistory {
            merged[r.date] = [
                "weightKg": r.weightKg, "bmi": r.bmi, "bodyFatPct": r.bodyFatPct, "musclePercent": r.musclePct,
                "waterPercent": r.waterPct, "boneMineral": r.boneMineralPct, "visceralFat": r.visceralFat, "bmr": r.bmr,
                "muscleMassKg": r.muscleMassKg, "fatFreeMassKg": r.fatFreeMassKg, "fatMassKg": r.fatMassKg,
                "proteinMassKg": r.proteinMassKg, "proteinPercent": r.proteinPct, "boneMineralKg": r.boneMassKg,
                "waterMassKg": r.bodyWaterMassKg, "skeletalMuscleMassKg": r.skeletalMuscleMassKg,
            ].compactMapValues { $0 }
        }
        for r in d.bodyHistoryLogs {
            let fields: [String: Double?] = [
                "weightKg": r.weightKg, "bmi": r.bmi, "bodyFatPct": r.bodyFatPct, "musclePercent": r.musclePercent,
                "waterPercent": r.waterPercent, "boneMineral": r.boneMineral, "visceralFat": r.visceralFat, "bmr": r.bmr,
                "muscleMassKg": r.muscleMassKg, "fatFreeMassKg": r.fatFreeMassKg, "fatMassKg": r.fatMassKg,
                "proteinMassKg": r.proteinMassKg, "proteinPercent": r.proteinPercent, "boneMineralKg": r.boneMineralKg,
                "waterMassKg": r.waterMassKg, "skeletalMuscleMassKg": r.skeletalMuscleMassKg,
                "estimatedWaistToHipRatio": r.estimatedWaistToHipRatio,
            ]
            merged[r.date, default: [:]].merge(fields.compactMapValues { $0 }) { _, log in log }
        }
        // Only days with a metric beyond bare weight; the daily table lists weight.
        let beyondWeight = ["bmi", "bodyFatPct", "musclePercent", "waterPercent", "visceralFat", "bmr", "boneMineral",
                            "muscleMassKg", "fatFreeMassKg", "skeletalMuscleMassKg", "estimatedWaistToHipRatio"]
        let scanned = merged.keys.sorted()
            .filter { date in beyondWeight.contains { merged[date]![$0] != nil } }

        /// The median of one compartment over the fourteen days ending at
        /// `date`, the scan itself included — a window of one is its own median
        /// and therefore never anomalous, which is the right answer for a first
        /// scan and the reason the flag needs history to fire.
        /* LEAVE ONE OUT, and never over fewer than two others.
           A scan compared against a median it is IN is compared against itself:
           with two scans in the fortnight the median is their midpoint, each
           sits half the gap from it, and one bad reading flagged BOTH — which
           emptied `valid` and took `T4WM` and `clean_scan_means` with it. The
           scan is judged against its neighbours, and under two of them there is
           no neighbourhood to judge it by. */
        func trailingMedian(_ date: String, _ field: String) -> Double? {
            guard let from = ISODate.addDays(date, -13) else { return nil }
            let others = scanned
                .filter { $0 >= from && $0 <= date && $0 != date }
                .compactMap { merged[$0]?[field] }
            return others.count >= 2 ? Self.median(others) : nil
        }

        return scanned.filter { $0 >= weekStart }.map { date in
            var out: [String: Any] = merged[date]!
            out["date"] = date
            var why: [String] = []
            // Both figures rounded on the way into the string. Every other
            // number in this document goes through `jsRound`; a raw `Double`
            // interpolation prints `3.0500000000000003`.
            func round2(_ v: Double) -> String { jsIntegerString(jsRound(v * 100) / 100) }
            if let v = merged[date]?["boneMineralKg"], let m = trailingMedian(date, "boneMineralKg"),
               abs(v - m) > Self.boneAnomalyKg {
                why.append("bone \(round2(abs(v - m))) kg from the 14-day median \(round2(m))")
            }
            if let v = merged[date]?["waterMassKg"], let m = trailingMedian(date, "waterMassKg"),
               abs(v - m) > Self.waterAnomalyKg {
                why.append("water \(round2(abs(v - m))) kg from the 14-day median \(round2(m))")
            }
            out["anomaly"] = why.isEmpty ? NSNull() : why.joined(separator: ", ")
            return out
        }
    }

    // MARK: - Supplements

    /// The stack as rows — the DATABASE verbatim. An empty table is an empty
    /// stack since W2; there is no compiled seed to fall back to.
    func supplementStack(_ customs: [CustomSupplement]) -> [[String: Any]] {
        return customs.map { c in
            [
                // The key `supplement_log` is written against: without it a
                // day's "taken" list can only print `d3k2@07:00`.
                "time": j(c.time), "key": c.schedule?.key ?? c.id, "name": c.name, "dose": c.dose,
                "trainingDose": j(c.schedule?.trainingDose), "restDose": j(c.schedule?.restDose),
                "trainingOnly": j(c.schedule?.trainingOnly), "notes": j(c.schedule?.notes),
            ]
        }
    }

    /// `SUPPLEMENT_NUTRIENTS` — the seed's payloads, per unit of dose.
    static let supplementNutrients: [String: [String: Double]] = [
        "multivitamin": ["vitaminB12": 300, "folate": 680, "vitaminC": 470],
        "d3k2": ["vitaminD": 5000],
        "citrulline": ["citrulline": 3000],
        "caffeine": ["caffeine": 200],
        "omega3": ["epa": 500, "dha": 250],
        "creatine": ["creatine": 5000],
        "theanine": ["theanine": 200],
        "glycine": ["glycine": 5000],
        "magnesium": ["magnesium": 300],
    ]

    /// `doseUnits`: only a COUNT unit multiplies ("2 caps"); a mass stays ×1.
    static func doseUnits(_ dose: String?) -> Double {
        let pattern = #"^\s*(\d+(?:\.\d+)?)\s*(tabs?|caps?|capsules?|pills?|scoops?|softgels?|gummies|gummy)\b"#
        guard let dose, let m = dose.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return 1 }
        let head = dose[m].trimmingCharacters(in: .whitespaces)
        let digits = head.prefix { $0.isNumber || $0 == "." }
        guard let n = Double(digits), n > 0 else { return 1 }
        return n
    }

    // MARK: - Ledger

    /// `fetchTrendLedger`: every week from Week 0 to the exported one, through
    /// the SAME `trendTotals` as the week's own figures.
    func ledger(_ d: Rows, weekStart: String, ctx: ScheduleContext) throws -> [LedgerWeek] {
        var logByDate: [String: DailyLogRow] = [:]
        for r in d.ledgerLogs { logByDate[r.date] = r }
        var kcalByDate: [String: Double] = [:]
        for r in d.ledgerNutrition { kcalByDate[r.date] = r.calories }
        var waterByDate: [String: Double] = [:]
        for w in d.ledgerWater { waterByDate[w.date, default: 0] += w.amountMl }
        var cardioByDate: [String: [Double]] = [:]
        for c in d.ledgerCardio { if let m = c.durationMin { cardioByDate[c.date, default: []].append(m) } }
        var volByDate: [String: [Double]] = [:]
        for s in d.ledgerSessions {
            // Seed rows are scaffolding; a session with no rows has no volume.
            if s.notes?.hasPrefix("__seed_") == true { continue }
            guard let v = d.ledgerVolumeBySession[s.id] else { continue }
            volByDate[s.date, default: []].append(v)
        }

        var out: [LedgerWeek] = []
        var ws = ctx.weekZeroStart ?? weekStart
        while ws <= weekStart {
            let dates = (0..<7).map { ISODate.addDays(ws, $0) ?? ws }
            let days: [ExportDay] = try dates.enumerated().map { i, date in
                try make([
                    "date": date, "weekdayLabel": Self.weekdayLabels[i], "isTrainingDay": Schedule.isTrainingDayIn(ctx, date),
                    "weightKg": j(logByDate[date]?.weightKg), "calories": j(kcalByDate[date]),
                    "steps": j(logByDate[date]?.steps.map(Double.init)),
                    "waterMl": j(waterByDate[date] ?? logByDate[date]?.waterMl),
                    "nutritionEstimated": false,
                ])
            }
            let sessions: [ExportSession] = try dates.flatMap { volByDate[$0] ?? [] }.map {
                try make(["date": "", "label": "", "volumeKg": $0, "exercises": [] as [Any], "prs": [] as [Any]])
            }
            let cardio: [ExportCardio] = try dates.flatMap { cardioByDate[$0] ?? [] }.map {
                try make(["date": "", "kind": "", "durationMin": $0])
            }
            out.append(try make([
                "label": Week.label(ofWeekStart: ws, anchor: ctx.weekZeroStart, phases: ctx.phases), "weekStart": ws,
                "totals": Self.encodeToJSON(WeeklyExport.trendTotals(days: days, sessions: sessions, cardio: cardio)),
            ]))
            guard let next = ISODate.addDays(ws, 7) else { break }
            ws = next
        }
        return out
    }

    // MARK: - Helpers

    /// OnyxCore's export types have no public initialisers; they are built
    /// the way the fixture is — as JSON. `NSNull` is an explicit null.
    func make<T: Decodable>(_ fields: [String: Any]) throws -> T {
        try JSONDecoder().decode(T.self, from: try JSONSerialization.data(withJSONObject: fields))
    }

    static func encodeToJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: try JSONEncoder().encode(value)) as? [String: Any] ?? [:]
    }

    static func numbers(_ text: JSONText) -> [String: Double]? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.raw.utf8)) as? [String: Any] else { return nil }
        return obj.compactMapValues { ($0 as? NSNumber).map(\.doubleValue) }.filter { $0.value.isFinite }
    }

    static func custom(_ r: CustomSupplementRow) -> CustomSupplement {
        CustomSupplement(
            id: r.id, name: r.name, dose: r.dose, color: r.color, form: r.form, time: r.time,
            schedule: r.schedule.flatMap { try? JSONDecoder().decode(CustomSchedule.self, from: Data($0.raw.utf8)) },
            micros: r.micros.flatMap(numbers)
        )
    }

    /// `L` / `R` or nil — the export never carries another spelling.
    static func lr(_ side: String?) -> String? { side == "L" || side == "R" ? side : nil }

    static func volume(_ sets: [HistorySetRow]) -> Double {
        SessionVolume.sessionVolumeKg(sets.map {
            VolumeSet(weightKg: $0.weightKg, reps: Double($0.reps), side: lr($0.lr), pairId: $0.pairId, setType: $0.setType)
        })
    }

    /// `countCommittedSets` — what the web wrote to `set_count`.
    static func committedSets(_ sets: [HistorySetRow]) -> Int {
        var pairs = Set<String>()
        var solo = 0
        for s in sets where s.setType != "ghost" {
            if let p = s.pairId, !p.isEmpty { pairs.insert(p) } else { solo += 1 }
        }
        return solo + pairs.count
    }

    /// Local wall-clock ISO with offset — the "THH:MM" the renderer reads.
    func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f.string(from: date)
    }

    /// Local wall-clock `HH:mm` — what a stress event prints as.
    func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// `Date.toISOString()` — what `nightOf` buckets on.
    static func utcStamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func utc(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    /// JS `Array.sort` is stable; Swift's is not guaranteed to be.
    static func stableSorted<T>(_ items: [T], by less: (T, T) throws -> Bool) rethrows -> [T] {
        try items.enumerated().sorted { a, b in
            if try less(a.element, b.element) { return true }
            if try less(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}

/// Optional → JSON value (`NSNull` for nil), for the dictionaries `make` decodes.
private func j<T>(_ v: T?) -> Any {
    if let v { return v }
    return NSNull()
}
