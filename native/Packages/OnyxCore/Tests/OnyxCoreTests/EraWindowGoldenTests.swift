import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// The six chart windows — replayed from `npm run golden` (W11).
//
// The phase labels go through `rebranded` for the reason `NutritionGoldenTests`
// states: the fixtures come from the web app's `lib/phases.ts`, which keeps the web's own
// era tags on purpose (decision 2). Every other character is compared as-is.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Era windows — the six pills and what they resolve to")
struct EraWindowGoldenTests {

    struct ResolveIn: Decodable { let mode: EraWindow; let input: EraWindowInput }
    struct ResolveOut: Decodable {
        let label: String
        let startISO: String
        let endISO: String
        let days: Int
        let era: String
    }

    @Test("resolveEraWindow matches on every mode, phase boundary and lever run")
    func resolveMatches() throws {
        let fixture = try GoldenFixture<ResolveIn, ResolveOut>.load("era-window")
        #expect(fixture.cases.count >= 40)
        for c in fixture.cases {
            // The vector predates the table fields; the founder's rows go in.
            var input = c.input.input
            input.phases = FounderTables.phases
            input.rungs = FounderTables.rungs
            input.periods = FounderTables.periods
            input.planStartISO = FounderTables.planStartISO
            let actual = c.input.mode.resolve(input)
            #expect(actual.label == rebranded(c.expected.label), "label — \(c.name)")
            #expect(actual.startISO == c.expected.startISO, "start — \(c.name)")
            #expect(actual.endISO == c.expected.endISO, "end — \(c.name)")
            #expect(actual.days == c.expected.days, "days — \(c.name)")
            #expect(actual.era(cutStartISO: FounderTables.planStartISO) == c.expected.era, "era — \(c.name)")
        }
    }

    struct KeyIn: Decodable { let key: String }

    @Test("a stored key that no longer names a mode reads as nil")
    func keysMatch() throws {
        for c in try GoldenFixture<KeyIn, EraWindow?>.load("era-window-keys").cases {
            #expect(EraWindow.fromKey(c.input.key) == c.expected, "fromKey — \(c.name)")
        }
    }

    struct DaysIn: Decodable { let from: String; let to: String }

    @Test("the day count is inclusive and never below one")
    func dayCountMatches() throws {
        for c in try GoldenFixture<DaysIn, Int>.load("era-window-days").cases {
            #expect(EraWindow.dayCount(from: c.input.from, to: c.input.to) == c.expected, "dayCount — \(c.name)")
        }
    }

    // MARK: - Invariants the fixtures cannot state

    @Test("every mode round-trips through its key")
    func keysRoundTrip() {
        // `keyed`, not `modes`: W3's two windows are offered by the muscle atlas
        // card rather than by the screen picker, and a key that serialises but
        // reads back nil is a preference that silently reverts to the default.
        for mode in EraWindow.keyed {
            #expect(EraWindow.fromKey(mode.key) == mode, "\(mode.key)")
        }
        #expect(EraWindow.keyed.contains(.thisWeek) && EraWindow.keyed.contains(.currentProgram))
        #expect(EraWindow.modes.contains(EraWindow.default))
    }

    /// A key that serializes but will not read back is a stored preference that
    /// silently reverts. `.days(0)` is not a window anyone picks, but it is a
    /// window the type can hold, and its key has to name the one it draws.
    @Test("a non-positive span keys as the window it actually draws")
    func degenerateSpansRoundTrip() {
        let input = EraWindowInput(today: "2026-09-06", planLabel: "Onyx-5")
        for n in [-30, -1, 0, 1, 2] {
            let mode = EraWindow.days(n)
            let read = EraWindow.fromKey(mode.key)
            #expect(read != nil, "days:\(n) must read back")
            #expect(read?.resolve(input) == mode.resolve(input), "days:\(n) resolves the same either way")
        }
    }

    /// A window that ended before it started would draw a negative axis, and a
    /// window whose `days` disagreed with its own bounds would caption itself
    /// wrongly. Both are cheap to make true and expensive to notice.
    @Test("no window runs backwards, and days always equals its own span")
    func windowsAreWellFormed() {
        let input = EraWindowInput(
            today: "2026-09-06", planLabel: "Onyx-5", storedLever: "lever-1",
            releaseEndsOn: nil, firstDataISO: "2026-03-08", planStartISO: FounderTables.planStartISO,
            phases: FounderTables.phases, rungs: FounderTables.rungs, periods: FounderTables.periods
        )
        for day in stride(from: -400, through: 30, by: 13) {
            guard let today = ISODate.addDays(input.today, day) else { continue }
            var walked = input
            walked.today = today
            for mode in EraWindow.modes + [.days(1), .days(0), .days(-4)] {
                let w = mode.resolve(walked)
                #expect(w.startISO <= w.endISO, "\(mode.key) on \(today)")
                #expect(w.endISO == today, "\(mode.key) ends today on \(today)")
                #expect(w.days == EraWindow.dayCount(from: w.startISO, to: w.endISO), "\(mode.key) on \(today)")
                #expect(!w.label.isEmpty, "\(mode.key) on \(today)")
                #expect(w.contains(today) && w.contains(w.startISO), "\(mode.key) on \(today)")
            }
        }
    }
}
