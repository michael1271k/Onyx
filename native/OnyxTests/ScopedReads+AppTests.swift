import Foundation
import OnyxData

/// The pre-W11 door names for the app-target tests, same purpose as
/// `ScopedReads+Tests` in OnyxDataTests: the suites here seed ONE account and
/// are not about isolation, so they keep the old spellings and resolve the user
/// the store itself holds (`knownUserId`). `TwoUserIsolationTests` (OnyxData)
/// is the suite that calls the real doors with an explicit id.
///
/// A single-user store's owner is the same for every session, so there is no
/// per-session lookup to do — and `writer` is not public here anyway.
extension AppDatabase {
    private var soleTestUser: String { (try? knownUserId()) ?? "" }

    func sessions(on date: String) throws -> [WorkoutSession] { try sessions(on: date, userId: soleTestUser) }
    func session(id: String) throws -> WorkoutSession? { try session(id: id, userId: soleTestUser) }
    func sets(sessionId: String) throws -> [WorkoutSet] { try sets(sessionId: sessionId, userId: soleTestUser) }
    func historySets(sessionId: String) throws -> [HistorySetRow] {
        try historySets(sessionId: sessionId, userId: soleTestUser)
    }
    func historySets() throws -> [HistorySetRow] { try historySets(userId: soleTestUser) }
}
