import Foundation

/// The last 24 hours of heart rate THIS wrist measured (Precision D2/D3).
///
/// ── WHY THE WATCH KEEPS ITS OWN ─────────────────────────────────────────────
/// `LastHeartRate` is one number and its age. The Heart detail draws a day
/// of them and the Live Heart complication an arc of six blocks, and neither
/// can come from the phone: the phone sees heart rate only as a workout's
/// average. `WatchVitals` (OnyxData) feeds this from its anchored query and
/// parks it in the watch's suite, where the complication extension reads it.
///
/// ── THINNED, NOT RAW ────────────────────────────────────────────────────────
/// One sample per five-minute grain — the newest in it wins. A workout logs a
/// sample every few seconds; 24 hours of that is ~17 000 rows decoded on
/// every complication timeline. 288 is the most the day can hold, and a
/// sparkline 146 pt wide cannot draw more than that anyway.
///
/// ── GAPS ARE GAPS ───────────────────────────────────────────────────────────
/// Off the wrist, asleep with the sensor quiet, a flat battery: the day has
/// holes. `runs()` breaks the line at any gap over half an hour rather than
/// drawing a straight segment across a morning nobody measured.
public struct HeartTrail: Codable, Sendable, Equatable {

    public struct Sample: Codable, Sendable, Equatable {
        public let at: Date
        public let bpm: Int
        public init(at: Date, bpm: Int) {
            self.at = at
            self.bpm = bpm
        }
        enum CodingKeys: String, CodingKey { case at = "t", bpm = "b" }
    }

    /// Oldest first, inside the window, one per grain.
    public private(set) var samples: [Sample]

    public static let window: TimeInterval = 24 * 3600
    public static let grain: TimeInterval = 5 * 60
    /// The longest silence a line may span.
    public static let maxGap: TimeInterval = 30 * 60

    public init(samples: [Sample] = []) { self.samples = samples }

    public var latest: Sample? { samples.last }

    /// Fold `new` in and drop what fell out of the window.
    public mutating func merge(_ new: [Sample], now: Date) {
        let floor = now.addingTimeInterval(-Self.window)
        var byGrain: [Int: Sample] = [:]
        for sample in samples + new where sample.at >= floor && sample.at <= now.addingTimeInterval(60) {
            let key = Int((sample.at.timeIntervalSince1970 / Self.grain).rounded(.down))
            if let kept = byGrain[key], kept.at >= sample.at { continue }
            byGrain[key] = sample
        }
        samples = byGrain.values.sorted { $0.at < $1.at }
    }

    /// The trail as continuous stretches — a line per run, never across a gap.
    public func runs(maxGap: TimeInterval = HeartTrail.maxGap) -> [[Sample]] {
        var out: [[Sample]] = []
        for sample in samples {
            if let last = out.last?.last, sample.at.timeIntervalSince(last.at) <= maxGap {
                out[out.count - 1].append(sample)
            } else {
                out.append([sample])
            }
        }
        return out
    }

    /// The day as `count` equal blocks, oldest first: each block's mean bpm,
    /// nil where the wrist saw nothing. The Live Heart complication's arc.
    public func blocks(now: Date, count: Int = 6) -> [Int?] {
        guard count > 0 else { return [] }
        let start = now.addingTimeInterval(-Self.window)
        let span = Self.window / Double(count)
        var sums = Array(repeating: (total: 0, n: 0), count: count)
        for sample in samples {
            let i = Int((sample.at.timeIntervalSince(start) / span).rounded(.down))
            guard (0..<count).contains(i) else { continue }
            sums[i].total += sample.bpm
            sums[i].n += 1
        }
        return sums.map { $0.n == 0 ? nil : Int((Double($0.total) / Double($0.n)).rounded()) }
    }

    // MARK: Where the watch keeps it

    public static let key = "onyx.watch.heartTrail"
    /// The Live Heart complication's `kind:` (Precision D4).
    public static let widgetKind = "OnyxWatch.liveHeart"

    public static func load(from defaults: UserDefaults = WatchTiles.defaults()) -> HeartTrail? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(HeartTrail.self, from: $0) }
    }

    public func save(to defaults: UserDefaults = WatchTiles.defaults()) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// When the wrist's last heart rate is worth drawing as a reading.
public enum WatchHeart {

    public enum Freshness: Equatable, Sendable { case none, stale, fresh }

    /// 90 minutes. Background delivery is hourly (`WatchVitals`), so a rate up
    /// to an hour old is the NORMAL state between workouts; half an hour past
    /// that the delivery was missed, and the petal goes hollow rather than
    /// print a number from before lunch as if it were now.
    public static let freshFor: TimeInterval = 90 * 60

    public static func freshness(_ reading: LastHeartRate?, now: Date = Date()) -> Freshness {
        guard let reading else { return .none }
        return now.timeIntervalSince(reading.at) <= freshFor ? .fresh : .stale
    }

    /// The reading to save after `samples` arrived, or nil when none of them
    /// is newer than what is stored — a background delivery must never
    /// overwrite the rate a running workout wrote ten seconds ago.
    public static func adopt(_ samples: [HeartTrail.Sample], over current: LastHeartRate?) -> LastHeartRate? {
        guard let newest = samples.max(by: { $0.at < $1.at }) else { return nil }
        if let current, current.at >= newest.at { return nil }
        return LastHeartRate(bpm: newest.bpm, at: newest.at)
    }
}

/// The newest heart-rate variability (SDNN) this wrist measured — the Heart
/// detail's third figure. The watch takes it overnight and at rest; there is
/// no series, one reading and its age.
public struct LastHRV: Codable, Sendable, Equatable {
    public let ms: Int
    public let at: Date

    public init(ms: Int, at: Date) {
        self.ms = ms
        self.at = at
    }

    public static let key = "onyx.watch.lastHrv"

    public static func load(from defaults: UserDefaults = WatchTiles.defaults()) -> LastHRV? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(LastHRV.self, from: $0) }
    }

    public func save(to defaults: UserDefaults = WatchTiles.defaults()) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
