import Foundation

/// The event log's own wire format — `wave-10-set-events.sql (git history)`.
///
/// ── WHY THE SERVER CARRIES EVENTS AS WELL AS ROWS ───────────────────────────
/// `SyncEngine` reconciles the PROJECTION: for each queued event it upserts or
/// deletes the `workout_sets` row the event names. That is complete while one
/// device writes, and it stops being complete the moment two do.
///
/// `TrainingPuller.applyPulledSets` refuses to write pulled rows into a session
/// that already has local events — it has to, because those rows are a fold and
/// the next append would delete them. So with rows alone the phone logs sets
/// 1-3, the watch logs set 4, the server ends up holding all four, and neither
/// device can adopt the other's. The workout is whole on the server and
/// permanently partial on both clients.
///
/// `AppDatabase.ingest(_:)` has been the answer since Wave 1b — de-duplicating
/// by event id, pulling the Lamport clock up, marking the event synced and
/// re-folding. It has never had a transport. This is that transport.
///
/// ── AND WHY IT IS ADVISORY, NOT AUTHORITATIVE ───────────────────────────────
/// The table is applied BY HAND (there is no DDL path from this machine), so
/// there is a window — possibly a long one — where the client has shipped and
/// the table has not. Everything here therefore degrades to a no-op rather than
/// to a failure:
///
///   · the push is attempted AFTER the row reconcile has already succeeded, and
///     its error is swallowed. A missing table costs one 404 per drain and
///     changes nothing else — sets sync exactly as they did before.
///   · the pull is wrapped the same way and reports zero.
///
/// The alternative is a queue that poisons itself against a schema the user has
/// not run yet, which would take the whole workout down with it. Events start
/// flowing the moment the SQL lands, with no client change and no migration.
public struct RemoteSetEventRow: Codable, Sendable, Equatable {
    /// The event's own id. Client-supplied and never defaulted: it is what makes
    /// a re-delivery a no-op, on this side and in `ingest`.
    public var id: String
    public var userId: String
    public var sessionId: String
    /// The set this is ABOUT. No foreign key server-side — a `void` names a set
    /// whose row is already deleted.
    public var setId: String
    public var deviceId: String
    /// Lamport, not time. Ordering only.
    public var seq: Int64
    /// Denormalised beside `body` so SQL can filter without decoding a blob.
    public var kind: String
    /// `SetEvent.Body` exactly as it encodes — `{"kind": …, "payload": {…}}`.
    /// Nested `Codable` rather than an `AnyJSON`, which keeps this type
    /// Foundation-only and reuses the one hand-written wire shape that the
    /// on-disk rows already use.
    public var body: SetEvent.Body
    /// The DEVICE's wall clock. Display only.
    public var createdAt: Date
    /// **THE CURSOR — read, never written.**
    ///
    /// Server-assigned (`default now()`), and the only value in the row that is
    /// monotonic across devices: `seq` is per-device and two devices
    /// legitimately both emit 41, so a cursor on it steps over events.
    ///
    /// Absent from `encode(to:)` for the same reason `RemoteSessionRow` omits
    /// `updatedAt`: a device three minutes slow would stamp a row into a range
    /// the next pull has already been through, and that event would never be
    /// seen again.
    public var insertedAt: Date?

    public enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sessionId = "session_id"
        case setId = "set_id"
        case deviceId = "device_id"
        case seq
        case kind
        case body
        case createdAt = "created_at"
        case insertedAt = "inserted_at"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(setId, forKey: .setId)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(seq, forKey: .seq)
        try container.encode(kind, forKey: .kind)
        try container.encode(body, forKey: .body)
        try container.encode(createdAt, forKey: .createdAt)
        // `insertedAt` deliberately not encoded. See the doc comment.
    }

    public init(
        id: String, userId: String, sessionId: String, setId: String,
        deviceId: String, seq: Int64, kind: String, body: SetEvent.Body,
        createdAt: Date, insertedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.sessionId = sessionId
        self.setId = setId
        self.deviceId = deviceId
        self.seq = seq
        self.kind = kind
        self.body = body
        self.createdAt = createdAt
        self.insertedAt = insertedAt
    }
}

// MARK: - Translation

public extension SetEvent {
    /// The server row for this event.
    ///
    /// Ids are lowercased on the way out for the same reason `newOnyxID` mints
    /// them lowercase and `normalisedIdentity` re-lowercases on the way in:
    /// Postgres renders `uuid` lowercase, and a round trip that changes the
    /// string defeats both the idempotence of `append` and the terminality of
    /// `void`.
    func remoteRow(userId: String) -> RemoteSetEventRow {
        RemoteSetEventRow(
            id: id.lowercased(),
            userId: userId.lowercased(),
            sessionId: sessionId.lowercased(),
            setId: setId.lowercased(),
            deviceId: deviceId,
            seq: seq,
            kind: kind.rawValue,
            body: body,
            createdAt: createdAt
        )
    }
}

public extension RemoteSetEventRow {
    /// Back to a domain event. `ingest` normalises the identity again on the
    /// way into the store — this does not have to be the only place it happens,
    /// and it should not be the only place it happens.
    var event: SetEvent {
        SetEvent(
            id: id,
            sessionId: sessionId,
            setId: setId,
            deviceId: deviceId,
            seq: seq,
            createdAt: createdAt,
            body: body
        )
    }
}

// MARK: - The push half

public extension SyncRemote {
    /// Write events. `ON CONFLICT DO NOTHING` — events are immutable, so the
    /// only correct behaviour for an id the server already has is to leave it
    /// alone, and that is what makes a replay free.
    ///
    /// ── A DEFAULT IMPLEMENTATION, AND WHY IT DOES NOTHING ───────────────────
    /// Every existing conformer — the test fakes especially — predates this
    /// method, and a protocol requirement with no default would break all of
    /// them at once for a feature none of them is about. A fake that WANTS to
    /// observe the event push overrides it; one that is testing the row
    /// reconcile carries on saying nothing, which is exactly what it was
    /// saying before.
    ///
    /// The real conformer is `PostgRESTRemote`.
    func upsertSetEvents(_ rows: [RemoteSetEventRow]) async throws {}
}
