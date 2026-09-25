import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// Everything the session ticket and its callers say about ONE finished
/// session, as a value.
///
/// ── WHY A VALUE AND NOT A `Page` ────────────────────────────────────────────
/// The session page builds a whole `SessionAnalysis.Page` — the ledger, the PR
/// pass, the split's own line, the session before it — because it draws all of
/// it. The Train tab's done card and the Pulse day want the masthead and
/// nothing else, and a card that took a `Page` would make either screen pay for
/// a full report per session in order to print a date and four capsules.
/// `SessionAnalysis.headers` fills these in one pass for a batch of ids.
struct SessionHeader: Identifiable, Sendable, Equatable {
    let id: String
    /// The programme's own name for the day — "Legs & Core B".
    let label: String
    let dayKey: String?
    /// Position in the whole CAREER, oldest first. Nil for a session that
    /// recorded no work: numbering it would put a gap in every number after it.
    let careerIndex: Int?
    let prCount: Int
    let planLabel: String
    let week: WeekPhase?
    let lever: NutritionLever?
    let maintenance: Bool
    /// `Sat 13 Sep · 18:20`.
    let stamp: String
    /// What the session was FOR, biggest share of the work first.
    let muscles: [LandmarkMuscle]
    /// The six-point heart-rate spark off the telemetry cache (overhaul
    /// W5.3) — empty until the finish prefetch has filled it.
    var hrSpark: [Double] = []
    /// The session's MEASURED average heart rate — nil for an estimate, which
    /// in the heart's red would read as a reading (the masthead's own rule).
    /// The ticket's third figure when the session set no record (Precision B2).
    var avgBpm: Int? = nil
}

extension SessionHeader {
    /// The session page already holds every one of these; this is a field copy,
    /// not a second derivation.
    init(page: SessionAnalysis.Page, label: String) {
        let session = page.report.session
        self.init(
            id: session.id,
            label: label,
            dayKey: session.dayKey,
            careerIndex: page.careerIndex,
            prCount: page.report.prCount,
            planLabel: page.planLabel,
            week: page.week,
            lever: page.lever,
            maintenance: page.maintenance,
            stamp: SessionAnalysis.stamp(date: session.date, startedAt: session.startedAt),
            muscles: page.report.primaryOrder
        )
    }
}

// MARK: - The ticket (Precision B2, decision Q17 · design 5)

/// A finished session as ONE 64 pt row — the banner Train and the day page
/// draw for it: a 3 pt bar in the day's ink · the name · three figures, with
/// the heart-rate spark laid behind the figures as a 20 % wash.
///
/// ── WHY A TICKET AND NOT THE MASTHEAD ───────────────────────────────────────
/// The banner was the masthead plus a 22 pt spark, the plan tags and the
/// muscle row in 16 pt of padding: ~170 pt to say "you trained, here is the
/// door". The plan tags and the muscles are the SUMMARY's second line now, so
/// the banner keeps what a reader decides on — which session, how long, how
/// heavy, and whether it set a record — and the tap (the zoom Train already
/// runs) opens the rest.
///
/// The third figure is the record count when there is one, and the measured
/// average heart rate, in the heart's red, when there is not: a banner with
/// no record still says how hard the session was. A session with neither
/// shows two figures — never a "—" holding a cell.
///
/// ── WHY THE AX TIER IS A BRANCH, NOT A `ViewThatFits` ───────────────────────
/// The brief asked for `ViewThatFits`. The name is the flexible child here and
/// `ViewThatFits` truncates a flexible child instead of stacking it (memory
/// `w1b-week-detail`), so the break is decided by the type size, as
/// `Shoulders` decides it: one line below the accessibility sizes (the name
/// gives up a little size, then letters), two lines inside them.
struct SessionTicket: View {
    let label: String
    let dayKey: String?
    let durationSec: Int?
    let tonnageKg: Double?
    let prCount: Int
    /// MEASURED only; nil otherwise.
    let avgBpm: Int?
    /// The six-point spark; fewer than two points draws no wash.
    let spark: [Double]
    /// False inside another slab (Train's plan card): a ticket in a tile is a
    /// card in a card, so the host draws the surface and this draws the row.
    var framed = true

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The row's height below the accessibility sizes (the brief's 64 pt).
    static let height: CGFloat = 64

    var body: some View {
        HStack(spacing: OnyxSpace.m) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.onyx.day(dayKey))
                .frame(width: 3)
                .padding(.vertical, OnyxSpace.m)
                .accessibilityHidden(true)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                    name.lineLimit(2)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: OnyxSpace.m) { figureViews }
                        VStack(alignment: .leading, spacing: 2) { figureViews }
                    }
                    .background(alignment: .bottom) { wash }
                }
                .padding(.vertical, OnyxSpace.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                name
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(0)
                Spacer(minLength: OnyxSpace.s)
                HStack(spacing: OnyxSpace.m) { figureViews }
                    .fixedSize()
                    .layoutPriority(1)
                    .frame(maxHeight: .infinity)
                    .background { wash }
            }
        }
        .padding(.leading, OnyxSpace.m)
        .padding(.trailing, OnyxSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: typeSize.isAccessibilitySize ? nil : Self.height)
        .frame(minHeight: Self.height)
        .modifier(TicketSurface(framed: framed))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// `.headline` as a banner; one step down inside a host slab, where the
    /// host's own title is the headline (critique: the unframed ticket on
    /// Train's plan card competed with "Upper A").
    private var name: some View {
        Text(label.isEmpty ? "Session" : label)
            .font(framed ? .headline : .subheadline.weight(.semibold))
            .foregroundStyle(Color.onyx.textPrimary)
    }

    /// The heart-rate spark as a 20 % area, behind the figures only.
    @ViewBuilder
    private var wash: some View {
        if spark.count > 1 {
            SparkArea(points: spark)
                .fill(OnyxInk.Fixed.heart.opacity(0.2))
                .padding(.vertical, OnyxSpace.s)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var figureViews: some View {
        if let durationSec, durationSec > 0 {
            TicketFigure(symbol: "clock", tint: Color.onyx.textSecondary, value: Self.duration(durationSec))
        }
        if let tonnes = OnyxSnapshot.tonnes(tonnageKg.flatMap { $0 > 0 ? $0 : nil }) {
            TicketFigure(symbol: "scalemass", tint: Color.onyx.textSecondary, value: tonnes)
        }
        if prCount > 0 {
            TicketFigure(symbol: "trophy.fill", tint: Color.onyx.record, value: prCount == 1 ? "PR" : "\(prCount) PRs")
        } else if let avgBpm {
            TicketFigure(symbol: "heart.fill", tint: OnyxInk.Fixed.heart, value: "\(avgBpm)", valueTint: OnyxInk.Fixed.heart)
        }
    }

    /// "52 min", "1 h 04" — the masthead's spelling.
    static func duration(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        return m < 60 ? "\(m) min" : String(format: "%d h %02d", m / 60, m % 60)
    }

    private var spoken: String {
        var parts = [label.isEmpty ? "Session" : label]
        if let durationSec, durationSec > 0 { parts.append("\(durationSec / 60) minutes") }
        if let tonnes = OnyxSnapshot.tonnes(tonnageKg.flatMap { $0 > 0 ? $0 : nil }) { parts.append(tonnes) }
        if prCount > 0 { parts.append(prCount == 1 ? "1 record" : "\(prCount) records") }
        else if let avgBpm { parts.append("average heart rate \(avgBpm)") }
        return parts.joined(separator: ", ")
    }
}

/// The Stone slab, or nothing when the host is already one.
private struct TicketSurface: ViewModifier {
    let framed: Bool
    func body(content: Content) -> some View {
        if framed {
            content
                .onyxGlass(.tile)
                .contentShape(RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous))
        } else {
            content.contentShape(.rect)
        }
    }
}

/// One ticket figure: a glyph in its ink, a value in tabular digits.
private struct TicketFigure: View {
    let symbol: String
    let tint: Color
    let value: String
    var valueTint: Color = Color.onyx.textPrimary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(.subheadline, weight: .semibold))
                .imageScale(.small)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.subheadline, weight: .semibold).monospacedDigit())
                .foregroundStyle(valueTint)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// A spark as a filled area: the six points joined, closed to the floor.
/// Scaled to its own min…max with a 10 % band so a flat session is a flat
/// band, not a cliff.
struct SparkArea: Shape {
    let points: [Double]

    func path(in rect: CGRect) -> Path {
        guard points.count > 1, let lo = points.min(), let hi = points.max() else { return Path() }
        let span = max(hi - lo, 1)
        let floor = lo - span * 0.1, ceiling = hi + span * 0.1
        let step = rect.width / CGFloat(points.count - 1)
        func y(_ v: Double) -> CGFloat {
            rect.maxY - CGFloat((v - floor) / (ceiling - floor)) * rect.height
        }
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for (i, v) in points.enumerated() {
            path.addLine(to: CGPoint(x: rect.minX + CGFloat(i) * step, y: y(v)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - The things the week screens borrow (W5)

/// Two things at the two ends of one line — until the type size says a line
/// cannot hold two of anything.
///
/// ── WHY THE BREAK IS A BRANCH AND NOT A `ViewThatFits` ──────────────────────
/// `ViewThatFits` cannot stack a flexible child (memory: `w1b-week-detail`) and
/// a `Spacer` cannot wrap — which is how the ledger header once had its chips
/// and its prescription dividing a 375 pt line four ways. At the accessibility
/// sizes there is no arrangement of two long strings that fits across, so the
/// second one takes its own line and nothing is measured at all.
///
/// Shared since W5: the cardio card's bout puts its kind on one shoulder and
/// its stamp on the other, which is the same line with the same failure at AX5.
struct Shoulders<Leading: View, Trailing: View>: View {
    let alignment: VerticalAlignment
    let leading: () -> Leading
    let trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    init(
        _ alignment: VerticalAlignment = .firstTextBaseline,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.alignment = alignment
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                leading()
                trailing()
            }
        } else {
            HStack(alignment: alignment, spacing: OnyxSpace.s) {
                leading()
                Spacer(minLength: OnyxSpace.xs)
                trailing()
            }
        }
    }
}

/// What a session was FOR, as capsules — the muscle's OWN hue (W3): sixteen
/// muscles, one colour each, so the band, the ramp, the legend and the atlas
/// figure all call one muscle by one colour, and a tag keeps its colour when
/// the session's ranking changes underneath it.
///
/// Named rather than numbered: the share is the Muscle focus card's job, and a
/// capsule carrying "Quads 6.5" would put the session's longest number in its
/// smallest type.
///
/// One row for every caller (the week screens and the Library), because a
/// second drawing of a muscle capsule is how a hue or a padding comes to
/// differ between two screens.
struct MuscleTagRow: View {
    let muscles: [LandmarkMuscle]

    var body: some View {
        // Wrapping, not an `HStack`: at AX5 a row of capsules on one line
        // becomes a row of vertical blobs one letter wide.
        FlowRow(spacing: OnyxSpace.xs) {
            ForEach(muscles, id: \.self) { muscle in
                let tint = Color.onyx.muscle(muscle)
                Text(muscle.displayName)
                    .onyxType(.micro)
                    .foregroundStyle(tint)
                    .padding(.horizontal, OnyxSpace.s)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.16), in: .capsule)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The masthead's day wash: 22 %→0 of the split's hue over the top 72 pt.
    ///
    /// ── WHY A WASH AND NOT A COLOURED CARD ──────────────────────────────────
    /// A tinted panel makes the glass under it read as a different material and
    /// puts a hard edge across the top of the screen — the "gradient header"
    /// look the whole mandate exists to avoid. A 22 %→0 wash behind transparent
    /// content says the same thing (this is a leg day) and leaves the surface
    /// alone. The title carries the same hue at full strength, which is where
    /// the colour is actually legible.
    ///
    /// Applied INSIDE `onyxGlass(.tile)`, always: the glass clips it to the
    /// card's own corner, and a wash outside that clip paints a rectangle with
    /// square corners behind a rounded card.
    ///
    /// Not `onyxMuscleWash` (OnyxUI), which is a different fact: that one is
    /// 6 %→2 % of a MOVEMENT's family over a whole card, plus a 3 pt rail. This
    /// is a session's DAY, at the head of the card and nowhere else.
    func sessionDayWash(_ dayKey: String?) -> some View {
        onyxTopWash(Color.onyx.day(dayKey))
    }

    /// The masthead wash with the hue named by the caller — the same 22 %→0
    /// over the same 72 pt, and deliberately not a second gradient.
    ///
    /// A week banner in the Library is the same object as a session masthead
    /// (hero label, tags, totals, a wash at the head of a tile) wearing a
    /// PHASE's colour instead of a split's, and a copied `LinearGradient` is
    /// how the two come to differ by two points or four percent for the half
    /// second a reader is looking at exactly that difference. One wash, two
    /// callers, one number to change.
    func onyxTopWash(_ tint: Color) -> some View {
        background(alignment: .top) {
            LinearGradient(
                colors: [tint.opacity(0.22), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 72)
        }
    }
}
