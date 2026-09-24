import SwiftUI
import OnyxUI
import OnyxCore

/// Which face of the logger is showing.
enum LoggerFace: String, CaseIterable, Identifiable {
    case workout, stats

    var id: String { rawValue }
    /// "Train", not "Workout", since 2026-09-07: the tab this deck belongs to
    /// is called Train, and a segmented control naming the other word inside it
    /// is the app calling one thing two names on one screen.
    var title: String { self == .workout ? "Train" : "Live Stats" }
    var index: Int { self == .workout ? 0 : 1 }
}

/// The face, and how it got here.
///
/// The two facts travel together because the ANIMATION is a property of the
/// change and not of the state: the same face arrived at by tapping a segment
/// and by throwing one should not move the same way. Carrying `flicked` beside
/// `face` is what lets the hero and the pages agree on that without either of
/// them owning a spring the other has to be told about.
struct LoggerFaceSelection: Equatable {
    var face: LoggerFace = .workout
    /// The one case that earns overshoot: a finger supplied the energy.
    var flicked = false

    /// Critically damped unless the gesture threw it. §*Designing Fluid
    /// Interfaces*: momentum has to have come from somewhere.
    var animation: Animation { flicked ? OnyxMotion.flick : OnyxMotion.move }
}

/// The top of the live logger: which workout, how long you have been in it, and
/// the switch between its two faces.
///
/// ── WHAT IT REPLACED ────────────────────────────────────────────────────────
/// A 44 pt totals strip under a system navigation title. The strip printed
/// tonnage, sets and records — three numbers you read once a set — in the space
/// above the set you were logging, and the title said "Upper B" in 17 pt inline
/// text that could not carry the day's colour. The three numbers moved to the
/// Live Stats face, where they have room to say what they are, and what is left
/// here is the two things you actually read mid-session: which workout, and how
/// long it has been.
///
/// ── THE HEIGHT IS THE DESIGN ────────────────────────────────────────────────
/// 132 pt is the ceiling and the whole band comes in under it at the default
/// text size: a 28 pt title, a 15 pt sub line with the week chip, and the clock
/// on the same row as both. Stacking the clock UNDER the title reads better and
/// costs 40 pt the deck does not have, so it happens only at an accessibility
/// size, where the title has taken the width anyway.
struct LoggerHero: View {
    @Environment(AppEnvironment.self) private var environment
    let day: ProgramDay
    let clock: any PauseControlling
    @Binding var selection: LoggerFaceSelection
    /// Tapping the clock opens `TimerSheet`.
    let onTimer: () -> Void
    /// Set when the deck is re-opened on a finished session (§U4.5) — the hero
    /// then states WHEN rather than HOW LONG SO FAR.
    var editing: LoggerModel.EditContext?
    /// The phase the day is being run at, and the way to change it.
    ///
    /// The chip REPLACES the `Phase` fast-action chip that used to sit under the
    /// tabs. It is the same sheet: the founder's note deletes the chip, not the
    /// ability to switch phase, and a tag that states the phase is a better home
    /// for the verb than a chip that only ever said the word.
    var phase: ProgramPhase = .cut
    var onPhase: () -> Void = {}
    /// The rest countdown, ALREADY validated by `restCountdown(_:)` at the call
    /// site — `Text(timerInterval:)` traps on a range that has already ended.
    ///
    /// It lives here rather than under the hero because it used to cost a full
    /// row of its own between the tabs and the deck, which is the row the
    /// founder asked back. In the trailing column it costs nothing: the clock's
    /// column is 34 pt of number over empty space the rest of the session.
    var restCountdown: ClosedRange<Date>?
    var onSkipRest: () -> Void = {}
    var onAdjustRest: (TimeInterval) -> Void = { _ in }
    /// The wrist's heart rate, if a watch has sent one recently (W10).
    ///
    /// Passed in rather than read off `environment.watchBridge` here, for the
    /// reason every other figure on this band is passed in: the hero is drawn
    /// by the previews and by the screenshot harness with no bridge at all, and
    /// a band that reached for one would be a band that could only be
    /// photographed from a running app. `PhoneWatchBridge.liveBpm` has already
    /// aged the number out; nil means "no wrist, or nothing recent".
    var liveBpm: Int?

    @Environment(\.dynamicTypeSize) private var typeSize

    private var accent: Color { Color.onyx.day(day.key) }

    /// "Week 8". The session's own week, never today's.
    ///
    /// ── THE LOGICAL DAY, NOT THE INSTANT ────────────────────────────────────
    /// A live deck has only an instant to go on and `LogicalDay.iso` is the
    /// right reading of it. An edited session has a stored `date` — its LOGICAL
    /// day, as the day it was logged in decided — and that is the one to use:
    /// `started_at` is a UTC instant, and re-reading it through the phone's
    /// current time zone puts a 17:00 session on the next day for every reader
    /// east of the meridian. The first shot of this hero said "Wed, 2 Sep" over
    /// a session whose own summary page, ten points above, said "Tue, 1 Sep".
    private var iso: String {
        editing?.date ?? LogicalDay.iso(clock.startedAt)
    }

    private var week: String {
        let schedule = environment.targets?.schedule
        return Week.label(ofWeekStart: Week.start(of: iso), anchor: schedule?.weekZeroStart, phases: schedule?.phases ?? [])
    }

    /// Tag 1's text, or nil when the catalogue has not loaded.
    private var planLabel: String? {
        environment.targets.map { Schedule.planLabel(owning: iso, in: $0.schedule) }
    }

    /// Tag 2's text — `WeekPhase.short`, the string the summary page draws.
    ///
    /// ── WHY THE WEEK IS CUT ON THE ATHLETE'S OWN DAY ────────────────────────
    /// `Week.start(of:)` defaults to Sunday and this screen took the default,
    /// while `SessionPage` passed `week_end_day`. For anyone whose week ends on
    /// a day other than Saturday that is a different week start, so the same
    /// session could be W9 on the deck and W10 on its own summary. The resolver
    /// already knows the answer.
    ///
    /// Falls back to `week` — "Week 9", or an era label — when the phase table
    /// has no row for this week. A date outside the table still has a POSITION,
    /// and dropping the tag would lose it to say nothing.
    private var phaseWeek: String {
        guard let resolver = environment.targets else { return week }
        return Phases.weekPhase(
            weekStart: Week.start(of: iso, startDay: resolver.weekStartDay),
            in: resolver.schedule.phases
        )?.short ?? week
    }

    /// "Sat 30 Aug" — the session's own date, which in edit mode takes the
    /// sub-line's place.
    ///
    /// It is the fact a person correcting a three-week-old workout most needs on
    /// screen and the one the live hero has no reason to carry: on a live deck
    /// the date is today, and a screen that tells you today's date is a screen
    /// spending its most valuable band on nothing.
    private var dateLabel: String? {
        guard editing != nil, let date = LogicalDay.date(fromISO: iso) else { return nil }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.m) {
            if typeSize.isAccessibilitySize {
                // Title and clock only. At AX5 the sub-line, the chip and a
                // two-line title took the band to 228 pt and pushed every set
                // row off a 874 pt screen — a full screen of chrome above the
                // one thing the reader opened this to touch.
                VStack(alignment: .leading, spacing: OnyxSpace.s) {
                    titleBlock
                    timerButton
                }
            } else {
                // Centred, not baseline-aligned. Sitting a 34 pt clock on the
                // 28 pt title's baseline pushes its ascender above the title's
                // and costs the band ten points it does not have — and the
                // clock reads better sitting optically between the split name
                // and the line under it than hanging off the first one.
                HStack(alignment: .center, spacing: OnyxSpace.m) {
                    titleBlock
                    Spacer(minLength: OnyxSpace.s)
                    timerButton
                }
            }
            tagRow
            LoggerFaceSwitch(selection: $selection, accent: accent)
        }
        .padding(.horizontal, OnyxSpace.l)
        .padding(.top, OnyxSpace.s)
        // 8 rather than 12: the band's budget is 132 pt and the four points buy
        // the margin that keeps it there when the week chip grows.
        .padding(.bottom, OnyxSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) { bleed }
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.label)
                .onyxType(.hero).fontWeight(.semibold)
                .foregroundStyle(Color.onyx.textPrimary)
                .lineLimit(typeSize.isAccessibilitySize ? 1 : 2)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 0.6 : 0.7)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: OnyxSpace.s) {
                // At AX5 "Chest + Back" truncates to "Chest +…" beside the
                // chip, which is a description that has stopped describing. The
                // week is a POSITION in the block and cannot be inferred; the
                // sub-title is the muscle group the split name already implies.
                // So the one that survives the squeeze is the chip.
                if clock.isPaused {
                    // Paused is a MODE, and grey is what this app says for
                    // "disabled" everywhere else — so a dimmed clock reads as a
                    // timer that has stopped working rather than one you
                    // stopped. The word is the only unambiguous channel, and it
                    // takes the sub-line's place because a paused session is
                    // more worth saying than which muscles it trains.
                    Text("Paused")
                        .onyxType(.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.onyx.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, OnyxSpace.s)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.onyx.textPrimary.opacity(0.14)))
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else if let dateLabel {
                    // Kept at every type size, unlike `day.sub`: the split name
                    // above already implies the muscle group, and nothing at all
                    // implies which Saturday this was.
                    Text(dateLabel)
                        .onyxType(.secondary).onyxNumeral()
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                } else if let sub = day.sub, !sub.isEmpty, !typeSize.isAccessibilitySize {
                    Text(sub)
                        .onyxType(.secondary)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(day.label). \(dateLabel ?? day.sub ?? ""). \(week)")
    }

    // MARK: - Tags

    /// `[Cut] [Week 8] [Quads] [Hamstrings] [Core]`.
    ///
    /// ── WHY THE MUSCLES ARE HERE AND NOT IN THE SUB-LINE ────────────────────
    /// `day.sub` says "Quad Focus" — an editorial label, written once per day
    /// and true in the way a chapter title is true. The tags are DERIVED from
    /// the movers of the exercises this phase actually prescribes, so a phase
    /// that drops the hip adduction drops `Adductors` with it, and each one is
    /// painted in the muscle's own colour — the same `Color.onyx.muscle` the
    /// card rails, the atlas and the distribution sheet use, so a green tag up
    /// here and a green rail 200 pt down are the same claim about the same
    /// muscle rather than two decorations that happen to agree.
    ///
    /// ── AND WHY IT COLLAPSES AT AN ACCESSIBILITY SIZE ───────────────────────
    /// The band's ceiling is 132 pt and AX5 has already spent it on a two-line
    /// title. Phase and week are POSITIONS — which block, which week of it —
    /// and cannot be re-derived by looking at the screen; the muscles are a
    /// restatement of the split name directly above them. So the muscles are
    /// what goes, which is the same rule the sub-line already follows.
    @ViewBuilder
    private var tagRow: some View {
        HStack(spacing: OnyxSpace.xs) {
            planChip
            phaseWeekChip
            if !typeSize.isAccessibilitySize {
                ForEach(dayMuscles, id: \.self) { muscle in
                    chip(muscle.displayName, tint: Color.onyx.muscle(muscle))
                }
            }
            Spacer(minLength: 0)
            heartChip
        }
        .lineLimit(1)
        // The row is a HEADER, not a control strip: VoiceOver reads it as one
        // phrase and the phase chip publishes its own button separately.
        .accessibilityElement(children: .contain)
    }

    /// The wrist, live — a heart and a number, pinned to the trailing edge.
    ///
    /// ── WHY IT IS AFTER THE `Spacer` AND NOT IN THE ROW OF CHIPS ────────────
    /// The muscles are what this row drops first when it runs out of width
    /// (see `tagRow`), and they drop by being omitted at an accessibility size
    /// — a mechanism that works because everything before the spacer is the
    /// same KIND of thing, a tag naming what the session is. A live reading is
    /// not a tag; it changes several times a minute, and a number that moves
    /// inside a row of fixed labels drags every chip beside it a point left and
    /// right as the digits change. Pinned past the spacer it moves nothing, and
    /// it is the one item here worth keeping at AX5: the muscles restate the
    /// split name above them, and nothing else on this screen is your pulse.
    ///
    /// No capsule. Three of the five chips on this row are already capsules and
    /// a fourth would read as a fourth tag; a glyph and a numeral read as a
    /// reading, which is what it is.
    @ViewBuilder
    private var heartChip: some View {
        if let liveBpm {
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .imageScale(.small)
                    .foregroundStyle(OnyxInk.Fixed.heart)
                Text("\(liveBpm)")
                    .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                    .foregroundStyle(Color.onyx.textPrimary)
                    // Reserved, or the tag beside it steps sideways every time
                    // the rate crosses 100 — the same rule the rest control's
                    // countdown follows.
                    .frame(minWidth: 26, alignment: .trailing)
            }
            .fixedSize()
            .transition(.scale(scale: 0.9).combined(with: .opacity))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Heart rate")
            .accessibilityValue("\(liveBpm) beats per minute, from your watch")
        }
    }

    /// The muscles this day trains, primaries only, in deck order and
    /// de-duplicated — three at most.
    ///
    /// PRIMARIES ONLY on purpose. Secondaries are half-credit assistance in
    /// `MuscleCredit` and there are a dozen of them across a day: a row that
    /// listed every muscle a leg session touches would name eight and inform
    /// nobody. Three is what fits beside the phase and the week at 375 pt.
    private var dayMuscles: [LandmarkMuscle] {
        var seen: [LandmarkMuscle] = []
        for exercise in day.exercises(for: phase) {
            for token in exercise.movers.primary {
                guard let muscle = LandmarkMuscle.from(token: token), !seen.contains(muscle)
                else { continue }
                seen.append(muscle)
            }
        }
        return Array(seen.prefix(3))
    }

    // ── THE TWO TAGS, AND WHY THEY ARE THE SAME TWO EVERYWHERE ─────────────
    // This row used to carry `Cut` and `Week 9` as separate chips while the
    // session's own summary page, one tap later, carried `Onyx-5` and `Cut W9`.
    // Four strings for two facts, and a reader comparing the two screens had to
    // work out that `Cut` + `Week 9` and `Cut W9` were the same claim while
    // `Onyx-5` appeared from nowhere.
    //
    // There are now exactly two, in this order, on both: the PLAN, then the
    // PHASE AND WEEK. `SessionDetailView.planTags` is the shape being matched —
    // it already read `WeekPhase.short`, so the unification is this screen
    // moving to what the summary always did, not a new format for both.

    /// Tag 1 — the plan that owns this session's date. "Onyx-5".
    ///
    /// `planId(owning:)`, not the ACTIVE plan: a deck re-opened on a session
    /// from a previous block belongs to the block that was running then, and
    /// the tag is about the session rather than about today.
    @ViewBuilder
    private var planChip: some View {
        if let label = planLabel {
            chip(label, tint: Color.onyx.textSecondary)
        }
    }

    /// Tag 2 — the phase and the week inside it, as one string. "Cut W9".
    ///
    /// ── STILL THE WAY INTO THE PHASE PICKER ─────────────────────────────────
    /// The phase used to be its own chip and that chip was the button. Folding
    /// it into the week's would have removed the only entry point to
    /// `PhaseSheet` from this screen, so the COMBINED tag carries the button
    /// instead. The affordance moves; it does not disappear.
    private var phaseWeekChip: some View {
        Button(action: onPhase) {
            chip(phaseWeek, tint: accent)
        }
        .onyxPress()
        .accessibilityLabel("Phase and week, \(phaseWeek)")
        .accessibilityHint("Opens the phase picker.")
    }

    /// One tag. The shape the week chip already had, so a row of them is one
    /// visual family rather than a capsule beside three of something else.
    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .onyxType(.caption).fontWeight(.semibold)
            .foregroundStyle(tint)
            .lineLimit(1)
            // NOT `.fixedSize()`. A chip that refuses to compress sets the
            // hero's minimum width, and five of them at AX5 is how a 402 pt
            // screen ends up proposing 510 — the trap `logger-chrome-u1`
            // records. A scale factor bends instead.
            .minimumScaleFactor(0.8)
            .padding(.horizontal, OnyxSpace.s)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.40), lineWidth: 0.5))
    }

    // ── THE REST CLOCK IS NOT HERE ANY MORE ─────────────────────────────────
    // It was an inline reading under the elapsed clock, 110 pt above the card
    // it was counting for, and adjusting it meant finding a context menu on a
    // caption. It now lives in the exercise card, in the slot the "2 / 3 sets"
    // fraction had — `ExerciseCardView.restControl`, with ±15 s as buttons you
    // can hit rather than a menu you have to discover.
    //
    // `restCountdown`, `onSkipRest` and `onAdjustRest` stay on this type: the
    // Live Stats face still draws `LoggerRestCapsule` from them, and the Lock
    // Screen shares the same validated range.

    // MARK: - The clock

    /// Elapsed, and the way into correcting it.
    ///
    /// ── WHY THE RUNNING CASE IS A SYSTEM TIMER AND THE PAUSED ONE IS NOT ────
    /// `Text(_:style:.timer)` re-renders itself once a second without this view
    /// tree knowing, which is what makes a 34 pt clock affordable on a screen
    /// you are also typing into. It counts from an instant and cannot be
    /// stopped — so a paused session draws its frozen reading as plain text
    /// instead, from the same arithmetic the Lock Screen is sent.
    @ViewBuilder
    private var timerButton: some View {
        if let editing {
            storedDuration(editing)
        } else {
            liveTimer
        }
    }

    /// What a finished session's clock reads: `duration_min`, as stored, and no
    /// button under it.
    ///
    /// ── WHY IT IS NOT A TIMER AND NOT TAPPABLE ──────────────────────────────
    /// `Text(_:style:.timer)` counts from an instant and cannot be stopped, so
    /// on a three-week-old session it renders the wall-clock age of the workout
    /// — `512:04:11` and climbing. And `TimerSheet` edits `started_at` and the
    /// pause ledger, neither of which means anything once `closeSession` has
    /// derived a duration from them: the duration is what is stored and it is
    /// the finish sheet's Duration cell that edits it (§U3.2), which is also
    /// the only write that sets `duration_edited`.
    private func storedDuration(_ editing: LoggerModel.EditContext) -> some View {
        HStack(spacing: OnyxSpace.xs) {
            Image(systemName: "checkmark.seal")
                .imageScale(.medium)
                .foregroundStyle(accent)
            Text(editing.durationMin.map { Clock.format($0 * 60) } ?? "—")
                .onyxClock()
        }
        .foregroundStyle(Color.onyx.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Duration")
        .accessibilityValue(editing.durationMin.map { "\(Int($0.rounded())) minutes" } ?? "not recorded")
        .accessibilityHint("Edit it from Finish.")
    }

    private var liveTimer: some View {
        Button(action: onTimer) {
            HStack(spacing: OnyxSpace.xs) {
                // ── WHY THE GLYPH IS ALWAYS THERE ───────────────────────────
                // Three jobs at once. It is the only thing that says a 34 pt
                // number is a BUTTON. It separates elapsed from the wall clock
                // 25 pt above it in the status bar, which is the same white and
                // the same "22:02" shape. And it holds its own width whether or
                // not the session is paused — appearing on pause moved the
                // whole band four points, under a thumb reaching for a set.
                Image(systemName: clock.isPaused ? "pause.fill" : "stopwatch")
                    .imageScale(.medium)
                    .foregroundStyle(accent)
                    .contentTransition(.symbolEffect(.replace))
                Group {
                    if clock.isPaused {
                        Text(Clock.format(clock.elapsed()))
                    } else {
                        Text(clock.timerOrigin, style: .timer)
                    }
                }
                .onyxClock()
            }
            .foregroundStyle(clock.isPaused ? Color.onyx.textTertiary : Color.onyx.textPrimary)
            .lineLimit(1)
            // NOT `fixedSize`. Both the running timer and `Clock.format` emit
            // `H:MM:SS` with unbounded hours — the session this sheet exists for
            // recorded 6:25:00 — and at AX5 that reading plus the glyph is ~371
            // pt of a 375 pt screen. `fixedSize` would take the ideal and widen
            // the band; the priority keeps the title from squeezing it first,
            // and the scale factor is the fallback `fixedSize` forbids.
            .minimumScaleFactor(0.6)
            .contentShape(Rectangle())
        }
        .layoutPriority(1)
        .onyxPress()
        .animation(OnyxMotion.move, value: clock.isPaused)
        .accessibilityLabel(clock.isPaused ? "Paused" : "Elapsed")
        .accessibilityValue(Clock.format(clock.elapsed()))
        .accessibilityHint("Opens the session timer, where you can pause it or correct the start.")
    }

    // MARK: - The ground

    /// The day's own colour, as a mesh behind the band.
    ///
    /// Same discipline as `onyxScreen`: a mesh over black, heavily blurred, held
    /// under a ceiling — 12 % here against the screen's 10 %, because this one is
    /// a band 130 pt tall rather than a 280 pt bleed and it is saying which
    /// WORKOUT rather than which tab. The screen's own `.train` bleed sits
    /// behind it; two washes at these alphas read as one lit corner, which is
    /// the intent, and going past 12 % is where the glass above starts to muddy.
    private var bleed: some View {
        ZStack(alignment: .bottom) {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    .init(0, 0),   .init(0.5, 0),   .init(1, 0),
                    .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                    .init(0, 1),   .init(0.5, 1),   .init(1, 1),
                ],
                colors: [
                    // The whole top row is the accent, not two corners of it.
                    // At 40 pt of blur a single lit quadrant comes out as a
                    // smudge behind the back button — visible enough to read as
                    // banding and not enough to say which workout this is.
                    accent, accent, accent,
                    accent.opacity(0.6), accent.opacity(0.35), accent.opacity(0.6),
                    .black, .black, .black,
                ]
            )
            .blur(radius: 40)
            // The ceiling, and it stays the ceiling: past 12 % the glass above
            // tints towards the day and the set rows go muddy.
            .opacity(0.12)

            // Where the chrome ends and the deck begins. A hairline in the day's
            // colour rather than a divider: it is the bottom edge of a lit
            // surface, not a rule between two lists.
            Rectangle()
                .fill(accent.opacity(0.35))
                .frame(height: 0.5)
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

// MARK: - The face switch

/// `Workout | Live Stats`, with a pill you can throw.
///
/// ── WHY NOT `Picker(.segmented)` ────────────────────────────────────────────
/// The system control is the right default and it is the wrong one here for two
/// reasons: it cannot carry the day's colour, and the face it selects is a whole
/// page that slides — so the pill and the page have to move on the SAME spring
/// or the control arrives before the content and reads as two separate
/// animations of one action.
///
/// ── AND WHY THE PAGES ARE NOT DRAGGED ───────────────────────────────────────
/// A horizontal drag across the deck is already spoken for: the set row is
/// swiped right to log (wave U2 retires that; until then it is live), and a
/// pager underneath would compete for the same finger on every row of every
/// card. So the gesture lives on the CONTROL — drag the pill, which is what a
/// segmented control has always let you do — and the deck keeps its swipe.
struct LoggerFaceSwitch: View {
    @Binding var selection: LoggerFaceSelection
    let accent: Color

    /// Live displacement while a finger is on the pill, in points. Not animated:
    /// touch and content move together or the control is not being dragged.
    @State private var drag: CGFloat = 0

    /// Below this the release is a slide, above it a throw. 150 pt/s is about
    /// the speed at which a movement stops reading as positioning.
    private static let flickSpeed: CGFloat = 150

    /// A fixed 36 pt box put "Live Stats" outside its own capsule at AX5. The
    /// track scales with the label it holds, like every other control here.
    @ScaledMetric(relativeTo: .footnote) private var trackHeight: CGFloat = 36

    /// The track's measured width. Only the pill reads it.
    @State private var width: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LoggerFace.allCases) { face in
                segment(face)
            }
        }
        // ── WHY THE PILL IS A BACKGROUND AND NOT A SIBLING ──────────────────
        // A bare `Capsule()` has no intrinsic height. As the first child of a
        // `ZStack` it therefore accepted every point the stack could offer and
        // grew the control to 240 pt. Behind the labels it is proposed exactly
        // their height, which is also the only height this control has any
        // business being.
        // The floor FIRST, then the pill. `trackHeight` is a `@ScaledMetric`
        // and reaches ~122 pt at AX5 while the labels are ~60, so a background
        // applied before the frame is proposed the labels' height and the pill
        // ends up floating inside a track twice its size. Applied after, it is
        // proposed the height the track actually has.
        .frame(minHeight: trackHeight)
        .background(alignment: .leading) { pill(width / 2) }
        .contentShape(Capsule())
        .simultaneousGesture(gesture(width / 2))
        // The width is measured rather than proposed, because only the PILL
        // needs it — the segments divide the row themselves.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background {
            Capsule().fill(.ultraThinMaterial)
            Capsule().strokeBorder(Color.onyx.hairline, lineWidth: 0.5)
        }
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
    }

    private func pill(_ half: CGFloat) -> some View {
        Capsule()
            .fill(accent.opacity(0.26))
            .padding(2)
            .frame(width: half)
            .offset(x: pillX(half))
            // Keyed on the FACE, not on the offset: a change of face springs,
            // a finger on the pill tracks 1:1.
            .animation(selection.animation, value: selection.face)
    }

    private func segment(_ face: LoggerFace) -> some View {
        Button {
            withAnimation(OnyxMotion.move) {
                selection = LoggerFaceSelection(face: face, flicked: false)
            }
        } label: {
            Text(face.title)
                .onyxType(.caption).fontWeight(.semibold)
                .foregroundStyle(selection.face == face ? accent : Color.onyx.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, OnyxSpace.s)
                .padding(.vertical, OnyxSpace.s)
                // Width greedy, height NOT. `maxHeight: .infinity` here made
                // every segment claim whatever vertical space the screen had
                // spare, and the control came out 240 pt tall on a face whose
                // content was short. The label's own height is the height.
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection.face == face ? [.isSelected, .isButton] : .isButton)
    }

    /// Pill origin: the selected half, plus the finger, resisted at the ends.
    private func pillX(_ half: CGFloat) -> CGFloat {
        resist(CGFloat(selection.face.index) * half + drag, limit: half, dimension: half)
    }

    /// §*Designing Fluid Interfaces*: a boundary resists progressively. A hard
    /// clamp reads as frozen; this reads as "there is nothing more here".
    private func resist(_ x: CGFloat, limit: CGFloat, dimension: CGFloat) -> CGFloat {
        let c: CGFloat = 0.55
        if x < 0 { return -rubber(-x, dimension, c) }
        if x > limit { return limit + rubber(x - limit, dimension, c) }
        return x
    }

    private func rubber(_ over: CGFloat, _ dimension: CGFloat, _ c: CGFloat) -> CGFloat {
        (over * dimension * c) / (dimension + c * over)
    }

    private func gesture(_ half: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { drag = $0.translation.width }
            .onEnded { value in
                // The system's own momentum projection, rather than a
                // deceleration constant re-derived here: `predictedEndTranslation`
                // is where UIKit says this throw is going.
                let projected = CGFloat(selection.face.index) * half + value.predictedEndTranslation.width
                let target: LoggerFace = projected > half / 2 ? .stats : .workout
                let flicked = abs(value.velocity.width) > Self.flickSpeed
                // A throw that lands where it started still threw something:
                // the pill has to spring home, and it earned the overshoot —
                // which is why `flicked` is set from the velocity either way.
                let next = LoggerFaceSelection(face: target, flicked: flicked)
                withAnimation(next.animation) {
                    selection = next
                    drag = 0
                }
            }
    }
}

// MARK: - Rest

/// The rest clock, as a capsule under the hero.
///
/// ── WHY IT LEFT THE NAVIGATION BAR ──────────────────────────────────────────
/// It lived in `.principal`, where iOS puts a running timer in Phone and Voice
/// Memos — and that slot is 44 pt tall and shared with a title. With the hero
/// carrying the title and the elapsed clock, the bar has nothing to say, and a
/// countdown you are watching for the next 90 seconds belongs at the top of the
/// content rather than in chrome you are trying to ignore.
///
/// `Text(timerInterval:)` traps on a range whose end is behind its start, so the
/// check happens at the call site where the value is still optional —
/// `restCountdown` in `Shared/`, which the Lock Screen shares.
///
/// ── AND WHY IT IS THREE WORDS WIDE ──────────────────────────────────────────
/// It used to be full-bleed and carry the resting movement's name and the word
/// "Skip". The name is the card header 110 pt below it — and at AX5 the two
/// extra strings pushed the countdown itself into wrapping, so "1:43" rendered
/// as "1:4" over "3". A plausible-looking wrong number, on the one reading this
/// capsule exists for. "Skip" went with it: the whole capsule has been the skip
/// target since it lived in the navigation bar, and the word was a second label
/// for an action the chip row already spells out.
struct LoggerRestCapsule: View {
    let countdown: ClosedRange<Date>
    let accent: Color
    let onSkip: () -> Void
    let onAdjust: (TimeInterval) -> Void

    var body: some View {
        Button(action: onSkip) {
            HStack(spacing: OnyxSpace.s) {
                Image(systemName: "timer")
                Text(timerInterval: countdown, countsDown: true)
                    .onyxNumeral()
                    // Reserved, so the capsule does not resize as the digits
                    // fall from 1:00 to 59.
                    .frame(minWidth: 46, alignment: .leading)
                Text("Resting").foregroundStyle(Color.onyx.textSecondary)
            }
            .onyxType(.caption).fontWeight(.semibold)
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, OnyxSpace.m)
            .frame(minHeight: 44)
            .background(Capsule().fill(accent.opacity(0.16)))
        }
        .onyxPress()
        .contextMenu {
            Button("Add 15 seconds", systemImage: "plus") { onAdjust(15) }
            Button("Take 15 seconds off", systemImage: "minus") { onAdjust(-15) }
            Button("Skip rest", systemImage: "forward.end") { onSkip() }
        }
        .accessibilityLabel("Resting")
        .accessibilityHint("Tap to skip. Long press to add or remove fifteen seconds.")
    }
}

#if DEBUG
#Preview("Logger hero") {
    @Previewable @State var selection = LoggerFaceSelection()
    let model = LoggerModel.previewUpperB(logged: true)
    return VStack(spacing: OnyxSpace.m) {
        LoggerHero(
            day: model.day,
            clock: LoggerClock(startedAt: Date().addingTimeInterval(-22 * 60)),
            selection: $selection,
            onTimer: {}
        )
        LoggerRestCapsule(
            countdown: Date()...Date().addingTimeInterval(97),
            accent: Color.onyx.day(model.day.key),
            onSkip: {}, onAdjust: { _ in }
        )
        Spacer()
    }
    .onyxScreen(.train)
    .foregroundStyle(Color.onyx.textPrimary)
    .preferredColorScheme(.dark)
}
#endif
