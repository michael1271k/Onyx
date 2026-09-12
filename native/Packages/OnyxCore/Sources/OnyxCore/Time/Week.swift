import Foundation

/// Week boundaries and the ONE programme week counter — ports of
/// `weekStartOf` (the web app's `lib/utils/week.ts`) and the web app's `lib/reports/weekNumber.ts`.
///
/// ── WEEK 0 IS THE PLAN'S, NOT THE PACKAGE'S (W2) ─────────────────────────────
/// `week0Start = "2026-07-12"` was the Sunday of the week the founder's cut
/// opened, compiled in. The anchor is `plans.started_on` now — the week
/// containing the active plan's first day — and every counter takes it as a
/// parameter (`ScheduleContext.weekZeroStart` derives it). With no anchor
/// there is no programme week, and the label falls back to the phase.
public enum Week {

    /// `weekStartDayFromEndDay` — `user_goals.week_end_day` → the start day
    /// `start(of:startDay:)` wants. A week ending Sunday starts Monday; nil is
    /// the Sunday-start default.
    public static func startDay(fromEndDay endDay: Int?) -> Int {
        guard let endDay else { return 0 }
        return endDay == 0 ? 1 : 0
    }

    /// The first day of the week containing `dateISO`, for a week starting on
    /// `startDay` (0 = Sunday, 1 = Monday). Echoes an unparseable date.
    public static func start(of dateISO: String, startDay: Int = 0) -> String {
        guard let day = ISODate.dayNumber(dateISO) else { return dateISO }
        // 1970-01-01 was a Thursday (4).
        let weekday = (((day % 7) + 7) % 7 + 4) % 7
        let offset = (weekday - startDay + 7) % 7
        return ISODate.iso(dayNumber: day - offset)
    }

    /// The week-0 anchor for a plan that started on `startedOn`: the Sunday
    /// (or the athlete's start day) of the week that day fell in. Week 0 is a
    /// real, PARTIAL week when a block opens mid-week — the founder's did, on
    /// a Wednesday.
    public static func anchor(planStartedOn startedOn: String?, startDay: Int = 0) -> String? {
        startedOn.map { start(of: $0, startDay: startDay) }
    }

    /// Programme week number for a week start — Week 0 = `anchor`, then +1 a
    /// week. 0 rather than NaN for an unparseable date, and 0 with no anchor.
    public static func number(ofWeekStart weekStartISO: String, anchor: String?) -> Double {
        guard let anchor, let a = ISODate.dayNumber(anchor), let b = ISODate.dayNumber(weekStartISO) else { return 0 }
        return jsRound(Double(b - a) / 7)
    }

    public static func number(forDate dateISO: String, startDay: Int = 0, anchor: String?) -> Double {
        number(ofWeekStart: start(of: dateISO, startDay: startDay), anchor: anchor)
    }

    /// "Week 3" for a week on or after the anchor; a week before it draws its
    /// label from the phase table, and a week neither knows is "Week −n".
    public static func label(ofWeekStart weekStartISO: String, anchor: String?, phases: [PhaseDef]) -> String {
        let n = number(ofWeekStart: weekStartISO, anchor: anchor)
        if anchor != nil, n >= 0 { return "Week \(jsIntegerString(n))" }
        return Phases.weekPhase(weekStart: weekStartISO, in: phases)?.label ?? "Week \(jsIntegerString(n))"
    }
}
