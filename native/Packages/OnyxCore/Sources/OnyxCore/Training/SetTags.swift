import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// What a set WAS (its tag) and how it WENT (its quality) — two axes, one
// vocabulary each. A port of the web app's `lib/training/setTags.ts` minus colours.
//
// "Not a working set" used to be `setType !== 'warmup'` in twenty places;
// adding GHOST — a set that happened and does not count — by hand meant
// finding all twenty. So the question has a name, `isWorkingSet`, and a future
// tag is one line here.
//
// Quality is a second nullable column and changes NO arithmetic: a momentum
// set still counts its tonnage and can still set a record, because it
// happened. Null means "not reported", never "clean".
// ─────────────────────────────────────────────────────────────────────────────

public struct SetTag: Codable, Equatable, Sendable {
    /// The single character shown in the badge.
    public var label: String
    /// The whole word, for the tooltip and the export.
    public var full: String
}

public struct SetQuality: Codable, Equatable, Sendable {
    /// Shown on the row, under the numbers. Two words at most.
    public var label: String
    /// The whole sentence.
    public var full: String
}

public struct SetCompositionEntry: Codable, Equatable, Sendable {
    public var label: String
    public var full: String
    public var count: Int
}

public enum SetTags {
    public static let tags: [String: SetTag] = [
        "warmup": SetTag(label: "W", full: "Warm-up"),
        "failure": SetTag(label: "F", full: "Taken to failure"),
        "dropset": SetTag(label: "D", full: "Drop set"),
        "ghost": SetTag(label: "G", full: "Ghost set — logged, not counted"),
    ]

    /// The composition order — stable across sessions, and the order every
    /// chip row on either client draws in.
    ///
    /// Public since W3: the watch's Set Quality panel needs the four kinds in
    /// a fixed order, and a second list spelled out on the wrist is how two
    /// clients start disagreeing about what a set can be.
    public static let tagKeys = ["warmup", "failure", "dropset", "ghost"]

    private static let tagOrder = tagKeys

    /// ── THE THIRD LENGTH, AND WHY THE TABLE NEEDED ONE (W3) ─────────────────
    /// `SetTag.label` is a single glyph (`W`) and `SetTag.full` is a sentence
    /// ("Ghost set — logged, not counted"). A chip needs the word in between,
    /// and the phone has been spelling that word out in a `switch` inside
    /// `LoggerModel.SetKind` since wave U2 — where the watch cannot see it.
    ///
    /// So the word and its four-word meaning move here and the phone's enum
    /// delegates. That is a de-duplication and not a new table: two
    /// hand-maintained copies of one vocabulary both look right, which is the
    /// same argument `Program` makes about the muscle map.
    ///
    /// `nil` and `"normal"` both answer the unmarked set, because "normal" is
    /// the ABSENCE of a claim rather than a fifth kind — which is why neither
    /// client draws a chip for it.
    public static func word(for setType: String?) -> String {
        switch setType {
        case "warmup":  "Warm-up"
        case "failure": "Failure"
        case "dropset": "Drop"
        case "ghost":   "Ghost"
        default:        "Normal"
        }
    }

    /// What choosing a kind MEANS, in four words. Both clients keep one of
    /// these on screen at all times rather than stacking a hint under every
    /// chip.
    public static func hint(for setType: String?) -> String {
        switch setType {
        case "warmup":  "Before the work"
        case "failure": "Taken to failure"
        case "dropset": "No record from it"
        case "ghost":   "Logged, counts for nothing"
        default:        "Counts as work"
        }
    }

    /// Sets that are RECORDED but do not count as work: warm-ups and ghosts.
    public static func isWorkingSet(_ setType: String?) -> Bool {
        setType != "warmup" && setType != "ghost"
    }

    /// The tag for a stored `set_type`, or nil for a plain working set.
    public static func tag(for setType: String?) -> SetTag? {
        guard let setType, !setType.isEmpty else { return nil }
        return tags[setType]
    }

    /// A session's set composition as counted chips — `2W · 1F · 1D`. Only the
    /// kinds that occurred, in the fixed order.
    public static func composition(_ counts: [String: Int]) -> [SetCompositionEntry] {
        tagOrder.compactMap { key in
            let count = counts[key] ?? 0
            guard count > 0, let t = tags[key] else { return nil }
            return SetCompositionEntry(label: t.label, full: t.full, count: count)
        }
    }

    public static let quality: [String: SetQuality] = [
        "momentum": SetQuality(label: "Momentum", full: "Used body English to move the load"),
        "partial_rom": SetQuality(label: "Short ROM", full: "Cut the range short to finish the set"),
        "form_breakdown": SetQuality(label: "Form broke", full: "The last reps lost position"),
        "needed_warmup": SetQuality(label: "Cold", full: "The first reps were poor — needed a longer warm-up"),
        "assisted": SetQuality(label: "Assisted", full: "A spotter or the other arm helped"),
        "cut_short": SetQuality(label: "Cut short", full: "Stopped before the target for a reason other than failure"),
    ]

    /// Render order — matches the DB CHECK.
    public static let qualityKeys = ["momentum", "partial_rom", "form_breakdown", "needed_warmup", "assisted", "cut_short"]

    /// The quality for a stored value, or nil for a clean (null) set.
    public static func quality(for value: String?) -> SetQuality? {
        guard let value, !value.isEmpty else { return nil }
        return quality[value]
    }

    // ── MORE THAN ONE OF THEM AT A TIME ─────────────────────────────────────
    // `workout_sets.quality` is one `text` column. A set can be several of these
    // at once — "used momentum AND cut the range short" is one set, honestly
    // described — so the column has a GRAMMAR rather than a second shape: keys
    // joined by `+`, always in `qualityKeys` order. One key is byte-identical to
    // what every row already holds. `+` is in neither the key alphabet nor the
    // export's `·` separator alphabet, which is the whole requirement.
    //
    // This is the ONE parser. The app target's `SetQuality` enum is a typed
    // view over these strings and delegates here; the web read single keys
    // only and re-saved a combination as null, which is why the grammar lives
    // in OnyxCore and nowhere else.
    public static let qualitySeparator: Character = "+"

    /// A stored value → the known keys it names, in canonical order. An
    /// unknown key is DROPPED rather than failing the row: a value written by
    /// a newer client must not make an old one unable to draw the set at all.
    public static func parseQuality(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        let found = Set(raw.split(separator: qualitySeparator).map(String.init))
        return qualityKeys.filter(found.contains)
    }

    /// Keys → the stored string, canonical order. `nil` for none: "no tags" is
    /// the absence of a claim, and NULL is how the column says so.
    public static func joinQuality(_ keys: [String]) -> String? {
        let ordered = qualityKeys.filter(keys.contains)
        return ordered.isEmpty ? nil : ordered.joined(separator: String(qualitySeparator))
    }

    /// Guards a value arriving from the DB or a draft before it is written
    /// back. A value the CHECK constraint would refuse is refused here too —
    /// and the CHECK (`set-quality-tags.sql (git history)`) refuses an unknown key,
    /// an empty token, a repeat AND a non-canonical order. "Valid" is therefore
    /// exactly "survives a parse-and-join round trip unchanged".
    public static func isSetQuality(_ v: String?) -> Bool {
        guard let v, !v.isEmpty else { return false }
        return joinQuality(parseQuality(v)) == v
    }
}
