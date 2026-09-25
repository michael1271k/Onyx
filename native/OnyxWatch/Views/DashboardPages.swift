import OnyxCore
import OnyxUI
import SwiftUI
import WatchKit

// MARK: - The wrist's dashboard (overhaul A2, decisions Q4 + concept 4)
//
// ── A GLANCE, THEN THE PHONE'S TABS ─────────────────────────────────────────
// Page one is `GlanceView` — the readiness ring and its six petals (Precision
// D1; each pushes its own detail since D3), no text on
// the first paint but the one number. Then the phone's own tabs, in its order:
// Today, Pulse, Train, Fuel. Train is the old front door (`StartView`: the
// split and Start, Join, or today's banner — A1), because Train is where the
// phone starts a workout too; the Glance's centre opens Pulse and every petal
// pushes its own detail screen.
//
// ── IT DRAWS THE COMPLICATION FACES, AND THAT IS STILL THE DESIGN ───────────
// Today and Pulse are `OnyxTile.accessory` faces — the same unfenced view the
// phone's Lock Screen and this watch's complications draw, fed the same
// `WatchTiles` — now inside `WatchSlab` (16 pt continuous, frost, a one-pixel
// top highlight) instead of the flat tinted card. The Fuel page's food face is
// the one drawing that lives here: a macro bar has no accessory family.
//
// ── ONE INK A PAGE ──────────────────────────────────────────────────────────
// Today → `recover`, Pulse → the theme accent, Fuel → the calories ink. The
// ink is set AROUND the shared face (`WatchSlab`'s hierarchical style), never
// inside it. The inline title stays the system's grey — `.tint` does not reach
// an inline navigation title on watchOS (tested in W4, recorded then).
//
// ── WHAT DID NOT CHANGE ─────────────────────────────────────────────────────
// Vertical paging, three faces a page at most (`WatchDashboard.facesPerPage`,
// replayed in `OnyxWatchLayoutTests`), `.dimmedWhenLuminanceReduced` on every
// static page, and no `.scrollInputBehavior(.disabled, for: .handGestureShortcut)`
// — that modifier kills a scroll view's input entirely on this SDK.

/// Which page is up. `Hashable` for the `TabView` selection, and named rather
/// than indexed so the shot loop can ask for one by name.
enum DashboardPage: String, CaseIterable, Hashable {
    case glance, today, pulse, train, fuel

    var title: String {
        switch self {
        case .glance: "Onyx"
        case .today: "Today"
        case .pulse: "Pulse"
        case .train: "Train"
        case .fuel: "Fuel"
        }
    }

    /// The page's ink, for the slabs. Nil where the page draws no slab.
    var ink: Color? {
        switch self {
        case .glance, .train: nil
        case .today: OnyxDomain.recover.accent
        case .pulse: OnyxInk.Themed.accent
        case .fuel: Color.onyx.calories
        }
    }

    /// The accessory faces this page draws, most-wanted first — the order is
    /// the drop order if the budget ever shrinks.
    ///
    /// Today is the day so far (sleep, steps, the week's marks); Pulse is how
    /// the body is doing (battery + readiness in one face, stress, soreness).
    /// Glance and Train draw no face — theirs is a decision — and Fuel's two
    /// are its own food slab and the water face over the +1 glass button.
    var faces: [WidgetId] {
        switch self {
        case .glance, .train: []
        case .today: [.sleep, .steps, .weekRings]
        case .pulse: [.recovery, .stress, .soreness]
        case .fuel: [.water]
        }
    }
}

/// The dashboard.
///
/// The app's ROOT when no session is live (`RootView`), and still a pushed
/// screen from `DeckView`'s toolbar during one — where the Train page is left
/// out, because offering Start to somebody thirty minutes into today's split
/// is offering a button that cannot do anything.
struct DashboardView: View {

    @Environment(WatchModel.self) private var model

    /// False when this is pushed from inside a live session.
    private let showsStart: Bool

    @State private var page: DashboardPage = .glance

    init(showsStart: Bool = true) {
        self.showsStart = showsStart
    }

    private var pages: [DashboardPage] {
        showsStart ? DashboardPage.allCases : DashboardPage.allCases.filter { $0 != .train }
    }

    var body: some View {
        // ── A `TabView`, WHICH `SetView` DELIBERATELY COULD NOT USE ─────────
        // The Crown pages it natively everywhere but the Glance, whose Crown
        // is the petal highlight (decision Q4) — a swipe pages from there.
        TabView(selection: $page) {
            ForEach(pages, id: \.self) { page in
                Group {
                    switch page {
                    case .glance:
                        // Petals PUSH their detail (D3); only the centre,
                        // with nothing highlighted, turns to a page.
                        GlanceView {
                            if pages.contains(.pulse) { withAnimation { self.page = .pulse } }
                        }
                    case .train:
                        StartView()
                    default:
                        DashboardPageView(page: page, tiles: model.dashboardTiles)
                    }
                }
                .tag(page)
            }
        }
        .tabViewStyle(.verticalPage)
        .containerBackground(for: .navigation) { WatchInk.ground }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        // The shot loop's hook — `onChange(of:initial:)`, not `onAppear`: the
        // seeding runs in a `.task` one level up that starts AFTER this view
        // appears. Clamped to `pages`: a selection matching no tag draws
        // nothing, silently, under a correct filename.
        .onChange(of: model.debugScreen, initial: true) { _, screen in
            let wanted: DashboardPage? = switch screen {
            case .glance: .glance
            case .start, .restday, .banner, .join, .replay, .train: .train
            case .dashboard: .today
            case .pulse: .pulse
            case .fuel: .fuel
            default: nil
            }
            if let wanted, pages.contains(wanted) { page = wanted }
        }
        #endif
    }
}

/// One page: up to three accessory faces in `WatchSlab`s in the page's ink,
/// and whatever that page can DO.
private struct DashboardPageView: View {

    let page: DashboardPage
    let tiles: WatchTiles?

    var body: some View {
        ScrollView {
            VStack(spacing: OnyxSpace.xs) {
                if page == .fuel { FoodSlab(tiles: tiles) }
                // `prefix`, not a hand-written three: the cap is
                // `WatchDashboard.facesPerPage`, and the test replays it.
                ForEach(page.faces.prefix(WatchDashboard.facesPerPage), id: \.self) { id in
                    // Water is the fixed water blue on every page and in every
                    // theme (decision Q19) — the Fuel page's honey would make
                    // the one water reading on the wrist the wrong colour.
                    WatchSlab(tint: id == .water ? OnyxInk.Fixed.water : page.ink) {
                        OnyxTile.accessory(id, family: .accessoryRectangular, tiles: tiles)
                    }
                }
                if page == .fuel { WaterGlassButton() }
            }
            .padding(.horizontal, OnyxSpace.xs)
        }
        // A page of static readings held at full brightness is the textbook
        // burn-in case.
        .dimmedWhenLuminanceReduced()
    }
}

/// Today's food in one slab: kcal eaten, what is left, and a three-segment
/// macro bar (overhaul A2).
///
/// ── THE BAR IS ENERGY, NOT GRAMS ────────────────────────────────────────────
/// Each segment is its macro's share of the day's CALORIES (protein and carbs
/// at 4 kcal/g, fat at 9) — the proportion that matters, and the one a gram
/// bar would misdraw by more than double for fat. The inks are the W0
/// weighted macro inks, so the trio shifts with the theme but stays itself.
///
/// A phone that predates carbs and fat on the wire sends protein alone; the
/// bar is then not drawn rather than drawn as all protein.
struct FoodSlab: View {
    let tiles: WatchTiles?

    private var energy: [(kcal: Double, ink: Color, name: String)]? { Self.energy(tiles) }

    /// Each macro's energy, protein · carbs · fat — shared with the Food
    /// detail (D3) so the page and the detail cannot split the day
    /// differently. Nil unless all three rode the wire.
    static func energy(_ tiles: WatchTiles?) -> [(kcal: Double, ink: Color, name: String)]? {
        guard let p = tiles?.proteinG, let c = tiles?.carbsG, let f = tiles?.fatG, p + c + f > 0 else { return nil }
        return [(Double(p) * 4, Color.onyx.protein, "protein"),
                (Double(c) * 4, Color.onyx.carbs, "carbs"),
                (Double(f) * 9, Color.onyx.fat, "fat")]
    }

    var body: some View {
        WatchSlab(tint: Color.onyx.calories) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "fork.knife")
                        .font(.system(.callout, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tiles?.kcal.map { "\($0.formatted()) kcal" } ?? "No food yet")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(tiles?.kcalRemaining.map { $0 >= 0 ? "\($0.formatted()) left" : "\((-$0).formatted()) over" } ?? "No target")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(WatchInk.secondary)
                            .lineLimit(1)
                    }
                }
                if let energy { EnergyBar(energy: energy, height: 5) }
            }
        }
    }
}

/// The day's calories split protein · carbs · fat, as shares of ENERGY.
struct EnergyBar: View {
    let energy: [(kcal: Double, ink: Color, name: String)]
    let height: CGFloat

    var body: some View {
        let total = energy.reduce(0) { $0 + $1.kcal }
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(energy.indices, id: \.self) { i in
                    Capsule()
                        .fill(energy[i].ink)
                        .frame(width: max(3, (geo.size.width - 4) * energy[i].kcal / total))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Macros")
        .accessibilityValue(energy.map { "\($0.name) \(Int(($0.kcal / total * 100).rounded())) percent" }
            .joined(separator: ", "))
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
                //
                // NO accent: this is a harness for a face whose own colours
                // are the subject, and a tinted card around it would be
                // reviewing the card. A `nil` accent is the plain
                // `WatchInk.fill` row this card wore before the pages gained
                // colour, and — the part that matters — it sets no
                // `foregroundStyle`, so `LiveWorkoutFace` draws its movement
                // name at full ink exactly as the complication does. The first
                // version passed `WatchInk.secondary` here and photographed the
                // name at white 0.62, which is the harness lying about the
                // thing it exists to photograph.
                WatchSlab(tint: nil) {
                    LiveWorkoutFace(snapshot: snapshot, family: .accessoryRectangular)
                }
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
        .containerBackground(for: .navigation) { WatchInk.ground }
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
struct WaterGlassButton: View {

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
