import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit
import OnyxCore
import OnyxData
import OnyxUI

/// The native app's widget extension.
///
/// One Home Screen kind that draws every dashboard tile (`OnyxTileWidget`,
/// the sprint's W5), the Lock Screen accessory, three Control Center controls
/// (`OnyxControls.swift`) and the running-workout Live Activity. Every tile is
/// a `OnyxUI` view drawing a `OnyxSnapshot` that `OnyxProvider` builds from the
/// App Group database — no network, no snapshot route, no token.
///
/// ⚠️ `kind:` strings are load-bearing: a kind that disappears takes every
/// placed instance of it off the Home Screen. Six family kinds — Fuel,
/// Training, Body, Progress, Daily and Vitals — stood here as SHELLS for the
/// whole of 6.2.0–6.8.0 so a widget placed on 6.1.0 survived the move to the
/// generic kind. W12 deleted them on the founder's confirmation that the
/// release carrying W5 had been on device for a cycle. The FACES they drew are
/// untouched: they are `OnyxUI/Tiles/` views and `OnyxTileWidget` draws the
/// same ones through `OnyxTile.face`.
@main
struct OnyxWidgets: WidgetBundle {
    /// The theme, on a cold extension launch.
    ///
    /// ── AND AGAIN PER TIMELINE, WHICH THIS USED TO ARGUE AGAINST (W5) ───────
    /// The argument was cost: the palette is a `UserDefaults` read plus sixteen
    /// OKLCH rotations, and paying it per entry would be the same colours
    /// computed dozens of times an hour in an extension with a 30 MB budget.
    /// The premise is wrong in the only case that matters. `reloadAllTimelines`
    /// re-runs the PROVIDER, not this initialiser, and WidgetKit reuses a live
    /// extension process — so a theme picked in Settings reached a widget that
    /// was cold and missed one that happened to be warm, which reads as the
    /// feature working intermittently. `OnyxProvider` therefore loads per
    /// timeline too, and the cost is not the one above: `OnyxTheme.set` returns
    /// at `guard current.spec != spec` without rebuilding anything, so a
    /// reload in a warm process costs a string read, a two-field JSON decode
    /// and an `==`.
    ///
    /// `assumeIsolated` because a `WidgetBundle` init runs on the main actor
    /// but is not annotated as doing so, and `load` is `@MainActor`. Nothing is
    /// weakened: this is the assertion, not an escape from it.
    init() {
        MainActor.assumeIsolated {
            OnyxTheme.load(AppDatabase.appGroupDefaults())
        }
    }

    var body: some Widget {
        // Gallery order: the tile, the running session, the accessory sizes.
        // Four entries where there were ten — a `WidgetBundleBuilder` tops out
        // at ten, which is why the controls are still a bundle of their own,
        // and the headroom is now the reason they could stop being one.
        OnyxTileWidget()
        OnyxWorkoutActivityWidget()
        OnyxLockWidget()
        OnyxControls().body
    }
}

// MARK: - The tile (W5)

/// Every dashboard tile, one kind. The picker is `TileOption` (= `WidgetId`);
/// the face is `OnyxTile.face`, the same view the Today grid draws.
///
/// ── THE FAMILY TRAP ─────────────────────────────────────────────────────────
/// `supportedFamilies` is static per kind and this kind draws tiles whose
/// catalogue sizes range from `[.s]` (Bedtime) to `[.l]` (Day Rings). All three
/// are declared and `OnyxTile.clamped` draws the largest size at or below the
/// host that the tile has a body for — or a one-line note when there is none.
struct OnyxTileWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OnyxTile", intent: TileConfiguration.self, provider: OnyxIntentProvider<TileConfiguration>()) { entry in
            TileFace(entry: entry)
        }
        .configurationDisplayName("Onyx")
        .description("Any tile from the Today dashboard. Pick which in Edit Widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// `widgetFamily` is an environment value, and a `Widget`'s content closure
/// has no environment to read — so the clamp lives one view down.
private struct TileFace: View {
    let entry: OnyxEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        OnyxTile.clamped(entry.tile.tileId ?? .train, host: family, entry: entry.tile)
            // ── THE ONE PLACE THE WATER BUTTON IS BUILT (W6) ─────────────────
            // The Water face declares a slot (`EnvironmentValues.onyxWaterButton`)
            // and cannot fill it: `AddWaterIntent` is a `Shared/` type that
            // imports OnyxData, and OnyxUI is forbidden OnyxData by its own
            // manifest. The extension has both, so it builds the button here.
            //
            // Set for EVERY tile rather than only for Water: the environment is
            // read by the face that wants it and ignored by the twenty that do
            // not, and a conditional keyed on `tileId` would be a second list
            // of which tiles are water tiles.
            .environment(\.onyxWaterButton, OnyxWaterButton { AnyView(AddWaterButton()) })
    }
}

/// +250 ml, without leaving the Home Screen.
///
/// `AddWaterIntent` does not write the ledger — the extension opens the store
/// read-only — it adds a glass to the App Group mailbox and reloads the
/// timelines; `WidgetStore.snapshot` adds the pending millilitres to the figure
/// so the tap lands visibly, and the app drains the mailbox on its next
/// `.active`. See `AddWaterIntent.swift` for the whole chain.
private struct AddWaterButton: View {
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Button(intent: AddWaterIntent()) {
            HStack(spacing: 3) {
                Image(systemName: "plus").font(OnyxWidgetType.face(9, weight: .bold))
                Text("250").font(OnyxWidgetType.face(9, weight: .heavy))
            }
            .foregroundStyle(mode == .accented ? Color.white : Color.onyx.water)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill((mode == .accented ? Color.white : Color.onyx.water).opacity(0.18))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a glass of water")
    }
}

// MARK: - The Lock Screen accessory

struct OnyxLockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OnyxLockFamily", intent: LockConfiguration.self, provider: OnyxIntentProvider<LockConfiguration>()) { entry in
            LockView(entry: entry.tile, focus: entry.tile.lockFocus)
        }
        .configurationDisplayName("Lock Screen")
        .description("One fact on the Lock Screen: battery, calories, steps, today's session or last night's bedtime.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - The running workout

/// ── ONE STRUCT, BECAUSE THE FLOOR IS iOS 18 ─────────────────────────────────
/// An iOS 17 floor needs TWO widget structs for this — `supplementalActivity-
/// Families` is `@available(iOS 18.0, *)` and returns a different opaque type,
/// so it cannot be applied conditionally inside one `body`, and WidgetKit ships
/// no `AnyWidgetConfiguration` to erase it with. The native app's deployment
/// target IS 18.0, so the availability branch, the duplicate struct and the
/// `buildLimitedAvailability` dance all simply do not exist here.
///
/// ── AND WHY THE WATCH LAYOUT IS A BRANCH IN THE VIEW ────────────────────────
/// Before watchOS 11 the Smart Stack mirrored an iPhone activity by rendering
/// its DYNAMIC ISLAND COMPACT regions — two ~44 pt slots flanking a camera
/// cutout, drawn on a watch face with room for four lines, which is how "Onyx
/// 1/2 75x13" happened. Declaring the supplemental family makes the system ask
/// for a watch-shaped card through the SAME content closure, so the branch
/// belongs in the view (`@Environment(\.activityFamily)`) and not in a second
/// configuration.
struct OnyxWorkoutActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OnyxWorkoutAttributes.self) { context in
            LockScreenWorkout(context: context)
                // The Lock Screen draws on the SYSTEM's material. A solid
                // obsidian panel here reads as a black rectangle stuck to the
                // wallpaper; a tint makes the card the app's without claiming
                // the whole surface.
                .activityBackgroundTint(.black.opacity(0.55))
                .activitySystemActionForegroundColor(Color.onyx.accent(.train))
        } dynamicIsland: { context in
            // No `let accent = …` here, however much it would tidy the call
            // sites: a binding turns the trailing closure into a multi-statement
            // body, which stops `DynamicIslandExpandedContentBuilder` inferring
            // `Expanded` and fails with "generic parameter 'Expanded' could not
            // be inferred" — an error that names none of the actual code.
            DynamicIsland {
                // ── WHY ALMOST EVERYTHING IS IN `.bottom` ───────────────────
                // The expanded presentation has four regions and they are NOT
                // equal. `.leading` and `.trailing` are the narrow columns
                // either side of the camera and `.center` is the sliver BETWEEN
                // them — the narrowest of the three. Only `.bottom` spans the
                // full width. So the flanks hold only what is genuinely short,
                // and every fact that has a length lives where it can breathe.
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        // ── THE MARK, NOT THE NAME ──────────────────────────
                        // This slot used to read `● ONYX`, which was a dot
                        // that said nothing beside a wordmark for an app that
                        // no longer has that name. `OnyxMark` is both at once:
                        // the ring is the brand AND, tinted with the split's
                        // colour, it is the same coloured token every other
                        // surface uses to say which session is running.
                        //
                        // ── AND THE WORDMARK GAVE ITS SPACE TO THE CLOCK ────
                        // Top-left now reads TOTAL WORKOUT TIME. It used to
                        // read `ONYX` beside a ring that already says so, while
                        // the only clock on the surface was in the opposite
                        // corner and switched between two different durations.
                        OnyxMark(size: 12, tint: Color.onyx.day(context.state.dayKey), opacity: 1)
                        WorkoutElapsed(
                            state: context.state, startedAt: context.attributes.startedAt
                        )
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // ── THIS WAS `9/22`, AND `WorkoutTotals` SAYS IT AGAIN ──
                    // Twelve points below this slot, in the bottom region, in
                    // the same colour: "9/22 sets". A number printed twice on
                    // a surface this small is a number that has stopped being
                    // read. The muscle tag takes the slot instead — it is the
                    // fact the island did not carry, it is what the Lock
                    // Screen's own header pairs with the session, and the
                    // bottom region's rows have no width to spare for it.
                    WorkoutMuscleTag(token: context.state.primaryMuscle)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        WorkoutTotals(state: context.state)
                        // The chart that used to sit in the trailing column
                        // is gone (`WorkoutActivityCard` says why), and the
                        // set takes the whole width: the exercise name is the
                        // longest string on this region and it was sharing a
                        // 76 pt column boundary with a monotonic line.
                        WorkoutCurrentSet(state: context.state)
                        // ── `LAST TIME` LEFT WITH `prev` ────────────────────
                        // Same call, same reason: the founder's, and the row it
                        // occupied is what the rest controls now stand in. The
                        // previous load is still on the wire and still drawn by
                        // `WorkoutCurrentSet` while resting, which is the moment
                        // it is a decision rather than a table.
                        //
                        // Only while the clock is running: controls with nothing
                        // to control are dead chrome on a surface that has no
                        // room for any.
                        // `total:` — the same denominator fix the Lock Screen
                        // takes. This region draws the same `WorkoutRestBand`,
                        // so without it the island's bar snapped back toward
                        // full on every redraw while the card's drained.
                        if let countdown = restCountdown(
                            context.state.restEndsAt, total: context.state.restTotalSec
                        ) {
                            // No Skip here. Four 34 pt controls plus a bar do
                            // not fit this region's width, and the phone in the
                            // hand that just opened the island has the same
                            // button on the card below.
                            WorkoutRestBand(
                                countdown: countdown, state: context.state, showsSkip: false
                            )
                        }
                    }
                    // ── THE CLIPPED BOTTOM CORNER ───────────────────────────
                    // The expanded region draws to its own edge and the system
                    // rounds that edge, so a 34 pt capsule sitting flush at the
                    // bottom lost its lower corners to the mask. Two points of
                    // inset is the whole fix; the region has the height.
                    .padding(.bottom, 2)
                }
            } compactLeading: {
                // The one place the brand is visible while the phone is in a
                // pocket-to-hand glance, and it costs nothing a filled dot did
                // not already cost.
                OnyxMark(size: 14, tint: Color.onyx.day(context.state.dayKey), opacity: 1)
            } compactTrailing: {
                // Whichever number is the answer RIGHT NOW: the rest clock
                // while resting, the bout's clock on a treadmill, the wrist's
                // heart rate under the bar, the load with no watch speaking.
                // Two facts competing for one ~44 pt slot is how the compact
                // region becomes unreadable, so the branches are ordered and
                // exactly one draws.
                //
                // ── AND IT LIVES IN `Shared/` (W4) ──────────────────────────
                // It was written out here, and `WidgetPreviews.islandCompact`
                // — the only thing that PHOTOGRAPHS this slot — carried a
                // copy of three of its four branches. Adding the heart rate
                // to this one left the copy behind, so the contact sheet
                // reviewed a stand-in that no longer matched. One view, both
                // callers; see `WorkoutCompactTrailing`.
                WorkoutCompactTrailing(state: context.state)
            } minimal: {
                // One glyph for the whole activity, so it says what is
                // happening and not what the app is: resting, walking, or
                // lifting. A bout under a barbell was the one reading of the
                // three that was simply untrue.
                Image(systemName: minimalGlyph(context.state))
                    .font(OnyxWidgetType.label(12, weight: .bold))
                    .foregroundStyle(Color.onyx.day(context.state.dayKey))
            }
            .keylineTint(Color.onyx.day(context.state.dayKey))
        }
        // watchOS 11 / iOS 18: a real Watch card, asked for through the same
        // content closure. This is the fix for the Smart Stack rendering the
        // Dynamic Island's compact slots on a face with room for four lines.
        .supplementalActivityFamilies([.small])
    }

    /// The minimal presentation's one glyph, in the order the states shadow
    /// each other: resting beats walking beats lifting, because a rest clock is
    /// running on top of whichever of the other two you are between.
    ///
    /// Lifted out rather than left a nested ternary in the `minimal` closure:
    /// the third case is what pushed it past one, and a view builder is the one
    /// place a mis-parenthesised ternary reports as an unrelated type error.
    private func minimalGlyph(_ state: OnyxWorkoutAttributes.ContentState) -> String {
        if state.restEndsAt != nil { return "timer" }
        // `figure.run` is the symbol the app already draws a bout with — the
        // Quick Log spoke, the session ledger's cardio card and the Workout
        // tab all pick it. See `WorkoutTabView`.
        if state.cardioElapsedSec != nil || state.cardioDistanceKm != nil { return "figure.run" }
        return "figure.strengthtraining.traditional"
    }
}

// MARK: - Lock Screen

/// Unwraps the `ActivityViewContext` and picks the surface.
///
/// Everything it draws lives in `Shared/WorkoutActivityCard.swift`, taking the
/// attributes and the state as plain values — see that file's header for why.
/// This wrapper is all that has to stay here: the context type only exists
/// inside a running activity, so it is the one thing the harness cannot make.
private struct LockScreenWorkout: View {
    let context: ActivityViewContext<OnyxWorkoutAttributes>

    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small:
            WorkoutWatchCard(title: context.attributes.title, state: context.state)
        default:
            WorkoutLockCard(
                title: context.attributes.title,
                startedAt: context.attributes.startedAt,
                state: context.state
            )
        }
    }
}
