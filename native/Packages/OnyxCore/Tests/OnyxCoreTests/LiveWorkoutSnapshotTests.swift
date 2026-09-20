import Foundation
import Testing
@testable import OnyxCore

/// The live card's payload — and the two things a wrong one gets wrong
/// silently: a stale blob that keeps claiming a workout is running long after
/// it finished, and a wire shape whose keys drift from the ones a shipped
/// extension is reading.
@Suite("Live workout snapshot")
struct LiveWorkoutSnapshotTests {

    /// A whole second, deliberately.
    ///
    /// ── `Date` DOES NOT SURVIVE A JSON ROUND TRIP EXACTLY ───────────────────
    /// `JSONEncoder`'s default strategy writes `timeIntervalSinceReferenceDate`
    /// as decimal text, and the last bits of a `Date()` taken from the system
    /// clock do not come back — so an `==` on a decoded snapshot fails on a
    /// field nothing in this app reads to the microsecond. The fixture is
    /// therefore built on whole seconds, and the loss is recorded here rather
    /// than papered over: `updatedAt` feeds a 45-MINUTE staleness window and
    /// `restEndsAt` feeds a countdown drawn to the second, so nothing that
    /// reads either can tell.
    private static let fixedNow = Date(timeIntervalSince1970: 1_758_326_400)

    private func sample(
        bpm: Int? = 142, restEndsAt: Date? = nil, updatedAt: Date = LiveWorkoutSnapshotTests.fixedNow
    ) -> LiveWorkoutSnapshot {
        LiveWorkoutSnapshot(
            exercise: "Neutral-Grip Lat Pulldown",
            setsDone: 7, setsPlanned: 12,
            bpm: bpm, restEndsAt: restEndsAt,
            dayKey: "cb_b", primaryMuscle: "lats",
            updatedAt: updatedAt
        )
    }

    @Test("it round-trips")
    func roundTrips() throws {
        let data = try JSONEncoder().encode(sample())
        #expect(try JSONDecoder().decode(LiveWorkoutSnapshot.self, from: data) == sample())
    }

    /// Short keys, and the same rule the tiles follow: this is decoded on
    /// every timeline of a widget that redraws several times a minute.
    @Test("the keys are the short ones, and a nil reading is absent")
    func wireShape() throws {
        let bare = LiveWorkoutSnapshot(
            exercise: "Chest Press", setsDone: 0, setsPlanned: 3,
            updatedAt: Date(timeIntervalSince1970: 1_758_326_400)
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(bare)) as? [String: Any]
        )
        // Four required fields and nothing else: no `null`s, and above all no
        // `"h": 0` — a heart rate the sensor has not reported yet is absent,
        // not a heart that has stopped.
        #expect(object.keys.sorted() == ["e", "sd", "sp", "u"])
    }

    /// The guard that stops a jetsammed session haunting the Smart Stack.
    @Test("a snapshot goes stale, and `load` refuses a stale one")
    func staleness() {
        let now = Date()
        let fresh = sample(updatedAt: now.addingTimeInterval(-60))
        #expect(fresh.isLive(at: now))

        // One second inside the window and one second outside it.
        let edge = sample(updatedAt: now.addingTimeInterval(-LiveWorkoutSnapshot.staleAfter + 1))
        #expect(edge.isLive(at: now))
        let past = sample(updatedAt: now.addingTimeInterval(-LiveWorkoutSnapshot.staleAfter - 1))
        #expect(past.isLive(at: now) == false)

        // A clock that has run BACKWARDS past the window — a timezone change,
        // a manual date — is not evidence of a workout either.
        let future = sample(updatedAt: now.addingTimeInterval(LiveWorkoutSnapshot.staleAfter + 1))
        #expect(future.isLive(at: now) == false)
        // …but a few seconds of skew is not a reason to blank a live card.
        #expect(sample(updatedAt: now.addingTimeInterval(5)).isLive(at: now))
    }

    /// Save, read back, clear — through a real suite, because the whole
    /// mechanism is a `UserDefaults` key two processes share.
    @Test("save, load and clear round-trip through a suite")
    func suiteRoundTrip() throws {
        let name = "onyx.test.live.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { UserDefaults().removePersistentDomain(forName: name) }

        // `Date()`, not the fixture's fixed instant: `load` applies the
        // staleness guard, and the fixture is deliberately a date in the past.
        #expect(LiveWorkoutSnapshot.load(from: defaults) == nil)
        sample(updatedAt: Date()).save(to: defaults)
        #expect(LiveWorkoutSnapshot.load(from: defaults)?.exercise == "Neutral-Grip Lat Pulldown")

        // The staleness guard lives in `load`, not in the caller: every
        // caller would otherwise have to make the same check and the one
        // that forgot would draw a phantom.
        sample(updatedAt: Date(timeIntervalSinceNow: -LiveWorkoutSnapshot.staleAfter - 1)).save(to: defaults)
        #expect(LiveWorkoutSnapshot.load(from: defaults) == nil)

        sample(updatedAt: Date()).save(to: defaults)
        #expect(LiveWorkoutSnapshot.load(from: defaults) != nil)
        LiveWorkoutSnapshot.clear(from: defaults)
        #expect(LiveWorkoutSnapshot.load(from: defaults) == nil)
    }

    /// The two constants two targets agree on by reference rather than by
    /// literal — the failure they prevent is silent on both sides.
    @Test("the suite is the watch's, and the kind is namespaced")
    func constants() {
        #expect(LiveWorkoutSnapshot.suiteName == WatchTiles.suiteName)
        #expect(LiveWorkoutSnapshot.key != WatchTiles.key)
        #expect(LiveWorkoutSnapshot.widgetKind.hasPrefix("OnyxWatch."))
    }

    // MARK: - The rate ages faster than the session

    /// A SESSION is live for 45 minutes; a heart RATE is a reading for two.
    ///
    /// The case that forced this: a session paused for twenty minutes
    /// republishes on the pause, so `updatedAt` is seconds old while the
    /// number came off the sensor before the pause started — and the circular
    /// complication's entire content is that number.
    @Test("a rate ages at two minutes even inside a live session")
    func theRateAgesFaster() {
        let now = Date()
        let taken = now.addingTimeInterval(-20 * 60)
        let paused = LiveWorkoutSnapshot(
            exercise: "Chest Press", setsDone: 4, setsPlanned: 9,
            bpm: 142, updatedAt: now, bpmAt: taken
        )
        // The session is emphatically still live …
        #expect(paused.isLive(at: now))
        // … and the rate is emphatically not a reading.
        #expect(paused.freshBpm(at: now) == nil)
        #expect(paused.bpm == 142, "the number is still carried, just not vouched for")

        let fresh = LiveWorkoutSnapshot(
            exercise: "Chest Press", setsDone: 4, setsPlanned: 9,
            bpm: 142, updatedAt: now, bpmAt: now.addingTimeInterval(-30)
        )
        #expect(fresh.freshBpm(at: now) == 142)
    }

    /// The window is ONE number, because both devices draw one sensor.
    @Test("the watch and the phone age a reading over the same window")
    func oneWindow() {
        #expect(LiveWorkoutSnapshot.bpmStaleAfter == 120)
        // Far shorter than the session's, which is the whole point.
        #expect(LiveWorkoutSnapshot.bpmStaleAfter < LiveWorkoutSnapshot.staleAfter)
    }

    /// `bpmAt` is optional-and-last like everything else here: a snapshot
    /// written before it existed answers the rate it carries rather than
    /// blanking a face that was right a minute ago.
    @Test("a snapshot with no bpmAt still answers its rate")
    func undatedRateDegradesHonestly() {
        let old = LiveWorkoutSnapshot(
            exercise: "Row", setsDone: 1, setsPlanned: 3, bpm: 118, bpmAt: nil
        )
        #expect(old.freshBpm() == 118)
        // …and no rate at all is nil whatever the dates say.
        let none = LiveWorkoutSnapshot(exercise: "Row", setsDone: 1, setsPlanned: 3)
        #expect(none.freshBpm() == nil)
    }

    // MARK: - The de-dupe

    /// `WatchModel` reaches the writer twice on a single commit — once
    /// through `seedCursor`, once from `startRest` with the new rest on it —
    /// and each publish costs a timeline reload and a relevance
    /// invalidation on a device that budgets both.
    @Test("two snapshots that draw the same thing are the same reading")
    func sameReadingIgnoresTheClocks() {
        let a = sample(updatedAt: Date(timeIntervalSince1970: 1_000))
        let b = sample(updatedAt: Date(timeIntervalSince1970: 2_000))
        #expect(a != b, "they differ, or this test proves nothing")
        #expect(a.sameReading(as: b))
        // …and every field a face DRAWS is compared.
        #expect(a.sameReading(as: sample(bpm: 143)) == false)
        #expect(a.sameReading(as: sample(restEndsAt: Date())) == false)
        #expect(a.sameReading(as: nil) == false)
        let renamed = LiveWorkoutSnapshot(
            exercise: "Chest Press", setsDone: 7, setsPlanned: 12,
            bpm: 142, dayKey: "cb_b", primaryMuscle: "lats"
        )
        #expect(a.sameReading(as: renamed) == false)
    }
}
