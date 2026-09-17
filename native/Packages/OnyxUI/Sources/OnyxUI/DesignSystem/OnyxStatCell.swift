// ── iOS ONLY ────────────────────────────────────────────────────────────────
// The trail behind the figure is `Sparkline`, which lives in `Tiles/` behind
// the same guard: a Home Screen tile's primitives do not exist on watchOS, and
// the watch draws two screens of its own out of the tokens rather than out of
// this vocabulary. Both callers of this cell are the phone.
#if os(iOS)

import SwiftUI

/// A register label, one figure, and the line under it that says what the
/// figure means — the app's one square.
///
/// ── IT WAS TWO, AND THEY WERE THE SAME OBJECT ───────────────────────────────
/// `SessionDetailView.cell(_:_:_:sub:tint:symbol:)` and
/// `WeeklyWrapContent.stat(_:_:delta:tint:)` were a micro label, a `.display`
/// numeral and a small line beneath it, drawn twice in two files. They differed
/// in four things and only two of them were decisions: the session cell wears
/// `onyxGlass(.row)` and reserves its second line, the wrap-up's does neither.
/// The other two — a `.caption` sub against a `.micro` one, a 0.7 scale floor
/// against 0.6 — were drift, and drift is what a second implementation of one
/// object produces on its own.
///
/// So the two decisions are parameters and the drift is gone. Anything else
/// that wants a labelled figure takes this one.
///
/// ── AND WHY THE SPARKLINE IS BEHIND THE NUMBER, NOT UNDER IT ────────────────
/// A cell is ~84 pt wide in a 3-up grid and its whole height is three line
/// boxes. There is no room for a fourth, and a trail drawn under the value
/// would take the line the delta lives on — the one thing on the cell that
/// carries a comparison. Behind it costs nothing: the figure keeps its own
/// contrast (the trail is drawn at 18 %, under the text, clipped to the cell),
/// and eight weeks of shape arrives in the space the number was already using.
///
/// It is DECORATION in the accessibility sense and is hidden from VoiceOver —
/// the same eight sessions are readable as numbers on the Progression chart one
/// card down, and a curve has no reading to announce.
public struct OnyxStatCell: View {

    /// The line under the figure: what changed, and what that is worth.
    public struct Sub: Equatable, Sendable {
        public let text: String
        public let color: Color
        public init(_ text: String, _ color: Color) {
            self.text = text
            self.color = color
        }
    }

    let label: String
    let value: String
    /// `kg`, `min`, `bpm` — set beside the figure, never under it.
    var unit: String?
    var sub: Sub?
    /// Whether a cell with nothing to say still keeps the room for it.
    ///
    /// True wherever the cell sits in a GRID that is redrawn for a different
    /// subject — §3.6's rule: a line that appears only when there is a change
    /// makes the whole grid change height between two sessions, and a cell
    /// silent about its comparison is indistinguishable from one that has none.
    /// False on a one-off card, where there is no second rendering to stay the
    /// same height as.
    var reserves = true
    var tint: Color?
    var symbol: String?
    /// The figure's own recent history, oldest first. Under two points the
    /// trail draws nothing at all rather than a flat line at zero.
    var spark: [Double] = []
    /// Whether the cell wears a surface of its own.
    var glass = true
    /// Said to VoiceOver and drawn nowhere — the restatement that used to take
    /// the sub-line ("measured", "estimated") on a cell whose sub-line is now
    /// a comparison or nothing.
    var detail: String?

    public init(
        _ label: String, _ value: String, unit: String? = nil, sub: Sub? = nil,
        reserves: Bool = true, tint: Color? = nil, symbol: String? = nil,
        spark: [Double] = [], glass: Bool = true, detail: String? = nil
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.sub = sub
        self.reserves = reserves
        self.tint = tint
        self.symbol = symbol
        self.spark = spark
        self.glass = glass
        self.detail = detail
    }

    @ViewBuilder
    public var body: some View {
        // A branch and not `onyxGlass(glass ? .row : .none)`: there is no
        // `.none` level, and adding one would put "draw no material" into the
        // vocabulary of the modifier that owns depth — where every other case
        // is a real layer. A cell with no surface is a cell the CALLER has
        // already given one.
        if glass {
            stack.padding(OnyxSpace.s).onyxGlass(.row)
        } else {
            stack
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 2) {
            // ── THE GLYPH SITS WITH THE LABEL, NOT WITH THE FIGURE ──────────
            // Three cells across is ~110 pt each on a 375 pt phone, and a
            // symbol beside the value takes that width from the one thing in
            // the cell that must not shrink. Beside the register label it costs
            // 14 pt of a line that is already short, and it is the half of the
            // cell the eye uses to FIND the reading rather than to read it.
            //
            // `.hierarchical` rather than flat: the flame's inner lobe and the
            // trophy's base separate at 11 pt, which is what makes them read as
            // objects instead of as blobs, and it takes the tint the label is
            // already spending.
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .onyxType(.micro)
                        .foregroundStyle(tint ?? Color.onyx.textTertiary)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .onyxMicro()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .onyxType(.display).onyxNumeral()
                    .foregroundStyle(tint ?? Color.onyx.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    // The figure takes the width FIRST. `38…` beside `kcal` is
                    // worse than `383` beside a slightly smaller `kcal`.
                    .layoutPriority(1)
                if let unit {
                    Text(unit)
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .bottomLeading) { trail }
            subLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }

    /// The eight weeks behind the figure, under it and quiet.
    ///
    /// Clipped to the value row's own bounds and drawn at the bottom, so a
    /// trail that rises steeply cannot climb over the register label above it.
    @ViewBuilder
    private var trail: some View {
        if spark.count >= 2 {
            Sparkline(points: spark, color: tint ?? Color.onyx.textSecondary, zeroBased: false)
                .opacity(0.18)
                .frame(height: 18)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var subLine: some View {
        if let sub {
            Text(sub.text)
                .onyxType(.caption).onyxNumeral()
                .foregroundStyle(sub.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else if reserves {
            // Measured BY the line it replaces rather than by a number: the
            // same `Text`, in the same role, hidden. `.hidden()` is documented
            // as "hides this view without changing its layout", so the
            // reservation is the real height at every text size — a
            // `frame(height:)` would hold at default type and drift at AX5.
            Text("—")
                .onyxType(.caption)
                .hidden()
                .accessibilityHidden(true)
        }
    }

    private var spoken: String {
        [label, [value, unit].compactMap { $0 }.joined(separator: " "), sub?.text, detail]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

#endif
