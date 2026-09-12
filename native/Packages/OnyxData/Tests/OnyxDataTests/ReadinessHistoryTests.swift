import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// The row → series rules of readiness v9, on the phone — the same cases
/// the web app's `tests/readiness-history.test.ts` pins on the web, so the two builders
/// have one written contract. The formulas downstream are vector-proven; this
/// is the half a vector cannot see.
@Suite("Readiness history — rows onto the 49-day calendar")
struct ReadinessHistoryTests {
    private let user = "u1"
    private let day = "2026-09-05"

    private func seeded() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let now = Date()
        try db.writer.write { conn in
            func log(_ id: String, _ date: String, hrv: Double?, rhr: Int?) throws {
                try DailyLogRow(id: id, userId: user, date: date, avgRestHeartRate: rhr, createdAt: now, updatedAt: now,
                                hrvMs: hrv, nutritionEstimated: false, sleepOnsetTrouble: false).insert(conn)
            }
            try log("l1", "2026-09-05", hrv: 48, rhr: 55)
            try log("l2", "2026-09-04", hrv: nil, rhr: 54)
            try log("l3", "2026-08-01", hrv: 62, rhr: 51)
            try log("l4", "2026-06-01", hrv: 99, rhr: 99)                 // outside the window
            try DailyMetricRow(id: "m1", userId: user, date: "2026-09-04", restHr: 57, createdAt: now, updatedAt: now).insert(conn)  // beats the log's 54
            try DailyMetricRow(id: "m2", userId: user, date: "2026-09-03", restHr: 53, createdAt: now, updatedAt: now).insert(conn)  // the only reading that day
            try WorkoutSession(id: "s1", userId: user, dayKey: "legs_a", date: "2026-09-05", durationMin: 60, sessionRpe: 8).insert(conn)
            try WorkoutSession(id: "s2", userId: user, dayKey: "legs_a", date: "2026-09-04", durationMin: 50, sessionRpe: nil).insert(conn)
            try WorkoutSession(id: "s3", userId: user, dayKey: "legs_a", date: "2026-06-01", durationMin: 60, sessionRpe: 9).insert(conn)
            try CardioLogRow(id: "c1", userId: user, date: "2026-09-04", kind: "walk", durationMin: 30, effort: 3).insert(conn)
            try CardioLogRow(id: "c2", userId: user, date: "2026-09-03", kind: "walk", durationMin: 30, effort: nil).insert(conn)
            // The nights (E3): the 5th holds two rows — the longest is the night;
            // the 4th is a duration-only legacy row; the 3rd a still night WITH
            // stages; a bedtime after noon on the 1st files under the 2nd.
            func night(_ id: String, _ iso: String, _ dur: Int, deep: Int, rem: Int, awake: Int) throws {
                let start = ISO8601DateFormatter().date(from: iso)!
                try SleepSessionRow(id: id, userId: user, startTime: start, endTime: start.addingTimeInterval(TimeInterval(dur) * 60),
                                    durationMin: dur, deepMin: deep, remMin: rem, coreMin: dur - deep - rem, awakeMin: awake, createdAt: now).insert(conn)
            }
            try night("n1", "2026-09-04T22:46:00Z", 431, deep: 74, rem: 96, awake: 18)
            try night("n1b", "2026-09-04T23:30:00Z", 90, deep: 0, rem: 0, awake: 0)
            try night("n2", "2026-09-03T23:00:00Z", 420, deep: 0, rem: 0, awake: 0)
            try night("n3", "2026-09-02T22:00:00Z", 400, deep: 60, rem: 80, awake: 0)
            try night("n4", "2026-09-01T13:00:00Z", 300, deep: 30, rem: 40, awake: 30)
            try night("n5", "2026-06-01T23:00:00Z", 999, deep: 1, rem: 1, awake: 999)   // outside the window
            // Another user's rows never leak in.
            try DailyLogRow(id: "x1", userId: "u2", date: "2026-09-05", avgRestHeartRate: 99, createdAt: now, updatedAt: now,
                            hrvMs: 99, nutritionEstimated: false, sleepOnsetTrouble: false).insert(conn)
        }
        return db
    }

    private func history(_ db: AppDatabase) throws -> ReadinessHistory {
        try db.read { conn in try AppDatabase.readinessHistory(conn, userId: user, date: day) }
    }

    @Test("49 consecutive dates ending on the day itself")
    func calendar() {
        let dates = AppDatabase.readinessHistoryDates(day)
        #expect(dates.count == Readiness.constants.historyDays)
        #expect(dates.first == "2026-07-19")
        #expect(dates.last == day)
        #expect(dates[41] == "2026-08-29")
    }

    @Test("every series lies on the calendar, newest last, out-of-window rows dropped")
    func series() throws {
        let h = try history(try seeded())
        #expect(h.hrv.count == 49 && h.rhr.count == 49 && h.loads.count == 49)
        #expect(h.hrv[48] == 48)
        #expect(h.hrv[47] == nil)
        #expect(h.hrv[13] == 62)
        #expect(!h.hrv.contains(99))
    }

    @Test("resting HR reads daily_metrics first and the log second — the scorer's own rule")
    func restingHrPrecedence() throws {
        let h = try history(try seeded())
        #expect(h.rhr[48] == 55)
        #expect(h.rhr[47] == 57)
        #expect(h.rhr[46] == 53)
        #expect(h.rhr[45] == nil)
    }

    @Test("loads sum per day; an unrated session at the default, an unrated walk at zero, an empty day a real zero")
    func loads() throws {
        let h = try history(try seeded())
        #expect(h.loads[48] == 480)
        #expect(h.loads[47] == 7 * 50 + 3 * 30)
        #expect(h.loads[46] == 0)
        #expect(h.loads[..<46].allSatisfy { $0 == 0 })
    }

    @Test("the nights lie on the calendar: longest wins, duration-only has no awake, noon files under tomorrow")
    func nights() throws {
        let h = try history(try seeded())
        let asleep = try #require(h.asleepMin)
        let awake = try #require(h.awakeMin)
        #expect(asleep.count == 49 && awake.count == 49)
        #expect(asleep[48] == 431 && awake[48] == 18)
        #expect(asleep[47] == 420 && awake[47] == nil)      // duration-only
        #expect(asleep[46] == 400 && awake[46] == 0)        // a real still night
        #expect(asleep[45] == 300 && awake[45] == 30)       // 2026-09-01T13:00Z → the 2nd
        #expect(asleep[44] == nil)
        #expect(!asleep.contains(999))
    }

    @Test("the stress inputs read the same scalars the battery does, plus the two it cannot see")
    func stressInputs() throws {
        let db = try seeded()
        try db.writer.write { conn in
            try FatigueLogRow(id: "f1", userId: user, date: day, slot: "waking", level: 2, createdAt: Date()).insert(conn)
            try FatigueLogRow(id: "f2", userId: user, date: day, slot: "post", level: 4, createdAt: Date()).insert(conn)
        }
        let s = try db.stressInputs(userId: user, date: day)
        let signals = Readiness.signals(try history(db))
        #expect(s.hrvZ == signals.hrv.z && s.rhrZ == signals.rhr.z)
        #expect(s.acwr == signals.load.acwr && s.strainZ == signals.load.strainZ)
        #expect(s.fatigueDayMean == 3, "the mean of 2 and 4, not the latest")
        #expect(s.sleepOnsetTrouble == false, "the column is NOT NULL DEFAULT false")
        #expect(s.fragZ == nil, "four nights cannot make a baseline")
        // The series is exactly the asked-for fortnight, computed on read.
        let series = try db.stressSeries(userId: user, endingOn: day, limit: 5)
        #expect(series.count == 5 && series.last?.d == day)
        #expect(series.last?.empty == false)
        #expect(series.last?.term(.selfReport) == 0)
    }

    @Test("a session logged on a scheduled rest day makes it a training day for the fold")
    func aLoggedSessionOutranksThePlan() throws {
        let db = try seeded()   // `s1` is on `day`
        try db.writer.write { conn in
            // The plan said rest; the athlete trained anyway. The fatigue rows
            // were answered under the day the athlete HAD, not the one the
            // calendar promised: `noon` was taken before training.
            try ScheduleOverrideRow(
                userId: user, date: day, dayKey: Schedule.restOverride, updatedAt: Date()
            ).insert(conn)
            try FatigueLogRow(id: "f1", userId: user, date: day, slot: "noon", level: 5, createdAt: Date()).insert(conn)
            try FatigueLogRow(id: "f2", userId: user, date: day, slot: "midday", level: 1, createdAt: Date()).insert(conn)
            try FatigueLogRow(id: "f3", userId: user, date: day, slot: "waking", level: 3, createdAt: Date()).insert(conn)
        }
        // TRAINING fold: noon→pre 5, midday 1, waking 3 — three answers, mean 3.
        // Read as REST it would be {midday 1, waking 3} = 2, with the pre-session
        // 5 silently merged away under the later modern row.
        #expect(try db.stressInputs(userId: user, date: day).fatigueDayMean == 3)
        // The scorer's wellness item reads the same fold: the LATEST slot on a
        // training day is `pre`, not `midday`.
        let inputs = try #require(try db.scoringInputs(
            userId: user, date: day, hoursAwake: 10, isRestDay: true, todayISO: day
        ))
        #expect(inputs.fatigueLevel == 5)
    }

    @Test("a rest day's fatigue folds as a rest day, so a legacy row does not invent a second slot")
    func fatigueFoldsByTheDayKind() throws {
        let db = try seeded()
        try db.writer.write { conn in
            // The day is a rest day, stated the way the athlete states it.
            try ScheduleOverrideRow(
                userId: user, date: day, dayKey: Schedule.restOverride, updatedAt: Date()
            ).insert(conn)
            // And nothing was logged: a session on the day would make it a
            // training day whatever the override says (see the next test).
            try WorkoutSession.filter(Column("date") == day).deleteAll(conn)
            // A MIXED day: a stale row under the OLD vocabulary and the answer
            // the athlete actually gave under the new one.
            //
            //   read as REST      `noon`→midday, `midday`→midday (modern wins,
            //                     rank 99 over rank 1), `waking`→waking
            //                     = {midday 1, waking 3}, mean 2.0
            //   read as TRAINING  `noon`→pre, `midday`→midday, `waking`→waking
            //                     = {pre 5, midday 1, waking 3}, mean 3.0
            //
            // The 5 is a reading the athlete superseded. Folding the day as a
            // training day resurrects it as a slot of its own, and a whole
            // point of mean fatigue is several points of Stress on a day that
            // had none of it.
            try FatigueLogRow(id: "f1", userId: user, date: day, slot: "noon", level: 5, createdAt: Date()).insert(conn)
            try FatigueLogRow(id: "f2", userId: user, date: day, slot: "midday", level: 1, createdAt: Date()).insert(conn)
            try FatigueLogRow(id: "f3", userId: user, date: day, slot: "waking", level: 3, createdAt: Date()).insert(conn)
        }
        #expect(try db.stressInputs(userId: user, date: day).fatigueDayMean == 2)

        // And the series agrees with the single day — it hoists the schedule
        // rather than resolving it per date, which is exactly where the two
        // could drift apart.
        let series = try db.stressSeries(userId: user, endingOn: day, limit: 3)
        let direct = Stress.breakdown(try db.stressInputs(userId: user, date: day))
        #expect(direct.terms.selfReport.fatigueDayMean == 2)
        #expect(series.last?.term(.selfReport) == direct.terms.selfReport.z)
    }

    @Test("the export's flat shape carries null for null")
    func flattened() throws {
        let flat = ExportReadiness(signals: Readiness.signals(try history(try seeded())))
        #expect(flat.hrvZ == nil && flat.rhrZ == nil)
        #expect(flat.load == 480)
        // Two sessions, both inside the rolling week: no chronic side, no ratio.
        #expect(flat.acwr == nil)
        #expect(flat.acute != nil)
    }
}
