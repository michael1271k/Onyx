import SwiftUI
import OnyxCore

/// Which muscle is under a finger.
///
/// ── WHY THE PATHS ARE THE HIT TARGETS AND NOT A GRID OF BOXES ───────────────
/// The obvious cheap answer is a table of rectangles over the figure — ten
/// boxes for the ten groups, tuned by eye. It is cheap until the atlas is
/// regenerated: `OnyxAtlas.swift` is emitted from the web app's `lib/body/atlas.ts` and
/// `atlas-parity.test.ts` fails when the two disagree, so the DRAWING can never
/// drift — but a hand-tuned box table is not in that contract and would drift
/// silently, leaving taps landing on the muscle next door.
///
/// So the hit test is the drawing: the same closures, built into the same rect,
/// asked `Path.contains`. Thirty-five paths per tap is nothing (a tap is a
/// once-per-second event and these are 4–12 segment curves), and correctness is
/// free forever.
///
/// ── Z-ORDER ────────────────────────────────────────────────────────────────
/// `OnyxAtlas.muscles` is in PAINT order — later entries are drawn over
/// earlier ones, and several overlap at the seams (the delts sit over the top of
/// the chest, the forearms over the wrist end of the biceps). What you see at a
/// point is the LAST path that covers it, so the search runs backwards and the
/// answer is what the eye was pointing at.
public extension OnyxAtlas {

    /// The muscle drawn at `point` within `rect`, or nil for the silhouette,
    /// the gaps and everything outside the figure.
    ///
    /// `rect` is the frame the figure was DRAWN into — the same rect handed to
    /// the path builders — so the letter-boxing `pt` applies is already
    /// accounted for and a tap in the margin correctly answers nil.
    static func muscle(at point: CGPoint, in rect: CGRect, side: OnyxAtlasView) -> LandmarkMuscle? {
        for entry in muscles.reversed() where entry.view == side {
            var path = Path()
            entry.build(rect, &path)
            if path.contains(point) {
                return LandmarkMuscle(rawValue: entry.muscle)
            }
        }
        return nil
    }

    /// Every landmark the atlas can draw on one side, in paint order and
    /// without repeats — the list an accessibility rotor walks, and the check
    /// that a name in the generated file still resolves to a landmark.
    static func landmarks(on side: OnyxAtlasView) -> [LandmarkMuscle] {
        var seen: Set<LandmarkMuscle> = []
        return muscles.compactMap { entry -> LandmarkMuscle? in
            guard entry.view == side, let muscle = LandmarkMuscle(rawValue: entry.muscle),
                  seen.insert(muscle).inserted
            else { return nil }
            return muscle
        }
    }
}
