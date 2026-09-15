import Foundation

/// How much water a day holds. ONE rule, for every surface that prints it.
///
/// ── WHY THIS EXISTS ─────────────────────────────────────────────────────────
/// There were two rules. The Nutrition tab read `daily_logs.water_ml` and
/// nothing else; `WidgetSnapshotBuilder` preferred the `water_intake` ledger
/// sum and fell back to the flat row. So the tab and the tile could print
/// different litres for the same day and neither was wrong about what it read.
///
/// The split mattered most on the day it was most visible: `clearWaterOverride`
/// empties the ledger and, until W1, nilled the flat column too, and the tab
/// rendered `— / 3.0 L` from then until the next successful HealthKit ingest —
/// which on a phone where the read was denied is never.
///
/// ── THE LEDGER LEADS, BECAUSE THE LEDGER IS THE LOG ─────────────────────────
/// `water_intake` is the append-only record: HealthKit's own row, every glass
/// tapped on the tab, and an override when one is standing. `daily_logs.water_ml`
/// is a PROJECTION of it, written by `addWaterGlass` and by the ingest, and a
/// projection is only ever as fresh as its last writer. When the ledger has
/// rows, it is the answer. The flat row is the fallback for a day pulled from
/// the server before the ledger came down, and for a row the web app wrote.
///
/// ── AND NIL IS A THIRD ANSWER, NOT A ZERO ───────────────────────────────────
/// Nothing in either store means the day has not been measured yet, which is
/// not the same claim as "you drank nothing". Callers render the difference:
/// the tab says "Waiting for Apple Health" on a day the ingest still covers.
///
/// Plain `Double`s rather than the mirror rows because `OnyxCore` cannot see
/// `OnyxData`, and because the rule has nothing to do with how either store is
/// shaped — it is two numbers and an order of preference.
public enum WaterTruth {

    /// The day's millilitres, or nil when neither store has been written.
    ///
    /// - Parameters:
    ///   - log: `daily_logs.water_ml` for the date.
    ///   - ledger: every `water_intake.amount_ml` on the date, in any order.
    public static func ml(log: Double?, ledger: [Double]) -> Double? {
        // A non-empty ledger is the answer even when it sums to zero: rows that
        // exist and add to nothing is a measured day, and the `> 0` guard below
        // belongs only to the projection, where a stored zero is what a day
        // looks like before anything wrote to it.
        if !ledger.isEmpty { return ledger.reduce(0, +) }
        // Zero or less reads as untracked — the rule the scorer already applies
        // to this column, and the reason the tab has always treated it that way.
        guard let log, log > 0 else { return nil }
        return log
    }
}
