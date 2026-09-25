#if canImport(HealthKit)
import Foundation
import HealthKit
import OnyxCore
#if os(watchOS)
import Observation
import os
#endif

/// Where an anchored query resumes from, one per sample type (Precision D2).
///
/// ── WHY IT IS PERSISTED ─────────────────────────────────────────────────────
/// A query with no anchor starts from the beginning of its predicate: every
/// launch would re-deliver the whole day, and a background wake would spend
/// its few seconds re-reading samples it already folded. The anchor is the
/// position; `NSKeyedArchiver` is the only serialisation `HKQueryAnchor` has.
///
/// Unfenced beyond `canImport(HealthKit)` so `swift test` on macOS can prove
/// the round trip; the query that uses it is watch-only.
public enum VitalsAnchor {

    static func key(_ identifier: String) -> String { "onyx.watch.anchor.\(identifier)" }

    public static func load(_ identifier: String, from defaults: UserDefaults = .standard) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: key(identifier)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    /// Nil forgets the anchor.
    public static func save(_ anchor: HKQueryAnchor?, _ identifier: String, to defaults: UserDefaults = .standard) {
        guard let anchor,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        else {
            defaults.removeObject(forKey: key(identifier))
            return
        }
        defaults.set(data, forKey: key(identifier))
    }
}

#if os(watchOS)
/// Heart rate and HRV OUTSIDE a workout (Precision D2, decision Q23 C).
///
/// ── WHAT IT ADDS TO `WorkoutSessionController` ──────────────────────────────
/// The workout controller's builder only runs inside an `HKWorkoutSession`,
/// so the Heart petal and the Heart Rate complication went stale the moment
/// a session closed and stayed stale until the next one (`LastHeartRate` was
/// written by `publishLiveSnapshot` alone). The system samples heart rate all
/// day on the wrist; this reads what it saved.
///
/// ── THREE READS, ONE FOLD ───────────────────────────────────────────────────
/// 1. `refresh()` — a one-shot `HKAnchoredObjectQuery` per type from its
///    persisted anchor, limited to the last 24 hours. Run at launch and each
///    time the Glance or the Heart detail appears.
/// 2. Under `ONYX_ADP` — an `HKObserverQuery` per type with
///    `enableBackgroundDelivery(.hourly)`: the system wakes the app, the
///    handler runs the same one-shot fetch and calls completion after it.
///    Gated because the entitlement cannot be signed on a personal team
///    (Gate 0, `HealthObservers`' header); without it the reads are the
///    launch/appear ones and the petal is "fresh as of the last glance".
/// 3. `startStream()` — while the Heart detail is on screen, a long-running
///    anchored query with an `updateHandler`. No `HKWorkoutSession`: outside
///    a workout the sensor keeps the system's own cadence, and a query cannot
///    make it sample faster — it only hears each sample the moment it lands.
///
/// Every read ends in `fold`: the 24 h `HeartTrail`, and `LastHeartRate` only
/// when a sample is NEWER than what is stored (`WatchHeart.adopt`) — a
/// background delivery never overwrites the rate a running workout wrote.
@MainActor
@Observable
public final class WatchVitals {

    /// The newest heart rate this wrist knows, from either source.
    public private(set) var heart: LastHeartRate?
    /// The last 24 hours, thinned.
    public private(set) var trail: HeartTrail
    /// The newest HRV (SDNN, ms).
    public private(set) var hrv: LastHRV?
    public private(set) var isStreaming = false
    /// When the stream last delivered, for the cadence the wave record reports.
    public private(set) var lastDelivery: Date?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var observers: [HKObserverQuery] = []
    @ObservationIgnored private var stream: HKAnchoredObjectQuery?
    /// Called when `heart` moved — the model reloads the heart complications
    /// (WidgetKit stays out of this package).
    @ObservationIgnored public var onHeart: (@MainActor (LastHeartRate) -> Void)?
    @ObservationIgnored private let log = Logger(subsystem: "app.onyx.watch", category: "vitals")

    // Computed and `nonisolated`: the HealthKit handlers below run on
    // HealthKit's own queue, and a stored static on a `@MainActor` class is
    // main-actor state they may not touch.
    nonisolated private static var heartRate: HKQuantityType { HKQuantityType(.heartRate) }
    nonisolated private static var variability: HKQuantityType { HKQuantityType(.heartRateVariabilitySDNN) }

    public init() {
        trail = HeartTrail.load() ?? HeartTrail()
        heart = LastHeartRate.load()
        hrv = LastHRV.load()
    }

    /// The read types this adds to the workout controller's request.
    public static var readTypes: Set<HKObjectType> { [heartRate, variability] }

    /// Catch up, and register for wakes. Idempotent.
    public func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        refresh()
        #if ONYX_ADP
        guard observers.isEmpty else { return }
        for type in [Self.heartRate, Self.variability] {
            let id = type.identifier
            let query = HKObserverQuery(sampleType: type, predicate: nil) { @Sendable [weak self] _, completion, error in
                // Called only after the fetch has folded: HealthKit gives a
                // background wake until completion, and not after.
                nonisolated(unsafe) let completion = completion
                guard error == nil else { return completion() }
                Task { @MainActor in
                    guard let self else { return completion() }
                    self.fetch(id == Self.heartRate.identifier ? Self.heartRate : Self.variability) { completion() }
                }
            }
            store.execute(query)
            observers.append(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { @Sendable [log] ok, error in
                log.notice("background delivery \(id, privacy: .public): \(ok ? "on" : String(describing: error), privacy: .public)")
            }
        }
        #endif
    }

    /// One anchored fetch of both types.
    public func refresh() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        fetch(Self.heartRate)
        fetch(Self.variability)
    }

    /// Hear each heart-rate sample as it lands, while the Heart detail is up.
    public func startStream() {
        guard stream == nil, HKHealthStore.isHealthDataAvailable() else { return }
        let since = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-600), end: nil)
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, (any Error)?) -> Void
            = { [weak self] _, samples, _, _, _ in
                let heart = Self.heartSamples(samples)
                Task { @MainActor in self?.fold(heart: heart, streamed: true) }
            }
        let query = HKAnchoredObjectQuery(type: Self.heartRate, predicate: since, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: handler)
        query.updateHandler = handler
        store.execute(query)
        stream = query
        isStreaming = true
        log.notice("heart stream started")
    }

    public func stopStream() {
        guard let stream else { return }
        store.stop(stream)
        self.stream = nil
        isStreaming = false
        log.notice("heart stream stopped")
    }

    // MARK: - The fetch

    private func fetch(_ type: HKQuantityType, then done: (@Sendable () -> Void)? = nil) {
        let identifier = type.identifier
        let since = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-HeartTrail.window), end: nil)
        let query = HKAnchoredObjectQuery(
            type: type, predicate: since, anchor: VitalsAnchor.load(identifier), limit: HKObjectQueryNoLimit
        ) { @Sendable [weak self] _, samples, _, anchor, error in
            // Saved here, off the main actor: `UserDefaults` is thread-safe
            // and the anchor never has to cross an isolation boundary.
            if error == nil { VitalsAnchor.save(anchor, identifier) }
            if identifier == Self.heartRate.identifier {
                let heart = Self.heartSamples(samples)
                Task { @MainActor in
                    self?.fold(heart: heart, streamed: false)
                    done?()
                }
            } else {
                let latest = Self.hrvSample(samples)
                Task { @MainActor in
                    self?.fold(hrv: latest)
                    done?()
                }
            }
        }
        store.execute(query)
    }

    nonisolated private static func heartSamples(_ samples: [HKSample]?) -> [HeartTrail.Sample] {
        (samples as? [HKQuantitySample] ?? []).map {
            HeartTrail.Sample(at: $0.endDate, bpm: Int($0.quantity.doubleValue(for: .count().unitDivided(by: .minute())).rounded()))
        }
    }

    nonisolated private static func hrvSample(_ samples: [HKSample]?) -> LastHRV? {
        (samples as? [HKQuantitySample] ?? []).max { $0.endDate < $1.endDate }.map {
            LastHRV(ms: Int($0.quantity.doubleValue(for: .secondUnit(with: .milli)).rounded()), at: $0.endDate)
        }
    }

    // MARK: - The fold

    private func fold(heart samples: [HeartTrail.Sample], streamed: Bool) {
        guard !samples.isEmpty else { return }
        let now = Date()
        if streamed {
            if let lastDelivery {
                log.notice("heart stream delivered \(samples.count) after \(Int(now.timeIntervalSince(lastDelivery)))s")
            }
            lastDelivery = now
        }
        trail.merge(samples, now: now)
        trail.save()
        guard let adopted = WatchHeart.adopt(samples, over: LastHeartRate.load() ?? heart) else { return }
        adopted.save()
        heart = adopted
        onHeart?(adopted)
    }

    private func fold(hrv sample: LastHRV?) {
        guard let sample, sample.at > (hrv?.at ?? .distantPast) else { return }
        sample.save()
        hrv = sample
    }

    /// The running workout wrote a rate (`publishLiveSnapshot`): the petal
    /// follows it without a HealthKit round trip. The trail picks the same
    /// samples up at the next fetch — the builder saves them to Health.
    public func noteWorkout(_ reading: LastHeartRate) {
        heart = reading
    }

    #if DEBUG
    /// The shot loop's seed: a day of rate so the Heart detail and the Live
    /// Heart face have something to draw on a simulator with no sensor.
    public func seedDebug(_ trail: HeartTrail, heart: LastHeartRate, hrv: LastHRV?) {
        self.trail = trail
        trail.save()
        self.heart = heart
        heart.save()
        self.hrv = hrv
        hrv?.save()
    }
    #endif
}
#endif
#endif
