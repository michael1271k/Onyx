import Foundation
import GRDB
import OnyxCore

/// What the stack has delivered on one day, read in one pass.
///
/// ── WHY A READER AND NOT A SECOND SET OF STREAMS ────────────────────────────
/// Two screens need this number: Pulse (which owns the stack and already
/// observes the schedule, the customs and the log) and Nutrition (which owns
/// the micronutrient totals and observes none of them). Giving Nutrition its
/// own copy of the schedule plumbing would put a second resolution of "is today
/// a training day" in the app, and the day a swap moved a Wednesday the two
/// screens would credit different stacks for the same date.
///
/// So the resolution lives here, once, and both callers ask it. It is a single
/// `read` over five small tables; the Nutrition tab re-asks when the customs or
/// the log tick, which is the only thing that can change the answer within a
/// day besides the clock.
public struct StackCredit: Sendable, Equatable {
    /// Every scheduled dose of the day, with where it stands.
    public var doses: [SupplementDose]
    /// The micronutrients the CREDITED ones deliver.
    public var nutrients: [String: Double]
    /// What those same doses deliver to the day's MACRO ring — a powder has
    /// calories, and a fibre supplement has most of a meal's worth of
    /// carbohydrate. Resolved here, from the same doses, so the grid and the
    /// ring cannot disagree about one scoop.
    public var macros: SupplementNutrients.StackMacros
    /// Whether the plan calls the day a training day — a rest day drops the
    /// training-only items entirely.
    public var isTraining: Bool

    public init(
        doses: [SupplementDose],
        nutrients: [String: Double],
        macros: SupplementNutrients.StackMacros = .zero,
        isTraining: Bool
    ) {
        self.doses = doses
        self.nutrients = nutrients
        self.macros = macros
        self.isTraining = isTraining
    }

    public static let empty = StackCredit(doses: [], nutrients: [:], macros: .zero, isTraining: false)
}

public extension AppDatabase {

    /// The day's stack, resolved and credited.
    ///
    /// `now` decides which doses have come due; a date that is not `today` is
    /// read as a day that has already happened, which is what a past day is.
    func stackCredit(userId: String, date: String, today: String, now: Date = Date(), calendar: Calendar = .current) throws -> StackCredit {
        try writer.read { db in
            try Self.stackCredit(db, userId: userId, date: date, today: today, now: now, calendar: calendar)
        }
    }

    /// The same read, inside a transaction the caller already holds — which is
    /// what lets `nutritionDayStream` fold the stack into ONE observation
    /// instead of re-reading it from two stream callbacks.
    static func stackCredit(
        _ db: Database, userId: String, date: String, today: String,
        now: Date = Date(), calendar: Calendar = .current
    ) throws -> StackCredit {
        let user = Column("user_id") == userId
        let schedule = try AppDatabase.scheduleContext(db, userId: userId)
        let isTraining = Schedule.isTrainingDayIn(schedule, date)

        let customs = try CustomSupplementRow.filter(user).order(Column("time")).fetchAll(db).map(AppDatabase.custom)
        let active = Supplements.active(customs, on: date)
        let weekday = ISODate.weekday(date) ?? 0
        let slots = Supplements.stackForDate(
            Supplements.customSlotsForDate(active, weekday: weekday, isTraining: isTraining),
            isTraining: isTraining, weekday: weekday
        )

        let log = try SupplementLogRow
            .filter(user && Column("date") == date)
            .fetchAll(db)
            .map { DoseLogEntry(itemKey: $0.itemKey, taken: $0.taken) }

        let clock: DayClock = date == today
            ? .today(minutes: Self.minutesOfDay(now, calendar: calendar))
            : (date < today ? .past : .future)
        let doses = Supplements.doses(slots: slots, log: log, clock: clock)
        // One payload table, read twice: the grid's micronutrients and the
        // ring's macros come off the same rows with the same credit rule.
        let payloads = SupplementNutrients.payloads(active)
        return StackCredit(
            doses: doses,
            nutrients: SupplementNutrients.credit(doses, payloads: payloads),
            macros: SupplementNutrients.macros(doses, payloads: payloads),
            isTraining: isTraining
        )
    }

    private static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
