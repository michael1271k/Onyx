import Foundation
import GRDB
import OnyxCore
@testable import OnyxData

/// The pre-W11 door names, for the tests that were written against them.
///
/// ── WHY A SHIM AND NOT A HUNDRED EDITS ──────────────────────────────────────
/// W11 gave every session-keyed read and write a `userId` and put the owner
/// check in one place per door. The suites that exercise the fold, the edit
/// envelope, the drainer and the puller seed ONE account and are about none of
/// that; threading a literal through ~120 call sites would say nothing they do
/// not already say. So the old spellings live on HERE, in the test target
/// only, and resolve the user the way the store itself does: the session's own
/// `user_id`, else the one account the store holds.
///
/// `TwoUserIsolationTests` never uses these. It calls the real doors with an
/// explicit id, which is the whole point of that suite.
extension AppDatabase {
    /// The one account a single-user test store holds.
    var soleUser: String { (try? knownUserId()) ?? "" }

    /// A session's owner — read unscoped, which is a thing only a test may do.
    func owner(of sessionId: String) -> String {
        (try? writer.read { db in try WorkoutSession.fetchOne(db, key: sessionId)?.userId }) ?? soleUser
    }

    func sessions(on date: String) throws -> [WorkoutSession] { try sessions(on: date, userId: soleUser) }
    func session(id: String) throws -> WorkoutSession? { try session(id: id, userId: owner(of: id)) }
    func sets(sessionId: String) throws -> [WorkoutSet] { try sets(sessionId: sessionId, userId: owner(of: sessionId)) }
    func observeSets(sessionId: String) -> ValueObservation<ValueReducers.Fetch<[WorkoutSet]>> {
        observeSets(sessionId: sessionId, userId: owner(of: sessionId))
    }
    func liveSession(dayKey: String, date: String) throws -> WorkoutSession? {
        try liveSession(dayKey: dayKey, date: date, userId: soleUser)
    }
    @discardableResult
    func discardSession(id: String) throws -> Bool { try discardSession(id: id, userId: owner(of: id)) }
    func setSessionStart(id: String, startedAt: Date) throws {
        try setSessionStart(id: id, startedAt: startedAt, userId: owner(of: id))
    }
    @discardableResult
    func setSessionMetrics(
        id: String, durationMin: Double? = nil, avgBpm: Int? = nil, caloriesBurned: Int? = nil, measured: Bool = true
    ) throws -> SessionEditing.Outcome? {
        try setSessionMetrics(
            id: id, userId: owner(of: id), durationMin: durationMin, avgBpm: avgBpm,
            caloriesBurned: caloriesBurned, measured: measured
        )
    }

    func sessionHistory() throws -> [WorkoutSession] { try sessionHistory(userId: soleUser) }
    func historySets(sessionId: String) throws -> [HistorySetRow] {
        try historySets(sessionId: sessionId, userId: owner(of: sessionId))
    }
    func historySets() throws -> [HistorySetRow] { try historySets(userId: soleUser) }
    func historySets(exerciseIds: [String]) throws -> [HistorySetRow] {
        try historySets(exerciseIds: exerciseIds, userId: soleUser)
    }
    func personalRecords(exerciseKey: String) throws -> [PersonalRecordRow] {
        try personalRecords(exerciseKey: exerciseKey, userId: soleUser)
    }
    func cardio(sessionId: String, date: String) throws -> [CardioLogRow] {
        try cardio(sessionId: sessionId, date: date, userId: owner(of: sessionId))
    }
    func bodyweight(onOrBefore date: String) throws -> Double? { try bodyweight(onOrBefore: date, userId: soleUser) }
    func prFloors() throws -> [String: PrFloor] { try prFloors(userId: soleUser) }
    func reportBody(id: String) throws -> String? { try reportBody(id: id, userId: soleUser) }
    func deleteCardio(id: String) throws { try deleteCardio(id: id, userId: soleUser) }
    @discardableResult
    func applyPulledSets(_ rows: [RemoteSetRow]) throws -> Int { try applyPulledSets(rows, userId: soleUser) }

    @discardableResult
    func updateMetrics(
        sessionId: String, durationMin: Double? = nil, avgBpm: Int? = nil, calories: Int? = nil,
        sessionRpe: Double? = nil, measured: Bool = true
    ) throws -> SessionEditing.Outcome? {
        try updateMetrics(
            sessionId: sessionId, userId: owner(of: sessionId), durationMin: durationMin, avgBpm: avgBpm,
            calories: calories, sessionRpe: sessionRpe, measured: measured
        )
    }
    @discardableResult
    func amendSet(
        sessionId: String, setId: String, weightKg: Double? = nil, reps: Int? = nil, rpe: Double? = nil,
        setType: String? = nil, quality: String? = nil, side: String? = nil, pairId: String? = nil,
        est1rmKg: Double? = nil, setIndex: Int? = nil, exerciseOrder: Int? = nil
    ) throws -> SessionEditing.Outcome? {
        try amendSet(
            sessionId: sessionId, userId: owner(of: sessionId), setId: setId, weightKg: weightKg, reps: reps,
            rpe: rpe, setType: setType, quality: quality, side: side, pairId: pairId, est1rmKg: est1rmKg,
            setIndex: setIndex, exerciseOrder: exerciseOrder
        )
    }
    @discardableResult
    func addSet(sessionId: String, _ snapshot: SetSnapshot, setId: String = newOnyxID()) throws -> SessionEditing.Outcome? {
        try addSet(sessionId: sessionId, userId: owner(of: sessionId), snapshot, setId: setId)
    }
    @discardableResult
    func deleteSet(sessionId: String, setId: String) throws -> SessionEditing.Outcome? {
        try deleteSet(sessionId: sessionId, userId: owner(of: sessionId), setId: setId)
    }
    @discardableResult
    func revertSessionEdits(sessionId: String) throws -> SessionEditing.Outcome? {
        try revertSessionEdits(sessionId: sessionId, userId: owner(of: sessionId))
    }
    func livePrBaselines(
        exerciseIds: [String], excluding sessionId: String?, before: String? = nil, dayKey: String?, program: Program
    ) throws -> PrBaselines {
        try livePrBaselines(
            userId: soleUser, exerciseIds: exerciseIds, excluding: sessionId, before: before,
            dayKey: dayKey, program: program
        )
    }
}
