import Foundation

/// Daily micronutrient targets for THIS athlete — the data half of
/// the web app's `lib/nutrition/nutrientTargets.ts`. `floor` = aim to reach; `ceiling` =
/// stay at or under. The rationale strings and HealthKit identifiers are
/// documentation and stay on the web side.
public struct NutrientTarget: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case floor, ceiling }
    public var key: String
    public var label: String
    public var target: Double
    public var unit: String
    public var kind: Kind
    public var group: String
    /// Delivered by the supplement stack rather than food.
    public var fromStack: Bool
}

public enum NutrientTargets {
    private static func t(_ key: String, _ label: String, _ target: Double, _ unit: String, _ kind: NutrientTarget.Kind, _ group: String, stack: Bool = false) -> NutrientTarget {
        NutrientTarget(key: key, label: label, target: target, unit: unit, kind: kind, group: group, fromStack: stack)
    }

    /// The sections, in the order a page reads them — the twin of
    /// `NUTRIENT_GROUPS`.
    ///
    /// ── WHY THE ORDER IS DECLARED AND NOT DERIVED ───────────────────────────
    /// Both clients used to group by first appearance in `all`, so the section
    /// order was a side effect of the row order and moving one nutrient
    /// reordered the page. Macros first because they are the day's shape;
    /// Other last because it is the things nothing but the stack delivers.
    public static let groups = ["Macros", "Vitamins", "Minerals", "Other"]

    /// Whether a reading meets its target.
    ///
    /// A floor (fibre, potassium) is met by reaching it; a ceiling (sodium,
    /// added sugar) is met by staying at or under it. Same geometry, opposite
    /// verdict — which is why the two cannot share a `>=`.
    ///
    /// `nil` is NOT "unmet": nothing measured it, and a nutrient the phone
    /// cannot see must not count against a completion figure.
    public static func isMet(_ target: NutrientTarget, total: Double?) -> Bool? {
        guard let total else { return nil }
        switch target.kind {
        case .floor:   return total >= target.target
        case .ceiling: return total <= target.target
        }
    }

    /// How many of a set of targets are met, out of how many were MEASURED.
    public static func completion(
        _ targets: [NutrientTarget], reading: (NutrientTarget) -> Double?
    ) -> (met: Int, measured: Int) {
        var met = 0, measured = 0
        for target in targets {
            guard let ok = isMet(target, total: reading(target)) else { continue }
            measured += 1
            if ok { met += 1 }
        }
        return (met, measured)
    }

    /// The targets of one section, in table order.
    public static func inGroup(_ group: String) -> [NutrientTarget] {
        all.filter { $0.group == group }
    }

    public static let all: [NutrientTarget] = [
        t("fiber", "Fiber", 30, "g", .floor, "Macros"),
        t("protein", "Protein", 170, "g", .floor, "Macros"),
        t("sodium", "Sodium", 3000, "mg", .ceiling, "Minerals"),
        t("potassium", "Potassium", 3400, "mg", .floor, "Minerals"),
        t("calcium", "Calcium", 1000, "mg", .floor, "Minerals"),
        t("iron", "Iron", 10, "mg", .floor, "Minerals"),
        /* ── THREE FLOORS THE STACK MEETS, NOT THE FOOD LOG ──────────────────
           `fromStack` says where a nutrient is EXPECTED to come from, and these
           three were marked as food's job while the stack has been delivering
           every milligram of them: magnesium glycinate 300 mg, D3 + K2 5 000 IU
           and the multivitamin's 470 mg of vitamin C, all of them in
           `SupplementNutrients.table` and all of them credited on the day.

           The cost of the wrong mark is one line: §7 names every non-stack
           floor the food source did not report, so the document ended each week
           saying magnesium and vitamin D were "not reported by the food source
           on 7 of 7 days" — true, irrelevant, and read as a deficiency against
           a target the stack was bought to meet. Nothing else changes: the
           weekly mean has always summed food AND stack, and the nutrient grid
           marks a stack-sourced row with a pill glyph, which is now correct for
           these three too. */
        t("magnesium", "Magnesium", 400, "mg", .floor, "Minerals", stack: true),
        t("vitaminC", "Vitamin C", 90, "mg", .floor, "Vitamins", stack: true),
        t("vitaminD", "Vitamin D", 2000, "IU", .floor, "Vitamins", stack: true),
        t("satFat", "Saturated Fat", 20, "g", .ceiling, "Macros"),
        t("sugar", "Added Sugar", 40, "g", .ceiling, "Macros"),
        t("vitaminB12", "Vitamin B12", 2.4, "mcg", .floor, "Vitamins", stack: true),
        t("folate", "Folate", 400, "mcg", .floor, "Vitamins", stack: true),
        t("epa", "EPA", 500, "mg", .floor, "Other", stack: true),
        t("dha", "DHA", 250, "mg", .floor, "Other", stack: true),
        t("creatine", "Creatine", 5000, "mg", .floor, "Other", stack: true),
        t("citrulline", "L-Citrulline", 3000, "mg", .floor, "Other", stack: true),
        t("caffeine", "Caffeine", 400, "mg", .ceiling, "Other", stack: true),
        t("theanine", "L-Theanine", 200, "mg", .floor, "Other", stack: true),
        t("glycine", "Glycine", 3000, "mg", .floor, "Other", stack: true),
        /* ── NINE HEALTH TYPES THAT WERE AUTHORISED AND NEVER READ (W6) ──────
           The read scope asked for them since the web era and no screen drew
           them, which `privacy/unnecessary_data` calls a rejection. They are
           read now, and this table is what makes them visible: the grid draws
           exactly these keys and nothing else.

           Floors are the adult DRI (NIH ODS, men 19–50 — the same basis as
           potassium 3,400 and magnesium 400 above); cholesterol is the label
           Daily Value, as a ceiling. Decided in W6, not measured — edit here.
           Appended rather than interleaved, so the export's nutrient line
           grows at its end and every existing position stays put. */
        t("zinc", "Zinc", 11, "mg", .floor, "Minerals"),
        t("iodine", "Iodine", 150, "mcg", .floor, "Minerals"),
        t("vitaminA", "Vitamin A", 900, "mcg", .floor, "Vitamins"),
        t("vitaminB6", "Vitamin B6", 1.3, "mg", .floor, "Vitamins"),
        t("vitaminE", "Vitamin E", 15, "mg", .floor, "Vitamins"),
        t("vitaminK", "Vitamin K", 120, "mcg", .floor, "Vitamins"),
        t("biotin", "Biotin", 30, "mcg", .floor, "Vitamins"),
        t("cholesterol", "Cholesterol", 300, "mg", .ceiling, "Macros"),
    ]
}
