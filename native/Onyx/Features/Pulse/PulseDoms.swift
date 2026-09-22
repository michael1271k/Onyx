import SwiftUI
import OnyxUI
import OnyxCore

/// Where it hurts, on the body it hurts on.
///
/// ── THE MAP IS THE INTERFACE ────────────────────────────────────────────────
/// What this replaces: a thumbnail of the body that was not a control, a
/// sentence listing the sore muscles in words, a chevron, and a sheet holding
/// nine named rows each with a five-segment picker. Two representations of one
/// nine-number fact, and the one that actually looks like a body was the one
/// you could not touch.
///
/// Now the figure IS the control — tap a muscle, rate it, done — and the words
/// are gone (§5.7: "no text label list"). The severity ramp is §3.2's: mild
/// Good, moderate Record, severe Danger, unsore left as the plain fill.
///
/// ── WHY A FLIP AND NOT TWO FIGURES SIDE BY SIDE ─────────────────────────────
/// Both bodies at once is what the old tile drew, and at tile width that is two
/// 44 pt figures — too small for a finger, let alone for a finger aiming at a
/// rear delt. One body at readable size, swiped over, keeps the hit targets big
/// enough to be a control at all. The dots say which side you are on.
struct DomsTile: View {
    let model: DayModel
    /// Whether the tile draws its own "Soreness" heading.
    ///
    /// On Pulse it must: the tile sits in a column of other tiles and the
    /// heading is what tells them apart. In `SorenessSheet` it must not —
    /// the sheet's navigation title already says Soreness 40 pt above it, and
    /// inside `LogDaySheet` the segment under it says Soreness a third time.
    /// Three labels for one control (`docs/COMPACTION_AUDIT.md` §2).
    var showsTitle = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The body is the CONTROL on this tile, so it is sized as one: a quad has
    /// to be a target a thumb can hit, and the atlas is 120 × 260 — height is
    /// what buys width. Capped, because past 360 the figure is taller than the
    /// tile it lives in.
    @ScaledMetric(relativeTo: .body) private var figureHeight: CGFloat = 280

    @State private var showingBack = false
    /// The muscle group whose popover is up, and the side the finger landed on.
    ///
    /// A GROUP, not a landmark: a sore arm is a sore arm, and rating "biceps"
    /// separately from "triceps" is a precision the body does not have. But a
    /// SIDE is a precision the body very much does have, and the tap already
    /// knew it — `OnyxAtlasHit` has always found which of a muscle's two paths
    /// the finger was in and, until W9, thrown the answer away.
    @State private var rating: Rating?
    /// Every rating tap, so one `.selection` trigger serves the whole tile.
    @State private var taps = 0

    private var severity: [String: Int] { model.domsSeverity }

    /// Muscle-and-side → severity colour, for every landmark of every sore
    /// group, on the side the rating named.
    ///
    /// ── AN AXIAL LANDMARK TAKES ONLY A `both` RATING ────────────────────────
    /// "Back, left" keys `MuscleSide(.lats, .left)` and also
    /// `MuscleSide(.upperBack, .left)` — but the trapezius is ONE path and the
    /// atlas calls it `both`, so that second key matches nothing and the traps
    /// stay unringed. That is the honest drawing: the athlete said the left of
    /// their back, and the only part of a back that HAS a left is the lat. A
    /// rating with no side keys `both` and rings the whole group, axial paths
    /// included, exactly as it did before laterality existed.
    ///
    /// ponytail: a dead key per axial landmark of a sided group, and it costs a
    /// dictionary slot nobody reads. Filtering them out means asking the atlas
    /// which landmarks are lateral, which is a second traversal to save three
    /// entries.
    private var colors: [MuscleSide: Color] {
        levels.mapValues { Color.onyx.severity($0) }
    }

    /// Muscle-and-side → severity, max-merged. Severities are merged and THEN
    /// coloured: two `Color`s have no order, so folding the ramp instead of the
    /// number would need the ramp inverted to compare anything.
    private var levels: [MuscleSide: Int] {
        var out: [MuscleSide: Int] = [:]
        for row in model.doms where row.severity > 0 {
            let side = row.bodySide
            for landmark in DomsMap.landmarks[row.muscleGroup] ?? [] {
                let key = MuscleSide(landmark, side)
                out[key] = max(out[key] ?? 0, row.severity)
            }
        }
        return out
    }

    var body: some View {
        DayTile(showsTitle ? "Soreness" : "", .recover) {
            figure
            HStack(spacing: OnyxSpace.s) {
                sideDots
                Text(caption)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        } trailing: {
            Text(showingBack ? "Back" : "Front").onyxMicro()
        }
        .sensoryFeedback(.selection, trigger: taps)
        // One `contextMenu`-shaped affordance for VoiceOver and for anyone who
        // cannot aim at a 20 pt calf: the same ten groups as named actions,
        // reachable from the rotor without a text list on screen. (Ten since
        // `Inner thighs` — the adductors were drawn on this map from the day it
        // was written and could never be rated.)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Soreness map, \(showingBack ? "back" : "front")")
        .accessibilityValue(spoken)
        .accessibilityActions {
            // The rotor offers the WHOLE muscle. The segment inside the popover
            // is where a side is chosen, so the action list stays ten items
            // rather than thirty — and a screen reader that cannot aim at a
            // 20 pt calf is exactly the reader who should not have to scroll
            // past "Calves, left" to reach "Chest".
            ForEach(DomsMap.muscles, id: \.self) { group in
                Button("Rate \(group)") { rating = Rating(group: group, side: .both) }
            }
            Button(showingBack ? "Show front" : "Show back") { flip() }
        }
    }

    // MARK: The body

    private var figure: some View {
        ZStack {
            side(.front).opacity(showingBack ? 0 : 1)
            // Counter-rotated so the back is a back and not a mirror of one.
            side(.back).opacity(showingBack ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(showingBack ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .frame(maxWidth: .infinity)
        .frame(height: min(figureHeight, 360))
        .contentShape(.rect)
        // A swipe turns the body over; §3.4 gives every drag a spring, and
        // Reduce Motion gets the cross-fade the opacity pair already provides.
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { drag in
                    if abs(drag.translation.width) > abs(drag.translation.height) { flip() }
                }
        )
        .popover(item: $rating) { target in
            SeverityPopover(
                group: target.group,
                tapped: target.side,
                current: { model.domsSeverity(target.group, side: $0) ?? 0 }
            ) { side, level in
                model.setDoms(target.group, severity: level, side: side)
                taps += 1
                rating = nil
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private func side(_ view: OnyxAtlasView) -> some View {
        // ── ONE BODY, TWO CHANNELS (§W6) ────────────────────────────────────
        // The FILL is what the ledger implies you are still carrying — sets
        // landed on a muscle, decayed by how long ago they landed. The RING is
        // what you reported. They disagree constantly and both are right: you
        // can be sore in a muscle the plan barely touched, and fresh in one
        // that took twelve sets, and that disagreement is the most interesting
        // thing either of them has to say.
        //
        // A second figure beside this one would make the reader do the
        // comparison; two fills on one figure cannot both be seen. A ring can.
        //
        // The fill is MONOCHROME in the recover accent rather than the sixteen
        // family hues. Recovery is one quantity — how loaded, nothing else —
        // and painting it in per-muscle hues would say that a loaded quad and a
        // loaded lat differ in kind. The family language belongs on the session
        // figure, which answers "where did this land", not "how much is left".
        //
        // Only the SORE landmarks are ringed: `AtlasFigure` draws an unrated
        // muscle as the plain fill, and the hit test walks `OnyxAtlas.muscles`
        // rather than either dictionary — so the whole body is tappable whether
        // or not any of it hurts or is loaded.
        AtlasFigure(
            side: view == .front ? .front : .back,
            worked: model.window.fatigue,
            monochromeTint: Color.onyx.accent(.recover),
            values: spokenValues,
            outlined: colors,
            onPick: { hit in
                guard let group = DomsMap.group(of: hit.muscle) else { return }
                // The side the finger landed in is the popover's PRE-SELECTION
                // and never its verdict: the segment at the head of the sheet
                // is right there to say "actually both", so aiming at a glute
                // costs nothing and aiming at the right one saves a tap.
                rating = Rating(group: group, side: hit.side)
            }
        )
        .frame(maxWidth: .infinity)
    }

    /// Landmark → "Moderate · still loaded", for VoiceOver's walk over the body.
    ///
    /// BOTH channels, because a screen reader gets one string per muscle and
    /// dropping either one would leave the sighted figure saying something the
    /// spoken one does not. The report leads: it is the thing the user typed
    /// and the thing a tap is about to change.
    private var spokenValues: [MuscleSide: String] {
        var out: [MuscleSide: String] = [:]
        let reported = levels
        for landmark in LandmarkMuscle.allCases {
            for side in BodySide.allCases {
                // The side's OWN rating, or the whole-muscle one, whichever is
                // worse: a right glute rated `severe` on a muscle that also
                // carries a `both` row reads as the severe one, which is what
                // the ring under the finger is drawing.
                let level = max(reported[MuscleSide(landmark, side)] ?? 0, reported[MuscleSide(landmark, .both)] ?? 0)
                let words = DomsMap.levels[min(level, DomsMap.maxSeverity)]
                let key = MuscleSide(landmark, side)
                guard let loaded = model.window.fatigue[landmark] else { out[key] = words; continue }
                out[key] = "\(words) · \(MuscleRecovery.label(loaded).lowercased())"
            }
        }
        return out
    }

    private func flip() {
        withAnimation(reduceMotion ? OnyxMotion.fade : OnyxMotion.move) { showingBack.toggle() }
    }

    private var sideDots: some View {
        HStack(spacing: OnyxSpace.xs) {
            ForEach([false, true], id: \.self) { back in
                Circle()
                    .fill(showingBack == back ? Color.onyx.accent(.recover) : Color.onyx.hairline)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    /// What caused it, when the row says — `doms_logs` carries the session that
    /// is credited (`source_day_key`). When nothing does, the caption is the
    /// protocol instead, because "rate this in 24 hours" is the only thing an
    /// empty soreness map has to say.
    private var caption: String {
        // ── THE LOADED MUSCLES COME FIRST ───────────────────────────────────
        // The fill is the channel with no words on it — a ring at least carries
        // a colour from a ramp the user chose — so the caption is where the
        // model gets to say what it thinks. Naming the two or three muscles
        // most likely to limit today is the only actionable sentence either
        // channel produces.
        //
        // The tap hint RIDES ALONG rather than being replaced. The first build
        // swapped one for the other, and since something is loaded on most days
        // of a training week, the only sentence telling you this figure is a
        // control would have been absent nearly always — on a tile whose entire
        // premise is that the body IS the interface.
        let loaded = MuscleRecovery.mostLoaded(model.window.fatigue, limit: 2)
        if !loaded.isEmpty {
            return "Still loaded: " + loaded.map { $0.0.rawValue }.joined(separator: ", ") + " · tap to rate"
        }
        let credited = model.doms.compactMap(\.sourceDayKey).first
        if let credited, let label = SessionAnalysis.dayLabel(credited, in: model.program) {
            return "Credited to \(label)"
        }
        return "Tap a muscle · swipe to turn"
    }

    private var spoken: String {
        DomsMap.summary(severity) ?? "nothing sore"
    }

    /// What the popover is about: a group, and the side the tap landed on.
    ///
    /// `popover(item:)` wants an `Identifiable`, and the id has to carry the
    /// SIDE as well as the group — presenting "Glutes, left" while "Glutes,
    /// right" is already up must re-present the sheet, and an id of the group
    /// alone reads as the same item and leaves the old side on screen.
    private struct Rating: Identifiable, Equatable {
        let group: String
        let side: BodySide
        var id: String { "\(group)-\(side.rawValue)" }
    }
}

/// Four words, one tap each — and, above them, which side you meant.
///
/// A popover rather than a sheet: the answer is one of four and the question is
/// "this muscle" — a half-screen sheet for that loses the body you were just
/// pointing at, which is the context that makes the question answerable.
///
/// ── THE SEGMENT IS A CORRECTION, NOT A STEP ─────────────────────────────────
/// It opens PRE-SELECTED to the side the finger landed on, so the common case
/// is still one tap: aim at the right glute, pick a severity, done. The segment
/// exists for the two cases the tap cannot express — "both, actually", and "I
/// hit the wrong one" — and for the muscles the atlas draws as one shape, where
/// the tap can only ever answer `both` and the segment is the only way to say
/// otherwise.
///
/// Whole words for `Both` and single letters for `L` and `R`: three full words
/// do not fit a 220 pt popover at AX sizes, and `B` alone is the one of the
/// three that is genuinely ambiguous on a body.
/// Not `private`: a popover only exists under a finger, so the shot loop cannot
/// reach it through the tile. `PulsePreviews` renders it directly (the same
/// trick W8 used on `SignedInTabs`), and a control nobody can photograph is a
/// control nobody reviews.
struct SeverityPopover: View {
    let group: String
    /// Where the finger landed. The initial selection, and nothing more.
    let tapped: BodySide
    /// This group's stored severity for a side — read per side, because the
    /// tick has to move when the segment does.
    let current: (BodySide) -> Int
    let onPick: (BodySide, Int) -> Void

    @State private var side: BodySide

    init(group: String, tapped: BodySide, current: @escaping (BodySide) -> Int, onPick: @escaping (BodySide, Int) -> Void) {
        self.group = group
        self.tapped = tapped
        self.current = current
        self.onPick = onPick
        _side = State(initialValue: tapped)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.uppercased())
                .onyxMicro()
                .padding(.horizontal, OnyxSpace.m)
                .padding(.top, OnyxSpace.m)
                .padding(.bottom, OnyxSpace.s)
            Picker("Side", selection: $side) {
                ForEach(BodySide.allCases, id: \.self) { option in
                    Text(option == .both ? "Both" : option.mark)
                        .accessibilityLabel(option.label)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, OnyxSpace.m)
            .padding(.bottom, OnyxSpace.s)
            .accessibilityLabel("Side")
            ForEach(Array(DomsMap.levels.enumerated()), id: \.offset) { level, label in
                Button { onPick(side, level) } label: {
                    HStack(spacing: OnyxSpace.s) {
                        Circle()
                            .fill(Color.onyx.severity(level))
                            .frame(width: 8, height: 8)
                        Text(label)
                            .onyxType(.body)
                            .foregroundStyle(Color.onyx.textPrimary)
                        Spacer(minLength: OnyxSpace.l)
                        if level == current(side) {
                            Image(systemName: "checkmark")
                                .onyxType(.caption).fontWeight(.bold)
                                .foregroundStyle(Color.onyx.accent(.recover))
                        }
                    }
                    .padding(.horizontal, OnyxSpace.m)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(level == current(side) ? .isSelected : [])
            }
        }
        .frame(minWidth: 220)
        .presentationBackground(Color.onyx.base)
    }
}

/// The atlas at the size it is a control at, in a sheet.
///
/// `.large` alone rather than `[.medium, .large]`: the figure is 280 pt before
/// its caption, and a medium detent opens onto a body cropped at the ribs —
/// which is the half you cannot aim a thumb at.
struct SorenessSheet: View {
    let model: DayModel

    var body: some View {
        DaySheet("Soreness", domain: .recover, glass: false, detents: [.large]) {
            ScrollView {
                DomsTile(model: model, showsTitle: false)
                    .padding(OnyxSpace.l)
            }
            .scrollContentBackground(.hidden)
            .onyxScreen(.recover)
        }
    }
}
