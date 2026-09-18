import Foundation
import Observation
import Supabase
import WidgetKit
import OnyxCore
import OnyxData
import OnyxUI

/// Everything the app needs, resolved once at launch.
///
/// ── WHY THIS IS ONE OBJECT AND NOT A PILE OF SINGLETONS ─────────────────────
/// The web app's equivalent state is spread across a react-query client, a
/// Supabase client module, 24 `localStorage` keys and four provider components,
/// and the recurring bug class there is two of them disagreeing — a cache that
/// says signed-in while the session is gone, a schedule store read during render
/// that React cannot see. One owned object with one source of truth for each
/// fact removes that class rather than managing it.
@MainActor
@Observable
public final class AppEnvironment {

    public enum AuthState: Equatable {
        /// Reading the Keychain. Sub-millisecond, but it is a real state and
        /// pretending otherwise is what produces a flash of the wrong screen.
        case resolving
        case signedIn(userID: UUID)
        case signedOut
    }

    public private(set) var auth: AuthState = .resolving
    /// A launch failure worth showing rather than crashing on — a missing
    /// `Secrets.xcconfig` is the overwhelmingly likely cause and the message
    /// says so.
    public private(set) var startupError: String?

    /// `profiles.role` for the signed-in user, read ONCE per session from the
    /// local mirror. Nil until the first sync has landed the row.
    ///
    /// ── WHY IT FAILS CLOSED ─────────────────────────────────────────────────
    /// It gates the developer-only Settings rows, so "unknown" must mean "not
    /// an admin". A fresh sign-up sees no admin rows until its profile row
    /// arrives, and if it never arrives it never sees them — which is the right
    /// answer for a member and a recoverable inconvenience for the one admin.
    /// Nothing SECURITY-relevant hangs off this: the rows it hides are
    /// diagnostics, and the server's RLS does not consult it.
    public private(set) var role: String?

    public var isAdmin: Bool { role == "admin" }

    public let database: AppDatabase
    public let supabase: SupabaseClient

    /// What Today's hairline and "Synced 2s ago" caption read. Owned here
    /// because every tab will report the same sync, and two of them holding
    /// their own idea of when it last ran is the disagreement this class exists
    /// to prevent.
    let sync = SyncStatus()

    /// The watch link. Present on every phone; inert on one with no Apple Watch
    /// paired, because every send checks `isPaired && isWatchAppInstalled`
    /// first. See `PhoneWatchBridge`.
    /// `@ObservationIgnored` because `@Observable` rewrites every stored
    /// property into a computed one, and `lazy` cannot be computed. Correct
    /// either way: nothing in the phone UI reads the bridge — it is a transport,
    /// and its one piece of state (`lastError`) is for a diagnostics row that
    /// does not exist yet.
    @ObservationIgnored private(set) lazy var watchBridge = PhoneWatchBridge(database: database)

    /// The whole sync — `OnyxData`'s `SyncCoordinator`, one per signed-in
    /// user. It owns the HealthKit read, the outbox drain, the pulls, the
    /// score and the realtime socket, in that order. Nil while signed out.
    var coordinator: SyncCoordinator?
    /// Non-nil while the first-launch backfill sheet is up (§7.2). The sheet
    /// binds to this; `runBackfill` clears it when the history has landed.
    var backfill: BackfillModel?
    /// Non-nil while a brand-new account is being set up (W5). Offered once,
    /// after the first pull has landed — see `offerOnboardingIfNeeded`.
    var onboarding: OnboardingModel?
    /// What every gauge, widget snapshot and score input is graded against
    /// (§6.2): one observation over `user_goals`, `daily_targets`,
    /// `target_profiles` and `schedule_overrides`. A lever pulled in Settings
    /// is one outbox row and one tick here; no view keeps a copy. Nil while
    /// signed out.
    private(set) var targets: TargetResolver?

    #if DEBUG
    /// The preview environment's resolver, over its seeded in-memory store —
    /// so a preview reads the same live catalogue (decks, plans, phases,
    /// rungs) a signed-in screen does. Never called outside `.preview`.
    func installPreviewTargets(userId: String) {
        let resolver = TargetResolver(database: database, userId: userId)
        resolver.start()
        targets = resolver
    }
    #endif

    /// The logical day, republished at local midnight (§6.4). A model that
    /// holds its own `today` re-reads it on change; nothing is written for a
    /// rollover, and a `WeekWindow` cut from this re-cuts itself on the first
    /// weekday without a second timer.
    private(set) var today: String = LogicalDay.today()
    /// Bumped with `today`, for a view that only needs to know a day passed.
    private(set) var dayTick = 0

    /// Health has today's weight, and the InBody numbers it cannot know are
    /// still blank.
    ///
    /// ── WHY THE ROW AND NOT THE INGEST REPORT ───────────────────────────────
    /// `HealthSync` reports `body_composition` in its `IngestReport` when a
    /// weigh-in lands, and that was the obvious hook. It is the wrong one: a
    /// report exists only for the length of one sync, so a banner keyed to it
    /// appears once and is gone the next time the app launches — while the two
    /// blank columns are still blank. The ROW is the fact. HealthKit has no
    /// muscle-mass or body-water type at all (`DailyLogIngest` says so where it
    /// deliberately leaves `muscle_mass_kg` alone), so a row with a weight and
    /// no muscle is exactly "the scale synced, the reading is half here".
    ///
    /// ── AND WHY THE ROW ALONE IS NOT ENOUGH ─────────────────────────────────
    /// It was, and the banner would not go away. The row IS the fact, but it is
    /// a fact this app does not fully control: `DailyLogIngest` rewrites the
    /// day's `body_composition` row on every sync, a pull replaces it with the
    /// server's copy, and a day that ends up with more than one row is read by
    /// `measured_at` — so "the two columns are blank" could go back to being
    /// true minutes after the athlete filled them in. A predicate with no
    /// memory then asks the same question again, and again, for the rest of the
    /// day.
    ///
    /// So there are two conditions now, and the second one is a MEMORY:
    /// `weighInAnswered` is the date whose nudge the athlete has already dealt
    /// with. It is set when the InBody form saves — the one moment this app can
    /// be sure the question was answered — and it is keyed by DATE, so tomorrow
    /// morning's weigh-in asks again, which is the entire point of the banner.
    private(set) var weighInPending = false

    /// `UserDefaults`, not the store: this is a fact about this phone's UI, not
    /// about the athlete's training, and a row for it would be a row to sync,
    /// to mirror and to reconcile for something that is forgotten at midnight.
    private static let weighInAnsweredKey = "onyx.weighIn.answeredDate"

    /// Has today's nudge already been dealt with?
    private var weighInAnswered: Bool {
        UserDefaults.standard.string(forKey: Self.weighInAnsweredKey) == today
    }

    /// The athlete answered the weigh-in question for today.
    ///
    /// Called by the InBody form when a save LANDS, which is the only event
    /// that means "asked and answered" without guessing. Opening the sheet does
    /// not count — a form opened and abandoned has answered nothing — and
    /// neither does the presence of the two columns, for the reason
    /// `weighInPending` gives above.
    ///
    /// ponytail: a phone whose scale reports neither muscle nor water still
    /// sees the banner once a day until the form is saved once for that day.
    /// That is the banner doing its job, not the defect — the defect was seeing
    /// it again five minutes after answering it.
    func answerWeighIn() {
        UserDefaults.standard.set(today, forKey: Self.weighInAnsweredKey)
        weighInPending = false
    }

    /// Bumped by a banner that wants the InBody sheet. Pulse owns that sheet;
    /// Today only knows it wants it open, and switching tab is the shell's job.
    private(set) var scaleEntryRequests = 0

    /// Lifts that have earned a load bump, and the day they were graded for.
    ///
    /// ── PUBLISHED, NOT COMPUTED, HERE ───────────────────────────────────────
    /// The answer depends on the schedule (which day key is today, after
    /// overrides and the permanent layout), and that resolution already exists
    /// in exactly one place — `WorkoutWeek.build`. Re-deriving it here would be
    /// a second copy of the rule that decides what day it is, which is the one
    /// thing this app has already been bitten by (a swapped session read off
    /// the weekday). So whoever has the day key in hand publishes, and every
    /// surface that shows an alert reads the same array.
    ///
    /// In-app only (decision 10): nothing here schedules a notification.
    ///
    /// STAGED: the session-open banner and the exercise chip are Track U's
    /// (waves U1, U2). The Workout tab's own card still computes its own list
    /// in `WorkoutWeek.build`; it moves onto this array when U1 lands.
    private(set) var progressionAlerts: [ProgressionQueue.Alert] = []
    private(set) var progressionDayKey: String?

    /// Which tab is showing, as `SignedInTabs.Tab.rawValue`. Empty means
    /// "whatever the shell opens on".
    ///
    /// ── WHY THE SHELL DOES NOT OWN ITS OWN SELECTION ────────────────────────
    /// It did, as `@State`, and that put it UNDER `OnyxApp`'s `.id(themeJSON)`
    /// — so committing a theme dropped the user on the launch tab. Picking a
    /// colour in Settings and being answered with the dashboard reads as the
    /// app restarting, and it made the Appearance screen a way of DELAYING that
    /// eviction by one tap rather than avoiding it.
    ///
    /// This object is `@State` on the `App` struct itself, which is above the
    /// `.id`, so it is the one place in the app where a value survives a theme
    /// change. A raw `String` rather than the enum because `Tab` belongs to the
    /// shell and nothing here should have an opinion about which tabs exist.
    var selectedTab: String = ""

    /// Whether the Train tab is holding a live `LoggerModel` right now.
    ///
    /// ── WHY SETTINGS OF ALL SCREENS NEEDS TO KNOW ───────────────────────────
    /// A theme write changes `@AppStorage(OnyxTheme.key)`, which is what
    /// `OnyxApp.swift`'s `.id(themeJSON)` hangs off — and re-identifying the
    /// root throws away every `@State` under it, including the session the
    /// Train tab keeps at `WorkoutTabView.swift:44`. No SET would be lost (they
    /// are in the event log the moment they are logged), but the clock, the rest
    /// timer, the deck cursor and the Live Activity's link to this model all go,
    /// and the Mini Player falls back to "Resume workout" mid-workout. So the
    /// Appearance section refuses to write while this is true.
    ///
    /// Published rather than computed, for the same reason `progressionAlerts`
    /// is: the fact lives in the view that owns the model, and re-deriving it
    /// here would be a second copy of a rule that has bitten this app before.
    private(set) var isSessionLive = false

    /// Bumped when a rescore cascade COMPLETES — never per day, never per
    /// commit.
    ///
    /// ── WHAT IT IS FOR ──────────────────────────────────────────────────────
    /// Four screens load their data once and never look again: Trends
    /// (`guard sessions == nil`), History, the week grid and Body Trends. That
    /// was correct while the only thing that could change under them was a
    /// sync — which they were about to be replaced by anyway. It stopped being
    /// correct the moment a session became editable from inside the app: lower
    /// a set on the summary card, come back to Trends, and the chart is still
    /// drawing the old tonnage with no way to ask it not to.
    ///
    /// So they key a `.task(id:)` on this. It moves once per cascade, which is
    /// the only moment at which every score the edit touched agrees — publish
    /// per day and History would re-read the whole ledger forty-nine times for
    /// one correction.
    private(set) var rescoreGeneration = 0
    /// A run is going. A thin hint (a hairline, a caption) and nothing more —
    /// no screen blocks on it, because the numbers on display are the OLD
    /// consistent ones until the generation moves.
    private(set) var isRescoring = false

    /// The cascade, off the main actor and coalesced. Nil while signed out.
    private var rescoreQueue: RescoreQueue?

    /// Rewrite every stored score an edit on `date` can move.
    ///
    /// The ONE entry point. Every editing surface calls this rather than
    /// touching `AppDatabase.rescore` directly, so there is exactly one place
    /// that decides how a cascade is scheduled and one place that publishes the
    /// generation when it lands.
    /// Returns whether the request was ACCEPTED — false while signed out,
    /// when there is no queue to take it.
    ///
    /// The caller that has state to clear (the session editor's dirty flag)
    /// needs to know: clearing it on a request that went nowhere loses the
    /// cascade AND the only record that one was owed, and the chevron can then
    /// never ask again.
    @discardableResult
    func rescore(from date: String, reason: Rescore.Reason) -> Bool {
        guard let rescoreQueue else { return false }
        isRescoring = true
        Task { await rescoreQueue.request(from: date, reason: reason) }
        return true
    }

    /// Re-window a night, then rewrite every score it can move (E2).
    ///
    /// The ONE place a sleep edit runs from: `HealthSync.editSleepWindow` reads
    /// the samples and the overnight HRV inside the new window and writes the
    /// row under the sleep sentinel; the cascade is scheduled here, through
    /// `rescore(from:reason:)`, like every other edit. A fresh `HealthSync` is
    /// cheap — an actor holding three references — and the coordinator's own
    /// is private to it on purpose.
    /// Returns whether the edit was ACCEPTED — false while signed out, when
    /// there is no user to write under — for the same reason `rescore` does:
    /// a sheet that clears its dirty state on a request that went nowhere has
    /// lost the edit and the only record that one was owed.
    @discardableResult
    func editSleepWindow(date: String, start: Date, end: Date, onset: Date? = nil) async throws -> Bool {
        guard case .signedIn(let userID) = auth else { return false }
        let userId = OnyxJSON.canonicalUserID(userID)
        let health = HealthSync(database: database, reader: Self.healthReader, userId: userId)
        try await health.editSleepWindow(date: date, start: start, end: end, onset: onset)
        return rescore(from: date, reason: .sleepEdit)
    }

    /// Sleep v2 (W3, 6.0.0) moved every stored sleep score a bedtime can
    /// reach — regularity reads `start_time`, which every night has — so the
    /// first launch on this build rewrites the whole history once. The flag is
    /// set when THAT run completes, not when it is asked for: a launch killed
    /// mid-cascade owes the rest, and rewriting a day twice costs a read while
    /// leaving one unrewritten costs a wrong number nobody will look at again.
    /// A store with nothing scored (a fresh install) is done by definition.
    private static let sleepV2RescoredKey = "onyx.rescore.sleepV2.done"

    private func requestMigrationRescore(_ queue: RescoreQueue, userId: String) {
        guard !UserDefaults.standard.bool(forKey: Self.sleepV2RescoredKey) else { return }
        guard let first = try? database.earliestScoredDate(userId: userId) else {
            UserDefaults.standard.set(true, forKey: Self.sleepV2RescoredKey)
            return
        }
        isRescoring = true
        let today = LogicalDay.today()
        Task { await queue.request(from: first, through: today, reason: .migration) }
    }

    /// Publish the queue for a day. Passing a different `dayKey` replaces the
    /// list rather than merging: an alert is about a lift ON a routine day, and
    /// two days' alerts in one array is how the banner starts naming a lift
    /// today's session does not contain.
    func publishProgression(_ alerts: [ProgressionQueue.Alert], for dayKey: String?) {
        progressionAlerts = alerts
        progressionDayKey = dayKey
    }

    /// The Train tab, saying whether it is holding a live session. See
    /// `isSessionLive`.
    func publishSessionLive(_ live: Bool) { isSessionLive = live }

    /// The theme changed: tell the two processes that do not share this one's
    /// memory.
    ///
    /// Called AFTER `OnyxTheme.save`, both of them: the widget extension reads
    /// the App Group defaults the save has just written, and the watch bridge
    /// attaches `OnyxTheme.current.spec`, which the save is what sets.
    /// `reloadAllTimelines()` needs no entitlement and is a no-op with no
    /// widgets installed, so it is called unguarded; `pushWatchContext` is a
    /// no-op signed out.
    func themeDidChange() {
        WidgetCenter.shared.reloadAllTimelines()
        if case .signedIn(let userID) = auth { pushWatchContext(userID: userID) }
    }

    #if DEBUG
    /// The shot loop: the banner's state is a row in a store the harness never
    /// signs in to, so the flag is set directly rather than seeded.
    func seedWeighInPendingForPreview() { weighInPending = true }
    #endif

    /// Ask Pulse to open the InBody form. The caller switches to the tab.
    public func requestScaleEntry() { scaleEntryRequests += 1 }

    private var weighInTask: Task<Void, Never>?
    #if ONYX_ADP
    private var observers: HealthObservers?
    #endif

    private var authTask: Task<Void, Never>?
    private var midnight: Task<Void, Never>?
    /// The commit observer, held for the life of the app (GRDB stops observing
    /// when it is deallocated). Untyped so the app target need not import GRDB.
    private var commitObserver: AnyObject?
    private var widgetReload: Task<Void, Never>?

    public init(database: AppDatabase, supabase: SupabaseClient) {
        self.database = database
        self.supabase = supabase
    }

    /// Build the real environment. Throws only for a configuration problem the
    /// user can fix.
    public static func live() throws -> AppEnvironment {
        let config = try SupabaseConfig.fromBundle()
        // BEFORE the store is opened, and ONLY here. `sharedFolder()` is pure
        // path resolution now and the widget extension calls it too; a
        // migration running inside an extension could rename the database out
        // from under a running app. Idempotent, so a second launch is a no-op.
        AppDatabase.adoptLegacyStores()
        return AppEnvironment(
            database: try AppDatabase.onDisk(folderURL: AppDatabase.sharedFolder()),
            supabase: OnyxSupabase.makeClient(config: config)
        )
    }

    /// Resolve the persisted session, then follow auth changes for the life of
    /// the app.
    ///
    /// The stream is the only writer of `auth`. Sign-in and sign-out below do
    /// not set it themselves — they perform the action and let the stream report
    /// what actually happened, so the UI can never show a state the auth client
    /// disagrees with.
    public func start() {
        guard authTask == nil else { return }
        startMidnightClock()
        // Every local write — a set, a day edit, a mirror pull — reloads the
        // widgets, debounced: a pull commits per table and a session logs a
        // set every minute, and each reload is a full snapshot build.
        commitObserver = database.onCommit { [weak self] in
            Task { @MainActor in self?.scheduleWidgetReload() }
        }
        // The watch link. It takes its own `onCommit` rather than sharing this
        // one: this observer is debounced for the widget reload (a full snapshot
        // build), and holding a set back for two seconds before handing it to a
        // watch that is sitting six inches away is the wrong trade for a
        // transfer that costs nothing.
        watchBridge.start()
        authTask = Task { [weak self] in
            guard let self else { return }
            #if DEBUG
            // `ONYX_SESSION_FILE=<path>` in the launch environment
            // (`SIMCTL_CHILD_ONYX_SESSION_FILE` through simctl): a JSON file
            // holding a `refresh_token`, so the backfill gate can sign a fresh
            // simulator in without a password and without a token in argv. The
            // token is single-use and rotates, so the file is dead once read.
            if let path = ProcessInfo.processInfo.environment["ONYX_SESSION_FILE"] {
                // After the stream below is subscribed, so the sign-in arrives
                // as a live event rather than being missed by `initialSession`.
                Task { [supabase] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let data = FileManager.default.contents(atPath: path),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let access = json["access_token"] as? String,
                          let refresh = json["refresh_token"] as? String
                    else { NSLog("onyx-session: could not read %@", path); return }
                    do {
                        _ = try await supabase.auth.setSession(accessToken: access, refreshToken: refresh)
                        // `stored` is the tell: an UNSIGNED simulator build cannot
                        // write the Keychain, the session never persists, and
                        // every pull comes back `[]` under RLS with a 200.
                        NSLog("onyx-session: signed in from file; stored=%@", supabase.auth.currentSession == nil ? "nil" : "yes")
                    } catch {
                        NSLog("onyx-session: refresh failed: %@", String(describing: error))
                    }
                }
            }
            #endif
            for await (event, session) in self.supabase.auth.authStateChanges {
                guard event != .initialSession || session != nil else {
                    self.auth = .signedOut
                    continue
                }
                // ── THE ACCOUNT-SWITCH DOOR (W11) ───────────────────────────
                // A sign-in with no sign-out before it used to inherit the
                // previous account's store until its own sync overwrote it,
                // and `AppDatabase.sharedFolder()` has no user component — so
                // every reader answered from the wrong person's rows in the
                // meantime, and the widget kept drawing them. The erase runs
                // HERE, before `auth` flips and before a coordinator exists,
                // so no view and no worker reads across the boundary; it is
                // the same `eraseLocalData()` sign-out runs. A store that
                // cannot be cleared is a store this account may not use: the
                // session is revoked and the loop hears the sign-out.
                if let session, !self.prepareStore(for: session.user.id) {
                    try? await self.supabase.auth.signOut()
                    continue
                }
                self.auth = session.map { .signedIn(userID: $0.user.id) } ?? .signedOut
                if case .signedIn(let userID) = self.auth {
                    self.startSync(userID: userID)
                    self.loadRole(userID: userID)
                    // The watch cannot sign in — Wave 10 keeps every credential
                    // on the phone — so this is the ONLY way it learns whose
                    // data it is holding and what the plan says today is.
                    self.pushWatchContext(userID: userID)
                }
                if case .signedOut = self.auth { self.role = nil }
            }
        }
    }

    /// Every foreground, and the first resolved sign-in. Cheap when there is
    /// nothing new: HealthKit answers an already-granted authorization without
    /// showing anything, and `ingest` rewrites the same two days' rows.
    ///
    /// ── WHY FOREGROUND AND NOT ONCE AT LAUNCH ───────────────────────────────
    /// A phone does not relaunch this app for days. Steps and active energy
    /// accrue all day, and `HealthSync` computes the day key when it is CALLED,
    /// so a process alive past midnight that only ever synced once would never
    /// create the new day's row at all — the tabs would keep re-reading a GRDB
    /// nothing had written to, and pull-to-refresh would refresh nothing.
    public func refreshHealth() {
        // Through `syncNow`, not straight to the coordinator: a foreground
        // sync writes today's rows, and one that does so with no hairline and
        // no timestamp leaves the caption reading "Synced 40m ago" over data
        // that landed a second ago. Fire-and-forget is still right HERE — the
        // scene phase is not waiting on an answer.
        Task { await syncNow(reason: .foreground) }
    }

    /// One sync, awaited — the shape `.refreshable` needs.
    ///
    /// `.refreshable` holds the spinner for exactly as long as its body runs,
    /// so something has to be awaitable end to end. The coordinator is: a call
    /// while one is running joins the run that will include it, and the status
    /// is stamped only when that run is genuinely done. Overlapping calls are
    /// fine — `SyncStatus` counts them.
    func syncNow(reason: SyncReason) async {
        guard case .signedIn = auth, let coordinator else { return }
        sync.begin()
        var failure: String?
        do { try await coordinator.syncNow(reason: reason) } catch { failure = String(describing: error) }
        // A sign-out during the await dropped the coordinator — and a sign-in
        // after it built a new one, so identity, not presence. Stamping
        // `lastSync` for the abandoned run would leave the next user's Today
        // saying "Synced just now" about a sync that was theirs to begin with.
        guard case .signedIn = auth, self.coordinator === coordinator else {
            sync.finish(error: "Signed out before the sync finished.")
            return
        }
        sync.finish(error: failure)
        // Read and cleared inside the actor, so two overlapping syncs cannot
        // announce the same three walks twice. Nil on almost every pass.
        if let ingest = await coordinator.takeCardioIngest() { sync.noticeCardio(ingest) }
    }

    /// Build the coordinator for this user and run the first sync.
    ///
    /// ── WHY IT HANGS OFF AUTH ───────────────────────────────────────────────
    /// Every row the sync writes is keyed by `user_id`, so there is nothing to
    /// sync before a user is resolved. The auth stream also re-emits on every
    /// token refresh; an existing coordinator is what absorbs that.
    ///
    /// The HealthKit read is inside the coordinator now (§7.4): it runs first,
    /// before the push, so today's steps are never left in the outbox under a
    /// "Synced just now" caption. A declined permission is silent — absent
    /// metrics render as "—" downstream.
    private func startSync(userID: UUID) {
        guard coordinator == nil else { return }
        let userId = OnyxJSON.canonicalUserID(userID)
        let coordinator = SyncCoordinator(
            database: database, client: supabase, userId: userId,
            health: HealthSync(database: database, reader: Self.healthReader, userId: userId)
        )
        self.coordinator = coordinator
        // ── WHY IT HANGS OFF AUTH, LIKE THE COORDINATOR ─────────────────────
        // Every score it writes is keyed by `user_id`, and a queue that
        // outlived a sign-out would rewrite the previous user's days into the
        // next one's store.
        let queue = RescoreQueue(database: database, userId: userId) { [weak self] run in
            await MainActor.run {
                guard let self else { return }
                if run.reason == .migration, !run.hasMore, run.failed == 0 {
                    UserDefaults.standard.set(true, forKey: Self.sleepV2RescoredKey)
                }
                self.rescoreGeneration &+= 1
                // `hasMore` is the queue's own answer, not a second read: two
                // passes of one logical cascade must not flicker the hint off
                // between them.
                self.isRescoring = run.hasMore
                NSLog(
                    "onyx-rescore: %@ %@…%@ wrote %d, failed %d",
                    run.reason.rawValue, run.from, run.through, run.written, run.failed
                )
            }
        }
        rescoreQueue = queue
        requestMigrationRescore(queue, userId: userId)
        startWeighInWatch()
        let targets = TargetResolver(database: database, userId: userId)
        targets.start()
        self.targets = targets
        Task {
            // A user this device has never synced gets the whole history
            // behind the sheet; everyone else gets the ordinary launch sync.
            if (try? await coordinator.needsBackfill()) == true {
                await self.runBackfill(coordinator, model: BackfillModel())
            } else {
                await self.syncNow(reason: .launch)
            }
            // ── ONBOARDING GOES AFTER A PULL THAT LANDED (W5) ───────────────
            // "Has this account been set up" is a question about ROWS, and on a
            // new device the rows have not arrived yet.
            //
            // "After the pull" is NOT enough on its own, because a pull that
            // fails does not say so: `MirrorPuller.refresh` collects every
            // per-table error into its report and returns normally, and
            // `runBackfill` then clears its sheet with no error on screen. A
            // reinstall on a dead network therefore reaches this line with an
            // empty store and an account that has years in it — and the seed's
            // `user_goals` upsert conflicts on `user_id`, so it would merge
            // onboarding's defaults straight over the real row.
            //
            // So the offer is gated on the SYNC LEDGER, which is stamped only
            // by a table that actually landed, and `seedAccount` asks the
            // question again inside the transaction that would do the writing.
            await self.offerOnboardingIfNeeded(userId: userId, coordinator: coordinator)
            // A no-op if sign-out stopped this coordinator meanwhile.
            await coordinator.startRealtime(client: supabase)
            #if ONYX_ADP
            self.startObservers()
            #endif
        }
    }

    /// The cardio bouts Apple Health holds for one logical day.
    ///
    /// ── WHY IT IS HERE AND NOT ON `HealthSync` ──────────────────────────────
    /// `HealthSync` owns the reader for the daily ingest, and it is built INSIDE
    /// `SyncCoordinator`, which is built inside `startSync`, which only runs once
    /// a user has resolved. The cardio sheet is a read with no ingest, no
    /// watermark and no outbox behind it, and threading it down through two
    /// actors that exist for the write path would put the sheet's availability
    /// at the mercy of whether a sync has started yet.
    ///
    /// `healthReader` is already the app's one answer to "which reader" — the
    /// `ONYX_NO_HEALTH` gate included, which is what keeps a shot of this screen
    /// from hanging on a permission sheet nobody can tap.
    ///
    /// Failure is an empty list, not a throw: Health being unavailable, denied
    /// or empty are three states a person cannot act on differently, and all
    /// three mean "there is nothing to import, type it in".
    func cardioBouts(on iso: String) async -> [WorkoutSample] {
        guard let day = LogicalDay.date(fromISO: iso) else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        let found = (try? await Self.healthReader.workouts(start: start, end: end)) ?? []
        return found.filter { !$0.isLifting && $0.cardioKind != nil }
    }

    /// Put the onboarding flow up, if this account has never been set up.
    ///
    /// Three conditions, and all three are load-bearing:
    ///
    /// 1. **The backfill sheet is down.** Its failure path leaves `backfill`
    ///    non-nil, and two `fullScreenCover`s racing on one view means either
    ///    the error is buried under a flow nobody can dismiss, or the flow is
    ///    silently dropped and reappears later over a populated account.
    /// 2. **A pull actually landed.** `needsBackfill` reads the sync ledger,
    ///    which is stamped per table only on success — so it is still `true`
    ///    after a failure that reported nothing, and the offer is withheld.
    ///    This is the check that keeps a reinstall on a dead network from being
    ///    offered a fresh start on an account full of history.
    /// 3. **The store has no evidence of a person.** `needsOnboarding` is
    ///    deliberately conservative (see `AccountSeed`) and now counts food,
    ///    water and weigh-ins as well as training.
    ///
    /// A throw is NOT an offer. A store that will not open is a reason to show
    /// the app, not a reason to re-seed an account that may be full of data.
    func offerOnboardingIfNeeded(userId: String, coordinator: SyncCoordinator) async {
        guard onboarding == nil, backfill == nil else { return }
        guard (try? await coordinator.needsBackfill()) == false else { return }
        guard (try? database.needsOnboarding(userId: userId)) == true else { return }
        onboarding = OnboardingModel(database: database, userId: userId)
    }

    /// The flow finished (or was dismissed after seeding). One-way.
    func finishOnboarding() {
        onboarding = nil
        // The seed queued nine tables' worth of rows; push them now rather than
        // waiting for the next foreground, so a new account's first sight of
        // the Sync screen is not a backlog.
        Task { await syncNow(reason: .foreground) }
    }

    /// Ask for Apple Health, from onboarding.
    ///
    /// ── IT IS AN OFFER AND IT STAYS AN OFFER ────────────────────────────────
    /// Guideline 5.1.1 is explicit that data useful to a non-essential feature
    /// must be optional, and Onyx logs sets perfectly well with no Health access
    /// at all. So the step this is called from has a "Not now" that is exactly
    /// as prominent as the button, and the answer is not recorded anywhere:
    /// iOS owns the permission and the app asks it, never a flag of its own.
    ///
    /// The returned `Bool` is only "did the sheet complete" — HealthKit
    /// deliberately does not report what was granted for READ types, so an
    /// onboarding screen that claimed "connected" would be guessing.
    @discardableResult
    func requestHealthAccess() async -> Bool {
        let reader = Self.healthReader
        guard reader.isAvailable else { return false }
        return (try? await reader.requestAuthorization(read: HealthCatalogue.readTypes)) ?? false
    }

    /// Resting energy over a window, in kilocalories.
    ///
    /// ── WHY THE CARDIO SHEET WANTS IT ───────────────────────────────────────
    /// A bout carries its ACTIVE energy — the cost of the walk above sitting
    /// still. Apple's Fitness app, every treadmill console and every other app a
    /// person compares against report the TOTAL, which is active plus the
    /// resting burn the same forty minutes would have cost anyway. Logging 218
    /// kcal for a walk the watch called 340 is the kind of discrepancy that
    /// reads as a broken importer.
    ///
    /// So the sheet offers both, filled and editable, and `cardio_logs` has
    /// held `active_kcal` and `total_kcal` as separate columns all along.
    ///
    /// Basal is authorised (`HealthCatalogue.extraReadTypes`) but nothing
    /// ingests it, and until W5 `HealthKitReader.unit(for:)` had no case for it
    /// — it fell through to `.count()` and returned a number that was not
    /// kilocalories and did not say so.
    func restingEnergy(from start: Date, to end: Date) async -> Double? {
        guard end > start else { return nil }
        return try? await Self.healthReader.quantity(
            "HKQuantityTypeIdentifierBasalEnergyBurned", reduce: .sum, start: start, end: end
        )
    }

    /// The most recent body reading Apple Health holds, for the InBody sheet.
    ///
    /// One call for the four figures rather than four, because the sheet wants
    /// them together or not at all — a prefill that filled weight and left body
    /// fat blank would read as "Health has no body fat" when it means "the read
    /// half-failed". Each is independently optional inside the answer.
    ///
    /// The window is ninety days back. A `.latest` statistics query still needs
    /// one, and a body reading older than a quarter is not a prefill, it is a
    /// number that will be wrong in a way the user has to notice.
    func latestHealthBody(now: Date = Date(), days: Int = 90) async -> HealthBodyReading {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let reader = Self.healthReader
        func read(_ identifier: String) async -> Double? {
            try? await reader.quantity(identifier, reduce: .latest, start: start, end: now)
        }
        return HealthBodyReading(
            weightKg: await read("HKQuantityTypeIdentifierBodyMass"),
            bmi: await read("HKQuantityTypeIdentifierBodyMassIndex"),
            // HealthKit hands percentages back as a 0–1 fraction; every screen
            // in this app is in whole percent. `HealthCatalogue` scales the same
            // read by 100 for the same reason.
            bodyFatPct: await read("HKQuantityTypeIdentifierBodyFatPercentage").map { $0 * 100 },
            // Lean body mass is FAT-FREE mass, not muscle mass. `HealthMetrics`
            // and `DailyLogIngest` both refuse to put it in `muscle_mass_kg`
            // and this must not be the one place that does.
            fatFreeMassKg: await read("HKQuantityTypeIdentifierLeanBodyMass")
        )
    }

    /// `ONYX_NO_HEALTH=1` (DEBUG launch environment) reads no HealthKit at
    /// all, so the permission sheet — which nothing on a simulator can tap —
    /// never covers the screen a gate is photographing.
    private static var healthReader: any HealthReading {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ONYX_NO_HEALTH"] != nil { return NoHealth() }
        #endif
        return HealthKitReader()
    }

    /// Settings' "Re-run backfill": the same run, the same sheet.
    func rerunBackfill() {
        guard let coordinator, backfill == nil else { return }
        Task { await runBackfill(coordinator, model: BackfillModel()) }
    }

    /// The sheet's Retry, on the sheet's own model so the rows stay put.
    func retryBackfill(_ model: BackfillModel) {
        guard let coordinator else { return }
        model.error = nil
        Task { await runBackfill(coordinator, model: model) }
    }

    /// One backfill behind the sheet. Success shows the finished state for a
    /// beat, then drops the sheet; failure keeps it up with Retry.
    private func runBackfill(_ coordinator: SyncCoordinator, model: BackfillModel) async {
        backfill = model
        sync.begin()
        var failure: String?
        do {
            try await coordinator.backfill { progress in
                Task { @MainActor in model.progress = progress }
            }
        } catch {
            failure = String(describing: error)
        }
        guard case .signedIn = auth, self.coordinator === coordinator else {
            sync.finish(error: "Signed out before the sync finished.")
            backfill = nil
            return
        }
        sync.finish(error: failure)
        if let failure {
            model.error = failure
            return
        }
        try? await Task.sleep(for: .milliseconds(800))
        if backfill === model { backfill = nil }
    }

    #if ONYX_ADP
    /// Background delivery (Gate 0). A note from HealthKit is a `.healthKit`
    /// sync through the coordinator's queue, like every other trigger.
    private func startObservers() {
        guard observers == nil else { return }
        let observers = HealthObservers { [weak self] _ in
            Task { @MainActor in await self?.syncNow(reason: .healthKit) }
        }
        observers.start()
        self.observers = observers
    }
    #endif

    public func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }

    /// Create an account. Returns `true` when the email still needs confirming.
    ///
    /// Email confirmation is ON in the project, so the usual result is a user
    /// with no session: `signUp` returns the user and `session` is nil until
    /// the link is followed. The screen has to say so — a sign-up that appears
    /// to succeed and then leaves the user on the sign-in form reads as a bug.
    /// When confirmation is off (or the address is already confirmed) a session
    /// arrives immediately, `authStateChanges` fires, and `RootView` moves on
    /// its own; `false` says that happened.
    @discardableResult
    public func signUp(email: String, password: String) async throws -> Bool {
        let response = try await supabase.auth.signUp(email: email, password: password)
        return response.session == nil
    }

    /// Delete the account, then sign out — in that order, and both halves.
    ///
    /// The RPC removes every row and the `auth.users` record itself. The JWT
    /// already in memory stays VALID until it expires, so a client that skipped
    /// the sign-out would keep making authorised requests as a user that no
    /// longer exists. `signOut()` is what makes the deletion real on this
    /// device: it revokes the session and erases the local store.
    ///
    /// The sign-out is not conditional on the RPC succeeding — see below. It is
    /// conditional on it, deliberately: signing out after a FAILED delete would
    /// leave the user with no session, no local data and an account still on
    /// the server, and no way to retry from this phone.
    public func deleteAccount() async throws {
        try await supabase.rpc("delete_my_account").execute()
        await signOut()
    }

    /// Erase a store that belongs to another account, before this one reads
    /// it. `AppDatabase.prepareForUser` decides; this surfaces what it found
    /// exactly as `signOut()` surfaces its own unsynced count, and redraws the
    /// widget against the now-empty store the same way. False when the erase
    /// itself failed — the one case a sign-in must not proceed.
    private func prepareStore(for userID: UUID) -> Bool {
        let userId = OnyxJSON.canonicalUserID(userID)
        do {
            guard let discarded = try database.prepareForUser(userId) else { return true }
            NSLog("onyx-session: the store belonged to another account; erased, %d unsynced", discarded)
            if discarded > 0 {
                startupError = "Signed in to a different account. \(discarded) change\(discarded == 1 ? "" : "s")"
                    + " from the previous account had not reached the server and could not be kept."
            }
            widgetReload?.cancel()
            widgetReload = nil
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            startupError = "Signed in to a different account, but the previous account's data could not be cleared."
            return false
        }
    }

    /// One read of `profiles.role`, from the mirror rather than the network.
    /// Silent on failure: the property stays nil and `isAdmin` stays false.
    private func loadRole(userID: UUID) {
        let id = OnyxJSON.canonicalUserID(userID)
        Task { [database] in
            let value = try? database.role(userId: id)
            await MainActor.run { self.role = value }
        }
    }

    /// ── DRAIN, THEN ERASE. IN THAT ORDER, AND NEVER ONLY THE FIRST HALF ─────
    ///
    /// Sign-out used to stop the workers and leave every local row where it
    /// was. Two things were wrong with that. Anything logged since the last
    /// sync was silently thrown away — it sat in the outbox of a store nobody
    /// would open again. And the widget reads `AppDatabase.sharedFolder()`
    /// directly, with no session and no auth check at all, so it went on
    /// drawing the previous user's week on the home screen of a signed-out
    /// phone, and would have gone on drawing it to the NEXT user.
    ///
    /// The order below is the whole of it:
    ///
    ///  1. Push what is queued, while the session is still valid — bounded, so
    ///     a dead network cannot trap someone on this screen.
    ///  2. Stop every worker, AWAITED, so nothing writes after step 4.
    ///  3. Revoke the session.
    ///  4. Erase the local store.
    ///  5. Redraw the widget immediately, against the now-empty store.
    ///
    /// A failure anywhere in 1–3 must not skip 4: a user who cannot reach the
    /// network still gets to sign out, and still gets their data off the phone.
    public func signOut() async {
        // 1. The last push. `stop()` below awaits the coordinator's own task,
        //    which is what actually closes the race with the erase.
        if let coordinator {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { try? await coordinator.drainOutbox() }
                group.addTask { try? await Task.sleep(for: .seconds(5)) }
                await group.next()
                group.cancelAll()
            }
        }

        // 2. Every worker down, each one awaited. Dropping a reference does not
        //    stop a drain: it runs in an unstructured task that retains the
        //    actor, so it would go on writing the PREVIOUS user's days into the
        //    store the next one is signing in to, queueing upserts their RLS
        //    will reject and bumping a generation that belongs to somebody else.
        if let coordinator {
            self.coordinator = nil
            await coordinator.stop()
        }
        #if ONYX_ADP
        observers?.stop()
        observers = nil
        #endif
        backfill = nil
        if let rescoreQueue {
            self.rescoreQueue = nil
            await rescoreQueue.stop()
        }
        isRescoring = false
        targets?.stop()
        targets = nil
        // The next account's blocks are not this one's. Left behind, a cut
        // would tint a signed-out launch and the first screens of whoever
        // signs in next. `isSessionLive` is cleared first: signing out ends
        // the session by definition, and `publishPhase` declines while one is
        // up — which would leave the previous account's block behind.
        isSessionLive = false
        publishPhase(nil)
        weighInTask?.cancel()
        weighInTask = nil
        weighInPending = false

        // 3. A failed sign-out must still clear local state, or the user is
        //    stuck on a screen with no way forward.
        try? await supabase.auth.signOut()

        // 4. Not optional and not deferred. This is the step that makes the
        //    phone stop holding an account the user has left.
        //
        //    ── AND IT RUNS EVEN IF STEP 1 DID NOT FINISH ───────────────────
        //    A drain that timed out means work is about to be discarded, and
        //    the alternative — keeping it — is leaving one user's training log
        //    on a signed-out device for the next person to open. Security wins
        //    that trade. What it does not get to do is win it QUIETLY: the
        //    count is read before the erase and reported after it, so "I lost
        //    three sets" is something the user is told rather than something
        //    they discover.
        let unsynced = (try? database.outboxPendingCount()) ?? 0
        do {
            try database.eraseLocalData()
            if unsynced > 0 {
                startupError = "Signed out. \(unsynced) change\(unsynced == 1 ? "" : "s") had not"
                    + " reached the server yet and could not be kept."
            }
        } catch {
            startupError = "Signed out, but some local data could not be cleared."
        }

        auth = .signedOut

        // 5. NOT `scheduleWidgetReload()`. That debounces two seconds against a
        //    commit storm, and the storm here is the erase itself — the user
        //    would watch a stale week sit on their home screen for two seconds
        //    after signing out. Cancel the pending one and redraw now.
        widgetReload?.cancel()
        widgetReload = nil
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - The weigh-in

    /// One observation over today's `body_composition` row. Restarted by
    /// `rollDay`, because the row it watches is the DAY's.
    private func startWeighInWatch() {
        weighInTask?.cancel()
        guard case .signedIn(let userID) = auth else {
            weighInPending = false
            return
        }
        let userId = OnyxJSON.canonicalUserID(userID)
        let date = today
        weighInTask = Task { [database] in
            do {
                for try await row in database.bodyCompositionStream(userId: userId, date: date) {
                    if Task.isCancelled { return }
                    // A weight with no muscle AND no water is a scale that
                    // synced through Health; either one present means the
                    // InBody numbers were entered and there is nothing to ask.
                    //
                    // And the memory wins over the row: once the form has saved
                    // for this date the question has been answered, whatever a
                    // later sync does to the two columns.
                    self.weighInPending = !self.weighInAnswered
                        && row != nil && row?.muscleMassKg == nil && row?.waterPct == nil
                }
            } catch {
                // A dropped observation is not worth a banner of its own — the
                // next day tick restarts it.
                self.weighInPending = false
            }
        }
    }

    // MARK: - Midnight

    /// Republish `today` at every local 00:00, and whenever the system says
    /// the day changed under us — a timezone crossing, a clock correction, or
    /// a wake from a suspension that slept through the deadline.
    ///
    /// ── WHY BOTH A SLEEP AND A NOTIFICATION ─────────────────────────────────
    /// `NSCalendarDayChanged` is the platform's own midnight, but it is only
    /// delivered while the process is running and not always promptly on a
    /// return from suspension. The sleep is exact when the app is awake; the
    /// notification catches the cases the sleep cannot see. `rollDay` is
    /// idempotent — it compares before publishing — so the two racing is a
    /// no-op, not a double tick.
    private func startMidnightClock() {
        guard midnight == nil else { return }
        midnight = Task { [weak self] in
            let center = NotificationCenter.default
            let days = Task { [weak self] in
                for await _ in center.notifications(named: .NSCalendarDayChanged) {
                    self?.rollDay()
                }
            }
            defer { days.cancel() }
            while !Task.isCancelled {
                let now = Date()
                let calendar = Calendar.current
                // The next 00:00 in the device's own calendar — DST-aware, so
                // the 23- and 25-hour nights land on the right instant.
                let next = calendar.nextDate(
                    after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime
                ) ?? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
                // Continuous clock: keeps counting through a suspension, so a
                // deadline that passed while asleep fires on the way back in.
                try? await Task.sleep(until: .now + .seconds(next.timeIntervalSince(now) + 0.5), clock: .continuous)
                self?.rollDay()
            }
        }
    }

    /// Hand the watch the resolved plan.
    ///
    /// Cheap, idempotent and lossy by design: `updateApplicationContext` keeps
    /// exactly one slot, so a second call before the first is delivered simply
    /// replaces it — which is the correct behaviour for a value where only the
    /// newest has ever been wanted.
    private func pushWatchContext(userID: UUID) {
        let userId = OnyxJSON.canonicalUserID(userID)
        guard let schedule = try? database.scheduleContext(userId: userId, today: today) else { return }
        // BEFORE the send, not after: the bridge attaches
        // `OnyxTheme.current.spec`, which is the pick plus the block's mood
        // offset. Publishing afterwards would hand the watch one phase's
        // palette every time the block rolled, and only correct it on the next
        // push — which on a quiet day is the following midnight.
        publishPhase(schedule)
        watchBridge.send(userId: userId, today: today, schedule: schedule)
    }

    /// Park the training block the whole palette reads itself through
    /// (`OnyxTheme.phaseKey`), and repaint if it moved.
    ///
    /// ── WHY THIS IS A DEFAULTS WRITE AND NOT A PROPERTY ─────────────────────
    /// Three processes need the answer and only one of them is this one: the
    /// app root hangs its `.id` off the key, the widget extension reads it in
    /// `OnyxProvider.theme()`, and the watch is sent the already-reacted spec.
    /// A published property on this object reaches exactly none of them.
    ///
    /// The block comes from `plan_phases` — the DATED table — and not from
    /// `schedule.phase`, which is the `ProgramPhase` direction (cut/bulk) the
    /// deck follows and has never had a deload in it. A date between blocks
    /// resolves to nil, which `reacting(to:)` treats as the identity, so an
    /// athlete with no plan sees the palette exactly as they picked it.
    ///
    /// Guarded on the stored value so the common call — every debounced commit
    /// — is one string compare. Only a real move pays for the reload.
    ///
    /// ── AND GUARDED ON THE LIVE SESSION, WHICH IS LAW 9 ─────────────────────
    /// Writing this key re-ids the app root exactly as a theme pick does, and
    /// that rebuild takes `WorkoutTabView`'s live `LoggerModel` with it — the
    /// clock, the rest timer and the deck cursor. `AppearanceView` refuses to
    /// write during a workout for this reason; a block that rolled over at
    /// midnight, mid-session, would have done the same damage with nobody
    /// touching the phone. So it waits: every local write runs the debounced
    /// reload, the finished session IS a local write, and the block lands on
    /// the far side of it.
    private func publishPhase(_ schedule: ScheduleContext?) {
        guard !isSessionLive else { return }
        let raw = schedule.flatMap { Phases.span(for: today, in: $0.phases)?.def.kind }?.rawValue ?? ""
        let defaults = AppDatabase.appGroupDefaults()
        guard (defaults.string(forKey: OnyxTheme.phaseKey) ?? "") != raw else { return }
        defaults.set(raw, forKey: OnyxTheme.phaseKey)
        // `@AppStorage` re-ids the app root for the views; this is for THIS
        // process's own static tokens, which a `body` invalidation does not
        // touch, and for anything that reads `OnyxTheme.current` off the tree.
        OnyxTheme.load(defaults)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func rollDay() {
        let day = LogicalDay.today()
        guard day != today else { return }
        today = day
        dayTick += 1
        // Yesterday's queue is about yesterday's routine day.
        publishProgression([], for: nil)
        startWeighInWatch()
        // The watch resolves its split against the date the PHONE believes it
        // is, not against its own clock — the two can disagree across midnight,
        // and a watch that decided it was already Tuesday would open the wrong
        // workout. So the roll has to travel.
        if case .signedIn(let userID) = auth { pushWatchContext(userID: userID) }
    }

    /// The signed-in user's id as the store spells it.
    ///
    /// `workout_sessions.user_id` is NOT NULL in Postgres, so a session row has
    /// to carry one from the moment it is created — before any sync exists to
    /// supply it. Signed out, there is no session to open and nothing calls
    /// this; the empty string is the honest answer rather than a placeholder
    /// uuid that would later have to be found and corrected.
    ///
    /// "As the store spells it" was a lie until W1: this returned
    /// `userID.uuidString`, which is uppercase, while every pulled row carried
    /// Postgres's lowercase. See `OnyxJSON.canonicalUserID`.
    public var userIdString: String {
        if case .signedIn(let userID) = auth { return OnyxJSON.canonicalUserID(userID) }
        return ""
    }

    private func scheduleWidgetReload() {
        widgetReload?.cancel()
        widgetReload = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            // A pull that lands a new `plan_phases` row is a commit and nothing
            // else — no sign-in, no midnight — so without this the palette
            // would not learn about a deload until one of those came round.
            // Free when the block has not moved; see `publishPhase`.
            self.publishPhase(self.targets?.schedule)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    public func reportStartupError(_ message: String) {
        startupError = message
    }
}

#if DEBUG
/// A device with no Health store. Every read answers "nothing here".
private struct NoHealth: HealthReading {
    var isAvailable: Bool { false }
    func requestAuthorization(read: [String]) async throws -> Bool { false }
    func quantity(_ identifier: String, reduce: HealthReduce, start: Date, end: Date) async throws -> Double? { nil }
    func sleepSamples(start: Date, end: Date) async throws -> [SleepSample] { [] }
}
#endif
