#if os(watchOS)
import Foundation
import HealthKit
import Observation
import os

/// The `HKWorkoutSession` the whole watch app sits inside.
///
/// ── IT IS NOT A HEART-RATE FEATURE. IT IS THE RUNTIME ───────────────────────
/// Without a running workout session, watchOS suspends this app within seconds
/// of the wrist dropping. The rest countdown stops, the haptic at zero never
/// fires, and raising your wrist gets a cold launch instead of the set you were
/// on. Every screen in `OnyxWatch` assumes it is still running while you are
/// under a bar, and this is the only thing that makes that true.
///
/// It needs `WKBackgroundModes: [workout-processing]` in the target's
/// `Info.plist`. The entitlement is `com.apple.developer.healthkit` and the two
/// usage strings; all four are in `project.yml`.
///
/// Heart rate and active energy are the second-order benefit — `SessionMetrics`
/// already has somewhere to put them, and `closeSession` already carries
/// `avgBpm`/`calories` to the server.
///
/// ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────
/// No route, no segments, no interval events. A strength session is one
/// continuous block as far as HealthKit is concerned; the set structure lives in
/// `set_events` where it can be folded, and duplicating it as workout events
/// would be a second history nobody reads.
///
/// `NSObject` because `HKWorkoutSessionDelegate` and
/// `HKLiveWorkoutBuilderDelegate` both inherit `NSObjectProtocol`, which Swift
/// cannot satisfy without the base class.
@MainActor
@Observable
public final class WorkoutSessionController: NSObject {

    /// Live heart rate in beats per minute, or nil before the first sample.
    ///
    /// The first sample takes several seconds to arrive — the sensor has to
    /// settle — and a view that draws `0` in the meantime is claiming a reading
    /// it does not have. Nil renders as a dash.
    public private(set) var heartRate: Int?
    /// Active energy for the session so far, kilocalories.
    public private(set) var activeCalories: Int?
    /// Average heart rate across the whole session, which is what
    /// `workout_sessions.avg_bpm` stores — not the last sample.
    public private(set) var averageHeartRate: Int?

    /// The last readings, oldest first, for the rest screen's sparkline (W3).
    ///
    /// ── A BUFFER AND NOT A QUERY, AND WHY THAT IS THE HONEST SHAPE ──────────
    /// `HKLiveWorkoutBuilder` hands out STATISTICS, not a series:
    /// `mostRecentQuantity()` is one number and there is no "the last minute of
    /// samples" on it. The alternative is an `HKAnchoredObjectQuery` running
    /// beside the builder for the same data the builder is already collecting —
    /// a second HealthKit subscription, on the battery you need for the rest of
    /// the workout, to reconstruct something this process has watched go past.
    ///
    /// So the readings are kept as they arrive. What that costs in honesty is
    /// stated rather than hidden: these are the samples THIS LAUNCH saw, at
    /// whatever cadence HealthKit delivered them (roughly one every five
    /// seconds while a workout session is running, and not a fixed grid). It is
    /// a shape, not a time series — the rest screen draws it without an axis
    /// for exactly that reason, and nothing derives a number from it.
    ///
    /// Capped at `sampleCapacity`. An app relaunched mid-session starts empty,
    /// which draws no sparkline rather than a line with a hole in it.
    public private(set) var recentSamples: [Int] = []

    /// 60 readings — the plan's number, and about five minutes at HealthKit's
    /// in-workout cadence, which is the span a rest screen is open over.
    public static let sampleCapacity = 60

    public private(set) var isRunning = false
    /// True between `pause()` and `resume()`. The training log keeps its own
    /// pause ledger in `set_events` (`AppDatabase.pauseLedger`) and THAT is the
    /// number the clock reads; this is only what HealthKit believes, so the two
    /// can disagree after a relaunch without anything being wrong.
    public private(set) var isPaused = false
    /// The last thing that went wrong, for a diagnostics row. Not shown mid-set:
    /// a person under a bar cannot act on it.
    public private(set) var lastError: String?

    private let store = HKHealthStore()
    /// `.notice`, never `.info`: info lines are memory-only and `log show`
    /// never returns them, and "did the workout session start" is a question
    /// a gate has to answer from the device's log (App Store W4).
    private let log = Logger(subsystem: "app.onyx.watch", category: "workout")
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    public override init() { super.init() }

    /// Ask for the types this app reads and writes.
    ///
    /// ── THE WRITE HALF IS WHAT MAKES THE SESSION LEGAL ──────────────────────
    /// `HKWorkoutSession` needs share access to `HKObjectType.workoutType()`;
    /// without it `beginCollection` fails and the app has no runtime. Heart rate
    /// and active energy are read so the hero can show them, and are written by
    /// `finishWorkout` as samples attached to the workout.
    ///
    /// Called once, from the watch app's first launch. A denial is not fatal to
    /// LOGGING — the log is a local database and does not care — but it costs
    /// the background runtime, so the caller shows it plainly.
    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        // HRV since Precision D2: `WatchVitals` reads heart rate and HRV
        // outside a workout, and one prompt is kinder than two.
        let read = Set<HKObjectType>([
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]).union(WatchVitals.readTypes)
        try await store.requestAuthorization(toShare: share, read: read)
    }

    /// Start the session. Idempotent — a second call while one is running is a
    /// no-op rather than a second session, which HealthKit would refuse and
    /// which would leave the app with a builder it no longer owns.
    /// ── THE GUARD IS THE SESSION, NOT `isRunning` (W3) ──────────────────────
    /// It was `!isRunning`, and pausing broke it: the delegate sets `isRunning`
    /// from the HealthKit state, so a PAUSED session reads as not running, and
    /// the next `adopt` — a rejoin, a context arrival — would have built a
    /// second `HKWorkoutSession` over the top of the paused one. The first
    /// session's builder is then orphaned mid-collection and its energy never
    /// reaches the workout. The object's existence is the thing that must be
    /// unique, so it is what the guard tests.
    public func start(startDate: Date = Date()) {
        guard session == nil, HKHealthStore.isHealthDataAvailable() else { return }

        let configuration = HKWorkoutConfiguration()
        // The category the rings and the Fitness app file it under. Indoor
        // because a gym is, and because it tells HealthKit not to expect GPS.
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { [weak self] _, error in
                guard let error else { return }
                Task { @MainActor in self?.lastError = error.localizedDescription }
            }
            isRunning = true
            log.notice("HKWorkoutSession started at \(startDate, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            log.error("HKWorkoutSession could not start: \(error.localizedDescription, privacy: .public)")
            // Deliberately not rethrown. A watch that cannot start a workout
            // session can still log every set into its own store and hand them
            // to the phone; it simply loses the background runtime. Refusing to
            // open the logger over it would be the worse failure.
        }
    }

    /// End the session and write the `HKWorkout`.
    ///
    /// Awaited rather than fire-and-forget: the caller closes the local session
    /// row straight afterwards and wants `averageHeartRate` and
    /// `activeCalories` to have settled, because those are what reach
    /// `workout_sessions.avg_bpm` and `.calories_burned`.
    ///
    /// Errors are swallowed into `lastError` for the same reason `start` does:
    /// a workout that will not save to Health must not stop the training log
    /// from closing. The sets are the record; the `HKWorkout` is a courtesy to
    /// the rings.
    @discardableResult
    public func end(endDate: Date = Date()) async -> SessionMetricsSample {
        guard let session, let builder else { return sample() }
        isRunning = false
        isPaused = false
        session.end()
        await withCheckedContinuation { continuation in
            builder.endCollection(withEnd: endDate) { _, error in
                if let error {
                    Task { @MainActor in self.lastError = error.localizedDescription }
                }
                continuation.resume()
            }
        }
        await withCheckedContinuation { continuation in
            builder.finishWorkout { _, error in
                if let error {
                    Task { @MainActor in self.lastError = error.localizedDescription }
                }
                continuation.resume()
            }
        }
        self.session = nil
        self.builder = nil
        return sample()
    }

    /// Stop the session clock without ending the session (W3).
    ///
    /// ── WHY HEALTHKIT HAS TO HEAR ABOUT IT AT ALL ───────────────────────────
    /// The training log's pause lives in `set_events` and is what the elapsed
    /// clock reads. This is the other half: a paused `HKWorkoutSession` stops
    /// accruing active energy, so a workout left paused through a coffee does
    /// not hand the rings twenty minutes of exercise nobody did. The two are
    /// written together by the caller and neither is derived from the other —
    /// the log survives a relaunch and this does not.
    ///
    /// Idempotent, like the log's own pause: HealthKit refuses a pause on a
    /// session that is not running, so the guard is the whole implementation.
    public func pause() {
        guard let session, session.state == .running else { return }
        session.pause()
        isPaused = true
    }

    public func resume() {
        guard let session, session.state == .paused else { return }
        session.resume()
        isPaused = false
    }

    /// Stop without writing anything to Health — the discard path.
    ///
    /// Its caller since W3 is `WatchModel.cancelSession`, reached by holding
    /// the session clock. Before that it had none, which is why the watch had
    /// no way to throw a workout away.
    public func cancel() {
        guard let session else { return }
        isRunning = false
        isPaused = false
        session.end()
        builder?.discardWorkout()
        self.session = nil
        self.builder = nil
        heartRate = nil
        activeCalories = nil
        averageHeartRate = nil
        recentSamples = []
    }

    private func sample() -> SessionMetricsSample {
        SessionMetricsSample(avgBpm: averageHeartRate, calories: activeCalories)
    }

    #if DEBUG
    /// Stand in for the sensor, so the rest screen's sparkline can be
    /// photographed. A simulator has no heart, and `recentSamples` is
    /// `private(set)` precisely so nothing but HealthKit fills it in a shipping
    /// build — this is the same DEBUG-only door `WatchModel.seedDebugRest` uses
    /// one layer up, and it goes through the same cap.
    public func seedDebugSamples(_ values: [Int]) {
        recentSamples = Array(values.suffix(Self.sampleCapacity))
        heartRate = values.last
        averageHeartRate = values.isEmpty ? nil : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
    #endif

    fileprivate func absorb(_ types: Set<HKSampleType>, from builder: HKLiveWorkoutBuilder) {
        for type in types {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = builder.statistics(for: quantityType)
            else { continue }

            switch quantityType {
            case HKQuantityType(.heartRate):
                let unit = HKUnit.count().unitDivided(by: .minute())
                // `mostRecentQuantity` for the live number and
                // `averageQuantity` for the one that is stored: the hero shows
                // what your heart is doing now, and `avg_bpm` is a fact about
                // the whole session. Storing the last sample as the average is
                // how a workout ends up recorded at whatever your heart rate
                // happened to be while you were putting the plates away.
                if let now = statistics.mostRecentQuantity()?.doubleValue(for: unit) {
                    let bpm = Int(now.rounded())
                    heartRate = bpm
                    // ── ONLY A READING THAT MOVED ───────────────────────────
                    // `didCollectDataOf` fires for energy as well, and both
                    // branches re-read the same heart-rate statistics object —
                    // so appending unconditionally would stamp the same bpm
                    // several times and draw a sparkline whose flat runs are
                    // an artefact of the delivery cadence rather than of the
                    // heart. Equal-to-last is dropped; the line is a shape,
                    // not a time series, and the header says so.
                    if recentSamples.last != bpm {
                        recentSamples.append(bpm)
                        if recentSamples.count > Self.sampleCapacity {
                            recentSamples.removeFirst(recentSamples.count - Self.sampleCapacity)
                        }
                    }
                }
                if let mean = statistics.averageQuantity()?.doubleValue(for: unit) {
                    averageHeartRate = Int(mean.rounded())
                }
            case HKQuantityType(.activeEnergyBurned):
                if let total = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                    activeCalories = Int(total.rounded())
                }
            default:
                continue
            }
        }
    }
}

/// What a finished workout session knows that the training log does not.
public struct SessionMetricsSample: Sendable, Equatable {
    public var avgBpm: Int?
    public var calories: Int?

    public init(avgBpm: Int? = nil, calories: Int? = nil) {
        self.avgBpm = avgBpm
        self.calories = calories
    }
}

// MARK: - Delegates

/// ── `@unchecked Sendable` AND WHY IT IS HONEST HERE ─────────────────────────
/// HealthKit calls both delegates on its own queue and neither protocol is
/// annotated for the main actor, so the conformance cannot be `@MainActor`. Both
/// methods below do exactly one thing: hop to the main actor and touch the
/// controller's state there. Nothing is read or written off it.
extension WorkoutSessionController: HKWorkoutSessionDelegate {

    public nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            // ── ONLY THE SESSION WE STILL OWN ───────────────────────────────
            // Both delegates hop to the main actor, so a callback enqueued
            // before `cancel()` lands after it. Without this guard a
            // discarded workout's last events rewrite `isRunning`, and the
            // builder's do the same to `heartRate` and `recentSamples` — the
            // next rest screen opened with the discarded workout's sparkline
            // already drawn.
            guard workoutSession === self.session else { return }
            self.isRunning = toState == .running
            // Raw values, for whoever reads the log: 1 not started,
            // 2 running, 3 ended, 4 paused, 5 prepared, 6 stopped.
            self.log.notice("HKWorkoutSession \(fromState.rawValue) -> \(toState.rawValue)")
        }
    }

    public nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didFailWithError error: any Error
    ) {
        Task { @MainActor in
            // The same identity guard as the state callback above. Without it
            // a DISCARDED session's late failure — the one a `cancel()` ends
            // with — stamped `isRunning = false` on the workout that replaced
            // it, and the next `adopt` read that as "start one" (W4).
            guard workoutSession === self.session else { return }
            self.isRunning = false
            self.lastError = error.localizedDescription
            self.log.error("HKWorkoutSession failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension WorkoutSessionController: HKLiveWorkoutBuilderDelegate {

    public nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            guard workoutBuilder === self.builder else { return }
            self.absorb(collectedTypes, from: workoutBuilder)
        }
    }

    /// Pause and resume markers. The training log keeps its own pause ledger in
    /// `set_events` — which survives a relaunch and merges across devices — so
    /// there is nothing to mirror here.
    public nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
#endif
