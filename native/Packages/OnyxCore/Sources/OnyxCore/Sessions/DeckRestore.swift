import Foundation

/// Folding a logged session back onto a deck.
///
/// ── WHY THIS LEFT `LoggerModel` ─────────────────────────────────────────────
/// `restoreLoggedSets` did three things at once — match rows to cards, decide
/// how many blanks the prescription still wants, and build the rows — and the
/// only test available for any of them was to open the app. It shipped two
/// defects of the same shape, four months apart:
///
///   1. **A unit mismatch.** The blank count was computed in ROWS
///      (`exercise.rows.count - restored.count`) and spent in SETS
///      (`seedRows(count:)`, which pre-splits a unilateral movement). On a
///      movement trained one side at a time that squares the shortfall: P sets
///      prescribed and L logged came back as `2P − L` sets, so a four-set
///      Single Arm Lateral Raise with two sets logged reopened with SIX, and
///      sets 5 and 6 were rows the program never asked for and the athlete
///      could tick.
///   2. **A fan-out.** Matching filtered the whole log per card and consumed
///      nothing, so two cards answering to one name each received the SAME
///      rows — the treadmill drawn twice, ticked twice, counted twice, with
///      both copies writing under one set id.
///
/// Both are arithmetic over two lists. Neither needed a database, a view or a
/// simulator to find, and neither could be written down as a test while it
/// lived inside a method that also built `SetRow`s. So the arithmetic is here,
/// the row-building stays in the model, and the contract between them is:
///
/// > Restore PARTITIONS the log. Every logged row lands in exactly one card or
/// > in `unmatched`, never in two. Blanks are counted in the unit the
/// > prescription is written in — SETS — and a pair is one set.
///
/// `fold` is pure, total and idempotent: `fold(c, l)` twice is `fold(c, l)`.
public enum DeckRestore {

    /// One card of the deck, as the fold needs to see it.
    public struct Card: Sendable, Equatable {
        /// The movement's canonical name, already lowercased by the caller.
        ///
        /// Lowercased on BOTH sides or not at all: `SessionDetailView.editorDay`
        /// compares case-insensitively when it decides whether the program
        /// already names a movement, and a case-sensitive match here would
        /// reuse the program's card and then fail to find its rows.
        public let key: String
        /// How many SETS this card is currently showing — the target the blanks
        /// make up to. Sets, never rows.
        public let shownSets: Int

        public init(key: String, shownSets: Int) {
            self.key = key
            self.shownSets = shownSets
        }
    }

    /// One row already in the log.
    public struct LoggedSet: Sendable, Equatable {
        public let id: String
        /// The movement this row resolves to, canonical and lowercased — the
        /// caller applies the catalogue/slug/alias ladder before handing it over.
        public let key: String
        public let pairId: String?
        /// The LOCAL spelling (`left`/`right`), already normalised by the
        /// caller. The wire's `L`/`R` reaching here would make one physical set
        /// two, which is the bug `SyncTranslation.localSide` exists to stop.
        public let side: String?

        public init(id: String, key: String, pairId: String? = nil, side: String? = nil) {
            self.id = id
            self.key = key
            self.pairId = pairId
            self.side = side
        }

        /// What `SetGrouping` folds this row onto. Both fields tested, for the
        /// reason that function's own documentation gives.
        public var pairKey: String? {
            guard let pairId, !pairId.isEmpty, side != nil, !(side?.isEmpty ?? true) else { return nil }
            return pairId
        }
    }

    /// What one card gets back. Index-aligned with the `cards` handed in.
    public struct Restored: Sendable, Equatable {
        public let key: String
        /// The log rows this card owns, in log order.
        public let loggedIds: [String]
        /// How many blank SETS to seed after them.
        public let blankSets: Int

        public init(key: String, loggedIds: [String], blankSets: Int) {
            self.key = key
            self.loggedIds = loggedIds
            self.blankSets = blankSets
        }
    }

    public struct Plan: Sendable, Equatable {
        /// One entry per input card, in input order.
        public let cards: [Restored]
        /// Rows the deck has no card for.
        ///
        /// ── WHY THEY ARE RETURNED AND NOT DROPPED ───────────────────────────
        /// The old code dropped them silently, and a row that is in the log, in
        /// `closeSession`'s counts and not on the screen is the projection and
        /// the log disagreeing — the one thing this layer exists to prevent.
        /// Returning them is what makes "the fold partitions the log" a
        /// property a test can state; the deck may still choose to draw none of
        /// them, but it can no longer lose them without saying so.
        public let unmatched: [LoggedSet]

        public init(cards: [Restored], unmatched: [LoggedSet]) {
            self.cards = cards
            self.unmatched = unmatched
        }
    }

    /// Fold the log onto the deck.
    ///
    /// ── FIRST CARD WINS, AND IT CONSUMES ────────────────────────────────────
    /// Two cards answering to one key is a deck defect (see
    /// `LoggerModel.withWarmupCardio`), and this is the layer that refuses to
    /// AMPLIFY it: the first card in deck order takes the rows, every later
    /// namesake gets an empty list and its blanks, and no row is ever served
    /// twice. That alone would have kept the duplicated treadmill a cosmetic
    /// bug instead of a double-counted session with two writers on one set id.
    public static func fold(cards: [Card], logged: [LoggedSet]) -> Plan {
        // Bucketed in ONE pass, in log order, so a card's rows come back in the
        // order they were performed rather than in the order the deck asks.
        var byKey: [String: [LoggedSet]] = [:]
        var order: [String] = []
        for set in logged {
            if byKey[set.key] == nil { order.append(set.key) }
            byKey[set.key, default: []].append(set)
        }

        var claimed = Set<String>()
        var restored: [Restored] = []
        restored.reserveCapacity(cards.count)
        for card in cards {
            // `claimed` is what makes this a partition: a second card with the
            // same key finds the bucket already taken and gets nothing.
            let mine = claimed.insert(card.key).inserted ? (byKey[card.key] ?? []) : []
            restored.append(Restored(
                key: card.key,
                loggedIds: mine.map(\.id),
                // ── THE UNIT FIX, AND IT IS THE WHOLE BUG ───────────────────
                // Both sides of this subtraction are SETS. `shownSets` is the
                // card counted in sets, `physical(mine)` folds a pair to one,
                // and the caller spends the answer on `seedRows(count:)`, whose
                // parameter has always been working SETS. The old line
                // subtracted rows and spent sets.
                blankSets: max(0, card.shownSets - SetGrouping.physical(mine, pairKey: \.pairKey))
            ))
        }

        let unmatched = order.filter { !claimed.contains($0) }.flatMap { byKey[$0] ?? [] }
        return Plan(cards: restored, unmatched: unmatched)
    }
}
