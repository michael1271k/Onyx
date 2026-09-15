// ── iOS ONLY ────────────────────────────────────────────────────────────────
// `UIAccessibility.isReduceMotionEnabled` is unavailable on watchOS. The
// watch reads `@Environment(\.accessibilityReduceMotion)` instead — which it
// has to anyway, because there it shares a branch with `isLuminanceReduced`.
#if os(iOS)

import SwiftUI
import Charts

/// The chart kit. Swift Charts, one style modifier, no custom legend, no custom
/// scrubber.
///
/// ── WHAT THE WEB KIT WAS, AND WHY NONE OF IT COMES ACROSS ───────────────────
/// `components/charts/{ChartTooltip, SmartLegend, ChartRange, OnyxViz}.tsx`
/// plus the hand-rolled SVG kit in `parts.tsx` — ~700 loc that existed because
/// recharts' tooltip, legend and brush were the wrong shape for a phone. Swift
/// Charts ships the three things that code imitated:
///
///   · `chartXSelection(value:)` — the scrub. A `RuleMark` at the selected x with
///     an `.annotation` is the tooltip; the OS owns the gesture, the haptics and
///     the accessibility of it.
///   · `chartScrollableAxes(.horizontal)` + `chartXVisibleDomain` — the range
///     rail. The user pans a window over the whole series instead of picking a
///     bucket from a segmented control.
///   · `chartLegend` — drawn from `chartForegroundStyleScale`, so the legend and
///     the marks cannot disagree, which was `SmartLegend`'s entire bug class.
///
/// What the kit DOES own is the part Apple leaves to the app: colour, type and
/// the weight of the axes. That is `onyxChart(_:)`, and every chart in the app
/// wears it so the chart on the Body tab and the chart on an exercise's history
/// read as one instrument.
///
/// ── THE DATAVIZ RULES THIS ENCODES ──────────────────────────────────────────
/// · Recessive axes: grid lines are the 8 % hairline, no axis line, no ticks,
///   labels in tertiary ink. The data is the only thing that is a colour.
/// · One axis. Nothing here lets a second y-scale in; two measures are two
///   charts stacked, never one chart with two rails.
/// · Text wears text tokens, never the series colour — a value beside a mark
///   is `textPrimary` with the coloured mark carrying identity.
/// · Categorical colour is a FIXED order (`Color.onyx.series`), validated on
///   black with the dataviz palette script (OKLCH L 0.48–0.67, ΔE ≥ 9 across
///   every CVD simulation, ≥ 3:1 on the surface). A seventh series is never a
///   generated hue; it is the neutral and it should have been folded.
/// · Numerals are rounded + monospaced, as everywhere else in the app.
public struct OnyxChartStyle: ViewModifier {
    let domain: OnyxDomain

    public func body(content: Content) -> some View {
        content
            .foregroundStyle(domain.accent)
            .chartXAxis {
                AxisMarks(preset: .aligned) { _ in
                    AxisGridLine().foregroundStyle(Color.onyx.hairline)
                    AxisValueLabel()
                        .font(OnyxChart.axisFont)
                        .foregroundStyle(Color.onyx.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(Color.onyx.hairline)
                    AxisValueLabel()
                        .font(OnyxChart.axisFont)
                        .foregroundStyle(Color.onyx.textTertiary)
                }
            }
            .chartPlotStyle { plot in plot.background(.clear) }
            .chartLegend(position: .top, alignment: .leading, spacing: 8)
            // Selection and pan tracks the finger 1:1 and never animates; the
            // only motion a chart makes is the data changing under it, and
            // under Reduce Motion even that is a cut.
            .transaction { t in if OnyxChart.reduceMotion { t.animation = nil } }
    }
}

public extension View {
    /// The one chart modifier. Colour, type, axis weight — everything a chart
    /// should not decide for itself.
    ///
    /// A chart that must shape its own axis (thin the labels, hide one) sets
    /// `chartXAxis`/`chartYAxis` BEFORE this modifier: the axis closest to the
    /// `Chart` wins, so an override placed after it is silently ignored.
    func onyxChart(_ domain: OnyxDomain) -> some View {
        modifier(OnyxChartStyle(domain: domain))
    }

    /// A pannable window over a dated x-axis, parked on the newest data.
    ///
    /// This replaces `ChartRange.tsx`: instead of picking 30/90/180 from a
    /// segmented control and re-fetching, the whole series is on the chart and
    /// the user pans. `days` is how much of it fits in the plot at once.
    func onyxScrollable(days: Int, endingAt end: Date = Date()) -> some View {
        self
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: TimeInterval(days) * 86_400)
            .chartScrollPosition(initialX: end.addingTimeInterval(-TimeInterval(days) * 86_400))
    }
}

public enum OnyxChart {
    /// Axis labels: the app's numeral face at caption size.
    public static let axisFont: Font = .system(.caption2, design: .rounded).monospacedDigit()

    /// The default plot height. Charts scale their TYPE with Dynamic Type; the
    /// plot itself keeps a fixed height because a taller plot is not more
    /// legible, and the hairline grid would spread until it read as empty.
    public static let plotHeight: CGFloat = 180

    /// A chart card's own inset — between `OnyxSpace.m` and `.l`, and the one
    /// value in the system that is neither. It is named rather than typed
    /// because a card that is NOT an `OnyxChartCard` but sits beside one (the
    /// Trends muscle atlas, whose content is a figure and a legend rather than a
    /// plot) has to match it exactly, and a second `14` in a view is a number
    /// nobody can tell was deliberate.
    public static let cardPadding: CGFloat = 14

    /// Read once per draw; a chart has no ambient motion, so this only decides
    /// whether a data change cross-fades or cuts.
    static var reduceMotion: Bool {
        MainActor.assumeIsolated { UIAccessibility.isReduceMotionEnabled }
    }

    /// A short date for an x-axis or a callout: "4 Sep".
    public static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// ISO `yyyy-MM-dd` → `Date` at local midnight, the x-value every dated
    /// series plots on. Every domain series is keyed by ISO string; the chart
    /// is the one place a `Date` is wanted, so the conversion lives here.
    public static func date(_ iso: String) -> Date? {
        var parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let day = parts.removeLast(), month = parts.removeLast(), year = parts.removeLast()
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }
}

public extension Color.onyx {
    /// Categorical series colour, in FIXED order: Ion, Tide, Solar, Lunar, then
    /// the far stop of Ion and of Solar.
    ///
    /// ── WHY THESE ARE THE DOMAIN TOKENS AND NOT SIX HEXES OF THEIR OWN ──────
    /// They used to be six hand-darkened hexes, chosen because the v1 accents
    /// were neons that blew out as a filled area on black. Tokens v2 is already
    /// two steps down (§3.2), which is the same correction — so a separate chart
    /// palette is now a second definition of the same four hues, drifting from
    /// the first the moment either moves. A series that is literally
    /// `OnyxDomain.body.start` is the guarantee that the Body tab's chart and
    /// the Body tab's accent are one colour.
    ///
    /// Four domains first so a two-series chart in the Body tab is still Tide
    /// and something, not two strangers.
    ///
    /// Re-measured on black after the v2 re-key, because deriving from the
    /// tokens is not on its own a guarantee: worst adjacent pair ΔE76 29.9, all
    /// six ≥ 5.4:1. Re-measure if a domain stop moves.
    ///
    /// Computed so it follows `OnyxTheme.current`; a stored static would
    /// capture the theme at first read.
    static var series: [Color] { [
        OnyxDomain.train.start,
        OnyxDomain.body.start,
        OnyxDomain.fuel.start,
        OnyxDomain.recover.start,
        OnyxDomain.train.end,
        OnyxDomain.fuel.end,
    ] }

    /// Series `index`, or the neutral past the sixth: a seventh series is a
    /// chart that should have been two, and it does not get a colour that
    /// pretends otherwise.
    static func series(_ index: Int) -> Color {
        index >= 0 && index < series.count ? series[index] : textTertiary
    }
}

/// The scrub callout: what `RuleMark(x:).annotation { }` shows at the selected
/// x. Glass, a caption and one or more numerals in text ink.
///
/// `chartXSelection` gives the x; the caller resolves the y-values for that x
/// (there may be several series) and hands them here as label/value pairs, so
/// the callout never re-derives data.
public struct OnyxCallout: View {
    public struct Line: Identifiable {
        /// Its own identity, never the label: two lines with the same (or an
        /// empty) label collided in `ForEach`, which drew the first twice and
        /// dropped the second — the volume callout on a PR session.
        public let id = UUID()
        public let label: String
        public let value: String
        public let color: Color?
        public init(_ label: String, _ value: String, color: Color? = nil) {
            self.label = label; self.value = value; self.color = color
        }
    }

    let title: String
    let lines: [Line]
    /// One line of context under the values — "6 days since", "Maintenance
    /// week". Tertiary ink and caption size, because it qualifies the reading
    /// rather than being one: a footnote set in the same weight as a value is
    /// a second value with no units.
    let footnote: String?
    /// The callout is PINNED and will not follow the finger away. Drawn as a
    /// glyph beside the title, so a callout that stayed behind is visibly
    /// different from one that is being scrubbed.
    let pinned: Bool

    public init(_ title: String, lines: [Line], footnote: String? = nil, pinned: Bool = false) {
        self.title = title
        self.lines = lines
        self.footnote = footnote
        self.pinned = pinned
    }

    public init(_ title: String, value: String) {
        self.init(title, lines: [Line("", value)])
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(Color.onyx.textSecondary)
                if pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.onyx.textTertiary)
                }
            }
            ForEach(lines) { line in
                HStack(spacing: 5) {
                    if let color = line.color {
                        Circle().fill(color).frame(width: 6, height: 6)
                    }
                    if !line.label.isEmpty {
                        Text(line.label)
                            .font(.caption2)
                            .foregroundStyle(Color.onyx.textSecondary)
                    }
                    Text(line.value)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.onyx.textPrimary)
                }
            }
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // ── WHY NOT `onyxGlass(.row)` ───────────────────────────────────────
        // Glass is a material, and a material TINTS towards whatever is behind
        // it. Behind this one is a chart: a saturated line, a filled bar and,
        // on the Body tab, a Tide mesh under all of it — so the callout on the
        // composition chart came out as a grey-green box with a green gradient
        // baked into its corner, and `textSecondary` on that is barely a
        // reading. Every other surface in the app sits on the SCREEN, where
        // sampling is the whole point; this is the one that sits on the DATA.
        //
        // It is also the one surface whose ink cannot follow the material: the
        // text tokens are fixed white alphas, so in a light colour scheme the
        // thin material goes pale and takes 92 % white with it. A flat base
        // fill is legible in both, which a material here can never be.
        //
        // 0.92 rather than 1: the mark under the finger stays faintly visible
        // through it, which is what keeps this a callout on a chart and not a
        // card parked over one. The hairline is the edge the material used to
        // imply.
        .background {
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .fill(Color.onyx.base.opacity(0.92))
        }
        .overlay {
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .strokeBorder(Color.onyx.hairline, lineWidth: 0.5)
        }
    }
}

/// A titled chart on a tile. The header carries the name, an optional headline
/// value (the latest reading, in the domain's accent) and the chart sits under
/// it at `OnyxChart.plotHeight`.
public struct OnyxChartCard<Content: View>: View {
    let title: String
    let domain: OnyxDomain
    let headline: String?
    let caption: String?
    /// A key for something the marks encode that colour cannot — a hollow
    /// symbol, a washed bar.
    ///
    /// ── WHY IT IS THE CARD'S AND NOT THE CHART'S ────────────────────────────
    /// `content` is handed a FIXED height, so a legend drawn inside it comes
    /// out of the plot: adding one 30 pt row to a 180 pt budget took a third of
    /// the bars away, which is the opposite of what a legend is for. Up here it
    /// costs the CARD height, like the caption it sits under. `chartLegend`
    /// cannot do this job — it is generated from `chartForegroundStyleScale`,
    /// and what is being explained is a shape, not a hue.
    let legend: AnyView?
    let content: Content

    /// The plot scales with the type, not the other way round: at AX5 the axis
    /// labels are three times taller and a fixed 180 pt plot would be all
    /// labels and no data.
    @ScaledMetric(relativeTo: .body) private var plotHeight = OnyxChart.plotHeight
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        _ title: String,
        domain: OnyxDomain,
        headline: String? = nil,
        caption: String? = nil,
        legend: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.domain = domain
        self.headline = headline
        self.caption = caption
        self.legend = legend
        self.content = content()
    }

    public var body: some View {
        // Title beside the headline, until the headline alone is a line wide.
        let header = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        VStack(alignment: .leading, spacing: 10) {
            header {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(domain.accent)
                Spacer(minLength: 8)
                if let headline {
                    Text(headline)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.onyx.textPrimary)
                        .contentTransition(.numericText())
                }
            }
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Color.onyx.textSecondary)
            }
            if let legend { legend }
            content
                .frame(height: plotHeight)
        }
        .padding(OnyxChart.cardPadding)
        .onyxGlass(.tile)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(headline.map { "\(title), \($0)" } ?? title)
    }
}

/// What a chart shows when the series is empty. Stock, so it looks like every
/// other empty state on the device.
///
/// ── AND WHY IT HAS A COMPACT FORM ───────────────────────────────────────────
/// W12 put charts on WIDGET faces, where a `ContentUnavailableView` at a 180 pt
/// minimum is three times the height of the tile it is meant to fill. The
/// alternative was a second empty state written per face, which is how a
/// dashboard ends up with six different ways of saying "no data" — so the
/// compact form lives here instead, with the same words and the same glyph at a
/// size a 158 pt tile can hold.
public struct OnyxChartEmpty: View {
    let message: String
    /// Widget-face sizing: no minimum height, the widget type scale, and no
    /// `ContentUnavailableView` — which reserves space for a title, a
    /// description and an action a tile has no room for.
    let compact: Bool

    public init(_ message: String = "Nothing logged yet.", compact: Bool = false) {
        self.message = message
        self.compact = compact
    }

    public var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "chart.xyaxis.line")
                    .font(OnyxWidgetType.face(14))
                    .foregroundStyle(Color.onyx.textTertiary)
                Text(message)
                    .font(OnyxWidgetType.face(10))
                    .foregroundStyle(Color.onyx.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("No data. \(message)")
        } else {
            ContentUnavailableView {
                Label("No data", systemImage: "chart.xyaxis.line")
            } description: {
                Text(message)
            }
            .frame(maxWidth: .infinity, minHeight: OnyxChart.plotHeight)
        }
    }
}

#endif
