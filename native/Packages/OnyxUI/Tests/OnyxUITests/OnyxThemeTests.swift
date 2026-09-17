import Testing
import SwiftUI
import OnyxCore
@testable import OnyxUI

/// The runtime theme. `.serialized` because three of these tests move the
/// process-wide `OnyxTheme.current` and put it back; a parallel reader of
/// `Color.onyx.*` in another suite would otherwise see a preset for a frame.
/// `@MainActor` because every writer is.
@Suite("OnyxTheme", .serialized)
@MainActor
struct OnyxThemeTests {

    @Test("the default spec reproduces every default colour, bit for bit")
    func defaultIsIdentity() {
        let theme = OnyxTheme(spec: .default)
        for d in OnyxDomain.allCases {
            let hex = OnyxDomain.defaultDomainHex[d]!
            #expect(theme.start[d] == Color(hex: hex.start), "\(d) start")
            #expect(theme.end[d] == Color(hex: hex.end), "\(d) end")
        }
        for m in LandmarkMuscle.allCases {
            #expect(theme.muscle[m] == Color(hex: Color.onyx.defaultMuscleHex[m]!), "\(m)")
        }
        // And the process boots on it.
        #expect(OnyxTheme.current.spec == .default)
        #expect(OnyxTheme.current.start == theme.start)
        #expect(OnyxTheme.current.end == theme.end)
        #expect(OnyxTheme.current.muscle == theme.muscle)
    }

    @Test("the sixteen muscles stay sixteen colours under any quarter turn")
    func musclesStayDistinct() {
        for delta in [0.0, 90, 180, 270] {
            let rotated = LandmarkMuscle.allCases.map {
                OKLCHConvert.rotate(Color.onyx.defaultMuscleHex[$0]!, byDegrees: delta)
            }
            #expect(Set(rotated).count == rotated.count, "Δ \(delta)")
        }
    }

    @Test("every preset keeps the four domain accents and the sixteen muscles apart")
    func presetsKeepDomainsApart() {
        #expect(OnyxTheme.presets.count == 9)
        #expect(OnyxTheme.presets.first?.spec == .default)
        for preset in OnyxTheme.presets {
            // Identity, not idempotence: the literals in the table ARE the
            // normalised values, so the source shows what ships.
            #expect(preset.spec.normalised() == preset.spec, "\(preset.name) literal is already in range")
            let theme = OnyxTheme(spec: preset.spec)
            let accents = OnyxDomain.allCases.map { theme.start[$0]!.description }
            #expect(Set(accents).count == accents.count, "\(preset.name)")

            // ── AND THE MUSCLES, PER PRESET ────────────────────────────────
            // `musclesStayDistinct` proves the property for four quarter
            // turns, which is a fact about the ROTATION. What ships is this
            // fixed table, and a preset whose Δp folded two muscles onto one
            // colour would draw a sixteen-row legend with fifteen hues in it
            // and pass every other test in this file.
            let muscles = LandmarkMuscle.allCases.map { theme.muscle[$0]!.description }
            #expect(muscles.count == 16, "\(preset.name): the atlas is sixteen muscles")
            #expect(Set(muscles).count == muscles.count, "\(preset.name) muscles")
        }
    }

    @Test("the six chart series stay six colours under every preset")
    func seriesStayDistinctUnderEveryPreset() {
        // `Chart kit`'s distinctness test runs in parallel with this suite and
        // may read `series` while a test here holds a preset; the property has
        // to be true under every theme, not just the default.
        defer { OnyxTheme.apply(json: "") }
        for preset in OnyxTheme.presets {
            OnyxTheme.set(preset.spec)
            let series = Color.onyx.series.map(\.description)
            #expect(series.count == 6)
            #expect(Set(series).count == series.count, "\(preset.name): \(series)")
        }
    }

    @Test("a non-default spec moves train and fuel and drags the rest with them")
    func derivation() {
        let ember = OnyxTheme.presets.first { $0.name == "Terracotta" }!.spec
        let theme = OnyxTheme(spec: ember)
        #expect(theme.start[.train] == Color(hex: ember.primary))
        #expect(theme.start[.fuel] == Color(hex: ember.secondary))
        #expect(theme.end[.train] != Color(hex: OnyxDomain.defaultDomainHex[.train]!.end))
        #expect(theme.muscle[.chest] != Color(hex: Color.onyx.defaultMuscleHex[.chest]!))
    }

    @Test("the derived statics follow a theme change instead of freezing at first read")
    func derivedStaticsFollow() {
        defer { OnyxTheme.apply(json: "") }
        OnyxTheme.apply(json: "")
        let protein = Color.onyx.protein
        let carbs = Color.onyx.carbs
        let fat = Color.onyx.fat
        let calories = Color.onyx.calories
        let series0 = Color.onyx.series[0]

        OnyxTheme.current = OnyxTheme(spec: OnyxTheme.presets.first { $0.name == "Terracotta" }!.spec)
        #expect(Color.onyx.protein != protein)
        #expect(Color.onyx.carbs != carbs)
        #expect(Color.onyx.fat != fat)
        #expect(Color.onyx.calories != calories)
        #expect(Color.onyx.series[0] != series0)
    }

    @Test("an out-of-range spec is normalised on the way in, never rendered raw")
    func appliedSpecsAreNormalised() throws {
        defer { OnyxTheme.apply(json: "") }
        let raw = OnyxThemeSpec(primary: 0x101020, secondary: 0xFF0000)
        #expect(raw.normalised() != raw)
        let json = try #require(String(data: JSONEncoder().encode(raw), encoding: .utf8))

        OnyxTheme.apply(json: json)
        #expect(OnyxTheme.current.spec == raw.normalised())

        let suite = "onyx.theme.tests.normalised"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(json, forKey: OnyxTheme.key)
        OnyxTheme.apply(json: "")
        OnyxTheme.load(defaults)
        #expect(OnyxTheme.current.spec == raw.normalised())

        OnyxTheme.apply(json: "")
        OnyxTheme.save(raw, to: defaults)
        #expect(OnyxTheme.current.spec == raw.normalised())
        let stored = try #require(defaults.string(forKey: OnyxTheme.key))
        #expect(try JSONDecoder().decode(OnyxThemeSpec.self, from: Data(stored.utf8)) == raw.normalised())
    }

    @Test("apply, load and save move the current theme; corrupt or empty means default")
    func plumbing() {
        defer { OnyxTheme.apply(json: "") }
        let ember = OnyxTheme.presets.first { $0.name == "Terracotta" }!.spec

        OnyxTheme.apply(json: "")
        #expect(OnyxTheme.current.spec == .default)
        OnyxTheme.apply(json: "{not json")
        #expect(OnyxTheme.current.spec == .default)

        let suite = "onyx.theme.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removeObject(forKey: OnyxTheme.key)

        OnyxTheme.save(ember, to: defaults)
        #expect(OnyxTheme.current.spec == ember)
        // The static tokens follow — this is the whole point.
        #expect(OnyxDomain.train.start == Color(hex: ember.primary))
        #expect(OnyxDomain.fuel.accent == Color(hex: ember.secondary))
        #expect(Color.onyx.muscle(.chest) != Color(hex: Color.onyx.defaultMuscleHex[.chest]!))
        let json = defaults.string(forKey: OnyxTheme.key)!
        #expect(json.contains("\"primary\""))

        OnyxTheme.apply(json: "")
        #expect(OnyxTheme.current.spec == .default)
        OnyxTheme.load(defaults)
        #expect(OnyxTheme.current.spec == ember)
        OnyxTheme.apply(json: json)
        #expect(OnyxTheme.current.spec == ember)

        defaults.set("garbage", forKey: OnyxTheme.key)
        OnyxTheme.load(defaults)
        #expect(OnyxTheme.current.spec == .default)
    }

    // MARK: - The mood knob (W3)

    @Test("an old two-key blob keeps its theme and lands on the neutral knob")
    func oldBlobSurvivesTheNewKeys() throws {
        defer { OnyxTheme.apply(json: "") }
        // The literal shape every install written before W3 holds at
        // `OnyxTheme.key`: two keys, no chroma, no lift. The hexes are
        // interpolated rather than written out in decimal — `UInt32` encodes as
        // a JSON number, and a hand-converted one is a digit waiting to be
        // wrong about which theme this test is even asserting.
        let old = "{\"primary\":\(0xE57255),\"secondary\":\(0x32B36E)}"
        #expect(!old.contains("chroma") && !old.contains("lift"))

        let decoded = try JSONDecoder().decode(OnyxThemeSpec.self, from: Data(old.utf8))
        #expect(decoded.primary == 0xE57255)
        #expect(decoded.secondary == 0x32B36E)
        #expect(decoded.chroma == 1)
        #expect(decoded.lift == 0)

        // And the path that actually runs on launch. `apply` swallows a decode
        // failure into `.default`, so a synthesized `Decodable` would have made
        // this assertion read Ion — silently, on every themed install.
        OnyxTheme.apply(json: old)
        #expect(OnyxTheme.current.spec.primary == 0xE57255)
        #expect(OnyxTheme.current.spec != .default)
        #expect(OnyxTheme.current.spec.chroma == 1)
        #expect(OnyxTheme.current.spec.lift == 0)
    }

    @Test("the neutral knob is today's palette; a turned one is not")
    func theKnobIsNeutralAtTheDefaultAndLiveOtherwise() {
        // Spelled out rather than relying on the memberwise default: this is
        // the property `defaultIsIdentity` depends on.
        #expect(OnyxThemeSpec.default.chroma == 1)
        #expect(OnyxThemeSpec.default.lift == 0)

        let neutral = OnyxTheme(spec: .default)
        let muted = OnyxTheme(spec: OnyxThemeSpec(primary: OnyxThemeSpec.default.primary,
                                                  secondary: OnyxThemeSpec.default.secondary,
                                                  chroma: 0.6, lift: -0.06))
        // The two CHOSEN accents do not move, by design.
        #expect(muted.start[.train] == neutral.start[.train])
        #expect(muted.start[.fuel] == neutral.start[.fuel])
        // Everything derived does — otherwise the knob is decoration.
        #expect(muted.end[.train] != neutral.end[.train])
        #expect(muted.end[.fuel] != neutral.end[.fuel])
        #expect(muted.start[.body] != neutral.start[.body])
        #expect(muted.start[.recover] != neutral.start[.recover])
        #expect(muted.muscle[.chest] != neutral.muscle[.chest])
    }

    /// Contrast of an sRGB hex against `Color.onyx.base`, which is true black.
    private func onBlack(_ hex: UInt32) -> Double {
        func lin(_ v: UInt32) -> Double {
            let c = Double(v) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let y = 0.2126 * lin((hex >> 16) & 0xFF) + 0.7152 * lin((hex >> 8) & 0xFF) + 0.0722 * lin(hex & 0xFF)
        return (y + 0.05) / 0.05
    }

    @Test("no knob puts a themed ink under AA, anywhere a user can go")
    func theKnobCannotBreakTheContrastFloor() {
        // ── WHY THIS SWEEPS THE HUE CIRCLE AND NOT THE PRESET TABLE ─────────
        // The first version of this test swept the nine presets' own hues and
        // passed with the defect in place. The failing band is 114°–160° of
        // primary rotation — warm-yellow primaries — and NO preset sits there.
        // But the Appearance screen has a `ColorPicker`, so every hue in the
        // guard box is somewhere a user can go, and the reachable worked
        // example is `0xE3A650`: the app's OWN Solar accent, on which
        // `normalised()` is the identity.
        //
        // ── AND WHY IT SWEEPS CHROMA INSTEAD OF PINNING IT ──────────────────
        // The first version also pinned `chroma: 0.6`, on the reasoning that
        // the lowest saturation was the harshest case. Measured, it is the
        // SAFEST: lowering chroma at fixed L moves a colour toward the neutral
        // of that lightness, which on black is 5.3:1. The failing column is
        // chroma 0.9–1.0.
        //
        // ── AND WHY IT READS `end` ──────────────────────────────────────────
        // `OnyxDomain.body.end` is the ink of the LEAN SOFT TISSUE numeral on
        // two widget faces and `fuel.end` is `Color.onyx.protein`. An "end" is
        // not decoration in this app, and a test that only looked at `start`
        // could not see that.
        let aa = 4.5
        var worst = (ratio: Double.infinity, what: "")
        for degrees in stride(from: 0.0, to: 360.0, by: 10) {
            // Both corners of the guard box, at the chroma ceiling.
            for lightness in [0.60, 0.78] {  // the guard box's own corners
                let primary = OKLCHConvert.hex(from: OKLCH(l: lightness, c: 0.20, h: degrees))
                let secondary = OKLCHConvert.hex(from: OKLCH(l: lightness, c: 0.20, h: (degrees + 120).truncatingRemainder(dividingBy: 360)))
                for chroma in [0.6, 0.8, 0.9, 1.0] {
                    for lift in [-0.06, -0.03, 0.0, 0.03, 0.06] {
                        let theme = OnyxTheme(spec: OnyxThemeSpec(
                            primary: primary, secondary: secondary, chroma: chroma, lift: lift
                        ).normalised())
                        for domain in OnyxDomain.allCases {
                            for (stop, hex) in [("start", theme.start[domain]!.onyxHex),
                                                ("end", theme.end[domain]!.onyxHex)] {
                                let ratio = onBlack(hex)
                                if ratio < worst.ratio {
                                    worst = (ratio, "h\(Int(degrees)) L\(lightness) c\(chroma) l\(lift) \(domain).\(stop) #\(String(hex, radix: 16))")
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(worst.ratio >= aa, "worst themed ink is \(worst.ratio):1 at \(worst.what)")
    }

    @Test("the sixteen muscles keep their lightness ladder under every knob")
    func theMusclesTakeChromaButNeverLift() {
        // The ladder IS the family ramp — five legs stepping 0.830 … 0.569 —
        // and Calves sits 0.03 of L above AA with nothing to give. A lift would
        // either flatten the ladder or drop Calves under the floor.
        for preset in OnyxTheme.presets {
            let dp = OKLCHConvert.hue(ofHex: preset.spec.primary)
                - OKLCHConvert.hue(ofHex: OnyxThemeSpec.default.primary)
            for lift in [-0.06, 0.0, 0.06] {
                let spec = OnyxThemeSpec(primary: preset.spec.primary,
                                         secondary: preset.spec.secondary,
                                         chroma: 0.6, lift: lift)
                let theme = OnyxTheme(spec: spec)
                for m in LandmarkMuscle.allCases {
                    let mine = OKLCHConvert.oklch(fromHex: theme.muscle[m]!.onyxHex).l
                    let plain = OKLCHConvert.oklch(
                        fromHex: OKLCHConvert.rotate(Color.onyx.defaultMuscleHex[m]!, byDegrees: dp)
                    ).l
                    #expect(abs(mine - plain) < 0.02, "\(preset.name) lift \(lift) \(m): \(plain) → \(mine)")
                }
            }
        }
    }

    @Test("the knob is clamped on the way in, and a corrupt one falls back")
    func knobIsBounded() {
        let wild = OnyxThemeSpec(primary: OnyxThemeSpec.default.primary,
                                 secondary: OnyxThemeSpec.default.secondary,
                                 chroma: 4, lift: 9).normalised()
        #expect(wild.chroma == 1.0)
        #expect(wild.lift == 0.06)

        let low = OnyxThemeSpec(primary: OnyxThemeSpec.default.primary,
                                secondary: OnyxThemeSpec.default.secondary,
                                chroma: -2, lift: -9).normalised()
        #expect(low.chroma == 0.6)
        #expect(low.lift == -0.06)

        let nan = OnyxThemeSpec(primary: OnyxThemeSpec.default.primary,
                                secondary: OnyxThemeSpec.default.secondary,
                                chroma: .nan, lift: .nan).normalised()
        #expect(nan.chroma == 1)
        #expect(nan.lift == 0)

        // ── THE SLIDER'S OWN ARITHMETIC ─────────────────────────────────────
        // `Slider(value:in:step:)` snaps to `lowerBound + n × step` in binary
        // floating point, so the Terracotta position on the lift slider is
        // −0.019999999999999997. `AppearanceView` lights a chip by
        // `draft == preset.spec`, an exact comparison, so without the rounding
        // in `bounded` a user could drag a slider onto a preset's own value and
        // watch its chip stay dark.
        let slid = OnyxThemeSpec(primary: OnyxThemeSpec.default.primary,
                                 secondary: OnyxThemeSpec.default.secondary,
                                 chroma: 0.6 + 10 * 0.02, lift: -0.06 + 4 * 0.01).normalised()
        #expect(slid.chroma == 0.8)
        #expect(slid.lift == -0.02)
    }

    @Test("every preset declares a knob inside the published ranges")
    func presetKnobsAreInRange() {
        for preset in OnyxTheme.presets {
            #expect(OnyxThemeSpec.chromaScale.contains(preset.spec.chroma), "\(preset.name) chroma")
            #expect(OnyxThemeSpec.liftOffset.contains(preset.spec.lift), "\(preset.name) lift")
        }
        // The mood knob has to EARN the column: at least one preset each side
        // of neutral, or the two sliders are a setting nobody can see.
        #expect(OnyxTheme.presets.contains { $0.spec.lift < 0 })
        #expect(OnyxTheme.presets.contains { $0.spec.lift > 0 })
        #expect(OnyxTheme.presets.contains { $0.spec.chroma < 0.8 })
    }
}
