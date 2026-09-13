import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// PR engine — the web app's `lib/training/pr*.ts` + `exercises/aliases.ts`,
// replayed from `npm run golden`.
// ─────────────────────────────────────────────────────────────────────────────

private struct Empty: Decodable {}

@Suite("Exercise aliases")
struct AliasGoldenTests {
    @Test("the alias table equals the TypeScript one")
    func tableMatches() throws {
        let e = try #require(try GoldenFixture<Empty, [String: String]>.load("exercise-aliases").cases.first).expected
        #expect(ExerciseAliases.table == e)
    }

    struct RawIn: Decodable { let raw: String }

    @Test("canonicalExerciseName matches — aliases resolve, everything else is handed back untouched")
    func canonicalMatches() throws {
        let fixture = try GoldenFixture<RawIn, String>.load("exercise-canonical-name")
        #expect(fixture.cases.count > 80)
        for c in fixture.cases {
            #expect(ExerciseAliases.canonicalName(c.input.raw) == c.expected, "canonicalExerciseName — \(c.name)")
        }
    }
}

@Suite("PR engine — the four axes")
struct PrEngineGoldenTests {
    struct E1rmIn: Decodable { let reps: Double; let floor: Double? }
    struct TypeIn: Decodable { let setType: String? }
    struct WeightIn: Decodable { let weightKg: Double }
    struct LabelIn: Decodable { let axis: PrAxis; let timed: Bool }

    @Test("the eligibility rules and labels match")
    func rulesMatch() throws {
        for c in try GoldenFixture<E1rmIn, Bool>.load("pr-e1rm-eligible").cases {
            #expect(PrEngine.e1rmEligible(c.input.reps, floor: c.input.floor) == c.expected, "e1rmEligible — \(c.name)")
        }
        for c in try GoldenFixture<TypeIn, Bool>.load("pr-ineligible").cases {
            #expect(PrEngine.isPrIneligible(c.input.setType) == c.expected, "isPrIneligible — \(c.name)")
        }
        for c in try GoldenFixture<WeightIn, Bool>.load("pr-reps-eligible").cases {
            #expect(PrEngine.repsAxisEligible(c.input.weightKg) == c.expected, "repsAxisEligible — \(c.name)")
        }
        for c in try GoldenFixture<LabelIn, String>.load("pr-axis-label").cases {
            #expect(PrEngine.axisLabel(c.input.axis, timed: c.input.timed) == c.expected, "prAxisLabel — \(c.name)")
        }
    }

    struct CreditIn: Decodable { let rows: [VolumeCreditRow] }

    @Test("volumeCredits matches — the pair scores once, at the weaker side, on the completing row")
    func creditsMatch() throws {
        let fixture = try GoldenFixture<CreditIn, [Double?]>.load("pr-volume-credits")
        for c in fixture.cases {
            let actual = PrEngine.volumeCredits(c.input.rows)
            #expect(actual.count == c.expected.count, "volumeCredits length — \(c.name)")
            for (a, e) in zip(actual, c.expected) { expectClose(a, e, "volumeCredits — \(c.name)") }
        }
    }

    struct BaseIn: Decodable { let rows: [BaselineSetRow]; let timedKeys: [String]; let floor: Bool }

    @Test("buildBaselines matches, tuple for tuple, in insertion order")
    func baselinesMatch() throws {
        let fixture = try GoldenFixture<BaseIn, PrBaselines>.load("pr-baselines")
        #expect(fixture.cases.count > 300)
        for c in fixture.cases {
            let timed = Set(c.input.timedKeys)
            let actual = PrEngine.buildBaselines(
                c.input.rows,
                isTimed: { timed.contains($0) },
                floorFor: c.input.floor ? { FounderTables.floors[$0] } : nil
            )
            #expect(actual == c.expected, "buildBaselines — \(c.name)")
        }
    }

    struct SessIn: Decodable { let sets: [PrCandidateSet]; let baselines: PrBaselines }
    struct PerSet: Decodable { let axes: [PrAxis]; let est1rm: Double?; let records: [String: AxisRecord] }
    struct KeyAxesOut: Decodable { let key: String; let axes: [PrAxis] }
    struct RecEntry: Decodable { let axis: PrAxis; let weightKg: Double; let reps: Double; let value: Double }
    struct RecKey: Decodable { let key: String; let records: [RecEntry] }
    struct SessOut: Decodable { let perSet: [PerSet]; let axesByKey: [KeyAxesOut]; let prCount: Int; let recordSets: [RecKey] }

    @Test("whole sessions match — axes, deltas, counts and the ledger")
    func sessionsMatch() throws {
        let fixture = try GoldenFixture<SessIn, SessOut>.load("pr-session")
        #expect(fixture.cases.count > 150)
        for c in fixture.cases {
            // `PrSeed` — the July 2026 record book asserted by hand and the
            // detection it suppressed — is `personal_records` rows now; the
            // engine has no asserted era to replay these against.
            if c.name.hasPrefix("seed — ") || c.name.contains(" asserted — ") { continue }
            let r = PrEngine.detectSessionPrs(c.input.sets, c.input.baselines)
            let e = c.expected

            #expect(r.perSet.count == e.perSet.count, "perSet length — \(c.name)")
            for (i, (a, x)) in zip(r.perSet, e.perSet).enumerated() {
                #expect(a.axes == x.axes, "axes[\(i)] — \(c.name)")
                expectClose(a.est1rm, x.est1rm, "est1rm[\(i)] — \(c.name)")
                let records = Dictionary(uniqueKeysWithValues: a.records.map { ($0.key.rawValue, $0.value) })
                #expect(records == x.records, "records[\(i)] — \(c.name)")
            }

            #expect(r.axesByKey.map(\.key) == e.axesByKey.map(\.key), "axesByKey keys — \(c.name)")
            #expect(r.axesByKey.map(\.axes) == e.axesByKey.map(\.axes), "axesByKey axes — \(c.name)")
            #expect(r.prCount == e.prCount, "prCount — \(c.name)")

            let rec = PrEngine.recordSets(c.input.sets, r)
            #expect(rec.map(\.key) == e.recordSets.map(\.key), "recordSets keys — \(c.name)")
            for (a, x) in zip(rec, e.recordSets) {
                #expect(a.records.map(\.axis) == x.records.map(\.axis), "recordSets axes — \(a.key) — \(c.name)")
                for (ra, rx) in zip(a.records, x.records) {
                    #expect(ra.set == RecordSet(weightKg: rx.weightKg, reps: rx.reps, value: rx.value), "recordSets \(a.key) \(ra.axis) — \(c.name)")
                }
            }
        }
    }
}
