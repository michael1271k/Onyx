import Foundation
import Testing
import GRDB
import OnyxCore
@testable import OnyxData

// The write paths W5 added: a catalogue row that can be created, a routine day
// that can be saved, and a whole account that can be seeded in one go. Every one
// of them queues, because a row that never reaches the server is a row that
// exists on one phone.

private let user = "00000000-0000-0000-0000-0000000000aa"

private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "seed-test") }

private func queued(_ db: AppDatabase) throws -> [(table: String, id: String)] {
    try db.pendingOutbox(limit: 500).compactMap { item in
        guard item.kind == SyncKind.rowUpsert,
              let ref = try? OnyxJSON.decoder.decode(RowRef.self, from: item.payload)
        else { return nil }
        return (ref.table, ref.id)
    }
}

private func sampleDays() -> [RoutineDay] {
    [
        RoutineDay(
            programId: "onyx5", dayKey: "cb_a", label: "Upper A", sub: "Chest + Back",
            weekday: 0, accent: 0xE0703C, sort: 0,
            payload: RoutinePayload(exercises: [
                RoutineExercise(name: "Lat Pulldown", sets: 3, reps: "8–12", restSec: 135),
                RoutineExercise(name: "Pec Deck", sets: 2, reps: "12–15", restSec: 120),
            ])
        ),
        RoutineDay(
            programId: "onyx5", dayKey: "legs_a", label: "Legs A", weekday: 1,
            accent: 0x3D7AB8, sort: 1,
            payload: RoutinePayload(exercises: [
                RoutineExercise(name: "Hack Squat", sets: 3, reps: "10–12", restSec: 135),
            ])
        ),
    ]
}

private func seed(plan: SeedPlan?, goal: StartingGoal = .cut) -> AccountSeed {
    var volume: [String: Int] = [:]
    for (muscle, sets) in VolumeLandmarks.starting(for: goal.phase) {
        volume[muscle.rawValue] = sets
    }
    return AccountSeed(
        userId: user,
        goal: goal,
        targets: StartingTargetsBuilder.build(weightKg: 80, goal: goal),
        volume: volume,
        weightKg: 80,
        weekEndDay: 6,
        plan: plan,
        exercises: [
            ExerciseDraft(name: "Lat Pulldown"),
            ExerciseDraft(name: "Pec Deck"),
            ExerciseDraft(name: "Hack Squat"),
        ],
        oneRepMaxes: [SeedOneRepMax(exerciseName: "Bench Press", kg: 100)],
        startedOn: "2026-09-14"
    )
}

@Suite("W5 · the catalogue can be written")
struct ExerciseCatalogueWriterTests {

    @Test("a created row lands locally AND in the queue")
    func createQueues() throws {
        let db = try store()
        let id = try db.createExercise(userId: user, name: "Zercher Squat", primaryMuscle: "Quads")

        let row = try #require(try db.exercise(id: id))
        #expect(row.name == "Zercher Squat")
        #expect(row.primaryMuscle == "Quads")
        // The slug is the same function the logger stamps on a set.
        #expect(row.slug == nil, "a row created today has no legacy id to alias")

        let items = try queued(db)
        #expect(items.contains { $0.table == "exercises" })
        // The outbox id carries the user, because the local table has no
        // `user_id` column and Postgres requires one.
        let ref = try #require(items.first { $0.table == "exercises" })
        #expect(ref.id == AppDatabase.rowID([user, id]))
    }

    /// A second row for a name the catalogue already holds is the SPLIT that
    /// `ExerciseIndex`'s header exists to prevent — and an importer is exactly
    /// where it would happen.
    @Test("a name already in the catalogue returns the row that is there")
    func createIsIdempotentOnName() throws {
        let db = try store()
        let first = try db.createExercise(userId: user, name: "Hip Thrust")
        let again = try db.createExercise(userId: user, name: "  hip thrust ")
        #expect(first == again)
        #expect(try db.exercises().count == 1)
    }

    @Test("a batch is one transaction and keeps its order")
    func batchCreate() throws {
        let db = try store()
        let ids = try db.createExercises(userId: user, [
            ExerciseDraft(name: "Meadows Row", primaryMuscle: "Lats"),
            ExerciseDraft(name: ""),
            ExerciseDraft(name: "Jefferson Curl", primaryMuscle: "Lower back"),
        ])
        #expect(ids.count == 3)
        #expect(ids[1] == nil)
        #expect(try db.exercises().map(\.name) == ["Jefferson Curl", "Meadows Row"])
    }

    /// The whole reason the table needed a push at all: without an entry here
    /// the outbox item fails `unmirroredTable` forever and every set logged
    /// against the movement is rejected by the foreign key.
    @Test("`exercises` is pushable even though it is not in the generated catalogue")
    func exercisesArePushable() {
        #expect(MirrorCatalogue.byName["exercises"] == nil)
        #expect(MirrorCatalogue.pushable["exercises"] != nil)
        // And adding it did not disturb the generated list, which a test counts.
        #expect(MirrorCatalogue.pushable.count == MirrorCatalogue.byName.count + 1)
    }

    /// The local and remote shapes are different tables that share a name; this
    /// is the six lines that bridge them.
    @Test("the wire shape carries what Postgres requires")
    func wireShape() throws {
        let db = try store()
        let id = try db.createExercise(
            userId: user, name: "Lat Pulldown", equipment: "Cable"
        )
        let wire = ExerciseWire(try #require(try db.exercise(id: id)), userId: user)
        #expect(wire.userId == user)
        // NOT NULL in Postgres, both of them.
        #expect(wire.splitDay == "custom")
        #expect(wire.equipment == ["Cable"])
        // Movers come from the dictionary when it knows the name — so the
        // server and the phone cannot disagree about what a pulldown trains.
        #expect(wire.muscleGroups?.first == "lats")
        #expect(wire.isCompound == true)
    }

    @Test("a movement with no equipment sends an empty list, never null")
    func equipmentIsNeverNull() throws {
        let db = try store()
        let id = try db.createExercise(userId: user, name: "Hanging Knee Raise")
        let wire = ExerciseWire(try #require(try db.exercise(id: id)), userId: user)
        #expect(wire.equipment == [])
    }

    /// An imported movement the dictionary has never seen still names its
    /// muscles, through the stored fallback.
    @Test("an unknown name falls back to the tags the import gave it")
    func unknownNamesKeepTheirTags() throws {
        let db = try store()
        let id = try db.createExercise(
            userId: user, name: "Zercher Squat", primaryMuscle: "Quads",
            secondaryMuscles: ["Glutes"]
        )
        let wire = ExerciseWire(try #require(try db.exercise(id: id)), userId: user)
        #expect(wire.muscleGroups == ["Quads", "Glutes"])
    }
}

@Suite("W5 · routines can be written")
struct RoutineWriterTests {

    @Test("a saved day round-trips and queues on its composite key")
    func saveAndRead() throws {
        let db = try store()
        let day = sampleDays()[0]
        try db.saveRoutineDay(userId: user, day)

        let back = try db.routineDays(userId: user, programId: "onyx5")
        #expect(back.count == 1)
        #expect(back[0].label == "Upper A")
        #expect(back[0].payload.exercises.map(\.name) == ["Lat Pulldown", "Pec Deck"])

        let ref = try #require(try queued(db).first { $0.table == "routines" })
        #expect(ref.id == AppDatabase.rowID([user, "onyx5", "cb_a"]))
    }

    @Test("days come back in the order the logger reads them")
    func order() throws {
        let db = try store()
        try db.saveRoutineDays(userId: user, sampleDays().reversed())
        #expect(try db.routineDays(userId: user, programId: "onyx5").map(\.dayKey) == ["cb_a", "legs_a"])
    }

    /// A deleted day is not an empty day: the schedule reads a missing day as
    /// REST and an empty one as a session with nothing in it.
    @Test("a deleted day is gone and its delete is queued")
    func delete() throws {
        let db = try store()
        try db.saveRoutineDays(userId: user, sampleDays())
        try db.deleteRoutineDay(userId: user, programId: "onyx5", dayKey: "legs_a")

        #expect(try db.routineDays(userId: user, programId: "onyx5").map(\.dayKey) == ["cb_a"])
        let deletes = try db.pendingOutbox(limit: 500).filter { $0.kind == SyncKind.rowDelete }
        #expect(deletes.count == 1)
    }

    /// A row this device invented must not look newer than the server's own, or
    /// the next delta pull starts after it and the server's rows never arrive.
    @Test("a local write never drags the delta cursor forward")
    func localTimestamp() throws {
        let db = try store()
        try db.saveRoutineDay(userId: user, sampleDays()[0])
        let row = try #require(try db.writer.read { conn in
            try RoutineRow.filter(Column("user_id") == user).fetchOne(conn)
        })
        #expect(row.updatedAt == AppDatabase.localWriteTimestamp)
    }

    @Test("resolving fills every id the catalogue can name and reports the rest")
    func resolving() throws {
        let index = ExerciseIndex([
            RemoteExercise(id: "ex-1", name: "Lat Pulldown"),
            RemoteExercise(id: "ex-2", name: "Pec Deck"),
        ])
        let payload = RoutinePayload(exercises: [
            RoutineExercise(name: "Lat Pulldown", sets: 3, reps: "8–12"),
            RoutineExercise(name: "Pec Deck", sets: 2, reps: "12–15"),
            RoutineExercise(name: "Zercher Squat", sets: 3, reps: "8–12"),
        ])
        let (out, unresolved) = payload.resolving(index)
        #expect(out.exercises[0].exerciseId == "ex-1")
        #expect(out.exercises[1].exerciseId == "ex-2")
        #expect(out.exercises[2].exerciseId == nil)
        // Non-throwing on purpose: one unplaceable movement must not stop a
        // person writing their routine down.
        #expect(unresolved == ["Zercher Squat"])
    }
}

@Suite("W5 · a whole account can be seeded")
struct AccountSeedTests {

    @Test("an empty store needs onboarding; a seeded one never again")
    func gate() throws {
        let db = try store()
        #expect(try db.needsOnboarding(userId: user) == true)
        try db.seedAccount(seed(plan: SeedPlan(
            programId: "onyx5", label: "Onyx-5", days: sampleDays()
        )))
        #expect(try db.needsOnboarding(userId: user) == false)
    }

    /// The founder's account trips every check. This is the gate that keeps W5
    /// from writing a "My plan" over a real one.
    @Test("an account that already has a deck is never offered onboarding")
    func founderIsNeverReseeded() throws {
        let db = try store()
        try db.writer.write { conn in try SampleDeck.seedCatalogue(conn, userId: user) }
        #expect(try db.needsOnboarding(userId: user) == false)
    }

    @Test("a catalogue row alone is enough evidence of a person")
    func catalogueCounts() throws {
        let db = try store()
        _ = try db.createExercise(userId: user, name: "Hip Thrust")
        #expect(try db.needsOnboarding(userId: user) == false)
    }

    @Test("the seed writes the plan, the deck, both phases and the preferences")
    func writesEverything() throws {
        let db = try store()
        let unresolved = try db.seedAccount(seed(plan: SeedPlan(
            programId: "onyx5", label: "Onyx-5", blurb: "Five days", days: sampleDays()
        )))
        // Every movement in the deck was seeded into the catalogue beside it.
        #expect(unresolved.isEmpty)

        let ctx = try db.scheduleContext(userId: user)
        #expect(ctx.plans.map(\.id) == ["onyx5"])
        #expect(ctx.program(id: "onyx5")?.days.count == 2)
        #expect(ctx.planStartISO == "2026-09-14")

        // The deck's ids were resolved to catalogue rows, so the logger stamps
        // a uuid rather than falling back to the legacy slug (D3).
        let day = try #require(ctx.program(id: "onyx5")?.day(key: "cb_a"))
        #expect(day.exercises.allSatisfy { $0.exerciseId?.isEmpty == false })

        let goals = try #require(try db.userGoals(userId: user))
        #expect(goals.activePlan == "onyx5")
        #expect(goals.activePhase == "cut")
        #expect(goals.weekEndDay == 6)
        #expect(goals.activeLever == "custom")
        #expect(goals.calorieGoal == 2_160)
    }

    /// A person who flips to a bulk in March should not find a screen of blanks.
    @Test("both phases get goals and volume, not just the one being started")
    func bothPhases() throws {
        let db = try store()
        try db.seedAccount(seed(plan: nil, goal: .cut))

        for phase in ProgramPhase.allCases {
            let goals = try db.phaseGoals(userId: user, planId: AccountSeed.blankProgramId, phase: phase)
            #expect((goals?.calorieGoal ?? 0) > 0, "\(phase.rawValue) has no kcal")
            let volume = try db.volumeTargets(userId: user, planId: AccountSeed.blankProgramId, phase: phase)
            #expect(volume.count == LandmarkMuscle.allCases.count, "\(phase.rawValue) volume")
        }
        // The phase NOT being started takes the MEV table's own answer for it,
        // rather than a copy of a deficit wearing a bulk's name.
        let bulk = try db.phaseGoals(userId: user, planId: AccountSeed.blankProgramId, phase: .bulk)
        let cut = try db.phaseGoals(userId: user, planId: AccountSeed.blankProgramId, phase: .cut)
        #expect((bulk?.calorieGoal ?? 0) > (cut?.calorieGoal ?? 0))
    }

    /// "I'll build my own" still needs somewhere to hang four tables off.
    @Test("a blank plan is still a plan")
    func blankPlan() throws {
        let db = try store()
        try db.seedAccount(seed(plan: nil))
        let ctx = try db.scheduleContext(userId: user)
        #expect(ctx.plans.map(\.id) == [AccountSeed.blankProgramId])
        #expect(ctx.program(id: AccountSeed.blankProgramId)?.days.isEmpty ?? true)
    }

    /// A Postgres trigger makes a "My Plan" row with no `program_id` at sign-up.
    /// Writing a second row beside it leaves an account with two plans, one of
    /// which no screen can name.
    @Test("the sign-up placeholder is claimed, not duplicated")
    func claimsThePlaceholder() throws {
        let db = try store()
        try db.writer.write { conn in
            try PlanRow(id: "trigger-row", userId: user, name: "My Plan").save(conn)
        }
        try db.seedAccount(seed(plan: SeedPlan(programId: "onyx5", label: "Onyx-5", days: sampleDays())))

        let plans = try db.writer.write { conn in try PlanRow.filter(Column("user_id") == user).fetchAll(conn) }
        #expect(plans.count == 1)
        #expect(plans[0].id == "trigger-row")
        #expect(plans[0].programId == "onyx5")
        #expect(plans[0].active == true)
    }

    /// `session_id` nil is what MAKES it a floor. e1RM only: "my bench is 100"
    /// is a claim about an estimate, not about a single.
    @Test("a 1RM becomes a session-less e1RM floor and nothing else")
    func oneRepMaxFloor() throws {
        let db = try store()
        try db.seedAccount(seed(plan: nil))
        let rows = try db.writer.write { conn in try PersonalRecordRow.fetchAll(conn) }
        #expect(rows.count == 1)
        #expect(rows[0].axis == "e1rm")
        #expect(rows[0].value == 100)
        #expect(rows[0].sessionId == nil)
        // That column is for a floor a real session has already beaten.
        #expect(rows[0].floorValue == nil)
        #expect(rows[0].achievedOn == "2026-09-14")
    }

    /// The two day shapes come from THIS account's numbers — W2 deleted the
    /// compiled Home/Restaurant pair because a stranger was offered the
    /// founder's 2,150 kcal "Home".
    @Test("day shapes are seeded from the account's own targets")
    func dayShapes() throws {
        let db = try store()
        try db.seedAccount(seed(plan: nil))
        let profiles = try db.writer.write { conn in
            try TargetProfileRow.filter(Column("user_id") == user).order(Column("sort")).fetchAll(conn)
        }
        #expect(profiles.map(\.key) == ["home", "out"])
        #expect(profiles[0].kcal == 2_160)
        // Untracked, never zero: a 0 g fat target grades the day 0/0 and calls
        // it perfect.
        #expect(profiles[1].carbsG == nil)
        #expect(profiles[1].fatG == nil)
    }

    /// Nine tables, and every row has to reach the server. A seed that wrote
    /// locally and queued nothing is an account that exists on one phone.
    @Test("every seeded table is queued")
    func everythingIsQueued() throws {
        let db = try store()
        try db.seedAccount(seed(plan: SeedPlan(programId: "onyx5", label: "Onyx-5", days: sampleDays())))
        let tables = Set(try queued(db).map(\.table))
        for expected in [
            "exercises", "plans", "routines", "plan_phase_goals",
            "plan_phase_volume", "user_goals", "target_profiles", "personal_records",
        ] {
            #expect(tables.contains(expected), "\(expected) was written but never queued")
        }
    }

    /// A second seed is REFUSED, not merged.
    ///
    /// The gate is re-asked inside the transaction that would do the writing,
    /// because the answer taken when the flow opened is minutes old by the time
    /// anyone taps Finish — realtime streams rows in while the user is on step
    /// three, and a pull that failed silently produces an empty store on an
    /// account that has years in it. Refusing leaves the account as it was.
    @Test("an account that has acquired rows refuses a second seed")
    func refusesASecondSeed() throws {
        let db = try store()
        let s = seed(plan: SeedPlan(programId: "onyx5", label: "Onyx-5", days: sampleDays()))
        try db.seedAccount(s)
        #expect(throws: AccountSeedError.alreadySetUp) { try db.seedAccount(s) }

        #expect(try db.exercises().count == 3)
        #expect(try db.routineDays(userId: user, programId: "onyx5").count == 2)
        let plans = try db.writer.write { conn in try PlanRow.filter(Column("user_id") == user).fetchAll(conn) }
        #expect(plans.count == 1)
        let records = try db.writer.write { conn in try PersonalRecordRow.fetchAll(conn) }
        #expect(records.count == 1)
    }

    /// The half of the app the first version of the gate could not see.
    ///
    /// A person who used the app only for food, water and weigh-ins has no plan,
    /// no routine, no catalogue and no session — the sign-up trigger's `plans`
    /// row carries no `program_id` — so they read as brand new and would have
    /// had a seed written over their `user_goals`.
    @Test("evidence on the other four tabs closes the gate too")
    func nonTrainingEvidenceCounts() throws {
        let cases: [(String, @Sendable (Database) throws -> Void)] = [
            ("a logged day", { conn in
                try DailyLogRow(
                    id: "d1", userId: user, date: "2026-09-01",
                    createdAt: Date(), updatedAt: Date(),
                    nutritionEstimated: false, sleepOnsetTrouble: false
                ).insert(conn)
            }),
            ("a body reading", { conn in
                try BodyCompositionRow(
                    id: "b1", userId: user, measuredAt: Date(), date: "2026-09-01",
                    weightKg: 80, createdAt: Date()
                ).insert(conn)
            }),
            ("targets somebody set", { conn in
                try UserGoalRow(
                    id: "g1", userId: user, calorieGoal: 2_400, contextMode: "normal",
                    createdAt: Date(), updatedAt: Date(), autoLogSupplements: false,
                    activeProgram: "", dayCutoffHour: 0, unitSystem: "metric",
                    reduceMotion: false, timezone: "UTC", trackRpe: true
                ).insert(conn)
            }),
        ]
        for (name, write) in cases {
            let db = try store()
            #expect(try db.needsOnboarding(userId: user) == true)
            try db.writer.write { conn in try write(conn) }
            #expect(try db.needsOnboarding(userId: user) == false, "\(name) did not close the gate")
        }
    }
}
