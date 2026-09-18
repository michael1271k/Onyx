import Foundation
import OnyxCore
import OnyxData

/// The app's reading of `OnyxCore.WeekWindow` (§6.4): the setting it is cut
/// on, and the labels the History and Workout screens draw from it. The value
/// itself — the seven dates, the number, `isCurrent` — lives in OnyxCore
/// beside `Week`, so the export and the screens cannot disagree about which
/// Saturday a week ended on.
extension WeekWindow {

    init(containing dateISO: String, startDay: Int) {
        self.init(containing: dateISO, startDay: startDay, today: LogicalDay.today())
    }

    /// The setting, read from the goals row the whole app already observes.
    ///
    /// `user_goals.week_end_day` is the column — the END day — and
    /// `Week.startDay(fromEndDay:)` is the one conversion. Settings writes it,
    /// the Workout tab's This-week panel reads it, the weekly export reads it,
    /// and so does History.
    static func startDay(from goals: UserGoalRow?) -> Int {
        Week.startDay(fromEndDay: goals?.weekEndDay)
    }

    init(containing dateISO: String, goals: UserGoalRow?) {
        self.init(containing: dateISO, startDay: Self.startDay(from: goals))
    }

    /// `Week 7`, or the phase's own label for a week before Week 0. The
    /// anchor is the window's own (`weekZero`); the phases are the caller's.
    func label(phases: [PhaseDef]) -> String { Week.label(ofWeekStart: start, anchor: weekZero, phases: phases) }

    /// The same, off the live catalogue a view holds (`environment.targets`):
    /// the active plan's week-0 anchor and its phase table. With none, the
    /// window's own anchor and no phases.
    func label(in schedule: ScheduleContext?) -> String {
        Week.label(ofWeekStart: start, anchor: schedule?.weekZeroStart ?? weekZero, phases: schedule?.phases ?? [])
    }

    /// The phase this week sits in, and with it the era (Onyx or PPL).
    func phase(in phases: [PhaseDef]) -> WeekPhase? { Phases.weekPhase(weekStart: start, in: phases) }

    /// The window `count` weeks after this one — negative walks back.
    func offset(byWeeks count: Int) -> WeekWindow? { shifted(by: count, today: LogicalDay.today()) }

    /// `M` — the one-letter column head over a day cell. Locale's own narrow
    /// symbol, so a locale whose week runs Saturday-first still gets its own
    /// letters rather than an English initial.
    static func initial(_ dateISO: String) -> String {
        guard let date = LogicalDay.date(fromISO: dateISO) else { return "·" }
        return String(date.formatted(.dateTime.weekday(.narrow)).prefix(1))
    }
}
