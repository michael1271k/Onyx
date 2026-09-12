import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Stress index v1 — the web app's `lib/scoring/stress.ts`, replayed from `npm run golden`.
// Every nil is compared as a nil: a number where the TypeScript answered "no
// reading" is the exact bug this suite exists to catch.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Stress index v1")
struct StressGoldenTests {
    struct Empty: Decodable {}
    struct BandConst: Decodable { let key: String; let label: String; let upTo: Double? }
    struct Weights: Decodable { let auto, sleep, load: Double; let selfReport: Double
        enum CodingKeys: String, CodingKey { case auto, sleep, load; case selfReport = "self" } }
    struct Constants: Decodable {
        let version, center, scale, min, max, fatigueNeutral: Double
        let weights: Weights
        let bands: [BandConst]
    }
    struct FragInput: Decodable { let awakeMin: [Double?]; let asleepMin: [Double?] }
    struct SeriesIn: Decodable { let days: [StressDayIn]; let endingOn: String; let limit: Int }
    struct IsolationIn: Decodable { let inputs: ScoringInputs; let stress: StressInputs }
    struct IsolationOut: Decodable { let battery: Battery.Breakdown; let maxTotalDrain: Double; let stressIndex: Double? }

    static func expectBreakdown(_ a: Stress.Breakdown, _ e: Stress.Breakdown, _ name: String) {
        expectClose(a.version, e.version, "version — \(name)")
        expectClose(a.terms.auto.z, e.terms.auto.z, "auto.z — \(name)")
        expectClose(a.terms.auto.hrv, e.terms.auto.hrv, "auto.hrv — \(name)")
        expectClose(a.terms.auto.rhr, e.terms.auto.rhr, "auto.rhr — \(name)")
        #expect(a.terms.auto.answered == e.terms.auto.answered, "auto.answered — \(name)")
        expectClose(a.terms.sleep.z, e.terms.sleep.z, "sleep.z — \(name)")
        expectClose(a.terms.sleep.frag, e.terms.sleep.frag, "sleep.frag — \(name)")
        expectClose(a.terms.sleep.onset, e.terms.sleep.onset, "sleep.onset — \(name)")
        #expect(a.terms.sleep.answered == e.terms.sleep.answered, "sleep.answered — \(name)")
        expectClose(a.terms.selfReport.z, e.terms.selfReport.z, "self.z — \(name)")
        expectClose(a.terms.selfReport.fatigueDayMean, e.terms.selfReport.fatigueDayMean, "self.fatigueDayMean — \(name)")
        expectClose(a.terms.selfReport.stressDayMean, e.terms.selfReport.stressDayMean, "self.stressDayMean — \(name)")
        #expect(a.terms.selfReport.answered == e.terms.selfReport.answered, "self.answered — \(name)")
        expectClose(a.terms.load.z, e.terms.load.z, "load.z — \(name)")
        expectClose(a.terms.load.acwrTerm, e.terms.load.acwrTerm, "load.acwrTerm — \(name)")
        expectClose(a.terms.load.strainTerm, e.terms.load.strainTerm, "load.strainTerm — \(name)")
        #expect(a.terms.load.answered == e.terms.load.answered, "load.answered — \(name)")
        expectClose(a.weightSum, e.weightSum, "weightSum — \(name)")
        expectClose(a.composite, e.composite, "composite — \(name)")
        expectClose(a.index, e.index, "index — \(name)")
        #expect(a.band == e.band, "band — \(name)")
    }

    @Test("every constant survived the translation")
    func constantsMatch() throws {
        let e = try #require(try GoldenFixture<Empty, Constants>.load("stress-constants").cases.first).expected
        let c = Stress.constants
        expectClose(c.version, e.version, "version")
        expectClose(c.center, e.center, "center")
        expectClose(c.scale, e.scale, "scale")
        expectClose(c.min, e.min, "min")
        expectClose(c.max, e.max, "max")
        expectClose(c.fatigueNeutral, e.fatigueNeutral, "fatigueNeutral")
        expectClose(c.weights.auto, e.weights.auto, "w.auto")
        expectClose(c.weights.sleep, e.weights.sleep, "w.sleep")
        expectClose(c.weights.selfReport, e.weights.selfReport, "w.self")
        expectClose(c.weights.load, e.weights.load, "w.load")
        #expect(c.bands.count == e.bands.count)
        for (a, b) in zip(c.bands, e.bands) {
            #expect(a.key.rawValue == b.key && a.label == b.label, "band \(b.key)")
            expectClose(a.upTo, b.upTo, "band \(b.key) upTo")
        }
    }

    @Test("the breakdown matches, every term of it — one case per band, the floor, every missing shape")
    func breakdownMatches() throws {
        let fixture = try GoldenFixture<StressInputs, Stress.Breakdown>.load("stress-breakdown")
        #expect(fixture.cases.count >= 25)
        var bands = Set<StressBand>()
        for c in fixture.cases {
            let got = Stress.breakdown(c.input)
            Self.expectBreakdown(got, c.expected, c.name)
            if let b = got.band { bands.insert(b) }
        }
        #expect(bands == Set(StressBand.allCases), "every band is reached from real inputs")
    }

    @Test("the fragmentation z matches — ratios through the readiness z-signal, holes kept")
    func fragmentationMatches() throws {
        let fixture = try GoldenFixture<FragInput, ZSignal>.load("stress-fragmentation")
        for c in fixture.cases {
            let got = Stress.fragmentationZ(awakeMin: c.input.awakeMin, asleepMin: c.input.asleepMin)
            ReadinessV9GoldenTests.expectZ(got, c.expected, c.name)
        }
    }

    @Test("the series matches, holes and rounding included")
    func seriesMatches() throws {
        let fixture = try GoldenFixture<SeriesIn, [StressDay]>.load("stress-series")
        #expect(fixture.cases.count >= 7)
        for c in fixture.cases {
            let got = StressSeries.build(c.input.days, endingOn: c.input.endingOn, limit: c.input.limit)
            #expect(got.count == c.expected.count, "count — \(c.name)")
            for (a, e) in zip(got, c.expected) {
                #expect(a.d == e.d && a.empty == e.empty && a.band == e.band, "\(c.name) — \(e.d)")
                expectClose(a.index, e.index, "index — \(c.name) \(e.d)")
                for key in StressTermKey.allCases {
                    expectClose(a.term(key), e.term(key), "\(key.rawValue) — \(c.name) \(e.d)")
                }
            }
        }
    }

    @Test("the battery is not listening: the same inputs, the same breakdown, whatever the index is handed")
    func batteryIsolated() throws {
        let fixture = try GoldenFixture<IsolationIn, IsolationOut>.load("stress-battery-isolation")
        #expect(fixture.cases.count >= 25)
        let first = try #require(fixture.cases.first)
        let reference = Battery.breakdown(first.input.inputs)
        for c in fixture.cases {
            _ = Stress.breakdown(c.input.stress)
            let b = Battery.breakdown(c.input.inputs)
            #expect(b == reference, "battery moved — \(c.name)")
            expectClose(b.currentPct, c.expected.battery.currentPct, "currentPct — \(c.name)")
            expectClose(b.drains.total, c.expected.battery.drains.total, "drains.total — \(c.name)")
            expectClose(Battery.maxTotalDrain, c.expected.maxTotalDrain, "maxTotalDrain — \(c.name)")
            expectClose(Stress.index(c.input.stress), c.expected.stressIndex, "stressIndex — \(c.name)")
        }
    }
}
