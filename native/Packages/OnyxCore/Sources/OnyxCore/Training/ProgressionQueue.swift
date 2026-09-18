import Foundation

/// The Smart-Coach queue, pure — a port of the web app's `lib/training/progressionQueue.ts`
/// (§6.5). `OnyxData`'s `AppDatabase.progressionQueue` feeds it today's day
/// key and the ledger; the Workout tab's "Ready to progress" box draws it.
///
/// For every (exercise, routine day) target it grades the last two sessions
/// with the SAME strict engine the session view uses (`Ceilings.
/// progressionVerdict` — all working sets at the programmed ceiling, one
/// load, two consecutive sessions) and returns those that earned a load bump,
/// or are one session away. Derived purely from the last two sessions, so the
/// moment a heavier load is logged the old-load chain breaks and the alert
/// clears itself.
///
/// ── HISTORY IS SCOPED TO THE ROUTINE DAY, NOT THE EXERCISE ──────────────────
/// The rep ceiling comes from the day: Leg Press is 8–12 on Legs A and 12–15
/// on Legs B. A history fetched by exercise ALONE graded the Legs A target
/// (ceiling 12) against Legs B sets, and the coach said "add load" on a lift
/// that had not touched its own window. Rows are bucketed by (day, exercise,
/// session); a row whose session has no `dayKey` is dropped, not pooled.
public enum ProgressionQueue {

    /// An exercise as the active plan programs it on one day.
    public struct Target: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var dayKey: String
        public var dayLabel: String
        public var color: String

        public init(id: String, name: String, dayKey: String, dayLabel: String, color: String) {
            self.id = id
            self.name = name
            self.dayKey = dayKey
            self.dayLabel = dayLabel
            self.color = color
        }
    }

    /// A `workout_sets` row joined to the session that owns it. `startedAt`
    /// is the session instant — any string that sorts chronologically.
    public struct SetRow: Sendable, Equatable {
        public var exerciseId: String
        public var weightKg: Double
        public var reps: Double
        public var setType: String?
        /// Nullable, and most of the history is null — `Ceilings
        /// .underEffortCeiling` treats an unrated set as making no claim.
        /// Carried so the RPE ≤ 8.5 half of the progression rule is not dead
        /// code in the one place that grades it.
        public var rpe: Double?
        public var startedAt: String
        public var dayKey: String?

        public init(
            exerciseId: String, weightKg: Double, reps: Double, setType: String?,
            rpe: Double? = nil, startedAt: String, dayKey: String?
        ) {
            self.exerciseId = exerciseId
            self.weightKg = weightKg
            self.reps = reps
            self.setType = setType
            self.rpe = rpe
            self.startedAt = startedAt
            self.dayKey = dayKey
        }
    }

    public struct Alert: Codable, Sendable, Equatable {
        public var exerciseId: String
        public var name: String
        public var dayKey: String?
        public var dayLabel: String?
        public var dayColor: String?
        /// Recommended new load; nil for a timed hold ("extend the hold").
        public var suggestKg: Double?
        /// The TOP load of the latest session — the load the verdict is about.
        public var currentKg: Double?
        public var timed: Bool
        public var ceiling: Double?
        public var state: ProgressionState

        /// Public because the type is, and its fields are. The synthesised
        /// memberwise init is internal, so until now the only way to build one
        /// outside this module was to decode JSON — which the app's shot
        /// harness was reduced to doing to photograph a chip.
        public init(
            exerciseId: String, name: String, dayKey: String? = nil,
            dayLabel: String? = nil, dayColor: String? = nil,
            suggestKg: Double? = nil, currentKg: Double? = nil,
            timed: Bool = false, ceiling: Double? = nil, state: ProgressionState
        ) {
            self.exerciseId = exerciseId
            self.name = name
            self.dayKey = dayKey
            self.dayLabel = dayLabel
            self.dayColor = dayColor
            self.suggestKg = suggestKg
            self.currentKg = currentKg
            self.timed = timed
            self.ceiling = ceiling
            self.state = state
        }
    }

    static func key(_ dayKey: String, _ exerciseId: String) -> String { "\(dayKey)|\(exerciseId)" }

    /// `(day, exercise) → session instant → working sets`. Warm-ups and ghosts
    /// are dropped — a light opener is not evidence about a ceiling.
    static func bucket(_ rows: [SetRow]) -> [String: [String: [WorkingSet]]] {
        var out: [String: [String: [WorkingSet]]] = [:]
        for r in rows {
            guard SetTags.isWorkingSet(r.setType), let dk = r.dayKey, !dk.isEmpty else { continue }
            out[key(dk, r.exerciseId), default: [:]][r.startedAt, default: []].append(WorkingSet(weightKg: r.weightKg, reps: r.reps, rpe: r.rpe))
        }
        return out
    }

    /// The last two sessions for one bucket, oldest first — the shape
    /// `progressionVerdict` grades. Empty when never logged on that day.
    static func lastTwo(_ byExDay: [String: [String: [WorkingSet]]], dayKey: String, exerciseId: String) -> [[WorkingSet]] {
        guard let perEx = byExDay[key(dayKey, exerciseId)] else { return [] }
        return perEx.keys.sorted().suffix(2).map { perEx[$0]! }
    }

    /// The queue, in the order `targets` is given — plan order, day by day
    /// and within a day the order the session is performed in.
    public static func alerts(targets: [Target], rows: [SetRow], program: Program, phase: ProgramPhase = .cut) -> [Alert] {
        let byExDay = bucket(rows)
        var out: [Alert] = []
        for t in targets {
            let sessions = lastTwo(byExDay, dayKey: t.dayKey, exerciseId: t.id)
            guard let latest = sessions.last else { continue }
            let timed = TimedExercise.isTimed(t.name)
            let ceiling = timed
                ? Ceilings.holdTarget(for: t.name, dayKey: t.dayKey, program: program, phase: phase)
                : Ceilings.repWindow(for: t.name, dayKey: t.dayKey, program: program, phase: phase)?.ceiling
            let verdict = timed
                ? Ceilings.timedProgressionVerdict(sessions, targetSec: ceiling)
                : Ceilings.progressionVerdict(sessions, ceiling: ceiling)
            // one-more is surfaced too: seeing the trigger approach is more
            // use than silence followed by a sudden instruction.
            guard verdict.state == .ready || verdict.state == .oneMore else { continue }
            let working = latest.filter { $0.weightKg > 0 }
            out.append(Alert(
                exerciseId: t.id, name: t.name, dayKey: t.dayKey, dayLabel: t.dayLabel, dayColor: t.color,
                suggestKg: verdict.suggestKg,
                currentKg: working.map(\.weightKg).max(),
                timed: timed, ceiling: ceiling, state: verdict.state
            ))
        }
        return out
    }
}
