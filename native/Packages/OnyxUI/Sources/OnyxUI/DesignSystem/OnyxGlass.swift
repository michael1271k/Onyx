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

private struct OnyxGlassModifier: ViewModifier {
    let level: GlassLevel

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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

/// How lit the mesh is allowed to be, 0…1 — the device's battery.
///
/// ── WHY A BACKGROUND WATCHES THE BATTERY ────────────────────────────────────
/// The bleed is the one thing on this app that is pure decoration: it says
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

/// True black, with one mesh bleed of the screen's domain behind the top of it.
///
/// ── ONE BLEED, TEN PERCENT, TOP ONLY ────────────────────────────────────────
/// The accent's job is to say which domain you are in before you read a word.
/// It does that from the corner of your eye; at 30 % it becomes a background you
/// have to read text against, and every material above it turns muddy because
/// glass tints towards whatever is behind it. The bleed is behind the TOP
/// because that is where the title is and where the eye lands.
///
/// v2 took it from 12 % over 340 pt to 8 % over 240 (§3.1). Phase 2.5 §W5.2
/// gives it back two points and forty: the desaturated v2 accents were quiet
/// enough that 8 % over 240 read as a smudge above the title rather than as a
/// domain, and 10 % over 280 is still under the 12 % that made every screenshot
/// look like a landing page. The ceiling is 10 %, and the battery is what keeps
/// the average below it.
///
/// ── AND ONE STOP AT THE BOTTOM ──────────────────────────────────────────────
/// A screen taller than its bleed ends in dead black, which on a long scroll
/// reads as the app having run out rather than the list having. One faint
/// ellipse in the bottom-leading corner — half the top's alpha, no structure —
/// closes the frame without becoming a second gradient.
private struct OnyxScreenBackground: ViewModifier {
    /// `nil` is the neutral ground: Settings belongs to no domain, and giving
    /// it one would say the tab is about that domain.
    let domain: OnyxDomain?

    /// Frostier and opaque when the system asks for it. A mesh under glass is
    /// the exact thing this setting exists to switch off, so it goes entirely —
    /// dimming it would leave a tinted haze that is neither the design nor flat.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.onyxBatteryLevel) private var battery

    /// §W5.2: the peak the bleed may reach, at a full battery.
    private static let peak: Double = 0.10
    /// Tall enough to bleed under a large navigation title and no further.
    private static let bleedHeight: CGFloat = 280

    /// `peak × clamp(0.5 + battery/2)` — full at 100 %, 70 % at 40 %, and never
    /// under half, because a bleed that has faded out entirely stops saying
    /// which tab you are on.
    private var intensity: Double {
        Self.peak * min(max(0.5 + battery / 2, 0.5), 1)
    }

    /// The two stops the mesh is lit with. Neutral borrows the text ink, which
    /// on this ground is a grey lift and not a hue.
    private var stops: (Color, Color) {
        guard let domain else { return (Color.onyx.textPrimary, Color.onyx.textSecondary) }
        return (domain.start, domain.end)
    }

    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency {
                Color.onyx.base.ignoresSafeArea()
            } else {
                ZStack(alignment: .top) {
                    Color.onyx.base
                    mesh
                        .opacity(domain == nil ? intensity / 2 : intensity)
                        .frame(height: Self.bleedHeight)
                        .blur(radius: 40)
                        .ignoresSafeArea()
                }
                .overlay(alignment: .bottomLeading) { corner }
                .ignoresSafeArea()
            }
        }
    }

    private var mesh: some View {
        let (a, b) = stops
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                .init(0, 0),   .init(0.5, 0),   .init(1, 0),
                .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                .init(0, 1),   .init(0.5, 1),   .init(1, 1),
            ],
            colors: [
                a,     a,      b,
                b,     .black, .black,
                .black, .black, .black,
            ]
        )
    }

    /// The bottom-leading stop. An ellipse rather than a second mesh: it has no
    /// structure to show and a mesh would cost a second render pass to say the
    /// same thing.
    private var corner: some View {
        Ellipse()
            .fill(stops.1)
            .frame(width: 240, height: 160)
            .blur(radius: 60)
            .opacity(intensity / 2)
            .offset(x: -60, y: 40)
            .allowsHitTesting(false)
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
