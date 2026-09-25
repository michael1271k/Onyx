import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

@main
struct OnyxApp: App {
    /// `launch.firstFrame` — opened as the process builds its scene, closed by
    /// the first `RootView` that actually draws. It spans the database open,
    /// the Keychain read and `AppEnvironment.live()`, which is what a cold
    /// launch is; a warm one never runs this `init` again.
    private static let launch = Perf.begin("launch.firstFrame")
    private static let launchStarted: Void = { _ = launch }()
    @State private var firstFrame = false

    init() { _ = Self.launchStarted }

    @Environment(\.scenePhase) private var scenePhase
    @State private var environment: AppEnvironment?
    @State private var startupError: String?
    /// A session a shared `onyx://session/<uuid>` link asked for.
    @State private var linkedSession: SessionLink?
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
                        .task {
                            environment.start()
                            if !firstFrame { firstFrame = true; Perf.end(Self.launch) }
                        }
                } else if let startupError {
                    StartupErrorView(message: startupError)
                } else {
                    ProgressView().controlSize(.large)
                }
                #else
                if let environment {
                    RootView()
                        .environment(environment)
                        .task {
                            environment.start()
                            if !firstFrame { firstFrame = true; Perf.end(Self.launch) }
                        }
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
            // ── onyx://session/<uuid> (Precision B5, seam 7) ────────────────
            // The link a replay share carries. It opens that session's
            // summary over whatever is on screen; the shell's own handler
            // (`RootView`, `onyx://open?path=`) ignores this shape.
            .onOpenURL { url in
                if let id = SessionLink.sessionId(from: url) { linkedSession = SessionLink(id: id) }
            }
            .sheet(item: $linkedSession) { link in
                if let environment {
                    NavigationStack {
                        SessionDetailView(sessionId: link.id)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") { linkedSession = nil }
                                }
                            }
                    }
                    .environment(environment)
                    .preferredColorScheme(.dark)
                }
            }
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
                /* ── THE REMINDERS ARE RE-ARMED ON EVERY FOREGROUND ─────────
                   They are one-shots for the coming week, so a slot answered
                   since the last foreground has to stop being scheduled and a
                   new week has to be armed. There is no background refresh on
                   a free developer account, so "the app was opened" is the only
                   clock this has — plus `DayModel.write`, which re-arms after
                   a tick or a stack edit made while the app is open. `refresh`
                   clears everything when both toggles are off. */
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

/// `onyx://session/<uuid>` — the link a replay share carries (Precision B5,
/// decision Q21 · seam 7).
///
/// A custom scheme is callable by anything on the device, so the id is
/// UNTRUSTED input: it must parse as a UUID, and it is lowercased because the
/// store keys sessions lower-case (memory `next-gen-w1-health-truth`: an
/// uppercase id stops matching itself after one round trip).
struct SessionLink: Identifiable, Equatable {
    let id: String

    static func sessionId(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "onyx", url.host()?.lowercased() == "session" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let uuid = UUID(uuidString: parts[0]) else { return nil }
        return uuid.uuidString.lowercased()
    }

    static func url(sessionId: String) -> URL {
        URL(string: "onyx://session/\(sessionId.lowercased())")!
    }
}

