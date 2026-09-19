import Foundation
import GRDB
import OnyxCore
@testable import OnyxData

/// The founder's ONYX-5 deck as a TEST FIXTURE — generated from
/// `native/Onyx/Resources/plan-templates.json` (the same template W5 seeds a new
/// account from), not typed by hand. `Program.onyx5` no longer exists in
/// OnyxCore (W2); the tests that exercised the sync, the seed and the
/// progression queue against a real deck get this one instead.
enum SampleDeck {
    static let onyx5 = Program(id: "onyx5", label: "Onyx-5", blurb: "5-day antagonist hybrid — Sun/Mon/Tue/Thu/Fri, Wed & Sat Zone-2 rest.", days: [
        ProgramDay(key: "cb_a", label: "Upper A", sub: "Chest + Back", accent: 0xE0703C, weekday: 0, exercises: [
            ProgramExercise("Incline DB Press", sets: 3, cutSets: 3, wk1Kg: 32, reps: "8–12", restSec: 120, compound: true),
            ProgramExercise("Lat Pulldown", sets: 3, cutSets: 3, wk1Kg: 45, reps: "8–12", restSec: 135, compound: true),
            ProgramExercise("Chest Press", sets: 3, cutSets: 2, wk1Kg: 34, reps: "10–12", restSec: 135, compound: true),
            ProgramExercise("Seated Cable Row (V-Grip)", sets: 3, cutSets: 2, wk1Kg: 38.5, reps: "10–12", restSec: 120, compound: true, note: "V-grip"),
            ProgramExercise("Pec Deck", sets: 2, cutSets: 2, wk1Kg: 47.5, reps: "12–15", restSec: 120),
            ProgramExercise("Straight-Arm Pulldown", sets: 3, cutSets: 3, wk1Kg: 15, reps: "12–15", restSec: 105),
            ProgramExercise("Face Pull", sets: 3, cutSets: 3, wk1Kg: 13.75, reps: "12–15", restSec: 105),
        ]),
        ProgramDay(key: "legs_a", label: "Legs & Core A", sub: "Quad Focus", accent: 0x3D7AB8, weekday: 1, exercises: [
            ProgramExercise("Leg Press", sets: 4, cutSets: 3, wk1Kg: 70, reps: "8–12", restSec: 135, compound: true, note: "1 warm-up @40kg"),
            ProgramExercise("Hack Squat", sets: 3, cutSets: 2, wk1Kg: nil, reps: "10–12", restSec: 135, compound: true),
            ProgramExercise("Leg Extension", sets: 3, cutSets: 3, wk1Kg: 37.5, reps: "12–15", restSec: 120),
            ProgramExercise("Seated Leg Curl", sets: 3, cutSets: 3, wk1Kg: 40, reps: "10–15", restSec: 105),
            ProgramExercise("Calf Press", sets: 4, cutSets: 3, wk1Kg: 65, reps: "10–15", restSec: 90),
            ProgramExercise("Crunch Machine", sets: 3, cutSets: 3, wk1Kg: 52.5, reps: "10–12", restSec: 90),
            ProgramExercise("Reverse Crunch", sets: 3, cutSets: 3, wk1Kg: nil, reps: "12–15", restSec: 75),
        ]),
        ProgramDay(key: "arms", label: "Delts & Arms", sub: nil, accent: 0x8A6FA8, weekday: 2, exercises: [
            ProgramExercise("Shoulder Press", sets: 3, cutSets: 3, wk1Kg: 28, reps: "8–10", restSec: 105, compound: true),
            ProgramExercise("Single Arm Lateral Raise", sets: 5, cutSets: 4, wk1Kg: 5, reps: "12–20", restSec: 105, note: "per side"),
            ProgramExercise("Seated Incline DB Curl", sets: 3, cutSets: 3, wk1Kg: 14, reps: "8–12", restSec: 105),
            ProgramExercise("Overhead Triceps Extension", sets: 3, cutSets: 3, wk1Kg: 9, reps: "10–15", restSec: 90),
            ProgramExercise("Hammer Curl", sets: 3, cutSets: 3, wk1Kg: 16, reps: "10–12", restSec: 105),
            ProgramExercise("Rope Triceps Pushdown", sets: 2, cutSets: 2, wk1Kg: 13.5, reps: "12–15", restSec: 90),
            ProgramExercise("Reverse EZ-Bar Curl", sets: 2, cutSets: 2, wk1Kg: 15, reps: "12–15", restSec: 90),
            ProgramExercise("Seated DB Wrist Curl", sets: 2, cutSets: 0, wk1Kg: 16, reps: "15–20", restSec: 90),
        ]),
        ProgramDay(key: "cb_b", label: "Upper B", sub: "Chest + Back", accent: 0xB4522A, weekday: 4, exercises: [
            ProgramExercise("Chest Press", sets: 3, cutSets: 3, wk1Kg: 35, reps: "10–12", restSec: 120, compound: true),
            ProgramExercise("Neutral-Grip Lat Pulldown", sets: 3, cutSets: 2, wk1Kg: 45, reps: "10–12", restSec: 120, compound: true),
            ProgramExercise("Single Arm Cable Crossover", sets: 2, cutSets: 2, wk1Kg: 7.5, reps: "12–15", restSec: 105, note: "per arm"),
            ProgramExercise("Seated Cable Row (Wide Grip)", sets: 3, cutSets: 2, wk1Kg: 35, reps: "10–12", restSec: 120, compound: true, note: "wide bar"),
            ProgramExercise("Single Arm Lateral Raise", sets: 4, cutSets: 3, wk1Kg: 3.75, reps: "15–20", restSec: 90, note: "per side"),
            ProgramExercise("Preacher Curl", sets: 3, cutSets: 3, wk1Kg: 15, reps: "8–12", restSec: 105),
            ProgramExercise("Single Arm Triceps Pushdown", sets: 3, cutSets: 3, wk1Kg: 5, reps: "12–15", restSec: 90, note: "per arm"),
        ]),
        ProgramDay(key: "legs_b", label: "Legs & Core B", sub: "Posterior Focus", accent: 0x2E5C8A, weekday: 5, exercises: [
            ProgramExercise("Romanian Deadlift", sets: 4, cutSets: 3, wk1Kg: 30, reps: "8–12", restSec: 120, compound: true),
            ProgramExercise("Hip Thrust", sets: 3, cutSets: 3, wk1Kg: 25, reps: "8–15", restSec: 135, compound: true),
            ProgramExercise("Leg Press", sets: 2, cutSets: 2, wk1Kg: 70, reps: "12–15", restSec: 135, compound: true, note: "horizontal sled"),
            ProgramExercise("Hip Adduction", sets: 2, cutSets: 0, wk1Kg: 50, reps: "12–15", restSec: 90),
            ProgramExercise("Seated Leg Curl", sets: 2, cutSets: 2, wk1Kg: 45, reps: "10–15", restSec: 105),
            ProgramExercise("Calf Press", sets: 4, cutSets: 3, wk1Kg: 67.5, reps: "10–15", restSec: 105),
            ProgramExercise("Hanging Knee Raise", sets: 3, cutSets: 3, wk1Kg: nil, reps: "10–15", restSec: 90),
            ProgramExercise("Side Plank", sets: 2, cutSets: 2, wk1Kg: nil, reps: "55s", restSec: 90, note: "per side"),
        ]),
    ])
}

extension SampleDeck {
    /// The catalogue the founder's seed wrote, as rows in a test store: three
    /// `plans`, the ONYX-5 `routines`, and the eight dated `plan_phases` —
    /// so a test that used to lean on the compiled deck, the era boundary
    /// (`Era.forDate`) or `Phases.all` reads them the way the app does.
    static func seedCatalogue(_ conn: Database, userId: String) throws {
        let t = Date(timeIntervalSince1970: 1_756_000_000)
        try PlanRow(id: "plan-onyx5", userId: userId, name: "Onyx-5", programId: "onyx5", active: true, startedOn: "2026-07-15", createdAt: t, blurb: onyx5.blurb, isLegacy: false, sort: 0).save(conn)
        try PlanRow(id: "plan-onyx4", userId: userId, name: "Onyx-4", programId: "onyx4", active: false, startedOn: nil, createdAt: t, blurb: "", isLegacy: false, sort: 1).save(conn)
        try PlanRow(id: "plan-ppl", userId: userId, name: "Push/Pull/Legs", programId: "ppl", active: false, startedOn: "2026-03-08", createdAt: t, blurb: "", isLegacy: true, sort: 2).save(conn)
        for (i, day) in onyx5.days.enumerated() {
            let payload = RoutinePayload(exercises: day.exercises.map {
                RoutineExercise(name: $0.name, exerciseId: $0.exerciseId, sets: $0.sets, cutSets: $0.cutSets, reps: $0.reps,
                                restSec: $0.restSec, wk1Kg: $0.wk1Kg, compound: $0.isCompound, note: $0.note)
            })
            try RoutineRow(userId: userId, programId: onyx5.id, dayKey: day.key, label: day.label, sub: day.sub,
                           weekday: day.weekday, accent: Int(day.accent), sort: i,
                           payload: JSONText(raw: payload.encoded()), updatedAt: t).save(conn)
        }
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
            try PlanPhaseRow(userId: userId, planId: plan, start: start, kind: kind, name: name, short: short,
                             weeks: weeks, numbered: numbered, era: era, eraTag: tag, updatedAt: t).save(conn)
        }
    }
}
