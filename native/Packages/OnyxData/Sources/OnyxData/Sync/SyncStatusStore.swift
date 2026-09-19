import Foundation
import GRDB

/// One line of the sync ledger.
public struct SyncStatusRow: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "sync_status"

    public var id: Int64?
    public var userId: String
    public var tableName: String
    public var syncedAt: Date
    public var reason: String
    public var rows: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case tableName = "table_name"
        case syncedAt = "synced_at"
        case reason, rows
    }
}

public extension AppDatabase {

    /// Append one successful pull to the ledger. Never updated, never deleted
    /// by the app: the table is the history.
    func recordSync(userId: String, table: String, rows: Int, reason: String, at now: Date) throws {
        try writer.write { db in
            try SyncStatusRow(id: nil, userId: userId, tableName: table, syncedAt: now, reason: reason, rows: rows)
                .insert(db)
        }
    }

    /// The newest ledger rows for one table name, newest first — Sync doctor
    /// draws the rescore runs off this (`table_name = "rescore"`).
    func syncLedger(userId: String, table: String, limit: Int) throws -> [SyncStatusRow] {
        try writer.read { db in
            try SyncStatusRow
                .filter(Column("user_id") == userId && Column("table_name") == table)
                .order(Column("synced_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Table → when it last synced successfully. Empty for a user who has
    /// never synced, which is how a first launch is recognised.
    func lastSync(userId: String) throws -> [String: Date] {
        try writer.read { db in
            var out: [String: Date] = [:]
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT table_name, max(synced_at) AS at FROM sync_status WHERE user_id = ? GROUP BY table_name",
                arguments: [userId]
            )
            for row in rows {
                if let name: String = row["table_name"], let at: Date = row["at"] { out[name] = at }
            }
            return out
        }
    }
}
