import OnyxCore
import OnyxUI
import SwiftUI

/// Today's session, replayed on the wrist (overhaul W5, feature 2) — the same
/// keyframes as the phone's card, condensed to three seconds
/// (`SessionReplay.watchDuration`). Reached by tapping the finished-session
/// banner; a tap here plays it again.
///
/// ── 40 MM ───────────────────────────────────────────────────────────────────
/// A caption line, a 60 pt track and the masthead, which drops to its 2 × 2
/// caption tier by itself. In a `ScrollView` so the Crown still reaches the
/// masthead if a long split name wraps to two lines.
struct ReplayView: View {
    let timeline: SessionReplay.Timeline
    let dayInk: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?

    var body: some View {
        ScrollView {
            TimelineView(.animation(paused: startedAt == nil)) { context in
                let frame = startedAt.map { timeline.frame(at: context.date.timeIntervalSince($0)) } ?? timeline.final
                VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                    ReplayCaption(timeline: timeline, frame: frame, role: .caption)
                    ReplayCanvas(timeline: timeline, frame: frame, accent: OnyxInk.Themed.accent, lineWidth: 1.5)
                        .frame(height: 60)
                    OnyxMasthead(timeline.masthead, accent: dayInk)
                        .opacity(frame.settle)
                        .offset(y: 4 * (1 - frame.settle))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: play)
        .onAppear(perform: play)
        .task(id: startedAt) {
            guard startedAt != nil else { return }
            try? await Task.sleep(for: .seconds(timeline.duration))
            if !Task.isCancelled { startedAt = nil }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session replay")
        .accessibilityValue(ReplayCaption.accessibilityValue(timeline))
        .accessibilityAction(named: "Replay", play)
    }

    private func play() {
        guard !reduceMotion else { return }
        startedAt = Date()
    }
}
