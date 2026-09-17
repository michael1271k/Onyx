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

    // MARK: - W6 · the week delta compares the same stretch

    /// A week that starts on MONDAY, so "Wednesday is three days in" is
    /// arithmetic and not an artefact of where the fixture begins.
    /// `week_end_day == 0` (a week ending Sunday) is what `Week.startDay`
    /// turns into a Monday start.
    ///
    /// The CATALOGUE is seeded too, and that is not decoration: `weekPaceKg`'s
    /// denominator is the plan's training days, which `Schedule.isTrainingDayIn`
    /// resolves through `routines` ROWS. A store holding only a `user_goals`
    /// row naming `onyx5` has an empty `activeProgram`, so every day of the
    /// week is a rest day and the projection is correctly — and uselessly —
    /// nil. The first cut of these tests asserted against exactly that.
    private func mondayStartStore() throws -> AppDatabase {
        let database = try AppDatabase.inMemory(deviceId: "test")
        PreviewCatalogue.seed(database, userId: Self.userId, today: "2026-09-09")
        try database.editUserGoals(userId: Self.userId) { $0.weekEndDay = 0; $0.activePlan = "onyx5" }
        return database
    }

    /// One finished session, `kg × reps` on one movement, on a given date.
    private func seedSession(_ database: AppDatabase, id: String, date: String, kg: Double) throws {
        let start = LogicalDay.date(fromISO: date)!
        let user = Self.userId
        try database.seedRows { db in
            try WorkoutSession(id: id, userId: user, dayKey: "cb_a", date: date,
                               startedAt: start, endedAt: start.addingTimeInterval(3600),
                               durationMin: 60).insert(db)
            try WorkoutSet(id: "\(id)-1", sessionId: id, exerciseId: "ex-incline",
                           setIndex: 1, weightKg: kg, reps: 10, foldOrder: 0).insert(db)
        }
    }

    /// THE BUG (F8). Monday morning, nothing lifted yet, and a full week
    /// behind it — the door used to print the whole of last week as a loss.
    @Test("the first morning of the week is nil, never the whole of last week as a negative")
    func firstMorningIsNotACollapse() async throws {
        let database = try mondayStartStore()
        // Last week: Tuesday through Friday, four sessions, nothing on its Monday.
        for (i, date) in ["2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04"].enumerated() {
            try seedSession(database, id: "last-\(i)", date: date, kg: 100)
        }
        let monday = week(database, dayKey: "cb_a", today: "2026-09-07")
        await monday.refresh()
        #expect(monday.snapshot.weekTonnageKg == 0)
        // Last Monday holds nothing either, so the matched stretch is empty on
        // both sides: nothing to say, and certainly not −4,000 kg.
        #expect(monday.snapshot.weekDeltaKg == nil)
        // An empty week has no rate, so nothing to project from.
        #expect(monday.snapshot.weekPaceKg == nil)
    }

    @Test("Wednesday compares three days against three, not three against seven")
    func wednesdayComparesThreeDays() async throws {
        let database = try mondayStartStore()
        // Last week: five sessions, 1,000 kg each — 5,000 over the full week,
        // 3,000 over its first three days.
        for (i, date) in ["2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04"].enumerated() {
            try seedSession(database, id: "last-\(i)", date: date, kg: 100)
        }
        // This week: three sessions at the same load. Level at this point.
        for (i, date) in ["2026-09-07", "2026-09-08", "2026-09-09"].enumerated() {
            try seedSession(database, id: "now-\(i)", date: date, kg: 100)
        }
        let wednesday = week(database, dayKey: "cb_a", today: "2026-09-09")
        await wednesday.refresh()
        #expect(wednesday.snapshot.weekTonnageKg == 3_000)
        // The old rule subtracted all five of last week's sessions and reported
        // −2,000 on a week that was running exactly level.
        #expect(wednesday.snapshot.weekDeltaKg == 0)
    }

    @Test("a week with nothing behind it has no delta rather than a gain of everything")
    func noPreviousWeekHasNoDelta() async throws {
        let database = try mondayStartStore()
        for (i, date) in ["2026-09-07", "2026-09-08"].enumerated() {
            try seedSession(database, id: "now-\(i)", date: date, kg: 100)
        }
        let tuesday = week(database, dayKey: "cb_a", today: "2026-09-08")
        await tuesday.refresh()
        #expect(tuesday.snapshot.weekTonnageKg == 2_000)
        #expect(tuesday.snapshot.weekDeltaKg == nil)
        // The projection needs no previous week — it is this week's own rate.
        #expect(tuesday.snapshot.weekPaceKg != nil)
    }

    /// The projection is finite and above the work done so far, and a week with
    /// nothing in it produces none — the two states a caption may be drawn in.
    @Test("the projection is a real number mid-week and absent on an empty one")
    func paceNeverDividesByZero() async throws {
        let database = try mondayStartStore()
        try seedSession(database, id: "now-0", date: "2026-09-07", kg: 100)
        let monday = week(database, dayKey: "cb_a", today: "2026-09-07")
        await monday.refresh()
        let pace = try #require(monday.snapshot.weekPaceKg)
        #expect(pace.isFinite)
        #expect(pace >= monday.snapshot.weekTonnageKg)

        let empty = week(try mondayStartStore(), dayKey: "cb_a", today: "2026-09-07")
        await empty.refresh()
        #expect(empty.snapshot.weekPaceKg == nil)
    }

    // MARK: - W6 · past weeks and the arrangement

    @Test("closed weeks come back newest first, and a week with a missed day still summarises")
    func pastWeeksAreListedAndSummarise() async throws {
        let database = try mondayStartStore()
        // Three weeks behind this one, one session each — none of them complete
        // under `WeeklyWrap.isWrapped`, which is the ordinary state of a log.
        for (i, date) in ["2026-08-18", "2026-08-25", "2026-09-01"].enumerated() {
            try seedSession(database, id: "past-\(i)", date: date, kg: 100)
        }
        let tab = week(database, dayKey: "cb_a", today: "2026-09-09")
        await tab.refresh()
        // Off `library()` and no longer off the snapshot: the walk is a sheet's
        // content since §W1 C, so the tab does not pay for it on every refresh.
        let weeks = await tab.library().weeks
        #expect(weeks.map(\.weekStart) == ["2026-08-31", "2026-08-24", "2026-08-17"])
        #expect(weeks.allSatisfy { $0.sessions == 1 })
        #expect(weeks[0].tonnageKg == 1_000)
        // The row expands into a summary even though the week missed four of
        // its five planned days — `isWrapped` is about the CURRENT week.
        #expect(await tab.pastSummary(weekStart: "2026-08-31") != nil)
    }

    // MARK: - W4 · the anchor week is a past week

    /// The founder's own store, as `PreviewCatalogue` seeds it: `onyx5`
    /// started 2026-07-15, `plan_phases` opening on 2026-07-12, and a week
    /// that ends on Saturday — `week_end_day = 6`, which `Week.startDay`
    /// turns into a SUNDAY start. So `weekZeroStart` is 2026-07-12 and the
    /// anchor week is a real, partial week with two sessions in it.
    private func sundayStartStore() throws -> AppDatabase {
        let database = try AppDatabase.inMemory(deviceId: "test")
        PreviewCatalogue.seed(database, userId: Self.userId, today: "2026-09-09")
        try database.editUserGoals(userId: Self.userId) { $0.weekEndDay = 6; $0.activePlan = "onyx5" }
        return database
    }

    /// THE BUG (W4 · GOAL 1). Week 0 is the week the plan opened in and the
    /// shelf never drew it: the walk stops at the first week that fails
    /// `Schedule.isPlannable`, and it was testing the week it had just stepped
    /// off rather than the one it was about to emit.
    @Test("the anchor week itself is listed, labelled Week 0")
    func weekZeroIsAPastWeek() async throws {
        let database = try sundayStartStore()
        // Wednesday and Friday of the anchor week — the two days the founder's
        // plan actually opened on.
        try seedSession(database, id: "w0-wed", date: "2026-07-15", kg: 100)
        try seedSession(database, id: "w0-fri", date: "2026-07-17", kg: 100)

        let tab = week(database, dayKey: "cb_a", today: "2026-09-09")
        let weeks = await tab.library().weeks
        let zero = weeks.first { $0.weekStart == "2026-07-12" }
        #expect(zero != nil, "the anchor week draws no banner: \(weeks.map(\.weekStart))")
        #expect(zero?.label == "Week 0")
        #expect(zero?.sessions == 2)
        // And it opens: a banner that lists but cannot expand is half a door.
        #expect(await tab.pastSummary(weekStart: "2026-07-12") != nil)
    }

    /// The other half of the same decision. The PPL era ran March–July under a
    /// different plan and stays out of Past Weeks — the walk stops BELOW the
    /// anchor, it does not stop AT it.
    @Test("the walk still stops below the anchor — the PPL era stays hidden")
    func theEraBeforeTheAnchorStaysHidden() async throws {
        let database = try sundayStartStore()
        try seedSession(database, id: "w0-wed", date: "2026-07-15", kg: 100)
        // The week before Week 0, and a PPL cut week two months back. Both are
        // logged, both are real, and neither is this plan's to show.
        try seedSession(database, id: "pre", date: "2026-07-08", kg: 100)
        try seedSession(database, id: "ppl", date: "2026-05-13", kg: 100)

        let weeks = await week(database, dayKey: "cb_a", today: "2026-09-09").library().weeks
        #expect(weeks.allSatisfy { $0.weekStart >= "2026-07-12" })
    }

    @Test("hiding a section survives a re-read, and costs the dashboard nothing")
    func customizeRoundTrips() async throws {
        let database = try mondayStartStore()
        try database.saveDashboardLayout(userId: database.localUserId(), Dashboard.defaultLayout(.phone))
        let tab = week(database, dayKey: "cb_a", today: "2026-09-09")
        await tab.refresh()
        #expect(tab.snapshot.trainLayout == .default)

        tab.setTrainSection(.cardio, visible: false)
        #expect(!tab.snapshot.trainLayout.shows(.cardio))

        let reread = week(database, dayKey: "cb_a", today: "2026-09-09")
        await reread.refresh()
        #expect(reread.snapshot.trainLayout.hidden == [.cardio])
        // That the dashboard in the same row survives a Train write is
        // `DashboardLayoutStoreTests.trainAndDashboardShareTheRow`'s claim,
        // where the stored JSON is reachable.
    }

}
