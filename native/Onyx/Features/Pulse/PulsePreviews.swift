#if DEBUG
import SwiftUI
import GRDB
import OnyxUI
import OnyxCore
import OnyxData

/// Seeded Pulse screens for `#Preview` and `scripts/native-shot.sh`.
///
/// Every store is in-memory and written through the same `DayEditing` API the
/// screen uses, so a shot exercises the read path end to end. The date is
/// FIXED — a Tuesday, a Onyx-5 training day — so the shot does not become a
/// rest-day layout on Wednesdays or churn its title daily.
enum PulsePreviews {

    static let userId = "00000000-0000-0000-0000-000000000001"
    /// Tue 1 Sept 2026 — Onyx-5 trains Sun/Mon/Tue/Thu/Fri.
    static let date = "2026-09-01"

    @MainActor
    static func model(_ seed: (AppDatabase) throws -> Void = { _ in }) -> DayModel {
        let database = try! AppDatabase.inMemory(deviceId: "shot")
        // The catalogue as rows (W2): decks, plans, phases, rungs.
        PreviewCatalogue.seed(database)
        _ = try? database.editUserGoals(userId: userId) { row in
            row.activePlan = "onyx5"
            row.activePhase = ProgramPhase.cut.rawValue
            row.sleepGoalHours = 8
            row.calorieGoal = 1955
            row.proteinGoalG = 170
        }
        try? seed(database)
        let model = DayModel(database: database, userId: userId, date: date)
        // ── THE CLOCK IS PINNED FOR EVERY PULSE FIXTURE (W3) ────────────
        // It used to be pinned per shot, by the four whose CONTENT moved
        // with the time of day. The Stack square made that every shot: the
        // due/later split is a question about the clock, so an unpinned
        // `day` would have counted 3 of 9 at lunchtime and 9 of 9 after ten,
        // and the committed PNG would have churned by the hour. 13:00 is the
        // same minute `pinned` has always used — those call sites are now
        // restating this rather than setting it, and are kept because they
        // say WHY that sheet needs it.
        model.previewNowMinutes = 13 * 60
        return model
    }

    /// A full training day.
    ///
    /// `withSession` adds the workout that was actually performed, which is
    /// what separates the `day` shot from `day-past`: the Workout summary card
    /// only exists when the day HAS a finished session, and a shot of the
    /// screen without one would never photograph it.
    @MainActor
    static func fullDay(withSession: Bool = false) -> DayModel {
        model { db in try seedFullDay(db, withSession: withSession) }
    }

    /// The same day with the night unremarkable and HRV collapsed — the state
    /// `VitalHero` exists for, and the only one in which Pulse's hero slot is
    /// not the night.
    ///
    /// Both halves are needed. Dropping HRV alone would not promote it:
    /// `fullDay`'s last nine nights are short enough that the night's own z
    /// clamps at −2, and the rule hands the slot to a vital only when it is
    /// further from its own normal than the night is. So the nights go back to
    /// ordinary (z ≈ −0.6, inside the band) and HRV falls to the mid thirties
    /// against a fortnight in the high forties (z = −2).
    @MainActor
    static func alarmedDay() -> DayModel {
        model { db in
            try seedFullDay(db, withSession: false)
            for (i, minutes) in [475, 468, 482, 460, 490, 472, 465, 478, 470].enumerated() {
                let d = ISODate.addDays(date, -i) ?? date
                try db.editDailyLog(userId: userId, date: d) { $0.sleepMinutes = minutes }
            }
            for (i, hrv) in [32.0, 34, 33, 36, 33, 35, 34].enumerated() {
                let d = ISODate.addDays(date, -i) ?? date
                try db.editDailyLog(userId: userId, date: d) { $0.hrvMs = hrv }
            }
        }
    }

    /// `@MainActor` because `DayModel.localInstant` is: the stress log and the
    /// supplement mark below both stamp a wall-clock instant, and the closure
    /// this body was extracted from inherited the isolation it needed.
    @MainActor
    private static func seedFullDay(_ db: AppDatabase, withSession: Bool) throws {
        if withSession { try seedSession(db) }
        // ── FORTY-NINE NIGHTS, NOT NINE (W2) ────────────────────────────
        // The last nine are the short week the bank is built from: 3.4 h of
        // decayed debt over the fortnight it reads. The forty behind them
        // are ordinary nights around the 8 h goal, and they exist because
        // the hero rule reads `sleep_minutes` over the same 49 days
        // `Readiness.zSignal` reads every other series over. Seeded with
        // nine, the night had no baseline, no z and no claim on its own
        // slot — and HRV's −1.05 took the hero on the DEFAULT shot.
        for (i, minutes) in [400, 420, 500, 430, 480, 510, 460, 440, 490].enumerated() {
            let d = ISODate.addDays(date, -i) ?? date
            try db.editDailyLog(userId: userId, date: d) { $0.sleepMinutes = minutes }
        }
        let ordinary = [478, 470, 486, 474, 482, 466, 490]
        for i in 9...48 {
            let d = ISODate.addDays(date, -i) ?? date
            try db.editDailyLog(userId: userId, date: d) { $0.sleepMinutes = ordinary[i % 7] }
        }
        // The night itself, with stages: 6 h 40 m asleep.
        let noon = LogicalDay.date(fromISO: date)!
        var cursor = noon.addingTimeInterval(-(12 * 60 + 40) * 60)   // 23:20 the evening before
        var samples: [SleepSample] = []
        for (stage, minutes) in [(3, 60), (4, 40), (3, 50), (5, 45), (2, 10), (3, 60), (4, 35), (3, 50), (5, 45), (2, 10), (3, 15)] {
            let end = cursor.addingTimeInterval(Double(minutes) * 60)
            samples.append(SleepSample(value: stage, start: cursor, end: end))
            cursor = end
        }
        try db.ingest(HealthPayload(date: date, sleep: Sleep.aggregate(samples)), userId: userId)

        // ── TEN WEIGH-INS, BECAUSE THE SCALE SQUARE DRAWS A TRACE (W3) ──
        // W2's lesson in the other column: a fixture thin in one column is a
        // CLAIM, not a neutral state. `fullDay` seeded no body metrics at
        // all, so the Scale square would have photographed "No weigh-in" on
        // the DEFAULT shot and its trace would have shipped unreviewed.
        // Twice a week over five weeks, which is the real cadence — and it is
        // the cadence, not the count, that makes the sparkline sparse.
        let weighIns: [(days: Int, kg: Double, fat: Double)] = [
            (0, 64.8, 15.2), (3, 65.0, 15.4), (7, 65.3, 15.5), (10, 65.5, 15.7),
            (14, 65.4, 15.9), (17, 65.8, 16.0), (21, 66.0, 16.1), (25, 66.1, 16.3),
            (28, 66.3, 16.4), (32, 66.2, 16.6),
        ]
        for reading in weighIns {
            let d = ISODate.addDays(date, -reading.days) ?? date
            try db.saveBodyMetrics(userId: userId, date: d) { row in
                row.weightKg = reading.kg
                row.bodyFatPct = reading.fat
            }
        }

        // ── AND A STACK, BECAUSE THE STACK SQUARE COUNTS DOSES (W3) ─────
        // `fullDay` seeded no supplements at all, so the fourth square would
        // have photographed "Nothing scheduled" on the DEFAULT shot and its
        // dose dots — counted, still ahead, said no to — would have shipped
        // unreviewed.
        //
        // ── AND THE SKIP BELOW WAS DEAD UNTIL THIS LINE EXISTED ─────────
        // This fixture has always ended with `setSupplementSkipped("caffeine")`,
        // against a stack nothing ever seeded: the write landed on a key with
        // no dose behind it and the day had nine fewer rows than its author
        // thought. Seeding `PreviewCatalogue`'s nine is what makes that line
        // mean something, and at the pinned 13:00 it is what puts all three
        // dot states on the default shot — three counted (10:30 and 11:45 have
        // passed), one skipped (caffeine), five still ahead.
        PreviewCatalogue.seedStack(db)

        try db.setFatigue(userId: userId, date: date, slot: FatigueSlot.waking.rawValue, level: 2)
        try db.setFatigue(userId: userId, date: date, slot: FatigueSlot.pre.rawValue, level: 3)
        // ── THREE EVENTS, TWO OF THEM IN ONE SLOT ───────────────────────
        // 08:30 and 09:12 are both `morning`, which is the whole point of
        // the wave: under the old unique key the second of them would have
        // deleted the first, and the day would have read "Tense" with no
        // record that it started at "Okay". The strip has to show both, the
        // export has to print both, and the index's day mean has to be the
        // mean of all three — none of which a fixture with one reading per
        // bucket can photograph.
        //
        // Three is also exactly the card's cap at shipping type, so the
        // same fixture draws a full strip there and a "+1 earlier" marker
        // at AX5, where the cap is two.
        try db.logStress(userId: userId, date: date, loggedAt: DayModel.localInstant(date, hhmm: "08:30") ?? Date(),
                         level: 2, tags: [.work])
        try db.logStress(userId: userId, date: date, loggedAt: DayModel.localInstant(date, hhmm: "09:12") ?? Date(),
                         level: 3, tags: [.work])
        try db.logStress(userId: userId, date: date, loggedAt: DayModel.localInstant(date, hhmm: "13:10") ?? Date(),
                         level: 4, tags: [.work, .money], note: "Deadline moved to Friday.")
        try db.setDoms(userId: userId, date: date, muscleGroup: "Quads", severity: 2)
        try db.setDoms(userId: userId, date: date, muscleGroup: "Chest", severity: 1)
        // ── ONE SIDE, ON PURPOSE (W9) ───────────────────────────────────────
        // Quads and Chest are BILATERAL ratings and ring both paths, which is
        // what every rating written before W9 does. The right glute is the
        // thing the wave added, and it is the only state where a shot can show
        // that the body is asymmetric — a figure ringed symmetrically is
        // identical whether or not laterality works at all.
        // One per view, because the tile opens on the front and a reviewer
        // should not have to swipe to find out whether the wave shipped.
        try db.setDoms(userId: userId, date: date, muscleGroup: "Calves", severity: 3, side: .left)
        try db.setDoms(userId: userId, date: date, muscleGroup: "Glutes", severity: 3, side: .right)
        try db.setSupplementSkipped(
            userId: userId, date: date, itemKey: "caffeine", skipped: true,
            dueAt: DayModel.localInstant(date, hhmm: "11:45")
        )
        try db.addCardio(CardioLogRow(
            id: newOnyxID(), userId: userId, date: date, kind: "walk",
            distanceM: 4200, durationMin: 45, fromHealthkit: false, createdAt: Date(),
            activeKcal: 285, avgHr: 118, effort: 4, inclinePct: 12
        ))
        // The fortnight behind the date: every vital needs a BASELINE or
        // its row draws a reading with no delta and no sparkline, which is
        // exactly the half of this screen a shot has to prove.
        let hrv: [Double] =   [48, 51, 44, 47, 53, 49, 46, 50, 45, 52, 47, 43, 49, 41]
        let rest: [Int] =     [52, 51, 54, 53, 50, 52, 55, 51, 53, 52, 50, 54, 52, 56]
        let resp: [Double] =  [14.2, 14.0, 14.6, 14.1, 13.9, 14.3, 14.8, 14.2, 14.4, 14.1, 14.0, 14.5, 14.2, 15.1]
        let spo2: [Double] =  [97.4, 97.1, 96.8, 97.3, 97.6, 97.2, 96.9, 97.5, 97.0, 97.3, 97.4, 96.7, 97.2, 96.6]
        let temp: [Double] =  [-0.08, 0.02, 0.14, -0.03, 0.05, 0.11, 0.21, -0.02, 0.07, 0.03, -0.05, 0.16, 0.04, 0.27]
        let steps: [Int] =    [9120, 11040, 7480, 10230, 12560, 8890, 6740, 10410, 9330, 11870, 8060, 7210, 10980, 8430]
        let stand: [Int] =    [11, 12, 9, 12, 13, 10, 8, 12, 11, 13, 10, 9, 12, 10]
        let active: [Double] = [612, 704, 488, 668, 792, 574, 431, 683, 596, 741, 512, 466, 715, 548]
        for i in 0..<14 {
            let d = ISODate.addDays(date, -(13 - i)) ?? date
            try db.editDailyLog(userId: userId, date: d) { row in
                row.hrvMs = hrv[i]
                row.avgRestHeartRate = rest[i]
                row.respiratoryRate = resp[i]
                row.bloodOxygen = spo2[i]
                row.wristTempDelta = temp[i]
                row.steps = steps[i]
                row.standHours = stand[i]
                row.activeEnergy = active[i]
            }
        }
        try db.editDailyLog(userId: userId, date: date) { $0.waterMl = 2100 }
        // 1,420 kcal against macros that come to 1,450 — Health's own
        // figure, kept (memory `no-ai-in-app`'s sibling in `MacroEditSheet`).
        try db.setManualMacros(
            userId: userId, date: date,
            calories: 1420, proteinG: 128, carbsG: 132, fatG: 46, phase: ProgramPhase.cut.rawValue
        )
        try db.seedRows { db in
            try DailyScoreRow(
                id: newOnyxID(), userId: userId, date: date, score: 78,
                sleepScore: 71, nutritionScore: 84, activityScore: 76,
                workoutScore: 88, recoveryScore: 69, batteryPct: 64,
                computedAt: Date(), finalized: false
            ).insert(db)
        }

        try db.saveBodyMetrics(userId: userId, date: date) { row in
            row.weightKg = 64.8; row.bodyFatPct = 15.2; row.musclePercent = 77.6
            row.waterPercent = 58.4; row.boneMineral = 4.1; row.visceralFat = 5
            row.bmr = 1540; row.bmi = 21.3; row.skeletalMuscleMassKg = 27.1
            row.estimatedWaistToHipRatio = 0.86
            row.muscleMassKg = 50.3; row.fatMassKg = 9.85; row.fatFreeMassKg = 54.95
        }
        try seedStressHistory(db)
    }

    /// Days 14–48 behind the seeded date — what the STRESS index needs and the
    /// vitals grid does not (§U5.3).
    ///
    /// Every one of the index's four terms is a `Readiness` z-score, and a z
    /// needs 14 readings in the 42-day BASELINE behind the 7-day roll. The
    /// fortnight above is what the vitals cards read and it is three times too
    /// short for that, so a tile seeded from it alone draws a flat 50 with
    /// three terms unanswered — a screenshot that reviews a state the app is
    /// almost never in.
    ///
    /// So the baseline is laid steady here and the EXCURSION stays in the
    /// fortnight above, where it already is: HRV falling to 41, resting HR
    /// climbing to 56. This adds the two series that fortnight has no reason to
    /// hold — the nights' awake fraction (fragmentation) and the week's
    /// sessions (load) — and breaks the last seven nights so the reading is a
    /// real Elevated rather than a synthetic one.
    ///
    /// Nothing here reaches the other Pulse shots: the vitals grid reads 14
    /// days, `sleepDebt` reads `daily_logs.sleep_minutes` (untouched), and the
    /// Workout summary card only draws sessions dated ON the selected day,
    /// which is the one day this skips.
    private static func seedStressHistory(_ db: AppDatabase) throws {
        let hrv: [Double] = [47, 49, 52, 46, 50, 48, 51]
        let rest: [Int] =   [52, 51, 53, 50, 52, 54, 51]
        for i in 14...48 {
            let d = ISODate.addDays(date, -i) ?? date
            try db.editDailyLog(userId: userId, date: d) { row in
                row.hrvMs = hrv[i % 7]
                row.avgRestHeartRate = rest[i % 7]
            }
        }

        // One night per date, filed by its BEDTIME inside the night's own UTC
        // window — `readinessHistory` buckets by `NightWindow.nightOf`, so a
        // row stamped anywhere else belongs to a night nobody reads. The last
        // seven are broken (44 awake minutes in 395 asleep against a steady
        // 19 in 430), which is the fragmentation the index exists to see.
        try db.seedRows { db in
            for i in 1...48 {
                let d = ISODate.addDays(date, -i) ?? date
                guard let bed = OnyxData.NightWindow.fallbackBedTime(d) else { continue }
                let broken = i <= 7
                let asleep = broken ? 395 : 430
                let awake = broken ? 44 : 19
                let deep = broken ? 52 : 71
                let rem = broken ? 78 : 96
                try SleepSessionRow(
                    id: newOnyxID(), userId: userId, hkUuid: "seed-night-\(d)",
                    startTime: bed, endTime: bed.addingTimeInterval(Double(asleep + awake) * 60),
                    durationMin: asleep, deepMin: deep, remMin: rem,
                    coreMin: asleep - deep - rem, awakeMin: awake,
                    createdAt: bed
                ).insert(db)
            }
        }

        // Four sessions a week. The load term answers only with a chronic side
        // built on real sessions (`minLoadDays`) and fourteen prior weekly
        // strains behind it (`minStrainHistory`); the last week is longer and
        // harder, which is what lifts the acute:chronic ratio off its floor.
        try db.seedRows { db in
            for i in 1...48 where [0, 1, 2, 4].contains(i % 7) {
                let d = ISODate.addDays(date, -i) ?? date
                let noon = LogicalDay.date(fromISO: d) ?? Date()
                let heavy = i <= 7
                try WorkoutSession(
                    id: newOnyxID(), userId: userId, dayKey: nil, date: d,
                    startedAt: noon.addingTimeInterval(-3 * 3600),
                    endedAt: noon.addingTimeInterval(-3 * 3600 + Double(heavy ? 86 : 62) * 60),
                    durationMin: heavy ? 86 : 62, sessionRpe: heavy ? 8.5 : 7
                ).insert(db)
            }
        }
    }

    /// One finished Legs & Core A, on the seeded date.
    ///
    /// Written as raw rows rather than through the logger: the card reads
    /// `workout_sessions` and `workout_sets` and nothing else, and a seed that
    /// drove the whole logger would be photographing the logger.
    ///
    /// Parameterised since W3 so `twoSessions` can put a second, different
    /// session on the same date. Every name below is one `MuscleMap` knows: a
    /// plausible-looking name it has never seen resolves to NOTHING and the
    /// card's muscle wash comes out grey (memory: `worktree-guard-and-hooks`).
    private static func seedSession(
        _ db: AppDatabase,
        dayKey: String = "legs_a",
        hoursAgo: Double = 3,
        durationMin: Double = 68,
        lifts: [(name: String, kg: Double, reps: Int)] = [
            ("Leg Press", 92, 10), ("Hack Squat", 60, 10), ("Leg Extension", 45, 12),
            ("Seated Leg Curl", 45, 12), ("Calf Press", 67.5, 15),
        ]
    ) throws {
        try db.seedRows { db in
            let sessionId = newOnyxID()
            let noon = LogicalDay.date(fromISO: date)!
            let started = noon.addingTimeInterval(-hoursAgo * 3600)
            try WorkoutSession(
                id: sessionId, userId: userId, dayKey: dayKey, date: date,
                startedAt: started,
                endedAt: started.addingTimeInterval(durationMin * 60),
                durationMin: durationMin, sessionRpe: 8
            ).insert(db)
            var index = 0
            for lift in lifts {
                let exerciseId = newOnyxID()
                try Exercise(id: exerciseId, name: lift.name).insert(db)
                // A warm-up and three working sets: the warm-up is what proves
                // the card counts working sets rather than rows.
                for set in 0..<4 {
                    let load = set == 0 ? lift.kg * 0.6 : lift.kg
                    try WorkoutSet(
                        id: newOnyxID(), sessionId: sessionId, exerciseId: exerciseId,
                        setIndex: index, weightKg: load, reps: lift.reps,
                        setType: set == 0 ? "warmup" : "normal", side: nil, pairId: nil,
                        est1rmKg: OneRepMax.estimate(weight: load, reps: Double(lift.reps)),
                        foldOrder: index
                    ).insert(db)
                    index += 1
                }
            }
        }
    }

    /// A training day with TWO finished sessions on it — an early upper
    /// session and a lower one after it, which is what a double day looks like
    /// and what the screen-and-a-half budget has to survive.
    @MainActor
    static func twoSessions() -> DayModel {
        model { db in
            try seedFullDay(db, withSession: true)
            try seedSession(db, dayKey: "cb_b", hoursAgo: 5, durationMin: 54, lifts: [
                ("Chest Press", 40, 10), ("Neutral-Grip Lat Pulldown", 49.5, 10),
                ("Seated Cable Row (Wide Grip)", 40, 12), ("Preacher Curl", 20, 12),
            ])
        }
    }

    /// A stack with every state on it at once: one due, one explicitly taken,
    /// one skipped, two still ahead, and one archived.
    ///
    /// The clock is PINNED to 13:00 rather than read, so the Due and Later
    /// sections hold the same rows whatever time the loop runs.
    @MainActor
    static func stackDay() -> DayModel {
        let model = model { db in
            // One of each FORM and one of each colour the token map knows:
            // the whole point of the glyph is that five silhouettes are
            // distinguishable in a list of nine, and a seed that left every
            // `form` nil photographed the same default five times.
            let add = { (name: String, dose: String, time: String, key: String,
                         form: SupplementForm, colour: String, micros: [String: Double]?) in
                _ = try db.addCustomSupplement(
                    userId: userId, name: name, dose: dose, color: colour, form: form.rawValue, time: time,
                    schedule: CustomSchedule(key: key, slot: time == "10:30" ? "Morning" : "Before Bed"),
                    micros: micros,
                    doseAmount: Supplements.parseDose(dose)?.amount,
                    doseUnit: Supplements.parseDose(dose)?.unit.rawValue
                )
            }
            try add("Two Per Day Multivitamin", "2 tabs", "10:30", "multivitamin", .pill, "amber", nil)
            try add("Vitamin D3 + K2", "125 mcg", "10:30", "d3k2", .capsule, "green", nil)
            try add("Creatine Monohydrate", "5 g", "10:30", "creatine", .powder, "blue", nil)
            try add("Magnesium Glycinate", "300 mg", "22:00", "magnesium", .gummy, "purple", nil)
            try add("L-Theanine", "200 mg", "22:00", "theanine", .liquid, "teal", nil)

            let retired = try db.addCustomSupplement(
                userId: userId, name: "Ashwagandha", dose: "600 mg", time: "22:00",
                schedule: CustomSchedule(key: "ashwagandha")
            )
            try db.setCustomSupplementArchived(id: retired, userId: userId, archived: true, at: Date(timeIntervalSince1970: 1_756_000_000))

            try db.markSupplement(userId: userId, date: date, itemKey: "d3k2", mark: .taken)
            try db.markSupplement(userId: userId, date: date, itemKey: "creatine", mark: .skipped)
        }
        model.previewNowMinutes = 13 * 60
        return model
    }

    /// The clock, pinned to 13:00 — a Midday bucket and a "before training"
    /// fatigue slot. Every sheet whose CONTENT depends on the time of day gets
    /// this, or the committed PNG changes by the hour.
    @MainActor
    static func pinned(_ model: DayModel) -> DayModel {
        model.previewNowMinutes = 13 * 60
        return model
    }

    /// Nothing logged, but a reading three days earlier for the form to offer.
    @MainActor
    static func withHistory() -> DayModel {
        model { db in
            try db.saveBodyMetrics(userId: userId, date: ISODate.addDays(date, -3) ?? date) { row in
                row.weightKg = 65.1; row.bodyFatPct = 15.6; row.musclePercent = 77.2
                row.waterPercent = 58.0; row.boneMineral = 4.1; row.visceralFat = 5
                row.bmr = 1545; row.bmi = 21.4; row.skeletalMuscleMassKg = 27.0
                row.estimatedWaistToHipRatio = 0.87
            }
        }
    }

    @MainActor @ViewBuilder
    static func view(_ screen: String) -> some View {
        switch screen {
        case "day":
            NavigationStack { PulseTabView(seeded: fullDay()) }
                .environment(AppEnvironment.preview)
        case "day-rows":
            NavigationStack { PulseTabView(seeded: fullDay(), startAtRows: true) }
                .environment(AppEnvironment.preview)
        // ── THE CAROUSEL'S OTHER TWO PAGES ──────────────────────────────────
        // A pager shows one page, and `simctl` can film a simulator but cannot
        // swipe one (the same reason `widgets-nudge` has a self-pressing
        // button). `startAtPage` writes the page binding a finger would write,
        // so each of the three is photographable without a second code path.
        case "day-stress":
            NavigationStack { PulseTabView(seeded: pinned(fullDay()), startAtPage: .stress) }
                .environment(AppEnvironment.preview)
        // Where the soreness square's door leads. It was the carousel's third
        // page until W3; the page is gone and the sheet it opened is what the
        // square opens, so the name keeps pointing at the thing being reviewed.
        case "day-soreness":
            Presenting(model: fullDay()) { SorenessSheet(model: $0) }
                .environment(AppEnvironment.preview)
        // The one state `day` cannot photograph: a vital far enough out to
        // take the night's slot. The grid stays eight cells — HRV has left it
        // and Sleep is in HRV's place — which is the half of the swap a static
        // shot has to prove.
        case "day-hero":
            NavigationStack { PulseTabView(seeded: alarmedDay()) }
                .environment(AppEnvironment.preview)
        // A day with the session on it, parked on the bottom half — the scale
        // and stack rows, the stress index and the session card. Since the
        // reorder the whole day fits a phone with room over, so this scrolls
        // very little; it is kept because it is the only screen that draws
        // `SessionHeaderCard` on Pulse at all.
        case "day-past":
            NavigationStack { PulseTabView(seeded: fullDay(withSession: true), startAtRows: true) }
                .environment(AppEnvironment.preview)
        // The same day, at the TOP — where the muscle wash is. It is the one
        // part of this screen that exists only above the fold and only when the
        // date holds a session, so `day-past` (which parks on the rows) cannot
        // photograph it, and a colour nobody has photographed is a colour that
        // was reviewed by reading the source.
        case "day-session":
            NavigationStack { PulseTabView(seeded: fullDay(withSession: true)) }
                .environment(AppEnvironment.preview)
        case "day-empty":
            NavigationStack { PulseTabView(seeded: model()) }
                .environment(AppEnvironment.preview)
        // TWO sessions on one date — the state the W3 budget is measured
        // against, because the session cards are the only part of this screen
        // whose count is not fixed. Parked on the rows, like `day-past`: the
        // wash at the top is `day-session`'s shot and the thing THIS one has to
        // prove is the square grid with two cards under it.
        case "day-two":
            NavigationStack { PulseTabView(seeded: twoSessions(), startAtRows: true) }
                .environment(AppEnvironment.preview)
        // Named for what it is rather than for where it opens from: the shot
        // list called this `day-inbody` and the plan's gate calls it `scale`,
        // and two names for one screen is the drift this file exists to stop.
        case "scale":
            Presenting(model: withHistory()) { InBodyEntryView(model: $0) }
                .environment(AppEnvironment.preview)
        // The same form with nothing behind it — the nil-history path, where
        // "Fill from last time" has nothing to copy and says so.
        case "scale-first":
            Presenting(model: model()) { InBodyEntryView(model: $0) }
                .environment(AppEnvironment.preview)
        case "day-swap":
            Presenting(model: fullDay()) { SwapDaySheet(model: $0) }
                .environment(AppEnvironment.preview)
        case "stack":
            Observing(model: stackDay()) { StackView(model: $0) }
                .environment(AppEnvironment.preview)
        case "stack-add":
            Presenting(model: stackDay()) { SupplementEditSheet(model: $0, editing: nil) }
                .environment(AppEnvironment.preview)
        // ── THE SAME SHEET ON A ROW THAT HAS A TIME ─────────────────────────
        // `stack-add` cannot photograph the clock: a new item has no time, so
        // the toggle sits off and the wheel is not on screen. W1 replaced a
        // free-text field with that wheel, and a control whose only shot is of
        // its absence is a control nobody reviewed. The row is built here
        // rather than read back from `stackDay`, so the shot is of one fixed
        // 18:30 and not of whatever the seed happens to order first.
        case "stack-edit":
            Presenting(model: stackDay()) {
                SupplementEditSheet(model: $0, editing: CustomSupplement(
                    id: "preview-psyllium", name: "Psyllium Husk Powder", dose: "5 g",
                    color: "#8E9AAC", form: SupplementForm.powder.rawValue, time: "18:30",
                    schedule: CustomSchedule(key: "psyllium", slot: "Evening"),
                    micros: ["kcal": 16.7, "carbs": 4.4, "fiber": 3.9],
                    doseAmount: 5, doseUnit: DoseUnit.g.rawValue
                ))
            }
            .environment(AppEnvironment.preview)
        // The night's own editor, over the tile it changes. `fullDay` seeds a
        // real night with stages, so the sheet opens on a window worth trimming
        // rather than on the mint-a-night path.
        case "sleep-edit":
            Presenting(model: fullDay()) { SleepEditSheet(model: $0) }
                .environment(AppEnvironment.preview)
        // The index and its four terms. `Presenting` keeps the tile visible
        // behind the sheet, which is the whole point of the shot: the tile says
        // the number and the sheet says where it came from.
        case "stress":
            Presenting(model: fullDay()) { StressBreakdownSheet(model: $0) }
                .environment(AppEnvironment.preview)
        // The five words, on the slot the clock picks. `previewNowMinutes` pins
        // the clock so the shot lands on the same slot every run — without it
        // the segmented control moves at 11:00 and again at 17:00 and the
        // committed PNG churns twice a day.
        case "fatigue":
            Presenting(model: pinned(fullDay())) { FatigueSheet(model: $0) }
                .environment(AppEnvironment.preview)
        // The logging sheet: five words, the time wheel defaulted to the pinned
        // clock, the chips and the note. `pinned` so the wheel lands on the
        // same minute every run — without it the committed PNG churns whenever
        // the shot is taken.
        case "stress-log":
            Presenting(model: pinned(fullDay())) { StressLogSheet(model: $0) }
                .environment(AppEnvironment.preview)
        // The whole day's events as rows, which is where the tags, the note and
        // the swipe-delete live — and the one shot in which both morning events
        // are visible with their tags.
        case "stress-day":
            Presenting(model: pinned(fullDay())) { StressLogListSheet(model: $0) }
                .environment(AppEnvironment.preview)
        // The ring behind the dashboard mark. Over Pulse rather than over
        // Today: the sheet needs a `DayModel` with its streams running, and
        // `PulseTabView` is what starts them.
        case "quick-log":
            Presenting(model: pinned(fullDay())) { QuickLogSheet(model: $0) }
                .environment(AppEnvironment.preview)
        case "doms":
            // The tile alone, at the size it actually gets: half of what §5.7
            // asks of it — the severity tints, the flip, the hit targets — is
            // below the fold on the full screen and cannot be photographed
            // there.
            DomsOnly()
                .environment(AppEnvironment.preview)
        // ── THE RATING POPOVER, WITH ITS SIDE SEGMENT (W9) ─────────────────
        // Drawn directly rather than presented, because a popover only exists
        // under a finger and the shot loop has none. It is shown as the tap on
        // the RIGHT glute leaves it — segment pre-selected to `R`, tick beside
        // the severity that side already carries — which is the whole claim of
        // the wave in one frame.
        // ── THE 2 × 2 GRID, ABOVE THE FOLD ─────────────────────────────────
        // `day` opens on the score, the night and the vitals; the squares are
        // three screens down and `native-shot.sh` photographs a scroll view's
        // FIRST screen only. The Soreness square counts what the map rings, so
        // once a rating can be one-sided the count is a number W9 changed —
        // and it had no shot of its own to change it in.
        case "pulse-squares":
            SquaresOnly()
                .environment(AppEnvironment.preview)
        // ── THE TWO FACES THE MIDDAY SHOT CANNOT HOLD ──────────────────────
        // `pulse-squares` is pinned to 13:00, where the Stack square is a row
        // of dots and Soreness has four ratings on it. Both of the faces this
        // wave added live outside that fixture: the stack's END-OF-DAY pile
        // needs a clock past the last slot, and the soreness PLACEHOLDER needs
        // a day nobody rated. A face with no shot is a face that gets reviewed
        // as though it were not there.
        case "pulse-squares-evening":
            SquaresOnly(nowMinutes: 23 * 60)
                .environment(AppEnvironment.preview)
        case "pulse-squares-empty":
            SquaresOnly(seed: { PulsePreviews.model() })
                .environment(AppEnvironment.preview)
        case "doms-rate":
            SeverityPopover(group: "Glutes", tapped: .right, current: { $0 == .right ? 3 : 0 }) { _, _ in }
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onyxScreen(.recover)
        default:
            ContentUnavailableView("No Day screen named \(screen)", systemImage: "questionmark.square.dashed")
        }
    }

    /// The 2 × 2 grid on its own ground, observed for the same reason
    /// `DomsOnly` is: the ratings arrive on a GRDB stream.
    private struct SquaresOnly: View {
        /// Minutes since local midnight, for the squares that read the clock.
        /// 13:00 is the grid's own default and the one every earlier shot used.
        var nowMinutes: Int = 13 * 60
        /// Which day to build. The default is the seeded one; `pulse-squares-
        /// empty` hands in a bare model so the empty faces can be photographed
        /// over a store that genuinely has nothing in it.
        var seed: () -> DayModel = { PulsePreviews.fullDay(withSession: true) }

        @State private var model: DayModel?

        var body: some View {
            NavigationStack {
                ScrollView {
                    if let model {
                        PulseSquareGrid(model: model, onStress: {}, onSoreness: {}, onScale: {}, onStack: {})
                            .padding(OnyxSpace.l)
                    }
                }
                .onyxScreen(.recover)
                .navigationTitle("Pulse")
                .navigationBarTitleDisplayMode(.inline)
            }
            .task {
                if model == nil {
                    let built = seed()
                    built.previewNowMinutes = nowMinutes
                    model = built
                }
                // `DayModel` does not subscribe on init — `observe()` is what
                // opens the GRDB streams. Without it the squares render their
                // EMPTY states over a seeded store, and the shot photographs
                // four blanks that look like a design decision.
                await model?.observe()
            }
        }
    }

    /// The soreness tile on its own ground, observed — the ratings arrive on a
    /// GRDB stream, and a tile handed an unobserved model draws an untouched
    /// body no matter what the seed wrote.
    private struct DomsOnly: View {
        /// Built ONCE and kept: the harness re-evaluates its switch on every
        /// observation tick, and a fresh model each time is a model whose
        /// streams never get past their first yield.
        @State private var model: DayModel?

        var body: some View {
            NavigationStack {
                ScrollView {
                    if let model {
                        DomsTile(model: model).padding(OnyxSpace.l)
                    }
                }
                .onyxScreen(.recover)
                .navigationTitle("Soreness")
                .navigationBarTitleDisplayMode(.inline)
            }
            .task {
                // `withSession: true` since §W6, and it is load-bearing. The
                // tile now draws TWO channels — the modelled fatigue as a fill,
                // the reported soreness as a ring — and the default fixture
                // logs no session at all, so the first shot of the composite
                // photographed a body with rings on it and nothing underneath.
                // A screen whose new half is invisible in its own review shot is
                // a screen that gets reviewed as though the half were missing.
                if model == nil { model = PulsePreviews.fullDay(withSession: true) }
                await model?.observe()
            }
        }
    }

    /// A screen the tab PUSHES, rendered on its own. It needs the model's
    /// streams running — `PulseTabView` is what normally starts them, and a
    /// pushed screen photographed without it draws the seed protocol instead of
    /// the store's own stack.
    private struct Observing<Content: View>: View {
        /// `@State`, not a `let`: the harness rebuilds this view's arguments on
        /// every pass, so a stored model would be a NEW in-memory database each
        /// time and the streams would restart against a store the previous
        /// render seeded. The first one wins and keeps its rows.
        @State private var model: DayModel
        @ViewBuilder let content: (DayModel) -> Content

        init(model: DayModel, @ViewBuilder content: @escaping (DayModel) -> Content) {
            _model = State(initialValue: model)
            self.content = content
        }

        var body: some View {
            NavigationStack { content(model) }
                .task { await model.observe() }
        }
    }

    /// A screen with one of its sheets already up.
    ///
    /// ── `@State`, FOR THE SAME REASON `Observing` IS ────────────────────────
    /// The harness re-evaluates its switch on every observation tick, so a
    /// `let model` was a NEW in-memory database on every pass — and the sheet
    /// then rendered against a `DayModel` whose streams had never been started,
    /// while `PulseTabView`'s own `@State` kept the first one. Sheets that read
    /// the store synchronously (the InBody form's `latestBodyReading`) survived
    /// that; the two §U5 sheets read STREAMED state — `night`, and the window
    /// read behind `stressBreakdown` — and photographed "No sleep recorded" and
    /// "No reading" over a tile that was showing both.
    ///
    /// One model, held, observed here as well as by the tab: `observe()` guards
    /// re-entry, so the second call costs nothing and the sheet cannot be the
    /// one surface with no streams behind it.
    private struct Presenting<Sheet: View>: View {
        @State private var model: DayModel
        @ViewBuilder let sheet: (DayModel) -> Sheet
        @State private var shown = true

        init(model: DayModel, @ViewBuilder sheet: @escaping (DayModel) -> Sheet) {
            _model = State(initialValue: model)
            self.sheet = sheet
        }

        var body: some View {
            NavigationStack { PulseTabView(seeded: model) }
                .sheet(isPresented: $shown) { sheet(model) }
                .task { await model.observe() }
        }
    }
}

#Preview("Pulse — full") { PulsePreviews.view("day") }
#Preview("Pulse — past") { PulsePreviews.view("day-past") }
#Preview("Pulse — empty") { PulsePreviews.view("day-empty") }
#Preview("Pulse — InBody") { PulsePreviews.view("scale") }
#Preview("Pulse — swap") { PulsePreviews.view("day-swap") }
#Preview("Pulse — sleep edit") { PulsePreviews.view("sleep-edit") }
#Preview("Pulse — stress") { PulsePreviews.view("stress") }
#Preview("Pulse — fatigue") { PulsePreviews.view("fatigue") }
#Preview("Pulse — stress log") { PulsePreviews.view("stress-log") }
#Preview("Pulse — stress day") { PulsePreviews.view("stress-day") }
#Preview("Pulse — carousel") { PulsePreviews.view("day-stress") }
#Preview("Pulse — a promoted vital") { PulsePreviews.view("day-hero") }
#Preview("Pulse — two sessions") { PulsePreviews.view("day-two") }
#Preview("Quick Log") { PulsePreviews.view("quick-log") }
#endif
