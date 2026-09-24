import Foundation
import GRDB
import HealthKit
import Observation
import OnyxCore
import OnyxData
import OnyxUI
import os
// For the timeline reload a wrist-tapped glass owes the Home Screen (W4).
import WidgetKit

/// The phone's half of the watch link.
///
/// ── WHAT IT OWES THE WATCH ──────────────────────────────────────────────────
/// Three things, and they are not the same kind of thing.
///
///   · **The context** — who is signed in, what today is, and how the plan
///     resolves it. STATE, sent over `updateApplicationContext`, replaced
///     wholesale, and the only reason the watch can name today's split at all.
///     Without it the watch shows "Open Onyx on your iPhone" and nothing else.
///   · **The events** — every set, amend, void and pause this phone produces.
///     FACTS, sent over `transferUserInfo`, queued and delivered even when the
///     watch app is not running.
///   · **The session's life** (App Store W4) — opened, finished, discarded, as
///     a `SessionPulse` carrying the row, in the events' own queue. Without
///     the row the wrist's store refuses every event behind it.
///
/// ── AND WHY THE PHONE IS THE ONLY ROAD TO THE NETWORK ───────────────────────
/// Wave 10 decided the watch holds no Supabase session: no refresh token
/// travels, and no credential sits on a second device. The consequence is that
/// this bridge is load-bearing in one direction — a set logged on the wrist
/// reaches the server through this phone's outbox and no other way — and it is
/// why every send here is queued rather than immediate.
@MainActor
@Observable
final class PhoneWatchBridge {

    private let database: AppDatabase
    private var link: WatchLink?
    private var commitObserver: AnyDatabaseCancellable?

    /// The highest `seq` of our own events the watch has been sent.
    ///
    /// Persisted so a relaunch does not re-send a whole workout. Re-sending
    /// would be harmless — `ingest` de-duplicates by event id — but it is a
    /// queued transfer per commit carrying nothing new.
    private var sentThrough: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: Self.markKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: Self.markKey) }
    }
    private static let markKey = "onyx.watch.sentThroughSeq"

    /// What went wrong last, for the sync diagnostics row. Never surfaced
    /// mid-workout: a failed transfer is not something the athlete can act on,
    /// and the set is already safe in the log.
    private(set) var lastError: String?

    /// Run the pending-water drain (W4). Set once by `AppEnvironment.start`.
    ///
    /// ── A CLOSURE, BECAUSE THE DRAIN NEEDS THE SESSION AND THIS DOES NOT ───
    /// `drainPendingWater` writes under the signed-in user id, and this type
    /// deliberately holds a database and no auth — it is a wire. What it keeps
    /// for itself is a heart rate, the sessions the wrist joined, and the news
    /// the Train tab has not read yet.
    /// Handing it `AppEnvironment` to reach one method would give the wire a
    /// reference to the whole app; handing it the method is the same call
    /// with none of that. The session closures below (W4) are the same idea.
    ///
    /// Optional because the harness and the tests build a bridge with no
    /// environment behind it, and a glass arriving there should be a no-op
    /// rather than a trap — the key simply waits for a launch that has one.
    var onWaterQueued: (() -> Void)?

    /// What the wrist did to a session that the Train tab has not acted on
    /// yet (App Store W4). The tab reads it, acts, and clears it.
    ///
    /// ── ONE VALUE, READ IN ONE ORDER ────────────────────────────────────────
    /// Stored rather than a callback into a view: the tab is built lazily and
    /// may not exist when a pulse lands. And ONE value holding both, because
    /// the order matters and two `onChange`s have none: when the wrist's open
    /// beats this phone's own empty one, the tab must let go of its session
    /// BEFORE it can follow the wrist's — the follow refuses while it is
    /// holding one.
    struct WristNews: Equatable {
        /// Sessions the wrist finished or discarded, or that lost to one of
        /// the wrist's. The tab lets go of its model if it was holding one.
        /// A set: two can end before the tab next reads.
        var ended: Set<String> = []
        /// A session the wrist opened. The tab presents the logger for it.
        var opened: String?
    }
    private(set) var news = WristNews()
    /// The last provisional RPE the wrist's Crown sent (overhaul A3). Read
    /// by the live logger; never persisted.
    private(set) var effort: EffortPulse?
    /// `.notice`, so `log show` returns it — the phone's half of the watch's
    /// own session log (App Store W4).
    private let log = Logger(subsystem: "app.onyx.phone", category: "watch")
    /// Only for `startWatchApp` (W5.2) — one store for the bridge's lifetime.
    private let healthStore = HKHealthStore()
    func clearNews() { news = WristNews() }

    /// Switches the shell to the Train tab when the wrist opens a session.
    /// Set by `AppEnvironment.start`, for the reason `onWaterQueued` is a
    /// closure: this is a wire, and the selected tab is the app's.
    var onSessionOpened: (() -> Void)?
    /// The wrist finished a session: the phone's `sessionFinished`, which a
    /// finish on THIS phone runs from the logger (the telemetry prefetch, and
    /// the Health-workout decision — which `joined` makes a skip).
    var onSessionClosed: ((String) -> Void)?

    /// Sessions whose `HKWorkoutSession` the wrist said it was running.
    ///
    /// ── THE DUPLICATE `HKWorkout` THIS PREVENTS ─────────────────────────────
    /// `WorkoutWriter.decide` writes the phone's own workout for a session
    /// nobody else measured, and it used to learn "somebody else did" only
    /// from a set logged there or a heart rate echoed during the interval. A
    /// phone-started session the wrist now FOLLOWS has neither until the
    /// athlete rests — and the wrist saves its workout when the phone
    /// finishes. So the wrist says `.joined` on every adoption, and this is
    /// where it is kept.
    ///
    /// Persisted, because the phone is jetsammed mid-workout often enough to
    /// matter and the wrist does not repeat itself. The last twenty is plenty:
    /// the question is only ever asked at a finish.
    private(set) var joined: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.joinedKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(20)), forKey: Self.joinedKey) }
    }
    private static let joinedKey = "onyx.watch.joinedSessions"

    /// The wrist's last heart rate, and when it arrived (W10, decision 3).
    ///
    /// ── THE ONE THING THE PHONE TAKES OFF AN INBOUND REST PULSE ─────────────
    /// `receive` still refuses the watch's CLOCK — this device has its own
    /// logger, its own timer and its own Live Activity, and two clocks fighting
    /// over one banner is worse than one clock. The heart rate is the opposite
    /// case: there is no second source for it on this device at all, so the
    /// pulse is the only road it has.
    ///
    /// The instant travels with it because a heart rate is only a reading while
    /// it is fresh. `RestPulse` arrives over `sendMessage`, which needs
    /// reachability — put the phone in a locker and the last number sits here
    /// unrefreshed. `liveBpm` is what views read, and it goes back to nil after
    /// `bpmStaleAfter`; a stale number presented as live is the failure this
    /// pair exists to prevent.
    private(set) var lastBpm: Int?
    private(set) var lastBpmAt: Date?

    /// How long a wrist reading stays a reading.
    ///
    /// `LiveWorkoutSnapshot.bpmStaleAfter` since W4, not a second 120: the
    /// watch draws the same sensor on its own faces now, and two devices
    /// disagreeing about when a heart rate stopped being one is the drift a
    /// shared constant exists to prevent.
    static let bpmStaleAfter: TimeInterval = LiveWorkoutSnapshot.bpmStaleAfter

    /// Wakes once, `bpmStaleAfter` after the last reading, to make the expiry
    /// an actual mutation (W4).
    ///
    /// ── WHY A TIMER AFTER ALL, WHEN `liveBpm` ARGUED AGAINST ONE ───────────
    /// `liveBpm` is COMPUTED, and the note above it says a timer whose only
    /// job is to nil a field would run for the whole of every workout. That
    /// was right while the only readers were views that redraw when a set
    /// lands. The Live Activity is not one: `LiveActivityController` caches
    /// the last value it was handed and only re-pushes when something tells
    /// it to, and `@Observable` fires on a STORED-property mutation — two
    /// minutes elapsing is not one. So the Lock Screen and the Dynamic
    /// Island kept drawing 142 from a watch that had come off the wrist,
    /// which is precisely what `liveBpm`'s own doc says must never happen.
    ///
    /// Not a `Timer`, and not running for the whole workout: one `Task` per
    /// reading, replaced by the next one, cancelled when the app tears the
    /// bridge down. A workout produces one of these per rest pulse and each
    /// costs a sleep.
    private var bpmExpiry: Task<Void, Never>?

    /// The wrist's heart rate if it is still fresh, otherwise nil.
    ///
    /// Computed rather than stored: nothing ticks in this type, and a timer
    /// whose only job is to nil a field is a timer running for the whole of
    /// every workout. The readers are views, they redraw when a set lands, and
    /// a number that lingers a few seconds past its window on a screen nobody
    /// is touching is not a defect worth a `Timer` for.
    var liveBpm: Int? {
        guard let lastBpm, let lastBpmAt,
              Date().timeIntervalSince(lastBpmAt) < Self.bpmStaleAfter
        else { return nil }
        return lastBpm
    }

    init(database: AppDatabase) {
        self.database = database
    }

    /// Open the link and start watching for local writes.
    ///
    /// Called from `AppEnvironment.start`, once. Safe on a phone with no watch
    /// paired: `WatchLink.activate` checks `WCSession.isSupported()` and every
    /// send checks `isPaired && isWatchAppInstalled`, so this costs nothing at
    /// all on a phone that has never seen an Apple Watch.
    func start() {
        guard link == nil else { return }
        let link = WatchLink { [weak self] inbound in
            Task { @MainActor in self?.receive(inbound) }
        }
        link.activate()
        self.link = link

        // Every committed write, debounced by nothing: `localEvents(after:)` is
        // an indexed read of the rows above a cursor, and on a commit that wrote
        // no event of ours it returns empty and sends nothing. The same
        // `onCommit` seam the widget reload and the watch's own projection use.
        commitObserver = database.onCommit { [weak self] in
            Task { @MainActor in self?.flush() }
        }
        flush()
    }

    /// Hand the watch every event of ours it has not seen.
    func flush() {
        guard let link else { return }
        do {
            let pending = try database.localEvents(after: sentThrough)
            guard !pending.isEmpty else { return }
            link.send(events: pending)
            // Advanced only after the transfer is QUEUED, not after it is
            // delivered — WatchConnectivity owns the delivery and retries it
            // across relaunch and reboot. Advancing on delivery would mean
            // holding the cursor back for the whole time a watch is off the
            // wrist, and then re-sending an entire workout when it comes back.
            sentThrough = pending.map(\.seq).max() ?? sentThrough
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Tell the watch who is signed in and what today is.
    ///
    /// Called on sign-in, on the midnight roll, and whenever the plan or phase
    /// changes. Cheap and idempotent: one slot, overwritten, and the watch
    /// caches whatever arrived last so a cold launch out of range still opens
    /// the right split.
    ///
    /// `tiles` (W7) is the complications' dozen numbers, cut from the same
    /// snapshot the Home Screen widgets draw. It rides INSIDE the context
    /// rather than as a second application-context kind, because the channel
    /// is one slot: a second kind would overwrite the schedule every time a
    /// number moved, and the watch would open on "Open Onyx on your iPhone"
    /// between two pushes.
    func send(userId: String, today: String, schedule: ScheduleContext, tiles: WatchTiles?) {
        var tiles = tiles
        // The Next Dose complication's reading (overhaul Lane A, decision Q5):
        // the snapshot the tiles are cut from carries no supplement schedule,
        // so the stack is read here, where the push is assembled.
        let isTraining = !(tiles?.restDay ?? false)
        tiles?.nextDose = nextDose(today: today, isTraining: isTraining)
        var context = WatchContext(
            userId: userId, today: today, schedule: resolved(schedule),
            // The wrist wears what the phone wears. The watch has no
            // Settings screen for this, and a second place to set a theme
            // is a second place for the two to disagree.
            theme: OnyxTheme.current.spec,
            tiles: tiles
        )
        // Every push carries the lifecycle — sign-in, the midnight roll, a
        // theme pick and the throttled tiles alike — so the one slot never
        // says less about today's session than the last push did.
        context.session = lifecycle(for: context)
        lastContext = context
        link?.send(context: context)
    }

    // MARK: - The session's lifecycle (overhaul Lane A, decision Q1)

    /// The phone's word on today's session — open, finished or discarded —
    /// as it last changed, and whose it is.
    ///
    /// ── PERSISTED, BECAUSE THE SLOT MUST NEVER REGRESS ──────────────────────
    /// Every context push rewrites the watch's ONE application-context slot.
    /// A phone relaunched after a finish that held this only in memory would
    /// push the next tiles with no lifecycle, and the wrist would go back to
    /// offering Start for a workout that is over — the reported bug, one
    /// jetsam later. Keyed on the user, so an account switch cannot hand one
    /// person's banner to another.
    private struct Word: Codable {
        var userId: String
        var lifecycle: SessionLifecycle
    }
    private static let wordKey = "onyx.watch.lifecycle"
    private var word: Word? {
        get { UserDefaults.standard.data(forKey: Self.wordKey).flatMap { try? OnyxJSON.decoder.decode(Word.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? OnyxJSON.encoder.encode($0) }, forKey: Self.wordKey) }
    }

    /// The last context sent, so a lifecycle change can go out NOW with the
    /// last known tiles on it rather than wait for a fresh `.full` build.
    private var lastContext: WatchContext?

    /// The lifecycle moved. `AppEnvironment.pushLifecycle` — the unthrottled
    /// push. Nil in the harness and the tests, where the bridge re-sends its
    /// own last context instead.
    var onLifecycleChanged: (() -> Void)?

    /// What `context` should say about the session: the stored word when it is
    /// this user's and still about today — an OPEN session is carried whatever
    /// its date, a finished one only on its own day. A finished session's
    /// masthead is rebuilt on every push, because the heart-rate spark lands
    /// in the telemetry cache AFTER the finish (`sessionFinished`'s prefetch),
    /// and that write is a commit that throttles its own push through here.
    private func lifecycle(for context: WatchContext) -> SessionLifecycle? {
        guard var word, word.userId == context.userId else { return nil }
        guard word.lifecycle.phase == .open || word.lifecycle.isOn(context.today) else { return nil }
        // An OPEN word is checked against the row: a session closed or thrown
        // away by a path that never came through here (a crash, a history
        // delete) must not keep offering the wrist a Join.
        if word.lifecycle.phase == .open {
            guard let row = try? database.session(id: word.lifecycle.sessionId, userId: word.userId) else { return nil }
            if let ended = row.endedAt {
                word.lifecycle.phase = .finished
                word.lifecycle.endedAt = ended
            }
        }
        if word.lifecycle.phase == .finished,
           let summary = try? database.sessionMasthead(
               sessionId: word.lifecycle.sessionId, userId: word.userId,
               name: dayName(word.lifecycle.dayKey, in: context.schedule)
           ) {
            word.lifecycle.summary = summary
        }
        return word.lifecycle
    }

    /// Re-send the last context with the current lifecycle on it. False when
    /// nothing has been sent this launch — the caller builds a whole one.
    @discardableResult
    func pushLifecycle() -> Bool {
        guard var context = lastContext else { return false }
        context.session = lifecycle(for: context)
        lastContext = context
        link?.send(context: context)
        return true
    }

    /// A session opened, finished or was discarded — on this phone or on the
    /// wrist. Stored, then pushed without the tiles' throttle.
    private func record(_ pulse: SessionPulse) {
        guard let lifecycle = SessionLifecycle(pulse) else { return }
        // ── NEVER BACKWARDS (after review) ──────────────────────────────────
        // The same three rules the wrist's `noteWord` keeps: a pulse about an
        // OLDER session than the stored word, the discard of a losing rival
        // while the winner is open, and a late open for a session the word
        // has already closed all leave the word alone. Otherwise every later
        // context told the wrist the live session had been discarded.
        if let current = word?.lifecycle, word?.userId == pulse.userId {
            if current.sessionId != lifecycle.sessionId, current.startedAt > lifecycle.startedAt { return }
            if current.sessionId != lifecycle.sessionId, current.phase == .open, lifecycle.phase == .discarded { return }
            if current.sessionId == lifecycle.sessionId, current.phase != .open, lifecycle.phase == .open { return }
        }
        word = Word(userId: pulse.userId, lifecycle: lifecycle)
        log.notice("lifecycle \(lifecycle.phase.rawValue, privacy: .public) \(lifecycle.sessionId, privacy: .public)")
        if let onLifecycleChanged { onLifecycleChanged() } else { pushLifecycle() }
    }

    /// The next timed slot of today's stack, through the same resolver the
    /// Stack screen draws (`customSlotsForDate` → `stackForDate`), so the
    /// complication and the phone cannot name different doses. Read once per
    /// push — a small table, and pushes are throttled to one per 30 s.
    private func nextDose(today: String, isTraining: Bool, now: Date = Date()) -> WatchTiles.NextDose? {
        guard let rows = try? database.read({ db in try CustomSupplementRow.fetchAll(db) }), !rows.isEmpty else { return nil }
        let active = Supplements.active(rows.map(AppDatabase.custom), on: today)
        let weekday = ISODate.weekday(today) ?? 0
        let slots = Supplements.stackForDate(
            Supplements.customSlotsForDate(active, on: today, weekday: weekday, isTraining: isTraining),
            isTraining: isTraining, weekday: weekday
        )
        let clock = Calendar.current.dateComponents([.hour, .minute], from: now)
        return .next(in: slots, date: today, nowMinutes: (clock.hour ?? 0) * 60 + (clock.minute ?? 0))
    }

    /// The split's own name for the banner — the deck's label, else the key
    /// tidied, the rule `SessionAnalysis.dayLabel` follows.
    private func dayName(_ dayKey: String?, in schedule: ScheduleContext) -> String {
        SessionAnalysis.dayLabel(dayKey, in: schedule.activeProgram) ?? "Workout"
    }

    /// Fill in `ProgramExercise.exerciseId` wherever the routine payload left
    /// it nil, from the phone's own catalogue.
    ///
    /// ── SO THE TWO DEVICES AGREE BEFORE THEY WRITE ──────────────────────────
    /// `WatchModel.exerciseId(of:)` writes this id when it has one and the
    /// legacy slug when it does not, while the phone resolves the catalogue —
    /// so a movement the payload could not name is the one case where the two
    /// spell the same set differently and `SessionAnalysis.grouped` draws it
    /// twice. The phone knows the answer and already sends the deck; sending it
    /// resolved costs one read and removes the disagreement at the source.
    ///
    /// Resolution only. A name the catalogue does not hold, or holds twice,
    /// stays nil and both devices fall back to the slug — which is agreement
    /// too, and `ExerciseIndex` resolves it at push. Minting a row to send to a
    /// watch would be creating a fact to answer a question nobody asked.
    private func resolved(_ schedule: ScheduleContext) -> ScheduleContext {
        guard let byName = try? database.exerciseIdsByCanonicalName(), !byName.isEmpty else {
            return schedule
        }
        var schedule = schedule
        for program in schedule.programs.indices {
            for day in schedule.programs[program].days.indices {
                for slot in schedule.programs[program].days[day].exercises.indices {
                    let exercise = schedule.programs[program].days[day].exercises[slot]
                    guard exercise.exerciseId == nil else { continue }
                    schedule.programs[program].days[day].exercises[slot].exerciseId =
                        byName[ExerciseAliases.canonicalName(exercise.name).lowercased()]
                }
            }
        }
        return schedule
    }

    /// Clear `lastBpm` once the reading has aged out, so the expiry is a
    /// mutation something can observe.
    ///
    /// ── IT RE-CHECKS RATHER THAN ASSUMING ──────────────────────────────────
    /// A pulse that arrives while this is asleep replaces the task, but the
    /// replaced one may already be past its `sleep` and about to write. The
    /// guard is `liveBpm == nil` — the same computed answer every reader
    /// uses — so a task that wakes to find a fresher reading in place does
    /// nothing rather than blanking it.
    private func scheduleBpmExpiry() {
        bpmExpiry?.cancel()
        bpmExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.bpmStaleAfter))
            guard !Task.isCancelled, let self, self.liveBpm == nil else { return }
            self.lastBpm = nil
            self.lastBpmAt = nil
        }
    }

    // ── NO `deinit` CANCEL, AND IT IS NOT NEEDED ────────────────────────────
    // A `deinit` is nonisolated on a `@MainActor` class under Swift 6, so it
    // cannot touch `bpmExpiry` at all — "main actor-isolated property cannot
    // be referenced from a nonisolated context", which is a build error and
    // not a warning. It is also unnecessary: the task captures `[weak self]`
    // and does nothing when the bridge has gone, and the worst case is one
    // sleeping task outliving it by under two minutes. This bridge lives for
    // the lifetime of the app in every shipping path anyway.

    /// Mirror the phone's rest clock onto the wrist. `nil` stops it.
    func send(rest: RestPulse?) {
        link?.send(rest: rest)
    }

    /// Tell the wrist a session opened, finished or was discarded here (App
    /// Store W4). See `WatchLink.send(session:)` for the channels.
    ///
    /// A FINISH carries this store's event count for the session (overhaul
    /// Lane A), which is what lets `WatchLink` message it as well as queue it:
    /// the wrist holds the messaged copy until its own log has caught up. The
    /// flush first, so every set of ours is queued ahead of the finish.
    func send(session pulse: SessionPulse) {
        var pulse = pulse
        if pulse.phase == .finished {
            flush()
            pulse.expectedEventCount = try? database.authoredEventCount(sessionId: pulse.sessionId)
        }
        link?.send(session: pulse)
        record(pulse)
        if pulse.phase == .open { launchWatchApp() }
    }

    /// Wake a CLOSED watch app on the phone's Start (overhaul W5.2, founder
    /// decision 2026-09-24). A running or recently woken app already follows
    /// the messaged open; a closed one only learned of the session when the
    /// wearer opened it. `startWatchApp` launches it with a strength workout
    /// configuration, and the launch runs the ordinary lifecycle path
    /// (`WatchModel.handleWorkoutLaunch` → the queued open → adopt).
    ///
    /// Never blocks Start: it is fire-and-forget, and every outcome is logged.
    /// It fails quietly without HealthKit authorisation — which only a device
    /// can prove (the simulator pair has no HK workout launch).
    private func launchWatchApp() {
        guard let reach = link?.reach else {
            log.notice("startWatchApp skipped: the watch link has not activated")
            return
        }
        guard WatchLaunch.shouldStartWatchApp(paired: reach.paired, installed: reach.installed, reachable: reach.reachable) else {
            log.notice("startWatchApp skipped: paired \(reach.paired), installed \(reach.installed), reachable \(reach.reachable)")
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            log.notice("startWatchApp skipped: no HealthKit on this device")
            return
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let log = log
        healthStore.startWatchApp(with: configuration) { launched, error in
            if launched {
                log.notice("startWatchApp launched the watch app")
            } else {
                log.error("startWatchApp failed: \(error?.localizedDescription ?? "no error", privacy: .public)")
            }
        }
    }

    // MARK: - Inbound

    private func receive(_ inbound: WatchLink.Inbound) {
        do {
            switch inbound {
            case .events(let events):
                // ── MERGED LIKE A PULL, QUEUED LIKE OUR OWN ────────────────
                // `ingest` marks what it takes as synced, which stranded every
                // watch set until the phone happened to touch the same session
                // (W2, decision 15). `ingestFromWatch` merges the same way and
                // queues each event through the phone's own outbox.
                try database.ingestFromWatch(events)
            case .ownership(let claim):
                try database.ingestOwnership(claim)
            case .rest(let pulse):
                // The phone does not mirror the watch's rest CLOCK. It has its
                // own logger with its own timer and its own Live Activity, and
                // two clocks fighting over one banner is worse than one clock.
                //
                // The heart rate is taken, and only it — see `lastBpm`. Nothing
                // is sent back from here, which is what keeps the watch's echo
                // (`WatchModel.answerWithHeartRate`) one message rather than a
                // conversation.
                if let bpm = pulse?.bpm, bpm > 0 {
                    lastBpm = bpm
                    lastBpmAt = Date()
                    scheduleBpmExpiry()
                }
            case .water(let ml):
                // ── THE WRIST'S GLASS, INTO THE PHONE'S OWN MAILBOX (W4) ───
                // Not written here. `PendingWater` is the same key Control
                // Center's `AddWaterIntent` drops a glass into, and
                // `AppEnvironment.drainPendingWater` is what turns it into a
                // `water_intake` row — under the signed-in user, through
                // `addWaterGlass`, with the ledger re-summed and the day
                // rescored at the door. This bridge has a database and no
                // idea who is signed in, and inventing a second write path
                // for the same 250 ml is how two glasses stop being one row.
                PendingWater.add(ml, to: AppDatabase.appGroupDefaults())
                // The widgets' optimistic figure reads the mailbox directly
                // (`WidgetStore.snapshot`), so this is what makes the Home
                // Screen agree with the wrist before the drain has run.
                WidgetCenter.shared.reloadAllTimelines()
                // And the drain itself, now rather than at the next return to
                // `.active`: a `transferUserInfo` wakes this app in the
                // BACKGROUND, which is not a scene phase change, so without
                // this the glass would sit in the mailbox until the phone was
                // next picked up. Signed out it does nothing and the key
                // waits, which is `drainPendingWater`'s own behaviour.
                onWaterQueued?()
            case .effort(let pulse):
                // The wrist's Crown, mid-scrub (overhaul A3). Held here for
                // the logger to read — `LiveLoggerView` hands it to
                // `LoggerModel.receiveEffort`, which draws it as provisional
                // ink. Never stored: the wire says so and so does this.
                effort = pulse
            case .session(let pulse):
                // ── THE WRIST'S SESSION, IN THIS STORE (App Store W4) ───────
                // The row first — `ingestFromWatch` refuses a set whose
                // session this store has never seen, and the watch cannot
                // push its own.
                let outcome = try database.receiveSession(pulse)
                log.notice("pulse \(pulse.phase.rawValue, privacy: .public) \(pulse.sessionId, privacy: .public) from the watch: \(String(describing: outcome), privacy: .public)")
                // A JOIN, and not an open: the wrist announces an open before
                // HealthKit has said yes, and a refused workout session sends
                // no join — so counting the open would stop this phone writing
                // the one workout nobody else is going to.
                if pulse.phase == .joined, !joined.contains(pulse.sessionId) {
                    joined.append(pulse.sessionId)
                }
                switch outcome {
                case .opened(let superseded):
                    // This phone's own EMPTY row for the split lost to the
                    // wrist's earlier one and is gone here; the wrist holds a
                    // copy (this phone announced it) and is told.
                    if let superseded {
                        link?.send(session: SessionPulse(superseded, phase: .discarded))
                        news.ended.insert(superseded.id)
                    }
                    news.opened = pulse.sessionId
                    record(pulse)
                    onSessionOpened?()
                case .closed, .discarded:
                    news.ended.insert(pulse.sessionId)
                    // The phone owns the lifecycle whoever ended it: a
                    // wrist-finished session gets its banner the same way.
                    record(pulse)
                    // A start banked for this split would otherwise be adopted
                    // by the next Start on it today — a dead session's clock
                    // on a new one. Finish and cancel clear it; this is their
                    // road when the wrist is the one that ended it.
                    if let dayKey = pulse.dayKey { LiveSessionStart.clear(dayKey: dayKey, date: pulse.date) }
                    if outcome == .closed { onSessionClosed?(pulse.sessionId) }
                case .unchanged:
                    break
                }
            case .context:
                // Phone → watch only. The watch has no plan resolution to send.
                break
            }
        } catch {
            lastError = String(describing: error)
            log.error("inbound refused: \(String(describing: error), privacy: .public)")
        }
    }
}
