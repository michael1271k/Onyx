import Foundation
import GRDB
import Testing
@testable import OnyxData

/// What `v17.adoptRepairedSessions` is for.
///
/// ── THE HOLE IT CLOSES ──────────────────────────────────────────────────────
/// `applyPulledSets` skips any session that has local `set_events`, because its
/// sets are a fold over them and pulled rows would be deleted by the very next
/// append. That is right for a session this device is still logging, and it has
/// no exception — so a session repaired directly in the database can never
/// reach the device that logged it. 2026-09-07 was exactly that: sixteen of
/// twenty-one weighted sets had survived the tombstoned-`storeId` void bug, and
/// the fix was applied server-side.
///
/// The migration's whole mechanism is "drop the local fold, then let the
/// ordinary pull path adopt the server copy". This asserts both halves — that
/// the guard really does refuse while events exist, and that clearing them is
/// really enough — because a migration that deleted rows the puller then
/// declined to refill would be strictly worse than the stale fold it replaced.
@Suite("A session repaired on the server")
struct RepairedSessionTests {

    private let user = "u1"

    private func remoteSet(_ id: String, session: String, setNumber: Int, order: Int?) -> RemoteSetRow {
        RemoteSetRow(
            id: id, sessionId: session, exerciseId: "onyx-leg-press", userId: user,
            setNumber: setNumber, weightKg: 75, reps: 13, setType: "normal",
            side: nil, pairId: nil, est1rmKg: 107.5, rpe: 8.5, exerciseOrder: order
        )
    }

    @Test("the pull refuses it while local events exist, and adopts it once they are gone")
    func adoptsAfterTheFoldIsCleared() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let session = try db.openSession(userId: user, dayKey: "legs_a", date: "2026-09-07")

        // The device's own truncated log: ONE set, the state the founder's
        // phone was left in.
        try db.appendSet(
            sessionId: session.id, setId: "local-1",
            SetSnapshot(
                exerciseId: "onyx-leg-press", setIndex: 1,
                weightKg: 75, reps: 13, exerciseOrder: nil
            )
        )
        #expect(try db.sets(sessionId: session.id).count == 1)

        // The server's repaired copy: three sets, carrying the deck order the
        // local rows never had.
        let repaired = [
            remoteSet("srv-1", session: session.id, setNumber: 1, order: 1),
            remoteSet("srv-2", session: session.id, setNumber: 2, order: 1),
            remoteSet("srv-3", session: session.id, setNumber: 3, order: 1),
        ]

        // THE GUARD. Not "nothing happened by accident" — the pull is asked to
        // apply three rows and reports writing none of them.
        #expect(try db.applyPulledSets(repaired) == 0)
        #expect(try db.sets(sessionId: session.id).count == 1)

        // What the migration does, and nothing else.
        try db.writer.write { conn in
            try conn.execute(
                sql: "DELETE FROM set_events WHERE session_id = ?", arguments: [session.id]
            )
            try conn.execute(
                sql: "DELETE FROM workout_sets WHERE session_id = ?", arguments: [session.id]
            )
        }

        #expect(try db.applyPulledSets(repaired) == 3)
        let adopted = try db.sets(sessionId: session.id)
        #expect(adopted.count == 3)
        // The order came across. A repair that landed the rows and dropped the
        // column would leave the report grouping the workout by set number
        // again, which is the defect the repair exists to end.
        #expect(adopted.allSatisfy { $0.exerciseOrder == 1 })
    }

    @Test("the cursor is dropped too, or the rows are cleared and never refilled")
    func rewindsTheCursor() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")

        // A device that has synced since the repair: its cursor is already past
        // the repaired `updated_at`, so a delta pull would not return the
        // session at all.
        try db.setMirrorCursor(table: "workout_sessions", to: Date(), at: Date())
        #expect(try db.mirrorCursor(table: "workout_sessions") != nil)

        try db.writer.write { conn in
            try conn.execute(
                sql: "DELETE FROM sync_cursors WHERE table_name IN ('workout_sessions', 'workout_sets')"
            )
        }
        #expect(try db.mirrorCursor(table: "workout_sessions") == nil)
    }
}
