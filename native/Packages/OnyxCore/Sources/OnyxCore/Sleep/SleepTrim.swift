import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Sleep trim — strategy B, a port of the web app's `lib/sleep/trim.ts` (Phase 3 E2).
//
// What a night's stage minutes become when its window is edited and there are
// NO HealthKit samples to re-aggregate (strategy A lives in OnyxData, next to
// `Sleep.aggregate`, because only the phone holds samples). This operates on
// ASLEEP minutes, not window length:
//
//   trim      · awake minutes go first, then the asleep stages in proportion
//   extension · core only — no samples means no stage claim
//   shift     · the same span moved is the same night
//
// A window shorter than the minutes it holds (legacy `end_time = start_time`
// rows) is read as exactly `asleep + awake` long. The `sleep-trim` and
// `sleep-trim-night` golden vectors replay every rule below case for case.
// ─────────────────────────────────────────────────────────────────────────────

/// `NightStages` — a night's minutes as `sleep_sessions` stores them.
public struct NightStages: Codable, Sendable, Equatable {
    /// `duration_min` — asleep, the union of the stages.
    public var asleepMin: Double
    public var deepMin: Double
    public var remMin: Double
    public var coreMin: Double
    public var awakeMin: Double

    public init(asleepMin: Double, deepMin: Double, remMin: Double, coreMin: Double, awakeMin: Double) {
        self.asleepMin = asleepMin
        self.deepMin = deepMin
        self.remMin = remMin
        self.coreMin = coreMin
        self.awakeMin = awakeMin
    }

    /// `JSON.stringify` writes a NaN as `null`; the TypeScript reads a NaN as
    /// zero (`nonNeg`), so a null decodes to the non-finite value that takes the
    /// same path here rather than failing the whole fixture.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asleepMin = try c.decodeIfPresent(Double.self, forKey: .asleepMin) ?? .nan
        deepMin = try c.decodeIfPresent(Double.self, forKey: .deepMin) ?? .nan
        remMin = try c.decodeIfPresent(Double.self, forKey: .remMin) ?? .nan
        coreMin = try c.decodeIfPresent(Double.self, forKey: .coreMin) ?? .nan
        awakeMin = try c.decodeIfPresent(Double.self, forKey: .awakeMin) ?? .nan
    }
}

/// `StoredNight` — the row, with its window as ISO instants.
public struct StoredNight: Codable, Sendable, Equatable {
    public var start: String
    public var end: String
    public var asleepMin: Double
    public var deepMin: Double
    public var remMin: Double
    public var coreMin: Double
    public var awakeMin: Double

    public init(start: String, end: String, asleepMin: Double, deepMin: Double, remMin: Double, coreMin: Double, awakeMin: Double) {
        self.start = start
        self.end = end
        self.asleepMin = asleepMin
        self.deepMin = deepMin
        self.remMin = remMin
        self.coreMin = coreMin
        self.awakeMin = awakeMin
    }

    public var stages: NightStages {
        NightStages(asleepMin: asleepMin, deepMin: deepMin, remMin: remMin, coreMin: coreMin, awakeMin: awakeMin)
    }
}

/// `NightWindowEdit` — the window the user chose.
public struct NightWindowEdit: Codable, Sendable, Equatable {
    public var start: String
    public var end: String
    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }
}

/// `TrimmedNight` — the answer. Whole minutes throughout.
public struct TrimmedNight: Codable, Sendable, Equatable {
    public var asleepMin: Double
    public var deepMin: Double
    public var remMin: Double
    public var coreMin: Double
    public var awakeMin: Double
    /// Minutes the edit removed (0 on an extension or a shift).
    public var cutMin: Double
    /// Minutes the edit added (0 on a trim or a shift).
    public var addedMin: Double
    /// The row carried no stage split — awake = deep = rem = 0.
    public var durationOnly: Bool

    public var stages: NightStages {
        NightStages(asleepMin: asleepMin, deepMin: deepMin, remMin: remMin, coreMin: coreMin, awakeMin: awakeMin)
    }
}

public enum SleepTrim {

    private static func nonNeg(_ v: Double) -> Double { v.isFinite && v > 0 ? v : 0 }

    /// Whole minutes between two ISO instants, floored at zero. An unparseable
    /// instant reads as zero, as `Date.parse` → NaN does on the web.
    public static func spanMinutes(start: String, end: String) -> Double {
        guard let a = ISODate.parseMillis(start), let b = ISODate.parseMillis(end) else { return 0 }
        let ms = b - a
        return ms > 0 ? jsRound(ms / 60_000) : 0
    }

    /// A row with no stage split: everything asleep was filed as core (or as nothing).
    public static func isDurationOnly(_ n: NightStages) -> Bool {
        nonNeg(n.awakeMin) == 0 && nonNeg(n.deepMin) == 0 && nonNeg(n.remMin) == 0
    }

    /// Strategy B on minute counts — `trimStages`.
    public static func trimStages(_ n: NightStages, oldSpanMin: Double, newSpanMin: Double) -> TrimmedNight {
        let asleep = jsRound(nonNeg(n.asleepMin))
        let awake = jsRound(nonNeg(n.awakeMin))
        let deep = Swift.min(asleep, jsRound(nonNeg(n.deepMin)))
        let rem = Swift.min(asleep - deep, jsRound(nonNeg(n.remMin)))
        let durationOnly = isDurationOnly(n)

        // A window shorter than the minutes it holds is read as exactly that long.
        let oldSpan = Swift.max(jsRound(nonNeg(oldSpanMin)), asleep + awake)
        let newSpan = jsRound(nonNeg(newSpanMin))
        let delta = newSpan - oldSpan

        if delta == 0 {
            return TrimmedNight(
                asleepMin: asleep, deepMin: deep, remMin: rem, coreMin: asleep - deep - rem, awakeMin: awake,
                cutMin: 0, addedMin: 0, durationOnly: durationOnly
            )
        }

        if delta > 0 {
            // Extension: core only. No samples, no stage claim.
            return TrimmedNight(
                asleepMin: asleep + delta, deepMin: deep, remMin: rem, coreMin: asleep - deep - rem + delta,
                awakeMin: awake, cutMin: 0, addedMin: delta, durationOnly: durationOnly
            )
        }

        // Trim: awake first, then the asleep stages in proportion.
        let cut = -delta
        let awakeCut = Swift.min(awake, cut)
        let asleepCut = Swift.min(asleep, cut - awakeCut)
        let newAsleep = asleep - asleepCut
        let factor = asleep > 0 ? newAsleep / asleep : 0
        var newDeep = jsRound(deep * factor)
        var newRem = jsRound(rem * factor)
        // Rounding can push deep + rem a minute past the new total; core absorbs
        // the remainder and never goes negative.
        var newCore = newAsleep - newDeep - newRem
        if newCore < 0 {
            newRem += newCore
            newCore = 0
            if newRem < 0 { newDeep += newRem; newRem = 0 }
        }
        return TrimmedNight(
            asleepMin: newAsleep, deepMin: newDeep, remMin: newRem, coreMin: newCore,
            awakeMin: awake - awakeCut, cutMin: cut, addedMin: 0, durationOnly: durationOnly
        )
    }

    /// Strategy B over a stored row and the window the user chose — `trimNight`.
    ///
    /// An edit whose instants do not parse, or whose end is not after its
    /// start, is NOT an edit: the night comes back as a shift. A bad date that
    /// read as a zero-length window would wipe seven hours of stages.
    public static func trimNight(_ row: StoredNight, edit: NightWindowEdit) -> TrimmedNight {
        let oldSpan = spanMinutes(start: row.start, end: row.end)
        guard let a = ISODate.parseMillis(edit.start), let b = ISODate.parseMillis(edit.end), b - a > 0 else {
            return trimStages(row.stages, oldSpanMin: oldSpan, newSpanMin: oldSpan)
        }
        return trimStages(row.stages, oldSpanMin: oldSpan, newSpanMin: spanMinutes(start: edit.start, end: edit.end))
    }
}
