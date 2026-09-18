import Foundation
import Testing
@testable import OnyxCore

/// The wire budget and the projection — the two things a wrong `WatchTiles`
/// gets wrong silently: an oversized payload makes every context push slower
/// on a channel nothing measures, and a projection that reads the wrong
/// snapshot field draws a confident wrong number on the face least able to
/// explain itself.
@Suite("Watch tiles")
struct WatchTilesTests {

    private var full: WatchTiles {
        WatchTiles(
            date: "2026-09-18", battery: 72, score: 81, sleepMin: 445, sleepScore: 58,
            waterMl: 1750, waterGoalMl: 3000, steps: 8_412, stepsGoal: 10_000,
            kcal: 1_640, kcalGoal: 2_150, todayLabel: "Delts & Arms", todayLogged: false,
            restDay: false, stressIndex: 41.5, sorenessCount: 3,
            week: (0..<7).map { WatchTiles.WeekDay(trained: $0 % 2 == 0, fuelHit: $0 != 3, sleepHit: $0 > 1) },
            medianBedtime: "23:12", lastBedtime: "00:16"
        )
    }

    @Test("a full payload round-trips and stays under 2 KB")
    func roundTripsUnderBudget() throws {
        let data = try JSONEncoder().encode(full)
        #expect(data.count <= 2_048, "wire size \(data.count) B")
        #expect(try JSONDecoder().decode(WatchTiles.self, from: data) == full)
    }

    @Test("nil readings are absent on the wire, not null and not zero")
    func nilIsAbsent() throws {
        let empty = WatchTiles(date: "2026-09-18", todayLabel: "Rest", todayLogged: false, restDay: true)
        let object = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(empty)) as? [String: Any]
        )
        #expect(object.keys.sorted() == ["d", "r", "td", "tl"])
        #expect(try JSONDecoder().decode(WatchTiles.self, from: try JSONEncoder().encode(empty)) == empty)
    }

    @Test("the projection reads the snapshot's own fields")
    func projectsTheSnapshot() {
        let snapshot = OnyxSnapshot(
            date: "2026-09-18", generatedAt: "2026-09-18T06:00:00.000Z",
            battery: 72, score: 81,
            sleep: .init(minutes: 445, score: 58, startTime: "2026-09-17T21:16:00.000Z", medianBedtime: "23:12"),
            weight: .init(), macros: .init(kcal: 1_640.4, kcalGoal: 2_150),
            water: .init(ml: 1_750, goalMl: 3_000), steps: .init(count: 8_412, goal: 10_000),
            workout: .init(label: "Delts & Arms", dayKey: "arms", logged: false, isRestDay: false),
            week: .init(sessions: 3, volumeKg: nil, prs: 0, sets: 40),
            weekRings: (0..<7).map { OnyxSnapshot.WeekRingDay(date: "2026-09-1\($0)", trained: $0 % 2 == 0, fuelHit: true, sleepHit: false) },
            soreness: [.init(landmark: "Quads", level: 2), .init(landmark: "Glutes", level: 1)],
            stress: .init(index: 41.5)
        )
        let tiles = WatchTiles(snapshot)
        #expect(tiles.battery == 72)
        #expect(tiles.sleepMin == 445)
        #expect(tiles.kcal == 1_640)
        #expect(tiles.kcalRemaining == 510)
        #expect(tiles.waterMl == 1_750)
        #expect(tiles.steps == 8_412)
        #expect(tiles.todayLabel == "Delts & Arms")
        #expect(tiles.stressIndex == 41.5)
        #expect(tiles.sorenessCount == 2)
        #expect(tiles.week?.count == 7)
        #expect(tiles.week?.map(\.trained) == [true, false, true, false, true, false, true])
        #expect(tiles.medianBedtime == "23:12")
        // Last night's bedtime is the device-zone clock of `startTime`; the
        // exact digits depend on the zone the test runs in, so only its shape
        // is pinned here.
        #expect(tiles.lastBedtime?.count == 5)
    }

    @Test("a snapshot that never asked for soreness projects nil, not zero")
    func sorenessNilIsNotZero() {
        let snapshot = OnyxSnapshot(
            date: "2026-09-18", generatedAt: "2026-09-18T06:00:00.000Z",
            sleep: .init(), weight: .init(), macros: .init(), water: .init(), steps: .init(),
            workout: .init(label: "Rest", dayKey: nil, logged: false, isRestDay: true),
            week: .init(sessions: 0, volumeKg: nil, prs: 0, sets: 0)
        )
        let tiles = WatchTiles(snapshot)
        #expect(tiles.sorenessCount == nil)
        #expect(tiles.week == nil)
        #expect(tiles.kcalRemaining == nil)
        #expect(tiles.restDay)
    }
}
