import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Expansion W5 — whose workout it is, which one wins, and how a heart-rate
// series is cut into movements. Three fixtures, hand-computed.
// ─────────────────────────────────────────────────────────────────────────────

private func seconds(_ s: Double) -> Date { Date(timeIntervalSince1970: s) }

// MARK: - workout-origin.json

private struct OriginInput: Decodable {
    let sourceBundleId: String?
    let sourceName: String?
    let ownBundleId: String
}

private struct OriginExpected: Decodable {
    let kind: String
    let name: String?

    var origin: WorkoutOrigin {
        kind == "own" ? .own : .foreign(name ?? "")
    }
}

@Suite("Workout provenance — origin")
struct WorkoutOriginGoldenTests {
    @Test("every case in workout-origin.json")
    func origin() throws {
        let fixture = try GoldenFixture<OriginInput, OriginExpected>.load("workout-origin")
        for c in fixture.cases {
            let got = WorkoutProvenance.origin(
                sourceBundleId: c.input.sourceBundleId, sourceName: c.input.sourceName, ownBundleId: c.input.ownBundleId
            )
            #expect(got == c.expected.origin, "\(c.name)")
        }
    }
}

// MARK: - workout-pick.json

private struct PickInput: Decodable {
    struct Interval: Decodable { let start: Double; let end: Double }
    struct Candidate: Decodable {
        let origin: String
        let isLifting: Bool
        let start: Double
        let end: Double

        var value: WorkoutProvenance.Candidate {
            let origin: WorkoutOrigin = self.origin == "own"
                ? .own
                : .foreign(String(self.origin.dropFirst("foreign:".count)))
            return .init(origin: origin, isLifting: isLifting, start: seconds(start), end: seconds(end))
        }
    }
    let session: Interval
    let slack: Double
    let candidates: [Candidate]
}

private struct PickExpected: Decodable {
    let kind: String
    let index: Int?

    var pick: WorkoutProvenance.Pick {
        switch kind {
        case "own": .own(index!)
        case "foreign": .foreign(index!)
        default: .none
        }
    }
}

@Suite("Workout provenance — precedence")
struct WorkoutPickGoldenTests {
    @Test("every case in workout-pick.json")
    func pick() throws {
        let fixture = try GoldenFixture<PickInput, PickExpected>.load("workout-pick")
        for c in fixture.cases {
            let got = WorkoutProvenance.pick(
                c.input.candidates.map(\.value),
                sessionStart: seconds(c.input.session.start), sessionEnd: seconds(c.input.session.end),
                slack: c.input.slack
            )
            #expect(got == c.expected.pick, "\(c.name)")
        }
    }

    @Test("a foreign pick is never an own one, whatever the order")
    func foreignNeverPromoted() {
        let s = seconds(0), e = seconds(3600)
        let hevy = WorkoutProvenance.Candidate(origin: .foreign("Hevy"), isLifting: true, start: s, end: e)
        #expect(WorkoutProvenance.pick([hevy, hevy, hevy], sessionStart: s, sessionEnd: e) == .foreign(0))
    }
}

// MARK: - hr-segments.json

private struct SegmentsFixture: Decodable {
    struct Sample: Decodable { let at: Double; let bpm: Int }
    struct Marker: Decodable { let kind: String; let exerciseId: String?; let at: Double }
    struct Input: Decodable { let sessionStart: Double; let sessionEnd: Double; let markers: [Marker] }
    struct Segment: Decodable {
        let exerciseId: String; let start: Double; let end: Double
        let avgBpm: Int?; let maxBpm: Int?; let continues: Bool
    }
    struct Summary: Decodable { let avgBpm: Int?; let maxBpm: Int? }
    struct Expected: Decodable { let segments: [Segment]; let summary: Summary }
    struct Case: Decodable { let name: String; let input: Input; let expected: Expected }

    let samples: [Sample]
    let cases: [Case]

    static func load() throws -> SegmentsFixture {
        guard let url = Bundle.module.url(forResource: "hr-segments", withExtension: "json", subdirectory: "Fixtures") else {
            throw GoldenError.missing("hr-segments")
        }
        return try JSONDecoder().decode(SegmentsFixture.self, from: Data(contentsOf: url))
    }
}

@Suite("HR segments")
struct HRSegmentsGoldenTests {
    @Test("every case in hr-segments.json")
    func segments() throws {
        let fixture = try SegmentsFixture.load()
        let samples = fixture.samples.map { HRSample(at: seconds($0.at), bpm: $0.bpm) }
        for c in fixture.cases {
            let markers: [HRSegments.Marker] = c.input.markers.map { m in
                switch m.kind {
                case "set": .set(exerciseId: m.exerciseId!, at: seconds(m.at))
                case "pause": .pause(at: seconds(m.at))
                default: .resume(at: seconds(m.at))
                }
            }
            let start = seconds(c.input.sessionStart), end = seconds(c.input.sessionEnd)
            let got = HRSegments.build(markers: markers, samples: samples, sessionStart: start, sessionEnd: end)
            let want = c.expected.segments.map {
                HRSegment(exerciseId: $0.exerciseId, start: seconds($0.start), end: seconds($0.end),
                          avgBpm: $0.avgBpm, maxBpm: $0.maxBpm, continues: $0.continues)
            }
            #expect(got == want, "\(c.name)")
            let summary = HRSegments.summary(markers: markers, samples: samples, sessionStart: start, sessionEnd: end)
            #expect(summary.avgBpm == c.expected.summary.avgBpm, "\(c.name) — avg")
            #expect(summary.maxBpm == c.expected.summary.maxBpm, "\(c.name) — max")
        }
    }

    @Test("segments never overlap and never leave the session")
    func invariants() throws {
        let fixture = try SegmentsFixture.load()
        let samples = fixture.samples.map { HRSample(at: seconds($0.at), bpm: $0.bpm) }
        for c in fixture.cases {
            let markers: [HRSegments.Marker] = c.input.markers.map { m in
                switch m.kind {
                case "set": .set(exerciseId: m.exerciseId!, at: seconds(m.at))
                case "pause": .pause(at: seconds(m.at))
                default: .resume(at: seconds(m.at))
                }
            }
            let start = seconds(c.input.sessionStart), end = seconds(c.input.sessionEnd)
            let got = HRSegments.build(markers: markers, samples: samples, sessionStart: start, sessionEnd: end)
            for (i, s) in got.enumerated() {
                #expect(s.start < s.end && s.start >= start && s.end <= end, "\(c.name) — piece \(i)")
                if i > 0 { #expect(got[i - 1].end <= s.start, "\(c.name) — pieces \(i - 1)/\(i) overlap") }
            }
        }
    }
}
