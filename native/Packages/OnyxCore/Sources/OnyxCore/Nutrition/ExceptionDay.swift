import Foundation

/// A day that was ALLOWED to miss its calorie target.
///
/// A dinner out on week six of a cut is not a lapse in discipline, but the
/// scorer cannot tell the difference: 3,200 kcal against a 1,900 goal is a 68%
/// overshoot, the cut asymmetry multiplies it by 1.5, and a planned evening
/// lands the day's largest score component (nutrition, weight 0.30) somewhere
/// near 18. Repeat that four times in a phase and the score stops describing the
/// phase — it describes your social life.
///
/// So the deviation is DECLARED rather than inferred, and the declaration
/// changes exactly one thing.
///
/// ── THE RULE: FORGIVE THE GRADE, NEVER THE ARITHMETIC ───────────────────────
/// An exception day is graded on protein alone. It is NOT excluded from anything
/// that adds numbers up: the week's average intake, the TDEE deficit and the
/// weight trend all see the real figure, because they describe physics and
/// physics did not get the memo.
///
/// ── NULL MEANS NO EXCEPTION — NOTE THE INVERSION ────────────────────────────
/// `lib/body/weighIn.ts` is this module's sibling and looks almost identical,
/// but its default runs the other way: an unrecorded weigh-in skip resolves to
/// "As Planned", because skipping the scale IS the protocol. Here, absence means
/// an ordinary day. Do not copy that fallback into this file when it is ported.
public enum ExceptionDay {

    /// The offered reasons, in rough order of expected frequency.
    ///
    /// Deliberately no "Other"-with-free-text: the reason exists so a week-old
    /// row still explains itself in the export, and five words do that as well
    /// as a sentence would.
    public static let reasons = ["Event", "Holiday", "Refeed", "Travel", "Illness", "Social"]

    /// The reason stored against a day, or nil for an ordinary day.
    ///
    /// Whitespace-only is absent: a stored `" "` is not a reason, and printing it
    /// would produce `[Exception: ]` in the export and a nameless highlight in
    /// the UI. Anything non-empty is honoured even if it is not one of the
    /// presets — a value written before the list changed must never silently
    /// stop counting.
    public static func reason(_ stored: String?) -> String? {
        guard let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// Was this day declared an exception?
    public static func isException(_ stored: String?) -> Bool {
        reason(stored) != nil
    }

    /// The export's tag for a day, or an empty string for an ordinary one.
    ///
    /// A suffix rather than a whole line, so the day keeps its real numbers in
    /// front of it — the tag annotates the figures, it does not replace them.
    public static func tag(_ stored: String?) -> String {
        reason(stored).map { " [Exception: \($0)]" } ?? ""
    }

    /// ── ESTIMATED — THE OTHER AXIS, AND IT FORGIVES NOTHING ─────────────────
    ///
    /// "I ate out and could not weigh it" is a statement about CONFIDENCE, not
    /// about permission. It is orthogonal to the exception above and the two
    /// co-occur constantly: a restaurant birthday is both a declared surplus AND
    /// a guess. That is why it is a second field and not a third enum case — an
    /// enum would force the day to pick one of two true things to say.
    ///
    /// It has no scoring counterpart, and adding one would be a bug: an estimate
    /// is still your best knowledge of what you ate, so grading it more gently
    /// would mean the score improves when the measurement gets worse.
    /// Uncertainty is reported, never rewarded.
    public static func estimatedTag(_ estimated: Bool?) -> String {
        estimated == true ? " [Estimated]" : ""
    }
}
