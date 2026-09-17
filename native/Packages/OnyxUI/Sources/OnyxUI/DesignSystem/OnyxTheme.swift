import SwiftUI
import OnyxCore

/// The runtime theme — the whole palette, resolved ONCE from a two-hue spec.
///
/// Every `Color.onyx.*` and `OnyxDomain.*` read in the app (about 1,250 of
/// them, all static, none through the Environment) resolves through
/// `OnyxTheme.current`. A token read is a dictionary lookup; the colour maths
/// runs when the theme changes, not when a view draws.
///
/// ── THE DERIVATION RULE ──────────────────────────────────────────────────────
/// Δp = hue(primary) − hue(default primary); Δs likewise for the secondary.
/// `train.start` IS the primary and `fuel.start` IS the secondary; every other
/// default hex — train's end, fuel's end, both body and recover stops, all
/// sixteen muscles — is the DEFAULT hex rotated by Δp (Δs for fuel) at its own
/// L and C. Body and Recover therefore keep their measured offsets from Train
/// rather than round ones. Under the default spec both deltas are exactly zero,
/// `OKLCHConvert.rotate` short-circuits, and every colour is the original
/// literal, bit for bit — the tests hold that line.
///
/// ── AND WHAT THE MOOD KNOB MOVES (W3) ────────────────────────────────────────
/// `spec.chroma` and `spec.lift` run AFTER the rotation, and they do not reach
/// every colour. Three rules, each measured:
///
///   · THE TWO CHOSEN ACCENTS are untouched. `start[.train]` is the primary and
///     `start[.fuel]` is the secondary, exactly as picked — the swatch on the
///     Appearance screen draws those two hexes, and a knob that moved them would
///     make the swatch a lie. It is also the one place lift could not work: the
///     contrast guard clamps an accent back into 0.60…0.78 the moment it leaves.
///
///   · THE TWO DERIVED ACCENTS — `start[.body]` and `start[.recover]` — take the
///     knob and then go back through `OnyxThemeSpec.guarded`. They tint section
///     headers and gauges, so they carry text; the guard is what keeps them at
///     ≥ 4.5:1 on black after a −0.06 lift.
///
///   · THE FOUR ENDS take the knob and then go through `OnyxThemeSpec.floored`
///     — the L ≥ 0.60 half of the guard and nothing else. An end is allowed to
///     be deep, which is most of what "deep and muted" looks like on a screen,
///     and it is allowed to be light: `recover.end` sits at L 0.868 and the
///     full `guarded` would crush it to the 0.78 saturation ceiling. What it is
///     NOT allowed to be is illegible, because an end is not decoration —
///     `body.end` is the ink of the LEAN SOFT TISSUE numeral on two widget
///     faces. Measured, a Solar primary at chroma 1.0 and lift −0.06 put it at
///     4.46:1 before this floor existed.
///
///   · THE SIXTEEN MUSCLES take the CHROMA SCALE ONLY, never the lift. Measured,
///     the palette's own lightness ladder IS the family ramp — the five legs run
///     0.830, 0.766, 0.699, 0.636, 0.569 in even steps — and Calves already sits
///     at 4.99:1, 0.03 of L above AA. A lift either flattens the ladder (if
///     floored) or drops Calves under the floor (if not). Muting or saturating
///     the data palette is the whole mood the knob owes them.
///
/// Under chroma 1.0 / lift 0.0 `OKLCHConvert.mood` short-circuits exactly as
/// `rotate` does, so the default palette is still the original literals.
public struct OnyxTheme: Sendable {
    public let spec: OnyxThemeSpec
    let start: [OnyxDomain: Color]
    let end: [OnyxDomain: Color]
    let muscle: [LandmarkMuscle: Color]

    public init(spec: OnyxThemeSpec) {
        self.spec = spec
        let base = OnyxThemeSpec.default
        let dp = OKLCHConvert.hue(ofHex: spec.primary) - OKLCHConvert.hue(ofHex: base.primary)
        let ds = OKLCHConvert.hue(ofHex: spec.secondary) - OKLCHConvert.hue(ofHex: base.secondary)

        var start: [OnyxDomain: Color] = [:]
        var end: [OnyxDomain: Color] = [:]
        /// Rotate onto this theme's hue, then apply the mood knob.
        func moved(_ hex: UInt32, _ delta: Double, lift: Bool) -> UInt32 {
            OKLCHConvert.mood(
                OKLCHConvert.rotate(hex, byDegrees: delta),
                chroma: spec.chroma,
                lift: lift ? spec.lift : 0
            )
        }

        for domain in OnyxDomain.allCases {
            let hex = OnyxDomain.defaultDomainHex[domain]!
            let delta = domain == .fuel ? ds : dp
            switch domain {
            case .train: start[domain] = Color(hex: spec.primary)
            case .fuel:  start[domain] = Color(hex: spec.secondary)
            // A derived ACCENT: back through the contrast guard, because this
            // one tints section headers and gauges.
            default:     start[domain] = Color(hex: OnyxThemeSpec.guarded(moved(hex.start, delta, lift: true)))
            }
            end[domain] = Color(hex: OnyxThemeSpec.floored(moved(hex.end, delta, lift: true)))
        }
        self.start = start
        self.end = end

        var muscle: [LandmarkMuscle: Color] = [:]
        for m in LandmarkMuscle.allCases {
            // Chroma only. The sixteen carry their own lightness ladder and
            // Calves sits 0.03 of L above AA — see the note above the type.
            muscle[m] = Color(hex: moved(Color.onyx.defaultMuscleHex[m]!, dp, lift: false))
        }
        self.muscle = muscle
    }

    /// The ramp a domain takes under THIS theme rather than under `current`.
    ///
    /// `OnyxDomain.start` and `.end` read the global, which is the right answer
    /// for every view in the app and the wrong one for the single screen that
    /// draws a theme the user has not committed yet.
    public func ramp(_ domain: OnyxDomain) -> (start: Color, end: Color) {
        (start[domain] ?? .clear, end[domain] ?? .clear)
    }

    /// The theme every static token reads.
    ///
    /// What is guaranteed, exactly:
    ///   · outside OnyxUI every WRITE is one of the `@MainActor` entry points
    ///     `set`, `load`, `save` or `apply` — the setter is `internal(set)`, so
    ///     another module cannot assign the property, and the compiler
    ///     serialises the writes it can reach. Inside OnyxUI the setter is
    ///     internal and used only by `set` and by the tests;
    ///   · READS are unsynchronised. A view, a widget timeline builder or a
    ///     Sendable value type may read from any actor and may observe the
    ///     previous theme for up to a frame after a write. The struct is four
    ///     immutable fields, so a stale read is a stale COLOUR, never a
    ///     half-written one — Swift's exclusivity rules do not make that a
    ///     data-race-free claim, which is what `nonisolated(unsafe)` admits.
    /// `@MainActor` isolation of the property itself was rejected because the
    /// off-main-actor readers above would stop compiling under language mode
    /// v6, and a theme swap is a Settings gesture, not a hot path.
    public nonisolated(unsafe) internal(set) static var current = OnyxTheme(spec: .default)

    /// The UserDefaults key. The caller passes the App Group suite so the app,
    /// the widgets and the watch bridge all read one value.
    public static let key = "onyx.theme"

    /// JSON at `key` → spec → `current`. Missing or corrupt → the default.
    @MainActor public static func load(_ defaults: UserDefaults) {
        apply(json: defaults.string(forKey: key) ?? "")
    }

    /// Make the spec current, then persist exactly what became current — one
    /// normalisation, so the stored blob and `current.spec` cannot drift by a
    /// requantised LSB.
    @MainActor public static func save(_ spec: OnyxThemeSpec, to defaults: UserDefaults) {
        set(spec)
        if let data = try? JSONEncoder().encode(current.spec), let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: key)
        }
    }

    /// `load` from a string — what an `@AppStorage` observer hands over. Empty
    /// or unreadable → the default.
    @MainActor public static func apply(json: String) {
        set((try? JSONDecoder().decode(OnyxThemeSpec.self, from: Data(json.utf8))) ?? .default)
    }

    /// The one writer — the app root and the watch call it with a spec in
    /// hand. Normalises first — a hand-edited or corrupt defaults blob must
    /// not render unreadable text — and is idempotent, so a redundant `load`
    /// on every foreground is free.
    @MainActor public static func set(_ spec: OnyxThemeSpec) {
        let spec = spec.normalised()
        guard current.spec != spec else { return }
        current = OnyxTheme(spec: spec)
    }

    /// Named pairs for Settings; the first is the default. Secondaries sit
    /// roughly 120° from their primaries. Every literal is already inside the
    /// contrast guard — `OnyxThemeTests` asserts `normalised()` is the
    /// identity on each — so the source shows exactly what ships.
    ///
    /// ── HOW THESE NUMBERS WERE ARRIVED AT (W3) ──────────────────────────────
    /// Not by eye. Each pair was SOLVED with `OKLCHConvert.hex(from:)` from a
    /// chosen (L, C, h) inside the guard box, its secondary at h + 120°, and
    /// the round trip checked to be a `normalised()` fixed point before it was
    /// written down. The nine primaries are spread around the hue circle with a
    /// minimum separation of 35° — measured pairwise, not assumed from the list
    /// order — so no two themes read as the same theme.
    ///
    /// ── AND WHY ION CANNOT BE DROPPED ───────────────────────────────────────
    /// It IS `OnyxThemeSpec.default`. `AppearanceView` offers "Reset to Ion",
    /// and `SettingsTabView` names the current theme by MATCHING the live spec
    /// against this array — so an install that never chose a theme would read
    /// "Custom" the moment Ion left the table. It stays first.
    ///
    /// The chroma/lift column is the mood: Obsidian and Basalt are pulled deep
    /// and grey, Aurora and Halcyon are lifted and saturated, and Ion is the
    /// neutral knob, which is what makes it bit-for-bit today's palette.
    public static let presets: [(name: String, spec: OnyxThemeSpec)] = [
        ("Ion",        OnyxThemeSpec.default),
        ("Obsidian",   OnyxThemeSpec(primary: 0x3C90B8, secondary: 0xB46C8C, chroma: 0.62, lift: -0.05)),
        ("Solstice",   OnyxThemeSpec(primary: 0xE5A323, secondary: 0x30C8CC, chroma: 0.94, lift:  0.03)),
        ("Meridian",   OnyxThemeSpec(primary: 0x19BCB9, secondary: 0xC18BDE, chroma: 0.86, lift:  0.00)),
        ("Basalt",     OnyxThemeSpec(primary: 0xB58194, secondary: 0x909866, chroma: 0.66, lift: -0.03)),
        ("Aurora",     OnyxThemeSpec(primary: 0x31D96D, secondary: 0x9CB4FE, chroma: 1.00, lift:  0.05)),
        ("Terracotta", OnyxThemeSpec(primary: 0xE57255, secondary: 0x32B36E, chroma: 0.80, lift: -0.02)),
        ("Vesper",     OnyxThemeSpec(primary: 0xAA72C2, secondary: 0xBA7F14, chroma: 0.72, lift: -0.04)),
        ("Halcyon",    OnyxThemeSpec(primary: 0xAAB354, secondary: 0x51B7EB, chroma: 0.88, lift:  0.04)),
    ]
}

// MARK: - The editor's bridge

/// `Color` ↔ 8-bit sRGB hex, for the one screen that edits a theme.
///
/// It lives HERE and not beside the Appearance screen because `Color(hex:)` is
/// a spelling `TokenDisciplineTests` fails anywhere but the three token files —
/// which is the right rule and this is the one legitimate exception to it: a
/// colour picker deals in `Color` and the spec stores `UInt32`, so something has
/// to convert, once, where the palette already lives.
public extension Color {

    /// The inverse of `Color(hex:)`.
    ///
    /// ── THE TWO WAYS THIS GOES WRONG ────────────────────────────────────────
    /// `Color.Resolved` is EXTENDED-RANGE sRGB, and its `red`/`green`/`blue` are
    /// already gamma-ENCODED — `linearRed` and friends are the linear ones, and
    /// quantising those instead turns Ion (`0x6B78F0`) into `0x2530DE`: not a
    /// subtle shift, a different, darker colour. So: the encoded components,
    /// clamped before the multiply (the system picker's wheel can hand back a
    /// Display P3 colour whose sRGB components fall outside 0…1), and ROUNDED
    /// rather than truncated — measured, truncation loses 63 of the 256 levels
    /// to a one-LSB error after a round trip, which is a swatch that refuses to
    /// settle on the colour you picked. Same order as `OKLCHConvert.hex(from:)`.
    var onyxHex: UInt32 {
        let c = resolve(in: EnvironmentValues())
        func level(_ v: Float) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return (level(c.red) << 16) | (level(c.green) << 8) | level(c.blue)
    }
}

public extension OnyxTheme {

    /// The binding a `ColorPicker` takes, over a hex the caller owns.
    ///
    /// The picker writes on EVERY frame of a drag (UIKit's
    /// `didSelect:continuously:`) and SwiftUI surfaces no end-of-edit signal, so
    /// what this is bound to must be a draft — never the store. Persisting per
    /// frame would re-id the app root (`OnyxApp.swift`) sixty times a second and
    /// tear down the very view presenting the picker.
    static func picked(_ hex: Binding<UInt32>) -> Binding<Color> {
        Binding(get: { Color(hex: hex.wrappedValue) }, set: { hex.wrappedValue = $0.onyxHex })
    }

    /// The two stops a preset swatch draws — the accents themselves, not the
    /// ramp they generate, because those are what the picker below edits.
    static func swatch(_ spec: OnyxThemeSpec) -> (primary: Color, secondary: Color) {
        (Color(hex: spec.primary), Color(hex: spec.secondary))
    }
}
