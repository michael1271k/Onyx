import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// Editing a workout that is already history — and the PR retraction that
/// nothing in this app could do before it.
@Suite("Editing a closed session")
struct SessionEditingTests {

    private let user = "u1"
    /// Both after `PrSeed.cutoff` and off `assertedDates`, so the records here
    /// are DERIVED by the engine rather than read out of the seed table.
    private let older = "2026-08-10"
    private let newer = "2026-08-24"
    private let lift = "onyx-bench-press"

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    /// Two finished bench sessions, the older one heavier. Written straight to
    /// the tables — no `set_events` — which is exactly the shape a session
    /// logged on the WEB and pulled down here has.
    private func history(_ db: AppDatabase) throws {
        try db.writer.write { conn in
            try Exercise(id: lift, name: "Bench Press").insert(conn)
            // The older session is the heavier one and its FIRST set is the
            // heaviest thing in the history — so lowering that one set is what
            // the retraction has to notice. Its second set is deliberately
            // lighter than the newer session's, or the record would simply
            // stay where it is and prove nothing.
            for (id, date, loads) in [("s-old", older, [100.0, 70.0]), ("s-new", newer, [80.0, 80.0])] {
                let start = LogicalDay.date(fromISO: date)!
                try WorkoutSession(
                    id: id, userId: user, dayKey: "cb_a", date: date,
                    startedAt: start, endedAt: start.addingTimeInterval(3600), durationMin: 60
                ).insert(conn)
                for (i, weight) in loads.enumerated() {
                    try WorkoutSet(
                        id: "\(id)-\(i + 1)", sessionId: id, exerciseId: lift,
                        setIndex: i + 1, weightKg: weight, reps: 5
                    ).insert(conn)
                }
            }
            // The ledger as `closeSession` would have left it: replayed in
            // order, so the 100 kg session owns the records.
            _ = try PrRecorder.recomputeAll(conn, userId: user)
        }
    }

    private func records(_ db: AppDatabase) throws -> [String: Double] {
        try db.writer.read { conn in
            Dictionary(
                try PersonalRecordRow
                    .filter(Column("user_id") == user && Column("exercise_key") == "Bench Press")
                    .fetchAll(conn)
                    .map { ($0.axis, $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    // ── THE 2-MINUTE SESSION ────────────────────────────────────────────────
    // `seedEventLog` stamped every seed with `Date()` — the moment of the
    // seed, not of the set. `closeSession` reads `lastSetAt` off exactly those
    // stamps, so a session pulled from the server and closed on the phone was
    // judged against a "last set" that happened at pull time: seeded at the
    // start, closed later, the long-idle guard read `worked ≈ 0` and answered
    // one rest — Pec Deck's 120 s, `duration_min = 2`.
    @Test("a seeded event carries the set's own clock, so a pulled session's duration is its own")
    func seedsCarryTheSetClock() throws {
        let db = try store()
        try history(db)
        let start = LogicalDay.date(fromISO: older)!
        // The server said when the two rows arrived: five and fifteen minutes in.
        try db.seedEventLogs(
            sessionIds: ["s-old"],
            loggedAt: ["s-old-1": start.addingTimeInterval(300), "s-old-2": start.addingTimeInterval(900)]
        )
        let stamps = try db.writer.read { conn in
            try SetEvent.filter(SetEvent.Columns.sessionId == "s-old").fetchAll(conn).map(\.createdAt)
        }
        #expect(Set(stamps) == [start.addingTimeInterval(300), start.addingTimeInterval(900)])

        // Closed an hour in, 45 minutes after the last set: the guard fires and
        // counts the work plus one rest — 15 + 2 — not the hour, not the rest alone.
        let closed = try db.closeSession(id: "s-old", endedAt: start.addingTimeInterval(3600), restTargetSec: 120)
        #expect(closed?.durationMin == 17)
    }

    @Test("a seed with no clock to carry is stamped at the session's start, never at the seed")
    func seedsWithoutAClockFallBackToTheStart() throws {
        let db = try store()
        try history(db)
        try db.seedEventLogs(sessionIds: ["s-new"])
        let stamps = try db.writer.read { conn in
            try SetEvent.filter(SetEvent.Columns.sessionId == "s-new").fetchAll(conn).map(\.createdAt)
        }
        #expect(Set(stamps) == [LogicalDay.date(fromISO: newer)!])

        // And `closeSession` does not mistake that stamp for a last set: closed
        // an hour in with nothing else logged, the answer is the hour, never
        // one rest (the 2-minute bug by another road).
        let start = LogicalDay.date(fromISO: newer)!
        let closed = try db.closeSession(id: "s-new", endedAt: start.addingTimeInterval(3600), restTargetSec: 120)
        #expect(closed?.durationMin == 60)
    }

    // MARK: - The engine rule the fixtures lean on

    @Test("the first session on record sets the bar and wins nothing — a delta against nothing")
    func theFirstSessionIsTheBaseline() throws {
        let db = try store()
        try history(db)
        // 100 kg on 10 August is the oldest set for this lift, so a replay
        // judges it against an empty index and awards no axis. The 80 kg on
        // 24 August is the first thing with a bar to beat — and it does not
        // beat 100, so raising the OLDER session can empty the ledger outright.
        _ = try db.amendSet(sessionId: "s-old", setId: "s-old-1", weightKg: 90)
        #expect(try records(db).isEmpty)
    }

    // MARK: - The retraction

    @Test("lowering the set that set a record retracts it, and the runner-up takes over")
    func loweringASetRetractsThePr() throws {
        let db = try store()
        try history(db)

        let before = try records(db)
        #expect(before[PrAxis.weight.rawValue] == 100, "the 10 August session owns the weight record")

        // The 100 was a typo: it was 60.
        let outcome = try #require(try db.amendSet(sessionId: "s-old", setId: "s-old-1", weightKg: 60))
        #expect(outcome.replayed == ["Bench Press"])
        #expect(outcome.date == older, "the cascade starts at the edited session's own date")

        let after = try records(db)
        #expect(
            after[PrAxis.weight.rawValue] == 80,
            "80 kg from 24 August is now the best — the retracted 100 must not stand"
        )
        // The set itself really changed, through the log.
        let edited = try #require(try db.sets(sessionId: "s-old").first { $0.id == "s-old-1" })
        #expect(edited.weightKg == 60)
        // And the OTHER set of that session is untouched — a seeded log
        // reproduces the session, it does not rewrite it.
        let sibling = try #require(try db.sets(sessionId: "s-old").first { $0.id == "s-old-2" })
        #expect(sibling.weightKg == 70 && sibling.reps == 5)
    }

    @Test("deleting every qualifying set retracts the ledger entirely, and tells the server")
    func deletingTheLastSetClearsTheLedger() throws {
        let db = try store()
        try history(db)
        #expect(!(try records(db)).isEmpty)

        for id in ["s-old-1", "s-old-2"] { _ = try db.deleteSet(sessionId: "s-old", setId: id) }
        for id in ["s-new-1", "s-new-2"] { _ = try db.deleteSet(sessionId: "s-new", setId: id) }

        #expect(try records(db).isEmpty, "no set, no record")
        // An upsert cannot say "there is no record here any more".
        let deletes = try db.pendingOutbox(limit: 200)
            .filter { $0.idempotencyKey.hasPrefix("rowdel:personal_records:") }
        #expect(!deletes.isEmpty, "the retraction has to reach the other client")
    }

    @Test("raising a set still files a record — the replay is not a one-way ratchet down")
    func raisingASetFilesAPr() throws {
        let db = try store()
        try history(db)
        _ = try db.amendSet(sessionId: "s-new", setId: "s-new-1", weightKg: 120)
        #expect(try records(db)[PrAxis.weight.rawValue] == 120)
    }

    // MARK: - Totals

    @Test("the stored aggregates follow the sets, on every edit")
    func totalsAreRecomputed() throws {
        let db = try store()
        try history(db)
        // 2 × (100 × 5) = 1,000 kg over two sets.
        // 100×5 + 70×5 = 850 kg to begin with.
        let amended = try #require(try db.amendSet(sessionId: "s-old", setId: "s-old-1", reps: 10))
        #expect(amended.totalVolumeKg == 1_350, "100×10 + 70×5")
        #expect(amended.setCount == 2)

        let deleted = try #require(try db.deleteSet(sessionId: "s-old", setId: "s-old-1"))
        #expect(deleted.totalVolumeKg == 350)
        #expect(deleted.setCount == 1)

        let added = try #require(try db.addSet(
            sessionId: "s-old",
            SetSnapshot(exerciseId: lift, setIndex: 3, weightKg: 50, reps: 4)
        ))
        #expect(added.totalVolumeKg == 550)
        #expect(added.setCount == 2)

        // And they reach the row the sync pushes, not just the return value.
        let row = try #require(try db.session(id: "s-old"))
        #expect(row.totalVolumeKg == 550 && row.setCount == 2)
    }

    @Test("a unilateral pair counts once and weighs its weaker side, as the web writes it")
    func pairsFollowTheWebsRules() throws {
        let db = try store()
        try db.writer.write { conn in
            try Exercise(id: lift, name: "Bench Press").insert(conn)
            let start = LogicalDay.date(fromISO: newer)!
            try WorkoutSession(
                id: "s", userId: user, dayKey: "cb_a", date: newer,
                startedAt: start, endedAt: start.addingTimeInterval(3600)
            ).insert(conn)
            try WorkoutSet(id: "l", sessionId: "s", exerciseId: lift, setIndex: 1,
                           weightKg: 20, reps: 10, side: "left", pairId: "p").insert(conn)
            try WorkoutSet(id: "r", sessionId: "s", exerciseId: lift, setIndex: 1,
                           weightKg: 22, reps: 10, side: "right", pairId: "p").insert(conn)
        }
        let out = try #require(try db.updateMetrics(sessionId: "s", avgBpm: 130))
        #expect(out.setCount == 1, "one set of work, logged as two rows")
        #expect(out.totalVolumeKg == 200, "the weaker side: 20 × 10")
    }

    // MARK: - The event log

    @Test("editing a pulled session seeds its log, once, without disturbing the rows")
    func seedingIsInvisibleAndHappensOnce() throws {
        let db = try store()
        try history(db)
        let before = try db.sets(sessionId: "s-old").map(\.id)
        #expect(try db.setEvents(sessionId: "s-old").isEmpty, "a pulled session has no log")

        _ = try db.amendSet(sessionId: "s-old", setId: "s-old-1", rpe: 8)
        let seeded = try db.setEvents(sessionId: "s-old")
        #expect(seeded.count == 3, "two appends for the existing rows, one amend")
        #expect(try db.sets(sessionId: "s-old").map(\.id) == before, "same rows, same order")

        _ = try db.amendSet(sessionId: "s-old", setId: "s-old-2", rpe: 9)
        #expect(try db.setEvents(sessionId: "s-old").count == 4, "seeded once, not twice")
    }

    @Test("the seed does not queue an upload for rows the server already has")
    func seedEventsAreBornSynced() throws {
        let db = try store()
        try history(db)
        _ = try db.amendSet(sessionId: "s-old", setId: "s-old-1", weightKg: 95)
        let queued = try db.pendingOutbox(limit: 200)
            .filter { $0.idempotencyKey.hasPrefix("set_event:") }
        #expect(queued.count == 1, "only the amend is news; the two seeds are not")
    }

    // MARK: - Metrics

    @Test("a typed duration survives the close, and the clock stops arguing")
    func editedDurationIsNotReDerived() throws {
        let db = try store()
        try db.writer.write { conn in
            try Exercise(id: lift, name: "Bench Press").insert(conn)
            try WorkoutSession(
                id: "s", userId: user, dayKey: "cb_a", date: newer,
                startedAt: Date(timeIntervalSince1970: 1_787_000_000)
            ).insert(conn)
            try WorkoutSet(id: "s-1", sessionId: "s", exerciseId: lift, setIndex: 1,
                           weightKg: 60, reps: 8).insert(conn)
        }
        _ = try db.setSessionMetrics(id: "s", durationMin: 47)
        let edited = try #require(try db.session(id: "s"))
        #expect(edited.durationMin == 47 && edited.durationEdited)

        // Closing it would ordinarily derive a duration from the clock — here,
        // hours of it. The typed answer stands.
        _ = try db.closeSession(id: "s", endedAt: Date(timeIntervalSince1970: 1_787_030_000))
        #expect(try #require(try db.session(id: "s")).durationMin == 47)
    }

    @Test("a negative duration is clamped, not stored — it is an ACWR input")
    func durationIsClamped() throws {
        let db = try store()
        try history(db)
        _ = try db.updateMetrics(sessionId: "s-old", durationMin: -30)
        #expect(try #require(try db.session(id: "s-old")).durationMin == 0)
    }

    // MARK: - Refusals

    @Test("a live session belongs to the logger and is refused here")
    func liveSessionsAreRefused() throws {
        let db = try store()
        try db.writer.write { conn in
            try Exercise(id: lift, name: "Bench Press").insert(conn)
            try WorkoutSession(id: "live", userId: user, dayKey: "cb_a", date: newer, startedAt: Date()).insert(conn)
            try WorkoutSet(id: "live-1", sessionId: "live", exerciseId: lift, setIndex: 1,
                           weightKg: 60, reps: 8).insert(conn)
        }
        #expect(throws: SessionEditing.EditError.sessionIsLive("live")) {
            _ = try db.amendSet(sessionId: "live", setId: "live-1", weightKg: 70)
        }
    }

    @Test("an amend that changes nothing touches nothing — not even the log seed")
    func emptyAmendIsANoOp() throws {
        let db = try store()
        try history(db)
        let queued = try db.pendingOutbox(limit: 200).count
        #expect(try db.amendSet(sessionId: "s-old", setId: "s-old-1") == nil)
        // Seeding is a ONE-WAY DOOR — it takes the session out of the mirror's
        // reach permanently — so a no-op amend must not open it.
        #expect(try db.setEvents(sessionId: "s-old").isEmpty)
        // The ledger rows `history` filed are already queued; the point is that
        // a no-op amend adds nothing to them.
        #expect(try db.pendingOutbox(limit: 200).count == queued, "and queues no upload")
    }

    // MARK: - What this device does not know

    @Test("a session whose sets were never mirrored keeps the aggregates the web wrote")
    func aPartialMirrorDoesNotOverwriteTheTotals() throws {
        let db = try store()
        try db.writer.write { conn in
            try Exercise(id: lift, name: "Bench Press").insert(conn)
            // The session row landed; its sets did not. `TrainingPuller` pulls
            // the two separately and the second half can fail.
            let start = LogicalDay.date(fromISO: newer)!
            try WorkoutSession(
                id: "orphan", userId: user, dayKey: "cb_a", date: newer,
                startedAt: start, endedAt: start.addingTimeInterval(3600),
                totalVolumeKg: 4_820, setCount: 18, prCount: 2
            ).insert(conn)
        }
        // Typing a heart rate must not rewrite the tonnage of a workout this
        // device cannot see. A confident zero here is worse than no answer.
        let out = try #require(try db.updateMetrics(sessionId: "orphan", avgBpm: 128))
        #expect(out.totalVolumeKg == 0, "what this device can see, honestly reported")
        let row = try #require(try db.session(id: "orphan"))
        #expect(row.avgBpm == 128)
        #expect(row.totalVolumeKg == 4_820, "and what it cannot see is left alone")
        #expect(row.setCount == 18 && row.prCount == 2)

        // Adding one set to a session it holds none of is the same trap: one
        // row is not the workout.
        _ = try db.addSet(
            sessionId: "orphan",
            SetSnapshot(exerciseId: lift, setIndex: 1, weightKg: 60, reps: 8)
        )
        let after = try #require(try db.session(id: "orphan"))
        #expect(after.totalVolumeKg == 4_820 && after.setCount == 18)
    }

    @Test("deleting the last set of a session it DOES hold writes the zero — that one is true")
    func emptyingAKnownSessionWritesZero() throws {
        let db = try store()
        try history(db)
        _ = try db.deleteSet(sessionId: "s-old", setId: "s-old-1")
        let out = try #require(try db.deleteSet(sessionId: "s-old", setId: "s-old-2"))
        #expect(out.totalVolumeKg == 0 && out.setCount == 0)
        let row = try #require(try db.session(id: "s-old"))
        #expect(row.totalVolumeKg == 0 && row.setCount == 0)
    }

    @Test("a live session is never replayed into the ledger")
    func liveSessionsAreOutsideTheReplay() throws {
        let db = try store()
        try history(db)
        // A workout in progress, heavier than anything in the history.
        try db.writer.write { conn in
            try WorkoutSession(
                id: "live", userId: user, dayKey: "cb_a", date: "2026-09-01", startedAt: Date()
            ).insert(conn)
            try WorkoutSet(id: "live-1", sessionId: "live", exerciseId: lift, setIndex: 1,
                           weightKg: 150, reps: 5).insert(conn)
        }
        // Raise the LATER closed session past the earlier one, so the replay
        // has a record to file — and check which set it filed it against.
        _ = try db.amendSet(sessionId: "s-new", setId: "s-new-1", weightKg: 120)
        #expect(
            try records(db)[PrAxis.weight.rawValue] == 120,
            "the 150 is still being logged; `record` files that at close, not this"
        )
    }
}
