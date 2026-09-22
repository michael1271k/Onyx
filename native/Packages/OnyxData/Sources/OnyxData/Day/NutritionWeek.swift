import Foundation
import GRDB
import OnyxCore

/// One day of the Nutrition tab's seven-day strip.
///
/// `nil` figures are the loading-and-empty distinction the tab already makes for
/// today: a day with no `nutrition_entries` row has `kcal == nil`, which draws as
/// an untracked dot and no bars — never as a zero-calorie day.
public struct NutritionDay: Sendable, Equatable, Identifiable {
    public var id: String { date }
    public var date: String
    public var kcal: Double?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    /// `daily_logs.nutrition_exception`, verbatim. `ExceptionDay.reason` is what
    /// turns it into a word; the presence of one is what colours the dot.
    public var exception: String?
    public var estimated: Bool

    public init(
        date: String, kcal: Double? = nil, proteinG: Double? = nil, carbsG: Double? = nil,
        fatG: Double? = nil, exception: String? = nil, estimated: Bool = false
    ) {
        self.date = date
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.exception = exception
        self.estimated = estimated
    }

    public var isTracked: Bool { kcal != nil }
}

public extension AppDatabase {

    /// Every day in `from…to` inclusive, oldest first, with a row for days that
    /// have nothing — the strip is a fixed seven columns and a gap in the middle
    /// of it is a fact, not a missing element.
    ///
    /// ── WHY THE MACROS COME FROM `nutrition_entries` AND NOT `daily_logs` ────
    /// `daily_logs` carries `protein_g`/`carbs_g`/`fats_g` too, and it does NOT
    /// carry calories — so a strip built from it would have to invent kcal with
    /// Atwater while the card above it showed HealthKit's own figure. One source
    /// for both, and the strip can never disagree with the day it sits under.
    /// A malformed or reversed range yields NOTHING rather than a strip with
    /// one column in it — the same guard `sleepNightStream` puts on its own
    /// date, and for the same reason: a window nobody can parse is a caller
    /// bug, and answering it with a plausible-looking short answer hides it.
    func nutritionWeekStream(userId: String, from: String, to: String) -> AsyncThrowingStream<[NutritionDay], any Error> {
        guard from <= to, ISODate.addDays(from, 0) != nil, ISODate.addDays(to, 0) != nil else {
            return AsyncThrowingStream { $0.finish() }
        }
        return stream(ValueObservation.tracking { db in
            try Self.nutritionWeek(db, userId: userId, from: from, to: to)
        })
    }

    /// The same rows, inside a transaction the caller already holds.
    /// A malformed range answers `[]`, as the stream answers nothing.
    static func nutritionWeek(
        _ db: Database, userId: String, from: String, to: String
    ) throws -> [NutritionDay] {
        guard from <= to, ISODate.addDays(from, 0) != nil, ISODate.addDays(to, 0) != nil else {
            return []
        }
        var byDate: [String: NutritionDay] = [:]
        let totals = try Row.fetchAll(
            db,
            sql: """
            SELECT date,
                   SUM(calories) AS kcal,
                   SUM(protein_g) AS protein,
                   SUM(carbs_g) AS carbs,
                   SUM(fat_g) AS fat
              FROM nutrition_entries
             WHERE user_id = ? AND date >= ? AND date <= ?
             GROUP BY date
            """,
            arguments: [userId, from, to]
        )
        for row in totals {
            let date: String = row["date"]
            byDate[date] = NutritionDay(
                date: date, kcal: row["kcal"], proteinG: row["protein"],
                carbsG: row["carbs"], fatG: row["fat"]
            )
        }
        let flags = try Row.fetchAll(
            db,
            sql: """
            SELECT date, nutrition_exception, nutrition_estimated
              FROM daily_logs
             WHERE user_id = ? AND date >= ? AND date <= ?
            """,
            arguments: [userId, from, to]
        )
        for row in flags {
            let date: String = row["date"]
            var day = byDate[date] ?? NutritionDay(date: date)
            day.exception = row["nutrition_exception"]
            day.estimated = row["nutrition_estimated"] ?? false
            byDate[date] = day
        }
        var out: [NutritionDay] = []
        var cursor = from
        while cursor <= to {
            out.append(byDate[cursor] ?? NutritionDay(date: cursor))
            guard let next = ISODate.addDays(cursor, 1) else { break }
            cursor = next
        }
        return out
    }
}
