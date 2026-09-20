import Foundation

/// How ONE session has rearranged today's deck, as arithmetic.
///
/// ── WHY IT LEFT THE WATCH MODEL (W3, AFTER REVIEW) ──────────────────────────
/// The wrist gained five ways to move the deck about — do-this-next, skip,
/// jump, one more set, swap — and they lived as five private properties on
/// `WatchModel`, which is `@MainActor`, watchOS-only and in the app target:
/// unreachable by any test this repository can run. Review found five defects
/// in them in one pass, and every one was arithmetic:
///
///   · a reorder rebuilt its index list against the UN-swapped plan array, so
///     a swapped movement and every set logged against it fell out of the deck
///     and the survivors were then re-stamped over their `exercise_order`;
///   · swapping the same slot twice was a silent no-op, because the second
///     swap was keyed on the replacement's name;
///   · an arrangement survived a routine edit that changed the same day's
///     contents, so the stored indices named different movements;
///   · "one more set" from a finished row added the set to a different
///     movement;
///   · two of the five moved the cursor without re-seeding it.
///
/// The fix for the first four is one idea: **every key is the SLOT, never the
/// name currently in it.** A slot is the position in the day's own exercise
/// list, and it is what a skip, a pin, an added set and a swap all refer to.
/// Names move; slots do not.
///
/// So the state and its five mutations are here, pure, `Equatable` and
/// testable on the command line, and `WatchModel` holds one value of it.
public struct DeckArrangement: Equatable, Sendable {

    /// One place in the deck, resolved.
    public struct Slot: Equatable, Sendable, Identifiable {
        /// The id of the movement the DAY prescribes here — the key everything
        /// in this type is stored under, and stable across a swap.
        public let originId: String
        /// What is actually being done in this slot, which is the day's
        /// movement unless it has been swapped.
        public let plan: ProgramExercise
        /// Position in the arranged, skip-sunk deck. Dense from 0. This is
        /// what a logged set carries as `exercise_order`.
        public let order: Int
        public let isSkipped: Bool
        /// Sets added on the wrist today, on top of the plan's own count.
        public let extraSets: Int

        /// ── IDENTITY IS THE SLOT, NOT THE MOVEMENT ──────────────────────────
        /// A `ForEach` keyed on the displayed movement re-identifies the row
        /// the instant it is swapped, which tears down the gesture that did
        /// the swapping. The slot survives it.
        public var id: String { originId }

        public init(
            originId: String, plan: ProgramExercise, order: Int,
            isSkipped: Bool = false, extraSets: Int = 0
        ) {
            self.originId = originId
            self.plan = plan
            self.order = order
            self.isSkipped = isSkipped
            self.extraSets = extraSets
        }
    }

    /// Slot indices in the order this session is doing them. Nil is the day's
    /// own order, which is also what an arrangement resets to.
    public private(set) var order: [Int]?
    public private(set) var skipped: Set<String> = []
    public private(set) var extraSets: [String: Int] = [:]
    public private(set) var swaps: [String: ProgramExercise] = [:]
    /// The slot the athlete jumped to. Advisory — `Slot` does not carry it,
    /// because whether a pin still applies depends on what has been logged,
    /// which this type deliberately does not know.
    public private(set) var pinned: String?

    /// What the arrangement was computed against.
    ///
    /// ── THE SIGNATURE IS THE WHOLE DAY, NOT ITS KEY ─────────────────────────
    /// `order` holds INDICES, so it is meaningless the moment the list behind
    /// them changes — and a routine edited on the phone changes the list
    /// without changing the day key. Comparing the key alone left a wrist
    /// showing a three-movement deck for a day that now has four, with the new
    /// movement unreachable. The signature is the ids, in order.
    public private(set) var signature: [String] = []

    public init() {}

    // MARK: - Resolving

    /// Forget everything if the deck behind the arrangement has changed.
    ///
    /// ── THE SIGNATURE IS CHECKED BEFORE EVERY READ AND EVERY WRITE ──────────
    /// `order` holds INDICES, so it is meaningless the moment the list behind
    /// them changes — and a routine edited on the phone changes the list
    /// without changing the day key. `slots(of:)` applies the same rule
    /// without storing it, so a READ is pure; this is the call that makes the
    /// reset stick, and the owner makes it wherever the deck can have moved.
    @discardableResult
    public mutating func reconcile(with plans: [ProgramExercise]) -> Bool {
        let ids = plans.map(\.id)
        guard ids != signature else { return false }
        self = DeckArrangement()
        signature = ids
        return true
    }

    /// The deck, arranged: the day's movements with swaps applied, in this
    /// session's order, with the skipped ones sunk to the bottom.
    ///
    /// PURE. A `plans` that the arrangement was not built against is answered
    /// as if nothing had been rearranged — the same answer `reconcile` then
    /// makes permanent, so a reader and a writer can never disagree.
    public func slots(of plans: [ProgramExercise]) -> [Slot] {
        guard plans.map(\.id) == signature else {
            return plans.enumerated().map { Slot(originId: $1.id, plan: $1, order: $0) }
        }
        let arranged = (order ?? Array(plans.indices)).filter(plans.indices.contains)
        return DeckOrder.sunk(arranged) { skipped.contains(plans[$0].id) }
            .enumerated().map { position, index in
                let origin = plans[index].id
                return Slot(
                    originId: origin,
                    plan: swaps[origin] ?? plans[index],
                    order: position,
                    isSkipped: skipped.contains(origin),
                    extraSets: extraSets[origin] ?? 0
                )
            }
    }

    // MARK: - Moving

    /// Move a slot to just after `afterOriginId`, or to the front when that is
    /// nil — "do this one next".
    ///
    /// ── IT PERMUTES THE INDEX LIST, IT DOES NOT LOOK NAMES BACK UP ──────────
    /// The first version mapped the displayed deck back through the day's
    /// exercises by name to rebuild the index list. That is what dropped a
    /// swapped movement: its displayed name is, by construction, not in the
    /// day. Permuting the indices themselves cannot lose one.
    public mutating func moveNext(_ originId: String, after afterOriginId: String?, in plans: [ProgramExercise]) {
        reconcile(with: plans)
        let deck = slots(of: plans)
        guard let from = deck.firstIndex(where: { $0.originId == originId }) else { return }
        let target = afterOriginId
            .flatMap { id in deck.firstIndex { $0.originId == id } }
            .map { $0 + 1 } ?? 0
        let move = DeckOrder.move(count: deck.count, from: from, to: target)
        guard !move.isNoOp else { return }
        // The displayed deck in slot-index terms, then permuted by the same
        // arithmetic the phone's drag uses.
        let indices = deck.map { slot in plans.firstIndex { $0.id == slot.originId } ?? 0 }
        order = move.applied(to: indices)
        // Moving a movement to the front is a plain statement that it is not
        // skipped.
        skipped.remove(originId)
    }

    /// Put a slot aside for this session, or take it back.
    public mutating func toggleSkip(_ originId: String) {
        if skipped.contains(originId) {
            skipped.remove(originId)
        } else {
            skipped.insert(originId)
            if pinned == originId { pinned = nil }
        }
    }

    /// One more set of this movement, today only. The ROUTINE is untouched.
    public mutating func addSet(to originId: String) {
        extraSets[originId, default: 0] += 1
        pinned = originId
    }

    /// Put another movement in this slot for today.
    ///
    /// Keyed on the SLOT, so swapping twice replaces the first choice instead
    /// of writing an entry nothing reads. Swapping back to the day's own
    /// movement clears the entry rather than storing an identity.
    public mutating func swap(_ originId: String, for candidate: ProgramExercise, in plans: [ProgramExercise]) {
        reconcile(with: plans)
        guard let slot = plans.first(where: { $0.id == originId }) else { return }
        if candidate.id == originId {
            swaps[originId] = nil
        } else {
            // The set COUNT and the rest come from the slot being replaced,
            // not from the candidate's own row in whatever day it was
            // borrowed from: you are doing this movement instead of that one,
            // in this slot, for this session. Its load seed and rep window
            // come with it, because those are facts about the lift.
            swaps[originId] = ProgramExercise(
                candidate.name,
                exerciseId: candidate.exerciseId,
                sets: slot.sets,
                cutSets: slot.cutSets,
                wk1Kg: candidate.wk1Kg,
                reps: candidate.reps,
                restSec: slot.restSec ?? candidate.restSec,
                movers: candidate.movers,
                compound: candidate.isCompound,
                note: candidate.note
            )
        }
        // Anything remembered about the old movement is about a movement that
        // is no longer in this slot.
        if pinned == originId { pinned = nil }
        skipped.remove(originId)
        extraSets[originId] = nil
    }

    public mutating func pin(_ originId: String?) { pinned = originId }
}
