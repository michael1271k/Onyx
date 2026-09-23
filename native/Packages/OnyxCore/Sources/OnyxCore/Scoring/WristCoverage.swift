import Foundation

/// How long the watch was off a wrist (App Store W6).
///
/// ── THE WATCH SIMPLY STOPS WRITING ──────────────────────────────────────────
/// Nothing in HealthKit says "off wrist". A watch on its charger writes no
/// heart rate, no HRV, no sleep stages — and every reader downstream sees the
/// same nil it would see for a signal nobody measures. The one trace the gap
/// leaves is in the heart-rate series: a worn watch samples every few minutes,
/// all day and all night, and a stretch with no sample at all is a stretch
/// nobody was wearing it.
///
/// So the off-wrist time is DERIVED from the presence of heart-rate readings,
/// never from their values, and it reaches the scorer as one raw fact,
/// `ScoringInputs.offWristMin`. Everything decided from it is decided here,
/// from those inputs: whether the night was unmeasured (the battery's one
/// place that still read a missing night as zero hours) and what a readiness
/// surface says about it. One rule, one threshold, one set of inputs — the
/// battery and the sentence cannot disagree about what was missing.
public enum WristCoverage {

    /// A silence between two heart-rate readings longer than this is time off
    /// the wrist. Decided, not measured: a worn Apple Watch samples every few
    /// minutes at rest and continuously in a workout, and 30 minutes is well
    /// past any gap a worn watch leaves.
    // ponytail: one fixed threshold. If a device in Low Power Mode (which
    // samples less) reads as "off", this is the calibration knob.
    public static let offWristGap: TimeInterval = 30 * 60

    /// Off-wrist time worth acting on — for the battery AND for the sentence,
    /// which is why it is one constant. Under an hour is a shower, not a
    /// missing signal.
    public static let minimumMinutes: Double = 60

    /// The LONGEST stretch of `[from, to)` with no heart-rate reading, in
    /// minutes — 0 when no silence runs past `offWristGap`. The window's start
    /// counts as a boundary; its end does too unless `openEnded`.
    ///
    /// ── THE LONGEST, NOT THE SUM ────────────────────────────────────────────
    /// "Off your wrist for 6 h" is one absence. Summing every gap over half an
    /// hour turned a shower and a charge before bed into one invented night
    /// off the wrist.
    ///
    /// ── AND AN OPEN END IS NOT A GAP ────────────────────────────────────────
    /// A window that ends at `now` ends where the phone's copy of Health ends,
    /// and the watch delivers its samples in batches: the minutes since the
    /// last one to ARRIVE are not minutes off the wrist. `openEnded` stops at
    /// the last reading instead.
    ///
    /// Nil when the window holds NO reading at all: a watch in a drawer for
    /// the whole window and no watch are the same series, and only one of them
    /// is off a wrist. A phone-only athlete must never be told to put a watch on.
    public static func offWristMinutes(readings: [Date], from: Date, to: Date, openEnded: Bool = false) -> Double? {
        guard to > from else { return nil }
        let inside = readings.filter { $0 >= from && $0 < to }.sorted()
        guard let last = inside.last else { return nil }
        var longest: TimeInterval = 0
        var previous = from
        for reading in inside + [openEnded ? last : to] {
            let gap = reading.timeIntervalSince(previous)
            if gap > offWristGap { longest = max(longest, gap) }
            previous = reading
        }
        return longest / 60
    }

    /// No night was recorded and the watch was off the wrist long enough to
    /// explain it. `Battery.sleepQualityParts` then drops the night's two terms
    /// rather than scoring zero hours.
    ///
    /// Known limit: `offWristMin` is measured over a fixed local overnight
    /// window (`HealthSync.overnight`, 21:00 → 09:00), not over the bed —
    /// there is no bed window for a night nobody recorded. A long evening on
    /// the charger before a night worn with sleep tracking off reads as
    /// unmeasured, which errs toward "unknown", never toward a penalty.
    public static func nightUnmeasured(_ inputs: ScoringInputs) -> Bool {
        inputs.sleepHours <= 0 && (inputs.offWristMin ?? 0) >= minimumMinutes
    }

    /// The watch-measured inputs readiness reads — five, because the model
    /// reads five: last night's duration and its stages (`Battery`'s charge,
    /// `Score.sleep`), the day's HRV and resting heart rate (`Score.recovery`;
    /// the charge's z-terms roll over a week and survive one missing day), and
    /// active energy (the activity drain, `Score.activity`). Load, the
    /// session, the wellness answers and the clock are not the watch's to lose.
    public static let signalsTotal = 5

    /// How many of the five `inputs` actually carries — the same object the
    /// battery and the score were computed from.
    public static func signals(_ inputs: ScoringInputs) -> Int {
        [inputs.sleepHours > 0,
         inputs.deepMinutes + inputs.remMinutes > 0,
         inputs.hrvMs != nil,
         inputs.restingHR != nil,
         inputs.activeCal > 0].filter { $0 }.count
    }
}

/// What a readiness surface says when the watch was off the wrist and a
/// signal went missing with it. Nil otherwise — the reading is then shown as
/// the reading, with nothing to explain.
public struct OffWristNote: Codable, Sendable, Equatable {
    /// Off-wrist time, whole hours, at least 1.
    public var hours: Int
    /// How many of `WristCoverage.signalsTotal` readiness actually had.
    public var signals: Int
    /// Not on the wire: always `WristCoverage.signalsTotal`.
    public var of: Int { WristCoverage.signalsTotal }

    public init(hours: Int, signals: Int) {
        self.hours = hours
        self.signals = signals
    }

    /// Short, because it rides inside `WatchTiles` (the 2 KB wire budget).
    enum CodingKeys: String, CodingKey { case hours = "h", signals = "s" }

    /// Both conditions, or nothing: off-wrist time that cost no signal is not
    /// news, and a missing signal with the watch on the wrist is not the
    /// watch's absence (a phone with no watch, a night with tracking off).
    public static func make(_ inputs: ScoringInputs) -> OffWristNote? {
        guard let off = inputs.offWristMin, off >= WristCoverage.minimumMinutes else { return nil }
        let signals = WristCoverage.signals(inputs)
        guard signals < WristCoverage.signalsTotal else { return nil }
        return OffWristNote(hours: max(1, Int((off / 60).rounded())), signals: signals)
    }

    /// The sentence, in the founder's words.
    public var sentence: String {
        let lead = "Your watch was off your wrist for \(hours) h — "
        return signals == 0
            ? lead + "readiness has none of its \(of) watch signals."
            : lead + "readiness is from \(signals) signal\(signals == 1 ? "" : "s"), not \(of)."
    }

    /// "3 of 5" — the one short count every small face appends.
    public var signalsText: String { "\(signals) of \(of)" }

    /// The short form, for a face with one line to give.
    public var short: String { "off wrist \(hours) h · \(signalsText)" }
}
