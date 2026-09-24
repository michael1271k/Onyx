import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// The App Group read path: the builder that replaced `/api/widget/snapshot`,
/// and the store surface the widget extension needs to reach it.
@Suite("Widget snapshot builder")
struct WidgetSnapshotBuilderTests {
    private let user = "u1"
    /// Thursday 2026-09-03 15:00 UTC — `cb_b` (Upper B) on the onyx5 week.
    private let now = Date(timeIntervalSince1970: 1_788_447_600)
    private let today = "2026-09-03"
    private let utc = TimeZone(identifier: "UTC")!

    private func seeded() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let t = now
        try db.writer.write { conn in
            try ProfileRow(userId: user, role: "athlete", updatedAt: t, createdAt: t).insert(conn)
            try UserGoalRow(
                id: "g1", userId: user, sleepGoalHours: 7.5, calorieGoal: 2000, proteinGoalG: 180,
                stepsGoal: 10_000, waterGoalMl: 3000, contextMode: "normal", createdAt: t, updatedAt: t,
                autoLogSupplements: false, activeProgram: "onyx5", dayCutoffHour: 4, unitSystem: "metric",
                reduceMotion: false, timezone: "UTC", targetWeightKg: 80, activePlan: "onyx5",
                activePhase: "cut", trackRpe: true,
                // `custom` resolves to itself and applies no preset, so the
                // stored calorie goal survives whatever lever the calendar holds.
                activeLever: "custom"
            ).insert(conn)
            // The catalogue as rows (W2): plans, the ONYX-5 routines, phases.
            try SampleDeck.seedCatalogue(conn, userId: user)
            // A swap: Wednesday (rest) trains Delts & Arms.
            try ScheduleOverrideRow(userId: user, date: "2026-09-02", dayKey: "arms", updatedAt: t).insert(conn)

            try Exercise(id: "ex-squat", name: "Back Squat", primaryMuscle: "quads").insert(conn)
            for (id, day, key) in [("s-prev", "2026-08-27", "cb_b"), ("s-mon", "2026-08-31", "legs_a"), ("s-today", today, "cb_b")] {
                try WorkoutSession(id: id, userId: user, dayKey: key, date: day, startedAt: t, durationMin: 50, sessionRpe: 8).insert(conn)
            }
            try WorkoutSet(id: "p1", sessionId: "s-prev", exerciseId: "ex-squat", setIndex: 0, weightKg: 90, reps: 5).insert(conn)
            try WorkoutSet(id: "m1", sessionId: "s-mon", exerciseId: "ex-squat", setIndex: 0, weightKg: 100, reps: 5).insert(conn)
            try WorkoutSet(id: "m2", sessionId: "s-mon", exerciseId: "ex-squat", setIndex: 1, weightKg: 100, reps: 5).insert(conn)
            try WorkoutSet(id: "t1", sessionId: "s-today", exerciseId: "ex-squat", setIndex: 0, weightKg: 105, reps: 5).insert(conn)
            try PersonalRecordRow(userId: user, exerciseKey: "Back Squat", axis: "weight", value: 105, reps: 5,
                                  sessionId: "s-today", achievedOn: today).insert(conn)

            try NutritionEntryRow(id: "n1", userId: user, loggedAt: t, date: today, mealType: "daily",
                                  calories: 1850, proteinG: 170, carbsG: 150, fatG: 60, createdAt: t).insert(conn)
            try NutritionEntryRow(id: "n0", userId: user, loggedAt: t, date: "2026-09-02", mealType: "daily",
                                  calories: 1900, proteinG: 170, carbsG: 150, fatG: 60, createdAt: t).insert(conn)
            try WaterIntakeRow(id: "w1", userId: user, loggedAt: t, date: today, amountMl: 500, createdAt: t).insert(conn)
            try WaterIntakeRow(id: "w2", userId: user, loggedAt: t, date: today, amountMl: 1000, createdAt: t).insert(conn)
            try DailyMetricRow(id: "dm1", userId: user, date: today, steps: 8000, activeCal: 420, createdAt: t, updatedAt: t).insert(conn)
            // Logs: today's HRV is excluded from its own baseline.
            for (i, hrv, steps) in [(0, 100.0, 7000), (1, 40.0, 6000), (2, 60.0, 9000)] {
                try DailyLogRow(id: "dl\(i)", userId: user, date: ISODate.addDays(today, -i)!, steps: steps,
                                createdAt: t, updatedAt: t, hrvMs: hrv, distanceM: 5000,
                                nutritionEstimated: false, sleepOnsetTrouble: false).insert(conn)
            }
            let night = try #require(NightWindow.range(today))
            try SleepSessionRow(id: "sl1", userId: user, startTime: night.from.addingTimeInterval(10 * 3600),
                                endTime: night.to.addingTimeInterval(-4 * 3600), durationMin: 420, deepMin: 70, createdAt: t).insert(conn)
            // Weigh-ins: an identical re-synced reading is not a fresh weigh-in.
            for (i, day, kg, fat) in [(0, today, 82.4, 18.0), (1, "2026-09-02", 82.4, 18.2), (2, "2026-09-01", 83.0, 18.5), (3, "2026-08-25", 84.0, 19.0)] {
                try BodyCompositionRow(id: "bc\(i)", userId: user, measuredAt: t, date: day, weightKg: kg,
                                       bodyFatPct: fat, createdAt: t, skeletalMuscleMassKg: 27).insert(conn)
            }
            try CardioLogRow(id: "c1", userId: user, date: "2026-08-31", kind: "Run", distanceM: 5000, durationMin: 30, createdAt: t).insert(conn)
            try CardioLogRow(id: "c2", userId: user, date: today, kind: "Walk", distanceM: 2000, durationMin: 15, createdAt: t).insert(conn)
        }
        return db
    }

    private func build(_ db: AppDatabase, _ scope: OnyxScope) throws -> OnyxSnapshot {
        try WidgetSnapshotBuilder(database: db, userId: user, timeZone: utc).build(scope: scope, now: now)
    }

    // ── A PHONE-LOGGED SET IS A SLUG, NOT A UUID ────────────────────────────
    // `LoggerModel.exerciseId` stamps `onyx-<slug>` on every set logged on
    // the phone, and `applyPulledSets` never repairs a session that has local
    // events — so the slug is the id that set keeps. `exerciseNames` used to be
    // the catalogue alone, which only ever holds server uuids, and every
    // phone-logged set was dropped from muscle credit. "Side delts 0/7" after a
    // logged Upper B was this: the lateral raise was the only side-delt source.
    @Test("a phone-logged slug set credits its landmark on the sheet AND the tile")
    func slugSetsCountTowardsMuscleCredit() throws {
        let db = try seeded()
        try db.writer.write { conn in
            // The slug resolves through the catalogue's `slug` column (W2).
            try Exercise(id: "ex-lat", name: "Single Arm Lateral Raise", slug: ExerciseSlug.id("Single Arm Lateral Raise")).save(conn)
            try WorkoutSet(
                id: "t-lat", sessionId: "s-today", exerciseId: ExerciseSlug.id("Single Arm Lateral Raise"),
                setIndex: 1, weightKg: 5, reps: 15
            ).insert(conn)
        }

        let feed = try TodayFeedBuilder(database: db, userId: user, timeZone: utc).build(now: now)
        let sideDelts = feed.muscleFocus.rows.first { $0.muscle == .sideDelts }
        #expect(sideDelts?.sets == 1, "the sheet credits the slug set")

        // The tile reads the same sixteen and rolls them up to eight. One
        // accumulator (F7): the sheet's Side delts row and the tile's Shoulders
        // bar are now the same arithmetic, not two that happen to agree.
        let payload = try #require(build(db, .full).muscleFocus)
        #expect(payload.first { $0.muscle == "Side delts" }?.sets == 1, "the tile credits the slug set")
        let families = try build(db, .full).volumeByFamily
        #expect(families.contains { $0.family == .shoulders && $0.sets == 1 }, "the tile agrees: \(families)")
    }

    /// Overhaul B2: the Fuel faces' key micros are summed from the day's rows
    /// the way `NutritionModel.nutrients` sums them.
    @Test("key-micro totals sum fibre and every row's micros bundle")
    func microTotals() {
        let at = Date(timeIntervalSince1970: 1_757_000_000)
        func row(_ id: String, fiber: Double?, micros: String?) -> NutritionEntryRow {
            NutritionEntryRow(
                id: id, userId: "u", loggedAt: at, date: today, calories: 500, proteinG: 30,
                carbsG: 50, fatG: 10, fiberG: fiber, createdAt: at, micros: micros.map { JSONText(raw: $0) }
            )
        }
        let totals = WidgetSnapshotBuilder.microTotals([
            row("a", fiber: 8, micros: #"{"potassium": 900, "sodium": 1200}"#),
            row("b", fiber: nil, micros: #"{"potassium": 494}"#),
            row("c", fiber: 4, micros: "not json"),
        ])
        #expect(totals["potassium"] == 1394)
        #expect(totals["sodium"] == 1200)
        #expect(totals["fiber"] == 12)
        #expect(KeyMicro.top(totals: totals).first?.key == "potassium")
    }

    @Test("the full scope carries the route's headline numbers")
    func fullScope() throws {
        let s = try build(try seeded(), .full)

        #expect(s.date == today)
        #expect(s.generatedAt == "2026-09-03T15:00:00.000Z")
        #expect(s.scope == "full")

        #expect(s.macros.kcal == 1850)
        #expect(s.macros.kcalGoal == 2000)
        #expect(s.macros.proteinGoalG == 180)
        #expect(s.water.ml == 1500)
        #expect(s.water.goalMl == 3000)
        #expect(s.steps.count == 8000, "daily_metrics wins over the log")
        #expect(s.steps.goal == 10_000)
        #expect(s.steps.distanceM == 5000)
        #expect(s.steps.trend?.count == 3)

        #expect(s.weight.kg == 82.4)
        #expect(s.weight.deltaKg == -0.6, "skips the identical reading back to 83.0")
        #expect(s.weight.measuredOn == today)
        #expect(s.weight.targetKg == 80)

        #expect(s.sleep.minutes == 420)
        #expect(s.sleep.goalMin == 450)

        // Sunday-start week from 2026-08-30: Monday legs + today's Upper B.
        #expect(s.week.sessions == 2)
        // `Double(...)` is load-bearing, not noise. `volumeKg` is `Double?`
        // since W1, and `#expect` binds each operand's type on its own: an
        // integer *expression* on the right settles as `Int` and the
        // comparison is then never true, while reporting both sides as 1525.
        // A bare literal would infer `Double` and pass; `1000 + 525` does not.
        #expect(s.week.volumeKg == Double(1000 + 525))
        #expect(s.week.sets == 3)
        #expect(s.week.prs == 1)
        #expect(s.week.sessionTarget == 5)
        #expect(s.weekPrev?.sessions == 1)
        #expect(s.weekPrev?.volumeKg == 450)

        // A week with nothing in it has no tonnage — not a tonnage of zero.
        // `reduce(0)` over no sessions printed "0.0 t" on Monday morning, on a
        // fresh install, and throughout the casing bug that hid every synced
        // session from the query. Counts stay zero: none of those DID happen.
        let empty = WidgetSnapshotBuilder.totals([])
        #expect(empty.volumeKg == nil)
        #expect(empty.sessions == 0 && empty.sets == 0 && empty.prs == 0)

        #expect(s.workout.label == "Upper B")
        #expect(s.workout.dayKey == "cb_b")
        #expect(s.workout.logged)
        #expect(!s.workout.isRestDay)
        #expect((s.workout.plannedSets ?? 0) > 0)
        #expect(s.workout.lastVolumeKg == 450, "the last Upper B, not today's own")
        #expect(s.today?.volumeKg == 525)
        #expect(s.today?.prCount == 1)
        #expect(s.today?.durationMin == 50)

        // Jul 24 (42 days back) through Sep 30 (end of month).
        let calendar = try #require(s.calendar)
        #expect(calendar.count == 69)
        #expect(calendar.first?.d == "2026-07-24")
        #expect(calendar.last?.d == "2026-09-30")
        let swapped = try #require(calendar.first { $0.d == "2026-09-02" })
        #expect(swapped.scheduled && swapped.dayKey == "arms", "the override, not the weekday")
        #expect(calendar.first { $0.d == today }?.logged == true)

        let cardio = try #require(s.cardio)
        #expect(cardio.weekSessions == 1, "Zone 2 is a count of sessions over 20 min")
        #expect(cardio.weekMinutes == 45)
        #expect(cardio.last?.kind == "Walk")

        let hrv = try #require(s.vitals?.hrvMs)
        #expect(hrv.value == 100)
        #expect(hrv.baseline == 50, "today is not in its own baseline")

        let e1rm = try #require(s.e1rm?.first)
        #expect(e1rm.exercise == "Back Squat")
        #expect(e1rm.trend?.count == 3)
        #expect(e1rm.kg == (OneRepMax.estimate(weight: 105, reps: 5)! * 10).rounded() / 10)
        #expect(s.records?.first?.exercise == "Back Squat")
        #expect(s.volumeTrend?.count == 2)

        #expect(s.body?.smmKg == 27)
        #expect(s.body?.fatPct == 18)
        #expect(s.body?.fatPctDelta == -0.2)
        // The active plan's `started_on` row (seeded 2026-07-15) is day 1.
        #expect(s.streak?.current == Streak.programDayCount(today, startISO: "2026-07-15"))
        #expect(s.context == nil)

        // Recomputed locally, not read from a (missing) daily_scores row.
        #expect(s.score != nil)
        #expect(s.battery != nil)
        #expect(s.scores?.sleep != nil)
        #expect(s.readiness != nil)

        // ── The sprint's W4 faces ────────────────────────────────────────
        let rings = try #require(s.weekRings)
        #expect(rings.count == 7)
        #expect(rings.first?.date == "2026-08-28" && rings.last?.date == today)
        // Nothing rated today is an EMPTY array, not a nil one: "nothing
        // hurts" is an answer and "nobody asked" is not the same statement.
        #expect(s.soreness == [])
        #expect(s.stress?.series14.count == 14)
        // One night in the store and it is TONIGHT's, so the baseline has
        // nothing before the window to take a median of.
        #expect(s.sleep.medianBedtime == nil)
    }

    // ── OVERHAUL W5.3: the finished Medium's heart-rate band ────────────────

    @Test("today's spark is the telemetry cache in six points, and empty (no key) without one")
    func todaySparkFromTheCache() throws {
        let db = try seeded()
        #expect(try build(db, .full).today?.spark == [])
        #expect(try build(db, .full).today?.hrSpark == nil, "an empty spark stays off the wire")

        let samples = (0..<12).map { HRSample(at: now.addingTimeInterval(Double($0) * 60), bpm: 110 + $0) }
        try db.writeTelemetryCache(sessionId: "s-today", samples: samples, segments: [], source: "health", fetchedAt: now)
        let spark = try #require(try build(db, .full).today?.spark)
        #expect(spark == SessionMasthead.spark(samples.map { Double($0.bpm) }))
        #expect(spark.count == 6)
    }

    @Test("a Today payload written before hrSpark existed still decodes")
    func todayWithoutSparkDecodes() throws {
        let old = #"{"durationMin":68,"volumeKg":5840,"prCount":2}"#
        let today = try JSONDecoder().decode(OnyxSnapshot.Today.self, from: Data(old.utf8))
        #expect(today.spark == [] && today.durationMin == 68)
    }

    // ── THE SPRINT'S W4 FACES ───────────────────────────────────────────────

    @Test("the week's rings count the days the goals were actually met")
    func weekRingsCountWhatHappened() throws {
        let db = try seeded()
        try db.writer.write { conn in
            // A night that CLEARS the 7.5 h goal, on the night of Aug 31 — the
            // seed's only other night is tonight's 7 h, which misses it, so
            // without this the sleep row would be seven falses and prove only
            // that `false` renders.
            let night = try #require(NightWindow.range("2026-08-31"))
            try SleepSessionRow(id: "sl-long", userId: user, startTime: night.from.addingTimeInterval(10 * 3600),
                                endTime: night.to.addingTimeInterval(-2 * 3600), durationMin: 480, createdAt: now).insert(conn)
        }
        let rings = try #require(build(db, .full).weekRings)
        func day(_ d: String) throws -> OnyxSnapshot.WeekRingDay { try #require(rings.first { $0.date == d }) }

        // Sessions on Aug 31 (Legs A) and today. Aug 27's is outside the week.
        #expect(try day("2026-08-31").trained)
        #expect(try day(today).trained)
        #expect(try !day("2026-09-01").trained)

        // 1850 and 1900 against a 2000 goal are both inside the tenth; a day
        // with nothing logged is a miss, which is the rule `WeekRingDay`
        // states and the only place this payload does not treat missing as nil.
        #expect(try day(today).fuelHit, "1850 of 2000")
        #expect(try day("2026-09-02").fuelHit, "1900 of 2000")
        #expect(try !day("2026-09-01").fuelHit, "nothing logged is not a hit")

        #expect(try day("2026-08-31").sleepHit, "480 min clears the 450 goal")
        #expect(try !day(today).sleepHit, "420 min does not")
    }

    /// The tile paints the atlas's sixteen; the user taps one of ten words.
    @Test("a rated group lights every landmark it covers, at the worst of its rows")
    func sorenessFansOutToLandmarks() throws {
        let db = try seeded()
        try db.writer.write { conn in
            // One shoulder rated on each side, differently: max within the
            // group, never a mean — "left severe, right fine" is a severe
            // shoulder, and averaging it reports a day nobody had.
            try DomsLogRow(id: "d1", userId: user, date: today, muscleGroup: "Shoulders", severity: 1,
                           createdAt: now, side: "left", subRegion: "").insert(conn)
            try DomsLogRow(id: "d2", userId: user, date: today, muscleGroup: "Shoulders", severity: 3,
                           createdAt: now, side: "right", subRegion: "").insert(conn)
            try DomsLogRow(id: "d3", userId: user, date: today, muscleGroup: "Quads", severity: 2,
                           createdAt: now, side: "both", subRegion: "").insert(conn)
            // Rated None — the array is what is SORE.
            try DomsLogRow(id: "d4", userId: user, date: today, muscleGroup: "Calves", severity: 0,
                           createdAt: now, side: "both", subRegion: "").insert(conn)
            // A word the vocabulary does not know can never be read back as a
            // rating (`DomsMuscles.recognised`) — the same guard the scorer's
            // fold applies, for the same reason.
            try DomsLogRow(id: "d5", userId: user, date: today, muscleGroup: "Tail", severity: 3,
                           createdAt: now, side: "both", subRegion: "").insert(conn)
            // Yesterday's rating is yesterday's.
            try DomsLogRow(id: "d6", userId: user, date: "2026-09-02", muscleGroup: "Chest", severity: 3,
                           createdAt: now, side: "both", subRegion: "").insert(conn)
        }
        let s = try build(db, .full)
        let sore = try #require(s.soreness)
        let byLandmark = Dictionary(sore.map { ($0.landmark, $0.level) }, uniquingKeysWith: { a, _ in a })

        #expect(byLandmark["Front delts"] == 3)
        #expect(byLandmark["Side delts"] == 3)
        #expect(byLandmark["Rear delts"] == 3)
        #expect(byLandmark["Quads"] == 2)
        #expect(byLandmark["Calves"] == nil)
        #expect(byLandmark["Chest"] == nil, "yesterday's rating is yesterday's")
        #expect(sore.count == 4)
        // `allCases` order, so the face's list does not shuffle between two
        // refreshes that read the same rows.
        #expect(sore.map(\.landmark) == ["Front delts", "Side delts", "Rear delts", "Quads"])

        // And the figure takes it as 0…1 over the vocabulary's own maximum —
        // the identical shape `muscleWorked` hands the same view.
        #expect(s.soreWorked["Side delts"] == 1)
        #expect(s.soreWorked["Quads"] == 2.0 / 3.0)
    }

    /// The regularity baseline, made visible — W3 scored against it and no
    /// surface printed it.
    @Test("the usual bedtime is a local clock time, and needs five nights to exist")
    func medianBedtimeIsAClock() throws {
        // Six nights before tonight's window, at 22:00, 22:00, 22:30, 21:30,
        // 23:00 and 21:00 UTC — a median of exactly ten hours past the night's
        // opening noon. Not all equal, so this pins the MEDIAN rather than the
        // newest row.
        func seedNights(_ db: AppDatabase, offsetsMin: [Double]) throws {
            try db.writer.write { conn in
                for (i, offset) in offsetsMin.enumerated() {
                    let night = ISODate.addDays("2026-09-02", -i)!
                    let window = try #require(NightWindow.range(night))
                    try SleepSessionRow(
                        id: "bn\(i)", userId: user,
                        startTime: window.from.addingTimeInterval(offset * 60),
                        endTime: window.from.addingTimeInterval(offset * 60 + 7 * 3600),
                        durationMin: 420, createdAt: now
                    ).insert(conn)
                }
            }
        }

        let four = try seeded()
        try seedNights(four, offsetsMin: [600, 600, 630, 570])
        #expect(try build(four, .full).sleep.medianBedtime == nil, "four nights is not a usual")

        let six = try seeded()
        try seedNights(six, offsetsMin: [600, 600, 630, 570, 660, 540])
        #expect(try build(six, .full).sleep.medianBedtime == "22:00")

        // The same store read from a phone three hours east prints the local
        // clock, not the UTC one. A bedtime read in UTC in Jerusalem is three
        // hours wrong, every night.
        let east = try WidgetSnapshotBuilder(
            database: six, userId: user, timeZone: TimeZone(secondsFromGMT: 3 * 3600)!
        ).build(scope: .full, now: now)
        #expect(east.sleep.medianBedtime == "01:00")
    }

    @Test("the three W4 blocks are body-scope; the bedtime is on every payload")
    func w4ScopeGating() throws {
        let db = try seeded()
        for scope in [OnyxScope.lifestyle, .performance, .training] {
            let s = try build(db, scope)
            #expect(s.weekRings == nil, "\(scope) carries no week")
            #expect(s.soreness == nil, "\(scope) carries no soreness")
            #expect(s.stress == nil, "\(scope) carries no stress")
        }
        let body = try build(db, .body)
        #expect(body.weekRings?.count == 7)
        #expect(body.soreness != nil)
        #expect(body.stress != nil)
    }

    @Test("lifestyle keeps its own quarter and nothing else")
    func lifestyleScope() throws {
        let s = try build(try seeded(), .lifestyle)
        #expect(s.steps.trend != nil && s.vitals != nil && s.water.trend != nil && s.macros.kcalTrend != nil && s.weight.trend != nil)
        #expect(s.records == nil && s.e1rm == nil && s.muscleFocus == nil && s.volumeTrend == nil)
        #expect(s.calendar == nil && s.cardio == nil)
        #expect(s.body == nil && s.scores == nil && s.readiness == nil && s.sleep.trend == nil)
    }

    @Test("performance keeps records, 1RM and the family split")
    func performanceScope() throws {
        let s = try build(try seeded(), .performance)
        #expect(s.records != nil && s.e1rm != nil && s.muscleFocus != nil && s.volumeTrend != nil)
        #expect(s.steps.trend == nil && s.vitals == nil && s.water.trend == nil && s.weight.trend == nil)
        #expect(s.calendar == nil && s.cardio == nil && s.body == nil && s.scores == nil)
    }

    @Test("training keeps the calendar, cardio and the volume trend")
    func trainingScope() throws {
        let s = try build(try seeded(), .training)
        #expect(s.calendar != nil && s.cardio != nil && s.volumeTrend != nil)
        #expect(s.records == nil && s.e1rm == nil && s.vitals == nil && s.body == nil && s.weight.trend == nil)
    }

    @Test("body keeps composition, scores, readiness and the sleep trend")
    func bodyScope() throws {
        let s = try build(try seeded(), .body)
        #expect(s.body != nil && s.scores != nil && s.readiness != nil && s.sleep.trend != nil && s.weight.trend != nil)
        #expect(s.calendar == nil && s.cardio == nil && s.records == nil && s.vitals == nil && s.volumeTrend == nil && s.steps.trend == nil)
    }

    /// The bug W13 found: `rows.weights` is `limit(30)` with NO date filter,
    /// because the Weight face needs the latest reading however old it is.
    /// Handing those same rows to a least-squares fit is a different thing —
    /// weigh-ins are sparse by protocol, so thirty of them reach back months,
    /// and a distant point has enormous leverage on the rate, the pace verdict
    /// and the ETA that print on BOTH the Today Goal Board row and the
    /// Trajectory tile.
    ///
    /// A reading from before `historyStart` must therefore change nothing. The
    /// scale face must still see it, which is the other half of the rule.
    @Test("a weigh-in older than the window moves the trajectory not at all")
    func trajectoryIsBounded() throws {
        let db = try seeded()
        let before = try #require(try build(db, .body).trajectory)

        // Six months back and eleven kilos heavier: unbounded, this drags the
        // rate towards zero and the arrival date out by months.
        try db.writer.write { conn in
            try BodyCompositionRow(
                id: "bc-ancient", userId: user, measuredAt: now, date: "2026-03-10",
                weightKg: 95, bodyFatPct: 26, createdAt: now, skeletalMuscleMassKg: 27
            ).insert(conn)
        }
        let after = try #require(try build(db, .body).trajectory)

        #expect(after.points.count == before.points.count, "an out-of-window reading is not a point on the line")
        #expect(after.board.ratePerWeekKg == before.board.ratePerWeekKg)
        #expect(after.board.etaISO == before.board.etaISO)
        #expect(after.board.pace == before.board.pace)
        #expect(after.latestEwmaKg == before.latestEwmaKg)

        // …and the face that reads the ledger directly still sees it, because
        // the bound is on the fit and not on the fetch.
        let weight = try build(db, .body).weight
        #expect(weight.kg != nil, "the scale face still has a reading")
    }

    @Test("an empty store still answers, with nil where the route sent null")
    func emptyStore() throws {
        let db = try AppDatabase.inMemory()
        let s = try build(db, .full)
        #expect(s.macros.kcal == nil && s.water.ml == nil && s.steps.count == nil)
        #expect(s.weight.kg == nil && s.today == nil && s.week.sessions == 0)
        // No `routines` rows, no deck: an empty store is a rest day everywhere
        // (W2 — the compiled Upper B used to answer here).
        #expect(s.workout.label == "Rest")
        #expect(s.readiness == nil, "no battery, no verdict")
    }

    @Test("knownUserId is the one user the mirror holds")
    func knownUser() throws {
        #expect(try AppDatabase.inMemory().knownUserId() == nil)
        #expect(try seeded().knownUserId() == user)
    }

    @Test("onCommit fires after a local write")
    func commitObserver() async throws {
        let db = try AppDatabase.inMemory()
        let (fired, continuation) = AsyncStream<Void>.makeStream()
        let observer = db.onCommit { continuation.yield() }
        try await db.writer.write { try Exercise(id: "e", name: "Row").insert($0) }
        var iterator = fired.makeAsyncIterator()
        _ = await iterator.next()
        _ = observer
    }

    @Test("a read-only connection reads the app's file and refuses to write")
    func readOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "onyx-ro-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: AppDatabase.OpenError.missingDatabase(folder.appendingPathComponent("onyx.sqlite").path)) {
            try AppDatabase.readOnly(folderURL: folder)
        }
        let app = try AppDatabase.onDisk(folderURL: folder)
        try app.writer.write { try Exercise(id: "e", name: "Row").insert($0) }

        let widget = try AppDatabase.readOnly(folderURL: folder)
        #expect(try widget.exercises().count == 1)
        #expect(throws: (any Error).self) {
            try widget.writer.write { try Exercise(id: "f", name: "Press").insert($0) }
        }
    }

    @Test("the store moves into the App Group folder once, WAL and SHM included")
    func migratesOldStore() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "onyx-mv-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let old = base.appending(path: "old"), new = base.appending(path: "new")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            try Data("x".utf8).write(to: old.appendingPathComponent("onyx.sqlite" + suffix))
        }
        AppDatabase.moveStoreIfNeeded(from: old, to: new)
        for suffix in ["", "-wal", "-shm"] {
            #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("onyx.sqlite" + suffix).path))
            #expect(!FileManager.default.fileExists(atPath: old.appendingPathComponent("onyx.sqlite" + suffix).path))
        }
        // Second run: nothing to move, nothing overwritten.
        try Data("y".utf8).write(to: old.appendingPathComponent("onyx.sqlite"))
        AppDatabase.moveStoreIfNeeded(from: old, to: new)
        #expect(try String(contentsOf: new.appendingPathComponent("onyx.sqlite"), encoding: .utf8) == "x")
    }

    // The companion test — "a store written under the predecessor's name is
    // adopted under the new one" — was deleted in 7.0.0 with the code it
    // covered. See `AppDatabase.adoptLegacyStores`: that path could not
    // survive a purge of the name it hunted for, and it had never fired.
    // `moveStoreIfNeeded` above is the surviving half and still carries the
    // WAL/SHM rule and the never-overwrite rule, which were the parts with
    // teeth.

    // ══ W6 ═══════════════════════════════════════════════════════════════════

    // ── THE DECK'S MUSCLES ARE THE PLAN'S, NOT THE SESSION'S ────────────────
    // `workout.muscles` washes the Today tile, and the tile has to be right at
    // 07:00 on a day nothing has been logged on. It therefore reads the PLAN —
    // which also means it survives the session being finished, because a deck's
    // muscles do not change when you tick its last set.
    @Test("the day's deck names its muscles, in deck order, on a due day and a done one")
    func deckMusclesFollowThePlan() throws {
        let db = try seeded()
        let due = try build(db, .training).workout
        let muscles = try #require(due.muscles)
        #expect(!muscles.isEmpty, "Upper B trains something")
        #expect(muscles.count == Set(muscles).count, "each muscle named once")
        #expect(muscles.allSatisfy { LandmarkMuscle(rawValue: $0) != nil },
                "every token is a landmark the figure can paint: \(muscles)")
        // `landmarks` is what the wash actually reads.
        #expect(due.landmarks.map(\.rawValue) == muscles)
        // Today already HAS a session in the fixture, so this is the done state
        // and the answer is the same one.
        #expect(try build(db, .full).workout.muscles == muscles)
    }

    // A rest day plans nothing, and a wash with no hues draws nothing. Nil and
    // not `[]`: the face's own rule is that absence has no colour.
    @Test("a rest day carries no muscles at all")
    func restDayHasNoMuscles() throws {
        let db = try seeded()
        try db.writer.write { conn in
            try ScheduleOverrideRow(userId: user, date: today, dayKey: Schedule.restOverride, updatedAt: now).insert(conn)
        }
        let workout = try build(db, .training).workout
        #expect(workout.isRestDay)
        #expect(workout.muscles == nil)
        #expect(workout.landmarks.isEmpty)
    }

    // ── THE MARGIN IS THE FLOOR, BECAUSE THE PREVIOUS ROW DOES NOT EXIST ────
    // `personal_records` is UNIQUE on (user_id, exercise_key, axis) — the first
    // thing this test proved, and the reason `Record.previous` is
    // `floor_value` and not "the row before". A beaten record is overwritten;
    // the bar it cleared is what survives.
    @Test("the standing record carries the bar it cleared, and a first record carries nothing")
    func recordsCarryTheFloorTheyCleared() throws {
        let db = try seeded()
        try db.writer.write { conn in
            // The natural key refuses a second row on the same lift and axis.
            #expect(throws: (any Error).self) {
                try PersonalRecordRow(userId: user, exerciseKey: "Back Squat", axis: "weight", value: 100,
                                      reps: 5, sessionId: "s-mon", achievedOn: "2026-08-31").insert(conn)
            }
            // What a beaten floor actually looks like: the row that replaced it
            // carries the old bar (`PrRecorder.carryFloor`).
            try PersonalRecordRow
                .filter(Column("exercise_key") == "Back Squat" && Column("axis") == "weight")
                .updateAll(conn, [Column("floor_value").set(to: 100)])
            // A second axis on the same lift, with nothing under it.
            try PersonalRecordRow(userId: user, exerciseKey: "Back Squat", axis: "reps", value: 12, reps: 12,
                                  sessionId: "s-today", achievedOn: today).insert(conn)
        }
        let records = try #require(build(db, .performance).records)

        let weight = try #require(records.first { $0.axis == "weight" })
        #expect(weight.previous == 100)
        #expect(weight.margin == 5, "105 kg stands five past the bar it cleared")

        let reps = try #require(records.first { $0.axis == "reps" })
        #expect(reps.previous == nil, "nothing stood before it")
        #expect(reps.margin == nil)
    }

    // A compiled floor can sit ABOVE a logged record — the book is asserted
    // from a history the phone never saw. That is not a negative gain, it is no
    // gain, and the face prints "first on the board" rather than "−5.0 kg".
    @Test("a record that did not clear its own floor reports no margin")
    func noMarginWithoutAnImprovement() throws {
        let db = try seeded()
        try db.writer.write { conn in
            try PersonalRecordRow
                .filter(Column("exercise_key") == "Back Squat" && Column("axis") == "weight")
                .updateAll(conn, [Column("floor_value").set(to: 110)])
        }
        let records = try #require(build(db, .performance).records)
        let weight = try #require(records.first { $0.axis == "weight" })
        #expect(weight.previous == 110, "the floor is carried whatever it says")
        #expect(weight.margin == nil, "105 did not clear a 110 bar")
    }

    // ── SEVEN BARS, ALWAYS, AND A HOLE IS NOT A ZERO ────────────────────────
    // A day missing intake, BMR or active energy contributes nothing to the
    // ledger, and the face draws no bar for it. Dropping the day instead would
    // shift every bar after it and put the wrong weekday under each one.
    @Test("the deficit face gets seven dated days, a day with a hole carrying nil")
    func deficitDaysAreSevenAndHonest() throws {
        let db = try seeded()
        try db.writer.write { conn in
            // Two complete days and one with no active energy at all.
            for (i, active) in [(0, 600.0 as Double?), (1, 550.0 as Double?), (2, nil as Double?)] {
                let date = ISODate.addDays(today, -i)!
                try DailyLogRow.filter(Column("id") == "dl\(i)").deleteAll(conn)
                // The seeded fixture already has a `daily` meal on some of
                // these dates, and `ledgerDays` keys intake by DATE — two rows
                // on one day is whichever came back last, which is not a test.
                try NutritionEntryRow.filter(Column("date") == date).deleteAll(conn)
                try DailyLogRow(
                    id: "dl\(i)", userId: user, date: date,
                    activeEnergy: active, bmr: 1600, createdAt: now, updatedAt: now,
                    nutritionEstimated: false, sleepOnsetTrouble: false
                ).insert(conn)
                try NutritionEntryRow(id: "nd\(i)", userId: user, loggedAt: now, date: date, mealType: "daily",
                                      calories: 2000, proteinG: 150, carbsG: 150, fatG: 60, createdAt: now).save(conn)
            }
        }
        let days = try #require(build(db, .lifestyle).deficitDays)
        #expect(days.count == 7, "seven bar positions, whatever the data")
        #expect(days.map(\.d) == (0..<7).reversed().map { ISODate.addDays(today, -$0)! },
                "oldest first, ending today")
        // The value is the LEDGER's own rule and not a literal: `Energy.tdee`
        // adds the thermic effect of the food on top of BMR and active energy,
        // so a hand-written 2000 − 2200 would be testing the wrong arithmetic
        // and would start failing the day the TEF coefficient moved.
        #expect(days.last?.kcal == DeficitLedgerSeries.dayBalanceKcal(
            DeficitDayIn(date: today, intakeKcal: 2000, bmrKcal: 1600, activeKcal: 600)))
        #expect((days.last?.kcal ?? 0) < 0, "a 2000 kcal day against a 2200+ expenditure is a deficit")
        #expect(days.first(where: { $0.d == ISODate.addDays(today, -2)! })?.kcal == nil,
                "a day with no active energy is nil, never zero")
    }

    // Scope-gated like every other optional, and `deficit` is its neighbour.
    @Test("the seven days ride with the ledger's own scope")
    func deficitDaysAreScoped() throws {
        let db = try seeded()
        #expect(try build(db, .training).deficitDays == nil)
        #expect(try build(db, .lifestyle).deficitDays?.count == 7)
        #expect(try build(db, .full).deficitDays?.count == 7)
    }

}

/// The widget's half of "the tab and the tile agree".
///
/// `WaterTruth` is the rule; this asserts the SNAPSHOT reproduces it over the
/// four shapes a day can be in. `WaterRowTests` asserts the same four against
/// `NutritionModel`. The two surfaces live in modules that cannot see each
/// other, so pinning both to the same oracle is what "they agree" can mean.
@Suite("Water: the tile reads the one truth")
struct WidgetWaterTruthTests {
    private let user = "u1"
    private let now = Date(timeIntervalSince1970: 1_788_447_600)
    private let today = "2026-09-03"
    private let utc = TimeZone(identifier: "UTC")!

    private func snapshot(log: Double?, ledger: [Double]) throws -> Double? {
        let db = try AppDatabase.inMemory(deviceId: "water-\(UUID().uuidString)")
        try db.writer.write { conn in
            if let log {
                try DailyLogRow(
                    id: "dl", userId: user, date: today, waterMl: log,
                    createdAt: now, updatedAt: now,
                    nutritionEstimated: false, sleepOnsetTrouble: false
                ).insert(conn)
            }
            for (i, ml) in ledger.enumerated() {
                try WaterIntakeRow(
                    id: "w\(i)", userId: user, loggedAt: now, date: today,
                    amountMl: ml, createdAt: now
                ).insert(conn)
            }
        }
        return try WidgetSnapshotBuilder(database: db, userId: user, timeZone: utc)
            .build(scope: .full, now: now).water.ml
    }

    @Test("all four shapes, against the rule itself")
    func agreesWithWaterTruth() throws {
        for (log, ledger) in [
            (500.0 as Double?, [500.0, 250, 250]),  // the ledger leads
            (1750.0 as Double?, [] as [Double]),    // no ledger: the flat row
            (nil as Double?, [] as [Double]),       // nothing: nil, not zero
            (0.0 as Double?, [] as [Double]),       // a stored zero is untracked
        ] {
            #expect(try snapshot(log: log, ledger: ledger) == WaterTruth.ml(log: log, ledger: ledger),
                    "log \(String(describing: log)) ledger \(ledger)")
        }
    }
}
