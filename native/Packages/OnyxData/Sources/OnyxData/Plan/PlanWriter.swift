import Foundation
import GRDB
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Writing `plans` — a program made on the phone (Precision E2/E3).
//
// Until this wave the only thing that ever created a `plans` row was
// `AccountSeed.seedAccount`, once per account. The routine builder could edit
// the RUNNING plan's days and nothing else; a second program meant SQL. This
// file is the one writer, and the seed is now its first caller: a program
// written two ways is a program that drifts.
//
// ── ONE ROW PER PROGRAM, KEYED BY `program_id` ─────────────────────────────
// `routines.program_id`, `plan_phase_goals.plan_id`, `plan_phase_volume.plan_id`
// and `program_day_layout.program_id` all join on the text id, never on the row
// uuid. So the id is minted ONCE, from the name, and never changes: a rename is
// a label edit (the same rule `RoutinesModel.rename` states for a day key).
//
// ── CREATING NEVER SWITCHES ─────────────────────────────────────────────────
// A new program is benched (`active = false`, no `started_on`). Running it is
// a separate, deliberate gesture — `activateProgram` — because switching the
// plan moves the deck, the phase and the macros at once, and dates an era.
// ─────────────────────────────────────────────────────────────────────────────

public enum PlanWriteError: Error, LocalizedError, Equatable {
    /// The program is the one being run. Switch first.
    case activePlan
    /// The program owned dated weeks — `Schedule.planId(owning:)` reads its
    /// `started_on` to label them — and deleting it would relabel history.
    case hasRun(since: String)
    /// No `plans` row carries that id for this user.
    case unknownPlan

    public var errorDescription: String? {
        switch self {
        case .activePlan:
            "This is the program you're running. Make another one active first."
        case let .hasRun(since):
            "You've trained on this program since \(since), and those weeks keep its name. It stays in your list."
        case .unknownPlan:
            "That program is no longer on this device."
        }
    }
}

public extension AppDatabase {

    // MARK: - Create

    /// A new, benched program: its `plans` row and its days, in one
    /// transaction. Returns the minted program id.
    ///
    /// `days` may carry any `programId` — a template's, a copy's — and are
    /// re-homed under the new id.
    ///
    /// ── IT STARTS FROM THE RUNNING PROGRAM'S NUMBERS ────────────────────────
    /// A program with no `plan_phase_goals` rows has no targets, and running
    /// it would write `.empty` — 0 kcal — over the user's own numbers
    /// (review, Precision E). So a new program copies the running program's
    /// phase goals and weekly volume, both phases, as its starting point; a
    /// goal set on it later replaces its own phase's row.
    @discardableResult
    func createPlan(
        userId: String, name: String, blurb: String = "",
        goal: ProgramGoal? = nil, goalTarget: ProgramGoalTarget? = nil, days: [RoutineDay] = []
    ) throws -> String {
        try writer.write { db in
            let running = try Self.runningProgramId(db, userId: userId)
            let id = try Self.createPlan(
                db, userId: userId, programId: nil, name: name, blurb: blurb, isLegacy: false,
                sort: nil, goal: goal, goalTarget: goalTarget, days: days
            ).programId
            if !running.isEmpty, running != id {
                try Self.copyTargets(db, userId: userId, from: running, to: id)
            }
            return id
        }
    }

    /// The program the app runs — the stored selection resolved against the
    /// rows, the rule `scheduleContext` and `deletePlan` share.
    static func runningProgramId(_ db: Database, userId: String) throws -> String {
        let rows = try PlanRow.filter(Column("user_id") == userId).fetchAll(db)
        let goals = try UserGoalRow.filter(Column("user_id") == userId).fetchOne(db)
        return Programs.resolvePlanId(
            stored: goals?.activePlan ?? goals?.activeProgram,
            in: rows.compactMap(PlanInfo.init),
            activeFallback: rows.first { $0.active == true }?.programId
        )
    }

    /// Both phases' goals and weekly volume from one program onto another.
    static func copyTargets(_ db: Database, userId: String, from source: String, to target: String) throws {
        let owner = Column("user_id") == userId
        for var row in try PlanPhaseGoalRow.filter(owner && Column("plan_id") == source).fetchAll(db) {
            row.planId = target
            row.updatedAt = Self.localWriteTimestamp
            try row.save(db)
            try Self.enqueueRowUpsert(
                table: PlanPhaseGoalRow.databaseTableName, id: Self.rowID([userId, target, row.phase]), in: db
            )
        }
        for var row in try PlanPhaseVolumeRow.filter(owner && Column("plan_id") == source).fetchAll(db) {
            row.planId = target
            row.updatedAt = Self.localWriteTimestamp
            try row.save(db)
            try Self.enqueueRowUpsert(
                table: PlanPhaseVolumeRow.databaseTableName, id: Self.rowID([userId, target, row.phase, row.muscle]), in: db
            )
        }
    }

    /// The same, inside a caller's transaction — the seed's form.
    ///
    /// `programId` nil mints one from the name. `sort` nil APPENDS (after the
    /// last program). The sign-up trigger's placeholder row ("My Plan", no
    /// `program_id`) is CLAIMED when present, never duplicated — the rule the
    /// seed has always had (`AccountSeed`'s header).
    ///
    /// Returns the id and the movements the catalogue could not resolve.
    static func createPlan(
        _ db: Database, userId: String, programId: String?, name: String, blurb: String,
        isLegacy: Bool, sort: Int?, goal: ProgramGoal?, goalTarget: ProgramGoalTarget?, days: [RoutineDay]
    ) throws -> (programId: String, unresolved: [String]) {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = try PlanRow.filter(Column("user_id") == userId).fetchAll(db)
        let id = try programId ?? mintProgramId(db, userId: userId, from: label)

        let same = existing.first { $0.programId == id }
        var row = same
            ?? existing.first { ($0.programId ?? "").isEmpty }
            ?? PlanRow(id: newOnyxID(), userId: userId, name: label)
        // A claimed placeholder arrives `active = true` (the trigger's
        // default); a program created here is benched until it is run.
        if same == nil { row.active = false }
        row.name = label.isEmpty ? "Program" : label
        row.programId = id
        row.blurb = blurb
        row.isLegacy = isLegacy
        row.sort = sort ?? ((existing.filter { !($0.programId ?? "").isEmpty }.compactMap(\.sort).max() ?? -1) + 1)
        if let goal { row.goalKind = goal.rawValue }
        if let goalTarget { row.goalTarget = JSONText(raw: goalTarget.encoded()) }
        if row.createdAt == nil { row.createdAt = Self.localWriteTimestamp }
        try row.save(db)
        try Self.enqueueRowUpsert(table: PlanRow.databaseTableName, id: row.id, in: db)

        return (id, try Self.writeDays(db, userId: userId, programId: id, days: days))
    }

    /// Days into a program that exists — the goal sheet's "fill this program
    /// with the recommended template". Re-homed under `programId` whatever id
    /// they arrived with. Returns the movements the catalogue could not name.
    @discardableResult
    func writeDays(userId: String, programId: String, days: [RoutineDay]) throws -> [String] {
        try writer.write { db in try Self.writeDays(db, userId: userId, programId: programId, days: days) }
    }

    /// The deck, resolved against the catalogue as the builder resolves it
    /// (D3), so the logger stamps a uuid rather than the legacy slug.
    static func writeDays(_ db: Database, userId: String, programId: String, days: [RoutineDay]) throws -> [String] {
        let index = ExerciseIndex(
            try Exercise.fetchAll(db).map { RemoteExercise(id: $0.id, name: $0.name, slug: $0.slug) }
        )
        var unresolved: [String] = []
        for day in days {
            var homed = day
            homed.programId = programId
            let (payload, missing) = day.payload.resolving(index)
            homed.payload = payload
            unresolved.append(contentsOf: missing)
            try Self.saveRoutineDay(db, userId: userId, homed)
        }
        return unresolved
    }

    /// A program id nothing of this user's already answers to.
    ///
    /// Slugged from the name ("Upper / Lower" → `upper-lower`) and made unique
    /// with a counter. "Nothing answers to it" is wider than the live plans:
    /// a deck, a goals row or a volume row left under an id by an older build
    /// would otherwise be ADOPTED by the new program. And never an alias
    /// `Programs.normalizePlanId` rewrites — a program minted as `apex51`
    /// would read as Onyx-5 everywhere.
    static func mintProgramId(_ db: Database, userId: String, from name: String) throws -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let slug = folded
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let stem = slug.isEmpty ? "program" : String(slug.prefix(40))
        var taken = Set<String>()
        for (table, column) in [
            ("plans", "program_id"), ("routines", "program_id"), ("plan_phase_goals", "plan_id"),
            ("plan_phase_volume", "plan_id"), ("plan_phases", "plan_id"), ("program_day_layout", "program_id"),
        ] {
            taken.formUnion(try String.fetchAll(
                db, sql: "SELECT DISTINCT \(column) FROM \(table) WHERE user_id = ? AND \(column) IS NOT NULL",
                arguments: [userId]
            ))
        }
        // The stored selection too: an id `user_goals` still names (a plan
        // deleted on another device, not yet pulled away) must not be reborn.
        if let goals = try UserGoalRow.filter(Column("user_id") == userId).fetchOne(db) {
            taken.formUnion([goals.activePlan, goals.activeProgram].compactMap { $0 })
        }
        func free(_ candidate: String) -> Bool {
            !taken.contains(candidate) && Programs.normalizePlanId(candidate) == candidate
        }
        if free(stem) { return stem }
        var n = 2
        while !free("\(stem)-\(n)") { n += 1 }
        return "\(stem)-\(n)"
    }

    // MARK: - Edit

    /// Change a program's label. The id never moves.
    func renamePlan(userId: String, programId: String, name: String) throws {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        try writer.write { db in
            guard var row = try Self.planRow(db, userId: userId, programId: programId) else {
                throw PlanWriteError.unknownPlan
            }
            guard row.name != label else { return }
            row.name = label
            try row.save(db)
            try Self.enqueueRowUpsert(table: PlanRow.databaseTableName, id: row.id, in: db)
        }
    }

    /// Remove a benched, never-run program and everything keyed on its id.
    ///
    /// Refused for the running program (`activePlan`) and for one that has
    /// run (`hasRun`): see `PlanWriteError`. Everything else it owns — its
    /// days, its phase goals, its weekly volume, its weekday layout — goes in
    /// the same transaction, locally and in the queue, so no orphan row is
    /// left for a later program to adopt.
    func deletePlan(userId: String, programId: String) throws {
        try writer.write { db in
            let rows = try PlanRow.filter(Column("user_id") == userId).fetchAll(db)
            guard let row = rows.first(where: { $0.programId == programId }) else {
                throw PlanWriteError.unknownPlan
            }
            let running = try Self.runningProgramId(db, userId: userId)
            if running == programId || row.active == true { throw PlanWriteError.activePlan }
            // ── HISTORY IS A SESSION IT OWNS, NOT A START DATE ──────────────
            // `started_on` is set on the first run and never moves, so a
            // program run for a minute by mistake would be undeletable. What
            // deleting would actually damage is a logged session whose week
            // is labelled with this program (`Schedule.planId(owning:)`), or
            // a dated block that names it.
            if let since = row.startedOn {
                let context = try Self.scheduleContext(db, userId: userId)
                let dates = try String.fetchAll(
                    db, sql: "SELECT DISTINCT date FROM workout_sessions WHERE user_id = ?", arguments: [userId]
                )
                let owns = dates.contains { Schedule.planId(owning: $0, in: context) == programId }
                let blocks = try PlanPhaseRow.filter(Column("user_id") == userId && Column("plan_id") == programId).fetchCount(db)
                if owns || blocks > 0 { throw PlanWriteError.hasRun(since: since) }
            }

            try row.delete(db)
            try Self.enqueueRowDelete(table: PlanRow.databaseTableName, key: ["id": row.id], in: db)

            let owner = Column("user_id") == userId
            for day in try RoutineRow.filter(owner && Column("program_id") == programId).fetchAll(db) {
                try day.delete(db)
                try Self.enqueueRowDelete(
                    table: RoutineRow.databaseTableName,
                    key: ["user_id": userId, "program_id": programId, "day_key": day.dayKey], in: db
                )
            }
            for goal in try PlanPhaseGoalRow.filter(owner && Column("plan_id") == programId).fetchAll(db) {
                try goal.delete(db)
                try Self.enqueueRowDelete(
                    table: PlanPhaseGoalRow.databaseTableName,
                    key: ["user_id": userId, "plan_id": programId, "phase": goal.phase], in: db
                )
            }
            for volume in try PlanPhaseVolumeRow.filter(owner && Column("plan_id") == programId).fetchAll(db) {
                try volume.delete(db)
                try Self.enqueueRowDelete(
                    table: PlanPhaseVolumeRow.databaseTableName,
                    key: ["user_id": userId, "plan_id": programId, "phase": volume.phase, "muscle": volume.muscle], in: db
                )
            }
            for layout in try ProgramDayLayoutRow.filter(owner && Column("program_id") == programId).fetchAll(db) {
                try layout.delete(db)
                try Self.enqueueRowDelete(
                    table: ProgramDayLayoutRow.databaseTableName,
                    key: ["user_id": userId, "program_id": programId], in: db
                )
            }
        }
    }

    // MARK: - Goal

    /// Give a program its goal, and the targets that goal produces.
    ///
    /// One transaction: `plans.goal_kind` + `goal_target`, and the
    /// `plan_phase_goals` row of the phase the goal trains in — the macros the
    /// user approved, the body destination, the safe weekly band.
    ///
    /// ── THE OTHER PHASE IS LEFT ALONE WHEN IT HAS A ROW ─────────────────────
    /// The founder's cut row is 1,935 / 190 — tuned by hand over months — and
    /// setting a bulk goal must not overwrite it. A plan with NO row for the
    /// other phase gets that phase's own arithmetic (the seed's rule), so a
    /// later phase switch never lands on a screen of zeros.
    ///
    /// It does not RUN the program — `activateProgram` does, and the caller
    /// decides whether to (the sheet does when this is the running plan).
    func applyProgramGoal(
        userId: String, programId: String, goal: ProgramGoal, target: ProgramGoalTarget,
        targets: StartingTargets, weightKg: Double?
    ) throws {
        try writer.write { db in
            guard var plan = try Self.planRow(db, userId: userId, programId: programId) else {
                throw PlanWriteError.unknownPlan
            }
            plan.goalKind = goal.rawValue
            plan.goalTarget = JSONText(raw: target.encoded())
            try plan.save(db)
            try Self.enqueueRowUpsert(table: PlanRow.databaseTableName, id: plan.id, in: db)

            let rate = weightKg.map { StartingTargetsBuilder.weeklyRate(weightKg: $0, programGoal: goal) }
            try Self.writePhaseGoals(
                db, userId: userId, planId: programId, phase: goal.phase, targets: targets,
                rate: rate, target: target
            )

            let other: ProgramPhase = goal.phase == .bulk ? .cut : .bulk
            let hasOther = try PlanPhaseGoalRow
                .filter(Column("user_id") == userId && Column("plan_id") == programId && Column("phase") == other.rawValue)
                .fetchCount(db) > 0
            if !hasOther, let weightKg {
                let direction: StartingGoal = other == .bulk ? .bulk : .cut
                try Self.writePhaseGoals(
                    db, userId: userId, planId: programId, phase: other,
                    targets: StartingTargetsBuilder.build(weightKg: weightKg, goal: direction),
                    rate: StartingTargetsBuilder.weeklyRate(weightKg: weightKg, goal: direction), target: nil
                )
            }
        }
    }

    /// One `plan_phase_goals` row. With a `target`, its three destinations are
    /// written — a nil one cleared on the server too (the columns are long
    /// live), so a goal changed from "72 kg" to "12 % body fat" does not keep
    /// the 72 on the other device.
    private static func writePhaseGoals(
        _ db: Database, userId: String, planId: String, phase: ProgramPhase, targets: StartingTargets,
        rate: (min: Double, max: Double)?, target: ProgramGoalTarget?
    ) throws {
        var row = try PlanPhaseGoalRow
            .filter(Column("user_id") == userId && Column("plan_id") == planId && Column("phase") == phase.rawValue)
            .fetchOne(db)
            ?? PlanPhaseGoalRow(userId: userId, planId: planId, phase: phase.rawValue, updatedAt: Self.localWriteTimestamp)
        row.label = row.label ?? phase.label
        row.kcal = targets.kcal
        row.proteinG = targets.proteinG
        row.carbsG = targets.carbsG
        row.fatG = targets.fatG
        row.fiberG = targets.fiberG
        row.stepsGoal = targets.stepsGoal
        row.rateMinKgWk = rate?.min
        row.rateMaxKgWk = rate?.max
        var nulls: [String] = []
        if let target {
            row.targetWeightKg = target.targetWeightKg
            row.targetBodyFatPct = target.targetBodyFatPct
            row.targetMuscleMassKg = target.targetMuscleMassKg
            if target.targetWeightKg == nil { nulls.append("target_weight_kg") }
            if target.targetBodyFatPct == nil { nulls.append("target_body_fat_pct") }
            if target.targetMuscleMassKg == nil { nulls.append("target_muscle_mass_kg") }
        }
        row.updatedAt = Self.localWriteTimestamp
        try row.save(db)
        try Self.enqueueRowUpsert(
            table: PlanPhaseGoalRow.databaseTableName, id: Self.rowID([userId, planId, phase.rawValue]),
            nulls: nulls, in: db
        )
    }

    // MARK: - Run

    /// Switch the running program and phase — the You tab's phase switch,
    /// moved here from `SettingsModel.activate` so Programs and Settings run
    /// the SAME five writes: the phase's goals into `user_goals`, the plan and
    /// phase themselves, the date the phase started, and the dated registry
    /// the charts label eras from.
    ///
    /// ── NO ROW, NO NUMBERS WRITTEN ──────────────────────────────────────────
    /// A phase the program has no `plan_phase_goals` row for moves the plan
    /// and the phase and leaves the user's numbers alone. `SettingsModel`
    /// used to write `.empty` there — 0 kcal over the user's own figures —
    /// which no plan could reach until programs could be made on the phone.
    ///
    /// ── A CLEARED TARGET IS SENT AS A CLEAR ─────────────────────────────────
    /// A nil stays out of a push body (`encodeIfPresent`), so a body target
    /// the phase no longer has would survive on the server and come back on
    /// the next pull. The three target columns are live, so a nil one is
    /// named in the upsert's `nulls`.
    func activateProgram(userId: String, programId: String, phase: ProgramPhase, startedOn: String) throws {
        let goals = try phaseGoals(userId: userId, planId: programId, phase: phase)
        let row = try editUserGoals(userId: userId) { row in
            if let goals {
                row.calorieGoal = Int(goals.calorieGoal)
                row.proteinGoalG = goals.proteinGoalG.map { Int($0) }
                row.carbsGoalG = goals.carbsGoalG.map { Int($0) }
                row.fatGoalG = goals.fatGoalG.map { Int($0) }
                row.stepsGoal = Int(goals.stepsGoal)
                row.targetWeightKg = goals.targetWeightKg
                row.targetBodyFatPct = goals.targetBodyFatPct
                row.targetMuscleMassKg = goals.targetMuscleMassKg
            }
            row.activePlan = programId
            row.activeProgram = programId
            row.activePhase = phase.rawValue
            row.goalPreset = phase.rawValue
            row.phaseStartedOn = startedOn
        }
        if goals != nil {
            let cleared = [
                ("target_weight_kg", row.targetWeightKg), ("target_body_fat_pct", row.targetBodyFatPct),
                ("target_muscle_mass_kg", row.targetMuscleMassKg),
            ].filter { $0.1 == nil }.map(\.0)
            if !cleared.isEmpty {
                try enqueueRowUpsert(table: UserGoalRow.databaseTableName, id: row.id, nulls: cleared)
            }
        }
        try activatePlanRow(userId: userId, programId: programId, startedOn: startedOn)
    }

    // MARK: - Reads

    static func planRow(_ db: Database, userId: String, programId: String) throws -> PlanRow? {
        try PlanRow.filter(Column("user_id") == userId && Column("program_id") == programId).fetchOne(db)
    }
}
