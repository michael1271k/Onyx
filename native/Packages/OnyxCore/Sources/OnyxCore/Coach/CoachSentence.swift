import Foundation

/// The Mega Widget's one sentence — a rule table, never a model call (W7, A8).
///
/// ── WHY THIS IS RULES AND NOT A PROMPT ───────────────────────────────────────
/// The sentence is the only piece of prose on the dashboard and it appears
/// under a ring that says how the day is going. An offline gym app must not
/// need a server to say "rest day needed": the tile renders in a widget
/// extension, on a phone in a basement, at 06:00 before anything has synced.
/// A sentence that arrives late — or not at all — is worse than no sentence,
/// because the ring above it has already drawn.
///
/// Rules are also the only form this can take and still be TESTABLE. Every
/// branch below has a fixture (`coach-sentence.json`), so "what does the app
/// say when the battery is flat and the load is spiking" is a question with one
/// answer that a diff can change on purpose and nothing can change by accident.
///
/// ── THE ORDER IS THE WHOLE DESIGN ────────────────────────────────────────────
/// One line, one claim. The table is ordered by how much the reading should
/// change what the athlete does today, most first, and the FIRST match wins —
/// so a day that is simultaneously flat, spiking and short of sleep says the
/// thing that matters most rather than three things badly. Nothing here
/// averages; nothing here concatenates.
///
/// Thresholds are borrowed, never invented: the ACWR onset and saturation are
/// `Readiness.constants`' (Williams 2017), the debt bands are `SleepDebt.band`'s,
/// the stress bands are `Stress.band`'s, and the battery's 60/30 cuts are the
/// ones `Color.onyx.battery` already paints with — so the sentence and the
/// colour of the figure beside it can never disagree about which band a day is
/// in.
public enum CoachSentence {

    /// The four dimensions, every one optional. Optional is not a formality:
    /// a new account has none of them, and a day before the first sync has
    /// none either.
    public struct Inputs: Codable, Sendable, Equatable {
        /// The v9 battery, 0…100.
        public var batteryPct: Double?
        /// EWMA acute-over-chronic sRPE load. Nil until there is enough history
        /// (`Readiness.loadSignal` states the rule).
        public var acwr: Double?
        /// The day's stress index band, or nil when nothing answered.
        public var stress: StressBand?
        /// The decayed 14-night shortfall, hours, ≥ 0.
        public var sleepDebtHours: Double?

        public init(
            batteryPct: Double? = nil, acwr: Double? = nil,
            stress: StressBand? = nil, sleepDebtHours: Double? = nil
        ) {
            self.batteryPct = batteryPct
            self.acwr = acwr
            self.stress = stress
            self.sleepDebtHours = sleepDebtHours
        }
    }

    // MARK: - The cuts

    /// Below this the battery is painted `danger` and the day is a rest day.
    public static let batteryLow = 30.0
    /// At or above this the battery is painted `good`.
    public static let batteryGood = 60.0

    // MARK: - The table

    /// One sentence. Deterministic, total, and never empty.
    public static func sentence(_ i: Inputs) -> String {
        let r = Readiness.constants

        // 0. Nothing at all. Said plainly rather than guessed at — a tile that
        //    invents a verdict for an account with no data is the one tile
        //    nobody can correct.
        if i.batteryPct == nil, i.acwr == nil, i.stress == nil, i.sleepDebtHours == nil {
            return "Nothing is known about today yet."
        }

        let debtBand = i.sleepDebtHours.map(SleepDebt.band)

        // 1. A flat battery outranks everything. It is the composite the other
        //    three already feed into, so when it is this low the reasons are
        //    already inside it and naming one of them would be arbitrary.
        if let b = i.batteryPct, b < batteryLow {
            return "Battery \(pct(b)). Rest day needed."
        }

        // 2. A spiking load is the one reading with an injury attached to it.
        //    At or past saturation the drain is capped — the model has stopped
        //    being able to say how much worse it is getting.
        if let a = i.acwr, a >= r.acwrSaturation {
            return "Load is spiking at \(ratio(a)). Hold the week where it is."
        }

        // 3. Overreached is the top stress band, and it is a self-report as
        //    much as a signal — the athlete has already said this.
        if i.stress == .overreached {
            return "Stress is overreached. Train light and sleep early."
        }

        // 4. Past the oxide band the bank is deep enough that a night will not
        //    clear it, which is what makes it worth a sentence of its own.
        if let d = i.sleepDebtHours, debtBand == "oxide" {
            return "\(hours(d)) of sleep debt. Bank an early night before anything heavy."
        }

        // 5. Climbing, not spiking: past the onset the drain has started but
        //    the week is still recoverable.
        if let a = i.acwr, a >= r.acwrOnset {
            return "Load is climbing at \(ratio(a)). Keep this week flat."
        }

        // 6. High stress with the load in band — a life week, not a training
        //    week, and the advice is different for it.
        if i.stress == .high {
            return "Stress is high. Keep the session short and finish it."
        }

        // 7. A middling battery is the "train light" case the readiness coach
        //    already names, said with the number behind it.
        if let b = i.batteryPct, b < batteryGood {
            return "Battery \(pct(b)). Train light today."
        }

        // 8. Gold debt on an otherwise fine day: worth mentioning precisely
        //    BECAUSE nothing else is wrong, which is when it can still be paid.
        if let d = i.sleepDebtHours, debtBand == "gold" {
            return "\(hours(d)) of sleep debt is the only thing behind. Train as planned."
        }

        // 9. Everything that is known is in band.
        if let b = i.batteryPct, b >= batteryGood {
            return "Battery \(pct(b)) and nothing is behind. Train hard."
        }

        // 10. Something was known, none of it tripped, and the battery was not
        //     among it — a day with a stress reading and no score, which is
        //     every day before the first scoring pass of the morning.
        return "Nothing is flagged today."
    }

    // MARK: - Formatting
    //
    // Whole percents, one decimal on a ratio and one on an hour count. The
    // sentence sits under a ring at caption size: a second decimal is three
    // more glyphs on a line that has to fit a phone, and none of these
    // readings is accurate to one.

    static func pct(_ v: Double) -> String { "\(Int(v.rounded()))%" }

    static func ratio(_ v: Double) -> String { String(format: "%.2f", v) }

    static func hours(_ v: Double) -> String {
        let rounded = (v * 10).rounded() / 10
        // "6 h", not "6.0 h" — a whole number of hours reads as a count, and
        // the trailing zero claims a precision the bank does not have.
        return rounded == rounded.rounded()
            ? "\(Int(rounded)) h"
            : String(format: "%.1f h", rounded)
    }
}
