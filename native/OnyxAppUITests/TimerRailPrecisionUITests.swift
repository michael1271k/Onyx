import XCTest

/// Precision A4: the rail's elapsed reading skips no second.
///
/// A UI test and not a unit test because the reading is `Text(_:style: .timer)`,
/// which the SYSTEM ticks off the view tree — the only way to watch it count is
/// to launch the app and read it twice. The harness screen `logger` is a live
/// deck twenty-two minutes in, resting, with the rail under it.
@MainActor
final class TimerRailPrecisionUITests: XCTestCase {

    func testElapsedCountsTenSecondsInTen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--onyx-screen", "logger"]
        app.launch()

        let elapsed = app.staticTexts["timer-rail-elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 20), "the rail draws its elapsed reading")

        let first = try XCTUnwrap(Self.seconds(elapsed.label), "unreadable: \(elapsed.label)")
        let started = Date()
        Thread.sleep(forTimeInterval: 10)
        let second = try XCTUnwrap(Self.seconds(elapsed.label), "unreadable: \(elapsed.label)")
        let waited = Date().timeIntervalSince(started)

        // Two reads bracket the wait: the reading moved by the wall time
        // between them, give or take the one second either read can straddle.
        XCTAssertLessThanOrEqual(abs(Double(second - first) - waited), 1.5,
                                 "\(first) → \(second) across \(waited) s")
    }

    /// `22:06` / `1:02:03` → seconds.
    static func seconds(_ label: String) -> Int? {
        let parts = label.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard (2...3).contains(parts.count) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}
