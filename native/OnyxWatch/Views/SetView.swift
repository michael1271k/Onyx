import OnyxCore
import OnyxData
import OnyxUI
import SwiftUI
import WatchKit

/// The set in front of you. This is the app.
///
/// ── TWO PAGES, AND WHY THE OLD HEADER SAID NONE ─────────────────────────────
/// The first design here was a three-page `TabView(.verticalPage)` — SET, RPE,
/// REST — and it could not have worked. `.digitalCrownRotation` is delivered to
/// the FOCUSED view, and a vertical pager claims Crown focus for paging: the
/// load binding and the container would have been two consumers of one focus,
/// and the result on device is either the page sliding when you meant to add a
/// plate or the Crown going dead. That is still true of `TabView`, and this is
/// not one.
///
/// W3 adds a SECOND page under this one — the Set Quality panel (founder
/// decision 3) — as a `ScrollView` whose children are view-aligned, which is a
/// different mechanism from a pager in the one way that matters: paging is
/// driven by the FINGER, and the Crown still belongs to whatever holds focus.
/// Two things make that safe rather than lucky:
///
///   · the two value rows are `focusable` only while page one is showing, so
///     there is no state in which the Crown can move a load you cannot see;
///   · `.scrollInputBehavior(.disabled, for: .handGestureShortcut)` keeps the
///     double-pinch on the tick instead of letting it turn a page.
///
/// Rest is still a `fullScreenCover` — a STATE you are in rather than a page
/// you can visit — because it ends on its own.
///
/// ── THE CROWN MEANS WHATEVER HAS THE RING ───────────────────────────────────
/// Multiple meanings for the Crown are fine. Meanings bound to which PAGE you
/// are on are not, because the page is invisible while you are staring at the
/// numeral. Tap the kilograms, the focus ring moves there, the Crown drives
/// kilograms. Tap the reps, the ring moves, the Crown drives reps. One control,
/// one visible answer to "what will this change", no modes to remember. On page
/// two nothing is focusable, so the Crown scrolls the panel — which is the only
/// thing on that page it could mean.
///
/// ── AND THERE IS NO STEPPER ─────────────────────────────────────────────────
/// A `−`/`+` pair is the direct port of the phone's `SetRowView.stepper` and it
/// is the loudest tell that a watch app used to be a phone app. Two 32 pt ends
/// cost 64 of the 146 pt this screen actually has at 40 mm — 44% of the width —
/// to do worse, with more noise, what one Crown turn does eyes-free. The Crown
/// is the only adjuster and the tick is the only button.
struct SetView: View {

    @Environment(WatchModel.self) private var model
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// Which value the Crown drives. See the type header.
    private enum Field: Hashable { case load, reps }
    @FocusState private var field: Field?

    /// The two pages, by identity rather than by offset.
    private enum Page: Int, Hashable { case set, quality }
    @State private var page: Page = .set

    /// Shown until the panel has been reached once, ever.
    @AppStorage("onyx.watch.sawQualityPanel", store: WatchTiles.defaults())
    private var sawQualityPanel = false

    @State private var isConfirmingCancel = false

    var body: some View {
        @Bindable var model = model

        Group {
            if !model.holdsPencil {
                MirrorView()
            } else if let cursor = model.cursor {
                logger(cursor, model: model)
            } else {
                FinishView()
            }
        }
        .containerBackground(for: .navigation) { WatchInk.ground }
        // ── THE TITLE IS THE SET POSITION, NOT THE SPLIT ────────────────────
        // "Legs & Core A" truncates to "Legs & Co" at 40 mm and tells you
        // nothing you did not know — you started the workout. "Set 1 of 4" is
        // the fact that changes, it fits, and moving it up here buys back the
        // ~24 pt row that was pushing the load numeral off the bottom of the
        // scroll view. Two problems, one line.
        .navigationTitle(setTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // ── AND ONLY WHILE THIS WRIST HOLDS THE PENCIL ──────────────────
            // The toolbar is attached to the outer `Group`, so it drew over
            // `MirrorView` too — offering a pause and a discard on a session
            // the PHONE is writing, where `EventStore.record` refuses every
            // write. The refusal is handled now (`WatchModel.failed`), but a
            // control that is guaranteed to fail should not be drawn.
            if model.sessionId != nil, model.holdsPencil {
                // ── LEADING HERE, TRAILING ON THE REST SCREEN ───────────────
                // It was a second `.topBarTrailing` item, and the 40 mm shot
                // showed watchOS silently drawing only ONE of them: the deck
                // link rendered and the clock did not — no warning, no overflow
                // menu, nothing. The corner holds one item on this device.
                //
                // The leading corner is free on this screen — `SetView` is the
                // root of its stack, so there is no back chevron — and the rest
                // cover's leading corner is NOT, because a cover has a dismiss
                // button there. So the clock takes whichever corner is free on
                // each screen. That is not the symmetry the brief asked for,
                // and the alternative was one of the two screens not having it.
                //
                // ── AND THE CLOCK IS THE PAUSE BUTTON (W3) ──────────────────
                // Both corners were already spent when this wave had to add
                // pause and cancel, and a bar 162 pt wide that already carries
                // a title and two glyphs has no third corner. A control that
                // DISPLAYS a value is the obvious place to change it — the
                // argument the phone's options sheet makes about the set badge
                // — and pausing is the one thing that changes this value.
                ToolbarItem(placement: .topBarLeading) {
                    WatchSessionTimer()
                        .onTapGesture { togglePause() }
                        .onLongPressGesture(minimumDuration: 0.6) {
                            WKInterfaceDevice.current().play(.retry)
                            isConfirmingCancel = true
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(model.isPaused ? "Resumes the session" : "Pauses the session")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // ── `tint` COLOURS THE DISC, NOT THE GLYPH ──────────────
                    // With `WatchInk.secondary` the toolbar button renders as
                    // a near-WHITE filled circle with dark ink — the
                    // brightest object on five screens, brighter than the
                    // movement name, for a reference link that was meant to
                    // be quiet. The rest cover's dismiss and the deck's back
                    // chevron are dark discs with light glyphs; this is the
                    // same.
                    NavigationLink(value: WatchRoute.deck) { Image(systemName: "list.bullet") }
                        .tint(WatchInk.fill)
                        .foregroundStyle(WatchInk.secondary)
                }
            }
        }
        // The one undoable thing on this wrist — see `DiscardSheet`.
        .sheet(isPresented: $isConfirmingCancel) {
            DiscardSheet(setCount: model.sets.count) {
                model.cancelSession()
                WKInterfaceDevice.current().play(.success)
            }
        }
    }

    private func togglePause() {
        model.togglePause()
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - The logger

    @ViewBuilder
    private func logger(_ cursor: WatchModel.Cursor, model: WatchModel) -> some View {
        // ── THE BUTTON IS A SIBLING, NOT AN INSET ───────────────────────────
        // This was `ScrollView { … }.safeAreaInset(edge: .bottom) { tick }`, and
        // the first 40 mm screenshot showed the inset failing to reserve any
        // space: the tick floated over the load numeral and the reps row, hiding
        // the two values it exists to commit.
        //
        // A `VStack` with the scroll view above and the button below is
        // deterministic. It keeps the property that mattered — the tick never
        // scrolls away — and it keeps the Larger Text answer too, because the
        // ScrollView still takes all the flexible height and scrolls; only the
        // button is fixed, and a button is one line at any type size.
        //
        // ── AND THE TICK IS THE SAME BUTTON ON BOTH PAGES (W3) ──────────────
        // Showing or hiding it by page would resize the scroll container mid
        // drag, so every page would re-measure against an offset that no longer
        // exists. One button, one footprint, one label. It still means "log the
        // set you are on" from page two, which is the page the panel describes
        // the set BEFORE that one — the panel's header names its set for
        // exactly this reason.
        VStack(spacing: OnyxSpace.xs) {
            pages(cursor, model: model)
            tick
        }
        .dimmedWhenLuminanceReduced()
        // The first focus. `onScrollPhaseChange` restores it after every page
        // turn, but a scroll view that has never been dragged never changes
        // phase — so without this the Crown is dead until you scroll once.
        .onAppear {
            if field == nil, !isLuminanceReduced { field = .load }
            #if DEBUG
            if model.debugScreen == .cancel { isConfirmingCancel = true }
            #endif
        }
    }

    /// The two pages.
    ///
    /// ── `minHeight`, NOT `containerRelativeFrame` ───────────────────────────
    /// A page pinned to exactly one container height deletes the reason this
    /// screen is a `ScrollView` at all: at Larger Text and Bold Text the
    /// content does not fit, and a fixed frame does not scroll — it overflows,
    /// unclipped and unwarned, and draws over the page below. `minHeight` makes
    /// a page at least a screen tall and lets it grow, and
    /// `.viewAligned(limitBehavior: .alwaysByOne)` still snaps page TOPS and
    /// still moves at most one page per gesture.
    ///
    /// The height is measured rather than assumed, because the scroll view's
    /// own height is this `VStack` minus the tick and nobody should be spelling
    /// that out. `onScrollGeometryChange` writes no offset, so it is not in the
    /// family of the "scroll position written before layout" defect.
    private func pages(_ cursor: WatchModel.Cursor, model: WatchModel) -> some View {
        // ── THE HEIGHT IS READ, NOT OBSERVED ────────────────────────────────
        // This was `onScrollGeometryChange(for:) { $0.containerSize.height }`,
        // and it never fired: that modifier reports a CHANGE, and the first
        // layout is not one. `pageHeight` stayed 0, `minHeight: 0` made each
        // page exactly as tall as its content, and the two ran together in one
        // scroll — the quality panel's heading sat twenty points under the
        // reps row with no page boundary anywhere. The accessibility tree
        // showed it; the screenshot did not, because the pinned tick covered
        // the seam.
        //
        // A `GeometryReader` takes the flexible space between the bar and the
        // tick and reports it on the FIRST pass, which is the whole
        // requirement.
        GeometryReader { proxy in
        ScrollView(.vertical) {
            // A plain `VStack`: a lazy one realises only the first child, so
            // page two would be absent from the accessibility tree and could
            // not report its own visibility. Two children — there is nothing
            // to be lazy about.
            VStack(spacing: 0) {
                setPage(cursor, model: model)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .id(Page.set)
                SetQualityPanel()
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .id(Page.quality)
            }
            .scrollTargetLayout()
        }
        // ── `.paging`, AND `.viewAligned` WAS MEASURED AND REJECTED ─────────
        // `.viewAligned(limitBehavior: .alwaysByOne)` is the obvious choice —
        // it snaps to the tops of the two pages — and on this screen it makes
        // the panel unreachable. Page two is taller than the display (a
        // header, two chip grids and their meaning lines come to ~380 pt in
        // ~98), and `.alwaysByOne` measures the gesture against the size of
        // the view it is scrolling TO. A swipe of a whole screen is a small
        // fraction of a 380 pt target, so it fell short of the threshold and
        // snapped back, every time: the panel could not be opened with a
        // finger at all. `axe` proved it — the accessibility tree showed page
        // two laid out at y=158 and the offset never moved.
        //
        // `.paging` measures against the CONTAINER instead. The first turn is
        // exactly one display, which is page one's height and therefore page
        // two's top; the rest of the panel then scrolls in screenfuls like
        // any long page.
        .scrollTargetBehavior(.paging)
        // ── `.scrollInputBehavior(.disabled, for: .handGestureShortcut)` ────
        // ── IS NOT HERE, AND IT COST A DAY TO FIND OUT WHY ──────────────────
        // It looks exactly right: watchOS 11 added a `ScrollInputKind` whose
        // only member is the hand gesture, for arbitrating the double pinch
        // between a scroll view and a button — and this screen has both.
        //
        // On this SDK it disables the scroll view's input ENTIRELY. With the
        // modifier on, no swipe of any length, speed or position moved the
        // content by a point: `axe` showed page two laid out at y=158 and the
        // offset never changed, under both `.viewAligned` and `.paging`. The
        // panel was unreachable by finger, which is the only way it is
        // reachable at all. Removing this one line fixed it.
        //
        // So the double pinch keeps whatever watchOS gives it. The tick still
        // declares `.handGestureShortcut(.primaryAction)`; if a future build
        // starts turning pages on a double tap instead of logging the set,
        // the fix is NOT to put this back.
        // ── NOTHING HERE WRITES A SCROLL POSITION ───────────────────────────
        // This view had a `scrollPosition` binding, purely so the shot loop
        // could photograph page two. It never landed: the binding is honoured
        // only after layout, the `GeometryReader` cancels and restarts any
        // task that waits for layout, and every variant came back as page one
        // under the filename `quality.png`.
        //
        // The loop drives a real SWIPE instead (`scripts/watch-shot.sh`), and
        // what is left here are two read-only observers. That is also the
        // better code: paging belongs to the finger, and a screen that can
        // only be photographed by writing state no finger writes is a screen
        // the photograph does not prove.
        // ── WHICH PAGE, MEASURED AGAINST THE CONTAINER ──────────────────────
        // This was `onScrollTargetVisibilityChange(idType:threshold: 0.6)`,
        // and `threshold` is a fraction of the TARGET — page two is ~380 pt
        // of content in a ~95 pt viewport, so its visible fraction tops out
        // near a quarter and the callback could never fire. `page` was
        // therefore `.set` for the life of the screen, and everything hanging
        // off it was dead: the value rows stayed focusable, so the Crown went
        // on moving a load nobody could see; `field = nil` never ran and
        // `onScrollPhaseChange` re-grabbed focus at every settle; the page
        // dots never moved; and the once-ever chevron was drawn over the
        // panel's chips forever. The screenshots showed the lit dot on page
        // one while the panel filled the frame, which is how it was caught.
        //
        // The offset against the container is the honest question, it is one
        // number, and it is a READ — not the "scroll position written before
        // layout" family the comment above warns about.
        .onScrollGeometryChange(for: Bool.self) {
            $0.contentOffset.y > $0.containerSize.height * 0.5
        } action: { _, isPanel in
            let shown: Page = isPanel ? .quality : .set
            guard shown != page else { return }
            page = shown
            if shown == .quality {
                field = nil                 // free the Crown BEFORE the panel lands
                sawQualityPanel = true
                WKInterfaceDevice.current().play(.directionUp)
            }
        }
        // Focus is taken back only once the scroll has settled. Doing it on
        // visibility would grab the Crown mid-drag, which reads as the page
        // sticking.
        .onScrollPhaseChange { _, phase, _ in
            guard phase == .idle, page == .set, field == nil, !isLuminanceReduced else { return }
            field = .load
        }
        .overlay(alignment: .trailing) { pageDots }
        }
    }

    /// Two dots, drawn.
    ///
    /// There is no system page indicator for a `ScrollView` — `PageIndexViewStyle`
    /// belongs to `TabView`, which is the control this screen cannot use. Four
    /// points each, hidden from VoiceOver (both pages are already in the tree)
    /// and hidden in the always-on state, where a static tinted mark held in
    /// one corner for an hour is the textbook burn-in case.
    private var pageDots: some View {
        VStack(spacing: 4) {
            ForEach([Page.set, Page.quality], id: \.self) { dot in
                Circle()
                    // `fill` and not `fillActive` for the inactive one: at
                    // 18 % against 100 % the two dots read as a pair of dots
                    // rather than as a position.
                    .fill(dot == page ? WatchInk.primary : WatchInk.fill)
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.trailing, 1)
        .accessibilityHidden(true)
        .opacity(isLuminanceReduced ? 0 : 1)
    }

    // MARK: - Page one

    @ViewBuilder
    private func setPage(_ cursor: WatchModel.Cursor, model: WatchModel) -> some View {
        @Bindable var model = model

        // ── THE WHOLE PAGE IS 94 pt AND THE CONTENT IS 96 ───────────────────
        // Measured off the accessibility tree at 49 mm: the scroll view starts
        // at 64 and the pinned tick at 158. A movement name (21), the value
        // row (54) and the receipt (21) do not fit two 8 pt gaps between them
        // — the first build of this wave drew the receipt half under the
        // tick. Two-point gaps, a point off each value row's vertical padding
        // and the scroll view's own top inset cancelled are what make it fit,
        // and there is nothing left over: a two-line movement name scrolls,
        // which is what the scroll view has been here for since Wave 10.
        VStack(alignment: .leading, spacing: 2) {
            Text(cursor.movement.plan.name)
                // Two lines, not the phone's three: at 146 pt with Bold Text
                // on, "Incline Dumbbell Press" truncates on one and there is
                // no room for three.
                .font(WatchType.name)
                .foregroundStyle(WatchInk.primary)
                .lineLimit(2)
                .allowsTightening(true)

            // ── ONE ROW, TWO FOCUSABLE VALUES ───────────────────────────
            // They were two stacked rows and the 40 mm screenshot showed
            // the cost: ~193 pt of content in ~165 pt of space, so the load
            // numeral was cut off by the bottom of the scroll view on first
            // paint — the one number the screen exists to set.
            //
            // Side by side they cost one row instead of two, and they read
            // as the set itself: `70 kg x 8`. The ring still says which one
            // the Crown drives, which is the whole legibility argument.
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.xs) {
                loadRow(model: model)
                Text("x")
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.secondary)
                    .accessibilityHidden(true)
                repsRow(model: model)
            }

            receipt
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The strip watchOS reserves under the navigation bar before a scroll
        // view's first child — the same 4 pt `RestView` cancels, and here it
        // is the difference between the receipt being on the screen and being
        // drawn under the tick.
        .padding(.top, -OnyxSpace.xs)
    }

    /// What this movement cost last time, and what your heart is doing.
    ///
    /// ── THE HEART IS HERE AND NOT IN THE TITLE ──────────────────────────────
    /// The brief asked for it trailing the navigation title. That bar is
    /// 162 pt and already holds "Set 1/3", the session clock and the deck
    /// glyph, and the file's own history records watchOS silently dropping a
    /// toolbar item rather than overflowing it — so a fourth thing up there is
    /// a reading that disappears without a diagnostic. This line already
    /// exists, it is already the line about what just happened, and the rate
    /// is legible at 146 pt beside it.
    ///
    /// It goes in the always-on state with everything else stale: a heart rate
    /// from four minutes ago is a lie, not a reading (`WatchInk`).
    @ViewBuilder
    private var receipt: some View {
        if model.lastTime != nil || model.workout.heartRate != nil {
            HStack(spacing: OnyxSpace.xs) {
                if let last = model.lastTime {
                    Text("last · \(last)")
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                if let bpm = model.workout.heartRate, !isLuminanceReduced {
                    Label("\(bpm)", systemImage: "heart.fill")
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.record)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .accessibilityLabel("Heart rate \(bpm) beats per minute")
                }
            }
        }
    }

    /// ── THE CHEVRON IS GONE, AND THE DOTS ARE THE HINT (W3) ─────────────────
    /// There was a chevron here, then a labelled row, and the 49 mm shot said
    /// the same thing about both: page one is a movement name, a 50 pt
    /// numeral and a receipt inside about 95 pt, so anything else lands under
    /// the pinned tick and reads as a nick in the button rather than as
    /// "there is more below". The two dots at the trailing edge are the
    /// platform's own answer to the same question, they cost no height, and
    /// they are now honest about which page you are on. `sawQualityPanel` is
    /// kept: `DeckView`'s first-run affordances will want it.
    /// What the navigation bar says. The split's name is not it — see the
    /// comment on `.navigationTitle`.
    private var setTitle: String {
        guard let cursor = model.cursor else { return model.day?.label ?? "Onyx" }
        // ── "Set 1/3", NOT "Set 1 of 3" ────────────────────────────────────
        // The words cost ~17 pt of a 162 pt bar that now also carries the
        // session clock, and the 40 mm shot showed what that buys: the title
        // truncated to "Set 1 of" — the position without the total, which is
        // half a fact. A slash is the same fact in a form the bar can hold, and
        // it is how every set row in this app already writes a count.
        return "Set \(cursor.setNumber)/\(cursor.movement.plannedSets)"
    }

    // MARK: - The two values

    private func loadRow(model: WatchModel) -> some View {
        @Bindable var model = model

        return ValueRow(
            value: Deck.fmtKg(model.load),
            unit: "kg",
            font: WatchType.hero,
            isFocused: field == .load
        )
        // ── FOCUSABLE ONLY ON PAGE ONE (W3) ─────────────────────────────────
        // A view that cannot take focus cannot hold the Crown, whatever
        // SwiftUI's focus restoration decides to do when a page turns. Setting
        // `field = nil` is the other half; this is the one that does not depend
        // on a callback arriving in time.
        .focusable(page == .set && !isLuminanceReduced)
        .focused($field, equals: .load)
        // ── ONE DETENT IS 1.25 kg ───────────────────────────────────────────
        // `Ceilings.loadSteps` is `[2.5, 1.25]` and `loadStepFineKg` is 1.25 —
        // the plate stack's own two steps, pinned by `TrainingGoldenTests`, and
        // its comment says the constants live there "so both clients agree
        // before either draws a control". This is that control.
        //
        // NOT `Deck.fineStep` (0.25): that is the snap grid a hand-TYPED load is
        // rounded to, not a UI step, and at 0.25 per detent one plate is ten
        // clicks.
        .digitalCrownRotation(
            $model.load,
            from: 0, through: 500, by: Ceilings.loadStepFineKg,
            sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .onTapGesture { field = .load }
        // ── VOICEOVER TAKES THE CROWN ───────────────────────────────────────
        // `.digitalCrownRotation` is invisible to VoiceOver, and VoiceOver
        // claims the Crown for its own navigation — so a load whose only input
        // is the Crown is a load a VoiceOver user cannot change at all. This is
        // the same mutation, reachable by swipe.
        .accessibilityElement()
        .accessibilityLabel("Load")
        .accessibilityValue("\(Deck.fmtKg(model.load)) kilograms")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? Ceilings.loadStepFineKg : -Ceilings.loadStepFineKg
            model.load = Deck.nudgeLoad(model.load, step)
        }
    }

    private func repsRow(model: WatchModel) -> some View {
        @Bindable var model = model

        return ValueRow(
            value: "\(model.reps)",
            unit: "reps",
            font: WatchType.value,
            isFocused: field == .reps
        )
        .focusable(page == .set && !isLuminanceReduced)
        .focused($field, equals: .reps)
        .digitalCrownRotation(
            Binding(
                get: { Double(model.reps) },
                set: { model.reps = max(1, Int($0.rounded())) }
            ),
            from: 1, through: 50, by: 1,
            sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .onTapGesture { field = .reps }
        .accessibilityElement()
        .accessibilityLabel("Reps")
        .accessibilityValue("\(model.reps)")
        .accessibilityAdjustableAction { direction in
            model.reps = max(1, model.reps + (direction == .increment ? 1 : -1))
        }
    }

    // MARK: - The one button

    private var tick: some View {
        Button {
            if model.commitSet() {
                WKInterfaceDevice.current().play(.success)
            } else {
                WKInterfaceDevice.current().play(.failure)
            }
        } label: {
            Label("Log set", systemImage: "checkmark")
                .font(WatchType.value)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchInk.commit)
        .foregroundStyle(WatchInk.onCommit)
        // ── THE CHEAPEST WAY TO BEAT HEVY, IN ONE MODIFIER ──────────────────
        // Double-pinch logs the set. Hevy's advantage over a phone is not
        // needing your phone; this app's advantage over Hevy is not needing your
        // hand — which matters most at the exact moment your hands are chalked,
        // gloved or still on the bar.
        .handGestureShortcut(.primaryAction)
        // A full-width accent at full brightness for three minutes of rest is
        // an OLED power cost and a burn-in risk. Hidden rather than dimmed: a
        // button drawn as pressable that needs a wake-tap first is a button
        // that should not be drawn.
        .opacity(isLuminanceReduced ? 0 : 1)
        .disabled(isLuminanceReduced)
    }
}

// MARK: - Throwing the workout away

/// The one gesture on this wrist that cannot be undone.
///
/// ── WHY IT IS NOT A `confirmationDialog` ────────────────────────────────────
/// It was, and the 49 mm shot showed two things a system dialog would not let
/// this app fix. Its destructive button renders red text on a dark red fill —
/// about 3.4:1, under AA for text this size, on the one control that must not
/// be mis-tapped. And watchOS places the `.cancel` role LAST whatever order
/// the buttons are declared in, so the only labelled control in frame was
/// "Discard" and the only visible way out was the ✕ in the corner — which
/// everywhere else in this app means "dismiss the rest cover".
///
/// So: the escape is first, full width and in ordinary ink; the destructive
/// one is below it, red on the app's own flat fill rather than on a
/// translucent material — this device has no glass anywhere else either
/// (`WatchInk`).
struct DiscardSheet: View {

    let setCount: Int
    let onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: OnyxSpace.s) {
                Text("Discard this workout?")
                    .font(WatchType.value)
                    .foregroundStyle(WatchInk.primary)
                    .multilineTextAlignment(.center)
                Text(setCount == 1 ? "1 logged set is deleted." : "\(setCount) logged sets are deleted.")
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.secondary)
                    .multilineTextAlignment(.center)

                Button("Keep going") { dismiss() }
                    .font(WatchType.value)
                    .buttonStyle(.borderedProminent)
                    .tint(WatchInk.fillActive)
                    .foregroundStyle(WatchInk.primary)

                Button("Discard") {
                    onDiscard()
                    dismiss()
                }
                .font(WatchType.value)
                .buttonStyle(.bordered)
                .tint(WatchInk.fill)
                .foregroundStyle(WatchInk.danger)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OnyxSpace.xs)
        }
        .containerBackground(for: .navigation) { WatchInk.ground }
    }
}

// MARK: - A focusable number

/// A value the Crown can drive, with the ring that says so.
///
/// The ring is the entire legibility argument for one Crown with two meanings
/// (see `SetView`'s header) — so it is drawn as a real border rather than a
/// tint, and it is the thing that changes when focus moves.
///
/// Internal rather than private since W3: the rest screen's "edit last set"
/// sheet drives the same two values with the same Crown, and a second row
/// style for the same job on the same wrist is how two screens start
/// disagreeing about what a focused number looks like.
struct ValueRow: View {
    let value: String
    let unit: String
    let font: Font
    let isFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.xs) {
            Text(value)
                .font(font)
                .foregroundStyle(WatchInk.primary)
                // Six characters at hero size — `137.25` is reachable on the
                // 1.25 grid — is ~130 pt of the 146 available at 40 mm.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit)
                .font(WatchType.label)
                .foregroundStyle(WatchInk.secondary)
        }
        .padding(.horizontal, OnyxSpace.xs)
        // One point, not two. See the budget note on `setPage`: the four
        // points this gives back are four the receipt needed.
        .padding(.vertical, 1)
        // ── IT SIZES TO ITS CONTENT, AND THAT IS THE POINT ──────────────────
        // Never a hardcoded `.frame(width:)`: watchOS does not clip an over-wide
        // child and does not warn — it draws it off the display.
        // `containerRelativeFrame(.horizontal)` was the first cure and it was
        // the wrong one, because it measures the SCROLL VIEW rather than the
        // padded content area, so the row came out wider than the space it had
        // and the `kg` went past the right edge.
        //
        // Now that the load and the reps share a row, neither may claim the
        // width: they take what they need, `minimumScaleFactor` absorbs a long
        // load, and the HStack does the arranging.
        .background(
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .fill(isFocused ? WatchInk.fillActive : WatchInk.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .strokeBorder(isFocused ? WatchInk.commit : .clear, lineWidth: 2)
        )
    }
}
