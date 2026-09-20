import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Ceilings, effort, set tags and rest targets — replayed from `npm run golden`.
// ─────────────────────────────────────────────────────────────────────────────

private struct Empty: Decodable {}

/// `FounderTables.deck` is read from `plan-templates.json`, a copy of the
/// app's seed; this is the check that the copy is the deck the vectors on
/// this page (and the seed, queue and schedule pages) were generated over.
@Suite("Program deck — the Onyx-5 fixture")
struct ProgramDeckGoldenTests {
    struct PhaseIn: Decodable { let phase: ProgramPhase }
    struct ExOut: Decodable, Equatable { let name: String; let sets: Int; let reps: String; let restSec: Int?; let wk1Kg: Double? }
    struct DayOut: Decodable, Equatable { let key: String; let label: String; let weekday: Int; let exercises: [ExOut] }
    struct DeckOut: Decodable { let id: String; let days: [DayOut] }

    @Test("the founder's routine rows equal the TypeScript deck, per phase")
    func deckMatches() throws {
        for c in try GoldenFixture<PhaseIn, DeckOut>.load("program-onyx5").cases {
            let p = FounderTables.deck
            #expect(p.id == c.expected.id)
            let days = p.days.map { d in
                DayOut(key: d.key, label: d.label, weekday: d.weekday, exercises: d.exercises(for: c.input.phase).map {
                    ExOut(name: $0.name, sets: $0.sets(for: c.input.phase), reps: $0.reps, restSec: $0.restSec, wk1Kg: $0.wk1Kg)
                })
            }
            #expect(days == c.expected.days, "deck — \(c.name)")
        }
    }
}

@Suite("Ceilings — the rep window and the double-progression verdicts")
struct CeilingsGoldenTests {
    struct RepsIn: Decodable { let reps: String }

    @Test("parseRepWindow matches")
    func parseMatches() throws {
        for c in try GoldenFixture<RepsIn, RepWindow?>.load("rep-window").cases {
            #expect(Ceilings.parseRepWindow(c.input.reps) == c.expected, "parseRepWindow — \(c.name)")
        }
    }

    struct LookupIn: Decodable { let name: String; let dayKey: String?; let phase: ProgramPhase }
    struct LookupOut: Decodable { let window: RepWindow?; let hold: Double?; let restSec: Double? }

    @Test("repWindowFor, holdTargetFor and programRestSec match on every lift, day and phase")
    func lookupsMatch() throws {
        let fixture = try GoldenFixture<LookupIn, LookupOut>.load("program-lookups")
        #expect(fixture.cases.count > 400)
        for c in fixture.cases {
            let i = c.input
            #expect(Ceilings.repWindow(for: i.name, dayKey: i.dayKey, program: FounderTables.deck, phase: i.phase) == c.expected.window, "repWindowFor — \(c.name)")
            expectClose(Ceilings.holdTarget(for: i.name, dayKey: i.dayKey, program: FounderTables.deck, phase: i.phase), c.expected.hold, "holdTargetFor — \(c.name)")
            expectClose(RestTargets.programRestSec(for: i.name, dayKey: i.dayKey, program: FounderTables.deck, phase: i.phase), c.expected.restSec, "programRestSec — \(c.name)")
        }
    }

    struct SessIn: Decodable { let sets: [WorkingSet]; let ceiling: Double; let floor: Double }
    struct SessOut: Decodable {
        let working: [WorkingSet]; let cleared: Bool; let ladder: [LoadRung]; let verdict: LadderVerdict
        let topLoadCleared: Bool; let levelUp: LevelUpCue?
    }

    @Test("every single-session verdict matches")
    func sessionMatches() throws {
        let fixture = try GoldenFixture<SessIn, SessOut>.load("ceiling-session")
        #expect(fixture.cases.count > 150)
        for c in fixture.cases {
            let sets = c.input.sets, ceiling = c.input.ceiling
            #expect(Ceilings.workLoads(sets) == c.expected.working, "workLoads — \(c.name)")
            #expect(Ceilings.clearedCeiling(sets, ceiling: ceiling) == c.expected.cleared, "clearedCeiling — \(c.name)")
            #expect(Ceilings.loadLadder(sets, ceiling: ceiling) == c.expected.ladder, "loadLadder — \(c.name)")
            #expect(Ceilings.ladderVerdict(sets, ceiling: ceiling) == c.expected.verdict, "ladderVerdict — \(c.name)")
            #expect(Ceilings.topLoadCleared(sets, ceiling: ceiling) == c.expected.topLoadCleared, "topLoadCleared — \(c.name)")
            #expect(Ceilings.levelUpCue(sets, window: RepWindow(floor: c.input.floor, ceiling: ceiling)) == c.expected.levelUp, "levelUpCue — \(c.name)")
        }
    }

    struct ProgIn: Decodable { let sessions: [[WorkingSet]]; let ceiling: Double? }

    @Test("progressionVerdict matches over every pair of sessions")
    func progressionMatches() throws {
        let fixture = try GoldenFixture<ProgIn, ProgressionVerdict>.load("progression-verdict")
        #expect(fixture.cases.count > 200)
        for c in fixture.cases {
            #expect(Ceilings.progressionVerdict(c.input.sessions, ceiling: c.input.ceiling) == c.expected, "progressionVerdict — \(c.name)")
        }
    }

    @Test("timedProgressionVerdict matches — never a kg")
    func timedMatches() throws {
        for c in try GoldenFixture<ProgIn, ProgressionVerdict>.load("timed-progression-verdict").cases {
            #expect(Ceilings.timedProgressionVerdict(c.input.sessions, targetSec: c.input.ceiling) == c.expected, "timedProgressionVerdict — \(c.name)")
        }
    }

    struct StepIn: Decodable { let kg: Double; let step: Double? }
    struct SetsIn: Decodable { let sets: [WorkingSet] }

    @Test("the stepper's steps, the effort ceiling and the snap match")
    func stepsMatch() throws {
        let fixture = try GoldenFixture<StepIn, Double>.load("load-steps")
        // The constants are stated in the fixture's note, so the numbers
        // themselves are pinned here against the TypeScript's own values.
        #expect(Ceilings.loadSteps == [2.5, 1.25])
        #expect(Ceilings.loadStepKg == Ceilings.loadSteps[0])
        #expect(Ceilings.loadStepFineKg == Ceilings.loadSteps[Ceilings.loadSteps.count - 1])
        #expect(Ceilings.progressionMaxRpe == 8.5)
        for c in fixture.cases {
            let got = c.input.step.map { Ceilings.roundToStep(c.input.kg, step: $0) }
                ?? Ceilings.roundToStep(c.input.kg)
            expectClose(got, c.expected, "roundToStep — \(c.name)")
        }
        // Not in the vector — `JSON.stringify` cannot carry NaN. Both sides
        // hand a non-finite value straight back rather than producing one.
        #expect(Ceilings.roundToStep(.nan).isNaN)
        #expect(Ceilings.roundToStep(47, step: .nan) == 47)
    }

    @Test("underEffortCeiling matches — an unrated set passes")
    func effortCeilingMatches() throws {
        for c in try GoldenFixture<SetsIn, Bool>.load("effort-ceiling").cases {
            #expect(Ceilings.underEffortCeiling(c.input.sets) == c.expected, "underEffortCeiling — \(c.name)")
        }
        // Not in the vector, same reason: a non-finite rating is no rating.
        #expect(Ceilings.underEffortCeiling([WorkingSet(weightKg: 60, reps: 12, rpe: .nan)]))
    }
}

@Suite("Effort — CR10, the ladder and the words")
struct EffortGoldenTests {
    struct Tables: Decodable {
        let cr10Min: Double; let cr10Max: Double; let anchors: [Cr10Anchor]; let ladder: [RpeStop]; let words: [EffortWord]
        let coldBaseline: Double; let minHistory: Int
    }

    @Test("the tables equal the TypeScript")
    func tablesMatch() throws {
        let e = try #require(try GoldenFixture<Empty, Tables>.load("effort-tables").cases.first).expected
        #expect(Effort.cr10Min == e.cr10Min)
        #expect(Effort.cr10Max == e.cr10Max)
        #expect(Effort.anchors == e.anchors)
        #expect(Effort.ladder == e.ladder)
        #expect(Effort.words == e.words)
        #expect(Effort.coldBaseline == e.coldBaseline)
        #expect(Effort.minHistory == e.minHistory)
    }

    struct ValueIn: Decodable { let v: Double? }
    struct ValueOut: Decodable {
        let label: String; let normalized: Double?; let stopIndex: Int; let rpeLabel: String
        let up: Double?; let down: Double?; let word: EffortWord?
    }

    @Test("every reader of a CR10 value matches")
    func valuesMatch() throws {
        for c in try GoldenFixture<ValueIn, ValueOut>.load("cr10").cases {
            let v = c.input.v
            #expect(Effort.cr10Label(v) == c.expected.label, "cr10Label — \(c.name)")
            expectClose(Effort.normalizeCr10(v), c.expected.normalized, "normalizeCr10 — \(c.name)")
            #expect(Effort.rpeStopIndex(v) == c.expected.stopIndex, "rpeStopIndex — \(c.name)")
            #expect(Effort.rpeLabel(v) == c.expected.rpeLabel, "rpeLabel — \(c.name)")
            expectClose(Effort.nudgeRpe(v, 1), c.expected.up, "nudgeRpe up — \(c.name)")
            expectClose(Effort.nudgeRpe(v, -1), c.expected.down, "nudgeRpe down — \(c.name)")
            #expect(Effort.effortWord(for: v) == c.expected.word, "effortWordFor — \(c.name)")
        }
    }

    struct KeyIn: Decodable { let key: String? }

    @Test("effortCr10 matches")
    func cr10Matches() throws {
        for c in try GoldenFixture<KeyIn, Double?>.load("effort-cr10").cases {
            expectClose(Effort.effortCr10(c.input.key), c.expected, "effortCr10 — \(c.name)")
        }
    }

    struct SuggestIn: Decodable { let mean: Double?; let history: [Double] }

    @Test("suggestEffortWord matches on every band edge")
    func suggestMatches() throws {
        for c in try GoldenFixture<SuggestIn, EffortWord?>.load("effort-suggest").cases {
            #expect(Effort.suggestEffortWord(mean: c.input.mean, history: c.input.history) == c.expected, "suggestEffortWord — \(c.name)")
        }
    }
}

@Suite("Set tags — what a set was and how it went")
struct SetTagsGoldenTests {
    struct Tables: Decodable { let tags: [String: SetTag]; let quality: [String: SetQuality]; let qualityKeys: [String] }

    @Test("the vocabularies equal the TypeScript")
    func tablesMatch() throws {
        let e = try #require(try GoldenFixture<Empty, Tables>.load("set-tags-table").cases.first).expected
        #expect(SetTags.tags == e.tags)
        #expect(SetTags.quality == e.quality)
        #expect(SetTags.qualityKeys == e.qualityKeys)
    }

    struct TypeIn: Decodable { let v: String? }
    struct TypeOut: Decodable { let working: Bool; let tag: SetTag?; let quality: SetQuality?; let isQuality: Bool }

    @Test("the readers match")
    func readersMatch() throws {
        for c in try GoldenFixture<TypeIn, TypeOut>.load("set-type").cases {
            let v = c.input.v
            #expect(SetTags.isWorkingSet(v) == c.expected.working, "isWorkingSet — \(c.name)")
            #expect(SetTags.tag(for: v) == c.expected.tag, "setTagFor — \(c.name)")
            #expect(SetTags.quality(for: v) == c.expected.quality, "setQualityFor — \(c.name)")
            #expect(SetTags.isSetQuality(v) == c.expected.isQuality, "isSetQuality — \(c.name)")
        }
    }

    struct CountsIn: Decodable { let counts: [String: Int] }

    @Test("setComposition matches — fixed order, only what occurred")
    func compositionMatches() throws {
        for c in try GoldenFixture<CountsIn, [SetCompositionEntry]>.load("set-composition").cases {
            #expect(SetTags.composition(c.input.counts) == c.expected, "setComposition — \(c.name)")
        }
    }

    // MARK: - The third length (W3)

    /// `word` and `hint` moved here out of the phone's `LoggerModel.SetKind`
    /// so the watch's Set Quality panel could read them. Both clients now
    /// depend on this table being complete and on `tagKeys` naming exactly the
    /// kinds `tags` holds — a fifth kind added to one and not the other is a
    /// chip row that draws four items and a badge that draws five.
    @Test("tagKeys names exactly the kinds, and every one has a word and a hint")
    func kindWords() {
        #expect(Set(SetTags.tagKeys) == Set(SetTags.tags.keys))
        #expect(SetTags.tagKeys == ["warmup", "failure", "dropset", "ghost"])

        var words: Set<String> = []
        for key in SetTags.tagKeys {
            let word = SetTags.word(for: key)
            let hint = SetTags.hint(for: key)
            #expect(!word.isEmpty && !hint.isEmpty, "\(key) has no word or no hint")
            // A chip row of four identical words is four chips that say
            // nothing — and the badge letters are already distinct.
            #expect(words.insert(word).inserted, "\(key) repeats the word \(word)")
            #expect(word != SetTags.word(for: nil), "\(key) reads as the unmarked set")
        }
    }

    /// `nil` and `"normal"` are the SAME state — the absence of a claim —
    /// which is why neither client draws a chip for it.
    @Test("the unmarked set answers the same to nil and to normal")
    func normalIsAbsence() {
        #expect(SetTags.word(for: nil) == SetTags.word(for: "normal"))
        #expect(SetTags.hint(for: nil) == SetTags.hint(for: "normal"))
        #expect(SetTags.word(for: nil) == "Normal")
        // An unknown value reads as unmarked rather than crashing or printing
        // a raw key: a kind written by a newer client must not make an older
        // one unable to draw the set at all.
        #expect(SetTags.word(for: "supersetish") == "Normal")
    }
}

@Suite("Rest targets — the pure half")
struct RestTargetsGoldenTests {
    struct Constants: Decodable { let step: Double; let min: Double; let max: Double }

    @Test("the grid constants match")
    func constantsMatch() throws {
        let e = try #require(try GoldenFixture<Empty, Constants>.load("rest-constants").cases.first).expected
        #expect(RestTargets.stepSec == e.step)
        #expect(RestTargets.minSec == e.min)
        #expect(RestTargets.maxSec == e.max)
    }

    struct SecIn: Decodable { let sec: Double }
    struct SecOut: Decodable { let clamped: Double; let formatted: String }

    @Test("clampRestSec and formatRestTarget match")
    func clampFormatMatch() throws {
        for c in try GoldenFixture<SecIn, SecOut>.load("rest-clamp-format").cases {
            let clamped = RestTargets.clamp(c.input.sec)
            expectClose(clamped, c.expected.clamped, "clampRestSec — \(c.name)")
            #expect(RestTargets.format(clamped) == c.expected.formatted, "formatRestTarget — \(c.name)")
        }
    }

    struct KeyIn: Decodable { let name: String; let dayKey: String?; let programId: String; let date: String }
    struct KeyOut: Decodable { let plan: String; let session: String }

    @Test("the store keys match")
    func keysMatch() throws {
        for c in try GoldenFixture<KeyIn, KeyOut>.load("rest-keys").cases {
            let i = c.input
            #expect(RestTargets.targetKey(i.name, dayKey: i.dayKey, programId: i.programId) == c.expected.plan, "restTargetKey — \(c.name)")
            #expect(RestTargets.sessionKey(i.date, i.name, dayKey: i.dayKey, programId: i.programId) == c.expected.session, "sessionRestKey — \(c.name)")
        }
    }
}
