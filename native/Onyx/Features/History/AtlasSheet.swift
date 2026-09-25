import SwiftUI
import OnyxUI
import OnyxCore

/// Where the session landed, on a body you can turn over.
///
/// ── WHY A FLIP AND NOT TWO FIGURES SIDE BY SIDE (decision 7) ────────────────
/// `AtlasFigure(side: .both)` draws the front and the back as an `HStack`,
/// which is the right answer at thumbnail size and the wrong one on a sheet:
/// two 150 pt bodies is two bodies too small to hit-test with a thumb, and it
/// says the front and the back are two separate pictures. They are one body.
///
/// So there is ONE figure and it rotates. A drag turns it about its own Y axis
/// and the far side comes round; the two faces occupy the same rectangle, so
/// the whole width goes to whichever one you are reading. Which is also why the
/// hamstrings and the glutes stop being an afterthought below the fold.
///
/// ── THE THREE THINGS THAT MAKE IT READ AS A SOLID ───────────────────────────
///  1. **Depth shading.** `|sin θ|` darkens the figure as it turns edge-on, so
///     the swap between the two faces happens at the moment the body is a dark
///     sliver — the way a real object's far side is never visible mid-turn. A
///     hard cut at 90° with both faces at full brightness reads as two images
///     being switched, which is exactly what it is and exactly what it must not
///     look like.
///  2. **Parallax.** The caption under the figure counter-moves by a few points
///     against the turn. A rigid label under a rotating object is the tell that
///     the object is a texture on a plane.
///  3. **Velocity handoff.** The release is projected forward (the scroll
///     deceleration curve from *Designing Fluid Interfaces*), snapped to the
///     nearest half turn and animated with `OnyxMotion.flick` — a finger that
///     throws the body past 90° must not have it fall back.
///
/// ── AND WHY THE GESTURE IS NOT THE ONLY WAY ─────────────────────────────────
/// A control that exists only as a drag is a control nobody with a switch, a
/// pointer or Reduce Motion can reach. The segmented `Front | Back` above the
/// figure sets the same angle, VoiceOver walks the landmarks (`AtlasFigure`
/// builds one element per muscle), and under Reduce Motion the two faces
/// cross-fade instead of turning.
struct AtlasSheet: View {

    /// Weighted credit per landmark, and the count of sets that produced it —
    /// the same two values `MuscleDistributionSheet` takes, because they are
    /// what `SessionAnalysis.Report` and `LoggerModel` both already hold.
    let sets: [LandmarkMuscle: Double]
    let physicalSets: Int
    /// What the share sheet says this session was: "Upper A · 30 Aug".
    let sessionLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var valueWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var dotMetric: CGFloat = 8

    /// Degrees of turn that have been COMMITTED. `live` is what the finger is
    /// adding right now, and it is folded in on release rather than reset —
    /// resetting it and animating `turn` from its old value is the "animate
    /// from the target, not the presentation value" jump.
    @State private var turn: Double
    @State private var live: Double = 0
    @State private var picked: Picked?
    /// Which way the finger committed on this drag. `nil` until it is past the
    /// threshold in one axis — see `spin`.
    @State private var horizontal: Bool?

    init(sets: [LandmarkMuscle: Double], physicalSets: Int, sessionLabel: String) {
        self.sets = sets
        self.physicalSets = physicalSets
        self.sessionLabel = sessionLabel
        // ── THE OPENING FACE IS DECIDED HERE, NOT IN A `.task` ──────────────
        // Setting it after the first render turned the body 180° in one
        // unanimated frame AND crossed `showsBack`, which fired the selection
        // haptic on presentation — a body that jumps and buzzes as the sheet
        // arrives. `sets` is available in `init`, so the state can simply start
        // where it belongs.
        //
        // Always-Front is right for a chest day and wrong for every pull: the
        // sheet's question is "where did it land", and it may as well open on
        // the half where most of it did.
        func credit(_ side: OnyxAtlasView) -> Double {
            OnyxAtlas.landmarks(on: side).reduce(0) { $0 + (sets[$1] ?? 0) }
        }
        _turn = State(initialValue: credit(.back) > credit(.front) ? 180 : 0)
    }

    private var angle: Double { turn + live }

    /// 0…360, so the face test and the shading agree at every multiple.
    private var wrapped: Double {
        let m = angle.truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }

    private var showsBack: Bool { wrapped > 90 && wrapped < 270 }

    /// 0 face-on, 1 edge-on.
    private var edgeOn: Double { abs(sin(angle * .pi / 180)) }

    private var worked: [LandmarkMuscle: Double] { MuscleCredit.worked(from: sets) }

    private var weightedTotal: Double { sets.values.reduce(0, +) }

    /// Ranked, heaviest first, ties broken on the landmark's own order so the
    /// legend cannot reshuffle between two redraws.
    private var ranked: [(muscle: LandmarkMuscle, sets: Double)] {
        LandmarkMuscle.allCases
            .compactMap { m in sets[m].flatMap { $0 > 0 ? (m, $0) : nil } }
            .sorted { a, b in
                a.1 == b.1
                    ? (LandmarkMuscle.allCases.firstIndex(of: a.0) ?? 0) < (LandmarkMuscle.allCases.firstIndex(of: b.0) ?? 0)
                    : a.1 > b.1
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OnyxSpace.l) {
                    counts
                    faceSwitch
                    stage
                    if ranked.isEmpty {
                        ContentUnavailableView(
                            "Nothing landed here",
                            systemImage: "figure.strengthtraining.traditional",
                            description: Text("No working sets on this session.")
                        )
                    } else {
                        legend
                    }
                    Text("Drag the body to turn it over. Tap a muscle to share what it took. Direct work counts 1.0, assistance 0.5; warm-ups count, ghost sets do not.")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(OnyxSpace.l)
            }
            .onyxScreen(.train)
            .navigationTitle("Where it landed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // §3.4 gives `.selection` to a control changing value, and the body
        // coming round is exactly that — fired on the FACE rather than on every
        // degree, so a slow turn ticks once.
        .sensoryFeedback(.selection, trigger: showsBack)
    }

    // MARK: - The two totals

    /// ── TWO COLUMNS, OR TWO ROWS ────────────────────────────────────────────
    /// `onyxMicro` is upper-case and tracked out — right at 11 pt, and at the
    /// accessibility sizes it is what turns "PHYSICAL SETS" into "PHYSI-/CAL/
    /// SETS" in a half-width column: three lines and a hyphen mid-word, taking
    /// the pair to ~600 pt and pushing the BODY, which is the whole sheet,
    /// below the fold.
    ///
    /// Side by side is a comparison — two counts of the same session by two
    /// rules — and it stops being one the moment either label needs three
    /// lines. Full-width rows read the same fact in a quarter of the height,
    /// with the label beside its number instead of under it.
    private var counts: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: OnyxSpace.grid))
            : AnyLayout(HStackLayout(spacing: OnyxSpace.grid))
        return layout {
            countTile(OnyxFormat.sets(Double(physicalSets)), "Physical sets", Color.onyx.textPrimary)
            countTile(OnyxFormat.sets(weightedTotal), "Weighted sets", Color.onyx.accent(.train))
        }
    }

    private func countTile(_ value: String, _ label: String, _ color: Color) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let inner = stacked
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: OnyxSpace.s))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: OnyxSpace.xs))
        return inner {
            Text(value).onyxHero().foregroundStyle(color)
            if stacked {
                Text(label)
                    .onyxType(.body)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(label).onyxMicro()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OnyxSpace.m)
        .onyxGlass(.tile)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Front | Back

    /// The same fact the gesture states, as a control — and the only way to
    /// reach the back face under Reduce Motion, with a pointer, or with Switch
    /// Control.
    private var faceSwitch: some View {
        Picker("Side", selection: Binding(
            get: { showsBack },
            set: { back in
                // The SHORTEST way round from wherever the finger left it, so
                // tapping the segment you are already nearly on does not send
                // the body all the way through the long side.
                // Folded first, exactly as `spin.onEnded` does. Assigning
                // `turn` absolutely while a drag is still in flight — or after
                // one was cancelled without `onEnded`, which leaves `live`
                // standing — jumps the body by whatever the finger had added.
                turn += live
                live = 0
                let from = turn
                let target = (from / 360).rounded() * 360 + (back ? 180 : 0)
                let alternative = target + (target > from ? -360 : 360)
                let nearest = abs(target - from) <= abs(alternative - from) ? target : alternative
                withAnimation(reduceMotion ? OnyxMotion.fade : OnyxMotion.move) {
                    turn = nearest
                }
            }
        )) {
            Text("Front").tag(false)
            Text("Back").tag(true)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - The body

    /// Both faces in one rectangle, one of them turned half a revolution so it
    /// is upright when it arrives.
    ///
    /// ── WHY BOTH ARE ALWAYS IN THE TREE ─────────────────────────────────────
    /// `opacity` rather than an `if`: a face rebuilt on the frame it becomes
    /// visible is a `Canvas` re-rendering thirty-five paths in the middle of a
    /// gesture, and the drop shows. Both are drawn all the way through and the
    /// hidden one costs a composite.
    private var stage: some View {
        ZStack {
            ground
            face(.front, at: angle)
            face(.back, at: angle + 180)
        }
        .frame(height: figureHeight)
        .frame(maxWidth: .infinity)
        // Shading over the WHOLE stage rather than per face: the two are the
        // same solid and a seam between their shadows is the seam this exists
        // to hide.
        .overlay {
            Color.black
                .opacity(0.75 * edgeOn)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) { callout }
        .contentShape(.rect)
        // ── SIMULTANEOUS, AND AXIS-LOCKED ───────────────────────────────────
        // `.gesture` alone WINS against the enclosing `ScrollView`'s pan, so a
        // 300 pt figure filling most of a large sheet became a dead zone: you
        // could not scroll to the legend by dragging on the body, which is the
        // obvious place to put a thumb. Simultaneous keeps the scroll, and the
        // axis lock is what stops a vertical flick from also spinning the body
        // on its way past.
        .simultaneousGesture(spin)
        .padding(.bottom, OnyxSpace.s)
        .accessibilityAction(named: "Turn over") {
            withAnimation(reduceMotion ? OnyxMotion.fade : OnyxMotion.move) {
                turn += live + 180
                live = 0
            }
        }
    }

    /// The light the body turns in front of — and the parallax.
    ///
    /// It slides the opposite way to the face by a fraction of the turn, so the
    /// figure has something to move AGAINST. Without it the rotation is a
    /// transform on a plane with nothing behind it, which the eye reads as a
    /// card flipping rather than a solid turning. Purely decorative and
    /// hit-testing nothing.
    private var ground: some View {
        RadialGradient(
            colors: [Color.onyx.accent(.train).opacity(0.20), .clear],
            center: .center, startRadius: 0, endRadius: figureHeight * 0.55
        )
        .offset(x: -sin(angle * .pi / 180) * 28)
        .blur(radius: 24)
        .opacity(reduceMotion ? 0.6 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// §5.7's gauge sizing rule, applied to a body: a FIXED height sets its own
    /// type at AX5 and the accessible frames come out of the wrong rectangle.
    /// It grows with the setting and is capped where it stops fitting a phone.
    @ScaledMetric(relativeTo: .title) private var figureSize: CGFloat = 300
    private var figureHeight: CGFloat { min(figureSize, 380) }

    private func face(_ side: AtlasFigure.Side, at degrees: Double) -> some View {
        AtlasFace(
            side: side,
            worked: worked,
            spoken: spoken,
            onPick: { hit in pick(hit.muscle) }
        )
        .equatable()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Reduce Motion turns the turn into a cross-fade: the face that is
        // "forward" is simply the opaque one. `rotation3DEffect` is skipped
        // entirely rather than run at zero, because a perspective transform is
        // still a vestibular effect when the angle changes in one step.
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : degrees),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.4
        )
        // Face-on is 1, edge-on is 0 — and it crosses zero exactly where the
        // shading is at its darkest, so nothing is ever caught half-visible.
        .opacity(visible(at: degrees) ? 1 : 0)
        .allowsHitTesting(visible(at: degrees) && edgeOn < 0.5)
        // Opacity does NOT take a view out of the accessibility tree, and
        // `AtlasFigure` publishes one button per landmark — so the rotor walked
        // sixteen muscles on the face nobody can see, and activating one fired
        // `onPick` for a muscle that is not drawn.
        .accessibilityHidden(!visible(at: degrees))
    }

    private func visible(at degrees: Double) -> Bool {
        cos(degrees * .pi / 180) >= 0
    }

    /// 1:1 with the finger while it is down, projected forward when it leaves.
    ///
    /// 0.6 degrees per point: a 300 pt swipe is 180°, so one comfortable drag
    /// across the figure turns it exactly once. Anything faster overshoots on
    /// every casual scroll-adjacent movement.
    private var spin: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Decided once per drag, on the first movement past the
                // threshold, and never revisited — a lock that can flip
                // mid-drag is a body that starts turning halfway down a scroll.
                if horizontal == nil {
                    horizontal = abs(value.translation.width) > abs(value.translation.height)
                }
                guard horizontal == true else { return }
                live = value.translation.width * 0.6
                if picked != nil { picked = nil }
            }
            .onEnded { value in
                defer { horizontal = nil }
                guard horizontal == true else { return }
                // Fold BEFORE animating: `live` going to zero while `turn`
                // animates from its old value is a visible jump back through
                // everything the finger just did.
                turn += live
                live = 0
                let projected = turn + Self.project(value.velocity.width * 0.6)
                withAnimation(reduceMotion ? OnyxMotion.fade : OnyxMotion.flick) {
                    turn = (projected / 180).rounded() * 180
                }
            }
    }

    /// Where a flick comes to rest — the exponential-decay projection iOS's own
    /// scroll views use, not the textbook `v² / 2a`.
    private static func project(_ velocity: Double, deceleration: Double = 0.998) -> Double {
        (velocity / 1000) * deceleration / (1 - deceleration)
    }

    // MARK: - Sharing a landmark

    /// One muscle, picked off the body.
    ///
    /// `Identifiable` on the landmark itself so the callout is re-created (and
    /// re-springs) when the finger moves to a different muscle rather than
    /// silently swapping its text.
    private struct Picked: Identifiable, Equatable {
        let muscle: LandmarkMuscle
        let sets: Double
        var id: LandmarkMuscle { muscle }
    }

    private func pick(_ muscle: LandmarkMuscle) {
        withAnimation(OnyxMotion.drawer) {
            picked = picked?.muscle == muscle ? nil : Picked(muscle: muscle, sets: sets[muscle] ?? 0)
        }
    }

    /// ── WHY THE TAP REVEALS A SHARE RATHER THAN FIRING ONE ──────────────────
    /// §U4.4 asks for "landmark tap → share". A tap on a BODY that throws the
    /// system share sheet straight up is a modal you did not ask for on a
    /// surface whose whole job is to be dragged — and the first thing a finger
    /// does here is turn the figure, which would fire it by accident on every
    /// short drag. So the tap states the reading and the reading IS the share
    /// button: one object, anchored at what it describes (§7 spatial
    /// consistency), gone again on the next turn.
    @ViewBuilder
    private var callout: some View {
        if let picked {
            ShareLink(item: sentence(picked)) {
                HStack(spacing: OnyxSpace.s) {
                    Circle()
                        .fill(Color.onyx.muscle(picked.muscle))
                        .frame(width: dot, height: dot)
                    Text(picked.muscle.displayName)
                        .onyxType(.body).fontWeight(.semibold)
                        .foregroundStyle(Color.onyx.textPrimary)
                    Text(OnyxFormat.sets(picked.sets))
                        .onyxType(.body).onyxNumeral()
                        .foregroundStyle(Color.onyx.textSecondary)
                    Image(systemName: "square.and.arrow.up")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.accent(.train))
                }
                .padding(.horizontal, OnyxSpace.m)
                .frame(minHeight: 44)
                .onyxGlass(.chrome)
                .clipShape(.capsule)
            }
            .buttonStyle(.plain)
            .onyxPress()
            .transition(.scale(scale: 0.85).combined(with: .opacity))
            .accessibilityHint("Shares this muscle's share of the session")
        }
    }

    private func sentence(_ picked: Picked) -> String {
        "\(sessionLabel) — \(picked.muscle.displayName): \(OnyxFormat.sets(picked.sets)) weighted sets of \(OnyxFormat.sets(weightedTotal))."
    }

    /// What VoiceOver reads on a landmark, and what the callout would say.
    ///
    /// Keyed `both`, and that is the whole of this screen's relationship with
    /// laterality (W9): the figure answers "where did this session land", and
    /// the ledger behind it records that a set of squats happened, not which
    /// leg did more of it. A `both` key lights and speaks for the left path and
    /// the right path alike, so a tap on either glute states the same share —
    /// which is the truthful answer, where a side-specific number here would be
    /// one the store never held.
    private var spoken: [MuscleSide: String] {
        Dictionary(uniqueKeysWithValues: ranked.map {
            (MuscleSide($0.muscle, .both), "\(OnyxFormat.sets($0.sets)) weighted sets")
        })
    }

    // MARK: - The ranking

    /// The legend's colour dot, scaled with the body type and capped.
    ///
    /// A fixed 8 pt bullet is about 47 % of cap height at the default size and
    /// about 15 % at AX5 — it shrinks, relatively, exactly where the reader
    /// needs it most. Capped at 16 because past that it stops being a bullet.
    private var dot: CGFloat { min(dotMetric, 16) }

    private var legend: some View {
        VStack(spacing: 0) {
            ForEach(Array(ranked.enumerated()), id: \.element.muscle) { i, entry in
                row(entry)
                if i < ranked.count - 1 { Divider().overlay(Color.onyx.hairline) }
            }
        }
        .padding(.horizontal, OnyxSpace.m)
        .onyxGlass(.tile)
    }

    private func row(_ entry: (muscle: LandmarkMuscle, sets: Double)) -> some View {
        let tint = Color.onyx.muscle(entry.muscle)
        let stacked = typeSize.isAccessibilitySize
        return Button { pick(entry.muscle) } label: {
            // ── THE BAR MOVES AT AX5, IT DOES NOT LEAVE ─────────────────────
            // It used to be dropped outright at accessibility sizes, which made
            // this the one list in the app where colour identification got WORSE
            // as the type got bigger: the 72 pt sample went and the 8 pt dot
            // stayed, beside 53 pt text. Since W3 the dot is one of sixteen
            // landmark hues rather than one of four accents, and the bar is also
            // the redundant, non-colour channel a deuteranomalous reader is
            // using — so at AX5 it goes full width UNDER the row instead.
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                HStack(spacing: OnyxSpace.grid) {
                    Circle().fill(tint).frame(width: dot, height: dot)
                    Text(entry.muscle.displayName)
                        .onyxType(.body)
                        .foregroundStyle(Color.onyx.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: OnyxSpace.s)
                    if !stacked { share(entry.sets, tint: tint) }
                    Text(OnyxFormat.sets(entry.sets))
                        .onyxType(.body).fontWeight(.semibold).onyxNumeral()
                        .foregroundStyle(Color.onyx.textPrimary)
                        .lineLimit(1)
                        // A fixed 34 pt column holds "4.5" at the default size and
                        // wraps it at AX5. The column scales with the type it is
                        // sized for.
                        .frame(width: valueWidth, alignment: .trailing)
                }
                if stacked { share(entry.sets, tint: tint, width: nil) }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Selects it on the body")
    }

    /// `width: nil` fills the row instead of taking a fixed 72 pt column.
    private func share(_ value: Double, tint: Color, width: CGFloat? = 72) -> some View {
        let peak = ranked.first?.sets ?? value
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.onyx.hairline)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * (peak > 0 ? value / peak : 0))
            }
        }
        .frame(width: width, height: 4)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .accessibilityHidden(true)
    }
}

/// One face of the turnable body, repainted only when what it SHOWS changes.
///
/// ── WHY EQUATABLE (Precision F1) ────────────────────────────────────────────
/// A drag re-evaluates the sheet's body on every frame (`live` is state), and
/// a `Canvas` whose closure is rebuilt repaints — so both 300–380 pt faces
/// re-drew thirty-five paths per frame of a turn that moves nothing on them:
/// the turn is `rotation3DEffect`, a transform. The écorché made that paint a
/// glow layer and a sheen per muscle, so the sheet now compares what the face
/// draws and skips the repaint. `onPick` is left out of the comparison: it
/// only reaches the sheet's `@State`, which a kept closure reaches too.
private struct AtlasFace: View, Equatable {
    let side: AtlasFigure.Side
    let worked: [LandmarkMuscle: Double]
    let spoken: [MuscleSide: String]
    let onPick: (MuscleSide) -> Void

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.side == b.side && a.worked == b.worked && a.spoken == b.spoken
    }

    var body: some View {
        AtlasFigure(side: side, worked: worked, values: spoken, onPick: onPick)
    }
}

#if DEBUG
#Preview("Atlas — Upper B") {
    let day = PlanTemplates.day("onyx5", "cb_b")
    let sets = MuscleCredit.weightedSets(
        day.exercises(for: .cut).map { .init(physicalSets: $0.sets(for: .cut), movers: $0.movers) }
    )
    return AtlasSheet(sets: sets, physicalSets: 18, sessionLabel: "Upper B · 30 Aug")
}
#endif
