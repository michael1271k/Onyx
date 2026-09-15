import Testing
import Foundation
@testable import Onyx

/// `restCountdown` is the guard in front of every `Text(timerInterval:)` in the
/// app, and the reason it exists is that the alternative crashes.
///
/// ── WHY A DATE IN THE PAST IS THE NORMAL CASE, NOT THE EDGE CASE ────────────
/// `Text(timerInterval:)` traps on an inverted range — "Fatal error: Range
/// requires lowerBound <= upperBound" — and `restEndsAt` goes stale by
/// construction on all four surfaces that read it:
///
///   · the Lock Screen card and the Dynamic Island are read while the phone is
///     LOCKED, so the app is suspended and nothing clears the date at expiry;
///   · the logger's nav-bar capsule is cleared by a `.task(id:)` that belongs to
///     the logger's own view — and leaving the logger (which keeps the session
///     running, by design) cancels it. Rest for 90 s on the Workout tab, resume,
///     and the capsule renders a deadline that passed.
///
/// That last one shipped through Wave 2.12: the fix went to three surfaces and
/// missed the one that is hardest to reach and easiest to hit.
@Suite("Rest countdown")
struct RestCountdownTests {

    @Test("A future deadline becomes a forward range")
    func futureIsARange() {
        let endsAt = Date().addingTimeInterval(90)
        let range = restCountdown(endsAt)
        let unwrapped = try! #require(range)
        #expect(unwrapped.upperBound == endsAt)
        #expect(unwrapped.lowerBound <= unwrapped.upperBound)
    }

    @Test("A deadline that has passed is nil, not an inverted range")
    func pastIsNil() {
        #expect(restCountdown(Date().addingTimeInterval(-1)) == nil)
        #expect(restCountdown(Date().addingTimeInterval(-86_400)) == nil)
    }

    @Test("No rest is nil")
    func nilIsNil() {
        #expect(restCountdown(nil) == nil)
    }

    /// The property that actually matters: whatever comes back can be handed to
    /// `Text(timerInterval:)` without trapping.
    @Test("Every range it returns is one Text(timerInterval:) accepts")
    func everyRangeIsWellFormed() {
        for offset in stride(from: -600.0, through: 600.0, by: 7.5) {
            guard let range = restCountdown(Date().addingTimeInterval(offset)) else { continue }
            #expect(range.lowerBound <= range.upperBound)
        }
    }

    @Test("A total puts the lower bound exactly total seconds before endsAt")
    func totalSetsTheLowerBound() {
        let endsAt = Date().addingTimeInterval(5)
        let range = restCountdown(endsAt, total: 90)
        let unwrapped = try! #require(range)
        #expect(abs(unwrapped.lowerBound.timeIntervalSince(endsAt) - -90) < 0.01)
        #expect(unwrapped.upperBound == endsAt)
    }

    @Test("No total keeps the lower bound at now")
    func nilTotalKeepsNow() {
        let endsAt = Date().addingTimeInterval(90)
        let range = restCountdown(endsAt, total: nil)
        let unwrapped = try! #require(range)
        #expect(abs(unwrapped.lowerBound.timeIntervalSinceNow) < 0.5)
    }

    @Test("A past deadline is still nil, total or not")
    func pastIsNilEvenWithTotal() {
        #expect(restCountdown(Date().addingTimeInterval(-1), total: 90) == nil)
    }

    @Test("Every total in the stride yields an ordered range")
    func everyTotalIsWellFormed() {
        let endsAt = Date().addingTimeInterval(45)
        for total in [0, 1, 30, 90, 600] {
            let range = restCountdown(endsAt, total: total)
            let unwrapped = try! #require(range)
            #expect(unwrapped.lowerBound <= unwrapped.upperBound)
        }
    }

    /// A total shorter than the actual remaining time clamps to `now` rather
    /// than landing `endsAt − total` in the future — the case that only the
    /// `min(..., now)` clamp handles. Pinned at `now`, not at `endsAt − total`,
    /// so deleting the clamp fails this test specifically.
    @Test("A total shorter than the remaining time clamps the lower bound to now")
    func shortTotalClampsToNow() {
        let endsAt = Date().addingTimeInterval(45)
        let range = restCountdown(endsAt, total: 1)
        let unwrapped = try! #require(range)
        #expect(abs(unwrapped.lowerBound.timeIntervalSinceNow) < 0.01)
    }

    /// ── THE +15 s GATE, AS ARITHMETIC ───────────────────────────────────────
    /// The defect this whole helper exists for: pressing +15 s used to send the
    /// bar back to FULL, because the range was `now...endsAt` and the span was
    /// recomputed to the new, longer remainder. The fill is
    /// `(now − lower) / (upper − lower)`, so the test is that the LOWER BOUND
    /// DOES NOT MOVE when a nudge adds to both the deadline and the total —
    /// which is what `LoggerModel.adjustRest` and `RestNudgeIntent` both do.
    ///
    /// Elapsed is therefore unchanged and the denominator grows, so the fill
    /// goes DOWN a little rather than resetting. A test and not just a
    /// recording, because a recording cannot fail a build.
    @Test("+15 s leaves the bar's origin where it was, so the fill falls instead of resetting")
    func nudgeDoesNotResetTheBar() throws {
        // 75 s into a 150 s rest: half gone.
        let endsAt = Date().addingTimeInterval(75)
        let before = try #require(restCountdown(endsAt, total: 150))

        // +15 s moves the deadline AND the total, together.
        let after = try #require(restCountdown(endsAt.addingTimeInterval(15), total: 165))

        // The origin is the same instant — this is the whole fix.
        #expect(abs(before.lowerBound.timeIntervalSince(after.lowerBound)) < 0.01)

        func fill(_ range: ClosedRange<Date>) -> Double {
            let span = range.upperBound.timeIntervalSince(range.lowerBound)
            return Date().timeIntervalSince(range.lowerBound) / span
        }
        #expect(abs(fill(before) - 0.5) < 0.02)
        // Falls to 75/165, and emphatically is not 0 (a reset bar reads full
        // under `countsDown: true`, i.e. a fraction of zero elapsed).
        #expect(abs(fill(after) - 0.4545) < 0.02)
        #expect(fill(after) < fill(before))
    }

    /// The same nudge WITHOUT a total — the behaviour being replaced, kept as a
    /// test so the regression is visible rather than remembered. The lower
    /// bound is `now` both times, so every press restarts the bar at empty and
    /// the fill can never be anything but zero-elapsed.
    @Test("without a total the origin follows now, which is the bug the total fixes")
    func nudgeWithoutTotalResetsTheOrigin() throws {
        let endsAt = Date().addingTimeInterval(75)
        let before = try #require(restCountdown(endsAt))
        let after = try #require(restCountdown(endsAt.addingTimeInterval(15)))
        #expect(abs(before.lowerBound.timeIntervalSinceNow) < 0.01)
        #expect(abs(after.lowerBound.timeIntervalSinceNow) < 0.01)
    }
}
