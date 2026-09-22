import Foundation
import Testing

/// One hero and at most two captions per card — the house law, enforced.
///
/// ── WHY A THIRD FILE WALK ───────────────────────────────────────────────────
/// `TokenDisciplineTests` catches a screen that spells a colour;
/// `AppearanceCoverageTests` catches a screen with no ground. Neither can
/// catch the failure this app actually keeps having, which is a card that
/// says too much: `docs/COMPACTION_AUDIT.md` §3 found nine text nodes in one
/// glass tile on Today and eight value+label pairs in another on the week
/// page. Nothing breaks, nothing looks wrong in isolation, and the screen
/// gets a little denser every wave until no reading on it is the answer to
/// anything.
///
/// Counted, not rendered: SwiftUI has no way to ask a view how many `Text`s
/// it resolved to, and a snapshot test would fail on a font change. The walk
/// is the same shape as its two siblings — `native/` from `#filePath`, no
/// build setting, no path in `project.yml`.
///
/// ── WHAT COUNTS AS A CARD ───────────────────────────────────────────────────
/// A `View` whose name ends in Card / Row / Tile / Square AND which applies
/// `onyxGlass(` — the glass is what makes it a card rather than a stack of
/// rows on the page's own ground. A card that grows past the budget either
/// loses a caption or states, in `allowed` below, why it is a REGISTER: a grid
/// built to be scanned, where no cell outranks another and there is therefore
/// no hero to protect.
@Suite("Card text budget")
struct CardTextBudgetTests {

    /// One hero (a value and its label), two captions, and the card's own
    /// title: six text nodes. A seventh is where a card stops having an answer
    /// and starts having contents.
    static let budget = 6

    /// Cards over the budget on purpose, each with the reason.
    ///
    /// The reason is the point of the list. Being a register is a legitimate
    /// decision; before this test it was one nobody had to write down.
    static let allowed: [String: String] = [
        "MiniPlayerCard":
            """
            The live session's transport, not a reading: movement, set, load, \
            reps, rest and the two controls are each a separate thing the \
            thumb is reaching for mid-set. A register of controls.
            """,
        "HevyCompareCard":
            """
            A DIFF (W5, decision 7): four rows of ours-versus-theirs plus two \
            buttons. Every line exists to be compared with the one beside it, \
            so there is no hero to protect — dropping a row would drop half a \
            comparison.
            """,
        "SessionHeaderCard":
            """
            The session's whole claim in one card, and the three large type \
            roles are documented there: the tonnage hero, the career number \
            and the split's name. `docs/COMPACTION_AUDIT.md` row 15 is the \
            open work — one `SessionTotals.line(…)` across four surfaces — \
            and it shrinks this card when it lands.
            """,
    ]

    @Test("no card says more than a card can say")
    func withinBudget() throws {
        var over: [String] = []
        for file in Self.swiftFiles(in: Self.featuresRoot) {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (name, body) in Self.cards(in: source) {
                guard body.contains("onyxGlass(") else { continue }
                let nodes = Self.count(of: "Text(", in: body) + Self.count(of: "Label(", in: body)
                guard nodes > Self.budget, Self.allowed[name] == nil else { continue }
                over.append("\(name) (\(nodes) text nodes) — \(file.lastPathComponent)")
            }
        }
        #expect(
            over.isEmpty,
            """
            Over the \(Self.budget)-node budget:
            \(over.joined(separator: "\n"))

            One hero, at most two captions. Move a reading to the surface that \
            owns its question (docs/COMPACTION_AUDIT.md), or add the card to \
            `allowed` with the reason it is a register.
            """
        )
    }

    @Test("the allowlist has no ghosts")
    func allowlistIsCurrent() throws {
        var seen: Set<String> = []
        for file in Self.swiftFiles(in: Self.featuresRoot) {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (name, _) in Self.cards(in: source) { seen.insert(name) }
        }
        let ghosts = Set(Self.allowed.keys).subtracting(seen).sorted()
        #expect(ghosts.isEmpty, "Allowed but no longer a card: \(ghosts.joined(separator: ", "))")
    }

    // MARK: - The walk

    /// `native/Onyx/Features`, from this file's own path — the same trick
    /// `AppearanceCoverageTests` uses, and for the same reason: a test that
    /// needs a build setting to find its input is a test somebody turns off.
    static var featuresRoot: URL {
        URL(fileURLWithPath: #filePath)                       // …/OnyxUITests/CardTextBudgetTests.swift
            .deletingLastPathComponent()                      // …/OnyxUITests
            .deletingLastPathComponent()                      // …/Tests
            .deletingLastPathComponent()                      // …/OnyxUI
            .deletingLastPathComponent()                      // …/Packages
            .deletingLastPathComponent()                      // …/native
            .appendingPathComponent("Onyx/Features")
    }

    static func swiftFiles(in root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// Every `struct <Name>Card/Row/Tile/Square: View` and the source between
    /// it and the next top-level declaration.
    static func cards(in source: String) -> [(String, String)] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [(String, String)] = []
        var current: (name: String, body: [String])?
        for line in lines {
            if let name = declaredCard(line) {
                if let held = current { out.append((held.name, held.body.joined(separator: "\n"))) }
                current = (name, [])
                continue
            }
            // A top-level declaration ends the one before it — anything at
            // column zero that is not a continuation.
            if current != nil, !line.isEmpty, !line.hasPrefix(" "), !line.hasPrefix("}"), !line.hasPrefix("\t") {
                out.append((current!.name, current!.body.joined(separator: "\n")))
                current = nil
            }
            current?.body.append(line)
        }
        if let held = current { out.append((held.name, held.body.joined(separator: "\n"))) }
        return out
    }

    static func declaredCard(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains(": View"), let range = trimmed.range(of: "struct ") else { return nil }
        let rest = trimmed[range.upperBound...]
        let name = String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
        let isCard = ["Card", "Row", "Tile", "Square"].contains { name.hasSuffix($0) }
        return isCard && !name.isEmpty ? name : nil
    }

    static func count(of needle: String, in body: String) -> Int {
        var total = 0
        var cursor = body.startIndex
        while let found = body.range(of: needle, range: cursor..<body.endIndex) {
            // `.foregroundStyle(…)` and friends: only a bare `Text(` counts,
            // not `SharePreview(`. The character before must not be part of an
            // identifier.
            let ok: Bool = {
                guard found.lowerBound > body.startIndex else { return true }
                let before = body[body.index(before: found.lowerBound)]
                return !(before.isLetter || before.isNumber || before == "_" || before == ".")
            }()
            if ok { total += 1 }
            cursor = found.upperBound
        }
        return total
    }
}
