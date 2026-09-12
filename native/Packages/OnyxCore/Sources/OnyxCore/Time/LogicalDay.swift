import Foundation

/// The logical day, and the ISO strings every table in this app is keyed by.
///
/// ── THE BOUNDARY IS MIDNIGHT, DEVICE-LOCAL ──────────────────────────────────
/// A port of the web app's `lib/utils/day.ts`, including its history: there used to be a
/// configurable end-of-day cutoff, and it caused native-versus-web drift — the
/// native side leaked the previous day — so it was removed. Apple Health resets
/// at 00:00, which settles the argument. `user_goals.day_cutoff_hour` still
/// exists in Postgres and is no longer read by anything; do not reintroduce it
/// here without changing both apps at once.
///
/// The timezone is always the DEVICE's, never a hardcoded zone and never the
/// server's. `/api/today` takes the date as a parameter for exactly this reason.
public enum LogicalDay {

    /// `yyyy-MM-dd` for a moment, in a calendar's timezone.
    ///
    /// Built from `DateComponents` rather than a `DateFormatter`. A formatter is
    /// a reference type with mutable state, so a shared one is not `Sendable`
    /// and a per-call one is a surprisingly expensive object to allocate inside
    /// a list row. This is neither.
    public static func iso(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }

    /// Today's logical date.
    public static func today(calendar: Calendar = .current) -> String {
        iso(Date(), calendar: calendar)
    }

    /// The logical date `n` days before `date`.
    ///
    /// Calendar arithmetic, not `date - n * 86400`. A day is not always 86,400
    /// seconds — Israel, where this app is used, moves its clocks twice a year —
    /// and the seconds version silently returns the wrong day on those two dates.
    public static func daysAgo(
        _ n: Int, from date: Date = Date(), calendar: Calendar = .current
    ) -> String {
        let shifted = calendar.date(byAdding: .day, value: -n, to: date) ?? date
        return iso(shifted, calendar: calendar)
    }

    /// Parse a `yyyy-MM-dd` back into a `Date` at local noon.
    ///
    /// NOON, not midnight. A date rendered at midnight and then formatted in any
    /// timezone west of the calendar's shows the previous day, which is the
    /// oldest bug in date handling. Nothing here needs the time of day; the
    /// twelve-hour offset costs nothing and removes the whole class.
    public static func date(fromISO iso: String, calendar: Calendar = .current) -> Date? {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: 12
        ))
    }
}
