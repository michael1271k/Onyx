import Foundation
import Testing
@testable import OnyxCore

/// Two figures (founder decision Q10): "Sets" = everything performed — working,
/// warm-up and cardio bouts, a pair once, ghosts never; "Working" = the rule
/// every screen already reads.
@Suite("Session set counts")
struct SessionCountsTests {

    static let rows: [VolumeSet] = [
        VolumeSet(weightKg: 0, reps: 0, setType: "warmup"),          // a treadmill bout
        VolumeSet(weightKg: 60, reps: 15, setType: "warmup"),        // a loaded warm-up
        VolumeSet(weightKg: 100, reps: 10), VolumeSet(weightKg: 100, reps: 10), VolumeSet(weightKg: 100, reps: 9),
        VolumeSet(weightKg: 100, reps: 8, setType: "failure"),
        VolumeSet(weightKg: 80, reps: 12, setType: "dropset"),
        VolumeSet(weightKg: 5, reps: 15, side: "L", pairId: "p1"), VolumeSet(weightKg: 5, reps: 14, side: "R", pairId: "p1"),
        VolumeSet(weightKg: 5, reps: 15, side: "L", pairId: "p2", setType: "ghost"),
        VolumeSet(weightKg: 5, reps: 14, side: "R", pairId: "p2", setType: "ghost"),
        VolumeSet(weightKg: 100, reps: 10, setType: "ghost"),
    ]

    @Test("total counts the bout, the warm-up, every working kind, a pair once and no ghost")
    func total() {
        #expect(SessionCounts.total(Self.rows) == 8)
    }

    @Test("working is today's rule: no warm-up, no bout, no ghost, a pair once")
    func working() {
        #expect(SessionCounts.working(Self.rows) == 6)
    }

    @Test("the founder's Thursday: 20 sets, 19 working")
    func upperB() {
        #expect(SessionCounts.total(VolumeBasisTests.upperB) == 20)
        #expect(SessionCounts.working(VolumeBasisTests.upperB) == 19)
    }

    @Test("a lone side is a set; an empty pairId is no pair")
    func loneSideAndEmptyPair() {
        let rows = [
            VolumeSet(weightKg: 5, reps: 15, side: "L", pairId: "p"),
            VolumeSet(weightKg: 5, reps: 15, pairId: ""),
        ]
        #expect(SessionCounts.total(rows) == 2)
    }

    @Test("a pairId with no sides is still one set — the server's count(distinct coalesce(pair_id, id))")
    func sidelessPairMatchesTheServer() {
        let rows = [
            VolumeSet(weightKg: 15, reps: 12, pairId: "p"),
            VolumeSet(weightKg: 15, reps: 12, pairId: "p"),
        ]
        #expect(SessionCounts.total(rows) == 1)
        #expect(SessionCounts.working(rows) == 1)
    }
}
