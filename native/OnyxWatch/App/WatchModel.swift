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
    /// The store would not OPEN. Fatal to the app, and the only thing that
    /// replaces the whole screen with `StoreErrorView`.
    private(set) var storeError: String?

    /// The last WRITE that failed, if any.
    ///
    /// ── A WRITE FAILURE IS NOT A BROKEN APP (W3, AFTER REVIEW) ──────────────
    /// Every failed write used to land in `storeError`, which is cleared in
    /// exactly one place — inside `start()`, behind `store == nil`, so once
    /// per launch. One throw therefore replaced the logger with "Store
    /// unavailable" and the raw text of the error for the rest of the
    /// workout, with a force-quit as the only way back. And the throw was not
    /// hypothetical: `EventStore.record` refuses a write while the PHONE
    /// holds the pencil, and this wave put the pause and discard gestures on
    /// a toolbar that renders over the mirror screen — which is exactly that
    /// state.
    ///
    /// So a write failure is its own field, it is cleared by the next write
    /// that works, and it is reported where there is room to report it
    /// (`DeckView`, `FinishView`) rather than by taking the screen.
    private(set) var writeError: String?

    /// Who is signed in, what today is, and how the plan resolves it — sent by
    /// the phone over `updateApplicationContext` and cached so a cold launch out
    /// of range still opens the right split.
    private(set) var context: WatchContext?

    /// The deck for today, resolved from the context. Nil on a rest day, and
    /// nil before the phone has ever spoken to this watch.
    private(set) var day: ProgramDay?

    /// The live session's id, once a set has been logged into it.
    private(set) var sessionId: String?

    /// The session row's own `started_at`. WALL TIME, pauses still in it.
    ///
    /// Nil before a session — the toolbar draws no timer rather than a wrong
    /// one. `clock(at:)` is what a view reads; this is one of its two inputs.
    private(set) var sessionStartedAt: Date?

    /// The origin a PHONE-DRIVEN session sent us, pauses already subtracted.
    ///
    /// ── TWO WRITERS, AND THE OTHER ONE WINS WHEN IT SPEAKS ──────────────────
    /// A `RestPulse` carries `timerOrigin` because the phone holds the pencil
    /// in that case and its number has the banked pauses already taken out of
    /// it. A session paused for eleven minutes is eleven minutes younger than
    /// `started_at` says, and the wrist showing a different hour from the phone
    /// in your hand is worse than the wrist showing nothing.
    ///
    /// ── AND WHY IT IS NO LONGER WRITTEN INTO `sessionStartedAt` (W3) ────────
    /// It used to be, and that was correct while the wrist had no pause
    /// control: one field, one origin, nothing to subtract twice. Now the watch
    /// keeps its own `PauseLedger` and `clock(at:)` subtracts it — so folding
    /// an already-adjusted origin into the same field would take the same
    /// pause off twice and run the wrist's clock fast by exactly the length of
    /// every pause in the session.
    ///
    /// Nil on a wrist-driven session and on a pulse from a phone that predates
    /// the field, which is when the ledger below answers instead.
    private(set) var remoteOrigin: Date?

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

    /// Millilitres tapped on the Fuel page that the phone has not confirmed
    /// yet (W4).
    ///
    /// ── WHY THE WRIST KEEPS A NUMBER IT DOES NOT OWN ────────────────────────
    /// The glass is posted to the phone and written there — this device has no
    /// `water_intake` table (`WatchLink.Inbound.water`). The round trip is a
    /// `transferUserInfo` out, a drain on the phone, a commit, and a fresh
    /// application context back, which is seconds at best and minutes with the
    /// phone in a locker. A button whose number does not move until then is a
    /// button people press twice.
    ///
    /// So the page draws `tiles.addingWater(pendingWaterMl)` and this is the
    /// addend. It is the same optimism the phone's own widget takes on the
    /// same mailbox (`WidgetStore.snapshot` reads `PendingWater.pending`), and
    /// it is cleared the moment a context arrives, because that context IS the
    /// phone's answer — including the answer "I have not drained it yet",
    /// which flicks the reading back for one push rather than leaving it
    /// permanently one glass high.
    private(set) var pendingWaterMl = 0

    /// The set being edited right now. Seeded from the plan and from what you
    /// lifted last time, then moved by the Crown.
    var load: Double = 0
    var reps: Int = 0

    /// The `HKWorkoutSession`. See `WorkoutSessionController` — it is the
    /// runtime, not a heart-rate feature.
    let workout = WorkoutSessionController()

    /// The session clock's ledger, as the event log last stated it.
    ///
    /// Re-read from `set_events` on every commit rather than accumulated here,
    /// for the reason `sets` is: the log is the truth and a second tally in a
    /// model is a third answer. `SessionRun.resolve` turns it into an origin —
    /// see `timerOrigin`.
    private(set) var pauses = PauseLedger()

    // MARK: - The deck, as this wrist has rearranged it (W3)

    /// How this session has moved today's deck about — the order, the skips,
    /// the added sets, the swaps and the jump.
    ///
    /// ── LOCAL, AND THAT IS THE DESIGN AND NOT A SHORTCUT ────────────────────
    /// What CROSSES to the phone is `exercise_order` on the logged rows, which
    /// is what the session report groups by — so a deck rearranged here and a
    /// deck rearranged on the phone produce the same history. The arrangement
    /// itself is a view of today: it has no row, it does not survive a
    /// relaunch, and it must not, because the routine is a template and a
    /// wrist reordering one workout is not editing next week's.
    ///
    /// ── AND IT IS A VALUE IN OnyxCore, NOT FIVE PROPERTIES HERE (W3) ────────
    /// It was five, and review found five defects in them in one pass — every
    /// one arithmetic, and none of them reachable by a test, because this type
    /// is `@MainActor`, watchOS-only and in the app target. `DeckArrangement`
    /// is the same five keyed on the SLOT rather than on the name currently in
    /// it, with a suite under it.
    private var arrangement = DeckArrangement()

    private var link: WatchLink?
    private var setsObserver: AnyDatabaseCancellable?

    /// The last snapshot handed to the widget extension (W4).
    ///
    /// Not what is IN the suite — what this process last wrote there. It is
    /// the de-dupe cursor for `publishLiveSnapshot`, which is reached twice
    /// on every commit (once through `seedCursor`, once from `startRest`
    /// with the new rest on it) and from seven places in all.
    private var lastPublished: LiveWorkoutSnapshot?

    #if DEBUG
    /// Which screen the shot loop asked for (`ONYX_WATCH_SCREEN`).
    ///
    /// ── WHY IT IS MODEL STATE AND NOT A VIEW'S ──────────────────────────────
    /// Four of the six screens this wave added are reached by NAVIGATION from
    /// inside a live session — the deck, the quality page, the cancel dialog,
    /// the finish card — and a simulator can tap none of them. W1's
    /// `watch-shot.sh` refuses those names by name rather than photographing
    /// `StartView` under the wrong filename, and says the hook is W3's to add.
    /// This is that hook: one value, read by whichever view owns the screen,
    /// so each screen is reached along the path a finger would take rather
    /// than by a second rendering nobody ships.
    /// `dashboard` is W4's, and it is the last name `watch-shot.sh` refused
    /// (W1 left it named as unreachable and said so by name rather than
    /// photographing `StartView` under its filename).
    enum DebugScreen: String { case start, restday, rest, deck, quality, pause, cancel, finish, dashboard, fuel, train, widget }
    var debugScreen: DebugScreen?
    #endif

    // MARK: - Derived

    /// The movements of today's deck, each with the sets already logged
    /// against it.
    ///
    /// Rebuilt from `day` and `sets` on every read rather than cached: the
    /// deck is at most a dozen movements, the fold is already in memory, and a
    /// cache here would be a third answer to "what has been logged" beside the
    /// log and the projection.
    /// Today's prescription, before this session rearranged anything.
    private var planDeck: [ProgramExercise] {
        guard let day, let context else { return [] }
        return day.exercises(for: context.schedule.phase)
    }

    var movements: [Movement] {
        arrangement.slots(of: planDeck).map { slot in
            let ids = Self.identities(of: slot.plan)
            let rows = sets.filter { ids.contains($0.exerciseId) }
            return Movement(
                slot: slot,
                rows: rows,
                logged: rows.filter { SetTags.isWorkingSet($0.setType) }
            )
        }
    }

    /// Where you are: the movement you jumped to, else the first one still
    /// owed. A skipped movement is owed nothing.
    ///
    /// Nil once the deck is finished, which is what turns the tick into a
    /// finish button.
    var cursor: Cursor? {
        let owing = movements.filter { !$0.isSkipped && $0.logged.count < $0.plannedSets }
        // The pin outranks the order for exactly as long as it still owes a
        // set. Falling through rather than sticking is what stops a jump from
        // becoming a mode you have to leave.
        let movement = owing.first { $0.id == arrangement.pinned } ?? owing.first
        guard let movement else { return nil }
        return Cursor(movement: movement, setNumber: movement.logged.count + 1)
    }

    var isFinished: Bool { day != nil && cursor == nil && !sets.isEmpty }

    /// The set the quality panel describes: the last one logged into this
    /// session, in fold order.
    ///
    /// NOT `cursor`'s set — that one does not exist yet, and `SetPatch` amends
    /// a set that does. The panel names it for the same reason the phone's
    /// options sheet prints the movement in its title bar: you reached it by a
    /// swipe, and the only evidence you are describing the set you meant is
    /// the line at the top.
    var lastLogged: WorkoutSet? { sets.last }

    /// The movement `lastLogged` belongs to, for the panel's header.
    var lastLoggedMovement: Movement? {
        guard let last = lastLogged else { return nil }
        return movements.first { Self.identities(of: $0.plan).contains(last.exerciseId) }
    }

    // MARK: - The clock

    /// What the session clock reads at `now` — the instant it counts up from,
    /// and whether it is frozen.
    ///
    /// ── THE ARITHMETIC IS `SessionRun`'s, NOT THIS FILE'S ───────────────────
    /// `SessionRun.resolve` is the phone's own clock repair, pure and in
    /// OnyxCore with a table test under it: it bounds an OPEN pause at fifteen
    /// minutes (a session jetsammed at 18:40 and reopened at 07:00 was never
    /// thirteen hours of rest) and it clamps the total so `pausedTotal` can
    /// never outgrow the wall interval — the bug that printed a confident
    /// `0:00` on an intact session. The wrist gets exactly that behaviour by
    /// calling it rather than by subtracting a number here.
    ///
    /// `now` is a parameter so the toolbar's `TimelineView` can pass its own
    /// date and the view stays a function of it.
    func clock(at now: Date = Date()) -> (origin: Date, isPaused: Bool)? {
        // The phone's own origin already has its pauses out of it, and the
        // phone is the device the athlete is looking at. Subtracting this
        // wrist's ledger on top would take every pause off twice.
        //
        // ── UNLESS THE LOG SAYS A PAUSE IS OPEN ─────────────────────────────
        // A pause is an EVENT, not a rest pulse, so a pause taken on the
        // phone never updates `remoteOrigin` — the wrist kept counting for
        // the whole pause and then jumped backwards when the next pulse
        // arrived. The ledger is the thing both devices share, so it wins
        // whenever it has something to say.
        if let remoteOrigin, pauses.openedAt == nil { return (remoteOrigin, false) }
        guard let sessionStartedAt else { return nil }
        let resolved = SessionRun.resolve(
            startedAt: sessionStartedAt,
            banked: pauses.banked,
            pauseOpenedAt: pauses.openedAt,
            now: now
        )
        return (sessionStartedAt.addingTimeInterval(resolved.pausedTotal), resolved.pausedAt != nil)
    }

    /// True while the session clock is stopped, for the toolbar's glyph.
    ///
    /// The LEDGER and not `clock()`: the latter defaults `now` to `Date()`,
    /// and a view body that reads the wall clock is not a function of its
    /// state — which is the whole reason `clock(at:)` takes the instant as a
    /// parameter. An open pause is an open pause whatever time it is.
    var isPaused: Bool { pauses.openedAt != nil }

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
        // The row's own start — wall time. `clock(at:)` takes the pauses off
        // it, from the ledger `reload` reads two lines below.
        sessionStartedAt = session.startedAt
        holdsPencil = (try? store.holdsPencil(sessionId: session.id)) ?? true
        observeSets(session.id)
        seedCursor()
        if !workout.isRunning { workout.start() }
        // ── AND HEALTHKIT AGREES WITH THE LOG ───────────────────────────────
        // `observeSets` has just read the ledger. A session rejoined after a
        // relaunch while paused would otherwise start a RUNNING
        // `HKWorkoutSession` — the rings accruing active energy for the rest
        // of a pause, which is the one thing `pause()` exists to prevent.
        if pauses.openedAt != nil { workout.pause() }
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
            // The clock's ledger comes off the same log and in the same read:
            // a `pause` written on the phone reaches this wrist as an event,
            // `ingest` commits it, and this is the line that makes the wrist's
            // timer stop with the phone's.
            pauses = try store.pauseLedger(sessionId: id)
            seedCursor()
        } catch {
            storeError = String(describing: error)
        }
    }

    private func resolveDay() {
        let previous = day?.key
        guard let context else { return day = nil }
        guard let scheduled = Schedule.scheduleDayIn(context.schedule, context.today),
              let key = scheduled.dayKey
        else { return day = nil }
        let (program, _) = Schedule.programForContext(context.schedule, context.today)
        day = program.day(key: key)
        // ── THE ARRANGEMENT IS RECONCILED AGAINST THE DECK, NOT THE KEY ─────
        // A different day is obviously a different deck. So is the SAME day
        // after the routine behind it is edited on the phone, and that is the
        // case the first version missed: an order holding plan indices then
        // names different movements, and a movement added on the phone never
        // appears on the wrist at all. `DeckArrangement.reconcile` compares
        // the exercise ids, so both cases are one check — and a context push
        // that changed only a tile or the theme still keeps a reorder made
        // two movements ago.
        arrangement.reconcile(with: planDeck)
        _ = previous
    }

    /// Put the plan's numbers — or last time's — into the two editable values.
    ///
    /// ── SEEDED, NEVER CARRIED OVER ──────────────────────────────────────────
    /// The load resets to what the set SHOULD be rather than to what the last
    /// set was, because a drop set typed once would otherwise become the
    /// prescription for the rest of the workout. `logged.last` wins over the
    /// plan's `wk1Kg` when there is one: what you actually lifted five minutes
    /// ago is a better prediction than a seed written months ago.
    ///
    /// ── AND IT IS WHERE THE SMART STACK CARD IS PUBLISHED (W4) ─────────────
    /// Seven callers, and they are every change the card cares about:
    /// `adopt` (rejoining a live session), `reload` (every commit, void,
    /// amend and phone-side ingest — the observer path) and the five deck
    /// mutators (`doNext`, `toggleSkip`, `jump`, `addSet`, `swap`). W4 first
    /// published only from the four REST beats, which left the card
    /// confidently wrong after any deck edit: skip or swap the movement you
    /// are resting before and the blob is seconds old, so `isLive` is true,
    /// `load()` hands it back, and the face draws a movement you have just
    /// removed against a denominator that no longer exists. `voidLast` was
    /// crisper — the card read 8/12 while the log held 7 — and neither
    /// self-repairs if the next commit never comes.
    ///
    /// One line here rather than six at the call sites, because this is
    /// already the thing they all end in.
    private func seedCursor() {
        // BEFORE the guard, not after it: a finished deck has no cursor and
        // is exactly the state the card must still describe — the last rest
        // of the session is the one you are most likely to be looking at.
        defer { publishLiveSnapshot() }
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
                setIndex: cursor.movement.nextStoreIndex,
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
            // ── RE-READ BEFORE THE REST CLOCK IS BUILT ──────────────────────
            // `observeSets` reloads through a `Task`, so without this the
            // fold is still the one from before this append: `sets.last` is
            // the PREVIOUS set and `cursor` still points at the movement just
            // logged — so the rest screen's receipt showed the wrong set and
            // its "Next ·" line named the movement you had just finished.
            reload(id)
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

    /// What to do when a store write throws.
    ///
    /// `notSessionOwner` is not an error to report — it is the phone having
    /// taken the pencil, which the UI already has a whole screen for. Every
    /// other throw is a write failure, which is a banner and not a takeover.
    private func failed(_ error: any Error) {
        if case EventStoreError.notSessionOwner = error {
            holdsPencil = false
            return
        }
        writeError = String(describing: error)
    }

    /// Amend the set just logged, and hand the event to the phone.
    ///
    /// ── ONE DOOR FOR EVERY CORRECTION ON THIS WRIST ─────────────────────────
    /// The rating, the kind, the side, the quality tags and the two numbers all
    /// describe the SAME set — the last one in the fold — and they all reach
    /// the log the same way: one `amend`, one event, one send. Before W3 the
    /// rating had its own copy of this, which re-READ the log to find the event
    /// it had just written; `amendSet` returns it.
    ///
    /// An empty patch is refused by `amendSet` itself (an event that changes
    /// nothing is permanent noise in a log that is never compacted), so every
    /// caller below checks that its value actually moved before calling.
    /// `OnyxData.SetPatch` spelled out: OnyxCore has a `SetPatch` of its own
    /// (the deck draft's), both modules are imported here, and the two are
    /// unrelated types. Every other mention below is inferred from this one.
    @discardableResult
    func amend(_ setId: String?, _ patch: OnyxData.SetPatch) -> Bool {
        guard let store, let sessionId, let setId else { return false }
        // The panel renders against ONE set and this re-resolves it, so a set
        // arriving from the phone between the render and the tap would
        // otherwise retarget the amend. The caller passes the id it drew.
        guard sets.contains(where: { $0.id == setId }) else { return false }
        do {
            let event = try store.amendSet(sessionId: sessionId, setId: setId, patch)
            link?.send(events: [event])
            writeError = nil
            return true
        } catch {
            failed(error)
            return false
        }
    }

    /// Rate the set just logged. `nil` is not a value to write — it is the
    /// absence of one, and the rest screen dismissing itself is how you say it.
    func rate(_ value: Double) {
        amend(sets.last?.id, OnyxData.SetPatch(rpe: value))
    }

    // MARK: - The quality panel (W3)
    //
    // ── EVERY ONE NAMES ITS SET ─────────────────────────────────────────────
    // They each re-read `sets.last` at tap time, and the panel renders
    // against one set. Between the render and the finger landing, a set
    // logged on the PHONE can arrive over `WatchLink`, commit, and reload the
    // fold — so the tag landed on the phone's set instead. Passing the id the
    // panel drew makes a stale tap a refusal rather than a wrong write.

    /// Mark what the last set WAS. Passing the kind it already carries
    /// withdraws it — the phone's own grammar, and the reason there is no
    /// "Work" chip: normal is the ABSENCE of a claim.
    func setKind(_ key: String, on setId: String) {
        guard let row = sets.first(where: { $0.id == setId }) else { return }
        let next = (row.setType == key) ? "normal" : key
        guard next != row.setType else { return }
        amend(setId, OnyxData.SetPatch(setType: next))
    }

    /// Toggle one technique tag on the last set.
    ///
    /// Several at once, in `SetTags.qualityKeys` order, joined by `+` — the
    /// one grammar, parsed in OnyxCore and shared with the phone and the
    /// export. An empty list clears the column, which is the one field
    /// `SetPatch` is allowed to null (`OnyxData.SetPatch.clearedQuality`).
    func toggleQuality(_ key: String, on setId: String) {
        guard let row = sets.first(where: { $0.id == setId }) else { return }
        var keys = Set(SetTags.parseQuality(row.quality))
        if keys.contains(key) { keys.remove(key) } else { keys.insert(key) }
        amend(setId, OnyxData.SetPatch(quality: SetTags.joinQuality(Array(keys)) ?? OnyxData.SetPatch.clearedQuality))
    }

    /// Mark which limb the last set was.
    ///
    /// ── ONE WAY, AND THE PANEL SAYS SO ──────────────────────────────────────
    /// `SetPatch` cannot clear `side`: nil means UNCHANGED, and there is no
    /// second flag. That is deliberate upstream — clearing a side means two
    /// rows becoming one, which is a void-and-append and not a patch. So this
    /// switches L to R and back, and the only way to un-side a set is to undo
    /// it. A side with no `pairId` is an ordinary set everywhere it is counted
    /// (`SessionVolume`: "a side without a pairId is an ordinary set"), so
    /// marking one costs the session's tonnage nothing.
    func setSide(_ side: String, on setId: String) {
        guard let row = sets.first(where: { $0.id == setId }), row.side != side else { return }
        amend(setId, OnyxData.SetPatch(side: side))
    }

    /// Correct the last set's two numbers, from the rest screen's receipt.
    ///
    /// The estimate travels with them. `commitSet` derives `est_1rm_kg` at tick
    /// time so a watch-logged set carries what a phone-logged one would; an
    /// edit that moved the load and left the estimate behind would leave a
    /// 1RM from a set that was never performed sitting in the PR engine's
    /// input.
    func editLast(load: Double, reps: Int) {
        guard let last = sets.last else { return }
        guard load != last.weightKg || reps != last.reps else { return }
        amend(last.id, OnyxData.SetPatch(
            weightKg: load,
            reps: reps,
            est1rmKg: OneRepMax.estimate(weight: load, reps: Double(reps))
        ))
    }

    // MARK: - The clock's two buttons (W3)

    /// Stop the session clock, or start it again.
    ///
    /// TWO writes, deliberately, and neither is derived from the other: the
    /// `pause` event is what the elapsed clock reads and what survives a
    /// relaunch and a merge, and the `HKWorkoutSession` pause is what stops the
    /// rings accruing exercise nobody did. `WorkoutSessionController` keeps its
    /// own flag because HealthKit's state does not survive a launch and the
    /// log's does.
    func togglePause() {
        guard let store, let sessionId else { return }
        do {
            let paused = try store.isPaused(sessionId: sessionId)
            let event = paused
                ? try store.resumeSession(sessionId)
                : try store.pauseSession(sessionId)
            link?.send(events: [event])
            if paused { workout.resume() } else { workout.pause() }
            pauses = try store.pauseLedger(sessionId: sessionId)
            // ── THIS WRIST IS STEERING THE CLOCK NOW ────────────────────────
            // `remoteOrigin` is the phone's already-adjusted origin, and
            // `clock(at:)` prefers it. Left in place it outlives the reason
            // for it: a pause taken here would write its event, stop the
            // `HKWorkoutSession`, and leave the wrist counting up with no
            // pause glyph while the phone's hero sat frozen — the two
            // disagreeing by exactly the length of every pause.
            remoteOrigin = nil
            writeError = nil
            // A paused session whose card still counted a rest down was the
            // one state the live face could be confidently wrong about.
            publishLiveSnapshot()
        } catch {
            failed(error)
        }
    }

    /// Throw the session away — this workout did not happen.
    ///
    /// The phone's `LoggerModel.cancel` is the model: `discardSession` rather
    /// than a close, because an empty-but-finished session row is the worse
    /// outcome. The three things this adds are the wrist's: the `HKWorkout` is
    /// DISCARDED rather than saved (`WorkoutSessionController.cancel`, which
    /// until now had no caller anywhere in the app), the pencil is released so
    /// the phone is not left locked out of a session that no longer exists, and
    /// the local deck arrangement goes with it.
    ///
    /// Nothing is sent over the link. The phone learns about the discard the
    /// way it learns about everything else — from the store, when the two next
    /// sync — and a `WatchLink` message saying "forget that" is a second
    /// deletion protocol for a case the event log already covers by having no
    /// events to fold.
    ///
    /// ── THE LOG LETS GO FIRST ───────────────────────────────────────────────
    /// `workout.cancel()` ran first and the teardown ran unconditionally, and
    /// both are the wrong way round. `discardSession` returns FALSE when the
    /// row belongs to another account — nothing is deleted — and it can
    /// throw, in which case `releasePencil` never ran and the wrist kept the
    /// pencil on a session it had just forgotten, locking the phone out of a
    /// session that still existed. Either way the `HKWorkout` was already in
    /// the bin and `rejoinLiveSession` brought every set back on the next
    /// context push.
    ///
    /// So: the store, checked; then Health; then the model.
    func cancelSession() {
        guard let store, let sessionId, let context else { return }
        do {
            guard try store.discardSession(id: sessionId, userId: context.userId) else {
                writeError = "That session belongs to another account."
                return
            }
            try? store.releasePencil(sessionId: sessionId)
        } catch {
            failed(error)
            return
        }
        workout.cancel()
        writeError = nil
        setsObserver = nil
        self.sessionId = nil
        sessionStartedAt = nil
        remoteOrigin = nil
        pauses = PauseLedger()
        sets = []
        rest = nil
        arrangement = DeckArrangement()
        clearLiveSnapshot()
    }

    // MARK: - Rearranging today's deck (W3)

    /// Do this movement next — put it immediately after the one you are on.
    ///
    /// ── THE ARITHMETIC IS SHARED, AND IT IS NOT HERE ────────────────────────
    /// `DeckArrangement` keeps the order and `DeckOrder.move` permutes it —
    /// the same function `LoggerModel.moveExercise` calls — so the two clients
    /// agree about which rows have to be re-stamped. What is left here is the
    /// three things a value type cannot do: write the new order onto the log,
    /// re-seed the numbers under the Crown, and make a haptic.
    func doNext(_ movement: Movement) {
        arrangement.reconcile(with: planDeck)
        arrangement.moveNext(movement.originId, after: cursor?.movement.originId, in: planDeck)
        restampOrder()
        seedCursor()
    }

    /// Put a movement aside for this session, or take it back.
    func toggleSkip(_ movement: Movement) {
        arrangement.reconcile(with: planDeck)
        arrangement.toggleSkip(movement.originId)
        restampOrder()
        // ── AND RE-SEED, BECAUSE THE CURSOR MOVED ───────────────────────────
        // Skipping the movement you are on hands the cursor to the next one,
        // and without this the Crown keeps the load of the movement you just
        // put aside — 40 kg of Chest Press logged against a Lat Pulldown that
        // prescribes 47. `restampOrder` self-heals it only when a row was
        // actually amended, which on a deck with nothing logged is never.
        seedCursor()
    }

    /// Jump the cursor to a movement. The pin lasts only while that movement
    /// still owes a set — see `cursor`.
    func jump(to movement: Movement) {
        guard !movement.isSkipped, !movement.isDone else { return }
        arrangement.reconcile(with: planDeck)
        arrangement.pin(movement.originId)
        seedCursor()
    }

    /// One more set of a movement, today only.
    ///
    /// ── IT TAKES A TARGET, AND THAT IS NOT DECORATION ───────────────────────
    /// The deck's swipe action used to `jump` and then call a no-argument
    /// version of this. `jump` refuses a movement that is finished or
    /// skipped — silently, and correctly — and the no-argument version then
    /// fell through to the cursor, so "one more set" swiped on the movement
    /// you had just FINISHED added the set to a different one. That is the
    /// exact gesture the action exists for.
    func addSet(to movement: Movement) {
        arrangement.reconcile(with: planDeck)
        arrangement.addSet(to: movement.originId)
        seedCursor()
    }

    /// One more set of the movement you are on — the logger screen's door.
    func addSet() {
        guard let target = cursor?.movement ?? lastLoggedMovement else { return }
        addSet(to: target)
    }

    /// The movements this wrist may swap a card for.
    ///
    /// ── ONLY WHAT THE PHONE ALREADY SENT ────────────────────────────────────
    /// Every candidate is a `ProgramExercise` out of `WatchContext.schedule`,
    /// so it arrives carrying the `exerciseId` the phone resolved — and the
    /// watch resolves, it never mints (see `exerciseId(of:)`): a catalogue row
    /// created on this wrist would carry a uuid no other client has seen, and
    /// the movement would exist twice the moment the two logs met.
    ///
    /// Same-muscle, by the primary movers `MuscleMap` already resolved for
    /// both names. A lift with no movers offers nothing rather than
    /// everything.
    func swapCandidates(for movement: Movement) -> [ProgramExercise] {
        guard let context else { return [] }
        let wanted = Set(movement.plan.movers.primary)
        guard !wanted.isEmpty else { return [] }
        let onDeck = Set(movements.map(\.plan.id))
        var seen: Set<String> = []
        return Self.catalogue(context)
            .filter { candidate in
                guard !onDeck.contains(candidate.id), !seen.contains(candidate.id) else { return false }
                guard !Set(candidate.movers.primary).isDisjoint(with: wanted) else { return false }
                seen.insert(candidate.id)
                return true
            }
            .sorted { $0.name < $1.name }
    }

    /// Whether the deck should offer a swap on this row at all.
    ///
    /// A BOOLEAN and not `!swapCandidates(for:).isEmpty`: the deck asks this
    /// once per row inside a `swipeActions` builder, on every render of a
    /// `List` inside a running `HKWorkoutSession`, and the full version walks
    /// every program × every day × every exercise and then SORTS the result —
    /// to answer yes or no.
    func hasSwapCandidate(for movement: Movement) -> Bool {
        guard movement.rows.isEmpty, let context else { return false }
        let wanted = Set(movement.plan.movers.primary)
        guard !wanted.isEmpty else { return false }
        let onDeck = Set(movements.map(\.plan.id))
        return Self.catalogue(context).contains { candidate in
            !onDeck.contains(candidate.id)
                && !Set(candidate.movers.primary).isDisjoint(with: wanted)
        }
    }

    /// Every movement this wrist may offer as a swap.
    ///
    /// Since W6 the phone sends the ACTIVE program in `schedule.programs` and
    /// the WHOLE catalogue, flat and in its original order, in `swapPool`. The
    /// pool wins when it is there — it already holds today's deck, and
    /// concatenating the two would put the active program's copy of a shared
    /// name ahead of the one the phone's own order resolves to. A phone on an
    /// older build sends no pool and every program, which is the fallback.
    private static func catalogue(_ context: WatchContext) -> [ProgramExercise] {
        if let pool = context.swapPool, !pool.isEmpty { return pool }
        return context.schedule.programs.flatMap(\.days).flatMap(\.exercises)
    }

    /// Put another movement in this one's place for today.
    func swap(_ movement: Movement, for candidate: ProgramExercise) {
        // A movement with ANY row against it is not swapped: the rows would be
        // orphaned under an id the deck no longer names, and the honest
        // gesture there is to skip it. `rows` and not `logged` for the reason
        // the restamp uses it — a warm-up is still a row. The deck hides the
        // action in that case, and this is the second guard rather than the
        // first.
        guard movement.rows.isEmpty else { return }
        arrangement.reconcile(with: planDeck)
        arrangement.swap(movement.originId, for: candidate, in: planDeck)
        restampOrder()
        seedCursor()
    }

    private func restampOrder() {
        guard let store, let sessionId else { return }
        for movement in movements {
            for row in movement.rows where row.exerciseOrder != movement.order {
                do {
                    let event = try store.amendSet(
                        sessionId: sessionId, setId: row.id, OnyxData.SetPatch(exerciseOrder: movement.order)
                    )
                    link?.send(events: [event])
                } catch {
                    storeError = String(describing: error)
                }
            }
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
            // Taking the pencil is taking the clock with it — see
            // `togglePause`, and `remoteOrigin`'s own header.
            remoteOrigin = nil
            writeError = nil
        } catch {
            failed(error)
        }
    }

    // MARK: - Rest

    private func startRest(after movement: Movement) {
        let seconds = RestTargets.clamp(Double(movement.plan.restSec ?? 120))
        let last = sets.last
        let pulse = RestPulse(
            sessionId: sessionId ?? "",
            endsAt: Date().addingTimeInterval(seconds),
            duration: seconds,
            exercise: cursor?.movement.plan.name ?? movement.plan.name,
            // ── THE SET THAT EARNED IT, ON A WRIST-STARTED REST (W3) ────────
            // These were left nil, which is how an OLDER PHONE's pulse
            // arrives — so the rest screen drew no receipt, and this wave's
            // "edit the set you just logged" was unreachable on every
            // session logged without a phone. Which is every session this
            // client exists for.
            loadKg: last?.weightKg,
            reps: last?.reps,
            rpe: last?.rpe,
            // The one reading only this device can take. Nil until the sensor
            // has settled, which is a missing number and not a zero.
            bpm: workout.heartRate
        )
        rest = pulse
        link?.send(rest: pulse)
        // The Smart Stack's card, on the two beats the plan names: a commit
        // (which is the only caller of this) and a rest pulse (which is this).
        // One call covers both because a commit always starts a rest.
        publishLiveSnapshot()
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
            timerOrigin: rest.timerOrigin,
            // The CURRENT reading, not the one the pulse was built with: a
            // nudge is a fresh message and a fifteen-second-old heart rate is
            // the only stale thing that would be on it.
            bpm: workout.heartRate ?? rest.bpm
        )
        // ── THE MESSAGE GETS THE FRESH RATE, THE SCREEN KEEPS THE OLD ONE ───
        // `bpm` is two things at once: on the WIRE it is "what the wrist reads
        // now", which the phone's deck wants fresh. Locally it is the BASELINE
        // the rest screen's recovery delta is measured from — the rate at the
        // instant you racked the bar. Writing the fresh one into both made
        // +15 s wipe the number the sparkline row exists to show: "120 −28"
        // became "120", for the rest of the countdown.
        link?.send(rest: pulse)
        self.rest = RestPulse(
            sessionId: pulse.sessionId, endsAt: pulse.endsAt, duration: pulse.duration,
            exercise: pulse.exercise, loadKg: pulse.loadKg, reps: pulse.reps, rpe: pulse.rpe,
            timerOrigin: pulse.timerOrigin, bpm: rest.bpm
        )
        publishLiveSnapshot()
    }

    func stopRest() {
        rest = nil
        link?.send(rest: nil)
        publishLiveSnapshot()
    }

    // MARK: - What the Smart Stack reads (W4)

    /// The tiles the dashboard pages draw — the phone's, plus whatever water
    /// this wrist has tapped and the phone has not confirmed.
    ///
    /// ONE place adds the optimistic glass, so the Fuel page's face and any
    /// later reader cannot disagree about how much water today has had.
    ///
    /// ── THE COMPLICATION DOES NOT GET IT, AND MUST NOT ──────────────────────
    /// The watch's Water complication reads the suite directly
    /// (`WatchTiles.load`), so between a tap here and the phone's next
    /// context push the Fuel page reads 2 000 ml and a face on the clock
    /// reads 1 750. That is the right side of the trade: this page knows the
    /// tap happened because it is the thing that was tapped, and a
    /// complication that adds an optimistic 250 would be a face asserting a
    /// number no store has agreed to — on the one surface with no way to
    /// explain itself.
    var dashboardTiles: WatchTiles? {
        context?.tiles?.addingWater(pendingWaterMl)
    }

    /// Write the running session where the complication extension can read it,
    /// and tell WidgetKit twice.
    ///
    /// ── TWO CALLS, AND THE SECOND ONE IS THE POINT ──────────────────────────
    /// `reloadTimelines` refreshes what the card DRAWS. It does not re-ask
    /// `LiveWorkoutProvider.relevance()`, whose answer the system caches — so
    /// without `invalidateRelevance` the card would update perfectly inside a
    /// Smart Stack it never rose to the top of, which is the whole feature.
    ///
    /// ── AND WHY NOT `reloadAllTimelines` ────────────────────────────────────
    /// Eleven widgets live in that extension and reloads are budgeted on a
    /// watch. Regenerating all eleven on every set commit is how the live card
    /// becomes the one widget that stops updating. `reloadAllTimelines` stays
    /// where it belongs — the once-a-push context arrival, which is when the
    /// other ten actually change.
    private func publishLiveSnapshot() {
        // ── `sessionId`, AND NOT `cursor` ───────────────────────────────────
        // The guard read `let cursor` and cleared the card without one. But
        // `cursor` is nil the moment the deck is FINISHED (`isFinished` keys
        // off exactly that), so committing the last planned set ran
        // commit → startRest → publish → cursor nil → clear: the rest clock
        // running, the session still open, `finish()` not called, and the
        // Smart Stack card already gone to "No session running" and dropped
        // out of `relevance()`. The 45-minute window never got a chance to
        // matter. The session is over when `sessionId` is nil and at no other
        // moment.
        guard sessionId != nil else { return clearLiveSnapshot() }
        // The movement the card is ABOUT: the one you are walking to, or —
        // on the last rest of the session — the one you have just finished.
        // `lastLoggedMovement` is the same fallback `addSet()` uses.
        guard let movement = cursor?.movement ?? lastLoggedMovement else {
            return clearLiveSnapshot()
        }
        // ── BOTH FOLDS FILTER THE SAME WAY ──────────────────────────────────
        // `done` walked every movement and `planned` only the unskipped ones,
        // so skipping a movement you had already logged two sets of printed
        // "9/8" on the card. A progress whose numerator can outrun its
        // denominator is not a progress.
        let live = movements.filter { !$0.isSkipped }
        let next = LiveWorkoutSnapshot(
            exercise: movement.plan.name,
            setsDone: live.reduce(0) { $0 + $1.logged.count },
            setsPlanned: live.reduce(0) { $0 + $1.plannedSets },
            // Nil until the sensor settles — a reading that has not arrived
            // and not a heart that has stopped.
            bpm: workout.heartRate,
            restEndsAt: rest?.endsAt,
            dayKey: day?.key,
            primaryMuscle: Self.primaryMuscle(of: movement.plan),
            // The instant the rate was taken, so a face can age it at two
            // minutes the way the phone ages its own copy. Nil when there is
            // no rate to date.
            bpmAt: workout.heartRate == nil ? nil : Date()
        )
        // Nothing the card draws has moved — and this method is reached twice
        // per commit (`seedCursor` then `startRest`). Reloads are budgeted on
        // a watch; spending two on an unchanged card is how the live one
        // stops updating. See `LiveWorkoutSnapshot.sameReading`.
        guard !next.sameReading(as: lastPublished) else { return }
        lastPublished = next
        next.save()
        WidgetCenter.shared.reloadTimelines(ofKind: LiveWorkoutSnapshot.widgetKind)
        WidgetCenter.shared.invalidateRelevance(ofKind: LiveWorkoutSnapshot.widgetKind)
    }

    /// The session is over. Called on finish and on discard.
    ///
    /// `LiveWorkoutSnapshot.load` already refuses a blob older than its stale
    /// window, so this is not what stops a jetsammed session haunting the
    /// stack — it is what stops a FINISHED one haunting it for the next
    /// three-quarters of an hour.
    private func clearLiveSnapshot() {
        // Nothing to clear and nothing published — a no-op rather than two
        // reloads on every launch that has no session.
        guard lastPublished != nil || LiveWorkoutSnapshot.load() != nil else { return }
        lastPublished = nil
        LiveWorkoutSnapshot.clear()
        WidgetCenter.shared.reloadTimelines(ofKind: LiveWorkoutSnapshot.widgetKind)
        WidgetCenter.shared.invalidateRelevance(ofKind: LiveWorkoutSnapshot.widgetKind)
    }

    /// The token this movement's muscle chip resolves, or nil.
    ///
    /// The phone's rule, spelled where the wrist can reach it:
    /// `LoggerModel.primaryMuscle(of:)` reads `plan.movers.primary.first` and
    /// validates it through `LandmarkMuscle`, so the deck rail, the Lock
    /// Screen and this card cannot call one movement three things. The
    /// phone's cardio fallback is not mirrored — it tests `SetRow.isCardio`,
    /// which is a phone type — and the face falls back to the split's colour,
    /// which is the right answer for a bout anyway.
    static func primaryMuscle(of plan: ProgramExercise) -> String? {
        guard let token = plan.movers.primary.first,
              LandmarkMuscle.from(token: token) != nil
        else { return nil }
        return token
    }

    // MARK: - Water, from the wrist (W4)

    /// One glass — the same 250 ml the phone's Pulse row and its Control
    /// Centre button add.
    ///
    /// Posted, not written: see `WatchLink.Inbound.water` for why this device
    /// cannot log it itself, and `pendingWaterMl` for what the page draws in
    /// the meantime.
    /// - Returns: whether the glass was queued. False means the link could
    ///   not take it — no counterpart app, or `WCSession` still activating,
    ///   which is the state for the first moment after launch. The caller
    ///   plays no haptic and the figure does not move, because a glass that
    ///   was confirmed and then lost is worse than one that visibly did not
    ///   take.
    @discardableResult
    func addWaterGlass() -> Bool {
        let ml = PendingWater.glassMl
        guard link?.send(waterMl: ml) == true else { return false }
        pendingWaterMl += Int(ml)
        return true
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
            // ── AND THE SESSION STAYS OPEN ──────────────────────────────────
            // The teardown used to run whatever happened, so a throw in the
            // metrics write left the `HKWorkout` saved, the session row still
            // live, the pencil still held — and the model believing the
            // workout was over. Returning leaves the finish button on screen,
            // which is a second tap rather than a lost session.
            failed(error)
            return
        }
        writeError = nil
        setsObserver = nil
        self.sessionId = nil
        sessionStartedAt = nil
        remoteOrigin = nil
        pauses = PauseLedger()
        sets = []
        rest = nil
        arrangement = DeckArrangement()
        clearLiveSnapshot()
        // ── THE WRIST WARMS ITS OWN CACHE (W5, decision 10) ─────────────────
        // The `HKWorkout` just written holds the series, and this store is
        // the wrist's own; the read is one query and it lands in the watch's
        // `session_telemetry`. The PHONE's cache is the phone's — its samples
        // arrive through Health's sync, which `sessionFinished` there listens
        // for. Detached and unawaited: the finish is already over.
        let telemetry = SessionTelemetry(database: store, reader: HealthKitReader())
        Task.detached(priority: .utility) { await telemetry.prefetch(sessionId: sessionId) }
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
        case .water:
            // Watch → phone only. A glass tapped on the wrist is posted and
            // written there; nothing sends one back (`WatchLink.Inbound.water`).
            break
        case .context(let next):
            context = next
            WatchContextCache.save(next)
            // ── THE PHONE HAS ANSWERED, WHATEVER IT SAID (W4) ───────────────
            // `pendingWaterMl` is an optimistic addend over the phone's own
            // reading, and this context IS the phone's reading. Clearing it
            // here means a push that arrives BEFORE the drain has run flicks
            // the Fuel page back by one glass for one push — which is honest,
            // and strictly better than a wrist that is permanently one glass
            // high because an addend was never taken off.
            pendingWaterMl = 0
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
            // leaves the wrist resolving its own ledger — see `remoteOrigin`.
            if let origin = pulse?.timerOrigin { remoteOrigin = origin }
            answerWithHeartRate(pulse)
        }
    }

    /// Send the phone's own rest pulse back to it with this wrist's heart rate
    /// on it. ONE message, only when there is a reading to carry.
    ///
    /// ── WHY THE PHONE CANNOT GET THIS ANY OTHER WAY ─────────────────────────
    /// The sensor is here. The phone drives most sessions, so the watch never
    /// starts a rest of its own and never sends a pulse — which would leave
    /// `RestPulse.bpm` a field that only ever draws on the rare wrist-driven
    /// workout, i.e. dead on the common path. The echo is what makes the
    /// phone's live reading real.
    ///
    /// ── AND WHY IT IS NOT A LOOP ────────────────────────────────────────────
    /// `PhoneWatchBridge.receive` takes the `bpm` off an inbound pulse and
    /// nothing else: it does not adopt the clock (it has its own) and it never
    /// sends in reply. So this is one message out for one message in, and it
    /// stops there. An older phone ignores the key it does not know; an older
    /// watch never sends this at all.
    ///
    /// The pulse is echoed VERBATIM but for the rate — same `endsAt`, same
    /// `duration`, same origin — so that even if a future phone were to read
    /// more of it, what comes back is what it sent.
    private func answerWithHeartRate(_ pulse: RestPulse?) {
        guard var pulse, let bpm = workout.heartRate else { return }
        pulse.bpm = bpm
        link?.send(rest: pulse)
    }
}

// MARK: - Deck shapes

extension WatchModel {

    /// One movement of today's deck, with what has been logged against it.
    /// One movement of today's deck, with what has been logged against it.
    ///
    /// A `DeckArrangement.Slot` — the position, the plan in it, whether it is
    /// skipped and how many sets have been added — plus the rows. The slot
    /// half is arithmetic and lives in OnyxCore with a suite under it; this
    /// half is the log.
    struct Movement: Identifiable, Equatable {
        let slot: DeckArrangement.Slot
        /// EVERY row of this movement, whatever kind it is.
        ///
        /// ── AND WHY THE RESTAMP WALKS THIS AND NOT `logged` ─────────────────
        /// `logged` drops warm-ups and ghosts, which is right for counting
        /// work and catastrophic for re-stamping position: mark the only set
        /// of a movement as a warm-up and then reorder the deck, and that row
        /// is invisible to the loop and keeps the `exercise_order` it was
        /// appended with. `SessionAnalysis.grouped` ranks a movement by the
        /// MINIMUM order across all its rows, warm-ups included, so the stale
        /// value drags the movement back to where it used to sit — and
        /// `RoutineOrder.save` carries that into next week's deck on every
        /// device. The phone's own restamp has always walked every row
        /// (`LoggerModel.moveExercise`, `row.isDone`, no kind filter); this is
        /// the watch agreeing with it.
        let rows: [WorkoutSet]
        /// The WORKING sets — what the deck owes is counted against these.
        let logged: [WorkoutSet]

        var plan: ProgramExercise { slot.plan }
        /// Dense from 0 — what `SetSnapshot.exerciseOrder` carries, so a
        /// watch-logged session groups on the phone the way it happened.
        var order: Int { slot.order }
        var isSkipped: Bool { slot.isSkipped }

        /// The SLOT, not the movement in it. A `ForEach` keyed on the
        /// displayed movement re-identifies the row the instant it is
        /// swapped, which tears down the gesture that did the swapping.
        var id: String { slot.originId }
        var originId: String { slot.originId }

        /// The phase's own set count, plus anything added on the wrist.
        /// `cutSets` may legitimately be zero, which drops the movement —
        /// `exercises(for:)` has already filtered those out by the time this
        /// is built.
        var plannedSets: Int { plan.sets + slot.extraSets }

        var isDone: Bool { logged.count >= plannedSets }

        /// What the NEXT set of this movement is stored under.
        ///
        /// `rows` and not `logged`: marking the last set a warm-up drops it
        /// out of `logged`, so a `logged.count + 1` index would hand the next
        /// set the index the warm-up already holds, and two rows of one
        /// movement would collide on `(exercise_id, set_index)`.
        var nextStoreIndex: Int { rows.count + 1 }
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
    /// - Parameter restDay: seeds the same plan with TODAY unscheduled, which
    ///   is what `resolveDay` reads as a rest day. The one state the founder
    ///   named by name — the old root was the word "Rest day" and nothing else
    ///   — and it had no shot hook, so nobody had reviewed it since it was
    ///   written. `watch-shot.sh restday` is that hook.
    func seedDebugContext(restDay: Bool = false) {
        let today = LogicalDay.iso()
        let next = WatchContext(
            userId: "preview",
            today: today,
            schedule: ScheduleContext(
                programId: "onyx5",
                phase: .cut,
                overrides: restDay ? [:] : [today: "cb_b"],
                // Spelled out rather than read from `PlanTemplates`: that
                // lives in the APP target and the watch cannot see it. Three
                // real movements off the founder's Upper B — enough deck for
                // the cursor to advance and for `lastTime` to have something
                // to say, and the names are ones `MuscleMap` actually knows.
                // ── AN EMPTY PROGRAM IS WHAT MAKES A REST DAY (W2) ──────
                // Clearing `overrides` is NOT enough: `Schedule.scheduleDayIn`
                // falls back to the day's own `weekday`, so the first rest-day
                // shot came back as the training hero with "Upper B" on it —
                // a real screen under the wrong filename. A program with no
                // days is the only seed `resolveDay` reads as nothing
                // scheduled.
                programs: [
                    Program(id: "onyx5", label: "Onyx 5", days: restDay ? [] : [
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
                kcal: 1_640, kcalGoal: 2_150, todayLabel: restDay ? "Rest" : "Upper B",
                todayLogged: false,
                restDay: restDay, stressIndex: 41.5, sorenessCount: 3,
                week: (0..<7).map { WatchTiles.WeekDay(trained: $0 % 2 == 0, fuelHit: $0 != 3, sleepHit: $0 > 1) },
                medianBedtime: "23:12", lastBedtime: "00:16",
                // W4's four. Without them the Train page photographs "No
                // volume yet" and the Fuel page falls back to the kcal line
                // — both real states, and neither the one under review.
                weekSets: 84, weekVolumeKg: 12_430, proteinG: 118, proteinGoalG: 185
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
            if let origin = rest?.timerOrigin { remoteOrigin = origin }
            // A heart, so the sparkline has a shape. A simulator has none, and
            // `recentSamples` is `private(set)` against exactly this — the
            // seed goes through the controller's own DEBUG door.
            workout.seedDebugSamples(Self.debugHeartSeries)
        }
        rest = RestPulse(
            sessionId: sessionId ?? "preview",
            endsAt: Date().addingTimeInterval(97),
            duration: 150,
            exercise: "Single Arm Cable Crossover",
            loadKg: 42.5,
            reps: 12,
            rpe: 8.5,
            timerOrigin: Date().addingTimeInterval(-45 * 60),
            // The rate AT THE MOMENT THE REST STARTED, which is what the rest
            // screen's recovery delta is measured from. Without it the shot
            // showed a curve and a number with nothing to compare them to — a
            // real state (an older phone sends no rate) and not the one under
            // review.
            bpm: Self.debugHeartSeries.first
        )
    }

    /// A recovery curve, not a random walk: the rate is still up at the top of
    /// the rest and settles over the next two minutes, which is the SHAPE the
    /// sparkline exists to show. A flat or noisy seed would photograph a line
    /// that says nothing and pass review anyway.
    static let debugHeartSeries: [Int] = {
        (0..<60).map { i in
            let t = Double(i) / 59
            return Int((148 - 44 * (1 - pow(1 - t, 2.2))).rounded())
        }
    }()

    /// Put sets in the log so the deck, the quality panel and the finish card
    /// have something real to draw.
    ///
    /// It goes through `commitSet` — the ordinary path, events, fold, rest
    /// clock and all — rather than writing rows, for the reason
    /// `seedDebugContext` goes through the cache: a screenshot of a second
    /// code path is a screenshot of something that does not ship. The rest
    /// cover it opens is closed again, because every screen that wants these
    /// sets wants them WITHOUT a cover over the top.
    func seedDebugSets(_ count: Int) {
        for _ in 0..<count {
            guard cursor != nil else { break }
            // `commitSet` re-reads the fold itself now, so the loop advances
            // the way a finger does. It did not, and every set here was
            // appended as set 1 of the first movement: the deck showed "2/3"
            // while the quality panel's header said "Set 1", which is how
            // that defect was caught.
            _ = commitSet()
        }
        rest = nil
        workout.seedDebugSamples(Self.debugHeartSeries)
    }
}
#endif
