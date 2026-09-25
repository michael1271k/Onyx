import CryptoKit
import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// Pick a movement, or make one — the Muscle Shelf (Precision A1).
///
/// ── SEARCH THAT OFFERS TO CREATE IS STILL THE WHOLE ESCAPE HATCH ────────────
/// A picker that can only pick is a dead end the first time someone's gym has a
/// machine this catalogue has never heard of, and the answer to a dead end in a
/// routine builder is that people stop using the routine builder. So the search
/// field doubles as the new-movement field. What "new" then does is the
/// CALLER's: the routine builder creates the row through `createExercise`,
/// which refuses to make a second row for a name that already exists — a SPLIT
/// is the silent failure `ExerciseIndex` exists to prevent — and the logger
/// lets its first logged set mint it (`storedIdCreatingCatalogueRow`).
///
/// ── WHY SHELVES, AND WHY THE ATLAS'S SIXTEEN ────────────────────────────────
/// It was one alphabetical section, which at forty movements is a scroll and at
/// two hundred is a search you are forced into. The founder chose the atlas's
/// own muscles as the headings (Q1): the unit the rest of the app already
/// scores, colours and draws in, so "Rear delts" here is the same coral as the
/// Rear delts on the body sheet. A movement sits on ONE shelf — its first
/// primary mover — because a row listed three times is a list that lies about
/// its length.
///
/// ── ONE PICKER, TWO CALLERS (W3) ────────────────────────────────────────────
/// The logger hands it an `ExerciseLibrary` (the pinned shelves and every
/// row's last time); the routine builder hands it only a catalogue, and gets
/// the muscle shelves alone. What comes back is the same either way: the name,
/// and the catalogue row it picked — nil when the name is new.
struct ExercisePickerSheet: View {
    let library: ExerciseLibrary
    /// The create row's footer — what "Add" does, in the caller's own terms.
    let createNote: String
    let onPick: (_ name: String, _ picked: Exercise?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query: String
    /// The shelf the bar last jumped to — the capsule drawn selected.
    @State private var selected: MuscleShelf?

    /// Every row, filed once, built when the sheet is — never per keystroke.
    private let index: [ShelfEntry]
    private let shelves: [(shelf: MuscleShelf, entries: [ShelfEntry])]
    private let pinned: [(shelf: MuscleShelf, entries: [ShelfEntry])]

    init(
        library: ExerciseLibrary,
        createNote: String,
        query: String = "",
        onPick: @escaping (_ name: String, _ picked: Exercise?) -> Void
    ) {
        self.library = library
        self.createNote = createNote
        self.onPick = onPick
        _query = State(initialValue: query)
        let index = library.catalogue.map(ShelfEntry.init)
        self.index = index
        self.shelves = MuscleShelf.file(index)
        self.pinned = MuscleShelf.pin(library, index: index)
    }

    /// The routine builder's door: a catalogue and nothing pinned.
    init(
        catalogue: [Exercise],
        createNote: String,
        onPick: @escaping (_ name: String, _ picked: Exercise?) -> Void
    ) {
        self.init(library: ExerciseLibrary(catalogue: catalogue), createNote: createNote, onPick: onPick)
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var matches: [ShelfEntry] {
        let needle = trimmed.lowercased()
        return index.filter { $0.search.contains(needle) }
    }

    /// The typed name is not already a movement, so offer to make it one.
    private var creatable: String? {
        guard !trimmed.isEmpty else { return nil }
        let key = trimmed.lowercased()
        return library.catalogue.contains { $0.name.lowercased() == key } ? nil : trimmed
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    // A typed name nothing matches leads with the offer to
                    // make it; a muscle word that found ten movements leads
                    // with the ten, and the offer waits underneath.
                    if matches.isEmpty { createSection }
                    if trimmed.isEmpty {
                        ForEach(pinned + shelves, id: \.shelf) { group in
                            section(group.shelf, group.entries)
                        }
                    } else {
                        Section {
                            ForEach(matches) { row($0, in: nil) }
                        } header: {
                            OnyxSectionHeader(matches.count == 1 ? "1 movement" : "\(matches.count) movements", .train)
                        }
                        createSection
                    }
                    if library.catalogue.isEmpty && trimmed.isEmpty {
                        Section {
                        } footer: {
                            Text("Your exercise list is empty. Type a name above to add your first movement, or import a CSV from Settings.")
                        }
                    }
                }
                .onyxFormBackground(.train)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if trimmed.isEmpty, !shelves.isEmpty { shelfBar(proxy) }
                }
            }
            .searchable(text: $query, prompt: "Search a movement or a muscle")
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

    @ViewBuilder private var createSection: some View {
        if let creatable {
            Section {
                Button {
                    onPick(creatable, nil)
                    dismiss()
                } label: {
                    Label("Add “\(creatable)”", systemImage: "plus.circle")
                        .frame(minHeight: 44, alignment: .leading)
                }
            } footer: {
                Text(createNote)
            }
        }
    }

    // MARK: - The bar

    /// The sticky row of muscles. A capsule jumps the list to its shelf; the
    /// pinned shelves are at the top already and need no capsule.
    private func shelfBar(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OnyxSpace.s) {
                ForEach(shelves, id: \.shelf) { group in
                    capsule(group.shelf, count: group.entries.count, proxy)
                }
            }
            .padding(.horizontal, OnyxSpace.l)
        }
        // Capped: at AX5 two capsules filled the width and the bar stopped
        // being a way to see the shelves. The headings below still scale.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(Color.onyx.base)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.onyx.ink(0.08)).frame(height: 0.5) }
    }

    private func capsule(_ shelf: MuscleShelf, count: Int, _ proxy: ScrollViewProxy) -> some View {
        let on = selected == shelf
        return Button {
            selected = shelf
            withAnimation(reduceMotion ? nil : OnyxMotion.move) {
                proxy.scrollTo(shelf, anchor: .top)
            }
        } label: {
            HStack(spacing: OnyxSpace.xs) {
                Circle().fill(shelf.ink).frame(width: 6, height: 6)
                Text(shelf.title)
                    .onyxType(.caption)
                    .fontWeight(on ? .semibold : .regular)
                    .foregroundStyle(on ? OnyxDomain.train.accent : Color.onyx.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, OnyxSpace.m)
            .frame(minHeight: 32)
            .background(on ? OnyxDomain.train.accent.opacity(0.20) : Color.onyx.ink(0.08), in: .capsule)
            .overlay {
                Capsule().strokeBorder(on ? OnyxDomain.train.accent.opacity(0.6) : .clear, lineWidth: 1)
            }
            // A 32 pt capsule inside a 44 pt target: the row reads light and
            // the thumb still lands.
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(shelf.title), \(count) movements")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - Shelves and rows

    private func section(_ shelf: MuscleShelf, _ entries: [ShelfEntry]) -> some View {
        Section {
            ForEach(entries) { row($0, in: shelf) }
        } header: {
            OnyxSectionHeader(shelf.title, color: shelf.ink)
                // The bar's `scrollTo` target: a header is a view the list
                // lays out, where a `Section` is not.
                .id(shelf)
        }
    }

    private func row(_ entry: ShelfEntry, in shelf: MuscleShelf?) -> some View {
        Button {
            onPick(entry.name, entry.exercise)
            dismiss()
        } label: {
            ShelfRow(entry: entry, last: library.lastSets[entry.name])
        }
        // A movement can sit on a pinned shelf and on its muscle's: the row id
        // carries the shelf, or `ForEach` sees one id twice.
        .id("\(shelf?.id ?? "match")·\(entry.id)")
    }
}

// MARK: - What the logger hands over

/// The Muscle Shelf's inputs, gathered when it opens (`LoggerModel.library`).
struct ExerciseLibrary {
    var catalogue: [Exercise]
    /// "Recent": the last movements performed, newest first, minus the deck.
    var recent: [String] = []
    /// "On this day": today's plan minus what is already on the deck.
    var onThisDay: [String] = []
    /// Every row's last working set, keyed by the catalogue NAME.
    var lastSets: [String: LastWorkingSet] = [:]
}

// MARK: - The shelves

/// A heading the library is browsed by: one of the atlas's sixteen muscles,
/// Obliques, Cardio, Other — or one of the two pinned shelves.
enum MuscleShelf: Hashable, Identifiable {
    case recent, onThisDay
    case muscle(LandmarkMuscle)
    /// Named because the founder named it (Q1). `obliques` folds into Abs/core
    /// for CREDIT (`LandmarkMuscle.from(token:)`), but a twist and a crunch are
    /// different movements to go looking for.
    case obliques
    case cardio
    /// A movement nothing can place: no dictionary entry, no stored muscle, not
    /// a bout. Named honestly rather than guessed onto a shelf.
    case other

    /// The founder's order (plan, A1) — upper body front to back, the arms, the
    /// trunk, the legs. Adductors is the atlas's sixteenth muscle; Q1's list
    /// named Obliques in its place, and dropping it would leave the hip
    /// adduction machine on no shelf, so it sits beside the glutes.
    static let order: [MuscleShelf] = [
        .muscle(.chest), .muscle(.frontDelts), .muscle(.sideDelts), .muscle(.rearDelts),
        .muscle(.lats), .muscle(.upperBack), .muscle(.lowerBack),
        .muscle(.biceps), .muscle(.triceps), .muscle(.forearms),
        .muscle(.absCore), .obliques,
        .muscle(.quads), .muscle(.hamstrings), .muscle(.glutes), .muscle(.adductors), .muscle(.calves),
        .cardio, .other,
    ]

    var id: String {
        switch self {
        case .recent: "recent"
        case .onThisDay: "on-this-day"
        case .muscle(let m): m.rawValue
        case .obliques: "obliques"
        case .cardio: "cardio"
        case .other: "other"
        }
    }

    var title: String {
        switch self {
        case .recent: "Recent"
        case .onThisDay: "On this day"
        case .muscle(let m): m.displayName
        case .obliques: "Obliques"
        case .cardio: "Cardio"
        case .other: "Other"
        }
    }

    /// The fixed anatomical ink for a muscle (Q18), the domain's for the rest.
    var ink: Color {
        switch self {
        case .recent, .onThisDay: OnyxDomain.train.accent
        case .muscle(let m): Color.onyx.muscle(m)
        case .obliques: Color.onyx.muscle(.absCore)
        case .cardio: OnyxDomain.body.accent
        case .other: Color.onyx.textSecondary
        }
    }

    /// The one shelf a movement sits on: its FIRST primary mover.
    ///
    /// The name first, exactly as every reader resolves it; the stored
    /// `primary_muscle` only for a movement the dictionary has never seen (a
    /// CSV import that brought its own tags); then the cardio table, which
    /// answers the display question and nothing else.
    static func of(name: String, storedPrimary: String?) -> MuscleShelf {
        let first = MuscleMap.movers(name)?.primary.first ?? storedPrimary
        if let first {
            if first.lowercased() == "obliques" { return .obliques }
            if let muscle = LandmarkMuscle.from(token: first) { return .muscle(muscle) }
        }
        return MuscleMap.cardioMovers(name) != nil ? .cardio : .other
    }

    /// The catalogue on its shelves, in `order`, empty shelves dropped. Every
    /// row lands exactly once.
    static func file(_ index: [ShelfEntry]) -> [(shelf: MuscleShelf, entries: [ShelfEntry])] {
        let byShelf = Dictionary(grouping: index, by: \.shelf)
        return order.compactMap { shelf in
            guard let entries = byShelf[shelf], !entries.isEmpty else { return nil }
            return (shelf, entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    /// The two pinned shelves. A name the catalogue does not hold still gets
    /// a row on "On this day" — a plan movement nobody has logged has no
    /// catalogue row yet, and it is exactly what that shelf is for; picking it
    /// hands back nil, and the logger resolves the plan's own entry.
    static func pin(_ library: ExerciseLibrary, index: [ShelfEntry]) -> [(shelf: MuscleShelf, entries: [ShelfEntry])] {
        var byName: [String: ShelfEntry] = [:]
        for entry in index { byName[ExerciseAliases.canonicalName(entry.name).lowercased()] = entry }
        func entries(_ names: [String], keepUnknown: Bool) -> [ShelfEntry] {
            names.compactMap { name in
                byName[ExerciseAliases.canonicalName(name).lowercased()]
                    ?? (keepUnknown ? ShelfEntry(name: name) : nil)
            }
        }
        return [
            (MuscleShelf.recent, entries(library.recent, keepUnknown: false)),
            (MuscleShelf.onThisDay, entries(library.onThisDay, keepUnknown: true)),
        ].filter { !$0.1.isEmpty }
    }
}

/// One row of the shelf: the movement, resolved once.
struct ShelfEntry: Identifiable {
    let id: String
    let name: String
    /// The catalogue row, or nil for a plan movement it does not hold.
    let exercise: Exercise?
    let shelf: MuscleShelf
    let primary: [LandmarkMuscle]
    let secondary: [LandmarkMuscle]
    let isCardio: Bool
    /// Name and muscle words, lowercased — what search matches against.
    let search: String

    init(_ exercise: Exercise) {
        self.init(name: exercise.name, exercise: exercise)
    }

    init(name: String, exercise: Exercise? = nil) {
        id = exercise?.id ?? "plan·\(name)"
        self.name = name
        self.exercise = exercise
        let stored = [exercise?.primaryMuscle].compactMap { $0 }
        let movers = MuscleMap.movers(name)
            ?? MuscleMap.cardioMovers(name)
            ?? MuscleMap.resolveMovers(name, stored: stored)
        shelf = MuscleShelf.of(name: name, storedPrimary: exercise?.primaryMuscle)
        isCardio = shelf == .cardio
        let primary = MuscleMap.landmarks(movers.primary)
        self.primary = primary
        secondary = MuscleMap.landmarks(movers.secondary).filter { !primary.contains($0) }
        search = ([name, shelf.title] + movers.primary + movers.secondary + (primary + self.secondary).map(\.displayName))
            .joined(separator: " ")
            .lowercased()
    }
}

/// Mini atlas · name · muscle chips · last time.
private struct ShelfRow: View {
    let entry: ShelfEntry
    let last: LastWorkingSet?

    /// Which face of the figure shows a muscle — the back muscles have no
    /// front path, and a figure lit on the wrong side is a figure lit nowhere.
    private static let frontMuscles = Set(OnyxAtlas.muscles.filter { $0.view == .front }.map(\.muscle))

    var body: some View {
        HStack(alignment: .top, spacing: OnyxSpace.m) {
            figure
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                Text(entry.name)
                    .onyxType(.body)
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !entry.primary.isEmpty {
                    FlowRow(spacing: OnyxSpace.xs) {
                        ForEach(entry.primary, id: \.self) { chip($0, primary: true) }
                        ForEach(entry.secondary, id: \.self) { chip($0, primary: false) }
                    }
                    // The shelf heading already names the muscle at full
                    // size; the chips repeat it, so they stop at AX1 rather
                    // than turning one row into a screen.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
                if let line = lastLine {
                    Text(line)
                        .onyxType(.secondary)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, OnyxSpace.xs)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var figure: some View {
        let lit = entry.primary.first
        let onBack = lit.map { !Self.frontMuscles.contains($0.rawValue) } ?? false
        return AtlasFigure(side: onBack ? .back : .front, worked: lit.map { [$0: 1] } ?? [:], isThumbnail: true)
            .frame(width: 28, height: 52)
            .accessibilityHidden(true)
    }

    /// `47kg × 12 · 12 Sep`, "New" for a lift never logged, and nothing for a
    /// bout — a treadmill's history is a duration, which a set line cannot say.
    private var lastLine: String? {
        guard !entry.isCardio else { return nil }
        guard let last else { return "New" }
        let set = SetFormat.format(weightKg: last.weightKg, reps: Double(last.reps))
        guard let date = LogicalDay.date(fromISO: last.date) else { return set }
        return "\(set) · \(date.formatted(.dateTime.day().month(.abbreviated)))"
    }

    /// A primary mover is a filled capsule, an assisting one an outline — the
    /// same distinction the credit makes (a whole set against half of one).
    private func chip(_ muscle: LandmarkMuscle, primary: Bool) -> some View {
        let tint = Color.onyx.muscle(muscle)
        return Text(muscle.displayName)
            .onyxType(.micro)
            .foregroundStyle(tint)
            .padding(.horizontal, OnyxSpace.s)
            .padding(.vertical, 2)
            .background(primary ? tint.opacity(0.16) : .clear, in: .capsule)
            .overlay { Capsule().strokeBorder(tint.opacity(primary ? 0 : 0.45), lineWidth: 1) }
    }
}

// MARK: - The fifteen every account starts with

/// The movements the catalogue shipped without (Q4, plan A1), created on this
/// device the first time the library opens, so an account that never pastes
/// `docs/sql/precision-a-exercises.sql` still has them.
///
/// ── THE ID IS THE SQL'S ID ──────────────────────────────────────────────────
/// `md5(user_id || ':' || name)` read as a uuid, here and in the SQL. Whichever
/// runs first, the other lands on the SAME row — the push upserts on `id` and
/// the SQL does `on conflict do nothing` — so the pair cannot leave two rows
/// for one movement, whatever unique constraints the live table does or does
/// not carry. The user is in the hash, so two accounts never share an id.
enum StarterMovements {
    static let all: [(name: String, equipment: String?)] = [
        ("Squat (Barbell)", "Barbell"),
        ("Deadlift (Barbell)", "Barbell"),
        ("Pull Up", nil),
        ("Chin Up", nil),
        ("Bent Over Row (Barbell)", "Barbell"),
        ("Dumbbell Row", "DB"),
        ("Dips", nil),
        ("Bulgarian Split Squat", "DB"),
        ("Walking Lunge", "DB"),
        ("Reverse Fly", "DB"),
        ("Push Up", nil),
        ("Shrug (Dumbbell)", "DB"),
        ("Front Squat", "Barbell"),
        ("Skull Crusher", "Barbell"),
        ("Arnold Press", "DB"),
    ]

    /// `md5(lower(user) || ':' || name)::uuid`, Postgres's spelling.
    static func id(userId: String, name: String) -> String {
        let hex = Insecure.MD5.hash(data: Data("\(userId.lowercased()):\(name)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let c = Array(hex)
        return [c[0..<8], c[8..<12], c[12..<16], c[16..<20], c[20..<32]].map { String($0) }.joined(separator: "-")
    }

    /// Create whichever of the fifteen this catalogue lacks. Idempotent: a
    /// name already held — typed by hand, pulled, or created here before — is
    /// left alone (`createExercise` answers with the existing row).
    @discardableResult
    static func ensure(in store: AppDatabase, userId: String, catalogue: [Exercise]) -> Int {
        let held = Set(catalogue.map { $0.name.lowercased() })
        var created = 0
        for movement in all where !held.contains(movement.name.lowercased()) {
            if (try? store.createExercise(
                userId: userId, name: movement.name, equipment: movement.equipment,
                id: id(userId: userId, name: movement.name)
            )) != nil { created += 1 }
        }
        return created
    }
}
