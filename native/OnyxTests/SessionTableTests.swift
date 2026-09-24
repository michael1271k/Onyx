import Foundation
import SwiftUI
import Testing
import OnyxCore
import OnyxData
import OnyxUI
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
///
/// ── THE "HOST FAULT" WAS AN ISOLATION TRAP (found in App Store W7) ─────────
/// W4 measured these tests taking the app host down with a signal trap and
/// put it down to the host. The crash report says otherwise:
/// `dispatch_assert_queue` ← `swift_task_isCurrentExecutor` ← `SetRow.layout`.
/// `SetRow` is a `View`, so `layout(_:)` is main-actor; the suite was not, and
/// Swift Testing ran it on the cooperative pool. The suite is `@MainActor` now.
///
/// So the assertions below are written to be READ as much as run, and the half
/// of W4 that does not need an app host — `MuscleMap.cardioMovers` and the
/// separation between it and `dict` — has its own suite in `OnyxCoreTests`
/// (`CardioMoversTests`), which `npm run swift:core` executes on every wave.
/// When the host is fixed, this file is the specification that was waiting.
/// `.serialized` since W4: the suite now renders a row and reads
/// `OnyxTheme.current`, and Swift Testing runs a suite's tests
/// concurrently by default — so a trap in one of them reported against
/// whichever test happened to have logged its start line first.
@MainActor
@Suite("Session ledger — which table a card draws", .serialized)
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
    ///
    /// ── A `side` NEEDS A `pairId`, AND USED NOT TO HAVE ONE ────────────────
    /// `SessionDetail.toRows` folds on `pairId` and nothing else, and
    /// `SessionVolume` refuses to collapse a side that carries no pair id. A
    /// fixture with `side` alone therefore produced two SINGLE rows that every
    /// rule downstream treated as two separate sets — so the pair case below
    /// was asserting `.whole` about a card that held no pair. The tag is `"L"`
    /// / `"R"` for the same reason: `toRows` tests `side == "R"` exactly, and
    /// `"right"` folded silently onto the left.
    private func set(_ number: Int, kg: Double, reps: Double, rpe: Double? = nil,
                     cardio: Bool = false, side: String? = nil,
                     pair: String? = nil) throws -> DetailSet {
        let axes = cardio ? #", "durationSec": 300, "distanceKm": 0.37"# : ""
        let lr = side.map { #", "side": "\#($0)""# } ?? ""
        let pairId = pair.map { #", "pairId": "\#($0)""# } ?? ""
        let effort = rpe.map { #", "rpe": \#($0)"# } ?? ""
        return try decode("""
        {"setNumber": \(number), "weightKg": \(kg), "reps": \(reps),
         "isPr": false, "setType": "working"\(effort)\(axes)\(lr)\(pairId)}
        """)
    }

    private func report(_ sets: [DetailSet], timed: Bool = false,
                       canonical: String = "X",
                       previous: [HistorySet] = []) throws -> SessionAnalysis.ExerciseReport {
        let detail: DetailExercise = try decode("""
        {"exerciseId": "x", "name": "X", "order": 0, "muscleGroups": [],
         "isCompound": true, "sets": [], "workingSets": 0, "topKg": 0, "volumeKg": 0}
        """)
        return SessionAnalysis.ExerciseReport(
            detail: detail, canonical: canonical, timed: timed,
            rows: SessionDetail.toRows(sets),
            prevDate: nil, previousSets: previous, cue: nil,
            stats: SessionDetail.exerciseStats(detail),
            window: nil, atCeiling: 0, trail: [], records: [:], rest: [:]
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

    /// A hold has one reading and no second number, so there is nothing to put
    /// in a second track. It keeps the string the page drew before columns
    /// existed, and the card draws no heading over it.
    @Test("A timed hold keeps the whole string and gets no heading")
    func whole() throws {
        let hold = SetRow.layout(try report([try set(1, kg: 0, reps: 45)], timed: true))
        #expect(hold == .whole)
        #expect(hold.heads.isEmpty)
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

    // MARK: - W4 · the ledger stops shouting

    /// ── THE DELTA IS THE NUMERAL'S INK, NOT A LINE UNDER IT (overhaul Q14) ──
    /// W4 reserved an empty line under every reading so a card could not
    /// change height between two sessions. The overhaul deletes the line: the
    /// comparison is carried by the reading's own colour, so a row with a
    /// previous set and one without are the same height by construction — and
    /// that height is the compact 30 pt floor, not the old 36.
    @MainActor
    @Test("A row with a previous set is as tall as one without, at the 30 pt floor")
    func noReservedLine() throws {
        let rows = SessionDetail.toRows([try set(1, kg: 42.5, reps: 10)])
        let compared = SetRow(row: rows[0], timed: false,
                              prev: HistorySet(weightKg: 40, reps: 9), layout: .loaded)
        let alone = SetRow(row: rows[0], timed: false, layout: .loaded)
        let withPrevious = try #require(height(of: compared))
        let without = try #require(height(of: alone))
        #expect(withPrevious == without)
        #expect(withPrevious >= SetRow.rowFloor)
        #expect(withPrevious < 36, "the reserved delta line is gone")
    }

    /// ── BETTER IS THE ACCENT, WORSE IS QUIET, NOTHING IS RED OR GREEN ───────
    /// `upIsGood` survives the redesign: a rise in RPE is still the harder
    /// session, so it takes the quiet ink, while a rise in load takes the
    /// theme's accent. No change and no comparison leave the numeral alone.
    @MainActor
    @Test("A rise in RPE is quiet ink, a rise in load is the accent")
    func effortInverts() throws {
        let rows = SessionDetail.toRows([try set(1, kg: 42.5, reps: 10, rpe: 9.5)])
        let row = SetRow(row: rows[0], timed: false,
                         prev: HistorySet(weightKg: 42.5, reps: 10, rpe: 8), layout: .loaded)
        let effort = row.effortFigure
        #expect(effort.upIsGood == false)
        #expect(effort.delta == 1.5)
        #expect(SetRow.Figure(text: "42.5").upIsGood)
        #expect(SetRow.deltaInk(1.5, upIsGood: false) == Color.onyx.textSecondary)
        #expect(SetRow.deltaInk(-0.5, upIsGood: false) == OnyxInk.Themed.accent)
        #expect(SetRow.deltaInk(2.5, upIsGood: true) == OnyxInk.Themed.accent)
        #expect(SetRow.deltaInk(-2.5, upIsGood: true) == Color.onyx.textSecondary)
        #expect(SetRow.deltaInk(0, upIsGood: true) == nil)
        #expect(SetRow.deltaInk(nil, upIsGood: true) == nil)
        for ink in [SetRow.deltaInk(3, upIsGood: true), SetRow.deltaInk(-3, upIsGood: true)] {
            #expect(ink != Color.onyx.good && ink != Color.onyx.danger)
        }
    }

    /// ── A UNILATERAL CARD FINALLY COMPARES (A3) ─────────────────────────────
    /// It was routed to `.whole`, whose `comparable` is false, so the movement
    /// where the two sides most obviously drift apart was the one carrying no
    /// arrow at all.
    @MainActor
    @Test("A pair card is .pair, compares, and carries the pair's own delta")
    func pair() throws {
        let sets = [
            try set(1, kg: 22, reps: 10, side: "L", pair: "p1"),
            try set(1, kg: 22, reps: 9, side: "R", pair: "p1")
        ]
        let previous = [
            HistorySet(weightKg: 20, reps: 10, setType: "working", side: "L", pairId: "q1"),
            HistorySet(weightKg: 20, reps: 9, setType: "working", side: "R", pairId: "q1")
        ]
        let ex = try report(sets, previous: previous)
        let layout = SetRow.layout(ex)
        #expect(layout == .pair)
        #expect(layout.comparable)
        // No heading: the row is a string, not a table.
        #expect(layout.heads.isEmpty)

        // One row for two sides — which is what makes ONE delta the right
        // number of deltas.
        #expect(ex.rows.count == 1)
        #expect(ex.rows[0].kind == "pair")

        // Both sides are folded to the weaker one on both sides of the
        // comparison — `SessionVolume`'s rule, not a second pair arithmetic.
        // 20 × 9 = 180 last time; 22 × 9 = 198 this time.
        let before = try #require(SessionDetailView.previousUnitVolume(ex, row: ex.rows[0]))
        #expect(before == 180)
        #expect(SessionVolume.sessionVolumeKg(sets.map {
            VolumeSet(weightKg: $0.weightKg, reps: $0.reps,
                      side: $0.side, pairId: $0.pairId, setType: $0.setType)
        }) - before == 18)
    }

    /// A warm-up on a pair card still draws its own string and still reserves
    /// its own line — which is what lets one card hold both shapes.
    @Test("One pair row is enough to make the whole card a pair card")
    func pairWithSingle() throws {
        let layout = SetRow.layout(try report([
            try set(1, kg: 22, reps: 12),
            try set(2, kg: 22, reps: 10, side: "L", pair: "p1"),
            try set(2, kg: 22, reps: 9, side: "R", pair: "p1")
        ]))
        #expect(layout == .pair)
    }

    /// ── THE TREADMILL CARD WAS SIX ABSENCES, NOT A BROKEN VIEW (F6) ─────────
    /// Every one of `headerTags`' five strength capsules is guarded off on a
    /// bout, so the row came out empty; `MuscleMap` holds no cardio entry, so
    /// the chips came out empty; and the hue fell through to `.recover`, the
    /// lavender Abs/core wears.
    @MainActor
    @Test("A treadmill card has readings, chips and the cardio hue")
    func treadmill() throws {
        let ex = try report([try set(1, kg: 0, reps: 0, cardio: true)], canonical: "Treadmill")

        // The hue, and specifically NOT the six-group fallback.
        #expect(SessionDetailView.family(ex) == Color.onyx.cardio)
        #expect(SessionDetailView.family(ex) != OnyxDomain.recover.accent)

        // The chips, from the display table and not from `dict` — which must
        // still know nothing about a treadmill, or the weekly accumulator would
        // start paying muscle credit for walking.
        #expect(MuscleMap.movers("Treadmill") == nil)
        #expect(!MuscleMap.cardioPrimaryLandmarks("Treadmill").isEmpty)
        #expect(MuscleMap.cardioMovers("Incline DB Press") == nil)

        // The readings. Distance and pace come from the card's own rows, so
        // they are there with no bout filed at all.
        let alone = SessionDetailView.cardioTags(ex, bout: nil)
        #expect(alone.count >= 1)
        #expect(alone.contains { $0.text.hasSuffix("km") })

        // Heart rate and provenance need the bout, and are absent without it.
        #expect(!alone.contains { $0.text == "Automatically logged" })
        let imported = SessionDetailView.cardioTags(ex, bout: CardioLogRow(
            id: "c", userId: "u", date: "2026-09-06", kind: "walk",
            fromHealthkit: true, avgHr: 118
        ))
        #expect(imported.contains { $0.text == "118 bpm" })
        #expect(imported.contains { $0.text == "Automatically logged" })

        // And a lift never reaches that branch.
        #expect(SessionDetailView.cardioTags(
            try report([try set(1, kg: 42.5, reps: 10)]), bout: nil
        ).isEmpty)
    }

    /// The rendered height of one row at a phone's width. Nil when the renderer
    /// could not produce an image, which `#require` turns into a failure rather
    /// than a silently-passing comparison of two nils.
    @MainActor
    /// ── A PAIR REACHES THE CEILING ONCE, NOT TWICE (overhaul C1 review) ─────
    /// The ledger header printed `4/2 @ 12–20` on a unilateral card: the
    /// count walked SIDES while the total counts SETS — the 3.10.0 rows-vs-sets
    /// unit bug in a new place. A pair counts when BOTH of its sides reached
    /// the ceiling; a side that fell short means the set did not.
    @Test("a pair counts once toward the ceiling, and only when both sides reached it")
    func ceilingCountsPairsOnce() {
        let sets: [(reps: Double, pairId: String?)] = [
            (21, "p1"), (20, "p1"),   // both sides at 20 → one set at the ceiling
            (22, "p2"), (19, "p2"),   // one side short → not at the ceiling
            (20, nil),                // an ordinary set at the ceiling
            (18, nil),
        ]
        #expect(SessionAnalysis.atCeiling(sets, ceiling: 20) == 2)
        #expect(SessionAnalysis.atCeiling(sets, ceiling: nil) == 0)
        #expect(SessionAnalysis.atCeiling([(20, ""), (20, "")], ceiling: 20) == 2, "an empty pair id is no pair")
    }

    private func height(of row: SetRow) -> CGFloat? {
        let renderer = ImageRenderer(content: row.frame(width: 393))
        renderer.scale = 1
        return renderer.uiImage?.size.height
    }

}
