import Testing
import Foundation
import GRDB
import OnyxCore
import OnyxData
@testable import Onyx

/// The two claims Wave 2.11 makes that a screenshot cannot photograph.
///
/// ── WHY THESE AND NOT THE LAYOUT ────────────────────────────────────────────
/// The shot loop covers every pixel of Settings and History. What it cannot
/// cover is the arithmetic underneath them — a week cut on the wrong day looks
/// exactly like a week cut on the right one until you read the dates — and it
/// cannot cover a TRANSITION at all, because it launches one screen and
/// photographs it. So the week cut is asserted here, and so is the gate's own
/// sentence: changing a lever in Settings has to reach the Nutrition gauges
/// through GRDB observation, with no relaunch and nothing invalidated by hand.
@MainActor
@Suite("History weeks")
struct HistoryWeeksTests {

    private static let userId = "00000000-0000-0000-0000-000000000001"

    private func store() throws -> AppDatabase {
        try AppDatabase.inMemory(deviceId: "test")
    }

    // MARK: - The cut

    /// 2026-09-02 is a Wednesday. Sunday-start puts it in the week of the 30th
    /// of August; Monday-start puts it in the week of the 31st — and every
    /// number on every History screen hangs off which of those it is.
    @Test("Week starts on cuts the window")
    func weekStartCutsTheWindow() {
        let sunday = WeekWindow(containing: "2026-09-02", startDay: 0)
        #expect(sunday.start == "2026-08-30")
        #expect(sunday.end == "2026-09-05")

        let monday = WeekWindow(containing: "2026-09-02", startDay: 1)
        #expect(monday.start == "2026-08-31")
        #expect(monday.end == "2026-09-06")

        // Always seven, never "however many days had rows" — the padding bug
        // §2.2 caught in `dailySeries` is the same bug one level up.
        #expect(sunday.days.count == 7)
        #expect(monday.days.count == 7)
        #expect(sunday.days.first == "2026-08-30")
        #expect(sunday.days.last == "2026-09-05")

        #expect(sunday.contains("2026-08-30"))
        #expect(sunday.contains("2026-09-05"))
        #expect(!sunday.contains("2026-09-06"))
        #expect(!sunday.contains("2026-08-29"))
    }

    /// `week_end_day` is the column; the control asks for the START day. The
    /// inversion has exactly one home, and both readers go through it.
    @Test("The stored end day resolves to a start day")
    func endDayResolvesToStartDay() throws {
        let database = try store()
        try database.editUserGoals(userId: Self.userId) { $0.weekEndDay = 0 }   // ends Sunday
        var goals = try #require(try database.userGoals(userId: Self.userId))
        #expect(WeekWindow.startDay(from: goals) == 1)
        #expect(WeekWindow(containing: "2026-09-02", goals: goals).start == "2026-08-31")

        try database.editUserGoals(userId: Self.userId) { $0.weekEndDay = 6 }   // ends Saturday
        goals = try #require(try database.userGoals(userId: Self.userId))
        #expect(WeekWindow.startDay(from: goals) == 0)
        #expect(WeekWindow(containing: "2026-09-02", goals: goals).start == "2026-08-30")
    }

    @Test("Week 0 is the week the block opened on")
    func weekZero() {
        #expect(WeekWindow(containing: "2026-07-15", startDay: 0).number == 0)
        #expect(WeekWindow(containing: "2026-07-19", startDay: 0).number == 1)
    }

    /// One week either side of a month boundary prints one month name, not two.
    @Test("The range label folds a single month")
    func rangeLabel() {
        #expect(WeekWindow(containing: "2026-09-08", startDay: 0).rangeLabel.contains("–"))
        // 30 Aug – 5 Sep straddles, so BOTH months are named.
        let straddling = WeekWindow(containing: "2026-09-02", startDay: 0).rangeLabel
        #expect(straddling.contains("Aug"))
        #expect(straddling.contains("Sep"))
    }

    // MARK: - The capsules

    /// Two sessions in one week, one in the next, and the seven-cell strip
    /// shows what was PLANNED and not done — the fact the flat session list
    /// this screen replaced could not draw at all.
    @Test("A capsule counts its week and marks the days that were missed")
    func capsulesFoldByWeek() throws {
        let database = try store()
        try database.editUserGoals(userId: Self.userId) { $0.weekEndDay = 6 }  // Sunday start
        try seedSession(database, id: "s1", date: "2026-08-31", dayKey: "cb_a", sets: 3, weight: 40)
        try seedSession(database, id: "s2", date: "2026-09-01", dayKey: "legs_a", sets: 3, weight: 60)
        try seedSession(database, id: "s3", date: "2026-09-08", dayKey: "cb_a", sets: 3, weight: 42)

        let capsules = HistoryWeeks.capsules(database: database, today: "2026-09-10")

        // Newest first, and every week between the first record and today is
        // present — including a week nothing was logged in, which is the point.
        try #require(capsules.count == 2)
        #expect(capsules[0].window.start == "2026-09-06")
        #expect(capsules[1].window.start == "2026-08-30")

        let first = capsules[1]
        #expect(first.sessions == 2)
        #expect(first.sets == 6)
        #expect(first.tonnageKg == 3 * 40 * 10 + 3 * 60 * 10)
        #expect(first.cells.count == 7)
        #expect(first.cells.filter(\.isLogged).map(\.date) == ["2026-08-31", "2026-09-01"])
        // Onyx-5 trains five days, so a full week holds five planned days;
        // two were logged, so three are missed and none is in the future.
        #expect(first.cells.filter(\.isMissed).count == 3)
        #expect(first.cells.filter(\.isRest).count == 2)
        #expect(first.cells.allSatisfy { !$0.isFuture })
    }

    /// Week over week, from the last reading of each — not first-to-last within
    /// a week, which reports nothing for the many weeks holding one weigh-in.
    @Test("Weight delta is week over week and nil until there are two")
    func weightDelta() throws {
        let database = try store()
        try database.editUserGoals(userId: Self.userId) { $0.weekEndDay = 6 }
        try seedWeight(database, date: "2026-08-31", kg: 64.0)
        try seedWeight(database, date: "2026-09-07", kg: 63.4)

        let capsules = HistoryWeeks.capsules(database: database, today: "2026-09-09")
        try #require(capsules.count == 2)
        // Oldest week has nothing to compare against.
        #expect(capsules[1].weightDeltaKg == nil)
        let delta = try #require(capsules[0].weightDeltaKg)
        #expect(abs(delta - -0.6) < 0.0001)
    }

    /// Seven rows whatever happened, and the numbers on the 2×4 come from the
    /// week's own span.
    @Test("A week detail is seven days and its own vitals")
    func weekDetail() throws {
        let database = try store()
        try database.editUserGoals(userId: Self.userId) { $0.weekEndDay = 6 }
        try seedSession(database, id: "s1", date: "2026-08-31", dayKey: "cb_a", sets: 3, weight: 40)
        try seedWeight(database, date: "2026-08-30", kg: 64.0)
        try seedWeight(database, date: "2026-09-05", kg: 63.2)

        let window = WeekWindow(containing: "2026-09-02", startDay: 0)
        let detail = HistoryWeeks.detail(database: database, window: window, today: "2026-09-10")

        #expect(detail.days.count == 7)
        #expect(detail.days.first?.date == "2026-08-30")
        #expect(detail.days.filter(\.isLogged).count == 1)
        #expect(detail.vitals.sessions == 1)
        #expect(detail.vitals.tonnageKg == 1200)
        let delta = try #require(detail.vitals.weightDeltaKg)
        #expect(abs(delta - -0.8) < 0.0001)
        // No scores were written, so there is no mean — and a 0 in that cell
        // would read as a flat battery.
        #expect(detail.vitals.batteryMean == nil)
    }

    // MARK: - The gate

    /// **Wave 2.11 gate:** picking a rung in Settings has to reach every gauge
    /// in the app without a relaunch.
    ///
    /// The mechanism is one transaction and one `ValueObservation`: `pickLever`
    /// writes `user_goals.active_lever` and queues it in the same write, and
    /// `userGoalsStream` — which is what `NutritionModel` binds to — yields the
    /// new row. Asserted end to end, through the same model the radio row
    /// calls, and then run through `TargetSnapshot` (the resolver's value) so the claim is about the
    /// NUMBER on the gauge rather than about a column having changed.
    @Test("Picking a lever republishes the targets through GRDB")
    func leverChangeRepublishes() async throws {
        let database = try store()
        let model = SettingsModel(database: database, userId: Self.userId)
        try database.editUserGoals(userId: Self.userId) { row in
            row.calorieGoal = 1955
            row.proteinGoalG = 170
            row.activeLever = "custom"
        }
        // The rung is a row since W2.
        let user = Self.userId
        try database.seedRows { conn in
            try TargetProfileRow(userId: user, key: "lever-1", label: "Lever 1", sort: 11, kcal: 1885, proteinG: 170, carbsG: 182, fatG: 53, stepsGoal: 10000, updatedAt: Date(), kind: "deficit").insert(conn)
        }

        var iterator = database.userGoalsStream(userId: Self.userId).makeAsyncIterator()
        let before = try #require(try await iterator.next() ?? nil)
        #expect(before.activeLever == "custom")
        let ownKcal = TargetSnapshot(goals: before).targets(for: "2026-09-05", today: "2026-09-05").kcal
        #expect(ownKcal == 1955)

        model.pickLever("lever-1")

        // The observation fires because the row was committed, not because
        // anything here invalidated a cache.
        let after = try #require(try await iterator.next() ?? nil)
        #expect(after.activeLever == "lever-1")

        let snapshot = try database.targetSnapshot(userId: Self.userId)
        let held = try #require(Levers.lever(byId: "lever-1", in: snapshot.ladder))
        let republished = snapshot.targets(for: "2026-09-05", today: "2026-09-05")
        #expect(republished.kcal == held.calorieGoal)
        #expect(republished.kcal != ownKcal)

        // And it is queued, so the choice survives the phone as well as the
        // screen. A rung that only ever exists locally is a rung the web app
        // and the next device disagree with.
        let queued = try database.pendingOutbox(limit: 50)
        #expect(queued.contains { $0.idempotencyKey.contains("user_goals") || $0.kind.contains("user_goals") })
    }

    // MARK: - A day opened from a week

    /// The empty-boxes bug (Phase 3, F12): a day pushed from a week list built a
    /// `DayModel` and never asked it to observe, so every per-date stream sat at
    /// its initial value and `window.loaded` stayed false — the tiles drew "—"
    /// for a day that had rows. `DayScreen` now opens the streams itself, on
    /// every door in. This cannot see the view — it pins the MODEL half of the
    /// contract: one `observe()` on a past date lands the day's row and loads
    /// its window. The view half is the `day-past` shot in the loop.
    @Test("A day opened from a week has its row and a loaded window")
    func dayOpenedFromWeekLoads() async throws {
        let database = try store()
        try seedWeight(database, date: "2026-08-31", kg: 72.4)

        let model = DayModel(database: database, userId: Self.userId, date: "2026-08-31")
        #expect(model.log == nil)
        #expect(!model.window.loaded)

        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        let deadline = ContinuousClock.now + .seconds(5)
        while (model.log == nil || !model.window.loaded), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.date == "2026-08-31")
        #expect(model.log?.weightKg == 72.4)
        #expect(model.window.loaded)
    }

    // MARK: - The masthead

    /// `careerIndex` is a POSITION in the whole record, so no card can compute
    /// it from its own row — and a session that recorded nothing must not take
    /// a number, or every number after it is one too high for the rest of the
    /// user's training life.
    @Test("headers numbers the career and skips a shell")
    func headersNumberTheCareer() throws {
        let database = try store()
        try seedSession(database, id: "s1", date: "2026-09-01", dayKey: "cb_a", sets: 3, weight: 40)
        // Twelve hours of a Wednesday and not one set — the shell that exists
        // on record, and the reason the filter is `sets > 0`.
        try seedSession(database, id: "shell", date: "2026-09-02", dayKey: "cb_b", sets: 0, weight: 0)
        try seedSession(database, id: "s2", date: "2026-09-03", dayKey: "cb_a", sets: 3, weight: 42.5)
        try seedSession(database, id: "s3", date: "2026-09-05", dayKey: "cb_b", sets: 3, weight: 45)

        let headers = SessionAnalysis.headers(
            database: database, userId: Self.userId,
            sessionIds: ["s1", "s2", "s3", "shell"]
        )
        #expect(headers["s1"]?.careerIndex == 1)
        #expect(headers["s2"]?.careerIndex == 2)
        #expect(headers["s3"]?.careerIndex == 3)
        // The shell still gets a card — it just has no ordinal on it.
        #expect(headers["shell"] != nil)
        #expect(headers["shell"]?.careerIndex == nil)

        // The two facts `WorkoutWeek.State` cannot supply: when it happened,
        // and what it was for.
        let second = try #require(headers["s2"])
        #expect(second.stamp.contains("Sep"))
        #expect(!second.muscles.isEmpty)

        // Asking for one id costs the same walk and answers the same number —
        // the Train tab draws exactly one of these.
        let alone = SessionAnalysis.headers(database: database, userId: Self.userId, sessionIds: ["s3"])
        #expect(alone.count == 1)
        #expect(alone["s3"]?.careerIndex == 3)
    }

    // MARK: - Seeds

    private func seedSession(
        _ database: AppDatabase, id: String, date: String, dayKey: String, sets: Int, weight: Double
    ) throws {
        let userId = Self.userId
        try database.seedRows { db in
            if try Exercise.fetchOne(db, key: "ex-1") == nil {
                try Exercise(id: "ex-1", name: "Incline DB Press").insert(db)
            }
            let start = LogicalDay.date(fromISO: date)!.addingTimeInterval(17 * 3600)
            try WorkoutSession(
                id: id, userId: userId, dayKey: dayKey, date: date, startedAt: start,
                endedAt: start.addingTimeInterval(60 * 60), durationMin: 60
            ).insert(db)
            for index in 0..<sets {
                try WorkoutSet(
                    id: "\(id)-\(index)", sessionId: id, exerciseId: "ex-1", setIndex: index + 1,
                    weightKg: weight, reps: 10,
                    est1rmKg: OneRepMax.estimate(weight: weight, reps: 10), foldOrder: index
                ).insert(db)
            }
        }
    }

    private func seedWeight(_ database: AppDatabase, date: String, kg: Double) throws {
        let userId = Self.userId
        try database.seedRows { db in
            var log = DailyLogRow(
                id: newOnyxID(), userId: userId, date: date, createdAt: Date(), updatedAt: Date(),
                nutritionEstimated: false, sleepOnsetTrouble: false
            )
            log.weightKg = kg
            try log.insert(db)
        }
    }
}
