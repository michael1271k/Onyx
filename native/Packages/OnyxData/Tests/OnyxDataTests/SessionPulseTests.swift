import Foundation
import OnyxCore
import Testing
@testable import OnyxData

/// A session opened on one device, arriving on the other (App Store W4).
///
/// ── THE PREMISE THIS FILE EXISTS TO CORRECT ─────────────────────────────────
/// The sprint plan said a workout started on one device "does not reach the
/// other until a set is logged". It did not reach it THEN either.
/// `set_events.session_id` is a foreign key to `workout_sessions`, and neither
/// device ever created the other's session row — the watch has no Supabase to
/// pull one from, and the link carried events and nothing else. So the first
/// test below is the old world: the other device's set is REFUSED, and on the
/// watch that refusal was a `try?`. Everything after it is the fix — the row
/// travels first, as `SessionPulse`, and every event behind it lands.
///
/// `WatchConvergenceTests` never saw this because its harness inserts the same
/// session row into both stores before anything happens.
@Suite("Session pulse")
struct SessionPulseTests {

    private static let userId = "22222222-2222-2222-2222-222222222222"
    private static let date = "2026-09-23"

    private func snapshot(_ index: Int) -> SetSnapshot {
        SetSnapshot(exerciseId: ExerciseSlug.id("Hack Squat"), setIndex: index, weightKg: 100, reps: 8)
    }

    private func opened(on device: AppDatabase) throws -> WorkoutSession {
        try device.openSession(userId: Self.userId, dayKey: "cb_b", date: Self.date)
    }

    @Test("without the session row, the other device's set is refused — the old world")
    func eventsWithoutTheRowAreRefused() throws {
        let phone = try AppDatabase.inMemory(deviceId: "phone")
        let watch = try AppDatabase.inMemory(deviceId: "watch")
        let session = try opened(on: phone)
        let event = try phone.appendSet(sessionId: session.id, snapshot(1))

        #expect(throws: (any Error).self) { try watch.ingest([event]) }
        #expect(try watch.liveSession(dayKey: "cb_b", date: Self.date, userId: Self.userId) == nil)
    }

    @Test("an open pulse carries the row, and the events behind it land")
    func openCarriesTheRow() throws {
        let phone = try AppDatabase.inMemory(deviceId: "phone")
        let watch = try AppDatabase.inMemory(deviceId: "watch")
        let session = try opened(on: phone)

        #expect(try watch.receiveSession(SessionPulse(session, phase: .open)) == .opened(superseded: nil))
        // What `rejoinLiveSession` reads: the SAME id, found by split and date.
        #expect(try watch.liveSession(dayKey: "cb_b", date: Self.date, userId: Self.userId)?.id == session.id)

        let event = try phone.appendSet(sessionId: session.id, snapshot(1))
        try watch.ingest([event])
        #expect(try watch.sets(sessionId: session.id, userId: Self.userId).count == 1)
    }

    /// A transfer delivered twice, or a re-announce after a relaunch, must
    /// not duplicate or rewrite a row.
    @Test("a second open is a no-op, not a second row or a rewrite")
    func openIsIdempotent() throws {
        let watch = try AppDatabase.inMemory(deviceId: "watch")
        let session = WorkoutSession(
            id: "33333333-3333-3333-3333-333333333333", userId: Self.userId, dayKey: "cb_b",
            date: Self.date, startedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
        #expect(try watch.receiveSession(SessionPulse(session, phase: .open)) == .opened(superseded: nil))
        var moved = session
        moved.startedAt = session.startedAt?.addingTimeInterval(600)
        #expect(try watch.receiveSession(SessionPulse(moved, phase: .open)) == .unchanged)
        #expect(try watch.session(id: session.id, userId: Self.userId)?.startedAt == session.startedAt)
    }

    /// The phone's half of a wrist-finished workout: it is the only device
    /// that syncs, so ITS close is the one the server keeps.
    @Test("a finish closes the row at the sender's instant, from the events it holds")
    func finishClosesAtTheSendersInstant() throws {
        let phone = try AppDatabase.inMemory(deviceId: "phone")
        let watch = try AppDatabase.inMemory(deviceId: "watch")
        let session = try opened(on: watch)
        #expect(try phone.receiveSession(SessionPulse(session, phase: .open)) == .opened(superseded: nil))
        try phone.ingestFromWatch([
            try watch.appendSet(sessionId: session.id, snapshot(1)),
            try watch.appendSet(sessionId: session.id, snapshot(2)),
        ])

        try watch.closeSession(id: session.id, restTargetSec: 150)
        // Re-read, not `closeSession`'s return: that is the in-memory value at
        // full precision, and both stores keep milliseconds.
        let closed = try #require(try watch.session(id: session.id, userId: Self.userId))
        #expect(try phone.receiveSession(SessionPulse(closed, phase: .finished, restTargetSec: 150)) == .closed)

        let row = try #require(try phone.session(id: session.id, userId: Self.userId))
        #expect(row.endedAt == closed.endedAt)
        #expect(row.setCount == 2, "the aggregates come from the wrist's events, not from nothing")
        #expect(row.durationMin == closed.durationMin)

        // Delivered twice, or echoed: still one close.
        #expect(try phone.receiveSession(SessionPulse(closed, phase: .finished)) == .unchanged)
        // And an open that arrives late never reopens a finished workout.
        #expect(try phone.receiveSession(SessionPulse(session, phase: .open)) == .unchanged)
        #expect(try phone.liveSession(dayKey: "cb_b", date: Self.date, userId: Self.userId) == nil)
    }

    @Test("a discard removes the row — and only for its own account")
    func discardRemovesTheRow() throws {
        let phone = try AppDatabase.inMemory(deviceId: "phone")
        let watch = try AppDatabase.inMemory(deviceId: "watch")
        let session = try opened(on: phone)
        _ = try watch.receiveSession(SessionPulse(session, phase: .open))

        var stranger = SessionPulse(session, phase: .discarded)
        stranger.userId = "44444444-4444-4444-4444-444444444444"
        #expect(try watch.receiveSession(stranger) == .unchanged)
        #expect(try watch.session(id: session.id, userId: Self.userId) != nil)

        #expect(try watch.receiveSession(SessionPulse(session, phase: .discarded)) == .discarded)
        #expect(try watch.session(id: session.id, userId: Self.userId) == nil)
        #expect(try watch.receiveSession(SessionPulse(session, phase: .discarded)) == .unchanged)
    }

    /// The wrist's "throw this away" can cross the phone's finish in flight.
    /// The phone has already closed, ledgered and queued the workout by then;
    /// the finish wins.
    @Test("a discard never deletes a finished workout")
    func finishBeatsDiscard() throws {
        let phone = try AppDatabase.inMemory(deviceId: "phone")
        let session = try opened(on: phone)
        try phone.appendSet(sessionId: session.id, snapshot(1))
        try phone.closeSession(id: session.id)

        #expect(try phone.receiveSession(SessionPulse(session, phase: .discarded)) == .unchanged)
        #expect(try phone.session(id: session.id, userId: Self.userId)?.endedAt != nil)
        #expect(try phone.sets(sessionId: session.id, userId: Self.userId).count == 1)
    }

    /// The open travels twice — messaged and queued — in no order. Start then
    /// an immediate Cancel must stay cancelled whichever copy lands last.
    @Test("a late open never revives a discarded session — here or on the other device")
    func lateOpenAfterDiscardIsRefused() throws {
        let phone = try AppDatabase.inMemory(deviceId: "phone")
        let watch = try AppDatabase.inMemory(deviceId: "watch")
        let session = try opened(on: phone)
        let open = SessionPulse(session, phase: .open)
        #expect(try watch.receiveSession(open) == .opened(superseded: nil))

        // The wrist throws it away itself; the queued copy then lands.
        try watch.discardSession(id: session.id, userId: Self.userId)
        #expect(try watch.receiveSession(open) == .unchanged)
        #expect(try watch.liveSession(dayKey: "cb_b", date: Self.date, userId: Self.userId) == nil)

        // The phone discards; the wrist hears the discard before a late open.
        let other = try AppDatabase.inMemory(deviceId: "watch2")
        #expect(try other.receiveSession(open) == .opened(superseded: nil))
        #expect(try other.receiveSession(SessionPulse(session, phase: .discarded)) == .discarded)
        #expect(try other.receiveSession(open) == .unchanged)
        #expect(try other.session(id: session.id, userId: Self.userId) == nil)
    }

    @Test("a join is about the other device's runtime — it never makes a row")
    func joinMakesNoRow() throws {
        let phone = try AppDatabase.inMemory(deviceId: "phone")
        let session = WorkoutSession(id: "55555555-5555-5555-5555-555555555555", userId: Self.userId, dayKey: "cb_b", date: Self.date)
        #expect(try phone.receiveSession(SessionPulse(session, phase: .joined)) == .unchanged)
        #expect(try phone.session(id: session.id, userId: Self.userId) == nil)
    }

    /// Start on the phone with the watch app closed; open it and tap Start
    /// before the queued open lands. Each device now holds a live row for one
    /// split, and each applies the same rule to the other's open.
    @Test("two opens of one split converge on the earlier, and the empty loser goes")
    func oneSplitOneWinner() throws {
        let phone = try AppDatabase.inMemory(deviceId: "phone")
        let watch = try AppDatabase.inMemory(deviceId: "watch")
        let early = try phone.openSession(
            userId: Self.userId, dayKey: "cb_b", date: Self.date, startedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
        let late = try watch.openSession(
            userId: Self.userId, dayKey: "cb_b", date: Self.date, startedAt: Date(timeIntervalSince1970: 1_790_000_030)
        )

        // The watch hears the phone's: the phone's is earlier, the wrist's is
        // empty, so the wrist's goes — and the outcome names it, so the watch
        // can tell the phone.
        guard case .opened(let superseded) = try watch.receiveSession(SessionPulse(early, phase: .open)) else {
            Issue.record("the phone's open did not land on the watch")
            return
        }
        #expect(superseded?.id == late.id)
        #expect(try watch.session(id: late.id, userId: Self.userId) == nil)
        #expect(try watch.liveSession(dayKey: "cb_b", date: Self.date, userId: Self.userId)?.id == early.id)

        // The phone hears the wrist's: it LOSES, so nothing local goes. The
        // row lands (the wrist's discard pulse is what removes it), and the
        // phone's own is still the live one.
        #expect(try phone.receiveSession(SessionPulse(late, phase: .open)) == .opened(superseded: nil))
        #expect(try phone.liveSession(dayKey: "cb_b", date: Self.date, userId: Self.userId)?.id == early.id)
        #expect(try phone.receiveSession(SessionPulse(late, phase: .discarded)) == .discarded)
        #expect(try phone.session(id: late.id, userId: Self.userId) == nil)
    }

    /// The wire carries whole seconds (`OnyxJSON` is ISO-8601 without a
    /// fraction) and each store keeps milliseconds. Two Starts inside one
    /// second must still leave exactly ONE workout, and the same one, on both
    /// devices — compared raw, each device saw the other as earlier and both
    /// discarded their own.
    @Test("two Starts in the same second agree on one winner after the wire")
    func sameSecondStartsAgree() throws {
        let phone = try AppDatabase.inMemory(deviceId: "phone")
        let watch = try AppDatabase.inMemory(deviceId: "watch")
        let p = try phone.openSession(
            userId: Self.userId, dayKey: "cb_b", date: Self.date, startedAt: Date(timeIntervalSince1970: 1_790_000_000.7)
        )
        let w = try watch.openSession(
            userId: Self.userId, dayKey: "cb_b", date: Self.date, startedAt: Date(timeIntervalSince1970: 1_790_000_000.3)
        )
        func wire(_ s: WorkoutSession) throws -> SessionPulse {
            try OnyxJSON.decoder.decode(SessionPulse.self, from: OnyxJSON.encoder.encode(SessionPulse(s, phase: .open)))
        }
        _ = try watch.receiveSession(try wire(p))
        _ = try phone.receiveSession(try wire(w))

        let winner = min(p.id, w.id)
        let loser = max(p.id, w.id)
        for device in [phone, watch] {
            #expect(try device.session(id: winner, userId: Self.userId) != nil, "the winner is gone on a device")
        }
        // The loser's owner discarded it; the other still holds a copy until
        // the owner's discard pulse lands — never zero workouts, anywhere.
        let owner = loser == p.id ? phone : watch
        #expect(try owner.session(id: loser, userId: Self.userId) == nil)
    }

    @Test("a loser with a set logged into it is never discarded")
    func loggedLoserStays() throws {
        let phone = try AppDatabase.inMemory(deviceId: "phone")
        let watch = try AppDatabase.inMemory(deviceId: "watch")
        let early = try phone.openSession(
            userId: Self.userId, dayKey: "cb_b", date: Self.date, startedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
        let late = try watch.openSession(
            userId: Self.userId, dayKey: "cb_b", date: Self.date, startedAt: Date(timeIntervalSince1970: 1_790_000_030)
        )
        try watch.appendSet(sessionId: late.id, snapshot(1))

        #expect(try watch.receiveSession(SessionPulse(early, phase: .open)) == .opened(superseded: nil))
        #expect(try watch.sets(sessionId: late.id, userId: Self.userId).count == 1)
    }

    /// The wire half. A watch runs an older build than its phone routinely,
    /// and an optional that stops being optional is a pulse that stops
    /// decoding in silence.
    @Test("a pulse round-trips, and an open puts no close fields on the wire")
    func pulseRoundTrips() throws {
        let session = WorkoutSession(
            id: "33333333-3333-3333-3333-333333333333", userId: Self.userId, dayKey: "cb_b",
            date: Self.date, startedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
        let open = SessionPulse(session, phase: .open)
        let object = try #require(
            try JSONSerialization.jsonObject(with: try OnyxJSON.encoder.encode(open)) as? [String: Any]
        )
        #expect(object.keys.sorted() == ["date", "dayKey", "phase", "sessionId", "startedAt", "userId"])
        #expect(try OnyxJSON.decoder.decode(SessionPulse.self, from: try OnyxJSON.encoder.encode(open)) == open)
    }
}
