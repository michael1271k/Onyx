import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// STRESS INDEX v1 — a port of the web app's `lib/scoring/stress.ts` (Phase 3 E3).
// `docs/STRESS_MODEL.md` states the model with its citations; the `stress-*`
// golden vectors replay every function below case for case.
//
// Report-only (decision 2): a Pulse tile, a Trends series, an export line. It
// is NOT a battery input — `Battery.breakdown` does not read it, `ScoringInputs`
// carries no stress field, the budget stays 93. `InvariantTests` asserts it.
//
// The readiness v9 grammar throughout: personal z-scores, SWC-gated, clamped
// ±2, missing terms neutral, answered terms renormalised, load never negative.
// Three of the four terms share scalars with the battery and the index WILL
// co-move with the battery stack by construction — the model document says
// so at length. Fragmentation and the day's whole fatigue curve are what the
// battery cannot see, and the reason this exists.
// ─────────────────────────────────────────────────────────────────────────────

/// `STRESS` — the constants the port must not drift from.
public struct StressConstants: Sendable {
    public struct Weights: Sendable {
        public let auto: Double = 0.35
        public let sleep: Double = 0.25
        /// `self` in the TypeScript — a keyword here, so it has a longer name.
        public let selfReport: Double = 0.25
        public let load: Double = 0.15
    }
    public struct Band: Sendable, Equatable {
        public let key: StressBand
        public let label: String
        /// The band's INCLUSIVE ceiling (Calm's is exclusive: 30 is Baseline).
        /// Nil for the open last band.
        public let upTo: Double?
    }
    public let version: Double = 1
    /// Term weights, renormalised over the answered terms.
    public let weights = Weights()
    /// `S = center + scale · composite`.
    public let center: Double = 50
    public let scale: Double = 20
    /// The reachable range, and the clamp.
    public let min: Double = 10
    public let max: Double = 90
    /// The 1–5 fatigue scale's midpoint — "Worn" — reads as z = 0.
    public let fatigueNeutral: Double = 3
    /// Calm < 30 · Baseline 30–50 · Elevated 50–62 · High 62–75 · Overreached > 75.
    public let bands: [Band] = [
        Band(key: .calm, label: "Calm", upTo: 30),
        Band(key: .baseline, label: "Baseline", upTo: 50),
        Band(key: .elevated, label: "Elevated", upTo: 62),
        Band(key: .high, label: "High", upTo: 75),
        Band(key: .overreached, label: "Overreached", upTo: nil),
    ]

    public init() {}
}

public enum StressBand: String, Codable, Sendable, CaseIterable {
    case calm, baseline, elevated, high, overreached
}

public enum StressTermKey: String, Codable, Sendable, CaseIterable {
    case auto, sleep, load
    /// `self` in the TypeScript and in the JSON; a keyword here.
    case selfReport = "self"
}

/// `StressInputs` — the scalars the index reads, every one optional.
public struct StressInputs: Codable, Sendable, Equatable {
    /// From `Readiness.signals`. Positive HRV z is GOOD; positive RHR z is BAD.
    public var hrvZ: Double?
    public var rhrZ: Double?
    /// `Stress.fragmentationZ(...).z`.
    public var fragZ: Double?
    /// `daily_logs.sleep_onset_trouble`. Nil only when the column was unreadable.
    public var sleepOnsetTrouble: Bool?
    /// Mean of the DAY's fatigue slots, 1 (Fresh) … 5 (Empty). Nil when none logged.
    public var fatigueDayMean: Double?
    /// Mean of the DAY's `stress_logs` levels, 1 (calm) … 5 (overwhelmed).
    /// Nil when none logged. The second input of the `self` term (D6): Hooper
    /// treats fatigue and stress as one self-report, so the term averages the
    /// two that answered and the weights are unchanged.
    public var stressDayMean: Double?
    /// From `Readiness.signals.load`.
    public var acwr: Double?
    public var strainZ: Double?

    public init(
        hrvZ: Double? = nil, rhrZ: Double? = nil, fragZ: Double? = nil, sleepOnsetTrouble: Bool? = nil,
        fatigueDayMean: Double? = nil, stressDayMean: Double? = nil, acwr: Double? = nil, strainZ: Double? = nil
    ) {
        self.hrvZ = hrvZ
        self.rhrZ = rhrZ
        self.fragZ = fragZ
        self.sleepOnsetTrouble = sleepOnsetTrouble
        self.fatigueDayMean = fatigueDayMean
        self.stressDayMean = stressDayMean
        self.acwr = acwr
        self.strainZ = strainZ
    }

}

public enum Stress {
    public static let constants = StressConstants()

    private static func finite(_ v: Double?) -> Double? {
        guard let v, v.isFinite else { return nil }
        return v
    }

    // MARK: - Fragmentation

    /// A night as the fragmentation series needs it.
    public struct FragmentationNight: Sendable, Equatable {
        public var awakeMin: Double?
        public var asleepMin: Double?
        public var deepMin: Double?
        public var remMin: Double?
        public init(awakeMin: Double?, asleepMin: Double?, deepMin: Double? = nil, remMin: Double? = nil) {
            self.awakeMin = awakeMin
            self.asleepMin = asleepMin
            self.deepMin = deepMin
            self.remMin = remMin
        }
    }

    /// `awake / asleep` for one night, or nil when the row cannot claim one:
    /// no night, nothing asleep, or a DURATION-ONLY row (awake = deep = rem =
    /// 0), whose zero awake minutes are an absence of stage data.
    public static func fragmentationRatio(_ n: FragmentationNight) -> Double? {
        guard let asleep = finite(n.asleepMin), asleep > 0, let awake = finite(n.awakeMin), awake >= 0 else { return nil }
        let deep = finite(n.deepMin) ?? 0
        let rem = finite(n.remMin) ?? 0
        if awake == 0 && deep == 0 && rem == 0 { return nil }
        return awake / asleep
    }

    /// `awake / asleep` per night through the readiness z-signal — raw, not
    /// logged. Series oldest → newest; a night with no ratio is a hole.
    public static func fragmentationZ(awakeMin: [Double?], asleepMin: [Double?]) -> ZSignal {
        let n = Swift.min(awakeMin.count, asleepMin.count)
        var ratios: [Double?] = []
        ratios.reserveCapacity(n)
        for i in 0..<n {
            if let s = finite(asleepMin[i]), s > 0, let a = finite(awakeMin[i]), a >= 0 {
                ratios.append(a / s)
            } else {
                ratios.append(nil)
            }
        }
        return Readiness.zSignal(ratios, log: false)
    }

    // MARK: - The index

    // Each term carries its z (nil when no input answered it — the term is
    // then neutral), its weight, how many of its inputs were present, and the
    // pieces it was built from.
    public struct AutoTerm: Codable, Sendable, Equatable {
        public var z: Double?
        public var weight: Double
        public var answered: Int
        public var hrv: Double?
        public var rhr: Double?
    }
    public struct SleepTerm: Codable, Sendable, Equatable {
        public var z: Double?
        public var weight: Double
        public var answered: Int
        public var frag: Double?
        public var onset: Double?
    }
    public struct SelfTerm: Codable, Sendable, Equatable {
        public var z: Double?
        public var weight: Double
        public var answered: Int
        public var fatigueDayMean: Double?
        /// Absent from vectors written before D6; decodes as nil.
        public var stressDayMean: Double?

        public init(z: Double?, weight: Double, answered: Int, fatigueDayMean: Double?, stressDayMean: Double? = nil) {
            self.z = z; self.weight = weight; self.answered = answered
            self.fatigueDayMean = fatigueDayMean; self.stressDayMean = stressDayMean
        }
    }
    public struct LoadTerm: Codable, Sendable, Equatable {
        public var z: Double?
        public var weight: Double
        public var answered: Int
        public var acwrTerm: Double
        public var strainTerm: Double
    }

    public struct Terms: Codable, Sendable, Equatable {
        public var auto: AutoTerm
        public var sleep: SleepTerm
        /// `self` in the JSON.
        public var selfReport: SelfTerm
        public var load: LoadTerm

        enum CodingKeys: String, CodingKey {
            case auto, sleep, load
            case selfReport = "self"
        }

        /// One term's z by key, for the series.
        public func z(_ key: StressTermKey) -> Double? {
            switch key {
            case .auto: auto.z
            case .sleep: sleep.z
            case .selfReport: selfReport.z
            case .load: load.z
            }
        }
    }

    /// `StressBreakdown` — every term behind one reading.
    public struct Breakdown: Codable, Sendable, Equatable {
        public var version: Double
        public var terms: Terms
        /// Σ wᵢ over the answered terms. 0 when nothing answered.
        public var weightSum: Double
        /// Σ wᵢ zᵢ / Σ wᵢ. Nil when nothing answered.
        public var composite: Double?
        /// `round(clamp(50 + 20·composite, 10, 90))`. Nil when nothing answered.
        public var index: Double?
        public var band: StressBand?
    }

    /// Which band a reading falls in — see `StressConstants.bands` for the edge rule.
    public static func band(_ index: Double) -> StressBand {
        let bands = constants.bands
        if let calm = bands.first?.upTo, index < calm { return .calm }
        for b in bands.dropFirst() {
            if let up = b.upTo, index <= up { return b.key }
        }
        return .overreached
    }

    public static func bandLabel(_ band: StressBand?) -> String? {
        guard let band else { return nil }
        return constants.bands.first { $0.key == band }?.label
    }

    private static func meanOfAnswered(_ values: [Double?]) -> (z: Double?, answered: Int) {
        let xs = values.compactMap(finite)
        return (xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count), xs.count)
    }

    /// The load term's two pieces, each ≥ 0 — a light week de-stresses nothing.
    public static func loadParts(acwr: Double?, strainZ: Double?) -> (acwrTerm: Double, strainTerm: Double, answered: Int) {
        let r = Readiness.constants
        var acwrTerm: Double = 0
        if let a = finite(acwr) {
            acwrTerm = 2 * Swift.max(0, Swift.min(a, r.acwrSaturation) - r.acwrOnset) / (r.acwrSaturation - r.acwrOnset)
        }
        let strainTerm = finite(strainZ).map { Swift.max(0, $0) } ?? 0
        return (acwrTerm, strainTerm, (finite(acwr) == nil ? 0 : 1) + (finite(strainZ) == nil ? 0 : 1))
    }

    /// `stressBreakdown` — the model, term by term.
    public static func breakdown(_ inputs: StressInputs) -> Breakdown {
        let c = constants
        let r = Readiness.constants
        let w = c.weights

        let hrv = finite(inputs.hrvZ).map { -$0 }
        let rhr = finite(inputs.rhrZ)
        let auto = meanOfAnswered([hrv, rhr])

        let frag = finite(inputs.fragZ).map { clamp($0, -r.zClamp, r.zClamp) }
        // One-sided by design: a calm night does not de-stress.
        let onset: Double? = inputs.sleepOnsetTrouble.map { $0 ? 1 : 0 }
        let sleep = meanOfAnswered([frag, onset])

        // Two self-reports on one 1–5 scale, each centred on 3 and clamped,
        // then the mean of those that answered — so a day with only fatigue
        // logged reads exactly as it did before `stress_logs` existed.
        let fatigue = finite(inputs.fatigueDayMean)
        let stress = finite(inputs.stressDayMean)
        let selfParts = meanOfAnswered([
            fatigue.map { clamp($0 - c.fatigueNeutral, -r.zClamp, r.zClamp) },
            stress.map { clamp($0 - c.fatigueNeutral, -r.zClamp, r.zClamp) },
        ])
        let selfZ = selfParts.z

        let load = loadParts(acwr: inputs.acwr, strainZ: inputs.strainZ)
        let loadZ: Double? = load.answered > 0 ? clamp(0.5 * (load.strainTerm + load.acwrTerm), 0, r.zClamp) : nil

        let terms = Terms(
            auto: AutoTerm(z: auto.z, weight: w.auto, answered: auto.answered, hrv: hrv, rhr: rhr),
            sleep: SleepTerm(z: sleep.z, weight: w.sleep, answered: sleep.answered, frag: frag, onset: onset),
            selfReport: SelfTerm(z: selfZ, weight: w.selfReport, answered: selfParts.answered, fatigueDayMean: fatigue, stressDayMean: stress),
            load: LoadTerm(z: loadZ, weight: w.load, answered: load.answered, acwrTerm: load.acwrTerm, strainTerm: load.strainTerm)
        )

        var weightSum = 0.0
        var weighted = 0.0
        // The same order the TypeScript's `Object.values` walks, so the sums
        // reassociate identically.
        for (z, weight) in [(terms.auto.z, w.auto), (terms.sleep.z, w.sleep), (terms.selfReport.z, w.selfReport), (terms.load.z, w.load)] {
            guard let z else { continue }
            weightSum += weight
            weighted += weight * z
        }
        let composite: Double? = weightSum > 0 ? weighted / weightSum : nil
        let index = composite.map { jsRound(clamp(c.center + c.scale * $0, c.min, c.max)) }
        return Breakdown(
            version: c.version, terms: terms, weightSum: weightSum, composite: composite,
            index: index, band: index.map(band)
        )
    }

    /// The one number. See `breakdown` for the rest.
    public static func index(_ inputs: StressInputs) -> Double? {
        breakdown(inputs).index
    }
}
