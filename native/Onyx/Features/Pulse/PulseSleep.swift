import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

// ── WHERE THE SLEEP TILE WENT (W4) ─────────────────────────────────
// `SleepTile` was 280 lines of arc, stage column, bank line and a door, drawn
// permanently under the Now strip. Every part of it survives somewhere the
// night is actually the subject: the arc, the four stages and the two flags the
// watch cannot record are `SleepEditSheet`, which draws the same `DepthArc` at
// the same size and is what the night's cell opens. The duration is the Body
// ring's Sleep petal and the vitals grid's first cell since Precision B4, which
// retired `SleepHeroCell` (the petal said the night a second time, 200 pt tall).
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
