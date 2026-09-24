import Foundation

/// One micronutrient the Fuel faces call out (overhaul B2, W0 open call 3):
/// its `NutrientTargets` key, its label, and the day's total as a share of its
/// target (1.0 = on target).
public struct KeyMicro: Codable, Sendable, Equatable, Identifiable {
    public let key: String
    public let name: String
    public let pct: Double
    public var id: String { key }

    public init(key: String, name: String, pct: Double) {
        self.key = key
        self.name = name
        self.pct = pct
    }

    /// The `limit` micronutrients furthest from their targets, furthest first.
    ///
    /// ── WHICH NUTRIENTS ARE ELIGIBLE ────────────────────────────────────────
    /// Not the Macros group — protein and fibre already have their own rails
    /// on the same faces. Not the stack-delivered ones (`fromStack`): the widget
    /// sums FOOD, so a nutrient only the supplement stack delivers would read 0 %
    /// every day and take a slot forever. And not a nutrient with no reading at
    /// all — `NutrientTargets.isMet` treats nil as "nothing measured it", never
    /// as zero, and so does this.
    ///
    /// Deviation is the SHORTFALL for a floor and the OVERAGE for a ceiling —
    /// the direction that is a problem. 40 % of the sodium ceiling is a good
    /// day (the first test run picked exactly that), and so is 400 % of the
    /// vitamin C floor (code review): neither is the nutrient worth a glance.
    /// Ties keep the table's own order, so the pick is stable across refreshes.
    public static func top(
        totals: [String: Double],
        targets: [NutrientTarget] = NutrientTargets.all,
        limit: Int = 3
    ) -> [KeyMicro] {
        let eligible: [(index: Int, off: Double, micro: KeyMicro)] = targets.enumerated().compactMap { index, t in
            guard t.group != "Macros", !t.fromStack, t.target > 0, let total = totals[t.key] else { return nil }
            let pct = total / t.target
            let off = t.kind == .ceiling ? max(0, pct - 1) : max(0, 1 - pct)
            return (index, off, KeyMicro(key: t.key, name: t.label, pct: pct))
        }
        return eligible.sorted { a, b in a.off != b.off ? a.off > b.off : a.index < b.index }
            .prefix(max(0, limit))
            .map(\.micro)
    }
}
