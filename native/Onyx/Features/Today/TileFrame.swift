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
/// the room.
///
/// ── THE JIGGLE, AND WHY IT IS A SPRING (W7) ──────────────────────────────────
/// It was ±0.8° on `.easeInOut(duration: 0.14)`. Two things were wrong with it.
/// The amplitude is under the Home Screen's, so the mode read as a shimmer
/// rather than as "these tiles are loose" — and `TileMenu` now takes the long
/// press, so the jiggle is the ONLY thing that says which mode you are in.
/// And an ease curve is symmetrical: every tile spent the same time at each
/// extreme and the grid breathed in unison however the phases were offset.
/// A spring overshoots and settles, so two tiles a fifth of a beat apart are
/// visibly out of step rather than merely delayed.
///
/// ±1.2°, and the phase offset window is the spring's own duration — a stagger
/// wider than one cycle wraps and is the same offset again.
///
/// ── AND WHAT `accessibilityReduceMotion` GETS INSTEAD ────────────────────────
/// Not "the badges and no jiggle", which is what it used to get: the badges are
/// 24 pt circles in the two corners and the tray appears below the fold, so a
/// reader who has turned motion off had no whole-screen signal that the grid was
/// live at all. A hairline in the tile's own accent, on every tile, says the
/// same thing the wobble says and says it without moving. Same message, same
/// moment, no vestibular cost — which is the substitution the setting asks for,
/// rather than the removal it is usually read as.
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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.onyxForcesReducedMotion) private var forcedReduceMotion

    /// ── WHY THERE ARE TWO ────────────────────────────────────────────────────
    /// `accessibilityReduceMotion` is READ-ONLY in `EnvironmentValues`, so the
    /// shot harness cannot set it and the still state could not be photographed
    /// — which is how a substitution nobody has ever seen ships broken. The
    /// simulator's own toggle is a `defaults write` and a respring, which is a
    /// per-screen dance `native-shot.sh` has no way to express.
    ///
    /// The override defaults to false and is written in exactly one place
    /// (`TodayPreviews`, `#if DEBUG`), so on a device this is the system value
    /// and nothing else. It ORs rather than replaces: a reader who has turned
    /// motion off must never have it turned back on by a flag.
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }

    // Computed, not stored: `TileFrame` is generic over its content and Swift
    // has no static STORED properties on a generic type. A separate namespace
    // would put the numbers somewhere the view that uses them is not.

    /// How far the tile leans, each way.
    static var tilt: Double { 1.2 }
    /// One half-cycle. Also the width of the per-tile phase offset — see the
    /// header for why it cannot usefully be wider.
    static var beat: TimeInterval { 0.2 }

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
            .overlay { if editing, reduceMotion { stillOutline } }
            .overlay(alignment: .topLeading) { if editing { removeBadge } }
            .overlay(alignment: .bottomTrailing) { if editing, sizes.count > 1 { resizeBadge } }
            .rotationEffect(.degrees(editing && !reduceMotion ? (wiggle ? Self.tilt : -Self.tilt) : 0))
            .animation(
                editing && !reduceMotion
                    ? .spring(duration: Self.beat, bounce: 0.35).repeatForever(autoreverses: true)
                    : .default,
                value: wiggle
            )
            .onChange(of: editing, initial: true) { _, on in
                // A different phase per tile, so the grid does not shiver in
                // lockstep. `stagger` is the slot id's hash and is already what
                // spreads the stacks' rotation; taking it modulo one half-cycle
                // spreads the wobble across the same beat.
                if on { Task { try? await Task.sleep(for: .milliseconds(SmartStackView.stagger(slot.id) % Int(Self.beat * 1000))); wiggle = true } }
                else { wiggle = false }
            }
            .sensoryFeedback(.selection, trigger: resizes)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Self.label(slot, up: up))
            .accessibilityHint(editing ? "Editing. Double-tap and hold to drag." : "Opens the sheet. Actions available.")
    }

    /// The jiggle's stand-in when motion is off — see the header.
    private var stillOutline: some View {
        RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous)
            .strokeBorder(up.domain.accent, lineWidth: 1)
            .accessibilityHidden(true)
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

/// The shot harness's stand-in for a setting SwiftUI will not let anything
/// write — see `TileFrame.reduceMotion`. False everywhere except one `#if
/// DEBUG` preview.
private struct OnyxForcesReducedMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var onyxForcesReducedMotion: Bool {
        get { self[OnyxForcesReducedMotionKey.self] }
        set { self[OnyxForcesReducedMotionKey.self] = newValue }
    }
}
