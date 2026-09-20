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
/// ── IT IS THE SET, NOT A DASHBOARD ──────────────────────────────────────────
/// The first design made a dashboard the root, and that is the phone's
/// information architecture rotated onto a wrist. Nobody raises a wrist mid-gym
/// to read "week so far", and every screen that is not the set in front of you
/// is a tap on the way to the set in front of you. So: a live session opens
/// straight into `SetView`; no live session opens a card that starts today's
/// split in one tap.
///
/// The dashboard is still here — it is one swipe away, in `DashboardView` —
/// because a glance at readiness before you start is a real thing to want. It
/// simply does not stand between you and a barbell.
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
                    StartView()
                }
            }
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .deck: DeckView()
                case .dashboard: DashboardView()
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
            // W4's three, which are one screen with a page selection — the
            // page itself is picked inside `DashboardView`, because the path
            // can name a destination and not a tab within one.
            if screen == .dashboard || screen == .train || screen == .fuel, path.isEmpty {
                path = [.dashboard]
            }
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

/// No session yet.
///
/// One tap starts today's split. The "Change" row exists because a swap is
/// real — the plan moves days — but it is deliberately the second thing on the
/// screen and not a picker you have to get through first.
struct StartView: View {

    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                if let day = model.day {
                    Text(day.label)
                        .font(WatchType.value)
                        .foregroundStyle(WatchInk.primary)
                        .lineLimit(2)
                    Text("\(day.exercises(for: model.phase).count) movements")
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.secondary)
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
                        .font(WatchType.value)
                        .foregroundStyle(WatchInk.primary)
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            if model.day != nil {
                Button {
                    model.beginSession()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(WatchType.value)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchInk.commit)
                .foregroundStyle(WatchInk.onCommit)
                .handGestureShortcut(.primaryAction)
            }
        }
        .containerBackground(WatchInk.ground, for: .navigation)
        .navigationTitle("Onyx")
        // ── THE DASHBOARD IS A TOOLBAR ITEM, NOT A SECOND BUTTON ────────────
        // It was a filled `NavigationLink` under the copy, and the first 40 mm
        // screenshot showed exactly why that was wrong: the pinned Start button
        // sits in the bottom safe-area inset and drew straight over it. Even
        // scrolled clear it was a second capsule competing with the one action
        // this screen exists for.
        //
        // Same treatment as the deck list on `SetView`: a reference lives in the
        // toolbar, and the screen keeps one button.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // A dark disc with a light glyph — see `SetView`'s deck link
                // for why `tint` alone made these near-white.
                NavigationLink(value: WatchRoute.dashboard) { Image(systemName: "chart.bar.fill") }
                    .tint(WatchInk.fill)
                    .foregroundStyle(WatchInk.secondary)
            }
        }
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
