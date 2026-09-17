import Foundation
import Testing

/// The other rule the type system cannot enforce: every screen stands on the
/// app's ground.
///
/// ── WHY A SECOND FILE WALK ──────────────────────────────────────────────────
/// `TokenDisciplineTests` catches a screen that spells a colour. It cannot
/// catch a screen that names no colour at all — one that simply never applied
/// `.onyxScreen(_:)` and so draws on whatever SwiftUI's default background is.
/// That failure is invisible in every way the other one is: it compiles, it
/// renders, and under the default theme a flat dark screen beside a meshed one
/// reads as a design choice rather than as an omission. It only announces
/// itself when the user picks Obsidian and one screen out of thirty stays grey.
///
/// The ground is also where the domain tint reaches the screen — the mesh
/// bleed behind the title is `domain.start`/`domain.end` — so a screen with no
/// ground is a screen with no domain, which is the same coverage hole W8
/// closed in the tab bar.
///
/// Same shape as its sibling: walk `native/` from `#filePath`, no build
/// setting, no path in `project.yml`, and it runs in the OnyxUI suite because
/// OnyxUI owns `onyxScreen`.
@Suite("Appearance coverage")
struct AppearanceCoverageTests {

    /// A screen stands on the ground if it applies one of these.
    ///
    /// `DaySheet` is the third because it is not a screen — it is the shared
    /// presented-sheet chrome (`PulseTabView`), and it applies `.onyxScreen` or
    /// `.onyxFormBackground` itself depending on whether its content is a
    /// `Form`. Seven of this app's sheets ground through it, and requiring them
    /// to ALSO apply a ground would be asking for the bug: two meshes stacked,
    /// the inner one over the outer one's bleed.
    static let grounds = [".onyxScreen", ".onyxFormBackground", "DaySheet("]

    /// Types that look like a root screen and are not, each with the reason.
    ///
    /// The reason is the point of the allowlist. Skipping the ground is a
    /// legitimate decision — a card is not a screen — but it is a decision, and
    /// before this test it was one nobody had to write down.
    static let allowed: [String: String] = [
        "RootView":
            """
            The shell, not a screen. It is a `TabView` of `NavigationStack`s and \
            each tab's own root takes its domain's ground; a background here \
            would be drawn once, underneath all five, and seen through none.
            """,
        "SmartStackView":
            """
            A tile face inside `DashboardGrid`, not a screen. It stands on \
            Today's ground and draws `onyxGlass(.tile)` over it — a second mesh \
            inside a 170 pt cell is the bleed competing with its own tiles.
            """,
        "WeekSoFarView":
            """
            A card inside `TodayTabView`, for the same reason as \
            `SmartStackView`. Named `…View` rather than `…Card` only because it \
            predates the naming rule.
            """,
    ]

    /// Does this file apply a ground in CODE?
    ///
    /// The `//` rule is `TokenDisciplineTests`' rule, and it is not pedantry:
    /// the first version of this test read the whole file, so commenting a
    /// ground out left the marker in the text and the screen kept passing with
    /// no background at all — the exact failure this suite exists to catch,
    /// walking straight through it.
    static func isGrounded(_ text: String) -> Bool {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            for ground in grounds {
                guard let hit = line.range(of: ground) else { continue }
                if let comment = line.range(of: "//"), comment.lowerBound < hit.lowerBound { continue }
                return true
            }
        }
        return false
    }

    @Test("every root screen applies the ground, or is allowlisted with a reason")
    func everyScreenStandsOnTheGround() throws {
        var native = URL(fileURLWithPath: #filePath)
        // …/native/Packages/OnyxUI/Tests/OnyxUITests/AppearanceCoverageTests.swift
        for _ in 0..<5 { native.deleteLastPathComponent() }
        #expect(FileManager.default.fileExists(atPath: native.appendingPathComponent("project.yml").path),
                "expected \(native.path) to be the repo's native/ directory")
        let features = native.appending(path: "Onyx/Features", directoryHint: .isDirectory)

        // `struct Name: …View…`, with an optional generic clause. Built at
        // runtime rather than written as a literal so this file compiles the
        // same way under every language mode the two build systems pick.
        let declaration = try Regex(#"struct\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^>]*>)?\s*:\s*[^{\n]*\bView\b"#)

        var violations: [String] = []
        var seen = Set<String>()
        var files = 0

        let walk = FileManager.default.enumerator(at: features, includingPropertiesForKeys: nil)
        while let url = walk?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else { continue }

            // ponytail: the ground is looked for anywhere in the FILE, not in
            // the declaring type's own body — brace-matching Swift in a test is
            // a parser, and this is a grep. The hole it leaves is a file that
            // declares two root screens where only one is grounded. Close it by
            // splitting the file, which is the right answer anyway.
            let names = text.matches(of: declaration)
                .map { String($0[1].substring ?? "") }
                .filter { $0.hasSuffix("TabView") || $0.hasSuffix("Sheet") || $0.hasSuffix("View") }
            guard !names.isEmpty else { continue }
            files += 1
            seen.formUnion(names)
            guard !Self.isGrounded(text) else { continue }

            let unexcused = names.filter { Self.allowed[$0] == nil }
            guard !unexcused.isEmpty else { continue }
            let path = url.path.replacingOccurrences(of: native.path + "/", with: "native/")
            violations.append("\(path): \(unexcused.joined(separator: ", ")) — apply .onyxScreen(_:) or .onyxFormBackground(_:), or allowlist it in AppearanceCoverageTests with a reason")
        }

        // "No output" is not a pass: a walk that found nothing would be green
        // and would be testing the enumerator.
        #expect(files > 30, "expected the walk to reach the feature screens, saw \(files) files")
        #expect(violations.isEmpty, "screens with no ground:\n\(violations.joined(separator: "\n"))")

        // And the allowlist cannot outlive what it excuses. A name left here
        // after its type is renamed or deleted is an exception nobody is
        // taking, quietly widening the rule.
        let stale = Self.allowed.keys.filter { !seen.contains($0) }.sorted()
        #expect(stale.isEmpty, "allowlisted types that no longer exist: \(stale.joined(separator: ", "))")
    }
}
