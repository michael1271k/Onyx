import Testing
import Foundation
import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI
@testable import Onyx

@MainActor
@Suite("Today model")
struct TodayModelTests {

    /// `micros` in place of `deficit` since W12: the Deficit Ledger has a face
    /// now, and the three still without one are `bar`, `micros` and `stack`.
    @Test("web-only faces are projected out of a slot; a slot with none left disappears; the layout is untouched")
    func projection() {
        let slots = [
            StackSlot(id: "a", size: .m, items: [.sleep, .micros, .vitals]),
            StackSlot(id: "b", size: .s, items: [.stack]),
            StackSlot(id: "c", size: .s, items: [.steps]),
        ]
        let shown = TodayModel.projectNative(slots)
        #expect(shown.map(\.id) == ["a", "c"])
        #expect(shown[0].items == [.sleep, .vitals])
        #expect(shown[0].size == .m)
    }

    @Test("rows pair smalls and give every taller tile its own row; a lone small stays lone")
    func packing() {
        let s = { (id: String, size: WidgetSize) in StackSlot(id: id, size: size, items: [.steps]) }
        let rows = DashboardGrid.rows([s("a", .s), s("b", .m), s("c", .s), s("d", .s), s("e", .l), s("f", .s)])
        #expect(rows.map { $0.slots.map(\.id) } == [["a"], ["b"], ["c", "d"], ["e"], ["f"]])
    }

    /// Sixteen since W12: `trajectory` is new, and `deficit` and `fatigue`
    /// stopped being projected out when they got their series. The three
    /// without a face are `bar`, `micros` and `stack`.
    @Test("the catalogue the phone offers is every widget with a face, in catalogue order")
    func native() {
        #expect(OnyxTile.native.count == 16)
        #expect(OnyxTile.native.first == .recovery)
        #expect(OnyxTile.native.contains(.deficit))
        #expect(OnyxTile.native.contains(.fatigue))
        #expect(OnyxTile.native.contains(.trajectory))
        // The order is the catalogue's, so the tray reads the way the grid does.
        #expect(OnyxTile.native == Dashboard.widgetIds.filter(\.isNative))
        for id in [WidgetId.bar, .micros, .stack] {
            #expect(!OnyxTile.native.contains(id), "\(id.rawValue) has no face yet")
        }
    }

    @Test("stagger is deterministic, inside the window, and spreads two ids")
    func stagger() {
        let a = SmartStackView.stagger("sl-sleep"), b = SmartStackView.stagger("sl-vitals")
        #expect(a == SmartStackView.stagger("sl-sleep"))
        #expect(a >= 0 && a < SmartStackView.staggerWindowMs)
        #expect(a != b)
    }

    // MARK: - W2: the rotation clock

    /// D3. The clock used to be a countdown the task restarted, so every resume
    /// cost `period + stagger` again. These are the two properties that say it
    /// is a clock and not a countdown.
    @Test("the beats are absolute: on the beat the wait is a full period, and a resume never waits more than one")
    func beats() {
        let id = "sl-sleep"
        let phase = TimeInterval(SmartStackView.stagger(id)) / 1000
        // 9_000 is a multiple of the 9 s period, so this instant IS a beat. A
        // second past it the next one is 8 s away — which is the property: the
        // wait is read off a grid fixed to the epoch, not counted from whenever
        // this view happened to start.
        let onBeat = Date(timeIntervalSince1970: 9_000 + phase)
        #expect(abs(SmartStackView.untilNextBeat(now: onBeat + 1, slotId: id) - 8) < 0.001)
        #expect(abs(SmartStackView.untilNextBeat(now: onBeat + 4.5, slotId: id) - 4.5) < 0.001)

        // The 40-minute-in-the-background case: the beat is already due, and the
        // tile must not flip in the blink the grid came back in.
        let overdue = onBeat.addingTimeInterval(-0.1)
        #expect(SmartStackView.untilNextBeat(now: overdue, slotId: id) == SmartStackView.grace)

        // Whenever the user comes back, the next face is at most a period away —
        // which is the whole of D3. Through the epoch too: `truncatingRemainder`
        // takes the sign of the dividend, so a date before 1970 used to return
        // up to twice a period.
        for step in stride(from: -9_020.0, to: 60.0, by: 0.37) {
            let wait = SmartStackView.untilNextBeat(now: onBeat.addingTimeInterval(step), slotId: id)
            #expect(wait > 0 && wait <= SmartStackView.period)
        }
    }

    @Test("a drag is the stack's only when it is far enough AND more vertical than sideways")
    func takesTheDrag() {
        // Under the threshold, whatever the axis.
        #expect(!SmartStackView.takes(CGSize(width: 0, height: 9)))
        // Over it, and vertical.
        #expect(SmartStackView.takes(CGSize(width: 0, height: -12)))
        // The diagonal a thumb draws still pages: 30 down, 10 across.
        #expect(SmartStackView.takes(CGSize(width: 10, height: 30)))
        // Mostly sideways does not, however long it is — `minimumDistance`
        // measures the VECTOR, so this drag reaches the gesture and has to be
        // refused here or the grid's scroll latches off for nothing.
        #expect(!SmartStackView.takes(CGSize(width: 60, height: 40)))
        // Exactly on the axis ratio is not enough (strictly greater).
        #expect(!SmartStackView.takes(CGSize(width: 20, height: 30)))
    }

    @Test("the swipe commits on the throw, or on a drag that went far enough and stopped")
    func commitRule() {
        let h: CGFloat = 160
        // A short flick: too little travel, but projected well past a third.
        #expect(SmartStackView.step(travelled: -14, projected: -90, over: h) == 1)
        // A slow drag that stopped: no throw left, a quarter of the face gone.
        // This is the case `hold` exists for — under the projection rule alone
        // (at rest, projected == travelled) it would snap back.
        #expect(SmartStackView.step(travelled: -44, projected: -44, over: h) == 1)
        #expect(SmartStackView.step(travelled: 44, projected: 44, over: h) == -1)
        // A nudge stays put.
        #expect(SmartStackView.step(travelled: -20, projected: -22, over: h) == 0)
        // Pulled down a quarter, flicked up at the moment of release: the two
        // rules disagree in SIGN, so the distance rule is refused and the page
        // does not slide away from the offset the finger is looking at.
        #expect(SmartStackView.step(travelled: 44, projected: -30, over: h) == 0)
        // …but a real throw the other way still wins on its own.
        #expect(SmartStackView.step(travelled: 44, projected: -80, over: h) == 1)
    }

    /// The band's asymptote is its `dimension`: pull forever and it gives back
    /// exactly that much and no more. A zero dimension used to be 0/0.
    @Test("the rubber band saturates at its dimension and never returns NaN")
    func rubberBand() {
        #expect(SmartStackView.resisted(0, over: 0) == 0)
        #expect(SmartStackView.resisted(1_000_000, over: 68) < 68)
        #expect(SmartStackView.resisted(1_000_000, over: 68) > 67)
        // Monotone, and it always gives back less than it is pulled.
        #expect(SmartStackView.resisted(40, over: 68) < 40)
        #expect(SmartStackView.resisted(80, over: 68) > SmartStackView.resisted(40, over: 68))
        #expect(SmartStackView.resisted(-40, over: 68) == -SmartStackView.resisted(40, over: 68))
    }

    /// The face the menu NAMES and the face `unstackFace` lifts are indexed in
    /// two different lists whenever a slot carries a face the phone cannot draw.
    @Test("unstacking the visible face lifts that face, not the one at the same stored index")
    func unstackCrossesTheProjection() throws {
        let database = try AppDatabase.inMemory(deviceId: "w2-unstack")
        // What the web can store: `micros` has no native face, so the phone
        // draws this three-item slot as the two-face stack [water, sleep].
        let layout = DashboardLayout(
            slots: [StackSlot(id: "a", size: .s, items: [.micros, .water, .sleep])],
            hidden: [], updatedAt: 0
        )
        let model = TodayModel(database: database, userId: "u", layout: layout)
        #expect(model.visibleSlots[0].items == [.water, .sleep])

        // Sleep is the second face ON SCREEN and the third one STORED.
        model.unstackVisible("a", visibleIndex: 1)
        #expect(Dashboard.slot(model.layout, at: "a")?.items == [.micros, .water])
        #expect(model.layout.slots.count == 2)
        #expect(model.layout.slots[1].items == [.sleep])
        // And the tile goes on showing what it showed, rather than losing Water.
        #expect(model.visibleSlots.map(\.items) == [[.water], [.sleep]])
    }

    /// Two stacks stay out of step with each other — the reason `stagger` exists
    /// at all. A countdown restarted on resume loses this; a clock cannot.
    @Test("two slots resuming at the same instant land on different beats")
    func beatsStaySpread() {
        let now = Date(timeIntervalSince1970: 1_757_000_000)
        let a = SmartStackView.untilNextBeat(now: now, slotId: "sl-sleep")
        let b = SmartStackView.untilNextBeat(now: now, slotId: "sl-vitals")
        #expect(abs(a - b) > 0.5)
    }

    // MARK: - W2: face identity

    /// D4. `items` may repeat a widget, so the raw value is not a unique id; the
    /// index is unique and moves under a reorder. The occurrence key is both.
    @Test("a repeated widget still gets distinct face ids")
    func faceIdentity() {
        let ids = SmartStackView.faces([.water, .steps, .water]).map(\.id)
        #expect(ids == ["water#0", "steps#0", "water#1"])
        #expect(Set(ids).count == 3)
    }

    /// The gate: sort the stack in the Edit Stack sheet and the tile goes on
    /// showing the same thing. It used to show whatever moved into that slot.
    @Test("a reorder moves the face index so the same widget stays up")
    func reorderKeepsTheVisibleFace() {
        // Sleep is up at index 0; the sheet moves it below Vitals.
        #expect(SmartStackView.follow(0, from: [.sleep, .vitals], to: [.vitals, .sleep]) == 1)
        // Vitals was up at 1 and is now on top.
        #expect(SmartStackView.follow(1, from: [.sleep, .vitals], to: [.vitals, .sleep]) == 0)
        // The SECOND Water is up; it is still the second Water afterwards.
        #expect(SmartStackView.follow(2, from: [.water, .steps, .water], to: [.steps, .water, .water]) == 2)
        // Nothing moved: nothing moves.
        #expect(SmartStackView.follow(1, from: [.sleep, .vitals], to: [.sleep, .vitals]) == 1)
    }

    /// The face that is up is also the face `Unstack` lifts, so it is the one
    /// most likely to leave. Then there is nothing to follow and the index has
    /// to land somewhere real.
    @Test("a face that leaves the stack clamps the index instead of pointing past the end")
    func removalClamps() {
        #expect(SmartStackView.follow(1, from: [.sleep, .vitals], to: [.sleep]) == 0)
        #expect(SmartStackView.follow(0, from: [.sleep, .vitals], to: [.vitals]) == 0)
        #expect(SmartStackView.follow(2, from: [.sleep, .vitals, .steps], to: [.sleep, .steps]) == 1)
    }

    // MARK: - W2: what the long-press menu offers

    /// D1's rule, and it is `Dashboard.canStack`'s — the menu and the
    /// drag-and-hold must never disagree about which pairs are legal.
    @Test("the menu offers same-size tiles only, never the tile itself, and never one the phone does not draw")
    func stackTargets() throws {
        let database = try AppDatabase.inMemory(deviceId: "w2")
        let layout = DashboardLayout(
            slots: [
                StackSlot(id: "a", size: .s, items: [.steps]),
                StackSlot(id: "b", size: .s, items: [.water]),
                StackSlot(id: "c", size: .m, items: [.sleep]),
                // Every face is web-only, so this slot is not on the screen and
                // must not be offered as somewhere to put a tile.
                StackSlot(id: "d", size: .s, items: [.bar]),
            ],
            hidden: [], updatedAt: 0
        )
        let model = TodayModel(database: database, userId: "u", layout: layout)
        #expect(model.stackTargets("a").map(\.id) == ["b"])
        #expect(model.stackTargets("c").isEmpty)
        // A slot the phone does not draw has nothing to stack, either way round.
        #expect(model.stackTargets("d").isEmpty)
    }

    // MARK: - W2: what VoiceOver hears

    @Test("a stack announces the face that is up, then its depth; a single tile is just its name")
    func tileLabel() {
        let stack = StackSlot(id: "a", size: .s, items: [.sleep, .vitals])
        #expect(TileFrame<EmptyView>.label(stack, up: .vitals) == "Vitals. Stack of 2.")
        let single = StackSlot(id: "b", size: .s, items: [.steps])
        #expect(TileFrame<EmptyView>.label(single, up: .steps) == "Steps")
    }
}
