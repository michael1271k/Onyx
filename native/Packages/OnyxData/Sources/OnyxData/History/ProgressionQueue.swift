import Foundation
import GRDB
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// "Ready to progress" — the store side of `ProgressionQueue` (§6.5).
//
// Scoped to ONE day key: the lifts today's session asks for, graded over the
// last two sessions logged UNDER THAT KEY in the current era. The web queue
// walks the whole plan and scopes at the banner; here the Workout tab only
// ever asks about today, and reading the whole ledger to answer a question
// about five lifts was the cost the app-side scan paid.
// ─────────────────────────────────────────────────────────────────────────────

public extension AppDatabase {

    /// The plan's lifts for `dayKey`, in the order the day performs them, with
    /// the verdict over their last two sessions on that key. Empty when the
    /// program has no such day, or nothing has been logged under it.
    ///
    /// Sessions are attributed by their own `day_key`, never by the weekday —
    /// a swapped session still carries the key it was performed as. Rows from
    /// the other era are dropped, as the web does: a new block never inherits
    /// the old one's chain.
    /// - Parameter qualifying: the session ids `SessionSeedBuilder
    ///   .sessionsForSeed` already returned, when the caller has them. Passing
    ///   them avoids folding the same sessions and re-reading all of their sets
    ///   a second time — `AppDatabase.sessionSeed` needs both answers and would
    ///   otherwise pay for the read twice, on the main actor.
    func progressionQueue(
        dayKey: String, program: Program, phase: ProgramPhase, today: String,
        qualifying: Set<String>? = nil
    ) throws -> [ProgressionQueue.Alert] {
        guard let day = program.day(key: dayKey) else { return [] }
        let exercises = day.exercises(for: phase)
        guard !exercises.isEmpty else { return [] }

        // Canonical name → EVERY catalogue id it was logged under. A merged
        // alias leaves the same lift under two ids, and a chain split across
        // them is still one chain: rows are read for all of them and folded
        // onto the first.
        let wanted = Set(exercises.map { ExerciseAliases.canonicalName($0.name).lowercased() })
        var idsByName: [String: [String]] = [:]
        for row in try read({ db in try Exercise.fetchAll(db) }) {
            let canonical = ExerciseAliases.canonicalName(row.name).lowercased()
            if wanted.contains(canonical) { idsByName[canonical, default: []].append(row.id) }
        }

        var fold: [String: String] = [:]   // any id → the target's id
        let targets = exercises.compactMap { exercise -> ProgressionQueue.Target? in
            let canonical = ExerciseAliases.canonicalName(exercise.name)
            guard let ids = idsByName[canonical.lowercased()], let first = ids.first else { return nil }
            for id in ids { fold[id] = first }
            return ProgressionQueue.Target(
                id: first, name: canonical, dayKey: day.key, dayLabel: day.label,
                color: String(format: "#%06X", day.accent)
            )
        }
        guard !targets.isEmpty else { return [] }

        // ── THE SEED AND THE VERDICT READ THE SAME SESSIONS ─────────────────
        // `SessionSeedBuilder.sessionsForSeed` is the one rule: this day key,
        // this era, no maintenance week (decision 6). Grading a chain that
        // includes a deliberately lighter week, and then pre-filling the deck
        // from a list that excludes it, would put a `ready` chip on a load the
        // seed never proposed.
        //
        // Which plan owns a date, off the catalogue. The local store is ONE
        // user's mirror, so the goals row names the user (the same reading
        // `HistoryWeeks` and `sessionsForSeed` make).
        let user = localUserId()
        let ctx = try scheduleContext(userId: user)
        let owner = { (date: String) in Schedule.planId(owning: date, in: ctx) }
        let era = owner(today)
        let allowed = try qualifying
            ?? Set(sessionsForSeed(dayKey: dayKey, today: today).sessions.map(\.id))
        // The session instant, for ordering two sessions of one lift: the
        // ledger already comes date-then-started_at ordered, so the date plus
        // the row's position in that order is a sortable key without a second
        // read of `workout_sessions`.
        var instant: [String: String] = [:]
        var rows: [ProgressionQueue.SetRow] = []
        for r in try historySets(exerciseIds: Array(fold.keys), userId: user)
        where r.dayKey == dayKey && owner(r.date) == era && allowed.contains(r.sessionId) {
            if instant[r.sessionId] == nil {
                instant[r.sessionId] = "\(r.date)|\(String(format: "%06d", instant.count))"
            }
            rows.append(ProgressionQueue.SetRow(
                exerciseId: fold[r.exerciseId] ?? r.exerciseId, weightKg: r.weightKg, reps: Double(r.reps), setType: r.setType,
                rpe: r.rpe, startedAt: instant[r.sessionId]!, dayKey: r.dayKey
            ))
        }
        return ProgressionQueue.alerts(targets: targets, rows: rows, program: program, phase: phase)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The verdict line under Train's last-session ticket (Precision B2, decision
// Q18 · design 6): what the LAST session of a split did against the one
// before it, in one line — "+2.5 kg on 3 lifts · 2 PR · 4.4 t".
//
// The plan named it `ProgressionVerdict`; OnyxCore already owns that name
// (`Ceilings`' two-session ceiling verdict, the one `progressionQueue` grades
// with), so this is `SessionVerdict` — a verdict about a session, not a lift.
// ─────────────────────────────────────────────────────────────────────────────

public struct SessionVerdict: Sendable, Equatable {
    /// One movement's best working set: the heavier load, then more reps.
    public struct Top: Sendable, Equatable {
        public let weightKg: Double
        public let reps: Double
        public init(weightKg: Double, reps: Double) {
            self.weightKg = weightKg
            self.reps = reps
        }
    }

    /// Each lift whose top load went UP, by how much (kg), ascending.
    public var loadGains: [Double] = []
    /// Same top load, more reps.
    public var repLifts = 0
    /// The same top set, exactly.
    public var heldLifts = 0
    /// A lower top set — said, because a verdict that only counts wins is
    /// flattery (PRODUCT.md, principle 1).
    public var lighterLifts = 0
    public var prCount = 0
    public var tonnageKg = 0.0

    /// "+2.5 kg on 3 lifts · +reps on 1 lift · 1 lighter · 2 PRs · 4.4 t", each
    /// clause present only when it has something to say; "Held 5 lifts" when
    /// nothing moved. "PRs" plural, as the masthead and the ticket above it
    /// spell a count (the brief's "2 PR" would sit under a ticket saying
    /// "2 PRs"). Only lifts BOTH sessions held are compared: a movement
    /// that was added or dropped is not progress and not a loss.
    public var line: String {
        var parts: [String] = []
        if let lo = loadGains.first, let hi = loadGains.last {
            let amount = lo == hi ? Self.kg(lo) : Self.kg(lo) + "–" + Self.kg(hi)
            parts.append("+\(amount) kg on \(Self.lifts(loadGains.count))")
        }
        if repLifts > 0 { parts.append("+reps on \(Self.lifts(repLifts))") }
        if loadGains.isEmpty, repLifts == 0, heldLifts > 0 {
            parts.append("Held \(Self.lifts(heldLifts))")
        }
        if lighterLifts > 0 { parts.append("\(lighterLifts) lighter") }
        if prCount > 0 { parts.append(prCount == 1 ? "1 PR" : "\(prCount) PRs") }
        if tonnageKg > 0 { parts.append(String(format: "%.1f t", tonnageKg / 1000)) }
        return parts.joined(separator: " · ")
    }

    public static func build(current: [String: Top], previous: [String: Top],
                             prCount: Int, tonnageKg: Double) -> SessionVerdict {
        var out = SessionVerdict(prCount: prCount, tonnageKg: tonnageKg)
        for (name, now) in current {
            guard let before = previous[name] else { continue }
            if now.weightKg > before.weightKg {
                out.loadGains.append(now.weightKg - before.weightKg)
            } else if now.weightKg == before.weightKg, now.reps > before.reps {
                out.repLifts += 1
            } else if now.weightKg == before.weightKg, now.reps == before.reps {
                out.heldLifts += 1
            } else {
                out.lighterLifts += 1
            }
        }
        out.loadGains.sort()
        return out
    }

    /// Working sets only, a genuine L/R pair collapsed to min(load) × min(reps)
    /// — the weaker side, the rule `SessionVolume` scores a pair by — then the
    /// heaviest load per movement with reps breaking the tie. Keyed by the
    /// canonical lowercased name, the one join between a plan and a ledger.
    static func tops(_ rows: [HistorySetRow]) -> [String: Top] {
        var candidates: [(name: String, top: Top)] = []
        var pairs: [String: [HistorySetRow]] = [:]
        for row in rows where SetTags.isWorkingSet(row.setType) {
            let name = ExerciseAliases.canonicalName(row.exerciseName).lowercased()
            if let pair = row.pairId, row.side != nil {
                pairs["\(name)|\(pair)", default: []].append(row)
            } else {
                candidates.append((name, Top(weightKg: row.weightKg, reps: Double(row.reps))))
            }
        }
        for (key, sides) in pairs {
            let name = String(key.split(separator: "|", maxSplits: 1)[0])
            candidates.append((name, Top(weightKg: sides.map(\.weightKg).min() ?? 0,
                                         reps: Double(sides.map(\.reps).min() ?? 0))))
        }
        var out: [String: Top] = [:]
        for (name, top) in candidates where top.weightKg > 0 || top.reps > 0 {
            guard let held = out[name] else { out[name] = top; continue }
            if top.weightKg > held.weightKg || (top.weightKg == held.weightKg && top.reps > held.reps) {
                out[name] = top
            }
        }
        return out
    }

    private static func kg(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", (value * 100).rounded() / 100)
    }

    private static func lifts(_ n: Int) -> String { n == 1 ? "1 lift" : "\(n) lifts" }
}

public extension AppDatabase {
    /// The verdict for a finished session against the session of the SAME
    /// split before it (`day_key`, finished, earlier date or clock). Nil when
    /// the session is unknown or has no day key; a first session of its split
    /// still gets its records and tonnage.
    ///
    /// Records are the row's own `pr_count` and tonnage its
    /// `total_volume_kg` — the numbers the close path wrote, which is what the
    /// ticket above the line prints.
    func sessionVerdict(sessionId: String, userId: String) throws -> SessionVerdict? {
        let sessions = try sessionHistory(userId: userId)
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }),
              let dayKey = sessions[index].dayKey else { return nil }
        let session = sessions[index]
        // `sessionHistory` is newest first, so the first match after this
        // session's own position IS the one before it.
        let before = sessions[(index + 1)...].first { $0.dayKey == dayKey && $0.endedAt != nil }
        let current = SessionVerdict.tops(try historySets(sessionId: session.id, userId: userId))
        let previous = try before.map { SessionVerdict.tops(try historySets(sessionId: $0.id, userId: userId)) } ?? [:]
        return .build(current: current, previous: previous,
                      prCount: session.prCount ?? 0, tonnageKg: session.totalVolumeKg ?? 0)
    }
}
