import HealthKit
import SwiftUI
import WatchKit

/// Owns the app's one `WatchModel`, and receives the phone's
/// `HKHealthStore.startWatchApp` launch (overhaul W5.2).
///
/// ── THE DELEGATE OWNS THE MODEL, NOT THE ROOT VIEW ──────────────────────────
/// A `startWatchApp` launch can land in the BACKGROUND, where the root view's
/// `.task` may never run — so a model handed over from there could arrive too
/// late or never (review). Owned here, it exists before `handle(_:)` is called.
@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let model = WatchModel()

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        model.handleWorkoutLaunch()
    }
}

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

    /// Owns the one model for the whole app (so it outlives every view, and
    /// exists for a background `startWatchApp` launch — W5.2).
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    /// `WatchModel` is `@Observable`; reading it through the delegate is
    /// tracked the same way `@State` was.
    private var model: WatchModel { delegate.model }

    var body: some Scene {
        WindowGroup {
            RootView()
                // ── A PUSHED THEME REPAINTS THE WHOLE WRIST (overhaul A2) ───
                // `WatchInk` is computed now, but a view only re-reads it when
                // it re-renders, and nothing it observes changes with the
                // palette. Re-identifying the root on the theme is the one
                // line that makes every view draw again. It is safe mid-session
                // because the phone refuses a theme change during a workout
                // (`AppearanceView` locks, `publishPhase` waits) — and a
                // re-id costs only view state: the session, the rest cover
                // and the deck all live on the model.
                .id(model.themeKey)
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
                        // ── EVERY SHOT STARTS FROM ZERO ─────────────────
                        // `start()` has already run `rejoinLiveSession`, and
                        // on a simulator that has been shot before there IS
                        // one: the previous run's session, with its own sets
                        // and its own cursor. The first run of this loop
                        // photographed "Set 2/3" on a screen that had just
                        // been launched, and a shot that depends on what a
                        // simulator happens to be holding is a shot that
                        // reviews the wrong screen — the same lesson the
                        // `seedDebugContext` comment below records about a
                        // stale context.
                        //
                        // Discarded through the shipping path, so what the
                        // loop exercises is `cancelSession` and not a special
                        // reset nobody ships.
                        model.cancelSession()
                        model.seedDebugContext()
                        model.beginSession()
                    }
                    // `ONYX_WATCH_SCREEN=<name>` puts a screen up, the way
                    // `--onyx-screen` picks a face on the phone. Every one of
                    // these is reachable no other way on a simulator: the rest
                    // cover is presented by a pulse from the phone or by
                    // committing a set, and the four W3 screens are reached by
                    // navigation, a swipe or a long press — and a watch
                    // simulator can do none of them.
                    //
                    // ── EACH ONE SEEDS THE STATE AND THEN LETS THE APP DRAW ──
                    // `debugScreen` is read by whichever view owns the screen,
                    // so the shot goes down the path a finger would take. The
                    // sets go in through `commitSet`, which is the ordinary
                    // write — a photograph of a second code path is a
                    // photograph of something that does not ship.
                    if let name = ProcessInfo.processInfo.environment["ONYX_WATCH_SCREEN"],
                       let screen = WatchModel.DebugScreen(rawValue: name) {
                        model.debugScreen = screen
                        // ── EVERY SCREEN STARTS FROM ZERO, NOT ONLY AUTOSTART ──
                        // A screen shot WITHOUT autostart after one shot with
                        // it (`finish`, then `dashboard`) rejoined the earlier
                        // shot's live session in `start()` and photographed
                        // the finish card under `dashboard.png` — found in the
                        // overhaul A1 round. Discarded the same shipping way.
                        if ProcessInfo.processInfo.environment["ONYX_WATCH_AUTOSTART"] != "1" {
                            model.cancelSession()
                        }
                        switch screen {
                        case .rest, .restband:
                            model.seedDebugRest()
                        case .deck, .quality, .pause, .cancel:
                            // Two sets: enough for the deck to show a movement
                            // done and one in progress, and enough for the
                            // quality panel to have a set to describe.
                            model.seedDebugSets(2)
                            if screen == .pause { model.togglePause() }
                        case .finish:
                            // Every planned set, which is what empties the
                            // cursor and turns the tick into a finish button.
                            model.seedDebugSets(99)
                        case .widget:
                            // The widget faces read the App Group suite, and
                            // the only thing that ever writes it is a live
                            // session's `publishLiveSnapshot`. Two sets put
                            // one there through the ordinary path — a
                            // photograph of a literal would prove the face
                            // draws and nothing about whether a widget has
                            // anything to draw FROM.
                            //
                            // A heart first, because a simulator has none and
                            // the circular face's WHOLE content is the rate:
                            // without this the shot is an honest "—" that
                            // reviews nothing. Same call `seedDebugRest`
                            // makes for the sparkline.
                            model.workout.seedDebugSamples([131, 138, 142])
                            // THREE, so the cursor advances off "Chest
                            // Press" — the shortest name in the seeded deck
                            // — onto "Neutral-Grip Lat Pulldown", which is
                            // the length this 162 pt slot actually has to
                            // survive. A face photographed with its easiest
                            // input is a face whose truncation nobody has
                            // reviewed.
                            model.seedDebugSets(3)
                        case .banner, .join, .replay:
                            // ── THE PHONE'S LIFECYCLE, SEEDED (overhaul A1) ─
                            // The same context every dashboard shot gets,
                            // with a finished or a live session on it — what
                            // `pushLifecycle` sends. Page one then draws the
                            // banner, or Start turned into Join, through
                            // `frontDoor` exactly as a real push would.
                            model.seedDebugContext(session: WatchModel.debugLifecycle(screen == .join ? .open : .finished))
                        case .restday:
                            // The same seed with today unscheduled — see
                            // `seedDebugContext(restDay:)`. It falls through to
                            // page one, which is where the rest-day hero is.
                            model.seedDebugContext(restDay: true)
                        case .start, .dashboard, .train, .fuel, .glance, .pulse:
                            // ── THE CONTEXT, WHICH AUTOSTART USUALLY SEEDS ──
                            // These three are the only screens reached with
                            // `ONYX_WATCH_AUTOSTART` OFF, and the seed above
                            // is inside that branch — so the first run of
                            // this hook drew whatever context the simulator
                            // happened to be holding from an earlier wave.
                            // It photographed "No volume yet" on the Train
                            // page and the kcal fallback on Fuel: a cached
                            // payload from before those fields existed. A
                            // real screen, under the right filename, showing
                            // last month's wire format — which is the exact
                            // failure `seedDebugContext`'s own header records
                            // having shipped once already.
                            model.seedDebugContext()
                            // ── AND WHY `start` JOINED THEM (W2) ───────────
                            // The Start screen is page one of the dashboard
                            // now, so it needs the same context the other
                            // three pages do. Without it the shot came back
                            // as the honest "Open Onyx on your iPhone" empty
                            // state under the filename `start.png` — a real
                            // screen, correctly named, and not the one the
                            // wave changed. `nophone` is that state's own
                            // name in `watch-shot.sh`.
                            //
                            // ── THE LAST NAME `watch-shot.sh` REFUSED (W4) ──
                            // W1 left `dashboard` unreachable and said so by
                            // name rather than photographing `StartView`
                            // under its filename. It is reached the way a
                            // finger reaches it — a real push onto the real
                            // stack, from `RootView` — and the PAGE within it
                            // is picked by `DashboardView` off the same
                            // value.
                            //
                            // No seeded sets: the dashboard is the screen you
                            // open BEFORE a session, its numbers come from
                            // `WatchTiles` (which `seedDebugContext` above
                            // already filled), and a session behind it would
                            // photograph the in-session entry point instead
                            // of the one this page is normally reached from.
                            break
                        }
                    }
                    #endif
                }
        }
    }
}
