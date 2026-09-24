import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The NIH Dietary Supplement Label Database — the pure half (overhaul C3,
// decision Q11). CC0 data, no key.
//
// ── THE BASE URL THE PLAN NAMED IS BEHIND A BROWSER CHALLENGE ───────────────
// `https://dsld.od.nih.gov/dsld/v9/` answers every request with Cloudflare's
// "Just a moment…" HTML page (verified 2026-09-24), which no app can pass. The
// same v9 API is served un-challenged at `https://api.ods.od.nih.gov/dsld/v9/`
// — that is the base `DSLDClient` uses. Shapes below were read off live
// responses once and are pinned by `dsld-label-323076.json`.
//
// Three reads:
//   · `search-filter?q=…&size=20&from=…[&brand=…]` — product search; hits are
//     LIGHT (brand, name, physical form; no serving, no amounts).
//   · `browse-brands?method=by_keyword&q=…&size=…` — one hit PER LABEL carrying
//     a `brandName`, so the brand list is those names deduplicated.
//   · `label/{id}` — one whole label: servings and ingredient rows with
//     amount, unit and %DV.
// ─────────────────────────────────────────────────────────────────────────────

public enum DSLD {

    /// One search hit — enough for a result row and for the label read.
    public struct Hit: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        public let brand: String
        public let product: String
        /// `Capsule`, `Tablet or Pill`, `Powder`… — DSLD's own word.
        public let form: String?
        /// `2 Capsule(s)` — only brand-products hits carry a serving.
        public let serving: String?
        public let offMarket: Bool

        public init(id: String, brand: String, product: String, form: String?, serving: String?, offMarket: Bool = false) {
            self.id = id
            self.brand = brand
            self.product = product
            self.form = form
            self.serving = serving
            self.offMarket = offMarket
        }

        private enum CodingKeys: String, CodingKey { case id = "_id", source = "_source" }
        private struct Source: Decodable {
            let brandName: String?
            let fullName: String?
            let physicalState: Label.PhysicalState?
            let servingSizes: [Label.ServingSize]?
            let offMarket: Int?
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let source = try c.decode(Source.self, forKey: .source)
            id = try c.decode(String.self, forKey: .id)
            brand = source.brandName ?? ""
            product = source.fullName ?? ""
            form = source.physicalState?.langualCodeDescription
            serving = source.servingSizes?.first.flatMap(\.text)
            offMarket = (source.offMarket ?? 0) != 0
        }
    }

    /// A page of hits. `search-filter` counts in `stats.count`; the browse and
    /// brand reads in `total.value`.
    public struct Page: Decodable, Sendable, Equatable {
        public let hits: [Hit]
        public let total: Int

        public init(hits: [Hit], total: Int) {
            self.hits = hits
            self.total = total
        }

        private enum CodingKeys: String, CodingKey { case hits, stats, total }
        private struct Count: Decodable { let count: Int?; let value: Int? }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // `hits` is a bare array on search-filter and the same array on the
            // others; a hit whose shape does not decode is skipped, not fatal.
            let raw = try c.decodeIfPresent([Lenient<Hit>].self, forKey: .hits) ?? []
            hits = raw.compactMap(\.value)
            total = (try? c.decode(Count.self, forKey: .stats))?.count
                ?? (try? c.decode(Count.self, forKey: .total))?.value
                ?? hits.count
        }
    }

    /// One whole label.
    public struct Label: Decodable, Sendable, Equatable {
        public let id: Int
        public let fullName: String
        public let brandName: String
        public let physicalState: PhysicalState?
        public let servingSizes: [ServingSize]
        public let ingredientRows: [IngredientRow]
        public let upcSku: String?

        public struct PhysicalState: Decodable, Sendable, Equatable {
            public let langualCodeDescription: String?
        }

        public struct ServingSize: Decodable, Sendable, Equatable {
            public let minQuantity: Double?
            public let maxQuantity: Double?
            public let unit: String?

            /// `2 Capsule(s)`, `0.5–1 Gram(s)`.
            public var text: String? {
                guard let min = minQuantity, let unit else { return nil }
                let lo = Self.number(min)
                if let max = maxQuantity, max != min { return "\(lo)–\(Self.number(max)) \(unit)" }
                return "\(lo) \(unit)"
            }

            static func number(_ v: Double) -> String {
                v == v.rounded() ? String(Int(v)) : String(v)
            }
        }

        public struct IngredientRow: Decodable, Sendable, Equatable {
            public let name: String
            public let ingredientGroup: String?
            public let quantity: [Quantity]

            public struct Quantity: Decodable, Sendable, Equatable {
                public let quantity: Double?
                public let unit: String?
                public let dailyValueTargetGroup: [DailyValue]?
            }

            public struct DailyValue: Decodable, Sendable, Equatable {
                public let percent: Double?
            }

            /// The first serving's amount — the label's own figure.
            public var amount: Double? { quantity.first?.quantity }
            public var unit: String? { quantity.first?.unit }
            public var percentDV: Double? { quantity.first?.dailyValueTargetGroup?.first?.percent }
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            fullName = try c.decodeIfPresent(String.self, forKey: .fullName) ?? ""
            brandName = try c.decodeIfPresent(String.self, forKey: .brandName) ?? ""
            physicalState = try c.decodeIfPresent(PhysicalState.self, forKey: .physicalState)
            servingSizes = try c.decodeIfPresent([ServingSize].self, forKey: .servingSizes) ?? []
            ingredientRows = (try c.decodeIfPresent([Lenient<IngredientRow>].self, forKey: .ingredientRows) ?? [])
                .compactMap(\.value)
            upcSku = try c.decodeIfPresent(String.self, forKey: .upcSku)
        }

        private enum CodingKeys: String, CodingKey {
            case id, fullName, brandName, physicalState, servingSizes, ingredientRows, upcSku
        }
    }

    /// A value that decodes to nil instead of failing its array.
    struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    // MARK: - Label → the edit sheet

    /// What a label fills in on `SupplementEditSheet`.
    public struct Prefill: Sendable, Equatable {
        public var name: String
        public var form: SupplementForm?
        public var doseAmount: Double?
        public var doseUnit: DoseUnit?
        /// Per ONE unit of the dose, keyed by `NutrientTargets` — the shape
        /// `SupplementNutrients.payloads` credits. A count dose (2 caps) is
        /// divided down to one cap; a mass dose stays the serving's total.
        public var micros: [String: Double]
        /// Ingredient names the nutrient table has no key for — kept for the
        /// export rather than dropped.
        public var otherIngredients: [String]

        public init(name: String, form: SupplementForm?, doseAmount: Double?, doseUnit: DoseUnit?,
                    micros: [String: Double], otherIngredients: [String]) {
            self.name = name; self.form = form; self.doseAmount = doseAmount
            self.doseUnit = doseUnit; self.micros = micros; self.otherIngredients = otherIngredients
        }
    }

    /// The label as the sheet fills it.
    public static func prefill(_ label: Label) -> Prefill {
        let serving = label.servingSizes.first
        let unit = serving.flatMap { doseUnit($0.unit) }
        let amount = serving?.minQuantity
        // Micros are per ONE unit of a count dose — `doseUnits` multiplies back.
        let perUnit = (unit?.isCount == true) ? max(amount ?? 1, 1) : 1
        var micros: [String: Double] = [:]
        var other: [String] = []
        for row in label.ingredientRows {
            guard let key = nutrientKey(row.name),
                  let target = NutrientTargets.all.first(where: { $0.key == key }),
                  let value = row.amount, value > 0,
                  let converted = convert(value, from: row.unit, to: target.unit, key: key)
            else {
                if !other.contains(row.name) { other.append(row.name) }
                continue
            }
            micros[key, default: 0] += round4(converted / perUnit)
        }
        return Prefill(
            name: label.brandName.isEmpty ? label.fullName : "\(label.brandName) \(label.fullName)",
            form: supplementForm(label.physicalState?.langualCodeDescription),
            doseAmount: amount,
            doseUnit: unit,
            micros: micros,
            otherIngredients: other
        )
    }

    /// Distinct brand names in first-seen order — `browse-brands` answers one
    /// hit per LABEL.
    public static func brands(_ page: Page) -> [String] {
        var seen = Set<String>()
        return page.hits.map(\.brand).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    // MARK: - Vocabulary

    /// A label's ingredient NAME → the nutrient key. By name, not by group:
    /// `Magnesium Glycinate` (the compound, 2 g) and `Magnesium` (the element,
    /// 300 mg) share a group, and only the element is the nutrient.
    static let names: [String: String] = [
        "vitamin a": "vitaminA", "vitamin c": "vitaminC", "vitamin d": "vitaminD",
        "vitamin d3": "vitaminD", "vitamin e": "vitaminE", "vitamin k": "vitaminK",
        "vitamin b6": "vitaminB6", "vitamin b12": "vitaminB12", "folate": "folate",
        "folic acid": "folate", "biotin": "biotin", "calcium": "calcium", "iron": "iron",
        "magnesium": "magnesium", "potassium": "potassium", "sodium": "sodium",
        "zinc": "zinc", "iodine": "iodine", "creatine": "creatine",
        "creatine monohydrate": "creatine", "l-citrulline": "citrulline",
        "citrulline": "citrulline", "caffeine": "caffeine", "l-theanine": "theanine",
        "theanine": "theanine", "glycine": "glycine", "epa": "epa",
        "eicosapentaenoic acid": "epa", "dha": "dha", "docosahexaenoic acid": "dha",
        "dietary fiber": "fiber", "fiber": "fiber",
    ]

    public static func nutrientKey(_ name: String) -> String? {
        names[name.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// A label amount in the target's unit, or nil when there is no honest
    /// conversion (vitamin A or E in IU — the factor depends on the form).
    static func convert(_ value: Double, from raw: String?, to target: String, key: String) -> Double? {
        guard let raw else { return nil }
        // `mcg DFE`, `mcg RAE` are mcg — the qualifier says how it was counted.
        let unit = raw.lowercased().split(separator: " ").first.map(String.init) ?? ""
        let mcg: [String: Double] = ["g": 1_000_000, "mg": 1_000, "mcg": 1, "µg": 1, "ug": 1]
        if target == "IU" {
            if unit == "iu" { return value }
            // Vitamin D only: 1 mcg cholecalciferol = 40 IU.
            if key == "vitaminD", let f = mcg[unit] { return value * f * 40 }
            return nil
        }
        guard let from = mcg[unit], let to = mcg[target.lowercased()] else { return nil }
        return value * from / to
    }

    /// DSLD's `Gram(s)`, `Capsule(s)`, `Tablet(s)`… → the sheet's unit.
    static func doseUnit(_ raw: String?) -> DoseUnit? {
        guard let s = raw?.lowercased() else { return nil }
        if s.hasPrefix("capsule") || s.hasPrefix("softgel") || s.hasPrefix("vegcap") { return .cap }
        if s.hasPrefix("tablet") || s.hasPrefix("caplet") || s.hasPrefix("gumm") || s.hasPrefix("lozenge") || s.hasPrefix("chew") { return .tab }
        if s.hasPrefix("scoop") { return .scoop }
        if s.hasPrefix("gram") || s == "g" { return .g }
        if s.hasPrefix("milligram") || s == "mg" { return .mg }
        if s.hasPrefix("milliliter") || s.hasPrefix("ml") { return .ml }
        return nil
    }

    /// DSLD's physical state → the sheet's form.
    static func supplementForm(_ raw: String?) -> SupplementForm? {
        guard let s = raw?.lowercased() else { return nil }
        if s.contains("capsule") || s.contains("softgel") { return .capsule }
        if s.contains("tablet") || s.contains("pill") || s.contains("lozenge") { return .pill }
        if s.contains("powder") { return .powder }
        if s.contains("liquid") { return .liquid }
        if s.contains("gumm") || s.contains("jelly") { return .gummy }
        return nil
    }

    private static func round4(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
}
