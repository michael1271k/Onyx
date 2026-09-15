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
        for domain in OnyxDomain.allCases {
            let hex = OnyxDomain.defaultDomainHex[domain]!
            let delta = domain == .fuel ? ds : dp
            switch domain {
            case .train: start[domain] = Color(hex: spec.primary)
            case .fuel:  start[domain] = Color(hex: spec.secondary)
            default:     start[domain] = Color(hex: OKLCHConvert.rotate(hex.start, byDegrees: delta))
            }
            end[domain] = Color(hex: OKLCHConvert.rotate(hex.end, byDegrees: delta))
        }
        self.start = start
        self.end = end

        var muscle: [LandmarkMuscle: Color] = [:]
        for m in LandmarkMuscle.allCases {
            muscle[m] = Color(hex: OKLCHConvert.rotate(Color.onyx.defaultMuscleHex[m]!, byDegrees: dp))
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
    public static let presets: [(name: String, spec: OnyxThemeSpec)] = [
        ("Ion",   OnyxThemeSpec.default),
        ("Ember", OnyxThemeSpec(primary: 0xE07A5F, secondary: 0x5FB0E0)),
        ("Moss",  OnyxThemeSpec(primary: 0x5FC48A, secondary: 0xC4805F)),
        ("Rose",  OnyxThemeSpec(primary: 0xE06A9A, secondary: 0x59CBD0)),
        ("Gold",  OnyxThemeSpec(primary: 0xDDB04A, secondary: 0x7B6BE1)),
        ("Sea",   OnyxThemeSpec(primary: 0x4FB6E8, secondary: 0xE8A04F)),
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
