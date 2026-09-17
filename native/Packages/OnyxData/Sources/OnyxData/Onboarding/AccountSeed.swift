import Foundation
import GRDB
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Everything a brand-new account needs before any screen in this app has an
// honest answer. The write half of W5's onboarding.
//
// ── WHY IT IS ONE TRANSACTION ───────────────────────────────────────────────
// Nine tables, and the app reads across them constantly: `TargetResolver` wants
// the plan AND the phase goals, `Schedule` wants the plan AND the routines,
// the muscle sheet wants the volume rows AND the sets. A seed that landed table
// by table would be observable half-done — the `ValueObservation` streams fire
// on every commit — and a screen that redrew in the middle would show a plan
// with no deck, or a deck with no targets, and cache it.
//
// All-or-nothing also means a seed that fails leaves an account that is still
// obviously new, rather than one that is half-configured and will never be
// offered onboarding again.
//
// ── THE ORDER INSIDE IT IS NOT ARBITRARY ────────────────────────────────────
// The catalogue goes first, because a routine payload carries the `exercises.id`
// of every movement it names (D3) and those ids do not exist until the rows do.
// Everything else is independent.
//
// ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────────
// It does not touch an account that already has rows. `AccountSeed.isNeeded`
// is the gate and it is deliberately conservative: any plan with a programme,
// any routine, any catalogue row at all means somebody has been here, and a
// second seed would write a second "My Plan" over a real one. The founder's
// account trips every one of those checks.
// ─────────────────────────────────────────────────────────────────────────────

public enum AccountSeedError: Error, LocalizedError, Equatable {
    /// The account acquired rows between the flow opening and Finish being
    /// tapped — a slow pull that landed, a realtime row, or a sync that had
    /// failed silently and then succeeded.
    case alreadySetUp

    public var errorDescription: String? {
        switch self {
        case .alreadySetUp:
            "This account already has data in it, so nothing was changed. Close and reopen Onyx."
        }
    }
}

/// One program a new account can start with, already shaped as rows.
public struct SeedPlan: Sendable {
    public var programId: String
    public var label: String
    public var blurb: String
    public var isLegacy: Bool
    public var sort: Int
    public var days: [RoutineDay]

    public init(
        programId: String, label: String, blurb: String = "", isLegacy: Bool = false,
        sort: Int = 0, days: [RoutineDay]
    ) {
        self.programId = programId; self.label = label; self.blurb = blurb
        self.isLegacy = isLegacy; self.sort = sort; self.days = days
    }
}

/// A 1RM the athlete asserted, as a record floor.
public struct SeedOneRepMax: Sendable, Equatable {
    /// The movement's display NAME — `personal_records.exercise_key` is a name
    /// and never an id (`PrRecorder`'s header, rule 2).
    public var exerciseName: String
    public var kg: Double

    public init(exerciseName: String, kg: Double) {
        self.exerciseName = exerciseName; self.kg = kg
    }
}

/// Everything onboarding collected.
public struct AccountSeed: Sendable {
    public var userId: String
    public var goal: StartingGoal
    public var targets: StartingTargets
    /// Landmark raw value → weekly working sets. Written for BOTH phases so a
    /// user who switches phase later does not land on a screen of zeroes.
    public var volume: [String: Int]
    public var weightKg: Double?
    /// `user_goals.week_end_day` — the END day (0 = Sunday-ending ⇒ the week
    /// starts Monday). The inversion lives in `SettingsModel.setWeekStartDay`
    /// and the caller has already done it.
    public var weekEndDay: Int
    public var unitSystem: String
    /// nil for "I'll build my own" — the account still gets targets, a
    /// catalogue and a plan row, just no days.
    public var plan: SeedPlan?
    public var exercises: [ExerciseDraft]
    public var oneRepMaxes: [SeedOneRepMax]
    /// ISO day the plan starts from. `plans.started_on` and the phase's own
    /// start both take it.
    public var startedOn: String

    public init(
        userId: String, goal: StartingGoal, targets: StartingTargets, volume: [String: Int],
        weightKg: Double? = nil, weekEndDay: Int, unitSystem: String = "metric",
        plan: SeedPlan?, exercises: [ExerciseDraft], oneRepMaxes: [SeedOneRepMax] = [],
        startedOn: String
    ) {
        self.userId = userId; self.goal = goal; self.targets = targets; self.volume = volume
        self.weightKg = weightKg; self.weekEndDay = weekEndDay; self.unitSystem = unitSystem
        self.plan = plan; self.exercises = exercises; self.oneRepMaxes = oneRepMaxes
        self.startedOn = startedOn
    }

    /// The id a plan-less account's rows hang off. A blank plan is still a
    /// plan: the phase goals, the volume targets and `user_goals.active_plan`
    /// are all keyed by one, and "none" would leave four tables unaddressable.
    public static let blankProgramId = "my-plan"
    public static let blankLabel = "My plan"
}

public extension AppDatabase {

    /// Has this account never been set up?
    ///
    /// Conservative on purpose — see the file header. Every check is "is there
    /// ANY evidence of a person here", and any one of them answering yes means
    /// onboarding must not run.
    func needsOnboarding(userId: String) throws -> Bool {
        try writer.read { db in try Self.needsOnboarding(db, userId: userId) }
    }

    /// The same question, inside a caller's transaction.
    ///
    /// ── EVERY HALF OF THE APP COUNTS, NOT ONLY THE TRAINING HALF ────────────
    /// The first version asked about plans, routines, the catalogue and
    /// sessions — and a person who had used the app only for food, water and
    /// weigh-ins tripped none of them. The sign-up trigger's `plans` row has no
    /// `program_id`, so they read as brand new and would have had a seed
    /// written over their `user_goals`. The rule the header states is "any
    /// evidence of a person here", and that has to include the evidence they
    /// left on the other four tabs.
    static func needsOnboarding(_ db: Database, userId: String) throws -> Bool {
        let user = Column("user_id") == userId
        // A `plans` row the sign-up trigger made carries NO `program_id`
        // ("My Plan"). That is a placeholder, not evidence of setup.
        if try PlanRow.filter(user).fetchAll(db).contains(where: { ($0.programId ?? "").isEmpty == false }) {
            return false
        }
        if try RoutineRow.filter(user).fetchCount(db) > 0 { return false }
        // NOT the catalogue. Local `exercises` has no `user_id`, so a row there
        // says a catalogue was pulled onto this phone at some point — by
        // whichever account — and nothing about whether THIS one has been set
        // up. Counting it is how a brand-new account landed on a configured
        // app (W11; the check is deleted, not filtered, because it cannot be).
        if try WorkoutSession.filter(user).fetchCount(db) > 0 { return false }
        // The non-training half.
        if try DailyLogRow.filter(user).fetchCount(db) > 0 { return false }
        if try NutritionEntryRow.filter(user).fetchCount(db) > 0 { return false }
        if try BodyCompositionRow.filter(user).fetchCount(db) > 0 { return false }
        // And targets somebody has actually set. The trigger does not write
        // these; a row with a calorie goal in it is a person who has been to
        // the Levers screen.
        if try UserGoalRow.filter(user).fetchAll(db).contains(where: { $0.calorieGoal != nil }) {
            return false
        }
        return true
    }

    /// Write the whole account. One transaction; see the file header.
    ///
    /// Returns the names the catalogue could not resolve inside the chosen
    /// plan's payloads — always empty for the bundled templates, whose
    /// movements ARE the catalogue this seed just wrote, and non-empty only if
    /// a caller hands in a plan naming something it did not also seed.
    @discardableResult
    func seedAccount(_ seed: AccountSeed, now: Date = Date()) throws -> [String] {
        try writer.write { db in
            // ── THE GATE IS INSIDE THE TRANSACTION, NOT ONLY AT THE DOOR ────
            // `AppEnvironment` asks `needsOnboarding` before it puts the flow
            // up, and that answer is minutes old by the time anyone taps
            // Finish — the realtime socket subscribes to `routines`,
            // `exercises` and the sessions while the user is on step three, so
            // an account that was empty when the cover went up can be full when
            // it comes down. A pull that failed silently (`MirrorPuller.refresh`
            // collects per-table failures and returns normally) produces the
            // same empty store on an account that has years in it.
            //
            // Asking again here, in the transaction that would do the writing,
            // is the only check that cannot go stale. It closes the retry path,
            // the realtime path and every future caller at once.
            guard try Self.needsOnboarding(db, userId: seed.userId) else {
                throw AccountSeedError.alreadySetUp
            }
            // ── 1. The catalogue ────────────────────────────────────────────
            // First, because the payloads below name its ids.
            for draft in seed.exercises {
                _ = try Self.createExercise(
                    db, userId: seed.userId, name: draft.name, primaryMuscle: draft.primaryMuscle,
                    secondaryMuscles: draft.secondaryMuscles, equipment: draft.equipment, id: nil
                )
            }
            let index = ExerciseIndex(
                try Exercise.fetchAll(db).map { RemoteExercise(id: $0.id, name: $0.name, slug: $0.slug) }
            )

            // ── 2. The plan row ─────────────────────────────────────────────
            let programId = seed.plan?.programId ?? AccountSeed.blankProgramId
            let label = seed.plan?.label ?? AccountSeed.blankLabel
            try Self.seedPlanRow(
                db, userId: seed.userId, programId: programId, label: label,
                blurb: seed.plan?.blurb ?? "", isLegacy: seed.plan?.isLegacy ?? false,
                sort: seed.plan?.sort ?? 0, startedOn: seed.startedOn
            )

            // ── 3. The deck ─────────────────────────────────────────────────
            var unresolved: [String] = []
            for day in seed.plan?.days ?? [] {
                var resolved = day
                let (payload, missing) = day.payload.resolving(index)
                resolved.payload = payload
                unresolved.append(contentsOf: missing)
                try Self.saveRoutineDay(db, userId: seed.userId, resolved)
            }

            // ── 4. Nutrition, per phase ─────────────────────────────────────
            // Both phases, not just the one being started: a person who flips to
            // a bulk in March should not find a screen of blanks waiting.
            for phase in ProgramPhase.allCases {
                try Self.seedPhaseGoals(
                    db, userId: seed.userId, planId: programId, phase: phase, seed: seed
                )
            }

            // ── 5. Weekly sets, per phase ───────────────────────────────────
            // The chosen phase takes the numbers the user just saw and edited;
            // the other takes the MEV table's own answer for it, because the
            // user has expressed no opinion about a phase they are not in.
            for phase in ProgramPhase.allCases {
                for muscle in LandmarkMuscle.allCases {
                    let sets = phase == seed.goal.phase
                        ? (seed.volume[muscle.rawValue] ?? 0)
                        : (VolumeLandmarks.table[muscle]?.target(for: phase) ?? 0)
                    try Self.seedVolume(
                        db, userId: seed.userId, planId: programId,
                        phase: phase.rawValue, muscle: muscle.rawValue, sets: sets
                    )
                }
            }

            // ── 6. The preferences row ──────────────────────────────────────
            try Self.seedUserGoals(db, seed: seed, programId: programId, now: now)

            // ── 7. Day shapes ───────────────────────────────────────────────
            try Self.seedTargetProfiles(db, seed: seed, programId: programId)

            // ── 8. Asserted records ─────────────────────────────────────────
            for max in seed.oneRepMaxes where max.kg > 0 {
                try Self.seedOneRepMax(db, userId: seed.userId, max: max, on: seed.startedOn)
            }

            return unresolved
        }
    }

    // MARK: - The pieces

    /// Claim the placeholder `plans` row, or make one.
    ///
    /// A Postgres trigger creates a row named "My Plan" with NO `program_id` at
    /// sign-up (`PlanInfo.init?(_:)` documents it). Writing a second row beside
    /// it would leave the account with two plans, one of which no screen can
    /// name — so the placeholder is CLAIMED when it is there.
    static func seedPlanRow(
        _ db: Database, userId: String, programId: String, label: String,
        blurb: String, isLegacy: Bool, sort: Int, startedOn: String
    ) throws {
        let existing = try PlanRow.filter(Column("user_id") == userId).fetchAll(db)
        var row = existing.first { $0.programId == programId }
            ?? existing.first { ($0.programId ?? "").isEmpty }
            ?? PlanRow(id: newOnyxID(), userId: userId, name: label)

        row.name = label
        row.programId = programId
        row.blurb = blurb
        row.isLegacy = isLegacy
        row.sort = sort
        row.active = true
        row.startedOn = row.startedOn ?? startedOn
        if row.createdAt == nil { row.createdAt = Self.localWriteTimestamp }
        try row.save(db)
        try Self.enqueueRowUpsert(table: PlanRow.databaseTableName, id: row.id, in: db)
    }

    static func seedPhaseGoals(
        _ db: Database, userId: String, planId: String, phase: ProgramPhase, seed: AccountSeed
    ) throws {
        // The phase being started takes the numbers the user just approved.
        // The other takes the same arithmetic run for ITS goal, so it is a real
        // answer rather than a copy of a deficit wearing a bulk's name.
        let targets = phase == seed.goal.phase
            ? seed.targets
            : StartingTargetsBuilder.build(
                weightKg: seed.weightKg ?? 0, goal: phase == .bulk ? .bulk : .cut
            )
        let goal: StartingGoal = phase == seed.goal.phase ? seed.goal : (phase == .bulk ? .bulk : .cut)
        let rate = StartingTargetsBuilder.weeklyRate(weightKg: seed.weightKg ?? 0, goal: goal)

        var row = try PlanPhaseGoalRow
            .filter(Column("user_id") == userId && Column("plan_id") == planId
                    && Column("phase") == phase.rawValue)
            .fetchOne(db)
            ?? PlanPhaseGoalRow(
                userId: userId, planId: planId, phase: phase.rawValue,
                updatedAt: Self.localWriteTimestamp
            )
        row.label = phase.label
        row.kcal = targets.kcal
        row.proteinG = targets.proteinG
        row.carbsG = targets.carbsG
        row.fatG = targets.fatG
        row.fiberG = targets.fiberG
        row.stepsGoal = targets.stepsGoal
        // A rate of zero is a real instruction on a maintenance block and a
        // missing one everywhere else; nil rather than 0 when there is no
        // bodyweight to scale it from.
        row.rateMinKgWk = seed.weightKg == nil ? nil : rate.min
        row.rateMaxKgWk = seed.weightKg == nil ? nil : rate.max
        row.updatedAt = Self.localWriteTimestamp
        try row.save(db)
        try Self.enqueueRowUpsert(
            table: PlanPhaseGoalRow.databaseTableName,
            id: Self.rowID([userId, planId, phase.rawValue]), in: db
        )
    }

    static func seedVolume(
        _ db: Database, userId: String, planId: String, phase: String, muscle: String, sets: Int
    ) throws {
        var row = try PlanPhaseVolumeRow
            .filter(Column("user_id") == userId && Column("plan_id") == planId
                    && Column("phase") == phase && Column("muscle") == muscle)
            .fetchOne(db)
            ?? PlanPhaseVolumeRow(
                userId: userId, planId: planId, phase: phase, muscle: muscle,
                targetSets: sets, updatedAt: Self.localWriteTimestamp
            )
        row.targetSets = sets
        row.updatedAt = Self.localWriteTimestamp
        try row.save(db)
        try Self.enqueueRowUpsert(
            table: PlanPhaseVolumeRow.databaseTableName,
            id: Self.rowID([userId, planId, phase, muscle]), in: db
        )
    }

    static func seedUserGoals(
        _ db: Database, seed: AccountSeed, programId: String, now: Date
    ) throws {
        var row = try UserGoalRow.filter(Column("user_id") == seed.userId).fetchOne(db)
            ?? UserGoalRow(
                id: newOnyxID(), userId: seed.userId, contextMode: "normal",
                createdAt: Self.localWriteTimestamp, updatedAt: Self.localWriteTimestamp,
                autoLogSupplements: false, activeProgram: programId, dayCutoffHour: 0,
                unitSystem: seed.unitSystem, reduceMotion: false,
                timezone: TimeZone.current.identifier, trackRpe: true
            )
        row.calorieGoal = seed.targets.kcal
        row.proteinGoalG = seed.targets.proteinG
        row.carbsGoalG = seed.targets.carbsG
        row.fatGoalG = seed.targets.fatG
        row.stepsGoal = seed.targets.stepsGoal
        row.activeProgram = programId
        row.activePlan = programId
        row.activePhase = seed.goal.phase.rawValue
        row.phaseStartedOn = seed.startedOn
        row.weekEndDay = seed.weekEndDay
        row.unitSystem = seed.unitSystem
        // ── `custom` IS THE SENTINEL FOR "MY OWN NUMBERS" ───────────────────
        // W2's rule, and it is the right one here: the macros above came from
        // an arithmetic the user was shown and allowed to edit, so they are the
        // user's, not a rung of a ladder that does not exist yet.
        row.activeLever = "custom"
        row.updatedAt = Self.localWriteTimestamp
        try row.save(db)
        try Self.enqueueRowUpsert(
            table: UserGoalRow.databaseTableName, id: row.id, in: db
        )
    }

    /// The two day shapes every account starts with.
    ///
    /// `TargetProfiles.builtin` (Home / Restaurant) was deleted in W2 because it
    /// was the founder's two rows compiled in, and a stranger was being offered
    /// a 2,150 kcal "Home" they never wrote. The answer is not to bring the
    /// constant back — it is to seed rows FROM THIS ACCOUNT'S OWN TARGETS, so
    /// the numbers on the picker are numbers this person chose.
    ///
    /// A restaurant day's carbohydrate and fat are UNTRACKED, never zero: a 0 g
    /// fat target grades the day 0/0 and calls it perfect (`Profiles.swift`).
    static func seedTargetProfiles(_ db: Database, seed: AccountSeed, programId: String) throws {
        let profiles: [(key: String, label: String, summary: String, sort: Int,
                        kcal: Int, protein: Int, carbs: Int?, fat: Int?)] = [
            ("home", "Home", "Your usual day, cooked at home.", 0,
             seed.targets.kcal, seed.targets.proteinG,
             seed.targets.carbsG, seed.targets.fatG),
            ("out", "Eating out", "Protein and calories only — the rest is a guess.", 1,
             seed.targets.kcal, seed.targets.proteinG, nil, nil),
        ]
        for p in profiles {
            var row = try TargetProfileRow
                .filter(Column("user_id") == seed.userId && Column("key") == p.key)
                .fetchOne(db)
                ?? TargetProfileRow(
                    userId: seed.userId, key: p.key, label: p.label, sort: p.sort,
                    updatedAt: Self.localWriteTimestamp
                )
            row.label = p.label
            row.summary = p.summary
            row.sort = p.sort
            row.kcal = p.kcal
            row.proteinG = p.protein
            row.carbsG = p.carbs
            row.fatG = p.fat
            row.stepsGoal = seed.targets.stepsGoal
            row.kind = "day"
            row.updatedAt = Self.localWriteTimestamp
            try row.save(db)
            try Self.enqueueRowUpsert(
                table: TargetProfileRow.databaseTableName,
                id: Self.rowID([seed.userId, p.key]), in: db
            )
        }
    }

    /// One asserted 1RM as a record floor.
    ///
    /// ── E1RM ONLY, AND THAT IS THE HONEST AXIS ──────────────────────────────
    /// "My bench is 100 kg" is a claim about an ESTIMATED one-rep max — it may
    /// have come from 80 × 5 and never from a single at 100. Writing a `weight`
    /// floor of 100 as well would assert something the athlete did not say, and
    /// the first honest 90 kg single would then fail to register as the weight
    /// record it is.
    ///
    /// `session_id` nil is what MAKES it a floor: a record with no session
    /// behind it is, by definition, one asserted rather than earned
    /// (`PrTruth.swift`). `floor_value` stays nil — that column is for a floor
    /// a real session has already beaten.
    static func seedOneRepMax(
        _ db: Database, userId: String, max: SeedOneRepMax, on date: String
    ) throws {
        let key = ExerciseAliases.canonicalName(max.exerciseName)
        let axis = PrAxis.e1rm.rawValue
        var row = try PersonalRecordRow
            .filter(Column("user_id") == userId && Column("exercise_key") == key
                    && Column("axis") == axis)
            .fetchOne(db)
            ?? PersonalRecordRow(
                userId: userId, exerciseKey: key, axis: axis, value: max.kg,
                sessionId: nil, achievedOn: date, updatedAt: Self.localWriteTimestamp
            )
        // Never lower a record that already exists — a floor is a bar to raise.
        guard row.value <= max.kg else { return }
        row.value = max.kg
        row.sessionId = nil
        row.achievedOn = date
        row.updatedAt = Self.localWriteTimestamp
        try row.save(db)
        try Self.enqueueRowUpsert(
            table: PersonalRecordRow.databaseTableName,
            id: Self.rowID([userId, key, axis]), in: db
        )
    }
}
