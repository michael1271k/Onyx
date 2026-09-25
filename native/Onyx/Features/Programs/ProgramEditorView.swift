import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// One program: its name, its goal, whether it runs — and its days, which are
/// the routine builder's own sections (Precision E2).
///
/// ── THE DAYS ARE NOT A COPY ─────────────────────────────────────────────────
/// Below the program section this is `RoutineDaySections` over a
/// `RoutinesModel` for this program: add, duplicate, delete, reorder, rename,
/// weekday, and each day's `RoutineDayEditor` with sets/reps/rest per movement
/// and "Add a movement" through `ExercisePickerSheet`. The builder in Settings
/// and this screen write the same rows the same way.
struct ProgramEditorView: View {
    let programs: ProgramsModel
    let programId: String

    @State private var routines: RoutinesModel
    @State private var name: String
    /// Built on the tap, not in the sheet's builder: its init reads the
    /// weigh-in and the phase goals, and a builder re-runs on every redraw.
    @State private var goalSheet: GoalSetupModel?
    @FocusState private var nameFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    init(programs: ProgramsModel, programId: String) {
        self.programs = programs
        self.programId = programId
        _routines = State(initialValue: programs.routines(programId))
        _name = State(initialValue: programs.plan(programId)?.label ?? "")
    }

    private var plan: PlanInfo? { programs.plan(programId) }
    private var running: Bool { programs.runningId == programId }
    private var accent: Color { OnyxDomain.train.accent }

    var body: some View {
        List {
            programSection
            RoutineDaySections(model: routines)
        }
        .onyxFormBackground(.train)
        .navigationTitle(routines.programLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .toolbar { OnyxKeyboardDone { nameFocused = false } }
        .task { await routines.reload() }
        // The list above this screen stops observing while it is covered, so
        // the editor keeps the catalogue live itself — "Run" must redraw here.
        .task { await programs.observe() }
        // Committed on focus loss and on the way out, as every field in the
        // routine builder commits — a name typed and swiped away from is kept.
        .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
        .onDisappear { commitName() }
        .sheet(item: $goalSheet) { GoalSetupSheet(model: $0) }
        // No alert of its own: this screen is always pushed over
        // `ProgramsView`, whose alert reads the same `failure` — two bound to
        // one value would both try to present.
    }

    private var programSection: some View {
        Section {
            LabeledContent("Name") {
                TextField("Program name", text: $name)
                    .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                    .foregroundStyle(Color.onyx.textPrimary)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit(commitName)
            }
            Button {
                goalSheet = GoalSetupModel(
                    database: programs.database, userId: programs.userId, programId: programId,
                    programLabel: routines.programLabel, running: running,
                    hasDays: !routines.days.isEmpty, current: plan
                )
            } label: {
                LabeledContent {
                    HStack(spacing: OnyxSpace.xs) {
                        Text(plan.map(GoalSetupModel.summary) ?? "Set a goal")
                            .foregroundStyle(plan?.goal == nil ? accent : Color.onyx.textPrimary)
                            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                        // Opens a sheet, and says so the way a pushing row does.
                        Image(systemName: "chevron.right")
                            .onyxType(.caption)
                            .foregroundStyle(Color.onyx.textTertiary)
                            .accessibilityHidden(true)
                    }
                } label: {
                    Text("Goal").foregroundStyle(Color.onyx.textPrimary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .accessibilityHint("Sets the goal and the daily targets it produces")
            if running {
                LabeledContent("Status") {
                    // Ink, not the accent: in the accent it sat where the
                    // "Run this program" button sits and read as tappable.
                    Text(runningSince).foregroundStyle(Color.onyx.textSecondary)
                }
            } else {
                Button {
                    programs.activate(programId)
                } label: {
                    Label("Run this program", systemImage: "play.fill")
                }
                .frame(minHeight: 44)
                .accessibilityHint("Makes this the program Train deals your days from")
            }
        } header: {
            OnyxSectionHeader("Program", .train)
        } footer: {
            if !running {
                Text("Running it switches Train to these days and applies its goal's targets.")
            }
        }
    }

    private var runningSince: String {
        plan?.startedOn.flatMap(ProgramsModel.shortDate).map { "Running since \($0)" } ?? "Running"
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != plan?.label else { return }
        programs.rename(programId, to: trimmed)
        routines.programLabel = trimmed
    }
}
