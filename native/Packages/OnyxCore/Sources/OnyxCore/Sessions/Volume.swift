import Foundation

/// One logged set, as `VolumeSet` in the web app's `lib/sessions/volume.ts`.
public struct VolumeSet: Codable, Sendable, Equatable {
    public var weightKg: Double
    public var reps: Double
    /// `"L"` or `"R"` for a unilateral row; anything else is unsided.
    public var side: String?
    /// Two rows sharing a pairId, one per side, are ONE set of work.
    public var pairId: String?
    /// Only `"ghost"` changes the answer: a set deliberately not performed.
    public var setType: String?

    public init(weightKg: Double, reps: Double, side: String? = nil, pairId: String? = nil, setType: String? = nil) {
        self.weightKg = weightKg
        self.reps = reps
        self.side = side
        self.pairId = pairId
        self.setType = setType
    }
}

/// Session volume — the ONE rule, ported from the web app's `lib/sessions/volume.ts`.
///
/// The history is in the TypeScript header. The rule that must survive:
///
/// > A genuine L/R pair is scored **once**, at the weaker side —
/// > `min(weight) × min(reps)` — so a set logged split weighs exactly what the
/// > same set weighs logged as a single unsided row. A ghost weighs nothing; a
/// > warm-up still counts.
public enum SessionVolume {
    /// Σ volume in kg, collapsing unilateral pairs to their weaker side,
    /// rounded to two decimals (the smallest place a real plate can reach).
    public static func sessionVolumeKg(_ sets: [VolumeSet]) -> Double {
        // First-seen order, so the arithmetic is deterministic on both sides.
        var order: [String] = []
        var pairs: [String: [VolumeSet]] = [:]
        var total = 0.0

        for s in sets {
            if s.setType == "ghost" { continue }
            let w = s.weightKg.isFinite ? s.weightKg : 0
            let r = s.reps.isFinite ? s.reps : 0
            // Only a genuine two-sided pair collapses: a pairId without a side,
            // or a side without a pairId, is an ordinary set. `"" ` is no pairId.
            if let pairId = s.pairId, !pairId.isEmpty, s.side == "L" || s.side == "R" {
                if pairs[pairId] == nil {
                    order.append(pairId)
                    pairs[pairId] = []
                }
                pairs[pairId]!.append(VolumeSet(weightKg: w, reps: r, side: s.side, pairId: pairId))
                continue
            }
            total += w * r
        }

        for pairId in order {
            let bucket = pairs[pairId]!
            let left = bucket.first { $0.side == "L" }
            let right = bucket.first { $0.side == "R" }
            if let left, let right {
                total += Swift.min(left.weightKg, right.weightKg) * Swift.min(left.reps, right.reps)
            } else {
                // A lone side, or a malformed 3+ bucket: each row as logged.
                for x in bucket { total += x.weightKg * x.reps }
            }
        }

        return jsRound(total * 100) / 100
    }
}
