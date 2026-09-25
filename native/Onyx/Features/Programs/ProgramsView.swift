import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// Every program the account has, which one is running, and where a new one
/// comes from (Precision E2, decision: Hevy-style programs in Train).
///
/// ── A GROUPED LIST, BECAUSE IT IS ONE ───────────────────────────────────────
/// Settings-shaped content — rows you pick, swipe and push into — so the stock
/// inset list on the Train ground, the same vocabulary as the routine builder
/// it leads to. The running program is marked by a filled ring and the word
/// "Running" in the train accent: the one tinted thing on the screen.
///
/// ── NEW PROGRAMS ARE BENCHED ────────────────────────────────────────────────
/// A blank program or a template copy opens straight into its editor and is
/// NOT run. Running one moves the deck, the phase and the macros at once, and
/// dates an era, so it is its own gesture (swipe → Run, or the editor's
/// button).
struct ProgramsView: View {
    @State private var model: ProgramsModel
    @State private var opened: Opened?
    @State private var pendingDelete: PlanInfo?
    @Environment(\.dynamicTypeSize) private var typeSize

    init(model: ProgramsModel) {
        _model = State(initialValue: model)
    }

    /// The program an action just created, pushed by value.
    struct Opened: Hashable { let id: String }

    private var accent: Color { OnyxDomain.train.accent }

    var body: some View {
        List {
            Section {
                ForEach(model.live, id: \.id) { plan in row(plan) }
            } header: {
                OnyxSectionHeader("Yours", .train)
            } footer: {
                Text(model.live.isEmpty
                     ? "No programs yet. Start from a template or a blank one below."
                     : "Swipe a program to run it or delete it.")
            }

            Section {
                ForEach(PlanTemplates.plans, id: \.id) { template in
                    newRow(
                        "\(template.label) template",
                        detail: Self.templateDetail(template),
                        systemImage: "doc.on.doc"
                    ) { model.startFrom(template) }
                }
                newRow("Blank program", detail: "Name it, then add your days", systemImage: "plus") {
                    model.createBlank()
                }
            } header: {
                OnyxSectionHeader("New program", .train)
            }

            if !model.past.isEmpty {
                Section {
                    ForEach(model.past, id: \.id) { plan in row(plan) }
                } header: {
                    OnyxSectionHeader("Past programs", .train)
                }
            }
        }
        .onyxFormBackground(.train)
        .navigationTitle("Programs")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.observe() }
        .navigationDestination(item: $opened) { opened in
            ProgramEditorView(programs: model, programId: opened.id)
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.label ?? "this program")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let plan = pendingDelete { model.delete(plan.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Its days, goal and targets go with it. Sessions you logged are kept.")
        }
        .alert(
            "Not changed",
            isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
        ) {
            Button("OK", role: .cancel) { model.failure = nil }
        } message: {
            Text(model.failure ?? "")
        }
    }

    // MARK: - Rows

    private func row(_ plan: PlanInfo) -> some View {
        let running = plan.id == model.runningId
        return NavigationLink {
            ProgramEditorView(programs: model, programId: plan.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.m) {
                RunningMark(running: running, tint: accent)
                VStack(alignment: .leading, spacing: 2) {
                    // The goal chip beside the name at every ordinary size;
                    // under it at the accessibility sizes, where a chip beside
                    // a two-line name leaves the name three characters wide.
                    if typeSize.isAccessibilitySize {
                        name(plan)
                        if let goal = plan.goal { GoalChip(goal: goal, tint: running ? accent : nil) }
                    } else {
                        HStack(spacing: OnyxSpace.s) {
                            name(plan)
                            if let goal = plan.goal { GoalChip(goal: goal, tint: running ? accent : nil) }
                        }
                    }
                    meta(plan, running: running)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(running ? "Running" : "")
        .swipeActions(edge: .leading) {
            if !running {
                Button { model.activate(plan.id) } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .tint(accent)
            }
        }
        .swipeActions(edge: .trailing) {
            if !running {
                Button(role: .destructive) { pendingDelete = plan } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func name(_ plan: PlanInfo) -> some View {
        Text(plan.label)
            .onyxType(.body).fontWeight(.semibold)
            .foregroundStyle(Color.onyx.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "Running · 5 days · since 15 Jul". One `Text` at ordinary sizes so it
    /// wraps as a sentence; its parts stacked at the accessibility sizes,
    /// where a joined line broke as "since 15" / "Jul".
    @ViewBuilder
    private func meta(_ plan: PlanInfo, running: Bool) -> some View {
        let parts = (running ? ["Running"] : []) + model.metaParts(plan)
        if typeSize.isAccessibilitySize {
            ForEach(parts, id: \.self) { part in
                Text(part)
                    .onyxType(.secondary)
                    .fontWeight(part == "Running" ? .semibold : .regular)
                    .foregroundStyle(part == "Running" ? Color.onyx.textPrimary : Color.onyx.textSecondary)
            }
        } else {
            ((running
                ? Text("Running").fontWeight(.semibold).foregroundStyle(Color.onyx.textPrimary)
                    + Text(" · ").foregroundStyle(Color.onyx.textSecondary)
                : Text(""))
            + Text(model.metaParts(plan).joined(separator: " · ")).foregroundStyle(Color.onyx.textSecondary))
            .onyxType(.secondary)
        }
    }

    private func newRow(
        _ title: String, detail: String, systemImage: String, create: @escaping () -> String?
    ) -> some View {
        Button {
            if let id = create() { opened = Opened(id: id) }
        } label: {
            HStack(spacing: OnyxSpace.m) {
                // Ink, not the accent: the running program is the one tinted
                // thing on this screen.
                Image(systemName: systemImage)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .onyxType(.body)
                        .foregroundStyle(Color.onyx.textPrimary)
                    Text(detail)
                        .onyxType(.secondary)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// "5 days · antagonist hybrid" — the template's day count and its kind,
    /// not its founder's weekday map, and nothing that repeats its name
    /// ("Historical Push/Pull/Legs" under "Push/Pull/Legs template").
    static func templateDetail(_ template: PlanTemplates.TemplatePlan) -> String {
        let clause = (template.blurb.components(separatedBy: CharacterSet(charactersIn: "—.")).first ?? "")
            .replacingOccurrences(of: #"^\d+-day\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let days = "\(template.days.count) days"
        guard !clause.isEmpty, !clause.localizedCaseInsensitiveContains(template.label) else { return days }
        return "\(days) · \(clause)"
    }
}

/// The running mark: a check in the accent beside the program in force, an
/// empty slot of the same width beside the rest, so every name starts on one
/// line. Not a ring — a filled ring among hollow ones is the iOS radio button,
/// and this row does not select on tap (it opens the program).
struct RunningMark: View {
    let running: Bool
    let tint: Color

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .onyxType(.body)
            .foregroundStyle(tint)
            .opacity(running ? 1 : 0)
            .accessibilityHidden(true)
    }
}

/// A program's goal as a chip — caption semibold in a capsule. Tinted on the
/// running program only (the screen's one tinted thing), ink elsewhere.
struct GoalChip: View {
    let goal: ProgramGoal
    var tint: Color?

    var body: some View {
        // The label is ink; the accent lives only in the fill — accent text
        // on an accent wash read near 3.5:1.
        Text(goal.label)
            .onyxType(.caption).fontWeight(.semibold)
            .foregroundStyle(tint == nil ? Color.onyx.textSecondary : Color.onyx.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, OnyxSpace.s)
            .padding(.vertical, 2)
            .background((tint ?? Color.onyx.textSecondary).opacity(tint == nil ? 0.14 : 0.22), in: .capsule)
            .fixedSize()
    }
}
