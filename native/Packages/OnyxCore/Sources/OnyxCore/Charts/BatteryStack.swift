import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The battery, taken apart — a port of the web app's `lib/charts/batteryStack.ts` (§W12).
//
// ── WHY A STACK AND NOT A LINE ───────────────────────────────────────────────
// A battery percentage is one number and it is the answer to the wrong
// question. "62 %" says where you are; it does not say whether you are there
// because you slept badly or because the week's load is finally showing, and
// those two have opposite answers today. v9 computes five drains separately
// (`Battery.breakdown`) and then throws four of them away at the point of
// render. This puts them back: the charge line is what the night was worth, and
// the bands under it are where it went.
//
// ── THE FLOOR IS WHY THE SUM DOES NOT ALWAYS CLOSE ───────────────────────────
// `currentPct` is `clamp(charge − Σdrains, floor, 100)`, so on a day whose
// drains exceed the charge the reading sits on the floor and the stack is
// taller than the gap it explains. That is not an error to hide — it is the day
// saying the model ran out of room — so `totalDrain` is reported raw and the
// face draws the overflow rather than scaling it away.
// ─────────────────────────────────────────────────────────────────────────────

/// Stacking order, bottom to top: the involuntary drains first, then the ones
/// you chose, then the ones your body is reporting.
public enum BatteryDrain: String, Codable, Sendable, CaseIterable {
    case time, activity, workout, load, wellness
}

public struct BatteryStackDayIn: Codable, Sendable, Equatable {
    public var date: String
    /// `daily_scores.battery_pct` — what the day was actually stored as.
    public var batteryPct: Double?
    /// The v9 breakdown, when the day was scored with one.
    public var breakdown: Battery.Breakdown?

    public init(date: String, batteryPct: Double? = nil, breakdown: Battery.Breakdown? = nil) {
        self.date = date
        self.batteryPct = batteryPct
        self.breakdown = breakdown
    }
}

public struct BatteryStackDay: Codable, Sendable, Equatable, Identifiable {
    public var d: String
    /// The morning charge the drains come off. Nil on an unscored day.
    public var charge: Double?
    /// Each drain, floored at zero — a negative drain is a recharge and v9 has
    /// none. Keyed by `BatteryDrain.rawValue`.
    public var drains: [String: Double]
    /// The five, summed, BEFORE the floor and ceiling. Nil on an unscored day.
    public var totalDrain: Double?
    /// The stored reading. Not `charge − totalDrain`: see the header.
    public var batteryPct: Double?
    /// Nothing was scored for this day. The face draws a gap, never a zero.
    public var empty: Bool
    public var id: String { d }

    /// One band, in stacking order.
    public func drain(_ key: BatteryDrain) -> Double { drains[key.rawValue] ?? 0 }
}

public enum BatteryStackSeries {

    private static let emptyDrains: [String: Double] =
        Dictionary(uniqueKeysWithValues: BatteryDrain.allCases.map { ($0.rawValue, 0.0) })

    /// One day's bands, floored.
    public static func day(_ day: BatteryStackDayIn?, date: String) -> BatteryStackDay {
        guard let b = day?.breakdown else {
            return BatteryStackDay(
                d: date, charge: nil, drains: emptyDrains, totalDrain: nil,
                batteryPct: day?.batteryPct, empty: day?.batteryPct == nil
            )
        }
        var drains: [String: Double] = [:]
        for key in BatteryDrain.allCases {
            let v: Double
            switch key {
            case .time:     v = b.drains.time
            case .activity: v = b.drains.activity
            case .workout:  v = b.drains.workout
            case .load:     v = b.drains.load
            case .wellness: v = b.drains.wellness
            }
            drains[key.rawValue] = v.isFinite ? Swift.max(0, jsRound(v * 10) / 10) : 0
        }
        return BatteryStackDay(
            d: date,
            charge: jsRound(b.charge.morningCharge * 10) / 10,
            drains: drains,
            totalDrain: jsRound(b.drains.total * 10) / 10,
            batteryPct: day?.batteryPct ?? jsRound(b.currentPct),
            empty: false
        )
    }

    /// Exactly `limit` days ending on `endingOn`, oldest first. A day nothing
    /// was scored for is present and empty, never absent — a stack with holes
    /// closed up would draw a fortnight as though it were ten days.
    public static func build(
        _ days: [BatteryStackDayIn], endingOn: String, limit: Int = 14
    ) -> [BatteryStackDay] {
        guard limit > 0 else { return [] }
        // `new Map(entries)` — a LATER duplicate overwrites an earlier one.
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        return stride(from: limit - 1, through: 0, by: -1).map { i in
            let date = ISODate.addDays(endingOn, -i) ?? endingOn
            return day(byDate[date], date: date)
        }
    }
}
