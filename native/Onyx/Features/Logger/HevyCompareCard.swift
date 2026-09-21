import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// "Hevy logged this too." Expansion W5, founder decision 7.
///
/// ── ONE CARD, FOUR ROWS, TWO BUTTONS, AND IT WRITES NOTHING TO HEALTH ──────
/// Hevy stays in use and Onyx never overrides a Hevy session. When a foreign
/// strength workout overlaps the one just finished, this shows the two
/// records side by side — average heart rate, calories, duration, sets — and
/// asks one question. **Skip** is the primary answer and keeps Onyx's own
/// numbers exactly as they are. "Use Hevy HR/kcal" adopts the two figures the
/// phone could not measure itself, stamped as the athlete's answer (the same
/// path a typed correction takes). Neither button touches Health: the
/// `HKWorkout` Hevy wrote is Hevy's, and Onyx writes none beside it
/// (decision 8, `WorkoutWriter`).
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
    let onSkip: () -> Void
    let onUse: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

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

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.m) {
            HStack(spacing: OnyxSpace.xs) {
                Image(systemName: "arrow.left.arrow.right")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                Text("\(source) logged this too")
                    .onyxType(.body).fontWeight(.semibold)
                    .foregroundStyle(Color.onyx.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            table
            buttons
        }
        .padding(OnyxSpace.m)
        .onyxGlass(.tile)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(source) logged this session too")
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

    // MARK: - The two answers

    private var buttons: some View {
        VStack(spacing: OnyxSpace.xs) {
            // Primary WITHIN the card, and off the train ramp: that ramp is
            // "Finish session" one screen down, and a second ramp reads as a
            // second way to continue.
            Button(action: onSkip) {
                Text("Skip")
                    .onyxType(.body).fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(OnyxDomain.train.accent)
            .accessibilityHint("Keeps Onyx's own numbers. Nothing is written to Health.")
            // Present only when there is something to adopt — a greyed
            // caption was colour as the only signal, and no affordance.
            if canUse {
                Button(action: onUse) {
                    Text("Use \(source) HR/kcal")
                        .onyxType(.caption)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Color.onyx.textSecondary)
                .accessibilityHint("Adopts \(source)'s heart rate and calories for this session. Nothing is written to Health.")
            }
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
