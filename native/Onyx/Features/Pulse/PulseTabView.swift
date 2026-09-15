import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// The Pulse tab root — one date's recovery, vitals and body.
///
/// ── WHAT WAVE 2.9 CHANGED ───────────────────────────────────────────────────
/// This was a `ScrollView` of six equal boxes: Sleep, Fatigue, Soreness, Stack,
/// Scale, Schedule — every one of them a bordered card with a caption header,
/// every one the same size whether it held one number or twenty-seven. That is
/// the web app's shape, and §3.6 names it exactly ("every list is a `List`, not
/// a `ScrollView` of cards").
///
/// What it is now: two tiles that genuinely need to be tiles because they draw
/// a GAUGE (the sleep arc, the body), a real `List` section of eight vitals at
/// 44 pt, and three rows — fatigue, scale, stack — that open sheets. The
/// Schedule tile is gone (swap moved to the Workout tab's session card, where
/// the thing you are swapping actually lives) and so is Cardio (§5.2 item 5).
struct PulseTabView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Supplied only by previews and the screenshot harness.
    var seeded: DayModel?
    /// Harness only: which section to open scrolled to. Half this screen is
    /// below the fold and a single shot cannot reach it.
    var startAtRows = false
    /// Harness only: which carousel page to open on. Two of the three pages are
    /// off-screen by definition, and `simctl` can film a simulator but cannot
    /// swipe one.
    var startAtPage: PulsePage?
    /// Harness only: open with the vitals grid down. It is a disclosure, so its
    /// open state exists only after a tap nobody can make in a screenshot.
    var startVitalsOpen = false

    @State private var resolved: DayModel?

    init() {}

    init(seeded: DayModel, startAtRows: Bool = false,
         startAtPage: PulsePage? = nil, startVitalsOpen: Bool = false) {
        self.seeded = seeded
        self.startAtRows = startAtRows
        self.startAtPage = startAtPage
        self.startVitalsOpen = startVitalsOpen
    }

    var body: some View {
        Group {
            if let resolved {
                DayScreen(
                    model: resolved,
                    startAtRows: startAtRows,
                    startAtPage: startAtPage,
                    startVitalsOpen: startVitalsOpen
                )
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task {
            if resolved == nil {
                resolved = seeded ?? DayModel(database: environment.database, userId: environment.userIdString)
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
    /// Harness only — see `PulseTabView.startAtRows`.
    var startAtRows = false
    var startAtPage: PulsePage?
    var startVitalsOpen = false

    @State private var showCalendar = false
    @State private var ratingFatigue = false
    @State private var loggingStress = false
    @State private var browsingStress = false
    @State private var entering = false
    @State private var showStack = false
    @State private var showSoreness = false
    @State private var editingSleep = false
    /// Which carousel page is showing.
    ///
    /// ── WHY IT LIVES HERE AND NOT IN `PulseCarousel` ────────────────────────
    /// The carousel is one `List` row, and a row scrolled out of the window and
    /// back is re-hosted with its inner scroll view at offset zero — the reader
    /// who was on Soreness comes back to Fatigue. `.scrollPosition(id:)` is a
    /// two-way binding and re-applies its value on that relayout, so the
    /// selection has to outlive the row for the offset to be recoverable at
    /// all. Optional because that is the only shape the modifier takes, and
    /// SwiftUI writes nil back while a scroll is between pages.
    @State private var page: PulsePage? = .fatigue
    /// Whether the vitals grid is open under the chip row.
    @State private var vitalsExpanded = false
    /// The session the Workout summary card was tapped on. `item:` rather than
    /// `isPresented:` because a day can hold two sessions and each card has to
    /// push its own.
    @State private var openSession: DayModel.WorkoutSummary?
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

            NowStripPulse(model: model, date: title).plainRow()

            // ── THE MEASUREMENTS, COMPRESSED TO ONE LINE ────────────────────
            // The night's tile and the nine-cell vitals grid were 360 pt of
            // permanently-open reference directly under the strip — the two
            // things on this screen that something ELSE measured, sitting above
            // the three it asks you. A chip row says the same readings in 44 pt
            // and the grid is one tap behind it (`VitalsChipRow`).
            VitalsChipRow(model: model, expanded: $vitalsExpanded) { editingSleep = true }

            // ── AND THEN THE THREE IT ASKS YOU ──────────────────────────────
            // Fatigue, the stress log and soreness were three 44 pt rows at the
            // BOTTOM of this screen, under a body map and five doors. They are
            // the only things on Pulse that cannot be answered by a watch, and
            // a row has no room for the answer AND the control. One page each,
            // swiped between, with the verb on the card's face.
            PulseCarousel(
                model: model,
                page: $page,
                onFatigue: { ratingFatigue = true },
                onLogStress: { loggingStress = true },
                onBrowseStress: { browsingStress = true },
                onSoreness: { showSoreness = true }
            )
            .plainRow(edgeToEdge: true)
            .id(Self.carouselAnchor)

            // ── WHY THESE TWO ARE ONE SECTION ───────────────────────────────
            // What you weigh and what you took: two 44 pt rows that each state
            // an answer and open a sheet, and neither is a question this screen
            // asks — the scale is a device reading you transcribe and the stack
            // is a list you maintain. The scale leads (§W11): what you weigh is
            // the reading the other is context for.
            Section {
                ScaleRow(model: model) { entering = true }
                StackRow(model: model) { showStack = true }
            }
            .id(Self.rowsAnchor)

            // Under the log, not above it: the index's `self` term is built
            // from the readings on the card above, and a number placed above
            // the thing it is partly made of asks to be read as a cause of it.
            StressTile(model: model).plainRow()

            // Whatever was trained on this date, and the door to the page that
            // reads it properly. §W11 asks for it on a PAST day; it is drawn
            // whenever the day HAS a finished session, because a card that
            // appears at midnight for the session you finished at six is a
            // worse rule than one that appears when the session does.
            //
            // Last on the screen, on purpose (founder decision 7): Pulse
            // answers "how am I", and what caused it is the footnote to that,
            // not its headline.
            ForEach(model.window.sessions) { session in
                PulseSessionCard(session: session, header: sessionHeaders[session.id]) {
                    openSession = session
                }
                .plainRow()
            }
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
        .navigationTitle("Pulse")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        // ── EVERY SHEET IS PRESENTED FROM HERE, INCLUDING THE CARDS' ────────
        // The carousel's three cards live inside a `List` row, which is
        // re-hosted when it scrolls out of the window. A `.sheet` declared on a
        // card would be torn down with it — the sheet dismisses itself the
        // first time the list scrolls far enough, mid-typing. So the cards take
        // closures and the screen owns the presentation, which is the rule this
        // file already followed for the four rows they replace.
        .sheet(isPresented: $ratingFatigue) { FatigueSheet(model: model) }
        .sheet(isPresented: $loggingStress) { StressLogSheet(model: model) }
        .sheet(isPresented: $browsingStress) { StressLogListSheet(model: model) }
        .sheet(isPresented: $showSoreness) { SorenessSheet(model: model) }
        .sheet(isPresented: $editingSleep) { SleepEditSheet(model: model) }
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
        .task(id: model.window.sessions.map(\.id)) {
            let ids = model.window.sessions.map(\.id)
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
            guard startAtPage != nil || startVitalsOpen || startAtRows else { return }
            // ── THE WAIT IS NOT OPTIONAL, FOR EITHER OPENING ────────────────
            // The same 400 ms the ledger shot needs (Wave 2.8): a `List` picks
            // its anchor at first layout, which happens while it is still
            // empty, so the scroll has to wait for the rows to exist.
            //
            // `.scrollPosition(id:)` has the same rule and fails WORSE: written
            // before the carousel's children have laid out, the binding keeps
            // the new page — so the dots move — and the scroll view never
            // applies it. The first shot of page two was page one with page
            // two's dot lit, which reviews as a broken pager and is in fact a
            // harness writing too early.
            try? await Task.sleep(for: .milliseconds(400))
            // `startAtPage` writes the SAME binding a swipe writes, so the shot
            // photographs the real paging path rather than a second code path
            // that only runs in a screenshot.
            if let startAtPage {
                // ── SCROLL FIRST, THEN PAGE ─────────────────────────────────
                // At an accessibility size the carousel starts well below the
                // fold, so its row is not realised yet and `.scrollPosition`
                // has nothing to apply the page to — the binding takes the
                // value, the pager does not move, and the shot is page one with
                // page two's dot lit. The same failure the 400 ms above exists
                // for, one layer down: bring the row on screen, let it lay out,
                // then ask it to page.
                scroller.scrollTo(Self.carouselAnchor, anchor: .top)
                try? await Task.sleep(for: .milliseconds(300))
                page = startAtPage
            }
            if startVitalsOpen { vitalsExpanded = true }
            guard startAtRows else { return }
            scroller.scrollTo(Self.rowsAnchor, anchor: .top)
        }
    }

    /// The anchor the harness scrolls to: the scale-and-stack section, which is
    /// where the bottom half of the screen starts. Everything under it — the
    /// stress index and the session card — is below the fold on a phone, and
    /// everything above it is what the default `day` shot already photographs.
    private static let rowsAnchor = "pulse.rows"

    /// The carousel row. At an accessibility size the Now strip alone is most
    /// of the screen, so the three cards are below the fold by definition and a
    /// shot of "page two at AX5" photographs the strip — which is how the time
    /// strip's own accessibility layout went unreviewed for a round.
    private static let carouselAnchor = "pulse.carousel"


    /// "Thu 3 Sept" — a date, formatted; never the ISO string. It rides in the
    /// Now strip rather than the nav bar: the tab is called Pulse everywhere
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

// MARK: - Now strip

/// Score, battery and the day's fuel in one line.
///
/// ── WHY THE MACROS ARE NOT DRAWN HERE ───────────────────────────────────────
/// §5.7 is explicit: no macro gauges on Pulse. Three gauges of protein, carbs
/// and fat exist on the Nutrition tab and are the same three gauges — drawing
/// them twice is how a five-tab app becomes a one-tab app with four aliases.
/// What survives is the SENTENCE, which is the only form in which the day's
/// intake is context for a recovery screen rather than the subject of it.
private struct NowStripPulse: View {
    let model: DayModel
    /// Which day this is — the only place on the screen that says so.
    let date: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var battery: Int? { model.battery }

    /// 44 pt, and NO numeral inside it. A ring this size cannot hold a legible
    /// number at any type size — at AX5 the first attempt rendered "…" inside
    /// the ring — and the figure it would hold is the one beside it.
    private var ring: some View {
        ZStack {
            Circle().stroke(Color.onyx.hairline, lineWidth: 4)
            Circle()
                .trim(from: 0, to: Double(battery ?? 0) / 100)
                .stroke(Color.onyx.battery(battery), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : OnyxMotion.counter, value: battery)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    /// A numeral over its name. Two of these — the day's score and the battery
    /// — because they answer different questions and the ring is a shape, not a
    /// reading you can put a decimal on.
    private func reading(_ value: Int?, _ label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value.map { "\($0)" } ?? "—")
                .onyxHero().onyxNumeral()
                .contentTransition(.numericText())
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(label).onyxMicro()
        }
    }

    private var scoreReading: some View {
        reading(model.score, "SCORE", tint: Color.onyx.textPrimary)
    }

    private var batteryReading: some View {
        reading(battery, "BATTERY", tint: Color.onyx.battery(battery))
    }

    @ViewBuilder
    private var fuel: some View {
        Text(model.fuelLine ?? "Nothing logged yet")
            .onyxType(.caption).onyxNumeral()
            .foregroundStyle(model.fuelLine == nil ? Color.onyx.textTertiary : Color.onyx.textSecondary)
            // At AX5 the sentence is six words a line; capping it at two cost
            // the water figure to an ellipsis. On one line of shipping type two
            // is the whole string.
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        Group {
            // At AX5 two numerals, a ring and a sentence cannot share a line —
            // the fuel line broke into five and pushed the ring off the tile.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OnyxSpace.s) {
                    Text(date).onyxMicro()
                    HStack(spacing: OnyxSpace.m) { ring; scoreReading; Spacer(minLength: 0) }
                    batteryReading
                    fuel
                }
            } else {
                VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                    Text(date).onyxMicro()
                    HStack(spacing: OnyxSpace.m) {
                        ring
                        scoreReading
                        batteryReading
                        Spacer(minLength: OnyxSpace.s)
                        fuel
                    }
                }
            }
        }
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .onyxGlass(.tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(date). Score \(model.score.map { "\($0)" } ?? "not scored"), battery \(battery.map { "\($0) percent" } ?? "unknown"). \(model.fuelLine ?? "nothing logged")"
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
            // At AX5 the title and its trailing word are each half a line wide
            // and ran into each other ("Soreness FRONT" with no gap).
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

    static func minutes(_ total: Int?) -> String {
        guard let total, total > 0 else { return "—" }
        return total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total)m"
    }

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
