import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The chart series builders — a port of the web app's `lib/charts/series.ts` (§6.5).
//
// Four questions the screens ask of the ledger, answered once each and
// replayed against the TypeScript in `SeriesGoldenTests`. Nothing here reads
// a store or a clock: dates arrive as ISO strings and `endingOn` is the
// caller's "today".
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Estimated 1RM per session

/// One working set as the trend reads it. `est` is the STORED estimate.
public struct TrendSetRow: Codable, Sendable, Equatable {
    public var weightKg: Double
    public var reps: Double
    public var est: Double?
    public var side: String?
    public var pairId: String?

    public init(weightKg: Double, reps: Double, est: Double? = nil, side: String? = nil, pairId: String? = nil) {
        self.weightKg = weightKg
        self.reps = reps
        self.est = est
        self.side = side
        self.pairId = pairId
    }
}

public struct ExerciseTrend: Codable, Sendable, Equatable {
    /// Per-session headline, oldest → newest: the MEAN across that session's
    /// working sets, one decimal — est-1RM kg loaded, seconds timed, reps
    /// unloaded. The mean, not the best set: on a double-progression program
    /// the top set reaches the ceiling first and then holds there while the
    /// rest climb, and a max drew five improving sessions as a flat line.
    public var points: [Double]
    public var pctChange: Double?
    /// All-time best SET.
    public var best: Double
    /// Latest session's working volume (kg loaded · reps/seconds otherwise).
    public var tonnage: Double
    public var tonnageDelta: Double?
    public var topSet: WorkingSet?
    /// Sets AT THE TOP LOAD that reached the ceiling in the latest session.
    public var setsAtCeiling: Double
    public var progression: ProgressionVerdict
    public var timed: Bool
    /// `points` and `tonnage` are reps or seconds rather than kg.
    public var byReps: Bool
}

public enum E1rmSeries {
    /// How many sets AT THE TOP LOAD reached the ceiling — the "2/3 @ 12"
    /// chip. Counting every set whose reps met the number credited back-off
    /// sets as if they were at the load being chased.
    public static func setsAtCeiling(_ sets: [WorkingSet], ceiling: Double?) -> Double {
        guard let ceiling else { return 0 }
        let work = Ceilings.workLoads(sets)
        guard let top = work.map(\.weightKg).max() else { return 0 }
        return Double(work.filter { $0.weightKg == top && $0.reps >= ceiling }.count)
    }

    /// L + R rows sharing a `pairId` are ONE set: differing L/R loads would
    /// otherwise trip the "single top weight" gate and never clear. The RIGHT
    /// side leads, falling back to the higher-rep side. First-seen order, as
    /// the TypeScript's Map iterates.
    public static func collapsePairs(_ sets: [TrendSetRow]) -> [TrendSetRow] {
        var order: [String] = []
        var pairs: [String: [TrendSetRow]] = [:]
        var out: [TrendSetRow] = []
        for s in sets {
            guard let id = s.pairId, !id.isEmpty else { out.append(s); continue }
            if pairs[id] == nil { order.append(id) }
            pairs[id, default: []].append(s)
        }
        for id in order {
            let g = pairs[id]!
            out.append(g.first { $0.side == "R" } ?? g.dropFirst().reduce(g[0]) { $1.reps > $0.reps ? $1 : $0 })
        }
        return out
    }

    /// The trend of one exercise over its sessions, oldest FIRST, working sets
    /// only. Nil with no sessions. Unloaded work (no session ever carried load)
    /// is scored on reps, checked across the WHOLE history; a stored est-1RM
    /// wins over Epley with `||` semantics (a stored 0 is missing).
    public static func build(_ sessions: [[TrendSetRow]], timed: Bool, ceiling: Double?) -> ExerciseTrend? {
        guard !sessions.isEmpty else { return nil }
        let unloaded = !timed && sessions.allSatisfy { $0.allSatisfy { !($0.weightKg > 0) } }
        let byReps = timed || unloaded

        func headline(_ s: TrendSetRow) -> Double {
            if byReps { return s.reps }
            // TS `est || Epley`: 0 AND NaN are falsy there, so both fall through.
            if let est = s.est, est != 0, !est.isNaN { return est }
            return Epley.oneRepMax(weight: s.weightKg, reps: s.reps) ?? 0
        }
        func bestOf(_ sets: [TrendSetRow]) -> Double { sets.reduce(0) { Swift.max($0, headline($1)) } }
        func meanOf(_ sets: [TrendSetRow]) -> Double {
            let one = collapsePairs(sets)
            guard !one.isEmpty else { return 0 }
            return one.reduce(0) { $0 + headline($1) } / Double(one.count)
        }
        func tonnageOf(_ sets: [TrendSetRow]) -> Double {
            jsRound(byReps
                ? collapsePairs(sets).reduce(0) { $0 + $1.reps }
                : SessionVolume.sessionVolumeKg(sets.map {
                    VolumeSet(weightKg: $0.weightKg, reps: $0.reps, side: $0.side == "L" || $0.side == "R" ? $0.side : nil, pairId: $0.pairId)
                }))
        }
        func asWorking(_ sets: [TrendSetRow]) -> [WorkingSet] {
            collapsePairs(sets).map { WorkingSet(weightKg: $0.weightKg, reps: $0.reps) }
        }

        let points = sessions.map { jsRound1(meanOf($0)) }
        let cur = points[points.count - 1]
        let prev: Double? = points.count >= 2 ? points[points.count - 2] : nil
        let latest = sessions[sessions.count - 1]
        let prevSets: [TrendSetRow]? = sessions.count >= 2 ? sessions[sessions.count - 2] : nil

        let topSet = latest.reduce(nil as TrendSetRow?) { best, s in
            guard let best else { return s }
            return headline(s) > headline(best) ? s : best
        }
        let tonnage = tonnageOf(latest)
        let ladder = prevSets.map { [asWorking($0), asWorking(latest)] } ?? [asWorking(latest)]

        return ExerciseTrend(
            points: points,
            pctChange: prev.flatMap { $0 > 0 ? jsRound((cur - $0) / $0 * 1000) / 10 : nil },
            best: sessions.map(bestOf).max() ?? 0,
            tonnage: tonnage,
            tonnageDelta: prevSets.map { tonnage - tonnageOf($0) },
            topSet: topSet.map { WorkingSet(weightKg: $0.weightKg, reps: $0.reps) },
            setsAtCeiling: setsAtCeiling(asWorking(latest), ceiling: ceiling),
            progression: timed
                ? Ceilings.timedProgressionVerdict(ladder, targetSec: ceiling)
                : Ceilings.progressionVerdict(ladder, ceiling: ceiling),
            timed: timed,
            byReps: byReps
        )
    }
}

// MARK: - Session volume by split

public struct VolumeSession: Codable, Sendable, Equatable {
    public var date: String
    /// `workout_sessions.day_key` — what was PERFORMED.
    public var dayKey: String?
    /// The legacy `split_day` column, for rows written before `day_key`.
    public var split: String?
    public var volumeKg: Double?

    public init(date: String, dayKey: String? = nil, split: String? = nil, volumeKg: Double?) {
        self.date = date
        self.dayKey = dayKey
        self.split = split
        self.volumeKg = volumeKg
    }
}

public enum SessionVolumeSeries {
    /// Tonnage per day for one chart split (nil = every session), newest
    /// `limit` days, oldest first. Same-day sessions add up; empty days are
    /// omitted — `WidgetDerive.paddedWindow` lays it on a fixed axis.
    public static func build(_ sessions: [VolumeSession], splitDay: String?, era: String, limit: Int) -> [TrendPoint] {
        let rows = sessions
            .filter { s in
                guard let splitDay else { return true }
                return VolumeSplit.resolve(dateISO: s.date, split: s.split ?? "", era: era, dayKey: s.dayKey) == splitDay
            }
            .map { DatedValue(date: $0.date, value: $0.volumeKg) }
        return WidgetDerive.dailySeries(rows, limit: limit, combine: .sum)
    }
}

// MARK: - Macro adherence, seven days

public struct AdherenceDayIn: Codable, Sendable, Equatable {
    public var date: String
    public var kcal: Double?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    /// `daily_logs.nutrition_exception`, verbatim.
    public var exception: String?
    public var estimated: Bool?

    public init(date: String, kcal: Double? = nil, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil, exception: String? = nil, estimated: Bool? = nil) {
        self.date = date
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.exception = exception
        self.estimated = estimated
    }
}

/// What the day was graded against — `ResolvedTargets` for that date.
public struct AdherenceTargets: Codable, Sendable, Equatable {
    public var kcal: Double
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?

    public init(kcal: Double, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

/// `untracked` nothing logged (no kcal, or 0) · `ungraded` logged but no
/// target · `exception` a declared exception day (its own colour, not a hit
/// or a miss) · `hit` · `miss`.
public enum AdherenceVerdict: String, Codable, Sendable {
    case untracked, ungraded, exception, hit, miss
}

public struct AdherenceDay: Codable, Sendable, Equatable {
    public var date: String
    public var verdict: AdherenceVerdict
    /// intake ÷ target × 100, one decimal; nil without both.
    public var kcalPct: Double?
    public var proteinPct: Double?
    public var carbsPct: Double?
    public var fatPct: Double?
    public var estimated: Bool
}

public enum MacroAdherenceSeries {
    /// A day within this much of its calorie target is a hit (`coach/insights`).
    public static let tolerancePct = 10.0

    static func pct(_ intake: Double?, _ target: Double?) -> Double? {
        guard let intake, let target, target > 0 else { return nil }
        return jsRound(intake / target * 1000) / 10
    }

    /// The seven dots (or `limit`) ending on `endingOn`, oldest first, every
    /// date present. A hit is calories within ±10 % AND protein at least 90 %
    /// of its target when one is set; an exception day is graded elsewhere on
    /// protein alone and drawn as an exception. `targets` is keyed by date —
    /// the rung in force ON THAT DATE, not today's.
    public static func build(_ days: [AdherenceDayIn], targets: [String: AdherenceTargets], endingOn: String, limit: Int = 7) -> [AdherenceDay] {
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        return WidgetDerive.paddedWindow([], endingOn: endingOn, limit: limit).map { slot in
            let day = byDate[slot.date]
            let t = targets[slot.date]
            let kcalPct = pct(day?.kcal, t?.kcal)
            let proteinPct = pct(day?.proteinG, t?.protein)
            var out = AdherenceDay(
                date: slot.date, verdict: .untracked, kcalPct: kcalPct, proteinPct: proteinPct,
                carbsPct: pct(day?.carbsG, t?.carbs), fatPct: pct(day?.fatG, t?.fat),
                estimated: day?.estimated == true
            )
            // `<= 0` is nothing logged, as the nutrition score reads it.
            guard let day, let kcal = day.kcal, kcal > 0 else { return out }
            if ExceptionDay.isException(day.exception) { out.verdict = .exception; return out }
            guard let kcalPct else { out.verdict = .ungraded; return out }
            let kcalHit = abs(kcalPct - 100) <= tolerancePct
            let proteinHit = proteinPct.map { $0 >= 100 - tolerancePct } ?? true
            out.verdict = kcalHit && proteinHit ? .hit : .miss
            return out
        }
    }
}

// MARK: - Vitals

public struct VitalSeries: Codable, Sendable, Equatable {
    /// Exactly `days` buckets ending on `endingOn`; nil where nothing landed.
    public var points: [DatedValue]
    public var latest: Double?
    /// Movement from the newest reading that DIFFERS (≥ 0.05), two decimals.
    public var delta: Double?
    /// Mean of the readings in the window, one decimal.
    public var mean: Double?
    /// Days in the window with a reading.
    public var coverage: Double

    /// `max` for readings (a re-sync must not double a heart rate), `sum` for
    /// quantities — steps, stand hours, active energy.
    public typealias Combine = WidgetDerive.Combine

    /// One vital over a 7- or 30-day window. Days outside the window are
    /// dropped, never folded onto its edge; a missing day is a gap, not a zero.
    public static func build(_ rows: [DatedValue], days: Int, endingOn: String, combine: Combine) -> VitalSeries {
        // No `limit` clamp before the window: a reading dated after `endingOn`
        // must not push a real day out of the newest-N slice.
        let points = WidgetDerive.paddedWindow(WidgetDerive.dailySeries(rows, limit: rows.count, combine: combine), endingOn: endingOn, limit: days)
        let real = points.compactMap { p in p.value.map { (date: p.date, value: $0) } }
        let latest = real.last?.value
        let previous = latest.flatMap { l in real.reversed().first { abs($0.value - l) >= 0.05 } }
        return VitalSeries(
            points: points,
            latest: latest,
            delta: latest.flatMap { l in previous.map { jsRound((l - $0.value) * 100) / 100 } },
            mean: real.isEmpty ? nil : jsRound(real.reduce(0) { $0 + $1.value } / Double(real.count) * 10) / 10,
            coverage: Double(real.count)
        )
    }
}
