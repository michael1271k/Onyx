import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// Pick a movement, or make one.
///
/// ── SEARCH THAT OFFERS TO CREATE IS THE WHOLE SCREEN ────────────────────────
/// A picker that can only pick is a dead end the first time someone's gym has a
/// machine this catalogue has never heard of, and the answer to a dead end in a
/// routine builder is that people stop using the routine builder. So the search
/// field doubles as the new-movement field. What "new" then does is the
/// CALLER's: the routine builder creates the row through `createExercise`,
/// which refuses to make a second row for a name that already exists — a SPLIT
/// is the silent failure `ExerciseIndex` exists to prevent — and the logger
/// lets its first logged set mint it (`storedIdCreatingCatalogueRow`).
///
/// ── ONE PICKER, TWO CALLERS (W3) ────────────────────────────────────────────
/// It was a `private` view inside `RoutineDayEditor`, parameterised on the
/// routine model and a day key. The logger's mid-session add needs exactly the
/// same list, search and create row, so it is parameterised on what it hands
/// back instead: the name, and the catalogue row it picked — nil when the name
/// is new.
struct ExercisePickerSheet: View {
    let catalogue: [Exercise]
    /// The create row's footer — what "Add" does, in the caller's own terms.
    let createNote: String
    let onPick: (_ name: String, _ picked: Exercise?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [Exercise] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return catalogue }
        return catalogue.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    /// The typed name is not already a movement, so offer to make it one.
    private var creatable: String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let key = trimmed.lowercased()
        return catalogue.contains { $0.name.lowercased() == key } ? nil : trimmed
    }

    var body: some View {
        NavigationStack {
            List {
                if let creatable {
                    Section {
                        Button {
                            onPick(creatable, nil)
                            dismiss()
                        } label: {
                            Label("Add “\(creatable)”", systemImage: "plus.circle")
                        }
                    } footer: {
                        Text(createNote)
                    }
                }
                Section {
                    ForEach(matches, id: \.id) { exercise in
                        Button {
                            onPick(exercise.name, exercise)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .foregroundStyle(Color.onyx.textPrimary)
                                // What it trains, resolved the way every reader
                                // resolves it — so the picker and the muscle
                                // sheet cannot disagree. Named by the landmark,
                                // as the deck's chip names it: the raw token
                                // capitalised read "Rear_Delts".
                                if let muscles = MuscleMap.muscleGroups(exercise.name),
                                   let first = muscles.first {
                                    Text(LandmarkMuscle.from(token: first)?.displayName ?? first.capitalized)
                                        .onyxType(.caption)
                                        .foregroundStyle(Color.onyx.textSecondary)
                                }
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                    }
                } header: {
                    OnyxSectionHeader(catalogue.isEmpty ? "Your exercises" : "\(matches.count) movements", .train)
                } footer: {
                    if catalogue.isEmpty {
                        Text("Your exercise list is empty. Type a name above to add your first movement, or import a CSV from Settings.")
                    }
                }
            }
            .onyxFormBackground(.train)
            .searchable(text: $query, prompt: "Search or type a new movement")
            .navigationTitle("Add a movement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(OnyxDomain.train.accent)
        .presentationBackground(Color.onyx.base)
        .preferredColorScheme(.dark)
    }
}
