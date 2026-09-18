import Foundation
import Testing
import GRDB
import OnyxCore
import OnyxData
@testable import Onyx

/// The Delts & Arms session of 2026-09-15, end to end.
///
/// ── WHY THIS SUITE EXISTS AND WHAT IT IS NOT ────────────────────────────────
/// `DeckRestoreTests` and `SessionRunTests` hold the ARITHMETIC in OnyxCore,
/// exhaustively and with no database in sight. This is the other half: that the
/// model actually routes through them, with a real store, on the deck the
/// symptoms were reported against.
///
/// Three things went wrong in one workout and every one of them was silent:
///
///   1. A crash, then a relaunch onto the dashboard with the deck still live.
///   2. Sets 5 and 6 appearing under a movement prescribed four.
///   3. The treadmill warm-up drawn twice on the edit deck, both copies ticked.
///
/// They share one cause between them — the deck rebuilding itself from a log it
/// matched loosely and counted in the wrong unit — so they share one suite.
@MainActor
@Suite("Live state restore")
struct LiveStateRestoreTests {

    /// The bout this fixture's athlete last logged, and therefore the one their
    /// decks open with.
    ///
    /// Local to the suite: `WarmupCardio` names no bout of its own any more —
    /// the opener is read off `cardio_logs`, so a fixture that wants one has to
    /// log one. `walkedStore` seeds exactly this row.
    private nonisolated static let bout = WarmupCardio.Bout(
        name: "Treadmill", durationSec: 300, distanceKm: 0.37, inclinePct: 2
    )

    private nonisolated static let userId = "00000000-0000-0000-0000-00000000000a"
    private nonisolated static let sessionId = "s-arms"
    private nonisolated static let date = "2026-09-15"

    /// `nonisolated` because `seedRows` takes a `@Sendable` closure and the
    /// suite is `@MainActor` — the same reason `SessionEditModeTests` spells
    /// its ids as static constants.
    private nonisolated static func armsDay() -> ProgramDay { PlanTemplates.day("onyx5", "arms") }
    private func armsDay() -> ProgramDay { Self.armsDay() }

    /// The lift the whole wave is named after: prescribed four sets, trained one
    /// arm at a time, so the deck carries EIGHT rows for it.
    private func lateralRaise(_ model: LoggerModel) -> LoggerModel.ExerciseState? {
        model.exercises.first { $0.name == "Single Arm Lateral Raise" }
    }

    /// A live session with `pairs` sets of the lateral raise already logged,
    /// each split L/R — the state the app was jetsammed in.
    private func liveStore(pairs: Int, ended: Bool = false) throws -> AppDatabase {
        let database = try AppDatabase.inMemory(deviceId: "restore-test")
        let start = Date().addingTimeInterval(-2 * 3600)
        try database.seedRows { db in
            try Exercise(id: "ex-lateral", name: "Single Arm Lateral Raise").insert(db)
            try WorkoutSession(
                id: Self.sessionId, userId: Self.userId, dayKey: Self.armsDay().key,
                date: LogicalDay.today(),
                startedAt: start,
                endedAt: ended ? start.addingTimeInterval(3600) : nil,
                durationMin: ended ? 60 : nil
            ).insert(db)
            var fold = 0
            for pair in 0..<pairs {
                for side in ["left", "right"] {
                    try WorkoutSet(
                        id: "lat-\(pair)-\(side)", sessionId: Self.sessionId, exerciseId: "ex-lateral",
                        setIndex: pair + 1, weightKg: 10, reps: 12, setType: "normal",
                        side: side, pairId: "pair-\(pair)",
                        est1rmKg: OneRepMax.estimate(weight: 10, reps: 12),
                        exerciseOrder: 0, foldOrder: fold
                    ).insert(db)
                    fold += 1
                }
            }
        }
        return database
    }

    // MARK: - Sets 5 and 6

    @Test("a unilateral movement reopens at its prescription, not at twice the shortfall")
    func restoreDoesNotInventSets() throws {
        // Four prescribed, two logged. The old arithmetic subtracted ROWS
        // (8 − 4 = 4) and spent the answer as SETS, which `seedRows` then
        // pre-split into eight more rows: twelve rows, SIX sets, and sets 5 and
        // 6 were tickable rows the program never asked for.
        // The prescription is read off the deck rather than hardcoded — it is
        // a `routines` row and it moves. What is asserted is the RELATION: a
        // reopened card shows what it prescribed, never twice the shortfall.
        let store = try liveStore(pairs: 2)
        let model = LoggerModel(day: armsDay(), phase: .bulk, store: store, userId: Self.userId)
        guard let card = lateralRaise(model) else {
            Issue.record("Delts & Arms has no Single Arm Lateral Raise")
            return
        }
        let prescribed = LoggerModel.physical(card.rows)
        #expect(prescribed >= 2, "the fixture logs two sets and needs room for them")
        #expect(card.rows.count == prescribed * 2, "the deck opens pre-split")

        model.attach()
        #expect(LoggerModel.physical(card.rows) == prescribed, "\(prescribed) sets, not \(2 * prescribed - 2)")
        #expect(card.rows.count == prescribed * 2, "and two rows per set, still")
        #expect(card.rows.filter(\.isDone).count == 4, "the two logged pairs came back ticked")
        #expect(card.rows.allSatisfy { $0.pairId != nil }, "the blanks are pairs too")
    }

    @Test("every shortfall on a unilateral deck restores to the prescription")
    func restoreIsCorrectAtEveryShortfall() throws {
        let prescribed = LoggerModel.physical(
            lateralRaise(LoggerModel(day: armsDay(), phase: .bulk))?.rows ?? []
        )
        // Past the prescription too: logging MORE than was asked for must grow
        // the card, not shrink it back.
        for logged in 0...(prescribed + 2) {
            let store = try liveStore(pairs: logged)
            let model = LoggerModel(day: armsDay(), phase: .bulk, store: store, userId: Self.userId)
            model.attach()
            guard let card = lateralRaise(model) else { continue }
            #expect(
                LoggerModel.physical(card.rows) == max(prescribed, logged),
                "\(logged) logged of \(prescribed): got \(LoggerModel.physical(card.rows)) sets"
            )
            #expect(card.rows.filter(\.isDone).count == logged * 2)
        }
    }

    @Test("attaching twice adds nothing — the bug fired on every re-open")
    func restoreIsIdempotent() throws {
        let store = try liveStore(pairs: 2)
        let model = LoggerModel(day: armsDay(), phase: .bulk, store: store, userId: Self.userId)
        model.attach()
        let first = model.exercises.map { LoggerModel.physical($0.rows) }
        // `attach`'s own guard makes a second call a no-op, so the restore is
        // driven directly — which is what tapping Edit on the same session did.
        model.attach()
        #expect(model.exercises.map { LoggerModel.physical($0.rows) } == first)
    }

    // MARK: - The treadmill, twice

    /// A FINISHED session that opens with a treadmill bout, plus the catalogue
    /// row that makes the deck prepend one — the exact shape `editorDay` builds.
    private func walkedStore() throws -> (AppDatabase, WorkoutSession) {
        let database = try AppDatabase.inMemory(deviceId: "restore-test")
        let start = LogicalDay.date(fromISO: "2026-09-08")!.addingTimeInterval(17 * 3600)
        let session = WorkoutSession(
            id: "s-walked", userId: Self.userId, dayKey: Self.armsDay().key, date: "2026-09-08",
            startedAt: start, endedAt: start.addingTimeInterval(3600), durationMin: 60
        )
        let row = session
        try database.seedRows { db in
            // The catalogue row the performed set points at...
            try Exercise(id: "ex-treadmill", name: Self.bout.name, slug: ExerciseSlug.id(Self.bout.name)).insert(db)
            // ...and the LOGGED bout, which is what turns the prepend on at
            // all now. Without it this athlete has never done cardio, the deck
            // opens with no opener, and the duplicate this suite is named for
            // could not be reproduced.
            try CardioLogRow(
                id: "cardio-1", userId: Self.userId, date: "2026-09-07", kind: "treadmill",
                distanceM: (Self.bout.distanceKm ?? 0) * 1000,
                durationMin: Double(Self.bout.durationSec) / 60,
                inclinePct: Self.bout.inclinePct
            ).insert(db)
            try row.insert(db)
            try WorkoutSet(
                id: "tread-1", sessionId: "s-walked", exerciseId: "ex-treadmill",
                setIndex: 1, weightKg: 0, reps: 0, setType: "warmup",
                exerciseOrder: 0,
                durationSec: Self.bout.durationSec, incline: Self.bout.inclinePct,
                distanceKm: Self.bout.distanceKm, foldOrder: 0
            ).insert(db)
        }
        return (database, session)
    }

    /// `SessionDetailView.editorDay`'s shape: the session's own movements, in
    /// performed order, as a day.
    private func walkedDay() -> ProgramDay {
        ProgramDay(
            key: armsDay().key, label: "Delts & Arms", accent: 0x8A8A8E, weekday: 0,
            exercises: [ProgramExercise(Self.bout.name, sets: 1, cutSets: 1, wk1Kg: nil, reps: "5 min", restSec: 90)]
        )
    }

    @Test("an edit deck that already walks is not given a second treadmill")
    func warmupIsNotPrepiendedOntoItself() throws {
        // The chain that produced the duplicate: `editorDay` puts the performed
        // Treadmill in the deck; `init` seeds it with blank rows, and
        // `SeedRow` carries no `durationSec`, so `rows.contains(isCardio)` was
        // FALSE and a second card was prepended. `restoreLoggedSets` then fed
        // the same logged bout to both, both ticked, and the `removeAll` that
        // was supposed to clean up refused to drop either.
        let (store, session) = try walkedStore()
        let model = LoggerModel(
            day: walkedDay(), phase: .cut, store: store, userId: Self.userId,
            startedAt: session.startedAt ?? Date()
        )
        model.attach(editing: session)

        let treadmills = model.exercises.filter {
            ExerciseAliases.canonicalName($0.name) == ExerciseAliases.canonicalName(Self.bout.name)
        }
        #expect(treadmills.count == 1, "one card, not one at the top and one at the bottom")
        #expect(treadmills.first?.rows.filter(\.isDone).count == 1, "and the bout it holds is the one that was walked")
        #expect(model.exercises.count == 1)
    }

    @Test("a card's identity is its own, so a namesake can never be fatal")
    func cardIdentitiesAreUnique() throws {
        let store = try liveStore(pairs: 1)
        let model = LoggerModel(day: armsDay(), phase: .bulk, store: store, userId: Self.userId)
        model.attach()
        let ids = model.exercises.map(\.id)
        #expect(Set(ids).count == ids.count, "a duplicate id in a ForEach is undefined and fatal in a LazyVStack")
        #expect(!ids.contains { $0 == Self.bout.name }, "and it is not the movement's name any more")
    }

    @Test("a phase switch over a deck with a namesake card does not trap")
    func phaseSwitchSurvivesADuplicate() throws {
        // `rebuildForPhase` built `Dictionary(uniqueKeysWithValues:)` from the
        // cards' ids, which TRAPS on a duplicate — so the crash did not need a
        // view at all, only a phase toggle.
        let (store, session) = try walkedStore()
        let model = LoggerModel(
            day: walkedDay(), phase: .cut, store: store, userId: Self.userId,
            startedAt: session.startedAt ?? Date()
        )
        model.attach(editing: session)
        model.phase = .bulk
        model.phase = .cut
        #expect(model.exercises.count == 1)
    }

    // MARK: - The clock

    @Test("rejoining a live session restores its start, not the moment it reopened")
    func clockSurvivesTheKill() throws {
        let store = try liveStore(pairs: 2)
        let model = LoggerModel(day: armsDay(), phase: .bulk, store: store, userId: Self.userId)
        model.attach()
        // The fixture opened two hours ago.
        #expect(abs(model.elapsed() - 2 * 3600) < 5, "got \(model.elapsed()) s")
    }

    @Test("a session terminated while paused comes back running, not at 0:00")
    func abandonedPauseDoesNotReadZero() throws {
        let store = try liveStore(pairs: 2)
        // Pause the session an hour ago and never resume it — the log's state
        // after a jetsam. `pausedSeconds` would hand the deck the whole hour,
        // `timerOrigin` would land in the future, and the hero would print
        // `0:00` on a workout two hours old.
        try store.seedRows { db in
            try SetEvent(
                id: "ev-pause", sessionId: Self.sessionId, setId: Self.sessionId,
                deviceId: "restore-test", seq: 1,
                createdAt: Date().addingTimeInterval(-3600),
                body: .pause
            ).insert(db)
        }
        let model = LoggerModel(day: armsDay(), phase: .bulk, store: store, userId: Self.userId)
        model.attach()

        #expect(!model.isPaused, "an hour-old pause is abandoned, not held")
        #expect(model.elapsed() > 0, "and the clock is emphatically not 0:00")
        // Two hours of session, less the fifteen minutes credited as rest.
        #expect(abs(model.elapsed() - (2 * 3600 - SessionRun.openPauseCeilingSec)) < 5)
        #expect(model.storeError != nil, "the repair is said out loud, not swallowed")
    }

    @Test("a start banked before the first set survives a relaunch with no session row")
    func startSurvivesBeforeTheFirstAppend() throws {
        // The window `started_at` could never cover: the deck is open, the
        // warm-up is done, nothing is ticked — so `ensureSession` has not run
        // and there is no row to restore from.
        let database = try AppDatabase.inMemory(deviceId: "restore-test")
        let day = armsDay()
        LiveSessionStart.clear(dayKey: day.key, date: LogicalDay.today())

        let opened = LoggerModel(
            day: day, phase: .bulk, store: database, userId: Self.userId,
            startedAt: Date().addingTimeInterval(-11 * 60)
        )
        opened.attach()
        #expect(opened.sessionId == nil, "nothing logged, so no session row — as designed")

        // …jetsam. A fresh model, built now, the way the Train tab builds one.
        let rejoined = LoggerModel(day: day, phase: .bulk, store: database, userId: Self.userId)
        rejoined.attach()
        #expect(abs(rejoined.elapsed() - 11 * 60) < 5, "got \(rejoined.elapsed()) s")

        LiveSessionStart.clear(dayKey: day.key, date: LogicalDay.today())
    }

    @Test("a banked start older than any real workout is not believed")
    func staleBankedStartIsRefused() {
        let day = armsDay()
        LiveSessionStart.write(Date().addingTimeInterval(-9 * 3600), dayKey: day.key, date: LogicalDay.today())
        #expect(LiveSessionStart.read(dayKey: day.key, date: LogicalDay.today()) == nil)
        LiveSessionStart.clear(dayKey: day.key, date: LogicalDay.today())
        #expect(LiveSessionStart.read(dayKey: day.key, date: LogicalDay.today()) == nil)
    }
}
