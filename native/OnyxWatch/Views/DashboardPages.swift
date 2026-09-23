import OnyxCore
import OnyxUI
import SwiftUI
import WatchKit

// MARK: - The wrist's four pages (W2 of the App Store sprint, founder decision 2)
//
// ── IT IS THE ROOT NOW, AND THAT IS THE WHOLE REBUILD ───────────────────────
// W4 built this as a PUSHED screen behind a toolbar disc, and W3's `RootView`
// header argued for that at length: "every screen that is not the set in front
// of you is a tap on the way to the set in front of you". That argument is
// still right DURING a workout and it was always wrong outside one — outside a
// workout there is no set in front of you, and what the app opened on instead
// was the word "Rest day" over an empty screen.
//
// So the pages moved up one level. `RootView` opens on this when no session is
// live, and page one is the Start screen rather than a reading — the one tap
// that used to be the whole root is still the first thing under your thumb,
// and everything the phone knows is now a Crown turn away instead of a
// toolbar disc away.
//
// ── IT DRAWS THE COMPLICATION FACES, AND THAT IS STILL THE DESIGN ───────────
// Unchanged from W4 and worth restating, because it is what keeps this from
// being a third rendering of the day's numbers: the cards are
// `OnyxTile.accessory`, the same unfenced view the phone's Lock Screen and
// this watch's own complications draw, fed the same `WatchTiles` the phone
// already sent. Nothing here composes a string from a number.
//
// ── WHERE THE COLOUR COMES FROM ─────────────────────────────────────────────
// The founder's complaint was "ugly, colorless list tabs", and the diagnosis
// was in `AccessoryFace`: a rectangular face is a glyph, a `title` and a `sub`,
// all of them ink, because an accessory renders `.accented` on most watch faces
// and the system flattens colour away there anyway. That face must not change —
// it is shared with the phone — so the colour is added AROUND it, by the card,
// and it is the PAGE's colour rather than each face's.
//
// One accent a page, from `OnyxDomain`, which is the palette the phone has had
// since 3.0: Today → `recover` (lavender), Train → `train` (indigo), Fuel →
// `fuel` (honey). Page one takes the SPLIT's own colour, `WatchInk.day`, which
// is the colour that session already wears everywhere else in the app. No
// second palette was invented and no hex appears in this file.
//
// ── THREE FACES A PAGE, AND WHY THEY FIT NOW ────────────────────────────────
// `WatchDashboard.facesPerPage` is still three, and the price it used to carry
// turned out not to exist. The re-root is NOT what bought it back — a root
// navigation bar measures the same 64 pt as a pushed one, which is why there is
// no `rootBar` constant. What bought it back was putting the app on a 40 mm
// case for the first time: `WatchCase.navBar40mm` is 47.5, not the 64 this
// repository had been budgeting against, so the page is 149.5 and a row is 46.
// Three rows are 146. The old claim — "the third card hangs 20.5 pt below the
// 40 mm fold" — was arithmetic on an estimate, and `OnyxWatchLayoutTests`
// now replays both the conservative budget and the measured device.
//
// ── WHAT DID NOT CHANGE ─────────────────────────────────────────────────────
// Vertical paging (the Crown already drives it), `.dimmedWhenLuminanceReduced`
// on every static face (burn-in), two ink levels, and no
// `.scrollInputBehavior(.disabled, for: .handGestureShortcut)` — that modifier
// kills a scroll view's input entirely on this SDK and W3 paid for finding out.

/// Which page is up. `Hashable` for the `TabView` selection, and named rather
/// than indexed so the shot loop can ask for one by name.
enum DashboardPage: String, CaseIterable, Hashable {
    /// Today's split and the one Start button. The root's first page, and the
    /// screen that used to BE the root.
    case start
    case today, train, fuel

    var title: String {
        switch self {
        case .start: "Onyx"
        case .today: "Today"
        case .train: "Train"
        case .fuel: "Fuel"
        }
    }

    /// The page's one colour.
    ///
    /// Nil on `.start` deliberately: that page's accent is the SPLIT's colour,
    /// which is data (`WatchInk.day`) and not a domain. The view resolves it;
    /// this enum does not get to hold a model.
    var domain: OnyxDomain? {
        switch self {
        case .start: nil
        case .today: .recover
        case .train: .train
        case .fuel: .fuel
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
        // Page one is the hero and draws no accessory face at all — its
        // content is `StartView`, which is a decision and one control.
        case .start: []
        // Battery and score are ONE face (`AccessoryReading.recovery` draws
        // the battery as its hero and the readiness score as its second
        // line), which is what leaves room for sleep and stress beside them.
        //
        // ── THE ORDER IS THE DROP ORDER ────────────────────────────────────
        // `prefix(facesPerPage)` cuts from the END, so each list is written
        // most-wanted first and the last entry is the one that goes if the
        // budget ever shrinks: `.stress` is nil until something is answered on
        // the phone, and `.steps` has a first-party app one button press away.
        case .today: [.recovery, .sleep, .stress]
        // ── `.train` IS NOT HERE, AND `.steps` IS (W2) ─────────────────────
        // W4's Train page opened with the `.train` face, which draws "Upper B
        // / due". Page one now draws the same split at `WatchType.figure` in
        // the split's own colour with the Start button under it, so the face
        // was the same fact said smaller, two Crown turns away. It is still a
        // complication (`WidgetId.wearable`) — it is just not a page.
        //
        // `.steps` took the slot, off the Fuel page, for a layout reason
        // measured rather than felt: three faces AND the "+1 glass" button is
        // `overflow(rows: 3, button: true, within: WatchCase.content49mmHeight)`
        // = 24.5 pt below even the 49 mm fold — and the 49 mm screenshot showed
        // "Add a glass" cut through the middle, which is the exact failure that
        // constant was added to name. Two faces and the button is 159 pt of the
        // pair's 187, and 145 of the 40 mm case's measured 149.5.
        case .train: [.volume, .weekRings, .steps]
        case .fuel: [.fuel, .water]
        }
    }
}

/// The dashboard.
///
/// The app's ROOT when no session is live (`RootView`), and still a pushed
/// screen from `DeckView`'s toolbar during one — `showsStart` is the whole
/// difference between the two, because offering "Start today's split" to
/// somebody who is thirty minutes into today's split is offering a button
/// that cannot do anything.
struct DashboardView: View {

    @Environment(WatchModel.self) private var model

    /// False when this is pushed from inside a live session. See the type
    /// header.
    private let showsStart: Bool

    @State private var page: DashboardPage

    /// ── THE SELECTION IS SET AT INIT, NOT CORRECTED IN `onAppear` ───────────
    /// A `TabView` whose selection names a tag no page carries draws NOTHING —
    /// and `showsStart: false` removes exactly the page a `.start` default
    /// would name. Correcting that in `onAppear` would work and would be the
    /// third thing in this app to learn why it should not: `RootView` and
    /// `DashboardView` both carry a comment about `onAppear` firing before the
    /// `.task` one level up has seeded anything. A `State(initialValue:)` in
    /// the initialiser has no ordering to get wrong.
    init(showsStart: Bool = true) {
        self.showsStart = showsStart
        _page = State(initialValue: showsStart ? .start : .today)
    }

    private var pages: [DashboardPage] {
        showsStart ? DashboardPage.allCases : DashboardPage.allCases.filter { $0 != .start }
    }

    /// The current page's colour. `.start` resolves to the split's own tint,
    /// which is why this is a function of the model and not a property of the
    /// enum.
    private func accent(_ page: DashboardPage) -> Color {
        page.domain?.accent ?? WatchInk.day(model.day?.key)
    }

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
            ForEach(pages, id: \.self) { page in
                Group {
                    if page == .start {
                        StartView()
                    } else {
                        DashboardPageView(page: page, tiles: model.dashboardTiles, accent: accent(page))
                    }
                }
                .tag(page)
            }
        }
        .tabViewStyle(.verticalPage)
        .containerBackground(WatchInk.ground, for: .navigation)
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        // ── THE TITLE DOES NOT TAKE THE PAGE'S COLOUR, AND THAT WAS TESTED ──
        // The first version of this file put `.tint(accent(page))` here on the
        // belief that watchOS draws an inline navigation title in the tint
        // colour. It does not — the heading came back `WatchInk.secondary` grey
        // on all four pages in the 49 mm screenshots, identical with and
        // without the modifier. `.foregroundStyle` does not reach a navigation
        // title either, and `.principal` is not a placement this app has ever
        // proved on watchOS.
        //
        // So the title stays the system's grey and the colour lives entirely
        // in the cards, which is where the founder's complaint was. The
        // heading is still the wayfinding — four pages need names — it simply
        // is not the accent. Recorded rather than deleted so the next wave
        // does not spend the same round discovering it.
        #if DEBUG
        // The shot loop's hook. `onChange(of:initial:)` and not `onAppear`,
        // for the reason `RootView` records: the seeding runs in a `.task`
        // one level up, which starts AFTER this view appears — so `onAppear`
        // read a nil `debugScreen` every time and photographed page one under
        // every filename.
        .onChange(of: model.debugScreen, initial: true) { _, screen in
            // Clamped to `pages`, because `.start` is not one of them on the
            // in-session push and a `TabView` selection that matches no tag
            // draws NOTHING — silently, permanently, under a correct filename.
            let wanted: DashboardPage? = switch screen {
            case .start, .restday, .banner, .join: .start
            case .dashboard: .today
            case .train: .train
            case .fuel: .fuel
            default: nil
            }
            if let wanted, pages.contains(wanted) { page = wanted }
        }
        #endif
    }
}

/// One page: up to three accessory faces in the page's colour, and whatever
/// that page can DO.
private struct DashboardPageView: View {

    let page: DashboardPage
    let tiles: WatchTiles?
    let accent: Color

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
                    DashboardCard(accent: accent) {
                        OnyxTile.accessory(id, family: .accessoryRectangular, tiles: tiles)
                    }
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
                DashboardCard(accent: nil) {
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

/// The card a face sits in — and the whole of the "colourless" fix.
///
/// ── A TINT AND A HAIRLINE, NOT A REWRITTEN FACE ─────────────────────────────
/// `AccessoryFace` is shared with the phone's Lock Screen and this watch's
/// complications, where the system flattens everything to one tint — so colour
/// inside it would carry no information there and would be a second drawing of
/// a view that exists to be one drawing. The card is the one layer that is only
/// ever on this screen, so the colour goes here.
///
/// ── THE TWO NUMBERS, AND WHY 0.14 IS ARITHMETIC AND NOT TASTE ───────────────
/// A `0.14` fill and a `0.45` hairline, both of the page's accent over pure
/// black.
///
/// 0.14 because `LuminanceDim` multiplies this whole page by 0.76 in the
/// always-on state, and 0.14 × 0.76 = 0.106 — which is `WatchInk.fill` to
/// within a thousandth. So the dimmed card weighs exactly what the grey card
/// it replaces weighed: the always-on state costs the COLOUR and not the
/// layout, and nothing about the panel's static load changed. It is not 0.10,
/// because a hue at 10 % on true black reads as the same grey the founder
/// called colourless; it is not 0.25, because `WatchInk`'s own header forbids
/// "any large area of accent" held at brightness.
///
/// A border rather than a leading rule because a rule costs WIDTH — 3 pt plus
/// its inset — and at 40 mm the face has 146 pt and spends all of it on two
/// `lineLimit(1)` captions that already tighten.
///
/// ── AND WHY A TINTED FILL IS DEFENSIBLE HERE AT ALL ─────────────────────────
/// Because this is the IDLE root. A live session roots at `SetView`, so no
/// page in this file is ever the screen held under a bar for an hour — which
/// is the case `WatchInk` is written against. That is the whole licence, and
/// it disappears the day a dashboard page is shown during a workout.
private struct DashboardCard<Content: View>: View {

    /// The page's colour, or nil for the plain row this card used to be —
    /// which is what the DEBUG widget harness wants and nothing else does.
    let accent: Color?
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
    }

    /// Geometry only. Both branches below draw this; they differ in paint.
    private var padded: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OnyxSpace.xs)
            .padding(.vertical, 4)
    }

    @ViewBuilder var body: some View {
        if let accent {
            padded
                // ── THE GLYPH AND THE HEADLINE, WITHOUT TOUCHING THE FACE ───
                // `AccessoryFace.rectangular` draws `Image(systemName:)` and
                // `Text(r.title)` with NO `foregroundStyle` of their own, and
                // `Text(r.sub)` with `.secondary`. So a two-style hierarchy set
                // here lands exactly where it should: the glyph and the reading
                // take the page's colour, the caption under them stays ink.
                // That is an ENVIRONMENT value, not an edit — the face is byte
                // for byte the one the phone's Lock Screen and this watch's
                // complications draw, and on those surfaces the system's own
                // rendering mode wins over anything set here.
                //
                // It does reach one thing beyond the glyph and the headline:
                // `WeekMarks` fills a missed day with `.secondary.opacity(0.35)`
                // and that `.secondary` now resolves to `WatchInk.secondary`
                // rather than the system's. Same family, and the Train page's
                // screenshot shows the marks reading correctly.
                .foregroundStyle(accent, WatchInk.secondary)
                .background(shape.fill(accent.opacity(0.14)))
                .overlay(shape.strokeBorder(accent.opacity(0.45), lineWidth: 1))
        } else {
            padded.background(shape.fill(WatchInk.fill))
        }
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
