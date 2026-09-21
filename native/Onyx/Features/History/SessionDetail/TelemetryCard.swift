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
/// its two captions. The chart under them is the series with each movement's
/// stretch washed in that movement's own muscle colour (the sixteen the atlas
/// uses, so a chest press is the same coral here as on the body) and a
/// `RuleMark` at each boundary naming it. Rests after the last set, and every
/// paused interval, are the thin tertiary line with no wash: the gaps.
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

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var reading: SessionTelemetry.Reading?
    @State private var names: [String: String] = [:]
    @State private var loaded = false

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
        if let kcal { parts.append("\(kcal) kcal") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func spoken(_ reading: SessionTelemetry.Reading) -> String {
        var parts: [String] = []
        if let a = avg(reading) { parts.append("average \(a) beats per minute") }
        if let p = reading.maxBpm { parts.append("peak \(p)") }
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
            "Heart rate", domain: .train, headline: headline(reading), caption: caption(reading),
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
        let numbers = Dictionary(labelled(reading).map { ($0.segment.id, $0.number) }, uniquingKeysWith: { a, _ in a })
        // The gaps: every bucket no segment claims — rests after the last
        // set, paused minutes — as one tertiary line. The washed stretches
        // draw their own line, so nothing is drawn twice.
        let gaps = samples.filter { s in !reading.segments.contains { s.at >= $0.start && s.at < $0.end } }
        return Chart {
            ForEach(gaps, id: \.at) { s in
                LineMark(x: .value("Time", s.at), y: .value("bpm", s.bpm), series: .value("Series", "gaps"))
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
            }
            ForEach(reading.segments) { segment in
                let tint = colour(for: segment.exerciseId)
                let inside = samples.filter { $0.at >= segment.start && $0.at < segment.end }
                ForEach(inside, id: \.at) { s in
                    AreaMark(x: .value("Time", s.at), y: .value("bpm", s.bpm), series: .value("Series", segment.id))
                        .foregroundStyle(
                            LinearGradient(colors: [tint.opacity(0.30), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                        )
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", s.at), y: .value("bpm", s.bpm), series: .value("Series", segment.id))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
                // One rule per movement, at the start of its FIRST piece. A
                // second piece after a pause continues the same movement.
                // The NAMES are the legend above the plot: five of them on
                // the plot's top edge collided into one line, and a chart
                // whose labels cannot be read is a chart with no labels.
                if !segment.continues {
                    RuleMark(x: .value("Start", segment.start))
                        .foregroundStyle(Color.onyx.hairline)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        // One digit, matched to the legend: a character cannot
                        // collide the way five names did.
                        .annotation(position: .top, alignment: .leading, spacing: 2) {
                            Text("\(numbers[segment.id] ?? 0)")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(tint)
                                .padding(.horizontal, 3)
                        }
                }
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: axisStride(samples))) { _ in
                AxisGridLine().foregroundStyle(Color.onyx.hairline)
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(OnyxChart.axisFont)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
        }
        .chartLegend(.hidden)
        .onyxChart(.train)
    }

    /// The movements in the order they were under the bar, each in its wash.
    /// `FlowRow` wraps, so a five-movement session takes two lines and every
    /// name stays whole. A movement split by a pause is named once.
    private func legend(_ reading: SessionTelemetry.Reading) -> some View {
        FlowRow(spacing: OnyxSpace.s) {
            ForEach(labelled(reading), id: \.segment.id) { entry in
                HStack(spacing: 4) {
                    // The number is the signal the colour alone is not: two
                    // chest movements share a hue by design, and the lat and
                    // upper-back teals are one teal at seven points.
                    Text("\(entry.number)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(colour(for: entry.segment.exerciseId))
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

    /// Ten-minute marks on an hour, five on a short session.
    private func axisStride(_ samples: [HRSample]) -> Int {
        guard let first = samples.first?.at, let last = samples.last?.at else { return 10 }
        return last.timeIntervalSince(first) > 35 * 60 ? 10 : 5
    }

    // MARK: - AX5: the numbers only

    private func numbers(_ reading: SessionTelemetry.Reading) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            Text("HEART RATE")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(OnyxDomain.train.accent)
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
        OnyxChartCard("Heart rate", domain: .train, headline: "—") {
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

    /// The movement's PRIMARY mover, in the atlas's own colour. A movement the
    /// map cannot place — a treadmill bout, an unknown name — takes the train
    /// accent rather than a colour that means a muscle.
    private func colour(for exerciseId: String) -> Color {
        let name = name(for: exerciseId)
        guard let token = MuscleMap.movers(name)?.primary.first,
              let muscle = LandmarkMuscle.from(token: token)
        else { return OnyxDomain.train.accent }
        return Color.onyx.muscle(muscle)
    }
}
