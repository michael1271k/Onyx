import Testing
import Foundation
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Holiday — a one-day nutrition context, exactly like Event: a stamp only,
// not a range, no scoring change, does not suspend the step goal.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Context — Holiday")
struct ContextHolidayTests {

    /// The invariant that makes `Context.rangeLine`'s `meta[mode]!` safe: every
    /// case the enum can produce has a meta entry, forever, not just today.
    @Test("Context.meta holds an entry for every ContextMode case")
    func metaCoversEveryCase() {
        for mode in ContextMode.allCases {
            #expect(Context.meta[mode] != nil, "missing meta for \(mode)")
        }
    }

    @Test("Holiday reads back from its day label and behaves like Event")
    func holidayBehavesLikeEvent() {
        #expect(Context.fromDayLabel("Holiday") == .holiday)
        #expect(Context.isRangeMode(.holiday) == false)
        #expect(Context.scoringContext(for: .holiday) == Context.scoringContext(for: .event))
        #expect(Context.suspendsStepGoal(.holiday) == false)
    }

    @Test("ExceptionDay offers Holiday as a reason")
    func exceptionDayOffersHoliday() {
        #expect(ExceptionDay.reasons.contains("Holiday"))
        #expect(ExceptionDay.isException("Holiday"))
    }
}
