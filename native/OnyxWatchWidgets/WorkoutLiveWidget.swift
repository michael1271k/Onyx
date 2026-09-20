import SwiftUI
import WidgetKit
import RelevanceKit
import OnyxCore
import OnyxUI

// MARK: - The Smart Stack's live workout (W4, founder decision 6)
//
// ── WHAT PUTS IT IN FRONT OF YOU ────────────────────────────────────────────
// Not a timeline. The Smart Stack ranks its cards by RELEVANCE, and watchOS 11
// added a provider-side hook for it — `TimelineProvider.relevance()`, which
// answers a `WidgetRelevance<Void>` and needs no App Intent, no
// `AppIntentConfiguration` and no metadata extractor. This widget returns
// `RelevantContext.fitness(.workoutActive)` while a session is live and an
// EMPTY relevance when it is not, which is how the card is cleared: there is
// no "remove" call, the empty answer is the removal.
//
// ── AND WHY RELOADING THE TIMELINE IS NOT ENOUGH ────────────────────────────
// The system CACHES the answer to `relevance()`. A timeline reload refreshes
// what the card draws and leaves the ranking on yesterday's answer, so the
// card would update perfectly in a stack it never rose to the top of. The
// watch app therefore calls `invalidateRelevance(ofKind:)` beside its reload —
// see `WatchModel.publishLiveSnapshot`.
//
// ── TWO FAMILIES, AND NOT FOUR ──────────────────────────────────────────────
// `.accessoryRectangular` is what the Smart Stack renders, and it is what
// this widget is for — declaring it is what makes the card eligible at all.
// `.accessoryCircular` is the second, because §W4 asks for a heart rate ON
// THE FACE during a workout and a corner is where that lives: same snapshot,
// three characters of room, so it draws the one reading you cannot get
// anywhere else.
//
// `.accessoryInline` and `.accessoryCorner` are NOT declared. A line beside
// the clock reading "no session running" for twenty-three hours is the
// hide-until-data argument's opposite failure — a slot spent on an absence —
// and the ten complications beside this one are the things that have
// something to say all day.

struct WorkoutLiveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LiveWorkoutSnapshot.widgetKind, provider: LiveWorkoutProvider()) { entry in
            LiveWorkoutFaceWrapper(entry: entry)
        }
        .configurationDisplayName("Live workout")
        .description("The set you are on, and your heart rate, while a session is running.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

/// The family is read here rather than in the package, for the reason
/// `WatchTileFace` gives one file over: `widgetFamily` is a real value inside
/// WidgetKit and a get-only default outside it, so the face takes it as a
/// parameter and this wrapper is the one place that reads the environment.
struct LiveWorkoutFaceWrapper: View {
    let entry: LiveWorkoutEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        LiveWorkoutFace(snapshot: entry.snapshot, family: family)
    }
}

// MARK: - Timeline

struct LiveWorkoutEntry: TimelineEntry {
    let date: Date
    let snapshot: LiveWorkoutSnapshot?
}

/// One entry, no schedule — the same argument `WatchTileProvider` makes.
///
/// The numbers change when the watch app writes, and it reloads this kind the
/// moment it does. The one thing that moves on its own is the rest countdown,
/// and that is a `Text(timerInterval:)` ticked by the system inside the face
/// (`LiveWorkoutFace`): a timeline of per-second entries would be the reload
/// budget spent on a clock watchOS will draw for free.
struct LiveWorkoutProvider: TimelineProvider {

    // `TimelineProviderContext` spelled out: OnyxCore exports a `Context`
    // that shadows `Self.Context` here — the same note `WatchTileProvider`
    // carries, and the same one-word compiler error if it is left inferred.
    func placeholder(in context: TimelineProviderContext) -> LiveWorkoutEntry {
        LiveWorkoutEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: TimelineProviderContext, completion: @escaping (LiveWorkoutEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<LiveWorkoutEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    /// Where this card ranks, and when.
    ///
    /// Two attributes rather than one. `.fitness(.workoutActive)` reads the
    /// system's OWN notion of a running workout — which on this wrist is the
    /// `HKWorkoutSession` `WorkoutSessionController` opens — and is exactly
    /// "in progress now, end unknown". The dated window beside it is the belt:
    /// the workout state can lag, and a session whose snapshot was written a
    /// minute ago is a session whatever HealthKit currently thinks.
    ///
    /// An EMPTY `WidgetRelevance` is the clear. `LiveWorkoutSnapshot.load`
    /// already answers nil for a stale blob, so a jetsammed session stops
    /// ranking on its own without anything having to remember to clean up.
    func relevance() async -> WidgetRelevance<Void> {
        guard let snapshot = LiveWorkoutSnapshot.load() else { return WidgetRelevance([]) }
        return WidgetRelevance([
            WidgetRelevanceAttribute(context: .fitness(.workoutActive)),
            WidgetRelevanceAttribute(
                context: .date(
                    from: Date(),
                    to: snapshot.updatedAt.addingTimeInterval(LiveWorkoutSnapshot.staleAfter)
                )
            ),
        ])
    }

    /// The suite, every time — and the theme with it, for the warm-process
    /// reason the bundle's `init` gives.
    private func entry() -> LiveWorkoutEntry {
        MainActor.assumeIsolated { OnyxTheme.load(WatchTiles.defaults()) }
        return LiveWorkoutEntry(date: Date(), snapshot: LiveWorkoutSnapshot.load())
    }
}
