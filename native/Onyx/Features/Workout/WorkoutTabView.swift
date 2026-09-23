import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData
import os

/// The Workout tab — the week behind you, the session in front of you, and the
/// door into the logger.
///
/// ── THE LOGGER IS A COVER, NOT THE TAB ──────────────────────────────────────
/// Wave 1 put `LiveLoggerView` at the tab root, which made opening the tab the
/// same thing as starting a workout: the Live Activity appeared on the Lock
/// Screen because you glanced at Thursday's plan. A workout is something you
/// START. This screen shows what the week has been and what the day asks, and
/// one deliberate tap presents the logger as a full-screen cover.
///
/// ── WHY THE MODEL AND THE ACTIVITY LIVE HERE ────────────────────────────────
/// The cover can be dismissed mid-session to check the Pulse tab. If the logger
/// owned its `LoggerModel` and `LiveActivityController`, dismissing it would
/// drop the rest timer and orphan the Lock Screen card — a card nothing can
/// update or end, and a second one on re-open. So both are `@State` on the tab
/// that outlives the cover, and the logger borrows them.
///
/// ── WHAT WAVE 2.8 CHANGED ───────────────────────────────────────────────────
/// The tab used to be ONE tile: a 400 pt plan card with a 88 pt atlas, a phase
/// chip, and seven exercise rows at 44 pt each — a screen that answered "what is
/// today" three times and never answered "how is the week going" or "what should
/// go up". §5.2 re-cuts it into four things of different sizes, in the order you
/// actually ask them: the week, then today, then the lifts that have earned a
/// heavier load, then cardio. The plan rows shrink to 36 pt because they are a
/// reminder, not a document — the logger is where you read a set.
struct WorkoutTabView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Cut is the live block. `@AppStorage` so the toggle survives a relaunch.
    @AppStorage("onyx.phase") private var storedPhase = ProgramPhase.cut.rawValue

    /// Supplied only by the screenshot harness, which cannot depend on which
    /// weekday the shot happens to run on. The app never passes one.
    var seededDay: ProgramDay?
    var seededToday: String?
    /// Holds the done card on its stand-in, for the harness only.
    ///
    /// `SessionFallbackCard` is drawn for as long as `SessionAnalysis.headers`
    /// takes, which on a warm fixture is less than a frame — so the state this
    /// wave rebuilt is the one state of this tab a screenshot could never
    /// catch. A seed, and not a `#if DEBUG` branch inside the card: the point
    /// of the shot is that the REAL screen, with the real week under it, looks
    /// right while it waits.
    var seededHeaderPending = false
    @State private var week: WorkoutWeek?
    @State private var weekSheetOpen = false
    /// The Customize sheet, from a long press anywhere on the tab (W6).
    @State private var customizing = false
    /// The shelf of closed weeks (§W1 C). A sheet, and the only thing on this
    /// tab reached from a toolbar rather than from the page.
    @State private var libraryOpen = false
    /// Whether the previous value of `session != nil` was true — see the
    /// `onChange` that ends gym mode.
    @State private var hadSession = false
    /// The session this tab is keeping, live or not. Survives the cover being
    /// dismissed — that is the whole reason it lives here.
    @State private var session: LoggerModel?
    /// The session the cover is PRESENTING, which is a different fact: leaving
    /// the logger mid-workout clears this and keeps `session`, so the rest timer
    /// and the Lock Screen card carry on and "Resume workout" has something to
    /// resume.
    @State private var presented: LoggerModel?
    @State private var activity = LiveActivityController()
    /// The geometry the Mini Player hands to the logger on the way in.
    ///
    /// `.zoom` needs ONE namespace holding both ends, and the source lives in
    /// this view's bottom inset while the destination is the cover's content —
    /// so the namespace has to be owned here, above both.
    @Namespace private var zoom
    /// The session's elapsed clock, kept beside `session` and for the same
    /// reason: leaving the logger mid-workout tears the cover down, and a clock
    /// that lived in `LiveLoggerView`'s own `@State` went with it. Start at
    /// 10:00, pause at 10:30, leave, come back at 11:30 and the hero read
    /// 1:30:00 — the hour of pause gone, from the number this whole wave exists
    /// to make true. Wave E4 folds it into `LoggerModel`, which is kept here
    /// already, and this property goes with the stand-in.

    /// The masthead for the session logged today, when there is one.
    ///
    /// Loaded rather than derived: `careerIndex` is a position in the whole
    /// record and the muscle capsules are a fold over the session's own sets,
    /// neither of which is on `WorkoutWeek.State`. Nil until it arrives, and
    /// the four numbers the state DOES carry are drawn in the meantime.
    @State private var doneHeader: SessionHeader?
    @State private var showPhase = false
    @State private var loggingCardio = false
    /// The swap sheet. §5.2 item 3 puts rest and swap on the session card,
    /// which is where the thing being moved actually is — the Pulse tab's
    /// Schedule tile is deleted in the same wave.
    @State private var swapping = false
    /// The session to push once the cover closes on a FINISHED workout.
    ///
    /// ── WHY THE TAB PUSHES IT AND NOT THE FINISH SHEET ──────────────────────
    /// The sheet is inside a full-screen cover that is being torn down in the
    /// same transaction — a push from there lands on a stack that is about to
    /// stop existing. The tab outlives both, so it is the only place that can
    /// put the summary on screen and leave it there.
    @State private var summary: String?
    /// The previous session being reviewed in a sheet, from the plan card's
    /// door. A different verb from `summary`, which PUSHES the session you just
    /// finished onto the stack: this one is a look backwards that the plan you
    /// are about to perform has to survive, so it comes back to exactly where
    /// it was opened from.
    @State private var reviewing: Review?

    /// A session id the sheet can be presented BY. `String` is not
    /// `Identifiable` and making it so retroactively would reach every string
    /// in the app; this reaches one property.
    struct Review: Identifiable { let id: String }

    /// The id both ends of the done card's zoom agree on.
    ///
    /// Spelled once, for the reason `MiniPlayerCard.transitionID` states:
    /// `.matchedTransitionSource(id:in:)` and `.navigationTransition(.zoom)`
    /// match on a `Hashable` whose TYPE has to match as well as its value, so
    /// two literals in two places are two chances to typo a transition that
    /// then silently does not happen — with no build error and nothing in the
    /// console.
    static let doneTransitionID = "onyx.session.done"

    /// The closed week being read, PUSHED from the This-week tile (W4).
    @State private var wrapped: WrapDoor?

    /// The same box as `Review` above, for the same reason: `WeeklyWrap.Summary`
    /// is an OnyxCore value and making an OnyxCore type conform to present one
    /// destination reaches every caller of that type. The Monday the week
    /// starts on already names it uniquely.
    ///
    /// `Hashable` and no longer `Identifiable`: `navigationDestination(item:)`
    /// wants the former, which is the same box `WeekDaysView.ReportDoor` is and
    /// for the same reason.
    struct WrapDoor: Hashable {
        let summary: WeeklyWrap.Summary
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.summary.weekStart == rhs.summary.weekStart }
        func hash(into hasher: inout Hasher) { hasher.combine(summary.weekStart) }
    }
    /// Bumped when a dismissal turns out to have finished the session. The
    /// haptic lived on the finish button, which was torn down in the same
    /// transaction that fired it, so it very likely never played.
    @State private var finishes = 0

    @Environment(\.dynamicTypeSize) private var typeSize

    private var phase: ProgramPhase { ProgramPhase(rawValue: storedPhase) ?? .cut }
    private var accent: Color { Color.onyx.accent(.train) }

    /// Today's deck. The harness pins it; the app resolves it through the
    /// schedule rule (plan · per-date swaps · weekday layout), never off the
    /// raw weekday.
    private var today: ProgramDay? { seededDay ?? week?.todayDay }

    /// Where today stands. `.none` until the first read lands, which is the
    /// honest answer — the footer says "Start" and means it.
    private var state: WorkoutWeek.State { week?.snapshot.state ?? .none }

    var body: some View {
        ScrollView {
            // `.m` and not `.l` (W6 density): Today and Fuel were already at 12
            // between sections and this root was the one at 16, which put
            // Train's fifth card a little further below the fold than the same
            // card on either neighbour. The gutter stays at `.l` — that is the
            // screen's 16 pt line and every tile in the app stands on it.
            VStack(spacing: OnyxSpace.m) {
                // ── WHAT CANNOT BE PUT AWAY (W6 §4) ─────────────────────────
                // The week panel and the live/plan card carry no switch. They
                // are what the tab IS — the state you are in and the work in
                // front of you — and a Customize sheet that can empty a screen
                // is a Customize sheet that produces support requests. Every
                // section below them is the reader's to hide.
                weekPanel
                if let day = today { sessionCard(day) } else { restCard }
                if shows(.doors) { doorsRow }
                if shows(.cardio) { cardioCard }
                if shows(.progression) { progressionCard }
            }
            .padding(.horizontal, OnyxSpace.l)
            .padding(.top, OnyxSpace.s)
            .padding(.bottom, OnyxSpace.xl)
        }
        // ── THE LONG PRESS, AND WHY IT IS NOT A `contextMenu` ───────────────
        // `TileMenu` is the interaction precedent and its lesson is that a
        // press must SAY THE VERBS rather than start an opaque mode. It is not
        // a precedent for the modifier: `.contextMenu` renders a lifted
        // snapshot of the view it is attached to, and attached to a whole tab
        // that lift is the entire screen peeled off the background — which is
        // the animation iOS uses to say "this one thing", performed over
        // everything.
        //
        // `simultaneousGesture` and not `onLongPressGesture`: the plan card,
        // the day cells and the footer all own presses of their own, and an
        // exclusive recogniser on the container swallows them.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in customizing = true }
        )
        // On the way IN only — the closure's `true` gates it, so dismissing
        // the sheet does not buzz a second time for a press nobody made.
        .sensoryFeedback(.selection, trigger: customizing) { _, open in open }
        // A long press has no VoiceOver equivalent — the rotor cannot hold one
        // down. The same gap `TileMenu` fills with `accessibilityActions`.
        .accessibilityAction(named: "Customize Train") { customizing = true }
        .onyxScreen(.train)
        // The bout arrived without being asked for; the tab it belongs to says
        // so once and then forgets. Train and Pulse only — see the modifier.
        .cardioIngestNotice()
        .navigationTitle("Train")
        .navigationBarTitleDisplayMode(.inline)
        // ── THE TAB'S FIRST TOOLBAR, AND WHY THE SHELF EARNED IT ────────────
        // Everything else on this screen is the week in front of you, and the
        // page is ordered by how soon you need it. The weeks BEHIND you are a
        // different question — asked rarely, from anywhere, and never while
        // deciding what to lift — so it was the one section that had to be
        // scrolled past every time to reach the things it was less important
        // than. A bar button is the one place on this tab that costs the page
        // no height at all.
        //
        // Still gated on `TrainSection.pastWeeks`: the Customize sheet has
        // always been able to put this away, and a switch that stopped working
        // because its section became a button would be a setting that silently
        // does nothing.
        .toolbar {
            // ── THE WAY OUT OF GYM MODE (§W6-B, decision 26) ────────────────
            // Leading, where a back button would be: gym mode is a place the
            // app was put and this is the way out of it, which is the same
            // grammar. A capsule and not a glyph because it is the only
            // control on the screen that changes what the WHOLE app is doing,
            // and a bare chevron here would read as "back to the week".
            if environment.gymMode {
                ToolbarItem(placement: .topBarLeading) {
                    // ── TEXT, AND NO GLYPH ──────────────────────────────────
                    // A `Label` here renders as its ICON ALONE: the system
                    // wraps a toolbar item in its own circular glass and
                    // drops the title to fit, so the first shot of gym mode
                    // had an unexplained chevron where the way out should be
                    // — indistinguishable from a back button. A bare title
                    // makes the system draw a pill and keep the word, and it
                    // carries no second capsule of ours under the glass
                    // (memory: `logger-ux-hotfix-sep10`).
                    Button("Leave") {
                        environment.gymMode = false
                        // A REFUSAL and not a toggle: without this the next
                        // foreground — or any theme pick, which re-ids the app
                        // root — asks the clock again, gets the same yes, and
                        // takes the bar away a second time.
                        environment.gymModeDeclined = true
                    }
                    .tint(accent)
                    .accessibilityLabel("Leave gym mode")
                    .accessibilityHint("Shows the tab bar again")
                }
            }
            if shows(.pastWeeks) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { libraryOpen = true } label: {
                        Image(systemName: "books.vertical.fill")
                    }
                    .tint(accent)
                    .accessibilityLabel("Past weeks")
                    .accessibilityHint("Every closed week of the plan")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .navigationDestination(item: $summary) { id in
            SessionDetailView(sessionId: id)
        }
        // The whole page, in its own stack so its toolbar and its own
        // navigation still work inside the sheet.
        .sheet(item: $reviewing) { review in
            NavigationStack {
                SessionDetailView(sessionId: review.id)
                    // The drag indicator is the only other way out, and it
                    // needs the page scrolled back to the top to be reachable —
                    // on a session page that is most of a screen of scrolling.
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { reviewing = nil }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // ── WHY `item:` AND NOT `isPresented:` ──────────────────────────────
        // The boolean form evaluated `if let session` inside its own content
        // builder, so a cover presented in the same runloop turn as the model
        // being assigned came up with NOTHING in it — a full-screen black
        // rectangle with no way back except the gesture. Presenting by item
        // makes the model's existence the precondition of the cover, and the
        // empty case stops being representable.
        .fullScreenCover(item: $presented, onDismiss: reload) { model in
            NavigationStack {
                LiveLoggerView(model: model, activity: activity)
            }
            .preferredColorScheme(.dark)
            // ── THE CARD GROWS INTO THE LOGGER ──────────────────────────────
            // On the OUTERMOST view inside the closure, never on
            // `LiveLoggerView` inside the stack: the modifier's own
            // documentation says to add it to the view that appears within a
            // stack or a sheet, "outside of any containers", and a cover is a
            // sheet — both go through one presentation bridge in SwiftUI, which
            // is why this works from `.fullScreenCover(item:)` at all.
            //
            // Two things it changes that are worth knowing:
            //
            //  1. The zoom brings its OWN interactive dismissal, so the logger
            //     can now be dragged down. That used to be unavailable and used
            //     to be frightening — leaving mid-session dropped you onto a
            //     dim "Resume workout" strip. It drops you onto a live card
            //     carrying the clock now, which is the state minimising was
            //     always meant to be, so the gesture is welcome rather than
            //     tolerated.
            //  2. FINISHING a session dismisses without it. `footer` is gated
            //     on `!isDone`, so by the time the cover tears down the source
            //     card has already left the tree and the un-zoom has nothing to
            //     return to; the system falls back to a plain dismiss, which is
            //     the right feel for an exit that ends with the summary being
            //     pushed anyway.
            .navigationTransition(.zoom(sourceID: MiniPlayerCard.transitionID, in: zoom))
        }
        .sheet(isPresented: $showPhase) {
            if let day = today {
                PhaseSheet(day: day, phase: Binding(
                    get: { phase },
                    set: { storedPhase = $0.rawValue }
                ))
            }
        }
        // Re-read on dismissal for the same reason the day swap does: the
        // week panel, today's card and the progression queue all read the
        // schedule, and a week rearranged behind a modal must not leave any of
        // them drawing the old one.
        // No `onDismiss` refresh: `applyWeekPlan` already re-reads on success,
        // and a cancel changed nothing. Both fired before, so every confirm
        // cost two full tab reads — and on a wrapped week each one carries the
        // PR replay.
        .sheet(isPresented: $weekSheetOpen) {
            if let week, week.loaded {
                WeekOverrideSheet(week: week)
            }
        }
        .sheet(isPresented: $customizing) {
            if let week {
                CustomizeTrainSheet(
                    layout: week.snapshot.trainLayout,
                    set: { section, visible in week.setTrainSection(section, visible: visible) }
                )
            }
        }
        // `item:` and not a `Bool`, for the reason spelled out above the logger
        // cover: a destination whose content is `if let` over a separate piece
        // of state can come up empty. The summary IS the destination here.
        //
        // A PUSH since W4, beside the session destination above it and into the
        // same stack (`RootView`'s). The report is a place now, not a reel
        // behind a drag indicator — `WeekReportView`'s header has the whole
        // argument, and it is one door of four that had to move together.
        .navigationDestination(item: $wrapped) { door in
            WeekReportView(
                summary: door.summary,
                program: week?.snapshot.program ?? Program(id: "", label: "", days: [])
            )
        }
        // The shelf. It reads its own weeks when it opens (`WorkoutWeek.library`)
        // rather than taking them off the snapshot, which is what let the tab
        // stop paying for them on every refresh.
        .sheet(isPresented: $libraryOpen) {
            if let week {
                PastWeeksLibrary(week: week, program: week.snapshot.program)
            }
        }
        .sheet(isPresented: $loggingCardio) {
            if let week {
                CardioLogSheet(
                    userId: week.userId,
                    date: week.today,
                    // Today's rows are what an import is deduplicated against,
                    // and the tab is already holding them for the cardio card.
                    existing: week.snapshot.todayCardio,
                    onSave: week.addCardio,
                    bouts: { [environment] in await environment.cardioBouts(on: week.today) },
                    lastBout: week.snapshot.lastCardio
                )
            }
        }
        // Re-read on dismissal: a swap rewrites today's day key, which changes
        // the card, the week panel and the progression queue at once.
        .sheet(isPresented: $swapping, onDismiss: { Task { await week?.refresh() } }) {
            if let week {
                // The undo lives INSIDE the sheet: undoing a swap clears TWO
                // dates (memory `swap-day-semantics`) and the sentence saying
                // which is the whole reason it is safe to offer.
                SwapSheetDoor(date: week.today)
            }
        }
        .task {
            if week == nil {
                week = WorkoutWeek(
                    database: environment.database, userId: environment.userIdString,
                    phase: phase, seededToday: seededToday, seededDayKey: seededDay?.key
                )
            }
            await week?.refresh()
        }
        // Keyed on the id, so finishing a session loads its masthead and
        // opening the tab on a rest day clears the last one rather than leaving
        // yesterday's card under today's date.
        .task(id: doneSessionId) {
            guard let id = doneSessionId, !seededHeaderPending else {
                doneHeader = nil
                return
            }
            let database = environment.database, userId = environment.userIdString
            doneHeader = await Task.detached(priority: .userInitiated) {
                SessionAnalysis.headers(database: database, userId: userId, sessionIds: [id])[id]
            }.value
        }
        .onChange(of: storedPhase) { _, next in
            week?.setPhase(ProgramPhase(rawValue: next) ?? .cut)
        }
        // The one place that knows whether a session is live IS the one holding
        // it. Settings reads the published flag and refuses a theme write while
        // it is up — see `AppEnvironment.isSessionLive`. `initial: true` so a
        // tab rebuilt with no model (a relaunch, or a theme write that already
        // happened) lowers the flag rather than leaving the last value up.
        .onChange(of: session != nil, initial: true) { _, live in
            environment.publishSessionLive(live)
            // Gym mode ends with the workout, finished or cancelled: both
            // paths clear `session`, and neither of them is a tap on Leave.
            // `initial: true` fires with `live == false` on a tab rebuilt with
            // no model, which must NOT undo the launch door — hence the guard
            // on a session having been there to lose.
            if !live, hadSession { environment.gymMode = false }
            hadSession = live
        }
        // ── WHAT THE WRIST DID (App Store W4) ───────────────────────────────
        // An end first, then an open — `WristNews` says why the order is the
        // point. `initial: true` because this tab is built lazily: the news
        // can land before the view exists, and waits on the bridge for it.
        .onChange(of: environment.watchBridge.news, initial: true) { _, news in
            guard news != .init() else { return }
            environment.watchBridge.clearNews()
            news.ended.forEach(letGo)
            if let opened = news.opened { followWrist(opened) }
        }
        // §3.4: `.success` on session finished.
        .sensoryFeedback(.success, trigger: finishes)
    }

    // MARK: - This week

    /// Seven days, at a glance, in the colour of what they train.
    ///
    /// ── WHY A ROW OF DAYS AND NOT A BAR CHART OF TONNAGE ────────────────────
    /// The question this panel answers is "am I on the plan", and the plan is
    /// stated in SESSIONS, not kilograms. A filled cell is a session that
    /// happened, a hollow ring is one the plan is still expecting, and a grey
    /// dot is a rest day — three states you can count without reading a number.
    /// The tonnage is trailing in the header, where a supporting figure belongs.
    private var weekPanel: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            // ── THE HEADER IS THE DOOR (W6) ─────────────────────────────────
            // Tapping "This week" opens the week's seven days for reassignment.
            // The header and not the cells: a cell already means "open the
            // session that happened here", and giving it a second meaning that
            // depends on whether the day is logged is the kind of control
            // people learn by getting it wrong.
            //
            // A Button wrapping the whole ViewThatFits rather than just the
            // Text, so the tap target is the full width of the panel's top
            // line — a 60 pt word is not a target at the end of an arm holding
            // a phone in a gym.
            // ── THE TILE IS THE WRAP-UP DOOR ONCE THE WEEK CLOSES ──────────
            // A wrap-up modal that appears on its own gets dismissed by reflex
            // and is then gone — a summary of the week you just trained, shown
            // once, at a moment you did not choose. The panel transforms
            // instead: same tile, same place, now a door that stays.
            //
            // The rearrange sheet moves to a long press. It is the everyday
            // action for six days of the week and the wrap-up is the news on
            // the seventh, so the seventh takes the tap.
            if let wrap = week?.snapshot.wrap {
                // ── A PUSH, AND W1a's ARGUMENT FOR A SHEET WAS RIGHT (W4) ───
                // W1a made this a detent sheet because "a wrap-up is a thing
                // you glance at and put down". That was true of the REEL and it
                // is false of what the week now answers — macros, water,
                // records, the strongest lifts, the weigh-in. A document behind
                // a drag indicator is a document whose second half is never
                // read.
                //
                // The argument against a MODAL is unchanged and still holds: it
                // is an argument against a summary that appears UNINVITED. This
                // one opens because the tile was tapped, and the tile is still
                // a door that stays.
                Button { wrapped = WrapDoor(summary: wrap) } label: {
                    wrapLabel(wrap)
                }
                .buttonStyle(.plain)
                .onyxPress()
                .contextMenu {
                    // `week?.loaded` gates the TAP rather than the sheet's content.
            // Presenting and then drawing nothing is the black-cover-with-no-
            // way-out shape this file already warns about below; a header that
            // is simply inert for the half-second before the first detached
            // read lands cannot produce it.
            Button { if week?.loaded == true { weekSheetOpen = true } } label: {
                        Label("Rearrange this week", systemImage: "calendar.badge.clock")
                    }
                }
            } else {
            Button { weekSheetOpen = true } label: {
                // Label beside the tally until the tally alone is a line wide. At
                // AX5 an `HStack` broke "THIS WEEK" and "12,510 kg" across four
                // lines between them.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                        weekLabel
                        Spacer(minLength: OnyxSpace.s)
                        tally
                    }
                    VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                        weekLabel
                        tally
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onyxPress()
            .accessibilityLabel("This week")
            .accessibilityHint("Rearrange this week's days")
            }
            HStack(spacing: OnyxSpace.xs) {
                ForEach(week?.snapshot.cells ?? []) { cell in
                    dayCell(cell)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.tile)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("This week")
    }

    /// The closed week's header line: the news, the tally, and a chevron.
    ///
    /// Deliberately the same three parts in the same places as the open week's
    /// — only the word changes. A tile that re-lays itself out when its state
    /// flips reads as a different tile arriving, rather than as this one having
    /// something new to say.
    private func wrapLabel(_ wrap: WeeklyWrap.Summary) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                wrapTitle(wrap)
                Spacer(minLength: OnyxSpace.s)
                tally
            }
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                wrapTitle(wrap)
                tally
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week wrapped. \(wrap.headline)")
        .accessibilityHint("Open the weekly summary")
    }

    private func wrapTitle(_ wrap: WeeklyWrap.Summary) -> some View {
        HStack(spacing: OnyxSpace.xs) {
            Text(wrap.isDeload ? "Deload wrapped" : "Week wrapped")
                .onyxMicro()
                .foregroundStyle(OnyxDomain.train.accent)
            Image(systemName: "chevron.right")
                .onyxType(.micro)
                .foregroundStyle(OnyxDomain.train.accent.opacity(0.7))
                .accessibilityHidden(true)
        }
    }

    /// The header's own line. A chevron beside it, because a heading that opens
    /// something has to say so — the panel looked identical before it was
    /// tappable, and an affordance nobody can see is a feature nobody uses.
    private var weekLabel: some View {
        HStack(spacing: OnyxSpace.xs) {
            Text("This week").onyxMicro()
            Image(systemName: "chevron.right")
                .onyxType(.micro)
                .foregroundStyle(Color.onyx.textTertiary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var tally: some View {
        if let snapshot = week?.snapshot, week?.loaded == true {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.xs) {
                Text("\(snapshot.sessionsLogged)/\(snapshot.sessionTarget)")
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textPrimary)
                Text("· \(OnyxFormat.volume(snapshot.weekTonnageKg)) kg")
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
            }
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private func dayCell(_ cell: WorkoutWeek.DayCell) -> some View {
        let mark = dayMark(cell)
        if let id = cell.sessionId {
            NavigationLink { SessionDetailView(sessionId: id) } label: { mark }
                .buttonStyle(.plain)
                .onyxPress()
        } else {
            mark
        }
    }

    private func dayMark(_ cell: WorkoutWeek.DayCell) -> some View {
        let tint = Color.onyx.day(cell.dayKey)
        return VStack(spacing: OnyxSpace.xs) {
            Text(cell.initial)
                .onyxType(.micro)
                .textCase(.uppercase)
                // Today's letter is the one thing in the row that is not
                // tertiary, so the eye lands on it before it counts anything.
                .foregroundStyle(cell.isToday ? Color.onyx.textPrimary : Color.onyx.textTertiary)
            ZStack {
                if cell.isToday {
                    Circle().strokeBorder(Color.onyx.hairline, lineWidth: 1).frame(width: 32, height: 32)
                }
                if cell.isRest {
                    Circle().fill(Color.onyx.textTertiary).frame(width: 6, height: 6)
                } else if cell.isLogged {
                    Circle().fill(tint).frame(width: 22, height: 22)
                } else {
                    Circle().strokeBorder(tint.opacity(cell.isFuture ? 0.55 : 0.9), lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(height: 32)
            // A bout draws under the day rather than beside it: cardio is a
            // second thing that happened on the date, not a second kind of day.
            Circle()
                .fill(cell.hasCardio ? OnyxDomain.body.accent : .clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 36)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cellLabel(cell))
    }

    private func cellLabel(_ cell: WorkoutWeek.DayCell) -> String {
        let day = LogicalDay.date(fromISO: cell.date)?.formatted(.dateTime.weekday(.wide).day().month()) ?? cell.date
        let state = cell.isRest ? "rest" : cell.isLogged ? "logged, \(cell.label ?? "session")" : "planned, \(cell.label ?? "session")"
        return "\(day), \(state)\(cell.hasCardio ? ", cardio" : "")"
    }

    // MARK: - Today's session

    /// The finished session on this tab, or nil when today has not been logged.
    private var doneSessionId: String? {
        if case let .done(id, _, _, _, _) = state { return id }
        return nil
    }

    @ViewBuilder
    private func sessionCard(_ day: ProgramDay) -> some View {
        if case let .done(id, sets, volumeKg, minutes, prCount) = state {
            // ── LOGGED: THE SAME MASTHEAD THE SESSION PAGE OPENS WITH ───────
            // A finished day does not need its prescription read back to it,
            // and it does not need a THIRD layout for facts the session page
            // and the Pulse day already state: this card, the summary page's
            // band and Pulse's workout card were three renderings of one
            // session that drifted apart one edit at a time. `SessionHeaderCard`
            // is the one of them that survives (A6) — so the card you tap and
            // the page it opens are the same card, and the transition is the
            // page arriving under a header that never moved.
            //
            // The four numbers ride in as `totals`: the page drops them because
            // its metric grid is the next thing down, and this card is the only
            // place they are said at all.
            let summary = doneSummary(sets: sets, volumeKg: volumeKg, minutes: minutes, prCount: prCount)
            NavigationLink {
                SessionDetailView(sessionId: id)
                    // ── THE CARD GROWS INTO THE PAGE (§W2 H) ────────────────
                    // The card and the page open with the SAME masthead
                    // (`SessionHeaderCard`), so the push was the one animation
                    // that could not be read: an identical band slid in from
                    // the right over an identical band. A zoom says what
                    // actually happened — this card became that page — and the
                    // exit travels the same path, which is the rule the whole
                    // sprint's spatial consistency rests on.
                    //
                    // On the destination itself and not on the stack, the same
                    // placement the logger cover takes: the modifier's own
                    // documentation says the view that appears within the
                    // stack, outside of any containers.
                    .navigationTransition(.zoom(sourceID: Self.doneTransitionID, in: zoom))
            } label: {
                if let header = doneHeader, header.id == id {
                    SessionHeaderCard(header: header, totals: summary)
                } else {
                    // The header is a career-wide read; the label, the four
                    // numbers and the day's three muscles are all on the
                    // snapshot already. A card that drew nothing until the read
                    // landed would blink on every open of the tab — and one
                    // that drew a grey box made the finished session, which is
                    // the subject of this tab, the plainest thing on it (W5).
                    SessionFallbackCard(
                        dayKey: day.key, label: day.label, totals: summary,
                        muscles: week?.snapshot.doneMuscles ?? []
                    )
                }
            }
            .buttonStyle(.plain)
            .onyxPress(scale: 0.98)
            // OUTERMOST, and after `.onyxPress`: the source rect is this view's
            // bounds, so a press transform still applied at tap-up would start
            // the zoom from a shrunken rectangle. The clip shape is spelled
            // because the configuration only accepts a `RoundedRectangle` and
            // the default is square — the tile's own corner has to be said out
            // loud or the zoom begins from a box the card never was.
            .matchedTransitionSource(id: Self.doneTransitionID, in: zoom) {
                $0.clipShape(RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous))
            }
            // ── ONE BUTTON, NOT A CONTAINER OF FOUR LABELS ──────────────────
            // The card is a whole `NavigationLink` here, and its rows would
            // otherwise be exposed as four separate elements — a title, a
            // number, a tag row and a muscle row — none of which is the thing
            // a VoiceOver reader double-taps. On the session page the same card
            // is a static row and its parts are read in order, which is why the
            // grouping is decided by the caller and not by the card.
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the session summary")
        } else {
            planCard(day)
        }
    }

    private func planCard(_ day: ProgramDay) -> some View {
        let exercises = day.exercises(for: phase)
        return VStack(alignment: .leading, spacing: OnyxSpace.m) {
            HStack(alignment: .top, spacing: OnyxSpace.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.label)
                        .onyxDisplay()
                        .foregroundStyle(Color.onyx.dayLabel(day.key))
                    Text("\(exercises.count) exercises · \(day.plannedSets(for: phase)) sets")
                        .onyxType(.caption).onyxNumeral()
                        .foregroundStyle(Color.onyx.textSecondary)
                }
                Spacer(minLength: OnyxSpace.s)
                // 44 pt, not 88: the figure on this card says WHERE, and where
                // is legible at a thumbnail. The 96 pt hit-tested one lives on
                // the session page, which is the screen about the landing.
                AtlasFigure(side: .front, worked: worked(day), monochromeTint: accent, isThumbnail: true)
                    .frame(height: 44)
                    .accessibilityHidden(true)
            }

            // ── WHAT EACH ROW SAYS NOW ──────────────────────────────────────
            // It said `3 × 10-15`: a set count and the programmed rep window.
            // The window is the one thing on this screen the reader already
            // knows — it has not moved in eight weeks — and it is asserted by
            // the plan rather than earned, so it made the card a restatement of
            // the routine rather than a briefing.
            //
            // It now says what was actually done the last time this split was
            // trained: the top set, its effort, one line. That is the number
            // you have to beat, and it is the only number a set of double
            // progression is decided against. `WorkoutWeek.Previous` says why
            // the source is the same `day_key` and not "the last time you
            // trained this lift".
            //
            // A movement the last session did not hold prints NOTHING rather
            // than falling back — see `Previous`. A blank row is honest; a
            // number from a different day is not, and this card is read at a
            // glance where there is no room to caption the exception.
            VStack(spacing: 2) {
                ForEach(exercises) { exercise in
                    HStack(spacing: OnyxSpace.s) {
                        Text(exercise.name)
                            .onyxType(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: OnyxSpace.s)
                        if let top = week?.snapshot.previous?.top(for: exercise.name) {
                            Text(Self.lastLine(top))
                                .onyxType(.secondary).onyxNumeral()
                                .foregroundStyle(Color.onyx.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    .frame(minHeight: 36)
                    .accessibilityElement(children: .combine)
                }
            }

            if let previous = week?.snapshot.previous {
                previousDoor(previous)
            }
        }
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.tile)
        .foregroundStyle(Color.onyx.textPrimary)
        .contextMenu { dayMenu }
    }

    /// `Last: 72.5 kg × 15 @ 8.5` — or `Last: 66s @ 9` for a hold, and
    /// `Last: 18 reps @ 8.5` where nothing was loaded.
    ///
    /// One line, one set. `SetFormat.format` is the app's own spelling of a set
    /// and is reused rather than re-written here: a card that formats its own
    /// numbers is how `0 kg × 18` gets printed on a knee raise.
    static func lastLine(_ top: WorkoutWeek.TopSet) -> String {
        var line = "Last: " + SetFormat.format(weightKg: top.weightKg, reps: top.reps, timed: top.timed)
        if let rpe = top.rpe { line += " @ \(jsToFixed1(rpe))" }
        return line
    }

    /// The door to the whole of last time.
    ///
    /// ── WHY A DOOR AND NOT MORE ROWS ────────────────────────────────────────
    /// Every set of the previous session is between fourteen and twenty-two
    /// numbers, and this card is read standing in a gym doorway. The top set is
    /// the briefing; the session page is the document — and it already exists,
    /// already has the ledger, the muscle figure, the records and the deltas.
    /// Pushing the reader there costs one tap and duplicates nothing.
    ///
    /// A SHEET rather than a push: the plan you are about to perform stays on
    /// screen underneath, and the gesture back out is the one the reader's
    /// thumb is already on. `.large` because the session page is a page.
    private func previousDoor(_ previous: WorkoutWeek.Previous) -> some View {
        Button {
            reviewing = Review(id: previous.id)
        } label: {
            HStack(spacing: OnyxSpace.xs) {
                Image(systemName: "clock.arrow.circlepath")
                    .onyxType(.caption)
                Text(Self.previousLabel(previous.date))
                    .onyxType(.caption)
                Image(systemName: "chevron.right")
                    .onyxType(.micro)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
            .foregroundStyle(accent)
            .padding(.horizontal, OnyxSpace.s)
            .padding(.vertical, OnyxSpace.xs)
            .frame(minHeight: 32)
            .background(accent.opacity(0.12), in: .capsule)
            // AFTER the capsule, so the whole pill is the target and not just
            // the glyphs inside it.
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onyxPress()
        .accessibilityLabel("Open the previous session")
        .accessibilityHint("Shows the full summary of \(Self.previousLabel(previous.date))")
    }

    /// "Open last · Thu 4 Sep". The DATE is the point — "last session" alone
    /// leaves the reader unable to tell a four-day gap from a fortnight.
    static func previousLabel(_ iso: String) -> String {
        guard let date = LogicalDay.date(fromISO: iso) else { return "Open last session" }
        return "Open last · " + date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Long-press the card: the three things you can do to a DAY, as against
    /// the one thing the footer does (start the session). A `contextMenu`
    /// rather than three buttons on the tile — these are rare, and a tile that
    /// carries its rare actions on its face is the tile §5.2 shrank.
    @ViewBuilder
    private var dayMenu: some View {
        Button("Change phase", systemImage: "arrow.triangle.2.circlepath") { showPhase = true }
        Button("Take a rest day…", systemImage: "moon.zzz") { swapping = true }
        Button("Swap this day…", systemImage: "arrow.triangle.swap") { swapping = true }
    }

    private func doneSummary(sets: Int, volumeKg: Double, minutes: Double?, prCount: Int) -> String {
        var parts = ["\(OnyxFormat.volume(volumeKg)) kg", "\(sets) sets"]
        if prCount > 0 { parts.append("\(prCount) PR") }
        if let minutes, minutes > 0 { parts.append("\(jsIntegerString(jsRound(minutes))) min") }
        return parts.joined(separator: " · ")
    }

    private var restCard: some View {
        VStack(spacing: OnyxSpace.s) {
            Image(systemName: "figure.walk")
                .onyxType(.hero)
                .imageScale(.large)
                .foregroundStyle(accent)
            Text("Zone-2 rest")
                .onyxDisplay()
            Text("Nothing is scheduled today. A walk, and back tomorrow.")
                .onyxType(.secondary)
                .foregroundStyle(Color.onyx.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(OnyxSpace.xl)
        .onyxGlass(.tile)
        .foregroundStyle(Color.onyx.textPrimary)
        // A rest day is exactly the day you want to PLACE a session on, so it
        // carries the same menu rather than being the one card you cannot act
        // on.
        .contextMenu {
            Button("Place a workout here…", systemImage: "arrow.triangle.swap") { swapping = true }
        }
    }

    /// Landmark → 0…1 for the day's prescription, so the figure shows where the
    /// session will land before a set is logged.
    private func worked(_ day: ProgramDay) -> [LandmarkMuscle: Double] {
        MuscleCredit.worked(from: MuscleCredit.weightedSets(
            day.exercises(for: phase).map { .init(physicalSets: $0.sets(for: phase), movers: $0.movers) }
        ))
    }

    // MARK: - Ready to progress

    /// Double progression, stated as an instruction.
    ///
    /// ── WHY IT IS ABSENT MOST DAYS, AND THAT IS THE POINT ───────────────────
    /// The rule is the program's own: every working set at the ceiling, at ONE
    /// load, at RPE ≤ 8.5, in TWO consecutive sessions. That fires rarely — which
    /// is what makes the box worth reading when it appears. A panel that is
    /// always there, always saying "keep going", is a panel nobody looks at.
    @ViewBuilder
    private var progressionCard: some View {
        let rows = week?.snapshot.progression ?? []
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Text("Ready to progress").onyxMicro()
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(spacing: OnyxSpace.s) {
                            Text(row.name)
                                .onyxType(.body)
                                .lineLimit(1)
                                .foregroundStyle(Color.onyx.textPrimary)
                            Spacer(minLength: OnyxSpace.s)
                            Text(row.detail)
                                .onyxType(.secondary).onyxNumeral()
                                // Green is the verdict "go"; gold is "nearly",
                                // which is the record colour doing the one other
                                // job it is allowed — pointing at a threshold.
                                .foregroundStyle(row.ready ? Color.onyx.good : Color.onyx.record)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                        if row.id != rows.last?.id {
                            Divider().overlay(Color.onyx.hairline)
                        }
                    }
                }
            }
            .padding(OnyxSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onyxGlass(.tile)
        }
    }

    // MARK: - The doors

    /// Library · History · Trends, as three cells with a number on each.
    ///
    /// ── WHY THEY LEFT THE NAVIGATION BAR ────────────────────────────────────
    /// They were three glyphs in the top-right corner: a book, a clock and a
    /// chart, 24 pt each, side by side, with no labels and nothing to say. Three
    /// unlabelled icons in a row is the pattern iOS uses for ACTIONS on the
    /// thing you are looking at — and these are not actions, they are three
    /// other screens. They also left "Workout" no room for its own title.
    ///
    /// As cells they can carry the one number that makes a door worth opening:
    /// how much is behind it. A door with a number on it is a door you decide
    /// about; a chart glyph is one you tap to find out.
    /// ── AND WHY TRENDS LEFT THE STRIP (W6) ─────────────────────────────────
    /// Library and History carry a COUNT — `7 lifts`, `3 this month` — and a
    /// count fits in a third of a row. Trends now carries a SENTENCE: the
    /// window the delta was taken over, and where the week lands at this rate.
    /// `vs same point last week · on pace 32 t` is 38 characters, and a 109 pt
    /// cell renders it as `vs same point last / week · on pace 1…` — with the
    /// projection, which is the half the caption exists for, inside the
    /// ellipsis.
    ///
    /// So the two counts keep the strip and the sentence gets a line. Shrinking
    /// the type was the other option and it is the worse one: the caption is
    /// already `micro`, and a figure a reader has to lean in for is a figure
    /// they take on trust — which is how the old `−30.0 t` survived four waves.
    private var doorsRow: some View {
        VStack(spacing: OnyxSpace.grid) {
            if typeSize.isAccessibilitySize {
                VStack(spacing: OnyxSpace.grid) { doors }
            } else {
                HStack(spacing: OnyxSpace.grid) { doors }
            }
            if shows(.trends) { trendsDoor }
        }
    }

    @ViewBuilder
    private var doors: some View {
        door("Library", systemImage: "books.vertical", value: liftsTracked, unit: "lifts") {
            ExerciseLibraryView()
        }
        door("History", systemImage: "clock", value: sessionsThisMonth, unit: "this month") {
            HistoryView()
        }
    }

    /// The week's delta, the window it was taken over, and the projection.
    ///
    /// The value sits on the TITLE's line rather than under it, which is what
    /// the extra width buys: a full-width cell with a 20 pt figure on a line of
    /// its own is a banner, and this is a door. Two lines, one for the fact and
    /// one for the sentence that qualifies it.
    private var trendsDoor: some View {
        NavigationLink {
            TrainingTrendsView()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                // ── ONE COLUMN AT AN ACCESSIBILITY SIZE ─────────────────────
                // The same collapse `WeekVitalsRow` and the wrap-up's headline
                // already make, for the reason they state: a figure shown as an
                // ellipsis is worse than one not shown. At AX5 a 40 pt `+7.6 t`
                // beside the label left the label as `Tre…`, which is a door
                // that no longer says where it goes.
                //
                // Explicitly on `typeSize` and NOT `ViewThatFits`: that builder
                // picks the first child that fits and silently keeps the last
                // one when none does, so the fallback it chooses on a narrow
                // screen is a truncation rather than a stack (memory:
                // `w1b-week-detail`, `epic-sprint-w4-loggers`).
                if typeSize.isAccessibilitySize {
                    trendsTitle
                    HStack(spacing: OnyxSpace.xs) {
                        trendsValue
                        chevron
                    }
                } else {
                    HStack(spacing: OnyxSpace.xs) {
                        trendsTitle
                        Spacer(minLength: OnyxSpace.s)
                        trendsValue
                        chevron
                    }
                }
                Text(trendsCaption)
                    .onyxType(.micro)
                    .foregroundStyle(Color.onyx.textTertiary)
                    // NO `lineLimit`. The caption is a sentence and the figure
                    // it exists to carry is at its END — `on pace 13.0 t` — so
                    // any cap at all puts the payload inside the ellipsis. One
                    // line at every ordinary size in a full-width cell, and as
                    // many as it needs above them.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(OnyxSpace.s)
            .onyxGlass(.tile)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.98)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trends, \(weekDelta) \(trendsSpoken)")
        .accessibilityAddTraits(.isButton)
    }

    private var trendsTitle: some View {
        HStack(spacing: OnyxSpace.xs) {
            Image(systemName: "chart.xyaxis.line")
                .onyxType(.caption)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text("Trends")
                .onyxType(.micro)
                .foregroundStyle(Color.onyx.textSecondary)
                .lineLimit(1)
        }
        // The label never gives way to the figure: an `HStack` shrinks the
        // child it is cheapest to shrink, and here that was the word.
        .layoutPriority(1)
    }

    private var trendsValue: some View {
        Text(weekDelta)
            .onyxType(.display).onyxNumeral()
            .foregroundStyle(Color.onyx.textPrimary)
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .onyxType(.caption)
            .foregroundStyle(Color.onyx.textTertiary)
            .accessibilityHidden(true)
    }

    private func door<Destination: View>(
        _ title: String, systemImage: String, value: String, unit: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: OnyxSpace.xs) {
                    Image(systemName: systemImage)
                        .onyxType(.caption)
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                    Text(title)
                        .onyxType(.micro)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(value)
                    .onyxType(.display).onyxNumeral()
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(unit)
                    .onyxType(.micro)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 64 pt of CELL (§W9), which three lines of 11/20/11 fill exactly
            // at `s` padding. `m` made it 83 and the row stopped reading as a
            // strip of doors.
            .frame(minHeight: 64)
            .padding(OnyxSpace.s)
            .onyxGlass(.tile)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.98)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value) \(unit)")
        .accessibilityAddTraits(.isButton)
    }

    private var liftsTracked: String {
        week.map { "\($0.snapshot.liftsTracked)" } ?? "—"
    }

    private var sessionsThisMonth: String {
        week.map { "\($0.snapshot.sessionsThisMonth)" } ?? "—"
    }

    /// Tonnes, signed. A delta with no sign is a number you have to look up the
    /// other week to read.
    ///
    /// `—` and not `0.0 t` when there is nothing to compare: a zero is a claim
    /// that the two weeks matched, and `weekDeltaKg` is nil precisely when no
    /// such claim can be made.
    private var weekDelta: String {
        guard let delta = week?.snapshot.weekDeltaKg else { return "—" }
        let tonnes = delta / 1000
        let sign = tonnes > 0 ? "+" : tonnes < 0 ? "−" : ""
        return "\(sign)\(jsToFixed1(abs(tonnes))) t"
    }

    /// `vs same point last week · on pace 32 t` (A7).
    ///
    /// ── WHY THE CAPTION NAMES THE COMPARISON ────────────────────────────────
    /// The number above it used to be a full week subtracted from a partial
    /// one, and nothing on the screen said so — which is how it went four waves
    /// printing `−30.0 t` on Sunday mornings. Now the comparison is honest AND
    /// stated, because a delta whose window is left to be guessed is a delta
    /// that can drift back to the wrong window without anyone noticing.
    ///
    /// Each half is dropped when it has nothing behind it, so the caption never
    /// promises a figure the door is not showing.
    private var trendsCaption: String { trendsCaptionParts.joined(separator: " · ") }

    /// The same sentence for VoiceOver, with the `·` back as a comma — a
    /// visual separator read aloud is one more thing in the sentence.
    private var trendsSpoken: String { trendsCaptionParts.joined(separator: ", ") }

    private var trendsCaptionParts: [String] {
        var parts: [String] = []
        if week?.snapshot.weekDeltaKg != nil { parts.append("vs same point last week") }
        if let pace = week?.snapshot.weekPaceKg {
            parts.append("on pace \(jsToFixed1(pace / 1000)) t")
        }
        // A door with neither half says what it is waiting for rather than
        // standing under a dash with no caption at all.
        return parts.isEmpty ? ["nothing to compare yet"] : parts
    }

    /// Whether a section of this tab is showing (W6). `true` until the read
    /// lands — the tab that has always been there is the honest first frame,
    /// and a screen that assembles itself card by card on every launch reads
    /// as a bug.
    private func shows(_ section: TrainSection) -> Bool {
        week?.snapshot.trainLayout.shows(section) ?? true
    }

    // MARK: - Cardio

    /// The last bout in full, and the eight before it as a trail.
    ///
    /// ── WHY IT GREW, AND WHAT IT LOST AGAIN (W5) ────────────────────────────
    /// It was one 44 pt row: a glyph, the word "Cardio", and a line of
    /// `type · km · min · pace` truncated to whatever fitted. Everything that
    /// makes a bout worth reading — when it was, how hard it was — was either
    /// missing or squeezed out by `lineLimit(1)`. Cardio is the second half of
    /// this tab's subject and it was the smallest thing on the screen.
    ///
    /// What grew back too far was the Zone 2 RAIL. Its own arithmetic was
    /// sound — `zone2Done` counts this week's bouts over `Zone2.minMinutes`
    /// and `Zone2.weeklyTarget` is a target count of the same thing, so 1/2
    /// was a fraction that meant something. What was wrong was drawing it as a
    /// GAUGE, one line under the last bout's `avg bpm`: a filled bar under a
    /// heart rate reads as a heart-rate bar, and `cardio_logs` has an `avg_hr`
    /// column and no zone column, so there was no reading behind that promise
    /// and never could be. The rail is gone and the count is a caption on the
    /// header, which is what a count of sessions this week has always been.
    ///
    /// ponytail: the caption still says "Zone 2" for a rule that is purely
    /// about duration. That name is the app's vocabulary — `Zone2` in OnyxCore
    /// and the widget face both — so renaming it is a change to four surfaces
    /// and a founder's word, not to this card.
    ///
    /// The figures the bout DOES know now speak the session page's vocabulary
    /// exactly — `MetaTagRow.Capsule`, the same glyphs, the same `cardio`
    /// tint — because the ledger's own bout card (W4) says the same four facts
    /// about the same row, and two drawings of one reading is how they come to
    /// disagree.
    private var cardioCard: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                VStack(alignment: .leading, spacing: 2) {
                    OnyxSectionHeader("Cardio", .body)
                    zone2Caption
                }
                Spacer(minLength: 0)
                Button { loggingCardio = true } label: {
                    Image(systemName: "plus")
                        .onyxType(.body).fontWeight(.semibold)
                        .foregroundStyle(Color.onyx.cardio)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .onyxPress()
                .accessibilityLabel("Log cardio")
            }
            // The button's own 44 pt box already carries the row's height, so
            // the header does not ask for any of its own.
            .padding(.trailing, -OnyxSpace.m)

            if let bout = week?.snapshot.lastCardio {
                lastBout(bout)
                if trail.count >= 2 {
                    Sparkline(points: trail, color: Color.onyx.cardio)
                        .frame(height: 22)
                        .accessibilityHidden(true)
                    Text("last \(trail.count) bouts · minutes")
                        .onyxType(.micro)
                        .foregroundStyle(Color.onyx.textTertiary)
                }
            } else {
                Text("No bouts logged yet.")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textSecondary)
            }
        }
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.tile)
        .accessibilityElement(children: .contain)
    }

    /// Type and when on one line, then every reading the bout carries.
    private func lastBout(_ bout: CardioLogRow) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            // The masthead's own rule: at the accessibility sizes there is no
            // arrangement of "Outdoor Cycling" and "Sun 6 Sep · 08:00" that
            // fits across a 375 pt line, so the stamp takes its own.
            Shoulders {
                HStack(spacing: OnyxSpace.xs) {
                    Image(systemName: CardioKind(bout.kind).symbol)
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.cardio)
                        .accessibilityHidden(true)
                    Text(CardioKind(bout.kind).label)
                        .onyxType(.body)
                        .foregroundStyle(Color.onyx.textPrimary)
                        .lineLimit(2)
                }
            } trailing: {
                Text(boutStamp(bout))
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            MetaTagRow(tags: boutTags(bout))
        }
        // `.combine` and not `.ignore` plus a hand-built string: `MetaTagRow`
        // already says what each of its capsules is, including the one whose
        // glyph is the reading, and a second spelling of that list here is one
        // more place for the screen and the reader to come apart.
        .accessibilityElement(children: .combine)
    }

    /// Every reading a logged bout can carry, and only the ones it does — in
    /// the session page's own vocabulary (`SessionDetailView.cardioTags`, W4),
    /// because that card describes THIS row and the two must agree.
    ///
    /// An absent capsule says the bout never had the figure. Nothing here ever
    /// prints an em dash: `formatPace` answers `"—"` for anything it cannot
    /// divide, and a capsule holding an em dash is a reserved slot pretending
    /// to be a reading.
    private func boutTags(_ bout: CardioLogRow) -> [MetaTagRow.Tag] {
        var tags: [MetaTagRow.Tag] = []
        if let min = bout.durationMin, min > 0 {
            tags.append(.init("\(jsIntegerString(jsRound(min))) min",
                              symbol: "timer", tint: Color.onyx.cardio))
        }
        if let m = bout.distanceM, m > 0 {
            tags.append(.init("\(jsToFixed1(m / 1000)) km",
                              symbol: "figure.run", tint: Color.onyx.cardio))
        }
        // The OPTIONAL is the guard, not a comparison against `formatPace`'s
        // em-dash: the sentinel is one character in another file and a capsule
        // holding an em dash is the reserved slot this function refuses to draw.
        if let pace = CardioMetrics.paceMinPerKm(
            distanceM: bout.distanceM, durationMin: bout.durationMin
        ) {
            tags.append(.init(CardioMetrics.formatPace(pace),
                              symbol: "speedometer", tint: Color.onyx.cardio))
        }
        // A heart rate is a whole number: the column is a Double and printed
        // "131.0", which reads as a precision the sensor does not have.
        if let hr = bout.avgHr, hr > 0 {
            tags.append(.init("\(jsIntegerString(jsRound(hr))) bpm",
                              symbol: "heart.fill", tint: Color.onyx.cardio))
        }
        // The app's own glyph for "this came from Apple Health", and the
        // session page's own words for it.
        if bout.fromHealthkit == true {
            tags.append(.init("Automatically logged",
                              symbol: "heart.text.square", tint: Color.onyx.textSecondary))
        }
        return tags
    }

    /// `Today · 08:00`, or just the day.
    ///
    /// ── THE TIME IS PRINTED ONLY FOR AN IMPORTED BOUT ───────────────────────
    /// `cardio_logs` has no start-time column, so `created_at` carries two
    /// different facts and `CardioImport` is where they are told apart: on a
    /// row HealthKit filed it is the bout's own START, and on a row the founder
    /// typed it is the moment they typed it. A walk done at 08:00 and entered
    /// at 21:00 would be stamped 21:00, which is a time the bout never had.
    ///
    /// So the clock appears on exactly the rows that earned it — the same rows
    /// the "Automatically logged" capsule appears on, which is what makes the
    /// pair legible: a bout that says when it was also says who timed it.
    private func boutStamp(_ bout: CardioLogRow) -> String {
        var parts = [boutWhen(bout)]
        if bout.fromHealthkit == true, let start = bout.createdAt {
            parts.append(start.formatted(date: .omitted, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }

    private func boutWhen(_ bout: CardioLogRow) -> String {
        if bout.date == week?.today { return "Today" }
        guard let date = LogicalDay.date(fromISO: bout.date) else { return bout.date }
        return OnyxChart.shortDate(date)
    }

    /// The eight most recent bouts, in minutes. Minutes rather than distance
    /// because Zone 2 — the count in this card's header — is a rule about
    /// duration, and a walk with no distance still counts towards it.
    private var trail: [Double] {
        (week?.snapshot.recentCardio ?? []).compactMap { $0.durationMin }.filter { $0 > 0 }
    }

    /// The week's Zone 2, as a caption on the section's own title.
    ///
    /// Zone 2 is a COUNT of sessions over the minute floor, never a minute
    /// total — `Zone2` says so and the widget face already draws it that way.
    /// A count against its target is a fraction that means something, which is
    /// exactly what the rail this replaces was not: there, `2` was the
    /// constant `Zone2.weeklyTarget` and the figure a line above it was the
    /// last bout's average heart rate.
    ///
    /// Under the title rather than beside it: three objects on the header's one
    /// line are the "Cardio", the count and a 44 pt button, and at AX5 that is
    /// the collision no `ViewThatFits` can measure its way out of.
    private var zone2Caption: some View {
        let done = week?.snapshot.zone2Done ?? 0
        let target = Zone2.weeklyTarget
        return Text("Zone 2 · \(done)/\(target) this week")
            .onyxType(.caption).onyxNumeral()
            .foregroundStyle(done >= target ? Color.onyx.good : Color.onyx.textTertiary)
            // Two lines and not one: at AX5 this string is wider than the space
            // left beside a 44 pt button, and `minimumScaleFactor` alone would
            // spend its whole budget and then truncate the count — the half of
            // the sentence the caption exists for.
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .accessibilityLabel("Zone 2 this week, \(done) of \(target) sessions")
    }

    // MARK: - The door

    /// Nothing at all once the day is logged.
    ///
    /// ── WHY `.done` HAS NO FOOTER, NOT EVEN A QUIET ONE ─────────────────────
    /// It had a "Session complete" strip. The card above it already says the
    /// session is done, already carries its tonnage and sets, and already links
    /// to the summary — so the strip restated the card in words and cost a 44 pt
    /// band plus the material bar behind it to do it. A footer that only ever
    /// agrees with the thing above it is a footer that has stopped being a
    /// control, and the founder has now asked for it gone twice.
    ///
    /// The whole band goes with it, material and hairline included: leaving the
    /// bar with an empty `Group` inside would still paint a 26 pt strip of glass
    /// across the bottom of the screen with nothing in it.
    /// ── AND WHY THE BAND IS NOW THE BUTTON'S AND NOT THE FOOTER'S ───────────
    /// The `.regularMaterial` strip plus its hairline used to wrap whatever the
    /// footer drew. That was right for a full-bleed BUTTON, which has no
    /// surface of its own and needs something to separate it from the content
    /// scrolling underneath. It is wrong under the Mini Player, twice over:
    /// `.regularMaterial` is what `GlassLevel.chrome` resolves to and the card
    /// is `.tile`, so the two nest — one translucent surface on another, and
    /// both stop reading as glass, which is the one thing `onyxGlass`'s own
    /// documentation forbids. And the card does not span the width, so the band
    /// would paint a strip of material either side of it with nothing in it —
    /// the same empty-glass failure the `.done` case above is a note about.
    ///
    /// So the band moved INTO the `.none` branch, where the button still wants
    /// it, and the card carries its own surface and its own lift.
    @ViewBuilder
    private var footer: some View {
        if today != nil, !isDone {
            switch state {
            case .done:
                EmptyView()
            case let .live(sets, volumeKg):
                // `session` is the live model this tab keeps across the cover
                // being dismissed (`:44`), and it is the ONE thing that knows
                // the clock, the deck cursor and the records. The week
                // snapshot's `.live` numbers are a second, staler answer to two
                // of the five facts the card draws (F1).
                //
                // It can still be nil while `state` says live — the app was
                // relaunched mid-session, or the watch opened it — and there is
                // no model to minimise then, only a session to resume. That is
                // what the fallback is: the old button, doing the only job
                // still available to it.
                if let session {
                    // `start` and not `presented = session`: opening the deck
                    // also republishes the progression alerts for today's key,
                    // and it already refuses to mint a second model for a day
                    // it is holding one for. One door into the logger.
                    MiniPlayerCard(model: session, onOpen: start)
                        // OUTERMOST on the card, and after `.onyxPress` inside
                        // it: the source rect is this view's bounds, so a press
                        // transform still applied at tap-up would start the
                        // zoom from a shrunken rectangle. The clip shape is
                        // spelled because the configuration only accepts a
                        // `RoundedRectangle` and the default is square — the
                        // tile's own corner has to be said out loud or the zoom
                        // begins from a box the card never was.
                        .matchedTransitionSource(id: MiniPlayerCard.transitionID, in: zoom) {
                            $0.clipShape(
                                RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous)
                            )
                        }
                        .padding(.horizontal, OnyxSpace.l)
                        .padding(.bottom, OnyxSpace.s)
                } else {
                    banded {
                        startButton(
                            title: "Resume workout",
                            detail: liveSummary(sets: sets, volumeKg: volumeKg),
                            icon: "play.fill"
                        )
                    }
                }
            case .none:
                banded {
                    startButton(
                        title: "Start workout", detail: nil,
                        icon: "figure.strengthtraining.traditional"
                    )
                }
            }
        }
    }

    /// The material strip a full-bleed button stands on. See `footer`.
    private func banded(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(.horizontal, OnyxSpace.l)
            .padding(.vertical, OnyxSpace.s)
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
            }
            .overlay(alignment: .top) {
                Color.onyx.hairline.frame(height: 0.5)
            }
    }

    private func startButton(title: String, detail: String?, icon: String) -> some View {
        Button(action: start) {
            HStack(spacing: OnyxSpace.m) {
                Image(systemName: icon)
                    .onyxType(.display)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .onyxType(.body).fontWeight(.semibold)
                        .minimumScaleFactor(0.8)
                    if let detail {
                        Text(detail)
                            .onyxType(.caption).onyxNumeral()
                            .opacity(0.85)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .onyxType(.caption).fontWeight(.bold)
                    .opacity(0.7)
            }
            .foregroundStyle(Color.onyx.textPrimary)
            .padding(.horizontal, OnyxSpace.l)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                OnyxDomain.train.ramp,
                in: RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous)
            )
        }
        .onyxPress(scale: 0.98)
        .accessibilityHint("Opens the logger and starts the Live Activity")
    }

    private func liveSummary(sets: Int, volumeKg: Double) -> String {
        "\(sets) sets · \(OnyxFormat.volume(volumeKg)) kg"
    }

    // MARK: - Actions

    private func start() {
        guard let day = today else { return }
        if session == nil || session?.day.key != day.key {
            // A card carries its workout's name in `attributes`, which is fixed
            // for the life of the activity — so a new session feeding the old
            // activity would update a Lock Screen that still says yesterday.
            if session != nil { activity.end() }
            // `logger.open` covers the seed: `LoggerModel.init` reads the
            // day's sessions and sets SYNCHRONOUSLY on purpose (see
            // `loadSeed`) — a deck that draws the plan first and the real
            // loads a frame later moves under the reader's thumb.
            let model = Perf.measure("logger.open") {
                LoggerModel(
                    day: day, phase: phase,
                    store: environment.database, userId: environment.userIdString
                )
            }
            session = model
        }
        // The logger graded today's queue while building its seed, and it is
        // the surface that knows the day key for certain. One array, read by
        // the tab card, the session banner and the row chip (decision 10).
        // `attach` is the view's job, on appear — publishing does not need it.
        environment.publishProgression(session?.progressionAlerts ?? [], for: day.key)
        presented = session
    }

    /// Put the logger over a session the WRIST opened (App Store W4).
    ///
    /// The same `start` the button runs — `attach` then finds the wrist's row
    /// by split and date, and `begin` has nothing to open. Which is why every
    /// guard is here: a row already finished (its open and its finish were
    /// queued back to back), a different split from the one this tab would
    /// open, or a session this tab is already holding would each have sent
    /// `begin` off to open a SECOND row beside the wrist's.
    private func followWrist(_ id: String) {
        let row = try? environment.database.session(id: id, userId: environment.userIdString)
        // `sessionId`, not the model: a Cancel leaves the tab holding its
        // model — emptied, for the next Start to reuse — and "holding one"
        // has to mean holding a SESSION or a cancelled deck blocks the wrist.
        guard session?.sessionId == nil, let day = today, let row,
              row.endedAt == nil, row.dayKey == day.key, row.date == LogicalDay.today()
        else {
            // Said, because the guard has five reasons and the screen shows none.
            return Logger(subsystem: "app.onyx.phone", category: "watch").notice(
                "not following \(id, privacy: .public): holding \(session?.sessionId ?? "nothing", privacy: .public), split \(today?.key ?? "none", privacy: .public), row \(row.map { "\($0.dayKey ?? "-") \($0.date) ended \($0.endedAt != nil)" } ?? "missing", privacy: .public)"
            )
        }
        start()
        // Before the cover appears: a deck that follows never opens a row of
        // its own (`LoggerModel.following`).
        session?.following = id
    }

    /// Drop the kept model if it was on a session the wrist ended — the store
    /// has already closed or deleted the row, and a kept model would go on
    /// offering to append to it. `following` as well as `sessionId`: a deck
    /// whose `attach` found the row already gone has no id, only the one it
    /// was presented for.
    private func letGo(_ id: String) {
        // `following` only for a deck that bound nothing: one that `attach`
        // bound to a different live row is not the wrist's, whatever it was
        // presented for.
        guard let held = session,
              held.sessionId == id || (held.sessionId == nil && held.following == id)
        else { return }
        held.stopRest()
        activity.end()
        session = nil
        // The cover's `onDismiss` is `reload`, which pushes the summary of a
        // finished one; a minimised session has no cover to dismiss.
        if presented != nil { presented = nil } else { reload() }
    }

    /// Re-read on every dismissal. Finishing a session changes the week panel,
    /// the card, the progression box and the Library's stats at once, and they
    /// all come from the same read — so there is one place that can be stale
    /// and one call that fixes it.
    private func reload() {
        let wasDone = isDone
        Task {
            await week?.refresh()
            // The workout ENDED during this cover. Close the kept model, play
            // the one `.success` §3.4 gives a finished session, and put the
            // summary on screen — the page is built synchronously from GRDB, so
            // it is complete the moment it appears.
            if !wasDone, case let .done(id, _, _, _, _) = state {
                session = nil
                finishes += 1
                summary = id
            }
        }
    }

    private var isDone: Bool {
        if case .done = state { return true }
        return false
    }
}

/// What each hideable section is called on the Customize sheet, and what it
/// wears there.
///
/// In the app and not in `OnyxCore` alongside the enum, for the reason
/// `Layout.swift`'s header gives about `WIDGET_META`: a name and an SF Symbol
/// are UI, and the pure package has no business holding either.
extension TrainSection {
    var title: String {
        switch self {
        case .doors: return "Library · History · Trends"
        case .trends: return "Trends"
        case .cardio: return "Cardio"
        case .progression: return "Ready to Progress"
        case .pastWeeks: return "Past Weeks"
        }
    }

    var symbol: String {
        switch self {
        case .doors: return "rectangle.split.3x1"
        case .trends: return "chart.xyaxis.line"
        case .cardio: return "figure.run"
        case .progression: return "arrow.up.forward"
        case .pastWeeks: return "books.vertical.fill"
        }
    }
}

/// The long press, said in words (W6 §3).
///
/// ── WHY A SHEET OF SWITCHES AND NOT A MENU OF VERBS ─────────────────────────
/// `TileMenu` is the precedent for what a press must SAY, and it makes its case
/// against a press that starts an opaque mode. It is not a precedent for the
/// control: a context menu closes on the first tap, so hiding three sections
/// there is three long presses on a screen that has just rearranged itself
/// twice underneath the thumb. Five switches in one visit is the same five
/// verbs, said once, with the result visible behind the sheet as each one lands.
///
/// The writes go THROUGH `set` as they are made rather than on dismiss. There
/// is no Cancel here and there should not be — every switch is instantly
/// reversible by flipping it back, and a sheet that hoards five changes behind
/// a Done button is a sheet that can lose them to a swipe.
/// The long press, said in words (W6 §3).
///
/// ── WHY A SHEET OF SWITCHES AND NOT A MENU OF VERBS ─────────────────────────
/// `TileMenu` is the precedent for what a press must SAY, and it makes its case
/// against a press that starts an opaque mode. It is not a precedent for the
/// modifier: `.contextMenu` renders a lifted snapshot of the view it is
/// attached to, and a context menu also closes on the first tap — so hiding
/// three sections there is three long presses on a screen that has rearranged
/// itself twice underneath the thumb. Five switches in one visit is the same
/// five verbs, said once, with the result visible behind the sheet as each
/// one lands.
///
/// `DaySheet` with no `primary`, which is its own documented case: "a sheet
/// whose every tap already saved gets Done". There is no Cancel here and there
/// should not be — every switch is instantly reversible by flipping it back,
/// and a sheet that hoards five changes behind a button is a sheet that can
/// lose them to a swipe.
///
/// Internal and not `private`: the screenshot harness presents it directly,
/// because a shot script cannot hold a finger down for 600 ms.
struct CustomizeTrainSheet: View {
    let layout: TrainLayout
    let set: (TrainSection, Bool) -> Void

    /// The sheet's own copy, so a switch moves under the thumb that moved it
    /// rather than on the next read of the tab behind it.
    @State private var hidden: Set<TrainSection>

    init(layout: TrainLayout, set: @escaping (TrainSection, Bool) -> Void) {
        self.layout = layout
        self.set = set
        _hidden = State(initialValue: Set(layout.hidden))
    }

    var body: some View {
        // `glass: false` — a `Form` draws its own rows and takes the form
        // ground, which is the branch `DaySheet` keeps for exactly this.
        DaySheet("Customize Train", domain: .train, glass: false) {
            Form {
                Section {
                    ForEach(TrainSection.allCases, id: \.self) { section in
                        Toggle(isOn: binding(section)) {
                            Label(section.title, systemImage: section.symbol)
                        }
                        // Trends is a door INSIDE the row above it, so with the
                        // row away there is nothing for this switch to do. Shown
                        // and disabled rather than hidden — the same call
                        // `TileMenu` makes about its own unavailable row: a
                        // control that vanishes is a control nobody learns
                        // exists.
                        .disabled(section == .trends && hidden.contains(.doors))
                    }
                } header: {
                    Text("Sections")
                } footer: {
                    Text(footer)
                }
            }
        }
    }

    private var footer: String {
        if hidden.contains(.doors) {
            return "The week strip and today's session always show. Trends is a door inside the row above it — bring the row back to use it."
        }
        return "The week strip and today's session always show — they are what the tab is for."
    }

    private func binding(_ section: TrainSection) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(section) },
            set: { visible in
                if visible { hidden.remove(section) } else { hidden.insert(section) }
                set(section, visible)
            }
        )
    }
}

#if DEBUG
#Preview("Workout") {
    NavigationStack {
        WorkoutTabView(seededDay: PlanTemplates.program("onyx5")?.day(key: "cb_b"))
    }
    .environment(AppEnvironment.preview)
    .preferredColorScheme(.dark)
}
#endif
