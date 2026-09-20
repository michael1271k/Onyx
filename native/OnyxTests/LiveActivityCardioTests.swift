import Testing
import Foundation
import OnyxCore
@testable import Onyx

/// The two halves of putting a treadmill bout on the Lock Screen: a wire that
/// survives its own past, and a pace that cannot divide by zero.
///
/// ── WHY THE DECODE IS TESTED AND NOT JUST DOCUMENTED ────────────────────────
/// `ContentState` carries the rule in a comment — every field added after the
/// first release is Optional — and the rule is one keystroke from being broken
/// by someone adding the obvious `var cardioElapsedSec: Int`. Nothing about
/// that build fails: it compiles, the tests pass, the card draws. It breaks on
/// the phone of a user who UPDATES MID-WORKOUT, because ActivityKit decodes the
/// activity it is already holding with the new type, a synthesized `Decodable`
/// requires every non-optional key, the decode throws, `Activity.activities`
/// hands back nothing, and the workout in front of them loses its card to an
/// orphan nothing can end.
///
/// So the rule gets a test that fails on the keystroke rather than on the
/// update: a payload in the PREVIOUS shape has to decode here.
@Suite("Live Activity · the cardio bout")
struct LiveActivityCardioTests {

    // MARK: - The Optional rule

    /// Exactly the keys `ContentState` had before the bout existed. A
    /// synthesized encoder writes `encodeIfPresent` for an Optional, so a card
    /// encoded by the old build carries the ten required keys and nothing else
    /// — this is that payload, by hand, so it cannot drift with the type.
    private static let previousSchemaJSON = """
    {
      "exercise": "Seated Cable Row (Wide Grip)",
      "setLabel": "Set 3 of 4",
      "load": "42.5 kg × 12",
      "rpe": "RPE 8",
      "lastTime": "40 kg × 12",
      "volume": "1 074 kg",
      "setsDone": 9,
      "setsPlanned": 22,
      "prsThisSession": 1,
      "dayKey": "cb_b"
    }
    """

    @Test("A card encoded before the bout existed still decodes")
    func previousSchemaDecodes() throws {
        let state = try JSONDecoder().decode(
            OnyxWorkoutAttributes.ContentState.self,
            from: Data(Self.previousSchemaJSON.utf8)
        )
        // The activity survives, which is the whole point …
        #expect(state.exercise == "Seated Cable Row (Wide Grip)")
        #expect(state.setsDone == 9)
        // … and a card with no bout on it says so, rather than showing 0:00.
        #expect(state.cardioElapsedSec == nil)
        #expect(state.cardioDistanceKm == nil)
        #expect(cardioLine(sec: state.cardioElapsedSec, km: state.cardioDistanceKm) == nil)
        // W4's field, on the same terms: a card encoded before the wrist's
        // heart rate was on the wire decodes with no rate, and every reader
        // is an `if let` — so the band and the island draw what they drew.
        #expect(state.bpm == nil)
    }

    // MARK: - The wrist's heart rate (W4)

    /// The rule again, for the field this wave added — and stated as its own
    /// test rather than left to the assertion above, because the payload
    /// above is a memory of ONE past shape and `bpm` has to survive every
    /// shape that has ever been encoded, including the one with a bout on it.
    @Test("A card from any previous build decodes with no heart rate")
    func bpmIsAbsentOnEveryOlderCard() throws {
        // The richest payload a pre-W4 build could write: every optional it
        // knew about, filled. If `bpm` had been added as a required key this
        // would throw, which is the in-flight workout losing its card.
        let rich = """
        {
          "exercise": "Treadmill", "setLabel": "", "load": "", "rpe": "",
          "lastTime": "", "volume": "0 kg", "setsDone": 0, "setsPlanned": 4,
          "prsThisSession": 0, "dayKey": "cb_b",
          "nextExercise": "Chest Press", "lastRpe": "RPE 9",
          "restEndsAt": 780000000, "timerOrigin": 779999000,
          "isPaused": false, "elapsed": "12:30",
          "primaryMuscle": "cardio", "rpeValue": 8.5, "restTotalSec": 150,
          "cardioElapsedSec": 750, "cardioDistanceKm": 0.37
        }
        """
        let state = try JSONDecoder().decode(
            OnyxWorkoutAttributes.ContentState.self, from: Data(rich.utf8)
        )
        #expect(state.bpm == nil)
        #expect(state.cardioElapsedSec == 750)
        #expect(state.restTotalSec == 150)
    }

    /// And the other direction, the one `newKeysAreIgnorable` makes for the
    /// bout: a nil rate must be ABSENT from the wire, not `null` and above
    /// all not `0`. A zero would be a heart that had stopped.
    @Test("A nil heart rate is absent from the wire, and a real one is on it")
    func bpmEncoding() throws {
        var state = Self.treadmill
        state.bpm = nil
        let without = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(state)) as? [String: Any]
        )
        #expect(without["bpm"] == nil)

        state.bpm = 142
        let with = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(state)) as? [String: Any]
        )
        #expect(with["bpm"] as? Int == 142)
        // Round-trips, so the card the phone composed is the card the
        // extension draws.
        let back = try JSONDecoder().decode(
            OnyxWorkoutAttributes.ContentState.self, from: try JSONEncoder().encode(state)
        )
        #expect(back.bpm == 142)
    }

    /// The mistake, for this field, in the two lines it takes to make it.
    @Test("A required heart rate would have killed the running activity")
    func requiredBpmBreaksIt() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                RequiredBpm.self, from: Data(Self.previousSchemaJSON.utf8)
            )
        }
    }

    private struct RequiredBpm: Decodable {
        var exercise: String
        var bpm: Int
    }

    /// The same payload read by the shape the rule forbids — the two fields
    /// written without their `?`. A synthesized `Decodable` demands every
    /// non-optional key, the old card does not have them, and the throw is a
    /// user's in-flight workout losing its Lock Screen.
    ///
    /// Kept as a test rather than a paragraph because this is the failure that
    /// cannot be seen from the desk it is written at: the build is green, the
    /// card draws, and it only breaks on a phone that updated mid-session.
    @Test("A required key would have killed the running activity")
    func requiredKeyBreaksIt() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                RequiredKeys.self, from: Data(Self.previousSchemaJSON.utf8)
            )
        }
    }

    /// The mistake, in as few lines as it takes to make it: the bout's two
    /// fields with no `?` on them. Only the keys under test — a `Decodable`
    /// reads what it declares.
    private struct RequiredKeys: Decodable {
        var exercise: String
        var cardioElapsedSec: Int
        var cardioDistanceKm: Double
    }

    /// The other direction: the new keys must be ignorable, not just optional.
    /// A decoder that has never heard of them — every build before this one —
    /// reads the same payload and is unaffected.
    @Test("A decoder that has never heard of the bout is unaffected by it")
    func newKeysAreIgnorable() throws {
        let data = try JSONEncoder().encode(Self.treadmill)
        // Guard against a vacuous pass: if the keys were not written, the
        // decode below proves nothing.
        let raw = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(raw["cardioElapsedSec"] != nil)
        #expect(raw["cardioDistanceKm"] != nil)

        let old = try JSONDecoder().decode(PreviousSchema.self, from: data)
        #expect(old.exercise == "Treadmill")
        #expect(old.dayKey == "cb_b")
    }

    /// `ContentState` as it read before the bout — the shape the old decoder
    /// has. Written out rather than derived, because a mirror of the live type
    /// would change with it and stop being a memory of anything.
    private struct PreviousSchema: Codable {
        var exercise: String
        var setLabel: String
        var load: String
        var rpe: String
        var lastTime: String
        var volume: String
        var setsDone: Int
        var setsPlanned: Int
        var prsThisSession: Int
        var nextExercise: String?
        var lastRpe: String?
        var restEndsAt: Date?
        var timerOrigin: Date?
        var isPaused: Bool?
        var elapsed: String?
        var primaryMuscle: String?
        var rpeValue: Double?
        var restTotalSec: Int?
        var dayKey: String
    }

    /// A ten-minute warm-up walk, four minutes in — `load` empty, because a
    /// treadmill row's `weightKg` and `reps` are zeros and the producer no
    /// longer composes "0 kg × 0" out of them.
    private static let treadmill = OnyxWorkoutAttributes.ContentState(
        exercise: "Treadmill",
        setLabel: "Set 1 of 1",
        load: "",
        rpe: "",
        lastTime: "",
        volume: "0 kg",
        setsDone: 0,
        setsPlanned: 22,
        prsThisSession: 0,
        primaryMuscle: "cardio",
        cardioElapsedSec: 750,
        cardioDistanceKm: 0.37,
        dayKey: "cb_b"
    )

    // MARK: - The line

    @Test("The bout reads as a clock, a distance and a pace")
    func theLine() {
        #expect(cardioLine(sec: 750, km: 0.37) == "12:30 · 0.37 km · 33:47 /km")
        // 5 km in 28:30 is the pace the decision names.
        #expect(cardioLine(sec: 1710, km: 5) == "28:30 · 5 km · 5:42 /km")
    }

    /// ── THE STATE EVERY BOUT STARTS IN ─────────────────────────────────────
    /// A treadmill block that has begun and not moved is 0.00 km, and minutes
    /// over zero kilometres is `inf` — "∞ /km" on a Lock Screen, or a crash in
    /// a formatter that was not expecting it. The pace is simply dropped: the
    /// clock is still true, and a line that says less is not a line that lies.
    @Test("A bout that has not moved yet has no pace, not an infinite one")
    func noDistanceNoPace() {
        #expect(cardioLine(sec: 120, km: 0) == "2:00")
        #expect(cardioLine(sec: 120, km: nil) == "2:00")
        let line = try! #require(cardioLine(sec: 120, km: 0))
        #expect(!line.contains("∞"))
        #expect(!line.contains("—"))
        #expect(!line.contains("inf"))
    }

    @Test("A bout with no clock and no distance is not a bout")
    func nothingIsNil() {
        #expect(cardioLine(sec: nil, km: nil) == nil)
        #expect(cardioLine(sec: 0, km: 0) == nil)
    }

    /// The 40 mm face drops the pace for width — see `cardioLine`.
    @Test("The wrist gets the same line without the pace")
    func watchDropsThePace() {
        #expect(cardioLine(sec: 1710, km: 5, pace: false) == "28:30 · 5 km")
    }

    /// Nothing here may divide by zero, overflow or trap, whatever the row
    /// holds — a restored bout can carry any of these, and the card is drawn on
    /// a locked phone where a trap takes the whole widget extension down.
    @Test("No pair of numbers it can be handed produces a bad reading")
    func everyLineIsWellFormed() {
        let seconds: [Int?] = [nil, 0, 1, 59, 600, 86_400, -30]
        let distances: [Double?] = [nil, 0, 0.001, 0.37, 5, 42.195, -1, .nan, .infinity]
        for sec in seconds {
            for km in distances {
                guard let line = cardioLine(sec: sec, km: km) else { continue }
                #expect(!line.contains("∞"))
                #expect(!line.contains("inf"))
                #expect(!line.contains("nan"))
                #expect(!line.hasSuffix("·"))
            }
        }
    }
}
