import AppIntents
import Foundation
// `PendingWater`, which moved here from this file — see the note below.
import OnyxCore
import OnyxData
import WidgetKit

/// Control Center's three buttons, and the one mailbox the water one needs.
///
/// ── WHY THIS FILE SITS BESIDE `RestSkipIntent` ──────────────────────────────
/// The same rule: the widget extension DRAWS a control and the system performs
/// its intent in whichever process it likes, so the intent type has to be one
/// type compiled into both targets. Unlike `RestSkipIntent` this file imports
/// OnyxData — for `AppDatabase.appGroupDefaults()` alone, so the App Group
/// suite name is spelled in exactly one place. Both targets link OnyxData;
/// nothing here may reach further than that (no `LoggerModel`, no store).

// ── THE MAILBOX MOVED TO OnyxCore (W4) ──────────────────────────────────────
// `PendingWater` used to be declared here. It is a `UserDefaults` key and two
// arithmetic functions with nothing iOS about them, and `Shared/` is compiled
// into the phone app and the phone's widget extension and NEITHER watch
// target — so the wrist's new "+1 glass" button could not see it and would
// have had to write `250` a third time. It lives in
// `OnyxCore/Widget/PendingWater.swift` now, which both watch targets already
// link. The intent below, which writes to the PHONE's own App Group, stays.

// MARK: - +250 ml

struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a glass of water"
    static let description = IntentDescription("Adds 250 ml to today's water.")

    func perform() async throws -> some IntentResult {
        PendingWater.add(PendingWater.glassMl, to: AppDatabase.appGroupDefaults())
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Start session · Log stress

/// Opens the app on a screen, through the same `onyx://open?path=…` allow-list
/// every widget tap goes through (`DeepLink.safePath` in `RootView`). One intent
/// with the path as its argument rather than one intent per button — the two
/// buttons differ by a string.
struct OpenOnyxIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Onyx"
    static let description = IntentDescription("Opens Onyx on a screen.")
    static let openAppWhenRun = true
    /// Not a Shortcuts action: the paths are the router's, not the user's.
    static let isDiscoverable = false

    @Parameter(title: "Path")
    var path: String

    init() {}

    init(path: String) {
        self.path = path
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        var c = URLComponents()
        c.scheme = "onyx"
        c.host = "open"
        c.queryItems = [URLQueryItem(name: "path", value: path)]
        return .result(opensIntent: OpenURLIntent(c.url!))
    }
}
