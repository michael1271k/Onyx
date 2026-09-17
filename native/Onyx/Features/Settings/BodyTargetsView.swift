import SwiftUI
import OnyxUI
import OnyxCore

/// Where the plan is going: three numbers, and nothing else.
///
/// ── THREE METRICS THAT ARE NOT THE SAME METRIC ──────────────────────────────
/// Skeletal muscle (~26.8 kg), lean soft tissue (~50.3 kg) and fat-free mass
/// (~53.1 kg) are three different readings of the same body, and the app has
/// conflated them before. The row here is SKELETAL MUSCLE — the figure the scale
/// reports and the only one of the three a person can set a target for, because
/// the other two are derived.
///
/// ── AND WHY THERE ARE STILL NO TAPE MEASUREMENTS *HERE* ─────────────────────
/// This said "no waist, no hips, no limb girths" until 2026-09-17 (W3). The
/// waist now has a column and a field — in the InBody sheet, where a reading is
/// TAKEN. It is deliberately absent from this screen, which is about where the
/// plan is GOING: a waist target is a number you cannot train toward directly,
/// only arrive at, and the three here are the three the plan actually steers.
/// No hips, no limb girths, anywhere. Every target on this screen comes off the
/// scale.
struct BodyTargetsView: View {
    let model: SettingsModel

    @State private var draft = Draft()
    @FocusState private var focus: Field?

    private enum Field: Hashable { case weight, bodyFat, muscle }

    private struct Draft {
        var weight: Double?
        var bodyFat: Double?
        var muscle: Double?
    }

    var body: some View {
        Form {
            Section {
                OnyxNumberRow(label: "Weight", value: $draft.weight, field: Field.weight,
                               focus: $focus, unit: "kg", range: 0...300, fractionLength: 1,
                               onCommit: commit)
                OnyxNumberRow(label: "Body fat", value: $draft.bodyFat, field: Field.bodyFat,
                               focus: $focus, unit: "%", range: 0...70, fractionLength: 1,
                               onCommit: commit)
                OnyxNumberRow(label: "Skeletal muscle", value: $draft.muscle, field: Field.muscle,
                               focus: $focus, unit: "kg", range: 0...100, fractionLength: 1,
                               onCommit: commit)
            } header: {
                OnyxSectionHeader("Destination", .body)
            } footer: {
                Text("Blank is not zero — it means no target of your own, and \(model.phase.label)'s default shows through instead.")
            }

            Section {
                LabeledContent("\(model.phase.label) default") {
                    Text(defaultLine).onyxNumeral()
                }
            } footer: {
                Text("Targets belong to a plan and a phase. Switching either replaces them with that phase's own.")
            }
        }
        .onyxFormBackground(.body)
        .navigationTitle("Body targets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { OnyxKeyboardDone { focus = nil } }
        .task { await model.observe() }
        .onAppear(perform: loadDraft)
        // The override row arrives on a SECOND stream, after the goals row, and
        // it changes again whenever the plan or phase does. Loading the draft
        // only on appear meant the fields showed the previous phase's numbers —
        // and the first commit wrote them into the new phase's row.
        .onChange(of: model.phaseGoals) { _, _ in loadDraft() }
        .onDisappear {
            // Navigating back with a field still focused: the value is already
            // parsed (the row parses as you type), so this is the commit that
            // would otherwise never happen.
            focus = nil
            commit()
        }
    }

    private var defaultLine: String {
        let preset = model.preset
        let weight = preset.targetWeightKg.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—"
        let fat = preset.targetBodyFatPct.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—"
        let muscle = preset.targetMuscleMassKg.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—"
        return "\(weight) kg · \(fat)% · \(muscle) kg"
    }

    private func loadDraft() {
        // Never while a field is being typed into: this fires on a sync pull,
        // which can land mid-keystroke and would reset the row under the user.
        guard focus == nil else { return }
        // The OVERRIDE, not the resolved value. Showing the preset in the field
        // would make "no target of my own" indistinguishable from "my target
        // happens to equal the default", and the next commit would silently
        // turn the second into the first.
        draft.weight = model.phaseGoals?.targetWeightKg
        draft.bodyFat = model.phaseGoals?.targetBodyFatPct
        draft.muscle = model.phaseGoals?.targetMuscleMassKg
    }

    private func commit() {
        model.saveBodyTargets(
            weightKg: draft.weight, bodyFatPct: draft.bodyFat, muscleMassKg: draft.muscle
        )
    }
}

#if DEBUG
#Preview("Body targets") {
    NavigationStack {
        BodyTargetsView(model: SettingsModel(
            database: try! .inMemory(deviceId: "preview"), userId: "preview"
        ))
    }
}
#endif
