import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// Cancel — the discard path a finished-session edit never had.
///
/// Every edit in the editor lands in its own transaction the moment it is made,
/// so "cancel" cannot mean "do not commit the draft"; there is no draft. It
/// means writing the compensating events that put the log back, and the whole
/// question is whether the fold can express that — `SetEventFold`'s rule 3 says
/// a `void` is terminal, so a restored set cannot come back under its own id.
@Suite("Cancelling an edit")
struct SessionRevertTests {

    private let user = "u1"
    /// Two dates, after `PrSeed.cutoff` and off `assertedDates`, so the ledger
    /// here is DERIVED by the engine rather than read out of the seed table.
    private let older = "2026-08-10"
    private let newer = "2026-08-24"
    private let lift = "helix5-bench-press"
    private let walk = "helix5-treadmill"

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    /// An older, LIGHTER bench session and the one under edit — which opens
    /// with a treadmill bout, because a cardio row is the case a patch cannot
    /// express and therefore the case the revert has to get right.
    ///
    /// Written straight to the tables, no `set_events`: the shape of a session
    /// logged on the web and pulled down here, which is also the shape whose
    /// first edit seeds a log.
    private func history(_ db: AppDatabase) throws {
        try db.writer.write { conn in
            try Exercise(id: lift, name: "Bench Press").insert(conn)
            try Exercise(id: walk, name: "Treadmill").insert(conn)
            for (id, date, loads) in [("s-old", older, [60.0, 50.0]), ("s1", newer, [80.0, 80.0, 80.0])] {
                let start = LogicalDay.date(fromISO: date)!
                try WorkoutSession(
                    id: id, userId: user, dayKey: "cb_a", date: date,
                    startedAt: start, endedAt: start.addingTimeInterval(3600), durationMin: 60
                ).insert(conn)
                for (i, weight) in loads.enumerated() {
                    try WorkoutSet(
                        id: "\(id)-\(i + 1)", sessionId: id, exerciseId: lift,
                        setIndex: i + 1, weightKg: weight, reps: 5, exerciseOrder: 1
                    ).insert(conn)
                }
            }
            // Five minutes at incline 2 for 0.37 km — `0kg × 0` to any reader
            // that only has the two columns, which is exactly why `SetPatch`
            // cannot put it back.
            try WorkoutSet(
                id: "s1-walk", sessionId: "s1", exerciseId: walk, setIndex: 1,
                weightKg: 0, reps: 0, setType: "warmup", exerciseOrder: 0,
                durationSec: 300, incline: 2, distanceKm: 0.37
            ).insert(conn)

            // ── THE LEDGER IS SEEDED BY `replay`, NOT BY `recomputeAll` ─────
            // Both build it and they do NOT agree — `replay`'s own header says
            // so and calls `record` the narrow one. `record` judges a session
            // against every OTHER session, so the oldest one is measured
            // against its own future and files records; `replay` walks forward
            // and judges each session only against what came before, so the
            // first session in a history files nothing.
            //
            // Every path in the editor — an amend, an add, a delete, and now a
            // revert — goes through `replay`. Seeding the fixture with
            // `recomputeAll` would compare two different functions' answers and
            // read the difference as a defect in Cancel: the FIRST edit of the
            // sitting already rewrites the ledger into replay's frame, and did
            // so long before Cancel existed. The asymmetry is real and it is
            // filed against `record`; it is not what these tests are about.
            for key in ["Bench Press", "Treadmill"] {
                _ = try PrRecorder.replay(conn, userId: user, exerciseKey: key)
            }
        }
        // The aggregates as the client that logged it would have left them.
        try db.updateMetrics(sessionId: "s1")
    }

    /// The session's sets as CONTENT, order-independent.
    ///
    /// Not by id: a restored set carries a new one by design (see
    /// `SessionEditing.revertPlan`), so an id-wise comparison would fail on a
    /// revert that is byte-perfect about everything a reader can see.
    private func contents(_ db: AppDatabase, _ sessionId: String = "s1") throws -> [String] {
        try db.writer.read { conn in
            try WorkoutSet
                .filter(Column("session_id") == sessionId)
                .fetchAll(conn)
                .map { String(describing: SetSnapshot($0)) }
                .sorted()
        }
    }

    private func aggregates(_ db: AppDatabase) throws -> [Double] {
        let session = try #require(try db.session(id: "s1"))
        return [
            session.totalVolumeKg ?? -1,
            Double(session.setCount ?? -1),
            Double(session.prCount ?? -1),
        ]
    }

    /// The ledger for both movements, keyed as `personal_records` keys it.
    private func records(_ db: AppDatabase) throws -> [String: Double] {
        try db.writer.read { conn in
            Dictionary(
                try PersonalRecordRow
                    .filter(Column("user_id") == user)
                    .fetchAll(conn)
                    .map { ("\($0.exerciseKey)/\($0.axis)", $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    /// One sitting: a load corrected, a set added, a set deleted.
    private func edits(_ db: AppDatabase) throws {
        // 120 beats everything in the history, so this CLAIMS a record the
        // revert has to take back — the direction `record` alone cannot go.
        _ = try db.amendSet(sessionId: "s1", setId: "s1-1", weightKg: 120, est1rmKg: 140)
        _ = try db.addSet(
            sessionId: "s1",
            SetSnapshot(exerciseId: lift, setIndex: 4, weightKg: 75, reps: 8, exerciseOrder: 1),
            setId: "s1-added"
        )
        _ = try db.deleteSet(sessionId: "s1", setId: "s1-3")
    }

    // MARK: - The headline

    @Test("Cancel returns every aggregate, every set row and the PR ledger")
    func cancelPutsTheSessionBack() throws {
        let db = try store()
        try history(db)
        let beforeRows = try contents(db)
        let beforeTotals = try aggregates(db)
        let beforeLedger = try records(db)
        // Non-vacuous on the ledger side: there IS something to give back.
        #expect(beforeLedger["Bench Press/weight"] == 80)

        try db.markEditStart(sessionId: "s1")
        try edits(db)
        // Nor on the others: the sitting really did move all three.
        #expect(try aggregates(db) != beforeTotals)
        #expect(try contents(db) != beforeRows)
        #expect(try records(db)["Bench Press/weight"] == 120)

        let outcome = try #require(try db.revertSessionEdits(sessionId: "s1"))
        #expect(outcome.sessionId == "s1")
        #expect(outcome.replayed == ["Bench Press"])
        #expect(try contents(db) == beforeRows)
        #expect(try aggregates(db) == beforeTotals)
        #expect(try records(db) == beforeLedger)
    }

    @Test("Save does not — the edits stand, which is the point of having two verbs")
    func saveKeepsTheEdits() throws {
        let db = try store()
        try history(db)
        let beforeRows = try contents(db)
        let beforeTotals = try aggregates(db)
        let beforeLedger = try records(db)

        try db.markEditStart(sessionId: "s1")
        try edits(db)
        // Save is `updateMetrics` plus the cascade; it never reverts.
        try db.updateMetrics(sessionId: "s1", sessionRpe: 8)
        try db.clearEditMark(sessionId: "s1")

        #expect(try contents(db) != beforeRows)
        #expect(try aggregates(db) != beforeTotals)
        #expect(try records(db) != beforeLedger)
        // And the mark is gone, so a later sitting's Cancel cannot reach back
        // through this one.
        #expect(try db.editMark(sessionId: "s1") == nil)
        #expect(try db.revertSessionEdits(sessionId: "s1") == nil)
        #expect(try contents(db) != beforeRows)
    }

    // MARK: - The crash case

    @Test("the watermark survives being re-read from the store")
    func theMarkIsPersisted() throws {
        let db = try store()
        try history(db)
        let beforeRows = try contents(db)

        let opened = try db.markEditStart(sessionId: "s1")
        #expect(opened.deviceId == "device-a")
        try edits(db)

        // The seed pushed the mark past its own restatement of the pulled rows
        // (see `seedEventLog`) — that is the one thing allowed to move it.
        let mark = try #require(try db.editMark(sessionId: "s1"))
        #expect(mark.deviceId == opened.deviceId)

        // What re-opening the editor after a jetsam does: the mark is read back
        // off disk, not held in memory, and `markEditStart` hands the SAME one
        // back rather than moving it forward over the edits it has to undo.
        #expect(try db.markEditStart(sessionId: "s1") == mark)
        #expect(try db.editMark(sessionId: "s1") == mark)

        // And the revert that survives the crash is a whole one.
        _ = try db.revertSessionEdits(sessionId: "s1")
        #expect(try contents(db) == beforeRows)
    }

    @Test("a second Cancel is a no-op, not a second round of new ids")
    func revertIsIdempotent() throws {
        let db = try store()
        try history(db)
        try db.markEditStart(sessionId: "s1")
        try edits(db)
        _ = try db.revertSessionEdits(sessionId: "s1")
        let restored = try contents(db)
        let ids = try db.writer.read { conn in
            try String.fetchAll(conn, sql: "SELECT id FROM workout_sets WHERE session_id = 's1'").sorted()
        }

        #expect(try db.revertSessionEdits(sessionId: "s1") == nil)
        #expect(try contents(db) == restored)
        let after = try db.writer.read { conn in
            try String.fetchAll(conn, sql: "SELECT id FROM workout_sets WHERE session_id = 's1'").sorted()
        }
        #expect(after == ids)
    }

    // MARK: - The other device

    @Test("a revert leaves another device's concurrent events standing")
    func anotherDeviceKeepsItsSets() throws {
        let db = try store()
        try history(db)
        try db.markEditStart(sessionId: "s1")
        try edits(db)

        // The watch logs a fourth bench set while the phone is editing. Its
        // `seq` is above the phone's mark on purpose — that is the collision
        // the watermark's device half exists to survive.
        try db.ingest([
            SetEvent(
                id: "evt-watch", sessionId: "s1", setId: "watch-set",
                deviceId: "device-b", seq: 9_000,
                body: .append(
                    SetSnapshot(exerciseId: lift, setIndex: 9, weightKg: 65, reps: 12, exerciseOrder: 1)
                )
            )
        ])
        #expect(try contents(db).contains { $0.contains("65.0") })

        _ = try db.revertSessionEdits(sessionId: "s1")
        let after = try contents(db)
        #expect(after.contains { $0.contains("65.0") })
        // The phone's own sitting is gone, and nothing else with it: three
        // bench sets, the treadmill bout, and the watch's set.
        #expect(after.count == 5)
        #expect(!after.contains { $0.contains("120.0") })
    }

    // MARK: - The case a patch cannot express

    @Test("a voided cardio row comes back whole — duration, incline and distance")
    func aVoidedCardioRowIsRestoredInFull() throws {
        let db = try store()
        try history(db)
        try db.markEditStart(sessionId: "s1")

        _ = try db.deleteSet(sessionId: "s1", setId: "s1-walk")
        #expect(try db.writer.read { conn in
            try WorkoutSet.filter(Column("session_id") == "s1" && Column("exercise_id") == walk)
                .fetchCount(conn)
        } == 0)

        _ = try db.revertSessionEdits(sessionId: "s1")

        let bout = try #require(try db.writer.read { conn in
            try WorkoutSet
                .filter(Column("session_id") == "s1" && Column("exercise_id") == walk)
                .fetchOne(conn)
        })
        // A new id — rule 3 is terminal and the fold will not take the old one
        // back. Everything a reader can see is the same.
        #expect(bout.id != "s1-walk")
        #expect(bout.durationSec == 300)
        #expect(bout.incline == 2)
        #expect(bout.distanceKm == 0.37)
        #expect(bout.setType == "warmup")
        #expect(bout.setIndex == 1)
        #expect(bout.exerciseOrder == 0)
    }

    @Test("an amended cardio axis is reverted by void-and-append, not by a lossy patch")
    func anAmendedCardioRowIsNotPatchedBack() throws {
        let db = try store()
        try history(db)
        try db.markEditStart(sessionId: "s1")

        // `SetPatch` has no `duration_sec`, so the only way back is a void and
        // a re-append. The edit itself goes through the log the same way the
        // logger's own does: void the row, append the corrected one.
        _ = try db.deleteSet(sessionId: "s1", setId: "s1-walk")
        _ = try db.addSet(
            sessionId: "s1",
            SetSnapshot(
                exerciseId: walk, setIndex: 1, weightKg: 0, reps: 0, setType: "warmup",
                exerciseOrder: 0, durationSec: 1_800, incline: 8, distanceKm: 3.2
            ),
            setId: "s1-walk-fixed"
        )
        _ = try db.revertSessionEdits(sessionId: "s1")

        let bout = try #require(try db.writer.read { conn in
            try WorkoutSet
                .filter(Column("session_id") == "s1" && Column("exercise_id") == walk)
                .fetchOne(conn)
        })
        #expect(bout.durationSec == 300)
        #expect(bout.incline == 2)
        #expect(bout.distanceKm == 0.37)
    }

    // MARK: - The planner, with no store under it

    @Test("the plan reads the diff, and a lossless change is an amend rather than a new id")
    func aPatchableChangeKeepsItsId() throws {
        let snapshot = SetSnapshot(exerciseId: lift, setIndex: 1, weightKg: 80, reps: 5)
        let events = [
            SetEvent(id: "e1", sessionId: "s", setId: "a", deviceId: "device-a", seq: 1,
                     body: .append(snapshot)),
            SetEvent(id: "e2", sessionId: "s", setId: "a", deviceId: "device-a", seq: 7,
                     body: .amend(SetPatch(weightKg: 120))),
        ]
        let plan = SessionEditing.revertPlan(
            events: events, sessionId: "s",
            mark: .init(sessionId: "s", deviceId: "device-a", seq: 1)
        )
        #expect(plan.touched == [lift])
        guard case .amend(let setId, let patch) = try #require(plan.steps.first) else {
            Issue.record("a weight correction is patchable and must not churn the id")
            return
        }
        #expect(setId == "a")
        #expect(patch.weightKg == 80)
        #expect(plan.steps.count == 1)
    }

    @Test("clearing an rpe is not patchable, so the planner voids and re-appends")
    func clearingARatingIsNotPatchable() throws {
        // `SetPatch.rpe` reads nil as UNCHANGED and has no sentinel, so an edit
        // that RATED an unrated set cannot be undone by a patch.
        let snapshot = SetSnapshot(exerciseId: lift, setIndex: 1, weightKg: 80, reps: 5)
        let events = [
            SetEvent(id: "e1", sessionId: "s", setId: "a", deviceId: "device-a", seq: 1,
                     body: .append(snapshot)),
            SetEvent(id: "e2", sessionId: "s", setId: "a", deviceId: "device-a", seq: 7,
                     body: .amend(SetPatch(rpe: 9))),
        ]
        let plan = SessionEditing.revertPlan(
            events: events, sessionId: "s",
            mark: .init(sessionId: "s", deviceId: "device-a", seq: 1)
        )
        #expect(plan.steps == [.void(setId: "a"), .restore(snapshot)])
    }
}
