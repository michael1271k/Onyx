import SwiftUI
import OnyxUI

/// A session's meta line as capsules rather than as a sentence.
///
/// ── WHY THE FOOTER BLOB HAD TO GO (§U4.3) ───────────────────────────────────
/// It was one `Text`: `"top 40 kg × 11 · 29 reps · 1,160 kg · RPE 8.7 · prev
/// 30 Aug"`. Five independent readings joined by middots into a single 13 pt
/// grey line, set in the same style as the caption above it — so nothing in it
/// could be found without reading all of it, the numbers wrapped mid-figure at
/// an accessibility size, and the one item that carries a VERDICT (the
/// comparison against the previous session) looked exactly like the four that
/// carry a fact.
///
/// Capsules fix all four at once: each reading is its own object with its own
/// bounds, `FlowRow` wraps between them rather than inside them, and a tint is
/// available to the one item that has earned one without repainting the rest.
///
/// ── AND WHY 24 PT IS A FLOOR, NOT A HEIGHT ──────────────────────────────────
/// §U4.3 asks for 24 pt capsules, which is right at the default type size and
/// is a clipped label at AX5 — the trap [[logger-chrome-u1]] records twice. So
/// the frame is a `minHeight` and the padding is what actually sets the shape;
/// a capsule grows with its text and the row grows with it.
struct MetaTagRow: View {

    /// One reading. `tint` is nil for a plain fact — the four that are just
    /// numbers — and set only where the value means something beyond itself.
    /// ── IDENTIFIED BY ITS TEXT, NOT BY A FRESH UUID ────────────────────────
    /// `tags` is a computed property on both callers, so a `let id = UUID()`
    /// gave every capsule a new identity on every body evaluation: the whole
    /// row torn down and rebuilt on each redraw, no transition able to finish,
    /// and `List` row reuse defeated in a section footer. The text IS the
    /// identity — two capsules on one row never carry the same reading.
    struct Tag {
        let text: String
        /// Drawn before the text at `micro`, scaling with the type.
        let symbol: String?
        let tint: Color?

        init(_ text: String, symbol: String? = nil, tint: Color? = nil) {
            self.text = text
            self.symbol = symbol
            self.tint = tint
        }

        /// What VoiceOver hears. The symbol names are the app's only two
        /// direction glyphs; anything else is drawn and not spoken, which is
        /// correct for a decoration.
        var spoken: String {
            switch symbol {
            case "arrowtriangle.up.fill":   "up \(text)"
            case "arrowtriangle.down.fill": "down \(text)"
            default:                        text
            }
        }
    }

    let tags: [Tag]

    var body: some View {
        FlowRow(spacing: OnyxSpace.xs) {
            ForEach(tags, id: \.text) { tag in
                Capsule(tag)
            }
        }
        .accessibilityElement(children: .combine)
        // The glyph is read, not skipped: the arrow on "vs 30 Aug" is the only
        // judgement on the row, and a label built from the text alone made the
        // one tag that says whether the lift went up or down sound exactly like
        // the four that state a total.
        .accessibilityLabel(tags.map(\.spoken).joined(separator: ", "))
    }

    /// One reading, as the object it is.
    ///
    /// ── WHY THE DRAWING LEFT THE ROW (W4) ───────────────────────────────────
    /// The session ledger's header now flows the movement's muscle chips and
    /// its readings through ONE `FlowRow` — the anatomy and the arithmetic on
    /// the same line, because two flow layouts stacked cannot share a line even
    /// when both of them have room (A4). A `FlowRow` places SUBVIEWS, so the
    /// header cannot nest a `MetaTagRow` inside its own and get one line out of
    /// it; it needs the capsule itself.
    ///
    /// Nested rather than free: a capsule is the row's own vocabulary, and the
    /// two must never come to disagree about what a reading looks like.
    struct Capsule: View {
        let tag: Tag

        init(_ tag: Tag) { self.tag = tag }

        var body: some View { drawn }
    }
}

private extension MetaTagRow.Capsule {
    var drawn: some View {
        let tint = tag.tint
        return HStack(spacing: OnyxSpace.xs) {
            if let symbol = tag.symbol {
                // `.hierarchical` and not flat: at 11 pt the flame's inner
                // lobe, the trophy's base and the scale's pan separate into
                // layers, which is what makes a glyph read as an object rather
                // than as a blob — and it takes the tint the capsule is already
                // spending, so it costs no second colour.
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .onyxType(.micro)
                    .foregroundStyle(tint ?? Color.onyx.textTertiary)
            }
            Text(tag.text)
                // Monospaced digits, always: these sit in a row that redraws
                // between two sessions, and proportional figures make the whole
                // line shuffle sideways when a 1,160 becomes a 1,240.
                .onyxType(.caption).onyxNumeral()
                .foregroundStyle(tint ?? Color.onyx.textSecondary)
                // `FlowRow` wraps BETWEEN subviews and never inside one, so a
                // capsule wider than the screen has only two ways out: scale
                // down or truncate mid-figure. "Top 40 kg × 11" passes 375 pt
                // at AX5, and a truncated number is worse than a small one.
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, OnyxSpace.s)
        .padding(.vertical, OnyxSpace.xs)
        .frame(minHeight: 24)
        // A plain fact gets the hairline; a tinted one gets a wash of its OWN
        // ink, so the capsule and the text it holds are one colour at two
        // strengths.
        //
        // 0.12 and not the 0.16 the title band's capsules wear: those sit on
        // the page's own black, these sit on a card that already carries
        // `onyxMuscleWash` at 6 %→2 % of a related hue. The same opacity over
        // a lit surface reads a step heavier, and a row of five heavy capsules
        // is a row of buttons — these are readings.
        // `SwiftUI.Capsule()` spelled in full, not `.capsule`: this type now
        // nests a view of its own called `Capsule`, and the shorthand would
        // resolve to that one.
        .background(
            (tint?.opacity(0.12) ?? Color.onyx.hairline.opacity(0.55)),
            in: SwiftUI.Capsule()
        )
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Meta tags") {
    MetaTagRow(tags: [
        .init("Top 40 kg × 11"),
        .init("29 reps"),
        .init("1,160 kg"),
        .init("RPE 8.7"),
        .init("vs 30 Aug", symbol: "arrowtriangle.up.fill", tint: Color.onyx.good),
    ])
    .padding()
    .onyxScreen(.train)
}
#endif
