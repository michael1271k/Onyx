import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// The export gate, variant B: `weekly-export.json`'s rich case is a hand-made
/// renderer fixture (an exercise with a top load and no sets, a rest target
/// that differs from its plan, "Onyx-5" as a programme label) and cannot be
/// seeded back into tables. So this seeds ONE week of real rows and asserts the
/// builder's `WeeklyExportInput` equals a hand-written one; string equality then
/// follows from OnyxCore's own vector test over `WeeklyExport.build`.
@Suite("Weekly export builder")
struct WeeklyExportBuilderTests {
    private let user = "u1"
    private let weekStart = "2026-08-23"

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    private func seeded() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let t = iso("2026-08-23T00:00:00Z")
        try db.writer.write { conn in
            try UserGoalRow(
                id: "g1", userId: user, sleepGoalHours: 8, calorieGoal: 1999, proteinGoalG: 170, carbsGoalG: 206,
                fatGoalG: 55, stepsGoal: 10_000, waterGoalMl: 3000, contextMode: "normal", createdAt: t, updatedAt: t,
                autoLogSupplements: false, activeProgram: "onyx5", dayCutoffHour: 4, unitSystem: "metric",
                reduceMotion: false, timezone: "UTC", activePlan: "onyx5", activePhase: "cut", trackRpe: true,
                activeLever: "custom"
            ).insert(conn)
            // Thursday (cb_b) swapped to rest.
            try ScheduleOverrideRow(userId: user, date: "2026-08-27", dayKey: "rest", updatedAt: t).insert(conn)
            try PlanPhaseVolumeRow(userId: user, planId: "onyx5", phase: "cut", muscle: "Quads", targetSets: 12).insert(conn)

            try Exercise(id: "ex-lp", name: "Leg Press").insert(conn)
            try SampleDeck.seedCatalogue(conn, userId: user)
            try Exercise(id: "ex-rc", name: "Reverse Crunch").insert(conn)
            try Exercise(id: "ex-lr", name: "Single Arm Lateral Raise (Cable)").insert(conn)

            // A session the week before — the ordinal's base and a ledger row.
            try WorkoutSession(id: "s0", userId: user, dayKey: "legs_a", date: "2026-08-18", startedAt: iso("2026-08-18T09:00:00Z")).insert(conn)
            try WorkoutSet(id: "z1", sessionId: "s0", exerciseId: "ex-lp", setIndex: 0, weightKg: 70, reps: 12).insert(conn)

            try WorkoutSession(id: "s1", userId: user, dayKey: "legs_a", date: "2026-08-24",
                               startedAt: iso("2026-08-24T09:02:00Z"), endedAt: iso("2026-08-24T10:20:00Z"),
                               durationMin: 78, sessionRpe: 8.5).insert(conn)
            try WorkoutSet(id: "a1", sessionId: "s1", exerciseId: "ex-lp", setIndex: 0, weightKg: 40, reps: 15, setType: "warmup").insert(conn)
            try WorkoutSet(id: "a2", sessionId: "s1", exerciseId: "ex-lp", setIndex: 1, weightKg: 75, reps: 12, rpe: 8.5).insert(conn)
            try WorkoutSet(id: "a3", sessionId: "s1", exerciseId: "ex-lp", setIndex: 2, weightKg: 75, reps: 12, rpe: 9.5).insert(conn)
            try WorkoutSet(id: "a4", sessionId: "s1", exerciseId: "ex-lp", setIndex: 3, weightKg: 75, reps: 10, setType: "failure", rpe: 10).insert(conn)
            // A stored 0 on unloaded work is a legacy artefact, not an estimate.
            try WorkoutSet(id: "a5", sessionId: "s1", exerciseId: "ex-rc", setIndex: 4, weightKg: 0, reps: 17, est1rmKg: 0, rpe: 8).insert(conn)
            try WorkoutSet(id: "a6", sessionId: "s1", exerciseId: "ex-rc", setIndex: 5, weightKg: 0, reps: 15).insert(conn)
            for (axis, value, reps, kg, key) in [("weight", 75.0, 12, 75.0, "Leg Press"), ("e1rm", 105.0, 12, 75.0, "Leg Press"), ("reps", 17.0, 17, 0.0, "Reverse Crunch")] {
                try PersonalRecordRow(userId: user, exerciseKey: key, axis: axis, value: value, reps: reps, weightKg: kg,
                                      sessionId: "s1", achievedOn: "2026-08-24").insert(conn)
            }

            try WorkoutSession(id: "s2", userId: user, dayKey: "arms", date: "2026-08-25",
                               startedAt: iso("2026-08-25T18:00:00Z"), durationMin: 55).insert(conn)
            let lr: [(String, Double, Int, String, String, String?, Double?)] = [
                ("b1", 5, 15, "left", "p1", nil, 8), ("b2", 5, 17, "right", "p1", nil, 9),
                ("b3", 5, 14, "left", "p2", "failure", nil), ("b4", 5, 16, "right", "p2", nil, nil),
                ("b5", 5, 14, "left", "p3", "ghost", nil), ("b6", 5, 14, "right", "p3", "ghost", nil),
            ]
            for (i, (id, kg, reps, side, pair, type, rpe)) in lr.enumerated() {
                try WorkoutSet(id: id, sessionId: "s2", exerciseId: "ex-lr", setIndex: i, weightKg: kg, reps: reps,
                               setType: type ?? "normal", side: side, pairId: pair, rpe: rpe).insert(conn)
            }

            try DailyLogRow(id: "d1", userId: user, date: "2026-08-23", steps: 8000, waterMl: 1234, sleepMinutes: 480,
                            weightKg: 65, bmi: 21.5, activeEnergy: 400, bodyFatPct: 17, standingMinutes: 55,
                            avgHeartRate: 70, avgRestHeartRate: 52, respiratoryRate: 14.5, bloodOxygen: 97, bmr: 1500,
                            createdAt: t, updatedAt: t, hrvMs: 60, exerciseMinutes: 30, standHours: 12, vo2max: 46.1,
                            wristTempDelta: 0.2, timeInDaylightMin: 40, distanceM: 6000, muscleMassKg: 50.1,
                            skeletalMuscleMassKg: 26.8, estimatedWaistToHipRatio: 0.85,
                            nutritionEstimated: false, sleepOnsetTrouble: false).insert(conn)
            try DailyLogRow(id: "d2", userId: user, date: "2026-08-24", steps: 11_000, sleepMinutes: 470,
                            createdAt: t, updatedAt: t, weighinSkipReason: "Sick", nutritionException: "Illness",
                            nutritionEstimated: false, sleepOnsetTrouble: true).insert(conn)
            try DailyLogRow(id: "d3", userId: user, date: "2026-08-25", steps: 8000, waterMl: 2400, weightKg: 64,
                            createdAt: t, updatedAt: t, nutritionEstimated: true, sleepOnsetTrouble: false).insert(conn)

            try NutritionEntryRow(id: "n1", userId: user, loggedAt: t, date: "2026-08-23", mealType: "daily",
                                  calories: 2000, proteinG: 170, carbsG: 206, fatG: 55, fiberG: 30, createdAt: t,
                                  micros: JSONText(raw: #"{"sodium":2400,"vitaminC":80}"#)).insert(conn)
            try NutritionEntryRow(id: "n2", userId: user, loggedAt: t, date: "2026-08-24", mealType: "daily",
                                  calories: 1800, proteinG: 150, carbsG: 200, fatG: 45, createdAt: t).insert(conn)
            // A meal row: not the day's total, never read.
            try NutritionEntryRow(id: "n3", userId: user, loggedAt: t, date: "2026-08-25", mealType: "breakfast",
                                  calories: 500, proteinG: 30, carbsG: 50, fatG: 20, createdAt: t).insert(conn)
            try WaterIntakeRow(id: "w1", userId: user, loggedAt: t, date: "2026-08-23", amountMl: 500, createdAt: t).insert(conn)
            try WaterIntakeRow(id: "w2", userId: user, loggedAt: t, date: "2026-08-23", amountMl: 1500, createdAt: t).insert(conn)
            try WaterIntakeRow(id: "w3", userId: user, loggedAt: t, date: "2026-08-24", amountMl: 1000, createdAt: t).insert(conn)

            try CustomSupplementRow(id: "c1", userId: user, name: "Creatine Monohydrate", dose: "5 g", time: "15:00",
                                    schedule: JSONText(raw: #"{"key":"creatine","slot":"Lunch"}"#),
                                    micros: JSONText(raw: #"{"creatine":5000}"#), createdAt: iso("2026-08-01T00:00:00Z"), sortOrder: 0).insert(conn)
            try CustomSupplementRow(id: "c2", userId: user, name: "Caffeine", dose: "200 mg", time: "11:45",
                                    schedule: JSONText(raw: #"{"key":"caffeine","trainingOnly":true}"#),
                                    createdAt: iso("2026-08-02T00:00:00Z"), sortOrder: 0).insert(conn)
            try CustomSupplementRow(id: "c3", userId: user, name: "Omega-3", dose: "2 caps", time: "15:00",
                                    schedule: JSONText(raw: #"{"key":"omega3","days":[0,1]}"#),
                                    createdAt: iso("2026-08-03T00:00:00Z"), sortOrder: 0).insert(conn)
            try SupplementLogRow(userId: user, date: "2026-08-24", itemKey: "caffeine", taken: false, updatedAt: t).insert(conn)
            try SupplementLogRow(userId: user, date: "2026-08-23", itemKey: "creatine", taken: true, updatedAt: t).insert(conn)

            try DomsLogRow(id: "dm1", userId: user, date: "2026-08-25", muscleGroup: "quads", severity: 3, createdAt: t,
                           sourceSessionId: "s1", sourceDayKey: "legs_a").insert(conn)
            try DomsLogRow(id: "dm2", userId: user, date: "2026-08-25", muscleGroup: "glutes", severity: 2, createdAt: t.addingTimeInterval(1)).insert(conn)
            try FatigueLogRow(id: "f1", userId: user, date: "2026-08-24", slot: "pre", level: 2, createdAt: t).insert(conn)
            try FatigueLogRow(id: "f2", userId: user, date: "2026-08-24", slot: "waking", level: 3, createdAt: t.addingTimeInterval(1)).insert(conn)
            try FatigueLogRow(id: "f3", userId: user, date: "2026-08-24", slot: "bogus", level: 5, createdAt: t.addingTimeInterval(2)).insert(conn)
            try FatigueLogRow(id: "f4", userId: user, date: "2026-08-26", slot: "midday", level: 4, createdAt: t).insert(conn)
            // The HEAD row. Two readings on one day, out of clock order and
            // with a tag the vocabulary does not know — the export has to sort
            // them into the order the day happens in and drop the unknown tag.
            try StressLogRow(id: "st1", userId: user, date: "2026-08-24", slot: "evening", level: 4,
                             tags: JSONText(raw: "[\"work\",\"nonsense\"]"), note: "deadline; again",
                             createdAt: t, updatedAt: t).insert(conn)
            try StressLogRow(id: "st2", userId: user, date: "2026-08-24", slot: "morning", level: 2,
                             tags: JSONText(raw: "[]"), note: nil,
                             createdAt: t.addingTimeInterval(1), updatedAt: t).insert(conn)

            try BodyCompositionRow(id: "bc1", userId: user, measuredAt: t, date: "2026-08-25", weightKg: 64, bodyFatPct: 16.8,
                                   waterPct: 58.6, boneMassKg: 2.7, bmi: 21.4, createdAt: t, fatMassKg: 10.9,
                                   bodyWaterMassKg: 38, musclePct: 40, proteinPct: 18, boneMineralPct: 4.1,
                                   skeletalMuscleMassKg: 26.9).insert(conn)
            // Two bouts, one of each provenance — the pair that pins the
            // `created_at` double meaning the export has to carry. `cl1` was
            // typed, so its stamp is the moment of typing; `cl2` came from
            // Health, so its stamp IS the bout's start and the export may say so.
            try CardioLogRow(id: "cl1", userId: user, date: "2026-08-26", kind: "walk", distanceM: 5000, durationMin: 50, kcal: 250, createdAt: t).insert(conn)
            try CardioLogRow(id: "cl2", userId: user, date: "2026-08-29", kind: "run", distanceM: 3000, durationMin: 18, kcal: 200,
                             fromHealthkit: true, createdAt: iso("2026-08-29T06:12:00Z"),
                             activeKcal: 200, totalKcal: 230, avgHr: 150, effort: 7, elevationM: 120).insert(conn)
            try SleepSessionRow(id: "sl1", userId: user, startTime: iso("2026-08-22T22:30:00Z"), endTime: iso("2026-08-23T06:30:00Z"),
                                durationMin: 480, deepMin: 60, remMin: 100, coreMin: 300, awakeMin: 20, createdAt: t).insert(conn)
            try SleepSessionRow(id: "sl2", userId: user, startTime: iso("2026-08-24T00:15:00Z"), endTime: iso("2026-08-24T07:00:00Z"),
                                durationMin: 405, deepMin: 40, remMin: 90, coreMin: 280, awakeMin: 10, createdAt: t).insert(conn)
            try DailyTargetRow(userId: user, date: "2026-08-27", kcal: 2400, updatedAt: t, profileKey: "restaurant",
                               trackCarbs: false, trackFat: false).insert(conn)
            // The battery the app showed on the Monday — v8's Derived block reads it.
            var score = DailyScoreRow(id: "sc1", userId: user, date: "2026-08-24", score: 70, computedAt: t, finalized: true)
            score.batteryPct = 41
            try score.insert(conn)
        }
        return db
    }

    @Test func assemblesTheHandWrittenInput() throws {
        let db = try seeded()
        // UTC EXPLICITLY. The builder now defaults to the phone's own zone —
        // a document about a day should be in the clock that day happened on —
        // and this fixture's timestamps are written in UTC, so the assertion
        // pins the zone rather than the machine that runs the suite.
        let got = try WeeklyExportBuilder(database: db, userId: user, timeZone: TimeZone(identifier: "UTC")!)
            .input(weekStart: weekStart, today: weekStart)
        let want = try JSONDecoder().decode(WeeklyExportInput.self, from: Data(Self.expected.utf8))

        // Section by section first, so a miss names its section.
        #expect(got.weekLabel == want.weekLabel)
        #expect(got.programLabel == want.programLabel)
        #expect(got.targetPeriods == want.targetPeriods)
        // Readiness v9's per-day signals are asserted on their own below — the
        // hand-written payload predates them, and a 49-day EWMA is not a thing
        // to write out by hand seven times.
        func withoutReadiness(_ d: ExportDay) -> ExportDay {
            var x = d; x.readiness = nil; x.hrvFlag = nil; return x
        }
        for (g, w) in zip(got.days, want.days) { #expect(withoutReadiness(g) == w, "day \(w.date)") }
        #expect(got.days.count == want.days.count)
        /* ── v5's FIELDS ARE ASSERTED BY NAME, NOT WRITTEN INTO THE FIXTURE ──
           `prescription`, `previous` and `compound` are read out of the PLAN
           and out of every session before this one, and `anomaly`/`hrvFlag` out
           of a fortnight and six weeks of history. Writing them into the
           hand-written payload would be copying what the code produced, which
           is a snapshot and not a specification. They are stripped here and
           each is asserted below against a figure worked out by hand — the same
           bargain `withoutReadiness` already struck for Readiness v9. */
        func withoutV5(_ e: ExportExercise) -> ExportExercise {
            var x = e; x.compound = nil; x.prescription = nil; x.previous = nil; return x
        }
        func withoutV5(_ s: ExportSession) -> ExportSession {
            var x = s; x.exercises = s.exercises.map(withoutV5); return x
        }
        var gotStripped = got
        gotStripped.days = got.days.map(withoutReadiness)
        gotStripped.sessions = got.sessions.map(withoutV5)
        gotStripped.bodyComp = got.bodyComp?.map { var x = $0; x.anomaly = nil; return x }
        gotStripped.leverBaselineKcal = nil
        gotStripped.anomalies = nil
        #expect(got.sessions.map(withoutV5) == want.sessions)
        #expect(got.volumeByMuscle == want.volumeByMuscle)
        #expect(got.tonnageByMuscle == want.tonnageByMuscle)
        #expect(got.doms == want.doms)
        #expect(got.fatigue == want.fatigue)
        #expect(got.stress == want.stress)
        #expect(got.bodyComp == want.bodyComp)
        #expect(got.cardio == want.cardio)
        #expect(got.supplementProtocol == want.supplementProtocol)
        #expect(got.ledger == want.ledger)
        #expect(gotStripped == want)

        // ── v5, FIELD BY FIELD ──
        // The anchor is forced: `active_lever` is "custom" in this seed, so the
        // ladder has no rung to name a baseline with.
        #expect(got.leverBaselineKcal == WeeklyExport.leverBaselineKcal)
        // Nothing to correct: no duplicate bout, and every night with a sleep
        // reading had one in `daily_logs` already.
        #expect(got.anomalies == [])
        // One HRV reading in the whole seed. `VitalsGate` needs seven nights
        // before it has an opinion, so it declines to have one.
        #expect(got.days.allSatisfy { $0.hrvFlag == nil })
        // One scan, so the fortnight's median IS that scan and nothing can
        // deviate from itself.
        #expect((got.bodyComp ?? []).allSatisfy { $0.anomaly == nil })

        let legPress = try #require(got.sessions.first?.exercises.first { $0.name == "Leg Press" })
        // Onyx-5's `legs_a` row, at the CUT set count.
        #expect(legPress.prescription?.sets == 3)
        #expect(legPress.prescription?.reps == "8–12")
        #expect(legPress.prescription?.loadKg == 70)
        #expect(legPress.compound == true)
        // s0, the week before — 70 kg × 12, the only prior Leg Press there is.
        #expect(legPress.previous?.date == "2026-08-18")
        #expect(legPress.previous?.weightKg == 70)
        #expect(legPress.previous?.reps == 12)
        // Reverse Crunch is in the deck but was never performed before.
        #expect(got.sessions.first?.exercises.first { $0.name == "Reverse Crunch" }?.previous == nil)
        // a4 is the one set rated 10; a2 and a3 at 8.5 and 9.5 are not failures.
        #expect(got.sessions.first?.failureSets == 1)
        // No `set_events` in this seed, and `ex-rc` carries no `exercise_order`.
        #expect(got.sessions.allSatisfy { $0.orderSource == "logged" })

        // ── READINESS v9 on the days ──
        // Every day carries the signals; with six weeks of history absent the
        // z-signals have no opinion (nil, never a number), and the loads are
        // the seeded sessions': s1 on the 24th is RPE 8.5 × 78 min = 663.
        let byDate = Dictionary(uniqueKeysWithValues: got.days.map { ($0.date, $0.readiness) })
        for day in got.days { #expect(day.readiness != nil, "readiness \(day.date)") }
        #expect(byDate["2026-08-23"]??.hrvZ == nil)
        #expect(byDate["2026-08-23"]??.rhrZ == nil)
        #expect(byDate["2026-08-23"]??.load == 0)
        #expect(byDate["2026-08-24"]??.load == 663)
        // A first real session against a chronic side built on nothing is NOT
        // a spike — the ratio has no opinion until three loaded days precede
        // the rolling week (`minLoadDays`).
        #expect(byDate["2026-08-24"]??.acwr == nil)
        #expect((byDate["2026-08-24"]??.acute ?? 0) > 0)
        // And the builder's series IS the scorer's series.
        let viaScorer = try db.read { conn in
            ExportReadiness(signals: Readiness.signals(try AppDatabase.readinessHistory(conn, userId: user, date: "2026-08-24")))
        }
        #expect(byDate["2026-08-24"]! == viaScorer)

        let markdown = WeeklyExport.build(got)
        #expect(markdown.contains("Legs & Core A"))
        // v5 opens on §1 and closes on §7. There is no title, no legend and no
        // closing notes: the document is seven sections of data and nothing else.
        #expect(markdown.hasPrefix("## 1 \u{00B7} WEEK\nweek_id Week 6 \u{00B7} 2026-08-23 \u{2192} 2026-08-29 \u{00B7} phase Cut"))
        #expect(markdown.contains("\n## 7 \u{00B7} ANOMALIES\n"))
        // The forced anchor — the ladder has no rungs to answer with.
        #expect(markdown.contains("baseline 1,935 kcal"))
    }

    /// The whole payload, by hand — every field the web's `weekPayload` would
    /// have produced for the rows above.
    static let expected = #"""
    {
      "weekStart": "2026-08-23", "weekEnd": "2026-08-29", "weekLabel": "Week 6",
      "programLabel": "Onyx-5 Cut", "phaseLabel": "Cut",
      "calorieGoal": 1999, "proteinGoalG": 170, "stepsGoal": 10000, "sleepGoalHours": 8, "waterGoalMl": 3000,
      "targetPeriods": [
        {"leverId": null, "label": "Custom", "goals": {"calorie": 1999, "protein": 170, "carbs": 206, "fat": 55, "steps": 10000},
         "dates": ["2026-08-23", "2026-08-24", "2026-08-25", "2026-08-26"]},
        {"leverId": null, "label": "Custom", "goals": {"calorie": 2400, "protein": 170, "steps": 10000}, "dates": ["2026-08-27"]},
        {"leverId": null, "label": "Custom", "goals": {"calorie": 1999, "protein": 170, "carbs": 206, "fat": 55, "steps": 10000},
         "dates": ["2026-08-28", "2026-08-29"]}
      ],
      "days": [
        {"date": "2026-08-23", "weekdayLabel": "Sun", "isTrainingDay": true,
         "weightKg": 65, "calories": 2000, "proteinG": 170, "carbsG": 206, "fatG": 55, "steps": 8000, "distanceM": 6000,
         "sleepMin": 480, "deepMin": 60, "remMin": 100, "restingHr": 52, "hrvMs": 60, "wristTempDeltaC": 0.2, "bloodOxygenPct": 97,
         "avgHr": 70, "respiratoryRate": 14.5, "vo2max": 46.1, "daylightMin": 40, "exerciseMin": 30, "standHours": 12, "standMin": 55,
         "coreMin": 300, "awakeMin": 20, "bedTime": "2026-08-22T22:30:00Z", "wakeTime": "2026-08-23T06:30:00Z", 
         "waterMl": 2000, "supplementsTaken": 3, "supplementsPlanned": 3,
         "supplementsLog": [{"key": "caffeine", "time": "11:45"}, {"key": "creatine", "time": "15:00"}, {"key": "omega3", "time": "15:00"}],
         "supplementsSkipped": [], "supplementsSkippedUnplanned": [], "supplementsLater": [],
         "nutrientsFood": {"sodium": 2400, "vitaminC": 80, "fiber": 30, "protein": 170},
         "nutrientsStack": {"caffeine": 200, "creatine": 5000, "epa": 1000, "dha": 500},
         "activeKcal": 400, "bmrKcal": 1500, "nutritionEstimated": false, "trackCarbs": true, "trackFat": true},
        {"date": "2026-08-24", "weekdayLabel": "Mon", "isTrainingDay": true,
         "calories": 1800, "proteinG": 150, "carbsG": 200, "fatG": 45, "steps": 11000, "sleepMin": 470, "deepMin": 40, "remMin": 90,
         "coreMin": 280, "awakeMin": 10, "bedTime": "2026-08-24T00:15:00Z", "wakeTime": "2026-08-24T07:00:00Z", "sleepOnsetTrouble": true, "restingHrBaseline": 52, "hrvBaseline": 60, "batteryPct": 41,
         "waterMl": 1000, "supplementsTaken": 2, "supplementsPlanned": 3,
         "supplementsLog": [{"key": "creatine", "time": "15:00"}, {"key": "omega3", "time": "15:00"}],
         "supplementsSkipped": ["Caffeine"], "supplementsSkippedUnplanned": [], "supplementsLater": [],
         "nutrientsFood": {"protein": 150}, "nutrientsStack": {"creatine": 5000, "epa": 1000, "dha": 500},
         "weighInSkipReason": "Sick", "nutritionException": "Illness", "nutritionEstimated": false, "trackCarbs": true, "trackFat": true},
        {"date": "2026-08-25", "weekdayLabel": "Tue", "isTrainingDay": true,
         "weightKg": 64, "steps": 8000, "restingHrBaseline": 52, "hrvBaseline": 60, "waterMl": 2400, "supplementsTaken": 2, "supplementsPlanned": 2,
         "supplementsLog": [{"key": "caffeine", "time": "11:45"}, {"key": "creatine", "time": "15:00"}], "supplementsSkipped": [], "supplementsSkippedUnplanned": [], "supplementsLater": [],
         "nutrientsFood": {}, "nutrientsStack": {"caffeine": 200, "creatine": 5000},
         "nutritionEstimated": true, "trackCarbs": true, "trackFat": true},
        {"date": "2026-08-26", "weekdayLabel": "Wed", "isTrainingDay": false,
         "restingHrBaseline": 52, "hrvBaseline": 60, "supplementsTaken": 1, "supplementsPlanned": 1,
         "supplementsLog": [{"key": "creatine", "time": "15:00"}], "supplementsSkipped": [], "supplementsSkippedUnplanned": [], "supplementsLater": [],
         "nutrientsFood": {}, "nutrientsStack": {"creatine": 5000}, "nutritionEstimated": false, "trackCarbs": true, "trackFat": true},
        {"date": "2026-08-27", "weekdayLabel": "Thu", "isTrainingDay": false,
         "restingHrBaseline": 52, "hrvBaseline": 60, "supplementsTaken": 1, "supplementsPlanned": 1,
         "supplementsLog": [{"key": "creatine", "time": "15:00"}], "supplementsSkipped": [], "supplementsSkippedUnplanned": [], "supplementsLater": [],
         "nutrientsFood": {}, "nutrientsStack": {"creatine": 5000}, "nutritionEstimated": false,
         "targetProfile": "Restaurant", "trackCarbs": false, "trackFat": false},
        {"date": "2026-08-28", "weekdayLabel": "Fri", "isTrainingDay": true,
         "restingHrBaseline": 52, "hrvBaseline": 60, "supplementsTaken": 2, "supplementsPlanned": 2,
         "supplementsLog": [{"key": "caffeine", "time": "11:45"}, {"key": "creatine", "time": "15:00"}], "supplementsSkipped": [], "supplementsSkippedUnplanned": [], "supplementsLater": [],
         "nutrientsFood": {}, "nutrientsStack": {"caffeine": 200, "creatine": 5000}, "nutritionEstimated": false, "trackCarbs": true, "trackFat": true},
        {"date": "2026-08-29", "weekdayLabel": "Sat", "isTrainingDay": false,
         "restingHrBaseline": 52, "hrvBaseline": 60, "supplementsTaken": 1, "supplementsPlanned": 1,
         "supplementsLog": [{"key": "creatine", "time": "15:00"}], "supplementsSkipped": [], "supplementsSkippedUnplanned": [], "supplementsLater": [],
         "nutrientsFood": {}, "nutrientsStack": {"creatine": 5000}, "nutritionEstimated": false, "trackCarbs": true, "trackFat": true}
      ],
      "sessions": [
        {"date": "2026-08-24", "startedAt": "2026-08-24T09:02:00Z", "endedAt": "2026-08-24T10:20:00Z", "sessionNumber": 2,
         "label": "Legs & Core A", "volumeKg": 3150, "setCount": 6, "failureSets": 1, "durationMin": 78,
         "caloriesEstimated": false, "avgBpmEstimated": false, "sessionRpe": 8.5, "orderSource": "logged",
         "exercises": [
           {"name": "Leg Press", "restTargetSec": 135, "restPlanSec": 135, "topKg": 75, "repWindow": "8–12",
            "primaryMuscles": ["Quads"], "secondaryMuscles": ["Glutes", "Hamstrings"], "sets": [
             {"weightKg": 40, "reps": 15, "failure": false, "warmup": true, "ghost": false, "dropset": false},
             {"weightKg": 75, "reps": 12, "rpe": 8.5, "failure": false, "warmup": false, "ghost": false, "dropset": false},
             {"weightKg": 75, "reps": 12, "rpe": 9.5, "failure": false, "warmup": false, "ghost": false, "dropset": false},
             {"weightKg": 75, "reps": 10, "rpe": 10, "failure": true, "warmup": false, "ghost": false, "dropset": false}]},
           {"name": "Reverse Crunch", "restTargetSec": 75, "restPlanSec": 75, "repWindow": "12–15",
            "primaryMuscles": ["Abs/core"], "secondaryMuscles": [], "sets": [
             {"weightKg": 0, "reps": 17, "rpe": 8, "failure": false, "warmup": false, "ghost": false, "dropset": false},
             {"weightKg": 0, "reps": 15, "failure": false, "warmup": false, "ghost": false, "dropset": false}]}
         ],
         "prs": [
           {"name": "Leg Press", "weightKg": 75, "reps": 12, "axes": ["weight", "e1rm"], "volumeKg": 900, "e1rmKg": 108},
           {"name": "Reverse Crunch", "weightKg": 0, "reps": 17, "axes": ["reps"], "volumeKg": 0}
         ]},
        {"date": "2026-08-25", "startedAt": "2026-08-25T18:00:00Z", "sessionNumber": 3,
         "label": "Delts & Arms", "volumeKg": 145, "setCount": 2, "failureSets": 1, "durationMin": 55,
         "caloriesEstimated": false, "avgBpmEstimated": false, "orderSource": "logged",
         "exercises": [
           {"name": "Single Arm Lateral Raise (Cable)", "restTargetSec": 105, "restPlanSec": 105, "topKg": 5, "repWindow": "12–20",
            "primaryMuscles": ["Side delts"], "secondaryMuscles": [], "sets": [
             {"weightKg": 5, "reps": 15, "rpe": 8, "side": "L", "pairId": "p1", "failure": false, "warmup": false, "ghost": false, "dropset": false},
             {"weightKg": 5, "reps": 17, "rpe": 9, "side": "R", "pairId": "p1", "failure": false, "warmup": false, "ghost": false, "dropset": false},
             {"weightKg": 5, "reps": 14, "side": "L", "pairId": "p2", "failure": true, "warmup": false, "ghost": false, "dropset": false},
             {"weightKg": 5, "reps": 16, "side": "R", "pairId": "p2", "failure": false, "warmup": false, "ghost": false, "dropset": false},
             {"weightKg": 5, "reps": 14, "side": "L", "pairId": "p3", "failure": false, "warmup": false, "ghost": true, "dropset": false},
             {"weightKg": 5, "reps": 14, "side": "R", "pairId": "p3", "failure": false, "warmup": false, "ghost": true, "dropset": false}]}
         ],
         "prs": []}
      ],
      "volumeByMuscle": [
        {"muscle": "Chest", "sets": 0, "target": 11, "directSets": 0, "indirectSets": 0},
        {"muscle": "Lats", "sets": 0, "target": 6, "directSets": 0, "indirectSets": 0},
        {"muscle": "Upper back", "sets": 0, "target": 4, "directSets": 0, "indirectSets": 0},
        {"muscle": "Lower back", "sets": 0, "target": 1, "directSets": 0, "indirectSets": 0},
        {"muscle": "Front delts", "sets": 0, "target": 4, "directSets": 0, "indirectSets": 0},
        {"muscle": "Side delts", "sets": 3, "target": 7, "directSets": 3, "indirectSets": 0},
        {"muscle": "Rear delts", "sets": 0, "target": 2, "directSets": 0, "indirectSets": 0},
        {"muscle": "Biceps", "sets": 0, "target": 8, "directSets": 0, "indirectSets": 0},
        {"muscle": "Triceps", "sets": 0, "target": 6, "directSets": 0, "indirectSets": 0},
        {"muscle": "Forearms", "sets": 0, "target": 4, "directSets": 0, "indirectSets": 0},
        {"muscle": "Quads", "sets": 4, "target": 12, "directSets": 4, "indirectSets": 0},
        {"muscle": "Hamstrings", "sets": 2, "target": 8, "directSets": 0, "indirectSets": 2},
        {"muscle": "Glutes", "sets": 2, "target": 6, "directSets": 0, "indirectSets": 2},
        {"muscle": "Adductors", "sets": 0, "target": 0, "directSets": 0, "indirectSets": 0},
        {"muscle": "Calves", "sets": 0, "target": 6, "directSets": 0, "indirectSets": 0},
        {"muscle": "Abs/core", "sets": 2, "target": 10, "directSets": 2, "indirectSets": 0}
      ],
      "tonnageByMuscle": [
        {"muscle": "Quads", "volumeKg": 3150}, {"muscle": "Hamstrings", "volumeKg": 1575},
        {"muscle": "Glutes", "volumeKg": 1575}, {"muscle": "Side delts", "volumeKg": 145}
      ],
      "doms": [
        {"date": "2026-08-25", "muscle": "glutes", "severity": 2},
        {"date": "2026-08-25", "muscle": "quads", "severity": 3, "sourceLabel": "Legs & Core A", "sourceDate": "2026-08-24"}
      ],
      "fatigue": [
        {"date": "2026-08-24", "slot": "Waking", "level": 3, "label": "Okay"},
        {"date": "2026-08-24", "slot": "Before training", "level": 2, "label": "Good"},
        {"date": "2026-08-26", "slot": "Midday", "level": 4, "label": "Tired"}
      ],
      "bodyComp": [
        {"date": "2026-08-23", "weightKg": 65, "bmi": 21.5, "bodyFatPct": 17, "bmr": 1500, "muscleMassKg": 50.1,
         "skeletalMuscleMassKg": 26.8, "estimatedWaistToHipRatio": 0.85},
        {"date": "2026-08-25", "weightKg": 64, "bmi": 21.4, "bodyFatPct": 16.8, "musclePercent": 40, "waterPercent": 58.6,
         "boneMineral": 4.1, "fatMassKg": 10.9, "proteinPercent": 18, "boneMineralKg": 2.7, "waterMassKg": 38, "skeletalMuscleMassKg": 26.9}
      ],
      "cardio": [
        {"date": "2026-08-26", "kind": "walk", "distanceM": 5000, "durationMin": 50, "kcal": 250,
         "startedAt": "2026-08-23T00:00:00Z", "source": "manual"},
        {"date": "2026-08-29", "kind": "run", "distanceM": 3000, "durationMin": 18, "kcal": 200, "totalKcal": 230, "avgHr": 150, "effort": 7,
         "startedAt": "2026-08-29T06:12:00Z", "elevationM": 120, "source": "health"}
      ],
      "stress": [
        {"date": "2026-08-24", "slot": "morning", "level": 2, "label": "Okay", "tags": []},
        {"date": "2026-08-24", "slot": "evening", "level": 4, "label": "Strained", "tags": ["work"], "note": "deadline; again"}
      ],
      "supplementProtocol": [
        {"time": "15:00", "key": "creatine", "name": "Creatine Monohydrate", "dose": "5 g"},
        {"time": "11:45", "key": "caffeine", "name": "Caffeine", "dose": "200 mg", "trainingOnly": true},
        {"time": "15:00", "key": "omega3", "name": "Omega-3", "dose": "2 caps"}
      ],
      "ledger": [
        {"label": "Week 0", "weekStart": "2026-07-12", "totals": {}},
        {"label": "Week 1", "weekStart": "2026-07-19", "totals": {}},
        {"label": "Week 2", "weekStart": "2026-07-26", "totals": {}},
        {"label": "Week 3", "weekStart": "2026-08-02", "totals": {}},
        {"label": "Week 4", "weekStart": "2026-08-09", "totals": {}},
        {"label": "Week 5", "weekStart": "2026-08-16", "totals": {"totalVolumeKg": 840}},
        {"label": "Week 6", "weekStart": "2026-08-23", "totals": {"avgKcal": 1900, "totalVolumeKg": 3295, "avgSteps": 9000,
         "cardioMinutes": 68, "avgWaterMl": 1800, "avgWeightKg": 64.5}}
      ]
    }
    """#
}

/// The four data defects v5 fixed in the BUILDER, each on rows that reproduce
/// it. None of them was ever a renderer bug: the document printed what it was
/// handed, and what it was handed was a UTC clock, a duplicated bout, a
/// treadmill with its measurement dropped by the SELECT, and a session span
/// taken from when the screen opened.
@Suite("Weekly export builder — v5")
struct WeeklyExportBuilderV5Tests {
    private let user = "u1"
    private let weekStart = "2026-08-23"

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    /// One `set_events` row. Written as SQL because the fold's `body` is a blob
    /// this query never opens — only `kind` and `created_at` matter here.
    private func event(_ db: Database, id: String, session: String, set: String, seq: Int, at: String) throws {
        try db.execute(
            sql: """
                INSERT INTO set_events (id, session_id, set_id, device_id, seq, kind, body, created_at, is_synced)
                VALUES (?, ?, ?, 'device-a', ?, 'append', X'7B7D', ?, 0)
                """,
            arguments: [id, session, set, seq, iso(at)])
    }

    private func seeded() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let t = iso("2026-08-23T00:00:00Z")
        try db.writer.write { conn in
            try UserGoalRow(
                id: "g1", userId: user, calorieGoal: 1999, proteinGoalG: 170, stepsGoal: 10_000,
                contextMode: "normal", createdAt: t, updatedAt: t, autoLogSupplements: false,
                activeProgram: "onyx5", dayCutoffHour: 4, unitSystem: "metric", reduceMotion: false,
                timezone: "UTC", activePlan: "onyx5", activePhase: "cut", trackRpe: true, activeLever: "custom"
            ).insert(conn)
            try Exercise(id: "ex-tm", name: "Treadmill").insert(conn)
            try Exercise(id: "ex-lp", name: "Leg Press").insert(conn)
            try Exercise(id: "ex-hs", name: "Hack Squat").insert(conn)

            /* The session ran 19:00–20:31. `started_at` and `ended_at` are the
               screen's: opened at 10:46, finished at 17:12 — which is exactly
               the span the export used to print for it. */
            try WorkoutSession(id: "s1", userId: user, dayKey: "legs_a", date: "2026-08-24",
                               startedAt: iso("2026-08-24T10:46:00Z"), endedAt: iso("2026-08-24T17:12:00Z"),
                               durationMin: 91, sessionRpe: 8).insert(conn)
            // A treadmill warm-up: no load, no reps, five minutes and 0.37 km.
            try WorkoutSet(id: "w1", sessionId: "s1", exerciseId: "ex-tm", setIndex: 0, weightKg: 0, reps: 0,
                           setType: "warmup", exerciseOrder: 0,
                           durationSec: 300, incline: 2, distanceKm: 0.37).insert(conn)
            /* Hack Squat sits SECOND in the deck and was performed FIRST.
               `exercise_order` records the deck; the event log records the
               session. The two disagree, on purpose. */
            try WorkoutSet(id: "h1", sessionId: "s1", exerciseId: "ex-hs", setIndex: 1, weightKg: 60, reps: 10,
                           rpe: 10, exerciseOrder: 2).insert(conn)
            try WorkoutSet(id: "p1", sessionId: "s1", exerciseId: "ex-lp", setIndex: 2, weightKg: 75, reps: 12,
                           rpe: 8, exerciseOrder: 1).insert(conn)

            try event(conn, id: "e1", session: "s1", set: "w1", seq: 1, at: "2026-08-24T19:00:00Z")
            try event(conn, id: "e2", session: "s1", set: "h1", seq: 2, at: "2026-08-24T19:20:00Z")
            try event(conn, id: "e3", session: "s1", set: "p1", seq: 3, at: "2026-08-24T20:31:00Z")

            // The same walk, imported three times. Identical start, duration
            // and distance — one physical bout.
            for (i, id) in ["c1", "c2", "c3"].enumerated() {
                try CardioLogRow(id: id, userId: user, date: "2026-08-24", kind: "walk",
                                 distanceM: 4200, durationMin: 48, kcal: 190, fromHealthkit: true,
                                 createdAt: iso("2026-08-24T07:32:00Z")).insert(conn)
                _ = i
            }
            // A genuinely different bout on the same day, same distance.
            try CardioLogRow(id: "c4", userId: user, date: "2026-08-24", kind: "walk",
                             distanceM: 4200, durationMin: 51, kcal: 200, fromHealthkit: true,
                             createdAt: iso("2026-08-24T17:40:00Z")).insert(conn)
            // A bout with no start at all: never deduped, and never a duplicate
            // of the clockless bout beside it.
            try CardioLogRow(id: "c5", userId: user, date: "2026-08-26", kind: "cycle",
                             durationMin: 30, fromHealthkit: false).insert(conn)
            try CardioLogRow(id: "c6", userId: user, date: "2026-08-28", kind: "swim",
                             durationMin: 45, fromHealthkit: false).insert(conn)

            /* A SECOND session whose event log was BACK-FILLED, not logged:
               `SessionEditing.seedEventLog` stamps every row with the session's
               own `started_at`, so all three instants are identical. */
            try WorkoutSession(id: "s2", userId: user, dayKey: "arms", date: "2026-08-26",
                               startedAt: iso("2026-08-26T18:00:00Z"), endedAt: iso("2026-08-26T19:05:00Z"),
                               durationMin: 65).insert(conn)
            for (i, (id, ex, order)) in [("z1", "ex-lp", 0), ("z2", "ex-hs", 1), ("z3", "ex-tm", 2)].enumerated() {
                try WorkoutSet(id: id, sessionId: "s2", exerciseId: ex, setIndex: i, weightKg: 20, reps: 10,
                               exerciseOrder: order).insert(conn)
                try event(conn, id: "se\(i)", session: "s2", set: id, seq: 10 + i, at: "2026-08-26T18:00:00Z")
            }

            // A reading taken before training on a day the calendar calls rest.
            try FatigueLogRow(id: "f1", userId: user, date: "2026-08-24", slot: "pre", level: 3,
                              createdAt: iso("2026-08-24T18:55:00Z")).insert(conn)
        }
        return db
    }

    private func built(_ zone: String) throws -> WeeklyExportInput {
        try WeeklyExportBuilder(database: try seeded(), userId: user, timeZone: TimeZone(identifier: zone)!)
            .input(weekStart: weekStart, today: weekStart)
    }

    @Test("the session's span is the first and last set, in the phone's own zone")
    func spanComesFromTheEventLog() throws {
        let got = try built("Asia/Jerusalem")
        let s = try #require(got.sessions.first)
        // 19:00 and 20:31 UTC are 22:00 and 23:31 in Jerusalem — the point is
        // that both the SOURCE and the ZONE changed, and neither is 10:46.
        #expect(s.startedAt == "2026-08-24T22:00:00+03:00")
        #expect(s.endedAt == "2026-08-24T23:31:00+03:00")
        #expect(WeeklyExport.build(got).contains("22:00–23:31"))
    }

    @Test("a bout is imported many times and exported once")
    func duplicateCardioIsRemoved() throws {
        let got = try built("UTC")
        // Three imports of one walk become one; the second walk, the cycle and
        // the swim are four distinct bouts.
        #expect((got.cardio ?? []).count == 4)
        #expect(got.anomalies?.contains("duplicate cardio removed 2") == true)
        // And the bout that only shares its distance survives.
        #expect((got.cardio ?? []).filter { $0.date == "2026-08-24" }.map(\.durationMin) == [48, 51])
        // Its own start, in the same clock as everything else.
        #expect((got.cardio ?? []).first?.startedAt == "2026-08-24T07:32:00Z")
    }

    @Test("the movements print in the order they were performed")
    func performedOrderWinsOverTheDeck() throws {
        let got = try built("UTC")
        let s = try #require(got.sessions.first)
        #expect(s.orderSource == "performed")
        // Deck order would be Treadmill, Leg Press, Hack Squat.
        #expect(s.exercises.map(\.name) == ["Treadmill", "Hack Squat", "Leg Press"])
    }

    @Test("a treadmill warm-up carries its duration, its distance and a derived speed")
    func treadmillWarmupIsNotZeroReps() throws {
        let got = try built("UTC")
        let treadmill = try #require(got.sessions.first?.exercises.first { $0.name == "Treadmill" })
        let set = try #require(treadmill.sets.first)
        #expect(set.durationSec == 300)
        #expect(set.distanceKm == 0.37)
        #expect(set.inclinePct == 2)
        // 0.37 km in 300 s is 4.44 km/h.
        let md = WeeklyExport.build(got)
        #expect(md.contains("warm-ups Treadmill 5:00 4.4 km/h 0.37 km 2%"))
        #expect(!md.contains("0 reps"))
    }

    @Test("a back-filled event log is not a record of what was performed")
    func seededEventsDoNotClaimPerformedOrder() throws {
        let got = try built("UTC")
        let s = try #require(got.sessions.first { $0.label != got.sessions.first?.label || $0.date == "2026-08-26" }
            ?? got.sessions.first { $0.date == "2026-08-26" })
        /* Every seeded event carries the session's own `started_at`, so there
           is no order in them. Without the guard the sort falls through to the
           NAME tiebreak and prints Hack Squat, Leg Press, Treadmill under the
           word `performed`; the span collapses onto 18:00–18:00. */
        #expect(s.orderSource == "index")
        #expect(s.exercises.map(\.name) == ["Leg Press", "Hack Squat", "Treadmill"])
        #expect(s.startedAt == "2026-08-26T18:00:00Z")
        #expect(s.endedAt == "2026-08-26T19:05:00Z")
        // Deck order is a guess too, and §7 says so.
        #expect(WeeklyExport.build(got).contains("no performed-order index 2026-08-26"))
    }

    @Test("a stress event prints its time; a legacy slot row still prints its slot")
    func stressEventPrintsItsTime() throws {
        let db = try seeded()
        try db.writer.write { conn in
            // 11:32 UTC is 14:32 in Jerusalem — the time printed is the zone's, not the clock's.
            try StressLogRow(id: "st-t", userId: user, date: "2026-08-24", slot: "midday", level: 3,
                             tags: JSONText(raw: "[]"), note: nil,
                             createdAt: iso("2026-08-24T11:32:00Z"), updatedAt: iso("2026-08-24T11:32:00Z"),
                             loggedAt: iso("2026-08-24T11:32:00Z")).insert(conn)
            // Written before W1: a slot and no time. Created AFTER the timed
            // row on purpose — the order is the day's, not the write's.
            try StressLogRow(id: "st-l", userId: user, date: "2026-08-24", slot: "evening", level: 4,
                             tags: JSONText(raw: "[]"), note: nil,
                             createdAt: iso("2026-08-24T12:00:00Z"), updatedAt: iso("2026-08-24T12:00:00Z")).insert(conn)
            // And a legacy MORNING row created last of all still sorts first.
            try StressLogRow(id: "st-m", userId: user, date: "2026-08-24", slot: "morning", level: 2,
                             tags: JSONText(raw: "[]"), note: nil,
                             createdAt: iso("2026-08-24T13:00:00Z"), updatedAt: iso("2026-08-24T13:00:00Z")).insert(conn)
        }
        let got = try WeeklyExportBuilder(database: db, userId: user, timeZone: TimeZone(identifier: "Asia/Jerusalem")!)
            .input(weekStart: weekStart, today: weekStart)
        #expect(got.stress?.map(\.time) == ["morning", "14:32", "evening"].map { $0.contains(":") ? $0 : nil })
        #expect(got.stress?.map(\.slot) == ["morning", "midday", "evening"])

        let md = WeeklyExport.build(got)
        // §2 trace: one token differs between a timed event and a legacy row.
        #expect(md.contains("stress 2026-08-24 morning 2 · 2026-08-24 14:32 3 · 2026-08-24 evening 4"))
        // §4 daily cell, same rule.
        let day = try #require(md.split(separator: "\n").first { $0.hasPrefix("2026-08-24 · ") })
        #expect(day.contains("stress morning 2, 14:32 3, evening 4"))
    }

    /// The wave's own gate: the screen now lets you log as many readings a day
    /// as you feel like, and two of them in one bucket is the case the old
    /// unique key made impossible. The export has to carry both — a week that
    /// silently dropped the second is a week that disagrees with the card the
    /// reader just looked at, and with the day mean the index was built from.
    @Test("two events in one slot both print, in the order the day happened")
    func twoEventsInOneSlotBothPrint() throws {
        let db = try seeded()
        try db.writer.write { conn in
            // 06:12 and 07:40 Jerusalem — both `morning`, and under the dropped
            // `(user_id, date, slot)` unique the second would have deleted the
            // first on write.
            try StressLogRow(id: "st-a", userId: user, date: "2026-08-24", slot: "morning", level: 2,
                             tags: JSONText(raw: "[]"), note: nil,
                             createdAt: iso("2026-08-24T03:12:00Z"), updatedAt: iso("2026-08-24T03:12:00Z"),
                             loggedAt: iso("2026-08-24T03:12:00Z")).insert(conn)
            try StressLogRow(id: "st-b", userId: user, date: "2026-08-24", slot: "morning", level: 4,
                             tags: JSONText(raw: "[]"), note: nil,
                             createdAt: iso("2026-08-24T04:40:00Z"), updatedAt: iso("2026-08-24T04:40:00Z"),
                             loggedAt: iso("2026-08-24T04:40:00Z")).insert(conn)
            // A third in a different bucket, so the ordering claim is about the
            // CLOCK and not merely about insertion order.
            try StressLogRow(id: "st-c", userId: user, date: "2026-08-24", slot: "evening", level: 3,
                             tags: JSONText(raw: "[]"), note: nil,
                             createdAt: iso("2026-08-24T17:05:00Z"), updatedAt: iso("2026-08-24T17:05:00Z"),
                             loggedAt: iso("2026-08-24T17:05:00Z")).insert(conn)
        }
        let got = try WeeklyExportBuilder(database: db, userId: user, timeZone: TimeZone(identifier: "Asia/Jerusalem")!)
            .input(weekStart: weekStart, today: weekStart)
        // Two rows, one slot, two distinct times — not one row, and not a mean.
        #expect(got.stress?.map(\.time) == ["06:12", "07:40", "20:05"])
        #expect(got.stress?.map(\.slot) == ["morning", "morning", "evening"])
        #expect(got.stress?.map(\.level) == [2, 4, 3])

        let md = WeeklyExport.build(got)
        #expect(md.contains("stress 2026-08-24 06:12 2 · 2026-08-24 07:40 4 · 2026-08-24 20:05 3"))
        let day = try #require(md.split(separator: "\n").first { $0.hasPrefix("2026-08-24 · ") })
        #expect(day.contains("stress 06:12 2, 07:40 4, 20:05 3"))
    }

    @Test("a clockless bout is never a duplicate of another clockless bout")
    func clocklessCardioIsNotDeduped() throws {
        let got = try built("UTC")
        let kinds = (got.cardio ?? []).map(\.kind).sorted()
        #expect(kinds == ["cycle", "swim", "walk", "walk"])
    }

    @Test("the fatigue slots follow the day that was trained, not the calendar")
    func fatigueSlotsFollowTheSession() throws {
        let got = try built("UTC")
        // The builder normalised `pre` against a day with a session on it.
        #expect(got.fatigue?.first { $0.date == "2026-08-24" }?.slot == "Before training")
        // And the renderer asks for the same three slots, so the reading lands.
        let day = try #require(got.days.first { $0.date == "2026-08-24" })
        let trace = WeeklyExport.fatigueLabels(isTrainingDay: true)
        #expect(trace.contains("Before training"))
        #expect(WeeklyExport.build(got).contains("2026-08-24 · TRAIN"))
        #expect(!WeeklyExport.build(got).split(separator: "\n")
            .first { $0.hasPrefix("2026-08-24 · TRAIN") }!.contains("fatigue -/-/-"))
        _ = day
    }

    @Test("a set rated 10 is a set to failure, whatever the tick says")
    func failureComesFromTheRating() throws {
        let got = try built("UTC")
        // h1 is rated 10 and carries `set_type = normal`; p1 is rated 8.
        #expect(got.sessions.first?.failureSets == 1)
        #expect(WeeklyExport.build(got).contains("failure_sets 1"))
    }
}
