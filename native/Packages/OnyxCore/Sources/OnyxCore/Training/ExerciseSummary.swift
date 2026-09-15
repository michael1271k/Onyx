import Foundation

/// The three numbers at the top of an exercise's page.
///
/// ── WHY THIS IS A SHARED FUNCTION AND NOT A QUERY ───────────────────────────
/// The web read them off the `exercise_history` RPC and the phone derived them
/// from the ledger, and the two disagreed on every unilateral lift and every
/// session with a warm-up in it: the RPC counts each side of a pair as its own
/// set and cannot collapse them (it has no `pair_id` to collapse ON), and its
/// `best_1rm` is a plain `max(est_1rm_kg)` with no Epley fallback, so a
/// bodyweight movement reported `0`. The web's answer to that was a footnote —
/// "Unilateral lifts count each side separately" — under a number that was
/// therefore not the number the phone showed.
///
/// Phase 2.5 decision 4 makes the NATIVE definitions the truth: pairs collapse,
/// warm-ups are excluded, and the estimate falls back to Epley. This is that
/// definition, once, with a TypeScript twin and a vector, so the two clients
/// cannot drift again.
public struct ExerciseSummarySet: Codable, Equatable, Sendable {
    /// Which session the set belongs to — the grouping the session-volume
    /// record is taken over.
    public var sessionId: String
    public var weightKg: Double
    public var reps: Double
    /// `workout_sets.est_1rm_kg`. A stored 0 is MISSING, never an estimate of
    /// zero — the `||` rule the whole app reads this column with.
    public var est: Double?
    public var setType: String?
    public var side: String?
    public var pairId: String?

    public init(sessionId: String, weightKg: Double, reps: Double, est: Double? = nil,
                setType: String? = nil, side: String? = nil, pairId: String? = nil) {
        self.sessionId = sessionId
        self.weightKg = weightKg
        self.reps = reps
        self.est = est
        self.setType = setType
        self.side = side
        self.pairId = pairId
    }
}

public struct ExerciseSummary: Codable, Equatable, Sendable {
    /// The heaviest load ever carried on a working set. Nil for unloaded work.
    public var heaviestKg: Double?
    /// The best estimated 1RM — stored where there is one, Epley where there is
    /// not. Nil when the movement carries no load, because an estimate of a
    /// one-rep max of nothing is not a number.
    public var bestE1rmKg: Double?
    /// The most tonnage this movement has carried in ONE session — the figure a
    /// set-level record book cannot answer.
    public var bestSessionVolumeKg: Double?
    /// The best rep count of any working set. The headline for unloaded and
    /// timed work, where there is no load to rank.
    public var bestReps: Double?
    /// The reps of the heaviest set, for the caveat line.
    public var heaviestSetReps: Double?
    /// Reps across every working set, pairs counted ONCE.
    public var totalReps: Double
    /// Working sets, pairs counted ONCE.
    public var workingSets: Int
    /// No working set has ever carried load.
    public var unloaded: Bool

    public static let empty = ExerciseSummary(
        heaviestKg: nil, bestE1rmKg: nil, bestSessionVolumeKg: nil, bestReps: nil,
        heaviestSetReps: nil, totalReps: 0, workingSets: 0, unloaded: true
    )
}

public extension ExerciseSummary {

    /// Summarise one exercise's whole ledger.
    ///
    /// - Parameter timed: the movement is scored in seconds rather than reps
    ///   (a plank), so it has no meaningful 1RM either.
    static func summarize(_ sets: [ExerciseSummarySet], timed: Bool = false) -> ExerciseSummary {
        let working = sets.filter { SetTags.isWorkingSet($0.setType) }
        guard !working.isEmpty else { return .empty }

        // ── ONE ROW PER PHYSICAL SET ────────────────────────────────────────
        // `collapsePairs` keeps the RIGHT side of an L/R pair (or the
        // higher-rep side), which is what makes "42 reps in 3 working sets"
        // true of a lift performed one arm at a time. Counting the rows as
        // logged says 84 reps in 6 sets and is the reason the web needed a
        // footnote under its own numbers.
        let collapsed = E1rmSeries.collapsePairs(working.map(Self.trendRow))
        let unloaded = !timed && working.allSatisfy { !($0.weightKg > 0) }

        let heaviest = collapsed.map(\.weightKg).max().flatMap { $0 > 0 ? $0 : nil }
        let bestReps = collapsed.map(\.reps).max()

        // The heaviest SET, not the heaviest load: at equal load the set that
        // says the most is the one with the most reps.
        let heaviestSetReps = heaviest.flatMap { top in
            collapsed.filter { $0.weightKg == top }.map(\.reps).max()
        }

        let bestE1rm: Double? = (timed || unloaded)
            ? nil
            : collapsed.compactMap(Self.oneRepMax).max()

        // ── THE SESSION RECORD ──────────────────────────────────────────────
        // Grouped by session and run through `sessionVolumeKg`, which is the
        // one implementation of "what a session weighed": a genuine L/R pair
        // scores min(weight) × min(reps) ONCE, and warm-ups never reach it
        // because they were filtered above.
        var bySession: [String: [ExerciseSummarySet]] = [:]
        for set in working { bySession[set.sessionId, default: []].append(set) }
        let bestVolume = bySession.values
            .map { SessionVolume.sessionVolumeKg($0.map(Self.volumeSet)) }
            .max()

        return ExerciseSummary(
            heaviestKg: heaviest,
            bestE1rmKg: bestE1rm,
            bestSessionVolumeKg: (bestVolume ?? 0) > 0 ? jsRound(bestVolume ?? 0) : nil,
            bestReps: bestReps,
            heaviestSetReps: heaviestSetReps,
            totalReps: collapsed.reduce(0) { $0 + $1.reps },
            workingSets: collapsed.count,
            unloaded: unloaded
        )
    }

    /// A stored estimate wins; a stored 0 is missing and falls through to
    /// Epley, which is itself nil for an unloaded set.
    private static func oneRepMax(_ set: TrendSetRow) -> Double? {
        // `isFinite`, not `!isNaN`: the twin's guard is `Number.isFinite`, which
        // rejects an infinity as well, and a rule that differs only on an
        // unreachable input is still a rule that differs.
        if let est = set.est, est > 0, est.isFinite { return est }
        return OneRepMax.estimate(weight: set.weightKg, reps: set.reps)
    }

    private static func trendRow(_ s: ExerciseSummarySet) -> TrendSetRow {
        TrendSetRow(weightKg: s.weightKg, reps: s.reps, est: s.est, side: s.side, pairId: s.pairId)
    }

    private static func volumeSet(_ s: ExerciseSummarySet) -> VolumeSet {
        VolumeSet(
            weightKg: s.weightKg, reps: s.reps,
            side: s.side == "L" || s.side == "R" ? s.side : nil,
            pairId: s.pairId, setType: s.setType
        )
    }
}
