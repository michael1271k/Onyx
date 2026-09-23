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

    private func preset(_ name: String) -> OnyxThemeSpec {
        OnyxTheme.presets.first { $0.name == name }!.spec
    }

    @Test("the origin spec reproduces every default domain colour, bit for bit")
    func originIsIdentity() {
        let theme = OnyxTheme(spec: .origin)
        for d in OnyxDomain.allCases {
            let hex = OnyxDomain.defaultDomainHex[d]!
            #expect(theme.start[d] == Color(hex: hex.start), "\(d) start")
            #expect(theme.end[d] == Color(hex: hex.end), "\(d) end")
        }
        // And the process boots on the DEFAULT, which is Slate — not the origin.
        #expect(OnyxTheme.current.spec == .default)
        #expect(OnyxTheme.presets.first?.name == "Slate")
    }

    @Test("the Stone eight, in grid order, with Slate first")
    func presetsAreTheStoneEight() {
        #expect(OnyxTheme.presets.map(\.name) == ["Slate", "Lagoon", "Sage", "Iris",
                                                  "Clay", "Ochre", "Moss", "Rosewood"])
        #expect(OnyxTheme.presets.first?.spec == .default)
    }

    @Test("every preset keeps the four domain accents apart and is its own normalised value")
    func presetsKeepDomainsApart() {
        #expect(OnyxTheme.presets.count == 8)
        for preset in OnyxTheme.presets {
            // Identity, not idempotence: the literals in the table ARE the
            // normalised values, so the source shows what ships.
            #expect(preset.spec.normalised() == preset.spec, "\(preset.name) literal is already in range")
            let theme = OnyxTheme(spec: preset.spec)
            let accents = OnyxDomain.allCases.map { theme.start[$0]!.description }
            #expect(Set(accents).count == accents.count, "\(preset.name)")
        }
    }

    @Test("the sixteen muscles are the fixed anatomical palette under every preset")
    func musclesAreFixed() {
        // Decision Q18: the theme tints chrome, never anatomy. Chest is the
        // same coral in Slate and in Rosewood, so a legend learned once holds.
        defer { OnyxTheme.apply(json: "") }
        for preset in OnyxTheme.presets {
            OnyxTheme.set(preset.spec)
            for m in LandmarkMuscle.allCases {
                #expect(Color.onyx.muscle(m) == Color(hex: Color.onyx.defaultMuscleHex[m]!), "\(preset.name) \(m)")
            }
            let families = MuscleFamily.allCases.map { Color.onyx.muscleFamily($0).description }
            #expect(Set(families).count == families.count, "\(preset.name) families")
        }
        #expect(Set(Color.onyx.defaultMuscleHex.values).count == 16)
    }

    @Test("water, heart and the sleep ramp never move with the theme")
    func fixedInksAreFixed() {
        defer { OnyxTheme.apply(json: "") }
        for preset in OnyxTheme.presets {
            OnyxTheme.set(preset.spec)
            #expect(Color.onyx.water == Color(hex: 0x4A9BD6), "\(preset.name) water")
            #expect(OnyxInk.Fixed.water == Color(hex: 0x4A9BD6))
            #expect(OnyxInk.Fixed.heart == Color(hex: 0xE5484D))
            #expect(OnyxInk.Fixed.heart == Color.onyx.danger)
            #expect(OnyxSleepStage.deep.color == Color(hex: 0x4B4A8A), "\(preset.name) deep")
            #expect(OnyxSleepStage.core.color == Color(hex: 0x7B76B8), "\(preset.name) core")
            #expect(OnyxSleepStage.rem.color == Color(hex: 0xB8B3E0), "\(preset.name) rem")
            #expect(OnyxSleepStage.awake.color == Color.onyx.textSecondary)
            #expect(OnyxInk.Fixed.sleep == OnyxSleepStage.allCases.map(\.color))
            #expect(OnyxInk.Fixed.good == Color.onyx.good)
            #expect(OnyxInk.Fixed.record == Color.onyx.record)
        }
    }

    @Test("the themed half of the ink table follows the theme")
    func themedInksFollow() {
        defer { OnyxTheme.apply(json: "") }
        OnyxTheme.set(preset("Clay"))
        #expect(OnyxInk.Themed.accent == Color(hex: preset("Clay").primary))
        #expect(OnyxInk.Themed.train.start == OnyxDomain.train.start)
        #expect(OnyxInk.Themed.train.end == OnyxDomain.train.end)
        #expect(OnyxInk.Themed.selection == OnyxDomain.train.accent)
        #expect(OnyxInk.Themed.mesh == OnyxDomain.allCases.map(\.accent))
    }

    // MARK: - Nutrition, weighted (Q19)

    /// ΔE in Oklab × 100 between two resolved colours.
    private func deltaE(_ a: Color, _ b: Color) -> Double {
        func lab(_ c: Color) -> (Double, Double, Double) {
            let o = OKLCHConvert.oklch(fromHex: c.onyxHex)
            return (o.l, o.c * cos(o.h * .pi / 180), o.c * sin(o.h * .pi / 180))
        }
        let (l1, a1, b1) = lab(a), (l2, a2, b2) = lab(b)
        return 100 * ((l1 - l2) * (l1 - l2) + (a1 - a2) * (a1 - a2) + (b1 - b2) * (b1 - b2)).squareRoot()
    }

    @Test("the nutrition inks move with the theme, but only a little")
    func nutritionIsWeighted() {
        defer { OnyxTheme.apply(json: "") }
        let inks: [(String, () -> Color)] = [
            ("protein", { Color.onyx.protein }), ("carbs", { Color.onyx.carbs }),
            ("fat", { Color.onyx.fat }), ("calories", { Color.onyx.calories }),
            ("micro", { Color.onyx.micro }),
        ]
        for (name, read) in inks {
            var colours: [(String, Color)] = []
            for preset in OnyxTheme.presets {
                OnyxTheme.set(preset.spec)
                colours.append((preset.name, read()))
                #expect(OKLCHConvert.oklch(fromHex: read().onyxHex).c <= OnyxThemeSpec.nutritionMaxChroma + 0.005,
                        "\(preset.name) \(name) chroma")
            }
            var low = Double.infinity, high = 0.0
            for i in colours.indices {
                for j in colours.indices where j > i {
                    let d = deltaE(colours[i].1, colours[j].1)
                    low = min(low, d)
                    high = max(high, d)
                }
            }
            // ≤ 12: still recognisably the same ink in all eight. The brief's
            // ≥ 3 floor is arithmetically out of reach at weight 0.35 / C ≤
            // 0.12 with primaries 35° apart (see the W0 wave record); 1.5 is
            // what the chord derivation guarantees — no two presets collapse.
            #expect(high <= 12, "\(name): widest pair ΔE \(high)")
            #expect(low >= 1.5, "\(name): closest pair ΔE \(low)")
        }
        // Calories are the Atwater sum and wear the carbs ink.
        OnyxTheme.set(preset("Moss"))
        #expect(Color.onyx.calories == Color.onyx.carbs)
        #expect(Color.onyx.carbs == Color(hex: preset("Moss").weighted(weight: OnyxThemeSpec.nutritionWeight).secondary))
    }

    @Test("the six chart series stay six colours under every preset")
    func seriesStayDistinctUnderEveryPreset() {
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
        let clay = preset("Clay")
        let theme = OnyxTheme(spec: clay)
        #expect(theme.start[.train] == Color(hex: clay.primary))
        #expect(theme.start[.fuel] == Color(hex: clay.secondary))
        #expect(theme.end[.train] != Color(hex: OnyxDomain.defaultDomainHex[.train]!.end))
    }

    @Test("the derived statics follow a theme change instead of freezing at first read")
    func derivedStaticsFollow() {
        defer { OnyxTheme.apply(json: "") }
        OnyxTheme.apply(json: "")
        let protein = Color.onyx.protein
        let carbs = Color.onyx.carbs
        let fat = Color.onyx.fat
        let calories = Color.onyx.calories
        let micro = Color.onyx.micro
        let series0 = Color.onyx.series[0]

        OnyxTheme.current = OnyxTheme(spec: preset("Clay"))
        #expect(Color.onyx.protein != protein)
        #expect(Color.onyx.carbs != carbs)
        #expect(Color.onyx.fat != fat)
        #expect(Color.onyx.calories != calories)
        #expect(Color.onyx.micro != micro)
        #expect(Color.onyx.series[0] != series0)
    }

    @Test("an out-of-range spec is normalised on the way in, never rendered raw")
    func appliedSpecsAreNormalised() {
        defer { OnyxTheme.apply(json: "") }
        let raw = OnyxThemeSpec(primary: 0x101020, secondary: 0xFF0000)
        #expect(raw.normalised() != raw)
        // `set` is the door the watch and the shot harness use with a pair in
        // hand; it normalises and does not snap to a preset.
        OnyxTheme.set(raw)
        #expect(OnyxTheme.current.spec == raw.normalised())
    }

    @Test("apply, load and save move the current theme; corrupt or empty means default")
    func plumbing() {
        defer { OnyxTheme.apply(json: "") }
        let clay = preset("Clay")

        OnyxTheme.apply(json: "")
        #expect(OnyxTheme.current.spec == .default)
        OnyxTheme.apply(json: "{not json")
        #expect(OnyxTheme.current.spec == .default)

        let suite = "onyx.theme.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removeObject(forKey: OnyxTheme.key)

        OnyxTheme.save(clay, to: defaults)
        #expect(OnyxTheme.current.spec == clay)
        // The static tokens follow — this is the whole point.
        #expect(OnyxDomain.train.start == Color(hex: clay.primary))
        #expect(OnyxDomain.fuel.accent == Color(hex: clay.secondary))
        let json = defaults.string(forKey: OnyxTheme.key)!
        #expect(json.contains("\"primary\""))

        OnyxTheme.apply(json: "")
        #expect(OnyxTheme.current.spec == .default)
        OnyxTheme.load(defaults)
        #expect(OnyxTheme.current.spec == clay)
        OnyxTheme.apply(json: json)
        #expect(OnyxTheme.current.spec == clay)

        defaults.set("garbage", forKey: OnyxTheme.key)
        OnyxTheme.load(defaults)
        #expect(OnyxTheme.current.spec == .default)
    }

    // MARK: - The legacy migration (W0)

    @Test("a legacy blob lands on the nearest Stone preset by hue")
    func legacyBlobsMigrate() {
        // The nine 8.0.0 presets, as they were stored.
        let ion = OnyxThemeSpec(primary: 0x6B78F0, secondary: 0xE3A650)
        let ember = OnyxThemeSpec(primary: 0xE8734A, secondary: 0x01B677, chroma: 0.90, lift: -0.02)
        #expect(OnyxTheme.migrateLegacy(ion) == preset("Slate"))
        #expect(OnyxTheme.migrateLegacy(ember) == preset("Clay"))
        // A current preset passes through as itself.
        for p in OnyxTheme.presets {
            #expect(OnyxTheme.migrateLegacy(p.spec) == p.spec, "\(p.name)")
        }
    }

    @Test("an old two-key blob still decodes, then load migrates it once and writes it back")
    func oldBlobMigratesOnLoad() throws {
        defer { OnyxTheme.apply(json: "") }
        // The literal shape every install written before W3 holds at
        // `OnyxTheme.key`: two keys, no chroma, no lift — Ion's pair.
        let old = "{\"primary\":\(0x6B78F0),\"secondary\":\(0xE3A650)}"
        let decoded = try JSONDecoder().decode(OnyxThemeSpec.self, from: Data(old.utf8))
        #expect(decoded.primary == 0x6B78F0)
        #expect(decoded.chroma == 1)
        #expect(decoded.lift == 0)

        let suite = "onyx.theme.tests.legacy"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(old, forKey: OnyxTheme.key)
        OnyxTheme.load(defaults)
        #expect(OnyxTheme.current.base == preset("Slate"))
        let stored = try #require(defaults.string(forKey: OnyxTheme.key))
        #expect(try JSONDecoder().decode(OnyxThemeSpec.self, from: Data(stored.utf8)) == preset("Slate"))

        // The render path snaps too, so the app root never draws a dead theme
        // in the frame before anything calls `load`.
        OnyxTheme.apply(json: "{\"primary\":\(0xE8734A),\"secondary\":\(0x01B677)}")
        #expect(OnyxTheme.current.base == preset("Clay"))
    }

    // MARK: - The mood knob

    @Test("the neutral knob on the origin is the measured palette; a turned one is not")
    func theKnobIsNeutralAtTheOriginAndLiveOtherwise() {
        #expect(OnyxThemeSpec.origin.chroma == 1)
        #expect(OnyxThemeSpec.origin.lift == 0)

        let neutral = OnyxTheme(spec: .origin)
        let muted = OnyxTheme(spec: OnyxThemeSpec(primary: OnyxThemeSpec.origin.primary,
                                                  secondary: OnyxThemeSpec.origin.secondary,
                                                  chroma: 0.6, lift: -0.06))
        // The two CHOSEN accents do not move, by design.
        #expect(muted.start[.train] == neutral.start[.train])
        #expect(muted.start[.fuel] == neutral.start[.fuel])
        // Everything derived does — otherwise the knob is decoration.
        #expect(muted.end[.train] != neutral.end[.train])
        #expect(muted.end[.fuel] != neutral.end[.fuel])
        #expect(muted.start[.body] != neutral.start[.body])
        #expect(muted.start[.recover] != neutral.start[.recover])
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
        // Sweeps the hue circle, not the preset table: the failing band of the
        // first version (warm-yellow primaries) held no preset and the test
        // passed with the defect in place. Chroma is swept too — the failing
        // column was 0.9–1.0 — and `end` is read because `body.end` carries a
        // numeral on two widget faces.
        let aa = 4.5
        var worst = (ratio: Double.infinity, what: "")
        for degrees in stride(from: 0.0, to: 360.0, by: 10) {
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
        // And the eight presets as they ship, every ink that carries text.
        for preset in OnyxTheme.presets {
            let theme = OnyxTheme(spec: preset.spec)
            for domain in OnyxDomain.allCases {
                #expect(onBlack(theme.start[domain]!.onyxHex) >= aa, "\(preset.name) \(domain).start")
                #expect(onBlack(theme.end[domain]!.onyxHex) >= aa, "\(preset.name) \(domain).end")
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

        // Rounded onto the two-decimal grid, so a value produced by binary
        // floating-point steps still compares equal to a preset's literal.
        let slid = OnyxThemeSpec(primary: OnyxThemeSpec.default.primary,
                                 secondary: OnyxThemeSpec.default.secondary,
                                 chroma: 0.6 + 10 * 0.02, lift: -0.06 + 4 * 0.01).normalised()
        #expect(slid.chroma == 0.8)
        #expect(slid.lift == -0.02)
    }

    // MARK: - The spacing rule, and the phase offset (W2)

    @Test("no two presets read as the same theme")
    func presetPrimariesStayThirtyFiveDegreesApart() {
        // PRIMARIES only — two themes may legitimately share a secondary family.
        // W0 moved Iris +4° (drafted 7D6BA6 at h 297.5 sat 32° from Slate).
        let hues = OnyxTheme.presets.map { (name: $0.name, h: OKLCHConvert.hue(ofHex: $0.spec.primary)) }
        for i in hues.indices {
            for j in hues.indices where j > i {
                var delta = abs(hues[i].h - hues[j].h)
                if delta > 180 { delta = 360 - delta }
                #expect(delta >= 35, "\(hues[i].name) vs \(hues[j].name): \(delta)°")
            }
        }
    }

    @Test("a training block moves the derived palette and never the pick")
    func phaseMovesTheDerivedPaletteAndNotThePick() {
        let pick = preset("Lagoon")

        // `peak` and nil are the identity — the app before this existed.
        #expect(pick.reacting(to: nil) == pick)
        #expect(pick.reacting(to: .peak) == pick)

        let cut = pick.reacting(to: .cut)
        #expect(cut.chroma == pick.chroma - 0.10)
        #expect(cut.lift == pick.lift - 0.03)
        let bulk = pick.reacting(to: .bulk)
        #expect(bulk.lift == pick.lift + 0.03)
        #expect(bulk.chroma == pick.chroma)
        // Deload SETS the saturation rather than stepping it: one fixed quiet.
        #expect(pick.reacting(to: .deload).chroma == 0.70)
        // And no preset is loud enough for that to be a step UP.
        for preset in OnyxTheme.presets {
            #expect(preset.spec.reacting(to: .deload).chroma <= preset.spec.chroma, "\(preset.name)")
        }
        let quiet = OnyxThemeSpec(primary: pick.primary, secondary: pick.secondary, chroma: 0.62, lift: -0.05)
        #expect(quiet.reacting(to: .cut).chroma == OnyxThemeSpec.chromaScale.lowerBound)
        #expect(quiet.reacting(to: .cut).lift == OnyxThemeSpec.liftOffset.lowerBound)

        // The two CHOSEN accents survive the block; the derived ones do not.
        let plain = OnyxTheme(spec: pick)
        let blocked = OnyxTheme(spec: cut, base: pick)
        #expect(blocked.start[.train] == plain.start[.train])
        #expect(blocked.start[.fuel] == plain.start[.fuel])
        #expect(blocked.start[.body] != plain.start[.body])
        #expect(blocked.base == pick)
        #expect(blocked.spec != pick)
    }

    @Test("the stored block reaches the palette, and never the stored theme")
    func thePhaseKeyLoadsButIsNeverSaved() throws {
        defer { OnyxTheme.apply(json: "") }
        let suite = "onyx.theme.tests.phase"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let pick = preset("Sage")

        defaults.set(PhaseKind.deload.rawValue, forKey: OnyxTheme.phaseKey)
        OnyxTheme.save(pick, to: defaults)
        #expect(OnyxTheme.current.base == pick)
        #expect(OnyxTheme.current.spec == pick.reacting(to: .deload))

        let stored = try #require(defaults.string(forKey: OnyxTheme.key))
        #expect(try JSONDecoder().decode(OnyxThemeSpec.self, from: Data(stored.utf8)) == pick)

        OnyxTheme.apply(json: "")
        OnyxTheme.load(defaults)
        #expect(OnyxTheme.current.base == pick)
        #expect(OnyxTheme.current.spec == pick.reacting(to: .deload))

        defaults.removeObject(forKey: OnyxTheme.phaseKey)
        OnyxTheme.load(defaults)
        #expect(OnyxTheme.current.spec == pick)
        #expect(OnyxTheme.current.base == pick)

        defaults.set("marathon", forKey: OnyxTheme.phaseKey)
        OnyxTheme.load(defaults)
        #expect(OnyxTheme.current.spec == pick)
    }

    @Test("every preset declares the Stone knob: chroma 0.85–0.95, lift 0")
    func presetKnobsAreInRange() {
        for preset in OnyxTheme.presets {
            #expect((0.85...0.95).contains(preset.spec.chroma), "\(preset.name) chroma")
            #expect(preset.spec.lift == 0, "\(preset.name) lift")
            #expect(preset.spec.moodWord == "Even", "\(preset.name) mood word")
        }
    }
}

/// `Color` → 8-bit sRGB hex, for the tests above that MEASURE a resolved
/// colour rather than compare it.
///
/// `Color.Resolved` is EXTENDED-RANGE sRGB, and its `red`/`green`/`blue` are
/// already gamma-ENCODED — `linearRed` and friends are the linear ones, and
/// quantising those instead turns Ion (`0x6B78F0`) into `0x2530DE`. So: the
/// encoded components, clamped before the multiply, and ROUNDED rather than
/// truncated. Same order as `OKLCHConvert.hex(from:)`.
private extension Color {
    var onyxHex: UInt32 {
        let c = resolve(in: EnvironmentValues())
        func level(_ v: Float) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return (level(c.red) << 16) | (level(c.green) << 8) | level(c.blue)
    }
}
