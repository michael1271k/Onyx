import Foundation

/// A finished session in one line — name · duration · tonnage · avg HR · PRs,
/// plus a six-point HR sparkline (overhaul W0, decisions Q3 and concept 8).
///
/// ONE value for every surface that names a finished workout: the watch's
/// post-workout banner (`SessionLifecycle.summary`, Lane A), the widget and
/// session banners (Lane B's `SessionMasthead` face), and the summary header
/// (Lane C). Built once on the phone from its session analysis, so the wrist
/// needs no telemetry query of its own.
///
/// Wire type: `Codable` with the synthesised keys. Never rename or reorder a
/// key; add new ones optional and last (the `WatchContext` story).
public struct SessionMasthead: Codable, Hashable, Sendable {
    public var name: String
    public var durationSec: Int
    public var tonnageKg: Double
    /// Nil when no heart rate was recorded — never 0, which would be a reading.
    public var avgBpm: Int?
    public var prCount: Int
    /// Exactly six points, or empty when there is no HR. The initialiser
    /// enforces it (`spark(_:)`); a decoded value is trusted as sent.
    public var hrSpark: [Double]
    public var startedAt: Date

    public init(name: String, durationSec: Int, tonnageKg: Double, avgBpm: Int?,
                prCount: Int, hrSpark: [Double], startedAt: Date) {
        self.name = name
        self.durationSec = durationSec
        self.tonnageKg = tonnageKg
        self.avgBpm = avgBpm
        self.prCount = prCount
        self.hrSpark = Self.spark(hrSpark)
        self.startedAt = startedAt
    }

    /// Any number of HR samples → six. Six or more: the mean of six equal
    /// buckets, in order. Fewer: the nearest sample to each of six evenly
    /// spaced slots, so the first and last points are the first and last
    /// samples. None: none.
    public static func spark(_ samples: [Double]) -> [Double] {
        let n = samples.count
        guard n > 0 else { return [] }
        guard n >= 6 else {
            return (0..<6).map { samples[Int((Double($0) * Double(n - 1) / 5).rounded())] }
        }
        return (0..<6).map { i in
            let bucket = samples[(i * n / 6)..<((i + 1) * n / 6)]
            return bucket.reduce(0, +) / Double(bucket.count)
        }
    }
}
