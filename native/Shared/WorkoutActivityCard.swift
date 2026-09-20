import SwiftUI
import OnyxCore
import OnyxUI

/// Everything the running workout draws, on every surface ActivityKit offers.
///
/// ── WHY THIS IS NOT IN THE WIDGET EXTENSION WITH ITS CONFIGURATION ──────────
/// It used to be, and the cost was that nothing could look at it. An
/// `ActivityViewContext` can only be made by ActivityKit, so a view that takes
/// one is a view that renders in exactly one place: a real Lock Screen, during
/// a real workout, on a device. Every other screen in this app is photographed
/// by the harness from a fixture and reviewed as a picture; this one was
/// reviewed by reading it, which is how it kept a `Text("ONYX")` through a
/// rename and typed itself in raw points beside thirty faces on the widget
/// scale.
///
/// So the views take the two plain values the context carries — the attributes
/// and the state — and the extension's configuration closures unwrap the
/// context for them. `Shared/` is already compiled into both targets for
/// `OnyxWorkoutAttributes` (see its header), so the app's preview harness can
/// draw the same card the Lock Screen does, from the same code, with no second
/// implementation to drift.

// MARK: - The clock

/// The rest countdown as a range `Text(timerInterval:)` / `ProgressView(timerInterval:)`
/// will accept, or `nil` once it has run out.
///
/// ── WHY THIS IS NOT `Date()...endsAt` INLINE ────────────────────────────────
/// It was, on four surfaces, and every one of them was a crash waiting for the
/// obvious moment. `Text(timerInterval:)` traps on a range whose end is behind
/// its start — "Fatal error: Range requires lowerBound <= upperBound" — and
/// `restEndsAt` is stale by construction on exactly this surface: the phone is
/// LOCKED while the card is being read, so the app is suspended and nothing
/// clears the date at the instant it expires. The next redraw took the whole
/// widget extension down with it.
///
/// `nil` therefore means "the rest is over", and each caller falls back to what
/// it shows when it was never resting — which is the truth at that moment
/// anyway.
///
/// ── WHY `total` MOVES THE LOWER BOUND INTO THE PAST ─────────────────────────
/// With no total the lower bound is `now`, so `ProgressView(timerInterval:)`'s
/// implicit fraction (elapsed / span) is always elapsed-since-render over
/// remaining-time — a denominator that shrinks every time the range is
/// recomputed, so the bar snaps back toward full on every redraw instead of
/// draining. A real denominator needs a lower bound that does not move with
/// `now`: `endsAt − total` is fixed for the life of the rest, so elapsed grows
/// and the span stays put. Both `Text(timerInterval:)` and
/// `ProgressView(timerInterval:)` accept a lower bound in the past — the timer
/// just starts already-elapsed.
func restCountdown(_ endsAt: Date?, total: Int? = nil) -> ClosedRange<Date>? {
    let now = Date()
    guard let endsAt, endsAt > now else { return nil }
    guard let total, total > 0 else { return now...endsAt }
    // A total shorter than what's actually left cannot happen, but must not
    // crash: `ClosedRange` traps on lower > upper, so clamp to `now`.
    let lowerBound = min(endsAt.addingTimeInterval(-Double(total)), now)
    return lowerBound...endsAt
}

/// The bout, as a line: `12:30 · 0.37 km · 5:42 /km`. `nil` when the set on the
/// card is a lift, which is what hands the slot back to `load`.
///
/// ── WHY THE PACE IS DERIVED HERE AND NOT SENT ───────────────────────────────
/// `ContentState` carries the two numbers for the reason that field documents:
/// pace is a ratio, and the surfaces do not all have the width for it. This is
/// the one place the line is composed, so the Lock Screen, the island and the
/// wrist cannot disagree about a rounding — and it is composed out of the two
/// formatters the rest of the app already draws bouts with (`SetFormat.cardio`
/// for the duration and the distance, `CardioMetrics` for the pace), so a
/// session ledger and a Lock Screen cannot disagree either.
///
/// ── AND WHY THERE IS NO DIVIDE TO GUARD HERE ────────────────────────────────
/// There was, in the obvious first draft: `minutes / km` with a zero denominator
/// is `inf`, and the first state EVERY treadmill block is in is a bout that has
/// started and not moved — 0.00 km. `paceMinPerKm` refuses a distance or a
/// duration that is zero, negative or non-finite and answers nil, and
/// `formatPace` refuses a ratio above 100 min/km as a typo. Both already
/// existed; re-deriving either here would be a second opinion about the same
/// arithmetic.
///
/// `pace: false` is the 40 mm Smart Stack's: three components at figure(15) is
/// ~210 pt of a ~150 pt face, and the pace is the one of the three that can be
/// re-derived by eye from the other two.
func cardioLine(sec: Int?, km: Double?, pace: Bool = true) -> String? {
    guard let line = SetFormat.cardio(
        durationSec: sec.map(Double.init), distanceKm: km, incline: nil, elevationM: nil
    ) else { return nil }
    guard pace else { return line }
    let text = CardioMetrics.formatPace(CardioMetrics.paceMinPerKm(
        distanceM: km.map { $0 * 1000 }, durationMin: sec.map { Double($0) / 60 }
    ))
    // `formatPace` answers "—" for a ratio it will not stand behind. An em dash
    // is a fact in a table column and noise on a Lock Screen, so the component
    // is dropped rather than drawn empty.
    return text == "—" ? line : "\(line) · \(text)"
}

// MARK: - The Lock Screen

/// The card on the Lock Screen and in the Notification Centre.
///
/// ── IT USED TO BE TWO COLUMNS, AND THE CHART OWNED ONE OF THEM ──────────────
/// A 86 pt sparkline sat in the trailing column for the whole card's height,
/// which cost the leading column a third of the width it needed for the one
/// thing this surface is read for — the movement in front of you and what it
/// asks. Full-width BANDS instead, in the order the questions are asked: what
/// is running, how it is going, what is next, the shape of it, and (only while
/// the clock runs) the controls for the rest. The chart is centred and short
/// because it is the least urgent of the five, not because it is unimportant.
///
/// ── AND THE CLOCK AT THE TOP IS THE SESSION'S ───────────────────────────────
/// It used to switch to the rest countdown, so the one number that was always
/// on the card sometimes meant "eleven minutes into the workout" and sometimes
/// "eleven seconds until the next set". Two facts through one slot, distinguished
/// by a glyph. The rest clock has its own band now, and this reads total elapsed
/// always.
struct WorkoutLockCard: View {
    let title: String
    let startedAt: Date
    let state: OnyxWorkoutAttributes.ContentState

    private var accent: Color { Color.onyx.day(state.dayKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // The mark, carrying the split's colour, IS the dot that used to
                // sit here — a filled circle said "this app has a colour", the
                // ring says which app.
                OnyxMark(size: 11, tint: accent, opacity: 1)
                Text(title.uppercased())
                    .font(OnyxWidgetType.label(10, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .layoutPriority(1)
                // ── THE MUSCLE TAG SITS AFTER THE SESSION TITLE ─────────────
                // Decision 4, and the header is where it belongs on width as
                // well as on sense. "DELTS & ARMS" is ~105 pt and the clock
                // ~62 of a 328 pt row, so this is the one band on the card with
                // a hundred points spare — every other row is already carrying
                // a 28-character movement name or four 34 pt controls.
                //
                // Beside the SESSION it also reads correctly: the split and the
                // muscle are both facts about what today is for, and the tag
                // under a movement name was answering a question the movement
                // name had already answered.
                WorkoutMuscleTag(token: state.primaryMuscle)
                Spacer(minLength: 4)
                WorkoutElapsed(state: state, startedAt: startedAt)
            }
            WorkoutTotals(state: state)
            WorkoutCurrentSet(state: state)
            // `total:` is what gives the bar a denominator — see `restCountdown`.
            // Without it the range was rebased to `now` on every redraw and the
            // fill snapped back toward full instead of draining.
            if let countdown = restCountdown(state.restEndsAt, total: state.restTotalSec) {
                WorkoutRestBand(countdown: countdown, state: state, showsSkip: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - The wrist

/// The Smart Stack card (`.small` activity family).
///
/// Four lines, all of them full words — no abbreviations, which is the entire
/// lesson of "Onyx 1/2 75x13": before watchOS 11 the Smart Stack mirrored the
/// Dynamic Island's two ~44 pt compact slots onto a face with room for four
/// lines.
struct WorkoutWatchCard: View {
    let title: String
    let state: OnyxWorkoutAttributes.ContentState

    private var accent: Color { Color.onyx.day(state.dayKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(OnyxWidgetType.hero(13))
                .foregroundStyle(accent)
                .lineLimit(1)
            Text(state.exercise)
                .font(OnyxWidgetType.label(12, weight: .medium))
                .foregroundStyle(Color.onyx.textPrimary)
                .lineLimit(2)
            if let countdown = restCountdown(state.restEndsAt, total: state.restTotalSec) {
                Text(timerInterval: countdown, countsDown: true)
                    .font(OnyxWidgetType.figure(16))
                    // The MOVEMENT's colour, not the split's — the same rule
                    // the Lock Screen's band follows. See `WorkoutRestBand`.
                    .foregroundStyle(WorkoutMuscleTag.tint(state.primaryMuscle) ?? accent)
            } else if let bout = cardioLine(
                // No pace on this face: three components at figure(15) measure
                // ~210 pt of a 40 mm card's ~150, and this is the surface whose
                // whole lesson is "Onyx 1/2 75x13" — a line that has to be
                // abbreviated to fit is a line that should have been shorter.
                sec: state.cardioElapsedSec, km: state.cardioDistanceKm, pace: false
            ) {
                Text(bout)
                    .font(OnyxWidgetType.figure(15))
                    .foregroundStyle(Color.onyx.cardio)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if !state.load.isEmpty {
                Text(state.load)
                    .font(OnyxWidgetType.figure(15))
                    .foregroundStyle(Color.onyx.textPrimary)
            }
            Text("\(state.setsDone)/\(state.setsPlanned) sets · \(state.volume)")
                .font(OnyxWidgetType.label(10, weight: .medium))
                .foregroundStyle(Color.onyx.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

// MARK: - Pieces

/// TOTAL WORKOUT TIME — how long this session has been running, and nothing
/// else. Never the rest clock: that has its own band now (`WorkoutRestBand`),
/// and one slot that meant two different durations depending on a glyph is
/// exactly the confusion this replaces.
///
/// ── WHY IT IS TWO CASES ─────────────────────────────────────────────────────
/// `Text(_:style:.timer)` is counted by the SYSTEM, which is why a clock on a
/// Lock Screen card is affordable at all: ActivityKit budgets updates and this
/// one spends none. What the system cannot do is STOP it. So a running session
/// is an origin — `state.timerOrigin`, already moved forward by whatever has
/// been banked in pauses — and a paused one is the frozen string the phone
/// computed, drawn beside a pause glyph so the reading is not mistaken for a
/// clock that has died.
struct WorkoutElapsed: View {
    let state: OnyxWorkoutAttributes.ContentState
    /// The activity's own fixed start, and the fallback for a card that was
    /// encoded before `timerOrigin` existed — see `ContentState.timerOrigin`.
    let startedAt: Date

    var body: some View {
        Group {
            if state.isPaused == true {
                Label {
                    Text(state.elapsed ?? "")
                } icon: {
                    Image(systemName: "pause.fill")
                }
                .foregroundStyle(Color.onyx.textTertiary)
            } else {
                Label {
                    Text(state.timerOrigin ?? startedAt, style: .timer)
                } icon: {
                    Image(systemName: "stopwatch")
                }
                .foregroundStyle(Color.onyx.textSecondary)
            }
        }
        .font(OnyxWidgetType.figure(12))
        .monospacedDigit()
        // A `.timer` text is as wide as its widest reading and no wider, so it
        // grows a digit at the hour and shunts the title. Reserved.
        .frame(minWidth: 62, alignment: .trailing)
        .lineLimit(1)
        .accessibilityLabel("Total workout time")
    }
}

/// The rest period: how long is left, how much of it has gone, and the three
/// things you can do about it.
///
/// ── WHY THE BAR IS A `ProgressView(timerInterval:)` ─────────────────────────
/// It is drawn and advanced by the SYSTEM from a date range, exactly as
/// `Text(timerInterval:)` is — so a bar that visibly empties over ninety
/// seconds costs the same number of ActivityKit updates as a static rectangle,
/// which is none. Computing a fraction on the producer would have needed an
/// update per tick, and ActivityKit rations precisely that.
///
/// The range is validated by `restCountdown(_:)` at every call site for the
/// reason that function documents: a reversed range traps, and `restEndsAt` is
/// stale by construction on a locked phone.
struct WorkoutRestBand: View {
    let countdown: ClosedRange<Date>
    let state: OnyxWorkoutAttributes.ContentState
    /// The Lock Screen keeps Skip; the expanded Dynamic Island does not have the
    /// width for four controls and drops it — the phone in your hand has the
    /// same button 110 pt down the card.
    var showsSkip: Bool = true

    /// The MOVEMENT's colour, falling back to the split's.
    ///
    /// ── WHY THE REST CLOCK IS NOT THE DAY COLOUR ────────────────────────────
    /// The split's hue is already the card's identity — the mark, the title and
    /// the keyline all carry it, and it is the same colour for every one of a
    /// session's twenty rests. The thing that actually CHANGES between them is
    /// which movement you are resting before, and the palette already has a
    /// hue per muscle that the deck, the body figure and this card's own tag
    /// are drawn in. Tinting the band with it makes the one element that moves
    /// also the one element that says what it is moving for (decision 4).
    ///
    /// The whole band takes it rather than the bar alone: the nudges and the
    /// skip sit inside the same 34 pt run, and two accents across four controls
    /// reads as a colour that failed to apply rather than as a distinction.
    ///
    /// Falls back to the day on a bout (no mover) and on a card encoded before
    /// `primaryMuscle` existed.
    private var accent: Color {
        WorkoutMuscleTag.tint(state.primaryMuscle) ?? Color.onyx.day(state.dayKey)
    }

    var body: some View {
        HStack(spacing: 8) {
            nudge(-15, "minus", "Take 15 seconds off the rest")
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(timerInterval: countdown, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(accent)
                // ── THE READING ROW, UNDER THE BAR ──────────────────────────
                // The countdown and the heart rate together, because they are
                // both READINGS and the four things either side of them are
                // CONTROLS.
                //
                // ── AND WHY THE HEART IS NOT OUT THERE WITH THEM ────────────
                // It was, for one build: a red element standing between the
                // teal `+` circle and the teal skip circle, in the exact slot
                // the Lock Screen puts a button. At arm's length that reads as
                // a control that failed to render, not as your pulse — which
                // is the "colour that failed to apply" failure this band's own
                // `accent` note already records once. Inside the bar's column
                // it is unambiguously a number.
                HStack(spacing: 6) {
                    Text(timerInterval: countdown, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(accent)
                    if let bpm = state.bpm {
                        // ── RED ON THE GLYPH, ORDINARY INK ON THE NUMBER ────
                        // A red NUMERAL beside teal ones reads as a value in a
                        // bad state, and on a card that also carries a gold
                        // `2 PR` the eye has no reason to read it as a
                        // measurement. The glyph is what says "heart" — the
                        // strongest convention on the platform, and the half
                        // that survives the accented and vibrant rendering
                        // modes, because the meaning is in the shape.
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(Color.onyx.danger)
                            Text("\(bpm)")
                                .monospacedDigit()
                                .foregroundStyle(Color.onyx.textPrimary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Heart rate")
                        .accessibilityValue("\(bpm) beats per minute, from your watch")
                    }
                }
                .font(OnyxWidgetType.figure(11))
                .lineLimit(1)
            }
            nudge(15, "plus", "Add 15 seconds to the rest")
            if showsSkip { WorkoutSkipRest(dayKey: state.dayKey, compact: true, tint: accent) }
        }
        .accessibilityElement(children: .contain)
    }

    /// 34 × 34 rather than 44: four controls at 44 do not fit the expanded
    /// Dynamic Island's bottom region beside a progress bar, and this is the one
    /// place in the app where the alternative is not a smaller target but no
    /// control at all. The Lock Screen draws the same size so the two surfaces
    /// are one control in two places.
    private func nudge(_ seconds: Int, _ glyph: String, _ label: String) -> some View {
        Button(intent: RestNudgeIntent(seconds: seconds)) {
            Image(systemName: glyph)
                .font(OnyxWidgetType.label(12, weight: .black))
                .foregroundStyle(accent)
                // `.frame` BEFORE `.background`, always. The other order sizes
                // the shape to the glyph and then draws the frame around it, so
                // the capsule is a circle behind a plus sign with its corners
                // outside the padded box — which is what clipped the bottom of
                // these buttons in the Dynamic Island.
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The Dynamic Island's compact TRAILING slot — whichever number is the
/// answer right now.
///
/// ── WHY IT IS A VIEW IN `Shared/` AND NOT FOUR BRANCHES IN THE ISLAND ───────
/// It was four branches in `OnyxWidgets.swift` and a COPY of three of them in
/// `WidgetPreviews.islandCompact`, which is the app's contact sheet for this
/// surface. The copy is documented there as a stand-in "free to drift", and it
/// did: W4 added the heart rate to the real slot and the photograph of that
/// slot kept showing the load, so the shot reviewed the harness rather than
/// the shipped code — and a shot that reviews a stand-in is the failure this
/// whole file's header is about.
///
/// The expanded island and the Lock Screen already avoid this by being made of
/// `Shared/` views taking plain values. This is that treatment applied to the
/// one region that had not had it.
///
/// ── THE ORDER IS "WHAT IS THE QUESTION RIGHT NOW" ───────────────────────────
/// Resting, it is the countdown. Walking, it is the bout's clock. Under the
/// bar it is the heart rate (W4, decision 4) — the one reading you cannot see
/// — and only with no watch speaking does it fall back to the load, which is
/// a number you are holding.
///
/// ~44 pt, reserved and monospaced on every branch: this slot has no room to
/// grow, and proportional digits re-measure it on every tick, which shunts the
/// mark beside it.
struct WorkoutCompactTrailing: View {
    let state: OnyxWorkoutAttributes.ContentState

    var body: some View {
        Group {
            if let countdown = restCountdown(state.restEndsAt, total: state.restTotalSec) {
                Text(timerInterval: countdown, countsDown: true)
                    .monospacedDigit()
                    .frame(minWidth: 44, maxWidth: 44, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // The timer wears the MOVEMENT's colour on every surface —
                    // see `WorkoutRestBand.accent`.
                    .foregroundStyle(
                        WorkoutMuscleTag.tint(state.primaryMuscle) ?? Color.onyx.day(state.dayKey)
                    )
            } else if let sec = state.cardioElapsedSec {
                // ── A REAL BRANCH, BECAUSE THE FALLBACK CANNOT ──────────────
                // The `else` below is string surgery on a load the producer
                // composed ("42.5 kg × 12" minus its unit), and a bout has no
                // " kg " in it to cut — it would print the whole line into a
                // ~44 pt slot. The bout's own clock is the one number that
                // fits, and it is the axis a treadmill block is prescribed in.
                Text(SetFormat.clock(Double(sec)))
                    .monospacedDigit()
                    .frame(minWidth: 44, maxWidth: 44, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.onyx.cardio)
            } else if let bpm = state.bpm {
                // Red on the glyph, ordinary ink on the number — the rule
                // `WorkoutRestBand`'s reading row states at length.
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill").foregroundStyle(Color.onyx.danger)
                    Text("\(bpm)").monospacedDigit().foregroundStyle(Color.onyx.textPrimary)
                }
                .frame(minWidth: 44, maxWidth: 44, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Heart rate")
                .accessibilityValue("\(bpm) beats per minute, from your watch")
            } else {
                Text(state.load.replacingOccurrences(of: " kg ", with: ""))
                    .foregroundStyle(Color.onyx.day(state.dayKey))
            }
        }
        .font(OnyxWidgetType.figure(12))
    }
}

/// Tonnage, sets done against planned, and records — the three numbers that
/// answer "how is this session going" without opening anything.
struct WorkoutTotals: View {
    let state: OnyxWorkoutAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            stat(state.volume, Color.onyx.day(state.dayKey))
            stat("\(state.setsDone)/\(state.setsPlanned) sets", Color.onyx.textPrimary)
            // Zero renders as NOTHING. A permanent gold zero is how gold stops
            // meaning a personal record.
            if state.prsThisSession > 0 {
                stat("\(state.prsThisSession) PR", Color.onyx.record)
            }
        }
    }

    private func stat(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(OnyxWidgetType.figure(12))
            .foregroundStyle(color)
    }
}

/// The set you are standing in front of. The card LEADS with this: history used
/// to be the largest thing on the face while the current set went unnamed.
struct WorkoutCurrentSet: View {
    let state: OnyxWorkoutAttributes.ContentState

    /// Resting AND there is something to rest before. Both halves matter: the
    /// last set of a session is a rest with no next lift, and naming a blank
    /// one would be worse than naming the set just finished.
    ///
    /// `nextExercise` is only on the wire at a MOVEMENT BOUNDARY — see
    /// `LoggerModel.restBoundaryExercise` — so this is false for the rest
    /// between two sets of the same lift, which is most of them.
    private var showsNext: Bool {
        state.restEndsAt != nil && !(state.nextExercise ?? "").isEmpty
    }

    /// ── THE HEADLINE IS THE CURRENT LIFT, ALWAYS ────────────────────────────
    /// It used to be `state.nextExercise ?? state.exercise`, which was safe only
    /// because the producer sent the two as the SAME string (F3): "NEXT" was a
    /// chip in front of the lift you were already doing. Now that the wire
    /// carries a real next-in-deck (A7), swapping the headline for it would put
    /// the following movement's NAME above this movement's load, `lastTime` and
    /// "Set 3 of 4" — one card, two lifts.
    ///
    /// So the name never moves, and the change of subject gets its own line
    /// below it, which is also what let the muscle tag come up beside the name
    /// and buy that line back.
    private var name: String { state.exercise }

    /// The one line under the name: where you are, or where you are going.
    ///
    /// They are mutually exclusive in time and they answer the same question,
    /// so they share a slot rather than each taking a row off a card that has
    /// four. "Next · …" only appears at a movement boundary (`showsNext`), and
    /// the set position is what the line says the rest of the time.
    @ViewBuilder
    private var context: some View {
        if showsNext, let next = state.nextExercise {
            // ── 13 pt SEMIBOLD, NOT A 9 pt TRACKED-OUT CHIP ─────────────────
            // The chip was a register label at the floor of the scale and it
            // carried no information — the name beside it was the whole
            // message, and that name was wrong (F3). A line that NAMES the next
            // movement is a fact worth reading at arm's length, so it is set
            // one step above the card's smallest type and in the split's own
            // colour, which is the channel that says "this is a different lift
            // from the one above".
            Text("Next · \(next)")
                .font(OnyxWidgetType.label(13, weight: .semibold))
                .foregroundStyle(Color.onyx.day(state.dayKey))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if !state.setLabel.isEmpty {
            Text(state.setLabel)
                .font(OnyxWidgetType.label(9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.onyx.textTertiary)
                .lineLimit(1)
        }
    }

    var body: some View {
        // ── TWO COLUMNS, AND THE NUMBERS ARE THE NARROW ONE ─────────────────
        // It was four stacked rows — name, muscle tag, load + RPE — down the
        // full width, with the right two thirds of the last two rows empty.
        // The load and the rating are a fixed ~110 pt between them and they are
        // read as a pair, so they go to a trailing column and the name gets the
        // rest. That is the row the muscle tag moved up into, and the row the
        // "Next · …" line now stands in (decision 4).
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // ── WHY IT SHRINKS RATHER THAN TRUNCATES ────────────────
                    // "Seated Cable Row (Wide Grip)" is 28 characters and the card
                    // is 360 pt wide with a sparkline in the other column, so a
                    // plain `lineLimit(1)` cut it at "Seated Cable Row (Wide…" —
                    // dropping the grip. The catalogue deliberately holds the wide
                    // and close grips as SEPARATE movements with separate records,
                    // so a card that ends at the bracket is a card that cannot tell
                    // you which of the two you are on.
                    Text(name)
                        // ── THE NAME IS THE HEADLINE NOW ────────────────────────
                        // It was 12 pt, one line among four, beside a chart. On a
                        // locked phone at arm's length the question is "what am I
                        // about to lift", and the answer was the smallest readable
                        // thing on the card. 16 pt semibold is what the sparkline's
                        // band paid for.
                        .font(OnyxWidgetType.label(16, weight: .semibold))
                        .foregroundStyle(Color.onyx.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    // ── AND THE MUSCLE TAG IS NOT ON THIS ROW ───────────────
                    // It was, for one build, and the screenshot killed it: the
                    // capsule measures ~100 pt of a ~200 pt leading column,
                    // which left the name ~95 pt and drew "Seated Cable Row (…".
                    // That is the precise failure the paragraph above exists
                    // about — the catalogue holds the wide and the close grip
                    // as separate movements with separate records, so a name
                    // that ends at the bracket cannot say which you are on.
                    //
                    // No arrangement of layout priorities fixes it, because the
                    // row genuinely lacks the width: a 28-character name at
                    // 16 pt is ~200 pt on its own. The tag moved UP to the
                    // card's own header beside the session title, which is the
                    // one row on this surface carrying a hundred points of
                    // slack — and is what decision 4 asks for in so many words.
                }
                context
            }
            Spacer(minLength: 0)
            // ── THE NUMBERS, RIGHT-ALIGNED AND STACKED ──────────────────────────
            // Trailing alignment rather than leading: the load and the rating have
            // different widths ("42.5 kg × 12" over "RPE 8.5"), and a ragged right
            // edge against the card's own right edge is what reads as a column.
            VStack(alignment: .trailing, spacing: 3) {
                // ── A BOUT TAKES THE LOAD'S SLOT, FOUR POINTS SMALLER ───────
                // It IS this set's content — the same question "42.5 kg × 12"
                // answers — and `load` is empty while it is on the wire, so the
                // two can never both draw. The size is width, not hierarchy:
                // `12:30 · 0.37 km · 5:42 /km` is ~26 characters against the
                // ~12 of a load, and the column only has the room because the
                // name beside it is "Treadmill" rather than a 28-character
                // movement. The scale floor is what covers the bout that runs
                // past an hour.
                if let bout = cardioLine(sec: state.cardioElapsedSec, km: state.cardioDistanceKm) {
                    Text(bout)
                        .font(OnyxWidgetType.figure(13))
                        .foregroundStyle(Color.onyx.cardio)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if !state.load.isEmpty {
                    Text(state.load)
                        .font(OnyxWidgetType.figure(17))
                        .foregroundStyle(Color.onyx.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                // ── THE RATING WEARS THE EFFORT RAMP ────────────────────────
                // It was secondary ink, which made a 9.5 and a 6 the same
                // colour on a surface read at arm's length. `Color.onyx.effort`
                // is the SAME function the effort picker's gradient is built
                // from, so the badge and the sheet that wrote it cannot drift —
                // and it degrades honestly: a card encoded before `rpeValue`
                // existed has no number, and falls back to the ink it had.
                if !state.rpe.isEmpty {
                    Text(state.rpe)
                        .font(OnyxWidgetType.figure(11))
                        .foregroundStyle(
                            state.rpeValue.map { Color.onyx.effort($0) } ?? Color.onyx.textSecondary
                        )
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(
                            (state.rpeValue.map { Color.onyx.effort($0) } ?? Color.onyx.textSecondary)
                                .opacity(0.16),
                            in: Capsule()
                        )
                }
            }
            // ── AND `prev …` IS GONE ────────────────────────────────────────────
            // The founder's call, and the space it freed is the chart's. The word
            // was doing the work of a label for a fact the surface can only be
            // showing about the past: the card names the lift and then a second,
            // smaller load underneath it. `lastTime` is still on the wire and still
            // drawn where there is room to say what it is — it was never the number
            // that was wrong, only the four characters in front of it and the line
            // they cost.
        }
        // One element to VoiceOver, in the order the eye reads it: the two
        // columns are a layout, not two facts, and swiping through five
        // fragments to assemble "Seated Cable Row, upper back, 42.5 kg by 12,
        // RPE 8" is worse than being told it.
        .accessibilityElement(children: .combine)
    }
}

/// The movement's primary muscle, as the deck draws it.
///
/// ── WHY IT RESOLVES THE TOKEN HERE ──────────────────────────────────────────
/// `ContentState.primaryMuscle` is a `LandmarkMuscle.token` on the wire, so the
/// hue comes from `Color.onyx.muscle` — the same function the card's rail, the
/// legend dot and the body figure read. A colour sent over the wire would be
/// frozen at whatever the palette was when the activity started, which is the
/// mistake `dayKey` already documents.
///
/// A bout carries the literal `cardio`: there is no mover to name, and the
/// alternative — an empty slot on a treadmill block — reads as a card that
/// failed to load rather than as a movement with no muscle.
struct WorkoutMuscleTag: View {
    let token: String?

    /// The token's label and hue, or nil when there is no mover to name.
    ///
    /// `static` because the COLOUR half has a second reader: the rest timer is
    /// tinted by the movement's muscle rather than by the split (decision 4),
    /// and the alternative was `Color.onyx.muscle(LandmarkMuscle.from(token:))`
    /// spelled out at four call sites — each of them free to forget the
    /// `cardio` literal, which is not a `LandmarkMuscle` and would resolve to
    /// nothing on a treadmill block.
    static func resolve(_ token: String?) -> (label: String, tint: Color)? {
        guard let token, !token.isEmpty else { return nil }
        if let muscle = LandmarkMuscle.from(token: token) {
            return (muscle.displayName, Color.onyx.muscle(muscle))
        }
        return token == "cardio" ? ("Cardio", Color.onyx.cardio) : nil
    }

    /// The movement's own hue, or nil — so a caller can fall back to the day.
    ///
    /// Nil rather than a default, because the two callers fall back
    /// differently: the tag draws NOTHING without a mover, and the rest timer
    /// falls back to `Color.onyx.day(dayKey)`.
    static func tint(_ token: String?) -> Color? { resolve(token)?.tint }

    private var resolved: (label: String, tint: Color)? { Self.resolve(token) }

    var body: some View {
        if let resolved {
            Text(resolved.label.uppercased())
                .font(OnyxWidgetType.label(9, weight: .black))
                .tracking(0.8)
                .foregroundStyle(resolved.tint)
                .padding(.horizontal, 5)
                .frame(height: 14)
                .background(resolved.tint.opacity(0.16), in: Capsule())
        }
    }
}

/// The rest-skip button (§9, decision 16).
///
/// 44 pt on both surfaces it appears on, including the expanded Dynamic Island
/// — that region has the height, and a 32 pt target there would have been the
/// only sub-HIG control in the app.
struct WorkoutSkipRest: View {
    let dayKey: String
    /// Glyph only, sized to sit in the rest band beside the two nudges. The
    /// worded capsule is still what a region with a whole row to itself draws.
    var compact: Bool = false
    /// The band's own ink, when this button is standing IN one.
    ///
    /// `WorkoutRestBand` is tinted by the movement's muscle rather than by the
    /// split (see its `accent`), and a skip button that kept the day colour
    /// would be the one control in a run of four wearing a different hue — which
    /// reads as a colour that failed to apply, not as a distinction. Nil is the
    /// standalone case, which is still the split's.
    var tint: Color?

    private var accent: Color { tint ?? Color.onyx.day(dayKey) }

    var body: some View {
        Button(intent: RestSkipIntent()) {
            Group {
                if compact {
                    Image(systemName: "forward.fill")
                        .font(OnyxWidgetType.label(12, weight: .black))
                        .frame(width: 34, height: 34)
                } else {
                    Label("Skip rest", systemImage: "forward.fill")
                        .font(OnyxWidgetType.label(12, weight: .bold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                }
            }
            .foregroundStyle(accent)
            // `.frame` before `.background` — see `WorkoutRestBand.nudge`.
            .background(accent.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Skip rest")
        .accessibilityHint("Ends the rest timer and moves on to the next set")
    }
}

/// ── THE SPARKLINE IS GONE ──────────────────────────────────────────────────
/// `WorkoutSpark` drew the session's cumulative tonnage as a line, 26 pt across
/// the Lock Screen card and 76×30 in the island. Cumulative tonnage is
/// monotonic: it has exactly one shape, going up, on every session anyone has
/// ever logged — so the chart could not distinguish a good session from a bad
/// one, and it was spending the card's best horizontal band to say so while the
/// exercise NAME sat at 12 pt. The name is what a glance at a locked phone is
/// for. Removed, and the space went to it.
///
