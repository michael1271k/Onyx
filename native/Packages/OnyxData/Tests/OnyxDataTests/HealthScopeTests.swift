import Foundation
import GRDB
import Testing
import OnyxCore
@testable import OnyxData
#if canImport(HealthKit)
import HealthKit
#endif

/// App Store W6 — the read scope is exactly what the app shows.
///
/// `privacy/unnecessary_data`: a HealthKit read type no screen draws is a
/// rejection. Sixteen of them sat in the scope, unread, from the web era until W6.
/// This pins the scope to its readers, so a type added without a surface — or
/// a surface removed without its type — fails here rather than at review.
@Suite("Health read scope")
struct HealthScopeTests {

    /// Every read type, and the one thing that shows it. Adding a type means
    /// adding a row here, which means naming its screen.
    static let surfaces: [String: String] = [
        "HKQuantityTypeIdentifierStepCount": "Pulse Steps, Steps tile, activity score",
        "HKQuantityTypeIdentifierDistanceWalkingRunning": "Steps tile km, Steps sheet",
        "HKQuantityTypeIdentifierActiveEnergyBurned": "Pulse Active, battery activity drain",
        "HKQuantityTypeIdentifierAppleExerciseTime": "Body Trends Training",
        "HKQuantityTypeIdentifierAppleStandTime": "Pulse Stand",
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": "Pulse HRV, readiness",
        "HKQuantityTypeIdentifierRestingHeartRate": "Pulse Resting HR, readiness",
        "HKQuantityTypeIdentifierHeartRate": "session heart-rate panel, wrist coverage",
        "HKQuantityTypeIdentifierVO2Max": "weekly export",
        "HKQuantityTypeIdentifierRespiratoryRate": "Pulse Respiratory",
        "HKQuantityTypeIdentifierOxygenSaturation": "Pulse Blood O₂",
        "HKQuantityTypeIdentifierBodyMass": "Scale square, weight tile",
        "HKQuantityTypeIdentifierBodyMassIndex": "InBody sheet BMI",
        "HKQuantityTypeIdentifierBodyFatPercentage": "Scale square, Composition tile",
        "HKQuantityTypeIdentifierLeanBodyMass": "Body Trends fat-free mass",
        "HKQuantityTypeIdentifierTimeInDaylight": "Body Trends Daylight",
        "HKQuantityTypeIdentifierAppleSleepingWristTemperature": "Pulse Wrist temp",
        "HKQuantityTypeIdentifierDietaryEnergyConsumed": "Nutrition ring",
        "HKQuantityTypeIdentifierDietaryProtein": "Nutrition macros",
        "HKQuantityTypeIdentifierDietaryCarbohydrates": "Nutrition macros",
        "HKQuantityTypeIdentifierDietaryFatTotal": "Nutrition macros",
        "HKQuantityTypeIdentifierDietaryWater": "Water row, Water tile",
        "HKQuantityTypeIdentifierDietaryFiber": "Nutrients grid",
        "HKQuantityTypeIdentifierDietarySugar": "Nutrients grid",
        "HKQuantityTypeIdentifierDietarySodium": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryPotassium": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryCalcium": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryIron": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryMagnesium": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryVitaminC": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryVitaminD": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryFatSaturated": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryZinc": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryIodine": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryVitaminA": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryVitaminB6": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryVitaminB12": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryVitaminE": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryVitaminK": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryBiotin": "Nutrients grid",
        "HKQuantityTypeIdentifierDietaryCholesterol": "Nutrients grid",
        "HKCategoryTypeIdentifierSleepAnalysis": "Sleep card, readiness",
        "HKWorkoutTypeIdentifier": "cardio import, Hevy line",
        "HKQuantityTypeIdentifierBasalEnergyBurned": "cardio sheet Total energy",
        "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute": "session heart-rate panel",
    ]

    @Test("the scope is exactly the types with a surface — nothing more, nothing less")
    func scopeHasSurfaces() {
        #expect(Set(HealthCatalogue.readTypes) == Set(Self.surfaces.keys))
        #expect(HealthCatalogue.readTypes.count == Self.surfaces.count, "deduped, as requestAuthorization gets it")
    }

    @Test("the seven web-era types with no screen are gone")
    func deadTypesGone() {
        for id in ["FlightsClimbed", "AppleMoveTime", "WalkingHeartRateAverage", "Height", "UVExposure",
                   "DietaryFatMonounsaturated", "DietaryFatPolyunsaturated"] {
            #expect(!HealthCatalogue.readTypes.contains("HKQuantityTypeIdentifier\(id)"), "\(id) has no surface")
        }
    }

    @Test("every micro the ingest stores is a key the Nutrients grid draws")
    func microsHaveRows() {
        let gridKeys = Set(NutrientTargets.all.map(\.key))
        for key in HealthCatalogue.microKeys {
            #expect(gridKeys.contains(key.rawValue), "\(key.rawValue) would be stored and never drawn")
        }
    }

    @Test("the micros bundle carries the nine new keys, and the grid reads them by those names")
    func bundleCarriesNewKeys() throws {
        var payload = HealthPayload(date: "2026-09-03")
        let new: [HealthKey: Double] = [.zinc: 9.5, .iodine: 140, .vitaminA: 820, .vitaminB6: 1.6, .vitaminB12: 3.1,
                                        .vitaminE: 11, .vitaminK: 95, .biotin: 28, .cholesterol: 260]
        for (k, v) in new { payload[k] = v }
        // The micros ride on the day's nutrition row, which needs a calorie total.
        payload[.calories] = 2100
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        try db.ingest(payload, userId: "u1")
        let row = try #require(try db.writer.read { conn in
            try NutritionEntryRow.filter(Column("user_id") == "u1" && Column("date") == "2026-09-03").fetchOne(conn)
        })
        let raw = try #require(row.micros?.raw)
        let decoded = try JSONDecoder().decode([String: Double].self, from: Data(raw.utf8))
        for (k, v) in new { #expect(decoded[k.rawValue] == v) }
    }

    #if canImport(HealthKit)
    @Test("the new micros are read in the unit their targets are written in")
    func units() {
        let mcg = HKUnit.gramUnit(with: .micro), mg = HKUnit.gramUnit(with: .milli)
        for id in ["Iodine", "VitaminA", "VitaminB12", "VitaminK", "Biotin"] {
            #expect(HealthKitReader.unit(for: "HKQuantityTypeIdentifierDietary\(id)") == mcg, "\(id) is µg")
        }
        for id in ["Zinc", "VitaminB6", "VitaminE", "Cholesterol"] {
            #expect(HealthKitReader.unit(for: "HKQuantityTypeIdentifierDietary\(id)") == mg, "\(id) is mg")
        }
        #expect(HealthKitReader.unit(for: HealthCatalogue.heartRateRecoveryIdentifier)
                == HKUnit.count().unitDivided(by: .minute()))
        // Each target's unit names the same scale the reader converts to.
        for t in NutrientTargets.all where ["iodine", "vitaminA", "vitaminB12", "vitaminK", "biotin"].contains(t.key) {
            #expect(t.unit == "mcg")
        }
    }
    #endif
}
