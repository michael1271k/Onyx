import OnyxUI
import SwiftUI

/// The watch's reading of `OnyxTokens` — the same palette, with three things
/// taken out of it.
///
/// ── TWO INK LEVELS, NOT THREE ───────────────────────────────────────────────
/// `Color.onyx.textTertiary` is `white.opacity(0.40)`, and its own docstring in
/// `OnyxTokens` admits it fails 4.5:1 by design. On a phone held at reading
/// distance that is a defensible tradeoff. On a 40 mm case, at arm's length,
/// tilted, under gym lighting, through sweat — and at 1 Hz in the always-on
/// state, where the display is dimmed further — it is not a colour, it is an
/// absence. So the watch has `primary` and `secondary` and nothing below them.
///
/// That is a simplification rather than a compromise: a screen with one number
/// on it does not have a third thing to say.
///
/// ── AND NO GLASS, NO MESH ───────────────────────────────────────────────────
/// `OnyxScreenBackground` is a 3×3 `MeshGradient` under a 40 pt blur plus a
/// blurred ellipse — a per-frame GPU composite, running during an
/// `HKWorkoutSession`, on the battery you need for the rest of the workout. Its
/// stated job is to tell you which section of the app you are in before you read
/// a word, and the watch app has one screen. `onyxGlass` has the same problem
/// from the other end: `.ultraThinMaterial` blurs what is behind it, what is
/// behind it is `Color.onyx.base`, and the result is `white.opacity(0.1)`
/// arrived at expensively.
///
/// The watch is pure black and flat fills. That is not a downgrade — pure black
/// is the one token that is MORE right here than on the phone, because the case
/// bezel is black and the app bleeds into it.
///
/// ── EVERY TOKEN IS COMPUTED (overhaul A2) ───────────────────────────────────
/// They were `static let`, which Swift evaluates ONCE, on first read — so a
/// theme the phone pushed mid-run never reached any of them, and only
/// `day(_:)`, the one function here, followed it. Each is a computed read of
/// the token table now; the app root re-ids on a theme change
/// (`WatchModel.themeKey`) so every view reads them again.
enum WatchInk {

    /// Everything you are meant to read.
    static var primary: Color { Color.onyx.textPrimary }
    /// Labels, units, and the set position. Never a number you act on.
    static var secondary: Color { Color.onyx.textSecondary }

    /// The commit colour.
    ///
    /// `Color.onyx.good` means "went the right way" in the token file and here
    /// it means "commit", which is a stretch worth naming. The alternative was
    /// `Color.onyx.day(dayKey)` — matching how the phone tints a session — but
    /// those are mid-luminance indigos and oranges, and at 40 mm against black a
    /// tick has to read as one thing from a metre away. Green on black inks at
    /// roughly 9:1 and nothing else in the app is green.
    static var commit: Color { Color.onyx.good }
    /// Ink ON the commit colour. Black, not white: the green is light.
    static var onCommit: Color { Color.onyx.base }

    static var danger: Color { Color.onyx.danger }
    static var record: Color { Color.onyx.record }

    /// The one background. See the type header.
    static var ground: Color { Color.onyx.base }

    /// The split's colour. A FUNCTION, not a `let`, for the reason the header
    /// gives about themes: a stored property freezes at first read, and the
    /// day tint has to follow whatever theme the phone last sent.
    ///
    /// ── AND IT WRAPS `dayLabel`, NOT `day` ──────────────────────────────────
    /// `Color.onyx.day` answers `textTertiary` — white at 40 % — for a key it
    /// does not recognise, which is a RING colour on the phone and rules itself
    /// out on this device: the header above spends three paragraphs on why
    /// there is no third ink level here, and 40 % on a 40 mm case in gym light
    /// "is not a colour, it is an absence". `dayLabel` is the same table with
    /// the one promise this needs — that it never answers tertiary.
    static func day(_ key: String?) -> Color { Color.onyx.dayLabel(key) }

    /// A filled control that is not the tick — the RPE rungs, the deck rows.
    /// Flat, because a material over black costs a blur pass to arrive here.
    static var fill: Color { Color.white.opacity(0.10) }
    /// The same, pressed or selected.
    static var fillActive: Color { Color.white.opacity(0.18) }
}

// MARK: - Always-on

extension View {

    /// Dim for the always-on display without hiding the thing being read.
    ///
    /// ── WHAT SURVIVES THE WRIST GOING DOWN ──────────────────────────────────
    /// At 1 Hz, dimmed, the two questions a glance asks are "how long left" and
    /// "what am I lifting". Those stay. What goes is anything that moves
    /// (an arc redrawn at 1 Hz stutters — and Reduce Motion wants it gone too,
    /// so they share one branch), anything stale (a heart rate from four minutes
    /// ago is a lie, not a reading) and any large area of accent — a full-width
    /// green tick at full brightness is both an OLED power cost and a burn-in
    /// risk over a three-minute rest.
    func dimmedWhenLuminanceReduced() -> some View {
        modifier(LuminanceDim())
    }
}

private struct LuminanceDim: ViewModifier {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    func body(content: Content) -> some View {
        content.opacity(isLuminanceReduced ? 0.76 : 1)
    }
}

// MARK: - Type

/// Watch type sizes, by role.
///
/// ── WHY THESE ARE TEXT STYLES AND NEVER `.system(size:)` ────────────────────
/// A hardcoded point size ignores the watch's own Text Size setting entirely,
/// so a 44 pt numeral stays 44 while every label around it grows — which is the
/// exact layout that clips. It is also already forbidden by this repo's token
/// discipline test on the phone, and the rule does not get weaker on a smaller
/// screen.
///
/// `OnyxType.points` is deliberately not consulted here: its table is iOS
/// metrics, and watchOS resolves the same style to a different size (and to
/// different sizes on different case sizes). It feeds tracking on the phone and
/// would simply be wrong as a budget here.
enum WatchType {
    /// The one number the screen is about.
    static let hero = Font.system(.largeTitle, design: .rounded, weight: .semibold)
    /// A headline figure on a screen that also has to hold a control.
    ///
    /// ── WHY THE SCALE GREW A STEP ───────────────────────────────────────────
    /// The rest countdown was `hero`, and on a 40 mm case `hero` plus the set
    /// line plus a navigation bar left the RPE ladder clipped in half by the
    /// fold — the one control that screen exists to offer. The step below
    /// `hero` was `value` (`.title3`), which is what the REPS are set in, so
    /// the countdown would have stopped outranking the things around it.
    ///
    /// `.title` is the system style between them, so this stays what the file
    /// promises: the roles ARE text styles, and a screen still may not spell a
    /// size.
    static let figure = Font.system(.title, design: .rounded, weight: .semibold)
    /// The second number — reps, or the rest clock's own digits.
    static let value = Font.system(.title3, design: .rounded, weight: .semibold)
    /// Movement names.
    static let name = Font.caption
    /// Units, positions, hints.
    static let label = Font.caption2
}
