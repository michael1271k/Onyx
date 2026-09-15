import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// THE HERO SLOT — which reading leads the vitals, and when the night loses it.
//
// Pulse draws one full-width reading over a grid of eight sidekicks. The night
// holds that slot, because it is the reading the other eight are context for.
// The exception this file exists for: a vital that has gone far enough wrong
// that reading it third in a grid of eight is the wrong order to learn it in.
//
// ── NO NEW THRESHOLD MODEL (A1) ─────────────────────────────────────────────
// The verdict is `Readiness.zSignal` and nothing else: a 7-day rolling mean
// against the 42 days before it, dead-banded at 0.5 × baseline SD, clamped ±2
// (`READINESS_MODEL.md` §2). The DEAD-BAND is the whole reason this can be a
// hero slot at all — a rule keyed on the raw delta would hand the slot to a
// different vital most mornings, and a lead that moves daily is a lead nobody
// learns to read.
// ─────────────────────────────────────────────────────────────────────────────

/// One reading, as the promotion rule needs it: which way is good, and how far
/// from its own normal it currently sits.
///
/// `z` is `nil` for a reading with no opinion — thin history, a flat baseline —
/// and a nil is never read as a zero here. "We cannot say" and "it has not
/// moved" are different facts, and only one of them is a reason NOT to promote.
public struct VitalReading: Codable, Sendable, Equatable {
    /// `VitalSpec.name` — the id the grid and the hero cell both key on.
    public let id: String
    /// False where DOWN is the good direction: a resting heart rate over your
    /// own normal is the bad night, and under it is not.
    public let upIsGood: Bool
    /// `Readiness.zSignal(...).z`. Nil when the signal has no opinion.
    public let z: Double?

    public init(id: String, upIsGood: Bool, z: Double?) {
        self.id = id
        self.upIsGood = upIsGood
        self.z = z
    }
}

/// Who holds the full-width slot.
public enum HeroSlot: Codable, Sendable, Equatable {
    case sleep
    /// The promoted reading's `VitalReading.id`.
    case vital(String)
}

public enum VitalHero {
    /// How far past its own normal, in SDs, a vital has to sit before it takes
    /// the night's slot. One SD on a signal already dead-banded at 0.5 SD, so
    /// the band a promotion has to clear is genuinely a bad night rather than
    /// the top of the noise.
    public static let alarmZ: Double = 1

    /// A reading from its own series — the zSignal grammar, unchanged.
    ///
    /// `values` is oldest → newest over `Readiness.constants.historyDays`; the
    /// last seven are the rolling window and everything before them is the
    /// baseline. `log` takes the natural log first, for HRV, exactly as
    /// `Readiness.signals` does — the same series must not be read one way by
    /// the battery and another way by this screen.
    public static func reading(
        id: String, upIsGood: Bool, log: Bool = false, series: [Double?]
    ) -> VitalReading {
        VitalReading(id: id, upIsGood: upIsGood, z: Readiness.zSignal(series, log: log).z)
    }

    /// Sleep by default; the worst alarming vital when there is one.
    ///
    /// A vital is promoted only when BOTH hold:
    ///  * its z crosses ±`alarmZ` in the BAD direction (`upIsGood ? z < −1 : z > 1`), and
    ///  * its magnitude exceeds the night's own.
    ///
    /// ── WHY THE NIGHT'S MAGNITUDE IS A FLOOR AND NOT A DIRECTION ────────────
    /// `|z|`, not "the night was bad". A night two SDs from your own normal is
    /// the most notable reading on the screen whichever way it went — six hours
    /// or ten — and handing the slot to a vital 1.2 SDs out would bury it.
    ///
    /// ── AND WHY THE ORDER OF `readings` IS THE TIE-BREAK ────────────────────
    /// Two vitals equally far out is a real state (they are correlated: a fever
    /// moves temperature, respiratory rate and resting HR together), and a
    /// `sorted` over equal keys is not guaranteed stable in Swift. The walk
    /// keeps the FIRST of an equal pair, so passing `VitalSpec.all` order in
    /// makes the answer the same on every launch and on every device.
    public static func promote(_ readings: [VitalReading], sleep: VitalReading?) -> HeroSlot {
        // A night with no baseline behind it is a floor of zero, not a veto:
        // it cannot say the night is remarkable, so it cannot outrank a vital
        // that has said so.
        let floor = abs(sleep?.z ?? 0)
        var best: (id: String, magnitude: Double)?
        for reading in readings {
            guard let magnitude = alarm(reading), magnitude > floor else { continue }
            if best == nil || magnitude > best!.magnitude { best = (reading.id, magnitude) }
        }
        return best.map { HeroSlot.vital($0.id) } ?? .sleep
    }

    /// `|z|` when the reading is alarming, nil when it is not — in band, moving
    /// the right way, or with no opinion at all.
    private static func alarm(_ reading: VitalReading) -> Double? {
        guard let z = reading.z else { return nil }
        let bad = reading.upIsGood ? z < -alarmZ : z > alarmZ
        return bad ? abs(z) : nil
    }
}
