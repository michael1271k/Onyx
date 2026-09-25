import SwiftUI
import WidgetKit
import OnyxCore
import OnyxUI

/// The watch's complications and its live-workout card.
///
/// ── SIX COMPLICATIONS, NOT TEN (overhaul A2, decision Q5) ───────────────────
/// Readiness, Workout, Water, Sleep, Heart Rate and Next Dose. The first four
/// keep the `kind:` strings they shipped with (`OnyxWatch.recovery`,
/// `.train`, `.water`, `.sleep`), so a face that already wears one keeps it.
/// Heart Rate (`OnyxWatch.heartRate`) and Next Dose (`OnyxWatch.nextDose`) are
/// new kinds. Removed — and every placed copy of them with them, which is why
/// the changelog names them: `OnyxWatch.fuel`, `.steps`, `.bedtime`,
/// `.stress`, `.soreness`, `.weekRings`. Their faces still draw on the
/// dashboard pages and the phone's Lock Screen; only the watch-face kinds
/// went.
///
/// ── NESTED BUNDLES, STILL ───────────────────────────────────────────────────
/// `@WidgetBundleBuilder` caps at ten ELEMENTS and a nested bundle is one
/// element (W4) — kept, so a later complication costs nothing.
///
/// ── WHERE THE NUMBERS COME FROM ─────────────────────────────────────────────
/// The four tile kinds read `WatchTiles` — the phone's, parked in the App
/// Group suite by the watch app — through `OnyxTile.accessory`, the SAME view
/// the phone's Lock Screen draws. Heart Rate reads `LastHeartRate`, the one
/// reading only this wrist takes; Next Dose reads `WatchTiles.nextDose`.
///
/// ⚠️ `kind:` strings are load-bearing: a kind that disappears takes every
/// placed complication with it.
@main
struct OnyxWatchWidgets: WidgetBundle {
    /// The palette before any view is built. `load` is the one read of the
    /// suite the watch app writes (`OnyxTheme.save(…, to: WatchTiles.defaults())`).
    init() {
        MainActor.assumeIsolated {
            OnyxTheme.load(WatchTiles.defaults())
        }
    }

    @WidgetBundleBuilder
    var body: some Widget {
        WatchComplications().body
        WatchLive().body
    }
}

/// The watch-face complications. A sub-bundle, so the root counts them as ONE
/// of its ten elements.
struct WatchComplications: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        RecoveryComplication()
        TrainComplication()
        WaterComplication()
        SleepComplication()
        HeartRateComplication()
        NextDoseComplication()
        // Precision D4 — three new kinds; nine of the ten elements.
        LiveHeartComplication()
        ReadinessSleepComplication()
        WaterFoodComplication()
    }
}

/// The Smart Stack card.
struct WatchLive: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        WorkoutLiveWidget()
    }
}

// MARK: - One kind per id
//
// One struct per kind, because `Widget` requires `init()` — a `WidgetBundle`
// constructs its members itself, so the id has to be in the TYPE.

struct RecoveryComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.recovery) } }
struct TrainComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.train) } }
struct WaterComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.water) } }
struct SleepComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.sleep) } }

/// `OnyxWatch.<rawValue>` — namespaced so a phone kind and a watch kind can
/// never collide in a log, and stable across renames of the title.
@MainActor
private func tileConfiguration(_ id: WidgetId) -> some WidgetConfiguration {
    StaticConfiguration(kind: "OnyxWatch.\(id.rawValue)", provider: WatchTileProvider()) { entry in
        WatchTileFace(id: id, entry: entry)
    }
    .configurationDisplayName(id == .train ? "Workout" : id == .recovery ? "Readiness" : id.title)
    .description(description(for: id))
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
}

/// One line in the watch-face editor's gallery.
private func description(for id: WidgetId) -> String {
    switch id {
    case .recovery: "Today's battery and readiness score."
    case .train: "Today's session — due, done or a rest day."
    case .water: "Water logged against today's goal."
    case .sleep: "Last night's hours and sleep score."
    default: id.title
    }
}

/// The family is read here rather than in the package: `widgetFamily` is a
/// real value inside WidgetKit and a get-only default outside it.
struct WatchTileFace: View {
    let id: WidgetId
    let entry: WatchTileEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        OnyxTile.accessory(id, family: family, tiles: entry.tiles)
    }
}

// MARK: - Timeline

struct WatchTileEntry: TimelineEntry {
    let date: Date
    let tiles: WatchTiles?
}

/// Two entries: now, and the next local midnight.
///
/// ── THE STALE FACE AFTER MIDNIGHT (overhaul A2) ─────────────────────────────
/// This was one entry and `.never`, on the reasoning that the watch app
/// reloads every timeline when a push lands. But the phone does not push AT
/// midnight unless it is awake then, and the face kept saying yesterday's
/// session was due, yesterday's water, yesterday's sleep, until the phone next
/// ran. The midnight entry draws the tiles through `current(on:)` — nil once
/// they are yesterday's, so the face says "—" — and the policy asks again
/// after it. The watch app ALSO reloads at its own midnight (`WatchModel`),
/// for the case the system spends the entry late.
struct WatchTileProvider: TimelineProvider {
    // `TimelineProviderContext` spelled out: OnyxCore exports a `Context` (the
    // nutrition one) that shadows `Self.Context` here.
    func placeholder(in context: TimelineProviderContext) -> WatchTileEntry {
        WatchTileEntry(date: Date(), tiles: nil)
    }

    func getSnapshot(in context: TimelineProviderContext, completion: @escaping (WatchTileEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<WatchTileEntry>) -> Void) {
        let now = Date()
        let midnight = WatchMidnight.next(after: now)
        completion(Timeline(entries: [entry(at: now), entry(at: midnight)], policy: .after(midnight)))
    }

    private func entry(at date: Date) -> WatchTileEntry {
        // The suite is looked up twice rather than passed across the
        // `assumeIsolated` boundary: `UserDefaults` is not `Sendable`.
        MainActor.assumeIsolated { OnyxTheme.load(WatchTiles.defaults()) }
        return WatchTileEntry(date: date, tiles: WatchTiles.load()?.current(on: LogicalDay.iso(date)))
    }
}

/// The next local 00:00 — DST-aware, the phone's own rule (`AppEnvironment`).
enum WatchMidnight {
    static func next(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
            ?? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
            ?? date.addingTimeInterval(3600)
    }
}
