import Foundation
import Testing
@testable import OnyxCore

/// `DeepLink.safePath` and the tab mapping, against the TypeScript's answers.
///
/// A `onyx://` URL is untrusted input — anything on the device can open one —
/// so these are security vectors, not formatting ones. The allow-list is
/// pinned case for case so the Swift port cannot quietly widen it.
@Suite("Deep links — the allow-list and where each path lands")
struct DeepLinkGoldenTests {

    struct In: Decodable { let raw: String? }
    struct Dest: Decodable { let kind: String; let date: String? }
    struct Out: Decodable { let path: String?; let destination: Dest? }

    @Test("every case matches the TypeScript")
    func matchesTypeScript() throws {
        let fixture = try GoldenFixture<In, Out>.load("deep-link")
        #expect(fixture.cases.count >= 20)

        for testCase in fixture.cases {
            let path = DeepLink.safePath(Self.rescheme(testCase.input.raw))
            #expect(path == testCase.expected.path, "\(testCase.name) — path")

            let destination = path.flatMap(DeepLink.destination(forPath:))
            let expected = testCase.expected.destination.map(Self.decode)
            #expect(destination == expected, "\(testCase.name) — destination")
        }
    }

    @Test("url(path:) round-trips through safePath")
    func urlRoundTrips() {
        for path in ["/", "/nutrition/micros", "/day/2026-09-03?section=sleep"] {
            #expect(DeepLink.safePath(DeepLink.url(path: path)?.absoluteString) == path)
        }
    }

    /// The one case `rescheme` cannot test, because it rewrites it first.
    ///
    /// Every fixture arrives here as `onyx://` — including the case named
    /// "upper-case scheme", which therefore proves case-insensitive ACCEPTANCE
    /// and not the scheme rejection the suite's doc comment claims. The retired
    /// app's scheme may still sit in a stale Shortcut or a bookmark, so a URL
    /// under it reaching this parser is a real thing that must be refused, and
    /// nothing in the vector says so.
    @Test("a foreign scheme is refused, the retired app's included")
    func foreignSchemesRejected() {
        for raw in ["helix://open?path=/nutrition", "HELIX://open?path=/nutrition",
                    "https://onyx.example/open?path=/nutrition",
                    "javascript:alert(1)", "capacitor://open?path=/nutrition"] {
            #expect(DeepLink.safePath(raw) == nil, "\(raw) was not refused")
        }
        // The control: the same path under the app's own scheme still passes.
        #expect(DeepLink.safePath("onyx://open?path=/nutrition") == "/nutrition")
    }

    /// Swap the SCHEME, and only the scheme, on the way in.
    ///
    /// The fixture was generated from the retired web app's deep-link module,
    /// which answered to that app's own scheme. Onyx registers `onyx://`, so the
    /// fixture's scheme is swapped on the way in and nothing else is.
    ///
    /// Everything the allow-list actually decides is downstream of the scheme,
    /// so translating it here keeps all thirty cases — including the
    /// case-insensitive upper-case one, the traversal attempts and the
    /// `//evil.example` protocol-relative smuggling — pointed at the real
    /// parser. A raw string with any OTHER scheme is passed through untouched,
    /// which is what makes the negative cases still negative.
    private static func rescheme(_ raw: String?) -> String? {
        guard let raw, let colon = raw.firstIndex(of: ":"),
              raw[raw.startIndex..<colon].lowercased() == "helix" else { return raw }
        return "onyx" + raw[colon...]
    }

    private static func decode(_ dest: Dest) -> DeepLink.Destination {
        switch dest.kind {
        case "today": return .today
        case "train": return .train
        case "fuel": return .fuel
        case "body": return .body(date: dest.date)
        case "you": return .you
        case "reports": return .reports
        default: fatalError("unknown destination kind \(dest.kind)")
        }
    }
}
