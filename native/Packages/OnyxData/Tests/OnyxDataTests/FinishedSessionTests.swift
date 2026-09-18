import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// What a FINISHED session has to survive.
///
/// ── THE BUG THIS SUITE IS ABOUT ─────────────────────────────────────────────
/// A session was finished on the phone and came back with an empty difficulty,
/// a two-beat heart rate, and a Train tab that said "Resume workout" on every
/// relaunch — three symptoms, two causes, and neither of them in the finish
/// path itself.
///
/// `closeSession` writes `ended_at`, `duration_min` and `session_rpe` and THEN
/// queues the row for upload. Until that queue item drains, the server's copy
/// of the session predates the close — and `applyPulledSessions` is a whole-row
/// `save`, so the next delta pull wrote every one of those columns back as they
/// stood before the workout ended. The session re-opened, the rating vanished,
/// and the loop repeated on every foreground until the drain happened to win.
///
/// Separately, nothing bounded what the finish sheet could store: two taps on a
/// `+` from an empty Avg HR cell wrote `avg_bpm = 2` and stamped it MEASURED,
/// which is what takes a session out of `sessionsNeedingMetrics` — so the one
/// mechanism that would have corrected it was switched off by the mistake.
@Suite("A finished session")
struct FinishedSessionTests {

    private let user = "u1"
    private let date = "2026-09-08"

    private func remote(
        _ id: String, endedAt: Date? = nil, durationMin: Int? = nil, sessionRpe: Double? = nil,
        avgBpm: Int? = nil, calories: Int? = nil
    ) -> RemoteSessionRow {
        RemoteSessionRow(
            id: id, userId: user, startedAt: Date(timeIntervalSince1970: 1_757_000_000),
            splitDay: "arms", endedAt: endedAt, dayKey: "arms",
            durationMin: durationMin, sessionRpe: sessionRpe,
            avgBpm: avgBpm, caloriesBurned: calories
        )
    }

    // MARK: - The pull

    @Test("a pull cannot re-open a session this device has closed but not yet pushed")
    func pullDoesNotReopen() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let session = try db.openSession(userId: user, dayKey: "arms", date: date)
        try db.appendSet(
            sessionId: session.id, setId: "set-1",
            SetSnapshot(exerciseId: "helix5-cable-curl", setIndex: 1, weightKg: 20, reps: 10)
        )
        // The finish. This writes the four columns AND queues `session:<id>`.
        try db.closeSession(id: session.id, sessionRpe: 8)
        let closed = try #require(try db.session(id: session.id))
        #expect(closed.endedAt != nil)
        #expect(closed.sessionRpe == 8)

        // The delta pull, arriving before the drain. The server has never heard
        // of the close, so every one of these is null on the wire.
        try db.applyPulledSessions([remote(session.id)])

        let after = try #require(try db.session(id: session.id))
        #expect(after.endedAt != nil, "the close survives — this is the Resume-workout loop")
        #expect(after.sessionRpe == 8, "and so does the rating — this is the empty difficulty")
        #expect(after.durationMin == closed.durationMin)
    }

    @Test("a pull still lands on a session with nothing queued for it")
    func pullWinsWhenNothingIsQueued() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        // A session finished on the WEB and pulled here: the device has no
        // outbox item for it, so the server is the only source there is. The
        // guard must not turn into "the local row always wins", which would
        // stop every web edit from ever reaching the phone.
        let ended = Date(timeIntervalSince1970: 1_757_003_600)
        try db.applyPulledSessions([
            remote("web-1", endedAt: ended, durationMin: 61, sessionRpe: 7, avgBpm: 131, calories: 480)
        ])
        let landed = try #require(try db.session(id: "web-1"))
        #expect(landed.endedAt == ended)
        #expect(landed.sessionRpe == 7)
        #expect(landed.avgBpm == 131)

        // And a later pull may still CHANGE it — the row is the server's.
        try db.applyPulledSessions([
            remote("web-1", endedAt: ended, durationMin: 61, sessionRpe: 9, avgBpm: 140, calories: 480)
        ])
        #expect(try db.session(id: "web-1")?.sessionRpe == 9)
        #expect(try db.session(id: "web-1")?.avgBpm == 140)
    }

    @Test("where this device has nothing, the server's answer still lands on a queued session")
    func serverFillsTheGaps() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let session = try db.openSession(userId: user, dayKey: "arms", date: date)
        try db.appendSet(
            sessionId: session.id, setId: "set-1",
            SetSnapshot(exerciseId: "helix5-cable-curl", setIndex: 1, weightKg: 20, reps: 10)
        )
        try db.closeSession(id: session.id, sessionRpe: 8)
        // The watch's own workout reached the server first. This device has no
        // heart rate at all, so there is nothing of ours to protect and the
        // measurement is the best answer anybody has.
        try db.applyPulledSessions([remote(session.id, avgBpm: 128, calories: 505)])
        let after = try #require(try db.session(id: session.id))
        #expect(after.avgBpm == 128)
        #expect(after.caloriesBurned == 505)
        #expect(after.sessionRpe == 8, "and ours is still ours")
    }

    // MARK: - What the finish sheet may store

    @Test("an implausible heart rate is refused rather than stamped measured")
    func implausibleMetricsAreRefused() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let session = try db.openSession(userId: user, dayKey: "arms", date: date)
        try db.appendSet(
            sessionId: session.id, setId: "set-1",
            SetSnapshot(exerciseId: "helix5-cable-curl", setIndex: 1, weightKg: 20, reps: 10)
        )

        // Two taps on `+` from an empty cell. The column stays NULL, which is
        // what keeps the session inside `sessionsNeedingMetrics`.
        try db.setSessionMetrics(id: session.id, avgBpm: 2, caloriesBurned: 1)
        var row = try #require(try db.session(id: session.id))
        #expect(row.avgBpm == nil)
        #expect(row.caloriesBurned == nil)

        // A real reading goes in and is the athlete's answer.
        try db.setSessionMetrics(id: session.id, avgBpm: 132, caloriesBurned: 495)
        row = try #require(try db.session(id: session.id))
        #expect(row.avgBpm == 132)
        #expect(row.avgBpmEstimated == false)
        #expect(row.caloriesBurned == 495)
        #expect(row.caloriesEstimated == false)
    }

    @Test("a pre-filled figure is stored as an estimate, so the watch can still correct it")
    func prefillStaysCorrectable() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let session = try db.openSession(userId: user, dayKey: "arms", date: date)
        try db.appendSet(
            sessionId: session.id, setId: "set-1",
            SetSnapshot(exerciseId: "helix5-cable-curl", setIndex: 1, weightKg: 20, reps: 10)
        )
        try db.setSessionMetrics(id: session.id, avgBpm: 129, caloriesBurned: 470, measured: false)
        let row = try #require(try db.session(id: session.id))
        #expect(row.avgBpm == 129)
        #expect(row.avgBpmEstimated, "carried over from last session is not measured")
        #expect(row.caloriesEstimated)

        // Which is the whole point: the Health sync's queue still has it.
        try db.closeSession(id: session.id)
        let pending = try db.sessionsNeedingMetrics(
            userId: user, endedAfter: Date(timeIntervalSince1970: 1_756_000_000)
        )
        #expect(pending.contains { $0.id == session.id })
    }

    // MARK: - The pre-fill's own source

    @Test("previousSessionMetrics takes each figure from the most recent session that has it")
    func previousMetrics() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        // Two finished sessions of this split, and a third on a different one.
        // The nearer session has no heart rate, so the figure has to come from
        // the one behind it — three tiles reading "—" because the last session
        // was missing one of them is the state the pre-fill exists to remove.
        try db.applyPulledSessions([
            RemoteSessionRow(
                id: "s-older", userId: user, startedAt: Date(timeIntervalSince1970: 1_756_400_000),
                splitDay: "arms", endedAt: Date(timeIntervalSince1970: 1_756_403_600),
                dayKey: "arms", durationMin: 55, avgBpm: 126, caloriesBurned: 430
            ),
            RemoteSessionRow(
                id: "s-newer", userId: user, startedAt: Date(timeIntervalSince1970: 1_756_900_000),
                splitDay: "arms", endedAt: Date(timeIntervalSince1970: 1_756_903_600),
                dayKey: "arms", durationMin: 62, caloriesBurned: 505
            ),
            RemoteSessionRow(
                id: "s-legs", userId: user, startedAt: Date(timeIntervalSince1970: 1_756_950_000),
                splitDay: "legs", endedAt: Date(timeIntervalSince1970: 1_756_953_600),
                dayKey: "legs_a", durationMin: 90, avgBpm: 150, caloriesBurned: 800
            ),
        ])

        let metrics = try db.previousSessionMetrics(userId: user, dayKey: "arms", before: date)
        #expect(metrics.durationMin == 62)
        #expect(metrics.calories == 505)
        #expect(metrics.avgBpm == 126, "the newer session has none; a Legs day's is not an answer")

        // A day with no history at all proposes nothing. "—" is a better
        // default than somebody else's workout.
        let cold = try db.previousSessionMetrics(userId: user, dayKey: "cb_a", before: date)
        #expect(cold.durationMin == nil)
        #expect(cold.avgBpm == nil)
        #expect(cold.calories == nil)
    }

    // MARK: - The finish sheet's trail (W10)

    /// Four rules in one read, and every one of them has a way to be wrong that
    /// draws a plausible-looking line: the split, the direction, the live
    /// session, and a row whose aggregates were never computed.
    @Test("splitTonnage is this split's finished sessions, oldest first, nils dropped")
    func tonnageTrail() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        try db.applyPulledSessions([
            // Oldest first in the ANSWER; deliberately not in the order given.
            RemoteSessionRow(
                id: "s-newer", userId: user, startedAt: Date(timeIntervalSince1970: 1_756_900_000),
                splitDay: "arms", endedAt: Date(timeIntervalSince1970: 1_756_903_600),
                dayKey: "arms", totalVolumeKg: 9_400
            ),
            RemoteSessionRow(
                id: "s-older", userId: user, startedAt: Date(timeIntervalSince1970: 1_756_400_000),
                splitDay: "arms", endedAt: Date(timeIntervalSince1970: 1_756_403_600),
                dayKey: "arms", totalVolumeKg: 8_200
            ),
            // A Legs day's tonnage is not an answer about an Arms day.
            RemoteSessionRow(
                id: "s-legs", userId: user, startedAt: Date(timeIntervalSince1970: 1_756_950_000),
                splitDay: "legs", endedAt: Date(timeIntervalSince1970: 1_756_953_600),
                dayKey: "legs_a", totalVolumeKg: 19_000
            ),
            // Still being logged: its aggregate is true of half a workout, and
            // plotted as a finished week it would draw every live session as a
            // collapse.
            RemoteSessionRow(
                id: "s-live", userId: user, startedAt: Date(timeIntervalSince1970: 1_757_000_000),
                splitDay: "arms", dayKey: "arms", totalVolumeKg: 1_100
            ),
            // Finished, and nobody ever computed its aggregates. Absent, never
            // a zero — a zero would be a claim that this session weighed
            // nothing.
            RemoteSessionRow(
                id: "s-blank", userId: user, startedAt: Date(timeIntervalSince1970: 1_756_500_000),
                splitDay: "arms", endedAt: Date(timeIntervalSince1970: 1_756_503_600),
                dayKey: "arms"
            ),
        ])

        #expect(
            try db.splitTonnage(userId: user, dayKey: "arms", before: date) == [8_200, 9_400],
            "oldest first, this split only, finished only, and no nil as a zero"
        )
        #expect(try db.splitTonnage(userId: user, dayKey: "cb_a", before: date).isEmpty)
        #expect(try db.splitTonnage(userId: user, dayKey: nil, before: date).isEmpty)
    }
}
