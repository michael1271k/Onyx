import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// The Today tab — the heart of the app.
///
/// ── NOT THE WEB DASHBOARD IN A NEW FONT (§3.6) ───────────────────────────────
/// · The tiles ARE the widgets: WidgetKit families at their own proportions,
///   one drawing shared with the Home Screen.
/// · Edit mode is the iOS jiggle, entered by long-press and left by Done. There
///   is no Edit BUTTON: a permanent control for a mode you enter by touching the
///   thing you want to edit is the web app's affordance, not the phone's.
/// · Stacks are a paging carousel, swiped vertically, with page dots. It owns
///   its own gesture and switches this screen's scroll off for the length of a
///   swipe — see `SmartStackView`.
/// · No desktop layout, no trend strip, no sidebar: one column, one surface.
/// · The screen opens on one row — score, battery, today's session — and the
///   verdict is said once, in the coach card, rather than twice.
struct TodayTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    /// A seeded model for the shot loop; the live one is built from the environment.
    var seeded: TodayModel?
    /// The Workout tab has the logger; the Workout tile hands off to it.
    var onOpenTrain: () -> Void = {}
    var onOpenReports: () -> Void = {}
    /// The Now strip is a summary of Pulse, so tapping it goes there.
    var onOpenPulse: () -> Void = {}

    @State private var resolved: TodayModel?
    /// Bumped when a PULL finishes — the only sync §3.4 gives a haptic, because
    /// it is the only one the user is waiting on.
    @State private var pulls = 0
    /// Quick Log, behind the mark.
    ///
    /// The day's own model, built the first time the ring is opened rather than
    /// with the screen: Today draws from `TodayFeed`, not from `DayModel`, and
    /// standing a second set of eleven per-date streams up on every launch to
    /// serve a sheet most launches never open is eleven observations for
    /// nothing. `.task(id:)` starts it when it exists.
    @State private var quickLog: DayModel?
    @State private var showQuickLog = false
    /// The stacked tile currently being swiped, if any. Both this screen and the
    /// stack page vertically, so one of them has to yield for the length of a
    /// drag; `SmartStackView`'s header has the whole argument, including why
    /// this is the slot's id rather than a flag.
    @State private var paging: String?

    var body: some View {
        Group {
            if let model = resolved {
                content(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onyxScreen(.recover)
        .task {
            if resolved == nil {
                resolved = seeded ?? TodayModel(database: environment.database, userId: environment.userIdString)
            }
            await resolved?.observe()
        }
    }

    private func content(_ model: TodayModel) -> some View {
        @Bindable var model = model
        return ScrollView {
            VStack(spacing: OnyxSpace.m) {
                if environment.weighInPending {
                    OnyxBanner(
                        tone: .notice,
                        title: "Weigh-in landed",
                        message: "Health has today's weight. Muscle and water are still blank.",
                        actionLabel: "Enter"
                    ) {
                        environment.requestScaleEntry()
                        onOpenPulse()
                    }
                }
                NowStrip(
                    score: model.feed?.snapshot.score,
                    battery: model.feed?.snapshot.battery,
                    workout: model.feed?.snapshot.workout,
                    status: environment.sync,
                    onOpen: onOpenPulse
                )
                if let feed = model.feed, feed.weeklySummaryReady {
                    WeeklySummaryCTA(weekStart: feed.lastWeekStart, onOpen: onOpenReports)
                }
                DashboardGrid(model: model, paging: $paging) { open($0, model) }
                if model.editing { WidgetGallery(model: model) }
                if let feed = model.feed {
                    GoalBoardRow(board: feed.goalBoard)
                    WeekSoFarView(week: feed.weekSoFar)
                }
                if let failure = model.failure {
                    OnyxBanner(tone: .failure, title: "Today could not be built", message: failure)
                }
            }
            .padding(OnyxSpace.l)
        }
        .scrollDisabled(paging != nil)
        // §5.1: the hairline is the sync's whole visual budget. It sits at the
        // top of the CONTENT, not in the nav bar, because a bar that changes
        // height when a sync starts moves the screen under the reader's thumb.
        .overlay(alignment: .top) { syncHairline }
        .animation(OnyxMotion.fade, value: environment.sync.phase)
        .refreshable {
            await environment.syncNow(reason: .pull)
            model.refresh()
            pulls += 1
        }
        // §3.4 gives sync TWO haptics, and a pull that failed must not feel like
        // one that worked. The phase is read at the moment the pull lands.
        .sensoryFeedback(trigger: pulls) { _, _ in
            if case .failed = environment.sync.phase { return .error }
            return .success
        }
        .navigationTitle("Onyx")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    HistoryView()
                } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("History")
            }
            ToolbarItem(placement: .primaryAction) {
                if model.editing {
                    Button("Done") {
                        withAnimation(OnyxMotion.flick) { model.editing = false }
                    }
                    .fontWeight(.bold)
                } else {
                    // ── THE MARK IS THE CONTROL NOW (decision 5) ────────────
                    // It was decoration — `.accessibilityHidden`, the
                    // wordmark's other half — sitting on the most reachable
                    // point of the busiest screen in the app and doing nothing,
                    // while the six readings behind it were three or four taps
                    // away on other tabs. "Done" still owns this slot in edit
                    // mode: one control that both ends the jiggle and opens a
                    // logger is a control you cannot tap in either state
                    // without meaning the other.
                    Button {
                        if quickLog == nil {
                            quickLog = DayModel(database: environment.database, userId: environment.userIdString)
                        }
                        showQuickLog = true
                    } label: {
                        OnyxMark(size: 18, opacity: 1)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quick Log")
                    .accessibilityHint("Log water, a weigh-in, fatigue, head, cardio or a note")
                }
            }
        }
        .sheet(item: $model.sheet) { which in
            switch which {
            case .tile(let id):
                DomainSheet(
                    id: id, entry: model.entry,
                    muscleFocus: model.feed?.muscleFocus,
                    onStartWorkout: onOpenTrain
                )
            case .stack(let slotId): StackEditSheet(slotId: slotId, model: model)
            case .session(let sessionId):
                NavigationStack { SessionDetailView(sessionId: sessionId) }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showQuickLog) {
            if let quickLog { QuickLogSheet(model: quickLog) }
        }
        // The ring's sheets read STREAMED state — the day's fatigue rows, its
        // stress readings, its cardio — and a model nobody observes draws every
        // one of them as "not rated" over a day that has them.
        .task(id: quickLog.map(ObjectIdentifier.init)) { await quickLog?.observe() }
        .onChange(of: scenePhase) { _, phase in
            model.isActive = phase == .active
            if phase == .active {
                model.refresh()
                // Across midnight the ring's model is still pointed at
                // yesterday, and the sheet has six writers on it.
                quickLog?.refreshToday()
                quickLog?.select(LogicalDay.today())
            }
        }
    }

    /// 1 pt of Lunar while a sync runs, and nothing at all when one is not.
    /// A track that is always drawn is a progress bar claiming to be at zero.
    @ViewBuilder
    private var syncHairline: some View {
        if environment.sync.phase == .running {
            Rectangle()
                .fill(OnyxDomain.recover.ramp)
                .frame(height: 1)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    /// Three states for the Workout tile, every one about today: a training day
    /// still to do opens the logger, a LOGGED one opens that session's own page,
    /// and a rest day opens the domain sheet.
    ///
    /// The middle case is new. It used to fall through to the sheet, which drew
    /// the Large face — and the bottom half of that face is a seven-day list,
    /// so a tile reporting today's session opened a page about the other six
    /// days. The session you just finished has a page of its own.
    ///
    /// It falls back to the sheet when no session id resolves, which is the
    /// honest answer for a day the mirror says is logged and the local store has
    /// no row for — a state a pull can be in for a second or two.
    private func open(_ id: WidgetId, _ model: TodayModel) {
        guard id == .train, let w = model.feed?.snapshot.workout, !w.isRestDay else {
            model.sheet = .tile(id)
            return
        }
        if !w.logged { onOpenTrain(); return }
        model.sheet = model.todaySessionId.map { .session($0) } ?? .tile(id)
    }
}
