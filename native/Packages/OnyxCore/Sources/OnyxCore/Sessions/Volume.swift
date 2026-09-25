import Foundation

/// One logged set, as `VolumeSet` in the web app's `lib/sessions/volume.ts`.
public struct VolumeSet: Codable, Sendable, Equatable {
    public var weightKg: Double
    public var reps: Double
    /// `"L"` or `"R"` for a unilateral row; anything else is unsided.
    public var side: String?
    /// Two rows sharing a pairId, one per side, are ONE set of work.
    public var pairId: String?
    /// `"ghost"` weighs nothing and counts for nothing; `"warmup"` counts as a
    /// set performed but weighs nothing (Q13).
    public var setType: String?
    /// The movement is a 100 % bodyweight movement (`Bodyweight.isBodyweight`,
    /// or the catalogue's `is_bodyweight`). At 0 kg its load IS the athlete.
    public var bodyweight: Bool

    public init(
        weightKg: Double, reps: Double, side: String? = nil, pairId: String? = nil, setType: String? = nil,
        bodyweight: Bool = false
    ) {
        self.weightKg = weightKg
        self.reps = reps
        self.side = side
        self.pairId = pairId
        self.setType = setType
        self.bodyweight = bodyweight
    }

    private enum CodingKeys: String, CodingKey { case weightKg, reps, side, pairId, setType, bodyweight }

    /// `bodyweight` is absent from every golden vector and every cached
    /// payload written before Lane C; absent reads as false.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weightKg = try c.decode(Double.self, forKey: .weightKg)
        reps = try c.decode(Double.self, forKey: .reps)
        side = try c.decodeIfPresent(String.self, forKey: .side)
        pairId = try c.decodeIfPresent(String.self, forKey: .pairId)
        setType = try c.decodeIfPresent(String.self, forKey: .setType)
        bodyweight = try c.decodeIfPresent(Bool.self, forKey: .bodyweight) ?? false
    }
}

/// Session volume — the ONE rule, on the Hevy basis since Precision Lane C
/// (founder decision Q13, 2026-09-25).
///
/// The rule that must survive:
///
/// > A genuine L/R pair is scored **once**, at the weaker side —
/// > `min(weight) × min(reps)` — so a set logged split weighs exactly what the
/// > same set weighs logged as a single unsided row. A ghost weighs nothing.
/// > A warm-up weighs nothing. A 100 % bodyweight movement at 0 kg weighs the
/// > athlete: `bodyWeightKg × reps` when the body weight is known, 0 when not.
///
/// ── WHY WARM-UPS LEFT (Q13) ─────────────────────────────────────────────────
/// The web rule counted them ("a warm-up still counts"), and every other app
/// the founder compares against does not. Tonnage is the figure two apps
/// disagreed about, so it takes the basis the other one uses. Set COUNTS are a
/// different question — `SessionCounts.total` still counts a warm-up as a set
/// performed — and the two stay separate on purpose.
///
/// ── WHY THE PAIR RULE STAYED ────────────────────────────────────────────────
/// Lane C's proof over the founder's 2026-09-24 Upper B: scoring both sides of
/// the three pairs would move 4409 → 4636.5, further from Hevy's 4372.8, so
/// the founder's weaker-side rule is kept.
public enum SessionVolume {
    /// Σ volume in kg, collapsing unilateral pairs to their weaker side,
    /// rounded to two decimals (the smallest place a real plate can reach).
    ///
    /// - Parameter bodyWeightKg: the athlete's latest `daily_logs.weight_kg`
    ///   on or before the session day. `nil` credits 0 for bodyweight rows,
    ///   which is what every caller did before the parameter existed.
    public static func sessionVolumeKg(_ sets: [VolumeSet], bodyWeightKg: Double? = nil) -> Double {
        // First-seen order, so the arithmetic is deterministic on both sides.
        var order: [String] = []
        var pairs: [String: [VolumeSet]] = [:]
        var total = 0.0

        for s in sets {
            if s.setType == "ghost" || s.setType == "warmup" { continue }
            var w = s.weightKg.isFinite ? s.weightKg : 0
            let r = s.reps.isFinite ? s.reps : 0
            // The athlete is the load on an unloaded bodyweight row. A loaded
            // one (a dip with a plate) is scored as logged, per Q13's "100 %".
            if s.bodyweight, w == 0, let bw = bodyWeightKg, bw.isFinite, bw > 0 { w = bw }
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
