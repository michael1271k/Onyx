import Foundation
import GRDB
import OnyxCore

/// What a day is graded against, resolved the way the widget resolves it: the
/// plan the athlete is ACTUALLY running (stored layout and overrides, never a
/// default) and the lever in force on that date.
struct DayPlan {
    var isTraining: Bool
    var dayKey: String?
    var planned: (exercises: Int, sets: Int)?
    var goals: ResolvedGoals
    var isMaintenance: Bool

    static func resolve(
        goals: UserGoalRow?, schedule: ScheduleContext, profiles: [TargetProfileRow], periods: [LeverPeriodRow],
        dayTarget: DailyTargetRow?, date: String, todayISO: String
    ) -> DayPlan {
        let program = Schedule.programForContext(schedule, date).program
        let day = Schedule.scheduleDayIn(schedule, date)
        let planned: (exercises: Int, sets: Int)? = day?.dayKey.flatMap { key in
            program.day(key: key).map { ($0.exercises(for: schedule.phase).count, max(1, $0.plannedSets(for: schedule.phase))) }
        }

        // One chain for the scorer, the widget and the tabs (§6.2).
        let snapshot = TargetSnapshot(
            goals: goals, dailyTargets: dayTarget.map { [$0.date: $0] } ?? [:], profiles: profiles,
            overrides: schedule.overrides, periods: periods, schedule: schedule
        )
        let resolved = snapshot.targets(for: date, today: todayISO)
        return DayPlan(
            isTraining: Schedule.isTrainingDayIn(schedule, date),
            dayKey: day?.dayKey,
            planned: planned,
            goals: ResolvedGoals(
                calorie: resolved.kcal, protein: resolved.protein ?? 0, carbs: resolved.carbs ?? 0,
                fat: resolved.fat ?? 0, steps: resolved.steps ?? Double(goals?.stepsGoal ?? 0)
            ),
            isMaintenance: Maintenance.isMaintenanceDate(date, today: todayISO, ladder: snapshot.ladder, phases: schedule.phases)
        )
    }

    var supplements: ScoringSupplements {
        ScoringSupplements(
            goals: goals,
            isMaintenance: isMaintenance,
            plannedExercises: planned.map { Double($0.exercises) },
            plannedSets: planned.map { Double($0.sets) }
        )
    }
}

public extension AppDatabase {

    /// Compute one day from the local store and write it — the production
    /// caller `writeDailyScore` waited for since Wave 2.
    ///
    /// A FINISHED DAY IS SCORED AS A FINISHED DAY: `hoursAwake` describes how
    /// far through the day the caller is, which only means anything today. A
    /// past date is pinned to a full waking day, so a recompute is idempotent
    /// with respect to the wall clock — the route learned that the hard way
    /// when the evening's numbers differed from the morning's for days that
    /// ended weeks ago.
    ///
    /// `nil` when the freeze refuses the day or there is nothing to score.
    @discardableResult
    func refreshDailyScore(
        userId: String, date: String, now: Date = Date(), calendar: Calendar = .current, force: Bool = false
    ) throws -> DailyScoreRow? {
        try rescoreWindow(userId: userId, dates: [date], now: now, calendar: calendar, force: force)[date]
    }
}
