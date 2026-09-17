import Foundation

/// What a training week amounted to — pure, so the verdicts can be tested
/// without a database, a clock or a screen.
///
/// ── WHY THE WEEK CLOSES ON THE LAST SESSION, NOT ON SUNDAY ──────────────────
/// `WeekReady.isComplete` is the calendar rule and the export uses it, because
/// a document claiming to be the week must not be written while days remain.
/// A wrap-up is a different object: it is the moment the work is DONE, and on a
/// plan that rests Saturday that moment is Friday evening. Waiting two more
/// days to say so means the summary arrives after you have stopped thinking
/// about the week it describes.
///
/// It is also deliberately not `WeekReady.isReady`, which asks whether every
/// training day *up to today* is logged and therefore turns true on a Tuesday.
/// `isWrapped` asks the stricter question: every training day the plan asks for
/// this week, past or future, has a session on it.
///
/// Cardio is not in the schedule and does not gate it. A walk on Sunday is not
/// a thing the training week is waiting for.
public enum WeeklyWrap {

    /// A drop must exceed this to be called a regression.
    ///
    /// ── WHY 2.5 % AND NOT "ANY DROP" ────────────────────────────────────────
    /// An e1RM is an estimate off a rep count, so one rep fewer at the same load
    /// moves it by about 3 % at ten reps and there is no session where that
    /// never happens. Flagging every one of those paints a normal week red and
    /// teaches the reader to ignore the colour, which costs the two real
    /// regressions a year their audience.
    public static let regressionThreshold = 0.025

    /// One movement's best set in a week, and what it was last week.
    public struct Movement: Equatable, Sendable, Identifiable {
        /// Name AND split. A lift that appears in two splits is deliberately
        /// two rows (see `dayKey` below), so keying identity on the name alone
        /// hands `ForEach` duplicate ids — a runtime warning, and undefined
        /// diffing in the very list this type exists to render.
        public var id: String { "\(name)|\(dayKey)" }
        public var name: String
        /// The split it was trained on — a movement in two splits is two rows,
        /// because the comparison is same-movement-same-day_key.
        public var dayKey: String
        public var weightKg: Double
        public var reps: Double
        /// Estimated 1RM of the top set. Nil on unloaded work, which has none.
        public var e1rm: Double?
        /// The same movement's e1RM on the same split last week, if it ran.
        public var previousE1rm: Double?

        public init(
            name: String, dayKey: String, weightKg: Double, reps: Double,
            e1rm: Double? = nil, previousE1rm: Double? = nil
        ) {
            self.name = name
            self.dayKey = dayKey
            self.weightKg = weightKg
            self.reps = reps
            self.e1rm = e1rm
            self.previousE1rm = previousE1rm
        }

        /// Fractional change against last week. Nil when either side is absent
        /// — a movement's first week has no verdict, and saying "new" is not
        /// the same as saying "no change".
        public var change: Double? {
            guard let e1rm, let previousE1rm, previousE1rm > 0 else { return nil }
            return (e1rm - previousE1rm) / previousE1rm
        }
    }

    /// The week's single biggest session, by the volume rule the rest of the
    /// app uses — every non-ghost row, warm-ups included.
    ///
    /// ── WHY IT CARRIES A DAY KEY AND NOT A LABEL ────────────────────────────
    /// "Legs A" is what the athlete's own `Program` calls `legs_a`, and a
    /// program can be renamed. Storing the rendered word would freeze one
    /// week's copy of a name the athlete may change tomorrow, and would put a
    /// presentation decision inside a pure summary. `Movement.dayKey` already
    /// set this precedent and the view already resolves it.
    public struct TopSession: Equatable, Sendable {
        public var dayKey: String
        public var date: String
        public var volumeKg: Double

        public init(dayKey: String, date: String, volumeKg: Double) {
            self.dayKey = dayKey
            self.date = date
            self.volumeKg = volumeKg
        }
    }

    /// What a movement did, once the deload rule has had its say.
    public enum Verdict: Equatable, Sendable {
        /// Beat last week by more than the threshold.
        case progressed
        /// Dropped by more than the threshold, in an ordinary week.
        case regressed
        /// Dropped by more than the threshold, in a DELOAD week — which is the
        /// plan working, not the lifter failing.
        case deloaded
        /// Inside the band, or nothing to compare against.
        case held
    }

    /// The verdict for one movement.
    ///
    /// ── WHY A DELOAD CANNOT PRODUCE A REGRESSION ────────────────────────────
    /// A deload week is a planned reduction in load. Every movement in it drops,
    /// by design, and a wrap-up that files eight red rows for a week that went
    /// exactly as intended is not reporting — it is punishing the user for
    /// following the plan. The drop is still SHOWN, with its own word, because
    /// hiding it would leave the week looking like nothing happened.
    public static func verdict(_ movement: Movement, isDeload: Bool) -> Verdict {
        guard let change = movement.change else { return .held }
        if change > regressionThreshold { return .progressed }
        if change < -regressionThreshold { return isDeload ? .deloaded : .regressed }
        return .held
    }

    /// Every training day the plan asks for this week has a session on it.
    ///
    /// `isTrainingDay` and `logged` are injected rather than read, so the rule
    /// stays pure and the caller decides what "the plan" means — which is the
    /// same contract `WeekReady` and every `Swap` function keep.
    ///
    /// A week the plan asks nothing of is never wrapped: there is no work to
    /// have finished, and a summary of it would be a page of dashes.
    public static func isWrapped(
        weekStart: String, logged: Set<String>, isTrainingDay: (String) -> Bool
    ) -> Bool {
        let due = (0..<7).compactMap { ISODate.addDays(weekStart, $0) }.filter(isTrainingDay)
        guard !due.isEmpty else { return false }
        return due.allSatisfy { logged.contains($0) }
    }

    /// The whole summary, assembled.
    public struct Summary: Equatable, Sendable {
        public var weekStart: String
        public var sessions: Int
        public var tonnageKg: Double
        /// This week's tonnage minus last week's. Nil with no week behind it.
        public var tonnageDeltaKg: Double?
        public var prCount: Int
        public var isDeload: Bool
        /// Every movement with a top set, heaviest-changed first.
        public var movements: [Movement]
        /// The week's last weigh-in, and the change across it.
        ///
        /// Carried but never shown by default on anything that leaves the
        /// phone — see the share card's own toggle. It is here rather than read
        /// separately by the card so the summary is one object the view cannot
        /// assemble half of.
        public var bodyweightKg: Double?
        public var bodyweightDeltaKg: Double?

        /// Where the week's work landed, in weighted sets per landmark.
        ///
        /// Carried on the summary rather than read beside it, for the reason
        /// stated above bodyweight: this is one object the view cannot assemble
        /// half of. Nil when the builder could not reach a store — a preview,
        /// or a summary assembled by hand in a test — and the ring simply does
        /// not draw, which is honest. A ring of zeroes is not.
        ///
        /// It is `MuscleFocusSummary` and NOT a bespoke tally, because
        /// `MuscleCredit.weightedSets` is the one accumulator every other
        /// surface counts a week with, and a fourth currency here would be the
        /// exact failure that consolidation ended.
        public var muscle: MuscleFocusSummary?

        /// The week's heaviest session by volume.
        ///
        /// Nil in a week with no rows — and equally in one where nothing was
        /// loaded, a bodyweight or cardio week, since a session of zero
        /// kilograms is not the biggest anything.
        public var topSession: TopSession?

        /// What to CALL this week — `Week 5`, or the phase's own label for a
        /// week before the plan's Week 0.
        ///
        /// ── WHY THE SUMMARY CARRIES ITS NAME (§W3) ──────────────────────────
        /// `Week.label(ofWeekStart:anchor:phases:)` is the one counter the app
        /// numbers a week with — History's capsules, the session masthead and
        /// the weekly export all take it — and it needs a phase table and a
        /// week-zero anchor, neither of which a VIEW holding a summary has. So
        /// the four screens that open this summary in a sheet all named the
        /// week by its DATE instead, out of a string built from `weekStart`,
        /// and W1's Past Weeks shelf then put `Week 5` directly above a sheet
        /// headed `Week of Sun 16 Aug`.
        ///
        /// The builder has both inputs, so it answers once and every door
        /// agrees. Nil for a summary assembled by hand (a preview, a test),
        /// where `WeeklyWrapContent.title` falls back to the date it always
        /// drew.
        public var label: String?

        public init(
            weekStart: String, sessions: Int, tonnageKg: Double, tonnageDeltaKg: Double? = nil,
            prCount: Int = 0, isDeload: Bool = false, movements: [Movement] = [],
            bodyweightKg: Double? = nil, bodyweightDeltaKg: Double? = nil,
            muscle: MuscleFocusSummary? = nil, topSession: TopSession? = nil,
            label: String? = nil
        ) {
            self.bodyweightKg = bodyweightKg
            self.bodyweightDeltaKg = bodyweightDeltaKg
            self.weekStart = weekStart
            self.sessions = sessions
            self.tonnageKg = tonnageKg
            self.tonnageDeltaKg = tonnageDeltaKg
            self.prCount = prCount
            self.isDeload = isDeload
            self.movements = movements
            self.muscle = muscle
            self.topSession = topSession
            self.label = label
        }

        public func movements(_ verdict: Verdict) -> [Movement] {
            movements
                .filter { WeeklyWrap.verdict($0, isDeload: isDeload) == verdict }
                .sorted { abs($0.change ?? 0) > abs($1.change ?? 0) }
        }

        public var progressions: [Movement] { movements(.progressed) }
        /// Empty in a deload week, by design — see `verdict`.
        public var regressions: [Movement] { movements(.regressed) }
        public var deloaded: [Movement] { movements(.deloaded) }

        /// The heaviest single set of the week, for the headline.
        ///
        /// By LOAD and not by e1RM: the headline is "the heaviest thing you
        /// picked up", which is a fact, where the best estimated max is an
        /// inference and belongs beside the reps it was inferred from.
        ///
        /// ── AND WHY `bestE1rm` SITS BESIDE IT RATHER THAN REPLACING IT ──────
        /// The reel shows BOTH, under different labels, because they answer two
        /// questions whose answers diverge constantly: 100 kg × 3 is the
        /// heaviest set of a week whose best estimated max came off 85 kg × 10.
        /// One figure under a label that could mean either is how "my heaviest
        /// lift" comes to name a set the lifter never performed.
        public var topSet: Movement? {
            movements.filter { $0.weightKg > 0 }.max { $0.weightKg < $1.weightKg }
        }

        /// The week's best estimated one-rep max — an INFERENCE, labelled as one.
        ///
        /// `> 0` and not `!= nil`: unloaded work has no estimate, and a lift
        /// carrying a stored zero has one that means the same thing. Both are
        /// excluded for the reason `topSet` excludes a zero load — a 61-second
        /// side plank is not in the running for either title.
        public var bestE1rm: Movement? {
            movements.filter { ($0.e1rm ?? 0) > 0 }.max { ($0.e1rm ?? 0) < ($1.e1rm ?? 0) }
        }

        /// The one movement that moved most.
        ///
        /// `progressions` is already sorted by the SIZE of the change, so this
        /// is its head and not a second sort with a second chance to disagree.
        public var topProgressed: Movement? { progressions.first }

        /// "Five sessions · 42,180 kg · 2 PRs" — one line, for the share card.
        public var headline: String {
            var parts = ["\(sessions) session\(sessions == 1 ? "" : "s")"]
            if tonnageKg > 0 { parts.append("\(jsIntegerString(jsRound(tonnageKg))) kg") }
            if prCount > 0 { parts.append("\(prCount) PR\(prCount == 1 ? "" : "s")") }
            return parts.joined(separator: " · ")
        }
    }
}
