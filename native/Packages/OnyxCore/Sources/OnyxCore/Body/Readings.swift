import Foundation

/// Body readings, joined and judged — a port of the web app's `lib/body/readings.ts`.

public struct BodyTrendRow: Codable, Sendable, Equatable {
    public var date: String
    public var weightKg: Double?
    public var bodyFatPct: Double?
    public var muscleMassKg: Double?
    public var fatFreeMassKg: Double?
    enum CodingKeys: String, CodingKey { case date, weightKg = "weight_kg", bodyFatPct = "body_fat_pct", muscleMassKg = "muscle_mass_kg", fatFreeMassKg = "fat_free_mass_kg" }
}

public struct BodyDetailRow: Codable, Sendable, Equatable {
    public var date: String
    public var waterPercent: Double?
    public var musclePercent: Double?
    public var visceralFat: Double?
    public var bodyFatPct: Double?
    enum CodingKeys: String, CodingKey { case date, waterPercent = "water_percent", musclePercent = "muscle_percent", visceralFat = "visceral_fat", bodyFatPct = "body_fat_pct" }
}

public struct BodyCompositionPoint: Codable, Sendable, Equatable {
    public var date: String
    public var weight: Double?
    public var muscleMass: Double?
    public var fatFreeMass: Double?
    public var fatMass: Double?
    public var fatPct: Double?
    public var water: Double?
    public var musclePct: Double?
    public var visceral: Double?

    init(date: String) { self.date = date }
}

public enum BodyReadings {
    /// Join the two sources by date, ascending. TWO lean series, never one.
    public static func merge(trend: [BodyTrendRow], detail: [BodyDetailRow], toDisplay: (Double?) -> Double?) -> [BodyCompositionPoint] {
        var order: [String] = []
        var byDate: [String: BodyCompositionPoint] = [:]
        func point(_ date: String) -> BodyCompositionPoint {
            if let p = byDate[date] { return p }
            order.append(date)
            return BodyCompositionPoint(date: date)
        }
        for r in trend {
            var p = point(r.date)
            p.weight = toDisplay(r.weightKg)
            p.fatPct = r.bodyFatPct ?? p.fatPct
            if let w = r.weightKg, let bf = r.bodyFatPct {
                let fatKg = (w * bf) / 100
                p.fatMass = toDisplay(fatKg)
                p.fatFreeMass = toDisplay(w - fatKg)
            } else if let ffm = r.fatFreeMassKg {
                p.fatFreeMass = toDisplay(ffm)
            }
            if let mm = r.muscleMassKg { p.muscleMass = toDisplay(mm) }
            byDate[r.date] = p
        }
        for r in detail {
            var p = point(r.date)
            p.water = r.waterPercent ?? p.water
            p.musclePct = r.musclePercent ?? p.musclePct
            p.visceral = r.visceralFat ?? p.visceral
            p.fatPct = p.fatPct ?? r.bodyFatPct
            byDate[r.date] = p
        }
        return order.sorted().map { byDate[$0]! }
    }

    /// The twelve columns a smart scale can fill.
    public static let scaleMetricKeys = [
        "weight_kg", "body_fat_pct", "muscle_percent", "water_percent", "muscle_mass_kg",
        "fat_free_mass_kg", "bone_mineral", "visceral_fat", "bmr", "bmi",
        "skeletal_muscle_mass_kg", "estimated_waist_to_hip_ratio",
    ]

    /// Any non-null scale column makes the day a weigh-in (0 counts).
    public static func hasScaleMetrics(_ log: [String: Double?]?) -> Bool {
        guard let log = log else { return false }
        return scaleMetricKeys.contains { (log[$0] ?? nil) != nil }
    }
}
