import SwiftUI
import OnyxCore
import OnyxUI

/// A set's identity, in one box — the ordinal it is, the state it is in, and
/// the record it won.
///
/// ── WHY THIS IS ONE TYPE AND NOT TWO DRAWINGS ───────────────────────────────
/// Two screens draw a set: the live deck (`ExerciseCardView.SetRowView`) and
/// the session ledger (`SessionDetailView.SetRow`). They had arrived at two
/// different objects for it. The deck drew a 32 pt rounded rectangle in the
/// movement's own hue, filled when logged, outlined for a warm-up, dashed for a
/// ghost. The ledger drew a 22 pt grey CIRCLE that swapped its number for a
/// trophy. Same set, same session, two shapes and two colour languages — and
/// the ledger is the screen you land on ten seconds after the deck, which is
/// the shortest possible distance between two answers to one question.
///
/// So the deck's language wins (it is the one with states to express) and the
/// ledger adopts it. What the ledger keeps is its own SIZE: nothing on that
/// page is tappable, its rows are 33 pt rather than 44, and a 32 pt badge in a
/// 33 pt row is a box with no air around it.
///
/// ── THE RECORD TREATMENT, IN ONE PLACE ──────────────────────────────────────
/// A record badge used to be solid gold on the deck and a pale gold disc in the
/// ledger, and both spent the movement's hue to say it. Gold means "never
/// beaten" app-wide and is the only fifth hue §3.2 allows, so it is spent on
/// the GLYPH — with a soft glow, which is what makes a 13 pt cup read as an
/// achievement on a dim screen — and the box stays the movement's, at the 16 %
/// every chip in this app wears, with a 1.5 pt ring to carry the hue at this
/// size. Composed rather than blended: mixing gold with sixteen muscle hues
/// would spend it sixteen times and leave none of them recognisable.
struct SetBadge: View {

    /// What the box says when nothing outranks it: `3`, `W`, `G`.
    let label: String
    /// The movement's own hue — `Color.onyx.muscle`, or the cardio token.
    let tint: Color
    /// Warm-up, ghost and drop-set are drawn as treatments rather than as
    /// letters, so the kind has to reach the surface and not only the label.
    var kind: LoggerModel.SetKind = .normal
    /// Logged. A filled box is a performed set; an empty one is a proposal.
    var filled: Bool = true
    var isRecord: Bool = false
    var isFailure: Bool = false
    /// The deck replaces the ordinal with a tick once the set is logged, which
    /// is right there and wrong in the ledger: EVERY set on that page is
    /// logged, so a card of ticks would lose the one column that places a set
    /// inside its movement.
    var showsCheck: Bool = false
    var side: CGFloat = 32

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            surface
            content
        }
        .frame(width: side, height: side)
    }

    /// ── STATE IS THE FILL TREATMENT, NOT THE HUE ────────────────────────────
    /// Filled / outlined / dashed is separable before the glyph resolves, at
    /// 32 pt, in peripheral vision, on a dim screen — and it spends no new
    /// colour, which §3.2 has none of to spend.
    @ViewBuilder
    private var surface: some View {
        switch kind {
        case .warmup:
            shape.strokeBorder(tint, lineWidth: 2)
        case .ghost:
            shape.strokeBorder(
                Color.onyx.textTertiary,
                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
            )
        default:
            if isRecord {
                shape.fill(tint.opacity(0.16))
                    .overlay(shape.strokeBorder(tint, lineWidth: 1.5))
            } else {
                shape.fill(filled ? tint : Color.onyx.hairline)
            }
        }
    }

    /// ── THREE OUTCOMES, ONE GLYPH SLOT ──────────────────────────────────────
    /// A record outranks a failure: both are true of a set taken to the stop
    /// that beat something, and "you beat it" is the fact worth the slot. When
    /// it is both, the `F` becomes a pip in the corner — one box, both facts.
    @ViewBuilder
    private var content: some View {
        if isRecord {
            glyph(Image(systemName: "trophy.fill").symbolRenderingMode(.hierarchical), Color.onyx.record)
                // On the glyph and never on the row: a shadow on a recycled
                // row is an offscreen pass per frame, on screens that have to
                // hold 120 Hz under a scrolling thumb.
                .shadow(color: Color.onyx.record.opacity(0.55), radius: 5)
            if isFailure { pip }
        } else if showsCheck, filled, kind == .normal {
            if isFailure {
                glyph(Text("F"), ink)
            } else {
                glyph(Image(systemName: "checkmark"), ink)
            }
        } else {
            Text(label)
                .onyxType(.caption).fontWeight(.bold).onyxNumeral()
                .foregroundStyle(ink)
                // The badge is the one column that must NOT grow with the type
                // size — it is the row's identity and its 44 pt target, and a
                // badge that grew would take the width from the two numbers
                // beside it. The glyph scales inside it instead.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private var pip: some View {
        Text("F")
            .onyxType(.micro).fontWeight(.heavy)
            .foregroundStyle(Color.onyx.danger)
            .offset(x: 7, y: 5)
    }

    private func glyph(_ view: some View, _ color: Color) -> some View {
        view
            .onyxType(.caption).fontWeight(.heavy)
            .foregroundStyle(color)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    /// Ink that survives every one of the surfaces above: on a solid fill it is
    /// the base colour, on an outline or a tint it is the outline's own.
    private var ink: Color {
        switch kind {
        case .warmup: tint
        case .ghost:  Color.onyx.textTertiary
        default:      isRecord ? tint : (filled ? Color.onyx.base : Color.onyx.textSecondary)
        }
    }
}

#if DEBUG
#Preview("Set badges") {
    HStack(spacing: 12) {
        SetBadge(label: "1", tint: Color.onyx.muscle(.chest), filled: false)
        SetBadge(label: "2", tint: Color.onyx.muscle(.chest), showsCheck: true)
        SetBadge(label: "3", tint: Color.onyx.muscle(.chest), isRecord: true, showsCheck: true)
        SetBadge(label: "4", tint: Color.onyx.muscle(.chest), isRecord: true, isFailure: true, showsCheck: true)
        SetBadge(label: "W", tint: Color.onyx.muscle(.chest), kind: .warmup)
        SetBadge(label: "G", tint: Color.onyx.muscle(.chest), kind: .ghost)
        SetBadge(label: "3", tint: Color.onyx.muscle(.lats), isRecord: true, side: 28)
    }
    .padding()
    .onyxScreen(.train)
}
#endif
