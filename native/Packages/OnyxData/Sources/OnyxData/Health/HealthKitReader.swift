#if canImport(HealthKit)
import Foundation
import HealthKit
import OnyxCore
import os

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
    /// This app's bundle id — what `heartRateSeries` and `WorkoutProvenance`
    /// call "own". Defaulted from the running process; injectable so the
    /// TelemetrySeed and a test can name it.
    let ownBundleId: String

    public init(ownBundleId: String = Bundle.main.bundleIdentifier ?? "") {
        self.ownBundleId = ownBundleId
    }

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// The sample types the PHONE writes (Expansion W5): the `HKWorkout` a
    /// phone-only session leaves behind, and the active-energy sample it
    /// carries when Health held none. The watch asks for its own in
    /// `WorkoutSessionController.requestAuthorization`. Empty on macOS,
    /// where tests run and nothing is ever written.
    static var shareTypes: Set<HKSampleType> {
        #if os(iOS)
        return [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        #else
        return []
        #endif
    }

    public func requestAuthorization(read: [String]) async throws -> Bool {
        guard isAvailable else { return false }
        let types = Set(read.compactMap(Self.objectType))
        guard !types.isEmpty else { return false }
        try await store.requestAuthorization(toShare: Self.shareTypes, read: types)
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

    /// The series, from sources the app may cite (Expansion W5).
    ///
    /// ── WHY A SOURCE FILTER AND NOT `predicateForObjects(from: workout)` ────
    /// The workout-scoped predicate answers only for samples the builder
    /// attached, and a phone-only session has no builder collecting heart
    /// rate at all — its samples are the watch's passive readings, which
    /// Health files under the WATCH (`com.apple.health.<uuid>`), not under
    /// any workout. One interval query with the source rule below serves
    /// both shapes: Apple's sensors and this app's own targets are cited,
    /// a foreign app's bpm is not.
    public func heartRateSeries(start: Date, end: Date) async throws -> [HRSample] {
        guard isAvailable, end > start else { return [] }
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let unit = HKUnit.count().unitDivided(by: .minute())
        let own = ownBundleId
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: error)
                    return
                }
                let out = (samples as? [HKQuantitySample] ?? []).compactMap { sample -> HRSample? in
                    let bundle = sample.sourceRevision.source.bundleIdentifier
                    guard Self.mayCite(bundle, own: own) else { return nil }
                    let bpm = sample.quantity.doubleValue(for: unit)
                    guard bpm.isFinite, bpm > 0 else { return nil }
                    return HRSample(at: sample.startDate, bpm: Int(bpm.rounded()))
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Apple's own sensors, or this app on either device.
    static func mayCite(_ bundle: String, own: String) -> Bool {
        bundle.hasPrefix("com.apple.") || WorkoutProvenance.origin(sourceBundleId: bundle, sourceName: nil, ownBundleId: own).isOwn
    }

    /// One tick per heart-rate change until `until`. An `HKObserverQuery`,
    /// stopped by the deadline; the completion handler is always called, or
    /// HealthKit stops delivering after three unanswered notifications.
    public func heartRateChanges(until: Date) -> AsyncStream<Void> {
        AsyncStream { continuation in
            guard isAvailable, until > Date() else { continuation.finish(); return }
            // The first callback fires on `execute`, before anything could
            // have landed; only the changes after it are changes.
            let primed = OSAllocatedUnfairLock(initialState: false)
            let query = HKObserverQuery(sampleType: HKQuantityType(.heartRate), predicate: nil) { _, completion, error in
                let isChange = primed.withLock { state -> Bool in
                    defer { state = true }
                    return state
                }
                if error == nil, isChange { continuation.yield() }
                completion()
            }
            store.execute(query)
            let deadline = Task {
                try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
                continuation.finish()
            }
            continuation.onTermination = { [store] _ in
                store.stop(query)
                deadline.cancel()
            }
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

    /// The kind a workout is filed under, reading the one metadata key that
    /// splits a kind: an INDOOR walk is a treadmill (overhaul C2). Outdoor, or
    /// a writer that never stamped the key, stays a walk — the key's absence
    /// is not evidence of a treadmill. Every other activity ignores it.
    static func cardioKind(_ type: HKWorkoutActivityType, indoor: Bool?) -> String? {
        if type == .walking, indoor == true { return CardioImport.treadmill }
        return cardioKinds[type]
    }

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
            cardioKind: cardioKind(
                workout.workoutActivityType,
                indoor: workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool
            ),
            distanceM: distance,
            activeKcal: energy,
            avgHr: hr,
            elevationM: ascent,
            sourceBundleId: workout.sourceRevision.source.bundleIdentifier,
            sourceName: workout.sourceRevision.source.name,
            sets: metadataSets(workout.metadata),
            energyEstimated: (workout.metadata?[WorkoutWriter.estimatedKey] as? Bool) ?? false
        )
    }

    /// A set count a foreign writer stamped, under whatever key it chose.
    ///
    /// No app publishes its metadata keys, so this is the loosest honest
    /// read: any key whose name says "set" and whose value is a whole number.
    /// Nil is the ordinary answer and the compare card prints "—" for it.
    static func metadataSets(_ metadata: [String: Any]?) -> Int? {
        guard let metadata else { return nil }
        // Sorted, so two matching keys answer the same way twice; booleans
        // skipped, so `hasSupersets: true` does not read as one set.
        for key in metadata.keys.sorted() where key.lowercased().contains("set") {
            let value = metadata[key]
            if let n = value as? NSNumber {
                if CFGetTypeID(n) == CFBooleanGetTypeID() { continue }
                if n.intValue >= 0 { return n.intValue }
            }
            if let text = value as? String, let n = Int(text), n >= 0 { return n }
        }
        return nil
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
             "HKQuantityTypeIdentifierHeartRate",
             // A DROP in bpm, stored as a positive rate — 28 means the heart
             // fell 28 beats per minute in the minute after the workout.
             "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute":
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
             "HKQuantityTypeIdentifierDietaryVitaminC",
             "HKQuantityTypeIdentifierDietaryZinc",
             "HKQuantityTypeIdentifierDietaryVitaminB6",
             "HKQuantityTypeIdentifierDietaryVitaminE",
             "HKQuantityTypeIdentifierDietaryCholesterol":
            return HKUnit.gramUnit(with: .milli)
        case "HKQuantityTypeIdentifierDietaryIodine",
             "HKQuantityTypeIdentifierDietaryVitaminA",
             "HKQuantityTypeIdentifierDietaryVitaminB12",
             "HKQuantityTypeIdentifierDietaryVitaminK",
             "HKQuantityTypeIdentifierDietaryBiotin":
            // Micrograms, the unit their targets are written in. Falling to
            // the `default` below would read them in GRAMS — a 900 µg vitamin
            // A day stored as 0.0009, the exact wrong-but-plausible failure
            // the file header warns about.
            return HKUnit.gramUnit(with: .micro)
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
