import Foundation
import Testing
@testable import OnyxCore

/// Overhaul C3 (decision Q11) — the DSLD label, decoded from REAL responses.
///
/// `dsld-label-323076.json` is Thorne "Basic Nutrients 2/Day" exactly as
/// `https://api.ods.od.nih.gov/dsld/v9/label/323076` answered on 2026-09-24
/// (CC0, unredacted). The expectations are hand-computed from that file.
@Suite("DSLD label import")
struct DSLDTests {

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("a real label decodes: serving, form and every ingredient row")
    func labelDecodes() throws {
        let label = try JSONDecoder().decode(DSLD.Label.self, from: fixture("dsld-label-323076"))
        #expect(label.id == 323076)
        #expect(label.brandName == "Thorne")
        #expect(label.fullName == "Basic Nutrients 2/Day")
        #expect(label.physicalState?.langualCodeDescription == "Capsule")
        #expect(label.servingSizes.first?.text == "2 Capsule(s)")
        #expect(label.ingredientRows.count == 24)
        let d = try #require(label.ingredientRows.first { $0.name == "Vitamin D" })
        #expect(d.amount == 50)
        #expect(d.unit == "mcg")
        #expect(d.percentDV == 250)
    }

    @Test("the label prefills the sheet: per-capsule micros in the nutrient table's units, the rest kept by name")
    func prefillMapsNutrients() throws {
        let label = try JSONDecoder().decode(DSLD.Label.self, from: fixture("dsld-label-323076"))
        let p = DSLD.prefill(label)
        #expect(p.name == "Thorne Basic Nutrients 2/Day")
        #expect(p.form == .capsule)
        #expect(p.doseAmount == 2)
        #expect(p.doseUnit == .cap)
        // A serving is two capsules; the payload is per ONE (`doseUnits`
        // multiplies it back for "2 caps").
        let expected: [String: Double] = [
            "vitaminA": 525,        // 1.05 mg → 1,050 mcg RAE ÷ 2
            "vitaminC": 125,
            "vitaminD": 1000,       // 50 mcg × 40 IU ÷ 2
            "vitaminE": 8.25,
            "vitaminK": 200,
            "vitaminB6": 10,
            "folate": 333.5,        // 667 mcg DFE ÷ 2
            "vitaminB12": 300,
            "biotin": 250,
            "calcium": 26,
            "iodine": 37.5,
            "magnesium": 10,
            "zinc": 7.5,
        ]
        #expect(p.micros == expected)
        #expect(p.otherIngredients == [
            "Thiamine", "Riboflavin", "Niacin", "Pantothenic Acid", "Selenium", "Copper",
            "Manganese", "Chromium", "D-Gamma-Tocopherol", "Boron", "Lutein",
        ])
    }

    @Test("a mass serving keeps the serving's total; an element beats its compound")
    func massServingAndCompound() throws {
        let json = """
        {"id": 33919, "fullName": "Magnesium Glycinate", "brandName": "Vinco's",
         "physicalState": {"langualCodeDescription": "Powder"},
         "servingSizes": [{"minQuantity": 1, "maxQuantity": 1, "unit": "Gram(s)"}],
         "ingredientRows": [
           {"name": "Magnesium Glycinate", "ingredientGroup": "Magnesium",
            "quantity": [{"quantity": 2000, "unit": "mg"}]},
           {"name": "Magnesium", "ingredientGroup": "Magnesium",
            "quantity": [{"quantity": 300, "unit": "mg", "dailyValueTargetGroup": [{"percent": 75}]}]},
           {"name": "Vitamin A", "quantity": [{"quantity": 5000, "unit": "IU"}]}
         ]}
        """
        let p = DSLD.prefill(try JSONDecoder().decode(DSLD.Label.self, from: Data(json.utf8)))
        #expect(p.form == .powder)
        #expect(p.doseUnit == .g)
        #expect(p.micros == ["magnesium": 300])
        // No honest IU → mcg factor for vitamin A: kept by name, not guessed.
        #expect(p.otherIngredients == ["Magnesium Glycinate", "Vitamin A"])
    }

    @Test("DSLD's spelled-out units convert: Gram(s), Milligram(s), µg")
    func spelledUnits() {
        #expect(DSLD.convert(5, from: "Gram(s)", to: "mg", key: "creatine") == 5000)
        #expect(DSLD.convert(200, from: "Milligram(s)", to: "mg", key: "theanine") == 200)
        #expect(DSLD.convert(25, from: "µg", to: "mcg", key: "vitaminB12") == 25)
        #expect(DSLD.convert(10, from: "Microgram(s)", to: "mcg", key: "biotin") == 10)
        #expect(DSLD.convert(1, from: "Serving(s)", to: "mg", key: "creatine") == nil)
    }

    @Test("an unknown serving unit leaves the dose blank rather than calling it mg")
    func unknownServingUnit() throws {
        let json = #"{"id": 1, "fullName": "Drops", "brandName": "X", "servingSizes": [{"minQuantity": 30, "unit": "Drop(s)"}], "ingredientRows": []}"#
        let p = DSLD.prefill(try JSONDecoder().decode(DSLD.Label.self, from: Data(json.utf8)))
        #expect(p.doseUnit == nil)
        #expect(p.doseAmount == nil)
    }

    @Test("a product search page decodes its hits and its count")
    func searchPage() throws {
        let page = try JSONDecoder().decode(DSLD.Page.self, from: fixture("dsld-search"))
        #expect(page.total == 29954)
        #expect(page.hits.map(\.id) == ["33919", "25018", "253226"])
        #expect(page.hits.first?.brand == "Vinco's")
        #expect(page.hits.first?.product == "Magnesium Glycinate")
        #expect(page.hits.first?.form == "Powder")
    }

    @Test("browse-brands answers one hit per label; the brand list is distinct")
    func brandsAreDistinct() throws {
        let page = try JSONDecoder().decode(DSLD.Page.self, from: fixture("dsld-brands"))
        #expect(page.hits.count == 40)
        #expect(page.total == 1715)
        #expect(DSLD.brands(page) == ["Thorne"])
    }

    @Test("a hit that does not decode is skipped, not fatal")
    func lenientHits() throws {
        let json = #"{"hits": [{"_id": "1", "_source": {"brandName": "A", "fullName": "X"}}, {"broken": true}], "stats": {"count": 2}}"#
        let page = try JSONDecoder().decode(DSLD.Page.self, from: Data(json.utf8))
        #expect(page.hits.map(\.id) == ["1"])
        #expect(page.total == 2)
    }

    /// Overhaul W5.3 (Lane C open call 2): a label's micros are per ONE unit
    /// of a count serving. Switching the dose to a mass unit before saving
    /// RESCALES them to the serving's total — a mass dose credits ×1, so the
    /// per-cap figure would have under-counted a 2-cap serving by half.
    @Test("micros are re-based when the dose unit changes before saving")
    func microsFollowTheSavedUnit() {
        let twoCaps = DSLD.Prefill(name: "Mag", form: .capsule, doseAmount: 2, doseUnit: .cap,
                                   micros: ["magnesium": 100, "zinc": 7.5], otherIngredients: [])
        // Unchanged count unit: per unit, as the label import stored it.
        #expect(DSLD.micros(twoCaps, amount: 2, unit: .cap) == ["magnesium": 100, "zinc": 7.5])
        #expect(DSLD.micros(twoCaps, amount: 3, unit: .tab) == ["magnesium": 100, "zinc": 7.5])
        // Count → mass: the serving's total, credited once.
        #expect(DSLD.micros(twoCaps, amount: 400, unit: .mg) == ["magnesium": 200, "zinc": 15])
        // Mass → count: the serving's total split over the units typed.
        let massServing = DSLD.Prefill(name: "Mag", form: .powder, doseAmount: 5, doseUnit: .g,
                                       micros: ["magnesium": 200], otherIngredients: [])
        #expect(DSLD.micros(massServing, amount: 2, unit: .scoop) == ["magnesium": 100])
        #expect(DSLD.micros(massServing, amount: 5, unit: .g) == ["magnesium": 200])
        // No micros, nothing to move.
        let bare = DSLD.Prefill(name: "X", form: nil, doseAmount: nil, doseUnit: nil, micros: [:], otherIngredients: [])
        #expect(DSLD.micros(bare, amount: 1, unit: .mg).isEmpty)
    }
}
