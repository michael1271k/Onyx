import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// One-rep max — Brzycki
// ─────────────────────────────────────────────────────────────────────────────

@Suite("OneRepMax — estimated 1RM")
struct OneRepMaxGoldenTests {
    struct Input: Decodable { let weight: Double; let reps: Double }

    /// ── THIS VECTOR IS NO LONGER THE TYPESCRIPT'S ───────────────────────────
    /// It was `epley.json`, exported from the web app and pinned to it. The web
    /// app is gone (W6) and the formula changed with it — Brzycki, so the
    /// number matches what every other training app reports for the same set.
    /// The grid is the same grid; the expectations were recomputed, plus ten
    /// cases the old one had no reason to carry: the rep ceiling, the
    /// singularity at 37, and the three sets from the session that prompted the
    /// change.
    @Test("matches the Brzycki vector on every case")
    func matchesGoldenVectors() throws {
        let fixture = try GoldenFixture<Input, Double?>.load("one-rep-max")
        #expect(!fixture.cases.isEmpty)

        for c in fixture.cases {
            let actual = OneRepMax.estimate(weight: c.input.weight, reps: c.input.reps)
            expectClose(actual, c.expected, "oneRepMax — \(c.name)")
        }
    }

    @Test("the vector is checked against the formula written out by hand")
    func vectorIsNotSelfReferential() {
        // A regenerated golden proves only that the code has not changed since
        // it was regenerated. This is the independent arithmetic: 24 kg × 9 is
        // 24 × 36 / 28 = 30.857…, which is 30.86 — the exact figure the founder
        // read off Hevy for the same set, and the reason Brzycki is what Onyx
        // now reports.
        #expect(OneRepMax.estimate(weight: 24, reps: 9) == 30.86)
        #expect(OneRepMax.estimate(weight: 100, reps: 5) == 112.5)
        #expect(OneRepMax.estimate(weight: 60, reps: 12) == 86.4)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Energy — TEF and TDEE
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Energy — TEF and TDEE")
struct EnergyGoldenTests {
    struct TefInput: Decodable { let intakeKcal: Double? }
    struct TdeeInput: Decodable {
        let bmr: Double?
        let active: Double?
        let intakeKcal: Double?
    }

    @Test("thermic effect of food matches")
    func tefMatches() throws {
        let fixture = try GoldenFixture<TefInput, Double?>.load("tef")
        for c in fixture.cases {
            expectClose(
                Energy.tef(intakeKcal: c.input.intakeKcal),
                c.expected,
                "tefKcal — \(c.name)"
            )
        }
    }

    @Test("total daily energy expenditure matches, including every null path")
    func tdeeMatches() throws {
        let fixture = try GoldenFixture<TdeeInput, Double?>.load("tdee")
        for c in fixture.cases {
            expectClose(
                Energy.tdee(bmr: c.input.bmr, active: c.input.active, intakeKcal: c.input.intakeKcal),
                c.expected,
                "tdeeKcal — \(c.name)"
            )
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Battery
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Battery — the drain model (v9)")
struct BatteryGoldenTests {
    struct Constants: Decodable {
        let floor, wakeMin, wakeRange, timeMax, activityCap, workoutMax: Double
        let defaultRpe, relMin, relMax, maxAwake: Double
        let maxTotalDrain, maintenanceDrainFactor, maintenanceRelMin: Double
        let restorativeShare: Double
        let version, loadCap, wellnessCap, zNeutral, zSlope: Double
    }
    struct Empty: Decodable {}
    struct WorkoutMaxInput: Decodable { let dayKey: String?; let maintenance: Bool }
    struct RelMinInput: Decodable { let maintenance: Bool }
    struct SleepQualityExpected: Decodable {
        let quality, morningCharge, ratio, stagesQ, hrvQ, rhrQ: Double
    }
    struct ZInput: Decodable { let z: Double? }
    struct WorkoutDrainInput: Decodable {
        let sessionVolumeKg: Double
        let trailingAvgVolumeKg: Double
        let sessionRpe: Double?
        let dayKey: String?
        let maintenance: Bool
    }
    struct TimeDrainInput: Decodable { let hoursAwake: Double }
    struct BatteryInput: Decodable {
        let inputs: ScoringInputs
        let hoursAwakeArg: Double?
    }
    struct BatteryExpected: Decodable { let morningCharge: Double; let currentPct: Double }

    @Test("every constant survived the translation")
    func constantsMatch() throws {
        let fixture = try GoldenFixture<Empty, Constants>.load("battery-constants")
        let e = try #require(fixture.cases.first).expected
        let d = Battery.defaults

        expectClose(d.floor, e.floor, "floor")
        expectClose(d.wakeMin, e.wakeMin, "wakeMin")
        expectClose(d.wakeRange, e.wakeRange, "wakeRange")
        expectClose(d.timeMax, e.timeMax, "timeMax")
        expectClose(d.activityCap, e.activityCap, "activityCap")
        expectClose(d.workoutMax, e.workoutMax, "workoutMax")
        expectClose(d.defaultRpe, e.defaultRpe, "defaultRpe")
        expectClose(d.relMin, e.relMin, "relMin")
        expectClose(d.relMax, e.relMax, "relMax")
        expectClose(d.maxAwake, e.maxAwake, "maxAwake")
        expectClose(Battery.maxTotalDrain, e.maxTotalDrain, "maxTotalDrain")
        expectClose(Battery.maintenanceDrainFactor, e.maintenanceDrainFactor, "maintenanceDrainFactor")
        expectClose(Battery.maintenanceRelMin, e.maintenanceRelMin, "maintenanceRelMin")
        expectClose(d.restorativeShare, e.restorativeShare, "restorativeShare")
        expectClose(d.version, e.version, "version")
        expectClose(d.loadCap, e.loadCap, "loadCap")
        expectClose(d.wellnessCap, e.wellnessCap, "wellnessCap")
        expectClose(d.zNeutral, e.zNeutral, "zNeutral")
        expectClose(d.zSlope, e.zSlope, "zSlope")
    }

    @Test("workoutMaxFor matches — keyed on the programme day, never the split")
    func workoutMaxMatches() throws {
        let fixture = try GoldenFixture<WorkoutMaxInput, Double>.load("workout-max")
        for c in fixture.cases {
            expectClose(
                Battery.workoutMaxFor(dayKey: c.input.dayKey, maintenance: c.input.maintenance),
                c.expected,
                "workoutMaxFor — \(c.name)"
            )
        }
    }

    @Test("relMinFor matches")
    func relMinMatches() throws {
        let fixture = try GoldenFixture<RelMinInput, Double>.load("rel-min")
        for c in fixture.cases {
            expectClose(
                Battery.relMinFor(maintenance: c.input.maintenance),
                c.expected,
                "relMinFor — \(c.name)"
            )
        }
    }

    @Test("sleep quality and the wake charge it drives both match")
    func sleepQualityMatches() throws {
        let fixture = try GoldenFixture<ScoringInputs, SleepQualityExpected>.load("sleep-quality")
        for c in fixture.cases {
            let parts = Battery.sleepQualityParts(c.input)
            let quality = Battery.computeSleepQuality(c.input)
            expectClose(quality, c.expected.quality, "computeSleepQuality — \(c.name)")
            expectClose(parts.ratio, c.expected.ratio, "ratio — \(c.name)")
            expectClose(parts.stagesQ, c.expected.stagesQ, "stagesQ — \(c.name)")
            expectClose(parts.hrvQ, c.expected.hrvQ, "hrvQ — \(c.name)")
            expectClose(parts.rhrQ, c.expected.rhrQ, "rhrQ — \(c.name)")
            expectClose(
                Battery.computeMorningCharge(sleepQuality: quality),
                c.expected.morningCharge,
                "computeMorningCharge — \(c.name)"
            )
        }
    }

    @Test("zQuality matches — neutral 0.75, full at +1, a quarter at −2")
    func zQualityMatches() throws {
        for c in try GoldenFixture<ZInput, Double>.load("z-quality").cases {
            expectClose(Battery.zQuality(c.input.z), c.expected, "zQuality — \(c.name)")
        }
    }

    @Test("the v9 wellness drain matches, item by item")
    func wellnessDrainMatches() throws {
        let fixture = try GoldenFixture<ScoringInputs, Battery.WellnessParts>.load("wellness-drain")
        for c in fixture.cases {
            let parts = Battery.wellnessParts(c.input)
            expectClose(parts.fatigue, c.expected.fatigue, "fatigue — \(c.name)")
            expectClose(parts.soreness, c.expected.soreness, "soreness — \(c.name)")
            expectClose(parts.onset, c.expected.onset, "onset — \(c.name)")
            expectClose(parts.sleep, c.expected.sleep, "sleep — \(c.name)")
            expectClose(parts.index, c.expected.index, "index — \(c.name)")
            expectClose(parts.drain, c.expected.drain, "drain — \(c.name)")
        }
    }

    @Test("the v9 load drain matches across the ACWR × strain grid")
    func loadDrainMatches() throws {
        let fixture = try GoldenFixture<ScoringInputs, Battery.LoadParts>.load("load-drain")
        #expect(fixture.cases.count > 100)
        for c in fixture.cases {
            let parts = Battery.loadParts(c.input)
            expectClose(parts.acwrTerm, c.expected.acwrTerm, "acwrTerm — \(c.name)")
            expectClose(parts.strainTerm, c.expected.strainTerm, "strainTerm — \(c.name)")
            expectClose(parts.drain, c.expected.drain, "drain — \(c.name)")
        }
    }

    @Test("the breakdown matches, every term of it")
    func breakdownMatches() throws {
        let fixture = try GoldenFixture<BatteryInput, Battery.Breakdown>.load("battery-breakdown")
        for c in fixture.cases {
            let b = Battery.breakdown(c.input.inputs, hoursAwake: c.input.hoursAwakeArg)
            let e = c.expected
            expectClose(b.version, e.version, "version — \(c.name)")
            expectClose(b.hoursAwake, e.hoursAwake, "hoursAwake — \(c.name)")
            expectClose(b.charge.quality, e.charge.quality, "charge.quality — \(c.name)")
            expectClose(b.charge.morningCharge, e.charge.morningCharge, "charge.morningCharge — \(c.name)")
            expectClose(b.drains.time, e.drains.time, "drains.time — \(c.name)")
            expectClose(b.drains.activity, e.drains.activity, "drains.activity — \(c.name)")
            expectClose(b.drains.workout, e.drains.workout, "drains.workout — \(c.name)")
            expectClose(b.drains.load, e.drains.load, "drains.load — \(c.name)")
            expectClose(b.drains.wellness, e.drains.wellness, "drains.wellness — \(c.name)")
            expectClose(b.drains.total, e.drains.total, "drains.total — \(c.name)")
            expectClose(b.loadParts.acwrTerm, e.loadParts.acwrTerm, "loadParts.acwrTerm — \(c.name)")
            expectClose(b.wellnessParts.index, e.wellnessParts.index, "wellnessParts.index — \(c.name)")
            expectClose(b.currentPct, e.currentPct, "currentPct — \(c.name)")
        }
    }

    @Test("the raised-cosine time drain matches")
    func timeDrainMatches() throws {
        let fixture = try GoldenFixture<TimeDrainInput, Double>.load("time-drain")
        for c in fixture.cases {
            expectClose(
                Battery.timeDrain(hoursAwake: c.input.hoursAwake),
                c.expected,
                "timeDrain — \(c.name)"
            )
        }
    }

    @Test("workout drain matches across all 1,300+ exported combinations")
    func workoutDrainMatches() throws {
        let fixture = try GoldenFixture<WorkoutDrainInput, Double>.load("workout-drain")
        #expect(fixture.cases.count > 1000, "the grid collapsed — check the exporter")

        for c in fixture.cases {
            expectClose(
                Battery.workoutDrain(
                    sessionVolumeKg: c.input.sessionVolumeKg,
                    trailingAvgVolumeKg: c.input.trailingAvgVolumeKg,
                    sessionRpe: c.input.sessionRpe,
                    dayKey: c.input.dayKey,
                    maintenance: c.input.maintenance
                ),
                c.expected,
                "workoutDrain — \(c.name)"
            )
        }
    }

    @Test("the whole battery matches, including both paths into hoursAwake")
    func computeBatteryMatches() throws {
        let fixture = try GoldenFixture<BatteryInput, BatteryExpected>.load("battery")
        for c in fixture.cases {
            let state = Battery.computeBattery(c.input.inputs, hoursAwake: c.input.hoursAwakeArg)
            expectClose(state.morningCharge, c.expected.morningCharge, "morningCharge — \(c.name)")
            expectClose(state.currentPct, c.expected.currentPct, "currentPct — \(c.name)")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Readiness
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Readiness")
struct ReadinessGoldenTests {
    struct Input: Decodable {
        let sleepScore: Double?
        let recoveryScore: Double?
        let batteryPct: Double
    }

    @Test("level, label, colour and reason all match")
    func matchesGoldenVectors() throws {
        let fixture = try GoldenFixture<Input, ReadinessResult>.load("readiness")
        for c in fixture.cases {
            let actual = Readiness.compute(
                sleepScore: c.input.sleepScore,
                recoveryScore: c.input.recoveryScore,
                batteryPct: c.input.batteryPct
            )
            // Compared whole, not field by field: the colour and the sentence are
            // part of the contract. A port that got the level right and the
            // advice text wrong would still be telling the athlete the wrong thing.
            #expect(actual == c.expected, "computeReadiness — \(c.name)")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nutrition phase
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Nutrition phase")
struct NutritionPhaseGoldenTests {
    struct DeriveInput: Decodable { let calories: Double? }
    struct ResolveInput: Decodable {
        let calories: Double?
        let exception: String?
        let estimated: Bool?
        let activePhase: NutritionPhase?
        let stored: NutritionPhase?
    }

    @Test("the calorie bands match, boundary for boundary")
    func deriveMatches() throws {
        let fixture = try GoldenFixture<DeriveInput, NutritionPhase?>.load("nutrition-phase-derive")
        #expect(!fixture.cases.isEmpty)
        for c in fixture.cases {
            let actual = NutritionPhase.derive(calories: c.input.calories)
            #expect(actual == c.expected, "derivePhase — \(c.name)")
        }
    }

    @Test("a flagged day holds the phase it was eaten in")
    func resolveMatches() throws {
        let fixture = try GoldenFixture<ResolveInput, NutritionPhase?>.load("nutrition-phase-resolve")
        #expect(!fixture.cases.isEmpty)
        for c in fixture.cases {
            let actual = NutritionPhase.resolve(.init(
                calories: c.input.calories,
                exception: c.input.exception,
                estimated: c.input.estimated,
                activePhase: c.input.activePhase,
                stored: c.input.stored
            ))
            #expect(actual == c.expected, "resolveDayPhase — \(c.name)")
        }
    }

    @Test("the chip labels are the ones the web app draws")
    func labels() {
        // Not a golden vector: `phaseDisplay(phase, dateISO)` in the TypeScript
        // is a no-op wrapper — its one special case returns the same string
        // `PHASE_META` already holds — so there is nothing there to diff against.
        // These are pinned here so a rename of the enum cannot silently rename
        // the chip.
        #expect(NutritionPhase.cut.label == "Cut")
        #expect(NutritionPhase.maintenance.label == "Maint")
        #expect(NutritionPhase.bulk.label == "Bulk")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Exception day
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Exception day")
struct ExceptionDayGoldenTests {
    struct Input: Decodable { let stored: String? }
    struct Expected: Decodable, Equatable {
        let reason: String?
        let isException: Bool
        let tag: String
    }
    struct EstimatedInput: Decodable { let estimated: Bool? }

    @Test("the declaration, its tag and its truthiness all match")
    func matchesGoldenVectors() throws {
        let fixture = try GoldenFixture<Input, Expected>.load("exception-day")
        #expect(!fixture.cases.isEmpty)
        for c in fixture.cases {
            let actual = Expected(
                reason: ExceptionDay.reason(c.input.stored),
                isException: ExceptionDay.isException(c.input.stored),
                tag: ExceptionDay.tag(c.input.stored)
            )
            #expect(actual == c.expected, "exceptionDay — \(c.name)")
        }
    }

    @Test("estimated tags match")
    func estimatedMatches() throws {
        let fixture = try GoldenFixture<EstimatedInput, String>.load("estimated-tag")
        for c in fixture.cases {
            #expect(
                ExceptionDay.estimatedTag(c.input.estimated) == c.expected,
                "estimatedTag — \(c.name)"
            )
        }
    }
}
