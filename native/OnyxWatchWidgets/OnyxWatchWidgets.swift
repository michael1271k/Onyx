import SwiftUI
import WidgetKit
import OnyxCore
import OnyxUI

/// The watch's complications (W7) and its live-workout card (W4).
///
/// Ten complication kinds, one per wearable `WidgetId`, every one a
/// `StaticConfiguration`: a complication has no picker on the wrist — the
/// FACE is the choice, made in the watch-face editor — so ten kinds is what
/// "every dashboard tile as a complication" means here, where on the phone it
/// is one kind with an intent.
///
/// ── ELEVEN, WITHOUT GIVING ONE UP (W4) ──────────────────────────────────────
/// `@WidgetBundleBuilder` caps at ten **elements**, and W7's note here read
/// that as ten widgets — so this wave was planned around picking a
/// complication to delete. It is not: a NESTED bundle is one element, which is
/// the same trick `OnyxControls` uses on the phone. `WatchComplications` is
/// one element, `WatchLive` is the second, and the eleventh widget cost
/// nothing. Verified by compiling it, not by reading a doc.
///
/// ── WHERE THE NUMBERS COME FROM ─────────────────────────────────────────────
/// Not from a store. The phone cuts `WatchTiles` out of the same snapshot its
/// Home Screen widgets draw and sends it inside the application context; the
/// watch app parks it in the App Group suite and reloads every timeline.
/// This extension reads that one value and hands it to `OnyxTile.accessory`,
/// which is the SAME view the phone's Lock Screen draws — one face, both
/// devices, by construction.
///
/// The live card's source is different and deliberately so: `WatchModel`
/// writes `LiveWorkoutSnapshot` into the same suite on every commit and every
/// rest pulse, because the phone cannot know what a wrist logged with the
/// phone in a locker — and the heart rate has exactly one source on this pair.
///
/// ⚠️ `kind:` strings are load-bearing, as on the phone: a kind that
/// disappears takes every placed complication with it.
@main
struct OnyxWatchWidgets: WidgetBundle {
    /// The palette the phone last sent, parked in the suite by `WatchModel`
    /// beside the tiles. Per bundle launch AND per timeline (`WatchTileProvider`),
    /// for the reason `OnyxWidgets.init` on the phone gives: a reload re-runs
    /// the provider in a process that may already be warm.
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

/// The ten watch-face complications. A sub-bundle, so the root counts them as
/// ONE of its ten elements — see `OnyxWatchWidgets`. No `@main`: a bundle
/// that is nested is constructed by its parent.
struct WatchComplications: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        RecoveryComplication()
        TrainComplication()
        FuelComplication()
        WaterComplication()
        StepsComplication()
        SleepComplication()
        BedtimeComplication()
        StressComplication()
        SorenessComplication()
        WeekRingsComplication()
    }
}

/// The Smart Stack card. Alone in its own sub-bundle because the ten above
/// have already spent the root's other element.
struct WatchLive: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        WorkoutLiveWidget()
    }
}

// MARK: - One kind per id
//
// Ten structs and not one struct with an `id` parameter, because `Widget`
// requires `init()` — a `WidgetBundle` constructs its members itself, so
// the id has to be in the TYPE. Each is one line over `tileConfiguration`.

struct RecoveryComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.recovery) } }
struct TrainComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.train) } }
struct FuelComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.fuel) } }
struct WaterComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.water) } }
struct StepsComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.steps) } }
struct SleepComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.sleep) } }
struct BedtimeComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.bedtime) } }
struct StressComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.stress) } }
struct SorenessComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.soreness) } }
struct WeekRingsComplication: Widget { var body: some WidgetConfiguration { tileConfiguration(.weekRings) } }

/// `OnyxWatch.<rawValue>` — namespaced so a phone kind and a watch kind can
/// never collide in a log, and stable across renames of the title.
///
/// `@MainActor` because `Widget.body` is, and the configuration modifiers are
/// main-actor methods returning a non-`Sendable` value; a nonisolated helper
/// cannot hand that back under strict concurrency.
@MainActor
private func tileConfiguration(_ id: WidgetId) -> some WidgetConfiguration {
    StaticConfiguration(kind: "OnyxWatch.\(id.rawValue)", provider: WatchTileProvider()) { entry in
        WatchTileFace(id: id, entry: entry)
    }
    .configurationDisplayName(id.title)
    .description(description(for: id))
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
}

/// One line in the watch-face editor's gallery.
private func description(for id: WidgetId) -> String {
    switch id {
    case .recovery: "Today's battery and readiness score."
    case .train: "Today's session — due, done or a rest day."
    case .fuel: "Calories left against today's target."
    case .water: "Water logged against today's goal."
    case .steps: "Steps against today's goal."
    case .sleep: "Last night's hours and sleep score."
    case .bedtime: "Last night's bedtime and your usual one."
    case .stress: "Today's stress index and its band."
    case .soreness: "How many muscles are sore today."
    case .weekRings: "Seven days of training, fuel and sleep marks."
    default: id.title
    }
}

/// The family is read here rather than in the package: `widgetFamily` is a
/// real value inside WidgetKit and a get-only default outside it, so the face
/// takes it as a parameter and this four-line wrapper is the one place that
/// reads the environment.
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

/// One entry, no schedule.
///
/// ── `.never`, BECAUSE THE APP IS THE CLOCK ───────────────────────────────────
/// The numbers change when the phone pushes, and the watch app reloads every
/// timeline the moment a push lands. A timeline of future entries would be a
/// guess about numbers this process cannot compute — it has no store — so the
/// honest schedule is "draw what you were given, until told otherwise".
///
/// ponytail: a face that outlives the day (the phone slept through midnight)
/// keeps saying yesterday's session is due; `WatchTiles.date` is carried so a
/// later wave can blank the today-fields past midnight without a second push.
struct WatchTileProvider: TimelineProvider {
    // `TimelineProviderContext` spelled out: OnyxCore exports a `Context` (the
    // nutrition one) that shadows `Self.Context` here, and the compiler's only
    // word on that is "does not conform" — the phone's provider says the same.
    func placeholder(in context: TimelineProviderContext) -> WatchTileEntry {
        WatchTileEntry(date: Date(), tiles: nil)
    }

    func getSnapshot(in context: TimelineProviderContext, completion: @escaping (WatchTileEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<WatchTileEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    /// The suite, every time — the theme too, for the warm-process reason on
    /// the bundle's `init`.
    private func entry() -> WatchTileEntry {
        // The suite is looked up twice rather than passed across the
        // `assumeIsolated` boundary: `UserDefaults` is not `Sendable`, and
        // `suiteName` lookups are cached by Foundation.
        MainActor.assumeIsolated { OnyxTheme.load(WatchTiles.defaults()) }
        return WatchTileEntry(date: Date(), tiles: WatchTiles.load())
    }
}
