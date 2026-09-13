import Foundation
// For `PostgrestError.code` alone — see `isMissingRelation`. The protocol below
// still keeps the SDK out of the drainer's RULES; this is the one wire fact the
// engine has to be able to read, because it is the difference between an error
// worth retrying and one that will never clear.
import Supabase

/// The half of sync that talks to PostgREST.
///
/// A protocol so the drainer's rules can be tested without a network. That is
/// not ceremony: every property the queue has to guarantee — a replay is a
/// no-op, a kill mid-drain loses nothing, one bad row does not take a workout
/// down with it — is a property about what happens when the network misbehaves,
/// and none of them are testable against a real server.
public protocol SyncRemote: Sendable {
    /// The user's `exercises` rows. Read once per drain, not cached: it is one
    /// small select against 60 rows, and a cache is a second source of truth
    /// that can be wrong about the catalogue for as long as nobody clears it.
    func exerciseCatalogue() async throws -> [RemoteExercise]
    /// Conflict target `id`, always. With `ignoreDuplicates` it is
    /// `ON CONFLICT DO NOTHING` — "make sure this row exists" — and without it
    /// a real merge. A set event only ever gets the first: it is a fact about a
    /// set, not a statement about the session, and the device sending it may
    /// hold an older copy of the session row.
    func upsertSessions(_ rows: [RemoteSessionRow], ignoreDuplicates: Bool) async throws
    func upsertSets(_ rows: [RemoteSetRow]) async throws
    /// `DELETE … ?id=in.(…)`. Used for a voided set, and only ever for ids this
    /// device produced and then tombstoned.
    func deleteSets(ids: [String]) async throws

    /// The append-only event log — `wave-10-set-events.sql (git history)`.
    ///
    /// ── IT IS A REQUIREMENT, NOT JUST AN EXTENSION ──────────────────────────
    /// It has a default implementation (a no-op, in `SetEventSync`) so that
    /// every conformer written before Wave 10 still compiles. It is declared
    /// HERE anyway, and that is the whole difference between working and not:
    /// a method that exists only in a protocol extension is dispatched
    /// STATICALLY, so a call through `any SyncRemote` would run the extension's
    /// no-op and never reach the conformer that overrode it. The events would
    /// silently never leave the device — with a green build and a passing
    /// drain.
    func upsertSetEvents(_ rows: [RemoteSetEventRow]) async throws
}

/// What one drain did.
public struct DrainReport: Sendable, Equatable {
    public var pushed: Int = 0
    public var failed: Int = 0
    /// True when the batch limit cut the drain short, or another drain was
    /// already running. Either way the caller may drain again. It says nothing
    /// about items the backoff is holding back — those are not ready yet by
    /// definition.
    public var hasMore: Bool = false
}

/// The outbox drainer.
///
/// ── WHAT IT ACTUALLY SENDS, AND WHY IT IS NOT THE EVENT ─────────────────────
/// The queue holds `set_event.append` / `.amend` / `.void` items, and there is
/// no `set_events` table on the server — introspected, not assumed. So an event
/// is not uploaded; it is a **trigger to reconcile the set it names**. For each
/// queued event the drainer looks at the current projection and either upserts
/// that set or, if the fold has removed it, deletes it server-side.
///
/// That is what makes the whole thing idempotent for free, and it is a stronger
/// property than replaying events would give:
///
///   · An append followed by three amends collapses into ONE upsert of the
///     final row, rather than four writes racing to be last.
///   · Replaying a drain writes the same values a second time — a true no-op,
///     not an approximation of one.
///   · A void is a delete of a specific id. There is no "delete everything the
///     server has that I do not" sweep anywhere in here, so a row this device
///     has never heard of is never at risk.
///   · Being killed mid-drain leaves rows `in_flight`; `resetInFlight` returns
///     them at launch and the second run produces byte-identical rows.
///
/// ── WHAT IT DELIBERATELY DOES NOT DO YET ────────────────────────────────────
/// No `personal_records` rows, and no `total_volume_kg` / `set_count` /
/// `pr_count` on the session. All four need `prEngine`, `sessionVolumeKg` and
/// `countCommittedSets`, which are Track D's list and are not ported. They are
/// left NULL rather than zeroed: `nil` is not `0` anywhere in this app, and a
/// zero volume would be a claim about a workout rather than a gap in one.
public actor SyncEngine {

    private let database: AppDatabase
    private let remote: any SyncRemote
    /// The generic half: any mirrored row, by table and id. Optional so a target
    /// that only logs workouts — the Watch — can build an engine without one.
    private let rows: (any MirrorPushRemote)?
    private let catalogue: [String: MirrorTable]
    private var isDraining = false

    public init(
        database: AppDatabase,
        remote: any SyncRemote,
        rows: (any MirrorPushRemote)? = nil,
        // `pushable`, not `byName`: the generated catalogue plus the tables
        // whose wire shape is hand-written because the local and remote columns
        // differ. `exercises` is the only one, and without it a movement a
        // person creates on the phone has nowhere to go — the row sits in the
        // outbox failing `unmirroredTable` forever, and every set logged
        // against it is rejected by the foreign key. See
        // `ExerciseCatalogueWriter`.
        catalogue: [String: MirrorTable] = MirrorCatalogue.pushable
    ) {
        self.database = database
        self.remote = remote
        self.rows = rows
        self.catalogue = catalogue
    }

    /// Push everything the queue is ready to push.
    ///
    /// Call on foreground, on `NWPathMonitor` regaining a path, and from the
    /// 15-minute `BGAppRefreshTask`. All three can fire at once; `claimOutbox`
    /// reserves its batch inside a transaction so they cannot pick up the same
    /// rows, and `isDraining` stops the two losers doing the setup work only to
    /// find an empty queue.
    ///
    /// **Hold ONE engine for the app's lifetime.** `isDraining` is instance
    /// state, so three call sites each constructing their own engine get three
    /// separate flags and no coalescing at all. Correctness would survive that
    /// — the reservation is what actually prevents a double upload — but the
    /// wasted round trips would not be visible anywhere.
    @discardableResult
    public func drain(limit: Int = 50, now: Date = Date()) async throws -> DrainReport {
        guard !isDraining else { return DrainReport(pushed: 0, failed: 0, hasMore: true) }
        isDraining = true
        defer { isDraining = false }

        // ── NOTHING LEAVES THIS FUNCTION STILL RESERVED ─────────────────────
        // `claimOutbox` marks its batch `in_flight`, and `claimOutbox` also
        // FILTERS `in_flight` out — so a row left reserved is invisible to
        // every future drain and comes back only at the next cold launch. On a
        // phone that is never force-quit that can be days.
        //
        // Every path below acknowledges or fails its items, but the calls that
        // do so are themselves SQLite writes that can throw (a full disk, a
        // file that will not open under `.completeUnlessOpen` during a
        // background launch). One sweep here makes every path safe by
        // construction rather than by audit.
        //
        // Scoped to THIS drain's ids, not a blanket `resetInFlight`: a second
        // engine instance — three call sites each building their own is an easy
        // mistake — would otherwise release rows this one is still uploading.
        var claimed: [String] = []
        // `_ =` because the return is the row count and a `defer` has nobody to
        // report it to; the throw is deliberately swallowed — see above.
        defer { _ = try? database.returnToQueue(ids: claimed) }

        let batch = try database.claimOutbox(limit: limit, now: now)
        guard !batch.isEmpty else { return DrainReport() }
        claimed = batch.map(\.id)

        var report = DrainReport(pushed: 0, failed: 0, hasMore: batch.count == limit)

        // Decode first, and treat a payload that will not decode as a failure of
        // that ONE row. It is kept and counted like any other failure — never
        // dropped — because a row nobody can read is still evidence of a set
        // somebody logged.
        var work: [(item: OutboxItem, sessionId: String, setId: String?)] = []
        var rowWork: [(item: OutboxItem, ref: RowRef)] = []
        var deleteWork: [(item: OutboxItem, ref: RowDeleteRef)] = []
        for item in batch {
            do {
                if item.kind == SyncKind.rowUpsert {
                    rowWork.append((item, try Self.rowRef(of: item)))
                } else if item.kind == SyncKind.rowDelete {
                    deleteWork.append((item, try Self.rowDeleteRef(of: item)))
                } else {
                    work.append(try Self.target(of: item))
                }
            } catch {
                try database.outboxFailed(item.id, error: describe(error), now: now)
                report.failed += 1
            }
        }
        // The mirrored rows go first, and it is not arbitrary. A day's macros,
        // metrics and score are small, independent, single-request writes with
        // no foreign keys between them; a workout is a catalogue read plus two
        // or three requests per session. Draining the cheap ones first means a
        // thirty-second window of signal lands the day rather than half a
        // workout — and the workout, unlike the day, is never at risk of being
        // superseded before the next drain.
        let rowOutcome = try await pushRows(rowWork, deletes: deleteWork, now: now)
        report.pushed += rowOutcome.pushed
        report.failed += rowOutcome.failed

        guard !work.isEmpty else { return report }

        // One catalogue read for the whole drain, and only when there is a set
        // to resolve. A drain that is nothing but session closes needs no
        // network round trip to find that out.
        //
        // ── AND IT MUST NOT THROW OUT OF HERE ───────────────────────────────
        // This is the first request of every drain, so offline is its normal
        // failure. Letting it propagate would leave the whole claimed batch
        // marked `in_flight` with no worker and no attempt recorded — invisible
        // to the next drain and stranded until `resetInFlight` runs at the next
        // launch, which on a phone that is only ever backgrounded may be days.
        var index: ExerciseIndex?
        if work.contains(where: { $0.setId != nil }) {
            do {
                index = ExerciseIndex(try await remote.exerciseCatalogue())
            } catch {
                // Only the entries that NEED the catalogue. A session close
                // does not, and it is the one write the outbox exists for —
                // backing it off because an unrelated select failed is how
                // `ended_at` stops reaching the server for a reason that has
                // nothing to do with it.
                let message = describe(error)
                for entry in work where entry.setId != nil {
                    try database.outboxFailed(entry.item.id, error: message, now: now)
                    report.failed += 1
                }
                work.removeAll { $0.setId != nil }
                guard !work.isEmpty else { return report }
            }
        }

        // Grouped by session so a 30-set workout is two requests, not sixty.
        // `sessionOrder` keeps the queue's own order — oldest first, by rowid —
        // rather than a dictionary's, so the sequence a failure stops at is the
        // sequence the user logged.
        var bySession: [String: [(item: OutboxItem, setId: String?)]] = [:]
        var sessionOrder: [String] = []
        for entry in work {
            if bySession[entry.sessionId] == nil { sessionOrder.append(entry.sessionId) }
            bySession[entry.sessionId, default: []].append((entry.item, entry.setId))
        }

        for sessionId in sessionOrder {
            // `push` records its own remote failures and does not throw them,
            // so one unreachable session leaves the rest of the batch alone.
            let outcome = try await push(
                sessionId: sessionId, entries: bySession[sessionId] ?? [], index: index, now: now
            )
            report.pushed += outcome.pushed
            report.failed += outcome.failed
        }

        return report
    }

    // MARK: - One session

    /// Throws only on a LOCAL failure — a SQLite write that will not happen. A
    /// remote failure is caught here and turned into failed queue items, so one
    /// unreachable session does not abandon the ones behind it in the batch.
    private func push(
        sessionId: String,
        entries: [(item: OutboxItem, setId: String?)],
        index: ExerciseIndex?,
        now: Date
    ) async throws -> (pushed: Int, failed: Int) {
        var failed = 0

        guard let session = try database.session(id: sessionId) else {
            // The session was deleted locally after the item was queued. There
            // is nothing to push and nothing to retry, but the row is kept:
            // deleting it would make a queued set vanish with no trace, and
            // `unknownSession` in `last_error` is a fact worth seeing.
            for entry in entries {
                try database.outboxFailed(
                    entry.item.id, error: describe(SyncError.unknownSession(sessionId)), now: now
                )
            }
            return (0, entries.count)
        }

        // Resolve every set this batch names BEFORE any request goes out, so a
        // movement that cannot be matched costs its own rows and nothing else.
        // The session row and every other set still upload.
        let projected = Dictionary(
            try database.sets(sessionId: sessionId).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var upserts: [RemoteSetRow] = []
        var deletions: [String] = []
        var ok: [OutboxItem] = []
        /// ── ONE ROW PER SET, NEVER ONE ROW PER EVENT ────────────────────────
        /// Several queued events routinely name the same set — appending it and
        /// then correcting the weight is the commonest gesture in the app, and
        /// offline logging delivers the whole workout in one batch. Emitting a
        /// row per event puts the same `id` in the body twice, and Postgres
        /// refuses that outright:
        ///
        ///     ON CONFLICT DO UPDATE command cannot affect row a second time
        ///
        /// which fails the whole statement, fails all of that session's items,
        /// and — since they back off together and re-form the identical body —
        /// never succeeds again. The session would simply never sync.
        ///
        /// Every entry for one set produces an identical row (they all read the
        /// same `projected` snapshot), so collapsing them is lossless, and each
        /// event is still acknowledged individually below.
        var built: Set<String> = []

        for entry in entries {
            guard let setId = entry.setId else {
                ok.append(entry.item)     // a `session.upsert` item
                continue
            }
            guard let set = projected[setId] else {
                // Not in the projection means the fold removed it — a void, or
                // an append the tombstone already suppressed. Either way the
                // server must not keep the row. A delete of an id that was
                // never uploaded is a no-op, which is what makes replay safe.
                if built.insert(setId).inserted { deletions.append(setId) }
                ok.append(entry.item)
                continue
            }
            do {
                guard let index else { throw SyncError.unknownExercise(slug: set.exerciseId, name: nil) }
                let row = try SyncTranslation.setRow(
                    set,
                    userId: session.userId,
                    exerciseId: try index.id(forSlug: set.exerciseId)
                )
                if built.insert(setId).inserted { upserts.append(row) }
                ok.append(entry.item)
            } catch {
                try database.outboxFailed(entry.item.id, error: describe(error), now: now)
                failed += 1
            }
        }

        /// The outbox items whose SET EVENT could not be delivered, and why.
        /// They are not acknowledged below; everything else in the batch is.
        var heldEvents: (ids: Set<String>, message: String)?

        do {
            // The session row goes first, always. `workout_sets.session_id` has
            // a foreign key to it, so a set that arrives before its parent is
            // rejected — and on a fresh session that is every set.
            //
            // ── BUT A SET EVENT MAY NOT OVERWRITE THE SESSION ───────────────
            // `workout_sessions` has no merge rule; the set log does. A device
            // pushing a set event is saying "this set happened", not "here is
            // the state of the session" — and it may hold an older copy of the
            // row. Merging it would let a watch that never heard the finish
            // push `ended_at: null` over a closed session and erase the rating
            // with it, silently, leaving nothing queued to show for it.
            //
            // So a set event only ENSURES the parent exists
            // (`ON CONFLICT DO NOTHING`), and the full row is written only by
            // the `session.upsert` item that `closeSession` queues — the one
            // write that is actually about the session.
            let carriesSessionFacts = entries.contains { $0.setId == nil }
            try await remote.upsertSessions(
                [try SyncTranslation.sessionRow(session, now: now)],
                ignoreDuplicates: !carriesSessionFacts
            )
            try database.markSessionSynced(id: sessionId)
            // ── TWO BODIES, BECAUSE OF ONE CONDITIONAL COLUMN ───────────────
            // `quality` is the only key `RemoteSetRow` encodes conditionally,
            // and PostgREST rejects a bulk body whose objects disagree about
            // keys (`PGRST102`). Splitting on exactly that condition gives two
            // bodies that are each one shape: the tagged sets carry `quality`,
            // the untagged ones do not carry the key at all — which is what
            // leaves a tag the web app recorded untouched rather than nulling
            // it from a device that was never asked. See `RemoteSetRow`.
            let tagged = upserts.filter { $0.quality != nil }
            let untagged = upserts.filter { $0.quality == nil }
            if !untagged.isEmpty { try await remote.upsertSets(untagged) }
            if !tagged.isEmpty { try await remote.upsertSets(tagged) }
            // Deletions last. Doing them first would drop a row that the upsert
            // in the same drain is about to restore, which is harmless but
            // leaves the server briefly disagreeing with the phone for no
            // reason.
            if !deletions.isEmpty { try await remote.deleteSets(ids: deletions) }
            // ── AND THE EVENTS THEMSELVES, LAST ────────────────────────────
            // The rows above are what the web app reads and what this queue has
            // always been about; the log is what lets a SECOND device adopt
            // them (`SetEventSync`). It goes last, and inside the `do` so a
            // network failure here is charged to the queue like any other.
            //
            // ── IT DOES NOT THROW, AND IT NO LONGER SWALLOWS ────────────────
            // Throwing here would charge the session row and every set row a
            // failure they did not earn — they already landed. So `pushEvents`
            // reports instead: the ids it could not deliver, which are held
            // back from the ack below and retried on the next drain.
            //
            // The one thing it still swallows is a MISSING TABLE. `set_events`
            // is applied by hand and PostgREST answers 404 until the SQL is
            // run; holding every set event of every session forever over a
            // table the user has not created yet is the worse failure by a
            // distance, and it is not transient — no number of retries makes
            // the table appear. Everything else — a 503, a dropped connection,
            // a timeout — is transient, and dropping a set event over one is
            // how two devices stop converging with nothing queued to show for
            // it.
            heldEvents = await pushEvents(entries, userId: session.userId)
        } catch {
            // Caught rather than thrown, for two reasons. One unreachable
            // session must not abandon the sessions behind it in the batch; and
            // an entry already failed above must not be charged a second
            // attempt for the same drain, which would double its backoff.
            let message = describe(error)
            for item in ok { try database.outboxFailed(item.id, error: message, now: now) }
            return (0, failed + ok.count)
        }

        // ponytail: one `reproject` per acknowledged event — a full fold of the
        // session's whole log, in its own transaction, N times for N sets. It
        // is microseconds a set today; if a long session's finish ever hitches,
        // the fix is a batch ack (one transaction, one UPDATE … IN (…), one
        // fold) rather than making the fold incremental.
        //
        // An item whose EVENT did not land is not acknowledged. Its set row
        // did land, and re-sending that row on the next drain is a no-op —
        // `upsertSets` is `ON CONFLICT DO UPDATE` over an identical
        // projection — so the retry costs one duplicate row write and buys
        // back an event that would otherwise be gone for good.
        var pushed = 0
        for item in ok {
            if let held = heldEvents, held.ids.contains(item.id) {
                try database.outboxFailed(item.id, error: held.message, now: now)
                failed += 1
            } else {
                try database.outboxSucceeded(item.id)
                pushed += 1
            }
        }
        return (pushed, failed)
    }

    /// The queued events of one session, as server rows.
    ///
    /// Re-decoded from the outbox payload rather than threaded down from
    /// `target(of:)`: the payload IS the event (`EventStore.commit` encodes it
    /// whole), the decode is microseconds, and carrying it through two tuples
    /// to save that would widen a signature every other caller has to read.
    ///
    /// Clock events are skipped here for the same reason `commit` never queues
    /// them — they are local facts about this device's session timer, and
    /// `duration_min` is what the server actually needs from a pause.
    ///
    /// Returns the ids of the items whose event did NOT reach the server and
    /// must therefore stay in the outbox, or `nil` when there is nothing to
    /// hold back. It never throws: the rows the queue is really about have
    /// already landed by the time this runs, and charging them for the event
    /// log's failure would back the whole workout off.
    private func pushEvents(
        _ entries: [(item: OutboxItem, setId: String?)], userId: String
    ) async -> (ids: Set<String>, message: String)? {
        var rows: [RemoteSetEventRow] = []
        var sent: Set<String> = []
        for entry in entries where entry.item.kind.hasPrefix(SyncKind.setEventPrefix) {
            guard let event = try? OnyxJSON.decoder.decode(SetEvent.self, from: entry.item.payload),
                  !event.kind.isClock
            else { continue }
            rows.append(event.remoteRow(userId: userId))
            sent.insert(entry.item.id)
        }
        guard !rows.isEmpty else { return nil }
        do {
            try await remote.upsertSetEvents(rows)
            return nil
        } catch {
            // The ONE permanent failure, swallowed on purpose. See the call
            // site: `set_events` is applied by hand, and a table that does not
            // exist will not start existing because the queue asked again.
            if Self.isMissingRelation(error) { return nil }
            return (ids: sent, message: "set_events: \(describe(error))")
        }
    }

    /// True when POSTGRES is saying the table is not there — `42P01`, the one
    /// answer no retry can change.
    ///
    /// ── WHY THE POSTGREST CODES ARE NOT HERE ANY MORE ───────────────────────
    /// This used to match `PGRST205` and `PGRST204` too, reading them as "the
    /// table / column does not exist". They mean "not in MY schema cache" —
    /// and PostgREST's cache is stale during a reload or a restart, the same
    /// window that produces the 503s the item is held for. In that window an
    /// existing table answers PGRST205, the event was acknowledged as
    /// undeliverable, and it was gone for good the moment the cache warmed.
    /// A silent permanent loss on a transient condition, on the one table
    /// whose rows only ever exist as events.
    ///
    /// `42703` (undefined column) goes for the same reason in the other
    /// direction: a column the SQL has not added yet is the pasted-by-hand
    /// case, and it appears the day the founder pastes. Held, backed off, and
    /// delivered then. The cost of holding a genuinely missing table is an
    /// outbox that grows by one row per set until the SQL is run, retried at
    /// most once an hour (`SyncBackoff.cap`) — the cost of dropping a real
    /// event is the workout.
    private static func isMissingRelation(_ error: any Error) -> Bool {
        (error as? PostgrestError)?.code == "42P01"
    }

    // MARK: - Mirrored rows

    /// Push queued mirrored rows — a day's metrics, a macro row, a preference,
    /// a score.
    ///
    /// One request per row and no grouping, because unlike a workout these rows
    /// are unrelated to each other: they hit six different tables with six
    /// different conflict targets, and batching them would mean one table's
    /// CHECK violation failing five innocent writes.
    ///
    /// Never throws on a remote failure, for the same reason `push` does not:
    /// one unreachable table must not abandon the rest of the batch.
    private func pushRows(
        _ entries: [(item: OutboxItem, ref: RowRef)],
        deletes: [(item: OutboxItem, ref: RowDeleteRef)],
        now: Date
    ) async throws -> (pushed: Int, failed: Int) {
        guard !entries.isEmpty || !deletes.isEmpty else { return (0, 0) }
        guard let rows else {
            // No push remote was supplied. The items stay queued and back off;
            // they are not dropped, because the row they name is real.
            for item in entries.map(\.item) + deletes.map(\.item) {
                try database.outboxFailed(item.id, error: "no MirrorPushRemote on this engine", now: now)
            }
            return (0, entries.count + deletes.count)
        }

        var pushed = 0
        var failed = 0
        // Deletes first. The queue never holds a delete and an upsert of the
        // SAME row (`enqueueRowUpsert` and `enqueueRowDelete` each drop the
        // other), so the order only matters for a row that was deleted and
        // re-created under a fresh id in one gap — the water override does
        // exactly that — and there the delete must land before the insert or
        // the server briefly holds two rows for one day.
        for entry in deletes {
            do {
                guard catalogue[entry.ref.table] != nil else {
                    throw SyncError.unmirroredTable(entry.ref.table)
                }
                try await rows.deleteRow(table: entry.ref.table, key: entry.ref.key)
                try database.outboxSucceeded(entry.item.id)
                pushed += 1
            } catch {
                try database.outboxFailed(entry.item.id, error: describe(error), now: now)
                failed += 1
            }
        }
        for entry in entries {
            do {
                guard let table = catalogue[entry.ref.table] else {
                    throw SyncError.unmirroredTable(entry.ref.table)
                }
                guard try await table.push(database, rows, entry.ref) else {
                    throw SyncError.unknownRow(table: entry.ref.table, id: entry.ref.id)
                }
                try database.outboxSucceeded(entry.item.id)
                pushed += 1
            } catch {
                try database.outboxFailed(entry.item.id, error: describe(error), now: now)
                failed += 1
            }
        }
        return (pushed, failed)
    }

    // MARK: - Reading an item

    /// What a `row.upsert` item names.
    static func rowRef(of item: OutboxItem) throws -> RowRef {
        do {
            return try OnyxJSON.decoder.decode(RowRef.self, from: item.payload)
        } catch {
            throw SyncError.undecodablePayload(kind: item.kind, detail: "\(error)")
        }
    }

    /// What a `row.delete` item names.
    static func rowDeleteRef(of item: OutboxItem) throws -> RowDeleteRef {
        do {
            return try OnyxJSON.decoder.decode(RowDeleteRef.self, from: item.payload)
        } catch {
            throw SyncError.undecodablePayload(kind: item.kind, detail: "\(error)")
        }
    }

    /// What an outbox item is about: a session, and at most one set.
    static func target(of item: OutboxItem) throws -> (item: OutboxItem, sessionId: String, setId: String?) {
        if item.kind.hasPrefix(SyncKind.setEventPrefix) {
            do {
                let event = try OnyxJSON.decoder.decode(SetEvent.self, from: item.payload)
                return (item, event.sessionId, event.setId)
            } catch {
                // The underlying error is carried, not swallowed. The whole
                // point of keeping a poison row is that somebody can see WHY,
                // and "undecodable" on its own says nothing a key path would.
                throw SyncError.undecodablePayload(kind: item.kind, detail: "\(error)")
            }
        }
        if item.kind == SyncKind.sessionUpsert {
            do {
                let ref = try OnyxJSON.decoder.decode(SessionRef.self, from: item.payload)
                return (item, ref.sessionId, nil)
            } catch {
                throw SyncError.undecodablePayload(kind: item.kind, detail: "\(error)")
            }
        }
        throw SyncError.undecodablePayload(kind: item.kind, detail: "unknown kind")
    }

    /// `last_error` is read by a human, so it holds the case and its values
    /// rather than `Optional(OnyxData.SyncError.unmappedDayKey("legs_c"))`.
    private func describe(_ error: any Error) -> String {
        if let sync = error as? SyncError {
            switch sync {
            case .undecodablePayload(let kind, let detail):
                return "undecodable payload for kind \(kind): \(detail)"
            case .unknownSession(let id): return "session \(id) is not in the local store"
            case .unmappedDayKey(let key): return "no split_day for day_key \(key ?? "nil")"
            case .sessionHasNoStart(let id): return "session \(id) has no started_at"
            case .unmappedSide(let side): return "side \"\(side)\" is neither left nor right"
            case .unknownExercise(let slug, let name):
                return "no catalogue row for \(name ?? slug) (\(slug))"
            case .ambiguousExercise(let name, let candidates):
                return "\(name) matches \(candidates.count) catalogue rows: \(candidates.joined(separator: ", "))"
            case .unmirroredTable(let table): return "\(table) is not in the mirror catalogue"
            case .unknownRow(let table, let id): return "\(table) row \(id) is not in the local store"
            }
        }
        return String(describing: error)
    }
}
