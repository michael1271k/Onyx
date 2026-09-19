import Foundation
import Observation
import GRDB
import OnyxCore
import OnyxData

/// Everything the Day screen reads and writes, for one selected date.
///
/// ── ONE MODEL, ELEVEN STREAMS, ONE DATE ─────────────────────────────────────
/// The web page mounted a hook per table, each with its own cache and its own
/// invalidation list, and the schedule lived in `localStorage` where React could
/// not see it change. Here the schedule is three streams like everything else,
/// and every tile derives from the same published rows — so a swap made on the
/// web redraws the fatigue slots here, because `isTraining` is a computed
/// property and not a value somebody remembered to refresh.
///
/// Per-user streams (goals, overrides, layout, the stack) are opened once. The
/// per-date streams are torn down and reopened when the date changes, and the
/// old day's rows are cleared in the same breath so nothing renders under the
/// new title that belongs to the previous one.
@MainActor
@Observable
final class DayModel {

    /// Internal rather than private: `DayScreen` loads the session mastheads
    /// (`SessionAnalysis.headers`) off THIS store, not off `AppEnvironment`'s.
    /// They are the same object in the tab, and are NOT in a preview or in a
    /// day History pushed — where reading the environment's store returned no
    /// sessions at all and every card drew its placeholder forever.
    let database: AppDatabase
    let userId: String

    /// The cascade, when the screen holding this model has an environment to
    /// run it on. See `setSleepOnsetTrouble`, the one writer that needs it.
    ///
    /// `weak` and `@ObservationIgnored`: this is a back-reference to the object
    /// that owns the store this model reads, not a piece of published state,
    /// and nothing redraws when it is set.
    @ObservationIgnored weak var environment: AppEnvironment?

    /// The selected logical day, ISO. Never later than today.
    private(set) var date: String
    private(set) var today: String = LogicalDay.today()

    // ── Per user ────────────────────────────────────────────────────────────
    private(set) var goals: UserGoalRow?
    private(set) var overrides: [String: String] = [:]
    private(set) var layout: DayLayout = [:]
    private(set) var customs: [CustomSupplementRow] = []
    /// The six squares in the reader's order (W9), off the same
    /// `dashboard_layouts` row the Today tab and the Train tab share.
    private(set) var pulseLayout: PulseLayout = .default
    /// Jiggle mode for the squares. Taps stop opening sheets; drags reorder.
    var editingSquares = false

    // ── Per date ────────────────────────────────────────────────────────────
    private(set) var log: DailyLogRow?
    private(set) var fatigueRows: [FatigueLogRow] = []
    private(set) var stressRows: [StressLogRow] = []
    /// Whether the date carries a session — the other half of the day's kind.
    /// See `isTraining`.
    private(set) var sessionLogged = false
    /// When the date's last session ended; nil while none has (W10).
    private(set) var sessionEndedAt: Date?
    private(set) var doms: [DomsLogRow] = []
    private(set) var supplementLog: [SupplementLogRow] = []
    private(set) var cardio: [CardioLogRow] = []
    private(set) var night: SleepSessionRow?
    private(set) var nights: [NightMinutes] = []
    private(set) var entries: [NutritionEntryRow] = []
    private(set) var dailyTarget: DailyTargetRow?

    /// The fortnight behind the selected date, folded once. Read rather than
    /// observed — see `loadWindow()`.
    private(set) var window = Window()

    /// The last write that failed, for the banner.
    private(set) var failure: String?
    /// What the last swap did, echoed back until the date changes.
    private(set) var swapNote: String?

    init(
        database: AppDatabase, userId: String, date: String = LogicalDay.today(),
        environment: AppEnvironment? = nil
    ) {
        self.database = database
        self.userId = userId
        self.date = min(date, LogicalDay.today())
        self.environment = environment
    }

    // MARK: - The squares' order (W9)

    /// `square` dropped onto `target`. Applied locally first so the grid moves
    /// under the finger, then written through the store, which carries every
    /// other key of the shared row through untouched.
    func moveSquare(_ square: PulseSquare, to target: PulseSquare) {
        let next = pulseLayout.moving(square, to: target)
        guard next != pulseLayout else { return }
        pulseLayout = next
        do {
            try database.savePulseLayout(userId: userId, next)
        } catch {
            report(error)
        }
    }

    // MARK: - Date

    func select(_ iso: String) {
        guard iso != date, iso <= today else { return }
        date = iso
        if isObserving { restartDateStreams() }
    }

    func step(_ days: Int) {
        if let next = ISODate.addDays(date, days) { select(next) }
    }

    var isToday: Bool { date == today }

    /// Re-read the logical day — an app left open across midnight otherwise
    /// keeps offering "next day" into the future.
    func refreshToday() { today = LogicalDay.today() }

    // MARK: - Reading

    private var isObserving = false
    private var userTasks: [Task<Void, Never>] = []
    private var dateTasks: [Task<Void, Never>] = []
    private var layoutTask: Task<Void, Never>?
    private var layoutKey = ""
    private var streamedDate = ""

    func observe() async {
        guard !isObserving else { return }
        isObserving = true
        defer {
            (userTasks + dateTasks).forEach { $0.cancel() }
            layoutTask?.cancel()
            userTasks = []
            dateTasks = []
            layoutKey = ""
            streamedDate = ""
            isObserving = false
        }
        today = LogicalDay.today()
        userTasks = [
            watch(database.scheduleOverridesStream(userId: userId), into: \.overrides),
            watch(database.customSupplementsStream(userId: userId), into: \.customs),
            // The row echoes a save back, so a drag on this device and a drag
            // on another land the same way — as a yield.
            Task { [weak self] in
                guard let self else { return }
                do {
                    for try await stored in database.dashboardLayoutStream(userId: userId) {
                        pulseLayout = stored?.pulse ?? .default
                    }
                } catch {
                    report(error)
                }
            },
        ]
        restartDateStreams()
        do {
            for try await row in database.userGoalsStream(userId: userId) {
                goals = row
                // The catalogue — decks, plans, phases — with the selection
                // this row names applied. Re-read on every goals tick, which
                // is every plan or phase change made anywhere.
                schedule = (try? database.scheduleContext(userId: userId)) ?? schedule
                // The layout row is keyed on the plan, which this row names.
                restartLayoutStream()
            }
        } catch {
            report(error)
        }
    }

    private func restartLayoutStream() {
        let plan = planId
        guard layoutKey != plan else { return }
        layoutKey = plan
        layoutTask?.cancel()
        layout = [:]
        layoutTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await row in database.programDayLayoutStream(userId: userId, programId: plan) {
                    let object = row.flatMap { try? JSONSerialization.jsonObject(with: Data($0.layout.raw.utf8)) }
                    layout = ScheduleLayout.parseLayout(object)
                }
            } catch {
                report(error)
            }
        }
    }

    private func restartDateStreams() {
        guard streamedDate != date else { return }
        streamedDate = date
        dateTasks.forEach { $0.cancel() }
        // Cleared, not left standing: these belong to the previous day until the
        // new streams' first yield, and a stale row under a new title is a lie.
        log = nil; fatigueRows = []; stressRows = []; doms = []; supplementLog = []; cardio = []; night = nil; nights = []
        sessionLogged = false; sessionEndedAt = nil
        swapNote = nil
        let d = date
        let from = ISODate.addDays(d, -(SleepDebt.windowDays - 1)) ?? d
        dateTasks = [
            // The day's own row is the one stream that also invalidates the
            // fortnight: a HealthKit sync writes today's HRV and steps, and the
            // baseline behind them moves with it.
            Task { [weak self] in
                guard let self else { return }
                do {
                    for try await row in database.dailyLogStream(userId: userId, date: d) {
                        log = row
                        loadWindow()
                    }
                } catch {
                    report(error)
                }
            },
            watch(database.fatigueStream(userId: userId, date: d), into: \.fatigueRows),
            watch(database.stressStream(userId: userId, date: d), into: \.stressRows),
            watch(database.sessionLoggedStream(userId: userId, date: d), into: \.sessionLogged),
            watch(database.sessionEndedStream(userId: userId, date: d), into: \.sessionEndedAt),
            watch(database.domsStream(userId: userId, date: d), into: \.doms),
            watch(database.supplementLogStream(userId: userId, date: d), into: \.supplementLog),
            watch(database.cardioStream(userId: userId, date: d), into: \.cardio),
            watch(database.sleepNightStream(userId: userId, date: d), into: \.night),
            watch(database.nightMinutesStream(userId: userId, from: from, to: d), into: \.nights),
            watch(database.nutritionEntriesStream(userId: userId, date: d), into: \.entries),
            watch(database.dailyTargetStream(userId: userId, date: d), into: \.dailyTarget),
        ]
        loadWindow()
    }

    // MARK: - The fortnight

    /// The 49 days behind each overnight reading, oldest → newest, ONE SLOT
    /// PER DATE — a day with no row is a nil in place, never a gap.
    ///
    /// ── WHY DENSE, AND WHY 49 ───────────────────────────────────────────────
    /// `Readiness.zSignal` splits its input at `count − 7`: the last seven
    /// entries are the rolling window and everything before them the baseline.
    /// A series built from the rows that HAPPEN to exist would slide that split
    /// by however many days the watch missed, so a fortnight off the wrist
    /// would quietly compare last week against the week before it. 49 is
    /// `Readiness.constants.historyDays` — the 7-day roll plus its 42-day
    /// baseline — and it is the ONLY thing this window reads over that range.
    /// Every delta on the screen is still the fortnight (`baselineDays`).
    struct VitalSeries: Sendable, Equatable {
        var hrv: [Double?] = []
        var restingBpm: [Double?] = []
        var wristTemp: [Double?] = []
        var bloodOxygen: [Double?] = []
        var respiratory: [Double?] = []
        /// `daily_logs.sleep_minutes`, not the `sleep_sessions` row: the night
        /// the hero cell DRAWS is the session, and the night it is RANKED by is
        /// the same series every other vital is ranked by.
        var sleepMinutes: [Double?] = []
    }

    /// Everything Pulse needs that is a WINDOW rather than a day: the vitals
    /// against their own fortnight baseline, the activity trends behind them,
    /// the series the hero rule ranks them by, and the day's stored score.
    struct Window: Sendable, Equatable {
        var vitals = OnyxSnapshot.Vitals()
        var steps: VitalBlock?
        var standHours: VitalBlock?
        var activeKcal: VitalBlock?
        /// What the hero rule reads. Folded in `VitalsGrid.hero(_:)`, which is
        /// where `VitalSpec` lives — the model does not import the design
        /// system, and the tie-break is that file's list order.
        var series = VitalSeries()
        /// What the scale said over the same 49 days, oldest first — the Scale
        /// square's trace (W3). One slot per date like every other series here,
        /// and SPARSE by nature: a weigh-in happens twice a week, so most slots
        /// are nil and the curve is the shape of the weigh-ins rather than of
        /// the calendar. It costs no query — the rows were already read for the
        /// vitals.
        var weight: [Double?] = []
        var score: DailyScoreRow?
        /// The day's FINISHED sessions, newest first. Here rather than on a
        /// stream of its own because it moves for exactly the same reasons the
        /// vitals do — the date changed, or the store did — and a tenth stream
        /// would be a tenth thing to keep in step with the other nine.
        var sessions: [WorkoutSummary] = []
        /// The stress index over the fortnight ending on the selected date,
        /// oldest first — the tile's sparkline and its headline reading, which
        /// is the LAST entry (§U5.3). Computed on read: v1 stores no column.
        var stress: [StressDay] = []
        /// The selected day's index term by term, for the breakdown sheet.
        var stressBreakdown: Stress.Breakdown?
        /// What the LEDGER implies every muscle is still carrying, 0…1
        /// (§W6). Sparse: a recovered muscle is absent, not zero.
        ///
        /// Distinct from `doms`, which is what the user reported, and drawn as
        /// the figure's FILL where the report is drawn as a ring over it. The
        /// two disagree constantly and both are right — see `MuscleRecovery`.
        var fatigue: [LandmarkMuscle: Double] = [:]
        /// False until the first read lands, so the rows can say "—" honestly
        /// rather than draw a zero they have not read yet.
        var loaded = false
    }

    /// One finished session, as the day page needs it.
    ///
    /// ── WHY THERE IS NO PR COUNT ────────────────────────────────────────────
    /// A PR is only knowable by replaying the WHOLE ledger in order — a record
    /// beaten last month still belongs to the session that set it, and
    /// `personal_records` is a current-best table that would say otherwise
    /// (`SessionAnalysis.summaries`). That walk costs the entire history and
    /// this card is a door: it names the session and hands the reader to
    /// `SessionDetailView`, which does the replay properly and is where the
    /// trophies are drawn. A count computed from one day's rows alone would be
    /// every set in the session, which is worse than no count at all.
    struct WorkoutSummary: Identifiable, Sendable, Hashable {
        let id: String
        let dayKey: String?
        /// "Legs & Core A", or nil for a session logged without a day key.
        let label: String?
        /// Working sets, a unilateral pair counted once.
        let sets: Int
        let tonnageKg: Double
        let durationMin: Double?
        /// The muscles the session was FOR, heaviest share first — at most the
        /// three the card's wash can distinguish.
        ///
        /// ── WHY THE CARD NEEDS THEM AND THE ROW DOES NOT ────────────────────
        /// This card is the door to the session, and it was washed in the
        /// SPLIT's colour: every Upper B is the same indigo whether it was a
        /// chest day or a back day, which is the one thing the reader standing
        /// on Pulse cannot already see from the label. The muscles are already
        /// being read — the rows this summary is built from are in memory for
        /// the set count and the tonnage — so this costs a fold, not a query.
        let muscles: [LandmarkMuscle]
    }

    /// The session's top muscles — the first three of the SAME order the
    /// masthead's capsules are in, so the door and the room agree about what
    /// the session was for.
    ///
    /// ── WHY IT IS `primaryLandmarks` AND NOT `weightedSets` (W5) ────────────
    /// It used to fold `MuscleCredit.weightedSets` itself. That is the
    /// distribution chart's accumulator and it answers a different question:
    /// it pays a SECONDARY mover half a set and it counts warm-ups, both of
    /// which are right for "where did this session land" and wrong for a flat
    /// capsule carrying no number. `SessionHeader.muscles` is
    /// `primaryLandmarks` — whole working sets per PRIMARY mover — so the two
    /// could disagree, and a muscle that is only ever an assistor could take a
    /// capsule here and then have no capsule at all once the header landed.
    ///
    /// That mattered the moment `SessionFallbackCard` started drawing them: a
    /// stand-in whose capsules DISAPPEAR on load is exactly what the card was
    /// rebuilt to stop. Same function, truncated — so this list is a prefix of
    /// the real one by construction, and the only thing a read can do is make
    /// it longer.
    ///
    /// Three at most. The wash behind the card is 64 pt tall and a gradient of
    /// four hues at 22 % is a smear; three is where the stops are still
    /// separable, and a leg day's fourth muscle is not what makes it a leg day.
    /// `nonisolated` because the summaries are folded on the detached read
    /// that builds the window, off the main actor — the same rule every other
    /// pure helper in this model follows.
    nonisolated static func focus(_ rows: [HistorySetRow]) -> [LandmarkMuscle] {
        Array(SessionAnalysis.primaryLandmarks(SessionAnalysis.grouped(rows)).prefix(3))
    }

    /// One detached read of `daily_logs` over the fortnight, plus the day's
    /// `daily_scores` row.
    ///
    /// ── WHY A READ AND NOT A NINTH STREAM ───────────────────────────────────
    /// Every vital on this screen is a reading against ITS OWN fortnight
    /// baseline, which is a window query — and `OnyxData` (Track E, plan §10)
    /// exposes streams per DATE, not per range. Rather than reach across the
    /// track boundary for a `dailyLogsStream(from:to:)`, this goes through the
    /// public `read` door on the same schedule the streams fire on: once per
    /// date change, and again whenever the day's own row yields, which is what
    /// a HealthKit sync or a manual edit produces. Forty-nine indexed rows.
    ///
    /// ── WHY IT READS 49 DAYS AND STILL SHOWS A FORTNIGHT (W2) ───────────────
    /// The hero rule needs `Readiness.zSignal`, which is a 7-day roll against
    /// the 42 days before it. The DELTAS are unchanged: `block(_:)` is handed
    /// the last fourteen rows and nothing else, because Apple's own baseline is
    /// a fortnight and the chip here and the chip on the Home Screen have to be
    /// the same number or one of them is lying.
    // ponytail: a `ValueObservation` over the range would repaint without the
    // nudge below; it belongs in OnyxData, which this wave may not edit.
    func loadWindow() {
        let to = date
        let from = ISODate.addDays(to, -(Readiness.constants.historyDays - 1)) ?? to
        let database = database
        let userId = userId
        Task { [weak self] in
            let window = await Task.detached(priority: .userInitiated) {
                Self.readWindow(database: database, userId: userId, from: from, to: to)
            }.value
            guard let self, self.date == to else { return }
            self.window = window
        }
    }

    /// Apple's own baseline window, and the one `WidgetSnapshotBuilder` uses —
    /// the delta chips on this screen and on the Home Screen have to be the
    /// same number or one of them is lying.
    private nonisolated static let baselineDays = 14
    private nonisolated static let trendDays = 7

    /// Every finished session inside the recovery horizon, reduced to a bout.
    ///
    /// ── WHY IT IS ANCHORED ON THE SELECTED DATE AND NOT ON `now` ────────────
    /// This screen is a day page and History pushes it for past dates. A
    /// recovery map computed against the wall clock would draw last March's
    /// page as fully recovered, which is true today and was not true then —
    /// and a figure that answers a different question depending on which door
    /// you came through is a figure nobody can read.
    ///
    /// The anchor is the END of the selected day, so a session logged that
    /// morning reads as hours old rather than as a day old.
    private nonisolated static func recoveryBouts(
        database: AppDatabase, userId: String, on dateISO: String
    ) -> [MuscleRecovery.Bout] {
        guard let day = LogicalDay.date(fromISO: dateISO) else { return [] }
        // `byAdding: .day`, not +86,400 seconds: on the two days a year the
        // clocks move, a day is 23 or 25 hours and the arithmetic version puts
        // the anchor an hour inside or outside the day it is meant to bound.
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: day)
        let anchor = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight.addingTimeInterval(86_400)
        let from = ISODate.addDays(dateISO, -Int(MuscleRecovery.horizonHours / 24)) ?? dateISO
        return ((try? database.sessionHistory(userId: userId)) ?? [])
            .filter { $0.date >= from && $0.date <= dateISO && $0.endedAt != nil }
            .compactMap { session -> MuscleRecovery.Bout? in
                guard let ended = session.endedAt else { return nil }
                let rows = ((try? database.historySets(sessionId: session.id, userId: userId)) ?? [])
                    // Working sets only. A warm-up is real weight and counts
                    // for tonnage, and it is not what leaves a muscle sore
                    // three days later.
                    .filter { SetTags.isWorkingSet($0.setType) }
                guard !rows.isEmpty else { return nil }
                let names = rows.map { SessionAnalysis.displayName(id: $0.exerciseId, stored: $0.exerciseName) }
                let worked = MuscleCredit.worked(from: MuscleCredit.weightedSets(exerciseNames: names))
                guard !worked.isEmpty else { return nil }
                return MuscleRecovery.Bout(
                    hoursAgo: anchor.timeIntervalSince(ended) / 3600, worked: worked
                )
            }
    }

    private nonisolated static func readWindow(database: AppDatabase, userId: String, from: String, to: String) -> Window {
        // The deck that names a session's day key — the active plan's rows.
        let program = (try? database.scheduleContext(userId: userId))?.activeProgram
        // Unfiltered on `user_id`, like every other read in the app: the local
        // store is one user's mirror and the id is `""` until auth resolves.
        // See the long note in `WorkoutWeek.build`.
        let logs: [DailyLogRow] = (try? database.read { db in
            try DailyLogRow
                .filter(Column("date") >= from && Column("date") <= to)
                .order(Column("date"))
                .fetchAll(db)
        }) ?? []
        let score: DailyScoreRow? = (try? database.read { db in
            try DailyScoreRow.filter(Column("date") == to).fetchOne(db)
        }) ?? nil

        // `sessionHistory()` is one query over a few hundred rows and is what
        // every other history read in the app already uses; a per-date query
        // would be a second spelling of "which sessions are on this day" to
        // keep in step with `HistoryWeeks`. Unfinished sessions are excluded:
        // an abandoned draft has no summary worth a card, and its ledger row
        // is the logger's business.
        let sessions = ((try? database.sessionHistory(userId: userId)) ?? [])
            .filter { $0.date == to && $0.endedAt != nil }
            .map { session -> WorkoutSummary in
                let rows = (try? database.historySets(sessionId: session.id, userId: userId)) ?? []
                // WORKING sets for the COUNT, every non-ghost row for the
                // TONNAGE — `SessionTonnage.kg` states why, and it is the same
                // split `SessionAnalysis.summaries` and `closeSession` make.
                let working = rows.filter { SetTags.isWorkingSet($0.setType) }
                return WorkoutSummary(
                    id: session.id,
                    dayKey: session.dayKey,
                    label: SessionAnalysis.dayLabel(session.dayKey, in: program),
                    sets: SessionDetail.toRows(working.map(SessionAnalysis.detailSet)).filter { $0.num != nil }.count,
                    tonnageKg: SessionVolume.sessionVolumeKg(rows.map(SessionAnalysis.volumeSet)),
                    durationMin: session.durationMin,
                    muscles: Self.focus(rows)
                )
            }

        // The fortnight, out of the 49 days the hero rule needs. `>=` on ISO
        // strings is the same comparison the query made.
        let baselineFrom = ISODate.addDays(to, -(baselineDays - 1)) ?? to
        let fortnight = logs.filter { $0.date >= baselineFrom }

        func block(_ pick: (DailyLogRow) -> Double?) -> VitalBlock {
            WidgetDerive.vitalBlock(
                fortnight.map { DatedValue(date: $0.date, value: pick($0)) },
                todayISO: to, trendLimit: trendDays
            )
        }

        // One slot per date, oldest → newest. `uniquingKeysWith` cannot fire —
        // `daily_logs` is unique on (user, date) — and stating an answer is
        // cheaper than a crash if that ever stops being true.
        let byDate = Dictionary(logs.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let dates = (0..<Readiness.constants.historyDays)
            .reversed()
            .map { ISODate.addDays(to, -$0) ?? to }
        func series(_ pick: @escaping (DailyLogRow) -> Double?) -> [Double?] {
            dates.map { byDate[$0].flatMap(pick) }
        }
        func vital(_ pick: (DailyLogRow) -> Double?) -> OnyxSnapshot.Vital {
            let b = block(pick)
            return OnyxSnapshot.Vital(
                value: b.value, baseline: b.baseline,
                trend: b.trend.map { OnyxSnapshot.Point(d: $0.d, v: $0.v) }
            )
        }

        // ── THE STRESS INDEX IS COMPUTED, NOT STORED (§U5.3) ────────────────
        // `stressSeries` builds fourteen days of `StressInputs` from the local
        // store and `stressBreakdown` builds the fifteenth — the selected day
        // again, kept because the SERIES only carries each term's z rounded to
        // one decimal, and the breakdown sheet names the weights, the pieces
        // and how many inputs answered. Fifteen `readinessHistory` reads on a
        // local SQLite file, off the main actor, on the same schedule the rest
        // of this window read runs on.
        // ponytail: the documented upgrade is `daily_scores.stress_index` +
        // `stress_breakdown`, written by the scorer — see `STRESS_MODEL.md` §6.
        let stress = (try? database.stressSeries(userId: userId, endingOn: to, limit: 14)) ?? []
        let stressBreakdown = try? database.stressBreakdown(userId: userId, date: to)

        return Window(
            vitals: OnyxSnapshot.Vitals(
                hrvMs: vital { $0.hrvMs },
                restingBpm: vital { $0.avgRestHeartRate.map(Double.init) },
                wristTempDeltaC: vital { $0.wristTempDelta },
                bloodOxygenPct: vital { $0.bloodOxygen },
                respiratoryRate: vital { $0.respiratoryRate }
            ),
            steps: block { $0.steps.map(Double.init) },
            standHours: block { $0.standHours.map(Double.init) },
            activeKcal: block { $0.activeEnergy },
            series: VitalSeries(
                hrv: series { $0.hrvMs },
                restingBpm: series { $0.avgRestHeartRate.map(Double.init) },
                wristTemp: series { $0.wristTempDelta },
                bloodOxygen: series { $0.bloodOxygen },
                respiratory: series { $0.respiratoryRate },
                sleepMinutes: series { $0.sleepMinutes.map(Double.init) }
            ),
            weight: series { $0.weightKg },
            score: score,
            sessions: sessions,
            stress: stress,
            stressBreakdown: stressBreakdown,
            fatigue: MuscleRecovery.fatigue(recoveryBouts(database: database, userId: userId, on: to)),
            loaded: true
        )
    }

    private func watch<T: Sendable>(
        _ stream: AsyncThrowingStream<T, any Error>,
        into keyPath: ReferenceWritableKeyPath<DayModel, T>
    ) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                for try await value in stream { self?[keyPath: keyPath] = value }
            } catch {
                self?.report(error)
            }
        }
    }

    /// Cancellation is not a failure — every date change cancels seven streams.
    ///
    /// ── AN ERROR THAT KNOWS WHY SAYS SO (W1 LEFT THIS) ──────────────────────
    /// `saveBodyMetrics` refuses a reading a body cannot report and throws a
    /// `BodyMetricError` that names the field, the value and what is wrong with
    /// it. Every one of those arrived here and came back out as "That change
    /// could not be saved on this device" — which is not only useless, it is
    /// false: the device is fine and the number is not. A typo of 855 in the
    /// body-fat field read as a broken phone.
    private func report(_ error: any Error) {
        if error is CancellationError { return }
        if let refused = error as? BodyMetricError {
            failure = refused.description
            return
        }
        failure = "That change could not be saved on this device."
    }

    // MARK: - Schedule

    /// The catalogue with the selection applied (`AppDatabase.scheduleContext`);
    /// the overrides and layout are streamed live and laid over it below.
    private(set) var schedule = ScheduleContext(programId: "", phase: .cut)

    var planId: String { schedule.programId }

    var phase: ProgramPhase { ProgramPhase.stored(goals?.activePhase ?? goals?.goalPreset) }

    var context: ScheduleContext {
        var ctx = schedule
        ctx.phase = phase
        ctx.overrides = overrides
        ctx.layout = layout
        return ctx
    }

    /// The plan that owns the selected date (era-aware), and its layout.
    var program: Program { Schedule.programForContext(context, date).program }

    var scheduled: ScheduleDay? { Schedule.scheduleDayIn(context, date) }
    /// Training day — as PLANNED or as LOGGED.
    ///
    /// ── W1 LEFT THIS READING THE PLAN ALONE ─────────────────────────────────
    /// The scorer settled on one rule (`AppDatabase.isTrainingDay`: a session
    /// exists, or the calendar says so) and this screen kept the plan-only
    /// half. So a session trained on a scheduled rest day offered Waking ·
    /// Midday · Night while the fold behind the score used Waking · Before ·
    /// After — a day where the slot you were asked for did not exist in the
    /// arithmetic that read your answer, and the stack dropped its
    /// training-only items under a session in progress.
    ///
    /// `sessionLogged` counts sessions exactly as `ScheduleResolution` counts
    /// them, unfinished ones included: the slot being asked for is "Before
    /// training", and it is asked for mid-session.
    var isTraining: Bool { Schedule.isTrainingDayIn(context, date) || sessionLogged }
    var isOverridden: Bool { overrides[date] != nil }

    /// What is on any date, overrides included — the closure `Swap` plans over.
    func resolver() -> ResolveDay {
        let ctx = context
        return { Schedule.scheduleDayIn(ctx, $0) }
    }

    /// The date a program day would fall on this week, layout applied.
    func naturalDate(of day: ProgramDay) -> String {
        Swap.dateForWeekday(date, ScheduleLayout.effectiveWeekday(day, Schedule.programForContext(context, date).layout))
    }

    func loggedDays(_ dates: [String]) -> [LoggedDay] {
        ((try? database.loggedDays(userId: userId, dates: dates)) ?? []).map { LoggedDay(date: $0.date, dayKey: $0.dayKey) }
    }

    // MARK: - Recovery

    var fatigueSlots: [FatigueSlot] { Fatigue.slotsForDay(isTraining: isTraining) }

    var fatigue: FatigueDay {
        Fatigue.foldRows(fatigueRows.map { FatigueRow(slot: $0.slot, level: $0.level) }, isTraining: isTraining)
    }

    /// The slot the card is asking for NOW — and the one the sheet opens on,
    /// so the question on the card and the segment under the words agree.
    /// The clock is `clock` (pinned in the shot loop) and the session's end
    /// is the stored row's, read as minutes of the day; `Date()` is not read.
    var fatigueAsk: FatigueSlot {
        Fatigue.askingSlot(
            isTraining: isTraining, clock: clock,
            sessionEndedMinutes: sessionEndedAt.map { PsychStress.minuteOfDay($0) }
        )
    }

    /// The STORED keys this slot stands in for, the modern key excluded — the
    /// writer already owns the row spelled the modern way, and listing it here
    /// would delete the row it had just saved.
    private func legacyKeys(for slot: FatigueSlot) -> [String] {
        let training = isTraining
        return Array(Set(fatigueRows.map(\.slot).filter {
            $0 != slot.rawValue && FatigueSlot(rawValue: $0) == nil && Fatigue.normalizeSlot($0, isTraining: training) == slot
        }))
    }

    /// Muscle group → severity, as rated today: the MAX across sides.
    ///
    /// Max, not last-wins, and that is a W9 change with a reason. A day can now
    /// hold a left row and a right row for one muscle, and "left quad severe,
    /// right quad fine" is a severe quad — averaging it, or taking whichever
    /// row the fetch returned last, reports a day nobody had. It is the same
    /// fold `ScoringInputsBuilder.foldDomsSeverity` and `Derived` apply, so the
    /// summary line, the battery and the export cannot disagree about how sore
    /// a muscle was.
    var domsSeverity: [String: Int] {
        doms.reduce(into: [:]) { out, row in
            out[row.muscleGroup] = max(out[row.muscleGroup] ?? 0, row.severity)
        }
    }

    /// One rating exactly as stored — this group, this side, the whole muscle.
    ///
    /// Nil is "never rated", which is NOT "None": the popover shows a tick
    /// beside the level the athlete chose, and defaulting an unrated side to 0
    /// would tick "None" on a muscle nobody has answered for.
    func domsSeverity(_ group: String, side: BodySide) -> Int? {
        doms.first { $0.muscleGroup == group && $0.matches(side: side, subRegion: nil) }?.severity
    }

    /// The weigh-ins in the window, oldest first, with the days between them
    /// dropped: `Sparkline` is a curve with no notion of a hole, and plotting a
    /// nil as zero would draw a cliff to the floor on every rest day.
    var weightTrace: [Double] { window.weight.compactMap { $0 } }

    /// The bank, or nil when fewer than three nights have data — too little
    /// history to be honest about debt. The window ENDS on the selected date.
    /// ── NO GOAL, NO DEBT (W7) ───────────────────────────────────────────
    /// `sleepGoalHours` below falls back to eight so the gauge and the edit
    /// sheet have a target to draw against, which is right for a DISPLAY. It
    /// is wrong for a bank: debt is a shortfall, and a shortfall against a goal
    /// the athlete never set is a number nobody asked for. The Mega tile's
    /// sentence applies the same rule, so the two surfaces cannot report a debt
    /// and no debt for the same unset goal.
    var sleepDebt: SleepDebt? {
        guard let goalHours = goals?.sleepGoalHours else { return nil }
        let debt = SleepDebt.compute(
            nights: nights.map { SleepDebtNight(date: $0.date, sleepMinutes: $0.sleepMinutes.map(Double.init)) },
            goalHours: goalHours,
            weekAgo: ISODate.addDays(date, -7) ?? date
        )
        return debt.nights >= SleepDebt.minimumNights ? debt : nil
    }

    var sleepGoalHours: Double { goals?.sleepGoalHours ?? 8 }

    // MARK: - Stress (§U5.3)

    /// The fortnight, oldest first. Empty while the window read is in flight.
    var stressSeries: [StressDay] { window.stress }

    /// The selected day's reading — the LAST entry in the series, by
    /// construction (`StressSeries.build` ends on the date it was asked for).
    /// Nil on a day where nothing answered, which the tile draws as a gap.
    var stress: StressDay? {
        guard let last = window.stress.last, !last.empty else { return nil }
        return last
    }

    /// Term by term, for the breakdown sheet.
    var stressBreakdown: Stress.Breakdown? { window.stressBreakdown }

    // MARK: - The stress log — the typed reading (decision 1)

    /// The day's own events in the order the day happened
    /// (`PsychStress.sorted`: a timed event by its time, a legacy row at its
    /// slot's start). A row whose slot this build does not know is dropped
    /// rather than drawn under a blank heading.
    var stressReadings: [StressReading] {
        PsychStress.sorted(stressRows.compactMap(AppDatabase.reading))
    }

    // ── NO `stressSlot` HERE ANY MORE ──────────────────────────────────────
    // The legacy sheet asked the MODEL what bucket it was, because the reading
    // it wrote had no timestamp of its own. `StressLogSheet` derives the slot
    // from the time the reader actually picked (`StressSlot.forMinutes` over
    // `loggedAt`), and a second "what slot is it now" accessor on the model is
    // how the clock-vs-timestamp split this wave removed would come back.

    /// What the row states: the LATEST answer, not the day's mean. The mean is
    /// the index's business (`StressInputsBuilder`).
    var stressLatest: StressReading? { PsychStress.latest(stressReadings) }

    // MARK: - The now strip

    /// The day's stored composite, or nil while the read is in flight or the
    /// day has not been scored. Never a zero — 0 is a real score.
    var score: Int? { window.score?.score }
    var battery: Int? { window.score?.batteryPct }

    /// `1,420 / 1,955 kcal · P 128 · water 2.1 L` — the whole of nutrition on
    /// this screen, because the gauges live in the Nutrition tab (§5.7).
    ///
    /// The kcal figure is what was RECORDED, never the Atwater sum of the
    /// macros beside it: Apple Health owns the day's energy (memory
    /// `no-tape-measurements`' sibling rule, and `MacroEditSheet`'s long note).
    var fuelLine: String? {
        guard !entries.isEmpty || log?.waterMl != nil else { return nil }
        let target = Targets.resolve(
            TargetSources(goals: goals, dayTarget: dailyTarget.map(DailyTarget.init), profiles: []), date: date, today: today
        ).goals
        var parts: [String] = []
        if !entries.isEmpty {
            let kcal = entries.reduce(0) { $0 + $1.calories }
            parts.append(target.calorie > 0
                ? "\(NutritionFormat.whole(kcal)) / \(NutritionFormat.whole(target.calorie)) kcal"
                : "\(NutritionFormat.whole(kcal)) kcal")
            let protein = entries.reduce(0) { $0 + $1.proteinG }
            parts.append("P \(NutritionFormat.whole(protein))")
        }
        if let ml = log?.waterMl, ml > 0 {
            parts.append("water \(DayFormat.number(ml / 1000)) L")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - The stack

    /// The stack rows as the core reads them — micros and `archived_at`
    /// included. Wave 2 decoded only the schedule, which is why the phone
    /// credited zero micronutrients from a stack it drew perfectly.
    private var decodedCustoms: [CustomSupplement] { customs.map(AppDatabase.custom) }

    /// The rows still in the protocol on the selected day.
    private var activeCustoms: [CustomSupplement] { Supplements.active(decodedCustoms, on: date) }

    /// The rows that had left it — the Stack screen's last section.
    var archivedCustoms: [CustomSupplement] { Supplements.archived(decodedCustoms, on: date) }

    private func stack(isTraining training: Bool) -> [SupplementSlot] {
        let weekday = ISODate.weekday(date) ?? 0
        return Supplements.stackForDate(
            Supplements.customSlotsForDate(activeCustoms, weekday: weekday, isTraining: training),
            isTraining: training, weekday: weekday
        )
    }

    /// The day's slots, in time order.
    var stack: [SupplementSlot] { stack(isTraining: isTraining) }

    #if DEBUG
    /// The shot loop pins the clock: without it Due and Later swap contents at
    /// 22:00 and the committed PNG churns by the hour.
    var previewNowMinutes: Int?
    #endif

    /// Where the selected day sits against the clock. A past day has had every
    /// slot; a future one cannot be selected at all (`date` never runs ahead).
    var clock: DayClock {
        #if DEBUG
        if let previewNowMinutes { return .today(minutes: previewNowMinutes) }
        #endif
        return isToday ? .today(minutes: DayFormat.nowMinutes) : .past
    }

    /// Every scheduled dose of the day, with where it stands.
    var doses: [SupplementDose] {
        Supplements.doses(slots: stack, log: logEntries, clock: clock)
    }

    /// What the day's micronutrients owe the stack.
    var stackNutrients: [String: Double] {
        SupplementNutrients.credit(doses.filter(\.credited), payloads: SupplementNutrients.payloads(activeCustoms))
    }

    private var logEntries: [DoseLogEntry] {
        supplementLog.map { DoseLogEntry(itemKey: $0.itemKey, taken: $0.taken) }
    }

    /// Keys of the items skipped today. Absence means the protocol.
    var skippedKeys: Set<String> { Set(supplementLog.filter { !$0.taken }.map(\.itemKey)) }

    /// The `custom_supplements` row behind a dose, when there is one — a seeded
    /// protocol item has none, and cannot be edited or archived.
    func custom(for dose: SupplementDose) -> CustomSupplement? {
        guard let id = dose.customId else { return nil }
        return decodedCustoms.first { $0.id == id }
    }

    /// The keys a rest day drops — read off the TRAINING stack, because on a
    /// rest day they are already gone from the day's own.
    var trainingOnlyKeys: [String] {
        stack(isTraining: true).flatMap(\.items).filter { $0.trainingOnly == true }.map(\.key)
    }

    // MARK: - Writing

    /// One failure path for every write. Returns whether it landed, for the
    /// sheets that close on success.
    @discardableResult
    private func write(_ body: () throws -> Void) -> Bool {
        do {
            try body()
            failure = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    func setFatigue(_ slot: FatigueSlot, level: Int?) {
        let superseded = legacyKeys(for: slot)
        // Optimistic: the chips read the fold, and a tap that shows a hop late
        // reads as a tap that missed.
        fatigueRows.removeAll { $0.slot == slot.rawValue || superseded.contains($0.slot) }
        if let level {
            fatigueRows.append(FatigueLogRow(id: "local", userId: userId, date: date, slot: slot.rawValue, level: level))
        }
        write { [database, userId, date] in
            try database.setFatigue(userId: userId, date: date, slot: slot.rawValue, level: level, superseding: superseded)
        }
    }

    /// Log one stress event at `loggedAt` on the model's day. Returns whether
    /// it landed, so the sheet closes on success and keeps the typing on
    /// failure.
    ///
    /// The write is synchronous, so the echo is the stored row itself rather
    /// than an optimistic stand-in: it is appended under its real id the
    /// moment the write returns, and the stream replaces it in place.
    @discardableResult
    func logStress(at loggedAt: Date, level: Int, tags: [StressTag] = [], note: String? = nil) -> Bool {
        var id: String?
        let landed = write { [database, userId, date] in
            id = try database.logStress(userId: userId, date: date, loggedAt: loggedAt, level: level, tags: tags, note: note)
        }
        if let id {
            let trimmed = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            stressRows.append(StressLogRow(
                id: id, userId: userId, date: date,
                slot: StressSlot.forMinutes(PsychStress.minuteOfDay(loggedAt)).rawValue, level: level,
                tags: JSONText(raw: "[" + StressTag.sorted(tags).map { "\"\($0.rawValue)\"" }.joined(separator: ",") + "]"),
                note: trimmed.isEmpty ? nil : trimmed,
                createdAt: Date(), updatedAt: Date(), loggedAt: loggedAt
            ))
        }
        // The index is a read over the day's rows, so a new reading only shows
        // up on the tile and in the breakdown once the window is rebuilt.
        if landed { loadWindow() }
        return landed
    }

    /// Remove one stress event. Optimistic like the other writers here.
    @discardableResult
    func deleteStress(id: String) -> Bool {
        stressRows.removeAll { $0.id == id }
        let landed = write { [database, userId] in
            try database.deleteStress(userId: userId, id: id)
        }
        if landed { loadWindow() }
        return landed
    }

    /// Attribution (`source`) is left nil: the session that caused the soreness
    /// is a 72-hour lookup over `workout_sessions` the web runs per muscle, and
    /// nothing on this screen reads it back yet.
    /// `side` defaults to `.both`, which stores NULL — the pre-W9 meaning, and
    /// what every rating written before the body had two sides already says.
    /// The optimistic row is keyed on the side too, so rating a left glute does
    /// not silently overwrite the right one under the thumb.
    func setDoms(_ muscle: String, severity: Int, side: BodySide = .both) {
        let stored = side.stored  // always the word: the column is NOT NULL
        // Spelling-tolerant, like the store's own lookup: a row the web era
        // wrote as `('both','')` is the row this re-rates (`DomsRow.swift`).
        if let i = doms.firstIndex(where: {
            $0.muscleGroup == muscle && $0.matches(side: side, subRegion: nil)
        }) {
            doms[i].severity = severity
        } else {
            // The id carries the side: two optimistic rows both called "local"
            // are two rows the next reload cannot tell apart.
            doms.append(DomsLogRow(
                id: "local-\(muscle)-\(stored)", userId: userId, date: date,
                muscleGroup: muscle, severity: severity, side: stored, subRegion: ""
            ))
        }
        write { [database, userId, date] in
            try database.setDoms(userId: userId, date: date, muscleGroup: muscle, severity: severity, side: side)
        }
    }

    /// Mark one dose taken, skipped, or back to the protocol.
    ///
    /// Optimistic, like every other writer here: the row moves section under
    /// the thumb and the store write follows.
    func mark(_ dose: SupplementDose, as mark: AppDatabase.SupplementMark) {
        supplementLog.removeAll { $0.itemKey == dose.key }
        if mark != .cleared {
            supplementLog.append(SupplementLogRow(
                userId: userId, date: date, itemKey: dose.key, taken: mark == .taken, updatedAt: Date()
            ))
        }
        let due = Self.localInstant(date, hhmm: dose.slotTime)
        write { [database, userId, date] in
            try database.markSupplement(userId: userId, date: date, itemKey: dose.key, mark: mark, dueAt: due)
        }
    }

    /// Skip the SAME dose tomorrow — "freeze for a day". Tomorrow's row is
    /// written now; nothing about today moves.
    @discardableResult
    func freezeTomorrow(_ dose: SupplementDose) -> Bool {
        guard let tomorrow = ISODate.addDays(date, 1) else { return false }
        let due = Self.localInstant(tomorrow, hhmm: dose.slotTime)
        return write { [database, userId] in
            try database.markSupplement(userId: userId, date: tomorrow, itemKey: dose.key, mark: .skipped, dueAt: due)
        }
    }

    /// Take an item out of the protocol, or put it back. Seeded items have no
    /// row of their own and cannot be archived — the caller checks first.
    func setArchived(_ custom: CustomSupplement, archived: Bool) {
        write { [database, userId] in
            try database.setCustomSupplementArchived(id: custom.id, userId: userId, archived: archived)
        }
    }

    /// Remove a row outright — for something added by mistake. Everything else
    /// archives, so the log keys it wrote keep resolving.
    func delete(_ custom: CustomSupplement) {
        write { [database, userId] in
            try database.deleteCustomSupplement(id: custom.id, userId: userId)
        }
    }

    /// Add a supplement to the stack.
    @discardableResult
    func addSupplement(
        name: String, dose: String, doseAmount: Double? = nil, doseUnit: String? = nil,
        time: String?, days: [Int],
        color: String?, form: String?, notes: String?, trainingOnly: Bool
    ) -> Bool {
        let schedule = CustomSchedule(
            days: days.isEmpty ? nil : days,
            slot: nil,
            notes: (notes ?? "").isEmpty ? nil : notes,
            trainingOnly: trainingOnly ? true : nil
        )
        return write { [database, userId] in
            try database.addCustomSupplement(
                userId: userId, name: name, dose: dose,
                color: color, form: (form ?? "").isEmpty ? nil : form,
                time: (time ?? "").isEmpty ? nil : time,
                schedule: schedule,
                doseAmount: doseAmount, doseUnit: doseUnit
            )
        }
    }

    /// Edit everything the form owns.
    ///
    /// ── WHY THIS IS NOT AN `editCustomSupplement` BLOCK ─────────────────────
    /// The schedule is a jsonb carrying five facts the form has no field for,
    /// one of which (`key`) is the join to every log row the item ever wrote.
    /// `AppDatabase.updateCustomSupplement` merges rather than replaces, and
    /// keeping that in one place is what stops the next caller from building a
    /// fresh `CustomSchedule` and quietly orphaning a year of history.
    @discardableResult
    func editSupplement(
        _ custom: CustomSupplement,
        name: String, dose: String, doseAmount: Double?, doseUnit: String?,
        form: String?, time: String?, days: [Int], trainingOnly: Bool
    ) -> Bool {
        write { [database, userId] in
            try database.updateCustomSupplement(
                id: custom.id, userId: userId,
                name: name, dose: dose, doseAmount: doseAmount, doseUnit: doseUnit,
                form: form, time: time, days: days, trainingOnly: trainingOnly
            )
        }
    }

    // MARK: - Quick Log

    /// The day's water, in litres, or nil when nothing has been recorded.
    var waterMl: Double? { log?.waterMl }

    /// One glass.
    ///
    /// ── A TAP ADDS; ONLY THE NUTRITION SHEET REPLACES ───────────────────────
    /// `addWaterGlass` appends a row to the ledger and the HealthKit ingest
    /// adds the glasses to what Apple reports. `setWaterOverride` — the other
    /// door — writes a manual sentinel that makes every later sync decline the
    /// date's water without saying so. A one-tap control must never be the
    /// second kind (`NutritionModel.addWater` carries the same note, and the
    /// same scar).
    ///
    /// ── AND THE LOCAL IS LOAD-BEARING ───────────────────────────────────────
    /// This read `log?.waterMl = (log?.waterMl ?? 0) + ml` and was the same
    /// crash as `NutritionModel.addWater`, verbatim: `log` is a stored property
    /// of an `@Observable` class, so `a?.b = rhs` opens an exclusive `_modify`
    /// on it before evaluating the right-hand side — it must, because the
    /// assignment has to short-circuit when the optional is nil — and the
    /// right-hand side then reads the same property. Swift's dynamic
    /// exclusivity checking traps: "Fatal access conflict detected", on the
    /// first tap of any day that already has a `daily_logs` row. Reading into a
    /// local closes the access before the write opens one.
    @discardableResult
    func addWaterGlass(_ ml: Double = 250) -> Bool {
        let total = (log?.waterMl ?? 0) + ml
        log?.waterMl = total
        return write { [database, userId, date] in
            try database.addWaterGlass(userId: userId, date: date, ml: ml)
        }
    }

    /// Whatever you wanted to say about the day — `daily_logs.journal_md`.
    ///
    /// The column has existed and been mirrored since the beginning and nothing
    /// has ever written it. Nothing reads it either: it is a note to yourself,
    /// it scores nothing, and it is deliberately not an input to anything.
    var note: String { log?.journalMd ?? "" }

    @discardableResult
    func setNote(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored: String? = trimmed.isEmpty ? nil : trimmed
        log?.journalMd = stored
        return write { [database, userId, date] in
            // Named in `clearing:` so a note the user emptied reaches the
            // server as a null rather than being omitted from the merge — the
            // same rule `setSleepInaccurate` and `setWeighInSkipReason` follow.
            try database.editDailyLog(userId: userId, date: date, clearing: stored == nil ? ["journal_md"] : []) {
                $0.journalMd = stored
            }
        }
    }

    /// "I could not get to sleep."
    ///
    /// ── AND IT MOVES NUMBERS, SO IT HAS TO CASCADE ──────────────────────────
    /// Unlike its neighbour `setSleepInaccurate`, this flag is a SCORING INPUT:
    /// `Stress.breakdown` reads it (`StressInputs.sleepOnsetTrouble`) and so
    /// does `Battery.wellnessDrain` (`ScoringInputs.sleepOnsetTrouble`). It
    /// wrote the row and stopped there, so the stored `daily_scores` for the
    /// night went on describing the un-flagged version of it — and every day
    /// inside the readiness window after it, because a battery is a walk over
    /// the window and not a reading of one date.
    ///
    /// The commit is the request — see `RescoreDoor`. A write that fails to
    /// land is a commit that never happens, so nothing is asked for it.
    func setSleepOnsetTrouble(_ on: Bool) {
        log?.sleepOnsetTrouble = on
        // The commit is the request (W2): `editDailyLog` writes `daily_logs`
        // and the rescore door reports the date.
        _ = write { [database, userId, date] in
            try database.editDailyLog(userId: userId, date: date) { $0.sleepOnsetTrouble = on }
        }
    }

    /// "The watch got this night wrong."
    ///
    /// Written as `true` or as nil, never as `false`: nil is what keeps the
    /// column out of the push body until Postgres has it (see `DailyLogRow`),
    /// and every reader treats the two the same — the night was not disputed.
    /// It moves NO score. Correcting a measurement by self-report is how a log
    /// becomes a wish; this marks the reading and leaves it standing.
    func setSleepInaccurate(_ on: Bool) {
        log?.sleepInaccurate = on ? true : nil
        write { [database, userId, date] in
            try database.editDailyLog(userId: userId, date: date, clearing: on ? [] : ["sleep_inaccurate"]) {
                $0.sleepInaccurate = on ? true : nil
            }
        }
    }

    /// `nil` is "As Planned" and is STORED as nil — the default is resolved on
    /// read, never written, so it can change wording without rewriting history.
    func setWeighInSkipReason(_ reason: String?) {
        let stored = WeighIn.isDefaultSkipReason(reason) ? nil : reason
        log?.weighinSkipReason = stored
        write { [database, userId, date] in
            try database.editDailyLog(userId: userId, date: date, clearing: stored == nil ? ["weighin_skip_reason"] : []) {
                $0.weighinSkipReason = stored
            }
        }
    }

    func saveBody(_ change: @Sendable @escaping (inout DailyLogRow) -> Void) -> Bool {
        write { [database, userId, date] in
            try database.saveBodyMetrics(userId: userId, date: date, change)
        }
    }

    /// The most recent reading before this date, for the form's placeholders.
    func latestBodyReading() throws -> DailyLogRow? {
        try database.latestBodyReading(userId: userId, before: date)
    }

    func addCardio(_ row: CardioLogRow) -> Bool {
        write { [database] in try database.addCardio(row) }
    }

    func deleteCardio(_ id: String) {
        cardio.removeAll { $0.id == id }
        write { [database, userId] in try database.deleteCardio(id: id, userId: userId) }
    }

    // MARK: Swaps

    func applySwap(_ writes: [ScheduleWrite], note: String) -> Bool {
        let landed = write { [database, userId, trainingOnlyKeys] in
            try database.applyScheduleWrites(
                userId: userId, writes.map { (date: $0.date, dayKey: $0.dayKey) },
                trainingOnlySupplementKeys: trainingOnlyKeys
            )
        }
        if landed { swapNote = note }
        return landed
    }

    /// Clear this date's override AND its partner's — a swap is two rows, and
    /// undoing one leaves the week half-rearranged.
    func undoSwap() {
        let dates = swapPairDates()
        guard !dates.isEmpty else { return }
        if write({ [database, userId, trainingOnlyKeys] in
            try database.clearScheduleOverrides(userId: userId, dates: dates, trainingOnlySupplementKeys: trainingOnlyKeys)
        }) {
            swapNote = dates.count > 1
                ? "Swap undone — \(Swap.shortDayLabel(dates[1])) is back to the plan too."
                : "Back to the plan."
        }
    }

    /// The two dates of the swap this date belongs to, this one first.
    ///
    /// The partner is the override, nearest first within the 13-day horizon in
    /// either direction, that now holds what the PLAN put here — and whose own
    /// plan day is what sits here now. A rest-day swap satisfies both halves
    /// (the partner is a plan rest day carrying the moved key); so does an
    /// exchange. When only the first half matches the nearest such row is taken.
    // ponytail: pairs are inferred, not stored — a `swap_id` column would make
    // this a lookup if two swaps in one fortnight ever share a key.
    func swapPairDates() -> [String] {
        guard let here = overrides[date] else { return [] }
        let bare = ScheduleContext(programId: planId, phase: phase, overrides: [:], layout: layout)
        func planKey(_ d: String) -> String { Schedule.scheduleDayIn(bare, d)?.dayKey ?? Schedule.restOverride }
        let wanted = planKey(date)
        guard wanted != here else { return [date] }
        let nearest = (1...Swap.horizonDays).flatMap { [$0, -$0] }.compactMap { ISODate.addDays(date, $0) }
        let partner = nearest.first { overrides[$0] == wanted && planKey($0) == here }
            ?? nearest.first { overrides[$0] == wanted }
        return [date] + (partner.map { [$0] } ?? [])
    }

    // MARK: - Helpers

    /// The slot's own time on that date, in the device's zone — a dose due at
    /// 22:00 was due at 22:00 here, not at some UTC noon.
    static func localInstant(_ iso: String, hhmm: String) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, let noon = LogicalDay.date(fromISO: iso) else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: noon)
    }
}
