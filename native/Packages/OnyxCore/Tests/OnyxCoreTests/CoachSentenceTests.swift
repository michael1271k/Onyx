import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// The Mega Widget's sentence — W7, A8.
//
// The point of a rule table is that every answer is written down somewhere a
// diff can see. `coach-sentence.json` is that place: one case per branch, plus
// the boundary of every cut the table reads, plus the precedence cases where
// two rules both match and only one may speak.
//
// It is hand-computed, like every other fixture here — there is no generator,
// and a spec you can regenerate from the code under test is not a spec
// (`GoldenVector.swift`).
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Coach sentence — the rule table")
struct CoachSentenceTests {

    @Test("every branch matches")
    func sentences() throws {
        let fixture = try GoldenFixture<CoachSentence.Inputs, String>.load("coach-sentence")
        for c in fixture.cases {
            #expect(CoachSentence.sentence(c.input) == c.expected, "\(c.name)")
        }
    }

    /// The fixture is only a spec if it covers the thing it claims to.
    @Test("the fixture names every branch the table can take")
    func everyBranchIsCovered() throws {
        let fixture = try GoldenFixture<CoachSentence.Inputs, String>.load("coach-sentence")
        let said = Set(fixture.cases.map(\.expected))
        // Eleven outcomes; the six that carry a number are matched by prefix,
        // because the number is part of what the cases above pin.
        let shapes = [
            "Nothing is known about today yet.",
            "Rest day needed.",
            "Hold the week where it is.",
            "Stress is overreached. Train light and sleep early.",
            "Bank an early night before anything heavy.",
            "Keep this week flat.",
            "Stress is high. Keep the session short and finish it.",
            "Train light today.",
            "is the only thing behind. Train as planned.",
            "and nothing is behind. Train hard.",
            "Nothing is flagged today.",
        ]
        for shape in shapes {
            #expect(said.contains { $0.contains(shape) }, "no fixture reaches \"\(shape)\"")
        }
    }

    /// Total, and never a string a tile would have to special-case.
    @Test("no input produces an empty sentence or one that is not a sentence")
    func totality() {
        let batteries: [Double?] = [nil, 0, 29.4, 30, 59.6, 60, 100]
        let acwrs: [Double?] = [nil, 0.4, 1.29, 1.3, 1.99, 2, 3.5]
        let debts: [Double?] = [nil, 0, 2, 2.1, 5, 5.1, 14]
        for b in batteries {
            for a in acwrs {
                for d in debts {
                    for s in [nil] + StressBand.allCases.map(Optional.some) {
                        let out = CoachSentence.sentence(
                            CoachSentence.Inputs(batteryPct: b, acwr: a, stress: s, sleepDebtHours: d)
                        )
                        #expect(!out.isEmpty)
                        #expect(out.hasSuffix("."))
                        // The one claim a widget face relies on: it fits.
                        #expect(out.count <= 80, "\"\(out)\" is \(out.count) characters")
                    }
                }
            }
        }
    }
}
