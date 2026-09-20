import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// The fold nothing could test until W8.
///
/// `WeekReport` was declared in `Features/Workout/WeeklyReportView.swift` — the
/// app target, whose suite `npm run check` does not run — so nine derived
/// figures over the whole weekly payload were verified by looking at a
/// screenshot of them. Every assertion below is the report against the payload
/// field it claims to fold, read out of the SAME `WeeklyExportBuilder` call the
/// page makes, because the whole point of there being one reader is that the
/// page and the exported document cannot disagree about one week.
@Suite("Week report")
struct WeekReportTests {
    private let user = "u1"
    private let weekStart = "2026-08-23"   // Sunday
    private let weekEnd = "2026-08-29"
    private let today = "2026-09-06"       // the week is closed

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    /// One week of real rows, holding one case of every shape the report folds:
    /// two tracked days and one untracked, two nights scored and one not, four
    /// records (one past the cap — the builder folds a movement's AXES into one
    /// `ExportPr`, so four records means four movements), two cardio bouts, two
    /// DOMS ratings and two stress readings.
    private func seeded() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let t = iso("2026-08-23T00:00:00Z")
        try db.writer.write { conn in
            try UserGoalRow(
                id: "g1", userId: user, sleepGoalHours: 8, calorieGoal: 2000, proteinGoalG: 170,
                carbsGoalG: 200, fatGoalG: 55, stepsGoal: 10_000, waterGoalMl: 3000,
                contextMode: "normal", createdAt: t, updatedAt: t, autoLogSupplements: false,
                activeProgram: "onyx5", dayCutoffHour: 4, unitSystem: "metric", reduceMotion: false,
                timezone: "UTC", weekEndDay: 6, activePlan: "onyx5", activePhase: "cut",
                trackRpe: true, activeLever: "custom"
            ).insert(conn)
            try SampleDeck.seedCatalogue(conn, userId: user)
            try PlanPhaseVolumeRow(
                userId: user, planId: "onyx5", phase: "cut", muscle: "Quads", targetSets: 12
            ).insert(conn)

            try Exercise(id: "ex-lp", name: "Leg Press").insert(conn)
            try Exercise(id: "ex-ip", name: "Incline DB Press").insert(conn)
            try Exercise(id: "ex-lat", name: "Lat Pulldown").insert(conn)
            try Exercise(id: "ex-cp", name: "Chest Press").insert(conn)

            // Two finished sessions inside the week, and four records across
            // them — one past `WeekReport.recordCap`.
            try WorkoutSession(
                id: "s1", userId: user, dayKey: "legs_a", date: "2026-08-24",
                startedAt: iso("2026-08-24T09:00:00Z"), endedAt: iso("2026-08-24T10:20:00Z"),
                durationMin: 80, sessionRpe: 8
            ).insert(conn)
            try WorkoutSet(id: "a1", sessionId: "s1", exerciseId: "ex-lp", setIndex: 0, weightKg: 40, reps: 15, setType: "warmup").insert(conn)
            try WorkoutSet(id: "a2", sessionId: "s1", exerciseId: "ex-lp", setIndex: 1, weightKg: 100, reps: 10, rpe: 9).insert(conn)
            try WorkoutSet(id: "a3", sessionId: "s1", exerciseId: "ex-lp", setIndex: 2, weightKg: 100, reps: 9, rpe: 9.5).insert(conn)
            try WorkoutSession(
                id: "s2", userId: user, dayKey: "cb_a", date: "2026-08-26",
                startedAt: iso("2026-08-26T09:00:00Z"), endedAt: iso("2026-08-26T10:00:00Z"),
                durationMin: 60, sessionRpe: 7
            ).insert(conn)
            try WorkoutSet(id: "b1", sessionId: "s2", exerciseId: "ex-ip", setIndex: 0, weightKg: 40, reps: 10, rpe: 8).insert(conn)
            try WorkoutSet(id: "b2", sessionId: "s2", exerciseId: "ex-lat", setIndex: 1, weightKg: 45, reps: 10, rpe: 8).insert(conn)
            try WorkoutSet(id: "b3", sessionId: "s2", exerciseId: "ex-cp", setIndex: 2, weightKg: 50, reps: 10, rpe: 8).insert(conn)
            for (axis, value, reps, kg, key, session, date) in [
                ("weight", 100.0, 10, 100.0, "Leg Press", "s1", "2026-08-24"),
                ("e1rm", 133.0, 10, 100.0, "Leg Press", "s1", "2026-08-24"),
                ("volume", 1_900.0, 10, 100.0, "Leg Press", "s1", "2026-08-24"),
                ("weight", 40.0, 10, 40.0, "Incline DB Press", "s2", "2026-08-26"),
                ("weight", 45.0, 10, 45.0, "Lat Pulldown", "s2", "2026-08-26"),
                ("weight", 50.0, 10, 50.0, "Chest Press", "s2", "2026-08-26"),
            ] {
                try PersonalRecordRow(
                    userId: user, exerciseKey: key, axis: axis, value: value, reps: reps,
                    weightKg: kg, sessionId: session, achievedOn: date
                ).insert(conn)
            }

            // Two days tracked, one deliberately left out — so `kcalByDay` has
            // a hole in it and the mean has a denominator smaller than seven.
            try NutritionEntryRow(
                id: "n1", userId: user, loggedAt: t, date: "2026-08-24", mealType: "daily",
                calories: 2010, proteinG: 175, carbsG: 198, fatG: 56, fiberG: 30, createdAt: t,
                micros: JSONText(raw: #"{"sodium":4200,"magnesium":150}"#)
            ).insert(conn)
            try NutritionEntryRow(
                id: "n2", userId: user, loggedAt: t, date: "2026-08-26", mealType: "daily",
                calories: 2600, proteinG: 150, carbsG: 260, fatG: 70, fiberG: 25, createdAt: t,
                micros: JSONText(raw: #"{"sodium":4400,"magnesium":160}"#)
            ).insert(conn)

            try WaterIntakeRow(id: "w1", userId: user, loggedAt: t, date: "2026-08-24", amountMl: 2000, createdAt: t).insert(conn)
            try WaterIntakeRow(id: "w2", userId: user, loggedAt: t, date: "2026-08-26", amountMl: 3000, createdAt: t).insert(conn)

            try SleepSessionRow(
                id: "sl1", userId: user, startTime: iso("2026-08-23T22:30:00Z"),
                endTime: iso("2026-08-24T06:30:00Z"), durationMin: 480, deepMin: 60, remMin: 100,
                coreMin: 300, awakeMin: 20, createdAt: t
            ).insert(conn)
            try SleepSessionRow(
                id: "sl2", userId: user, startTime: iso("2026-08-25T23:00:00Z"),
                endTime: iso("2026-08-26T05:00:00Z"), durationMin: 360, deepMin: 40, remMin: 80,
                coreMin: 230, awakeMin: 10, createdAt: t
            ).insert(conn)

            // Two scored nights and a third with NO sleep score — the mean has
            // to skip it rather than read it as a zero.
            for (date, score, sleep, battery) in [
                ("2026-08-24", 74, 80, 70), ("2026-08-26", 66, 60, 50), ("2026-08-27", 70, -1, 60),
            ] {
                var row = DailyScoreRow(id: "sc-\(date)", userId: user, date: date, score: score, computedAt: t, finalized: true)
                row.sleepScore = sleep >= 0 ? sleep : nil
                row.batteryPct = battery
                try row.insert(conn)
            }

            try DomsLogRow(id: "dm1", userId: user, date: "2026-08-25", muscleGroup: "quads", severity: 4, createdAt: t).insert(conn)
            try DomsLogRow(id: "dm2", userId: user, date: "2026-08-27", muscleGroup: "glutes", severity: 2, createdAt: t).insert(conn)
            try StressLogRow(id: "st1", userId: user, date: "2026-08-24", slot: "morning", level: 2, tags: JSONText(raw: "[]"), note: nil, createdAt: t, updatedAt: t).insert(conn)
            try StressLogRow(id: "st2", userId: user, date: "2026-08-26", slot: "evening", level: 4, tags: JSONText(raw: "[]"), note: nil, createdAt: t, updatedAt: t).insert(conn)

            try CardioLogRow(id: "cl1", userId: user, date: "2026-08-25", kind: "walk", distanceM: 5000, durationMin: 50, kcal: 250, createdAt: t).insert(conn)
            try CardioLogRow(
                id: "cl2", userId: user, date: "2026-08-28", kind: "run", distanceM: 3000,
                durationMin: 18, kcal: 200, fromHealthkit: true,
                createdAt: iso("2026-08-28T06:12:00Z"), activeKcal: 200, totalKcal: 230
            ).insert(conn)

            try BodyCompositionRow(
                id: "bc1", userId: user, measuredAt: t, date: "2026-08-25", weightKg: 82.4,
                bodyFatPct: 17.2, waterPct: 58.6, boneMassKg: 2.7, bmi: 24.1, createdAt: t,
                fatMassKg: 14.2, bodyWaterMassKg: 48.3, musclePct: 44.7, proteinPct: 18,
                boneMineralPct: 4.1, skeletalMuscleMassKg: 36.8
            ).insert(conn)
        }
        return db
    }

    private func summary() -> WeeklyWrap.Summary {
        WeeklyWrap.Summary(
            weekStart: weekStart, sessions: 2, tonnageKg: 12_000, tonnageDeltaKg: 400,
            prCount: 4, isDeload: false, movements: []
        )
    }

    private func built(userId: String? = nil) throws -> (WeekReport, WeeklyExportInput) {
        let db = try seeded()
        let report = try #require(
            WeekReport.build(
                database: db, userId: userId ?? user, summary: summary(),
                plannedSessions: 5, today: today
            )
        )
        let input = try WeeklyExportBuilder(database: db, userId: user)
            .input(weekStart: weekStart, today: today)
        return (report, input)
    }

    // MARK: - The three capsules

    @Test("the sleep capsule is the mean of the STORED sleep scores, and skips a night that has none")
    func sleepScoreIsTheStoredMean() throws {
        let (report, _) = try built()
        // 74 and 66 are scored; the third row carries a battery and no sleep
        // score, and a mean that read it as zero would print 47.
        #expect(report.sleepScoreAvg == 70)
    }

    @Test("the battery capsule is the stored battery, never a recomputed one")
    func batteryIsTheStoredMean() throws {
        let (report, input) = try built()
        let battery = input.days.compactMap(\.batteryPct)
        #expect(battery.count == 3)
        #expect(report.batteryAvg == battery.reduce(0, +) / Double(battery.count))
    }

    @Test("adherence counts graded days only — an exception is neither a hit nor a miss")
    func adherenceCountsGradedDaysOnly() throws {
        let (report, _) = try built()
        let graded = report.adherence.filter { $0.verdict == .hit || $0.verdict == .miss }
        let hits = report.adherence.filter { $0.verdict == .hit }.count
        #expect(!graded.isEmpty, "the seed grades no day — the capsule asserts nothing")
        #expect(report.nutritionAdherencePct == Double(hits) / Double(graded.count) * 100)
        #expect(!graded.contains { $0.verdict == .exception })
        // Seven dots whatever was logged: the strip is the week, not the days
        // that happened to carry food.
        #expect(report.adherence.count == 7)
    }

    // MARK: - Nutrition

    @Test("an untracked day is omitted from the bars and from the mean, never drawn as a zero")
    func anUntrackedDayIsMissingAndNotZero() throws {
        let (report, _) = try built()
        #expect(report.kcalByDay.map(\.d) == ["2026-08-24", "2026-08-26"])
        #expect(report.kcalByDay.map(\.v) == [2010, 2600])
        // The mean is over the two days that logged, not over seven.
        let calories = try #require(report.macroTable.first { $0.label == "Calories" })
        #expect(calories.mean == 2305)
        #expect(calories.target == 2000)
    }

    @Test("the target rule is the mean of the targets in force, not today's")
    func theTargetIsTheWeeksOwn() throws {
        let (report, input) = try built()
        var perDate: [Double] = []
        for period in input.targetPeriods ?? [] {
            for date in period.dates where input.days.contains(where: { $0.date == date }) {
                perDate.append(period.goals.calorie)
            }
        }
        if perDate.isEmpty { perDate = input.days.compactMap { _ in input.calorieGoal } }
        #expect(report.kcalTarget == jsRound(perDate.reduce(0, +) / Double(perDate.count)))
    }

    @Test("only the micronutrients that breach are carried, worst first")
    func onlyBreachedMicrosAreCarried() throws {
        let (report, _) = try built()
        let labels = report.flaggedMicros.map(\.label)
        // Sodium 4,300 mg against a 3,000 mg CEILING and magnesium 155 mg
        // against a 400 mg FLOOR both breach; protein at 162 g against 170 g is
        // inside the floor's 80 % and must not appear.
        #expect(labels.contains("Sodium"))
        #expect(labels.contains("Magnesium"))
        #expect(!labels.contains("Protein"))
        // Furthest from its target first: magnesium is 61 % short, sodium 43 %
        // over.
        #expect(labels.first == "Magnesium")
        #expect(report.flaggedMicros.allSatisfy { $0.isBreach || $0.doubted })
    }

    // MARK: - Training

    @Test("the muscle rows carry the plan_phase_volume target, and only landmarks")
    func muscleVolumeCarriesThePlanTarget() throws {
        let (report, input) = try built()
        let quads = try #require(report.volumeByMuscle.first { $0.muscle == "Quads" })
        #expect(quads.target == 12, "the plan_phase_volume override did not reach the report")
        #expect(quads.sets > 0)
        #expect(report.volumeByMuscle.count == input.volumeByMuscle.count)
        #expect(report.volumeByMuscle.allSatisfy { LandmarkMuscle(rawValue: $0.muscle) != nil })
        // The capsules are the muscles the week went into, most worked first —
        // never a muscle at zero sets.
        #expect(report.topMuscles.count <= 4)
        #expect(!report.topMuscles.isEmpty)
    }

    // MARK: - Recovery

    @Test("sleep is drawn in hours and a night with no reading is omitted")
    func sleepByDayIsHours() throws {
        let (report, _) = try built()
        #expect(report.sleepByDay.map(\.d) == ["2026-08-24", "2026-08-26"])
        #expect(report.sleepByDay.map(\.v) == [8, 6])
        #expect(report.sleepGoalHours == 8)
        #expect(report.batterySpark.count == 3)
    }

    @Test("stress is the mean of the week's readings and the peak is the worst DOMS rating")
    func stressAndDoms() throws {
        let (report, _) = try built()
        #expect(report.stressMean == 3)
        let peak = try #require(report.domsPeak)
        #expect(peak.severity == 4)
        #expect(peak.date == "2026-08-25")
    }

    // MARK: - Cardio and body

    @Test("cardio is the week's bouts summed, kinds most frequent first")
    func cardioTotals() throws {
        let (report, _) = try built()
        let cardio = try #require(report.cardio)
        #expect(cardio.bouts == 2)
        #expect(cardio.minutes == 68)
        #expect(cardio.km == 8)
        // `totalKcal` where the import carried one (230) and `kcal` behind it
        // (250) — the same preference the exported document states.
        #expect(cardio.kcal == 480)
        #expect(cardio.kinds == ["run", "walk"])
    }

    @Test("the body figures come from the week's last believed scan")
    func bodyComesFromTheScan() throws {
        let (report, _) = try built()
        #expect(report.scanDate == "2026-08-25")
        #expect(report.bodyFatPct == 17.2)
        /* 82.4 kg × 44.7 % = 36.83 kg of lean soft tissue, DERIVED — the scan
           stores the percentage and not the mass, and the export completes it
           now rather than falling through to `skeletalMuscleMassKg`.

           This read 36.8 and that was the SKELETAL muscle mass standing in for
           the lean one. The two are different compartments (`Composition.swift`
           says so in capitals) and they agree to a tenth in this seed by
           coincidence. The fallback is still there for a scan with no muscle
           percentage at all; this scan has one. */
        #expect(report.muscleMassKg == 36.83)
    }

    // MARK: - Records

    @Test("records are by exercise, capped at three, and the rest are still carried")
    func recordsAreCappedAndSorted() throws {
        let (report, _) = try built()
        #expect(report.records.count == 4)
        #expect(report.records.map(\.name) == report.records.map(\.name).sorted())
        #expect(report.topRecords.count == WeekReport.recordCap)
        #expect(report.hasMoreRecords)
        // The disclosure has something to disclose: the cap hides, it does not
        // discard.
        #expect(report.records.dropFirst(WeekReport.recordCap).count == 1)
    }

    @Test("three records is the whole list and there is no disclosure")
    func threeRecordsIsNotMore() {
        var report = WeekReport(rangeLabel: "x", sessions: 0, plannedSessions: 0, tonnageKg: 0, prCount: 0)
        report.records = (0..<3).map {
            ExportPr(name: "m\($0)", weightKg: 10, reps: 5, axes: [.weight])
        }
        #expect(report.topRecords.count == 3)
        #expect(!report.hasMoreRecords)
    }

    // MARK: - The harness's empty user

    /// Cross-wave law 16. `AppEnvironment.userIdString` is `""` in the shot
    /// harness and in previews, and an export built for "" comes back with
    /// seven empty days — a page that says "no day was graded" over a store
    /// holding a full week.
    @Test("an empty user id falls back to the store's own user")
    func emptyUserIdFallsBack() throws {
        let (fallback, _) = try built(userId: "")
        let (real, _) = try built()
        #expect(fallback == real)
        #expect(fallback.sleepScoreAvg != nil)
        #expect(!fallback.records.isEmpty)
    }
}
