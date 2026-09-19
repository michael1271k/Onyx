import Foundation
import GRDB

// MARK: - Device identity and the logical clock

/// A session's pause ledger, before anything decides what it is worth.
public struct PauseLedger: Sendable, Equatable {
    /// Seconds from pauses that have CLOSED. Bounded by construction.
    public var banked: TimeInterval
    /// When the pause in progress began, or nil while the clock is running.
    /// UNBOUNDED — it grows with the wall clock and may be days old.
    public var openedAt: Date?

    public init(banked: TimeInterval = 0, openedAt: Date? = nil) {
        self.banked = banked
        self.openedAt = openedAt
    }
}

extension AppDatabase {

    /// This install's device id, created on first use and stable thereafter.
    ///
    /// Deliberately **not** `identifierForVendor`: that value changes when the
    /// last app from a vendor is deleted and reinstalled, and it is unavailable
    /// early in launch. A device id that can change would split one device's
    /// history into two participants in the merge, and the fold's tiebreak would
    /// start giving different answers on either side of a reinstall.
    public func deviceId() throws -> String {
        try writer.write { db in try Self.deviceId(db) }
    }

    static func deviceId(_ db: Database) throws -> String {
        if let existing = try String.fetchOne(
            db, sql: "SELECT device_id FROM device_state WHERE row_id = 'local'"
        ) {
            return existing
        }
        let fresh = newOnyxID()
        try db.execute(
            sql: "INSERT INTO device_state (row_id, device_id, lamport) VALUES ('local', ?, 0)",
            arguments: [fresh]
        )
        return fresh
    }

    /// Stamp a locally-produced event: advance the clock and hand back the value.
    ///
    /// Runs inside the caller's transaction on purpose. If the clock advanced
    /// and the event that used the value failed to insert, the next event would
    /// skip a number — harmless — but if the event inserted and the clock did
    /// not advance, two events would share a stamp and the merge would have to
    /// guess. Same transaction, so neither can happen.
    static func tickClock(_ db: Database) throws -> Int64 {
        _ = try deviceId(db)   // ensures the row exists
        try db.execute(sql: "UPDATE device_state SET lamport = lamport + 1 WHERE row_id = 'local'")
        guard let stamp = try Int64.fetchOne(
            db, sql: "SELECT lamport FROM device_state WHERE row_id = 'local'"
        ) else {
            // Defaulting to 1 here would hand out a stamp that has almost
            // certainly been used already, silently collapsing two causally
            // ordered events onto the fold's tiebreak. A missing device_state
            // row is not a recoverable condition; it is a corrupt store.
            throw EventStoreError.clockUnavailable
        }
        return stamp
    }

    /// Take account of an event produced elsewhere. Never decreases.
    static func observeClock(_ db: Database, _ remote: Int64) throws {
        _ = try deviceId(db)
        try db.execute(
            sql: "UPDATE device_state SET lamport = MAX(lamport, ?) WHERE row_id = 'local'",
            arguments: [remote]
        )
    }

    /// The current Lamport value. Test and diagnostic use.
    public func clockValue() throws -> Int64 {
        try writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT lamport FROM device_state WHERE row_id = 'local'") ?? 0
        }
    }
}

// MARK: - Writing sets

extension AppDatabase {

    /// Log a set.
    ///
    /// Everything below funnels through `record`, so there is exactly one code
    /// path that appends a fact, enqueues its sync and rebuilds the projection —
    /// and it does all three in one transaction. A set that exists on the phone
    /// but never reaches the queue is training history lost with no symptom, so
    /// the two cannot be allowed to come apart.
    @discardableResult
    public func appendSet(
        sessionId: String,
        setId: String = newOnyxID(),
        _ snapshot: SetSnapshot
    ) throws -> SetEvent {
        try record(sessionId: sessionId, setId: setId, body: .append(snapshot))
    }

    /// Change some fields of a set already logged.
    ///
    /// An empty patch is rejected rather than written: an event that changes
    /// nothing is permanent noise in a log that is never compacted.
    @discardableResult
    public func amendSet(
        sessionId: String,
        setId: String,
        _ patch: SetPatch
    ) throws -> SetEvent {
        guard !patch.isEmpty else { throw EventStoreError.emptyPatch }
        return try record(sessionId: sessionId, setId: setId, body: .amend(patch))
    }

    /// Stop the session clock, and start it again.
    ///
    /// Idempotent in the only way that matters: pausing an already-paused
    /// session appends a second `pause`, and `pausedSeconds` counts from the
    /// FIRST of a run — so a double tap, or two devices pausing at once, cannot
    /// bank the same minutes twice.
    @discardableResult
    public func pauseSession(_ sessionId: String) throws -> SetEvent {
        try record(sessionId: sessionId, setId: sessionId, body: .pause)
    }

    @discardableResult
    public func resumeSession(_ sessionId: String) throws -> SetEvent {
        try record(sessionId: sessionId, setId: sessionId, body: .resume)
    }

    /// True when the session's clock is currently stopped.
    public func isPaused(sessionId: String) throws -> Bool {
        try pauseLedger(sessionId: sessionId).openedAt != nil
    }

    /// The pause ledger, SPLIT — what has closed, and when the open one began.
    ///
    /// ── WHY THE SPLIT IS THE WHOLE POINT ────────────────────────────────────
    /// `pausedSeconds` folds the two together and hands back one number, and a
    /// caller holding one number cannot tell a genuine 40-minute pause from a
    /// pause that was never closed because iOS terminated the app. The second
    /// grows at wall-clock rate for as long as the phone is away, and the
    /// logger imported it whole: `pausedTotal` passed the wall interval,
    /// `timerOrigin` went into the future, and `PauseControlling.elapsed`
    /// clamped that to a confident `0:00` on a session that was fully intact.
    ///
    /// `SessionRun.resolve` is what decides what an OPEN pause is worth. It
    /// needs to see it separately to do that, so this is the read the deck uses
    /// and `pausedSeconds` is the one the close uses.
    public func pauseLedger(sessionId: String) throws -> PauseLedger {
        try Self.pauseLedger(setEvents(sessionId: sessionId))
    }

    /// How long the session has been paused for, in seconds, as of `now`.
    ///
    /// ── ORDERED BY THE LAMPORT CLOCK, MEASURED BY THE WALL CLOCK ────────────
    /// `SetEvent` is emphatic that `createdAt` is for display and must never be
    /// sorted by, and this does not sort by it: the order is `(seq, deviceId,
    /// id)` like every other fold. But a Lamport clock has no duration, so the
    /// LENGTH of a pause can only come from the wall clock, and the difference
    /// between two stamps written by the same device minutes apart is the one
    /// thing it is reliable for. A pair that comes out negative (an NTP step
    /// mid-pause) contributes zero rather than shortening the session.
    public func pausedSeconds(sessionId: String, now: Date = Date()) throws -> TimeInterval {
        try Self.pausedSeconds(setEvents(sessionId: sessionId), now: now)
    }

    /// ONE fold, two readings. `isPaused` and `pausedSeconds` were two walks
    /// over the same events answering two halves of one question, and they
    /// could disagree — `isPaused` took the LAST clock event while this counts
    /// runs from the FIRST pause of each, so a `pause, pause, resume` sequence
    /// read as running with an interval still open.
    static func pauseLedger(_ events: [SetEvent]) -> PauseLedger {
        var banked: TimeInterval = 0
        var openedAt: Date?
        for event in ordered(events) where event.kind.isClock {
            switch event.kind {
            case .pause:
                // Only the FIRST pause of a run opens the interval.
                if openedAt == nil { openedAt = event.createdAt }
            case .resume:
                if let start = openedAt { banked += max(0, event.createdAt.timeIntervalSince(start)) }
                openedAt = nil
            default:
                break
            }
        }
        return PauseLedger(banked: banked, openedAt: openedAt)
    }

    static func isPaused(_ events: [SetEvent]) -> Bool { pauseLedger(events).openedAt != nil }

    static func pausedSeconds(_ events: [SetEvent], now: Date) -> TimeInterval {
        let ledger = pauseLedger(events)
        guard let start = ledger.openedAt else { return ledger.banked }
        return ledger.banked + max(0, now.timeIntervalSince(start))
    }

    /// The total order the fold uses — `(seq, deviceId, id)`, never wall time.
    private static func ordered(_ events: [SetEvent]) -> [SetEvent] {
        events.sorted { lhs, rhs in
            if lhs.seq != rhs.seq { return lhs.seq < rhs.seq }
            if lhs.deviceId != rhs.deviceId { return lhs.deviceId < rhs.deviceId }
            return lhs.id < rhs.id
        }
    }

    /// Delete a set — by appending a tombstone, never by deleting anything.
    ///
    /// The event that created the set stays in the log. That is the point: the
    /// other device may not have heard about the deletion yet, and when its
    /// append finally arrives the tombstone is what stops the set coming back.
    @discardableResult
    public func voidSet(sessionId: String, setId: String) throws -> SetEvent {
        try record(sessionId: sessionId, setId: setId, body: .void)
    }

    private func record(
        sessionId: String,
        setId: String,
        body: SetEvent.Body
    ) throws -> SetEvent {
        try writer.write { db in
            // Starting to log claims the pencil; logging while another device
            // holds it is refused. `ingest` is deliberately NOT guarded — a
            // remote event is a fact that already happened, and refusing it
            // would lose a set to enforce a UI rule.
            try Self.claimPencil(db, sessionId: sessionId, force: false)

            // ── THE ROWS THIS SESSION ALREADY HAS BECOME EVENTS FIRST ───────
            // A session can hold `workout_sets` and NO events: that is exactly
            // what `TrainingPuller.applyPulledSets` produces for a workout this
            // device did not log. `reproject` below rebuilds the table from the
            // fold, so the first append into such a session would rewrite a
            // thirty-set workout as one set — silently, and in the direction the
            // whole event log exists to make impossible.
            //
            // `SessionEditing.editSession` has seeded for this reason since Wave
            // 2. It belongs HERE, in the one funnel every append, amend and void
            // passes through, because the Watch reaches the same state by a
            // different road: it adopts the live session the phone opened, and
            // then logs into it. A guard at one call site leaves the siblings
            // broken.
            //
            // A no-op for every session that has an event already, which is
            // every session either device logged — one indexed COUNT per write.
            try Self.seedEventLog(db, sessionId: sessionId)

            let device = try Self.deviceId(db)
            let event = SetEvent(
                sessionId: sessionId,
                setId: setId,
                deviceId: device,
                seq: try Self.tickClock(db),
                body: body
            )
            try Self.commit(event, in: db)
            return event
        }
    }

    /// Insert one event, queue it, and rebuild the session's projection.
    /// Assumes it is already inside a write transaction.
    static func commit(_ event: SetEvent, in db: Database) throws {
        try event.insert(db)

        // ── A CLOCK EVENT NEVER LEAVES THE DEVICE ───────────────────────────
        // `set_events` is local-only and the drainer reconciles ROWS: it looks
        // each queued event's `setId` up in the projection and, finding
        // nothing, tells the server to delete that id (`SyncEngine`, the
        // `projected[setId]` miss). A pause carries the SESSION's id there, so
        // queueing one would send a delete for an id that is not a set — a
        // harmless no-op on the server and a request per pause for nothing.
        // What the server needs from a pause is `duration_min`, which
        // `closeSession` computes and the session upsert carries.
        guard !event.kind.isClock else {
            // ── AND IT IS BORN SYNCED ───────────────────────────────────────
            // `is_synced` starts 0 and is only ever set by the outbox ack or by
            // `ingest`, neither of which a clock event reaches — so it would sit
            // at 0 for the life of the row. `LiveSessionOwner.meActive` reads
            // "I own this session AND I have unsynced events" as "this device
            // is actively logging" and refuses the watch an implicit takeover
            // on the strength of it. One pause would make that true forever:
            // put the phone down, pick up the watch, and every append there is
            // refused until somebody presses *Log here*. A row that is
            // local-only by design has nowhere to sync TO, so it is already as
            // synced as it will ever be.
            try db.execute(
                sql: "UPDATE set_events SET is_synced = 1 WHERE id = ?", arguments: [event.id]
            )
            // No `reproject`: `SetEventFold` skips these kinds, so the
            // projection is provably unchanged and re-folding the whole log —
            // and rewriting every `workout_sets` row for the session — on each
            // pause tap buys nothing.
            return
        }

        var item = OutboxItem(
            kind: "set_event.\(event.kind.rawValue)",
            payload: try OnyxJSON.encoder.encode(event),
            // Events are immutable and uniquely identified, so the key is the
            // event itself. That makes a retry a true no-op — unlike the
            // row-upsert scheme it replaces, where a retry had to guess whether
            // the payload it held was still the current one.
            idempotencyKey: "set_event:\(event.id)"
        )
        try item.insert(db)

        try reproject(sessionId: event.sessionId, in: db)
    }

    /// Accept events produced by another device.
    ///
    /// Used by the Watch link and by the pull side of Supabase sync. Three
    /// things have to happen and all three are here:
    ///
    /// 1. Duplicates are ignored — the same event can legitimately arrive twice,
    ///    over two transports.
    /// 2. The local clock takes account of what it has seen, so this device's
    ///    next event stamps strictly above anything it is replying to.
    /// 3. Remote events are **not** queued for upload. They came from elsewhere;
    ///    echoing them back is how a sync loop starts.
    /// - Parameter mirror: the events came down from the server (the puller).
    ///   Raises the rescore door's mirror mark for the transaction, so the
    ///   reprojection is read as a pull and not as an edit. The watch bridge
    ///   goes through `ingestFromWatch` instead: a set logged on the wrist IS
    ///   this device family's edit, and a past-dated one owes the cascade.
    public func ingest(_ events: [SetEvent], mirror: Bool = false) throws {
        guard !events.isEmpty else { return }
        try writer.write { db in
            if mirror {
                try Self.markMirrorWrite(db) { _ = try Self.ingest(db, events) }
            } else {
                _ = try Self.ingest(db, events)
            }
        }
    }

    /// Accept events from the paired watch — merged like `ingest`, QUEUED like
    /// this phone's own (W2, decision 15).
    ///
    /// ── THE STRAND ──────────────────────────────────────────────────────────
    /// `ingest` marks what it takes as synced, because an event that arrived
    /// over the network must not be echoed back. A watch event did NOT arrive
    /// over the network: the watch holds no Supabase session, and this phone
    /// is its only road (`PhoneWatchBridge`'s header). Marked synced and never
    /// queued, a set logged on the wrist reached the server only when this
    /// phone next happened to touch the same session — which, for a workout
    /// finished on the watch, was never.
    ///
    /// ── AND WHY NOT A SESSION UPSERT ────────────────────────────────────────
    /// The plan said "re-queue the session upsert". A `session.upsert` item
    /// carries the session ROW and nothing else — `SyncEngine.push` sends a
    /// set only for a queued SET EVENT naming it — and a forced session row
    /// from the phone could write `ended_at: null` over a finish the phone
    /// has not heard about yet, the exact overwrite `push`'s own comment
    /// forbids. So the wrist's events go through `commit`, the same door this
    /// device's ticks go through: inserted unsynced, one outbox row each,
    /// and the projection rebuilt — all in one transaction. The event ensures
    /// its parent session exists on the server (`ON CONFLICT DO NOTHING`) and
    /// carries the set; `ingest`'s de-duplication by event id keeps a re-sent
    /// transfer harmless.
    public func ingestFromWatch(_ events: [SetEvent]) throws {
        guard !events.isEmpty else { return }
        try writer.write { db in
            for event in events.map(\.normalisedIdentity) {
                try Self.observeClock(db, event.seq)
                let known = try SetEvent.filter(SetEvent.Columns.id == event.id).fetchCount(db) > 0
                if known { continue }
                try Self.commit(event, in: db)
            }
        }
    }

    /// The merge, inside the caller's transaction. Returns the sessions it
    /// re-folded.
    private static func ingest(_ db: Database, _ events: [SetEvent]) throws -> Set<String> {
        var touched: Set<String> = []
        for event in events.map(\.normalisedIdentity) {
            try observeClock(db, event.seq)
            let known = try SetEvent
                .filter(SetEvent.Columns.id == event.id)
                .fetchCount(db) > 0
            if known { continue }
            // Already synced by definition: it reached us from the network.
            try event.insert(db)
            try db.execute(
                sql: "UPDATE set_events SET is_synced = 1 WHERE id = ?",
                arguments: [event.id]
            )
            touched.insert(event.sessionId)
        }
        for sessionId in touched {
            try reproject(sessionId: sessionId, in: db)
        }
        return touched
    }

    /// A session's log, in fold order.
    public func setEvents(sessionId: String) throws -> [SetEvent] {
        try writer.read { db in
            try SetEvent
                .filter(SetEvent.Columns.sessionId == sessionId)
                .order(SetEvent.Columns.seq, SetEvent.Columns.deviceId, SetEvent.Columns.id)
                .fetchAll(db)
        }
    }

    /// Live-updating log for a session — the Watch mirror reads this.
    public func observeSetEvents(sessionId: String) -> ValueObservation<ValueReducers.Fetch<[SetEvent]>> {
        ValueObservation.tracking { db in
            try SetEvent
                .filter(SetEvent.Columns.sessionId == sessionId)
                .order(SetEvent.Columns.seq, SetEvent.Columns.deviceId, SetEvent.Columns.id)
                .fetchAll(db)
        }
    }
}

// MARK: - The projection

extension AppDatabase {

    /// Rebuild `workout_sets` for one session from its log.
    ///
    /// ── WHY REBUILD RATHER THAN PATCH ───────────────────────────────────────
    /// Applying each event incrementally to the table would be faster and would
    /// be a second implementation of the merge rule — one in `SetEventFold` and
    /// one here, both plausible, drifting apart the first time either is
    /// touched. That is the failure the atlas generator exists to prevent, and
    /// it is worth far more than the microseconds. A session is tens of rows;
    /// the fold runs in microseconds; there is exactly one merge rule.
    ///
    /// `is_pending_sync` is true for a set with any event still unsynced, which
    /// is the honest answer to "has the server seen this set?"
    static func reproject(sessionId: String, in db: Database) throws {
        let events = try SetEvent
            .filter(SetEvent.Columns.sessionId == sessionId)
            .fetchAll(db)

        let unsyncedSetIds = Set(
            try String.fetchAll(
                db,
                sql: "SELECT DISTINCT set_id FROM set_events WHERE session_id = ? AND is_synced = 0",
                arguments: [sessionId]
            )
        )

        try db.execute(
            sql: "DELETE FROM workout_sets WHERE session_id = ?",
            arguments: [sessionId]
        )

        for (order, var set) in SetEventFold.sets(from: events, sessionId: sessionId).enumerated() {
            set.isPendingSync = unsyncedSetIds.contains(set.id)
            // The fold's own position, carried into the table so `observeSets`
            // can reproduce its order rather than leaning on rowid.
            set.foldOrder = order
            try set.insert(db)
        }
    }

    /// Rebuild every session's projection. For a migration or a repair, not for
    /// the hot path.
    public func reprojectAll() throws {
        try writer.write { db in
            let ids = try String.fetchAll(db, sql: "SELECT DISTINCT session_id FROM set_events")
            for id in ids { try Self.reproject(sessionId: id, in: db) }
        }
    }
}

// MARK: - Errors

public enum EventStoreError: Error, Equatable, Sendable {
    /// An amend that changes nothing. Rejected so the log stays meaningful.
    case emptyPatch
    /// `device_state` is missing or unreadable. The store cannot stamp an event
    /// without it, and guessing a stamp reorders history.
    case clockUnavailable
    /// An outbox acknowledgement whose event this store cannot resolve. Deleting
    /// the queue row anyway would strand the set as permanently "pending".
    case unresolvableAck(String)
    /// Another device holds the pencil for this session.
    case notSessionOwner(owner: String)
}


// MARK: - Identity normalisation

extension SetEvent {
    /// Lowercase the ids, at the one boundary where a foreign id enters.
    ///
    /// Postgres renders `uuid` lowercase and `UUID().uuidString` is uppercase,
    /// so an event that has been to the server and back arrives under a
    /// different string. `ingest`'s de-duplication is a case-sensitive compare,
    /// so without this the event inserts a second time, the fold sees two
    /// appends with different `setId`s, and the set appears twice — with a
    /// tombstone for one casing failing to suppress the other.
    var normalisedIdentity: SetEvent {
        SetEvent(
            id: id.lowercased(),
            sessionId: sessionId.lowercased(),
            setId: setId.lowercased(),
            deviceId: deviceId,
            seq: seq,
            createdAt: createdAt,
            body: body
        )
    }
}
