#if DEBUG
import Foundation
import HealthKit
import OnyxCore
import OnyxData

/// `--onyx-telemetry-seed` on the launch command line (Expansion W5).
///
/// ── WHY THE HARNESS WRITES TO THE REAL HEALTH STORE ─────────────────────────
/// The simulator has a working HealthKit and no heart. The heart-rate chart is
/// a read of that store, so the only way to photograph it is to put a series
/// there first: forty-nine minutes of bpm at the watch's in-workout cadence,
/// shaped like four movements with rests, ending a minute ago — and an OWN
/// `HKWorkout` over most of it, through the same `HealthWorkoutWriter` a
/// phone finish uses, so the provenance path is the one under review.
///
/// Every object is stamped `app.onyx.seed` and the previous run's are deleted
/// first, so the store does not accumulate a series per screenshot. A
/// Hevy-tagged workout CANNOT be seeded — the source of a sample is the
/// process that saves it — which is why the compare card is photographed
/// from a fixture (`hevy-card`) and its predicate from a golden vector.
///
/// The permission sheet appears on the first run; on a simulator it has to
/// be tapped once ("Turn On All"). Gated on the argument, so no other shot
/// ever sees it.
enum TelemetrySeed {

    static let seedKey = "app.onyx.seed"

    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("--onyx-telemetry-seed")
    }

    /// The series ends a minute ago and runs 49 minutes: the harness's
    /// live session starts 46 minutes ago, so its interval sits inside.
    static let end = Date().addingTimeInterval(-60)
    static let start = end.addingTimeInterval(-49 * 60)

    static func run() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let hr = HKQuantityType(.heartRate)
        let energy = HKQuantityType(.activeEnergyBurned)
        let workoutType = HKObjectType.workoutType()
        do {
            try await store.requestAuthorization(
                toShare: [hr, energy, workoutType], read: [hr, energy, workoutType]
            )
        } catch { return }

        // Last run's objects, out.
        let mine = HKQuery.predicateForObjects(withMetadataKey: seedKey)
        for type in [hr, energy, workoutType] as [HKObjectType] {
            _ = try? await store.deleteObjects(of: type, predicate: mine)
        }

        // The series: one reading every five seconds.
        let unit = HKUnit.count().unitDivided(by: .minute())
        var samples: [HKQuantitySample] = []
        var at = start
        var i = 0
        while at <= end {
            samples.append(HKQuantitySample(
                type: hr, quantity: HKQuantity(unit: unit, doubleValue: bpm(atMinute: Double(i) * 5 / 60)),
                start: at, end: at, metadata: [seedKey: true]
            ))
            at = at.addingTimeInterval(5)
            i += 1
        }
        try? await store.save(samples)

        // An own workout over the session's interval, through the writer the
        // phone uses — with its estimated energy, flagged as such.
        let session = WorkoutSession(
            id: "telemetry-seed", userId: PreviewCatalogue.userId, dayKey: "cb_b", date: LogicalDay.today(),
            startedAt: start.addingTimeInterval(3 * 60), endedAt: end.addingTimeInterval(-2 * 60),
            durationMin: 44, caloriesBurned: 378, caloriesEstimated: true
        )
        _ = try? await HealthWorkoutWriter().write(
            session: session, decision: .write(energyKcal: 378, estimated: true), extra: [seedKey: true]
        )
    }

    /// Four movements of ~10 minutes with three sets each, a rest between,
    /// warming through the session and cooling at the end. Deterministic.
    static func bpm(atMinute m: Double) -> Double {
        let block = min(3, Int(m / 10))
        let inBlock = m - Double(block) * 10
        let base = 96 + Double(block) * 5
        if m >= 42 { return max(88, 128 - (m - 42) * 6) }
        // Three lifts per block: a burst rising over ~40 s, decaying over the rest.
        let phase = inBlock.truncatingRemainder(dividingBy: 3.3)
        let burst = phase < 0.7 ? phase / 0.7 : max(0, 1 - (phase - 0.7) / 2.4)
        return base + burst * 34
    }
}
#endif
