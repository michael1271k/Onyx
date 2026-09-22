import SwiftUI
import UniformTypeIdentifiers
import OnyxCore
import OnyxData
import OnyxUI

/// Bring a movement list in from somewhere else.
///
/// ── IT PREVIEWS BEFORE IT WRITES, AND THAT IS THE POINT ─────────────────────
/// The expensive mistake an importer can make is a SPLIT: the same movement
/// landing under a second name, its history starting again from zero, its PR
/// baselines with it, and the first return to an old load reading as a new
/// record. `ExerciseIndex`'s header is the long version. No heuristic prevents
/// that — only a person looking at the list before it lands — so this screen is
/// mostly the list, and the write is one button under it.
///
/// ── AND IT SAYS WHAT IT COULD NOT CLASSIFY ──────────────────────────────────
/// Set credit is resolved from a movement's NAME through `MuscleMap`, a
/// hand-tuned table of the movements this app already knew. An imported
/// `Zercher Squat` is not in it, so unless the file said what it trains, that
/// movement earns ZERO muscle credit for the life of the account — silently.
/// The row says so, and the file's own muscle column is the fix.
struct ExerciseImportView: View {
    let database: AppDatabase
    let userId: String
    /// A paste to read on appear. The shot harness's only door into the PREVIEW
    /// state — the half of this screen that decides whether an import is safe,
    /// and the half that cannot be reached without typing into a `TextEditor`.
    var seededPaste: String?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var parsed: ExerciseImport?
    @State private var picking = false
    @State private var written: Int?
    @State private var failure: String?
    /// The catalogue's names, read once — see `loadExistingNames`.
    @State private var existingNames: [String] = []
    /// Whether that read has landed.
    ///
    /// The dedupe is the whole safety of this screen: parsed against an EMPTY
    /// list nothing looks like an existing movement, and a re-import of a list
    /// already in the catalogue adds a second row for every line. The controls
    /// that can reach `parse` are disabled until the names are in.
    @State private var namesLoaded = false

    var body: some View {
        List {
            if let written {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(written) \(written == 1 ? "movement" : "movements") added")
                                .onyxType(.body).fontWeight(.semibold)
                                .foregroundStyle(Color.onyx.textPrimary)
                            // Where they went, because the Exercises library
                            // hides a movement until a set has been logged
                            // against it and "I imported sixty and see nothing"
                            // is otherwise the next thing that happens.
                            Text("They're in the movement picker when you build a routine. The Exercises library shows them once you've trained them.")
                                .onyxType(.caption)
                                .foregroundStyle(Color.onyx.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.onyx.good)
                    }
                }
            }

            if let failure {
                Section { Text(failure).onyxType(.caption).foregroundStyle(Color.onyx.danger) }
            }

            if parsed == nil {
                sourceSection
            } else {
                previewSection
            }
        }
        .onyxFormBackground(.train)
        .navigationTitle("Import exercises")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $picking,
            // `.commaSeparatedText` alone rejects the `.txt` a lot of exports
            // arrive as, and plain text is what this parser actually consumes.
            allowedContentTypes: [.commaSeparatedText, .plainText, .tabSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            load(result)
        }
        .task {
            await loadExistingNames()
            guard let seededPaste, parsed == nil else { return }
            text = seededPaste
            parse(seededPaste)
        }
    }

    // MARK: - Source

    @ViewBuilder
    private var sourceSection: some View {
        Section {
            Button {
                picking = true
            } label: {
                Label("Choose a file", systemImage: "doc.badge.plus")
            }
            .disabled(!namesLoaded)
        } header: {
            OnyxSectionHeader("From a file", .train)
        } footer: {
            Text("A CSV from Hevy, Strong or a spreadsheet. Onyx reads a name column, and a muscle column if there is one.")
        }

        Section {
            TextEditor(text: $text)
                .frame(minHeight: 160)
                .onyxNumeral()
                .foregroundStyle(Color.onyx.textPrimary)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    // `TextEditor` has no placeholder and the empty state of a
                    // paste target is most of how a person works out what to
                    // paste into it.
                    if text.isEmpty {
                        Text("name,primary muscle\nZercher Squat,Quads\nMeadows Row,Lats")
                            .onyxType(.caption)
                            .foregroundStyle(Color.onyx.textSecondary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            OnyxSectionHeader("Or paste it", .train)
        }

        Section {
            Button("Read it") { parse(text) }
                // Also on the catalogue read — see `namesLoaded`. A parse
                // against an empty dedupe list re-adds every movement.
                .disabled(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !namesLoaded
                )
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        if let parsed {
            Section {
                summary("Will be added", "\(parsed.importable.count)", "plus.circle")
                if parsed.duplicates > 0 {
                    summary("Already in your list", "\(parsed.duplicates)", "equal.circle")
                }
                if parsed.unclassified > 0 {
                    summary("No muscle recorded", "\(parsed.unclassified)", "questionmark.circle")
                }
                if !parsed.skipped.isEmpty {
                    summary("Lines skipped", "\(parsed.skipped.count)", "minus.circle")
                }
            } header: {
                OnyxSectionHeader("What Onyx read", .train)
            } footer: {
                if parsed.wasTruncated {
                    Text("That file has more than \(ExerciseCSV.maxRows) rows and only the first \(ExerciseCSV.maxRows) were read. If it is a workout history rather than a movement list, start over.")
                } else if parsed.unclassified > 0 {
                    Text("A movement with no muscle recorded still logs, but it won't count towards your weekly sets for any muscle. Add a muscle column to the file to fix that.")
                } else if parsed.duplicates > 0 {
                    Text("Movements already in your list are left exactly as they are — never merged, never duplicated.")
                }
            }

            Section {
                ForEach(parsed.rows, id: \.line) { row in
                    previewRow(row)
                }
            } header: {
                OnyxSectionHeader("\(parsed.rows.count) movements", .train)
            }

            Section {
                Button("Add \(parsed.importable.count) to my exercises") { commit(parsed) }
                    .disabled(parsed.importable.isEmpty)
                Button("Start over", role: .destructive) {
                    self.parsed = nil
                    written = nil
                    failure = nil
                }
            }
        }
    }

    private func previewRow(_ row: ExerciseImportRow) -> some View {
        HStack(spacing: OnyxSpace.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .foregroundStyle(row.isDuplicate ? Color.onyx.textSecondary : Color.onyx.textPrimary)
                Text(detail(row))
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textSecondary)
            }
            Spacer(minLength: 0)
            if row.isDuplicate {
                Image(systemName: "equal.circle").foregroundStyle(Color.onyx.textSecondary)
            } else if row.isUnclassified {
                Image(systemName: "questionmark.circle").foregroundStyle(Color.onyx.record)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            row.isDuplicate ? "Already in your list"
                : row.isUnclassified ? "No muscle recorded" : ""
        )
    }

    private func detail(_ row: ExerciseImportRow) -> String {
        if row.isDuplicate { return "Already in your list — left as it is" }
        var parts: [String] = []
        if let primary = row.primaryMuscle { parts.append(primary.capitalized) }
        parts.append(contentsOf: row.secondaryMuscles.map { $0.capitalized })
        if parts.isEmpty {
            return row.isUnclassified
                ? "No muscle recorded — won't count towards weekly sets"
                : "Muscles from the name"
        }
        return parts.joined(separator: " · ")
    }

    private func summary(_ label: String, _ value: String, _ symbol: String) -> some View {
        LabeledContent {
            Text(value).onyxNumeral().foregroundStyle(Color.onyx.textPrimary)
        } label: {
            Label(label, systemImage: symbol)
        }
    }

    // MARK: - Actions

    /// Read ONCE, in `.task`, off the main actor — `parse` runs on every
    /// change of a text field and used to read the whole catalogue each time
    /// (W6). A movement added in another tab while this sheet is open is not
    /// in the list, which is the same staleness the sheet already had between
    /// two keystrokes.
    private func loadExistingNames() async {
        let database = database
        existingNames = await Task.detached(priority: .userInitiated) {
            (try? database.exercises().map(\.name)) ?? []
        }.value
        namesLoaded = true
    }

    private func parse(_ raw: String) {
        failure = nil
        written = nil
        let out = ExerciseCSV.parse(raw, existingNames: existingNames)
        guard !out.isEmpty else {
            failure = "Nothing in that looked like a list of movements. Onyx needs one movement per line, with an optional muscle column."
            return
        }
        parsed = out
    }

    private func load(_ result: Result<[URL], any Error>) {
        do {
            guard let url = try result.get().first else { return }
            // A file from the Files app arrives security-scoped; reading it
            // without asking first returns a permission error that looks
            // exactly like a missing file.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            // A spreadsheet export is very often UTF-16 or Latin-1; a strict
            // UTF-8 decode of one returns nil and reads as an empty file.
            let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(decoding: data, as: UTF8.self)
            text = raw
            parse(raw)
        } catch {
            failure = "Could not read that file. \(error.localizedDescription)"
        }
    }

    private func commit(_ out: ExerciseImport) {
        do {
            let drafts = out.importable.map {
                ExerciseDraft(
                    name: $0.name, primaryMuscle: $0.primaryMuscle,
                    secondaryMuscles: $0.secondaryMuscles, equipment: $0.equipment
                )
            }
            let ids = try database.createExercises(userId: userId, drafts)
            written = ids.compactMap { $0 }.count
            parsed = nil
            text = ""
            failure = nil
        } catch {
            failure = "Could not add those movements. \(error.localizedDescription)"
        }
    }
}
