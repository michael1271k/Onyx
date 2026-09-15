import SwiftUI
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
    @AppStorage(OnyxTheme.key, store: UserDefaults(suiteName: AppDatabase.appGroupID))
    private var themeJSON = ""

    var body: some Scene {
        WindowGroup {
            // Before anything draws: the tokens are read during `body` of every
            // view below, so the theme has to be current by the time they are.
            let _ = OnyxTheme.apply(json: themeJSON)
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
            .id(themeJSON)
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
                environment?.refreshHealth()
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
