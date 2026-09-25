import SwiftUI
import OnyxUI

/// Everything you do to a set that is not its two numbers.
///
/// ── WHY IT IS BEHIND THE SET NUMBER ─────────────────────────────────────────
/// The badge already SHOWS the set's type — `W`, `F`, `D`, `G`, or the ordinal.
/// A control that displays a value is the obvious place to change it, and it
/// costs no new pixels because the box was already drawn. Tap logs the set, hold
/// opens this; two gestures on one target, and the one you reach for constantly
/// is the shorter one.
///
/// ── TWO AXES, NOT ONE LONGER LIST ───────────────────────────────────────────
/// "Warm-up" and "form broke" are both true of the same set. Folding technique
/// into `set_type` would force a choice between two facts, and would give every
/// consumer of "is this a working set" an opinion about form — see `SetQuality`.
/// So the type is one row of toggles and the quality is another, each with its
/// own meaning line, and neither can express the other.
///
/// ── WHAT LEFT IN WAVE U2, AND WHY ───────────────────────────────────────────
/// **Duplicate**: it was here, on the row's long press, and in the VoiceOver
/// rotor, and `LoggerModel.duplicate` existed to serve it. "Add set" is one tap
/// away at the bottom of every card and carries the previous row's load and reps
/// forward already, so duplicate was a second way to do the same thing with its
/// own bug surface — it was the gesture that fired at 0.45 s while someone held
/// `+` to ramp a load. It is deleted, model method and all.
///
/// **Note**: the note belongs to the EXERCISE, not to this set, and it was only
/// here because the old confirmation dialog had nowhere else to put it. Wave U1
/// gave the logger a chip row with `Note` in it, which is the right level and is
/// reachable without first choosing a set. Two doors to one field, one of them
/// mislabelled, is worse than one door.
///
/// **`Normal`**: there is no chip for it, because "normal" is the ABSENCE of a
/// claim. Tapping the type a set already carries withdraws it, which is the same
/// grammar the quality row has always used, and it makes the row four toggles
/// rather than five radio buttons with a default nobody picks.
///
/// ── AND WHY THE FOUR TYPES ARE COLOURED NOW ─────────────────────────────────
/// They were one accent — §3.2 gives this app four domain meshes and gold, and
/// five invented hues for five chips would be five tokens nobody designed. But
/// four of the colours the system ALREADY has say exactly these four things, so
/// none of them is new: a warm-up is preparation (Lunar, the recover mesh),
/// failure is the top of the effort ramp (`danger`, which is what
/// `Color.onyx.effort` itself returns at 9.5 and above), a drop set is extra
/// work in the working range (Solar, which is that same ramp's middle), and a
/// skipped set is absent (tertiary ink, the token for "nothing was said"). The
/// row now reads as a scale rather than as four identical chips.
struct SetOptionsSheet: View {
    let ordinal: Int
    let exerciseName: String
    @Bindable var row: LoggerModel.SetRow
    let onKind: (LoggerModel.SetKind) -> Void
    let onQuality: (SetQuality?) -> Void
    /// Split this set into an independent Left and Right, or put a split one
    /// back together. `nil` on a movement that is not trained one side at a
    /// time — see `Unilateral`, and the note on `split` below for why the
    /// button is absent rather than disabled there.
    var onSplit: (() -> Void)?
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var accent: Color { Color.onyx.accent(.train) }

    /// The types a set can be MARKED as. `normal` is not one of them: see the
    /// note above.
    ///
    /// ── AND `ghost` IS NOT ONE ANY MORE (Precision A6, Q9) ─────────────────
    /// A ghost was a set you ticked to say you had NOT done it — stored, and
    /// then excluded from everything by a dozen separate rules. An unticked
    /// set already says that and is never stored, and the routine keeps it
    /// (`RoutineOrder`), so the manual mark was a second, heavier way to say
    /// the same nothing. The enum case stays: history holds ghost rows, and
    /// they must still read back.
    private static let kinds: [LoggerModel.SetKind] = [.warmup, .failure, .dropset]

    /// Three across, until the type size says otherwise. At an accessibility
    /// size three chips across is three truncated words, so they take two
    /// columns, as the four did.
    private var kindColumns: Int { typeSize.isAccessibilitySize ? 2 : 3 }
    private var qualityColumns: Int { typeSize.isAccessibilitySize ? 1 : 3 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OnyxSpace.l) {
                    kindSection
                    qualitySection
                    actions
                }
                .padding(OnyxSpace.l)
            }
            .onyxScreen(.train)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(row.sideLabel.map { "Set \(ordinal) · \($0)" } ?? "Set \(ordinal)")
                            .onyxType(.body).fontWeight(.semibold)
                        // `.onyxType(.micro)`, not `.onyxMicro()`: the register
                        // role uppercases, and this is a proper noun —
                        // `NEUTRAL-GRIP LAT PULLDOWN` is the movement shouted
                        // rather than named.
                        // ── AND WHY IT IS NOT A CAPTION ────────────────────
                        // You reached this by long-pressing a 32 pt badge in a
                        // five-row list with wet hands, and on a 375 pt phone
                        // the sheet covers the card completely — so this line
                        // is the ONLY evidence you opened the set you meant,
                        // in front of a Delete. It was set smaller, dimmer and
                        // tracked out: weaker than the title above it, for the
                        // half of the title that actually disambiguates.
                        Text(exerciseName)
                            .onyxType(.secondary).fontWeight(.semibold)
                            .foregroundStyle(Color.onyx.textSecondary)
                            .lineLimit(1)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        // ── WHY 440 AND NOT THE PLAN'S 320 ─────────────────────────────────
        // 320 was measured against the sheet this replaced, which had five type
        // chips on one row and no meaning line under the quality. At 320 the
        // rebuilt sheet cut off at the second row of quality chips and DELETE
        // WAS BELOW THE FOLD — a destructive action reachable only by dragging
        // a sheet nothing indicated could be dragged. 440 is what the content
        // measures on a 375 pt phone; the content is what the plan asked for.
        //
        // And at an accessibility size there is no short detent at all: the
        // same content is three times as tall, so 400 pt showed the title and
        // the first row of chips. A sheet whose opening height hides its own
        // controls is a sheet that has to be dragged before it can be used, by
        // exactly the reader least able to guess that it can be.
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(440), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - What it was

    private var kindSection: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            OnyxSectionHeader("What it was", .train)
            grid(columns: kindColumns) {
                ForEach(Self.kinds) { kind in
                    let selected = row.kind == kind
                    chip(
                        label: kind.label,
                        glyph: kind.badge,
                        tint: Self.tint(kind),
                        selected: selected,
                        hint: kind.hint
                    ) {
                        // Picking does NOT dismiss, and picking the one it
                        // already carries withdraws it. Making a set a warm-up
                        // and then marking it short of range is one errand, and
                        // a sheet that closes on the first tap makes it two.
                        onKind(selected ? .normal : kind)
                    }
                }
            }
            meaning(row.kind.hint, marked: row.kind != .normal, tint: Self.tint(row.kind))
        }
    }

    /// The four types, in colours the design system has already spent. See the
    /// note at the top of this file for why none of these is a new hue.
    private static func tint(_ kind: LoggerModel.SetKind) -> Color {
        switch kind {
        case .normal:  Color.onyx.textSecondary
        case .warmup:  OnyxDomain.recover.accent
        case .failure: Color.onyx.danger
        case .dropset: OnyxDomain.fuel.accent
        case .ghost:   Color.onyx.textTertiary
        }
    }

    // MARK: - Set quality

    /// ── WHY SEVERAL AT ONCE ─────────────────────────────────────────────────
    /// These are not a scale and never were. "Used momentum" and "cut the range
    /// short" are two observations about one set, and a radio group made you
    /// throw one away — so the set that most deserved describing was the one
    /// described least. Tapping a chosen chip still withdraws it; there is still
    /// no `Clean` chip, because clean is the ABSENCE of a claim and a chip for
    /// it would write a value asserting the set was inspected and passed.
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            OnyxSectionHeader("Set quality", .train)
            grid(columns: qualityColumns) {
                ForEach(SetQuality.allCases) { quality in
                    chip(
                        label: quality.label,
                        glyph: nil,
                        tint: accent,
                        selected: row.qualities.contains(quality),
                        hint: quality.full
                    ) {
                        onQuality(quality)
                    }
                }
            }
            // One tag prints its whole sentence, as it always has. Several print
            // their short labels: three full sentences is a paragraph under a
            // grid of chips, and the reserved height would have to grow to fit
            // the worst case on every set that has none.
            meaning(
                row.qualities.count == 1
                    ? (row.qualities[0].full)
                    : (SetQuality.summary(row.qualities) ?? "Clean unless you say otherwise"),
                marked: !row.qualities.isEmpty,
                tint: accent
            )
        }
    }

    // MARK: - The actions

    /// Split beside Remove, and Remove keeps its distance from the chips you
    /// came here for: it is the only thing in the sheet that cannot be undone by
    /// tapping it again.
    private var actions: some View {
        HStack(spacing: OnyxSpace.s) {
            if onSplit != nil { split }
            remove
        }
    }

    /// ── WHY THE BUTTON IS ABSENT AND NOT DISABLED ───────────────────────────
    /// Splitting a BILATERAL set is not a cosmetic mistake. A pair is scored
    /// once, at its weaker side, and counts as ONE set of work — so a barbell
    /// press split in half is a session logged at half its size, silently, in
    /// `total_volume_kg` and in every chart downstream. A greyed control invites
    /// the question "why not"; an absent one does not raise it.
    ///
    /// The label is the OUTCOME, not the state: `Split L / R` on a whole set,
    /// `Merge sides` on one already split. A toggle labelled with what it
    /// currently is, on a sheet you reached by holding a 32 pt badge, is a
    /// coin flip.
    @ViewBuilder
    private var split: some View {
        if let onSplit {
            Button {
                onSplit()
                dismiss()
            } label: {
                Label(
                    row.pairId == nil ? "Split L / R" : "Merge sides",
                    systemImage: row.pairId == nil
                        ? "arrow.left.and.right.square" : "arrow.down.right.and.arrow.up.left"
                )
                    .onyxType(.body).fontWeight(.semibold)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .onyxGlass(.row)
            }
            .onyxPress(scale: 0.98)
            .accessibilityHint(
                row.pairId == nil
                    ? "Splits this set into an independent left and right"
                    : "Puts the two sides back together at the weaker side's numbers"
            )
        }
    }

    private var remove: some View {
        Button {
            onDelete()
            dismiss()
        } label: {
            Label("Delete set", systemImage: "trash")
                .onyxType(.body).fontWeight(.semibold)
                .foregroundStyle(Color.onyx.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 48)
                .onyxGlass(.row)
        }
        .onyxPress(scale: 0.98)
    }

    // MARK: - Parts

    private func grid<Content: View>(
        columns: Int, @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.s), count: columns),
            spacing: OnyxSpace.s,
            content: content
        )
    }

    /// One choice. The colour IS the state, so there is no tick to find.
    private func chip(
        label: String, glyph: String?, tint: Color,
        selected: Bool, hint: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let glyph {
                    // The glyph wears its type's colour ALWAYS, and the fill
                    // and label only when chosen. Colour-on-selection alone
                    // made four identical grey chips whose colours nobody saw
                    // until after they had picked one, which is the wrong way
                    // round: the ramp is there to be read before the choice.
                    Text(glyph)
                        .onyxType(.body).fontWeight(.heavy).onyxNumeral()
                        .foregroundStyle(tint)
                }
                Text(label)
                    .onyxType(.caption).fontWeight(.semibold)
                    .foregroundStyle(selected ? tint : Color.onyx.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                    .fill(selected ? tint.opacity(0.16) : Color.onyx.hairline.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                    .strokeBorder(selected ? tint.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .onyxPress(scale: 0.95)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel(label)
        .accessibilityHint(selected ? "Selected. Tap to remove." : hint)
    }

    /// What the current answer MEANS, on a line that is always there. Its height
    /// is reserved so choosing a longer hint does not move the chips under the
    /// thumb that is still on them.
    private func meaning(_ text: String, marked: Bool, tint: Color) -> some View {
        Label {
            Text(text)
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark")
                .onyxType(.micro)
                .foregroundStyle(marked ? tint : .clear)
        }
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
    }
}

#if DEBUG
#Preview("Set options") {
    let model = LoggerModel.previewUpperB(logged: true)
    let exercise = model.exercises[1]
    return Color.clear.sheet(isPresented: .constant(true)) {
        SetOptionsSheet(
            ordinal: 2,
            exerciseName: exercise.name,
            row: exercise.rows[1],
            onKind: { model.setKind($0, on: exercise.rows[1], in: exercise) },
            onQuality: { model.setQuality($0, on: exercise.rows[1], in: exercise) },
            onSplit: { model.splitSet(exercise.rows[1], in: exercise) },
            onDelete: {}
        )
    }
    .preferredColorScheme(.dark)
}
#endif
