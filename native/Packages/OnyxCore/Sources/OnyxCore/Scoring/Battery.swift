import Foundation

/// Battery state — `BatteryState` in the web app's `lib/scoring/battery.ts`.
public struct BatteryState: Codable, Sendable, Equatable {
    /// 0–100, charge at wake, sleep-driven.
    public var morningCharge: Double
    /// 0–100, time-of-day aware.
    public var currentPct: Double

    public init(morningCharge: Double, currentPct: Double) {
        self.morningCharge = morningCharge
        self.currentPct = currentPct
    }
}

/// Phone-like battery — drain-only (v7), v8's stages-share charge, v9's
/// readiness signals on top. A direct port of the web app's `lib/scoring/battery.ts`;
/// the reasoning lives there and in `docs/READINESS_MODEL.md` and is not
/// duplicated here, but the one rule that must survive translation is repeated
/// because a port is exactly where it would be lost:
///
/// > **The drain budget must stay strictly under the charge budget.**
///
/// v6 broke it — max drain reached 104.2 against a 100-point charge, so a leg
/// day hit the floor before bedtime no matter how well you slept. `Invariants`
/// in the test target asserts it here the same way `battery.test.ts` asserts it
/// on the web side. If a constant below is ever edited, that test is the thing
/// that catches the edit being unsafe.
public enum Battery {
    public struct Defaults: Sendable {
        public let version: Double = 9
        public let floor: Double = 5
        /// Worst-sleep wake charge.
        public let wakeMin: Double = 55
        /// Plus up to 45 for perfect sleep, reaching 100.
        public let wakeRange: Double = 45
        /// Full chronological cost of an 18h day, cosine-distributed.
        public let timeMax: Double = 35
        public let activityCap: Double = 12
        /// The heaviest day's ceiling — see `workoutMaxByDay`.
        public let workoutMax: Double = 32
        /// v9 — ACWR past 1.3, and a strain above your own normal.
        public let loadCap: Double = 8
        /// v9 — the Hooper-style index: fatigue, soreness, onset, short sleep.
        public let wellnessCap: Double = 6
        /// v8 — (deep + REM) / asleep at which the stages term saturates.
        public let restorativeShare: Double = 0.45
        /// The charge a z-signal reads at exactly baseline, or when it has no opinion.
        public let zNeutral: Double = 0.75
        /// Charge per baseline SD: +1 SD fills the term, −2 SD leaves a quarter.
        public let zSlope: Double = 0.25
        /// Used when `session_rpe` is absent (legacy sessions carry none).
        /// Note this is already a 0–1 fraction, *not* a CR-10 value.
        public let defaultRpe: Double = 0.7
        /// A session at or below 60% of normal still costs something.
        public let relMin: Double = 0.6
        /// Beyond 140% of normal, more tonnage stops adding drain.
        public let relMax: Double = 1.4
        public let maxAwake: Double = 18
    }

    public static let defaults = Defaults()

    // ── THE BAND, WHICH IS NOT THE MODEL ────────────────────────────────────
    //
    // Where a percentage stops being green and starts being amber, and where
    // amber becomes red. It is a DISPLAY cut, not a term in the v9 arithmetic
    // — nothing above reads it — but it has to live in one place, because two
    // surfaces judge a day by it and they sit 40 pt apart on the Mega tile:
    // `Color.onyx.battery` paints the figure and `CoachSentence` writes the
    // line under it. Declared here rather than in either, because a battery
    // band belongs to the battery.

    /// At or above this the day reads as good.
    public static let goodPct = 60.0
    /// Below this the day reads as a rest day.
    public static let lowPct = 30.0

    /// The worst case the model can ever charge in a single day.
    /// v9: 35 + 12 + 32 + 8 + 6 = 93.
    public static var maxTotalDrain: Double {
        defaults.timeMax + defaults.activityCap + defaults.workoutMax + defaults.loadCap + defaults.wellnessCap
    }

    /// The workout drain ceiling, **per programme day**.
    ///
    /// Keyed on `day_key` (the programme day), never on `split_day` — `splitDay`
    /// does not drain, and has not since v7.
    public static let workoutMaxByDay: [String: Double] = [
        "legs_a": 32, "legs_b": 32,   // hardest — a third more than upper (v8)
        "cb_a": 24, "cb_b": 24,       // upper A / upper B
        "arms": 16,                   // delts & arms — the easiest day
    ]

    /// Default 24, the upper-day figure, for a session with no programme day.
    /// Assuming the middle beats assuming either extreme.
    public static let workoutMaxDefault: Double = 24

    /// How much of the day's workout ceiling a maintenance/deload day may spend.
    /// Strictly below 1, which is what keeps `maxTotalDrain` an upper bound.
    public static let maintenanceDrainFactor: Double = 0.75

    /// The floor of the relative term on a maintenance day. Lower than
    /// `relMin`, so it can only ever lower a drain — never raise the worst case.
    public static let maintenanceRelMin: Double = 0.35

    public static func workoutMaxFor(dayKey: String? = nil, maintenance: Bool = false) -> Double {
        let base = dayKey.flatMap { workoutMaxByDay[$0] } ?? workoutMaxDefault
        return maintenance ? base * maintenanceDrainFactor : base
    }

    /// The floor of the relative term for this kind of day.
    public static func relMinFor(maintenance: Bool) -> Double {
        maintenance ? maintenanceRelMin : defaults.relMin
    }

    /// Wake charge from sleep quality (0...1): `55 + 45·q`, rounded. v9 retired
    /// the onset penalty here — the flag is a wellness item now.
    public static func computeMorningCharge(sleepQuality: Double) -> Double {
        jsRound(defaults.wakeMin + defaults.wakeRange * clamp(sleepQuality, 0, 1))
    }

    /// A z-signal as a 0...1 charge term. Neutral 0.75 at z = 0 or unknown;
    /// +1 SD fills the term; −2 SD leaves a quarter.
    public static func zQuality(_ z: Double?) -> Double {
        guard let z, z.isFinite else { return defaults.zNeutral }
        return clamp(defaults.zNeutral + defaults.zSlope * z, 0, 1)
    }

    /// `computeSleepQuality`, with the four terms it is built from. Each 0...1.
    public struct SleepQualityParts: Codable, Sendable, Equatable {
        /// Duration vs goal, capped at 1.
        public var ratio: Double
        /// (deep + REM) / asleep, saturating at `restorativeShare`.
        public var stagesQ: Double
        /// `zQuality(hrvZ)`.
        public var hrvQ: Double
        /// `zQuality(−rhrZ)`.
        public var rhrQ: Double
        public var quality: Double
    }

    /// Sleep quality 0...1 (v9) — 45 % duration vs goal, 15 % restorative
    /// stages, 25 % HRV z, 15 % resting-HR z. Every term degrades to its
    /// NEUTRAL value when its inputs are missing, never to a penalty.
    public static func sleepQualityParts(_ inputs: ScoringInputs) -> SleepQualityParts {
        let ratio = inputs.sleepGoalHours != 0
            ? Swift.min(1, inputs.sleepHours / inputs.sleepGoalHours)
            : 1
        let asleepMin = inputs.sleepHours * 60
        let stagesQ = asleepMin > 0
            ? clamp((inputs.deepMinutes + inputs.remMinutes) / (defaults.restorativeShare * asleepMin), 0, 1)
            : 0
        let hrvQ = zQuality(inputs.hrvZ)
        // A HIGH resting HR is the bad direction, so the sign flips.
        let rhrQ = zQuality(inputs.rhrZ.map { -$0 })
        // ── A NIGHT THE WATCH NEVER SAW IS NOT A NIGHT OF ZERO HOURS (W6) ───
        // With no record, `ratio` and `stagesQ` above are 0 — which is the
        // right reading of a night you did not sleep and the wrong one of a
        // night the watch spent on its charger. When coverage says the latter,
        // the two terms drop and HRV and resting HR carry the charge between
        // them, the way `Score` drops every other nil. `ratio` and `stagesQ`
        // still report what was measured (nothing); only `quality` moves.
        if WristCoverage.nightUnmeasured(inputs) {
            let quality = clamp((0.25 * hrvQ + 0.15 * rhrQ) / 0.40, 0, 1)
            return SleepQualityParts(ratio: ratio, stagesQ: stagesQ, hrvQ: hrvQ, rhrQ: rhrQ, quality: quality)
        }
        let quality = clamp(0.45 * ratio + 0.15 * stagesQ + 0.25 * hrvQ + 0.15 * rhrQ, 0, 1)
        return SleepQualityParts(ratio: ratio, stagesQ: stagesQ, hrvQ: hrvQ, rhrQ: rhrQ, quality: quality)
    }

    public static func computeSleepQuality(_ inputs: ScoringInputs) -> Double {
        sleepQualityParts(inputs).quality
    }

    /// The Hooper-style index, item by item. Each 0...1 where 1 is WORST, and
    /// nil when the question was not answered that day.
    public struct WellnessParts: Codable, Sendable, Equatable {
        /// (level − 1) / 4 — Fresh 0 … Empty 1.
        public var fatigue: Double?
        /// Mean DOMS severity / 3.
        public var soreness: Double?
        /// 1 for a night that was hard to fall into, 0 otherwise. Nil when unasked.
        public var onset: Double?
        /// 1 − duration/goal. Nil with no night.
        public var sleep: Double?
        /// Mean of the answered items. Nil when none was.
        public var index: Double?
        /// `wellnessCap × index`; 0 when nothing was answered.
        public var drain: Double
    }

    /// Wellness drain (v9, cap 6) — the mean of the ANSWERED items, so a day
    /// with the tracker unopened drains nothing rather than reading as perfect.
    public static func wellnessParts(_ inputs: ScoringInputs) -> WellnessParts {
        var fatigue: Double?
        if let level = inputs.fatigueLevel, level.isFinite, level >= 1 {
            fatigue = clamp((level - 1) / 4, 0, 1)
        }
        var soreness: Double?
        if let sev = inputs.domsSeverity, sev.isFinite, sev >= 0 {
            soreness = clamp(sev / 3, 0, 1)
        }
        let onset: Double? = inputs.sleepOnsetTrouble.map { $0 ? 1 : 0 }
        var sleep: Double?
        if inputs.sleepHours > 0, inputs.sleepGoalHours > 0 {
            sleep = clamp(1 - Swift.min(1, inputs.sleepHours / inputs.sleepGoalHours), 0, 1)
        }
        let answered = [fatigue, soreness, onset, sleep].compactMap { $0 }
        let index: Double? = answered.isEmpty ? nil : answered.reduce(0, +) / Double(answered.count)
        return WellnessParts(
            fatigue: fatigue, soreness: soreness, onset: onset, sleep: sleep, index: index,
            drain: index.map { defaults.wellnessCap * $0 } ?? 0
        )
    }

    public static func wellnessDrain(_ inputs: ScoringInputs) -> Double {
        wellnessParts(inputs).drain
    }

    public struct LoadParts: Codable, Sendable, Equatable {
        /// 0 at or below an ACWR of 1.3, `loadCap × acwrShare` at 2.0 and beyond.
        public var acwrTerm: Double
        /// 0 at or below your own normal strain, the rest of the cap at +2 SD.
        public var strainTerm: Double
        /// The sum, capped at `loadCap`.
        public var drain: Double
    }

    /// Load drain (v9, cap 8) — the training you have done that today's
    /// session does not explain. Both terms floored at zero: a light week
    /// recharges nothing.
    public static func loadParts(_ inputs: ScoringInputs) -> LoadParts {
        let r = Readiness.constants
        let acwrCap = defaults.loadCap * r.acwrShare
        let strainCap = defaults.loadCap - acwrCap
        var acwrTerm: Double = 0
        if let acwr = inputs.acwr, acwr.isFinite {
            acwrTerm = acwrCap * clamp((acwr - r.acwrOnset) / (r.acwrSaturation - r.acwrOnset), 0, 1)
        }
        var strainTerm: Double = 0
        if let z = inputs.strainZ, z.isFinite {
            strainTerm = strainCap * clamp(z / r.zClamp, 0, 1)
        }
        return LoadParts(acwrTerm: acwrTerm, strainTerm: strainTerm, drain: Swift.min(defaults.loadCap, acwrTerm + strainTerm))
    }

    public static func loadDrain(_ inputs: ScoringInputs) -> Double {
        loadParts(inputs).drain
    }

    /// How far through the waking day the user is — `hoursAwakeInTZ` from the
    /// old snapshot route. The battery drains against this, so it is the one
    /// input that changes every hour with no new data; a 07:00 wake convention,
    /// clamped to `[0, maxAwake]`.
    public static func hoursAwake(at now: Date = Date(), calendar: Calendar = .current, wakeHour: Int = 7) -> Double {
        clamp(Double(calendar.component(.hour, from: now) - wakeHour), 0, defaults.maxAwake)
    }

    /// Chronological drain, as a raised cosine over the waking day rather than a
    /// line: little before hour 6, most between 8 and 14, flattening late.
    /// `awake = 0` gives 0; `awake = maxAwake` gives `timeMax`. Monotonic.
    public static func timeDrain(hoursAwake: Double) -> Double {
        let awake = clamp(hoursAwake, 0, defaults.maxAwake)
        return defaults.timeMax * (1 - Foundation.cos(Double.pi * awake / defaults.maxAwake)) / 2
    }

    /// Workout drain — relative to your own normal for this session type, scaled
    /// by how hard you said it was.
    ///
    /// `maintenance` lowers the ceiling and the relative floor and touches
    /// nothing else. It must never scale the effort term: an RPE 9 logged on a
    /// deload day was a nine.
    public static func workoutDrain(
        sessionVolumeKg: Double,
        trailingAvgVolumeKg: Double,
        sessionRpe: Double? = nil,
        dayKey: String? = nil,
        maintenance: Bool = false
    ) -> Double {
        guard sessionVolumeKg > 0 else { return 0 }
        let relative = trailingAvgVolumeKg > 0 ? sessionVolumeKg / trailingAvgVolumeKg : 1
        let intensity: Double = {
            guard let rpe = sessionRpe, rpe > 0 else { return defaults.defaultRpe }
            return clamp(rpe / 10, 0, 1)
        }()
        return workoutMaxFor(dayKey: dayKey, maintenance: maintenance)
            * intensity
            * clamp(relative, relMinFor(maintenance: maintenance), defaults.relMax)
            / defaults.relMax
    }

    /// Every term behind one battery reading — `BatteryBreakdown`. What the
    /// dashboard tile draws and what the export's Derived block prints.
    public struct Breakdown: Codable, Sendable, Equatable {
        public struct Charge: Codable, Sendable, Equatable {
            public var ratio: Double
            public var stagesQ: Double
            public var hrvQ: Double
            public var rhrQ: Double
            public var quality: Double
            public var morningCharge: Double
        }
        public struct Drains: Codable, Sendable, Equatable {
            public var time: Double
            public var activity: Double
            public var workout: Double
            public var load: Double
            public var wellness: Double
            /// The five, summed — before the floor and ceiling.
            public var total: Double
        }
        public var version: Double
        public var hoursAwake: Double
        public var charge: Charge
        public var drains: Drains
        public var loadParts: LoadParts
        public var wellnessParts: WellnessParts
        public var currentPct: Double
    }

    /// `batteryBreakdown` — the model, term by term.
    public static func breakdown(_ inputs: ScoringInputs, hoursAwake: Double? = nil) -> Breakdown {
        let q = sleepQualityParts(inputs)
        let wakeCharge = computeMorningCharge(sleepQuality: q.quality)

        let awake = clamp(hoursAwake ?? inputs.hoursAwake ?? 8, 0, defaults.maxAwake)
        let time = timeDrain(hoursAwake: awake)
        let activity = Swift.min(
            defaults.activityCap,
            0.004 * inputs.activeCal + 0.5 * (inputs.steps / 1000)
        )
        let workout = workoutDrain(
            sessionVolumeKg: inputs.sessionVolumeKg,
            trailingAvgVolumeKg: inputs.trailingAvgVolumeKg,
            sessionRpe: inputs.sessionRpe,
            dayKey: inputs.sessionDayKey,
            maintenance: inputs.isMaintenance ?? false
        )
        let load = loadParts(inputs)
        let wellness = wellnessParts(inputs)
        let total = time + activity + workout + load.drain + wellness.drain

        let currentPct = clamp(wakeCharge - total, defaults.floor, 100)
        return Breakdown(
            version: defaults.version,
            hoursAwake: awake,
            charge: .init(ratio: q.ratio, stagesQ: q.stagesQ, hrvQ: q.hrvQ, rhrQ: q.rhrQ, quality: q.quality, morningCharge: wakeCharge),
            drains: .init(time: time, activity: activity, workout: workout, load: load.drain, wellness: wellness.drain, total: total),
            loadParts: load,
            wellnessParts: wellness,
            currentPct: jsRound(currentPct)
        )
    }

    /// Current battery % — strict drain-only. There is no recharge term, which
    /// is why eating breakfast can never make the battery jump.
    public static func computeBattery(_ inputs: ScoringInputs, hoursAwake: Double? = nil) -> BatteryState {
        let b = breakdown(inputs, hoursAwake: hoursAwake)
        return BatteryState(morningCharge: b.charge.morningCharge, currentPct: b.currentPct)
    }
}
