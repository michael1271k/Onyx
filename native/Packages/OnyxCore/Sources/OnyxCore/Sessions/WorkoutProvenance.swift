import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Whose workout is it. Expansion W5.
//
// ── THE HOLE THIS CLOSES ─────────────────────────────────────────────────────
// `SessionMetrics` used to take the FIRST lifting `HKWorkout` overlapping a
// session as the watch's own record of it, and stamp its heart rate and energy
// MEASURED. Hevy stays in use (founder decision 7), and Hevy writes an
// `HKWorkout` of the same activity type over the same hour — so a Hevy log of
// the same session was adopted as Onyx's measurement, silently. Decision 8:
// a foreign strength workout overlapping a session is never adopted; Onyx
// keeps its own numbers and shows a one-card diff with Skip.
//
// Everything here is pure so the two rules — who owns a workout, and which one
// wins — are golden vectors (`workout-origin.json`, `workout-pick.json`), not
// behaviour that only a paired watch and a Hevy account could reproduce.
// ─────────────────────────────────────────────────────────────────────────────

/// Who wrote an `HKWorkout`.
public enum WorkoutOrigin: Equatable, Sendable, Hashable {
    /// This app, on either device: the watch app's bundle id is the phone
    /// app's with a `.watchkitapp` suffix, and either one may be the reader.
    case own
    /// Some other app, by the name Health shows for it ("Hevy", "Strong").
    case foreign(String)

    public var isOwn: Bool { self == .own }
}

public enum WorkoutProvenance {

    /// How far outside a session's own interval a workout may start or end
    /// and still be "this session": the watch is started a minute after the
    /// first set and stopped a minute before the last, and a Hevy log is
    /// typed in after the bar is racked.
    public static let overlapSlack: TimeInterval = 600

    /// Classify a workout by its source bundle id.
    ///
    /// ── NIL IS FOREIGN ──────────────────────────────────────────────────────
    /// A real `HKSource` always carries a bundle id, so `nil` only ever comes
    /// from a reader that did not fill it in. Reading that as "own" would be
    /// the exact silent adoption this file exists to stop; reading it as
    /// foreign costs a test double one string.
    public static func origin(sourceBundleId: String?, sourceName: String?, ownBundleId: String) -> WorkoutOrigin {
        guard let source = sourceBundleId, !source.isEmpty, !ownBundleId.isEmpty else {
            return .foreign(sourceName ?? "Unknown")
        }
        if source == ownBundleId
            || source.hasPrefix(ownBundleId + ".")
            || ownBundleId.hasPrefix(source + ".") {
            return .own
        }
        return .foreign(sourceName ?? source)
    }

    /// Whether a workout's interval touches a session's, with the slack.
    ///
    /// Closed on both ends: a workout that ends exactly at the slack boundary
    /// still counts. Empty or inverted intervals never overlap anything.
    public static func overlaps(
        workoutStart: Date, workoutEnd: Date,
        sessionStart: Date, sessionEnd: Date,
        slack: TimeInterval = overlapSlack
    ) -> Bool {
        guard workoutEnd >= workoutStart, sessionEnd >= sessionStart else { return false }
        return workoutStart <= sessionEnd.addingTimeInterval(slack)
            && workoutEnd >= sessionStart.addingTimeInterval(-slack)
    }

    /// One workout, reduced to what precedence needs.
    public struct Candidate: Equatable, Sendable {
        public var origin: WorkoutOrigin
        public var isLifting: Bool
        public var start: Date
        public var end: Date

        public init(origin: WorkoutOrigin, isLifting: Bool, start: Date, end: Date) {
            self.origin = origin
            self.isLifting = isLifting
            self.start = start
            self.end = end
        }
    }

    /// The verdict: which candidate (by index) the session's metrics may cite.
    public enum Pick: Equatable, Sendable {
        /// Our own record of the session — its figures are MEASURED.
        case own(Int)
        /// Only somebody else's record overlaps. Never adopted; offered.
        case foreign(Int)
        case none
    }

    /// Own wins. Among several of one origin, the one that covers most of the
    /// session wins; a tie keeps the earlier index. Non-lifting workouts and
    /// workouts outside the slack window are not candidates at all.
    public static func pick(
        _ candidates: [Candidate], sessionStart: Date, sessionEnd: Date, slack: TimeInterval = overlapSlack
    ) -> Pick {
        var bestOwn: (index: Int, covered: TimeInterval)?
        var bestForeign: (index: Int, covered: TimeInterval)?
        for (index, c) in candidates.enumerated() {
            guard c.isLifting,
                  overlaps(workoutStart: c.start, workoutEnd: c.end,
                           sessionStart: sessionStart, sessionEnd: sessionEnd, slack: slack)
            else { continue }
            let covered = max(0, min(c.end, sessionEnd).timeIntervalSince(max(c.start, sessionStart)))
            switch c.origin {
            case .own:
                if bestOwn.map({ covered > $0.covered }) ?? true { bestOwn = (index, covered) }
            case .foreign:
                if bestForeign.map({ covered > $0.covered }) ?? true { bestForeign = (index, covered) }
            }
        }
        if let bestOwn { return .own(bestOwn.index) }
        if let bestForeign { return .foreign(bestForeign.index) }
        return .none
    }
}
