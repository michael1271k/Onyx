import OnyxCore
import OnyxData
import OnyxUI
import SwiftUI

/// The two screens this app can push.
///
/// Value-based rather than closure-based links, since W3: a `NavigationPath`
/// can only present what it can NAME, and the shot loop needs to put the deck
/// on screen without a finger. Two cases, so it is an enum and not a protocol.
enum WatchRoute: Hashable {
    case deck
    case dashboard
    #if DEBUG
    /// The live-workout widget faces, at their real sizes (W4). DEBUG only:
    /// it is a harness screen, reached by `ONYX_WATCH_SCREEN=widget` and by
    /// nothing a finger can do — see `LiveWidgetPreview` for why the Smart
    /// Stack itself cannot be photographed on a simulator.
    case widgetPreview
    #endif
}

/// What the app opens on.
///
/// ── THE SET DURING A WORKOUT, THE DASHBOARD OUTSIDE ONE (W2) ────────────────
/// This header used to read "IT IS THE SET, NOT A DASHBOARD", and it argued
/// that "every screen that is not the set in front of you is a tap on the way
/// to the set in front of you". Half of that is still true and the half that
/// was wrong cost the app its front door.
///
/// DURING a session it holds completely: a wrist raised between two sets wants
/// the set, and a live session still opens straight into `SetView`. OUTSIDE
/// one there is no set in front of you, and what this app actually opened on
/// was the word "Rest day" in the middle of an empty screen, with everything
/// the phone knows about you hidden behind a toolbar disc. That is not a lean
/// root; it is a dead end.
///
/// So the dashboard moved up a level and is the idle root (founder decision 2,
/// and a deliberate reversal of W3's decision rather than a drift away from
/// it). Its first page is the Start screen, so the one tap that used to be the
/// whole root is still the first thing under a thumb — and readiness, sleep,
/// stress, the week and the day's fuel are a Crown turn away instead of a tap
/// and a push away.
///
/// The pushed `.dashboard` route survives for exactly one caller now:
/// `DeckView`'s toolbar, during a session, where the Start page has nothing to
/// offer and is left out.
struct RootView: View {

    @Environment(WatchModel.self) private var model

    /// The stack's path, so the shot loop can put the deck on screen.
    ///
    /// Empty in every shipping state — nothing but `ONYX_WATCH_SCREEN=deck`
    /// ever writes it, and the deck is still reached by its toolbar link. A
    /// path is the only way to present a pushed screen without a tap, and the
    /// alternative was photographing `DeckView` outside the stack it lives in.
    @State private var path: [WatchRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.storeError != nil {
                    StoreErrorView()
                } else if model.sessionId != nil {
                    SetView()
                } else {
                    DashboardView()
                }
            }
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .deck: DeckView()
                // Pushed only from `DeckView`, mid-session — so without the
                // Start page, which cannot start anything from in here.
                case .dashboard: DashboardView(showsStart: false)
                #if DEBUG
                case .widgetPreview: LiveWidgetPreview()
                #endif
                }
            }
        }
        #if DEBUG
        // ── `onChange`, NOT `onAppear` ──────────────────────────────────────
        // `onAppear` fires when this view appears, and the seeding runs in the
        // `.task` attached one level up — which starts AFTER. So `onAppear`
        // read a nil `debugScreen` every time and the deck shot came back as
        // the set screen: a real screen, under the wrong filename, which is
        // the one failure `watch-shot.sh` exists to refuse.
        .onChange(of: model.debugScreen, initial: true) { _, screen in
            if screen == .deck, path.isEmpty { path = [.deck] }
            // W4's `dashboard`/`train`/`fuel` used to push `.dashboard` here.
            // They do not any more: the dashboard IS this root, so a push
            // would photograph a second copy of it ON TOP of itself, complete
            // with a back chevron no shipping state has. `DashboardView`
            // reads the same value and moves its own `TabView`.
            if screen == .widget, path.isEmpty { path = [.widgetPreview] }
        }
        #endif
        // ── REST IS A STATE, NOT A PAGE ─────────────────────────────────────
        // A cover rather than a tab, because rest is not somewhere you can
        // usefully navigate TO — it is a thing that is happening to you, and it
        // ends on its own. Presenting it this way is also what lets it dismiss
        // itself at zero, which is what makes "not rated" the outcome of doing
        // nothing.
        .fullScreenCover(item: Binding(get: { model.rest }, set: { if $0 == nil { model.stopRest() } })) { pulse in
            // ── THE COVER NEEDS ITS OWN STACK, AND THAT IS NOT DECORATION ────
            // The `NavigationStack` above wraps the ROOT, not the cover, so a
            // `.toolbar` inside `RestView` had nothing to attach to and drew
            // nothing at all — no warning, no diagnostic, just a missing timer.
            // The rest screen carries the session clock in the same corner
            // `SetView` does, and it has to be the same corner on both or the
            // reading appears and disappears as rest starts and ends, which
            // reads as a glitch rather than as a state.
            NavigationStack { RestView(pulse: pulse) }
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// How long this session has been running, for the top-right of both screens.
///
/// ── WHY IT IS `h:mm` AND NOT A COUNTDOWN TEXT ───────────────────────────────
/// `Text(_:style:.timer)` and `Text(timerInterval:)` are ticked by the system,
/// which is exactly what a wrist wants — but both print seconds and neither can
/// be told not to. The 40 mm bar is 162 pt and `SetView` has already spent it:
/// "Set 1 of 4" takes ~62 and the deck link ~20, leaving about 50. "44:32" fits
/// that; "1:04:32" does not, and a six-hour session is a real reading in this
/// app's own history. A bar that re-lays itself out at the hour mark, mid-set,
/// is the layout this device punishes hardest.
///
/// So: hours and minutes, four characters, one redraw a minute — which is what
/// the always-on state wants anyway. The seconds are on the phone's hero at
/// 34 pt for anyone who wants them.
///
/// ── AND WHY IT DIMS ITSELF ──────────────────────────────────────────────────
/// A toolbar item is not inside the content that `.dimmedWhenLuminanceReduced`
/// is applied to, so without its own call this is a small, static, tinted
/// string held in one fixed corner at full brightness for an hour — the
/// textbook burn-in case on an OLED panel.
struct WatchSessionTimer: View {

    @Environment(WatchModel.self) private var model

    var body: some View {
        if model.sessionStartedAt != nil || model.remoteOrigin != nil {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let clock = model.clock(at: context.date)
                HStack(spacing: 2) {
                    // ── THE GLYPH, NOT A SECOND COLOUR (W3) ─────────────────
                    // A paused clock that only DIMS is a clock you read as a
                    // clock. `WatchInk` has two ink levels on purpose, so the
                    // state is a mark: the pause bars, 8 pt, ahead of the
                    // digits, which is where the eye already is.
                    if clock?.isPaused == true {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 8))
                            .accessibilityHidden(true)
                    }
                    Text(
                        Duration.seconds(max(0, context.date.timeIntervalSince(clock?.origin ?? context.date)))
                            .formatted(.time(pattern: .hourMinute))
                    )
                    // Required, and not for the usual reason: a proportional
                    // string in a toolbar re-measures the bar on every tick,
                    // which re-lays the title beside it, forever.
                    .monospacedDigit()
                }
                .font(WatchType.label)
                // 36 and not 44: `h:mm` is four characters and monospaced, so
                // the box only grows at ten hours. The 44 it started at was
                // enough of the 40 mm bar to truncate `SetView`'s title.
                .frame(minWidth: 36, alignment: .trailing)
                .foregroundStyle(WatchInk.day(model.day?.key))
                .dimmedWhenLuminanceReduced()
                .accessibilityLabel("Total workout time")
                .accessibilityValue(clock?.isPaused == true ? "paused" : "")
            }
        }
    }
}

/// Page one of the dashboard: today's split, and the one button that starts it.
///
/// ── IT IS A PAGE NOW, NOT THE ROOT ──────────────────────────────────────────
/// Everything this screen used to own that was CHROME — the container
/// background, the navigation title, the toolbar disc that led to the
/// dashboard — belongs to `DashboardView` now, because a page inside a
/// `TabView` that set its own title would fight the pager for it. What is left
/// is what this screen was always about: what today is, and starting it.
///
/// ── THE HERO, AND WHY THE SPLIT IS THE BIG THING ────────────────────────────
/// It was `WatchType.value` (`.title3`) over a caption, which on a 49 mm case
/// is a line of text floating in the top third of a black rectangle — the
/// founder's "tiny icon and nothing else". The split is the one thing this page
/// is about, so it takes `WatchType.figure` and the day's own colour, the same
/// tint that session wears on the phone, in the deck and in the session timer.
///
/// ── AND A REST DAY IS NO LONGER A DEAD END ──────────────────────────────────
/// "Rest day" on its own was the whole screen, and it answered a question
/// nobody asks a watch. A rest day is exactly when readiness is worth reading,
/// so the score becomes the hero and the stat row carries battery and sleep
/// beneath it. The three pages behind this one carry the rest, on a rest day
/// like any other.
struct StartView: View {

    @Environment(WatchModel.self) private var model

    /// ── START, JOIN, OR TODAY'S BANNER (overhaul A1, decisions Q1 + Q3) ────
    /// This page drew "Start" whenever there was a day, and ignored whether
    /// today's session had already closed — the founder's "the watch offers
    /// Start after the phone finished". The phone's lifecycle picks now
    /// (`WatchModel.frontDoor`): finished today is the banner, a session the
    /// phone is logging that this wrist has not followed is Join, and only
    /// nothing at all is Start.
    var body: some View {
        switch model.frontDoor {
        case .banner(let summary):
            SessionBannerView(summary: summary)
        case .start, .join:
            startPage
        }
    }

    /// The phone's live session this wrist can follow, if that is the door.
    private var joining: SessionLifecycle? {
        if case .join(let word) = model.frontDoor { return word }
        return nil
    }

    private var startPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                if let day = model.day {
                    Text(day.label)
                        .font(WatchType.figure)
                        .foregroundStyle(WatchInk.day(day.key))
                        .lineLimit(2)
                        // The longest split this plan has ever named is
                        // "Delts & Arms"; `minimumScaleFactor` is for the one
                        // a later block invents, because a truncated split is
                        // a split you cannot identify.
                        .minimumScaleFactor(0.8)
                    if let joining {
                        // Where the session is, and how long it has run —
                        // ticked by the system, one redraw a minute, the
                        // same `h:mm` the session timer uses. It takes the
                        // stat row's place rather than joining it: the 49 mm
                        // shot with both put the readings under the Join
                        // capsule, and a live session is not the moment for
                        // battery and readiness.
                        TimelineView(.periodic(from: .now, by: 60)) { tick in
                            Label {
                                Text("Live on iPhone · "
                                     + Duration.seconds(max(0, tick.date.timeIntervalSince(joining.startedAt)))
                                        .formatted(.time(pattern: .hourMinute)))
                                    .monospacedDigit()
                            } icon: {
                                Image(systemName: "iphone")
                            }
                            .font(WatchType.label)
                            .foregroundStyle(WatchInk.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        }
                    } else {
                        HeroStats(
                            tiles: model.dashboardTiles,
                            movements: day.exercises(for: model.phase).count
                        )
                    }
                } else if model.context == nil {
                    // The honest empty state. The watch cannot sign in — by
                    // design, Wave 10 — so the only way it learns who you are
                    // and what today is, is the phone's application context.
                    Text("Open Onyx on your iPhone")
                        .font(WatchType.name)
                        .foregroundStyle(WatchInk.primary)
                        .lineLimit(3)
                    Text("It sends this watch your plan.")
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.secondary)
                        .lineLimit(2)
                } else {
                    Text("Rest day")
                        .font(WatchType.name)
                        .foregroundStyle(OnyxDomain.recover.accent)
                    // The score is the hero on a day with nothing to lift, so
                    // the stat row below drops it rather than printing it
                    // twice.
                    let score = model.dashboardTiles?.score
                    // ── THE HERO AND ITS CAPTION ARE ONE READING ────────────
                    // Drawn as two `Text`s and spoken as one. VoiceOver read
                    // them separately — "81", then "Readiness" — which is a
                    // bare number, or a bare "—", ahead of the word that says
                    // what it scores. Every other figure on this page is a
                    // labelled `stat()`; the group makes the hero one too.
                    VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                        Text(score.map { "\($0)" } ?? "—")
                            .font(WatchType.hero)
                            .foregroundStyle(WatchInk.primary)
                            .monospacedDigit()
                        // W6: a verdict the watch was off the wrist for says
                        // how many of its five signals it had.
                        let offWrist = model.dashboardTiles?.offWrist
                        Text(offWrist.map { "Readiness · \($0.signalsText)" } ?? "Readiness")
                            .font(WatchType.label)
                            .foregroundStyle(WatchInk.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Readiness")
                    .accessibilityValue((score.map { "\($0)" } ?? "not scored yet")
                                        + (model.dashboardTiles?.offWrist.map { ". \($0.sentence)" } ?? ""))
                    HeroStats(tiles: model.dashboardTiles, showsScore: false, showsSleep: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, OnyxSpace.xs)
        }
        .safeAreaInset(edge: .bottom) {
            if model.day != nil {
                Button {
                    if joining != nil { model.joinSession() } else { model.beginSession() }
                } label: {
                    Label(joining == nil ? "Start" : "Join", systemImage: joining == nil ? "play.fill" : "arrow.right.circle.fill")
                        .font(WatchType.value)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchInk.commit)
                .foregroundStyle(WatchInk.onCommit)
                .handGestureShortcut(.primaryAction)
            }
        }
        .dimmedWhenLuminanceReduced()
    }
}

/// The three readings that answer "should I train today", in one row.
///
/// ── GLYPH AND NUMBER, NO WORDS ──────────────────────────────────────────────
/// "3 movements · Battery 72% · Readiness 81" is 40 characters, and 40
/// characters of `caption2` is about 260 pt against the 146 this page has at
/// 40 mm. A glyph carries the word for a third of the width, and every glyph
/// here is the one the face one Crown turn away already uses for the same
/// reading — `bolt.fill` is Battery on the Today page and on the complication,
/// `dumbbell.fill` is the split on the Train page and on the watch face.
///
/// ── WHY THE MOVEMENT COUNT IS A CHIP AND NOT ITS OWN LINE ───────────────────
/// Measured, not preferred. As a `Text` row it was 21 pt tall with a 4 pt gap
/// above it, and the 49 mm accessibility tree put the stat row at y=145.5–166.5
/// against a scroll viewport that ends at y=158 where the Start capsule begins:
/// the row overlapped the button by 8.5 pt, and at 40 mm it would have been
/// worse. Folding the count into this row buys back 25 pt and the page fits
/// both cases with room. A `ScrollView` would have "fixed" it by hiding the
/// readings below a fold on the screen the app opens on.
///
/// ── AND WHY SLEEP IS NOT ON A TRAINING DAY ──────────────────────────────────
/// Width, measured on both cases. Battery + readiness + SLEEP was 160.5 pt at
/// 49 mm, against the 146 a 40 mm case has (`WatchCase.content40mm`) — so the
/// sleep chip was the one that could not stay once the movement count joined
/// the row. What ships measures **121 pt of 146** on the 40 mm case itself
/// (movements at x=3.5, readiness ending at x=124.5), with 25 pt spare and no
/// figure tightened.
///
/// On a training day sleep is one Crown turn away on the Today page; on a REST
/// day the readiness score is the hero, so the score chip goes and sleep takes
/// its place — which is the reading a rest day is actually read for.
///
/// ── THE COLOUR IS ON THE GLYPH, NOT THE NUMBER ──────────────────────────────
/// `Color.onyx.battery` is a reading, not a decoration: it goes red as the
/// charge goes. Putting it on the number would make the number harder to read
/// at the exact moment it matters most, so the glyph carries the colour and the
/// figure stays full-contrast ink.
private struct HeroStats: View {

    let tiles: WatchTiles?
    /// Today's movement count, when there is a deck. Leads the row.
    var movements: Int?
    var showsScore = true
    var showsSleep = false

    var body: some View {
        HStack(spacing: OnyxSpace.s) {
            if let movements {
                stat("dumbbell.fill", "\(movements)", WatchInk.secondary, "Movements")
            }
            if let battery = tiles?.battery {
                stat("bolt.fill", "\(battery)%", Color.onyx.battery(battery), "Battery")
            }
            if showsScore, let score = tiles?.score {
                stat("gauge.medium", "\(score)", OnyxDomain.recover.accent, "Readiness")
            }
            if showsSleep, let minutes = tiles?.sleepMin {
                stat(
                    "moon.fill", OnyxSnapshot.formatSleep(minutes),
                    OnyxDomain.recover.accent, "Slept"
                )
            }
        }
        .padding(.top, 2)
    }

    private func stat(_ glyph: String, _ value: String, _ tint: Color, _ label: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: glyph)
                .font(WatchType.label)
                .foregroundStyle(tint)
            Text(value)
                .font(WatchType.label)
                .foregroundStyle(WatchInk.primary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// The phone holds the pencil.
///
/// ── ONE WRITER, AND THE OTHER ONE WATCHES ───────────────────────────────────
/// The event log tolerates two devices writing at once — `SetEventFold` is why
/// nothing can be lost — so this is not a correctness mechanism. It is a user
/// experience one: without it you log set 4 on the watch, glance at a phone
/// showing a stale list, log set 4 again, and spend the middle of your workout
/// cleaning up. With it exactly one device offers a keyboard.
///
/// The button is the whole escape hatch, and it always works: `claimPencil(force:
/// true)` is the deliberate takeover that `ingestOwnership` lets through even
/// when the other device is mid-set, because somebody pressed it.
struct MirrorView: View {

    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Text("iPhone is logging")
                    .font(WatchType.name)
                    .foregroundStyle(WatchInk.primary)
                    .lineLimit(2)
                Text("\(model.sets.count) sets so far")
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Log here") { model.takePencil() }
                .font(WatchType.value)
                .buttonStyle(.borderedProminent)
                .tint(WatchInk.commit)
                .foregroundStyle(WatchInk.onCommit)
        }
        // ── THE BURN-IN CALL THIS SCREEN NEVER MADE (W2) ────────────────────
        // `SetView` applies `dimmedWhenLuminanceReduced` to `logger(_:model:)`
        // and to nothing else, so this screen and `FinishView` beside it held
        // a full-width `WatchInk.commit` capsule at FULL brightness for as
        // long as a wrist was down — the exact case `WatchInk`'s own header
        // names ("any large area of accent"), on the two live-session screens
        // that are held longest. Applied after the inset so it reaches the
        // button, which is the part that was lit.
        .dimmedWhenLuminanceReduced()
    }
}

/// Every planned set is in. The tick becomes a finish button.
struct FinishView: View {

    @Environment(WatchModel.self) private var model
    @State private var isFinishing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Text("Deck complete")
                    .font(WatchType.value)
                    .foregroundStyle(WatchInk.primary)
                Text("\(model.sets.count) sets")
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.secondary)
                if let bpm = model.workout.averageHeartRate {
                    Text("\(bpm) bpm average")
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.secondary)
                }
                // The other place a refused write is reported — see
                // `DeckView`. A finish that did not take leaves the button on
                // screen, and this says why.
                if let problem = model.writeError {
                    Text(problem)
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.danger)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                isFinishing = true
                Task {
                    await model.finish()
                    isFinishing = false
                }
            } label: {
                Label("Finish", systemImage: "flag.checkered")
                    .font(WatchType.value)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchInk.commit)
            .foregroundStyle(WatchInk.onCommit)
            .disabled(isFinishing)
        }
        // See `MirrorView` — the same call, for the same lit capsule.
        .dimmedWhenLuminanceReduced()
    }
}

/// The store would not open. Rare, and not something a person under a bar can
/// act on — so it says what happened and nothing else.
struct StoreErrorView: View {

    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Text("Store unavailable")
                    .font(WatchType.name)
                    .foregroundStyle(WatchInk.danger)
                Text(model.storeError ?? "")
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
