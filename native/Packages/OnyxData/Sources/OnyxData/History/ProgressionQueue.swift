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
