import SwiftUI
import OnyxCore
import OnyxUI

/// The faces of one slot, and the two ways they turn over.
///
/// ── A STACK ROTATES, AND IT ALSO OBEYS A FINGER ──────────────────────────────
/// Left alone, a stack shows each face for nine seconds — slow enough never to
/// flip while a number is being read, quick enough that a tile reads as having
/// another side. A vertical swipe steps through by hand, and after any manual
/// swipe the clock holds for a full period: a tile that flips out from under a
/// finger that just chose a face has overruled its user.
///
/// Every stack gets its own phase (`stagger`), so the grid never turns over on
/// one beat like a page refresh. The clock stops in edit mode and whenever the
/// scene leaves the foreground.
///
/// ── THE BEATS ARE ABSOLUTE, NOT A COUNTDOWN (W2, D3) ─────────────────────────
/// The phase used to be a one-shot prologue: `sleep(period + stagger)` and then
/// a loop. `.task(id:)` keys on whether the clock runs, so every pause — every
/// trip to the background, every visit to edit mode — tore the task down and
/// started the prologue again from zero. A phone picked up after lunch waited
/// nine seconds plus up to seven more before a stack moved, every single time,
/// and every stack on the grid re-phased onto the instant the user unlocked.
///
/// `untilNextBeat` makes the beats a property of the CLOCK rather than of the
/// task: every multiple of `period` since 1970, shifted by the slot's own
/// stagger. Nothing is carried across a pause because nothing needs to be — a
/// stack coming back rejoins the beat it would have been on had it never
/// stopped, so the grid stays spread out and the wait is never more than one
/// period.
///
/// ── PAGING IS THIS VIEW'S OWN GESTURE (W2, D2) ───────────────────────────────
/// It was a `TabView(.page)` rotated a quarter turn, and the comment here used
/// to justify that by saying vertical was the axis "the grid's own scroll does
/// not" use. That was imported from the Home Screen, where the grid pages
/// sideways. It is not true here: `TodayTabView` is a plain vertical
/// `ScrollView`, so the stack and the screen under it were pulling on the same
/// axis and the TabView won every time you meant to scroll past it.
///
/// So the faces are a `ZStack` offset by hand, and the gesture is explicit:
///
///  · `.simultaneousGesture`, never `.gesture` — a plain `DragGesture` BEATS an
///    enclosing `ScrollView`'s pan outright, from touch-down, which would make
///    every stacked tile a dead patch you cannot scroll the dashboard by. That
///    is not a guess; it is what a 300 pt body figure did to the atlas sheet
///    (`AtlasSheet.swift:257`).
///  · `takeover` (10 pt) is what keeps the parent's short drags. Under it the
///    dashboard scrolls and this view has not started; over it the stack claims
///    the finger. It was 16, chosen so that a press which becomes a drag had
///    already failed `LongPressGesture`'s slop (10 pt, and the same 10 for
///    `UILongPressGestureRecognizer.allowableMovement`, which is what
///    `.contextMenu` runs on) — the ordering held by arithmetic. At 10 the two
///    are a tie rather than a guarantee, and that is affordable because the
///    drag is `.simultaneousGesture`: it does not FAIL the tile's tap or its
///    menu, both of which live on `TileFrame` above this view. What the six
///    points bought was stiffness — the finger spent them scrolling the grid
///    before the faces moved at all.
///  · Which makes the AXIS the real gate, not the distance. `minimumDistance`
///    measures the translation VECTOR, so at 10 pt a sideways drag reaches the
///    gesture too; `takes(_:)` is what refuses it. Latching the grid's scroll
///    off for a drag that then moves nothing is a dead screen with no feedback
///    on it, and that is the failure a lower threshold would otherwise buy.
///  · Simultaneous alone would page the stack AND scroll the grid — the atlas
///    solves that with an axis lock, which needs two axes and there is only one
///    here. So the takeover LATCHES: `paging` switches the parent's scroll off
///    for the rest of the drag. A disabled `UIScrollView` cancels the pan it is
///    holding, so the grid stops where it is rather than coasting on.
///
/// The handover costs the parent those first 16 pt of scroll. That is the trade
/// the threshold buys and it cannot be had both ways: a stack that claims the
/// axis from touch-down is a stack you cannot scroll past.
struct SmartStackView: View {
    let slot: StackSlot
    let entry: OnyxTileEntry
    let paused: Bool
    /// Which face is up, owned by the GRID.
    ///
    /// ── WHY THIS IS NOT LOCAL STATE ANY MORE ────────────────────────────────
    /// It was `@State`, so the only thing that knew which of a stack's faces was
    /// on screen was the view drawing it — and the tap handler lives one level
    /// up, on the tile's chrome. That handler opened `items.first`, always. A
    /// Sleep/Vitals stack therefore opened Sleep from both sides: the rotation
    /// turned the tile over, the tap did not turn over with it, and the sheet
    /// that appeared was about the face you had just stopped looking at.
    ///
    /// Hoisting the index is the whole fix. Nothing else about the rotation, the
    /// swipe or the hold-off changes — the grid simply knows what it is showing.
    @Binding var face: Int
    /// The slot id that currently owns a drag, or nil. The Today screen reads it
    /// as `.scrollDisabled`. See the header.
    ///
    /// ── WHY AN ID AND NOT A BOOL ────────────────────────────────────────────
    /// `@GestureState` guarantees the latch clears when a gesture is CANCELLED.
    /// It does not save a view that is DESTROYED mid-drag, which runs no
    /// `onChange` at all — and that is routine here, not exotic:
    /// `DashboardGrid.Row.id` is the row's slot ids joined, so any layout change
    /// (a `dashboard_layouts` row arriving from the web mid-swipe, a stack made
    /// on another device) re-ids the row and rebuilds this subtree. A stuck Bool
    /// leaves the whole Today tab unscrollable until the app is killed.
    ///
    /// `.onDisappear` covers that — but only if the latch says WHOSE drag it is.
    /// With two stacks on screen, a bare `paging = false` in B's `onDisappear`
    /// would lower A's latch out from under A's finger.
    @Binding var paging: String?

    @State private var touchedAt = Date.distantPast
    @State private var byClock = false
    @State private var drag: CGFloat = 0
    /// The translation at the moment of takeover. The 10 pt the finger already
    /// spent scrolling the grid are not spent again on the faces, so nothing
    /// jumps at the handover.
    @State private var origin: CGFloat?
    /// Which gesture the `origin` above belongs to — the touch-down point,
    /// which is unique per drag in practice and, unlike the latch, is known
    /// inside `onChanged` itself rather than one view update later.
    @State private var startedAt: CGPoint?
    /// `@GestureState` because it CANNOT be allowed to stick. A drag cancelled
    /// out from under the view — a system edge swipe, a call arriving — never
    /// calls `onEnded`, and a plain `@State` latch that missed its reset would
    /// leave the dashboard's scroll switched off until the view was rebuilt.
    @GestureState private var held = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One face, nine seconds.
    static let period: TimeInterval = 9
    /// Just under one period, so the offsets spread across a whole turn.
    static let staggerWindowMs = 7_000
    /// A tile never turns over in the blink the grid came back in.
    static let grace: TimeInterval = 2
    /// How far the finger travels before the stack takes the drag from the
    /// dashboard. See the header for why it is this and not more.
    static let takeover: CGFloat = 10
    /// How much more vertical than sideways a drag has to be to be this view's.
    /// 1.5 rather than 1.0 so the diagonal a thumb actually draws on a tile at
    /// the edge of the grid still pages, while a drag that is mostly across the
    /// screen is left to whatever is under it.
    static let axis: CGFloat = 1.5
    /// Heading past this much of a face once the throw is projected, the swipe
    /// commits to the next one.
    static let commit: CGFloat = 1.0 / 3.0
    /// Past this much of a face with the throw spent, it commits anyway.
    ///
    /// At release with no velocity left `predictedEndTranslation` IS
    /// `translation`, so the projection above is the only rule and it asks for a
    /// third of the tile. That is the stiffness: a finger that drags a face
    /// most of the way, stops to look, and lifts, gets the face it started on
    /// back. This is the rule for that finger, and it is the only case it
    /// changes — with any real velocity the projection is the larger of the two
    /// and fires first.
    static let hold: CGFloat = 0.25

    /// Which face the swipe committed to, relative to the one up: -1, 0 or +1.
    ///
    /// Both measurements are in FINGER units, from the takeover point rather
    /// than from the resisted `drag` — the throw is judged by what the hand did,
    /// not by how much of it the rubber band gave back.
    static func step(travelled: CGFloat, projected: CGFloat, over h: CGFloat) -> Int {
        // The throw, OR a drag that went far enough and stopped (see `hold`).
        // The sign test is not decoration: the DIRECTION comes from the
        // projection, so a face pulled a quarter of the way down and then
        // flicked up at the moment of release would satisfy the distance rule
        // downwards and page upwards — the tile sliding away from the finger's
        // own offset, which is a worse failure than the stiffness this rule
        // exists to fix.
        let far = abs(projected) > h * commit
            || (abs(travelled) > h * hold && travelled * projected > 0)
        guard far else { return 0 }
        return projected < 0 ? 1 : -1
    }

    /// Is this drag the stack's? Far enough, and meaningfully more vertical
    /// than it is sideways.
    ///
    /// One predicate because the test is made TWICE — in `.updating` and in
    /// `.onChanged` — and two spellings of it drifting apart is a stack that
    /// latches the grid's scroll off and then does not move.
    static func takes(_ translation: CGSize) -> Bool {
        abs(translation.height) >= takeover && abs(translation.height) > abs(translation.width) * axis
    }

    /// A deterministic offset per slot — the id's Java hash, as the web did,
    /// so the phase survives a remount and is the same on every device.
    static func stagger(_ slotId: String) -> Int {
        var h: Int32 = 0
        for unit in slotId.utf16 { h = h &* 31 &+ Int32(unit) }
        return Int(abs(Int(h))) % staggerWindowMs
    }

    /// Seconds until this slot's next beat — see the header.
    ///
    /// Wall-clock, not `ContinuousClock`: the phase has to mean the same thing
    /// across a relaunch and on every device, and a monotonic clock's zero is
    /// whenever the phone last booted. Each iteration re-derives from the epoch,
    /// so no sleep can accumulate drift.
    ///
    /// The floor is the one concession. A beat that is already due would flip
    /// the tile in the same blink it came back; `grace` pushes exactly one flip
    /// off the beat, and the next call measures from the epoch again.
    static func untilNextBeat(now: Date = .now, slotId: String) -> TimeInterval {
        let since = now.timeIntervalSince1970 - TimeInterval(stagger(slotId)) / 1000
        // `truncatingRemainder` takes the sign of the DIVIDEND, so a `since`
        // before the epoch would return more than a period and break the one
        // invariant this function has.
        let r = since.truncatingRemainder(dividingBy: period)
        return max(period - (r < 0 ? r + period : r), grace)
    }

    /// One face, with an identity that survives a reorder.
    ///
    /// ── WHY NOT THE INDEX, AND WHY NOT THE WIDGET (W2, D4) ──────────────────
    /// `items` is ordered and MAY repeat a widget (`Layout.swift:52`), so the
    /// raw value is not unique and cannot be a `ForEach` id on its own. The
    /// index is unique and is not STABLE: `reorderFace` moves one element and
    /// every index after it shifts, so a reorder in the Edit Stack sheet left
    /// `face` pointing at a position that now held something else — you sorted
    /// the stack and the tile silently changed what it was showing.
    ///
    /// The occurrence key is both. It identifies the second Water in a stack as
    /// distinct from the first, and it follows either of them through a move, so
    /// `face` can be re-pointed at the same widget on the other side of a
    /// reorder instead of at the same slot in the list.
    struct Face: Identifiable, Equatable {
        let index: Int
        let id: String
        let widget: WidgetId
    }

    static func faces(_ items: [WidgetId]) -> [Face] {
        var seen: [WidgetId: Int] = [:]
        return items.enumerated().map { index, widget in
            let n = seen[widget, default: 0]
            seen[widget] = n + 1
            return Face(index: index, id: "\(widget.rawValue)#\(n)", widget: widget)
        }
    }

    /// Where `face` has to move so the SAME face stays up across a change to
    /// `items` — a reorder, or a face lifted out of the stack. Falls back to a
    /// clamp when the face that was up is the one that left.
    static func follow(_ face: Int, from old: [WidgetId], to new: [WidgetId]) -> Int {
        let clamped = min(max(face, 0), max(0, new.count - 1))
        let was = faces(old)
        guard was.indices.contains(face) else { return clamped }
        return faces(new).first { $0.id == was[face].id }?.index ?? clamped
    }

    private var rotating: Bool { slot.items.count > 1 && !paused }

    var body: some View {
        let faces = Self.faces(slot.items)
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                ForEach(faces) { f in
                    OnyxTile.face(f.widget, entry: entry)
                        .frame(width: w, height: h)
                        // A `ZStack` materialises every face, and `.clipped()`
                        // clips DRAWING, not the accessibility tree. Without
                        // this, VoiceOver reads all three widgets of a
                        // three-face stack while one is on screen — which the
                        // rotated `TabView` never did, because UIKit's page
                        // controller excludes the pages either side.
                        .accessibilityHidden(f.index != face)
                        // EVERY face clips to its own page, not just the stack
                        // to the tile. A face whose content is taller than the
                        // tile — the large Sleep face is — overflows its frame
                        // in BOTH directions, so the face waiting one page below
                        // bled up into the one on screen and the tile drew two
                        // widgets at once. `TabView` clipped each page for us;
                        // a `ZStack` does not.
                        .clipped()
                        .offset(y: CGFloat(f.index - face) * h + drag)
                }
            }
            .frame(width: w, height: h)
            // The clip goes on the FACES, under the rail. Each face is already
            // clipped to its own page; this is what keeps the pages waiting
            // above and below from drawing outside the tile. The dot rail is
            // overlaid after it, because the rail deliberately sits outside the
            // face box and a clip over the top would erase it.
            .clipped()
            .contentShape(.rect)
            .simultaneousGesture(page(h))
            .overlay(alignment: .trailing) { dots(faces) }
        }
        // The latch can only be lowered here. `onEnded` lowers it too, but a
        // cancelled gesture never reaches `onEnded` — this one always runs.
        .onChange(of: held) { _, on in
            if on {
                paging = slot.id
                // `origin` used to be cleared HERE, on the way in, to discard
                // one a cancelled drag had left behind. It cannot be: this is a
                // view update, so it runs one pass AFTER `onChanged` has already
                // set the origin for this gesture — making the SECOND event past
                // the threshold the takeover point and throwing away a frame of
                // travel (~16 pt at a fast flick) from both the offset and the
                // commit distance. `startedAt` now owns that job, inside
                // `onChanged`, where the touch is identified rather than guessed.
            } else {
                if paging == slot.id { paging = nil }
                if drag != 0 {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : OnyxMotion.flick) { drag = 0 }
                }
            }
        }
        .onDisappear { if paging == slot.id { paging = nil } }
        .onChange(of: face) { _, _ in
            if byClock { byClock = false } else { touchedAt = .now }
        }
        .onChange(of: slot.items) { old, new in
            let next = Self.follow(face, from: old, to: new)
            // Sorting the stack in the Edit Stack sheet is not a swipe. Without
            // this the re-point trips the hold-off below and the tile sits still
            // for a period or two afterwards.
            if next != face { byClock = true }
            face = next
        }
        // The id carries the COUNT, not just whether the clock runs: the task
        // captured `slot`, so a stack that gained or lost a face would go on
        // modding by the old count and raise a face that is not there.
        .task(id: rotating ? slot.items.count : 0) {
            guard rotating else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.untilNextBeat(slotId: slot.id)))
                // `try?` swallowed the cancellation error along with the sleep.
                guard !Task.isCancelled else { return }
                guard Date.now.timeIntervalSince(touchedAt) >= Self.period else { continue }
                byClock = true
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : OnyxMotion.flick) {
                    face = (face + 1) % max(1, slot.items.count)
                }
            }
        }
    }

    /// 1:1 with the finger while it is down, thrown where UIKit says it is going
    /// when it leaves.
    private func page(_ h: CGFloat) -> some Gesture {
        // `minimumDistance` is the length of the translation VECTOR, not of its
        // vertical component, so a 16 pt drag across the tile satisfies it. The
        // axis test is therefore made here, twice, rather than inferred from the
        // gesture starting: latching the parent's scroll off for a sideways drag
        // that then moves nothing is a dead screen with no feedback on it.
        //
        // `held` only ever goes up within one gesture — a finger that wanders
        // back inside the threshold must not hand the scroll back mid-drag.
        DragGesture(minimumDistance: Self.takeover)
            .updating($held) { value, held, _ in
                held = held || Self.takes(value.translation)
            }
            .onChanged { value in
                // `origin` is cleared on the way IN by `onChange(of: held)` —
                // which is a view update, so it runs AFTER this closure has
                // already read it on the first event of a gesture. A CANCELLED
                // drag leaves one behind (`onEnded`'s `defer` never runs), and
                // the next drag's first frame then measures from a point in the
                // last one: a page-sized jump, snapped back the frame after.
                // The touch-down point says whose `origin` this is, which is a
                // fact the closure holds rather than one it has to be told.
                if startedAt != value.startLocation {
                    startedAt = value.startLocation
                    origin = nil
                }
                guard Self.takes(value.translation) else { return }
                let from = origin ?? value.translation.height
                if origin == nil { origin = from }
                touchedAt = .now
                let d = value.translation.height - from
                // ONE page of travel in each direction, and only where there is
                // a face to travel to; everything past that is resisted.
                //
                // One page because `step` below commits at most one — a drag
                // that slid two faces along and then snapped one back would be
                // the interface disagreeing with the finger. And resisted rather
                // than stopped, because a hard edge reads as frozen while a
                // stack that followed the finger off its own end would be
                // claiming there is another one.
                let down = face > 0 ? h : 0
                let up = face < slot.items.count - 1 ? -h : 0
                let inside = min(max(d, up), down)
                drag = inside + Self.resisted(d - inside, over: h * 0.6)
            }
            .onEnded { value in
                defer { origin = nil; startedAt = nil }
                // ── THE GESTURE ONLY ENDS IF IT EVER BEGAN ──────────────────
                // `onChanged` refuses a drag the axis test does not claim, and
                // `origin` is set there and nowhere else — so a nil `origin` is
                // exactly "this drag was never the stack's". Without this, a
                // refused drag fell through to `step` measuring from ZERO and
                // paged the tile with no preceding motion at all: 70 pt across
                // and 45 pt down on a small tile — the shape `TodayModelTests`
                // asserts is NOT the stack's — draws nothing, then flips a face
                // on release. `hold` widened that window (a quarter of a face,
                // no throw required) and the lower `takeover` lets more drags
                // reach here, so it has to be closed at the top.
                //
                // It also stops a refused drag touching `touchedAt`, which
                // would hold the auto-rotation off for a period the user never
                // asked for.
                guard origin != nil else { return }
                // `predictedEndTranslation` is the system's own momentum
                // projection — the same rule the logger's hero uses
                // (`LoggerHero.swift:568`) rather than a deceleration constant
                // re-derived here. Distance alone refuses a fast short flick,
                // which is how a thumb actually turns a small tile over; the
                // projection alone refuses a slow drag that stopped, which is
                // how one reads a tile before turning it. `step` takes both.
                let from = origin ?? 0
                let step = Self.step(
                    travelled: value.translation.height - from,
                    projected: value.predictedEndTranslation.height - from,
                    over: h
                )
                // Load-bearing, not belt-and-braces: a hard throw past the last
                // face projects well past the commit threshold, and this clamp
                // is the only thing that stops it stepping off the end.
                let next = min(max(face + step, 0), slot.items.count - 1)
                touchedAt = .now
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : OnyxMotion.flick) {
                    face = next
                    drag = 0
                }
            }
    }

    /// Progressive resistance past the first and last face: a hard stop reads as
    /// frozen, and a stack that followed the finger off its own end would be
    /// claiming there is another one. The curve is the platform's.
    static func resisted(_ over: CGFloat, over dimension: CGFloat, c: CGFloat = 0.55) -> CGFloat {
        // `dimension` is the asymptote — pull forever and the band gives exactly
        // this much. A tile is small, so it is passed a FRACTION of the height:
        // a band that could eventually expose a whole tile of empty glass is not
        // resistance, it is a second page that is not there.
        guard dimension > 0 else { return 0 }
        return (over * dimension * c) / (dimension + c * abs(over))
    }

    /// Which face is up. Vertical, because the faces are.
    ///
    /// ── THE RAIL RIDES IN THE GUTTER ────────────────────────────────────────
    /// Negative trailing padding pushes it off the face and into the tile's own
    /// 12 pt padding (`OnyxSpace.m`), where there is nothing to sit on top of. A
    /// 4 pt dot at the face's right edge lands squarely on the percentage column
    /// of the large Sleep face — the tiles ARE the widget faces, drawn to fill,
    /// so there is no margin inside them to borrow.
    ///
    /// Under the rotated `TabView` this overlay was aligned in the ROTATED
    /// view's coordinate space, and the rail did not appear on the tile at all:
    /// `today-edit.png` before this wave shows a two-face stack with no dots on
    /// it. The rail is not being moved here so much as arriving.
    private func dots(_ faces: [Face]) -> some View {
        VStack(spacing: 4) {
            ForEach(faces) { f in
                Circle()
                    .fill(f.index == face ? f.widget.domain.accent : Color.onyx.textTertiary)
                    .frame(width: 4, height: 4)
            }
        }
        // Centred in the 12 pt gutter: four points of air on either side of a
        // four-point dot, so the rail neither touches the numbers it sits beside
        // nor the glass edge it sits inside.
        .padding(.trailing, -(OnyxSpace.m - 4))
        .allowsHitTesting(false)
    }
}
