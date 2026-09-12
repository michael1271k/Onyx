import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Borg CR10 — the session-level effort scale, the per-set RPE ladder, and the
// session effort WORDS. A port of the web app's `lib/training/effort.ts` minus colours.
//
// CR10 is a RATIO scale: 10 is maximal, half-steps are real, and the column is
// numeric(3,1). Per-set RPE is reps-in-reserve and clusters at 8–9.5 on a
// hypertrophy block; session effort asks a different question, so the
// suggestion is read RELATIVE to what that day type usually costs — an
// absolute reading called every ordinary Tuesday "Extremely hard".
// ─────────────────────────────────────────────────────────────────────────────

public struct Cr10Anchor: Codable, Equatable, Sendable {
    public var value: Double
    public var label: String
}

public struct RpeStop: Codable, Equatable, Sendable {
    /// Stored value. Always on the 0.5 grid.
    public var value: Double
    public var label: String
    /// Reps-in-reserve gloss.
    public var hint: String
}

public struct EffortWord: Codable, Equatable, Sendable {
    public var key: String
    public var label: String
    /// What lands in `session_rpe`.
    public var cr10: Double
    public var hint: String
}

public enum Effort {
    public static let cr10Min: Double = 1
    public static let cr10Max: Double = 10

    /// Verbal anchors, ascending. Only the canonical CR10 points are named.
    public static let anchors: [Cr10Anchor] = [
        Cr10Anchor(value: 1, label: "Very light"),
        Cr10Anchor(value: 2, label: "Light"),
        Cr10Anchor(value: 3, label: "Moderate"),
        Cr10Anchor(value: 4, label: "Somewhat hard"),
        Cr10Anchor(value: 5, label: "Hard"),
        Cr10Anchor(value: 7, label: "Very hard"),
        Cr10Anchor(value: 9, label: "Extremely hard"),
        Cr10Anchor(value: 10, label: "Maximal"),
    ]

    /// The nearest anchor at or below `v` — every rating gets a word.
    public static func cr10Label(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "—" }
        var label = anchors[0].label
        for a in anchors where v >= a.value { label = a.label }
        return label
    }

    /// Clamp + snap to the 0.5 grid. Nil for anything unusable, so a blank
    /// never writes a 0 (which would read as "no effort", not "not rated").
    public static func normalizeCr10(_ v: Double?) -> Double? {
        guard let v, v.isFinite else { return nil }
        let snapped = jsRound(v * 2) / 2
        if snapped < cr10Min { return cr10Min }
        if snapped > cr10Max { return cr10Max }
        return snapped
    }

    /// The per-set ladder. Eight stops, all on the 0.5 grid the column stores.
    public static let ladder: [RpeStop] = [
        RpeStop(value: 5, label: "Very Easy", hint: "5+ reps left"),
        RpeStop(value: 6.5, label: "Easy", hint: "~4 left"),
        RpeStop(value: 7.5, label: "Medium", hint: "3 left"),
        RpeStop(value: 8, label: "Challenging", hint: "2–3 left"),
        RpeStop(value: 8.5, label: "Hard", hint: "2 left"),
        RpeStop(value: 9, label: "Very Hard", hint: "1 left"),
        RpeStop(value: 9.5, label: "Max Effort", hint: "0 left, form held"),
        RpeStop(value: 10, label: "Failure", hint: "missed or form broke"),
    ]

    /// Index of the lit pip, or -1 for unrated and for off-ladder values.
    public static func rpeStopIndex(_ v: Double?) -> Int {
        guard let v, v.isFinite else { return -1 }
        return ladder.firstIndex { $0.value == v } ?? -1
    }

    /// Ladder label on an exact stop, CR10 anchor otherwise — rows written
    /// before the ladder existed hold 6, 7, 8, 9 and 10, and none may render as a dash.
    public static func rpeLabel(_ v: Double?) -> String {
        let i = rpeStopIndex(v)
        return i >= 0 ? ladder[i].label : cr10Label(v)
    }

    /// ±0.5, never inventing a rating on an unrated set.
    public static func nudgeRpe(_ v: Double?, _ dir: Double) -> Double? {
        guard let v, v.isFinite else { return nil }
        return normalizeCr10(v + dir * 0.5)
    }

    /// How hard the SESSION was, as five words. Each carries its stored number.
    public static let words: [EffortWord] = [
        EffortWord(key: "easy",       label: "Easy",       cr10: 5,   hint: "lighter than usual — plenty left"),
        EffortWord(key: "solid",      label: "Solid",      cr10: 6.5, hint: "a normal working session"),
        EffortWord(key: "hard",       label: "Hard",       cr10: 8,   hint: "the session you planned, in full"),
        EffortWord(key: "brutal",     label: "Brutal",     cr10: 9,   hint: "harder than this day usually is"),
        EffortWord(key: "everything", label: "Everything", cr10: 10,  hint: "nothing left in the tank"),
    ]

    /// The stored number for a word.
    public static func effortCr10(_ key: String?) -> Double? {
        words.first { $0.key == key }?.cr10
    }

    /// The word a stored `session_rpe` reads back as — nearest rung, ties to the
    /// lower. 6, 7 and 8 land on Solid, Solid and Hard.
    public static func effortWord(for cr10: Double?) -> EffortWord? {
        guard let cr10, cr10.isFinite else { return nil }
        return words.dropFirst().reduce(words[0]) { best, w in
            abs(w.cr10 - cr10) < abs(best.cr10 - cr10) ? w : best
        }
    }

    /// This athlete's own trailing mean per-set rating — the baseline when a
    /// day type has no history yet.
    public static let coldBaseline = 8.8
    /// Below three prior sessions of the same type, a median is a coin toss.
    public static let minHistory = 3

    /// Suggest a word from this session's mean per-set rating, RELATIVE to what
    /// this day type usually costs. Quarter-point bands.
    public static func suggestEffortWord(mean: Double?, history: [Double] = []) -> EffortWord? {
        guard let mean, mean.isFinite else { return nil }
        let usable = history.filter(\.isFinite)
        let baseline = usable.count >= minHistory ? median(usable) : coldBaseline
        let delta = mean - baseline
        if delta <= -0.75 { return words[0] }
        if delta <= -0.25 { return words[1] }
        if delta < 0.25 { return words[2] }
        if delta < 0.75 { return words[3] }
        return words[4]
    }

    /// Median, not mean: one savage session must not move the bar it is about to be judged against.
    static func median(_ xs: [Double]) -> Double {
        let sorted = xs.sorted()
        let mid = sorted.count >> 1
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
