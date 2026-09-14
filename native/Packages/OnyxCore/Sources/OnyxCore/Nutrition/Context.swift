import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ONE context vocabulary, for the two systems that used to have their own.
// A port of the web app's `lib/nutrition/context.ts`.
//
// `daily_logs.nutrition_exception` (a per-day flag that forgives the nutrition
// grade) and `user_goals.context_mode` (a global switch that relaxes every
// penalty in the scorer) both held Travel and Illness with no code reading one
// to set the other. Now: Settings holds `{mode, since}`; each day inside the
// range is stamped into the day column as it is written, so a RECOMPUTE of a
// past day is stable — the day carries its own context.
//
// Event, Refeed and Social are one-day statements; Travel, Illness and
// Emergency are ranges. Same enum, same column, different persistence.
// ─────────────────────────────────────────────────────────────────────────────

public enum ContextMode: String, Codable, Sendable, CaseIterable {
    case normal, event, holiday, refeed, social, travel, illness, emergency
}

/// The four the SCORER understands.
public enum ScoringContext: String, Codable, Sendable { case normal, travel, illness, emergency }

public struct ContextMeta: Codable, Equatable, Sendable {
    public var label: String
    /// One line, written for the moment of choosing.
    public var desc: String
    /// How it is stored in `daily_logs.nutrition_exception`. Nil for normal.
    public var dayLabel: String?
}

public struct ContextRange: Codable, Equatable, Sendable {
    public var mode: ContextMode
    public var from: String
    public var to: String
    public var days: Int
}

/// A day as the export sees it — its date and the stored exception label.
public struct StampedDay: Codable, Sendable {
    public var date: String
    public var exception: String?
    public init(date: String, exception: String? = nil) { self.date = date; self.exception = exception }
}

public enum Context {
    public static let meta: [ContextMode: ContextMeta] = [
        .normal:    ContextMeta(label: "Normal",    desc: "Standard scoring and targets",            dayLabel: nil),
        .event:     ContextMeta(label: "Event",     desc: "A planned meal out — graded on protein",  dayLabel: "Event"),
        .holiday:   ContextMeta(label: "Holiday",   desc: "A day off the plan — graded on protein",  dayLabel: "Holiday"),
        .refeed:    ContextMeta(label: "Refeed",    desc: "A deliberate surplus day",                dayLabel: "Refeed"),
        .social:    ContextMeta(label: "Social",    desc: "Unplanned, and not a lapse",              dayLabel: "Social"),
        .travel:    ContextMeta(label: "Travel",    desc: "Relaxed penalties until you end it",      dayLabel: "Travel"),
        .illness:   ContextMeta(label: "Illness",   desc: "Penalties relaxed, step goal suspended",  dayLabel: "Illness"),
        .emergency: ContextMeta(label: "Emergency", desc: "Everything relaxed, step goal suspended", dayLabel: "Emergency"),
    ]

    /// Modes that persist until you end them. The rest describe a single day.
    public static func isRangeMode(_ mode: ContextMode) -> Bool {
        mode == .travel || mode == .illness || mode == .emergency
    }

    private static func normalized(_ stored: String?) -> String {
        stored?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    /// The mode a stored day label names, or normal. Case- and space-tolerant.
    /// An unknown non-empty value is still an EXCEPTION day and maps to `event`
    /// — the most conservative real mode — never to normal, so a day someone
    /// declared months ago is not quietly un-forgiven.
    public static func fromDayLabel(_ stored: String?) -> ContextMode {
        let v = normalized(stored)
        if v.isEmpty { return .normal }
        return ContextMode(rawValue: v) ?? .event
    }

    /// The mode a `user_goals.context_mode` value names. Unknown reads normal.
    public static func fromSetting(_ stored: String?) -> ContextMode {
        let v = normalized(stored)
        if v.isEmpty { return .normal }
        return ContextMode(rawValue: v) ?? .normal
    }

    /// What the scorer should apply. The one-day food modes map to normal
    /// DELIBERATELY: a dinner out must not improve your sleep score.
    public static func scoringContext(for mode: ContextMode) -> ScoringContext {
        switch mode {
        case .travel: return .travel
        case .illness: return .illness
        case .emergency: return .emergency
        default: return .normal
        }
    }

    /// Illness and Emergency only. Travel does NOT suspend the step target — an
    /// airport is one of the few places you outwalk your goal by accident.
    public static func suspendsStepGoal(_ mode: ContextMode) -> Bool {
        mode == .illness || mode == .emergency
    }

    /// Whole days from `a` to `b`, never negative; 0 when either does not parse.
    public static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = ISODate.dayNumber(a), let db = ISODate.dayNumber(b) else { return 0 }
        return Swift.max(0, db - da)
    }

    /// The export's header line for an active range, or nil.
    public static func rangeLine(_ mode: ContextMode, since: String?, today: String) -> String? {
        if mode == .normal { return nil }
        let label = meta[mode]!.label
        guard let since, !since.isEmpty else { return "Context: \(label) (active)" }
        let days = daysBetween(since, today) + 1
        return "Context: \(label) since \(since) (\(days) day\(days == 1 ? "" : "s"))"
    }

    /// Is a date inside an active range? Never the future; with no start date
    /// only TODAY is inside — stamping the whole of history with a context
    /// because one column was missing is unrecoverable.
    public static func rangeCovers(_ mode: ContextMode, since: String?, date: String, today: String) -> Bool {
        if !isRangeMode(mode) { return false }
        if date > today { return false }
        if let since, !since.isEmpty { return date >= since }
        return date == today
    }

    /// Contiguous RANGE contexts across a set of stamped days, oldest first.
    /// Gaps break a range: illness Mon–Tue and again Fri is two ranges.
    public static func rangesIn(_ days: [StampedDay]) -> [ContextRange] {
        let sorted = days.sorted { $0.date < $1.date }
        var out: [ContextRange] = []
        var cur: Int?
        for d in sorted {
            let mode = fromDayLabel(d.exception)
            guard mode != .normal, isRangeMode(mode) else { cur = nil; continue }
            if let c = cur, out[c].mode == mode, daysBetween(out[c].to, d.date) == 1 {
                out[c].to = d.date
                out[c].days += 1
                continue
            }
            out.append(ContextRange(mode: mode, from: d.date, to: d.date, days: 1))
            cur = out.count - 1
        }
        return out
    }

    /// The export's one-line rendering of a range.
    public static func rangeLabel(_ r: ContextRange) -> String {
        let label = meta[r.mode]!.label
        return r.from == r.to
            ? "\(label) · \(r.from)"
            : "\(label) · \(r.from) → \(r.to) (\(r.days) days)"
    }
}
