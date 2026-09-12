import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Readiness v9 — the web app's `lib/scoring/readiness.ts`, replayed from `npm run golden`.
//
// The z-signal, the sRPE load, the EWMA ratio, Foster's monotony and strain,
// and the composite. Every nil is compared as a nil: a number where the
// TypeScript answered "no opinion" is the exact bug this suite exists to catch.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Readiness v9 — the signals")
struct ReadinessV9GoldenTests {
    struct ZInput: Decodable { let values: [Double?]; let log: Bool }
    struct SessionInput: Decodable { let sessionRpe: Double?; let durationMin: Double? }
    struct CardioInput: Decodable { let effort: Double?; let durationMin: Double? }
    struct DailyInput: Decodable { let dates: [String]; let sessions: [LoadSession]; let cardio: [LoadCardio] }
    struct LoadsInput: Decodable { let loads: [Double] }
    struct Empty: Decodable {}
    struct Constants: Decodable {
        let rollingDays, baselineDays, historyDays, minRolling, minBaseline, monotonyDays, minStrainHistory, minLoadDays: Int
        let swcFactor, zClamp, acuteLambda, chronicLambda, defaultSessionRpe, acwrOnset, acwrSaturation, acwrShare: Double
    }

    static func expectZ(_ a: ZSignal, _ e: ZSignal, _ name: String) {
        expectClose(a.rolling, e.rolling, "rolling — \(name)")
        expectClose(a.baselineMean, e.baselineMean, "baselineMean — \(name)")
        expectClose(a.baselineSd, e.baselineSd, "baselineSd — \(name)")
        expectClose(a.swc, e.swc, "swc — \(name)")
        expectClose(a.delta, e.delta, "delta — \(name)")
        expectClose(a.z, e.z, "z — \(name)")
        #expect(a.n == e.n, "n — \(name)")
    }

    static func expectLoad(_ a: LoadSignal, _ e: LoadSignal, _ name: String) {
        expectClose(a.today, e.today, "today — \(name)")
        expectClose(a.acute, e.acute, "acute — \(name)")
        expectClose(a.chronic, e.chronic, "chronic — \(name)")
        expectClose(a.acwr, e.acwr, "acwr — \(name)")
        expectClose(a.weeklyLoad, e.weeklyLoad, "weeklyLoad — \(name)")
        expectClose(a.monotony, e.monotony, "monotony — \(name)")
        expectClose(a.strain, e.strain, "strain — \(name)")
        expectClose(a.strainZ, e.strainZ, "strainZ — \(name)")
    }

    @Test("every constant survived the translation")
    func constantsMatch() throws {
        let e = try #require(try GoldenFixture<Empty, Constants>.load("readiness-constants").cases.first).expected
        let c = Readiness.constants
        #expect(c.rollingDays == e.rollingDays && c.baselineDays == e.baselineDays && c.historyDays == e.historyDays)
        #expect(c.minRolling == e.minRolling && c.minBaseline == e.minBaseline)
        #expect(c.monotonyDays == e.monotonyDays && c.minStrainHistory == e.minStrainHistory && c.minLoadDays == e.minLoadDays)
        expectClose(c.swcFactor, e.swcFactor, "swcFactor")
        expectClose(c.zClamp, e.zClamp, "zClamp")
        expectClose(c.acuteLambda, e.acuteLambda, "acuteLambda")
        expectClose(c.chronicLambda, e.chronicLambda, "chronicLambda")
        expectClose(c.defaultSessionRpe, e.defaultSessionRpe, "defaultSessionRpe")
        expectClose(c.acwrOnset, e.acwrOnset, "acwrOnset")
        expectClose(c.acwrSaturation, e.acwrSaturation, "acwrSaturation")
        expectClose(c.acwrShare, e.acwrShare, "acwrShare")
    }

    @Test("the z-signal matches — thin windows, the SWC gate, both clamps, the log")
    func zMatches() throws {
        let fixture = try GoldenFixture<ZInput, ZSignal>.load("readiness-z")
        #expect(fixture.cases.count >= 20)
        for c in fixture.cases {
            Self.expectZ(Readiness.zSignal(c.input.values, log: c.input.log), c.expected, c.name)
        }
    }

    @Test("session and cardio loads match, including the unrated fallbacks")
    func loadsMatch() throws {
        for c in try GoldenFixture<SessionInput, Double>.load("readiness-session-load").cases {
            expectClose(Readiness.sessionLoad(LoadSession(sessionRpe: c.input.sessionRpe, durationMin: c.input.durationMin)), c.expected, "sessionLoad — \(c.name)")
        }
        for c in try GoldenFixture<CardioInput, Double>.load("readiness-cardio-load").cases {
            expectClose(Readiness.cardioLoad(LoadCardio(effort: c.input.effort, durationMin: c.input.durationMin)), c.expected, "cardioLoad — \(c.name)")
        }
        for c in try GoldenFixture<DailyInput, [Double]>.load("readiness-daily-loads").cases {
            let got = Readiness.dailyLoads(dates: c.input.dates, sessions: c.input.sessions, cardio: c.input.cardio)
            #expect(got.count == c.expected.count, "dailyLoads count — \(c.name)")
            for (a, e) in zip(got, c.expected) { expectClose(a, e, "dailyLoads — \(c.name)") }
        }
    }

    @Test("the load signal matches — EWMA, monotony, strain and its z")
    func loadSignalMatches() throws {
        let fixture = try GoldenFixture<LoadsInput, LoadSignal>.load("readiness-load")
        #expect(fixture.cases.count >= 15)
        for c in fixture.cases {
            Self.expectLoad(Readiness.loadSignal(c.input.loads), c.expected, c.name)
        }
    }

    @Test("the composite matches through one door")
    func signalsMatch() throws {
        for c in try GoldenFixture<ReadinessHistory, ReadinessSignals>.load("readiness-signals").cases {
            let got = Readiness.signals(c.input)
            Self.expectZ(got.hrv, c.expected.hrv, "hrv — \(c.name)")
            Self.expectZ(got.rhr, c.expected.rhr, "rhr — \(c.name)")
            Self.expectLoad(got.load, c.expected.load, "load — \(c.name)")
        }
    }
}
