import Foundation

/// Supplement → micronutrient contributions. The Swift twin of
/// the web app's `lib/nutrition/supplementNutrients.ts`, table and all.
///
/// Apple Health cannot export a supplement, so the payloads are the LABEL doses
/// of this athlete's actual products, per unit of the protocol's dose. Nothing
/// is estimated: an item contributes only what its label states, so a nutrient
/// a product does not declare is simply not credited.
///
/// ── WHY THE PHONE NEEDED THIS AT ALL ────────────────────────────────────────
/// The web has credited the stack into the day's micros since the tile was
/// built. The phone drew the same nutrient screen with `amount: nil` on every
/// stack-sourced row — the target stated, the reading blank — so 470 mg of
/// vitamin C and 5 000 IU of D3 taken every morning were invisible on the
/// surface the user actually looks at.
public enum SupplementNutrients {

    /// Micronutrient payload of ONE unit of a seeded supplement.
    public static let table: [String: [String: Double]] = [
        // Morning
        "multivitamin": ["vitaminB12": 300, "folate": 680, "vitaminC": 470],
        "d3k2": ["vitaminD": 5000],

        // Pre-workout
        "citrulline": ["citrulline": 3000],
        "caffeine": ["caffeine": 200],

        // Lunch / post-workout
        "omega3": ["epa": 500, "dha": 250],
        "creatine": ["creatine": 5000],

        // Before bed
        "theanine": ["theanine": 200],
        "glycine": ["glycine": 5000],
        "magnesium": ["magnesium": 300],
    ]

    /// A dose that names a COUNT of physical units. A mass dose is not one.
    ///
    /// The payloads are per physical unit (one tab / cap / pill / scoop), so a
    /// dose naming a multiple of those genuinely delivers that multiple. A mass
    /// dose ("300 mg", "5 g") is already the total the payload states — the
    /// magnesium figure is the combined total across three tablets — so mass
    /// doses stay ×1.
    private static let countUnit = try! NSRegularExpression(
        pattern: #"^\s*(\d+(?:\.\d+)?)\s*(tabs?|caps?|capsules?|pills?|scoops?|softgels?|gummies|gummy)\b"#,
        options: [.caseInsensitive]
    )

    /// How many units of an item a dose string represents — "2 caps" → 2.
    public static func doseUnits(_ dose: String?) -> Double {
        guard let dose else { return 1 }
        let range = NSRange(dose.startIndex..<dose.endIndex, in: dose)
        guard let match = countUnit.firstMatch(in: dose, options: [], range: range),
              let numberRange = Range(match.range(at: 1), in: dose),
              let n = Double(dose[numberRange]), n.isFinite, n > 0
        else { return 1 }
        return n
    }

    /// Every row's own payload, keyed the way the log keys it.
    ///
    /// The stack lives in `custom_supplements`, and each row carries its own
    /// `micros`. Without this, correcting a dose in the app would move the
    /// checklist and the export while the micro totals kept crediting the label
    /// the table above was written against — the one place a stale number is
    /// completely invisible.
    public static func payloads(_ customs: [CustomSupplement]) -> [String: [String: Double]] {
        var out: [String: [String: Double]] = [:]
        for c in customs {
            if let micros = c.micros, !micros.isEmpty { out[Supplements.key(of: c)] = micros }
        }
        return out
    }

    /// Sum what the CREDITED doses deliver.
    ///
    /// The argument is the day's resolved doses, not a set of keys: a key set
    /// cannot say whether the dose was taken, skipped or still ahead, and the
    /// bug that shape produced on the web — passing the SKIPPED set to a
    /// parameter named `takenKeys` — credited exactly the items that had been
    /// refused.
    public static func credit(
        _ doses: [SupplementDose],
        payloads overrides: [String: [String: Double]] = [:]
    ) -> [String: Double] {
        var out: [String: Double] = [:]
        for dose in doses where dose.credited {
            guard let payload = overrides[dose.key] ?? table[dose.key] else { continue }
            let units = doseUnits(dose.dose)
            for (micro, amount) in payload {
                out[micro, default: 0] += amount * units
            }
        }
        return out
    }

    /// Food plus stack. Kept separate from `credit` so a screen can show the
    /// split — "470 of it from the stack" is more useful than one total, and it
    /// makes it obvious when a target is only being met by a pill.
    public static func merge(food: [String: Double], stack: [String: Double]) -> [String: Double] {
        var out = food.filter { $0.value.isFinite }
        for (k, v) in stack { out[k, default: 0] += v }
        return out
    }
}
