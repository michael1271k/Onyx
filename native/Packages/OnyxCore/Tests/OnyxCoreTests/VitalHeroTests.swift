import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// The hero slot on Pulse (W2 of the next-gen UX sprint).
//
// Two suites, because there are two claims and only one of them is arithmetic:
// the RULE (`promote`) is replayed from `vital-hero.json`, and the GRAMMAR
// (`reading`) is asserted against `Readiness.zSignal` directly — the point of
// that half being that this file computes no z of its own.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Vital hero — the promotion rule")
struct VitalHeroGoldenTests {
    struct Input: Decodable {
        let readings: [VitalReading]
        let sleep: VitalReading?
    }
    struct Expected: Decodable { let hero: String }

    /// The fixture writes `.sleep` as "Sleep" and `.vital(id)` as the id.
    static func name(_ slot: HeroSlot) -> String {
        switch slot {
        case .sleep: "Sleep"
        case .vital(let id): id
        }
    }

    @Test("every case in the fixture")
    func replay() throws {
        let fixture = try GoldenFixture<Input, Expected>.load("vital-hero")
        #expect(fixture.cases.count >= 14)
        for c in fixture.cases {
            let got = VitalHero.promote(c.input.readings, sleep: c.input.sleep)
            #expect(Self.name(got) == c.expected.hero, "\(c.name) — got \(Self.name(got))")
        }
    }

    /// The invariant the fixture states case by case and never in general: the
    /// answer is one of the readings that were handed in, or the night. A rule
    /// that could name a vital not on the screen would promote a cell the grid
    /// has no room to give up.
    @Test("the answer is always a reading that was offered")
    func closedOverItsInput() throws {
        let fixture = try GoldenFixture<Input, Expected>.load("vital-hero")
        for c in fixture.cases {
            switch VitalHero.promote(c.input.readings, sleep: c.input.sleep) {
            case .sleep: continue
            case .vital(let id):
                #expect(c.input.readings.contains { $0.id == id }, "\(c.name) — promoted an absent id")
            }
        }
    }

    /// Order-independence of the VERDICT, not of the tie-break: reversing the
    /// input may change which of two EQUAL alarms wins, and must never change
    /// whether a vital is promoted at all.
    @Test("reversing the input never changes whether the night is beaten")
    func reversalKeepsTheVerdict() throws {
        let fixture = try GoldenFixture<Input, Expected>.load("vital-hero")
        for c in fixture.cases {
            let forward = VitalHero.promote(c.input.readings, sleep: c.input.sleep)
            let backward = VitalHero.promote(c.input.readings.reversed(), sleep: c.input.sleep)
            #expect((forward == .sleep) == (backward == .sleep), "\(c.name) — the verdict moved with the order")
        }
    }
}

@Suite("Vital hero — the zSignal grammar, borrowed whole")
struct VitalHeroSignalTests {
    /// 49 values: 42 of baseline and a 7-day roll, oldest → newest.
    static func series(baseline: Double, rolling: Double, jitter: Double = 1) -> [Double?] {
        var out: [Double?] = []
        let days = Readiness.constants.historyDays - Readiness.constants.rollingDays
        for i in 0..<days { out.append(baseline + (i % 2 == 0 ? jitter : -jitter)) }
        for _ in 0..<Readiness.constants.rollingDays { out.append(rolling) }
        return out
    }

    @Test("reading() is zSignal and nothing else")
    func borrowsTheGrammar() {
        let values = Self.series(baseline: 50, rolling: 42)
        let reading = VitalHero.reading(id: "HRV", upIsGood: true, log: true, series: values)
        expectClose(reading.z, Readiness.zSignal(values, log: true).z, "HRV z")
        #expect(reading.id == "HRV")
        #expect(reading.upIsGood)
    }

    @Test("a series with no baseline behind it has no z, and is never promoted")
    func thinHistoryIsNeverPromoted() {
        // Eight readings: one short rolling window and a baseline of one, which
        // is under `minBaseline` (14). A brand-new phone, four days in.
        let thin: [Double?] = Array(repeating: 40, count: 8)
        let reading = VitalHero.reading(id: "HRV", upIsGood: true, log: true, series: thin)
        #expect(reading.z == nil)
        #expect(VitalHero.promote([reading], sleep: nil) == .sleep)
    }

    /// ── AND WHY THIS ONE IS THE RAW SERIES, NOT THE ln ─────────────────────
    /// `sampleSd` of 42 IDENTICAL values is exactly zero only while the sum is
    /// exact. `50` repeated adds exactly; `ln(50)` repeated does not, and the
    /// last-bit residue leaves an SD around 1e-16 — which `zSignal`'s `sd > 0`
    /// guard passes, and every delta then clamps to ±2. That is a property of
    /// the existing signal, not of this rule, and it is unreachable with real
    /// sensor data (42 nights of HRV agreeing to the last decimal). It is
    /// asserted here on the path where a flat baseline IS exactly flat, which
    /// is the shape a fresh store actually produces.
    @Test("a flat baseline has no z either — a zero SD is not a small one")
    func flatBaselineIsNeverPromoted() {
        let flat: [Double?] = Array(repeating: 50, count: Readiness.constants.historyDays - 7)
            + Array(repeating: 62, count: 7)
        let reading = VitalHero.reading(id: "Resting HR", upIsGood: false, series: flat)
        #expect(reading.z == nil)
        #expect(VitalHero.promote([reading], sleep: nil) == .sleep)
    }

    /// The dead band, end to end: a move smaller than the smallest worthwhile
    /// change reads as zero, and zero never crosses the alarm.
    @Test("a move inside the SWC band cannot promote")
    func deadBandHolds() {
        // Baseline 50 ± 1 → SD ≈ 1.01, SWC ≈ 0.5. A roll at 50.3 is inside it.
        let values = Self.series(baseline: 50, rolling: 50.3)
        let reading = VitalHero.reading(id: "Resting HR", upIsGood: false, series: values)
        #expect(reading.z == 0)
        #expect(VitalHero.promote([reading], sleep: nil) == .sleep)
    }

    /// And the other side of it: a real collapse clamps at 2 and takes the slot
    /// off a night that has nothing to say.
    @Test("a real excursion clears the band and beats a silent night")
    func excursionPromotes() {
        let values = Self.series(baseline: 50, rolling: 38)
        let reading = VitalHero.reading(id: "HRV", upIsGood: true, log: true, series: values)
        #expect((reading.z ?? 0) <= -VitalHero.alarmZ)
        #expect(reading.z == -Readiness.constants.zClamp)
        #expect(VitalHero.promote([reading], sleep: nil) == .vital("HRV"))
    }
}
