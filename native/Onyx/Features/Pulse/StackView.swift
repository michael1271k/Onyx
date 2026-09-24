import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// The supplement stack, in full — a screen, not a sheet.
///
/// ── WHY IT LEFT THE BOTTOM SHEET ────────────────────────────────────────────
/// The stack was a `DaySheet`: a modal list of nine items whose only gesture
/// was a tap that opened a confirmation dialog anchored to the SHEET's root, so
/// the question about the 22:00 magnesium appeared at the top of the screen
/// over the 10:30 multivitamin. A sheet is for one decision; the stack is a
/// place you go — it has sections, an editor, an archive and a `+`.
///
/// This is Apple's own Medications shape, and deliberately: Due · Taken · Later
/// is the vocabulary the phone already teaches, swipe-to-take is the gesture
/// Health uses for the same act, and the long-press menu is where iOS has put
/// "edit this row" since the beginning.
///
/// ── WHERE A SKIPPED DOSE LIVES ──────────────────────────────────────────────
/// In `Due`, struck through. The section is not "what you have not handled" —
/// under the credit rule an unhandled dose past its slot is already counted —
/// it is "today's decisions that are still open to change", and a skip is
/// exactly that. Putting it in a fifth section would file the one row you might
/// want to undo furthest from the one you would undo it with.
struct StackView: View {
    let model: DayModel

    @State private var adding = false
    @State private var editing: CustomSupplement?
    /// "Add from label database" (overhaul C3). The import sheet hands back a
    /// prefill; the edit sheet opens on it only after the import sheet has
    /// gone, because one presenter cannot hold two sheets at once.
    @State private var importing = false
    @State private var pending: LabelDraft?
    @State private var draft: LabelDraft?

    struct LabelDraft: Identifiable {
        let id = UUID()
        let prefill: DSLD.Prefill
    }

    private var doses: [SupplementDose] { model.doses }

    /// A past day says which day. Each row carries the dose in force THAT day
    /// (`Supplements.doseAt`), so the day before a change reads 300 mg where
    /// today reads 400 — and a screen titled only "Stack" would make that look
    /// like an edit that did not save.
    private var title: String {
        guard !model.isToday, let day = LogicalDay.date(fromISO: model.date) else { return "Stack" }
        return "Stack · \(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    var body: some View {
        List {
            if doses.isEmpty && model.archivedCustoms.isEmpty {
                Text("Nothing scheduled for this day.")
                    .onyxType(.body)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .plainRow()
            }

            section("Due", doses.filter { $0.state == .due || $0.state == .skipped })
            section("Taken", doses.filter { $0.state == .taken })
            section("Later", doses.filter { $0.state == .later })

            if !model.archivedCustoms.isEmpty {
                Section {
                    ForEach(model.archivedCustoms, id: \.id) { custom in
                        ArchivedRow(custom: custom, model: model)
                    }
                } header: {
                    OnyxSectionHeader("Archived", .fuel)
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(OnyxSpace.l)
        .scrollContentBackground(.hidden)
        .onyxScreen(.fuel)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.onyx.accent(.fuel))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { adding = true } label: { Label("Add by hand", systemImage: "square.and.pencil") }
                    Button { importing = true } label: { Label("Add from label database", systemImage: "text.magnifyingglass") }
                } label: {
                    Image(systemName: "plus").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Add a supplement")
            }
        }
        .sheet(isPresented: $adding) { SupplementEditSheet(model: model, editing: nil) }
        .sheet(isPresented: $importing, onDismiss: {
            draft = pending
            pending = nil
        }) {
            DSLDImportView(
                onAdd: { prefill in
                    pending = LabelDraft(prefill: prefill)
                    importing = false
                },
                onManual: { name in
                    pending = LabelDraft(prefill: DSLD.Prefill(
                        name: name, form: nil, doseAmount: nil, doseUnit: nil, micros: [:], otherIngredients: []))
                    importing = false
                }
            )
        }
        .sheet(item: $draft) { draft in
            SupplementEditSheet(model: model, editing: nil, prefill: draft.prefill)
        }
        .sheet(item: $editing) { custom in SupplementEditSheet(model: model, editing: custom) }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [SupplementDose]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { dose in
                    DoseRow(dose: dose, model: model, onEdit: { editing = model.custom(for: dose) })
                }
            } header: {
                OnyxSectionHeader("\(title) · \(items.count)", .fuel)
            }
        }
    }
}

// MARK: - One dose

/// ── THE DIALOG IS ON THE ROW ────────────────────────────────────────────────
/// `.confirmationDialog` presents from the view it is attached to. Attached to
/// a list's root it anchors to the top of the screen, which is what the old
/// sheet did and why the question never appeared to belong to the item it was
/// about. Each row owns its own — the same fix `PulseScale` made for the
/// weigh-in reason.
private struct DoseRow: View {
    let dose: SupplementDose
    let model: DayModel
    let onEdit: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirming = false
    @State private var frozen = false

    private var custom: CustomSupplement? { model.custom(for: dose) }
    private var skipped: Bool { dose.state == .skipped }

    /// What the thing IS, as a silhouette — the way Health draws a medication.
    ///
    /// Five shapes a reader tells apart in a list of nine, tinted from the
    /// item's own stored colour (`Color.onyx.supplement`). A skipped dose draws
    /// it tertiary so the glyph does not contradict the struck-through name.
    ///
    /// Dropped at the accessibility sizes for the reason `PulseRow.glyph`
    /// already gives: a 50 pt glyph beside a 50 pt word is a row with room for
    /// neither.
    @ViewBuilder
    private var glyph: some View {
        if !typeSize.isAccessibilitySize {
            Image(systemName: SupplementForm.parse(custom?.form)?.symbol ?? SupplementForm.unspecifiedSymbol)
                .imageScale(.medium)
                .foregroundStyle(skipped ? Color.onyx.textTertiary : Color.onyx.supplement(custom?.color))
                .frame(width: 24)
                .accessibilityHidden(true)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.m) {
            glyph
            VStack(alignment: .leading, spacing: 2) {
                Text(dose.name)
                    .onyxType(.body)
                    .strikethrough(skipped, color: Color.onyx.textTertiary)
                    .foregroundStyle(skipped ? Color.onyx.textTertiary : Color.onyx.textPrimary)
                if let caption {
                    Text(caption)
                        .onyxType(.caption)
                        .foregroundStyle(skipped ? Color.onyx.danger : Color.onyx.textSecondary)
                }
            }
            Spacer(minLength: OnyxSpace.s)
            if dose.trainingOnly == true, model.isTraining {
                Image(systemName: "bolt.fill")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.accent(.train))
                    .accessibilityHidden(true)
            }
            Text(dose.dose)
                .onyxType(.caption).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .plainRow()
        // ── Leading: the one act that needs no question ─────────────────────
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if dose.state != .taken {
                Button {
                    model.mark(dose, as: .taken)
                } label: {
                    Label("Taken", systemImage: "checkmark")
                }
                .tint(Color.onyx.good)
            } else {
                Button {
                    model.mark(dose, as: .cleared)
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
            }
        }
        // ── Trailing: the three that change the protocol ────────────────────
        .swipeActions(edge: .trailing) {
            if let custom {
                Button(role: .destructive) {
                    model.setArchived(custom, archived: true)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }
            Button {
                frozen = model.freezeTomorrow(dose)
            } label: {
                Label("Freeze", systemImage: "snowflake")
            }
            .tint(Color.onyx.accent(.recover))
            Button {
                if skipped { model.mark(dose, as: .cleared) } else { confirming = true }
            } label: {
                Label(skipped ? "Unskip" : "Skip", systemImage: skipped ? "arrow.uturn.backward" : "xmark")
            }
            .tint(Color.onyx.accent(.fuel))
        }
        .contextMenu {
            if custom != nil {
                Button("Edit", systemImage: "square.and.pencil", action: onEdit)
            }
            Button(skipped ? "Undo skip" : "Skip today", systemImage: skipped ? "arrow.uturn.backward" : "xmark") {
                model.mark(dose, as: skipped ? .cleared : .skipped)
            }
            Button("Freeze tomorrow", systemImage: "snowflake") { frozen = model.freezeTomorrow(dose) }
            if let custom {
                Button("Archive", systemImage: "archivebox") { model.setArchived(custom, archived: true) }
                Button("Delete", systemImage: "trash", role: .destructive) { model.delete(custom) }
            }
        }
        .confirmationDialog("Skip \(dose.name)?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Skip today", role: .destructive) { model.mark(dose, as: .skipped) }
        } message: {
            Text("\(dose.slotLabel) · \(dose.slotTime) · \(dose.dose). Its micronutrients stop counting towards today.")
        }
        .alert("Frozen for tomorrow", isPresented: $frozen) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(dose.name) is marked skipped tomorrow. Today is unchanged.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dose.name), \(dose.dose), \(spokenState)")
        .accessibilityHint(dose.state == .taken ? "Swipe to undo" : "Swipe to mark taken")
    }

    private var caption: String? {
        switch dose.state {
        case .skipped: "Skipped"
        case .taken: "Taken · \(dose.slotLabel) · \(dose.slotTime)"
        case .due, .later: "\(dose.slotLabel) · \(dose.slotTime)" + (dose.notes.map { " · \($0)" } ?? "")
        }
    }

    private var spokenState: String {
        switch dose.state {
        case .taken: "taken"
        case .skipped: "skipped"
        case .due: "due, counting towards today"
        case .later: "later, at \(dose.slotTime)"
        }
    }
}

// MARK: - An archived row

private struct ArchivedRow: View {
    let custom: CustomSupplement
    let model: DayModel

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.m) {
            // The same glyph a live row draws, in the inactive ink — an
            // archived row that is structurally unlike a live one is harder to
            // read, and the tint already says which it is.
            if !typeSize.isAccessibilitySize {
                Image(systemName: SupplementForm.parse(custom.form)?.symbol ?? SupplementForm.unspecifiedSymbol)
                    .imageScale(.medium)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(custom.name)
                    .onyxType(.body)
                    .foregroundStyle(Color.onyx.textTertiary)
                Text("Archived — its history still counts")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
            Spacer(minLength: OnyxSpace.s)
            Text(custom.dose)
                .onyxType(.caption).onyxNumeral()
                .foregroundStyle(Color.onyx.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .plainRow()
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { model.setArchived(custom, archived: false) } label: {
                Label("Re-add", systemImage: "arrow.uturn.backward")
            }
            .tint(Color.onyx.good)
        }
        .contextMenu {
            Button("Re-add", systemImage: "arrow.uturn.backward") { model.setArchived(custom, archived: false) }
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(custom) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(custom.name), \(custom.dose), archived")
    }
}

// MARK: - Add and edit

/// One form for both, and it now reaches every field the row has.
///
/// ── THE ASYMMETRY THIS FIXES ────────────────────────────────────────────────
/// Add could set the weekdays and the training-only flag; Edit could not. So
/// the only way to change an item's schedule was to delete it and add it again
/// — which takes the row's `schedule.key` with it, and that key is the join to
/// every `supplement_log` row the item ever wrote. A year of ticked history
/// stopped resolving, silently, because the item kept rendering under the
/// `custom:<id>` fallback that now matched nothing.
///
/// ── AND WHY THE DOSE IS TWO FIELDS ──────────────────────────────────────────
/// `dose` stays the display string every reader parses, because
/// `SupplementNutrients.doseUnits` decides whether a payload is MULTIPLIED by
/// regex-matching it: "2 tabs" delivers twice the label, "300 mg" already is
/// the label. Typing that string by hand is how a dose becomes "2 tabs w/
/// food" and the multiplier quietly goes to 1. An amount and a unit compose it
/// (`Supplements.doseText`), and the pair is stored beside it so the editor
/// never has to re-parse prose.
struct SupplementEditSheet: View {
    let model: DayModel
    let editing: CustomSupplement?
    /// A label from the DSLD import (overhaul C3): name, form, dose and the
    /// per-unit micros it fills in. Nil for the plain add and for an edit.
    var prefill: DSLD.Prefill? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var name = ""
    @State private var amount: Double?
    @State private var unit: DoseUnit?
    @State private var form: SupplementForm?
    @State private var time = ""
    @State private var days: Set<Int> = []
    @State private var trainingOnly = false
    @State private var loaded = false
    @FocusState private var focus: Field?

    /// No `.time`: the time is a wheel now, and a wheel takes no keyboard.
    private enum Field: Hashable { case name, amount }

    private static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var cleanName: String { name.trimmingCharacters(in: .whitespaces) }

    private var valid: Bool {
        !cleanName.isEmpty && (amount ?? 0) > 0 && unit != nil
    }

    var body: some View {
        DaySheet(
            editing == nil ? "Add a supplement" : "Edit",
            domain: .fuel, glass: false,
            primary: ("Save", valid, save)
        ) {
            Form {
                itemSection
                daysSection
            }
        }
        .onAppear(perform: load)
    }

    // MARK: The item

    private var itemSection: some View {
        Section {
            TextField("Name", text: $name)
                .focused($focus, equals: .name)

            Picker("Form", selection: $form) {
                Text("Not set").tag(SupplementForm?.none)
                ForEach(SupplementForm.allCases) { form in
                    Label(form.title, systemImage: form.symbol).tag(SupplementForm?.some(form))
                }
            }
            // A menu, not a segmented control: five options across a phone is
            // 60 pt each and "Capsule" truncates.
            .pickerStyle(.menu)

            // At an accessibility size a label plus two controls on one line
            // collapses the number field to about 20 pt. Two rows instead.
            if typeSize.isAccessibilitySize {
                amountField
                unitPicker
            } else {
                LabeledContent("Dose") {
                    HStack(spacing: OnyxSpace.s) {
                        amountField
                        unitPicker.labelsHidden()
                    }
                }
            }

            timeRows
        } header: {
            OnyxSectionHeader("Item", .fuel)
        } footer: {
            Text(prefillNote.map { dosePreview + " " + $0 } ?? dosePreview)
        }
    }

    // MARK: The time

    /// A toggle, and the wheel it reveals.
    ///
    /// ── WHY A WHEEL AND NOT `.compact` ──────────────────────────────────────
    /// The same reason `TimerSheet` gives: a compact `DatePicker` opens a
    /// popover, and a popover over a sheet is where one gesture becomes three.
    /// `[.hourAndMinute]` only — a dose has a time of day and no date, unlike
    /// the sleep window, which straddles midnight and therefore carries `.date`.
    ///
    /// ── AND WHY THE TOGGLE EXISTS AT ALL ────────────────────────────────────
    /// A wheel cannot express "no time". The column is nullable and an empty
    /// one is a real state — it lands in `customSlotsForDate`'s "—" bucket,
    /// which sorts first — so the absence needs a control of its own. Turning
    /// it off empties `time`, and `editCustomSupplement` sends that through as
    /// a genuine NULL rather than as an empty string.
    @ViewBuilder
    private var timeRows: some View {
        Toggle("Set a time", isOn: timeEnabled)
            .accessibilityHint("Off means the item has no set time and sits at the top of the stack.")
        if !time.isEmpty {
            DatePicker("Time", selection: timeBinding, displayedComponents: [.hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                // 128, as the sleep sheet clamps it: the wheel's intrinsic
                // height is 216 pt, which is two thirds of this Form.
                .frame(height: 128)
                .clipped()
                .accessibilityLabel("Time")
        }
    }

    /// The wheel's `Date`, over the `"HH:mm"` the row stores. `OnyxCore` owns
    /// both halves — the string is grouped on and ordered by, so its spelling
    /// is domain, not presentation.
    private var timeBinding: Binding<Date> {
        Binding(
            get: { Supplements.slotTime(from: time) ?? Self.defaultDoseTime },
            set: { time = Supplements.slotTimeString($0) }
        )
    }

    private var timeEnabled: Binding<Bool> {
        Binding(
            get: { !time.isEmpty },
            set: { time = $0 ? Supplements.slotTimeString(Self.defaultDoseTime) : "" }
        )
    }

    /// Where the wheel opens for a row that has never had a time: 09:00, not
    /// "now" — a stack is a protocol, and the minute you happened to add an
    /// item to it is not when you intend to take it.
    private static var defaultDoseTime: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private var amountField: some View {
        TextField("Amount", value: $amount, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            .focused($focus, equals: .amount)
            .frame(minWidth: 64, minHeight: 44)
            .onyxNumeral()
            .accessibilityLabel("Amount")
            .accessibilityHint("For example 300, or 2")
    }

    private var unitPicker: some View {
        Picker("Unit", selection: $unit) {
            Text("Unit").tag(DoseUnit?.none)
            ForEach(DoseUnit.allCases) { unit in
                Text(unit.rawValue).tag(DoseUnit?.some(unit))
            }
        }
        .pickerStyle(.menu)
        .frame(minHeight: 44)
    }

    /// What the row will read, said before it is saved. A count multiplies its
    /// micronutrient payload and a mass does not, and this is the only place
    /// that difference is visible before it starts moving the day's totals.
    /// What the label brought with it, said once under the form.
    private var prefillNote: String? {
        guard let prefill, !prefill.micros.isEmpty || !prefill.otherIngredients.isEmpty else { return nil }
        var parts: [String] = []
        if !prefill.micros.isEmpty { parts.append("\(prefill.micros.count) micronutrients from the label count toward your day") }
        if !prefill.otherIngredients.isEmpty { parts.append("\(prefill.otherIngredients.count) other ingredients are kept by name") }
        return parts.joined(separator: "; ") + "."
    }

    private var dosePreview: String {
        guard let amount, amount > 0, let unit else {
            return "An amount and a unit. \"2 tabs\" delivers twice the label; \"300 mg\" is the label itself."
        }
        let text = Supplements.doseText(amount: amount, unit: unit)
        return unit.isCount
            ? "Reads as \"\(text)\" — a count, so its micronutrients count that many times."
            : "Reads as \"\(text)\" — a mass, counted once."
    }

    // MARK: The days

    private var daysSection: some View {
        Section {
            HStack(spacing: OnyxSpace.xs) {
                ForEach(Array(Self.weekdays.enumerated()), id: \.offset) { index, label in
                    dayToggle(index, label)
                }
            }
            .frame(maxWidth: .infinity)
            Toggle("Training days only", isOn: $trainingOnly)
        } header: {
            OnyxSectionHeader("Days", .fuel)
        } footer: {
            Text("No day selected means every day. Nothing here touches the days already logged — an item's history is keyed to the item, not to its schedule.")
        }
    }

    private func dayToggle(_ index: Int, _ label: String) -> some View {
        let on = days.contains(index)
        return Button {
            if on { days.remove(index) } else { days.insert(index) }
        } label: {
            Text(label.prefix(1))
                .onyxType(.caption).fontWeight(.semibold)
                // 44, not 32: this row was add-only until W4 and is now on
                // the common path, so it has to meet the minimum like
                // everything else you tap twice a week.
                .frame(minWidth: 40, minHeight: 44)
                .background(Circle().fill(on ? Color.onyx.accent(.fuel).opacity(0.25) : Color.onyx.hairline))
                .foregroundStyle(on ? Color.onyx.accent(.fuel) : Color.onyx.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Loading and saving

    /// ── AN EXISTING ROW OPENS ON "NOT SET", A NEW ONE ON A PILL ─────────────
    /// Defaulting the form on an EDIT would stamp "pill" on every untouched row
    /// the first time its time was corrected — nine silent writes for one
    /// intended change.
    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let editing else {
            form = prefill?.form ?? .pill
            unit = prefill?.doseUnit ?? .mg
            name = prefill?.name ?? ""
            amount = prefill?.doseAmount
            return
        }
        name = editing.name
        time = editing.time ?? ""
        form = SupplementForm.parse(editing.form)
        days = Set(editing.schedule?.days ?? [])
        trainingOnly = editing.schedule?.trainingOnly ?? false
        // The stored pair first, the display string as a fallback — a row the
        // web wrote has only the string, and a dose the parser cannot read
        // leaves the fields empty rather than inventing a number.
        if let parts = Supplements.doseParts(editing) {
            amount = parts.amount
            unit = parts.unit
        }
    }

    private func save() {
        guard let amount, let unit, valid else { return }
        let dose = Supplements.doseText(amount: amount, unit: unit)
        let cleanTime = time.trimmingCharacters(in: .whitespaces)
        // The writers return whether the row landed. Dismissing regardless put
        // the failure banner on the screen the reader had just left.
        let landed: Bool
        if let editing {
            landed = model.editSupplement(
                editing,
                name: cleanName, dose: dose, doseAmount: amount, doseUnit: unit.rawValue,
                form: form?.rawValue, time: cleanTime,
                days: days.sorted(), trainingOnly: trainingOnly
            )
        } else {
            landed = model.addSupplement(
                name: cleanName, dose: dose, doseAmount: amount, doseUnit: unit.rawValue,
                time: cleanTime, days: days.sorted(),
                color: nil, form: form?.rawValue, notes: nil, trainingOnly: trainingOnly,
                micros: prefill?.micros, otherIngredients: prefill?.otherIngredients
            )
        }
        if landed { dismiss() }
    }
}
