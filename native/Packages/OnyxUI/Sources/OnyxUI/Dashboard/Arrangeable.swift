#if os(iOS)
import SwiftUI

// `#if os(iOS)` like every tile file: `.draggable` and `.dropDestination`
// do not exist on watchOS, and nothing there has a grid to arrange.
//
// The two modifiers an editable grid wears, shared by the Today tab's tiles and
// the Pulse tab's squares (W9). Extracted from `DashboardGrid` and `TileFrame`
// unchanged in behaviour; the headers there say why each number is what it is.

/// `.draggable` and `.dropDestination`, only while editing — a tile you can
/// lift while reading is a tile you will lift by accident while scrolling.
///
/// The lift, the 1:1 tracking, the interruptibility and the drop animation are
/// UIKit's, which is what makes them match every other app. `id` is what a
/// drop hands to `onDrop`: the dragged item's id, for the caller to move.
public struct Arrangeable: ViewModifier {
    let enabled: Bool
    let id: String
    let onDrop: (String) -> Void
    let onTargeted: (Bool) -> Void

    public init(enabled: Bool, id: String, onDrop: @escaping (String) -> Void,
                onTargeted: @escaping (Bool) -> Void = { _ in }) {
        self.enabled = enabled
        self.id = id
        self.onDrop = onDrop
        self.onTargeted = onTargeted
    }

    public func body(content: Content) -> some View {
        if enabled {
            content
                .draggable(id) {
                    // The lifted preview is the tile's own outline, not a
                    // screenshot of a jiggling view mid-tilt.
                    RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 120, height: 120)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let dragged = items.first else { return false }
                    onDrop(dragged)
                    return true
                } isTargeted: { onTargeted($0) }
        } else {
            content
        }
    }
}

/// The edit-mode wobble: the Home Screen's own ±1.1°, a sub-point slide so the
/// tile reads as loose in its slot rather than hinged, and a per-tile rate and
/// phase from `seed`'s hash so a grid never shivers in lockstep.
///
/// Off — no movement at all — for a reader who has turned motion off; the
/// caller draws its own still stand-in (`TileFrame`'s hairline) off the same
/// two flags via `Jiggle.reduced(_:)`.
public struct Jiggle: ViewModifier {
    let on: Bool
    let seed: String

    @State private var wiggle = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.onyxForcesReducedMotion) private var forcedReduceMotion

    public init(on: Bool, seed: String) {
        self.on = on
        self.seed = seed
    }

    /// How far the tile leans, each way.
    public static var tilt: Double { 1.1 }
    /// The NOMINAL half-cycle; every tile runs at its own rate around it.
    public static var beat: TimeInterval { 0.2 }
    /// How far the tile slides as it leans. Sub-point on purpose.
    public static var drift: CGFloat { 0.6 }
    /// The window the stacks' rotation phase is spread over, in ms; the hash
    /// below is taken modulo it so one number serves both spreads.
    public static var staggerWindowMs: Int { 7_000 }

    /// A stable per-seed number in `0..<staggerWindowMs`. `h = h * 31 + c`.
    public static func stagger(_ seed: String) -> Int {
        var h: Int32 = 0
        for unit in seed.utf16 { h = h &* 31 &+ Int32(unit) }
        return Int(abs(Int(h))) % staggerWindowMs
    }

    /// This seed's own half-cycle: `beat` ±10%.
    public static func beat(_ seed: String) -> TimeInterval {
        beat * (0.9 + Double(stagger(seed) % 21) / 100)
    }

    /// Which way this seed slides. Bit four of the hash, not the low bit —
    /// 31 is odd, so the hash's parity is the parity of the character sum and
    /// `sl-` ids collide on it constantly.
    public static func driftSign(_ seed: String) -> CGFloat {
        (stagger(seed) >> 4) & 1 == 0 ? 1 : -1
    }

    private var wobbling: Bool { on && !(systemReduceMotion || forcedReduceMotion) }
    private var beat: TimeInterval { Self.beat(seed) }
    private var driftSign: CGFloat { Self.driftSign(seed) }

    public func body(content: Content) -> some View {
        content
            // ── SCOPED TO THE LEAN AND THE SLIDE, AND NOTHING INSIDE (W9) ───
            // `.animation(_:value:)` would hand this repeat-forever spring to
            // every change in the subtree that lands in the same transaction
            // as the flip — and a face whose data arrives in that instant
            // swaps its empty state for its reading under an animation that
            // never ends. The Pulse edit shot photographed exactly that: "Not
            // reported" frozen over the readings. `animation(_:body:)` applies
            // the spring to these two modifiers only.
            .animation(
                wobbling
                    ? .spring(duration: beat, bounce: 0.35).repeatForever(autoreverses: true)
                    : .default
            ) { view in
                view
                    .rotationEffect(.degrees(wobbling ? (wiggle ? Self.tilt : -Self.tilt) : 0))
                    .offset(
                        x: wobbling ? (wiggle ? Self.drift : -Self.drift) * driftSign : 0,
                        y: wobbling ? (wiggle ? -Self.drift : Self.drift) * driftSign : 0
                    )
            }
            .onChange(of: on, initial: true) { _, on in
                // A different phase per tile, modulo THIS tile's half-cycle.
                if on { Task { try? await Task.sleep(for: .milliseconds(Self.stagger(seed) % Int(beat * 1000))); wiggle = true } }
                else { wiggle = false }
            }
    }
}

/// The shot harness's stand-in for a setting SwiftUI will not let anything
/// write: `accessibilityReduceMotion` is read-only in `EnvironmentValues`, so
/// the still state could not be photographed. False everywhere except one
/// `#if DEBUG` preview; it ORs with the system value and never replaces it.
private struct OnyxForcesReducedMotionKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var onyxForcesReducedMotion: Bool {
        get { self[OnyxForcesReducedMotionKey.self] }
        set { self[OnyxForcesReducedMotionKey.self] = newValue }
    }
}
#endif
