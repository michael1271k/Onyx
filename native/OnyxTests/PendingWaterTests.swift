import Testing
import Foundation
@testable import Onyx

/// The Control Center water mailbox (W5) — the arithmetic between a tap in
/// the extension and a row in the store.
///
/// The drain itself (`AppEnvironment.drainPendingWater`) needs a signed-in
/// environment, which the harness cannot make; what it does with the key is
/// three calls on this enum, and they are what has to hold: add accumulates,
/// take empties, and a take on an empty key is zero rather than a stale
/// figure counted twice.
@Suite("Pending water")
struct PendingWaterTests {

    private static func defaults() -> UserDefaults {
        let suite = "onyx-tests-pending-water-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test("two glasses queue as one figure, a take empties it, a second take is zero")
    func accumulatesAndDrains() {
        let d = Self.defaults()
        #expect(PendingWater.pending(in: d) == 0)
        PendingWater.add(PendingWater.glassMl, to: d)
        PendingWater.add(PendingWater.glassMl, to: d)
        #expect(PendingWater.pending(in: d) == 500)
        #expect(PendingWater.take(from: d) == 500)
        #expect(PendingWater.take(from: d) == 0)
        #expect(PendingWater.pending(in: d) == 0)
    }

    @Test("a failed drain puts the glasses back without doubling them")
    func putBack() {
        let d = Self.defaults()
        PendingWater.add(250, to: d)
        let taken = PendingWater.take(from: d)
        PendingWater.add(taken, to: d)
        #expect(PendingWater.pending(in: d) == 250)
    }
}
