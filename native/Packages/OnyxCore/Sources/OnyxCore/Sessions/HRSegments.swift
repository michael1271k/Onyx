import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// A session's heart-rate series, cut into the movements it was under.
// Expansion W5.
//
// ── WHAT A BOUNDARY IS ───────────────────────────────────────────────────────
// The log knows WHEN each set was committed (`SetEvent.createdAt`) and nothing
// about when it began — a set's duration is not recorded. So a movement's
// segment runs from the previous movement's LAST commit (the session's start
// for the first) to its own last commit: the sets and the rests between them,
// which is the block of time a person calls "the chest press". Everything
// after the final commit — plates away, the walk out — belongs to no movement
// and is drawn as a gap, as is every paused interval.
//
// ── THE PAUSE LEDGER IS THE LOG'S OWN RULE ───────────────────────────────────
// The first `pause` of a run opens the interval and a `resume` closes it, so a
// double tap cannot bank the same minutes twice — `EventStore.pauseLedger`,
// restated here on the same markers so the clock and the chart agree about
// what a pause was. A segment a pause falls inside is split; the second piece
// is marked `continues` so the chart labels the movement once.
//
// Half-open pieces (`[start, end)`): a sample on a boundary belongs to the
// segment that begins there, never to both, so the numbers are deterministic
// and the golden vector (`hr-segments.json`) can be hand-computed.
// ─────────────────────────────────────────────────────────────────────────────

/// One heart-rate reading.
public struct HRSample: Codable, Sendable, Equatable {
    public var at: Date
    public var bpm: Int

    public init(at: Date, bpm: Int) {
        self.at = at
        self.bpm = bpm
    }
}

/// One movement's slice of the series (or one piece of it, around a pause).
public struct HRSegment: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(exerciseId)|\(Int(start.timeIntervalSince1970))" }
    public var exerciseId: String
    public var start: Date
    public var end: Date
    /// Nil when no sample fell inside the piece.
    public var avgBpm: Int?
    public var maxBpm: Int?
    /// True for the second and later pieces of one movement split by a pause.
    public var continues: Bool

    public init(exerciseId: String, start: Date, end: Date, avgBpm: Int?, maxBpm: Int?, continues: Bool = false) {
        self.exerciseId = exerciseId
        self.start = start
        self.end = end
        self.avgBpm = avgBpm
        self.maxBpm = maxBpm
        self.continues = continues
    }
}

public enum HRSegments {

    /// What the log says, in fold order. Only the three facts segmenting reads.
    public enum Marker: Sendable, Equatable {
        case set(exerciseId: String, at: Date)
        case pause(at: Date)
        case resume(at: Date)
    }

    /// The paused intervals, closed; an open pause closes at `end`.
    public static func pausedIntervals(_ markers: [Marker], end: Date) -> [(start: Date, end: Date)] {
        var out: [(Date, Date)] = []
        var openedAt: Date?
        for marker in markers {
            switch marker {
            case .pause(let at):
                if openedAt == nil { openedAt = at }
            case .resume(let at):
                if let start = openedAt, at > start { out.append((start, at)) }
                openedAt = nil
            case .set:
                break
            }
        }
        if let start = openedAt, end > start { out.append((start, end)) }
        return out.map { (start: $0.0, end: $0.1) }
    }

    /// The segments, in time order.
    public static func build(
        markers: [Marker], samples: [HRSample], sessionStart: Date, sessionEnd: Date
    ) -> [HRSegment] {
        guard sessionEnd > sessionStart else { return [] }
        let paused = pausedIntervals(markers, end: sessionEnd)

        // Runs of one movement: (exerciseId, last commit).
        var runs: [(exerciseId: String, lastAt: Date)] = []
        for marker in markers {
            guard case .set(let exerciseId, let at) = marker else { continue }
            if let last = runs.last, last.exerciseId == exerciseId {
                runs[runs.count - 1].lastAt = max(last.lastAt, at)
            } else {
                runs.append((exerciseId, at))
            }
        }

        var out: [HRSegment] = []
        var cursor = sessionStart
        for run in runs {
            let rawStart = cursor
            let rawEnd = min(run.lastAt, sessionEnd)
            cursor = max(cursor, rawEnd)
            guard rawEnd > rawStart else { continue }
            var first = true
            for piece in subtract((rawStart, rawEnd), paused) {
                let inside = samples.filter { $0.at >= piece.start && $0.at < piece.end }
                out.append(HRSegment(
                    exerciseId: run.exerciseId, start: piece.start, end: piece.end,
                    avgBpm: average(inside), maxBpm: inside.map(\.bpm).max(),
                    continues: !first
                ))
                first = false
            }
        }
        return out
    }

    /// The session's own two numbers, over every sample that was not taken
    /// during a pause. The hero when the store holds no measured average.
    public static func summary(
        markers: [Marker], samples: [HRSample], sessionStart: Date, sessionEnd: Date
    ) -> (avgBpm: Int?, maxBpm: Int?) {
        let paused = pausedIntervals(markers, end: sessionEnd)
        let live = samples.filter { s in
            s.at >= sessionStart && s.at <= sessionEnd
                && !paused.contains { s.at >= $0.start && s.at < $0.end }
        }
        return (average(live), live.map(\.bpm).max())
    }

    /// `[a, b)` minus every paused interval, in order.
    static func subtract(
        _ interval: (Date, Date), _ paused: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        var pieces: [(start: Date, end: Date)] = [(interval.0, interval.1)]
        for gap in paused.sorted(by: { $0.start < $1.start }) {
            var next: [(start: Date, end: Date)] = []
            for piece in pieces {
                if gap.end <= piece.start || gap.start >= piece.end {
                    next.append(piece)
                    continue
                }
                if gap.start > piece.start { next.append((piece.start, gap.start)) }
                if gap.end < piece.end { next.append((gap.end, piece.end)) }
            }
            pieces = next
        }
        return pieces
    }

    /// `Math.round` of the mean — the rounding every stored bpm uses.
    static func average(_ samples: [HRSample]) -> Int? {
        guard !samples.isEmpty else { return nil }
        let mean = Double(samples.reduce(0) { $0 + $1.bpm }) / Double(samples.count)
        return Int(jsRound(mean))
    }
}
