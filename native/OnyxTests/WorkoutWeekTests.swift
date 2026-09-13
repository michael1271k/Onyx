import Testing
import GRDB
import OnyxCore
import OnyxData
@testable import Onyx

/// The Workout tab's read, and the one claim the Wave 2.8 gate makes about it:
/// finishing a session updates the tab, the week panel and the library from the
/// STORE, with no relaunch and nothing cached in a view.
///
/// ── WHY THIS IS A TEST AND NOT A SCREENSHOT ─────────────────────────────────
/// The shot loop cannot tap "Finish session" — it launches one screen with
/// seeded data and photographs it. What it therefore cannot photograph is the
/// only interesting part of this wave's gate: the TRANSITION. So the transition
/// is asserted here, against a real in-memory database, through the same
/// `LoggerModel` the button calls and the same `WorkoutWeek.refresh()` the tab
/// runs on dismissal.
@MainActor
@Suite("Workout week")
struct WorkoutWeekTests {

    private static let userId = "00000000-0000-0000-0000-000000000001"

    /// A logger bound to a fresh store, with `sets` working sets logged on the
    /// day's first movement.
    private func loggedSession(_ database: AppDatabase, day: ProgramDay, sets: Int) -> LoggerModel {
        let model = LoggerModel(day: day, phase: .cut, store: database, userId: Self.userId)
        model.attach()
        // The first LIFT. `exercises[0]` is the treadmill the deck now opens
        // with, whose rows are warm-ups — so logging into it would put three
        // ticked rows on the deck and none of them in `workingSets`, which is
        // the number every assertion below counts.
        let exercise = model.exercises.first { !$0.rows.contains(where: \.isCardio) }!
        for index in 0..<sets {
            while exercise.rows.count <= index { model.addSet(to: exercise) }
            let row = exercise.rows[index]
            row.weightKg = 40
            row.reps = 10
            model.toggleDone(row, in: exercise)
        }
        return model
    }

    private func week(_ database: AppDatabase, dayKey: String, today: String) -> WorkoutWeek {
        WorkoutWeek(
            database: database, userId: Self.userId, phase: .cut,
            // Pinned so the assertion does not depend on which weekday the test
            // happens to run on — the tab resolves the real one from the plan.
            seededToday: today, seededDayKey: dayKey
        )
    }

    @Test("finishing a session leaves the tab on `.done`, with the week and the ledger carrying it")
    func finishFeedsTheTab() async throws {
        let database = try AppDatabase.inMemory(deviceId: "test")
        let day = PlanTemplates.day("onyx5", "cb_a")
        let today = LogicalDay.today()

        // The tab before: nothing logged, nothing to show.
        let before = week(database, dayKey: day.key, today: today)
        await before.refresh()
        #expect(before.snapshot.state == .none)
        #expect(before.snapshot.sessionsLogged == 0)
        #expect(before.snapshot.weekTonnageKg == 0)

        let model = loggedSession(database, day: day, sets: 3)
        // Mid-session the tab reads LIVE, not done: an open session is not a
        // fact about the day yet, and the footer must still say "Resume".
        let during = week(database, dayKey: day.key, today: today)
        await during.refresh()
        #expect(during.snapshot.state == .live(sets: 3, volumeKg: 1200))
        #expect(during.snapshot.sessionsLogged == 0, "an open session does not fill a day cell")

        #expect(model.finish(sessionRpe: 8))

        // ── The gate ────────────────────────────────────────────────────────
        // A NEW reader, as the tab makes on dismissal. Nothing is carried over
        // from the logger; every number below came back out of the database.
        let after = week(database, dayKey: day.key, today: today)
        await after.refresh()

        guard case let .done(id, sets, volumeKg, _, _) = after.snapshot.state else {
            Issue.record("the tab did not see a finished session: \(after.snapshot.state)")
            return
        }
        #expect(sets == 3)
        #expect(volumeKg == 1200)
        #expect(after.snapshot.sessionsLogged == 1)
        #expect(after.snapshot.weekTonnageKg == 1200)

        // The day cell is now a link to the summary the tab pushes.
        let cell = after.snapshot.cells.first { $0.isToday }
        #expect(cell?.sessionId == id)
        #expect(cell?.isLogged == true)
        #expect(cell?.dayKey == day.key)

        // ...and the summary that link opens is built, from the same store.
        let page = SessionAnalysis.page(database: database, sessionId: id)
        #expect(page?.report.sets == 3)
        #expect(page?.report.tonnageKg == 1200)
        #expect(page?.previous == nil, "the first session of a split has nothing to compare against")
    }

    @Test("the library's rows and sparklines come out of the same finished session")
    func finishFeedsTheLibrary() async throws {
        let database = try AppDatabase.inMemory(deviceId: "test")
        let day = PlanTemplates.day("onyx5", "cb_a")
        let name = day.exercises(for: .cut)[0].name
        // Resolved on the main actor and captured as a plain `String`:
        // `seedRows` takes a `@Sendable` closure and `LoggerModel` is isolated.
        let exerciseId = ExerciseSlug.id(name)
        // The catalogue row the mirror supplies; the logger writes sets against
        // its id but never invents the movement itself.
        try database.seedRows { db in
            try Exercise(id: exerciseId, name: name).insert(db)
        }

        let model = loggedSession(database, day: day, sets: 2)
        #expect(model.finish(sessionRpe: 7))

        var listed: [ExerciseCatalogEntry] = []
        for try await rows in database.exerciseCatalogStream() {
            listed = rows
            break
        }
        let entry = listed.first { $0.name == name }
        #expect(entry?.setCount == 2, "the library counts the sets the logger just wrote")
        #expect(entry?.lastTrained == LogicalDay.today())

        // The row's 40×16 trail is one point after one session — which is why
        // the row draws nothing rather than a flat line.
        let ledger = try database.historySets()
        #expect(SessionAnalysis.sparkline(ledger).count == 1)
    }

    @Test("ready to progress fires only after the ceiling is cleared twice")
    func progressionNeedsTwoSessions() async throws {
        let database = try AppDatabase.inMemory(deviceId: "test")
        let day = PlanTemplates.day("onyx5", "cb_a")
        let name = day.exercises(for: .cut)[0].name          // Incline DB Press, 8–12
        let exerciseId = ExerciseSlug.id(name)
        let user = Self.userId
        let dayKey = day.key
        try database.seedRows { db in
            try Exercise(id: exerciseId, name: name).insert(db)
        }
        // ── PINNED, NOT `LogicalDay.today()` ────────────────────────────────
        // Since P3 E4 the queue skips sessions logged under the maintenance
        // lever, and `Levers.schedule` puts one on 2026-08-30 … 09-05. A test
        // that counts backwards from the real clock walks its two sessions into
        // that week for part of every month and reports a rule change as a
        // regression. 08-29 is the last deficit day before it, so -14, -7 and
        // -1 are all ordinary training days.
        let today = "2026-08-29"

        /// One finished session of `reps`-rep sets at one load.
        func session(_ id: String, date: String, reps: Int) throws {
            let start = LogicalDay.date(fromISO: date)!
            try database.seedRows { db in
                try WorkoutSession(id: id, userId: user, dayKey: dayKey, date: date,
                                   startedAt: start, endedAt: start.addingTimeInterval(3600),
                                   durationMin: 60).insert(db)
                for i in 0..<3 {
                    try WorkoutSet(id: "\(id)-\(i)", sessionId: id,
                                   exerciseId: exerciseId, setIndex: i + 1,
                                   weightKg: 40, reps: reps, foldOrder: i).insert(db)
                }
            }
        }

        // One clearing session: nearly there, and it says so rather than
        // promoting the load off a single week.
        try session("s-1", date: ISODate.addDays(today, -14)!, reps: 12)
        let once = week(database, dayKey: day.key, today: today)
        await once.refresh()
        #expect(once.snapshot.progression.first?.name == ExerciseAliases.canonicalName(name))
        #expect(once.snapshot.progression.first?.ready == false)
        #expect(once.snapshot.progression.first?.detail == "1 more session")

        // Twice in a row is the program's rule, and 2.5 kg is its step.
        try session("s-2", date: ISODate.addDays(today, -7)!, reps: 12)
        let twice = week(database, dayKey: day.key, today: today)
        await twice.refresh()
        #expect(twice.snapshot.progression.first?.ready == true)
        #expect(twice.snapshot.progression.first?.detail == "40 → 42.5 kg")

        // A session that FADES on the last set clears nothing, whatever the
        // two before it did — the fade is the evidence the load is not owned.
        try session("s-3", date: ISODate.addDays(today, -1)!, reps: 9)
        let faded = week(database, dayKey: day.key, today: today)
        await faded.refresh()
        #expect(faded.snapshot.progression.isEmpty)
    }
}
