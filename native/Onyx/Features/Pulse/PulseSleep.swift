import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

// ── WHERE THE SLEEP TILE WENT (W4) ─────────────────────────────────
// `SleepTile` was 280 lines of arc, stage column, bank line and a door, drawn
// permanently under the Now strip. Every part of it survives somewhere the
// night is actually the subject: the arc, the four stages and the two flags the
// watch cannot record are `SleepEditSheet`, which draws the same `DepthArc` at
// the same size and is what the night's cell opens; the duration, the stage bar
// and the bank are `SleepHeroCell` below. What went is the 168 pt a reading you
// glance at was holding above the three readings you are asked for — the hero
// cell says the same four facts in about half of it (W2).
//
// `SleepStageList` stays — `SleepEditSheet` previews an edit through it.

/// Deep · Core · REM · Awake — a dot, a name, its minutes and its share of the
/// night, one 22 pt row each (§U5.1).
///
/// ── FOUR ROWS, NOT FOUR COLUMNS ─────────────────────────────────────────────
/// W11 made this a four-column `LazyVGrid` of `StageCell`, which was the right
/// call while the tile was full width: four readings of one kind, scanned
/// across. In a column beside a 96 pt gauge there is no width to scan across —
/// a quarter of 190 pt is 47, and "AWAKE 41m 9%" is three lines of it. A row
/// per stage reads down instead, and 22 pt each is the height that keeps the
/// four of them inside the arc column beside them.
///
/// A dot rather than `StageCell`'s bar: the arc IS the bar, drawn in the same
/// four colours, and a second length for the same fact beside it is the "no box
/// that only repeats the box above it" rule (§3.6).
///
/// Shared with `SleepEditSheet`, which previews what an edit does to the same
/// four numbers — so a preview and the tile it is previewing cannot render one
/// night two ways.
struct SleepStageList: View {
    /// `(stage, minutes)` — a stage nobody reported is ABSENT, not zero, and
    /// draws an em dash rather than claiming the watch measured none of it.
    let segments: [(OnyxSleepStage, Int)]

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var shareWidth: CGFloat = 34

    /// The share denominator: everything reported, asleep and awake alike.
    private var staged: Int { segments.reduce(0) { $0 + $1.1 } }

    /// The same xxLarge threshold `SleepEditSheet` takes — at a large size the
    /// row grows with the label that wraps inside it.
    private var tall: Bool { typeSize >= .xxLarge }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(OnyxSleepStage.allCases, id: \.self) { stage in
                row(stage)
            }
        }
    }

    /// ── `ViewThatFits`, NOT A TYPE-SIZE THRESHOLD ───────────────────────────
    /// "Awake 20m 5%" is three readings on one line, and at AX5 that is ~400 pt
    /// of type in a 350 pt column however wide the column is — so the tile's
    /// own `>= .xxLarge` switch, which only decides whether the list sits BESIDE
    /// the gauge, cannot help: the first AX5 shot of the edit sheet drew
    /// "1h…", "3h…", "20…" with the shares intact and the durations gone.
    ///
    /// What the row needs is to wrap when it genuinely does not fit, which is a
    /// measurement rather than a setting — the same reason `DayTile` puts its
    /// title and trailing word in a `ViewThatFits`. The name keeps its line and
    /// the two figures take the next.
    private func row(_ stage: OnyxSleepStage) -> some View {
        let minutes = segments.first(where: { $0.0 == stage })?.1
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: OnyxSpace.s) {
                dot(stage)
                name(stage)
                Spacer(minLength: OnyxSpace.xs)
                figures(minutes, shareWidth: shareWidth)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: OnyxSpace.s) {
                    dot(stage)
                    name(stage)
                    Spacer(minLength: 0)
                }
                // No fixed share column in the wrapped form: the whole reason
                // it is wrapped is that the width was not there to align to.
                HStack(spacing: OnyxSpace.s) {
                    figures(minutes, shareWidth: nil)
                    Spacer(minLength: 0)
                }
            }
        }
        // A MINIMUM: the row grows with whatever wraps inside it.
        .frame(minHeight: tall ? 32 : 22)
        .accessibilityElement(children: .combine)
    }

    private func dot(_ stage: OnyxSleepStage) -> some View {
        Circle()
            .fill(stage.color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    private func name(_ stage: OnyxSleepStage) -> some View {
        Text(stage.title)
            .onyxType(.caption)
            .foregroundStyle(Color.onyx.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// The minutes and the share. `shareWidth` aligns the percentages into a
    /// column when the four rows share one; nil lets it sit at its own width.
    @ViewBuilder
    private func figures(_ minutes: Int?, shareWidth: CGFloat?) -> some View {
        Text(Format.sleep(minutes.map(Double.init)))
            .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
            .foregroundStyle(Color.onyx.textPrimary)
            .lineLimit(1)
        Text(share(minutes))
            .onyxType(.caption).onyxNumeral()
            .foregroundStyle(Color.onyx.textTertiary)
            .frame(width: shareWidth, alignment: .trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// A stage with no reading has no share — 0 % would claim the watch
    /// measured none of it, which is a different fact from not having looked.
    private func share(_ minutes: Int?) -> String {
        guard let minutes, staged > 0 else { return "—" }
        return "\(Int((Double(minutes) / Double(staged) * 100).rounded()))%"
    }
}

// MARK: - The hero cell

/// The night, leading the vitals: one numeral, the stage bar, the bank, and a
/// door into `SleepEditSheet`.
///
/// ── WHY THE NIGHT AND NOT A SCROLLER (W2) ───────────────────────────────────
/// The nine readings were a `ScrollView(.horizontal)` of 104 pt chips —
/// ~1,010 pt of content in a 375 pt window, eight of the nine reachable only by
/// swiping a row nobody swipes. What a reader wants from this block is "is
/// anything off", and the answer is one reading large enough to be read from
/// the top of the screen plus eight small enough to be scanned in one glance.
/// So the block has a lead and eight sidekicks (`VitalsGrid`), and the lead is
/// the night — the reading the other eight are context for.
///
/// ── AND WHY THE NUMERAL IS `.display` AND NOT `.hero` ───────────────────────
/// `OnyxType.hero` is documented "at most one per screen — a second hero is two
/// screens in a trench coat", and this same wave is REMOVING the strip's second
/// one (battery). Adding one back 80 pt lower would undo the rule in the diff
/// that enforces it. The Now strip's Score keeps the screen's single `.hero`;
/// this leads the VITALS, which it does at `.display` against a grid whose
/// cells are `.secondary`.
///
/// ── THE HALF-RING, NOT A BAR (overhaul B2, decision Q6) ─────────────────────
/// This was a 44 pt `DepthBar`, so the night was drawn as a bar here and as a
/// half-ring on the tile, the Today sheet and the edit sheet. It is the same
/// `DepthArc` now — sweep = the night against the goal, fill = the stages in
/// the fixed sleep ramp. The whole cell is still one button.
struct SleepHeroCell: View {
    let model: DayModel
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var night: SleepSessionRow? { model.night }

    /// A row with a zero duration is a night nobody recorded — the same guard
    /// `goalText` made when this was a chip.
    private var minutes: Int? {
        guard let value = night?.durationMin, value > 0 else { return nil }
        return value
    }

    private var goalMin: Int { Int((model.sleepGoalHours * 60).rounded()) }

    /// "+22m" / "−1h 20m" / "goal met". Nil for a night with no reading, where
    /// a gap against the goal would be a gap from nothing.
    private var goalText: String? {
        guard let minutes else { return nil }
        let gap = minutes - goalMin
        if abs(gap) <= 5 { return "goal met" }
        return "\(gap > 0 ? "+" : "−")\(Format.sleep(Double(abs(gap))))"
    }

    private var goalMet: Bool { (minutes ?? goalMin) - goalMin >= -5 }

    /// `SleepStage`'s one rule (OnyxCore): depth order, a stage with no
    /// reading ABSENT — the arc draws its empty track for a night synced as a
    /// duration alone, a different fact from a night of pure core sleep.
    private var segments: [(OnyxSleepStage, Int)] {
        guard let night else { return [] }
        return OnyxSleepStage.segments(
            deep: night.deepMin, core: night.coreMin, rem: night.remMin, awake: night.awakeMin
        )
    }

    /// The bank, in one line. `sleepDebt` is nil under three nights of data,
    /// and that is a sentence rather than a blank: the line is the only place
    /// this screen says the night is read against a fortnight and not a goal.
    private var debtLine: String {
        guard let debt = model.sleepDebt else { return "Not enough nights to bank a debt yet" }
        guard debt.debtHours > 0 else { return "No debt over \(debt.nights) nights" }
        let hours = OnyxSnapshot.fixed(debt.debtHours, decimals: 1) ?? "\(debt.debtHours)"
        return "\(hours) h of debt over \(debt.nights) nights"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                header
                // The half-ring (decision Q6): the same `DepthArc` the tiles,
                // the Today sheet and the edit sheet draw. Its bowl stays
                // empty — the duration beside it is the Dynamic Type numeral.
                HStack(alignment: .center, spacing: OnyxSpace.m) {
                    DepthArc(
                        segments: segments, minutes: minutes, goalMin: goalMin,
                        lineWidth: 10, showsGoal: false, showsLabel: false
                    )
                    .frame(width: 96, height: 56)
                    reading
                }
                Text(debtLine)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(OnyxSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onyxGlass(.tile)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.98)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep, \(spoken). \(debtLine).")
        .accessibilityHint("Opens the night")
        .accessibilityAddTraits(.isButton)
    }

    private var header: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.onyx.accent(.recover))
                .frame(width: 4, height: 4)
                .accessibilityHidden(true)
            Text("Sleep").onyxMicro()
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .onyxType(.micro).fontWeight(.bold)
                .foregroundStyle(Color.onyx.textTertiary)
        }
    }

    /// ── `ViewThatFits`, NOT A TYPE-SIZE THRESHOLD ───────────────────────────
    /// "6h 40m" at `.display` beside "−1h 20m" at `.caption` is two figures on
    /// one line, and at AX5 that is more type than a phone is wide however the
    /// cell is laid out. The same measurement `SleepStageList.row` makes: the
    /// duration keeps its line and the gap takes the next.
    private var reading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                duration
                gap
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 0) {
                duration
                gap
            }
        }
    }

    private var duration: some View {
        Text(Format.sleep(minutes.map(Double.init)))
            .onyxDisplay().fontWeight(.semibold).onyxNumeral()
            .foregroundStyle(Color.onyx.textPrimary)
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private var gap: some View {
        if let goalText {
            Text(goalText)
                .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                .foregroundStyle(goalMet ? Color.onyx.good : Color.onyx.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text("No night recorded")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// `Format.sleep` prints an em dash for a night nobody recorded, and a
    /// reader hears an em dash as silence — the rule the sleep chip stated.
    private var spoken: String {
        guard let minutes else { return "no reading" }
        return "\(Format.sleep(Double(minutes)))\(goalText.map { ", \($0)" } ?? "")"
    }
}
