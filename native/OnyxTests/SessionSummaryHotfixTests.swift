import Foundation
import Testing
import GRDB
import OnyxCore
import OnyxData
@testable import Onyx

/// The post-workout page's three data-shaped defects, and the editing gate that
/// was never lifted after its reason went away.
///
/// Each of these was reported as something the page DREW, and each of them is
/// really a question about what the page is handed. So they are asserted here,
/// against a real store, rather than photographed: a screenshot of
/// "74 min, +72" cannot tell you whether the 72 came from this session or the
/// one before it.
@MainActor
@Suite("Session summary — the hotfix")
struct SessionSummaryHotfixTests {

    private nonisolated static let userId = "00000000-0000-0000-0000-00000000000d"

    /// Two Upper B sessions a week apart, the earlier one carrying whatever
    /// `previousDurationMin` says. Twelve working sets each, so the credibility
    /// floor has a set count to work against.
    private func store(previousDurationMin: Double) throws -> AppDatabase {
        let database = try AppDatabase.inMemory(deviceId: "summary-hotfix")
        try database.seedRows { db in
            try Exercise(id: "ex-row", name: "Chest Press").insert(db)
            for (session, date, duration) in [
                ("s-prev", "2026-09-03", previousDurationMin),
                ("s-now", "2026-09-10", 74.0),
            ] {
                let start = LogicalDay.date(fromISO: date)!.addingTimeInterval(10 * 3600)
                try WorkoutSession(
                    id: session, userId: Self.userId, dayKey: "cb_b", date: date,
                    startedAt: start, endedAt: start.addingTimeInterval(duration * 60),
                    durationMin: duration, sessionRpe: 8
                ).insert(db)
                for index in 0..<12 {
                    try WorkoutSet(
                        id: "\(session)-\(index)", sessionId: session, exerciseId: "ex-row",
                        setIndex: index + 1, weightKg: 40, reps: 10,
                        exerciseOrder: 0, foldOrder: index
                    ).insert(db)
                }
            }
        }
        return database
    }

    // MARK: - §3.1 · the +72

    @Test("a previous session's impossible clock produces no delta, not a wrong one")
    func incredibleDurationYieldsNoDelta() throws {
        // 2026-09-03 as the database actually held it: twelve sets and
        // 3,108 kg, stored as two minutes. The page read "74 min, +72" — and
        // +72 is a claim about the session BEFORE this one, printed on this
        // one, with nothing on screen to say so.
        let page = try #require(SessionAnalysis.page(
            database: try store(previousDurationMin: 2), sessionId: "s-now"
        ))
        #expect(page.previous?.durationMin == 2, "the stored figure is still readable")
        #expect(page.previous?.credibleDurationMin == nil, "…and is not believed")
        #expect(page.durationDelta == nil, "a reserved blank line, never an invented +72")

        // The tonnage delta is unaffected: only the CLOCK was corrupt, and a
        // guard that suppressed the whole comparison would lose a real reading.
        #expect(page.tonnageDelta == 0)
    }

    @Test("a credible previous session still gets its delta")
    func credibleDurationStillCompares() throws {
        let page = try #require(SessionAnalysis.page(
            database: try store(previousDurationMin: 60), sessionId: "s-now"
        ))
        #expect(page.durationDelta == 14)
    }

    @Test("the floor is seconds per set, so a short honest session survives it")
    func theFloorDoesNotEatRealSessions() {
        func summary(_ minutes: Double, sets: Int) -> SessionAnalysis.Summary {
            SessionAnalysis.Summary(
                id: "s", date: "2026-09-03", dayKey: "cb_b",
                durationMin: minutes, sets: sets, tonnageKg: 3108.5, prCount: 0
            )
        }
        // The tightest real session on record — 13 sets in 46 minutes — and the
        // shortest plausible one anybody could log.
        #expect(summary(46, sets: 13).credibleDurationMin == 46)
        #expect(summary(5, sets: 12).credibleDurationMin == 5)
        // And the corruption: 12 sets in 2 minutes is 10 s a set.
        #expect(summary(2, sets: 12).credibleDurationMin == nil)
        #expect(summary(0, sets: 12).credibleDurationMin == nil)
        // No sets at all is a shell session, not an impossible one — there is
        // no work for the floor to be measured against.
        #expect(summary(2, sets: 0).credibleDurationMin == 2)
    }

    // MARK: - §3.2 · onyx-treadmill

    @Test("a treadmill logged on this phone is titled Treadmill, not its slug")
    func treadmillIsNamed() throws {
        // `WarmupCardio` is not in `Program.onyx5` (a walk has no sets, reps or
        // load), so the deck's `onyx-treadmill` was in no lookup: the
        // catalogue has no row under that id and `nameBySlug` was built from the
        // program alone. `COALESCE(e.name, s.exercise_id)` therefore fell
        // through to the id and the page drew it as a movement's name.
        let slug = ExerciseSlug.id(WarmupCardio.name)
        #expect(slug == "onyx-treadmill")

        let database = try AppDatabase.inMemory(deviceId: "treadmill-name")
        try database.seedRows { db in
            let start = LogicalDay.date(fromISO: "2026-09-08")!.addingTimeInterval(10 * 3600)
            try WorkoutSession(
                id: "s-tread", userId: Self.userId, dayKey: "arms", date: "2026-09-08",
                startedAt: start, endedAt: start.addingTimeInterval(76 * 60),
                durationMin: 76, sessionRpe: 8
            ).insert(db)
            // No `Exercise` row: this is a set logged on the phone and not yet
            // reconciled against the catalogue, which is exactly the state the
            // bug was reported in.
            try WorkoutSet(
                id: "set-tread", sessionId: "s-tread", exerciseId: slug,
                setIndex: 1, weightKg: 0, reps: 0, setType: "warmup",
                exerciseOrder: 0, durationSec: 300, incline: 2, distanceKm: 0.4
            ).insert(db)
        }

        let page = try #require(SessionAnalysis.page(database: database, sessionId: "s-tread"))
        let bout = try #require(page.report.exercises.first)
        #expect(bout.canonical == "Treadmill")
        // The prefix, not the brand word: this asserts that an internal KEY
        // never reaches a title. Spelling the brand here would also reject a
        // movement legitimately named after the app, and would have to be
        // re-edited the next time the stamp changes.
        #expect(!bout.canonical.contains(ExerciseSlug.prefix), "no internal key may reach a title")
        // And it still weighs nothing: naming it must not enrol it in tonnage.
        #expect(page.report.tonnageKg == 0)
    }

    // MARK: - §3.3 · no other day's sets on this page

    @Test("the ledger rows are this session's sets and only this session's")
    func noPreviousSetsInTheLedger() throws {
        let database = try AppDatabase.inMemory(deviceId: "no-prev")
        try database.seedRows { db in
            try Exercise(id: "ex-raise", name: "Lateral Raise").insert(db)
            // Last week: four plain sets of the same movement.
            let was = LogicalDay.date(fromISO: "2026-09-01")!.addingTimeInterval(10 * 3600)
            try WorkoutSession(
                id: "s-was", userId: Self.userId, dayKey: "arms", date: "2026-09-01",
                startedAt: was, endedAt: was.addingTimeInterval(47 * 60), durationMin: 47
            ).insert(db)
            for index in 0..<4 {
                try WorkoutSet(
                    id: "was-\(index)", sessionId: "s-was", exerciseId: "ex-raise",
                    setIndex: index + 1, weightKg: 5, reps: 15, exerciseOrder: 0, foldOrder: index
                ).insert(db)
            }
            // This week: ONE unsided set and three L/R pairs — the 2026-09-08
            // Single Arm Lateral Raise, which is four sets stored as seven rows.
            let now = LogicalDay.date(fromISO: "2026-09-08")!.addingTimeInterval(10 * 3600)
            try WorkoutSession(
                id: "s-now", userId: Self.userId, dayKey: "arms", date: "2026-09-08",
                startedAt: now, endedAt: now.addingTimeInterval(76 * 60), durationMin: 76
            ).insert(db)
            try WorkoutSet(
                id: "now-solo", sessionId: "s-now", exerciseId: "ex-raise",
                setIndex: 1, weightKg: 5, reps: 16, exerciseOrder: 0, foldOrder: 0
            ).insert(db)
            var fold = 1
            for (pair, reps) in [("p1", 15), ("p2", 19), ("p3", 15)] {
                for side in ["left", "right"] {
                    try WorkoutSet(
                        id: "now-\(pair)-\(side)", sessionId: "s-now", exerciseId: "ex-raise",
                        setIndex: fold + 1, weightKg: 5, reps: reps, side: side, pairId: pair,
                        exerciseOrder: 0, foldOrder: fold
                    ).insert(db)
                    fold += 1
                }
            }
        }

        let page = try #require(SessionAnalysis.page(database: database, sessionId: "s-now"))
        let raise = try #require(page.report.exercises.first)

        // Seven rows, three pairs folded: FOUR ledger rows, one per set the
        // athlete actually performed. Before this change each of them also
        // carried a set from 1 September, so a four-set movement drew eight
        // numbers and half of them were from another workout.
        #expect(raise.rows.count == 4)
        #expect(raise.rows.filter { $0.kind == "pair" }.count == 3)
        #expect(raise.rows.compactMap(\.num) == [1, 2, 3, 4])

        // The comparison is not lost — it moved to the header capsule, which
        // reads the previous session WHOLE rather than positionally.
        #expect(raise.prevDate == "2026-09-01")
        #expect(raise.previousSets.count == 4)
    }

    // MARK: - §2 · the editing gate

    @Test("a session holding L/R pairs is editable, and the deck does not double it")
    func pairedSessionEditsWithoutDoubling() throws {
        // `canEdit` refused any session containing a pair, because the logger
        // "has no split concept". It does: `SetRow` carries `side` and
        // `pairId`, `restoreLoggedSets` restores them and `ExerciseState.
        // volumeKg` routes through `SessionVolume`. This is that claim, made
        // against the deck the Edit button opens.
        let database = try AppDatabase.inMemory(deviceId: "paired-edit")
        let name = "Single Arm Lateral Raise"
        let exerciseId = ExerciseSlug.id(name)
        try database.seedRows { db in
            try Exercise(id: exerciseId, name: name).insert(db)
            let start = LogicalDay.date(fromISO: "2026-09-08")!.addingTimeInterval(10 * 3600)
            try WorkoutSession(
                id: "s-pair", userId: Self.userId, dayKey: "arms", date: "2026-09-08",
                startedAt: start, endedAt: start.addingTimeInterval(76 * 60), durationMin: 76
            ).insert(db)
            // One pair, deliberately ASYMMETRIC: 5 × 15 left, 5 × 18 right. The
            // weaker side is the set (75 kg); summed literally it is 165.
            for (index, (side, reps)) in [("left", 15), ("right", 18)].enumerated() {
                try WorkoutSet(
                    id: "pair-\(side)", sessionId: "s-pair", exerciseId: exerciseId,
                    setIndex: 1, weightKg: 5, reps: reps, side: side, pairId: "p1",
                    exerciseOrder: 0, foldOrder: index
                ).insert(db)
            }
        }

        let session = try #require(try database.session(id: "s-pair"))
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "arms"), phase: .cut,
            store: database, userId: Self.userId, startedAt: session.startedAt ?? Date()
        )
        model.attach(editing: session)
        #expect(model.isEditing)

        let raise = try #require(model.exercises.first { $0.name == name })
        let restored = raise.rows.filter(\.isDone)
        #expect(restored.count == 2, "a split set restores split")
        #expect(restored.compactMap(\.pairId) == ["p1", "p1"])
        #expect(Set(restored.compactMap(\.sideLabel)) == ["L", "R"])

        // The gate's own stated fear, measured: the deck must reach the SAME
        // tonnage the save path wrote, not nearly double it.
        #expect(raise.volumeKg() == 75)
        #expect(LoggerModel.physical(restored) == 1, "two rows, one set of work")
    }
}
