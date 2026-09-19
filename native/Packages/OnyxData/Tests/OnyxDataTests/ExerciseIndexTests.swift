import Foundation
import Testing
import OnyxCore
@testable import OnyxData

/// The slug, and the catalogue lookup it feeds.
///
/// ── THE CATALOGUE BELOW IS REAL ─────────────────────────────────────────────
/// These are the actual `exercises.name` strings from the live database
/// (2026-09-03, 60 rows). The near-duplicates are not test noise: `Seated Cable
/// Row` / `(V-Grip)` / `(Wide Grip)` are three deliberately separate rows,
/// carved apart on 2026-08-06 because sharing one cost a real record, and
/// `Crunch (Machine)` / `Crunch Machine` are two rows on two different splits.
/// A resolver that collapses either pair re-creates a bug this project has
/// already paid for once.
@Suite("Exercise identity")
struct ExerciseIndexTests {

    /// The live catalogue, verbatim — 46 rows as of 2026-09-07.
    ///
    /// It was 60 until the hotfix-polish sprint merged fifteen duplicate rows
    /// and moved the equipment out of thirteen titles into `exercises.equipment`
    /// (hotfix-polish.sql (git history)). Every `(Machine)` / `(DB)` / `(Cable)` twin
    /// in the old list was a SECOND PR baseline for one movement, which is the
    /// failure `aliases.ts` documents at length. `Treadmill` is the one addition.
    private static let liveNames = [
        "Behind-Back Wrist Curl", "Bicep Curl", "Bicycle Crunch",
        "Calf Press", "Calf Raise", "Chest Press",
        "Cross-Body Cable Extension", "Crunch Machine", "Face Pull",
        "Hack Squat", "Hammer Curl", "Hanging Knee Raise", "Hip Adduction",
        "Hip Thrust", "Hollow Hold", "Hollow Rock", "Incline DB Press",
        "Lat Pulldown", "Lateral Raise", "Leg Extension", "Leg Press",
        "Lying Leg Raise", "Neutral-Grip Lat Pulldown",
        "Overhead Triceps Extension", "Pec Deck", "Preacher Curl",
        "Reverse Crunch", "Reverse EZ-Bar Curl", "Romanian Deadlift",
        "Rope Triceps Pushdown", "Russian Twist", "Seated Cable Row",
        "Seated Cable Row (V-Grip)", "Seated Cable Row (Wide Grip)",
        "Seated DB Wrist Curl", "Seated Incline DB Curl",
        "Seated Lateral Raise", "Seated Leg Curl", "Shoulder Press",
        "Side Plank", "Single Arm Cable Crossover",
        "Single Arm Lateral Raise", "Single Arm Triceps Pushdown",
        "Single-Arm Cable Fly", "Straight-Arm Pulldown", "Treadmill",
    ]

    private static let liveCatalogue = liveNames.enumerated().map {
        RemoteExercise(id: "uuid-\($0.offset)", name: $0.element)
    }

    private func index() -> ExerciseIndex { ExerciseIndex(Self.liveCatalogue) }

    // MARK: The slug

    @Test("no two ONYX-5 movements share a slug")
    func slugsAreUnique() {
        // If two ever did, one would resolve to the other's catalogue row and
        // two movements' histories would merge — with the PR baselines.
        var seen: [String: String] = [:]
        for exercise in SampleDeck.onyx5.days.flatMap(\.exercises) {
            let slug = ExerciseSlug.id(exercise.name)
            if let clash = seen[slug], clash != exercise.name {
                Issue.record("\(exercise.name) and \(clash) both slug to \(slug)")
            }
            seen[slug] = exercise.name
        }
        #expect(seen[ExerciseSlug.id(WarmupCardio.name)] == nil,
                "the treadmill must not collide with a program movement's slug")
    }

    @Test("the treadmill resolves by slug — through the catalogue's slug column")
    func treadmillResolves() throws {
        // The reverse map is DATA since W2: `exercises.slug` names the legacy
        // id a row answers for, and both the name and the push resolve
        // through it.
        #expect(ExerciseSlug.id(WarmupCardio.name) == "onyx-treadmill")
        let rows = [Exercise(id: "uuid-treadmill", name: "Treadmill", slug: "onyx-treadmill")]
        #expect(ExerciseSlug.nameBySlug(rows)["onyx-treadmill"] == "Treadmill")
        let catalogue = [RemoteExercise(id: "uuid-treadmill", name: "Treadmill", slug: "onyx-treadmill")]
        #expect(try ExerciseIndex(catalogue).id(forSlug: "onyx-treadmill") == "uuid-treadmill")
        // A set that already carries the uuid passes straight through (D3).
        #expect(try ExerciseIndex(catalogue).id(forSlug: "uuid-treadmill") == "uuid-treadmill")
    }

    @Test("the slug is byte-identical to LoggerModel's copy")
    func slugIsPinned() {
        // There are two implementations of this function — the other is
        // `LoggerModel.exerciseId` in the app target, which this package cannot
        // import. These pinned strings are what makes a drift in EITHER copy
        // fail a test instead of quietly failing to resolve at drain time.
        #expect(ExerciseSlug.id("Incline DB Press") == "onyx-incline-db-press")
        #expect(ExerciseSlug.id("Seated Cable Row (V-Grip)") == "onyx-seated-cable-row-v-grip")
        #expect(ExerciseSlug.id("Seated Cable Row (Wide Grip)") == "onyx-seated-cable-row-wide-grip")
        #expect(ExerciseSlug.id("Straight-Arm Pulldown") == "onyx-straight-arm-pulldown")
        #expect(ExerciseSlug.id("Romanian Deadlift (Dumbbell)") == "onyx-romanian-deadlift-dumbbell")
        #expect(ExerciseSlug.id("Reverse EZ-Bar Curl") == "onyx-reverse-ez-bar-curl")
    }

    @Test("every slug maps back to the name the program spells, off the column")
    func slugRoundTrips() {
        let rows = SampleDeck.onyx5.days.flatMap(\.exercises).map {
            Exercise(id: "id-\($0.name)", name: $0.name, slug: ExerciseSlug.id($0.name))
        }
        let bySlug = ExerciseSlug.nameBySlug(rows)
        for exercise in SampleDeck.onyx5.days.flatMap(\.exercises) {
            #expect(bySlug[ExerciseSlug.id(exercise.name)] == exercise.name)
        }
    }

    // MARK: Resolution

    @Test("every movement in the program resolves to a catalogue row by name")
    func wholeProgramResolves() throws {
        // The real coverage check: if this fails, the routine payload cannot
        // name its catalogue rows and the seed's `exerciseId`s would be nil.
        for exercise in SampleDeck.onyx5.days.flatMap(\.exercises) {
            let id = try index().id(forName: exercise.name)
            #expect(!id.isEmpty, "\(exercise.name) did not resolve")
        }
    }

    @Test("an exact name wins, so a grip variant never folds into its parent")
    func exactNameWins() throws {
        // Three separate rows, three separate ladders. The V-grip is programmed
        // on Upper A and the wide bar on Upper B; sharing one row is what made
        // 2026-08-06's 42.5 × 11 lose both axes to a Sunday set.
        let vGrip = try index().id(forSlug: "onyx-seated-cable-row-v-grip")
        let wide = try index().id(forSlug: "onyx-seated-cable-row-wide-grip")
        #expect(vGrip != wide)
        #expect(vGrip == Self.liveCatalogue.first { $0.name == "Seated Cable Row (V-Grip)" }?.id)
        #expect(wide == Self.liveCatalogue.first { $0.name == "Seated Cable Row (Wide Grip)" }?.id)
    }

    @Test("an unambiguous normalised match resolves the one name that differs")
    func normalisedFallbackResolvesRDL() throws {
        // ── THE LIVE MISMATCH THIS GUARDED IS GONE, AND THE TIER IS NOT ──────
        // It used to read: the program says `Romanian Deadlift (Dumbbell)`, the
        // catalogue says `Romanian Deadlift (DB)`, and stripping the
        // parenthesised text is what keeps both apps writing to one row. The
        // 2026-09-07 rename made both sides say `Romanian Deadlift`, so that
        // pair now matches EXACTLY and never reaches this tier.
        //
        // The tier still has to work — the next name typed with a suffix the
        // catalogue spells differently depends on it — so the case is made
        // explicit here instead of borrowed from a live mismatch that a rename
        // can quietly remove. That removal is exactly what happened, and it
        // took the ambiguity test below with it.
        let catalogue = [RemoteExercise(id: "uuid-db", name: "Romanian Deadlift (DB)")]
        #expect(try ExerciseIndex(catalogue).id(forSlug: "onyx-romanian-deadlift") == "uuid-db")
    }

    @Test("an ambiguous normalised match throws instead of picking one")
    func ambiguityThrows() throws {
        // Give the normalised tier two equally good answers and it must refuse:
        // the web app takes whichever row Postgres happened to return first,
        // which is a coin flip, and a coin flip here splits a movement's
        // history in half.
        //
        // The catalogue is synthetic on purpose. This used to lean on
        // `Romanian Deadlift (Dumbbell)` being "the one program name with no
        // exact row" — a property the 2026-09-07 rename removed, which turned
        // the assertion into an `unknownExercise` about a slug that no longer
        // exists rather than the ambiguity it means to describe.
        let catalogue = [
            RemoteExercise(id: "uuid-db", name: "Romanian Deadlift (DB)"),
            RemoteExercise(id: "uuid-bb", name: "Romanian Deadlift (Barbell)"),
        ]
        #expect(throws: SyncError.ambiguousExercise(
            name: "Romanian Deadlift",
            candidates: ["Romanian Deadlift (Barbell)", "Romanian Deadlift (DB)"]
        )) {
            _ = try ExerciseIndex(catalogue).id(forSlug: "onyx-romanian-deadlift")
        }

        // With only one of them present it resolves, which is the live case.
        #expect(try ExerciseIndex([catalogue[0]])
                .id(forSlug: "onyx-romanian-deadlift") == "uuid-db")
    }

    @Test("a slug the program does not know throws and names itself")
    func unknownSlugThrows() {
        // The error names the movement a person can read, off the slug.
        #expect(throws: SyncError.unknownExercise(slug: "onyx-zercher-squat", name: "Zercher Squat")) {
            _ = try index().id(forSlug: "onyx-zercher-squat")
        }
    }

    @Test("a movement missing from the catalogue throws rather than creating a row")
    func missingCatalogueRowThrows() throws {
        // The deliberate difference from `resolveExercises.ts`, which creates.
        // Creating is right for a paste importer taking names from a foreign
        // vocabulary; here every possible name already has a row, so a miss
        // means drift — and a 61st row would split a history silently.
        let thin = ExerciseIndex([RemoteExercise(id: "uuid-0", name: "Hack Squat")])
        #expect(throws: SyncError.self) {
            _ = try thin.id(forSlug: "onyx-pec-deck")
        }
        #expect(try thin.id(forSlug: "onyx-hack-squat") == "uuid-0")
    }
}
