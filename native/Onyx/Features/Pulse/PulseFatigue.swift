import SwiftUI
import OnyxUI
import OnyxCore

/// One slot, five words, one tap (founder decision 6, D9).
///
/// ── WHAT WAS HERE, AND WHY IT WENT ──────────────────────────────────────────
/// Three `Section`s, each an inline `Picker` of six rows spelled
/// "Word — sentence", plus a per-slot definition line and a session-cost
/// footer: roughly a screen and a half of form, scrolled, for a reading taken
/// twice a day. Every piece of it was defensible on its own and the whole was a
/// questionnaire.
///
/// The day still has three slots, so the sheet still has to ask which. It asks
/// once, at the top, with the answer already filled in from the clock — and
/// then the rest of the sheet is the five words, at the size of something you
/// hit without looking. One tap writes and closes.
///
/// The session cost left with the pickers: `FatigueCard` already prints the
/// delta on the card this sheet opens from, and a sheet that repeats the thing
/// that opened it is a sheet you read twice to learn nothing.
struct FatigueSheet: View {
    let model: DayModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Nil until `onAppear` picks one — the day's kind decides which three
    /// slots exist, and it is not known at init.
    @State private var slot: FatigueSlot?
    private var slots: [FatigueSlot] { model.fatigueSlots }
    private var current: FatigueSlot { slot ?? slots.first ?? .waking }
    private var level: Int? { model.fatigue[current] }

    var body: some View {
        DaySheet(
            "Fatigue",
            domain: .recover,
            glass: false,
            // ── THE DETENT HAS TO HOLD "CLEAR" TOO ──────────────────────
            // A medium detent fits the segments, the five words and the hint
            // line exactly — and cuts "Clear this slot" below the fold, which
            // is the one row that only ever exists on a slot you might want to
            // correct. So a rated slot opens a fraction taller. A tap that
            // picks a word dismisses the sheet, so the only way this changes
            // mid-life is the segment moving to a slot with a different answer
            // — where the content really did change height.
            //
            // Above the default type size the five words become a column
            // (`FiveWordPicker`) that no fraction holds, and a sheet which
            // opens already clipped is worse than one that opens tall.
            detents: typeSize > .large ? [.large] : [level != nil ? .fraction(0.62) : .medium, .large]
        ) {
            Form {
                if slots.count > 1 { slotSection }
                wordSection
                if level != nil { clearSection }
            }
        }
        .onAppear { if slot == nil { slot = model.fatigueAsk } }
        // The day can change kind under the sheet — a session started while it
        // was open swaps Midday for Before training. Land on a slot that exists.
        .onChange(of: slots) { _, next in
            if let slot, !next.contains(slot) { self.slot = model.fatigueAsk }
        }
    }

    // MARK: - Which slot

    @ViewBuilder
    private var slotSection: some View {
        // ── TWO STYLES, TWO BRANCHES ────────────────────────────────────────
        // A segmented control neither wraps nor scrolls, so at an accessibility
        // size all three titles shred at once. It cannot be a ternary on
        // `.pickerStyle` either — `SegmentedPickerStyle` and its alternatives
        // are different TYPES, not two values of one.
        //
        // The AX branch is `.inline` rather than `.menu`: a menu picker inside a
        // `Form` draws its title and its value on one row, and at AX5 the title
        // is clipped by the row's own top edge ("Iime ot day") while the value
        // wraps under it. Three tappable rows cannot clip, and they are the
        // shape iOS itself uses for a three-way choice at that size.
        if typeSize.isAccessibilitySize {
            Section {
                slotPicker(full: true)
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .tint(Color.onyx.accent(.recover))
            } header: {
                OnyxSectionHeader("Time of day", .recover)
            }
        } else {
            Section {
                slotPicker(full: false)
                    .pickerStyle(.segmented)
                    .tint(Color.onyx.accent(.recover))
            }
        }
    }

    /// The short name in the segments, the full one in the menu: three segments
    /// across a phone is 111 pt each and "Before training" truncates; a menu row
    /// has the whole width.
    private func slotPicker(full: Bool) -> some View {
        Picker("Time of day", selection: Binding(get: { current }, set: { slot = $0 })) {
            ForEach(slots, id: \.self) { slot in
                Text(full ? slot.label : slot.short).tag(slot)
            }
        }
    }

    // MARK: - The five words

    private var wordSection: some View {
        Section {
            FiveWordPicker(words: Fatigue.levels.map(FiveWordPicker.Word.init), selected: level) { value in
                model.setFatigue(current, level: value)
                dismiss()
            }
            .listRowInsets(EdgeInsets(
                top: OnyxSpace.s, leading: OnyxSpace.s, bottom: OnyxSpace.s, trailing: OnyxSpace.s
            ))
        } header: {
            OnyxSectionHeader(current.label, .recover)
        } footer: {
            // ── THE ONE LINE OF HINT (D9) ───────────────────────────────────
            // The ENDS of the scale, not the selected rung: one tap closes this
            // sheet, so prose about what you just picked is prose nobody reads.
            // What a first-time reader needs is which way the row runs, and the
            // two anchors say that in a line. Derived from the table so the
            // words and their definitions cannot drift apart.
            Text(anchors)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var anchors: String {
        guard let first = Fatigue.levels.first, let last = Fatigue.levels.last else { return "" }
        return "\(first.label) = \(first.hint). \(last.label) = \(last.hint)."
    }

    // MARK: - Taking it back

    /// ── A TAP THAT ANSWERS CLOSES; A TAP THAT UN-ANSWERS DOES NOT ───────────
    /// A slot you can set and never unset records a mistap forever, which is
    /// what the old picker's "Not rated" row was for. It is not a sixth target
    /// — that would break "five equal" — and it is not destructive red: nothing
    /// is mourned here. Dismissing on a clear would make a correction feel like
    /// it had committed something.
    private var clearSection: some View {
        Section {
            Button("Clear this slot") { model.setFatigue(current, level: nil) }
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }
}
