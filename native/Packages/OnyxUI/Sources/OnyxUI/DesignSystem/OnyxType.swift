import SwiftUI

/// Onyx — the type scale. Six roles, and `Features/` may not spell a size.
///
/// ── WHY THE SIZES ARE APPLE'S AND NOT OURS ──────────────────────────────────
/// v1 was a transliteration of the web app's `clamp()` scale: 11.6, 13.3, 15.1,
/// 17.5, 20.7, 28.2, 36.5 — seven sizes evaluated at a 390 pt viewport and then
/// frozen. Every one of them lands a fraction off a system text style, which is
/// why the screens read as a web page in SF: the app's 15.1 pt secondary line
/// sits beside a system `Section` header at 13 and a navigation title at 17, and
/// nothing aligns to anything.
///
/// The six roles below ARE system text styles — `.title` is 28, `.title3` is 20,
/// `.body` is 17, `.subheadline` is 15, `.footnote` is 13, `.caption2` is 11 —
/// so the sizes in §3.3 are not a scale we invented that happens to look Apple,
/// they are the scale, named for what each one is for. Naming them is what makes
/// the rule enforceable; using the system styles is what makes Dynamic Type,
/// optical sizing and the system's own tracking tables come for free. There is
///
/// The only frozen number left is the TRACKING, and `@ScaledMetric` scales that
/// against the role's own style so an `em` stays an `em` at every text setting.
///
/// ── NOTHING BELOW 11 ────────────────────────────────────────────────────────
/// `micro` is the floor, and it is for LABELS — a unit, a register caption, an
/// axis tick. Never a value. A widget face may go to 9 pt because WidgetKit does
/// not scale and a Lock Screen accessory is 40 pt tall; that is `OnyxWidgetType`
/// and it does not exist inside the app.
///
/// ── TRACKING IS SIZE-SPECIFIC, WHICH IS THE WHOLE POINT ─────────────────────
/// Letterforms read further apart as they grow, so display text takes NEGATIVE
/// tracking and small text takes a little positive. One fixed value across a
/// scale is wrong at both ends. Stored in `em` and multiplied by the SCALED
/// size, so it stays proportional when the user turns text up.
public enum OnyxType: CaseIterable, Sendable {
    /// A RUNNING clock, and only that: the live logger's elapsed timer.
    ///
    /// ── WHY THE SCALE GREW A SEVENTH ROLE RATHER THAN THE FEATURE A SIZE ────
    /// The logger's timer is read at arm's length, across a gym floor, by
    /// someone deciding whether to start the next set — the one figure in this
    /// app whose viewing distance is not the phone's. `hero` at 28 is what every
    /// other screen's headline number is, and a timer set in it disappears into
    /// the split name beside it. `.largeTitle` is 34 and is the one system style
    /// above `.title`, so this stays what the file promises: the roles ARE
    /// system text styles, and a feature still may not spell a size.
    case clock
    /// The one figure a screen is about: a readiness score, the day's kcal.
    /// At most one per screen — a second hero is two screens in a trench coat.
    case hero
    /// A card's own title, a sheet's heading, a split name.
    case display
    /// Prose, list rows, and every value that is not the hero.
    case body
    /// The line under a value: a target, a previous set, a meta line.
    case secondary
    /// A section caption, a unit suffix, a chart's axis label.
    case caption
    /// A register label — uppercase, tracked out, never carrying a number.
    case micro

    /// The system style this role IS. Not "scales against" — is.
    public var textStyle: Font.TextStyle {
        switch self {
        case .clock:     .largeTitle  // 34
        case .hero:      .title       // 28
        case .display:   .title3      // 20
        case .body:      .body        // 17
        case .secondary: .subheadline // 15
        case .caption:   .footnote    // 13
        case .micro:     .caption2    // 11
        }
    }

    /// Size at the default Dynamic Type setting. Documentation and the token
    /// record; the rendering never reads it.
    public var points: CGFloat {
        switch self {
        case .clock: 34
        case .hero: 28
        case .display: 20
        case .body: 17
        case .secondary: 15
        case .caption: 13
        case .micro: 11
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .hero:      .bold
        // Semibold rather than bold at 34: the mass a weight adds is what makes
        // a figure loud, and at this size the size is already the loudness.
        case .clock:     .semibold
        case .display:   .semibold
        case .micro:     .semibold
        case .body, .secondary, .caption: .regular
        }
    }

    /// Rounded only for the figures — the hero and the clock — which take the
    /// same shape language as `onyxNumeral()`. Prose in a rounded face reads as
    /// a children's app.
    public var design: Font.Design {
        switch self {
        case .hero, .clock: .rounded
        default: .default
        }
    }

    /// CSS `letter-spacing`, in `em`. Negative as the type grows, positive at
    /// the floor — `micro` is set in caps, and caps at 11 pt close their counters
    /// up into a block unless they are opened out. 0.10 em is 1.1 pt, which is
    /// what the register captions it replaces were tracked to by hand.
    public var trackingEm: CGFloat {
        switch self {
        case .clock:   -0.03
        case .hero:    -0.02
        case .display: -0.01
        case .micro:    0.10
        case .body, .secondary, .caption: 0
        }
    }

    public var font: Font {
        Font.system(textStyle, design: design).weight(weight)
    }
}

private struct OnyxTypeModifier: ViewModifier {
    let role: OnyxType
    /// An `em` that overrides the role's own. For the wordmark, which is a piece
    /// of brand rather than a piece of the scale.
    let trackingEm: CGFloat?

    /// The role's own point size, as the user's text setting renders it. Only
    /// the TRACKING needs it — the font comes from the text style — but tracking
    /// is an `em` and an `em` of a size nobody measured is a guess.
    @ScaledMetric private var size: CGFloat

    init(role: OnyxType, trackingEm: CGFloat?) {
        self.role = role
        self.trackingEm = trackingEm
        _size = ScaledMetric(wrappedValue: role.points, relativeTo: role.textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(role.font)
            .tracking(size * (trackingEm ?? role.trackingEm))
    }
}

public extension View {
    /// Apply an Onyx type role.
    func onyxType(_ role: OnyxType, tracking trackingEm: CGFloat? = nil) -> some View {
        modifier(OnyxTypeModifier(role: role, trackingEm: trackingEm))
    }

    /// Every number in the app.
    ///
    /// ── THREE THINGS THAT ONLY WORK TOGETHER ────────────────────────────────
    /// `.monospacedDigit()` stops neighbours shuffling as a value changes;
    /// `.rounded` matches the numerals to the shape language of the tiles;
    /// `.contentTransition(.numericText())` animates a digit rolling rather than
    /// cross-fading, which is the difference between a number that CHANGED and
    /// a number that was replaced. Numbers are the product here — they get the
    /// same care the copy does.
    func onyxNumeral() -> some View {
        self.fontDesign(.rounded)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    /// The hero figure. `onyxType(.hero)` plus numeral treatment, because the
    /// hero is always a number.
    func onyxHero() -> some View {
        onyxType(.hero).monospacedDigit().contentTransition(.numericText())
    }

    /// A running clock. Monospaced so the digits do not shuffle the layout once
    /// a second, and WITHOUT `contentTransition(.numericText())` — that animates
    /// a digit rolling, which is right for a total that changed because you did
    /// something and wrong for a second hand.
    func onyxClock() -> some View {
        onyxType(.clock).monospacedDigit()
    }

    /// A card or sheet title.
    func onyxDisplay() -> some View { onyxType(.display) }

    /// A section caption or a unit suffix, in secondary ink.
    func onyxCaption() -> some View {
        onyxType(.caption).foregroundStyle(Color.onyx.textSecondary)
    }

    /// A register label: uppercase, tracked out. The case is part of the role —
    /// a register caption in sentence case is just small body text.
    ///
    /// Secondary ink by default since 9.0.0 (W6 polish): a register label
    /// ("SCORE", "THIS WEEK") is the only copy of what the figure under it
    /// means, and tertiary (40 %) fails 4.5:1 on the slab by design — it is for
    /// unit suffixes only. The ink is a PARAMETER because a `.foregroundStyle`
    /// chained after this call never won: the inner style is the one SwiftUI
    /// draws, so eight "accent" labels had been rendering tertiary.
    func onyxMicro(_ ink: Color = Color.onyx.textSecondary) -> some View {
        onyxType(.micro)
            .textCase(.uppercase)
            .foregroundStyle(ink)
    }
}
