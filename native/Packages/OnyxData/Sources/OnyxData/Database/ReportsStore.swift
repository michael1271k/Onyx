import Foundation
import GRDB
import OnyxCore

/// One week of the reports list: the week, and the report on it if there is one.
///
/// ── WHY THE LIST IS WEEKS AND NOT ROWS ──────────────────────────────────────
/// Until W4 the only writer was the web (`useSentinelExport.ts`), so a week
/// with no row was a week that did not exist — the list drew what had been
/// saved and offered no way to save anything. Now the phone writes, and the
/// question the screen answers changed: not "what have I got" but "which weeks
/// am I missing". A week is therefore a first-class row whether or not it holds
/// a report, and the empty ones are the whole point of the screen.
public struct ReportWeek: Sendable, Equatable, Identifiable {
    /// ISO date of the week's first day, under the athlete's own week start.
    public let start: String
    /// ISO date of its last day.
    public let end: String
    /// The saved report, when one exists.
    public let report: ReportRow?
    /// The week the selected day falls in.
    public let isCurrent: Bool

    public var id: String { start }
    public var hasReport: Bool { report?.contentMd?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }

    public init(start: String, end: String, report: ReportRow?, isCurrent: Bool) {
        self.start = start
        self.end = end
        self.report = report
        self.isCurrent = isCurrent
    }
}

public extension AppDatabase {

    /// The weeks the list draws: every week from `today`'s back to the oldest
    /// one that holds a report, and never fewer than `minWeeks`.
    ///
    /// The floor exists so a fresh account still has somewhere to paste: with
    /// no reports at all the oldest-report bound is the current week, and a
    /// one-row list offering only "this week" hides the two the athlete is
    /// actually behind on. Twelve is a quarter.
    ///
    /// The athlete's own week start is read per tick rather than passed in, so
    /// moving `week_end_day` re-files every report without a relaunch.
    func reportWeeksStream(
        userId: String, today: String = LogicalDay.today(), minWeeks: Int = 12
    ) -> AsyncThrowingStream<[ReportWeek], any Error> {
        stream(ValueObservation.tracking { db in
            let startDay = Week.startDay(fromEndDay: try Self.weekEndDay(db, userId: userId))
            let rows = try Self.bodiedReports(db, userId: userId)
            return Self.weeks(rows, today: today, startDay: startDay, minWeeks: minWeeks)
        })
    }

    /// Pure, so the shape of the list is testable without a store.
    static func weeks(
        _ rows: [ReportRow], today: String, startDay: Int, minWeeks: Int
    ) -> [ReportWeek] {
        let current = Week.start(of: today, startDay: startDay)
        // Keyed on the week the report's own `period_start` FALLS IN, not on
        // the stored string: a row written under a different week start (the
        // web's, or the athlete's before they moved it) is still that week's
        // report, and matching on the raw date would file it under no week at
        // all and offer "Add report" over the top of it.
        var byWeek: [String: ReportRow] = [:]
        for row in rows {
            let key = Week.start(of: row.periodStart, startDay: startDay)
            // Newest first is the caller's order; the first row to claim a week
            // keeps it, so a duplicate never displaces the one being read.
            if byWeek[key] == nil { byWeek[key] = row }
        }
        let oldest = byWeek.keys.min() ?? current
        var out: [ReportWeek] = []
        var cursor = current
        while out.count < minWeeks || cursor >= oldest {
            let end = ISODate.addDays(cursor, 6) ?? cursor
            out.append(ReportWeek(start: cursor, end: end, report: byWeek[cursor], isCurrent: cursor == current))
            guard let previous = ISODate.addDays(cursor, -7), previous < cursor else { break }
            cursor = previous
        }
        return out
    }

    /// One report's body, read at open time rather than carried in the list.
    ///
    /// The bodies run 16 kB to 40 kB and grow every week; holding twenty of them
    /// in a list model to show twenty date rows is a megabyte of strings the
    /// screen never draws.
    func reportBody(id: String, userId: String) throws -> String? {
        try writer.read { db in
            try String.fetchOne(
                db, sql: "SELECT content_md FROM reports WHERE id = ? AND user_id = ?", arguments: [id, userId]
            )
        }
    }

    /// Save a week's report — the first native writer this table has had.
    ///
    /// ── KEYED ON THE WEEK, NOT ON THE ROW ───────────────────────────────────
    /// The mirror pushes `reports` on `id`, but the fact being written is "this
    /// is the report for the week of the 23rd", and a second row for a week
    /// that already has one is two answers to a one-answer question. So the
    /// week is looked up FIRST — across every row, stubs included, because a
    /// Notion-era stub for that week is the row this text belongs in — and only
    /// a week with nothing at all mints an id.
    ///
    /// ── AND THE LOOKUP IS A RANGE, NOT AN EQUALITY ──────────────────────────
    /// `weeks(_:today:startDay:)` files a row under the week its `period_start`
    /// FALLS IN, which is not always the string the row holds: one written by
    /// the web under a Monday start shows under the Sunday the athlete's week
    /// begins on (`weekStartDrift` pins exactly that case). Matching
    /// `period_start ==` therefore missed the very row the reader had open — it
    /// minted a SECOND row for the week, which the list then hid behind the
    /// first, so an edit disappeared and a Remove silently did nothing while
    /// both reported success. The range the screen offered IS the week, so the
    /// range is the key.
    ///
    /// An empty body DELETES — every row in the range, not the first. There is
    /// no other way to take back a paste that went to the wrong week, and a row
    /// whose body is whitespace is a row the list would offer and the reader
    /// would find blank.
    @discardableResult
    func saveReport(
        userId: String, periodStart: String, periodEnd: String,
        markdown: String, type: String = "sentinel7", now: Date = Date()
    ) throws -> String? {
        let body = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return try writer.write { db in
            let inTheWeek = try ReportRow
                .filter(Column("user_id") == userId)
                .filter(Column("period_start") >= periodStart && Column("period_start") <= periodEnd)
                .order(Column("created_at").desc)
                .fetchAll(db)

            guard !body.isEmpty else {
                for row in inTheWeek {
                    try row.delete(db)
                    try Self.enqueueRowDelete(table: ReportRow.databaseTableName, key: ["id": row.id], in: db)
                }
                return nil
            }

            // The newest row in the week is the one being edited; anything else
            // in the range is a duplicate, and it goes rather than shadowing
            // what was just written.
            let existing = inTheWeek.first
            for shadow in inTheWeek.dropFirst() {
                try shadow.delete(db)
                try Self.enqueueRowDelete(table: ReportRow.databaseTableName, key: ["id": shadow.id], in: db)
            }

            var row = existing ?? ReportRow(
                id: newOnyxID(), userId: userId, type: type,
                periodStart: periodStart, periodEnd: periodEnd, createdAt: now
            )
            row.contentMd = body
            // The range is restated on every save: a stub written by Notion
            // carries whatever end date that era used, and the week the athlete
            // is actually filing under is the one the screen offered.
            row.periodEnd = periodEnd
            // The TYPE is left alone on an existing row. A web-written
            // `sentinel7` stays `sentinel7`; only a row this device mints takes
            // the default, and nothing reads the column anyway (the FMT test is
            // a regex on the body).
            try row.save(db)
            try Self.enqueueRowUpsert(table: ReportRow.databaseTableName, id: row.id, in: db)
            return row.id
        }
    }

    // MARK: - Helpers

    /// ── ONLY THE ONES WITH A BODY ──────────────────────────────────────────
    /// `content_md` is nullable and nine of the fifteen rows are Notion-era
    /// stubs — a type, a date range and nothing to read. A week holding one of
    /// those is a week with no report, and the list offers to fill it.
    ///
    /// No type filter: the FMT v2 test is a regex on the BODY, not a column, so
    /// a `weekly` row whose text says "FMT v2" is a v2 report and renders as
    /// one. Filtering on `type = 'sentinel7'` here would hide it.
    private static func bodiedReports(_ db: Database, userId: String) throws -> [ReportRow] {
        try ReportRow
            .filter(Column("user_id") == userId)
            .filter(sql: "content_md IS NOT NULL AND trim(content_md) <> ''")
            .order(Column("period_start").desc, Column("created_at").desc)
            .fetchAll(db)
    }

    /// The athlete's week end, or Saturday. The stream is started from a
    /// signed-in screen with the session's own id (W11), so the row is theirs.
    private static func weekEndDay(_ db: Database, userId: String) throws -> Int? {
        try UserGoalRow.filter(Column("user_id") == userId).fetchOne(db)?.weekEndDay
    }
}
