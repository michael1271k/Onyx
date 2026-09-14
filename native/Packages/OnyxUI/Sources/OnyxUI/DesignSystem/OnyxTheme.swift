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

    /// The theme every static token reads.
    ///
    /// Written only from the main actor — app boot, Settings, the widget
    /// bundle's init, the watch's context receive — and read from anywhere. A
    /// torn read is one frame of the old colour, never a crash: the value is
    /// an immutable struct of dictionaries and the write is a pointer swap.
    /// `@MainActor` isolation was rejected because Sendable value types and the
    /// widget timeline builder read `Color.onyx.*` off the main actor and would
    /// stop compiling under language mode v6.
    public nonisolated(unsafe) static var current = OnyxTheme(spec: .default)

    /// The UserDefaults key. The caller passes the App Group suite so the app,
    /// the widgets and the watch bridge all read one value.
    public static let key = "onyx.theme"

    /// JSON at `key` → spec → `current`. Missing or corrupt → the default.
    public static func load(_ defaults: UserDefaults) {
        apply(json: defaults.string(forKey: key) ?? "")
    }

    /// Persist the spec and make it current.
    public static func save(_ spec: OnyxThemeSpec, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(spec), let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: key)
        }
        set(spec)
    }

    /// `load` from a string — what an `@AppStorage` observer hands over. Empty
    /// or unreadable → the default.
    public static func apply(json: String) {
        set((try? JSONDecoder().decode(OnyxThemeSpec.self, from: Data(json.utf8))) ?? .default)
    }

    /// Idempotent: the same spec is not re-resolved, so a redundant `load` on
    /// every foreground is free.
    private static func set(_ spec: OnyxThemeSpec) {
        guard current.spec != spec else { return }
        current = OnyxTheme(spec: spec)
    }

    /// Named pairs for Settings; the first is the default. Secondaries sit
    /// roughly 120° from their primaries. Each runs through `normalised()` so
    /// no preset can ship outside the contrast guard.
    public static let presets: [(name: String, spec: OnyxThemeSpec)] = [
        ("Ion",   OnyxThemeSpec.default),
        ("Ember", OnyxThemeSpec(primary: 0xE07A5F, secondary: 0x5FB0E0)),
        ("Moss",  OnyxThemeSpec(primary: 0x5FC48A, secondary: 0xC4805F)),
        ("Rose",  OnyxThemeSpec(primary: 0xE06A9A, secondary: 0x6ADBE0)),
        ("Gold",  OnyxThemeSpec(primary: 0xE3B650, secondary: 0x7A6AE0)),
        ("Sea",   OnyxThemeSpec(primary: 0x4FB6E8, secondary: 0xE8A04F)),
    ].map { (name: $0.0, spec: $0.1.normalised()) }
}
