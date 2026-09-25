import SwiftUI
import OnyxUI
import OnyxCore

/// Cut the Stone — how hard the session was, as the app icon's own gesture
/// (Precision A5, design 3).
///
/// ── WHY IT REPLACED THE DIAL ────────────────────────────────────────────────
/// The dial was a 168 pt ring: a generic control, the tallest thing on the
/// sheet, and a circle asked to carry five words. The founder asked for the
/// rating to feel like Onyx. The icon is a black slab with one diagonal light
/// vein running through it, so the rating is that slab: drag or tap across it
/// and the vein cuts further in — a 12 % sliver at Easy, the whole diagonal at
/// Everything. Five detents, the five words `Effort.words` has always stored
/// (`session_rpe` still takes the half-point CR-10 underneath each), and 116 pt
/// against the dial's 200.
///
/// Nothing is cut until something is rated: a slab that opens with a vein has
/// answered the question for you — and clearing a suggestion must leave it
/// whole. The vein grows with a spring; under Reduce Motion it moves straight
/// to its length.
struct EffortSlab: View {
    @Binding var word: EffortWord?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The slab's width, for the drag — measured, because the slab's HEIGHT
    /// is its content's (a `GeometryReader` would fix it instead).
    @State private var width: CGFloat = 0

    private var words: [EffortWord] { Effort.words }
    private var index: Int? { word.flatMap { w in words.firstIndex { $0.key == w.key } } }

    /// How far the vein runs: 12 % at the first word, the whole diagonal at
    /// the last, nothing when unrated.
    static func level(_ index: Int?, of count: Int) -> CGFloat {
        guard let index, count > 1 else { return 0 }
        return 0.12 + 0.88 * CGFloat(index) / CGFloat(count - 1)
    }

    var body: some View {
        VStack(spacing: OnyxSpace.s) {
            slab
            scale
        }
    }

    // MARK: - The slab

    private var slab: some View {
        // At the accessibility sizes the words fill the stone and the vein's
        // diagonal ran through "CR-10" (W-final shot) — so there the vein gets
        // its own band under the words instead of the whole slab.
        let band: CGFloat? = typeSize.isAccessibilitySize ? 40 : nil
        return reading
            .padding(OnyxSpace.m)
            .padding(.bottom, band ?? 0)
            // At least the icon's proportion of a slab; taller when the type
            // is — the word must never be clipped by the stone it is cut in.
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(alignment: .bottom) {
                vein(Self.level(index, of: words.count)).frame(maxHeight: band ?? .infinity)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .contentShape(.rect)
            // A tap rates where it lands; a drag rates only once it is going
            // SIDEWAYS — a sheet scroll that starts on the slab is not a
            // training-load input (review).
            .onTapGesture { location in pick(x: location.x, width: width) }
            .gesture(DragGesture(minimumDistance: 8).onChanged { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                pick(x: drag.location.x, width: width)
            })
            .onyxGlass(.tile)
        .sensoryFeedback(.selection, trigger: word?.key)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session effort")
        .accessibilityValue(word.map { "\($0.label), \(OnyxFormat.rpe($0.cr10))" } ?? "Not rated")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            default: break
            }
        }
    }

    /// A tapering crack, not a line: wide where the cut began, a hair at its
    /// tip — a soft lavender glow, the lavender edge, the pearl core. A
    /// constant-width stroke read as a chart's trend line (shot review).
    private func vein(_ level: CGFloat) -> some View {
        ZStack {
            VeinShape(level: level, width: 9)
                .fill(OnyxInk.Fixed.veinEdge.opacity(0.5))
                .blur(radius: 7)
            VeinShape(level: level, width: 5)
                .fill(OnyxInk.Fixed.veinEdge)
            VeinShape(level: level, width: 2)
                .fill(OnyxInk.Fixed.veinCore)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.15), value: level)
        .accessibilityHidden(true)
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(word?.label ?? "Slide to rate")
                .onyxDisplay()
                .foregroundStyle(word.map { Color.onyx.effort($0.cr10) } ?? Color.onyx.textTertiary)
                .lineLimit(1)
                .animation(reduceMotion ? nil : OnyxMotion.fade, value: word?.key)
            if let word {
                Text("CR-10 \(OnyxFormat.rpe(word.cr10))")
                    .onyxType(.micro).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
            }
        }
        // Capped: the word is also spelled, at full size, in the row of
        // detents under the slab; here it only has to fit the stone.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        // The words sit over the vein's widest end; a faint shadow of the
        // slab's own black keeps them legible where the light crosses.
        .shadow(color: Color.onyx.base.opacity(0.9), radius: 6)
    }

    // MARK: - The five words

    /// The detents, spelled. Tapping one rates it; the slab above is the same
    /// control for a thumb that would rather drag.
    private var scale: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { stops }
            VStack(alignment: .leading, spacing: 4) { stops }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var stops: some View {
        ForEach(words, id: \.key) { stop in
            let on = stop.key == word?.key
            Button { word = stop } label: {
                Text(stop.label)
                    .onyxType(.caption)
                    .fontWeight(on ? .semibold : .regular)
                    .foregroundStyle(on ? Color.onyx.effort(stop.cr10) : Color.onyx.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The slab's adjustable action already speaks and moves these.
            .accessibilityHidden(true)
        }
    }

    /// Equal fifths — the same five zones the words under the slab occupy,
    /// so a finger over "Everything" rates Everything (review: rounding onto
    /// four gaps put 85 % of the width on Brutal).
    private func pick(x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let i = min(Int(max(x, 0) / width * CGFloat(words.count)), words.count - 1)
        word = words[i]
    }

    private func step(_ by: Int) {
        let next = min(max((index ?? -1) + by, 0), words.count - 1)
        word = words[next]
    }
}

/// The vein: a crack from the slab's lower left toward its upper right, with
/// the small kinks a real vein in stone has, cut to `level` of its length and
/// tapering from `width` at its root to a hair at its tip. A `Shape` so the
/// length animates as one path rather than as a redraw.
struct VeinShape: Shape {
    var level: CGFloat
    var width: CGFloat

    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }

    /// Along the diagonal (0…1) and across it (points): the kinks. Small and
    /// fixed, so the same rating is always the same cut.
    private static let kinks: [(t: CGFloat, off: CGFloat)] = [
        (0, 0), (0.21, 1.5), (0.4, -1), (0.58, 1.8), (0.77, -0.8), (1, 0),
    ]

    private static func offset(at t: CGFloat) -> CGFloat {
        guard let upper = kinks.firstIndex(where: { $0.t >= t }), upper > 0 else { return 0 }
        let a = kinks[upper - 1], b = kinks[upper]
        return a.off + (b.off - a.off) * (t - a.t) / (b.t - a.t)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard level > 0 else { return path }
        let start = CGPoint(x: rect.minX + rect.width * 0.03, y: rect.maxY - rect.height * 0.16)
        let end = CGPoint(x: rect.maxX - rect.width * 0.03, y: rect.minY + rect.height * 0.16)
        let dx = end.x - start.x, dy = end.y - start.y
        let length = max((dx * dx + dy * dy).squareRoot(), 1)
        // The unit normal: the kinks run along it, and so does the width.
        let nx = -dy / length, ny = dx / length
        let steps = 24
        var left: [CGPoint] = [], right: [CGPoint] = []
        for k in 0...steps {
            let t = level * CGFloat(k) / CGFloat(steps)
            let centre = Self.offset(at: t)
            // Full width at the root, a tenth of it at the tip.
            let half = width / 2 * (1 - 0.9 * CGFloat(k) / CGFloat(steps))
            let x = start.x + dx * t, y = start.y + dy * t
            left.append(CGPoint(x: x + nx * (centre + half), y: y + ny * (centre + half)))
            right.append(CGPoint(x: x + nx * (centre - half), y: y + ny * (centre - half)))
        }
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }
}
