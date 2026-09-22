import Foundation
import Testing
@testable import OnyxCore

/// The envelope and the range picker behind it (W7).
///
/// ── WHY THE ROUND TRIP IS A TEST AND NOT AN ASSUMPTION ──────────────────────
/// `ExportEnvelope` is the wire between four processes that do not share a
/// compiler: the app writes it, a Shortcuts action hands it on as a file, a
/// `jsonb` column stores it, and an MCP server in Node reads it back. Every one
/// of those reads the KEY NAMES. A renamed property is a silent break in three
/// of them, so the key set is pinned here as a literal.
@Suite("Export envelope — the one wire")
struct ExportEnvelopeTests {

    private struct SpanIn: Decodable {
        let range: String
        let today: String
        let weekStartDay: Int
        let exportedThrough: String?
    }

    private struct SpanOut: Decodable {
        let start: String
        let end: String
        let days: Int
    }

    @Test("the range vector replays")
    func rangeGolden() throws {
        for c in try GoldenFixture<SpanIn, SpanOut>.load("export-range").cases {
            let range = try #require(ExportRange(rawValue: c.input.range), "\(c.name): unknown range")
            let span = range.span(
                today: c.input.today,
                weekStartDay: c.input.weekStartDay,
                exportedThrough: c.input.exportedThrough
            )
            #expect(span.start == c.expected.start, "\(c.name): start")
            #expect(span.end == c.expected.end, "\(c.name): end")
            #expect(span.dayCount == c.expected.days, "\(c.name): days")
            #expect(span.dates.first == c.expected.start, "\(c.name): first date")
            #expect(span.dates.last == c.expected.end, "\(c.name): last date")
        }
    }

    /// The property the vector's cases are samples of. Whatever the range and
    /// whatever the marker, a span is ordered, non-empty, ends today, and never
    /// exceeds the cap — those four are what the builder is allowed to assume.
    @Test("every span is ordered, non-empty, capped, and ends no later than today")
    func spansAreSane() {
        let today = "2026-09-17"
        let markers: [String?] = [nil, "2026-09-16", "2026-09-17", "2026-01-01", "2027-01-01", "not-a-date"]
        for range in ExportRange.allCases {
            for startDay in [0, 1] {
                for marker in markers {
                    let span = range.span(today: today, weekStartDay: startDay, exportedThrough: marker)
                    #expect(span.start <= span.end, "\(range) \(startDay) \(marker ?? "nil"): inverted")
                    #expect(span.dayCount >= 1, "\(range) \(startDay) \(marker ?? "nil"): empty")
                    #expect(span.dayCount <= ExportRange.maxDays, "\(range) \(startDay) \(marker ?? "nil"): over the cap")
                    #expect(span.end <= today, "\(range) \(startDay) \(marker ?? "nil"): ends in the future")
                }
            }
        }
    }

    /// A marker that is not a date is not a marker. `ExportLog` refuses to
    /// store one; the resolver has to survive one arriving anyway, because the
    /// defaults suite is shared storage another build could have written.
    @Test("an unreadable marker falls back to this week")
    func rubbishMarker() {
        let span = ExportRange.sinceLastExport.span(today: "2026-09-17", weekStartDay: 0, exportedThrough: "yesterday")
        #expect(span.start == "2026-09-13")
        #expect(span.end == "2026-09-17")
    }

    // MARK: - The wire

    private static let minimalInput = WeeklyExportInput(
        weekStart: "2026-09-14", weekEnd: "2026-09-20", weekLabel: nil,
        programLabel: "Upper/Lower", calorieGoal: nil, proteinGoalG: nil,
        stepsGoal: nil, sleepGoalHours: nil, waterGoalMl: nil, phaseLabel: nil,
        targetPeriods: nil, days: [], sessions: [], volumeByMuscle: [],
        tonnageByMuscle: nil, doms: [], joints: nil, fatigue: nil, stress: nil,
        bodyComp: nil, cardio: nil, supplementProtocol: nil, ledger: nil,
        leverBaselineKcal: nil, anomalies: nil, protocolNotes: nil, insomnia: nil
    )

    /// The six top-level keys, exactly. Nothing outside this module can be made
    /// to fail when one of them is renamed, so it fails here.
    @Test("the envelope's wire keys are the six the MCP server and jsonb read")
    func wireKeys() throws {
        let envelope = ExportEnvelope.make(
            input: Self.minimalInput,
            span: ExportSpan(start: "2026-09-14", end: "2026-09-20"),
            generatedAt: "2026-09-22T10:30:00Z"
        )
        let object = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(envelope)) as? [String: Any]
        let keys = Set(try #require(object).keys)
        #expect(keys == ["version", "rangeStart", "rangeEnd", "generatedAt", "input", "markdown"])
    }

    @Test("an envelope survives encode → decode unchanged")
    func roundTrip() throws {
        let envelope = ExportEnvelope.make(
            input: Self.minimalInput,
            span: ExportSpan(start: "2026-09-14", end: "2026-09-20"),
            generatedAt: "2026-09-22T10:30:00Z"
        )
        // `.sortedKeys` because the claim is about BYTES, and `JSONEncoder`
        // makes no promise about key order between two calls. A canonical
        // encoding is what makes "encode → decode → encode is the same
        // document" a statement about the type rather than about Foundation.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        let back = try JSONDecoder().decode(ExportEnvelope.self, from: data)
        #expect(back == envelope)
        // And again, so a lossy field shows up as a difference between the two
        // encodings rather than as equality against a value it damaged twice.
        #expect(try encoder.encode(back) == data)
        #expect(back.version == 6)
    }

    /// The claim the whole wave rests on: the envelope carries the document the
    /// golden vectors pin, not a second rendering of it. Every case in
    /// `weekly-export.json` is wrapped and checked against its own expectation.
    @Test("the envelope's markdown is the golden document, for every vector case")
    func envelopeCarriesTheGoldenDocument() throws {
        struct Expected: Decodable { let markdown: String? }
        let fixture = try GoldenFixture<WeeklyExportInput, Expected>.load("weekly-export")
        var checked = 0
        for c in fixture.cases {
            guard let expected = c.expected.markdown else { continue }
            let envelope = ExportEnvelope.make(
                input: c.input,
                span: ExportSpan(start: c.input.weekStart, end: c.input.weekEnd),
                generatedAt: "2026-09-22T10:30:00Z"
            )
            #expect(envelope.markdown == expected, "\(c.name): the envelope re-rendered the document")
            checked += 1
        }
        #expect(checked > 0, "no vector case carried a document")
    }

    @Test("the file stem keeps the single-date name for a whole week")
    func fileStem() {
        let week = ExportEnvelope.make(
            input: Self.minimalInput,
            span: ExportSpan(start: "2026-08-30", end: "2026-09-05"),
            generatedAt: "2026-09-22T10:30:00Z")
        #expect(week.fileStem == "onyx-week-2026-08-30")
        let partial = ExportEnvelope.make(
            input: Self.minimalInput,
            span: ExportSpan(start: "2026-08-30", end: "2026-09-02"),
            generatedAt: "2026-09-22T10:30:00Z")
        #expect(partial.fileStem == "onyx-week-2026-08-30-to-2026-09-02")
    }

    @Test("the timestamp is ISO-8601 in UTC, whatever the device's zone")
    func timestamp() {
        // 2026-09-22T10:30:00Z.
        let date = Date(timeIntervalSince1970: 1_790_073_000)
        #expect(ExportEnvelope.timestamp(date) == "2026-09-22T10:30:00Z")
    }

    // MARK: - The marker

    @Test("the export marker only ever moves forward, and refuses a non-date")
    func exportLog() throws {
        let suite = "onyx.test.exportlog.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ExportLog.exportedThrough(in: defaults) == nil)
        ExportLog.record(through: "2026-09-12", in: defaults)
        #expect(ExportLog.exportedThrough(in: defaults) == "2026-09-12")
        // Exporting "last complete week" after "since last export" must not
        // make the next default re-export days that already went out.
        ExportLog.record(through: "2026-09-05", in: defaults)
        #expect(ExportLog.exportedThrough(in: defaults) == "2026-09-12")
        ExportLog.record(through: "2026-09-19", in: defaults)
        #expect(ExportLog.exportedThrough(in: defaults) == "2026-09-19")
        ExportLog.record(through: "tomorrow", in: defaults)
        #expect(ExportLog.exportedThrough(in: defaults) == "2026-09-19")
    }

    @Test("a nil defaults suite is not a crash")
    func exportLogWithoutDefaults() {
        ExportLog.record(through: "2026-09-12", in: nil)
        #expect(ExportLog.exportedThrough(in: nil) == nil)
    }
}
