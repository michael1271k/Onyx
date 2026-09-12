import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// READINESS v9 — the signals behind the battery, and the coach that reads it.
// A port of the web app's `lib/scoring/readiness.ts`; `docs/READINESS_MODEL.md` states
// the model with its citations. The `readiness-*` golden vectors replay every
// function below case for case.
//
// Every nil is a nil for a reason: a z that cannot be computed (thin history,
// a flat baseline) is `nil`, and every reader treats nil as NEUTRAL — the
// charge reads 0.75, the drains read 0. It is never a zero standing in for
// "we don't know", because a zero z is a claim and a missing one is not.
// ─────────────────────────────────────────────────────────────────────────────

/// `READINESS` — the constants the port must not drift from.
public struct ReadinessConstants: Sendable {
    /// The rolling window the z-signal compares. Plews 2013: 7-day averages.
    public let rollingDays: Int = 7
    /// The baseline the rolling mean is compared against. Buchheit 2014.
    public let baselineDays: Int = 42
    /// `rollingDays + baselineDays` — what the data layer fetches.
    public let historyDays: Int = 49
    /// Fewer rolling readings than this and the signal has no opinion.
    public let minRolling: Int = 3
    /// Fewer baseline readings than this and the signal has no opinion.
    public let minBaseline: Int = 14
    /// Smallest worthwhile change = 0.5 × baseline SD (Hopkins; Buchheit 2014).
    public let swcFactor: Double = 0.5
    /// A z beyond this is clamped.
    public let zClamp: Double = 2
    /// EWMA λ = 2/(N+1): acute N = 7, chronic N = 28. Williams 2017.
    public let acuteLambda: Double = 2.0 / 8.0
    public let chronicLambda: Double = 2.0 / 29.0
    /// Monotony and strain are read over the last seven days. Foster 1998.
    public let monotonyDays: Int = 7
    /// Fewer prior rolling strains than this and strain z has no opinion.
    public let minStrainHistory: Int = 14
    /// Fewer days WITH load before the rolling window than this and the ACWR
    /// has no opinion — a chronic side built on zeros cannot tell six weeks
    /// off from six weeks of sessions that never synced.
    public let minLoadDays: Int = 3
    /// CR-10 assumed for a lifting session that was not rated — the battery's
    /// own `defaultRpe` (0.7) as a CR-10, so "unrated" means one thing.
    public let defaultSessionRpe: Double = 7
    /// ACWR at which the load drain starts (the top of the "sweet spot").
    public let acwrOnset: Double = 1.3
    /// ACWR at which the load drain saturates.
    public let acwrSaturation: Double = 2.0
    /// How much of the load cap the ACWR term may spend; strain gets the rest.
    public let acwrShare: Double = 5.0 / 8.0

    public init() {}
}

/// One series' reading: a rolling mean against the baseline before it.
public struct ZSignal: Codable, Sendable, Equatable {
    public struct Counts: Codable, Sendable, Equatable {
        public var rolling: Int
        public var baseline: Int
    }
    /// Mean of the rolling window (ln-transformed when `log`). Nil when too thin.
    public var rolling: Double?
    public var baselineMean: Double?
    public var baselineSd: Double?
    /// Smallest worthwhile change, `swcFactor × baselineSd`.
    public var swc: Double?
    /// `rolling − baselineMean`.
    public var delta: Double?
    /// 0 inside ±SWC (noise); otherwise `delta / baselineSd` clamped ±`zClamp`.
    /// Nil when either window is too thin or the baseline is flat.
    public var z: Double?
    public var n: Counts
}

public struct LoadSession: Codable, Sendable, Equatable {
    public var date: String?
    public var sessionRpe: Double?
    public var durationMin: Double?
    public init(date: String? = nil, sessionRpe: Double?, durationMin: Double?) {
        self.date = date
        self.sessionRpe = sessionRpe
        self.durationMin = durationMin
    }
}

public struct LoadCardio: Codable, Sendable, Equatable {
    public var date: String?
    public var effort: Double?
    public var durationMin: Double?
    public init(date: String? = nil, effort: Double?, durationMin: Double?) {
        self.date = date
        self.effort = effort
        self.durationMin = durationMin
    }
}

public struct LoadSignal: Codable, Sendable, Equatable {
    /// Today's load (the last entry). Nil on an empty series.
    public var today: Double?
    public var acute: Double?
    public var chronic: Double?
    /// `acute / chronic`. Nil when there is no history or the chronic load is zero.
    public var acwr: Double?
    /// Sum of the last seven daily loads.
    public var weeklyLoad: Double?
    /// Mean over SD of the last seven daily loads. Nil when the SD is zero.
    public var monotony: Double?
    /// `weeklyLoad × monotony`.
    public var strain: Double?
    /// This week's strain against the rolling strains before it, clamped ±2.
    public var strainZ: Double?
}

public struct ReadinessHistory: Codable, Sendable, Equatable {
    /// SDNN ms per day, oldest → today. Nil for a day with no reading.
    public var hrv: [Double?]
    /// Resting HR bpm per day, oldest → today.
    public var rhr: [Double?]
    /// sRPE load per day, oldest → today. Rest days are zeros.
    public var loads: [Double]
    /// The stress index's fragmentation series (Phase 3 E3). `awakeMin` is nil
    /// for a night with no row AND for a duration-only row (awake = deep = rem
    /// = 0); `asleepMin` is nil only for a night with no row. Optional: the
    /// battery never reads them and the `readiness-signals` vectors predate them.
    public var awakeMin: [Double?]?
    public var asleepMin: [Double?]?
    public init(hrv: [Double?], rhr: [Double?], loads: [Double], awakeMin: [Double?]? = nil, asleepMin: [Double?]? = nil) {
        self.hrv = hrv
        self.rhr = rhr
        self.loads = loads
        self.awakeMin = awakeMin
        self.asleepMin = asleepMin
    }
}

public struct ReadinessSignals: Codable, Sendable, Equatable {
    public var hrv: ZSignal
    public var rhr: ZSignal
    public var load: LoadSignal
}

public enum Readiness {
    public static let constants = ReadinessConstants()

    // MARK: - Helpers

    static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    /// Sample standard deviation (n − 1). Nil below two values.
    static func sampleSd(_ xs: [Double]) -> Double? {
        guard xs.count >= 2, let m = mean(xs) else { return nil }
        return (xs.reduce(0) { $0 + pow($1 - m, 2) } / Double(xs.count - 1)).squareRoot()
    }

    // MARK: - The z-signal

    /// `values` is oldest → newest, the last `rollingDays` entries being the
    /// window and everything before them the baseline. `log` takes the natural
    /// log first (a non-positive reading is then missing, never −∞).
    public static func zSignal(_ values: [Double?], log useLog: Bool) -> ZSignal {
        let c = constants
        func usable(_ v: Double?) -> Double? {
            guard let v, v.isFinite else { return nil }
            if !useLog { return v }
            return v > 0 ? Foundation.log(v) : nil
        }
        let split = max(0, values.count - c.rollingDays)
        let baseline = values[..<split].compactMap(usable)
        let rolling = values[split...].compactMap(usable)

        let n = ZSignal.Counts(rolling: rolling.count, baseline: baseline.count)
        let rollingMean = rolling.count >= c.minRolling ? mean(rolling) : nil
        let baselineMean = baseline.count >= c.minBaseline ? mean(baseline) : nil
        let baselineSd = baseline.count >= c.minBaseline ? sampleSd(baseline) : nil
        let swc = baselineSd.map { c.swcFactor * $0 }
        var delta: Double?
        if let r = rollingMean, let b = baselineMean { delta = r - b }

        var z: Double?
        if let delta, let sd = baselineSd, let swc, sd > 0 {
            z = abs(delta) < swc ? 0 : clamp(delta / sd, -c.zClamp, c.zClamp)
        }
        return ZSignal(rolling: rollingMean, baselineMean: baselineMean, baselineSd: baselineSd, swc: swc, delta: delta, z: z, n: n)
    }

    // MARK: - sRPE load (Foster 1998 / 2001)

    /// A lifting session's load: CR-10 × minutes. Unrated → the default
    /// effort, not a rest day. No duration, no load.
    public static func sessionLoad(_ s: LoadSession) -> Double {
        let minutes: Double = {
            guard let d = s.durationMin, d.isFinite, d > 0 else { return 0 }
            return d
        }()
        if minutes == 0 { return 0 }
        let rpe: Double = {
            guard let r = s.sessionRpe, r.isFinite, r > 0 else { return constants.defaultSessionRpe }
            return clamp(r, 0, 10)
        }()
        return rpe * minutes
    }

    /// A cardio bout's load: effort × minutes. An unrated bout carries NO load.
    public static func cardioLoad(_ c: LoadCardio) -> Double {
        let minutes: Double = {
            guard let d = c.durationMin, d.isFinite, d > 0 else { return 0 }
            return d
        }()
        let effort: Double = {
            guard let e = c.effort, e.isFinite, e > 0 else { return 0 }
            return clamp(e, 0, 10)
        }()
        return effort * minutes
    }

    /// One load per date, in the order `dates` gives them. A date with nothing
    /// on it is a REAL zero.
    public static func dailyLoads(dates: [String], sessions: [LoadSession], cardio: [LoadCardio]) -> [Double] {
        var byDate: [String: Double] = [:]
        for s in sessions { if let d = s.date { byDate[d, default: 0] += sessionLoad(s) } }
        for c in cardio { if let d = c.date { byDate[d, default: 0] += cardioLoad(c) } }
        return dates.map { byDate[$0] ?? 0 }
    }

    // MARK: - EWMA ACWR (Williams 2017); monotony and strain (Foster 1998)

    /// Seeded with the mean of the first week, then run from the eighth day.
    public static func ewmaLoads(_ loads: [Double]) -> (acute: Double?, chronic: Double?) {
        guard !loads.isEmpty else { return (nil, nil) }
        let c = constants
        let seedN = min(c.monotonyDays, loads.count)
        let seed = mean(Array(loads[..<seedN]))!
        var acute = seed
        var chronic = seed
        if seedN < loads.count {
            for i in seedN..<loads.count {
                acute = loads[i] * c.acuteLambda + (1 - c.acuteLambda) * acute
                chronic = loads[i] * c.chronicLambda + (1 - c.chronicLambda) * chronic
            }
        }
        return (acute, chronic)
    }

    /// Foster's week: the sum, the monotony and the strain of seven daily loads.
    static func fosterWeek(_ week: [Double]) -> (weeklyLoad: Double, monotony: Double?, strain: Double?) {
        let weeklyLoad = week.reduce(0, +)
        let sd = sampleSd(week)
        let m = mean(week)!
        let monotony: Double? = (sd != nil && sd! > 0) ? m / sd! : nil
        return (weeklyLoad, monotony, monotony.map { weeklyLoad * $0 })
    }

    /// `loads` is oldest → newest, one per calendar day, today last.
    public static func loadSignal(_ loads: [Double]) -> LoadSignal {
        let c = constants
        let n = loads.count
        let (acute, chronic) = ewmaLoads(loads)
        // The ratio needs a chronic side built on real sessions — see `minLoadDays`.
        let loadedDays = loads.prefix(max(0, n - c.rollingDays)).filter { $0 > 0 }.count
        var acwr: Double?
        if let a = acute, let ch = chronic, ch > 0, loadedDays >= c.minLoadDays { acwr = a / ch }

        if n < c.monotonyDays {
            return LoadSignal(today: loads.last, acute: acute, chronic: chronic, acwr: acwr, weeklyLoad: nil, monotony: nil, strain: nil, strainZ: nil)
        }
        let thisWeek = fosterWeek(Array(loads[(n - c.monotonyDays)...]))

        // Every rolling seven-day strain that ENDS before today, for the z.
        var prior: [Double] = []
        if c.monotonyDays < n {
            for end in c.monotonyDays..<n {
                if let s = fosterWeek(Array(loads[(end - c.monotonyDays)..<end])).strain { prior.append(s) }
            }
        }
        var strainZ: Double?
        if let strain = thisWeek.strain, prior.count >= c.minStrainHistory {
            let m = mean(prior)!
            if let sd = sampleSd(prior), sd > 0 { strainZ = clamp((strain - m) / sd, -c.zClamp, c.zClamp) }
        }

        return LoadSignal(
            today: loads[n - 1], acute: acute, chronic: chronic, acwr: acwr,
            weeklyLoad: thisWeek.weeklyLoad, monotony: thisWeek.monotony, strain: thisWeek.strain, strainZ: strainZ
        )
    }

    // MARK: - The composite

    /// The three series through one door — what the data layer calls.
    public static func signals(_ history: ReadinessHistory) -> ReadinessSignals {
        ReadinessSignals(
            hrv: zSignal(history.hrv, log: true),
            rhr: zSignal(history.rhr, log: false),
            load: loadSignal(history.loads)
        )
    }

    // MARK: - The coach

    /// Readiness Coach — a port of `computeReadiness`.
    ///
    /// Sleep 40%, battery 40%, recovery 20%. `>= 70` train hard, `>= 45` train
    /// light, below that rest.
    ///
    /// A null sleep or recovery score falls back to the battery rather than to
    /// zero, so a day with no sensor data reads as "we don't know, here is what the
    /// battery says" instead of cratering into a false "Rest Today".
    public static func compute(
        sleepScore: Double?,
        recoveryScore: Double?,
        batteryPct: Double
    ) -> ReadinessResult {
        let sleep = sleepScore ?? batteryPct
        let recovery = recoveryScore ?? batteryPct
        let readinessScore = sleep * 0.40 + batteryPct * 0.40 + recovery * 0.20

        if readinessScore >= 70 {
            return ReadinessResult(
                level: .trainHard,
                label: "Train Hard",
                color: "#3E9E7A",
                reason: "Sleep, battery, and recovery are all strong today."
            )
        }
        if readinessScore >= 45 {
            return ReadinessResult(
                level: .trainLight,
                label: "Train Light",
                color: "#D4AF37",
                reason: "Moderate readiness — a lighter session will serve you well."
            )
        }
        return ReadinessResult(
            level: .rest,
            label: "Rest Today",
            color: "#C4514E",
            reason: "Recovery indicators are low — prioritize rest and nutrition."
        )
    }
}
