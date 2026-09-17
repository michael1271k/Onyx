import Foundation
import Testing
import GRDB
@testable import OnyxData

/// The half of sign-out that leaves nothing behind.
///
/// ── WHY THIS IS WORTH A TEST AND THE REST OF `signOut()` IS NOT ─────────────
/// The order of `signOut()` — drain, stop, revoke, erase, redraw — lives in
/// `AppEnvironment`, which needs a live Supabase client to exist, so it is
/// verified on a device. `eraseLocalData` is the one piece with real logic in
/// it: it enumerates `sqlite_master` rather than carrying a list of tables, and
/// the whole argument for doing it that way is that a list falls behind the
/// schema silently. A test that seeds several tables and then insists on ZERO
/// rows everywhere is what makes that argument checkable — and it fails the day
/// a new table escapes the sweep, which a hand-written list never would.
@Suite("Sign-out erases the local store")
struct SignOutEraseTests {

    private func seeded() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { conn in
            try Exercise(id: "ex-squat", name: "Back Squat", primaryMuscle: "quads").insert(conn)
            try WorkoutSession(id: "s1", userId: "u1", dayKey: "legs_a", date: "2026-09-02").insert(conn)
        }
        return db
    }

    /// Every user table, by the same rule the erase itself uses. A test that
    /// named the tables would be the list this design exists to avoid.
    private func tableCounts(_ db: AppDatabase) throws -> [String: Int] {
        try db.writer.read { conn in
            let names = try String.fetchAll(conn, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name <> 'grdb_migrations'
                """)
            var counts: [String: Int] = [:]
            for name in names {
                counts[name] = try Int.fetchOne(conn, sql: "SELECT count(*) FROM \"\(name)\"") ?? 0
            }
            return counts
        }
    }

    @Test("no user table keeps a row")
    func everythingGoes() throws {
        let db = try seeded()
        let before = try tableCounts(db)
        #expect(before.values.reduce(0, +) > 0, "the fixture must actually seed something")

        try db.eraseLocalData()

        for (table, count) in try tableCounts(db) {
            #expect(count == 0, "\(table) still holds \(count) row(s) after sign-out")
        }
    }

    @Test("the schema survives, so the next user signs in to a working store")
    func schemaSurvives() throws {
        let db = try seeded()
        let tablesBefore = Set(try tableCounts(db).keys)

        try db.eraseLocalData()

        // Same tables, still writable. Dropping them — or dropping the
        // migration record — would make the next launch re-run the migrator
        // against a store it half-owns.
        #expect(Set(try tableCounts(db).keys) == tablesBefore)
        try db.writer.write { conn in
            try Exercise(id: "ex-new", name: "Leg Press", primaryMuscle: "quads").insert(conn)
        }
        #expect(try db.exercises().count == 1)
    }

    @Test("erasing an already-empty store is a no-op, not an error")
    func idempotent() throws {
        let db = try AppDatabase.inMemory()
        try db.eraseLocalData()
        try db.eraseLocalData()
        #expect(try tableCounts(db).values.reduce(0, +) == 0)
    }

    // ── The account-switch path (W11) ───────────────────────────────────────
    // `prepareForUser` is the sign-in half of the same erase: a sign-in whose
    // user is not the one the store belongs to clears it before the first sync,
    // and reports the previous account's unsynced count exactly as `signOut()`
    // does. Without it a sign-in with no sign-out before it inherited the
    // previous account's rows until its own sync landed.

    private func storeFor(_ userId: String, unsynced: Int) throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { conn in
            // `knownUserId` reads `profiles`/`user_goals` first, so a profile
            // is what makes the store "belong" to someone.
            try ProfileRow(userId: userId, role: "member", updatedAt: Date(), createdAt: Date()).insert(conn)
            try WorkoutSession(id: "s1", userId: userId, dayKey: "legs_a", date: "2026-09-02").insert(conn)
            for i in 0..<unsynced {
                try conn.execute(
                    sql: "INSERT INTO outbox (id, kind, payload, idempotency_key, created_at, attempts, status) VALUES (?,?,?,?,?,0,'pending')",
                    arguments: ["o\(i)", "row_upsert", Data(), "key-\(i)", Date()]
                )
            }
        }
        return db
    }

    @Test("a different user signing in erases the store and reports the unsynced count")
    func switchErasesAndReports() throws {
        let db = try storeFor("11111111-1111-1111-1111-111111111111", unsynced: 3)
        let discarded = try db.prepareForUser("22222222-2222-2222-2222-222222222222")
        #expect(discarded == 3, "the previous account's queued changes are reported, then lost")
        for (table, count) in try tableCounts(db) {
            #expect(count == 0, "\(table) survived the account switch")
        }
    }

    @Test("the same user signing back in keeps everything, reports nothing")
    func sameUserIsUntouched() throws {
        let db = try storeFor("11111111-1111-1111-1111-111111111111", unsynced: 2)
        let before = try tableCounts(db)
        let discarded = try db.prepareForUser("11111111-1111-1111-1111-111111111111")
        #expect(discarded == nil, "no switch happened")
        #expect(try tableCounts(db) == before, "the store was left exactly as it was")
    }

    @Test("the first sign-in on an empty store is not a switch")
    func firstSignInIsNotASwitch() throws {
        let db = try AppDatabase.inMemory()
        #expect(try db.prepareForUser("11111111-1111-1111-1111-111111111111") == nil)
    }
}
