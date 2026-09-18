import Foundation
import GRDB
import Observation
import OnyxCore
import OnyxData
import OnyxUI

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
    ///
    /// `tiles` (W7) is the complications' dozen numbers, cut from the same
    /// snapshot the Home Screen widgets draw. It rides INSIDE the context
    /// rather than as a second application-context kind, because the channel
    /// is one slot: a second kind would overwrite the schedule every time a
    /// number moved, and the watch would open on "Open Onyx on your iPhone"
    /// between two pushes.
    func send(userId: String, today: String, schedule: ScheduleContext, tiles: WatchTiles?) {
        link?.send(
            context: WatchContext(
                userId: userId, today: today, schedule: resolved(schedule),
                // The wrist wears what the phone wears. The watch has no
                // Settings screen for this, and a second place to set a theme
                // is a second place for the two to disagree.
                theme: OnyxTheme.current.spec,
                tiles: tiles
            )
        )
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
