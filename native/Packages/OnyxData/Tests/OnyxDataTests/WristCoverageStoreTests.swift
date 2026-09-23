import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// App Store W6 — the watch simply stops writing, and missing must never read
// as zero. A scripted Health store with a hole in its heart-rate series, a
// real in-memory store, and the places the hole has to arrive: the coverage
// row, the battery's inputs, and the readiness the faces draw.
// ─────────────────────────────────────────────────────────────────────────────

/// Heart rate every five minutes across whatever window is asked, except `hole`.
private struct GappedHealth: HealthReading {
    var isAvailable = true
    var hole: (from: Date, to: Date)?
    var noReadings = false
    /// The last sample the phone has received — the watch syncs in batches.
    var arrivedUntil: Date?

    func requestAuthorization(read: [String]) async throws -> Bool { true }
    func quantity(_ identifier: String, reduce: HealthReduce, start: Date, end: Date) async throws -> Double? { nil }
    func sleepSamples(start: Date, end: Date) async throws -> [SleepSample] { [] }
    func heartRateSeries(start: Date, end: Date) async throws -> [HRSample] {
        guard !noReadings else { return [] }
        return stride(from: start, to: min(end, arrivedUntil ?? end), by: 300).compactMap { at in
            if let hole, at >= hole.from, at < hole.to { return nil }
            return HRSample(at: at, bpm: 60)
        }
    }
}

@Suite("Wrist coverage — the store, the battery, the readiness note")
struct WristCoverageStoreTests {

    private let user = "u1"
    private let day = "2026-09-03"
    private let utc = TimeZone(identifier: "UTC")!
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }
    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    /// 21:00 the evening before → 09:00 on `day`, local (UTC here).
    private func overnight() throws -> (from: Date, to: Date) {
        try #require(HealthSync.overnight(day, calendar: calendar))
    }
    /// 22:00 → 04:00 inside it.
    private func hole() throws -> (from: Date, to: Date) {
        let w = try overnight()
        return (w.from.addingTimeInterval(3600), w.from.addingTimeInterval(7 * 3600))
    }

    private func coverage(_ db: AppDatabase) throws -> Double? {
        try db.writer.read { conn in
            try Double.fetchOne(conn, sql: "SELECT off_wrist_min FROM wrist_coverage WHERE user_id = ? AND date = ?",
                                arguments: [user, day])
        }
    }

    // MARK: The sync writes it

    @Test("the overnight window is 21:00 → 09:00 LOCAL, not UTC noon to noon")
    func overnightIsLocal() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let w = try #require(HealthSync.overnight(day, calendar: tokyo))
        #expect(tokyo.component(.hour, from: w.from) == 21 && tokyo.component(.day, from: w.from) == 2)
        #expect(tokyo.component(.hour, from: w.to) == 9 && tokyo.component(.day, from: w.to) == 3)
    }

    @Test("a six-hour hole in the night is six hours off the wrist, written before the ingest")
    func syncWritesCoverage() async throws {
        let db = try store()
        let sync = HealthSync(database: db, reader: GappedHealth(hole: try hole()), userId: user)
        try await sync.sync(day: day, isToday: false, now: try overnight().to.addingTimeInterval(3 * 3600), calendar: calendar)
        // 21:55 → 04:00, the gap between the readings either side of the hole.
        #expect(try coverage(db) == 365)
    }

    @Test("no reading at all writes nothing — a phone with no watch is not off anyone's wrist")
    func noWatchNoRow() async throws {
        let db = try store()
        let sync = HealthSync(database: db, reader: GappedHealth(noReadings: true), userId: user)
        try await sync.sync(day: day, isToday: false, now: try overnight().to.addingTimeInterval(3600), calendar: calendar)
        #expect(try coverage(db) == nil)
    }

    @Test("today's window is open at now: samples still in transit are not an absence")
    func todayIsOpenEnded() async throws {
        let db = try store()
        let w = try overnight()
        // 07:00, and the watch last synced at 05:30.
        let now = w.from.addingTimeInterval(10 * 3600)
        let health = GappedHealth(hole: try hole(), arrivedUntil: w.from.addingTimeInterval(8.5 * 3600))
        let sync = HealthSync(database: db, reader: health, userId: user)
        try await sync.sync(day: day, isToday: true, now: now, calendar: calendar)
        #expect(try coverage(db) == 365, "the night's hole — not the 90 minutes since the last batch")
    }

    @Test("an unchanged figure is a no-op, so a repeat sync asks for no rescore")
    func unchangedIsNoOp() throws {
        let db = try store()
        try db.writeWristCoverage(userId: user, date: day, offWristMin: 364.6)
        let changes = try db.writer.write { conn -> Int in
            try conn.execute(sql: """
                INSERT INTO wrist_coverage (user_id, date, off_wrist_min) VALUES (?, ?, ?)
                ON CONFLICT (user_id, date) DO UPDATE SET off_wrist_min = excluded.off_wrist_min
                    WHERE off_wrist_min IS NOT excluded.off_wrist_min
                """, arguments: [user, day, 365.0])
            return conn.changesCount
        }
        #expect(changes == 0, "365 both times: the second write must not touch the row")
        try db.writeWristCoverage(userId: user, date: day, offWristMin: 420)
        #expect(try coverage(db) == 420)
    }

    // MARK: The battery reads it

    private func inputs(_ db: AppDatabase) throws -> ScoringInputs? {
        try db.scoringInputs(userId: user, date: day, hoursAwake: 8, isRestDay: true, todayISO: day, isToday: true)
    }

    @Test("a night with no record and the watch off the wrist is unmeasured, not zero hours")
    func nightOffWristReachesTheBattery() throws {
        let db = try store()
        try db.ingest(HealthPayload(date: day, values: [.hrv: 50, .avgRestHeartRate: 55, .activeEnergy: 300]), userId: user)
        let plain = try #require(try inputs(db))
        #expect(plain.offWristMin == nil, "no coverage row: v9, unchanged")

        try db.writeWristCoverage(userId: user, date: day, offWristMin: 365)
        let off = try #require(try inputs(db))
        #expect(off.offWristMin == 365)
        #expect(WristCoverage.nightUnmeasured(off))
        #expect(Battery.computeBattery(off).morningCharge > Battery.computeBattery(plain).morningCharge)
    }

    @Test("a recorded night keeps the v9 charge, whatever the coverage says")
    func recordedNightIsScoredAsBefore() throws {
        let db = try store()
        let w = try overnight()
        try db.writeWristCoverage(userId: user, date: day, offWristMin: 365)
        try db.writer.write { conn in
            try SleepSessionRow(id: "n1", userId: user, startTime: w.from.addingTimeInterval(2 * 3600),
                                endTime: w.from.addingTimeInterval(8 * 3600), durationMin: 300,
                                createdAt: w.to).insert(conn)
        }
        let i = try #require(try inputs(db))
        #expect(i.sleepHours > 0 && !WristCoverage.nightUnmeasured(i))
    }

    @Test("a store below v37 — the widget's read-only view before the app migrates — scores, not throws")
    func unmigratedStoreStillScores() throws {
        let db = try store()
        try db.ingest(HealthPayload(date: day, values: [.hrv: 50, .steps: 4000]), userId: user)
        try db.writer.write { conn in try conn.execute(sql: "DROP TABLE wrist_coverage") }
        #expect(try inputs(db)?.offWristMin == nil)
    }

    // MARK: The readiness the faces draw

    @Test("the snapshot's readiness carries the note, and the watch payload carries it on")
    func snapshotCarriesNote() throws {
        let db = try store()
        let now = try overnight().to.addingTimeInterval(3600)   // 10:00 on the day
        try db.ingest(HealthPayload(date: day, values: [.hrv: 50, .avgRestHeartRate: 55, .activeEnergy: 300, .steps: 4000]),
                      userId: user)
        let builder = WidgetSnapshotBuilder(database: db, userId: user, timeZone: utc)

        let plain = try builder.build(scope: .full, now: now)
        #expect(plain.readiness != nil, "the fixture must reach a verdict for this test to mean anything")
        #expect(plain.readiness?.offWrist == nil, "no coverage row: nothing to explain")

        try db.writeWristCoverage(userId: user, date: day, offWristMin: 365)
        let snap = try builder.build(scope: .full, now: now)
        let note = try #require(snap.readiness?.offWrist)
        #expect(note == OffWristNote(hours: 6, signals: 3))
        #expect(note.sentence == "Your watch was off your wrist for 6 h — readiness is from 3 signals, not 5.")
        #expect(WatchTiles(snap).offWrist == note)
    }
}
