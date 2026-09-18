import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// A Health store that answers from a script — the `SleepTrimTests` double,
/// here for the onset the third wheel threads through the edit.
private struct OnsetHealth: HealthReading {
    var isAvailable = true
    var samples: [SleepSample] = []

    func requestAuthorization(read: [String]) async throws -> Bool { true }
    func quantity(_ identifier: String, reduce: HealthReduce, start: Date, end: Date) async throws -> Double? { nil }
    func sleepSamples(start: Date, end: Date) async throws -> [SleepSample] {
        samples.filter { $0.end > start && $0.start < end }
    }
}

/// Sleep v2 (W3): the two columns, the third wheel, and the five terms the
/// builder fills. The formula itself is `sleep-score-v2.json` in OnyxCore;
/// this file is the store's half — what reaches `ScoringInputs`.
@Suite("Sleep v2 — onset, awakenings, the five terms")
struct SleepV2Tests {

    private let user = "u1"
    /// The night that ends on the morning of the 6th; 2026-09-05T22:00Z.
    private let night = "2026-09-06"
    private let bed = Date(timeIntervalSince1970: 1_788_645_600)
    private var wake: Date { bed.addingTimeInterval(8 * 3600) }
    private func min(_ m: Double) -> Date { bed.addingTimeInterval(m * 60) }

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    /// In bed 20 min awake, core, a 6-min awakening, deep, a 3-min stir, rem,
    /// then awake at the end.
    private var samples: [SleepSample] {
        [
            SleepSample(value: 0, start: bed, end: wake),                 // inBed — the phone's own span
            SleepSample(value: 2, start: bed, end: min(20)),
            SleepSample(value: 3, start: min(20), end: min(120)),
            SleepSample(value: 2, start: min(120), end: min(126)),        // ≥ 5 min: counts
            SleepSample(value: 4, start: min(126), end: min(200)),
            SleepSample(value: 2, start: min(200), end: min(203)),        // 3 min: a stir, not an awakening
            SleepSample(value: 5, start: min(203), end: min(300)),
            SleepSample(value: 3, start: min(300), end: min(460)),
            SleepSample(value: 2, start: min(460), end: wake),            // 20 min at the end: counts
        ]
    }

    private func storedNight(_ db: AppDatabase) throws -> SleepSessionRow? {
        try db.writer.read { conn in try SleepSessionRow.filter(Column("user_id") == user).fetchOne(conn) }
    }

    // MARK: Aggregation

    @Test("onset is the first asleep minute, awakenings are merged awake episodes of five minutes or more")
    func aggregateOnsetAndAwakenings() throws {
        let n = try #require(Sleep.aggregate(samples))
        #expect(n.onset == min(20), "the in-bed and awake samples before it ARE the latency")
        #expect(n.awakenings == 2, "6 min and 20 min count; the 3-min stir and the 20 min BEFORE onset do not")
        #expect(n.awakeMin == 49)
        #expect(n.inBedMinutes == 480)
        #expect(n.bedStart == bed && n.bedEnd == wake)
    }

    @Test("two adjacent awake samples are one awakening, and clip inherits the five-minute rule")
    func awakeningsMergeAndClip() throws {
        let split = try #require(Sleep.aggregate([
            SleepSample(value: 3, start: bed, end: min(60)),
            SleepSample(value: 2, start: min(60), end: min(63)),
            SleepSample(value: 2, start: min(63), end: min(66)),          // 3 + 3 adjacent = one 6-min episode
            SleepSample(value: 3, start: min(66), end: min(120)),
        ]))
        #expect(split.awakenings == 1)
        // Clipping the window to end mid-episode leaves 2 min of it — no longer an awakening.
        let clipped = try #require(Sleep.aggregate(samples, within: bed, min(122)))
        #expect(clipped.awakenings == 0 && clipped.awakeMin == 22)
        #expect(clipped.onset == min(20))
        // A window opening after the onset: the onset moves with it.
        let late = try #require(Sleep.aggregate(samples, within: min(130), wake))
        #expect(late.onset == min(130))
    }

    // MARK: Ingest

    @Test("writeSleep stores onset_time and awakenings")
    func ingestWritesTheTwoColumns() throws {
        let db = try store()
        let n = try #require(Sleep.aggregate(samples))
        try db.ingest(HealthPayload(date: night, values: [:], sleep: n), userId: user)
        let row = try #require(try storedNight(db))
        #expect(row.onsetTime == min(20))
        #expect(row.awakenings == 2)
    }

    // MARK: The edit — the store is the trust boundary

    @Test("an onset outside [start, end) is refused before it touches the store")
    func onsetOutsideWindowRefused() throws {
        let db = try store()
        #expect(throws: SleepEditError.onsetOutsideWindow(night)) {
            try db.editSleepWindow(userId: user, date: night, start: bed, end: wake, onset: bed.addingTimeInterval(-60))
        }
        #expect(throws: SleepEditError.onsetOutsideWindow(night)) {
            try db.editSleepWindow(userId: user, date: night, start: bed, end: wake, onset: wake)
        }
        #expect(try storedNight(db) == nil)
        // Inside — on the bedtime itself is fine (latency 0).
        let row = try db.editSleepWindow(userId: user, date: night, start: bed, end: wake, onset: bed)
        #expect(row.onsetTime == bed)
    }

    @Test("A: the re-aggregated onset lands unless the wheel gave one")
    func strategyATakesOnset() async throws {
        let db = try store()
        let sync = HealthSync(database: db, reader: OnsetHealth(samples: samples), userId: user)
        let fromSamples = try await sync.editSleepWindow(date: night, start: bed, end: wake)
        #expect(fromSamples.onsetTime == min(20) && fromSamples.awakenings == 2)
        let fromWheel = try await sync.editSleepWindow(date: night, start: bed, end: wake, onset: min(45))
        #expect(fromWheel.onsetTime == min(45), "the wheel wins over the samples")
        #expect(fromWheel.awakenings == 2)
    }

    @Test("B: the stored onset survives only while the new window still holds it; the wheel's always wins")
    func strategyBKeepsOrDropsOnset() throws {
        let db = try store()
        try db.writer.write { conn in
            try SleepSessionRow(
                id: "web-night", userId: user, startTime: bed, endTime: wake, durationMin: 431,
                deepMin: 74, remMin: 96, coreMin: 261, awakeMin: 18, createdAt: Date(),
                onsetTime: min(15), awakenings: 1
            ).insert(conn)
        }
        let kept = try db.editSleepWindow(userId: user, date: night, start: bed, end: wake.addingTimeInterval(-1800))
        #expect(kept.onsetTime == min(15) && kept.awakenings == 1)
        let dropped = try db.editSleepWindow(userId: user, date: night, start: min(30), end: wake)
        #expect(dropped.onsetTime == nil, "an onset before the new bedtime is a negative latency")
        let wheel = try db.editSleepWindow(userId: user, date: night, start: min(30), end: wake, onset: min(50))
        #expect(wheel.onsetTime == min(50))
    }

    // MARK: The builder

    /// The 2026-09-18 reference night: in bed 00:16, asleep 03:05, awake 10:30,
    /// usual bedtime 23:30. Written in UTC so the window arithmetic is the
    /// fixture's own; the offsets are noon-anchored either way.
    private let refDate = "2026-09-18"
    private var refWindow: (from: Date, to: Date) { NightWindow.range("2026-09-18")! }
    private var refBed: Date { refWindow.from.addingTimeInterval((12 * 60 + 16) * 60) }   // 00:16
    private var refOnset: Date { refWindow.from.addingTimeInterval((15 * 60 + 5) * 60) }  // 03:05
    private var refWake: Date { refWindow.from.addingTimeInterval((22 * 60 + 30) * 60) }  // 10:30

    private func seedUsualNights(_ db: AppDatabase, count: Int) throws {
        try db.writer.write { conn in
            for i in 1...count {
                let d = ISODate.addDays(refDate, -i)!
                let w = NightWindow.range(d)!
                let start = w.from.addingTimeInterval((11 * 60 + 30) * 60)                 // 23:30 the evening before
                try SleepSessionRow(
                    id: "usual-\(i)", userId: user, startTime: start,
                    endTime: start.addingTimeInterval(8 * 3600), durationMin: 450, createdAt: start
                ).insert(conn)
            }
        }
    }

    private func refInputs(_ db: AppDatabase) throws -> ScoringInputs {
        try #require(try db.scoringInputs(
            userId: user, date: refDate, hoursAwake: 12, isRestDay: false, todayISO: "2026-09-19"
        ))
    }

    @Test("the reference night fills all five terms and scores in the fifties")
    func referenceNight() throws {
        let db = try store()
        try seedUsualNights(db, count: 5)
        try db.writer.write { conn in
            // The watch labels the 169-minute lie-awake AWAKE, plus 11 real
            // minutes after onset: awake_min 180, of which 11 are fragmentation.
            try SleepSessionRow(
                id: "ref", userId: user, startTime: refBed, endTime: refWake, durationMin: 445,
                deepMin: 60, remMin: 80, coreMin: 305, awakeMin: 180, createdAt: refWake,
                onsetTime: refOnset, awakenings: 0
            ).insert(conn)
        }
        let i = try refInputs(db)
        #expect(abs(i.sleepHours - 445.0 / 60) < 1e-9)
        #expect(abs((i.sleepInBedHours ?? 0) - 614.0 / 60) < 1e-9)
        #expect(i.sleepLatencyMin == 169)
        #expect(i.sleepAwakeMin == 11, "awake_min less the latency")
        #expect(i.sleepAwakenings == 0)
        #expect(i.sleepBedtimeDeltaMin == 46, "00:16 against a 23:30 median")
        let score = try #require(Score.sleep(i))
        #expect(score >= 55 && score <= 60, "v1 said 100; the reference night is \(score)")
    }

    @Test("a pre-W3 row fills nothing but duration — and no bed window means no efficiency")
    func legacyRowFillsNothing() throws {
        let db = try store()
        try db.writer.write { conn in
            try SleepSessionRow(
                id: "legacy", userId: user, startTime: refBed, endTime: refBed, durationMin: 445, createdAt: refBed
            ).insert(conn)
        }
        let i = try refInputs(db)
        #expect(i.sleepInBedHours == nil && i.sleepLatencyMin == nil && i.sleepAwakeMin == nil)
        #expect(i.sleepAwakenings == nil && i.sleepBedtimeDeltaMin == nil)
    }

    @Test("regularity needs five nights: four is nil, five is a median, the day itself is excluded")
    func regularityBaselineEdge() throws {
        let db = try store()
        try db.writer.write { conn in
            try SleepSessionRow(
                id: "ref", userId: user, startTime: refBed, endTime: refWake, durationMin: 445, createdAt: refWake
            ).insert(conn)
        }
        try seedUsualNights(db, count: 4)
        #expect(try refInputs(db).sleepBedtimeDeltaMin == nil)
        #expect(try db.bedtimeOffsets(userId: user, before: refDate).count == 4)

        try db.writer.write { conn in
            let d = ISODate.addDays(refDate, -5)!
            let start = NightWindow.range(d)!.from.addingTimeInterval((11 * 60 + 30) * 60)
            try SleepSessionRow(
                id: "usual-5", userId: user, startTime: start,
                endTime: start.addingTimeInterval(8 * 3600), durationMin: 450, createdAt: start
            ).insert(conn)
        }
        let offsets = try db.bedtimeOffsets(userId: user, before: refDate)
        #expect(offsets.count == 5 && offsets.allSatisfy { $0 == 690 }, "23:30 is 690 min past the window's noon")
        #expect(try refInputs(db).sleepBedtimeDeltaMin == 46)
        #expect(ScoringInputsBuilderProbe.median([1, 5, 3, 2, 4]) == 3)
        #expect(ScoringInputsBuilderProbe.median([1, 5, 3, 2, 4, 6]) == 3.5)
    }
}

/// `median` is a static on the builder's extension; named here so a test can
/// reach it without restating the file it lives in.
private enum ScoringInputsBuilderProbe {
    static func median(_ v: [Double]) -> Double? { AppDatabase.median(v) }
}
