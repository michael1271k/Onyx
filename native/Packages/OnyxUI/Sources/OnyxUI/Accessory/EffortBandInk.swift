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
    var ink: Color {
        switch self {
        case .steady: OnyxInk.Themed.accent
        case .hard: Color(hex: 0xE3A23B)
        case .veryHard: Color(hex: 0xC8694B)
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
