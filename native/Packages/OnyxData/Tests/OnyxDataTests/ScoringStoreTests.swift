import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

@Suite("Scoring inputs")
struct ScoringInputsTests {

    private let user = "u1"
    private let day = "2026-09-03"

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    private func inputs(
        _ db: AppDatabase, date: String? = nil, isToday: Bool = false,
        supplements: ScoringSupplements = ScoringSupplements()
    ) throws -> ScoringInputs? {
        try db.scoringInputs(
            userId: user, date: date ?? day, hoursAwake: 12,
            isRestDay: false, todayISO: "2026-09-04", isToday: isToday,
            supplements: supplements
        )
    }

    // MARK: The ghost guard

    @Test("a past day with nothing behind it gets no inputs at all")
    func ghostGuard() throws {
        // Trailing baselines and rest-day logic can fabricate a score out of
        // nothing, and a score-only "ghost day" pollutes every chart that reads
        // the journey.
        let db = try store()
        #expect(try inputs(db) == nil)
    }

    @Test("today is exempt from the guard — it accumulates")
    func todayIsExempt() throws {
        let db = try store()
        #expect(try inputs(db, isToday: true) != nil)
    }

    @Test("one water row is enough to make the day real")
    func anySignalDefeatsTheGuard() throws {
        let db = try store()
        try db.writer.write { conn in
            try WaterIntakeRow(
                id: "w1", userId: user, loggedAt: Date(), date: day,
                amountMl: 500, createdAt: Date()
            ).insert(conn)
        }
        let got = try #require(try inputs(db))
        #expect(got.waterMl == 500)
    }

    // MARK: Sleep

    @Test("the night is found by its window, not by a date column")
    func sleepComesFromTheNightWindow() throws {
        let db = try store()
        let window = try #require(NightWindow.range(day))
        try db.writer.write { conn in
            // Bedtime is the PREVIOUS EVENING. A `start_time >= date 00:00`
            // filter matched nothing, so the scorer read sleepHours = 0 on
            // every single day — "Awaiting Sleep Data" beside a synced night.
            try SleepSessionRow(
                id: "s1", userId: user,
                startTime: window.from.addingTimeInterval(9 * 3600),
                endTime: window.to.addingTimeInterval(-3 * 3600),
                durationMin: 431, deepMin: 74, remMin: 96, createdAt: Date()
            ).insert(conn)
        }
        let got = try #require(try inputs(db))
        #expect(abs(got.sleepHours - 431.0 / 60) < 0.001)
        #expect(got.deepMinutes == 74)
        #expect(got.remMinutes == 96)
    }

    @Test("the longest session wins when a night has more than one")
    func longestNightWins() throws {
        let db = try store()
        let window = try #require(NightWindow.range(day))
        try db.writer.write { conn in
            for (id, minutes) in [("s1", 90), ("s2", 431)] {
                try SleepSessionRow(
                    id: id, userId: user,
                    startTime: window.from.addingTimeInterval(9 * 3600),
                    endTime: window.to, durationMin: minutes, createdAt: Date()
                ).insert(conn)
            }
        }
        #expect(try #require(try inputs(db)).sleepHours > 7)
    }

    // MARK: Sets

    @Test("a unilateral pair is one set, and a ghost is neither side of the ratio")
    func setArithmetic() throws {
        let db = try store()
        try db.writer.write { conn in
            try WorkoutSession(
                id: "sess", userId: user, dayKey: "legs_a", date: day,
                startedAt: Date(), sessionRpe: 8
            ).insert(conn)
            // One bilateral working set…
            try WorkoutSet(
                id: "a", sessionId: "sess", exerciseId: "onyx-hack-squat",
                setIndex: 1, weightKg: 100, reps: 8
            ).insert(conn)
            // …one unilateral PAIR, which is ONE set…
            try WorkoutSet(
                id: "l", sessionId: "sess", exerciseId: "onyx-split-squat",
                setIndex: 2, weightKg: 40, reps: 10, side: "left", pairId: "p1"
            ).insert(conn)
            try WorkoutSet(
                id: "r", sessionId: "sess", exerciseId: "onyx-split-squat",
                setIndex: 2, weightKg: 42, reps: 10, side: "right", pairId: "p1"
            ).insert(conn)
            // …one warm-up, which is not work…
            try WorkoutSet(
                id: "w", sessionId: "sess", exerciseId: "onyx-hack-squat",
                setIndex: 0, weightKg: 60, reps: 10, setType: "warmup"
            ).insert(conn)
            // …one failure set, which is…
            try WorkoutSet(
                id: "f", sessionId: "sess", exerciseId: "onyx-leg-curl",
                setIndex: 3, weightKg: 55, reps: 6, setType: "failure"
            ).insert(conn)
            // …and one ghost, deliberately not performed.
            try WorkoutSet(
                id: "g", sessionId: "sess", exerciseId: "onyx-calf-raise",
                setIndex: 4, weightKg: 0, reps: 0, setType: "ghost"
            ).insert(conn)
        }

        let got = try #require(try inputs(db, supplements: ScoringSupplements(plannedSets: 20)))
        #expect(got.sessionSets == 3, "bilateral + pair + failure; the warm-up and ghost are not work")
        #expect(got.loggedExercises == 3)
        #expect(got.failureSets == 1)
        // A set marked skipped on purpose leaves BOTH sides of the ratio, or a
        // deliberate decision is graded as an incomplete session.
        #expect(got.plannedSets == 19)
        #expect(got.workoutLogged)
        #expect(got.sessionRpe == 8)
        #expect(got.sessionDayKey == "legs_a")
    }

    @Test("plannedSets stays absent when the programme prescribed nothing")
    func noPrescriptionDropsTheComponent() throws {
        let db = try store()
        try db.writer.write { conn in
            try WorkoutSession(id: "sess", userId: user, date: day, startedAt: Date()).insert(conn)
        }
        // `nil` drops the coverage component rather than inventing a plan.
        #expect(try #require(try inputs(db)).plannedSets == nil)
    }

    // MARK: Baselines

    @Test("the HRV and resting-HR baselines exclude the day being scored")
    func baselinesExcludeToday() throws {
        let db = try store()
        try db.writer.write { conn in
            // The day itself: a high reading that must not raise its own bar.
            try DailyLogRow(
                id: "d0", userId: user, date: day, avgRestHeartRate: 70,
                createdAt: Date(), updatedAt: Date(), hrvMs: 100,
                nutritionEstimated: false, sleepOnsetTrouble: false
            ).insert(conn)
            for (i, hrv) in [40.0, 50.0, 60.0].enumerated() {
                try DailyLogRow(
                    id: "d\(i + 1)", userId: user, date: "2026-09-0\(2 - i)",
                    avgRestHeartRate: 50, createdAt: Date(), updatedAt: Date(), hrvMs: hrv,
                    nutritionEstimated: false, sleepOnsetTrouble: false
                ).insert(conn)
            }
        }
        let got = try #require(try inputs(db))
        #expect(got.hrvMs == 100)
        #expect(got.hrvBaseline == 50, "the mean of 40, 50, 60 — not of the day itself")
        #expect(got.baselineHR == 50)
    }

    @Test("a missing reading is no baseline, never a zero")
    func missingBaselineIsNil() throws {
        let db = try store()
        try db.writer.write { conn in
            try DailyLogRow(
                id: "d0", userId: user, date: day, steps: 900,
                createdAt: Date(), updatedAt: Date(),
                nutritionEstimated: false, sleepOnsetTrouble: false
            ).insert(conn)
        }
        let got = try #require(try inputs(db))
        #expect(got.hrvBaseline == nil)
        #expect(got.hrvMs == nil)
    }

    // MARK: Goals

    @Test("without a resolved lever the stored baseline is used, knowingly")
    func goalsFallBackToTheStoredRow() throws {
        let db = try store()
        try db.writer.write { conn in
            try UserGoalRow(
                id: "g1", userId: user, sleepGoalHours: 8, calorieGoal: 1955,
                proteinGoalG: 190, carbsGoalG: 150, fatGoalG: 60, stepsGoal: 10_000,
                waterGoalMl: 3000, contextMode: "normal", createdAt: Date(), updatedAt: Date(),
                autoLogSupplements: false, activeProgram: "onyx5", dayCutoffHour: 0,
                unitSystem: "metric", reduceMotion: false, timezone: "Asia/Jerusalem", trackRpe: true
            ).insert(conn)
        }
        let got = try #require(try inputs(db, isToday: true))
        #expect(got.calorieGoal == 1955)
        #expect(got.waterGoalMl == 3000)

        // And a resolved lever overrides it — the 70 kcal that otherwise sits
        // between the goal shown and the goal graded, every day, invisibly.
        let levered = try #require(try inputs(db, isToday: true, supplements: ScoringSupplements(
            goals: ResolvedGoals(calorie: 1885, protein: 190, carbs: 130, fat: 55, steps: 10_000)
        )))
        #expect(levered.calorieGoal == 1885)
    }

    @Test("the local hour comes from hours awake, not from a fixed zone")
    func localHour() throws {
        let db = try store()
        let got = try #require(try inputs(db, isToday: true))
        #expect(got.localHour == 19, "07:00 wake convention + 12 hours awake")
        #expect(got.hoursAwake == 12)
    }
}

// MARK: - Writing the score

@Suite("The daily score row")
struct DailyScoreStoreTests {

    private let user = "u1"
    private let day = "2026-09-03"

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    private func write(
        _ db: AppDatabase, total: Int, isToday: Bool, force: Bool = false, now: Date = Date()
    ) throws -> DailyScoreRow? {
        try db.writeDailyScore(
            userId: user, date: day, inputs: ScoringInputs(), hoursAwake: 12,
            isToday: isToday, force: force, now: now
        ) { _ in ScoreComponents(total: total, sleep: 80, nutrition: 70) }
    }

    @Test("a past day is sealed on its first write")
    func pastDayFreezes() throws {
        let db = try store()
        #expect(try write(db, total: 74, isToday: false)?.finalized == true)
        // Re-ingesting old data must never rewrite a snapshot.
        #expect(try write(db, total: 99, isToday: false) == nil)
        #expect(try db.dailyScore(userId: user, date: day)?.score == 74)
    }

    @Test("force is the one way a correction reaches a sealed day")
    func forceBypassesTheFreeze() throws {
        let db = try store()
        _ = try write(db, total: 74, isToday: false)
        _ = try write(db, total: 88, isToday: false, force: true)
        #expect(try db.dailyScore(userId: user, date: day)?.score == 88)
    }

    @Test("today accumulates and stays live")
    func todayIsNotFrozen() throws {
        let db = try store()
        #expect(try write(db, total: 40, isToday: true)?.finalized == false)
        #expect(try write(db, total: 61, isToday: true)?.score == 61)
    }

    @Test("computed_at is rewritten on every write")
    func computedAtMovesForward() throws {
        let db = try store()
        let first = Date(timeIntervalSince1970: 1_788_000_000)
        let later = first.addingTimeInterval(3600)
        _ = try write(db, total: 40, isToday: true, now: first)
        let row = try #require(try write(db, total: 61, isToday: true, now: later))

        // The column defaults to `now()` on INSERT and has no update trigger, so
        // the upsert-UPDATE path kept the FIRST computation's timestamp — a
        // column named "computed at" that meant "first computed at", which made
        // every staleness check see every row as ancient forever.
        #expect(row.computedAt == later)
    }

    @Test("a day the scorer declines to grade writes no row")
    func noComponentsNoRow() throws {
        let db = try store()
        let row = try db.writeDailyScore(
            userId: user, date: day, inputs: ScoringInputs(), hoursAwake: 12, isToday: true
        ) { _ in nil }
        // A zero would be a claim that the day was bad. An absent row is the
        // truth: nothing is known about it.
        #expect(row == nil)
        #expect(try db.dailyScore(userId: user, date: day) == nil)
    }

    @Test("the score row is queued for upload, once")
    func scoreIsQueued() throws {
        let db = try store()
        _ = try write(db, total: 40, isToday: true)
        _ = try write(db, total: 61, isToday: true)
        let queued = try db.pendingOutbox()
        #expect(queued.count == 1)
        #expect(try SyncEngine.rowRef(of: queued[0]).table == "daily_scores")
    }
}
