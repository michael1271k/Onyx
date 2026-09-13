import Foundation

// `isWeekComplete` (the web app's `lib/utils/week.ts`) and `isWeekReady`
// (the web app's `lib/training/weekReady.ts`) — the two halves of "the week is over".
// The calendar says the week is over; `ready` says the work in it is done.
public enum WeekReady {
    /// Strictly after the week's final day.
    public static func isComplete(weekStart: String, today: String) -> Bool {
        guard let end = ISODate.addDays(weekStart, 6) else { return false }
        return today > end
    }

    /// Every training day the plan asked for, up to `today`, is logged. A week
    /// with no training days due yet is never ready.
    public static func isReady(
        weekStart: String, logged: Set<String>, today: String, isTrainingDay: (String) -> Bool
    ) -> Bool {
        let due = (0..<7).compactMap { ISODate.addDays(weekStart, $0) }
            .filter { $0 <= today && isTrainingDay($0) }
        if due.isEmpty { return false }
        return due.allSatisfy { logged.contains($0) }
    }
}
