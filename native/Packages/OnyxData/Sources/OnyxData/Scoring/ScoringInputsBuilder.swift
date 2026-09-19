import Foundation
import GRDB
import OnyxCore

/// What the caller resolves that this store cannot: the plan and the lever.
///
/// ── WHAT USED TO BE HERE ────────────────────────────────────────────────────
/// `sessionVolumeKg` and `newPRsToday` were holes too, back when `volume.ts`
/// and `prEngine.ts` were unported. Both are read out of the store now —
/// `SessionVolume` over the day's sets, `personal_records` for the date — so a
/// caller can no longer hand in a tonnage that double-counts a unilateral pair.
///
///   · `goals` — `levers.ts` + `dailyTargets.ts`. The stored `user_goals`
///     figures are the BASELINE, and a lever moves them: scoring against the
///     baseline while the app displays Lever 1's 1,885 kcal is a 70-kcal
///     difference between the goal shown and the goal graded, every day,
///     invisibly. Left `nil`, the stored values are used and the day is graded
///     against the baseline — the pre-lever behaviour, wrong in a known
///     direction rather than in an unknown one. `DayPlan` resolves it.
public struct ScoringSupplements: Sendable, Equatable {
    public var goals: ResolvedGoals?
    /// Inside a planned maintenance / deload week (`maintenance.ts`). Lowers the
    /// workout-drain ceiling and the relative floor, and nothing else.
    public var isMaintenance: Bool
    /// The programme's prescription for the day (`prescribedFor`). `nil` drops
    /// the coverage component rather than inventing a plan.
    public var plannedExercises: Double?
    public var plannedSets: Double?

    public init(
        goals: ResolvedGoals? = nil,
        isMaintenance: Bool = false,
        plannedExercises: Double? = nil,
        plannedSets: Double? = nil
    ) {
        self.goals = goals
        self.isMaintenance = isMaintenance
        self.plannedExercises = plannedExercises
        self.plannedSets = plannedSets
    }
}

/// The day's targets after the lever and any day override have been applied.
public struct ResolvedGoals: Sendable, Equatable {
    public var calorie: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var steps: Double

    public init(calorie: Double, protein: Double, carbs: Double, fat: Double, steps: Double) {
        self.calorie = calorie
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.steps = steps
    }
}

// MARK: - Gathering

public extension AppDatabase {

    /// One day's `ScoringInputs`, read out of the local store.
    ///
    /// A one-day `ScoringWindow` (W2): the same assembly the cascade runs
    /// over forty-nine days, so there is exactly one place that decides how
    /// rows become inputs. The six queries that used to be here are that
    /// window's loads.
    ///
    /// `nil` is the GHOST GUARD: a past day with no underlying data at all must
    /// never get a score row. Trailing baselines and rest-day logic can
    /// otherwise fabricate one out of nothing, and a score-only "ghost day"
    /// pollutes every chart that reads the journey. Today accumulates live and
    /// is exempt.
    func scoringInputs(
        userId: String,
        date: String,
        hoursAwake: Double,
        isRestDay: Bool,
        todayISO: String,
        isToday: Bool = false,
        supplements: ScoringSupplements = ScoringSupplements()
    ) throws -> ScoringInputs? {
        try writer.read { db in
            try ScoringWindow.load(db, userId: userId, dates: [date], todayISO: todayISO)
                .inputs(for: date, hoursAwake: hoursAwake, isToday: isToday, isRestDay: isRestDay, supplements: supplements)
        }
    }
}

// MARK: - Set arithmetic

extension AppDatabase {

    struct SetCounts {
        var exercises = 0
        var workingSets = 0
        var ghostSets = 0
        var failureSets = 0
    }

    static func sets(_ db: Database, sessionIds: [String], userId: String) throws -> [WorkoutSet] {
        guard !sessionIds.isEmpty else { return [] }
        return try WorkoutSet
            .filter(sessionIds.contains(Column("session_id")))
            // Ownership rides on the session (W11): a set has no `user_id` locally.
            .filter(sql: "session_id IN (SELECT id FROM workout_sessions WHERE user_id = ?)", arguments: [userId])
            .fetchAll(db)
    }

    static func countSets(_ rows: [WorkoutSet]) -> SetCounts {
        var counts = SetCounts()

        var exercises = Set<String>()
        var working = Set<String>()
        var ghosts = Set<String>()
        for row in rows {
            // ── GHOSTS LEAVE BOTH SIDES OF THE RATIO ────────────────────────
            // A ghost is a set the plan asked for that was deliberately not
            // done. Excluding it from the numerator while the prescription still
            // supplied the denominator graded a deliberate decision as an
            // incomplete session, and docked up to twelve points for it.
            guard Self.isWorkingSet(row.setType) else {
                if row.setType == "ghost" { ghosts.insert(row.pairId ?? row.id) }
                continue
            }
            exercises.insert(row.exerciseId)
            // Unilateral L/R sub-sets share a `pair_id` and are ONE set.
            working.insert(row.pairId ?? row.id)
            if row.setType == "failure" { counts.failureSets += 1 }
        }
        counts.exercises = exercises.count
        counts.workingSets = working.count
        counts.ghostSets = ghosts.count
        return counts
    }

    /// `isWorkingSet`, from `lib/training/setTags.ts`.
    ///
    /// One line, and it stays one line: "not a working set" was written as
    /// `setType !== 'warmup'` in roughly twenty places, so adding `ghost` meant
    /// finding all twenty and getting all twenty right. The ones that were
    /// missed failed silently and in the worst direction — a ghost became a
    /// baseline, and the coach paced against a set explicitly marked as not
    /// counting.
    static func isWorkingSet(_ setType: String?) -> Bool {
        setType != "warmup" && setType != "ghost"
    }

    /// `sessionVolumeKg` over local set rows: a unilateral pair scored once,
    /// at the weaker side. The widget builder reads through the same door.
    static func volume(_ sets: [WorkoutSet]) -> Double {
        SessionVolume.sessionVolumeKg(sets.map {
            VolumeSet(
                weightKg: $0.weightKg, reps: Double($0.reps),
                side: (try? SyncTranslation.side($0.side)) ?? nil, pairId: $0.pairId, setType: $0.setType
            )
        })
    }

    /// Mean severity over DISTINCT RECOGNISED muscles, max within each.
    ///
    /// A 1:1 port of `foldDomsSeverity` in the web app's `lib/recovery/soreness.ts`.
    /// Max rather than mean within a muscle, deliberately: "left quad severe,
    /// right quad fine" is a severe quad, and averaging it to moderate reports
    /// a day nobody had.
    static func foldDomsSeverity(_ rows: [DomsLogRow]) -> Double? {
        var peak: [String: Int] = [:]
        for row in rows where DomsMuscles.recognised.contains(row.muscleGroup) {
            peak[row.muscleGroup] = max(peak[row.muscleGroup] ?? 0, row.severity)
        }
        guard !peak.isEmpty else { return nil }
        return Double(peak.values.reduce(0, +)) / Double(peak.count)
    }

    /// The usual bedtime, as minutes past the night window's opening noon,
    /// for the `limit` nights before `date` — newest first. Noon-anchored so a
    /// bedtime either side of midnight is one continuous number (23:30 is
    /// 690, 00:16 is 736) and no wrap-around arithmetic exists to get wrong.
    /// UTC noon, like the window itself: a DST change moves every offset by
    /// sixty together, which the median absorbs within a fortnight.
    static func bedtimeOffsets(_ db: Database, userId: String, before date: String, limit: Int) throws -> [Double] {
        guard let window = NightWindow.range(date) else { return [] }
        return try SleepSessionRow
            .filter(Column("user_id") == userId && Column("start_time") < window.from)
            .order(Column("start_time").desc)
            .limit(limit)
            .fetchAll(db)
            .compactMap { row in
                NightWindow.range(NightWindow.nightOf(row.startTime)).map { row.startTime.timeIntervalSince($0.from) / 60 }
            }
    }

    /// The median of at least five, else nil — under five nights "usual" is a
    /// guess, and a guess is not a baseline.
    static func median(_ values: [Double]) -> Double? {
        guard values.count >= 5 else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
