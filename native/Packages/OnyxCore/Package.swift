// swift-tools-version: 6.0
import PackageDescription

/// OnyxCore — the domain arithmetic, and nothing else.
///
/// ── WHY THIS IS A PACKAGE AND NOT A FOLDER IN THE APP ────────────────────────
/// Two reasons, both practical.
///
/// 1. It imports Foundation and NOTHING ELSE — no SwiftUI, no UIKit, no GRDB,
///    no Supabase. That is enforced by being a separate module: an accidental
///    `import SwiftUI` in a scoring file fails the build instead of quietly
///    tying the formulas to a view layer. The web codebase earned this rule the
///    hard way (the web app's `lib/scoring/computeForDate.ts` carries a "SERVER-SAFE by
///    construction: no React" header for the same reason), and the Swift port
///    keeps it.
///
/// 2. It builds and tests for **macOS**, so `swift test` runs the whole domain
///    suite from the command line in seconds with no simulator, no signing and
///    no Xcode. On a free Apple team where the app itself expires every seven
///    days, having the arithmetic verifiable without a device is not a
///    convenience — it is the only continuously trustworthy signal there is.
let package = Package(
    name: "OnyxCore",
    platforms: [
        // iOS 18 is the app's floor. macOS is here purely so the test suite runs
        // on the command line; no product ships for it.
        .iOS(.v18),
        .macOS(.v14),
        // The Watch client (Wave 10). Pure Foundation arithmetic, so this
        // costs one line and the whole domain — the deck, the ladder, the
        // rest targets — is on the wrist with no second implementation.
        .watchOS(.v11),
    ],
    products: [
        .library(name: "OnyxCore", targets: ["OnyxCore"]),
    ],
    targets: [
        .target(
            name: "OnyxCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OnyxCoreTests",
            dependencies: ["OnyxCore"],
            // The golden vectors, exported from the TypeScript implementation by
            // `npm run golden`. They are checked into git deliberately: they are
            // the acceptance spec for this port, and a spec you have to
            // regenerate before you can read it is not a spec.
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
