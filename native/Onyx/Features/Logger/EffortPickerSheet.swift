import SwiftUI
import OnyxUI

/// How close to failure that set was — the eight rungs of `RpeLadder`, as a
/// ladder.
///
/// ── WHY THIS REPLACED A `Menu` ──────────────────────────────────────────────
/// The row's effort control was a system `Menu` listing the eight stops as
/// eight equal rows. A menu is the right control for a set of unrelated
/// commands and the wrong one for an ORDERED scale: it draws "Easy" and
/// "Failure" as peers, gives no sense of how far apart two answers are, and
/// puts the rungs a working set actually lands on — Challenging through Max
/// Effort — behind a scroll on the small end of a phone. Picking one rung too
/// low is a one-notch mistake; the menu made it look like any other.
///
/// A ladder says the thing the scale is: left is easy, right is failure, the
/// colour warms as it climbs, and the rung you chose is the one standing
/// proud. The word and its reps-in-reserve gloss sit under it, so the ANSWER is
/// stated in prose and the ladder is only how you point at it.
///
/// ── THE COLOUR RAMP ─────────────────────────────────────────────────────────
/// `Color.onyx.effort` has three stops on purpose (§3.2: effort is a reading,
/// not a verdict — secondary ink through the easy end, Solar through the
/// working range, danger at failure). Eight hues would be eight tokens nobody
/// designed. The ramp here is that same three-stop function at a rising
/// opacity, so the ladder reads as a gradient and still contains no colour the
/// design system has not already spent.
struct EffortPickerSheet: View {
    let ordinal: Int
    let exerciseName: String
    @Bindable var row: LoggerModel.SetRow
    /// Whether the rating was stale WHEN THIS OPENED. Picking a rung clears
    /// `row.rpeStale`, and a height computed from the live flag shrank the
    /// sheet 80 pt at the exact moment of the tap, under the thumb still on the
    /// ladder. The sheet describes the set as you found it.
    let wasStale: Bool
    /// `nil` withdraws the rating. Writing the value is the caller's job — the
    /// row also has to be committed to the store and its stale flag cleared,
    /// and a sheet that did half of that would leave the two disagreeing.
    let onPick: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var accent: Color { Color.onyx.accent(.train) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OnyxSpace.l) {
                    // Control, then answer, then the note that explains why the
                    // pip sent you here. The note was first, and at AX5 it was
                    // the whole of the opening screen — a sheet that opens on a
                    // paragraph about a ladder nobody can see yet.
                    if typeSize.isAccessibilitySize { list } else { ladder }
                    reading
                    if wasStale { staleNote }
                    clear
                }
                .padding(OnyxSpace.l)
            }
            .onyxScreen(.train)
            // The title is the principal item below — it carries the set and the
            // movement under the word, which a plain title cannot.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Effort").onyxType(.body).fontWeight(.semibold)
                        // `.onyxType(.micro)`, not `.onyxMicro()` — the
                        // register role uppercases, and the movement is a
                        // proper noun, not a label.
                        Text("Set \(ordinal) · \(exerciseName)")
                            .onyxType(.micro)
                            .foregroundStyle(Color.onyx.textSecondary)
                            .lineLimit(1)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        // 320 is the ladder, the reading and the clear button with nothing
        // spare — and the stale note is a fourth thing, which is why the height
        // asks whether it is there. A detent that ignored it put "Clear rating"
        // under the bottom edge of a 375 pt phone. At an accessibility size the ladder becomes eight rows and no
        // fixed detent holds those, so there is no short detent to offer: a
        // sheet whose opening height hides its own control has to be dragged
        // before it can be used, by exactly the reader least able to guess
        // that it can be.
        .presentationDetents(
            typeSize.isAccessibilitySize ? [.large] : [.height(wasStale ? 400 : 320), .large]
        )
        .presentationDragIndicator(.visible)
        // The pick used to be committed by the row, which fired this; the sheet
        // owns the choice now, so it owns the detent.
        .sensoryFeedback(.selection, trigger: row.rpe)
    }

    // MARK: - The ladder

    /// Eight rungs, in one row, hardest on the right.
    ///
    /// Ordered EASY → HARD rather than the menu's hard-first: a ladder that
    /// climbs to the left is a ladder that has to be read twice, and the ramp
    /// only means anything if it runs the same way as the numbers. The rung a
    /// working set lands on is at the right-hand end, which is also the end a
    /// right thumb reaches first.
    private var ladder: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            HStack(spacing: 2) {
                ForEach(Array(RpeLadder.stops.enumerated()), id: \.element.id) { index, stop in
                    rung(stop, ramp: Double(index) / Double(max(1, RpeLadder.stops.count - 1)))
                }
            }
            HStack {
                Text("easier").onyxMicro(Color.onyx.textTertiary)
                Spacer(minLength: 0)
                Text("failure").onyxMicro(Color.onyx.textTertiary)
            }
            .accessibilityHidden(true)
        }
    }

    private func rung(_ stop: RpeLadder.Stop, ramp: Double) -> some View {
        let selected = row.rpe == stop.value
        let tint = Color.onyx.effort(stop.value)
        return Button {
            onPick(stop.value)
        } label: {
            Text(OnyxFormat.rpe(stop.value))
                .onyxType(.caption).fontWeight(.bold).onyxNumeral()
                .foregroundStyle(selected ? Color.onyx.base : Color.onyx.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                // 56 rather than 44: this is the only control on the sheet and
                // the rung is 40 pt wide on a 375 pt phone, so the height is
                // what makes the target one. A miss here writes a number onto
                // a set, which is the kind of mistake that survives to the
                // weekly export.
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                        .fill(selected ? tint : tint.opacity(0.14 + 0.26 * ramp))
                )
                // ── SELECTION IS A STROKE, AND IT IS NOT THE RAMP'S COLOUR ──
                // The chosen rung wore a 2 pt border in its own tint, which at
                // 8.5 is Solar — close enough to the record gold that a picker
                // opened seconds after a PR read as if it were about the PR.
                // Gold means one thing in this app. Selection is chrome, so it
                // takes ink: white on the fill, and the scale below does the
                // rest.
                //
                // Inside the tile rather than `padding(-3)` around it: the
                // rungs are 2 pt apart, so a stroke drawn outside overprinted
                // both neighbours.
                .overlay(
                    RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                        .strokeBorder(selected ? Color.onyx.textPrimary : .clear, lineWidth: 2)
                )
                .contentShape(.rect)
        }
        .onyxPress(scale: 0.94)
        // The chosen rung stands proud of the ladder — the same gesture the
        // segmented control in the hero uses, and the reason the ladder needs
        // no tick.
        .scaleEffect(selected ? 1.06 : 1)
        .zIndex(selected ? 1 : 0)
        .animation(OnyxMotion.move, value: row.rpe)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel(stop.label)
        .accessibilityValue(stop.hint)
    }

    /// At an accessibility size the ladder becomes a list: eight 40 pt rungs
    /// cannot hold an AX5 numeral, and a ramp nobody can read the labels on is
    /// a decoration with a tap target.
    private var list: some View {
        VStack(spacing: OnyxSpace.xs) {
            ForEach(RpeLadder.stops.reversed()) { stop in
                let selected = row.rpe == stop.value
                Button { onPick(stop.value) } label: {
                    HStack(spacing: OnyxSpace.s) {
                        Text(OnyxFormat.rpe(stop.value))
                            .onyxType(.body).fontWeight(.bold).onyxNumeral()
                            .foregroundStyle(Color.onyx.effort(stop.value))
                            .frame(minWidth: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(stop.label).onyxType(.body).fontWeight(.semibold)
                                .foregroundStyle(Color.onyx.textPrimary)
                            Text(stop.hint).onyxType(.caption)
                                .foregroundStyle(Color.onyx.textSecondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark").fontWeight(.bold)
                                .foregroundStyle(accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OnyxSpace.s)
                    .background(
                        RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                            .fill(selected ? accent.opacity(0.16) : Color.onyx.hairline.opacity(0.35))
                    )
                    .contentShape(.rect)
                }
                .onyxPress(scale: 0.98)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    // MARK: - What you picked

    /// The word, and the gloss you can actually count. Its height is reserved
    /// so moving along the ladder does not move the ladder under the thumb that
    /// is still on it.
    private var reading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(RpeLadder.label(row.rpe) ?? "Not rated")
                .onyxDisplay().fontWeight(.semibold)
                .foregroundStyle(row.rpe.map(Color.onyx.effort) ?? Color.onyx.textTertiary)
                .contentTransition(.opacity)
            Text(RpeLadder.stop(for: row.rpe)?.hint
                 ?? (row.rpe == nil ? "Nothing is written to this set" : "Rated before the ladder existed"))
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .animation(OnyxMotion.fade, value: row.rpe)
        .accessibilityElement(children: .combine)
    }

    /// The seed carried a rating forward and then dropped it, because this row
    /// asks for more work than the set it was remembered from. Said here rather
    /// than only as a pip on the row: the pip is what makes you open this, and
    /// arriving with no explanation is how a pip becomes something you learn to
    /// ignore.
    private var staleNote: some View {
        Label {
            Text("Last time's rating no longer fits this set — it asks for more work.")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            // Not an arrow: `↗` is the progression chip's glyph in the card
            // header, and the same arrow in a second colour meaning a second
            // thing is two vocabularies for one shape.
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OnyxSpace.s)
        .onyxGlass(.row)
    }

    /// Withdrawing a rating is not the same as rating a set easy, and the
    /// progression rule depends on being able to tell them apart — see
    /// `Ceilings.progressionVerdict`, where a null RPE passes and a 9 does not.
    @ViewBuilder
    private var clear: some View {
        if row.rpe != nil {
            Button { onPick(nil) } label: {
                Label("Clear rating", systemImage: "xmark.circle")
                    .onyxType(.body).fontWeight(.semibold)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .onyxGlass(.row)
            }
            .onyxPress(scale: 0.98)
        }
    }
}

#if DEBUG
#Preview("Effort picker") {
    let model = LoggerModel.previewUpperB(logged: true)
    let exercise = model.exercises[1]
    let row = exercise.rows[0]
    return Color.clear.sheet(isPresented: .constant(true)) {
        EffortPickerSheet(
            ordinal: 1, exerciseName: exercise.name, row: row,
            wasStale: row.rpeStale, onPick: { row.rpe = $0 }
        )
    }
    .preferredColorScheme(.dark)
}
#endif
