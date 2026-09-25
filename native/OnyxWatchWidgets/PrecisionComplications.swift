import SwiftUI
import WidgetKit
import OnyxCore
import OnyxUI

// MARK: - Three complications (Precision D4)
//
// Live Heart, Readiness & Sleep, Water & Food. New kinds beside the six that
// shipped — none of those changes its `kind:` string, so every placed face
// keeps its complication. Like Heart Rate and Next Dose they have no
// `WidgetId`: a new id reaches the phone's layout goldens and its picker, and
// none of these three exists on the phone. Every timeline carries the
// midnight entry (the day-scoped faces say "—" past it, `current(on:)`), and
// colour appears only in full-colour mode, as `AccessoryFace` rules.

// MARK: Live Heart

struct LiveHeartComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HeartTrail.widgetKind, provider: LiveHeartProvider()) { entry in
            LiveHeartFace(entry: entry)
        }
        .configurationDisplayName("Live Heart")
        .description("Your heart rate now, and the day's rhythm in six blocks.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LiveHeartEntry: TimelineEntry {
    let date: Date
    let heart: LastHeartRate?
    /// Six four-hour blocks, oldest first, as of `date`.
    let blocks: [Int?]
}

/// Now; every hour until midnight, because the six blocks are relative to the
/// entry's date and a face reloaded at 08:00 must not draw the 08:00 day at
/// 14:00 (review); the moment the reading goes stale (`WatchHeart.freshFor`);
/// and midnight. The watch app reloads this kind when the rate or the trail
/// moves outside a session.
struct LiveHeartProvider: TimelineProvider {
    func placeholder(in context: TimelineProviderContext) -> LiveHeartEntry {
        LiveHeartEntry(date: Date(), heart: nil, blocks: Array(repeating: nil, count: 6))
    }

    func getSnapshot(in context: TimelineProviderContext, completion: @escaping (LiveHeartEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<LiveHeartEntry>) -> Void) {
        let now = Date()
        let midnight = WatchMidnight.next(after: now)
        var dates = [now]
        var hour = now.addingTimeInterval(3600)
        while hour < midnight { dates.append(hour); hour.addTimeInterval(3600) }
        if let at = LastHeartRate.load()?.at.addingTimeInterval(WatchHeart.freshFor), at > now, at < midnight {
            dates.append(at)
        }
        dates.append(midnight)
        completion(Timeline(entries: dates.sorted().map(entry(at:)), policy: .after(midnight)))
    }

    private func entry(at date: Date) -> LiveHeartEntry {
        LiveHeartEntry(
            date: date, heart: LastHeartRate.load(),
            blocks: (HeartTrail.load() ?? HeartTrail()).blocks(now: date)
        )
    }
}

struct LiveHeartFace: View {
    let entry: LiveHeartEntry
    @Environment(\.widgetRenderingMode) private var mode

    private var tint: Color { mode == .fullColor ? OnyxInk.Fixed.heart : .primary }
    private var fresh: Bool { WatchHeart.freshness(entry.heart, now: entry.date) == .fresh }

    var body: some View {
        let known = entry.blocks.compactMap { $0 }
        let lo = known.min() ?? 0, hi = known.max() ?? 0
        ZStack {
            // The day as six arcs around the rate, a clock face of 24 hours:
            // the oldest block leaves 12 o'clock, the newest arrives back at
            // it — now is always the top. Brightness is the block's
            // mean against the day's own range; an unmeasured block is the
            // faint track alone.
            ForEach(0..<entry.blocks.count, id: \.self) { i in
                let from = Double(i) / Double(entry.blocks.count) + 0.012
                let to = Double(i + 1) / Double(entry.blocks.count) - 0.012
                let level = entry.blocks[i].map { hi > lo ? Double($0 - lo) / Double(hi - lo) : 1 }
                Circle()
                    .trim(from: from, to: to)
                    .stroke(tint.opacity(level.map { 0.35 + 0.65 * $0 } ?? 0.15),
                            style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            .padding(1.5)
            VStack(spacing: 0) {
                Image(systemName: "heart.fill")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(tint)
                Text(entry.heart.map { "\($0.bpm)" } ?? "—")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    // A rate from before lunch is still the last one, but not
                    // one to read as now.
                    .opacity(fresh ? 1 : 0.5)
            }
            .padding(6)
        }
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(entry.heart.map { "\($0.bpm) beats per minute" + (fresh ? "" : ", not recent") } ?? "no reading")
    }
}

// MARK: Readiness & Sleep

struct ReadinessSleepComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnyxWatch.readinessSleep", provider: WatchTileProvider()) { entry in
            ReadinessSleepFace(tiles: entry.tiles)
        }
        .configurationDisplayName("Readiness & Sleep")
        .description("Today's readiness score and last night's sleep.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct ReadinessSleepFace: View {
    let tiles: WatchTiles?
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.medium")
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(mode == .fullColor ? OnyxInk.Themed.accent : .primary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Readiness \(tiles?.score.map { "\($0)" } ?? "—")")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Label {
                    Text(tiles?.sleepMin.map { "Slept \(OnyxSnapshot.formatSleep($0))" } ?? "No night recorded")
                } icon: {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(mode == .fullColor ? OnyxInk.Fixed.sleepREM : .secondary)
                }
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(mode == .fullColor ? AnyShapeStyle(Color.onyx.textSecondary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness and sleep")
        .accessibilityValue((tiles?.score.map { "readiness \($0)" } ?? "not scored")
                            + (tiles?.sleepMin.map { ", slept \(OnyxSnapshot.formatSleep($0))" } ?? ""))
    }
}

// MARK: Water & Food

struct WaterFoodComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnyxWatch.waterFood", provider: WatchTileProvider()) { entry in
            WaterFoodFace(tiles: entry.tiles)
        }
        .configurationDisplayName("Water & Food")
        .description("Water against today's goal, and the calories left.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct WaterFoodFace: View {
    let tiles: WatchTiles?
    @Environment(\.widgetRenderingMode) private var mode

    private var level: Double {
        WatchTiles.progress(tiles?.waterMl, tiles?.waterGoalMl) ?? 0
    }

    private var water: String {
        guard let ml = tiles?.waterMl else { return "No water yet" }
        let l = String(format: "%.1f", Double(ml) / 1000)
        return tiles?.waterGoalMl.map { "\(l) of " + String(format: "%.1f", Double($0) / 1000) + " L" } ?? "\(l) L"
    }

    private var food: String {
        guard let left = tiles?.kcalRemaining else { return tiles?.kcal.map { "\($0) kcal" } ?? "No food yet" }
        return left >= 0 ? "\(left) kcal left" : "\(-left) kcal over"
    }

    var body: some View {
        HStack(spacing: 6) {
            WaterJug(level: level, ink: mode == .fullColor ? OnyxInk.Fixed.water : .primary)
                .frame(width: 16, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(water)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(food)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(mode == .fullColor ? AnyShapeStyle(Color.onyx.textSecondary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Water and food")
        .accessibilityValue("\(water), \(food)")
    }
}

/// The pitcher at complication size: an outline and a level. The app's
/// `WristPitcher` draws the full figure; the two live in two targets that
/// share no source, and W-final is asked to lift one copy into OnyxUI.
private struct WaterJug: View {
    let level: Double
    let ink: Color

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                Rectangle().fill(ink)
                    .frame(height: h * 0.9 * min(1, max(0, level)))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .clipShape(Jug())
                Jug().stroke(ink.opacity(0.8), lineWidth: 1.2)
            }
        }
        .accessibilityHidden(true)
    }

    private struct Jug: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX + r.width * 0.05, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.78, y: r.minY + r.height * 0.05))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.1))
            p.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.12, y: r.maxY),
                           control: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.12, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - r.height * 0.1),
                           control: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.15))
            p.closeSubpath()
            return p
        }
    }
}
