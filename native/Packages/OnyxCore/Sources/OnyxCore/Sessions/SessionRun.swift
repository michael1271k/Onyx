import Foundation

/// The session clock's ledger, resolved — the arithmetic behind "how long have
/// I been training", with the two holes that produced a confident `0:00` shut.
///
/// ── WHY `max(0, …)` WAS THE BUG AND NOT THE GUARD ───────────────────────────
/// The hero reads `PauseControlling.elapsed`, which is
/// `max(0, (pausedAt ?? now) − (startedAt + pausedTotal))`. That clamp turns a
/// VIOLATED INVARIANT into a plausible reading: the moment `pausedTotal` grows
/// past the wall interval the timer prints `0:00`, which is indistinguishable
/// from a deck opened a second ago. The session was intact, the sets restored,
/// and the one number the athlete was watching said the workout had not
/// started.
///
/// `pausedTotal` can outgrow the wall clock because an OPEN pause has no bound:
/// `EventStore.pausedSeconds` adds `now − pauseOpenedAt` with nothing capping
/// it, and a pause is left open by any of
///
///   · the app being terminated between `pause` and `resume` (iOS jetsams a
///     backgrounded app without warning — this is the ordinary case, not the
///     exotic one),
///   · `resumeSession` throwing, which leaves `pausedAt` set and writes no
///     `resume` event, so the interval never closes, or
///   · a `resume` tapped while the model had no `sessionId` to write under.
///
/// Every one of those leaves the LOG saying "paused" while the athlete is
/// walking back to the rack. Hours later the ledger claims more time than has
/// passed.
///
/// So the invariant is stated here and enforced at the only place that can:
///
/// > `0 ≤ pausedTotal ≤ now − startedAt`, always. `timerOrigin` is therefore
/// > never in the future and `0:00` means `0:00`.
///
/// Pure and total — no clock of its own, `now` is a parameter — so the whole
/// thing is a table test rather than a device and a stopwatch.
public enum SessionRun {

    /// The longest an OPEN pause is believed.
    ///
    /// Fifteen minutes, the same figure and the same argument as
    /// `LoggerModel.restGapCeilingSec`: a heavy double can legitimately take
    /// five, and beyond a quarter of an hour the phone was not paused, it was
    /// off. Past the ceiling the pause is treated as ABANDONED — the ceiling is
    /// banked and the deck comes back RUNNING, because a session that was
    /// jetsammed at 18:40 and reopened at 07:00 the next morning was never
    /// thirteen hours of rest.
    public static let openPauseCeilingSec: TimeInterval = 900

    public struct Resolved: Equatable, Sendable {
        /// Seconds to subtract, guaranteed within `0 … wall`.
        public var pausedTotal: TimeInterval
        /// The instant the clock reads as frozen at, or nil when running.
        ///
        /// Re-anchored to `now` for a live pause rather than to when the pause
        /// began: `pausedTotal` already contains the open interval up to this
        /// instant, and anchoring to the start would count those minutes twice.
        public var pausedAt: Date?
        /// The ledger asked for more time than has passed, and was cut to fit.
        ///
        /// The deck shows this rather than swallowing it — a clock that had to
        /// be repaired is worth one line in the header, and it is the only
        /// evidence the athlete or a later reader ever gets that the log went
        /// inconsistent.
        public var clamped: Bool
        /// An open pause older than the ceiling was closed at read.
        public var abandonedPause: Bool

        public init(
            pausedTotal: TimeInterval, pausedAt: Date?,
            clamped: Bool = false, abandonedPause: Bool = false
        ) {
            self.pausedTotal = pausedTotal
            self.pausedAt = pausedAt
            self.clamped = clamped
            self.abandonedPause = abandonedPause
        }
    }

    /// Resolve the stored ledger against the wall clock.
    ///
    /// - Parameters:
    ///   - banked: seconds from pauses that have CLOSED.
    ///   - pauseOpenedAt: when the pause in progress began, or nil while running.
    public static func resolve(
        startedAt: Date, banked: TimeInterval, pauseOpenedAt: Date?, now: Date
    ) -> Resolved {
        // A non-finite total is a corrupt row, not a long pause.
        let closed = banked.isFinite ? Swift.max(0, banked) : 0
        // A start in the future is a clock that stepped; the wall interval is
        // zero rather than negative, which makes the clamp below total.
        let wall = Swift.max(0, now.timeIntervalSince(startedAt))

        var open: TimeInterval = 0
        var stillPaused = false
        var abandoned = false
        if let pauseOpenedAt {
            let elapsed = Swift.max(0, now.timeIntervalSince(pauseOpenedAt))
            if elapsed > openPauseCeilingSec {
                // Abandoned. Bank the ceiling — the rest you plausibly took
                // before the phone went away — and start the clock again.
                open = openPauseCeilingSec
                abandoned = true
            } else {
                open = elapsed
                stillPaused = true
            }
        }

        let wanted = closed + open
        let total = Swift.min(wanted, wall)
        return Resolved(
            pausedTotal: total,
            pausedAt: stillPaused ? now : nil,
            // `>` and not `!=`: equality is the ordinary case for a session
            // that has been paused since the instant it opened, and reporting
            // that as a repair would put a warning on a correct clock.
            clamped: wanted > wall,
            abandonedPause: abandoned
        )
    }
}
