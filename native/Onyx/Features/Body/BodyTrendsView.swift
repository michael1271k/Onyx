import SwiftUI
import Charts
import OnyxUI
import OnyxCore
import OnyxData

/// Body & Vitals over time — the Body tab's trends screen.
///
/// One column of chart cards on the Tide ground: the scale, its ledger, steps,
/// then the four vitals groups. Everything comes from ONE range read at
/// appearance (`bodyVitals`); the screen is a push, so a fresh push after a
/// weigh-in is the refresh. Every chart is Swift Charts wearing `onyxChart`,
/// pans over the whole window and scrubs with the system selection — no
/// custom legend, no custom tooltip, one y-axis each.
struct BodyTrendsView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Supplied only by previews and the screenshot harness.
    var seeded: BodyVitalsSlice?
    /// Screenshot harness only: open with the ledger card pinned to this
    /// reading. A scrub is a gesture, and a gesture is the one thing a
    /// screenshot cannot perform.
    var seededSelection: String?
    /// Screenshot harness only — see `readStress` below. The one series on this
    /// screen that is read from the DATABASE rather than handed in with the
    /// slice, so the harness has to supply it separately or photograph an empty
    /// card under ninety days of charts.
    var seededStress: [StressDay]?
    /// History's Body segment shows this same screen INSIDE its own navigation
    /// (§5.9), where a second "Trends" title and a second background would both
    /// be wrong. Only the chrome differs — the charts are one implementation.
    var embedded = false

    @State private var slice: BodyVitalsSlice?
    @State private var window: EraWindow = .default
    @State private var input: EraWindowInput?
    /// The stress index over `StressSection.days`, oldest first (§U5.3).
    @State private var stress: [StressDay] = []
    /// Which run of the read below is the current one — see the `.task`.
    @State private var reads = 0

    var body: some View {
        Group {
            if let slice, let input {
                BodyTrendsScreen(
                    slice: slice, window: $window, input: input,
                    stress: stress, seededSelection: seededSelection
                )
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .modifier(BodyTrendsChrome(embedded: embedded))
        // Keyed on the window AND the cascade: a body reading is not a score,
        // but an edit that moves a day moves what the ledger card compares
        // against, and a screen that has been open since before the edit would
        // go on drawing the old series with no way to ask it not to.
        // ── A SUPERSEDED RUN MUST NOT WIN ──────────────────────────────
        // These reads are detached now, and `await Task.detached(…).value` on
        // a non-throwing task is not a cancellation point: `.task(id:)`
        // cancels the old run, but its child finishes anyway and its
        // assignment lands. An `All` scan started before the reader picked
        // `1 year` returns AFTER the small one and overwrites it, so the chart
        // draws the whole account under a picker that says a year. One
        // generation, checked before every write.
        .task(id: Reload(window: window, generation: environment.rescoreGeneration)) {
            reads &+= 1
            let run = reads
            // Detached: `EraWindowSource.input` is three reads and the slice
            // below is a ranged scan of `body_composition` and `daily_logs`
            // that `.all` lets run to the start of the account. Both used to
            // happen on the main actor because a `.task` on a `@MainActor`
            // view runs there (W6).
            let database = environment.database
            let resolved = await Task.detached(priority: .userInitiated) {
                EraWindowSource.input(database: database)
            }.value
            guard run == reads else { return }
            input = resolved
            // A seeded slice is a fixed window by definition; re-reading it on
            // a window change would replace the harness's data with an empty
            // database's answer.
            if let seeded {
                slice = seeded
            } else {
                let userId = environment.userIdString
                let range = window.resolve(resolved)
                let read = await Task.detached(priority: .userInitiated) {
                    (try? database.bodyVitals(userId: userId, from: range.startISO, to: range.endISO)) ?? .empty
                }.value
                guard run == reads else { return }
                slice = read
            }
            if let seededStress {
                stress = seededStress
            } else {
                let series = await Self.readStress(
                    database: environment.database, userId: environment.userIdString
                )
                guard run == reads else { return }
                stress = series
            }
        }
    }

    /// ── WHY THE STRESS SERIES IGNORES THE WINDOW PICKER ─────────────────────
    /// v1 stores no column, so every day in the series is a `readinessHistory`
    /// build over the 49 days behind it (`STRESS_MODEL.md` §6). At the picker's
    /// "All" that is one such build per day of the account's whole life, and
    /// the answer would be a year of dots two pixels apart. Eight weeks is the
    /// same display window the vitals cards on this screen already keep, for
    /// the same reason, and it is what the index is legible over.
    // ponytail: window-driven once `daily_scores.stress_index` exists.
    private static func readStress(database: AppDatabase, userId: String) async -> [StressDay] {
        let limit = StressSection.days
        return await Task.detached(priority: .userInitiated) {
            (try? database.stressSeries(userId: userId, endingOn: LogicalDay.today(), limit: limit)) ?? []
        }.value
    }

    /// ── WHY "ALL" IS SAFE HERE NOW ──────────────────────────────────────────
    /// This read is RANGED, and the range picker used to stop at a year for
    /// exactly that reason: an unbounded query grows with the account forever
    /// to draw a line nobody can read at a phone's width. `EraWindow.all`
    /// resolves against `EraWindowSource.programStart` — the first day any
    /// phase covers — which is a real date from the phase table rather than a
    /// floor invented for this screen, and is a bound the account cannot have
    /// data before.
}

/// What re-reads the screen: the picked window, or a finished rescore.
///
/// One `Equatable` value because `.task(id:)` takes ONE id, and two `.task`s
/// racing to fill the same `@State` is how a screen ends up showing the older
/// of two reads.
private struct Reload: Equatable {
    let window: EraWindow
    let generation: Int
}

/// The chrome the pushed screen wears and the embedded one does not.
private struct BodyTrendsChrome: ViewModifier {
    let embedded: Bool

    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .onyxScreen(.body)
                .navigationTitle("Trends")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct BodyTrendsScreen: View {
    let slice: BodyVitalsSlice
    @Binding var window: EraWindow
    let input: EraWindowInput
    let stress: [StressDay]
    let seededSelection: String?

    var body: some View {
        let readings = BodyVitals.readings(ledger: slice.ledger, logs: slice.logs)
        // The vitals cards keep their own 56-day display window. The window
        // picker drives the three charts §5.9 names — scale, ledger, steps —
        // and widening eight sparklines to a year alongside them would make
        // every one of them a smear.
        let recent = ISODate.addDays(LogicalDay.today(), -55) ?? LogicalDay.today()
        let logs = slice.logs.filter { $0.date >= recent }
        // The chart's scroll span is the window the picker resolved, not a
        // constant. W11 replaced this screen's 30/90/365 control with
        // `EraWindow`; two strings under it went on saying 90 days, so a
        // reader who chose "30 d" was told "No weigh-ins in the last 90 days"
        // about a window they had not asked for.
        let resolved = window.resolve(input)
        ScrollView {
            VStack(alignment: .leading, spacing: OnyxSpace.l) {
                EraWindowPicker(selection: $window, input: input)

                CompositionSection(
                    readings: readings, goals: slice.goals, windowDays: resolved.days,
                    ladder: input.ladder, phases: input.phases,
                    seededSelection: seededSelection
                )
                StepsSection(
                    steps: BodyVitals.steps(metrics: slice.metrics.filter { $0.date >= recent }, logs: logs),
                    goal: slice.goals?.stepsGoal
                )
                // Above the vitals it is built from: the index is the ONE line
                // on this screen that answers "how far from normal", and the
                // four groups below it are the readings it folds.
                StressSection(days: stress)
                ForEach(VitalGroup.allCases) { VitalGroupCard(group: $0, logs: logs) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }
}

/// A row that stacks at accessibility sizes: an `HStack` of a header and a
/// picker, or a date and a number, is three one-word columns at AX5.
@MainActor
@ViewBuilder
private func accessibleRow<Content: View>(spacing: CGFloat = 8, @ViewBuilder _ content: () -> Content) -> some View {
    AccessibleRow(spacing: spacing, content: content())
}

private struct AccessibleRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let spacing: CGFloat
    let content: Content
    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}

// MARK: - Shared chart arithmetic

/// What every dated chart on this screen needs and Swift Charts leaves to the
/// app: which point the finger is nearest, where a line must break, and how
/// tight the y-axis sits on the data.
enum Trend {
    struct Run { let point: TrendPoint; let run: Int }

    /// A gap in the dates is a gap in the line: consecutive days share a run,
    /// a missing day starts a new one, and `series:` on the mark breaks the
    /// stroke between runs. Nothing is ever plotted for the missing day.
    static func runs(_ series: [TrendPoint]) -> [Run] {
        var out: [Run] = []
        var run = 0
        var previous: Int?
        for p in series {
            let n = ISODate.dayNumber(p.d)
            if let previous, let n, n - previous > 1 { run += 1 }
            out.append(Run(point: p, run: run))
            previous = n
        }
        return out
    }

    struct Hit { let point: TrendPoint; let date: Date }

    /// The reading nearest the scrubbed x, within three and a half days of it.
    /// Scale readings are sparse by protocol, so "the day under the finger" is
    /// usually a day with nothing on it; the nearest reading is what Health
    /// shows and what the finger meant.
    static func nearest(_ series: [TrendPoint], to selected: Date) -> Hit? {
        let hits = series.compactMap { p in OnyxChart.date(p.d).map { Hit(point: p, date: $0) } }
        guard let hit = hits.min(by: { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }),
              abs(hit.date.timeIntervalSince(selected)) <= 3.5 * 86_400 else { return nil }
        return hit
    }

    /// The tight domain as a range, for `chartYScale`.
    static func domain(_ values: [Double?]) -> ClosedRange<Double> {
        let (lo, hi) = ChartScale.tightDomain(values)
        return lo...hi
    }

    static let dash = StrokeStyle(lineWidth: 1, dash: [4, 3])
}

// MARK: - A. Composition

/// What the picker can put on the one y-axis. Switching swaps the series; it
/// never adds a rail.
private enum BodyPlot: String, CaseIterable, Identifiable {
    case weight, fat, skeletal, lean, ffm, visceral, whr

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weight:   "Weight"
        case .fat:      "Body fat"
        case .skeletal: "Skeletal muscle"
        case .lean:     "Lean soft tissue"
        case .ffm:      "Fat-free mass"
        case .visceral: "Visceral fat"
        case .whr:      "W:H ratio"
        }
    }

    func value(_ r: BodyReading) -> Double? {
        switch self {
        case .weight:   r.weight
        case .fat:      r.fatPct
        case .skeletal: r.skeletalMuscle
        case .lean:     r.leanSoftTissue
        case .ffm:      r.fatFreeMass
        case .visceral: r.visceral
        case .whr:      r.waistToHip
        }
    }

    /// The domain metric whose direction `DeltaVerdict` knows, or nil.
    ///
    /// Only four things have an agreed direction. Lean soft tissue and
    /// fat-free mass move with muscle and are read the same way; a visceral
    /// index and a waist-to-hip ratio are readings this screen has no rule for,
    /// and colouring their deltas would be the view inventing one.
    var bodyMetric: BodyMetric? {
        switch self {
        case .weight:                     .weight
        case .fat:                        .fat
        case .skeletal, .lean, .ffm:      .muscle
        case .visceral, .whr:             nil
        }
    }

    func format(_ v: Double?) -> String {
        guard let v else { return "—" }
        switch self {
        case .weight, .skeletal, .lean, .ffm: return "\(jsToFixed(v, 1)) kg"
        case .fat:      return "\(jsToFixed(v, 1)) %"
        case .visceral: return jsToFixed(v, 0)
        case .whr:      return jsToFixed(v, 2)
        }
    }
}

private struct CompositionSection: View {
    let readings: [BodyReading]
    let goals: UserGoalRow?
    /// The resolved window's span, so the scroll domain matches the picker.
    let windowDays: Int
    /// The rungs and the phases — what decides whether a delta fell inside a
    /// maintenance week (rows since W2, carried by the era-window input).
    let ladder: LeverLadder
    let phases: [PhaseDef]
    /// Harness only — see `BodyTrendsView.seededSelection`.
    var seededSelection: String?

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var plot: BodyPlot = .weight
    @State private var selected: Date?
    /// The reading the card was left on. A long-press banks the point under the
    /// finger; letting go then returns to it rather than to nothing, and a
    /// second long-press lets it go.
    @State private var pinned: Date?

    /// What the ledger card is about right now: the finger while it is down,
    /// the pin when it is not.
    private var active: Date? { selected ?? pinned }

    private var series: [TrendPoint] {
        readings.compactMap { r in plot.value(r).map { TrendPoint(d: r.date, v: $0) } }
    }

    private var target: Double? { plot == .weight ? goals?.targetWeightKg : nil }

    var body: some View {
        let series = series
        VStack(alignment: .leading, spacing: 8) {
            accessibleRow {
                OnyxSectionHeader("Composition", .body)
                Spacer(minLength: 8)
                Picker("Metric", selection: $plot) {
                    ForEach(BodyPlot.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Color.onyx.accent(.body))
                .accessibilityLabel("Composition metric")
            }
            OnyxChartCard(plot.label, domain: .body, headline: series.last.map { plot.format($0.v) }) {
                if series.isEmpty {
                    OnyxChartEmpty("No \(plot.label.lowercased()) readings yet.")
                } else {
                    chart(series)
                }
            }
            // ── AT AX5 IT STOPS FLOATING ────────────────────────────────────
            // The card carries the delta and the interval, and since the
            // ledger LIST was deleted it is the only place either is written
            // down — so capping its type to keep it small would cap the one
            // surface a fact appears on. Instead it leaves the plot: at an
            // accessibility size a card set in accessibility type covers the
            // chart it is describing and clips its own last line. The rule
            // still marks the reading; the card just sits under it.
            if typeSize.isAccessibilitySize, let active, let hit = Trend.nearest(series, to: active) {
                ledger(hit, series: series)
            }
        }
        // A pin is about ONE reading of ONE metric. Carrying it across a
        // picker change would leave the card describing kilograms over a body
        // fat axis, which is the bug the deleted ledger list had.
        .onChange(of: plot) {
            selected = nil
            pinned = nil
        }
        .task {
            guard pinned == nil, let iso = seededSelection else { return }
            pinned = OnyxChart.date(iso)
        }
    }

    // MARK: - The ledger card

    /// The scrubbed reading, its delta and how long ago — the ledger, as a
    /// floating card instead of a list.
    ///
    /// ── WHY THE DELTA IS JUDGED AND NOT JUST SIGNED ─────────────────────────
    /// Half a kilogram down is good in a cut, bad in a bulk and neither in a
    /// maintenance week — that is `DeltaVerdict`, the same rule with the same
    /// vector the ledger list used, now reached through `Color.onyx.verdict`
    /// so the tooltip and anything else that shows a delta cannot disagree.
    /// Inside the maintenance band the verdict is `neutral` and the colour is
    /// text ink: "this did not move" is a statement, and a hue would make it a
    /// verdict it is not.
    ///
    /// ── AND WHY "DAYS SINCE" IS THE FOOTNOTE ────────────────────────────────
    /// Scale readings are sparse by protocol. A −0.4 kg is a different fact
    /// after two days than after three weeks, and without the interval the
    /// delta invites being read as a rate.
    private func ledger(_ hit: Trend.Hit, series: [TrendPoint]) -> some View {
        let i = series.firstIndex { $0.d == hit.point.d }
        let previous = i.flatMap { $0 > 0 ? series[$0 - 1] : nil }
        let delta = previous.map { hit.point.v - $0.v }
        let days: Int? = previous.flatMap { p in
            guard let now = ISODate.dayNumber(hit.point.d), let was = ISODate.dayNumber(p.d)
            else { return nil }
            return now - was
        }
        var lines = [OnyxCallout.Line(plot.label, plot.format(hit.point.v))]
        if let delta, abs(delta) >= 0.01 {
            lines.append(
                OnyxCallout.Line(
                    "Δ",
                    (delta > 0 ? "+" : "−") + plot.format(abs(delta)),
                    color: Color.onyx.verdict(verdict(delta, on: hit.point.d))
                )
            )
        }
        return OnyxCallout(
            OnyxChart.shortDate(hit.date),
            lines: lines,
            // Short on purpose: the card is clamped inside the plot, so a
            // footnote wider than the values above it is a footnote with its
            // tail cut off. "3 days since" says the same thing and fits.
            footnote: days.map { $0 == 1 ? "1 day since" : "\($0) days since" }
                ?? "First in this window",
            pinned: pinned == hit.date && selected == nil
        )
        // The pin is dropped by tapping the card it left behind — the same
        // place the eye already is, and the only affordance that does not
        // compete with the scrub.
        .contentShape(.rect)
        .onTapGesture { pinned = nil }
        .accessibilityElement(children: .combine)
    }

    /// Is this delta good news? Phase-aware, and dead inside a maintenance
    /// week's band — `DeltaVerdict`, unchanged from the list this replaced.
    ///
    /// Only weight, fat and skeletal muscle have a direction anyone agrees on;
    /// the rest are readings, and a verdict on a waist-to-hip ratio delta would
    /// be this screen inventing a rule the domain does not have.
    private func verdict(_ delta: Double, on date: String) -> Verdict {
        guard let metric = plot.bodyMetric else { return .neutral }
        return DeltaVerdict.verdict(
            metric, delta: delta,
            phase: ProgramPhase.stored(goals?.activePhase ?? goals?.goalPreset),
            maintenance: Maintenance.isMaintenanceDate(date, today: LogicalDay.today(), ladder: ladder, phases: phases)
        )
    }

    private func chart(_ series: [TrendPoint]) -> some View {
        Chart {
            ForEach(series, id: \.d) { p in
                if let date = OnyxChart.date(p.d) {
                    LineMark(x: .value("Day", date, unit: .day), y: .value(plot.label, p.v))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Day", date, unit: .day), y: .value(plot.label, p.v))
                        .symbolSize(24)
                }
            }
            if let target {
                RuleMark(y: .value("Target", target))
                    .lineStyle(Trend.dash)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Target \(jsToFixed(target, 1)) kg")
                            .font(OnyxChart.axisFont)
                            .foregroundStyle(Color.onyx.textTertiary)
                    }
            }
            if let active, let hit = Trend.nearest(series, to: active) {
                RuleMark(x: .value("Day", hit.date, unit: .day))
                    .foregroundStyle(Color.onyx.textTertiary)
                    // ── `y: .fit`, NOT `.disabled` ──────────────────────────
                    // `position: .top` puts the card ABOVE the rule and the
                    // rule spans the whole plot, so with the vertical overflow
                    // unresolved the card lands above the plot's own top edge
                    // and the card clips it away entirely — the first shot was
                    // a rule line with nothing on it. Fitting to the chart
                    // pulls it back inside, which is where a card following a
                    // finger belongs anyway.
                    .annotation(
                        position: .top, spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        if !typeSize.isAccessibilitySize { ledger(hit, series: series) }
                    }
            }
        }
        .chartYScale(domain: Trend.domain(series.map { Optional($0.v) } + [target]))
        .chartXSelection(value: $selected)
        // ── SIMULTANEOUS, NOT `.onLongPressGesture` ─────────────────────────
        // `chartXSelection` owns a drag on this view. A long press added the
        // ordinary way is a second exclusive gesture and one of the two stops
        // firing — in practice the scrub, which is the one that matters.
        // Simultaneous lets the press land WHILE the finger is scrubbing,
        // which is also the only moment there is a point worth pinning.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                guard let selected, let hit = Trend.nearest(series, to: selected) else { return }
                pinned = pinned == hit.date ? nil : hit.date
            }
        )
        .onyxScrollable(days: windowDays)
        .onyxChart(.body)
    }
}

// MARK: - B. The ledger, folded into the chart
//
// ── WHY THE LIST IS GONE ─────────────────────────────────────────────────────
// `LedgerSection` drew the last ten weigh-ins as rows under the chart: the same
// ten points the chart above it had just plotted, with the same deltas, judged
// by the same `DeltaVerdict` — a second rendering of one dataset, four hundred
// points tall, that the reader had to look away from the chart to consult. And
// it only ever spoke about WEIGHT, so choosing "Body fat" from the picker left
// a "Ledger" underneath still listing kilograms.
//
// The chart already has a scrub. So the ledger is what the scrub SAYS: the
// reading, its delta against the previous one with the verdict's colour, and
// how long ago that was — for whichever metric is on the axis. Long-press pins
// the card so it can be read with the thumb off the glass. See
// `CompositionSection.ledger`.

// MARK: - C. Steps

/// Daily steps against the goal. Above-goal days wear Tide, the rest wear
/// tertiary ink — status colours stay reserved; a short day is not a failure.
private struct StepsSection: View {
    let steps: [TrendPoint]
    let goal: Int?

    @State private var selected: Date?

    private static func count(_ v: Double) -> String { Int(jsRound(v)).formatted() }

    var body: some View {
        let week = BodyVitals.weekly(steps, roll: .mean).last
        VStack(alignment: .leading, spacing: 8) {
            OnyxSectionHeader("Steps", .body)
            OnyxChartCard(
                "Daily steps", domain: .body,
                headline: steps.last.map { Self.count($0.v) },
                caption: week.map { w in
                    "This week \(Self.count(w.v)) a day" + (goal.map { " · goal \($0.formatted())" } ?? "")
                }
            ) {
                if steps.isEmpty {
                    OnyxChartEmpty("No steps from Apple Health yet.")
                } else {
                    chart
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(steps, id: \.d) { p in
                if let date = OnyxChart.date(p.d) {
                    BarMark(x: .value("Day", date, unit: .day), y: .value("Steps", p.v))
                        .foregroundStyle(goal.map { p.v >= Double($0) } ?? true ? Color.onyx.accent(.body) : Color.onyx.textTertiary)
                        .cornerRadius(3)
                }
            }
            if let goal {
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(Trend.dash)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal \(goal.formatted())")
                            .font(OnyxChart.axisFont)
                            .foregroundStyle(Color.onyx.textTertiary)
                    }
            }
            if let selected, let hit = Trend.nearest(steps, to: selected) {
                RuleMark(x: .value("Day", hit.date, unit: .day))
                    .foregroundStyle(Color.onyx.textTertiary)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        OnyxCallout(OnyxChart.shortDate(hit.date), value: "\(Self.count(hit.point.v)) steps")
                    }
            }
        }
        .chartYScale(domain: 0...ChartScale.niceDomain(steps.map { Optional($0.v) } + [goal.map(Double.init)], zeroBased: true).1)
        .chartXSelection(value: $selected)
        .onyxScrollable(days: 28)
        .onyxChart(.body)
    }
}

// MARK: - D. Stress

/// The stress index over eight weeks — `StressSeries` on a chart (§U5.3).
///
/// ── WHY THE AXIS IS FIXED AT 10–90 AND NOT TIGHT TO THE DATA ────────────────
/// Every other chart on this screen plots a quantity whose interesting range is
/// wherever the readings happen to sit, so `Trend.domain` crops to them. This
/// one plots a SCALE: 50 is your normal by construction, the clamp is 10 and 90,
/// and the band words partition that range. Cropping to a fortnight that never
/// left 44–58 would draw the same picture as one that swung 20–80, and the
/// dotted rule at 50 would stop meaning "the middle".
///
/// ── AND WHY THE POINTS ARE COLOURED BY BAND ─────────────────────────────────
/// Redundantly with their height, deliberately: the band word is the thing a
/// reader acts on, and reading it off a y-position means holding five
/// thresholds in your head. Colour is the same fact said in the channel the eye
/// answers first. No legend — the y-axis IS the legend, and a five-chip key for
/// an encoding that repeats the axis is the legend trap `OnyxChartCard` grew a
/// `legend:` slot to survive.
struct StressSection: View {
    let days: [StressDay]

    /// Eight weeks — see `BodyTrendsView.readStress`.
    static let days = 56

    @State private var selected: Date?

    /// The readings, as the shared chart arithmetic wants them. An empty day is
    /// dropped, and `Trend.runs` then breaks the line across the hole rather
    /// than drawing through it.
    private var series: [TrendPoint] {
        days.compactMap { day in day.index.map { TrendPoint(d: day.d, v: $0) } }
    }

    private var latest: StressDay? { days.last { !$0.empty } }

    var body: some View {
        let series = series
        VStack(alignment: .leading, spacing: 8) {
            OnyxSectionHeader("Stress", .recover)
            OnyxChartCard(
                "Stress index", domain: .recover,
                headline: latest.flatMap { day in day.index.map { "\(Int($0)) \(day.band?.word ?? "")" } },
                caption: "50 is your own normal. Report-only — it moves no score."
            ) {
                if series.isEmpty {
                    OnyxChartEmpty("No stress readings yet — the index needs a fortnight of vitals behind it.")
                } else {
                    chart(series)
                }
            }
        }
    }

    private func chart(_ series: [TrendPoint]) -> some View {
        Chart {
            // ── THE RULE CARRIES NO LABEL ───────────────────────────────────
            // The goal rules on the charts above are labelled because their
            // value is a setting the reader chose and cannot otherwise see.
            // This one is at 50 on every chart forever, and the card's own
            // caption — one line higher, in secondary ink — already says "50 is
            // your own normal". A "normal" tag on the rule is that sentence
            // said twice (§3.6), and it clipped against the y-axis labels at
            // trailing and vanished off the plot's leading inset at leading.
            RuleMark(y: .value("Normal", 50))
                .lineStyle(Trend.dash)
                .foregroundStyle(Color.onyx.textTertiary)
            ForEach(Trend.runs(series), id: \.point.d) { run in
                if let date = OnyxChart.date(run.point.d) {
                    LineMark(
                        x: .value("Day", date, unit: .day),
                        y: .value("Stress", run.point.v),
                        series: .value("Run", run.run)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.onyx.accent(.recover))
                    PointMark(x: .value("Day", date, unit: .day), y: .value("Stress", run.point.v))
                        .symbolSize(18)
                        .foregroundStyle(Stress.band(run.point.v).tint)
                }
            }
            if let selected, let hit = Trend.nearest(series, to: selected) {
                RuleMark(x: .value("Day", hit.date, unit: .day))
                    .foregroundStyle(Color.onyx.textTertiary)
                    // `.fit(to: .chart)` on BOTH axes: a `.top` annotation with
                    // the vertical overflow unresolved is laid out above the
                    // plot and clipped away entirely (the same trap the
                    // composition tooltip hit).
                    .annotation(
                        position: .top, spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        callout(hit)
                    }
            }
        }
        // The reachable range, plus a hair so a 90 does not sit on the frame.
        .chartYScale(domain: 8...92)
        .chartXSelection(value: $selected)
        .onyxScrollable(days: 28)
        .onyxChart(.recover)
    }

    /// The reading, its word, and every term that answered — which is the whole
    /// breakdown sheet in the two lines a callout has room for.
    private func callout(_ hit: Trend.Hit) -> some View {
        let day = days.first { $0.d == hit.point.d }
        let band = day?.band ?? Stress.band(hit.point.v)
        let terms = StressTermKey.display.compactMap { key in
            day?.term(key).map { OnyxCallout.Line(key.title, signed($0)) }
        }
        return OnyxCallout(
            OnyxChart.shortDate(hit.date),
            lines: [OnyxCallout.Line(band.word, "\(Int(hit.point.v))", color: band.tint)] + terms,
            footnote: terms.count == StressTermKey.display.count
                ? nil
                : "\(terms.count) of 4 terms answered"
        )
    }

    private func signed(_ v: Double) -> String {
        "\(v > 0 ? "+" : v < 0 ? "−" : "")\(jsToFixed(abs(v), 1))"
    }
}
