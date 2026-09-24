import SwiftUI
import WidgetKit
import OnyxCore
import OnyxUI

// MARK: - The two complications that are not tiles (overhaul A2, decision Q5)
//
// Heart Rate and Next Dose have no `WidgetId` and no `AccessoryFace` case on
// purpose: a new `WidgetId` reaches the phone's layout goldens and its widget
// picker (Lane B's files), and neither reading exists on the phone's Home
// Screen. So they are drawn here, in the one target that shows them, with the
// same four families and the same full-colour-only tint rule `AccessoryFace`
// follows (the system flattens colour on an accented face anyway).

struct HeartRateComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LastHeartRate.widgetKind, provider: HeartRateProvider()) { entry in
            HeartRateFace(reading: entry.reading)
        }
        .configurationDisplayName("Heart Rate")
        .description("The last heart rate this watch measured, and how long ago.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct HeartRateEntry: TimelineEntry {
    let date: Date
    let reading: LastHeartRate?
}

/// One entry. The age is drawn by the system (`Text(_:style: .relative)`), so
/// the face stays right without a timeline of future entries; the watch app
/// reloads this kind when it saves a new reading.
struct HeartRateProvider: TimelineProvider {
    func placeholder(in context: TimelineProviderContext) -> HeartRateEntry {
        HeartRateEntry(date: Date(), reading: nil)
    }

    func getSnapshot(in context: TimelineProviderContext, completion: @escaping (HeartRateEntry) -> Void) {
        completion(HeartRateEntry(date: Date(), reading: LastHeartRate.load()))
    }

    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<HeartRateEntry>) -> Void) {
        completion(Timeline(entries: [HeartRateEntry(date: Date(), reading: LastHeartRate.load())], policy: .never))
    }
}

/// The heart is the FIXED heart ink in every theme (decision Q19) — red, never
/// the theme's accent.
struct HeartRateFace: View {
    let reading: LastHeartRate?
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    private var tint: Color? { mode == .fullColor ? OnyxInk.Fixed.heart : nil }
    private var bpm: String { reading.map { "\($0.bpm)" } ?? "—" }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label(reading.map { "\($0.bpm) bpm" } ?? "No heart rate", systemImage: "heart.fill")
            case .accessoryRectangular:
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(tint ?? .primary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reading.map { "\($0.bpm) bpm" } ?? "No reading yet")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                        if let reading {
                            Text(reading.at, style: .relative)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            #if os(watchOS)
            case .accessoryCorner:
                Image(systemName: "heart.fill")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(tint ?? .primary)
                    .widgetLabel("\(bpm) bpm")
            #endif
            default:
                VStack(spacing: 1) {
                    Image(systemName: "heart.fill")
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(tint ?? .primary)
                    Text(bpm)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(reading.map { "\($0.bpm) beats per minute" } ?? "no reading")
    }
}

// MARK: - Next Dose

struct NextDoseComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnyxWatch.nextDose", provider: NextDoseProvider()) { entry in
            NextDoseFace(dose: entry.dose)
        }
        .configurationDisplayName("Next Dose")
        .description("The next supplement in today's stack, and when.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct NextDoseEntry: TimelineEntry {
    let date: Date
    let dose: WatchTiles.NextDose?
}

/// Now, the dose's own time (when it stops being NEXT — the face then says
/// nothing is queued until the phone pushes the one after), and midnight.
struct NextDoseProvider: TimelineProvider {
    func placeholder(in context: TimelineProviderContext) -> NextDoseEntry {
        NextDoseEntry(date: Date(), dose: nil)
    }

    func getSnapshot(in context: TimelineProviderContext, completion: @escaping (NextDoseEntry) -> Void) {
        completion(NextDoseEntry(date: Date(), dose: dose(at: Date())))
    }

    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<NextDoseEntry>) -> Void) {
        let now = Date()
        let midnight = WatchMidnight.next(after: now)
        var entries = [NextDoseEntry(date: now, dose: dose(at: now))]
        if let due = entries[0].dose?.at, due < midnight { entries.append(NextDoseEntry(date: due, dose: nil)) }
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }

    private func dose(at date: Date) -> WatchTiles.NextDose? {
        guard let dose = WatchTiles.load()?.current(on: LogicalDay.iso(date))?.nextDose, dose.at > date else { return nil }
        return dose
    }
}

struct NextDoseFace: View {
    let dose: WatchTiles.NextDose?
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    private var tint: Color? { mode == .fullColor ? OnyxInk.Themed.accent : nil }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                if let dose {
                    Label { Text("\(dose.name) · ") + Text(dose.at, style: .time) } icon: { Image(systemName: "pills.fill") }
                } else {
                    Label("Stack done", systemImage: "pills.fill")
                }
            case .accessoryRectangular:
                HStack(spacing: 6) {
                    Image(systemName: "pills.fill")
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(tint ?? .primary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(dose?.name ?? "Stack done")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let dose {
                            Text(dose.at, style: .time)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Nothing left today")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            #if os(watchOS)
            case .accessoryCorner:
                Image(systemName: "pills.fill")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(tint ?? .primary)
                    .widgetLabel { dose.map { Text($0.at, style: .time) } ?? Text("Done") }
            #endif
            default:
                VStack(spacing: 1) {
                    Image(systemName: "pills.fill")
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(tint ?? .primary)
                    if let dose {
                        Text(dose.at, style: .time)
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    } else {
                        Text("—").font(.system(.caption2, design: .rounded, weight: .semibold))
                    }
                }
            }
        }
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next dose")
        .accessibilityValue(dose.map { "\($0.name) at \($0.at.formatted(date: .omitted, time: .shortened))" } ?? "nothing left today")
    }
}
