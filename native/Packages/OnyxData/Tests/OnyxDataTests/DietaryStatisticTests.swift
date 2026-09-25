import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// A reader whose statistic is whatever the test says HealthKit merged it to,
/// beside the raw samples the old code used to re-sum.
private struct StatisticHealth: HealthReading {
    var isAvailable = true
    var statistic: [String: Double] = [:]
    var samples: [String: [QuantitySample]] = [:]
    var bySource: [String: [String: Double]] = [:]

    func requestAuthorization(read: [String]) async throws -> Bool { true }

    func quantity(
        _ identifier: String, reduce: HealthReduce, start: Date, end: Date
    ) async throws -> Double? { statistic[identifier] }

    func quantityBySource(
        _ identifier: String, start: Date, end: Date
    ) async throws -> [String: Double] { bySource[identifier] ?? [:] }

    /// Still answers — a reader that implements it is not a reader the sync
    /// may consult. `QuantitySample` is a test-local shape now.
    func quantitySamples(
        _ identifier: String, start: Date, end: Date
    ) async throws -> [QuantitySample]? { samples[identifier] }

    func sleepSamples(start: Date, end: Date) async throws -> [SleepSample] { [] }
}

/// What the old `QuantitySamples.dedupedSum` took: kept here so the double
/// can still be handed a raw-sample shape the sync must ignore.
private struct QuantitySample: Sendable, Equatable {
    let source: String
    let start: Date
    let end: Date
    let value: Double
}

/// Founder decision Q15 (Precision Lane C): a dietary day total is HealthKit's
/// own source-merged statistic. The raw-sample re-sum is gone.
@Suite("A dietary total is HealthKit's statistic")
struct DietaryStatisticTests {

    private let user = "u1"
    private let day = "2026-09-25"
    private static let cholesterol = "HKQuantityTypeIdentifierDietaryCholesterol"
    /// `nutrition_entries.calories` is NOT NULL, so every day needs an energy statistic to be written at all.
    private static let energy = "HKQuantityTypeIdentifierDietaryEnergyConsumed"

    private func at(_ hhmm: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: "2026-09-25T\(hhmm):00Z")!
    }
    private func sample(_ app: String, _ hhmm: String, _ value: Double) -> QuantitySample {
        QuantitySample(source: app, start: at(hhmm), end: at(hhmm), value: value)
    }

    private func cholesterol(_ db: AppDatabase) throws -> Double? {
        let row = try db.read { conn in
            try NutritionEntryRow.filter(Column("user_id") == user && Column("date") == day).fetchOne(conn)
        }
        return row?.micros.flatMap(WeeklyExportBuilder.numbers)?["cholesterol"]
    }

    @Test("two sources logging the same 305 mg omelet store the merged 305, not 610")
    func twoSourcesOneOmelet() async throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let health = HealthSync(
            database: db,
            reader: StatisticHealth(
                statistic: [Self.cholesterol: 305, Self.energy: 1900],
                samples: [Self.cholesterol: [sample("MyFitnessPal", "08:10", 305), sample("Onyx", "08:10", 305)]],
                bySource: [Self.cholesterol: ["MyFitnessPal": 305, "Onyx": 305]]),
            userId: user)
        _ = try await health.sync(day: day, isToday: false)
        #expect(try cholesterol(db) == 305)
    }

    /// The case the old rule got wrong: one app files an omelet as two eggs at
    /// one instant — same source, same interval, same amount — and the GCD
    /// re-sum halved it to one egg. The statistic said 610 and 610 is stored.
    @Test("one app filing two identical items at one instant is not halved")
    func twoEggsStayTwoEggs() async throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let health = HealthSync(
            database: db,
            reader: StatisticHealth(
                statistic: [Self.cholesterol: 610, Self.energy: 1900],
                samples: [Self.cholesterol: [sample("MyFitnessPal", "08:10", 305), sample("MyFitnessPal", "08:10", 305)]],
                bySource: [Self.cholesterol: ["MyFitnessPal": 610]]),
            userId: user)
        let report = try await health.sync(day: day, isToday: false)
        #expect(try cholesterol(db) == 610)
        #expect(!report.declined.contains { $0.contains("re-filed") }, "nothing is struck out of a statistic any more")
    }

    @Test("the per-source breakdown is kept for display")
    func breakdownKept() async throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let health = HealthSync(
            database: db,
            reader: StatisticHealth(
                statistic: [Self.cholesterol: 305, Self.energy: 1900],
                bySource: [Self.cholesterol: ["MyFitnessPal": 200, "Onyx": 105]]),
            userId: user)
        _ = try await health.sync(day: day, isToday: false)
        let row = try db.read { conn in
            try NutritionEntryRow.filter(Column("user_id") == user && Column("date") == day).fetchOne(conn)
        }
        let micros = try #require(row?.micros.flatMap(WeeklyExportBuilder.numbers))
        #expect(micros["cholesterol@MyFitnessPal"] == 200)
        #expect(micros["cholesterol@Onyx"] == 105)
    }

    @Test("the re-ingest door re-reads the last N finished days")
    func reingestWindow() async throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let health = HealthSync(
            database: db, reader: StatisticHealth(statistic: [Self.cholesterol: 305, Self.energy: 1900]), userId: user)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = at("14:00")
        let reports = try await health.reingest(days: 30, now: now, calendar: cal)
        #expect(reports.count == 30)
        let dates = try db.read { conn in
            try String.fetchAll(conn, sql: "SELECT date FROM nutrition_entries WHERE user_id = ? ORDER BY date", arguments: [user])
        }
        #expect(dates.first == "2026-08-26" && dates.last == "2026-09-24", "yesterday back thirty days; today is `syncRecent`'s")
        #expect(dates.count == 30)
    }
}
