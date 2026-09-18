import Foundation
// GRDB, for `AnyDatabaseCancellable` alone — the type `onCommit` hands back.
// Every other database call in this file is `AppDatabase`'s own public API.
import GRDB
import Observation
import OnyxCore
import OnyxData
import OnyxUI
import SwiftUI
import WidgetKit

/// The watch app's whole state.
///
/// ── ONE MODEL, BECAUSE THERE IS ONE SCREEN ──────────────────────────────────
/// The phone splits this across `LoggerModel`, `TodayModel` and a sync
/// coordinator, and it is right to: it has tabs, a history, an editor and a
/// dozen sheets. The watch has a set in front of you, a rest clock, and a
/// dashboard you swipe to. Splitting three screens across three models would
/// buy layering that nothing needs and cost a reader the ability to see the
/// whole app at once.
///
/// ── WHAT IT IS NOT ──────────────────────────────────────────────────────────
/// Not a source of truth, and not a network client. Every write goes through
/// `AppDatabase.appendSet` / `amendSet` / `voidSet`, which commit the event, the
/// outbox row and the re-fold in one transaction. The watch never opens a socket
/// (Wave 10 decision: the phone relays), so `WatchLink` is the only road out and
/// Supabase is reached through the phone's drain.
///
/// The consequence is worth stating plainly rather than discovering: a watch
/// that never sees its phone again keeps its sets locally and nowhere else. That
/// is the accepted cost of not putting a refresh token on the wrist.
@MainActor
@Observable
final class WatchModel {

    // MARK: - Stored

    private(set) var store: AppDatabase?
    private(set) var storeError: String?

    /// Who is signed in, what today is, and how the plan resolves it — sent by
    /// the phone over `updateApplicationContext` and cached so a cold launch out
    /// of range still opens the right split.
    private(set) var context: WatchContext?

    /// The deck for today, resolved from the context. Nil on a rest day, and
    /// nil before the phone has ever spoken to this watch.
    private(set) var day: ProgramDay?

    /// The live session's id, once a set has been logged into it.
    private(set) var sessionId: String?

    /// The instant the session's elapsed clock counts up from.
    ///
    /// ── TWO WRITERS, IN THAT ORDER, AND BOTH ARE RIGHT ──────────────────────
    /// `adopt` sets it from the session row's own `started_at`, which is the
    /// only answer available when this watch is the device running the workout
    /// — there is no pause control on the wrist, so wall time IS elapsed time.
    ///
    /// A `RestPulse` carrying a `timerOrigin` then overwrites it, because the
    /// phone holds the pencil in that case and the phone's number has the
    /// banked pauses already taken out of it. A session paused for eleven
    /// minutes is eleven minutes younger than `started_at` says, and the wrist
    /// showing a different hour from the phone in your hand is worse than the
    /// wrist showing nothing.
    ///
    /// Nil before a session and on a rest pulse from a phone that predates the
    /// field — the toolbar draws no timer rather than a wrong one.
    private(set) var sessionStartedAt: Date?

    /// The fold — every surviving set of this session, in fold order. This is
    /// what makes the watch and the phone agree: it is not a list the watch
    /// maintains, it is the projection `SetEventFold` rebuilds inside every
    /// append, on whichever device made it.
    private(set) var sets: [WorkoutSet] = []

    /// False while the PHONE holds the pencil. The watch then renders the
    /// session live and read-only with one button — see `takePencil`.
    private(set) var holdsPencil = true

    /// The rest clock, or nil. Mirrored to the phone as a `RestPulse`.
    private(set) var rest: RestPulse?

    /// The set being edited right now. Seeded from the plan and from what you
    /// lifted last time, then moved by the Crown.
    var load: Double = 0
    var reps: Int = 0

    /// The `HKWorkoutSession`. See `WorkoutSessionController` — it is the
    /// runtime, not a heart-rate feature.
    let workout = WorkoutSessionController()

    private var link: WatchLink?
    private var setsObserver: AnyDatabaseCancellable?

    // MARK: - Derived

    /// The movements of today's deck, each with the sets already logged
    /// against it.
    ///
    /// Rebuilt from `day` and `sets` on every read rather than cached: the
    /// deck is at most a dozen movements, the fold is already in memory, and a
    /// cache here would be a third answer to "what has been logged" beside the
    /// log and the projection.
    var movements: [Movement] {
        guard let day, let context else { return [] }
        let phase = context.schedule.phase
        return day.exercises(for: phase).enumerated().map { order, plan in
            let ids = Self.identities(of: plan)
            return Movement(
                plan: plan,
                order: order,
                logged: sets.filter { ids.contains($0.exerciseId) && SetTags.isWorkingSet($0.setType) }
            )
        }
    }

    /// Where you are: the first movement with a working set still owed.
    ///
    /// Nil once the deck is finished, which is what turns the tick into a
    /// finish button.
    var cursor: Cursor? {
        for movement in movements where movement.logged.count < movement.plannedSets {
            return Cursor(movement: movement, setNumber: movement.logged.count + 1)
        }
        return nil
    }

    var isFinished: Bool { day != nil && cursor == nil && !sets.isEmpty }

    /// Cut or bulk, as the phone resolved it.
    ///
    /// It is a property of the CONTEXT and never of the watch: the phase toggle
    /// changes set counts across the whole deck, and a watch that guessed it
    /// would prescribe a different workout from the one the phone is showing.
    /// Defaults to `.cut` only for the window before the phone has ever spoken,
    /// where nothing is drawn from it anyway.
    var phase: ProgramPhase { context?.schedule.phase ?? .cut }

    /// Open the session deliberately, from the Start button.
    ///
    /// ── THE ONE PLACE A ROW IS CREATED WITHOUT A SET ────────────────────────
    /// `rejoinLiveSession` is look-up-only for the reason `LoggerModel.attach`
    /// gives: creating on appearing leaves an empty session behind every time
    /// the app is opened and closed, and an empty session is indistinguishable
    /// later from an abandoned workout.
    ///
    /// A tap on Start is not an appearance. It is a person saying they are
    /// training now, and the `HKWorkoutSession` has to begin at that moment
    /// rather than at the first set — the whole point of the workout session is
    /// to be running during the warm-up, when the app would otherwise be
    /// suspended between the first two things you do.
    func beginSession() {
        guard let store, let context, let day, sessionId == nil else { return }
        do {
            let session = try store.openSession(
                userId: context.userId, dayKey: day.key, date: context.today
            )
            adopt(session)
        } catch {
            storeError = String(describing: error)
        }
    }

    /// What this movement cost last time — the one line from the phone's card
    /// worth its width here, because it is the number the next set is chosen
    /// from.
    var lastTime: String? {
        guard let cursor, let previous = cursor.movement.logged.last else { return nil }
        return "\(Deck.fmtKg(previous.weightKg)) kg × \(previous.reps)"
    }

    // MARK: - Lifecycle

    /// Open the store and the link. Called once, from `.task` on the root.
    func start() {
        guard store == nil else { return }
        do {
            // The same folder resolution the phone uses. On the watch there is
            // no App Group container, so this answers Application Support — and
            // that is correct: an App Group is shared between processes on ONE
            // device, and the phone's store is on a different device entirely.
            let database = try AppDatabase.onDisk(folderURL: AppDatabase.sharedFolder())
            store = database
            storeError = nil
        } catch {
            storeError = String(describing: error)
            return
        }

        context = WatchContextCache.load()
        // The cache already persists the context, so the phone's palette
        // survives a relaunch and an out-of-range morning for free. A context
        // from a phone that predates the theme field carries nil — which is
        // the default palette, i.e. exactly what the watch looked like before.
        OnyxTheme.set(context?.theme ?? .default)
        resolveDay()

        let link = WatchLink { [weak self] inbound in
            // WatchConnectivity delivers on its own queue. The store writes are
            // fine there — `ingest` takes its own transaction — but everything
            // that touches this model has to come back to the main actor.
            Task { @MainActor in self?.receive(inbound) }
        }
        link.activate()
        self.link = link

        rejoinLiveSession()
        Task { try? await workout.requestAuthorization() }
    }

    /// Rejoin the session already in progress, if there is one.
    ///
    /// LOOK-UP ONLY, and for the reason `LoggerModel.attach` gives: creating a
    /// row on appearing leaves an empty session behind every time the app is
    /// opened and closed without a set, and an empty session is indistinguishable
    /// later from an abandoned workout. The row is created by the first append.
    private func rejoinLiveSession() {
        guard let store, let day, let context else { return }
        guard let live = try? store.liveSession(dayKey: day.key, date: context.today, userId: context.userId) else { return }
        adopt(live)
    }

    private func adopt(_ session: WorkoutSession) {
        guard let store, sessionId != session.id else { return }
        sessionId = session.id
        // The row's own start. Wall time, and correct here: the watch has no
        // pause control, so nothing has been banked out of it. A phone-driven
        // session overwrites this from the rest pulse — see `sessionStartedAt`.
        sessionStartedAt = session.startedAt
        holdsPencil = (try? store.holdsPencil(sessionId: session.id)) ?? true
        observeSets(session.id)
        seedCursor()
        if !workout.isRunning { workout.start() }
    }

    /// Watch the projection.
    ///
    /// ── WHY `onCommit` AND NOT A `ValueObservation` ─────────────────────────
    /// `AppDatabase.observeSets` returns one, but `AppDatabase.writer` is
    /// internal — deliberately, so nothing outside the package can open a
    /// transaction — and a `ValueObservation` needs a writer to start in. The
    /// public seam is `onCommit`, which is what `TodayModel` already uses on the
    /// phone for the same job.
    ///
    /// It fires after EVERY committed write rather than for this session's rows
    /// alone, which on a phone would be wasteful and here is not: the watch's
    /// store holds one athlete's live workout, this app is its only writer, and
    /// re-reading a session's twenty rows costs less than the bookkeeping to
    /// avoid it.
    ///
    /// This is the line that makes a set logged on the PHONE appear here without
    /// the model knowing a phone exists: the event arrives over `WatchLink`,
    /// `ingest` re-folds, `workout_sets` changes, this fires, and the fold is
    /// read back.
    private func observeSets(_ id: String) {
        guard let store else { return }
        reload(id)
        setsObserver = store.onCommit { [weak self] in
            Task { @MainActor in
                guard let self, self.sessionId == id else { return }
                self.reload(id)
            }
        }
    }

    private func reload(_ id: String) {
        guard let store, let context else { return }
        do {
            sets = try store.sets(sessionId: id, userId: context.userId)
            seedCursor()
        } catch {
            storeError = String(describing: error)
        }
    }

    private func resolveDay() {
        guard let context else { return day = nil }
        guard let scheduled = Schedule.scheduleDayIn(context.schedule, context.today),
              let key = scheduled.dayKey
        else { return day = nil }
        let (program, _) = Schedule.programForContext(context.schedule, context.today)
        day = program.day(key: key)
    }

    /// Put the plan's numbers — or last time's — into the two editable values.
    ///
    /// ── SEEDED, NEVER CARRIED OVER ──────────────────────────────────────────
    /// The load resets to what the set SHOULD be rather than to what the last
    /// set was, because a drop set typed once would otherwise become the
    /// prescription for the rest of the workout. `logged.last` wins over the
    /// plan's `wk1Kg` when there is one: what you actually lifted five minutes
    /// ago is a better prediction than a seed written months ago.
    private func seedCursor() {
        guard let cursor else { return }
        if let previous = cursor.movement.logged.last {
            load = previous.weightKg
            reps = previous.reps
        } else {
            load = cursor.movement.plan.wk1Kg ?? 0
            reps = cursor.movement.plan.repFloor ?? 10
        }
    }

    // MARK: - Logging

    /// Commit the set in front of you.
    ///
    /// Everything below happens in one place on purpose: the event, the rest
    /// clock and the hand-off to the phone. A set that reached the log but not
    /// the link would still be safe (the phone gets it from Supabase when the
    /// two next meet) — but a set that started a rest clock without being
    /// logged would be a timer counting down for a set that never happened.
    @discardableResult
    func commitSet() -> Bool {
        guard let store, let context, let day, let cursor else { return false }
        do {
            let id = try ensureSession(store: store, context: context, day: day)
            let snapshot = SetSnapshot(
                exerciseId: Self.exerciseId(of: cursor.movement.plan),
                setIndex: cursor.setNumber,
                weightKg: load,
                reps: reps,
                setType: "normal",
                // The Crown moves a load in kilograms; the estimate is the one
                // derivation the phone also does at tick time, so a watch-logged
                // set carries the same `est_1rm_kg` a phone-logged one would.
                est1rmKg: OneRepMax.estimate(weight: load, reps: Double(reps)),
                exerciseOrder: cursor.movement.order
            )
            let event = try store.appendSet(sessionId: id, snapshot)
            link?.send(events: [event])
            startRest(after: cursor.movement)
            return true
        } catch EventStoreError.notSessionOwner {
            // The phone took the pencil while you were on this screen. Nothing
            // is lost — the set was never written — and the UI switches to the
            // read-only mirror with its *Log here* button.
            holdsPencil = false
            return false
        } catch {
            storeError = String(describing: error)
            return false
        }
    }

    /// Rate the set just logged. `nil` is not a value to write — it is the
    /// absence of one, and the rest screen dismissing itself is how you say it.
    func rate(_ value: Double) {
        guard let store, let sessionId, let last = sets.last else { return }
        do {
            _ = try store.amendSet(sessionId: sessionId, setId: last.id, SetPatch(rpe: value))
            if let event = try? store.setEvents(sessionId: sessionId).last {
                link?.send(events: [event])
            }
        } catch {
            storeError = String(describing: error)
        }
    }

    /// Undo the last set — a tombstone, never a delete.
    func voidLast() {
        guard let store, let sessionId, let last = sets.last else { return }
        do {
            let event = try store.voidSet(sessionId: sessionId, setId: last.id)
            link?.send(events: [event])
        } catch {
            storeError = String(describing: error)
        }
    }

    /// The id a set of this movement is written under.
    ///
    /// ── THE WATCH RESOLVES, IT DOES NOT MINT (W6) ───────────────────────────
    /// The phone creates a catalogue row for a movement the catalogue has never
    /// heard of; the watch must not. Its store is its OWN — Application Support
    /// on this device, not an App Group shared with the phone — so a row minted
    /// here would carry a uuid no other client has ever seen, and the movement
    /// would exist twice the moment the two logs met. The routine payload
    /// already names the catalogue row for all but a handful of movements; for
    /// the rest the legacy slug travels, and `ExerciseIndex` resolves it on the
    /// phone at push time, exactly as it has since W2.
    static func exerciseId(of plan: ProgramExercise) -> String {
        plan.exerciseId ?? ExerciseSlug.id(plan.name)
    }

    /// Both spellings a logged set of this movement can carry: the catalogue id
    /// and the legacy slug. A session begun on a build that wrote one and
    /// continued on a build that writes the other still counts its sets once.
    static func identities(of plan: ProgramExercise) -> Set<String> {
        var ids: Set<String> = [ExerciseSlug.id(plan.name)]
        if let catalogued = plan.exerciseId { ids.insert(catalogued) }
        return ids
    }

    private func ensureSession(store: AppDatabase, context: WatchContext, day: ProgramDay) throws -> String {
        if let sessionId { return sessionId }
        let session = try store.openSession(
            userId: context.userId, dayKey: day.key, date: context.today
        )
        adopt(session)
        return session.id
    }

    // MARK: - The pencil

    /// Take over from the phone. The one gesture that is allowed to.
    ///
    /// `force: true` is the *Log here* button and it always succeeds —
    /// `ingestOwnership` on the other device distinguishes it from the implicit
    /// claim every first write makes, and a deliberate takeover wins because
    /// somebody pressed a button.
    func takePencil() {
        guard let store, let sessionId else { return }
        do {
            let claim = try store.claimPencil(sessionId: sessionId, force: true)
            holdsPencil = true
            link?.send(ownership: claim)
        } catch {
            storeError = String(describing: error)
        }
    }

    // MARK: - Rest

    private func startRest(after movement: Movement) {
        let seconds = RestTargets.clamp(Double(movement.plan.restSec ?? 120))
        let pulse = RestPulse(
            sessionId: sessionId ?? "",
            endsAt: Date().addingTimeInterval(seconds),
            duration: seconds,
            exercise: cursor?.movement.plan.name ?? movement.plan.name
        )
        rest = pulse
        link?.send(rest: pulse)
    }

    /// ±15 s, clamped and snapped to the same grid the phone's control uses.
    ///
    /// ── WHY `duration` MOVES WITH THE DEADLINE ──────────────────────────────
    /// It used to stay put while `endsAt` moved, and that is the wrist's half
    /// of the same defect the Lock Screen's bar had: `duration` is the
    /// DENOMINATOR every reader divides the remainder by, so +15 s on a 90 s
    /// rest left 105 seconds remaining out of a stated 90 — a fraction above 1,
    /// which the old ring drew as a circle that had closed and kept going.
    ///
    /// `max(…, next)` rather than the sum alone because the sum can be smaller
    /// than what is actually left: the clamp has a floor, so taking 15 s off a
    /// rest already at the minimum moves the deadline by less than 15 and a
    /// bare `duration - 15` would go under the remainder and reopen the same
    /// fraction-above-1. The total is never allowed to be shorter than the
    /// countdown it contains.
    func adjustRest(by seconds: Double) {
        guard let rest else { return }
        let remaining = rest.endsAt.timeIntervalSinceNow
        let next = RestTargets.clamp(remaining + seconds)
        let pulse = RestPulse(
            sessionId: rest.sessionId,
            endsAt: Date().addingTimeInterval(next),
            duration: max(rest.duration + seconds, next),
            exercise: rest.exercise,
            loadKg: rest.loadKg,
            reps: rest.reps,
            rpe: rest.rpe,
            timerOrigin: rest.timerOrigin
        )
        self.rest = pulse
        link?.send(rest: pulse)
    }

    func stopRest() {
        rest = nil
        link?.send(rest: nil)
    }

    // MARK: - Finishing

    /// Close the session and write the workout to Health.
    ///
    /// The HealthKit figures are read BEFORE `closeSession`, because that is the
    /// call that computes `duration_min` and queues the session upsert — a
    /// metrics write afterwards would be a second queue item for a row that had
    /// already gone.
    func finish() async {
        guard let store, let sessionId, let context else { return }
        let metrics = await workout.end()
        do {
            try store.setSessionMetrics(
                id: sessionId, userId: context.userId, durationMin: nil,
                avgBpm: metrics.avgBpm, caloriesBurned: metrics.calories
            )
            _ = try store.closeSession(
                id: sessionId, restTargetSec: cursor.map { Double($0.movement.plan.restSec ?? 120) }
            )
            try store.releasePencil(sessionId: sessionId)
        } catch {
            storeError = String(describing: error)
        }
        setsObserver = nil
        self.sessionId = nil
        sessionStartedAt = nil
        sets = []
        rest = nil
    }

    // MARK: - Inbound

    private func receive(_ inbound: WatchLink.Inbound) {
        guard let store else { return }
        switch inbound {
        case .events(let events):
            // The one merge path, shared with the pull side of Supabase.
            // Idempotent, clock-advancing, and it never re-queues what it took.
            try? store.ingest(events)
        case .ownership(let claim):
            try? store.ingestOwnership(claim)
            if let sessionId {
                holdsPencil = (try? store.holdsPencil(sessionId: sessionId)) ?? true
            }
        case .context(let next):
            context = next
            WatchContextCache.save(next)
            // `save`, not `set` (W7): the complication extension is a second
            // process on this wrist and reads the palette back out of the
            // suite (`OnyxTheme.load`) the way the phone's widgets do. The
            // phone sends the already-reacted spec, so what lands under
            // `OnyxTheme.key` here is what is drawn — there is no phase key
            // on the watch to react it twice.
            OnyxTheme.save(next.theme ?? .default, to: WatchTiles.defaults())
            // The complications' numbers, then the reload that makes them
            // draw. Nil tiles (an older phone) leave the last ones in place
            // rather than blanking a face that was right yesterday.
            if let tiles = next.tiles {
                tiles.save()
                WidgetCenter.shared.reloadAllTimelines()
            }
            resolveDay()
            rejoinLiveSession()
        case .rest(let pulse):
            // The phone started or stopped resting. Mirrored, not merged: a
            // rest clock has no history to reconcile, and the last word wins.
            rest = pulse
            // The phone's origin wins while the phone holds the pencil: it has
            // the banked pauses already subtracted. Nil from an older phone
            // leaves whatever `adopt` read off the row.
            if let origin = pulse?.timerOrigin { sessionStartedAt = origin }
        }
    }
}

// MARK: - Deck shapes

extension WatchModel {

    /// One movement of today's deck, with what has been logged against it.
    struct Movement: Identifiable, Equatable {
        let plan: ProgramExercise
        /// Dense from 0 — what `SetSnapshot.exerciseOrder` carries, so a
        /// watch-logged session groups on the phone the way it happened.
        let order: Int
        let logged: [WorkoutSet]

        var id: String { plan.id }

        /// The phase's own set count. `cutSets` may legitimately be zero, which
        /// drops the movement — `exercises(for:)` has already filtered those
        /// out by the time this is built.
        var plannedSets: Int { plan.sets }

        var isDone: Bool { logged.count >= plannedSets }
    }

    /// The set you are about to do.
    struct Cursor: Equatable {
        let movement: Movement
        /// 1-based, among this movement's working sets.
        let setNumber: Int
    }
}

private extension ProgramExercise {
    /// The bottom of the rep window — `"8–12"` is 8. The seed for a movement
    /// with no history, because starting at the top of the window and failing is
    /// worse information than starting at the bottom and finishing.
    var repFloor: Int? {
        let digits = reps.prefix { $0.isNumber }
        return Int(digits)
    }
}

// MARK: - The context cache

/// The phone's last context, kept across launches.
///
/// ── WHY `UserDefaults` AND NOT THE DATABASE ─────────────────────────────────
/// It is one small value, it is replaced wholesale, it is read once at launch
/// before the store is open, and losing it costs a single reconnection to the
/// phone. That is the shape `UserDefaults` is for. A table would need a
/// migration for a value that has no history and no relations.
///
/// No token lives here. Wave 10's phone-relay decision means the watch never
/// authenticates, so the only identity it holds is a user id — which is not a
/// credential, and is already on every row in its own store.
///
/// ── IN THE APP GROUP SUITE SINCE W7 ─────────────────────────────────────────
/// `WatchTiles.defaults()` — the suite the complication extension reads —
/// rather than `.standard`, so the one place the watch keeps what the phone
/// last said is a place both of its processes can see. A context cached under
/// `.standard` by an earlier build is simply not found here; the next push
/// from the phone rewrites it, which is one reconnection, the cost the header
/// already accepts.
enum WatchContextCache {
    private static let key = "onyx.watch.context"

    static func load() -> WatchContext? {
        guard let data = WatchTiles.defaults().data(forKey: key) else { return nil }
        return try? OnyxJSON.decoder.decode(WatchContext.self, from: data)
    }

    static func save(_ context: WatchContext) {
        guard let data = try? OnyxJSON.encoder.encode(context) else { return }
        WatchTiles.defaults().set(data, forKey: key)
    }
}

#if DEBUG
extension WatchModel {

    /// Stand in for the phone, so the wrist can be photographed.
    ///
    /// ── WHY IT GOES THROUGH THE CACHE AND NOT STRAIGHT INTO `context` ───────
    /// `WatchContextCache` is exactly what a real context arrival writes, and
    /// `start()` reads it before anything else happens. Seeding there means the
    /// screenshot exercises the ordinary cold-launch path — stored context,
    /// `resolveDay`, `rejoinLiveSession` — rather than a second code path that
    /// only screenshots ever take, and which is therefore free to be wrong
    /// about the screen it is photographing.
    ///
    /// The day is pinned with an `overrides` entry rather than by the weekday
    /// layout: a shot that depends on which day of the week it ran on is a
    /// visual diff that fails on Tuesdays.
    func seedDebugContext() {
        let today = LogicalDay.iso()
        let next = WatchContext(
            userId: "preview",
            today: today,
            schedule: ScheduleContext(
                programId: "onyx5",
                phase: .cut,
                overrides: [today: "cb_b"],
                // Spelled out rather than read from `PlanTemplates`: that
                // lives in the APP target and the watch cannot see it. Three
                // real movements off the founder's Upper B — enough deck for
                // the cursor to advance and for `lastTime` to have something
                // to say, and the names are ones `MuscleMap` actually knows.
                programs: [
                    Program(id: "onyx5", label: "Onyx 5", days: [
                        ProgramDay(
                            key: "cb_b", label: "Upper B", accent: 0, weekday: 2,
                            exercises: [
                                ProgramExercise("Chest Press", sets: 3, wk1Kg: 40, reps: "8-12", restSec: 150),
                                ProgramExercise("Neutral-Grip Lat Pulldown", sets: 3, wk1Kg: 47, reps: "8-12", restSec: 150),
                                ProgramExercise("Single Arm Cable Crossover", sets: 3, wk1Kg: 7.5, reps: "12-15", restSec: 90),
                            ]
                        ),
                    ]),
                ]
            ),
            // The complications' numbers, spelled out for the same reason the
            // deck is: `OnyxSnapshot.sample` is behind OnyxUI's iOS fence.
            // Saved to the suite below exactly as a real arrival is, so the
            // watch simulator's complication gallery has something to draw.
            tiles: WatchTiles(
                date: today, battery: 72, score: 81, sleepMin: 445, sleepScore: 58,
                waterMl: 1_750, waterGoalMl: 3_000, steps: 8_412, stepsGoal: 10_000,
                kcal: 1_640, kcalGoal: 2_150, todayLabel: "Upper B", todayLogged: false,
                restDay: false, stressIndex: 41.5, sorenessCount: 3,
                week: (0..<7).map { WatchTiles.WeekDay(trained: $0 % 2 == 0, fuelHit: $0 != 3, sleepHit: $0 > 1) },
                medianBedtime: "23:12", lastBedtime: "00:16"
            )
        )
        WatchContextCache.save(next)
        next.tiles?.save()
        WidgetCenter.shared.reloadAllTimelines()
        context = next
        resolveDay()
    }

    /// The rest cover, with the set that earned it.
    ///
    /// The four optional fields are filled the way a phone on this build fills
    /// them, because the whole point of photographing this screen is the line
    /// they draw — a pulse without them renders the state an OLDER phone
    /// produces, which is a real state and not the one under review.
    func seedDebugRest() {
        defer {
            // The same assignment `receive(.rest:)` makes. Without it the shot
            // showed a session timer at 0:00 — true of a watch that had just
            // opened its own session a second earlier, and not the state under
            // review, which is a phone 45 minutes into a workout.
            if let origin = rest?.timerOrigin { sessionStartedAt = origin }
        }
        rest = RestPulse(
            sessionId: sessionId ?? "preview",
            endsAt: Date().addingTimeInterval(97),
            duration: 150,
            exercise: "Single Arm Cable Crossover",
            loadKg: 42.5,
            reps: 12,
            rpe: 8.5,
            timerOrigin: Date().addingTimeInterval(-45 * 60)
        )
    }
}
#endif
