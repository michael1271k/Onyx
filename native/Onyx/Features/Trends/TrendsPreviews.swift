#if DEBUG
import SwiftUI
import OnyxCore
import OnyxData

/// Seeded Trends screens for `#Preview` and `scripts/native-shot.sh`.
///
/// Ten Onyx-5 weeks ending today, written as raw rows through `seedRows` and
/// read back through the same `trainingTrendSessions` the screen uses, so a
/// shot exercises the read path. Loads step up 2.5 kg a week so the strength
/// lines slope; one exercise is bodyweight so the `||` rule has something to
/// drop; one is a unilateral pair so the volume collapse is exercised.
enum TrendsPreviews {
    static let userId = "00000000-0000-0000-0000-000000000001"

    /// (name, working kg in week 10, reps) — names the muscle map resolves.
    private static let plan: [(dayKey: String, weekday: Int, lifts: [(String, Double, Int)])] = [
        ("cb_a",   0, [("Incline DB Press", 36, 10), ("Lat Pulldown", 52, 10), ("Cable Fly", 15, 12)]),
        ("legs_a", 1, [("Leg Press", 92, 10), ("Seated Leg Curl", 45, 12), ("Reverse Crunch", 0, 15)]),
        ("arms",   2, [("Lateral Raise DB", 10, 15), ("Hammer Curl", 14, 12), ("Rope Triceps Pushdown", 20, 12)]),
        ("cb_b",   4, [("Incline DB Press", 36, 10), ("Seated Cable Row (V-Grip)", 45, 10)]),
        ("legs_b", 5, [("Leg Press", 92, 10), ("Leg Extension", 45, 12), ("Calf Raise", 60, 15)]),
    ]

    @MainActor
    static func sessions(seeded: Bool = true) -> [TrendSession] {
        let database = try! AppDatabase.inMemory(deviceId: "shot")
        let today = LogicalDay.today()
        if seeded {
            try! database.seedRows { db in
                var exerciseIds: [String: String] = [:]
                for day in plan {
                    for (name, _, _) in day.lifts where exerciseIds[name] == nil {
                        let id = newOnyxID()
                        exerciseIds[name] = id
                        try Exercise(id: id, name: name).insert(db)
                    }
                }
                let thisWeek = Week.start(of: today)
                for weeksAgo in 0..<10 {
                    for day in plan {
                        guard let start = ISODate.addDays(thisWeek, -7 * weeksAgo),
                              let date = ISODate.addDays(start, day.weekday), date <= today else { continue }
                        let sessionId = newOnyxID()
                        try WorkoutSession(id: sessionId, userId: userId, dayKey: day.dayKey, date: date, sessionRpe: 7).insert(db)
                        var index = 0
                        for (name, kg, reps) in day.lifts {
                            let load = kg > 0 ? kg - 2.5 * Double(weeksAgo) : 0
                            let unilateral = name == "Lateral Raise DB"
                            for set in 0..<3 {
                                let sides: [String?] = unilateral ? ["left", "right"] : [nil]
                                let pairId = unilateral ? newOnyxID() : nil
                                for side in sides {
                                    try WorkoutSet(
                                        id: newOnyxID(), sessionId: sessionId, exerciseId: exerciseIds[name]!,
                                        setIndex: index, weightKg: set == 0 ? load * 0.6 : load, reps: reps,
                                        setType: set == 0 ? "warmup" : "normal", side: side, pairId: pairId,
                                        est1rmKg: OneRepMax.estimate(weight: set == 0 ? load * 0.6 : load, reps: Double(reps)),
                                        foldOrder: index
                                    ).insert(db)
                                    index += 1
                                }
                            }
                        }
                    }
                }
            }
        }
        return try! database.trainingTrendSessions(userId: userId, from: "2000-01-01", to: today)
    }

    /// A lever pulled for one week, three weeks back. `stored` only governs
    /// dates from `today` on, so the WEEK is expressed as a release that has
    /// already ended — which is exactly how a past maintenance week reads.
    private static var maintenanceLens: MaintenanceLens {
        let today = LogicalDay.today()
        let weekStart = ISODate.addDays(Week.start(of: today), -21) ?? today
        let release = NutritionLever(
            id: "maintenance-week", kind: .release, label: "Maintenance Week", summary: "",
            calorieGoal: 2151, proteinGoalG: 170, carbsGoalG: 244, fatGoalG: 55, stepsGoal: 7500
        )
        return MaintenanceLens(
            ladder: LeverLadder(rungs: [release], stored: release.id, releaseEndsOn: ISODate.addDays(weekStart, 6)),
            today: weekStart
        )
    }

    @MainActor @ViewBuilder
    static func view(_ screen: String) -> some View {
        switch screen {
        case "trends-empty":
            NavigationStack { TrainingTrendsView(seeded: sessions(seeded: false)) }.environment(AppEnvironment.preview)
        case "trends-maintenance":
            // A maintenance lever running from three weeks ago to two, so the
            // hollow bar sits BETWEEN solid ones — a wash at the end of the
            // series could be read as a week that is not over yet.
            NavigationStack {
                TrainingTrendsView(seeded: sessions(), seededLens: maintenanceLens)
            }
            .environment(AppEnvironment.preview)
        default:
            NavigationStack { TrainingTrendsView(seeded: sessions()) }.environment(AppEnvironment.preview)
        }
    }
}
#endif
