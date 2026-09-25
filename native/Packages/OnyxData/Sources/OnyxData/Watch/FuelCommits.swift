import Foundation
import GRDB

/// The fuel half of the watch push policy (Precision D4, seam 4).
///
/// ── WHY THE WRIST NEEDS TO KNOW WHICH TABLE ─────────────────────────────────
/// Every commit reaches the watch through the widget reload's 2 s debounce
/// and then a 30 s trailing throttle (`AppEnvironment.scheduleWatchPush`),
/// because a session logs a set a minute and each push is a `.full` snapshot
/// build. That is right for sets and wrong for a glass of water: the person
/// who taps +250 on the phone looks at the wrist next, and half a minute is
/// long enough to decide the watch is broken. So a commit that touched what
/// the Fuel page and the Water/Food petals draw is told apart here, and the
/// push skips the throttle — keeping the debounce — exactly as the lifecycle
/// push does.
///
/// `daily_logs` is left out on purpose: a Health sync writes it on every
/// foreground, and letting it skip the throttle would put the snapshot build
/// back on every pull. The water glass writes `water_intake` beside it, and
/// that is the table that fires.
///
/// A mirror pull re-saves these rows too (windowed/whole-table pulls), and
/// that fires the signal. Left alone on purpose: the pull already schedules a
/// throttled push, and the bypass sends that SAME one push 28 s earlier —
/// `pushWatchContext` cancels the pending throttle — so it adds no build.
public extension AppDatabase {

    /// Water, food and the supplement stack.
    static let fuelTables = ["water_intake", "nutrition_entries", "supplement_log", "custom_supplements"]

    /// Fires after a commit that wrote any of `fuelTables`, on the writer's
    /// queue. Cancel the return value to stop.
    func onFuelCommit(_ handler: @escaping @Sendable () -> Void) -> AnyDatabaseCancellable {
        DatabaseRegionObservation(tracking: Self.fuelTables.map { Table($0) })
            .start(in: writer, onError: { _ in }, onChange: { _ in handler() })
    }
}
