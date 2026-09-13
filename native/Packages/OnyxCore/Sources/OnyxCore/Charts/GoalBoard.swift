import Foundation

/// The Goal Board — the three numbers that say whether the phase is working.
///
/// ── WHY THIS REPLACED THE COACH ─────────────────────────────────────────────
/// The Insight Coach drew correlations: "nights over 7 h precede your three
/// heaviest sessions (r = 0.71)". It was interesting and it was never
/// actionable, because nothing about the day changes on the strength of it. The
/// phase, meanwhile, has exactly one question — is the scale moving at the rate
/// the phase asked for, and when does it arrive — and nothing on Today answered
/// it.
///
/// ── THE TYPESCRIPT TWIN ARRIVED A WAVE LATE ─────────────────────────────────
/// This shipped in W5 with hand-written Swift tests and no TypeScript behind
/// it, because the row it feeds is native-only. W12 rebinds that row to
/// `TrajectorySeries` and puts the same rate and the same arrival date on a
/// widget face, so the two now have to agree to the digit in a snapshot built
/// by a different builder. the web app's `lib/charts/goalBoard.ts` is the definition and
/// `goal-board.json` is the proof; nothing about the arithmetic changed.
///
/// ── THE RATE IS A REGRESSION, NOT A DIFFERENCE ──────────────────────────────
/// Ported from `weeklyRateKg` in the web app's `lib/hooks/useEnergyBalance.ts`, and for
/// the reason stated there: two readings a fortnight apart can differ by a kilo
/// of water, so "latest minus earliest ÷ weeks" computes the rate from
/// precisely the two noisiest numbers in the window. Least squares over every
/// reading is the whole point of having weighed yourself twenty times. Under
/// three readings it returns nil — a line through two points is not a trend.
///
/// ── AND THE ETA IS MEASURED FROM THE FITTED LINE ────────────────────────────
/// Not from the last reading. The rate is a smoothed quantity and the target is
/// a fixed one; dividing a smoothed rate into a raw distance makes the ETA jump
/// by weeks whenever the morning's reading is a bad one. The line already knows
/// where today sits, so the ETA asks it.
/// ── CODABLE SINCE W12 ───────────────────────────────────────────────────────
/// `TrajectorySeries` carries one of these onto a widget face, and the golden
/// vector that pins the two together (`goal-board.json`) decodes it directly.
/// The keys are the property names and match the web app's `lib/charts/goalBoard.ts`
/// field for field, which is what makes the fixture a comparison rather than a
/// translation.
public struct GoalBoard: Codable, Sendable, Equatable {
    /// Least-squares kg per week over the trailing window. Nil under three
    /// readings.
    public var ratePerWeekKg: Double?
    /// Where the fitted line puts today — the weight the ETA is measured from.
    public var trendWeightKg: Double?
    /// The phase's signed band: negative on a cut, positive on a bulk.
    public var targetRateMinKgWk: Double?
    public var targetRateMaxKgWk: Double?
    /// The weight the phase is aiming at.
    public var targetWeightKg: Double?
    /// Weeks to that weight at the measured rate — nil when the rate is unknown,
    /// flat, or pointing the wrong way.
    public var weeksToTarget: Double?
    /// The date those weeks land on.
    public var etaISO: String?
    /// `intake − TDEE`, summed over the week so far. Negative is a deficit.
    public var weekBalanceKcal: Double?
    /// How many of the week's days had BOTH sides — a ledger over four days is
    /// not a week, and the row says which it is.
    public var weekDaysCounted: Int
    public var pace: Pace

    /// Where the measured rate sits against the phase's band.
    public enum Pace: String, Codable, Sendable, Equatable {
        /// Inside the band, or near enough that the band contains it.
        case onTrack
        /// Moving the right way, slower than asked — or not moving at all.
        case under
        /// Moving the right way, faster than asked.
        case over
        /// Moving the other way entirely.
        case reversed
        /// No rate yet, or no band to judge it against.
        case unknown
    }

    public init(
        ratePerWeekKg: Double? = nil, trendWeightKg: Double? = nil,
        targetRateMinKgWk: Double? = nil, targetRateMaxKgWk: Double? = nil,
        targetWeightKg: Double? = nil, weeksToTarget: Double? = nil, etaISO: String? = nil,
        weekBalanceKcal: Double? = nil, weekDaysCounted: Int = 0, pace: Pace = .unknown
    ) {
        self.ratePerWeekKg = ratePerWeekKg
        self.trendWeightKg = trendWeightKg
        self.targetRateMinKgWk = targetRateMinKgWk
        self.targetRateMaxKgWk = targetRateMaxKgWk
        self.targetWeightKg = targetWeightKg
        self.weeksToTarget = weeksToTarget
        self.etaISO = etaISO
        self.weekBalanceKcal = weekBalanceKcal
        self.weekDaysCounted = weekDaysCounted
        self.pace = pace
    }
}

public extension GoalBoard {

    /// One day's scale reading. A nil weight is a day with no weigh-in and is
    /// dropped, never carried forward — a carried weight would flatten the
    /// slope towards zero for free.
    struct Reading: Codable, Sendable, Equatable {
        public var date: String
        public var weightKg: Double?
        public init(date: String, weightKg: Double?) {
            self.date = date
            self.weightKg = weightKg
        }
    }

    /// One day of the energy ledger. `tdee` is `Energy.tdee`, which is nil
    /// unless BMR, active energy and intake are ALL present — see the ledger
    /// note in `useEnergyBalance`: a day with a hole contributes nothing rather
    /// than a deficit that is 400 kcal too large.
    struct EnergyDay: Codable, Sendable, Equatable {
        public var date: String
        public var intakeKcal: Double?
        public var tdeeKcal: Double?
        public init(date: String, intakeKcal: Double?, tdeeKcal: Double?) {
            self.date = date
            self.intakeKcal = intakeKcal
            self.tdeeKcal = tdeeKcal
        }
    }

    /// The least-squares slope of a weight series, in kg per week, rounded to
    /// two decimals — `weeklyRateKg` in TypeScript, to the digit.
    static func weeklyRateKg(_ readings: [Reading]) -> Double? {
        fit(readings)?.slopePerWeek
    }

    /// The line, or nil under three readings.
    static func fit(_ readings: [Reading]) -> (slopePerWeek: Double, at: (String) -> Double?)? {
        let points: [(t: Double, w: Double)] = readings.compactMap { r in
            guard let w = r.weightKg, w.isFinite, let day = ISODate.dayNumber(r.date) else { return nil }
            return (Double(day), w)
        }
        guard points.count >= 3 else { return nil }
        let n = Double(points.count)
        let mt = points.reduce(0) { $0 + $1.t } / n
        let mw = points.reduce(0) { $0 + $1.w } / n
        var num = 0.0, den = 0.0
        for p in points {
            num += (p.t - mt) * (p.w - mw)
            den += (p.t - mt) * (p.t - mt)
        }
        guard den != 0 else { return nil }
        let slope = num / den
        return (
            slopePerWeek: jsRound(slope * 7 * 100) / 100,
            at: { iso in ISODate.dayNumber(iso).map { mw + slope * (Double($0) - mt) } }
        )
    }

    /// The whole row, from the two windows and the phase's goals.
    ///
    /// - Parameters:
    ///   - readings: the trailing weigh-in window, any order.
    ///   - energy: the days of the CURRENT week, up to and including today.
    ///   - today: the logical day the ETA counts from.
    static func build(
        readings: [Reading],
        energy: [EnergyDay],
        targetWeightKg: Double?,
        rateMinKgWk: Double?,
        rateMaxKgWk: Double?,
        today: String
    ) -> GoalBoard {
        var board = GoalBoard(
            targetRateMinKgWk: rateMinKgWk,
            targetRateMaxKgWk: rateMaxKgWk,
            targetWeightKg: targetWeightKg
        )

        if let line = fit(readings) {
            board.ratePerWeekKg = line.slopePerWeek
            board.trendWeightKg = line.at(today).map { jsRound($0 * 10) / 10 }
        }

        // ── The ETA ─────────────────────────────────────────────────────────
        // Only when the line is pointing at the target. A cut whose scale is
        // going up has no arrival date, and reporting a negative number of
        // weeks — or an absolute value of one — would be the app inventing an
        // answer it does not have.
        if let rate = board.ratePerWeekKg, rate != 0,
           let target = targetWeightKg, let current = board.trendWeightKg {
            let distance = target - current
            if distance == 0 {
                board.weeksToTarget = 0
                board.etaISO = today
            } else if (distance > 0) == (rate > 0) {
                let weeks = distance / rate
                board.weeksToTarget = jsRound(weeks * 10) / 10
                board.etaISO = ISODate.addDays(today, Int(jsRound(weeks * 7)))
            }
        }

        // ── The week's ledger ───────────────────────────────────────────────
        let counted = energy.filter { $0.intakeKcal != nil && $0.tdeeKcal != nil }
        board.weekDaysCounted = counted.count
        if !counted.isEmpty {
            board.weekBalanceKcal = jsRound(counted.reduce(0) { $0 + ($1.intakeKcal ?? 0) - ($1.tdeeKcal ?? 0) })
        }

        board.pace = pace(rate: board.ratePerWeekKg, min: rateMinKgWk, max: rateMaxKgWk)
        return board
    }

    /// The band is SIGNED, so "faster" is not "larger". A cut asking for
    /// −0.50…−0.40 is over its pace at −0.7 and under it at −0.2; a bulk asking
    /// for +0.20…+0.25 is the mirror. The direction the band points is what
    /// decides which side of it is which.
    static func pace(rate: Double?, min lo: Double?, max hi: Double?) -> Pace {
        guard let rate, let lo, let hi else { return .unknown }
        let low = Swift.min(lo, hi), high = Swift.max(lo, hi)
        if rate >= low && rate <= high { return .onTrack }
        let losing = (low + high) < 0
        if losing {
            if rate > 0 { return .reversed }
            return rate < low ? .over : .under
        }
        if rate < 0 { return .reversed }
        return rate > high ? .over : .under
    }
}
