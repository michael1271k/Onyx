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
            medianBedtime: "23:12", lastBedtime: "00:16",
            weekSets: 84, weekVolumeKg: 12_430, proteinG: 118, proteinGoalG: 185,
            offWrist: OffWristNote(hours: 6, signals: 3)
        )
    }

    @Test("a full payload round-trips and stays under 2 KB")
    func roundTripsUnderBudget() throws {
        let data = try JSONEncoder().encode(full)
        #expect(data.count <= 2_048, "wire size \(data.count) B")
        #expect(try JSONDecoder().decode(WatchTiles.self, from: data) == full)
    }

    /// The budget re-pinned, as the wave that spent some of it (cross-wave
    /// law: extend with optional-and-last fields, then re-pin).
    ///
    /// ── WHY A CEILING AND NOT AN EQUALITY ───────────────────────────────────
    /// An exact byte count would fail on a `Double` that serialises one digit
    /// differently, which is a test that cries about the encoder rather than
    /// about the payload. The number in the message is what a reader wants;
    /// the assertion is that four more fields did not quietly double it.
    @Test("W4's four fields cost the wire under 80 bytes")
    func w4FieldsAreCheap() throws {
        let before = WatchTiles(
            date: full.date, battery: full.battery, score: full.score,
            sleepMin: full.sleepMin, sleepScore: full.sleepScore,
            waterMl: full.waterMl, waterGoalMl: full.waterGoalMl,
            steps: full.steps, stepsGoal: full.stepsGoal,
            kcal: full.kcal, kcalGoal: full.kcalGoal,
            todayLabel: full.todayLabel, todayLogged: full.todayLogged, restDay: full.restDay,
            stressIndex: full.stressIndex, sorenessCount: full.sorenessCount,
            week: full.week, medianBedtime: full.medianBedtime, lastBedtime: full.lastBedtime,
            offWrist: full.offWrist
        )
        let grew = try JSONEncoder().encode(full).count - (try JSONEncoder().encode(before).count)
        #expect(grew > 0, "the four fields encoded nothing")
        #expect(grew < 80, "W4 added \(grew) B to the wire")
    }

    /// App Store W6 re-pins the budget for the one field it spent.
    @Test("W6's off-wrist note costs the wire under 25 bytes, and a pre-W6 payload decodes without it")
    func w6NoteIsCheapAndOptional() throws {
        var without = try JSONDecoder().decode(WatchTiles.self, from: try JSONEncoder().encode(full))
        without = WatchTiles(
            date: without.date, battery: without.battery, score: without.score,
            todayLabel: without.todayLabel, todayLogged: without.todayLogged, restDay: without.restDay
        )
        var with = without
        with = WatchTiles(
            date: with.date, battery: with.battery, score: with.score,
            todayLabel: with.todayLabel, todayLogged: with.todayLogged, restDay: with.restDay,
            offWrist: OffWristNote(hours: 12, signals: 3)
        )
        let grew = try JSONEncoder().encode(with).count - (try JSONEncoder().encode(without).count)
        #expect(grew > 0 && grew < 25, "W6 added \(grew) B to the wire")
        let legacy = #"{"d":"2026-09-18","b":72,"sc":81,"tl":"Rest","td":false,"r":true}"#
        #expect(try JSONDecoder().decode(WatchTiles.self, from: Data(legacy.utf8)).offWrist == nil)
    }

    /// The compatibility half of "optional and last": a payload from a phone
    /// that predates W4 has none of these keys and must still decode.
    @Test("a pre-W4 payload decodes with the four new fields nil")
    func oldPayloadStillDecodes() throws {
        let legacy = #"""
        {"d":"2026-09-18","b":72,"sc":81,"tl":"Delts & Arms","td":false,"r":false}
        """#
        let tiles = try JSONDecoder().decode(WatchTiles.self, from: Data(legacy.utf8))
        #expect(tiles.battery == 72)
        #expect(tiles.weekSets == nil)
        #expect(tiles.weekVolumeKg == nil)
        #expect(tiles.proteinG == nil)
        #expect(tiles.proteinGoalG == nil)
        // And the derived reading over two nils is nil, not zero.
        #expect(tiles.proteinRemaining == nil)
    }

    /// The wrist's optimistic glass (W4).
    @Test("adding water adds to a reading, creates one from nil, and 0 is a no-op")
    func optimisticWater() {
        let logged = WatchTiles(
            date: "2026-09-18", waterMl: 1_750, waterGoalMl: 3_000,
            todayLabel: "Rest", todayLogged: false, restDay: true
        )
        #expect(logged.addingWater(250).waterMl == 2_000)
        // Nothing queued changes nothing at all — the same object, so a page
        // with an empty queue hands the face exactly what arrived.
        #expect(logged.addingWater(0) == logged)

        // ── nil + 250 IS 250, AND THAT IS NOT A BREACH OF "nil IS NOT 0" ────
        // Nil means the phone has sent no water reading for today. The glass
        // you just tapped IS today's water, so the absence is answered rather
        // than preserved.
        let dry = WatchTiles(date: "2026-09-18", todayLabel: "Rest", todayLogged: false, restDay: true)
        #expect(dry.waterMl == nil)
        #expect(dry.addingWater(250).waterMl == 250)
        // …and a payload with nothing queued keeps the absence.
        #expect(dry.addingWater(0).waterMl == nil)
        // Every other field survives the copy.
        #expect(logged.addingWater(250).waterGoalMl == 3_000)
        #expect(logged.addingWater(250).restDay)
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
        // W4's four, off the snapshot's own fields. The week in this fixture
        // has 40 sets and a NIL tonnage (`OnyxSnapshot.Week.volumeKg` is nil,
        // never 0, on a week with no sessions) — so this pins that the
        // projection carries the nil rather than flattening it, which is the
        // mistake the whole payload's header is about.
        #expect(tiles.weekSets == 40)
        #expect(tiles.weekVolumeKg == nil)
        // The fixture's macros carry no protein, so both sides stay nil and
        // the derived reading refuses to subtract.
        #expect(tiles.proteinG == nil)
        #expect(tiles.proteinGoalG == nil)
        #expect(tiles.proteinRemaining == nil)
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
