import SwiftUI
import OnyxCore

/// The four effort bands as ink (overhaul A3, decision Q2) — ONE table, read by
/// the watch's rest ladder and the phone's deck card, so a Crown scrub and the
/// provisional capsule it paints on the phone are the same colour.
///
/// Steady is the theme's accent: an ordinary working set is the user's own
/// colour. The three that mean "close to the edge" are FIXED, in every theme,
/// because they are warnings and a warning cannot change hue with a preset —
/// a warm amber (the record gold's family, the one fixed warm ink), a clay
/// terracotta, and failure in the fixed heart red.
///
/// In `Accessory/` because it is unfenced: the watch app links OnyxUI for
/// watchOS and this is the one folder both platforms compile.
public extension EffortBand {
    ///
    /// ── MIXED FROM TWO FIXED TOKENS, NOT NEW HEXES ──────────────────────────
    /// Raw colour lives in the token files only (`TokenDisciplineTests`), and
    /// this folder is not one. The warm band is the record gold walked toward
    /// the heart red: a quarter of the way is amber (gold-adjacent but not the
    /// PR gold, which `Color.onyx.effort` rightly refuses to share), past half
    /// is clay, all the way is failure. Fixed in every theme, because both ends
    /// are. Request for W6: lift these two into `OnyxInk.Fixed` by name.
    var ink: Color {
        switch self {
        case .steady: OnyxInk.Themed.accent
        case .hard: OnyxInk.Fixed.record.mix(with: OnyxInk.Fixed.heart, by: 0.25)
        case .veryHard: OnyxInk.Fixed.record.mix(with: OnyxInk.Fixed.heart, by: 0.6)
        case .failure: OnyxInk.Fixed.heart
        }
    }

    /// The band in a word, for a capsule and for VoiceOver.
    var title: String {
        switch self {
        case .steady: "Steady"
        case .hard: "Hard"
        case .veryHard: "Very hard"
        case .failure: "Failure"
        }
    }
}
