import Foundation

/// The eight muscle families — the grain every CHART groups by.
///
/// ── WHY EIGHT AND NOT THE SIX THIS USED TO BE ───────────────────────────────
/// The six were a port of the web app's `lib/theme/muscleHue.ts` (`familyOf`), which
/// folded biceps, triceps and forearms into one "Arms". That fold is fine for a
/// web app whose chart had six bars to colour; it is wrong for ONYX, because the
/// programme prescribes biceps and triceps SEPARATELY — they have their own
/// `plan_phase_volume` rows, their own targets and their own weeks where one is
/// met and the other is not. A family that cannot be behind on its own is not a
/// family, it is a label.
///
/// Founder decision 4 (2026-09-10): eight families, landmarks stepped
/// light → dark inside a family. Charts group by these eight; the atlas keeps
/// painting all sixteen landmarks.
///
/// ── THE ORDER IS PART OF THE TYPE ───────────────────────────────────────────
/// `CaseIterable` order is chart order and legend order, and it follows the
/// body from the chest outwards — chest, back, shoulders, the three arm
/// muscles, legs, core. A reordering here silently reorders every bar chart, so
/// it is a decision and not a formatting choice, exactly as in `LandmarkMuscle`.
public enum MuscleFamily: String, CaseIterable, Codable, Sendable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case forearms = "Forearms"
    case legs = "Legs"
    case core = "Core"

    public static func of(_ muscle: LandmarkMuscle) -> MuscleFamily {
        switch muscle {
        case .chest: return .chest
        case .lats, .upperBack, .lowerBack: return .back
        case .frontDelts, .sideDelts, .rearDelts: return .shoulders
        case .biceps: return .biceps
        case .triceps: return .triceps
        case .forearms: return .forearms
        case .quads, .hamstrings, .glutes, .adductors, .calves: return .legs
        case .absCore: return .core
        }
    }

    /// The landmarks this family owns, in `LandmarkMuscle` declaration order.
    ///
    /// Derived rather than listed: a second list of the sixteen is a second
    /// place for the taxonomy to be wrong, and `of(_:)` is already the one rule.
    public var members: [LandmarkMuscle] {
        LandmarkMuscle.allCases.filter { MuscleFamily.of($0) == self }
    }

    /// Where a landmark sits inside its own family — 0 is the first, and the
    /// LIGHTEST step of the family's colour ramp.
    ///
    /// This is why the step is intrinsic and not passed in by the caller. The
    /// old `Color.onyx.muscle(_:step:of:)` took "where the muscle sits in the
    /// list you happen to be drawing", so Lats was one teal in a session that
    /// trained three back muscles and a different teal in a session that trained
    /// one — the same muscle, two colours, on two screens of the same app.
    public static func step(of muscle: LandmarkMuscle) -> Int {
        of(muscle).members.firstIndex(of: muscle) ?? 0
    }
}
