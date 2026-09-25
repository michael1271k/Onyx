import Foundation
import OnyxData
import Testing
@testable import Onyx

/// The phone half of the fuel push (Precision D4): a water, food or supplement
/// commit marks the bridge so `AppEnvironment.scheduleWatchPush` skips its
/// 30 s throttle. The push itself needs a signed-in environment, which the
/// harness cannot make; what it reads is `takeFuelCommit`, and that is what
/// has to hold — set by a fuel commit, not by any other, and cleared by the
/// read so one glass is one unthrottled push.
@Suite("Watch fuel push")
@MainActor
struct WatchFuelPushTests {

    @Test("a glass marks the bridge once; a take clears it")
    func glassMarksOnce() async throws {
        let db = try AppDatabase.inMemory(deviceId: "phone")
        let bridge = PhoneWatchBridge(database: db)
        bridge.start()
        #expect(bridge.takeFuelCommit() == false)

        try db.addWaterGlass(userId: "u", date: "2026-09-25", ml: 250)
        // The observer hops to the main actor; give it the hop.
        for _ in 0..<50 where !bridge.fuelCommitPending { try await Task.sleep(for: .milliseconds(20)) }
        #expect(bridge.takeFuelCommit() == true)
        #expect(bridge.takeFuelCommit() == false, "one glass, one unthrottled push")
    }
}
