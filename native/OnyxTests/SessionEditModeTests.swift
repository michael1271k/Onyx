import Foundation
import Testing
import GRDB
import OnyxCore
import OnyxData
@testable import Onyx

/// Re-opening a finished workout on the deck (§U4.5).
///
/// ── WHY THESE FOUR AND NOT MORE ─────────────────────────────────────────────
/// `SessionEditing` is already held to its own contract in `OnyxDataTests` —
/// the seed, the replay, the retraction, the aggregate guard. What is untested
/// there, and is the whole of what this wave added, is the JOIN: a deck built
/// from `Program.onyx5` folding onto rows that may carry the WEB's catalogue
/// uuids rather than this phone's slugs. Every fault that join can produce is
/// silent — a blank deck, a session split in two under one name, a bar built
/// from nothing — so each gets a case.
@MainActor
@Suite("Session edit mode")
struct SessionEditModeTests {

    /// `nonisolated` because `seedRows` takes a `@Sendable` closure and the
    /// suite is `@MainActor` — a main-actor-isolated constant cannot be read
    /// from one, and the alternative is spelling both strings twice.
    private nonisolated static let userId = "00000000-0000-0000-0000-000000000009"
    private nonisolated static let sessionId = "s-edit"

    /// One finished Upper A, logged the way the WEB logs: `exercise_id` is a
    /// catalogue uuid, not `onyx-<slug>`. This is the case `restoreLoggedSets`
    /// used to find nothing for.
    private func store() throws -> AppDatabase {
        let database = try AppDatabase.inMemory(deviceId: "edit-test")
        try database.seedRows { db in
            try Exercise(id: "ex-chest-press", name: "Chest Press").insert(db)
            let start = LogicalDay.date(fromISO: "2026-08-30")!.addingTimeInterval(17 * 3600)
            try WorkoutSession(
                id: Self.sessionId, userId: Self.userId, dayKey: "cb_a", date: "2026-08-30",
                startedAt: start, endedAt: start.addingTimeInterval(60 * 60),
                durationMin: 60, sessionRpe: 7
            ).insert(db)
            for (index, reps) in [10, 9, 8].enumerated() {
                try WorkoutSet(
                    id: "set-\(index + 1)", sessionId: Self.sessionId, exerciseId: "ex-chest-press",
                    setIndex: index + 1, weightKg: 40, reps: reps, setType: "normal",
                    est1rmKg: OneRepMax.estimate(weight: 40, reps: Double(reps)),
                    // `exercise_order` as the WEB writes it — dense from 0,
                    // which `buildCommitPayload` has always done, and 2 is where
                    // `Chest Press` sits in Upper A.
                    //
                    // Left nil (as it was), the deck's own index for this
                    // movement was a genuine CHANGE, so the first "no-op" commit
                    // legitimately seeded the log — `deckOrder` is documented as
                    // the DECK's index in edit mode too. The fixture, not the
                    // rule, is what made that look like a bug; this test never
                    // reached the assertion to find out, because the movement it
                    // looked up had been renamed out from under it.
                    exerciseOrder: 2, foldOrder: index
                ).insert(db)
            }
        }
        return database
    }

    private func attached(_ database: AppDatabase) throws -> LoggerModel {
        let session = try #require(try database.session(id: Self.sessionId))
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "cb_a"), phase: .cut,
            store: database, userId: Self.userId, startedAt: session.startedAt ?? Date()
        )
        model.attach(editing: session)
        return model
    }

    /// `Chest Press`, not `Chest Press (Machine)`: the equipment-as-data wave
    /// took the implement out of every title and put it in a column, and this
    /// lookup was never updated — six tests in this suite have been requiring a
    /// movement the programme stopped naming.
    private func chestPress(_ model: LoggerModel) throws -> LoggerModel.ExerciseState {
        try #require(model.exercises.first { $0.name == "Chest Press" })
    }

    @Test("a session logged on the web restores onto the deck, matched by name")
    func restoresAcrossIdSchemes() throws {
        let model = try attached(try store())

        #expect(model.isEditing)
        #expect(model.sessionId == Self.sessionId)
        let exercise = try chestPress(model)
        let done = exercise.rows.filter(\.isDone)
        #expect(done.count == 3, "the three logged sets must come back ticked")
        #expect(done.map { $0.reps ?? 0 } == [10, 9, 8])
        // Matched by canonical NAME: the rows carry `ex-chest-press` and the
        // deck's own key for this movement is `onyx-chest-press-machine`.
        #expect(exercise.storedExerciseId == "ex-chest-press")
        #expect(exercise.rows[0].id == "set-1", "the deck must own the STORED set ids, or an amend addresses nothing")
    }

    @Test("a set added to a web-logged session keeps the session's own exercise id")
    func appendKeepsTheStoredId() throws {
        let database = try store()
        let model = try attached(database)
        let exercise = try chestPress(model)

        model.addSet(to: exercise)
        let fresh = try #require(exercise.rows.last)
        fresh.weightKg = 40
        fresh.reps = 7
        model.toggleDone(fresh, in: exercise)

        let ids = Set(try database.sets(sessionId: Self.sessionId).map(\.exerciseId))
        #expect(ids == ["ex-chest-press"], "a slug beside the uuid splits one movement into two in every report")
        #expect(try database.sets(sessionId: Self.sessionId).count == 4)
    }

    @Test("editing a finished session never opens a second one")
    func neverMintsASession() throws {
        let database = try store()
        let model = try attached(database)
        let exercise = try chestPress(model)

        model.addSet(to: exercise)
        let fresh = try #require(exercise.rows.last)
        fresh.weightKg = 30
        fresh.reps = 12
        model.toggleDone(fresh, in: exercise)

        let sessions = try database.read { db in try WorkoutSession.fetchAll(db) }
        #expect(sessions.count == 1)
        #expect(sessions[0].id == Self.sessionId)
        // `ended_at` is what makes it history; an edit must not reopen it.
        #expect(sessions[0].endedAt != nil)
    }

    @Test("unticking and re-ticking a set does not destroy it")
    func retickSurvivesTheTombstone() throws {
        let database = try store()
        let model = try attached(database)
        let exercise = try chestPress(model)
        let row = try #require(exercise.rows.first)

        model.toggleDone(row, in: exercise)            // untick — a tombstone
        #expect(!row.isDone)
        #expect(try database.sets(sessionId: Self.sessionId).count == 2)

        model.toggleDone(row, in: exercise)            // and change your mind
        #expect(row.isDone)

        // ── THE RULE THIS PINS ──────────────────────────────────────────────
        // `SetEventFold` says a voided set id "outranks everything, forever" —
        // an `.append` under it is skipped before any other rule. So a re-tick
        // under the SAME id left the row ticked on screen and absent from the
        // projection, while `recount` wrote the smaller tonnage onto the
        // session row and queued it for upload.
        let rows = try database.sets(sessionId: Self.sessionId)
        #expect(rows.count == 3, "the re-ticked set must come back")
        #expect(!rows.contains { $0.id == "set-1" }, "the tombstoned id must not be reused")
        #expect(rows.contains { $0.reps == 10 && $0.weightKg == 40 })
    }

    @Test("re-committing a set without changing it does not seed the event log")
    func noOpAmendIsNotAnEdit() throws {
        let database = try store()
        let model = try attached(database)
        let exercise = try chestPress(model)
        let row = try #require(exercise.rows.first)

        // What a tap into the weight field and a tap away produces:
        // `ExerciseCardView` commits on every focus loss, changed or not.
        model.commitEdit(row, in: exercise)

        let events = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM set_events WHERE session_id = ?",
                             arguments: [Self.sessionId]) ?? 0
        }
        // Seeding is a ONE-WAY DOOR: from the first event this session is
        // skipped by `applyPulledSets` forever. Reading a number must not walk
        // through it.
        #expect(events == 0, "a patch that restates the row must not seed the log")
    }

    @Test("finishing an edit anchors on the session's date")
    func finishReportsTheCascadeAnchor() throws {
        let database = try store()
        let model = try attached(database)
        let exercise = try chestPress(model)

        let row = try #require(exercise.rows.first)
        row.weightKg = 60
        model.commitEdit(row, in: exercise)

        // The date is the session's LOGICAL day, never today: `RescoreQueue`
        // walks forward from it, and anchoring on today would leave every score
        // between the workout and now describing the load that was corrected.
        #expect(model.finishEdit(sessionRpe: 8) == "2026-08-30")

        let session = try #require(try database.session(id: Self.sessionId))
        #expect(session.sessionRpe == 8)
        let stored = try #require(try database.sets(sessionId: Self.sessionId).first { $0.id == "set-1" })
        #expect(stored.weightKg == 60, "the amend must reach the projection, not just the event log")
    }

    // MARK: - Overhaul C2 · Discard and Add a movement

    /// `revertSessionEdits` answers nil for a sitting that changed nothing, and
    /// its contract says the caller still closes the screen. `cancelEdit`
    /// reported that as a failure, so Discard on an untouched editor did
    /// nothing at all — no banner, no dismissal, the mark still standing.
    @Test("Discard on a sitting that changed nothing closes the editor")
    func discardNoOpDismisses() throws {
        let database = try store()
        let model = try attached(database)
        #expect(model.editWatermarked, "the editor opened with a mark to go back to")

        #expect(model.cancelEdit() == true)
        #expect(model.editWatermarked == false)
        #expect(model.storeError == nil)
        #expect(try database.sets(sessionId: Self.sessionId).count == 3)
    }

    /// The edit deck offers "Add a movement" now. A set logged on it is a real
    /// set of THIS session (not a new one), and Discard takes it — and its
    /// card — back out.
    @Test("a movement added while editing persists, and Discard removes it")
    func addedMovementPersistsAndReverts() throws {
        let database = try store()
        let model = try attached(database)

        let added = try #require(model.addExercise(named: "Hip Thrust"))
        let row = try #require(added.rows.first)
        row.weightKg = 80
        row.reps = 10
        model.toggleDone(row, in: added)

        let sets = try database.sets(sessionId: Self.sessionId)
        #expect(sets.count == 4, "the added set lands on the session being edited")
        #expect(try database.read { db in try WorkoutSession.fetchCount(db) } == 1)

        #expect(model.cancelEdit() == true)
        #expect(try database.sets(sessionId: Self.sessionId).count == 3)
        #expect(!model.exercises.contains { $0.name == "Hip Thrust" }, "the card added during the sitting goes with it")
    }
}
