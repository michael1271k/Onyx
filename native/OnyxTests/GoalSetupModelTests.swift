import Foundation
import Testing
import GRDB
import OnyxCore
import OnyxData
@testable import Onyx

/// Precision E3's sheet, walked through its model: the weigh-in prefills, a
/// goal change re-derives what the user has not touched, and Save lands the
/// targets where `Targets.resolve` reads them.
@MainActor
@Suite("Precision E3 · the goal sheet")
struct GoalSetupModelTests {

    static let user = "00000000-0000-0000-0000-0000000000ef"

    private func store(weighIn: Bool = true) throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "goal-sheet")
        try db.seedAccount(AccountSeed(
            userId: Self.user, goal: .cut, targets: StartingTargetsBuilder.build(weightKg: 80, goal: .cut),
            volume: [:], weightKg: 80, weekEndDay: 6,
            plan: SeedPlan(programId: "mine", label: "Mine", days: []), exercises: [], startedOn: "2026-09-01"
        ))
        if weighIn {
            _ = try db.editDailyLog(userId: Self.user, date: "2026-09-24") { row in
                row.weightKg = 82.34
                row.bodyFatPct = 20
                row.skeletalMuscleMassKg = 36
                row.bmr = 1800
            }
        }
        return db
    }

    private func model(_ db: AppDatabase, running: Bool = true, today: String = "2026-09-25") throws -> GoalSetupModel {
        let plan = try db.planCatalogue(userId: Self.user).plans.first { $0.id == "mine" }
        return GoalSetupModel(
            database: db, userId: Self.user, programId: "mine", programLabel: "Mine",
            running: running, hasDays: false, current: plan, today: today
        )
    }

    @Test("the latest weigh-in prefills step two, today included, rounded to 0.1")
    func prefillsFromTheWeighIn() throws {
        let m = try model(try store(), today: "2026-09-24")
        #expect(m.weightKg == 82.3)
        #expect(m.bodyFatPct == 20)
        #expect(m.muscleMassKg == 36)
        #expect(m.bmr == 1800)
        #expect(m.readingDate == "2026-09-24")
    }

    @Test("no weigh-in: no weight, and step two cannot continue until one is typed")
    func noWeighInBlocksStepTwo() throws {
        let m = try model(try store(weighIn: false))
        #expect(m.weightKg == nil)
        m.step = .now
        #expect(!m.canAdvance)
        m.weightKg = 79
        #expect(m.canAdvance)
    }

    /// The first thing step two shows must not be a warning the app itself
    /// produced: the proposed target lands mid-band for every kind.
    @Test("the proposed target is inside the safe band for every goal")
    func proposalIsInsideTheBand() throws {
        let m = try model(try store())
        for goal in ProgramGoal.allCases {
            m.goal = goal
            let pace = try #require(m.pace, "\(goal) proposed nothing")
            #expect(pace.verdict == .inside, "\(goal): \(pace.weeklyRateKg) outside \(pace.bandMin)…\(pace.bandMax)")
        }
    }

    @Test("changing the goal re-derives the macros and the target until they are touched")
    func goalChangeRederives() throws {
        let m = try model(try store())
        m.goal = .bulk
        #expect(m.kcal == Double(StartingTargetsBuilder.build(weightKg: 82.3, programGoal: .bulk).kcal))
        #expect(m.targetWeightKg != nil)
        m.markTargetsTouched()
        m.proteinG = 250
        m.goal = .recomp
        #expect(m.proteinG == 250, "a touched macro is the user's")
    }

    /// The brief's gate from the app side: Save on the running program writes
    /// the phase row, runs the phase switch, and the resolver reads the numbers.
    @Test("saving on the running program puts the targets in force")
    func saveApplies() throws {
        let db = try store()
        let m = try model(db)
        m.goal = .bodyFat
        m.targetBodyFatPct = 15
        m.horizonWeeks = 12
        let expected = m.targets
        #expect(m.save(today: "2026-09-25"))

        let info = try #require(try db.planCatalogue(userId: Self.user).plans.first { $0.id == "mine" })
        #expect(info.goal == .bodyFat)
        #expect(info.goalTarget?.targetBodyFatPct == 15)
        #expect(info.goalTarget?.startWeightKg == 82.3)
        #expect(info.goalTarget?.weeklyRateKg == m.pace?.weeklyRateKg)
        let resolved = try db.targetSnapshot(userId: Self.user).targets(for: "2026-09-25", today: "2026-09-25")
        #expect(resolved.kcal == Double(expected.kcal))
        #expect(resolved.protein == Double(expected.proteinG))
        #expect(try db.userGoals(userId: Self.user)?.activeLever == "custom")
    }

    @Test("an empty program accepts the recommended template's days")
    func acceptsTheTemplate() throws {
        let db = try store()
        let m = try model(db, running: false)
        m.goal = .cut
        m.acceptTemplate = true
        #expect(m.save())
        let days = try db.routineDays(userId: Self.user, programId: "mine")
        #expect(days.count == (PlanTemplates.plans.first { $0.id == "onyx4" }?.days.count ?? -1))
        #expect(days.count > 0)
    }

    @Test("the goal row's words")
    func summary() {
        let plan = PlanInfo(
            id: "p", label: "P", blurb: "", goalKind: "cut",
            goalTarget: ProgramGoalTarget(targetWeightKg: 74.5, horizonWeeks: 12)
        )
        #expect(GoalSetupModel.summary(plan) == "Cut · 74.5 kg in 12 wk")
        #expect(GoalSetupModel.summary(PlanInfo(id: "p", label: "P", blurb: "")) == "Set a goal")
    }
}
