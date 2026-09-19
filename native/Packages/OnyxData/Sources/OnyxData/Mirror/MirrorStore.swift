import Foundation
import GRDB

// MARK: - Writing mirrored rows

extension AppDatabase {

    /// Save server rows, upserting on the primary key.
    ///
    /// ── UPSERT, NEVER DELETE-THEN-INSERT ────────────────────────────────────
    /// `replaceNutritionDays` used to clear a date range and re-insert it, on
    /// the grounds that an upsert leaves behind rows the server has since
    /// deleted. That was safe for one table that held nothing local. It is not
    /// safe here: a delta pull returns only what CHANGED, so clearing the range
    /// first would delete every unchanged row in it and leave the table holding
    /// whatever happened to be edited recently.
    ///
    /// The cost is that a row deleted on the server lingers locally until a full
    /// pull. For a training log — where the overwhelming majority of deletes are
    /// the user's own, made on this device — showing a stale row is the correct
    /// direction to fail in, and it is the same trade the event log makes.
    func saveMirrorRows<T: MirrorRow>(_ rows: [T]) throws {
        guard !rows.isEmpty else { return }
        try writer.write { db in
            // Pulled, not edited: the rescore door reads past these rows.
            try Self.markMirrorWrite(db) {
                for row in rows { try row.save(db) }
            }
        }
    }

    /// The newest value of a timestamp column, for a delta cursor.
    ///
    /// Read out of SQLite rather than tracked through the decode: one place
    /// knows how to read a timestamp, instead of 26 row types each having to
    /// expose their own cursor field.
    func maxTimestamp(table: String, column: String) -> Date? {
        try? writer.read { db in
            try Date.fetchOne(db, sql: "SELECT max(\"\(column)\") FROM \"\(table)\"")
        }
    }
}

// MARK: - Cursors

extension AppDatabase {

    /// How far a table has been pulled.
    public func mirrorCursor(table: String) throws -> Date? {
        try writer.read { db in
            try Date.fetchOne(
                db, sql: "SELECT cursor_at FROM sync_cursors WHERE table_name = ?", arguments: [table]
            )
        }
    }

    /// Move a cursor forward.
    ///
    /// Forward only. A cursor that could move BACKWARDS would re-pull the same
    /// range forever; one that could be cleared by an empty pull would re-pull
    /// the entire table on the next refresh, which on a metered connection is
    /// the difference between a sync and a download.
    func setMirrorCursor(table: String, to value: Date?, at now: Date) throws {
        guard let value else { return }
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO sync_cursors (table_name, cursor_at, pulled_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(table_name) DO UPDATE
                      SET cursor_at = max(excluded.cursor_at, sync_cursors.cursor_at),
                          pulled_at = excluded.pulled_at
                    """,
                arguments: [table, value, now]
            )
        }
    }

    /// Forget a table's cursor, so the next refresh pulls it whole.
    ///
    /// The repair for the one failure a delta cursor cannot detect: a row that
    /// was written with a timestamp in the past — which is exactly what every
    /// client-stamped `updated_at` was before the server-side trigger existed.
    public func resetMirrorCursor(table: String? = nil) throws {
        try writer.write { db in
            if let table {
                try db.execute(sql: "DELETE FROM sync_cursors WHERE table_name = ?", arguments: [table])
            } else {
                try db.execute(sql: "DELETE FROM sync_cursors")
            }
        }
    }

    /// Every cursor, for a diagnostics screen.
    public func mirrorCursors() throws -> [String: Date] {
        try writer.read { db in
            var out: [String: Date] = [:]
            let rows = try Row.fetchAll(db, sql: "SELECT table_name, cursor_at FROM sync_cursors")
            for row in rows {
                if let name: String = row["table_name"], let at: Date = row["cursor_at"] { out[name] = at }
            }
            return out
        }
    }
}

// MARK: - Observation

extension AppDatabase {

    /// Bridge a `ValueObservation` into an `AsyncThrowingStream`.
    ///
    /// ── WHY A STREAM AND NOT A `ValueObservation` IN THE SIGNATURE ───────────
    /// `observeSets` returns `ValueObservation<ValueReducers.Fetch<[WorkoutSet]>>`,
    /// which names two GRDB types in a public signature and forces every caller
    /// to import GRDB to hold the result. The database is supposed to be an
    /// implementation detail of this package; a view that cannot name its own
    /// data source without importing SQLite's Swift wrapper is not one.
    ///
    /// A stream is also what SwiftUI wants: `for await rows in stream` inside
    /// `.task`, cancelled automatically when the view goes away.
    ///
    /// `.immediate` scheduling so the first value arrives synchronously rather
    /// than one hop later. The difference is a frame of the empty state on every
    /// appearance, which reads as a flicker on a list whose data is already on
    /// disk — and having it on disk is the entire reason this store exists.
    ///
    /// - important: call this from the main actor. `.immediate` traps otherwise
    ///   — `ImmediateValueObservationScheduler.immediateInitialValue()` is a
    ///   `GRDBPrecondition(Thread.isMainThread)`. Every caller today is a
    ///   `@MainActor` model or a `@MainActor` test, which is why the rule has
    ///   never been felt; it is a runtime rule, not a compile-time one.
    public func stream<T: Sendable>(
        _ observation: ValueObservation<ValueReducers.Fetch<T>>
    ) -> AsyncThrowingStream<T, any Error> {
        AsyncThrowingStream { continuation in
            // ── WHY THE SCHEDULER IS BOUND TO AN EXISTENTIAL FIRST ───────────
            // GRDB declares `start(in:scheduling:onError:onChange:)` TWICE, and
            // `ImmediateValueObservationScheduler` conforms to both scheduler
            // protocols — so a bare `.immediate` leaves the `@MainActor`
            // overload viable, it wins as the more specialised candidate, and
            // this nonisolated function cannot call it. Under Swift 6 that is
            // an isolation violation held down to a warning only by GRDB's
            // `@preconcurrency`; the day that attribute comes off, it is an
            // error and the app target stops building.
            //
            // Binding to `any ValueObservationScheduler` opens the existential
            // (SE-0352) into a type parameter whose only conformance is the
            // BASE protocol, so `some ValueObservationMainActorScheduler` is
            // unsatisfiable and the nonisolated overload is the only candidate
            // left. The scheduler value is unchanged, so the synchronous first
            // fetch the doc comment above promises still happens inside
            // `start` — that was verified, not assumed.
            //
            // The `let` is load-bearing: existentials only open through a
            // reference to a binding, so inlining this as a cast is a hard
            // error, not a silent regression.
            let scheduler: any ValueObservationScheduler = .immediate
            let cancellable = observation.start(
                in: writer,
                scheduling: scheduler,
                onError: { continuation.finish(throwing: $0) },
                onChange: { continuation.yield($0) }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// A live sequence of one mirrored table, filtered and ordered by the caller.
    ///
    /// This is what replaces the react-query layer wholesale: there is no cache
    /// to invalidate, no query key to match, and no way for the view and the
    /// store to disagree. A pull writes a row; the observation fires; the view
    /// redraws.
    public func mirrorStream<T: MirrorRow & FetchableRecord>(
        _ type: T.Type,
        _ shape: @escaping @Sendable (QueryInterfaceRequest<T>) -> QueryInterfaceRequest<T> = { $0 }
    ) -> AsyncThrowingStream<[T], any Error> {
        stream(ValueObservation.tracking { db in try shape(T.all()).fetchAll(db) })
    }
}
