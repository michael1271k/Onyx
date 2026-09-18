import Foundation
import Testing
@testable import OnyxCore

@Suite("Week so far — the one change worth naming")
struct WeekSoFarGoldenTests {
    struct In: Decodable { let cur: WeekTotals; let prev: WeekTotals }

    @Test("biggestChange matches, label, text and direction")
    func matches() throws {
        let fixture = try GoldenFixture<In, WeekChange?>.load("week-so-far")
        #expect(fixture.cases.count >= 18)
        for c in fixture.cases {
            #expect(WeekSoFar.biggestChange(c.input.cur, c.input.prev) == c.expected, Comment(rawValue: c.name))
        }
    }

    @Test("a week with no training days due is never ready; one logged short is not ready")
    func ready() {
        let train: (String) -> Bool = { ["2026-08-31", "2026-09-01", "2026-09-03"].contains($0) }
        #expect(!WeekReady.isReady(weekStart: "2026-08-30", logged: [], today: "2026-08-30", isTrainingDay: train))
        #expect(WeekReady.isReady(weekStart: "2026-08-30", logged: ["2026-08-31", "2026-09-01"], today: "2026-09-02", isTrainingDay: train))
        #expect(!WeekReady.isReady(weekStart: "2026-08-30", logged: ["2026-08-31"], today: "2026-09-02", isTrainingDay: train))
        #expect(WeekReady.isComplete(weekStart: "2026-08-30", today: "2026-09-06"))
        #expect(!WeekReady.isComplete(weekStart: "2026-08-30", today: "2026-09-05"))
    }
}

@Suite("Schedule-aware readiness — the coach headline")
struct ScheduleReadinessGoldenTests {
    struct In: Decodable { let base: ReadinessResult?; let ctx: ScheduleReadinessContext }

    /// 64 = the (base × dayLabel × logged × mode × reentry) sweep, none of
    /// which names a plan, plus 2 hand-written cases that do — the rest line
    /// stopped being one athlete's plan name and became the caller's.
    @Test("every (base, schedule, mode) cell matches")
    func matches() throws {
        let fixture = try GoldenFixture<In, ReadinessResult?>.load("readiness-schedule")
        #expect(fixture.cases.count == 64 + 2)
        for c in fixture.cases {
            #expect(ScheduleReadiness.apply(c.input.base, c.input.ctx) == c.expected, Comment(rawValue: c.name))
        }
    }
}
