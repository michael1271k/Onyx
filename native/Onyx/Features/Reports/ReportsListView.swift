import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// Every week, and what is written on it.
///
/// ── THE SCREEN CHANGED ITS QUESTION (W4) ────────────────────────────────────
/// Until now the only writer was the web, so this listed the reports that
/// happened to exist and offered no way to make one — a week you had not
/// exported was a week that simply was not here. The phone writes now, and the
/// useful question is not "what have I got" but "which weeks am I missing". So
/// the list is WEEKS: every one back to the oldest report and never fewer than
/// a quarter, each either a report to read or an invitation to paste one.
struct ReportsListView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Supplied by the screenshot harness.
    var seeded: [ReportRow]?

    @State private var weeks: [ReportWeek] = []
    @State private var editing: ReportWeek?
    @State private var failure: String?

    var body: some View {
        List {
            if let failure {
                OnyxBanner(tone: .failure, title: "Not read", message: failure)
                    .listRowBackground(Color.clear)
            }
            ForEach(weeks) { week in
                row(week)
            }
        }
        .listRowBackground(Rectangle().fill(.ultraThinMaterial))
        .scrollContentBackground(.hidden)
        .onyxScreen(.recover)
        .tint(OnyxDomain.recover.accent)
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if weeks.isEmpty, failure == nil {
                ContentUnavailableView(
                    "No weeks yet",
                    systemImage: "doc.text",
                    description: Text("Weeks appear here as they pass.")
                )
            }
        }
        .sheet(item: $editing) { week in
            ReportEditorSheet(week: week, seededBody: seeded == nil ? nil : sampleBody)
        }
        .task {
            if let seeded {
                // The harness has no store; the same pure function the stream
                // uses builds the list, so the shot photographs the real shape.
                weeks = AppDatabase.weeks(seeded, today: seeded.first?.periodEnd ?? LogicalDay.today(), startDay: 0, minWeeks: 8)
                return
            }
            do {
                for try await rows in environment.database.reportWeeksStream(userId: environment.userIdString) {
                    weeks = rows
                }
            } catch {
                // NOT `weeks = []`: that lands on "No weeks yet", which tells a
                // reader whose store failed that their reports do not exist.
                if !(error is CancellationError) {
                    failure = "The weeks could not be read on this device."
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ week: ReportWeek) -> some View {
        if let report = week.report, week.hasReport {
            NavigationLink {
                ReportReaderView(report: report, week: week, seededBody: seeded == nil ? nil : sampleBody)
            } label: {
                label(week, detail: subtitle(report))
            }
        } else {
            Button { editing = week } label: {
                HStack(spacing: OnyxSpace.m) {
                    label(week, detail: "Add report")
                    Spacer(minLength: OnyxSpace.s)
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(OnyxDomain.recover.accent)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Paste a report for this week")
        }
    }

    private func label(_ week: ReportWeek, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Self.weekLabel(week))
                .foregroundStyle(Color.onyx.textPrimary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(week.hasReport ? Color.onyx.textSecondary : Color.onyx.textTertiary)
        }
        .padding(.vertical, 3)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    /// `19 Jul – 25 Jul 2026`. The stored dates, formatted — never a week
    /// number, which is a different subsystem and would be wrong here the first
    /// time a report covered a re-entry week.
    static func weekLabel(_ report: ReportRow) -> String {
        range(report.periodStart, report.periodEnd)
    }

    /// The current week says so. It is the one row on this screen that is about
    /// a week still happening, and "Add report" on it means something different
    /// from "Add report" on a week that closed in April.
    static func weekLabel(_ week: ReportWeek) -> String {
        week.isCurrent ? "This week · \(range(week.start, week.end))" : range(week.start, week.end)
    }

    /// The same week, in a navigation bar between two buttons. "This week" is
    /// the whole fact there; the dates alongside it truncated to "This week ·
    /// 30…", which says less than either half alone.
    static func shortWeekLabel(_ week: ReportWeek) -> String {
        week.isCurrent ? "This week" : range(week.start, week.end)
    }

    private static func range(_ startISO: String, _ endISO: String) -> String {
        let start = LogicalDay.date(fromISO: startISO)
        let end = LogicalDay.date(fromISO: endISO)
        guard let start else { return startISO }
        guard let end else { return start.formatted(.dateTime.day().month(.abbreviated).year()) }
        return "\(start.formatted(.dateTime.day().month(.abbreviated))) – "
            + end.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func subtitle(_ report: ReportRow) -> String {
        let kind = report.type == "sentinel7" ? "Sentinel-7" : report.type.capitalized
        let size = (report.contentMd?.count ?? 0) / 1000
        return size > 0 ? "\(kind) · \(size) k" : kind
    }

    /// `PreviewReport` is `#if DEBUG`, and so is the only caller that can make
    /// `seeded` non-nil — but the reference itself is not, which failed the
    /// RELEASE build (the shot loop only ever builds Debug, so nothing caught
    /// it until the first archive).
    private var sampleBody: String? {
        #if DEBUG
        PreviewReport.body
        #else
        nil
        #endif
    }
}

// MARK: - The reader

/// The reader: a native bar over a bundled web document.
struct ReportReaderView: View {
    let report: ReportRow
    /// The week the row was filed under, for the export's filename and for the
    /// editor this screen can open.
    var week: ReportWeek?
    /// The harness passes a body directly; the app reads it from the store when
    /// the screen opens, so a list of twenty reports does not hold a megabyte of
    /// markdown it never draws.
    var seededBody: String?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var body_: String?
    @State private var editing = false

    private var title: String { ReportsListView.weekLabel(report) }

    var body: some View {
        Group {
            if let body_ {
                ReportWebView(markdown: body_)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .background(Color.onyx.base)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let body_ {
                    Menu {
                        // The one thing a report page has always been for:
                        // getting the text somewhere else.
                        ShareLink(item: body_) { Label("Share text", systemImage: "doc.plaintext") }
                        // ── AND THE ONE IT NEVER COULD ──────────────────────
                        // A `Transferable` whose file representation renders on
                        // DEMAND: the PDF costs a hidden web view and a layout
                        // pass, and paying that every time a report is opened —
                        // which is what a plain `ShareLink(item: url)` would
                        // need — is a second of work for a tap most readers
                        // never make. The system shows its own progress while
                        // the export runs.
                        ShareLink(
                            item: ReportDocument(markdown: body_, filename: "Onyx report — \(title)"),
                            preview: SharePreview(title, image: Image(systemName: "doc.richtext"))
                        ) {
                            Label("Export PDF", systemImage: "arrow.down.doc")
                        }
                        if week != nil {
                            Button("Edit", systemImage: "square.and.pencil") { editing = true }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share or edit")
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let week {
                ReportEditorSheet(week: week, seededBody: seededBody) { saved in
                    // Removed from inside its own reader: the row this screen
                    // was pushed for is gone, so the screen goes too. Staying
                    // would leave an empty document with Export PDF still on it.
                    if saved.isEmpty { dismiss() } else { body_ = saved }
                }
            }
        }
        .task {
            if let seededBody {
                body_ = seededBody
                return
            }
            body_ = (try? environment.database.reportBody(id: report.id, userId: environment.userIdString)) ?? report.contentMd
        }
    }
}

// MARK: - The editor

/// Where a pasted report lands.
///
/// ── WHY A `TextEditor` AND NOT A `TextField` ────────────────────────────────
/// The thing being pasted is a 40 kB document with its own headings, tables and
/// ASCII banners. A growing `TextField` would reflow the whole sheet on every
/// keystroke and has no scroll of its own; the editor is a document surface,
/// which is what this is. It costs the placeholder, which SwiftUI does not give
/// it — hence the overlay.
struct ReportEditorSheet: View {
    let week: ReportWeek
    var seededBody: String?
    /// Handed the saved text, for the reader that opened this over itself.
    var onSaved: ((String) -> Void)?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var loaded = false
    @State private var failure: String?
    @FocusState private var typing: Bool

    private var hasBody: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hadBody: Bool { week.hasReport }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let failure {
                    OnyxBanner(tone: .failure, title: "Not saved", message: failure)
                        .padding(OnyxSpace.l)
                }
                editor
            }
            .onyxScreen(.recover)
            .navigationTitle(ReportsListView.shortWeekLabel(week))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    // Saving an empty body on a week that HAS one takes the
                    // report back — the only way to undo a paste that went to
                    // the wrong week. On a week that has none there is nothing
                    // to do, so the button is off and still says Save: "Remove"
                    // over an empty editor names an act that has no object.
                    Button(hadBody && !hasBody ? "Remove" : "Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!hasBody && !hadBody)
                }
                ToolbarItem(placement: .keyboard) {
                    HStack { Spacer(); Button("Done") { typing = false } }
                }
            }
        }
        .tint(OnyxDomain.recover.accent)
        .presentationDetents([.large])
        .presentationBackground(Color.onyx.base)
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
    }

    private var editor: some View {
        TextEditor(text: $text)
            .focused($typing)
            .onyxType(.caption)
            .onyxNumeral()
            .scrollContentBackground(.hidden)
            .padding(.horizontal, OnyxSpace.m)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Paste your AI coach reports…")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textTertiary)
                        .padding(.horizontal, OnyxSpace.m + 5)
                        .padding(.top, OnyxSpace.s)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Report text")
            .accessibilityHint("Paste the week's report here")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let seededBody {
            text = week.hasReport ? seededBody : ""
            return
        }
        guard let id = week.report?.id else { return }
        text = (try? environment.database.reportBody(id: id, userId: environment.userIdString)) ?? week.report?.contentMd ?? ""
    }

    private func save() {
        do {
            try environment.database.saveReport(
                userId: environment.userIdString,
                periodStart: week.start, periodEnd: week.end,
                markdown: text
            )
            onSaved?(text)
            dismiss()
        } catch {
            failure = "That report could not be saved on this device."
        }
    }
}

// MARK: - The PDF, as something the share sheet can ask for

/// A report, exportable as a PDF the system renders when it is actually wanted.
///
/// `FileRepresentation`'s exporter is async, which is the whole reason this type
/// exists: the render is a real web view and a real layout pass, and a
/// `ShareLink(item: url)` would have to have paid for it before the reader
/// decided to share anything.
struct ReportDocument: Transferable, Sendable {
    let markdown: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { document in
            SentTransferredFile(
                try await ReportPDF.render(markdown: document.markdown, filename: document.filename)
            )
        }
    }
}

#if DEBUG
/// A short FMT v2 document for the shot loop, carried from the parser's own
/// tests so the screenshot exercises the real dialect: a banner, both heading
/// forms, an anchor ladder and a table with no separator row.
enum PreviewReport {
    static let body = """
    # ⬢ ONYX OS · WEEKLY TELEMETRY & PERFORMANCE AUDIT

    ```
    ╔══════════════════════════════════════════╗
    ║ W01 · 2026-07-19 → 07-25 · CUT · FMT v2  ║
    ╚══════════════════════════════════════════╝
    ```

    # ▓ PART 1 — WEIGHT & METABOLIC VERIFICATION

    ## 🟢 QUICK VERDICT — the cut is on rails
    Weight is down 0.7 kg on the week with muscle mass flat.

    ## 🧮 THE MATH & TDEE CHECK
    ANCHOR A · DIARY (blueprint primary)     2,400   ← ADOPTED
    ANCHOR B · HISTORICAL CUT @1,925         2,430   (−0.46 kg/wk @ 65.6 kg)
    ANCHOR C · BOTTOM-UP THIS WEEK           2,290   (range 2,163–2,420)

    ## 📉 WEIGHT & BODY COMP TRAJECTORY
    Date | Wt | BF% | Fat kg | Musc kg
    2026-07-19 | 64.8 | 17.9 | 11.6 | 29.9
    2026-07-22 | 64.4 | 17.6 | 11.3 | 29.8
    2026-07-25 | 64.1 | 17.4 | 11.2 | 29.7

    # ▓ PART 2 — GYM PERFORMANCE & HYPERTROPHY

    ## ⚑ DB LADDER VALIDATOR
    Steps are 11–25% relative — inside tolerance on every rung.

    Protein ████████████░░░░ 78%
    Steps   ██████████████░░ 88%

    ## Adherence notes
    Two sessions moved by a day; nothing dropped.
    """

    static let rows: [ReportRow] = [
        ReportRow(
            id: "r1", userId: "u1", type: "sentinel7",
            periodStart: "2026-08-23", periodEnd: "2026-08-29",
            contentMd: body, sessionSummaryMd: nil, weightReportMd: nil,
            metrics: nil, notionPageId: nil, createdAt: Date()
        ),
        ReportRow(
            id: "r2", userId: "u1", type: "sentinel7",
            periodStart: "2026-08-16", periodEnd: "2026-08-22",
            contentMd: body, sessionSummaryMd: nil, weightReportMd: nil,
            metrics: nil, notionPageId: nil, createdAt: Date()
        ),
    ]
}
#endif
