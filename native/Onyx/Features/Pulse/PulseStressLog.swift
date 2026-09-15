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
// They sit on one screen — the log in the carousel, the index in the square
// grid directly below it — so the separation has to be structural rather than a
// matter of wording:
//
//   • THE NUMERAL IS THE INDEX'S, AND ONLY THE INDEX'S. `StressSquare` owns the
//     `.display` integer and the `Sparkline`. Nothing in this file sets a
//     reading above `.body`. The only figures here are clock stamps at
//     `.caption` — metadata, not measurements.
//   • THE AXIS DIFFERS. The square's x-axis is fourteen days, drawn as a
//     continuous line; this card's x-axis is today's clock, drawn as discrete
//     stamps. The trailing words say so out loud: "14 days" against "N today".
//   • THE INK DIFFERS. The square takes `StressBand.tint`, whose two loaded
//     bands are Solar's stops (`OnyxDomain.fuel.start/end`) and appear nowhere
//     else on Pulse. A typed reading takes `Color.onyx.fatigue(level)` — the
//     shared severity ramp, the same one the fatigue card beside it uses,
//     because D6 folds the two answers into ONE term of the index.
//   • THE POSTURE DIFFERS. The square is a button onto a read-only breakdown.
//     This card carries its verb on its face.
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
        return "\(when) · \(word)"
    }

    /// The same fact, spelled for a reader who cannot see the capsule.
    static func spoken(_ reading: StressReading) -> String {
        let when = clock(reading) ?? "\(reading.slot.label), no time recorded"
        let word = PsychStress.level(reading.level)?.label ?? "level \(reading.level)"
        let tags = reading.tags.map(\.label).joined(separator: ", ")
        return "\(when), \(word)" + (tags.isEmpty ? "" : ", tagged \(tags)")
    }
}

// MARK: - The card

/// The day's readings on a time strip, and the button that adds one.
///
/// ── WHY A CAP AND NOT A WRAP ────────────────────────────────────────────────
/// This card is one page of a horizontal pager, so it cannot grow sideways, and
/// its sibling has to agree with it about height — a flow-wrapped strip
/// would set the carousel's height from the worst day anyone ever has, and
/// would change that height under the thumb the moment you logged. A day with
/// twelve readings is a real day; a card four hundred points tall is not.
///
/// So: the last three, in the order the day happened, and the ones before them
/// behind a marker that stands exactly where they would have been.
struct StressLogCard: View {
    let model: DayModel
    /// Both sheets are presented by `DayScreen`, not from here. This view is one
    /// page of a carousel inside a recyclable `List` row: a `.sheet` declared on
    /// a cell is torn down with the cell, which dismisses it the first time the
    /// list scrolls far enough — mid-typing, with the note unsaved.
    let onLog: () -> Void
    let onBrowse: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Oldest first — the strip reads left to right as the day did.
    private var readings: [StressReading] { model.stressReadings }

    /// Three at shipping type, two at an accessibility size, where one capsule
    /// is most of the card's width. The same branch `PulseRow` takes.
    private var visibleCount: Int { typeSize.isAccessibilitySize ? 2 : 3 }

    private var shown: [StressReading] { Array(readings.suffix(visibleCount)) }
    private var hidden: Int { max(0, readings.count - shown.count) }

    var body: some View {
        PulseCard(
            "Stress log",
            .recover,
            // The unit that says which axis this is. The index square's
            // trailing word is "14 days"; this one counts today.
            // "today" only on today: `DayScreen` draws past dates too (the
            // calendar, the chevrons, History's push), and a card that says
            // "3 today" while standing on 3 September is a card that lies about
            // the one axis its wording exists to name.
            trailing: readings.isEmpty ? nil : "\(readings.count) \(model.isToday ? "today" : "logged")"
        ) {
            strip
            Spacer(minLength: 0)
            PulseCardAction(symbol: "plus.circle.fill", title: "Log stress", action: onLog)
        }
    }

    // MARK: The strip

    @ViewBuilder
    private var strip: some View {
        if readings.isEmpty {
            // Not "0", and not an empty row. A day nobody answered is a day
            // with no reading, which is a different fact from a calm one — the
            // same rule `DayFormat.number` follows everywhere else.
            Text("Not reported")
                .onyxType(.secondary)
                .foregroundStyle(Color.onyx.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                earlier
                ForEach(shown) { reading in stackedRow(reading) }
            }
        } else {
            // `FlowRow`'s wrapping is what keeps two capsules and the marker on
            // one line at shipping type and lets them take two lines at
            // xxLarge, without a third layout branch to keep in step.
            FlowRow(spacing: OnyxSpace.xs) {
                earlier
                ForEach(shown) { reading in capsule(reading) }
            }
        }
    }

    /// The readings the cap cut, as one target, LEADING — where they happened.
    /// A marker on the trailing edge would claim the hidden ones came last.
    @ViewBuilder
    private var earlier: some View {
        if hidden > 0 {
            Button(action: onBrowse) {
                Text("+\(hidden) earlier")
                    .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
                    .padding(.horizontal, OnyxSpace.s)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(Color.onyx.hairline))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(hidden) earlier reading\(hidden == 1 ? "" : "s")")
            .accessibilityHint("Opens the whole day's log")
        }
    }

    private func capsule(_ reading: StressReading) -> some View {
        Text(StressStamp.label(reading))
            .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
            .foregroundStyle(Color.onyx.fatigue(reading.level))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, OnyxSpace.s)
            .frame(minHeight: 32)
            .background(Capsule().fill(Color.onyx.fatigue(reading.level).opacity(0.16)))
            .contentShape(Capsule())
            .modifier(StressEventActions(reading: reading, model: model))
    }

    /// At an accessibility size a capsule is the width of the card, so the
    /// stamp and the word take the two ends of a row instead of sharing one
    /// pill. Same target, same actions.
    private func stackedRow(_ reading: StressReading) -> some View {
        HStack(spacing: OnyxSpace.s) {
            Text(StressStamp.clock(reading) ?? reading.slot.label)
                .onyxType(.caption).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
            Spacer(minLength: OnyxSpace.s)
            // "13:10" and "Strained" cannot share a page's width at AX5, and
            // a level word cut to "Strai…" is a reading you cannot read.
            Text(PsychStress.level(reading.level)?.label ?? "—")
                .onyxType(.body).fontWeight(.semibold)
                .foregroundStyle(Color.onyx.fatigue(reading.level))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .modifier(StressEventActions(reading: reading, model: model))
    }
}

/// Delete, on a surface that has no swipe to give.
///
/// ── WHY NOT `.swipeActions` ─────────────────────────────────────────────────
/// Not a matter of taste: this card lives inside a horizontally paged
/// `ScrollView`, so a horizontal pan IS the page turn. A trailing swipe would
/// be fighting the pager on every attempt and would win at random. The plan
/// text says "swipe/long-press"; swipe is unavailable here and long-press is
/// the whole affordance. The full-log sheet below DOES have List rows, and
/// takes the swipe there.
///
/// `.contextMenu` alone is not a VoiceOver path — the rotor reads custom
/// actions, not menu items — so the two are declared together, which is the
/// pairing `DashboardGrid` already uses for its tiles.
private struct StressEventActions: ViewModifier {
    let reading: StressReading
    let model: DayModel

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Delete \(StressStamp.label(reading))", role: .destructive) {
                    model.deleteStress(id: reading.id)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(StressStamp.spoken(reading))
            // The same sentence the menu item carries: one operation named two
            // ways is two operations to anyone who cannot see that it is one.
            .accessibilityActions {
                Button("Delete \(StressStamp.label(reading))", role: .destructive) {
                    model.deleteStress(id: reading.id)
                }
            }
    }
}

// MARK: - The sheet that writes one

/// Five words, a time, seven optional chips and a line of your own.
///
/// ── WHY THE TIME IS A CONTROL NOW, AND WAS NOT BEFORE ───────────────────────
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

    @State private var level: Int?
    @State private var tags: Set<StressTag> = []
    @State private var note = ""
    @State private var at: Date?
    /// Whether the note is open. Closed on every open: the field is the one
    /// control on this sheet most days do not use, and 88 pt of `Form` for a
    /// line nobody types is the compaction W3 is spending everywhere else.
    @State private var noteOpen = false
    /// The chip grid's column minimum, scaled — see `tagSection`.
    ///
    /// 84, not 96 (W3). 96 packed three columns on a 375 pt phone with 30 pt of
    /// slack in each; 84 packs four, which takes the seven chips from three rows
    /// to two and ~50 pt off the sheet. The `@ScaledMetric` is what still
    /// reflows it to one column at the accessibility sizes, so the number below
    /// is a packing decision at shipping type and nothing else.
    @ScaledMetric(relativeTo: .footnote) private var chipWidth: CGFloat = 84

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
            glass: false,
            // A form: five words, a wheel and a chip grid do not fit a medium
            // detent even with the note folded away, and a sheet that opens
            // already clipped is worse than one that opens tall.
            detents: [.large],
            // `dayStart` nil means the date did not parse, which cannot
            // happen from a `LogicalDay` string — but if it ever did, `bounds`
            // would fall back to TODAY while `save` still files against
            // `model.date`, which is precisely the silent misfiling the clamp
            // below exists to prevent. So it disables Save instead.
            primary: ("Save", level != nil && dayStart != nil, save)
        ) {
            Form {
                wordAndTimeSection
                tagSection
                noteSection
            }
        }
        // ── "NOW" IS READ ONCE, NOT ON EVERY BODY PASS ──────────────────────
        // `bounds.upperBound` walks back to `Date()` through `model.clock`, and
        // this sheet's body re-evaluates on every keystroke in the note and
        // every tag tap. Left derived, the wheel visibly moves under the finger
        // and — worse — a reading started at 17:58 under a footer saying
        // "Files under midday" saves at 18:01 under evening, a slot the reader
        // was never shown and never chose.
        .task { if at == nil { at = bounds.upperBound } }
    }

    // MARK: The five words, and the clock

    /// ── ONE SECTION, NOT TWO (W3) ───────────────────────────────────────────
    /// The word and the time were two `Form` sections: two headers, two footers
    /// and ~34 pt of inter-section inset between a question and the clock it is
    /// being answered about. They are one act — you say how it was, and when —
    /// and merging them takes ~90 pt off a sheet that opens at `.large` because
    /// it did not fit a medium detent.
    ///
    /// Both footers survive verbatim, in the order they are read. The anchors
    /// explain the five words; the slot line explains that the bucket is derived
    /// and never chosen, which is the one thing a reader who has only ever seen
    /// the three slot names needs told.
    private var wordAndTimeSection: some View {
        Section {
            FiveWordPicker(words: PsychStress.levels.map(FiveWordPicker.Word.init), selected: level) { value in
                level = value
            }
            .listRowInsets(EdgeInsets(
                top: OnyxSpace.s, leading: OnyxSpace.s, bottom: OnyxSpace.s, trailing: OnyxSpace.s
            ))
            DatePicker(
                "Time",
                // ── THE CLAMP IS THE BINDING'S JOB, NOT THE PICKER'S ────────
                // `AppDatabase.logStress` takes the logical `date` and the
                // instant `loggedAt` as two independent parameters and asserts
                // nothing about their agreeing. A time that escaped the day
                // would file the row under one date while its stamp said
                // another — the reading would count toward the wrong day's mean
                // silently, with no error and nothing on screen to show it. The
                // range below stops the wheel; this stops everything else.
                selection: Binding(
                    get: { when },
                    set: { at = min(max($0, bounds.lowerBound), bounds.upperBound) }
                ),
                in: bounds,
                displayedComponents: .hourAndMinute
            )
            .frame(minHeight: 44)
        } header: {
            OnyxSectionHeader("How it was, and when", .recover)
        } footer: {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                Text(anchors)
                // The bucket, stated rather than chosen. A reader who has only
                // ever seen the three slot names needs to know they still exist
                // and that nothing here asks them to pick one.
                Text("Files under \(slot.label.lowercased()). The part of the day is worked out from the time — you never pick it.")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var anchors: String {
        guard let first = PsychStress.levels.first, let last = PsychStress.levels.last else { return "" }
        return "\(first.label) = \(first.hint). \(last.label) = \(last.hint)."
    }

    // MARK: The chips

    private var tagSection: some View {
        Section {
            // An adaptive grid reflows to one column at an accessibility size
            // with no branch of its own. `.adaptive`'s minimum is a raw point
            // value and does not know about Dynamic Type, so at AX5 the grid
            // still packs three ~100 pt columns and "Family", "Travel" and
            // "Health" all truncate inside them; `@ScaledMetric` moves the
            // minimum with the text, which is what makes the reflow happen.
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

    /// ── FOLDED AWAY UNTIL IT IS WANTED (W3) ─────────────────────────────────
    /// A four-line `TextField` and its footer is ~88 pt at the bottom of a sheet
    /// whose primary control is five words at the top, and the note is optional
    /// on a reading most days answer in one tap. Behind a disclosure it costs
    /// one 44 pt row, and the row carries what was typed so closing it is not
    /// the same as losing it.
    ///
    /// NOT a `.sheet` or a second screen: the note is saved by the same Save
    /// button as everything else on this form, and a control that leaves the
    /// form is a control that has to be brought back to it.
    private var noteSection: some View {
        Section {
            DisclosureGroup(isExpanded: $noteOpen) {
                // `TextField(axis: .vertical)`, not a `TextEditor`: the editor
                // has no placeholder, no intrinsic height and draws its own box
                // inside a `Form` row that is already a box.
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(1...4)
                    .frame(minHeight: 44)
            } label: {
                HStack(spacing: OnyxSpace.s) {
                    Text("Note").onyxType(.body)
                    Spacer(minLength: OnyxSpace.s)
                    // What is in there, when it is shut. A disclosure that hides
                    // a line you already typed and gives no sign of it is a
                    // disclosure that loses work.
                    if !noteOpen, !note.isEmpty {
                        Text(note)
                            .onyxType(.caption)
                            .foregroundStyle(Color.onyx.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: 44)
            }
        } footer: {
            Text("Optional. It stays on your account and is never read by anything that scores a day.")
        }
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
