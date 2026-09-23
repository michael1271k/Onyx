import Foundation
import Testing
@testable import OnyxCore

/// Overhaul W0 — the two wire-adjacent types the watch and logger lanes
/// compile against. The JSON goldens live in `OnyxDataTests/WatchPayloadTests`
/// where the wire encoder (`OnyxJSON`) is.
@Suite("Overhaul contract — EffortBand, SessionMasthead")
struct OverhaulContractTests {

    @Test("the eight-stop ladder folds into four bands; nil and off-ladder are steady")
    func effortBandsFromTheLadder() {
        let expected: [Double: EffortBand] = [
            5: .steady, 6.5: .steady, 7.5: .steady,
            8: .hard, 8.5: .hard, 9: .hard,
            9.5: .veryHard,
            10: .failure,
        ]
        #expect(Set(Effort.ladder.map(\.value)) == Set(expected.keys), "every rung is mapped")
        for (rpe, band) in expected {
            #expect(EffortBand(rpe: rpe) == band, "rpe \(rpe)")
        }
        #expect(EffortBand(rpe: nil) == .steady)
        #expect(EffortBand(rpe: 7) == .steady)      // a legacy CR10 row, off the ladder
        #expect(EffortBand(rpe: 9.2) == .steady)
        #expect(EffortBand(rpe: .nan) == .steady)
        #expect(EffortBand.allCases.map(\.rawValue) == ["steady", "hard", "veryHard", "failure"])
    }

    @Test("the masthead's HR spark is exactly six points, or empty with no HR")
    func mastheadSparkIsSixPoints() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let none = SessionMasthead(name: "Upper A", durationSec: 3_120, tonnageKg: 8_450,
                                   avgBpm: nil, prCount: 0, hrSpark: [], startedAt: start)
        #expect(none.hrSpark.isEmpty)

        // Twelve samples bucket into six means, in order.
        let twelve = (1...12).map(Double.init)
        let bucketed = SessionMasthead(name: "Upper A", durationSec: 3_120, tonnageKg: 8_450,
                                       avgBpm: 131, prCount: 2, hrSpark: twelve, startedAt: start)
        #expect(bucketed.hrSpark == [1.5, 3.5, 5.5, 7.5, 9.5, 11.5])

        // Fewer than six still come out as six (nearest sample per slot).
        #expect(SessionMasthead.spark([100, 140]).count == 6)
        #expect(SessionMasthead.spark([100, 140]).first == 100)
        #expect(SessionMasthead.spark([100, 140]).last == 140)
        // Six in, the same six out.
        let six = [120.0, 130, 140, 150, 145, 125]
        #expect(SessionMasthead.spark(six) == six)
        #expect(SessionMasthead.spark([]) == [])
    }
}
