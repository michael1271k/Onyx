import Foundation
import GRDB
import Testing
import OnyxCore
@testable import OnyxData

/// W10 — the fatigue card's "after training" flips on the day's session end.
///
/// The one case a pure test cannot see: two sessions on one date, one closed
/// and one open. `MAX(ended_at)` alone answers the closed one's finish while
/// the second is mid-set, and the card would ask "after" during the session.
@Suite("Session ended stream")
@MainActor
struct SessionEndedStreamTests {

    private let user = "u1"
    private let date = "2026-09-17"

    private func first(_ db: AppDatabase) async throws -> Date? {
        for try await ended in db.sessionEndedStream(userId: user, date: date) { return ended }
        return nil
    }

    private func insert(_ db: AppDatabase, id: String, ended: Date?) throws {
        try db.writer.write { g in
            try WorkoutSession(
                id: id, userId: user, dayKey: "legs_a", date: date,
                startedAt: Date(timeIntervalSince1970: 1_789_000_000), endedAt: ended
            ).insert(g)
        }
    }

    @Test("no session, no end; one closed session, its end")
    func noneThenOne() async throws {
        let db = try AppDatabase.inMemory(deviceId: "t")
        let none = try await first(db)
        #expect(none == nil)
        let ended = Date(timeIntervalSince1970: 1_789_003_600)
        try insert(db, id: "a", ended: ended)
        let one = try await first(db)
        #expect(one == ended)
    }

    @Test("an open session on a two-a-day means not ended, whatever the morning did")
    func openSessionWins() async throws {
        let db = try AppDatabase.inMemory(deviceId: "t")
        try insert(db, id: "a", ended: Date(timeIntervalSince1970: 1_789_003_600))
        try insert(db, id: "b", ended: nil)
        let open = try await first(db)
        #expect(open == nil)
        // Closing it answers with the LATER finish.
        let later = Date(timeIntervalSince1970: 1_789_020_000)
        try await db.writer.write { g in
            try g.execute(sql: "UPDATE workout_sessions SET ended_at = ? WHERE id = 'b'", arguments: [later])
        }
        let closed = try await first(db)
        #expect(closed == later)
    }
}
