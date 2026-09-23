import Foundation
import GRDB
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// The session's LIFE across two devices (overhaul Lane A, decisions Q1 + Q3).
//
// The root cause of "the watch offers Start after the phone finished" was three
// stacked defects, and all three were about there being no STATE on the wire —
// only events, which a simulator never delivers and hardware delivers whenever
// the queue drains. `WatchContext.session` is that state now. This file is the
// arithmetic both ends need around it, out here in the package where
// `swift test` reaches it:
//
//   · the phone builds the lifecycle and its masthead off its own row;
//   · the watch applies it to its own store (close, discard, tombstone) so a
//     finished session can never be re-adopted, however late its open lands;
//   · a MESSAGED finish waits for the queue ahead of it (`finishIsReady`);
//   · and the wrist's front door is one pure decision (`WatchFrontDoor`).
// ─────────────────────────────────────────────────────────────────────────────

extension SessionLifecycle {
    /// The state a pulse leaves its session in. Nil for `joined`, which is a
    /// fact about the other device's runtime and never a state.
    public init?(_ pulse: SessionPulse, summary: SessionMasthead? = nil) {
        let phase: Phase
        switch pulse.phase {
        case .open: phase = .open
        case .finished: phase = .finished
        case .discarded: phase = .discarded
        case .joined: return nil
        }
        guard let startedAt = pulse.startedAt else { return nil }
        self.init(
            sessionId: pulse.sessionId, phase: phase, startedAt: startedAt,
            endedAt: phase == .finished ? pulse.endedAt : nil,
            summary: phase == .finished ? summary : nil,
            date: pulse.date, dayKey: pulse.dayKey
        )
    }

    /// Whether this is about the day `today` names. The row's own date when
    /// the phone sent it, else the logical day of the start — an older
    /// build's lifecycle carries no date.
    public func isOn(_ today: String, calendar: Calendar = .current) -> Bool {
        (date ?? LogicalDay.iso(startedAt, calendar: calendar)) == today
    }
}

extension SessionMasthead {
    /// A CLOSED session in one line, off its own row: `closeSession` has
    /// already written the tonnage and the PR count there, so nothing is
    /// recomputed. Nil for a row that is still open or has no start.
    ///
    /// `avg_bpm` wins over the samples when the row has one — it is the
    /// number the session page prints — and the samples are the spark.
    public init?(session: WorkoutSession, name: String, samples: [HRSample]) {
        guard let start = session.startedAt, let end = session.endedAt else { return nil }
        let seconds = session.durationMin.map { Int(($0 * 60).rounded()) }
            ?? max(0, Int(end.timeIntervalSince(start).rounded()))
        let bpms = samples.map { Double($0.bpm) }
        let mean = bpms.isEmpty ? nil : Int((bpms.reduce(0, +) / Double(bpms.count)).rounded())
        self.init(
            name: name, durationSec: seconds, tonnageKg: session.totalVolumeKg ?? 0,
            avgBpm: session.avgBpm ?? mean, prCount: session.prCount ?? 0,
            hrSpark: bpms, startedAt: start
        )
    }
}

extension AppDatabase {

    /// The masthead of a finished session, with the heart-rate spark from the
    /// telemetry cache when the prefetch has filled it. Nil while the row is
    /// still open.
    public func sessionMasthead(sessionId: String, userId: String, name: String) throws -> SessionMasthead? {
        guard let row = try session(id: sessionId, userId: userId) else { return nil }
        let samples = (try? telemetryCache(sessionId: sessionId))?.samples ?? []
        return SessionMasthead(session: row, name: name, samples: samples)
    }

    /// Every event this store holds for a session — the number a messaged
    /// finish is measured against. Pauses and voids count: the sender counted
    /// its whole log for the session, and so does this.
    public func eventCount(sessionId: String) throws -> Int {
        try writer.read { db in
            try SetEvent.filter(SetEvent.Columns.sessionId == sessionId).fetchCount(db)
        }
    }

    /// May this finish be applied yet? Always, unless it carries a count this
    /// store's log has not reached — the queued sets ahead of it are still in
    /// flight.
    public func finishIsReady(_ pulse: SessionPulse) throws -> Bool {
        guard pulse.phase == .finished, let expected = pulse.expectedEventCount else { return true }
        return try eventCount(sessionId: pulse.sessionId) >= expected
    }

    /// Hold a messaged finish until `finishIsReady` or `grace` runs out.
    ///
    /// Polled rather than observed: a quarter-second read of one indexed
    /// count, for at most five seconds, once per workout. An observation
    /// would be a subscription to tear down for the same answer.
    public func waitForFinish(_ pulse: SessionPulse, grace: TimeInterval = SessionPulse.finishGrace) async {
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline, !((try? finishIsReady(pulse)) ?? true) {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Whether a session id was discarded here — or retired by a lifecycle —
    /// and may never be opened again.
    public func isTombstoned(sessionId: String) throws -> Bool {
        try writer.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM session_tombstones WHERE id = ?)",
                              arguments: [sessionId]) ?? false
        }
    }

    /// Apply the phone's lifecycle word to THIS store (the watch's).
    ///
    /// A finished or discarded session is closed or thrown away here exactly
    /// as its missed pulse would have done, and then TOMBSTONED either way —
    /// so a late copy of its open (message and queue both carry one, in no
    /// order) cannot put a live row back for `rejoinLiveSession` to adopt.
    /// That was the third stacked defect behind "Start reappears": the wrist
    /// re-adopted a closed session and restarted its `HKWorkoutSession`.
    ///
    /// An open is not applied: joining is a person's decision (the Join
    /// button), not a context push's.
    @discardableResult
    public func applyLifecycle(_ lifecycle: SessionLifecycle, userId: String) throws -> SessionPulseOutcome {
        guard lifecycle.phase != .open else { return .unchanged }
        var outcome = SessionPulseOutcome.unchanged
        if var row = try session(id: lifecycle.sessionId, userId: userId), row.endedAt == nil {
            if lifecycle.phase == .finished { row.endedAt = lifecycle.endedAt ?? Date() }
            outcome = try receiveSession(SessionPulse(row, phase: lifecycle.phase == .finished ? .finished : .discarded))
        }
        try writer.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO session_tombstones (id) VALUES (?)", arguments: [lifecycle.sessionId])
        }
        return outcome
    }
}

/// What the wrist opens on when it holds no session — a pure answer to the
/// phone's lifecycle, so the three states are a table and not a view's
/// `if`s (overhaul Lane A, decisions Q1 + Q3).
public enum WatchFrontDoor: Equatable, Sendable {
    /// Nothing today, or only a discard: the Start button.
    case start
    /// The phone is logging a session this wrist has not adopted.
    case join(SessionLifecycle)
    /// Today's workout is done. The masthead when the phone sent one — an
    /// older phone says only `todayLogged`, and the banner draws the split.
    case banner(SessionMasthead?)

    /// - Parameter context: the phone's last word; nil before it has spoken.
    public static func resolve(_ context: WatchContext?, calendar: Calendar = .current) -> WatchFrontDoor {
        guard let context else { return .start }
        if let session = context.session, session.isOn(context.today, calendar: calendar) {
            switch session.phase {
            case .open: return .join(session)
            case .finished: return .banner(session.summary)
            // A discard is "nothing happened" — fall through to what the
            // tiles say about any OTHER session today.
            case .discarded: break
            }
        }
        return context.tiles?.todayLogged == true ? .banner(nil) : .start
    }
}
