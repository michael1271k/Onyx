import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// "The scale synced a weight, but nobody entered the composition." A port of
// the web app's `lib/body/compGap.ts`.
//
// HealthKit delivers bodyweight alone; body fat, lean soft tissue and skeletal
// muscle are typed in from the scale's display. A weigh-in with an empty
// composition is therefore a STATE, not an absence — and the actionable one.
// ─────────────────────────────────────────────────────────────────────────────

public struct BodyCompFields: Codable, Equatable, Sendable {
    public var weightKg: Double?
    public var bodyFatPct: Double?
    /// Lean SOFT TISSUE — not skeletal muscle.
    public var muscleMassKg: Double?
    public var skeletalMuscleMassKg: Double?

    enum CodingKeys: String, CodingKey {
        case weightKg = "weight_kg", bodyFatPct = "body_fat_pct", muscleMassKg = "muscle_mass_kg", skeletalMuscleMassKg = "skeletal_muscle_mass_kg"
    }

    public init(weightKg: Double? = nil, bodyFatPct: Double? = nil, muscleMassKg: Double? = nil, skeletalMuscleMassKg: Double? = nil) {
        self.weightKg = weightKg; self.bodyFatPct = bodyFatPct; self.muscleMassKg = muscleMassKg; self.skeletalMuscleMassKg = skeletalMuscleMassKg
    }
}

public enum BodyCompState: String, Codable, Sendable {
    case none
    case weightOnly = "weight-only"
    case partial
    case complete
}

public enum CompGap {
    /// The MANUAL fields — the ones a sync can never fill — in entry order, by column name.
    static let manualFields = ["body_fat_pct", "muscle_mass_kg", "skeletal_muscle_mass_kg"]

    static let fieldName: [String: String] = [
        "body_fat_pct": "body fat", "muscle_mass_kg": "lean soft tissue", "skeletal_muscle_mass_kg": "skeletal muscle",
    ]

    /// A value counts as present when it is a real number > 0. 0 is not a body fat %.
    static func present(_ v: Double?) -> Bool { v.map { $0.isFinite && $0 > 0 } ?? false }

    static func value(_ row: BodyCompFields, _ field: String) -> Double? {
        switch field {
        case "body_fat_pct": return row.bodyFatPct
        case "muscle_mass_kg": return row.muscleMassKg
        case "skeletal_muscle_mass_kg": return row.skeletalMuscleMassKg
        default: return nil
        }
    }

    public static func state(_ row: BodyCompFields?) -> BodyCompState {
        guard let row, present(row.weightKg) else { return .none }
        let have = manualFields.filter { present(value(row, $0)) }.count
        if have == 0 { return .weightOnly }
        return have == manualFields.count ? .complete : .partial
    }

    /// Which manual fields are still owed, in entry order. Empty with no weight.
    public static func missingFields(_ row: BodyCompFields?) -> [String] {
        guard let row, present(row.weightKg) else { return [] }
        return manualFields.filter { !present(value(row, $0)) }
    }

    /// "body fat and skeletal muscle" — an Oxford-free list.
    static func nameList(_ fields: [String]) -> String {
        let names = fields.map { fieldName[$0] ?? $0 }
        if names.count <= 1 { return names.first ?? "" }
        return "\(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1])"
    }

    /// The nudge for a day whose weight arrived alone, or nil.
    public static func gapLabel(_ row: BodyCompFields?) -> String? {
        guard state(row) == .weightOnly else { return nil }
        return "Weight synced — add \(nameList(missingFields(row)))"
    }

    /// The short trailing hint for a `partial` day, or nil.
    public static func gapShort(_ row: BodyCompFields?) -> String? {
        guard state(row) == .partial else { return nil }
        return "add \(nameList(missingFields(row)))"
    }
}
