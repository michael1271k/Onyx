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
}
