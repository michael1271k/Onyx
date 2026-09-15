import OnyxCore
import OnyxData
import OnyxUI
import SwiftUI
import WatchKit

/// Rest, and the rating for the set that earned it.
///
/// ── WHY THE RPE LADDER LIVES HERE ───────────────────────────────────────────
/// Rest is 90 to 180 seconds of dead time. It is the only moment in a workout
/// when asking "how hard was that" is free — during the set it is noise, and
/// after the next set it is a memory test. Putting the ladder on its own page
/// would mean navigating to it, and nobody navigates to a rating.
///
/// It also gives `nil` the right shape. `SetSnapshot.rpe` is emphatic that an
/// unrated set is not a set rated zero — the progression rule has to tell "I
/// did not judge this" from "this was easy". On this screen, doing nothing IS
/// the unrated answer: the cover dismisses itself when the clock runs out and
/// no rating is written. You have to reach for a rung to make a claim.
///
/// ── AND THE LADDER IS EIGHT WORDS, NOT A NUMBER LINE ────────────────────────
/// `Effort.ladder` is eight NON-UNIFORM stops starting at 5.0 —
/// `[5, 6.5, 7.5, 8, 8.5, 9, 9.5, 10]` — because that is the shape of the scale
/// this athlete's 2,190 rated rows are on. A uniform 6-to-10 half-step scrubber
/// would write 6.0 and 7.0, which are not rungs: `Effort.rpeStopIndex` returns
/// -1 for them and the phone falls through to the CR-10 anchor, so the same set
/// would read with a word from a different scale on the two devices.
///
/// The Crown scrubs the ladder BY INDEX and the screen shows the word and its
/// reps-in-reserve gloss. A number on a ten-point scale means nothing to anyone
/// who has not memorised the scale — which is why the phone deleted its own
/// numeric picker.
struct RestView: View {

    @Environment(WatchModel.self) private var model
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    // `accessibilityReduceMotion` is GONE with the ring it guarded. An
    // environment property that nothing reads is still a live subscription:
    // the view re-renders whenever the setting changes, for a setting it no
    // longer honours. Nothing else here animates — the ladder's fill is an
    // unanimated state change and the toolbar clock ticks once a minute.
    @Environment(\.dismiss) private var dismiss

    let pulse: RestPulse

    /// Which rung the Crown is on. -1 is "nothing chosen", which is the state
    /// this screen is designed to be left in.
    @State private var rung: Double = -1
    @State private var didWarn = false
    @State private var didFire = false

    private var chosen: RpeStop? {
        let index = Int(rung.rounded())
        guard index >= 0, index < Effort.ladder.count else { return nil }
        return Effort.ladder[index]
    }

    var body: some View {
        // Same shape as `SetView`, and for the same reason: an inset that does
        // not reserve space draws the button over the countdown.
        VStack(spacing: OnyxSpace.xs) {
            ScrollView {
            // ── THE ORDER IS DIGITS, RATING, RECEIPT ────────────────────
            // The set line sat directly under the digits for one build, on the
            // reasoning that a receipt for the set belongs beside the clock
            // counting its rest. The 40 mm shot said otherwise: countdown plus
            // set line plus a navigation bar pushed the RPE ladder past the
            // fold, so the one control this screen exists to collect was
            // invisible on first paint and reachable only by scrolling — and
            // "nobody navigates to a rating" is the whole argument for the
            // ladder living here rather than on a page of its own.
            //
            // So the rating comes second and the receipt third. Both remain
            // above `Next ·`, which is the only line here about the future and
            // the right thing to put below the fold.
            VStack(spacing: 2) {
                clock
                ladder
                if let exercise = pulse.exercise {
                    Text("Next · \(exercise)")
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.secondary)
                        // Two lines: "Next · Incline Dumbbell Press" is three at
                        // 146 pt, and a "Next" line that pushes the ladder off
                        // the screen is worse than one that truncates.
                        .lineLimit(2)
                        .allowsTightening(true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OnyxSpace.s)
            // ── CANCELLING THE SCROLL VIEW'S OWN TOP INSET ──────────────────
            // watchOS reserves a strip under the navigation bar before a scroll
            // view's first child. On a 197 pt display with a bar above and a
            // pinned button below, that strip is the difference between the RPE
            // ladder being on screen and being cut in half by the fold — which
            // is what three rounds of screenshots kept showing.
            //
            // Measured, not guessed: the ladder overran the viewport by ~8 pt,
            // and this is that 8 pt. Shrinking type instead was tried first and
            // bought almost nothing — watchOS resolves `.largeTitle` and
            // `.title` to nearly the same size on a 40 mm case, which is its
            // own lesson about budgeting this device in points.
            .padding(.top, -OnyxSpace.s)
            }
            skip
        }
        .containerBackground(WatchInk.ground, for: .navigation)
        .dimmedWhenLuminanceReduced()
        // The session clock, in the same corner `SetView` puts it — see
        // `WatchSessionTimer`. This is what the cover's own `NavigationStack`
        // in `RootView` exists for: without one there is no bar to attach to
        // and the item draws nothing, silently.
        //
        // It replaces the system time of day in that corner, which is the right
        // trade mid-workout and has to be the same trade on both screens.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { WatchSessionTimer() }
        }
        .focusable()
        // The Crown means the ladder here, and nothing else is on screen — so
        // it is unambiguous by construction rather than by a focus ring.
        .digitalCrownRotation(
            $rung,
            from: -1, through: Double(Effort.ladder.count - 1), by: 1,
            sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .accessibilityElement()
        .accessibilityLabel("Effort")
        .accessibilityValue(chosen?.label ?? "not rated")
        .accessibilityAdjustableAction { direction in
            let next = rung + (direction == .increment ? 1 : -1)
            rung = min(Double(Effort.ladder.count - 1), max(-1, next))
        }
        .onChange(of: chosen?.value) { _, value in
            guard let value else { return }
            model.rate(value)
        }
        .task(id: pulse.endsAt) { await countdown() }
    }

    // MARK: - The clock

    /// mm:ss, counted by the SYSTEM.
    ///
    /// `Text(timerInterval:)` is ticked by the OS rather than by a timer in this
    /// view tree, which is what makes a running countdown cost nothing while the
    /// wrist is down — and what makes it still correct after the app has been
    /// suspended, because it is derived from an instant rather than accumulated.
    /// That is the same reason `RestPulse` carries `endsAt` and not a remaining
    /// duration.
    /// ── THE ARC IS GONE ─────────────────────────────────────────────────────
    /// A 44 pt `Circle().trim` redrawn by a 1 Hz `TimelineView`. It was already
    /// hidden in the always-on state and under Reduce Motion — the two
    /// conditions it was most needed in — because an arc stepped once a second
    /// stutters visibly, which left it drawing only when the digits underneath
    /// it were fully legible anyway. It was also the sole reader of
    /// `RestPulse.duration`, and therefore the sole victim of `adjustRest`
    /// keeping that value while it moved `endsAt`: +15 s made the fraction
    /// exceed 1 and the circle closed and kept going.
    ///
    /// The 48 pt it occupied is what the set line below and the toolbar clock
    /// above are now spending, and the digits — which are the answer to the
    /// only question a dropped wrist is asking — got bigger by being alone.
    private var clock: some View {
        VStack(spacing: 0) {
            Text(timerInterval: Date()...pulse.endsAt, countsDown: true)
                // `figure` and not `hero` — see the token. This screen carries
                // a control as well as a number, and at 40 mm `hero` took the
                // ladder off the bottom of it.
                .font(WatchType.figure)
                .foregroundStyle(WatchInk.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            lastSet
        }
    }

    /// The set that earned this rest — `70 kg × 8 · RPE 8`.
    ///
    /// ── BELOW THE DIGITS, NOT ABOVE THEM ────────────────────────────────────
    /// The countdown is the only thing on this screen that is true right now,
    /// and it holds the top of the display where a raised wrist looks first. A
    /// receipt for a set that is already finished, placed above it, reads as
    /// the headline's kicker — which is the opposite of what it is.
    ///
    /// ── AND IT IS EMPHATICALLY NOT TINTED BY THE EFFORT RAMP ────────────────
    /// `Color.onyx.effort` is what the phone tints an RPE badge with, and it
    /// would be wrong here twice: it is a third and fourth ink on a screen that
    /// has exactly two by design, and the RPE LADDER sits twenty points below
    /// this line. A coloured rating above the control that sets ratings reads
    /// as that control's current value, which it is not — it is the last set's,
    /// and picking a rung would then appear to change a number that had already
    /// been written.
    ///
    /// Nil until a phone new enough to send the set is talking to this watch,
    /// and nil for a rest the watch started itself. It draws nothing then,
    /// rather than a row of dashes.
    @ViewBuilder
    private var lastSet: some View {
        if let line = lastSetLine {
            Text(line)
                .font(WatchType.label)
                .foregroundStyle(WatchInk.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var lastSetLine: String? {
        guard let load = pulse.loadKg, let reps = pulse.reps else { return nil }
        // `×` and not `x`: on `SetView` the lowercase letter is a layout element
        // standing between two focusable rows, and here this is a sentence.
        // `WatchModel.lastTime` already spells the same fact the same way.
        let set = "\(Deck.fmtKg(load)) kg × \(reps)"
        guard let rpe = pulse.rpe else { return set }
        // `trimNum` and not `fmtKg`: the output is identical for every rung on
        // the ladder, and one of them is a weight formatter being asked about a
        // rating. 8 prints "8", 8.5 prints "8.5".
        return "\(set) · RPE \(Deck.trimNum(rpe, digits: 1))"
    }

    // MARK: - The ladder

    /// ── ONE LINE AT 40 mm, NOT TWO ─────────────────────────────────────────
    /// The word and its reps-in-reserve gloss were stacked. On a 40 mm case
    /// that second line is 16 pt the screen does not have: the navigation bar
    /// takes ~37 of 197, the pinned Skip another 34, and the shot came back
    /// with the ladder clipped and the set line pushed off the bottom
    /// altogether — losing one of the two things this wave added here.
    ///
    /// Side by side instead, separated by the same `·` the rest of the app
    /// uses. Nothing is dropped: unrated still reads "Rate", and a chosen rung
    /// still carries the gloss, which is the half that says what the word
    /// MEANS to someone who has not memorised a ten-point scale.
    private var ladder: some View {
        Group {
            if let chosen {
                Text("\(chosen.label) · \(chosen.hint)")
                    .foregroundStyle(WatchInk.primary)
            } else {
                Text("Rate")
                    .foregroundStyle(WatchInk.secondary)
            }
        }
        .font(WatchType.value)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .fill(chosen == nil ? WatchInk.fill : WatchInk.fillActive)
        )
    }

    private var skip: some View {
        Button("Skip rest") {
            model.stopRest()
            dismiss()
        }
        .font(WatchType.label)
        .buttonStyle(.bordered)
        // ── `.small`, AND IT IS THE FOLD THAT ASKED ─────────────────────────
        // A default `.bordered` button renders ~35 pt tall on a 40 mm case for
        // a caption-sized label, and it is PINNED — every point it takes comes
        // straight off the scroll viewport above it. At the default size the
        // RPE ladder was clipped in half by the fold. `.small` gives back ~12,
        // which is what puts the rating control fully on screen, and the target
        // is still comfortably reachable: it is the full width of the display.
        .controlSize(.small)
        .tint(WatchInk.fill)
        .foregroundStyle(WatchInk.primary)
        .opacity(isLuminanceReduced ? 0 : 1)
        .disabled(isLuminanceReduced)
    }

    // MARK: - Haptics

    /// Warn at three seconds, fire at zero, then get out of the way.
    ///
    /// ── AND WHY THIS ONLY WORKS INSIDE AN `HKWorkoutSession` ────────────────
    /// A haptic fires when the app is frontmost or when a workout session is
    /// running. With your wrist down and no session, watchOS has suspended this
    /// process seconds ago: the countdown is frozen, the zero never arrives, and
    /// raising your wrist gets a cold launch. `WorkoutSessionController` is what
    /// makes every line of this screen mean anything.
    ///
    /// Driven by a `task` rather than a `Timer` so it is cancelled with the
    /// view, and keyed on `endsAt` so adding 15 s restarts it rather than
    /// leaving a second one running.
    private func countdown() async {
        didWarn = false
        didFire = false
        while !Task.isCancelled {
            let remaining = pulse.endsAt.timeIntervalSinceNow
            if remaining <= 3, !didWarn {
                didWarn = true
                WKInterfaceDevice.current().play(.click)
            }
            if remaining <= 0, !didFire {
                didFire = true
                WKInterfaceDevice.current().play(.notification)
                model.stopRest()
                dismiss()
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
