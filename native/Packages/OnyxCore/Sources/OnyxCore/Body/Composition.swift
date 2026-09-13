import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Body-composition math — the "InBody engine". A port of the web app's `lib/body/composition.ts`.
//
// A smart scale reports percentages; the trendable numbers are masses, derived
// as weight × %. Fat-free mass = weight − fat mass. Protein: its own % when
// given, else backed out of the fat-free compartment (FFM − water − bone).
//
// NO TAPE MEASUREMENTS, EVER: the waist-to-hip ratio Onyx tracks is the
// scale's own single float, entered, never derived. SKELETAL MUSCLE MASS IS
// NOT DERIVED AND CANNOT BE: weight × muscle% is lean SOFT TISSUE (~50 kg),
// skeletal muscle (~27 kg) is a separate scale reading.
// ─────────────────────────────────────────────────────────────────────────────

public struct BodyCompInput: Codable, Equatable, Sendable {
    public var weightKg: Double?
    public var bodyFatPct: Double?
    public var musclePercent: Double?
    public var waterPercent: Double?
    /// A percentage.
    public var boneMineral: Double?
    public var proteinPercent: Double?

    enum CodingKeys: String, CodingKey {
        case weightKg = "weight_kg", bodyFatPct = "body_fat_pct", musclePercent = "muscle_percent"
        case waterPercent = "water_percent", boneMineral = "bone_mineral", proteinPercent = "protein_percent"
    }

    public init(weightKg: Double? = nil, bodyFatPct: Double? = nil, musclePercent: Double? = nil, waterPercent: Double? = nil, boneMineral: Double? = nil, proteinPercent: Double? = nil) {
        self.weightKg = weightKg; self.bodyFatPct = bodyFatPct; self.musclePercent = musclePercent
        self.waterPercent = waterPercent; self.boneMineral = boneMineral; self.proteinPercent = proteinPercent
    }
}

/// Only the masses whose inputs were present.
public struct BodyCompDerived: Codable, Equatable, Sendable {
    public var fatMassKg: Double?
    public var fatFreeMassKg: Double?
    public var muscleMassKg: Double?
    public var waterMassKg: Double?
    public var boneMineralKg: Double?
    public var proteinMassKg: Double?

    enum CodingKeys: String, CodingKey {
        case fatMassKg = "fat_mass_kg", fatFreeMassKg = "fat_free_mass_kg", muscleMassKg = "muscle_mass_kg"
        case waterMassKg = "water_mass_kg", boneMineralKg = "bone_mineral_kg", proteinMassKg = "protein_mass_kg"
    }

    public init() {}
}

/// WHO abdominal-obesity risk bands, applied to the SCALE'S reported ratio.
public enum WhrBand: String, Codable, Sendable { case low, moderate, high }

/// Visceral-fat index bands — stricter than the scale's, from the plan's own targets.
public enum VisceralBand: String, Codable, Sendable { case optimal, elevated, high }

public enum BodyComposition {
    /// Round to 2 dp, the JavaScript way.
    private static func r2(_ v: Double) -> Double { jsRound(v * 100) / 100 }

    private static func finite(_ v: Double?) -> Double? { v.flatMap { $0.isFinite ? $0 : nil } }

    /// One percentage of a bodyweight, as kilograms.
    ///
    /// Public since W5: the InBody sheet prints "= xx.x kg" live beside every
    /// percentage field, and a second copy of `(weight × pct) / 100` in a view
    /// is a second copy that rounds differently the first time either is
    /// touched. `nil` in either argument is `nil` out — a percentage of an
    /// unknown weight is not a mass.
    public static func massFromPct(_ weight: Double?, _ pct: Double?) -> Double? {
        guard let weight, let pct else { return nil }
        return r2((weight * pct) / 100)
    }

    /// Derive every mass we can from the entered weight + percentages.
    public static func derive(_ input: BodyCompInput) -> BodyCompDerived {
        let weight = finite(input.weightKg), bf = finite(input.bodyFatPct)
        let musclePct = finite(input.musclePercent), waterPct = finite(input.waterPercent)
        let bonePct = finite(input.boneMineral), proteinPct = finite(input.proteinPercent)

        var out = BodyCompDerived()
        out.fatMassKg = massFromPct(weight, bf)
        let ffm: Double? = (weight != nil && bf != nil) ? r2(weight! * (1 - bf! / 100)) : nil
        out.fatFreeMassKg = ffm
        out.muscleMassKg = massFromPct(weight, musclePct)
        let waterMass = massFromPct(weight, waterPct)
        out.waterMassKg = waterMass
        let boneMass = massFromPct(weight, bonePct)
        out.boneMineralKg = boneMass
        if let p = massFromPct(weight, proteinPct) {
            out.proteinMassKg = p
        } else if let ffm, let waterMass, let boneMass {
            out.proteinMassKg = r2(Swift.max(0, ffm - waterMass - boneMass))
        }
        return out
    }

    public static func whrBand(_ ratio: Double, sex: String = "male") -> WhrBand {
        let (lo, hi) = sex == "male" ? (0.90, 1.00) : (0.80, 0.85)
        if ratio < lo { return .low }
        return ratio < hi ? .moderate : .high
    }

    public static func visceralBand(_ index: Double) -> VisceralBand {
        if index < 5 { return .optimal }
        return index <= 7 ? .elevated : .high
    }
}
