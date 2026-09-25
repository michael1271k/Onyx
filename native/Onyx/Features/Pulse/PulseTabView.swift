import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// The Body tab root (Pulse until Precision B4, decision Q19) — one date's
/// readiness, vitals and body. The file keeps its old name; the type is new.
///
/// ── WHAT WAVE 2.9 CHANGED ───────────────────────────────────────────────────
/// This was a `ScrollView` of six equal boxes: Sleep, Fatigue, Soreness, Stack,
/// Scale, Schedule — every one of them a bordered card with a caption header,
/// every one the same size whether it held one number or twenty-seven. That is
/// the web app's shape, and §3.6 names it exactly ("every list is a `List`, not
/// a `ScrollView` of cards").
///
/// What it is now, after W9: a Now strip, one hero vital over a grid of eight,
/// and a 2 × 3 grid of squares in the reader's own order — the two things the
/// day ASKS (fatigue, the stress log) and the four it MEASURED (the stress
/// index, what is sore, what the scale said, what the stack counted). Nothing
/// on it scrolls sideways. The Schedule tile is gone (swap moved to the Workout
/// tab's session card, where the thing you are swapping actually lives) and so
/// is Cardio (§5.2 item 5).
struct BodyTabView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Supplied only by previews and the screenshot harness.
    var seeded: DayModel?
    /// Harness only: which section to open scrolled to. Half this screen is
    /// below the fold and a single shot cannot reach it.
    var startAtRows = false
    /// Harness only: open with the squares already jiggling. A long press
    /// cannot be filmed; the mode can.
    var startEditing = false
    @State private var resolved: DayModel?

    init() {}

    /// Harness only: draw the day as History's past-day push draws it —
    /// session tickets and the retro door included (Precision B4).
    var showsWorkouts = false

    init(seeded: DayModel, startAtRows: Bool = false, startEditing: Bool = false, showsWorkouts: Bool = false) {
        self.seeded = seeded
        self.startAtRows = startAtRows
        self.startEditing = startEditing
        self.showsWorkouts = showsWorkouts
    }

    var body: some View {
        Group {
            if let resolved {
                // The tab root shows no workouts (Q19: Train owns them). The
                // same screen pushed from History for a past day keeps them.
                DayScreen(model: resolved, showsWorkouts: showsWorkouts,
                          startAtRows: startAtRows, startEditing: startEditing)
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task {
            if resolved == nil {
                resolved = seeded ?? DayModel(
                    database: environment.database, userId: environment.userIdString,
                    environment: environment
                )
            }
            await resolved?.observe()
        }
    }
}

/// One date, laid out. Named for the date rather than the tab because History
/// pushes this same screen for a past day (§5.9).
struct DayScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    let model: DayModel
    /// The day's session tickets and the "Log a workout here" door. False on
    /// the Body tab (decision Q19: Train owns workouts); true when History
    /// pushes this screen for a past day, where the retro door is the only
    /// way to log a workout on a date that has gone.
    var showsWorkouts = true
    /// Harness only — see `BodyTabView.startAtRows`.
    var startAtRows = false
    var startEditing = false

    @State private var showCalendar = false
    @State private var ratingFatigue = false
    @State private var loggingStress = false
    @State private var browsingStress = false
    @State private var entering = false
    @State private var showStack = false
    @State private var showSoreness = false
    @State private var editingSleep = false
    /// The Water petal's sheet (Precision B4) — the day's water answer.
    @State private var loggingWater = false
    /// The Heart and Steps petals' door: the vitals' own trends.
    @State private var showTrends = false
    /// The stress breakdown. Declared here rather than on the square that opens
    /// it for the reason every other sheet on this screen is: the square grid is
    /// one `List` row, and a `.sheet` on a recyclable cell is torn down with the
    /// cell. `StressTile` owned this presentation until W3 and was the one
    /// surface on Pulse that still did.
    @State private var showingStress = false
    /// The session the Workout summary card was tapped on. `item:` rather than
    /// `isPresented:` because a day can hold two sessions and each card has to
    /// push its own.
    @State private var openSession: DayModel.WorkoutSummary?
    /// A workout being logged for THIS past date (W2, decision 12): the edit
    /// deck over a session born closed. `item:` so the cover owns the model.
    @State private var retroEditor: LoggerModel?
    /// The masthead for each session on this date, by id.
    ///
    /// A career-wide read (`SessionAnalysis.headers` walks the whole ledger to
    /// place each session in the record), so it is NOT on the day-window path
    /// that runs on every date step — it is its own detached task keyed on the
    /// ids, exactly as the Train tab's done card loads the same value.
    @State private var sessionHeaders: [String: SessionHeader] = [:]
    /// How far the list has been pulled up, in points, clamped to the wash's
    /// own height. Zero at the top and 1 once the header band has scrolled
    /// away — see `muscleWash`.
    @State private var scrolled: CGFloat = 0

    var body: some View {
        ScrollViewReader { scroller in list(scroller: scroller) }
    }

    /// The programme that owned this date — its plan's `routines` rows.
    private var retroProgram: Program? {
        environment.targets.map { Schedule.programForContext($0.schedule, model.date).program }
    }

    /// The cover closed. A retro session that never got a set is a workout
    /// that did not happen: `discardSession` takes the row, its queued upsert
    /// and the server copy, and the door cascades the day back.
    private func discardEmptyRetro() {
        guard let id = lastRetroSessionId else { return }
        lastRetroSessionId = nil
        let database = environment.database
        if (try? database.sets(sessionId: id, userId: environment.userIdString))?.isEmpty == true {
            _ = try? database.discardSession(id: id, userId: environment.userIdString)
        }
    }
    @State private var lastRetroSessionId: String?

    /// Create the session on this date, born closed, and open the edit deck.
    private func logRetro(_ day: ProgramDay) {
        guard let session = try? environment.database.createRetroSession(
            userId: environment.userIdString, dayKey: day.key, date: model.date
        ) else { return }
        let editor = LoggerModel(
            day: day, phase: environment.targets?.schedule.phase ?? .cut,
            store: environment.database, userId: environment.userIdString,
            startedAt: session.startedAt ?? Date(), openingForEdit: true
        )
        editor.attach(editing: session)
        guard editor.sessionId != nil else {
            _ = try? environment.database.discardSession(id: session.id, userId: environment.userIdString)
            return
        }
        lastRetroSessionId = session.id
        retroEditor = editor
    }

    /// The wash itself. Nil hues — a day with no session, or a session of
    /// movements the map does not know — draw nothing at all rather than a
    /// grey band: "nothing was trained" is a real answer and it has no colour.
    @ViewBuilder
    private var muscleWash: some View {
        // Two sessions on one date is two decks' worth of muscles; the first
        // two distinct ones are what the gradient can distinguish, and the
        // first session is the one the eye has already seen a card for.
        var seen: Set<LandmarkMuscle> = []
        let hues = model.window.sessions
            .flatMap(\.muscles)
            .filter { seen.insert($0).inserted }
            .prefix(2)
            .map { Color.onyx.muscle($0) }
        if !hues.isEmpty {
            LinearGradient(
                stops: hues.enumerated().map { index, hue in
                    .init(
                        color: hue.opacity(0.18),
                        location: hues.count > 1 ? Double(index) / Double(hues.count - 1) : 0
                    )
                },
                startPoint: .topLeading, endPoint: .topTrailing
            )
            .mask { LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom) }
            .frame(height: 120)
            // Gone by the time the band itself would have scrolled off, so the
            // fade tracks the thing it belongs to rather than a guessed
            // distance.
            .opacity(Double(max(0, 1 - scrolled / 120)))
            .allowsHitTesting(false)
            .ignoresSafeArea(edges: .top)
            .accessibilityHidden(true)
        }
    }

    private func list(scroller: ScrollViewProxy) -> some View {
        List {
            if let failure = model.failure {
                OnyxBanner(tone: .failure, title: "Not saved locally", message: failure).plainRow()
            }

            // The scale synced through Health and the InBody numbers it cannot
            // know are still blank. Only on today — a past day's blanks are
            // history, not a task.
            if environment.weighInPending, model.isToday {
                OnyxBanner(
                    tone: .notice,
                    title: "Finish the InBody reading",
                    message: "Weight is in from Health. Muscle and water are still blank.",
                    actionLabel: "Enter"
                ) { entering = true }
                    .plainRow()
            }

            // ── THE INSTRUMENT (Precision B4, design 9) ─────────────────────
            // The readiness ring and its six petals replace the Now strip:
            // the score, the battery and the fuel sentence ARE the ring, its
            // inner arc and three of its petals now. The date the strip
            // carried is the line over it — the only place the screen says
            // which day this is.
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Text(title).onyxMicro()
                BodyRing(score: model.score, battery: model.battery, petals: model.bodyPetals, onPetal: openPetal)
            }
            .plainRow()

            // ── THE MEASUREMENTS: ONE LEAD AND EIGHT SIDEKICKS (W2) ─────────
            // These nine were a horizontal scroller of 104 pt chips with the
            // grid behind a disclosure — ~1,010 pt of content in a 375 pt
            // window, eight of the nine reachable only by swiping. Now the
            // night leads at full width and the eight sit under it, and an
            // alarming vital takes the lead from the night (`VitalsSection`).
            VitalsSection(model: model) { editingSleep = true }

            // ── AND THE SIX: TWO IT ASKS YOU, FOUR IT MEASURED (W9) ─────────
            // Fatigue and the stress log were a two-page carousel here — the
            // one side-scroll on Pulse — over a 2 × 2 of the measurements. One
            // 2 × 3 grid now, in the order the reader keeps (toolbar Edit,
            // then drag), stored beside the Today tab's arrangement
            // (`PulseLayout`). The default puts the index first and the log
            // beside it: the index's `self` term is built from those two
            // answers, and the two sit on one row rather than one above the
            // other so neither reads as the other's cause.
            PulseSquareGrid(
                model: model,
                onStress: { showingStress = true },
                onLogStress: { loggingStress = true },
                onBrowseStress: { browsingStress = true },
                onSoreness: { showSoreness = true },
                onFatigue: { ratingFatigue = true },
                onScale: { entering = true },
                onStack: { showStack = true }
            )
            .plainRow()
            .id(Self.rowsAnchor)

            // Whatever was trained on this date, and the door to the page that
            // reads it properly. §W11 asks for it on a PAST day; it is drawn
            // whenever the day HAS a finished session, because a card that
            // appears at midnight for the session you finished at six is a
            // worse rule than one that appears when the session does.
            //
            // Last on the screen, on purpose (founder decision 7): Pulse
            // answers "how am I", and what caused it is the footnote to that,
            // not its headline.
            if showsWorkouts {
                ForEach(model.window.sessions) { session in
                    PulseSessionCard(session: session, header: sessionHeaders[session.id]) {
                        openSession = session
                    }
                    .plainRow()
                }
            }
            // ── LOG A WORKOUT HERE (W2, decision 12) ────────────────────────
            // A past day only: today's workouts start from the Train tab with
            // a clock, and a future one is a plan. The deck is one of the
            // programme's days, chosen here because a rest day has none to
            // assume; the session is created closed and opens in EDIT mode —
            // no timer, no Live Activity, no watch mirror.
            if showsWorkouts, model.date < LogicalDay.today(), let program = retroProgram, !program.days.isEmpty {
                Menu {
                    ForEach(program.days, id: \.key) { day in
                        Button(day.label) { logRetro(day) }
                    }
                } label: {
                    Label("Log a workout here", systemImage: "plus.circle")
                        .onyxType(.body)
                        .foregroundStyle(Color.onyx.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel("Log a workout on \(model.date)")
                .plainRow()
            }
        }
        .fullScreenCover(item: $retroEditor, onDismiss: discardEmptyRetro) { editor in
            NavigationStack { LiveLoggerView(model: editor) }
        }
        .listStyle(.plain)
        // ── THE DAY'S OWN COLOUR, BEHIND THE TOP OF THE LIST ────────────────
        // A recovery screen that says nothing about what caused the recovery
        // was the gap: the session card is 600 pt down the page, and the top of
        // Pulse was black whatever yesterday had been. This is the same
        // 18 %→0 wash the session card wears, in the same muscle hues, behind
        // the first 120 pt of the list.
        //
        // ── AND WHY IT FADES WITH THE SCROLL ────────────────────────────────
        // It belongs to the TOP of the screen, not to the screen: pinned, it
        // would sit behind the vitals and the soreness rows as a coloured band
        // that means nothing where it is, and it would fight the glass of every
        // tile that scrolled under it. Tying its opacity to the offset is what
        // Apple Music does with an album header — the colour is a property of
        // being at the top, and it leaves when you do.
        //
        // `onScrollGeometryChange` rather than a `GeometryReader` in a row: the
        // reader would re-measure on every row recycle, and this needs ONE
        // number per frame from the scroll view that already has it.
        .background(alignment: .top) { muscleWash }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrolled = max(0, offset)
        }
        // `m`, not `l`: every section on this screen is now either a tile with
        // its own 12 pt of padding or a run of 44 pt rows, so a 16 pt trench
        // between them is a gap between two gaps. Four of those is 16 pt of the
        // screen and a half this wave is aiming at.
        .listSectionSpacing(OnyxSpace.m)
        .scrollContentBackground(.hidden)
        .onyxScreen(.body)
        .cardioIngestNotice()
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // ── NO TITLE IN THE BAR (W9) ────────────────────────────────────
            // Five items across two pills leave "Pulse" no room on a phone,
            // and what iOS does with a title that does not fit depends on the
            // width: clipped to its first letter on one, hidden on another.
            // Removed on purpose instead, so the bar is the same bar
            // everywhere. `navigationTitle` stays — it is the back button on
            // Body trends — and the tab bar and the date line name the screen.
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            // The date walks on the LEADING side and the doors sit trailing:
            // four glyphs crowded into one group left "Pulse" with no room for
            // its own title, and a chevron beside a chart icon reads as a
            // disclosure rather than as yesterday.
            ToolbarItemGroup(placement: .topBarLeading) {
                Button { model.step(-1) } label: {
                    Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Previous day")

                Button { model.step(1) } label: {
                    Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                }
                .disabled(model.isToday)
                .accessibilityLabel("Next day")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showCalendar = true } label: {
                    Image(systemName: "calendar").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Choose a day")

                NavigationLink {
                    BodyTrendsView()
                } label: {
                    Image(systemName: "chart.xyaxis.line").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Body trends")

                // The squares' arrangement (W9) — the Today tab's Edit/Done,
                // for the same mode. The glyph is the one Today's long-press
                // menu already puts beside "Edit Dashboard"; the WORD "Edit"
                // as a third trailing item left "Pulse" one letter of title.
                if model.editingSquares {
                    Button("Done") { withAnimation(OnyxMotion.flick) { model.editingSquares = false } }
                        .fontWeight(.bold)
                } else {
                    Button { withAnimation(OnyxMotion.flick) { model.editingSquares = true } } label: {
                        Image(systemName: "square.grid.2x2").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Edit squares")
                    .accessibilityHint("Rearrange the squares")
                }
            }
        }
        .tint(Color.onyx.accent(.body))
        .sheet(isPresented: $showCalendar) {
            DaySheet("Choose a day", domain: .body) {
                DatePicker("Day", selection: selectedDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(OnyxSpace.s)
            }
        }
        // ── EVERY SHEET IS PRESENTED FROM HERE, INCLUDING THE SQUARES' ──────
        // The grid is one `List` row, which is re-hosted when it scrolls out
        // of the window. A `.sheet` declared on a square would be torn down
        // with it — the sheet dismisses itself the first time the list scrolls
        // far enough, mid-typing. So the squares take closures and the screen
        // owns the presentation.
        .sheet(isPresented: $ratingFatigue) { FatigueSheet(model: model) }
        // ── ONE SHEET, THREE SEGMENTS (§W6-B.4) ─────────────────────────
        // Both squares open the SAME sheet on their own segment, so the other
        // two answers about this day are one tap away instead of on another
        // tab behind a long-press. `LogDaySheet` explains why the three are
        // not one form.
        .sheet(isPresented: $loggingStress) { LogDaySheet(model: model, segment: .stress) }
        .sheet(isPresented: $browsingStress) { StressLogListSheet(model: model) }
        .sheet(isPresented: $showSoreness) { LogDaySheet(model: model, segment: .soreness) }
        .sheet(isPresented: $showingStress) { StressBreakdownSheet(model: model) }
        .sheet(isPresented: $editingSleep) { SleepEditSheet(model: model) }
        .sheet(isPresented: $loggingWater) { LogDaySheet(model: model, segment: .water) }
        .navigationDestination(isPresented: $showTrends) { BodyTrendsView() }
        .navigationDestination(item: $openSession) { SessionDetailView(sessionId: $0.id) }
        .sheet(isPresented: $entering) { InBodyEntryView(model: model) }
        // Today's banner switched to this tab and asked for the form.
        .onChange(of: environment.scaleEntryRequests) { _, _ in
            if model.isToday { entering = true }
        }
        // A push, not a sheet: the stack has sections, an editor and an
        // archive, and a modal is for one decision (§W6).
        .navigationDestination(isPresented: $showStack) { StackView(model: model) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshToday()
                model.loadWindow()
            }
        }
        .onChange(of: environment.today) { _, _ in
            model.refreshToday()
            model.loadWindow()
        }
        // Every door into this screen — the Pulse tab, a week in History, the
        // calendar jump — has to open the day's streams, or the tiles draw
        // their initial empty values and stay that way. `observe()` guards
        // re-entry, so the Pulse tab's own call is harmless; a `.task` of its
        // own so the streams stop when the screen goes, keyed on the model so
        // a parent that rebuilds its `DayModel` inline (History, the calendar
        // jump) hands the new one a running observer too.
        .task(id: ObjectIdentifier(model)) { await model.observe() }
        // The mastheads. Keyed on the ids so stepping to a day with the same
        // sessions costs nothing, and detached because `headers` replays every
        // set ever logged to place each session in the career — the same read,
        // made the same way, as the Train tab's done card.
        .task(id: showsWorkouts ? model.window.sessions.map(\.id) : []) {
            let ids = showsWorkouts ? model.window.sessions.map(\.id) : []
            guard !ids.isEmpty else {
                sessionHeaders = [:]
                return
            }
            let database = model.database, userId = model.userId
            let loaded = await Task.detached(priority: .userInitiated) {
                SessionAnalysis.headers(database: database, userId: userId, sessionIds: ids)
            }.value
            // ── THE GUARD IS NOT DEFENSIVE, IT IS THE WHOLE RACE ────────────
            // `await someTask.value` on a non-throwing Task is NOT a
            // cancellation point: when `.task(id:)` tears this body down
            // because the date stepped, the old body still resumes and still
            // assigns. The walk is the whole career and its cost varies with
            // the day, so stepping A → B while A is slow leaves `sessionHeaders`
            // holding A's dictionary — and B's card falls to its placeholder
            // and NEVER recovers, because `.task(id:)` will not fire again
            // until the ids change.
            guard !Task.isCancelled else { return }
            sessionHeaders = loaded
        }
        .task {
            guard startEditing || startAtRows else { return }
            // `startEditing` flips the SAME flag the toolbar flips, so the shot
            // photographs the real mode rather than a second code path.
            if startEditing { model.editingSquares = true }
            guard startAtRows else { return }
            // ── THE WAIT IS NOT OPTIONAL ────────────────────────────────────
            // The same 400 ms the ledger shot needs (Wave 2.8): a `List` picks
            // its anchor at first layout, which happens while it is still
            // empty, so the scroll has to wait for the rows to exist.
            try? await Task.sleep(for: .milliseconds(400))
            scroller.scrollTo(Self.rowsAnchor, anchor: .top)
        }
    }

    /// A petal's door: the sheet or screen that already owns its domain.
    private func openPetal(_ kind: BodyPetal.Kind) {
        switch kind {
        case .sleep: editingSleep = true
        case .water: loggingWater = true
        // Food lives on its own tab; the petal is a way there, not a copy.
        case .food: environment.selectedTab = "fuel"
        case .heart, .steps: showTrends = true
        case .stress: showingStress = true
        }
    }

    /// The anchor the harness scrolls to: the square grid, which is where the
    /// bottom half of the screen starts. Everything under it — the session
    /// cards — is below the fold on a phone, and everything above it is what
    /// the default `day` shot already photographs.
    private static let rowsAnchor = "pulse.rows"

    /// "Thu 3 Sept" — a date, formatted; never the ISO string. It rides over
    /// the ring rather than in the nav bar: the tab is called Body everywhere
    /// else on the device, and a title that changes as you step through the
    /// week is a title you cannot navigate by.
    private var title: String {
        guard let date = LogicalDay.date(fromISO: model.date) else { return model.date }
        return model.isToday
            ? "Today · \(date.formatted(.dateTime.day().month(.abbreviated)))"
            : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var selectedDate: Binding<Date> {
        Binding(
            get: { LogicalDay.date(fromISO: model.date) ?? Date() },
            set: { model.select(LogicalDay.iso($0)) }
        )
    }
}

// MARK: - Shared chrome

/// One tile: a caption header in the domain's accent, then content.
struct DayTile<Content: View, Trailing: View>: View {
    let title: String
    let domain: OnyxDomain
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, _ domain: OnyxDomain,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.domain = domain
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.m) {
            // An EMPTY title means the surface above has already said it —
            // a sheet whose navigation bar carries the same word
            // (`docs/COMPACTION_AUDIT.md` §2). The trailing word stays: on the
            // soreness atlas it is Front/Back, which is state and not a label.
            if title.isEmpty {
                HStack { Spacer(minLength: 0); trailing() }
            } else {
                // At AX5 the title and its trailing word are each half a line
                // wide and ran into each other ("Soreness FRONT" with no gap).
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        OnyxSectionHeader(title, domain)
                        Spacer(minLength: OnyxSpace.s)
                        trailing()
                    }
                    VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                        OnyxSectionHeader(title, domain)
                        trailing()
                    }
                }
            }
            content()
        }
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.tile)
        .foregroundStyle(Color.onyx.textPrimary)
    }
}

/// The 44 pt row this tab is mostly made of: a symbol, a name, what it says
/// today, and the thing you tap.
///
/// Three screens' worth of content — fatigue, the scale, the stack — used to be
/// three tiles of chips, seven metrics and a nested list. Each is now one row
/// that states its answer and opens a sheet, which is what a `List` row on iOS
/// has always been.
struct PulseRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let detail: String
    var tint: Color = Color.onyx.accent(.body)
    /// Spoken instead of `detail` when the words on screen are shorthand.
    var spoken: String?
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    init(symbol: String, title: String, detail: String,
         tint: Color = Color.onyx.accent(.body), spoken: String? = nil,
         action: @escaping () -> Void,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.tint = tint
        self.spoken = spoken
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            Group {
                if typeSize.isAccessibilitySize { stacked } else { oneLine }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.99)
        .listRowInsets(EdgeInsets(top: OnyxSpace.s, leading: OnyxSpace.l, bottom: OnyxSpace.s, trailing: OnyxSpace.l))
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.onyx.hairline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(spoken ?? detail)")
        .accessibilityAddTraits(.isButton)
    }

    private var oneLine: some View {
        HStack(spacing: OnyxSpace.m) {
            glyph
            Text(title)
                .onyxType(.body)
                .foregroundStyle(Color.onyx.textPrimary)
            Spacer(minLength: OnyxSpace.s)
            Text(detail)
                .onyxType(.caption).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
                .lineLimit(1)
            trailing()
            chevron
        }
    }

    /// Three lines rather than two. At AX5 the second line held the detail AND
    /// the trailing content, and the fatigue row's word pushed its own dots off
    /// the right edge — a row that cannot show its own state.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            HStack(spacing: OnyxSpace.s) {
                Text(title).onyxType(.body).foregroundStyle(Color.onyx.textPrimary)
                Spacer(minLength: OnyxSpace.s)
                chevron
            }
            Text(detail)
                .onyxType(.caption).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
            HStack(spacing: OnyxSpace.s) {
                trailing()
                Spacer(minLength: 0)
            }
        }
    }

    /// Decoration, and the first thing to go at the accessibility sizes: the
    /// glyph tracks the text scale, and a 50 pt pill beside a 50 pt word is a
    /// row with no room for either.
    @ViewBuilder
    private var glyph: some View {
        if !typeSize.isAccessibilitySize {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .onyxType(.caption).fontWeight(.bold)
            .foregroundStyle(Color.onyx.textTertiary)
            .accessibilityHidden(true)
    }
}

/// A presented sheet: inline title, Done, the domain's ground, medium/large.
///
/// A form sheet passes `primary` — a (title, enabled, action) triple — and gets
/// Cancel on the left and that action on the right; a sheet whose every tap
/// already saved (soreness, the calendar) passes nothing and gets Done.
struct DaySheet<Content: View>: View {
    typealias Primary = (title: String, enabled: Bool, action: () -> Void)

    let title: String
    let domain: OnyxDomain
    var glass = true
    /// Half height and full, which is right for a form and wrong for a body:
    /// the soreness atlas is 280 pt before its caption and a medium detent
    /// opens onto a figure cropped at the ribs. A sheet whose content has a
    /// natural size passes its own.
    var detents: Set<PresentationDetent> = [.medium, .large]
    var primary: Primary?
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    init(_ title: String, domain: OnyxDomain, glass: Bool = true,
         detents: Set<PresentationDetent> = [.medium, .large], primary: Primary? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.domain = domain
        self.glass = glass
        self.detents = detents
        self.primary = primary
        self.content = content
    }

    var body: some View {
        NavigationStack {
            Group {
                if glass {
                    ScrollView {
                        content()
                            .padding(OnyxSpace.l)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onyxGlass(.sheet)
                            .padding(OnyxSpace.l)
                    }
                    .onyxScreen(domain)
                } else {
                    // A `Form` draws its own rows; it takes the form ground.
                    content().onyxFormBackground(domain)
                }
            }
            .foregroundStyle(Color.onyx.textPrimary)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let primary {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(primary.title, action: primary.action)
                            .fontWeight(.semibold)
                            .disabled(!primary.enabled)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .tint(domain.accent)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.onyx.base)
        .preferredColorScheme(.dark)
    }
}

/// A figure or an em dash. `nil` is never zero, anywhere in this app.
enum DayFormat {
    static func number(_ value: Double?, fraction: Int = 1, unit: String? = nil) -> String {
        guard let value, value.isFinite else { return "—" }
        let text = value.formatted(.number.precision(.fractionLength(0...fraction)).grouping(.never))
        return unit.map { "\(text) \($0)" } ?? text
    }

    // Sleep durations are `Format.sleep` (OnyxCore), not a second rule here:
    // the same night is printed by the widget and the export, and a copy that
    // said "7h 0m" where they said "7h" was two apps disagreeing about one
    // reading.

    /// The device's minute of the day, for the slot clock.
    static var nowMinutes: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

#if DEBUG
#Preview("Pulse") {
    NavigationStack { PulsePreviews.view("day") }
}
#endif
