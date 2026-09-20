import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// A store whose statistics query sums every sample it holds — which is what a
/// real `HKStatisticsQuery` does, and the whole defect.
private struct DoubleFilingHealth: HealthReading {
    var isAvailable = true
    var samples: [String: [QuantitySample]] = [:]

    func requestAuthorization(read: [String]) async throws -> Bool { true }

    func quantity(
        _ identifier: String, reduce: HealthReduce, start: Date, end: Date
    ) async throws -> Double? {
        guard let rows = samples[identifier], !rows.isEmpty else { return nil }
        switch reduce {
        case .sum: return rows.reduce(0) { $0 + $1.value }
        case .average: return rows.reduce(0) { $0 + $1.value } / Double(rows.count)
        case .latest: return rows.last?.value
        }
    }

    func quantitySamples(
        _ identifier: String, start: Date, end: Date
    ) async throws -> [QuantitySample]? { samples[identifier] }

    func sleepSamples(start: Date, end: Date) async throws -> [SleepSample] { [] }
}

@Suite("A re-filed meal is one meal")
struct DietaryDedupeTests {

    private let user = "u1"
    private let day = "2026-09-17"

    private func at(_ hhmm: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: "2026-09-17T\(hhmm):00Z")!
    }

    private func sample(_ app: String, _ hhmm: String, _ value: Double) -> QuantitySample {
        QuantitySample(source: app, start: at(hhmm), end: at(hhmm), value: value)
    }

    // MARK: - The rule

    @Test("a day filed twice comes back once")
    func aWholeReSync() {
        let rows = [
            sample("MyFitnessPal", "08:10", 1_047),
            sample("MyFitnessPal", "13:20", 1_048),
            sample("MyFitnessPal", "08:10", 1_047),   // the second pass
            sample("MyFitnessPal", "13:20", 1_048),
        ]
        let (total, dropped) = QuantitySamples.dedupedSum(rows)
        #expect(total == 2_095)
        #expect(dropped.count == 2)
    }

    @Test("three passes come back once, not twice")
    func threePasses() {
        let rows = (0..<3).flatMap { _ in
            [sample("MyFitnessPal", "08:10", 500), sample("MyFitnessPal", "13:20", 300)]
        }
        #expect(QuantitySamples.dedupedSum(rows).total == 800)
    }

    /// ── THE CASE THAT MADE THE FIRST RULE WRONG ────────────────────────────
    /// A food logger files every item of a meal under the MEAL's timestamp, so
    /// two entries at 08:10 from one app are ordinary — and two eggs logged as
    /// two entries agree on their source, their interval AND their amount while
    /// being two eggs. Dropping one halves a number the athlete entered
    /// correctly, silently. An inflated total is at least visible, and the
    /// export already refuses to believe it.
    @Test("two identical items in one meal are two items, not a duplicate")
    func twoEggsAreTwoEggs() {
        let rows = [
            sample("MyFitnessPal", "08:10", 28),   // an egg
            sample("MyFitnessPal", "08:10", 28),   // and another egg
            sample("MyFitnessPal", "08:10", 120),  // the yoghurt beside them
        ]
        // Counts are [2, 1] — a gcd of one, so nothing is touched.
        let (total, dropped) = QuantitySamples.dedupedSum(rows)
        #expect(total == 176)
        #expect(dropped.isEmpty)
    }

    /// Two meals that genuinely agree on an amount are two meals. The INTERVAL
    /// is what separates them, and a person does not eat twice in one instant.
    @Test("the same amount at a different time is two entries")
    func timeSeparatesThem() {
        let rows = [sample("MyFitnessPal", "08:10", 500), sample("MyFitnessPal", "12:10", 500)]
        #expect(QuantitySamples.dedupedSum(rows).total == 1_000)
        #expect(QuantitySamples.dedupedSum(rows).dropped.isEmpty)
    }

    @Test("two apps filing the same figure are two entries — that is a user problem, not a re-sync")
    func sourceSeparatesThem() {
        let rows = [sample("MyFitnessPal", "08:10", 500), sample("Onyx", "08:10", 500)]
        #expect(QuantitySamples.dedupedSum(rows).total == 1_000)
    }

    // MARK: - The wiring

    @Test("a dietary total is re-summed without the re-filed entries, and the sync says so")
    func theSyncDropsThem() async throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let health = HealthSync(
            database: db,
            reader: DoubleFilingHealth(samples: [
                // The MACROS are re-filed too — the same meal, twice — and what
                // lands is the meal, not two of it.
                "HKQuantityTypeIdentifierDietaryEnergyConsumed": [
                    sample("MyFitnessPal", "08:10", 900),
                    sample("MyFitnessPal", "13:20", 1_100),
                    sample("MyFitnessPal", "08:10", 900),
                    sample("MyFitnessPal", "13:20", 1_100),
                ],
                "HKQuantityTypeIdentifierDietaryCalcium": [
                    sample("MyFitnessPal", "08:10", 1_047),
                    sample("MyFitnessPal", "13:20", 1_048),
                    sample("MyFitnessPal", "08:10", 1_047),
                    sample("MyFitnessPal", "13:20", 1_048),
                ],
                // A BODY metric with two identical samples is NOT touched: an
                // iPhone and a Watch recording the same minute is exactly what
                // the statistics query's own dedupe is for, and re-summing by
                // hand here would undo it.
                "HKQuantityTypeIdentifierStepCount": [
                    sample("iPhone", "08:10", 4_000),
                    sample("iPhone", "08:10", 4_000),
                ],
            ]), userId: user)
        let report = try await health.sync(day: day, isToday: false)

        let row = try db.read { conn in
            try NutritionEntryRow
                .filter(Column("user_id") == user && Column("date") == day)
                .fetchOne(conn)
        }
        let micros = try #require(row?.micros.flatMap(WeeklyExportBuilder.numbers))
        // 3,142 mg was the figure the export refused to believe. 2,095 is what
        // the athlete actually ate.
        #expect(micros["calcium"] == 2_095)
        #expect(row?.calories == 2_000)
        #expect(report.declined.contains { $0.contains("calcium") && $0.contains("MyFitnessPal") })
        #expect(report.declined.contains { $0.contains("calories") })

        let log = try db.read { conn in
            try DailyLogRow.filter(Column("user_id") == user && Column("date") == day).fetchOne(conn)
        }
        #expect(log?.steps == 8_000, "a body metric keeps HealthKit's own cross-device dedupe")
    }
}
