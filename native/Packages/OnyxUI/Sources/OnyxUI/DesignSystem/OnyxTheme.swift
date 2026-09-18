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
///     `start[.fuel]` is the secondary, exactly as picked — two of the four
///     corners the Appearance grid's mesh swatch draws, and a knob that moved
///     them would make the swatch a lie. It is also the one place lift could not
///     work: the contrast guard clamps an accent back into 0.60…0.78 the moment
///     it leaves.
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
///
/// ── AND WHO TURNS THE KNOB NOW (W2) ──────────────────────────────────────────
/// Nobody, by hand. The two sliders are gone; the mood is a column of the
/// preset table plus whatever the current training block adds on top of it
/// (`OnyxThemeSpec.reacting(to:)`). `spec` is the sum and `base` is the pick,
/// and everything that NAMES a theme reads `base` — see the note on it.
public struct OnyxTheme: Sendable {
    /// The spec this palette was resolved from — the chosen theme AFTER the
    /// training block's offset (`OnyxThemeSpec.reacting(to:)`).
    public let spec: OnyxThemeSpec
    /// The chosen theme itself, before the phase moved it.
    ///
    /// ── WHY BOTH ───────────────────────────────────────────────────────────
    /// `spec` is what is DRAWN and `base` is what was PICKED, and from W2 they
    /// are different values on most days. Everything that answers "which theme
    /// is this" reads `base` — the Appearance grid's selection ring, Settings'
    /// theme name, and the guard in `commit()` that decides whether a write is
    /// needed. Reading `spec` for any of those would show "Custom" for the
    /// whole of a cut and re-save a phase-shifted spec back over the user's
    /// pick, which is how a preset stops being a preset after one deload.
    public let base: OnyxThemeSpec
    let start: [OnyxDomain: Color]
    let end: [OnyxDomain: Color]
    let muscle: [LandmarkMuscle: Color]

    public init(spec: OnyxThemeSpec, base: OnyxThemeSpec? = nil) {
        self.spec = spec
        self.base = base ?? spec
        // `origin` and not `base`: `base` is now a property of this type, and a
        // local of the same name reading the DEFAULT spec is one shadow away
        // from a palette rotated against the wrong zero.
        let origin = OnyxThemeSpec.default
        let dp = OKLCHConvert.hue(ofHex: spec.primary) - OKLCHConvert.hue(ofHex: origin.primary)
        let ds = OKLCHConvert.hue(ofHex: spec.secondary) - OKLCHConvert.hue(ofHex: origin.secondary)

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

    /// Where the app parks the training block the palette is currently reading
    /// itself through — `PhaseKind.rawValue`, or absent for no block at all.
    ///
    /// A SECOND key rather than a field on the stored spec, because the two
    /// have different owners and different lifetimes: `key` is what the user
    /// picked and changes when they pick again, this is what the calendar says
    /// and changes at a midnight nobody touched. Folding the phase into the
    /// stored blob would mean the plan rewriting the user's theme every time a
    /// block rolled over, and `SettingsTabView` reading "Custom" ever after.
    ///
    /// `AppEnvironment` is the only writer; the app root, the widget provider
    /// and `load` below are the readers. The watch is not one of them — it is
    /// sent the already-reacted spec (`PhoneWatchBridge`), which is why a
    /// watch build needed no change for any of this.
    public static let phaseKey = "onyx.theme.phase"

    /// The block at `phaseKey`, or nil for "no block" — which `reacting(to:)`
    /// treats as the identity.
    public static func phase(in defaults: UserDefaults) -> PhaseKind? {
        PhaseKind(rawValue: defaults.string(forKey: phaseKey) ?? "")
    }

    /// JSON at `key`, read through the block at `phaseKey` → `current`.
    /// Missing or corrupt → the default.
    @MainActor public static func load(_ defaults: UserDefaults) {
        apply(json: defaults.string(forKey: key) ?? "", phase: phase(in: defaults))
    }

    /// Persist the CHOSEN spec, then make the reacted one current.
    ///
    /// The order matters and so does which value lands where: what is written
    /// to `key` is the pick, normalised once so the stored blob and
    /// `current.base` cannot drift by a requantised LSB — never
    /// `current.spec`, which on any day inside a block is the pick plus the
    /// phase offset. Persisting that would bake a deload into the theme and
    /// then bake a second deload on top of it the next time a block rolled.
    @MainActor public static func save(_ spec: OnyxThemeSpec, to defaults: UserDefaults) {
        let base = spec.normalised()
        if let data = try? JSONEncoder().encode(base), let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: key)
        }
        set(base, phase: phase(in: defaults))
    }

    /// `load` from a string — what an `@AppStorage` observer hands over. Empty
    /// or unreadable → the default.
    @MainActor public static func apply(json: String, phase: PhaseKind? = nil) {
        set((try? JSONDecoder().decode(OnyxThemeSpec.self, from: Data(json.utf8))) ?? .default, phase: phase)
    }

    /// The one writer — the app root and the watch call it with a spec in
    /// hand. Normalises first — a hand-edited or corrupt defaults blob must
    /// not render unreadable text — and is idempotent, so a redundant `load`
    /// on every foreground is free.
    ///
    /// Idempotence is checked on BOTH halves: two different picks can react to
    /// the same drawn palette (a deload pins chroma), and an early return that
    /// only compared `spec` would keep drawing the right colours while
    /// `current.base` still named the theme the user had just replaced.
    @MainActor public static func set(_ spec: OnyxThemeSpec, phase: PhaseKind? = nil) {
        let base = spec.normalised()
        let reacted = base.reacting(to: phase)
        guard current.base != base || current.spec != reacted else { return }
        current = OnyxTheme(spec: reacted, base: base)
    }

    /// Nine named pairs for Settings; the first is the default.
    ///
    /// Secondaries sit 120° from their primaries. Every literal is already
    /// inside the contrast guard — `OnyxThemeTests` asserts `normalised()` is
    /// the identity on each — so the source shows exactly what ships.
    ///
    /// ── HOW THESE NUMBERS WERE ARRIVED AT ───────────────────────────────────
    /// Not by eye. Each pair was SOLVED with `OKLCHConvert.hex(from:)` from a
    /// chosen (L, C, h) inside the guard box, its secondary emitted from the
    /// SAME (L, C) at h + 120°, and both round-trips checked to be
    /// `normalised()` fixed points before they were written down. The nine
    /// primaries are spread around the hue circle with a minimum separation of
    /// 35° — measured pairwise, not assumed from the list order — so no two
    /// themes read as the same theme. The tightest pair that ships is Aurora
    /// against Verdigris at 36.1°.
    ///
    /// ── AND WHY TWO OF THE FOUR NEW ONES ARE NOT THE COLOUR THEIR NAME SAYS ─
    /// W2's brief drafted Verdigris at h 169.8° (a blue-green) and Nocturne at
    /// h 286.3° (a violet). Neither hue is legal: 169.8° sits 19.9° from Aurora
    /// and 22.9° from Meridian, and 286.3° sits 11.0° from Ion and 28.9° from
    /// Vesper — and the gaps those five leave (42.8° between Aurora and
    /// Meridian, 39.9° between Ion and Vesper) are too narrow to hold a tenth
    /// hue at all. With the five kept themes fixed, the hue circle has exactly
    /// two openings left: 113.8° and 352.0°. Verdigris took the first (a green
    /// — which is what the pigment is) and Nocturne the second, which is a
    /// deep rose rather than a night violet. The names are the founder's; the
    /// spacing is the rule. Renaming Nocturne, or freeing the violet band by
    /// retiring Vesper, are both one-line changes here.
    ///
    /// ── AND WHY ION CANNOT BE DROPPED ───────────────────────────────────────
    /// It IS `OnyxThemeSpec.default`. `AppearanceView` offers "Reset to Ion",
    /// and `SettingsTabView` names the current theme by MATCHING the live
    /// `base` spec against this array — so an install that never chose a theme
    /// would read "Custom" the moment Ion left the table. It stays first.
    ///
    /// The chroma/lift column is the mood, and `OnyxThemeSpec.moodWord` is what
    /// the grid prints from it: Vesper and Nocturne are pulled deep and grey,
    /// Solstice, Aurora and Glacier are lifted, and Ion is the neutral knob,
    /// which is what makes it bit-for-bit today's palette.
    public static let presets: [(name: String, spec: OnyxThemeSpec)] = [
        ("Ion",        OnyxThemeSpec.default),
        ("Solstice",   OnyxThemeSpec(primary: 0xE5A323, secondary: 0x30C8CC, chroma: 0.94, lift:  0.03)),
        ("Meridian",   OnyxThemeSpec(primary: 0x19BCB9, secondary: 0xC18BDE, chroma: 0.86, lift:  0.00)),
        ("Aurora",     OnyxThemeSpec(primary: 0x31D96D, secondary: 0x9CB4FE, chroma: 1.00, lift:  0.05)),
        ("Vesper",     OnyxThemeSpec(primary: 0xAA72C2, secondary: 0xBA7F14, chroma: 0.72, lift: -0.04)),
        ("Ember",      OnyxThemeSpec(primary: 0xE8734A, secondary: 0x01B677, chroma: 0.90, lift: -0.02)),
        ("Glacier",    OnyxThemeSpec(primary: 0x5FB3E8, secondary: 0xE38BA8, chroma: 0.80, lift:  0.04)),
        ("Verdigris",  OnyxThemeSpec(primary: 0xA6AF4B, secondary: 0x46B2E8, chroma: 0.85, lift:  0.00)),
        ("Nocturne",   OnyxThemeSpec(primary: 0xD95D9B, secondary: 0x939718, chroma: 0.70, lift: -0.05)),
    ]
}
