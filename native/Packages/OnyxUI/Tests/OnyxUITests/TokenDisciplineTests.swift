import Foundation
import Testing

/// The one rule that cannot be enforced by the type system: no raw colour.
///
/// ── WHY A FILE WALK AND NOT A LINT CONFIG ───────────────────────────────────
/// Every `Color.onyx.*` read resolves through `OnyxTheme.current`, so a theme
/// swap repaints the app — except wherever someone wrote the hex by hand. Such
/// a line does not fail to compile, does not fail a snapshot (the default spec
/// renders it identically) and only shows up as the one tile that stayed blue
/// after the user picked Obsidian. The cheapest place to catch it is the text.
///
/// The test walks `native/` from `#filePath` so it needs no build setting and
/// no path in `project.yml`, and it runs in the OnyxUI suite because that is
/// the module that owns the tokens.
@Suite("Token discipline")
struct TokenDisciplineTests {

    /// Writing a colour by hand is legal in exactly these files.
    ///
    /// `OnyxTokens.swift` holds the default palette and `OnyxTheme.swift` the
    /// derivation that rotates it — they ARE the hex literals. `OnyxAtlas.swift`
    /// is generated. `OnyxThemeTests.swift` asserts that the derivation under
    /// the default spec reproduces each default literal bit for bit, which it
    /// can only do by naming them.
    static let allowed: Set<String> = [
        "OnyxTokens.swift",
        "OnyxTheme.swift",
        "OnyxAtlas.swift",
        "OnyxThemeTests.swift",
        "TokenDisciplineTests.swift",  // this file: the patterns below are its data
    ]

    /// Spellings of a raw colour. `Color(.sRGB` covers the labelled
    /// `Color(.sRGB, red:…)` initialiser as well as `.sRGBLinear`.
    static let banned = ["Color(hex:", "Color(red:", "Color(.sRGB", "UIColor(", "#colorLiteral"]

    @Test("no raw colour outside the token files")
    func noRawColour() throws {
        var native = URL(fileURLWithPath: #filePath)
        // …/native/Packages/OnyxUI/Tests/OnyxUITests/TokenDisciplineTests.swift
        for _ in 0..<5 { native.deleteLastPathComponent() }
        #expect(FileManager.default.fileExists(atPath: native.appendingPathComponent("project.yml").path),
                "expected \(native.path) to be the repo's native/ directory")

        var violations: [String] = []
        let walk = FileManager.default.enumerator(at: native, includingPropertiesForKeys: nil)
        while let url = walk?.nextObject() as? URL {
            let name = url.lastPathComponent
            // Build products and the generated project carry copies of everything.
            if name == ".build" || name == "Onyx.xcodeproj" { walk?.skipDescendants(); continue }
            guard url.pathExtension == "swift", !Self.allowed.contains(name) else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                for pattern in Self.banned {
                    guard let hit = line.range(of: pattern) else { continue }
                    // A `//` before the match makes the line prose, not code.
                    // (A banned spelling inside a string literal on a code line
                    // is rare enough to be worth the false positive.)
                    if let comment = line.range(of: "//"), comment.lowerBound < hit.lowerBound { continue }
                    let path = url.path.replacingOccurrences(of: native.path + "/", with: "native/")
                    violations.append("\(path):\(index + 1): \(pattern) — use a Color.onyx.* token")
                }
            }
        }

        #expect(violations.isEmpty, "raw colour outside the token files:\n\(violations.joined(separator: "\n"))")
    }
}
