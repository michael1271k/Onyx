import Testing
import Foundation
@testable import OnyxCore

/// Overhaul Lane B's two pure rules: the one sleep stage order, and which
/// micronutrients a Fuel face calls out.
@Suite("Overhaul faces")
struct OverhaulFacesTests {

    @Test("stages come back in depth order; a nil stage is absent, a zero stays")
    func stageOrder() {
        let s = SleepStage.segments(deep: 68, core: 251, rem: 92, awake: 26)
        #expect(s.map(\.0) == [.deep, .core, .rem, .awake])
        #expect(s.map(\.1) == [68, 251, 92, 26])
        // The watch reported no REM at all vs. reported zero REM.
        #expect(SleepStage.segments(deep: 60, core: 200, rem: nil, awake: 10).map(\.0) == [.deep, .core, .awake])
        #expect(SleepStage.segments(deep: 60, core: 200, rem: 0, awake: 10).map(\.0) == [.deep, .core, .rem, .awake])
        // A night synced as a duration alone has no composition to draw.
        #expect(SleepStage.segments(deep: nil, core: nil, rem: nil, awake: nil).isEmpty)
        // A negative stage (a bad trim) never draws negative width.
        #expect(SleepStage.segments(deep: -5, core: nil, rem: nil, awake: nil).first?.1 == 0)
    }

    @Test("key micros: furthest from target first, food-only, never a macro or an unmeasured nutrient")
    func keyMicros() {
        let totals: [String: Double] = [
            "potassium": 1394,   // 41 % of 3400 → 0.59 off
            "sodium": 4140,      // 138 % of the 3000 ceiling → 0.38 off
            "calcium": 660,      // 66 % → 0.34 off
            "iron": 10,          // exactly on target → 0 off
            "protein": 20,       // a macro: its own rail already
            "fiber": 3,          // Macros group: excluded
            "magnesium": 10,     // stack-delivered: the widget sums food only
        ]
        let top = KeyMicro.top(totals: totals)
        #expect(top.map(\.key) == ["potassium", "sodium", "calcium"])
        // Far OVER a floor is a good day, not a callout: 400 % iron must not
        // push the 41 % potassium out.
        var rich = totals
        rich["iron"] = 40
        #expect(KeyMicro.top(totals: rich, limit: 1).first?.key == "potassium")
        #expect(abs(top[0].pct - 1394.0 / 3400) < 1e-9)
        #expect(top[0].name == "Potassium")
        #expect(KeyMicro.top(totals: totals, limit: 2).count == 2)
        // Nothing measured is nothing to call out — never a row of 0 %.
        #expect(KeyMicro.top(totals: [:]).isEmpty)
        #expect(KeyMicro.top(totals: ["protein": 10, "magnesium": 5]).isEmpty)
    }

    @Test("an old payload without keyMicros still decodes, and reads as none")
    func keyMicrosDecodeOld() throws {
        let old = #"{"kcal":1200,"kcalGoal":2000}"#
        let macros = try JSONDecoder().decode(OnyxSnapshot.Macros.self, from: Data(old.utf8))
        #expect(macros.keyMicros == nil)
        #expect(macros.micros.isEmpty)
        let new = OnyxSnapshot.Macros(kcal: 1, keyMicros: [KeyMicro(key: "iron", name: "Iron", pct: 0.5)])
        let round = try JSONDecoder().decode(OnyxSnapshot.Macros.self, from: JSONEncoder().encode(new))
        #expect(round == new)
    }
}
