import Foundation
import GRDB

/// The three tables the mirror cannot generate, pulled by hand.
///
/// ── WHY THESE THREE ARE DIFFERENT ───────────────────────────────────────────
/// `workout_sessions`, `workout_sets` and `exercises` already exist locally, in
/// shapes the logger owns and that do not match Postgres: `set_index` is
/// `set_number` on the server, `workout_sessions.date` has no server column at
/// all, and the local `exercises` row invents five fields Postgres has never
/// heard of. Mirroring them beside the existing tables under a second name
/// would give the app two answers to "what did I lift on Sunday".
///
/// So they are pulled through `SyncTranslation`, into the tables that are
/// already there.
///
/// ── AND WHY THE SETS PULL REFUSES SOME SESSIONS ─────────────────────────────
/// `workout_sets` is a PROJECTION of `set_events`, rebuilt by the fold inside
/// every append. Writing pulled rows into it for a session this device has
/// events for would be erased by the next `reproject` — and, worse, would look
/// like it had worked until then.
///
/// A session with no local events is a session this device did not log: the
/// web app's history, or another device's workout before the log existed. For
/// those the server IS the record and the pulled rows are the only rows there
/// will ever be. `reproject` never touches them, because it only ever runs for
/// a session that has events.
public actor TrainingPuller {

    private let database: AppDatabase
    private let remote: any MirrorRemote
    private let userId: String
    private let windowDays: Int?

    public init(database: AppDatabase, remote: any MirrorRemote, userId: String, windowDays: Int? = 90) {
        self.database = database
        self.remote = remote
        self.userId = userId
        self.windowDays = windowDays
    }

    /// Pull the exercise catalogue, then sessions changed since the cursor,
    /// then their sets.
    ///
    /// ── THE CATALOGUE GOES FIRST ────────────────────────────────────────────
    /// `workout_sets.exercise_id` REFERENCES `exercises` and the local store
    /// enforces its foreign keys. On a device that has never pulled — the
    /// first-launch backfill — sets landing before the movements they name
    /// fail on the constraint, every one of them. Sixty rows, read first, is
    /// what makes the other 2,000 land.
    ///
    /// `onTable` fires as each of the three tables lands, with its row count,
    /// so a progress sheet can tick rows in dependency order.
    /// Pull `set_events` for these sessions and merge them.
    ///
    /// ── SEEDED FIRST, INGESTED SECOND, AND THE ORDER IS THE POINT ───────
    /// A session can straddle the day this table was created: some of its sets
    /// were logged before there were any server events, the rest after. Ingest
    /// alone would give that session a log holding only the LATER half — and
    /// `ingest` re-folds, so `reproject` would rewrite `workout_sets` from that
    /// half and the earlier sets would vanish from a workout that is complete on
    /// the server.
    ///
    /// `seedEventLog` is the existing answer to exactly this shape (it is what
    /// the first edit of a web-logged session already does): it turns the rows
    /// that ARE there into born-synced `.append`s. Run first, the fold then sees
    /// the whole session; run at all, it is a no-op for any session that already
    /// has events, which is the common case.
    ///
    /// ── AND THE WHOLE THING IS BEST-EFFORT ───────────────────────
    /// `set_events` is applied by hand (`wave-10-set-events.sql (git history)`).
    /// Until the SQL is run PostgREST answers 404, and a refresh that threw on
    /// that would take the sessions and sets — which landed fine — down with
    /// it. Returns 0 instead, and the pull starts working the day the table
    /// exists, with no client change.
    private func ingestRemoteEvents(sessionIds: [String], loggedAt: [String: Date]) async throws -> Int {
        guard !sessionIds.isEmpty else { return 0 }
        let rows: [RemoteSetEventRow]
        do {
            rows = try await remote.selectIn(
                RemoteSetEventRow.self, table: "set_events", column: "session_id", values: sessionIds
            )
        } catch {
            return 0
        }
        guard !rows.isEmpty else { return 0 }
        // The seeds carry the server's clock for each row (see `seedEventLog`),
        // so a session the watch logged and the phone finishes is timed by its
        // sets, not by this pull.
        try database.seedEventLogs(sessionIds: Set(rows.map(\.sessionId)), loggedAt: loggedAt)
        try database.ingest(rows.map(\.event))
        return rows.count
    }

    @discardableResult
    public func refresh(
        now: Date = Date(), onTable: (@Sendable (String, Int) -> Void)? = nil
    ) async throws -> MirrorReport {
        var report = MirrorReport()

        // The catalogue is 60 rows and changes when a movement is added, which
        // is a few times a year. A cursor for that is bookkeeping nobody reads.
        let exercises: [RemoteExerciseRow] = try await remote.select(
            RemoteExerciseRow.self,
            request: MirrorRequest(table: "exercises", userId: userId, since: nil)
        )
        let catalogue = try database.applyPulledExercises(exercises)
        report.rows += catalogue
        report.tables += 1
        report.rowsByTable["exercises"] = catalogue
        onTable?("exercises", catalogue)

        // ── ROWS THE SERVER NO LONGER HAS ───────────────────────────────────
        // `applyPulledExercises` only ever inserts and updates, and the pull
        // above is a FULL snapshot (`since: nil`) — so a movement DELETED on
        // the server, which is what merging two duplicates does, survives here
        // forever. `Lat Pulldown (Cable)` was merged into `Lat Pulldown` on the
        // server and went on being a second row in the phone's library.
        //
        // It is a second row rather than a dead one because
        // `merge-exercise.mjs` (git history) re-points `workout_sets.exercise_id`
        // WITHOUT touching the parent session's `updated_at` — the only delta
        // the sets pull below has. So the cursor skips exactly the rows that
        // need re-pointing, the local sets keep the dead id, and
        // `exerciseCatalogStream`'s `HAVING COUNT(s.id) > 0` duly lists the
        // movement twice.
        //
        // Both halves have to move, in this order: pull every session's sets
        // again so they carry the surviving id, THEN drop the rows nothing
        // points at any more.
        let orphans = try database.exerciseIds(absentFrom: exercises.map(\.id))
        // ponytail: one full session re-pull per orphan discovery. A set that
        // can never be re-pulled — a phone-logged session's own event fold —
        // would keep an orphan alive and force a full pull every refresh.
        // Those sets carry `helix5-` slugs rather than catalogue uuids, so
        // today they cannot reference one; if that ever changes, this wants a
        // "tried at" stamp beside the cursor rather than a bare `isEmpty`.
        let cursor = orphans.isEmpty
            ? try database.mirrorCursor(table: "workout_sessions")
            : nil
        let request = MirrorRequest(
            table: "workout_sessions",
            userId: userId,
            since: cursor.map { ("updated_at", ISO8601.string($0)) }
        )
        let remoteSessions: [RemoteSessionRow] = try await remote.select(RemoteSessionRow.self, request: request)
        let newest = try database.applyPulledSessions(remoteSessions)
        report.tables += 1
        report.rows += remoteSessions.count
        report.rowsByTable["workout_sessions"] = remoteSessions.count
        onTable?("workout_sessions", remoteSessions.count)

        // Sets come with their parents. They carry neither an `updated_at` nor a
        // date of their own, so "the sets of the sessions that changed" is the
        // only delta available — and it is the right one, because a set edit
        // bumps its session's `updated_at` through the same trigger.
        let sessionIds = remoteSessions.map(\.id)
        if !sessionIds.isEmpty {
            let sets: [RemoteSetRow] = try await remote.selectIn(
                RemoteSetRow.self, table: "workout_sets", column: "session_id", values: sessionIds
            )
            let landed = try database.applyPulledSets(sets)
            report.rows += landed
            report.tables += 1
            report.rowsByTable["workout_sets"] = landed
            onTable?("workout_sets", landed)

            // ── AND THEN THE EVENTS THOSE ROWS ARE A FOLD OF ──────────────
            // `applyPulledSets` above deliberately skips any session this device
            // already has events for. That is correct for ROWS and it is exactly
            // why a second writer's sets could never arrive: the phone has
            // events, so the watch's set 4 — upserted to `workout_sets` by the
            // watch's own drain — is filtered straight back out on the way down.
            //
            // The log is the path that is allowed in. `ingest` de-duplicates by
            // event id, pulls the Lamport clock up, marks each event synced and
            // re-folds, so a set from another device lands in the same list by
            // the same merge rule both devices already use.
            let loggedAt = Dictionary(sets.compactMap { s in s.createdAt.map { (s.id, $0) } }, uniquingKeysWith: { a, _ in a })
            let landedEvents = try await ingestRemoteEvents(sessionIds: sessionIds, loggedAt: loggedAt)
            report.rows += landedEvents
            report.rowsByTable["set_events"] = landedEvents
            // Reported even at zero. `set_events` is in `backfillOrder`, and the
            // progress sheet marks a table LANDED when it is told a count — a
            // table that only speaks up when it has rows sits at "pending"
            // forever on a first launch that predates the log, which reads as a
            // backfill that never finished.
            onTable?("set_events", landedEvents)
        }

        // Now that the sets carry the surviving ids, the dead rows are
        // unreferenced and can go. Anything still referenced is LEFT alone — a
        // dangling `exercise_id` costs the set its name everywhere history is
        // drawn, which is worse than the duplicate this exists to remove.
        if !orphans.isEmpty {
            let dropped = try database.deleteUnreferencedExercises(ids: orphans)
            report.rowsByTable["exercises_removed"] = dropped
            onTable?("exercises_removed", dropped)
        }

        // Last, and only on success: a cursor moved before the sets landed
        // would skip them forever on the next pull.
        try database.setMirrorCursor(table: "workout_sessions", to: newest, at: now)
        return report
    }
}

/// `public.exercises`, reduced to the two columns the local table shares with it.
public struct RemoteExerciseRow: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    /// `exercises.slug` — nil until the W2 DDL has run on the server.
    public var slug: String?

    public init(id: String, name: String, slug: String? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
    }
}

// MARK: - Landing the rows

extension AppDatabase {

    /// Server sessions → the local `workout_sessions` table.
    ///
    /// Returns the newest `updated_at` seen, which becomes the cursor.
    @discardableResult
    func applyPulledSessions(_ rows: [RemoteSessionRow]) throws -> Date? {
        guard !rows.isEmpty else { return nil }
        return try writer.write { db in
            var newest: Date?
            // ── WHICH SESSIONS THIS DEVICE HAS NOT FINISHED TELLING THE
            // SERVER ABOUT ──────────────────────────────────────────────────
            // `closeSession` and `updateMetrics` both write their columns and
            // then enqueue `session:<id>`. Until that item drains, the SERVER'S
            // copy of this row predates the close — and this is a whole-row
            // `save`, so pulling it back wrote `ended_at`, `session_rpe`,
            // `duration_min`, `avg_bpm` and `calories_burned` as they stood
            // BEFORE the workout was finished.
            //
            // That is the "Resume workout" loop: a session closed locally,
            // pulled back open on the next foreground, the Train tab reading it
            // as live again on every launch until the drain happened to win the
            // race. The rating went with it — a finished session with an empty
            // difficulty is the same write, one column over.
            //
            // Read once for the batch rather than per row: `idempotency_key` is
            // UNIQUE, so this is an index scan of a queue that holds tens of
            // rows, not thousands.
            let queued = try Set(String.fetchAll(
                db, sql: "SELECT idempotency_key FROM outbox WHERE idempotency_key LIKE 'session:%'"
            ))
            for row in rows {
                let existing = try WorkoutSession.fetchOne(db, key: row.id)
                // `??`, not an override: where this device has nothing the
                // server's answer still lands. It only refuses to replace a
                // local value with an older remote one.
                let unpushed = queued.contains("session:\(row.id)")
                func local<T>(_ ours: T?, _ theirs: T?) -> T? {
                    unpushed ? (ours ?? theirs) : theirs
                }
                var session = WorkoutSession(
                    id: row.id,
                    userId: row.userId,
                    dayKey: row.dayKey,
                    // The column that does not exist server-side, derived here
                    // and nowhere else. The device's calendar, never the
                    // server's — a session logged at 21:30 UTC on a Wednesday
                    // in Jerusalem belongs to Thursday.
                    date: SyncTranslation.sessionDate(for: row.startedAt),
                    startedAt: row.startedAt,
                    endedAt: local(existing?.endedAt, row.endedAt),
                    durationMin: local(existing?.durationMin, row.durationMin.map(Double.init)),
                    sessionRpe: local(existing?.sessionRpe, row.sessionRpe),
                    notes: local(existing?.notes, row.notes),
                    avgBpm: local(existing?.avgBpm, row.avgBpm),
                    caloriesBurned: local(existing?.caloriesBurned, row.caloriesBurned),
                    // The provenance flags travel with the figures they
                    // describe, or a locally measured heart rate keeps the
                    // server's "estimated" stamp and `sessionsNeedingMetrics`
                    // overwrites it on the next Health sync.
                    avgBpmEstimated: unpushed && existing?.avgBpm != nil
                        ? existing!.avgBpmEstimated : row.avgBpmEstimated,
                    caloriesEstimated: unpushed && existing?.caloriesBurned != nil
                        ? existing!.caloriesEstimated : row.caloriesEstimated,
                    // ── A PULL MUST NOT ERASE WHAT THIS DEVICE COMPUTED ─────
                    // This is a whole-row `save`, so every column not carried
                    // here is written back as its default. The web computes
                    // the three aggregates on save and the phone computes them
                    // on close and on edit, so the pulled value is the right
                    // one to keep — but a server NULL on a session THIS device
                    // has the sets for would blank a figure the tab renders.
                    // Server first, ours as the fallback.
                    totalVolumeKg: row.totalVolumeKg ?? existing?.totalVolumeKg,
                    setCount: row.setCount ?? existing?.setCount,
                    prCount: row.prCount ?? existing?.prCount,
                    // Local-only and never on the wire: a pull has no opinion
                    // about who typed the duration, so the flag survives it.
                    // Without this line, one sync would hand a hand-corrected
                    // duration back to `closeSession` to re-derive.
                    durationEdited: existing?.durationEdited ?? false,
                    // It came FROM the server, so by definition it is not
                    // waiting to go TO it — unless this device still has queued
                    // events for it, in which case the flag is not ours to
                    // clear and the existing value stands.
                    isPendingSync: existing?.isPendingSync ?? false
                )
                if existing?.isPendingSync == true { session.isPendingSync = true }
                try session.save(db)
                if let at = row.updatedAt, newest == nil || at > newest! { newest = at }
            }
            return newest
        }
    }

    /// Server sets → the local projection, for sessions this device never logged.
    @discardableResult
    func applyPulledSets(_ rows: [RemoteSetRow]) throws -> Int {
        guard !rows.isEmpty else { return 0 }
        return try writer.write { db in
            var written = 0
            var bySession: [String: [RemoteSetRow]] = [:]
            for row in rows { bySession[row.sessionId, default: []].append(row) }

            for (sessionId, sessionRows) in bySession {
                // THE GUARD. A session with events is a session whose sets are
                // a fold over them; pulled rows would be deleted by the very
                // next append and the two would disagree in between.
                let hasEvents = try Int.fetchOne(
                    db, sql: "SELECT count(*) FROM set_events WHERE session_id = ?", arguments: [sessionId]
                ) ?? 0
                guard hasEvents == 0 else { continue }

                // Replace the session's sets wholesale. Safe here and ONLY here:
                // these rows are not local facts, the pull returned all of them
                // for this session, and a set deleted on the server has to be
                // able to disappear locally.
                try db.execute(
                    sql: "DELETE FROM workout_sets WHERE session_id = ?", arguments: [sessionId]
                )
                for (order, row) in sessionRows.sorted(by: { $0.setNumber < $1.setNumber }).enumerated() {
                    try WorkoutSet(
                        id: row.id,
                        sessionId: row.sessionId,
                        exerciseId: row.exerciseId,
                        // The rename, inverted.
                        setIndex: row.setNumber,
                        weightKg: row.weightKg,
                        reps: row.reps,
                        setType: row.setType,
                        side: SyncTranslation.localSide(row.side),
                        pairId: row.pairId,
                        est1rmKg: row.est1rmKg,
                        rpe: row.rpe,
                        // The other half of the round trip the push half opened
                        // (`RemoteSetRow.quality`). Without it a tag the web
                        // recorded is invisible on the phone, and the first
                        // edit here seeds an event log from a projection that
                        // never had it — which is how a "Cheated" quietly
                        // becomes no tag at all on the device that adopted it.
                        quality: row.quality,
                        // The web's own deck order, kept rather than re-derived.
                        // `seedEventLog` carries it into the log on the first
                        // edit, which is what stops this device pushing a null
                        // back over it — and it lets the report group a
                        // web-logged session the way it actually happened.
                        exerciseOrder: row.exerciseOrder,
                        // The cardio axes. Without these the treadmill that
                        // opens 2026-09-07 arrives as `weight_kg 0, reps 0` and
                        // nothing else, and the report renders five minutes of
                        // walking as `0kg × 0`.
                        durationSec: row.durationSec,
                        incline: row.incline,
                        distanceKm: row.distanceKm,
                        // The fourth axis, on the same terms: nil on every row
                        // until `cardio-elevation.sql (git history)` is applied.
                        elevationM: row.elevationM,
                        isPendingSync: false,
                        foldOrder: order
                    ).save(db)
                    written += 1
                }
            }
            return written
        }
    }

    /// Server catalogue → the local `exercises` table.
    ///
    /// Only `id` and `name`: the two columns the two schemas share. The local
    /// table's other five fields are the logger's own and are left alone, which
    /// is why this is a targeted UPDATE-or-INSERT rather than a `save` of a
    /// freshly built row — the latter would blank them on every pull.
    @discardableResult
    func applyPulledExercises(_ rows: [RemoteExerciseRow]) throws -> Int {
        guard !rows.isEmpty else { return 0 }
        return try writer.write { db in
            for row in rows {
                try db.execute(
                    sql: """
                        INSERT INTO exercises (id, name, slug) VALUES (?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET name = excluded.name, slug = excluded.slug
                        """,
                    arguments: [row.id, row.name, row.slug]
                )
            }
            return rows.count
        }
    }

    /// Local catalogue ids the server's snapshot does not contain.
    ///
    /// Only meaningful against a FULL snapshot, which is why the catalogue pull
    /// carries no cursor. An EMPTY remote list returns nothing rather than
    /// everything: a pull that came back empty is a failure far more often than
    /// it is a catalogue somebody deleted, and the difference between those two
    /// readings is the whole library.
    func exerciseIds(absentFrom remote: [String]) throws -> [String] {
        guard !remote.isEmpty else { return [] }
        let live = Set(remote)
        return try writer.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM exercises")
        }.filter { !live.contains($0) }
    }

    /// Drop catalogue rows nothing logged points at any more.
    ///
    /// The `NOT EXISTS` is the entire safety of this. `v4` removed the foreign
    /// key from `workout_sets.exercise_id`, so SQLite will happily delete a row
    /// two hundred sets still name and leave every one of them anonymous.
    @discardableResult
    func deleteUnreferencedExercises(ids: [String]) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
        return try writer.write { db in
            try db.execute(
                sql: """
                    DELETE FROM exercises
                     WHERE id IN (\(marks))
                       AND NOT EXISTS (
                           SELECT 1 FROM workout_sets WHERE exercise_id = exercises.id
                       )
                    """,
                arguments: StatementArguments(ids)
            )
            return db.changesCount
        }
    }
}
