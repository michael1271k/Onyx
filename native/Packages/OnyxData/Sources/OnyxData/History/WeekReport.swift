import Foundation
import GRDB
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// THE WEEK, AS A VALUE (W8)
//
// ── WHY IT LEFT THE VIEW ─────────────────────────────────────────────────────
// `WeekReport` was declared at the bottom of `Features/Workout/WeeklyReportView.
// swift`, in the app target, which had two consequences and only one of them
// was visible. The visible one: the weekly report lived on the Train tab and
// the Dashboard could not open the same page without importing a Workout
// feature file. The invisible one is worse — NOTHING in the repo could test it.
// `swift:core` and `swift:data` run the packages; the app target's own suite is
// `OnyxTests`, which `npm run check` does not run. A fold over the whole weekly
// payload, carrying nine derived figures, was verified by screenshot.
//
// Here it is a package type with a package test. `build(_:summary:plannedSessions:
// phase:)` is still PURE — no store, no clock, no locale — which is what lets
// every figure below be asserted against the payload field it claims to fold.
//
// ── ONE CALL, NOT NINE ───────────────────────────────────────────────────────
// Macros, water, micronutrients, muscle volume, sleep, battery, stress, DOMS,
// cardio, body composition and records are eleven tables, and a page that read
// them itself would be eleven queries that can disagree with the weekly export
// about the same week. `WeeklyExportBuilder.input(weekStart:today:)` already
// answers all of them — it is what the exported document is rendered out of —
// so this is a FOLD over that payload and not a second reader.
//
// TWO things are not in that payload and are read beside it: the phase table
// (for the band's hue and its era tag) and `daily_scores.sleep_score`. The
// second is deliberate rather than an omission — see `sleepScoreAvg`.
// ─────────────────────────────────────────────────────────────────────────────

public struct WeekReport: Sendable, Equatable {

    // MARK: - Identity

    public var phaseKind: PhaseKind?
    public var eraTag: String?
    public var rangeLabel: String

    // MARK: - The three banner capsules

    /// The mean stored `daily_scores.sleep_score` of the nights that have one.
    ///
    /// ── WHY IT IS A READ AND NOT A PAYLOAD FIELD ────────────────────────────
    /// `ExportDay` carries sleep MINUTES, deep, REM and awake — the inputs —
    /// and not the score. Adding the score to the payload would change the
    /// exported document and its golden fixture to serve one capsule on one
    /// screen, and the score is v2's five-term output (W3): a page that
    /// recomputed it from the minutes it does carry would be a second formula
    /// one refactor away from disagreeing with the Sleep tile.
    ///
    /// So it is read from the table that stores it, in `build(database:…)`, and
    /// the pure fold takes it as an argument.
    public var sleepScoreAvg: Double?
    /// The mean stored `battery_pct` of the days that have one — READINESS_MODEL
    /// §7's own output, not a fourth score.
    public var batteryAvg: Double?
    /// Days graded HIT ÷ days graded at all. Nil for a week where nothing was
    /// tracked — which is not the same week as one where nothing was hit.
    public var nutritionAdherencePct: Double?

    // MARK: - The three figures

    public var sessions: Int
    public var plannedSessions: Int
    public var tonnageKg: Double
    public var tonnageDeltaKg: Double?
    public var prCount: Int
    /// Tonnage per week from the plan's Week 0 to this one, oldest first —
    /// `WeeklyExportInput.ledger`, which is the one weekly series the payload
    /// already carries. Sessions and PRs have no such series and their cells
    /// draw no trail; `Sparkline` declines to draw under two points, which is
    /// the honest picture of "there is no history to show" rather than a flat
    /// line at zero.
    public var tonnageSpark: [Double]

    // MARK: - Body

    public var bodyweightKg: Double?
    public var bodyweightDeltaKg: Double?
    /// The week's last BELIEVED scan, reduced to the three figures a week is
    /// read by. An `anomaly` row is excluded — the export prints it and refuses
    /// to average it, and a weekly summary is an average.
    public var bodyFatPct: Double?
    public var muscleMassKg: Double?
    public var scanDate: String?

    // MARK: - Training

    /// Weighted sets against the `plan_phase_volume` target, one row per
    /// landmark, in `LandmarkMuscle` declaration order — `WeeklyExportInput.
    /// volumeByMuscle`, re-expressed as the type the heat strip and the atlas
    /// already read. A second muscle currency here is the exact failure
    /// consolidation ended.
    public var volumeByMuscle: [OnyxSnapshot.MuscleVolume]
    /// The four muscles the week actually went into, most worked first.
    public var topMuscles: [LandmarkMuscle]
    /// Hardest, Heaviest and best estimated 1RM of the whole week.
    public var strongest: [TopLifts.Group]

    // MARK: - Nutrition

    /// The seven days as verdicts — the strip.
    public var adherence: [AdherenceDay]
    /// Calories logged, per day. A day with no entry is omitted, never zero.
    public var kcalByDay: [OnyxSnapshot.Point]
    /// The rule the bars are read against: the MEAN of the per-date targets in
    /// force across the week.
    ///
    /// Mean and not "today's": a week that stepped from Baseline to Lever 1 on
    /// Thursday was eaten to two different numbers, and grading it against
    /// either one alone is grading four days against a target they never had.
    /// Nil for a store whose ladder has never been written.
    public var kcalTarget: Double?
    public var macroTable: [MacroRow]
    /// The micronutrients worth acting on — a floor the week missed, a ceiling
    /// it exceeded, or a reading the document does not believe. Built out of
    /// `WeeklyExport.weeklyNutrients`, which is the one place the week's
    /// micronutrient means (and the implausible days they exclude) are decided.
    public var flaggedMicros: [MicroRow]
    public var waterMlPerDay: Double?
    public var waterGoalMl: Double?

    // MARK: - Recovery

    /// Hours asleep, per night. Nights with no reading are omitted.
    public var sleepByDay: [OnyxSnapshot.Point]
    public var sleepGoalHours: Double?
    /// The week's battery, oldest first — the trail under the Recovery card.
    public var batterySpark: [Double]
    /// The mean level of the week's `stress_logs` rows. Nil for a week that
    /// logged none, which is not a calm week.
    public var stressMean: Double?
    /// The week's single worst soreness rating, and what it was.
    public var domsPeak: DomsPeak?

    // MARK: - Cardio

    public var cardio: CardioTotals?

    // MARK: - Records

    /// Every record the week set, sorted BY EXERCISE — because a record is a
    /// fact about a movement and the question a reader brings here is "what
    /// moved"; a list ordered by Tuesday answers a question about Tuesday.
    ///
    /// The page draws `topRecords` and puts the rest behind a disclosure. The
    /// cap is stated here rather than taken by the view so that "three, and
    /// there are more" is one decision with one number in it.
    public var records: [ExportPr]

    /// How many records a closed week shows before it stops being a list and
    /// starts being a table.
    public static let recordCap = 3

    public var topRecords: [ExportPr] { Array(records.prefix(Self.recordCap)) }
    public var hasMoreRecords: Bool { records.count > Self.recordCap }

    // MARK: - Parts

    /// One macro, as the week ate it against the rung it was on.
    public struct MacroRow: Sendable, Equatable, Identifiable {
        public var label: String
        /// Daily mean over the days that logged this macro. Nil for a macro
        /// the profile does not track (`trackCarbs`, `trackFat`).
        public var mean: Double?
        public var target: Double?
        public var unit: String
        public var id: String { label }

        public init(label: String, mean: Double?, target: Double?, unit: String) {
            self.label = label; self.mean = mean; self.target = target; self.unit = unit
        }

        /// Mean ÷ target × 100, or nil without both.
        public var pct: Double? {
            guard let mean, let target, target > 0 else { return nil }
            return mean / target * 100
        }
    }

    /// One micronutrient the week is asked to act on.
    public struct MicroRow: Sendable, Equatable, Identifiable {
        public var label: String
        /// The weekly mean total — food plus stack — over the days the document
        /// believes.
        public var value: Double
        public var target: Double
        public var unit: String
        public var kind: NutrientTarget.Kind
        public var pct: Double?
        /// At least one day of this nutrient was implausible and was dropped
        /// from the mean. Stated, because a mean over four days where two were
        /// discarded is a different claim from a mean over six.
        public var doubted: Bool
        public var id: String { label }

        public init(
            label: String, value: Double, target: Double, unit: String,
            kind: NutrientTarget.Kind, pct: Double?, doubted: Bool
        ) {
            self.label = label; self.value = value; self.target = target
            self.unit = unit; self.kind = kind; self.pct = pct; self.doubted = doubted
        }

        /// Is this row a MISS? A floor under 80 % and a ceiling over 100 %.
        public var isBreach: Bool {
            guard let pct else { return false }
            return kind == .floor ? pct < 80 : pct > 100
        }
    }

    public struct DomsPeak: Sendable, Equatable {
        public var muscle: String
        public var severity: Double
        public var date: String
        public init(muscle: String, severity: Double, date: String) {
            self.muscle = muscle; self.severity = severity; self.date = date
        }
    }

    public struct CardioTotals: Sendable, Equatable {
        public var bouts: Int
        public var minutes: Double
        public var km: Double?
        public var kcal: Double?
        /// The kinds the week held, most frequent first — `Walk · Run`.
        public var kinds: [String]
        public init(bouts: Int, minutes: Double, km: Double?, kcal: Double?, kinds: [String]) {
            self.bouts = bouts; self.minutes = minutes; self.km = km
            self.kcal = kcal; self.kinds = kinds
        }
    }

    public init(
        phaseKind: PhaseKind? = nil, eraTag: String? = nil, rangeLabel: String,
        sleepScoreAvg: Double? = nil, batteryAvg: Double? = nil, nutritionAdherencePct: Double? = nil,
        sessions: Int, plannedSessions: Int, tonnageKg: Double, tonnageDeltaKg: Double? = nil,
        prCount: Int, tonnageSpark: [Double] = [],
        bodyweightKg: Double? = nil, bodyweightDeltaKg: Double? = nil,
        bodyFatPct: Double? = nil, muscleMassKg: Double? = nil, scanDate: String? = nil,
        volumeByMuscle: [OnyxSnapshot.MuscleVolume] = [], topMuscles: [LandmarkMuscle] = [],
        strongest: [TopLifts.Group] = [],
        adherence: [AdherenceDay] = [], kcalByDay: [OnyxSnapshot.Point] = [],
        kcalTarget: Double? = nil, macroTable: [MacroRow] = [], flaggedMicros: [MicroRow] = [],
        waterMlPerDay: Double? = nil, waterGoalMl: Double? = nil,
        sleepByDay: [OnyxSnapshot.Point] = [], sleepGoalHours: Double? = nil,
        batterySpark: [Double] = [], stressMean: Double? = nil, domsPeak: DomsPeak? = nil,
        cardio: CardioTotals? = nil, records: [ExportPr] = []
    ) {
        self.phaseKind = phaseKind
        self.eraTag = eraTag
        self.rangeLabel = rangeLabel
        self.sleepScoreAvg = sleepScoreAvg
        self.batteryAvg = batteryAvg
        self.nutritionAdherencePct = nutritionAdherencePct
        self.sessions = sessions
        self.plannedSessions = plannedSessions
        self.tonnageKg = tonnageKg
        self.tonnageDeltaKg = tonnageDeltaKg
        self.prCount = prCount
        self.tonnageSpark = tonnageSpark
        self.bodyweightKg = bodyweightKg
        self.bodyweightDeltaKg = bodyweightDeltaKg
        self.bodyFatPct = bodyFatPct
        self.muscleMassKg = muscleMassKg
        self.scanDate = scanDate
        self.volumeByMuscle = volumeByMuscle
        self.topMuscles = topMuscles
        self.strongest = strongest
        self.adherence = adherence
        self.kcalByDay = kcalByDay
        self.kcalTarget = kcalTarget
        self.macroTable = macroTable
        self.flaggedMicros = flaggedMicros
        self.waterMlPerDay = waterMlPerDay
        self.waterGoalMl = waterGoalMl
        self.sleepByDay = sleepByDay
        self.sleepGoalHours = sleepGoalHours
        self.batterySpark = batterySpark
        self.stressMean = stressMean
        self.domsPeak = domsPeak
        self.cardio = cardio
        self.records = records
    }
}

// MARK: - The read

public extension WeekReport {

    /// The store read. Three calls, and every one of them already existed: the
    /// export payload, the schedule context every other week-shaped reader
    /// takes, and the seven `daily_scores` rows.
    nonisolated static func build(
        database: AppDatabase, userId: String, summary: WeeklyWrap.Summary,
        plannedSessions: Int, today: String
    ) -> WeekReport? {
        // ── THE SAME FALLBACK EVERY OTHER READER MAKES ──────────────────────
        // Nothing is signed in inside the shot harness or a preview, so
        // `AppEnvironment.userIdString` is the empty string there — and an
        // export built for "" comes back with seven empty days, which draws a
        // page that says "no day was graded" over a store holding a full week.
        // `localUserId()` is what `WorkoutWeek.library()` and every preview
        // reader already fall back to: the one user the rows belong to.
        let user = userId.isEmpty ? database.localUserId() : userId
        guard let input = try? WeeklyExportBuilder(database: database, userId: user)
            .input(weekStart: summary.weekStart, today: today)
        else { return nil }
        // The phase table, for the band's hue and its era tag. `weekPhase` is
        // how every other surface asks a week what block it is in.
        let phases = (try? database.scheduleContext(userId: user, today: summary.weekStart))?.phases ?? []
        let scores = (try? database.dailyScores(
            userId: user, from: input.weekStart, to: input.weekEnd
        )) ?? []
        return build(
            input, summary: summary, plannedSessions: plannedSessions,
            phase: Phases.weekPhase(weekStart: summary.weekStart, in: phases),
            sleepScores: scores.compactMap { $0.sleepScore.map(Double.init) }
        )
    }

    /// PURE from here down — no store, no clock, no locale beyond the range
    /// label the payload already carries. Which is what lets every figure be
    /// asserted against the source it claims to summarise.
    nonisolated static func build(
        _ input: WeeklyExportInput, summary: WeeklyWrap.Summary,
        plannedSessions: Int, phase: WeekPhase?, sleepScores: [Double] = []
    ) -> WeekReport {

        // ── NUTRITION ───────────────────────────────────────────────────────
        // `MacroAdherenceSeries.build` and its ±10 % tolerance, graded against
        // the rung that was in force ON EACH DATE — `targetPeriods` — and not
        // against today's. A week spent on Lever 1 that was then read after a
        // step back to Baseline would otherwise be graded against numbers it
        // was never eating to.
        var targets: [String: AdherenceTargets] = [:]
        for period in input.targetPeriods ?? [] {
            for date in period.dates {
                targets[date] = AdherenceTargets(
                    kcal: period.goals.calorie, protein: period.goals.protein,
                    carbs: period.goals.carbs, fat: period.goals.fat
                )
            }
        }
        // The week-level goal is the fallback for a payload with no periods on
        // it — a store whose ladder has never been written.
        if targets.isEmpty, let kcal = input.calorieGoal {
            for day in input.days {
                targets[day.date] = AdherenceTargets(kcal: kcal, protein: input.proteinGoalG)
            }
        }
        let adherence = MacroAdherenceSeries.build(
            input.days.map {
                AdherenceDayIn(
                    date: $0.date, kcal: $0.calories, proteinG: $0.proteinG,
                    carbsG: $0.carbsG, fatG: $0.fatG,
                    exception: $0.nutritionException, estimated: $0.nutritionEstimated
                )
            },
            targets: targets, endingOn: input.weekEnd, limit: 7
        )
        // GRADED days only. An exception day is declared, an untracked day was
        // never logged, and counting either as a miss punishes the athlete for
        // a Saturday they told the app about in advance.
        let graded = adherence.filter { $0.verdict == .hit || $0.verdict == .miss }
        let hits = adherence.filter { $0.verdict == .hit }.count
        let nutritionAdherencePct = graded.isEmpty
            ? nil
            : Double(hits) / Double(graded.count) * 100

        let kcalByDay = input.days.compactMap { day in
            day.calories.map { OnyxSnapshot.Point(d: day.date, v: $0) }
        }
        let weekTargets = input.days.compactMap { targets[$0.date]?.kcal }
        let kcalTarget = weekTargets.isEmpty
            ? nil
            : jsRound(weekTargets.reduce(0, +) / Double(weekTargets.count))

        // ── WATER ───────────────────────────────────────────────────────────
        // `WaterTruth` is the one rule, and the payload has already applied the
        // half of it that needs two stores: `ExportDay.waterMl` is the ledger's
        // sum where the ledger has rows and `daily_logs.water_ml` where it does
        // not. What is left is the rule's other half — a stored zero is a day
        // nobody measured, not a day nobody drank on — and passing an empty
        // ledger is how that half is applied without a second copy of it here.
        let water = input.days.compactMap { WaterTruth.ml(log: $0.waterMl, ledger: []) }
        let waterMlPerDay = water.isEmpty ? nil : water.reduce(0, +) / Double(water.count)

        // ── RECOVERY ────────────────────────────────────────────────────────
        // The stored battery, averaged over the nights that have one. Not
        // rebuilt and not re-scored: READINESS_MODEL §7 says `battery_pct` is
        // the output, and a page that recomputed it would be a second formula
        // one refactor away from disagreeing with the tile that shows it daily.
        let battery = input.days.compactMap(\.batteryPct)
        let batteryAvg = battery.isEmpty ? nil : battery.reduce(0, +) / Double(battery.count)
        let sleepScoreAvg = sleepScores.isEmpty
            ? nil
            : sleepScores.reduce(0, +) / Double(sleepScores.count)
        let sleepByDay = input.days.compactMap { day in
            day.sleepMin.map { OnyxSnapshot.Point(d: day.date, v: jsRound1($0 / 60)) }
        }
        let stress = (input.stress ?? []).map(\.level)
        let stressMean = stress.isEmpty ? nil : jsRound1(stress.reduce(0, +) / Double(stress.count))
        // The worst rating of the week, ties broken by DATE then muscle — a
        // dictionary has no order and two 4s on two muscles must not name a
        // different one on each build.
        let domsPeak = input.doms
            .max { a, b in
                (a.severity, b.date, b.muscle) < (b.severity, a.date, a.muscle)
            }
            .map { DomsPeak(muscle: $0.muscle, severity: $0.severity, date: $0.date) }

        // ── RECORDS ─────────────────────────────────────────────────────────
        // Off `ExportSession.prs`, which the builder reconstructs from the
        // `personal_records` rows achieved inside the week. Sorted by EXERCISE,
        // and a movement that set two axes on two days prints twice — the axes
        // differ, so the rows are different facts.
        let records = input.sessions.flatMap(\.prs).sorted {
            ($0.name, $0.weightKg) < ($1.name, $1.weightKg)
        }

        // ── STRONGEST ───────────────────────────────────────────────────────
        // `TopLifts.group` over the WEEK's working sets rather than a session's.
        // Warm-ups and ghosts are excluded here exactly as the engine excludes
        // them from a session: they win no role because they set no bar.
        // `previous: [:]` — the arrow is a SESSION-to-session comparison and
        // there is no "last week's hardest set of the week" to point it at.
        let sets: [TopLifts.Set] = input.sessions.flatMap { session in
            session.exercises.flatMap { exercise in
                exercise.sets
                    .filter { $0.warmup != true && $0.ghost != true }
                    .map {
                        TopLifts.Set(
                            exercise: exercise.name, kg: $0.weightKg,
                            reps: Int($0.reps), rpe: $0.rpe
                        )
                    }
            }
        }

        // ── BODY ────────────────────────────────────────────────────────────
        // The week's LAST believed scan. An `anomaly` row is printed by the
        // export and excluded from every mean it takes; a weekly summary is a
        // mean, so it is excluded here too.
        let scan = (input.bodyComp ?? [])
            .filter { $0.anomaly == nil }
            .max { $0.date < $1.date }

        return WeekReport(
            phaseKind: phase?.kind,
            eraTag: phase?.eraTag,
            rangeLabel: WeekWindow(
                containing: input.weekStart,
                startDay: ISODate.weekday(input.weekStart) ?? 0,
                today: input.weekEnd
            ).rangeLabel,
            sleepScoreAvg: sleepScoreAvg,
            batteryAvg: batteryAvg,
            nutritionAdherencePct: nutritionAdherencePct,
            sessions: summary.sessions,
            plannedSessions: plannedSessions,
            tonnageKg: summary.tonnageKg,
            tonnageDeltaKg: summary.tonnageDeltaKg,
            prCount: summary.prCount,
            tonnageSpark: (input.ledger ?? []).compactMap(\.totals.totalVolumeKg),
            bodyweightKg: summary.bodyweightKg,
            bodyweightDeltaKg: summary.bodyweightDeltaKg,
            bodyFatPct: scan?.bodyFatPct,
            muscleMassKg: scan?.muscleMassKg ?? scan?.skeletalMuscleMassKg,
            scanDate: scan?.date,
            volumeByMuscle: muscleVolume(input.volumeByMuscle),
            topMuscles: topMuscles(input.volumeByMuscle),
            strongest: TopLifts.group(sets, previous: [:]),
            adherence: adherence,
            kcalByDay: kcalByDay,
            kcalTarget: kcalTarget,
            macroTable: macroTable(input.days, targets: targets),
            flaggedMicros: flaggedMicros(input.days),
            waterMlPerDay: waterMlPerDay,
            waterGoalMl: input.waterGoalMl,
            sleepByDay: sleepByDay,
            sleepGoalHours: input.sleepGoalHours,
            batterySpark: battery,
            stressMean: stressMean,
            domsPeak: domsPeak,
            cardio: cardio(input.cardio ?? []),
            records: records
        )
    }

    // MARK: - The folds

    /// `VolumeByMuscle` → the one muscle currency the atlas, the heat strip and
    /// the Muscle tile already read. A row whose `muscle` is not a landmark is
    /// dropped rather than passed through: the strip keys on `LandmarkMuscle`
    /// and a token it cannot resolve would draw a cell with no name.
    nonisolated static func muscleVolume(_ rows: [VolumeByMuscle]) -> [OnyxSnapshot.MuscleVolume] {
        rows.compactMap { row in
            guard LandmarkMuscle(rawValue: row.muscle) != nil else { return nil }
            return OnyxSnapshot.MuscleVolume(
                muscle: row.muscle, sets: row.sets, target: Int(row.target.rounded())
            )
        }
    }

    /// The four the week actually went into, most weighted sets first. Ties
    /// broken by NAME so two muscles on 6 sets do not swap places between two
    /// builds of the same week.
    nonisolated static func topMuscles(_ rows: [VolumeByMuscle]) -> [LandmarkMuscle] {
        rows
            .filter { $0.sets > 0 }
            .sorted { $0.sets != $1.sets ? $0.sets > $1.sets : $0.muscle < $1.muscle }
            .prefix(4)
            .compactMap { LandmarkMuscle(rawValue: $0.muscle) }
    }

    /// Four macros, each a daily MEAN against the mean of the targets in force.
    ///
    /// The mean is over the days that logged the macro, not over seven: a week
    /// with two untracked days divided by seven understates every row on the
    /// table, and the strip above it already says which days were untracked.
    /// Carbs and fat are nil for a profile that does not track them
    /// (`ExportDay.trackCarbs` / `trackFat`) — a target of zero is a claim.
    nonisolated static func macroTable(
        _ days: [ExportDay], targets: [String: AdherenceTargets]
    ) -> [MacroRow] {
        func mean(_ values: [Double?]) -> Double? {
            let present = values.compactMap { $0 }.filter { $0.isFinite }
            guard !present.isEmpty else { return nil }
            return jsRound(present.reduce(0, +) / Double(present.count))
        }
        let tracksCarbs = days.contains { $0.trackCarbs != false }
        let tracksFat = days.contains { $0.trackFat != false }
        let goals = days.compactMap { targets[$0.date] }
        return [
            MacroRow(
                label: "Calories", mean: mean(days.map(\.calories)),
                target: mean(goals.map(\.kcal)), unit: "kcal"
            ),
            MacroRow(
                label: "Protein", mean: mean(days.map(\.proteinG)),
                target: mean(goals.map(\.protein)), unit: "g"
            ),
            MacroRow(
                label: "Carbs", mean: tracksCarbs ? mean(days.map(\.carbsG)) : nil,
                target: tracksCarbs ? mean(goals.map(\.carbs)) : nil, unit: "g"
            ),
            MacroRow(
                label: "Fat", mean: tracksFat ? mean(days.map(\.fatG)) : nil,
                target: tracksFat ? mean(goals.map(\.fat)) : nil, unit: "g"
            ),
        ]
    }

    /// The micronutrients a reader has to act on, worst breach first.
    ///
    /// ── WHY NOT THE WHOLE TABLE ─────────────────────────────────────────────
    /// `WeeklyExport.weeklyNutrients` returns every nutrient with a reading —
    /// eighteen rows on a fully logged week — and eighteen rows of "Vitamin C
    /// 104 %" is the exported document's job. What belongs on a page is the
    /// exception: a floor the week missed, a ceiling it went past, and anything
    /// the document says not to believe. Everything else is the week working.
    nonisolated static func flaggedMicros(_ days: [ExportDay]) -> [MicroRow] {
        WeeklyExport.weeklyNutrients(days)
            .map {
                MicroRow(
                    label: $0.label, value: jsRound1($0.total), target: $0.target,
                    unit: $0.unit, kind: $0.kind, pct: $0.pct.map(jsRound),
                    doubted: $0.flagged
                )
            }
            .filter { $0.isBreach || $0.doubted }
            // Furthest from target first; a doubted row with no mean at all
            // (every day excluded) sorts last, where it reads as a footnote.
            .sorted { a, b in
                let da = a.pct.map { a.kind == .floor ? 100 - $0 : $0 - 100 } ?? -1
                let db = b.pct.map { b.kind == .floor ? 100 - $0 : $0 - 100 } ?? -1
                return da != db ? da > db : a.label < b.label
            }
    }

    /// The week's cardio as one row. Nil for a week with no bout, which draws
    /// no section — a "Cardio: 0" heading is a heading that makes the reader
    /// check a thing that did not happen.
    nonisolated static func cardio(_ bouts: [ExportCardio]) -> CardioTotals? {
        guard !bouts.isEmpty else { return nil }
        let minutes = bouts.compactMap(\.durationMin).reduce(0, +)
        let metres = bouts.compactMap(\.distanceM).reduce(0, +)
        // `totalKcal` is the bout's own figure where the import carried one and
        // `kcal` the active-only estimate behind it; the document prefers the
        // first and so does this.
        let kcal = bouts.compactMap { $0.totalKcal ?? $0.kcal }.reduce(0, +)
        var counts: [String: Int] = [:]
        for bout in bouts { counts[bout.kind, default: 0] += 1 }
        return CardioTotals(
            bouts: bouts.count,
            minutes: jsRound(minutes),
            km: metres > 0 ? jsRound1(metres / 1000) : nil,
            kcal: kcal > 0 ? jsRound(kcal) : nil,
            kinds: counts
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map(\.key)
        )
    }
}
