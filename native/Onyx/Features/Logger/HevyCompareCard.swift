import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// "Hevy logged this too." Expansion W5, founder decision 7.
///
/// ── ONE LINE, AND IT IS NOT A QUESTION (W3) ─────────────────────────────────
/// Hevy stays in use and Onyx never overrides a Hevy session. When a foreign
/// strength workout overlaps the one just finished, this says so in ONE
/// compact line — the source's monogram and its two figures, `142 bpm ·
/// 412 kcal` — and a tap opens the side-by-side: average heart rate,
/// calories, duration, sets, and the single action, "Use Hevy HR &
/// calories", which adopts the two figures the phone could not measure
/// itself, stamped as the athlete's answer (the same path a typed correction
/// takes). Nothing touches Health: the `HKWorkout` Hevy wrote is Hevy's, and
/// Onyx writes none beside it (decision 8, `WorkoutWriter`).
///
/// ── WHY "SKIP" WENT WITH THE CARD, AND NOT BEFORE IT ────────────────────────
/// It was a full card asking a question, and Skip was its primary answer —
/// not a dismiss, a RECORDED `HevyDecision.skip` that stopped both surfaces
/// asking. Deleting the button alone would have left the question on screen
/// for good, because both callers drew it while the decision was nil. So the
/// question went first: a line that states a fact needs no answer, both
/// callers now draw it until the decision is `.use`, and `.use` is the only
/// decision either writes. An old `.skip` on disk still decodes and simply
/// no longer hides anything.
///
/// It appears only when a foreign LIFTING workout overlaps
/// (`AppEnvironment.foreignWorkout` → `WorkoutProvenance.pick`), which was
/// already true and is unchanged.
///
/// Hevy's set count is whatever it stamped in the workout's metadata, which
/// it usually does not — so "—" is the ordinary fourth cell on its side.
struct HevyCompareCard: View {

    struct Figures {
        var avgBpm: Int?
        var kcal: Int?
        var durationMin: Int?
        var sets: Int?
        /// Which of Onyx's two figures are MEASURED — the watch's own, or
        /// typed. "Use" never replaces those; it fills what is estimated or
        /// missing, and is disabled when there is nothing left to fill.
        var bpmMeasured = false
        var kcalMeasured = false
    }

    let onyx: Figures
    let hevy: WorkoutSample
    let onUse: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var comparing = false
    /// "Use" was tapped — acted on once the sheet has gone. Both callers answer
    /// `onUse` by removing THIS view, which is the sheet's presenter; doing it
    /// while the sheet is still leaving cut the dismissal short.
    @State private var using = false

    private var source: String { hevy.sourceName ?? "Another app" }

    private var rows: [(label: String, symbol: String, onyx: String, hevy: String)] {
        [
            ("Avg HR", "heart", figure(onyx.avgBpm, "bpm"), figure(hevy.avgHr.map { Int(jsRound($0)) }, "bpm")),
            ("Calories", "flame", figure(onyx.kcal, "kcal"), figure(hevy.activeKcal.map { Int(jsRound($0)) }, "kcal")),
            ("Duration", "timer", figure(onyx.durationMin, "min"), figure(Int(jsRound(hevy.durationMin)), "min")),
            ("Sets", "square.stack.3d.up", figure(onyx.sets, nil), figure(hevy.sets, nil)),
        ]
    }

    /// Whether Hevy has anything to lend: with no heart rate AND no energy on
    /// its workout, the second button would adopt two dashes.
    private var canUse: Bool {
        (hevy.avgHr != nil && !onyx.bpmMeasured) || (hevy.activeKcal != nil && !onyx.kcalMeasured)
    }

    /// `142 bpm · 412 kcal` — what Hevy has that is worth a look. Its
    /// duration when it recorded neither, which is still the fact that it
    /// logged this session.
    private var summary: String {
        let parts = [
            hevy.avgHr.map { "\(Int(jsRound($0))) bpm" },
            hevy.activeKcal.map { "\(Int(jsRound($0))) kcal" },
        ].compactMap { $0 }
        // A line each at an accessibility size: wrapped mid-join, the dot hung
        // at the end of the first line.
        return parts.isEmpty
            ? "\(Int(jsRound(hevy.durationMin))) min"
            : parts.joined(separator: typeSize.isAccessibilitySize ? "\n" : " · ")
    }

    var body: some View {
        Button { comparing = true } label: {
            HStack(spacing: OnyxSpace.s) {
                monogram
                // The figures under the name at an accessibility size, where
                // one line holds the name or the figures, not both.
                (typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(spacing: OnyxSpace.s))) {
                    Text(source)
                        .onyxType(.body).fontWeight(.semibold)
                        .foregroundStyle(Color.onyx.textPrimary)
                    Text(summary)
                        .onyxType(.body).onyxNumeral()
                        .foregroundStyle(Color.onyx.textSecondary)
                        .minimumScaleFactor(0.8)
                }
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
            .padding(.horizontal, OnyxSpace.m)
            .padding(.vertical, OnyxSpace.xs)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .onyxGlass(.row)
        }
        .onyxPress(scale: 0.98)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(source) logged this session too, \(summary)")
        .accessibilityHint("Compares the two records")
        .sheet(isPresented: $comparing, onDismiss: {
            guard using else { return }
            using = false
            onUse()
        }) { compare }
    }

    /// The source's initial on a rounded square — an app's shape without an
    /// app's artwork, which is not Onyx's to draw. `Strong` gets an S.
    private var monogram: some View {
        Text(String(source.prefix(1)).uppercased())
            .onyxType(.caption).fontWeight(.bold)
            .foregroundStyle(Color.onyx.textPrimary)
            // A floor, not a size: a fixed 24 pt square squeezed the AX5
            // letter to a sliver.
            .padding(4)
            .frame(minWidth: 24, minHeight: 24)
            .fixedSize()
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.onyx.textTertiary.opacity(0.35))
            )
            .accessibilityHidden(true)
    }

    // MARK: - The compare sheet

    private var compare: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OnyxSpace.l) {
                    table
                    use
                }
                .padding(OnyxSpace.l)
            }
            .navigationTitle("\(source) logged this too")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { comparing = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.onyx.base)
    }

    // MARK: - The four rows

    @ViewBuilder
    private var table: some View {
        if typeSize.isAccessibilitySize {
            // One reading per line pair: label, then the two figures on their
            // own lines. A three-column grid at AX5 holds three truncations.
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                ForEach(rows, id: \.label) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(row.label, systemImage: row.symbol).onyxMicro()
                        Text("Onyx \(row.onyx)").onyxType(.body).onyxNumeral().foregroundStyle(Color.onyx.textPrimary)
                        Text("\(source) \(row.hevy)").onyxType(.body).onyxNumeral().foregroundStyle(Color.onyx.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } else {
            Grid(alignment: .leading, horizontalSpacing: OnyxSpace.m, verticalSpacing: OnyxSpace.s) {
                GridRow {
                    Text("").onyxMicro()
                    Text("ONYX").onyxMicro().foregroundStyle(OnyxDomain.train.accent)
                        .gridColumnAlignment(.trailing)
                    Text(source.uppercased()).onyxMicro().foregroundStyle(Color.onyx.textTertiary)
                        .gridColumnAlignment(.trailing)
                }
                ForEach(rows, id: \.label) { row in
                    GridRow {
                        Label(row.label, systemImage: row.symbol)
                            .onyxType(.caption)
                            .foregroundStyle(Color.onyx.textSecondary)
                            .lineLimit(1)
                        Text(row.onyx)
                            .onyxType(.body).fontWeight(.semibold).onyxNumeral()
                            .foregroundStyle(Color.onyx.textPrimary)
                        // The figure on offer is the reading where Onyx has
                        // none; secondary ink where Onyx already has its own.
                        Text(row.hevy)
                            .onyxType(.body).onyxNumeral()
                            .foregroundStyle(row.onyx == "—" ? Color.onyx.textPrimary : Color.onyx.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.label): Onyx \(row.onyx), \(source) \(row.hevy)")
                }
            }
        }
    }

    // MARK: - The one action

    /// Present only when there is something to adopt — a greyed caption was
    /// colour as the only signal, and no affordance. When there is nothing,
    /// the sheet says why rather than leaving a gap where a button was.
    @ViewBuilder
    private var use: some View {
        if canUse {
            Button {
                using = true
                comparing = false
            } label: {
                Text("Use \(source) HR & calories")
                    .onyxType(.body).fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            // Prominent: the sheet's ONE action, and the tinted-on-tint
            // bordered style read as a disabled button beside nothing else.
            .buttonStyle(.borderedProminent)
            .tint(OnyxDomain.train.accent)
            .accessibilityHint("Adopts \(source)'s heart rate and calories for this session. Nothing is written to Health.")
        } else {
            Text(hevy.avgHr == nil && hevy.activeKcal == nil
                 ? "\(source) recorded no heart rate or calories to use."
                 : "Onyx already measured both for this session.")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func figure(_ value: Int?, _ unit: String?) -> String {
        guard let value else { return "—" }
        return unit.map { "\(value) \($0)" } ?? "\(value)"
    }
}

#if DEBUG
extension WorkoutSample {
    /// A Hevy record of the finish-sheet fixture's session, for the harness:
    /// the phone measured nothing, Hevy has a rate and a burn, and no set
    /// count — the ordinary shape.
    static func previewHevy(over start: Date, minutes: Double = 61) -> WorkoutSample {
        WorkoutSample(
            start: start.addingTimeInterval(-90), end: start.addingTimeInterval(minutes * 60),
            isLifting: true, activeKcal: 356, avgHr: 128,
            sourceBundleId: "com.hevy.app", sourceName: "Hevy"
        )
    }
}
#endif
