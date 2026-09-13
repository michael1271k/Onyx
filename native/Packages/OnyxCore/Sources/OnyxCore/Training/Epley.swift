import Foundation

/// Estimated one-rep max — a port of `epley1RM` in the web app's `lib/utils/epley.ts`.
public enum Epley {
    /// `weight × (1 + reps/30)`, rounded to one decimal. Returns the weight
    /// unchanged for a single rep.
    ///
    /// ── NIL ON UNLOADED WORK, AND THIS IS THE WHOLE POINT ───────────────────
    /// The formula yields 0 for every bodyweight set, and 0 is not "no
    /// estimate" — it is a number, and the app printed it. The session report
    /// showed "1RM 0" beside a Reverse Crunch 0 kg × 17, the PR history chart
    /// plotted a flat zero series, and the per-session e1RM trend read 0 → 0
    /// forever, so real rep progress on core work looked like no progress at
    /// all. A bodyweight lift has no one-rep max to estimate, so the honest
    /// answer is the absence of one.
    ///
    /// Negatives are guarded for the same reason: nothing downstream should
    /// have to decide what a −12 kg e1RM means.
    ///
    /// The `Optional` return is load-bearing. Do not "simplify" it to 0.
    public static func oneRepMax(weight: Double, reps: Double) -> Double? {
        guard weight.isFinite, weight > 0 else { return nil }
        if reps == 1 { return weight }
        return jsRound1(weight * (1 + reps / 30))
    }
}
