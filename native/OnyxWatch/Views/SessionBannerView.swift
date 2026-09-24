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
    /// The replay, frozen at the tap (overhaul W5).
    @State private var replay: SessionReplay.Timeline?

    private var name: String {
        summary?.name ?? model.day?.label ?? model.dashboardTiles?.todayLabel ?? "Workout"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.commit)
                if let summary {
                    // ── LANE B'S SHARED FACE (8.2.0) ────────────────────────
                    // `OnyxMasthead` is the one drawing of a finished session
                    // — the phone's banners, the widget and the Live Activity
                    // draw it too — so the wrist says the same figures in the
                    // same order. Its `ViewThatFits` drops to a two-column
                    // caption grid at 40 mm (measured in the shots).
                    OnyxMasthead(summary, accent: WatchInk.day(model.day?.key))
                    if summary.hrSpark.count > 1 {
                        Spark(values: summary.hrSpark.map { Int($0.rounded()) })
                            .stroke(OnyxInk.Fixed.heart, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(height: 22)
                            .padding(.top, OnyxSpace.xs)
                            .accessibilityHidden(true)
                    }
                } else {
                    // An older phone: no masthead, only `todayLogged`.
                    Text(name)
                        .font(WatchType.figure)
                        .foregroundStyle(WatchInk.day(model.day?.key))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(model.day == nil ? "" : "Touch and hold to start another workout")
        .accessibilityAction(named: "Start another workout") { offerAnother() }
        .accessibilityAction(named: "Replay") { openReplay() }
        // A tap is the replay; the long press stays the deliberate "another".
        .onTapGesture(perform: openReplay)
        .onLongPressGesture(minimumDuration: 0.6) { offerAnother() }
        .sheet(isPresented: Binding(get: { replay != nil }, set: { if !$0 { replay = nil } })) {
            if let replay {
                ReplayView(timeline: replay, dayInk: WatchInk.day(model.day?.key))
            }
        }
        .confirmationDialog("Start another workout?", isPresented: $isOfferingAnother, titleVisibility: .visible) {
            Button("Start another") { model.beginSession(another: true) }
            Button("Cancel", role: .cancel) {}
        }
        .dimmedWhenLuminanceReduced()
        #if DEBUG
        // The shot loop cannot tap: `ONYX_WATCH_SCREEN=replay` opens it.
        .onAppear { if model.debugScreen == .replay { openReplay() } }
        #endif
    }

    private func openReplay() {
        guard let summary else { return }
        replay = model.replayTimeline(summary)
    }

    private func offerAnother() {
        guard model.day != nil else { return }
        WKInterfaceDevice.current().play(.click)
        isOfferingAnother = true
    }
}
