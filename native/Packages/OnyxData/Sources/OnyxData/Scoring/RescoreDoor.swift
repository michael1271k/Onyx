import Foundation
import GRDB
import OnyxCore

/// Rescore at the door (W2, decision 11): every committed write to a
/// date-bearing table reports the earliest past date it touched, and the app
/// asks for the cascade from there. No caller has to remember.
///
/// ── WHY TRIGGERS AND NOT THE OBSERVER ALONE ─────────────────────────────────
/// GRDB's `TransactionObserver` sees a table name and a rowid per change, and
/// for a DELETE that is all it will ever see — the row is gone by commit, and
/// the pre-update hook that would show its columns is not compiled into the
/// system SQLite. A water glass removed from last Tuesday is exactly the write
/// this door exists for, so the DATE is captured where it is still known:
/// TEMP triggers on each table copy it into `temp.rescore_touched` as the
/// statement runs. The observer's only job is to notice the commit and read
/// what the triggers wrote.
///
/// TEMP objects live on the connection that created them. The writer is one
/// persistent connection, so the triggers and the table are created once per
/// open, are invisible to the reader pool and the widget's read-only store,
/// and never touch the migrated schema.
///
/// ── AND WHY A PULLED ROW DOES NOT COUNT ─────────────────────────────────────
/// A row the mirror brought down was edited on another device — which ran the
/// cascade there and pushed its `daily_scores`, and those rows come down in
/// the same pull. Rescoring here again would rewrite them with the same engine
/// and push them back; a backfill would set the "history stale" flag on every
/// fresh install. So the mirror's write doors raise a per-transaction mark
/// (`markMirrorWrite`) that the triggers copy onto every row, and the door
/// reads past those rows.
///
/// ── WHAT IS NOT WATCHED ─────────────────────────────────────────────────────
/// `daily_scores` (the cascade's own output), `body_composition` and
/// `stress_logs` (not scorer inputs), and the undated tables — goals, profiles,
/// plans, routines — whose edits reach every day and are a manual recompute.
public enum RescoreDoor {

    /// A committed write to something the scorer reads, dated in the past or
    /// not — the DECISION is `Rescore.doorDecision`; this is the fact.
    public struct Touch: Sendable, Equatable {
        /// The earliest date the commit touched, ISO.
        public var date: String
        /// Inferred from the tables: sets and sessions are a session edit,
        /// a night is a sleep edit, anything else is a day edit.
        public var reason: Rescore.Reason
    }

    /// `table → (date expression, kind)` for the triggers. `OLD` and `NEW`
    /// both carry the column, so one template serves the three verbs.
    static let watched: [(table: String, column: String, kind: String)] = [
        ("daily_logs", "date", "day"),
        ("daily_metrics", "date", "day"),
        ("daily_targets", "date", "day"),
        ("nutrition_entries", "date", "day"),
        ("water_intake", "date", "day"),
        ("supplement_log", "date", "day"),
        ("fatigue_logs", "date", "day"),
        ("doms_logs", "date", "day"),
        ("cardio_logs", "date", "day"),
        ("schedule_overrides", "date", "day"),
        ("lever_periods", "starts_on", "day"),
        ("personal_records", "achieved_on", "day"),
        ("sleep_sessions", "start_time", "night"),
        ("workout_sessions", "date", "session"),
    ]
    /// One more, whose date lives on the parent session. Not `workout_sets`:
    /// every runtime write to it is `reproject` inside the same transaction as
    /// the `set_events` row that already reports the session, and a reproject
    /// rewrites every set of the session — N trigger firings per tick for a
    /// date the door already has. And `set_events` on INSERT and DELETE only:
    /// an event is immutable, so the one UPDATE it ever sees is the sync ack
    /// (`is_synced = 1`), which is not an edit.
    static let sessionChildren = ["set_events"]

    /// An UPDATE on `workout_sessions` counts only when a column the scorer
    /// reads moved. `is_pending_sync`, `avg_bpm`, `calories_burned` and
    /// `total_volume_kg` change on every ack and every finish-sheet tweak and
    /// feed no score; without this every push of a past session cascaded
    /// again.
    static let sessionScorerColumns = ["date", "day_key", "duration_min", "session_rpe", "started_at", "ended_at"]

    static var observedTables: Set<String> {
        Set(watched.map(\.table)).union(sessionChildren)
    }

    /// Create the TEMP table and triggers on `db` — the writer connection,
    /// once per open. Idempotent (`IF NOT EXISTS`).
    static func install(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TEMP TABLE IF NOT EXISTS rescore_touched (
                date TEXT NOT NULL, kind TEXT NOT NULL, mirror INTEGER NOT NULL
            );
            CREATE TEMP TABLE IF NOT EXISTS rescore_origin (mirror INTEGER NOT NULL);
            INSERT INTO temp.rescore_origin (mirror)
                SELECT 0 WHERE NOT EXISTS (SELECT 1 FROM temp.rescore_origin);
            """)
        let origin = "(SELECT mirror FROM temp.rescore_origin)"
        for (table, column, kind) in watched {
            for (verb, row) in [("INSERT", "NEW"), ("UPDATE", "NEW"), ("DELETE", "OLD")] {
                var when = ""
                if verb == "UPDATE", kind == "session" {
                    when = "WHEN " + sessionScorerColumns.map { "NEW.\($0) IS NOT OLD.\($0)" }.joined(separator: " OR ")
                }
                try db.execute(sql: """
                    CREATE TEMP TRIGGER IF NOT EXISTS rescore_\(table)_\(verb.lowercased())
                    AFTER \(verb) ON \(table) \(when) BEGIN
                        INSERT INTO temp.rescore_touched (date, kind, mirror)
                        VALUES (\(row).\(column), '\(kind)', \(origin));
                    END;
                    """)
            }
        }
        for table in sessionChildren {
            for (verb, row) in [("INSERT", "NEW"), ("DELETE", "OLD")] {
                try db.execute(sql: """
                    CREATE TEMP TRIGGER IF NOT EXISTS rescore_\(table)_\(verb.lowercased())
                    AFTER \(verb) ON \(table) BEGIN
                        INSERT INTO temp.rescore_touched (date, kind, mirror)
                        SELECT date, 'session', \(origin) FROM workout_sessions WHERE id = \(row).session_id;
                    END;
                    """)
            }
        }
    }

    /// The observer. Notices a commit that touched a watched table, reads the
    /// rows the triggers wrote since its watermark, and reports the earliest
    /// local-origin date.
    final class Observer: TransactionObserver, @unchecked Sendable {
        private let onTouch: @Sendable (Touch) -> Void
        /// The last `temp.rescore_touched` rowid already reported. The table
        /// is never cleared — a commit callback may not write — so it is read
        /// past a watermark and dies with the connection.
        private var watermark: Int64
        private var touched = false

        init(onTouch: @escaping @Sendable (Touch) -> Void, watermark: Int64) {
            self.onTouch = onTouch
            self.watermark = watermark
        }

        func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
            RescoreDoor.observedTables.contains(eventKind.tableName)
        }

        func databaseDidChange(with event: DatabaseEvent) { touched = true }

        func databaseDidCommit(_ db: Database) {
            guard touched else { return }
            touched = false
            guard let rows = try? Row.fetchAll(
                db,
                sql: "SELECT rowid, date, kind, mirror FROM temp.rescore_touched WHERE rowid > ? ORDER BY rowid",
                arguments: [watermark]
            ), let last: Int64 = rows.last?["rowid"] else { return }
            watermark = last
            var earliest: String?
            var reason = Rescore.Reason.dayEdit
            for row in rows {
                let mirror: Int = row["mirror"]
                guard mirror == 0 else { continue }
                let kind: String = row["kind"]
                // A night is filed under the morning it ended on — the date
                // the scorer reads it under; the trigger copied the bedtime.
                let date: String = kind == "night" ? NightWindow.nightOf(row["date"] as Date) : row["date"]
                if earliest == nil || date < earliest! { earliest = date }
                switch kind {
                case "session": reason = .sessionEdit
                case "night": if reason != .sessionEdit { reason = .sleepEdit }
                default: break
                }
            }
            guard let earliest else { return }
            onTouch(Touch(date: earliest, reason: reason))
        }

        func databaseDidRollback(_ db: Database) { touched = false }
    }
}

public extension Rescore {

    /// How far back the door cascades on its own (decision 11). Older edits
    /// set a flag and wait for a manual "Recompute history".
    static let doorWindowDays = 120

    /// What the app does with a touch.
    enum DoorDecision: Sendable, Equatable {
        /// `date` is past and within the window: ask the queue.
        case cascade
        /// `date` is past and older than the window: flag history stale.
        case historyStale
        /// Today or the future: nothing — today is scored live everywhere it
        /// is drawn and stored by the next sync, and a future date is a swap.
        case ignore
    }

    static func doorDecision(date: String, today: String) -> DoorDecision {
        guard date < today else { return .ignore }
        guard let d = ISODate.dayNumber(date), let t = ISODate.dayNumber(today) else { return .ignore }
        return t - d <= doorWindowDays ? .cascade : .historyStale
    }
}

public extension AppDatabase {

    /// Watch every committed write for a past date the scorer cares about.
    ///
    /// `onTouch` runs on the writer queue, once per commit, with the earliest
    /// local-origin date that commit touched. Cancel the return value to stop.
    func observePastWrites(_ onTouch: @escaping @Sendable (RescoreDoor.Touch) -> Void) -> AnyDatabaseCancellable {
        // Forget whatever the triggers already recorded: rows written before
        // anybody was listening (the seed, a migration, the previous
        // observer's lifetime) are not this observer's news, and the table is
        // never cleared anywhere else.
        try? writer.write { db in try db.execute(sql: "DELETE FROM temp.rescore_touched") }
        let observer = RescoreDoor.Observer(onTouch: onTouch, watermark: 0)
        writer.add(transactionObserver: observer, extent: .observerLifetime)
        return AnyDatabaseCancellable { [writer] in writer.remove(transactionObserver: observer) }
    }

    /// Raise the mirror mark for the rest of THIS transaction: every row the
    /// triggers see until the commit is a pulled row, not an edit. The mark
    /// is lowered at the end of the closure; a rollback lowers it for free
    /// because the temp table is transactional.
    static func markMirrorWrite<T>(_ db: Database, _ body: () throws -> T) throws -> T {
        try db.execute(sql: "UPDATE temp.rescore_origin SET mirror = 1")
        defer {
            // A throw in `body` rolls the mark back with the transaction; this
            // matters on the success path only, and a failure here — one-row
            // TEMP update, so I/O or OOM — would leave the door deaf for the
            // rest of the process. Said out loud rather than swallowed.
            do { try db.execute(sql: "UPDATE temp.rescore_origin SET mirror = 0") }
            catch { NSLog("onyx-rescore: mirror mark stuck: %@", String(describing: error)) }
        }
        return try body()
    }
}
