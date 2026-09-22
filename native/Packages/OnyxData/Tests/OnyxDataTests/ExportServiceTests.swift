import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// The export path, end to end without a network (W7).
///
/// `ExportEnvelopeTests` in OnyxCore pins the wire and the range arithmetic.
/// This is the store half: that the builder really does render a span that is
/// not a week, that the marker advances only when a document is actually built,
/// and that the row the drop-box receives is the shape `w7-exports.sql`
/// creates.
@Suite("Export service — one envelope, three surfaces")
struct ExportServiceTests {
    private let user = "00000000-0000-0000-0000-000000000001"

    private func store() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        try db.editUserGoals(userId: user) { row in
            row.calorieGoal = 2000; row.proteinGoalG = 170; row.carbsGoalG = 200; row.fatGoalG = 60
            row.stepsGoal = 10000; row.waterGoalMl = 3000; row.sleepGoalHours = 8
            row.activeLever = "custom"
        }
        // No day rows. Every claim below is about the SPAN — how many days it
        // renders, what they are called, and where the marker lands — and a day
        // with nothing behind it renders exactly as the document says it does.
        return db
    }

    private func defaults() throws -> (UserDefaults, String) {
        let suite = "onyx.test.export.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    /// The claim the range picker rests on: a span that is not seven days long
    /// and does not start on a Sunday renders exactly those days, with their own
    /// weekday names.
    @Test("a three-day span renders three days, named for the days they are")
    func partialSpan() throws {
        let db = try store()
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let service = ExportService(database: db, userId: user)
        let envelope = try service.envelope(
            span: ExportSpan(start: "2026-09-14", end: "2026-09-16"),
            today: "2026-09-16", now: Date(timeIntervalSince1970: 1_790_073_000), defaults: defaults)

        #expect(envelope.input.days.count == 3)
        #expect(envelope.input.days.map(\.date) == ["2026-09-14", "2026-09-15", "2026-09-16"])
        // 2026-09-14 is a Monday. The old `weekdayLabels[i]` would have said
        // "Sun" for it, because `i` was the offset from the span's first day.
        #expect(envelope.input.days.map(\.weekdayLabel) == ["Mon", "Tue", "Wed"])
        #expect(envelope.rangeStart == "2026-09-14" && envelope.rangeEnd == "2026-09-16")
        #expect(envelope.markdown.contains("2026-09-14 → 2026-09-16"))
        #expect(envelope.fileStem == "onyx-week-2026-09-14-to-2026-09-16")
    }

    /// And the ordinary case is unchanged: a whole week from its first day is
    /// what it always was, by the same entry point every other caller uses.
    @Test("a whole week through either entry point is the same document")
    func wholeWeekIsUnchanged() throws {
        let db = try store()
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let builder = WeeklyExportBuilder(database: db, userId: user, timeZone: TimeZone(identifier: "UTC")!)
        let viaWeek = try builder.input(weekStart: "2026-09-13", today: "2026-09-19")
        let viaSpan = try builder.input(
            span: ExportSpan(start: "2026-09-13", end: "2026-09-19"), today: "2026-09-19")
        #expect(viaWeek == viaSpan)
        #expect(viaWeek.days.count == 7)
        #expect(viaWeek.days.map(\.weekdayLabel) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    }

    /// ── BUILDING IS NOT HANDING OVER ───────────────────────────────────────
    /// The marker moves only when a caller says the document actually left —
    /// the chip says so from `UIActivityViewController`'s completion handler,
    /// and the Shortcuts action says so by returning the files. A build that
    /// nobody shared must not advance it, or "since last export" skips days no
    /// model was ever shown and never offers them again.
    @Test("the marker moves only when a caller asks for it to")
    func markerAdvances() throws {
        let db = try store()
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ExportService(database: db, userId: user)

        // Nothing exported yet: "since last export" is this week.
        #expect(service.span(for: .sinceLastExport, today: "2026-09-16", defaults: defaults)
                == ExportSpan(start: "2026-09-13", end: "2026-09-16"))
        // A plain build leaves it alone.
        _ = try service.envelope(range: .sinceLastExport, today: "2026-09-16", defaults: defaults)
        #expect(ExportLog.exportedThrough(in: defaults) == nil)
        // Asking for it moves it.
        _ = try service.envelope(
            range: .sinceLastExport, today: "2026-09-16", defaults: defaults, recordingMarker: true)
        #expect(ExportLog.exportedThrough(in: defaults) == "2026-09-16")
        // The next one starts the day after.
        #expect(service.span(for: .sinceLastExport, today: "2026-09-18", defaults: defaults)
                == ExportSpan(start: "2026-09-17", end: "2026-09-18"))
        // And a deliberate re-export of an older week does not wind it back.
        _ = try service.envelope(
            range: .lastWeek, today: "2026-09-18", defaults: defaults, recordingMarker: true)
        #expect(ExportLog.exportedThrough(in: defaults) == "2026-09-16")
    }

    @Test("the span follows the athlete's own week start")
    func weekStartDay() throws {
        let db = try store()
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ExportService(database: db, userId: user)
        // `week_end_day` 0 (Sunday) means the week STARTS Monday.
        try db.editUserGoals(userId: user) { $0.weekEndDay = 0 }
        #expect(service.span(for: .thisWeek, today: "2026-09-17", defaults: defaults)
                == ExportSpan(start: "2026-09-14", end: "2026-09-17"))
        try db.editUserGoals(userId: user) { $0.weekEndDay = 6 }
        #expect(service.span(for: .thisWeek, today: "2026-09-17", defaults: defaults)
                == ExportSpan(start: "2026-09-13", end: "2026-09-17"))
    }

    /// A span longer than the cap is clamped by the SERVICE, not only by the
    /// range resolver — a caller handing in its own `ExportSpan` must not be
    /// able to ask for a year.
    @Test("a hand-made span is clamped too")
    func handMadeSpanIsClamped() throws {
        let db = try store()
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let envelope = try ExportService(database: db, userId: user).envelope(
            span: ExportSpan(start: "2026-01-01", end: "2026-09-16"),
            today: "2026-09-16", defaults: defaults)
        #expect(envelope.input.days.count == ExportRange.maxDays)
        #expect(envelope.rangeStart == "2026-08-20")

        // And a span that runs into the FUTURE is cut at today: days that have
        // not happened are not a record of anything.
        let ahead = try ExportService(database: db, userId: user).envelope(
            span: ExportSpan(start: "2026-09-14", end: "2026-12-31"),
            today: "2026-09-16", defaults: defaults)
        #expect(ahead.rangeEnd == "2026-09-16")
        #expect(ahead.input.days.count == 3)
    }

    // MARK: - The drop-box

    /// What `upload` sends, captured. The four columns beside the JSON are what
    /// `w7-exports.sql` indexes, so a rename here is a rename there.
    private final class Capture: MirrorPushRemote, @unchecked Sendable {
        var table: String?
        var conflict: String?
        var body: [String: Any]?
        func upsertRow<T: Encodable & Sendable>(_ row: T, table: String, conflict: String, nulls: [String]) async throws {
            self.table = table
            self.conflict = conflict
            self.body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]
        }
        func deleteRow(table: String, key: [String: String]) async throws {}
    }

    @Test("the uploaded row is the shape the exports table has")
    func uploadShape() async throws {
        let db = try store()
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ExportService(database: db, userId: user)
        let envelope = try service.envelope(
            span: ExportSpan(start: "2026-09-14", end: "2026-09-16"),
            today: "2026-09-16", defaults: defaults)

        let remote = Capture()
        try await service.upload(envelope, via: remote)

        #expect(remote.table == "exports")
        #expect(remote.conflict == "user_id,range_start,range_end")
        let body = try #require(remote.body)
        #expect(Set(body.keys) == ["user_id", "range_start", "range_end", "version", "envelope"])
        #expect(body["user_id"] as? String == user)
        #expect(body["range_start"] as? String == "2026-09-14")
        #expect(body["range_end"] as? String == "2026-09-16")
        #expect(body["version"] as? Int == 6)
        // And the jsonb column really is the whole envelope.
        let inner = try #require(body["envelope"] as? [String: Any])
        #expect(Set(inner.keys) == ["version", "rangeStart", "rangeEnd", "generatedAt", "input", "markdown"])
    }
}
