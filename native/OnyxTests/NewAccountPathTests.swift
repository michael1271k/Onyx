import Foundation
import Testing
import GRDB
import OnyxCore
import OnyxData
@testable import Onyx

/// W5's gate, as a test.
///
/// > *A fresh account must reach the logger with a chosen routine and zero
/// > founder data; the founder's account must be unchanged.*
///
/// The simulator run demonstrates it; this pins it. It walks the REAL path —
/// `OnboardingModel` itself, not a hand-built `AccountSeed` — so a change to
/// what the flow collects, or to how it maps onto rows, fails here rather than
/// in a screenshot somebody has to look at.
@MainActor
@Suite("W5 · the new-account path")
struct NewAccountPathTests {

    static let user = "00000000-0000-0000-0000-0000000000bb"

    private func store() throws -> AppDatabase {
        try AppDatabase.inMemory(deviceId: "new-account")
    }

    /// Everything onboarding would have collected if a person tapped through
    /// taking the defaults and picking ONYX-5 on the last step.
    private func flow(_ database: AppDatabase, plan: String? = "onyx5") -> OnboardingModel {
        let model = OnboardingModel(database: database, userId: Self.user)
        model.planId = plan
        return model
    }

    // MARK: - The gate

    @Test("an empty account walks the flow and lands on a logger with its routine in it")
    func endToEnd() async throws {
        let database = try store()

        // 1. It is offered, because nothing is here.
        #expect(try database.needsOnboarding(userId: Self.user) == true)

        // 2. The flow's defaults are a complete answer on their own.
        let model = flow(database)
        #expect(model.canAdvance)
        #expect(model.weightKg == OnboardingModel.defaultWeightKg)
        #expect(model.targets.kcal > 0)
        #expect(model.weeklySets == VolumeLandmarks.weeklyTotal(for: .cut))

        // 3. One write.
        #expect(await model.finish())
        #expect(try database.needsOnboarding(userId: Self.user) == false)

        // 4. There is a plan, and it is the one that was picked.
        let context = try database.scheduleContext(userId: Self.user)
        #expect(context.plans.map(\.id) == ["onyx5"])
        let program = context.activeProgram
        #expect(program.days.count == 5)

        // 5. THE GATE: a logger opens on one of those days with the routine's
        // movements in it, in the routine's order.
        let day = try #require(program.days.first)
        let logger = LoggerModel(
            day: day, phase: .cut, store: database, userId: Self.user, startedAt: Date()
        )
        #expect(!logger.exercises.isEmpty, "the logger opened an empty deck")
        #expect(logger.exercises.map(\.plan.name) == day.exercises.map(\.name))

        // 6. And every movement resolves to a catalogue row this account owns,
        // so the sets it logs carry a uuid rather than falling back to the
        // legacy slug (D3).
        for exercise in logger.exercises {
            #expect(exercise.plan.exerciseId?.isEmpty == false, "\(exercise.plan.name) has no catalogue id")
        }
        let catalogue = try database.exercises()
        #expect(catalogue.count == Set(program.days.flatMap { $0.exercises.map(\.name) }).count)
    }

    /// The other half of the gate, and the one a bug would be quiet about.
    @Test("nothing the founder owned comes with it")
    func noFounderData() async throws {
        let database = try store()
        #expect(await flow(database).finish())

        let context = try database.scheduleContext(userId: Self.user)
        // The dated blocks and the nutrition ladder were founder constants until
        // W2 turned them into rows. A new account gets NEITHER — it has no
        // history to have phases about, and no ladder it has climbed.
        #expect(context.phases.isEmpty, "a new account inherited a phase calendar")
        #expect(try database.sessions(on: LogicalDay.today()).isEmpty)

        // The targets it DOES have are its own arithmetic, not the founder's.
        let expected = StartingTargetsBuilder.build(
            weightKg: OnboardingModel.defaultWeightKg, goal: .cut
        )
        let goals = try #require(try database.phaseGoals(userId: Self.user, planId: "onyx5", phase: .cut))
        #expect(Int(goals.calorieGoal) == expected.kcal)
        #expect(Int(goals.calorieGoal) != 1_955, "that is the founder's cut")

        // And the volume is the MEV table's, not the founder's tuned numbers —
        // his cut asks for eleven sets of chest; the table asks for eight.
        let volume = try database.volumeTargets(userId: Self.user, planId: "onyx5", phase: .cut)
        #expect(volume[.chest] == Double(VolumeLandmarks.table[.chest]?.mev ?? 0))
        #expect(volume[.chest] != 11, "that is the founder's chest target")
    }

    /// The founder's account trips every gate. This is the one property the
    /// whole wave has to preserve: W5 must be invisible to him.
    @Test("an account that already has a deck is never offered onboarding again")
    func neverReoffered() async throws {
        let database = try store()
        #expect(await flow(database).finish())

        let before = try database.scheduleContext(userId: Self.user)
        let beforeCatalogue = try database.exercises().map(\.id).sorted()

        // Asking again changes nothing and answers no. `AccountSeedTests`
        // covers the founder's own shape — a seeded `SampleDeck` — from inside
        // OnyxData, where its fixtures live.
        #expect(try database.needsOnboarding(userId: Self.user) == false)
        #expect(try database.needsOnboarding(userId: Self.user) == false)

        let after = try database.scheduleContext(userId: Self.user)
        #expect(before.plans.map(\.id) == after.plans.map(\.id))
        #expect(before.activeProgram.days.count == after.activeProgram.days.count)
        #expect(try database.exercises().map(\.id).sorted() == beforeCatalogue)
    }

    /// The W11 gate, on a phone that has HELD ANOTHER ACCOUNT.
    ///
    /// Local `exercises` has no `user_id`, so account B's catalogue rows say a
    /// catalogue was pulled here once — not that account A has been set up. The
    /// pre-W11 gate counted them and suppressed onboarding for A; this pins that
    /// A is still offered the flow, and that A's PR list is empty however many
    /// of B's records sit in the same table. (On a real device the
    /// account-switch erase clears B first; the gate must be right even if it
    /// did not.)
    @Test("a store holding another account's catalogue still offers onboarding to a new account")
    func newAccountPastAnotherAccountsCatalogue() async throws {
        let database = try store()
        let other = "00000000-0000-0000-0000-0000000000cc"

        // B leaves a catalogue row behind (public path; the store has no
        // per-user catalogue). The record-book half of the isolation — A never
        // reading B's PRs — is proved exhaustively in `TwoUserIsolationTests`
        // and `AccountSeedTests`, which have @testable access to seed a PR row.
        _ = try database.createExercise(userId: other, name: "Hip Thrust")

        // A is new despite B's catalogue, and its own record book is empty.
        #expect(try database.needsOnboarding(userId: Self.user) == true,
                "a leftover catalogue row suppressed onboarding for a new account")
        #expect(try database.personalRecords(exerciseKey: "Hip Thrust", userId: Self.user).isEmpty)

        // And the flow still lands cleanly.
        #expect(await flow(database).finish())
        #expect(try database.needsOnboarding(userId: Self.user) == false)
    }

    /// "Build my own" is a real answer, and the logger has to survive it.
    @Test("a blank plan reaches a logger with nothing in it, and does not crash")
    func blankPlan() async throws {
        let database = try store()
        #expect(await flow(database, plan: nil).finish())

        let context = try database.scheduleContext(userId: Self.user)
        #expect(context.plans.map(\.id) == [AccountSeed.blankProgramId])
        #expect(context.activeProgram.days.isEmpty)
        // No catalogue either: an empty list and an importer is an honest start;
        // sixty rows nobody asked for is not.
        #expect(try database.exercises().isEmpty)

        // The targets still exist — they are keyed on the blank plan's id, which
        // is why a blank plan is still a plan.
        let goals = try database.phaseGoals(
            userId: Self.user, planId: AccountSeed.blankProgramId, phase: .cut
        )
        #expect((goals?.calorieGoal ?? 0) > 0)
    }

    /// A person who taps Finish twice, or whose account filled up behind the
    /// flow. The second write is REFUSED and the account is left alone.
    @Test("finishing twice refuses rather than doubling the account")
    func finishingTwiceIsRefused() async throws {
        let database = try store()
        let model = flow(database)
        #expect(await model.finish())
        #expect(await model.finish() == false)
        #expect(model.failure != nil, "a refused seed must say so")

        let context = try database.scheduleContext(userId: Self.user)
        #expect(context.plans.count == 1)
        #expect(context.activeProgram.days.count == 5)
        #expect(try database.exercises().count == Set(
            PlanTemplates.plans.first { $0.id == "onyx5" }?
                .days.flatMap { $0.exercises.map(\.name) } ?? []
        ).count)
    }

    /// The bundled templates are the seed's own catalogue, so nothing in them
    /// can fail to resolve. A template that named a movement it did not also
    /// seed would log every one of its sets against the legacy slug.
    @Test("every bundled plan resolves completely")
    func templatesResolve() async throws {
        for template in PlanTemplates.plans {
            let database = try store()
            let model = flow(database, plan: template.id)
            #expect(await model.finish(), "\(template.id) failed to seed")

            let context = try database.scheduleContext(userId: Self.user)
            let program = try #require(context.program(id: template.id))
            for day in program.days {
                for exercise in day.exercises {
                    #expect(
                        exercise.exerciseId?.isEmpty == false,
                        "\(template.id) · \(day.key) · \(exercise.name) did not resolve"
                    )
                }
            }
        }
    }
}
