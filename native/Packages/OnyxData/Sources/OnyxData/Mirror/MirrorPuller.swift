import Foundation
import GRDB

/// Anything the mirror can store: a Postgres row, decodable off the wire and
/// persistable into SQLite under the same column names.
public typealias MirrorRow = Codable & FetchableRecord & PersistableRecord & Sendable

public enum MirrorGroup: String, Sendable, CaseIterable {
    case training, daily, body, plan, reports
}

/// How a table is kept current.
public enum MirrorStrategy: Sendable, Equatable {
    /// Everything at or after the newest value this device already holds.
    ///
    /// **Only as trustworthy as the column.** `updated_at` is maintained by a
    /// `BEFORE UPDATE` trigger server-side; before that trigger existed the
    /// column was written by whichever client touched the row, and a phone
    /// running three minutes slow stamped an edit in the past — where a
    /// `>= cursor` filter would never see it again.
    case delta(column: String)
    /// A trailing window on a date or timestamp column, for the append-mostly
    /// day-keyed tables that carry no `updated_at` at all.
    ///
    /// It cannot see an edit to a row older than the window. Realtime is what
    /// covers that (`MirrorRealtime`), and a wider window is the fallback.
    case window(column: String)
    /// Small, rarely written, cheaper to re-read than to reason about.
    case full
}

/// One mirrored table.
///
/// `pull` is a closure rather than a generic parameter because the catalogue is
/// a heterogeneous list — 26 different row types in one array — and a protocol
/// with an associated type cannot be put in one. The closure captures the type
/// at the point the generator knows it.
public struct MirrorTable: Sendable {
    public let name: String
    public let group: MirrorGroup
    public let strategy: MirrorStrategy
    /// The PostgREST conflict target for a LOCAL write of this table — the
    /// natural key wherever Postgres has one, `id` otherwise.
    ///
    /// Load-bearing. Every one of these tables has an `id` primary key, so
    /// upserting on `id` compiles, reads right and is wrong: a day this device
    /// invented a uuid for is a row the server already holds under a different
    /// one, and the insert dies on `daily_logs_user_id_date_key` every time it
    /// is retried. Introspected from `pg_constraint`, not assumed.
    public let conflict: String
    /// The primary key, in column order — the ORDER BY of every paged pull.
    ///
    /// Keyset pagination needs a total order, and this is it; without one
    /// Postgres may hand back a row on two pages and another on none. The
    /// primary key is the one order every table is guaranteed to have.
    public let order: [String]
    let pull: @Sendable (MirrorPuller, MirrorRequest) async throws -> Int
    /// Read one local row by id and upsert it. `false` when the row is gone.
    ///
    /// A closure for the same reason `pull` is one: the catalogue is a
    /// heterogeneous list of twenty-six row types, and only the generator knows
    /// which type each name means.
    let push: @Sendable (AppDatabase, any MirrorPushRemote, RowRef) async throws -> Bool

    public init(
        name: String,
        group: MirrorGroup,
        strategy: MirrorStrategy,
        conflict: String = "id",
        order: [String] = ["id"],
        pull: @escaping @Sendable (MirrorPuller, MirrorRequest) async throws -> Int,
        push: @escaping @Sendable (AppDatabase, any MirrorPushRemote, RowRef) async throws -> Bool
    ) {
        self.name = name
        self.group = group
        self.strategy = strategy
        self.conflict = conflict
        self.order = order
        self.pull = pull
        self.push = push
    }
}

/// What one table's pull is asking the server for.
public struct MirrorRequest: Sendable, Equatable {
    public let table: String
    public let userId: String
    /// `nil` for a full pull.
    public let since: (column: String, value: String)?
    /// The total order the pages are read in. See `MirrorTable.order`.
    public let order: [String]

    public init(
        table: String, userId: String, since: (column: String, value: String)?, order: [String] = ["id"]
    ) {
        self.table = table
        self.userId = userId
        self.since = since
        self.order = order
    }

    public static func == (lhs: MirrorRequest, rhs: MirrorRequest) -> Bool {
        lhs.table == rhs.table && lhs.userId == rhs.userId
            && lhs.since?.column == rhs.since?.column && lhs.since?.value == rhs.since?.value
            && lhs.order == rhs.order
    }
}

/// The read half of sync. A protocol for the same reason `SyncRemote` is one:
/// every interesting case is a network case.
public protocol MirrorRemote: Sendable {
    /// `GET /rest/v1/<table>?select=*&user_id=eq.<id>[&<col>=gte.<value>]`
    func select<T: Decodable & Sendable>(
        _ type: T.Type, request: MirrorRequest
    ) async throws -> [T]
    /// Rows of one table by an `in` list. Used for `workout_sets`, which has
    /// neither an `updated_at` nor a date of its own.
    func selectIn<T: Decodable & Sendable>(
        _ type: T.Type, table: String, column: String, values: [String]
    ) async throws -> [T]
    /// How many rows the SERVER holds for this user in one table.
    ///
    /// Not part of any pull — nothing is decoded and nothing is stored. It
    /// exists because every sync failure this app has shipped was invisible in
    /// the same way: the device could only ever report what the device already
    /// had. A local count next to the server's own count is the one comparison
    /// that makes a hole visible instead of inferred, and it is what the Sync
    /// Doctor draws.
    func count(table: String) async throws -> Int
}

/// Pulls Postgres into the local store.
///
/// ── WHAT REPLACED WHAT ──────────────────────────────────────────────────────
/// `NutritionSync` pulled four tables for one screen with four hand-written
/// queries and four hand-written wire types, and every new screen would have
/// added its own. This is that, generalised: the queries come from a generated
/// catalogue, the wire types ARE the storage types, and adding a table is a
/// line in `native/schema/supabase.json`.
///
/// It only ever writes rows that came from the server. Nothing here can lose a
/// local fact, because nothing here touches a table the device writes to — the
/// three that it does are handled by `TrainingPuller`, which knows about the
/// event log and refuses to overwrite it.
public actor MirrorPuller {

    private let database: AppDatabase
    private let remote: any MirrorRemote
    private let userId: String
    /// How far back a `.window` strategy reaches. Ninety days covers every
    /// trailing average the app computes (the longest is the 14-night sleep-debt
    /// decay and the 40-session calorie sample) with room to spare.
    ///
    /// `nil` removes the cap: a `.window` table is pulled WHOLE, every time.
    /// That is what the app runs with since Phase 2 (decision 7 — full history,
    /// no 90-day horizon); the parameter stays so the window tests keep their
    /// subject. Every row that comes back is upserted, so the cost is bytes,
    /// never correctness.
    private let windowDays: Int?

    public init(database: AppDatabase, remote: any MirrorRemote, userId: String, windowDays: Int? = 90) {
        self.database = database
        self.remote = remote
        self.userId = userId
        self.windowDays = windowDays
    }

    /// Refresh every table, or one group of them.
    ///
    /// Failures are per-table and collected, not thrown: one table that 404s
    /// because a migration has not run must not stop the other twenty-five. The
    /// report says which, and the cursor of a table that failed is left where it
    /// was, so the next pull asks for the same range again.
    ///
    /// `onTable` fires as each table lands, with its row count — what the
    /// backfill sheet ticks. A failed table fires nothing; the report says why.
    @discardableResult
    public func refresh(
        group: MirrorGroup? = nil,
        tables: [MirrorTable] = MirrorCatalogue.tables,
        now: Date = Date(),
        onTable: (@Sendable (String, Int) -> Void)? = nil
    ) async -> MirrorReport {
        var report = MirrorReport()
        for table in tables where group == nil || table.group == group {
            do {
                let rows = try await refresh(table, now: now)
                report.rows += rows
                report.tables += 1
                report.rowsByTable[table.name] = rows
                onTable?(table.name, rows)
            } catch {
                report.failures[table.name] = String(describing: error)
            }
        }
        return report
    }

    /// Refresh one table.
    @discardableResult
    public func refresh(_ table: MirrorTable, now: Date = Date()) async throws -> Int {
        let request = MirrorRequest(
            table: table.name, userId: userId, since: try since(table, now: now), order: table.order
        )
        let count = try await table.pull(self, request)
        // The cursor is read back out of the LOCAL table rather than tracked
        // through the decode. It means one place knows how to read a timestamp
        // column — SQLite — instead of every row type having to expose its own
        // cursor, and "the newest row I hold" is exactly what the next delta
        // wants to ask from.
        if case .delta(let column) = table.strategy {
            try database.setMirrorCursor(table: table.name, to: database.maxTimestamp(table: table.name, column: column), at: now)
        }
        return count
    }

    /// The server's row count for one table, for the Sync Doctor.
    ///
    /// A pass-through, and it lives here only because the puller is who holds
    /// the remote. It touches neither the store nor a cursor: asking the server
    /// how many rows it has must never be able to move a delta forward.
    public func serverCount(table: String) async throws -> Int {
        try await remote.count(table: table)
    }

    /// Decode and store. Called by the generated catalogue, which is what knows
    /// each table's row type.
    func pull<T: MirrorRow>(_ type: T.Type, from request: MirrorRequest) async throws -> Int {
        let rows: [T] = try await remote.select(T.self, request: request)
        try database.saveMirrorRows(rows)
        return rows.count
    }

    /// The filter for this table's next pull.
    private func since(_ table: MirrorTable, now: Date) throws -> (column: String, value: String)? {
        switch table.strategy {
        case .full:
            return nil
        case .window(let column):
            guard let windowDays else { return nil }
            let from = Calendar.current.date(byAdding: .day, value: -windowDays, to: now) ?? now
            // A `date` column wants `yyyy-MM-dd`; a `timestamptz` wants an
            // instant. Asking for the day is correct for both — PostgREST widens
            // a date to midnight — and it keeps the window aligned to days,
            // which is how every screen that reads these tables thinks.
            return (column, LogicalDayISO.string(from))
        case .delta(let column):
            guard let cursor = try database.mirrorCursor(table: table.name) else { return nil }
            // `gte`, not `gt`. Two rows written in the same millisecond would
            // otherwise lose the second one forever; re-reading the boundary row
            // costs one row and is a no-op, because every write here is an
            // upsert on the primary key.
            return (column, ISO8601.string(cursor))
        }
    }
}

/// What a refresh did.
public struct MirrorReport: Sendable, Equatable {
    public var tables = 0
    public var rows = 0
    /// Table name → rows landed, for every table that succeeded. What the
    /// `sync_status` ledger is written from.
    public var rowsByTable: [String: Int] = [:]
    /// Table name → the error it reported. Empty is the happy path.
    public var failures: [String: String] = [:]

    public var isClean: Bool { failures.isEmpty }

    /// Fold another report in. A later count for the same table wins.
    public mutating func merge(_ other: MirrorReport) {
        rows += other.rows
        tables += other.tables
        rowsByTable.merge(other.rowsByTable) { _, new in new }
        failures.merge(other.failures) { _, new in new }
    }
}

// MARK: - Formatting

/// ISO-8601 with fractional seconds, which is what PostgREST returns for a
/// `timestamptz` and what it accepts back in a filter.
enum ISO8601 {
    /// Built per call, not shared. `ISO8601DateFormatter` is a mutable reference
    /// type and therefore not `Sendable`, so a `static let` is a data race the
    /// Swift 6 compiler is right to reject. Allocating one is only worth
    /// avoiding in a hot loop — `LogicalDay` says exactly that about a list row —
    /// and this runs a couple of dozen times per refresh, not per row.
    private static func formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }
    static func string(_ date: Date) -> String { formatter().string(from: date) }
    static func date(_ string: String) -> Date? { formatter().date(from: string) }
}

/// `yyyy-MM-dd` in the device's calendar. The same rule `LogicalDay` in
/// OnyxCore applies, restated here only so this file does not have to import
/// the domain package to format a window boundary.
enum LogicalDayISO {
    static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }
}
