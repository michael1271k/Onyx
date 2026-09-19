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
            let path = DeepLink.safePath(testCase.input.raw)
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

    /// The cases the fixture cannot carry, because they are not this app's URLs.
    ///
    /// ── AND THE ONE THAT LEFT WITH THE PREDECESSOR (Expansion W1) ──────────
    /// This list used to open with the retired web app's own scheme, because a
    /// URL under it could still sit in a stale Shortcut or a bookmark and had
    /// to be refused by name. W1 removed that name from the repository, and a
    /// rejection test cannot assert about a string it may not spell. What
    /// replaces it is structural and stronger: `safePath` accepts exactly one
    /// scheme and every other shape below is refused, so a retired scheme is
    /// refused for the same reason `capacitor://` is — not by a special case.
    @Test("a foreign scheme is refused")
    func foreignSchemesRejected() {
        for raw in ["https://onyx.example/open?path=/nutrition",
                    "javascript:alert(1)", "capacitor://open?path=/nutrition",
                    "onyxapp://open?path=/nutrition", "on://open?path=/nutrition"] {
            #expect(DeepLink.safePath(raw) == nil, "\(raw) was not refused")
        }
        // The control: the same path under the app's own scheme still passes.
        #expect(DeepLink.safePath("onyx://open?path=/nutrition") == "/nutrition")
    }

    // ── `rescheme` IS GONE (Expansion W1) ───────────────────────────────────
    // The fixture was generated from the retired web app's deep-link module
    // and answered to that app's scheme, so every case was translated on the
    // way in. W1 rewrote the fixture itself to `onyx://`, which left that
    // helper doing exactly one thing: downcasing the scheme of the case named
    // "upper-case scheme" — the ONLY uppercase input in the suite, and the
    // only thing that exercises `safePath`'s `scheme?.lowercased()`. It was
    // silently disarming the case it was supposedly preserving. Every input
    // now reaches the parser as written.

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
