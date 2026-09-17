import Foundation
import GRDB
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// The plan catalogue — `plans`, `routines`, `plan_phases`, `lever_periods` as
// the domain reads them, and the ONE place a `ScheduleContext` is assembled.
//
// Until W2 the context carried a plan ID and the deck was compiled in. Now the
// deck, the plan entries and the dated blocks are rows, and every reader that
// used to build a context from four stored values (`TodayFeedBuilder`,
// `WidgetSnapshotBuilder`, the watch bridge, the export, `HistoryWeeks`,
// `WorkoutWeek`, `PulseModel`) gets it from here — so no two of them can
// normalise the plan id, or fold the routines, differently.
// ─────────────────────────────────────────────────────────────────────────────

public extension PlanInfo {
    /// A `plans` row with a `program_id`. The sign-up trigger creates a row
    /// with none ("My Plan"), which is a placeholder, not a plan.
    init?(_ r: PlanRow) {
        guard let id = r.programId, !id.isEmpty else { return nil }
        self.init(
            id: id, label: r.name, blurb: r.blurb ?? "", isLegacy: r.isLegacy ?? false,
            startedOn: r.startedOn, sort: r.sort ?? 0
        )
    }
}

public extension RoutineDay {
    init(_ r: RoutineRow) {
        self.init(
            programId: r.programId, dayKey: r.dayKey, label: r.label, sub: r.sub,
            weekday: r.weekday, accent: r.accent, sort: r.sort,
            payload: RoutinePayload.decode(r.payload.raw) ?? RoutinePayload(exercises: [])
        )
    }
}

public extension PhaseDef {
    init(_ r: PlanPhaseRow) {
        self.init(
            kind: PhaseKind(rawValue: r.kind) ?? .cut, name: r.name, start: r.start, weeks: r.weeks,
            numbered: r.numbered, short: r.short, firstWeek: r.firstWeek,
            era: r.era.flatMap(PhaseEra.init(rawValue:)), eraTag: r.eraTag, planId: r.planId
        )
    }
}

public extension LeverPeriod {
    init(_ r: LeverPeriodRow) {
        self.init(from: r.startsOn, profileKey: r.profileKey, goals: r.goals.flatMap(Self.goals))
    }

    /// `{calorie, protein, carbs, fat, steps}` — the shape the seed wrote and
    /// `recordLeverChange` writes.
    static func goals(_ json: JSONText) -> LeverGoals? {
        guard let data = json.raw.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let calorie = (o["calorie"] as? NSNumber)?.doubleValue
        else { return nil }
        func d(_ k: String) -> Double? { (o[k] as? NSNumber)?.doubleValue }
        return LeverGoals(calorie: calorie, protein: d("protein"), carbs: d("carbs"), fat: d("fat"), steps: d("steps"))
    }

    static func json(_ g: LeverGoals) -> JSONText {
        var o: [String: Any] = ["calorie": g.calorie]
        if let v = g.protein { o["protein"] = v }
        if let v = g.carbs { o["carbs"] = v }
        if let v = g.fat { o["fat"] = v }
        if let v = g.steps { o["steps"] = v }
        let data = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ?? Data("{}".utf8)
        return JSONText(raw: String(decoding: data, as: UTF8.self))
    }
}

public extension PhaseGoals {
    /// A `plan_phase_goals` row, translated. Integer columns become the
    /// domain's doubles; a nullable column stays nil, never 0.
    init(_ r: PlanPhaseGoalRow) {
        let phase = ProgramPhase.stored(r.phase)
        self.init(
            phase: phase, label: r.label ?? phase.label, calorieGoal: Double(r.kcal ?? 0),
            proteinGoalG: r.proteinG.map(Double.init), carbsGoalG: r.carbsG.map(Double.init), fatGoalG: r.fatG.map(Double.init),
            fiberGoalG: r.fiberG.map(Double.init), fiberMin: r.fiberMin.map(Double.init), fiberMax: r.fiberMax.map(Double.init),
            stepsGoal: Double(r.stepsGoal ?? 0),
            targetWeightKg: r.targetWeightKg, targetBodyFatPct: r.targetBodyFatPct, targetMuscleMassKg: r.targetMuscleMassKg,
            rateMinKgWk: r.rateMinKgWk, rateMaxKgWk: r.rateMaxKgWk, bodyFatCeilingPct: r.bodyFatCeilingPct
        )
    }
}

/// The catalogue rows for one user, translated once.
public struct PlanCatalogue: Sendable, Equatable {
    public var plans: [PlanInfo]
    public var programs: [Program]
    public var phases: [PhaseDef]
    /// `plans.active` — the server's idea of the current plan, the fallback
    /// when `user_goals.active_plan` names nothing the rows know.
    public var activePlanId: String?

    public init(plans: [PlanInfo] = [], programs: [Program] = [], phases: [PhaseDef] = [], activePlanId: String? = nil) {
        self.plans = plans; self.programs = programs; self.phases = phases; self.activePlanId = activePlanId
    }

    public static let empty = PlanCatalogue()
}

extension AppDatabase {

    /// `plans` + `routines` + `plan_phases` for a user, as one value.
    static func planCatalogue(_ db: Database, userId: String) throws -> PlanCatalogue {
        let user = Column("user_id") == userId
        let planRows = try PlanRow.filter(user).order(Column("sort"), Column("created_at")).fetchAll(db)
        let plans = planRows.compactMap(PlanInfo.init)
        let routines = try RoutineRow.filter(user).fetchAll(db).map(RoutineDay.init)
        let phases = try PlanPhaseRow.filter(user).order(Column("start")).fetchAll(db).map(PhaseDef.init)
        return PlanCatalogue(
            plans: plans,
            programs: Program.from(routines: routines, plans: plans),
            phases: phases,
            activePlanId: planRows.first { $0.active == true }?.programId
        )
    }

    /// The plan, phase, dated overrides, weekday layout AND the catalogue for
    /// this user — the value `Schedule.scheduleDayIn` turns into "today is
    /// Upper A". Read straight off an OPEN transaction.
    ///
    /// `goals` may be handed in by a caller that already read the row (the
    /// snapshot builder does); it is re-read otherwise.
    static func scheduleContext(_ db: Database, userId: String, goals: UserGoalRow?? = nil) throws -> ScheduleContext {
        let user = Column("user_id") == userId
        let goals = try goals ?? UserGoalRow.filter(user).fetchOne(db)
        let catalogue = try planCatalogue(db, userId: userId)
        let programId = Programs.resolvePlanId(
            stored: goals?.activePlan ?? goals?.activeProgram, in: catalogue.plans, activeFallback: catalogue.activePlanId
        )
        var overrides: [String: String] = [:]
        for row in try ScheduleOverrideRow.filter(user).fetchAll(db) { overrides[row.date] = row.dayKey }
        let layoutRaw = try ProgramDayLayoutRow
            .filter(user && Column("program_id") == programId)
            .fetchOne(db)?.layout.raw
        return ScheduleContext(
            programId: programId,
            phase: ProgramPhase.stored(goals?.activePhase ?? goals?.goalPreset),
            overrides: overrides,
            layout: ScheduleLayout.parseLayout(layoutRaw.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }),
            programs: catalogue.programs,
            plans: catalogue.plans,
            phases: catalogue.phases
        )
    }

    /// The phase goals row for a plan and phase, or nil when the user has none.
    static func phaseGoals(_ db: Database, userId: String, planId: String, phase: ProgramPhase) throws -> PhaseGoals? {
        try PlanPhaseGoalRow
            .filter(Column("user_id") == userId && Column("plan_id") == planId && Column("phase") == phase.rawValue)
            .fetchOne(db)
            .map(PhaseGoals.init)
    }

    /// The weekly set targets for a plan and phase — `plan_phase_volume` rows,
    /// keyed by landmark. A muscle with no row has no target (0).
    static func volumeTargets(_ db: Database, userId: String, planId: String, phase: ProgramPhase) throws -> [LandmarkMuscle: Double] {
        var out: [LandmarkMuscle: Double] = [:]
        for r in try PlanPhaseVolumeRow
            .filter(Column("user_id") == userId && Column("plan_id") == planId && Column("phase") == phase.rawValue)
            .fetchAll(db)
        {
            if let m = LandmarkMuscle(rawValue: r.muscle) { out[m] = Double(r.targetSets) }
        }
        return out
    }

    /// The rung, the schedule and the selection — `LeverLadder` off the rows.
    static func leverLadder(_ db: Database, userId: String, goals: UserGoalRow?? = nil) throws -> LeverLadder {
        let user = Column("user_id") == userId
        let goals = try goals ?? UserGoalRow.filter(user).fetchOne(db)
        return LeverLadder(
            profiles: try TargetProfileRow.filter(user).order(Column("sort")).fetchAll(db).compactMap(TargetProfile.init),
            periods: try LeverPeriodRow.filter(user).order(Column("starts_on")).fetchAll(db).map(LeverPeriod.init),
            stored: goals?.activeLever,
            releaseEndsOn: goals?.maintenanceUntil
        )
    }
}

public extension AppDatabase {

    /// Whose mirror this store is — the goals row's user, else the user any
    /// `plans` row names. The local store holds ONE user's rows, and a reader
    /// that filters on an id in hand answers "nothing" whenever that id is not
    /// the one the rows were written under (every preview, every screenshot,
    /// any read before auth resolves). Empty when the store is empty.
    func localUserId() -> String {
        (try? writer.read { db in
            try UserGoalRow.fetchOne(db)?.userId ?? PlanRow.fetchOne(db)?.userId
        }) ?? nil ?? ""
    }

    /// The catalogue, for a caller outside a transaction.
    func planCatalogue(userId: String) throws -> PlanCatalogue {
        try writer.read { db in try Self.planCatalogue(db, userId: userId) }
    }

    /// The rungs, the schedule of rungs and the selection, off the rows.
    func leverLadder(userId: String) throws -> LeverLadder {
        try writer.read { db in try Self.leverLadder(db, userId: userId) }
    }

    /// The `plan_phase_goals` row for a plan and phase, as a value; nil when
    /// the user has none for that pair.
    func phaseGoals(userId: String, planId: String, phase: ProgramPhase) throws -> PhaseGoals? {
        try writer.read { db in try Self.phaseGoals(db, userId: userId, planId: planId, phase: phase) }
    }

    /// The weekly set targets a plan and phase prescribe (`plan_phase_volume`).
    func volumeTargets(userId: String, planId: String, phase: ProgramPhase) throws -> [LandmarkMuscle: Double] {
        try writer.read { db in try Self.volumeTargets(db, userId: userId, planId: planId, phase: phase) }
    }

    /// The asserted PR floors — session-less `personal_records` rows, per key.
    func prFloors(userId: String) throws -> [String: PrFloor] {
        try writer.read { db in try PrRecorder.floors(db, userId: userId) }
    }

    /// The schedule context — see the static twin.
    func scheduleContext(userId: String) throws -> ScheduleContext {
        try writer.read { db in try Self.scheduleContext(db, userId: userId) }
    }

    /// The rung the user just moved to, recorded as a `lever_periods` row from
    /// today — so the past keeps its rung when the selection moves again.
    ///
    /// Idempotent for one day: a second change on the same day replaces the
    /// day's row rather than adding a second one. `profileKey` nil is "back
    /// to my own numbers".
    ///
    /// ── THE PIN GOES ON THE STRETCH BEING CLOSED ────────────────────────────
    /// A keyless period's `goals` say what "my own numbers" WERE for the days
    /// it covered, so those days keep grading the same after the next edit to
    /// `user_goals`. That is only knowable when the stretch ends: pinning the
    /// numbers at the moment it opens would freeze today's targets at tap
    /// time, deaf to every edit after (`Levers.goalsForDate` reads the live
    /// row for today+ for the same reason). So this writes today's row with no
    /// pin, and pins the PREVIOUS keyless row — if one is still open — with
    /// `ownGoals`, the live numbers as the stretch closes.
    func recordLeverChange(userId: String, profileKey: String?, ownGoals: LeverGoals, today: String) throws {
        try writer.write { db in
            let user = Column("user_id") == userId
            if var open = try LeverPeriodRow
                .filter(user && Column("starts_on") < today)
                .order(Column("starts_on").desc)
                .fetchOne(db),
               open.profileKey == nil, open.goals == nil
            {
                open.goals = LeverPeriod.json(ownGoals)
                open.updatedAt = AppDatabase.localWriteTimestamp
                try open.save(db)
                try Self.enqueueRowUpsert(
                    table: LeverPeriodRow.databaseTableName,
                    id: AppDatabase.rowID([userId, open.startsOn]), nulls: ["profile_key"], in: db
                )
            }
            var row = try LeverPeriodRow
                .filter(user && Column("starts_on") == today)
                .fetchOne(db)
                ?? LeverPeriodRow(userId: userId, startsOn: today, updatedAt: AppDatabase.localWriteTimestamp)
            row.profileKey = profileKey
            row.goals = nil
            row.updatedAt = AppDatabase.localWriteTimestamp
            try row.save(db)
            try Self.enqueueRowUpsert(
                table: LeverPeriodRow.databaseTableName,
                id: AppDatabase.rowID([userId, today]),
                nulls: (profileKey == nil ? ["profile_key"] : []) + ["goals"],
                in: db
            )
        }
    }
}
