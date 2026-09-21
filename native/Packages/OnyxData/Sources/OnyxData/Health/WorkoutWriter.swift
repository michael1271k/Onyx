import Foundation
import OnyxCore

/// The phone's `HKWorkout` for a session the watch did not run.
/// Expansion W5, founder decisions 8 and 9.
///
/// ── WHEN THE PHONE WRITES, AND WHEN IT MUST NOT ─────────────────────────────
/// Before this wave the phone never wrote to Health (`toShare: []`), so a
/// session logged with no watch on the wrist left no workout for the rings.
/// The phone writes now — but only when nobody else already has:
///
///   · the WATCH ran this session (any `set_events` row from another device,
///     or an own `HKWorkout` already overlapping it) — `finishWorkout` on the
///     wrist wrote the workout, and a second one would double the rings;
///   · a FOREIGN strength workout overlaps (Hevy) — decision 8: Onyx does not
///     write its own over it and keeps its heart rate internally.
///
/// `decide` is the whole of that rule, pure over `HealthReading`, so it is
/// tested with a fake reader on macOS; `HealthWorkoutWriter` below is the
/// twenty lines of `HKWorkoutBuilder` that act on it, iOS only.
///
/// ── WHAT THE WORKOUT CARRIES (decision 9) ───────────────────────────────────
/// Heart rate: nothing. The phone has no sensor, and the passive readings a
/// watch left in the interval are already Health's — re-saving them would
/// duplicate them, and `SessionTelemetry` reads the interval anyway.
/// Energy: if Health already holds active energy inside the interval (a watch
/// worn but not running the app), none — the rings have it. Otherwise the
/// session's own figure, stamped `HKMetadataKeyWasUserEntered` when the
/// athlete typed it and `app.onyx.estimated = true` when `Estimates` did.
public enum WorkoutWriter {

    /// What to do about one finished session.
    public enum Decision: Equatable, Sendable {
        /// Write the workout, with this energy sample (nil = none).
        case write(energyKcal: Int?, estimated: Bool)
        case skip(Reason)

        public enum Reason: Equatable, Sendable {
            case noInterval
            case watchRan
            case ownWorkoutExists
            case foreignOverlap
        }
    }

    /// Metadata keys the phone stamps. `sessionId` is what lets a later read
    /// find THIS session's workout without a time window.
    public static let sessionIdKey = "app.onyx.sessionId"
    public static let estimatedKey = "app.onyx.estimated"

    /// The guard.
    ///
    /// `events` is the session's own log and `localDeviceId` this store's
    /// device: an event stamped by any other device means the watch logged
    /// into this session, and the watch writes its own workout on finish.
    ///
    /// `watchWasLive` is the phone's other signal: the wrist starts its
    /// `HKWorkoutSession` the moment it mirrors a phone session and sends
    /// its heart rate up, whether or not a set is ever ticked there — so a
    /// bpm received during the interval means a workout is coming from the
    /// watch even when every event is the phone's.
    public static func decide(
        session: WorkoutSession, events: [SetEvent], localDeviceId: String,
        watchWasLive: Bool = false,
        reader: any HealthReading, ownBundleId: String
    ) async -> Decision {
        guard let start = session.startedAt, let end = session.endedAt, end > start else {
            return .skip(.noInterval)
        }
        if watchWasLive || events.contains(where: { $0.deviceId != localDeviceId }) {
            return .skip(.watchRan)
        }
        switch await reader.liftingOverlap(start: start, end: end, ownBundleId: ownBundleId) {
        case .own: return .skip(.ownWorkoutExists)
        case .foreign: return .skip(.foreignOverlap)
        case .none: break
        }
        let existing = (try? await reader.quantity(
            "HKQuantityTypeIdentifierActiveEnergyBurned", reduce: .sum, start: start, end: end
        )) ?? 0
        if existing > 0 {
            return .write(energyKcal: nil, estimated: false)
        }
        return .write(energyKcal: session.caloriesBurned, estimated: session.caloriesEstimated)
    }
}

#if os(iOS) && canImport(HealthKit)
import HealthKit

/// The `HKWorkoutBuilder` half. One call, one workout.
public struct HealthWorkoutWriter: Sendable {

    private let store = HKHealthStore()

    public init() {}

    /// Save the workout and return its uuid, or nil when the decision was a
    /// skip or the store is unavailable. Throws only for a HealthKit refusal.
    ///
    /// `extra` is metadata the caller stamps beside Onyx's own — the DEBUG
    /// seed marks its workout so it can be deleted on the next run.
    @discardableResult
    public func write(
        session: WorkoutSession, decision: WorkoutWriter.Decision, extra: [String: Bool] = [:]
    ) async throws -> UUID? {
        guard case .write(let kcal, let estimated) = decision,
              HKHealthStore.isHealthDataAvailable(),
              let start = session.startedAt, let end = session.endedAt, end > start
        else { return nil }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        try await builder.beginCollection(at: start)
        var metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: true,
            WorkoutWriter.sessionIdKey: session.id,
        ]
        for (key, value) in extra { metadata[key] = value }
        if let kcal, kcal > 0 {
            var sampleMetadata: [String: Any] = [
                HKMetadataKeyWasUserEntered: !estimated,
                WorkoutWriter.estimatedKey: estimated,
            ]
            for (key, value) in extra { sampleMetadata[key] = value }
            let sample = HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(kcal)),
                start: start, end: end,
                metadata: sampleMetadata
            )
            try await builder.addSamples([sample])
            metadata[WorkoutWriter.estimatedKey] = estimated
        }
        try await builder.addMetadata(metadata)
        try await builder.endCollection(at: end)
        let workout = try await builder.finishWorkout()
        return workout?.uuid
    }
}
#endif
