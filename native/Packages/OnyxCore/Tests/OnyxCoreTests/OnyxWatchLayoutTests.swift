import Foundation
import Testing
@testable import OnyxCore

/// The 40 mm floor (cross-wave law 11).
///
/// ── THIS IS THE GATE THE SCREENSHOTS CANNOT BE ──────────────────────────────
/// The paired simulator is an Ultra 2 at 49 mm — 205 pt wide — and every watch
/// screen in this app is laid out for 162 pt. watchOS neither clips an
/// over-wide child nor warns about one; it draws it off the display. So a
/// screenshot on the pair is evidence about look and never about fit, and
/// `scripts/watch-shot.sh` says so in its own closing comment and names this
/// suite.
///
/// ── WHAT IT ASSERTS, AND WHAT IT DOES NOT ───────────────────────────────────
/// It asserts the CELL WIDTHS the Set Quality panel's grids resolve to at
/// 162 pt, and that each kind of chip gets a cell at least as wide as that kind
/// of chip needs. It does not measure a string: no test here renders text, and
/// claiming it did would be the thin fixture this sprint keeps warning about.
/// The panel's views take their column counts from `WatchPanel` and nowhere
/// else, so what is asserted here is what is drawn.
@Suite("Watch layout — the 162 pt floor")
struct OnyxWatchLayoutTests {

    /// The two vocabularies the panel draws, by count. Spelled out rather than
    /// read from `SetTags` so that ADDING a quality key fails this test: a
    /// seventh chip changes the grid, and the grid is the thing under review.
    private let kindChips = 4      // W / F / D / G — SetTags.tags, no "normal" chip
    private let qualityChips = 6   // SetTags.qualityKeys
    private let sideChips = 2      // L / R

    @Test("the case is 162 × 197 and a row has 146 of it")
    func theCase() {
        #expect(WatchCase.width40mm == 162)
        #expect(WatchCase.height40mm == 197)
        #expect(WatchCase.content40mm == 146)
    }

    /// The claim in the wave's gate: every row of the panel fits 162 pt.
    @Test("every panel row fits inside the 40 mm case")
    func everyRowFits() {
        let rows: [(name: String, count: Int, floor: Double)] = [
            ("kind", kindChips, WatchPanel.wordChip),
            ("quality", qualityChips, WatchPanel.wordChip),
            ("side", sideChips, WatchPanel.glyphChip),
        ]
        for row in rows {
            let columns = WatchPanel.columns(forCount: row.count, minWidth: row.floor)
            let cell = WatchPanel.cellWidth(columns: columns)
            let used = cell * Double(columns) + WatchPanel.gap * Double(columns - 1)
            #expect(cell >= row.floor, "\(row.name): \(cell) pt cell is under the \(row.floor) pt floor")
            #expect(used <= WatchCase.content40mm + 0.001, "\(row.name): \(used) pt of 146")
            #expect(used + WatchCase.gutter * 2 <= WatchCase.width40mm + 0.001, "\(row.name): past the 162 pt case")
        }
    }

    /// The column counts the panel actually draws. Pinned as values, not
    /// recomputed, so a change to the floors or the gap shows up here as a
    /// decision rather than sliding through.
    @Test("the grids are 2 × 2 kinds, 2 × 3 qualities and one row of sides")
    func theGrids() {
        #expect(WatchPanel.columns(forCount: kindChips, minWidth: WatchPanel.wordChip) == 2)
        #expect(WatchPanel.columns(forCount: qualityChips, minWidth: WatchPanel.wordChip) == 2)
        #expect(WatchPanel.columns(forCount: sideChips, minWidth: WatchPanel.glyphChip) == 2)
        #expect(WatchPanel.cellWidth(columns: 2) == 71)
    }

    /// Four across is what the plan asked for and what 146 pt refuses — the
    /// same refusal the phone's own sheet makes at an accessibility size.
    @Test("four word chips across do not fit, and three do not either")
    func fourAcrossIsRefused() {
        #expect(WatchPanel.fits(columns: 4, minWidth: WatchPanel.wordChip) == false)
        #expect(WatchPanel.fits(columns: 3, minWidth: WatchPanel.wordChip) == false)
        #expect(WatchPanel.fits(columns: 2, minWidth: WatchPanel.wordChip))
        // Glyph chips are a different question and three of them DO fit, which
        // is why the two floors are two constants.
        #expect(WatchPanel.fits(columns: 3, minWidth: WatchPanel.glyphChip))
    }

    /// The candidates are balanced grids. Three across for four chips would be
    /// a ragged row with a widow, which reads as a missing fourth option.
    @Test("a grid never comes out ragged")
    func balanced() {
        // 4 chips: 1 row (no) then 2 rows of 2 — never 3 + 1.
        #expect(WatchPanel.columns(forCount: 4, minWidth: WatchPanel.wordChip) == 2)
        // 5 glyph chips at 146: 1 row of 5 is 27 pt (no), 2 rows of 3 is 46 (yes).
        #expect(WatchPanel.columns(forCount: 5, minWidth: WatchPanel.glyphChip) == 3)
        // 3 word chips: 1 row of 3 is 46 (no), 2 rows of 2 is 71 (yes).
        #expect(WatchPanel.columns(forCount: 3, minWidth: WatchPanel.wordChip) == 2)
    }

    /// A case narrower than anything shipped still answers, and answers 1
    /// rather than 0 — a grid with no columns draws nothing, silently.
    @Test("an impossible width falls back to one column")
    func degenerate() {
        #expect(WatchPanel.columns(forCount: 6, minWidth: WatchPanel.wordChip, within: 30) == 1)
        #expect(WatchPanel.columns(forCount: 1, minWidth: WatchPanel.wordChip) == 1)
        #expect(WatchPanel.columns(forCount: 0, minWidth: WatchPanel.wordChip) == 1)
        #expect(WatchPanel.cellWidth(columns: 0) == 0)
    }

    /// The 49 mm case the shots are taken on, stated so the gap between the
    /// gate and the photograph is a number in the repository rather than a
    /// remark in a shell script.
    @Test("the Ultra 2 is 43 pt wider than the floor, which is why it proves nothing")
    func thePairIsWider() {
        let ultra2: Double = 205
        #expect(ultra2 - WatchCase.width40mm == 43)
        // Four word chips would "fit" on the device the screenshots come from.
        #expect(WatchPanel.fits(columns: 4, minWidth: WatchPanel.wordChip, within: ultra2 - WatchCase.gutter * 2) == false)
        // …and three would, which is the row a 49 mm shot would have approved.
        #expect(WatchPanel.fits(columns: 3, minWidth: WatchPanel.wordChip, within: ultra2 - WatchCase.gutter * 2))
    }

    // MARK: - The dashboard pages (W4)
    //
    // The same gate in the other dimension. A page that overflows does not
    // clip and does not warn — it becomes a page you have to SCROLL, which
    // turns a glance into a gesture, and the Ultra 2 the shots come from has
    // 54 pt of height the 40 mm case does not.
    //
    // ── EVERY NUMBER BELOW WAS MEASURED, AND THE FIRST SET WAS NOT ──────────
    // W4 wrote this suite twice. The first version estimated a 28 pt
    // navigation bar and a 42 pt row, and passed — asserting that three faces
    // plus a button fit a page on which the button was photographed hanging
    // half off the bottom. The bar is 64 and the row is 48.5, off the
    // accessibility tree of the running app. A layout test built on a guess
    // is worse than no layout test: it is a green light with a number behind
    // it that nobody checked.

    @Test("the 49 mm bar is 64 and the 40 mm bar is 47.5, so the pages are 187 and 149.5")
    func thePageHeight() {
        #expect(WatchCase.navBar == 64)
        #expect(WatchCase.navBar40mm == 47.5)
        #expect(WatchCase.content40mmHeight == 149.5)
        #expect(WatchCase.content49mmHeight == 187)
    }

    @Test("two faces fit the 40 mm page on the conservative budget, and three miss by 4")
    func whatFitsTheFloor() {
        #expect(WatchDashboard.fits(rows: 2))
        #expect(WatchDashboard.fits(rows: 3) == false)
        #expect(WatchDashboard.rows() == 2)
        // 48.5 × 2 + 4 = 101, of 149.5.
        #expect(WatchDashboard.used(rows: 2) == 101)
        #expect(WatchDashboard.used(rows: 3) == 153.5)
    }

    /// The design decision, and the four points the proxy says it costs.
    @Test("the pages draw three faces, and the 49 mm proxy puts the third 4 pt over")
    func threeFacesAndWhatItCosts() {
        #expect(WatchDashboard.facesPerPage == 3)
        // One more than the conservative budget allows — see `facesPerPage`.
        #expect(WatchDashboard.facesPerPage == WatchDashboard.rows() + 1)
        #expect(WatchDashboard.overflow(rows: 3) == 4)
        // It was 20.5 against the ESTIMATED 40 mm bar, which is the estimate
        // `WatchCase.navBar40mm` replaced with a measurement.
    }

    /// What a 40 mm case ACTUALLY reports, read off the accessibility tree of
    /// the running app on `Apple Watch SE 3 (40mm)` — the first time any
    /// screen in this repository was measured on the floor it is laid out for.
    ///
    /// This is the test that stops the suite asserting a scroll the device
    /// does not have. Every shipped page fits, with single-digit room.
    @Test("measured at 40 mm, every dashboard page fits without scrolling")
    func theRealFortyMillimetreCase() {
        #expect(WatchDashboard.rowHeight40mm == 46)
        #expect(WatchDashboard.buttonHeight40mm == 45)

        // Today / Train: three faces. 46 × 3 + 4 × 2 = 146 of 149.5.
        let threeFaces = WatchDashboard.rowHeight40mm * 3 + WatchDashboard.gap * 2
        #expect(threeFaces == 146)
        #expect(threeFaces <= WatchCase.content40mmHeight)
        #expect(WatchCase.content40mmHeight - threeFaces == 3.5)

        // Fuel: two faces and the button. 46 × 2 + 4 + 4 + 45 = 145.
        let twoAndAButton = WatchDashboard.rowHeight40mm * 2 + WatchDashboard.gap
            + WatchDashboard.gap + WatchDashboard.buttonHeight40mm
        #expect(twoAndAButton == 145)
        #expect(twoAndAButton <= WatchCase.content40mmHeight)

        // And the shape of the old claim: three faces AND the button is over,
        // which is why `.steps` moved to the Train page.
        #expect(threeFaces + WatchDashboard.gap + WatchDashboard.buttonHeight40mm
                > WatchCase.content40mmHeight)
    }

    /// What the 49 mm pair actually shows, which is what the screenshots in
    /// this wave are evidence of and no more.
    @Test("three faces fit the pair with room, and a button beside them would not")
    func whatThePairShows() {
        #expect(WatchDashboard.fits(rows: 3, within: WatchCase.content49mmHeight))
        #expect(WatchDashboard.overflow(rows: 3, within: WatchCase.content49mmHeight) == 0)
        // 33.5 pt spare — which is 24.5 short of the button, and is exactly
        // why the first Fuel shot came back with "Add a glass" cut in half.
        #expect(WatchCase.content49mmHeight - WatchDashboard.used(rows: 3) == 33.5)
        #expect(WatchDashboard.overflow(rows: 3, button: true, within: WatchCase.content49mmHeight) == 24.5)
        // A fourth face would "fit" the pair, which is the whole reason a
        // screenshot cannot be this gate.
        #expect(WatchDashboard.fits(rows: 4, within: WatchCase.content49mmHeight) == false)
        #expect(WatchDashboard.rows(within: WatchCase.content49mmHeight) == 3)
    }

    /// The Fuel page as W2 actually ships it, which is the arithmetic that
    /// took "Add a glass" off the bottom of the 49 mm display.
    ///
    /// W4 put three faces AND the button on that page and the screenshot came
    /// back with the button cut through the middle, 24.5 pt below the fold on
    /// the very case this app is worn on. W2 moved `.steps` to the Train page
    /// — the one reading on Fuel that is not fuel — and two faces plus a
    /// button is 159 pt of the pair's 187.
    @Test("the Fuel page is two faces and a button, and that fits the pair")
    func theFuelPage() {
        // 48.5 × 2 + 4 = 101, + 4 + 54 = 159.
        #expect(WatchDashboard.used(rows: 2) + WatchDashboard.gap + WatchDashboard.buttonHeight == 159)
        #expect(WatchDashboard.overflow(rows: 2, button: true, within: WatchCase.content49mmHeight) == 0)
        #expect(WatchCase.content49mmHeight - 159 == 28)
        // The conservative 49 mm proxy puts it 9.5 pt over the 40 mm page;
        // the measured 40 mm numbers put it 4.5 pt UNDER — see
        // `theRealFortyMillimetreCase`, and the screenshot that agrees with it.
        #expect(WatchDashboard.overflow(rows: 2, button: true) == 9.5)
    }

    /// A case shorter than anything shipped still answers, and answers 1
    /// rather than 0: a page with no rows draws nothing at all, silently.
    /// The same refusal `WatchPanel.columns` makes.
    @Test("an impossible height still yields one row")
    func degenerateHeight() {
        #expect(WatchDashboard.rows(within: 10) == 1)
        #expect(WatchDashboard.used(rows: 0) == 0)
        #expect(WatchDashboard.fits(rows: 0) == false)
        #expect(WatchDashboard.overflow(rows: 0) == 0)
    }

    // MARK: - The Glance (overhaul A2)

    /// ── MEASURED, AND THE FIRST DRAFT OF THIS TEST WAS A GUESS ──────────────
    /// It fed the layout `height − nav bar` (187 / 149.5) and passed. `axe
    /// describe-ui` on the two simulators said otherwise: inside the vertical
    /// `TabView` the Glance's square is **148 pt at 49 mm** (petals at
    /// y 64…212, 40 pt each) and **130 pt at 40 mm** (y 48…178, 35 pt each) —
    /// the page reserves its own bottom inset. Those are the numbers here.
    static let glanceSquare49mm: Double = 148
    static let glanceSquare40mm: Double = 130

    // MARK: - Six petals (Precision D1, decision Q22)

    /// ── THE HEIGHT IS THE WHOLE BUDGET ──────────────────────────────────────
    /// A petal sits on the vertical axis above the ring and another below it,
    /// so ring + two petals + two gaps IS the square's height — the width is
    /// never what binds (the side petals sit at ±30°, only cos 30° out). The
    /// founder's rule (Overhaul open call 4, resolved Q22): the petals keep
    /// ≥ 38 pt at 40 mm and the RING is what gives.
    @Test("six petals: ≥ 38 pt at 40 mm, the ring shrinks, nothing touches")
    func sixPetalsFit() {
        #expect(WatchGlance.petalCount == 6)
        #expect(WatchGlance.angles.count == WatchGlance.petalCount)
        let big = WatchGlance.layout(width: WatchCase.width49mm, height: Self.glanceSquare49mm)
        let small = WatchGlance.layout(width: WatchCase.width40mm, height: Self.glanceSquare40mm)
        #expect(small.petal >= 38, "40 mm petal is \(small.petal) pt")
        #expect(big.petal >= small.petal, "the 49 mm petal is smaller than the 40 mm one")
        // ── MEASURED (axe describe-ui, D1 round 3) ──────────────────────────
        // 40 mm (SE 3): petals 38 × 38, ring 46.5, centre 30.5, the square
        // y 47.5…178. 49 mm (Ultra 2): petals 42.5–43, ring 54, centre 38,
        // the square y 64…212. The squares are the ones this suite already
        // pinned: the page did not move, the flower inside it did.
        #expect(abs(small.petal - 38) < 0.5 && abs(big.petal - 42.75) < 0.5, "axe: 38 / 42.5–43 pt")
        #expect(abs(small.ring - 46.5) < 1 && abs(big.ring - 54) < 1, "axe: ring 46.5 / 54 pt")
        for layout in [big, small] {
            // The ring clears every petal (they all sit on one orbit).
            #expect(layout.clearance >= WatchGlance.ringGap - 0.01, "petals touch the ring: \(layout.clearance) pt")
            // Neighbours 60° apart: the chord is the orbit itself.
            #expect(layout.neighbourGap >= 4, "petals touch each other: \(layout.neighbourGap) pt")
            // Top and bottom petals inside the square.
            #expect(layout.orbit + layout.petal / 2 <= layout.square / 2 + 0.01)
            // Every petal is a button: 38 pt is the floor the brief sets, the
            // Crown and the centre are the other two doors.
            for i in 0..<WatchGlance.petalCount {
                let o = layout.offset(i)
                #expect(abs((o.x * o.x + o.y * o.y).squareRoot() - layout.orbit) < 0.01)
            }
        }
        // The flower is the Body tab's (seam 5): top-left, top, top-right,
        // then bottom-left, bottom, bottom-right — none on the horizontal.
        #expect(WatchGlance.angles == [-150, -90, -30, 150, 90, 30])
        // Two digits of readiness fit inside the ring and its battery arc.
        #expect(small.centre >= 24, "40 mm centre is \(small.centre) pt")
        #expect(small.width <= WatchCase.content40mm, "40 mm flower is \(small.width) pt wide")
    }

    @Test("a degenerate page still answers a layout, never a negative ring")
    func sixPetalsDegenerate() {
        let tiny = WatchGlance.layout(width: 20, height: 20)
        #expect(tiny.ring >= 0)
        #expect(tiny.centre >= 0)
        #expect(tiny.petal <= tiny.square / 3 + 0.01)
    }
}
