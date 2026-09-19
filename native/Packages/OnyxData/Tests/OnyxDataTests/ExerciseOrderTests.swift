import Foundation
import GRDB
import Testing
@testable import OnyxData

/// `workout_sets.exercise_order`, from the migration to the wire.
///
/// ── WHY ONE TEST AND NOT FOUR ───────────────────────────────────────────────
/// The column is a single fact travelling through four layers, and the failure
/// that shipped was a HOLE between two of them, not a bug inside one: the local
/// store did not track it, so every phone session uploaded a null and the
/// session report — which orders on this column before `set_number` — read a
/// workout back in whatever order the set numbers implied. Testing the fold and
/// the encoder separately is exactly what would have passed while that hole was
/// open. So this walks one value the whole way: migration → snapshot → fold →
/// projection → amend → wire row.
@Suite("Exercise order")
struct ExerciseOrderTests {

    private let user = "u1"

    private func snapshot(_ order: Int?, setIndex: Int = 1) -> SetSnapshot {
        SetSnapshot(
            exerciseId: "onyx-bench-press", setIndex: setIndex,
            weightKg: 60, reps: 8, exerciseOrder: order
        )
    }

    @Test("v16 adds the column, and it survives a round trip through the log")
    func roundTrips() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")

        // The migration ran. Asked of the schema rather than of a row, because
        // a missing column is what `v16` exists to add and a `nil` read back
        // from a row would not tell the two apart.
        let columns = try db.writer.read { try $0.columns(in: "workout_sets").map(\.name) }
        #expect(columns.contains("exercise_order"))

        let session = try db.openSession(userId: user, dayKey: "cb_a", date: "2026-09-07")

        // Third movement in the deck. Dense from 0, like `buildCommitPayload`
        // on the web — the two clients write one column and a second numbering
        // scheme would interleave a session logged half on each.
        try db.appendSet(sessionId: session.id, setId: "set-1", snapshot(2))
        #expect(try db.sets(sessionId: session.id).first?.exerciseOrder == 2)

        // The drag. `moveExercise` re-amends every logged row of every movement
        // the move shifted, and this is the write it makes — no new
        // `SetEvent.Kind`, which is a one-way door, just a field on the patch
        // the amend already carries.
        try db.amendSet(sessionId: session.id, setId: "set-1", SetPatch(exerciseOrder: 0))
        let moved = try db.sets(sessionId: session.id)
        #expect(moved.first?.exerciseOrder == 0)
        // And the amend changed NOTHING else. A patch that quietly restated the
        // load would make a reorder a way to lose a set's weight.
        #expect(moved.first?.weightKg == 60)
        #expect(moved.first?.reps == 8)

        // ── AND IT REACHES POSTGRES ─────────────────────────────────────────
        // The whole point. `exercise_order` was omitted from this payload with
        // the comment "the local store does not track it", which was true and
        // is what made every phone-logged session unorderable.
        let json = try JSONSerialization.jsonObject(
            with: OnyxJSON.encoder.encode(
                try SyncTranslation.setRow(moved[0], userId: user, exerciseId: "uuid-1")
            )
        ) as? [String: Any]
        #expect(json?["exercise_order"] as? Int == 0)
        // Still not sent, and for a reason that outlived the PR engine being
        // ported: a record is not a property of a set at the moment it is
        // logged — a later set supersedes it and `PrRecorder` can retract it —
        // so a flag frozen into the append payload goes stale inside the same
        // workout. `false` here would overwrite a record the web app filed.
        #expect(json?["is_pr"] == nil)
    }

    @Test("a set logged before v16 says nothing, rather than claiming it opened the workout")
    func absentIsNotZero() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let session = try db.openSession(userId: user, dayKey: "cb_a", date: "2026-09-07")
        try db.appendSet(sessionId: session.id, setId: "old", snapshot(nil))

        // Null, not 0. Every row this store held before the migration means
        // "nobody said", and a default of 0 would have every one of them claim
        // the first slot of its workout.
        #expect(try db.sets(sessionId: session.id).first?.exerciseOrder == nil)

        let json = try JSONSerialization.jsonObject(
            with: OnyxJSON.encoder.encode(try SyncTranslation.setRow(
                try #require(db.sets(sessionId: session.id).first),
                userId: user, exerciseId: "uuid-1"
            ))
        ) as? [String: Any]
        // WRITTEN as null rather than omitted: a batch is one session's sets and
        // PostgREST rejects a body whose objects disagree about keys, which
        // would fail the whole session rather than one column of one row.
        #expect(json?.keys.contains("exercise_order") == true)
        #expect(json?["exercise_order"] is NSNull)
    }
}
