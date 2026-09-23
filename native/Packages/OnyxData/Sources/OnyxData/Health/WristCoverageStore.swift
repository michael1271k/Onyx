import Foundation
import GRDB
import OnyxCore

/// `wrist_coverage` — the off-wrist minutes of each day's night window
/// (App Store W6). Local only; see `v37.wristCoverage`.
extension AppDatabase {

    /// Upsert, and a no-op when the whole minutes have not moved: the row is
    /// watched by `RescoreDoor`, and today's window grows at every sync — a
    /// write that changes nothing must not ask for a rescore.
    public func writeWristCoverage(userId: String, date: String, offWristMin: Double) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO wrist_coverage (user_id, date, off_wrist_min) VALUES (?, ?, ?)
                ON CONFLICT (user_id, date) DO UPDATE SET off_wrist_min = excluded.off_wrist_min
                    WHERE off_wrist_min IS NOT excluded.off_wrist_min
                """, arguments: [userId, date, offWristMin.rounded()])
        }
    }

    /// `date → minutes` over `[from, to]`. The ONE read, for the scorer and
    /// the export alike.
    ///
    /// Empty — never a throw — on a store below v37: the widget extension
    /// opens the App Group file read-only and never migrates, so after an
    /// update it can meet the old schema before the app has run once, and a
    /// throw here would blank every widget until then.
    static func offWristByDate(_ db: Database, userId: String, from: String, to: String) throws -> [String: Double] {
        guard try db.tableExists("wrist_coverage") else { return [:] }
        let rows = try Row.fetchAll(
            db, sql: "SELECT date, off_wrist_min FROM wrist_coverage WHERE user_id = ? AND date >= ? AND date <= ?",
            arguments: [userId, from, to])
        return Dictionary(rows.map { (row: Row) in (row["date"] as String, row["off_wrist_min"] as Double) },
                          uniquingKeysWith: { first, _ in first })
    }
}
