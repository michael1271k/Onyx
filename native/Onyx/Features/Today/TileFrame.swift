import SwiftUI
import OnyxCore
import WidgetKit
import OnyxUI

/// One slot's chrome: the glass, the edit badges and the jiggle.
///
/// ── WHAT EDIT MODE PUTS ON A TILE ────────────────────────────────────────────
/// The iOS grammar and nothing else: a minus at the top-left removes, the size
/// letter at the bottom-right steps through the sizes every face in the slot
/// can draw, and the whole tile jiggles so the mode is unmistakable from across
/// the room. `accessibilityReduceMotion` keeps the badges and drops the jiggle.
///
/// ── THE LONG PRESS BELONGS TO THE MENU NOW (W2, D1) ──────────────────────────
/// It used to be `onLongPressGesture(0.45)`, whose only act was to start the
/// jiggle. That made edit mode the one thing a press could mean, and stacking —
/// which is only reachable from inside edit mode, by dragging a tile onto a
/// same-size neighbour and HOLDING there for 600 ms — unguessable.
///
/// `TileMenu` (`DashboardGrid.swift`) takes the press instead and says the
/// words. Edit mode is still one gesture away, now as a named row rather than a
/// mode that arrives unannounced. The two cannot both own the press:
/// `.contextMenu` installs its own recogniser, so leaving the old one attached
/// started the jiggle BEHIND the menu.
struct TileFrame<Content: View>: View {
    let slot: StackSlot
    /// The face that is up. VoiceOver reads it first — a stack that announces
    /// "Sleep, Vitals" tells a user who cannot see it everything except the one
    /// thing the tile is currently saying, and "Unstack Sleep" in the menu is
    /// then unverifiable by ear.
    let up: WidgetId
    let editing: Bool
    let onTap: () -> Void
    let onRemove: () -> Void
    let onResize: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var wiggle = false
    @State private var resizes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sizes: [WidgetSize] { Dashboard.sizesFor(slot.items) }

    /// A single tile is its name. A stack leads with the face that is up and
    /// then says how deep it goes, rather than reading a list in which nothing
    /// marks which one is on screen.
    static func label(_ slot: StackSlot, up: WidgetId) -> String {
        slot.items.count > 1 ? "\(up.title). Stack of \(slot.items.count)." : up.title
    }

    var body: some View {
        content()
            .environment(\.onyxTileFamily, slot.size.family)
            .padding(OnyxSpace.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onyxGlass(.tile)
            .contentShape(RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous))
            .onTapGesture { onTap() }
            .overlay(alignment: .topLeading) { if editing { removeBadge } }
            .overlay(alignment: .bottomTrailing) { if editing, sizes.count > 1 { resizeBadge } }
            .rotationEffect(.degrees(editing && !reduceMotion ? (wiggle ? 0.8 : -0.8) : 0))
            .animation(editing && !reduceMotion ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true) : .default, value: wiggle)
            .onChange(of: editing, initial: true) { _, on in
                // A slightly different phase per tile, so the grid does not
                // shiver in lockstep.
                if on { Task { try? await Task.sleep(for: .milliseconds(SmartStackView.stagger(slot.id) % 140)); wiggle = true } }
                else { wiggle = false }
            }
            .sensoryFeedback(.selection, trigger: resizes)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Self.label(slot, up: up))
            .accessibilityHint(editing ? "Editing. Double-tap and hold to drag." : "Opens the sheet. Actions available.")
    }

    private var removeBadge: some View {
        Button(action: onRemove) {
            Image(systemName: "minus")
                .onyxType(.caption).fontWeight(.heavy)
                // 24 pt badges on the tile's corner; the label carries the
                // meaning for VoiceOver, so the glyph does not scale with it.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(Color.onyx.textPrimary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(Color.onyx.hairline, lineWidth: 0.5))
        }
        .buttonStyle(OnyxPressStyle(scale: 0.9))
        .offset(x: -6, y: -6)
        .accessibilityLabel("Remove \(slot.items.map(\.title).joined(separator: ", "))")
    }

    private var resizeBadge: some View {
        Button { resizes += 1; onResize() } label: {
            Text(slot.size.rawValue.uppercased())
                .onyxType(.micro).fontWeight(.heavy)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(Color.onyx.textPrimary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(Color.onyx.hairline, lineWidth: 0.5))
        }
        .buttonStyle(OnyxPressStyle(scale: 0.9))
        .offset(x: 6, y: 6)
        .accessibilityLabel("Resize, currently \(slot.size.rawValue.uppercased())")
    }
}
