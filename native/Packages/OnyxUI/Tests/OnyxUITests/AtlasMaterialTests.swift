#if os(iOS)
import Testing
import SwiftUI
import OnyxCore
@testable import OnyxUI

/// The écorché atlas (Precision F1), stated where a screenshot cannot state it.
///
/// A flesh figure whose back teals mixed to grey, or whose Achilles sat off
/// the heel, photographs as a plausible body either way. The geometry the
/// generator emitted, the colour arithmetic the painter draws and the rule
/// that picks a material are pinned here.
@Suite("Atlas material")
struct AtlasMaterialTests {

    // MARK: - Geometry the generator emitted

    @Test("every muscle path carries a fibre axis, and the axes are anatomy")
    func fibres() {
        #expect(OnyxAtlas.muscles.allSatisfy { hypot($0.fibre.dx, $0.fibre.dy) > 0 })
        func axis(_ muscle: String) -> [CGVector] { OnyxAtlas.muscles.filter { $0.muscle == muscle }.map(\.fibre) }
        // Arms and legs run down their length…
        for muscle in ["Biceps", "Triceps", "Forearms", "Quads", "Hamstrings", "Calves"] {
            #expect(axis(muscle).allSatisfy { abs($0.dy) > 3 * abs($0.dx) }, "\(muscle) is not along the limb")
        }
        // …the pecs run across the chest toward the arm, the glutes on the
        // diagonal from sacrum to femur.
        #expect(axis("Chest").allSatisfy { abs($0.dx) > 2 * abs($0.dy) })
        #expect(axis("Glutes").allSatisfy { abs($0.dx) > 0.5 * abs($0.dy) && abs($0.dy) > 0.5 * abs($0.dx) })
    }

    @Test("tendons and bones are on both views, closed, mirrored and on the body")
    func tendonsAndBones() {
        #expect(OnyxAtlas.tendons.filter { $0.view == .front }.count == 14)
        #expect(OnyxAtlas.tendons.filter { $0.view == .back }.count == 12)
        #expect(OnyxAtlas.bones.filter { $0.view == .front }.count == 9)
        #expect(OnyxAtlas.bones.filter { $0.view == .back }.count == 6)

        let rect = CGRect(x: 0, y: 0, width: 240, height: 520)
        func built(_ build: (CGRect, inout Path) -> Void) -> Path {
            var path = Path()
            build(rect, &path)
            return path
        }
        let silhouette = OnyxAtlas.base.map { built($0) }
        for (index, shape) in (OnyxAtlas.tendons + OnyxAtlas.bones).enumerated() {
            let path = built(shape.build)
            let bounds = path.boundingRect
            #expect(bounds.width > 0 && bounds.height > 0, "shape \(index) is empty")
            // Every tendon and bone sits ON the body: its centre is inside the
            // silhouette, never floating in the margin.
            let centre = CGPoint(x: bounds.midX, y: bounds.midY)
            #expect(silhouette.contains { $0.contains(centre) }, "shape \(index) at \(centre) is off the body")
        }
        // Bilateral shapes come in mirrored pairs about the midline: the
        // union of each list's centres is symmetric.
        for list in [OnyxAtlas.tendons, OnyxAtlas.bones] {
            for view in [OnyxAtlasView.front, .back] {
                let centres = list.filter { $0.view == view }.map { built($0.build).boundingRect }.map { CGPoint(x: $0.midX, y: $0.midY) }
                for c in centres {
                    let mirror = CGPoint(x: rect.width - c.x, y: c.y)
                    #expect(centres.contains { hypot($0.x - mirror.x, $0.y - mirror.y) < 1 }, "\(view) shape at \(c) has no mirror")
                }
            }
        }
    }

    // MARK: - Colour

    private static func hex(_ color: Color) -> UInt32 { AtlasInk.hex(of: color, in: EnvironmentValues()) }

    @Test("the tokens resolve to the hexes the founder chose")
    func tokens() {
        #expect(Self.hex(OnyxInk.Fixed.fleshDeep) == 0x7A2E2E)
        #expect(Self.hex(OnyxInk.Fixed.fleshLit) == 0xB34A3A)
        #expect(Self.hex(OnyxInk.Fixed.tendon) == 0xE8DCC8)
        #expect(Self.hex(OnyxInk.Fixed.bone) == 0xF2EEE6)
        #expect(Self.hex(OnyxInk.Fixed.silhouette) == 0x141010)
    }

    /// The brief's floor, for every one of the sixteen, down to the darkest
    /// point a lit muscle can reach: Pulse's fatigue runs continuously to 0,
    /// the weekly focus floors at 0.15, a session at 0.25.
    @Test("a lit muscle holds ≥ 3 : 1 against the silhouette, all sixteen inks, and keeps its ink's hue")
    func activeContrast() {
        let deep = Self.hex(OnyxInk.Fixed.fleshDeep), lit = Self.hex(OnyxInk.Fixed.fleshLit)
        let silhouette = Self.hex(OnyxInk.Fixed.silhouette)
        for muscle in LandmarkMuscle.allCases {
            let ink = Self.hex(OnyxInk.Fixed.muscle(muscle))
            for share in [0.0001, 0.15, 0.25, 1] {
                // Both stops the painter draws.
                let stops = AtlasInk.activeStops(deep: deep, lit: lit, ink: ink, share: share)
                for active in [stops.deep, stops.lit] {
                    let ratio = AtlasInk.contrast(active, silhouette)
                    #expect(ratio >= 3, "\(muscle) share \(share): \(String(active, radix: 16)) is \(ratio) : 1")
                    // Identity: the lit muscle is its OWN ink, not the grey an
                    // Oklab chord between coral flesh and a teal lands on.
                    let a = OKLCHConvert.oklch(fromHex: active).h, i = OKLCHConvert.oklch(fromHex: ink).h
                    let turn = abs(a - i).truncatingRemainder(dividingBy: 360)
                    #expect(min(turn, 360 - turn) < 3, "\(muscle) drifted \(turn)° off its ink")
                }
            }
        }
    }

    @Test("more share is more ink, never less")
    func shareIsMonotone() {
        let deep = Self.hex(OnyxInk.Fixed.fleshDeep)
        let ink = Self.hex(OnyxInk.Fixed.muscle(.quads))
        let l = [0.25, 0.5, 0.75, 1].map { OKLCHConvert.oklch(fromHex: AtlasInk.active(deep, ink: ink, share: $0)).l }
        #expect(zip(l, l.dropFirst()).allSatisfy { $0 < $1 }, "\(l)")
        #expect(AtlasInk.weight(share: 1) == 0.6)
        // The amount rides on the lit stop: a hammered muscle is visibly
        // brighter than a touched one, not 0.06 L apart.
        let lit = Self.hex(OnyxInk.Fixed.fleshLit)
        let low = OKLCHConvert.oklch(fromHex: AtlasInk.activeStops(deep: deep, lit: lit, ink: ink, share: 0.15).lit).l
        let high = OKLCHConvert.oklch(fromHex: AtlasInk.activeStops(deep: deep, lit: lit, ink: ink, share: 1).lit).l
        #expect(high - low > 0.1, "lit stop \(low) → \(high)")
    }

    @Test("an untrained muscle is the flesh darkened 35 %")
    func inactive() {
        for flesh: UInt32 in [0x7A2E2E, 0xB34A3A] {
            let before = OKLCHConvert.oklch(fromHex: flesh).l
            let after = OKLCHConvert.oklch(fromHex: AtlasInk.inactive(flesh)).l
            #expect(abs(after / before - 0.65) < 0.02, "\(after / before)")
        }
    }

    // MARK: - Which material

    @Test("flat for a monochrome thumbnail and under Reduce Transparency, écorché everywhere else")
    func figureMaterial() {
        #expect(AtlasMaterial.figure(monochrome: false, thumbnail: false, reduceTransparency: false) == .ecorche)
        #expect(AtlasMaterial.figure(monochrome: false, thumbnail: true, reduceTransparency: false) == .ecorche)
        #expect(AtlasMaterial.figure(monochrome: true, thumbnail: false, reduceTransparency: false) == .ecorche)
        #expect(AtlasMaterial.figure(monochrome: true, thumbnail: true, reduceTransparency: false) == .flat)
        #expect(AtlasMaterial.figure(monochrome: false, thumbnail: false, reduceTransparency: true) == .flat)
    }

    // MARK: - The frame budget

    /// The brief's budget: the logger's 170 pt `.both` figure paints in
    /// < 4 ms. Measured here end to end — the painter's commands AND their
    /// rasterisation at the phone's 3× scale, through a fresh `ImageRenderer`
    /// per sample — as the
    /// median of 40 paints after a warm-up, with an upper-B-like session lit
    /// (eight muscles, glow and sheen on). Printed so the wave record quotes
    /// the number against the brief's 4 ms; ASSERTED at one 60 Hz frame
    /// (16 ms), because a wall-clock bound this tight inside a parallel test
    /// run on a loaded machine would fail the gate at random.
    @MainActor
    @Test("the 170 pt both-views écorché paints inside a frame (brief: 4 ms, printed)")
    func paintBudget() {
        let worked: [String: Double] = [
            "Lats": 1, "Upper back": 1, "Chest": 0.9, "Biceps": 0.66, "Forearms": 0.66,
            "Front delts": 0.45, "Rear delts": 0.33, "Triceps": 0.25,
        ]
        func median(_ material: AtlasMaterial) -> Double {
            let painter = AtlasPainter(material: material)
            func face(_ view: OnyxAtlasView) -> some View {
                Canvas { context, size in
                    painter.paint(&context, in: CGRect(origin: .zero, size: size), view: view, mark: { entry in
                        worked[entry.muscle].map {
                            AtlasPainter.Mark(ink: OnyxInk.Fixed.muscle(LandmarkMuscle(rawValue: entry.muscle)!), share: $0)
                        }
                    })
                }
                .aspectRatio(OnyxAtlas.viewBox.width / OnyxAtlas.viewBox.height, contentMode: .fit)
            }
            // A FRESH renderer per sample: one `ImageRenderer` hands back its
            // cached image on a second read (83 ns — measured, and useless),
            // so each sample pays setup + layout + paint + raster, an upper
            // bound on what a frame of the logger costs.
            func render() {
                let renderer = ImageRenderer(content: HStack(spacing: 10) { face(.front); face(.back) }.frame(width: 361, height: 170))
                renderer.scale = 3
                _ = renderer.cgImage
            }
            render()
            var samples: [Double] = []
            for _ in 0..<40 {
                let start = ContinuousClock.now
                render()
                let elapsed = ContinuousClock.now - start
                samples.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
            }
            return samples.sorted()[samples.count / 2]
        }
        let ecorche = median(.ecorche), flat = median(.flat)
        print("ATLAS-PAINT ecorche \(ecorche) ms · flat \(flat) ms (170 pt both, 3x, median of 40)")
        #expect(ecorche < 16, "écorché \(ecorche) ms")
    }

    @Test("a widget is flat when it cannot show colour or sits in a rectangular accessory")
    func widgetMaterial() {
        #expect(AtlasMaterial.widget(monochrome: false, fullColor: true, rectangularAccessory: false) == .ecorche)
        #expect(AtlasMaterial.widget(monochrome: true, fullColor: true, rectangularAccessory: false) == .flat)
        #expect(AtlasMaterial.widget(monochrome: false, fullColor: false, rectangularAccessory: false) == .flat)
        #expect(AtlasMaterial.widget(monochrome: false, fullColor: true, rectangularAccessory: true) == .flat)
        #expect(AtlasMaterial.widget(monochrome: false, fullColor: true, rectangularAccessory: false, reduceTransparency: true) == .flat)
    }
}
#endif
