import SwiftUI

/// Chips that wrap.
///
/// ── WHY IT LIVES IN THE DESIGN SYSTEM (W11) ─────────────────────────────────
/// It was written for one card on the exercise page and file-scoped there. Ten
/// screens now reach for it — the ledger's two tag rows, the session header,
/// the cardio sheet's kind picker and its bout cards, the week's capsules and
/// dots, the logger's deck, a Pulse square, the routine editor — which made an
/// app-target file the load-bearing layout for half the app's chips. Moving it
/// here is what lets a tile or a watch face use the same wrap, and what stops
/// the next package-side chip row from being a second implementation of the
/// clamp below.
///
/// `Layout` rather than a `LazyVGrid`: a grid gives every chip the widest chip's
/// width, so "Bodyweight" and "One side at a time" would sit in two columns the
/// width of the longer one. This is the smallest correct flow layout — measure
/// each subview, break when the line is full.
public struct FlowRow: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = measure(view, within: width)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = measure(view, within: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    /// A chip's own ideal size — unless its ideal is wider than the whole row,
    /// in which case the row's width is offered instead.
    ///
    /// ── WHY THE CLAMP (W5) ──────────────────────────────────────────────────
    /// This layout wraps BETWEEN subviews and never inside one, so `.unspecified`
    /// alone is the right question for every chip that fits: it is what keeps
    /// "Bodyweight" one line rather than letting it break on its own. But a chip
    /// whose ideal exceeds the container has no line to be moved to — it was
    /// placed at that ideal width and drawn straight off the edge of the card,
    /// with `lineLimit` and `minimumScaleFactor` never consulted because nothing
    /// ever told the text it was short of room.
    ///
    /// It went unseen because every chip in this app is two or three words. The
    /// first one that is not — the bout's "Automatically logged", on the ledger
    /// since W4 and on the Train tab since W5 — reads "Automatically lo" at AX5,
    /// clipped mid-word with a capsule running past the glass.
    ///
    /// Re-proposing the row's width is what lets the chip's OWN rules run: two
    /// lines first, then down to 60 %, and only then a truncation. Nothing that
    /// already fitted changes, because for those the branch is never taken.
    private func measure(_ view: LayoutSubviews.Element, within width: CGFloat) -> CGSize {
        let ideal = view.sizeThatFits(.unspecified)
        guard ideal.width > width else { return ideal }
        return view.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }
}
