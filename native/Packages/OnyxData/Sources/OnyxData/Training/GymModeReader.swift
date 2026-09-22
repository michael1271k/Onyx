import Foundation
import GRDB
import OnyxCore

/// The store's half of gym mode (§W6-B): when does this person train, and is
/// today one of those days?
public extension AppDatabase {

    /// The minute of local midnight each past session STARTED at.
    ///
    /// `started_at` is when the deck was opened (memory: export v5), which is
    /// the closest thing the store has to "when you walked in" — `ended_at`
    /// carries the session's length in it and would push the learned window
    /// an hour late for everyone who trains long.
    ///
    /// Bounded at 180 sessions: a habit that moved two years ago is not this
    /// person's habit, and an unbounded scan grows with the account forever to
    /// answer a question 180 points already answer.
    func trainingStartMinutes(
        userId: String, limit: Int = 180, calendar: Calendar = .current
    ) throws -> [Int] {
        try writer.read { db in
            try WorkoutSession
                .filter(Column("user_id") == userId && Column("started_at") != nil)
                .order(Column("date").desc)
                .limit(limit)
                .fetchAll(db)
                .compactMap { $0.startedAt.map { GymMode.minuteOfDay($0, calendar: calendar) } }
        }
    }

    /// Everything gym mode needs, in ONE read.
    ///
    /// One call and not three, because this runs on the launch path and every
    /// separate `writer.read` there is a transaction the first frame waits on.
    /// The caller is expected to be off the main actor — `RootView` reaches it
    /// through a detached task.
    func gymModeInputs(userId: String, today: String, calendar: Calendar = .current) throws -> GymModeInputs {
        let minutes = try trainingStartMinutes(userId: userId, calendar: calendar)
        let schedule = try? scheduleContext(userId: userId)
        return GymModeInputs(
            liveWorkout: (try? liveWorkoutInProgress(date: today, userId: userId)) ?? false,
            sessionDueToday: schedule.map { Schedule.isTrainingDayIn($0, today) } ?? false,
            window: GymMode.window(startMinutes: minutes)
        )
    }
}

public struct GymModeInputs: Sendable, Equatable {
    public var liveWorkout: Bool
    public var sessionDueToday: Bool
    public var window: ClosedRange<Int>?

    public init(liveWorkout: Bool, sessionDueToday: Bool, window: ClosedRange<Int>?) {
        self.liveWorkout = liveWorkout
        self.sessionDueToday = sessionDueToday
        self.window = window
    }

    public func isDue(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        GymMode.isDue(
            liveWorkout: liveWorkout,
            sessionDueToday: sessionDueToday,
            minuteOfDay: GymMode.minuteOfDay(now, calendar: calendar),
            window: window
        )
    }
}
