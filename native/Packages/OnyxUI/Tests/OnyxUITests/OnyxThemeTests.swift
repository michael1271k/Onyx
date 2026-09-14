import Testing
import SwiftUI
import OnyxCore
@testable import OnyxUI

/// The runtime theme. `.serialized` because three of these tests move the
/// process-wide `OnyxTheme.current` and put it back; a parallel reader of
/// `Color.onyx.*` in another suite would otherwise see a preset for a frame.
@Suite("OnyxTheme", .serialized)
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

    @Test("every preset keeps the four domain accents apart, and the first is the default")
    func presetsKeepDomainsApart() {
        #expect(OnyxTheme.presets.count >= 6 && OnyxTheme.presets.count <= 8)
        #expect(OnyxTheme.presets.first?.spec == .default)
        for preset in OnyxTheme.presets {
            #expect(preset.spec.normalised() == preset.spec, "\(preset.name) is in range")
            let theme = OnyxTheme(spec: preset.spec)
            let accents = OnyxDomain.allCases.map { theme.start[$0]!.description }
            #expect(Set(accents).count == accents.count, "\(preset.name)")
        }
    }

    @Test("a non-default spec moves train and fuel and drags the rest with them")
    func derivation() {
        let ember = OnyxTheme.presets.first { $0.name == "Ember" }!.spec
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

        OnyxTheme.current = OnyxTheme(spec: OnyxTheme.presets.first { $0.name == "Ember" }!.spec)
        #expect(Color.onyx.protein != protein)
        #expect(Color.onyx.carbs != carbs)
        #expect(Color.onyx.fat != fat)
        #expect(Color.onyx.calories != calories)
        #expect(Color.onyx.series[0] != series0)
    }

    @Test("apply, load and save move the current theme; corrupt or empty means default")
    func plumbing() {
        defer { OnyxTheme.apply(json: "") }
        let ember = OnyxTheme.presets.first { $0.name == "Ember" }!.spec

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
}
