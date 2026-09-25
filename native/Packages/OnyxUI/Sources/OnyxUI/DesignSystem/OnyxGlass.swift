import SwiftUI

/// Obsidian Glass — the one modifier that owns depth.
///
/// ── MATERIAL, NOT PAINT ─────────────────────────────────────────────────────
/// Hierarchy on this app is material WEIGHT, not border lines and not lighter
/// greys. A row is thinner than the tile it sits in; a sheet is thicker than the
/// screen behind it; navigation chrome is thicker still. That ordering is what
/// tells you which layer you are on, and it survives Dynamic Type, dark rooms
/// and the colour-blind — none of which a 1 px border does.
///
/// ── AND WHY IT IS ONE MODIFIER ──────────────────────────────────────────────
/// If the deployment target ever rises to iOS 26, `glassEffect` replaces the
/// BODY of this modifier and nothing else in the app moves. Every screen that
/// spelled out its own `.background(.ultraThinMaterial)` would be a separate
/// edit, and the ones that got missed would be the bug.
public enum GlassLevel: Sendable {
    /// A row inside a tile. Thinnest, no border, no shadow — it is already
    /// inside something.
    case row
    /// A tile on a screen.
    case tile
    /// A presented sheet.
    case sheet
    /// Navigation chrome: a bar, a toolbar, a floating control.
    case chrome

    public var material: Material {
        switch self {
        // Stone (overhaul B3, challenge C1): the frost under every slab.
        case .row, .tile, .sheet: .thinMaterial
        case .chrome:     .regularMaterial
        }
    }

    public var radius: CGFloat {
        switch self {
        case .row:    OnyxCorner.row
        case .tile:   OnyxCorner.tile
        case .sheet:  OnyxCorner.sheet
        case .chrome: 0
        }
    }

    /// A hairline only where content meets chrome — a tile's own edge is drawn
    /// by the material, and outlining it as well reads as a box around a box.
    public var drawsHairline: Bool {
        switch self {
        case .tile, .sheet, .chrome: true
        case .row: false
        }
    }

    /// Large, soft and dark. Shadows separate a floating surface from busy
    /// content; a row that is flush with its container is not floating and gets
    /// none, because a shadow under something that has not lifted is just dirt.
    public var shadow: (radius: CGFloat, y: CGFloat)? {
        switch self {
        // Stone has no drop shadows: depth is the lit edge and the radius.
        case .row, .tile, .sheet, .chrome: nil
        }
    }
}

/// Reduce Transparency, forced (Precision B3) — the shot harness's `rt-`
/// screens. `accessibilityReduceTransparency` is read-only in
/// `EnvironmentValues` (the same wall `onyxForcesReducedMotion` works around),
/// so the slab and the ground OR this with the system value. False outside
/// the harness.
private struct OnyxForcesReducedTransparencyKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var onyxForcesReducedTransparency: Bool {
        get { self[OnyxForcesReducedTransparencyKey.self] }
        set { self[OnyxForcesReducedTransparencyKey.self] = newValue }
    }
}

private struct OnyxGlassModifier: ViewModifier {
    let level: GlassLevel

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.onyxForcesReducedTransparency) private var forcedReduceTransparency
    private var reduceTransparency: Bool { systemReduceTransparency || forcedReduceTransparency }

    // ── STONE (overhaul B3, concept 1 + challenge C1) ───────────────────────
    // Every level is one slab: `.thinMaterial` so what scrolls behind frosts,
    // the near-black `slab` over it at `slabTint` so the card is onyx and not
    // grey glass (which is also what holds text contrast over the frost), one
    // lit top edge, and no drop shadow. Reduce Transparency draws the slab
    // solid. The call sites never changed — `.onyxGlass(_:)` is the door.
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: level.radius, style: .continuous)
        return content
            .background {
                if reduceTransparency {
                    shape.fill(Color.onyx.slab)
                } else {
                    shape.fill(level.material)
                    shape.fill(Color.onyx.slab.opacity(Color.onyx.slabTint))
                }
            }
            .overlay {
                if level.drawsHairline {
                    // One pixel of light on the top edge, fading down the
                    // sides into the hairline weight — the icon's bevel.
                    shape.strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.12), location: 0),
                                .init(color: .white.opacity(0.04), location: 0.3),
                                .init(color: .white.opacity(0.04), location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
            }
            .clipShape(shape)
    }
}

public extension View {
    /// The app's only depth primitive.
    ///
    /// Never stack two of these directly: `.tile` inside `.tile` puts one light
    /// translucent surface on another and both stop reading as glass. A row
    /// inside a tile is `.row`, which is the whole reason the level exists.
    func onyxGlass(_ level: GlassLevel = .tile) -> some View {
        modifier(OnyxGlassModifier(level: level))
    }
}

// MARK: - The screen ground

/// How lit the ground is allowed to be, 0…1 — the device's battery.
///
/// ── WHY A BACKGROUND WATCHES THE BATTERY ────────────────────────────────────
/// The ground's light is the one thing on this app that is pure decoration: it says
/// which domain you are in, and nothing else. On an OLED panel it is also the
/// only thing that is not black, which means it is the only thing costing
/// power on a screen that is otherwise free to draw. So it is the first thing
/// to go quiet when the phone is running out — the same trade every part of
/// this app makes, stated once here rather than argued at each screen.
///
/// It defaults to 1 so a widget, a preview and the shot loop all draw the mesh
/// at full strength: a screenshot whose look depends on the simulator's battery
/// is a visual diff that fails for no reason.
private struct OnyxBatteryLevelKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

public extension EnvironmentValues {
    var onyxBatteryLevel: Double {
        get { self[OnyxBatteryLevelKey.self] }
        set { self[OnyxBatteryLevelKey.self] = newValue }
    }
}

/// Black, lit from two corners by the stone (Precision B3, decision Q20 ·
/// design 7 "Stone light gradient").
///
/// ── WHY THE MESH WENT ───────────────────────────────────────────────────────
/// The 3 × 3 mesh bled the domain's two stops across the top 280 pt at 10 %,
/// then went black: a band behind the title and dead black under it, which is
/// what the founder called "flat black". The ground is now two radials that
/// reach the whole screen (peaks: `OnyxTheme.groundPeak`): the domain's accent from just
/// off the top-left corner (radius 70 % of the height) and the theme's
/// secondary from just off the bottom-right (55 %). Light falls across the
/// stone rather than sitting on its head. REPLACED, not stacked — a mesh under
/// two radials is three light sources and a muddy middle.
///
/// ── WHAT IS HELD ────────────────────────────────────────────────────────────
/// Both hues are clamped to chroma 0.10 (`OnyxTheme.groundHex`); the brightest
/// point of the ground stays under OKLab L 0.35 and `textSecondary` over it
/// stays ≥ 4.5 : 1 for all eight stones × four domains
/// (`TokenDisciplineTests`). The theme's phase mood (`reacting(to:)`) reaches
/// the ground on its own — `current.spec` is the reacted spec.
///
/// Reduce Transparency draws flat black: a lit ground under glass is the thing
/// that setting exists to switch off. The battery still dims it (below).
public struct OnyxGround: View {
    let domain: OnyxDomain?
    /// Nil = `OnyxTheme.current`; Appearance draws an uncommitted draft.
    let theme: OnyxTheme?
    /// 1 on a screen, 0.5 in the widget container (a tile's glass is
    /// thinner and the Home Screen wallpaper is not black).
    let strength: Double

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.onyxForcesReducedTransparency) private var forcedReduceTransparency
    @Environment(\.onyxBatteryLevel) private var battery

    private var reduceTransparency: Bool { systemReduceTransparency || forcedReduceTransparency }

    public init(domain: OnyxDomain?, theme: OnyxTheme? = nil, strength: Double = 1) {
        self.domain = domain
        self.theme = theme
        self.strength = strength
    }

    /// `clamp(0.5 + battery/2)` — full at 100 %, 70 % at 40 %, never under
    /// half (a ground that has gone black stops saying which tab you are on).
    private var intensity: Double {
        strength * min(max(0.5 + battery / 2, 0.5), 1)
    }

    public var body: some View {
        if reduceTransparency {
            Color.onyx.base
        } else {
            let wash = (theme ?? OnyxTheme.current).groundWash(domain)
            GeometryReader { geo in
                let h = max(geo.size.height, 1)
                ZStack {
                    Color.onyx.base
                    RadialGradient(
                        colors: [wash.primary, wash.primary.opacity(0)],
                        center: UnitPoint(x: -0.10, y: -0.10),
                        startRadius: 0, endRadius: h * 0.70
                    )
                    .opacity(intensity)
                    RadialGradient(
                        colors: [wash.secondary, wash.secondary.opacity(0)],
                        center: UnitPoint(x: 1.10, y: 1.10),
                        startRadius: 0, endRadius: h * 0.55
                    )
                    .opacity(intensity)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The screen modifier: `OnyxGround` under the whole screen, safe areas and
/// all.
private struct OnyxScreenBackground: ViewModifier {
    /// `nil` is the neutral ground: Settings belongs to no domain, and is lit
    /// by the theme's own pair.
    let domain: OnyxDomain?

    func body(content: Content) -> some View {
        content.background {
            OnyxGround(domain: domain).ignoresSafeArea()
        }
    }
}

public extension View {
    /// The ground every screen stands on, in its domain's colour.
    func onyxScreen(_ domain: OnyxDomain) -> some View {
        modifier(OnyxScreenBackground(domain: domain))
    }

    /// The neutral ground, for a screen that belongs to no domain.
    func onyxScreen() -> some View {
        modifier(OnyxScreenBackground(domain: nil))
    }
}

#if DEBUG
#Preview("Glass levels") {
    ScrollView {
        VStack(spacing: OnyxSpace.l) {
            ForEach(OnyxDomain.allCases, id: \.self) { domain in
                VStack(alignment: .leading, spacing: OnyxSpace.s) {
                    Text(domain.rawValue.capitalized)
                        .font(.headline)
                        .foregroundStyle(domain.accent)
                    Text("1,950")
                        .onyxHero()
                        .foregroundStyle(Color.onyx.textPrimary)
                    HStack {
                        Text("A row")
                        Spacer()
                        Text("42").onyxNumeral()
                    }
                    .padding(OnyxSpace.m)
                    .onyxGlass(.row)
                }
                .padding(OnyxSpace.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onyxGlass(.tile)
            }
        }
        .padding()
    }
    .onyxScreen(.train)
    .foregroundStyle(Color.onyx.textPrimary)
}
#endif
