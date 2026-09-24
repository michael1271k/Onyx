import SwiftUI

/// The motion vocabulary, in two numbers.
///
/// ── WHY THIS REPLACES `lib/motion/springs.ts` RATHER THAN PORTING IT ────────
/// The web app carries 233 lines to get spring physics into CSS. SwiftUI's
/// `Animation.spring(response:dampingFraction:)` takes exactly the two
/// parameters Apple's own designers use — *response* (how fast it reaches the
/// target, in seconds) and *damping fraction* (how much it overshoots) — so the
/// port is four constants and the file it replaces is deleted.
///
/// ── AND WHY THE DEFAULT DOES NOT BOUNCE ─────────────────────────────────────
/// Overshoot reads as *momentum*, and momentum has to have come from somewhere.
/// A sheet you threw should bounce; a panel that appeared because a number
/// arrived from the database should not. Critically damped (1.0) is therefore
/// the default and `flick` is the exception, taken only where a finger supplied
/// the energy.
///
/// The values are Apple's shipped ones, from *Designing Fluid Interfaces*:
/// reposition 1.0/0.4, rotation 0.8/0.4, drawer 0.8/0.3.
public enum OnyxMotion {

    /// Anything that moves because state changed. No overshoot.
    public static let move = Animation.spring(response: 0.4, dampingFraction: 1.0)

    /// Anything a finger threw. A little overshoot, because the hand put it there.
    public static let flick = Animation.spring(response: 0.4, dampingFraction: 0.8)

    /// Sheets and drawers — snappier and slightly springy.
    public static let drawer = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// Press feedback. Not a spring: it must be over before you notice it, and
    /// a spring's settle time is exactly what you would notice.
    public static let press = Animation.easeOut(duration: 0.1)

    /// A state appearing or leaving with no gesture behind it — the sync
    /// hairline, a chip swapping. §3.4 already names 200 ms cross-fade as what
    /// Reduce Motion falls back to; a thing that only fades may as well use it
    /// always, and then there is no motion value spelled outside this file.
    public static let fade = Animation.easeInOut(duration: 0.2)

    /// A value counting up because a set was logged. Slower than `move` on
    /// purpose — the eye should be able to follow the number changing, which is
    /// the only reason to animate a number at all.
    public static let counter = Animation.spring(response: 0.55, dampingFraction: 1.0)
}

// MARK: - Press

/// Scale-on-press, applied the instant the finger lands.
///
/// The rule from *Designing Fluid Interfaces*: respond on touch-DOWN, never on
/// release. `ButtonStyle` gets `configuration.isPressed`, which is the down
/// event — `.onTapGesture` does not, which is why nothing here uses one.
public struct OnyxPressStyle: ButtonStyle {
    public var scale: CGFloat = 0.96
    /// Brighten the surface a touch while pressed — for a large surface (a
    /// dashboard tile) where a 3 % shrink alone is easy to miss under a thumb.
    public var highlight: Bool = false

    public init(scale: CGFloat = 0.96, highlight: Bool = false) {
        self.scale = scale
        self.highlight = highlight
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(highlight && configuration.isPressed ? 0.06 : 0)
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(OnyxMotion.press, value: configuration.isPressed)
            // The whole frame stays hittable while it shrinks; without this a
            // press near the edge can slip out of the shrunken shape and cancel
            // itself, which reads as an unreliable button.
            .contentShape(Rectangle())
    }
}

public extension View {
    /// A tappable surface that answers immediately.
    func onyxPress(scale: CGFloat = 0.96) -> some View {
        buttonStyle(OnyxPressStyle(scale: scale))
    }
}

// MARK: - Depth

public extension View {
    /// The floating-chrome treatment: a translucent material with a bright top
    /// edge, so the surface catches light like glass rather than sitting on the
    /// page as a painted rectangle.
    ///
    /// Content scrolls UNDER this, which is the whole point — an opaque bar
    /// consumes a fixed strip of a 390 pt screen and a translucent one only
    /// borrows it.
    func onyxChrome(accent: Color) -> some View {
        background(alignment: .top) {
            ZStack(alignment: .top) {
                Rectangle().fill(.ultraThinMaterial)
                // The day's colour, bled down from the top edge. A solid accent
                // bar would compete with the set you are logging; a wash says
                // which workout this is and then gets out of the way.
                LinearGradient(
                    colors: [accent.opacity(0.22), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 96)
                Rectangle()
                    .fill(accent.opacity(0.55))
                    .frame(height: 0.75)
            }
            .ignoresSafeArea()
        }
    }
}
