import Foundation

/// Name-matched movement flags — ports of the web app's `lib/exercises/{bodyweight,
/// unilateral,icons}.ts`. The catalog is a name table with no equipment or
/// laterality column, so these are HEURISTICS on the name and behave like one.

func matches(_ pattern: String, _ text: String, caseInsensitive: Bool = true) -> Bool {
    let re = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

public enum BodyweightExercise {
    static let patterns = [
        #"\b(hanging\s+)?(knee|leg)\s+raises?$"#,
        #"\breverse\s+crunch(es)?$"#,
        #"^crunch(es)?$"#,
        #"\bsit[-\s]?ups?$"#,
        #"\bpush[-\s]?ups?$"#,
        #"\b(pull|chin)[-\s]?ups?$"#,
        #"\bdips?$"#,
        #"\bback\s+extensions?$"#,
        #"\bglute\s+bridges?$"#,
        #"\bmountain\s+climbers?$"#,
        #"\bbicycle\s+crunch(es)?$"#,
        #"\bflutter\s+kicks?$"#,
        #"\bair\s+squats?$"#,
    ]
    static let loadable = [
        #"\b(pull|chin)[-\s]?ups?$"#,
        #"\bdips?$"#,
        #"\bpush[-\s]?ups?$"#,
        #"\bback\s+extensions?$"#,
    ]
    static let qualifier = #"\b(machine|cable|smith|barbell|dumbbell|db|plate|assisted)\b"#

    /// True when the movement carries no external load by default — reps are the record.
    public static func isBodyweight(_ name: String?) -> Bool {
        guard let name = name, !name.isEmpty else { return false }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if matches(qualifier, n) { return false }
        return patterns.contains { matches($0, n) }
    }

    /// Unloaded for EITHER reason — a rep-only movement or a timed hold.
    public static func isUnloaded(_ name: String?) -> Bool {
        TimedExercise.isTimed(name) || isBodyweight(name)
    }

    /// Bodyweight AND has a genuine weighted variant.
    public static func isLoadableBodyweight(_ name: String?) -> Bool {
        guard isBodyweight(name) else { return false }
        let n = name!.trimmingCharacters(in: .whitespacesAndNewlines)
        return loadable.contains { matches($0, n) }
    }
}

public enum UnilateralExercise {
    static let patterns = [
        #"\b(single|one|1)[-\s]?(arm|armed|leg|legged|side)\b"#,
        #"\bunilateral\b"#,
        #"\bper\s+(side|arm|leg)\b"#,
        #"\b(each|ea)\s+(side|arm|leg)\b"#,
        #"\bbulgarian\b"#,
        #"\bsplit\s+squats?\b"#,
        #"\blunges?\b"#,
        #"\bstep[-\s]?ups?\b"#,
        #"\bpistol\s+squats?\b"#,
        #"\bskater\s+squats?\b"#,
        #"\bcopenhagen\b"#,
        #"\bsuitcase\s+(carry|carries|deadlift)\b"#,
        #"\bside\s+planks?\b"#,
    ]
    static let bilateralOverride = #"\b(double|two|both|2)[-\s]?(arm|armed|leg|legged|side|sided)\b"#

    /// True when a set of this movement is one side at a time.
    public static func isUnilateral(_ name: String?) -> Bool {
        guard let name = name, !name.isEmpty else { return false }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return false }
        if matches(bilateralOverride, n) { return false }
        return patterns.contains { matches($0, n) }
    }
}

/// The glyph RULE for a movement — the label only. The lucide/SF glyph is OnyxUI's.
public enum ExerciseIcon {
    static let rules: [(String, String)] = [
        (#"\b(treadmill|walk|run|jog|incline\s*walk)\b"#, "Treadmill"),
        (#"\b(plank|hollow\s*hold|dead\s*hang|wall\s*sit|l-?sit|hold)\b"#, "Timed hold"),
        (#"\b(carry|farmer)\b"#, "Loaded carry"),
        (#"\b(pull-?up|chin-?up|hang(ing)?)\b"#, "Hanging"),
        (#"\bcable\b|\(cable\)"#, "Cable"),
        (#"\bdumbbell\b|\(dumbbell\)|\bdb\b"#, "Dumbbell"),
        (#"\bbarbell\b|\(barbell\)|\bsmith\b|\bbb\b"#, "Barbell"),
        (#"\bmachine\b|\(machine\)|\bpress\s*machine\b|\bsled\b"#, "Machine"),
        (#"\b(bodyweight|push-?up|dip|sit-?up|crunch|raise)\b"#, "Bodyweight"),
    ]
    public static let fallback = "Exercise"

    /// The catalogue's own answer, by canonical name — the port of
    /// `EQUIPMENT_BY_NAME` in the web app's `lib/exercises/equipment.ts`.
    ///
    /// ── WHY A TABLE NOW ─────────────────────────────────────────────────────
    /// This file's header says the catalogue is "a name table with no equipment
    /// column", which is what made `rules` the whole answer. On 2026-09-07 the
    /// founder moved the kit out of the titles and into `exercises.equipment`,
    /// so thirteen movements lost the only word that placed them — and
    /// `Single Arm Triceps Pushdown`, with "(Cable)" gone, fell through to the
    /// LAST rule and came back `Bodyweight`. The logger hides the load column on
    /// a bodyweight movement, so a cable pushdown would have had nowhere to
    /// record what it was done with. A missing hint became a wrong claim.
    ///
    /// The table wins; `rules` stays underneath for a movement nobody has
    /// classified yet. Keep it equal to the TypeScript one.
    public static let byName: [String: String] = [
        "chest press": "Machine",
        "hip adduction": "Machine",
        "hip thrust": "Machine",
        "preacher curl": "Machine",
        "lateral raise": "Machine",
        "calf press": "Machine",
        "leg extension": "Machine",
        "leg press": "Machine",
        "hack squat": "Machine",
        "seated leg curl": "Machine",
        "pec deck": "Machine",
        "lat pulldown": "Machine",
        "neutral-grip lat pulldown": "Machine",
        "crunch machine": "Machine",
        "bicep curl": "Dumbbell",
        "hammer curl": "Dumbbell",
        "shoulder press": "Dumbbell",
        "romanian deadlift": "Dumbbell",
        "seated lateral raise": "Dumbbell",
        "overhead triceps extension": "Cable",
        "single arm lateral raise": "Cable",
        "single arm triceps pushdown": "Cable",
        "straight-arm pulldown": "Cable",
        "rope triceps pushdown": "Cable",
        "face pull": "Cable",
    ]

    /// Matched against the LOWERCASED name, most-specific first. Never nil.
    public static func label(for name: String?) -> String {
        guard let name = name, !name.isEmpty else { return fallback }
        let lower = name.lowercased()
        // The table is the catalogue's own answer and outranks every heuristic.
        if let known = byName[lower.trimmingCharacters(in: .whitespaces)] { return known }
        return rules.first { matches($0.0, lower, caseInsensitive: false) }?.1 ?? fallback
    }
}
