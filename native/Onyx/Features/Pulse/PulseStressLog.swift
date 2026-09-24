import SwiftUI
import OnyxUI
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// THE STRESS LOG — what you typed, when you typed it (founder decision 1).
//
// This file replaces `PulseHead.swift`. The old name is gone from every
// surface — the tile, the row, the sheet, the Quick Log spoke and the export's
// own comments — because it named a body part rather than the reading, and the
// reading is stress. W6's gate greps for the quoted word, so it is not written
// here either.
//
// ── TWO THINGS CALLED STRESS, AND HOW THEY STAY APART ───────────────────────
// `PulseStress.swift` is the stress INDEX: 0–100, computed from HRV, the
// night, this log and training load, against your own fortnight. This file is
// the stress LOG: any number of 1–5 readings a day, each stamped with when you
// felt it. One is a measurement you cannot argue with; the other is an opinion
// you are asked for, and it is an INPUT to the first.
//
// They sit on one screen — two squares of the same grid since W9 — so the
// separation has to be structural rather than a matter of wording. The four
// rules are stated on `StressLogSquare` (`PulseSquares.swift`), which is where
// the log is drawn; this file keeps the stamp formatter and the two sheets.
// ─────────────────────────────────────────────────────────────────────────────

/// A stored reading, as the strip prints it.
enum StressStamp {

    /// `15:40`, in the reader's own clock — 12- or 24-hour as the device is
    /// set, which is what `SleepEditSheet`'s window line already does.
    ///
    /// ── AND WHY THE EXPORT DOES NOT USE THIS ────────────────────────────────
    /// `WeeklyExportBuilder` writes a fixed `HH:mm`. That string is parsed by
    /// whatever reads a week, and a file whose timestamps change shape with a
    /// device setting is a file nothing can parse. A screen has the opposite
    /// requirement, so the two formats are deliberately different and neither
    /// is derived from the other.
    static func clock(_ reading: StressReading) -> String? {
        reading.loggedAt?.formatted(Date.FormatStyle(date: .omitted, time: .shortened))
    }

    /// What the capsule says. A row written before the event log existed has no
    /// time at all, and prints the only thing it knows — its bucket.
    static func label(_ reading: StressReading) -> String {
        let when = clock(reading) ?? reading.slot.label
        guard let word = PsychStress.level(reading.level)?.label else { return when }
        return "\(when)\u{00A0}· \(word)"
    }

    /// The same fact, spelled for a reader who cannot see the capsule.
    static func spoken(_ reading: StressReading) -> String {
        let when = clock(reading) ?? "\(reading.slot.label), no time recorded"
        let word = PsychStress.level(reading.level)?.label ?? "level \(reading.level)"
        let tags = reading.tags.map(\.label).joined(separator: ", ")
        return "\(when), \(word)" + (tags.isEmpty ? "" : ", tagged \(tags)")
    }
}

// MARK: - The sheet that writes one

/// Five words, a time, seven optional chips and a line of your own — all of it
/// at once, at half height.
///
/// ── WHY IT IS NOT A `Form` ANY MORE (W11) ───────────────────────────────────
/// It was three `Form` sections and it opened `.large`, because a grouped form
/// spends a header, a footer and ~34 pt of inter-section inset on every one of
/// three questions that between them take four taps. The reading is a mood, a
/// minute and up to seven words; asking for it over a full-height scroll made
/// the smallest entry in the app look like the biggest.
///
/// What actually cost the height was prose, not controls. Four footers stated
/// the anchors, that the bucket is derived, that tags are not scored and that
/// the note is not read — ~120 pt of type for facts a reader needs ONCE. They
/// are all still here: the anchors are the line under the words (and become
/// the chosen rung's own definition once you have picked one), the derived
/// bucket is the picker's own subtitle and moves as you move the wheel, and
/// the two "yours, not scored" promises are one line at the foot.
///
/// ── AND WHY THE CHIPS ARE A `FlowRow` AND NOT A GRID ────────────────────────
/// `LazyVGrid(.adaptive(minimum:))` gives every chip the same width, so
/// "Work" was as wide as "Family" and seven short words took three columns of
/// dead space. `FlowRow` (OnyxUI since this wave) packs them at their own
/// widths — four on the first line, three on the second, ~50 pt saved — and
/// wraps rather than shrinking at an accessibility size.
///
/// ── WHY THE TIME IS A CONTROL AT ALL ────────────────────────────────────────
/// The sheet this replaces stated the slot as a heading and offered no way to
/// change it, on the reasoning that "which part of the day is this about" is a
/// question the clock already answers. That was right while a day held three
/// buckets and you answered each as it arrived. Under an event log the reading
/// carries its own timestamp and the founder asked for backdating: you notice
/// at nine in the evening that the afternoon was the bad part, and the reading
/// belongs at four. So the picker is here, it defaults to now, and it cannot
/// leave the day — the slot stays derived (`StressSlot.forMinutes`), so what
/// you set is a TIME and never a bucket.
///
/// ── AND WHY IT STILL OPENS BLANK ────────────────────────────────────────────
/// Every Save is a new event. There is nothing to pre-fill, and pre-filling the
/// latest reading would make the sheet look like an editor for a row it would
/// in fact duplicate.
struct StressLogSheet: View {
    let model: DayModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var level: Int?
    @State private var tags: Set<StressTag> = []
    @State private var note = ""
    @State private var at: Date?

    /// Midnight to now on the day being logged.
    ///
    /// A calendar day rather than the night window: the slot a reading falls in
    /// is decided by minutes since local midnight (`StressSlot.forMinutes`), so
    /// a picker that could produce a time outside that range could produce a
    /// reading whose slot and stamp disagree.
    ///
    /// ── THE CEILING COMES FROM `model.clock`, NOT FROM `Date()` ─────────────
    /// `DayClock.nowMinutes` is nil exactly when the date being viewed is not
    /// today, which is the same signal `StressSlot.forClock` and `FatigueSheet`
    /// read — so a finished day caps at its own last minute and today caps at
    /// now, from one source. Reading the wall clock instead would also make the
    /// preview's pinned clock a lie, and the committed screenshot would move
    /// whenever it was taken.
    private var dayStart: Date? {
        LogicalDay.date(fromISO: model.date).map { Calendar.current.startOfDay(for: $0) }
    }

    private var bounds: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = dayStart ?? calendar.startOfDay(for: Date())
        let lastMinute = 24 * 60 - 1
        let cap = min(model.clock.nowMinutes ?? lastMinute, lastMinute)
        let end = calendar.date(byAdding: .minute, value: cap, to: start) ?? start
        return start...max(start, end)
    }

    /// Now, on today; the last minute of the day on a day that has finished —
    /// which is `StressSlot.forClock`'s own rule for a day already over, so a
    /// late answer files where that function would have filed it.
    private var when: Date { at ?? bounds.upperBound }

    private var slot: StressSlot { StressSlot.forMinutes(PsychStress.minuteOfDay(when)) }

    var body: some View {
        DaySheet(
            "Log stress",
            domain: .recover,
            // ── HALF HEIGHT, EXCEPT WHERE HALF IS A LIE (W11) ───────────────
            // Everything above fits ~290 pt and a medium detent leaves ~380 pt
            // under the bar on the shot device. At an accessibility size it
            // does not and cannot: the words stack into a column of five, the
            // chips wrap to one per line, and a sheet that opens already
            // clipped is worse than one that opens tall. The Fuel tab's day
            // picker takes the same branch for the same reason.
            detents: typeSize.isAccessibilitySize ? [.large] : [.medium],
            // `dayStart` nil means the date did not parse, which cannot
            // happen from a `LogicalDay` string — but if it ever did, `bounds`
            // would fall back to TODAY while `save` still files against
            // `model.date`, which is precisely the silent misfiling the clamp
            // in `time` exists to prevent. So it disables Save instead.
            primary: ("Save", level != nil && dayStart != nil, save)
        ) {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                FiveWordPicker(words: PsychStress.levels.map(FiveWordPicker.Word.init), selected: level) { value in
                    level = value
                }
                definition
                time
                chips
                TextField("Note", text: $note)
                    .onyxType(.body)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, OnyxSpace.m)
                    .background(
                        RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                            .fill(Color.onyx.hairline.opacity(0.6))
                    )
                    .accessibilityLabel("Note")
                // The two promises the deleted footers made, in one line: a tag
                // is report-only (`StressTag`'s own header) and the note reaches
                // nothing that scores a day.
                Text("Tags and the note are yours. Nothing here is scored.")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // ── "NOW" IS READ ONCE, NOT ON EVERY BODY PASS ──────────────────────
        // `bounds.upperBound` walks back to `Date()` through `model.clock`, and
        // this sheet's body re-evaluates on every keystroke in the note and
        // every tag tap. Left derived, the wheel visibly moves under the finger
        // and — worse — a reading started at 17:58 under a caption saying
        // "Files under midday" saves at 18:01 under evening, a slot the reader
        // was never shown and never chose.
        .task { if at == nil { at = bounds.upperBound } }
    }

    // MARK: The line under the words

    /// The anchors before you pick, the chosen rung's own definition after.
    ///
    /// One line at shipping type either way, and it is the whole of what two
    /// of the four deleted `Form` footers said about the scale. The anchors are
    /// what keep "Tense" meaning the same thing in March as in August
    /// (`PsychStress.levels`); once a rung IS chosen the anchors have done
    /// their work and the useful sentence is that rung's — which is also the
    /// one VoiceOver already reads as the cell's hint, so the two agree by
    /// construction.
    private var definition: some View {
        Text(scaleLine)
            .onyxType(.caption)
            .foregroundStyle(Color.onyx.textSecondary)
            // It WRAPS rather than shrinking or truncating. Both strings are
            // one line at shipping type on a 402 pt phone and neither can be
            // at AX5 — the first AX5 shot read "Relaxed = nothing…", which is
            // an anchor with its own anchor cut off. There is nothing below
            // this line that a second line would push off a sheet that is
            // already `.large` at those sizes.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }

    private var scaleLine: String {
        if let level, let picked = PsychStress.level(level) {
            return "\(picked.label) — \(picked.hint)."
        }
        guard let first = PsychStress.levels.first, let last = PsychStress.levels.last else { return "" }
        return "\(first.label) = \(first.hint). \(last.label) = \(last.hint)."
    }

    // MARK: The clock, and the bucket it lands in

    /// `.compact`, with the derived slot on the line under it.
    ///
    /// The bucket was a `Form` footer two sections away. It is now the caption
    /// directly beneath the control that decides it and it moves when that
    /// control moves, so "you never pick it" is something the screen
    /// demonstrates rather than asserts.
    ///
    /// ── AND WHY IT IS NOT THE PICKER'S OWN SUBTITLE ─────────────────────────
    /// It was, for one shot: a two-line label inside `DatePicker`. A compact
    /// picker takes its width from the right and gives the label whatever is
    /// left, which at an accessibility size is a column about four characters
    /// wide — the AX5 shot read "Files / under / …" one word per line beside
    /// the clock. Under it the caption gets the full width at every size, and
    /// the line it costs at shipping type is ~17 pt of the ~99 pt the sheet has
    /// spare inside a medium detent.
    private var time: some View {
        VStack(alignment: .leading, spacing: 2) {
            picker
            Text("Files under \(slot.label.lowercased()) — you never pick it")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var picker: some View {
        DatePicker(
            // ── THE CLAMP IS THE BINDING'S JOB, NOT THE PICKER'S ────────────
            // `AppDatabase.logStress` takes the logical `date` and the instant
            // `loggedAt` as two independent parameters and asserts nothing
            // about their agreeing. A time that escaped the day would file the
            // row under one date while its stamp said another — the reading
            // would count toward the wrong day's mean silently, with no error
            // and nothing on screen to show it. The range below stops the
            // wheel; this stops everything else.
            selection: Binding(
                get: { when },
                set: { at = min(max($0, bounds.lowerBound), bounds.upperBound) }
            ),
            in: bounds,
            displayedComponents: .hourAndMinute
        ) {
            Text("Time").onyxType(.body)
        }
        .datePickerStyle(.compact)
        .frame(minHeight: 44)
    }

    // MARK: The chips

    private var chips: some View {
        FlowRow(spacing: OnyxSpace.xs) {
            ForEach(StressTag.allCases, id: \.self) { tag in chip(tag) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What's on it")
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
            // 44 and not the 30 the cardio sheet's kind chips take: these are
            // toggles a reader taps two or three of, not a one-of-six picker,
            // and `FlowRow` charges nothing for the height of a line it was
            // going to draw anyway.
            .frame(minHeight: 44)
            .background(Capsule().fill(on ? Color.onyx.accent(.recover).opacity(0.25) : Color.onyx.hairline))
            .foregroundStyle(on ? Color.onyx.accent(.recover) : Color.onyx.textSecondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag.label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func save() {
        guard let level, dayStart != nil else { return }
        if model.logStress(at: when, level: level, tags: StressTag.sorted(tags), note: note) {
            dismiss()
        }
    }
}

// MARK: - The whole day

/// Every reading on the date, as rows — the destination of "+N earlier", and
/// the one surface where deleting is a swipe because the rows are `List` rows.
struct StressLogListSheet: View {
    let model: DayModel

    private var readings: [StressReading] { model.stressReadings }

    var body: some View {
        DaySheet("Stress log", domain: .recover, glass: false, detents: [.large]) {
            List {
                if readings.isEmpty {
                    Text("Not reported")
                        .onyxType(.secondary)
                        .foregroundStyle(Color.onyx.textTertiary)
                        .frame(minHeight: 44)
                } else {
                    ForEach(readings) { reading in row(reading) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onyxScreen(.recover)
        }
    }

    private func row(_ reading: StressReading) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            HStack(spacing: OnyxSpace.s) {
                Text(StressStamp.clock(reading) ?? reading.slot.label)
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
                Spacer(minLength: OnyxSpace.s)
                Text(PsychStress.level(reading.level)?.label ?? "—")
                    .onyxType(.body).fontWeight(.semibold)
                    .foregroundStyle(Color.onyx.fatigue(reading.level))
                    .lineLimit(1)
            }
            // Tags and the note are the two things the strip has no room for
            // and the reason this sheet is worth opening at all.
            if !reading.tags.isEmpty {
                Text(reading.tags.map(\.label).joined(separator: " · "))
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
            if let note = reading.note, !note.isEmpty {
                Text(note)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 44)
        .listRowInsets(EdgeInsets(top: OnyxSpace.s, leading: OnyxSpace.l, bottom: OnyxSpace.s, trailing: OnyxSpace.l))
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.onyx.hairline)
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { model.deleteStress(id: reading.id) }
        }
        .accessibilityElement(children: .ignore)
        // The note is drawn on this row and nowhere else — it is half of why
        // this sheet is worth opening — so it has to be spoken here too.
        .accessibilityLabel(StressStamp.spoken(reading) + (reading.note.map { ", note: \($0)" } ?? ""))
        .accessibilityActions {
            Button("Delete \(StressStamp.label(reading))", role: .destructive) {
                model.deleteStress(id: reading.id)
            }
        }
    }
}
