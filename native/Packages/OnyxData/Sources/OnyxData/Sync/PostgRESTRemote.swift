import Foundation
import Supabase

/// `SyncRemote` over supabase-swift's PostgREST client.
///
/// Thin on purpose: every rule about WHAT to send lives in `SyncTranslation`
/// and every rule about WHEN lives in `SyncEngine`. What is left here is the
/// three HTTP shapes and the two things that are genuinely PostgREST-specific:
/// the conflict target, and `returning: .minimal`.
///
/// `.minimal` matters more than it looks. The default is `.representation`,
/// which makes the server re-SELECT every affected row THROUGH RLS and send
/// all of it back — thirty full rows on the return leg of a thirty-set upload,
/// over cellular, inside a background task, and then discarded unread.
public struct PostgRESTRemote: SyncRemote {

    private let client: SupabaseClient
    private let userId: String

    /// `userId` scopes the catalogue read. RLS already restricts every table to
    /// `user_id = auth.uid()`, so this is belt and braces — but the filter also
    /// keeps the request honest if the policy is ever widened for an admin.
    public init(client: SupabaseClient, userId: String) {
        self.client = client
        self.userId = userId
    }

    public func exerciseCatalogue() async throws -> [RemoteExercise] {
        try await client
            .from("exercises")
            .select("id,name,slug")
            .eq("user_id", value: userId)
            .execute()
            .value
    }

    public func upsertSessions(_ rows: [RemoteSessionRow], ignoreDuplicates: Bool) async throws {
        guard !rows.isEmpty else { return }
        // `onConflict: "id"` is not a preference, it is the only legal target:
        // `workout_sessions` has exactly one unique constraint, its primary
        // key. There is no unique index on `client_session_id` — the web app's
        // idempotency token is enforced by a SELECT, not by the database.
        try await client
            .from("workout_sessions")
            .upsert(rows, onConflict: "id", returning: .minimal, ignoreDuplicates: ignoreDuplicates)
            .execute()
    }

    public func upsertSets(_ rows: [RemoteSetRow]) async throws {
        guard !rows.isEmpty else { return }
        try await client
            .from("workout_sets")
            .upsert(rows, onConflict: "id", returning: .minimal)
            .execute()
    }

    public func deleteSets(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await client
            .from("workout_sets")
            .delete(returning: .minimal)
            .in("id", values: ids)
            .execute()
    }

    /// The event log — `wave-10-set-events.sql (git history)`.
    ///
    /// `ignoreDuplicates: true` is `ON CONFLICT DO NOTHING`, and it is the only
    /// legal setting: an event is immutable, so an id the server already holds
    /// must be left exactly as it is. A real merge would let one device rewrite
    /// history another device has already folded.
    ///
    /// ── AND IT MAY 404 UNTIL THE SQL IS RUN ─────────────────────────────────
    /// The table is applied by hand. `SyncEngine` calls this AFTER the row
    /// reconcile has already succeeded and swallows whatever comes back, so a
    /// database without the table costs one failed request per drain and
    /// changes nothing else.
    public func upsertSetEvents(_ rows: [RemoteSetEventRow]) async throws {
        guard !rows.isEmpty else { return }
        try await client
            .from("set_events")
            .upsert(rows, onConflict: "id", returning: .minimal, ignoreDuplicates: true)
            .execute()
    }
}

/// `MirrorRemote` over the same client — the READ half of sync.
///
/// Every mirrored table carries a `user_id`, so one filter serves all of them,
/// which is what lets the generated catalogue treat twenty-six tables
/// identically. RLS already restricts each to `user_id = auth.uid()`; sending
/// the filter anyway keeps the request honest if a policy is ever widened for
/// an admin.
public struct PostgRESTMirrorRemote: MirrorRemote, MirrorPushRemote {

    private let client: SupabaseClient
    private let userId: String

    public init(client: SupabaseClient, userId: String) {
        self.client = client
        self.userId = userId
    }

    /// The write half. `conflict` comes from the generated catalogue and is the
    /// table's NATURAL key wherever Postgres has one — see `MirrorTable`.
    ///
    /// RLS supplies the `user_id` guard on the way in; the row carries its own
    /// `user_id` because these tables are `NOT NULL` on it.
    ///
    /// ── THE SERVER OWNS ITS OWN TIMESTAMPS ──────────────────────────────────
    /// `created_at` and `updated_at` are stripped from the body. Both default to
    /// `now()` on every one of these tables and a `BEFORE UPDATE` trigger
    /// maintains `updated_at`, so sending them can only ever be worse than not:
    ///
    ///   · `updated_at` is the DELTA CURSOR. On an INSERT no trigger fires, so a
    ///     phone whose clock is three minutes slow would stamp a brand-new row
    ///     in the past — where every other device's `>= cursor` filter would
    ///     step straight over it and never see the row again.
    ///   · `created_at` on a row this device is updating is the server's own
    ///     record of when the row first appeared. Echoing our mirrored copy back
    ///     is at best a no-op and at worst overwrites it with a value that has
    ///     been through two clocks and a decode.
    ///
    /// Done here rather than in the row types because it is a fact about
    /// PostgREST, not about the schema — and the mirror needs both columns on
    /// the way IN.
    public func upsertRow<T: Encodable & Sendable>(
        _ row: T, table: String, conflict: String, nulls: [String]
    ) async throws {
        var body = try JSONDecoder().decode([String: AnyJSON].self, from: OnyxJSON.encoder.encode(row))
        body.removeValue(forKey: "created_at")
        body.removeValue(forKey: "updated_at")
        // A cleared column is absent from the body (`encodeIfPresent`), which
        // the merge reads as "no opinion". Saying `null` out loud is the one
        // way a clear reaches the server — and only where the row is actually
        // missing the column, so a value typed back in is never overwritten.
        for column in nulls where body[column] == nil {
            body[column] = .null
        }
        try await client
            .from(table)
            .upsert(body, onConflict: conflict, returning: .minimal)
            .execute()
    }

    /// ── WHY THE USER FILTER IS HERE AND NOT AT THE ELEVEN CALL SITES ────────
    /// `key` is whatever `RowRef` carried, and for most tables that is a
    /// NATURAL key — `{date: "2026-09-05"}` for a daily row, `{session_id: …,
    /// exercise_id: …}` for a set. None of those name a user. RLS is what has
    /// been keeping the request honest, which is the same argument
    /// `exerciseCatalogue` above declined to accept.
    ///
    /// Filtering here rather than at each `enqueueRowDelete` is the smaller and
    /// the safer change: eleven call sites in five files each have to remember,
    /// and this one cannot forget. Every one of the 32 tables carries
    /// `user_id`, so the column is always valid. A key that ALREADY names a
    /// user is unaffected — PostgREST ANDs the filters, so an equal value is a
    /// no-op and a different one matches nothing, which is the correct answer
    /// to a delete aimed at somebody else's row.
    public func deleteRow(table: String, key: [String: String]) async throws {
        guard !key.isEmpty else { throw RowPushError.emptyKey(table: table) }
        var query = client.from(table).delete(returning: .minimal).eq("user_id", value: userId)
        // Sorted so the request is byte-identical on a replay; a dictionary's
        // order is not.
        for (column, value) in key.sorted(by: { $0.key < $1.key }) {
            query = query.eq(column, value: value)
        }
        try await query.execute()
    }

    public func select<T: Decodable & Sendable>(
        _ type: T.Type, request: MirrorRequest
    ) async throws -> [T] {
        try await Pagination.keyset(order: request.order) { after, limit in
            var query = client.from(request.table).select().eq("user_id", value: userId)
            if let since = request.since {
                // `gte`, not `gt`: the boundary row is re-read and upserted, which
                // is a no-op, and two rows sharing a millisecond cannot lose one.
                query = query.gte(since.column, value: since.value)
            }
            // The page boundary is a SECOND filter, ANDed with the delta one
            // above. They answer different questions — `since` is which rows
            // are worth asking for, `after` is where the last page stopped —
            // and conflating them is what made `updated_at` look like a cursor
            // it cannot be (it is not unique, so it cannot end a page).
            if let after { query = query.or(after) }
            let response: PostgrestResponse<[T]> = try await Self.ordered(query, by: request.order)
                .limit(limit)
                .execute()
            return (response.value, response.data)
        }
    }

    public func selectIn<T: Decodable & Sendable>(
        _ type: T.Type, table: String, column: String, values: [String]
    ) async throws -> [T] {
        var out: [T] = []
        // Keyed on `id`: the one caller is `workout_sets`, whose primary key it
        // is. A composite-key table would need the order passed through.
        // A URL has a length; 2,000 uuids in one `in.(…)` do not fit in it.
        for chunk in Pagination.chunks(values, size: Pagination.inListLimit) {
            out += try await Pagination.keyset(order: ["id"]) { after, limit in
                var query = client.from(table).select().eq("user_id", value: userId).in(column, values: chunk)
                if let after { query = query.or(after) }
                let response: PostgrestResponse<[T]> = try await Self.ordered(query, by: ["id"])
                    .limit(limit)
                    .execute()
                return (response.value, response.data)
            }
        }
        return out
    }

    /// `HEAD /rest/v1/<table>?select=*&user_id=eq.<id>`, `Prefer: count=exact`.
    ///
    /// `head: true` is what makes this affordable from a phone: the request
    /// transfers no rows at all, and the number arrives in the `Content-Range`
    /// header. Twenty-six of these is twenty-six empty bodies.
    ///
    /// `exact` rather than `planned` or `estimated`. The two cheap options ask
    /// the query planner, which answers from `pg_class.reltuples` — a figure
    /// that is stale between vacuums and routinely several percent out. Several
    /// percent out is exactly the size of the discrepancy this call exists to
    /// find, so an estimate here would be a screen that says "close enough" to
    /// the one question it was built to answer.
    public func count(table: String) async throws -> Int {
        let response = try await client
            .from(table)
            .select("*", head: true, count: .exact)
            .eq("user_id", value: userId)
            .execute()
        // Nil means PostgREST sent no `Content-Range`, which it always does
        // under `count=exact` — including `*/0` for a table with no rows.
        return response.count ?? 0
    }

    private static func ordered(_ query: PostgrestFilterBuilder, by columns: [String]) -> PostgrestTransformBuilder {
        var q: PostgrestTransformBuilder = query
        for column in columns { q = q.order(column, ascending: true) }
        return q
    }
}

/// Keyset paging over PostgREST, until a short page.
///
/// ── WHAT THE KEY IS, AND WHY IT IS NOT `(updated_at, id)` ───────────────────
/// The key is `MirrorTable.order`: the table's PRIMARY KEY in column order,
/// which the catalogue already declares and every page is already sorted by.
/// It is the only total order all 33 mirrored tables are guaranteed to have,
/// it is UNIQUE by definition, and it is the one order the server holds an
/// index for — so each page is an index seek instead of a sort.
///
/// `(updated_at, id)` — the shape the Supabase guide reaches for — cannot be
/// spelled against this schema. Eleven of the mirrored tables have no `id`
/// column at all (`daily_targets` is keyed `user_id,date`; `plan_phase_volume`
/// on four columns) and twelve carry no `updated_at`, so either half of that
/// pair is a 400 on a third of the catalogue. Where both DO exist it is still
/// the worse order: there is no `(updated_at, id)` index to seek on, and a row
/// edited mid-pull bumps its own `updated_at` forward past the cursor and is
/// read a second time. `updated_at` stays what it already was here — the DELTA
/// filter (`MirrorRequest.since`), which is a different question from where a
/// page ended.
///
/// ── WHAT REPLACED WHAT ──────────────────────────────────────────────────────
/// `range` made the server walk and discard every row it had already sent:
/// page N pays an `OFFSET` of N×1000, so a backfill is O(pages²) server work.
/// It is also only stable while nothing is written mid-pull — one insert
/// landing on page 1 while page 2 is in flight slides EVERY later row back by
/// one, and the row that crosses the boundary is never read. A cursor has no
/// such shift: a page is defined by the key it starts after, not by how many
/// rows came before it.
///
/// What a cursor does NOT fix, and this is worth being exact about: most of
/// these tables are keyed on a random v4 uuid, so a row inserted mid-pull
/// lands at a uniformly random position and lands BEFORE the cursor about
/// half the time. Such a row is missed by this pull exactly as it was under
/// `range` — the delta filter catches it on the next one. The win here is the
/// O(pages²) server work and the shifting boundary, not at-most-once delivery,
/// which this sync has never claimed.
enum Pagination {
    /// PostgREST's default `db-max-rows`. Asking for more than the server will
    /// give is how a page looks full when it was cut.
    static let pageSize = 1000
    /// How many values one `in.(…)` carries. Session ids are 36 bytes; 200 of
    /// them is ~7 KB of URL, under every proxy's limit.
    static let inListLimit = 200

    /// Every row, page by page.
    ///
    /// `fetch(after, limit)` runs the query with `after` — a PostgREST `or=(…)`
    /// body meaning "strictly past the last row you gave me", `nil` on the
    /// first page — and hands back the decoded rows AND the bytes they were
    /// decoded from, which is where the next cursor comes from.
    ///
    /// `db-max-rows` truncates a page silently, so a truncated page and a short
    /// page cannot be told apart; the loop stops on `< pageSize` and not on
    /// empty, which is why `pageSize` must stay at the server's own limit.
    static func keyset<T>(
        order: [String],
        pageSize: Int = pageSize,
        fetch: (_ after: String?, _ limit: Int) async throws -> (rows: [T], body: Data)
    ) async throws -> [T] {
        var out: [T] = []
        var after: String?
        while true {
            let page = try await fetch(after, pageSize)
            out += page.rows
            guard page.rows.count == pageSize else { return out }
            // Termination: the key is UNIQUE, every row of the next page is
            // strictly past this cursor, and the table is finite — so the
            // cursor can only move forward and the pages can only run out. Two
            // rows sharing an `updated_at` cannot stall it because
            // `updated_at` is not part of the key.
            //
            // The `next != after` guard is for the server disagreeing — a
            // filter it ignored, a row handed back twice. Stopping one page
            // early loses rows the next sync re-reads; asking for the same
            // page for ever does not stop at all.
            guard let next = try cursor(after: page.body, order: order), next != after else { return out }
            after = next
        }
    }

    /// The `or=(…)` body for "strictly after the last row of this page", in the
    /// lexicographic order of `order`:
    ///
    ///     one column   id.gt."9f3…"
    ///     two columns  user_id.gt."u",and(user_id.eq."u",date.gt."2026-09-05")
    ///
    /// `nil` when the body held no rows to page past.
    ///
    /// ── WHY THE PAGE IS PARSED A SECOND TIME ────────────────────────────────
    /// The rows left as an opaque `T`: the catalogue is 33 row types behind one
    /// generic call, so there is no property here to read a key off, and a
    /// protocol to expose one would have to be threaded through every
    /// generated type. A second pass over the SAME bytes costs no request and
    /// only runs on a FULL page — the page about to be followed by another. A
    /// table that comes down in one page, which is every table but the three
    /// big ones, never pays it.
    static func cursor(after body: Data, order: [String]) throws -> String? {
        guard !order.isEmpty,
              let last = try JSONDecoder().decode([[String: AnyJSON]].self, from: body).last
        else { return nil }

        // Every key column in this schema is a `uuid`, a `date` or `text`, so
        // the value is always a JSON string. A key column that is absent or
        // is not one THROWS rather than ending the pull: a half-read table
        // reported as a success is the failure mode this whole file is
        // written against, and `MirrorPuller` already turns a throw into one
        // named line in the Sync Doctor.
        let values = try order.map { column -> String in
            guard let value = last[column]?.stringValue else {
                throw PagingError.unkeyed(column: column)
            }
            return quoted(value)
        }

        // `(k0 > v0) OR (k0 = v0 AND k1 > v1) OR …` — the lexicographic "after
        // this row", one term per key column. Four columns is the widest key
        // in the catalogue (`plan_phase_volume`).
        let terms = order.indices.map { index -> String in
            let equal = zip(order, values).prefix(index).map { "\($0).eq.\($1)" }
            let greater = "\(order[index]).gt.\(values[index])"
            return equal.isEmpty ? greater : "and(\((equal + [greater]).joined(separator: ",")))"
        }
        return terms.joined(separator: ",")
    }

    /// Always quoted, never bare. A comma is what separates the terms of an
    /// `or=(…)`, and `item_key`, `plan_id` and `exercise_key` are free text
    /// that can contain one: unquoted, an `item_key` of `omega,3` is read as
    /// two filter terms and 400s the whole pull. Quoting every value rather
    /// than only the ones that need it keeps the rule one line long.
    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// The offset pager keyset replaced. Nothing in the app calls it any more;
    /// `PaginationTests` still does, and this stays only until that suite goes
    /// with it.
    static func all<T>(
        pageSize: Int = pageSize, fetch: (Int, Int) async throws -> [T]
    ) async throws -> [T] {
        var out: [T] = []
        var from = 0
        while true {
            let page = try await fetch(from, from + pageSize - 1)
            out += page
            if page.count < pageSize { return out }
            from += pageSize
        }
    }

    static func chunks<T>(_ values: [T], size: Int) -> [[T]] {
        guard !values.isEmpty else { return [] }
        return stride(from: 0, to: values.count, by: size).map { Array(values[$0..<min($0 + size, values.count)]) }
    }
}

/// A page that cannot say where it ended.
///
/// Its own error rather than a `MirrorError` case because it is a CATALOGUE
/// bug, not a network one: the only way to reach it is an `order` naming a
/// column the table does not return.
enum PagingError: Error, CustomStringConvertible {
    case unkeyed(column: String)

    var description: String {
        switch self {
        case .unkeyed(let column):
            return "Cannot page: the last row carries no string `\(column)` to key on."
        }
    }
}
