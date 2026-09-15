import OnyxCore
import OnyxUI
import SwiftUI

/// The running workout, minimised — 64 pt above the tab bar.
///
/// ── WHAT IT REPLACES, AND WHY THE OLD ONE COULD NOT BE FIXED ────────────────
/// A full-width "Resume workout" button bound to `WorkoutWeek.State.live(sets:
/// volumeKg:)` — two numbers, re-read from the ledger on every tab refresh. The
/// live `LoggerModel` was already being kept two properties away
/// (`WorkoutTabView.session`), holding the clock, the deck cursor, the records
/// and the same tonnage without a query (F1). So the footer was a second,
/// staler answer to a question the tab could already answer exactly, and no
/// amount of work on the button would have changed that: it was reading the
/// wrong model.
///
/// ── AND WHY A CARD RATHER THAN A BUTTON ─────────────────────────────────────
/// A button says "there is somewhere to go". The thing that is actually true is
/// that a workout is RUNNING — the clock is counting, the rest timer is armed,
/// the Lock Screen is showing it — and the phone should say so on the screen
/// you are standing on. Every music app on this platform solved the same
/// problem the same way, and the shape is worth borrowing: a surface that
/// carries the state, that you can ignore, and that opens the full thing when
/// you want it.
///
/// It lives inside the Train tab's own bottom inset and not above the tab bar
/// app-wide. A cross-tab player would need `session` lifted out of
/// `WorkoutTabView` into `AppEnvironment` — a real change with a real benefit,
/// and not this wave's (see the plan's upgrade path).
struct MiniPlayerCard: View {

    /// The id both ends of the zoom agree on.
    ///
    /// Spelled once, here, because `.matchedTransitionSource(id:in:)` and
    /// `.navigationTransition(.zoom(sourceID:in:))` match on a `Hashable` whose
    /// TYPE has to match as well as its value — two string literals in two
    /// files are two chances to typo a transition that then silently does not
    /// happen, with no build error and nothing in the console.
    static let transitionID = "onyx.miniplayer"

    let model: LoggerModel
    var onOpen: () -> Void

    /// AX5 is not a bigger version of this card — it is a shorter one. See
    /// `compact`.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onOpen) {
            Group {
                if typeSize.isAccessibilitySize { compact } else { full }
            }
            .padding(.horizontal, OnyxSpace.m)
            .padding(.vertical, typeSize.isAccessibilitySize ? OnyxSpace.s : OnyxSpace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            // `minHeight`, never `height`: 64 is the sum of three line boxes at
            // the default size, and SF Pro's real leading lands within a point
            // of it. A fixed height would clip the day the arithmetic is off by
            // one; a minimum draws what it promised and grows if it must.
            .frame(minHeight: 64)
            // ── THE WASH GOES ON BEFORE THE GLASS, AND THAT IS LOAD-BEARING ──
            // `onyxGlass` is `content.background { material }.clipShape(shape)`,
            // so a `.background` applied BEFORE it lands above the material and
            // below the content, clipped by the same shape — one glass level,
            // one wash, no second rounded rectangle to keep in step. Applied
            // after, it would sit BEHIND the material and be blurred into a
            // flat grey, which is `white.opacity(0.1)` arrived at expensively.
            .background { wash }
            .onyxGlass(.tile)
            // `GlassLevel.tile` carries no shadow on purpose — "a shadow under
            // something that has not lifted is just dirt". This card HAS
            // lifted: the tab's scroll content runs underneath it. The values
            // are `.sheet`'s, copied rather than invented, and they stay at the
            // call site so every other tile in the app stays flat.
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        }
        // 0.98 and not the 0.96 default: on a 343 pt card 4 % is 14 pt of
        // horizontal travel, which reads as the card jumping rather than
        // depressing. The footer button it replaces took the same value.
        .onyxPress(scale: 0.98)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            model.isPaused
                ? "Workout paused, \(model.day.label)"
                : "Workout in progress, \(model.day.label)"
        )
        // ── THE VALUE IS THE SAME AT EVERY TYPE SIZE ────────────────────────
        // `compact` drops the day label and the totals row from the SCREEN.
        // They stay here, so the triage costs a sighted reader two facts they
        // can reach in one tap and costs a VoiceOver reader nothing at all.
        //
        // The clock is a frozen string rather than the running `Text(style:)`:
        // a system timer announces once and is stale from the second word.
        .accessibilityValue(spokenValue)
        .accessibilityHint("Opens the logger.")
    }

    // MARK: - The two shapes

    /// Three rows: what this is, what is next, how it is going.
    private var full: some View {
        // `spacing: 0`. A 20 pt line box around 15 pt type already carries ~5 pt
        // of leading, so three stacked boxes read as five points apart with no
        // spacing at all — and any step of the scale on top of that puts the
        // card at 72 and breaks the 64 the founder asked for.
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: OnyxSpace.s) {
                Text(model.day.label)
                    .onyxType(.secondary).fontWeight(.semibold)
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: OnyxSpace.xs)
                elapsed
            }
            nextLine
            totals
        }
    }

    /// AX5: the clock and what is next, and nothing else.
    ///
    /// ── WHY IT DROPS ROWS RATHER THAN GROWING ───────────────────────────────
    /// At AX5 the three roles are ~49 and ~44 pt, and the "Next ·" line alone
    /// takes four lines of a 319 pt width. The honest card is about 300 pt —
    /// 45 % of an SE's screen spent on a bottom inset, over the screen it is
    /// supposed to be a footnote to.
    ///
    /// So it triages. The clock survives because it is the only fact on this
    /// tab with no second home on screen. "Next" survives because it is the
    /// only forward-looking one and the only reason to tap. The day label goes
    /// because `sessionCard` says it 100 pt higher; the totals go because the
    /// logger's own Live Stats face and the Lock Screen both carry the same
    /// three figures. Both stay in `accessibilityValue`.
    ///
    /// A `ViewThatFits` was rejected rather than untried: every candidate here
    /// is full-width by construction and every child carries a
    /// `minimumScaleFactor`, and that combination is exactly what makes
    /// `ViewThatFits` report that the tallest candidate fits — it took the
    /// three-row branch at AX5 and drew three slivers. Branching on the type
    /// size is what the rest of this app does for the same reason.
    private var compact: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            // Leading rather than trailing: a 49 pt label and a 49 pt clock do
            // not share a 319 pt line, and with the label gone there is nothing
            // for the clock to be trailing OF.
            elapsed
            nextLine
        }
        .frame(maxHeight: 200)
    }

    // MARK: - The rows

    /// The session clock — the SAME two cases the Lock Screen card draws, for
    /// the same reason (`WorkoutElapsed`): a running clock is an origin the
    /// system ticks for free, and a paused one is a frozen string, because the
    /// system cannot be told to stop counting.
    ///
    /// `timerOrigin` already has the banked pauses added into it, so the two
    /// surfaces and the logger's own hero count the same seconds.
    ///
    /// The glyph is present in BOTH states and keeps its width in both. A glyph
    /// that appears on pause moves the whole row four points under a reaching
    /// thumb, which is the defect `LoggerHero` records.
    private var elapsed: some View {
        Label {
            Group {
                if model.isPaused {
                    Text(Clock.format(model.elapsed()))
                } else {
                    Text(model.timerOrigin, style: .timer)
                }
            }
            // No `.onyxNumeral()` here: its `contentTransition(.numericText())`
            // is for figures that change because you logged something. A clock
            // changes because time passed, and animating every tick is both
            // noise and a redraw a second.
            .monospacedDigit()
            // A `.timer` text is as wide as its widest reading and no wider, so
            // it grows a digit group at the hour and shunts the day label. The
            // width is reserved and the label yields first — the same pair of
            // defences `WorkoutElapsed` and `LoggerRestCapsule` already take.
            .frame(minWidth: 64, alignment: .trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } icon: {
            Image(systemName: model.isPaused ? "pause.fill" : "stopwatch")
        }
        .onyxType(.secondary)
        .foregroundStyle(model.isPaused ? Color.onyx.textTertiary : Color.onyx.textSecondary)
        .layoutPriority(1)
    }

    /// Where the session goes next.
    ///
    /// ── WHY THE PREFIX IS ITS OWN `Text` ────────────────────────────────────
    /// "Next · Seated Cable Row (Wide Grip)" is 35 characters, and one
    /// interpolated string with a `minimumScaleFactor` truncates from the END
    /// once it bottoms out — which cuts inside the bracket and prints "Seated
    /// Cable Row (Wide…". The catalogue holds the wide and the close grip as
    /// separate movements with separate records, so that ellipsis is a card
    /// that cannot say which of two lifts it means. Splitting the prefix off
    /// and fixing its size gives the NAME every remaining point before anything
    /// is dropped. Visually identical; behaviourally the difference between
    /// losing the grip and losing nothing.
    @ViewBuilder
    private var nextLine: some View {
        if let name = nextName {
            // ── AND THE SPLIT IS ONLY RIGHT WHILE THE LINE IS ONE LINE ──────
            // At AX5 the first shot of this card drew "Next · Single Arm C…" —
            // truncated, with `lineLimit(2)` set and ignored. The cause is the
            // `.fixedSize()` prefix: an HStack is as tall as its tallest child,
            // the prefix is unconditionally one line tall, and the name is
            // therefore given one line's HEIGHT no matter how many lines it is
            // allowed. It could only scale, and scaling bottoms out at 0.7.
            //
            // At an accessibility size it is one `Text` instead, wrapping over
            // the full width — where there is no sibling to pin the height and
            // nothing to protect the name FROM, because two lines at 44 pt hold
            // any movement in the catalogue.
            if typeSize.isAccessibilitySize {
                Text("Next · \(name)")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 0) {
                    Text("Next · ")
                        .foregroundStyle(Color.onyx.textTertiary)
                        .fixedSize()
                    Text(name)
                        .foregroundStyle(Color.onyx.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .onyxType(.caption)
            }
        } else {
            // The same words the Lock Screen uses for the same state, so a
            // finished deck does not have two names depending on which surface
            // you happen to be looking at.
            Text("Session complete")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
                .lineLimit(1)
        }
    }

    /// Sets, tonnage, records — the three figures that answer "how is this
    /// going" without opening anything, and the same three the Lock Screen's
    /// `WorkoutTotals` draws.
    ///
    /// Separate `Text`s rather than one string because the record segment is
    /// gold and the other two are not, and a `Spacer` at the end because five
    /// children with no slack wrap the last one onto a second line inside a
    /// 64 pt card and clip it with no warning.
    private var totals: some View {
        HStack(spacing: OnyxSpace.xs) {
            Text("\(model.completedSets)/\(model.plannedSets) sets")
                .foregroundStyle(Color.onyx.textSecondary)
            separator
            Text("\(OnyxFormat.volume(model.totalVolumeKg)) kg")
                .foregroundStyle(Color.onyx.textSecondary)
            // Zero renders as NOTHING — no separator either. A permanent gold
            // zero is how gold stops meaning a personal record.
            if model.recordCount > 0 {
                separator
                Text("\(model.recordCount) PR")
                    .foregroundStyle(Color.onyx.record)
            }
            Spacer(minLength: 0)
        }
        .onyxType(.caption).onyxNumeral()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var separator: some View {
        Text("·").foregroundStyle(Color.onyx.textTertiary).fixedSize()
    }

    // MARK: - Values

    /// The movement AFTER the one you are standing in front of, falling back to
    /// the one you are standing in front of.
    ///
    /// ── WHY THIS SURFACE MAY READ `nextExercise` AND THE LOCK SCREEN MAY NOT ─
    /// `LoggerModel.nextExercise` is the following MOVEMENT in deck order, and
    /// the Live Activity is forbidden from headlining it: that card also draws
    /// this set's load, its `lastTime` and "Set 3 of 4", all off `currentSet`,
    /// so naming the lift after this one would put two different movements on
    /// one card. This card carries no set at all — a clock, a name and three
    /// session totals — so there is nothing for the following movement to
    /// contradict, and "what is coming" is the useful thing to say about a
    /// workout you have just minimised.
    ///
    /// It is also the caller W1 built the property for and left without one.
    ///
    /// Nil only on the last movement of a finished deck, which is the one state
    /// that reads "Session complete".
    private var nextName: String? {
        model.nextExercise?.name ?? model.currentSet?.exercise.name
    }

    /// The day's own colour, laid over the glass as a two-stop ramp.
    ///
    /// Leading to trailing, not diagonally: on a 343 × 64 box a diagonal IS a
    /// horizontal, and the strong end belongs under the word it is the colour
    /// of — with the weak end under the clock and the figures, which is where
    /// contrast has to survive.
    ///
    /// ── 0.30, AND WHY IT IS NOT THE 0.10–0.12 THE SCREEN GROUND USES ────────
    /// It was 0.18 for one build, reasoning from `OnyxScreenBackground.peak`
    /// and `LoggerHero.bleed`. The shot showed a card that read as plain dark
    /// glass: the day was technically present and said nothing, which is the
    /// whole job it was added to do.
    ///
    /// Those ceilings are about a full-screen wash behind running body text —
    /// "past 12 % the glass above tints towards the day and the set rows go
    /// muddy" is a statement about a screen of set rows. This is a 64 pt card
    /// whose strong end carries one bold 15 pt word in `textPrimary`. A 30 %
    /// indigo over `.ultraThinMaterial` over black is still a dark surface and
    /// white on it stays far above 4.5:1; the constraint that actually binds
    /// here is legibility, and it is not close to binding.
    ///
    /// `dayLabel` and not `day`: the latter answers `textTertiary` for a key it
    /// does not know, and a wash of a 40 % grey is a smudge rather than a
    /// colour. `dayLabel` is the function that promises never to answer it.
    private var wash: some View {
        LinearGradient(
            colors: [
                Color.onyx.dayLabel(model.day.key).opacity(0.30),
                Color.onyx.dayLabel(model.day.key).opacity(0.05),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private var spokenValue: String {
        var parts = [
            "\(Clock.format(model.elapsed())) elapsed",
            nextName.map { "next, \($0)" } ?? "session complete",
            "\(model.completedSets) of \(model.plannedSets) sets",
            "\(OnyxFormat.volume(model.totalVolumeKg)) kilograms",
        ]
        if model.recordCount > 0 { parts.append("\(model.recordCount) personal records") }
        return parts.joined(separator: ". ") + "."
    }
}

#if DEBUG
/// The card's own harness screen — `native-shot.sh mini-player`.
///
/// ── WHY IT IS NOT PHOTOGRAPHED ON `train` ───────────────────────────────────
/// The Train tab's harness seeds a WEEK from the history store, not a session:
/// `WorkoutTabView.session` is nil until somebody taps Start, and a shot cannot
/// tap. The footer's live branch is therefore unreachable from a fixture, and
/// the alternative — teaching the tab to accept a seeded model — would put a
/// test-only initialiser on a production view to photograph a 64 pt card that
/// is perfectly capable of being photographed on its own.
///
/// Both states, one screen, because the pause is the half that has a different
/// clock, a different glyph and a different ink, and a reviewer needs to see
/// them next to each other to tell whether the swap is legible.
struct MiniPlayerHarness: View {
    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.l) {
            Spacer(minLength: 0)
            label("live")
            MiniPlayerCard(model: .previewUpperB(logged: true), onOpen: {})
            label("paused")
            MiniPlayerCard(model: Self.paused, onOpen: {})
            label("no records yet — the gold segment is absent, not zero")
            MiniPlayerCard(model: LoggerModel(day: PlanTemplates.day("onyx5", "cb_b"), phase: .cut), onOpen: {})
        }
        .padding(.horizontal, OnyxSpace.l)
        .padding(.bottom, OnyxSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onyxScreen(.train)
    }

    private static var paused: LoggerModel {
        let model = LoggerModel.previewUpperB(logged: true)
        model.pause()
        return model
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.onyx.textTertiary)
    }
}

#Preview("Mini Player") {
    VStack(spacing: OnyxSpace.l) {
        Spacer()
        MiniPlayerCard(model: .previewUpperB(logged: true), onOpen: {})
        MiniPlayerCard(model: .previewUpperB(logged: true), onOpen: {})
            .environment(\.dynamicTypeSize, .accessibility5)
    }
    .padding(.horizontal, OnyxSpace.l)
    .onyxScreen(.train)
    .preferredColorScheme(.dark)
}
#endif
