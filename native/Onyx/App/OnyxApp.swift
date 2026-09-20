import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

@main
struct OnyxApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var environment: AppEnvironment?
    @State private var startupError: String?
    /// The persisted theme, in the App Group suite the widgets read too.
    ///
    /// `@AppStorage` is what makes a Settings write repaint this process: it
    /// invalidates `body`, `apply(json:)` rebuilds `OnyxTheme.current`, and the
    /// `.id` below throws away the view tree so the ~1,250 STATIC
    /// `Color.onyx.*` reads all run again. Without the `.id` the tokens would
    /// be correct and the screen would still show the old palette until each
    /// view happened to redraw for some other reason.
    ///
    /// Empty (the fresh-install case) resolves to the default spec, so the app
    /// is pixel-identical until somebody picks a theme.
    @AppStorage(OnyxTheme.key, store: AppDatabase.appGroupDefaults())
    private var themeJSON = ""

    /// The training block the palette reads itself through — `AppEnvironment`
    /// writes it whenever a schedule resolves, and it changes at a midnight
    /// nobody touched.
    ///
    /// A SECOND `@AppStorage` and not a field of the blob above, for the reason
    /// `OnyxTheme.phaseKey` gives: the user owns one value and the calendar
    /// owns the other. It joins the `.id` below because a phase roll changes
    /// twenty-four derived colours and nothing else invalidates the tree.
    @AppStorage(OnyxTheme.phaseKey, store: AppDatabase.appGroupDefaults())
    private var themePhase = ""

    var body: some Scene {
        WindowGroup {
            // Before anything draws: the tokens are read during `body` of every
            // view below, so the theme has to be current by the time they are.
            let _ = OnyxTheme.apply(json: themeJSON, phase: PhaseKind(rawValue: themePhase))
            Group {
                #if DEBUG
                // The screenshot loop's door. Checked before anything else so a
                // shot never waits on a database or a Keychain read.
                if let screen = PreviewHarness.requestedScreen {
                    PreviewHarness.view(screen)
                } else if let environment {
                    RootView()
                        .environment(environment)
                        .task { environment.start() }
                } else if let startupError {
                    StartupErrorView(message: startupError)
                } else {
                    ProgressView().controlSize(.large)
                }
                #else
                if let environment {
                    RootView()
                        .environment(environment)
                        .task { environment.start() }
                } else if let startupError {
                    StartupErrorView(message: startupError)
                } else {
                    // The database opens and the Keychain is read in single-digit
                    // milliseconds, so this is almost never seen — but it is a
                    // real state, and a `ProgressView` here is what stops a
                    // frame of the wrong screen from being drawn.
                    ProgressView().controlSize(.large)
                }
                #endif
            }
            .id(themeJSON + "·" + themePhase)
            .preferredColorScheme(.dark)
            .task {
                guard environment == nil, startupError == nil else { return }
                do {
                    environment = try AppEnvironment.live()
                } catch {
                    startupError = String(describing: error)
                }
            }
            // Apple Health is read on every foreground, not once at launch —
            // see `AppEnvironment.refreshHealth`. Signed out, or with a pull
            // already running, this is a no-op.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                // The Control Center glasses first: the sync that follows
                // writes today's row too, and the ledger it sums should
                // already hold them.
                environment?.drainPendingWater()
                environment?.refreshHealth()
                /* ── THE REMINDERS ARE RE-ARMED HERE AND NOWHERE ELSE ────────
                   They are one-shots for the coming week, so a slot answered
                   since the last foreground has to stop being scheduled and a
                   new week has to be armed. There is no background refresh on
                   a free developer account, so "the app was opened" is the only
                   clock this has. `refresh` is a no-op when the toggle is off. */
                if let environment {
                    OnyxReminders.refresh(
                        database: environment.database, userId: environment.userIdString)
                }
            }
        }
    }
}

/// A launch that could not proceed, with the reason on screen.
///
/// A `fatalError` here would be a crash on first run for the one mistake
/// everyone makes — forgetting to copy `Secrets.xcconfig` — and a crash tells
/// you nothing. `SupabaseConfig.ConfigError` already carries the fix; this just
/// shows it.
private struct StartupErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Onyx could not start", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
        .textSelection(.enabled)
    }
}
