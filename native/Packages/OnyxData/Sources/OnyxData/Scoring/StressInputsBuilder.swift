import Foundation
import GRDB
import OnyxCore

/// The stress index's data half — rows in, `StressInputs` out (Phase 3 E3).
///
/// ── COMPUTED ON READ, NO COLUMN ─────────────────────────────────────────────
/// v1 stores nothing (`docs/STRESS_MODEL.md` §6). The Pulse tile asks for one
/// day and the Trends series for fourteen, and each day is one
/// `readinessHistory` read (five narrow table scans on a local SQLite file)
/// plus the day's own fatigue rows and flat row. Fourteen of those is a few
/// milliseconds on device, which is why nothing is cached or stored yet.
/// Since W6 `stressSeries` reads its fortnight as ONE window and slices it per
/// day, so the fourteen are one pass over five tables rather than fourteen.
/// ponytail: still computed on read, never stored; the documented upgrade is
/// `daily_scores.stress_index` + `stress_breakdown` written by the scorer.
///
/// ── THE SAME SCALARS THE BATTERY READS, BY DESIGN ───────────────────────────
/// `hrvZ`, `rhrZ`, `acwr`, `strainZ` and the onset flag come from exactly the
/// calls `scoringInputs` makes, so the tile and the battery stack cannot
/// disagree about the same fact. The two the battery does not read — the
/// fragmentation z and the day MEAN of fatigue — are built here.
public extension AppDatabase {

    /// One day's stress inputs. A day with nothing to say comes back with every
    /// field nil, and `Stress.breakdown` reads that as no reading.
    func stressInputs(userId: String, date: String) throws -> StressInputs {
        try writer.read { db in try Self.stressInputs(db, userId: userId, date: date) }
    }

    /// `schedule` is an optimisation and nothing else: it is the same context
    /// this would resolve for itself, hoisted by `stressSeries` so a fortnight
    /// costs one resolution rather than fourteen. Passing a context for a
    /// DIFFERENT user is the one way to make this lie.
    static func stressInputs(
        _ db: Database, userId: String, date: String, schedule: ScheduleContext? = nil
    ) throws -> StressInputs {
        let history = try readinessHistory(db, userId: userId, date: date)
        let signals = Readiness.signals(history)
        let frag = Stress.fragmentationZ(awakeMin: history.awakeMin ?? [], asleepMin: history.asleepMin ?? [])

        let log = try DailyLogRow
            .filter(Column("user_id") == userId && Column("date") == date)
            .fetchOne(db)

        // ── THE DAY MEAN, NOT THE LATEST, AND FOLDED AS THE DAY ACTUALLY WAS ─
        // This used to fold every day as a TRAINING day, on the argument that
        // the legacy keys are a bijection either way ({morning, noon, evening,
        // eod} onto {waking, pre, post} on a training day and onto {waking,
        // midday, night} on a rest day), so the mean over the slots comes out
        // the same. That is true of a day whose rows are ALL legacy or ALL
        // modern, and it is the only kind of day the argument considered.
        //
        // A MIXED day breaks it. A rest day carrying a legacy `noon` and a
        // modern `midday` folds to two slots when read as training (`pre` and
        // `midday`, both counted) and to one when read as rest (both land on
        // `midday`, later-wins). Two readings of 5 and 1 mean 3.0 one way and
        // 5.0 or 1.0 the other — and `fatigueDayMean` is a stress TERM, so the
        // tile reports a rest day as several points more stressed than the day
        // the athlete actually had. Every device that answers a slot under the
        // new vocabulary while an old row survives is such a day.
        //
        // `ScoringInputsBuilder` has always passed the real kind here
        // (`isTraining: !isRestDay`). This file's whole premise is that the
        // tile and the battery cannot disagree about the same fact, so it
        // resolves the day the same way rather than assuming past it.
        let fatigueRows = try FatigueLogRow
            .filter(Column("user_id") == userId && Column("date") == date)
            .fetchAll(db)
            .map { FatigueRow(slot: $0.slot, level: $0.level) }
        //
        // And "the real kind" is the day as LOGGED, not as planned — a session
        // on the calendar's rest day is a training day (`isTrainingDay`).
        let isTraining = try Self.isTrainingDay(
            db, userId: userId, date: date, schedule: try schedule ?? Self.scheduleContext(db, userId: userId)
        )

        // ── THE SECOND SELF-REPORT (D6) ─────────────────────────────────────
        // `stress_logs` has no slot vocabulary to fold: every row of the day
        // is one answer, and the mean of them is the day's stress. Nil when
        // nothing was logged, so a day with only fatigue reads as it did
        // before the table existed.
        let stressLevels = try StressLogRow
            .filter(Column("user_id") == userId && Column("date") == date)
            .fetchAll(db)
            .map { Double($0.level) }

        return Self.stressInputs(
            history: history, log: log, fatigueRows: fatigueRows,
            isTraining: isTraining, stressLevels: stressLevels
        )
    }

    /// The assembly, off rows already in hand — the same two-variant shape
    /// `readinessHistory` has, and for the same reason: `stressSeries` reads
    /// its fortnight as one window and needs to fold each day without going
    /// back to the database.
    static func stressInputs(
        history: ReadinessHistory,
        log: DailyLogRow?,
        fatigueRows: [FatigueRow],
        isTraining: Bool,
        stressLevels: [Double]
    ) -> StressInputs {
        let signals = Readiness.signals(history)
        let frag = Stress.fragmentationZ(awakeMin: history.awakeMin ?? [], asleepMin: history.asleepMin ?? [])
        let fatigueDayMean = Fatigue.dayMean(Fatigue.foldRows(fatigueRows, isTraining: isTraining))
        let stressDayMean: Double? = stressLevels.isEmpty
            ? nil
            : stressLevels.reduce(0, +) / Double(stressLevels.count)
        return StressInputs(
            hrvZ: signals.hrv.z,
            rhrZ: signals.rhr.z,
            fragZ: frag.z,
            // The column is NOT NULL DEFAULT false: a missing row is the same
            // statement as an unticked night, as the scorer reads it.
            sleepOnsetTrouble: log?.sleepOnsetTrouble ?? false,
            fatigueDayMean: fatigueDayMean,
            stressDayMean: stressDayMean,
            acwr: signals.load.acwr,
            strainZ: signals.load.strainZ
        )
    }

    /// The day's reading, term by term — what the tile's breakdown sheet draws.
    func stressBreakdown(userId: String, date: String) throws -> Stress.Breakdown {
        Stress.breakdown(try stressInputs(userId: userId, date: date))
    }

    /// `limit` days ending on `endingOn`, computed on read, for the Trends
    /// series and the tile's sparkline. A day with nothing answered comes back
    /// empty, never as a 50.
    func stressSeries(userId: String, endingOn: String, limit: Int = 14) throws -> [StressDay] {
        guard limit > 0 else { return [] }
        let dates = (0..<limit).map { ISODate.addDays(endingOn, -$0) ?? endingOn }.reversed().map { $0 }
        let days = try writer.read { db in
            // ── ONE WINDOW, NOT FOURTEEN (W6) ───────────────────────────────
            // Every day of the fortnight needs the 49-day readiness series
            // behind it, and those fourteen series overlap by 48 days each.
            // Read the union once — `[endingOn − 13 − 48, endingOn]` — and hand
            // each date the same rows; `readinessHistory(dates:…)` already
            // ignores rows outside the dates it was given, which is the seam
            // that makes this free. The per-day tables (`fatigue_log`,
            // `stress_logs`, `daily_logs`) are read as one range each and
            // grouped, rather than three narrow queries per day.
            //
            // The schedule does not vary by date — the overrides and the
            // layout ARE the per-date rules — so it is resolved once.
            let schedule = try Self.scheduleContext(db, userId: userId)
            let first = dates.first ?? endingOn
            let user = Column("user_id") == userId
            let span = user && Column("date") >= first && Column("date") <= endingOn
            let historyStart = Self.readinessHistoryStart(first)
            let historySpan = user && Column("date") >= historyStart && Column("date") <= endingOn

            // `.order(Column.rowID)` for the reason `ScoringWindow.load`
            // gives about its own metrics read: the per-day path this replaces
            // was `fetchOne` on a (user, date) filter, which is THE FIRST ROW
            // THE SCAN FINDS, and keeping the first per date is what
            // reproduces it. `daily_logs` has no local unique index on
            // (user_id, date) — the constraint is server-side — and this
            // codebase has already met a device holding two rows for one day.
            let logs = try DailyLogRow.filter(historySpan).order(Column.rowID).fetchAll(db)
            let metrics = try DailyMetricRow.filter(historySpan).fetchAll(db)
            let sessions = try WorkoutSession.filter(historySpan).fetchAll(db)
            let cardio = try CardioLogRow.filter(historySpan).fetchAll(db)
            // The union of every night window the fortnight's histories reach.
            var nights: [SleepSessionRow] = []
            if let from = NightWindow.range(historyStart), let to = NightWindow.range(endingOn) {
                nights = try SleepSessionRow
                    .filter(user && Column("start_time") >= from.from && Column("start_time") < to.to)
                    .fetchAll(db)
            }
            let logByDate = Dictionary(logs.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
            var fatigueByDate: [String: [FatigueRow]] = [:]
            for row in try FatigueLogRow.filter(span).fetchAll(db) {
                fatigueByDate[row.date, default: []].append(FatigueRow(slot: row.slot, level: row.level))
            }
            var stressByDate: [String: [Double]] = [:]
            for row in try StressLogRow.filter(span).fetchAll(db) {
                stressByDate[row.date, default: []].append(Double(row.level))
            }
            // A day with a session is a training day whatever the calendar
            // promised (`isTrainingDay`) — answered off the rows already read.
            let trained = Set(sessions.map(\.date))

            return dates.map { date -> StressDayIn in
                let history = Self.readinessHistory(
                    dates: Self.readinessHistoryDates(date),
                    logs: logs, metrics: metrics, sessions: sessions, cardio: cardio, nights: nights
                )
                let isTraining = Schedule.isTrainingDayIn(schedule, date) || trained.contains(date)
                let levels = stressByDate[date] ?? []
                return StressDayIn(
                    date: date,
                    breakdown: Stress.breakdown(Self.stressInputs(
                        history: history,
                        log: logByDate[date],
                        fatigueRows: fatigueByDate[date] ?? [],
                        isTraining: isTraining,
                        stressLevels: levels
                    ))
                )
            }
        }
        return StressSeries.build(days, endingOn: endingOn, limit: limit)
    }
}
