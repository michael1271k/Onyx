import SwiftUI
import OnyxUI
import OnyxCore

/// The session's clocks, pinned under the deck (Precision A4, Q7 A + Q8 C).
///
/// ── WHY A RAIL ──────────────────────────────────────────────────────────────
/// Every clock the session has used to live somewhere you had to go: elapsed in
/// the hero (scrolled away by the second card), the rest on whichever card
/// started it, pause and the set stopwatch inside a 560 pt sheet. The founder
/// asked for them in ONE place that never scrolls: 44 pt of Stone under the
/// deck — elapsed on the left, the rest and its ±15 s in the middle, pause on
/// the right. The hero keeps its big reading; a tap on it now only corrects
/// the start (`TimerSheet`).
///
/// ── EXACT, AND NO TIMER OF OUR OWN ──────────────────────────────────────────
/// Both readings are `Text(_:style: .timer)` / `Text(timerInterval:)`, ticked by
/// the SYSTEM off this view tree. Nothing here schedules a `Timer` or a
/// `TimelineView`, so no second can be skipped by a busy main thread and the
/// rail costs the deck nothing while you type a load. The rest's expiry haptic
/// stays `LiveLoggerView`'s `.task(id: restEndsAt)` — one source.
///
/// ── THE STOPWATCH OPENS FROM THE ELAPSED READING (Q8) ───────────────────────
/// A long press on elapsed unfolds the set stopwatch above the rail: start,
/// stop, lap, and the laps as capsules. Its state is `LiveLoggerView`'s
/// (`watch*`), so it keeps running through a collapse and a face switch.
struct TimerRail: View {
    let clock: any PauseControlling
    let accent: Color
    /// The running rest, already validated by `restCountdown(_:total:)` — nil
    /// when nobody is resting.
    let rest: ClosedRange<Date>?
    let onSkipRest: () -> Void
    let onAdjustRest: (TimeInterval) -> Void
    @Binding var watchStart: Date?
    @Binding var watchAccumulated: TimeInterval
    @Binding var watchLaps: [TimeInterval]
    @Binding var stopwatchOpen: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ticks = 0

    var body: some View {
        VStack(spacing: 0) {
            if stopwatchOpen {
                stopwatch
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                Rectangle().fill(Color.onyx.hairline).frame(height: 0.5)
            }
            HStack(spacing: OnyxSpace.s) {
                elapsed
                Spacer(minLength: 0)
                if let rest { restControl(rest) }
                Spacer(minLength: 0)
                pauseButton
            }
            .padding(.horizontal, OnyxSpace.s)
            .frame(minHeight: 44)
        }
        // The rest as a LENGTH: the bar that lived under the resting card's
        // header, moved here so it is on screen wherever the deck is scrolled.
        // Ticked by the system, like the digits (`ProgressView(timerInterval:)`).
        .overlay(alignment: .top) {
            if let rest, !stopwatchOpen {
                ProgressView(timerInterval: rest, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(accent)
                .padding(.horizontal, OnyxSpace.l)
                .accessibilityHidden(true)
            }
        }
        .onyxGlass(.chrome)
        // A rail that grows with the type until it is a second deck is not a
        // rail. Its readings stay legible at AX1; the hero above carries the
        // elapsed reading at full size for anyone past that.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, OnyxSpace.m)
        .padding(.bottom, OnyxSpace.xs)
        .animation(reduceMotion ? nil : OnyxMotion.drawer, value: stopwatchOpen)
        .animation(reduceMotion ? nil : OnyxMotion.drawer, value: rest == nil)
        .sensoryFeedback(.selection, trigger: ticks)
    }

    // MARK: - Elapsed

    private var elapsed: some View {
        HStack(spacing: OnyxSpace.xs) {
            Image(systemName: watchStart != nil ? "stopwatch.fill" : (clock.isPaused ? "pause.fill" : "stopwatch"))
                .imageScale(.small)
                .foregroundStyle(watchStart != nil ? accent : Color.onyx.textSecondary)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            Group {
                if clock.isPaused {
                    Text(Clock.format(clock.elapsed()))
                } else {
                    Text(clock.timerOrigin, style: .timer)
                }
            }
            .onyxType(.body).fontWeight(.semibold).onyxNumeral()
            .foregroundStyle(clock.isPaused ? Color.onyx.textTertiary : Color.onyx.textPrimary)
            .lineLimit(1)
            // The digits stay their own element — spoken as the reading, and
            // what the precision UI test reads twice.
            .accessibilityIdentifier("timer-rail-elapsed")
            .accessibilityHint(clock.isPaused ? "Session paused. Hold for the set stopwatch." : "Session time. Hold for the set stopwatch.")
            .accessibilityAction(named: stopwatchOpen ? "Close the stopwatch" : "Open the stopwatch") { toggleStopwatch() }
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .onLongPressGesture(minimumDuration: 0.35) { toggleStopwatch() }
    }

    private func toggleStopwatch() {
        stopwatchOpen.toggle()
        ticks += 1
    }

    // MARK: - Rest

    /// The countdown between its two nudges. The digits skip the rest; the
    /// nudges move it by 15 s, which dies with the set (`adjustRest`).
    private func restControl(_ rest: ClosedRange<Date>) -> some View {
        HStack(spacing: 0) {
            nudge(-15)
            Button(action: onSkipRest) {
                HStack(spacing: 3) {
                    Image(systemName: "timer").imageScale(.small)
                    Text(timerInterval: rest, countsDown: true)
                        .onyxNumeral()
                        // Reserved, or the nudges walk inwards as the digits
                        // fall from 1:00 to 59 — under the thumb reaching for one.
                        .frame(minWidth: 40, alignment: .leading)
                }
                .onyxType(.body).fontWeight(.semibold)
                .foregroundStyle(accent)
                .lineLimit(1)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resting")
            .accessibilityHint("Tap to skip the rest")
            nudge(15)
        }
    }

    private func nudge(_ seconds: TimeInterval) -> some View {
        Button { onAdjustRest(seconds) } label: {
            Text(seconds > 0 ? "+15" : "−15")
                .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
                .frame(minWidth: 40, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seconds > 0 ? "Add 15 seconds to the rest" : "Take 15 seconds off the rest")
    }

    // MARK: - Pause

    private var pauseButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : OnyxMotion.move) {
                if clock.isPaused { clock.resume() } else { clock.pause() }
            }
            ticks += 1
        } label: {
            Image(systemName: clock.isPaused ? "play.fill" : "pause.fill")
                .onyxType(.body).fontWeight(.semibold)
                .foregroundStyle(clock.isPaused ? accent : Color.onyx.textPrimary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(clock.isPaused ? "Resume session" : "Pause session")
    }

    // MARK: - The set stopwatch

    private var watchElapsed: TimeInterval {
        watchAccumulated + (watchStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private var stopwatch: some View {
        HStack(spacing: OnyxSpace.s) {
            Group {
                if let watchStart {
                    Text(watchStart.addingTimeInterval(-watchAccumulated), style: .timer)
                } else {
                    Text(Clock.format(watchAccumulated))
                }
            }
            .onyxType(.body).fontWeight(.semibold).onyxNumeral()
            .foregroundStyle(watchStart == nil ? Color.onyx.textPrimary : accent)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Stopwatch")
            // Newest first, as capsules: a lap list is read for the LAST lap,
            // and a row of them scrolls where a column would grow the rail.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OnyxSpace.xs) {
                    ForEach(Array(watchLaps.enumerated()), id: \.offset) { i, lap in
                        Text("\(watchLaps.count - i) · \(Clock.format(lap))")
                            .onyxType(.caption).onyxNumeral()
                            .foregroundStyle(Color.onyx.textSecondary)
                            .padding(.horizontal, OnyxSpace.s)
                            .padding(.vertical, 3)
                            .background(Color.onyx.ink(0.08), in: .capsule)
                            .accessibilityLabel("Lap \(watchLaps.count - i), \(Clock.format(lap))")
                    }
                }
            }
            if watchStart == nil {
                watchButton("arrow.counterclockwise", "Reset the stopwatch") {
                    watchAccumulated = 0
                    watchLaps = []
                }
                .disabled(watchAccumulated == 0 && watchLaps.isEmpty)
            } else {
                watchButton("flag.fill", "Lap") {
                    watchLaps.insert(watchElapsed - watchLaps.reduce(0, +), at: 0)
                }
            }
            watchButton(watchStart == nil ? "play.fill" : "stop.fill", watchStart == nil ? "Start the stopwatch" : "Stop the stopwatch") {
                if let started = watchStart {
                    watchAccumulated += Date().timeIntervalSince(started)
                    watchStart = nil
                } else {
                    watchStart = Date()
                }
            }
        }
        .padding(.horizontal, OnyxSpace.s)
        .frame(minHeight: 44)
    }

    private func watchButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            ticks += 1
        } label: {
            Image(systemName: symbol)
                .onyxType(.body).fontWeight(.semibold)
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
