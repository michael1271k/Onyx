import Foundation

/// The wrist's width budget, in points.
///
/// ── WHY A SCREENSHOT CANNOT BE THE GATE HERE ────────────────────────────────
/// Every watch screen in this app is laid out for **40 mm — 162 × 197 pt** —
/// and the paired simulator is an Ultra 2 at 49 mm, which is 205 pt wide. A
/// 49 mm screenshot therefore hides exactly the overflow the budget exists to
/// catch, and watchOS does not clip an over-wide child and does not warn: it
/// draws it off the display. `scripts/watch-shot.sh` says the same thing at its
/// bottom, and names this file as the gate.
///
/// So the arithmetic is here, pure, and `OnyxWatchLayoutTests` replays it — the
/// same argument `PairLayout` makes one folder over: a layout decision that is
/// arithmetic belongs where a test can reach it, not inline in a `body` whose
/// only available test is a photograph.
///
/// ── WHAT IT DOES NOT CLAIM ──────────────────────────────────────────────────
/// It does not measure text. It states how wide a cell IS at a given column
/// count and how wide a cell of each KIND has to be, and the views take their
/// grids from here so the two cannot drift. Whether a particular string fits
/// its cell is still the view's problem, solved the way this app always solves
/// it — `lineLimit`, `allowsTightening`, `minimumScaleFactor` — and checked by
/// eye at 49 mm. The number this file guards is the one the eye cannot check.
public enum WatchCase {

    /// The 40 mm display. The floor, not the target.
    public static let width40mm: Double = 162
    public static let height40mm: Double = 197

    /// What watchOS insets a full-screen view by on each side at 40 mm.
    ///
    /// 8, arrived at by subtraction rather than by documentation: `SetView`,
    /// `RestView` and `WatchSessionTimer` have all budgeted against "the 146 pt
    /// this screen actually has at 40 mm" since Wave 10, against a 162 pt bar.
    /// The difference is the gutter, and this is the first place it is written
    /// down as a number instead of as a remark in three headers.
    public static let gutter: Double = 8

    /// 146 — the width a row may actually occupy at 40 mm.
    public static let content40mm: Double = width40mm - gutter * 2

    /// The 49 mm Ultra 2 — the case every screenshot in this repository is
    /// taken on. Stated so the gap between the gate and the photograph is a
    /// number here rather than a remark in a shell script.
    public static let width49mm: Double = 205
    public static let height49mm: Double = 251

    /// What the inline navigation bar with a back chevron takes off the top.
    ///
    /// ── 64, AND IT WAS MEASURED, NOT ESTIMATED ──────────────────────────────
    /// W4 first wrote 28 here by the same subtraction `gutter` was arrived at,
    /// and the accessibility tree said 64: the bar is a 36 pt circular Back
    /// button at y=19 plus a 21.5 pt heading, and the group around them is
    /// 64 pt tall. The error was 36 points — more than half a row — and the
    /// test built on it happily asserted that a page fits which does not.
    ///
    /// Measured on the 49 mm pair, and used as the budget for 40 mm too. That
    /// is deliberate and it is the conservative direction: a 40 mm bar is no
    /// TALLER than this, so every "it fits" this constant produces is an
    /// answer that also holds on the case nothing here can photograph.
    public static let navBar: Double = 64

    /// 187 — the page a pushed screen actually has on the 49 mm pair.
    public static let content49mmHeight: Double = height49mm - navBar

    /// 133 — the same, at 40 mm, against the measured 49 mm bar.
    ///
    /// Conservative by construction: the real 40 mm bar is smaller, so the
    /// true page is a little taller than this. A layout that fits 133 fits
    /// the device; one that does not may still fit, and this file will not
    /// claim it does.
    public static let content40mmHeight: Double = height40mm - navBar
}

/// The wrist's dashboard pages (W4, founder decision 2).
///
/// ── WHY THIS IS ARITHMETIC AND NOT A LAYOUT ─────────────────────────────────
/// The same argument `WatchPanel` makes one type up, in the other dimension.
/// The pages are a vertical `TabView`, so a page that does not fit does not
/// clip and does not warn — it scrolls, which silently turns a glance into a
/// gesture, and the paired simulator is an Ultra 2 whose 251 pt of height
/// hides it completely. 40 mm has 197.
///
/// So how many faces a page may hold is decided here, replayed by
/// `OnyxWatchLayoutTests`, and read by `DashboardPages` — which takes its row
/// count from this and nowhere else.
public enum WatchDashboard {

    /// Between two rows on a page. `OnyxSpace.xs`, as a number, for the reason
    /// `WatchPanel.gap` gives.
    public static let gap: Double = 4

    /// One accessory row: a `.accessoryRectangular` face — a glyph and two
    /// lines of `footnote`/`caption2` — inside a card's own padding.
    ///
    /// ── 48.5, MEASURED OFF THE ACCESSIBILITY TREE ───────────────────────────
    /// Not estimated. The Fuel page's three cards sit at y = 64, 116.5 and
    /// 169 on the 49 mm pair, so the pitch is 52.5 and the row is that less
    /// the 4 pt gap. W4's first guess was 42, which was six points light per
    /// row and eighteen over a page — enough to turn "this fits" into a
    /// button photographed half off the bottom of the display.
    ///
    /// Measured at 49 mm and used at 40 mm, like `WatchCase.navBar` and for
    /// the same reason: a 40 mm row is no taller, so this over-counts, and
    /// over-counting is the only direction a budget may be wrong in.
    public static let rowHeight: Double = 48.5

    /// The Fuel page's "+1 glass" button, which is a fourth element under
    /// three faces. 54 pt measured, on the same tree.
    public static let buttonHeight: Double = 54

    /// How many rows fit a page WITHOUT it having to scroll.
    ///
    /// Floors at 1 rather than 0 — a page with no rows draws nothing at all,
    /// silently, which is the failure mode `WatchPanel.columns` also refuses.
    public static func rows(within height: Double = WatchCase.content40mmHeight) -> Int {
        var n = 1
        while used(rows: n + 1) <= height { n += 1 }
        return n
    }

    /// The height `n` rows and their gaps occupy.
    public static func used(rows n: Int) -> Double {
        guard n > 0 else { return 0 }
        return rowHeight * Double(n) + gap * Double(n - 1)
    }

    /// Does a page of `n` rows fit without scrolling?
    public static func fits(rows n: Int, within height: Double = WatchCase.content40mmHeight) -> Bool {
        n > 0 && used(rows: n) <= height
    }

    /// THREE faces a page — the design decision, which is not the same number
    /// as `rows()` and deliberately so.
    ///
    /// ── WHAT THIS COSTS, STATED RATHER THAN HIDDEN ──────────────────────────
    /// Three faces fit the 49 mm pair with 33 pt to spare, and do NOT fit the
    /// 40 mm case: 153.5 pt of rows against a 133 pt page, so the third card
    /// hangs about 20 pt below the fold and the Fuel page's button a further
    /// 58. The page is a `ScrollView` and the Crown reaches both — which is
    /// the same gesture that turns the page, on a screen whose whole
    /// interaction is the Crown.
    ///
    /// It is three and not two because the pages were specified as three
    /// readings each and the alternative is deleting a reading from every
    /// page to buy a scroll nobody has to make on the case this app is worn
    /// on. `OnyxWatchLayoutTests` asserts BOTH halves of that — what fits and
    /// what hangs — so the cost is a number in the repository and a decision
    /// a later wave can reverse by changing this one constant.
    public static let facesPerPage = 3

    /// How far a page of `facesPerPage` faces hangs below a given page, or 0.
    public static func overflow(
        rows n: Int, button: Bool = false, within height: Double = WatchCase.content40mmHeight
    ) -> Double {
        let content = used(rows: n) + (button ? buttonHeight + gap : 0)
        return max(0, content - height)
    }
}

/// The Set Quality panel's grid (W3).
///
/// One place decides how many columns each chip row gets, because the panel is
/// three rows of chips that must all survive the same 146 pt and the failure is
/// invisible on the only device available to photograph it.
public enum WatchPanel {

    /// Between two chips. `OnyxSpace.xs`, spelled as a number because OnyxCore
    /// may not import OnyxUI — the view passes the token and the test pins the
    /// two together (`OnyxWatchLayoutTests.gapIsTheToken`).
    public static let gap: Double = 4

    /// The narrowest a chip carrying ONE OR TWO GLYPHS may be drawn — the L/R
    /// side markers, and a kind badge on its own.
    ///
    /// 44, the platform's minimum target, and here it is the target that binds
    /// rather than the text: two glyphs of `caption2` are ~13 pt.
    public static let glyphChip: Double = 44

    /// The narrowest a chip carrying a WORD may be drawn.
    ///
    /// ── IT IS THE LONGEST WORD, NOT THE LONGEST LABEL ───────────────────────
    /// The chips wrap to two lines like the phone's do, so "Form broke" may
    /// break after "Form". What can never break is a single word: the longest
    /// in either vocabulary is `Momentum` / `Assisted` at eight glyphs, and
    /// `caption2` resolves to ~13 pt on a 40 mm case, where a lowercase glyph
    /// advances about half an em. 8 × 6.5 = 52, plus the chip's own 4 pt insets
    /// on each side = 60.
    ///
    /// A word chip is therefore WIDER than the 44 pt target, which is why the
    /// two floors are two constants: sizing the quality grid off the tap target
    /// is what would put three columns on this row and ellipsise every label.
    public static let wordChip: Double = 60

    /// How wide each cell comes out at this column count.
    public static func cellWidth(columns: Int, within width: Double = WatchCase.content40mm) -> Double {
        guard columns > 0 else { return 0 }
        return (width - gap * Double(columns - 1)) / Double(columns)
    }

    /// Does a grid of this many columns hold cells at least `minWidth` wide?
    public static func fits(columns: Int, minWidth: Double, within width: Double = WatchCase.content40mm) -> Bool {
        columns > 0 && cellWidth(columns: columns, within: width) >= minWidth
    }

    /// The column count a row of `count` chips should use.
    ///
    /// ── THE CANDIDATES ARE BALANCED GRIDS, NOT EVERY INTEGER ────────────────
    /// One line first, then two, then three. Trying every count downwards would
    /// answer THREE for a row of four chips — a 3 + 1 grid, which is a ragged
    /// row and a widow, and which the eye reads as a missing fourth option. The
    /// candidates are therefore `ceil(count / rows)` for rows = 1, 2, 3 …, so
    /// four chips fall to 2 × 2 and six fall to 3 × 2.
    ///
    /// This is the same call the phone's own sheet makes at an accessibility
    /// size — `SetOptionsSheet.kindColumns` drops four across to two, because
    /// "four 74 pt chips is four truncated words". A 40 mm wrist is that case
    /// permanently: 146 pt over two columns is 71, which is within a point of
    /// the width the phone decided was the floor for a word.
    ///
    /// Falls back to 1 when even one column is too narrow — a state this app
    /// cannot reach at 146 pt, and the honest answer if a smaller case ever
    /// ships.
    public static func columns(
        forCount count: Int, minWidth: Double, within width: Double = WatchCase.content40mm
    ) -> Int {
        guard count > 1 else { return 1 }
        for rows in 1...count {
            let candidate = Int((Double(count) / Double(rows)).rounded(.up))
            if fits(columns: candidate, minWidth: minWidth, within: width) { return candidate }
            if candidate <= 1 { break }
        }
        return 1
    }
}
