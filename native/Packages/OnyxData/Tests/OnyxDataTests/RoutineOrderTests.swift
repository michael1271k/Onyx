import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// A reorder that survives the session it was made in.
///
/// ── WHAT WAS BROKEN ─────────────────────────────────────────────────────────
/// Dragging a movement up mid-workout wrote `exercise_order` on every ticked
/// row, and both clients read it back into the session REPORT. It reached
/// nothing else: the next deck is built from `Program.onyx5`, a constant, so
/// the drag had to be repeated every single week. The web has upserted
/// `routine_templates` on every commit since `save.ts` was written; the phone
/// never wrote the row.
///
/// The risk in writing it from here is the payload, not the order. The phone's
/// view of it (`SeedTemplate`) decodes a strict subset — no `kind`, no cardio
/// fields, no `side`/`pairId`, no `note` — so a phone-side rebuild would delete
/// the treadmill block and flatten every unilateral pair the web put there, on
/// the next session finished on the phone. `patch` therefore edits the stored
/// JSON in place and never decodes it.
@Suite("Routine order")
struct RoutineOrderTests {

    private let user = "u1"

    // MARK: - Patching an existing payload

    @Test("the order is rewritten and every other key survives untouched")
    func patchPreservesUnknownKeys() throws {
        // A payload as the WEB writes it: a cardio opener with three fields the
        // phone has no type for, and a unilateral pair.
        let stored = """
        {"version":1,"exercises":[
          {"name":"Treadmill","order":0,"kind":"cardio","sets":[],
           "distanceKm":0.37,"durationSec":300,"inclinePct":2,"note":"Pace rising 4.3 to 5.0"},
          {"name":"Cable Curl","order":1,"sets":[{"weightKg":20,"reps":10,"rpe":8}]},
          {"name":"Lateral Raise","order":2,
           "sets":[{"weightKg":8,"reps":12,"side":"L","pairId":"p1"},
                   {"weightKg":8,"reps":12,"side":"R","pairId":"p1"}]}
        ]}
        """

        // The drag: Lateral Raise moved above Cable Curl.
        let patched = try #require(
            RoutineOrder.patch(stored, order: ["Treadmill", "Lateral Raise", "Cable Curl"])
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(patched.utf8)) as? [String: Any]
        )
        let exercises = try #require(object["exercises"] as? [[String: Any]])
        #expect(exercises.map { $0["name"] as? String } == ["Treadmill", "Lateral Raise", "Cable Curl"])
        #expect(exercises.map { $0["order"] as? Int } == [0, 1, 2], "dense from 0, like the web")

        // Nothing else moved. This is the assertion the whole design is for.
        #expect(exercises[0]["kind"] as? String == "cardio")
        #expect(exercises[0]["durationSec"] as? Int == 300)
        #expect(exercises[0]["note"] as? String == "Pace rising 4.3 to 5.0")
        let pair = try #require(exercises[1]["sets"] as? [[String: Any]])
        #expect(pair.compactMap { $0["side"] as? String } == ["L", "R"])
        #expect(pair.allSatisfy { $0["pairId"] as? String == "p1" })
        #expect((exercises[2]["sets"] as? [[String: Any]])?.first?["rpe"] as? Double == 8)
    }

    @Test("a movement the session never logged keeps its place, after the ones it did")
    func unnamedMovementsHoldPosition() throws {
        let stored = """
        {"version":1,"exercises":[
          {"name":"A","order":0,"sets":[]},
          {"name":"B","order":1,"sets":[]},
          {"name":"C","order":2,"sets":[]},
          {"name":"D","order":3,"sets":[]}
        ]}
        """
        // Only C and A were logged, in that order. B and D are untouched and
        // must not swap with each other — `sorted(by:)` is not stable in Swift,
        // which is why the rank carries the original index as a tiebreak.
        let patched = try #require(RoutineOrder.patch(stored, order: ["C", "A"]))
        let exercises = try #require(
            (try JSONSerialization.jsonObject(with: Data(patched.utf8)) as? [String: Any])?["exercises"]
                as? [[String: Any]]
        )
        #expect(exercises.map { $0["name"] as? String } == ["C", "A", "B", "D"])
    }

    @Test("a garbled payload is left alone rather than thrown over")
    func garbledPayloadIsAbsent() {
        #expect(RoutineOrder.patch("not json", order: ["A"]) == nil)
        #expect(RoutineOrder.patch("{\"version\":1}", order: ["A"]) == nil)
        #expect(RoutineOrder.patch("{\"version\":1,\"exercises\":[]}", order: ["A"]) == nil)
    }

    // MARK: - End to end, through the close

    @Test("finishing a session stores the deck order and queues it for upload")
    func closeStoresTheOrder() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        try db.writer.write { db in
            try Exercise(id: "onyx-cable-curl", name: "Cable Curl").insert(db)
            try Exercise(id: "onyx-lateral-raise", name: "Lateral Raise").insert(db)
        }
        let session = try db.openSession(userId: user, dayKey: "arms", date: "2026-09-08")
        // Logged in deck order, then dragged: the Lateral Raise ends up first,
        // which is what `moveExercise` writes onto the rows.
        try db.appendSet(
            sessionId: session.id, setId: "set-1",
            SetSnapshot(exerciseId: "onyx-cable-curl", setIndex: 1, weightKg: 20, reps: 10, exerciseOrder: 1)
        )
        try db.appendSet(
            sessionId: session.id, setId: "set-2",
            SetSnapshot(exerciseId: "onyx-lateral-raise", setIndex: 1, weightKg: 8, reps: 12, exerciseOrder: 0)
        )
        try db.closeSession(id: session.id, sessionRpe: 8)

        // The order is readable by the thing that seeds the next deck.
        #expect(try db.deckOrder(dayKey: "arms", userId: user) == ["Lateral Raise", "Cable Curl"])

        // And it is on its way to Postgres. A row written locally and absent
        // from the queue is a reorder that stops at this device.
        let queued = try db.pendingOutbox().map(\.idempotencyKey)
        #expect(queued.contains("row:routine_templates:\(AppDatabase.rowID([user, "arms"]))"))

        // A locally invented row must not drag the delta cursor forward.
        let row = try #require(try db.writer.read { db in
            try RoutineTemplateRow.fetchOne(db, key: ["user_id": user, "day_key": "arms"])
        })
        #expect(row.updatedAt == AppDatabase.localWriteTimestamp)
        #expect(row.sourceSessionId == session.id)
    }

    @Test("a ghosted movement shapes nothing about next week")
    func ghostsAreExcluded() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        try db.writer.write { db in
            try Exercise(id: "onyx-cable-curl", name: "Cable Curl").insert(db)
            try Exercise(id: "onyx-wrist-curl", name: "Wrist Curl").insert(db)
        }
        let session = try db.openSession(userId: user, dayKey: "arms", date: "2026-09-08")
        try db.appendSet(
            sessionId: session.id, setId: "set-1",
            SetSnapshot(exerciseId: "onyx-cable-curl", setIndex: 1, weightKg: 20, reps: 10, exerciseOrder: 0)
        )
        // Skipped on purpose. `payloadToTemplate` drops it on the web for the
        // same reason: a ghost records what you chose NOT to do.
        try db.appendSet(
            sessionId: session.id, setId: "set-2",
            SetSnapshot(
                exerciseId: "onyx-wrist-curl", setIndex: 1, weightKg: 0, reps: 0,
                setType: "ghost", exerciseOrder: 1
            )
        )
        try db.closeSession(id: session.id)
        #expect(try db.deckOrder(dayKey: "arms", userId: user) == ["Cable Curl"])
    }

    // MARK: - Unticked sets stay planned (Precision A6, Q9)

    @Test("finishing 2 of 4 leaves a 4-row template with the two ticked loads updated")
    func untickedSetsStayPlanned() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let stored = """
        {"version":1,"exercises":[
          {"name":"Cable Curl","order":0,"note":"elbows pinned","sets":[
            {"weightKg":10,"reps":12,"setType":"warmup"},
            {"weightKg":20,"reps":10,"rpe":8},{"weightKg":20,"reps":10},
            {"weightKg":20,"reps":9},{"weightKg":20,"reps":8}]},
          {"name":"Treadmill","order":1,"kind":"cardio","sets":[],"durationSec":300}
        ]}
        """
        try db.writer.write { db in
            try Exercise(id: "onyx-cable-curl", name: "Cable Curl").insert(db)
            try RoutineTemplateRow(
                userId: user, dayKey: "arms", payload: JSONText(raw: stored),
                sourceSessionId: nil, updatedAt: AppDatabase.localWriteTimestamp
            ).insert(db)
        }
        let session = try db.openSession(userId: user, dayKey: "arms", date: "2026-09-25")
        // Two of the four working sets ticked, heavier; the other two never
        // stored — and the warm-up done at a new load.
        try db.appendSet(sessionId: session.id, setId: "w", SetSnapshot(
            exerciseId: "onyx-cable-curl", setIndex: 1, weightKg: 12.5, reps: 12, setType: "warmup", exerciseOrder: 0))
        try db.appendSet(sessionId: session.id, setId: "a", SetSnapshot(
            exerciseId: "onyx-cable-curl", setIndex: 2, weightKg: 22.5, reps: 10, exerciseOrder: 0))
        try db.appendSet(sessionId: session.id, setId: "b", SetSnapshot(
            exerciseId: "onyx-cable-curl", setIndex: 3, weightKg: 22.5, reps: 9, exerciseOrder: 0))
        try db.closeSession(id: session.id)

        let template = try #require(try db.seedTemplate(dayKey: "arms", userId: user))
        let curl = try #require(template.exercises.first { $0.name == "Cable Curl" })
        #expect(curl.sets.filter { $0.setType != "warmup" }.map { [$0.weightKg, Double($0.reps)] }
                == [[22.5, 10], [22.5, 9], [20, 9], [20, 8]],
                "four planned rows: the two ticked updated, the two unticked kept at their last load")
        #expect(curl.sets.first { $0.setType == "warmup" }.map { [$0.weightKg, Double($0.reps)] } == [12.5, 12])
        #expect(curl.sets.count == 5)
        #expect(curl.sets[1].rpe == nil, "a rating the new set did not carry is not inherited")

        // Every key the phone does not model survives, and the cardio block
        // the session did not touch is exactly what it was.
        let raw = try #require(try db.writer.read { db in
            try RoutineTemplateRow.fetchOne(db, key: ["user_id": user, "day_key": "arms"])
        }).payload.raw
        let object = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        let exercises = try #require(object["exercises"] as? [[String: Any]])
        #expect(exercises.first { $0["name"] as? String == "Cable Curl" }?["note"] as? String == "elbows pinned")
        #expect(exercises.first { $0["name"] as? String == "Treadmill" }?["durationSec"] as? Int == 300)
    }
}
