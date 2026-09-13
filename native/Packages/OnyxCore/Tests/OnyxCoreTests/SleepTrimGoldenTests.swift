import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Sleep trim — strategy B, the web app's `lib/sleep/trim.ts`, replayed from `npm run golden`.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Sleep trim — strategy B")
struct SleepTrimGoldenTests {
    struct StagesInput: Decodable { let stages: NightStages; let oldSpanMin: Double; let newSpanMin: Double }
    struct NightInput: Decodable { let row: StoredNight; let edit: NightWindowEdit }

    static func expectNight(_ a: TrimmedNight, _ e: TrimmedNight, _ name: String) {
        expectClose(a.asleepMin, e.asleepMin, "asleepMin — \(name)")
        expectClose(a.deepMin, e.deepMin, "deepMin — \(name)")
        expectClose(a.remMin, e.remMin, "remMin — \(name)")
        expectClose(a.coreMin, e.coreMin, "coreMin — \(name)")
        expectClose(a.awakeMin, e.awakeMin, "awakeMin — \(name)")
        expectClose(a.cutMin, e.cutMin, "cutMin — \(name)")
        expectClose(a.addedMin, e.addedMin, "addedMin — \(name)")
        #expect(a.durationOnly == e.durationOnly, "durationOnly — \(name)")
    }

    @Test("minute counts match — awake first, proportion after, core on an extension")
    func stagesMatch() throws {
        let fixture = try GoldenFixture<StagesInput, TrimmedNight>.load("sleep-trim")
        #expect(fixture.cases.count >= 15)
        for c in fixture.cases {
            let got = SleepTrim.trimStages(c.input.stages, oldSpanMin: c.input.oldSpanMin, newSpanMin: c.input.newSpanMin)
            Self.expectNight(got, c.expected, c.name)
            // The invariant the vector does not spell out: the stages always sum.
            #expect(got.deepMin + got.remMin + got.coreMin == got.asleepMin, "stages sum — \(c.name)")
            #expect(got.deepMin >= 0 && got.remMin >= 0 && got.coreMin >= 0 && got.awakeMin >= 0, "no negative stage — \(c.name)")
        }
    }

    @Test("stored rows and edits match, ISO instants included")
    func nightsMatch() throws {
        let fixture = try GoldenFixture<NightInput, TrimmedNight>.load("sleep-trim-night")
        #expect(fixture.cases.count >= 6)
        for c in fixture.cases {
            Self.expectNight(SleepTrim.trimNight(c.input.row, edit: c.input.edit), c.expected, c.name)
        }
    }
}
