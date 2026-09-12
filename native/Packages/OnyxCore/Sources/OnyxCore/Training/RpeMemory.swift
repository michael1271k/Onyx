import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Per-set RPE memory, and the session value derived from it. A port of
// the web app's `lib/training/rpeMemory.ts`.
//
// Last session's rating seeds this session's set, so you only tap where the
// effort actually changed. But a seeded rating on a HEAVIER set is a number you
// never gave — so the seed clears the moment the work gets harder, in either
// axis. A load DECREASE keeps it (a deload week must not wipe every remembered
// value), and `weightKg == 0` is real data: on bodyweight work the reps branch
// is the only one that can fire, which is exactly what those lifts need.
// ─────────────────────────────────────────────────────────────────────────────

/// What was remembered, and the work it was earned against.
public struct RpeSeed: Codable, Equatable, Sendable {
    public var rpe: Double
    public var weightKg: Double
    public var reps: Double
    public init(rpe: Double, weightKg: Double, reps: Double) { self.rpe = rpe; self.weightKg = weightKg; self.reps = reps }
}

public struct ResolvedRpe: Equatable, Sendable {
    /// nil = unrated. Never 0.
    public var rpe: Double?
    /// true = cleared because the work got harder. Drives the "rate this" pip.
    public var stale: Bool
}

/// The minimum a set has to look like to be weighted.
public struct RatedSet: Codable, Sendable {
    public var weightKg: Double
    public var reps: Double
    public var rpe: Double?
    public var setType: String?
    public init(weightKg: Double, reps: Double, rpe: Double? = nil, setType: String? = nil) {
        self.weightKg = weightKg; self.reps = reps; self.rpe = rpe; self.setType = setType
    }
}

public enum RpeMemory {
    /// Decide whether a remembered rating survives the current numbers.
    public static func resolveSeededRpe(_ seed: RpeSeed?, weightKg: Double, reps: Double) -> ResolvedRpe {
        guard let seed else { return ResolvedRpe(rpe: nil, stale: false) }
        let loadIncreased = weightKg > seed.weightKg
        let repsHarder = weightKg == seed.weightKg && reps > seed.reps
        if loadIncreased || repsHarder { return ResolvedRpe(rpe: nil, stale: true) }
        return ResolvedRpe(rpe: seed.rpe, stale: false)
    }

    /// `session_rpe` from the per-set ratings — tonnage-weighted, over working
    /// sets only; an unloaded set weighs 1 so it still counts. Nil when nothing
    /// is rated — never a fabricated number.
    public static func deriveSessionRpe(_ sets: [RatedSet]) -> Double? {
        var weighted = 0.0
        var total = 0.0
        for s in sets {
            guard SetTags.isWorkingSet(s.setType), let rpe = s.rpe, rpe.isFinite else { continue }
            let tonnage = s.weightKg * s.reps
            let w = tonnage > 0 ? tonnage : 1
            weighted += rpe * w
            total += w
        }
        if total == 0 { return nil }
        return Effort.normalizeCr10(weighted / total)
    }
}
