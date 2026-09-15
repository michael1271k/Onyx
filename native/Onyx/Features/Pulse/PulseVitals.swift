import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// Eight readings, each once: five overnight and three from the ring.
///
/// ── WHY THIS STOPPED BEING EIGHT ROWS ───────────────────────────────────────
/// Wave 2.9 made these eight 44 pt `MetricRow`s, which was right about the
/// SHAPE — they are eight readings of one kind and a bordered box each was the
/// web app's answer — and wrong about the cost. Eight rows is 352 pt of a
/// screen that also carries a night, a body and four controls, and the vitals
/// are the part of it a reader SCANS rather than reads: the question is "is
/// anything off tonight", and the answer is the shape of eight deltas at once,
/// not eight sentences one under the other.
///
/// Three columns of 64 pt says the same eight facts in 192 pt. Each cell keeps
/// everything the row carried — the value, its unit, the delta against your own
/// fortnight, and the week behind it — because the compaction is of WHITESPACE,
/// not of content (§W11: Pulse fits in a screen and a half).
///
/// ── AND WHY IT BECOMES ROWS AGAIN AT AX5 ────────────────────────────────────
/// A third of a phone is 120 pt wide. "Respiratory" is one word that does not
/// fit in it at the largest accessibility size, and "14.2 br/min" beside it is
/// two more. The grid is a compaction that only exists while the type is small
/// enough for it to be one; past that the eight go back to being rows, which is
/// the escape `WeekVitalsRow` and `MetricRow` already take.
///
/// ── THE DELTA IS AGAINST A FORTNIGHT, NOT AGAINST YESTERDAY ─────────────────
/// `WidgetDerive.vitalBlock` reads the trailing fortnight EXCLUDING the date
/// itself. One night against one other night is noise; one night against your
/// own fortnight is the only version of "your HRV is down" worth printing.
struct VitalsGrid: View {
    let model: DayModel

    @Environment(\.dynamicTypeSize) private var typeSize

    private var window: DayModel.Window { model.window }

    /// One reading, in the form both layouts need. Built once so the grid and
    /// the row list cannot disagree about what a cell says.
    fileprivate struct Reading: Identifiable {
        let id: String
        let value: String?
        let unit: String
        let delta: Double?
        let decimals: Int
        let upIsGood: Bool
        let trend: [Double]
        let color: Color
    }

    /// ── STATIC, BECAUSE THE CHIP ROW NEEDS IT TOO ───────────────────
    /// `VitalsChipRow` draws the first two lines of each of these cells. It
    /// used to reach them by constructing a throwaway `VitalsGrid` and reading
    /// the instance property — which worked only while this fold happened not
    /// to touch the view's `@Environment`, and would have begun silently
    /// disagreeing with the grid beneath it the moment it did. It is a pure
    /// function of the window and always was.
    fileprivate static func readings(_ window: DayModel.Window) -> [Reading] {
        var out: [Reading] = VitalSpec.all.map { spec in
            let vital = spec.read(window.vitals)
            return Reading(
                id: spec.name,
                value: OnyxSnapshot.fixed(vital?.value, decimals: spec.decimals),
                unit: spec.unit,
                delta: vital?.delta,
                decimals: spec.decimals,
                upIsGood: spec.upIsGood,
                trend: vital?.trend?.map(\.v) ?? [],
                color: spec.color
            )
        }
        out.append(activity("Steps", window.steps, unit: "steps", grouped: true, color: OnyxDomain.body.accent))
        out.append(activity("Stand", window.standHours, unit: "h", grouped: false, color: OnyxDomain.body.at(0.5)))
        out.append(activity("Active", window.activeKcal, unit: "kcal", grouped: true, color: OnyxDomain.fuel.accent))
        return out
    }

    private var readings: [Reading] { Self.readings(window) }

    /// The three the ring reports. Same fortnight rule as the five above.
    ///
    /// Named "Stand" and "Active" rather than "Stand hours" and "Active
    /// energy": the unit sits in the cell beside the figure, and a two-word
    /// name in a 120 pt column wraps to a second line the cell has no room for.
    private static func activity(
        _ name: String, _ block: VitalBlock?, unit: String, grouped: Bool, color: Color
    ) -> Reading {
        Reading(
            id: name,
            // Grouped where the figure runs to four digits: "8430 steps" is a
            // number you have to count the digits of, and this cell exists to
            // be read at a glance.
            value: block?.value.map { grouped ? NutritionFormat.whole($0) : OnyxSnapshot.fixed($0, decimals: 0) ?? "—" },
            unit: unit,
            delta: block.flatMap { b in zip2(b.value, b.baseline).map { $0 - $1 } },
            decimals: 0,
            upIsGood: true,
            trend: block?.trend.map(\.v) ?? [],
            color: color
        )
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            ForEach(readings) { r in
                MetricRow(
                    name: r.id, value: r.value, unit: r.unit, delta: r.delta,
                    decimals: r.decimals, upIsGood: r.upIsGood, trend: r.trend, color: r.color
                )
            }
        } else {
            grid
                .listRowInsets(EdgeInsets(top: 0, leading: OnyxSpace.l, bottom: 0, trailing: OnyxSpace.l))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.s), count: 3),
            spacing: OnyxSpace.s
        ) {
            ForEach(readings) { VitalCell(reading: $0) }
        }
        .padding(OnyxSpace.m)
        .onyxGlass(.tile)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vitals")
    }
}

/// One cell of the grid: a name, the reading, its deviation and the week
/// behind it, in 64 pt.
///
/// Not shared with anything: the shape is only correct at a third of a screen
/// width, and the same view in a full-width context is a 64 pt box holding one
/// number.
private struct VitalCell: View {
    let reading: VitalsGrid.Reading

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(reading.id)
                .onyxMicro()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                // A number never wraps and never shrinks past 70 %: an "8,430"
                // scaled to nothing is a figure shown as a smudge.
                Text(reading.value ?? "—")
                    .onyxType(.secondary).fontWeight(.semibold).onyxNumeral()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.onyx.textPrimary)
                if !reading.unit.isEmpty {
                    Text(reading.unit)
                        .onyxType(.micro)
                        .lineLimit(1)
                        .foregroundStyle(Color.onyx.textTertiary)
                }
                Spacer(minLength: 0)
            }
            delta
            // 24 pt of trace, and the reason a cell is 64 pt rather than 40:
            // the delta says which way tonight went and the line says whether
            // that is a move or a wobble.
            Sparkline(points: reading.trend, color: reading.color)
                .frame(height: 24)
                .opacity(reading.trend.count > 1 ? 1 : 0)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.id), \(reading.value ?? "no reading") \(reading.unit)\(deltaSpoken)")
    }

    /// A reading with no baseline behind it has no delta — "0.0" would be a
    /// claim that it did not move, which is not the same as never having moved.
    /// The line is still occupied, so the cells beside it stay aligned.
    @ViewBuilder
    private var delta: some View {
        if let d = reading.delta, let text = OnyxSnapshot.signed(d, decimals: reading.decimals) {
            let moved = abs(d) > 0.0001
            let good = reading.upIsGood ? d > 0 : d < 0
            Text(text)
                .onyxType(.micro).fontWeight(.semibold).onyxNumeral()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(!moved ? Color.onyx.textSecondary : good ? Color.onyx.good : Color.onyx.danger)
        } else {
            Text(" ").onyxType(.micro).accessibilityHidden(true)
        }
    }

    private var deltaSpoken: String {
        guard let d = reading.delta, let text = OnyxSnapshot.signed(d, decimals: reading.decimals) else { return "" }
        return ", \(text) from baseline"
    }
}

/// Both or neither — the delta of a reading with no baseline behind it is not
/// zero, it is unknown, and a "0" chip claims the night did not move.
private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

// MARK: - The chip row

/// Nine readings in one 44 pt line, and the grid behind a tap.
///
/// ── WHY THE GRID STOPPED BEING ALWAYS-OPEN ──────────────────────────────────
/// The grid is 192 pt of permanently-open reference on a screen whose top half
/// is now the strip, the chips and three cards you actually answer. Nine cells
/// with sparklines is what you want when something is off; it is not what you
/// want every time you open the tab, and it was pushing the three questions
/// this screen ASKS below the fold — which is the whole complaint §W11 filed.
///
/// A chip says the same two facts a cell leads with — the reading and which way
/// it went — in a fifth of the height. The rest of the cell (the unit, the
/// fortnight trace) is what the grid is for, and the grid is one tap away.
///
/// ── AND WHY SLEEP IS THE FIRST CHIP ─────────────────────────────────────────
/// The night was a 168 pt tile of its own directly under the strip. It is the
/// same KIND of thing as the eight below it — an overnight reading you scan —
/// and it was the only one with a gauge, a stage column and a bank line drawn
/// permanently. Its chip leads the row because it is the reading the other
/// eight are context for, and it is the one chip that is a DOOR rather than a
/// disclosure: the arc, the four stages, the debt and the two flags the watch
/// cannot see all live in `SleepEditSheet` already, at the size they are
/// legible at. Tapping a measurement you cannot change opens the grid; tapping
/// the night opens the night.
struct VitalsChipRow: View {
    let model: DayModel
    @Binding var expanded: Bool
    /// `DayScreen` owns the sheet — see `StressLogCard`.
    let onSleep: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var night: SleepSessionRow? { model.night }

    private var readings: [VitalsGrid.Reading] { VitalsGrid.readings(model.window) }

    var body: some View {
        Group {
            // At an accessibility size a chip is most of a phone wide, so a
            // scroller of nine is nine screens of swiping to learn one fact.
            // One row that names the count and opens the list — which is what
            // `VitalsGrid` already becomes at that size.
            if typeSize.isAccessibilitySize { summaryRow } else { chips }
            if expanded { VitalsGrid(model: model) }
        }
    }

    // MARK: The row itself

    private var chips: some View {
        ScrollView(.horizontal) {
            // Eager, like the carousel: nine children cost nothing to realise
            // and an unrealised one is absent from the accessibility tree, so
            // VoiceOver could not reach the last four readings at all.
            HStack(spacing: OnyxSpace.s) {
                // The night is a DOOR and the grid does not contain it, so its
                // chip stands in both states.
                sleepChip
                // ── THE EIGHT LEAVE WHEN THE GRID ARRIVES ───────────────────
                // Open, the chips and the cells below them were the same eight
                // readings twice — §3.6's "no box that only repeats the box
                // above it", drawn as a scroller over a grid. A chip's whole
                // content is the cell's first two lines. So open, the row is
                // the night and the way back.
                if expanded {
                    hideChip
                } else {
                    ForEach(readings) { reading in chip(reading) }
                }
            }
            .padding(.horizontal, OnyxSpace.l)
        }
        .scrollIndicators(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// ── TWO ROWS, NOT ONE ───────────────────────────────────────────────────
    /// The first draft collapsed the whole row to a single "Vitals" disclosure,
    /// which took the SLEEP CHIP with it — and the sleep chip is the only door
    /// to the night on this screen since the tile left. At AX5 there was then no
    /// way to reach the arc, the stages, the bank or the two flags the watch
    /// cannot see, from the tab that owns them. A control that exists only above
    /// a type size is a control that does not exist.
    @ViewBuilder
    private var summaryRow: some View {
        PulseRow(
            symbol: "bed.double.fill",
            title: "Sleep",
            detail: [DayFormat.minutes(night?.durationMin), goalText].compactMap { $0 }.joined(separator: " · "),
            tint: Color.onyx.accent(.recover),
            action: onSleep
        )
        PulseRow(
            symbol: "waveform.path.ecg",
            title: "Vitals",
            detail: expanded ? "Hide" : "\(readings.count) readings",
            action: { withAnimation(OnyxMotion.counter) { expanded.toggle() } }
        )
    }

    /// The way back, in the shape of the chips it replaced — so the row does
    /// not change height when the grid opens and the eight disappear.
    private var hideChip: some View {
        Button { withAnimation(OnyxMotion.counter) { expanded = false } } label: {
            chipBody(
                name: "Vitals", value: "Hide", unit: "", delta: nil,
                deltaTint: Color.onyx.textSecondary,
                accent: Color.onyx.accent(.body), door: false
            )
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hide the full vitals")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: The night

    private var sleepChip: some View {
        Button(action: onSleep) {
            chipBody(
                name: "Sleep",
                value: DayFormat.minutes(night?.durationMin),
                unit: "",
                delta: goalText,
                deltaTint: goalMet ? Color.onyx.good : Color.onyx.danger,
                accent: Color.onyx.accent(.recover),
                door: true
            )
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep, \(spokenDuration)\(goalText.map { ", \($0)" } ?? "")")
        .accessibilityHint("Opens the night")
        .accessibilityAddTraits(.isButton)
    }

    /// What the chip says out loud.
    ///
    /// `DayFormat.minutes` prints an em dash for a night nobody recorded, and a
    /// reader hears an em dash as nothing at all — "Sleep," followed by silence.
    /// The dash stays on screen, where it is the app's word for "no reading"
    /// everywhere; the sentence says the words.
    private var spokenDuration: String {
        guard let minutes = night?.durationMin, minutes > 0 else { return "no reading" }
        return DayFormat.minutes(minutes)
    }

    /// "+22m" / "−1h 20m" / "goal met" — the rule the Sleep tile's goal chip
    /// followed until W4, without the two words the arc it sat under was
    /// already saying. This chip has no arc over it, so the sign and the
    /// magnitude are the whole reading.
    private var goalText: String? {
        guard let minutes = night?.durationMin, minutes > 0 else { return nil }
        let gap = minutes - Int((model.sleepGoalHours * 60).rounded())
        if abs(gap) <= 5 { return "goal met" }
        return "\(gap > 0 ? "+" : "−")\(DayFormat.minutes(abs(gap)))"
    }

    private var goalMet: Bool {
        guard let minutes = night?.durationMin, minutes > 0 else { return true }
        return minutes - Int((model.sleepGoalHours * 60).rounded()) >= -5
    }

    // MARK: The eight

    private func chip(_ reading: VitalsGrid.Reading) -> some View {
        Button { withAnimation(OnyxMotion.counter) { expanded.toggle() } } label: {
            chipBody(
                name: reading.id,
                value: reading.value ?? "—",
                unit: reading.unit,
                delta: OnyxSnapshot.signed(reading.delta, decimals: reading.decimals),
                deltaTint: deltaTint(reading),
                accent: reading.color,
                door: false
            )
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.96)
        .accessibilityElement(children: .ignore)
        // The DELTA is why a chip exists — "41 ms" alone does not say the night
        // went the wrong way — and `VitalCell` already speaks it. The hint has
        // one branch only: these eight are replaced by `hideChip` while the grid
        // is open, so a chip is never drawn in the expanded state.
        .accessibilityLabel(
            "\(reading.id), \(reading.value ?? "no reading") \(reading.unit)"
                + (OnyxSnapshot.signed(reading.delta, decimals: reading.decimals).map { ", \($0) from baseline" } ?? "")
        )
        .accessibilityHint("Shows the full vitals")
        .accessibilityAddTraits(.isButton)
    }

    /// A reading that did not move is neither good nor bad, and a reading with
    /// no baseline behind it has no delta at all — the same rule `VitalCell`
    /// states, because the chip and the cell are one fact at two sizes.
    private func deltaTint(_ reading: VitalsGrid.Reading) -> Color {
        guard let d = reading.delta, abs(d) > 0.0001 else { return Color.onyx.textSecondary }
        return (reading.upIsGood ? d > 0 : d < 0) ? Color.onyx.good : Color.onyx.danger
    }

    /// One chip. Fixed width, because a row of chips that each measure their
    /// own content is a row whose items move as the numbers change — and these
    /// numbers change every morning.
    private func chipBody(
        name: String, value: String, unit: String,
        delta: String?, deltaTint: Color, accent: Color, door: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                // 4 pt of the reading's own colour, which is what makes the row
                // scannable as nine DIFFERENT readings rather than nine boxes.
                Circle().fill(accent).frame(width: 4, height: 4)
                Text(name)
                    .onyxMicro()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if door {
                    Image(systemName: "chevron.right")
                        .onyxType(.micro).fontWeight(.bold)
                        .foregroundStyle(Color.onyx.textTertiary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .onyxType(.secondary).fontWeight(.semibold).onyxNumeral()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.onyx.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .onyxType(.micro)
                        .lineLimit(1)
                        .foregroundStyle(Color.onyx.textTertiary)
                }
                Spacer(minLength: 0)
            }
            Text(delta ?? " ")
                .onyxType(.micro).fontWeight(.semibold).onyxNumeral()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(delta == nil ? Color.onyx.textTertiary : deltaTint)
        }
        .padding(.horizontal, OnyxSpace.s)
        .padding(.vertical, OnyxSpace.s)
        .frame(width: 104, alignment: .topLeading)
        .onyxGlass(.row)
        .contentShape(.rect)
    }
}
