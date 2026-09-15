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
    struct TypeIn: Decodable { let setType: String? }
    struct WeightIn: Decodable { let weightKg: Double }
    struct LabelIn: Decodable { let axis: PrAxis; let timed: Bool }

    @Test("the eligibility rules and labels match")
    func rulesMatch() throws {
        // `pr-e1rm-eligible` is gone with the rule it pinned: the e1RM axis is
        // no longer gated on the programmed rep floor (`PrEngine`, 2026-09-15).
        // What bounds it now is the formula's own domain, and that is pinned by
        // `one-rep-max` in `DomainGoldenTests`.
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

    /// ── THE e1RM BAR IS NO LONGER PINNED BY THIS VECTOR ─────────────────────
    /// `bestE1rm` in `pr-baselines.json` was computed under two rules that have
    /// both changed: Epley, and the programmed-rep-floor gate (`PrEngine`,
    /// 2026-09-15). Every other tuple in the file — the weight bar, the
    /// reps-at-load bar, the seconds bar, the set-volume bar, the insertion
    /// ORDER they are emitted in, and the floor fold — is untouched by that
    /// change and is still exactly the specification.
    ///
    /// So the file is not regenerated. `GoldenVector`'s own header is explicit
    /// about why — "a spec you can regenerate from the code under test is not a
    /// spec" — and rewriting 300 expectations from the engine would retire the
    /// only independent record of what the other four bars are supposed to do.
    /// The one axis whose rule changed is asserted by hand instead, in
    /// `PrEngineE1rmTests`, against arithmetic written out longhand.
    private func withoutE1rm(_ b: PrBaselines) -> PrBaselines {
        PrBaselines(
            bestWeight: b.bestWeight, bestRepsAtWeight: b.bestRepsAtWeight,
            bestE1rm: [], bestSeconds: b.bestSeconds, bestSetVolume: b.bestSetVolume
        )
    }

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
            #expect(withoutE1rm(actual) == withoutE1rm(c.expected), "buildBaselines — \(c.name)")
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

            // ── THE e1RM AXIS IS FILTERED OUT OF BOTH SIDES ─────────────────
            // For the reason `withoutE1rm` gives above, and on the same terms:
            // the expectations in this file were computed under Epley with the
            // rep-floor gate, so every `.e1rm` entry in them describes a rule
            // the engine no longer has. Everything else in the file — which
            // axes the weight, reps and volume rules award, the ORDER they come
            // back in, the delta each record carries, the pair collapse, the
            // per-key grouping — is unaffected and is still the specification.
            //
            // Filtering rather than deleting the cases is what keeps that true:
            // a case whose only recorded axis was `.e1rm` still asserts that
            // the other three award NOTHING, which is half of what it was
            // written to say.
            func drop(_ axes: [PrAxis]) -> [PrAxis] { axes.filter { $0 != .e1rm } }

            #expect(r.perSet.count == e.perSet.count, "perSet length — \(c.name)")
            for (i, (a, x)) in zip(r.perSet, e.perSet).enumerated() {
                #expect(drop(a.axes) == drop(x.axes), "axes[\(i)] — \(c.name)")
                let records = Dictionary(uniqueKeysWithValues:
                    a.records.filter { $0.key != .e1rm }.map { ($0.key.rawValue, $0.value) })
                #expect(records == x.records.filter { $0.key != PrAxis.e1rm.rawValue }, "records[\(i)] — \(c.name)")
            }

            let actualKeys = r.axesByKey.filter { !drop($0.axes).isEmpty }
            let expectedKeys = e.axesByKey.filter { !drop($0.axes).isEmpty }
            #expect(actualKeys.map(\.key) == expectedKeys.map(\.key), "axesByKey keys — \(c.name)")
            #expect(actualKeys.map { drop($0.axes) } == expectedKeys.map { drop($0.axes) }, "axesByKey axes — \(c.name)")

            let rec = PrEngine.recordSets(c.input.sets, r).map {
                ($0.key, $0.records.filter { $0.axis != .e1rm })
            }.filter { !$0.1.isEmpty }
            let expectedRec = e.recordSets.map {
                ($0.key, $0.records.filter { $0.axis != .e1rm })
            }.filter { !$0.1.isEmpty }
            #expect(rec.map(\.0) == expectedRec.map(\.0), "recordSets keys — \(c.name)")
            for (a, x) in zip(rec, expectedRec) {
                #expect(a.1.map(\.axis) == x.1.map(\.axis), "recordSets axes — \(a.0) — \(c.name)")
                for (ra, rx) in zip(a.1, x.1) {
                    #expect(ra.set == RecordSet(weightKg: rx.weightKg, reps: rx.reps, value: rx.value), "recordSets \(a.0) \(ra.axis) — \(c.name)")
                }
            }
        }
    }
}
