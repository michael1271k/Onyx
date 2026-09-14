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
                Spacer(minLength: 4)
                WorkoutElapsed(state: state, startedAt: startedAt)
            }
            WorkoutTotals(state: state)
            WorkoutCurrentSet(state: state)
            if let countdown = restCountdown(state.restEndsAt) {
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
                .foregroundStyle(.white)
                .lineLimit(2)
            if let countdown = restCountdown(state.restEndsAt) {
                Text(timerInterval: countdown, countsDown: true)
                    .font(OnyxWidgetType.figure(16))
                    .foregroundStyle(accent)
            } else if !state.load.isEmpty {
                Text(state.load)
                    .font(OnyxWidgetType.figure(15))
                    .foregroundStyle(.white)
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

    private var accent: Color { Color.onyx.day(state.dayKey) }

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
                Text(timerInterval: countdown, countsDown: true)
                    .font(OnyxWidgetType.figure(11))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }
            nudge(15, "plus", "Add 15 seconds to the rest")
            if showsSkip { WorkoutSkipRest(dayKey: state.dayKey, compact: true) }
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
    private var showsNext: Bool {
        state.restEndsAt != nil && !(state.nextExercise ?? "").isEmpty
    }

    /// `currentSet` is the first UNTICKED row, so while you are resting the
    /// card is already naming the set you are about to do. The only thing that
    /// changes here is that it says so — and adds what that lift cost last
    /// time, which is the decision the rest period is actually for.
    private var name: String { state.nextExercise ?? state.exercise }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // `NEXT` rather than a different colour or a smaller name: the
                // card changes SUBJECT here, and a label is the only channel
                // that says so unambiguously at a glance on a locked screen.
                if showsNext {
                    Text("NEXT")
                        .font(OnyxWidgetType.label(9, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(Color.onyx.day(state.dayKey))
                }
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
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !showsNext, !state.setLabel.isEmpty {
                    Text(state.setLabel)
                        .font(OnyxWidgetType.label(9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.onyx.textTertiary)
                }
            }
            // What this movement is FOR, under its name — the deck's own chip,
            // in the deck's own hue, on the one surface that never had it.
            WorkoutMuscleTag(token: state.primaryMuscle)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !state.load.isEmpty {
                    Text(state.load)
                        .font(OnyxWidgetType.figure(17))
                        .foregroundStyle(.white)
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
            // ── AND `prev …` IS GONE ────────────────────────────────────────
            // The founder's call, and the space it freed is the chart's. The
            // word was doing the work of a label for a fact the surface can
            // only be showing about the past: the card names the NEXT lift and
            // then a second, smaller load underneath it. `lastTime` is still on
            // the wire and still drawn where there is room to say what it is —
            // it was never the number that was wrong, only the four characters
            // in front of it and the line they cost.
        }
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

    private var resolved: (label: String, tint: Color)? {
        guard let token, !token.isEmpty else { return nil }
        if let muscle = LandmarkMuscle.from(token: token) {
            return (muscle.displayName, Color.onyx.muscle(muscle))
        }
        return token == "cardio" ? ("Cardio", Color.onyx.cardio) : nil
    }

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
            .foregroundStyle(Color.onyx.day(dayKey))
            // `.frame` before `.background` — see `WorkoutRestBand.nudge`.
            .background(Color.onyx.day(dayKey).opacity(0.16), in: Capsule())
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
