import Foundation

/// Day-swap planning — a port of the web app's `lib/schedule/swap.ts`.
///
/// ── THE BUG THIS EXISTS TO FIX ───────────────────────────────────────────────
/// "Rest Day" used to write ONE row: `{today: rest}`. That is not a swap, it is
/// a deletion — the week lost a session and nothing said so. A rest day taken
/// because you slept four hours is a REARRANGEMENT of the week, so taking one
/// has to move the work somewhere: the next date whose effective schedule is
/// already rest, read from the plan (Onyx-5 rests Wed and Sat, PPL Wed and
/// Sat, a plan swapped in Settings brings its own).
///
/// `resolve` is INJECTED rather than imported so the caller decides what
/// "effective" means — in the app that is `Schedule.scheduleDayIn` over the
/// live context. Everything here is a pure function of its arguments.
public struct ScheduleWrite: Codable, Equatable, Sendable {
    public var date: String
    /// A program day key, or `Schedule.restOverride`.
    public var dayKey: String
    public init(date: String, dayKey: String) { self.date = date; self.dayKey = dayKey }
}

public enum RestOutcome: String, Codable, Sendable {
    /// The date was already rest — nothing to do.
    case alreadyRest = "already-rest"
    /// The workout found a home; `movedTo` says where.
    case swapped
    /// Every day inside the horizon is already spoken for.
    case noSlot = "no-slot"
    /// A day with a label but no `dayKey` — there is no key to place anywhere.
    case unscheduled
}

public struct RestDayPlan: Equatable, Sendable {
    public var writes: [ScheduleWrite]
    /// The workout that was on the date, or nil when it was already rest.
    public var moved: ScheduleDay?
    /// Where it landed, or nil when nothing moved / nowhere to put it.
    public var movedTo: String?
    /// False when the only free slot was in the following week.
    public var sameWeek: Bool
    public var outcome: RestOutcome
}

/// What is actually scheduled on a date, overrides included. nil = rest.
public typealias ResolveDay = @Sendable (String) -> ScheduleDay?

/// A committed session, as the scheduler needs to see it.
public struct LoggedDay: Codable, Equatable, Sendable {
    public var date: String
    public var dayKey: String?
    public init(date: String, dayKey: String?) { self.date = date; self.dayKey = dayKey }
}

/// Why a move was refused.
public struct SwapBlock: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case targetLogged = "target-logged", sourceLogged = "source-logged" }
    public var kind: Kind
    public var date: String
    /// What was logged there — nil when the session carried no key.
    public var dayKey: String?
}

public struct PermanentMovePlan: Equatable, Sendable {
    /// The layout to store, or nil when the move was refused.
    public var layout: DayLayout?
    /// Per-date overrides that PIN already-happened days to what they were.
    public var writes: [ScheduleWrite]
    /// Those dates, so the UI can say which part of this week is unaffected.
    public var pinned: [String]
    public var block: SwapBlock?
}

public enum Swap {

    /// How far ahead a displaced workout may be re-homed: the rest of this week
    /// plus all of the next. Beyond that it is no longer the same training week.
    public static let horizonDays = 13

    /// Sunday-anchored date for a program weekday in the week containing
    /// `dateISO`. Deliberately Sunday-anchored regardless of the display
    /// week-start preference: `ProgramDay.weekday` is 0 = Sun by definition.
    /// Any integer weekday is honoured (7 is next Sunday, -1 last Saturday),
    /// exactly as `setUTCDate` overflows. Echoes an unparseable date, where the
    /// web throws.
    public static func dateForWeekday(_ dateISO: String, _ weekday: Int) -> String {
        guard let n = ISODate.dayNumber(dateISO) else { return dateISO }
        return ISODate.iso(dayNumber: n - ISODate.weekday(dayNumber: n) + weekday)
    }

    /// The seven Sunday-anchored dates of the week containing `dateISO`.
    public static func weekDatesOf(_ dateISO: String) -> [String] {
        (0..<7).map { dateForWeekday(dateISO, $0) }
    }

    private static func sundayOf(_ dateISO: String) -> String { dateForWeekday(dateISO, 0) }

    /// Take a rest day on `dateISO`, moving whatever was scheduled there onto
    /// the next date the plan already rests. The search runs FORWARD only — a
    /// "next available" slot that lands on Monday when it is Thursday would
    /// quietly rewrite a week that has already been reported on.
    public static func planRestDay(_ dateISO: String, resolve: ResolveDay, horizon: Int = horizonDays) -> RestDayPlan {
        guard let current = resolve(dateISO) else {
            return RestDayPlan(writes: [], moved: nil, movedTo: nil, sameWeek: true, outcome: .alreadyRest)
        }
        let rest = ScheduleWrite(date: dateISO, dayKey: Schedule.restOverride)

        // A bare label with no program key: nothing to place, the day just rests.
        guard let dayKey = current.dayKey, !dayKey.isEmpty else {
            return RestDayPlan(writes: [rest], moved: current, movedTo: nil, sameWeek: true, outcome: .unscheduled)
        }

        for i in stride(from: 1, through: horizon, by: 1) {
            guard let target = ISODate.addDays(dateISO, i) else { break }
            if resolve(target) != nil { continue }
            return RestDayPlan(
                writes: [rest, ScheduleWrite(date: target, dayKey: dayKey)],
                moved: current, movedTo: target,
                sameWeek: sundayOf(target) == sundayOf(dateISO),
                outcome: .swapped
            )
        }
        return RestDayPlan(writes: [rest], moved: current, movedTo: nil, sameWeek: true, outcome: .noSlot)
    }

    /// Place `dayKey` onto `dateISO` as a genuine EXCHANGE: the displaced day
    /// takes the vacated slot, so the week keeps the same set of sessions in a
    /// different order. `naturalDate` is the incoming day's own weekday slot,
    /// used only when the day isn't currently placed anywhere in this week (so
    /// a day already moved once is not duplicated onto two dates).
    public static func planDaySwap(_ dateISO: String, dayKey: String, resolve: ResolveDay, naturalDate: String?) -> [ScheduleWrite] {
        let incoming = ScheduleWrite(date: dateISO, dayKey: dayKey)
        // `findInWeek(...) ?? naturalDate`, then `!source` — an empty string is
        // falsy in the web and is treated the same here.
        let source = findInWeek(dateISO, dayKey, resolve) ?? naturalDate
        guard let source, !source.isEmpty, source != dateISO else { return [incoming] }
        return [incoming, ScheduleWrite(date: source, dayKey: keyOrRest(resolve(dateISO)))]
    }

    /// Where `dayKey` currently sits in this week, if anywhere.
    private static func findInWeek(_ dateISO: String, _ dayKey: String, _ resolve: ResolveDay) -> String? {
        weekDatesOf(dateISO).first { $0 != dateISO && resolve($0)?.dayKey == dayKey }
    }

    /// `displaced === 'rest' ? REST : (displaced.dayKey ?? REST)`.
    private static func keyOrRest(_ day: ScheduleDay?) -> String {
        day?.dayKey ?? Schedule.restOverride
    }

    // MARK: What a LOGGED session does to a swap

    /// Can `dayKey` be placed on `dateISO`?
    ///
    /// A session is attributed by its own `day_key`, never by the weekday it
    /// landed on. The plan says what is PLANNED. They contradict each other in
    /// exactly one situation: a date holds a committed session AND the plan is
    /// changed to say a different day belongs there.
    ///
    ///   · TARGET already logged — refused, unless the incoming key IS what was
    ///     logged (a no-op).
    ///   · SOURCE already logged — the session stays put (it keeps its own key)
    ///     and a fresh slot opens elsewhere, so the week counts it twice. A
    ///     completed day cannot be moved.
    public static func blockForPlacement(_ dateISO: String, dayKey: String, logged: [LoggedDay], sourceDate: String?) -> SwapBlock? {
        if let onTarget = logged.first(where: { $0.date == dateISO }), onTarget.dayKey != dayKey {
            return SwapBlock(kind: .targetLogged, date: dateISO, dayKey: onTarget.dayKey)
        }
        if let sourceDate, !sourceDate.isEmpty, sourceDate != dateISO,
           let onSource = logged.first(where: { $0.date == sourceDate }) {
            return SwapBlock(kind: .sourceLogged, date: sourceDate, dayKey: onSource.dayKey)
        }
        return nil
    }

    /// One sentence naming what stands in the way.
    public static func describeBlock(_ block: SwapBlock, labelFor: (String?) -> String) -> String {
        let what = labelFor(block.dayKey)
        switch block.kind {
        case .targetLogged: return "\(shortDayLabel(block.date)) already has \(what) logged."
        case .sourceLogged: return "\(what) is already logged on \(shortDayLabel(block.date)) — it can't move."
        }
    }

    // MARK: The PERMANENT tier

    /// Move a day permanently, and protect the part of this week that already
    /// happened.
    ///
    /// A permanent layout change needs NO writes to take effect — every date
    /// without a per-date override picks it up, forever. The writes exist to
    /// stop it applying where it must not: the layout is read for EVERY date,
    /// so it would also rewrite the earlier days of the current week. Every day
    /// of this week that is SPENT (simply before today) and whose meaning the
    /// change would alter is pinned to what it was. A logged today needs no
    /// extra clause: an exchange changes exactly two weekdays, and
    /// `blockForPlacement` has already refused both when today carries a session.
    public static func planPermanentMove(
        program: Program, layout: DayLayout, dayKey: String, weekday: Int, todayISO: String,
        logged: [LoggedDay], resolveWith: @Sendable (String, DayLayout) -> ScheduleDay?
    ) -> PermanentMovePlan {
        let nextLayout = ScheduleLayout.moveDay(program, layout, dayKey, weekday)
        let week = weekDatesOf(todayISO)
        let targetDate = dateForWeekday(todayISO, weekday)
        let sourceDate = week.first { resolveWith($0, layout)?.dayKey == dayKey }

        if let block = blockForPlacement(targetDate, dayKey: dayKey, logged: logged, sourceDate: sourceDate) {
            return PermanentMovePlan(layout: nil, writes: [], pinned: [], block: block)
        }

        var writes: [ScheduleWrite] = []
        for d in week where d < todayISO {
            let before = keyOrRest(resolveWith(d, layout))
            let after = keyOrRest(resolveWith(d, nextLayout))
            if before != after { writes.append(ScheduleWrite(date: d, dayKey: before)) }
        }
        return PermanentMovePlan(layout: nextLayout, writes: writes, pinned: writes.map(\.date), block: nil)
    }

    // MARK: Labels

    private static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    /// en-GB abbreviated months, CLDR ≥ 38: September is "Sept", not "Sep".
    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sept", "Oct", "Nov", "Dec"]

    /// "Wed 6 Aug" — `toLocaleDateString('en-GB', { weekday: 'short',
    /// day: 'numeric', month: 'short', timeZone: 'UTC' })`, spelled out rather
    /// than asked of a `DateFormatter`, so it cannot drift with the device
    /// locale. Echoes an unparseable date, where the web prints "Invalid Date".
    public static func shortDayLabel(_ dateISO: String) -> String {
        guard let n = ISODate.dayNumber(dateISO) else { return dateISO }
        let parts = dateISO.split(separator: "-")
        let month = Int(parts[1])!, day = Int(parts[2])!
        return "\(weekdayNames[ISODate.weekday(dayNumber: n)]) \(day) \(monthNames[month - 1])"
    }

    /// One sentence describing what a rest-day plan did, for the UI to echo back.
    public static func describeRestPlan(_ plan: RestDayPlan) -> String {
        let name = plan.moved?.label ?? "The session"
        switch plan.outcome {
        case .alreadyRest:
            return "Already a rest day."
        case .swapped:
            return "\(name) moved to \(shortDayLabel(plan.movedTo ?? ""))\(plan.sameWeek ? "" : " — next week")."
        case .noSlot:
            return "Rest day set. No free rest slot in the next \(horizonDays) days, so \(name) was dropped."
        case .unscheduled:
            return "Rest day set."
        }
    }
}

// MARK: - The WEEK tier (W6)

/// One week's assignment, as the sheet holds it while it is being edited.
///
/// ── WHY A DRAFT AND NOT A SEQUENCE OF SWAPS ─────────────────────────────────
/// `planDaySwap` is an EXCHANGE, and an exchange is the right shape for a
/// single tap on a single day: you say "put Legs A here" and the thing that was
/// here goes to where Legs A was. It is the wrong shape for a screen showing
/// all seven days at once, because every tap would silently rewrite a second
/// row the user is looking at. They move Wednesday and Friday changes under
/// their finger, and the two edits they have made so far stop describing the
/// week they can see.
///
/// So the week sheet edits an ASSIGNMENT — seven dates, each holding a day key
/// or rest — and the writes are derived once, at the end, by diffing the draft
/// against the plan. Everything the user does is visible in the seven rows in
/// front of them, which is the entire reason this tier exists rather than
/// looping the day tier seven times.
public struct WeekAssignment: Equatable, Sendable {
    /// Sunday-anchored, seven entries. `Schedule.restOverride` for a rest day.
    public private(set) var days: [String: String]
    /// The dates, in week order — the sheet's row order, and stable.
    public let dates: [String]

    public init(dates: [String], days: [String: String]) {
        self.dates = dates
        self.days = days
    }

    public func key(on date: String) -> String { days[date] ?? Schedule.restOverride }

    /// Where `dayKey` sits in this week, if anywhere.
    public func date(of dayKey: String) -> String? {
        guard dayKey != Schedule.restOverride else { return nil }
        return dates.first { days[$0] == dayKey }
    }

    /// Put `dayKey` on `date`, and take it off wherever else it was.
    ///
    /// ── THE VACATED DAY RESTS; IT DOES NOT INHERIT ──────────────────────────
    /// The day tier's exchange hands the displaced session to the vacated slot,
    /// because there it is the only way the week keeps its session count. Here
    /// the user can see the vacated slot and assign it themselves in the next
    /// tap, so filling it for them would be the screen arguing with the person
    /// reading it. It goes to rest, visibly, and the footer says the week is
    /// one session short until they place it.
    ///
    /// Placing rest simply clears the date. A day key may live on exactly one
    /// date, which is what makes "two Legs A this week" unrepresentable rather
    /// than merely refused.
    /// Record what a date HELD, without moving anything.
    ///
    /// ── WHY THIS IS NOT `place` ─────────────────────────────────────────────
    /// `place` enforces one date per day key, which is the right rule for a
    /// DRAFT: a week cannot plan two Legs A. It is the wrong rule for the
    /// RECORD, because history is perfectly capable of holding two — a split
    /// trained twice in a week, a swap that doubled one up, or simply a store
    /// where several sessions carry the same key.
    ///
    /// Overlaying logged sessions through `place` made each one evict the last:
    /// with Sunday and Wednesday both logged as Chest & Back, whichever the
    /// dictionary happened to iterate second won and the other row drew "Rest"
    /// beside a completed-session seal. The sheet was reporting a session that
    /// happened as a day that did not.
    public mutating func set(_ dayKey: String, on date: String) {
        guard dates.contains(date) else { return }
        days[date] = dayKey
    }

    public mutating func place(_ dayKey: String, on date: String) {
        guard dates.contains(date) else { return }
        if dayKey == Schedule.restOverride {
            days[date] = Schedule.restOverride
            return
        }
        if let previous = self.date(of: dayKey), previous != date {
            days[previous] = Schedule.restOverride
        }
        days[date] = dayKey
    }
}

/// What confirming a week's edit will do.
public struct WeekPlan: Equatable, Sendable {
    /// Dates whose override must be written.
    public var writes: [ScheduleWrite]
    /// Dates whose override must be DELETED — they are back on the plan.
    public var clears: [String]
    /// Day keys the plan schedules this week that the draft has nowhere. The
    /// week is short by this many sessions, and the sheet says so rather than
    /// letting a holiday quietly delete a leg day.
    public var dropped: [String]
    /// The first refusal, or nil. A placement onto or off a logged session.
    public var block: SwapBlock?

    public var isEmpty: Bool { writes.isEmpty && clears.isEmpty }
}

public extension Swap {

    /// The plan's own answer for this week — the draft's starting point.
    static func weekAssignment(of dateISO: String, resolve: ResolveDay) -> WeekAssignment {
        let dates = weekDatesOf(dateISO)
        var days: [String: String] = [:]
        for date in dates { days[date] = keyOrRest(resolve(date)) }
        return WeekAssignment(dates: dates, days: days)
    }

    /// Diff a draft against the plan and say what it costs.
    ///
    /// ── WHY IT DIFFS AGAINST THE PLAN AND NOT AGAINST THE CURRENT STATE ─────
    /// `base` is the week with NO overrides — the layout's own weekday answer.
    /// A date whose draft equals the plan is CLEARED rather than written, which
    /// is what makes dragging a day back where it started actually undo the
    /// override instead of pinning the plan's own value on top of itself.
    ///
    /// That distinction is invisible for one week and load-bearing after it: a
    /// pinned row survives a later permanent layout change and quietly holds
    /// one date on the old plan, which is the bug `planPermanentMove` writes
    /// pins to CAUSE deliberately and this tier must not cause by accident.
    ///
    /// ── AND WHY A LOGGED DAY BLOCKS THE WHOLE CONFIRM ───────────────────────
    /// Not just its own row. The rule from `blockForPlacement` is that a
    /// session is attributed by its own `day_key` and the plan says what was
    /// PLANNED, so a date holding a committed session cannot be told it held
    /// something else. Applying the other six rows and skipping that one would
    /// leave the week in a shape the user did not ask for and did not see.
    /// - Parameters:
    ///   - base: the week with NO overrides — the layout's own weekday answer.
    ///   - current: the week as it stands now, overrides included. What the
    ///     sheet opened on, and the only way to tell "this date is already
    ///     correct" from "this date must be changed back".
    ///   - draft: what the user has built.
    ///   - scheduled: the day keys the plan asks for this week, for `dropped`.
    static func planWeek(
        base: WeekAssignment,
        current: WeekAssignment,
        draft: WeekAssignment,
        logged: [LoggedDay],
        scheduled: [String]
    ) -> WeekPlan {
        var writes: [ScheduleWrite] = []
        var clears: [String] = []

        for date in draft.dates {
            let want = draft.key(on: date)
            // Nothing to do: this date already holds what the user asked for,
            // by override or by plan. A write here would restamp an identical
            // row, and on a date with no override it would PIN the plan's own
            // value — invisible for a week, and load-bearing after it, because
            // a pin survives a later permanent layout change and quietly holds
            // one date on the old plan.
            if want == current.key(on: date) { continue }

            // ── EMPTYING A LOGGED DATE IS A `sourceLogged` REFUSAL ──────────
            // The generic rule below would catch this too, and would name the
            // wrong obstacle: scanning dates in week order reaches the date
            // being emptied before the one being filled, so moving Monday's
            // logged push to Wednesday reported "Monday already has Push A
            // logged" — true, and a description of a placement the user never
            // attempted. What they did was take a finished session off the day
            // it was performed on, and that is the sentence they need.
            //
            // Only when the date is left EMPTY. A date that is simultaneously
            // being vacated and filled — legs dropped onto a logged Monday — is
            // both refusals at once, and there the target framing is the direct
            // answer to the thing the user just did.
            if want == Schedule.restOverride, let leaving = current.days[date], leaving != want,
               let session = logged.first(where: { $0.date == date }), session.dayKey == leaving {
                return WeekPlan(
                    writes: [], clears: [], dropped: [],
                    block: SwapBlock(kind: .sourceLogged, date: date, dayKey: session.dayKey)
                )
            }

            // ── THE PLACEMENT RULE GATES BOTH OUTCOMES ──────────────────────
            // This check used to sit BELOW the clears branch, and that branch
            // returned early — so deleting an override was the one way to
            // change a date's meaning without asking whether a session was on
            // it. Monday overridden to Legs A, Legs A logged there, Monday put
            // back to the plan: the row vanished and the schedule claimed Push
            // A on a date that had run Legs A. That is the exact state
            // `blockForPlacement`'s own header calls unrepresentable.
            //
            // A clear is a change of meaning like any other, so it is asked the
            // same question. The no-op case stays allowed for free, because the
            // rule already returns nil when the incoming key IS what was logged.
            if let block = blockForPlacement(date, dayKey: want, logged: logged, sourceDate: current.date(of: want)) {
                return WeekPlan(writes: [], clears: [], dropped: [], block: block)
            }

            if want == base.key(on: date) {
                // Back on the plan, and something is currently in the way. The
                // override has to GO, not be rewritten to the plan's value.
                clears.append(date)
                continue
            }
            writes.append(ScheduleWrite(date: date, dayKey: want))
        }

        let placed = Set(draft.dates.compactMap { draft.days[$0] })
        let dropped = scheduled.filter { !placed.contains($0) }
        return WeekPlan(writes: writes, clears: clears, dropped: dropped, block: nil)
    }
}
