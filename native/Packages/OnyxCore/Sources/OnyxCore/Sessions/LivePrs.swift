import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Records claimed by the sets ticked green so far. A port of
// the web app's `lib/sessions/livePrs.ts`.
//
// ONLY COMMITTED SETS COUNT — an untouched template row still holds last week's
// numbers. Sets are fed to the engine in deck order with the draft's DATE, so an
// asserted date takes the record-book branch here exactly as it does at save
// time: what you see on the tick is what gets written.
// ─────────────────────────────────────────────────────────────────────────────

public struct LivePrEntry: Equatable, Sendable {
    /// `${localId}|${setIdx}`.
    public var key: String
    public var axes: [PrAxis]
}

public struct LivePrDetail: Equatable, Sendable {
    public var key: String
    public var records: [PrAxis: AxisRecord]
}

public struct LivePrs: Equatable, Sendable {
    public var bySet: [LivePrEntry]
    /// Only the axes that SURVIVED supersession keep a delta.
    public var detailBySet: [LivePrDetail]
    /// Distinct axis-records across the session.
    public var count: Int

    public static let empty = LivePrs(bySet: [], detailBySet: [], count: 0)
}

public enum LivePrEngine {
    public static func key(_ localId: String, _ setIdx: Int) -> String { "\(localId)|\(setIdx)" }

    /// Everything the record answer depends on, as a string — the memo key.
    /// Only committed sets appear, because only they can change the answer.
    public static func digest(_ draft: SessionDraft?) -> String {
        guard let draft else { return "" }
        var out = draft.date
        for ex in draft.exercises where !ex.isCardio {
            for (i, s) in ex.sets.enumerated() where s.isCommitted {
                out += "|\(ex.localId):\(i):\(ex.name):\(jsIntegerString(s.weightKg)):\(jsIntegerString(s.reps)):\(s.setType ?? ""):\(s.side ?? ""):\(s.pairId ?? "")"
            }
        }
        return out
    }

    public static func compute(_ draft: SessionDraft?, baselines: PrBaselines?) -> LivePrs {
        guard let draft, let baselines else { return .empty }
        var candidates: [PrCandidateSet] = []
        var origin: [(localId: String, setIdx: Int)] = []
        for ex in draft.exercises where !ex.isCardio {
            let timed = TimedExercise.isTimed(ex.name)
            for (i, s) in ex.sets.enumerated() where s.isCommitted {
                candidates.append(PrCandidateSet(
                    key: ex.name, weightKg: s.weightKg, reps: s.reps, setType: s.setType, timed: timed,
                    pairId: s.pairId, side: s.side,
                    date: draft.date, exerciseName: ex.name, setNumber: i + 1
                ))
                origin.append((ex.localId, i))
            }
        }
        if candidates.isEmpty { return .empty }

        let r = PrEngine.detectSessionPrs(candidates, baselines)
        var bySet: [LivePrEntry] = []
        var detail: [LivePrDetail] = []
        for (i, d) in r.perSet.enumerated() where !d.axes.isEmpty {
            let k = key(origin[i].localId, origin[i].setIdx)
            bySet.append(LivePrEntry(key: k, axes: d.axes))
            var records: [PrAxis: AxisRecord] = [:]
            for axis in d.axes { if let rec = d.records[axis] { records[axis] = rec } }
            if !records.isEmpty { detail.append(LivePrDetail(key: k, records: records)) }
        }
        return LivePrs(bySet: bySet, detailBySet: detail, count: r.prCount)
    }
}
