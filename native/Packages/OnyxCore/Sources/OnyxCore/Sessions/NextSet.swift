import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The set you are walking towards, and what it cost you last time — the Live
// Activity's one decision. A port of the web app's `lib/sessions/nextSet.ts` and the
// alignment rule in `prevAlign.ts`.
// ─────────────────────────────────────────────────────────────────────────────

/// One set of a previous session, as the history hook returns it.
public struct HistorySet: Codable, Equatable, Sendable {
    public var weightKg: Double
    public var reps: Double
    public var rpe: Double?
    public var setType: String?
    public var side: String?
    public var pairId: String?
    public init(weightKg: Double, reps: Double, rpe: Double? = nil, setType: String? = nil, side: String? = nil, pairId: String? = nil) {
        self.weightKg = weightKg; self.reps = reps; self.rpe = rpe; self.setType = setType; self.side = side; self.pairId = pairId
    }
}

public struct ExerciseHistory: Codable, Equatable, Sendable {
    /// Most recent session date.
    public var date: String
    /// That session's FULL set list, warm-ups included.
    public var sets: [HistorySet]
    public init(date: String, sets: [HistorySet]) { self.date = date; self.sets = sets }
}

public struct NextSet: Codable, Equatable, Sendable {
    public var exercise: String
    /// Human set number among the exercise's own working sets, 1-based.
    public var setNumber: Int
    public var setTotal: Int
    public var lastWeightKg: Double?
    public var lastReps: Double?
    public var lastRpe: Double?
    /// THIS set's own numbers — the Lock Screen leads with these.
    public var weightKg: Double?
    public var reps: Double?
    public var rpe: Double?
}

public enum NextSetFinder {
    /// The first set not ticked green, in deck order, skipping cardio blocks,
    /// warm-ups and ghosts; a unilateral pair counts as ONE set. Nil once every
    /// set is done.
    public static func find(_ draft: SessionDraft?, history: [String: ExerciseHistory]? = nil) -> NextSet? {
        guard let draft else { return nil }
        for ex in draft.exercises where !ex.isCardio {
            var total = 0
            var seenPairs = Set<String>()
            for s in ex.sets where SetTags.isWorkingSet(s.setType) {
                if let p = s.pairId, !p.isEmpty { if !seenPairs.insert(p).inserted { continue } }
                total += 1
            }
            if total == 0 { continue }

            var number = 0
            var counted = Set<String>()
            for s in ex.sets where SetTags.isWorkingSet(s.setType) {
                if let p = s.pairId, !p.isEmpty { if !counted.insert(p).inserted { continue } }
                number += 1
                if s.isCommitted { continue }
                let prev = previous(history?[ex.name], setNumber: number)
                return NextSet(
                    exercise: ex.name, setNumber: number, setTotal: total,
                    lastWeightKg: prev?.weightKg, lastReps: prev?.reps, lastRpe: prev?.rpe,
                    weightKg: s.weightKg, reps: s.reps, rpe: s.rpe
                )
            }
        }
        return nil
    }

    /// Last session's Nth working set — warm-ups and ghosts stripped, pairs
    /// folded to their first row — or nil when last time had fewer sets.
    private static func previous(_ h: ExerciseHistory?, setNumber: Int) -> HistorySet? {
        guard let h else { return nil }
        let working = h.sets.filter { SetTags.isWorkingSet($0.setType) }
        var folded: [HistorySet] = []
        var seen = Set<String>()
        for s in working {
            if let p = s.pairId, !p.isEmpty { if !seen.insert(p).inserted { continue } }
            folded.append(s)
        }
        return setNumber - 1 < folded.count ? folded[setNumber - 1] : nil
    }

    /// `3.75` stays `3.75`: whole loads print bare, tenths when they suffice, else hundredths.
    private static func load(_ w: Double) -> String {
        if w.truncatingRemainder(dividingBy: 1) == 0 { return jsToFixed(w, 0) }
        if (w * 10).truncatingRemainder(dividingBy: 1) == 0 { return jsToFixed(w, 1) }
        return jsToFixed(w, 2)
    }

    /// "3.75 kg × 16", "16 reps", or "" — what the Lock Screen draws for last time.
    public static func formatLastTime(_ next: NextSet?) -> String {
        guard let next, let reps = next.lastReps else { return "" }
        guard let w = next.lastWeightKg, w > 0 else { return "\(jsIntegerString(reps)) reps" }
        return "\(load(w)) kg × \(jsIntegerString(reps))"
    }

    /// "RPE 10", or "" when last time was never rated.
    public static func formatLastRpe(_ next: NextSet?) -> String {
        guard let rpe = next?.lastRpe else { return "" }
        return "RPE \(jsIntegerString(rpe))"
    }

    /// The load on the set you are ON — "32.5 kg × 10", "10 reps", "32.5 kg" or "".
    public static func formatLoad(_ next: NextSet?) -> String {
        guard let next else { return "" }
        let loaded = (next.weightKg ?? 0) > 0
        if !loaded && next.reps == nil { return "" }
        guard loaded, let w = next.weightKg else { return "\(jsIntegerString(next.reps!)) reps" }
        guard let reps = next.reps else { return "\(load(w)) kg" }
        return "\(load(w)) kg × \(jsIntegerString(reps))"
    }

    /// "RPE 8" for the set you are on, or "" while it is unrated.
    public static func formatRpe(_ next: NextSet?) -> String {
        guard let rpe = next?.rpe else { return "" }
        return "RPE \(jsIntegerString(rpe))"
    }
}

public enum PrevAlign {
    /// Collapse a previous session's set list into DISPLAY rows — a pair counts once.
    public static func previousDisplayRows(_ sets: [HistorySet]?) -> [HistorySet] {
        guard let sets, !sets.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [HistorySet] = []
        for s in sets {
            if let p = s.pairId, !p.isEmpty { if !seen.insert(p).inserted { continue } }
            out.append(s)
        }
        return out
    }

    /// One previous set per row of today's deck, like against like: warm-up
    /// rows take the history's non-working rows in order, working rows take
    /// working rows; surplus is nil, never repeated or borrowed.
    public static func alignPreviousSets(todayWarmup: [Bool], previous: [HistorySet]?) -> [HistorySet?] {
        let rows = previousDisplayRows(previous)
        let warm = rows.filter { !SetTags.isWorkingSet($0.setType) }
        let work = rows.filter { SetTags.isWorkingSet($0.setType) }
        var wi = 0, ki = 0
        return todayWarmup.map { isWarm in
            if isWarm { defer { wi += 1 }; return wi < warm.count ? warm[wi] : nil }
            defer { ki += 1 }
            return ki < work.count ? work[ki] : nil
        }
    }
}
