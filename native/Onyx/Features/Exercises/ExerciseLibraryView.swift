import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// Every lift you have actually trained, grouped by what it trains.
///
/// ── A SUB-SCREEN OF TRAINING, NOT A SIXTH TAB ───────────────────────────────
/// A library is somewhere you go FROM the training screen, not a peer of it.
/// The web app made the same call and wrote down the argument against a sixth
/// nav item; five tabs is also the point at which iOS stops giving you a tab and
/// starts giving you a "More" list.
///
/// ── THE SEARCH IS LOCAL, AND THAT IS NOT A SHORTCUT ─────────────────────────
/// The list is already in memory — thirty rows, read once from GRDB and kept
/// live by an observation. A query per keystroke would be slower than not having
/// a search at all, and would be the only screen in the app that can fail to
/// filter because the network did.
///
/// ── WHY EVERY ROW CARRIES A SPARKLINE ───────────────────────────────────────
/// `48 sets · last 1 Sep` says how much and how recently, and neither says the
/// thing you open a library for: is this movement going anywhere. A 40×16 trail
/// of session-best estimated 1RM answers that in the width of a word, and the
/// whole ledger is one read — the same read the session page makes — so it costs
/// a grouping pass rather than thirty queries.
struct ExerciseLibraryView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Supplied by the screenshot harness; the app reads its own store.
    var seeded: [ExerciseCatalogEntry]?

    @State private var entries: [ExerciseCatalogEntry] = []
    /// Exercise id → session-best estimated 1RM, oldest first.
    @State private var sparks: [String: [Double]] = [:]
    @State private var query = ""

    var body: some View {
        List {
            ForEach(groups, id: \.group) { section in
                Section {
                    ForEach(section.entries) { entry in
                        NavigationLink {
                            ExerciseDetailView(entry: entry, siblings: flat)
                        } label: {
                            row(entry, in: section.group)
                        }
                    }
                } header: {
                    OnyxSectionHeader(section.group.rawValue, section.group.domain)
                }
            }
        }
        .listRowBackground(Rectangle().fill(.ultraThinMaterial))
        .scrollContentBackground(.hidden)
        .onyxScreen(.train)
        .tint(OnyxDomain.train.accent)
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
        // Stock `.searchable`: the system owns the field, its placement under
        // the title, the cancel button, the keyboard, Scribble, dictation and
        // the VoiceOver rotor entry. The web app hand-built all of that from a
        // bordered `<label>` and an `<input>`.
        .searchable(text: $query, prompt: "Search exercises")
        .autocorrectionDisabled()
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Nothing logged yet",
                    systemImage: "dumbbell",
                    description: Text("Log a session and every lift in it shows up here.")
                )
            } else if groups.isEmpty {
                // The system's own no-results view, which VoiceOver announces
                // and which matches every other search on the device.
                ContentUnavailableView.search(text: query)
            }
        }
        .task {
            let database = environment.database
            // The trails first, so a row never appears without its sparkline
            // and then grows one under the reader's finger.
            sparks = await Task.detached(priority: .userInitiated) {
                let ledger = (try? database.historySets(userId: database.localUserId())) ?? []
                return Dictionary(grouping: ledger, by: \.exerciseId)
                    .mapValues { SessionAnalysis.sparkline($0) }
            }.value
            if let seeded {
                entries = seeded
                return
            }
            do {
                for try await rows in database.exerciseCatalogStream() {
                    entries = rows
                }
            } catch {
                // An empty library is a bad screen; a crashed one is worse.
                entries = []
            }
        }
    }

    // MARK: - Rows

    private func row(_ entry: ExerciseCatalogEntry, in group: MuscleGroup) -> some View {
        HStack(spacing: OnyxSpace.grid) {
            // The rule carries the group's colour, so a scan down the list reads
            // as bands rather than as thirty identical rows.
            Capsule()
                .fill(group.domain.accent)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .onyxType(.body)
                    .foregroundStyle(Color.onyx.textPrimary)
                Text(subtitle(entry))
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
            }
            Spacer(minLength: OnyxSpace.s)
            // Nothing at all rather than `Sparkline`'s own "not enough
            // readings" caption, which is written for a widget face with room
            // for a sentence. Here the absence IS the message: one session so
            // far, and a trail starts at two.
            if let trail = sparks[entry.id], trail.count >= 2 {
                Sparkline(points: trail, color: group.domain.accent)
                    .frame(width: 32, height: 12)
                    .accessibilityHidden(true)
            }
        }
        // §W7: the card loses 15 % of its height. 40 pt of CONTENT, not of tap
        // target — the list's own row insets carry it back over 44, which is
        // what a finger needs and what a row of text does not.
        .frame(minHeight: 40)
        // One element, one announcement. Without this VoiceOver reads the name
        // and the subtitle as two separate stops inside a row that is one link.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name), \(subtitle(entry))")
    }

    private func subtitle(_ entry: ExerciseCatalogEntry) -> String {
        let sets = entry.setCount == 1 ? "1 set" : "\(entry.setCount) sets"
        guard let last = entry.lastTrained else { return sets }
        return "\(sets) · last \(Self.shortDate(last))"
    }

    private static func shortDate(_ iso: String) -> String {
        guard let date = LogicalDay.date(fromISO: iso) else { return iso }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    // MARK: - Grouping

    private var filtered: [ExerciseCatalogEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return entries }
        // Matched on the canonical name as well as the stored one, so searching
        // for the name you know finds the row that was renamed under you.
        return entries.filter {
            $0.name.lowercased().contains(needle)
                || ExerciseAliases.canonicalName($0.name).lowercased().contains(needle)
        }
    }

    /// Groups in a fixed order, each alphabetical, empty ones omitted.
    ///
    /// The ORDER is fixed rather than by size: a list whose headings move as you
    /// train is a list you cannot learn the shape of.
    private var groups: [(group: MuscleGroup, entries: [ExerciseCatalogEntry])] {
        let byGroup = Dictionary(grouping: filtered) { MuscleGroup.forExercise($0.name) }
        return MuscleGroup.allCases.compactMap { group in
            guard let rows = byGroup[group], !rows.isEmpty else { return nil }
            return (group, rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    /// The list as the detail page's chevrons walk it: exactly the order on
    /// screen, so "next" means the row under your finger and not the next id.
    private var flat: [ExerciseCatalogEntry] { groups.flatMap(\.entries) }
}

#if DEBUG
#Preview("Library") {
    NavigationStack {
        ExerciseLibraryView(seeded: PreviewHarness.sampleExercises)
    }
    .environment(AppEnvironment.preview)
}
#endif
