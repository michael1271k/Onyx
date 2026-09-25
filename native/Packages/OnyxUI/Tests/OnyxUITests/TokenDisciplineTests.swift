import Foundation
import Testing
import OnyxCore
@testable import OnyxUI

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

    // MARK: - The ground's light (Precision B3, decision Q20)

    /// Fails if `groundPeak` or the chroma clamp is raised far enough to lift
    /// the ground into the text: the brightest point of the ground (both
    /// radials summed at their peaks, which on screen never coincide) must
    /// stay under OKLab L 0.35, and `textSecondary` over it at ≥ 4.5 : 1 —
    /// every stone, every domain, and the neutral ground.
    @Test("the ground's light keeps L ≤ 0.35 and textSecondary ≥ 4.5 : 1 — 8 stones × 4 domains")
    func groundHoldsContrast() {
        func channels(_ hex: UInt32) -> [Double] {
            [Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF)].map { $0 / 255 }
        }
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func luminance(_ rgb: [Double]) -> Double {
            let l = rgb.map(linear)
            return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
        }
        func hex(_ rgb: [Double]) -> UInt32 {
            rgb.map { UInt32((min(max($0, 0), 1) * 255).rounded()) }.reduce(0) { $0 << 8 | $1 }
        }
        // `textSecondary` is white at 0.62 over the ground.
        let textAlpha = 0.62
        var checked = 0
        for preset in OnyxTheme.presets {
            let theme = OnyxTheme(spec: preset.spec)
            for domain in [nil] + OnyxDomain.allCases.map(Optional.some) {
                let pair = theme.groundHex(domain)
                // Composited over black the way the render server does it —
                // opacity in the ENCODED (gamma) space. Measured, not assumed:
                // Slate at 14 % reads sRGB (16, 16, 21) at the ground's
                // brightest on-screen point, which is the gamma blend; a
                // linear-light blend would read ~(60, 60, 70).
                let ground: [Double] = (0..<3).map { i in
                    let a = channels(pair.primary)[i], b = channels(pair.secondary)[i]
                    return a * OnyxTheme.groundPeak + b * OnyxTheme.groundSecondaryPeak
                }
                let l = OKLCHConvert.oklch(fromHex: hex(ground)).l
                #expect(l <= 0.35, "\(preset.name) \(String(describing: domain)): ground L \(l)")
                let text = ground.map { textAlpha + (1 - textAlpha) * $0 }
                let ratio = (luminance(text) + 0.05) / (luminance(ground) + 0.05)
                #expect(ratio >= 4.5, "\(preset.name) \(String(describing: domain)): textSecondary \(ratio):1")
                // The clamp itself.
                #expect(OKLCHConvert.oklch(fromHex: pair.primary).c <= 0.1 + 0.005)
                #expect(OKLCHConvert.oklch(fromHex: pair.secondary).c <= 0.1 + 0.005)
                checked += 1
            }
        }
        #expect(checked == 8 * 5, "eight stones × (four domains + neutral)")
    }
}
