import Foundation

/// The arithmetic behind the dashboard tiles — a port of the web app's `lib/dashboard/tiles.ts`.

public struct StackDose: Codable, Sendable, Equatable {
    public var key: String
    public var name: String
    public var time: String
    public init(key: String, name: String, time: String) { self.key = key; self.name = name; self.time = time }
}

public struct StackBlock: Codable, Sendable, Equatable {
    public var time: String
    public var items: [StackDose]
    public var at: Double
}

public struct StackBehind: Codable, Sendable, Equatable {
    public var key: String
    public var name: String
    public var time: String
    public var wasSkipped: Bool
}

public struct StackSchedule: Codable, Sendable, Equatable {
    public var blocks: [StackBlock]
    public var behind: [StackBehind]
    public var onProtocol: [StackDose]
    public var blockCount: Int
    public var next: StackBlock?
    public var inMin: Double?
}

public struct LedgerWindow: Codable, Sendable, Equatable {
    public var days: Int
    public var inPhase: Int
    public var label: String?
}

public enum Tiles {
    /// Mean of the values that exist, or nil when none do.
    public static func mean(_ vals: [Double?]) -> Double? {
        let ok = vals.compactMap { $0 }.filter(\.isFinite)
        return ok.isEmpty ? nil : ok.reduce(0, +) / Double(ok.count)
    }

    /// Today against the mean of the series EXCLUDING its last element, to one place.
    public static func vsBaseline(_ series: [Double?], today: Double?) -> Double? {
        guard let today = today, let base = mean(Array(series.dropLast())) else { return nil }
        return jsRound((today - base) * 10) / 10
    }

    /// The waypoints up to the goal: four multiples of a 500-step-rounded fifth, then the goal.
    public static func stepMarks(goal: Double) -> [Double] {
        let step: Double = max(500, jsRound(goal / 5 / 500) * 500)
        let ladder: [Double] = [step, step * 2, step * 3, step * 4]
        var marks = ladder.filter { $0 < goal }
        marks.append(goal)
        return marks
    }

    /// -1 unmeasured; 0 at or past a non-positive target; shortfall for a floor, overage for a ceiling.
    public static func nutrientRisk(have: Double?, target: Double, ceiling: Bool) -> Double {
        guard let have = have else { return -1 }
        if target <= 0 { return 0 }
        return ceiling ? max(0, have / target - 1) : max(0, 1 - have / target)
    }

    public static let ledgerFloorDays = 14
    public static let ledgerMaxDays = 30

    /// Phase-to-date, floored at 14 and capped at 30; the flat month outside every phase.
    public static func ledgerWindow(_ todayISO: String, phases: [PhaseDef]) -> LedgerWindow {
        guard let span = Phases.span(for: todayISO, in: phases) else { return LedgerWindow(days: ledgerMaxDays, inPhase: ledgerMaxDays, label: nil) }
        let inPhase = min(span.dayIndex + 1, ledgerMaxDays)
        return LedgerWindow(
            days: min(ledgerMaxDays, max(inPhase, ledgerFloorDays)),
            inPhase: inPhase,
            label: "\(span.def.short ?? span.def.name) · day \(span.dayIndex + 1)"
        )
    }

    /// `(weeks - 1) * 7` plus the days of this week that have happened.
    public static func consistencyWindow(weeks: Int, todayISO: String) -> Int? {
        guard let dow = ISODate.weekday(todayISO) else { return nil }
        return (weeks - 1) * 7 + dow + 1
    }

    /// `today` / `yesterday` / `4d ago`.
    public static func daysAgo(_ iso: String, today: String) -> String? {
        guard let a = ISODate.dayNumber(today), let b = ISODate.dayNumber(iso) else { return nil }
        let n = a - b
        if n <= 0 { return "today" }
        if n == 1 { return "yesterday" }
        return "\(n)d ago"
    }

    /// JS `Number(s)` for the strings a clock field can hold: "" → 0, whitespace trimmed, else a finite parse or nil.
    static func jsNumber(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return 0 }
        return Double(t)
    }

    /// `HH:MM` → minutes since midnight; anything unparseable sorts to the end (1440).
    public static func parseMin(_ t: String) -> Double {
        let parts = t.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let h = parts.count > 0 ? jsNumber(parts[0]) : nil
        let m = parts.count > 1 ? jsNumber(parts[1]) : nil
        guard let hh = h, let mm = m, hh.isFinite, mm.isFinite else { return 24 * 60 }
        return hh * 60 + mm
    }

    public static func stackSchedule(_ slots: [StackDose], skipped: Set<String>, minutes: Double) -> StackSchedule {
        var order: [String] = []
        var byTime: [String: [StackDose]] = [:]
        for s in slots {
            if skipped.contains(s.key) || parseMin(s.time) <= minutes { continue }
            if byTime[s.time] == nil { order.append(s.time); byTime[s.time] = [] }
            byTime[s.time]!.append(s)
        }
        let blocks = order.map { StackBlock(time: $0, items: byTime[$0]!, at: parseMin($0)) }
            .enumerated().sorted { a, b in a.element.at != b.element.at ? a.element.at < b.element.at : a.offset < b.offset }.map(\.element)
        let behind = slots
            .filter { skipped.contains($0.key) || parseMin($0.time) <= minutes }
            .map { StackBehind(key: $0.key, name: $0.name, time: $0.time, wasSkipped: skipped.contains($0.key)) }
            .enumerated().sorted { a, b in
                let x = parseMin(a.element.time), y = parseMin(b.element.time)
                return x != y ? x > y : a.offset < b.offset
            }.map(\.element)
        let onProtocol = slots.filter { !skipped.contains($0.key) }
        let next = blocks.first
        return StackSchedule(
            blocks: blocks, behind: behind, onProtocol: onProtocol,
            blockCount: Set(onProtocol.map(\.time)).count,
            next: next, inMin: next.map { $0.at - minutes }
        )
    }

    /// "in 12 min" · "in 2h 5m" · "now" · "40 min overdue".
    public static func dueLabel(_ mins: Double) -> String {
        if mins < 0 {
            let a = abs(mins)
            return a < 60 ? "\(jsIntegerString(a)) min overdue" : "\(jsIntegerString(floor(a / 60)))h overdue"
        }
        if mins < 1 { return "now" }
        if mins < 60 { return "in \(jsIntegerString(mins)) min" }
        let rem = mins.truncatingRemainder(dividingBy: 60)
        let tail = rem != 0 ? "\(jsIntegerString(rem))m" : ""
        return "in \(jsIntegerString(floor(mins / 60)))h \(tail)".trimmingCharacters(in: .whitespaces)
    }
}
