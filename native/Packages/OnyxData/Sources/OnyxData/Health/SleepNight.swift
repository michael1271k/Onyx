import Foundation

/// One HealthKit sleep sample, reduced to what the aggregation needs.
public struct SleepSample: Sendable, Equatable {
    /// HealthKit's `HKCategoryValueSleepAnalysis`: 0 inBed · 1 asleepUnspecified
    /// · 2 awake · 3 asleepCore · 4 asleepDeep · 5 asleepREM.
    public var value: Int
    public var start: Date
    public var end: Date

    public init(value: Int, start: Date, end: Date) {
        self.value = value
        self.start = start
        self.end = end
    }
}

/// A night, aggregated.
public struct SleepNight: Sendable, Equatable {
    public var sleepMinutes: Int
    public var deepMin: Int
    public var remMin: Int
    public var coreMin: Int
    public var awakeMin: Int
    public var bedStart: Date?
    public var bedEnd: Date?
    /// When sleep BEGAN — the earliest asleep sample (W3). nil when the night
    /// was aggregated from a duration alone. `onset − bedStart` is the latency
    /// term of the sleep score.
    public var onset: Date? = nil
    /// Merged awake intervals of five minutes or more AFTER `onset`. A
    /// one-minute stir the watch labels awake is not an awakening anyone
    /// remembers, and the lie-awake before sleep is the latency, not a
    /// waking. `awakeMin` still counts every awake minute in the window.
    public var awakenings: Int = 0

    /// The bed window, in minutes — efficiency's denominator. Zero when the
    /// night has no window, which the scorer reads as "no efficiency term".
    public var inBedMinutes: Int {
        guard let bedStart, let bedEnd, bedEnd > bedStart else { return 0 }
        return Int((bedEnd.timeIntervalSince(bedStart) / 60).rounded())
    }

    /// What `core_min` stores: the real per-stage split when present, else
    /// everything asleep — which is what a legacy duration-only reading means.
    /// One rule for `writeSleep` and the trim engine.
    public var storedCoreMin: Int {
        coreMin > 0 ? coreMin : max(0, sleepMinutes - deepMin - remMin)
    }
}

/// The night window, and the union arithmetic that makes a night one number.
public enum Sleep {

    /// Total minutes covered by a set of intervals, counting overlap ONCE.
    ///
    /// ── THE WHOLE REASON THIS FUNCTION EXISTS ───────────────────────────────
    /// iPhone and Watch both write sleep, and their samples overlap. Naive
    /// summation inflated the night: the app read 9h11m where Apple — which
    /// dedupes by source priority — showed 9h15m, and the error moved in both
    /// directions depending on which sources were active.
    public static func mergedMinutes(_ intervals: [(start: Date, end: Date)]) -> Double {
        merged(intervals).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60
    }

    /// The union, as disjoint intervals in time order. Overlapping or adjacent
    /// spans join; the count of what comes back is the count of separate
    /// episodes, which is what `awakenings` is.
    static func merged(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var out: [(start: Date, end: Date)] = []
        var current = sorted[0]
        for next in sorted.dropFirst() {
            if next.start <= current.end {
                current.end = max(current.end, next.end)   // overlapping or adjacent
            } else {
                out.append(current)
                current = next
            }
        }
        out.append(current)
        return out
    }

    /// Bucket a night's samples and merge each stage.
    ///
    /// `nil` when nothing slept — never a zero-minute night, which would be a
    /// claim rather than a gap and would overwrite a real reading from another
    /// source on the next sync.
    public static func aggregate(_ samples: [SleepSample]) -> SleepNight? {
        var deep: [(start: Date, end: Date)] = []
        var rem: [(start: Date, end: Date)] = []
        var core: [(start: Date, end: Date)] = []
        var awake: [(start: Date, end: Date)] = []
        var bedStart: Date?
        var bedEnd: Date?
        var onset: Date?

        for sample in samples where sample.end > sample.start {
            if bedStart == nil || sample.start < bedStart! { bedStart = sample.start }
            if bedEnd == nil || sample.end > bedEnd! { bedEnd = sample.end }
            let span = (start: sample.start, end: sample.end)
            switch sample.value {
            case 4: deep.append(span)
            case 5: rem.append(span)
            case 1, 3: core.append(span)   // asleepUnspecified + asleepCore
            case 2: awake.append(span)
            default: break                 // 0 inBed → the bed window only
            }
            // Onset is the first minute ASLEEP, whatever the stage — an in-bed
            // or awake sample before it is exactly the latency being measured.
            if [1, 3, 4, 5].contains(sample.value), onset == nil || sample.start < onset! {
                onset = sample.start
            }
        }

        // ── TOTAL IS THE UNION OF ALL ASLEEP STAGES TOGETHER ────────────────
        // Not the sum of separately-merged stages. When two sources label the
        // same minute differently — one Core, one REM — a per-stage sum counts
        // it twice. HealthKit exposes no precomputed "time asleep" scalar;
        // Apple's own Health app derives its number from these same samples, so
        // this is the closest faithful reconstruction rather than a value that
        // can be read directly.
        let total = Int(mergedMinutes(deep + rem + core).rounded())
        guard total > 0 else { return nil }
        return SleepNight(
            sleepMinutes: total,
            deepMin: Int(mergedMinutes(deep).rounded()),
            remMin: Int(mergedMinutes(rem).rounded()),
            coreMin: Int(mergedMinutes(core).rounded()),
            awakeMin: Int(mergedMinutes(awake).rounded()),
            bedStart: bedStart,
            bedEnd: bedEnd,
            onset: onset,
            // ≥ 5 min and after onset: `clip` inherits this, so a trim that
            // cuts an awakening to four minutes at the edge stops counting it.
            awakenings: merged(awake)
                .filter { $0.end.timeIntervalSince($0.start) >= 5 * 60 && $0.start >= (onset ?? .distantPast) }
                .count
        )
    }
}

// MARK: - Strategy A: the same samples, a narrower window

public extension Sleep {
    /// The samples INSIDE `[start, end]`, each clipped to it. A sample that
    /// straddles an edge keeps only its inner part; one wholly outside is gone.
    /// `aggregate` over the result is the trim engine's strategy A (E2): the
    /// stages re-sum from what the watch actually recorded in the new window,
    /// which is the one answer no proportional rule can reach.
    static func clip(_ samples: [SleepSample], start: Date, end: Date) -> [SleepSample] {
        guard end > start else { return [] }
        return samples.compactMap { s in
            let a = Swift.max(s.start, start)
            let b = Swift.min(s.end, end)
            return b > a ? SleepSample(value: s.value, start: a, end: b) : nil
        }
    }

    /// Strategy A in one call — nil when nothing slept inside the window.
    static func aggregate(_ samples: [SleepSample], within start: Date, _ end: Date) -> SleepNight? {
        aggregate(clip(samples, start: start, end: end))
    }
}

// MARK: - The night window

/// The ONE definition of "the night belonging to date D", ported from
/// `lib/sleep/nightWindow.ts`.
///
/// `sleep_sessions.start_time` is BEDTIME — the previous evening. Every reader
/// and writer must agree on the same half-open window or rows are written into
/// a window nobody queries, which is exactly what made the scorer see
/// `sleepHours = 0` on every day for months.
///
/// Window: `[prevDay(D) 12:00Z, D 12:00Z)`. Half-open and exactly 24 h wide, so
/// consecutive nights TILE the timeline without overlapping. That property is
/// load-bearing: the writer DELETEs this window before inserting, and a rolling
/// sync writes two adjacent days — with an overlapping window, yesterday's
/// delete reached tonight's bedtime and destroyed the row today had just
/// written.
public enum NightWindow {

    /// UTC, deliberately. The window is a fixed 24-hour tile on the absolute
    /// timeline shared with the server, not a local calendar day — two devices
    /// in different zones must agree on which night a bedtime belongs to.
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    public static func previousDay(_ dateISO: String) -> String {
        shift(dateISO, days: -1)
    }

    public static func nextDay(_ dateISO: String) -> String {
        shift(dateISO, days: 1)
    }

    private static func shift(_ dateISO: String, days: Int) -> String {
        guard let date = midnight(dateISO),
              let moved = utc.date(byAdding: .day, value: days, to: date)
        else { return dateISO }
        return iso(moved)
    }

    /// `[from, to)` for the night that ENDS on the morning of `dateISO`.
    public static func range(_ dateISO: String) -> (from: Date, to: Date)? {
        guard let noon = midnight(dateISO)?.addingTimeInterval(12 * 3600) else { return nil }
        return (noon.addingTimeInterval(-24 * 3600), noon)
    }

    /// The inverse: which date's night a bedtime belongs to.
    ///
    /// Needed the moment anything reads more than one night — a seven-night
    /// trend gets back a flat list and must bucket it, and doing that by the
    /// date part of `start_time` files every pre-midnight bedtime under the
    /// evening it began rather than the morning it ended. Half the nights would
    /// land on the wrong day, and only the half you went to bed early on.
    public static func nightOf(_ start: Date) -> String {
        let day = iso(start)
        return utc.component(.hour, from: start) >= 12 ? nextDay(day) : day
    }

    /// Where to stamp a session with no reported bed time. It MUST sit inside
    /// the window or the row is written and invisible to every reader.
    public static func fallbackBedTime(_ dateISO: String) -> Date? {
        midnight(previousDay(dateISO))?.addingTimeInterval(23 * 3600)
    }

    static func midnight(_ dateISO: String) -> Date? {
        let parts = dateISO.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func iso(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
