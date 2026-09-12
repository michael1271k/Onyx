import Foundation

/// The Session Report's arithmetic — a port of the web app's `lib/sessions/detail.ts`
/// (extracted from ExerciseBreakdown, SessionHighlights and MetricGrid).

public struct DetailSet: Codable, Sendable, Equatable {
    public var setNumber: Double
    public var weightKg: Double
    public var reps: Double
    public var rpe: Double?
    public var isPr: Bool
    public var est1rmKg: Double?
    public var setType: String
    public var side: String?
    public var pairId: String?
    /// nil = a legacy row persisted before the field existed; read as empty.
    public var prAxes: [String]?
    /// The cardio axes: seconds under load, incline percent, kilometres.
    ///
    /// Optional on the type as well as in value — the vectors written before
    /// they existed carry no such key, and a non-optional would stop every one
    /// of them decoding. All three nil is the ordinary case and means "score
    /// this set as load × reps"; see `SetFormat.cardio`.
    public var durationSec: Double?
    public var incline: Double?
    public var distanceKm: Double?
    /// Total ascent in METRES, measured rather than derived from
    /// `incline` × `distanceKm` — see `WorkoutSet.elevationM`. Optional on the
    /// type for the reason the three above it are: every vector written before
    /// it existed carries no such key.
    public var elevationM: Double?
}

public struct DetailExercise: Codable, Sendable, Equatable {
    public var exerciseId: String
    public var name: String
    public var order: Double
    public var muscleGroups: [String]
    public var isCompound: Bool
    public var sets: [DetailSet]
    public var workingSets: Double
    public var topKg: Double
    public var volumeKg: Double
    public var bestEst1rm: Double?
    public var prAxes: [String]?
}

/// A ledger row: a single set or a folded pair. `num` is nil for a warm-up.
public struct DetailRow: Codable, Sendable, Equatable {
    public var kind: String
    public var num: Int?
    public var set: DetailSet?
    public var left: DetailSet?
    public var right: DetailSet?
}

public struct RowWithPrev: Codable, Sendable, Equatable {
    public var row: DetailRow
    public var prev: HistorySet?
    public var prevRight: HistorySet?
}

public struct CueProgression: Codable, Sendable, Equatable {
    public var state: String
    public var ceiling: Double?
    public var suggestKg: Double?
}

public struct ProgressionCue: Codable, Sendable, Equatable {
    public var short: String
    public var title: String
}

public struct ExerciseStats: Codable, Sendable, Equatable {
    public var totalReps: Double
    public var avgRpe: Double?
    public var topKg: Double
    public var topReps: Double
}

public struct Highlight: Codable, Sendable, Equatable {
    public var name: String
    public var axes: [String]
    public var detail: String
}

public struct IntelMetric: Codable, Sendable, Equatable {
    public var key: String
    public var label: String
    public var value: Double?
    public var previous: Double?
    public var delta: Double?
    public var higherIsBetter: Bool
}

public struct MetricPct: Codable, Sendable, Equatable {
    public var pct: Double
    public var good: Bool
}

public enum SessionDetail {
    static func truthy(_ s: String?) -> Bool { !(s ?? "").isEmpty }

    /// Only WORKING sets take an ordinal; a truthy pairId folds into one row.
    public static func toRows(_ sets: [DetailSet]) -> [DetailRow] {
        var rows: [DetailRow] = []
        var pairIndex: [String: Int] = [:]
        var num = 0
        for s in sets {
            let counts = SetTags.isWorkingSet(s.setType)
            if truthy(s.pairId) {
                let p = s.pairId!
                var gi = pairIndex[p]
                if gi == nil {
                    if counts { num += 1 }
                    rows.append(DetailRow(kind: "pair", num: counts ? num : nil))
                    gi = rows.count - 1
                    pairIndex[p] = gi
                }
                if s.side == "R" { rows[gi!].right = s } else { rows[gi!].left = s }
            } else {
                if counts { num += 1 }
                rows.append(DetailRow(kind: "single", num: counts ? num : nil, set: s))
            }
        }
        return rows
    }

    /// A numbered row takes the next previous set; a pair takes two; a warm-up none.
    public static func rowsWithPrev(_ rows: [DetailRow], prev: [HistorySet]) -> [RowWithPrev] {
        var i = 0
        func at(_ k: Int) -> HistorySet? { k < prev.count ? prev[k] : nil }
        return rows.map { row in
            if row.num == nil { return RowWithPrev(row: row) }
            if row.kind == "pair" {
                let out = RowWithPrev(row: row, prev: at(i), prevRight: at(i + 1))
                i += 2
                return out
            }
            let out = RowWithPrev(row: row, prev: at(i))
            i += 1
            return out
        }
    }

    /// `delta`: `.some(nil)` is the JS null (🆕); `nil` is undefined (no glyph).
    public static func deltaGlyph(_ delta: Int??) -> String? {
        guard let d = delta else { return nil }
        guard let v = d else { return "🆕" }
        return v == 1 ? "⬆️" : v == -1 ? "⬇️" : "═"
    }

    static func js(_ v: Double?) -> String { v.map(jsIntegerString) ?? "null" }

    public static func progressionCue(_ t: CueProgression?, timed: Bool, unit: String, toDisplay: (Double) -> Double?) -> ProgressionCue? {
        guard let p = t, p.state == "ready" || p.state == "one-more" else { return nil }
        let ceil = "\(js(p.ceiling))\(timed ? "s" : " reps")"
        if p.state == "one-more" { return ProgressionCue(short: "1 more", title: "One more clean session at \(ceil)") }
        if timed { return ProgressionCue(short: "extend", title: "Cleared twice — extend past \(js(p.ceiling))s") }
        guard let kg = p.suggestKg else { return ProgressionCue(short: "extend", title: "Cleared twice — extend past \(ceil)") }
        let step = jsIntegerString(Ceilings.loadStepKg)
        return ProgressionCue(short: "+\(step)\(unit)", title: "Cleared twice — add \(step)\(unit) to \(js(toDisplay(kg)))\(unit)")
    }

    public static func exerciseStats(_ ex: DetailExercise) -> ExerciseStats {
        let working = ex.sets.filter { SetTags.isWorkingSet($0.setType) }
        var seen = Set<String>()
        var totalReps = 0.0
        for s in working {
            let key = s.pairId ?? "#\(jsIntegerString(s.setNumber))-\(s.side ?? "")"
            if truthy(s.pairId), seen.contains(key) { continue }
            seen.insert(key)
            totalReps += s.reps
        }
        let rpes = working.compactMap(\.rpe)
        let avgRpe: Double? = rpes.isEmpty ? nil : jsRound(rpes.reduce(0, +) / Double(rpes.count) * 10) / 10
        return ExerciseStats(
            totalReps: totalReps, avgRpe: avgRpe,
            topKg: working.reduce(0) { max($0, $1.weightKg) },
            topReps: working.reduce(0) { max($0, $1.reps) }
        )
    }

    /// The highest bestEst1rm > 0; first on a tie.
    public static func strongest(_ exercises: [DetailExercise]) -> DetailExercise? {
        var best: DetailExercise? = nil
        for e in exercises {
            let v = e.bestEst1rm ?? 0
            if v > 0 && (best == nil || v > (best!.bestEst1rm ?? 0)) { best = e }
        }
        return best
    }

    /// One line per exercise with a PR set: the set carrying the most axes, then the heaviest.
    public static func highlights(_ exercises: [DetailExercise], toDisplay: @escaping (Double) -> Double?, unit: String) -> [Highlight] {
        var out: [Highlight] = []
        for ex in exercises {
            let timed = TimedExercise.isTimed(ex.name)
            let won = ex.sets.filter(\.isPr)
            if won.isEmpty { continue }
            let lead = won.enumerated().sorted { a, b in
                let ca = a.element.prAxes?.count ?? 0, cb = b.element.prAxes?.count ?? 0
                if ca != cb { return ca > cb }
                if a.element.weightKg != b.element.weightKg { return a.element.weightKg > b.element.weightKg }
                return a.offset < b.offset
            }.first!.element
            let source = (lead.prAxes?.isEmpty == false) ? lead.prAxes! : (ex.prAxes ?? [])
            var axes: [String] = []
            for a in source {
                let label = PrAxis(rawValue: a).map { PrEngine.axisLabel($0, timed: timed) } ?? "1RM"
                if !axes.contains(label) { axes.append(label) }
            }
            out.append(Highlight(
                name: ex.name, axes: axes,
                detail: SetFormat.format(weightKg: lead.weightKg, reps: lead.reps, timed: timed, unit: unit, toDisplay: toDisplay)
            ))
        }
        return out
    }

    /// Percent change in the direction the metric considers good; nil when undecidable or a rounded 0.
    public static func pct(of m: IntelMetric?) -> MetricPct? {
        guard let m = m, let v = m.value, let p = m.previous, p != 0 else { return nil }
        let pct = jsRound((v - p) / p * 100)
        if pct == 0 { return nil }
        return MetricPct(pct: pct, good: (pct > 0) == m.higherIsBetter)
    }
}
