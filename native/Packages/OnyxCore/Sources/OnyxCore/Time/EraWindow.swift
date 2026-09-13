import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The six windows a chart can be asked to draw — a port of
// the web app's `lib/era/eraWindow.ts` (decision 12).
//
// ── WHAT THIS REPLACES ───────────────────────────────────────────────────────
// Two segmented controls that answered two different questions and called
// themselves the same thing. Trends had `EraFilter { all, ppl, axis }`, whose
// middle pill rendered the string "Axis" — a product name two renames out of
// date, kept because the rawValue was load-bearing for
// `VolumeSplit.splits(forEra:)`. History had its own `EraFilter { all, onyx,
// ppl }`, which spelled the same era "Onyx". Neither was a TIME window: both
// were programme filters, so "the last 30 days" was not askable anywhere and
// "this phase" was not either.
//
// A window is a range and a name for it. The name comes from the phase table,
// the lever schedule or the plan catalogue — never from a `switch` in a view,
// which is how the two spellings got there.
//
// ── EVERY WINDOW ENDS TODAY ──────────────────────────────────────────────────
// These are trailing windows. A range running past today would reserve axis
// space for days that do not exist, drawing every live phase as though it were
// tailing off.
// ─────────────────────────────────────────────────────────────────────────────

/// Which window. `days` carries its own length so 30 and 90 are one case.
public enum EraWindow: Sendable, Equatable, Hashable {
    /// The athlete's own training week, ending today — `user_goals.week_end_day`
    /// through `Week.startDay(fromEndDay:)`, never a hard-coded Sunday. The
    /// window a set target is denominated in, and the muscle atlas card's
    /// default.
    case thisWeek
    /// The programme phase covering today — "Onyx Cut", "Lean Bulk".
    case currentPhase
    /// The run of days ending today that share today's nutrition rung.
    case currentLever
    /// From the day the cut block opened. Legacy: its label is the fixed string
    /// "Since cut", which is a lie on a bulk. `currentProgram` is the same range
    /// under the plan's own name and should be preferred by new callers.
    case sinceCutStart
    /// From `plans.started_on` of the active plan, under that plan's OWN label —
    /// "Onyx-5 Cut", not "Since cut".
    case currentProgram
    /// A trailing count of days, today included.
    case days(Int)
    /// Everything the caller holds.
    case all

    /// Display order; `first` is the default (decision 12).
    public static let modes: [EraWindow] = [
        .currentPhase, .currentLever, .sinceCutStart, .days(30), .days(90), .all,
    ]

    public static let `default`: EraWindow = .currentPhase

    /// A stable key — what a `Picker` binds to, and what a preference stores.
    ///
    /// The span is CLAMPED the same way `resolve` clamps it, so the key names
    /// the window that would actually be drawn. Without that, `.days(0)` writes
    /// `days:0`, which `fromKey` refuses — and a preference that serializes but
    /// cannot be read back is a preference that silently reverts to the default.
    public var key: String {
        switch self {
        case .currentPhase: "currentPhase"
        case .currentLever: "currentLever"
        case .sinceCutStart: "sinceCutStart"
        case .thisWeek: "thisWeek"
        case .currentProgram: "currentProgram"
        case .days(let n): "days:\(Swift.max(1, n))"
        case .all: "all"
        }
    }

    /// Every keyed window, `modes` plus the two the muscle atlas card offers.
    ///
    /// `fromKey` walked `modes` until W3, so a window OUTSIDE the screen
    /// picker's six serialised fine and read back as nil. Nothing persists a
    /// window today — both pickers are plain `@State` — so this is a trap
    /// disarmed rather than a bug fixed: the first caller to store one would
    /// have found `.thisWeek` reverting to the default with no error anywhere.
    static let keyed: [EraWindow] = modes + [.thisWeek, .currentProgram]

    /// The window a key names, or nil.
    public static func fromKey(_ key: String) -> EraWindow? {
        if key.hasPrefix("days:") {
            guard let n = Int(key.dropFirst(5)), n > 0 else { return nil }
            return .days(n)
        }
        return keyed.first { $0.key == key }
    }
}

/// `{ "kind": "days", "n": 30 }` — the shape the golden vector carries. Written
/// out rather than synthesised because the synthesised form for an enum with an
/// associated value is `{"days":{"_0":30}}`, which no TypeScript would emit.
extension EraWindow: Codable {
    private enum CodingKeys: String, CodingKey { case kind, n }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "thisWeek": self = .thisWeek
        case "currentProgram": self = .currentProgram
        case "currentPhase": self = .currentPhase
        case "currentLever": self = .currentLever
        case "sinceCutStart": self = .sinceCutStart
        case "all": self = .all
        case "days": self = .days(try c.decode(Int.self, forKey: .n))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c, debugDescription: "Unknown era window kind \"\(kind)\""
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .days(let n):
            try c.encode("days", forKey: .kind)
            try c.encode(n, forKey: .n)
        default:
            try c.encode(key, forKey: .kind)
        }
    }
}

/// What the caller knows that the window cannot derive.
public struct EraWindowInput: Codable, Sendable, Equatable {
    /// The logical day the window ends on.
    public var today: String
    /// The active plan's display name — the `plans` row's.
    public var planLabel: String
    /// `user_goals.week_end_day` — 0 = Sunday-ending. `.thisWeek` is the only
    /// window that reads it, and it reads it through `Week.startDay(fromEndDay:)`
    /// so there is still exactly one place that knows the mapping.
    public var weekEndDay: Int?
    /// `user_goals.active_lever`, verbatim.
    public var storedLever: String?
    /// `user_goals.maintenance_until` — a release that closes itself.
    public var releaseEndsOn: String?
    /// The oldest date the caller has anything for, and the whole of what
    /// "All" can honestly mean. Without it "All" would need an invented floor,
    /// and every candidate is either months of empty axis or the cut start —
    /// which is what "Since cut" already says.
    public var firstDataISO: String?
    /// `plans.started_on` of the active plan — what "Since cut" opens on.
    public var planStartISO: String?
    /// The dated blocks (`plan_phases`) — what "Current phase" walks.
    public var phases: [PhaseDef]
    /// The rungs and the schedule — what "Current lever" walks. `storedLever`
    /// and `releaseEndsOn` above are the ladder's selection, kept as fields
    /// because the fixtures set them by name.
    public var rungs: [NutritionLever]
    public var periods: [LeverPeriod]

    public init(
        today: String, planLabel: String, weekEndDay: Int? = nil, storedLever: String? = nil,
        releaseEndsOn: String? = nil, firstDataISO: String? = nil,
        planStartISO: String? = nil, phases: [PhaseDef] = [], rungs: [NutritionLever] = [], periods: [LeverPeriod] = []
    ) {
        self.today = today
        self.planLabel = planLabel
        self.weekEndDay = weekEndDay
        self.storedLever = storedLever
        self.releaseEndsOn = releaseEndsOn
        self.firstDataISO = firstDataISO
        self.planStartISO = planStartISO
        self.phases = phases
        self.rungs = rungs
        self.periods = periods
    }

    public var ladder: LeverLadder {
        LeverLadder(rungs: rungs, periods: periods, stored: storedLever, releaseEndsOn: releaseEndsOn)
    }

    enum CodingKeys: String, CodingKey { case today, planLabel, weekEndDay, storedLever, releaseEndsOn, firstDataISO, planStartISO, phases, rungs, periods }

    /// The W2 table fields are optional on the wire: an input written before
    /// them (the golden fixtures) decodes with empty tables, never as a failure.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        today = try c.decode(String.self, forKey: .today)
        planLabel = try c.decode(String.self, forKey: .planLabel)
        weekEndDay = try c.decodeIfPresent(Int.self, forKey: .weekEndDay)
        storedLever = try c.decodeIfPresent(String.self, forKey: .storedLever)
        releaseEndsOn = try c.decodeIfPresent(String.self, forKey: .releaseEndsOn)
        firstDataISO = try c.decodeIfPresent(String.self, forKey: .firstDataISO)
        planStartISO = try c.decodeIfPresent(String.self, forKey: .planStartISO)
        phases = try c.decodeIfPresent([PhaseDef].self, forKey: .phases) ?? []
        rungs = try c.decodeIfPresent([NutritionLever].self, forKey: .rungs) ?? []
        periods = try c.decodeIfPresent([LeverPeriod].self, forKey: .periods) ?? []
    }
}

/// A window, resolved: the range and the words that name it.
public struct ResolvedEraWindow: Codable, Sendable, Equatable, Hashable {
    /// The pill's text, and the chart caption's.
    public var label: String
    /// First day, inclusive.
    public var startISO: String
    /// Last day, inclusive — always the input's `today`.
    public var endISO: String
    /// Inclusive day count, floored at 1.
    public var days: Int

    public init(label: String, startISO: String, endISO: String, days: Int) {
        self.label = label
        self.startISO = startISO
        self.endISO = endISO
        self.days = days
    }

    /// Is this date inside the window? Both ends inclusive, string compare —
    /// the same test every other dated read in this package uses.
    public func contains(_ dateISO: String) -> Bool {
        dateISO >= startISO && dateISO <= endISO
    }
}

public extension EraWindow {

    /// Inclusive day count between two ISO dates, floored at 1.
    static func dayCount(from: String, to: String) -> Int {
        guard let a = ISODate.dayNumber(from), let b = ISODate.dayNumber(to) else { return 1 }
        return Swift.max(1, b - a + 1)
    }

    /// How far back the lever walk may go: the first row of the schedule, else
    /// the plan's start, else today. Before it there was no rung and every day
    /// answers the same nil, so an unfloored walk would step to the epoch one
    /// day at a time.
    static func leverFloor(_ input: EraWindowInput) -> String {
        input.periods.first?.from ?? input.planStartISO ?? input.today
    }

    /// The first day of the run ending on `today` that shares today's rung.
    ///
    /// A walk, not a lookup in `Levers.schedule`, and deliberately: the rung in
    /// force is `leverForDate`, which is the SCHEDULE for past days and the
    /// STORED selection from today onward. When those disagree — a rung pulled
    /// this morning that the schedule does not know about — the run genuinely
    /// is one day long, and reading the schedule's `from` would claim a
    /// fortnight had been eaten under a rung chosen at breakfast.
    static func leverRunStart(_ input: EraWindowInput) -> String {
        let today = input.today
        let ladder = input.ladder
        let id = Levers.leverForDate(today, today: today, in: ladder)
        let floor = leverFloor(input)
        var start = today
        while let prev = ISODate.addDays(start, -1), prev >= floor {
            guard Levers.leverForDate(prev, today: today, in: ladder) == id
            else { break }
            start = prev
        }
        return start
    }

    /// The window this mode names, on a given day.
    ///
    /// A start after `today` is clamped to `today`, so the worst a bad anchor
    /// can do is draw a single day.
    func resolve(_ input: EraWindowInput) -> ResolvedEraWindow {
        let today = input.today
        func clamp(_ startISO: String, _ label: String) -> ResolvedEraWindow {
            let start = startISO > today ? today : startISO
            return ResolvedEraWindow(
                label: label, startISO: start, endISO: today,
                days: EraWindow.dayCount(from: start, to: today)
            )
        }

        switch self {
        case .thisWeek:
            // The athlete's week, not the calendar's: `week_end_day` is what the
            // per-muscle set targets are denominated in, and a hard-coded Sunday
            // here would grade a Monday-start week against six of its own days
            // and one of somebody else's. That Sunday was real: it is what
            // `MuscleAggregator.weekStartUTC` did until W3 deleted it.
            // Ending TODAY, not at the week's end — every window here is
            // trailing (see the header). The widget's week is the whole
            // `[start, start + 7)` span, so a session somehow dated later this
            // week counts on the tile and not here.
            return clamp(Week.start(of: today, startDay: Week.startDay(fromEndDay: input.weekEndDay)), "This week")

        case .currentPhase:
            // No phase covers the day — the gap around the Thailand trip is a
            // real one. The plan is still a true name for what is running.
            guard let span = Phases.span(for: today, in: input.phases) else {
                return clamp(input.firstDataISO ?? today, "\(input.planLabel) Era")
            }
            return clamp(span.start, span.def.eraTag ?? span.def.name)

        case .currentLever:
            let ladder = input.ladder
            let id = Levers.leverForDate(today, today: today, in: ladder)
            // `lever(byId:)` is nil for no rung and for a day before the first
            // period, which is the point: it names the ABSENCE of a rung.
            return clamp(EraWindow.leverRunStart(input), Levers.lever(byId: id, in: ladder)?.label ?? "Custom")

        case .sinceCutStart, .currentProgram:
            // The active plan's first day. A plan never started has no "since".
            //
            // ONE arm for two cases: the range is identical and only the NAME
            // differs — `.currentProgram` wears the plan's own label, because a
            // filter pill reading "Since cut" on a bulk is exactly the
            // hard-coded era name `EraWindow` was built to replace. Two arms
            // spelled the same expression twice, and the next change to the
            // anchor chain would have had two places to land.
            return clamp(
                input.planStartISO ?? input.firstDataISO ?? today,
                self == .currentProgram ? input.planLabel : "Since cut"
            )

        case .days(let n):
            let span = Swift.max(1, n)
            return clamp(ISODate.addDays(today, -(span - 1)) ?? today, "\(span) d")

        case .all:
            return clamp(input.firstDataISO ?? today, "All")
        }
    }
}

public extension ResolvedEraWindow {
    /// Which ERA's splits this window's charts should offer.
    ///
    /// The volume chart keys its split pills off this, and the two eras bucket
    /// sessions differently — a PPL week has Push/Pull/Legs and an Onyx week
    /// has none of them. A window that starts before the cut and ends today
    /// spans both, so it gets both.
    ///
    /// `cutStartISO` is the active plan's `started_on`; with none, every window
    /// is the current era.
    func era(cutStartISO: String?) -> String {
        guard let cut = cutStartISO else { return "axis" }
        if startISO >= cut { return "axis" }
        if endISO < cut { return "ppl" }
        return "all"
    }
}
