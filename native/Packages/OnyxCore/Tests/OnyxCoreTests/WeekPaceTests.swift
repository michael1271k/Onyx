import Testing
@testable import OnyxCore

/// The Sunday-morning bug, pinned.
///
/// Every case here is a week the Train tab printed something false about, or a
/// window it has to keep straight to go on printing something true.
@Suite("Week pace — comparing a partial week against a finished one")
struct WeekPaceTests {

    /// A week that starts on MONDAY, so "Wednesday is three days in" is
    /// arithmetic rather than a coincidence of where the fixture starts.
    private let monday = "2026-09-07"
    private static let week = ["2026-09-07", "2026-09-08", "2026-09-09", "2026-09-10",
                               "2026-09-11", "2026-09-12", "2026-09-13"]
    /// The same seven weekdays, one week earlier.
    private static let lastWeek = ["2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03",
                                   "2026-09-04", "2026-09-05", "2026-09-06"]

    // MARK: - The window

    @Test("the first day of the week is one day in, not zero and not seven")
    func elapsedOnTheFirstDay() {
        #expect(WeekPace.elapsedDays(today: monday, weekStart: monday) == 1)
    }

    @Test("Wednesday is three days in")
    func elapsedMidWeek() {
        #expect(WeekPace.elapsedDays(today: "2026-09-09", weekStart: monday) == 3)
    }

    @Test("the last day of the week is the whole week")
    func elapsedOnTheLastDay() {
        #expect(WeekPace.elapsedDays(today: "2026-09-13", weekStart: monday) == 7)
    }

    /// Neither is a state the tab can reach, and neither may produce a prefix
    /// that runs off an end of last week.
    @Test("a date outside the week clamps instead of running backwards or past the end")
    func elapsedClamps() {
        #expect(WeekPace.elapsedDays(today: "2026-09-06", weekStart: monday) == 1)
        #expect(WeekPace.elapsedDays(today: "2026-09-20", weekStart: monday) == 7)
        #expect(WeekPace.elapsedDays(today: "not-a-date", weekStart: monday) == 7)
    }

    // MARK: - The delta

    /// THE BUG. Sunday morning, nothing lifted yet, and last week was a full
    /// five sessions — the old rule printed the whole of last week as a loss.
    @Test("the first morning of the week is not 30 tonnes down")
    func sundayIsNotACollapse() {
        let previous = Dictionary(uniqueKeysWithValues: Self.lastWeek.dropFirst().prefix(5).map { ($0, 6_000.0) })
        let delta = WeekPace.delta(
            currentKg: 0, previousByDate: previous,
            previousDates: Self.lastWeek, elapsedDays: 1
        )
        // Last week rested its own first day too, so the matched stretch is
        // empty on both sides: nothing to say, and certainly not −30,000.
        #expect(delta == nil)
    }

    /// The other half of the same morning, and it is NOT a nil: a first day
    /// that was trained last week and has not been trained this week is a real
    /// shortfall at the same point, and hiding it would be the opposite lie.
    @Test("a first day that was trained last week reports the honest shortfall")
    func sundayAgainstATrainedSunday() {
        let delta = WeekPace.delta(
            currentKg: 0, previousByDate: [Self.lastWeek[0]: 5_000],
            previousDates: Self.lastWeek, elapsedDays: 1
        )
        #expect(delta == -5_000)
    }

    @Test("Wednesday compares three days against three, not three against seven")
    func wednesdayComparesThreeDays() {
        let previous = Dictionary(uniqueKeysWithValues: Self.lastWeek.map { ($0, 4_000.0) })
        let delta = WeekPace.delta(
            currentKg: 12_000, previousByDate: previous,
            previousDates: Self.lastWeek, elapsedDays: 3
        )
        // 12,000 against last week's first three days (12,000) — level.
        // The old rule subtracted all seven (28,000) and reported −16,000.
        #expect(delta == 0)
    }

    @Test("a week with no week behind it has no delta")
    func noPreviousWeek() {
        #expect(WeekPace.delta(
            currentKg: 9_000, previousByDate: [:],
            previousDates: Self.lastWeek, elapsedDays: 4
        ) == nil)
    }

    @Test("two empty stretches are nothing to say, not a signed zero")
    func bothSidesEmpty() {
        #expect(WeekPace.delta(
            currentKg: 0, previousByDate: [Self.lastWeek[5]: 7_000],
            previousDates: Self.lastWeek, elapsedDays: 2
        ) == nil)
    }

    @Test("the full week is the same function with the whole prefix")
    func fullWeekIsTheSameRule() {
        let previous = Dictionary(uniqueKeysWithValues: Self.lastWeek.prefix(4).map { ($0, 5_000.0) })
        #expect(WeekPace.delta(
            currentKg: 25_000, previousByDate: previous,
            previousDates: Self.lastWeek, elapsedDays: 7
        ) == 5_000)
    }

    // MARK: - The projection

    @Test("two of five days done projects the week at two and a half times the work")
    func paceProjects() {
        #expect(WeekPace.pace(tonnageKg: 12_000, elapsedTrainingDays: 2, plannedTrainingDays: 5) == 30_000)
    }

    /// A Sunday whose first training day has not arrived has no rate. The
    /// division that would produce one is the crash this guards.
    @Test("zero elapsed training days does not divide by zero")
    func paceNeedsADenominator() {
        #expect(WeekPace.pace(tonnageKg: 12_000, elapsedTrainingDays: 0, plannedTrainingDays: 5) == nil)
    }

    @Test("a week that has begun but lifted nothing projects nothing, not zero")
    func paceNeedsANumerator() {
        #expect(WeekPace.pace(tonnageKg: 0, elapsedTrainingDays: 2, plannedTrainingDays: 5) == nil)
    }

    /// A week of pure rest — every day overridden — asks for nothing, so there
    /// is nothing to project onto.
    @Test("a week that plans no training day has no projection")
    func paceNeedsAPlan() {
        #expect(WeekPace.pace(tonnageKg: 12_000, elapsedTrainingDays: 2, plannedTrainingDays: 0) == nil)
    }

    /// Missing a session has to pull the projection DOWN — the denominator is
    /// the days the plan asked for, not the days that were attended.
    @Test("a skipped day lowers the projection rather than leaving it flat")
    func paceCountsSkippedDays() {
        let attended = WeekPace.pace(tonnageKg: 12_000, elapsedTrainingDays: 2, plannedTrainingDays: 5)
        let planned = WeekPace.pace(tonnageKg: 12_000, elapsedTrainingDays: 3, plannedTrainingDays: 5)
        #expect(planned! < attended!)
        #expect(planned == 20_000)
    }
}
