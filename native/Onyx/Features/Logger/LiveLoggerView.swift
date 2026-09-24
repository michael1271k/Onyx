import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// The Live Logger.
///
/// ── WHAT SURVIVED THE PORT AND WHAT DID NOT ─────────────────────────────────
/// The web deck (the web app's `components/command-center/`, 7,246 lines) got the data
/// hierarchy right: which workout, what it has accumulated, then the movements
/// in order with their sets. That hierarchy is reproduced exactly. Almost
/// nothing else is.
///
/// What is gone: a sticky header re-implemented in JavaScript, a hand-rolled
/// bottom sheet, a scroll-position memory, an edge-swipe gesture, a
/// pull-to-refresh. All five exist in the web app to imitate behaviour a
/// `NavigationStack`, a `.sheet` and a toolbar simply have.
///
/// ── AND WHAT WAVE 2.4 CHANGED ───────────────────────────────────────────────
/// Wave 1 hid the navigation bar and drew its own: a hero header that collapsed
/// into a compact one, three stat tiles, a floating rest bar with its own ring
/// and its own ± buttons. That is 180 pt of chrome above a set row, all of it
/// re-implementing something the system ships — and re-implementing it worse,
/// because the collapse animated a frame behind the scroll.
///
/// So the bar is the system's bar. The rest clock lived in it, as a capsule in
/// the principal slot, which is exactly where iOS puts a running timer in Phone
/// and in Voice Memos. Everything the header used to hold that is not a number
/// you are reading right now moved into the trailing menu, and what was left on
/// screen was one 44 pt strip of totals and the movement in front of you.
///
/// ── AND WHAT PHASE 3 MADE IT ────────────────────────────────────────────────
/// The logger is the flagship screen now, and a flagship cannot be a system
/// title over a strip of three numbers. Wave U1 gives it a hero in the day's own
/// colour — the split, the week, and a 34 pt clock you can stop — a segmented
/// control between two faces of one model, and a row of chips where a three-dot
/// menu used to hide four verbs.
///
/// What moved, and where it went:
///   • the 44 pt totals strip → the Live Stats face's `Now` card, with room to
///     say what each number is (`LiveStatsView`);
///   • `Text(startedAt, style: .timer)` in that strip → the hero's clock, which
///     is now pausable and correctable (`LoggerHero`, `TimerSheet`);
///   • the `.principal` rest capsule → under the hero (`LoggerRestCapsule`),
///     because a countdown you watch for ninety seconds is content;
///   • the trailing three-dot `Menu` → `OnyxChipRow`, where "Skip rest" is
///     absent rather than present-and-disabled;
///   • "Muscle distribution" → a card that draws the body, and still opens the
///     sheet it used to be a menu item for.
///
/// The navigation bar keeps exactly what it should: the two ways out.
struct LiveLoggerView: View {
    @State private var model: LoggerModel
    @State private var showDistribution = false
    @State private var showPhase = false
    @State private var showFinish = false
    @State private var showTimer = false
    /// The catalogue the "Add a movement" picker lists, read when it opens —
    /// nil while it is closed (W3).
    @State private var adding: [Exercise]?
    /// Bumped to scroll the deck to `focus` — see the picker's handler.
    @State private var scrollTick = 0
    /// The SET stopwatch, owned here and lent to `TimerSheet`.
    ///
    /// It cannot live in the sheet: a sheet's `@State` dies with the sheet, and
    /// the whole point of this control is to run through a hold — which is
    /// exactly when the reader swipes back to the deck to look at the set they
    /// are about to write into. The same argument `WorkoutTabView`'s header
    /// makes about `LoggerModel` and the Live Activity, one level down.
    @State private var watchStart: Date?
    @State private var watchAccumulated: TimeInterval = 0
    @State private var watchLaps: [TimeInterval] = []
    @State private var confirmCancel = false

    /// Which face, and how it got here — the animation travels with it.
    @State private var selection = LoggerFaceSelection()

    /// The session clock and the records are both `model` now.
    ///
    /// U1 built the hero, the timer sheet, the Records card and the Live
    /// Activity's paused face against `PauseControlling` and `LivePrProviding`
    /// while E4 built the engine that answers them, and this is where the two
    /// waves meet: `LoggerModel` conforms, so the pause reaches `set_events`
    /// and survives a relaunch, and the Records card draws
    /// `PrEngine.detectSessionPrs` against the same baselines the ledger is
    /// written from. Nothing else on this screen changed, which is what the
    /// protocols bought. `LoggerClock` and `SeedPrProvider` remain as the
    /// preview and test doubles they now only are.
    private var clock: any PauseControlling { model }
    private var prs: any LivePrProviding { model }
    /// Bumped when the rest clock reaches zero of its own accord — never when
    /// it is skipped or dragged into the past, both of which cancel the task
    /// below before it fires. §3.4 gives `.success` to "session finished"; a
    /// rest period that has run out is the same kind of event and it is the one
    /// the phone is in your pocket for.
    @State private var restExpiries = 0
    /// The movement you are WORKING ON — not the scroll offset.
    ///
    /// ── WHY THOSE ARE DIFFERENT THINGS NOW ──────────────────────────────────
    /// It used to be bound to `.scrollPosition` of a horizontal pager, so the
    /// two were the same fact by construction: the card on screen was the card
    /// you were on. A vertical list has no such identity — you scroll down to
    /// check what is coming and scroll back, and neither of those is a
    /// statement about which set you are standing in front of.
    ///
    /// So this is the logger's own cursor. Nothing writes it but `init` — the
    /// opening position — and a movement added mid-session, which you added
    /// to do next (W3); after that the reader's own scrolling. It used to
    /// be advanced on completing a movement; that is gone (see the
    /// `completedSets` observer).
    @State private var focus: String?

    /// `@State`, emphatically not `let`.
    ///
    /// A `View` is a struct that SwiftUI re-initialises on every parent redraw,
    /// so a stored `let` controller is a NEW controller each time — one that has
    /// forgotten the activity it started. The visible symptom is a Live Activity
    /// that appears once, never updates, and is still on the Lock Screen after
    /// the session ends, because nothing holds the handle any more.
    @State private var activity: LiveActivityController

    /// The phase survives a relaunch. Written here rather than in the model
    /// because it is a preference, and `LoggerModel` is a session — it should
    /// not know that a phase outlives the workout it was chosen for.
    @AppStorage("onyx.phase") private var storedPhase = ProgramPhase.cut.rawValue

    /// Presented as a full-screen cover by `WorkoutTabView`; this is how it leaves.
    @Environment(\.dismiss) private var dismiss

    /// OPTIONAL, and it has to be: `LoggerPreviews` and the shot harness present
    /// this screen with a model and no environment, and a non-optional
    /// `@Environment(AppEnvironment.self)` traps the moment it is read. Only the
    /// edit path needs it — to run the rescore cascade, which is the one thing
    /// `LoggerModel.finishEdit` deliberately does not do itself.
    @Environment(AppEnvironment.self) private var environment: AppEnvironment?

    /// `activity` is BORROWED from the Workout tab when the logger is presented
    /// as a cover, so dismissing the cover mid-session keeps the Lock Screen
    /// card alive and updatable. Previews and the harness pass nothing and get
    /// their own.
    ///
    /// `face` and `clock` are the same argument the finish sheet's harness case
    /// makes: a screen with a state nobody can reach is a screen nobody
    /// maintains. Live Stats and a paused session are two of this screen's three
    /// faces, and neither can be photographed by a shot script that can only
    /// launch it. They are ordinary parameters rather than debug flags because
    /// they are ordinary facts — which face is showing, and which clock is
    /// running. The clock is `model` itself since E4, so a harness that wants
    /// a paused screen pauses the model.
    init(
        model: LoggerModel,
        activity: LiveActivityController? = nil,
        face: LoggerFace = .workout,
        paused: Bool = false
    ) {
        _model = State(initialValue: model)
        _activity = State(initialValue: activity ?? LiveActivityController())
        // ── AND THE CURSOR STARTS DIFFERENTLY ON AN EDIT ───────────────────
        // `currentSet` is the first movement with an UNTICKED row, which on a
        // live deck is where you are standing. On a re-opened session every set
        // that was performed is already ticked, so it is the first lift the
        // session SKIPPED — and the deck opened six cards down, past every
        // movement the reader came here to correct. The top is the answer: an
        // edit is read in the session's own order, which `editorDay` now builds.
        _focus = State(initialValue: model.isEditing
            ? model.exercises.first?.id
            : (model.currentSet?.exercise.id ?? model.exercises.first?.id))
        _selection = State(initialValue: LoggerFaceSelection(face: face))
        if paused { model.pause() }
    }

    private var accent: Color { Color.onyx.day(model.day.key) }

    var body: some View {
        // ── WHY A `GeometryReader` AND NOT A MEASUREMENT ────────────────────
        // The page width had been measured on the stack itself, and that is a
        // loop: the stack's width set a frame inside the stack, which set the
        // stack's width. At an accessibility size it settled 55 pt wide of the
        // screen, and the Live Stats face came into view down the edge of the
        // deck. A `GeometryReader` takes the size PROPOSED to it and ignores
        // what its content would like, so `proxy.size.width` is the screen and
        // nothing inside can argue with it — which is also what stops the chip
        // row's own ideal width from widening the column it sits in.
        GeometryReader { proxy in
            stack(page: proxy.size.width)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .onyxScreen(.train)
        .foregroundStyle(Color.onyx.textPrimary)
        // The hero says which workout this is, in 28 pt and in the day's own
        // colour. A system title repeating it in 17 pt grey is the same fact
        // twice, and the bar's material over the mesh is a second surface where
        // the design has one.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { leaveItem }
        .toolbar { finishItem }
        // Pushed on DISMISSAL, not on every change. `startedAt` moves once per
        // tick of the timer sheet's wheel, and each one would have been an
        // ActivityKit update against a budget this file is careful about
        // everywhere else — for a card that is behind the sheet the whole time.
        .sheet(isPresented: $showTimer) {
            // Guarded like every sibling. It is unreachable in edit mode today
            // — `LoggerHero` draws a static duration and never sets the flag —
            // and if it ever fires there `LiveActivityController.update` falls
            // through to `start()`, which ENDS the running workout's card to
            // adopt a three-week-old session and takes the global rest-skip
            // handler with it.
            guard !model.isEditing else { return }
            activity.update(model: model, clock: clock)
        } content: {
            TimerSheet(
                clock: clock, accent: accent,
                watchStart: $watchStart, accumulated: $watchAccumulated, laps: $watchLaps
            )
        }
        .sheet(isPresented: $showDistribution) { MuscleDistributionSheet(model: model) }
        .sheet(isPresented: $showPhase) {
            PhaseSheet(day: model.day, phase: Binding(
                get: { model.phase },
                set: { model.phase = $0 }
            ))
        }
        .sheet(isPresented: $showFinish) {
            FinishSheet(model: model, onFinish: finish)
        }
        .sheet(isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
            ExercisePickerSheet(
                catalogue: adding ?? [],
                createNote: "Adds it to this session."
            ) { name, picked in
                // To the card — the new one, or the one already on the deck.
                // The tick, not `focus` alone: picking the card that already
                // HAS the focus changes nothing an `onChange(of: focus)` sees.
                if let card = model.addExercise(named: name, exerciseId: picked?.id) {
                    focus = card.id
                    scrollTick += 1
                }
            }
        }
        // ── WHY A CONFIRMATION AND NOT AN UNDO ──────────────────────────────
        // §3.4 prefers undo to a prompt, and this is the exception the rule
        // has: the sets are gone from the log, the projection and the queue in
        // one transaction, and an undo would have to reconstruct events that
        // were deliberately destroyed. One dialog, and the message says exactly
        // what is at stake — which is nothing at all on the session this button
        // is mostly for.
        .confirmationDialog(
            cancelDialogTitle,
            isPresented: $confirmCancel,
            titleVisibility: .visible
        ) {
            // ── BOTH LABELS AND THE ACTION ARE NAMED, NOT INLINE ────────────
            // A ternary in either slot is enough to tip this body over the
            // solver's budget — "unable to type-check this expression in
            // reasonable time", reported against the `Text` two lines down
            // rather than against the branch that caused it. The chain above is
            // already long; anything added here has to arrive pre-typed.
            Button(cancelActionTitle, role: .destructive) { confirmedCancel() }
            Button(keepTitle, role: .cancel) {}
        } message: {
            Text(cancelMessage)
        }
        // ── LEAVING IS NOT CANCELLING, AND IT STILL OWES THE CASCADE ────────
        // There is no draft here: every set edit committed the moment it was
        // made, seeded the event log, replayed the ledger and rewrote the
        // session's aggregates. So the chevron KEEPS the changes — Cancel is
        // now the button that does not — and the only thing it CAN do wrong is
        // skip the rescore, leaving `daily_scores` describing a session that no
        // longer exists, from the edit's date up to forty-eight days after it.
        // `RescoreQueue` coalesces, so a Save followed by a dismiss asks twice
        // and runs once.
        //
        // ── AND IT HAS TO CLOSE THE SITTING, WHICHEVER WAY IT ENDED ─────────
        // The watermark `markEditStart` laid down is a ROW, on purpose: an
        // editor killed mid-sitting can still be cancelled when it comes back,
        // which is the whole reason it is not held on the model. The cost is
        // that nothing forgets it for free — and `markEditStart` deliberately
        // does NOT move an existing mark, because moving it is how the crash
        // case loses the very edits it needs to undo.
        //
        // So a mark left standing after the chevron is worse than no Cancel at
        // all: leaving KEEPS the changes, and re-opening the session next month
        // would find a mark still pointing at last month, so one Discard would
        // silently undo both sittings. `finishEdit` and `cancelEdit` clear
        // their own; this is the third exit, and it is the only one nothing in
        // the model can see.
        //
        // ── AND WHY THE VIEW REACHES THE STORE HERE ────────────────────────
        // The same argument `mirrorRestToWatch` makes one screen down.
        // `LoggerModel` is the session's arithmetic; the mark is not about the
        // session at all, it is about a SCREEN being open, and this is the line
        // that knows the screen is going away. Giving the model a method for it
        // would be giving the model a fact it has no other use for.
        .onDisappear {
            if let sessionId = model.sessionId, model.isEditing {
                try? environment?.database.clearEditMark(sessionId: sessionId)
            }
        }
        // ── NO CASCADE CALL HERE (W2) ───────────────────────────────────────
        // Every set edit commits through `SessionEditing`, and the rescore
        // door reports the session's date on that commit. The view no longer
        // has to remember, and a jetsammed app owes nothing.
        .onAppear {
            // Edit mode is attached by the caller, which is the only place that
            // holds the session row. `attach`'s own guard (`sessionId == nil`)
            // makes this a no-op there rather than a second lookup, but the
            // Live Activity is not idempotent: starting one for a workout that
            // finished three weeks ago puts a countdown on the Lock Screen for
            // a session nobody is doing.
            guard !model.isEditing else { return }
            // ── START OPENS THE ROW, AND THE WRIST FOLLOWS (App Store W4) ───
            // `attach` rejoins a session that exists; `begin` opens one when
            // none does. Only a row this deck CREATES is announced — a rejoin
            // re-announcing could revive, on the wrist, a session the wrist
            // discarded while this cover was away. The hook is set first so
            // `ensureSession`'s fallback announces too.
            // The bridge, captured now: the hook may fire from a tap long
            // after this closure was made.
            let bridge = environment?.watchBridge
            model.onOpened = { bridge?.send(session: SessionPulse($0, phase: .open)) }
            model.attach()
            model.begin()
            // Before `start`, so the FIRST card already carries the wrist's
            // reading rather than acquiring it one pulse later.
            activity.liveBpm = environment?.watchBridge.liveBpm
            activity.start(model: model, clock: clock)
        }
        // ── THE WRIST'S HEART RATE, ONTO THE LOCK SCREEN (W4, DECISION 4) ───
        // `PhoneWatchBridge` is `@Observable`, so reading `liveBpm` here
        // registers and this fires whenever the wrist echoes one — which is a
        // rest starting, a ±15 s nudge, or the watch answering a pulse. A few
        // times a minute, not a few times a second: the sensor's own sampling
        // never reaches this property (`ContentState.bpm` says why that
        // matters for ActivityKit's update budget).
        //
        // It also fires when the reading goes STALE and the bridge starts
        // answering nil, which is what takes the number off the card rather
        // than freezing it at whatever the watch last said before it left.
        // ── THE WRIST'S CROWN, ONTO THE DECK CARD (overhaul A3) ─────────────
        // A provisional RPE, drawn and never stored until a tick commits it.
        .onChange(of: environment?.watchBridge.effort) { _, pulse in
            guard let pulse, !model.isEditing else { return }
            model.receiveEffort(pulse)
        }
        .onChange(of: environment?.watchBridge.liveBpm) { _, bpm in
            guard !model.isEditing else { return }
            activity.liveBpm = bpm
            activity.update(model: model, clock: clock)
        }
        .onChange(of: model.completedSets) { _, _ in
            guard !model.isEditing else { return }
            activity.update(model: model, clock: clock)
            // ── THE DECK NO LONGER MOVES ITSELF ─────────────────────────────
            // `advanceIfFinished()` used to run here: finishing a movement slid
            // the deck to the next card. It is deleted, on the founder's call.
            // The behaviour is indefensible on a phone propped against a rack —
            // you tick the last set, look away, and the screen you look back at
            // is a different movement, so correcting the set you just logged
            // means scrolling back to find it. `focus` is now written by `init`
            // alone and the scroll follows the reader.
        }
        // The Lock Screen mirrors the pause. A card counting a session up while
        // the phone in your hand says it is stopped is the two surfaces
        // disagreeing about the number that becomes `duration_min`.
        .onChange(of: clock.pausedAt) { _, _ in guard !model.isEditing else { return }; activity.update(model: model, clock: clock) }
        // A warm-up changes neither `completedSets` nor the rest clock, and
        // `commitEdit` — retyping a load on a logged set — changes none of the
        // three. Both leave the Lock Screen showing a number that is no longer
        // true.
        .onChange(of: model.physicalSets) { _, _ in guard !model.isEditing else { return }; activity.update(model: model, clock: clock) }
        .onChange(of: model.totalVolumeKg) { _, _ in guard !model.isEditing else { return }; activity.update(model: model, clock: clock) }
        .onChange(of: model.restEndsAt) { _, _ in
            guard !model.isEditing else { return }
            activity.update(model: model, clock: clock)
            mirrorRestToWatch()
        }
        // And the record count moves on paths none of the three above touch:
        // demoting a ticked set to a warm-up keeps its tonnage and its physical
        // count and takes its record away.
        .onChange(of: model.recordCount) { _, _ in guard !model.isEditing else { return }; activity.update(model: model, clock: clock) }
        // ── THE CLOCK HAS TO END ITSELF ─────────────────────────────────────
        // `startRest` set a deadline and only a tap, an adjustment into the
        // past or the next set ever cleared it. So the capsule sat at 0:00
        // until you logged again, the nav title never came back, and the
        // Dynamic Island showed a dead countdown instead of the load. `.task`
        // is cancelled and restarted whenever the deadline moves, which is
        // exactly the ±15 s case.
        .task(id: model.restEndsAt) {
            guard let endsAt = model.restEndsAt else { return }
            // A deadline already in the PAST is cleared, not celebrated. It is
            // reachable exactly as the paragraph above describes: the rest
            // expires while you are on the Workout tab, this task is not
            // running to clear it, and coming back used to `max(0, …)` the
            // negative interval into a zero-length sleep that completed
            // uncancelled — a `.success` haptic for a rest that ended minutes
            // ago, on a screen you had only just opened.
            let wait = endsAt.timeIntervalSinceNow
            guard wait > 0 else {
                model.stopRest()
                return
            }
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            restExpiries += 1
            withAnimation(OnyxMotion.drawer) { model.stopRest() }
        }
        // §3.4: `.success` on the rest clock running out. The capsule vanishing
        // from the navigation bar is the only visual notice, and the phone is
        // face-down on a bench when it happens.
        .sensoryFeedback(.success, trigger: restExpiries)
        .onChange(of: model.phase) { _, next in storedPhase = next.rawValue }
    }

    private func stack(page: CGFloat) -> some View {
        VStack(spacing: OnyxSpace.m) {
            LoggerHero(
                day: model.day,
                clock: clock,
                selection: $selection,
                onTimer: { showTimer = true },
                editing: model.editing,
                phase: model.phase,
                onPhase: { showPhase = true },
                // Validated HERE, where it is still optional:
                // `Text(timerInterval:)` traps on a range whose end is behind
                // its start, and the deadline outlives this view.
                // `total:` is the prescription this rest is counting through,
                // so the range has a fixed lower bound rather than one rebased
                // to `now` on every redraw — see `restCountdown`. The capsule
                // draws digits rather than a bar, so this changes nothing it
                // shows today; it is here so the one helper is called the same
                // way on every surface and a bar added here later is right.
                restCountdown: restCountdown(model.restEndsAt, total: Int(model.restDuration)),
                onSkipRest: { withAnimation(OnyxMotion.drawer) { model.stopRest() } },
                onAdjustRest: { model.adjustRest(by: $0) },
                // The wrist, if one is on it and has spoken recently. The
                // bridge is `@Observable`, so reading this registers and the
                // band redraws on the next pulse without anything polling.
                liveBpm: environment?.watchBridge.liveBpm
            )
            if let storeError = model.storeError { banner(storeError) }
            faces(page: page)
        }
        // One place, so the capsule arriving, the "Skip rest" chip arriving and
        // the deck sliding down for both are ONE movement rather than three
        // that start together and end apart.
        .animation(OnyxMotion.drawer, value: model.restEndsAt)
    }

    // MARK: - Toolbar

    /// Leave the logger with the session still live — the rest timer keeps
    /// counting and the Lock Screen card stays, because the workout is not over.
    private var leaveItem: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel(model.isEditing ? "Close editor" : "Leave workout")
                .accessibilityHint(model.isEditing
                    ? "Every change is already saved. Finish runs the recompute."
                    : "The session keeps running. Resume it from the Train tab.")

            // ── WHY EDIT MODE STILL HAS NO TRASH, AND NOW HAS AN UNDO ───────
            // `cancel()` is `discardSession`: the session row, its sets, its
            // events and its outbox items in one transaction. On the live deck
            // that is a workout that did not happen. On a session from three
            // weeks ago it is a workout that DID, with a daily score, a PR
            // ledger and forty-eight days of readiness built on it. Deleting a
            // past session is a different verb than cancelling a live one and
            // it still does not belong on a screen whose other buttons are
            // about the set in front of you.
            //
            // What DID belong here, and was missing, is the other half of
            // Save. This paragraph used to say an undo was impossible because
            // "the events it would destroy are the record of it" — true of a
            // discard, and the wrong shape for a cancel. A revert destroys no
            // event: `revertSessionEdits` diffs the session against the
            // watermark `markEditStart` laid down when the editor opened and
            // writes the COMPENSATING events — a void for what the sitting
            // added, a fresh append for what it deleted. The log grows in both
            // directions, which is what lets the server, the watch and a
            // half-synced queue all end up agreeing.
            //
            // Two things it deliberately is not. It is not the chevron: that
            // leaves with the changes KEPT (`.onDisappear`, and the hint
            // above), which is the right default for a screen whose every edit
            // has already committed. And it is not scoped to the app's
            // lifetime: the watermark is a row, so an editor killed mid-sitting
            // can still be cancelled when it comes back.
            // ── AND ONLY WHEN THERE IS A MARK TO GO BACK TO ─────────────────
            // `markEditStart` can fail — a busy store, a migration that has not
            // run — and `attach(editing:)` swallows that on purpose rather than
            // refusing to open an editor over it. Without this clause the button
            // still drew: the dialog promised "every set goes back to the way it
            // was", `revertSessionEdits` found no mark, did nothing, and the
            // screen dismissed reporting success. A button that looks live and
            // does nothing is worse than no button.
            if model.isEditing, model.editWatermarked {
                Button(role: .destructive) { confirmCancel = true } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .tint(Color.onyx.danger)
                .accessibilityLabel("Discard changes")
                .accessibilityHint("Puts every set back the way it was when you opened the editor.")
            } else {

            // ── AND WHY LEAVING NEEDED A SIBLING ────────────────────────────
            // The chevron was the only way out, and it leaves the session
            // RUNNING — which is right, and which meant a logger opened on the
            // wrong day, or by a pocket, had no exit that did not end in a
            // workout. Opening the screen still costs nothing (`attach` looks a
            // session up and never creates one), so the button mostly just
            // closes a door; when a set HAS been logged it is the only control
            // in the app that can take it back.
                Button(role: .destructive) { confirmCancel = true } label: {
                    Image(systemName: "trash")
                }
                .tint(Color.onyx.danger)
                .accessibilityLabel("Cancel workout")
                .accessibilityHint("Ends the session and discards anything logged in it.")
            }
        }
    }

    // MARK: - Fast actions

    // ── THE CHIP ROW IS GONE ────────────────────────────────────────────────
    // It held `Muscle focus` and `Note` — the last two of the five verbs that
    // started as a toolbar menu, then a row of chips, then a row of two. The
    // header now ends at the tabs, which is what the founder asked for: the
    // band above the deck says which workout and how long, and stops.
    //
    // `Muscle focus` did not lose its door — the Live Stats face opens the same
    // `MuscleDistributionSheet`, and that is the face the distribution belongs
    // on anyway.
    //
    // `Note` is gone entirely, on the founder's call rather than by omission.
    // A note still RENDERS on the exercise card and still arrives from the web,
    // so an existing one is never hidden — the phone simply stopped being a
    // place to type one. `ExerciseState.note` and its sync stay for that
    // reading half; only the writing half left.

    /// Finish, in the navigation bar's trailing slot.
    ///
    /// ── WHY IT LEFT THE CHIP ROW ────────────────────────────────────────────
    /// U1 declined exactly this move and said so: Finish stayed a chip because
    /// pinning it out of the scroll had fixed the real defect. What changed is
    /// the row around it. `Phase` and `Skip rest` are gone, so the row is two
    /// cold verbs — and a filled, prominent chip beside two grey ones reads as
    /// the row's subject rather than as the way out. The bar is where iOS puts
    /// the way out, opposite the way back in, and it costs the band nothing.
    ///
    /// ── AND WHY IT HIDES THE BAR'S OWN BACKGROUND ───────────────────────────
    /// Built against the iOS 26 SDK, a toolbar item is given a glass capsule of
    /// its own — the platform's, sized to the item, drawn UNDER whatever the
    /// item draws. This item draws its own filled capsule, so the result was
    /// two stacked pills: a solid accent one inside a slightly larger
    /// translucent box, out of register with it on every side. It read as a
    /// rendering bug because it is one.
    ///
    /// The fix is to say the item supplies its own background rather than to
    /// re-style ours to fit inside the platform's, which would put the word
    /// back inside a shape the app does not control. `Visibility.hidden` on the
    /// shared background is exactly that statement, and on iOS 18 — where no
    /// such background exists — there is nothing to say.
    @ToolbarContentBuilder
    private var finishItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            finishToolbarItem.sharedBackgroundVisibility(.hidden)
        } else {
            finishToolbarItem
        }
    }

    private var finishToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            // "Finish" on a session that finished three weeks ago is the wrong
            // verb: it reads as ending something, and what it does is write the
            // effort and run the recompute.
            // ── AN HStack, NOT A `Label`, AND NOT `.borderedProminent` ─────
            // A `Label` in a toolbar collapses to its glyph, and
            // `.labelStyle(.titleAndIcon)` does not win it back: the bar's own
            // style is applied outside it. Two shots of this change came back
            // as a bare blue tick in the corner — "confirm" in every other app,
            // and here "end the workout and run a 49-day recompute". The word
            // is the control, so the row is built by hand and the fill is a
            // background rather than a button style that can restyle it.
            // ── AND WHY THE WORD IS `fixedSize` ───────────────────────────
            // It shipped as "Fin…". A toolbar hands its trailing items a width
            // from what is LEFT after the leading group and the title, and a
            // `Text` inside `lineLimit(1)` answers a squeeze by truncating —
            // silently, and only on the device, because the preview canvas has
            // no navigation bar to run out of. Six characters is the whole
            // control; a truncated verb on the button that ends the workout is
            // worse than any layout it could push on.
            //
            // `fixedSize` makes the word incompressible, so the bar takes the
            // space from the flexible middle instead. The capsule's own
            // horizontal padding stays outside it and can still absorb — see
            // the `minHeight` below, which is the tap target and not the type.
            Button { showFinish = true } label: {
                HStack(spacing: OnyxSpace.xs) {
                    Image(systemName: "checkmark").imageScale(.small)
                    Text(model.isEditing ? "Save" : "Finish")
                        .fixedSize(horizontal: true, vertical: false)
                }
                .onyxType(.caption).fontWeight(.semibold)
                .foregroundStyle(Color.onyx.base)
                .lineLimit(1)
                .padding(.horizontal, OnyxSpace.m)
                .frame(minHeight: 32)
                .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isEditing ? "Save session" : "Finish workout")
        }
    }

    // MARK: - The two faces

    /// One model, two pages, one slide.
    ///
    /// ── WHY BOTH PAGES STAY IN THE TREE ─────────────────────────────────────
    /// The deck is a `ScrollView` and you are eleven movements into it. A face
    /// switch that rebuilt it would return you to the top of a workout that is
    /// half done — the exact failure `focus` exists to prevent on the other
    /// axis. Two children of an `HStack` at an offset are both alive, so the
    /// scroll offset is simply never lost. The deck's own `LazyVStack` is what
    /// keeps the offscreen cost to nothing.
    ///
    /// The spring comes from the SELECTION, so the pill in the hero and the page
    /// under it move on one animation: damping 1.0 when a segment was tapped,
    /// 0.8 when the pill was thrown.
    ///
    /// ── AND WHY IT IS NOT A PAGING SCROLL VIEW ──────────────────────────────
    /// It was, briefly, and turning its scrolling off — which is what a pager
    /// driven from a segmented control has to do — also stops `scrollPosition`
    /// from moving it. The Live Stats face rendered as the deck, with the pill
    /// saying otherwise. So the offset is ours, and the gesture stays on the
    /// pill.
    ///
    /// (The original reason was a second one: the deck's set rows were swiped
    /// horizontally to log, and a pager underneath competed for the same finger
    /// on every row of every card. Wave U2 retired that swipe — the set number
    /// does both jobs now — so only the `scrollPosition` reason is left. It is
    /// on its own sufficient, and a reader who checks the first reason and
    /// finds it gone should not conclude the pager is back on the table.)
    ///
    /// ── AND WHY IT IS PINNED AND CLIPPED ────────────────────────────────────
    /// `frame(width:alignment: .leading)` puts a two-page strip inside a
    /// one-page box anchored left, and `clipped()` cuts what hangs off it —
    /// belt and braces over a width `body`'s `GeometryReader` already
    /// guarantees, because leaking the other face down the right-hand edge is
    /// the failure this screen actually shipped at an accessibility size.
    private func faces(page: CGFloat) -> some View {
        HStack(spacing: 0) {
            deck(ready: page > 1)
                .frame(width: page)
                .accessibilityHidden(selection.face != .workout)
            LiveStatsView(
                model: model,
                clock: clock,
                prs: prs,
                onMuscleFocus: { showDistribution = true }
            )
            .frame(width: page)
            .accessibilityHidden(selection.face != .stats)
        }
        .frame(width: page, alignment: .leading)
        .offset(x: -CGFloat(selection.face.index) * page)
        .animation(selection.animation, value: selection.face)
        .clipped()
    }

    // MARK: - The deck

    /// Every movement, on one page, scrolled vertically.
    ///
    /// ── WHY THE PAGER WENT ──────────────────────────────────────────────────
    /// It was a horizontal deck, one movement per page, snapped with
    /// `.viewAligned`. It reads beautifully and it is the wrong shape for this
    /// screen. A workout is not a slideshow you advance through once: you look
    /// ahead at what is coming to decide how hard to go now, you drop back to
    /// the movement before to fix a load you mistyped, and you want to see that
    /// the session is eleven movements long without counting "3 of 11" eleven
    /// times. Every one of those is a scroll in a list and a page-flick hunt in
    /// a deck.
    ///
    /// It also cost the rows a gesture. The card's set rows were swiped
    /// horizontally to log, and a horizontal pager under them meant the two were
    /// competing for the same drag on every row of every card — which is why the
    /// row's own swipe had to abandon itself the moment the finger went
    /// vertical. Wave U2 retired the row swipe for its own reasons (it owned the
    /// whole horizontal axis of a row that has no spare width), so this is now
    /// history rather than a live constraint — but it is why the deck is
    /// vertical, and the vertical deck is what made retiring the swipe cheap.
    ///
    /// ── AND WHY THE SCROLL FOLLOWS `focus` RATHER THAN REPORTING IT ─────────
    /// `.scrollPosition(id:)` is a two-way binding, which was exactly right when
    /// the position and the current movement were the same fact. They are not
    /// here — see `focus` — so this is a `ScrollViewReader` and a one-way
    /// `scrollTo`. Scrolling to read never moves the cursor, and finishing a
    /// movement still takes you to the next one.
    private func deck(ready: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: OnyxSpace.m) {
                    ForEach(Array(model.exercises.enumerated()), id: \.element.id) { index, exercise in
                        ExerciseCardView(
                            exercise: exercise, model: model,
                            position: (index, model.exercises.count)
                        )
                        .frame(maxWidth: .infinity)
                        .id(exercise.id)
                    }
                    // A session is not a contract with the program: the
                    // machine was taken, the shoulder asked for something
                    // else. Live decks only — an edit deck already carries
                    // every movement the session or its plan named.
                    if !model.isEditing { addMovement }
                }
                // 12 rather than the 16 the rest of the app uses. The set row
                // inside these cards is within a few points of the width of a
                // phone (see `ExerciseCardView.sets`), and a gutter the row
                // cannot afford is not a gutter — it is an overflow that draws
                // the cards edge to edge and looks like no gutter was asked for.
                .padding(.horizontal, OnyxSpace.m)
                // The last card has to be able to reach the middle of the
                // screen, or finishing the session means logging its final set
                // with the keyboard over it.
                .padding(.bottom, OnyxSpace.xl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollTick) {
                guard let focus else { return }
                withAnimation(OnyxMotion.move) { proxy.scrollTo(focus, anchor: .top) }
            }
            // Resuming mid-session opens on the set you stopped at, not at the
            // top of a workout that is half done. Unanimated on purpose: this is
            // where the screen STARTS, and a scroll you did not ask for on the
            // first frame reads as the app losing its place.
            //
            // Keyed on `ready` — the page having a width — because a `scrollTo`
            // into a scroll view that has not been given any room yet is a
            // no-op, and a plain `.task` never runs again to notice. That is
            // exactly what happened when the pager moved into a
            // `GeometryReader`: the deck opened at movement one, every time.
            .task(id: ready) {
                guard ready else { return }
                proxy.scrollTo(focus, anchor: .top)
            }
        }
    }


    /// The last thing on the deck, where the next movement would go (W3).
    private var addMovement: some View {
        Button { adding = model.catalogue() } label: {
            Label("Add a movement", systemImage: "plus")
                .onyxType(.body).fontWeight(.semibold)
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onyxGlass(.tile)
    }

    // MARK: - Failures

    /// A store write that failed, stated rather than swallowed.
    ///
    /// It is a banner and not an alert on purpose: the set is still on screen
    /// and still correct, the outbox will retry, and a modal between you and the
    /// next set would cost more than the failure does. What must never happen is
    /// the failure being invisible — a set that looks logged and is not is the
    /// one outcome this whole data layer exists to prevent.
    private func banner(_ message: String) -> some View {
        OnyxBanner(tone: .failure, title: "Not saved locally", message: message)
            .padding(.horizontal, OnyxSpace.l)
    }

    /// What the confirmation offers, and what it warns about.
    ///
    /// The states are genuinely different actions and the dialog says so: a
    /// session with nothing in it has nothing to discard, and telling someone
    /// their sets are about to be deleted when there are none is how a dialog
    /// stops being read.
    ///
    /// ── AND EDITING IS A THIRD THING AGAIN ──────────────────────────────────
    /// One button opens this dialog from two screens that share no verb. On the
    /// live deck the workout is thrown away; in the editor the WORKOUT survives
    /// and the sitting's changes are thrown away. Reusing the live copy would
    /// have told a person about to undo a typo that their session is being
    /// deleted from the server — the one sentence guaranteed to make them tap
    /// Cancel on the Cancel.
    private var cancelDialogTitle: String {
        if model.isEditing { return "Discard your changes?" }
        return model.completedSets > 0 ? "Discard this workout?" : "Cancel this workout?"
    }

    private var cancelActionTitle: String {
        if model.isEditing { return "Discard changes" }
        return model.completedSets > 0 ? "Discard \(model.completedSets) sets" : "Cancel workout"
    }

    private var keepTitle: String { model.isEditing ? "Keep editing" : "Keep logging" }

    /// One dialog, two screens, two verbs — resolved here rather than in the
    /// button, which the type-checker cannot afford. See the call site.
    private func confirmedCancel() {
        if model.isEditing { cancelEdit() } else { cancelWorkout() }
    }

    private var cancelMessage: String {
        if model.isEditing {
            return "Every set goes back to the way it was when you opened this session. The workout itself is kept."
        }
        return model.completedSets > 0
            ? "The sets logged in this session are deleted here and on the server. This cannot be undone."
            : "Nothing has been logged, so nothing is saved. The session closes and no workout is recorded."
    }

    /// Discard the session and leave.
    ///
    /// The store failing keeps the screen up: `model.cancel` puts the reason in
    /// `storeError`, the banner is already rendering it, and dismissing anyway
    /// would leave the session live with the failure reported to a screen that
    /// no longer exists — the same rule `finish` follows.
    private func cancelWorkout() {
        // Read BEFORE the discard deletes it — the pulse names the row.
        let row = storedRow(model.sessionId)
        guard model.cancel() else { return }
        tellWatch(.discarded, row)
        model.stopRest()
        activity.end()
        dismiss()
    }

    /// Stamp the session finished — and only then leave.
    ///
    /// Returns false when there is nothing to close: no store row, or not one
    /// working set logged (a session of warm-ups). Ending the activity and
    /// dismissing anyway left the session row open forever, the tab reading it
    /// back as live, and the failure reported to a screen that no longer
    /// existed. Now the sheet stays up and the banner has somewhere to appear.
    private func finish(sessionRpe: Double?) -> Bool {
        if model.isEditing { return finishEdit(sessionRpe: sessionRpe) }
        let finished = model.sessionId
        guard model.finish(sessionRpe: sessionRpe) else { return false }
        // The closed row, so the wrist ends its `HKWorkoutSession` at the
        // instant this one was stamped rather than when the pulse lands.
        tellWatch(.finished, storedRow(finished))
        model.stopRest()
        activity.end()
        // The phone's own `HKWorkout` when the watch did not run this one,
        // and the heart-rate prefetch (W5). Off the main actor, after the
        // row is closed, and nothing here waits for it.
        if let finished { environment?.sessionFinished(sessionId: finished) }
        dismiss()
        return true
    }

    /// Put the sitting back, and only then leave.
    ///
    /// A revert rewrites `total_volume_kg`, the PR ledger and every set row of
    /// the session — the same three things an edit rewrites, in the opposite
    /// direction — in one `SessionEditing` transaction, and the rescore door
    /// reports that commit (W2). Nothing to ask for here.
    ///
    /// The store failing keeps the screen up — `cancelEdit` puts the reason in
    /// `storeError` and the banner is already rendering it — which is the rule
    /// `finish` and `cancelWorkout` both follow. Dismissing anyway would report
    /// a half-done revert to a screen that no longer exists.
    private func cancelEdit() {
        guard model.cancelEdit() else { return }
        model.stopRest()
        dismiss()
    }

    /// Close an edit: the effort word (§U4.5). The cascade is the door's (W2).
    ///
    /// The set edits themselves already landed, one transaction each, as they
    /// were made. So it does not refuse when there is nothing to write:
    /// leaving a session with no sets left in it is a correction.
    private func finishEdit(sessionRpe: Double?) -> Bool {
        guard model.finishEdit(sessionRpe: sessionRpe) != nil else { return false }
        model.stopRest()
        dismiss()
        return true
    }

    /// Tell the wrist a session opened, finished or was discarded here (App
    /// Store W4). From the view, for the reason `mirrorRestToWatch` gives one
    /// function down: the model is the session's arithmetic and holds no
    /// transport.
    private func tellWatch(_ phase: SessionPulse.Phase, _ row: WorkoutSession?) {
        guard let row, let bridge = environment?.watchBridge else { return }
        bridge.send(session: SessionPulse(row, phase: phase))
    }

    private func storedRow(_ id: String?) -> WorkoutSession? {
        guard let id, let environment else { return nil }
        return try? environment.database.session(id: id, userId: environment.userIdString)
    }

    /// Put the phone's rest clock on the wrist — including when it STOPS.
    ///
    /// ── WHY THIS DID NOT EXIST ──────────────────────────────────────────────
    /// `PhoneWatchBridge.send(rest:)` and `WatchLink`'s whole rest channel have
    /// been in the tree since Wave 10, and nothing on the phone ever called
    /// them: the watch mirrored ITS own clock to the phone (which the phone
    /// deliberately ignores) and the phone mirrored nothing back. So a rest
    /// started on the phone never reached the watch, and — the case this wave
    /// is about — a rest CANCELLED on the phone by unticking a set could not
    /// reach it either. `nil` is the whole point of the payload being optional.
    ///
    /// Sent from the view rather than from the model on purpose: `LoggerModel`
    /// is the session's arithmetic and has no transport in it, and the one
    /// place that already watches this exact value for the Live Activity is
    /// here. Two mirrors of one clock, driven off one `onChange`.
    private func mirrorRestToWatch() {
        guard let bridge = environment?.watchBridge, let sessionId = model.sessionId else { return }
        guard let endsAt = model.restEndsAt else { return bridge.send(rest: nil) }
        // ── THE SET THAT EARNED THE REST, AND THE SESSION'S OWN CLOCK ───────
        // The watch draws `load × reps · RPE` under the countdown and a session
        // timer in its toolbar, and it can derive neither. It holds the fold,
        // so `sets.last` looks like an answer for the first — but the fold is
        // only populated for a session this watch ADOPTED, and the rest cover
        // presents from this pulse whether or not it ever did. The elapsed
        // clock it cannot get at all: `started_at` on the row is wall time, and
        // a session paused for eleven minutes is eleven minutes younger.
        //
        // Both are cheap to send and neither has a second source, so they ride
        // along. Every one of them is optional on the far side: an older watch
        // ignores the keys, and an older phone sends none of them.
        let done = model.exercises
            .first { $0.name == model.restingExercise }?
            .rows.last { $0.isDone }
        bridge.send(rest: RestPulse(
            sessionId: sessionId,
            endsAt: endsAt,
            duration: model.restDuration,
            exercise: model.restingExercise,
            loadKg: done?.weightKg,
            reps: done?.reps,
            rpe: done?.rpe,
            // `timerOrigin`, never `startedAt` — pauses are already folded into
            // it, so the wrist counts the same seconds the hero does.
            timerOrigin: model.timerOrigin
        ))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Live Logger — Upper B, cut, mid-session") {
    NavigationStack {
        LiveLoggerView(model: .previewUpperB(logged: true))
    }
    .preferredColorScheme(.dark)
}
#endif

#if DEBUG
#Preview("Live Logger — Legs & Core A, bulk, fresh") {
    NavigationStack {
        LiveLoggerView(model: LoggerModel(
            day: PlanTemplates.day("onyx5", "legs_a"), phase: .bulk
        ))
    }
    .preferredColorScheme(.dark)
}
#endif
