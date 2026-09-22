import SwiftUI
import Charts
import OnyxUI
import OnyxCore
import OnyxData

/// Training Trends — four charts over ONE read of the session history.
///
/// ── WHY THERE IS NO MODEL ───────────────────────────────────────────────────
/// Every series here is a pure function of `[TrendSession]` and two pickers,
/// and the arithmetic is already ported with golden vectors (`sessionVolumeKg`,
/// `VolumeSplit`, `IntensityCalendar`, `WidgetDerive.e1rmTrends`,
/// `MuscleAggregator`). All that is left is slicing rows into marks, and a
/// `@State` array is the honest home for that — a model would be a struct
/// holding one array and four computed properties.
/// Everything the screen's `.task(id:)` must re-read on. See the note there.
private struct TrendsRead: Hashable {
    let generation: Int
    let plan: String?
    let phase: String?
}

struct TrainingTrendsView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Screenshot harness only; the app reads the environment's database.
    var seeded: [TrendSession]?
    /// Screenshot harness only: force a maintenance week the seeded history
    /// would not otherwise contain, so the hollow bars can be photographed.
    var seededLens: MaintenanceLens?

    @State private var sessions: [TrendSession]?
    @State private var window: EraWindow = .default
    @State private var input: EraWindowInput?
    /// Which weeks were maintenance weeks, resolved once for both charts that
    /// draw them. See `MaintenanceLens`.
    @State private var lens: MaintenanceLens = .schedule
    /// This phase's per-muscle weekly set targets (`plan_phase_volume`), for the
    /// atlas card — through `AppDatabase.volumeTargets`, which is the read the
    /// Today sheet and the widget tile already make. A fourth read of this table
    /// with a fourth policy about `user_id` is how the three accumulators W3
    /// deleted came to exist.
    @State private var volumeTargets: [LandmarkMuscle: Double] = [:]
    /// The generation this screen's data was read at.
    ///
    /// `.task(id:)` also fires on APPEAR, and this screen's whole point is that
    /// it reads a few thousand sets once. Keying the guard on the generation
    /// rather than on `sessions == nil` keeps that — and re-reads exactly when
    /// an edit has finished rewriting the scores behind it.
    @State private var loadedAt = -1

    private let today = LogicalDay.today()

    var body: some View {
        ScrollView {
            VStack(spacing: OnyxSpace.l) {
                if let sessions, let input {
                    let resolved = window.resolve(input)
                    // ── THE ATLAS CARD OWNS ITS OWN WINDOW ──────────────────
                    // It sits ABOVE the screen picker on purpose. Its question
                    // is "what has my body had", whose natural answer is a
                    // TRAINING WEEK against the week's targets — and the picker
                    // below governs three trend series whose natural answer is a
                    // phase. One control driving both would have to be wrong for
                    // one of them, so the card carries its own four windows and
                    // the picker visibly starts the section under it.
                    MuscleFocusAtlasCard(sessions: sessions, input: input, targets: volumeTargets)
                    EraWindowPicker(selection: $window, input: input)
                    // The window decides which sessions EXIST for this screen;
                    // each card still owns its own display span (the intensity
                    // grid is twelve weeks, the muscle bars four). Widening a
                    // heat grid to a year would draw a smear, and narrowing it
                    // to the window would make two cards answer the same
                    // question at two scales.
                    let visible = sessions.filter { resolved.contains($0.date) }
                    VolumeStreamCard(sessions: visible, era: resolved.era(cutStartISO: input.planStartISO), today: today, lens: lens, schedule: environment.targets?.schedule ?? ScheduleContext(programId: "", phase: .cut))
                    IntensityCard(sessions: visible, today: today)
                    StrengthTrendsCard(sessions: visible, today: today)
                } else {
                    ProgressView().controlSize(.large)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .onyxScreen(.train)
        .navigationTitle("Trends")
        // ── WHY THE SCHEDULE IS IN THE TASK ID ──────────────────────────────
        // `environment.targets` is nil until sign-in installs the resolver, and
        // a `.task` body does not observe. Keyed on the generation alone, a cold
        // open that lands before the resolver resolved read no targets and kept
        // none — the card would grade the week against nothing and say nothing
        // about it. The phase moving at a day boundary is the same bug with a
        // slower fuse: the generation does not change, so the week would be
        // graded against the phase before last.
        .task(id: TrendsRead(
            generation: environment.rescoreGeneration,
            plan: environment.targets?.schedule.programId,
            phase: environment.targets?.schedule.phase.rawValue
        )) {
            // Sixteen small rows, re-read whenever any of those three move —
            // they are also the one input here the athlete can change without a
            // rescore, by editing weekly set volume in Settings.
            // ── OFF THE MAIN ACTOR (W6) ─────────────────────────────────
            // A `.task` on a `@MainActor` view runs on the main actor, and
            // the read below it is the whole session history — ~5k sets on
            // this account, and it grows. Both go to a detached task; the
            // screen draws its previous answer until they land, which is what
            // it did before while blocking the first frame to do it.
            let database = environment.database
            let userId = environment.userIdString
            if let schedule = environment.targets?.schedule {
                volumeTargets = await Task.detached(priority: .userInitiated) {
                    (try? database.volumeTargets(
                        userId: database.localUserId(),
                        planId: schedule.programId,
                        phase: schedule.phase
                    )) ?? [:]
                }.value
            } else {
                // Cleared, not left behind: keeping the previous phase's numbers
                // after a switch is the staleness this key exists to prevent.
                volumeTargets = [:]
            }
            guard loadedAt != environment.rescoreGeneration else { return }
            loadedAt = environment.rescoreGeneration
            // ponytail: the whole history in one read (~5k sets today); page by
            // era/year when the table is ten times that.
            let today = today
            let read = await Task.detached(priority: .userInitiated) {
                (
                    sessions: (try? database.trainingTrendSessions(
                        userId: userId, from: "2000-01-01", to: today
                    )) ?? [],
                    lens: MaintenanceLens.read(database: database, userId: userId, today: today)
                )
            }.value
            let loaded = seeded ?? read.sessions
            sessions = loaded
            lens = seededLens ?? read.lens
            // "All" means this screen's own oldest session, not a floor
            // invented for it — which is exactly what `firstDataISO` is for.
            let firstData = loaded.map(\.date).min()
            input = await Task.detached(priority: .userInitiated) {
                EraWindowSource.input(database: database, today: today, firstDataISO: firstData)
            }.value
        }
    }
}

// MARK: - A. Volume stream

/// Weekly tonnage, one bar per programme week, stacked by split.
///
/// A session lands in the bucket its OWN `day_key` names (`VolumeSplit.resolve`)
/// — never the weekday, which a swap makes meaningless.
private struct VolumeStreamCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let sessions: [TrendSession]
    /// `ResolvedEraWindow.era` — `"ppl"`, `"axis"` or `"all"`, which is what
    /// `VolumeSplit.splits(forEra:)` speaks. A window spanning the cut start
    /// spans both programmes and gets both pill sets.
    let era: String
    let today: String
    let lens: MaintenanceLens
    /// Which plan owned a date — the legacy era tag `VolumeSplit` keys on.
    let schedule: ScheduleContext

    /// `nil` is every split, stacked.
    @State private var split: String?

    private struct Bar: Identifiable {
        let id: String
        let start: Date
        let end: Date
        let split: String
        let kg: Double
        /// Planned lighter — see `MaintenanceLens`.
        let maintenance: Bool
    }

    private var splits: [String] { VolumeSplit.splits(forEra: era) }

    /// The picked split, or all of them when the pick belongs to another era.
    private var activeSplit: String? { split.flatMap { splits.contains($0) ? $0 : nil } }

    private var bars: [Bar] {
        var order: [String] = []
        var kg: [String: Double] = [:]
        for s in sessions {
            let key = s.session.dayKey
            let bucket = VolumeSplit.resolve(dateISO: s.date, split: key ?? "", era: Schedule.legacyEra(schedule, s.date), dayKey: key)
            guard splits.contains(bucket), activeSplit == nil || bucket == activeSplit else { continue }
            let id = Week.start(of: s.date) + "|" + bucket
            if kg[id] == nil { order.append(id) }
            kg[id, default: 0] += s.volumeKg
        }
        return order.compactMap { id in
            let parts = id.split(separator: "|").map(String.init)
            guard let start = OnyxChart.date(parts[0]) else { return nil }
            return Bar(
                id: id, start: start, end: start.addingTimeInterval(7 * 86_400),
                split: parts[1], kg: kg[id]!, maintenance: lens.callsWeek(startingOn: parts[0])
            )
        }
    }

    /// The newest week's total, as the headline.
    private var latestWeekKg: Double? {
        guard let last = bars.map(\.start).max() else { return nil }
        return bars.filter { $0.start == last }.reduce(0) { $0 + $1.kg }
    }

    var body: some View {
        let bars = bars
        let weekTotals = Dictionary(grouping: bars, by: \.start).values.map { $0.reduce(0) { $0 + $1.kg } }
        OnyxChartCard(
            "Volume", domain: .train,
            headline: latestWeekKg.map { "\(ChartScale.compactKg($0)) kg" },
            legend: bars.contains(where: \.maintenance)
                ? AnyView(MaintenanceLegend(symbol: .bar)) : nil
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Split", selection: $split) {
                    Text("All splits").tag(String?.none)
                    ForEach(splits, id: \.self) { Text(VolumeSplit.label($0)).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
                .tint(Color.onyx.textSecondary)

                if bars.isEmpty {
                    OnyxChartEmpty("No sessions in this window.")
                } else {
                    Chart(bars) { bar in
                        // `x:` with a unit, not xStart/xEnd: only the former
                        // STACKS the splits; the range form overlays them.
                        BarMark(
                            x: .value("Week", bar.start, unit: .weekOfYear),
                            y: .value("Tonnage", bar.kg)
                        )
                        .foregroundStyle(by: .value("Split", VolumeSplit.label(bar.split)))
                        .cornerRadius(3)
                        // ── A MAINTENANCE WEEK IS DRAWN HOLLOW ──────────────
                        // A deliberate deload is a SHORT bar, and a short bar
                        // drawn like every other one reads as a week that went
                        // wrong. Washing it back says "planned" while keeping
                        // the split's own colour, which is what the legend and
                        // the picker are keyed on — a second hue per split
                        // would double the palette to say one thing.
                        //
                        // Hollow and not hatched: a stacked bar has no outline
                        // to hollow out and Swift Charts has no pattern fill,
                        // so a hatch would be a custom `ChartContent` drawing
                        // its own rectangles and losing the stack.
                        .opacity(bar.maintenance ? 0.38 : 1)
                    }
                    .chartForegroundStyleScale(
                        domain: splits.map(VolumeSplit.label),
                        range: splits.map { Color.onyx.day(Self.dayKey(for: $0)) }
                    )
                    // Tonnage starts at zero; left to itself the axis pads
                    // below the floor and prints a negative tonnage.
                    .chartYScale(domain: 0...max(1, weekTotals.max() ?? 1) * 1.08)
                    .onyxChart(.train)
                    // Eight legend rows at AX5 are the whole plot. The split
                    // picker above is the legend there: pick one, see one.
                    .chartLegend(typeSize.isAccessibilitySize ? .hidden : .automatic)
                    .onyxScrollable(days: 84, endingAt: OnyxChart.date(Week.start(of: today))?.addingTimeInterval(7 * 86_400) ?? Date())
                }
            }
        }
    }

    /// A split's swatch is the colour of the DAY that trains it.
    private static func dayKey(for split: String) -> String {
        switch split {
        case "push": "ppl_push_sun"
        case "pull": "ppl_pull_mon"
        case "legs": "ppl_legs_tue"
        default: split
        }
    }
}

// MARK: - B. Intensity calendar

/// Twelve weeks of daily load as a heat grid: x = week, y = weekday, fill = the
/// day's tonnage against the window's heaviest day, on ONE hue.
private struct IntensityCard: View {
    let sessions: [TrendSession]
    let today: String

    private static let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private struct Cell: Identifiable {
        let id: String
        let week: String
        /// 0 = Sunday, plotted top-down on a numeric y so the band has a real
        /// height: a categorical y ignores `height: .ratio` and draws a hairline.
        let day: Int
        let t: Double
        var yStart: Double { Double(6 - day) + 0.1 }
        var yEnd: Double { Double(6 - day) + 0.9 }
    }

    private var volumeByDate: [(String, Double)] {
        var order: [String] = []
        var kg: [String: Double] = [:]
        for s in sessions {
            if kg[s.date] == nil { order.append(s.date) }
            kg[s.date, default: 0] += s.volumeKg
        }
        return order.map { ($0, kg[$0]!) }
    }

    var body: some View {
        let model = IntensityCalendar.build(volumeByDate: volumeByDate, days: 84, todayISO: today)
        let weeks = model?.weeks.compactMap { $0.first.flatMap { OnyxChart.date($0.date) }.map(OnyxChart.shortDate) } ?? []
        let cells: [Cell] = (model?.weeks ?? []).enumerated().flatMap { w, column in
            column.enumerated().compactMap { d, cell in
                cell.elapsed ? Cell(id: cell.date, week: weeks[w], day: d, t: cell.t) : nil
            }
        }
        OnyxChartCard("Intensity", domain: .train, caption: model.map(caption)) {
            if let model, model.stats.activeDays > 0 {
                Chart(cells) { cell in
                    RectangleMark(
                        x: .value("Week", cell.week),
                        yStart: .value("Day", cell.yStart),
                        yEnd: .value("Day", cell.yEnd),
                        width: .ratio(0.8)
                    )
                    // Sequential: the accent from faint to full. Untrained is the hairline.
                    .foregroundStyle(cell.t > 0 ? OnyxDomain.train.accent.opacity(0.25 + 0.75 * cell.t) : Color.onyx.hairline)
                    .cornerRadius(3)
                }
                .chartXScale(domain: weeks)
                .chartYScale(domain: 0...7)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: (0..<7).map { Double($0) + 0.5 }) { value in
                        if let y = value.as(Double.self) {
                            AxisValueLabel {
                                Text(Self.days[6 - Int(y)])
                                    .font(OnyxChart.axisFont)
                                    .foregroundStyle(Color.onyx.textTertiary)
                            }
                        }
                    }
                }
                // Twelve week labels do not fit one plot width; every third.
                // Before `onyxChart`: the axis closest to the Chart wins.
                .chartXAxis {
                    AxisMarks(values: weeks) { value in
                        if let week = value.as(String.self), let i = weeks.firstIndex(of: week), i % 3 == 0 {
                            AxisValueLabel {
                                Text(week)
                                    .font(OnyxChart.axisFont)
                                    .foregroundStyle(Color.onyx.textTertiary)
                            }
                        }
                    }
                }
                .onyxChart(.train)

            } else {
                OnyxChartEmpty("Nothing in the last 12 weeks.")
            }
        }
    }

    private func caption(_ model: CalendarModel) -> String {
        let stats = model.stats
        var bestWeek: [String: Double] = [:]
        let first = model.weeks.first?.first?.date ?? today
        for s in sessions where s.date >= first { bestWeek[Week.start(of: s.date), default: 0] += s.volumeKg }
        var parts = ["\(stats.activeDays) sessions", "streak \(stats.streak) d"]
        if let best = bestWeek.values.max(), best > 0 { parts.append("best week \(ChartScale.compactKg(best)) kg") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - C. Strength trends

/// Session-best estimated 1RM for the most-trained loaded exercises — one point
/// per session, the TOP set's estimate (`collapseToSessionBest`), stored
/// `est_1rm_kg` read with `||` semantics so a legacy 0 falls through to Epley.
private struct StrengthTrendsCard: View {
    let sessions: [TrendSession]
    let today: String

    @State private var selection: Date?

    private struct Point: Identifiable {
        let id: String
        let exercise: String
        let iso: String
        let date: Date
        let kg: Double
    }

    /// Most-trained first, so colour order is stable across eras.
    private var series: [WidgetE1rm] {
        var sessionsPer: [String: Set<String>] = [:]
        var rows: [WidgetSetRow] = []
        for s in sessions {
            for t in s.sets where SetTags.isWorkingSet(t.set.setType) && t.set.weightKg > 0 {
                sessionsPer[t.exerciseName, default: []].insert(s.id)
                rows.append(WidgetSetRow(
                    exercise: t.exerciseName, day: s.date, weightKg: t.set.weightKg, reps: Double(t.set.reps),
                    est1rmKg: t.set.est1rmKg, setType: t.set.setType
                ))
            }
        }
        let top = sessionsPer
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .prefix(4)
            .map(\.key)
        let trends = WidgetDerive.e1rmTrends(rows.filter { top.contains($0.exercise) }, asOf: today, windowDays: 28, limit: top.count)
        return top.compactMap { name in trends.first { $0.exercise == name } }
    }

    var body: some View {
        let series = series
        let points: [Point] = series.flatMap { e in
            e.trend.compactMap { p in
                OnyxChart.date(p.d).map { Point(id: "\(e.exercise)|\(p.d)", exercise: e.exercise, iso: p.d, date: $0, kg: p.v) }
            }
        }
        let domain = ChartScale.niceDomain(points.map(\.kg), hardMin: 0)
        OnyxChartCard("Strength", domain: .train) {
            if points.isEmpty {
                OnyxChartEmpty("No loaded sets yet.")
            } else {
                Chart {
                    ForEach(points) { p in
                        LineMark(x: .value("Date", p.date), y: .value("est. 1RM", p.kg))
                            .foregroundStyle(by: .value("Exercise", p.exercise))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", p.date), y: .value("est. 1RM", p.kg))
                            .foregroundStyle(by: .value("Exercise", p.exercise))
                            .symbolSize(18)
                    }
                    if let picked = nearest(points, to: selection) {
                        RuleMark(x: .value("Date", picked.date))
                            .foregroundStyle(Color.onyx.textTertiary)
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                OnyxCallout(OnyxChart.shortDate(picked.date), lines: series.enumerated().compactMap { i, e in
                                    points.first { $0.exercise == e.exercise && $0.iso == picked.iso }
                                        .map { OnyxCallout.Line(e.exercise, "\(jsToFixed1($0.kg)) kg", color: Color.onyx.series(i)) }
                                })
                            }
                    }
                }
                .chartForegroundStyleScale(domain: series.map(\.exercise), range: series.indices.map(Color.onyx.series))
                .chartYScale(domain: domain.0...domain.1)
                .chartXSelection(value: $selection)
                .onyxChart(.train)
                .onyxScrollable(days: 120, endingAt: OnyxChart.date(today) ?? Date())
            }
        }
    }

    /// The logged date closest to the finger.
    private func nearest(_ points: [Point], to date: Date?) -> Point? {
        guard let date else { return nil }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

// MARK: - D. Muscle focus · the body, and what landed on it

/// The week on the body: the atlas at full size, and every landmark's weighted
/// set count under it.
///
/// ── WHAT THIS REPLACED ──────────────────────────────────────────────────────
/// A horizontal bar chart of six families over a hard-coded trailing 28 days,
/// fed by `MuscleAggregator` — the third of the three accumulators F7 found, and
/// the one that credited no assistance and started its weeks on a Sunday
/// whatever the athlete had chosen. It could disagree with the tile on the
/// dashboard and with the sheet that tile opens, about the same session, and it
/// did. It is gone; this card calls `MuscleCredit.weightedSets(exerciseNames:)`
/// like both of them.
///
/// ── AND WHY THE FIGURE, NOT BARS ────────────────────────────────────────────
/// Sixteen bars ranked by count tell you Legs was the biggest number, which you
/// knew. The body tells you the week was all on the FRONT of you, which no
/// ranked list can — the sheet's own note (`MuscleFocusSheetBody`) makes the
/// same argument for the same reason, and this card is that sheet's answer over
/// a window you choose.
private struct MuscleFocusAtlasCard: View {
    let sessions: [TrendSession]
    let input: EraWindowInput
    /// `plan_phase_volume` for the current (plan, phase).
    let targets: [LandmarkMuscle: Double]

    /// This week / 30 d / All / the plan's own name.
    ///
    /// Four and not the screen picker's six: "current lever" is a NUTRITION
    /// window and means nothing to a set count, and "since cut" is
    /// `.currentProgram` under a name that is wrong on a bulk.
    private static let windows: [EraWindow] = [.thisWeek, .days(30), .all, .currentProgram]

    @State private var window: EraWindow = .thisWeek

    private var resolved: ResolvedEraWindow { window.resolve(input) }

    /// Targets are WEEKLY. Over any wider window they are not a bar to clear, so
    /// the legend drops them rather than grading a month against seven days.
    ///
    /// …and an athlete who has set NONE has no targets to grade against either.
    /// Without the second clause the figure and every rail grade against a peak
    /// target of zero and come out blank — a week with work in it, drawn as a
    /// week with none, which is the one thing this card may never do.
    private var showsTargets: Bool {
        window == .thisWeek && targets.values.contains { $0 > 0 }
    }


    private var rows: [MuscleFocusRow] {
        let credit = MuscleCredit.weightedSets(
            exerciseNames: sessions
                .filter { resolved.contains($0.date) }
                .flatMap(\.sets)
                .filter { $0.set.setType != "ghost" }
                .map(\.exerciseName)
        )
        return LandmarkMuscle.allCases.map { muscle in
            MuscleFocusRow(
                muscle: muscle,
                // One decimal: the credit is halves, and a raw Double prints
                // 8.500000000000002 often enough to matter.
                sets: ((credit[muscle] ?? 0) * 10).rounded() / 10,
                target: showsTargets ? Int(targets[muscle] ?? 0) : 0
            )
        }
    }

    var body: some View {
        let rows = rows
        let done = rows.reduce(0) { $0 + $1.sets }
        VStack(alignment: .leading, spacing: 10) {
            header(done: done)
            picker
            if done == 0 {
                OnyxChartEmpty("No sets logged in this window.")
            } else {
                AtlasFigure(side: .both, worked: worked(rows))
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                MuscleFocusLegend(rows: rows, showsTargets: showsTargets)
            }
        }
        .padding(OnyxChart.cardPadding)
        .onyxGlass(.tile)
    }

    /// The card's own header, in `OnyxChartCard`'s language — but not that card:
    /// it hands its content a FIXED plot height, and a 260 pt figure with
    /// sixteen legend rows under it is not a plot.
    @ViewBuilder private func header(done: Double) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) { title; Spacer(minLength: 8); headline(done) }
            VStack(alignment: .leading, spacing: 4) { title; headline(done) }
        }
        Text(resolved.label)
            .font(.footnote)
            .foregroundStyle(Color.onyx.textSecondary)
    }

    private var title: some View {
        Text("MUSCLE FOCUS")
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(OnyxDomain.train.accent)
    }

    /// The window's weighted sets — the sum over all SIXTEEN landmarks, so a
    /// leg-press week reads about double its physical set count. That is the
    /// currency, not a double count: see "WHY A SUM AND NOT A SET COUNT" on
    /// `OnyxSnapshot.FamilyVolume`. It agrees exactly with the Today sheet's
    /// "sets done", which reduces the same sixteen.
    private func headline(_ done: Double) -> some View {
        Text("\(OnyxFormat.sets(done)) sets")
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Color.onyx.textPrimary)
            .contentTransition(.numericText())
    }

    /// Segmented while four labels fit, a menu when they do not.
    ///
    /// Not a type-size threshold: the fourth label is the PLAN's name and can be
    /// anything from "PPL" to "Onyx-5 Lean Bulk", so whether the row fits is a
    /// question about this athlete's data and not about the body font.
    private var picker: some View {
        ViewThatFits(in: .horizontal) {
            Picker("Window", selection: $window) { options }
                .pickerStyle(.segmented)
            Picker("Window", selection: $window) { options }
                .pickerStyle(.menu)
                .tint(Color.onyx.textSecondary)
        }
    }

    @ViewBuilder private var options: some View {
        ForEach(Self.windows, id: \.key) { w in
            Text(label(w)).tag(w)
        }
    }

    private func label(_ w: EraWindow) -> String {
        switch w {
        case .thisWeek: "Week"
        case .days(let n): "\(n) d"
        case .all: "All"
        case .currentProgram: input.planLabel
        default: w.resolve(input).label
        }
    }

    /// Landmark → 0…1 for the figure. `rows` already zeroes every target outside
    /// a week window, and `MuscleCredit.worked(sets:targets:)` grades against the
    /// busiest muscle when there is no target to grade against — so this is the
    /// same one call the widget tile and the Today sheet make, in both windows.
    private func worked(_ rows: [MuscleFocusRow]) -> [LandmarkMuscle: Double] {
        MuscleCredit.worked(
            sets: Dictionary(rows.map { ($0.muscle, $0.sets) }, uniquingKeysWith: { a, _ in a }),
            targets: Dictionary(rows.map { ($0.muscle, $0.target) }, uniquingKeysWith: { a, _ in a })
        )
    }
}

#if DEBUG
#Preview("Trends") {
    TrendsPreviews.view("trends")
}

#Preview("Trends — empty") {
    TrendsPreviews.view("trends-empty")
}
#endif
