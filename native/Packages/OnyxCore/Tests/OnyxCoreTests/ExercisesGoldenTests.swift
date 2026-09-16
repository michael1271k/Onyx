import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// The three name-keyed exercise modules: the muscle map, the bodyweight flags
// and the L/R split — replayed from `npm run golden`.
//
// ── WHY THE DICTIONARY CROSSES WHOLE ─────────────────────────────────────────
// Everything else in this suite samples a formula over a grid. `MuscleMap`
// cannot be sampled: it IS a table, each line was bought separately by
// reconciling a real training week against Hevy's own per-muscle breakdown, and
// a line that drifts renders as a set count that looks completely ordinary. So
// the whole table crosses the language boundary and is compared entry for
// entry, in order — order is data, because a tie on token count goes to the
// entry written first.
//
// The two predicates are regex, and regex is where ICU and JavaScript are most
// likely to disagree quietly (`$` before a trailing newline, what `\b` counts
// as a word character). The vectors carry padded, cased and near-miss names for
// exactly that reason.
// ─────────────────────────────────────────────────────────────────────────────

private struct Empty: Decodable {}

@Suite("Muscle map — the dictionary, the matcher and the stored-column fallback")
struct MuscleMapGoldenTests {

    @Test("the Swift dictionary is the TypeScript dictionary, entry for entry, in order")
    func dictionaryMatches() throws {
        let expected = try #require(
            try GoldenFixture<Empty, [MuscleMap.Entry]>.load("muscle-map-dict").cases.first
        ).expected

        // Count first: a failure that reads "50 vs 51" names the bug better
        // than a diff of two fifty-element arrays does.
        #expect(MuscleMap.dict.count == expected.count)
        for (i, e) in expected.enumerated() where i < MuscleMap.dict.count {
            #expect(MuscleMap.dict[i] == e, "entry \(i) — tokens \(e.tokens.joined(separator: "+"))")
        }
    }

    struct NameIn: Decodable { let name: String }
    struct LookupOut: Decodable {
        let movers: MoverTokens?
        let groups: [String]?
        let primaryLandmarks: [LandmarkMuscle]
        let secondaryLandmarks: [LandmarkMuscle]
    }

    @Test("lookup, the flat column and the landmark fold all match")
    func lookupMatches() throws {
        for c in try GoldenFixture<NameIn, LookupOut>.load("muscle-map-lookup").cases {
            let n = c.input.name
            // nil vs an empty entry is the distinction that matters here:
            // "this map has never seen the movement" and "this movement trains
            // nothing" are different facts and only one of them is a bug.
            #expect(MuscleMap.movers(n) == c.expected.movers, "movers — \(c.name)")
            #expect(MuscleMap.muscleGroups(n) == c.expected.groups, "muscleGroups — \(c.name)")
            #expect(MuscleMap.primaryLandmarks(n) == c.expected.primaryLandmarks, "primaryLandmarks — \(c.name)")
            #expect(MuscleMap.secondaryLandmarks(n) == c.expected.secondaryLandmarks, "secondaryLandmarks — \(c.name)")
        }
    }

    @Test("every dictionary entry is actually reachable through the matcher")
    func everyEntryIsReachable() {
        // A guard against a line that can never fire: an entry whose tokens are
        // a superset of an earlier, shorter entry's is still reachable, but one
        // that duplicates another exactly is dead weight nobody would notice.
        for entry in MuscleMap.dict {
            let name = entry.tokens.joined(separator: " ")
            #expect(MuscleMap.movers(name) != nil, "\(name) matches nothing")
        }
    }

    struct ResolveIn: Decodable { let name: String; let stored: [String]? }

    @Test("resolveMovers matches, name first and the stale column last")
    func resolveMatches() throws {
        for c in try GoldenFixture<ResolveIn, MoverTokens>.load("muscle-map-resolve").cases {
            #expect(MuscleMap.resolveMovers(c.input.name, stored: c.input.stored) == c.expected,
                    "resolveMovers — \(c.name)")
        }
    }
}

@Suite("Bodyweight and unilateral — the two name predicates the logger renders from")
struct ExercisePredicateGoldenTests {

    struct NameIn: Decodable { let name: String? }
    struct BodyweightOut: Decodable { let bodyweight: Bool; let loadable: Bool; let unloaded: Bool }

    @Test("isBodyweight, isLoadable and isUnloaded match")
    func bodyweightMatches() throws {
        for c in try GoldenFixture<NameIn, BodyweightOut>.load("bodyweight-exercise").cases {
            #expect(Bodyweight.isBodyweight(c.input.name) == c.expected.bodyweight, "isBodyweight — \(c.name)")
            #expect(Bodyweight.isLoadable(c.input.name) == c.expected.loadable, "isLoadable — \(c.name)")
            #expect(Bodyweight.isUnloaded(c.input.name) == c.expected.unloaded, "isUnloaded — \(c.name)")
        }
    }

    @Test("loadable is a strict subset of bodyweight, and never a timed hold")
    func loadableIsASubset() throws {
        for c in try GoldenFixture<NameIn, BodyweightOut>.load("bodyweight-exercise").cases {
            guard Bodyweight.isLoadable(c.input.name) else { continue }
            #expect(Bodyweight.isBodyweight(c.input.name), "loadable but not bodyweight — \(c.name)")
            // `reps` carries SECONDS on a timed hold and session tonnage has no
            // timed concept, so one "+ Add load" tap plus a 60 s plank would
            // inject phantom kilograms into the week.
            #expect(TimedExercise.isTimed(c.input.name) == false, "a timed hold is loadable — \(c.name)")
        }
    }

    @Test("isUnilateral matches")
    func unilateralMatches() throws {
        for c in try GoldenFixture<NameIn, Bool>.load("unilateral-exercise").cases {
            #expect(Unilateral.isUnilateral(c.input.name) == c.expected, "isUnilateral — \(c.name)")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The deck ↔ map parity check.
//
// `Program.swift` used to carry a hand-copied `primary:` / `secondary:` answer
// on every one of its 37 movements, because the map had not been ported. It now
// resolves them through `MuscleMap` instead, and this is the assertion that
// makes that safe in BOTH directions:
//
//   · every lift the deck prescribes resolves in the map — a miss would leave
//     that lift with empty movers, contributing nothing to the muscle sheet,
//     and nothing on screen would say so;
//   · and the answer it resolves to is the answer the TypeScript gives, taken
//     straight out of the golden vector rather than from the Swift table it is
//     supposed to be checking.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("The deck resolves its anatomy from the map, and agrees with TypeScript")
struct DeckMoverParityTests {

    /// Every prescribed movement, both phases, duplicates included — the same
    /// 37 rows the founder's Onyx-5 routine rows hold.
    private var allExercises: [ProgramExercise] {
        FounderTables.deck.days.flatMap(\.exercises)
    }

    @Test("all 37 movements resolve, and carry exactly what the map says")
    func everyLiftResolves() {
        #expect(allExercises.count == 37)
        for ex in allExercises {
            let mapped = MuscleMap.movers(ex.name)
            #expect(mapped != nil, "\(ex.name) is not in the muscle map — it would train nothing")
            #expect(ex.movers == mapped, "\(ex.name) — deck \(ex.movers) vs map \(String(describing: mapped))")
            // Empty movers would be silent: the lift would still render, still
            // count sets, and simply never appear on the muscle sheet.
            #expect(ex.movers.primary.isEmpty == false, "\(ex.name) has no primary mover")
        }
    }

    @Test("and that answer is the TypeScript's, vector for vector")
    func agreesWithTypeScript() throws {
        let fixture = try GoldenFixture<MuscleMapGoldenTests.NameIn, MuscleMapGoldenTests.LookupOut>
            .load("muscle-map-lookup")
        // The vector carries every deck name (the emitter walks the same deck),
        // so this is the deck's anatomy compared against the shipping web app's
        // rather than against the Swift table that was ported from it.
        let byName = Dictionary(fixture.cases.map { ($0.input.name, $0.expected) }, uniquingKeysWith: { a, _ in a })
        for ex in allExercises {
            let expected = try #require(byName[ex.name], "\(ex.name) is missing from muscle-map-lookup.json")
            #expect(ex.movers == expected.movers, "\(ex.name) — deck disagrees with the TypeScript map")
        }
    }

    @Test("the split-by-grip row is still two different answers")
    func theRowSplitSurvives() throws {
        let wide = try #require(allExercises.first { $0.name == "Seated Cable Row (Wide Grip)" })
        let vGrip = try #require(allExercises.first { $0.name == "Seated Cable Row (V-Grip)" })
        // A merge here is a loud bug; the SPLIT is the silent one, and it was
        // carved back out deliberately on 2026-08-06 because sharing one row
        // cost a real record. `traps` is the whole difference.
        #expect(wide.movers != vGrip.movers)
        #expect(wide.movers.secondary.contains("traps"))
        #expect(vGrip.movers.secondary.contains("traps") == false)
        // And neither grip pays the rear delt — the load is chosen for the
        // mid-back, and Hevy classes every row as back work.
        #expect(wide.movers.secondary.contains("rear_delts") == false)
        #expect(vGrip.movers.secondary.contains("rear_delts") == false)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tags (P3 E4) — the chip row, and the two labels that would otherwise print
// themselves twice.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Exercise tags")
struct ExerciseTagsGoldenTests {
    struct TagIn: Decodable { let name: String?; let compound: Bool? }

    @Test("exerciseTags matches — order, collisions and the fallback")
    func tagsMatch() throws {
        let fixture = try GoldenFixture<TagIn, [ExerciseTag]>.load("exercise-tags")
        #expect(fixture.cases.count > 100)
        for c in fixture.cases {
            #expect(
                ExerciseTags.tags(for: c.input.name, compound: c.input.compound) == c.expected,
                "exerciseTags — \(c.name)"
            )
        }
    }

    @Test("labels is the labels of the same list")
    func labelsMatch() throws {
        for c in try GoldenFixture<TagIn, [ExerciseTag]>.load("exercise-tags").cases {
            #expect(
                ExerciseTags.labels(for: c.input.name, compound: c.input.compound) == c.expected.map(\.label),
                "labels — \(c.name)"
            )
        }
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// The cardio table (W4)
// ─────────────────────────────────────────────────────────────────────────────

/// `MuscleMap.cardioDict` — what a BOUT works, for the surfaces that name
/// muscles in words.
///
/// ── WHY THIS SUITE IS ABOUT WHAT THE TABLE DOES *NOT* TOUCH ─────────────────
/// The table exists because `dict` cannot hold it. `dict` is held to the
/// TypeScript by two golden fixtures AND is the input to
/// `MuscleCredit.weightedSets`, so a treadmill entry there would start paying
/// muscle credit for walking — moving the weekly accumulator, the Freshness
/// Map and the battery, silently, in the name of drawing two chips on a card.
///
/// So the assertions that matter most here are the negative ones: the lift
/// table still knows nothing about a bout, and the cardio table still knows
/// nothing about a lift. Either one failing is the separation collapsing.
@Suite("Cardio movers — the display table beside the dictionary")
struct CardioMoversTests {

    @Test("A bout resolves to legs, and the lift dictionary still refuses it")
    func treadmill() {
        #expect(MuscleMap.movers("Treadmill") == nil)
        #expect(MuscleMap.muscleGroups("Treadmill") == nil)

        let movers = MuscleMap.cardioMovers("Treadmill")
        #expect(movers?.primary == ["quadriceps", "calves"])
        #expect(movers?.secondary == ["hamstrings", "glutes"])
        #expect(MuscleMap.cardioPrimaryLandmarks("Treadmill") == [.quads, .calves])
        #expect(MuscleMap.cardioSecondaryLandmarks("Treadmill") == [.hamstrings, .glutes])
    }

    /// Every kind `CardioImport.offered` names must resolve, or a card drawn
    /// for that bout falls back to an empty chip row — which is the defect
    /// this table was added to fix, surviving for five of six kinds.
    @Test("Every offered kind except HIIT names a muscle")
    func everyKind() {
        for kind in CardioImport.offered where kind != CardioImport.hiit {
            #expect(MuscleMap.cardioMovers(kind) != nil, "no cardio entry for \(kind)")
        }
        // HIIT describes an INTERVAL STRUCTURE, not a movement. Guessing legs
        // from it would be the table asserting something the row does not say.
        #expect(MuscleMap.cardioMovers(CardioImport.hiit) == nil)
    }

    /// The machine names the exercise catalogue files bouts under, which are
    /// not the `cardio_logs` kinds.
    @Test("The catalogue's machine names resolve too")
    func machines() {
        for name in ["Treadmill Walk", "Incline Treadmill", "Stair Climber",
                     "Elliptical", "Stationary Bike", "Rowing Machine"] {
            #expect(MuscleMap.cardioMovers(name) != nil, "no cardio entry for \(name)")
        }
    }

    /// ── THE SEPARATION, FROM THE OTHER SIDE ─────────────────────────────────
    /// A lift must never reach this table, or the ledger would start drawing a
    /// bench press's chips out of the cardio vocabulary. `cardioDict`'s tokens
    /// are chosen so that nothing in the catalogue collides — the ergometer is
    /// `rowing` / `rower` and never the bare `row` that `dict`'s cable-row
    /// family matches on.
    @Test("A lift never resolves through the cardio table")
    func liftsAreRefused() {
        for name in ["Incline DB Press", "Seated Cable Row (Wide Grip)",
                     "Lat Pulldown", "Hack Squat", "Hanging Knee Raise",
                     "Romanian Deadlift", "Bench Press", "Leg Press"] {
            #expect(MuscleMap.cardioMovers(name) == nil, "\(name) reached the cardio table")
        }
    }

    /// Nothing in the cardio table may name a token the landmark fold does not
    /// know — a silent nil there is a chip that never draws, which is exactly
    /// the failure mode `LandmarkMuscle.from(token:)`'s own tests exist for.
    @Test("Every token in the table folds to a landmark")
    func tokensFold() {
        for entry in MuscleMap.cardioDict {
            for token in entry.muscles.primary + entry.muscles.secondary {
                #expect(LandmarkMuscle.from(token: token) != nil,
                        "\(token) folds to nothing")
            }
        }
    }
}
