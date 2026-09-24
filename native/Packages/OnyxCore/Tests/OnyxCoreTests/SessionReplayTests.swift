import Foundation
import Testing
@testable import OnyxCore

/// Overhaul W5 — the Session Replay timeline. The views draw `frame(at:)` and
/// nothing else, so every promise the replay makes about timing is made here.
@Suite("Session replay — timeline invariants")
struct SessionReplayTests {

    static let start = Date(timeIntervalSince1970: 1_790_000_000)
    static let end = start.addingTimeInterval(60 * 60)

    static func masthead(prs: Int) -> SessionMasthead {
        SessionMasthead(name: "Upper A", durationSec: 3_600, tonnageKg: 8_450, avgBpm: 131,
                        prCount: prs, hrSpark: [], startedAt: start)
    }

    /// Three movements, eight sets, two records, one set with no clock.
    static func input(hr: Bool) -> SessionReplay.Input {
        let movements = [
            SessionReplay.Movement(name: "Incline DB Press", tonnageKg: 2_400),
            SessionReplay.Movement(name: "Chest Supported Row", tonnageKg: 3_000),
            SessionReplay.Movement(name: "Cable Pushdown", tonnageKg: 0),
        ]
        func at(_ minute: Double?) -> Date? { minute.map { start.addingTimeInterval($0 * 60) } }
        let sets = [
            SessionReplay.SetMark(movement: 0, at: at(4), records: 0),
            SessionReplay.SetMark(movement: 0, at: at(8), records: 2),
            SessionReplay.SetMark(movement: 0, at: at(12), records: 0),
            SessionReplay.SetMark(movement: 1, at: at(20), records: 0),
            SessionReplay.SetMark(movement: 1, at: nil, records: 0),
            SessionReplay.SetMark(movement: 1, at: at(30), records: 1),
            SessionReplay.SetMark(movement: 2, at: at(40), records: 0),
            SessionReplay.SetMark(movement: 2, at: at(50), records: 0),
        ]
        let samples = hr
            ? stride(from: 0.0, to: 3_600, by: 20).map {
                HRSample(at: start.addingTimeInterval($0), bpm: Int(110 + 25 * sin($0 / 300)))
            }
            : []
        return SessionReplay.Input(masthead: masthead(prs: 3), start: start, end: end,
                                   samples: samples, movements: movements, sets: sets)
    }

    @Test("keyframes are monotonic, start at 0 and end at the duration", arguments: [true, false])
    func keyframesAreMonotonic(hr: Bool) {
        for duration in [SessionReplay.duration, SessionReplay.watchDuration] {
            let timeline = SessionReplay.timeline(Self.input(hr: hr), duration: duration)
            let times = timeline.keyframes.map(\.at)
            #expect(times == times.sorted(), "keyframes out of order at \(duration) s")
            #expect(times.first == 0)
            #expect(times.last == duration)
            #expect(timeline.keyframes.last?.kind == .end)
        }
    }

    @Test("every set has exactly one dot, dropping inside 2–8 s, in order along the track", arguments: [true, false])
    func everySetHasADot(hr: Bool) {
        let timeline = SessionReplay.timeline(Self.input(hr: hr))
        #expect(timeline.mode == (hr ? .trace : .tonnage))
        #expect(timeline.dots.count == 8)
        #expect(timeline.keyframes.filter { if case .dot = $0.kind { true } else { false } }.count == 8)
        for dot in timeline.dots {
            #expect(dot.appearAt >= 2 && dot.appearAt + SessionReplay.dropFraction * 10 <= 8 + 1e-9)
            #expect((0...1).contains(dot.x) && (0...1).contains(dot.y))
        }
        #expect(timeline.dots.map(\.appearAt) == timeline.dots.map(\.appearAt).sorted())
        #expect(timeline.dots.map(\.x) == timeline.dots.map(\.x).sorted())
        // Each movement keeps its own sets.
        #expect(timeline.dots.map(\.movement) == [0, 0, 0, 1, 1, 1, 2, 2])
    }

    @Test("a dot never lands on a stretch of trace (or bar) that has not been drawn yet", arguments: [true, false])
    func dotsLandOnDrawnTrack(hr: Bool) {
        let timeline = SessionReplay.timeline(Self.input(hr: hr))
        for dot in timeline.dots {
            let frame = timeline.frame(at: dot.appearAt)
            #expect(frame.trackProgress >= dot.x - 1e-9, "dot at x \(dot.x) appears before the track reaches it")
        }
    }

    @Test("the record count matches the flagged sets and the masthead's trophy count")
    func recordCountMatches() {
        let timeline = SessionReplay.timeline(Self.input(hr: true))
        // Two record SETS, three record AXES — the trophy counts axes.
        #expect(timeline.dots.filter(\.isRecord).count == 2)
        #expect(timeline.recordCount == 3)
        #expect(timeline.recordCount == timeline.masthead.prCount)
        #expect(timeline.keyframes.contains { $0.kind == .recordsFlash && $0.at == 8 })
    }

    @Test("no records, no flash keyframe")
    func noRecordsNoFlash() {
        var input = Self.input(hr: true)
        input.sets = input.sets.map { SessionReplay.SetMark(movement: $0.movement, at: $0.at) }
        let timeline = SessionReplay.timeline(input)
        #expect(timeline.recordCount == 0)
        #expect(!timeline.keyframes.contains { $0.kind == .recordsFlash })
        #expect(timeline.frame(at: 8.5).recordGlow == 0)
    }

    @Test("the phases: trace 0–6 s, records flash 8–9 s, masthead settles 9–10 s")
    func phases() {
        let timeline = SessionReplay.timeline(Self.input(hr: true))
        #expect(timeline.frame(at: 0).trackProgress == 0)
        #expect(abs(timeline.frame(at: 3).trackProgress - 0.5) < 1e-9)
        #expect(timeline.frame(at: 6).trackProgress == 1)
        #expect(timeline.frame(at: 7.9).recordGlow == 0)
        #expect(timeline.frame(at: 8.5).recordGlow > 0.99)
        #expect(!timeline.frame(at: 7.9).recordsLit)
        #expect(timeline.frame(at: 9.5).recordsLit)
        #expect(timeline.frame(at: 8.99).settle == 0)
        #expect(abs(timeline.frame(at: 9.5).settle - 0.5) < 1e-9)
        #expect(timeline.frame(at: 10).settle == 1)
        // Before its drop a dot is absent; after it, landed.
        let dot = timeline.dots[3]
        #expect(timeline.frame(at: dot.appearAt - 0.01).drops[3] == 0)
        #expect(timeline.frame(at: dot.appearAt + 1).drops[3] == 1)
    }

    @Test("the final frame is the whole picture — what Reduce Motion and the share frames draw")
    func finalFrame() {
        let timeline = SessionReplay.timeline(Self.input(hr: true))
        let last = timeline.final
        #expect(last.trackProgress == 1)
        #expect(last.drops.allSatisfy { $0 == 1 })
        #expect(last.settle == 1 && last.recordsLit && last.recordGlow == 0)
        #expect(last.currentMovement == 2)
        // Past the end clamps to the end.
        #expect(timeline.frame(at: 42) == last)
    }

    @Test("the condensed watch replay is the same keyframes, scaled to 3 s")
    func watchIsScaled() {
        let long = SessionReplay.timeline(Self.input(hr: true))
        let short = SessionReplay.timeline(Self.input(hr: true), duration: SessionReplay.watchDuration)
        #expect(short.keyframes.count == long.keyframes.count)
        for (a, b) in zip(long.keyframes, short.keyframes) {
            #expect(a.kind == b.kind)
            #expect(abs(a.at * 0.3 - b.at) < 1e-9)
        }
    }

    @Test("a set with no clock lands between its neighbours")
    func missingClockInterpolates() {
        let timeline = SessionReplay.timeline(Self.input(hr: true))
        // Minutes 20 and 30 of 60 → the untimed set sits at 25.
        #expect(abs(timeline.dots[4].x - 25.0 / 60) < 1e-9)
    }

    @Test("no clock at all spaces the sets evenly")
    func noClocksAreEven() {
        var input = Self.input(hr: true)
        input.sets = input.sets.map { SessionReplay.SetMark(movement: $0.movement, at: nil, records: $0.records) }
        let xs = SessionReplay.timeline(input).dots.map(\.x)
        #expect(xs.count == 8)
        #expect(abs(xs[0] - 0.5 / 8) < 1e-9 && abs(xs[7] - 7.5 / 8) < 1e-9)
    }

    @Test("tonnage mode: one bar segment per movement, proportional, the bodyweight one kept visible")
    func tonnageBars() {
        let timeline = SessionReplay.timeline(Self.input(hr: false))
        #expect(timeline.trace.isEmpty)
        #expect(timeline.bars.count == 3)
        #expect(timeline.bars.first?.from == 0 && timeline.bars.last?.to == 1)
        for (a, b) in zip(timeline.bars, timeline.bars.dropFirst()) { #expect(a.to == b.from) }
        let widths = timeline.bars.map { $0.to - $0.from }
        #expect(widths[1] > widths[0] && widths[2] > 0)
        // Every dot sits on its own movement's segment.
        for dot in timeline.dots {
            let bar = timeline.bars[dot.movement]
            #expect(dot.x > bar.from && dot.x < bar.to)
        }
        // A bar has grown fully by the time the track passes its end.
        #expect(timeline.frame(at: 6).bars.allSatisfy { $0 == 1 })
    }

    @Test("an empty session replays without dots and still settles")
    func empty() {
        let input = SessionReplay.Input(masthead: Self.masthead(prs: 0), start: Self.start, end: Self.end,
                                        samples: [], movements: [], sets: [])
        let timeline = SessionReplay.timeline(input)
        #expect(timeline.dots.isEmpty && timeline.bars.isEmpty)
        #expect(timeline.final.settle == 1)
        #expect(timeline.final.currentMovement == nil)
    }
}
