import Foundation
import GRDB
import Testing
@testable import OnyxData

#if canImport(HealthKit)
import HealthKit
#endif

/// Precision Lane D's two OnyxData seams: the anchored query's persisted
/// anchor (D2), and the fuel-only commit signal that lets a food, water or
/// supplement write skip the watch push's 30 s throttle (D4).
@Suite("Watch vitals and fuel pushes")
struct WatchVitalsTests {

    #if canImport(HealthKit)
    /// ── WHY THE ANCHOR IS THE WHOLE POINT ───────────────────────────────────
    /// An anchored query without its anchor starts from the beginning of time:
    /// every relaunch would re-deliver a year of heart rate, and the petal
    /// would spend its first seconds re-deciding what it already knew.
    @Test("an anchor survives a relaunch through the defaults, per type")
    func anchorRoundTrip() throws {
        let suite = try #require(UserDefaults(suiteName: "WatchVitalsTests.\(UUID().uuidString)"))
        #expect(VitalsAnchor.load("HKQuantityTypeIdentifierHeartRate", from: suite) == nil)
        let anchor = HKQueryAnchor(fromValue: 4_242)
        VitalsAnchor.save(anchor, "HKQuantityTypeIdentifierHeartRate", to: suite)
        let back = try #require(VitalsAnchor.load("HKQuantityTypeIdentifierHeartRate", from: suite))
        #expect(back == anchor)
        // One anchor per type: HRV's is its own.
        #expect(VitalsAnchor.load("HKQuantityTypeIdentifierHeartRateVariabilitySDNN", from: suite) == nil)
        // Saving nil forgets it (a query that failed must not resume from a
        // position it never reached).
        VitalsAnchor.save(nil, "HKQuantityTypeIdentifierHeartRate", to: suite)
        #expect(VitalsAnchor.load("HKQuantityTypeIdentifierHeartRate", from: suite) == nil)
    }
    #endif

    @Test("a water glass fires the fuel signal; a set or an exercise does not")
    func fuelCommitsOnly() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let fuel = Counter()
        let observer = db.onFuelCommit { fuel.bump() }
        defer { observer.cancel() }

        try db.writer.write { try Exercise(id: "e", name: "Row").insert($0) }
        #expect(fuel.count == 0, "an exercise is not fuel")

        try db.addWaterGlass(userId: "u", date: "2026-09-25", ml: 250)
        #expect(fuel.count == 1, "one glass, one commit")
    }

    @Test("every fuel table exists in the store, so the region resolves")
    func fuelTablesExist() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        for table in AppDatabase.fuelTables {
            #expect(try db.writer.read { try $0.tableExists(table) }, "\(table) is not a table")
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.withLock { n } }
    func bump() { lock.withLock { n += 1 } }
}
