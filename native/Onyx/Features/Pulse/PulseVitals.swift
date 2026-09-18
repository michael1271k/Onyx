import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// VITALS — one lead and eight sidekicks.
//
// ── WHAT W2 CHANGED, AND WHY ────────────────────────────────────────────────
// This was `VitalsChipRow`: nine 104 pt chips in a `ScrollView(.horizontal)` —
// about 1,010 pt of content in a 375 pt window — with the grid behind a
// disclosure under it. Two things were wrong with it. Eight of the nine
// readings were reachable only by swiping a row that gives no sign it can be
// swiped, and the one reading that matters most on a recovery screen, the
// night, was a 104 pt box with the same weight as Stand hours.
//
// The block now has a HERO and eight SIDEKICKS. The hero is full width and the
// sidekicks are the grid this file already drew; nothing is behind a swipe and
// nothing is behind a disclosure. Sleep holds the hero slot, because it is the
// reading the other eight are context for — and loses it to a vital that has
// gone far enough wrong to be read first (`VitalHero`, `OnyxCore`).
// ─────────────────────────────────────────────────────────────────────────────

/// The whole block: the lead, then the grid.
///
/// One view rather than two rows in `DayScreen` because the two halves are a
/// SWAP — a promoted vital leaves the grid and Sleep takes its cell — and a
/// swap split across two call sites is two places that must agree about which
/// eight are drawn.
struct VitalsSection: View {
    let model: DayModel
    /// `DayScreen` owns the sheet — see `PulseSquareGrid`.
    let onSleep: () -> Void

    private var window: DayModel.Window { model.window }

    /// Both folds happen ONCE, here, and are handed down.
    ///
    /// `hero(_:)` is six `Readiness.zSignal` passes over 49 points each and
    /// `readings(_:)` is eight formats; as computed properties they ran two and
    /// three times per body evaluation, which is a cost SwiftUI pays again on
    /// every scroll tick that re-realises this row.
    var body: some View {
        let all = VitalsGrid.readings(window)
        // A promoted id the readings no longer carry cannot happen while both
        // fold the same window — and resolves to the night if it ever does,
        // rather than to a blank hero.
        let promoted: VitalsGrid.Reading? = {
            guard case .vital(let id) = VitalsGrid.hero(window) else { return nil }
            return all.first { $0.id == id }
        }()
        return Group {
            if let promoted {
                VitalHeroCell(reading: promoted).plainRow()
            } else {
                SleepHeroCell(model: model, action: onSleep).plainRow()
            }
            VitalsGrid(readings: sidekicks(all, promoted: promoted)).plainRow()
        }
    }

    /// Always eight, whoever leads: the five overnight readings and the three
    /// from the ring, with the promoted one replaced IN PLACE by the night.
    ///
    /// In place rather than appended, so the grid does not reshuffle on the
    /// morning a vital is promoted — the cell you learned the position of keeps
    /// its position, and the one that left is the one now drawn above it.
    private func sidekicks(
        _ all: [VitalsGrid.Reading], promoted: VitalsGrid.Reading?
    ) -> [VitalsGrid.Reading] {
        guard let promoted, let index = all.firstIndex(where: { $0.id == promoted.id }) else { return all }
        var out = all
        out[index] = sleepReading
        return out
    }

    /// The night as a grid cell. It keeps its door — the sheet is the only way
    /// to the arc, the stages and the two flags the watch cannot record, and a
    /// control that exists only while Sleep happens to be the hero is a control
    /// that does not exist.
    private var sleepReading: VitalsGrid.Reading {
        let minutes = model.night.flatMap { $0.durationMin > 0 ? $0.durationMin : nil }
        let goal = Int((model.sleepGoalHours * 60).rounded())
        let gap = minutes.map { $0 - goal }
        return VitalsGrid.Reading(
            id: "Sleep",
            value: minutes.map { DayFormat.minutes($0) },
            unit: "",
            delta: nil,
            decimals: 0,
            upIsGood: true,
            // The same seven days every other cell's trace covers, out of the
            // 49 the hero rule reads.
            trend: window.series.sleepMinutes.suffix(7).compactMap { $0 },
            color: Color.onyx.accent(.recover),
            detail: gap.map { abs($0) <= 5 ? "goal met" : "\($0 > 0 ? "+" : "−")\(DayFormat.minutes(abs($0)))" },
            detailGood: (gap ?? 0) >= -5,
            action: onSleep
        )
    }
}

/// Eight readings, each once: five overnight and three from the ring.
///
/// ── WHY THIS IS A GRID AND NOT EIGHT ROWS ───────────────────────────────────
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
/// It is deliberately NOT the 49-day z the hero rule ranks by: a z is a verdict
/// about a WEEK and this is a reading about a NIGHT, and printing the verdict in
/// the cell would make the two disagree in public every time the week caught up.
struct VitalsGrid: View {
    fileprivate let readings: [Reading]

    @Environment(\.dynamicTypeSize) private var typeSize

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
        /// A pre-formatted stand-in for the delta line, for a reading whose
        /// deviation is not a number in its own units — the night, whose
        /// comparison is against a GOAL and reads "goal met".
        var detail: String? = nil
        var detailGood = true
        /// Non-nil makes the cell a door. Only the night has one: the other
        /// eight are measurements with nothing behind them to open.
        var action: (() -> Void)? = nil
    }

    /// ── STATIC, BECAUSE THE SECTION AROUND IT NEEDS IT TOO ──────────────────
    /// `VitalsSection` folds the same eight to find the promoted one and to
    /// swap the night into its place. It used to be reached by constructing a
    /// throwaway `VitalsGrid` and reading the instance property — which worked
    /// only while this fold happened not to touch the view's `@Environment`,
    /// and would have begun silently disagreeing with the grid beneath it the
    /// moment it did. It is a pure function of the window and always was.
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

    /// Who leads the block (`VitalHero`, A1).
    ///
    /// ── WHY THE RULE IS CALLED FROM HERE AND NOT FROM `DayModel` ────────────
    /// The candidates are `VitalSpec.all`, in `VitalSpec.all`'s order — that
    /// order IS the tie-break, so building the list anywhere else would mean
    /// two files had to agree about it. `VitalSpec` lives in `OnyxUI` and the
    /// model deliberately does not import the design system, so the model
    /// carries the SERIES and this carries the ORDER. Six 49-point folds over
    /// arrays already in memory; the reading path is `DayModel.readWindow`.
    ///
    /// ── AND WHY THE THREE RING READINGS ARE NOT CANDIDATES ──────────────────
    /// Steps, Stand and Active are activity, not vitals: a quiet Sunday is a
    /// step count two SDs down and is not a reason to lead a recovery screen
    /// with it. The five the watch takes overnight are the ones that mean
    /// something went wrong while you were not doing anything.
    fileprivate static func hero(_ window: DayModel.Window) -> HeroSlot {
        let series = window.series
        let bySpec: [String: [Double?]] = [
            VitalSpec.hrv.name: series.hrv,
            VitalSpec.restingBpm.name: series.restingBpm,
            VitalSpec.wristTemp.name: series.wristTemp,
            VitalSpec.bloodOxygen.name: series.bloodOxygen,
            VitalSpec.respiratoryRate.name: series.respiratory,
        ]
        let candidates = VitalSpec.all.compactMap { spec -> VitalReading? in
            guard let values = bySpec[spec.name] else { return nil }
            // `log` for HRV alone, exactly as `Readiness.signals` does it: SDNN
            // is log-normal and its z is taken on the ln. One series may not be
            // read one way by the battery and another way by this screen.
            return VitalHero.reading(
                id: spec.name, upIsGood: spec.upIsGood,
                log: spec.name == VitalSpec.hrv.name, series: values
            )
        }
        return VitalHero.promote(
            candidates,
            sleep: VitalHero.reading(id: "Sleep", upIsGood: true, series: series.sleepMinutes)
        )
    }

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
                // The night keeps its door in the row layout too. A `MetricRow`
                // is a measurement and has no tap; `PulseRow` is this screen's
                // word for "a reading you can open", and it is the only reason
                // the arc and the two flags are reachable at AX5 at all.
                if let action = r.action {
                    PulseRow(
                        symbol: "bed.double.fill",
                        title: r.id,
                        detail: [r.value, r.detail].compactMap { $0 }.joined(separator: " · "),
                        tint: r.color,
                        action: action
                    )
                } else {
                    MetricRow(
                        name: r.id, value: r.value, unit: r.unit, delta: r.delta,
                        decimals: r.decimals, upIsGood: r.upIsGood, trend: r.trend, color: r.color
                    )
                }
            }
        } else {
            grid
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
/// number — which is what `VitalHeroCell` exists to be instead.
private struct VitalCell: View {
    let reading: VitalsGrid.Reading

    var body: some View {
        if let action = reading.action {
            Button(action: action) { face }
                .buttonStyle(.plain)
                .onyxPress(scale: 0.96)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel)
                .accessibilityHint("Opens the night")
                .accessibilityAddTraits(.isButton)
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel)
        }
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: 2) {
            // The chevron sits against the NAME, not against the cell's
            // trailing edge: a third of a phone is 120 pt, and a chevron pushed
            // to the far edge of one cell lands 8 pt from the next cell's label
            // and reads as belonging to it.
            HStack(spacing: 3) {
                Text(reading.id)
                    .onyxMicro()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if reading.action != nil {
                    Image(systemName: "chevron.right")
                        .onyxType(.micro).fontWeight(.bold)
                        .foregroundStyle(Color.onyx.textTertiary)
                }
                Spacer(minLength: 0)
            }
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
        .contentShape(.rect)
    }

    /// A reading with no baseline behind it has no delta — "0.0" would be a
    /// claim that it did not move, which is not the same as never having moved.
    /// The line is still occupied, so the cells beside it stay aligned.
    @ViewBuilder
    private var delta: some View {
        if let detail = reading.detail {
            Text(detail)
                .onyxType(.micro).fontWeight(.semibold).onyxNumeral()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(reading.detailGood ? Color.onyx.good : Color.onyx.danger)
        } else if let d = reading.delta, let text = OnyxSnapshot.signed(d, decimals: reading.decimals) {
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

    private var spokenLabel: String {
        "\(reading.id), \(reading.value ?? "no reading") \(reading.unit)\(deltaSpoken)"
    }

    private var deltaSpoken: String {
        if let detail = reading.detail { return ", \(detail)" }
        guard let d = reading.delta, let text = OnyxSnapshot.signed(d, decimals: reading.decimals) else { return "" }
        return ", \(text) from baseline"
    }
}

/// A promoted vital, in the slot the night usually holds.
///
/// ── WHY IT IS NOT A DOOR AND THE NIGHT IS ───────────────────────────────────
/// There is nothing behind a vital to open: it is a number a watch measured and
/// no part of it is editable, which is the same reason the eight cells are not
/// buttons. The night has a window you can re-cut, two flags the watch cannot
/// record and an arc worth the room — so it stays a door in either slot.
///
/// The name says WHY it is here. "HRV" over a number is the grid cell; "HRV ·
/// 1.4 SD below your normal week" is the sentence that explains why this
/// reading, of the nine on the screen, is the one drawn at full width.
private struct VitalHeroCell: View {
    let reading: VitalsGrid.Reading

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            HStack(spacing: 3) {
                Circle()
                    .fill(reading.color)
                    .frame(width: 4, height: 4)
                    .accessibilityHidden(true)
                Text(reading.id).onyxMicro()
                Spacer(minLength: 0)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                    numeral
                    deviation
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 0) {
                    numeral
                    deviation
                }
            }
            // Full width, because the whole point of the slot is the trace: a
            // 24 pt line in a 120 pt cell says "down"; the same line across a
            // phone says how long it has been going down for.
            Sparkline(points: reading.trend, color: reading.color)
                .frame(height: 44)
                .opacity(reading.trend.count > 1 ? 1 : 0)
                .accessibilityHidden(true)
            Text("Further from your own normal than the night is")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(reading.id), \(reading.value ?? "no reading") \(reading.unit)"
                + (OnyxSnapshot.signed(reading.delta, decimals: reading.decimals).map { ", \($0) from baseline" } ?? "")
                + ". Further from your own normal than the night is."
        )
    }

    private var numeral: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(reading.value ?? "—")
                .onyxDisplay().fontWeight(.semibold).onyxNumeral()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.onyx.textPrimary)
            if !reading.unit.isEmpty {
                Text(reading.unit)
                    .onyxType(.caption)
                    .lineLimit(1)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var deviation: some View {
        if let d = reading.delta, let text = OnyxSnapshot.signed(d, decimals: reading.decimals) {
            let good = reading.upIsGood ? d > 0 : d < 0
            Text("\(text) vs your fortnight")
                .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(good ? Color.onyx.good : Color.onyx.danger)
        }
    }
}

/// Both or neither — the delta of a reading with no baseline behind it is not
/// zero, it is unknown, and a "0" chip claims the night did not move.
private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
