import Foundation

/// Movements trained ONE SIDE AT A TIME, so a set is two rows — an L and an R
/// sharing a `pairId`. A port of the web app's `lib/exercises/unilateral.ts`.
///
/// Sibling of `TimedExercise` and `Bodyweight`, and matched the same way: by
/// NAME, because the exercise catalogue has no laterality column.
///
/// ── WHAT THIS IS FOR ────────────────────────────────────────────────────────
/// The logger's "Split L / R" button. In the web it used to be gated by a regex
/// spelled inline in a component —
///
///     /single[- ]?arm|one[- ]?arm|single[- ]?leg|per (side|arm)/i
///
/// — four alternations covering three catalogue entries, with no test, no home
/// and no way to add the movements it misses (a Bulgarian split squat, a lunge
/// and a step-up are all unilateral and none of them say "single arm").
///
/// Splitting a BILATERAL set is not a harmless mistake either: the pair is
/// scored at its WEAKER side for tonnage and counts as ONE set of work, so a
/// press split in half is logged as half a session.
///
/// ── WHY "ALTERNATING" IS NOT HERE ───────────────────────────────────────────
/// An alternating curl is performed one arm at a time but logged as one set of
/// N total reps, which is the opposite of what a pair records. The rule is not
/// "does one limb move at a time" — it is "does this set produce two
/// independent loads worth tracking apart".
public enum Unilateral {

    /// The tell-tales. Anchored loosely — these words are qualifiers and can
    /// sit anywhere in a name — but specifically enough that no bilateral
    /// movement in the catalogue contains one.
    static let unilateralPatterns: [String] = [
        // "Single Arm", "Single-Leg", "One Arm", "1-Arm"
        #"\b(single|one|1)[-\s]?(arm|armed|leg|legged|side)\b"#,
        #"\bunilateral\b"#,
        // Rep strings and free-typed names carry the qualifier as a suffix.
        #"\bper\s+(side|arm|leg)\b"#,
        #"\b(each|ea)\s+(side|arm|leg)\b"#,
        // Movements that are unilateral by definition and never say so.
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

    /// Names that contain a tell-tale but are performed with both limbs
    /// together. Checked FIRST, so an explicit "double" always wins over a
    /// pattern match.
    static let bilateralOverride = #"\b(double|two|both|2)[-\s]?(arm|armed|leg|legged|side|sided)\b"#

    /// True when a set of this movement is one side at a time.
    public static func isUnilateral(_ exerciseName: String?) -> Bool {
        guard let name = exerciseName, !name.isEmpty else { return false }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return false }
        if n.matchesAnyPattern([bilateralOverride]) { return false }
        return n.matchesAnyPattern(unilateralPatterns)
    }
}

/// How a PAIR is drawn — one set box, whatever the two sides say.
///
/// ── WHY THIS IS A RULE AND NOT A VIEW DECISION ──────────────────────────────
/// A pair is ONE set everywhere it is counted (`SessionVolume` scores it at the
/// weaker side, `set_count` folds it on `pair_id`, the card's progress counts
/// it once) and it was TWO rows everywhere it was drawn. So a three-set lunge
/// rendered six boxes, six checkmarks and — because the badge prints the side
/// in place of the ordinal — a set list that ran `1, L, R, 4`. The deck was the
/// only place in the app that disagreed with the rest of it about what a set is.
///
/// The layout is the decision, and it is arithmetic on four optionals, so it
/// belongs here with a vector rather than inline in a `body` where the only
/// test available is a screenshot.
///
/// ── AND WHY THREE CASES AND NOT TWO ─────────────────────────────────────────
/// Two sides usually differ in ONE thing. Both arms press 12 kg × 10 and the
/// left one was harder — that is the ordinary case, and drawing it as two value
/// lines repeats `12 kg × 10` to say `9` instead of `8`. So the effort splits
/// on its own, in the effort column, and the value lines only split when the
/// numbers they hold actually differ.
public enum SetPairLayout: String, Sendable, Equatable {
    /// The sides agree on everything. Drawn as an ordinary set: no L, no R.
    case unified
    /// Same load and reps, different effort. One value line, and the two
    /// ratings printed compactly beside each other.
    case effortSplit
    /// The load or the rep count differs. Two sub-lines inside ONE set box.
    case valueSplit

    /// The layout for one group of rows, in deck order.
    ///
    /// A group of one is `unified` by definition — there is nothing to compare
    /// it against, and an unpaired row is not a pair.
    ///
    /// ── A PAIR IS NEVER `unified`, SINCE 2026-09-11 ─────────────────────────
    /// It was: two sides agreeing on load, reps AND effort drew as an ordinary
    /// set, with no L, no R and one effort control writing to both rows. That
    /// reads well and is a DEAD END, and the founder walked straight into it —
    /// split a Side Plank to rate the left side Challenging and the right side
    /// Hard at the same duration, and:
    ///
    ///   1. the split appeared to do nothing (the two new rows drew as the one
    ///      row they replaced — "the UI refused to spawn the L/R rows"), and
    ///   2. there was no way out, because the only control that could have made
    ///      the sides differ was the one writing to both of them. `effortSplit`
    ///      was reachable only from a state the UI could not produce.
    ///
    /// So a completed pair now always draws at least `effortSplit`: one value
    /// line — the numbers DO agree, and repeating them to say `9` instead of
    /// `8` is what the three cases exist to avoid — and two per-side effort
    /// controls, `L 8 · R 9`, each writing to its own row. Splitting is
    /// visible, and rating one side is possible.
    ///
    /// This is also what the WEB has always done:
    /// `ExerciseBreakdown.tsx` reads `row.kind === 'pair' && left && right` and
    /// draws two ratings with no equality test at all. The phone was the odd
    /// one out.
    ///
    /// `rpes` is no longer read. It stays in the signature because callers pass
    /// what they have and a shorter one would only move the decision about
    /// which fields matter out of this file, which is where it is tested.
    public static func resolve(
        weights: [Double?], reps: [Int?], rpes: [Double?]
    ) -> SetPairLayout {
        guard weights.count > 1 || reps.count > 1 || rpes.count > 1 else { return .unified }
        guard allEqual(weights), allEqual(reps) else { return .valueSplit }
        return .effortSplit
    }

    /// Every element equal to the first — `nil` included, because "unrated" is
    /// a value the two sides can agree on and `nil != 8` is a disagreement
    /// worth drawing.
    private static func allEqual<T: Equatable>(_ values: [T?]) -> Bool {
        guard let first = values.first else { return true }
        return values.allSatisfy { $0 == first }
    }
}
