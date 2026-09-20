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
