import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// The session summary's bento pieces (overhaul C1, decisions Q12–Q15, concepts
// 5 and 6). The page used to be a `List` of six panels and one ledger card per
// movement — four screens of scroll on a six-movement day. It is five rows now:
// masthead · heart-rate strip · a 2-column grid of exercise chips · the focus
// pills · one Progression button. Everything the scroll used to carry is one
// tap away in a sheet (the ledger card, the chart and the metric grid, the
// atlas), so the first screen answers "what did I just do" and nothing else.
// ─────────────────────────────────────────────────────────────────────────────

extension SessionMasthead {
    /// The page's own figures, as the one masthead value every surface draws.
    ///
    /// `avgBpm` only when MEASURED: an estimate in the heart's red would read
    /// as a reading. The estimate keeps its cell, with its basis, in the
    /// Progression sheet's metric grid.
    init(page: SessionAnalysis.Page, label: String) {
        let session = page.report.session
        self.init(
            name: label,
            durationSec: Int(jsRound((session.durationMin ?? 0) * 60)),
            tonnageKg: page.report.tonnageKg,
            avgBpm: page.avgBpmEstimated ? nil : page.avgBpm.map { Int(jsRound($0)) },
            prCount: page.report.prCount,
            hrSpark: [],
            startedAt: session.startedAt ?? LogicalDay.date(fromISO: session.date) ?? Date()
        )
    }
}

/// Row 3's cell — one movement: its pattern glyph, its name, its best set and
/// a gold dot when it set a record. A `Button`, so it answers on touch-down and
/// a scroll cancels it.
///
/// ── THREE ACROSS SINCE PRECISION B1 (decision Q16) ──────────────────────────
/// Two columns put six movements over three rows of ~80 pt; three put them over
/// two. A 115 pt cell cannot hold a glyph BESIDE a name, so the glyph sits on
/// the cell's first line with the record dot opposite it, the name takes up to
/// two lines under it and the best set one more. The name drops its parenthetical
/// ("Seated Cable Row (V-Grip)" → "Seated Cable Row") — the qualifier is the
/// ledger sheet's title, one tap away, and VoiceOver still reads it whole.
/// The trophy glyph became a 6 pt dot: at 115 pt a trophy beside the best set
/// was the one thing on the cell that pushed the figure to shrink.
struct ExerciseChip: View {
    let exercise: SessionAnalysis.ExerciseReport
    let tint: Color
    let onOpen: () -> Void

    @ScaledMetric(relativeTo: .footnote) private var glyphLine: CGFloat = 18

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: OnyxSpace.xs) {
                    Image(systemName: ExerciseGlyph.symbol(for: exercise.canonical))
                        .onyxType(.caption)
                        .foregroundStyle(tint)
                        // One line height for every glyph: symbols of
                        // different heights put the names 3–7 pt apart
                        // across a row (critique, shot round 2).
                        .frame(height: glyphLine, alignment: .leading)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    if records > 0 {
                        Circle()
                            .fill(Color.onyx.record)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                }
                Text(Self.shortName(exercise.canonical))
                    .onyxType(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color.onyx.textPrimary)
                    // Two lines, not one: "Single Arm Lateral Raise" in a
                    // 115 pt cell truncated to "Single Arm Later…" (shot
                    // round 1). `Grid` gives the row one height either way.
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.best(exercise))
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, OnyxSpace.s + 2)
            .padding(.vertical, OnyxSpace.s - 2)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .topLeading)
            .onyxGlass(.tile)
            .contentShape(RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous))
        }
        .onyxPress()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens this movement's sets")
        .accessibilityAddTraits(.isButton)
    }

    /// "Seated Cable Row (V-Grip)" → "Seated Cable Row": the cell's one line.
    static func shortName(_ name: String) -> String {
        let head = name.components(separatedBy: " (").first ?? name
        return head.isEmpty ? name : head
    }

    /// Sets on this card that set a record.
    private var records: Int {
        exercise.rows.reduce(0) { total, row in
            total + [row.set, row.left, row.right].compactMap { $0 }
                .filter { !($0.prAxes ?? []).isEmpty }.count
        }
    }

    private var spoken: String {
        var parts = [exercise.canonical, "best \(Self.best(exercise))"]
        if records > 0 { parts.append(records == 1 ? "1 record set" : "\(records) record sets") }
        return parts.joined(separator: ", ")
    }

    /// The best set in the card's own words: top load × reps for a lift, the
    /// bout for cardio, the set count for anything else.
    static func best(_ ex: SessionAnalysis.ExerciseReport) -> String {
        if ex.stats.topKg > 0 || ex.stats.topReps > 0 {
            return SetFormat.format(weightKg: ex.stats.topKg, reps: ex.stats.topReps, timed: ex.timed)
        }
        let sets = ex.rows.flatMap { [$0.set, $0.left, $0.right].compactMap { $0 } }
        if let bout = sets.lazy.compactMap({ SetFormat.cardio(
            durationSec: $0.durationSec, distanceKm: $0.distanceKm, incline: nil, elevationM: nil
        ) }).first {
            return bout
        }
        let n = sets.count
        return n == 1 ? "1 set" : "\(n) sets"
    }
}

/// The top muscles as capsules in the fixed anatomical palette. The whole row
/// opens the atlas, which is where the full ranking lives.
///
/// Since Precision B1 the masthead's second line (top three), not a row of its
/// own under the grid.
struct FocusPills: View {
    let muscles: [(muscle: LandmarkMuscle, sets: Double)]
    var limit = 4
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: OnyxSpace.s) {
                FlowRow(spacing: OnyxSpace.xs) {
                    ForEach(Array(muscles.prefix(limit)), id: \.muscle) { row in
                        pill(row.muscle, row.sets)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // At the accessibility sizes the chevron's column made
                // "Upper back 4.5" wrap inside its capsule (W-final AX5 shot);
                // the row is still a button without it.
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textTertiary)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .onyxPress()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus: " + muscles.prefix(limit)
            .map { "\($0.muscle.displayName) \(OnyxFormat.sets($0.sets))" }
            .joined(separator: ", "))
        .accessibilityHint("Opens the body you can turn over")
        .accessibilityAddTraits(.isButton)
    }

    private func pill(_ muscle: LandmarkMuscle, _ sets: Double) -> some View {
        let ink = Color.onyx.muscle(muscle)
        return HStack(spacing: OnyxSpace.xs) {
            Text(muscle.displayName)
                .onyxType(.caption).fontWeight(.semibold)
                .foregroundStyle(ink)
            Text(OnyxFormat.sets(sets))
                .onyxType(.caption).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
        }
        .lineLimit(1)
        .padding(.horizontal, OnyxSpace.s + 2)
        .padding(.vertical, OnyxSpace.xs + 1)
        .background(ink.opacity(0.14), in: .capsule)
    }
}

/// The last row — one door to the progression chart and the full metric grid.
///
/// ONE line since Precision B1 (the name, then the verdict trailing it) and
/// two only when the verdict will not fit beside the name: the second line was
/// 20 pt of the summary's 423 pt budget on every session.
struct ProgressionButton: View {
    let caption: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: OnyxSpace.s) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .onyxType(.body)
                    .foregroundStyle(OnyxInk.Themed.accent)
                    .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                        title.fixedSize()
                        captionText.lineLimit(1)
                    }
                    // No `fixedSize` here: at AX5 "Progression" alone is wider
                    // than the phone, and a title that refused to wrap widened
                    // the whole page past the screen (shot round 2).
                    VStack(alignment: .leading, spacing: 1) {
                        title
                            .fixedSize(horizontal: false, vertical: true)
                        captionText
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: OnyxSpace.s)
                Image(systemName: "chevron.right")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OnyxSpace.m)
            .padding(.vertical, OnyxSpace.s)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .onyxGlass(.tile)
            .contentShape(RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous))
        }
        .onyxPress()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the split's progression and every figure of this session")
    }

    private var title: some View {
        Text("Progression")
            .onyxType(.body).fontWeight(.semibold)
            .foregroundStyle(Color.onyx.textPrimary)
    }

    private var captionText: some View {
        Text(caption)
            .onyxType(.caption)
            .foregroundStyle(Color.onyx.textSecondary)
    }
}
