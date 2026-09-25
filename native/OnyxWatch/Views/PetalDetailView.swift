import OnyxCore
import OnyxData
import OnyxUI
import SwiftUI

// MARK: - The six petal details (Precision D3, decision Q24 · design 12)
//
// ── WHAT A DETAIL IS FOR ────────────────────────────────────────────────────
// The Glance answers "which part of today is short" with a disc; the detail
// answers "by how much, and what is it made of" — one figure, one drawing,
// one line of context, on ONE screen at 40 mm (the Crown scrolls anything a
// larger Text Size pushes past it). Each is a `WatchSlab` in its petal's
// fixed ink, so the detail is visibly the petal you tapped, opened.
//
// ── THE DRAWINGS ARE THE PHONE'S, REDRAWN HERE ─────────────────────────────
// `DepthArc` and `PitcherFigure` live behind OnyxUI's iOS fence, in files no
// lane in this sprint owns. The wrist copies (`WristDepthArc`,
// `WristPitcher`) keep their rules — stage spans share the fill, the sweep
// caps at the goal, the pitcher is the fixed water blue — and the wave
// record asks W-final to lift the phone's two above the fence and delete
// these.

/// The pushed screen a petal opens.
struct PetalDetailView: View {

    let petal: PetalDetail
    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                let tiles = model.dashboardTiles
                switch petal {
                case .sleep: SleepDetail(tiles: tiles)
                case .water: WaterDetail(tiles: tiles)
                case .food: FoodDetail(tiles: tiles)
                case .heart: HeartDetail(vitals: model.vitals, restingBpm: tiles?.restingBpm)
                case .steps: StepsDetail(tiles: tiles)
                case .stress: StressDetail(tiles: tiles)
                }
            }
            .padding(.horizontal, OnyxSpace.xs)
        }
        .containerBackground(for: .navigation) { WatchInk.ground }
        .navigationTitle(petal.title)
        .navigationBarTitleDisplayMode(.inline)
        .dimmedWhenLuminanceReduced()
    }
}

/// The screen's one figure and its unit, on a shared baseline.
private struct DetailFigure: View {
    let value: String
    let unit: String?
    var ink: Color = WatchInk.primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(WatchType.figure)
                .foregroundStyle(ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let unit {
                Text(unit)
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A label and its figure, for the second line of a detail.
private struct DetailStat: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(WatchInk.secondary)
            Text(value).foregroundStyle(WatchInk.primary).monospacedDigit()
        }
        .font(WatchType.label)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// "1:11" — a stage, a night, where the space is four glyphs.
private func clock(_ minutes: Int) -> String {
    "\(minutes / 60):" + String(format: "%02d", minutes % 60)
}

// MARK: - Sleep

private struct SleepDetail: View {
    let tiles: WatchTiles?

    private var stages: [(OnyxSleepStage, Int)] {
        guard let raw = tiles?.sleepStages else { return [] }
        return zip(OnyxSleepStage.allCases, raw).compactMap { stage, m in m.map { (stage, $0) } }
    }

    var body: some View {
        WatchSlab(tint: OnyxInk.Fixed.sleepREM) {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                WristDepthArc(segments: stages, minutes: tiles?.sleepMin, goalMin: tiles?.sleepGoalMin)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                if !stages.isEmpty {
                    // One column a stage, the name over its time. Two by two
                    // with "Deep 1:11" on one line ellipsised every cell at
                    // 40 mm (round 1): 61 pt a cell against ~70 of text.
                    // One row of four where it fits; two by two with the
                    // ramp's dots (49 mm); two by two without them (40 mm —
                    // measured 136 pt with dots against 130, round 3). The
                    // names carry the key, the arc keeps the order.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                            ForEach(stages.indices, id: \.self) { i in legend(stages[i].0, stages[i].1) }
                        }
                        grid(dots: true)
                        // Two lines, each ONE `Text` that tightens as a unit:
                        // a Grid of cells at 40 mm ellipsised names even when
                        // the sums said they fitted (round 3).
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(0..<((stages.count + 1) / 2), id: \.self) { row in
                                pair(stages.indices.filter { $0 / 2 == row }.map { stages[$0] })
                                    .font(WatchType.label)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                        }
                    }
                }
                // The goal sits here, not in the bowl: "asleep · goal 8h00m"
                // is wider than the bowl at either case (round 1). One line
                // that may tighten, not two stats that ellipsise (round 2).
                if let line = bedLine {
                    line
                        .font(WatchType.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    /// "In bed 8:02 · Goal 8:00", labels secondary, figures primary.
    private var bedLine: Text? {
        var parts: [Text] = []
        if let inBed = tiles?.inBedMin {
            parts.append(Text("In bed ").foregroundStyle(WatchInk.secondary) + Text(clock(inBed)).foregroundStyle(WatchInk.primary))
        }
        if let goal = tiles?.sleepGoalMin {
            parts.append(Text("Goal ").foregroundStyle(WatchInk.secondary) + Text(clock(goal)).foregroundStyle(WatchInk.primary))
        }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { $0 + Text(" · ").foregroundStyle(WatchInk.secondary) + $1 }
    }

    private func grid(dots: Bool) -> some View {
        Grid(alignment: .leading, horizontalSpacing: OnyxSpace.s, verticalSpacing: 2) {
            ForEach(0..<((stages.count + 1) / 2), id: \.self) { row in
                GridRow {
                    ForEach(stages.indices.filter { $0 / 2 == row }, id: \.self) { i in
                        cell(stages[i].0, stages[i].1, dot: dots)
                    }
                }
            }
        }
    }

    /// "Deep 1:11 · Core 3:58" — names secondary, times primary.
    private func pair(_ two: [(OnyxSleepStage, Int)]) -> Text {
        let parts = two.map {
            Text($0.0.title + " ").foregroundStyle(WatchInk.secondary) + Text(clock($0.1)).foregroundStyle(WatchInk.primary)
        }
        guard let first = parts.first else { return Text("") }
        return parts.dropFirst().reduce(first) { $0 + Text(" · ").foregroundStyle(WatchInk.secondary) + $1 }
    }

    /// One line: (dot,) name, time — a two-by-two's cell.
    private func cell(_ stage: OnyxSleepStage, _ minutes: Int, dot: Bool) -> some View {
        HStack(spacing: 3) {
            if dot { Circle().fill(stage.color).frame(width: 5, height: 5) }
            Text(stage.title).foregroundStyle(WatchInk.secondary)
            Text(clock(minutes)).foregroundStyle(WatchInk.primary).monospacedDigit()
        }
        .font(WatchType.label)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private func legend(_ stage: OnyxSleepStage, _ minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(stage.title)
                .foregroundStyle(WatchInk.secondary)
                .minimumScaleFactor(0.75)
            HStack(spacing: 2) {
                Circle().fill(stage.color).frame(width: 5, height: 5)
                Text(clock(minutes)).foregroundStyle(WatchInk.primary).monospacedDigit()
            }
        }
        .font(WatchType.label)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// The night as a half ring: the sweep is asleep against the goal, the fill
/// split by stage in the fixed sleep ramp — `DepthArc`'s two answers, at a
/// wrist's size. Over-sleeping caps at full; a night with no stages is one
/// colour; no night at all is the track alone.
struct WristDepthArc: View {
    let segments: [(OnyxSleepStage, Int)]
    let minutes: Int?
    let goalMin: Int?
    var lineWidth: CGFloat = 7

    private var fill: Double? {
        guard let minutes, minutes > 0 else { return nil }
        return min(1, Double(minutes) / Double(goalMin ?? 480))
    }

    private var spans: [(from: Double, to: Double, color: Color)] {
        guard let fill else { return [] }
        let staged = segments.reduce(0) { $0 + $1.1 }
        guard staged > 0 else { return [(0, fill, OnyxInk.Fixed.sleepREM)] }
        var cursor = 0.0
        return segments.map { stage, m in
            let width = fill * Double(m) / Double(staged)
            defer { cursor += width }
            return (cursor, cursor + width, stage.color)
        }
    }

    var body: some View {
        GeometryReader { geo in
            // The drawn circle's top half is the arc; its stroke's ends hang
            // half a line below the diameter, so the height pays for that.
            let d = max(0, min(geo.size.width - lineWidth, (geo.size.height - lineWidth / 2) * 2))
            ZStack {
                Circle().trim(from: 0, to: 0.5)
                    .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(180))
                ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                    Circle().trim(from: 0.5 * span.from, to: 0.5 * span.to)
                        .stroke(span.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(180))
                }
            }
            .frame(width: d, height: d)
            .frame(width: d, height: d / 2 + lineWidth / 2, alignment: .top)
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    Text(minutes.map(OnyxSnapshot.formatSleep) ?? "—")
                        .font(WatchType.value)
                        .foregroundStyle(WatchInk.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("asleep")
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: d * 0.72)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement()
        .accessibilityLabel("Asleep")
        .accessibilityValue(
            (minutes.map(OnyxSnapshot.formatSleep) ?? "no night recorded")
                + (goalMin.map { ", goal \(OnyxSnapshot.formatSleep($0))" } ?? "")
        )
    }
}

// MARK: - Water

private struct WaterDetail: View {
    let tiles: WatchTiles?

    var body: some View {
        WatchSlab(tint: OnyxInk.Fixed.water) {
            HStack(spacing: OnyxSpace.s) {
                WristPitcher(ml: tiles?.waterMl.map(Double.init), goalMl: tiles?.waterGoalMl.map(Double.init))
                    .frame(width: 40, height: 50)
                VStack(alignment: .leading, spacing: 1) {
                    DetailFigure(value: tiles?.waterMl.map { String(format: "%.1f", Double($0) / 1000) } ?? "—", unit: "L")
                    Text(tiles?.waterGoalMl.map { "of " + String(format: "%.1f", Double($0) / 1000) + " L" } ?? "No goal")
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        WaterGlassButton()
    }
}

/// The day's water as a pitcher filling, in the fixed water blue — the
/// phone's `PitcherFigure` rule, at a wrist's size: the level is the day
/// against its goal, a lighter meniscus on the surface.
struct WristPitcher: View {
    let ml: Double?
    let goalMl: Double?

    /// `Glasses.level`'s rule: no goal is a level of nothing.
    private var level: Double {
        guard let goalMl, goalMl > 0 else { return 0 }
        return min(1, max(0, (ml ?? 0) / goalMl))
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = min(geo.size.width, h * 0.8)
            let top = h * (0.12 + 0.88 * (1 - level))
            ZStack(alignment: .topLeading) {
                PitcherJug().fill(Color.white.opacity(0.08))
                if level > 0 {
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(OnyxInk.Fixed.water).frame(height: h - top).offset(y: top)
                        Rectangle().fill(Color.white.opacity(0.45)).frame(height: 1.5).offset(y: top)
                    }
                    .frame(width: w, height: h, alignment: .topLeading)
                    .clipShape(PitcherJug())
                }
                PitcherJug().stroke(WatchInk.secondary, lineWidth: 1.5)
            }
            .frame(width: w, height: h)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// A jug: a rim a little narrower than its foot, a spout on the left and a
/// handle on the right, all one closed outline so the water clips to it.
private struct PitcherJug: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.minX + w * 0.04, y: r.minY + h * 0.02))            // spout lip
        p.addLine(to: CGPoint(x: r.minX + w * 0.70, y: r.minY + h * 0.06))         // rim
        p.addLine(to: CGPoint(x: r.minX + w * 0.70, y: r.minY + h * 0.16))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.70, y: r.minY + h * 0.62),        // handle
                   control1: CGPoint(x: r.maxX + w * 0.08, y: r.minY + h * 0.16),
                   control2: CGPoint(x: r.maxX + w * 0.08, y: r.minY + h * 0.62))
        p.addLine(to: CGPoint(x: r.minX + w * 0.76, y: r.maxY - h * 0.06))
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.64, y: r.maxY),
                       control: CGPoint(x: r.minX + w * 0.77, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + w * 0.12, y: r.maxY))                    // foot
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.00, y: r.maxY - h * 0.06),
                       control: CGPoint(x: r.minX - w * 0.01, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + w * 0.10, y: r.minY + h * 0.14))
        p.closeSubpath()
        return p
    }
}

// MARK: - Food

private struct FoodDetail: View {
    let tiles: WatchTiles?

    var body: some View {
        WatchSlab(tint: Color.onyx.calories) {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                DetailFigure(value: tiles?.kcal.map { $0.formatted() } ?? "—", unit: "kcal")
                Text(remaining)
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.secondary)
                    .lineLimit(1)
                if let energy = FoodSlab.energy(tiles) {
                    EnergyBar(energy: energy, height: 6)
                    // Grams on one line at 49 mm; at 40 mm the unit goes
                    // before any figure does (round 1 ellipsised all three).
                    ViewThatFits(in: .horizontal) {
                        macros(units: true, spacing: OnyxSpace.s)
                        macros(units: false, spacing: OnyxSpace.xs)
                    }
                }
            }
        }
    }

    private var remaining: String {
        guard let left = tiles?.kcalRemaining else { return tiles?.kcal == nil ? "No food yet" : "No target" }
        return left >= 0 ? "\(left.formatted()) left" : "\((-left).formatted()) over"
    }

    private func macros(units: Bool, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            macro("P", tiles?.proteinG, Color.onyx.protein, units: units)
            macro("C", tiles?.carbsG, Color.onyx.carbs, units: units)
            macro("F", tiles?.fatG, Color.onyx.fat, units: units)
        }
    }

    private func macro(_ letter: String, _ grams: Int?, _ ink: Color, units: Bool) -> some View {
        HStack(spacing: 2) {
            Circle().fill(ink).frame(width: 5, height: 5)
            Text(letter).foregroundStyle(WatchInk.secondary)
            Text(grams.map { units ? "\($0)g" : "\($0)" } ?? "—").foregroundStyle(WatchInk.primary).monospacedDigit()
        }
        .font(WatchType.label)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(letter == "P" ? "Protein" : letter == "C" ? "Carbs" : "Fat")
        .accessibilityValue(grams.map { "\($0) grams" } ?? "no reading")
    }
}

// MARK: - Heart

private struct HeartDetail: View {
    let vitals: WatchVitals
    let restingBpm: Int?

    var body: some View {
        WatchSlab(tint: OnyxInk.Fixed.heart) {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    DetailFigure(value: vitals.heart.map { "\($0.bpm)" } ?? "—", unit: "bpm")
                    Spacer(minLength: 0)
                    if let at = vitals.heart?.at {
                        Text(at, style: .time)
                            .font(WatchType.label)
                            .foregroundStyle(WatchInk.secondary)
                            .lineLimit(1)
                    }
                }
                VStack(spacing: 1) {
                    HeartSpark(trail: vitals.trail)
                        .frame(height: 30)
                    HStack {
                        Text("24 h ago")
                        Spacer(minLength: 0)
                        Text("now")
                    }
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.secondary)
                    .accessibilityHidden(true)
                }
                // One line with units (49 mm), one line without (40 mm);
                // two lines only past that — they cost the slab its bottom
                // edge at 40 mm (round 2).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: OnyxSpace.s) { stats(units: true) }
                    HStack(spacing: OnyxSpace.s) { stats(units: false) }
                    VStack(alignment: .leading, spacing: 1) { stats(units: false) }
                }
            }
        }
        // The live half of Q23: hear each sample while this is on screen,
        // and only then.
        .onAppear { vitals.startStream() }
        .onDisappear { vitals.stopStream() }
    }
}

private extension HeartDetail {
    @ViewBuilder func stats(units: Bool) -> some View {
        DetailStat(label: "Resting", value: restingBpm.map { "\($0)" } ?? "—")
        DetailStat(label: "HRV", value: vitals.hrv.map { units ? "\($0.ms) ms" : "\($0.ms)" } ?? "—")
    }
}

/// The last 24 hours, gap-aware: one line per run of samples, never a line
/// across a silence (`HeartTrail.runs`). Time on x, the day's own range on y.
private struct HeartSpark: View {
    let trail: HeartTrail

    var body: some View {
        TimelineView(.everyMinute) { tick in
            Canvas { ctx, size in
                let now = tick.date
                let start = now.addingTimeInterval(-HeartTrail.window)
                let bpms = trail.samples.map(\.bpm)
                guard let lo = bpms.min(), let hi = bpms.max() else {
                    var base = Path()
                    base.move(to: CGPoint(x: 0, y: size.height - 1))
                    base.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                    ctx.stroke(base, with: .color(.white.opacity(0.12)), lineWidth: 1)
                    return
                }
                let span = Double(max(hi - lo, 10))
                func point(_ s: HeartTrail.Sample) -> CGPoint {
                    let x = s.at.timeIntervalSince(start) / HeartTrail.window
                    let y = 1 - (Double(s.bpm - lo) + (span - Double(hi - lo)) / 2) / span
                    return CGPoint(x: size.width * x, y: 2 + (size.height - 4) * y)
                }
                for run in trail.runs() {
                    if run.count == 1 {
                        let p = point(run[0])
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)),
                                 with: .color(OnyxInk.Fixed.heart))
                        continue
                    }
                    var line = Path()
                    line.move(to: point(run[0]))
                    for s in run.dropFirst() { line.addLine(to: point(s)) }
                    ctx.stroke(line, with: .color(OnyxInk.Fixed.heart),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Heart rate, last 24 hours")
        .accessibilityValue(trail.samples.isEmpty ? "no readings"
            : "\(trail.samples.map(\.bpm).min() ?? 0) to \(trail.samples.map(\.bpm).max() ?? 0) beats per minute")
    }
}

// MARK: - Steps

private struct StepsDetail: View {
    let tiles: WatchTiles?

    var body: some View {
        WatchSlab(tint: nil) {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                DetailFigure(value: tiles?.steps.map { $0.formatted() } ?? "—", unit: "steps")
                Text(tiles?.stepsGoal.map { "of \($0.formatted())" } ?? "No goal")
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.secondary)
                    .lineLimit(1)
                if let week = tiles?.stepsWeek, let date = tiles?.date {
                    StepBars(week: week, goal: tiles?.stepsGoal, endingOn: date)
                        .frame(height: 50)
                }
            }
        }
    }
}

/// Seven days, oldest left, today lit. A day with no count has no bar — a
/// gap, never a zero. The goal is a dotted hairline, and in the scale, so a
/// week far short of it still shows how far.
private struct StepBars: View {
    let week: [Int?]
    let goal: Int?
    let endingOn: String

    private var letters: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        return (0..<week.count).map { i in
            guard let iso = ISODate.addDays(endingOn, i - (week.count - 1)),
                  let date = LogicalDay.date(fromISO: iso) else { return "" }
            return symbols[calendar.component(.weekday, from: date) - 1]
        }
    }

    var body: some View {
        let top = Double(max(week.compactMap { $0 }.max() ?? 0, goal ?? 0, 1))
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(week.indices, id: \.self) { i in
                            let lit = i == week.count - 1
                            Group {
                                if let n = week[i] {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(lit ? WatchInk.primary : WatchInk.secondary.opacity(0.55))
                                        .frame(width: 8, height: max(2, geo.size.height * Double(n) / top))
                                } else {
                                    Color.clear.frame(height: 2)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    if let goal, goal > 0 {
                        Path { p in
                            let y = geo.size.height * (1 - Double(goal) / top)
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(WatchInk.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                }
            }
            HStack(spacing: 4) {
                ForEach(letters.indices, id: \.self) { i in
                    Text(letters[i])
                        .font(WatchType.label)
                        .foregroundStyle(i == letters.count - 1 ? WatchInk.primary : WatchInk.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Steps, last seven days")
        .accessibilityValue(week.map { $0.map { "\($0)" } ?? "no count" }.joined(separator: ", "))
    }
}

// MARK: - Stress

private struct StressDetail: View {
    let tiles: WatchTiles?

    private var band: StressBand? { tiles?.stressIndex.map(Stress.band) }
    private var ink: Color { WatchInk.stress(band) }

    var body: some View {
        WatchSlab(tint: ink) {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                DetailFigure(value: tiles?.stressIndex.map { "\(Int($0.rounded()))" } ?? "—", unit: "of 100", ink: ink)
                Text(band.flatMap { Stress.bandLabel($0) ?? $0.rawValue.capitalized } ?? "No reading today")
                    .font(WatchType.name)
                    .foregroundStyle(band == nil ? WatchInk.secondary : ink)
                    .lineLimit(1)
                if let last = lastRead {
                    Text(last)
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// "Last read today" / "Last read Tue".
    private var lastRead: String? {
        guard let iso = tiles?.stressLast, let date = LogicalDay.date(fromISO: iso) else { return nil }
        if iso == tiles?.date { return "Last read today" }
        return "Last read " + date.formatted(.dateTime.weekday(.abbreviated))
    }
}
