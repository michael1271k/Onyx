import Foundation

/// The arithmetic behind the widget payload — a port of the web app's `lib/widget/derive.ts`.
/// NULL, NEVER ZERO: every function omits what it cannot compute.

public struct TrendPoint: Codable, Sendable, Equatable {
    public var d: String
    public var v: Double
    public init(d: String, v: Double) { self.d = d; self.v = v }
}

/// A dated reading; `value` nil covers null/undefined/NaN/Infinity.
public struct DatedValue: Codable, Sendable, Equatable {
    public var date: String
    public var value: Double?
    public init(date: String, value: Double?) { self.date = date; self.value = value }
}

public struct CalendarSession: Codable, Sendable, Equatable {
    public var date: String
    public var volumeKg: Double?
    public init(date: String, volumeKg: Double?) { self.date = date; self.volumeKg = volumeKg }
}

public struct ScheduledDay: Codable, Sendable, Equatable {
    public var dayKey: String?
    public var scheduled: Bool
    public var label: String?
    public init(dayKey: String?, scheduled: Bool, label: String? = nil) { self.dayKey = dayKey; self.scheduled = scheduled; self.label = label }
}

public struct CalendarDay: Codable, Sendable, Equatable {
    public var d: String
    public var dayKey: String?
    public var label: String?
    public var scheduled: Bool
    public var logged: Bool
    public var volumeKg: Double?
}

public struct WidgetCardioRow: Codable, Sendable, Equatable {
    public var date: String
    public var kind: String?
    public var distanceM: Double?
    public var durationMin: Double?
    enum CodingKeys: String, CodingKey { case date, kind, distanceM = "distance_m", durationMin = "duration_min" }
    public init(date: String, kind: String?, distanceM: Double?, durationMin: Double?) { self.date = date; self.kind = kind; self.distanceM = distanceM; self.durationMin = durationMin }
}

public struct LastCardio: Codable, Sendable, Equatable {
    public var kind: String
    public var date: String
    public var distanceM: Double?
    public var durationMin: Double?
    public var paceMinPerKm: Double?
}

public struct CardioBlock: Codable, Sendable, Equatable {
    public var last: LastCardio?
    public var weekSessions: Int
    public var weekTarget: Int
    public var weekMinutes: Double
    public var trend: [TrendPoint]
}

public struct LedgerRow: Codable, Sendable, Equatable {
    public var exerciseKey: String
    public var axis: String
    public var value: Double?
    public var reps: Double?
    public var achievedOn: String?
    enum CodingKeys: String, CodingKey { case axis, value, reps, exerciseKey = "exercise_key", achievedOn = "achieved_on" }
    public init(exerciseKey: String, axis: String, value: Double?, reps: Double?, achievedOn: String?) {
        self.exerciseKey = exerciseKey; self.axis = axis; self.value = value; self.reps = reps; self.achievedOn = achievedOn
    }
}

public struct WidgetRecord: Codable, Sendable, Equatable {
    public var exercise: String
    public var axis: String
    public var value: Double
    public var reps: Double?
    public var achievedOn: String
}

public struct WidgetSetRow: Codable, Sendable, Equatable {
    public var exercise: String
    public var day: String
    public var weightKg: Double?
    public var reps: Double?
    public var est1rmKg: Double?
    public var setType: String?
    public init(exercise: String, day: String, weightKg: Double?, reps: Double?, est1rmKg: Double? = nil, setType: String? = nil) {
        self.exercise = exercise; self.day = day; self.weightKg = weightKg; self.reps = reps; self.est1rmKg = est1rmKg; self.setType = setType
    }
}

public struct WidgetE1rm: Codable, Sendable, Equatable {
    public var exercise: String
    public var kg: Double
    public var deltaKg: Double?
    public var trend: [TrendPoint]
}

public struct VitalBlock: Codable, Sendable, Equatable {
    public var value: Double?
    public var baseline: Double?
    public var trend: [TrendPoint]
}

public struct LatestDelta: Codable, Sendable, Equatable {
    public var value: Double?
    public var delta: Double?
}

public enum WidgetDerive {
    static func round2(_ v: Double) -> Double { jsRound(v * 100) / 100 }
    static func round1(_ v: Double) -> Double { jsRound(v * 10) / 10 }

    // MARK: Trends

    /// Oldest first, rounded to two places, gaps left as gaps, newest `limit` kept.
    public static func trendPoints(_ rows: [DatedValue], limit: Int) -> [TrendPoint] {
        let clean = rows.compactMap { r -> TrendPoint? in
            guard let v = r.value, v.isFinite else { return nil }
            return TrendPoint(d: r.date, v: round2(v))
        }
        let sorted = clean.enumerated().sorted { a, b in a.element.d != b.element.d ? a.element.d < b.element.d : a.offset < b.offset }.map(\.element)
        return Array(sorted.dropFirst(max(0, sorted.count - limit)))
    }

    /// Mean over the half-open window [from, to), or nil when empty.
    public static func meanBetween(_ points: [TrendPoint], from: String, to: String) -> Double? {
        let inWindow = points.filter { $0.d >= from && $0.d < to }
        guard !inWindow.isEmpty else { return nil }
        return round2(inWindow.reduce(0) { $0 + $1.v } / Double(inWindow.count))
    }

    public enum Combine: String, Codable, Sendable { case sum, max }

    /// Several rows per date rolled up per day; days with no rows are OMITTED.
    public static func dailySeries(_ rows: [DatedValue], limit: Int, combine: Combine = .sum) -> [TrendPoint] {
        var order: [String] = []
        var byDay: [String: Double] = [:]
        for r in rows {
            guard let v = r.value, v.isFinite else { continue }
            if let held = byDay[r.date] {
                byDay[r.date] = combine == .max ? Swift.max(held, v) : held + v
            } else {
                order.append(r.date); byDay[r.date] = v
            }
        }
        return trendPoints(order.map { DatedValue(date: $0, value: byDay[$0]) }, limit: limit)
    }

    /// `dailySeries` laid back onto the calendar: exactly `limit` buckets ending
    /// on `endingOn`, oldest first, `value` nil where no row landed.
    ///
    /// ── WHY THE COMPACT SERIES IS STILL RIGHT, AND STILL NOT ENOUGH ──────────
    /// `dailySeries` omits empty days on purpose (see its own note, and the TS
    /// twin's): a day you forgot to log and a day you drank nothing are not the
    /// same day, and zeroing one into the other is the lie a bar chart is least
    /// able to walk back. But omission drops the day's POSITION too, and that is
    /// a second lie in any fixed window: four logged nights out of seven draw as
    /// four bars filling the width, which reads as a full week.
    ///
    /// So the gap survives as a gap. A nil bucket is a slot the renderer can
    /// draw as an empty track — present, dated, and visibly not a zero. Nothing
    /// on the wire changes: `OnyxSnapshot.Point.v` stays non-optional and every
    /// widget payload is byte-identical. This is the window a SCREEN asks for.
    ///
    /// A reading on either side of the window is DROPPED, never folded onto the
    /// nearest edge — a device clock a day ahead must not turn tomorrow's number
    /// into tonight's. Duplicate dates in the input resolve last-wins.
    ///
    /// Either exactly `limit` buckets or none at all: an `endingOn` that is not
    /// an ISO day has no window, and half a window is worse than no window.
    public static func paddedWindow(_ series: [TrendPoint], endingOn: String, limit: Int) -> [DatedValue] {
        // `limit < 0` would build a reversed Range and TRAP, so the guard is
        // load-bearing rather than tidy.
        guard limit > 0, let end = ISODate.dayNumber(endingOn) else { return [] }
        let byDay = Dictionary(series.map { ($0.d, $0.v) }, uniquingKeysWith: { _, last in last })
        return ((end - limit + 1)...end).map { day in
            let iso = ISODate.iso(dayNumber: day)
            return DatedValue(date: iso, value: byDay[iso])
        }
    }

    /// The newest reading and how far it moved from the newest one that DIFFERS (≥ 0.05).
    public static func latestDelta(_ series: [TrendPoint]) -> LatestDelta {
        guard let latest = series.last else { return LatestDelta(value: nil, delta: nil) }
        let previous = series.reversed().first { abs($0.v - latest.v) >= 0.05 }
        return LatestDelta(value: latest.v, delta: previous.map { round2(latest.v - $0.v) })
    }

    // MARK: The training calendar

    public static func calendarDays(_ days: [String], sessions: [CalendarSession], scheduledFor: (String) -> ScheduledDay) -> [CalendarDay] {
        var logged = Set<String>()
        var volume: [String: Double] = [:]
        for s in sessions {
            logged.insert(s.date)
            if let v = s.volumeKg, v.isFinite { volume[s.date] = (volume[s.date] ?? 0) + v }
        }
        return days.map { d in
            let s = scheduledFor(d)
            return CalendarDay(d: d, dayKey: s.dayKey, label: s.label, scheduled: s.scheduled, logged: logged.contains(d), volumeKg: volume[d])
        }
    }

    /// Weekly tonnage, oldest first, `d` = week start. A week with sessions but no
    /// tonnage is 0; a week with no sessions is omitted.
    public static func weeklyVolume(_ sessions: [CalendarSession], weekStartOfDate: (String) -> String, limit: Int) -> [TrendPoint] {
        var order: [String] = []
        var byWeek: [String: Double] = [:]
        for s in sessions {
            let w = weekStartOfDate(s.date)
            if byWeek[w] == nil { order.append(w) }
            byWeek[w] = (byWeek[w] ?? 0) + (s.volumeKg ?? 0)
        }
        return trendPoints(order.map { DatedValue(date: $0, value: byWeek[$0]) }, limit: limit)
    }

    // MARK: Cardio

    public static func cardioBlock(
        _ rows: [WidgetCardioRow], today: String, weekStart: String, zone2MinMinutes: Double, weekTarget: Int,
        paceOf: (Double?, Double?) -> Double?, trendDays: Int
    ) -> CardioBlock {
        // Newest first, stable — the LAST logged session of a day wins.
        let sorted = rows.enumerated().sorted { a, b in a.element.date != b.element.date ? a.element.date > b.element.date : a.offset < b.offset }.map(\.element)
        let newest = sorted.first { $0.date <= today }
        let thisWeek = rows.filter { $0.date >= weekStart && $0.date <= today }
        func minutes(_ r: WidgetCardioRow) -> Double { (r.durationMin?.isFinite ?? false) ? r.durationMin! : 0 }
        return CardioBlock(
            last: newest.map { n in
                LastCardio(
                    kind: (n.kind?.isEmpty ?? true) ? "Cardio" : n.kind!,
                    date: n.date, distanceM: n.distanceM, durationMin: n.durationMin,
                    paceMinPerKm: paceOf(n.distanceM, n.durationMin)
                )
            },
            weekSessions: thisWeek.filter { minutes($0) >= zone2MinMinutes }.count,
            weekTarget: weekTarget,
            weekMinutes: jsRound(thisWeek.reduce(0) { $0 + minutes($1) }),
            trend: dailySeries(rows.map { DatedValue(date: $0.date, value: $0.durationMin) }, limit: trendDays)
        )
    }

    // MARK: Records

    /// The most recent genuine records, newest first.
    ///
    /// Until W2 rows below the compiled record book's floor were dropped here.
    /// The floors are `personal_records` rows themselves now (session-less,
    /// dated the day the book was asserted), so every row in the ledger is at
    /// or above its floor by construction and the filter is gone.
    public static func topRecords(_ rows: [LedgerRow], limit: Int = 3) -> [WidgetRecord] {
        let kept = rows
            .filter { r in
                guard let v = r.value, v.isFinite, r.achievedOn != nil else { return false }
                return true
            }
        let sorted = kept.enumerated().sorted { a, b in
            let x = a.element.achievedOn!, y = b.element.achievedOn!
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
        return sorted.prefix(max(0, limit)).map {
            WidgetRecord(exercise: $0.exerciseKey, axis: $0.axis, value: round2($0.value!), reps: $0.reps, achievedOn: $0.achievedOn!)
        }
    }

    // MARK: Estimated 1RM

    public static func e1rmTrends(_ sets: [WidgetSetRow], asOf: String, windowDays: Int = 28, limit: Int = 3) -> [WidgetE1rm] {
        let cutoff = ISODate.addDays(asOf, -windowDays) ?? asOf
        var order: [String] = []
        var byExercise: [String: [String: Double]] = [:]
        for s in sets {
            guard SetTags.isWorkingSet(s.setType) else { continue }
            let stored: Double? = (s.est1rmKg ?? 0) > 0 ? s.est1rmKg : nil
            let est = stored ?? Epley.oneRepMax(weight: s.weightKg ?? 0, reps: s.reps ?? 0)
            guard let e = est, e > 0 else { continue }
            if byExercise[s.exercise] == nil { order.append(s.exercise); byExercise[s.exercise] = [:] }
            byExercise[s.exercise]![s.day] = Swift.max(byExercise[s.exercise]![s.day] ?? 0, e)
        }
        struct Row { let e1rm: WidgetE1rm; let lastDay: String }
        var out: [Row] = []
        for exercise in order {
            let days = byExercise[exercise]!.sorted { $0.key < $1.key }
            let (lastDay, current) = days.last!
            let baseline = days.reversed().first { $0.key <= cutoff }?.value
            out.append(Row(
                e1rm: WidgetE1rm(exercise: exercise, kg: round1(current), deltaKg: baseline.map { round1(current - $0) }, trend: days.map { TrendPoint(d: $0.key, v: round1($0.value)) }),
                lastDay: lastDay
            ))
        }
        let sorted = out.enumerated().sorted { a, b in
            if a.element.lastDay == b.element.lastDay {
                if a.element.e1rm.kg != b.element.e1rm.kg { return a.element.e1rm.kg > b.element.e1rm.kg }
                return a.offset < b.offset
            }
            return a.element.lastDay > b.element.lastDay
        }.map(\.element)
        return sorted.prefix(max(0, limit)).map(\.e1rm)
    }

    // ── `volumeByFamily` LIVED HERE ──────────────────────────────────────────
    // Deleted in W3. It was the second of the three accumulators F7 found: six
    // families, half credit for assistance, the athlete's week start — agreeing
    // with neither the Trends card above it nor the sheet the tile opens. The
    // widget now reads `MuscleCredit.weightedSets(exerciseNames:)` like
    // everything else, and rolls the sixteen up to the eight in the payload
    // (`OnyxSnapshot.volumeByFamily`). Do not re-add a family-grained count.

    // MARK: Vitals

    /// Today's reading, the trailing baseline EXCLUDING today, and the trace (max per day).
    public static func vitalBlock(_ rows: [DatedValue], todayISO: String, trendLimit: Int) -> VitalBlock {
        let real = rows.filter { ($0.value?.isFinite) ?? false }
        let today = real.first { $0.date == todayISO }?.value
        let past = real.filter { $0.date != todayISO }
        let baseline: Double? = past.isEmpty ? nil : round1(past.reduce(0) { $0 + $1.value! } / Double(past.count))
        return VitalBlock(value: today, baseline: baseline, trend: dailySeries(real, limit: trendLimit, combine: .max))
    }
}

/// The widget's refresh cadence — a port of the web app's `lib/widget/cadence.ts`, the
/// web mirror of `OnyxRefresh.schedule`.
public enum WidgetCadence {
    /// `(startHour, minutesBetweenRefreshes)`, ordered, starting at hour 0.
    public static let schedule: [(Int, Int)] = [(0, 150), (6, 20), (10, 45), (17, 20), (22, 60)]
    public static let failureMinutes = 5

    public static func minutes(forHour hour: Int) -> Int {
        var minutes = schedule[0].1
        for (from, m) in schedule where hour >= from { minutes = m }
        return minutes
    }

    /// Refreshes asked for over 24 hours — fractional on purpose.
    public static func refreshesPerDay() -> Double {
        var total = 0.0
        for i in schedule.indices {
            let (from, minutes) = schedule[i]
            let to = i + 1 < schedule.count ? schedule[i + 1].0 : 24
            total += Double((to - from) * 60) / Double(minutes)
        }
        return total
    }

    /// When the next timeline entry is due — `OnyxRefresh.nextRefresh` from the
    /// old extension. A failed build asks again in `failureMinutes` regardless
    /// of the hour, because a cadence that depends on data it failed to read
    /// has a mode where it never refreshes again.
    public static func nextRefresh(after now: Date = Date(), ok: Bool, calendar: Calendar = .current) -> Date {
        let minutes = ok ? minutes(forHour: calendar.component(.hour, from: now)) : failureMinutes
        return calendar.date(byAdding: .minute, value: minutes, to: now)
            ?? now.addingTimeInterval(TimeInterval(minutes * 60))
    }
}
