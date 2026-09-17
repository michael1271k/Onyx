import Foundation
import GRDB
import OnyxCore

/// Editing a workout that is already history.
///
/// ── WHY THIS IS NOT THE LOGGER ──────────────────────────────────────────────
/// `LoggerModel` writes through `set_events` into a session whose `ended_at` is
/// still NULL, and everything about it assumes the session is happening now:
/// `liveSession` finds only today's, `closeSession` derives the duration from a
/// clock that is still running, and `PrRecorder` only ever RAISES, because a
/// set being logged cannot make an older one smaller.
///
/// None of that holds for a session from three weeks ago. Correcting a mistyped
/// 100 kg to 60 has to be able to take a record BACK; changing a duration has
/// to leave the finished clock alone; and the tonnage the web reads has to be
/// rewritten, or the two clients describe different workouts.
///
/// ── EVERY EDIT GOES THROUGH THE EVENT LOG, INCLUDING A WEB SESSION'S ────────
/// `reproject` DELETES a session's `workout_sets` and rebuilds them from the
/// log. So a direct row edit on a session that HAS events is erased by the next
/// append — and a session that has NO events (every workout logged on the web
/// and pulled down here) would be erased the other way, wholesale, the first
/// time anything appended to it.
///
/// So the log is SEEDED from the projection before the first edit: one `append`
/// per existing row, carrying every column, in the order the rows already sit
/// in. Re-folding reproduces the session byte for byte, and from that moment
/// the invariant `applyPulledSets` states — "a session with events is a session
/// whose sets are a fold over them" — is true of this session too. Which is
/// also what stops the next delta pull from overwriting the edit.
public enum SessionEditing {

    /// What an edit did, and what the caller must do next.
    ///
    /// `date` is the anchor for the cascade: hand it to
    /// `RescoreQueue.request(from:reason:)`. The rescore is deliberately NOT
    /// run in here — it is up to forty-nine day-computations, and a store write
    /// the UI has to wait a second and a half for is a store write nobody uses.
    public struct Outcome: Sendable, Equatable {
        public var sessionId: String
        /// The session's own date — where the cascade starts.
        public var date: String
        public var totalVolumeKg: Double
        public var setCount: Int
        public var prCount: Int
        /// The ledger keys whose records were rebuilt from scratch.
        public var replayed: [String]
    }

    public enum EditError: Error, Equatable {
        case noSuchSession(String)
        case noSuchSet(String)
        /// The logger owns a live session; this API is for finished ones.
        case sessionIsLive(String)
    }

    /// What a session-average heart rate can be and still be one.
    ///
    /// Deliberately absurd at both ends rather than physiologically tight: the
    /// floor is below any resting rate ever recorded and the ceiling is above
    /// any maximum, so the only thing this rejects is a figure nobody could
    /// have measured. It exists because the finish sheet's `+` starts an empty
    /// cell at zero and steps by one — `avg_bpm = 2` is two taps, and it was
    /// stamped measured and therefore permanent.
    public static let plausibleBpm = 25...260
    /// Active energy for one lifting session. The ceiling is a Tour de France
    /// mountain stage; the floor is one minute of standing up.
    public static let plausibleCalories = 5...5000

    /// Σ tonnage and the committed-set count for a session's rows.
    ///
    /// Both are the WEB's definitions, because both columns are the web's:
    /// `sessionVolumeKg` collapses a genuine L/R pair to its weaker side and
    /// skips a ghost; `countCommittedSets` counts each `pair_id` once and every
    /// unpaired row once — warm-ups included, in both. The two treat a pair
    /// differently on purpose, and `save.ts` says so where it calls them.
    public static func totals(_ sets: [WorkoutSet]) -> (volumeKg: Double, count: Int) {
        let volume = SessionVolume.sessionVolumeKg(
            sets.map {
                VolumeSet(
                    weightKg: $0.weightKg, reps: Double($0.reps),
                    // ── `left` HERE, `L` THERE ──────────────────────────────
                    // The store spells a side out; every OnyxCore rule that
                    // folds a pair tests for the one letter. Handed over
                    // unmapped, a pair is scored as two lone sides — silently,
                    // and the tonnage comes out nearly double. Same door
                    // `ScoringInputsBuilder` goes through.
                    side: (try? SyncTranslation.side($0.side)) ?? nil,
                    pairId: $0.pairId, setType: $0.setType
                )
            }
        )
        var paired = Set<String>()
        var solo = 0
        for set in sets {
            if let pairId = set.pairId, !pairId.isEmpty { paired.insert(pairId) } else { solo += 1 }
        }
        return (volume, solo + paired.count)
    }
}

public extension AppDatabase {

    // MARK: - Metrics

    /// The three figures the athlete knows: duration, average heart rate,
    /// active energy. `nil` leaves one alone rather than clearing it — clearing
    /// is not something the sheet can ask for, and inventing the distinction
    /// here would be a state nothing reads.
    ///
    /// ── WHY A TYPED DURATION IS A ONE-WAY DOOR ──────────────────────────────
    /// `closeSession` derives `duration_min` from the clock and the pause
    /// ledger, and it is right to — that arithmetic is why 6 September recorded
    /// 385 minutes. But a person correcting it knows something the clock does
    /// not: that the deck stayed open on the drive home. So a correction sets
    /// `duration_edited` and the close path is then forbidden to re-derive over
    /// it. The flag is LOCAL — see `WorkoutSession.durationEdited`.
    ///
    /// ── THE ONE ENTRY POINT HERE THAT ACCEPTS A LIVE SESSION ───────────────
    /// The set edits refuse one (`edit` throws `sessionIsLive`) because they
    /// would race the deck the athlete is looking at. This does not, and must
    /// not: the finish sheet sets a typed duration on the session it is ABOUT
    /// to close, and that is the whole point of `duration_edited`. It touches
    /// no sets, so there is nothing for the logger to disagree with.
    ///
    /// Returns nil when the id names nothing — the set edits throw there
    /// instead, because a set edit that silently did nothing is a lost
    /// correction, while a metrics write is fire-and-forget from a sheet.
    /// - Parameter measured: whether the figures are the athlete's own answer.
    ///   `true` — the default, and what the finish sheet's steppers and every
    ///   existing caller mean — stamps them measured, which takes the session
    ///   out of `sessionsNeedingMetrics` so a later Health sync cannot replace
    ///   what a person typed. `false` is the finish sheet's PRE-FILL: a figure
    ///   carried over from the previous session of the same split is a good
    ///   default and is not a measurement, so the watch must still be allowed
    ///   to correct it when its workout arrives a day late.
    @discardableResult
    func updateMetrics(
        sessionId: String,
        durationMin: Double? = nil,
        avgBpm: Int? = nil,
        calories: Int? = nil,
        sessionRpe: Double? = nil,
        measured: Bool = true
    ) throws -> SessionEditing.Outcome? {
        try writer.write { db in
            guard var session = try WorkoutSession.fetchOne(db, key: sessionId) else { return nil }
            // ── WHY THE EFFORT IS HERE AND NOT IN `closeSession` ────────────
            // `closeSession` writes it because closing is when it is first
            // asked. Re-opening a finished session for editing (§U4.5) asks
            // again — the dial is the same dial — and closing a session that
            // already ended would rewrite `ended_at` and re-derive a duration
            // over a clock that has not been running for three weeks. Clamped
            // to the CR-10 scale the dial can produce; a keyboard cannot reach
            // this, but `session_rpe` is an ACWR input and every other write to
            // it is clamped.
            if let sessionRpe {
                session.sessionRpe = min(10, max(0, sessionRpe))
            }
            if let durationMin {
                // Clamped, not trusted. A stepper cannot produce a negative and
                // a keyboard can, and `duration_min` is an ACWR input.
                session.durationMin = max(0, durationMin)
                session.durationEdited = true
            }
            // ── CLAMPED, FOR THE SAME REASON THE OTHER TWO ARE ──────────────
            // `session_rpe` and `duration_min` are clamped here because a
            // keyboard can reach them and they are ACWR inputs. These two were
            // not, and a stepper CAN reach them: two taps on `+` from an empty
            // Avg HR cell wrote `avg_bpm = 2` — and stamped it MEASURED, which
            // takes the session out of `sessionsNeedingMetrics` and so forbids
            // the watch from ever correcting it. A figure that survives the one
            // mechanism built to fix it has to be plausible before it lands.
            //
            // The bounds are the widest a human body reaches, not a tight
            // physiological window: rejecting an unusual truth is worse than
            // storing one, and this only has to stop a mis-tap becoming
            // permanent. A value outside them is DROPPED rather than clamped
            // into range — a 2 clamped to 30 is still a number nobody measured,
            // and leaving the column nil is what keeps the session in the
            // Health sync's queue.
            if let avgBpm, SessionEditing.plausibleBpm.contains(avgBpm) {
                session.avgBpm = avgBpm
                session.avgBpmEstimated = !measured
            }
            if let calories, SessionEditing.plausibleCalories.contains(calories) {
                session.caloriesBurned = calories
                session.caloriesEstimated = !measured
            }
            let outcome = try Self.recount(
                db, session: &session, replayed: [],
                authoritative: try Self.holdsSets(db, sessionId: sessionId)
            )
            try session.update(db)
            try Self.enqueueSessionUpsert(sessionId: sessionId, in: db)
            return outcome
        }
    }

    // MARK: - Sets

    /// Change a logged set on a finished session.
    ///
    /// Every argument is optional and `nil` means "leave it": the sheet edits
    /// one field at a time, and a patch carrying the others as nulls would
    /// clear a rating nobody touched. `SetPatch.clearedQuality` is the one
    /// sentinel that takes a value back off — see the field.
    @discardableResult
    /// `est1rmKg` travels with a changed load on purpose: `PrEngine` reads the
    /// STORED estimate with `||` — a value that is present and wrong is not
    /// missing, so it does not fall through to Epley — and the ledger, the
    /// sparkline and the next session's baselines would all keep the estimate of
    /// the weight you just corrected. `setIndex` is here for the same class of
    /// reason: the logger's deck knows a set's position within its exercise and
    /// the patch is the only way to say so.
    func amendSet(
        sessionId: String,
        setId: String,
        weightKg: Double? = nil,
        reps: Int? = nil,
        rpe: Double? = nil,
        setType: String? = nil,
        quality: String? = nil,
        /// `left` / `right` — the LOCAL spelling. See `SetSnapshot.side`.
        side: String? = nil,
        /// The two sides of one physical set share this.
        pairId: String? = nil,
        est1rmKg: Double? = nil,
        setIndex: Int? = nil,
        exerciseOrder: Int? = nil
    ) throws -> SessionEditing.Outcome? {
        let patch = SetPatch(
            setIndex: setIndex, weightKg: weightKg, reps: reps, setType: setType,
            side: side, pairId: pairId,
            est1rmKg: est1rmKg, rpe: rpe, quality: quality, exerciseOrder: exerciseOrder
        )
        // An amend that changes nothing is permanent noise in a log that is
        // never compacted — the rule `EventStore.amendSet` states. Checked HERE
        // rather than inside the transaction because `edit` seeds the event log
        // on the way in, and seeding is a ONE-WAY DOOR: a no-op amend would
        // permanently take a pulled session out of the mirror's reach (see
        // `seedEventLog`) and queue an upload for a session nothing touched.
        //
        // ── AND `isEmpty` IS NOT ENOUGH ─────────────────────────────────────
        // `SetPatch.isEmpty` is "every field is nil", which the logger's own
        // amend can never be: it sends the whole row on every commit, and
        // `ExerciseCardView` commits on every focus LOSS, changed or not. So
        // tapping into a set's weight field to read it and tapping away was a
        // full edit — a seed, a PR replay, a recount, an outbox upsert and a
        // forty-nine-day rescore, for a session nobody had touched, and it took
        // that session permanently out of the mirror's reach. The patch is
        // compared against the row it describes, which is the only check that
        // can tell "I retyped 40" from "I changed 40 to 60".
        guard !patch.isEmpty else { return nil }
        guard try changesSomething(patch, sessionId: sessionId, setId: setId) else { return nil }
        return try edit(sessionId: sessionId) { db, _ in
            guard let existing = try WorkoutSet.fetchOne(db, key: setId), existing.sessionId == sessionId
            else { throw SessionEditing.EditError.noSuchSet(setId) }
            try Self.appendEvent(db, sessionId: sessionId, setId: setId, body: .amend(patch))
            return [existing.exerciseId]
        }
    }

    /// Add a set the logger never captured — the one you did and forgot to tick.
    ///
    /// `snapshot.setIndex` is the position within the exercise. Only the caller
    /// knows the deck, so choosing the next free one is its job.
    @discardableResult
    func addSet(
        sessionId: String,
        _ snapshot: SetSnapshot,
        setId: String = newOnyxID()
    ) throws -> SessionEditing.Outcome? {
        try edit(sessionId: sessionId) { db, _ in
            try Self.appendEvent(db, sessionId: sessionId, setId: setId, body: .append(snapshot))
            return [snapshot.exerciseId]
        }
    }

    /// Remove a set — a tombstone in the log, never a DELETE.
    ///
    /// The event that created it stays, for the reason `voidSet` gives: another
    /// device may not have heard about the deletion, and when its append finally
    /// arrives the tombstone is what stops the set coming back.
    @discardableResult
    func deleteSet(sessionId: String, setId: String) throws -> SessionEditing.Outcome? {
        try edit(sessionId: sessionId) { db, _ in
            guard let existing = try WorkoutSet.fetchOne(db, key: setId), existing.sessionId == sessionId
            else { throw SessionEditing.EditError.noSuchSet(setId) }
            try Self.appendEvent(db, sessionId: sessionId, setId: setId, body: .void)
            return [existing.exerciseId]
        }
    }

    // MARK: - The shape every set edit has

    /// Seed, apply, replay, recount — in ONE transaction.
    ///
    /// ── WHY THE PR REPLAY IS INSIDE IT ──────────────────────────────────────
    /// The same reason `closeSession` puts the recorder inside its own: a
    /// ledger that exists only because a later write succeeded is a ledger that
    /// disappears when it does not. It matters more here, because this write
    /// can RETRACT — a crash between the set edit and the replay would leave a
    /// record standing for a set that no longer exists, and nothing would ever
    /// go looking for it again.
    ///
    /// `apply` returns the `exercise_id`s it touched; they become ledger keys.
    private func edit(
        sessionId: String,
        _ apply: (Database, WorkoutSession) throws -> [String]
    ) throws -> SessionEditing.Outcome? {
        try writer.write { db in
            guard var session = try WorkoutSession.fetchOne(db, key: sessionId) else {
                throw SessionEditing.EditError.noSuchSession(sessionId)
            }
            // A live session belongs to the logger, which appends through
            // `EventStore` and closes through `closeSession`. Editing one here
            // would race the deck the athlete is looking at.
            guard session.endedAt != nil else {
                throw SessionEditing.EditError.sessionIsLive(sessionId)
            }
            // Asked BEFORE the edit: `addSet` on a session whose sets were
            // never mirrored would otherwise leave exactly one row behind and
            // call that the whole workout.
            let held = try Self.holdsSets(db, sessionId: sessionId)
            try Self.seedEventLog(db, sessionId: sessionId)

            let touched = try apply(db, session)
            let name = try PrRecorder.nameResolver(db)
            var replayed: [String] = []
            for key in Set(touched.map(name)).sorted() {
                _ = try PrRecorder.replay(db, userId: session.userId, exerciseKey: key)
                replayed.append(key)
            }
            let outcome = try Self.recount(
                db, session: &session, replayed: replayed, authoritative: held
            )
            try session.update(db)
            try Self.enqueueSessionUpsert(sessionId: sessionId, in: db)
            return outcome
        }
    }

    /// Would applying `patch` produce a different row?
    ///
    /// Read in its own transaction, before `edit` opens the write one. That is
    /// a race in principle — the row could change in between — and it is the
    /// harmless direction: the worst case is one redundant event, which is what
    /// the check exists to reduce and not a correctness claim.
    ///
    /// `SetSnapshot` is the shape the fold applies a patch to, so this asks the
    /// question with exactly the arithmetic `reproject` would use. Missing rows
    /// answer `true` — `amendSet` throws `noSuchSet` inside the transaction and
    /// that error belongs there, not swallowed here as a no-op.
    private func changesSomething(_ patch: SetPatch, sessionId: String, setId: String) throws -> Bool {
        try writer.read { db in
            guard let existing = try WorkoutSet.fetchOne(db, key: setId),
                  existing.sessionId == sessionId
            else { return true }
            let before = SetSnapshot(
                exerciseId: existing.exerciseId,
                setIndex: existing.setIndex,
                weightKg: existing.weightKg,
                reps: existing.reps,
                setType: existing.setType,
                side: existing.side,
                pairId: existing.pairId,
                est1rmKg: existing.est1rmKg,
                rpe: existing.rpe,
                quality: existing.quality,
                exerciseOrder: existing.exerciseOrder
            )
            return patch.applied(to: before) != before
        }
    }

    /// Does this device hold the session's sets?
    ///
    /// ── WHY THE AGGREGATES NEED THE QUESTION ASKED ──────────────────────────
    /// `recount` derives `total_volume_kg` and `set_count` from the rows this
    /// device has, and those columns are then PUSHED. On a session the mirror
    /// has never brought down — the session row arrives before its sets, and a
    /// pull can fail between the two — that is one set of arithmetic over an
    /// empty table, and the answer is a confident zero written over a figure
    /// the web computed correctly from eighteen sets. `encodeIfPresent` cannot
    /// catch it: the value is not unknown, it is wrong.
    ///
    /// So an empty local set list means the aggregates are left ALONE. Deleting
    /// the last set of a session this device does hold is a different case and
    /// still writes zero, which is the truth about it.
    private static func holdsSets(_ db: Database, sessionId: String) throws -> Bool {
        try Int.fetchOne(
            db, sql: "SELECT count(*) FROM workout_sets WHERE session_id = ?", arguments: [sessionId]
        ) ?? 0 > 0
    }

    /// Stamp, commit and reproject one event inside the caller's transaction.
    ///
    /// `appendSet` / `amendSet` / `voidSet` each open their OWN `writer.write`,
    /// and GRDB's writer is not reentrant — calling one from inside this
    /// transaction deadlocks. This is their shared body without the outer
    /// transaction, and it deliberately does not claim the pencil: that lock is
    /// about who is logging a session LIVE, and a session that ended weeks ago
    /// has nobody to take it from.
    private static func appendEvent(
        _ db: Database, sessionId: String, setId: String, body: SetEvent.Body
    ) throws {
        let event = SetEvent(
            sessionId: sessionId,
            setId: setId,
            deviceId: try deviceId(db),
            seq: try tickClock(db),
            body: body
        )
        try commit(event, in: db)
    }

    /// Give a pulled session a log of its own, once.
    ///
    /// One `append` per existing row, in the projection's own order, carrying
    /// every column the snapshot has. Re-folding these reproduces the same rows
    /// with the same ids, so seeding is invisible: `reproject` deletes the
    /// projection and rebuilds it, and what comes back is what was there.
    ///
    /// A session that already has events is left alone — it IS its log.
    ///
    /// ── AND IT IS A ONE-WAY DOOR, PERMANENTLY ───────────────────────────────
    /// `applyPulledSets` skips any session that has events, and it does not
    /// un-skip. So the first edit to a web-logged session takes it out of the
    /// mirror's reach FOREVER, not merely for the pull that might have raced
    /// it: edit a set here, then edit the same session on the web, and this
    /// device keeps its own version with no symptom on either side.
    ///
    /// That is the trade, and it is the right one — the alternative is an edit
    /// this device made being silently overwritten by a pull it did not ask
    /// for — but it is wider than "stops the next delta pull from overwriting
    /// the edit", and a reader deserves to be told which.
    /// Give these sessions a log, if they do not have one, from the rows they
    /// already hold.
    ///
    /// ── WHY THE PULLER NEEDS THIS AND THE EDITOR ALREADY DID ────────────────
    /// `seedEventLog` has been a private step of `editSession` since Wave 2: a
    /// session pulled from the server has rows and no events, and the first
    /// edit has to seed the log or the fold would rebuild the session from the
    /// single event that edit produced — a thirty-set workout collapsing to one.
    ///
    /// The Watch adds the same shape from the other direction. A session can
    /// straddle the day `set_events` was created server-side: the early sets
    /// exist only as rows, the later ones as events. Ingesting the events alone
    /// re-folds the session from the later half and the early sets disappear
    /// from a workout that is complete on the server. Seeding first means the
    /// fold sees all of it.
    ///
    /// Idempotent and cheap: `seedEventLog` returns immediately for any session
    /// that already has an event, which is every session this device logged.
    ///
    /// - Parameter loggedAt: set id → the server's `created_at` for the row,
    ///   when the caller has it (the puller does). See `seedEventLog`.
    func seedEventLogs(sessionIds: Set<String>, loggedAt: [String: Date] = [:]) throws {
        guard !sessionIds.isEmpty else { return }
        try writer.write { db in
            for sessionId in sessionIds.sorted() {
                try Self.seedEventLog(db, sessionId: sessionId, loggedAt: loggedAt)
            }
        }
    }

    /// ── A SEED IS NOT A LOGGING ACT, AND ITS CLOCK MUST NOT SAY IT WAS ──────
    /// `closeSession` reads "when was the last set logged" off the append
    /// events' `created_at`, and `SessionDuration`'s long-idle guard turns
    /// that into the answer. Seeds used to be stamped with `Date()` — the
    /// moment of the SEED — so a session pulled from the server and finished
    /// on the phone was judged against a last set that happened at pull time.
    /// Seeded as the session opened and closed later, `worked ≈ 0`, the guard
    /// fired, and the duration came out as one rest: Pec Deck's 120 s, 2 min.
    ///
    /// The seed now carries the set's own clock: the server's `created_at`
    /// when the caller pulled it (`RemoteSetRow.createdAt`), else the
    /// session's start — the earliest instant the row can honestly claim, and
    /// one that never outranks a set this device goes on to log.
    static func seedEventLog(_ db: Database, sessionId: String, loggedAt: [String: Date] = [:]) throws {
        let existing = try Int.fetchOne(
            db, sql: "SELECT count(*) FROM set_events WHERE session_id = ?", arguments: [sessionId]
        ) ?? 0
        guard existing == 0 else { return }

        let rows = try WorkoutSet
            .filter(Column("session_id") == sessionId)
            .order(Column("set_index"), Column("fold_order"), Column("rowid"))
            .fetchAll(db)
        guard !rows.isEmpty else { return }

        let fallback = try WorkoutSession.fetchOne(db, key: sessionId)?.startedAt ?? Date()
        let device = try deviceId(db)
        for row in rows {
            let event = SetEvent(
                sessionId: sessionId,
                setId: row.id,
                deviceId: device,
                seq: try tickClock(db),
                createdAt: loggedAt[row.id] ?? fallback,
                body: .append(
                    SetSnapshot(
                        exerciseId: row.exerciseId,
                        setIndex: row.setIndex,
                        weightKg: row.weightKg,
                        reps: row.reps,
                        setType: row.setType,
                        side: row.side,
                        pairId: row.pairId,
                        est1rmKg: row.est1rmKg,
                        rpe: row.rpe,
                        quality: row.quality,
                        // Carried, not re-derived. A pulled session's rows come
                        // down with the web's own order on them, and seeding is
                        // supposed to reproduce the session byte for byte —
                        // dropping it here would blank the column on the first
                        // edit of every workout logged on the other client.
                        exerciseOrder: row.exerciseOrder,
                        // Same argument, three more columns: a treadmill set
                        // pulled from the server is five minutes at incline 2
                        // for 0.37 km, and a seed that drops those re-renders
                        // it as `0kg × 0` on the first edit of the session.
                        durationSec: row.durationSec,
                        incline: row.incline,
                        distanceKm: row.distanceKm,
                        elevationM: row.elevationM,
                        // Carried for the same reason, with one difference: a
                        // seed is built from rows the SERVER holds, and the
                        // server does not hold this column — so in practice
                        // this is nil here and stays nil. It is passed anyway
                        // because the day a local-first session is re-seeded
                        // (a repair, an adoption) the measurement is on the row
                        // and dropping it would erase it on the first edit.
                        actualRestSec: row.actualRestSec
                    )
                )
            )
            try event.insert(db)
            // ── BORN SYNCED, LIKE A CLOCK EVENT ─────────────────────────────
            // These describe rows the server ALREADY HAS — that is where they
            // came from. Left unsynced they would queue an upsert per set on
            // the next drain, re-pushing an untouched session; and `reproject`
            // reads `is_synced` to decide `is_pending_sync`, so the whole
            // session would render as awaiting upload. The edit that follows
            // writes its own event, and THAT one syncs.
            try db.execute(
                sql: "UPDATE set_events SET is_synced = 1 WHERE id = ?", arguments: [event.id]
            )
        }
        try reproject(sessionId: sessionId, in: db)

        // ── A SEED IS NOT AN EDIT, AND A CANCEL MUST NOT UNDO ONE ───────────
        // `markEditStart` records where this device's log STOOD when the editor
        // opened, and on a web-logged session it stood nowhere: there was no
        // log until the first edit ran this. The seed then stamps one `append`
        // per existing row from `tickClock`, so every one of them lands ABOVE
        // the mark — and `revertPlan`, which excludes this device's post-mark
        // events, folded an empty array and concluded the whole session was
        // this sitting's work. Cancel emptied the workout.
        //
        // Pushing the mark past the seed says what was always meant: these
        // events describe rows that were already there. Nothing else can be
        // above the mark yet — `edit` seeds BEFORE it applies — so this can
        // only ever skip the restatement, never a real edit. A session that
        // already has a log returns above and the mark is left alone.
        if try editMark(db, sessionId: sessionId) != nil {
            try writeEditMark(db, sessionId: sessionId, replacing: true)
        }
    }

    /// Recompute the session's stored aggregates from its rows, and report.
    ///
    /// `pr_count` is the SESSION's number — distinct axis-PRs across every
    /// exercise in it — which is not the count of ledger rows a replay wrote
    /// for one of them. Recomputed over the whole session so it agrees with
    /// what the web would write for these rows.
    private static func recount(
        _ db: Database, session: inout WorkoutSession, replayed: [String],
        authoritative: Bool
    ) throws -> SessionEditing.Outcome {
        let sets = try WorkoutSet
            .filter(Column("session_id") == session.id)
            .order(Column("set_index"), Column("fold_order"))
            .fetchAll(db)
        let totals = SessionEditing.totals(sets)
        let prCount = try PrRecorder.prCount(
            db, sets: sets, dayKey: session.dayKey, date: session.date
        )
        // Not ours to state — see `holdsSets`. The columns keep whatever the
        // client that DID hold the sets last wrote, and the outcome still
        // reports what this device can see so a caller is not left guessing.
        if authoritative {
            session.totalVolumeKg = totals.volumeKg
            session.setCount = totals.count
            session.prCount = prCount
        }
        return SessionEditing.Outcome(
            sessionId: session.id, date: session.date,
            totalVolumeKg: totals.volumeKg, setCount: totals.count,
            prCount: prCount, replayed: replayed
        )
    }
}

// MARK: - Cancelling an edit

public extension SessionEditing {

    /// Where an edit began.
    ///
    /// "Every event THIS device wrote for this session above `seq`" — see
    /// `v29.sessionEditMarks` for why the pair, and why neither half alone
    /// would do. It is persisted, so a crash mid-edit does not take the ability
    /// to cancel with it.
    struct Watermark: Sendable, Equatable {
        public var sessionId: String
        public var deviceId: String
        public var seq: Int64

        public init(sessionId: String, deviceId: String, seq: Int64) {
            self.sessionId = sessionId
            self.deviceId = deviceId
            self.seq = seq
        }
    }

    /// One compensating event a revert has to write.
    ///
    /// Three kinds, because `SetEventFold` only has three verbs and a revert is
    /// written in the same language as the edit it undoes — never by deleting
    /// rows from the log. Deleting them would be undone by the very next pull:
    /// `TrainingPuller.ingestRemoteEvents` re-fetches this session's events
    /// from the server and `AppDatabase.ingest` de-duplicates by event id, so
    /// an event this device removed locally and had already pushed simply comes
    /// back. Compensating events survive that, because the server has them too.
    enum RevertStep: Sendable, Equatable {
        /// The edit brought this set into existence. Tombstone it.
        case void(setId: String)
        /// A patch puts this set back exactly. Cheapest, and it keeps the id.
        case amend(setId: String, patch: SetPatch)
        /// The edit VOIDED this set, and `SetEventFold`'s rule 3 is terminal —
        /// so it comes back under a **new** id. See `revertPlan`.
        case restore(SetSnapshot)
    }

    /// What it would take to put this session back, and which ledger keys move.
    struct RevertPlan: Sendable, Equatable {
        public var steps: [RevertStep] = []
        /// `exercise_id`s, for the PR replay. Sorted, so a plan is comparable.
        public var touched: [String] = []
        public var isEmpty: Bool { steps.isEmpty }
    }

    /// Diff the session as it is against the session as it was, and say what to
    /// write. **Pure** — no database, no clock, no ids minted. `SetEventFold`
    /// is pure for the same reason, and this is the other half of that bargain:
    /// the awkward orderings are testable in microseconds.
    ///
    /// ── THE TARGET IS A FOLD WITH A HOLE IN IT ──────────────────────────────
    /// `SetEventFold.sets` takes an array, so "the session without this
    /// sitting's edits" is just that array minus this device's post-watermark
    /// events. Another device's events stay in — all of them, at any `seq` —
    /// which is the whole reason the watermark is a pair. A watch that logged
    /// set 4 while you were correcting set 2 keeps set 4.
    ///
    /// ── WHY A RESTORED SET GETS A NEW ID, AND WHY THAT IS SAFE ──────────────
    /// Rule 3 of the fold is that a `void` is TERMINAL and wins even when it
    /// arrives first — a voided `setId` can never be appended again, by design,
    /// because a partially-synced log must not resurrect deleted sets. So there
    /// is no compensating event that restores a set under its own id, and
    /// weakening the rule to make one would break the property it protects.
    ///
    /// The id therefore changes, and the SERVER agrees anyway.
    /// `SyncEngine.push` reconciles each queued event against the local
    /// projection: an event whose `setId` the fold no longer holds becomes
    /// `remote.deleteSets([id])` (`Sync/SyncEngine.swift:305-310`). The edit's
    /// own `void` is an outbox item naming the old id, and it is still there —
    /// either queued, in which case the next drain deletes the server row, or
    /// already drained, in which case it deleted it then. Either way the stale
    /// row does not survive, and the restored one uploads under the new id from
    /// its own `append`. Nothing keys on a set id but the set: the PR ledger is
    /// keyed `(user_id, exercise_key, axis)` and references a SESSION, never a
    /// set.
    ///
    /// The cost is real and small: a restored set moves to the end of its
    /// `setIndex` tie group, because rule 5 breaks a tie on first appearance
    /// and a re-append is a new arrival. That is why the walk below is in
    /// TARGET order — it keeps restored sets in the order they had relative to
    /// each other.
    static func revertPlan(
        events: [SetEvent], sessionId: String, mark: Watermark
    ) -> RevertPlan {
        let current = SetEventFold.sets(from: events, sessionId: sessionId)
        let target = SetEventFold.sets(
            from: events.filter { !($0.deviceId == mark.deviceId && $0.seq > mark.seq) },
            sessionId: sessionId
        )
        let byId = { (sets: [WorkoutSet]) in
            Dictionary(sets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        let targetById = byId(target)
        let currentById = byId(current)

        var plan = RevertPlan()
        var touched: Set<String> = []

        // Anything the edit ADDED. Order is irrelevant — a tombstone is
        // terminal wherever it lands.
        for set in current where targetById[set.id] == nil {
            plan.steps.append(.void(setId: set.id))
            touched.insert(set.exerciseId)
        }

        // Then the target in its OWN fold order, so a set that has to be
        // re-appended arrives in the position it held.
        for want in target {
            let wanted = SetSnapshot(want)
            guard let have = currentById[want.id] else {
                plan.steps.append(.restore(wanted))
                touched.insert(want.exerciseId)
                continue
            }
            let held = SetSnapshot(have)
            guard held != wanted else { continue }
            touched.insert(want.exerciseId)
            touched.insert(have.exerciseId)
            if let patch = restoringPatch(to: wanted, from: held) {
                plan.steps.append(.amend(setId: want.id, patch: patch))
            } else {
                // ── A PATCH IS NOT ALWAYS ENOUGH, AND IT SAYS SO ────────────
                // `SetPatch` reads `nil` as UNCHANGED for every field but
                // `quality`, so it cannot put a `side`, a `pairId` or an `rpe`
                // back to null; and it has no `duration_sec`, `incline`,
                // `distance_km`, `elevation_m` or `actual_rest_sec` at all,
                // though `SetSnapshot` does. An amend back to a treadmill row's
                // pre-edit state is therefore LOSSY, silently. Void and
                // re-append is the honest way to say "that never happened" —
                // which is the advice `SetPatch`'s own doc comment gives.
                plan.steps.append(.void(setId: want.id))
                plan.steps.append(.restore(wanted))
            }
        }

        plan.touched = touched.sorted()
        return plan
    }

    /// The patch that turns `have` back into `want`, or nil when no patch can.
    ///
    /// Deliberately MAXIMAL — every patchable field is set from the target,
    /// changed or not — and then checked by applying it. That is the only way
    /// to ask "can a patch express this?" that cannot drift from what the fold
    /// would actually do: the answer comes from `SetPatch.applied`, the same
    /// function `reproject` runs, rather than from a hand-maintained list of
    /// which fields `SetPatch` happens to carry this month. Add a field to
    /// `SetSnapshot` and this keeps telling the truth with no edit.
    ///
    /// A maximal patch is also what the logger already writes — it sends the
    /// whole row on every commit — so this adds no shape the log has not had.
    private static func restoringPatch(to want: SetSnapshot, from have: SetSnapshot) -> SetPatch? {
        let patch = SetPatch(
            setIndex: want.setIndex,
            weightKg: want.weightKg,
            reps: want.reps,
            setType: want.setType,
            side: want.side,
            pairId: want.pairId,
            est1rmKg: want.est1rmKg,
            rpe: want.rpe,
            // The sentinel, not nil: `nil` means UNCHANGED, so withdrawing a
            // quality the edit added is the one clearing a patch CAN express.
            quality: want.quality ?? SetPatch.clearedQuality,
            exerciseOrder: want.exerciseOrder
        )
        return patch.applied(to: have) == want ? patch : nil
    }
}

extension SetSnapshot {
    /// A projected row, read back as the snapshot it came from.
    ///
    /// The inverse of the map at the bottom of `SetEventFold.sets`, and it has
    /// to carry every axis that one does — a comparison that quietly omits
    /// `duration_sec` would call an edited treadmill bout unchanged and leave
    /// it edited through a Cancel.
    init(_ set: WorkoutSet) {
        self.init(
            exerciseId: set.exerciseId,
            setIndex: set.setIndex,
            weightKg: set.weightKg,
            reps: set.reps,
            setType: set.setType,
            side: set.side,
            pairId: set.pairId,
            est1rmKg: set.est1rmKg,
            rpe: set.rpe,
            quality: set.quality,
            exerciseOrder: set.exerciseOrder,
            durationSec: set.durationSec,
            incline: set.incline,
            distanceKm: set.distanceKm,
            elevationM: set.elevationM,
            actualRestSec: set.actualRestSec
        )
    }
}

public extension AppDatabase {

    /// Open an edit sitting: remember where this device's log stands.
    ///
    /// Call it once, as the editor attaches. **It does not move an existing
    /// mark**, and that is not a convenience — it is the crash case. An app
    /// killed mid-edit never got to clear its mark, so re-opening the editor
    /// finds it and Cancel can still reach back past the crash to where the
    /// edit actually began. Re-entrancy falls out of the same rule: a second
    /// `attach` in one sitting cannot silently shrink the window.
    ///
    /// A mark left by a DIFFERENT device id is replaced rather than kept — it
    /// can only come from a store restored under a new install, where the seq
    /// it names belongs to a clock this device has never run.
    @discardableResult
    func markEditStart(sessionId: String) throws -> SessionEditing.Watermark {
        try writer.write { db in try Self.writeEditMark(db, sessionId: sessionId, replacing: false) }
    }

    /// The mark as stored. Nil once the sitting was saved, left or reverted.
    func editMark(sessionId: String) throws -> SessionEditing.Watermark? {
        try writer.read { db in try Self.editMark(db, sessionId: sessionId) }
    }

    /// Close the sitting without undoing it — Save, and the chevron.
    ///
    /// The chevron matters as much as Save does. Leaving with the changes KEPT
    /// and the mark standing would mean the next sitting's Cancel reverts this
    /// one too, silently, weeks later.
    func clearEditMark(sessionId: String) throws {
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM session_edit_marks WHERE session_id = ?", arguments: [sessionId]
            )
        }
    }

    /// Cancel: put the session back to where the mark says it was.
    ///
    /// Returns nil when there is nothing to undo — no mark, or a sitting that
    /// changed nothing. Nil is not a failure, and the caller should still close
    /// the screen on it.
    ///
    /// ── WHY THE EMPTY CASE IS CHECKED OUTSIDE THE TRANSACTION ───────────────
    /// `edit` SEEDS the event log on the way in, and seeding is a one-way door:
    /// it takes a web-logged session permanently out of the mirror's reach (see
    /// `seedEventLog`). Cancelling out of an editor that was opened and touched
    /// nothing must not do that, and must not queue an upload for a session
    /// nothing changed. The pre-check is one COUNT, not a fold — the PLAN is
    /// still computed inside the write transaction, off the log as it stands
    /// there, so nothing that lands in between is planned against a stale read.
    ///
    /// Everything else — the seed, the compensating events, the PR replay, the
    /// recount and the outbox upsert — is `edit`'s existing envelope, in ONE
    /// transaction. A revert that half-happened is a session no reader could
    /// describe.
    @discardableResult
    func revertSessionEdits(sessionId: String) throws -> SessionEditing.Outcome? {
        let worthDoing = try writer.read { db -> Bool in
            guard let mark = try Self.editMark(db, sessionId: sessionId) else { return false }
            // `kind` is filtered because `pause` / `resume` are in this log too
            // and change no set. A sitting whose only event was a clock tick
            // has nothing to revert, and running the envelope for it would seed
            // a pulled session for nothing.
            return try Int.fetchOne(db, sql: """
                SELECT count(*) FROM set_events
                WHERE session_id = ? AND device_id = ? AND seq > ?
                  AND kind IN ('append', 'amend', 'void')
                """, arguments: [sessionId, mark.deviceId, mark.seq]) ?? 0 > 0
        }
        guard worthDoing else {
            try clearEditMark(sessionId: sessionId)
            return nil
        }

        return try edit(sessionId: sessionId) { db, _ in
            guard let mark = try Self.editMark(db, sessionId: sessionId) else { return [] }
            let events = try SetEvent
                .filter(SetEvent.Columns.sessionId == sessionId)
                .fetchAll(db)
            let plan = SessionEditing.revertPlan(events: events, sessionId: sessionId, mark: mark)
            for step in plan.steps {
                switch step {
                case .void(let setId):
                    try Self.appendEvent(db, sessionId: sessionId, setId: setId, body: .void)
                case .amend(let setId, let patch):
                    try Self.appendEvent(db, sessionId: sessionId, setId: setId, body: .amend(patch))
                case .restore(let snapshot):
                    try Self.appendEvent(
                        db, sessionId: sessionId, setId: newOnyxID(), body: .append(snapshot)
                    )
                }
            }
            // ── RE-MARKED AT THE CLOCK AS IT NOW STANDS ────────────────────
            // Two things need this. A second Cancel must be a no-op rather than
            // a diff between the restored session and itself — which, because a
            // restored set carries a new id, would void and re-append it again
            // and churn ids forever. And the screen stays open long enough for
            // the reader to keep editing, which should still be cancellable.
            _ = try Self.writeEditMark(db, sessionId: sessionId, replacing: true)
            return plan.touched
        }
    }

    // MARK: - The mark, in SQL

    internal static func editMark(
        _ db: Database, sessionId: String
    ) throws -> SessionEditing.Watermark? {
        try Row.fetchOne(
            db,
            sql: "SELECT device_id, seq FROM session_edit_marks WHERE session_id = ?",
            arguments: [sessionId]
        ).map {
            SessionEditing.Watermark(
                sessionId: sessionId, deviceId: $0["device_id"], seq: $0["seq"]
            )
        }
    }

    @discardableResult
    internal static func writeEditMark(
        _ db: Database, sessionId: String, replacing: Bool
    ) throws -> SessionEditing.Watermark {
        let device = try deviceId(db)
        if !replacing, let existing = try editMark(db, sessionId: sessionId),
           existing.deviceId == device {
            return existing
        }
        // The clock is READ, never ticked. `tickClock` hands out a stamp for an
        // event that is about to be written, and a mark is not an event — one
        // taken by ticking would leave a gap in the log's numbering per editor
        // opened, and (worse) would sit one above the last real event, so the
        // first edit of the sitting would fall on the boundary rather than
        // above it.
        let seq = try Int64.fetchOne(
            db, sql: "SELECT lamport FROM device_state WHERE row_id = 'local'"
        ) ?? 0
        try db.execute(
            sql: """
                INSERT INTO session_edit_marks (session_id, device_id, seq) VALUES (?, ?, ?)
                ON CONFLICT(session_id) DO UPDATE SET
                    device_id = excluded.device_id, seq = excluded.seq
                """,
            arguments: [sessionId, device, seq]
        )
        return SessionEditing.Watermark(sessionId: sessionId, deviceId: device, seq: seq)
    }
}
