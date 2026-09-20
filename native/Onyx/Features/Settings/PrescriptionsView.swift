import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// The coach's weekly audit, pasted — and read back before a word of it lands.
///
/// ── WHY THIS SCREEN IS MOSTLY A PREVIEW ─────────────────────────────────────
/// `PrescriptionPaste` is tolerant on purpose: it maps the columns it knows and
/// then scavenges every other cell for a figure, so a load written in a
/// sentence is still found. That tolerance is the whole reason the parser is
/// usable on a table a person retypes each week — and it is also why the number
/// it lands becomes the baseline every later `load Δ` in the export is drawn
/// against. A parser that guesses is fine. A parser that guesses SILENTLY is
/// not. So everything it read, every field it could not find and every line it
/// refused is on the screen above the one button that writes.
///
/// ── AND WHY A MISSING FIELD IS AN EM DASH, NOT AN ABSENCE ───────────────────
/// A row that simply omits the load the parser failed to find is indistinguishable
/// from a row for a bodyweight movement, and both of them look correct. The gap
/// has to occupy space or it is not a finding — it is a confirmation the athlete
/// gave without being shown what they were giving it to.
struct PrescriptionsView: View {
    let database: AppDatabase
    let userId: String

    /// The day the pasted instructions start. A `Date` because that is what a
    /// `DatePicker` binds; `yyyy-MM-dd` is what everything below the view
    /// speaks, and the conversion happens in exactly one place (`day`).
    ///
    /// Defaulted to today, and never inferred from the text — a coach's table
    /// rarely carries a date, and a wrong one re-dates the whole history
    /// silently, because `Prescriptions.current` resolves purely on this field.
    @State private var effectiveFrom = LogicalDay.date(fromISO: LogicalDay.today()) ?? Date()
    @State private var text = ""
    /// What is in force TODAY, re-read after every write. Held rather than
    /// recomputed in `body`: this one is a database round trip, unlike the
    /// parse above it.
    @State private var inForce: [Prescription] = []
    @State private var saved: Int?
    @State private var failure: String?
    /// A multiline editor's keyboard cannot be dismissed by its return key —
    /// return is a newline here — and the Save button lives underneath it.
    @FocusState private var editing: Bool

    private var day: String { LogicalDay.iso(effectiveFrom) }

    var body: some View {
        // Parsed ONCE per render rather than by four sections reading a
        // computed property. `parse` is pure and cheap, but four calls is four
        // chances for the preview, the warnings, the refusals and the button's
        // own count to describe different contents of the same box.
        let parsed = PrescriptionPaste.parse(text, effectiveFrom: day)
        return Form {
            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let saved {
                Section {
                    Label(
                        "\(saved) \(saved == 1 ? "prescription" : "prescriptions") saved",
                        systemImage: "checkmark.circle.fill"
                    )
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.good)
                }
            }

            paste
            date
            preview(parsed)
            notices(parsed)
            confirm(parsed)
            current
        }
        .onyxFormBackground(.train)
        .navigationTitle("Prescriptions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { OnyxKeyboardDone { editing = false } }
        .task { reload() }
    }

    // MARK: - The box

    private var paste: some View {
        Section {
            TextEditor(text: $text)
                .frame(minHeight: 160)
                // Monospaced digits: the thing being pasted is a table, and a
                // table whose columns shuffle as you scroll it is unreadable.
                .onyxNumeral()
                .foregroundStyle(Color.onyx.textPrimary)
                .focused($editing)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    // `TextEditor` has no placeholder, and the empty state of a
                    // paste target is most of how a person works out what is
                    // supposed to go in it. Both accepted shapes are shown,
                    // because the freeform one is the escape hatch for the week
                    // the coach writes prose instead of a table.
                    if text.isEmpty {
                        Text("| Exercise | Load | Sets × Reps | RPE |\nIncline DB Press | 34 kg | 3 × 8–12 | 8\n\nor one movement a line:\nRDL — 40 kg × 3 × 8–10 @8")
                            .onyxType(.caption)
                            .foregroundStyle(Color.onyx.textTertiary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            OnyxSectionHeader("Paste the audit", .train)
        } footer: {
            Text("A markdown table or one movement a line. Onyx reads the columns it recognises and scans the rest of each row for figures it can still use.")
        }
    }

    private var date: some View {
        Section {
            DatePicker("Starts on", selection: $effectiveFrom, displayedComponents: .date)
        } header: {
            OnyxSectionHeader("In force from", .train)
        } footer: {
            Text("The first day these instructions apply. Onyx never reads a date out of the text — a table rarely carries one, and the wrong date re-dates every comparison the export draws.")
        }
    }

    // MARK: - What was read

    @ViewBuilder
    private func preview(_ parsed: PrescriptionPaste.Result) -> some View {
        if !parsed.rows.isEmpty {
            Section {
                // Keyed on position, not on the movement: two rows for one
                // movement in a single paste is a coach editing a line in
                // place, both are meant to land, and `id: \.exercise` would
                // draw one of them and quietly hide the other.
                ForEach(Array(parsed.rows.enumerated()), id: \.offset) { _, p in
                    row(p)
                }
            } header: {
                OnyxSectionHeader(
                    "\(parsed.rows.count) \(parsed.rows.count == 1 ? "movement" : "movements") read",
                    .train
                )
            }
        }
    }

    /// One parsed movement.
    ///
    /// Every line is a single wrapping `Text` and nothing here carries a
    /// `lineLimit`, a `minimumScaleFactor` or a height. A row of fixed pieces —
    /// chips in an `HStack`, a trailing value column — is what truncates
    /// `42.5/37.5/37.5 kg` to `42.5/37…` at AX5, and a load the athlete cannot
    /// finish reading is the one thing this screen exists to show them.
    private func row(_ p: Prescription) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.exercise)
                .onyxType(.body)
                .foregroundStyle(Color.onyx.textPrimary)
            Text(scheme(p))
                .onyxType(.caption)
                .onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
            if let ladder = ladder(p) {
                Text(ladder)
                    .onyxType(.caption)
                    .onyxNumeral()
                    .foregroundStyle(Color.onyx.record)
            }
            if let notes = p.notes {
                Text(notes)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element, one sentence. Combined alone would read the em dashes
        // out as "dash", so the label is spelled for the ear instead.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(p))
    }

    /// `3 × 8–12 @ 34 kg · cap @8 · alternating`.
    ///
    /// The grammar is FIXED: sets, window, load and cap always occupy their
    /// place and an em dash stands in the one that was not found. The lead rule
    /// is the exception — `NONE` is a bilateral lift, the absence of the
    /// question rather than an unanswered one, so it prints nothing.
    private func scheme(_ p: Prescription) -> String {
        var out = "\(p.sets.map(String.init) ?? "—") × \(p.repRange ?? "—")"
        out += " @ " + (p.referenceLoadKg.map { OnyxFormat.kg($0) + " kg" } ?? "— kg")
        out += " · cap " + (p.rpeCap.map { "@" + OnyxFormat.rpe($0) } ?? "—")
        if p.leadRule != Prescription.LeadRule.none { out += " · " + label(p.leadRule) }
        return out
    }

    /// The per-set ladder, which only a top set / back-off has.
    ///
    /// A `TOPSET_BACKOFF` with ONE load is the parser saying the coach named a
    /// top set and never listed the back-offs (`PrescriptionPaste.finish`
    /// refuses to invent them). That is a gap in the paste, not a one-rung
    /// ladder, and printing `34 kg` here would read as the whole instruction.
    private func ladder(_ p: Prescription) -> String? {
        guard p.structure == .topsetBackoff, let loads = p.setLoads else { return nil }
        guard loads.count > 1 else { return "top set only — back-offs not stated" }
        return loads.map(OnyxFormat.kg).joined(separator: "/") + " kg"
    }

    private func label(_ rule: Prescription.LeadRule) -> String {
        switch rule {
        case .alternate: return "alternating"
        case .left: return "left leads"
        case .right: return "right leads"
        case .none: return "both sides"
        }
    }

    /// The row as a sentence. "Not stated" where the visible row shows a dash:
    /// VoiceOver reads an em dash as "dash" or as nothing at all depending on
    /// verbosity, and either way the gap stops being the point.
    private func spoken(_ p: Prescription) -> String {
        var parts = [p.exercise]
        parts.append(p.sets.map { "\($0) sets" } ?? "sets not stated")
        parts.append(p.repRange.map { "of \($0.replacingOccurrences(of: "–", with: " to ")) reps" }
                     ?? "rep range not stated")
        parts.append(p.referenceLoadKg.map { "at \(OnyxFormat.kg($0)) kilograms" } ?? "load not stated")
        parts.append(p.rpeCap.map { "R P E cap \(OnyxFormat.rpe($0))" } ?? "no R P E cap")
        if p.leadRule != Prescription.LeadRule.none { parts.append(label(p.leadRule)) }
        if let ladder = ladder(p) { parts.append(ladder.replacingOccurrences(of: "/", with: " then ")) }
        return parts.joined(separator: ", ")
    }

    // MARK: - What was not

    @ViewBuilder
    private func notices(_ parsed: PrescriptionPaste.Result) -> some View {
        if !parsed.warnings.isEmpty {
            Section {
                // `id: \.self` on strings would collapse two identical warnings
                // — and "no rep range" twice for two movements is exactly the
                // shape these take.
                ForEach(Array(parsed.warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning)
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.record)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                OnyxSectionHeader("Gaps", .train)
            } footer: {
                Text("These movements still save. The field named simply is not in the paste, and the export prints it as unknown rather than carrying a blueprint number forward as if it were an instruction.")
            }
        }

        if !parsed.skipped.isEmpty {
            Section {
                ForEach(Array(parsed.skipped.enumerated()), id: \.offset) { _, line in
                    // Verbatim, wrapped, unstyled beyond the token: this is the
                    // athlete's own text handed back, and editing it for
                    // display would hide the character that broke it.
                    Text(line)
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                OnyxSectionHeader("Not read", .train)
            } footer: {
                Text("Onyx refused these lines and nothing in them will be saved. If one was an instruction, rewrite it as `Movement — 34 kg × 3 × 8–12 @8` and paste again.")
            }
        }
    }

    @ViewBuilder
    private func confirm(_ parsed: PrescriptionPaste.Result) -> some View {
        Section {
            Button("Save \(parsed.rows.count) \(parsed.rows.count == 1 ? "prescription" : "prescriptions")") {
                save(parsed.rows)
            }
            .disabled(parsed.rows.isEmpty)
        } footer: {
            Text("Each save APPENDS a version — nothing is ever overwritten, so the day a load moved stays in the record.")
        }
    }

    // MARK: - What is in force

    @ViewBuilder
    private var current: some View {
        Section {
            if inForce.isEmpty {
                Text("None yet. Until the first one lands the export compares your sessions against the program's blueprint load, which is the number the block was compiled with and not what you are working to.")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Unique by construction: `currentPrescriptions` returns one
                // version per canonical movement name.
                ForEach(inForce, id: \.exercise) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.exercise)
                            .onyxType(.body)
                            .foregroundStyle(Color.onyx.textPrimary)
                        Text(scheme(p))
                            .onyxType(.caption)
                            .onyxNumeral()
                            .foregroundStyle(Color.onyx.textSecondary)
                        Text("v\(p.version) · from \(p.effectiveFrom)")
                            .onyxType(.micro)
                            .onyxNumeral()
                            .foregroundStyle(Color.onyx.textTertiary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(spoken(p)), version \(p.version), in force since \(p.effectiveFrom)")
                }
            }
        } header: {
            OnyxSectionHeader("In force today", .train)
        } footer: {
            Text("What this week's export will print as prescribed. A version dated after today is saved but not yet in force.")
        }
    }

    // MARK: - Actions

    /// TODAY, not the date in the picker. This list answers "what will the
    /// export print", and a prescription dated next Monday is saved but is not
    /// yet an instruction — showing it here would claim it already applied.
    private func reload() {
        do {
            inForce = try database
                .currentPrescriptions(userId: userId, on: LogicalDay.today())
                .values
                .sorted { $0.exercise < $1.exercise }
        } catch {
            failure = "Could not read the prescriptions already in force. \(error.localizedDescription)"
        }
    }

    private func save(_ drafts: [Prescription]) {
        editing = false
        do {
            let landed = try database.appendPrescriptions(drafts, userId: userId)
            saved = landed.count
            failure = nil
            // Cleared only on success. A paste left in the box after a failed
            // write is the athlete's only copy of it.
            text = ""
            reload()
        } catch {
            failure = "Could not save those prescriptions. \(error.localizedDescription)"
        }
    }
}

#if DEBUG
#Preview("Prescriptions") {
    NavigationStack {
        PrescriptionsView(
            database: try! .inMemory(deviceId: "preview"),
            userId: "preview"
        )
    }
}
#endif
