import Foundation

/// One week as the athlete's settings cut it — the seven days, their number,
/// and whether today is inside them. A port of `weekWindowOf` in
/// the web app's `lib/reports/weekNumber.ts`.
///
/// ── WHY A VALUE AND NOT A DATE SUM AT EVERY CALL SITE ───────────────────────
/// "This week" was computed by hand in six places (`Week.start` + six
/// `addDays`), and every one of them had to remember the start day from
/// `Preferences.weekStartDay`. A reader that forgot fell back to Sunday and
/// disagreed with the export. Every "this week" read takes one of these
/// instead; `AppEnvironment` re-cuts it at midnight and when "Week starts on"
/// changes, and nothing is written for either.
///
/// An unparseable date echoes as both bounds with no days, the way
/// `Week.start` echoes its input — a bad string draws an empty week, not a
/// crash.
public struct WeekWindow: Codable, Hashable, Identifiable, Sendable {
    /// First day, inclusive.
    public let start: String
    /// Last day, inclusive — `start + 6`.
    public let end: String
    /// Programme week number via `Week.number` — Week 0 is the week the active
    /// plan started in (`weekZero`); 0 when the caller has no anchor.
    public let number: Double
    /// Is `today` one of `days`?
    public let isCurrent: Bool
    /// The seven dates, in order. Empty when the date does not parse.
    public let days: [String]
    /// The anchor `number` was counted from, carried so `shifted(by:)` keeps it.
    public let weekZero: String?

    public var id: String { start }
    /// The cut this window was made on, 0 = Sunday — read back off `start`.
    public var startDay: Int { ISODate.weekday(start) ?? 0 }

    /// Inclusive on both ends: a Saturday session belongs to THIS capsule.
    public func contains(_ dateISO: String) -> Bool { dateISO >= start && dateISO <= end }

    public init(containing dateISO: String, startDay: Int, today: String, weekZero: String? = nil) {
        let start = Week.start(of: dateISO, startDay: startDay)
        let days = (0..<7).compactMap { ISODate.addDays(start, $0) }
        self.start = start
        self.end = days.last ?? start
        self.number = Week.number(ofWeekStart: start, anchor: weekZero)
        self.isCurrent = days.contains(today)
        self.days = days
        self.weekZero = weekZero
    }

    /// The week `days` before or after this one. Nil when this window has no
    /// days to step from.
    public func shifted(by weeks: Int, today: String) -> WeekWindow? {
        guard let date = ISODate.addDays(start, weeks * 7), !days.isEmpty else { return nil }
        return WeekWindow(containing: date, startDay: startDay, today: today, weekZero: weekZero)
    }
}
