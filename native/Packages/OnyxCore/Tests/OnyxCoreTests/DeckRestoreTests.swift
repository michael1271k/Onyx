import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// DeckRestore — folding a logged session back onto a deck.
//
// The two shipped defects this function exists to make impossible:
//
//   1. **The phantom pairs.** The blank count was computed in ROWS and spent in
//      SETS, and a unilateral movement is two rows per set — so the shortfall
//      was squared. Four prescribed with two logged came back as SIX sets, and
//      sets 5 and 6 were tickable rows the program never asked for.
//   2. **The fan-out.** Matching filtered the whole log per card and consumed
//      nothing, so two cards answering to one name each received every row —
//      the treadmill drawn twice, ticked twice, counted twice.
//
// Both are properties, not examples, so most of what follows is a grid.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("DeckRestore — the fold")
struct DeckRestoreTests {

    // MARK: Builders

    /// `count` physical sets of one movement, split into L/R pairs when asked —
    /// the shape `LoggerModel.seedRows` produces for a unilateral lift.
    private func sets(_ key: String, _ count: Int, split: Bool, from: Int = 0) -> [DeckRestore.LoggedSet] {
        (0..<count).flatMap { i -> [DeckRestore.LoggedSet] in
            let n = from + i
            guard split else {
                return [DeckRestore.LoggedSet(id: "\(key)-\(n)", key: key)]
            }
            return ["left", "right"].map {
                DeckRestore.LoggedSet(id: "\(key)-\(n)-\($0)", key: key, pairId: "\(key)-pair-\(n)", side: $0)
            }
        }
    }

    private func card(_ key: String, _ shownSets: Int) -> DeckRestore.Card {
        DeckRestore.Card(key: key, shownSets: shownSets)
    }

    // MARK: The regression that named this wave

    @Test("four prescribed, two logged, split L/R — six sets was the bug")
    func lateralRaiseComesBackAtFour() {
        // Single Arm Lateral Raise: the deck pre-splits, so four prescribed
        // sets are EIGHT rows and two logged sets are FOUR rows. The old line
        // was `max(0, rows - rows) = 8 - 4 = 4`, spent as four SETS, pre-split
        // into eight more rows — twelve rows, six sets, sets 5 and 6 invented.
        let plan = DeckRestore.fold(
            cards: [card("single arm lateral raise", 4)],
            logged: sets("single arm lateral raise", 2, split: true)
        )
        let only = plan.cards[0]
        #expect(only.loggedIds.count == 4, "two split sets are four rows")
        #expect(only.blankSets == 2, "two sets still to do, counted in sets")

        // The number that reaches the screen.
        let restoredSets = DeckRestore.physicalSetsForTest(only.loggedIds.count, split: true)
        #expect(restoredSets + only.blankSets == 4, "the card shows four sets, not six")
    }

    @Test("the same fold on a bilateral movement is unchanged")
    func bilateralIsUntouched() {
        // The unit bug was invisible here — rows and sets are the same number —
        // so this is the "did the fix move anything it should not" test.
        let plan = DeckRestore.fold(cards: [card("leg press", 4)], logged: sets("leg press", 2, split: false))
        #expect(plan.cards[0].loggedIds.count == 2)
        #expect(plan.cards[0].blankSets == 2)
    }

    // MARK: The fan-out

    @Test("two cards with one name: the first takes the rows, the second gets none")
    func duplicateCardsDoNotBothClaim() {
        // The duplicated treadmill, as the deck actually built it: two cards,
        // one logged bout. Both used to be filled and both used to tick.
        let logged = sets("treadmill", 1, split: false)
        let plan = DeckRestore.fold(cards: [card("treadmill", 1), card("treadmill", 1)], logged: logged)

        #expect(plan.cards.count == 2, "one entry per card, in card order")
        #expect(plan.cards[0].loggedIds == ["treadmill-0"])
        #expect(plan.cards[1].loggedIds.isEmpty, "a second card answering to one name owns nothing")
        #expect(plan.unmatched.isEmpty)
    }

    @Test("a duplicate card cannot double any count")
    func duplicateCardsCannotDoubleCount() {
        let logged = sets("treadmill", 3, split: false)
        let one = DeckRestore.fold(cards: [card("treadmill", 3)], logged: logged)
        let two = DeckRestore.fold(cards: [card("treadmill", 3), card("treadmill", 3)], logged: logged)
        let owned = { (p: DeckRestore.Plan) in p.cards.flatMap(\.loggedIds).count }
        #expect(owned(one) == owned(two), "adding a namesake card adds no rows")
        #expect(owned(two) == 3)
    }

    // MARK: Partition — the invariant with teeth

    @Test("every logged row lands in exactly one place, over a wide grid")
    func foldPartitionsTheLog() {
        let keys = ["press", "curl", "row", "orphan"]
        for cardCount in 0...4 {
            for split in [false, true] {
                for logCount in 0...5 {
                    let deck = (0..<cardCount).map { card(keys[$0 % keys.count], logCount) }
                    let logged = keys.flatMap { sets($0, logCount, split: split) }
                    let plan = DeckRestore.fold(cards: deck, logged: logged)

                    let placed = plan.cards.flatMap(\.loggedIds) + plan.unmatched.map(\.id)
                    #expect(
                        placed.count == logged.count,
                        "cards \(cardCount) split \(split) log \(logCount): \(placed.count) placed of \(logged.count)"
                    )
                    #expect(
                        Set(placed) == Set(logged.map(\.id)),
                        "no row invented and none lost"
                    )
                    #expect(
                        Set(placed).count == placed.count,
                        "no row served twice"
                    )
                }
            }
        }
    }

    @Test("a card's total is max(what it showed, what was logged) — never more")
    func totalSetsNeverExceedTheLargerOfTheTwo() {
        // The property the phantom pairs violated. `shownSets` and the logged
        // count are both SETS; the total after the fold is the larger of them.
        // Six from a four-set prescription with two logged is exactly the shape
        // this refuses.
        for shown in 0...6 {
            for loggedSets in 0...6 {
                for split in [false, true] {
                    let plan = DeckRestore.fold(
                        cards: [card("lift", shown)],
                        logged: sets("lift", loggedSets, split: split)
                    )
                    let owned = plan.cards[0]
                    let restored = DeckRestore.physicalSetsForTest(owned.loggedIds.count, split: split)
                    #expect(restored == loggedSets, "restore counts a pair once")
                    #expect(
                        restored + owned.blankSets == max(shown, loggedSets),
                        "shown \(shown), logged \(loggedSets), split \(split): got \(restored + owned.blankSets)"
                    )
                    #expect(owned.blankSets >= 0)
                }
            }
        }
    }

    // MARK: Determinism

    @Test("the fold is pure — the same inputs answer the same way, twice")
    func foldIsDeterministic() {
        let deck = [card("press", 3), card("curl", 4), card("press", 2)]
        let logged = sets("press", 2, split: false) + sets("curl", 1, split: true) + sets("ghost lift", 1, split: false)
        #expect(DeckRestore.fold(cards: deck, logged: logged) == DeckRestore.fold(cards: deck, logged: logged))
    }

    @Test("re-folding the plan's own outcome changes nothing")
    func foldIsIdempotentUnderReapplication() {
        // What a second `attach` does: the deck now SHOWS what the first fold
        // produced, and the same log is folded onto it again. A fold that grew
        // the card here is the phantom-pair bug in its recurring form — it fired
        // on every re-open, which is why tapping Edit added sets 5 and 6 again.
        for shown in 0...5 {
            for loggedSets in 0...5 {
                for split in [false, true] {
                    let logged = sets("lift", loggedSets, split: split)
                    let first = DeckRestore.fold(cards: [card("lift", shown)], logged: logged).cards[0]
                    let shownAfter = DeckRestore.physicalSetsForTest(first.loggedIds.count, split: split) + first.blankSets
                    let second = DeckRestore.fold(cards: [card("lift", shownAfter)], logged: logged).cards[0]
                    #expect(second.blankSets == first.blankSets, "shown \(shown), logged \(loggedSets), split \(split)")
                    #expect(second.loggedIds == first.loggedIds)
                }
            }
        }
    }

    // MARK: Order, orphans and edges

    @Test("a card's rows come back in log order, not deck order")
    func logOrderIsPreserved() {
        // The performed order is what the deck numbers its badges from, and it
        // is what `seededPrevious` walks to find a row's working index.
        let logged = [
            DeckRestore.LoggedSet(id: "c", key: "press"),
            DeckRestore.LoggedSet(id: "a", key: "press"),
            DeckRestore.LoggedSet(id: "b", key: "press"),
        ]
        #expect(DeckRestore.fold(cards: [card("press", 3)], logged: logged).cards[0].loggedIds == ["c", "a", "b"])
    }

    @Test("rows the deck has no card for are reported, not dropped")
    func orphansSurvive() {
        let plan = DeckRestore.fold(
            cards: [card("press", 2)],
            logged: sets("press", 1, split: false) + sets("watch only lift", 2, split: false)
        )
        #expect(plan.cards[0].loggedIds.count == 1)
        #expect(plan.unmatched.map(\.key) == ["watch only lift", "watch only lift"])
    }

    @Test("a pairId with no side is not a pair, and counts as two sets")
    func halfWrittenPairIsNotAPair() {
        // `SessionVolume` says so explicitly, and the deck has to agree or a
        // half-written pair scores one arm's load as the whole set's.
        let logged = [
            DeckRestore.LoggedSet(id: "l", key: "lunge", pairId: "p1", side: "left"),
            DeckRestore.LoggedSet(id: "r", key: "lunge", pairId: "p1", side: nil),
        ]
        let plan = DeckRestore.fold(cards: [card("lunge", 4)], logged: logged)
        #expect(plan.cards[0].blankSets == 2, "one real pair and one loose row is two sets of four")
    }

    @Test("an empty side string is not a side either")
    func emptySideIsNotASide() {
        let logged = [
            DeckRestore.LoggedSet(id: "l", key: "lunge", pairId: "p1", side: ""),
            DeckRestore.LoggedSet(id: "r", key: "lunge", pairId: "p1", side: ""),
        ]
        #expect(DeckRestore.fold(cards: [card("lunge", 4)], logged: logged).cards[0].blankSets == 2)
    }

    @Test("an empty pairId is not a pair")
    func emptyPairIdIsNotAPair() {
        let logged = [
            DeckRestore.LoggedSet(id: "l", key: "lunge", pairId: "", side: "left"),
            DeckRestore.LoggedSet(id: "r", key: "lunge", pairId: "", side: "right"),
        ]
        #expect(DeckRestore.fold(cards: [card("lunge", 4)], logged: logged).cards[0].blankSets == 2)
    }

    @Test("an empty deck and an empty log are both answerable")
    func emptyInputs() {
        #expect(DeckRestore.fold(cards: [], logged: []).cards.isEmpty)
        #expect(DeckRestore.fold(cards: [], logged: sets("press", 2, split: false)).unmatched.count == 2)
        let blank = DeckRestore.fold(cards: [card("press", 3)], logged: [])
        #expect(blank.cards[0].loggedIds.isEmpty)
        #expect(blank.cards[0].blankSets == 3, "a card with nothing logged keeps its whole prescription")
    }

    @Test("logging past the prescription asks for no blanks, and never a negative")
    func overshootAsksForNothing() {
        let plan = DeckRestore.fold(cards: [card("press", 2)], logged: sets("press", 5, split: true))
        #expect(plan.cards[0].blankSets == 0)
        #expect(plan.cards[0].loggedIds.count == 10)
    }

    @Test("a three-card deck keeps its own order regardless of the log's")
    func cardOrderIsTheDecksOrder() {
        let plan = DeckRestore.fold(
            cards: [card("a", 1), card("b", 1), card("c", 1)],
            logged: sets("c", 1, split: false) + sets("a", 1, split: false)
        )
        #expect(plan.cards.map(\.key) == ["a", "b", "c"])
        #expect(plan.cards[1].loggedIds.isEmpty)
    }

    // MARK: The pair rule itself

    @Test("SetGrouping counts a pair once and an unpaired row once")
    func groupingIsTheOneRule() {
        let rows = sets("lunge", 3, split: true) + sets("lunge", 2, split: false, from: 10)
        #expect(SetGrouping.physical(rows, pairKey: \.pairKey) == 5)
        #expect(SetGrouping.groups(rows, pairKey: \.pairKey).map(\.count) == [2, 2, 2, 1, 1])
    }

    @Test("grouping keeps first-appearance order even when the sides interleave")
    func groupingKeepsOrderAcrossInterleavedPairs() {
        let rows = [
            DeckRestore.LoggedSet(id: "1L", key: "k", pairId: "p1", side: "left"),
            DeckRestore.LoggedSet(id: "2L", key: "k", pairId: "p2", side: "left"),
            DeckRestore.LoggedSet(id: "1R", key: "k", pairId: "p1", side: "right"),
            DeckRestore.LoggedSet(id: "2R", key: "k", pairId: "p2", side: "right"),
        ]
        #expect(SetGrouping.groups(rows, pairKey: \.pairKey).map { $0.map(\.id) } == [["1L", "1R"], ["2L", "2R"]])
    }
}

private extension DeckRestore {
    /// Rows back to sets, for a fixture whose split-ness the test already knows.
    /// Not production code's business — the model counts its own `SetRow`s.
    static func physicalSetsForTest(_ rows: Int, split: Bool) -> Int {
        split ? rows / 2 : rows
    }
}
