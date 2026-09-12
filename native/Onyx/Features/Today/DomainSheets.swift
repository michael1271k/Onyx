import SwiftUI
import OnyxCore
import OnyxData
import WidgetKit
import OnyxUI

/// The sheet behind a tile.
///
/// ── THE TILE AT LARGE IS THE SHEET, EXCEPT WHERE IT IS THE SHEET TWICE ───────
/// Every widget family has a Large face that is the tile's own question answered
/// in full, so most domains lead with it rather than with a second implementation
/// of the same reading, and add only what the Large face cannot hold.
///
/// Two did not work that way. §3.6 forbids "a box that only repeats the box
/// above it", and Sleep and Vitals were doing exactly that:
///
///   · **Sleep** drew `SleepLargeFace` — arc, stage bar, four stage rows, seven
///     nights — and then a SECOND list of the same four stages with the same
///     four durations, six points lower down the same scroll view.
///   · **Vitals** drew `VitalsPanelFace` at Large, which lists all five overnight
///     readings, and then the Medium `recovery` face (HRV + resting HR) and the
///     Medium `respiration` face (SpO₂ + respiratory) — so three of the five
///     readings appeared twice and two appeared three times, in three different
///     box sizes, at 8 pt.
///
/// Three more joined them in the dashboard-polish wave — Steps, Muscle focus
/// and Records — for a different reason. Theirs are not the same answer twice;
/// their Large faces answer a DIFFERENT question from the one the sheet is
/// opened to ask, and `TileSheets.swift` carries the argument for each. Train
/// is a fourth case and is not here at all: a logged day opens that SESSION's
/// own page, which `TodayTabView.open` routes to directly.
///
/// Both are now purpose-built for the sheet rather than assembled out of widget
/// faces: one arc, one list, app type throughout. A widget face is a GLANCE at
/// a fixed size with no Dynamic Type; a sheet is a page you read. Reusing the
/// first as the second is what made the sheets look like a web dashboard.
struct DomainSheet: View {
    let id: WidgetId
    let entry: OnyxTileEntry
    /// The week's sets against the week's targets — the one thing on any of
    /// these sheets that the widget payload does not carry, because targets are
    /// a (plan, phase) row and the payload is a day.
    var muscleFocus: MuscleFocusSummary?
    let onStartWorkout: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var s: OnyxSnapshot? { entry.snapshot }

    var body: some View {
        NavigationStack {
            Group {
                switch id {
                case .sleep: SleepSheetBody(snapshot: s)
                case .vitals: VitalsSheetBody(snapshot: s)
                // Three more that are not their own Large face — see the header
                // of `TileSheets.swift` for what each one was drawing instead.
                case .steps: StepsSheetBody(snapshot: s)
                case .muscle: MuscleFocusSheetBody(focus: muscleFocus ?? MuscleFocusSummary())
                case .pr: RecordsSheetBody(snapshot: s)
                default: stack
                }
            }
            .onyxScreen(id.domain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        // Without this a drag on the Vitals list GROWS the sheet to large
        // instead of scrolling it — which is the whole interaction of an
        // eight-row list in a half sheet.
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .presentationBackground(GlassLevel.sheet.material)
    }

    /// What the SHEET is called, which is not always what the TILE is called.
    ///
    /// A widget's title is written for a tile: "Latest PR" is exactly right on a
    /// 158 pt square showing one record, and exactly wrong at the top of a page
    /// listing every record ever set. The same for "Muscle Focus", which the
    /// sheet answers over a whole week. Everything else keeps the catalogue's
    /// name — a sheet that renames its tile is a sheet you have to work out you
    /// opened from it.
    private var title: String {
        switch id {
        case .pr: "Records"
        case .muscle: "Weekly Muscle Focus"
        default: id.title
        }
    }

    /// The Large face, plus what it cannot hold. Every domain but the two above.
    private var stack: some View {
        ScrollView {
            VStack(spacing: OnyxSpace.m) {
                // Not every widget HAS a large. W12's Trajectory tops out at
                // medium on purpose (a weight curve is one series, and a taller
                // plot of one series is the stretched medium `layout.ts` warns
                // about) — asking for a large draws the medium body in a
                // 354 pt box, which is that warning made real.
                face(id, focus: nil, family: Dashboard.sizesFor([id]).contains(.l) ? .systemLarge : .systemMedium)
                extras
            }
            .padding(OnyxSpace.l)
        }
    }

    @ViewBuilder
    private var extras: some View {
        switch id {
        // `.recovery` has no extras. `WellbeingFace` at Large already draws the
        // five sub-scores as labelled rails AND the daily score, and the list
        // that used to sit under it repeated all six — the same defect Sleep
        // and Vitals were rewritten to remove, three inches lower.
        case .fuel:
            face(.fuel, focus: .fuel(.macros))
            face(.water, focus: .fuel(.water), family: .systemMedium)
        case .train: startButton
        // The scale under the composition, not the composition twice: since
        // W12 the tile's own face IS the composition strip, and the extra was
        // the same face a second time.
        case .body: face(.body, focus: .body(.weight), family: .systemMedium)
        // The two halves of "is the block working" that the tapped tile does
        // not draw. Medium each — neither has a large body.
        case .trajectory: face(.deficit, focus: .progress(.deficit), family: .systemMedium)
        case .deficit: face(.trajectory, focus: .progress(.trajectory), family: .systemMedium)
        default: EmptyView()
        }
    }

    /// A widget face inside the sheet, at Large unless told otherwise.
    @ViewBuilder
    private func face(_ id: WidgetId, focus: OnyxFocus?, family: WidgetFamily = .systemLarge) -> some View {
        let e = OnyxTileEntry(date: entry.date, snapshot: entry.snapshot, focus: focus)
        Group {
            switch focus {
            case .fuel(let f): FuelView(entry: e, focus: f)
            case .body(let f): BodyView(entry: e, focus: f)
            case .vitals(let f): VitalsView(entry: e, focus: f)
            case .training(let f): TrainingView(entry: e, focus: f)
            case .progress(let f): ProgressTileView(entry: e, focus: f)
            case .lock, .none: OnyxTile.face(id, entry: e)
            }
        }
        .environment(\.onyxTileFamily, family)
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity)
        .aspectRatio(family == .systemLarge ? 338 / 354 : 338 / 158, contentMode: .fit)
        .onyxGlass(.tile)
    }

    @ViewBuilder
    private var startButton: some View {
        if let w = s?.workout, !w.isRestDay, !w.logged {
            Button { dismiss(); onStartWorkout() } label: {
                Label("Start \(w.label)", systemImage: "play.fill")
                    .onyxType(.body).fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, OnyxSpace.s)
                    .foregroundStyle(Color.onyx.base)
                    .background(OnyxDomain.train.ramp, in: RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous))
            }
            .buttonStyle(OnyxPressStyle())
        }
    }
}

// MARK: - Sleep

/// One night, said once.
///
/// ── WHY THE ARC IS THE ONLY GAUGE ON THIS SHEET ──────────────────────────────
/// The arc already answers both questions a night raises: its SWEEP is duration
/// against the goal, and its FILL is the stage breakdown. The old sheet then
/// drew a full-width `DepthBar` of the same stages under it and listed the same
/// four durations twice — three renderings of one four-number fact. What the arc
/// genuinely cannot say is the SHARE each stage took and how last night compares
/// to the six before it, so those are the only two things beneath it.
private struct SleepSheetBody: View {
    let snapshot: OnyxSnapshot?

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var arcSize: CGFloat = 180
    private var arcWidth: CGFloat { min(arcSize, 300) }

    private var sleep: OnyxSnapshot.Sleep? { snapshot?.sleep }
    private var segments: [(OnyxSleepStage, Int)] { sleepSegments(snapshot) }
    private var staged: Int { segments.reduce(0) { $0 + $1.1 } }

    /// Seven nights on the calendar rather than seven readings in a row: a week
    /// with four logged nights must draw four bars and three gaps, not four bars
    /// filling the width. `paddedWindow` is that function (§2.2).
    private var nights: [DatedValue] {
        WidgetDerive.paddedWindow(
            (sleep?.trend ?? []).map { TrendPoint(d: $0.d, v: $0.v) },
            endingOn: snapshot?.date ?? LogicalDay.today(),
            limit: 7
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: OnyxSpace.l) {
                arc
                stageGrid
                sevenNights
            }
            .padding(OnyxSpace.l)
        }
    }

    private var arc: some View {
        VStack(spacing: OnyxSpace.s) {
            DepthArc(segments: segments, minutes: sleep?.minutes, goalMin: sleep?.goalMin, lineWidth: 12)
                // §5.1 asks for 180 pt of GAUGE, and `DepthArc` sizes itself
                // `min(width, height / 0.72)` — so the height has to be 0.72 of
                // the width or the frame silently draws a smaller arc than it
                // reserves room for.
                //
                // And it scales: the arc sets its type off its own diameter, so
                // a fixed frame makes "7h17m" — the only place this sheet says
                // how long the night was — the SMALLEST text on the screen at
                // AX5. Capped, because past 300 pt it is wider than the phone.
                .frame(width: arcWidth, height: arcWidth * 0.72)
            if let window = sleepWindowText(snapshot) {
                Text(window)
                    .onyxType(.secondary).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
            }
            goalChip
        }
        .frame(maxWidth: .infinity)
        .padding(OnyxSpace.m)
        .onyxGlass(.tile)
    }

    /// "+22m vs goal" — signed, because under and over are different nights.
    @ViewBuilder
    private var goalChip: some View {
        if let minutes = sleep?.minutes, minutes > 0 {
            let goal = sleep?.goalMin ?? 480
            let gap = minutes - goal
            let met = gap >= -5
            // `Format.sleep`, not the arc's `formatSleep`: 43 minutes short is
            // "43m", not "0h43m", and the stage grid below already says it that
            // way. Two duration formats on one sheet is one too many.
            let text = abs(gap) <= 5 ? "goal met" : "\(gap > 0 ? "+" : "−")\(Format.sleep(Double(abs(gap)))) vs goal"
            Text(text)
                .onyxType(.caption).fontWeight(.semibold)
                .foregroundStyle(met ? Color.onyx.good : Color.onyx.danger)
                .padding(.horizontal, OnyxSpace.s)
                .padding(.vertical, OnyxSpace.xs)
                .background(Capsule().fill((met ? Color.onyx.good : Color.onyx.danger).opacity(0.14)))
        }
    }

    /// The 2×2 the arc cannot draw: each stage's SHARE of the night, which is the
    /// number you compare between nights, next to the minutes that produced it.
    private var stageGrid: some View {
        // Two columns until the type will not take two: a stage row is four
        // pieces of text on one line, and at AX5 that is one column or it is
        // truncation.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.m), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: OnyxSpace.s) {
            ForEach(OnyxSleepStage.allCases, id: \.self) { stage in
                StageCell(
                    stage: stage,
                    minutes: segments.first(where: { $0.0 == stage })?.1,
                    share: share(segments.first(where: { $0.0 == stage })?.1)
                )
            }
        }
        .padding(.horizontal, OnyxSpace.m)
        .onyxGlass(.tile)
    }

    /// A stage with no reading has no share — 0 % would claim the watch measured
    /// none of it.
    func share(_ minutes: Int?) -> String {
        guard let minutes, staged > 0 else { return "—" }
        return "\(Int((Double(minutes) / Double(staged) * 100).rounded()))%"
    }

    private var sevenNights: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            Text("SEVEN NIGHTS").onyxMicro()
            NightBars(nights: nights, goalMin: sleep?.goalMin.map(Double.init) ?? 480)
                .frame(height: 96)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OnyxSpace.m)
        .onyxGlass(.tile)
    }
}

/// One stage: a dot, a name, its share of the night and its minutes.
///
/// `ViewThatFits` rather than a Dynamic Type check: the row is four pieces of
/// text and whether they fit is a question about THIS device at THIS type size
/// in THIS column width, which is exactly the question the layout system is
/// already answering. A hand-written breakpoint gets it wrong on the iPhone it
/// was not written on. §3.1 allows a taller row for two lines of content.
/// Internal since Wave 2.9: the Pulse tab's sleep tile is the same 2×2 grid of
/// the same four stages, and two copies would drift the first time either is
/// nudged.
struct StageCell: View {
    let stage: OnyxSleepStage
    let minutes: Int?
    let share: String
    /// Draw the narrowest layout unconditionally.
    ///
    /// ── WHY THIS IS NOT LEFT TO `ViewThatFits` ──────────────────────────────
    /// A grid of four gives every cell the same width, but not the same
    /// CONTENT: "Awake · 5% · 20m" fits a line that "Core · 56% · 3h 55m" does
    /// not. Left to itself each cell picks its own best layout and the row
    /// comes out with three stacked cells and one two-line one sitting at a
    /// different height — which reads as a rendering fault rather than as a
    /// fit. A row of four is one shape, chosen by the caller that knows it is a
    /// row of four.
    var compact = false

    private var dot: some View { Circle().fill(stage.color).frame(width: 8, height: 8) }

    /// ── WHY EVERY LINE HERE IS `lineLimit(1)` ───────────────────────────────
    /// `ViewThatFits` chooses by asking each candidate whether it fits, and a
    /// `Text` that is allowed to wrap always answers yes — it just gets taller.
    /// Without the limit the widest layout "fits" a quarter-width cell by
    /// breaking "1h 15m" across two lines, which is both the wrong layout and a
    /// duration rendered as two numbers. The limit is what makes the fallbacks
    /// below reachable.
    private var name: some View {
        Text(stage.title).onyxType(.secondary).lineLimit(1).foregroundStyle(Color.onyx.textPrimary)
    }
    private var percent: some View {
        Text(share).onyxType(.caption).onyxNumeral().lineLimit(1).foregroundStyle(Color.onyx.textTertiary)
    }
    /// `Format.sleep(0)` answers "—", which is what it also says for a stage
    /// the watch never reported. A measured zero is a different fact from an
    /// absent one, and this row already draws "0%" beside it.
    private var durationText: String {
        minutes == 0 ? "0m" : Format.sleep(minutes.map(Double.init))
    }

    private var duration: some View {
        Text(durationText)
            .onyxType(.secondary).onyxNumeral().lineLimit(1).foregroundStyle(Color.onyx.textSecondary)
    }

    /// Three layouts, widest first: one line, two, then three.
    ///
    /// The third is what a QUARTER of a tile can hold — the Pulse sleep tile
    /// draws these four across rather than two-by-two since §W11, and at 85 pt
    /// a share and a duration do not share a line. The duration leads the
    /// numbers there because it is the reading; the share is the context.
    var body: some View {
        Group {
            if compact {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: OnyxSpace.s) {
                        dot; name
                        Spacer(minLength: OnyxSpace.s)
                        percent; duration
                    }
                    VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                        HStack(spacing: OnyxSpace.s) { dot; name }
                        HStack(spacing: OnyxSpace.s) { percent; duration }
                    }
                    stacked
                }
            }
        }
        .frame(minHeight: compact ? 0 : 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stage.title), \(share), \(durationText)")
    }

    /// What a quarter of a tile can hold. The duration leads the numbers
    /// because it is the reading; the share is the context for it.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: OnyxSpace.xs) { dot; name }
            duration
            percent
        }
    }
}

/// Seven dated buckets, drawn as seven slots.
///
/// ── WHY NOT `BarChart` ───────────────────────────────────────────────────────
/// `BarChart` takes `[Point]`, whose `v` is non-optional — it CANNOT represent a
/// night that was not recorded, which is the whole point of the padded window.
/// It also labels its bars at 7 pt, which is right for a widget and below the
/// app's floor of 11 (§3.3). A missing night is drawn as an empty track: present,
/// dated, and visibly not a zero.
private struct NightBars: View {
    let nights: [DatedValue]
    let goalMin: Double

    private var peak: Double { max(nights.compactMap(\.value).max() ?? 0, goalMin, 1) }

    /// The most recent night that was actually RECORDED — not the last bucket.
    /// Before tonight's sync the last bucket is empty, and keying the highlight
    /// to it left every real night dimmed and nothing lit at all.
    private var newestRecorded: String? {
        nights.last { $0.value != nil }?.date
    }

    var body: some View {
        VStack(spacing: OnyxSpace.xs) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: OnyxSpace.s) {
                        ForEach(nights, id: \.date) { night in
                            // Every slot gets a full-height RAIL and a bar is
                            // drawn on top of it. A missing night is the bare
                            // rail: unmistakably an empty slot rather than —
                            // as filling the slot height made it — the tallest
                            // column on the chart.
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.onyx.hairline)
                                if let value = night.value {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(OnyxDomain.recover.accent
                                            .opacity(night.date == newestRecorded ? 1 : 0.5))
                                        .frame(height: max(2, geo.size.height * value / peak))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Path { p in
                        let y = geo.size.height * (1 - goalMin / peak)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.onyx.textSecondary.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            HStack(spacing: OnyxSpace.s) {
                ForEach(nights, id: \.date) { night in
                    Text(OnyxSnapshot.weekdayInitial(night.date))
                        .onyxType(.micro)
                        .foregroundStyle(night.value == nil ? Color.onyx.textTertiary : Color.onyx.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seven nights. \(nights.filter { $0.value != nil }.count) recorded.")
    }
}

// MARK: - Vitals

/// Five overnight readings and three activity totals, each once.
///
/// A `List`, not a scroll view of cards (§3.6). These are eight readings of the
/// same kind — a value, a unit, how far it sits from your own normal, and the
/// week behind it — and eight bordered boxes is the web app's way of saying
/// "rows".
private struct VitalsSheetBody: View {
    let snapshot: OnyxSnapshot?

    var body: some View {
        List {
            Section("Overnight") {
                ForEach(VitalSpec.all, id: \.name) { spec in
                    MetricRow(
                        name: spec.name,
                        value: OnyxSnapshot.fixed(spec.read(snapshot?.vitals)?.value, decimals: spec.decimals),
                        unit: spec.unit,
                        delta: spec.read(snapshot?.vitals)?.delta,
                        decimals: spec.decimals,
                        upIsGood: spec.upIsGood,
                        trend: spec.read(snapshot?.vitals)?.trend?.map(\.v) ?? [],
                        color: spec.color
                    )
                }
            }
            Section("Activity") {
                MetricRow(
                    name: "Steps",
                    value: snapshot?.steps.count.map { "\($0)" },
                    unit: snapshot?.steps.goal.map { "of \($0)" } ?? "",
                    delta: nil, decimals: 0, upIsGood: true,
                    trend: snapshot?.steps.trend?.map(\.v) ?? [],
                    color: OnyxDomain.body.accent
                )
                MetricRow(
                    name: "Active energy",
                    value: snapshot?.steps.activeKcal.map { "\(Int($0.rounded()))" },
                    unit: "kcal",
                    delta: nil, decimals: 0, upIsGood: true,
                    trend: [], color: OnyxDomain.fuel.accent
                )
                if let distance = snapshot?.steps.distanceM {
                    MetricRow(
                        name: "Distance",
                        value: String(format: "%.1f", distance / 1000), unit: "km",
                        delta: nil, decimals: 1, upIsGood: true,
                        trend: [], color: OnyxDomain.body.accent
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

/// One reading: name · value · unit · delta · the week behind it.
///
/// The 44 pt row of §3.1, and the only row shape the sheets use — a metric is a
/// metric whether it is measured in ms or in steps.
/// Internal since Wave 2.9 — the Pulse tab's vitals list is these rows.
struct MetricRow: View {
    let name: String
    let value: String?
    let unit: String
    let delta: Double?
    let decimals: Int
    let upIsGood: Bool
    let trend: [Double]
    let color: Color

    @Environment(\.dynamicTypeSize) private var typeSize

    private var label: some View {
        Text(name).onyxType(.body).foregroundStyle(Color.onyx.textPrimary)
    }

    /// The sparkline is the first thing to go at accessibility sizes: it is
    /// 40 pt of decoration beside a number that has to grow to 60.
    @ViewBuilder
    private var spark: some View {
        if !typeSize.isAccessibilitySize, trend.count > 1 {
            Sparkline(points: trend, color: color)
                .frame(width: 40, height: 16)
                .accessibilityHidden(true)
        }
    }

    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value ?? "—")
                .onyxType(.body).fontWeight(.semibold).onyxNumeral()
                // A number NEVER wraps. At AX5 an unlimited "52" broke across
                // two lines and read as a 5 and a 2.
                .lineLimit(1)
                .foregroundStyle(Color.onyx.textPrimary)
            if !unit.isEmpty {
                Text(unit)
                    .onyxType(.caption)
                    .lineLimit(1)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        // One line while one line fits; a name over its reading when it does
        // not. Same rule as `StageCell`, same reason: the layout system knows
        // whether it fits and a hand-written type-size breakpoint does not.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: OnyxSpace.m) {
                label
                Spacer(minLength: OnyxSpace.s)
                spark
                deltaChip
                reading
            }
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                label
                HStack(spacing: OnyxSpace.s) {
                    deltaChip
                    Spacer(minLength: 0)
                    reading
                }
            }
        }
        // 44 pt and not a point more (§3.1). A `List` row already guarantees the
        // minimum; what it does NOT guarantee is the maximum, and the default
        // insets on top of a fixed minHeight are what turned eight readings into
        // a screen and a half of scrolling.
        .listRowInsets(EdgeInsets(top: OnyxSpace.s, leading: OnyxSpace.l, bottom: OnyxSpace.s, trailing: OnyxSpace.l))
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.onyx.hairline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(value ?? "no reading") \(unit)\(deltaSpoken)")
    }

    /// `children: .combine` under an explicit label drops the chip, and the
    /// deviation from your own normal is the entire reason this row exists.
    private var deltaSpoken: String {
        guard let delta, let text = OnyxSnapshot.signed(delta, decimals: decimals) else { return "" }
        return ", \(text) from baseline"
    }

    /// A reading with no baseline behind it has no delta — "0.0" would be a
    /// claim that it did not move, which is not the same as never having moved.
    @ViewBuilder
    private var deltaChip: some View {
        if let delta, let text = OnyxSnapshot.signed(delta, decimals: decimals) {
            let moved = abs(delta) > 0.0001
            let good = upIsGood ? delta > 0 : delta < 0
            Text(text)
                .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                .foregroundStyle(!moved ? Color.onyx.textSecondary : good ? Color.onyx.good : Color.onyx.danger)
        }
    }
}

/// What is inside one stack, and the three things you can do to it.
///
/// The tile can say which face is up; it cannot show an ORDER, because only one
/// face is on screen at a time. So the tile keeps the glance and the sheet takes
/// the editing — a `List` with `onMove`, exactly as Edit Stack does on the Home
/// Screen. Unstack gives a face its own tile; remove sends it to the tray.
struct StackEditSheet: View {
    let slotId: String
    @Bindable var model: TodayModel
    @Environment(\.dismiss) private var dismiss

    private var slot: StackSlot? { Dashboard.slot(model.layout, at: slotId) }

    var body: some View {
        NavigationStack {
            List {
                if let slot {
                    ForEach(Array(slot.items.enumerated()), id: \.offset) { index, id in
                        Label(id.title, systemImage: id.symbol)
                            .foregroundStyle(Color.onyx.textPrimary)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { model.removeFace(slotId, index: index) } label: { Label("Remove", systemImage: "minus.circle") }
                                Button { model.unstack(slotId, index: index) } label: { Label("Unstack", systemImage: "rectangle.stack.badge.minus") }
                                    .tint(id.domain.accent)
                            }
                    }
                    .onMove { from, to in
                        guard let f = from.first else { return }
                        model.reorderFace(slotId, from: f, to: to > f ? to - 1 : to)
                    }
                } else {
                    Text("This stack is a single tile now.").foregroundStyle(Color.onyx.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .onyxScreen(.train)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(GlassLevel.sheet.material)
        .onChange(of: slot?.items.count) { _, n in if (n ?? 0) < 2 { dismiss() } }
    }
}
