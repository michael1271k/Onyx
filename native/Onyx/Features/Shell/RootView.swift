import SwiftUI
import UIKit
import OnyxCore
import OnyxData
import OnyxUI

/// The app shell.
///
/// ── THE SYSTEM CONTAINERS ARE THE POINT ─────────────────────────────────────
/// A `TabView` of `NavigationStack`s, and nothing custom around them. That one
/// choice deletes, outright, four pieces of the web app that exist only to
/// imitate it:
///
///   · `lib/nav/useEdgeSwipeBack.ts` (227 loc) — a hand-rolled back gesture on
///     raw touch events, with its own projection and rubber-banding physics,
///     written because WKWebView cannot swipe a `pushState` navigation;
///   · `lib/nav/scrollMemory.ts` (171 loc) — per-route scroll restoration,
///     written because App Router remounts the subtree on every navigation;
///   · `nav/BottomNav.tsx` + `Sidebar.tsx` (404 loc) — a `layoutId` tab
///     indicator;
///   · `ui/PullToRefresh.tsx` (301 loc) — replaced below by `.refreshable`.
///
/// None of that is ported. `NavigationStack` gives the interactive back-edge
/// swipe, `TabView` gives scroll restoration and scroll-to-top on re-tap, and
/// both are Apple's, so they match every other app on the device.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        switch environment.auth {
        case .resolving:
            ProgressView().controlSize(.large)
        case .signedOut:
            SignInView()
        case .signedIn:
            SignedInTabs()
        }
    }
}

/// Not `private`: `PreviewHarness` renders this directly for the `tabs-*`
/// shots. `RootView` gates on `auth` and a preview environment is never signed
/// in, so photographing the tab bar through the real root would mean seeding a
/// session — a Keychain read and a Supabase client in the screenshot loop, for
/// a picture of five icons.
struct SignedInTabs: View {
    enum Tab: String, Hashable { case today, train, fuel, body, you }

    @Environment(AppEnvironment.self) private var environment
    /// Held on `AppEnvironment` rather than here — see `selectedTab` there.
    /// `@State` would be discarded by the theme rebuild, which is how a colour
    /// change used to dump the user on the dashboard.
    private var selection: Binding<Tab> {
        Binding(
            get: { Tab(rawValue: environment.selectedTab) ?? Self.initialTab },
            set: { environment.selectedTab = $0.rawValue }
        )
    }
    /// 0…1. The mesh behind every screen dims with it (§W5.2).
    @State private var battery: Double = 1

    /// `ONYX_START_TAB=nutrition` (DEBUG launch environment): open on a tab,
    /// for a gate that watches one tab react to a server change. A deep link
    /// from `simctl openurl` puts an "Open in Onyx?" alert over the screen
    /// that nothing can tap; a launch argument does not.
    private static var initialTab: Tab {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["ONYX_START_TAB"],
           let destination = DeepLink.destination(forPath: name) {
            return tab(for: destination)
        }
        #endif
        return .today
    }

    var body: some View {
        TabView(selection: selection) {
            SwiftUI.Tab("Today", systemImage: "square.grid.2x2", value: Tab.today) {
                NavigationStack {
                    TodayTabView(
                        onOpenTrain: { selection.wrappedValue = .train },
                        onOpenPulse: { selection.wrappedValue = .body }
                    )
                }
            }
            // Onyx's five: Today · Workout · Nutrition · Pulse · Settings
            // (§4). The names are the ones on the screens they open, which is
            // the rule that matters and the reason this tab and
            // `WorkoutTabView.navigationTitle` always move together.
            //
            // "Train" since 2026-09-07, on the founder's call. It had been
            // "Workout" because "Train" was the web app's word and read as
            // borrowed; the tab and its screen were renamed in the same commit,
            // so the tab still says exactly what the screen it opens says.
            // `Tab.train` was already the case name. The logger is NOT the
            // Train root — see `WorkoutTabView` for why.
            SwiftUI.Tab("Train", systemImage: "figure.strengthtraining.traditional", value: Tab.train) {
                NavigationStack { WorkoutTabView() }
            }
            SwiftUI.Tab("Nutrition", systemImage: "fork.knife", value: Tab.fuel) {
                NavigationStack { NutritionTabView() }
            }
            SwiftUI.Tab("Pulse", systemImage: "waveform.path.ecg", value: Tab.body) {
                NavigationStack { PulseTabView() }
            }
            SwiftUI.Tab("Settings", systemImage: "gearshape", value: Tab.you) {
                NavigationStack { SettingsTabView() }
            }
        }
        .environment(\.onyxBatteryLevel, battery)
        // ── THE TAB BAR LEARNS WHICH TAB IT IS ON ───────────────────────────
        // §4 decision 4: the selected tab icon adopts the domain tint. Every
        // screen already stands on `onyxScreen(domain)`, so the ground under
        // Train is Ion and the ground under Nutrition is Solar — and the bar
        // over both was the one piece of chrome that never got the message.
        //
        // ── WHY IT IS ONE MODIFIER HERE AND NOT FIVE ON THE TABS ────────────
        // The obvious spelling is `.tint()` on each `SwiftUI.Tab`. It does not
        // exist: `Tab` is a `TabContent`, not a `View`, and the modifiers
        // SwiftUI declares on `TabContent` are `badge`, `hidden`, `disabled`,
        // `tabPlacement`, `customizationBehavior`, the accessibility set and
        // the gesture set — no `tint`. Applying it to the CONTENT inside a tab
        // tints that screen's controls and never reaches the bar item, which
        // is the half that matters here.
        //
        // A tab bar only ever colours its SELECTED item, so one tint driven by
        // the selection says exactly what five would have: the bar is Ion on
        // Train and Solar on Nutrition, and it changes on the tap.
        //
        // `nil` restores the system tint, which is what Settings gets.
        .tint(Self.domain(for: selection.wrappedValue)?.accent)
        // ── A WORKOUT IN PROGRESS OUTRANKS THE DASHBOARD ────────────────────
        // `selectedTab` is in-memory (see `AppEnvironment`) — deliberately, so
        // a theme rebuild cannot evict the reader — which also means it is
        // EMPTY on every cold launch and `initialTab` answers `.today`. So an
        // app terminated three sets from the end of a workout came back on the
        // dashboard, and the deck it was still holding had to be gone looking
        // for. The state survived the kill; the way back to it did not.
        //
        // Empty and only empty: the moment the reader has chosen a tab in this
        // process this does nothing, so it cannot fight a deliberate tap, and a
        // deep link (`onOpenURL`) writes `selectedTab` before this runs.
        // `liveWorkoutInProgress` is the same test the Train tab's own footer
        // uses to decide whether to say "Resume workout".
        .task {
            guard environment.selectedTab.isEmpty,
                  (try? environment.database.liveWorkoutInProgress(date: LogicalDay.today())) == true
            else { return }
            selection.wrappedValue = .train
        }
        // The battery the backgrounds read. Monitoring is off by default and
        // costs nothing to enable; an unknown level reads −1, which is the one
        // value that must NOT become a dimmed screen — a simulator, a preview
        // and a device that has not answered yet all report it.
        .task {
            UIDevice.current.isBatteryMonitoringEnabled = true
            battery = Self.batteryLevel
            for await _ in NotificationCenter.default.notifications(named: UIDevice.batteryLevelDidChangeNotification) {
                battery = Self.batteryLevel
            }
        }
        // `onyx://open?path=…` from a widget or the Lock Screen card. The
        // allow-list runs first; an unknown path is ignored, not "home".
        .onOpenURL { url in
            guard let path = DeepLink.safePath(url.absoluteString),
                  let destination = DeepLink.destination(forPath: path) else { return }
            selection.wrappedValue = Self.tab(for: destination)
        }
        // The first-launch backfill (§7.2). A cover, not a replacement of the
        // tabs: they mount underneath, observe the store, and are already
        // showing March by the time the cover lifts.
        .fullScreenCover(isPresented: Binding(get: { environment.backfill != nil }, set: { _ in })) {
            if let model = environment.backfill { BackfillSheet(model: model) }
        }
        // Setting up a brand-new account (W5). A cover for the same reasons the
        // backfill is one — the tabs mount underneath and observe the store, so
        // by the time the last step's write commits they are already showing the
        // plan it wrote.
        //
        // It is offered strictly after a pull that LANDED
        // (`offerOnboardingIfNeeded`), because "has this account been set up" is
        // a question about rows and on a fresh install the rows have not
        // arrived yet.
        //
        // ── AND ONLY WHEN THE BACKFILL IS DOWN ──────────────────────────────
        // Two covers on one view is a race SwiftUI resolves by dropping one,
        // and the backfill's FAILURE path leaves its model in place — so
        // without this condition a failed first sync could bury its own Retry
        // button under a flow that cannot be dismissed.
        .fullScreenCover(
            isPresented: Binding(
                get: { environment.onboarding != nil && environment.backfill == nil },
                set: { _ in }
            )
        ) {
            if let model = environment.onboarding { OnboardingFlow(model: model) }
        }
    }

    private static var batteryLevel: Double {
        let raw = Double(UIDevice.current.batteryLevel)
        return raw < 0 ? 1 : min(max(raw, 0), 1)
    }

    /// The domain a tab belongs to, or `nil` for the one that belongs to none.
    ///
    /// Settings is deliberately absent. It is not a Recover screen with a
    /// different title — it is where you go to change the app, and painting it
    /// a domain's colour would say the tab is ABOUT that domain. The same
    /// argument `OnyxScreenBackground` already makes for its `nil` ground, and
    /// `SettingsTabView` takes `onyxFormBackground()` with no domain for it.
    ///
    /// Pulse takes `.body` rather than a literal red. Every hue in this app is
    /// derived from the user's two theme colours by OKLCH rotation
    /// (`OnyxTheme.init`), so a hardcoded red would be the one colour on the
    /// screen that goes stale the moment they change Primary — and
    /// `TokenDisciplineTests` would not even catch it, because `.red` is a
    /// system colour and not a spelled-out hex.
    private static func domain(for tab: Tab) -> OnyxDomain? {
        switch tab {
        case .today: return .recover
        case .train: return .train
        case .fuel:  return .fuel
        case .body:  return .body
        case .you:   return nil
        }
    }

    private static func tab(for destination: DeepLink.Destination) -> Tab {
        switch destination {
        case .today: return .today
        case .train: return .train
        case .fuel: return .fuel
        // ponytail: the date is dropped — PulseTabView has no date initialiser yet; thread it through when Body grows a date route.
        case .body: return .body
        // ponytail: Reports is a value-less NavigationLink inside SettingsTabView; landing on You is as deep as the shell can push today.
        case .you, .reports: return .you
        }
    }
}
