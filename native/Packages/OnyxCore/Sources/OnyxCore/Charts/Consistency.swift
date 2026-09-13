import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Planned against done, eight weeks of it — a port of
// the web app's `lib/charts/consistency.ts` (§W12).
//
// ── WHY THE PLAN IS HALF THE DATA ────────────────────────────────────────────
// A session list cannot draw a MISSED day: a day nothing happened on has no
// row, so a chart built from sessions alone shows a perfect record with gaps in
// it. The block is judged on exactly the gaps — five sessions against a target
// of five — so every cell carries what the SCHEDULE asked for as well as what
// landed, and the two disagreeing is the point of the surface. The same
// argument `HistoryWeeks` makes for its seven-dot strip.
//
// ── AND WHY A DAY CAN BE "EXTRA" ─────────────────────────────────────────────
// Training on a scheduled rest day is neither adherence nor a miss. Counting it
// as a hit would let a week of six random sessions read as 120 % of a five-day
// plan without saying which five; ignoring it would erase a session that
// happened. It gets its own state, it counts towards `done`, and `adherencePct`
// is allowed to exceed 100 — a true statement about a week that trained more
// than it planned to.
// ─────────────────────────────────────────────────────────────────────────────

public struct ConsistencyDayIn: Codable, Sendable, Equatable {
    public var date: String
    /// The plan's key for the day — nil on a scheduled rest day.
    public var dayKey: String?
    /// Did the plan ask for a session?
    public var scheduled: Bool
    /// Did one land?
    public var logged: Bool

    public init(date: String, dayKey: String? = nil, scheduled: Bool, logged: Bool) {
        self.date = date
        self.dayKey = dayKey
        self.scheduled = scheduled
        self.logged = logged
    }
}

/// `rest` nothing was asked · `done` asked and delivered · `extra` delivered
/// unasked · `missed` asked, not delivered, and the day is over · `planned`
/// asked and the day has not happened yet.
public enum ConsistencyState: String, Codable, Sendable, CaseIterable {
    case rest, done, extra, missed, planned
}

public struct ConsistencyCell: Codable, Sendable, Equatable, Identifiable {
    public var date: String
    public var dayKey: String?
    public var state: ConsistencyState
    public var id: String { date }
}

public struct ConsistencyWeek: Codable, Sendable, Equatable, Identifiable {
    public var weekStart: String
    /// Days the plan asked for.
    public var planned: Int
    /// Sessions that landed, extras included.
    public var done: Int
    /// Seven cells, always, oldest first.
    public var cells: [ConsistencyCell]
    public var id: String { weekStart }
}

public struct Consistency: Codable, Sendable, Equatable {
    /// Exactly `weeks` weeks, oldest first, ending on the week holding `endingOn`.
    public var weeks: [ConsistencyWeek]
    public var planned: Int
    public var done: Int
    /// done ÷ planned × 100, one decimal. Nil when nothing was ever planned.
    public var adherencePct: Double?
}

public enum ConsistencySeries {

    /// The state one day is in. The only place the five words are decided.
    public static func state(_ day: ConsistencyDayIn?, date: String, endingOn: String) -> ConsistencyState {
        if day?.logged == true { return day?.scheduled == true ? .done : .extra }
        guard day?.scheduled == true else { return .rest }
        return date > endingOn ? .planned : .missed
    }

    public static func build(
        _ days: [ConsistencyDayIn], endingOn: String, weeks: Int = 8, startDay: Int = 0
    ) -> Consistency {
        // `new Map(entries)` — a LATER duplicate overwrites an earlier one.
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        let lastStart = Week.start(of: endingOn, startDay: startDay)

        var out: [ConsistencyWeek] = []
        for w in stride(from: weeks - 1, through: 0, by: -1) {
            let weekStart = ISODate.addDays(lastStart, -7 * w) ?? lastStart
            var cells: [ConsistencyCell] = []
            for i in 0..<7 {
                let date = ISODate.addDays(weekStart, i) ?? weekStart
                let day = byDate[date]
                cells.append(ConsistencyCell(date: date, dayKey: day?.dayKey, state: state(day, date: date, endingOn: endingOn)))
            }
            out.append(ConsistencyWeek(
                weekStart: weekStart,
                planned: cells.filter { $0.state != .rest && $0.state != .extra }.count,
                done: cells.filter { $0.state == .done || $0.state == .extra }.count,
                cells: cells
            ))
        }

        let planned = out.reduce(0) { $0 + $1.planned }
        let done = out.reduce(0) { $0 + $1.done }
        return Consistency(
            weeks: out,
            planned: planned,
            done: done,
            adherencePct: planned > 0 ? jsRound(Double(done) / Double(planned) * 1000) / 10 : nil
        )
    }
}
