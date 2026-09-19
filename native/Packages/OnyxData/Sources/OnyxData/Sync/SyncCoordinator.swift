import Foundation
import Supabase

/// Why a sync is running. Not decoration: the coordinator coalesces on it, the
/// ledger records it, and `.pull` is the only one a person is watching.
public enum SyncReason: Hashable, Sendable {
    case launch
    case foreground
    case pull
    case realtime(table: String)
    case healthKit
    /// The whole history, in dependency order, with the cursors cleared first.
    /// A superset of every other reason — see `syncNow` for what that buys.
    case backfill

    var isRealtime: Bool {
        if case .realtime = self { return true }
        return false
    }

    var ledgerName: String {
        switch self {
        case .launch: return "launch"
        case .foreground: return "foreground"
        case .pull: return "pull"
        case .realtime(let table): return "realtime:\(table)"
        case .healthKit: return "healthKit"
        case .backfill: return "backfill"
        }
    }
}

/// Where a running sync is.
public enum SyncStep: String, Sendable, Equatable {
    case push, health, pull, score
}

/// What the backfill sheet draws: one row per table, in the order they are
/// pulled, with a count once each has landed.
public struct BackfillProgress: Sendable, Equatable {
    public struct Table: Sendable, Equatable, Identifiable {
        public let name: String
        /// Rows landed. `nil` until the table has been pulled.
        public var rows: Int?
        public var error: String?
        public var id: String { name }
        public init(name: String, rows: Int? = nil, error: String? = nil) {
            self.name = name
            self.rows = rows
            self.error = error
        }
    }

    public var tables: [Table]
    public var startedAt: Date
    /// Set once every step — pull, score, push — has run clean. The clock on
    /// the sheet stops here.
    public var finishedAt: Date?
    public var isFinished: Bool { finishedAt != nil }

    public init(tables: [Table], startedAt: Date, finishedAt: Date? = nil) {
        self.tables = tables
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var rowsLanded: Int { tables.compactMap(\.rows).reduce(0, +) }
    public var tablesLanded: Int { tables.filter { $0.rows != nil }.count }
}

public struct SyncProgress: Sendable, Equatable {
    public var reason: SyncReason
    public var step: SyncStep
}

public enum SyncState: Sendable, Equatable {
    case idle
    case running(SyncProgress)
    case failed(String)
}

public enum SyncCoordinatorError: Error, Equatable, CustomStringConvertible {
    /// Every step ran, but these tables did not land. Thrown AFTER the score
    /// and the closing drain, so one table a migration has not reached costs
    /// the sync its green light and nothing else.
    case tablesFailed([String: String])

    public var description: String {
        switch self {
        case .tablesFailed(let failures):
            return "Sync failed for \(failures.keys.sorted().joined(separator: ", "))."
        }
    }
}

/// The one object that runs a sync, in order, once at a time.
///
/// ── THE ORDER, AND THE ONE PLACE IT DEPARTS FROM §7.1 ───────────────────────
/// `resetInFlight` → HealthKit → `drain` → pull → score → `drain`.
///
/// §7.1 writes the HealthKit read AFTER the first drain. It cannot go there:
/// `saveMirrorRows` is a blind upsert, so a pull that follows a local write and
/// precedes its push overwrites the write with the server's older row — and the
/// outbox item, which reads the row at drain time, then pushes the server's own
/// value back at it. Today's steps would vanish on every sync. Reading Apple
/// first and pushing second keeps §7.1's actual rule — a pull never overwrites
/// a local edit — for the health rows too.
///
/// The second drain is for what the sync itself wrote: two `daily_scores`
/// rows. An empty queue costs one SQLite read.
///
/// ── COALESCING ──────────────────────────────────────────────────────────────
/// A call while one is running is queued ONCE; a third call joins the queued
/// one. Every caller awaits the run that will include its request, so
/// `.refreshable` holds its spinner for exactly as long as the truth takes.
///
/// ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────────
/// It does not touch WidgetKit — this package compiles for macOS, and the app
/// already reloads timelines from `AppDatabase.onCommit`. It does not present
/// anything: the backfill sheet is the app's, drawn from `BackfillProgress`.
///
/// ── THE BACKFILL (§7.2) ─────────────────────────────────────────────────────
/// `syncNow(reason: .backfill)` is the same run with three differences: every
/// cursor is cleared first, so the whole history comes down (idempotent — every
/// landing is an upsert, so "Re-run backfill" is the same call); the pull goes
/// in dependency order (`user_goals`, `plans`, `exercises`, sessions, sets,
/// then the rest) and reports per table; and the score is recomputed for the
/// last fourteen days rather than two. The ledger is written only when every
/// table landed, so a backfill that died halfway is recognised as "never
/// synced" at the next launch and runs again from the top.
public actor SyncCoordinator: MirrorRefreshing {

    /// The tables the backfill sheet lists, in the order they are pulled.
    /// Parents before children: the three the training tables reference,
    /// sessions before the sets that belong to them, everything else after.
    public static let backfillOrder: [String] = {
        // `set_events` last of the training tables: it is pulled by
        // `TrainingPuller` right after the sets it is a fold of, and `ingest`
        // needs the session rows to exist first (`set_events.session_id` has a
        // foreign key locally as well as on the server).
        let head = ["user_goals", "plans", "exercises", "workout_sessions", "workout_sets", "set_events"]
        return head + MirrorCatalogue.tables.map(\.name).filter { !head.contains($0) }
    }()
    /// The catalogue tables pulled BEFORE the training three.
    private static let backfillHead: Set<String> = ["user_goals", "plans"]
    /// How many days the completion hook rescores.
    public static let backfillScoreDays = 14


    private let database: AppDatabase
    private let engine: SyncEngine
    private let puller: MirrorPuller
    private let training: TrainingPuller
    private let health: HealthSync?
    private let userId: String
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public private(set) var state: SyncState = .idle

    private var current: Task<Void, any Error>?
    private var queued: Task<Void, any Error>?
    /// The reason the WAITING run — `queued`, or an unstarted `current` — will
    /// run with. Read by the task when it starts, not fixed when it is made, so
    /// a later caller can upgrade it: a backfill request that joins a queued
    /// foreground sync turns that sync into the backfill, because a backfill
    /// does everything a sync does and more. Joining it the other way round
    /// needs no upgrade.
    private var queuedReason: SyncReason?

    /// What the last automatic cardio ingest brought in, or nil when the last
    /// pass found nothing new.
    ///
    /// Held rather than streamed: it is read once, by the tab that puts the
    /// notice up, and `take` clears it so the same three walks are not
    /// announced again on every foreground for the rest of the day.
    private var lastCardioIngest: CardioIngestReport?

    /// Read and clear.
    public func takeCardioIngest() -> CardioIngestReport? {
        defer { lastCardioIngest = nil }
        return lastCardioIngest
    }
    /// Whether `current` has begun its steps. Between one run's handover and
    /// the next run's first line there is a hop back onto the actor; a caller
    /// arriving in that gap can still join the promoted task instead of
    /// queueing a third run behind it.
    private var started = false
    /// Live during a backfill run; what `onBackfillProgress` is fed.
    public private(set) var backfillProgress: BackfillProgress?
    private var onBackfillProgress: (@Sendable (BackfillProgress) -> Void)?
    private var progressToken: UUID?
    private var realtime: MirrorRealtime?
    private var coalescer: MirrorCoalescer?
    /// Set by `stop()`. A launch sync that finishes after sign-out must not
    /// open a socket nobody will close.
    private var stopped = false

    /// The pieces, injected. What the tests build.
    public init(
        database: AppDatabase,
        engine: SyncEngine,
        puller: MirrorPuller,
        training: TrainingPuller,
        health: HealthSync? = nil,
        userId: String,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.database = database
        self.engine = engine
        self.puller = puller
        self.training = training
        self.health = health
        self.userId = userId
        self.calendar = calendar
        self.now = now
    }

    /// The production wiring, over one Supabase client. `windowDays: nil` —
    /// the cap is gone (decision 7).
    public init(database: AppDatabase, client: SupabaseClient, userId: String, health: HealthSync? = nil) {
        let mirror = PostgRESTMirrorRemote(client: client, userId: userId)
        self.init(
            database: database,
            engine: SyncEngine(database: database, userId: userId, remote: PostgRESTRemote(client: client, userId: userId), rows: mirror),
            puller: MirrorPuller(database: database, remote: mirror, userId: userId, windowDays: nil),
            training: TrainingPuller(database: database, remote: mirror, userId: userId, windowDays: nil),
            health: health,
            userId: userId
        )
    }

    // MARK: - Running

    /// One full sync. Awaits the run that includes this request.
    public func syncNow(reason: SyncReason) async throws {
        let task: Task<Void, any Error>
        if let running = current {
            if let waiting = queued ?? (started ? nil : running) {
                // A backfill does more than any sync; a sync does more than a
                // realtime note (which skips Apple). Joining never downgrades.
                if reason == .backfill || queuedReason?.isRealtime == true { queuedReason = reason }
                task = waiting
            } else {
                queuedReason = reason
                let t = Task {
                    _ = await running.result
                    try await self.runQueued()
                }
                queued = t
                task = t
            }
        } else {
            queuedReason = reason
            let t = Task { try await self.runQueued() }
            current = t
            task = t
        }
        try await task.value
    }

    /// The whole history, with per-table progress. `onProgress` is called on
    /// an arbitrary executor; hop to the main actor before touching a view.
    ///
    /// Idempotent: the cursors are cleared inside the run, so "Re-run backfill"
    /// in Settings is this same call.
    public func backfill(onProgress: @escaping @Sendable (BackfillProgress) -> Void) async throws {
        let token = UUID()
        onBackfillProgress = onProgress
        progressToken = token
        // Only this caller's handler is dropped: a second backfill queued
        // behind this run has already replaced it, and keeps it.
        defer { if progressToken == token { onBackfillProgress = nil } }
        try await syncNow(reason: .backfill)
    }

    /// Whether this user has ever completed a sync on this device. An empty
    /// ledger is how the app recognises a first launch — and a backfill that
    /// died halfway, which writes nothing to it.
    public func needsBackfill() throws -> Bool {
        // Not the `outbox` line: every run writes one, including the run that
        // died before a single table landed. Nor `rescore` (W2): the cascade
        // ledger lives in the same table and a door touch can land before the
        // first pull ever does.
        try database.lastSync(userId: userId).keys.allSatisfy { $0 == "outbox" || $0 == "rescore" }
    }

    private func runQueued() async throws {
        // Read at the last moment, so an upgrade to `.backfill` made while
        // this task was waiting is honoured. No suspension between here and
        // `started = true`, so a caller cannot slip in between.
        let reason = queuedReason ?? .foreground
        queuedReason = nil
        try await run(reason)
    }

    private func run(_ reason: SyncReason) async throws {
        // The task that finishes hands over to the one waiting, if any. A
        // queued task was created holding `current`'s result, so by the time
        // it reaches here this line has already made it `current`.
        started = true
        defer {
            current = queued
            queued = nil
            started = false
        }
        do {
            try await steps(reason)
            state = .idle
        } catch {
            state = .failed(String(describing: error))
            throw error
        }
    }

    private func steps(_ reason: SyncReason) async throws {
        // A queued run resumes after `stop()` regardless — `await
        // running.result` is not cancellable — and must not reset cursors or
        // read Apple for a user who has signed out.
        try checkStopped()
        let now = now()
        state = .running(SyncProgress(reason: reason, step: .push))
        try database.resetInFlight()

        let isBackfill = reason == .backfill
        if isBackfill {
            // Every cursor, so the delta tables come down whole; the window
            // tables already do (`windowDays: nil`). The sets of a session this
            // device has events for are still refused by `applyPulledSets`.
            try database.resetMirrorCursor()
            backfillProgress = BackfillProgress(
                tables: Self.backfillOrder.map { BackfillProgress.Table(name: $0) }, startedAt: now
            )
            emitBackfill()
        }

        // Not for a realtime note: the socket said a row moved on the server,
        // and reading Apple again for that is a HealthKit round trip per
        // notification. Foreground and pull still read it.
        //
        // Not before a BACKFILL either. The read goes first to keep a local
        // write ahead of the pull that would overwrite it, and a first launch
        // has no local write to protect — but it does have the Health
        // permission sheet, which `requestAuthorization` awaits, and the whole
        // history must not sit behind it. A backfill reads Apple after the
        // pull, where the closing drain still pushes what it wrote.
        if !reason.isRealtime, !isBackfill {
            try await readHealth(reason: reason, now: now)
        }

        state = .running(SyncProgress(reason: reason, step: .push))
        try await drainAll(now: now)

        state = .running(SyncProgress(reason: reason, step: .pull))
        let report = isBackfill ? try await backfillPull(now: now) : await pull(now: now)
        // Between the pull and the ledger, because this is the last moment at
        // which abandoning the run costs nothing. `pull` catches every error
        // per table into `report.failures` — cancellation included — so a run
        // stopped mid-pull arrives here with a report in hand and, without
        // this line, went on to `record` it. That is sign-out stamping the
        // ledger for the user who has just left, which is the exact thing
        // `stop()`'s own comment claims it prevents.
        try checkStopped()
        // A backfill's ledger is all or nothing: a table that did not land
        // must leave the user looking "never synced", so the next launch runs
        // the whole thing again. A normal sync records what it got.
        if !isBackfill || report.isClean { try record(report, reason: reason, at: now) }
        if isBackfill { try await readHealth(reason: reason, now: now) }

        // Session metrics AFTER the pull, on purpose. `applyPulledSessions`
        // overwrites the local row with the server's, so a value written
        // before the pull would vanish on the sync that pulled that session —
        // and the closing drain below is what pushes what is written here.
        if let health, !reason.isRealtime {
            _ = try? await health.syncSessionMetrics(now: now, calendar: calendar)
            // ── THE BOUT NOBODY HAD TO TYPE ─────────────────────────────────
            // Same placement and the same reason as session metrics: after the
            // pull, because `applyPulled*` overwrites local rows with the
            // server's, and before the closing drain, which is what pushes
            // whatever this wrote.
            //
            // `try?` because a cardio bout is not worth failing a sync over.
            // The report is kept rather than discarded so the UI can say what
            // arrived — a row that appears in the ledger with no account of
            // where it came from is the kind of data people stop trusting.
            if let report = try? await health.syncCardioBouts(now: now, calendar: calendar),
               !report.isEmpty {
                lastCardioIngest = report
            }
        }

        state = .running(SyncProgress(reason: reason, step: .score))
        // A backfill is "re-derive everything from the server", and the PR
        // ledger is derived — so this is where the one-off replay belongs
        // rather than in a button somebody has to remember to press. It covers
        // every session logged on this phone before the recorder existed, and
        // repairs any whose ledger write was lost. Idempotent, and the closing
        // drain below is what pushes whatever it wrote.
        if isBackfill { try database.recomputeAllPrs(userId: userId) }
        try scoreRecentDays(now: now, days: isBackfill ? Self.backfillScoreDays : 2)
        try await drainAll(now: now)

        if !report.failures.isEmpty { throw SyncCoordinatorError.tablesFailed(report.failures) }
        if isBackfill {
            backfillProgress?.finishedAt = self.now()
            emitBackfill()
        }
    }

    /// Today and yesterday out of HealthKit, into the store.
    private func readHealth(reason: SyncReason, now: Date) async throws {
        guard let health else { return }
        state = .running(SyncProgress(reason: reason, step: .health))
        // Silent, like the app's own read was: a withheld permission and a
        // device without Health data both render as "—" downstream, and
        // neither is a reason to fail the push that follows.
        if (try? await health.requestAuthorization()) == true {
            _ = try? await health.syncRecent(now: now, calendar: calendar)
        }
    }

    /// Every table, catalogue order. The training three come after the
    /// catalogue because their `applyPulled*` never touches a mirrored table.
    private func pull(now: Date) async -> MirrorReport {
        var report = await puller.refresh(now: now)
        do {
            let trained = try await training.refresh(now: now)
            report.merge(trained)
        } catch {
            report.failures["workout_sessions"] = String(describing: error)
        }
        return report
    }

    /// Dependency order, ticking the sheet as each table lands.
    ///
    /// The tick hops back onto this actor from inside the puller, so the rows
    /// it reports may arrive after the phase they belong to; `apply` writes
    /// the phase's report synchronously afterwards, so the sheet is exact by
    /// the time the next phase starts whatever the hop did.
    private func backfillPull(now: Date) async throws -> MirrorReport {
        let tick: @Sendable (String, Int) -> Void = { [weak self] name, rows in
            guard let self else { return }
            Task { await self.landed(name, rows: rows, run: now) }
        }
        let head = MirrorCatalogue.tables.filter { Self.backfillHead.contains($0.name) }
        let rest = MirrorCatalogue.tables.filter { !Self.backfillHead.contains($0.name) }

        var report = await puller.refresh(tables: head, now: now, onTable: tick)
        apply(report)
        try checkStopped()

        do {
            report.merge(try await training.refresh(now: now, onTable: tick))
        } catch {
            report.failures["workout_sessions"] = String(describing: error)
        }
        apply(report)
        try checkStopped()

        report.merge(await puller.refresh(tables: rest, now: now, onTable: tick))
        apply(report)
        // The LAST group had no check after it, and `rest` is where every table
        // but `user_goals` and `plans` lives. A run stopped while parked on one
        // of those returned its report and stamped the ledger — after sign-out,
        // for the user who had just left.
        try checkStopped()
        return report
    }

    private func landed(_ table: String, rows: Int, run: Date) {
        // A tick that hopped in after the next backfill began belongs to the
        // run that made it, not to this one.
        guard backfillProgress?.startedAt == run,
              let index = backfillProgress?.tables.firstIndex(where: { $0.name == table }) else { return }
        backfillProgress?.tables[index].rows = rows
        emitBackfill()
    }

    private func apply(_ report: MirrorReport) {
        guard var progress = backfillProgress else { return }
        for index in progress.tables.indices {
            let name = progress.tables[index].name
            if let rows = report.rowsByTable[name] { progress.tables[index].rows = rows }
            progress.tables[index].error = report.failures[name]
        }
        backfillProgress = progress
        emitBackfill()
    }

    private func emitBackfill() {
        if let backfillProgress { onBackfillProgress?(backfillProgress) }
    }

    /// Push whatever is still queued, and pull NOTHING.
    ///
    /// For sign-out. A full `syncNow` would also pull, refilling the store this
    /// is about to be followed by erasing — and it would do it with a session
    /// that is seconds from being revoked. The caller is expected to bound this
    /// with a timeout: a queue that cannot reach the network must not be able
    /// to hold a user on a screen they are trying to leave.
    public func drainOutbox() async throws {
        try await drainAll(now: .now)
    }

    /// Drain until the queue is empty or the backoff is holding the rest.
    /// Bounded: `hasMore` is also what a concurrent drain answers, and a loop
    /// that trusted it forever would spin on another engine's work.
    private func drainAll(now: Date) async throws {
        var pushed = 0
        for _ in 0..<20 {
            let report = try await engine.drain(now: now)
            pushed += report.pushed
            if !report.hasMore || report.pushed == 0 { break }
        }
        try database.recordSync(userId: userId, table: "outbox", rows: pushed, reason: "push", at: now)
    }

    private func record(_ report: MirrorReport, reason: SyncReason, at now: Date) throws {
        for (table, rows) in report.rowsByTable.sorted(by: { $0.key < $1.key }) {
            try database.recordSync(userId: userId, table: table, rows: rows, reason: reason.ledgerName, at: now)
        }
    }

    /// Today live, then each earlier day sealed — the production caller
    /// `writeDailyScore` was waiting for. Two days on a sync; fourteen after a
    /// backfill, which is how far the trailing inputs reach. A day the freeze
    /// refuses is a `nil`, not an error.
    private func scoreRecentDays(now: Date, days: Int) throws {
        var day = LogicalDayISO.string(now, calendar: calendar)
        for _ in 0..<days {
            _ = try database.refreshDailyScore(userId: userId, date: day, now: now, calendar: calendar)
            day = NightWindow.previousDay(day)
        }
    }

    // MARK: - Realtime

    /// A change notification.
    ///
    /// ── THROUGH THE QUEUE, NOT AROUND IT ────────────────────────────────────
    /// The obvious shape — pull just that table — is the one path that breaks
    /// the rule at the top of this file: a blind pull with no drain in front of
    /// it overwrites a local edit still waiting in the outbox, and the drainer
    /// then pushes the server's stale copy back. Draining first inside this
    /// method does not help either, because `SyncEngine.drain` yields to a
    /// drain already running and answers `hasMore` without pushing anything.
    /// So a note is a sync, coalesced like any other; the delta cursors keep
    /// the cost of the twenty-six pulls small, and the coalescer has already
    /// folded a burst into one call.
    public func refresh(table: String?) async {
        try? await syncNow(reason: .realtime(table: table ?? "workout_sessions"))
    }

    /// Open the socket. Once; a second call is a no-op.
    public func startRealtime(client: SupabaseClient) async {
        guard realtime == nil, !stopped else { return }
        let coalescer = MirrorCoalescer(refresher: self)
        let realtime = MirrorRealtime(client: client, coalescer: coalescer)
        self.coalescer = coalescer
        self.realtime = realtime
        await realtime.start()
    }

    /// Every checkpoint asks BOTH questions.
    ///
    /// `stop()` calls `current?.cancel()`, which reaches a run it stored — and
    /// nothing else. A run awaited directly by its caller is not in `current`,
    /// so task cancellation never arrives, and before this helper existed the
    /// only `stopped` check was the one at the top of `steps`. A sync already
    /// past that line therefore ran to completion after sign-out and stamped
    /// the ledger for the user who had just left, which is the precise thing
    /// the comment on `stop()` claims it prevents.
    private func checkStopped() throws {
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
    }

    /// Close the socket and abandon the run. Sign-out calls this before
    /// dropping the coordinator: a step still awaiting the network would
    /// otherwise finish and write the previous user's rows.
    public func stop() async {
        stopped = true
        current?.cancel()
        queued?.cancel()
        await realtime?.stop()
        realtime = nil
        coalescer = nil
    }

    // MARK: - Reading

    /// Table → when it last synced. What Settings' Sync Status section draws.
    public func lastSync() throws -> [String: Date] {
        try database.lastSync(userId: userId)
    }

    /// Table → how many rows the SERVER holds. The other half of the Sync
    /// Doctor's per-table line; the local half is a `count(*)` on the store.
    ///
    /// Concurrent because it is one HEAD request per table and twenty-six of
    /// them end to end is several seconds of a screen showing dashes. Nothing
    /// here writes, so there is no order to preserve.
    ///
    /// A table that errors is ABSENT from the result rather than zero — the
    /// same rule `MirrorPuller.refresh` follows for a failed pull. A `404` from
    /// a migration that has not run must not cost the other twenty-five their
    /// numbers, and reporting it as `0` would invent the exact alarm this
    /// screen exists to raise honestly.
    public func serverCounts(tables: [String] = SyncCoordinator.backfillOrder) async -> [String: Int] {
        await withTaskGroup(of: (String, Int?).self) { group in
            for table in tables {
                group.addTask { [puller] in (table, try? await puller.serverCount(table: table)) }
            }
            var out: [String: Int] = [:]
            // Assigning a nil `Int?` REMOVES the key, which is the absence the
            // doc comment above promises.
            for await (table, count) in group { out[table] = count }
            return out
        }
    }
}
