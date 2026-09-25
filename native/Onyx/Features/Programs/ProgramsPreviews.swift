#if DEBUG
import Foundation
import OnyxCore
import OnyxData

/// The Programs and goal-sheet harness fixtures (Precision E2/E3), read by
/// `PreviewHarness` under `// LANE-E`. Their own file so the shared harness
/// only gains its `case` lines.
enum ProgramsPreviews {

    /// LANE-E: the preview catalogue (Onyx-5 running, Onyx-4 benched, PPL
    /// past), its movements filed, a cut goal on Onyx-5 and yesterday's
    /// weigh-in. Built fresh per shot — the editor and the list each observe.
    @MainActor
    static func programsStore() -> AppDatabase {
        let database = try! AppDatabase.inMemory(deviceId: "shot-programs")
        PreviewCatalogue.seed(database)
        let user = PreviewCatalogue.userId
        for template in PlanTemplates.plans { try? PlanTemplates.fileMovements(template, into: database, userId: user) }
        _ = try? database.editUserGoals(userId: user) { row in
            row.activePlan = "onyx5"
            row.activePhase = ProgramPhase.cut.rawValue
            row.activeLever = "custom"
        }
        let yesterday = ISODate.addDays(LogicalDay.today(), -1) ?? LogicalDay.today()
        _ = try? database.editDailyLog(userId: user, date: yesterday) { row in
            row.weightKg = 80.4
            row.bodyFatPct = 18.2
            row.skeletalMuscleMassKg = 35.1
            row.bmr = 1742
        }
        try? database.applyProgramGoal(
            userId: user, programId: "onyx5", goal: .cut,
            target: ProgramGoalTarget(targetWeightKg: 76.5, horizonWeeks: 10, startWeightKg: 80.4),
            targets: StartingTargetsBuilder.build(weightKg: 80.4, programGoal: .cut), weightKg: 80.4
        )
        return database
    }

    @MainActor
    static func programsModel() -> ProgramsModel {
        ProgramsModel(database: programsStore(), userId: PreviewCatalogue.userId)
    }

    /// The goal sheet on step `step` (1–3), for the benched Onyx-4 — so step
    /// one is a fresh choice (body fat %, the kind with the most to show) and
    /// step three offers its recommended template.
    @MainActor
    static func goalModel(step: Int) -> GoalSetupModel {
        let database = programsStore()
        let plan = try? database.planCatalogue(userId: PreviewCatalogue.userId).plans.first { $0.id == "onyx4" }
        let model = GoalSetupModel(
            database: database, userId: PreviewCatalogue.userId, programId: "onyx4",
            programLabel: plan?.label ?? "Onyx-4", running: false, hasDays: true, current: plan
        )
        model.goal = .bodyFat
        model.step = GoalSetupModel.Step(rawValue: step - 1) ?? .goal
        return model
    }

}
#endif
