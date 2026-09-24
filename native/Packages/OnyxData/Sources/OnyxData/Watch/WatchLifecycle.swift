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
            date: pulse.date, dayKey: pulse.dayKey, expectedEventCount: pulse.expectedEventCount
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

    /// How many of a session's events THIS device wrote — what a sender puts
    /// on its finish (`SessionPulse.expectedEventCount`).
    ///
    /// ── ITS OWN, NOT ALL OF THEM (after review) ─────────────────────────────
    /// A whole-log count on both ends lets two queues cancel out: wrist events
    /// still on their way to the phone and phone events still on their way to
    /// the wrist leave both totals equal, and the finish lands early. Each
    /// side's own events are the ones only it can deliver, so the sender counts
    /// its own and the receiver counts everything it did NOT write
    /// (`receivedEventCount`). The phone relays only its own events to the
    /// watch (`PhoneWatchBridge.flush` → `localEvents`), so on the wrist
    /// "not mine" is exactly "the phone's".
    public func authoredEventCount(sessionId: String) throws -> Int {
        let me = try deviceId()
        return try writer.read { db in
            try SetEvent.filter(SetEvent.Columns.sessionId == sessionId && SetEvent.Columns.deviceId == me).fetchCount(db)
        }
    }

    /// How many of a session's events arrived from another device.
    public func receivedEventCount(sessionId: String) throws -> Int {
        let me = try deviceId()
        return try writer.read { db in
            try SetEvent.filter(SetEvent.Columns.sessionId == sessionId && SetEvent.Columns.deviceId != me).fetchCount(db)
        }
    }

    /// May this finish be applied yet? Always, unless it carries a count this
    /// store has not received — the sender's queued sets are still in flight.
    public func finishIsReady(_ pulse: SessionPulse) throws -> Bool {
        guard pulse.phase == .finished else { return true }
        return try isReady(sessionId: pulse.sessionId, expected: pulse.expectedEventCount)
    }

    /// The same question for a lifecycle arriving in the CONTEXT, which carries
    /// the count too — the context and the message go out together, so the
    /// context path must wait exactly as the message does (after review).
    public func lifecycleIsReady(_ lifecycle: SessionLifecycle) throws -> Bool {
        guard lifecycle.phase == .finished else { return true }
        return try isReady(sessionId: lifecycle.sessionId, expected: lifecycle.expectedEventCount)
    }

    private func isReady(sessionId: String, expected: Int?) throws -> Bool {
        guard let expected else { return true }
        return try receivedEventCount(sessionId: sessionId) >= expected
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

    /// The same wait for a lifecycle from the context.
    public func waitForLifecycle(_ lifecycle: SessionLifecycle, grace: TimeInterval = SessionPulse.finishGrace) async {
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline, !((try? lifecycleIsReady(lifecycle)) ?? true) {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Whether a session id was discarded here and may never be opened again.
    public func isTombstoned(sessionId: String) throws -> Bool {
        try writer.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM session_tombstones WHERE id = ?)",
                              arguments: [sessionId]) ?? false
        }
    }

    /// Apply the phone's lifecycle word to THIS store (the watch's).
    ///
    /// A finished or discarded session is closed or thrown away here exactly
    /// as its missed pulse would have done, so neither the next context push
    /// nor a late copy of its open (message and queue both carry one, in no
    /// order) leaves a LIVE row for `rejoinLiveSession` to adopt — the third
    /// stacked defect behind "Start reappears".
    ///
    /// ── A FINISH IS NEVER A TOMBSTONE (after review) ────────────────────────
    /// A finished session this store never had gets its row, born CLOSED, and
    /// not a tombstone: a tombstone refuses the late open, and then every
    /// queued set of that session fails the `set_events` foreign key — and
    /// `ingest` rolls the whole batch back with it. The closed row makes the
    /// late open a no-op (`receiveSession` never rewrites a row) and gives the
    /// events their parent. Only a DISCARD tombstones.
    ///
    /// The caller checks `lifecycleIsReady` first; this applies. An open is
    /// not applied: joining is a person's decision (Join), not a push's.
    @discardableResult
    public func applyLifecycle(_ lifecycle: SessionLifecycle, userId: String) throws -> SessionPulseOutcome {
        switch lifecycle.phase {
        case .open:
            return .unchanged
        case .finished:
            if var row = try session(id: lifecycle.sessionId, userId: userId) {
                guard row.endedAt == nil else { return .unchanged }
                row.endedAt = lifecycle.endedAt ?? Date()
                return try receiveSession(SessionPulse(row, phase: .finished))
            }
            guard let date = lifecycle.date else { return .unchanged }
            try writer.write { db in
                let tombstoned = try Bool.fetchOne(
                    db, sql: "SELECT EXISTS (SELECT 1 FROM session_tombstones WHERE id = ?)", arguments: [lifecycle.sessionId]
                ) ?? false
                guard !tombstoned, try WorkoutSession.fetchOne(db, key: lifecycle.sessionId) == nil else { return }
                try WorkoutSession(
                    id: lifecycle.sessionId, userId: userId, dayKey: lifecycle.dayKey, date: date,
                    startedAt: lifecycle.startedAt, endedAt: lifecycle.endedAt ?? lifecycle.startedAt
                ).insert(db)
            }
            return .unchanged
        case .discarded:
            var outcome = SessionPulseOutcome.unchanged
            if let row = try session(id: lifecycle.sessionId, userId: userId), row.endedAt == nil {
                outcome = try receiveSession(SessionPulse(row, phase: .discarded))
            }
            try writer.write { db in
                try db.execute(sql: "INSERT OR IGNORE INTO session_tombstones (id) VALUES (?)", arguments: [lifecycle.sessionId])
            }
            return outcome
        }
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
