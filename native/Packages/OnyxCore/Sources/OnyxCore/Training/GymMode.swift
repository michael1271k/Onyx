import Foundation

/// When the app should open straight into the logger (§W6-B, decision 26).
///
/// ── WHAT IT LEARNS, AND WHAT IT REFUSES TO GUESS ────────────────────────────
/// Two things put the app in gym mode: a workout that is already running, and
/// a session due today at an hour this person usually trains. The second is
/// learned from `workout_sessions.started_at` — the MEDIAN minute of day, ±90
/// minutes — and not from a setting, because "when do you train" is a question
/// the store has already answered several dozen times.
///
/// The median and not the mean: one 23:40 session after a flight drags a mean
/// by half an hour and leaves the median where the other forty sessions are.
///
/// Fewer than `minimumSessions` starts is NOT a window. A person with three
/// logged workouts has no habit yet, and a window fitted to three points would
/// throw the app into the logger on a Sunday morning because that is when they
/// happened to try it. No window means gym mode waits for a live session,
/// which is the behaviour the app had before this existed.
public enum GymMode {

    /// How far either side of the median counts as "about now".
    public static let halfWidthMinutes = 90
    /// Below this many starts there is no habit to read.
    public static let minimumSessions = 8

    /// The learned window, as minutes from local midnight, or `nil`.
    ///
    /// The bounds may fall outside `0..<1440` — a median at 23:00 gives
    /// `1290...1470` — and `contains` is what resolves that, not this.
    public static func window(startMinutes: [Int]) -> ClosedRange<Int>? {
        let minutes = startMinutes.filter { (0..<1440).contains($0) }.sorted()
        guard minutes.count >= minimumSessions else { return nil }
        let median: Int = {
            let middle = minutes.count / 2
            // An even count takes the LOWER of the two middles rather than
            // their mean: the mean of 07:00 and 19:00 is 13:00, an hour this
            // person has never trained at, and a window centred there covers
            // neither habit.
            return minutes.count.isMultiple(of: 2) ? minutes[middle - 1] : minutes[middle]
        }()
        return (median - halfWidthMinutes)...(median + halfWidthMinutes)
    }

    /// Is `minuteOfDay` inside the window, allowing for a window that crosses
    /// midnight at either end?
    public static func contains(_ minuteOfDay: Int, window: ClosedRange<Int>) -> Bool {
        // A window is at most 181 minutes wide, so exactly one wrapped copy on
        // each side can overlap the day; testing all three is cheaper than
        // reasoning about which.
        window.contains(minuteOfDay)
            || window.contains(minuteOfDay + 1440)
            || window.contains(minuteOfDay - 1440)
    }

    /// The whole decision.
    ///
    /// `liveWorkout` wins outright and ignores both the window and the due
    /// session: a workout in progress is the strongest possible statement that
    /// the phone is in a gym, whatever the clock says.
    public static func isDue(
        liveWorkout: Bool,
        sessionDueToday: Bool,
        minuteOfDay: Int,
        window: ClosedRange<Int>?
    ) -> Bool {
        if liveWorkout { return true }
        guard sessionDueToday, let window else { return false }
        return contains(minuteOfDay, window: window)
    }

    /// Minutes from local midnight.
    public static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
