import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// `StackSlot.linked` and the v5 payload (W7, A9).
//
// ── WHY THIS IS NOT IN `layout-from-stored.json` ────────────────────────────
// The golden vectors are a replay of the shipping TypeScript, and the
// TypeScript is gone (W6) — there is no oracle for a flag it never had. The
// fixtures are frozen evidence of what the two implementations agreed on; a
// case invented here and written into them would be this file's assertions
// wearing the fixtures' authority. So the new behaviour is asserted where it
// was decided, and the fixtures record only what the new id did to the
// arrangements they already held.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Connected stacks — the v5 flag")
struct LayoutLinkedTests {

    private func json(_ s: String) -> Any {
        try! JSONSerialization.jsonObject(with: Data(s.utf8))
    }

    /// The one that matters on a device: the row on the phone right now is v4.
    @Test("a v4 payload round-trips through v5 unchanged")
    func v4RoundTrips() throws {
        let stored = json("""
        {"v":4,"phone":{"slots":[
            {"id":"sl-sleep","size":"m","items":["sleep","vitals"]},
            {"id":"sl-water","size":"s","items":["water"]}
        ],"hidden":["steps"],"updatedAt":1700000000000}}
        """)
        let read = Dashboard.fromStored(stored, surface: .phone)
        // Absent means false, on every slot.
        #expect(read.slots.allSatisfy { !$0.linked })
        #expect(read.slots.first { $0.id == "sl-sleep" }?.items == [.sleep, .vitals])
        #expect(read.hidden == [.steps])

        // Written back, the phone side says the same thing it said — the slots
        // byte for byte, and only `v` moved.
        let written = Dashboard.serializeLayout(read, surface: .phone, other: stored)
        #expect(written["v"] as? Double == 5)
        let side = written["phone"] as! [String: Any]
        let slots = side["slots"] as! [[String: Any]]
        #expect(slots.allSatisfy { $0["linked"] == nil }, "a false flag is never written")
        #expect(Dashboard.fromStored(written, surface: .phone) == read)
    }

    @Test("a v5 payload reads its flag back, and a v4 one reads false")
    func readsTheFlag() {
        let v5 = json("""
        {"v":5,"phone":{"slots":[{"id":"a","size":"s","items":["water","steps"],"linked":true}],"hidden":[],"updatedAt":1}}
        """)
        #expect(Dashboard.fromStored(v5, surface: .phone).slots.first { $0.id == "a" }?.linked == true)

        // Anything that is not a JSON boolean is the pre-v5 meaning. A string
        // "true" is the shape a hand-edited row arrives in, and it must not
        // read as a connected stack.
        for raw in ["\"true\"", "1", "null", "{}"] {
            let odd = json("""
            {"v":5,"phone":{"slots":[{"id":"a","size":"s","items":["water"],"linked":\(raw)}],"hidden":[],"updatedAt":1}}
            """)
            #expect(Dashboard.fromStored(odd, surface: .phone).slots.first { $0.id == "a" }?.linked == false, "linked: \(raw)")
        }
    }

    @Test("a connected stack writes its flag")
    func writesTheFlag() {
        let layout = DashboardLayout(
            slots: [StackSlot(id: "a", size: .s, items: [.water, .steps], linked: true)],
            hidden: [], updatedAt: 1
        )
        let side = Dashboard.serializeLayout(layout, surface: .phone, other: nil)["phone"] as! [String: Any]
        let slot = (side["slots"] as! [[String: Any]])[0]
        #expect(slot["linked"] as? Bool == true)
        #expect(Dashboard.fromStored(Dashboard.serializeLayout(layout, surface: .phone, other: nil), surface: .phone)
            .slots.first { $0.id == "a" }?.linked == true)
    }

    /// The hazard the version bump creates, and the reason `splitVersions` is a
    /// set: a v5 writer over a v4 row must carry the desktop side through. Read
    /// the gate as `== version` and the first save after an upgrade silently
    /// wipes an arrangement the phone never had any business touching.
    @Test("a v5 write over a v4 row keeps the other surface")
    func carriesTheOtherSide() {
        let stored = json("""
        {"v":4,
         "phone":{"slots":[{"id":"p","size":"s","items":["water"]}],"hidden":[],"updatedAt":1},
         "desktop":{"slots":[{"id":"d","size":"l","items":["recovery"]}],"hidden":[],"updatedAt":2}}
        """)
        let phone = Dashboard.fromStored(stored, surface: .phone)
        let written = Dashboard.serializeLayout(phone, surface: .phone, other: stored)
        let desktop = written["desktop"] as! [String: Any]
        #expect((desktop["slots"] as! [[String: Any]])[0]["id"] as? String == "d")
        // And the same in the other direction, from a v5 row.
        let again = Dashboard.serializeLayout(Dashboard.fromStored(written, surface: .desktop), surface: .desktop, other: written)
        #expect(((again["phone"] as! [String: Any])["slots"] as! [[String: Any]])[0]["id"] as? String == "p")
    }

    @Test("the arrangement operations carry the flag")
    func opsCarryIt() {
        let layout = DashboardLayout(
            slots: [
                StackSlot(id: "a", size: .s, items: [.water, .steps, .cardio], linked: true),
                StackSlot(id: "b", size: .s, items: [.pr], linked: false),
            ],
            hidden: [], updatedAt: 0
        )
        // A face leaving does not disconnect what is left.
        #expect(Dashboard.removeFace(layout, slotId: "a", index: 0).slots.first { $0.id == "a" }?.linked == true)
        // The target stays and keeps its flag; the dragged slot's faces go under.
        let stacked = Dashboard.stackSlots(layout, fromId: "b", ontoId: "a")
        #expect(stacked.slots.first { $0.id == "a" }?.linked == true)
        #expect(stacked.slots.first { $0.id == "a" }?.items == [.water, .steps, .cardio, .pr])
        // The lifted face becomes its own tile, and a tile is not a stack.
        let lifted = Dashboard.unstackFace(layout, slotId: "a", index: 1)
        #expect(lifted.slots.first { $0.id == "a" }?.linked == true)
        #expect(lifted.slots.first { $0.items == [.steps] }?.linked == false)
        // A reorder does not touch it.
        #expect(Dashboard.reorderFace(layout, slotId: "a", from: 0, to: 2).slots.first { $0.id == "a" }?.linked == true)
    }

    @Test("setLinked refuses a single tile, stamps a real change and ignores a no-op")
    func setLinkedRules() {
        let layout = DashboardLayout(
            slots: [
                StackSlot(id: "a", size: .s, items: [.water, .steps]),
                StackSlot(id: "b", size: .s, items: [.pr]),
            ],
            hidden: [], updatedAt: 0
        )
        // A tile has nothing to share a window with.
        #expect(Dashboard.setLinked(layout, slotId: "b", true) == layout)
        // An unknown slot changes nothing.
        #expect(Dashboard.setLinked(layout, slotId: "zzz", true) == layout)
        // Setting it to what it already is does not stamp `updatedAt`, so a
        // sheet redrawing its own toggle cannot enqueue an outbox write.
        #expect(Dashboard.setLinked(layout, slotId: "a", false) == layout)

        let on = Dashboard.setLinked(layout, slotId: "a", true)
        #expect(on.slots.first { $0.id == "a" }?.linked == true)
        #expect(on.updatedAt > 0)
        // And off again, which a single tile is always allowed to be.
        #expect(Dashboard.setLinked(on, slotId: "a", false).slots.first { $0.id == "a" }?.linked == false)
    }

    /// `daily` is drawable and Large-only, and `reconcile` puts it last.
    @Test("the Mega Widget is one size, and it lands at the end of a stored layout")
    func megaWidget() {
        #expect(Dashboard.widgetIds.last == .daily)
        #expect(Dashboard.widgetSizes[.daily] == [.l])
        #expect(Dashboard.sizesFor([.daily]) == [.l])
        #expect(Dashboard.sizesFor([.daily], surface: .desktop) == [.l])
        // One rung on the ladder means the resize badge has nothing to offer,
        // which is what stops a Large-only face being asked to draw Small.
        #expect(Dashboard.resizeSlot(
            DashboardLayout(slots: [StackSlot(id: "a", size: .l, items: [.daily])], hidden: [], updatedAt: 0),
            slotId: "a"
        ).slots[0].size == .l)
        // Never stacked onto anything else either: no other widget draws at
        // Large only, so `clampSize` would have to shrink it.
        #expect(Dashboard.sizesFor([.daily, .sleep]) == [.l])

        let read = Dashboard.fromStored(
            json("""
            {"v":4,"phone":{"slots":[{"id":"sl-water","size":"s","items":["water"]}],"hidden":[],"updatedAt":1}}
            """),
            surface: .phone
        )
        #expect(read.slots.last?.items == [.daily])
        #expect(read.slots.last?.size == .l)
    }
}
