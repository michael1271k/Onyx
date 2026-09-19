import Foundation
import OnyxCore

/// The cascade: an edit rewrites every stored score it can still move.
///
/// ── WHY 48 DAYS AFTER AND NOT THE DAY ITSELF ────────────────────────────────
/// `ReadinessHistoryBuilder` reads a `Readiness.constants.historyDays` window
/// ENDING on the day being scored, and `duration_min × session_rpe` from every
/// session in it feeds ACWR, monotony and strain. So correcting one session's
/// duration does not move one number — it moves `battery_pct` on that day and
/// on every day up to forty-eight after it.
///
/// Before this existed the only production caller of `refreshDailyScore` was
/// `SyncCoordinator.scoreRecentDays`, which does today and yesterday (fourteen
/// on a backfill). An edit to a session three weeks ago changed the session row
/// and left seven weeks of scores describing a workout that no longer exists.
///
/// The horizon is DERIVED from that window rather than stated beside it, so the
/// two cannot drift; `RescoreTests` pins the arithmetic.
///
/// ── AND WHY EVERY DAY IS FORCED ─────────────────────────────────────────────
/// `writeDailyScore` seals a past day the first time it is computed after its
/// own midnight, so re-ingesting old data can never rewrite a snapshot. A
/// cascade is the one thing allowed through that: it runs because the athlete
/// explicitly changed the underlying data, which is the case `force` exists
/// for. See THE FREEZE in `DailyScoreStore`.
public enum Rescore {

    /// How far forward an edit reaches, in days AFTER the edited date.
    public static var horizonDays: Int { Readiness.constants.historyDays - 1 }

    /// Why the cascade ran. Carried for the sync ledger and the log line, never
    /// for a branch — every reason rewrites the same days.
    public enum Reason: String, Sendable, CaseIterable {
        case sessionEdit = "session-edit"
        case sleepEdit = "sleep-edit"
        case dayEdit = "day-edit"
        case manual = "manual"
        /// A formula changed under stored history (W3's sleep v2). The one
        /// reason whose range is not derived from an edit date.
        case migration = "migration"
    }

    /// Every date an edit on `from` can move, oldest first, clamped to today.
    ///
    /// Empty for a future date: a session dated tomorrow is a swap, and there
    /// are no stored scores after today to rewrite.
    public static func days(from: String, today: String) -> [String] {
        guard let start = ISODate.dayNumber(from), let end = ISODate.dayNumber(today), start <= end
        else { return [] }
        return (start...Swift.min(end, start + horizonDays)).map { ISODate.iso(dayNumber: $0) }
    }

    /// Every date in an inclusive range, oldest first. The queue's ranges are
    /// unions of several requests and no longer derivable from one `from`.
    public static func dates(from: String, through: String) -> [String] {
        guard let start = ISODate.dayNumber(from), let end = ISODate.dayNumber(through), start <= end
        else { return [] }
        return (start...end).map { ISODate.iso(dayNumber: $0) }
    }

    /// What one completed run did.
    public struct Run: Sendable, Equatable {
        /// The earliest date the run rewrote.
        public var from: String
        /// The last date it reached — `min(today, from + horizonDays)`.
        public var through: String
        /// Days that actually produced a row. A day with no data at all writes
        /// nothing and is not counted: `refreshDailyScore` answers `nil` there,
        /// and an absent row is the truth about a day nothing is known of.
        public var written: Int
        /// Days that THREW.
        ///
        /// Distinct from `written` on purpose. The queue keeps going past a
        /// failed day — the rest are still wrong and still worth rewriting —
        /// but folding a broken store into the same bucket as a blank day
        /// means a cascade that wrote nothing at all still reports success and
        /// still bumps the generation, and four screens reload announcing that
        /// the numbers agree.
        public var failed: Int
        /// More work was already queued when this run finished. The caller uses
        /// it to keep its "rescoring" hint up rather than flickering it off
        /// between two passes of one logical cascade.
        public var hasMore: Bool
        public var reason: Reason

        public init(
            from: String, through: String, written: Int,
            failed: Int = 0, hasMore: Bool = false, reason: Reason
        ) {
            self.from = from
            self.through = through
            self.written = written
            self.failed = failed
            self.hasMore = hasMore
            self.reason = reason
        }
    }
}

public extension AppDatabase {

    /// Rewrite every stored score an edit on `from` can move — synchronously,
    /// on the caller's thread: one read, one compute, one write (W2).
    ///
    /// ── ONE TRANSACTION FOR THE RUN, NOT ONE PER DAY ────────────────────────
    /// It was per day, and the header here argued for it: forty-nine reads of
    /// a forty-nine-day history each, and a write held across all of it would
    /// block the logger. `ScoringWindow` reads the range ONCE and computes in
    /// memory, so the write transaction holds forty-nine upserts and nothing
    /// else — milliseconds, and one commit for the widgets and the watch
    /// bridge to react to instead of forty-nine.
    ///
    /// The outbox collapses per row id, so a date rescored twice is still one
    /// upload — see `enqueueRowUpsert`.
    @discardableResult
    func rescore(
        userId: String,
        from: String,
        reason: Rescore.Reason = .manual,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Rescore.Run {
        let days = Rescore.days(from: from, today: LogicalDayISO.string(now, calendar: calendar))
        let written = try rescoreWindow(userId: userId, dates: days, now: now, calendar: calendar, force: true)
        // No `failed`: this form PROPAGATES a throw rather than counting it.
        // A caller that asked for the cascade synchronously is in a position
        // to handle the failure; the queue is not, which is why it counts.
        return Rescore.Run(
            from: from, through: days.last ?? from, written: written.count, reason: reason
        )
    }
}

/// The cascade, coalesced and off the main actor.
///
/// ── WHY A QUEUE AND NOT A TASK PER EDIT ─────────────────────────────────────
/// Editing a session is not one write. Correcting three sets is three calls,
/// each wanting forty-nine days rewritten from the same date — three unqueued
/// tasks would run a hundred and forty-seven day-computations against one GRDB
/// writer while the athlete is still typing.
///
/// PENDING is the union of every request since the running pass took work. A
/// pass is one window read and one write (W2), so a request that lands during
/// it simply waits and runs next; nothing is dropped and nothing is shortened.
///
/// ── AND WHY THE GENERATION IS PUBLISHED ONLY ON COMPLETION ──────────────────
/// `AppEnvironment.rescoreGeneration` is what four screens key their reload on.
/// Publishing per day would reload History forty-nine times for one edit, each
/// a full ledger read on the main actor. A cascade's whole point is that the
/// numbers agree when it ends, so the end is the only honest moment to say so.
public actor RescoreQueue {

    private let database: AppDatabase
    private let userId: String
    private let calendar: Calendar
    /// The clock, as a parameter.
    ///
    /// Every dated rule in this codebase takes `today` rather than reading one
    /// — `Levers.leverForDate` says so in as many words — because a rule that
    /// asks the wall what day it is cannot be tested and cannot be photographed
    /// twice with the same answer. The cascade's END is a date, so it needs the
    /// same treatment; the default is the real clock.
    private let now: @Sendable () -> Date
    /// Called when a run COMPLETES, never per day.
    private let onRun: @Sendable (Rescore.Run) async -> Void

    /// What is still owed: the earliest date anyone asked for, and the LATEST
    /// day any of those requests reaches.
    ///
    /// ── WHY BOTH ENDS, AND NOT JUST THE EARLIEST ────────────────────────────
    /// Folding two requests to `min(from)` alone is only the union when the
    /// earlier one already reaches today. It does not when the earlier edit is
    /// more than 48 days old — which is the case this file exists for. With
    /// today at 1 October, an edit on 1 August covers to 18 September and an
    /// edit on 20 September covers to 1 October; run from the minimum alone and
    /// the run stops on the 18th, and twelve days nobody will ever look at
    /// again keep a score for a workout that changed. So `from` folds with
    /// `min` and `through` with `max`, and the run walks the whole union.
    private var pending: Work?

    struct Work {
        var from: String
        var through: String
        var reason: Rescore.Reason

        /// Union with another request. Neither end may shrink — and a manual
        /// or migration request keeps its reason, because the app clears the
        /// stale mark and the sleep-v2 flag on THAT reason's completion. A
        /// door request that happened to be pending when Recompute was tapped
        /// must not relabel the run it merged into.
        mutating func absorb(_ other: Work) {
            from = Swift.min(from, other.from)
            through = Swift.max(through, other.through)
            if other.reason == .manual || other.reason == .migration { reason = other.reason }
        }
    }
    /// True from the moment a drain starts until it has nothing left — the thin
    /// hint a view can show, and the guard that keeps one drain at a time.
    public private(set) var isRescoring = false
    /// The running drain, so `stop` has something to cancel and await.
    private var drainTask: Task<Void, Never>?
    private var stopped = false

    public init(
        database: AppDatabase,
        userId: String,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        onRun: @escaping @Sendable (Rescore.Run) async -> Void
    ) {
        self.database = database
        self.userId = userId
        self.calendar = calendar
        self.now = now
        self.onRun = onRun
    }

    /// Ask for everything from `date` forward to be rewritten. Returns at once;
    /// a call while a run is going updates the pending mark instead of starting
    /// a second run.
    public func request(from date: String, reason: Rescore.Reason) {
        let days = Rescore.days(from: date, today: LogicalDayISO.string(now(), calendar: calendar))
        // A date with no days to rewrite (a session dated tomorrow — a swap) is
        // not an error and is not work either.
        guard let first = days.first, let last = days.last else { return }
        let work = Work(from: first, through: last, reason: reason)
        if pending == nil { pending = work } else { pending?.absorb(work) }
        guard !isRescoring else { return }
        isRescoring = true
        drainTask = Task { await self.drain() }
    }

    /// Ask for an explicit range — `Rescore.days` clamps an edit to its
    /// 48-day reach, and a formula change reaches every stored day. Clamped
    /// to today at the far end; empty or inverted ranges are not work.
    public func request(from: String, through: String, reason: Rescore.Reason) {
        let today = LogicalDayISO.string(now(), calendar: calendar)
        let dates = Rescore.dates(from: from, through: Swift.min(through, today))
        guard let first = dates.first, let last = dates.last else { return }
        let work = Work(from: first, through: last, reason: reason)
        if pending == nil { pending = work } else { pending?.absorb(work) }
        guard !isRescoring else { return }
        isRescoring = true
        drainTask = Task { await self.drain() }
    }

    /// Abandon the cascade. Called when the user signs out.
    ///
    /// ── WHY DROPPING THE REFERENCE IS NOT ENOUGH ────────────────────────────
    /// `drain` runs in an UNSTRUCTURED task that retains this actor, so
    /// releasing the queue leaves it writing — for up to forty-nine more days,
    /// keyed on the previous user's id, into a store the next user is already
    /// signing in to. It also keeps queuing `daily_scores` upserts that the new
    /// session's RLS will reject, and keeps bumping a generation that belongs
    /// to somebody else's screens. Awaited, like `SyncCoordinator.stop`.
    public func stop() async {
        stopped = true
        pending = nil
        drainTask?.cancel()
        _ = await drainTask?.value
        drainTask = nil
        isRescoring = false
    }

    /// Await the queue going idle. Tests and the gate; the app never waits.
    public func settle() async {
        while isRescoring { await Task.yield() }
    }

    private func drain() async {
        defer { isRescoring = false }
        while !stopped, let work = takePending() {
            guard var run = await runOnce(work) else { continue }
            // Two passes of one logical cascade must not flicker the hint off
            // between them: the caller keys it on this, not on a second read.
            run.hasMore = pending != nil
            guard !stopped else { return }
            await onRun(run)
        }
    }

    private func takePending() -> Work? {
        defer { pending = nil }
        return pending
    }

    /// One pass over the range: one window read, one write.
    ///
    /// A request that lands while this runs waits for it — the actor is busy
    /// in a synchronous store call — and is folded into the NEXT pass by
    /// `drain`. Nothing is dropped and nothing is shortened; the old "give way
    /// between days" is gone because there are no longer days to give way
    /// between, and a 49-day pass is the cost of one day's read used to be.
    private func runOnce(_ work: Work) async -> Rescore.Run? {
        let days = Rescore.dates(from: work.from, through: work.through)
        var written = 0
        var failed = 0
        // A throw here is a broken store, not a bad day. It IS counted, so a
        // cascade that failed outright cannot report success.
        //
        // ── ALL OR NOTHING, ON PURPOSE ──────────────────────────────────────
        // The per-day loop this replaced committed each day on its own, so one
        // broken day cost one day. One transaction (decision 17) means a throw
        // anywhere costs the whole pass — every day is counted failed, the
        // generation does not move, and the range stays queued in the ledger
        // as failed rather than half-written. A cascade that lands half its
        // days is a set of scores that disagree with each other, which is the
        // one state the cascade exists to prevent.
        do {
            written = try database.rescoreWindow(
                userId: userId, dates: days, now: now(), calendar: calendar, force: true
            ).count
        } catch {
            failed = days.count
        }
        if stopped { return nil }
        return Rescore.Run(
            from: work.from, through: days.last ?? work.from,
            written: written, failed: failed, reason: work.reason
        )
    }
}
