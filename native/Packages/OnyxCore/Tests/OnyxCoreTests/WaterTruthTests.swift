import Foundation
import Testing
@testable import OnyxCore

/// The one rule the Nutrition tab and the widget both read.
///
/// Four cases, because the bug was that there were two answers to them: the tab
/// read `daily_logs.water_ml` alone and the widget preferred the `water_intake`
/// ledger. The tab's own test (`WaterRowTests`) and the widget builder's
/// (`WidgetSnapshotBuilderTests`) each assert their surface against THIS
/// function over the same four shapes, which is what "they agree" means when
/// the two live in modules that cannot see each other.
@Suite("Water: one truth")
struct WaterTruthTests {

    @Test("the ledger beats the flat row")
    func ledgerWins() {
        // The flat column is a projection, and a projection is only as fresh as
        // its last writer. Three glasses tapped since the ingest last ran are
        // in the ledger and not yet in `water_ml`.
        #expect(WaterTruth.ml(log: 500, ledger: [500, 250, 250]) == 1000)
    }

    @Test("an empty ledger falls back to the flat row")
    func fallsBack() {
        // A day pulled from the server before `water_intake` came down, and a
        // row the web app wrote. Both are real water and neither has a ledger.
        #expect(WaterTruth.ml(log: 1750, ledger: []) == 1750)
    }

    @Test("both empty is nil, and nil is not zero")
    func nothingIsNil() {
        // "Nobody has been able to ask yet" is a different claim from "you
        // drank nothing", and only the caller can render the difference.
        #expect(WaterTruth.ml(log: nil, ledger: []) == nil)
    }

    @Test("a stored zero reads as untracked, the way the scorer reads it")
    func zeroFlatRowIsUntracked() {
        #expect(WaterTruth.ml(log: 0, ledger: []) == nil)
        #expect(WaterTruth.ml(log: -1, ledger: []) == nil)
    }

    @Test("rows that exist and add to nothing are a measured day")
    func zeroLedgerIsAnAnswer() {
        // The `> 0` guard belongs to the projection, where a zero is what the
        // column looks like before anything wrote to it. A ledger row is a
        // deliberate act, so its sum is an answer even at zero — and this is
        // the one case where the two stores must NOT be read the same way.
        #expect(WaterTruth.ml(log: 900, ledger: [0]) == 0)
    }

    @Test("order does not change the sum")
    func orderFree() {
        #expect(WaterTruth.ml(log: nil, ledger: [250, 1000, 500])
                == WaterTruth.ml(log: nil, ledger: [1000, 500, 250]))
    }
}
