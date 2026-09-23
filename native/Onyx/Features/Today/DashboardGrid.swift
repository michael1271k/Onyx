import SwiftUI
import UniformTypeIdentifiers
import OnyxCore
import WidgetKit
import OnyxUI

/// The arrangeable grid.
///
/// ── TWO COLUMNS, THREE FAMILIES ──────────────────────────────────────────────
/// A small is one cell, a medium and a large span both — the WidgetKit
/// families at their own proportions, packed into rows by `rows(_:)`.
/// Placement is sequential like the web's CSS grid: a lone small followed by a
/// medium leaves its neighbour cell empty rather than pulling a later small up,
/// so a drag never reorders anything you did not drag.
///
/// ── DRAG IS THE SYSTEM'S ─────────────────────────────────────────────────────
/// `.draggable` / `.dropDestination`. The lift, the 1:1 tracking, the
/// interruptibility and the drop animation are UIKit's, which is what makes them
/// match every other app. Dropping on a tile moves the dragged slot to its
/// position; HOLDING over a same-size tile for a beat offers to stack instead,
/// and the tile says so by brightening. Both rules are `Dashboard.canStack`'s.
///
/// ── AND DRAG IS NO LONGER THE ONLY WAY IN (W2, D1) ───────────────────────────
/// That hold is 600 ms long, unannounced, and 500 ms of it silently gets you a
/// move instead. `TileMenu` says the same verbs in words on a long press, so
/// stacking is something you can READ rather than something you have to already
/// know. Both routes call `Dashboard.canStack`, so they cannot disagree.
struct DashboardGrid: View {
    @Bindable var model: TodayModel
    let onOpen: (WidgetId) -> Void

    @State private var mergeTarget: String?
    /// Slot id → the face that is up, for the stacks that have more than one.
    /// Held here rather than inside `SmartStackView` because the TAP is here.
    @State private var faces: [String: Int] = [:]
    @State private var hover: Task<Void, Never>?
    @State private var drops = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// §3.1: the grid gap is `s + 2`, tighter than the section gap around it —
    /// tiles in one grid are one object, and spacing them like separate cards is
    /// what made the web dashboard read as a page of boxes.
    static let gap: CGFloat = OnyxSpace.grid
    /// Hold over a same-size tile this long mid-drag before it offers to stack.
    static let mergeHold: Duration = .milliseconds(600)

    var body: some View {
        let phases = SmartStackView.phases(model.visibleSlots)
        return VStack(spacing: Self.gap) {
            ForEach(Self.rows(model.visibleSlots)) { row in
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(row.slots, id: \.id) { slot in tile(slot, phase: phases[slot.id] ?? 0) }
                    // A lone small keeps its neighbour cell empty — sequential
                    // placement, like the web's CSS grid, never pulls a later
                    // small up past a medium.
                    if row.slots.count == 1, Dashboard.heightTier(row.slots[0].size) == .s {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : OnyxMotion.move, value: model.layout)
        .sensoryFeedback(.selection, trigger: drops)
    }

    /// One grid row: two smalls, or one medium or large.
    struct Row: Identifiable {
        let slots: [StackSlot]
        var id: String { slots.map(\.id).joined(separator: "+") }
    }

    /// Sequential packing. Smalls pair up left to right; anything taller takes
    /// a row of its own, closing a half-filled small row above it.
    static func rows(_ slots: [StackSlot]) -> [Row] {
        var rows: [Row] = []
        var open: [StackSlot] = []
        for slot in slots {
            if Dashboard.heightTier(slot.size) == .s {
                open.append(slot)
                if open.count == 2 { rows.append(Row(slots: open)); open = [] }
            } else {
                if !open.isEmpty { rows.append(Row(slots: open)); open = [] }
                rows.append(Row(slots: [slot]))
            }
        }
        if !open.isEmpty { rows.append(Row(slots: open)) }
        return rows
    }

    /// The face that is UP in a slot — what a tap opens, and what the merge
    /// highlight wears. It used to be spelled out at the tap site and `items[0]`
    /// at the highlight, which is how a Sleep/Vitals stack could be showing
    /// Vitals and brighten in Sleep's green while a tile hovered over it.
    ///
    /// `min` because a face removed from a stack while it was the visible one
    /// leaves the index past the end until the next redraw.
    private func upIndex(_ slot: StackSlot) -> Int {
        min(faces[slot.id] ?? 0, max(0, slot.items.count - 1))
    }

    private func upFace(_ slot: StackSlot) -> WidgetId {
        slot.items[upIndex(slot)]
    }

    /// The menu's submenu: every tile this one can absorb, named by the face
    /// each is SHOWING. A stacked target says how deep it is, because "Sleep"
    /// and "Sleep + 2" are different things to drop a tile onto.
    private func candidates(_ slot: StackSlot) -> [StackCandidate] {
        model.stackTargets(slot.id).map { target in
            let up = upFace(target)
            return StackCandidate(
                id: target.id,
                title: target.items.count > 1 ? "\(up.title) + \(target.items.count - 1)" : up.title,
                symbol: up.symbol
            )
        }
    }

    @ViewBuilder
    private func tile(_ slot: StackSlot, phase: TimeInterval) -> some View {
        let tier = Dashboard.heightTier(slot.size)
        TileFrame(
            slot: slot, up: upFace(slot), editing: model.editing,
            onTap: {
                // A sideways swipe on a stack ends on the button's touch-up;
                // it paged the stack and must not also open a sheet.
                guard !model.touch.isSwipe() else { return }
                model.touch.stamp()
                if model.editing { if slot.items.count > 1 { model.sheet = .stack(slot.id) } }
                else { onOpen(upFace(slot)) }
            },
            onRemove: { model.remove(slot.id) },
            onResize: { model.resize(slot.id) }
        ) {
            if slot.items.count > 1 {
                SmartStackView(
                    slot: slot, entry: model.entry,
                    paused: model.editing || !model.isActive,
                    phase: phase,
                    face: Binding(
                        get: { min(faces[slot.id] ?? 0, max(0, slot.items.count - 1)) },
                        set: { faces[slot.id] = $0 }
                    ),
                    touch: model.touch
                )
            } else {
                OnyxTile.face(slot.items[0], entry: model.entry)
            }
        }
        // A slot that stops being a stack forgets which face was up. Otherwise:
        // swipe a Sleep/Water stack to Water, unstack Water, then stack Vitals
        // onto the same tile — and it opens on Vitals, because the remembered 1
        // is still there and `SmartStackView` is gone, so its own re-point never
        // ran. It also keeps this dictionary from growing a row per deleted slot.
        .onChange(of: slot.items.count, initial: true) { _, n in
            if n < 2, faces[slot.id] != nil { faces[slot.id] = nil }
        }
        .aspectRatio(tier == .s ? 1 : tier == .m ? 338 / 158 : 338 / 354, contentMode: .fit)
        .overlay {
            if mergeTarget == slot.id {
                RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous)
                    .strokeBorder(upFace(slot).domain.accent, lineWidth: 2)
            }
        }
        .modifier(Arrangeable(
            enabled: model.editing, id: slot.id,
            onDrop: { dragged in drop(dragged, on: slot.id) },
            onTargeted: { targeted in hovered(slot.id, targeted) }
        ))
        .modifier(TileMenu(
            // Never in edit mode: `Arrangeable`'s `.draggable` needs the long
            // press to lift a tile, and a context menu there eats the drag —
            // which would trade D1 for a worse defect.
            enabled: !model.editing,
            up: upFace(slot),
            isStack: slot.items.count > 1,
            candidates: candidates(slot),
            onStack: { model.stack($0, onto: slot.id) },
            onUnstack: { model.unstackVisible(slot.id, visibleIndex: upIndex(slot)) },
            onNextFace: {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : OnyxMotion.flick) {
                    faces[slot.id] = (upIndex(slot) + 1) % slot.items.count
                }
            },
            onEditStack: { model.sheet = .stack(slot.id) },
            onEdit: { withAnimation(OnyxMotion.flick) { model.editing = true } }
        ))
    }

    private func hovered(_ slotId: String, _ targeted: Bool) {
        hover?.cancel()
        guard targeted else { if mergeTarget == slotId { mergeTarget = nil }; return }
        hover = Task {
            try? await Task.sleep(for: Self.mergeHold)
            guard !Task.isCancelled else { return }
            mergeTarget = slotId
        }
    }

    private func drop(_ dragged: String, on target: String) {
        hover?.cancel()
        defer { mergeTarget = nil; drops += 1 }
        guard dragged != target else { return }
        if mergeTarget == target, model.canStack(dragged, onto: target) {
            model.stack(dragged, onto: target)
        } else {
            model.move(dragged, to: target)
        }
    }
}

/// One row of the long-press menu's stack submenu: a tile this one can absorb,
/// named by the face it is currently showing.
struct StackCandidate: Identifiable {
    /// The slot id, which is what `Dashboard.stackSlots` is addressed by.
    let id: String
    let title: String
    let symbol: String
}

/// The long press, outside edit mode — the fix for D1.
///
/// ── WHAT A PRESS USED TO MEAN, AND WHAT IT MEANS NOW ─────────────────────────
/// It meant "start jiggling", and that was the only thing it could mean. So the
/// only route to a stack ran through a mode the user had to already be in, by a
/// drag-and-hold nothing on screen mentions. Now the press says the verbs.
///
/// ── THE DIRECTION, WHICH DECIDES EVERY STRING BELOW ──────────────────────────
/// The tile you pressed is the one that STAYS: `stackSlots` puts the dragged
/// slot's faces UNDER the target's, so picking Sleep from Vitals' menu leaves
/// Vitals where it is, showing Vitals, with Sleep behind it. "Stack With ▸
/// Sleep" reads correctly only that way round — the other direction would need
/// "Move Into", and a menu whose tile disappears when you use it is a menu
/// people stop using.
///
/// Order is the Home Screen's: the widget's own verbs, then the row that leaves
/// the tile alone and edits the container. `Edit Dashboard` is deliberately not
/// at the top, where a mis-tap would start the jiggle the user came here to
/// avoid.
private struct TileMenu: ViewModifier {
    let enabled: Bool
    let up: WidgetId
    let isStack: Bool
    let candidates: [StackCandidate]
    let onStack: (String) -> Void
    let onUnstack: () -> Void
    /// Turning the stack over by hand, for VoiceOver. It lives here rather than
    /// on `SmartStackView` because `TileFrame` is an
    /// `.accessibilityElement(children: .contain)`: an action added INSIDE that
    /// container is not reachable from the element the rotor lands on, so the
    /// action the carousel added to itself could not be performed.
    let onNextFace: () -> Void
    let onEditStack: () -> Void
    let onEdit: () -> Void

    /// VoiceOver's rotor cannot open a submenu, so the eligible targets are
    /// flattened into actions of their own — capped, because a grid of twelve
    /// smalls would otherwise read eleven near-identical rows before reaching
    /// anything else.
    static let spokenTargets = 6

    func body(content: Content) -> some View {
        if enabled {
            content
                .contextMenu { menu }
                .accessibilityActions {
                    ForEach(candidates.prefix(Self.spokenTargets)) { target in
                        Button("Stack with \(target.title)") { onStack(target.id) }
                    }
                    if isStack {
                        // The swipe has no VoiceOver equivalent of its own — the
                        // rotated `TabView` inherited one from UIKit's page
                        // controller and a `ZStack` inherits nothing.
                        Button("Next widget in stack") { onNextFace() }
                        Button("Unstack \(up.title)") { onUnstack() }
                        Button("Edit Stack") { onEditStack() }
                    }
                    Button("Edit Dashboard") { onEdit() }
                }
        } else {
            content
        }
    }

    @ViewBuilder
    private var menu: some View {
        Section {
            if candidates.isEmpty {
                // Shown, not hidden. A feature that vanishes when it is
                // unavailable is a feature nobody learns exists — which is the
                // defect this menu is here to fix. The row states the rule.
                Button {} label: {
                    Label("No Same-Size Widget to Stack With", systemImage: "rectangle.stack.badge.plus")
                }
                .disabled(true)
            } else {
                Menu {
                    ForEach(candidates) { target in
                        Button { onStack(target.id) } label: {
                            Label(target.title, systemImage: target.symbol)
                        }
                    }
                } label: {
                    Label(
                        isStack ? "Add to Stack" : "Stack With",
                        systemImage: isStack ? "rectangle.stack.badge.plus" : "rectangle.stack"
                    )
                }
            }
            if isStack {
                Button { onUnstack() } label: {
                    // The face that is UP, named. "Unstack this face" asks the
                    // user to know a word the app never taught them.
                    Label("Unstack \(up.title)", systemImage: "rectangle.stack.badge.minus")
                }
                Button { onEditStack() } label: {
                    // That sheet was reachable only by tapping a stack while
                    // already jiggling — a sibling of D1, fixed by one row.
                    Label("Edit Stack", systemImage: "pencil")
                }
            }
        }
        Section {
            Button { onEdit() } label: {
                Label("Edit Dashboard", systemImage: "square.grid.2x2")
            }
        }
    }
}

/// The tray: every drawable widget that is not on the grid, as chips.
struct WidgetGallery: View {
    let model: TodayModel

    var body: some View {
        if !model.gallery.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Not on the grid · \(model.gallery.count)")
                    .onyxType(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color.onyx.textSecondary)
                FlowLayout(spacing: 8) {
                    ForEach(model.gallery, id: \.self) { id in
                        Button { model.add(id) } label: {
                            Label(id.title, systemImage: id.symbol)
                                .onyxType(.secondary).fontWeight(.semibold)
                                .foregroundStyle(Color.onyx.textPrimary)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .onyxGlass(.row)
                        }
                        .buttonStyle(OnyxPressStyle())
                        .accessibilityHint("Adds \(id.title) to the grid")
                    }
                }
            }
            .padding(.top, 4)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

/// Chips that wrap. `Layout` in twenty lines; a `LazyVGrid` would force the
/// chips onto a column grid they have no reason to align to.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        place(in: proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, point) in zip(subviews, place(in: bounds.width, subviews).points) {
            view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func place(in width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (points, CGSize(width: maxX, height: y + rowHeight))
    }
}
