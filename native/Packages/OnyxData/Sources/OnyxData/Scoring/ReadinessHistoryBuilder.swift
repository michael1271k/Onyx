import Foundation
import GRDB
import OnyxCore

/// The data layer's half of readiness v9 — rows in, a `ReadinessHistory` out.
/// A port of the web app's `lib/scoring/readinessHistory.ts`, and the ONE place on the
/// phone that decides how rows become the 49-day series: which resting-HR
/// column wins, whether a missing day is a nil or a zero. `readiness-history
/// .test.ts` pins those rules for the web; `ReadinessHistoryTests` pins them
/// here against the same cases.
///
/// ── THE ONE KNOWN SEAM ──────────────────────────────────────────────────────
/// The web files a session under the UTC date of `started_at`; the phone
/// under its local logical day (`WorkoutSession.date`). They can differ on a
/// session started after local midnight. Pre-existing — the day's own
/// sessions are already read that way on each side — and not widened here.
extension AppDatabase {

    /// The first day the history reaches back to.
    static func readinessHistoryStart(_ date: String) -> String {
        ISODate.addDays(date, -(Readiness.constants.historyDays - 1)) ?? date
    }

    /// 49 consecutive dates, oldest first, ending on `date`.
    static func readinessHistoryDates(_ date: String) -> [String] {
        let start = readinessHistoryStart(date)
        return (0..<Readiness.constants.historyDays).map { ISODate.addDays(start, $0) ?? start }
    }

    /// The 49-day series behind a date. Resting HR reads `daily_metrics.rest_hr`
    /// first and `daily_logs.avg_rest_heart_rate` second — the scorer's own rule
    /// for the day itself, so the rolling window and its last entry agree. A day
    /// with neither is nil; a day with no session is a real zero load.
    static func readinessHistory(_ db: Database, userId: String, date: String) throws -> ReadinessHistory {
        let dates = readinessHistoryDates(date)
        let start = dates.first ?? date
        let window = Column("user_id") == userId && Column("date") >= start && Column("date") <= date

        var hrvByDate: [String: Double?] = [:]
        var rhrLog: [String: Double?] = [:]
        for r in try DailyLogRow.filter(window).fetchAll(db) {
            hrvByDate[r.date] = r.hrvMs
            rhrLog[r.date] = r.avgRestHeartRate.map(Double.init)
        }
        var rhrMetric: [String: Double?] = [:]
        for r in try DailyMetricRow.filter(window).fetchAll(db) {
            rhrMetric[r.date] = r.restHr.map(Double.init)
        }
        let sessions = try WorkoutSession.filter(window).fetchAll(db).map {
            LoadSession(date: $0.date, sessionRpe: $0.sessionRpe, durationMin: $0.durationMin)
        }
        let cardio = try CardioLogRow.filter(window).fetchAll(db).map {
            LoadCardio(date: $0.date, effort: $0.effort, durationMin: $0.durationMin)
        }

        // ── THE NIGHTS, ONE PER DATE, LONGEST WINS (E3) ─────────────────────
        // Filed under the morning they ended on (`NightWindow.nightOf`) — the
        // date the scorer reads them under — and where a window holds two rows
        // the longest is the night, as `scoringInputs` and `sleepNightStream`
        // already decide. The union of the 49 night windows is one range.
        var nightByDate: [String: SleepSessionRow] = [:]
        if let first = NightWindow.range(start), let last = NightWindow.range(date) {
            let nights = try SleepSessionRow
                .filter(Column("user_id") == userId && Column("start_time") >= first.from && Column("start_time") < last.to)
                .fetchAll(db)
            for n in nights {
                let d = NightWindow.nightOf(n.startTime)
                guard d >= start, d <= date else { continue }
                if let held = nightByDate[d], held.durationMin >= n.durationMin { continue }
                nightByDate[d] = n
            }
        }
        let asleepMin: [Double?] = dates.map { d in
            guard let n = nightByDate[d], n.durationMin > 0 else { return nil }
            return Double(n.durationMin)
        }
        let awakeMin: [Double?] = dates.map { d in
            guard let n = nightByDate[d], n.durationMin > 0 else { return nil }
            // A duration-only row (awake = deep = rem = 0) has no stage data;
            // its zero is an absence, not a still night. `fragmentationRatio`
            // is the one rule, on both platforms.
            let night = Stress.FragmentationNight(
                awakeMin: n.awakeMin.map(Double.init), asleepMin: Double(n.durationMin),
                deepMin: n.deepMin.map(Double.init), remMin: n.remMin.map(Double.init)
            )
            return Stress.fragmentationRatio(night) == nil ? nil : n.awakeMin.map(Double.init)
        }

        return ReadinessHistory(
            hrv: dates.map { hrvByDate[$0] ?? nil },
            rhr: dates.map { (rhrMetric[$0] ?? nil) ?? (rhrLog[$0] ?? nil) },
            loads: Readiness.dailyLoads(dates: dates, sessions: sessions, cardio: cardio),
            awakeMin: awakeMin,
            asleepMin: asleepMin
        )
    }
}

public extension AppDatabase {

    /// The training-load signal as of `date`: Foster's week ENDING on it, and
    /// the EWMA acute:chronic ratio at it.
    ///
    /// ── WHY A DOOR AND NOT A SECOND SERIES (W1b) ────────────────────────────
    /// `readinessHistory` is the one place on the phone that decides how rows
    /// become the 49-day series, and the battery has been scored through it
    /// since v9. The week detail needs the same series to a different endpoint
    /// — the week's last day rather than today — and building one for itself is
    /// how two screens start disagreeing about the same fortnight. So this
    /// exposes the existing accumulator at an arbitrary date and adds no
    /// arithmetic of its own.
    ///
    /// `Readiness.loadSignal` is the PUBLIC path and the only one used here.
    /// `fosterWeek` is internal to OnyxCore and stays that way: the caller
    /// wants a week's strain, and `loadSignal` already computes exactly that
    /// from the last `monotonyDays` of the series it is handed.
    ///
    /// ── WHAT `date` HAS TO BE ───────────────────────────────────────────────
    /// `LoadSignal.strain` is Foster's over the series' LAST SEVEN ENTRIES. It
    /// is a given calendar week's strain only when `date` is that week's last
    /// day; hand it any other date and the seven days it reports on straddle
    /// two weeks. A date in the FUTURE is legal and honest — every day after
    /// today carries a real zero load, so a live week reports the strain of
    /// what has been logged so far — but see the caller's own note before
    /// putting the ratio beside it.
    func loadSignal(userId: String, date: String) throws -> LoadSignal {
        try read { db in
            Readiness.loadSignal(try Self.readinessHistory(db, userId: userId, date: date).loads)
        }
    }
}
