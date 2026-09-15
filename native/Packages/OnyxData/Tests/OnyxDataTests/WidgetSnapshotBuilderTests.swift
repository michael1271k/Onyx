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
                autoLogSupplements: false, activeProgram: "helix5", dayCutoffHour: 4, unitSystem: "metric",
                reduceMotion: false, timezone: "UTC", targetWeightKg: 80, activePlan: "helix5",
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
    // `LoggerModel.exerciseId` stamps `helix5-<slug>` on every set logged on
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

    /// W2 renamed the container, the folder AND the file in one commit. A
    /// device that ran the previous build has `Helix/helix.sqlite` with real
    /// unsynced sets in it, and an app that just opened a fresh
    /// `Onyx/onyx.sqlite` beside it would look like a factory reset.
    @Test("a store written under the old name is adopted under the new one")
    func adoptsLegacyStore() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "onyx-legacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let old = base.appending(path: "Helix"), new = base.appending(path: "Onyx")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            try Data("history".utf8).write(to: old.appendingPathComponent("helix.sqlite" + suffix))
        }

        AppDatabase.adoptLegacyStore(into: new, from: old)

        for suffix in ["", "-wal", "-shm"] {
            #expect(try String(contentsOf: new.appendingPathComponent("onyx.sqlite" + suffix), encoding: .utf8) == "history")
            #expect(!FileManager.default.fileExists(atPath: old.appendingPathComponent("helix.sqlite" + suffix).path))
        }

        // A second launch must not resurrect a stale copy over the live store.
        try Data("stale".utf8).write(to: old.appendingPathComponent("helix.sqlite"))
        AppDatabase.adoptLegacyStore(into: new, from: old)
        #expect(try String(contentsOf: new.appendingPathComponent("onyx.sqlite"), encoding: .utf8) == "history")
    }
}
