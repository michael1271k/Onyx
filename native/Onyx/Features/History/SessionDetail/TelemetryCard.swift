import SwiftUI
import Charts
import OnyxUI
import OnyxCore
import OnyxData

/// The session's heart rate, cut into the movements it was under.
/// Expansion W5, founder decision 10.
///
/// ── ONE CHART, ONE HERO, TWO CAPTIONS ───────────────────────────────────────
/// The average is the hero — it is the number the session row stores and the
/// one the finish sheet's cell already shows — and the peak and the burn are
/// its two captions. The chart under them is the series, each movement's
/// stretch washed and a dashed `RuleMark` at each boundary. Rests after the
/// last set, and every paused interval, are the thin tertiary line with no
/// wash: the gaps.
///
/// ── ONE COLOUR, AND THE MOVEMENTS ON THE AXIS (W3, founder decision 3) ─────
/// It washed each stretch in its movement's MUSCLE colour, from
/// `MuscleMap.movers`. That drew a heart rate in sixteen hues that mean
/// "chest", "lats" and "quads" everywhere else in the app — a claim about
/// anatomy on a chart about a pulse. It is now `OnyxDomain.recover.accent`
/// alone, red under the default theme and whatever each Appearance preset
/// makes it, and neighbouring movements are told apart by OPACITY steps of
/// that one ink (`step`). The number is still the signal colour cannot be.
///
/// The x axis stopped being the wall clock. "18:40" answered a question
/// nobody asks of a heart rate after a workout; "which movement was that
/// spike" is the one they do. Each movement's number sits under the middle
/// of its first stretch and the legend names it — numbers in full ink, since
/// they are the names and the faintest step is not legible as text. Names on the axis were tried in W5 and collided into one line — the
/// reason the legend exists.
///
/// The y axis is hidden until the plot is tapped. The SHAPE is the reading
/// here; the average and the peak are already the hero and its caption, so
/// a bpm scale is a detail you ask for, not one the card wears.
///
/// ── AND IT IS NOT ON THE PAGE UNTIL ASKED FOR (W3) ──────────────────────────
/// Both surfaces that drew it inline — the finish sheet and the session page
/// — now draw it in `heartRatePanel`, which slides it up from the bottom when
/// the Avg HR reading is tapped. See that modifier.
///
/// ── IT NEVER HOLDS THE SCREEN ───────────────────────────────────────────────
/// A skeleton until the actor answers, then either the card or nothing at all:
/// a phone-only session with no watch on the wrist has no series, and a card
/// saying so on every finish sheet would be an empty state on the one screen
/// that is supposed to be a summary. The `.task` keys on the environment's
/// `telemetryGeneration`, so a chart that opened empty fills in when the
/// watch's samples land during the ten-minute late window.
///
/// AX5: the chart's labels would be three lines each and the boundaries
/// unreadable, so the accessibility sizes keep the three numbers only.
struct TelemetryCard: View {
    let sessionId: String
    /// The store's MEASURED average, which outranks the series' own mean —
    /// the two agree when the watch ran the session, and when it did not,
    /// the stored figure is what the rest of the app prints.
    let storedAvgBpm: Int?
    let kcal: Int?
    /// Told, once the actor answers, whether there is a series to draw — the
    /// Avg HR reading only opens the panel when there is one (W3).
    var onLoad: ((Bool) -> Void)? = nil

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var reading: SessionTelemetry.Reading?
    /// Apple's one-minute recovery (W6) — its own read, so a cached series
    /// draws without waiting on Health for it.
    @State private var recovery: Int?
    @State private var names: [String: String] = [:]
    @State private var loaded = false
    /// The bpm scale, shown on a tap of the plot.
    @State private var showScale = false

    var body: some View {
        Group {
            if !loaded {
                skeleton
            } else if let reading, !reading.isEmpty {
                if typeSize.isAccessibilitySize {
                    numbers(reading)
                } else {
                    card(reading)
                }
            }
        }
        .task(id: environment.telemetryGeneration) {
            let telemetry = environment.telemetry
            let database = environment.database
            let next = await telemetry.reading(sessionId: sessionId)
            if names.isEmpty {
                // A full-table read; off the main actor like the page's own.
                names = await Task.detached(priority: .userInitiated) {
                    Dictionary(
                        ((try? database.exercises()) ?? []).map { ($0.id, $0.name) },
                        uniquingKeysWith: { first, _ in first }
                    )
                }.value
            }
            reading = next
            loaded = true
            onLoad?(!(next?.isEmpty ?? true))
            if next?.isEmpty == false { recovery = await telemetry.recoveryBpm(sessionId: sessionId) }
        }
    }

    // MARK: - The three numbers

    private func avg(_ reading: SessionTelemetry.Reading) -> Int? { storedAvgBpm ?? reading.avgBpm }

    private func headline(_ reading: SessionTelemetry.Reading) -> String {
        avg(reading).map { "\($0) bpm" } ?? "—"
    }

    private func caption(_ reading: SessionTelemetry.Reading) -> String? {
        var parts: [String] = []
        if let peak = reading.maxBpm { parts.append("Peak \(peak) bpm") }
        // Apple's one-minute recovery (W6) — the drop, so it reads as one.
        if let drop = recovery { parts.append("−\(drop) bpm in 1 min") }
        if let kcal { parts.append("\(kcal) kcal") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func spoken(_ reading: SessionTelemetry.Reading) -> String {
        var parts: [String] = []
        if let a = avg(reading) { parts.append("average \(a) beats per minute") }
        if let p = reading.maxBpm { parts.append("peak \(p)") }
        if let drop = recovery { parts.append("heart rate fell \(drop) beats per minute in the first minute after") }
        if let kcal { parts.append("\(kcal) kilocalories") }
        let order = labelled(reading).map { "\($0.number) \(shortName(for: $0.segment.exerciseId))" }
        if !order.isEmpty { parts.append("movements in order: " + order.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }

    /// The movements, numbered in the order they were under the bar. A piece
    /// that continues a movement after a pause keeps its number.
    private func labelled(_ reading: SessionTelemetry.Reading) -> [(number: Int, segment: HRSegment)] {
        var out: [(Int, HRSegment)] = []
        var n = 0
        for segment in reading.segments where !segment.continues {
            n += 1
            out.append((n, segment))
        }
        return out
    }

    /// One reading per fifteen seconds — the mean of the watch's five-second
    /// samples in each bucket. Display only: the numbers come from the actor
    /// over the raw series. Six hundred points across a 250 pt plot is two
    /// samples per pixel, and every edge came out a staircase.
    private static func bucketed(_ samples: [HRSample], seconds: TimeInterval = 15) -> [HRSample] {
        guard let first = samples.first else { return [] }
        var out: [HRSample] = []
        var bucketStart = first.at
        var sum = 0, count = 0
        for s in samples {
            if s.at.timeIntervalSince(bucketStart) >= seconds, count > 0 {
                out.append(HRSample(at: bucketStart.addingTimeInterval(seconds / 2), bpm: Int((Double(sum) / Double(count)).rounded())))
                bucketStart = s.at
                sum = 0; count = 0
            }
            sum += s.bpm; count += 1
        }
        if count > 0 {
            out.append(HRSample(at: bucketStart.addingTimeInterval(seconds / 2), bpm: Int((Double(sum) / Double(count)).rounded())))
        }
        return out
    }

    // MARK: - Default: the card

    private func card(_ reading: SessionTelemetry.Reading) -> some View {
        OnyxChartCard(
            "Heart rate", domain: .recover, headline: headline(reading), caption: caption(reading),
            legend: AnyView(legend(reading))
        ) {
            chart(reading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(spoken(reading))
    }

    private func chart(_ reading: SessionTelemetry.Reading) -> some View {
        let samples = Self.bucketed(reading.samples)
        let domain = yDomain(samples)
        let numbers = numbered(reading)
        // The gaps: every bucket no segment claims — rests after the last
        // set, paused minutes — as one tertiary line. The washed stretches
        // draw their own line, so nothing is drawn twice.
        let gaps = samples.filter { s in !reading.segments.contains { s.at >= $0.start && s.at < $0.end } }
        // One tick per movement, under the middle of its first stretch.
        let ticks = Dictionary(
            labelled(reading).map { ($0.segment.start.addingTimeInterval($0.segment.end.timeIntervalSince($0.segment.start) / 2), $0.number) },
            uniquingKeysWith: { first, _ in first }
        )
        return Chart {
            ForEach(gaps, id: \.at) { s in
                LineMark(x: .value("Time", s.at), y: .value("bpm", Double(s.bpm)), series: .value("Series", "gaps"))
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
            }
            ForEach(reading.segments) { segment in
                let tint = ink.opacity(Self.step(numbers[segment.id] ?? 1))
                let inside = samples.filter { $0.at >= segment.start && $0.at < segment.end }
                ForEach(inside, id: \.at) { s in
                    // From the plot's floor, not from 0: the domain starts
                    // near 80 bpm, and a wash filled from zero ran out under
                    // the axis numbers to the card's edge.
                    AreaMark(
                        x: .value("Time", s.at),
                        yStart: .value("floor", domain.lowerBound), yEnd: .value("bpm", Double(s.bpm)),
                        series: .value("Series", segment.id)
                    )
                        .foregroundStyle(
                            LinearGradient(colors: [tint.opacity(0.30), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                        )
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", s.at), y: .value("bpm", Double(s.bpm)), series: .value("Series", segment.id))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
                // One rule per movement, at the start of its FIRST piece. A
                // second piece after a pause continues the same movement.
                if !segment.continues {
                    RuleMark(x: .value("Start", segment.start))
                        .foregroundStyle(Color.onyx.hairline)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: ticks.keys.sorted()) { value in
                // Full ink: the number is what NAMES the movement, and the
                // faint step read under 3:1 as text.
                AxisValueLabel {
                    Text("\(value.as(Date.self).flatMap { ticks[$0] } ?? 0)")
                        .font(OnyxChart.axisFont.weight(.bold))
                        .foregroundStyle(ink)
                }
            }
        }
        // Before `onyxChart`, whose own `chartYAxis` would otherwise win —
        // its header says why the axis closest to the `Chart` is the one read.
        //
        // ── ALWAYS LAID OUT, SHOWN ON A TAP ─────────────────────────────────
        // `.chartYAxis(.hidden)` was the obvious spelling and it moved the
        // plot: revealing the labels took a column from it, so every movement
        // boundary slid left under the finger that asked for a scale. The axis
        // keeps its room and the ink comes and goes instead.
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(showScale ? Color.onyx.hairline : .clear)
                AxisValueLabel()
                    .font(OnyxChart.axisFont)
                    .foregroundStyle(showScale ? Color.onyx.textTertiary : .clear)
            }
        }
        .chartLegend(.hidden)
        .onyxChart(.recover)
        // Charts renders the axis LABELS once and keeps them: the grid
        // answered the tap and the numbers stayed clear. A new identity per
        // state rebuilds the axis; the room it takes never changes, so
        // nothing moves.
        .id(showScale)
        .contentShape(.rect)
        .onTapGesture { withAnimation(OnyxMotion.fade) { showScale.toggle() } }
    }

    /// The movements in the order they were under the bar, each in its wash.
    /// `FlowRow` wraps, so a five-movement session takes two lines and every
    /// name stays whole. A movement split by a pause is named once.
    private func legend(_ reading: SessionTelemetry.Reading) -> some View {
        FlowRow(spacing: OnyxSpace.s) {
            ForEach(labelled(reading), id: \.segment.id) { entry in
                HStack(spacing: 4) {
                    // The number is the signal: the movements share one ink by
                    // decision, and an opacity step alone is not a name.
                    Text("\(entry.number)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(ink)
                    Text(shortName(for: entry.segment.exerciseId))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        // Spoken through `spoken(_:)` on the card, in order, once.
        .accessibilityHidden(true)
    }

    /// A rounded domain with a little air under the floor, so a flat
    /// warm-up does not sit on the axis.
    private func yDomain(_ samples: [HRSample]) -> ClosedRange<Double> {
        let values = samples.map(\.bpm)
        guard let lo = values.min(), let hi = values.max() else { return 60...180 }
        let floor = Double((lo / 10) * 10 - 10)
        let ceiling = Double(((hi + 9) / 10) * 10 + 5)
        return max(30, floor)...max(ceiling, floor + 30)
    }

    /// Every segment's movement number, the continuing pieces included — a
    /// stretch after a pause is the same movement in the same step of ink.
    private func numbered(_ reading: SessionTelemetry.Reading) -> [String: Int] {
        var out: [String: Int] = [:]
        var n = 0
        for segment in reading.segments {
            if !segment.continues { n += 1 }
            out[segment.id] = max(1, n)
        }
        return out
    }

    // MARK: - AX5: the numbers only

    private func numbers(_ reading: SessionTelemetry.Reading) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            Text("HEART RATE")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(ink)
            Text(headline(reading))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.onyx.textPrimary)
            if let caption = caption(reading) {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OnyxChart.cardPadding)
        .onyxGlass(.tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(spoken(reading))
    }

    // MARK: - Skeleton

    /// Three bars in tertiary ink, the card's own shape, until the actor
    /// answers. Gone — not replaced — when the answer is "no samples".
    private var skeleton: some View {
        OnyxChartCard("Heart rate", domain: .recover, headline: "—") {
            HStack(alignment: .bottom, spacing: OnyxSpace.s) {
                ForEach([0.45, 0.7, 0.55], id: \.self) { fraction in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.onyx.textTertiary.opacity(0.12))
                        .frame(maxWidth: .infinity)
                        .frame(height: OnyxChart.plotHeight * fraction)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Names and colours

    private func name(for exerciseId: String) -> String {
        names[exerciseId] ?? exerciseId.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// The name without its parenthetical — "Seated Cable Row", not "(Wide
    /// Grip)". The full name is on the ledger card; the legend is a key.
    private func shortName(for exerciseId: String) -> String {
        let full = name(for: exerciseId)
        return full.components(separatedBy: " (").first ?? full
    }

    /// The chart's one colour (decision 3). Computed, not stored: the token
    /// follows the Appearance preset, and a `static let` would keep the first.
    private var ink: Color { OnyxDomain.recover.accent }

    /// Movement `n`'s opacity step of `ink`. Three steps, so neighbours always
    /// differ; the faintest was 0.45 and measured under 3:1 as a line on the
    /// card, so the floor is 0.55.
    static func step(_ n: Int) -> Double {
        [1.0, 0.75, 0.55][(max(1, n) - 1) % 3]
    }
}

// MARK: - The panel (W3)

extension View {
    /// The heart-rate chart, off the page until the Avg HR reading asks for it,
    /// then slid up from the bottom edge over a scrim.
    ///
    /// ── WHY A PANEL AND NOT A ROW ON THE PAGE ───────────────────────────────
    /// It was a full-width card on both surfaces, under the metric grid,
    /// 280 pt tall on a finish sheet whose job is to be put down in thirty
    /// seconds. The founder's rule is that it is there only when asked for,
    /// and the reading that asks is the one it explains: the average. One
    /// modifier, two callers, so the finish sheet and the session page open
    /// the same chart the same way.
    ///
    /// ── THE MOTION, AND WHY IT IS AN OFFSET AND NOT A TRANSITION ────────────
    /// `OnyxMotion.drawer` — Apple's sheet spring, damping 0.8 / response 0.3.
    /// The panel stays in the tree and its OFFSET is what animates, because an
    /// offset is a value a spring can retarget mid-flight: tap the scrim while
    /// it is still rising and it turns round from where it is, carrying its
    /// speed. An insert/remove transition cannot — a removal already in flight
    /// is a different view from the one a second tap inserts. It leaves by the
    /// edge it came from, it follows the finger 1:1 when dragged, and a drag
    /// that is heading down — `predictedEndTranslation`, the projected landing
    /// point rather than where the finger let go — sends it back there.
    ///
    /// Under Reduce Motion nothing slides: it cross-fades in place
    /// (`OnyxMotion.fade`, the 200 ms the motion vocabulary already names).
    ///
    /// Staying in the tree is also what lets the card's `.task` answer
    /// `available` before anybody taps — the Avg HR reading opens a panel only
    /// when there is a series to show in it.
    ///
    /// `onEdit` is the finish sheet's: its average is also an answer you can
    /// correct, and the tap that used to open that stepper now opens this.
    func heartRatePanel(
        isPresented: Binding<Bool>, available: Binding<Bool>,
        sessionId: String?, storedAvgBpm: Int?, kcal: Int?,
        onEdit: (() -> Void)? = nil
    ) -> some View {
        modifier(HeartRatePanel(
            isPresented: isPresented, available: available,
            sessionId: sessionId, storedAvgBpm: storedAvgBpm, kcal: kcal, onEdit: onEdit
        ))
    }
}

// ponytail: a general bottom panel (scrim, drag, spring offset, Reduce Motion)
// with one caller's parameters. Lift it into OnyxUI as `onyxPanel` when a
// second surface needs one — not before.
private struct HeartRatePanel: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var available: Bool
    let sessionId: String?
    let storedAvgBpm: Int?
    let kcal: Int?
    let onEdit: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The finger's pull, in points below the resting position.
    @State private var drag: CGFloat = 0

    private var motion: Animation { reduceMotion ? OnyxMotion.fade : OnyxMotion.drawer }

    func body(content: Content) -> some View {
        content
            // What is behind the scrim is behind it for VoiceOver too.
            .accessibilityHidden(isPresented)
            .overlay {
                Color.black
                    .opacity(isPresented ? 0.45 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(isPresented)
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                    .animation(motion, value: isPresented)
            }
            .overlay(alignment: .bottom) {
                if let sessionId { panel(sessionId) }
            }
    }

    private func panel(_ sessionId: String) -> some View {
        // Copied out: `visualEffect`'s closure runs off the main actor.
        let shown = isPresented, slides = !reduceMotion, pull = drag
        return VStack(spacing: OnyxSpace.s) {
            Capsule()
                .fill(Color.onyx.textTertiary)
                .frame(width: 36, height: 5)
                .accessibilityHidden(true)
            TelemetryCard(
                sessionId: sessionId, storedAvgBpm: storedAvgBpm, kcal: kcal,
                onLoad: { available = $0 }
            )
            if let onEdit {
                Button {
                    close()
                    onEdit()
                } label: {
                    Text("Edit the average")
                        .onyxType(.body).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Color.onyx.textSecondary)
            }
        }
        // ONE surface under the handle, the card and the action, anchored to
        // the bottom edge the way a sheet is: a floating card let the page
        // show beneath it, and its top edge — base on a dimmed base — read as
        // the page cut along a line. The hairline is that edge, stated.
        .padding(.top, OnyxSpace.s)
        .padding(.horizontal, OnyxSpace.m)
        .padding(.bottom, OnyxSpace.m)
        .frame(maxWidth: .infinity)
        .background {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: OnyxCorner.sheet, topTrailingRadius: OnyxCorner.sheet, style: .continuous
            )
            shape.fill(Color.onyx.base)
                .overlay(shape.stroke(Color.onyx.hairline, lineWidth: 1))
                .ignoresSafeArea(edges: .bottom)
        }
        .visualEffect { content, proxy in
            content.offset(y: shown ? pull : (slides ? proxy.size.height + 80 : 0))
        }
        .opacity(shown ? 1 : 0)
        .animation(motion, value: isPresented)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    let dy = value.translation.height
                    // Upward is resisted, not refused: a hard stop reads as a
                    // frozen panel, a quarter of the pull reads as the top.
                    drag = dy > 0 ? dy : dy / 4
                }
                .onEnded { value in
                    let dismiss = value.predictedEndTranslation.height > 160
                    withAnimation(motion) {
                        drag = 0
                        if dismiss { isPresented = false }
                    }
                }
        )
        .allowsHitTesting(shown)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(!shown)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
    }

    private func close() {
        withAnimation(motion) { isPresented = false }
    }
}
