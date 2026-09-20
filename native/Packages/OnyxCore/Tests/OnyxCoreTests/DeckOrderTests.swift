import Foundation
import Testing
@testable import OnyxCore

/// `DeckOrder` — the deck-move arithmetic both clients now share (W3).
///
/// The golden vector is the spec; the cases below it are the properties a
/// vector cannot state, and the one claim that matters to the two clients:
/// the phone's old inline `moveExercise` arithmetic and this type agree on
/// every deck size either of them can hold.
@Suite("Deck order — one mover, two clients")
struct DeckOrderTests {

    private struct MoveIn: Decodable {
        let count: Int
        let from: Int
        let to: Int
    }

    private struct MoveOut: Decodable {
        let to: Int
        /// `[lo, hi]`, or absent for a no-op.
        let restamp: [Int]?
        let order: [Int]
    }

    @Test("the golden vector replays")
    func golden() throws {
        for c in try GoldenFixture<MoveIn, MoveOut>.load("deck-order-move").cases {
            let move = DeckOrder.move(count: c.input.count, from: c.input.from, to: c.input.to)
            #expect(move.to == c.expected.to, "\(c.name): destination")
            if let range = c.expected.restamp {
                #expect(move.restamp == range[0]...range[1], "\(c.name): restamp")
            } else {
                #expect(move.restamp == nil, "\(c.name): expected a no-op")
            }
            #expect(move.applied(to: Array(0..<c.input.count)) == c.expected.order, "\(c.name): order")
        }
    }

    /// The property the vector's cases are samples of, over every deck size
    /// either client can draw and every pair of positions in it.
    @Test("a move is a permutation, and only the positions it names move")
    func permutes() {
        for count in 0...12 {
            let deck = Array(0..<count)
            for from in -1...count {
                for to in -1...count {
                    let move = DeckOrder.move(count: count, from: from, to: to)
                    let out = move.applied(to: deck)
                    #expect(out.sorted() == deck, "\(count)/\(from)→\(to): not a permutation")
                    guard let restamp = move.restamp else {
                        #expect(out == deck, "\(count)/\(from)→\(to): a no-op moved something")
                        continue
                    }
                    // Everything OUTSIDE the restamp range is where it was.
                    for position in deck.indices where !restamp.contains(position) {
                        #expect(out[position] == deck[position], "\(count)/\(from)→\(to): position \(position) moved")
                    }
                    // And everything inside it genuinely changed — an amend
                    // that restates a row is permanent noise in a log that is
                    // never compacted, so the range may not be over-wide.
                    for position in restamp {
                        #expect(out[position] != deck[position], "\(count)/\(from)→\(to): position \(position) restamped for nothing")
                    }
                }
            }
        }
    }

    /// The phone's `LoggerModel.moveExercise` did this inline before W3. The
    /// extraction is only safe if it is the same function.
    @Test("it reproduces the arithmetic it was extracted from")
    func matchesTheOldInlineVersion() {
        func old(count: Int, from: Int, to: Int) -> (order: [Int], touched: [Int])? {
            var items = Array(0..<count)
            guard items.indices.contains(from) else { return nil }
            let target = min(max(to, 0), items.count - 1)
            guard from != target else { return nil }
            items.insert(items.remove(at: from), at: target)
            return (items, Array(min(from, target)...max(from, target)))
        }
        for count in 1...10 {
            for from in 0..<count {
                for to in -2...(count + 2) {
                    let move = DeckOrder.move(count: count, from: from, to: to)
                    guard let expected = old(count: count, from: from, to: to) else {
                        #expect(move.isNoOp, "\(count)/\(from)→\(to): old was a no-op, new was not")
                        continue
                    }
                    #expect(move.applied(to: Array(0..<count)) == expected.order)
                    #expect(move.restamp.map(Array.init) == expected.touched)
                }
            }
        }
    }

    // MARK: - Skipping

    @Test("skipped movements sink to the bottom, each half in the order it had")
    func sinks() {
        let deck = ["a", "b", "c", "d", "e"]
        #expect(DeckOrder.sunk(deck) { ["b", "d"].contains($0) } == ["a", "c", "e", "b", "d"])
        #expect(DeckOrder.sunk(deck) { _ in false } == deck)
        // Everything skipped keeps the deck's own order rather than reversing
        // it — a wrist that skipped the lot still sees the workout it planned.
        #expect(DeckOrder.sunk(deck) { _ in true } == deck)
        #expect(DeckOrder.sunk([String]()) { _ in true } == [])
    }

    /// Sinking after a move, which is the order the deck view composes them in.
    @Test("a move and a sink compose without losing a movement")
    func composes() {
        let deck = Array(0..<6)
        let moved = DeckOrder.move(count: 6, from: 4, to: 1).applied(to: deck)
        #expect(moved == [0, 4, 1, 2, 3, 5])
        let sunk = DeckOrder.sunk(moved) { $0 == 1 || $0 == 5 }
        #expect(sunk == [0, 4, 2, 3, 1, 5])
        #expect(sunk.sorted() == deck)
    }
}
