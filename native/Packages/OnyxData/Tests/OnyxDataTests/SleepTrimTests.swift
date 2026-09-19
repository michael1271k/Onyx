import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// A Health store that answers from a script — the same double `IngestTests`
/// uses, here for the night-window reads the trim engine makes.
private struct TrimHealth: HealthReading {
    var isAvailable = true
    var quantities: [String: Double] = [:]
    var samples: [SleepSample] = []
    var windowed: (@Sendable (String, Date, Date) -> Double?)? = nil

    func requestAuthorization(read: [String]) async throws -> Bool { true }
    func quantity(_ identifier: String, reduce: HealthReduce, start: Date, end: Date) async throws -> Double? {
        if let windowed, let v = windowed(identifier, start, end) { return v }
        return quantities[identifier]
    }
    /// Answers by overlap, as HealthKit does for a predicate on `[start, end)`.
    func sleepSamples(start: Date, end: Date) async throws -> [SleepSample] {
        samples.filter { $0.end > start && $0.start < end }
    }
}

/// The sleep trim engine (Phase 3 E2): strategy A over samples, strategy B over
/// stored minutes, the sentinel, the HRV re-read, and the id-keyed write.
@Suite("Sleep trim")
struct SleepTrimTests {

    private let user = "u1"
    /// The night that ends on the morning of the 6th.
    private let night = "2026-09-06"
    /// 2026-09-05T22:00Z.
    private let bed = Date(timeIntervalSince1970: 1_788_645_600)
    private var wake: Date { bed.addingTimeInterval(8 * 3600) }
    private let hrvId = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    /// Eight hours in bed: 20 min awake at each edge, deep · rem · core between.
    private var samples: [SleepSample] {
        let m = 60.0
        return [
            SleepSample(value: 2, start: bed, end: bed.addingTimeInterval(20 * m)),                              // awake
            SleepSample(value: 3, start: bed.addingTimeInterval(20 * m), end: bed.addingTimeInterval(120 * m)),  // core
            SleepSample(value: 4, start: bed.addingTimeInterval(120 * m), end: bed.addingTimeInterval(200 * m)), // deep
            SleepSample(value: 5, start: bed.addingTimeInterval(200 * m), end: bed.addingTimeInterval(300 * m)), // rem
            SleepSample(value: 3, start: bed.addingTimeInterval(300 * m), end: bed.addingTimeInterval(460 * m)), // core
            SleepSample(value: 2, start: bed.addingTimeInterval(460 * m), end: wake),                            // awake
        ]
    }

    private func storedNight(_ db: AppDatabase) throws -> SleepSessionRow? {
        try db.writer.read { conn in try SleepSessionRow.filter(Column("user_id") == user).fetchOne(conn) }
    }

    private func nightCount(_ db: AppDatabase) throws -> Int {
        try db.writer.read { conn in try SleepSessionRow.fetchCount(conn) }
    }

    /// The night as HealthKit would have synced it.
    @discardableResult
    private func syncNight(_ db: AppDatabase, hrv: Double = 58.3) async throws -> IngestReport {
        let reader = TrimHealth(quantities: [hrvId: hrv], samples: samples)
        return try await HealthSync(database: db, reader: reader, userId: user).sync(day: night, isToday: false)
    }

    // MARK: Strategy A

    @Test("A: samples re-aggregate inside the new window — the awake edges are gone, the stages re-sum")
    func strategyA() throws {
        let full = try #require(Sleep.aggregate(samples))
        #expect(full.sleepMinutes == 440 && full.awakeMin == 40 && full.deepMin == 80 && full.remMin == 100 && full.coreMin == 260)

        // Trim 30 min off each end: both awake blocks go, and 10 min of core each side.
        let trimmed = try #require(Sleep.aggregate(samples, within: bed.addingTimeInterval(30 * 60), wake.addingTimeInterval(-30 * 60)))
        #expect(trimmed.awakeMin == 0)
        #expect(trimmed.deepMin == 80 && trimmed.remMin == 100)
        #expect(trimmed.coreMin == 240)
        #expect(trimmed.sleepMinutes == 420)
        #expect(trimmed.bedStart == bed.addingTimeInterval(30 * 60))

        // A window with nothing asleep in it is no night, never a zero night.
        #expect(Sleep.aggregate(samples, within: bed, bed.addingTimeInterval(10 * 60)) == nil)
        #expect(Sleep.clip(samples, start: wake, end: bed).isEmpty)
    }

    @Test("A on the phone: the edit writes the re-aggregated stages, the sentinel and the window, by id")
    func strategyAWrites() async throws {
        let db = try store()
        try await syncNight(db)
        let before = try #require(try storedNight(db))
        #expect(before.durationMin == 440 && before.hkUuid == nil)

        let reader = TrimHealth(quantities: [hrvId: 58.3], samples: samples)
        let sync = HealthSync(database: db, reader: reader, userId: user)
        let newStart = bed.addingTimeInterval(30 * 60)
        let newEnd = wake.addingTimeInterval(-30 * 60)
        let row = try await sync.editSleepWindow(date: night, start: newStart, end: newEnd)

        #expect(row.id == before.id, "the same row — the trim moves start_time, so a natural key would mint a second night")
        #expect(row.startTime == newStart && row.endTime == newEnd)
        #expect(row.durationMin == 420 && row.awakeMin == 0 && row.coreMin == 240)
        #expect(row.hkUuid == ManualEntry.sleepSentinel(night))
        #expect(try nightCount(db) == 1)
        let log = try #require(try await db.writer.read { conn in try DailyLogRow.filter(Column("date") == night).fetchOne(conn) })
        #expect(log.sleepMinutes == 420)
    }

    // MARK: Strategy B

    @Test("B: no samples — awake first, then the stages in proportion; an extension is core only")
    func strategyB() throws {
        let db = try store()
        // A web-synced night the phone never sampled: 431 asleep, 18 awake, an 8 h window.
        try db.writer.write { conn in
            try SleepSessionRow(
                id: "web-night", userId: user, startTime: bed, endTime: wake, durationMin: 431,
                deepMin: 74, remMin: 96, coreMin: 261, awakeMin: 18, createdAt: Date()
            ).insert(conn)
        }
        // 60 min off the start: 18 awake, then 42 asleep in proportion.
        let trimmed = try db.editSleepWindow(userId: user, date: night, start: bed.addingTimeInterval(3600), end: wake)
        #expect(trimmed.id == "web-night")
        #expect(trimmed.durationMin == 389 && trimmed.awakeMin == 0)
        #expect(trimmed.deepMin == 67 && trimmed.remMin == 87 && trimmed.coreMin == 235)
        #expect((trimmed.deepMin ?? 0) + (trimmed.remMin ?? 0) + (trimmed.coreMin ?? 0) == trimmed.durationMin)

        // Then 30 min back on the end: core only.
        let extended = try db.editSleepWindow(userId: user, date: night, start: bed.addingTimeInterval(3600), end: wake.addingTimeInterval(1800))
        #expect(extended.durationMin == 419 && extended.coreMin == 265 && extended.deepMin == 67 && extended.remMin == 87)
        #expect(try nightCount(db) == 1)
    }

    @Test("B on a night nobody has written: all core, no stage claim")
    func strategyBFromNothing() throws {
        let db = try store()
        let row = try db.editSleepWindow(userId: user, date: night, start: bed, end: bed.addingTimeInterval(7 * 3600))
        #expect(row.durationMin == 420 && row.coreMin == 420 && row.deepMin == 0 && row.remMin == 0 && row.awakeMin == 0)
        #expect(row.hkUuid == ManualEntry.sleepSentinel(night))
        #expect(try nightCount(db) == 1)
    }

    @Test("an inverted window, or a bedtime outside the night's own window, is refused before it touches the store")
    func invertedWindowRefused() throws {
        let db = try store()
        #expect(throws: SleepEditError.emptyWindow) {
            try db.editSleepWindow(userId: user, date: night, start: wake, end: bed)
        }
        // A bedtime at 13:00Z on the 6th belongs to the night of the 7th; written
        // under the 6th's sentinel it would be found by nobody reading the 6th
        // and would block the 7th's real night forever.
        let noon = Date(timeIntervalSince1970: 1_788_699_600)   // 2026-09-06T13:00Z
        #expect(throws: SleepEditError.outsideNight(night)) {
            try db.editSleepWindow(userId: user, date: night, start: noon, end: noon.addingTimeInterval(7 * 3600))
        }
        // The other end. Both of these pass the wake WHEEL's own bounds
        // (`window.from ... window.to + 6h`), and both describe a night nobody
        // slept: the store refused neither until W-GATE, and wrote the second
        // as `duration_min = 1800`.
        guard let window = NightWindow.range(night) else { Issue.record("no window"); return }
        #expect(throws: SleepEditError.impossibleNight(night)) {
            // Wake 7 h past the wheel's own close.
            try db.editSleepWindow(
                userId: user, date: night,
                start: window.to.addingTimeInterval(-3600),
                end: window.to.addingTimeInterval(7 * 3600)
            )
        }
        #expect(throws: SleepEditError.impossibleNight(night)) {
            // Inside both wheels, 30 hours long.
            try db.editSleepWindow(
                userId: user, date: night,
                start: window.from,
                end: window.to.addingTimeInterval(6 * 3600)
            )
        }
        #expect(try nightCount(db) == 0)
    }

    @Test("a HealthKit read that throws during the edit is an error, never a silent fall-back to strategy B")
    func sampleReadFailureIsAnError() async throws {
        struct Throwing: HealthReading {
            struct Boom: Error {}
            var isAvailable = true
            func requestAuthorization(read: [String]) async throws -> Bool { true }
            func quantity(_ identifier: String, reduce: HealthReduce, start: Date, end: Date) async throws -> Double? { nil }
            func sleepSamples(start: Date, end: Date) async throws -> [SleepSample] { throw Boom() }
        }
        let db = try store()
        try await syncNight(db)
        let sync = HealthSync(database: db, reader: Throwing(), userId: user)
        await #expect(throws: Throwing.Boom.self) {
            try await sync.editSleepWindow(date: night, start: bed.addingTimeInterval(1800), end: wake)
        }
        #expect(try storedNight(db)?.hkUuid == nil, "nothing was written")
    }

    // MARK: The sentinel

    @Test("the sentinel blocks the ingest: a later HealthKit sync changes nothing about the night")
    func sentinelBlocksIngest() async throws {
        let db = try store()
        try await syncNight(db)
        let reader = TrimHealth(quantities: [hrvId: 58.3], samples: samples)
        let edited = try await HealthSync(database: db, reader: reader, userId: user)
            .editSleepWindow(date: night, start: bed.addingTimeInterval(1800), end: wake.addingTimeInterval(-1800))

        let report = try await syncNight(db)
        #expect(report.declined.contains { $0.contains("sleep") })
        let after = try #require(try storedNight(db))
        #expect(after == edited, "the next sync must not re-widen a trimmed night")
        #expect(try nightCount(db) == 1)
    }

    @Test("the second row in a window goes with the edit, and its delete is queued")
    func duplicateNightCollapses() throws {
        let db = try store()
        try db.writer.write { conn in
            try SleepSessionRow(id: "a", userId: user, startTime: bed, endTime: wake, durationMin: 431, deepMin: 74, remMin: 96, coreMin: 261, awakeMin: 18, createdAt: Date()).insert(conn)
            try SleepSessionRow(id: "b", userId: user, startTime: bed.addingTimeInterval(22), endTime: wake, durationMin: 431, deepMin: 74, remMin: 96, coreMin: 261, awakeMin: 18, createdAt: Date()).insert(conn)
        }
        try db.editSleepWindow(userId: user, date: night, start: bed, end: wake)
        #expect(try nightCount(db) == 1)
        let kinds = try db.pendingOutbox().map(\.kind)
        #expect(kinds.filter { $0 == SyncKind.rowUpsert }.count >= 1)
        #expect(kinds.contains(SyncKind.rowDelete))
    }

    // MARK: HRV

    @Test("overnight HRV is re-read over the NEW window on the edit, and over the STORED window on every later sync")
    func hrvFollowsTheStoredWindow() async throws {
        let db = try store()
        try await syncNight(db)
        let synced = try await db.writer.read { conn in try DailyLogRow.filter(Column("date") == night).fetchOne(conn) }
        #expect(synced?.hrvMs == 58.3)

        let newStart = bed.addingTimeInterval(1800)
        let newEnd = wake.addingTimeInterval(-1800)
        // Answers 71.26 over the trimmed window and 40 over HealthKit's own bed window.
        let reader = TrimHealth(
            quantities: [hrvId: 58.3], samples: samples,
            windowed: { [bed, wake] id, start, end in
                guard id == "HKQuantityTypeIdentifierHeartRateVariabilitySDNN" else { return nil }
                if start == newStart && end == newEnd { return 71.26 }
                if start == bed && end == wake { return 40 }
                return nil
            }
        )
        let sync = HealthSync(database: db, reader: reader, userId: user)
        try await sync.editSleepWindow(date: night, start: newStart, end: newEnd)
        func hrv() throws -> Double? { try db.writer.read { conn in try DailyLogRow.filter(Column("date") == night).fetchOne(conn) }?.hrvMs }
        #expect(try hrv() == 71.26, "the edit re-reads over the new window")

        // The next sync must read the STORED window, not HealthKit's bed window.
        let report = try await sync.sync(day: night, isToday: false)
        #expect(report.hrvOvernight)
        #expect(try hrv() == 71.26, "a sync after the trim reads HRV over the trimmed window")
        let row = try #require(try storedNight(db))
        #expect(row.startTime == newStart && row.endTime == newEnd)
    }

    // MARK: The cascade

    @Test("the cascade after an edit rewrites the day's score from the trimmed night")
    func rescoreReflectsTheTrim() throws {
        let db = try store()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // Today is the 6th, 14:00Z.
        let now = Date(timeIntervalSince1970: 1_788_703_200)
        try db.writer.write { conn in
            try UserGoalRow(
                id: "g1", userId: user, sleepGoalHours: 8, calorieGoal: 1955,
                proteinGoalG: 190, carbsGoalG: 150, fatGoalG: 60, stepsGoal: 10_000,
                waterGoalMl: 3000, contextMode: "normal", createdAt: now, updatedAt: now,
                autoLogSupplements: false, activeProgram: "onyx5", dayCutoffHour: 0,
                unitSystem: "metric", reduceMotion: false, timezone: "UTC", trackRpe: true
            ).insert(conn)
            try SleepSessionRow(
                id: "n", userId: user, startTime: bed, endTime: wake, durationMin: 480,
                deepMin: 80, remMin: 100, coreMin: 300, awakeMin: 0, createdAt: now
            ).insert(conn)
        }
        let before = try #require(try db.rescore(userId: user, from: night, reason: .sleepEdit, now: now, calendar: cal).written > 0
            ? db.writer.read { conn in try DailyScoreRow.filter(Column("date") == night).fetchOne(conn) } : nil)

        // Four hours off the night.
        try db.editSleepWindow(userId: user, date: night, start: bed, end: bed.addingTimeInterval(4 * 3600), now: now)
        let run = try db.rescore(userId: user, from: night, reason: .sleepEdit, now: now, calendar: cal)
        #expect(run.reason == .sleepEdit && run.written >= 1)
        let after = try #require(try db.writer.read { conn in try DailyScoreRow.filter(Column("date") == night).fetchOne(conn) })
        #expect((after.sleepScore ?? 0) < (before.sleepScore ?? 0), "half the night must cost sleep score")
        #expect((after.batteryPct ?? 0) < (before.batteryPct ?? 0), "and the battery")
    }
}
