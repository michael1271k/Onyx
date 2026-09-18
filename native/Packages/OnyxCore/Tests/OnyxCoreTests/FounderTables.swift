import Foundation
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// The founder's tables, as TEST INPUTS.
//
// Before W2 the package compiled these in (`Phases.all`, `Levers.all`,
// `PrTruth.book`, `Program.onyx5`, …) and the golden suites compared the
// constants against the fixtures. The constants are rows now and every
// function takes its table as a parameter, so the same fixtures feed the
// function vectors instead. They are inputs, not expectations, and none of
// them is deletable:
//
//   · `phases-table.json`   → `phases`   (era tags rebranded, `planId` filled)
//   · `levers-table.json`   → `rungs`, `periods`, `ladder(stored:releaseEndsOn:)`
//   · `pr-floor.json`       → `floors`
//   · `plan-templates.json` → `programs`, `plans`, `deck` — the founder's three
//     decks, generated from the same constants the vectors were, so the
//     schedule, swap and lookup vectors keep running over all three decks
//     with their subs and accents. `program-onyx5.json` holds `deck` to the
//     shape the vectors used.
//
//     IT IS NO LONGER A COPY OF THE BUNDLED FILE. `wk1Kg` and `phaseGoals`
//     were stripped out of `native/Onyx/Resources/plan-templates.json`:
//     they were one athlete's loads and one athlete's calories, shipped to
//     everybody in the app bundle. THIS file keeps both, because it is an
//     INPUT: `program-onyx5.json` asserts a `wk1Kg` per exercise, and a
//     fixture that stopped carrying them would not fail those vectors, it
//     would quietly compare nil against nil. The two files are allowed to
//     diverge and this paragraph is the record of why.
// ─────────────────────────────────────────────────────────────────────────────

private struct Nothing: Decodable {}

enum FounderTables {
    /// `plans.started_on` of Onyx-5 — the cut start every era rule keyed on.
    static let planStartISO = "2026-07-15"

    // MARK: Phases

    static let phases: [PhaseDef] = {
        let rows = try! GoldenFixture<Nothing, [PhaseDef]>.load("phases-table").cases[0].expected
        return rows.map { row in
            var d = row
            d.eraTag = d.eraTag.map(rebranded)
            d.planId = d.era == .ppl ? "ppl" : "onyx5"
            return d
        }
    }()

    // MARK: Levers

    private struct LeverTable: Decodable {
        struct Row: Decodable { let from: String; let leverId: String; let goals: LeverGoals? }
        let levers: [NutritionLever]
        let schedule: [Row]
    }
    private static let leverTable = try! GoldenFixture<Nothing, LeverTable>.load("levers-table").cases[0].expected

    static let rungs: [NutritionLever] = leverTable.levers
    static let periods: [LeverPeriod] = leverTable.schedule.map {
        LeverPeriod(from: $0.from, profileKey: $0.leverId == "custom" ? nil : $0.leverId, goals: $0.goals)
    }

    static func ladder(stored: String?, releaseEndsOn: String?) -> LeverLadder {
        LeverLadder(rungs: rungs, periods: periods, stored: stored, releaseEndsOn: releaseEndsOn)
    }

    /// The rungs as `target_profiles` rows with a `kind` — what `TargetSources`
    /// carries them as.
    static let rungProfiles: [TargetProfile] = rungs.enumerated().map { i, r in
        TargetProfile(key: r.id, label: r.label, summary: r.summary, sort: 10 + i, kcal: r.calorieGoal, proteinG: r.proteinGoalG,
                      carbsG: r.carbsGoalG, fatG: r.fatGoalG, stepsGoal: r.stepsGoal, kind: r.kind == .release ? .release : .deficit)
    }

    // MARK: PR floors

    private struct NameIn: Decodable { let name: String? }

    static let floors: [String: PrFloor] = {
        var out: [String: PrFloor] = [:]
        for c in try! GoldenFixture<NameIn, PrFloor?>.load("pr-floor").cases {
            if let name = c.input.name, let floor = c.expected { out[name] = floor }
        }
        return out
    }()

    // MARK: Decks and plans

    private struct Template: Decodable {
        struct Day: Decodable {
            let key: String; let label: String; let sub: String?; let accent: UInt32; let weekday: Int; let sort: Int
            let exercises: [RoutineExercise]
        }
        struct Plan: Decodable {
            let id: String; let label: String; let blurb: String; let isLegacy: Bool; let sort: Int; let days: [Day]
        }
        let plans: [Plan]
    }

    private static let template: Template = {
        let url = Bundle.module.url(forResource: "plan-templates", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode(Template.self, from: Data(contentsOf: url))
    }()

    /// `plans.started_on` from the founder's seed; Onyx-4 was never started.
    private static let startedOn = ["onyx5": planStartISO, "ppl": "2026-03-08"]

    static let plans: [PlanInfo] = template.plans.map {
        PlanInfo(id: $0.id, label: $0.label, blurb: $0.blurb, isLegacy: $0.isLegacy, startedOn: startedOn[$0.id], sort: $0.sort)
    }

    static let programs: [Program] = template.plans.map { plan in
        Program(id: plan.id, label: plan.label, blurb: plan.blurb, days: plan.days.sorted { $0.sort < $1.sort }.map {
            ProgramDay(key: $0.key, label: $0.label, sub: $0.sub, accent: $0.accent, weekday: $0.weekday,
                       exercises: $0.exercises.map(\.programExercise))
        })
    }

    static func program(_ id: String) -> Program? { programs.first { $0.id == id } }

    /// Onyx-5 — the deck every single-deck vector was generated over.
    static let deck: Program = program("onyx5")!

    /// A context with the founder's rows in, on the active Onyx-5 cut.
    static let scheduleContext = ScheduleContext(programId: "onyx5", phase: .cut, programs: programs, plans: plans, phases: phases)

    /// A fixture's context (id, phase, overrides, layout) with the tables in.
    ///
    /// The vectors were generated when "the current era" meant "whatever plan
    /// is selected"; the rows say which plan owns a block. So the Onyx-era
    /// blocks are tagged with the context's own plan — the same statement the
    /// old model made implicitly — and the PPL blocks stay PPL's.
    static func filled(_ ctx: ScheduleContext) -> ScheduleContext {
        var c = ctx
        c.programs = programs; c.plans = plans
        c.phases = phases.map { row in
            var p = row
            if p.era == .onyx { p.planId = ctx.programId }
            return p
        }
        return c
    }

    /// `Schedule.planId(owning:)` over the founder's rows — what replaced `Era.forDate`.
    static func planOwning(_ dateISO: String) -> String {
        Schedule.planId(owning: dateISO, in: scheduleContext)
    }
}
