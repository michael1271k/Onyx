import SwiftUI

/// The Watch logging client.
///
/// ── WHAT IT IS ──────────────────────────────────────────────────────────────
/// A full logging client, not a remote control. It holds its OWN GRDB store,
/// runs the same eighteen migrations the phone does, appends to the same
/// append-only event log and is simply a second `device_id` in it. A watch with
/// no phone in range logs a whole workout and hands it over later.
///
/// ── AND WHAT IT DELIBERATELY IS NOT ─────────────────────────────────────────
/// It is not a network client. There is no Supabase session on this wrist, no
/// refresh token and no Keychain item, because the alternative was moving a
/// long-lived credential onto a second device to save a case that a gym watch
/// rarely hits. Everything reaches the server through the phone, over
/// `WatchLink`, and the phone's outbox pushes it.
///
/// The cost of that, stated plainly rather than discovered: a watch that never
/// sees its phone again keeps its sets locally and nowhere else.
@main
struct OnyxWatchApp: App {

    /// One model for the whole app, created here so it outlives every view.
    /// `@State` rather than `@StateObject` — `WatchModel` is `@Observable`.
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // `.task` rather than `.onAppear`: opening the store, activating
                // WatchConnectivity and asking HealthKit for authorization are
                // all things that should be cancelled if the view goes away
                // before they finish, and `start()` is idempotent so a second
                // appearance costs nothing.
                .task {
                    model.start()
                    #if DEBUG
                    // ── THE SHOT LOOP'S ONE HOOK ────────────────────────────
                    // `ONYX_WATCH_AUTOSTART=1` in the launch environment
                    // (`SIMCTL_CHILD_ONYX_WATCH_AUTOSTART` through simctl)
                    // opens the session on appearing, so a screenshot can reach
                    // `SetView` — the screen this whole client is about — on a
                    // simulator that has no way to tap a button.
                    //
                    // Same convention as `ONYX_SESSION_FILE` on the phone:
                    // DEBUG only, environment only, and it does exactly what
                    // the Start button does rather than a special path.
                    if ProcessInfo.processInfo.environment["ONYX_WATCH_AUTOSTART"] == "1" {
                        // ── AND THE CONTEXT IT NEEDS TO HAVE ANY EFFECT ─────
                        // `beginSession` needs a `day`, `day` comes from the
                        // schedule, and the schedule only ever arrives over
                        // WatchConnectivity. On a simulator with no paired
                        // phone there is none, so this hook has silently done
                        // nothing since it was written: the shot came back as
                        // "Open Onyx on your iPhone" — a real screen, and not
                        // the one anybody was trying to review.
                        //
                        // Seeded through the SAME cache the phone writes, so
                        // the app underneath is running its ordinary path: a
                        // stored context, `resolveDay`, then the Start button's
                        // own call. The day is pinned with an `overrides` entry
                        // rather than a layout, so the shot does not depend on
                        // which weekday it happens to run on — the same reason
                        // `PreviewHarness` takes a `seededDay`.
                        // ALWAYS, not `if context == nil`. The first run of this
                        // hook photographed "Rest day": the simulator still had
                        // a context cached by an earlier wave, whose overrides
                        // were keyed to that day's date, so today fell through
                        // to a weekday layout the seed does not carry. A shot
                        // that depends on what a simulator happens to be
                        // holding is a shot that reviews the wrong screen.
                        model.seedDebugContext()
                        model.beginSession()
                    }
                    // `ONYX_WATCH_SCREEN=rest` puts the rest cover up, the way
                    // `--onyx-screen` picks a face on the phone. `RestView` is
                    // reachable no other way on a simulator: it is presented by
                    // a pulse from the phone, or by committing a set, and a
                    // watch simulator can do neither.
                    if ProcessInfo.processInfo.environment["ONYX_WATCH_SCREEN"] == "rest" {
                        model.seedDebugRest()
                    }
                    #endif
                }
        }
    }
}
