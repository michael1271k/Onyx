#if canImport(HealthKit)
import Foundation
import HealthKit
import OnyxCore

/// `HealthReading` over a real `HKHealthStore`.
///
/// ── WHAT THE WEB-SHELL PLUGIN DID THAT THIS DOES NOT ────────────────────────
/// The bridge marshalled every query through JSON, so the old plugin
/// carried an `inBatches(…, 6, …)` throttle — firing twenty-eight queries at
/// once the instant authorization resolved hammered the store during app launch
/// and stalled the WebView. There is no bridge here and no main thread involved:
/// the queries run on HealthKit's own queue and the results are `Double`s. The
/// batching is gone with the bridge that needed it.
///
/// Units are named explicitly at every call. HealthKit will happily convert, and
/// a wrong-but-plausible unit (grams for a macro that is stored in grams,
/// kilocalories for one stored in kilojoules) is the failure that looks like a
/// data problem for months.
public struct HealthKitReader: HealthReading {

    private let store = HKHealthStore()

    public init() {}

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestAuthorization(read: [String]) async throws -> Bool {
        guard isAvailable else { return false }
        let types = Set(read.compactMap(Self.objectType))
        guard !types.isEmpty else { return false }
        try await store.requestAuthorization(toShare: [], read: types)
        return true
    }

    public func quantity(
        _ identifier: String, reduce: HealthReduce, start: Date, end: Date
    ) async throws -> Double? {
        guard isAvailable,
              let type = HKObjectType.quantityType(forIdentifier: .init(rawValue: identifier))
        else { return nil }

        let options: HKStatisticsOptions
        switch reduce {
        case .sum: options = .cumulativeSum
        case .average: options = .discreteAverage
        case .latest: options = .mostRecent
        }
        // Half-open, so a sample at exactly midnight belongs to one day and not
        // to both. `.strictStartDate` is what makes the bound exclusive rather
        // than "overlaps the interval".
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: [.strictStartDate]
        )
        let unit = Self.unit(for: identifier)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: options
            ) { _, statistics, error in
                // A type with no samples returns `nil` statistics AND an error
                // whose code is `noData`. That is absence, not failure — and
                // treating it as failure would fail the whole day's sync on the
                // first metric this device does not record.
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: error)
                    return
                }
                let value: HKQuantity?
                switch reduce {
                case .sum: value = statistics?.sumQuantity()
                case .average: value = statistics?.averageQuantity()
                case .latest: value = statistics?.mostRecentQuantity()
                }
                continuation.resume(returning: value?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// The day's sum for one type, split by the app that wrote each sample.
    ///
    /// `.separateBySource` rides along with `.cumulativeSum` in one query, so
    /// this costs a pass over the same samples and no extra round trip. The
    /// keys are `HKSource.name` — "MyFitnessPal", "Onyx", "iPhone" — which is
    /// what a person reads in Health → Nutrition → Show All Data, and therefore
    /// what they can act on.
    public func quantityBySource(
        _ identifier: String, start: Date, end: Date
    ) async throws -> [String: Double] {
        guard isAvailable,
              let type = HKObjectType.quantityType(forIdentifier: .init(rawValue: identifier))
        else { return [:] }
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: [.strictStartDate]
        )
        let unit = Self.unit(for: identifier)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate,
                options: [.cumulativeSum, .separateBySource]
            ) { _, statistics, error in
                // Absence is not failure — the `noData` rule the total above
                // states, for the same reason.
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: error)
                    return
                }
                guard let statistics, let sources = statistics.sources else {
                    continuation.resume(returning: [:])
                    return
                }
                var out: [String: Double] = [:]
                for source in sources {
                    guard let q = statistics.sumQuantity(for: source) else { continue }
                    let v = q.doubleValue(for: unit)
                    // A zero contribution is not a contributor.
                    guard v > 0 else { continue }
                    out[source.name, default: 0] += v
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Raw samples, for the dietary types whose total a re-sync can inflate.
    public func quantitySamples(
        _ identifier: String, start: Date, end: Date
    ) async throws -> [QuantitySample]? {
        guard isAvailable,
              let type = HKObjectType.quantityType(forIdentifier: .init(rawValue: identifier))
        else { return nil }
        // The same half-open window the statistics query uses, so the deduped
        // sum and the total it replaces are taken over the same samples.
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: [.strictStartDate]
        )
        let unit = Self.unit(for: identifier)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    // Absence is not failure, and neither is a store that
                    // refuses: the caller keeps the statistics total.
                    if (error as? HKError)?.code == .errorNoData {
                        continuation.resume(returning: [])
                        return
                    }
                    continuation.resume(returning: nil)
                    return
                }
                let out = (samples as? [HKQuantitySample] ?? []).map {
                    QuantitySample(
                        source: $0.sourceRevision.source.name,
                        start: $0.startDate, end: $0.endDate,
                        value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    public func sleepSamples(start: Date, end: Date) async throws -> [SleepSample] {
        guard isAvailable,
              let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: error)
                    return
                }
                let out = (samples as? [HKCategorySample] ?? []).map {
                    SleepSample(value: $0.value, start: $0.startDate, end: $0.endDate)
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    public func workouts(start: Date, end: Date) async throws -> [WorkoutSample] {
        guard isAvailable else { return [] }
        // No `.strictStartDate`: a workout that STARTED before the session and
        // ran into it still overlaps it, and that is the one the watch made.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(), predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: error)
                    return
                }
                let out = (samples as? [HKWorkout] ?? []).map(Self.sample)
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// What counts as a lifting session on the watch. Strength training, both
    /// flavours; not core training, not HIIT, which are logged as cardio here.
    static let liftingTypes: Set<HKWorkoutActivityType> = [
        .traditionalStrengthTraining, .functionalStrengthTraining,
    ]

    /// `HKWorkoutActivityType` → the `cardio_logs.kind` the app files it under.
    ///
    /// This dictionary and `liftingTypes` are the only two places in the app
    /// that may name an activity type, and they partition the same space: a
    /// type in neither is a workout the app has no home for (yoga, a swim) and
    /// is offered to nobody rather than filed under a guess.
    static let cardioKinds: [HKWorkoutActivityType: String] = [
        .walking: CardioImport.walk,
        .running: CardioImport.run,
        .cycling: CardioImport.cycling,
        .rowing: CardioImport.rowing,
        .elliptical: CardioImport.elliptical,
        .highIntensityIntervalTraining: CardioImport.hiit,
    ]

    /// The distance type a given activity records against.
    ///
    /// HealthKit files distance under the LIMB doing the work, so asking a bike
    /// ride for `distanceWalkingRunning` returns nothing — silently, which is
    /// how a 40 km ride imports as a bout with no distance and a pace of "—".
    static func distanceType(for activity: HKWorkoutActivityType) -> HKQuantityType? {
        let identifier: HKQuantityTypeIdentifier?
        switch activity {
        case .walking, .running, .elliptical, .highIntensityIntervalTraining:
            identifier = .distanceWalkingRunning
        case .cycling:
            identifier = .distanceCycling
        case .rowing:
            // `distanceRowing` is iOS 18 / macOS 15. The package still builds
            // for an older macOS in tests, so the symbol is gated rather than
            // the whole mapping — an erg bout on an older OS imports its
            // duration, energy and heart rate and simply has no distance.
            if #available(iOS 18.0, macOS 15.0, *) {
                identifier = .distanceRowing
            } else {
                identifier = nil
            }
        default:
            identifier = nil
        }
        return identifier.flatMap(HKQuantityType.quantityType(forIdentifier:))
    }

    /// One workout, read through `statistics(for:)` rather than the totals.
    ///
    /// `HKWorkout.totalDistance` and `totalEnergyBurned` are deprecated and,
    /// more to the point, are whatever the writing app decided to stamp on the
    /// sample. `statistics(for:)` reduces the workout's OWN samples the way the
    /// Health app does, which is what makes an imported figure match the one the
    /// founder can see in Health — and a figure that disagrees with Apple's is a
    /// figure nobody will trust twice.
    static func sample(_ workout: HKWorkout) -> WorkoutSample {
        let distance = distanceType(for: workout.workoutActivityType)
            .flatMap { workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }

        let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
            .flatMap { workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .kilocalorie()) }

        // Average, not sum: a heart rate is a rate. `.count()/.minute()` is the
        // unit HealthKit stores bpm in, and naming it wrong here would return a
        // plausible number in the wrong scale — the failure the file header
        // warns about.
        let hr = HKQuantityType.quantityType(forIdentifier: .heartRate)
            .flatMap {
                workout.statistics(for: $0)?.averageQuantity()?
                    .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }

        // Ascent is metadata, not a sample type: only the app that recorded the
        // workout can supply it, so an indoor treadmill bout simply has none.
        let ascent = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
            .doubleValue(for: .meter())

        return WorkoutSample(
            uuid: workout.uuid,
            start: workout.startDate,
            end: workout.endDate,
            isLifting: liftingTypes.contains(workout.workoutActivityType),
            cardioKind: cardioKinds[workout.workoutActivityType],
            distanceM: distance,
            activeKcal: energy,
            avgHr: hr,
            elevationM: ascent
        )
    }

    // MARK: - Types and units

    static func objectType(_ identifier: String) -> HKObjectType? {
        if identifier == HealthCatalogue.workoutTypeIdentifier {
            return HKObjectType.workoutType()
        }
        if identifier.hasPrefix("HKQuantityTypeIdentifier") {
            return HKObjectType.quantityType(forIdentifier: .init(rawValue: identifier))
        }
        if identifier.hasPrefix("HKCategoryTypeIdentifier") {
            return HKObjectType.categoryType(forIdentifier: .init(rawValue: identifier))
        }
        return nil
    }

    /// The unit each metric is STORED in, which is the unit the rest of the app
    /// already assumes. Anything not named here is a count.
    static func unit(for identifier: String) -> HKUnit {
        switch identifier {
        case "HKQuantityTypeIdentifierDistanceWalkingRunning":
            return .meter()                                   // `distance_m`
        case "HKQuantityTypeIdentifierActiveEnergyBurned",
             // Basal is READ-ONLY here and has no `HealthKey`: nothing ingests
             // it into `daily_logs`. It is summed over one bout's window so the
             // cardio sheet can offer a TOTAL energy figure (active + resting),
             // which is the number Apple's own Fitness app shows and the one a
             // person compares against. Without this case it fell to the
             // `default` below — not a `Dietary` prefix, so `.count()` — and a
             // kilocalorie sum came back as a raw count with no error.
             "HKQuantityTypeIdentifierBasalEnergyBurned",
             "HKQuantityTypeIdentifierDietaryEnergyConsumed":
            return .kilocalorie()
        case "HKQuantityTypeIdentifierAppleExerciseTime",
             "HKQuantityTypeIdentifierAppleStandTime",
             "HKQuantityTypeIdentifierTimeInDaylight":
            return .minute()
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
            return .secondUnit(with: .milli)
        case "HKQuantityTypeIdentifierRestingHeartRate",
             "HKQuantityTypeIdentifierHeartRate":
            return HKUnit.count().unitDivided(by: .minute())
        case "HKQuantityTypeIdentifierRespiratoryRate":
            return HKUnit.count().unitDivided(by: .minute())
        case "HKQuantityTypeIdentifierVO2Max":
            // ml/(kg·min) — VO₂max's only sensible unit, and HealthKit will not
            // convert it to anything else.
            return HKUnit.literUnit(with: .milli)
                .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        case "HKQuantityTypeIdentifierOxygenSaturation",
             "HKQuantityTypeIdentifierBodyFatPercentage":
            // A 0–1 fraction. `HealthCatalogue` scales it ×100 — the unit fix and
            // the scale factor are the same decision, made once each side.
            return .percent()
        case "HKQuantityTypeIdentifierBodyMass",
             "HKQuantityTypeIdentifierLeanBodyMass":
            return HKUnit.gramUnit(with: .kilo)
        case "HKQuantityTypeIdentifierBodyMassIndex":
            return .count()
        case "HKQuantityTypeIdentifierAppleSleepingWristTemperature":
            return .degreeCelsius()
        case "HKQuantityTypeIdentifierDietaryWater":
            return HKUnit.literUnit(with: .milli)             // `water_ml`
        case "HKQuantityTypeIdentifierDietarySodium",
             "HKQuantityTypeIdentifierDietaryPotassium",
             "HKQuantityTypeIdentifierDietaryCalcium",
             "HKQuantityTypeIdentifierDietaryIron",
             "HKQuantityTypeIdentifierDietaryMagnesium",
             "HKQuantityTypeIdentifierDietaryVitaminC":
            return HKUnit.gramUnit(with: .milli)
        case "HKQuantityTypeIdentifierDietaryVitaminD":
            // Micrograms. `HealthUnits.vitaminDToIU` converts on the way into
            // the micros bundle, because every target in the app is in IU.
            return HKUnit.gramUnit(with: .micro)
        default:
            // Every remaining dietary macro is grams; steps and flights are
            // counts, and `.gram()` is not a legal unit for them — so the two
            // families are split by prefix rather than listed.
            return identifier.hasPrefix("HKQuantityTypeIdentifierDietary") ? .gram() : .count()
        }
    }
}
#endif
