import Foundation

/// The volume chart's buckets — a port of the web app's `lib/charts/volumeSplit.ts`.
/// A session is bucketed by what was PERFORMED (its own day_key), never by the
/// weekday the template says; the weekday guess survives only for legacy rows.
public enum VolumeSplit {
    public static let axisSplits = ["upper_a", "upper_b", "arms", "legs_a", "legs_b"]
    public static let pplSplits = ["push", "pull", "legs"]

    public static func splits(forEra era: String) -> [String] {
        switch era {
        case "ppl": return pplSplits
        case "axis": return axisSplits
        default: return axisSplits + pplSplits
        }
    }

    public static func label(_ s: String) -> String {
        switch s {
        case "upper_a": return "Upper A"
        case "upper_b": return "Upper B"
        case "arms": return "Delts & Arms"
        case "legs_a": return "Legs & Core A"
        case "legs_b": return "Legs & Core B"
        case "legs": return "Legs"
        default: return s.prefix(1).uppercased() + s.dropFirst()
        }
    }

    /// The program day a session RECORDED for itself → its chart bucket.
    public static let dayKeySplit: [String: String] = [
        "cb_a": "upper_a", "cb_b": "upper_b", "arms": "arms", "legs_a": "legs_a", "legs_b": "legs_b",
        "upper_a": "upper_a", "upper_b": "upper_b", "lower_a": "legs_a", "lower_b": "legs_b",
        "ppl_push_sun": "push", "ppl_push_thu": "push",
        "ppl_pull_mon": "pull", "ppl_pull_fri": "pull", "ppl_legs_tue": "legs",
    ]

    public static func resolve(dateISO: String, split: String, era: String, dayKey: String?) -> String {
        if let k = dayKey, !k.isEmpty, let byKey = dayKeySplit[k] { return byKey }
        if split == "lower" { return "legs" }
        if era == "axis", let weekday = ISODate.weekday(dateISO) {
            if split == "upper" { return weekday == 2 ? "arms" : weekday == 4 ? "upper_b" : "upper_a" }
            if split == "legs" { return weekday == 1 ? "legs_a" : weekday == 5 ? "legs_b" : "legs" }
        }
        return split
    }
}
