import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The stress index over a fortnight — a port of the web app's `lib/charts/stressSeries.ts`
// (Phase 3 E3). `BatteryStackSeries`' shape: exactly `limit` consecutive days
// ending on `endingOn`, oldest first; a day with no reading is present and
// EMPTY, never absent. Computed on read — v1 stores no column.
// ─────────────────────────────────────────────────────────────────────────────

public struct StressDayIn: Codable, Sendable, Equatable {
    public var date: String
    public var breakdown: Stress.Breakdown?

    public init(date: String, breakdown: Stress.Breakdown?) {
        self.date = date
        self.breakdown = breakdown
    }
}

public struct StressDay: Codable, Sendable, Equatable, Identifiable {
    public var d: String
    /// The index, 10–90. Nil on a day with no reading.
    public var index: Double?
    public var band: StressBand?
    /// Each term's z, one decimal; nil where the term was unanswered. Keyed by
    /// `StressTermKey.rawValue`.
    public var terms: [String: Double?]
    /// Nothing was computed for this day. The face draws a gap, never a zero.
    public var empty: Bool
    public var id: String { d }

    /// One term, in stacking order.
    public func term(_ key: StressTermKey) -> Double? { terms[key.rawValue] ?? nil }
}

public enum StressSeries {

    private static let emptyTerms: [String: Double?] =
        Dictionary(uniqueKeysWithValues: StressTermKey.allCases.map { ($0.rawValue, Optional<Double>.none) })

    /// One day's reading, rounded for the face.
    public static func day(_ day: StressDayIn?, date: String) -> StressDay {
        guard let b = day?.breakdown, b.index != nil else {
            return StressDay(d: date, index: nil, band: nil, terms: emptyTerms, empty: true)
        }
        var terms: [String: Double?] = [:]
        for key in StressTermKey.allCases {
            if let z = b.terms.z(key), z.isFinite {
                terms[key.rawValue] = jsRound(z * 10) / 10
            } else {
                terms[key.rawValue] = Optional<Double>.none
            }
        }
        return StressDay(d: date, index: b.index, band: b.band, terms: terms, empty: false)
    }

    /// Exactly `limit` days ending on `endingOn`, oldest first.
    public static func build(_ days: [StressDayIn], endingOn: String, limit: Int = 14) -> [StressDay] {
        guard limit > 0 else { return [] }
        // `new Map(entries)` — a LATER duplicate overwrites an earlier one.
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        return stride(from: limit - 1, through: 0, by: -1).map { i in
            let date = ISODate.addDays(endingOn, -i) ?? endingOn
            return day(byDate[date], date: date)
        }
    }
}
