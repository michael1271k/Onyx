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

    /// Twenty-one since the Widgets/Sleep/Themes sprint's W4, which added
    /// `weekRings`, `soreness`, `stress` and `bedtime`. Seventeen since W7,
    /// which added the Mega Widget; sixteen before that — `trajectory` is
    /// W12's, and `deficit` and `fatigue` stopped being projected out when
    /// they got their series. The three without a face are still `bar`,
    /// `micros` and `stack`.
    @Test("the catalogue the phone offers is every widget with a face, in catalogue order")
    func native() {
        #expect(OnyxTile.native.count == 21)
        #expect(OnyxTile.native.first == .recovery)
        // The Mega Widget is declared last, so it is offered last.
        #expect(OnyxTile.native.last == .daily)
        #expect(OnyxTile.native.contains(.deficit))
        #expect(OnyxTile.native.contains(.fatigue))
        #expect(OnyxTile.native.contains(.trajectory))
        for id in [WidgetId.weekRings, .soreness, .stress, .bedtime] {
            #expect(OnyxTile.native.contains(id), "\(id.rawValue) has a face")
        }
        // The four land BEFORE the Mega Widget and after everything that was
        // already in the catalogue — the tail the golden vectors pin.
        #expect(OnyxTile.native.suffix(5) == [.weekRings, .soreness, .stress, .bedtime, .daily])
        // The order is the catalogue's, so the tray reads the way the grid does.
        #expect(OnyxTile.native == Dashboard.widgetIds.filter(\.isNative))
        for id in [WidgetId.bar, .micros, .stack] {
            #expect(!OnyxTile.native.contains(id), "\(id.rawValue) has no face yet")
        }
    }

    @Test("the jiggle's stagger is deterministic, inside its window, and spreads two ids")
    func stagger() {
        let a = Jiggle.stagger("sl-sleep"), b = Jiggle.stagger("sl-vitals")
        #expect(a == Jiggle.stagger("sl-sleep"))
        #expect(a >= 0 && a < Jiggle.staggerWindowMs)
        #expect(a != b)
    }

    // MARK: - Overhaul B1: every stack its own phase (decision Q10)

    /// The phase used to be a hash mod 7 s (the last 2 s of the 9 s period were
    /// never used, and two ids could collide), and a linked stack dropped it.
    @Test("stack phases are distinct, spread evenly over the whole period, and linked stacks keep theirs")
    func phasesSpread() {
        let slots = [
            StackSlot(id: "a", size: .s, items: [.sleep, .vitals], linked: true),
            StackSlot(id: "single", size: .s, items: [.steps]),
            StackSlot(id: "b", size: .s, items: [.water, .steps], linked: true),
            StackSlot(id: "c", size: .m, items: [.train, .daily]),
        ]
        let phases = SmartStackView.phases(slots)
        // A single tile does not rotate and takes no share of the period.
        #expect(phases["single"] == nil)
        #expect(phases.count == 3)
        let sorted = phases.values.sorted()
        #expect(Set(sorted).count == 3, "every stack its own phase, linked or not")
        // Evenly spread: the gaps between neighbours, INCLUDING the wrap back
        // to the first, are all a third of the period.
        let period = SmartStackView.period
        let gaps = zip(sorted, sorted.dropFirst() + [sorted[0] + period]).map { $1 - $0 }
        for gap in gaps { #expect(abs(gap - period / 3) < 1e-9) }
        #expect(sorted.allSatisfy { $0 >= 0 && $0 < period })
    }

    @Test("two linked stacks turn over at different moments")
    func linkedStacksHaveDistinctBeats() {
        let slots = [
            StackSlot(id: "sl-sleep", size: .s, items: [.sleep, .vitals], linked: true),
            StackSlot(id: "sl-vitals", size: .s, items: [.water, .steps], linked: true),
        ]
        let phases = SmartStackView.phases(slots)
        let now = Date(timeIntervalSince1970: 1_757_000_000)
        let a = SmartStackView.untilNextBeat(now: now, phase: phases["sl-sleep"]!)
        let b = SmartStackView.untilNextBeat(now: now, phase: phases["sl-vitals"]!)
        // Two stacks sit half a period apart; the grace floor can pull one of
        // them in, never both onto the same instant.
        #expect(abs(a - b) >= SmartStackView.grace)
    }

    @Test("a touch anywhere on the grid holds the rotation for three seconds; a swipe's touch-up is not a tap")
    func gridTouch() {
        let touch = GridTouch()
        let t0 = Date(timeIntervalSince1970: 1_757_000_000)
        #expect(touch.quiet(t0))
        touch.stamp(t0)
        #expect(!touch.quiet(t0.addingTimeInterval(2.9)))
        #expect(touch.quiet(t0.addingTimeInterval(3)))
        #expect(!touch.isSwipe(t0))
        touch.swipe(true, now: t0)
        #expect(touch.isSwipe(t0.addingTimeInterval(5)), "a swipe in flight is never a tap")
        touch.swipe(false, now: t0)
        #expect(touch.isSwipe(t0.addingTimeInterval(0.2)))
        #expect(!touch.isSwipe(t0.addingTimeInterval(0.5)))
    }

    // MARK: - W2: the rotation clock

    /// D3. The clock used to be a countdown the task restarted, so every resume
    /// cost `period + stagger` again. These are the two properties that say it
    /// is a clock and not a countdown.
    @Test("the beats are absolute: on the beat the wait is a full period, and a resume never waits more than one")
    func beats() {
        let phase = 3.0
        // 9_000 is a multiple of the 9 s period, so this instant IS a beat. A
        // second past it the next one is 8 s away — which is the property: the
        // wait is read off a grid fixed to the epoch, not counted from whenever
        // this view happened to start.
        let onBeat = Date(timeIntervalSince1970: 9_000 + phase)
        #expect(abs(SmartStackView.untilNextBeat(now: onBeat + 1, phase: phase) - 8) < 0.001)
        #expect(abs(SmartStackView.untilNextBeat(now: onBeat + 4.5, phase: phase) - 4.5) < 0.001)

        // The 40-minute-in-the-background case: the beat is already due, and the
        // tile must not flip in the blink the grid came back in.
        let overdue = onBeat.addingTimeInterval(-0.1)
        #expect(SmartStackView.untilNextBeat(now: overdue, phase: phase) == SmartStackView.grace)

        // Whenever the user comes back, the next face is at most a period away —
        // which is the whole of D3. Through the epoch too: `truncatingRemainder`
        // takes the sign of the dividend, so a date before 1970 used to return
        // up to twice a period.
        for step in stride(from: -9_020.0, to: 60.0, by: 0.37) {
            let wait = SmartStackView.untilNextBeat(now: onBeat.addingTimeInterval(step), phase: phase)
            #expect(wait > 0 && wait <= SmartStackView.period)
        }
    }

    /// Overhaul B1: the stack pages SIDEWAYS, orthogonal to the page scroll.
    /// The 30 pt vertical drag is the founder's "scrolling opens a tile" —
    /// it is never the stack's, so it stays the page's scroll, which cancels
    /// the tile's button.
    @Test("a drag is the stack's only when it is far enough AND more sideways than vertical")
    func takesTheDrag() {
        // Under the threshold, whatever the axis.
        #expect(!SmartStackView.takes(CGSize(width: 9, height: 0)))
        // Over it, and sideways.
        #expect(SmartStackView.takes(CGSize(width: -12, height: 0)))
        // The diagonal a thumb draws still pages: 30 across, 10 down.
        #expect(SmartStackView.takes(CGSize(width: 30, height: 10)))
        // A vertical drag is the page's, however long it is.
        #expect(!SmartStackView.takes(CGSize(width: 0, height: 30)))
        #expect(!SmartStackView.takes(CGSize(width: 40, height: 60)))
        // Exactly on the axis ratio is not enough (strictly greater).
        #expect(!SmartStackView.takes(CGSize(width: 30, height: 20)))
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

    /// Two stacks stay out of step with each other — the reason phases exist
    /// at all. A countdown restarted on resume loses this; a clock cannot.
    @Test("two slots resuming at the same instant land on different beats")
    func beatsStaySpread() {
        let now = Date(timeIntervalSince1970: 1_757_000_000)
        let a = SmartStackView.untilNextBeat(now: now, phase: 0)
        let b = SmartStackView.untilNextBeat(now: now, phase: 4.5)
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

    // MARK: - W7: the clobber (F9)

    /// THE bug. `dashboard_layouts` was always synced both ways — the layout was
    /// never lost, it was overwritten by the default the screen draws while the
    /// first stream yield is in flight. A save in that window is refused
    /// outright: nothing moves on screen, nothing is written locally, and above
    /// all nothing is enqueued for the server.
    @Test("an edit made before the first stream yield changes nothing and queues nothing")
    func saveBeforeLoadWritesNothing() throws {
        let database = try AppDatabase.inMemory(deviceId: "w7-clobber")
        // No seeded layout, and `observe()` never started: exactly the state the
        // grid is in for the first frame after `TodayTabView.task` runs.
        let model = TodayModel(database: database, userId: "u")
        let before = model.layout
        #expect(before == Dashboard.defaultLayout(.phone), "the screen still DRAWS a default — it just may not save one")

        // Every route a finger can take in that window.
        model.remove("sl-steps")
        model.resize("sl-sleep")
        model.move("sl-sleep", to: "sl-water")
        model.stack("sl-vitals", onto: "sl-sleep")
        model.add(.steps)

        #expect(model.layout == before)
        // The outbox is the half that reaches the other devices, and it is the
        // half that made this a data loss rather than a redraw.
        #expect(try database.pendingOutbox().isEmpty)
    }

    /// And the gate has to OPEN, or the grid is simply read-only. The first
    /// yield is a database round trip, so this polls rather than sleeping a
    /// fixed amount.
    @Test("the first stream yield opens the gate, and the next edit lands")
    func theGateOpens() async throws {
        let database = try AppDatabase.inMemory(deviceId: "w7-gate")
        let model = TodayModel(database: database, userId: "u")
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        var landed = false
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(10))
            model.resize("sl-sleep")
            if !(try database.pendingOutbox().isEmpty) { landed = true; break }
        }
        #expect(landed, "the stream yielded and the edit still was not saved")
    }

    /// A store with no row yields `nil`, and `nil` is an ANSWER. A first-launch
    /// device that could not save its first drag would be a worse bug than the
    /// one this wave fixes.
    @Test("a device with no stored row can still save its first arrangement")
    func firstLaunchCanSave() async throws {
        let database = try AppDatabase.inMemory(deviceId: "w7-first")
        let model = TodayModel(database: database, userId: "nobody-has-a-row")
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        var landed = false
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(10))
            model.resize("sl-vitals")
            if !(try database.pendingOutbox().isEmpty) { landed = true; break }
        }
        #expect(landed)
    }

    /// A preview or a shot hands a layout in and then arranges it; there is no
    /// stream behind either, so the seeded layout has to count as a load.
    @Test("a seeded layout is a load")
    func seededLayoutIsALoad() throws {
        let database = try AppDatabase.inMemory(deviceId: "w7-seeded")
        let model = TodayModel(
            database: database, userId: "u",
            layout: DashboardLayout(
                slots: [StackSlot(id: "a", size: .s, items: [.steps]), StackSlot(id: "b", size: .s, items: [.water])],
                hidden: [], updatedAt: 1
            )
        )
        model.move("a", to: "b")
        #expect(model.layout.slots.map(\.id) == ["b", "a"])
    }

    // MARK: - W7: connected stacks (A9)

    /// The flag survives the projection, or a stack the web stored with a
    /// web-only face would silently disconnect on the phone.
    @Test("projecting a slot keeps its connection")
    func projectionKeepsLinked() {
        let shown = TodayModel.projectNative([
            StackSlot(id: "a", size: .s, items: [.micros, .water, .sleep], linked: true)
        ])
        #expect(shown[0].items == [.water, .sleep])
        #expect(shown[0].linked)
    }

    // MARK: - W7: the wiggle

    /// ±1.1° — the Home Screen's own amplitude — and the phase window is the
    /// tile's OWN half-cycle. A stagger wider than the cycle wraps and is the
    /// same offset again, which is the bug the old 140 ms window had in the
    /// other direction: it was narrower than the 140 ms half-cycle only by
    /// accident.
    @Test("the wiggle leans 1.1 degrees and its phases fit inside one half-cycle")
    func wiggleGeometry() {
        #expect(TileFrame<EmptyView>.tilt == 1.1)
        for id in ["sl-sleep", "sl-vitals", "sl-water", "sl-steps", "sl-daily"] {
            let window = Int(TileFrame<EmptyView>.beat(id) * 1000)
            #expect(window > 0)
            #expect(Jiggle.stagger(id) % window < window)
        }
        // Two tiles do not start together, which is the whole point of the
        // offset — if they did the grid would march in step.
        let window = Int(TileFrame<EmptyView>.beat * 1000)
        #expect(Jiggle.stagger("sl-sleep") % window != Jiggle.stagger("sl-vitals") % window)
    }

    /// The per-tile RATE, which is what stops the grid re-synchronising: a
    /// shared duration holds whatever phase offset it started with forever, so
    /// the whole grid still pulses as one body.
    @Test("every tile runs at its own rate, within ten percent of the beat")
    func wiggleRatesDiffer() {
        let ids = ["sl-sleep", "sl-vitals", "sl-water", "sl-steps", "sl-daily"]
        let nominal = TileFrame<EmptyView>.beat
        for id in ids {
            let beat = TileFrame<EmptyView>.beat(id)
            #expect(beat >= nominal * 0.9)
            #expect(beat <= nominal * 1.1)
        }
        #expect(Set(ids.map { TileFrame<EmptyView>.beat($0) }).count > 1,
                "a shared period is the lockstep this exists to break")
        // And they do not all slide the same way — a drift every tile shared
        // would be the grid itself moving rather than the tiles inside it.
        #expect(Set(ids.map { TileFrame<EmptyView>.driftSign($0) }).count == 2)
    }
}
