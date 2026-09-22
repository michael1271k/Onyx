import Foundation
import os

/// The eight seams this app is measured at, and the one signposter that marks
/// them.
///
/// ── WHY A SINK AND NOT JUST A SIGNPOST ──────────────────────────────────────
/// `os_signpost` is the right thing for Instruments and for the founder's
/// device trace, and it is what `xctrace` reads. It is also invisible from a
/// command line: getting a number out of a `.trace` bundle means an `xctrace
/// export` with an XPath at a schema that changes between Xcode releases, and
/// the wave that cannot read its own before/after table has not measured
/// anything. So every interval ALSO lands in a file, in DEBUG, when
/// `ONYX_PERF=1` is in the environment — which is how the table in
/// `docs/CHANGELOG.md` was produced. Release builds carry the signposts alone;
/// `signpostsEnabled` is `false` when no tool is listening, so the cost of a
/// disabled interval is a load and a branch.
public enum Perf {
    /// Subsystem `app.onyx.perf`. `ScoringWindow`'s `rescore.run` (W2) is the
    /// ninth interval and uses this same signposter.
    public static let signposter = OSSignposter(subsystem: "app.onyx.perf", category: "seam")

    public struct Span: Sendable {
        let name: StaticString
        let state: OSSignpostIntervalState
        let started: DispatchTime
    }

    /// Open an interval that ends somewhere else — a first frame, a sync that
    /// finishes in a callback. Prefer `measure` when the work is one scope.
    public static func begin(_ name: StaticString) -> Span {
        Span(
            name: name,
            state: signposter.beginInterval(name, id: signposter.makeSignpostID()),
            started: .now()
        )
    }

    public static func end(_ span: Span) {
        signposter.endInterval(span.name, span.state)
        record(span)
    }

    public static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let span = begin(name)
        defer { end(span) }
        return try body()
    }

    public static func measure<T>(
        _ name: StaticString, _ body: () async throws -> T
    ) async rethrows -> T {
        let span = begin(name)
        defer { end(span) }
        return try await body()
    }

    // MARK: - The sink

    #if DEBUG
    private static let sink = Sink()

    /// `<Documents>/perf.jsonl`, one `{"seam":…,"ms":…}` per interval. Read it
    /// with `xcrun simctl get_app_container booted app.onyx.native data`.
    public static var logURL: URL? { Sink.url }

    private static func record(_ span: Span) {
        guard Sink.url != nil else { return }
        let ms = Double(DispatchTime.now().uptimeNanoseconds &- span.started.uptimeNanoseconds)
            / 1_000_000
        sink.append(seam: "\(span.name)", ms: ms)
    }

    private final class Sink: @unchecked Sendable {
        static let url: URL? = {
            guard ProcessInfo.processInfo.environment["ONYX_PERF"] == "1" else { return nil }
            return FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("perf.jsonl")
        }()

        private let queue = DispatchQueue(label: "app.onyx.perf.sink", qos: .utility)

        func append(seam: String, ms: Double) {
            guard let url = Sink.url else { return }
            let line = #"{"seam":"\#(seam)","ms":\#(String(format: "%.2f", ms))}"# + "\n"
            queue.async {
                guard let data = line.data(using: .utf8) else { return }
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                } else {
                    try? data.write(to: url)
                }
            }
        }
    }
    #else
    private static func record(_ span: Span) {}
    #endif
}
