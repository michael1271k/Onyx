import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Groups a session's best lifts by EXERCISE rather than by role, so a movement
// that wins Hardest, Heaviest and 1RM prints once with three lifts instead of
// three times. A port of the three role-maxima the Live Stats screen already
// computes inline (`LiveStatsView.topLifts`), pulled out here so a later wave
// can call it instead of reimplementing the grouping in the view.
//
// PURE: no Date, no locale, no I/O.
// ─────────────────────────────────────────────────────────────────────────────

public enum TopLifts {
    public struct Set: Equatable, Sendable {
        /// Display name / stable key — the caller decides; the engine only
        /// groups by this string, it never interprets it.
        public var exercise: String
        public var kg: Double
        public var reps: Int
        /// nil = unrated — an unrated set can never win Hardest.
        public var rpe: Double?
        /// Axes this set set a record on (from the live PR engine); empty when none.
        public var recordAxes: Swift.Set<PrAxis>

        public init(exercise: String, kg: Double, reps: Int, rpe: Double? = nil, recordAxes: Swift.Set<PrAxis> = []) {
            self.exercise = exercise
            self.kg = kg
            self.reps = reps
            self.rpe = rpe
            self.recordAxes = recordAxes
        }
    }

    /// The previous session's bests for one exercise, one figure per role.
    public struct Best: Equatable, Sendable {
        public var kg: Double?
        public var rpeKg: Double?
        public var e1rm: Double?

        public init(kg: Double? = nil, rpeKg: Double? = nil, e1rm: Double? = nil) {
            self.kg = kg
            self.rpeKg = rpeKg
            self.e1rm = e1rm
        }
    }

    /// Order = display order.
    public enum Role: CaseIterable, Sendable {
        case hardest, heaviest, oneRM
    }

    public enum Delta: Sendable {
        case up, down, flat
    }

    public struct Lift: Equatable, Sendable {
        public var role: Role
        /// rpe×kg for Hardest, kg for Heaviest, Epley e1RM for oneRM.
        public var figure: Double
        public var set: Set
        /// vs `previous[exercise]` on the same figure; nil when there is no previous.
        public var delta: Delta?
        /// The winning set carries the role's PR axis: Heaviest ↔ .weight,
        /// oneRM ↔ .e1rm. Hardest has no axis, so it is never a record.
        public var isRecord: Bool
    }

    public struct Group: Equatable, Sendable {
        public var exercise: String
        /// In Role order, only the roles this exercise won.
        public var lifts: [Lift]
    }

    /// A candidate scored for one role: the highest-scoring eligible set,
    /// keeping the LAST maximum on a tie — same rule `LiveStatsView.topLifts`
    /// uses today (`max(by:)` only replaces the leader on a strictly greater
    /// score, so it never displaces an equal, later winner ahead of it).
    private static func best(_ sets: [Set], score: (Set) -> Double?) -> (set: Set, figure: Double)? {
        var winner: (set: Set, figure: Double)?
        for s in sets {
            guard let figure = score(s) else { continue }
            if winner == nil || figure >= winner!.figure {
                winner = (s, figure)
            }
        }
        return winner
    }

    private static func delta(_ figure: Double, vs previous: Double?) -> Delta? {
        guard let previous else { return nil }
        let diff = figure - previous
        if diff > 0.05 { return .up }
        if diff < -0.05 { return .down }
        return .flat
    }

    /// The bar the deltas are drawn against: for each movement, the newest
    /// qualifying session that actually LIFTED it, folded to one figure per
    /// role. Keyed by `ExerciseAliases.canonicalName`, which is what the caller
    /// must key `Set.exercise` with.
    ///
    /// ── WHY NOT THE DECK'S OWN SEED, WHICH IS ALREADY IN MEMORY ─────────────
    /// A `SeedRow` is a PROPOSAL and not a memory. `SessionSeedBuilder
    /// .workingRows` rewrites every working row to the progression ladder's
    /// suggested load at the rep floor whenever a movement is `.ready`, and
    /// `RpeMemory.resolveSeededRpe` drops the remembered rating when it does.
    /// Drawing the arrow against that bar points it DOWN on a session where you
    /// beat last week by a kilo and merely missed the suggestion, and leaves
    /// Hardest with no bar at all on exactly the lifts the ladder just raised —
    /// which are the lifts a block exists to move. These rows are what was
    /// lifted.
    ///
    /// `sessions` newest first, as `sessionsForSeed` returns them. The first
    /// session that logged a WORKING set of a movement wins it: a session you
    /// warmed up for and abandoned is not evidence, which is the same walk
    /// `SessionSeedBuilder.seed` makes for its history tier.
    ///
    /// Pairs are NOT collapsed, because the candidate side does not collapse
    /// them either — a unilateral set is two candidates to `group`, and a bar
    /// folded to last session's weaker side would draw `▲` on an arm that did
    /// the same weight.
    public static func previousBests(sessions: [SeedSession], sets: [SeedSet]) -> [String: Best] {
        var bySession: [String: [String: [SeedSet]]] = [:]
        for set in sets {
            let key = ExerciseAliases.canonicalName(set.exerciseName)
            bySession[set.sessionId, default: [:]][key, default: []].append(set)
        }
        var out: [String: Best] = [:]
        for session in sessions {
            for (name, raw) in bySession[session.id] ?? [:] where out[name] == nil {
                // The same eligibility `group` applies to today's candidates:
                // a working set with a load and reps on it.
                let working = raw.filter {
                    SetTags.isWorkingSet($0.setType) && $0.weightKg > 0 && $0.reps > 0
                }
                guard !working.isEmpty else { continue }
                out[name] = Best(
                    kg: working.map(\.weightKg).max(),
                    rpeKg: working.compactMap { set in set.rpe.map { $0 * set.weightKg } }.max(),
                    e1rm: working.compactMap { OneRepMax.estimate(weight: $0.weightKg, reps: Double($0.reps)) }.max()
                )
            }
        }
        return out
    }

    public static func group(_ sets: [Set], previous: [String: Best]) -> [Group] {
        // Only sets with positive load and positive reps are eligible for any role.
        let eligible = sets.filter { $0.kg > 0 && $0.reps > 0 }

        var winners: [Role: (set: Set, figure: Double)] = [:]

        if let hardest = best(eligible, score: { s in
            guard let rpe = s.rpe else { return nil }
            return rpe * s.kg
        }) {
            winners[.hardest] = hardest
        }
        if let heaviest = best(eligible, score: { $0.kg }) {
            winners[.heaviest] = heaviest
        }
        // The exact expression the app already uses — see `LoggerModel.SetRow.estimated1RM`
        // in native/Onyx/Features/Logger/LoggerModel.swift, which calls this same
        // `Epley.oneRepMax`. Reused here rather than a second formula.
        if let oneRM = best(eligible, score: { OneRepMax.estimate(weight: $0.kg, reps: Double($0.reps)) }) {
            winners[.oneRM] = oneRM
        }

        // Group by exercise, ordered by the first role each exercise wins.
        var order: [String] = []
        var byExercise: [String: [Lift]] = [:]
        for role in Role.allCases {
            guard let (set, figure) = winners[role] else { continue }
            let previousFigure: Double?
            let recordAxis: PrAxis?
            switch role {
            case .hardest:
                previousFigure = previous[set.exercise]?.rpeKg
                recordAxis = nil
            case .heaviest:
                previousFigure = previous[set.exercise]?.kg
                recordAxis = .weight
            case .oneRM:
                previousFigure = previous[set.exercise]?.e1rm
                recordAxis = .e1rm
            }
            let lift = Lift(
                role: role,
                figure: figure,
                set: set,
                delta: delta(figure, vs: previousFigure),
                isRecord: recordAxis.map { set.recordAxes.contains($0) } ?? false
            )
            if byExercise[set.exercise] == nil {
                order.append(set.exercise)
            }
            byExercise[set.exercise, default: []].append(lift)
        }

        return order.map { Group(exercise: $0, lifts: byExercise[$0] ?? []) }
    }
}
