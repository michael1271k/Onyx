import Foundation
import Testing

/// The replay harness for the golden vectors — `Fixtures/*.json`, one file per
/// domain function, `{ input, expected }` pairs the Swift must reproduce.
///
/// ── WHAT THIS IS FOR ─────────────────────────────────────────────────────────
/// The domain arithmetic here breaks SILENTLY: a formula that is 3 % wrong
/// renders a number nobody questions. The fixtures are the written
/// specification of every number the domain has ever been caught getting
/// wrong, plus the grids around them, and `swift test` replays every case.
///
/// ── SWIFT-OWNED SINCE W1 OF THE EPIC SPRINT (2026-09-10) ────────────────────
/// They were exported from the shipping TypeScript by
/// the web app's `tests/golden-vectors.test.ts` (`npm run golden`), which was the right
/// oracle while the two implementations had to agree. From W2 the Swift
/// domain deliberately diverges (founder constants become rows, the `+`
/// quality grammar, the logged-beats-planned fold), so the TypeScript is no
/// longer a definition of correct and the generator is gone with the script.
///
/// The fixtures are now frozen test resources, and the rule for changing one
/// is the rule for changing any test: a NEW case is hand-computed, written
/// into the JSON with a `note` naming the wave that added it, and reviewed by
/// `invariant-auditor` like any other formula change. Regenerating is not an
/// option any more, which is the point — a spec you can regenerate from the
/// code under test is not a spec.
struct GoldenFixture<Input: Decodable, Expected: Decodable>: Decodable {
    struct Case: Decodable {
        let name: String
        let input: Input
        let expected: Expected
    }

    let module: String
    let fn: String
    let note: String
    let cases: [Case]

    /// Load `Fixtures/<name>.json` from the test bundle.
    static func load(_ name: String) throws -> GoldenFixture {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ) else {
            throw GoldenError.missing(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GoldenFixture.self, from: data)
    }
}

enum GoldenError: Error, CustomStringConvertible {
    case missing(String)

    var description: String {
        switch self {
        case .missing(let name):
            return """
            Fixture "\(name).json" is not in the test bundle. The fixtures are \
            checked-in Swift test resources under Tests/OnyxCoreTests/Fixtures — \
            add the file there (hand-computed cases; there is no generator).
            """
        }
    }
}

// MARK: - Comparison

/// Tolerance for a `Double` that both languages computed.
///
/// JavaScript numbers and Swift `Double` are both IEEE-754 binary64, and the
/// same sequence of `+ - * /` and `cos` on the same values agrees bit for bit —
/// so in practice these comparisons are exact. The tolerance exists only so a
/// future refactor that reassociates an expression (mathematically identical,
/// last-bit different) reports as a pass rather than a spurious failure. It is
/// deliberately far too tight to hide a real formula difference: the smallest
/// bug this domain has ever shipped was a percent, not a quadrillionth.
private let relativeTolerance = 1e-12

/// Assert two optional doubles agree, treating nil as a first-class value.
///
/// `nil` vs `0` is the distinction three separate bugs in this codebase turned
/// on — the unloaded-work e1RM, the all-or-nothing TDEE, the absent session RPE
/// — so a nil that should be a number, or a number that should be nil, must
/// fail loudly here rather than compare "close enough".
func expectClose(
    _ actual: Double?,
    _ expected: Double?,
    _ label: @autoclosure () -> String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    switch (actual, expected) {
    case (nil, nil):
        return
    case (let a?, let e?):
        if a == e { return }
        let scale = Swift.max(Swift.abs(a), Swift.abs(e), 1)
        let diff = Swift.abs(a - e)
        #expect(
            diff <= relativeTolerance * scale,
            "\(label()) — Swift \(a) vs TypeScript \(e) (diff \(diff))",
            sourceLocation: sourceLocation
        )
    case (let a?, nil):
        let message = """
            \(label()) — Swift returned \(a) where TypeScript returned null. \
            A number standing in for "no answer" is the bug this suite exists to catch.
            """
        Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
    case (nil, let e?):
        let message = "\(label()) — Swift returned nil where TypeScript returned \(e)."
        Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
    }
}

/// Non-optional convenience.
func expectClose(
    _ actual: Double,
    _ expected: Double,
    _ label: @autoclosure () -> String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    expectClose(Optional(actual), Optional(expected), label(), sourceLocation: sourceLocation)
}
