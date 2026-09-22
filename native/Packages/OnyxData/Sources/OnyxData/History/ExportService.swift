import Foundation
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// THE ONE PLACE AN EXPORT IS MADE (W7).
//
// Three surfaces ask for one: the chip on a week, the Shortcuts action, and —
// once the founder has run `docs/sql/w7-exports.sql` — an MCP server reading
// what those two left behind. Each of them gets an `ExportEnvelope` from here
// and none of them builds one itself, because the moment two do, a document
// shared from the share sheet and a document a model read out of Supabase can
// disagree about the same week.
// ─────────────────────────────────────────────────────────────────────────────

public struct ExportService: Sendable {

    /// The table the envelope is filed in. Created by `docs/sql/w7-exports.sql`.
    ///
    /// NOT in the local mirror, and deliberately: the app never reads this
    /// table. It is the drop-box a desktop model reads, and mirroring it would
    /// mean carrying every envelope ever built in the phone's own store — a
    /// second copy of the whole document, for no reader.
    public static let table = "exports"
    /// `(user_id, range_start, range_end)` — the natural key. Re-exporting the
    /// same span replaces the row rather than stacking a second copy of a
    /// document that differs only by its timestamp.
    public static let conflict = "user_id,range_start,range_end"

    let database: AppDatabase
    let userId: String

    public init(database: AppDatabase, userId: String) {
        self.database = database
        self.userId = userId
    }

    /// The span a range resolves to, for this athlete's week start and this
    /// device's export marker.
    public func span(
        for range: ExportRange,
        today: String = LogicalDay.today(),
        defaults: UserDefaults? = AppDatabase.appGroupDefaults()
    ) -> ExportSpan {
        let weekStartDay = (try? database.preferences(userId: userId).weekStartDay) ?? 0
        return range.span(
            today: today,
            weekStartDay: weekStartDay,
            exportedThrough: ExportLog.exportedThrough(in: defaults))
    }

    /// Build the envelope for a range.
    ///
    /// ── `recordingMarker` IS NOT A CONVENIENCE ──────────────────────────────
    /// "This device has exported through X" must be written when a document was
    /// actually HANDED OVER, and building one is not that. The chip builds on
    /// the tap and records only when `UIActivityViewController` says the share
    /// completed; a caller that only wants to look at a document — a preview, a
    /// diagnostic, a test — passes `false` and burns nothing. The default is
    /// `false` for the same reason: a function named `envelope` that silently
    /// moved device state is the kind of thing that gets called twice.
    public func envelope(
        range: ExportRange,
        today: String = LogicalDay.today(),
        now: Date = Date(),
        defaults: UserDefaults? = AppDatabase.appGroupDefaults(),
        recordingMarker: Bool = false
    ) throws -> ExportEnvelope {
        try envelope(span: span(for: range, today: today, defaults: defaults),
                     today: today, now: now, defaults: defaults,
                     recordingMarker: recordingMarker)
    }

    public func envelope(
        span: ExportSpan,
        today: String = LogicalDay.today(),
        now: Date = Date(),
        defaults: UserDefaults? = AppDatabase.appGroupDefaults(),
        recordingMarker: Bool = false
    ) throws -> ExportEnvelope {
        let span = ExportRange.clamp(span, today: today)
        let input = try WeeklyExportBuilder(database: database, userId: userId)
            .input(span: span, today: today)
        let envelope = ExportEnvelope.make(
            input: input, span: span, generatedAt: ExportEnvelope.timestamp(now))
        if recordingMarker { ExportLog.record(through: span.end, in: defaults) }
        return envelope
    }

    // MARK: - The drop-box

    /// One row, shaped for `public.exports`.
    ///
    /// `envelope` is the whole value as `jsonb`. The three columns beside it
    /// are the only things a caller ever filters on, and they are copies of
    /// fields inside the JSON — duplicated on purpose, because an index on a
    /// `jsonb` path is a different conversation from an index on a date.
    struct Row: Encodable, Sendable {
        let user_id: String
        let range_start: String
        let range_end: String
        let version: Int
        let envelope: ExportEnvelope
    }

    /// Build, and send the copy on a best-effort basis.
    ///
    /// The one door both surfaces use. `remote` nil — a caller with no session
    /// to send with — is not an error: the document is what the caller asked
    /// for, and the copy on the server is a convenience for a desktop model.
    /// A failed send is reported through `onUploadFailure` and never thrown.
    public func build(
        range: ExportRange,
        today: String = LogicalDay.today(),
        now: Date = Date(),
        defaults: UserDefaults? = AppDatabase.appGroupDefaults(),
        uploadingVia remote: (any MirrorPushRemote)?,
        onUploadFailure: (@Sendable (any Error) -> Void)? = nil
    ) async throws -> ExportEnvelope {
        let envelope = try envelope(
            range: range, today: today, now: now, defaults: defaults, recordingMarker: true)
        guard let remote else { return envelope }
        do { try await upload(envelope, via: remote) }
        catch { onUploadFailure?(error) }
        return envelope
    }

    /// Send the envelope to Supabase.
    ///
    /// ── BEST EFFORT, AND SAID OUT LOUD ──────────────────────────────────────
    /// This does NOT go through the outbox. The outbox pushes LOCAL ROWS — it
    /// reads a table and an id out of the store and sends what it finds — and
    /// there is no local `exports` row to read, by the design note above. So
    /// this is one request, and a failed one is lost.
    ///
    /// That is the right trade and not an oversight: the markdown reaches the
    /// athlete through the share sheet whatever happens here, and the copy on
    /// the server exists only so a desktop model can fetch a week without one
    /// being pasted. A caller logs the failure and carries on; it must never
    /// fail the export.
    ///
    /// ponytail: no retry queue. If the MCP server starts missing weeks the
    /// founder actually exported, this becomes a mirrored table with an outbox
    /// row like everything else.
    public func upload(_ envelope: ExportEnvelope, via remote: any MirrorPushRemote) async throws {
        try await remote.upsertRow(
            Row(
                user_id: userId,
                range_start: envelope.rangeStart,
                range_end: envelope.rangeEnd,
                version: envelope.version,
                envelope: envelope
            ),
            table: Self.table, conflict: Self.conflict, nulls: []
        )
    }
}
