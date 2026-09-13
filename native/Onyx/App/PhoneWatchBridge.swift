import Foundation
import GRDB
import Observation
import OnyxCore
import OnyxData

/// The phone's half of the watch link.
///
/// ── WHAT IT OWES THE WATCH ──────────────────────────────────────────────────
/// Two things, and they are not the same kind of thing.
///
///   · **The context** — who is signed in, what today is, and how the plan
///     resolves it. STATE, sent over `updateApplicationContext`, replaced
///     wholesale, and the only reason the watch can name today's split at all.
///     Without it the watch shows "Open Onyx on your iPhone" and nothing else.
///   · **The events** — every set, amend, void and pause this phone produces.
///     FACTS, sent over `transferUserInfo`, queued and delivered even when the
///     watch app is not running.
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
    func send(userId: String, today: String, schedule: ScheduleContext) {
        link?.send(context: WatchContext(userId: userId, today: today, schedule: schedule))
    }

    /// Mirror the phone's rest clock onto the wrist. `nil` stops it.
    func send(rest: RestPulse?) {
        link?.send(rest: rest)
    }

    // MARK: - Inbound

    private func receive(_ inbound: WatchLink.Inbound) {
        do {
            switch inbound {
            case .events(let events):
                // The one merge path, shared with the pull side of Supabase.
                // `ingest` de-duplicates, advances the Lamport clock, marks the
                // events synced and re-folds — and deliberately does NOT queue
                // them, because echoing a remote event back is how a sync loop
                // starts.
                //
                // Note what this means for durability: a set logged on the wrist
                // is now in this phone's log, but `ingest` marks it synced, so
                // the phone's outbox will not push it. It reaches Supabase as a
                // `workout_sets` row through the projection the next time
                // anything about that session is queued — and, once
                // `wave-10-set-events.sql (git history)` is applied, as an event from
                // the watch's own drain. Until then the watch's sets reach the
                // server only through a session the phone also touches.
                try database.ingest(events)
            case .ownership(let claim):
                try database.ingestOwnership(claim)
            case .rest:
                // The phone does not mirror the watch's rest clock. It has its
                // own logger with its own timer and its own Live Activity, and
                // two clocks fighting over one banner is worse than one clock.
                break
            case .context:
                // Phone → watch only. The watch has no plan resolution to send.
                break
            }
        } catch {
            lastError = String(describing: error)
        }
    }
}
