import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// SessionRun — the clock ledger, and the invariant that stops `0:00` being a
// lie.
//
// `PauseControlling.elapsed` is `max(0, (pausedAt ?? now) − (startedAt +
// pausedTotal))`. That clamp is only safe while `pausedTotal ≤ now − startedAt`,
// and nothing enforced it: an OPEN pause grows at wall-clock rate for as long as
// the app is dead. So the whole suite is one property with a handful of named
// corners.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("SessionRun — the clock ledger")
struct SessionRunTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    /// What the hero would draw, given a resolved ledger.
    private func elapsed(_ r: SessionRun.Resolved, startedAt: Date) -> TimeInterval {
        max(0, (r.pausedAt ?? now).timeIntervalSince(startedAt.addingTimeInterval(r.pausedTotal)))
    }

    // MARK: The invariant

    @Test("pausedTotal never exceeds the wall interval, over a wide grid")
    func pausedTotalIsAlwaysWithinTheWallClock() {
        for startedMinutesAgo in [0.0, 1, 5, 30, 90, 240, 600, 1_440] {
            for banked in [0.0, 60, 600, 5_400, 86_400] {
                for openMinutesAgo in [nil, 0.0, 1, 5, 14, 16, 60, 600, 1_440] as [Double?] {
                    let startedAt = ago(startedMinutesAgo)
                    let run = SessionRun.resolve(
                        startedAt: startedAt,
                        banked: banked,
                        pauseOpenedAt: openMinutesAgo.map { ago($0) },
                        now: now
                    )
                    let wall = now.timeIntervalSince(startedAt)
                    #expect(run.pausedTotal >= 0)
                    #expect(
                        run.pausedTotal <= wall + 1e-9,
                        "started \(startedMinutesAgo)m banked \(banked) open \(String(describing: openMinutesAgo)): \(run.pausedTotal) > \(wall)"
                    )
                    // Which is the whole point: `timerOrigin` is never in the
                    // future, so `elapsed`'s clamp can never fire.
                    #expect(startedAt.addingTimeInterval(run.pausedTotal) <= now.addingTimeInterval(1e-9))
                }
            }
        }
    }

    @Test("a start in the future does not produce a negative ledger")
    func futureStartIsSurvivable() {
        // A clock that stepped, or a hand-typed start. Not representable on the
        // deck, but `resolve` is total or it is not a guarantee.
        let run = SessionRun.resolve(
            startedAt: now.addingTimeInterval(600), banked: 300, pauseOpenedAt: nil, now: now
        )
        #expect(run.pausedTotal == 0)
    }

    @Test("a non-finite banked total is a corrupt row, not a long pause")
    func nonFiniteBankedIsZero() {
        for bad in [Double.nan, .infinity, -.infinity, -600] {
            let run = SessionRun.resolve(startedAt: ago(60), banked: bad, pauseOpenedAt: nil, now: now)
            #expect(run.pausedTotal == 0, "banked \(bad)")
        }
    }

    // MARK: The report that named this wave

    @Test("a session terminated while paused comes back RUNNING, not at 0:00")
    func abandonedPauseDoesNotEatTheWorkout() {
        // 18:40: ninety minutes in, paused, then iOS jetsams the app.
        // 07:00 next morning: reopened. The old read imported `now − 18:40` as
        // pause — over twelve hours against a ninety-minute wall clock — so
        // `timerOrigin` landed in the future and the hero printed `0:00` on a
        // session whose sets had all restored.
        let startedAt = ago(90)
        let run = SessionRun.resolve(
            startedAt: startedAt, banked: 0, pauseOpenedAt: ago(75), now: now
        )
        #expect(run.abandonedPause, "75 minutes is past the ceiling")
        #expect(run.pausedAt == nil, "the deck comes back running")
        #expect(run.pausedTotal == SessionRun.openPauseCeilingSec, "the ceiling is banked, not the whole night")
        #expect(elapsed(run, startedAt: startedAt) == 75 * 60, "90 minutes less the 15 credited as rest")
    }

    @Test("a pause that is still plausible is still a pause")
    func liveePauseIsHeld() {
        let startedAt = ago(60)
        let run = SessionRun.resolve(
            startedAt: startedAt, banked: 120, pauseOpenedAt: ago(5), now: now
        )
        #expect(!run.abandonedPause)
        #expect(run.pausedAt == now, "re-anchored to now — the open interval is already inside pausedTotal")
        #expect(run.pausedTotal == 120 + 5 * 60)
        #expect(elapsed(run, startedAt: startedAt) == (60 - 2 - 5) * 60)
    }

    @Test("the ceiling is inclusive at its own value")
    func ceilingBoundary() {
        let atCeiling = SessionRun.resolve(
            startedAt: ago(60), banked: 0, pauseOpenedAt: ago(15), now: now
        )
        #expect(!atCeiling.abandonedPause, "exactly the ceiling is still a live pause")
        #expect(atCeiling.pausedAt == now)

        let past = SessionRun.resolve(
            startedAt: ago(60), banked: 0, pauseOpenedAt: ago(15.1), now: now
        )
        #expect(past.abandonedPause)
    }

    // MARK: The clamp, and saying so

    @Test("a ledger that outran the clock is trimmed AND reported")
    func runawayLedgerIsReported() {
        // Banked alone can outrun the wall clock — two devices folding the same
        // pause, or a session whose `started_at` was corrected forward after
        // the pauses were written.
        let run = SessionRun.resolve(
            startedAt: ago(10), banked: 3_600, pauseOpenedAt: nil, now: now
        )
        #expect(run.pausedTotal == 600, "trimmed to the wall interval")
        #expect(run.clamped, "and the deck is told, rather than drawing a silent 0:00")
    }

    @Test("an ordinary ledger reports no repair")
    func ordinaryLedgerIsQuiet() {
        let run = SessionRun.resolve(startedAt: ago(60), banked: 300, pauseOpenedAt: nil, now: now)
        #expect(!run.clamped)
        #expect(!run.abandonedPause)
        #expect(run.pausedTotal == 300)
    }

    @Test("a session paused for its whole life is not a repair")
    func pausedSinceTheStartIsNotClamped() {
        // `pausedTotal == wall` exactly. Reporting that as a trim would put a
        // warning on a correct clock — which is why the test is `>` and not
        // `!=`.
        let startedAt = ago(10)
        let run = SessionRun.resolve(
            startedAt: startedAt, banked: 0, pauseOpenedAt: startedAt, now: now
        )
        #expect(run.pausedTotal == 600)
        #expect(!run.clamped)
        #expect(!run.abandonedPause, "ten minutes is under the ceiling — a real, live pause")
        #expect(run.pausedAt == now)
        #expect(elapsed(run, startedAt: startedAt) == 0, "and 0:00 here is the truth, not a clamp")
    }

    @Test("no pause at all is the common case and costs nothing")
    func noPause() {
        let startedAt = ago(45)
        let run = SessionRun.resolve(startedAt: startedAt, banked: 0, pauseOpenedAt: nil, now: now)
        #expect(run.pausedTotal == 0)
        #expect(run.pausedAt == nil)
        #expect(elapsed(run, startedAt: startedAt) == 45 * 60)
    }

    @Test("resolve is pure — same inputs, same answer")
    func resolveIsDeterministic() {
        let a = SessionRun.resolve(startedAt: ago(30), banked: 90, pauseOpenedAt: ago(3), now: now)
        let b = SessionRun.resolve(startedAt: ago(30), banked: 90, pauseOpenedAt: ago(3), now: now)
        #expect(a == b)
    }
}
