import Foundation
import Testing
import OnyxCore
@testable import OnyxData
#if canImport(HealthKit)
import HealthKit
#endif

/// Overhaul C2 — a treadmill is a treadmill, not a walk.
///
/// Health files an indoor walk as `.walking` with `HKMetadataKeyIndoorWorkout`
/// set, and the reader never read the key, so every treadmill bout imported
/// as "walk" and the warm-up card named it "Walk".
@Suite("Treadmill kind")
struct TreadmillKindTests {

    @Test("the vocabulary offers a treadmill, after walk")
    func vocabulary() {
        #expect(CardioImport.treadmill == "treadmill")
        #expect(CardioImport.offered.contains(CardioImport.treadmill))
        #expect(CardioImport.offered.firstIndex(of: CardioImport.walk)! < CardioImport.offered.firstIndex(of: CardioImport.treadmill)!)
    }

    #if canImport(HealthKit)
    @Test("an indoor walk is a treadmill; outdoor or unknown stays a walk")
    func indoorWalkIsTreadmill() {
        #expect(HealthKitReader.cardioKind(.walking, indoor: true) == CardioImport.treadmill)
        #expect(HealthKitReader.cardioKind(.walking, indoor: false) == CardioImport.walk)
        #expect(HealthKitReader.cardioKind(.walking, indoor: nil) == CardioImport.walk)
        // Only a walk moves: an indoor run keeps its own kind.
        #expect(HealthKitReader.cardioKind(.running, indoor: true) == CardioImport.run)
        #expect(HealthKitReader.cardioKind(.cycling, indoor: true) == CardioImport.cycling)
        #expect(HealthKitReader.cardioKind(.yoga, indoor: true) == nil)
    }
    #endif
}

/// Precision A2 — the treadmill card repeats the last TREADMILL, and a bout
/// logged in the deck becomes "the last time" by being filed in `cardio_logs`.
@Suite("Treadmill truth")
struct TreadmillTruthTests {
    private let user = "u1"

    private func bout(_ id: String, _ date: String, _ kind: String, minutes: Double, at: Date? = nil,
                      healthKit: Bool = true, session: String? = nil) -> CardioLogRow {
        CardioLogRow(id: id, userId: user, date: date, kind: kind, distanceM: 2000, durationMin: minutes,
                     fromHealthkit: healthKit, createdAt: at, sessionId: session)
    }

    @Test("the last treadmill wins over a newer walk")
    func treadmillOverNewerWalk() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try db.addCardio(bout("t", "2026-09-10", CardioImport.treadmill, minutes: 20))
        try db.addCardio(bout("w", "2026-09-24", CardioImport.walk, minutes: 24))
        #expect(try db.lastCardioBout(userId: user, kind: CardioImport.treadmill)?.id == "t")
        #expect(try db.lastCardioBout(userId: user)?.id == "w", "unfiltered is still the newest of any kind")
    }

    /// A session that warmed up on the treadmill inside the deck.
    private func sessionWithBout(_ db: AppDatabase, id: String = "s1", date: String = "2026-09-20") throws {
        try db.writer.write { conn in
            try Exercise(id: "ex-tread", name: "Treadmill").insert(conn)
            try WorkoutSession(id: id, userId: user, dayKey: "cb_b", date: date,
                               startedAt: Date(timeIntervalSince1970: 1_790_000_000)).insert(conn)
            try WorkoutSet(id: "\(id)-t", sessionId: id, exerciseId: "ex-tread", setIndex: 1, weightKg: 0, reps: 0,
                           setType: "warmup", durationSec: 1_200, incline: 3, distanceKm: 1.6).insert(conn)
            try WorkoutSet(id: "\(id)-l", sessionId: id, exerciseId: "ex-tread", setIndex: 2, weightKg: 0, reps: 0,
                           setType: "ghost", durationSec: 60).insert(conn)
        }
    }

    @Test("closing files the deck's bout in cardio_logs once, as a treadmill, from this device")
    func recordsOnce() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try sessionWithBout(db)
        #expect(try db.recordSessionCardio(sessionId: "s1", userId: user) == 1)
        #expect(try db.recordSessionCardio(sessionId: "s1", userId: user) == 0, "a second close writes nothing")
        let rows = try db.cardioRows(userId: user, date: "2026-09-20")
        #expect(rows.count == 1, "the ghost is not a bout")
        let row = try #require(rows.first)
        #expect(row.kind == CardioImport.treadmill)
        #expect(row.durationMin == 20)
        #expect(row.distanceM == 1_600)
        #expect(row.inclinePct == 3)
        #expect(row.sessionId == "s1")
        #expect(row.fromHealthkit == false)
        #expect(row.hkUuid == nil)
        #expect(row.createdAt == Date(timeIntervalSince1970: 1_790_000_000), "the bout's own start")
        let queued = try db.pendingOutbox().map(\.idempotencyKey)
        #expect(queued.contains("row:cardio_logs:\(row.id)"))
    }

    @Test("the deck's bout is readable as the last one logged inside a session")
    func loggedBoutReads() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try sessionWithBout(db, id: "old", date: "2026-09-01")
        try db.writer.write { conn in
            try WorkoutSession(id: "new", userId: user, dayKey: "cb_a", date: "2026-09-21", startedAt: Date()).insert(conn)
            try WorkoutSet(id: "new-t", sessionId: "new", exerciseId: "ex-tread", setIndex: 1, weightKg: 0, reps: 0,
                           setType: "warmup", durationSec: 900, incline: 2, distanceKm: 1.1).insert(conn)
        }
        let last = try #require(try db.lastLoggedBout(named: "Treadmill", userId: user))
        #expect(last.date == "2026-09-21")
        #expect(last.durationSec == 900)
        #expect(last.distanceKm == 1.1)
        #expect(last.inclinePct == 2)
        #expect(try db.lastLoggedBout(named: "Rowing", userId: user) == nil)
    }

    @Test("a walk Health imported BEFORE the finish is adopted, not duplicated")
    func healthFirstIsAdopted() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try sessionWithBout(db)
        // The watch's indoor walk of the same twenty minutes, imported while
        // the session was still open: no session, a key, a start.
        try db.addCardio(CardioLogRow(
            id: "hk", userId: user, date: "2026-09-20", kind: CardioImport.treadmill,
            distanceM: 1_640, durationMin: 20.4, fromHealthkit: true,
            createdAt: Date(timeIntervalSince1970: 1_790_000_060), hkUuid: "HK-1"
        ))
        #expect(try db.recordSessionCardio(sessionId: "s1", userId: user) == 1)
        let rows = try db.cardioRows(userId: user, date: "2026-09-20")
        #expect(rows.count == 1, "one walk, one row")
        #expect(rows.first?.id == "hk")
        #expect(rows.first?.sessionId == "s1", "filed against the session it was the warm-up of")
        #expect(rows.first?.hkUuid == "HK-1", "Health's figures and key survive")
        #expect(try db.recordSessionCardio(sessionId: "s1", userId: user) == 0)
    }

    @Test("a HealthKit re-import of the same bout lands on the filed row, never beside it")
    func healthReimportDedupes() throws {
        let db = try AppDatabase.inMemory(deviceId: "d")
        try sessionWithBout(db)
        try db.recordSessionCardio(sessionId: "s1", userId: user)
        let existing = try db.cardioRows(userId: user, date: "2026-09-20").map {
            CardioImport.Existing(id: $0.id, date: $0.date, kind: $0.kind, durationMin: $0.durationMin,
                                  createdAt: $0.createdAt, fromHealthkit: $0.fromHealthkit ?? false, hkUuid: $0.hkUuid)
        }
        // The watch's indoor walk of the same twenty minutes, started a minute
        // later and a few seconds longer.
        let match = CardioImport.matchingRow(
            hkUuid: "HK-1", kind: CardioImport.treadmill,
            start: Date(timeIntervalSince1970: 1_790_000_060), durationMin: 20.4,
            date: "2026-09-20", in: existing
        )
        #expect(match?.id == existing.first?.id)
    }
}
