import Foundation

/// Comparing a week that is still running against one that has finished.
///
/// ── THE BUG THIS EXISTS TO MAKE UNREPEATABLE ────────────────────────────────
/// The Train tab's Trends door subtracted a FULL previous calendar week from a
/// PARTIAL current one. On a Sunday morning — the one moment of the week when
/// nothing could yet have been lifted — it printed the whole of last week as a
/// loss: `−30.0 t`, on a screen whose job is to tell you how the week is going.
///
/// The defect was not the sign and not the formatting. It was that the two
/// sides of a subtraction were different quantities, and nothing in the code
/// said what either window was. So the windows are named here, in the pure
/// package, with the tests that pin them — and the tab does arithmetic it
/// cannot get wrong by forgetting which half of a week it is holding.
///
/// ── AND WHY THESE ARE FUNCTIONS AND NOT A METHOD ON THE TAB ─────────────────
/// The Train tab's read is a detached pass over GRDB. Arithmetic inside it can
/// only be tested through a database, a schedule context and a seeded plan —
/// which is how a rule this small went four waves unasserted. Every input here
/// is a number or a date string.
public enum WeekPace {

    /// How many days of the week have happened, today included.
    ///
    /// Ordinal days and NOT "days that hold a session": a rest day is part of
    /// the week on both sides of a comparison, and matching on training days
    /// alone would put a Wednesday that trained against a Monday that did.
    ///
    /// Clamped into `1...span`. A `today` before the week's own start is not a
    /// representable state and a `today` after it is a week that has closed;
    /// both answer with a whole week rather than a negative prefix, which is
    /// the only answer that cannot make a caller subtract backwards. An
    /// unparseable date answers `span` for the same reason — the panel above
    /// the door has already drawn the whole week.
    public static func elapsedDays(today: String, weekStart: String, span: Int = 7) -> Int {
        guard span > 0 else { return 0 }
        guard let now = ISODate.dayNumber(today), let start = ISODate.dayNumber(weekStart) else {
            return span
        }
        return min(max(now - start + 1, 1), span)
    }

    /// This week's tonnage minus the SAME STRETCH of last week's.
    ///
    /// `previousDates` is last week in order, oldest first; `previousByDate`
    /// holds whichever of them have a session. The comparison runs over the
    /// first `elapsedDays` of them, so Wednesday compares three days to three.
    ///
    /// ── WHY NIL AND NOT ZERO, TWICE ─────────────────────────────────────────
    /// Nil when there is no previous week at all (`previousByDate` empty): a
    /// delta against a week that does not exist is not a gain of everything.
    /// Nil again when BOTH stretches are empty: zero is the claim that the two
    /// weeks matched, and two weeks in which nothing has happened yet have not
    /// matched — there is simply nothing to say. The door prints `—` for nil,
    /// and would print a signed zero for the second case.
    public static func delta(
        currentKg: Double, previousByDate: [String: Double],
        previousDates: [String], elapsedDays: Int
    ) -> Double? {
        guard !previousByDate.isEmpty else { return nil }
        let matched = previousDates.prefix(max(elapsedDays, 0)).reduce(0.0) { $0 + (previousByDate[$1] ?? 0) }
        guard currentKg != 0 || matched != 0 else { return nil }
        return jsRound(currentKg - matched)
    }

    /// Where the week LANDS if the rest of it goes like the part that has
    /// happened — `tonnage / elapsedTrainingDays × plannedTrainingDays`.
    ///
    /// ── THE DENOMINATOR IS THE PLAN, NOT THE ATTENDANCE ─────────────────────
    /// Elapsed TRAINING days means the days the plan asked for that have
    /// already passed, whether or not they were trained. A rate taken over
    /// "days I showed up" lets a week with one heavy Monday and three skipped
    /// days project a record, which is the same class of lie the delta above
    /// stopped telling. Missing a session has to pull the projection down.
    ///
    /// Nil on a zero denominator — a Sunday whose first training day has not
    /// arrived has no rate — and nil on an empty week, because a projection off
    /// no sessions is a number with no input rather than a forecast of nothing.
    public static func pace(
        tonnageKg: Double, elapsedTrainingDays: Int, plannedTrainingDays: Int
    ) -> Double? {
        guard elapsedTrainingDays > 0, plannedTrainingDays > 0, tonnageKg > 0 else { return nil }
        return jsRound(tonnageKg / Double(elapsedTrainingDays) * Double(plannedTrainingDays))
    }
}
