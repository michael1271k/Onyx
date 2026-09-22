import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

// ─────────────────────────────────────────────────────────────────────────────
// THE DIFF BETWEEN A REPORT AND YOUR GOALS (W7, decision 23).
//
// `TargetsBlockParser` found a block in the pasted report; `targetsPlan` worked
// out what it would change. This is the step in between — a human reading the
// change before it happens.
//
// ── WHY THERE IS A SHEET AT ALL ─────────────────────────────────────────────
// Every other write in this app is something the athlete typed. This one is a
// number a model wrote, arriving through a paste, and the thing it changes is
// what every day is graded against for the rest of the block. A screen that
// applied it on a tap would be the one place in the app where the app changed
// your targets and told you afterwards.
// ─────────────────────────────────────────────────────────────────────────────

struct ApplyTargetsSheet: View {
    let plan: TargetsPlan
    /// Told that the plan was applied. It must NOT dismiss anything: this
    /// sheet's own `dismiss()` runs a line later, and dismissing a presenting
    /// sheet from inside a presented one loses one of the two.
    var onApplied: (() -> Void)?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?
    @State private var applying = false

    private var applied: [TargetsPlan.Change] { plan.changes.filter(\.applies) }
    private var reported: [TargetsPlan.Change] { plan.changes.filter { !$0.applies } }

    var body: some View {
        NavigationStack {
            List {
                if let failure {
                    OnyxBanner(tone: .failure, title: "Not applied", message: failure)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if let note = plan.note {
                    Section {
                        Text(note)
                            .onyxType(.caption)
                            .foregroundStyle(Color.onyx.textSecondary)
                    } header: {
                        Text("What the report says")
                    }
                }
                if !applied.isEmpty {
                    Section {
                        ForEach(applied) { row(for: $0) }
                    } header: {
                        Text("Changing")
                    } footer: {
                        // The one thing a reader must understand before tapping:
                        // when these come into force, and that a date the
                        // report names is not a date these will wait for.
                        Text(plan.wasBackdated
                             ? "The report is written for the week of \(Self.day(plan.weekStart)). "
                               + "These apply from today, like every rung: the past keeps what it was "
                               + "graded against, and nothing is held back waiting for a date."
                             : "In force from today.")
                            .onyxType(.caption)
                            .foregroundStyle(Color.onyx.textSecondary)
                    }
                }
                if !reported.isEmpty {
                    Section {
                        ForEach(reported) { row(for: $0) }
                    } header: {
                        Text("Not changing")
                    }
                }
                if plan.changes.isEmpty {
                    ContentUnavailableView(
                        "Nothing to change",
                        systemImage: "equal.circle",
                        description: Text("The report's targets match what you already have."))
                        .listRowBackground(Color.clear)
                }
            }
            .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            .scrollContentBackground(.hidden)
            .onyxScreen(.recover)
            .navigationTitle("Apply targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: apply)
                        .fontWeight(.semibold)
                        .disabled(plan.isEmpty || applying)
                }
            }
        }
        .tint(OnyxDomain.recover.accent)
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.onyx.base)
        .preferredColorScheme(.dark)
    }

    /// One field: what it is, what it was, what it becomes.
    ///
    /// The arrow is drawn between two values rather than the new value being
    /// shown alone, because "2,100 kcal" tells you nothing about whether that
    /// is a cut or a hold. A row that will not be written says why, in place of
    /// its old value — there is no "was" to show for a change that is not one.
    private func row(for change: TargetsPlan.Change) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: OnyxSpace.s) {
                Text(change.field)
                    .foregroundStyle(Color.onyx.textPrimary)
                Spacer(minLength: OnyxSpace.s)
                if let current = change.current {
                    Text(current)
                        .foregroundStyle(Color.onyx.textTertiary)
                        .strikethrough(change.applies, color: Color.onyx.textTertiary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(Color.onyx.textTertiary)
                        .accessibilityHidden(true)
                }
                Text(change.proposed)
                    .foregroundStyle(change.applies ? OnyxDomain.recover.accent : Color.onyx.textTertiary)
                    .fontWeight(change.applies ? .semibold : .regular)
            }
            .onyxNumeral()
            if let reason = change.reason {
                Text(reason)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
        }
        .padding(.vertical, 3)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            change.applies
            ? "\(change.field), \(change.current ?? "not set") becomes \(change.proposed)"
            : "\(change.field), \(change.proposed), not changing. \(change.reason ?? "")")
    }

    private func apply() {
        applying = true
        do {
            try environment.database.applyTargets(plan, userId: environment.userIdString)
            onApplied?()
            dismiss()
        } catch {
            failure = "Those targets could not be saved on this device."
        }
        applying = false
    }

    /// `21 Sep`.
    static func day(_ iso: String) -> String {
        LogicalDay.date(fromISO: iso)
            .map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? iso
    }
}

#if DEBUG
#Preview("Apply targets") {
    ApplyTargetsSheet(plan: TargetsPlan(
        weekStart: "2026-09-21",
        effectiveFrom: "2026-09-22",
        note: "Protein was short on three days running; calories are fine.",
        changes: [
            .init(field: "Calories", current: "2,000 kcal", proposed: "2,100 kcal"),
            .init(field: "Protein", current: "160 g", proposed: "175 g"),
            .init(field: "Steps", current: "10,000", proposed: "12,000"),
            .init(field: "Lever", current: "My own numbers", proposed: "Lever 1",
                  applies: false,
                  reason: "the numbers above replace it — typing a figure is choosing your own"),
        ],
        leverKey: nil,
        goals: .init(kcal: 2100, proteinG: 175, stepsGoal: 12000)))
}
#endif
