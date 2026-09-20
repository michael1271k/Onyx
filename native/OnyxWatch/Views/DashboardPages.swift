import OnyxCore
import OnyxUI
import SwiftUI
import WatchKit

// MARK: - Today / Train / Fuel (W4, founder decision 2)
//
// ── IT DRAWS THE COMPLICATION FACES, AND THAT IS THE WHOLE DESIGN ───────────
// W7's `DashboardView` was four rows of `label: value` text, and its own
// comment defended that: "OnyxUI's tiles are fenced `#if os(iOS)` … at 40 mm
// the honest version of a dashboard is four rows of text." Half of that was
// true and has stopped being true. The Home Screen TILES are still iOS-only —
// they switch on `WidgetFamily` cases that do not exist here — but the
// ACCESSORY faces are not: `OnyxTile.accessory` is unfenced, takes the same
// `WatchTiles` this app already holds, and is the same drawing the phone's
// Lock Screen and this watch's own complications make.
//
// So the pages are not a third rendering of the day's numbers. They are the
// faces that were already on this wrist, laid out where you can see three at
// once — which is what a dashboard is, and it is why nothing here composes a
// string.
//
// ── THREE PAGES, THREE FACES, AND WHAT THE THIRD ONE COSTS ──────────────────
// Vertical paging, because the Crown already drives it and decision 5 says
// the Crown stays as it is.
//
// Three faces a page is a DECISION, not a measurement, and the measurement
// disagrees with it: 48.5 pt a row against a 133 pt page leaves the third
// card about 20 pt below the fold at 40 mm (and the Fuel page's button a
// further 58). It fits the 49 mm case this app is worn on with 33 pt spare,
// the page is a `ScrollView`, and the Crown that turns the page reaches the
// rest of it. `WatchDashboard.facesPerPage` is the decision,
// `WatchDashboard.overflow` is the price, and `OnyxWatchLayoutTests` asserts
// both — so dropping to two faces is one constant away if the founder would
// rather have the glance than the third reading.
//
// Every number above was measured off the running app's accessibility tree.
// The first set was estimated, passed its own test, and was wrong by 36 pt
// on the navigation bar alone.

/// Which page is up. `Hashable` for the `TabView` selection, and named rather
/// than indexed so the shot loop can ask for one by name.
enum DashboardPage: String, CaseIterable, Hashable {
    case today, train, fuel

    var title: String {
        switch self {
        case .today: "Today"
        case .train: "Train"
        case .fuel: "Fuel"
        }
    }

    /// The faces this page draws, in reading order.
    ///
    /// ── WHY `.volume` IS HERE AND NOT IN `WidgetId.wearable` ───────────────
    /// `wearable` is the ten ids that get a `StaticConfiguration` in the watch
    /// bundle — a watch FACE. A week's tonnage is not a thing to keep in the
    /// corner of a clock, and it is exactly a thing to see on a page you open
    /// before you start. The two lists came apart here on purpose; see that
    /// property's own note.
    var faces: [WidgetId] {
        switch self {
        // Battery and score are ONE face (`AccessoryReading.recovery` draws
        // the battery as its hero and the readiness score as its second
        // line), which is what leaves room for sleep and stress beside them.
        case .today: [.recovery, .sleep, .stress]
        case .train: [.train, .volume, .weekRings]
        case .fuel: [.fuel, .water, .steps]
        }
    }
}

/// The dashboard. Reached from `StartView`'s toolbar before a session and
/// from `DeckView`'s during one.
struct DashboardView: View {

    @Environment(WatchModel.self) private var model

    @State private var page: DashboardPage = .today

    var body: some View {
        // ── A `TabView`, WHICH `SetView` DELIBERATELY COULD NOT USE ─────────
        // W3's pager is a `ScrollView` with `scrollTargetBehavior(.paging)`
        // and it hand-draws its dots, because that screen needs a Crown bound
        // to a VALUE while it pages. This one does not: the Crown's only job
        // here is the page, which is what `TabView` binds it to natively —
        // system dots, system rubber-banding, no focus contest, no gesture to
        // arbitrate. Using the control that fits is the whole reason the
        // other screen's comment explains why it could not.
        TabView(selection: $page) {
            ForEach(DashboardPage.allCases, id: \.self) { page in
                DashboardPageView(page: page, tiles: model.dashboardTiles)
                    .tag(page)
            }
        }
        .tabViewStyle(.verticalPage)
        .containerBackground(WatchInk.ground, for: .navigation)
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        // The shot loop's hook. `onChange(of:initial:)` and not `onAppear`,
        // for the reason `RootView` records: the seeding runs in a `.task`
        // one level up, which starts AFTER this view appears — so `onAppear`
        // read a nil `debugScreen` every time and photographed page one under
        // every filename.
        .onChange(of: model.debugScreen, initial: true) { _, screen in
            switch screen {
            case .train: page = .train
            case .fuel: page = .fuel
            default: break
            }
        }
        #endif
    }
}

/// One page: up to three accessory faces, and whatever that page can DO.
private struct DashboardPageView: View {

    let page: DashboardPage
    let tiles: WatchTiles?

    var body: some View {
        ScrollView {
            VStack(spacing: OnyxSpace.xs) {
                // ── THE PAGE TAKES ITS ROW COUNT FROM OnyxCore ──────────────
                // `prefix` and not a hand-written three: the cap is
                // `WatchDashboard.facesPerPage`, the test replays the
                // arithmetic behind it, and a page that grew a fourth face
                // would be caught there rather than by a 49 mm screenshot
                // that cannot see the bottom of a 40 mm display.
                ForEach(page.faces.prefix(WatchDashboard.facesPerPage), id: \.self) { id in
                    DashboardCard { OnyxTile.accessory(id, family: .accessoryRectangular, tiles: tiles) }
                }
                if page == .fuel { WaterGlassButton() }
            }
            .padding(.horizontal, OnyxSpace.xs)
        }
        // A page of static readings held at full brightness for the length of
        // a workout is the textbook burn-in case — the same call
        // `WatchSessionTimer` makes about a four-character clock.
        .dimmedWhenLuminanceReduced()
    }
}

#if DEBUG
/// The two live-workout widget faces, at their real sizes, so they can be
/// photographed (W4).
///
/// ── WHY A SCREEN AND NOT A SCREENSHOT OF THE SMART STACK ────────────────────
/// The Smart Stack ranks by relevance, and relevance on a simulator is the
/// system's own judgement about a `HKWorkoutSession` there is no heart to
/// drive. Waiting for the card to rise is waiting on something outside this
/// repository; `simctl` cannot force it, and `xcrun simctl io screenshot` of
/// a stack that did not surface it is the "plausible photograph of the wrong
/// screen" `watch-shot.sh` exists to refuse.
///
/// So this draws the face the extension draws, from the snapshot the
/// extension reads, in the app that writes it — every part of the path except
/// the system's ranking. That is what a harness is for, and the summary says
/// so plainly rather than claiming a Smart Stack shot.
struct LiveWidgetPreview: View {

    /// Read back out of the suite, not composed here: photographing a
    /// literal would prove the FACE draws and say nothing about whether
    /// `publishLiveSnapshot` wrote anything a widget could read.
    private var snapshot: LiveWorkoutSnapshot? { LiveWorkoutSnapshot.load() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                caption("Smart Stack · rectangular")
                // 172 × 43 is the `.accessoryRectangular` box on a 49 mm
                // case. Framed, because a face drawn at whatever width a
                // `VStack` gives it is a face nobody has reviewed.
                DashboardCard { LiveWorkoutFace(snapshot: snapshot, family: .accessoryRectangular) }
                    .frame(width: 172, height: 43)
                caption("Watch face · circular")
                LiveWorkoutFace(snapshot: snapshot, family: .accessoryCircular)
                    .frame(width: 44, height: 44)
                if snapshot == nil {
                    caption("no snapshot in the suite — the idle faces")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(WatchInk.ground, for: .navigation)
        .navigationTitle("Live widget")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(WatchType.label)
            .foregroundStyle(WatchInk.secondary)
    }
}
#endif

/// The card a face sits in. The deck's own row treatment, so a reading here
/// and a movement there are the same object.
private struct DashboardCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OnyxSpace.xs)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                    .fill(WatchInk.fill)
            )
    }
}

/// +1 glass, on the page that shows the water.
///
/// ── IT IS A BUTTON AND NOT A TAP ON THE FACE ────────────────────────────────
/// The face above it is `AccessoryFace`, the same view the complication and
/// the phone's Lock Screen draw, and making it tappable would mean either a
/// gesture on a shared view that must not have one, or a second drawing of
/// the water reading that is allowed to disagree with the first.
///
/// ── AND IT IS FULL WIDTH, UNDER THE FACE, NOT BESIDE IT ─────────────────────
/// 146 pt of content at 40 mm, and the face's own two lines already want most
/// of it. A 44 pt target in the same row would leave the reading ~98 and
/// ellipsise "1750 ml" to "1750…" — which is the failure the whole
/// `WatchPanel` file exists about. A row of its own costs one line and
/// nothing else.
private struct WaterGlassButton: View {

    @Environment(WatchModel.self) private var model

    var body: some View {
        Button {
            // ── THE HAPTIC IS THE QUEUE'S, NOT THE TAP'S ────────────────────
            // `addWaterGlass` answers false when the link could not take the
            // transfer — no counterpart app, or `WCSession` still activating,
            // which is the state for the first moment after launch and this
            // page is two taps from the Start screen. Playing `.click`
            // regardless confirmed a glass that was never queued; `.failure`
            // says what happened without a sheet somebody standing at a rack
            // has to dismiss.
            WKInterfaceDevice.current().play(model.addWaterGlass() ? .click : .failure)
        } label: {
            Label("Add a glass", systemImage: "plus")
                .font(WatchType.label)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        // ── THE WATER COLOUR, NOT THE FUEL DOMAIN'S (W4) ────────────────
        // `OnyxDomain.fuel.accent` is amber, which is the family the eye
        // reads as caution — on the one control on this page, under a
        // droplet, on a row whose own reading is colourless. `Color.onyx
        // .water` is what the phone's own +250 button wears
        // (`OnyxWidgets.AddWaterButton`), so the two devices' water buttons
        // are now the same colour as well as the same code path.
        .tint(Color.onyx.water)
        .accessibilityLabel("Add a glass of water")
        .accessibilityHint("Adds 250 millilitres to today's water on your iPhone")
    }
}
