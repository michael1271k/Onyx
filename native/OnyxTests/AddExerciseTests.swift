import Foundation
import Testing
import GRDB
import OnyxCore
import OnyxData
@testable import Onyx

/// A movement added mid-session (W3): its card, its "last time", its place in
/// the log — and that adding it moves nothing on any card the day opened with.
@MainActor
@Suite("Add exercise mid-session")
struct AddExerciseTests {
    private nonisolated static let userId = "00000000-0000-0000-0000-00000000000b"
    private let added = "Face Pull"

    private func armsDay() -> ProgramDay { PlanTemplates.day("onyx5", "arms") }

    /// A Face Pull session on ANOTHER split, a week back: the only history the
    /// added card can have, and one the day-scoped seed cannot see.
    private func store() throws -> AppDatabase {
        let database = try AppDatabase.inMemory(deviceId: "add-test")
        try database.seedRows { db in
            try Exercise(id: "ex-face", name: "Face Pull").insert(db)
            try WorkoutSession(id: "s-push", userId: Self.userId, dayKey: "push_a", date: "2026-09-01", startedAt: Date()).insert(db)
            try WorkoutSet(id: "fp-1", sessionId: "s-push", exerciseId: "ex-face", setIndex: 1, weightKg: 30, reps: 12).insert(db)
            try WorkoutSet(id: "fp-2", sessionId: "s-push", exerciseId: "ex-face", setIndex: 2, weightKg: 32.5, reps: 10).insert(db)
        }
        return database
    }

    private func snapshot(_ model: LoggerModel) -> [String] {
        model.exercises.flatMap { card in
            card.rows.map { "\(card.name)|\($0.weightKg ?? -1)|\($0.reps ?? -1)|\($0.previous ?? "")" }
        }
    }

    @Test("it opens on its last working set from any split, and no other card moves")
    func opensOnTheNarrowLookup() throws {
        let day = armsDay()
        #expect(!day.exercises.contains { $0.name == added }, "the fixture needs a movement the day does not name")
        let model = LoggerModel(day: day, phase: .bulk, store: try store(), userId: Self.userId)
        model.attach()
        let before = snapshot(model)

        let card = try #require(model.addExercise(named: added))
        #expect(model.exercises.last?.id == card.id, "appended at the bottom")
        #expect(card.rows.count == 3, "the builder's own starting prescription")
        #expect(card.rows.allSatisfy { $0.weightKg == 32.5 && $0.reps == 10 && $0.previous == "32.5kg × 10" })
        #expect(model.lastTime(for: card)?.date == "2026-09-01")
        #expect(Array(snapshot(model).prefix(before.count)) == before, "the day's own cards read the seed exactly as before")

        #expect(model.addExercise(named: "face pull")?.id == card.id, "asking again goes to the card, never a second one")
        #expect(model.exercises.filter { $0.name == added }.count == 1)
    }

    @Test("its sets take the next exercise_order, and it survives a phase switch and a relaunch")
    func persistsLikeAnyCard() throws {
        let database = try store()
        let model = LoggerModel(day: armsDay(), phase: .bulk, store: database, userId: Self.userId)
        model.attach()
        let card = try #require(model.addExercise(named: added))
        let index = try #require(model.exercises.firstIndex { $0.id == card.id })
        #expect(model.toggleGroup([card.rows[0]], in: card))

        let sessionId = try #require(model.sessionId)
        let logged = try database.sets(sessionId: sessionId, userId: Self.userId)
        #expect(logged.map(\.exerciseOrder) == [index], "dense from 0: the next index, nothing restamped")

        model.phase = .cut
        #expect(model.exercises.contains { $0.name == added && $0.rows.contains(where: \.isDone) },
                "a phase switch rebuilds from the day, and the day holds it")
        // The seed is rebuilt on a phase switch — from the PROGRAM's day, so
        // the added card still reads its narrow "last time" afterwards.
        model.addSet(to: card)
        #expect(card.rows.last?.previous == "32.5kg × 10", "a set added after a phase switch keeps its Previous")

        // The app is killed and relaunched: a fresh model, rebuilt from the
        // PROGRAM, which does not name the movement.
        let relaunched = LoggerModel(day: armsDay(), phase: .bulk, store: database, userId: Self.userId)
        relaunched.attach()
        let back = try #require(relaunched.exercises.first { $0.name == added }, "the logged set comes back on its card")
        #expect(back.rows.filter(\.isDone).count == 1)
        #expect(LoggerModel.physical(back.rows) == 3, "with the blanks it still had")
        #expect(relaunched.lastTime(for: back)?.weightKg == 32.5, "last time is the session before, never this one")
    }

    @Test("a plan movement this phase drops comes back on its global last set (Precision A1)")
    func phaseDroppedPlanMovementSeedsFromHistory() throws {
        let database = try AppDatabase.inMemory(deviceId: "add-test")
        try database.seedRows { db in
            try Exercise(id: "ex-wrist", name: "Seated DB Wrist Curl").insert(db)
            // Lifted on ANOTHER split: the day-scoped seed cannot see it.
            try WorkoutSession(id: "s-x", userId: Self.userId, dayKey: "cb_b", date: "2026-09-02", startedAt: Date()).insert(db)
            try WorkoutSet(id: "w-1", sessionId: "s-x", exerciseId: "ex-wrist", setIndex: 1, weightKg: 12.5, reps: 18).insert(db)
        }
        // The cut drops the wrist curl (`cutSets: 0`), so the deck opens without it.
        let model = LoggerModel(day: armsDay(), phase: .cut, store: database, userId: Self.userId)
        model.attach()
        #expect(!model.exercises.contains { $0.name == "Seated DB Wrist Curl" })
        let card = try #require(model.addExercise(named: "Seated DB Wrist Curl"))
        #expect(card.rows.allSatisfy { $0.weightKg == 12.5 && $0.reps == 18 && $0.previous == "12.5kg × 18" })
    }
}

/// The Muscle Shelf (Precision A1): what it files where, what it pins, and
/// what it creates.
@MainActor
@Suite("Muscle Shelf")
struct MuscleShelfTests {
    private nonisolated static let userId = "00000000-0000-0000-0000-00000000000b"

    @Test("every catalogue movement sits on exactly one shelf, its first primary mover's")
    func everyRowOnce() {
        var catalogue = StarterMovements.all.map { Exercise(id: "s-\($0.name)", name: $0.name) }
        catalogue += [
            Exercise(id: "x1", name: "Russian Twist"),
            Exercise(id: "x2", name: "Hip Adduction"),
            Exercise(id: "x3", name: "Treadmill"),
            Exercise(id: "x4", name: "Sled Push"),
            // A CSV row the dictionary has never seen, carrying its own tag.
            Exercise(id: "x5", name: "Belt Squat Machine Thing", primaryMuscle: "glutes"),
            Exercise(id: "x6", name: "Mystery Move", primaryMuscle: "glutes"),
        ]
        let shelves = MuscleShelf.file(catalogue.map(ShelfEntry.init))
        let filed = shelves.flatMap { $0.entries.map(\.id) }
        #expect(filed.count == catalogue.count)
        #expect(Set(filed) == Set(catalogue.map(\.id)))
        func shelf(_ name: String) -> MuscleShelf? {
            shelves.first { $0.entries.contains { $0.name == name } }?.shelf
        }
        #expect(shelf("Deadlift (Barbell)") == .muscle(.hamstrings))
        #expect(shelf("Chin Up") == .muscle(.lats))
        #expect(shelf("Shrug (Dumbbell)") == .muscle(.upperBack), "traps fold to Upper back")
        #expect(shelf("Russian Twist") == .obliques)
        #expect(shelf("Hip Adduction") == .muscle(.adductors))
        #expect(shelf("Treadmill") == .cardio)
        #expect(shelf("Sled Push") == .other)
        #expect(shelf("Belt Squat Machine Thing") == .muscle(.quads), "the name wins over the stored tag")
        #expect(shelf("Mystery Move") == .muscle(.glutes), "the stored tag places what the name cannot")
        // The founder's order, empty shelves dropped.
        let order = shelves.map(\.shelf)
        #expect(order == MuscleShelf.order.filter(order.contains))
    }

    @Test("Recent is newest first minus the deck; On this day is the plan minus the deck")
    func pinnedShelves() throws {
        let database = try AppDatabase.inMemory(deviceId: "shelf-test")
        try database.seedRows { db in
            try Exercise(id: "ex-face", name: "Face Pull").insert(db)
            try Exercise(id: "ex-wrist", name: "Seated DB Wrist Curl").insert(db)
            try WorkoutSession(id: "old", userId: Self.userId, dayKey: "cb_a", date: "2026-09-01", startedAt: Date()).insert(db)
            try WorkoutSet(id: "o1", sessionId: "old", exerciseId: "ex-wrist", setIndex: 1, weightKg: 10, reps: 15).insert(db)
            try WorkoutSession(id: "new", userId: Self.userId, dayKey: "cb_b", date: "2026-09-08", startedAt: Date()).insert(db)
            try WorkoutSet(id: "n1", sessionId: "new", exerciseId: "ex-face", setIndex: 1, weightKg: 30, reps: 12).insert(db)
        }
        // Delts & Arms in a cut: the wrist curl is in the plan and off the deck.
        let model = LoggerModel(day: PlanTemplates.day("onyx5", "arms"), phase: .cut, store: database, userId: Self.userId)
        model.attach()
        let library = model.library()
        #expect(library.recent == ["Face Pull", "Seated DB Wrist Curl"])
        #expect(library.onThisDay == ["Seated DB Wrist Curl"])
        #expect(library.lastSets["Face Pull"]?.weightKg == 30)

        // Once the face pull is on the deck it leaves Recent.
        model.addExercise(named: "Face Pull")
        #expect(model.library().recent == ["Seated DB Wrist Curl"])
    }

    @Test("the fifteen are created once, under the ids the SQL writes")
    func startersOnce() throws {
        let database = try AppDatabase.inMemory(deviceId: "shelf-test")
        #expect(StarterMovements.ensure(in: database, userId: Self.userId, catalogue: []) == 15)
        let catalogue = try database.exercises()
        #expect(catalogue.count == 15)
        #expect(StarterMovements.ensure(in: database, userId: Self.userId, catalogue: catalogue) == 0)
        // Hand-computed: md5("00000000-0000-0000-0000-00000000000b:Pull Up").
        #expect(catalogue.first { $0.name == "Pull Up" }?.id == "0f2df3e0-9eb9-f2c0-a5a6-791d80a660e0")
        #expect(StarterMovements.id(userId: Self.userId.uppercased(), name: "Pull Up") == "0f2df3e0-9eb9-f2c0-a5a6-791d80a660e0")
    }

    @Test("the shelf opens in under 100 ms over two hundred movements")
    func opensFast() throws {
        let database = try AppDatabase.inMemory(deviceId: "shelf-test")
        try database.seedRows { db in
            for i in 0..<200 { try Exercise(id: "ex-\(i)", name: "Movement \(i)").insert(db) }
            for s in 0..<150 {
                try WorkoutSession(id: "s\(s)", userId: Self.userId, dayKey: "cb_a",
                                   date: LogicalDay.iso(Date().addingTimeInterval(Double(-s) * 86_400)), startedAt: Date()).insert(db)
                for k in 0..<20 {
                    try WorkoutSet(id: "s\(s)-\(k)", sessionId: "s\(s)", exerciseId: "ex-\((s * 7 + k) % 200)",
                                   setIndex: k + 1, weightKg: 20, reps: 10).insert(db)
                }
            }
        }
        let model = LoggerModel(day: PlanTemplates.day("onyx5", "arms"), phase: .bulk, store: database, userId: Self.userId)
        _ = model.library()   // the starters are created on the first open
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = model.library() }
        print("ONYXMEASURE library.open \(elapsed)")
        #expect(elapsed < .milliseconds(100))
    }
}
