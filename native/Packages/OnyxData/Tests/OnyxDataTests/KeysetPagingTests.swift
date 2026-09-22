import Foundation
import Testing
@testable import OnyxData

/// A page server that HONOURS the cursor it is handed.
///
/// It parses the one filter shape `Pagination.cursor` emits for a single-column
/// key — `id.gt."…"` — because a fake that ignores the filter would prove
/// nothing about paging: every test below is a question about what the second
/// request asks for.
private struct FakePages {
    let ids: [String]
    let pageSize: Int
    /// Every cursor the pager sent, `nil` for the first page.
    private(set) var asked: [String?] = []

    /// One column shared by every row, so "two rows with the same
    /// `updated_at`" is the normal case here rather than the exotic one.
    private static let sameInstant = "2026-09-22T09:00:00+00:00"

    mutating func page(after: String?) -> (rows: [String], body: Data) {
        asked.append(after)
        let cursor = after.flatMap { $0.split(separator: "\"").dropFirst().first.map(String.init) }
        let rows = ids.filter { id in cursor.map { id > $0 } ?? true }.prefix(pageSize)
        let json = rows
            .map { #"{"id":"\#($0)","updated_at":"\#(Self.sameInstant)"}"# }
            .joined(separator: ",")
        return (Array(rows), Data("[\(json)]".utf8))
    }
}

@Suite("Keyset paging")
struct KeysetPagingTests {

    private func body(_ objects: [String]) -> Data { Data("[\(objects.joined(separator: ","))]".utf8) }

    @Test("the first page has no cursor and the last one is short")
    func pagesUntilShort() async throws {
        var server = FakePages(ids: (0..<7).map { "row-\($0)" }, pageSize: 3)
        let all: [String] = try await Pagination.keyset(order: ["id"], pageSize: 3) { after, _ in
            server.page(after: after)
        }
        #expect(all == (0..<7).map { "row-\($0)" }, "every row, once, in key order")
        #expect(server.asked.count == 3, "3 + 3 + 1: the short page ends it")
        #expect(server.asked.first == .some(nil), "the first page asks for no cursor")
        #expect(server.asked.dropFirst().allSatisfy { $0 != nil })
    }

    @Test("rows sharing an updated_at cannot stall the cursor")
    func tiesCannotLoop() async throws {
        // Every row carries the SAME `updated_at`, which is exactly the page
        // boundary a timestamp cursor cannot express. The key is the primary
        // key, so the tie is not the pager's problem.
        var server = FakePages(ids: (0..<9).map { "row-\($0)" }, pageSize: 3)
        let all: [String] = try await Pagination.keyset(order: ["id"], pageSize: 3) { after, _ in
            server.page(after: after)
        }
        #expect(all.count == 9)
        #expect(Set(all).count == 9, "no row is served twice")
        #expect(server.asked.count == 4, "three full pages and one empty")
    }

    @Test("a server that ignores the cursor is stopped, not followed for ever")
    func repeatedPageTerminates() async throws {
        let page = body([#"{"id":"same"}"#, #"{"id":"same"}"#])
        let calls = Counter()
        let all: [String] = try await Pagination.keyset(order: ["id"], pageSize: 2) { _, _ in
            calls.bump()
            return (["a", "b"], page)
        }
        // Two full pages, an identical cursor, and the loop gives up rather
        // than asking a third time. Without that guard this test never ends.
        #expect(calls.count == 2)
        #expect(all.count == 4)
    }

    @Test("one key column, and four")
    func filterShape() throws {
        let one = try Pagination.cursor(after: body([#"{"id":"9f3"}"#]), order: ["id"])
        #expect(one == #"id.gt."9f3""#)

        let two = try Pagination.cursor(
            after: body([#"{"user_id":"u1","date":"2026-09-05"}"#]),
            order: ["user_id", "date"]
        )
        #expect(two == #"user_id.gt."u1",and(user_id.eq."u1",date.gt."2026-09-05")"#)

        // `plan_phase_volume`, the widest key in the catalogue.
        let four = try #require(try Pagination.cursor(
            after: body([#"{"user_id":"u","plan_id":"p","phase":"base","muscle":"quads"}"#]),
            order: ["user_id", "plan_id", "phase", "muscle"]
        ))
        // Four terms — one per key column, each pinning the columns before it.
        #expect(four == #"user_id.gt."u","# + #"and(user_id.eq."u",plan_id.gt."p"),"#
            + #"and(user_id.eq."u",plan_id.eq."p",phase.gt."base"),"#
            + #"and(user_id.eq."u",plan_id.eq."p",phase.eq."base",muscle.gt."quads")"#)
    }

    @Test("a comma in a key cannot split the filter")
    func quotingHoldsTheFilterTogether() throws {
        // `item_key` is free text. Unquoted, `omega,3` is two filter terms and
        // a 400 on the whole pull.
        let filter = try #require(try Pagination.cursor(
            after: body([#"{"user_id":"u","item_key":"omega,3"}"#]),
            order: ["user_id", "item_key"]
        ))
        #expect(filter.hasSuffix(#"and(user_id.eq."u",item_key.gt."omega,3")"#))

        let quote = try Pagination.cursor(after: body([#"{"id":"a\"b"}"#]), order: ["id"])
        #expect(quote == #"id.gt."a\"b""#, "an embedded quote is escaped, not left to end the value")
    }

    @Test("a row with no key column is loud")
    func missingKeyThrows() {
        // Silently returning what has landed so far is a half-read table
        // reported as a success, which is the one outcome sync must never
        // produce.
        #expect(throws: PagingError.self) {
            _ = try Pagination.cursor(after: Data(#"[{"date":"2026-09-05"}]"#.utf8), order: ["id"])
        }
        #expect(throws: PagingError.self) {
            _ = try Pagination.cursor(after: Data(#"[{"id":7}]"#.utf8), order: ["id"])
        }
    }
}

@Suite("Realtime retry ladder")
struct RealtimeRetryTests {

    @Test("it starts near a second, doubles, and stops at a minute")
    func ladder() {
        let floor = MirrorRealtime.retryFloor
        let ceiling = MirrorRealtime.retryCeiling

        for attempt in 0..<100 {
            let delay = MirrorRealtime.retryDelay(attempt: attempt)
            #expect(delay <= ceiling, "attempt \(attempt) must never outrun the poll it is racing")
            #expect(delay >= floor / 2, "attempt \(attempt) must never become a tight loop")
        }
        // A hundred attempts is a socket down for an hour; the shift is clamped
        // so that is a cap, not an overflow.
        #expect(MirrorRealtime.retryDelay(attempt: 0) <= floor)
        #expect(MirrorRealtime.retryDelay(attempt: 6) >= ceiling / 2)
        #expect(MirrorRealtime.pollInterval == ceiling, "the ceiling is only defensible while the poll covers it")
    }

    @Test("jitter, so two devices that dropped together do not re-join together")
    func jittered() {
        let draws = Set((0..<50).map { _ in MirrorRealtime.retryDelay(attempt: 4) })
        #expect(draws.count > 1)
    }
}

/// A call counter for the fake above; `Mutex` from Synchronization needs
/// macOS 15 and the package floor is 14.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
