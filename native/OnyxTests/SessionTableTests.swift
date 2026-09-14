import Foundation
import Testing
import OnyxCore
@testable import Onyx

/// Which table a movement's card draws, and therefore whether its heading and
/// its rows can agree.
///
/// ── WHY THIS IS THE ONE THING HERE WORTH A TEST ─────────────────────────────
/// `SetRow.layout(_:)` is the only branch in the session ledger that four
/// different views read: the column heads, every row's `figures`, the reserved
/// delta line and the spoken label. Get it wrong and nothing crashes and
/// nothing fails to build — the card simply draws `KG` over a column of
/// minutes, or three permanent em-dashes under a treadmill, and the only way to
/// find out is to look at it.
///
/// Everything else this wave changed is a colour, a position or a font, which
/// a screenshot answers faster than an assertion can.
@Suite("Session ledger — which table a card draws")
struct SessionTableTests {

    // ── FIXTURES THROUGH `Codable`, NOT THROUGH A MEMBERWISE INIT ───────────
    // `DetailSet` and `DetailExercise` are `public struct`s in OnyxCore whose
    // memberwise inits are internal to that module, and this bundle only
    // `@testable`s the app. They are `Codable` for the golden vectors, so the
    // vectors' own door is the one that opens from here.
    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    /// One set, with only the keys the layout actually reads.
    private func set(_ number: Int, kg: Double, reps: Double,
                     cardio: Bool = false, side: String? = nil) throws -> DetailSet {
        let axes = cardio ? #", "durationSec": 300, "distanceKm": 0.37"# : ""
        let lr = side.map { #", "side": "\#($0)""# } ?? ""
        return try decode("""
        {"setNumber": \(number), "weightKg": \(kg), "reps": \(reps),
         "isPr": false, "setType": "working"\(axes)\(lr)}
        """)
    }

    private func report(_ sets: [DetailSet], timed: Bool = false) throws -> SessionAnalysis.ExerciseReport {
        let detail: DetailExercise = try decode("""
        {"exerciseId": "x", "name": "X", "order": 0, "muscleGroups": [],
         "isCompound": true, "sets": [], "workingSets": 0, "topKg": 0, "volumeKg": 0}
        """)
        return SessionAnalysis.ExerciseReport(
            detail: detail, canonical: "X", timed: timed,
            rows: SessionDetail.toRows(sets),
            prevDate: nil, previousSets: [], cue: nil,
            stats: SessionDetail.exerciseStats(detail),
            window: nil, atCeiling: 0, spark: [], records: [:]
        )
    }

    @Test("A loaded lift gets three tracks, and they can be compared")
    func loaded() throws {
        let layout = SetRow.layout(try report([
            try set(1, kg: 42.5, reps: 10),
            try set(2, kg: 42.5, reps: 9)
        ]))
        #expect(layout == .loaded)
        #expect(layout.heads == ["KG", "REPS", "RPE"])
        #expect(layout.comparable)
    }

    /// The deck drops the `KG` track on a Reverse Crunch for the same reason:
    /// a `0kg` that cannot be anything else is a column that cannot speak.
    @Test("A movement carrying no load drops the load column for the whole card")
    func unloaded() throws {
        let layout = SetRow.layout(try report([
            try set(1, kg: 0, reps: 15),
            try set(2, kg: 0, reps: 12)
        ]))
        #expect(layout == .unloaded)
        #expect(layout.heads == ["REPS", "RPE"])
    }

    /// A bout is stored as a warm-up, so it carries no working ordinal to index
    /// the previous session by — nothing on the card can move, and the reserved
    /// delta line is not drawn.
    @Test("A bout gets minutes, kilometres and a pace, and reserves no delta line")
    func cardio() throws {
        let layout = SetRow.layout(try report([try set(1, kg: 0, reps: 0, cardio: true)]))
        #expect(layout == .cardio)
        #expect(layout.heads == ["MIN", "KM", "PACE"])
        #expect(!layout.comparable)
    }

    /// Two sides in one row, and a hold with no second number. Splitting either
    /// would mean choosing which half of a set to print in a track with room
    /// for one — so both keep the string the page drew before columns existed,
    /// and the card draws no heading over them.
    @Test("A pair and a timed hold keep the whole string and get no heading")
    func whole() throws {
        let pair = SetRow.layout(try report([
            try set(1, kg: 20, reps: 10, side: "left"),
            try set(1, kg: 20, reps: 10, side: "right")
        ]))
        #expect(pair == .whole)
        #expect(pair.heads.isEmpty)

        let hold = SetRow.layout(try report([try set(1, kg: 0, reps: 45)], timed: true))
        #expect(hold == .whole)
    }

    /// A card that cannot make up its mind is drawn the way this page drew
    /// every card before columns existed, rather than drawn wrongly.
    @Test("A card mixing a bout with a lift falls back to the whole string")
    func mixed() throws {
        let layout = SetRow.layout(try report([
            try set(1, kg: 0, reps: 0, cardio: true),
            try set(2, kg: 42.5, reps: 10)
        ]))
        #expect(layout == .whole)
    }
}
