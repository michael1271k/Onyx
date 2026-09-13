import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SessionDraft — the editable state between the deck and the commit, and the
// pure functions over it. A port of the arithmetic in the web app's `lib/sessions/draft.ts`;
// storage (localStorage, the v1 migration) and the commit payload belong to
// OnyxData and its event log.
// ─────────────────────────────────────────────────────────────────────────────

public struct DraftSet: Codable, Equatable, Sendable {
    public var weightKg: Double
    public var reps: Double
    public var rpe: Double?
    /// RPE MEMORY — last session's rating for this slot and the work it was
    /// earned against. Dropped the instant you tap a rating yourself.
    public var rpeSeed: Double?
    public var rpeSeedWeightKg: Double?
    public var rpeSeedReps: Double?
    /// Cleared by a load/rep increase — drives the "rate this" pip.
    public var rpeStale: Bool?
    /// `warmup` / `failure` / `dropset` / `ghost`; absent = a normal working set.
    public var setType: String?
    /// How the set went — a SECOND axis. Absent means "not reported", never "clean".
    public var quality: String?
    /// `false` = not ticked green and EXCLUDED from the commit; `true` / absent = committed.
    public var done: Bool?
    /// Unilateral tracking: L and R of ONE physical set share a `pairId`.
    public var side: String?
    public var pairId: String?

    public init(
        weightKg: Double, reps: Double, rpe: Double? = nil, rpeSeed: Double? = nil, rpeSeedWeightKg: Double? = nil,
        rpeSeedReps: Double? = nil, rpeStale: Bool? = nil, setType: String? = nil, quality: String? = nil,
        done: Bool? = nil, side: String? = nil, pairId: String? = nil
    ) {
        self.weightKg = weightKg; self.reps = reps; self.rpe = rpe; self.rpeSeed = rpeSeed
        self.rpeSeedWeightKg = rpeSeedWeightKg; self.rpeSeedReps = rpeSeedReps; self.rpeStale = rpeStale
        self.setType = setType; self.quality = quality; self.done = done; self.side = side; self.pairId = pairId
    }

    /// A set is committed (green, saved) unless it was explicitly ticked off.
    public var isCommitted: Bool { done != false }
}

public struct DraftExercise: Codable, Equatable, Sendable {
    public var localId: String
    public var name: String
    /// `cardio` renders a distance/duration card and is excluded from the sets.
    public var kind: String?
    public var distanceKm: Double?
    public var durationSec: Double?
    public var inclinePct: Double?
    public var done: Bool?
    public var note: String?
    public var sets: [DraftSet]
    /// The coach verdict chip: PR / PROGRESS / HOLD / REGRESS / NEW.
    public var status: String?
    /// The stored `exercises.muscle_groups` column, the fallback when the name is unknown to the dictionary.
    public var muscleGroups: [String]?

    public init(localId: String, name: String, kind: String? = nil, distanceKm: Double? = nil, durationSec: Double? = nil, inclinePct: Double? = nil, done: Bool? = nil, note: String? = nil, sets: [DraftSet], status: String? = nil, muscleGroups: [String]? = nil) {
        self.localId = localId; self.name = name; self.kind = kind; self.distanceKm = distanceKm
        self.durationSec = durationSec; self.inclinePct = inclinePct; self.done = done; self.note = note; self.sets = sets
        self.status = status; self.muscleGroups = muscleGroups
    }

    public var isCardio: Bool { kind == "cardio" }
}

public struct SessionDraft: Codable, Equatable, Sendable {
    public var splitDay: String
    /// YYYY-MM-DD.
    public var date: String
    public var dayKey: String?
    public var title: String?
    public var notes: String
    /// ISO instant the session began.
    public var startedAt: String
    /// Banked milliseconds from completed pauses.
    public var pausedMs: Double?
    /// ISO start of the pause in progress, nil while running.
    public var pausedAt: String?
    public var sessionRpe: Double?
    public var exercises: [DraftExercise]

    public init(splitDay: String, date: String, dayKey: String? = nil, title: String? = nil, notes: String = "", startedAt: String, pausedMs: Double? = nil, pausedAt: String? = nil, sessionRpe: Double? = nil, exercises: [DraftExercise]) {
        self.splitDay = splitDay; self.date = date; self.dayKey = dayKey; self.title = title; self.notes = notes
        self.startedAt = startedAt; self.pausedMs = pausedMs; self.pausedAt = pausedAt; self.sessionRpe = sessionRpe; self.exercises = exercises
    }
}

/// A `Partial<DraftSet>` with the one distinction JSON cannot carry: a field
/// that is PRESENT and undefined (`rpe: .some(nil)`, a clearing) versus absent
/// (`rpe: nil`). `applySetPatch` treats them differently.
public struct SetPatch: Equatable, Sendable {
    public var weightKg: Double?
    public var reps: Double?
    public var rpe: Double??
    public var setType: String??
    public var done: Bool?
    public var quality: String?

    public init(weightKg: Double? = nil, reps: Double? = nil, rpe: Double?? = nil, setType: String?? = nil, done: Bool? = nil, quality: String? = nil) {
        self.weightKg = weightKg; self.reps = reps; self.rpe = rpe; self.setType = setType; self.done = done; self.quality = quality
    }
}

public struct PairAsymmetry: Codable, Equatable, Sendable {
    public var pct: Double
    /// "L" or "R".
    public var weak: String
}

public enum Draft {
    /// The rating that MEANS failure, and the single definition of it.
    public static let failureRpe: Double = 10

    /// The committed strength sets, in deck order.
    static func committedSets(_ draft: SessionDraft) -> [DraftSet] {
        var out: [DraftSet] = []
        for ex in draft.exercises where !ex.isCardio {
            for s in ex.sets where s.isCommitted { out.append(s) }
        }
        return out
    }

    private static func volumeSets(_ sets: [DraftSet]) -> [VolumeSet] {
        sets.map { VolumeSet(weightKg: $0.weightKg, reps: $0.reps, side: $0.side, pairId: $0.pairId, setType: $0.setType) }
    }

    /// Σ weight×reps over the committed strength sets (warm-ups included), with
    /// the unilateral collapse, plus the count.
    public static func totals(_ draft: SessionDraft) -> (volumeKg: Double, sets: Int) {
        let committed = committedSets(draft)
        return (SessionVolume.sessionVolumeKg(volumeSets(committed)), committed.count)
    }

    /// Can this L/R pair be drawn as ONE row? Both present, both committed,
    /// same set type, and weight AND reps exactly equal — not "close".
    public static func isPairCompactable(_ l: DraftSet?, _ r: DraftSet?) -> Bool {
        guard let l, let r, l.isCommitted, r.isCommitted else { return false }
        if (l.setType ?? "normal") != (r.setType ?? "normal") { return false }
        return l.weightKg == r.weightKg && l.reps == r.reps
    }

    /// A pair's imbalance, by the work each side did: tonnage when loaded, the
    /// value column (seconds or reps) when not. Nil under 3% or with no work.
    public static func pairAsymmetry(_ l: DraftSet?, _ r: DraftSet?) -> PairAsymmetry? {
        guard let l, let r else { return nil }
        func work(_ s: DraftSet) -> Double { s.weightKg > 0 ? s.weightKg * s.reps : s.reps }
        let lv = work(l), rv = work(r)
        let hi = Swift.max(lv, rv)
        if hi <= 0 { return nil }
        let pct = jsRound((1 - Swift.min(lv, rv) / hi) * 100)
        if pct < 3 { return nil }
        return PairAsymmetry(pct: pct, weak: lv < rv ? "L" : "R")
    }

    /// Cumulative session tonnage after each committed set — the Live Activity's
    /// sparkline. Recomputed over each prefix (so a pair collapses exactly as the
    /// total does), sampled to `cap` points with both endpoints kept, empty below two.
    public static func volumeSeries(_ draft: SessionDraft, cap: Int = 12) -> [Double] {
        let committed = committedSets(draft)
        if committed.count < 2 { return [] }
        var cumulative: [Double] = []
        for i in 0..<committed.count {
            let prefix = Array(committed[0...i])
            cumulative.append(jsRound(SessionVolume.sessionVolumeKg(volumeSets(prefix))))
        }
        if cumulative.count <= cap { return cumulative }
        var out: [Double] = []
        for i in 0..<cap {
            let position = Double(i * (cumulative.count - 1)) / Double(cap - 1)
            out.append(cumulative[Int(jsRound(position))])
        }
        return out
    }

    /// Apply a patch to ONE set, with the two rules that hold whatever else is
    /// happening: any touch of the rating (present, even undefined) releases the
    /// seed, as does ticking a RATED set; and failure is derived from the rating
    /// — 10 tags it unless an explicit setType is in the patch or the set is a
    /// warm-up/dropset, and leaving 10 clears a failure tag.
    public static func applySetPatch(_ set: DraftSet, _ patch: SetPatch) -> DraftSet {
        var next = set
        if let w = patch.weightKg { next.weightKg = w }
        if let r = patch.reps { next.reps = r }
        if let rpe = patch.rpe { next.rpe = rpe }
        if let st = patch.setType { next.setType = st }
        if let d = patch.done { next.done = d }
        if let q = patch.quality { next.quality = q }

        let touchesRpe = patch.rpe != nil
        if touchesRpe { next = releaseRpeSeed(next) }
        if patch.done == true && next.rpe != nil { next = releaseRpeSeed(next) }

        if touchesRpe && patch.setType == nil {
            if next.rpe == failureRpe && next.setType == nil { next.setType = "failure" }
            else if next.rpe != failureRpe && next.setType == "failure" { next.setType = nil }
        }
        return next
    }

    /// Apply `patch` to `setIdx`, carry the new weight/reps to the NEXT set only
    /// (when it still holds the previous value; a 0 → n weight is a change of
    /// kind and never cascades), then re-resolve every inherited rating.
    public static func cascadeSetEdit(_ sets: [DraftSet], setIdx: Int, patch: SetPatch) -> [DraftSet] {
        guard sets.indices.contains(setIdx) else { return sets }
        let prev = sets[setIdx]
        var next = sets
        next[setIdx] = applySetPatch(prev, patch)
        let heir = setIdx + 1
        if heir < next.count {
            if let w = patch.weightKg, prev.weightKg > 0, next[heir].weightKg == prev.weightKg { next[heir].weightKg = w }
            if let r = patch.reps, next[heir].reps == prev.reps { next[heir].reps = r }
        }
        return next.map(applyRpeMemory)
    }

    /// The user has taken ownership of this rating; memory stops governing it.
    static func releaseRpeSeed(_ s: DraftSet) -> DraftSet {
        if s.rpeSeed == nil && s.rpeStale != true { return s }
        var next = s
        next.rpeSeed = nil; next.rpeSeedWeightKg = nil; next.rpeSeedReps = nil; next.rpeStale = nil
        return next
    }

    /// Reconcile one set's inherited rating with its current numbers.
    static func applyRpeMemory(_ s: DraftSet) -> DraftSet {
        guard let seed = s.rpeSeed, let w = s.rpeSeedWeightKg, let r = s.rpeSeedReps else { return s }
        let resolved = RpeMemory.resolveSeededRpe(RpeSeed(rpe: seed, weightKg: w, reps: r), weightKg: s.weightKg, reps: s.reps)
        if s.rpe == resolved.rpe && (s.rpeStale == true) == resolved.stale { return s }
        var next = s
        next.rpe = resolved.rpe
        next.rpeStale = resolved.stale ? true : nil
        return next
    }

    private static func cardioDuration(_ sec: Double) -> String {
        let m = (sec / 60).rounded(.down)
        let s = sec.truncatingRemainder(dividingBy: 60)
        if s == 0 { return "\(jsIntegerString(m)) min" }
        var ss = jsIntegerString(s)
        while ss.count < 2 { ss = "0" + ss }
        return "\(jsIntegerString(m)):\(ss) min"
    }

    /// "Treadmill: 0.4 km · 5 min" — the human-readable cardio summary.
    public static func cardioSummary(_ ex: DraftExercise) -> String {
        var parts: [String] = []
        if let d = ex.distanceKm { parts.append("\(jsIntegerString(d)) km") }
        if let s = ex.durationSec { parts.append(cardioDuration(s)) }
        if let i = ex.inclinePct, i != 0 { parts.append("\(jsIntegerString(i))% incline") }
        return parts.isEmpty ? ex.name : "\(ex.name): \(parts.joined(separator: " · "))"
    }

    /// The workout's NAME, without its strapline: the program day's own label,
    /// else the title up to its first `·`, else the split. Never empty.
    public static func cleanTitle(title: String?, dayKey: String?, splitDay: String, program: Program?) -> String {
        if let dayKey, !dayKey.isEmpty, let label = program?.day(key: dayKey)?.label { return label }
        let head = title?.components(separatedBy: "·").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !head.isEmpty { return head }
        return splitDay.isEmpty ? "Workout" : splitDay
    }
}
