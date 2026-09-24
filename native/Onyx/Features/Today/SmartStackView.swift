import SwiftUI
import OnyxCore
import OnyxUI

/// The faces of one slot, and the two ways they turn over.
///
/// ── A STACK ROTATES, AND IT ALSO OBEYS A FINGER ──────────────────────────────
/// Left alone, a stack shows each face for nine seconds — slow enough never to
/// flip while a number is being read, quick enough that a tile reads as having
/// another side. A SIDEWAYS swipe steps through by hand, and so does a tap on
/// the page dots; after either the clock holds for a full period. No stack
/// turns over within `GridTouch.hold` of a touch anywhere on the grid.
///
/// ── EVERY STACK HAS ITS OWN PHASE (overhaul B1, decision Q10) ────────────────
/// The phase used to be a hash of the slot id modulo seven seconds — two
/// stacks could share it, and the last two seconds of the period were never
/// used. A `linked` stack dropped it altogether, so connected stacks turned
/// over together, which is what the founder reported as "all the widgets
/// scroll at once". `phases(_:)` now spreads the grid's stacks EVENLY over the
/// whole period in layout order: distinct by construction, and as far apart as
/// the count allows. `linked` no longer touches the beat.
///
/// ── THE BEATS ARE ABSOLUTE, NOT A COUNTDOWN (W2, D3) ─────────────────────────
/// `untilNextBeat` makes the beats a property of the CLOCK rather than of the
/// task: every multiple of `period` since 1970, shifted by the slot's phase. A
/// stack coming back from the background rejoins the beat it would have been
/// on had it never stopped, so the wait is never more than one period.
///
/// ── PAGING IS SIDEWAYS, ORTHOGONAL TO THE PAGE (overhaul B1, Q9) ─────────────
/// It was vertical, on the same axis as the Today `ScrollView`, so the stack
/// had to LATCH the page's scroll off (`scrollDisabled`) to own a drag — and a
/// scroll that started on a stacked tile paged the stack instead. Sideways
/// there is nothing to fight: a vertical drag is always the page's, a sideways
/// one is always the stack's, and the page never needs switching off.
///
/// The drag stays `.simultaneousGesture`: a plain `.gesture` beats an enclosing
/// `ScrollView`'s pan from touch-down and would make every stacked tile a dead
/// patch you cannot scroll the dashboard by (`AtlasSheet.swift:257`).
struct SmartStackView: View {
    let slot: StackSlot
    let entry: OnyxTileEntry
    let paused: Bool
    /// This slot's offset into the period, in seconds — see `phases(_:)`.
    let phase: TimeInterval
    /// Which face is up, owned by the GRID so the tile's tap opens the face on
    /// screen and not `items.first`.
    @Binding var face: Int
    /// The grid's touch clock: read at every beat, written by every swipe.
    let touch: GridTouch

    @State private var touchedAt = Date.distantPast
    @State private var byClock = false
    @State private var drag: CGFloat = 0
    /// The translation at the moment of takeover, so the points the finger
    /// spent before the stack claimed it are not spent again on the faces.
    @State private var origin: CGFloat?
    /// Which gesture `origin` belongs to — the touch-down point. A CANCELLED
    /// drag never reaches `onEnded` and would leave its origin behind.
    @State private var startedAt: CGPoint?
    /// Up for the length of a claimed drag. `@GestureState` because it cannot
    /// be allowed to stick when a drag is cancelled out from under the view.
    @GestureState private var held = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One face, nine seconds.
    static let period: TimeInterval = 9
    /// A tile never turns over in the blink the grid came back in.
    static let grace: TimeInterval = 2
    /// How far the finger travels before the stack claims the drag.
    static let takeover: CGFloat = 10
    /// How much more sideways than vertical a drag has to be to be this view's.
    /// 1.5 so a thumb's diagonal still pages, while a drag that is mostly down
    /// the screen is left to the page scroll.
    static let axis: CGFloat = 1.5
    /// Heading past this much of a face once the throw is projected, the swipe
    /// commits to the next one.
    static let commit: CGFloat = 1.0 / 3.0
    /// Past this much of a face with the throw spent, it commits anyway — a
    /// finger that drags most of the way, stops to look and lifts gets the
    /// face it dragged in, not the one it started on.
    static let hold: CGFloat = 0.25

    /// Which face the swipe committed to, relative to the one up: -1, 0 or +1.
    /// Both measurements are in finger units from the takeover point.
    static func step(travelled: CGFloat, projected: CGFloat, over w: CGFloat) -> Int {
        // The throw, OR a drag that went far enough and stopped (see `hold`).
        // The sign test stops a face pulled one way and flicked back at release
        // from paging away from the finger's own offset.
        let far = abs(projected) > w * commit
            || (abs(travelled) > w * hold && travelled * projected > 0)
        guard far else { return 0 }
        return projected < 0 ? 1 : -1
    }

    /// Is this drag the stack's? Far enough, and meaningfully more sideways
    /// than it is vertical. One predicate because the test is made twice.
    static func takes(_ translation: CGSize) -> Bool {
        abs(translation.width) >= takeover && abs(translation.width) > abs(translation.height) * axis
    }

    /// Each rotating stack's phase, spread evenly over the whole period in
    /// layout order. Single tiles do not rotate and take no share.
    static func phases(_ slots: [StackSlot]) -> [String: TimeInterval] {
        let stacks = slots.filter { $0.items.count > 1 }
        let n = Double(max(1, stacks.count))
        return Dictionary(
            stacks.enumerated().map { ($1.id, period * Double($0) / n) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Seconds until this slot's next beat — see the header.
    ///
    /// Wall-clock, not `ContinuousClock`: the phase has to mean the same thing
    /// across a relaunch, and a monotonic clock's zero is the last boot. The
    /// floor is the one concession: a beat already due would flip the tile in
    /// the same blink it came back, so `grace` pushes exactly one flip off it.
    static func untilNextBeat(now: Date = .now, phase: TimeInterval) -> TimeInterval {
        let since = now.timeIntervalSince1970 - phase
        // `truncatingRemainder` takes the sign of the DIVIDEND.
        let r = since.truncatingRemainder(dividingBy: period)
        return max(period - (r < 0 ? r + period : r), grace)
    }

    /// One face, with an identity that survives a reorder: `items` may repeat
    /// a widget, and an index moves under `reorderFace`. The occurrence key is
    /// unique AND follows its widget (W2, D4).
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
    /// `items`. Falls back to a clamp when the face that was up has left.
    static func follow(_ face: Int, from old: [WidgetId], to new: [WidgetId]) -> Int {
        let clamped = min(max(face, 0), max(0, new.count - 1))
        let was = faces(old)
        guard was.indices.contains(face) else { return clamped }
        return faces(new).first { $0.id == was[face].id }?.index ?? clamped
    }

    private var rotating: Bool { slot.items.count > 1 && !paused }

    private var turn: Animation { reduceMotion ? .easeInOut(duration: 0.2) : OnyxMotion.flick }

    var body: some View {
        let faces = Self.faces(slot.items)
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                ForEach(faces) { f in
                    OnyxTile.face(f.widget, entry: entry)
                        .frame(width: w, height: h)
                        // `.clipped()` clips drawing, not the accessibility
                        // tree: without this VoiceOver reads every face.
                        .accessibilityHidden(f.index != face)
                        // Every face clips to its own page — a face taller
                        // than the tile overflows its frame and bled into the
                        // one on screen.
                        .clipped()
                        .offset(x: CGFloat(f.index - face) * w + drag)
                }
            }
            .frame(width: w, height: h)
            .clipped()
            .contentShape(.rect)
            .simultaneousGesture(page(w))
            .overlay(alignment: .bottom) { dots(faces) }
        }
        .onChange(of: held) { _, on in
            guard !on else { return }
            // A cancelled gesture never reaches `onEnded`; this always runs.
            if touch.swiping == slot.id { touch.swipe(slot.id, false) }
            if drag != 0 { withAnimation(turn) { drag = 0 } }
        }
        .onChange(of: face) { _, _ in
            if byClock { byClock = false } else { touchedAt = .now }
        }
        .onChange(of: slot.items) { old, new in
            let next = Self.follow(face, from: old, to: new)
            // Sorting the stack in Edit Stack is not a swipe; do not trip the
            // hold-off.
            if next != face { byClock = true }
            face = next
        }
        // The id carries the COUNT (the task captured `slot`) and the phase (a
        // layout change re-spreads the grid, and a stack must re-phase now,
        // not at its old beat).
        .task(id: rotating ? "\(slot.items.count)@\(phase)" : "off") {
            guard rotating else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.untilNextBeat(phase: phase)))
                guard !Task.isCancelled else { return }
                guard Date.now.timeIntervalSince(touchedAt) >= Self.period, touch.quiet() else { continue }
                byClock = true
                withAnimation(turn) { face = (face + 1) % max(1, slot.items.count) }
            }
        }
    }

    /// 1:1 with the finger while it is down, thrown where UIKit says it is
    /// going when it leaves.
    private func page(_ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: Self.takeover)
            .updating($held) { value, held, _ in
                held = held || Self.takes(value.translation)
            }
            .onChanged { value in
                if startedAt != value.startLocation {
                    startedAt = value.startLocation
                    origin = nil
                }
                guard Self.takes(value.translation) || origin != nil else { return }
                let from = origin ?? value.translation.width
                if origin == nil { origin = from; touch.swipe(slot.id, true) }
                touchedAt = .now
                let d = value.translation.width - from
                // One page of travel each way, and only where there is a face
                // to travel to; past that the drag is resisted, not stopped.
                let right = face > 0 ? w : 0
                let left = face < slot.items.count - 1 ? -w : 0
                let inside = min(max(d, left), right)
                drag = inside + Self.resisted(d - inside, over: w * 0.6)
            }
            .onEnded { value in
                defer { origin = nil; startedAt = nil }
                // A nil `origin` is exactly "this drag was never the stack's":
                // without the guard a refused drag paged from zero on release.
                guard let from = origin else { return }
                let step = Self.step(
                    travelled: value.translation.width - from,
                    projected: value.predictedEndTranslation.width - from,
                    over: w
                )
                // Load-bearing: a hard throw past the last face projects past
                // the commit threshold, and this clamp stops it stepping off.
                let next = min(max(face + step, 0), slot.items.count - 1)
                touchedAt = .now
                touch.swipe(slot.id, false)
                withAnimation(turn) {
                    face = next
                    drag = 0
                }
            }
    }

    /// Progressive resistance past the first and last face. `dimension` is the
    /// asymptote — pull forever and the band gives exactly this much.
    static func resisted(_ over: CGFloat, over dimension: CGFloat, c: CGFloat = 0.55) -> CGFloat {
        guard dimension > 0 else { return 0 }
        return (over * dimension * c) / (dimension + c * abs(over))
    }

    /// Which face is up, sideways because the faces are — and a tap target:
    /// each dot raises its face. It rides in the tile's bottom gutter (the
    /// 12 pt `OnyxSpace.m` padding), where there is nothing to sit on; the
    /// hit strip is taller than the dot and reaches up into the face.
    private func dots(_ faces: [Face]) -> some View {
        HStack(spacing: 0) {
            ForEach(faces) { f in
                Button {
                    touch.stamp()
                    withAnimation(turn) { face = f.index }
                } label: {
                    Circle()
                        .fill(f.index == face ? f.widget.domain.accent : Color.onyx.textTertiary)
                        .frame(width: 5, height: 5)
                        .frame(width: 16, height: Self.dotStrip)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        // Centre the dot in the gutter: the strip's bottom sits at the face's
        // bottom edge, so drop it by half the strip plus half the gutter.
        .offset(y: Self.dotStrip / 2 + OnyxSpace.m / 2)
        // VoiceOver has "Next widget in stack" as a named action on the tile.
        .accessibilityHidden(true)
    }

    static let dotStrip: CGFloat = 20
}
