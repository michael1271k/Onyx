import SwiftUI
import OnyxUI
import OnyxCore

/// The body, tinted by where the session landed.
///
/// `OnyxAtlas.swift` beside this file is GENERATED from the web app's `lib/body/atlas.ts`
/// and holds only geometry; `atlas-parity.test.ts` re-runs the generator and
/// fails when either Swift copy differs, so the web app, the widget and this
/// screen can never disagree about where a muscle is.
///
/// How a body is TINTED is a design decision rather than a translation, so the
/// drawing is hand-written — and it is written differently here than in the
/// widget. A 40 pt figure on a Home Screen has to fill in one hue at several
/// alphas to stay readable; a 160 pt figure in a sheet can afford the full
/// three-channel language (family hue · ramp step · alpha) and is a worse
/// figure without it.
struct AtlasFigure: View {

    enum Side { case front, back, both }

    var side: Side = .both
    /// Landmark → 0…1. `MuscleCredit.worked(from:)` produces exactly this.
    var worked: [LandmarkMuscle: Double] = [:]
    /// Draw every muscle in one colour instead of its own family hue.
    ///
    /// Two things used to be inferred from this being non-nil: "one hue" and
    /// "this is a 44 pt thumbnail, skip the drop shadow". Pulse's composite
    /// body is monochrome AND full size, so inheriting the second meaning
    /// silently deleted the §6.7 shadow from a 170 pt figure. They are separate
    /// questions now — `isThumbnail` asks the second one.
    var monochromeTint: Color?
    /// A 44 pt figure in a tile: no drop shadow, because a 10 pt blur is
    /// invisible at that size and costs an offscreen pass per tile.
    var isThumbnail = false
    /// An explicit colour per muscle AND SIDE, overriding both the family hue
    /// and the monochrome tint. The DOMS body needs this: soreness is a
    /// SEVERITY ramp (§3.2 — none tertiary · mild Good · moderate Record ·
    /// severe Danger) and a quadricep that hurts is not "more Tide" than one
    /// that does not.
    ///
    /// ── THE `both` KEY LIGHTS BOTH PATHS (W9) ───────────────────────────────
    /// Lookup is exact side FIRST, then `both`. A whole-muscle rating is stored
    /// as `both` and paints the left and the right path alike — which is what
    /// keeps every rating written before laterality existed drawing exactly as
    /// it did. A one-sided rating keys the side it names and the other path
    /// falls through to the plain fill, because the athlete said nothing about
    /// it and a figure must not invent the half nobody reported.
    var colors: [MuscleSide: Color] = [:]
    /// What VoiceOver reads for a muscle — "Moderate" on the DOMS body. Keyed
    /// and resolved like `colors`; a muscle with no entry reads its worked
    /// share instead.
    var values: [MuscleSide: String] = [:]
    /// Muscles to RING, over whatever the fill says.
    ///
    /// ── THE SECOND CHANNEL, AND WHY IT IS A STROKE ──────────────────────────
    /// Pulse draws two facts about the same body at once: modelled fatigue,
    /// which is what the ledger implies, and reported soreness, which is what
    /// the user typed. They disagree constantly and both are right — you can be
    /// sore in a muscle the plan barely touched, and fresh in one that took
    /// twelve sets — and the disagreement is the most interesting thing either
    /// of them has to say.
    ///
    /// Two figures side by side would make the reader do the comparison; two
    /// FILLS on one figure cannot both be seen. A ring can: it sits on the
    /// muscle's own edge, reads at a glance, and leaves the fill underneath
    /// entirely legible. A muscle filled dark with no ring is loaded and not
    /// complaining; a ring with no fill is complaining about work the ledger has
    /// no record of.
    ///
    /// Pulse-only in practice, because nothing else passes it. The logger's
    /// figure answers one question — where did this session land — and a second
    /// channel there would be decoration.
    var outlined: [MuscleSide: Color] = [:]
    /// Called with the muscle under a tap and the side of it, when there is
    /// one. Nil leaves the figure inert, which is what every figure outside the
    /// DOMS tile is.
    var onPick: ((MuscleSide) -> Void)?

    var body: some View {
        switch side {
        case .both:
            HStack(spacing: 10) {
                figure(.front)
                figure(.back)
            }
        case .front: figure(.front)
        case .back:  figure(.back)
        }
    }

    /// Muscle-and-side → colour and amount, resolved once per draw rather than
    /// per path, and built from the paths the VIEW actually draws.
    ///
    /// `OnyxAtlas` keys on the muscle's display STRING, because it is generated
    /// from TypeScript and knows nothing about a Swift enum. This is the join,
    /// and `LandmarkMuscle.rawValue` carrying the display spelling is what makes
    /// it a lookup rather than a translation table.
    ///
    /// The AMOUNT still comes from `worked`, which is whole-muscle: modelled
    /// fatigue is bilateral and always was — the ledger records that a set of
    /// squats happened, not which leg did more of it. Only the COLOUR is
    /// side-aware, because only the colour carries something the athlete
    /// reported.
    private func tints(_ view: OnyxAtlasView) -> [MuscleSide: (Color, Double)] {
        var out: [MuscleSide: (Color, Double)] = [:]
        for entry in OnyxAtlas.muscles where entry.view == view {
            guard let muscle = LandmarkMuscle(rawValue: entry.muscle),
                  let intensity = worked[muscle], intensity > 0 else { continue }
            let key = MuscleSide(muscle, entry.side)
            out[key] = (
                colors[key] ?? colors[MuscleSide(muscle, .both)] ?? monochromeTint ?? Color.onyx.muscle(muscle),
                intensity
            )
        }
        return out
    }

    private func figure(_ view: OnyxAtlasView) -> some View {
        let resolved = tints(view)
        return Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let light = Self.light(across: rect)
            func shade(_ top: Color, _ bottom: Color) -> GraphicsContext.Shading {
                .linearGradient(Gradient(colors: [top, bottom]), startPoint: light.start, endPoint: light.end)
            }

            // The silhouette first, and never tinted: it carries no data, and a
            // glowing head would read as a muscle nobody can train. It sits in
            // its own layer so the drop shadow falls under the BODY and not
            // under every muscle on it (§6.7).
            // The 44 pt monochrome thumbnails skip the layer: a 10 pt blur
            // under a thumbnail is invisible and an offscreen pass per tile.
            context.drawLayer { layer in
                if !isThumbnail {
                    layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 10, y: 6))
                }
                for build in OnyxAtlas.base {
                    var path = Path()
                    build(rect, &path)
                    layer.fill(path, with: shade(.white.opacity(0.11), .white.opacity(0.03)))
                    layer.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: Self.hairline)
                }
            }

            for entry in OnyxAtlas.muscles where entry.view == view {
                var path = Path()
                entry.build(rect, &path)
                let key = LandmarkMuscle(rawValue: entry.muscle).map { MuscleSide($0, entry.side) }
                if let key, let (tint, intensity) = resolved[key], intensity > 0 {
                    // Alpha carries the amount. A hue RAMP would read as a
                    // verdict — green good, red bad — and this figure passes no
                    // verdicts; it reports where work landed.
                    let strength = min(max(intensity, 0), 1)
                    context.fill(path, with: shade(
                        tint.opacity(0.30 + strength * 0.60),
                        tint.opacity(0.14 + strength * 0.42)
                    ))
                    context.stroke(path, with: .color(tint.opacity(0.95)), lineWidth: Self.hairline)
                } else {
                    // The belly of an untrained muscle: a shade darker than the
                    // flesh around it, lit from the same corner.
                    context.fill(path, with: shade(.white.opacity(0.07), .white.opacity(0.035)))
                    context.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: Self.hairline)
                }
            }

            // ── THE REPORTED RING, over the fill and under the definition ──
            // Drawn in its own pass rather than inside the loop above, so a
            // ring is never painted over by the NEXT muscle's fill: several
            // landmarks share an edge (the three delts, the two heads either
            // side of the linea alba) and in one pass the later path's fill
            // clips the earlier path's ring along exactly the boundary the ring
            // exists to mark.
            //
            // Two strokes, not one: a soft wide halo under a crisp hairline.
            // A single 2 pt stroke at this scale reads as a thicker muscle
            // rather than as a mark ON one, which is the difference between a
            // second channel and a rendering artefact.
            for entry in OnyxAtlas.muscles where entry.view == view {
                guard let muscle = LandmarkMuscle(rawValue: entry.muscle),
                      let ring = outlined[MuscleSide(muscle, entry.side)]
                              ?? outlined[MuscleSide(muscle, .both)] else { continue }
                var path = Path()
                entry.build(rect, &path)
                context.stroke(path, with: .color(ring.opacity(0.35)), lineWidth: Self.hairline * 5)
                context.stroke(path, with: .color(ring), lineWidth: Self.hairline * 1.6)
            }

            // Definition last, over everything, and STROKED ONLY — several of
            // these are OPEN paths (a brow, the linea alba), and SwiftUI closes
            // an open path when it fills one, so a filled brow becomes a wedge
            // across the forehead.
            for entry in OnyxAtlas.detail where entry.view == view {
                var path = Path()
                entry.build(rect, &path)
                context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 0.35)
            }
        }
        .aspectRatio(OnyxAtlas.viewBox.width / OnyxAtlas.viewBox.height, contentMode: .fit)
        // The hit test is the DRAWING — `OnyxAtlas.muscle(at:in:side:)` asks
        // the same closures, built into the same rect, `Path.contains`. A tap
        // on the silhouette or in the letter-boxed margin answers nil and the
        // gesture does nothing, which is the correct behaviour for a tap on a
        // shin.
        .contentShape(.rect)
        // The drawn size, tracked as it lays out: the gesture reports a point
        // and carries no bounds, and the hit test needs the rect the paths were
        // built into. Zero until first layout, where every tap answers nil.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { measured = $0 }
        .gesture(pick(view))
        // A figure with no `onPick` is DECORATION and must not eat a tap: the
        // 44 pt thumb on the Workout tab sits inside a tile with a context menu,
        // and swallowing the long-press there would cost the swap gesture.
        .allowsHitTesting(onPick != nil)
        // A figure you can tap is a figure VoiceOver can walk: one element per
        // landmark, sized to the muscle's own bounds so touch-explore lands on
        // the quad and not on "image". A decorative figure stays hidden — a
        // 44 pt thumbnail with sixteen children is a thumbnail nobody can get
        // past.
        .accessibilityHidden(onPick == nil)
        .accessibilityChildren {
            if onPick != nil {
                ZStack(alignment: .topLeading) {
                    ForEach(Self.bounds(on: view, in: CGRect(origin: .zero, size: measured)), id: \.key) { item in
                        // `.position`, not `.offset`: an offset takes no part
                        // in layout, so the stack sized itself to the largest
                        // muscle and centred every frame — touch-explore
                        // landed on the muscle next door.
                        Color.clear
                            .frame(width: item.rect.width, height: item.rect.height)
                            .position(x: item.rect.midX, y: item.rect.midY)
                            // "Glutes, left" — the rotor names the side the
                            // frame actually covers, because the two frames are
                            // otherwise two identically-labelled buttons and a
                            // screen reader cannot tell them apart.
                            .accessibilityLabel(item.key.label)
                            .accessibilityValue(spoken(item.key))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { onPick?(item.key) }
                    }
                }
            }
        }
    }

    /// The gradient's line: 145° in CSS terms — 0° straight up, clockwise —
    /// so the light falls from the upper left across the whole figure and
    /// every fill, flesh or muscle, is lit from the same corner.
    private static func light(across rect: CGRect) -> (start: CGPoint, end: CGPoint) {
        let theta = 145.0 * .pi / 180
        let dir = CGPoint(x: sin(theta), y: -cos(theta))
        // CSS's gradient line, so the corners land at exactly 0 and 1 as on
        // the web — the diagonal would leave them at ~0.1 / 0.9.
        let reach = (rect.width * abs(sin(theta)) + rect.height * abs(cos(theta))) / 2
        return (
            CGPoint(x: rect.midX - dir.x * reach, y: rect.midY - dir.y * reach),
            CGPoint(x: rect.midX + dir.x * reach, y: rect.midY + dir.y * reach)
        )
    }

    /// §6.7's hairline, on every outline.
    private static let hairline: CGFloat = 0.5

    /// Each landmark-and-side the view draws, with the union of that side's
    /// paths' bounds in `rect` — the accessibility frame. Zero-size before
    /// first layout.
    ///
    /// Unioning per SIDE rather than per muscle is what makes touch-explore
    /// useful on a lateralised body: the old union of a left and a right glute
    /// was one frame spanning the whole pelvis, so a finger anywhere across the
    /// hips got the same element and the side could not be chosen by feel.
    private static func bounds(on view: OnyxAtlasView, in rect: CGRect) -> [(key: MuscleSide, rect: CGRect)] {
        var out: [MuscleSide: CGRect] = [:]
        for entry in OnyxAtlas.muscles where entry.view == view {
            guard let muscle = LandmarkMuscle(rawValue: entry.muscle) else { continue }
            let key = MuscleSide(muscle, entry.side)
            var path = Path()
            entry.build(rect, &path)
            out[key] = out[key].map { $0.union(path.boundingRect) } ?? path.boundingRect
        }
        return OnyxAtlas.sidedLandmarks(on: view).compactMap { key in out[key].map { (key, $0) } }
    }

    private func spoken(_ key: MuscleSide) -> String {
        if let value = values[key] ?? values[MuscleSide(key.muscle, .both)] { return value }
        guard let share = worked[key.muscle], share > 0 else { return "not worked" }
        return "\(Int((min(share, 1) * 100).rounded())) percent"
    }

    /// `SpatialTapGesture` rather than `onTapGesture(coordinateSpace:)`: the
    /// location has to be in the FIGURE's own space, and the figure is the
    /// aspect-fitted frame rather than the row it sits in.
    private func pick(_ view: OnyxAtlasView) -> some Gesture {
        SpatialTapGesture()
            .onEnded { tap in
                guard let onPick else { return }
                // The gesture reports in the modified view's local space, which
                // after `aspectRatio` is exactly the rect the Canvas drew into.
                if let hit = OnyxAtlas.muscle(
                    at: tap.location,
                    in: CGRect(origin: .zero, size: measured),
                    side: view
                ) {
                    onPick(hit)
                }
            }
    }

    @State private var measured: CGSize = .zero
}

#if DEBUG
#Preview("Atlas — Upper B") {
    let day = PlanTemplates.day("onyx5", "cb_b")
    let sets = MuscleCredit.weightedSets(
        day.exercises(for: .cut).map { .init(physicalSets: $0.sets(for: .cut), movers: $0.movers) }
    )
    return AtlasFigure(worked: MuscleCredit.worked(from: sets))
        .frame(height: 260)
        .padding()
        .onyxScreen(.train)
}
#endif
