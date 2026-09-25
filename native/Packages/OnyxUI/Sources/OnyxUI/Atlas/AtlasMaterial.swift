import SwiftUI
import OnyxCore
import os

// MARK: - The material

/// How a body is LIT — the one decision both atlas renderers used to make
/// separately (Precision F1, founder decision "Atlas: A Écorché").
///
/// ── WHY A FLAYED FIGURE ─────────────────────────────────────────────────────
/// The old figure was white alpha over black: a mannequin with coloured decals,
/// which the founder called white plastic. An écorché is the anatomist's
/// figure with the skin off — muscle shaded along its fibres over a dark body,
/// the cords and the bone that show through in ivory — and it is the one
/// drawing of a body where "this muscle, lit" is the natural state rather than
/// a sticker on top of it.
///
/// `flat` is the look that shipped before, kept for the two places the flesh
/// cannot help: a 44 pt monochrome thumbnail (one hue at an alpha is all it can
/// carry) and Reduce Transparency (no glow, no sheen, no layered light).
public enum AtlasMaterial: Sendable, Equatable {
    case ecorche
    case flat

    /// The app's `AtlasFigure`: flat for a monochrome THUMBNAIL (the Train
    /// tab's day thumb) and under Reduce Transparency; flesh everywhere else —
    /// a full-size monochrome body (Pulse's fatigue figure) is still a body.
    public static func figure(monochrome: Bool, thumbnail: Bool, reduceTransparency: Bool) -> AtlasMaterial {
        reduceTransparency || (monochrome && thumbnail) ? .flat : .ecorche
    }

    /// A widget's `OnyxAtlasFigure`: flat when the Home Screen cannot show
    /// colour (accented / vibrant rendering, or the caller's `monochrome`) and
    /// in a rectangular Lock Screen accessory, where the system desaturates
    /// everything and flesh would come out as a grey smear.
    public static func widget(monochrome: Bool, fullColor: Bool, rectangularAccessory: Bool) -> AtlasMaterial {
        monochrome || !fullColor || rectangularAccessory ? .flat : .ecorche
    }
}

// MARK: - The colour arithmetic

/// Hex in, hex out, so a test can hold the exact numbers the painter draws.
///
/// ── WHY THE INK'S HUE AND NOT AN OKLAB MIX (measured) ───────────────────────
/// The brief says a lit muscle is the flesh "mixed 60 % toward" its fixed ink.
/// Taken as a straight Oklab chord that is right for the warm half of the
/// palette and wrong for the cool half: coral flesh and a teal are near
/// complements, so the chord runs through grey — Lats, Upper back and Lower
/// back came out at OKLCH chroma 0.021–0.037 (the dataviz validator's "reads
/// grey") and every lit back looked like dead tissue. So the mix takes
/// lightness and chroma 60 % of the way and the hue from the INK: the muscle
/// is its own colour, shaded as flesh. Pinned by `AtlasMaterialTests`.
public enum AtlasInk {

    /// How far toward its ink a lit muscle goes: 0.6 at full share (the
    /// brief), 0.4875 at the 0.25 floor `setsToWorked` hands the least-worked
    /// muscle. Share also drives the glow; the hue never moves with it.
    public static func weight(share: Double) -> Double {
        0.45 + 0.15 * min(max(share, 0), 1)
    }

    /// A lit muscle: `flesh` taken `weight(share:)` of the way to `ink` in
    /// lightness and chroma, at the ink's hue. An achromatic ink (a white or
    /// grey monochrome tint) has no hue to give, so it keeps the flesh's.
    public static func active(_ flesh: UInt32, ink: UInt32, share: Double) -> UInt32 {
        let f = OKLCHConvert.oklch(fromHex: flesh), i = OKLCHConvert.oklch(fromHex: ink)
        let t = weight(share: share)
        return OKLCHConvert.hex(from: OKLCH(
            l: f.l + (i.l - f.l) * t,
            c: f.c + (i.c - f.c) * t,
            h: i.c < 0.02 ? f.h : i.h
        ))
    }

    /// A lit muscle's two gradient stops. The deep stop is `active` as it
    /// is; the lit stop is lifted a further 0.06 OKLCH L toward the light,
    /// because 60 % of the way to the ink leaves only 40 % of the flesh's
    /// lightness span along the fibre — a lit belly read as a flat enamel
    /// decal beside the sculpted untrained ones (round-1 critique). Lifting
    /// the LIT end, not darkening the deep one, keeps the ≥ 3 : 1 floor
    /// against the silhouette where it was measured.
    public static func activeStops(deep: UInt32, lit: UInt32, ink: UInt32, share: Double) -> (deep: UInt32, lit: UInt32) {
        (active(deep, ink: ink, share: share), lighter(active(lit, ink: ink, share: share), by: 0.06))
    }

    /// An untrained muscle: the flesh darkened 35 % (brief).
    public static func inactive(_ flesh: UInt32) -> UInt32 { darker(flesh, by: 0.35) }

    /// Toward white in OKLCH lightness, hue and chroma kept (gamut-fitted).
    public static func lighter(_ hex: UInt32, by amount: Double) -> UInt32 {
        var colour = OKLCHConvert.oklch(fromHex: hex)
        colour.l = min(colour.l + amount, 1)
        return OKLCHConvert.hex(from: colour)
    }

    /// Toward black in Oklab — lightness and chroma scaled together, hue kept.
    public static func darker(_ hex: UInt32, by amount: Double) -> UInt32 {
        var colour = OKLCHConvert.oklch(fromHex: hex)
        let keep = 1 - min(max(amount, 0), 1)
        colour.l *= keep
        colour.c *= keep
        return OKLCHConvert.hex(from: colour)
    }

    /// WCAG 2 contrast ratio between two opaque sRGB colours.
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            func channel(_ shift: UInt32) -> Double {
                let c = Double((hex >> shift) & 0xFF) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        }
        let x = luminance(a) + 0.05, y = luminance(b) + 0.05
        return max(x, y) / min(x, y)
    }

    /// A token (or a caller's tint) as the 8-bit sRGB hex the arithmetic takes.
    /// Opacity is dropped: a lit muscle is opaque flesh whatever alpha its ink
    /// was declared at.
    public static func hex(of color: Color, in environment: EnvironmentValues) -> UInt32 {
        let resolved = color.resolve(in: environment)
        func byte(_ v: Float) -> UInt32 { UInt32((min(max(Double(v), 0), 1) * 255).rounded()) }
        return byte(resolved.red) << 16 | byte(resolved.green) << 8 | byte(resolved.blue)
    }

    /// A COMPUTED colour back to SwiftUI. Not a raw colour — every hex that
    /// reaches this was derived from `OnyxInk.Fixed` tokens and a caller's
    /// tint by the functions above, which is why it builds a `Color.Resolved`
    /// rather than reaching for the token files' `Color(hex:)`.
    static func color(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(Color.Resolved(
            red: Float((hex >> 16) & 0xFF) / 255,
            green: Float((hex >> 8) & 0xFF) / 255,
            blue: Float(hex & 0xFF) / 255,
            opacity: Float(opacity)
        ))
    }
}

// MARK: - The painter

/// The one drawing of a body, used by BOTH renderers — the app's
/// `AtlasFigure` and the widgets' `OnyxAtlasFigure`. Each keeps its own public
/// API and decides WHAT to light (a side-aware colour map, one accent); this
/// decides HOW, so the phone and the Home Screen can never draw two anatomies
/// in two materials again.
///
/// Paint order is the atlas's own (`OnyxAtlas.muscles` is in PAINT order and
/// `OnyxAtlas.muscle(at:)` hit-tests against it) — a lit muscle is never
/// lifted above its neighbours, or a tap on the seam would land on the muscle
/// the eye does not see.
public struct AtlasPainter: Sendable {

    /// What one muscle path carries: its ink and its share, 0…1.
    public struct Mark: Sendable {
        public var ink: Color
        public var share: Double
        public init(ink: Color, share: Double) {
            self.ink = ink
            self.share = share
        }
    }

    public var material: AtlasMaterial
    /// The budget cut: no specular band and no glow (écorché), no drop shadow
    /// (flat). A widget's memory ceiling and a thumbnail's size both mean the
    /// offscreen passes buy nothing anyone can see.
    public var isLite: Bool

    public init(material: AtlasMaterial, isLite: Bool = false) {
        self.material = material
        self.isLite = isLite
    }

    /// `os_signpost` intervals around every paint ("Atlas" category, name
    /// "paint") — the brief's < 4 ms budget for the logger's 170 pt `.both`
    /// figure is read off these in Instruments.
    static let signposter = OSSignposter(subsystem: "app.onyx.health", category: "Atlas")

    public func paint(
        _ context: inout GraphicsContext,
        in rect: CGRect,
        view: OnyxAtlasView,
        mark: (OnyxAtlasPath) -> Mark?,
        ring: (OnyxAtlasPath) -> Color? = { _ in nil }
    ) {
        let interval = Self.signposter.beginInterval("paint", "\(material == .ecorche ? "ecorche" : "flat") h\(Int(rect.height))")
        defer { Self.signposter.endInterval("paint", interval) }
        switch material {
        case .flat: paintFlat(&context, rect, view, mark)
        case .ecorche: paintEcorche(&context, rect, view, mark)
        }
        paintRings(&context, rect, view, ring)
        // Definition last, over everything, and STROKED ONLY — several of
        // these are OPEN paths (a brow, the linea alba), and SwiftUI closes an
        // open path when it fills one, so a filled brow becomes a wedge across
        // the forehead.
        // Fainter on flesh: the face and fibre lines at 18 % turned the rim
        // into a line drawing (round-1 critique).
        let definition = Color.white.opacity(material == .ecorche ? 0.10 : 0.18)
        for entry in OnyxAtlas.detail where entry.view == view {
            var path = Path()
            entry.build(rect, &path)
            context.stroke(path, with: .color(definition), lineWidth: 0.35)
        }
    }

    // MARK: Flat — the look that shipped before 9.x

    private func paintFlat(_ context: inout GraphicsContext, _ rect: CGRect, _ view: OnyxAtlasView, _ mark: (OnyxAtlasPath) -> Mark?) {
        let light = Self.light(across: rect)
        func shade(_ top: Color, _ bottom: Color) -> GraphicsContext.Shading {
            .linearGradient(Gradient(colors: [top, bottom]), startPoint: light.start, endPoint: light.end)
        }
        // The silhouette first, and never tinted: it carries no data, and a
        // glowing head would read as a muscle nobody can train. In its own
        // layer when it casts the shadow, so the shadow falls under the BODY
        // and not under every muscle on it (§6.7); a lite figure skips the
        // offscreen pass — a 10 pt blur under a thumbnail is invisible.
        func silhouette(_ layer: inout GraphicsContext) {
            for build in OnyxAtlas.base {
                var path = Path()
                build(rect, &path)
                layer.fill(path, with: shade(.white.opacity(0.11), .white.opacity(0.03)))
                layer.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: Self.hairline)
            }
        }
        if isLite {
            silhouette(&context)
        } else {
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 10, y: 6))
                silhouette(&layer)
            }
        }

        for entry in OnyxAtlas.muscles where entry.view == view {
            var path = Path()
            entry.build(rect, &path)
            if let lit = mark(entry), lit.share > 0 {
                // Alpha carries the amount. A hue RAMP would read as a
                // verdict — green good, red bad — and this figure passes no
                // verdicts; it reports where work landed.
                let strength = min(max(lit.share, 0), 1)
                context.fill(path, with: shade(
                    lit.ink.opacity(0.30 + strength * 0.60),
                    lit.ink.opacity(0.14 + strength * 0.42)
                ))
                context.stroke(path, with: .color(lit.ink.opacity(0.95)), lineWidth: Self.hairline)
            } else {
                context.fill(path, with: shade(.white.opacity(0.07), .white.opacity(0.035)))
                context.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: Self.hairline)
            }
        }
    }

    // MARK: Écorché

    private func paintEcorche(_ context: inout GraphicsContext, _ rect: CGRect, _ view: OnyxAtlasView, _ mark: (OnyxAtlasPath) -> Mark?) {
        let env = context.environment
        let deep = AtlasInk.hex(of: OnyxInk.Fixed.fleshDeep, in: env)
        let lit = AtlasInk.hex(of: OnyxInk.Fixed.fleshLit, in: env)
        let scale = min(rect.width / OnyxAtlas.viewBox.width, rect.height / OnyxAtlas.viewBox.height)
        // "A 1 pt darker edge" at the sizes the brief reviewed (170–380 pt);
        // a 44 pt thumbnail at 1 pt would be all outline.
        let edge = min(1, max(0.35, 1.5 * scale))
        let light = Self.light(across: rect)
        let toLight = Self.unit(CGVector(dx: light.start.x - light.end.x, dy: light.start.y - light.end.y))
        // ── BELOW ~78 PT TALL THE IVORY IS SPECKLE ──────────────────────────
        // The library's 28 × 52 pt rows: a patella is a pixel and the abs'
        // tendon grid is a stripe as loud as the lit chest, so the figure read
        // as a striped mannequin. Small figures skip tendon and bone and take
        // the untrained flesh down 55 % instead of 35 %, so the lit muscle is
        // the only thing in them that is bright.
        let small = scale < 0.3

        // ── 1. The body: warm near-black with a 12 % rim light, falling to
        // nothing on the side away from the light — a light, not an outline.
        let rim = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [.white.opacity(0.12), .white.opacity(0)]),
            startPoint: light.start, endPoint: light.end
        )
        for build in OnyxAtlas.base {
            var path = Path()
            build(rect, &path)
            context.fill(path, with: .color(OnyxInk.Fixed.silhouette))
            context.stroke(path, with: rim, lineWidth: edge * 0.75)
        }

        // ── 2. Muscle, shaded along its fibres, deep → lit toward the light.
        let rest = small
            ? (AtlasInk.darker(deep, by: 0.55), AtlasInk.darker(lit, by: 0.55))
            : (AtlasInk.inactive(deep), AtlasInk.inactive(lit))
        let restColors = (AtlasInk.color(rest.0), AtlasInk.color(rest.1), AtlasInk.color(AtlasInk.darker(rest.0, by: 0.4)))
        var glowing: [(path: Path, ink: Color, share: Double)] = []
        for entry in OnyxAtlas.muscles where entry.view == view {
            var path = Path()
            entry.build(rect, &path)
            let bounds = path.boundingRect
            let fibre = Self.facing(entry.fibre, toLight)
            let stops: (Color, Color, Color)
            if let marked = mark(entry), marked.share > 0 {
                let share = min(max(marked.share, 0), 1)
                let ink = AtlasInk.hex(of: marked.ink, in: env)
                let pair = AtlasInk.activeStops(deep: deep, lit: lit, ink: ink, share: share)
                stops = (AtlasInk.color(pair.deep), AtlasInk.color(pair.lit),
                         AtlasInk.color(AtlasInk.darker(pair.deep, by: 0.4)))
                glowing.append((path, marked.ink, share))
            } else {
                stops = restColors
            }
            let span = Self.span(bounds, fibre)
            context.fill(path, with: .linearGradient(Gradient(colors: [stops.0, stops.1]), startPoint: span.from, endPoint: span.to))
            if !isLite {
                // The specular band: a white stripe running WITH the fibres,
                // a quarter of the belly wide, centred 30 % in from the side
                // that faces the light — the sheen on a wet belly. Narrow on
                // purpose: at the brief's 8 % a wide soft band vanished on a
                // lit fill; a defined one reads.
                let across = Self.facing(CGVector(dx: -fibre.dy, dy: fibre.dx), toLight)
                let band = Self.span(bounds, across)
                context.fill(path, with: .linearGradient(Gradient(stops: [
                    .init(color: .white.opacity(0), location: 0.18),
                    .init(color: .white.opacity(0.08), location: 0.30),
                    .init(color: .white.opacity(0), location: 0.43),
                ]), startPoint: band.to, endPoint: band.from))
            }
            context.stroke(path, with: .color(stops.2), lineWidth: edge)
        }

        // ── 3. The glow: the lit muscles' own ink at 25 % × share, blurred,
        // and clipped to OUTSIDE them — it spills onto the neighbours and the
        // body, never over the muscle it belongs to. The radius is 2.5 % of
        // the figure's height: at 1.3 % (round 1) it read as a coloured
        // outline, and ten lit muscles became a neon edge rather than bloom.
        if !isLite, !glowing.isEmpty {
            var union = Path()
            for g in glowing { union.addPath(g.path) }
            context.drawLayer { outside in
                outside.clip(to: union, options: .inverse)
                outside.drawLayer { glow in
                    glow.addFilter(.blur(radius: 6.5 * scale))
                    for g in glowing {
                        glow.fill(g.path, with: .color(g.ink.opacity(0.25 * g.share)))
                        glow.stroke(g.path, with: .color(g.ink.opacity(0.25 * g.share)), lineWidth: 4 * scale)
                    }
                }
            }
        }

        // ── 4. Bone, then tendon, over the muscle — flat ivory, and QUIET.
        // Round 1 lit them like the muscles (a gradient to 90 %) and the
        // kneecaps became the brightest thing on the figure — a mannequin's
        // ball joints over an untrained quad. The data is the lit muscles;
        // ivory is the structure under it, so it stays below the dimmest lit
        // ink over untrained flesh (≈ L 0.5 against lit ≥ 0.55).
        if !small {
            for (shapes, color, alpha) in [(OnyxAtlas.bones, OnyxInk.Fixed.bone, 0.34), (OnyxAtlas.tendons, OnyxInk.Fixed.tendon, 0.30)] {
                for shape in shapes where shape.view == view {
                    var path = Path()
                    shape.build(rect, &path)
                    context.fill(path, with: .color(color.opacity(alpha)))
                }
            }
        }
    }

    // MARK: Reported rings (Pulse)

    /// Over the fill and under the definition, in their own pass, so a ring
    /// is never painted over by the NEXT muscle's fill — several landmarks
    /// share an edge and in one pass the later fill clips the earlier ring
    /// along exactly the boundary the ring exists to mark. Two strokes: a soft
    /// halo under a crisp hairline, so it reads as a mark ON a muscle rather
    /// than a thicker one.
    private func paintRings(_ context: inout GraphicsContext, _ rect: CGRect, _ view: OnyxAtlasView, _ ring: (OnyxAtlasPath) -> Color?) {
        for entry in OnyxAtlas.muscles where entry.view == view {
            guard let color = ring(entry) else { continue }
            var path = Path()
            entry.build(rect, &path)
            context.stroke(path, with: .color(color.opacity(0.35)), lineWidth: Self.hairline * 5)
            context.stroke(path, with: .color(color), lineWidth: Self.hairline * 1.6)
        }
    }

    // MARK: Geometry

    /// §6.7's hairline, on every flat outline.
    static let hairline: CGFloat = 0.5

    /// The light's line: 145° in CSS terms — 0° straight up, clockwise — so
    /// it falls from the upper left across the whole figure and every fill,
    /// silhouette or muscle, is lit from the same corner. `start` is the lit
    /// end.
    static func light(across rect: CGRect) -> (start: CGPoint, end: CGPoint) {
        let theta = 145.0 * .pi / 180
        let dir = CGPoint(x: sin(theta), y: -cos(theta))
        // CSS's gradient line, so the corners land at exactly 0 and 1 — the
        // diagonal would leave them at ~0.1 / 0.9.
        let reach = (rect.width * abs(sin(theta)) + rect.height * abs(cos(theta))) / 2
        return (
            CGPoint(x: rect.midX - dir.x * reach, y: rect.midY - dir.y * reach),
            CGPoint(x: rect.midX + dir.x * reach, y: rect.midY + dir.y * reach)
        )
    }

    static func unit(_ v: CGVector) -> CGVector {
        let length = hypot(v.dx, v.dy)
        return length > 0 ? CGVector(dx: v.dx / length, dy: v.dy / length) : CGVector(dx: 0, dy: 1)
    }

    /// An AXIS turned to face the light: the fibre's sign carries nothing, so
    /// whichever end is nearer the light is the lit end.
    static func facing(_ axis: CGVector, _ light: CGVector) -> CGVector {
        let u = unit(axis)
        return u.dx * light.dx + u.dy * light.dy < 0 ? CGVector(dx: -u.dx, dy: -u.dy) : u
    }

    /// The gradient line across `bounds` along unit `u`, reaching its corners:
    /// `from` is the end away from `u`, `to` the end it points at.
    static func span(_ bounds: CGRect, _ u: CGVector) -> (from: CGPoint, to: CGPoint) {
        let half = (abs(u.dx) * bounds.width + abs(u.dy) * bounds.height) / 2
        return (
            CGPoint(x: bounds.midX - u.dx * half, y: bounds.midY - u.dy * half),
            CGPoint(x: bounds.midX + u.dx * half, y: bounds.midY + u.dy * half)
        )
    }
}
