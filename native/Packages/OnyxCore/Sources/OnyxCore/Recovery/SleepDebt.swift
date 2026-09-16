import Foundation

/// The sleep-debt bank — `computeSleepDebt` from the web app's `lib/hooks/useSleepDebt.ts`.
///
/// A decayed cumulative shortfall against the goal over a 14-night window.
/// Surplus nights repay debt but never bank "credit" below zero; the older week
/// keeps 75% of its weight. `weekAgo` is a parameter, never a clock — the web
/// reads `logicalDaysAgoISO(7)` and the vectors pin it.
public struct SleepDebt: Codable, Equatable, Sendable {
    /// Cumulative decayed shortfall vs goal, hours, one decimal, ≥ 0.
    public var debtHours: Double
    /// Nights with data in the window.
    public var nights: Int
    public var worstNightMin: Double?
    public var goalHours: Double
}

/// One night as the bank needs it. Named apart from OnyxData's `SleepNight`,
/// which is a HealthKit aggregate and a different thing.
public struct SleepDebtNight: Codable, Equatable, Sendable {
    public var date: String
    public var sleepMinutes: Double?
    public init(date: String, sleepMinutes: Double?) { self.date = date; self.sleepMinutes = sleepMinutes }
}

public extension SleepDebt {
    static let windowDays = 14
    /// Last week's debt keeps 75% weight.
    static let weeklyDecay = 0.75
    /// Fewer nights than this in the window and there is no honest answer: one
    /// short night out of one is not a bank. Every reader applies it — Pulse's
    /// gauge and the Mega tile's sentence — so it is stated once here rather
    /// than spelled at each of them.
    static let minimumNights = 3

    static func compute(nights: [SleepDebtNight], goalHours: Double, weekAgo: String) -> SleepDebt {
        let withData = nights.filter { ($0.sleepMinutes ?? 0) > 0 }
        // Oldest → newest so decay applies chronologically. `Array.prototype.sort`
        // is stable; Swift's is not guaranteed to be, so the index breaks ties.
        let asc = withData.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
        var debt = 0.0
        var worst: Double?
        for n in asc {
            let mins = n.sleepMinutes!
            if worst == nil || mins < worst! { worst = mins }
            let deltaH = goalHours - mins / 60          // + = shortfall, − = surplus
            let weight = n.date < weekAgo ? weeklyDecay : 1
            debt = max(0, debt + deltaH * weight)       // surplus repays, never banks credit
        }
        return SleepDebt(debtHours: jsRound1(debt), nights: withData.count, worstNightMin: worst, goalHours: goalHours)
    }
}

public extension SleepDebt {
    /// The gauge's hue band — `debtBand` in the web app's `lib/sleep/debt.ts`.
    static func band(_ debtHours: Double) -> String {
        if debtHours <= 2 { return "ember" }
        if debtHours <= 5 { return "gold" }
        return "oxide"
    }
}
