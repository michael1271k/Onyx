import Foundation
import Supabase

/// What a realtime notification turns into: a re-pull of exactly what changed.
///
/// ── THE WHOLE `TABLE_KEYS` MAP EVAPORATES ───────────────────────────────────
/// The web app carried a hand-maintained dictionary of table → the eight or ten
/// react-query keys that table feeds, because a change had to be translated
/// into every cache entry that might be holding a stale copy. It was wrong
/// twice in ways the file's own comments record: `['daily_scores']` sat in seven
/// lists and matched no query at all, and `schedule_overrides` was missing
/// entirely, which is half of why a rest-day swap on the phone never reached
/// the desktop.
///
/// None of that exists here. A pull writes a row; `ValueObservation` sees the
/// write and pushes it into whatever is drawing. There is no key to match, no
/// list to maintain, and no way for the view and the store to disagree — so the
/// only thing realtime has to decide is WHICH TABLE to re-read.
public protocol MirrorRefreshing: Sendable {
    /// Re-read one table. `nil` means the training trio, which is pulled as a
    /// unit because its three tables are one fact.
    func refresh(table: String?) async
}

/// Turns a burst of change notifications into as few pulls as possible.
///
/// Separated from the socket because this is the only part with a decision in
/// it. Wiring a channel up is verified by the compiler; coalescing is verified
/// by a test, and it is the thing that decides whether finishing a workout on
/// the watch costs the phone one round trip or thirty.
public actor MirrorCoalescer {

    /// The web app settled on 400 ms after watching a session commit arrive as
    /// a session row plus thirty set rows: without a window, that is thirty-one
    /// notifications and thirty-one refetches for one logical event.
    public static let window: Duration = .milliseconds(400)

    private let refresher: any MirrorRefreshing
    private let window: Duration
    private var pending: Set<String> = []
    private var flush: Task<Void, Never>?

    public init(refresher: any MirrorRefreshing, window: Duration = MirrorCoalescer.window) {
        self.refresher = refresher
        self.window = window
    }

    /// A table changed somewhere else.
    public func note(_ table: String) {
        pending.insert(table)
        flush?.cancel()
        flush = Task { [window] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            await self.drain()
        }
    }

    /// Pull everything noted since the last flush.
    ///
    /// Public so a foreground can force it: coming back to the app should not
    /// wait out a debounce window that a suspended socket may never close.
    public func drain() async {
        let tables = pending
        pending.removeAll()
        guard !tables.isEmpty else { return }

        // The training trio collapses to one refresh. A set edit bumps its
        // session's `updated_at` through the same trigger, so pulling sessions
        // by cursor is what finds it — asking for `workout_sets` on its own
        // would be a query with no cursor to use.
        var wantsTraining = false
        var wanted: [String] = []
        for table in tables {
            if MirrorRealtime.trainingTables.contains(table) { wantsTraining = true } else {
                wanted.append(table)
            }
        }

        // ── TOGETHER, NOT ONE AFTER ANOTHER ─────────────────────────────────
        // Awaited in sequence, each refresh has finished before the next
        // begins — so nothing downstream can fold them, and the refresher the
        // app actually installs is `SyncCoordinator`, for which ONE refresh is
        // a whole sync that pulls every table. A flush of thirty-one notes was
        // therefore thirty-one syncs, each pulling all thirty-one tables, for
        // one catch-up. Fired together they collapse into the one or two runs
        // `syncNow` already knows how to merge: the same argument as the
        // debounce above, one layer down.
        await withTaskGroup(of: Void.self) { group in
            for table in wanted {
                group.addTask { [refresher] in await refresher.refresh(table: table) }
            }
            if wantsTraining {
                group.addTask { [refresher] in await refresher.refresh(table: nil) }
            }
        }
    }

    /// Drop what is waiting and the timer that would flush it. Sign-out: a
    /// debounced refresh must not fire into a coordinator that is gone.
    public func stop() {
        flush?.cancel()
        flush = nil
        pending.removeAll()
    }

    /// Test seam: what is waiting.
    public var noted: Set<String> { pending }
}

/// The Supabase channel, and the lifecycle around it.
///
/// ── WHAT IS NOT PORTED, AND WHY ─────────────────────────────────────────────
/// The web provider carried a `socketHealthy` flag, a `joinedOnce` flag, a
/// `visibilitychange` listener and an `online` listener — roughly half the
/// file — because a backgrounded PWA's WebSocket is suspended by iOS and may
/// never silently rejoin. `RealtimeClientV2` redials the socket itself, and a
/// native app gets real lifecycle callbacks instead of guessing from
/// `document.visibilityState`. So what is left is: subscribe, forward, re-pull
/// on foreground — and the one thing the library does NOT do for us, below.
///
/// The `requestIdleCallback` deferral does not port either. It existed because
/// opening a socket before first paint delayed first paint; a SwiftUI app starts
/// this from a `.task`, which is already after the first frame.
///
/// ── THE RETRY IS OURS; THE RECONNECT IS THEIRS ──────────────────────────────
/// `RealtimeClientV2` reconnects a dropped SOCKET with its own backoff and
/// re-sends `phx_join` for every channel — but exactly once, through a `try?`.
/// A JOIN that fails (a token mid-refresh, an RLS error, a server that times
/// the join out) therefore leaves the channel `.unsubscribed` with nothing
/// scheduled to try again, and the app goes quiet until it is next launched.
/// That is the hole `supervise()` fills, and the only one: it never opens a
/// socket, it re-asks for the join on the channel the library already owns.
///
/// While the channel is not joined the same data comes down on a 60 s poll —
/// `foreground()`, which is the "note everything and drain" a burst of
/// notifications would have produced. Push freshness degrades to pull
/// freshness rather than to nothing.
public actor MirrorRealtime {

    /// The three tables `TrainingPuller` owns. Named here rather than in the
    /// generated catalogue because the catalogue deliberately excludes them.
    public static let trainingTables: Set<String> = ["workout_sessions", "workout_sets", "exercises"]

    /// Everything worth listening to: the generated catalogue plus the trio.
    ///
    /// Derived rather than curated. The web app's list was hand-maintained and
    /// `schedule_overrides` fell off it, so a day swap made on the phone never
    /// reached the laptop until someone reloaded.
    public static var tables: [String] {
        MirrorCatalogue.tables.map(\.name) + trainingTables.sorted()
    }

    /// Where the retry ladder starts, and where it stops growing.
    ///
    /// One second because the failure this exists for — a join attempted while
    /// the access token is mid-refresh — is over by the time the first retry
    /// lands, and a minute of silence for it would be absurd. Sixty seconds as
    /// the ceiling because that is `pollInterval`: past that point the fallback
    /// poll is already delivering the same rows, so a slower retry costs
    /// nothing anyone can see, and a phone with no signal must not spend its
    /// battery dialling.
    static let retryFloor: Duration = .seconds(1)
    static let retryCeiling: Duration = .seconds(60)

    /// How often the fallback poll runs while the channel is not joined.
    ///
    /// A poll is `foreground()` — every table noted and drained as one fold,
    /// which the refresher folds again into a single sync of delta queries
    /// that mostly return nothing. Cheap, but not free: 60 s is slow enough to
    /// be invisible on the battery and fast enough that a set logged on the
    /// watch reaches the phone in about the time it takes to rack the bar.
    static let pollInterval: Duration = .seconds(60)

    private let client: SupabaseClient
    private let coalescer: MirrorCoalescer
    private var channel: RealtimeChannelV2?
    private var listeners: [Task<Void, Never>] = []
    /// The one retry loop. Non-nil means an attempt is in flight or waiting,
    /// and is what makes a second `start()` a no-op — two of these would be two
    /// joins racing to write `channel`.
    private var supervisor: Task<Void, Never>?
    /// The fallback poll, alive only while the channel is not joined.
    private var poll: Task<Void, Never>?

    public init(client: SupabaseClient, coalescer: MirrorCoalescer) {
        self.client = client
        self.coalescer = coalescer
    }

    /// Open the socket and start forwarding. Returns as soon as the attempt is
    /// scheduled; joining is the supervisor's problem, not the caller's.
    public func start() async {
        guard supervisor == nil else { return }
        supervisor = Task { [weak self] in await self?.supervise() }
    }

    /// Join, hold, re-join. The whole retry, in one place.
    ///
    /// The ladder is reset by a JOIN and not by a start, which is the only
    /// reset that means anything: a channel that joins and immediately drops
    /// has not recovered, and a channel that has been joined for an hour owes
    /// nothing to the four failures before it.
    ///
    /// ponytail: a socket that joined and dropped in a loop would retry at the
    /// floor for ever, because every join resets the ladder. Time the join and
    /// only reset once it has held a poll interval, if a flapping server ever
    /// turns up.
    private func supervise() async {
        var attempt = 0
        while !Task.isCancelled {
            if await join() {
                attempt = 0
                stopPolling()
                await waitForDrop()
            }
            guard !Task.isCancelled else { return }
            // Disconnected, one way or the other. The poll covers the gap
            // until a join sticks, and the sleep is what keeps this from
            // becoming the tight loop it is here to avoid.
            startPolling()
            try? await Task.sleep(for: Self.retryDelay(attempt: attempt))
            attempt += 1
        }
    }

    /// One join attempt against the channel, opening it the first time.
    ///
    /// The channel is REUSED across retries. Its bindings live on the channel
    /// and survive an unsubscribe — supabase-swift only clears them in
    /// `deinit` — and `subscribeWithError` rebuilds the join payload from the
    /// same config every time, which is exactly what the library's own rejoin
    /// does after a socket reconnect. Tearing the channel down and building a
    /// new one would be a second `phx_join` racing the library's.
    ///
    /// It is also why a second attempt cannot double-join: an already-joined
    /// channel returns immediately, and one already joining is awaited rather
    /// than started again.
    private func join() async -> Bool {
        // Cancellation is re-read here, not just at the top of the loop: a
        // sign-out that lands between the two would otherwise open a channel
        // nobody is left to remove.
        guard !Task.isCancelled else { return false }
        if channel == nil { open() }
        guard let channel else { return false }
        do {
            try await channel.subscribeWithError()
            return true
        } catch {
            // Swallowed, as it always was: the socket is a latency
            // optimisation, not a data path. `SyncCoordinator` pulls on launch
            // and on every foreground, the poll below covers the rest, and
            // there is no caller up the chain (`startRealtime` is `async`, not
            // `throws`) that could do anything with it. What is new is that
            // the failure is no longer terminal.
            return false
        }
    }

    /// Build the channel and its per-table streams.
    private func open() {
        let channel = client.channel("onyx-mirror")
        self.channel = channel

        // One binding per table, each its own stream. The streams are created
        // BEFORE `subscribe()`: a binding added after the join is not part of
        // the subscription the server acknowledged, and silently receives
        // nothing — which looks exactly like "nothing has changed".
        for table in Self.tables {
            let changes = channel.postgresChange(AnyAction.self, schema: "public", table: table)
            listeners.append(Task { [coalescer] in
                for await _ in changes {
                    // The payload is deliberately ignored. It carries the row,
                    // but trusting it would make the socket a second write path
                    // with its own decoding and its own bugs; re-reading through
                    // the puller means there is exactly one way a server row
                    // becomes a local row.
                    await coalescer.note(table)
                }
            })
        }
    }

    /// Suspend until the channel stops being joined — a socket drop, a server
    /// close, or `stop()` taking the channel away.
    ///
    /// `statusChange` replays the CURRENT status to a new iterator, so the join
    /// that just succeeded arrives here first and has to be stepped over;
    /// returning on it would spin. The stream also finishes on cancellation,
    /// which is how sign-out gets out of here.
    private func waitForDrop() async {
        guard let channel else { return }
        for await status in channel.statusChange {
            if case .subscribed = status { continue }
            return
        }
    }

    /// `~1 s, 2, 4 … 60`, each drawn from the top half of its step.
    ///
    /// Equal jitter rather than a fixed ladder: the phone, the watch and the
    /// widget extension all lose the same Wi-Fi at the same instant and would
    /// otherwise re-join in lockstep for ever. The shift is clamped because a
    /// socket down overnight is a four-digit `attempt`, and `1 << 64` is not a
    /// long wait, it is a crash.
    static func retryDelay(attempt: Int) -> Duration {
        min(retryFloor * (1 << min(attempt, 6)), retryCeiling) * Double.random(in: 0.5...1)
    }

    /// Ask the puller for what the socket is not delivering.
    ///
    /// The first poll is one interval away, not immediate: a drop is followed
    /// within a second by a re-join attempt, and a full twenty-nine-table drain
    /// fired at every flap would cost more than the silence it is covering.
    private func startPolling() {
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: MirrorRealtime.pollInterval)
                guard !Task.isCancelled else { return }
                await self?.foreground()
            }
        }
    }

    private func stopPolling() {
        poll?.cancel()
        poll = nil
    }

    /// Close it. Cancels the retry and the poll first, so neither can outlive
    /// the sign-out that asked for this, then every listener, so nothing is
    /// delivered into a channel that is going away.
    public func stop() async {
        supervisor?.cancel()
        supervisor = nil
        stopPolling()
        for task in listeners { task.cancel() }
        listeners.removeAll()
        await coalescer.stop()
        if let channel {
            await client.removeChannel(channel)
            self.channel = nil
        }
    }

    /// Foregrounding — and, every 60 s, the fallback poll.
    ///
    /// A suspended socket misses events without reporting anything, so returning
    /// to the app is the one moment a full catch-up is worth its cost. Cheap
    /// here in a way it was not on the web: a delta pull asks for what changed
    /// since a cursor, so "catch up on everything" is a fold of small queries
    /// that mostly return nothing, rather than a refetch of the world.
    ///
    /// The poll uses this rather than a shape of its own because a poll IS a
    /// foreground: neither knows which table moved, both have to ask about all
    /// of them, and there is no second way to ask.
    ///
    /// It notes every table and drains immediately — the debounce exists to
    /// coalesce a burst, and there is no burst to wait for here.
    public func foreground() async {
        for table in Self.tables { await coalescer.note(table) }
        await coalescer.drain()
    }
}

/// The two pullers behind one `MirrorRefreshing`.
///
/// This is the whole wiring: a table name from the socket becomes a pull, and
/// `nil` becomes the training trio. Everything else — cursors, strategies,
/// windows — is already decided by the catalogue.
public struct MirrorSync: MirrorRefreshing {

    private let puller: MirrorPuller
    private let training: TrainingPuller

    public init(puller: MirrorPuller, training: TrainingPuller) {
        self.puller = puller
        self.training = training
    }

    public func refresh(table: String?) async {
        guard let table else {
            _ = try? await training.refresh()
            return
        }
        guard let entry = MirrorCatalogue.byName[table] else { return }
        _ = try? await puller.refresh(entry)
    }

    /// Everything, once. The first sync after sign-in, and the manual
    /// pull-to-refresh.
    ///
    /// Failures are inside the report, not thrown: one table that a migration
    /// has not reached must not stop the other twenty-five, and a partial mirror
    /// is a working app with one stale screen rather than a blank one.
    @discardableResult
    public func refreshAll() async -> MirrorReport {
        var report = await puller.refresh()
        do {
            let training = try await self.training.refresh()
            report.tables += training.tables
            report.rows += training.rows
        } catch {
            report.failures["workout_sessions"] = String(describing: error)
        }
        return report
    }
}
