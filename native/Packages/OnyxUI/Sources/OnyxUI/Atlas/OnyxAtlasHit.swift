import SwiftUI
import OnyxCore

/// Which muscle is under a finger, and which side of it.
///
/// ── WHY THE PATHS ARE THE HIT TARGETS AND NOT A GRID OF BOXES ───────────────
/// The obvious cheap answer is a table of rectangles over the figure — ten
/// boxes for the ten groups, tuned by eye. It is cheap until the atlas is
/// regenerated: `OnyxAtlas.swift` is emitted from `scripts/src/atlas.ts` and
/// `npm run check:atlas` fails when the two disagree, so the DRAWING can never
/// drift — but a hand-tuned box table is not in that contract and would drift
/// silently, leaving taps landing on the muscle next door.
///
/// So the hit test is the drawing: the same closures, built into the same rect,
/// asked `Path.contains`. Thirty-five paths per tap is nothing (a tap is a
/// once-per-second event and these are 4–12 segment curves), and correctness is
/// free forever.
///
/// ── AND THE SIDE WAS ALWAYS IN THE ANSWER ───────────────────────────────────
/// A bilateral muscle is two entries per view, mirrored about x = 60, and the
/// search below already finds WHICH of the two contains the tap. Until W9 it
/// threw that away and returned the muscle alone, so "the right glute" and "the
/// left glute" were one answer. `OnyxAtlasPath.side` is the generator writing
/// the fact down; this function is the one that stops discarding it.
///
/// ── Z-ORDER ────────────────────────────────────────────────────────────────
/// `OnyxAtlas.muscles` is in PAINT order — later entries are drawn over
/// earlier ones, and several overlap at the seams (the delts sit over the top of
/// the chest, the forearms over the wrist end of the biceps). What you see at a
/// point is the LAST path that covers it, so the search runs backwards and the
/// answer is what the eye was pointing at.
public extension OnyxAtlas {

    /// The muscle drawn at `point` within `rect` and the side of it, or nil for
    /// the silhouette, the gaps and everything outside the figure.
    ///
    /// `rect` is the frame the figure was DRAWN into — the same rect handed to
    /// the path builders — so the letter-boxing `pt` applies is already
    /// accounted for and a tap in the margin correctly answers nil.
    ///
    /// `side:` here is the VIEW — front or back — and has been since this
    /// function was written. The `BodySide` in the answer is the other kind of
    /// side, which is exactly why the return is a named `MuscleSide` and not a
    /// bare tuple: `(muscle, .left)` at a call site that also passes `.front`
    /// is two different words spelled the same.
    static func muscle(at point: CGPoint, in rect: CGRect, side view: OnyxAtlasView) -> MuscleSide? {
        for entry in muscles.reversed() where entry.view == view {
            var path = Path()
            entry.build(rect, &path)
            if path.contains(point) {
                guard let muscle = LandmarkMuscle(rawValue: entry.muscle) else { return nil }
                return MuscleSide(muscle, entry.side)
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

    /// The same walk, one entry per landmark AND side.
    ///
    /// Twenty-six rows on the front where `landmarks(on:)` gives fourteen — the
    /// rotor's list once a glute is two things you can rate. An axial muscle
    /// appears once, as `both`, because it is one thing and offering "Upper
    /// back, left" would be a control with nothing behind it.
    static func sidedLandmarks(on side: OnyxAtlasView) -> [MuscleSide] {
        var seen: Set<MuscleSide> = []
        return muscles.compactMap { entry -> MuscleSide? in
            guard entry.view == side, let muscle = LandmarkMuscle(rawValue: entry.muscle) else { return nil }
            let key = MuscleSide(muscle, entry.side)
            return seen.insert(key).inserted ? key : nil
        }
    }
}
