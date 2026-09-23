import Foundation

/// The HealthKit contract, carried over verbatim from `lib/native/healthkit.ts`.
///
/// ── WHY VERBATIM, AND WHY THAT IS NOT LAZINESS ──────────────────────────────
/// Nearly every line of `METRIC_MAP` is a bug that was paid for once. The two
/// scale factors and three of the reducers are not preferences:
///
///   · `OxygenSaturation` is a 0–1 FRACTION. Stored unscaled it read 0.982 and
///     the card rendered "1%".
///   · `BodyFatPercentage` is the same fraction, with the same consequence.
///   · `LeanBodyMass` is FAT-FREE MASS (weight − fat), not muscle mass —
///     HealthKit has no muscle-mass type at all. Sent as `lean_mass` it landed
///     in the column the InBody card fills with weight × muscle%, ~2.6 kg
///     lower, and the trend line stepped whenever the source changed.
///   · `VO2Max` updates roughly weekly, so `latest` is the only honest reducer;
///     an average over a day of one sample is the same number, and over a day
///     of none it is nothing.
///   · Dietary energy is SUMMED from the source's own entries rather than
///     derived from 4·C + 4·P + 9·F, so the calorie total matches the app the
///     food was logged in, fibre and rounding included.
///
/// The plan lists this map as one of the six native contracts that survive the
/// migration unchanged. This is that file's Swift half.
public enum HealthReduce: String, Sendable, Equatable {
    /// Everything in the window, added up. `HKStatisticsOptions.cumulativeSum`.
    case sum
    /// The window's mean. `.discreteAverage`.
    case average
    /// The last reading in the window. `.mostRecent`.
    case latest
}

/// A payload key — the flat ingest vocabulary, which is NOT the column
/// vocabulary. `training_minutes` lands in `exercise_minutes`; `standing_minutes`
/// is Apple's stand-HOURS ring count despite the name. See `DailyLogIngest`.
public enum HealthKey: String, Sendable, Hashable, CaseIterable {
    case steps
    case distanceM = "distance_m"
    case activeEnergy = "active_energy"
    case trainingMinutes = "training_minutes"
    case standingMinutes = "standing_minutes"
    case hrv
    case avgRestHeartRate = "avg_rest_heart_rate"
    case avgHeartRate = "avg_heart_rate"
    case vo2max
    case respiratoryRate = "respiratory_rate"
    case bloodOxygen = "blood_oxygen"
    case weight
    case bmi
    case bodyFat = "body_fat"
    case fatFreeMass = "fat_free_mass"
    case timeInDaylight = "time_in_daylight"
    case wristTemp = "wrist_temp"
    case calories
    case protein
    case carbs
    case fats
    case water
    case fiber
    case sugar
    case sodium
    case potassium
    case calcium
    case iron
    case magnesium
    case vitaminC
    case vitaminD
    case satFat
    // App Store W6 — authorised since the web era and never read. Each one
    // now lands in the micros bundle and has a row in the Nutrients grid;
    // a read scope with a type no screen shows is a review rejection.
    case zinc
    case iodine
    case vitaminA
    case vitaminB6
    case vitaminB12
    case vitaminE
    case vitaminK
    case biotin
    case cholesterol
}

/// One quantity type, and what to do with it.
public struct HealthMetric: Sendable, Equatable {
    public let identifier: String
    public let key: HealthKey
    public let reduce: HealthReduce
    /// Multiplies the reduced value before it is stored. Only ever a unit fix.
    public let scale: Double

    init(_ identifier: String, _ key: HealthKey, _ reduce: HealthReduce, scale: Double = 1) {
        self.identifier = identifier
        self.key = key
        self.reduce = reduce
        self.scale = scale
    }
}

public enum HealthCatalogue {

    /// `METRIC_MAP`, in order.
    public static let metrics: [HealthMetric] = [
        .init("HKQuantityTypeIdentifierStepCount", .steps, .sum),
        // Real walking+running distance, in METRES. The Steps card shows ground
        // covered, and estimating km from a stride guess would put a fabricated
        // number next to measured ones.
        .init("HKQuantityTypeIdentifierDistanceWalkingRunning", .distanceM, .sum),
        .init("HKQuantityTypeIdentifierActiveEnergyBurned", .activeEnergy, .sum),
        .init("HKQuantityTypeIdentifierAppleExerciseTime", .trainingMinutes, .sum),
        // AppleStandTime is the QUANTITY type (minutes); AppleStandHour is a
        // category and cannot be read as a statistic. `standToHours` converts.
        .init("HKQuantityTypeIdentifierAppleStandTime", .standingMinutes, .sum),
        .init("HKQuantityTypeIdentifierHeartRateVariabilitySDNN", .hrv, .average),
        .init("HKQuantityTypeIdentifierRestingHeartRate", .avgRestHeartRate, .latest),
        .init("HKQuantityTypeIdentifierHeartRate", .avgHeartRate, .average),
        .init("HKQuantityTypeIdentifierVO2Max", .vo2max, .latest),
        .init("HKQuantityTypeIdentifierRespiratoryRate", .respiratoryRate, .average),
        // A 0–1 fraction → ×100 to store an actual percent.
        .init("HKQuantityTypeIdentifierOxygenSaturation", .bloodOxygen, .latest, scale: 100),
        .init("HKQuantityTypeIdentifierBodyMass", .weight, .latest),
        .init("HKQuantityTypeIdentifierBodyMassIndex", .bmi, .latest),
        .init("HKQuantityTypeIdentifierBodyFatPercentage", .bodyFat, .latest, scale: 100),
        // Fat-free mass. NOT muscle mass — see the file note.
        .init("HKQuantityTypeIdentifierLeanBodyMass", .fatFreeMass, .latest),
        .init("HKQuantityTypeIdentifierTimeInDaylight", .timeInDaylight, .sum),
        .init("HKQuantityTypeIdentifierAppleSleepingWristTemperature", .wristTemp, .average),
        .init("HKQuantityTypeIdentifierDietaryEnergyConsumed", .calories, .sum),
        .init("HKQuantityTypeIdentifierDietaryProtein", .protein, .sum),
        .init("HKQuantityTypeIdentifierDietaryCarbohydrates", .carbs, .sum),
        .init("HKQuantityTypeIdentifierDietaryFatTotal", .fats, .sum),
        .init("HKQuantityTypeIdentifierDietaryWater", .water, .sum),
        .init("HKQuantityTypeIdentifierDietaryFiber", .fiber, .sum),
        .init("HKQuantityTypeIdentifierDietarySugar", .sugar, .sum),
        .init("HKQuantityTypeIdentifierDietarySodium", .sodium, .sum),
        .init("HKQuantityTypeIdentifierDietaryPotassium", .potassium, .sum),
        .init("HKQuantityTypeIdentifierDietaryCalcium", .calcium, .sum),
        .init("HKQuantityTypeIdentifierDietaryIron", .iron, .sum),
        .init("HKQuantityTypeIdentifierDietaryMagnesium", .magnesium, .sum),
        .init("HKQuantityTypeIdentifierDietaryVitaminC", .vitaminC, .sum),
        .init("HKQuantityTypeIdentifierDietaryVitaminD", .vitaminD, .sum),
        .init("HKQuantityTypeIdentifierDietaryFatSaturated", .satFat, .sum),
        .init("HKQuantityTypeIdentifierDietaryZinc", .zinc, .sum),
        .init("HKQuantityTypeIdentifierDietaryIodine", .iodine, .sum),
        .init("HKQuantityTypeIdentifierDietaryVitaminA", .vitaminA, .sum),
        .init("HKQuantityTypeIdentifierDietaryVitaminB6", .vitaminB6, .sum),
        .init("HKQuantityTypeIdentifierDietaryVitaminB12", .vitaminB12, .sum),
        .init("HKQuantityTypeIdentifierDietaryVitaminE", .vitaminE, .sum),
        .init("HKQuantityTypeIdentifierDietaryVitaminK", .vitaminK, .sum),
        .init("HKQuantityTypeIdentifierDietaryBiotin", .biotin, .sum),
        .init("HKQuantityTypeIdentifierDietaryCholesterol", .cholesterol, .sum),
    ]

    /// The dietary micros — the only metrics whose SOURCE is worth recording.
    ///
    /// They are the ones that land as an un-decomposable daily aggregate in
    /// `nutrition_entries.micros`, so when one is implausible there is nothing
    /// left to interrogate. Everything else in the catalogue is a measurement
    /// of the body, where "which app wrote it" is not a useful question.
    public static let microKeys: Set<HealthKey> = [
        .sugar, .sodium, .potassium, .calcium, .iron, .magnesium, .vitaminC, .vitaminD, .satFat,
        .zinc, .iodine, .vitaminA, .vitaminB6, .vitaminB12, .vitaminE, .vitaminK, .biotin, .cholesterol,
    ]

    /// A food type. The prefix IS the classification — every dietary quantity
    /// HealthKit defines carries it, and nothing else does.
    public static func isDietary(_ identifier: String) -> Bool {
        identifier.hasPrefix("HKQuantityTypeIdentifierDietary")
    }

    public static let sleepIdentifier = "HKCategoryTypeIdentifierSleepAnalysis"
    /// Read a second time, over the night's bed window, for readiness v9.
    public static let hrvIdentifier = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"

    /// `HKObjectType.workoutType()` has no quantity or category identifier;
    /// this is the one name the reader maps to it.
    public static let workoutTypeIdentifier = "HKWorkoutTypeIdentifier"

    /// Resting energy over a bout's own window — the other half of a TOTAL
    /// figure. Read per bout by the cardio ingest, never into the daily row:
    /// `daily_logs` already carries active energy and adding basal to it would
    /// double-count the day against itself.
    public static let restingEnergyIdentifier = "HKQuantityTypeIdentifierBasalEnergyBurned"

    /// Apple's one-minute heart-rate recovery — the drop from the peak rate to
    /// the rate a minute after a workout ended. Read per session, at view
    /// time, by `SessionTelemetry`; never stored.
    public static let heartRateRecoveryIdentifier = "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute"

    /// Types read, but not into the daily row. Each has ONE reader, named.
    ///
    /// ── EVERY TYPE HERE HAS A SCREEN (App Store W6) ─────────────────────────
    /// This list used to carry sixteen types "to keep the app's entry under
    /// Health → Apps complete". Nothing read them. `privacy/unnecessary_data`
    /// reads it the other way round: a read scope wider than what the app
    /// shows is a rejection. The nine dietary ones moved into `metrics` and
    /// the Nutrients grid; flights, move time, walking heart rate, height,
    /// UV exposure and mono/polyunsaturated fat had no figure to feed and
    /// came out. `HealthScopeTests` pins the list to its readers.
    static let extraReadTypes = [
        // `sleepSamples` → `daily_logs.sleep_minutes`, the Sleep card, readiness.
        sleepIdentifier,
        // `workouts` → the cardio import, the Hevy line, `WorkoutWriter.decide`.
        workoutTypeIdentifier,
        // The cardio sheet's TOTAL energy (active + resting) for one bout.
        restingEnergyIdentifier,
        // The session heart-rate panel's "1-min recovery".
        heartRateRecoveryIdentifier,
    ]

    /// The exact `requestAuthorization` argument: every metric read, deduped,
    /// in a stable order.
    public static let readTypes: [String] = {
        var seen = Set<String>()
        var out: [String] = []
        for id in metrics.map(\.identifier) + extraReadTypes where seen.insert(id).inserted {
            out.append(id)
        }
        return out
    }()
}

// MARK: - Rounding

public extension HealthCatalogue {
    /// `roundReduced`: scale first (the unit fix), then round to the precision
    /// the metric deserves.
    ///
    /// A count is an integer; everything else keeps two decimals, which is what
    /// a weight, a resting heart rate, a VO₂max and a blood-oxygen percent all
    /// want. `nil` in is `nil` out — a metric this device does not record is
    /// absent, not zero, and the difference survives all the way to the column.
    static func round(_ raw: Double?, reduce: HealthReduce, scale: Double = 1, precise: Bool = false) -> Double? {
        guard let raw, raw.isFinite else { return nil }
        let v = raw * scale
        return reduce == .sum && !precise ? (v).rounded() : ((v * 100).rounded() / 100)
    }
}
