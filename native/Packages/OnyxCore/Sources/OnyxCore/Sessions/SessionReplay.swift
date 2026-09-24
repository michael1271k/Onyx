import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Session Replay (overhaul W5, feature 2, founder challenge F2).
//
// A finished session played back in ten seconds, as PURE DATA: the phone card,
// the watch's three-second version, the share PNGs and the MP4 all draw
// `frame(at:)` of one `Timeline` and nothing else. So every claim the replay
// makes about time — that a dot never lands on trace that is not drawn yet, that
// every set gets a dot, that the records flash as many times as the masthead
// counts — is a claim about this file, and `SessionReplayTests` holds it.
//
// ── THE FOUR PHASES, AS FRACTIONS OF THE LENGTH ─────────────────────────────
//   track    0.0 – 0.6   the HR trace draws itself left to right (or, with no
//                        heart rate, the tonnage bar grows one movement at a time)
//   dots     0.2 – 0.8   each set drops in at its own place on the track
//   records  0.8 – 0.9   the record dots flash gold, once
//   settle   0.9 – 1.0   the masthead settles
// At 10 s that is 0–6 / 2–8 / 8–9 / 9–10; the watch runs the same keyframes
// scaled to 3 s.
//
// ── ONE AXIS, TWO MEANINGS ──────────────────────────────────────────────────
// `x` runs 0…1 along the track. With heart rate it is TIME through the session
// (a set sits where its commit happened). Without, it is the TONNAGE bar
// (a movement's segment is half its share of the work, half its sets). Both grow at the
// same rate — the track reaches `x` at `0.6·D·x` — and a dot at `x` drops at
// `0.2·D + x·(0.6·D − drop)`, which is never earlier. That inequality is the
// whole reason a dot always lands on something already drawn — the track's
// PROGRESS, that is: a series that begins late (the watch joined at 30 %)
// has no ink before its first sample, and an early set drops onto the empty
// stretch at its own time rather than onto a trace that was never measured.
// ─────────────────────────────────────────────────────────────────────────────

public enum SessionReplay {

    /// The phone's replay, in seconds.
    public static let duration: Double = 10
    /// The watch's condensed replay — the same keyframes, scaled.
    public static let watchDuration: Double = 3
    /// How long one dot takes to drop, as a fraction of the length (0.5 s at 10).
    public static let dropFraction: Double = 0.05

    static let trackEnd = 0.6
    static let dotsStart = 0.2
    static let dotsEnd = 0.8
    static let recordsStart = 0.8
    static let recordsEnd = 0.9
    static let settleStart = 0.9
    /// The narrowest a movement's tonnage segment may be — a bodyweight
    /// movement did work, and a zero-width segment would hide its dots.
    static let minSegment = 0.04
    /// The trace is resampled to at most this many points; a 90-minute series
    /// at 5 s is 1,080 samples, and a 300-frame video redraws it on every frame.
    static let tracePoints = 60

    // MARK: - Input

    /// One movement, in performed order.
    public struct Movement: Sendable, Equatable {
        public var name: String
        public var tonnageKg: Double
        public init(name: String, tonnageKg: Double) {
            self.name = name
            self.tonnageKg = tonnageKg
        }
    }

    /// One logged set: its movement (an index into `Input.movements`), when it
    /// was committed if the log knows, and how many record axes it took.
    public struct SetMark: Sendable, Equatable {
        public var movement: Int
        /// Nil for a set the event log has no clock for (a pulled or legacy
        /// row). It is placed between its neighbours, never invented.
        public var at: Date?
        /// Axes, not a flag: the masthead's `prCount` counts a set that took
        /// the load AND the e1RM record twice, and the flash must agree with it.
        public var records: Int
        public init(movement: Int, at: Date?, records: Int = 0) {
            self.movement = movement
            self.at = at
            self.records = records
        }
    }

    /// Everything a replay is built from — the summary inputs the masthead
    /// already has, plus the heart-rate series and the set clocks.
    public struct Input: Sendable {
        public var masthead: SessionMasthead
        public var start: Date
        public var end: Date
        public var samples: [HRSample]
        public var movements: [Movement]
        /// In performed order — movement by movement, set by set.
        public var sets: [SetMark]
        public init(masthead: SessionMasthead, start: Date, end: Date, samples: [HRSample],
                    movements: [Movement], sets: [SetMark]) {
            self.masthead = masthead
            self.start = start
            self.end = end
            self.samples = samples
            self.movements = movements
            self.sets = sets
        }
    }

    // MARK: - Output

    public enum Mode: Sendable, Equatable {
        /// A heart-rate trace — `x` is time through the session.
        case trace
        /// No heart rate: a tonnage bar — `x` is cumulative work.
        case tonnage
    }

    public struct Point: Sendable, Equatable {
        public var x: Double
        /// 0 is the lowest bpm of the session, 1 the highest.
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct Dot: Sendable, Equatable {
        public var x: Double
        public var y: Double
        /// Seconds into the replay when it starts to drop.
        public var appearAt: Double
        public var movement: Int
        /// Record axes this set took; a dot with any flashes gold.
        public var records: Int
        public var isRecord: Bool { records > 0 }
    }

    /// One movement's stretch of the tonnage bar.
    public struct Bar: Sendable, Equatable {
        public var movement: Int
        public var from: Double
        public var to: Double
    }

    public enum KeyframeKind: Sendable, Equatable {
        case trackBegins, dot(Int), trackEnds, recordsFlash, settleBegins, end
    }

    public struct Keyframe: Sendable, Equatable {
        public var at: Double
        public var kind: KeyframeKind
    }

    /// What is on screen at one instant. Views draw this and nothing else.
    public struct Frame: Sendable, Equatable {
        /// How far along the track (0…1) the trace or the bar has drawn.
        public var trackProgress: Double
        /// Per bar, how much of it has grown (tonnage mode; empty otherwise).
        public var bars: [Double]
        /// Per dot: 0 not yet, 0…1 falling, 1 landed.
        public var drops: [Double]
        /// The one gold flash, 0 → 1 → 0 across the records phase.
        public var recordGlow: Double
        /// Record dots are gold from the flash on.
        public var recordsLit: Bool
        /// The masthead's settle, 0…1.
        public var settle: Double
        /// The movement of the last dot to land — the card's running label.
        public var currentMovement: Int?
    }

    public struct Timeline: Sendable, Equatable {
        public let duration: Double
        public let mode: Mode
        public let trace: [Point]
        public let bars: [Bar]
        public let dots: [Dot]
        public let masthead: SessionMasthead
        public let movements: [Movement]
        public let keyframes: [Keyframe]

        /// Record AXES — the number the masthead's trophy prints.
        public var recordCount: Int { dots.reduce(0) { $0 + $1.records } }

        /// The replay at `t` seconds, clamped to 0…duration.
        public func frame(at t: Double) -> Frame {
            let t = min(max(t, 0), duration)
            let track = min(t / (trackEnd * duration), 1)
            let drop = dropFraction * duration
            let drops = dots.map { min(max((t - $0.appearAt) / drop, 0), 1) }
            let records = recordsStart * duration, recordsLength = (recordsEnd - recordsStart) * duration
            let phase = (t - records) / recordsLength
            let glow = recordCount > 0 && phase > 0 && phase < 1 ? sin(.pi * phase) : 0
            let settleStartAt = settleStart * duration
            let settle = min(max((t - settleStartAt) / (duration - settleStartAt), 0), 1)
            return Frame(
                trackProgress: track,
                bars: bars.map { bar in
                    bar.to > bar.from ? min(max((track - bar.from) / (bar.to - bar.from), 0), 1) : (track >= bar.to ? 1 : 0)
                },
                drops: drops,
                recordGlow: glow,
                recordsLit: t >= records,
                settle: settle,
                currentMovement: drops.lastIndex { $0 >= 1 }.map { dots[$0].movement }
            )
        }

        /// The last frame — what Reduce Motion jumps to and the share frames draw.
        public var final: Frame { frame(at: duration) }

        /// The masthead as far as the replay has got — the video's figures
        /// count up with it instead of appearing only in the last second
        /// (the share round's critique). Duration follows the track, tonnage
        /// the landed sets' movements, the record count the flash. At the
        /// final frame it IS the masthead.
        public func masthead(at frame: Frame) -> SessionMasthead {
            guard frame.settle < 1 else { return masthead }
            var live = masthead
            live.durationSec = Int((Double(masthead.durationSec) * frame.trackProgress).rounded())
            let landed = zip(dots, frame.drops).filter { $0.1 >= 1 }.map(\.0)
            let share = dots.isEmpty ? frame.trackProgress : Double(landed.count) / Double(dots.count)
            // Never exactly 0 on a session that has a tonnage: the face drops a
            // zero figure, and the grid would reflow when the first set lands.
            live.tonnageKg = masthead.tonnageKg > 0 ? max(masthead.tonnageKg * share, 1) : 0
            live.prCount = frame.recordsLit ? masthead.prCount : 0
            return live
        }
    }

    // MARK: - Building

    public static func timeline(_ input: Input, duration: Double = SessionReplay.duration) -> Timeline {
        // A zero length would divide every phase by zero.
        let duration = max(duration, 0.1)
        let span = input.end.timeIntervalSince(input.start)
        let trace = span > 0 ? resample(input.samples, start: input.start, span: span) : []
        let mode: Mode = trace.count >= 2 ? .trace : .tonnage

        var bars: [Bar] = []
        var xs: [Double]
        switch mode {
        case .trace:
            xs = clocked(input.sets, start: input.start, span: span)
        case .tonnage:
            bars = segments(input.movements, sets: input.sets)
            xs = input.sets.map { _ in 0 }
            // Each movement's sets spaced evenly inside its own segment.
            for (m, bar) in bars.enumerated() {
                let own = input.sets.indices.filter { input.sets[$0].movement == m }
                for (k, i) in own.enumerated() {
                    xs[i] = bar.from + (Double(k) + 0.5) / Double(own.count) * (bar.to - bar.from)
                }
            }
        }

        let drop = dropFraction * duration
        let dots = zip(input.sets, xs).map { mark, x in
            Dot(
                x: x,
                y: mode == .trace ? height(of: trace, at: x) : 0.5,
                appearAt: dotsStart * duration + x * ((dotsEnd - dotsStart) * duration - drop),
                movement: mark.movement,
                records: max(mark.records, 0)
            )
        }
        // Along the track, stable — a clock that went backwards (two devices)
        // must not make a dot drop before the one it follows on screen.
        .enumerated().sorted { ($0.element.x, $0.offset) < ($1.element.x, $1.offset) }.map(\.element)

        var keyframes = [Keyframe(at: 0, kind: .trackBegins)]
        keyframes += dots.indices.map { Keyframe(at: dots[$0].appearAt, kind: .dot($0)) }
        keyframes.append(Keyframe(at: trackEnd * duration, kind: .trackEnds))
        if dots.contains(where: \.isRecord) {
            keyframes.append(Keyframe(at: recordsStart * duration, kind: .recordsFlash))
        }
        keyframes.append(Keyframe(at: settleStart * duration, kind: .settleBegins))
        keyframes.append(Keyframe(at: duration, kind: .end))
        keyframes = keyframes.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)

        return Timeline(duration: duration, mode: mode, trace: trace, bars: bars, dots: dots,
                        masthead: input.masthead, movements: input.movements, keyframes: keyframes)
    }

    /// The series as at most `tracePoints` means over equal slices of the
    /// session, normalised to its own range. An empty slice is skipped rather
    /// than zeroed — a gap in the watch's sampling is not a heart rate of 0.
    static func resample(_ samples: [HRSample], start: Date, span: TimeInterval) -> [Point] {
        var sums = [Double](repeating: 0, count: tracePoints)
        var counts = [Int](repeating: 0, count: tracePoints)
        for sample in samples {
            let f = sample.at.timeIntervalSince(start) / span
            guard f >= 0, f <= 1, sample.bpm > 0 else { continue }
            let slot = min(Int(f * Double(tracePoints)), tracePoints - 1)
            sums[slot] += Double(sample.bpm)
            counts[slot] += 1
        }
        let means = (0..<tracePoints).compactMap { i -> (x: Double, bpm: Double)? in
            counts[i] > 0 ? ((Double(i) + 0.5) / Double(tracePoints), sums[i] / Double(counts[i])) : nil
        }
        guard let lo = means.map(\.bpm).min(), let hi = means.map(\.bpm).max() else { return [] }
        return means.map { Point(x: $0.x, y: hi > lo ? ($0.bpm - lo) / (hi - lo) : 0.5) }
    }

    /// Each set's place in time, 0…1. A set with no clock sits on the straight
    /// line between the nearest clocked neighbours (or the session's ends); with
    /// no clocks at all, the sets are spaced evenly — the order is still true.
    static func clocked(_ sets: [SetMark], start: Date, span: TimeInterval) -> [Double] {
        let n = sets.count
        let known: [Double?] = sets.map { mark in
            mark.at.map { min(max($0.timeIntervalSince(start) / span, 0), 1) }
        }
        guard known.contains(where: { $0 != nil }) else {
            return (0..<n).map { (Double($0) + 0.5) / Double(n) }
        }
        return (0..<n).map { i in
            if let x = known[i] { return x }
            let before = known[..<i].lastIndex { $0 != nil }
            let after = known[(i + 1)...].firstIndex { $0 != nil }
            let (i0, x0) = before.map { ($0, known[$0]!) } ?? (-1, 0)
            let (i1, x1) = after.map { ($0, known[$0]!) } ?? (n, 1)
            return x0 + (x1 - x0) * Double(i - i0) / Double(i1 - i0)
        }
    }

    /// The trace's height at `x`, on the straight line between its points.
    static func height(of trace: [Point], at x: Double) -> Double {
        guard let first = trace.first, let last = trace.last else { return 0.5 }
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }
        let i = trace.firstIndex { $0.x >= x }!
        let a = trace[i - 1], b = trace[i]
        return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
    }

    /// The tonnage bar: each movement's width is HALF its share of the work and
    /// half its share of the sets, with a floor. Pure tonnage (the first
    /// draft) crowded a bodyweight movement's four sets into 4 % of the bar —
    /// a knot of dots at the end of the first shot. All zero → the set share.
    static func segments(_ movements: [Movement], sets: [SetMark]) -> [Bar] {
        guard !movements.isEmpty else { return [] }
        let total = movements.reduce(0) { $0 + max($1.tonnageKg, 0) }
        let counts = movements.indices.map { m in Double(sets.filter { $0.movement == m }.count) }
        let setTotal = counts.reduce(0, +)
        let raw = movements.indices.map { m -> Double in
            let work = total > 0 ? max(movements[m].tonnageKg, 0) / total : nil
            let share = setTotal > 0 ? counts[m] / setTotal : 1 / Double(movements.count)
            return max(work.map { 0.5 * $0 + 0.5 * share } ?? share, minSegment)
        }
        let sum = raw.reduce(0, +)
        var from = 0.0
        return raw.enumerated().map { i, w in
            let to = i == raw.count - 1 ? 1 : from + w / sum
            defer { from = to }
            return Bar(movement: i, from: from, to: to)
        }
    }
}
