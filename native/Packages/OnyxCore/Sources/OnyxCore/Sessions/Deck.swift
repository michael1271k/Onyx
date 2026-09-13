import Foundation

/// The deck's row arithmetic — a port of the web app's `lib/sessions/deck.ts` (extracted
/// from ExerciseCard and SetEditorRow) plus `setValueLabel` from setGrid.ts.

/// One display group of the deck: a single set, or a unilateral L/R pair folded
/// into ONE numbered row. Mirrors the TS discriminated union as one struct.
public struct SetGroup: Codable, Sendable, Equatable {
    public struct Indexed: Codable, Sendable, Equatable {
        public var idx: Int
        public var set: DraftSet
    }
    public var kind: String          // "single" | "pair"
    public var num: Int
    public var idx: Int?
    public var set: DraftSet?
    public var pairId: String?
    public var left: Indexed?
    public var right: Indexed?
}

public enum Deck {
    /// Coach status chip labels; the colours are OnyxUI's.
    public static let statusLabels: [String: String] = [
        "PR": "PR", "PROGRESS": "PROG ▲", "HOLD": "HOLD", "REGRESS": "REGR ▼", "NEW": "NEW",
    ]

    /// What the value column is called, per grid mode.
    public static func valueLabel(mode: String) -> String {
        if mode == "time" { return "Sec" }
        if mode == "cardio" { return "Min" }
        return "Reps"
    }

    /// A truthy pairId folds two rows into one group in first-seen order.
    public static func groupSets(_ sets: [DraftSet]) -> [SetGroup] {
        var groups: [SetGroup] = []
        var pairIndex: [String: Int] = [:]
        var num = 0
        for (idx, set) in sets.enumerated() {
            if let p = set.pairId, !p.isEmpty {
                var gi = pairIndex[p]
                if gi == nil {
                    num += 1
                    groups.append(SetGroup(kind: "pair", num: num, pairId: p))
                    gi = groups.count - 1
                    pairIndex[p] = gi
                }
                if set.side == "R" { groups[gi!].right = SetGroup.Indexed(idx: idx, set: set) }
                else { groups[gi!].left = SetGroup.Indexed(idx: idx, set: set) }
            } else {
                num += 1
                groups.append(SetGroup(kind: "single", num: num, idx: idx, set: set))
            }
        }
        return groups
    }

    public static let plateStep = 2.5
    public static let fineStep = 0.25

    /// Snap to the quarter-kg grid, never below 0.
    public static func nudgeLoad(_ weightKg: Double, _ delta: Double) -> Double {
        max(0, jsRound((weightKg + delta) * 4) / 4)
    }

    public static func nudgeReps(_ reps: Double, _ delta: Double) -> Double { max(1, reps + delta) }

    /// The shortest of 0/1/2 decimals that is exact — 3.75 never "3.8".
    public static func fmtKg(_ w: Double) -> String {
        if w.truncatingRemainder(dividingBy: 1) == 0 { return jsToFixed(w, 0) }
        if (w * 10).truncatingRemainder(dividingBy: 1) == 0 { return jsToFixed(w, 1) }
        return jsToFixed(w, 2)
    }

    /// toFixed with dead zeros trimmed (`/\.?0+$/`), "0" when nothing is left.
    public static func trimNum(_ v: Double, digits: Int) -> String {
        let fixed = jsToFixed(v, digits)
        let trimmed = fixed.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        return trimmed.isEmpty ? "0" : trimmed
    }
}
