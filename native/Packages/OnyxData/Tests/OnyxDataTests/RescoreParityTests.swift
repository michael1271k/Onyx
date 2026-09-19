import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// The cascade rewrite (W2, decision 17) against the per-day path it replaced.
///
/// ── WHY A VECTOR AND NOT A LIVE COMPARISON ──────────────────────────────────
/// The per-day path (`refreshDailyScore` → ~15 queries per day) was deleted
/// once `ScoringWindow` reproduced it row for row. The proof outlives the
/// deletion as `expected` below: sixty days of `daily_scores` the OLD path
/// wrote over `DenseSeed`, captured on 2026-09-19 before it went. A row that
/// moves here is a scoring rule that changed, and `invariant-auditor` reviews
/// it before the number is edited.
///
/// The seed is deliberately dense — every table the scorer reads, an exact
/// duration tie in the night window inserted out of bedtime order, a bare day
/// holding one 0 ml water row, a double-session day on the six-session
/// boundary, a unilateral pair, a ghost set, a warm-up, an exception day, a
/// rest override, a lever period, a deload phase — so the vector pins the
/// branches and not just the happy path.
@Suite("The cascade rewrite")
struct RescoreParityTests {

    private static let user = "parity-user"
    /// The clock: 2026-09-18 14:00 UTC.
    private static let now = Date(timeIntervalSince1970: 1_789_740_000)
    private static let today = "2026-09-18"
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    /// Sixty days ending today.
    private static let dates: [String] = (0..<60).map { ISODate.addDays("2026-07-21", $0)! }

    private static func seeded() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "parity")
        try DenseSeed.seed(db, userId: user, from: "2026-05-01", days: 141)
        return db
    }

    /// One row, as the vector stores it.
    struct Scored: Equatable, CustomStringConvertible {
        var date: String
        var score: Int
        var sleep: Int?
        var nutrition: Int?
        var activity: Int?
        var workout: Int?
        var recovery: Int?
        var battery: Int?
        var finalized: Bool

        init(_ r: DailyScoreRow) {
            date = r.date; score = r.score; sleep = r.sleepScore; nutrition = r.nutritionScore
            activity = r.activityScore; workout = r.workoutScore; recovery = r.recoveryScore
            battery = r.batteryPct; finalized = r.finalized
        }
        init(_ date: String, _ score: Int, _ sleep: Int?, _ nutrition: Int?, _ activity: Int?,
             _ workout: Int?, _ recovery: Int?, _ battery: Int?, _ finalized: Bool) {
            self.date = date; self.score = score; self.sleep = sleep; self.nutrition = nutrition
            self.activity = activity; self.workout = workout; self.recovery = recovery
            self.battery = battery; self.finalized = finalized
        }
        var description: String {
            func o(_ v: Int?) -> String { v.map(String.init) ?? "nil" }
            return "Scored(\"\(date)\", \(score), \(o(sleep)), \(o(nutrition)), \(o(activity)), \(o(workout)), \(o(recovery)), \(o(battery)), \(finalized)),"
        }
    }

    private static func rows(_ db: AppDatabase) throws -> [Scored] {
        try db.dailyScores(userId: user, from: dates.first!, to: dates.last!).map(Scored.init)
    }

    @Test("sixty days through the window equal the per-day path's vector")
    func windowMatchesTheVector() throws {
        let db = try Self.seeded()
        let written = try db.rescoreWindow(
            userId: Self.user, dates: Self.dates, now: Self.now, calendar: Self.calendar, force: true
        )
        let got = try Self.rows(db)
        if ProcessInfo.processInfo.environment["ONYX_PRINT_PARITY"] != nil {
            for r in got { print(r) }
        }
        #expect(written.count == got.count)
        #expect(got.count == Self.expected.count, "a day appeared or vanished")
        #expect(got.count == 59, "the bare 0 ml day (2026-08-04) reaches the scorer and scores nothing — no row, on both paths")
        for (g, e) in zip(got, Self.expected) where g != e {
            Issue.record("\(g.date): got \(g) expected \(e)")
        }
    }

    @Test("the window is idempotent, and today stays live")
    func windowIsIdempotent() throws {
        let db = try Self.seeded()
        _ = try db.rescoreWindow(userId: Self.user, dates: Self.dates, now: Self.now, calendar: Self.calendar, force: true)
        let first = try Self.rows(db)
        _ = try db.rescoreWindow(userId: Self.user, dates: Self.dates, now: Self.now, calendar: Self.calendar, force: true)
        #expect(try Self.rows(db) == first)
        #expect(first.last?.date == Self.today && first.last?.finalized == false)
        #expect(first.dropLast().allSatisfy { $0.finalized })
    }

    @Test("without force, a sealed day is left alone — the sync's refresh")
    func freezeStillHolds() throws {
        let db = try Self.seeded()
        let day = "2026-09-11"
        _ = try db.rescoreWindow(userId: Self.user, dates: [day], now: Self.now, calendar: Self.calendar)
        let sealed = try #require(try db.dailyScore(userId: Self.user, date: day))
        #expect(sealed.finalized)
        try db.writer.write { conn in
            try conn.execute(sql: "UPDATE daily_metrics SET steps = 30000 WHERE user_id = ? AND date = ?", arguments: [Self.user, day])
        }
        let again = try db.rescoreWindow(userId: Self.user, dates: [day], now: Self.now, calendar: Self.calendar)
        #expect(again.isEmpty, "the freeze refused it")
        #expect(try db.dailyScore(userId: Self.user, date: day)?.activityScore == sealed.activityScore)
        let forced = try db.rescoreWindow(userId: Self.user, dates: [day], now: Self.now, calendar: Self.calendar, force: true)
        #expect(forced.count == 1)
        #expect(try db.dailyScore(userId: Self.user, date: day)?.activityScore != sealed.activityScore)
    }

    @Test("a 49-day cascade through the window is one write transaction")
    func oneWriteTransaction() throws {
        let db = try Self.seeded()
        let commits = CommitCounter()
        let observer = db.onCommit { commits.bump() }
        defer { observer.cancel() }
        let dates = Array(Self.dates.suffix(49))
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            _ = try db.rescoreWindow(userId: Self.user, dates: dates, now: Self.now, calendar: Self.calendar, force: true)
        }
        // `onCommit` observes the full database, so this counts the score
        // writes and nothing else — the seed happened before the observer.
        #expect(commits.count == 1, "49 days must land in ONE commit")
        print("rescore.run 49 days (window): \(elapsed)")
    }

    @Test("a 0 ml water row is a row — the ghost guard reads presence, not the sum")
    func zeroMlWaterIsStillData() throws {
        let db = try Self.seeded()
        // 2026-08-04 holds exactly one water row, at 0 ml, and nothing else.
        let inputs = try db.scoringInputs(
            userId: Self.user, date: "2026-08-04", hoursAwake: Battery.defaults.maxAwake,
            isRestDay: true, todayISO: Self.today
        )
        #expect(inputs != nil, "the old path read `!water.isEmpty`; a sum of zero must not turn a logged day into a ghost")
        #expect(inputs?.waterMl == 0)
    }

    // MARK: - The vector

    /// The OLD path's output over `DenseSeed`, sixty days ending 2026-09-18.
    /// Regenerate ONLY with `invariant-auditor`'s sign-off:
    /// `ONYX_PRINT_PARITY=1 npm run swift:data -- --filter RescoreParityTests`.
    static let expected: [Scored] = [
        Scored("2026-07-21", 49, 38, 88, 81, nil, 60, 46, true),
        Scored("2026-07-22", 70, 72, 82, 68, 80, 75, 41, true),
        Scored("2026-07-23", 76, 84, 80, 68, nil, 91, 52, true),
        Scored("2026-07-24", 48, 45, nil, 100, 100, 53, 22, true),
        Scored("2026-07-25", 71, 59, 79, 79, nil, 73, 49, true),
        Scored("2026-07-26", 77, 87, 76, 79, nil, 87, 51, true),
        Scored("2026-07-27", 75, 70, 82, 67, 93, 71, 36, true),
        Scored("2026-07-28", 76, 81, 81, nil, nil, 91, 55, true),
        Scored("2026-07-29", 50, 42, 87, 47, 85, 57, 34, true),
        Scored("2026-07-30", 73, nil, nil, 85, nil, 76, 17, true),
        Scored("2026-07-31", 81, 95, 81, 68, nil, 94, 39, true),
        Scored("2026-08-01", 78, 81, 78, 78, nil, 95, 46, true),
        Scored("2026-08-02", 50, 41, 69, 85, nil, 60, 46, true),
        Scored("2026-08-03", 83, 97, 81, 75, 93, 96, 40, true),
        Scored("2026-08-05", 52, 46, nil, 100, 93, 52, 32, true),
        Scored("2026-08-06", 79, 84, 82, 86, nil, 88, 53, true),
        Scored("2026-08-07", 69, 60, 84, 74, 80, 70, 40, true),
        Scored("2026-08-08", 80, 85, 82, nil, nil, 86, 56, true),
        Scored("2026-08-09", 77, nil, 81, 71, nil, 93, 26, true),
        Scored("2026-08-10", 83, 85, 74, 99, 99, 98, 42, true),
        Scored("2026-08-11", 83, 84, nil, 100, nil, 75, 46, true),
        Scored("2026-08-12", 53, 42, 74, 100, 93, 63, 29, true),
        Scored("2026-08-13", 77, 86, 78, 77, nil, 86, 52, true),
        Scored("2026-08-14", 51, 29, 83, 60, 99, 59, 32, true),
        Scored("2026-08-15", 55, 50, 84, 94, nil, 62, 43, true),
        Scored("2026-08-16", 77, 88, 95, 53, nil, 88, 53, true),
        Scored("2026-08-17", 82, 82, nil, 80, 93, 85, 32, true),
        Scored("2026-08-18", 63, 54, 78, 86, nil, 58, 44, true),
        Scored("2026-08-19", 77, nil, 77, nil, 93, 100, 22, true),
        Scored("2026-08-20", 84, 84, 74, 100, nil, 90, 46, true),
        Scored("2026-08-21", 79, 83, 70, 86, 93, 80, 36, true),
        Scored("2026-08-22", 75, 82, 80, 66, nil, 78, 51, true),
        Scored("2026-08-23", 48, 34, nil, 93, nil, 49, 42, true),
        Scored("2026-08-24", 68, 56, 77, 100, 86, 69, 36, true),
        Scored("2026-08-25", 58, 55, 78, 70, nil, 67, 45, true),
        Scored("2026-08-26", 63, 53, 100, 100, nil, 62, 19, true),
        Scored("2026-08-27", 73, 86, 65, 71, nil, 97, 45, true),
        Scored("2026-08-28", 69, 65, 81, 52, 93, 71, 29, true),
        Scored("2026-08-29", 62, nil, nil, 66, nil, nil, 26, true),
        Scored("2026-08-30", 78, 82, 89, nil, nil, 86, 56, true),
        Scored("2026-08-31", 74, 71, 87, 56, 93, 78, 38, true),
        Scored("2026-09-01", 86, 82, 81, 100, nil, 94, 47, true),
        Scored("2026-09-02", 80, 75, 81, 99, 87, 74, 37, true),
        Scored("2026-09-03", 67, 78, 65, 54, nil, 84, 52, true),
        Scored("2026-09-04", 48, 46, nil, 70, 94, 55, 30, true),
        Scored("2026-09-05", 77, 80, 84, 90, nil, 66, 47, true),
        Scored("2026-09-06", 47, 43, 81, 99, nil, 48, 43, true),
        Scored("2026-09-07", 85, 82, 81, 92, 99, 96, 33, true),
        Scored("2026-09-08", 72, nil, 71, 72, nil, 86, 26, true),
        Scored("2026-09-09", 71, 60, 76, 74, 83, 79, 39, true),
        Scored("2026-09-10", 46, 40, nil, nil, nil, 54, 48, true),
        Scored("2026-09-11", 72, 81, 69, 67, 91, 87, 37, true),
        Scored("2026-09-12", 51, 42, 68, 91, nil, 56, 43, true),
        Scored("2026-09-13", 80, 73, 87, 88, nil, 82, 46, true),
        Scored("2026-09-14", 84, 75, 87, 77, 98, 89, 34, true),
        Scored("2026-09-15", 77, 86, 74, 83, nil, 100, 53, true),
        Scored("2026-09-16", 49, 39, nil, 47, 93, 53, 32, true),
        Scored("2026-09-17", 76, 75, 68, 100, nil, 82, 46, true),
        Scored("2026-09-18", 78, nil, 76, 74, 80, 100, 44, false),
    ]
}

private final class CommitCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.withLock { n } }
    func bump() { lock.withLock { n += 1 } }
}

// MARK: - The seed

/// A plausible account, every table the scorer reads, deterministic.
enum DenseSeed {

    /// A tiny LCG so the seed is the same on every machine and every run.
    struct Rng {
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        mutating func next(_ n: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(n))
        }
    }

    static func seed(_ db: AppDatabase, userId: String, from: String, days: Int) throws {
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        try db.seedRows { conn in
            var rng = Rng()
            try UserGoalRow(
                id: "g-\(userId)", userId: userId, sleepGoalHours: 8, calorieGoal: 2100,
                proteinGoalG: 170, carbsGoalG: 220, fatGoalG: 65, stepsGoal: 9000, activeCalGoal: 500,
                waterGoalMl: 3000, contextMode: "normal", createdAt: t, updatedAt: t,
                autoLogSupplements: false, activeProgram: "dense", dayCutoffHour: 0,
                unitSystem: "metric", reduceMotion: false, timezone: "UTC",
                activePlan: "plan-dense", trackRpe: true, activeLever: "cut"
            ).insert(conn)
            try PlanRow(
                id: "plan-dense", userId: userId, name: "Dense", programId: "dense", active: true,
                startedOn: from, createdAt: t, sort: 0
            ).insert(conn)
            let lifts = ["Bench Press", "Barbell Row", "Back Squat", "Overhead Press", "Romanian Deadlift", "Pull Up"]
            for name in lifts { try Exercise(id: ExerciseSlug.id(name), name: name).insert(conn) }
            let dayKeys = ["push", "pull", "legs"]
            for (i, key) in dayKeys.enumerated() {
                let pair = Array(lifts[(i * 2)..<(i * 2 + 2)])
                try RoutineRow(
                    userId: userId, programId: "dense", dayKey: key, label: key.capitalized,
                    weekday: [1, 3, 5][i], accent: i, sort: i,
                    payload: JSONText(raw: RoutinePayload(exercises: pair.map {
                        RoutineExercise(name: $0, sets: 3, cutSets: 3, reps: "8-12", restSec: 90)
                    }).encoded()),
                    updatedAt: t
                ).insert(conn)
            }
            try TargetProfileRow(
                userId: userId, key: "cut", label: "Cut", sort: 0, kcal: 1900, proteinG: 175, carbsG: 180, fatG: 60,
                stepsGoal: 10_000, updatedAt: t
            ).insert(conn)
            try LeverPeriodRow(userId: userId, startsOn: ISODate.addDays(from, 30)!, profileKey: "cut", updatedAt: t).insert(conn)
            // A planned deload inside the vector's window, so `isMaintenance`
            // and the full-effort filter on the trailing volume both fire.
            try PlanPhaseRow(
                userId: userId, planId: "plan-dense", start: "2026-08-10", kind: "deload", name: "Deload",
                weeks: 2, numbered: false, updatedAt: t
            ).insert(conn)

            var sessionCount = 0
            for i in 0..<days {
                let date = ISODate.addDays(from, i)!
                let noon = NightWindow.range(date)!.to
                let dayId = String(date.suffix(5)).replacingOccurrences(of: "-", with: "")

                // ── THE BARE DAY ────────────────────────────────────────────
                // One 0 ml water row and nothing else: a row is a row, so the
                // ghost guard must still score it. 2026-08-04, a Tuesday.
                if i == 95 {
                    try WaterIntakeRow(id: "w\(dayId)-0", userId: userId, loggedAt: noon, date: date, amountMl: 0, createdAt: t).insert(conn)
                    continue
                }

                if i % 11 != 0 {
                    try DailyMetricRow(
                        id: "m\(dayId)", userId: userId, date: date, steps: 3000 + rng.next(9000),
                        activeCal: 200 + rng.next(600), restHr: i % 4 == 0 ? nil : 52 + rng.next(10),
                        createdAt: t, updatedAt: t
                    ).insert(conn)
                }
                if i % 8 != 0 {
                    try DailyLogRow(
                        id: "l\(dayId)", userId: userId, date: date, avgRestHeartRate: 50 + rng.next(12),
                        createdAt: t, updatedAt: t, hrvMs: i % 7 == 0 ? nil : Double(40 + rng.next(40)),
                        nutritionException: i % 13 == 0 ? "travel" : nil, nutritionEstimated: false,
                        sleepOnsetTrouble: i % 9 == 0, sleepInaccurate: nil
                    ).insert(conn)
                }
                if i % 10 != 0 {
                    let bedOffsetSec: Double = Double(10 * 3600 + 30 * 60 + rng.next(150) * 60)
                    let bed = noon.addingTimeInterval(bedOffsetSec - 24 * 3600)
                    let minutes = 300 + rng.next(200)
                    let end = bed.addingTimeInterval(Double(minutes + 20 + rng.next(40)) * 60)
                    try SleepSessionRow(
                        id: "s\(dayId)", userId: userId, startTime: bed, endTime: end, durationMin: minutes,
                        deepMin: 40 + rng.next(60), remMin: 60 + rng.next(60), awakeMin: rng.next(40), createdAt: t,
                        onsetTime: i % 5 == 0 ? nil : bed.addingTimeInterval(Double(rng.next(30) * 60)),
                        awakenings: rng.next(5)
                    ).insert(conn)
                    if i % 23 == 0 {
                        // A second row in the same window with the SAME duration,
                        // an EARLIER bedtime and a LATER rowid: the tie goes to
                        // scan order, i.e. the first inserted, whatever its
                        // bedtime. Different stage data so the choice shows.
                        try SleepSessionRow(
                            id: "s\(dayId)b", userId: userId, startTime: bed.addingTimeInterval(-3600),
                            endTime: bed.addingTimeInterval(Double(minutes) * 60), durationMin: minutes,
                            deepMin: 5, remMin: 5, awakeMin: 0, createdAt: t, awakenings: 0
                        ).insert(conn)
                    }
                }
                if i % 6 != 0 {
                    try NutritionEntryRow(
                        id: "n\(dayId)", userId: userId, loggedAt: noon, date: date, mealType: "daily",
                        calories: Double(1500 + rng.next(1200)), proteinG: Double(100 + rng.next(120)),
                        carbsG: Double(120 + rng.next(200)), fatG: Double(40 + rng.next(60)), createdAt: t
                    ).insert(conn)
                }
                for g in 0..<(2 + rng.next(4)) {
                    try WaterIntakeRow(
                        id: "w\(dayId)-\(g)", userId: userId, loggedAt: noon, date: date,
                        amountMl: [250, 330, 500][rng.next(3)], createdAt: t
                    ).insert(conn)
                }
                if i % 3 == 0 {
                    for k in 0..<(1 + rng.next(3)) {
                        try SupplementLogRow(userId: userId, date: date, itemKey: "item-\(k)", taken: k % 2 == 0, updatedAt: t).insert(conn)
                    }
                }
                if i % 2 == 0 {
                    try FatigueLogRow(
                        id: "f\(dayId)", userId: userId, date: date, slot: ["morning", "evening"][rng.next(2)],
                        level: rng.next(5), createdAt: t
                    ).insert(conn)
                }
                if i % 3 == 1 {
                    for m in 0..<(1 + rng.next(3)) {
                        try DomsLogRow(
                            id: "d\(dayId)-\(m)", userId: userId, date: date,
                            muscleGroup: DomsMuscles.all[rng.next(DomsMuscles.all.count)], severity: 1 + rng.next(3), createdAt: t,
                            side: m == 0 ? "L" : nil
                        ).insert(conn)
                    }
                }
                if i % 4 == 2 {
                    try CardioLogRow(
                        id: "c\(dayId)", userId: userId, date: date, kind: "walk",
                        durationMin: Double(20 + rng.next(30)), createdAt: t, effort: Double(3 + rng.next(5))
                    ).insert(conn)
                }
                if i % 15 == 7 {
                    try DailyTargetRow(userId: userId, date: date, kcal: 1800, proteinG: 180, updatedAt: t, trackCarbs: true, trackFat: true).insert(conn)
                }
                if i % 19 == 4 {
                    try ScheduleOverrideRow(userId: userId, date: date, dayKey: Schedule.restOverride, updatedAt: t).insert(conn)
                }

                // Sessions on three weekdays, plus a double day now and then.
                guard let weekday = ISODate.weekday(date), [1, 3, 5].contains(weekday) else { continue }
                let sessionsToday = i % 21 == 0 ? 2 : 1
                for s in 0..<sessionsToday {
                    sessionCount += 1
                    let key = dayKeys[[1, 3, 5].firstIndex(of: weekday)!]
                    let started = noon.addingTimeInterval(Double(5 * 3600 + s * 5400))
                    let minutes = Double(50 + rng.next(40))
                    let sessionId = "ws\(dayId)-\(s)"
                    try WorkoutSession(
                        id: sessionId, userId: userId, dayKey: key, date: date, startedAt: started,
                        endedAt: started.addingTimeInterval(minutes * 60), durationMin: minutes,
                        sessionRpe: sessionCount % 6 == 0 ? nil : Double(6 + rng.next(4))
                    ).insert(conn)
                    let pair = Array(lifts[(dayKeys.firstIndex(of: key)! * 2)..<(dayKeys.firstIndex(of: key)! * 2 + 2)])
                    var setIndex = 0
                    for (e, name) in pair.enumerated() {
                        let base = 40.0 + Double(i) * 0.25 + Double(e) * 10
                        for n in 0..<3 {
                            setIndex += 1
                            let weight = base + Double(rng.next(5)) * 2.5
                            let reps = 8 + rng.next(5)
                            var type = "normal"
                            if e == 0 && n == 0 { type = "warmup" }
                            if sessionCount % 4 == 0 && n == 2 { type = "ghost" }
                            if sessionCount % 7 == 0 && n == 1 { type = "failure" }
                            let split = sessionCount % 5 == 0 && e == 1 && n == 1
                            for side in (split ? ["left", "right"] : [nil]) {
                                try WorkoutSet(
                                    id: "set-\(sessionId)-\(setIndex)-\(side ?? "b")", sessionId: sessionId,
                                    exerciseId: ExerciseSlug.id(name), setIndex: setIndex,
                                    weightKg: split ? weight / 2 : weight, reps: reps, setType: type,
                                    side: side, pairId: split ? "pair-\(sessionId)-\(setIndex)" : nil,
                                    est1rmKg: OneRepMax.estimate(weight: weight, reps: Double(reps))
                                ).insert(conn)
                            }
                        }
                    }
                    if sessionCount % 3 == 0 {
                        try PersonalRecordRow(
                            userId: userId, exerciseKey: pair[0], axis: "weight", value: 100 + Double(sessionCount),
                            reps: 8, weightKg: 100 + Double(sessionCount), sessionId: sessionId, achievedOn: date, updatedAt: t
                        ).save(conn)
                    }
                }
            }
        }
    }
}
