import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The 4-axis personal-record engine — a port of the web app's `lib/training/prEngine.ts`.
// PURE: no database, no clock, no UI.
//
// One implementation, every caller. PR detection used to live inline in the
// save path, so the live deck could not reuse it and a client-side copy would
// inevitably drift — the app flashes a badge when you tick the set, then saves
// the session without recording one. The Swift port has the same shape for the
// same reason, and `pr-session.json` holds it to the TypeScript case by case.
//
// THE KEY IS GENERIC. Server-side it is an exercise id; on the live deck it is
// a name. The engine never interprets it, it only groups by it.
//
// RE-ENTRY WEEKS ARE NOT GATED HERE. A deload week used to suppress detection
// outright and silently ate real records. Beating a baseline is objectively
// true whatever the programming intent.
// ─────────────────────────────────────────────────────────────────────────────

/// FOUR AXES, and a session total is deliberately not one of them: a
/// `sessionVolume` axis was built on 2026-08-11 and withdrawn the same day for
/// firing on ordinary sessions where no load rose and no set was a best.
public enum PrAxis: String, Codable, Sendable, CaseIterable, Hashable {
    case weight, reps, volume, e1rm
}

/// A historical set row, pre-session. `est1rm` may be absent — it is recomputed.
public struct BaselineSetRow: Codable, Sendable {
    public var key: String
    public var weightKg: Double?
    public var reps: Double?
    public var est1rm: Double?
    /// Warm-ups and drop sets set no bar, exactly as they win no record.
    public var setType: String?
    /// Floor of the programmed rep window — gates whether this row sets the e1RM bar.
    public var repFloor: Double?
    /// Unilateral pairing: L and R of ONE physical set share a `pairId`.
    public var pairId: String?
    public var side: String?

    public init(
        key: String, weightKg: Double?, reps: Double?, est1rm: Double? = nil, setType: String? = nil,
        repFloor: Double? = nil, pairId: String? = nil, side: String? = nil
    ) {
        self.key = key; self.weightKg = weightKg; self.reps = reps; self.est1rm = est1rm
        self.setType = setType; self.repFloor = repFloor; self.pairId = pairId; self.side = side
    }
}

public struct PrCandidateSet: Codable, Sendable {
    public var key: String
    public var weightKg: Double
    /// Reps, or SECONDS for a timed hold.
    public var reps: Double
    public var setType: String?
    public var timed: Bool
    /// Floor of the programmed rep window, when there is one. Gates the e1RM axis.
    public var repFloor: Double?
    public var pairId: String?
    public var side: String?
    /// The session date and the set's place in it — carried for the ledger row.
    public var date: String?
    public var exerciseName: String?
    public var setNumber: Int?

    public init(
        key: String, weightKg: Double, reps: Double, setType: String? = nil, timed: Bool = false,
        repFloor: Double? = nil, pairId: String? = nil, side: String? = nil,
        date: String? = nil, exerciseName: String? = nil, setNumber: Int? = nil
    ) {
        self.key = key; self.weightKg = weightKg; self.reps = reps; self.setType = setType; self.timed = timed
        self.repFloor = repFloor; self.pairId = pairId; self.side = side
        self.date = date; self.exerciseName = exerciseName; self.setNumber = setNumber
    }
}

/// The fields the unilateral collapse reads. Both row types feed it.
public struct VolumeCreditRow: Codable, Sendable {
    public var weightKg: Double?
    public var reps: Double?
    public var pairId: String?
    public var side: String?
    public init(weightKg: Double?, reps: Double?, pairId: String? = nil, side: String? = nil) {
        self.weightKg = weightKg; self.reps = reps; self.pairId = pairId; self.side = side
    }
}

/// One `[key, value]` tuple of the TypeScript `PrBaselines`, which are arrays
/// of tuples rather than maps so they survive a JSON cache round-trip. Encoded
/// the same way here so the fixture decodes directly.
public struct KeyedValue: Codable, Equatable, Sendable {
    public var key: String
    public var value: Double
    public init(key: String, value: Double) { self.key = key; self.value = value }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        key = try c.decode(String.self)
        value = try c.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(key)
        try c.encode(value)
    }
}

/// Per-axis bests, insertion-ordered. `bestRepsAtWeight` is keyed `${key}|${weightKg}`.
public struct PrBaselines: Codable, Equatable, Sendable {
    public var bestWeight: [KeyedValue]
    public var bestRepsAtWeight: [KeyedValue]
    public var bestE1rm: [KeyedValue]
    /// Timed holds: best SECONDS (carried in `reps`).
    public var bestSeconds: [KeyedValue]
    /// Heaviest SINGLE-SET tonnage ever logged for the exercise.
    public var bestSetVolume: [KeyedValue]

    public init(
        bestWeight: [KeyedValue] = [], bestRepsAtWeight: [KeyedValue] = [], bestE1rm: [KeyedValue] = [],
        bestSeconds: [KeyedValue] = [], bestSetVolume: [KeyedValue] = []
    ) {
        self.bestWeight = bestWeight; self.bestRepsAtWeight = bestRepsAtWeight; self.bestE1rm = bestE1rm
        self.bestSeconds = bestSeconds; self.bestSetVolume = bestSetVolume
    }

    public static let empty = PrBaselines()
}

/// The lookup form of `PrBaselines`.
public struct PrIndex: Sendable {
    public var bestWeight: [String: Double] = [:]
    public var bestRepsAtWeight: [String: Double] = [:]
    public var bestE1rm: [String: Double] = [:]
    public var bestSeconds: [String: Double] = [:]
    public var bestSetVolume: [String: Double] = [:]
    public init() {}
}

/// What a set achieved on one axis, and the standing figure it beat.
public struct AxisRecord: Codable, Equatable, Sendable {
    /// The new record — the number this set set.
    public var value: Double
    /// The value it beat. Always present: a record REQUIRES an existing baseline.
    public var previous: Double
    public init(value: Double, previous: Double) { self.value = value; self.previous = previous }
}

public struct DetectedSet: Equatable, Sendable {
    public var axes: [PrAxis]
    public var est1rm: Double?
    /// Per winning axis, the new value and the one it beat — captured BEFORE the
    /// winner is folded into the index, because the ledger is upsert-on-conflict
    /// and destroys the old value.
    public var records: [PrAxis: AxisRecord]
}

public struct KeyAxes: Equatable, Sendable {
    public var key: String
    public var axes: [PrAxis]
}

public struct SessionPrResult: Sendable {
    /// Parallel to the input array.
    public var perSet: [DetectedSet]
    /// Distinct axes per exercise key, insertion-ordered.
    public var axesByKey: [KeyAxes]
    /// Total distinct axis-PRs across exercises. Matches `workout_sessions.pr_count`.
    public var prCount: Int
}

public struct RecordSet: Equatable, Sendable {
    public var weightKg: Double
    public var reps: Double
    public var value: Double
}

public struct AxisRecordSet: Equatable, Sendable {
    public var axis: PrAxis
    public var set: RecordSet
}

public struct ExerciseRecordSets: Equatable, Sendable {
    public var key: String
    public var records: [AxisRecordSet]
}

/// A `Map<string, number>` whose `set` is a max — insertion order kept, because
/// `PrBaselines` is emitted in it.
private struct OrderedBests {
    var keys: [String] = []
    var values: [String: Double] = [:]

    mutating func bump(_ k: String, _ v: Double) {
        if values[k] == nil { keys.append(k) }
        values[k] = Swift.max(values[k] ?? 0, v)
    }

    var entries: [KeyedValue] { keys.map { KeyedValue(key: $0, value: values[$0]!) } }
}

public enum PrEngine {
    // MARK: - Rules

    /// Is this set's rep count a fair basis for an estimated 1RM? ONE-SIDED, on
    /// the floor only: going below the programmed window is a strength test
    /// where Epley extrapolates hardest; going above the ceiling is the rep
    /// progression working as designed. Unprogrammed: reps ≥ 5.
    public static func e1rmEligible(_ reps: Double, floor: Double?) -> Bool {
        if let floor { return reps >= floor }
        return reps >= 5
    }

    /// Warm-ups and drop sets are never a top-set record, and a GHOST counts
    /// toward nothing at all — excluded on both sides of the ledger.
    public static func isPrIneligible(_ setType: String?) -> Bool {
        setType == "warmup" || setType == "dropset" || setType == "ghost"
    }

    /// The REPS axis applies only when the set carries no external load. On a
    /// loaded lift the load is the achievement and the rep count is the dial
    /// between load jumps; at 0 kg reps ARE the record (and it catches timed
    /// holds for free — their duration rides in `reps`).
    public static func repsAxisEligible(_ weightKg: Double) -> Bool { weightKg == 0 }

    /// Display label per axis. Timed holds show Duration. Whole words, no "PR " prefix.
    public static func axisLabel(_ axis: PrAxis, timed: Bool = false) -> String {
        switch axis {
        case .reps: return timed ? "Duration" : "Reps"
        case .weight: return "Weight"
        case .volume: return "Volume"
        case .e1rm: return "1RM"
        }
    }

    // MARK: - The unilateral collapse

    /// Per-row tonnage for the VOLUME axis, with L/R pairs collapsed to ONE
    /// credit — `min(w) × min(reps)`, the weaker side — on the row that
    /// completes the pair, and `nil` on the other side. Per-set volume is "the
    /// tonnage of ONE working set as logged", identical whether the movement was
    /// logged as a pair or as a bare unsided row (the 2026-08-05 bug: a doubled
    /// pair set a 130 kg bar no unsided set could clear). The session total
    /// keeps its ×2 in `SessionVolume`, where the question is how much was lifted.
    ///
    /// Anything that is not exactly one L and one R per `pairId` is malformed
    /// and scored as logged. An empty `pairId` is no `pairId`.
    public static func volumeCredits(_ rows: [VolumeCreditRow]) -> [Double?] {
        var out: [Double?] = rows.map { ($0.weightKg ?? 0) * ($0.reps ?? 0) }

        var groups: [String: [Int]] = [:]
        for (i, r) in rows.enumerated() {
            guard let p = r.pairId, !p.isEmpty, r.side == "L" || r.side == "R" else { continue }
            groups[p, default: []].append(i)
        }

        for idxs in groups.values {
            let l = idxs.first { rows[$0].side == "L" }
            let r = idxs.first { rows[$0].side == "R" }
            guard idxs.count == 2, let l, let r else { continue }
            let w = Swift.min(rows[l].weightKg ?? 0, rows[r].weightKg ?? 0)
            let reps = Swift.min(rows[l].reps ?? 0, rows[r].reps ?? 0)
            let last = Swift.max(l, r)
            for i in idxs { out[i] = nil }
            out[last] = w * reps
        }
        return out
    }

    // MARK: - Baselines

    /// How JavaScript prints the load inside the `${key}|${weightKg}` map key:
    /// `27.5`, `25`, `0` — never `25.0`.
    static func loadKey(_ key: String, _ weightKg: Double) -> String {
        "\(key)|\(jsIntegerString(weightKg))"
    }

    /// Fold historical rows into per-axis bests. `isTimed` decides which axes
    /// apply to a key. `floorFor` — hand it the session-less `personal_records` rows folded per key (`PrRecorder.floors`), resolved
    /// through whatever the key is, NEVER the raw book — supplies a bar the
    /// logged rows cannot account for, folded in last as just another contender.
    ///
    /// Symmetric with `absorbSet`: a row that cannot WIN an axis must not raise
    /// the bar for it. A stored `est1rm` is read with `||`, not `??` — rows
    /// written before Epley returned nil for unloaded work hold exactly 0, which
    /// is not an estimate.
    public static func buildBaselines(
        _ rows: [BaselineSetRow],
        isTimed: (String) -> Bool,
        floorFor: ((String) -> PrFloor?)? = nil
    ) -> PrBaselines {
        var bestWeight = OrderedBests(), bestRepsAtWeight = OrderedBests(), bestE1rm = OrderedBests()
        var bestSeconds = OrderedBests(), bestSetVolume = OrderedBests()

        // The volume bar is built under the SAME unilateral rule detection
        // scores candidates by, or a pair is judged against a per-side history.
        let credits = volumeCredits(rows.map { VolumeCreditRow(weightKg: $0.weightKg, reps: $0.reps, pairId: $0.pairId, side: $0.side) })

        for (i, r) in rows.enumerated() {
            if isPrIneligible(r.setType) { continue }
            if isTimed(r.key) {
                // A hold's only record is duration.
                if let reps = r.reps { bestSeconds.bump(r.key, reps) }
                continue
            }
            guard let w = r.weightKg else { continue }
            bestWeight.bump(r.key, w)
            guard let reps = r.reps else { continue }
            bestRepsAtWeight.bump(loadKey(r.key, w), reps)
            if let vol = credits[i] { bestSetVolume.bump(r.key, vol) }
            if e1rmEligible(reps, floor: r.repFloor) {
                let stored = r.est1rm ?? 0
                let e = stored != 0 ? stored : Epley.oneRepMax(weight: w, reps: reps)
                if let e { bestE1rm.bump(r.key, e) }
            }
        }

        // The asserted floor, folded in last: `bump` is a max, so a key ends at
        // max(logged, asserted). Only keys already present are visited — a
        // first-ever set is never a PR, so by the time a key could win anything
        // it is in `rows`. The visiting order is the TypeScript's set union.
        if let floorFor {
            var seen = Set<String>()
            var keys: [String] = []
            for k in bestWeight.keys + bestSeconds.keys + bestSetVolume.keys + bestE1rm.keys where seen.insert(k).inserted {
                keys.append(k)
            }
            for key in keys {
                guard let t = floorFor(key) else { continue }
                if let v = t.weight { bestWeight.bump(key, v) }
                if let v = t.e1rm { bestE1rm.bump(key, v) }
                if let v = t.volume { bestSetVolume.bump(key, v) }
                if let v = t.seconds { bestSeconds.bump(key, v) }
                // Unloaded rep records are per-LOAD, and the only load they have is zero.
                if let v = t.reps { bestRepsAtWeight.bump("\(key)|0", v) }
            }
        }

        return PrBaselines(
            bestWeight: bestWeight.entries, bestRepsAtWeight: bestRepsAtWeight.entries,
            bestE1rm: bestE1rm.entries, bestSeconds: bestSeconds.entries, bestSetVolume: bestSetVolume.entries
        )
    }

    /// Tuples → lookup. A later duplicate key wins, as `new Map(tuples)` does.
    public static func baselineIndex(_ b: PrBaselines?) -> PrIndex {
        func m(_ rows: [KeyedValue]) -> [String: Double] {
            var d: [String: Double] = [:]
            for r in rows { d[r.key] = r.value }
            return d
        }
        var idx = PrIndex()
        guard let b else { return idx }
        idx.bestWeight = m(b.bestWeight)
        idx.bestRepsAtWeight = m(b.bestRepsAtWeight)
        idx.bestE1rm = m(b.bestE1rm)
        idx.bestSeconds = m(b.bestSeconds)
        idx.bestSetVolume = m(b.bestSetVolume)
        return idx
    }

    // MARK: - Detection

    /// Which axes this set just set a record on. A record requires beating an
    /// EXISTING baseline — a first-ever log is a data point, not a PR.
    ///
    /// `volumeKg` is this row's credit from `volumeCredits`: `nil` on the earlier
    /// side of a unilateral pair, so one physical set cannot carry two volume
    /// trophies. (The TypeScript also accepts `undefined` for "plain
    /// weight × reps"; every caller here passes the credit, which already IS
    /// weight × reps for a bilateral row.)
    public static func detectSetPrs(_ set: PrCandidateSet, _ idx: PrIndex, volumeKg: Double?) -> [PrAxis] {
        if isPrIneligible(set.setType) { return [] }
        var axes: [PrAxis] = []

        if set.timed {
            if let best = idx.bestSeconds[set.key], set.reps > best { axes.append(.reps) }
            return axes
        }

        if let bw = idx.bestWeight[set.key], set.weightKg > bw { axes.append(.weight) }

        if repsAxisEligible(set.weightKg) {
            if let br = idx.bestRepsAtWeight[loadKey(set.key, set.weightKg)], set.reps > br { axes.append(.reps) }
        }

        if let vol = volumeKg, let bv = idx.bestSetVolume[set.key], vol > bv { axes.append(.volume) }

        if e1rmEligible(set.reps, floor: set.repFloor) {
            if let e1rm = Epley.oneRepMax(weight: set.weightKg, reps: set.reps), let be = idx.bestE1rm[set.key], e1rm > be {
                axes.append(.e1rm)
            }
        }
        return axes
    }

    /// Fold a set's result back into the index, so three identical top sets do
    /// not each claim the same record — the flag marks the set that SET it.
    public static func absorbSet(_ set: PrCandidateSet, _ idx: inout PrIndex, volumeKg: Double?) {
        if isPrIneligible(set.setType) { return }
        func bump(_ m: inout [String: Double], _ k: String, _ v: Double) { m[k] = Swift.max(m[k] ?? 0, v) }
        if set.timed { bump(&idx.bestSeconds, set.key, set.reps); return }
        bump(&idx.bestWeight, set.key, set.weightKg)
        bump(&idx.bestRepsAtWeight, loadKey(set.key, set.weightKg), set.reps)
        if let vol = volumeKg { bump(&idx.bestSetVolume, set.key, vol) }
        // Symmetric with detection: a set that cannot WIN the e1RM axis must not raise its bar.
        if e1rmEligible(set.reps, floor: set.repFloor), let e = Epley.oneRepMax(weight: set.weightKg, reps: set.reps) {
            bump(&idx.bestE1rm, set.key, e)
        }
    }

    /// What a set scored on an axis — the number the record IS.
    public static func axisValue(_ axis: PrAxis, _ set: PrCandidateSet, volumeKg: Double?, est1rm: Double?) -> Double {
        switch axis {
        case .weight: return set.weightKg
        case .reps: return set.reps
        case .volume: return volumeKg ?? set.weightKg * set.reps
        case .e1rm: return est1rm ?? 0
        }
    }

    /// The standing figure each winning axis beat, read out of the index BEFORE
    /// `absorbSet`. An asserted session can name an axis the arithmetic has no
    /// bar for; that axis is simply omitted — a delta against nothing is not a delta.
    private static func beatenBaselines(
        _ set: PrCandidateSet, _ idx: PrIndex, _ axes: [PrAxis], volumeKg: Double?, est1rm: Double?
    ) -> [PrAxis: AxisRecord] {
        var out: [PrAxis: AxisRecord] = [:]
        for axis in axes {
            let previous: Double?
            switch axis {
            case .weight: previous = idx.bestWeight[set.key]
            case .reps: previous = set.timed ? idx.bestSeconds[set.key] : idx.bestRepsAtWeight[loadKey(set.key, set.weightKg)]
            case .volume: previous = idx.bestSetVolume[set.key]
            case .e1rm: previous = idx.bestE1rm[set.key]
            }
            guard let previous else { continue }
            out[axis] = AxisRecord(value: axisValue(axis, set, volumeKg: volumeKg, est1rm: est1rm), previous: previous)
        }
        return out
    }

    /// ONE ULTIMATE RECORD PER AXIS PER EXERCISE, PER SESSION. Detection is
    /// chronological, so a climbing session hands the same axis to every rung;
    /// only the GROUP holding the session's best value keeps it. A unilateral
    /// pair is one group and wins or loses together. Ties keep the LATER set —
    /// and a tie can only arise between rows of one group, because `absorbSet`
    /// makes every later group beat the standing value strictly.
    public static func supersedeWithinSession(
        _ sets: [PrCandidateSet], _ perSet: inout [DetectedSet], credits: [Double?]
    ) {
        struct Held { var group: String; var value: Double }
        var best: [String: Held] = [:]
        // `pairId ?? '#i'` — verbatim, so an empty-string pairId groups as "".
        func groupOf(_ i: Int) -> String { sets[i].pairId ?? "#\(i)" }

        for (i, d) in perSet.enumerated() {
            for axis in d.axes {
                let k = "\(sets[i].key)|\(axis.rawValue)"
                let v = axisValue(axis, sets[i], volumeKg: credits[i], est1rm: d.est1rm)
                if let held = best[k], v < held.value { continue }
                best[k] = Held(group: groupOf(i), value: v)
            }
        }

        for i in perSet.indices where !perSet[i].axes.isEmpty {
            perSet[i].axes = perSet[i].axes.filter { best["\(sets[i].key)|\($0.rawValue)"]?.group == groupOf(i) }
        }
    }

    /// Run a whole session in order — the single entry point, so there is
    /// exactly one place where "what counts as a PR" is decided. `sets` MUST be
    /// in the order performed.
    ///
    /// ── THE ASSERTED ERA IS GONE (W2) ───────────────────────────────────────
    /// `PrSeed` declared the July 2026 record book by hand and suppressed
    /// detection for those sessions. Those records are materialised in
    /// `personal_records` and `workout_sets.is_pr`; the override was the
    /// founder's history compiled into the engine, and it is deleted. A replay
    /// of a July session now derives its records like any other — against the
    /// floors `personal_records` carries with no session (`floorFor`).
    public static func detectSessionPrs(_ sets: [PrCandidateSet], _ baselines: PrBaselines) -> SessionPrResult {
        var idx = baselineIndex(baselines)
        let credits = volumeCredits(sets.map { VolumeCreditRow(weightKg: $0.weightKg, reps: $0.reps, pairId: $0.pairId, side: $0.side) })

        var perSet: [DetectedSet] = []
        perSet.reserveCapacity(sets.count)
        for (i, s) in sets.enumerated() {
            let axes = detectSetPrs(s, idx, volumeKg: credits[i])
            // No load, no one-rep max to estimate — nil, never 0.
            let est1rm = s.timed ? nil : Epley.oneRepMax(weight: s.weightKg, reps: s.reps)
            // READ THE BEATEN BASELINE BEFORE ABSORBING.
            let records = beatenBaselines(s, idx, axes, volumeKg: credits[i], est1rm: est1rm)
            absorbSet(s, &idx, volumeKg: credits[i])
            perSet.append(DetectedSet(axes: axes, est1rm: est1rm, records: records))
        }

        supersedeWithinSession(sets, &perSet, credits: credits)

        // Rebuilt from the per-set axes so `pr_count`, `is_pr` and the ledger
        // can never disagree about what counted.
        var axesByKey: [KeyAxes] = []
        for (i, d) in perSet.enumerated() where !d.axes.isEmpty {
            if let j = axesByKey.firstIndex(where: { $0.key == sets[i].key }) {
                for a in d.axes where !axesByKey[j].axes.contains(a) { axesByKey[j].axes.append(a) }
            } else {
                var distinct: [PrAxis] = []
                for a in d.axes where !distinct.contains(a) { distinct.append(a) }
                axesByKey.append(KeyAxes(key: sets[i].key, axes: distinct))
            }
        }
        let prCount = axesByKey.reduce(0) { $0 + $1.axes.count }
        return SessionPrResult(perSet: perSet, axesByKey: axesByKey, prCount: prCount)
    }

    /// The set that actually earned each axis, per exercise — the values
    /// written to `personal_records`. Two sets in one session can each win the
    /// same axis (the engine absorbs as it goes); the larger value is filed,
    /// except `reps`, which keeps the LAST claimant because it is a per-LOAD
    /// record and loads ascend. `volume` files the winning set's own collapsed tonnage.
    public static func recordSets(_ sets: [PrCandidateSet], _ result: SessionPrResult) -> [ExerciseRecordSets] {
        var out: [ExerciseRecordSets] = []
        func put(_ key: String, _ axis: PrAxis, _ rec: RecordSet) {
            let k = out.firstIndex { $0.key == key } ?? {
                out.append(ExerciseRecordSets(key: key, records: []))
                return out.count - 1
            }()
            if let a = out[k].records.firstIndex(where: { $0.axis == axis }) {
                let held = out[k].records[a].set
                if axis == .reps || rec.value > held.value { out[k].records[a].set = rec }
            } else {
                out[k].records.append(AxisRecordSet(axis: axis, set: rec))
            }
        }

        let credits = volumeCredits(sets.map { VolumeCreditRow(weightKg: $0.weightKg, reps: $0.reps, pairId: $0.pairId, side: $0.side) })

        for (i, d) in result.perSet.enumerated() {
            let s = sets[i]
            for axis in d.axes {
                let value: Double
                switch axis {
                case .weight: value = s.weightKg
                case .reps: value = s.reps
                case .volume: value = credits[i] ?? s.weightKg * s.reps
                case .e1rm: value = d.est1rm ?? 0
                }
                put(s.key, axis, RecordSet(weightKg: s.weightKg, reps: s.reps, value: value))
            }
        }
        return out
    }
}
