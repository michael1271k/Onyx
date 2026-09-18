import AppIntents
import Foundation
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

// MARK: - The pending-water mailbox

/// Millilitres tapped in Control Center that the store has not seen yet.
///
/// ── WHY A KEY AND NOT A WRITE ───────────────────────────────────────────────
/// The extension opens `onyx.sqlite` read-only (`WidgetStore` says why: two
/// processes migrating one schema is a race with no winner), so a control
/// cannot add the glass itself. It adds 250 to this App Group key and reloads
/// the timelines; the water face reads the key for the optimistic figure
/// (`WidgetStore.snapshot`), and the app drains it into the ledger the next
/// time it is active (`AppEnvironment.drainPendingWater`) — through the same
/// `addWaterGlass` the Pulse tab's tap uses, so a queued glass and a tapped
/// one are the same row.
public enum PendingWater {
    public static let key = "onyx.pending.waterMl"
    /// One glass. The same 250 the Pulse tab's water row adds.
    public static let glassMl: Double = 250

    /// Queue `ml` more.
    public static func add(_ ml: Double, to defaults: UserDefaults) {
        defaults.set(pending(in: defaults) + ml, forKey: key)
    }

    /// What is queued, without touching it.
    public static func pending(in defaults: UserDefaults) -> Double {
        max(0, defaults.double(forKey: key))
    }

    /// What is queued, and the queue emptied.
    @discardableResult
    public static func take(from defaults: UserDefaults) -> Double {
        let ml = pending(in: defaults)
        defaults.removeObject(forKey: key)
        return ml
    }
}

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
