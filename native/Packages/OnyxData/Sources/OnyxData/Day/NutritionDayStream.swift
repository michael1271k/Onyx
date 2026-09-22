import Foundation
import GRDB
import OnyxCore

/// Everything the Nutrition tab reads for one day, in one value.
///
/// ── WHY ONE OBSERVATION AND NOT SEVEN ───────────────────────────────────────
/// The tab used to open seven `ValueObservation`s per date — the flat row, the
/// entries, the water ledger, the day target, the week strip, the stack and the
/// dose log — and then re-read the supplement credit SYNCHRONOUSLY on the main
/// actor from two of their callbacks. Seven observations is seven SQLite region
/// registrations, seven transactions on every relevant commit, and seven
/// separate main-actor deliveries for one write: logging a meal woke the
/// entries stream and the week stream, each hopping to the main actor with its
/// own `body` invalidation, and a supplement tick woke two streams that both
/// answered by running `stackCredit` inline.
///
/// One observation is one transaction and one delivery, which also makes the
/// day CONSISTENT: the strip and the card are now read from the same snapshot
/// of the database, where before they were two reads with a commit possible
/// between them. `TargetResolver.snapshotStream` is the pattern (§6.2).
public struct NutritionDaySnapshot: Sendable, Equatable {
    public var dailyLog: DailyLogRow?
    public var entries: [NutritionEntryRow]
    public var water: [WaterIntakeRow]
    public var dailyTarget: DailyTargetRow?
    public var week: [NutritionDay]
    public var stack: StackCredit

    public init(
        dailyLog: DailyLogRow? = nil, entries: [NutritionEntryRow] = [],
        water: [WaterIntakeRow] = [], dailyTarget: DailyTargetRow? = nil,
        week: [NutritionDay] = [], stack: StackCredit = .empty
    ) {
        self.dailyLog = dailyLog
        self.entries = entries
        self.water = water
        self.dailyTarget = dailyTarget
        self.week = week
        self.stack = stack
    }
}

public extension AppDatabase {

    /// The selected day and the six before it, as one observed value.
    ///
    /// `today` is passed rather than read here because the caller holds the
    /// logical day for the whole render (`NutritionModel.today`) — the stack's
    /// clock rule turns on whether the date IS today, and a model that
    /// resolved it twice could grade one card against a different day from the
    /// one beside it. The wall clock inside the credit is read per fetch, so a
    /// dose that comes due while the tab is open is credited by the next
    /// commit rather than being frozen at subscribe time.
    func nutritionDayStream(
        userId: String, date: String, today: String
    ) -> AsyncThrowingStream<NutritionDaySnapshot, any Error> {
        let weekStart = ISODate.addDays(date, -6) ?? date
        let user = Column("user_id") == userId
        let onDate = Column("date") == date
        return stream(ValueObservation.tracking { db in
            NutritionDaySnapshot(
                dailyLog: try DailyLogRow.filter(user && onDate).fetchOne(db),
                entries: try NutritionEntryRow.filter(user && onDate)
                    .order(Column("logged_at")).fetchAll(db),
                water: try WaterIntakeRow.filter(user && onDate)
                    .order(Column("logged_at")).fetchAll(db),
                dailyTarget: try DailyTargetRow.filter(user && onDate).fetchOne(db),
                week: try Self.nutritionWeek(db, userId: userId, from: weekStart, to: date),
                // Reads `custom_supplements`, `supplement_log` and the
                // schedule, so those three tables join this observation's
                // region — which is what the two extra streams were for.
                stack: try Self.stackCredit(db, userId: userId, date: date, today: today)
            )
        })
    }
}
