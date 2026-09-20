import Foundation
import Testing
@testable import OnyxCore

/// `DeckArrangement` — the wrist's five ways to move today's deck about.
///
/// Every case below is a defect review found in the same logic while it was
/// five private properties on a `@MainActor`, watchOS-only model that no test
/// in this repository could reach. That is the argument for the extraction,
/// and these are the regressions.
@Suite("Deck arrangement — the slot is the key, never the name")
struct DeckArrangementTests {

    private func plan(_ name: String, sets: Int = 3, kg: Double = 40) -> ProgramExercise {
        ProgramExercise(name, sets: sets, wk1Kg: kg, reps: "8-12", restSec: 150)
    }

    private var deck: [ProgramExercise] {
        [plan("Chest Press"), plan("Lat Pulldown"), plan("Cable Crossover")]
    }

    // MARK: - Resolving

    @Test("an untouched arrangement is the day's own order")
    func identity() {
        var arrangement = DeckArrangement()
        let slots = arrangement.slots(of: deck)
        #expect(slots.map(\.originId) == ["Chest Press", "Lat Pulldown", "Cable Crossover"])
        #expect(slots.map(\.order) == [0, 1, 2])
        #expect(slots.allSatisfy { !$0.isSkipped && $0.extraSets == 0 })
        #expect(arrangement.slots(of: []).isEmpty)
    }

    @Test("order is dense from zero, and skipped movements sink")
    func sinks() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        arrangement.toggleSkip("Chest Press")
        let slots = arrangement.slots(of: deck)
        #expect(slots.map(\.originId) == ["Lat Pulldown", "Cable Crossover", "Chest Press"])
        // Dense from 0 whatever has been skipped: `exercise_order` is a
        // grouping key and a hole in it is a movement two clients can place
        // differently.
        #expect(slots.map(\.order) == [0, 1, 2])
        #expect(slots.last?.isSkipped == true)
        arrangement.toggleSkip("Chest Press")
        #expect(arrangement.slots(of: deck).map(\.originId) == ["Chest Press", "Lat Pulldown", "Cable Crossover"])
    }

    // MARK: - The defect that lost a movement

    /// THE critical one. A reorder used to rebuild its index list by looking
    /// the displayed names back up in the day's exercises — and a swapped
    /// movement's name is, by construction, not in the day. It was dropped,
    /// and the survivors were then re-stamped over its `exercise_order`.
    @Test("a reorder after a swap keeps the swapped movement and every slot")
    func reorderAfterSwapKeepsEverything() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        arrangement.swap("Chest Press", for: plan("Incline DB Press", kg: 30), in: deck)
        #expect(arrangement.slots(of: deck).map(\.plan.name) == ["Incline DB Press", "Lat Pulldown", "Cable Crossover"])

        // `after:` is a SLOT id, so it is still "Chest Press" even though the
        // row now reads "Incline DB Press". That is the whole point of the
        // type, and passing the displayed name is the mistake it prevents —
        // it names no slot, so the move goes to the front rather than
        // silently to the wrong place.
        arrangement.moveNext("Cable Crossover", after: "Chest Press", in: deck)
        let slots = arrangement.slots(of: deck)
        #expect(slots.count == 3, "a slot was lost")
        #expect(slots.map(\.originId) == ["Chest Press", "Cable Crossover", "Lat Pulldown"])
        #expect(slots.map(\.plan.name) == ["Incline DB Press", "Cable Crossover", "Lat Pulldown"])
        #expect(slots.map(\.order) == [0, 1, 2])
    }

    @Test("do-next puts a movement immediately after the one named")
    func doNext() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        arrangement.moveNext("Cable Crossover", after: "Chest Press", in: deck)
        #expect(arrangement.slots(of: deck).map(\.originId) == ["Chest Press", "Cable Crossover", "Lat Pulldown"])
        // With nothing to come after — a finished deck — the front is the only
        // meaningful "next".
        var fresh = DeckArrangement()
        fresh.reconcile(with: deck)
        fresh.moveNext("Cable Crossover", after: nil, in: deck)
        #expect(fresh.slots(of: deck).map(\.originId) == ["Cable Crossover", "Chest Press", "Lat Pulldown"])
    }

    @Test("do-next on a skipped movement brings it back")
    func doNextUnskips() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        arrangement.toggleSkip("Cable Crossover")
        arrangement.moveNext("Cable Crossover", after: "Chest Press", in: deck)
        let slots = arrangement.slots(of: deck)
        #expect(slots.map(\.originId) == ["Chest Press", "Cable Crossover", "Lat Pulldown"])
        #expect(slots.allSatisfy { !$0.isSkipped })
    }

    @Test("a movement named by nobody, or moved onto itself, changes nothing")
    func moveNoOps() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        var before = arrangement
        arrangement.moveNext("Nonesuch", after: "Chest Press", in: deck)
        #expect(arrangement == before)
        arrangement.moveNext("Chest Press", after: nil, in: deck)
        #expect(arrangement.slots(of: deck).map(\.originId) == before.slots(of: deck).map(\.originId))
    }

    // MARK: - Swapping

    /// The second defect: the swap was keyed on the name currently in the
    /// slot, so the second swap wrote an entry nothing ever read.
    @Test("swapping the same slot twice replaces the first choice")
    func swapTwice() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        arrangement.swap("Chest Press", for: plan("Incline DB Press"), in: deck)
        arrangement.swap("Chest Press", for: plan("Machine Press"), in: deck)
        #expect(arrangement.slots(of: deck).map(\.plan.name) == ["Machine Press", "Lat Pulldown", "Cable Crossover"])
        #expect(arrangement.swaps.count == 1)
    }

    @Test("a swap keeps the slot's set count and rest, and takes the lift's own seed")
    func swapCarriesTheRightHalves() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        let candidate = ProgramExercise("Incline DB Press", sets: 5, wk1Kg: 22.5, reps: "10-14", restSec: 60)
        arrangement.swap("Chest Press", for: candidate, in: deck)
        let slot = try! #require(arrangement.slots(of: deck).first)
        #expect(slot.plan.sets == 3, "the slot's prescription, not the candidate's")
        #expect(slot.plan.restSec == 150)
        #expect(slot.plan.wk1Kg == 22.5, "the lift's own seed")
        #expect(slot.plan.reps == "10-14")
    }

    @Test("swapping a slot back to its own movement clears the swap")
    func swapBack() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        arrangement.swap("Chest Press", for: plan("Incline DB Press"), in: deck)
        arrangement.swap("Chest Press", for: plan("Chest Press"), in: deck)
        #expect(arrangement.swaps.isEmpty)
        #expect(arrangement.slots(of: deck).map(\.plan.name) == ["Chest Press", "Lat Pulldown", "Cable Crossover"])
    }

    @Test("a swap forgets what was remembered about the movement it replaced")
    func swapForgets() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        arrangement.addSet(to: "Chest Press")
        arrangement.toggleSkip("Chest Press")
        arrangement.pin("Chest Press")
        arrangement.swap("Chest Press", for: plan("Incline DB Press"), in: deck)
        let slot = try! #require(arrangement.slots(of: deck).first { $0.originId == "Chest Press" })
        #expect(slot.extraSets == 0)
        #expect(!slot.isSkipped)
        #expect(arrangement.pinned == nil)
    }

    // MARK: - Added sets

    @Test("one more set lands on the slot it names, and pins it")
    func addSet() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        arrangement.addSet(to: "Cable Crossover")
        arrangement.addSet(to: "Cable Crossover")
        let slots = arrangement.slots(of: deck)
        #expect(slots.first { $0.originId == "Cable Crossover" }?.extraSets == 2)
        #expect(slots.first { $0.originId == "Chest Press" }?.extraSets == 0)
        #expect(arrangement.pinned == "Cable Crossover")
    }

    // MARK: - The signature

    /// The third defect: an arrangement held INDICES and survived a routine
    /// edit that changed the same day's contents, so the indices named
    /// different movements — and a movement added on the phone never appeared
    /// on the wrist at all.
    @Test("a changed exercise list resets the arrangement")
    func signatureResets() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        arrangement.moveNext("Cable Crossover", after: "Chest Press", in: deck)
        arrangement.toggleSkip("Lat Pulldown")

        let widened = deck + [plan("Face Pull")]
        // The READ is pure and already answers the un-arranged deck, so a
        // view that draws before the owner reconciles cannot show a stale
        // order either.
        #expect(arrangement.slots(of: widened).map(\.originId)
                == ["Chest Press", "Lat Pulldown", "Cable Crossover", "Face Pull"])

        let didReset = arrangement.reconcile(with: widened)
        #expect(didReset)
        let slots = arrangement.slots(of: widened)
        #expect(slots.count == 4, "the added movement must be reachable")
        #expect(slots.allSatisfy { !$0.isSkipped })
        #expect(arrangement.order == nil)
        let didResetAgain = arrangement.reconcile(with: widened)
        #expect(didResetAgain == false, "reconciling twice is not a reset")
    }

    @Test("the same list, re-resolved, keeps the arrangement")
    func signatureHolds() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        arrangement.moveNext("Cable Crossover", after: "Chest Press", in: deck)
        let once = arrangement.slots(of: deck).map(\.originId)
        let twice = arrangement.slots(of: deck).map(\.originId)
        #expect(once == twice)
        #expect(once == ["Chest Press", "Cable Crossover", "Lat Pulldown"])
    }

    /// A slot's identity has to survive the thing in it changing, or the row
    /// is torn down under the gesture that swapped it.
    @Test("a slot's id is the slot, not the movement in it")
    func identityIsTheSlot() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        let before = arrangement.slots(of: deck).map(\.id)
        arrangement.swap("Chest Press", for: plan("Incline DB Press"), in: deck)
        #expect(arrangement.slots(of: deck).map(\.id) == before)
    }

    /// Every sequence of the five mutations leaves a deck that is still the
    /// deck: same slots, dense order, nothing duplicated.
    @Test("no sequence of moves can lose or duplicate a slot")
    func neverLosesASlot() {
        var arrangement = DeckArrangement()
        arrangement.reconcile(with: deck)
        let ids = Set(deck.map(\.id))
        let names = deck.map(\.id)
        for (i, origin) in names.enumerated() {
            arrangement.moveNext(origin, after: names[(i + 1) % names.count], in: deck)
            arrangement.toggleSkip(names[(i + 2) % names.count])
            arrangement.addSet(to: origin)
            arrangement.swap(origin, for: plan("Alt \(i)"), in: deck)
            arrangement.pin(origin)
            let slots = arrangement.slots(of: deck)
            #expect(Set(slots.map(\.originId)) == ids, "step \(i): a slot was lost or invented")
            #expect(slots.map(\.order) == Array(0..<slots.count), "step \(i): the order is not dense")
            #expect(Set(slots.map(\.id)).count == slots.count, "step \(i): a duplicate slot")
        }
    }
}
