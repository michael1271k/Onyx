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
/// Δp = hue(primary) − hue(ORIGIN primary); Δs likewise for the secondary.
/// `train.start` IS the primary and `fuel.start` IS the secondary; every other
/// domain stop — train's end, fuel's end, both body and recover stops — is the
/// origin hex rotated by Δp (Δs for fuel) at its own L and C. Body and Recover
/// therefore keep their measured offsets from Train rather than round ones.
/// Under `OnyxThemeSpec.origin` both deltas are exactly zero, `rotate`
/// short-circuits, and every stop is the original literal, bit for bit — the
/// tests hold that line. What the theme does NOT drive is `OnyxInk.Fixed`.
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
///   · THE SIXTEEN MUSCLES are not themed at all (overhaul W0, decision Q18).
///     They are the fixed anatomical palette in `Color.onyx.defaultMuscleHex`,
///     so Chest is one coral in every theme and a legend learned once holds.
///     Until 8.0.0 they rotated with the primary and took the chroma knob.
///
///   · THE NUTRITION INKS (protein, carbs, fat, calories, micros) move by a
///     FRACTION of the theme's hue shift — `OnyxThemeSpec.weighted`, weight
///     `nutritionWeight`, chroma ≤ `nutritionMaxChroma`, lightness kept
///     (decision Q19). They read from the DEFAULT theme's own nutrition hexes,
///     not from this theme's domain ramps, so the trio is recognisable in all
///     eight and ignores the phase offset.
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
    /// The five nutrition inks under this theme — see `Nutrition`.
    let nutrition: Nutrition
    /// The ground's two hues per domain ("" = neutral) — see `groundHex`.
    let ground: [String: (primary: UInt32, secondary: UInt32)]

    /// Protein, carbs, fat and micros; calories wear carbs (Atwater sum).
    struct Nutrition: Sendable {
        let protein: Color
        let carbs: Color
        let fat: Color
        let micro: Color
    }

    /// This theme's protein ink — for a preview that draws a theme that is
    /// not (yet) the current one (Appearance's live strip, B3).
    public var proteinInk: Color { nutrition.protein }

    public init(spec: OnyxThemeSpec, base: OnyxThemeSpec? = nil) {
        self.spec = spec
        self.base = base ?? spec
        let hexes = Self.derive(spec)
        start = hexes.start.mapValues { Color(hex: $0) }
        end = hexes.end.mapValues { Color(hex: $0) }
        ground = Self.groundTable(spec, hexes.start)

        let w = OnyxThemeSpec.nutritionWeight
        let origin = Self.defaultNutritionHex
        nutrition = Nutrition(
            protein: Color(hex: spec.weighted(origin.protein, weight: w)),
            carbs: Color(hex: spec.weighted(weight: w).secondary),
            fat: Color(hex: spec.weighted(origin.fat, weight: w)),
            micro: Color(hex: spec.weighted(origin.micro, weight: w))
        )
    }

    /// The eight domain stops as hexes — the derivation itself, separate from
    /// the `Color`s so the default theme's nutrition hexes can be read from it.
    ///
    /// Rotates against `OnyxThemeSpec.origin` (Ion/Solar, where the default
    /// hexes were measured), never against `.default` (Slate, the preset a
    /// fresh install picks) — see the note on `.default`.
    static func derive(_ spec: OnyxThemeSpec) -> (start: [OnyxDomain: UInt32], end: [OnyxDomain: UInt32]) {
        let origin = OnyxThemeSpec.origin
        let dp = OKLCHConvert.hue(ofHex: spec.primary) - OKLCHConvert.hue(ofHex: origin.primary)
        let ds = OKLCHConvert.hue(ofHex: spec.secondary) - OKLCHConvert.hue(ofHex: origin.secondary)

        var start: [OnyxDomain: UInt32] = [:]
        var end: [OnyxDomain: UInt32] = [:]
        /// Rotate onto this theme's hue, then apply the mood knob.
        func moved(_ hex: UInt32, _ delta: Double) -> UInt32 {
            OKLCHConvert.mood(OKLCHConvert.rotate(hex, byDegrees: delta), chroma: spec.chroma, lift: spec.lift)
        }

        for domain in OnyxDomain.allCases {
            let hex = OnyxDomain.defaultDomainHex[domain]!
            let delta = domain == .fuel ? ds : dp
            switch domain {
            case .train: start[domain] = spec.primary
            case .fuel:  start[domain] = spec.secondary
            // A derived ACCENT: back through the contrast guard, because this
            // one tints section headers and gauges.
            default:     start[domain] = OnyxThemeSpec.guarded(moved(hex.start, delta))
            }
            end[domain] = OnyxThemeSpec.floored(moved(hex.end, delta))
        }
        return (start, end)
    }

    /// The nutrition inks as the DEFAULT theme draws them — the fixed point
    /// every other theme moves a fraction away from. Protein is Slate's
    /// `fuel.end` and fat Slate's `recover.start`, exactly the stops they were
    /// under 8.0.0's derivation; carbs/calories are Slate's secondary (read via
    /// `weighted(weight:)`). Micros had no ink of their own before W0 —
    /// `NutrientsView` borrowed good/danger/fuel — so theirs is the one new
    /// hex: a muted orchid (L 0.73, C 0.11, h 348), clear of coral protein,
    /// the abs-core magenta and the fixed water blue.
    static let defaultNutritionHex: (protein: UInt32, fat: UInt32, micro: UInt32) = {
        let slate = derive(.default)
        return (slate.end[.fuel]!, slate.start[.recover]!, 0xD98BB3)
    }()

    // MARK: - The ground's light (Precision B3, decision Q20 · design 7)

    /// The accent radial's opacity at its centre (top-left, off screen).
    ///
    /// ── 14 %, NOT THE BRIEF'S 6 % (shot round 1) ────────────────────────────
    /// Decision Q20 wrote "accent 6 % + secondary 3 %". Measured on the
    /// simulator, 6 % composites to sRGB (7, 7, 9) at the ground's brightest
    /// on-screen point — indistinguishable from the black it was meant to
    /// replace, which was the whole complaint ("the background is flat
    /// black"). The ratio (2 : 1), the centres, the radii and the chroma
    /// clamp are the brief's; only the peaks moved, and the contrast line
    /// the brief set (L ≤ 0.35, `textSecondary` ≥ 4.5 : 1, all eight stones)
    /// still holds at these values (`TokenDisciplineTests`).
    public static let groundPeak = 0.14
    /// The secondary radial's opacity at its centre (bottom-right, off screen).
    public static let groundSecondaryPeak = 0.07
    /// The chroma ceiling on both ground hues: a tint of the stone, never neon.
    static let groundMaxChroma = 0.10

    /// The two hues the ground is lit with under THIS theme, as hexes: the
    /// domain's own accent and the theme's secondary (the accent, on the fuel
    /// tab, whose accent IS the secondary), each with its chroma clamped to
    /// `groundMaxChroma`. Nil domain = the theme's own pair (Settings).
    ///
    /// Hexes, not `Color`s, so a test can composite them over black and hold
    /// the contrast line (`TokenDisciplineTests`).
    func groundHex(_ domain: OnyxDomain?) -> (primary: UInt32, secondary: UInt32) {
        ground[domain?.rawValue ?? ""] ?? (spec.primary, spec.secondary)
    }

    /// `groundHex` for every domain and the neutral ground, made once per
    /// theme in `init` — a token read is a lookup, and `OnyxGround` asks on
    /// every body pass (review).
    static func groundTable(_ spec: OnyxThemeSpec, _ start: [OnyxDomain: UInt32]) -> [String: (primary: UInt32, secondary: UInt32)] {
        var out: [String: (primary: UInt32, secondary: UInt32)] = [
            "": (clampedForGround(spec.primary), clampedForGround(spec.secondary))
        ]
        for domain in OnyxDomain.allCases {
            let accent = start[domain] ?? spec.primary
            let secondary = domain == .fuel ? spec.primary : spec.secondary
            out[domain.rawValue] = (clampedForGround(accent), clampedForGround(secondary))
        }
        return out
    }

    static func clampedForGround(_ hex: UInt32) -> UInt32 {
        let c = OKLCHConvert.oklch(fromHex: hex)
        guard c.c > groundMaxChroma else { return hex }
        return OKLCHConvert.hex(from: OKLCH(l: c.l, c: groundMaxChroma, h: c.h))
    }

    /// `groundHex` as the two colours the ground paints, at their peaks
    /// (`groundPeak`, `groundSecondaryPeak`).
    public func groundWash(_ domain: OnyxDomain?) -> (primary: Color, secondary: Color) {
        let hex = groundHex(domain)
        return (Color(hex: hex.primary).opacity(Self.groundPeak),
                Color(hex: hex.secondary).opacity(Self.groundSecondaryPeak))
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
    ///
    /// A blob from before the Stone presets is migrated here, ONCE: the
    /// nearest preset is drawn and written back, so the next read finds a
    /// preset and the migration is a no-op from then on.
    @MainActor public static func load(_ defaults: UserDefaults) {
        let json = defaults.string(forKey: key) ?? ""
        if let stored = decode(json), migrateLegacy(stored) != stored {
            save(migrateLegacy(stored), to: defaults)
            return
        }
        apply(json: json, phase: phase(in: defaults))
    }

    /// A stored spec whose primary is not one of the eight presets' → the
    /// preset whose primary hue is nearest (shortest way round). A current
    /// preset passes through untouched, whatever its knob.
    ///
    /// Why snap at all: 8.0.0 shipped nine presets (Ion … Nocturne) and no
    /// custom picker, so every stored blob IS one of those nine — and none of
    /// them is a Stone preset. Left alone they would draw a theme the grid
    /// cannot select and Settings would name "Custom". Ion → Slate, Ember →
    /// Clay, Solstice → Ochre, Meridian → Lagoon, Aurora → Sage, Vesper →
    /// Iris, Glacier → Lagoon, Verdigris → Moss, Nocturne → Rosewood.
    public static func migrateLegacy(_ spec: OnyxThemeSpec) -> OnyxThemeSpec {
        if presets.contains(where: { $0.spec.primary == spec.primary }) { return spec }
        let hue = OKLCHConvert.hue(ofHex: spec.primary)
        func distance(_ other: OnyxThemeSpec) -> Double {
            let d = abs(hue - OKLCHConvert.hue(ofHex: other.primary)).truncatingRemainder(dividingBy: 360)
            return min(d, 360 - d)
        }
        return presets.min { distance($0.spec) < distance($1.spec) }!.spec
    }

    private static func decode(_ json: String) -> OnyxThemeSpec? {
        try? JSONDecoder().decode(OnyxThemeSpec.self, from: Data(json.utf8))
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
    /// or unreadable → the default. A legacy blob is DRAWN migrated here (the
    /// app root calls this before `load` ever runs) but only `load` writes the
    /// migration back.
    @MainActor public static func apply(json: String, phase: PhaseKind? = nil) {
        set(decode(json).map(migrateLegacy) ?? .default, phase: phase)
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

    /// The eight Stone presets (overhaul W0, decision Q17), in the Appearance
    /// grid's order: row 1 Slate · Lagoon · Sage · Iris, row 2 Clay · Ochre ·
    /// Moss · Rosewood. Slate is `OnyxThemeSpec.default` and stays first —
    /// `SettingsTabView` names a theme by matching `base` against this table.
    ///
    /// Every literal is its own `normalised()` value (`OnyxThemeTests`), so the
    /// source shows exactly what ships. Muted, low-chroma primaries (OKLCH C
    /// 0.06–0.10) on a uniform knob — chroma 0.90, lift 0 — so every preset's
    /// mood word is "Even"; the mood lives in the hue now, not in the knob.
    ///
    /// ── WHAT THE GUARD FORCED, MEASURED ────────────────────────────────────
    /// The founder's draft hexes stand except three primaries that sat under
    /// the guard's L 0.60 floor and one hue that broke the 35° rule:
    ///   · Slate    6479A8 (L 0.579) → 6A7FAF, L lifted to 0.60, hue kept;
    ///   · Rosewood A66280 (L 0.581) → AC6886, L lifted to 0.60, hue kept;
    ///   · Iris     7D6BA6 (L 0.569, h 297.5) → 8A73AE, L 0.60 AND h 301.6 —
    ///     the draft sat 32.0° from Slate; +4° clears 35° (35.7°) and still
    ///     leaves 50.8° to Rosewood.
    /// Every secondary was already inside the box. The tightest pair that
    /// ships is Slate/Iris at 35.7°.
    public static let presets: [(name: String, spec: OnyxThemeSpec)] = [
        ("Slate",    OnyxThemeSpec.default),
        ("Lagoon",   OnyxThemeSpec(primary: 0x4F8FA0, secondary: 0xC98A6B, chroma: 0.90, lift: 0)),
        ("Sage",     OnyxThemeSpec(primary: 0x6E9A80, secondary: 0xC9A05C, chroma: 0.90, lift: 0)),
        ("Iris",     OnyxThemeSpec(primary: 0x8A73AE, secondary: 0xC4986E, chroma: 0.90, lift: 0)),
        ("Clay",     OnyxThemeSpec(primary: 0xB5705A, secondary: 0x6E9A9A, chroma: 0.90, lift: 0)),
        ("Ochre",    OnyxThemeSpec(primary: 0xB39250, secondary: 0x6A83A8, chroma: 0.90, lift: 0)),
        ("Moss",     OnyxThemeSpec(primary: 0x7F8F4E, secondary: 0xA87A8F, chroma: 0.90, lift: 0)),
        ("Rosewood", OnyxThemeSpec(primary: 0xAC6886, secondary: 0x7A9A8A, chroma: 0.90, lift: 0)),
    ]
}
