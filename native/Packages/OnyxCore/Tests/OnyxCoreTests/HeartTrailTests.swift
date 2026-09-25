import Foundation
import Testing
@testable import OnyxCore

/// The wrist's own 24 hours of heart rate (Precision D2/D3) — the series the
/// Heart detail's sparkline and the Live Heart complication's six-block arc
/// are drawn from, and the rule that says when the petal's reading is fresh.
@Suite("Heart trail")
struct HeartTrailTests {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func at(_ minutesAgo: Double, _ bpm: Int) -> HeartTrail.Sample {
        HeartTrail.Sample(at: now.addingTimeInterval(-minutesAgo * 60), bpm: bpm)
    }

    @Test("merge keeps 24 hours, oldest first, one sample per five-minute grain")
    func mergeWindowsAndThins() {
        var trail = HeartTrail()
        trail.merge([at(25 * 60, 70), at(30, 64), at(2, 71), at(1, 73), at(90, 58)], now: now)
        // The 25-hour-old sample is outside the window.
        #expect(trail.samples.map(\.bpm) == [58, 64, 73], "got \(trail.samples.map(\.bpm))")
        // The 2- and 1-minute samples share a grain: the newer one wins.
        #expect(trail.latest?.bpm == 73)
        // A second merge of the same samples changes nothing.
        let before = trail
        trail.merge([at(30, 64), at(1, 73)], now: now)
        #expect(trail == before)
    }

    @Test("runs break at a gap longer than half an hour, never bridge it")
    func runsAreGapAware() {
        var trail = HeartTrail()
        trail.merge([at(300, 60), at(290, 62), at(280, 61), at(120, 70), at(110, 72), at(5, 66)], now: now)
        let runs = trail.runs()
        #expect(runs.map { $0.map(\.bpm) } == [[60, 62, 61], [70, 72], [66]])
    }

    @Test("six four-hour blocks, oldest first, nil where the wrist saw nothing")
    func sixBlocks() {
        var trail = HeartTrail()
        // Block 0 is 24…20 h ago, block 5 is the last four hours.
        trail.merge([at(23 * 60, 60), at(22 * 60, 64), at(3 * 60, 80), at(30, 90)], now: now)
        #expect(trail.blocks(now: now) == [62, nil, nil, nil, nil, 85])
        #expect(HeartTrail().blocks(now: now) == Array(repeating: nil, count: 6))
    }

    @Test("a stale reading goes fresh when a newer sample lands, and an older one never overwrites it")
    func staleToFresh() {
        let stale = LastHeartRate(bpm: 88, at: now.addingTimeInterval(-3 * 3600))
        #expect(WatchHeart.freshness(stale, now: now) == .stale)
        #expect(WatchHeart.freshness(nil, now: now) == .none)

        let adopted = WatchHeart.adopt([at(3, 61), at(1, 63)], over: stale)
        #expect(adopted == LastHeartRate(bpm: 63, at: now.addingTimeInterval(-60)))
        #expect(WatchHeart.freshness(adopted, now: now) == .fresh)

        // A workout reading from ten seconds ago is newer than anything a
        // background delivery brings in: nothing to write.
        let live = LastHeartRate(bpm: 142, at: now.addingTimeInterval(-10))
        #expect(WatchHeart.adopt([at(3, 61)], over: live) == nil)
        #expect(WatchHeart.adopt([], over: stale) == nil)
    }

    @Test("the trail round-trips through its suite")
    func persists() throws {
        let suite = try #require(UserDefaults(suiteName: "HeartTrailTests.\(UUID().uuidString)"))
        var trail = HeartTrail()
        trail.merge([at(30, 64), at(1, 73)], now: now)
        trail.save(to: suite)
        #expect(HeartTrail.load(from: suite) == trail)
        #expect(HeartTrail.load(from: try #require(UserDefaults(suiteName: "empty.\(UUID().uuidString)"))) == nil)
    }
}
