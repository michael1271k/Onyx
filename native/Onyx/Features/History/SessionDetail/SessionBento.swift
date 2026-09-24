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
/// its trophy. A `Button`, so it answers on touch-down and a scroll cancels it.
struct ExerciseChip: View {
    let exercise: SessionAnalysis.ExerciseReport
    let tint: Color
    let onOpen: () -> Void

    @ScaledMetric(relativeTo: .body) private var glyphTrack: CGFloat = 28

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: OnyxSpace.s) {
                Image(systemName: ExerciseGlyph.symbol(for: exercise.canonical))
                    .onyxType(.body)
                    .foregroundStyle(tint)
                    // A SCALED track: a fixed 24 pt let the glyph print over the
                    // name at AX5, and a bare floor let each glyph's own width
                    // move its name, so names in one column did not line up.
                    .frame(width: glyphTrack)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.canonical)
                        .onyxType(.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.onyx.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: OnyxSpace.xs) {
                        Text(Self.best(exercise))
                            .onyxType(.caption).onyxNumeral()
                            .foregroundStyle(Color.onyx.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if records > 0 {
                            Image(systemName: "trophy.fill")
                                .onyxType(.micro)
                                .foregroundStyle(Color.onyx.record)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(OnyxSpace.m)
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

/// Row 4 — the top four muscles as capsules in the fixed anatomical palette.
/// The whole row opens the atlas, which is where the full ranking lives.
struct FocusPills: View {
    let muscles: [(muscle: LandmarkMuscle, sets: Double)]
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: OnyxSpace.s) {
                FlowRow(spacing: OnyxSpace.xs) {
                    ForEach(Array(muscles.prefix(4)), id: \.muscle) { row in
                        pill(row.muscle, row.sets)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .onyxPress()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus: " + muscles.prefix(4)
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
        .padding(.horizontal, OnyxSpace.s + 2)
        .padding(.vertical, OnyxSpace.xs + 1)
        .background(ink.opacity(0.14), in: .capsule)
    }
}

/// Row 5 — one door to the progression chart and the full metric grid.
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
                VStack(alignment: .leading, spacing: 1) {
                    Text("Progression")
                        .onyxType(.body).fontWeight(.semibold)
                        .foregroundStyle(Color.onyx.textPrimary)
                    Text(caption)
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: OnyxSpace.s)
                Image(systemName: "chevron.right")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(OnyxSpace.m)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .onyxGlass(.tile)
            .contentShape(RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous))
        }
        .onyxPress()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the split's progression and every figure of this session")
    }
}
