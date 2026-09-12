import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// What the energy ledger predicted against what the scale actually did — a port
// of the web app's `lib/charts/deficitLedger.ts` (§W12).
//
// ── TWO NUMBERS THAT DISAGREE ON PURPOSE ─────────────────────────────────────
// The ledger sums `intake − TDEE` and divides by 7,700 kcal/kg. The scale
// measures a weight. They disagree — always — because water, glycogen and gut
// content move faster than fat does, and the honest thing for a surface to do
// is show both rather than pick the one that flatters the week. `gapKg` is the
// disagreement, stated, and it is the only figure here worth acting on: a
// ledger saying −0.5 kg a week against a scale saying −0.1 kg for a month is
// either a mis-measured intake or an active-energy estimate that is too
// generous, and neither is visible from either number alone.
//
// ── AND WHY A DAY WITH A HOLE CONTRIBUTES NOTHING ────────────────────────────
// `Energy.tdee` is nil unless BMR, active energy AND intake are all present,
// deliberately: a missing active-energy sync treated as zero reports a ~400
// kcal larger deficit than the day earned, in the same direction every time it
// happens, so the error accumulates rather than averaging out. Every week
// therefore says how many days it is actually summing.
// ─────────────────────────────────────────────────────────────────────────────

public struct DeficitDayIn: Codable, Sendable, Equatable {
    public var date: String
    /// `nutrition_entries` daily total.
    public var intakeKcal: Double?
    /// `daily_logs.bmr`.
    public var bmrKcal: Double?
    /// `daily_logs.active_energy`.
    public var activeKcal: Double?
    /// The morning's reading, already through `Format.validWeight`.
    public var weightKg: Double?

    public init(date: String, intakeKcal: Double? = nil, bmrKcal: Double? = nil, activeKcal: Double? = nil, weightKg: Double? = nil) {
        self.date = date
        self.intakeKcal = intakeKcal
        self.bmrKcal = bmrKcal
        self.activeKcal = activeKcal
        self.weightKg = weightKg
    }
}

/// Named `DeficitWeek` rather than `LedgerWeek`: the weekly export already
/// owns that name (`Reports/ExportTypes`), and two of them in one module is a
/// compile error that reads as a mystery.
public struct DeficitWeek: Codable, Sendable, Equatable, Identifiable {
    public var weekStart: String
    /// Days with intake AND expenditure — the denominator the bar is honest about.
    public var daysCounted: Int
    /// Sum of `intake − TDEE` over the counted days. Negative is a deficit.
    public var balanceKcal: Double?
    /// `balanceKcal / 7700`, two decimals. Negative is a predicted loss.
    public var expectedKg: Double?
    /// The last reading of this week against the last reading of the newest
    /// EARLIER week that had one — not first-to-last inside the week, which
    /// reports nothing at all for the many weeks holding a single weigh-in.
    /// (`HistoryWeeks.capsules` compares weeks the same way, for the same reason.)
    public var measuredKg: Double?
    public var id: String { weekStart }
}

public struct DeficitLedger: Codable, Sendable, Equatable {
    /// Exactly `weeks` weeks, oldest first.
    public var weeks: [DeficitWeek]
    public var daysCounted: Int
    public var totalBalanceKcal: Double?
    public var expectedKg: Double?
    /// Last reading in the window minus the first.
    public var measuredKg: Double?
    /// `measured − expected`. Positive means the scale moved LESS than the
    /// ledger said it would — the usual direction, and the one worth explaining.
    public var gapKg: Double?
}

public enum DeficitLedgerSeries {
    /// 7,700 kcal per kilogram of body fat — the standard energy-density figure.
    public static let kcalPerKg: Double = 7700

    /// `intake − TDEE` for one day, or nil when either side is missing.
    public static func dayBalanceKcal(_ day: DeficitDayIn) -> Double? {
        guard let intake = day.intakeKcal,
              let tdee = Energy.tdee(bmr: day.bmrKcal, active: day.activeKcal, intakeKcal: day.intakeKcal)
        else { return nil }
        return jsRound(intake - tdee)
    }

    /// kcal → kg at 7,700, two decimals. Nil in, nil out.
    public static func kcalToKg(_ balance: Double?) -> Double? {
        balance.map { jsRound($0 / kcalPerKg * 100) / 100 }
    }

    public static func build(
        _ days: [DeficitDayIn], endingOn: String, weeks: Int = 8, startDay: Int = 0
    ) -> DeficitLedger {
        // `new Map(entries)` — a LATER duplicate overwrites an earlier one.
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        let lastStart = Week.start(of: endingOn, startDay: startDay)

        var out: [DeficitWeek] = []
        // The weight the NEXT week is compared against: the newest reading seen
        // so far, carried across weeks that have none. A week with no weigh-in
        // has no delta and must not silently borrow the one before it.
        var previousWeight: Double?
        var firstWeight: Double?
        var lastWeight: Double?

        for w in stride(from: weeks - 1, through: 0, by: -1) {
            let weekStart = Week.start(of: ISODate.addDays(lastStart, -7 * w) ?? lastStart, startDay: startDay)
            var counted = 0
            var balance: Double = 0
            var weekWeight: Double?

            for i in 0..<7 {
                let date = ISODate.addDays(weekStart, i) ?? weekStart
                if date > endingOn { break }
                guard let day = byDate[date] else { continue }
                if let dayBalance = dayBalanceKcal(day) {
                    counted += 1
                    balance += dayBalance
                }
                if let weight = day.weightKg {
                    weekWeight = weight
                    if firstWeight == nil { firstWeight = weight }
                    lastWeight = weight
                }
            }

            let balanceKcal: Double? = counted > 0 ? balance : nil
            let measuredKg: Double? = {
                guard let weekWeight, let previousWeight else { return nil }
                return jsRound((weekWeight - previousWeight) * 100) / 100
            }()
            if let weekWeight { previousWeight = weekWeight }

            out.append(DeficitWeek(
                weekStart: weekStart, daysCounted: counted, balanceKcal: balanceKcal,
                expectedKg: kcalToKg(balanceKcal), measuredKg: measuredKg
            ))
        }

        let daysCounted = out.reduce(0) { $0 + $1.daysCounted }
        let totalBalanceKcal: Double? = daysCounted > 0 ? out.reduce(0) { $0 + ($1.balanceKcal ?? 0) } : nil
        let expectedKg = kcalToKg(totalBalanceKcal)
        let measuredKg: Double? = {
            guard let firstWeight, let lastWeight else { return nil }
            return jsRound((lastWeight - firstWeight) * 100) / 100
        }()

        return DeficitLedger(
            weeks: out,
            daysCounted: daysCounted,
            totalBalanceKcal: totalBalanceKcal,
            expectedKg: expectedKg,
            measuredKg: measuredKg,
            gapKg: (measuredKg != nil && expectedKg != nil)
                ? jsRound((measuredKg! - expectedKg!) * 100) / 100
                : nil
        )
    }
}
