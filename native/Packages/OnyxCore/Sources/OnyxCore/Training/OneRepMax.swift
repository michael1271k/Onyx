import Foundation

/// The estimated one-rep max — **Brzycki**, `weight × 36 / (37 − reps)`.
///
/// ── WHY THIS IS NOT `Epley` ANY MORE ────────────────────────────────────────
/// It was `weight × (1 + reps/30)`, inherited from the web app, and the number
/// it produced was the one figure in Onyx an athlete can hold against another
/// app's screen — because a 1RM estimate is not a measurement, it is a
/// convention, and a convention is only useful if it is the same convention.
/// Hevy, Strong and every calculator the founder was checking against report
/// Brzycki. Onyx reported a number 1–3 % lower for the same set and called it a
/// disagreement about training.
///
/// The type is RENAMED rather than quietly re-bodied. A type called `Epley`
/// computing Brzycki is the thing somebody decodes at 3am; the call sites are
/// mechanical and there are twenty-odd of them.
///
/// ── WHAT CHANGES, AND WHAT DOES NOT ─────────────────────────────────────────
/// Brzycki and Epley agree exactly at one rep (`36/36 = 1`) — so the single-rep
/// special case Epley needed is gone, not lost. Below ten reps Brzycki reads
/// slightly higher; above about twelve it climbs much faster, and past thirty
/// it is nonsense (`36/7` is five times the load). That is the formula's known
/// ceiling and it is why `maxReps` exists.
///
/// ── NIL ON UNLOADED WORK, AND THIS IS STILL THE WHOLE POINT ─────────────────
/// The formula yields 0 for every bodyweight set, and 0 is not "no estimate" —
/// it is a number, and the app printed it. The session report showed "1RM 0"
/// beside a Reverse Crunch 0 kg × 17, the PR history chart plotted a flat zero
/// series, and the per-session e1RM trend read 0 → 0 forever, so real rep
/// progress on core work looked like no progress at all. A bodyweight lift has
/// no one-rep max to estimate, so the honest answer is the absence of one.
///
/// The `Optional` return is load-bearing. Do not "simplify" it to 0.
public enum OneRepMax {

    /// The highest rep count Brzycki is allowed to answer for.
    ///
    /// The denominator is `37 − reps`: it reaches zero at 37 and goes NEGATIVE
    /// above it, so a 40-rep set would report a negative one-rep max. Even well
    /// before that the answer stops meaning anything — a 20-rep set estimates
    /// at 2.1× the load — so the cut is stated rather than left to the
    /// arithmetic to discover.
    ///
    /// Sixteen sits ABOVE every rep ceiling this program prescribes — the
    /// widest window in `Program.onyx5` is 12–15 — so no programmed set loses
    /// an axis to it. What it excludes is loaded endurance work, whose record
    /// is the rep count (`bestRepsAtWeight`) or the set volume, both of which
    /// the engine already scores. Move it in one line if that stops being true;
    /// do not move it past 36.
    public static let maxReps: Double = 16

    /// `weight × 36 / (37 − reps)`, rounded to two decimals.
    ///
    /// Two decimals, not one: see `jsRound2`.
    public static func estimate(weight: Double, reps: Double) -> Double? {
        guard weight.isFinite, weight > 0 else { return nil }
        guard reps.isFinite, reps >= 1, reps <= maxReps else { return nil }
        return jsRound2(weight * 36 / (37 - reps))
    }
}
