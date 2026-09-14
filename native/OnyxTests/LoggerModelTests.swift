import Foundation
import Testing
import GRDB
import OnyxCore
import OnyxData
import OnyxUI
@testable import Onyx

/// The logger's own state machine.
///
/// ── WHY THIS TARGET EXISTS AT ALL ───────────────────────────────────────────
/// `OnyxCore` and `OnyxData` test on the command line in seconds, which is
/// why almost everything provable lives there. `LoggerModel` cannot: it is
/// `@MainActor`, it holds `@Observable` view state, and the rule it enforces —
/// what happens to sets you have ALREADY LOGGED when the prescription changes
/// under them — is not domain arithmetic and has nowhere else to go.
///
/// It is also the code in this wave that was wrong twice. Both faults below had
/// the same shape: a rebuild that honoured the new prescription by quietly
/// discarding work the old one had produced.
@MainActor
@Suite("Logger model")
struct LoggerModelTests {

    /// Total paused, open interval included. `PauseControlling` publishes the
    /// two halves (`pausedTotal` banked, `pausedAt` open) and derives `elapsed`
    /// from them; the sum is only ever wanted by a test.
    private func pausedSecondsOf(_ model: LoggerModel, at now: Date) -> TimeInterval {
        model.pausedTotal + (model.pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    private func armsBulk() -> LoggerModel {
        LoggerModel(day: PlanTemplates.day("onyx5", "arms"), phase: .bulk)
    }

    private func log(_ model: LoggerModel, _ name: String, sets: Int) {
        guard let exercise = model.exercises.first(where: { $0.name == name }) else {
            Issue.record("no exercise named \(name)")
            return
        }
        for index in 0..<sets {
            while exercise.rows.count <= index { model.addSet(to: exercise) }
            let row = exercise.rows[index]
            row.weightKg = 20
            row.reps = 10
            model.toggleDone(row, in: exercise)
        }
    }

    @Test("switching to a cut keeps a dropped lift that already carries work")
    func cutDoesNotEraseLoggedSets() {
        let model = armsBulk()
        // `Seated DB Wrist Curl` is `cutSets: 0` — the cut drops it entirely.
        #expect(model.exercises.contains { $0.name == "Seated DB Wrist Curl" })
        log(model, "Seated DB Wrist Curl", sets: 2)

        model.phase = .cut

        let survivor = model.exercises.first { $0.name == "Seated DB Wrist Curl" }
        #expect(survivor != nil, "a lift with logged sets must not vanish with the prescription")
        #expect(survivor?.rows.count == 2)
        #expect(survivor?.rows.allSatisfy(\.isDone) == true)
        // ...and the blanks it no longer prescribes are gone. `Single Arm
        // Lateral Raise` is the arms lift the cut actually trims (5 → 4);
        // Cable Overhead Extension used to be one and stopped being one in
        // `ca9bcfa`, when Week 6's real set counts became the program's.
        //
        // Counted in SETS, not in rows: this movement is unilateral, so the
        // deck opens it split and four sets is eight rows. `physical` is the
        // rule — each `pairId` once — and it is the number the card, the
        // header and `set_count` all use.
        let trimmed = model.exercises.first { $0.name == "Single Arm Lateral Raise" }
        #expect(trimmed.map { LoggerModel.physical($0.rows) } == 4)
    }

    @Test("a dropped lift with NO logged work does leave")
    func cutDropsUntouchedLifts() {
        let model = armsBulk()
        model.phase = .cut
        #expect(model.exercises.contains { $0.name == "Seated DB Wrist Curl" } == false)
        // Seven lifts plus the treadmill the deck now opens with — see
        // `LoggerModel.withWarmupCardio`. Counted as "the program's movements
        // plus the opener" rather than as a literal 8, so this reads as the
        // prescription it is testing and not as a number somebody has to guess
        // the provenance of.
        #expect(model.exercises.count == 7 + 1)
        #expect(model.exercises.first?.name == WarmupCardio.name)
    }

    @Test("trimming sets does not reorder the ones already logged")
    func rebuildPreservesRowOrder() {
        let model = armsBulk()
        // Bulk prescribes 5 of these; cut prescribes 4. Tick the LAST one only,
        // so a rebuild that sorts ticked rows to the top is visible. (DB Hammer
        // Curl was this test's lift until `ca9bcfa` made its cut count equal
        // its bulk count — a deck that trims nothing cannot show a reorder.)
        let exercise = model.exercises.first { $0.name == "Single Arm Lateral Raise" }!
        // Unilateral, so five prescribed sets are TEN rows — an L and an R
        // each. The rule under test is about ORDER, and it holds per row.
        #expect(LoggerModel.physical(exercise.rows) == 5)
        #expect(exercise.rows.count == 10)
        let ids = exercise.rows.map(\.id)
        let last = exercise.rows[9]
        last.weightKg = 5
        last.reps = 15
        model.toggleDone(last, in: exercise)

        model.phase = .cut

        let rebuilt = model.exercises.first { $0.name == "Single Arm Lateral Raise" }!
        #expect(LoggerModel.physical(rebuilt.rows) == 4)
        // The logged row is still LAST, not promoted to the front.
        #expect(rebuilt.rows.last?.id == ids[9])
        #expect(rebuilt.rows.first?.id == ids[0])
    }

    @Test("a set with no reps cannot be ticked")
    func repsAreRequiredToLog() {
        let model = armsBulk()
        // The first LIFT, not `exercises[0]` — the deck opens with the
        // treadmill, and a cardio row is deliberately tickable without reps
        // (`toggleDone`'s `|| row.isCardio`). Asking the opener this question
        // tests the exemption, not the rule.
        let exercise = model.exercises.first { !$0.rows.contains(where: \.isCardio) }!
        let row = exercise.rows[0]
        row.weightKg = 28
        row.reps = nil

        #expect(model.toggleDone(row, in: exercise) == false)
        #expect(row.isDone == false)
        // Zero tonnage, and no rest timer started for a set that did not happen.
        #expect(model.totalVolumeKg == 0)
        #expect(model.restEndsAt == nil)
    }

    @Test("a zero-kilogram set is real work and a nil load is not zero")
    func bodyweightSetsCount() {
        let model = LoggerModel(day: PlanTemplates.day("onyx5", "legs_b"), phase: .cut)
        let raise = model.exercises.first { $0.name == "Hanging Knee Raise" }!
        // The deck seeds no load for it, and nil is not 0 — nothing has silently
        // become a zero-kilogram set on the way in.
        #expect(raise.rows[0].weightKg == nil)

        raise.rows[0].weightKg = 0
        raise.rows[0].reps = 12
        #expect(model.toggleDone(raise.rows[0], in: raise))
        #expect(raise.physicalSets == 1)
        // Zero tonnage, but a set that counts everywhere sets are counted.
        #expect(model.totalVolumeKg == 0)
        #expect(model.completedSets == 1)
    }

    @Test("warm-ups count for the body and not for the prescription")
    func warmupsCountOnlyWhereTheyShould() {
        let model = armsBulk()
        let press = model.exercises.first { $0.name == "Shoulder Press" }!
        press.rows[0].weightKg = 12
        press.rows[0].reps = 15
        model.setKind(.warmup, on: press.rows[0], in: press)
        model.toggleDone(press.rows[0], in: press)

        #expect(press.physicalSets == 1)   // the body was asked to do it
        #expect(press.workingSets == 0)    // the program was not
        #expect(model.completedSets == 0)

        // And it reaches the muscle sheet, because that is the one question a
        // warm-up genuinely answers.
        #expect(model.muscleSets[.frontDelts] == 1)
        #expect(model.muscleSets[.triceps] == 0.5)
    }

    @Test("a ghost set counts for nothing, anywhere")
    func ghostSetsAreExcluded() {
        let model = armsBulk()
        let press = model.exercises.first { $0.name == "Shoulder Press" }!
        press.rows[0].weightKg = 28
        press.rows[0].reps = 10
        model.toggleDone(press.rows[0], in: press)
        model.setKind(.ghost, on: press.rows[0], in: press)

        #expect(press.physicalSets == 0)
        #expect(press.volumeKg == 0)
        #expect(model.muscleSets.isEmpty)
    }

    @Test("ticking a set starts the movement's own prescribed rest")
    func tickStartsRest() {
        let model = armsBulk()
        let press = model.exercises.first { $0.name == "Shoulder Press" }!
        #expect(press.plan.restSec == 105)
        press.rows[0].weightKg = 28
        press.rows[0].reps = 10
        model.toggleDone(press.rows[0], in: press)

        #expect(model.restDuration == 105)
        #expect(model.restingExercise == "Shoulder Press")

        // Pulling the clock below now ENDS it rather than counting negative.
        model.adjustRest(by: -600)
        #expect(model.restEndsAt == nil)
        #expect(model.restingExercise == nil)
    }

    // The volume-curve test left with `LoggerModel.volumeCurve`: the Live
    // Activity's sparkline was removed (`WorkoutActivityCard` says why), and it
    // was the only reader. A test for a shape nothing draws is a test that only
    // makes the next deletion harder.

    @Test("the current set is the first one not yet ticked")
    func currentSetWalksForward() {
        let model = armsBulk()
        // The cursor opens on the TREADMILL, because the deck does — the five
        // minutes at the top of every session is the first thing not yet ticked
        // and the card the logger should be showing you. `withWarmupCardio` is
        // where that block comes from.
        #expect(model.currentSet?.exercise.name == WarmupCardio.name)
        #expect(model.currentSet?.ordinal == 1)

        let warmup = model.exercises[0]
        model.toggleDone(warmup.rows[0], in: warmup)
        #expect(model.currentSet?.exercise.name == "Shoulder Press")

        log(model, "Shoulder Press", sets: 3)
        #expect(model.currentSet?.exercise.name == "Single Arm Lateral Raise")
        // Five SETS, and the cursor counts sets: this movement is unilateral,
        // so it is ten rows.
        #expect(model.currentSet?.total == 5)
    }

    // ── The seed (P3 E4) ────────────────────────────────────────────────────

    @Test("with no store, the deck opens on the program's cold start and says nothing about a previous set")
    func coldStartHasNoPrevious() {
        let model = armsBulk()
        let press = model.exercises.first { $0.name == "Shoulder Press" }!
        #expect(press.rows.count == 3)
        #expect(press.rows.allSatisfy { $0.weightKg == 28 })
        // The rep FLOOR, not the ceiling: the floor is what you walk up to.
        #expect(press.rows.allSatisfy { $0.reps == 8 })
        // ── THE WHOLE OF THE OLD BUG ────────────────────────────────────────
        // This used to read "28kg × 8" — the program's July seed, printed as
        // though it were the last set performed. Nothing was logged, so there
        // is no previous set, and the honest answer is nothing at all.
        #expect(press.rows.allSatisfy { $0.previous == nil })
        #expect(press.rows.allSatisfy { !$0.progressed && !$0.rpeStale })
        #expect(model.seededFrom(press) == nil)
    }

    @Test("a movement the program prescribes no load for seeds nil, not zero")
    func nilLoadIsNotZero() {
        let model = LoggerModel(day: PlanTemplates.day("onyx5", "legs_b"), phase: .cut)
        let raise = model.exercises.first { $0.name == "Hanging Knee Raise" }!
        #expect(raise.rows[0].weightKg == nil)
    }

    // ── The session clock (P3 E4) ───────────────────────────────────────────

    @Test("pause stops the clock and resume starts it again")
    func pauseStopsTheClock() {
        let start = Date(timeIntervalSince1970: 1_757_000_000)
        let model = LoggerModel(day: PlanTemplates.day("onyx5", "arms"), phase: .bulk, startedAt: start)
        #expect(model.isPaused == false)
        #expect(model.elapsed(at: start.addingTimeInterval(600)) == 600)

        model.pause(at: start.addingTimeInterval(600))
        #expect(model.isPaused)
        // Ten minutes in, paused: the number stops moving however long you wait.
        #expect(model.elapsed(at: start.addingTimeInterval(600)) == 600)
        #expect(model.elapsed(at: start.addingTimeInterval(3_000)) == 600)
        #expect(pausedSecondsOf(model, at: start.addingTimeInterval(3_000)) == 2_400)

        model.resume(at: start.addingTimeInterval(3_000))
        #expect(model.isPaused == false)
        #expect(model.elapsed(at: start.addingTimeInterval(3_600)) == 1_200)
    }

    @Test("pausing twice does not bank the interval twice")
    func doublePauseIsIdempotent() {
        let start = Date(timeIntervalSince1970: 1_757_000_000)
        let model = LoggerModel(day: PlanTemplates.day("onyx5", "arms"), phase: .bulk, startedAt: start)
        model.pause(at: start.addingTimeInterval(60))
        model.pause(at: start.addingTimeInterval(120))
        model.resume(at: start.addingTimeInterval(180))
        #expect(pausedSecondsOf(model, at: start.addingTimeInterval(600)) == 120)
        // A stray resume is not an interval either.
        model.resume(at: start.addingTimeInterval(240))
        #expect(pausedSecondsOf(model, at: start.addingTimeInterval(600)) == 120)
    }

    @Test("the clock never runs backwards")
    func clockNeverNegative() {
        let start = Date(timeIntervalSince1970: 1_757_000_000)
        let model = LoggerModel(day: PlanTemplates.day("onyx5", "arms"), phase: .bulk, startedAt: start)
        #expect(model.elapsed(at: start.addingTimeInterval(-600)) == 0)
    }

    // ── Live records (P3 E4) ────────────────────────────────────────────────

    @Test("with no store there are no baselines, so nothing claims a record")
    func previewsClaimNoRecords() {
        // The engine runs against `PrBaselines.empty` in previews. An empty bar
        // is not "everything is a record": `PrTruth.floor` and the engine's own
        // eligibility rules still gate it, and the count that matters is the one
        // the ledger will write.
        let model = armsBulk()
        log(model, "Shoulder Press", sets: 1)
        #expect(model.recordCount == model.prsThisSession)
    }

    // ── The deck the seed builds, against a real store ──────────────────────

    /// One finished Upper A on `date`, with a warm-up and three working sets of
    /// Face Pull.
    private func seeded(_ date: String) throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "test")
        let id = ExerciseSlug.id("Face Pull")
        try db.seedRows { conn in
            try Exercise(id: id, name: "Face Pull").insert(conn)
            try WorkoutSession(
                id: "s1", userId: "u1", dayKey: "cb_a", date: date,
                startedAt: LogicalDay.date(fromISO: date)
            ).insert(conn)
            try WorkoutSet(id: "w", sessionId: "s1", exerciseId: id, setIndex: 1,
                           weightKg: 5, reps: 15, setType: "warmup").insert(conn)
            for i in 0..<3 {
                try WorkoutSet(id: "n\(i)", sessionId: "s1", exerciseId: id, setIndex: i + 2,
                               weightKg: 16.25, reps: 15 - i).insert(conn)
            }
        }
        return db
    }

    @Test("the deck opens on the last session's numbers, warm-up included")
    func seedsFromHistory() throws {
        let db = try seeded("2026-08-24")
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "cb_a"), phase: .cut, store: db, userId: "u1"
        )
        let face = model.exercises.first { $0.name == "Face Pull" }!
        #expect(face.rows.map(\.kind) == [.warmup, .normal, .normal, .normal])
        #expect(face.rows.filter { $0.kind == .normal }.map(\.weightKg) == [16.25, 16.25, 16.25])
        #expect(face.rows.filter { $0.kind == .normal }.map(\.reps) == [15, 14, 13])
        #expect(model.seededFrom(face) == "2026-08-24")
    }

    @Test("the Previous column is about the right WORKING set, not the right row")
    func previousIsWorkingOrdinal() throws {
        // The seed carries a warm-up, so a row index counts one more than a
        // working ordinal. Reading the labels off the row index shifts every
        // one of them by the warm-up count.
        let db = try seeded("2026-08-24")
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "cb_a"), phase: .cut, store: db, userId: "u1"
        )
        let face = model.exercises.first { $0.name == "Face Pull" }!
        #expect(face.rows[0].previous == "5kg × 15", "the warm-up's own set")
        #expect(face.rows[1].previous == "16.25kg × 15")
        #expect(face.rows[2].previous == "16.25kg × 14")
        #expect(face.rows[3].previous == "16.25kg × 13")
    }

    @Test("a phase switch does not count ticked warm-ups against the prescription")
    func warmupsAreNotPrescribed() throws {
        // Upper A prescribes 3 working sets of Face Pull on a cut and 3 on a
        // bulk, so `Single Arm Lateral Raise` is the lift that trims —
        // but the failure this guards is about the WARM-UP row, so Face Pull is
        // the case: tick the warm-up and one working set, switch phase, and a
        // rule that counts the warm-up sees 2 of 3 rather than 1 of 3.
        let db = try seeded("2026-08-24")
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "cb_a"), phase: .cut, store: db, userId: "u1"
        )
        let face = model.exercises.first { $0.name == "Face Pull" }!
        for row in face.rows.prefix(2) {
            row.reps = row.reps ?? 10
            model.toggleDone(row, in: face)
        }
        model.phase = .bulk

        let rebuilt = model.exercises.first { $0.name == "Face Pull" }!
        #expect(rebuilt.rows.filter { $0.kind != .warmup }.count == 3,
                "all three working sets survive; two of them are still to do")
        #expect(rebuilt.rows.contains { $0.kind == .warmup }, "and the warm-up is not thrown away")
    }

    // ── Rejoining a session the system killed (W7) ──────────────────────────

    /// The clock has to survive iOS terminating the app mid-workout.
    ///
    /// `attach()` restored the session id, the pause ledger and every logged
    /// set, and left `startedAt` where `init` put it — at the instant of
    /// resumption. Forty minutes of training came back onto a deck claiming to
    /// be seconds old, and every reader of the session clock believed it: the
    /// hero's timer, the Live Activity, and `closeSession`'s `duration_min`.
    ///
    /// The row already held the right answer — `ensureSession` writes it at the
    /// first append — so nothing new is persisted here. The read was throwing
    /// it away.
    @Test("rejoining a killed session keeps the original start, not the resume instant")
    func attachRestoresTheClock() throws {
        let db = try AppDatabase.inMemory(deviceId: "resume-test")
        let began = Date().addingTimeInterval(-40 * 60)
        let id = ExerciseSlug.id("Face Pull")
        try db.seedRows { conn in
            try Exercise(id: id, name: "Face Pull").insert(conn)
            // `ended_at` nil and dated TODAY — the predicate `liveSession` runs.
            try WorkoutSession(
                id: "s-live", userId: "u1", dayKey: "cb_a", date: LogicalDay.today(),
                startedAt: began
            ).insert(conn)
            try WorkoutSet(id: "n1", sessionId: "s-live", exerciseId: id, setIndex: 1,
                           weightKg: 16.25, reps: 15).insert(conn)
        }
        // Built the way a relaunch builds it: a brand-new model whose clock
        // starts NOW, with no idea a session is already running.
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "cb_a"), phase: .cut, store: db, userId: "u1"
        )
        model.attach()

        #expect(model.sessionId == "s-live")
        #expect(abs(model.startedAt.timeIntervalSince(began)) < 1,
                "the stored instant, not the resume instant")
        #expect(model.elapsed() > 39 * 60,
                "the forty minutes already trained are still on the clock")
    }

    /// A deck opened on a day with no live session keeps its own clock.
    ///
    /// The restore must not reach for a session that is not there and must not
    /// fall back to something older than the deck — `LogicalDay.date(fromISO:)`
    /// is midnight, and a deck opened at 18:00 that adopted it would open
    /// claiming eighteen hours of training.
    @Test("with no live session the deck keeps the clock it opened with")
    func attachWithoutALiveSessionKeepsTheOpeningClock() throws {
        let db = try AppDatabase.inMemory(deviceId: "resume-test-2")
        let opened = Date().addingTimeInterval(-90)
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "cb_a"), phase: .cut, store: db, userId: "u1",
            startedAt: opened
        )
        model.attach()

        #expect(model.sessionId == nil)
        #expect(model.startedAt == opened)
    }

    // MARK: - Timeline dots and the next movement (D6)

    /// The opening bout. Every deck built without a store opens with one
    /// (`withWarmupCardio`), and it is the only exercise in the app whose rows
    /// are all cardio.
    private func bout(_ model: LoggerModel) -> LoggerModel.ExerciseState? {
        model.exercises.first { $0.rows.allSatisfy(\.isCardio) && !$0.rows.isEmpty }
    }

    @Test("a ticked cardio bout fills its dot")
    func cardioDotFillsOnTick() throws {
        let model = armsBulk()
        let cardio = try #require(bout(model))

        #expect(model.dotProgress(for: cardio).done == 0)
        #expect(model.dotProgress(for: cardio).planned == 1,
                "one bout is one dot, never zero")

        model.toggleDone(cardio.rows[0], in: cardio)

        #expect(model.dotProgress(for: cardio).done == 1)
        #expect(model.dotProgress(for: cardio).planned == 1)
    }

    /// The invariant the Live Activity audits: the bout is a warm-up and a
    /// warm-up is not work.
    @Test("ticking the bout leaves working sets, tonnage and the PR engine alone")
    func cardioTickIsNotAWorkingSet() throws {
        let model = armsBulk()
        let cardio = try #require(bout(model))
        let volume = model.totalVolumeKg
        let records = model.recordCount

        model.toggleDone(cardio.rows[0], in: cardio)

        #expect(cardio.workingSets == 0)
        #expect(model.completedSets == 0)
        #expect(model.totalVolumeKg == volume)
        #expect(model.recordCount == records)
    }

    @Test("a lifting exercise keeps the timeline's own arithmetic")
    func liftingDotProgressIsTodaysRule() throws {
        let model = armsBulk()
        let lift = try #require(model.exercises.first { $0.name == "Single Arm Lateral Raise" })
        log(model, "Single Arm Lateral Raise", sets: 2)

        let prescribed = lift.rows.filter { $0.kind != .warmup && $0.kind != .ghost }
        let expected = max(lift.plan.sets(for: model.phase), LoggerModel.physical(prescribed))
        let read = model.dotProgress(for: lift)

        #expect(read.done == lift.workingSets)
        #expect(read.planned == expected)
    }
}
