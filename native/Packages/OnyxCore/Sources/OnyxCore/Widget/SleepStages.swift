import Foundation

/// The four sleep stages, in DEPTH order — the order every sleep figure in the
/// app draws them in (overhaul B2).
///
/// ── ONE RULE, WHERE THERE WERE THREE ────────────────────────────────────────
/// `sleepSegments` (the tiles) ran deep → core → REM → awake and kept a zero;
/// Pulse's `SleepHeroCell` and `SleepEditSheet` ran deep → REM → core → awake
/// and dropped zeros. The same night drew its middle two stages in opposite
/// order on two tabs, under one fixed colour ramp that is itself ordered by
/// depth (`OnyxInk.Fixed.sleep`). This is now the only spelling.
public enum SleepStage: Int, CaseIterable, Sendable {
    case deep, core, rem, awake

    /// The stages as a figure wants them, depth order.
    ///
    /// A nil stage is ABSENT — "the watch did not report deep sleep" — and is
    /// left out; a zero stays — "you had no deep sleep" — and simply draws no
    /// width. A night synced as a duration alone therefore has no segments,
    /// and a figure draws its empty track rather than inventing a composition.
    public static func segments(deep: Int?, core: Int?, rem: Int?, awake: Int?) -> [(SleepStage, Int)] {
        [(SleepStage.deep, deep), (.core, core), (.rem, rem), (.awake, awake)]
            .compactMap { stage, minutes in minutes.map { (stage, max(0, $0)) } }
    }
}
