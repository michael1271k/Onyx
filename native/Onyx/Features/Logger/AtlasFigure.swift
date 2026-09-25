import SwiftUI
import OnyxUI
import OnyxCore

/// The body, tinted by where the session landed.
///
/// `OnyxAtlas.swift` (OnyxUI) is GENERATED from `scripts/src/atlas.ts` and
/// holds only geometry; `npm run check:atlas` re-runs the generator and fails
/// when the Swift differs, so the widget and this screen can never disagree
/// about where a muscle is.
///
/// WHAT to light is this figure's decision — a colour per muscle and side,
/// resolved below — and HOW is `AtlasPainter`'s (OnyxUI, Precision F1), the
/// one painter the widget's `OnyxAtlasFigure` draws with too. The material is
/// the écorché — flesh along the fibres, ivory tendon and bone, the lit
/// muscles in their own ink with a glow — except for a monochrome thumbnail
/// and under Reduce Transparency, which keep the flat figure that shipped
/// before (`AtlasMaterial.figure`).
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
    /// A 44 pt figure in a tile: LITE — no drop shadow (flat) and no glow or
    /// sheen (écorché), because a 10 pt blur is invisible at that size and
    /// costs an offscreen pass per tile. With `monochromeTint` it also picks
    /// the flat material (`AtlasMaterial.figure`).
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

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.onyxForcesReducedTransparency) private var forcedReduceTransparency

    /// Flat for a monochrome THUMBNAIL and under Reduce Transparency; a
    /// thumbnail is also LITE (no glow, no sheen, no shadow — offscreen passes
    /// nobody can see at 28–44 pt).
    private var painter: AtlasPainter {
        AtlasPainter(
            material: .figure(
                monochrome: monochromeTint != nil,
                thumbnail: isThumbnail,
                reduceTransparency: systemReduceTransparency || forcedReduceTransparency
            ),
            isLite: isThumbnail
        )
    }

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
        let painter = painter
        return Canvas { context, size in
            painter.paint(
                &context,
                in: CGRect(origin: .zero, size: size),
                view: view,
                mark: { entry in
                    LandmarkMuscle(rawValue: entry.muscle)
                        .flatMap { resolved[MuscleSide($0, entry.side)] }
                        .map { AtlasPainter.Mark(ink: $0.0, share: $0.1) }
                },
                ring: { entry in
                    LandmarkMuscle(rawValue: entry.muscle).flatMap {
                        outlined[MuscleSide($0, entry.side)] ?? outlined[MuscleSide($0, .both)]
                    }
                }
            )
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
