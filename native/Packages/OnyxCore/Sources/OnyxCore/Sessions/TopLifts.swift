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
        if let oneRM = best(eligible, score: { Epley.oneRepMax(weight: $0.kg, reps: Double($0.reps)) }) {
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
