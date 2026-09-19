#if DEBUG
import Foundation
import GRDB
import OnyxCore
import OnyxData

/// The catalogue a preview store needs to draw a deck, a plan, a rung or a
/// phase — as ROWS, the way the app reads them since W2.
///
/// The decks come from `plan-templates.json`; the goals, the rungs, the phases
/// and the stack are preview data in the same spirit as
/// `PreviewHarness.sampleBouts`: enough of a plausible account to photograph
/// every screen, not the founder's account. Nothing here reaches OnyxCore or a
/// running app.
///
/// ── `#if DEBUG`, LIKE EVERY OTHER HARNESS FILE ──────────────────────────────
/// A plausible account is still an account, and this one names a body weight, a
/// target, a calorie figure and a supplement stack. None of it is anybody's, and
/// none of it belongs in a shipped binary where a wrong call site could seed it
/// over a real store. Every caller is already `#if DEBUG` (`PreviewHarness`,
/// `LoggerPreviewData`, the five `*Previews` files); this is the wall that keeps
/// it that way rather than a convention that holds until somebody forgets.
enum PreviewCatalogue {

    static let userId = "00000000-0000-0000-0000-000000000001"

    /// Plans, routines, phase goals, weekly set targets, phases and rungs.
    static func seed(_ database: AppDatabase, userId: String = userId, today: String = LogicalDay.today()) {
        let t = Date(timeIntervalSince1970: 1_756_000_000)
        try? database.seedRows { conn in
            for (i, plan) in PlanTemplates.plans.enumerated() {
                let active = plan.id == "onyx5"
                try PlanRow(
                    id: "plan-\(plan.id)", userId: userId, name: plan.label, programId: plan.id, active: active,
                    startedOn: active ? "2026-07-15" : (plan.isLegacy ? "2026-03-08" : nil), createdAt: t,
                    blurb: plan.blurb, isLegacy: plan.isLegacy, sort: i
                ).save(conn)
                for day in plan.days.sorted(by: { $0.sort < $1.sort }) {
                    try RoutineRow(
                        userId: userId, programId: plan.id, dayKey: day.key, label: day.label, sub: day.sub,
                        weekday: day.weekday, accent: day.accent, sort: day.sort,
                        payload: JSONText(raw: RoutinePayload(exercises: day.exercises).encoded()), updatedAt: t
                    ).save(conn)
                }
            }
            // ── THE GOALS ARE THE HARNESS'S, NOT THE TEMPLATE'S ────────────
            // They used to be decoded off `plan-templates.json`, which carried
            // a `phaseGoals` block per plan. That block was one athlete's cut
            // and one athlete's bulk — a calorie figure, a macro split and a
            // target weight — shipped in the app bundle and seeded into every
            // new account's plan. The templates now carry the DECK and nothing
            // about a body, and the numbers a screenshot needs live here, with
            // the rungs and the stack they were always drawn beside.
            //
            // One cut and one bulk for all three plans. A per-plan variation
            // was a second set of numbers no shot and no test ever read.
            let goals: [PlanPhaseGoalRow] = [
                PlanPhaseGoalRow(
                    userId: userId, planId: "", phase: "cut",
                    kcal: 1955, proteinG: 170, carbsG: 195, fatG: 55, fiberMin: 28, fiberMax: 35,
                    updatedAt: t, stepsGoal: 10_000,
                    targetWeightKg: 62, targetBodyFatPct: 13, targetMuscleMassKg: 33,
                    rateMinKgWk: -0.5, rateMaxKgWk: -0.4, label: "Cut", fiberG: 30
                ),
                PlanPhaseGoalRow(
                    userId: userId, planId: "", phase: "bulk",
                    kcal: 2600, proteinG: 160, carbsG: 330, fatG: 70, fiberMin: 33, fiberMax: 38,
                    updatedAt: t, stepsGoal: 8_000,
                    targetWeightKg: 70, targetBodyFatPct: 15, targetMuscleMassKg: 37,
                    rateMinKgWk: 0.2, rateMaxKgWk: 0.25, label: "Lean Bulk", fiberG: 35,
                    bodyFatCeilingPct: 16
                ),
            ]
            for plan in PlanTemplates.plans {
                for var row in goals {
                    row.planId = plan.id
                    try row.save(conn)
                }
            }
            // The weekly set targets DO still come off the file: they are a
            // property of the deck (what the plan asks of each muscle), not of
            // the person running it, and the volume tile is drawn against them.
            if let url = Bundle.main.url(forResource: "plan-templates", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let plans = file["plans"] as? [[String: Any]] {
                for plan in plans {
                    guard let id = plan["id"] as? String else { continue }
                    for (phase, targets) in (plan["volumeTargets"] as? [String: [String: Any]]) ?? [:] {
                        for (muscle, sets) in targets {
                            try PlanPhaseVolumeRow(
                                userId: userId, planId: id, phase: phase, muscle: muscle,
                                targetSets: (sets as? NSNumber)?.intValue ?? 0, updatedAt: t
                            ).save(conn)
                        }
                    }
                }
            }
            // The dated blocks — what week labels, phase pills and the ledger window read.
            let phases: [(String, String, String, String, String?, Int, Bool, String, String)] = [
                ("ppl", "2026-03-08", "bulk", "Bulk", nil, 9, true, "ppl", "PPL Bulk"),
                ("ppl", "2026-05-10", "cut", "Cut", nil, 6, true, "ppl", "PPL Cut"),
                ("ppl", "2026-06-21", "peak", "Peak Week (Maintenance)", "Peak", 1, false, "ppl", "PPL Peak"),
                ("ppl", "2026-06-28", "deload", "Thailand Vacation", "Thailand", 2, false, "ppl", "Thailand Vacation (Deload)"),
                ("onyx5", "2026-07-12", "peak", "Week 0 · Transition", "W0", 1, false, "onyx", "Onyx · Week 0"),
                ("onyx5", "2026-07-19", "cut", "Cut", nil, 13, true, "onyx", "Onyx Cut"),
                ("onyx5", "2026-10-18", "deload", "Transition", "Trans", 2, true, "onyx", "Onyx Transition"),
                ("onyx5", "2026-11-01", "bulk", "Lean Bulk", nil, 11, true, "onyx", "Onyx Lean Bulk"),
            ]
            for (plan, start, kind, name, short, weeks, numbered, era, tag) in phases {
                try PlanPhaseRow(
                    userId: userId, planId: plan, start: start, kind: kind, name: name, short: short,
                    weeks: weeks, numbered: numbered, era: era, eraTag: tag, updatedAt: t
                ).save(conn)
            }
            // The ladder: three deficit rungs and one release, plus the day shapes.
            let rungs: [(String, String, String, Int, Int, Int?, Int?, Int?, String)] = [
                ("home", "Home", "Cooked and weighed — every macro is a real target.", 0, 1935, 190, 55, nil, "day"),
                ("restaurant", "Restaurant", "Eating out — hit the protein, let the split go.", 1, 2400, nil, nil, nil, "day"),
                ("baseline", "Baseline", "The plan as written — 190 g carbs, 10k steps.", 10, 1935, 190, 55, 10000, "deficit"),
                ("lever-1", "Lever 1", "−70 kcal off carbs and fat, steps to 10k.", 11, 1885, 182, 53, 10000, "deficit"),
                ("lever-2", "Lever 2", "Same food as Lever 1, steps 12k–15k. The last rung.", 12, 1885, 182, 53, 12000, "deficit"),
                ("maintenance-week", "Maintenance Week", "A planned week at maintenance — full food, lighter steps. Still cutting.", 13, 2151, 244, 55, 7500, "release"),
            ]
            for (key, label, summary, sort, kcal, carbs, fat, steps, kind) in rungs {
                try TargetProfileRow(
                    userId: userId, key: key, label: label, summary: summary, sort: sort,
                    kcal: kcal, proteinG: 170, carbsG: carbs, fatG: fat, stepsGoal: steps, updatedAt: t, kind: kind
                ).save(conn)
            }
            let periods: [(String, String?)] = [
                ("2026-07-15", "baseline"), ("2026-08-16", "lever-1"), ("2026-08-20", nil),
                ("2026-08-30", "maintenance-week"), ("2026-09-06", "baseline"),
            ]
            for (from, key) in periods {
                try LeverPeriodRow(
                    userId: userId, startsOn: from, profileKey: key,
                    goals: key == nil ? JSONText(raw: #"{"calorie":1999,"protein":170,"carbs":206,"fat":55,"steps":10000}"#) : nil,
                    updatedAt: t
                ).save(conn)
            }
        }
    }

    /// A supplement stack as rows — the seed W2 stopped compiling in.
    static func seedStack(_ database: AppDatabase, userId: String = userId) {
        let items: [(String, String, String, String, String, String, Bool?, String?)] = [
            ("multivitamin", "Two Per Day Multivitamin", "1 tab", "#3E9E7A", "10:30", "Morning", nil, "2 tabs on Monday & Friday (Leg Days)"),
            ("d3k2", "Vitamin D3 + K2", "125 mcg", "#3E9E7A", "10:30", "Morning", nil, nil),
            ("citrulline", "L-Citrulline", "6 g", "#8E9AAC", "11:45", "Pre-Workout", true, nil),
            ("caffeine", "Nutricost Caffeine", "200 mg", "#8E9AAC", "11:45", "Pre-Workout", true, nil),
            ("creatine", "Creatine Monohydrate", "5 g", "#3D7AB8", "15:00", "Lunch / Post-Workout", nil, nil),
            ("omega3", "Omega-3 Fish Oil", "2 caps", "#3D7AB8", "15:00", "Lunch / Post-Workout", nil, nil),
            ("magnesium", "Magnesium Glycinate", "300 mg", "#8A6FA8", "22:00", "Before Bed", nil, nil),
            ("glycine", "Glycine", "5 g", "#8A6FA8", "22:00", "Before Bed", nil, nil),
            ("theanine", "L-Theanine", "200 mg", "#8A6FA8", "22:00", "Before Bed", nil, nil),
        ]
        for (key, name, dose, color, time, slot, trainingOnly, notes) in items {
            _ = try? database.addCustomSupplement(
                userId: userId, name: name, dose: dose, color: color, form: nil, time: time,
                schedule: CustomSchedule(key: key, slot: slot, notes: notes, trainingOnly: trainingOnly),
                micros: SupplementNutrients.table[key]
            )
        }
    }
}
#endif
