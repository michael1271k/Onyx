import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Regenerating `weekly-export.json`.
//
// The fixture holds eight whole documents, byte for byte. Any wave that changes
// the document has to restate all eight, and hand-editing eight embedded
// markdown blobs inside a 9,000-line JSON file is how a golden quietly stops
// being a record of anything. So the rebuild is a test, run on demand:
//
//     ONYX_REGOLD=/tmp/weekly-export.json swift test --filter regold
//
// It rewrites ONLY `expected.markdown`, leaving every other expectation in the
// file untouched — `summary`, `totals`, `energy` and `derived` are separate
// claims about the same input and a renderer change must not silently restate
// them. Without the variable it does nothing at all, which is why it can live
// in the suite rather than in a script nobody runs.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Weekly export — regold")
struct WeeklyExportRegold {

    @Test("rewrites the fixture's documents when asked, and otherwise does nothing")
    func regold() throws {
        guard let out = ProcessInfo.processInfo.environment["ONYX_REGOLD"], !out.isEmpty else { return }
        guard let url = Bundle.module.url(forResource: "weekly-export", withExtension: "json", subdirectory: "Fixtures")
        else { throw GoldenError.missing("weekly-export") }

        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var cases = root["cases"] as! [[String: Any]]
        let decoder = JSONDecoder()

        for i in cases.indices {
            let input = try decoder.decode(
                WeeklyExportInput.self,
                from: try JSONSerialization.data(withJSONObject: cases[i]["input"]!))
            var expected = cases[i]["expected"] as! [String: Any]
            expected["markdown"] = WeeklyExport.build(input)
            cases[i]["expected"] = expected
        }
        root["cases"] = cases

        let data = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: URL(fileURLWithPath: out))
    }
}
