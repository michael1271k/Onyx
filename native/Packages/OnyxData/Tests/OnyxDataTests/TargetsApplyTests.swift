import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// Applying a pasted report's targets (W7, decision 23).
///
/// The parser's own vector lives in OnyxCore. This is what happens after: what
/// a block WOULD change against a real store, and what it actually writes.
@Suite("Apply targets — a paste is not a writer")
struct TargetsApplyTests {
    private let user = "00000000-0000-0000-0000-000000000001"
    private let today = "2026-09-22"

    private func store() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        try db.editUserGoals(userId: user) { row in
            row.calorieGoal = 2000; row.proteinGoalG = 160; row.carbsGoalG = 200; row.fatGoalG = 60
            row.stepsGoal = 10000; row.waterGoalMl = 3000; row.sleepGoalHours = 8
            row.activeLever = "custom"
        }
        try db.writer.write { conn in
            try TargetProfileRow(
                userId: user, key: "lever-1", label: "Lever 1", sort: 11,
                kcal: 1885, proteinG: 170, carbsG: 182, fatG: 53, stepsGoal: 10000,
                updatedAt: Date(), kind: "deficit").insert(conn)
        }
        return db
    }

    @Test("the plan is a diff, and only of what moved")
    func planIsADiff() throws {
        let db = try store()
        let block = TargetsBlock(
            weekStart: today,
            dailyTargets: .init(kcal: 2100, proteinG: 160, stepsGoal: 12000))
        let plan = try db.targetsPlan(for: block, userId: user, today: today)
        // Protein is unchanged at 160 and does not appear.
        #expect(plan.changes.map(\.field) == ["Calories", "Steps"])
        #expect(plan.changes[0].current == "2,000 kcal")
        #expect(plan.changes[0].proposed == "2,100 kcal")
        #expect(plan.changes[1].current == "10,000")
        #expect(plan.changes[1].proposed == "12,000")
        #expect(!plan.isEmpty)
        #expect(!plan.wasBackdated)
    }

    @Test("applying writes user_goals, the plan-phase override, and a lever period")
    func applyWritesAllThree() throws {
        let db = try store()
        let block = TargetsBlock(
            weekStart: today,
            dailyTargets: .init(kcal: 2100, proteinG: 175, waterMl: 3500, sleepHours: 8.5))
        let plan = try db.targetsPlan(for: block, userId: user, today: today)
        try db.applyTargets(plan, userId: user, now: Date())

        let goals = try #require(try db.userGoals(userId: user))
        #expect(goals.calorieGoal == 2100)
        #expect(goals.proteinGoalG == 175)
        // Untouched fields keep their value — a block is a patch, not a save.
        #expect(goals.carbsGoalG == 200)
        #expect(goals.fatGoalG == 60)
        #expect(goals.waterGoalMl == 3500)
        #expect(goals.sleepGoalHours == 8.5)
        // Typing a number IS choosing your own numbers.
        #expect(goals.activeLever == "custom")

        // And the stretch is on the schedule, so this week grades against it
        // and last week does not.
        let periods = try db.writer.read { conn in
            try LeverPeriodRow.filter(Column("user_id") == user).order(Column("starts_on")).fetchAll(conn)
        }
        #expect(periods.map(\.startsOn) == [today])
        #expect(periods[0].profileKey == nil)
    }

    @Test("a rung is selected by key, and an unknown key is reported and refused")
    func levers() throws {
        let db = try store()
        let known = try db.targetsPlan(
            for: TargetsBlock(weekStart: today, levers: [.init(key: "lever-1")]),
            userId: user, today: today)
        #expect(known.leverKey == "lever-1")
        #expect(known.changes.map(\.field) == ["Lever"])
        #expect(known.changes[0].proposed == "Lever 1")
        #expect(known.changes[0].applies)

        try db.applyTargets(known, userId: user, now: Date())
        #expect(try db.userGoals(userId: user)?.activeLever == "lever-1")

        let unknown = try db.targetsPlan(
            for: TargetsBlock(weekStart: today, levers: [.init(key: "lever-9")]),
            userId: user, today: today)
        #expect(unknown.leverKey == nil)
        #expect(unknown.isEmpty)
        #expect(unknown.changes[0].applies == false)
        #expect(unknown.changes[0].reason?.contains("cannot create one") == true)
        // An empty plan writes nothing at all.
        try db.applyTargets(unknown, userId: user, now: Date())
        #expect(try db.userGoals(userId: user)?.activeLever == "lever-1")
    }

    /// The app's own rule, applied to a paste: a typed figure beats a rung,
    /// because a figure a rung overrode would be an instruction that did
    /// nothing. The rung is still SHOWN, with the reason.
    @Test("a typed number supersedes a rung in the same block")
    func numbersBeatRungs() throws {
        let db = try store()
        let plan = try db.targetsPlan(
            for: TargetsBlock(
                weekStart: today,
                levers: [.init(key: "lever-1")],
                dailyTargets: .init(kcal: 2100)),
            userId: user, today: today)
        #expect(plan.leverKey == nil)
        let lever = try #require(plan.changes.first { $0.field == "Lever" })
        #expect(!lever.applies)
        #expect(lever.reason?.contains("replace it") == true)

        try db.applyTargets(plan, userId: user, now: Date())
        let goals = try #require(try db.userGoals(userId: user))
        #expect(goals.calorieGoal == 2100)
        #expect(goals.activeLever == "custom")
    }

    /// The claim that keeps a paste honest: a report written about last week
    /// must not re-grade last week.
    @Test("a back-dated block applies from today, and says so")
    func backdated() throws {
        let db = try store()
        let plan = try db.targetsPlan(
            for: TargetsBlock(weekStart: "2026-09-07", dailyTargets: .init(kcal: 2100)),
            userId: user, today: today)
        #expect(plan.weekStart == "2026-09-07")
        #expect(plan.effectiveFrom == today)
        #expect(plan.wasBackdated)

        try db.applyTargets(plan, userId: user, now: Date())
        let periods = try db.writer.read { conn in
            try LeverPeriodRow.filter(Column("user_id") == user).fetchAll(conn)
        }
        #expect(periods.map(\.startsOn) == [today])
    }

    /// A FUTURE week start is not honoured either, and that is the correction
    /// `invariant-auditor` forced. A period dated ahead makes
    /// `recordLeverChange` pin the still-open keyless stretch with today's live
    /// numbers, so every edit between now and that date stops counting for the
    /// days in between. One answer to "when does a rung start", and it is the
    /// one the Settings picker already gives.
    @Test("a future block applies today too, and the sheet still names the date asked for")
    func future() throws {
        let db = try store()
        let plan = try db.targetsPlan(
            for: TargetsBlock(weekStart: "2026-09-27", levers: [.init(key: "lever-1")]),
            userId: user, today: today)
        #expect(plan.weekStart == "2026-09-27")
        #expect(plan.effectiveFrom == today)
        #expect(plan.wasBackdated)
        try db.applyTargets(plan, userId: user, now: Date())
        let periods = try db.writer.read { conn in
            try LeverPeriodRow.filter(Column("user_id") == user).fetchAll(conn)
        }
        #expect(periods.map(\.startsOn) == [today])
    }

    /// The sheet rounds and the write used to truncate, so the number approved
    /// and the number stored were different. They are one conversion now.
    @Test("the number written is the number the sheet showed")
    func roundingAgrees() throws {
        let db = try store()
        let plan = try db.targetsPlan(
            for: TargetsBlock(weekStart: today, dailyTargets: .init(kcal: 2100.6, proteinG: 174.4)),
            userId: user, today: today)
        #expect(plan.changes.first { $0.field == "Calories" }?.proposed == "2,101 kcal")
        #expect(plan.changes.first { $0.field == "Protein" }?.proposed == "174 g")
        try db.applyTargets(plan, userId: user, now: Date())
        let goals = try #require(try db.userGoals(userId: user))
        #expect(goals.calorieGoal == 2101)
        #expect(goals.proteinGoalG == 174)
    }

    /// And a value that rounds to what is already there produces no diff line
    /// AND no drift — the case that used to write one less than the row held
    /// while showing nothing at all.
    @Test("a value that rounds to the current figure changes neither the sheet nor the row")
    func noSilentDrift() throws {
        let db = try store()
        let plan = try db.targetsPlan(
            for: TargetsBlock(weekStart: today, dailyTargets: .init(kcal: 1999.6, proteinG: 175)),
            userId: user, today: today)
        #expect(plan.changes.map(\.field) == ["Protein"])
        try db.applyTargets(plan, userId: user, now: Date())
        let goals = try #require(try db.userGoals(userId: user))
        #expect(goals.calorieGoal == 2000)
        #expect(goals.proteinGoalG == 175)
    }

    @Test("a block that asks for nothing changes nothing")
    func emptyBlock() throws {
        let db = try store()
        let plan = try db.targetsPlan(for: TargetsBlock(weekStart: today), userId: user, today: today)
        #expect(plan.changes.isEmpty)
        #expect(plan.isEmpty)
        try db.applyTargets(plan, userId: user, now: Date())
        #expect(try db.userGoals(userId: user)?.calorieGoal == 2000)
        let periods = try db.writer.read { conn in
            try LeverPeriodRow.filter(Column("user_id") == user).fetchCount(conn)
        }
        #expect(periods == 0)
    }

    /// Every write goes through a writer that queues. A goal edit that never
    /// leaves the phone is the failure the outbox exists to make impossible,
    /// and a paste must not be the one path that forgets.
    @Test("everything applied is queued for the server")
    func everythingIsQueued() throws {
        let db = try store()
        try db.writer.write { conn in try conn.execute(sql: "DELETE FROM outbox") }
        let plan = try db.targetsPlan(
            for: TargetsBlock(weekStart: today, dailyTargets: .init(kcal: 2100)),
            userId: user, today: today)
        try db.applyTargets(plan, userId: user, now: Date())
        // `enqueueRowUpsert` keys an item `row:<table>:<id>`.
        let keys = try db.writer.read { conn in
            try String.fetchAll(conn, sql: "SELECT idempotency_key FROM outbox ORDER BY idempotency_key")
        }
        #expect(keys.contains { $0.hasPrefix("row:user_goals:") })
        #expect(keys.contains { $0.hasPrefix("row:lever_periods:") })
    }
}
