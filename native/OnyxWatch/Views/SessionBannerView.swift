import OnyxCore
import OnyxUI
import SwiftUI
import WatchKit

/// Today's workout is done — the page that replaces Start once the phone says
/// so (overhaul A1, decision Q3: name · tonnage · avg HR · PRs + a six-point
/// heart-rate spark).
///
/// ── THE NUMBERS ARE THE PHONE'S ─────────────────────────────────────────────
/// `SessionLifecycle.summary` is built on the phone off the closed row
/// (`SessionMasthead(session:name:samples:)`), so the wrist runs no telemetry
/// query and cannot disagree with the session page about the same workout.
/// An older phone sends no masthead — only `todayLogged` — and the banner then
/// draws the split and the word, which is still the right answer to "why is
/// there no Start button".
///
/// ── A SECOND SESSION IS A LONG PRESS AWAY, NOT A BUTTON ─────────────────────
/// Two-a-days are real, and rare. A Start button under the banner would put
/// the reported bug back one tap from any raised wrist; a long press is a
/// deliberate gesture, and it still asks.
struct SessionBannerView: View {

    @Environment(WatchModel.self) private var model
    let summary: SessionMasthead?

    @State private var isOfferingAnother = false

    private var name: String {
        summary?.name ?? model.day?.label ?? model.dashboardTiles?.todayLabel ?? "Workout"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.commit)
                Text(name)
                    .font(WatchType.figure)
                    .foregroundStyle(WatchInk.day(model.day?.key))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let summary {
                    Text("\(Int(summary.tonnageKg.rounded()).formatted()) kg")
                        .font(WatchType.value)
                        .foregroundStyle(WatchInk.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    readings(summary)
                    if summary.hrSpark.count > 1 {
                        Spark(values: summary.hrSpark.map { Int($0.rounded()) })
                            .stroke(OnyxInk.Fixed.heart, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(height: 22)
                            .padding(.top, OnyxSpace.xs)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(model.day == nil ? "" : "Touch and hold to start another workout")
        .accessibilityAction(named: "Start another workout") { offerAnother() }
        .onLongPressGesture(minimumDuration: 0.6) { offerAnother() }
        .confirmationDialog("Start another workout?", isPresented: $isOfferingAnother, titleVisibility: .visible) {
            Button("Start another") { model.beginSession(another: true) }
            Button("Cancel", role: .cancel) {}
        }
        .dimmedWhenLuminanceReduced()
    }

    private func offerAnother() {
        guard model.day != nil else { return }
        WKInterfaceDevice.current().play(.click)
        isOfferingAnother = true
    }

    /// Average heart rate and records, glyph + number — the grammar of the
    /// Start page's stat row. The heart is the FIXED heart ink in every theme
    /// (decision Q19), the trophy the record gold.
    private func readings(_ summary: SessionMasthead) -> some View {
        HStack(spacing: OnyxSpace.s) {
            if let bpm = summary.avgBpm {
                stat("heart.fill", "\(bpm)", OnyxInk.Fixed.heart, "Average heart rate", "\(bpm) beats per minute")
            }
            if summary.prCount > 0 {
                stat("trophy.fill", "\(summary.prCount)", WatchInk.record, "Records", "\(summary.prCount)")
            }
        }
    }

    private func stat(_ glyph: String, _ value: String, _ tint: Color, _ label: String, _ spoken: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: glyph)
                .foregroundStyle(tint)
            Text(value)
                .foregroundStyle(WatchInk.primary)
                .monospacedDigit()
        }
        .font(WatchType.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
    }
}
