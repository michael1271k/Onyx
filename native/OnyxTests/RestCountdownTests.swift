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
}
