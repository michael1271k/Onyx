import Foundation

// MARK: - The pending-water mailbox
//
// ── WHY A KEY AND NOT A WRITE ───────────────────────────────────────────────
// The widget extension opens `onyx.sqlite` read-only (`WidgetStore` says why:
// two processes migrating one schema is a race with no winner), so a Control
// Centre button cannot add the glass itself. It adds 250 to this App Group key
// and reloads the timelines; the water face reads the key for the optimistic
// figure (`WidgetStore.snapshot`), and the app drains it into the ledger the
// next time it is active (`AppEnvironment.drainPendingWater`) — through the
// same `addWaterGlass` the Pulse tab's tap uses, so a queued glass and a tapped
// one are the same row.
//
// ── AND WHY IT IS IN OnyxCore AND NOT BESIDE `AddWaterIntent` (W4) ──────────
// It was in `Shared/`, which is compiled into the phone app and the phone's
// widget extension and NEITHER watch target — so the moment the wrist grew a
// "+1 glass" button, the only way to reach `glassMl` from `WatchModel` was to
// write `250` again. There were already two spellings of that number
// (`OnyxFigures` carries one with a comment promising it matches this one),
// and a third on a device that cannot even see the first is how a glass
// becomes 250 ml here and 300 ml there.
//
// Nothing in this type is iOS: it is a `UserDefaults` key, an addition and a
// take. `WatchTiles` in this same folder already owns a suite for the same
// kind of reason. `AddWaterIntent` — which IS iOS, and which writes to the
// phone's own App Group — stays in `Shared/`.

/// Millilitres tapped somewhere that cannot write, waiting for something that
/// can.
public enum PendingWater {
    public static let key = "onyx.pending.waterMl"
    /// One glass. The same 250 the Pulse tab's water row adds, the watch's
    /// Fuel page posts, and the Control Centre button queues.
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
