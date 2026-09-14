import SwiftUI
import OnyxUI
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// HEAD — the typed stress reading (founder decision 3, D6).
//
// `PulseStress.swift` is the COMPUTED index: four terms of heart rate, sleep,
// self-report and load, arranged around "how far from your own normal is
// today". This file is one of its inputs — a thing you type, in words, about
// your mind. They are a tile and a row apart on the same screen and they must
// not look like one feature: the index is a measurement you cannot argue with
// and this is an opinion you are asked for.
//
// It is NOT a battery input and it moves no score. What it moves is the `self`
// term, where it is averaged with the day's fatigue (`Stress.breakdown`) —
// which is why the two rows sit together and why they share a control and a
// colour ramp.
// ─────────────────────────────────────────────────────────────────────────────

/// What is on your mind, in one row.
struct HeadSummaryRow: View {
    let model: DayModel
    let onOpen: () -> Void

    private var readings: [StressReading] { model.stressReadings }
    private var latest: StressReading? { model.stressLatest }

    /// "Evening · 2 of 3", or the invitation when nothing is logged. Same
    /// sentence the fatigue row above builds, because it is the same question
    /// about a different thing and a reader should not have to parse two.
    private var detail: String {
        guard let latest else { return "Not rated · 0 of \(StressSlot.allCases.count)" }
        return "\(latest.slot.label) · \(readings.count) of \(StressSlot.allCases.count)"
    }

    var body: some View {
        PulseRow(
            symbol: "brain.head.profile",
            title: "Head",
            detail: detail,
            // ── THE FATIGUE RAMP, ON PURPOSE ────────────────────────────────
            // `OnyxTokens` states the rule where `fatigue` is defined: the
            // subjective readings on this screen share severity's three-step
            // ramp so a reader learns one colour language. `StressBand.tint`
            // would be the wrong ink here — it belongs to the computed index,
            // and painting a typed answer in it says the two are the same
            // number.
            tint: Color.onyx.fatigue(latest?.level),
            spoken: spoken,
            action: onOpen
        ) {
            HStack(spacing: OnyxSpace.s) {
                if let level = latest?.level, let word = PsychStress.level(level)?.label {
                    Text(word)
                        .onyxType(.body).fontWeight(.semibold)
                        .foregroundStyle(Color.onyx.fatigue(level))
                        .lineLimit(1)
                }
                dots
            }
        }
    }

    /// One dot per bucket the day can hold.
    private var dots: some View {
        HStack(spacing: OnyxSpace.xs) {
            ForEach(StressSlot.allCases, id: \.self) { slot in
                let level = readings.first { $0.slot == slot }?.level
                Circle()
                    .fill(level != nil ? Color.onyx.fatigue(level) : .clear)
                    .strokeBorder(level != nil ? .clear : Color.onyx.textTertiary, lineWidth: 1)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    private var spoken: String {
        guard let latest, let word = PsychStress.level(latest.level)?.label else { return detail }
        let tags = latest.tags.map(\.label).joined(separator: ", ")
        return "\(word), \(detail)" + (tags.isEmpty ? "" : ", tagged \(tags)")
    }
}

// MARK: - The sheet

/// Five words, seven optional chips and a line of your own.
///
/// ── WHY THIS ONE HAS A SAVE BUTTON AND FATIGUE DOES NOT ─────────────────────
/// Decision 6 gives fatigue one tap because a fatigue reading IS one number.
/// This reading is three things — the level, what it was about, and whatever
/// you want to say about it — and a control that committed on the first of them
/// would close the sheet before the other two could be entered. So: Cancel and
/// Save, the level is what makes Save legal, and the chips and the note are
/// each optional.
///
/// ── AND WHY THE TIME OF DAY IS NOT A CONTROL ────────────────────────────────
/// The server key is `(user_id, date, slot)` and the index reads the MEAN of
/// the day's rows, so the day can hold three answers. Which one you are writing
/// is a question about the clock, and the clock knows — a picker there would be
/// a control whose only correct setting is the one it already has. It is stated
/// as the section header instead, so an answer is never filed somewhere
/// surprising.
struct HeadSheet: View {
    let model: DayModel

    @Environment(\.dismiss) private var dismiss

    @State private var level: Int?
    @State private var tags: Set<StressTag> = []
    @State private var note = ""
    @State private var loaded = false
    /// The chip grid's column minimum, scaled — see `tagSection`.
    @ScaledMetric(relativeTo: .footnote) private var chipWidth: CGFloat = 96

    private var slot: StressSlot { model.stressSlot }

    var body: some View {
        DaySheet(
            "Head",
            domain: .recover,
            glass: false,
            // A form: five rows of words, a chip grid and a note do not fit a
            // medium detent, and a sheet that opens already clipped is worse
            // than one that opens tall.
            detents: [.large],
            primary: ("Save", level != nil, save)
        ) {
            Form {
                wordSection
                if !model.stressReadings.isEmpty { todaySection }
                tagSection
                noteSection
                if existing != nil { clearSection }
            }
        }
        // ── LOAD THE BUCKET'S OWN ANSWER, ONCE, WHENEVER IT ARRIVES ─────────
        // Without this a second visit to the same bucket writes a fresh reading
        // over the one already there and silently drops its tags and its note.
        //
        // It cannot be `onAppear` alone: the readings come off a GRDB stream and
        // `onAppear` fires before its first yield, so a sheet opened from a
        // screen whose streams are still starting (Quick Log builds its model on
        // the tap) showed an answered bucket as blank. `onChange` catches the
        // row when it lands — and both paths refuse to touch anything the user
        // has already typed.
        .onAppear(perform: adopt)
        .onChange(of: existing) { _, _ in adopt() }
    }

    /// Take the stored answer, but never over the top of one being written.
    ///
    /// FIELD BY FIELD, because `logStress` writes the whole row: a reader who
    /// tapped a word before the stream yielded would otherwise Save a level
    /// over a bucket that already held tags and a note, and take both with it.
    /// Each field is adopted only while it is still untouched, so a tap costs
    /// the level and nothing else.
    private func adopt() {
        guard !loaded, let existing else { return }
        loaded = true
        if level == nil { level = existing.level }
        if tags.isEmpty { tags = Set(existing.tags) }
        if note.isEmpty { note = existing.note ?? "" }
    }

    private var existing: StressReading? { model.stressReading(slot) }

    // MARK: The five words

    private var wordSection: some View {
        Section {
            FiveWordPicker(words: PsychStress.levels.map(FiveWordPicker.Word.init), selected: level) { value in
                level = value
            }
            .listRowInsets(EdgeInsets(
                top: OnyxSpace.s, leading: OnyxSpace.s, bottom: OnyxSpace.s, trailing: OnyxSpace.s
            ))
        } header: {
            OnyxSectionHeader(slot.label, .recover)
        } footer: {
            Text(anchors).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var anchors: String {
        guard let first = PsychStress.levels.first, let last = PsychStress.levels.last else { return "" }
        return "\(first.label) = \(first.hint). \(last.label) = \(last.hint)."
    }

    // MARK: What the day already holds

    /// One line, not a list. The buckets are the clock's, so re-answering an
    /// earlier one is deliberately not offered — this is here so the reader can
    /// see what the day's mean is being built from before adding to it.
    private var todaySection: some View {
        Section {
            HStack(spacing: OnyxSpace.s) {
                dots
                Text(summary)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today so far")
            .accessibilityValue(summary)
        }
    }

    private var dots: some View {
        HStack(spacing: OnyxSpace.xs) {
            ForEach(StressSlot.allCases, id: \.self) { slot in
                let value = model.stressReading(slot)?.level
                Circle()
                    .fill(value != nil ? Color.onyx.fatigue(value) : .clear)
                    .strokeBorder(value != nil ? .clear : Color.onyx.textTertiary, lineWidth: 1)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    private var summary: String {
        StressSlot.allCases.map { slot in
            let word = model.stressReading(slot).flatMap { PsychStress.level($0.level)?.label }
            return "\(slot.label) \(word ?? "not rated")"
        }
        .joined(separator: " · ")
    }

    // MARK: The chips

    private var tagSection: some View {
        Section {
            // An adaptive grid reflows to one column at an accessibility size
            // with no branch of its own, which is what a seven-chip row needs
            // and what a horizontal scroller would hide.
            // ── `.adaptive` DOES NOT KNOW ABOUT DYNAMIC TYPE ────────────
            // Its minimum is a raw point value, so at AX5 the grid still packs
            // three ~100 pt columns and "Family", "Travel" and "Health" all
            // truncate inside them. `@ScaledMetric` moves the minimum with the
            // text, which is what makes the reflow to one column happen.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: chipWidth), spacing: OnyxSpace.s)],
                alignment: .leading,
                spacing: OnyxSpace.s
            ) {
                ForEach(StressTag.allCases, id: \.self) { tag in chip(tag) }
            }
            .padding(.vertical, OnyxSpace.xs)
        } header: {
            OnyxSectionHeader("What's on it", .recover)
        } footer: {
            Text("Optional. Nothing here is scored — the tags are for you, reading this back.")
        }
    }

    private func chip(_ tag: StressTag) -> some View {
        let on = tags.contains(tag)
        return Button {
            if on { tags.remove(tag) } else { tags.insert(tag) }
        } label: {
            HStack(spacing: OnyxSpace.xs) {
                // The checkmark is what keeps the state off colour alone.
                if on { Image(systemName: "checkmark").onyxType(.caption) }
                Text(tag.label).onyxType(.caption).fontWeight(.semibold).lineLimit(1)
            }
            .padding(.horizontal, OnyxSpace.m)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(on ? Color.onyx.accent(.recover).opacity(0.25) : Color.onyx.hairline))
            .foregroundStyle(on ? Color.onyx.accent(.recover) : Color.onyx.textSecondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag.label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: The note

    private var noteSection: some View {
        Section {
            // `TextField(axis: .vertical)`, not a `TextEditor`: the editor has
            // no placeholder, no intrinsic height and draws its own box inside
            // a `Form` row that is already a box.
            TextField("Note", text: $note, axis: .vertical)
                .lineLimit(1...4)
                .frame(minHeight: 44)
        } footer: {
            Text("Optional. It stays on your account and is never read by anything that scores a day.")
        }
    }

    private var clearSection: some View {
        Section {
            Button("Clear this reading", role: .destructive) {
                if let existing, model.deleteStress(id: existing.id) { dismiss() }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }

    private func save() {
        guard let level else { return }
        if model.logStress(at: Date(), level: level, tags: StressTag.sorted(tags), note: note) {
            dismiss()
        }
    }
}
