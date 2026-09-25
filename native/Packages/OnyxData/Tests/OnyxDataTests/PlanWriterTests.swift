import Foundation
import Testing
import GRDB
import OnyxCore
@testable import OnyxData

// Precision E2/E3: a program written on the phone — created, renamed,
// activated, deleted, copied from a template, and given a goal whose targets
// the resolver then reads. Every write queues.

private let user = "00000000-0000-0000-0000-0000000000ee"

private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "plan-writer") }

private func queued(_ db: AppDatabase) throws -> [(kind: String, table: String)] {
    try db.pendingOutbox(limit: 500).compactMap { item in
        if item.kind == SyncKind.rowUpsert, let ref = try? OnyxJSON.decoder.decode(RowRef.self, from: item.payload) {
            return (item.kind, ref.table)
        }
        if item.kind == SyncKind.rowDelete, let ref = try? OnyxJSON.decoder.decode(RowDeleteRef.self, from: item.payload) {
            return (item.kind, ref.table)
        }
        return nil
    }
}

private func days(_ programId: String) -> [RoutineDay] {
    [
        RoutineDay(
            programId: programId, dayKey: "push", label: "Push", weekday: 1, accent: 0xE0703C, sort: 0,
            payload: RoutinePayload(exercises: [RoutineExercise(name: "Pec Deck", sets: 3, reps: "10–12")])
        ),
        RoutineDay(
            programId: programId, dayKey: "pull", label: "Pull", weekday: 3, accent: 0x3D7AB8, sort: 1,
            payload: RoutinePayload(exercises: [RoutineExercise(name: "Lat Pulldown", sets: 3, reps: "8–12")])
        ),
    ]
}

/// The founder's shape: a running Onyx-5 and a benched Onyx-4.
private func seeded() throws -> AppDatabase {
    let db = try store()
    try db.seedAccount(AccountSeed(
        userId: user, goal: .cut, targets: StartingTargetsBuilder.build(weightKg: 80, goal: .cut),
        volume: [:], weightKg: 80, weekEndDay: 6,
        plan: SeedPlan(programId: "onyx5", label: "Onyx-5", days: days("onyx5")),
        exercises: [ExerciseDraft(name: "Pec Deck"), ExerciseDraft(name: "Lat Pulldown")],
        startedOn: "2026-07-15"
    ))
    return db
}

@Suite("Precision E2 · creating a program")
struct PlanCreateTests {

    @Test("a new program is a plans row plus its days, not active, sorted last")
    func createsInactiveAndLast() throws {
        let db = try seeded()
        let id = try db.createPlan(userId: user, name: "Upper / Lower", days: days("ignored"))
        #expect(id == "upper-lower")
        let catalogue = try db.planCatalogue(userId: user)
        let info = try #require(catalogue.plans.first { $0.id == id })
        #expect(info.label == "Upper / Lower")
        #expect(info.startedOn == nil, "dated only on first activation")
        #expect(info.sort > (catalogue.plans.first { $0.id == "onyx5" }?.sort ?? 0))
        #expect(catalogue.activePlanId == "onyx5", "creating never switches the running plan")
        let program = try #require(catalogue.programs.first { $0.id == id })
        #expect(program.days.map(\.key) == ["push", "pull"])
        // Resolved against the catalogue, exactly as the builder resolves.
        #expect(program.days[0].exercises[0].exerciseId?.isEmpty == false)
        let tables = Set(try queued(db).map(\.table))
        #expect(tables.isSuperset(of: ["plans", "routines"]))
    }

    /// The template copy: the account already runs `onyx5`, so the copy gets a
    /// program id of its own and the original's days are untouched.
    @Test("starting from a template the account already runs mints a new id")
    func templateCopyNeverAdoptsTheOriginal() throws {
        let db = try seeded()
        let id = try db.createPlan(userId: user, name: "Onyx-5", days: days("onyx5"))
        #expect(id != "onyx5")
        let catalogue = try db.planCatalogue(userId: user)
        #expect(catalogue.programs.first { $0.id == id }?.days.count == 2)
        #expect(catalogue.programs.first { $0.id == "onyx5" }?.days.count == 2)
        #expect(Set(catalogue.plans.map(\.id)).count == catalogue.plans.count)
    }

    /// `apex51` is an alias `Programs.normalizePlanId` rewrites to `onyx5`; a
    /// program minted under it would be read as someone else's plan.
    @Test("a minted id is never a legacy alias")
    func neverMintsAnAlias() throws {
        let db = try seeded()
        let id = try db.createPlan(userId: user, name: "apex51")
        #expect(Programs.normalizePlanId(id) == id)
    }

    @Test("a program can be created with a goal on it")
    func createsWithAGoal() throws {
        let db = try store()
        let id = try db.createPlan(
            userId: user, name: "Summer cut", goal: .cut,
            goalTarget: ProgramGoalTarget(targetWeightKg: 74, horizonWeeks: 12)
        )
        let info = try #require(try db.planCatalogue(userId: user).plans.first { $0.id == id })
        #expect(info.goal == .cut)
        #expect(info.goalTarget?.targetWeightKg == 74)
    }

    @Test("renaming changes the label, never the id, and queues")
    func rename() throws {
        let db = try seeded()
        try db.renamePlan(userId: user, programId: "onyx5", name: "Onyx Five")
        let catalogue = try db.planCatalogue(userId: user)
        #expect(catalogue.plans.first { $0.id == "onyx5" }?.label == "Onyx Five")
        #expect(try queued(db).contains { $0.table == "plans" })
    }
}

@Suite("Precision E2 · activating and deleting")
struct PlanActivateDeleteTests {

    /// The brief's gate: create → activate → the schedule resolves the new days.
    @Test("create, activate, and the schedule deals the new program's days")
    func activateResolvesTheNewDays() throws {
        let db = try seeded()
        let id = try db.createPlan(userId: user, name: "Push Pull", days: days("x"))
        try db.activateProgram(userId: user, programId: id, phase: .bulk, startedOn: "2026-09-25")
        let ctx = try db.scheduleContext(userId: user)
        #expect(ctx.programId == id)
        #expect(ctx.phase == .bulk)
        #expect(ctx.activeProgram.days.map(\.key) == ["push", "pull"])
        #expect(ctx.planStartISO == "2026-09-25")
        // 2026-09-28 is a Monday — the Push day's weekday.
        #expect(Schedule.scheduleDayIn(ctx, "2026-09-28")?.dayKey == "push")
        let catalogue = try db.planCatalogue(userId: user)
        #expect(catalogue.activePlanId == id)
        #expect(catalogue.plans.first { $0.id == "onyx5" }?.startedOn == "2026-07-15", "the old era keeps its date")
    }

    @Test("deleting the running program is refused")
    func refusesTheActivePlan() throws {
        let db = try seeded()
        #expect(throws: PlanWriteError.activePlan) {
            try db.deletePlan(userId: user, programId: "onyx5")
        }
        #expect(try db.planCatalogue(userId: user).plans.contains { $0.id == "onyx5" })
    }

    /// A program that ran owns dated weeks — `Schedule.planId(owning:)` reads
    /// its `started_on` — and deleting it would relabel its history.
    @Test("deleting a program that has run is refused")
    func refusesAPlanWithHistory() throws {
        let db = try seeded()
        let id = try db.createPlan(userId: user, name: "Old", days: days("x"))
        try db.activateProgram(userId: user, programId: id, phase: .cut, startedOn: "2026-09-20")
        try db.activateProgram(userId: user, programId: "onyx5", phase: .cut, startedOn: "2026-09-25")
        #expect(throws: PlanWriteError.hasRun(since: "2026-09-20")) {
            try db.deletePlan(userId: user, programId: id)
        }
    }

    @Test("a benched, never-run program deletes with everything it owns, and queues it")
    func deletesAnUnusedPlan() throws {
        let db = try seeded()
        let id = try db.createPlan(userId: user, name: "Spare", days: days("x"))
        try db.applyProgramGoal(
            userId: user, programId: id, goal: .cut, target: ProgramGoalTarget(targetWeightKg: 75, horizonWeeks: 10),
            targets: StartingTargetsBuilder.build(weightKg: 80, programGoal: .cut), weightKg: 80
        )
        try db.deletePlan(userId: user, programId: id)
        let catalogue = try db.planCatalogue(userId: user)
        #expect(!catalogue.plans.contains { $0.id == id })
        #expect(!catalogue.programs.contains { $0.id == id })
        #expect(try db.phaseGoals(userId: user, planId: id, phase: .cut) == nil)
        let deletes = Set(try queued(db).filter { $0.kind == SyncKind.rowDelete }.map(\.table))
        #expect(deletes.isSuperset(of: ["plans", "routines", "plan_phase_goals"]))
    }
}

@Suite("Precision E3 · a program's goal")
struct PlanGoalTests {

    @Test("the goal, its target and the phase's targets land in one write")
    func writesGoalAndPhaseTargets() throws {
        let db = try seeded()
        let targets = StartingTargetsBuilder.build(weightKg: 80, programGoal: .bulk)
        try db.applyProgramGoal(
            userId: user, programId: "onyx5", goal: .bulk,
            target: ProgramGoalTarget(targetWeightKg: 83, horizonWeeks: 12, startWeightKg: 80),
            targets: targets, weightKg: 80
        )
        let info = try #require(try db.planCatalogue(userId: user).plans.first { $0.id == "onyx5" })
        #expect(info.goal == .bulk)
        #expect(info.goalTarget?.targetWeightKg == 83)
        let bulk = try #require(try db.phaseGoals(userId: user, planId: "onyx5", phase: .bulk))
        #expect(bulk.calorieGoal == Double(targets.kcal))
        #expect(bulk.proteinGoalG == Double(targets.proteinG))
        #expect(bulk.targetWeightKg == 83)
        #expect(bulk.rateMinKgWk == 0.16)
        #expect(bulk.rateMaxKgWk == 0.32)
    }

    /// The founder's tuned cut row (1935 / 190) must survive a bulk goal.
    @Test("the other phase's existing row is left alone")
    func keepsTheOtherPhasesRow() throws {
        let db = try seeded()
        _ = try db.editPlanPhaseGoals(userId: user, planId: "onyx5", phase: "cut") { row in
            row.kcal = 1935
            row.proteinG = 190
        }
        try db.applyProgramGoal(
            userId: user, programId: "onyx5", goal: .bulk,
            target: ProgramGoalTarget(targetWeightKg: 83, horizonWeeks: 12),
            targets: StartingTargetsBuilder.build(weightKg: 80, programGoal: .bulk), weightKg: 80
        )
        let cut = try #require(try db.phaseGoals(userId: user, planId: "onyx5", phase: .cut))
        #expect(cut.calorieGoal == 1935)
        #expect(cut.proteinGoalG == 190)
    }

    /// A plan with no row for the other phase gets its own arithmetic, so a
    /// later phase switch never lands on zeros.
    @Test("an absent other phase is filled with its own arithmetic")
    func fillsAnAbsentOtherPhase() throws {
        let db = try store()
        let id = try db.createPlan(userId: user, name: "Fresh")
        try db.applyProgramGoal(
            userId: user, programId: id, goal: .recomp,
            target: ProgramGoalTarget(targetWeightKg: 80, horizonWeeks: 12),
            targets: StartingTargetsBuilder.build(weightKg: 80, programGoal: .recomp), weightKg: 80
        )
        let cut = try #require(try db.phaseGoals(userId: user, planId: id, phase: .cut))
        #expect(cut.calorieGoal == 2_640, "recomp trains in the cut's rows at maintenance energy")
        #expect(cut.rateMinKgWk == -0.08 && cut.rateMaxKgWk == 0.08)
        let bulk = try #require(try db.phaseGoals(userId: user, planId: id, phase: .bulk))
        #expect(bulk.calorieGoal == Double(StartingTargetsBuilder.build(weightKg: 80, goal: .bulk).kcal))
    }

    /// The brief's gate: the targets are what `Targets.resolve` reads once the
    /// program runs. The user's own numbers win (`custom`), the phase is the
    /// goal's.
    @Test("activating a program with a goal puts its targets in force")
    func resolveSeesTheTargets() throws {
        let db = try seeded()
        let id = try db.createPlan(userId: user, name: "Lean bulk", days: days("x"))
        let targets = StartingTargetsBuilder.build(weightKg: 80, programGoal: .muscleMass)
        try db.applyProgramGoal(
            userId: user, programId: id, goal: .muscleMass,
            target: ProgramGoalTarget(targetMuscleMassKg: 36, horizonWeeks: 10),
            targets: targets, weightKg: 80
        )
        try db.activateProgram(userId: user, programId: id, phase: ProgramGoal.muscleMass.phase, startedOn: "2026-09-25")
        let resolved = try db.targetSnapshot(userId: user).targets(for: "2026-09-25", today: "2026-09-25")
        #expect(resolved.kcal == Double(targets.kcal))
        #expect(resolved.protein == Double(targets.proteinG))
        #expect(resolved.carbs == Double(targets.carbsG))
        #expect(resolved.fat == Double(targets.fatG))
        let goals = try #require(try db.userGoals(userId: user))
        #expect(goals.activePlan == id)
        #expect(goals.activePhase == "bulk")
    }
}
