import Foundation

/// The pure schedule core — `scheduleDayIn` / `isTrainingDayIn` /
/// `sessionTargetIn` from the web app's `lib/programs.ts`.
///
/// ── WHY A CONTEXT VALUE AND NOT MORE ARGUMENTS ───────────────────────────────
/// The web resolves four things — the plan, the phase, the per-date swaps and
/// the permanent weekday layout — and every one of them lived behind
/// `localStorage`. On a server all four silently answered with a default, so
/// the widget announced the wrong session and the scorer graded rest days
/// against a week the athlete was not training. The fix was to state the
/// inputs once, as a value, and run exactly one rule over them. That value is
/// this struct; the native app fills it from GRDB the way a route fills it from
/// `user_goals`, `schedule_overrides` and `program_day_layout`.
///
/// ── AND SINCE W2 IT CARRIES THE CATALOGUE TOO ────────────────────────────────
/// The decks (`routines`), the plan entries with their start dates (`plans`)
/// and the dated blocks (`plan_phases`) used to be compiled in, so a context
/// needed only the plan's ID to find its deck. They are rows now, and the
/// context is where they travel: every reader that already took a context —
/// the scorer, the widget, the export, the WATCH (it is the wire format of
/// `WatchContext`) — keeps working, and reads the athlete's own rows. The
/// three new fields decode as empty when absent, so a watch on the previous
/// build still decodes a context this build sends.
///
/// Nothing here reads a global or a clock.
public struct ScheduleDay: Codable, Equatable, Sendable {
    public var label: String
    public var sub: String?
    /// Absent only for a resolver that hands back a bare label.
    public var dayKey: String?

    public init(label: String, sub: String? = nil, dayKey: String? = nil) {
        self.label = label; self.sub = sub; self.dayKey = dayKey
    }

    init(_ day: ProgramDay) {
        self.init(label: day.label, sub: day.sub, dayKey: day.key)
    }
}

/// Everything the schedule rule needs, with nothing read from a global.
public struct ScheduleContext: Codable, Equatable, Sendable {
    public var programId: String
    public var phase: ProgramPhase
    /// `date → day_key | "rest"` (`schedule_overrides`).
    public var overrides: [String: String]
    /// `dayKey → weekday` for THIS plan (`program_day_layout`).
    public var layout: DayLayout
    /// The decks — `routines` rows folded into programs (W2).
    public var programs: [Program]
    /// The plan entries — `plans` rows — with their `started_on` dates.
    public var plans: [PlanInfo]
    /// The dated blocks — `plan_phases` rows — in start order.
    public var phases: [PhaseDef]

    public init(
        programId: String, phase: ProgramPhase, overrides: [String: String] = [:], layout: DayLayout = [:],
        programs: [Program] = [], plans: [PlanInfo] = [], phases: [PhaseDef] = []
    ) {
        self.programId = programId; self.phase = phase; self.overrides = overrides; self.layout = layout
        self.programs = programs; self.plans = plans; self.phases = Phases.sorted(phases)
    }

    enum CodingKeys: String, CodingKey { case programId, phase, overrides, layout, programs, plans, phases }

    /// The three W2 fields are optional on the wire: a context stored or sent
    /// before them decodes as an empty catalogue, never as a failure.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        programId = try c.decode(String.self, forKey: .programId)
        phase = try c.decode(ProgramPhase.self, forKey: .phase)
        overrides = try c.decodeIfPresent([String: String].self, forKey: .overrides) ?? [:]
        layout = try c.decodeIfPresent(DayLayout.self, forKey: .layout) ?? [:]
        programs = try c.decodeIfPresent([Program].self, forKey: .programs) ?? []
        plans = try c.decodeIfPresent([PlanInfo].self, forKey: .plans) ?? []
        phases = Phases.sorted(try c.decodeIfPresent([PhaseDef].self, forKey: .phases) ?? [])
    }

    /// The deck for a plan id, or nil when the rows do not describe one.
    public func program(id: String) -> Program? {
        programs.first { $0.id == id }
    }

    /// The active plan's deck — empty, under the active id, when there is none.
    public var activeProgram: Program {
        program(id: programId) ?? Program(id: programId, label: plans.first { $0.id == programId }?.label ?? programId, days: [])
    }

    /// `plans.started_on` of the active plan — what `Week` and the streak
    /// count from. Nil for a plan never started.
    public var planStartISO: String? {
        plans.first { $0.id == programId }?.startedOn
    }

    /// The week-0 anchor: the week the active plan started in (Sunday-cut, as
    /// the programme week has always been counted).
    public var weekZeroStart: String? {
        Week.anchor(planStartedOn: planStartISO)
    }
}

public enum Schedule {

    /// The override value that clears a training day. `REST_OVERRIDE`.
    public static let restOverride = "rest"

    /// Which plan OWNS a date.
    ///
    /// The CURRENT era opens on the latest `started_on` any plan carries, and
    /// every date from there on belongs to the plan the athlete has SELECTED
    /// (`programId`) — exactly what the compiled `Era.forDate` said with the
    /// founder's 2026-07-15 cut: selected plan after, PPL before. A date before
    /// that boundary belongs to the plan started most recently before it; a
    /// date before any plan began, to the earliest-started plan, because a
    /// session logged before the first block belongs to the block that
    /// followed it. With no dated plans at all, the selected plan.
    public static func planId(owning dateISO: String, in ctx: ScheduleContext) -> String {
        let dated = ctx.plans.compactMap { p in p.startedOn.map { (id: p.id, start: $0) } }
        guard let eraStart = dated.map(\.start).max(), dateISO < eraStart else { return ctx.programId }
        if let owner = dated.filter({ $0.start <= dateISO }).max(by: { $0.start < $1.start }) { return owner.id }
        return dated.min(by: { $0.start < $1.start })?.id ?? ctx.programId
    }

    /// The plan that owns a date, with the layout that applies to it.
    ///
    /// `program_day_layout` records a remap of the plan you are RUNNING, so
    /// only the active plan's dates get it; applying it to a finished block
    /// would move history. A plan the rows do not describe answers with an
    /// empty deck under its own id — a rest day everywhere, never someone
    /// else's Tuesday.
    public static func programForContext(_ ctx: ScheduleContext, _ dateISO: String) -> (program: Program, layout: DayLayout) {
        let owner = planId(owning: dateISO, in: ctx)
        let program = ctx.program(id: owner) ?? Program(id: owner, label: owner, days: [])
        return (program, owner == ctx.programId ? ctx.layout : [:])
    }

    /// `scheduleDayIn` — what is scheduled on a date. nil = rest.
    ///
    /// A per-date swap wins over the weekday default. An override naming a day
    /// this plan does not have is a stale row from a plan the user has left;
    /// it falls through to the weekday default rather than inventing a session.
    public static func scheduleDayIn(_ ctx: ScheduleContext, _ dateISO: String) -> ScheduleDay? {
        let (program, layout) = programForContext(ctx, dateISO)
        if let override = ctx.overrides[dateISO] {
            if override == restOverride { return nil }
            if let od = program.day(key: override) { return ScheduleDay(od) }
        }
        guard let weekday = ISODate.weekday(dateISO) else { return nil }
        return ScheduleLayout.programDayIn(program, layout, weekday).map(ScheduleDay.init)
    }

    /// `isTrainingDayIn`. Note the asymmetry with `scheduleDayIn`, kept on
    /// purpose: ANY non-rest override answers true here — including a stale
    /// key that `scheduleDayIn` would fall through on. The two can disagree
    /// about a Wednesday carrying a key from an abandoned plan; the vectors
    /// pin that, and it is the web's behaviour, not a port slip.
    public static func isTrainingDayIn(_ ctx: ScheduleContext, _ dateISO: String) -> Bool {
        if let override = ctx.overrides[dateISO] { return override != restOverride }
        guard let weekday = ISODate.weekday(dateISO) else { return false }
        let (program, layout) = programForContext(ctx, dateISO)
        return ScheduleLayout.programDayIn(program, layout, weekday) != nil
    }

    /// `sessionTargetIn` — how many sessions the plan schedules in a week, the
    /// denominator on "3/5". Off the UNTRIMMED plan: a cut drops lifts, never
    /// days. Not era-aware — it is about the plan you are running.
    public static func sessionTargetIn(_ ctx: ScheduleContext) -> Int {
        ctx.activeProgram.days.count
    }

    /// Was this date before the active plan began — a week the schedule
    /// cannot honestly speak for? The History strip and the consistency grid
    /// draw only what was logged for such a week.
    public static func isPlannable(_ dateISO: String, in ctx: ScheduleContext) -> Bool {
        guard let start = ctx.weekZeroStart else { return true }
        return dateISO >= start
    }

    /// The legacy era tag `VolumeSplit.resolve` keys on for a session with no
    /// day key: `"ppl"` for a date the PPL plan owns, `"axis"` otherwise. A
    /// compatibility shim for Notion-era rows, not a plan concept.
    public static func legacyEra(_ ctx: ScheduleContext, _ dateISO: String) -> String {
        planId(owning: dateISO, in: ctx) == "ppl" ? "ppl" : "axis"
    }
}
