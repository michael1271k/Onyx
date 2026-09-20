import Foundation

/// Moving a movement in the deck — the arithmetic, with no deck attached.
///
/// ── WHY IT LEFT `LoggerModel` (W3) ──────────────────────────────────────────
/// `moveExercise(from:to:)` did three separable things in eight lines: it
/// clamped the destination, it permuted the array, and it decided WHICH cards'
/// logged rows have to be re-amended with a new `exercise_order`. Only the
/// third is subtle, and it is the one a second client has to reproduce exactly:
/// the watch's "Do next" writes the same `exercise_order` onto the same rows,
/// and if the two disagree about which rows moved, one device's session report
/// groups the movements in an order the other never performed.
///
/// So the decision is here, pure and total, with a golden vector
/// (`deck-order-move.json`) under it. The two clients keep their own array —
/// the phone's is `[ExerciseState]`, the watch's is a plan — and share the
/// answer.
///
/// ── THE RESTAMP RANGE IS THE WHOLE POINT ────────────────────────────────────
/// Only the movements BETWEEN the two positions shift, so only their rows are
/// re-amended. Every other card's stored order is still correct, and an amend
/// that restates a row is permanent noise in a log that is never compacted —
/// in edit mode it is worse than noise, because each one is a seed, a PR
/// replay, a recount and an outbox upsert.
///
/// ── AND `to` IS A DESTINATION INDEX, NOT AN INSERTION OFFSET ────────────────
/// `List.onMove` hands an insertion offset, which is one greater than the
/// destination index when you drag downwards. Neither client uses `onMove` —
/// the phone's deck is a `LazyVStack` and the watch's is swipe actions — so
/// this type speaks destination indices only, and says so where somebody
/// porting an `onMove` call site will read it.
public enum DeckOrder {

    /// What a move comes to.
    public struct Move: Equatable, Sendable {
        /// Where the movement came from. Out of range on a deck this size
        /// means the move is a no-op, and `restamp` says so.
        public let from: Int
        /// Where it lands, clamped into the deck. Equal to `from` on a no-op.
        public let to: Int
        /// The NEW positions whose `exercise_order` changed, or nil when
        /// nothing moved. Positions in the array AFTER `applied(to:)`, which
        /// is the order both clients then walk.
        public let restamp: ClosedRange<Int>?

        public var isNoOp: Bool { restamp == nil }

        public init(from: Int, to: Int, restamp: ClosedRange<Int>?) {
            self.from = from
            self.to = to
            self.restamp = restamp
        }

        /// Permute a deck by this move. The identity on a no-op, and on any
        /// array whose count is not the one the move was computed for — a
        /// caller that resized its deck between the two calls gets its deck
        /// back rather than a crash or a silent reshuffle.
        public func applied<T>(to items: [T]) -> [T] {
            guard !isNoOp, items.indices.contains(from), items.indices.contains(to) else { return items }
            var next = items
            next.insert(next.remove(at: from), at: to)
            return next
        }
    }

    /// Move the movement at `from` to `to`.
    ///
    /// A destination outside the deck is CLAMPED rather than refused: "do this
    /// one next" on the last card of a finished deck asks for a position past
    /// the end, and the honest answer is the end. A `from` outside the deck is
    /// a no-op — there is no movement there to move.
    public static func move(count: Int, from: Int, to: Int) -> Move {
        guard count > 0, (0..<count).contains(from) else {
            return Move(from: from, to: from, restamp: nil)
        }
        let target = Swift.min(Swift.max(to, 0), count - 1)
        guard target != from else { return Move(from: from, to: from, restamp: nil) }
        return Move(from: from, to: target, restamp: Swift.min(from, target)...Swift.max(from, target))
    }

    /// The deck's display order with the skipped movements sunk to the bottom.
    ///
    /// ── SKIPPING IS A VIEW ORDER, NOT A LOG FACT (W3) ───────────────────────
    /// A skipped movement has no event: `SetEvent.Kind` is a one-way door (a
    /// build that predates a kind cannot decode a session that carries one, and
    /// the failure is "no further set can be logged into that session at all"),
    /// and "I did not do this one" is the ABSENCE of sets, which the log already
    /// records perfectly by containing none. So skipping moves a row out of the
    /// way and nothing else — it is undone by tapping it, it does not travel to
    /// the phone, and a session closed with a movement skipped is a session with
    /// that movement unlogged, which is exactly what happened.
    ///
    /// Stable within each half, so the deck you are left with is the deck you
    /// had with two holes closed up.
    public static func sunk<T>(_ items: [T], skipped: (T) -> Bool) -> [T] {
        items.filter { !skipped($0) } + items.filter(skipped)
    }
}
