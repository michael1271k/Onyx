import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ONE SERIALISER, THREE CONSUMERS (W7).
//
// The week's export has three readers now — the share sheet, a Shortcuts
// action, and an MCP server a desktop model talks to — and the first rule of
// this wave is that the EXTRACTION exists once. `WeeklyExportBuilder` reads the
// rows into a `WeeklyExportInput`; `WeeklyExport.build` renders that input to
// markdown. An `ExportEnvelope` is those two things in one value, so no
// consumer ever has to re-derive either.
//
// The envelope carries BOTH halves on purpose. The markdown is what a chat
// window wants; the input is what a program wants, and a program handed only
// markdown would have to parse a document written for a model to read. Shipping
// the input beside it costs bytes and removes a parser.
// ─────────────────────────────────────────────────────────────────────────────

/// What a caller is asking for when it asks for "the export".
///
/// ── WHY THE COMPLETE-WEEK LOCK IS GONE (decision 21) ────────────────────────
/// The old chip refused a week with days left in it, on the web's reasoning
/// that a partial record read as final once a report had been written from it.
/// That reasoning survives in the RANGE, not in a lock: a span that ends today
/// says so in its own dates, and the document's cover prints them. What the
/// lock actually cost was the ordinary use — asking on Thursday what Monday to
/// Wednesday looked like.
public enum ExportRange: String, Codable, Sendable, CaseIterable {
    /// The day after the last span this device exported, through today. The
    /// default: it is the only option that cannot hand the model a week it has
    /// already been shown.
    case sinceLastExport
    /// The week containing today, up to and including today.
    case thisWeek
    /// The last week that finished — the old gate's only answer.
    case lastWeek
    /// Today and the six days before it, whatever weekday that starts on.
    case last7Days

    public var label: String {
        switch self {
        case .sinceLastExport: return "Since last export"
        case .thisWeek: return "This week so far"
        case .lastWeek: return "Last complete week"
        case .last7Days: return "Last 7 days"
        }
    }

    /// The most days any one export may cover.
    ///
    /// ponytail: a flat cap, not a paging scheme. `sinceLastExport` is the only
    /// option that can run away — a device that has not exported since March
    /// would otherwise build a document with two hundred daily rows in it,
    /// which is past what any reader can hold and past what a share sheet
    /// should be handed. Four weeks is the longest span a coaching audit is
    /// written over. Raise it, or page, if a real caller ever wants more.
    public static let maxDays = 28
}

/// A resolved span of dates, inclusive at both ends.
public struct ExportSpan: Codable, Hashable, Sendable {
    public var start: String
    public var end: String

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }

    /// Every date in the span, oldest first. Empty only if the dates do not
    /// parse, which the resolver above cannot produce.
    public var dates: [String] {
        guard let a = ISODate.dayNumber(start), let b = ISODate.dayNumber(end), a <= b else { return [] }
        return (a...b).map(ISODate.iso(dayNumber:))
    }

    public var dayCount: Int { dates.count }
}

public extension ExportRange {
    /// Resolve to dates.
    ///
    /// `exportedThrough` is the END of the last span this device exported, or
    /// nil if it never has — see `ExportLog`. It is a DATE and not a timestamp
    /// because the question "what has the model already been shown" is about
    /// days, not instants: exporting last week on Tuesday must not make
    /// "since last export" start on Tuesday.
    ///
    /// Both ends are clamped so a span is always at least one day and never
    /// longer than `maxDays`. A span that would start after it ends — the
    /// second export in one day — collapses onto today rather than being
    /// refused, because a chip that does nothing is worse than a chip that
    /// hands over today again.
    func span(today: String, weekStartDay: Int = 0, exportedThrough: String? = nil) -> ExportSpan {
        let weekStart = Week.start(of: today, startDay: weekStartDay)
        let raw: ExportSpan
        switch self {
        case .thisWeek:
            raw = ExportSpan(start: weekStart, end: today)
        case .lastWeek:
            let start = ISODate.addDays(weekStart, -7) ?? weekStart
            raw = ExportSpan(start: start, end: ISODate.addDays(start, 6) ?? start)
        case .last7Days:
            raw = ExportSpan(start: ISODate.addDays(today, -6) ?? today, end: today)
        case .sinceLastExport:
            // No record of an export is not "everything" — it is this week,
            // which is the same span `thisWeek` gives and the least surprising
            // first answer on a fresh install.
            let after = exportedThrough.flatMap { ISODate.addDays($0, 1) }
            raw = ExportSpan(start: after ?? weekStart, end: today)
        }
        return Self.clamp(raw, today: today)
    }

    /// `start ≤ end`, no more than `maxDays` of it, and never past today.
    ///
    /// The `today` bound is for a caller that builds its own `ExportSpan`:
    /// nothing above can produce a future span, but a hand-made one would
    /// render 28 empty days and file them as a document. Days that have not
    /// happened are not a record of anything.
    static func clamp(_ span: ExportSpan, today: String = LogicalDay.today()) -> ExportSpan {
        var start = span.start
        var end = span.end
        if end > today { end = today }
        if start > end { start = end }
        if let floor = ISODate.addDays(end, -(maxDays - 1)), start < floor { start = floor }
        return ExportSpan(start: start, end: end)
    }
}

/// The week's export as one value: the rows it was built from, and the document
/// they rendered to.
///
/// `Codable` and nothing else — it goes into a file the Shortcuts action hands
/// on, and into a `jsonb` column the MCP server reads back.
public struct ExportEnvelope: Codable, Equatable, Sendable {

    /// The wire version, and the document's own generation. The two move
    /// together: an envelope is a `WeeklyExportInput` plus the markdown that
    /// input rendered to, so a reader that can read one can read the other.
    public static let currentVersion = 6

    public var version: Int
    public var rangeStart: String
    public var rangeEnd: String
    /// `2026-09-22T10:30:00Z`.
    ///
    /// A STRING and not a `Date`. This value crosses three decoders that do not
    /// share an encoding strategy — Swift's (seconds since 2001 by default),
    /// Postgres `jsonb`, and the MCP server's Node — and choosing one means
    /// being wrong in the other two. ISO-8601 in UTC is the one spelling all
    /// three already agree on, and it is what every other timestamp in this
    /// domain is.
    public var generatedAt: String
    /// The rows. Every figure the document prints is derivable from this and
    /// nothing else.
    public var input: WeeklyExportInput
    /// The document. Carried rather than re-rendered so two consumers cannot
    /// disagree about the bytes.
    public var markdown: String

    public init(
        version: Int = ExportEnvelope.currentVersion,
        rangeStart: String,
        rangeEnd: String,
        generatedAt: String,
        input: WeeklyExportInput,
        markdown: String
    ) {
        self.version = version
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.generatedAt = generatedAt
        self.input = input
        self.markdown = markdown
    }

    /// Build the envelope around an input, rendering the document once.
    public static func make(
        input: WeeklyExportInput, span: ExportSpan, generatedAt: String
    ) -> ExportEnvelope {
        ExportEnvelope(
            rangeStart: span.start, rangeEnd: span.end,
            generatedAt: generatedAt,
            input: input, markdown: WeeklyExport.build(input)
        )
    }

    /// `onyx-week-2026-08-30.md` / `…-to-2026-09-02.md`.
    ///
    /// A span of one week keeps the single-date name the share sheet has always
    /// produced, so nothing that files these by name has to learn a second
    /// shape for the ordinary case.
    public var fileStem: String {
        let sevenDays = ISODate.addDays(rangeStart, 6) == rangeEnd
        return sevenDays ? "onyx-week-\(rangeStart)" : "onyx-week-\(rangeStart)-to-\(rangeEnd)"
    }

    /// `onyx-week-2026-08-30.md`, in the temporary directory.
    ///
    /// A FILE and not a string: a string reaches a share target as loose text,
    /// so Files offers no "Save to" and Mail has nothing to attach. The name is
    /// what makes a weekly document something you can keep rather than
    /// something you paste once. Rewritten rather than suffixed, so sharing the
    /// same span twice leaves one file and not a drawer of near-identical ones.
    public func writeFile(
        in directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let url = directory.appendingPathComponent("\(fileStem).md")
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// `2026-09-22T10:30:00Z` — the one spelling this envelope stamps.
    public static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

// MARK: - What this device has already handed over

/// The end date of the last span exported from this device.
///
/// ── WHY `UserDefaults` AND NOT A COLUMN ─────────────────────────────────────
/// "Since last export" is a question about THIS DEVICE's own history of asking,
/// not a fact about the athlete: it exists so the chip does not hand a model a
/// week it was already shown from the phone in your hand. A `user_goals` column
/// would mean server DDL, a mirror regeneration and a migration to carry a
/// value that no other surface reads and no other device has an opinion about.
///
/// The suite is the App Group's, which is the same one `PendingWater` writes —
/// so a Shortcuts run and a tap on the chip advance the same marker.
///
/// ponytail: device-local. A second device that exports would start from its
/// own idea of "last"; if that ever happens, this becomes a `user_goals`
/// column and the two readers below become its accessors.
public enum ExportLog {
    public static let key = "onyx.export.through"

    public static func exportedThrough(in defaults: UserDefaults?) -> String? {
        guard let raw = defaults?.string(forKey: key), ISODate.dayNumber(raw) != nil else { return nil }
        return raw
    }

    /// Records a span as handed over. Never moves the marker BACKWARDS: an
    /// explicit "last complete week" after a "since last export" must not make
    /// the next default re-export days that already went out.
    public static func record(through end: String, in defaults: UserDefaults?) {
        guard let defaults, ISODate.dayNumber(end) != nil else { return }
        if let current = exportedThrough(in: defaults), current >= end { return }
        defaults.set(end, forKey: key)
    }
}
