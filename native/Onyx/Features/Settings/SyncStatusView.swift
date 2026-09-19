import SwiftUI
import GRDB
import OnyxUI
import OnyxCore
import OnyxData

/// What the sync actually did, table by table (§5.8, decision 14).
///
/// ── WHY A SCREEN AND NOT A SPINNER ──────────────────────────────────────────
/// Today already carries the reassuring half — a hairline while it runs and
/// "Synced 2s ago" when it stops. That is enough for the good case and useless
/// for every other one. §2.3 is a list of failures this app shipped WITH a
/// green tick on screen: a 90-day window that silently hid older rows, a
/// PostgREST `select` with no `range` that truncated at the server's row cap,
/// an outbox with no caller at all. Each was invisible because the only thing
/// the UI could say was "synced".
///
/// So this screen says five things a spinner cannot:
///
///   · **when** each table last heard from the server, from the `sync_status`
///     ledger, which survives relaunch — an in-memory timestamp says "never"
///     every cold start and that is not the same fact;
///   · **how much** of each table this device actually holds, counted locally
///     rather than reported by the thing under suspicion;
///   · **how much the SERVER holds** of the same table, asked for directly
///     (§W1.6). This is the only number on the screen the device cannot fake,
///     and it is what turns "synced" from a claim into a comparison;
///   · **how many user ids** each local table is keyed by — see below;
///   · **what has not left yet** — the outbox depth, anything that has already
///     failed, and the message it failed with, because those are three
///     different pieces of news.
///
/// ── WHY THE DISTINCT-USER-ID COLUMN IS THE POINT OF THIS WAVE ────────────
/// Phase 2.5's pre-flight (F1) found one root cause behind six symptoms: the
/// app wrote `UUID.uuidString`, which is UPPERCASE, while every row pulled from
/// Postgres carries the server's lowercase text verbatim. SQLite compares TEXT
/// byte by byte, so `user_id = ?` in a read matched exactly one of the two
/// spellings and the other half of the store went dark — Today emptying half a
/// second after a pull-to-refresh, the dashboard blank, Trends blank.
///
/// A store in that state has a fingerprint that fits in one integer: a table
/// holding rows under TWO distinct user ids. So it is a column here. Two is the
/// bug still present; one is the fix holding, and it is worth being able to see
/// that on a device rather than infer it from a screen that looks better.
///
/// Nothing here writes. The two buttons are the ordinary sync and Reconcile —
/// the backfill, which re-reads every table from the server and upserts what it
/// finds — both through `AppEnvironment` so the hairline and the caption on
/// Today move with them.
struct SyncStatusView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Supplied by the screenshot harness so the shot has a steady ledger.
    var seeded: Snapshot?

    @State private var snapshot: Snapshot?
    @State private var confirmingBackfill = false
    /// True while the server counts are in the air. The local half is already
    /// on screen by then, so this is a caption and never a blocking spinner.
    @State private var asking = false

    /// One row of the table list, and the whole thing this screen shows.
    struct Snapshot: Equatable, Sendable {
        struct Table: Identifiable, Equatable, Sendable {
            var id: String { name }
            let name: String
            /// From the `sync_status` ledger. Nil = this device has never
            /// pulled it, which is a real state and not "0 seconds ago".
            let syncedAt: Date?
            /// Counted locally, right now.
            var rows: Int
            /// `count(distinct user_id)` on the local table. Nil where the
            /// table has no `user_id` column at all, which is a fine answer and
            /// not a failure. Anything above 1 is the casing bug — see the type
            /// comment.
            var userIds: Int?
            /// The server's own `count=exact`, asked for over the network.
            ///
            /// Nil covers two states deliberately kept apart from zero: not
            /// asked yet, and asked and the request failed. Zero is a real
            /// count and the loudest one there is next to a local 1,586.
            var server: Int? = nil

            /// The row is quiet only when both numbers are in and agree.
            /// Absent server = nothing to say yet, which is also quiet.
            var matches: Bool? { server.map { $0 == rows } }
            /// More than one user id in one table. The Wave 1 fingerprint.
            var isSplit: Bool { (userIds ?? 1) > 1 }
            /// Worst first. Split before merely-disagreeing, because one is a
            /// bug in this build and the other can be a queue mid-drain.
            var rank: Int { isSplit ? 0 : (matches == false ? 1 : 2) }
        }

        var tables: [Table] = []
        /// Queued and in flight — everything written here that the server has
        /// not accepted.
        var pending = 0
        /// Rows the push gave up on. Counted apart: a queue that is draining
        /// and a queue that is stuck look identical as one number.
        var failed = 0
        /// The newest thing the queue was told by the server, verbatim.
        var lastError: String?

        /// The newest thing in the ledger — "nothing here is older than this
        /// is wrong", so the OLDEST table is the honest floor and is shown on
        /// its own row instead.
        var lastSync: Date? { tables.compactMap(\.syncedAt).max() }
        /// The staleness of the *least* recently pulled table that has ever
        /// been pulled. A full sync is only as fresh as its slowest table.
        var oldestSync: Date? { tables.compactMap(\.syncedAt).min() }
        var neverSynced: Int { tables.filter { $0.syncedAt == nil }.count }
        var totalRows: Int { tables.reduce(0) { $0 + $1.rows } }
        /// Only over the tables the server actually answered for, so a table
        /// whose HEAD failed cannot look like a hole in the data.
        var serverRows: Int { tables.compactMap(\.server).reduce(0, +) }
        var answered: Int { tables.filter { $0.server != nil }.count }
        var agreeing: Int { tables.filter { $0.matches == true }.count }
        var disagreeing: Int { answered - agreeing }
        /// The gate for this wave is "identical rows on every table", and this
        /// is that sentence as a Bool.
        var isReconciled: Bool { answered == tables.count && disagreeing == 0 }
        var split: [Table] { tables.filter(\.isSplit) }

        /// Faults first, then the pull order.
        ///
        /// A diagnostic screen that puts its one finding fifteen rows down is a
        /// screen that gets scanned and closed, and the catalogue order is only
        /// meaningful to the backfill. `enumerated()` carries the original
        /// index as the tie-break because `sorted(by:)` is not a stable sort and
        /// a table list that reshuffles between two loads is unreadable.
        var ranked: [Table] {
            tables.enumerated()
                .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
                .map(\.element)
        }
    }

    var body: some View {
        Form {
            summary
            rescores
            if let snapshot, !snapshot.tables.isEmpty { tables(snapshot) }
            actions
        }
        .onyxFormBackground(.body)
        .navigationTitle("Sync doctor")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            "Read every table again?",
            isPresented: $confirmingBackfill,
            titleVisibility: .visible
        ) {
            Button("Reconcile") {
                environment.rerunBackfill()
                // The sheet takes over from here; leaving this screen up behind
                // it means the counts are re-read the moment it drops.
                Task { await load() }
            }
        } message: {
            Text("Every table is read again from \(SyncStatusView.historyStart) and every row is upserted over the local copy. Nothing on this device is deleted, and nothing local is lost — the outbox is pushed first — but it is a few thousand rows over the network.")
        }
    }

    /// The last few cascades, off the `sync_status` ledger (W2). A rescore is
    /// a write to `daily_scores` nobody asked the server for, so it is the
    /// one thing on this screen that explains why the scores just moved.
    @State private var rescoreRuns: [SyncStatusRow] = []

    private var rescores: some View {
        Section {
            if rescoreRuns.isEmpty {
                Text("No cascade has run on this device yet.")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
            ForEach(rescoreRuns, id: \.id) { run in
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(run.rows.formatted()).onyxNumeral().foregroundStyle(Color.onyx.textSecondary)
                        Text(Self.age(run.syncedAt) ?? "")
                            .onyxType(.caption).foregroundStyle(Color.onyx.textTertiary)
                    }
                } label: {
                    Text(run.reason)
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textPrimary)
                }
            }
        } header: {
            OnyxSectionHeader("Rescores", .body)
        } footer: {
            Text("Every cascade that rewrote stored daily scores here: why, the dates it reached, and how many days it wrote. Edits within 120 days run on their own; older ones wait for Recompute history in Settings.")
        }
    }

    /// What the backfill actually reaches back to. Stated rather than implied:
    /// "the whole history" is a promise, and this is the date it means.
    static let historyStart = "March 2026"

    // MARK: - Summary

    @ViewBuilder
    private var summary: some View {
        Section {
            // A `TimelineView` for the same reason Today's caption uses one:
            // the age has to tick without re-rendering everything that reads
            // the environment once a second.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                LabeledContent("Last sync", value: environment.sync.caption(at: context.date) ?? "Never")
            }
            if let snapshot {
                LabeledContent("Oldest table", value: Self.age(snapshot.oldestSync) ?? "Never pulled")
                // Stacked in the same shape as a table row, so the eye learns
                // "top is here, bottom is the server" once and reads the whole
                // screen with it.
                LabeledContent("Rows") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(snapshot.totalRows.formatted())
                            .onyxNumeral()
                            .foregroundStyle(Color.onyx.textSecondary)
                        Text(snapshot.answered == 0
                             ? (asking ? "asking…" : "—")
                             : snapshot.serverRows.formatted())
                            .onyxType(.caption)
                            .onyxNumeral()
                            .foregroundStyle(Color.onyx.textTertiary)
                    }
                }
                // The wave's gate in one line. Tinted only when the two sides
                // genuinely disagree — "not asked yet" is not a disagreement.
                LabeledContent("Tables agreeing") {
                    Text(snapshot.answered == 0
                         ? "—"
                         : "\(snapshot.agreeing) of \(snapshot.tables.count)")
                        .onyxNumeral()
                        .foregroundStyle(snapshot.disagreeing > 0 ? Color.onyx.danger : Color.onyx.textSecondary)
                }
                LabeledContent("Waiting to send", value: snapshot.pending.formatted())
                if snapshot.failed > 0 {
                    LabeledContent("Failed to send") {
                        Text(snapshot.failed.formatted())
                            .foregroundStyle(Color.onyx.danger)
                    }
                }
                lastError(snapshot)
            }
        } header: {
            OnyxSectionHeader("This device", .body)
        } footer: {
            if case .failed(let message) = environment.sync.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.onyx.danger)
            } else if let snapshot, snapshot.pending > 0 {
                Text("Changes queue locally and go out on the next sync, so the app works with no signal at all.")
            } else if let snapshot, snapshot.isReconciled {
                Text("Every table holds the same number of rows here as on the server.")
            } else {
                Text("Everything written on this device has reached the server.")
            }
        }
    }

    /// The most recent failure, from whichever half of sync produced one.
    ///
    /// Two sources, and they answer different questions. `sync.phase` is the
    /// live run — the thing that just went wrong, in memory, gone at relaunch.
    /// The outbox's `last_error` is durable and is the one that matters when a
    /// single write has been rejected for a week under a green tick: the sync
    /// as a whole succeeds every time, so the phase is `.idle` and nothing else
    /// on this screen would ever mention it.
    ///
    /// The live one wins when both exist, because it is the newer news.
    @ViewBuilder
    private func lastError(_ snapshot: Snapshot) -> some View {
        let live: String? = if case .failed(let message) = environment.sync.phase { message } else { nil }
        let newest = live ?? snapshot.lastError
        VStack(alignment: .leading, spacing: 2) {
            Text("Last error")
                .foregroundStyle(Color.onyx.textPrimary)
            Text(newest ?? "None")
                .onyxType(.caption)
                .foregroundStyle(newest == nil ? Color.onyx.textTertiary : Color.onyx.danger)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tables

    private func tables(_ snapshot: Snapshot) -> some View {
        Section {
            ForEach(snapshot.ranked) { table in
                LabeledContent {
                    // Two numbers stacked rather than a difference: a delta of
                    // "−12" tells the reader which way it went and nothing about
                    // the scale it went there from, and 12 missing out of 24 is
                    // a different morning to 12 missing out of 1,586.
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(table.rows.formatted())
                            .onyxNumeral()
                            .foregroundStyle(table.matches == false ? Color.onyx.danger : Color.onyx.textSecondary)
                        Text(Self.serverLabel(table, asking: asking))
                            .onyxType(.caption)
                            .onyxNumeral()
                            .foregroundStyle(table.matches == false ? Color.onyx.danger : Color.onyx.textTertiary)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(table.name)
                            .foregroundStyle(Color.onyx.textPrimary)
                        Text(Self.age(table.syncedAt) ?? "Never pulled")
                            .onyxType(.caption)
                            .foregroundStyle(table.syncedAt == nil ? Color.onyx.textTertiary : Color.onyx.textSecondary)
                        // Only ever drawn when it is news. One user id is the
                        // correct state and a row saying so on every table is a
                        // row nobody reads by the third screenful.
                        if table.isSplit, let ids = table.userIds {
                            // Text and not a `Label`: the leading column is
                            // narrow next to two right-aligned numbers, and a
                            // `Label` there wraps its glyph onto its own line.
                            // The words carry the alarm, which is what a reader
                            // who cannot see the tint needs anyway.
                            Text("\(ids) user ids")
                                .onyxType(.caption)
                                .foregroundStyle(Color.onyx.danger)
                        }
                    }
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Self.spoken(table))
            }
        } header: {
            OnyxSectionHeader("Tables", .body)
        } footer: {
            tablesFooter(snapshot)
        }
    }

    @ViewBuilder
    private func tablesFooter(_ snapshot: Snapshot) -> some View {
        if !snapshot.split.isEmpty {
            let names = snapshot.split.map(\.name)
            // The one finding on this screen worth a sentence rather than a
            // tint: it is not a sync lag, it will not resolve on its own, and
            // the reader needs to know which tables to look at.
            Text("\(names.formatted(.list(type: .and))) hold rows under more than one user id. Everything this device reads is filtered by one of them, so the rest is invisible — not lost. Reconcile after updating the app.")
                .foregroundStyle(Color.onyx.danger)
        } else if snapshot.neverSynced > 0 {
            Text("\(snapshot.neverSynced) of \(snapshot.tables.count) tables have never been pulled on this device. Reconcile below.")
        } else if snapshot.disagreeing > 0 {
            Text("The lower number is the server's own count. A table can sit one or two rows ahead of it while the outbox drains; a table behind it has not finished pulling.")
        } else {
            Text("Local count on top, the server's own count under it. Both are counted, neither is reported by the sync.")
        }
    }

    /// `412` · `…` while the request is in the air · `—` when it never came back.
    ///
    /// A failed HEAD is NOT drawn as `0`: zero is a real and alarming count,
    /// and a screen that cannot tell "the server has none" from "I could not
    /// ask" is the same class of lie as the spinner this replaced.
    private static func serverLabel(_ table: Snapshot.Table, asking: Bool) -> String {
        if let server = table.server { return server.formatted() }
        return asking ? "…" : "—"
    }

    private static func spoken(_ table: Snapshot.Table) -> String {
        var parts = [table.name, Self.age(table.syncedAt) ?? "never pulled", "\(table.rows) rows here"]
        switch table.server {
        case .some(let server) where server == table.rows: parts.append("server agrees")
        case .some(let server): parts.append("\(server) on the server")
        case .none: parts.append("server count unknown")
        }
        if table.isSplit, let ids = table.userIds { parts.append("\(ids) user ids") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Actions

    private var actions: some View {
        Section {
            Button("Sync now") {
                Task {
                    await environment.syncNow(reason: .pull)
                    await load()
                }
            }
            .disabled(environment.sync.phase == .running)

            // The plan's "Reconcile" IS the backfill — cursors cleared, every
            // table read whole, every row upserted. One button, renamed for
            // what it is for rather than for how it is implemented.
            Button("Reconcile") { confirmingBackfill = true }
                .disabled(environment.backfill != nil)
        } footer: {
            Text("A sync pulls what changed since each table was last read. Reconcile ignores those markers and reads everything, which is what closes a gap the counts above have found.")
        }
    }

    // MARK: - Loading

    /// `2s ago` / `4h ago` / `Never pulled`.
    ///
    /// Same shape as `SyncStatus.caption` and deliberately not
    /// `RelativeDateTimeFormatter`, which says "in 0 seconds" for the instant a
    /// pull lands — the exact moment somebody is most likely to be reading it.
    static func age(_ date: Date?, now: Date = .now) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<5: return "just now"
        case ..<60: return "\(seconds)s ago"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3600)h ago"
        default: return "\(seconds / 86_400)d ago"
        }
    }

    /// Local first, then the network — never the other way round.
    ///
    /// The counts on this device are available in a few milliseconds and the
    /// server's are twenty-six HTTP round trips away. Drawing the local half
    /// immediately means the screen is useful on a train; awaiting both would
    /// make the one part that always works depend on the part under suspicion.
    private func load() async {
        // The cascade ledger is read even for the harness's seeded snapshot:
        // it is the one section that comes off the store rather than the sync.
        rescoreRuns = (try? environment.database.syncLedger(userId: environment.userIdString, table: "rescore", limit: 6)) ?? []
        if let seeded {
            snapshot = seeded
            return
        }
        // The ledger read goes through the actor because that is who owns the
        // user id the rows are keyed by; the counts are a plain read.
        let ledger = (try? await environment.coordinator?.lastSync()) ?? [:]
        let database = environment.database
        snapshot = await Task.detached(priority: .userInitiated) {
            Self.build(database: database, ledger: ledger)
        }.value

        guard let coordinator = environment.coordinator else { return }
        asking = true
        let counts = await coordinator.serverCounts()
        asking = false
        // Folded into whatever is on screen NOW rather than into the copy this
        // call started with: a second load may have replaced it while the HEADs
        // were in the air, and the two halves of a row must describe one moment.
        snapshot?.tables = snapshot?.tables.map { table in
            var table = table
            table.server = counts[table.name]
            return table
        } ?? []
    }

    /// Counted off the main actor: this is one `count(*)` per mirrored table.
    private nonisolated static func build(database: AppDatabase, ledger: [String: Date]) -> Snapshot {
        // ── THE NAMES ARE THE CATALOGUE'S, NOT A STRING FROM ANYWHERE ────────
        // `backfillOrder` is generated from `MirrorCatalogue`, so these are
        // compile-time identifiers rather than anything a user or a server can
        // influence — which is what makes interpolating them into SQL safe. The
        // intersection with `sqlite_master` is not the guard, it is the answer
        // to a catalogue table this schema version does not have yet: skipped
        // rather than counted as a crash.
        let existing: Set<String> = (try? database.read { db in
            try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
        }) ?? []

        var out = Snapshot()
        out.tables = SyncCoordinator.backfillOrder.filter(existing.contains).map { name in
            let rows = (try? database.read { db in
                try Int.fetchOne(db, sql: "SELECT count(*) FROM \"\(name)\"") ?? 0
            }) ?? 0
            // `try?` is the whole guard for a table with no `user_id` column:
            // SQLite raises on the unknown column and the answer is nil, which
            // the row draws as nothing rather than as a suspicious 1.
            let userIds = try? database.read { db in
                try Int.fetchOne(db, sql: "SELECT count(DISTINCT user_id) FROM \"\(name)\"")
            }
            return Snapshot.Table(name: name, syncedAt: ledger[name], rows: rows, userIds: userIds ?? nil)
        }

        // Folded to a dictionary INSIDE the read: GRDB's `Row` is not
        // `Sendable` and `AppDatabase.read` hands its result across an
        // isolation boundary, so a `[Row]` cannot leave the closure.
        let queue: [String: Int] = (try? database.read { db in
            var counts: [String: Int] = [:]
            let rows = try Row.fetchAll(db, sql: "SELECT status, count(*) AS n FROM outbox GROUP BY status")
            for row in rows {
                counts[row["status"] ?? "", default: 0] += row["n"] ?? 0
            }
            return counts
        }) ?? [:]
        for (status, n) in queue {
            // A row is deleted the moment the server accepts it, so everything
            // still in the table is unsent. `failed` is called out separately.
            if status == OutboxItem.Status.failed.rawValue { out.failed += n } else { out.pending += n }
        }

        // ── WHY `next_attempt_at` AND NOT A `failed_at` ─────────────────────
        // There is no `failed_at`. `outboxFailed` records the message, raises
        // `attempts` and stamps `next_attempt_at` from `SyncBackoff`, so the
        // only ordering column the queue has is "when may this be tried again"
        // — and the row it puts first is the one that has failed the MOST. That
        // is the right row to show: one failure ten minutes ago is a flaky
        // network, while a row backed off to an hour is a write the server will
        // never accept, and nothing else on this screen would ever say so.
        out.lastError = (try? database.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT last_error FROM outbox WHERE last_error IS NOT NULL ORDER BY next_attempt_at DESC, attempts DESC LIMIT 1"
            )
        }) ?? nil
        return out
    }
}

#if DEBUG
extension SyncStatusView.Snapshot {
    /// A HEALTHY device three weeks into the block: everything pulled, every
    /// table agreeing with the server, one edit still queued, and
    /// `fatigue_logs` never seen because nothing has written one.
    static let preview: Self = {
        var out = Self()
        let now = Date()
        // name, seconds since the pull, rows this device holds
        let seed: [(String, TimeInterval?, Int)] = [
            ("user_goals", 2, 1), ("plans", 2, 3), ("exercises", 3, 128),
            ("workout_sessions", 3, 61), ("workout_sets", 4, 1_586),
            ("daily_logs", 2, 412), ("daily_scores", 5, 178),
            ("nutrition_entries", 9, 934), ("water_intake", 9, 402),
            ("body_composition", 61, 24), ("sleep_sessions", 61, 171),
            ("cardio_logs", 240, 38), ("doms_logs", 1_920, 46),
            ("fatigue_logs", nil, 0), ("personal_records", 5, 21),
        ]
        out.tables = seed.map { name, ago, rows in
            // Agreeing and single-keyed: the quiet state, which is what a
            // reviewer needs to have seen before a tinted one means anything.
            Table(name: name, syncedAt: ago.map { now.addingTimeInterval(-$0) }, rows: rows, userIds: 1, server: rows)
        }
        out.pending = 3
        return out
    }()

    /// The same device with every fault the doctor can name, because a
    /// screenshot of fifteen agreeing rows proves the layout and nothing else.
    ///
    /// One table behind the server and one ahead of it, one the server could
    /// not be asked about at all, two split across user ids — the Phase 2.5
    /// casing bug (F1) as it would actually look — and a queued write the
    /// server has rejected outright. Every tint in this file is in the PNG.
    static let faults: Self = {
        var out = preview
        out.tables = out.tables.map { table in
            var table = table
            switch table.name {
            // Both training tables carry rows written before the casing fix and
            // rows pulled after it, which is the whole shape of the bug.
            case "workout_sessions": table.userIds = 2
            case "workout_sets": table.userIds = 2; table.server = 1_602
            // A local PR the ledger has never pushed: ahead of the server.
            case "personal_records": table.rows = 24; table.server = 21
            // The HEAD failed. Drawn as "—", never as nought.
            case "cardio_logs": table.server = nil
            // No `user_id` column reached at all.
            case "fatigue_logs": table.userIds = nil
            default: break
            }
            return table
        }
        out.failed = 1
        out.lastError = "PostgrestError 23514 — new row for relation fatigue_logs violates check constraint fatigue_logs_slot_check"
        return out
    }()
}

#Preview("Sync doctor") {
    NavigationStack { SyncStatusView(seeded: .preview) }
        .environment(AppEnvironment.preview)
}

#Preview("Sync doctor — faults") {
    NavigationStack { SyncStatusView(seeded: .faults) }
        .environment(AppEnvironment.preview)
}
#endif
