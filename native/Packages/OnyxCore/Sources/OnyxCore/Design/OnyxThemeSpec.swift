import Foundation

/// A theme is two hues and a mood. Everything else the app colours is derived
/// from those by `OnyxTheme` in OnyxUI, which keeps each other stop at its
/// measured offset from the one it follows.
///
/// Two `UInt32`s rather than two `Color`s so the value is Codable, comparable
/// and readable from OnyxCore, where no view framework is allowed.
///
/// ── WHY TWO HUES WERE NOT ENOUGH (W3) ───────────────────────────────────────
/// Until this wave the spec was the two hexes alone, and `OnyxTheme` derived
/// the whole palette by HUE ROTATION only: lightness and chroma stayed pinned
/// to the default literals, so every theme was Ion turned. `chroma` and `lift`
/// are the second axis — the same hues, read deep and muted or bright and
/// vivid. See `OnyxTheme.init(spec:)` for exactly which colours they move and,
/// more importantly, which ones they must not.
public struct OnyxThemeSpec: Codable, Equatable, Sendable {
    /// The train accent — Ion, `0x6B78F0`, by default.
    public var primary: UInt32
    /// The fuel accent — Solar, `0xE3A650`, by default.
    public var secondary: UInt32
    /// A SCALE on every derived colour's chroma, 0.6…1.0. Down only — see the
    /// contrast note below.
    public var chroma: Double
    /// An OFFSET on every derived STOP's lightness, −0.06…+0.06.
    public var lift: Double

    public init(primary: UInt32, secondary: UInt32, chroma: Double = 1, lift: Double = 0) {
        self.primary = primary
        self.secondary = secondary
        self.chroma = chroma
        self.lift = lift
    }

    /// ── THE DECODE THAT WOULD HAVE EATEN EVERY STORED THEME ─────────────────
    /// Swift's SYNTHESIZED `Decodable` requires a key for every non-Optional
    /// property; a default value on the property does not save it. Every
    /// install made before this wave holds `{"primary":…,"secondary":…}` at
    /// `OnyxTheme.key`, and `OnyxTheme.apply(json:)` falls back to `.default`
    /// on ANY decode failure — silently. Adding two stored properties with the
    /// synthesized conformance would therefore have reset every themed install
    /// to Ion on first launch, with no error and nothing to notice.
    ///
    /// So the decode is written out, `decodeIfPresent` on the two new keys,
    /// and an old two-key blob decodes to the neutral knob. `OnyxThemeTests`
    /// holds that line with the literal old JSON.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primary = try c.decode(UInt32.self, forKey: .primary)
        secondary = try c.decode(UInt32.self, forKey: .secondary)
        chroma = try c.decodeIfPresent(Double.self, forKey: .chroma) ?? 1
        lift = try c.decodeIfPresent(Double.self, forKey: .lift) ?? 0
    }

    public static let `default` = OnyxThemeSpec(primary: 0x6B78F0, secondary: 0xE3A650)

    /// The contrast guard.
    ///
    /// L ≥ 0.60 keeps an accent at ≥ 4.5:1 as foreground on black — measured
    /// across the hue circle at C = 0.20, the worst case is 4.77:1 at h ≈ 350°,
    /// against the muscle palette's own floor of 4.99:1 at Calves. Since the
    /// ratio is symmetric, that is also BLACK text on a filled accent.
    ///
    /// ── WHAT THE CEILING IS NOT (W5) ────────────────────────────────────────
    /// This comment used to say L ≤ 0.78 "keeps white text legible on a ramp
    /// button". Measured, that is false everywhere in the box and no ceiling
    /// can make it true: white on an accent runs 1.86:1 to 2.19:1 at L = 0.78
    /// and peaks at 4.40:1 at the floor — under AA at both ends. The two
    /// requirements are arithmetically incompatible (black needs Y ≥ 0.175,
    /// white needs Y ≤ 0.183, and the hue spread at C = 0.20 is five times
    /// wider than that window), so a filled control takes `Color.onyx.base` for
    /// its label, as `OnyxChipRow.face` already does. L ≤ 0.78 is a SATURATION
    /// bound: it stops a chosen hue washing out toward `textPrimary`, which at
    /// the ceiling is only 1.5–1.8:1 away.
    ///
    /// C ≤ 0.20 keeps a chosen hue in the same register as the sixteen data
    /// colours rather than shouting over them — though sRGB does most of that
    /// clamping itself: only 9 of 24 hues can even hold C = 0.20 at L = 0.60.
    /// A hue already inside the box passes through with its bits untouched.
    ///
    /// ── AND WHY THE MOOD KNOB CANNOT BREAK IT (W3) ──────────────────────────
    /// `lift` is NOT applied to the two chosen accents. It could not be: a
    /// negative lift on an accent already at the floor is clamped straight back
    /// here and does nothing, and a positive one would be capped at the ceiling
    /// — the knob would read as dead on exactly the themes it was added for. It
    /// moves the DERIVED colours instead, and every one of those that can carry
    /// text is put back inside a guard afterwards: the two derived accents
    /// through `guarded`, the four ramp ends through `floored`. `chroma` only
    /// ever scales DOWN, and lowering chroma at fixed L moves a colour toward
    /// the neutral of that lightness, which on black is 5.3:1 — above the
    /// floor, not below it.
    ///
    /// ── THE ENDS ARE NOT DECORATION, AND THAT WAS MEASURED THE HARD WAY ─────
    /// This comment claimed for one draft of W3 that the four ramp ENDS could
    /// skip the guard because "they are gradient stops". They are not:
    /// `OnyxDomain.body.end` is the ink of the LEAN SOFT TISSUE numeral on two
    /// widget faces (`OnyxComposition`, `OnyxLifestyle`), a 12–14 pt figure on
    /// black. Swept over the full hue circle, a primary of `0xE3A650` — the
    /// app's own Solar accent, and a legal pick — at chroma 1.0 and lift −0.06
    /// put `body.end` at `#A65E71`, **4.46:1**, under AA. The same hue at lift
    /// 0 is 5.73:1, so the lift was the whole cause. Hence `floored`.
    public func normalised() -> OnyxThemeSpec {
        OnyxThemeSpec(
            primary: Self.guarded(primary),
            secondary: Self.guarded(secondary),
            chroma: Self.bounded(chroma, Self.chromaScale, fallback: 1),
            lift: Self.bounded(lift, Self.liftOffset, fallback: 0)
        )
    }

    // MARK: - The phase offset

    /// The same theme, read the way the current training block wants it read.
    ///
    /// ── WHY A BLOCK MOVES THE PALETTE AND NOT A BADGE ───────────────────────
    /// A phase is the one fact about the app that is true for weeks at a time
    /// and true on every screen, and it was being told in one chip on one
    /// header. A mood offset says it everywhere without adding a pixel: a cut
    /// reads quieter and deeper, a bulk reads a shade brighter, and a deload
    /// drops the whole palette to one fixed low saturation — the week where
    /// nothing is supposed to shout.
    ///
    /// ── WHAT IT DELIBERATELY DOES NOT MOVE ──────────────────────────────────
    /// The two CHOSEN accents, because `OnyxTheme` holds those at the hexes the
    /// swatch draws whatever the knob says. So a phase tints the twenty-four
    /// DERIVED colours and leaves the theme recognisably itself — Ember in a
    /// deload is still Ember, muted.
    ///
    /// Pure, and through `normalised()`: an offset that walked out of
    /// `chromaScale` or `liftOffset` is clamped by the same guard a hand-edited
    /// defaults blob is, so no phase can put an ink under AA. `peak` and `nil`
    /// are the identity — a peak block is the palette as picked, and no block
    /// at all must look exactly like the app did before this existed.
    ///
    /// `deload` SETS chroma rather than offsetting it, which is why it is
    /// written unsigned: the deload mood is one fixed quiet, not a relative
    /// step, and no preset in `OnyxTheme.presets` sits below 0.70 — so it only
    /// ever lowers.
    public func reacting(to phase: PhaseKind?) -> OnyxThemeSpec {
        guard let phase else { return normalised() }
        switch phase {
        case .cut:
            return moved(chroma: chroma - 0.10, lift: lift - 0.03)
        case .bulk:
            return moved(chroma: chroma, lift: lift + 0.03)
        case .deload:
            return moved(chroma: 0.70, lift: lift)
        case .peak:
            return normalised()
        }
    }

    private func moved(chroma: Double, lift: Double) -> OnyxThemeSpec {
        OnyxThemeSpec(primary: primary, secondary: secondary, chroma: chroma, lift: lift).normalised()
    }

    /// The knob in one word — what the Appearance grid prints under a preset's
    /// name now that the two sliders are gone.
    ///
    /// Derived rather than a third column in the preset table: a word written
    /// beside the numbers is a second fact to keep true, and this one cannot
    /// disagree with the mood it names. The ladder is read top to bottom, so a
    /// theme that is both quiet and dark reads "Muted" — the saturation is the
    /// louder of the two statements.
    public var moodWord: String {
        if chroma <= 0.75 { return "Muted" }
        if lift >= 0.03 { return "Bright" }
        if lift <= -0.02 { return "Deep" }
        if chroma >= 0.95 { return "Vivid" }
        return "Even"
    }

    static let lightness = 0.60...0.78
    static let maxChroma = 0.20

    /// The mood knob's two ranges. Public so the Appearance sliders and the
    /// guard cannot disagree about what a legal value is.
    public static let chromaScale = 0.6...1.0
    public static let liftOffset = -0.06...0.06

    /// One hex, put inside the guard box above. Public because OnyxUI derives
    /// two more ACCENTS from these two — Body's and Recover's — and a derived
    /// accent that skipped the guard would carry text at whatever the mood knob
    /// left it at.
    public static func guarded(_ hex: UInt32) -> UInt32 {
        var colour = OKLCHConvert.oklch(fromHex: hex)
        guard !lightness.contains(colour.l) || colour.c > maxChroma else { return hex }
        colour.l = min(max(colour.l, lightness.lowerBound), lightness.upperBound)
        colour.c = min(colour.c, maxChroma)
        return OKLCHConvert.hex(from: colour)
    }

    /// The FLOOR on its own — L raised to 0.60, nothing else touched.
    ///
    /// For a derived colour that carries text but is allowed to be lighter than
    /// the accent ceiling: the four ramp ends, whose light end (`recover.end`
    /// at L 0.868) is meant to be light and would be crushed to 0.78 by the
    /// full `guarded`. Chroma is left alone because the knob only ever lowers
    /// it. A colour already above the floor passes through with its bits
    /// untouched, which is what keeps the default palette identical.
    public static func floored(_ hex: UInt32) -> UInt32 {
        var colour = OKLCHConvert.oklch(fromHex: hex)
        guard colour.l < lightness.lowerBound else { return hex }
        colour.l = lightness.lowerBound
        return OKLCHConvert.hex(from: colour)
    }

    /// A knob into its range, on the two-decimal grid the Appearance sliders
    /// step on.
    ///
    /// `isFinite` first: this value arrives from a JSON blob in a shared
    /// `UserDefaults` suite that is hand-editable, and a NaN survives
    /// `min`/`max` untouched — it would reach `OKLCHConvert` and come back as a
    /// black palette rather than as a clamped one.
    ///
    /// ROUNDED because `Slider(value:in:step:)` snaps to `lowerBound + n × step`
    /// in binary floating point, and the Terracotta position on the lift slider
    /// is `-0.019999999999999997`. Every preset's knob is written at two
    /// decimals, so without this a user could drag a slider onto a preset's
    /// exact value and watch its chip stay unlit — `AppearanceView` decides
    /// selection by `draft == preset.spec`, which is an exact comparison.
    static func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return (clamped * 100).rounded() / 100
    }
}
