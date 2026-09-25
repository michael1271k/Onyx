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
    @State private var isEditing = false
    @State private var isConfirmingCancel = false

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
            // ── THE ORDER IS NOW, NOW, CONTROL, THEN THE PAST ───────────
            // The set line sat directly under the digits for one build, on the
            // reasoning that a receipt for the set belongs beside the clock
            // counting its rest. The 40 mm shot said otherwise: countdown plus
            // set line plus a navigation bar pushed the RPE ladder past the
            // fold, so the one control this screen exists to collect was
            // invisible on first paint and reachable only by scrolling — and
            // "nobody navigates to a rating" is the whole argument for the
            // ladder living here rather than on a page of its own.
            //
            // W3 added the recovery curve and the budget could not hold five
            // rows, so the order is now: the countdown, the curve under it
            // (the other thing that is true RIGHT NOW), then ONE row carrying
            // both the receipt and the rate, then the control, then `Next ·`
            // — the only line here about the future and the right thing to
            // put below the fold.
            //
            // The ladder stays above the fold, which is the rule this comment
            // has defended since it was written. The first build of this wave
            // broke it in the other direction: the heart row and `Next ·` were
            // drawn BELOW the pinned Skip button, where watchOS puts them off
            // the display rather than clipping them. That is what adding a row
            // here costs — measure it, do not guess.
            VStack(spacing: 2) {
                clock
                spark
                receipt
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
        .containerBackground(for: .navigation) { WatchInk.ground }
        .dimmedWhenLuminanceReduced()
        // The session clock, in the same corner `SetView` puts it — see
        // `WatchSessionTimer`. This is what the cover's own `NavigationStack`
        // in `RootView` exists for: without one there is no bar to attach to
        // and the item draws nothing, silently.
        //
        // It replaces the system time of day in that corner, which is the right
        // trade mid-workout and has to be the same trade on both screens.
        .toolbar {
            // The same two gestures the set screen's clock carries, in the
            // corner this screen has free. Pause has to be reachable from the
            // screen you are actually on during a rest, and cancel has to be
            // the same gesture in both places or it is two things to remember.
            ToolbarItem(placement: .topBarTrailing) {
                WatchSessionTimer()
                    .onTapGesture {
                        model.togglePause()
                        WKInterfaceDevice.current().play(.click)
                    }
                    .onLongPressGesture(minimumDuration: 0.6) {
                        WKInterfaceDevice.current().play(.retry)
                        isConfirmingCancel = true
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(model.isPaused ? "Resumes the session" : "Pauses the session")
            }
        }
        .sheet(isPresented: $isConfirmingCancel) {
            DiscardSheet(setCount: model.sets.count) {
                model.cancelSession()
                dismiss()
            }
        }
        // ── THE SHEET IS PRESENTED, THE CROWN IS NOT SHARED ─────────────────
        // While it is up it owns the Crown for its own two rows, and this
        // view's ladder is not on screen to contest it. Dismissing gives the
        // rung back, which is why the rating survives an edit.
        .sheet(isPresented: $isEditing) { EditLastSetSheet() }
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
        // ── ONE AMEND PER SCRUB, NOT PER DETENT (overhaul A3) ───────────────
        // This called `model.rate` on every detent: five rungs, five
        // permanent events. The model now debounces — a provisional pulse to
        // the phone 150 ms after the Crown rests, one amend after a second of
        // stillness, and the cover leaving settles it at once.
        .onChange(of: chosen?.value) { _, value in
            guard let value else { return }
            model.scrubEffort(value)
        }
        .onDisappear { model.finishScrub() }
        #if DEBUG
        // `restband`: the ladder on a chosen rung, so the band ink can be
        // photographed — a simulator has no Crown to turn.
        .onChange(of: model.debugScreen, initial: true) { _, screen in
            if screen == .restband { rung = Double(Effort.rpeStopIndex(9.5)) }
        }
        #endif
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
    /// above are now spending.
    ///
    /// ── AND THE RECEIPT LEFT THIS STACK IN W3 ───────────────────────────────
    /// It was a second line inside this property. The wave that added the
    /// recovery curve had to choose what sits directly under the countdown,
    /// and the answer is the other thing that is true RIGHT NOW — the curve.
    /// The receipt is a fact about a set that has finished, so it moved down
    /// and shares a row with the rate.
    private var clock: some View {
        Text(timerInterval: Date()...pulse.endsAt, countsDown: true)
            // ── `value`, AND THE STEP DOWN WAS MEASURED (W3) ────────────────
            // It was `hero`, then `figure`, each time because the row under it
            // was being clipped. W3 added the recovery curve and the budget
            // ran out: the cover's scroll viewport is about 95 pt once the bar
            // and the pinned Skip button have taken theirs, and `figure` alone
            // spends 40 of it — the first build of this wave drew the receipt
            // and the `Next ·` line off the bottom of the display, which is
            // what watchOS does instead of clipping.
            //
            // At `value` the countdown, the curve, the receipt and the ladder
            // all fit above the fold. It is still the biggest thing here and
            // the only monospaced one, so it still reads as the answer to "how
            // long left".
            .font(WatchType.value)
            .foregroundStyle(WatchInk.primary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
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
    /// ── AND IT IS THE EDIT DOOR (W3) ────────────────────────────────────────
    /// A receipt is where you notice the number is wrong, and until W3 the
    /// wrist's only remedy was to undo the set and do it again. Tapping it
    /// opens the two Crown rows on the set it names — the same `ValueRow` the
    /// logger uses, because a focused number has one look on this device.
    ///
    /// It is tappable only when there is a set to edit: `lastSetLine` is nil
    /// for a rest this watch started itself (the pulse carries no numbers) and
    /// for a phone too old to send them, and a control that appears half the
    /// time is worse than one that appears with the thing it acts on.
    @ViewBuilder
    private var lastSet: some View {
        if let line = lastSetLine {
            Button {
                isEditing = true
            } label: {
                Text(line)
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(model.lastLogged == nil || isLuminanceReduced)
            .accessibilityHint("Edits the load and reps of this set")
        }
    }

    // MARK: - The heart

    /// ── A SHAPE, NOT A CHART ────────────────────────────────────────────────
    /// `LineMark` would work and costs more than it is worth here: Swift
    /// Charts is a framework the watch target does not link today, loaded on
    /// the launch path during an `HKWorkoutSession`, re-running scale and axis
    /// layout on every redraw — including the 1 Hz ticks of the always-on
    /// state — to draw a polyline with no axes, no legend and nothing to hit
    /// test. `WatchInk`'s header refuses a mesh gradient on this device for
    /// the same reason.
    ///
    /// ── AND THE DELTA IS AGAINST THE PULSE, NOT THE BUFFER ──────────────────
    /// `RestPulse.bpm` is the reading at the instant the rest started, which is
    /// the only thing "since rest began" can honestly mean here:
    /// `recentSamples` is a rolling window of this launch and has no idea when
    /// you racked the bar.
    ///
    /// ── THE CURVE ALONE ─────────────────────────────────────────────────────
    /// A 12 pt strip, full width, no axis and no number.
    ///
    /// Its own row because it is the only thing on this screen that is a
    /// SHAPE, and a polyline squeezed between two text runs is a squiggle.
    /// Twelve points is what the budget had, and it is enough to read a fall
    /// from a plateau, which is the whole question.
    @ViewBuilder
    private var spark: some View {
        if model.workout.recentSamples.count > 1, !isLuminanceReduced {
            Spark(values: model.workout.recentSamples)
                .stroke(
                    WatchInk.record,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .frame(height: 12)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 1)
                .accessibilityHidden(true)
        }
    }

    /// The set that earned this rest on the left, what your heart is doing on
    /// the right — ONE row.
    ///
    /// ── WHY THEY SHARE A LINE ───────────────────────────────────────────────
    /// They were two rows, and two did not fit: the first build of this wave
    /// had the receipt drawn off the bottom of the display, which is what
    /// watchOS does instead of clipping. They are also the same KIND of line —
    /// a small secondary fact under a hero number — so sharing one is not only
    /// a concession to points.
    ///
    /// Only the left half is a button. Tapping a heart rate to edit a set
    /// would be a target that does not mean what it shows.
    @ViewBuilder
    private var receipt: some View {
        if lastSetLine != nil || model.workout.heartRate != nil {
            HStack(spacing: OnyxSpace.xs) {
                lastSet
                Spacer(minLength: 0)
                if let bpm = model.workout.heartRate, !isLuminanceReduced {
                    // ── GOLD, LIKE THE CURVE AND LIKE THE SET SCREEN ────────
                    // It was `primary`, and the same fact was then white here
                    // and gold two screens over. Worse, it orphaned the gold
                    // curve directly above it — a colour with no labelled
                    // owner — and put a second white numeral under the
                    // countdown, which is the one thing on this screen that
                    // is allowed to be a white numeral.
                    Text("\(bpm)")
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.record)
                        .monospacedDigit()
                        .accessibilityLabel("Heart rate \(bpm) beats per minute")
                    if let drop = recovered {
                        // A recovery is a NEGATIVE delta and it is the good
                        // one, so the sign is printed rather than inferred
                        // from a colour — this screen has two inks and
                        // neither of them means "good".
                        // ── AN ARROW, NOT A SIGN ────────────────────────────
                        // Two integers of similar magnitude either side of a
                        // minus is the RANGE idiom: "104 −44" reads first as
                        // "104 to 44". An arrow cannot be read that way, and
                        // it costs the same width — which this row does not
                        // have to spare at 40 mm.
                        Text(drop > 0 ? "↓\(drop)" : "↑\(-drop)")
                            .font(WatchType.label)
                            .foregroundStyle(WatchInk.secondary)
                            .monospacedDigit()
                            .accessibilityLabel(
                                drop > 0 ? "down \(drop) since the set" : "up \(-drop) since the set"
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// How far the rate has come down since the pulse was sent. Nil when the
    /// pulse carried no reading — an older phone, or a rest this watch started
    /// before its own sensor had settled.
    private var recovered: Int? {
        guard let start = pulse.bpm, let now = model.workout.heartRate else { return nil }
        return start - now
    }

    private var lastSetLine: String? {
        guard let load = pulse.loadKg, let reps = pulse.reps else { return nil }
        // `×` and not `x`: on `SetView` the lowercase letter is a layout element
        // standing between two focusable rows, and here this is a sentence.
        // `WatchModel.lastTime` already spells the same fact the same way.
        // ── NO `kg`, BECAUSE THE ROW IS SHARED NOW ──────────────────────
        // The heart rate and its delta took the right-hand end of this line
        // in W3 and the 49 mm shot came back "42.5 kg × 12 · RPE…". The unit
        // is the one thing here that can go: `×` already says this is a set,
        // and every other load on this wrist is in kilograms.
        let set = "\(Deck.fmtKg(load)) × \(reps)"
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
            // ── THE UNRATED WORD IS PRIMARY INK ─────────────────────────────
            // Grey word on a grey fill with no glyph reads as a disabled
            // placeholder, and `Skip rest` directly under it is white on a
            // similar pill — so the one control this screen exists to offer
            // was the quietest thing on it and the escape hatch was the
            // loudest. The chevron says it is a control; the Crown is what
            // turns it.
            if let chosen {
                Text("\(chosen.label) · \(chosen.hint)")
                    .foregroundStyle(WatchInk.primary)
            } else {
                Text("Rate ›")
                    .foregroundStyle(WatchInk.primary)
            }
        }
        .font(WatchType.value)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        // ── THE BAND IS THE FILL (overhaul A3) ──────────────────────────────
        // A chosen rung washes the pill in its `EffortBand` ink — steady in
        // the theme's accent, hard amber, very hard clay, failure red — the
        // same colour the phone's deck card paints the provisional rating,
        // so the two devices agree at a glance. The word stays primary ink:
        // the colour is the band, the word is the rung.
        .background(
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .fill(chosen.map { EffortBand(rpe: $0.value).ink.opacity(0.32) } ?? WatchInk.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .strokeBorder(chosen.map { EffortBand(rpe: $0.value).ink } ?? .clear, lineWidth: 1)
        )
    }

    private var skip: some View {
        Button("Skip rest") {
            model.stopRest()
            dismiss()
        }
        .font(WatchType.label)
        // Secondary ink: it is the way out, not the thing to do. See the
        // ladder's note about which of the two was shouting.
        .foregroundStyle(WatchInk.secondary)
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

// MARK: - The sparkline

/// A polyline over the readings, normalised to its own range.
///
/// ── IT IS A SHAPE AND NOT A TIME SERIES, AND IT DRAWS NO AXIS ───────────────
/// `WorkoutSessionController.recentSamples` are the readings THIS LAUNCH saw,
/// at whatever cadence HealthKit delivered them — not a fixed grid. Spacing
/// them evenly is therefore a drawing decision and not a measurement, which is
/// exactly why there is no axis under it and no number derived from it: the
/// figure beside it is the current rate, read from the same controller.
///
/// Fewer than two readings draws nothing. A flat run draws the middle line
/// rather than dividing by a zero range — a heart that has not moved is a real
/// state, and `hi == lo` is how it arrives.
struct Spark: Shape {
    let values: [Int]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let lo = Double(values.min() ?? 0)
        let hi = Double(values.max() ?? 0)
        let dx = rect.width / CGFloat(values.count - 1)
        return Path { path in
            for (i, value) in values.enumerated() {
                let fraction = hi > lo ? (Double(value) - lo) / (hi - lo) : 0.5
                let point = CGPoint(
                    x: rect.minX + CGFloat(i) * dx,
                    y: rect.maxY - CGFloat(fraction) * rect.height
                )
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

// MARK: - Editing the set behind you

/// The two numbers of the last logged set, on the Crown.
///
/// ── WHY A SHEET AND NOT A THIRD PAGE ────────────────────────────────────────
/// It is reached from the receipt that names the set, it is about one set, and
/// it ends by being dismissed — which is a sheet. A page would have to exist
/// on the rest screen whether or not there was anything to edit, and the rest
/// screen's vertical budget is the one this app has fought hardest for.
///
/// ── AND WHY IT SAVES ON DISMISS RATHER THAN ON EVERY DETENT ─────────────────
/// The panel one screen over writes an `amend` per tap because a tap is a
/// decision. A Crown turn is not: scrubbing 40 kg to 42.5 passes through eight
/// values, and writing each one would put eight permanent events in a log that
/// is never compacted for one correction. So the numbers are local until the
/// button, and `editLast` refuses a patch that changes nothing.
private struct EditLastSetSheet: View {

    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case load, reps }
    @FocusState private var field: Field?

    @State private var load: Double = 0
    @State private var reps: Int = 0

    var body: some View {
        VStack(spacing: OnyxSpace.xs) {
            ScrollView {
                VStack(alignment: .leading, spacing: OnyxSpace.s) {
                    Text(model.lastLoggedMovement?.plan.name ?? "Last set")
                        .font(WatchType.name)
                        .foregroundStyle(WatchInk.primary)
                        .lineLimit(2)
                        .allowsTightening(true)
                    HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.xs) {
                        ValueRow(value: Deck.fmtKg(load), unit: "kg", font: WatchType.figure, isFocused: field == .load)
                            .focusable()
                            .focused($field, equals: .load)
                            .digitalCrownRotation(
                                $load,
                                from: 0, through: 500, by: Ceilings.loadStepFineKg,
                                sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true
                            )
                            .onTapGesture { field = .load }
                            .accessibilityElement()
                            .accessibilityLabel("Load")
                            .accessibilityValue("\(Deck.fmtKg(load)) kilograms")
                            .accessibilityAdjustableAction { direction in
                                let step = direction == .increment ? Ceilings.loadStepFineKg : -Ceilings.loadStepFineKg
                                load = Deck.nudgeLoad(load, step)
                            }
                        Text("x")
                            .font(WatchType.label)
                            .foregroundStyle(WatchInk.secondary)
                            .accessibilityHidden(true)
                        ValueRow(value: "\(reps)", unit: "reps", font: WatchType.value, isFocused: field == .reps)
                            .focusable()
                            .focused($field, equals: .reps)
                            .digitalCrownRotation(
                                Binding(get: { Double(reps) }, set: { reps = max(1, Int($0.rounded())) }),
                                from: 1, through: 50, by: 1,
                                sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
                            )
                            .onTapGesture { field = .reps }
                            .accessibilityElement()
                            .accessibilityLabel("Reps")
                            .accessibilityValue("\(reps)")
                            .accessibilityAdjustableAction { direction in
                                reps = max(1, reps + (direction == .increment ? 1 : -1))
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                model.editLast(load: load, reps: reps)
                WKInterfaceDevice.current().play(.success)
                dismiss()
            } label: {
                Label("Save", systemImage: "checkmark")
                    .font(WatchType.value)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchInk.commit)
            .foregroundStyle(WatchInk.onCommit)
        }
        .containerBackground(for: .navigation) { WatchInk.ground }
        .onAppear {
            // Seeded from the LOG, not from the pulse: the pulse is a message
            // that may predate an amend, and this sheet writes over whatever
            // it shows.
            load = model.lastLogged?.weightKg ?? 0
            reps = model.lastLogged?.reps ?? 0
            field = .load
        }
    }
}
