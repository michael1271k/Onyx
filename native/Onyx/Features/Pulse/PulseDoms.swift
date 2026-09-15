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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The body is the CONTROL on this tile, so it is sized as one: a quad has
    /// to be a target a thumb can hit, and the atlas is 120 × 260 — height is
    /// what buys width. Capped, because past 360 the figure is taller than the
    /// tile it lives in.
    @ScaledMetric(relativeTo: .body) private var figureHeight: CGFloat = 280

    @State private var showingBack = false
    /// The muscle group whose popover is up. A GROUP, not a landmark: a sore
    /// arm is a sore arm, and rating "biceps" separately from "triceps" is a
    /// precision the body does not have.
    @State private var rating: String?
    /// Every rating tap, so one `.selection` trigger serves the whole tile.
    @State private var taps = 0

    private var severity: [String: Int] { model.domsSeverity }

    /// Landmark → severity colour, for every landmark of every sore group.
    private var colors: [LandmarkMuscle: Color] {
        var out: [LandmarkMuscle: Color] = [:]
        for (group, level) in severity where level > 0 {
            for landmark in DomsMap.landmarks[group] ?? [] {
                out[landmark] = Color.onyx.severity(level)
            }
        }
        return out
    }

    var body: some View {
        DayTile("Soreness", .recover) {
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
            ForEach(DomsMap.muscles, id: \.self) { group in
                Button("Rate \(group)") { rating = group }
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
        .popover(item: Binding(get: { rating.map(Group.init) }, set: { rating = $0?.name })) { group in
            SeverityPopover(
                group: group.name,
                current: severity[group.name] ?? 0
            ) { level in
                model.setDoms(group.name, severity: level)
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
            onPick: { landmark in
                guard let group = DomsMap.group(of: landmark) else { return }
                rating = group
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
    private var spokenValues: [LandmarkMuscle: String] {
        var out: [LandmarkMuscle: String] = [:]
        for (group, landmarks) in DomsMap.landmarks {
            let level = severity[group] ?? 0
            for landmark in landmarks {
                let reported = DomsMap.levels[min(level, DomsMap.maxSeverity)]
                guard let loaded = model.window.fatigue[landmark] else { out[landmark] = reported; continue }
                out[landmark] = "\(reported) · \(MuscleRecovery.label(loaded).lowercased())"
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

    /// `popover(item:)` wants an `Identifiable`; a muscle group is a `String`.
    private struct Group: Identifiable {
        let name: String
        var id: String { name }
    }
}

/// Four words, one tap each.
///
/// A popover rather than a sheet: the answer is one of four and the question is
/// "this muscle" — a half-screen sheet for that loses the body you were just
/// pointing at, which is the context that makes the question answerable.
private struct SeverityPopover: View {
    let group: String
    let current: Int
    let onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.uppercased())
                .onyxMicro()
                .padding(.horizontal, OnyxSpace.m)
                .padding(.top, OnyxSpace.m)
                .padding(.bottom, OnyxSpace.s)
            ForEach(Array(DomsMap.levels.enumerated()), id: \.offset) { level, label in
                Button { onPick(level) } label: {
                    HStack(spacing: OnyxSpace.s) {
                        Circle()
                            .fill(Color.onyx.severity(level))
                            .frame(width: 8, height: 8)
                        Text(label)
                            .onyxType(.body)
                            .foregroundStyle(Color.onyx.textPrimary)
                        Spacer(minLength: OnyxSpace.l)
                        if level == current {
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
                .accessibilityAddTraits(level == current ? .isSelected : [])
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
                DomsTile(model: model)
                    .padding(OnyxSpace.l)
            }
            .scrollContentBackground(.hidden)
            .onyxScreen(.recover)
        }
    }
}
