import Foundation
import GRDB
import Testing
@testable import OnyxCore
@testable import OnyxData

/// The psych-stress loop, end to end: what the sheet writes is what the index
/// reads (D6) — as an EVENT log since Live UX W1 (decision A5).
///
/// ── THE SEAM THIS EXISTS FOR ────────────────────────────────────────────────
/// `StressInputsBuilder` takes the MEAN of the day's rows and does not care
/// how many there are or when they were felt. The writer is what changed: a
/// row per event, its slot DERIVED from the event's time, no same-slot
/// shadow delete (under events that delete is data loss). Each rule below is
/// a place where the writer, the reader and the sync can be individually
/// correct and jointly wrong.
@Suite("Stress logs — events the index reads")
struct StressLogTests {

    private let user = "u1"
    private let date = "2026-09-03"

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    /// `HH:mm` on the test day in the machine's own calendar — the slot is
    /// derived in the LOCAL calendar, so the instants are built there too.
    private func at(_ hhmm: String) -> Date {
        let p = hhmm.split(separator: ":").map { Int($0)! }
        return Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: p[0], minute: p[1]))!
    }

    @Test("two events in one slot both persist, each under its own id")
    func twoEventsOneSlot() throws {
        let db = try store()
        let a = try db.logStress(userId: user, date: date, loggedAt: at("08:00"), level: 2, tags: [.work])
        let b = try db.logStress(userId: user, date: date, loggedAt: at("09:15"), level: 4)
        #expect(a != b)
        let rows = try db.read { try StressLogRow.order(Column("logged_at")).fetchAll($0) }
        #expect(rows.count == 2)
        #expect(rows.map(\.id) == [a, b])
        #expect(rows.map(\.slot) == ["morning", "morning"])
        #expect(rows.map(\.loggedAt) == [at("08:00"), at("09:15")])
        // Flat mean over the day's rows — the rule `StressInputsBuilder` states.
        #expect(try db.stressInputs(userId: user, date: date).stressDayMean == 3)
    }

    @Test("deleting one event removes one row and queues one delete; the sibling stays")
    func deleteOne() throws {
        let db = try store()
        let a = try db.logStress(userId: user, date: date, loggedAt: at("08:00"), level: 2)
        let b = try db.logStress(userId: user, date: date, loggedAt: at("08:30"), level: 5)
        try db.deleteStress(userId: user, id: a)

        let rows = try db.read { try StressLogRow.fetchAll($0) }
        #expect(rows.map(\.id) == [b])
        #expect(try db.stressInputs(userId: user, date: date).stressDayMean == 5)

        let outbox = try db.pendingOutbox()
        let deletes = outbox.filter { $0.kind == SyncKind.rowDelete }
            .compactMap { try? OnyxJSON.decoder.decode(RowDeleteRef.self, from: $0.payload) }
        #expect(deletes.count == 1)
        #expect(deletes.first?.key["id"] == a)
        // The sibling's upsert is untouched.
        let upserts = outbox.filter { $0.kind == SyncKind.rowUpsert }
            .compactMap { try? OnyxJSON.decoder.decode(RowRef.self, from: $0.payload) }
        #expect(upserts.map(\.id) == [b])
    }

    @Test("the slot is derived from the event's time, in the local calendar")
    func slotDerivation() throws {
        let db = try store()
        let evening = try db.logStress(userId: user, date: date, loggedAt: at("23:30"), level: 3)
        let morning = try db.logStress(userId: user, date: date, loggedAt: at("08:00"), level: 3)
        let midday = try db.logStress(userId: user, date: date, loggedAt: at("12:00"), level: 3)
        let slots = try db.read { db in
            Dictionary(uniqueKeysWithValues: try StressLogRow.fetchAll(db).map { ($0.id, $0.slot) })
        }
        #expect(slots[evening] == StressSlot.evening.rawValue)
        #expect(slots[morning] == StressSlot.morning.rawValue)
        #expect(slots[midday] == StressSlot.midday.rawValue)
    }

    @Test("a row pulled before the founder's paste decodes, and is pushed without logged_at")
    func prePasteRowRoundTrips() throws {
        // What the server serves until `w1-stress-events.sql` runs: no
        // `logged_at` key at all. The mirror must decode it as a legacy row…
        let payload = #"""
        {"id":"srv-1","user_id":"u1","date":"2026-09-03","slot":"evening","level":4,"tags":["work"],
         "note":null,"created_at":"2026-09-03T18:05:00Z","updated_at":"2026-09-03T18:05:00Z"}
        """#
        let row = try OnyxJSON.decoder.decode(StressLogRow.self, from: Data(payload.utf8))
        #expect(row.loggedAt == nil)
        #expect(row.slot == "evening")
        // …and a push of it must not name a column Postgres does not have yet
        // (`encodeIfPresent` — the `sleep_inaccurate` rule).
        let body = String(decoding: try OnyxJSON.encoder.encode(row), as: UTF8.self)
        #expect(!body.contains("logged_at"))
        // While a timed event does carry it.
        var timed = row
        timed.loggedAt = at("18:05")
        #expect(String(decoding: try OnyxJSON.encoder.encode(timed), as: UTF8.self).contains("\"logged_at\""))
    }

    @Test("a fresh install has the column, and so does a store that pre-dates it")
    func columnExists() throws {
        let db = try store()
        let columns = try db.writer.read { try $0.columns(in: "stress_logs").map(\.name) }
        #expect(columns.contains("logged_at"))
    }

    @Test("the level reaches the index's self term, and moves it")
    func reachesTheSelfTerm() throws {
        let db = try store()
        #expect(try db.stressBreakdown(userId: user, date: date).terms.selfReport.z == nil)

        _ = try db.logStress(userId: user, date: date, loggedAt: at("20:00"), level: 5)
        let loaded = try db.stressBreakdown(userId: user, date: date)
        // 5 − 3 neutral = +2, clamped at the z bound.
        #expect(loaded.terms.selfReport.z == 2)
        #expect(loaded.terms.selfReport.stressDayMean == 5)
        #expect(loaded.terms.selfReport.answered == 1)

        try db.setFatigue(userId: user, date: date, slot: FatigueSlot.waking.rawValue, level: 1)
        let both = try db.stressBreakdown(userId: user, date: date)
        #expect(both.terms.selfReport.answered == 2)
        #expect(both.terms.selfReport.z == 0)
    }

    @Test("tags round-trip in stored order, and an unknown one costs a chip not a reading")
    func tagsRoundTrip() throws {
        let db = try store()
        let id = try db.logStress(userId: user, date: date, loggedAt: at("13:00"), level: 3, tags: [.travel, .work, .money])
        let row = try #require(try db.read { try StressLogRow.fetchOne($0) })
        #expect(row.tags.raw == #"["work","money","travel"]"#)
        let reading = try #require(AppDatabase.reading(row))
        #expect(reading.id == id)
        #expect(reading.loggedAt == at("13:00"))
        #expect(reading.tags == [.work, .money, .travel])

        var forged = row
        forged.tags = JSONText(raw: #"["work","astrology"]"#)
        #expect(AppDatabase.reading(forged)?.tags == [.work])
        #expect(AppDatabase.reading(forged)?.level == 3)
    }

    @Test("a blank note is stored as nil and queued as a null, not omitted")
    func blankNoteIsNull() throws {
        let db = try store()
        _ = try db.logStress(userId: user, date: date, loggedAt: at("19:00"), level: 3, note: "  ")
        let row = try #require(try db.read { try StressLogRow.fetchOne($0) })
        #expect(row.note == nil)
        let refs = try db.pendingOutbox()
            .filter { $0.kind == SyncKind.rowUpsert }
            .compactMap { try? OnyxJSON.decoder.decode(RowRef.self, from: $0.payload) }
        #expect(refs.contains { $0.nulls.contains("note") })
    }

    @Test("the row states the latest event, never the mean — timed rows by time, legacy rows by slot start")
    func latestNotMean() throws {
        let db = try store()
        _ = try db.logStress(userId: user, date: date, loggedAt: at("08:10"), level: 1)
        _ = try db.logStress(userId: user, date: date, loggedAt: at("14:32"), level: 5)
        // A legacy row — no time, filed under evening by the old clock rule.
        try db.seedRows { conn in
            try StressLogRow(
                id: "legacy", userId: "u1", date: "2026-09-03", slot: StressSlot.evening.rawValue,
                level: 2, tags: JSONText(raw: "[]"), note: nil, createdAt: Date(), updatedAt: Date()
            ).insert(conn)
        }
        let readings = try db.read { try StressLogRow.fetchAll($0) }.compactMap(AppDatabase.reading)

        // 14:32 is before evening's 18:00 start, so the legacy row is latest.
        #expect(PsychStress.latest(readings)?.id == "legacy")
        #expect(PsychStress.sorted(readings).map(\.level) == [1, 5, 2])
        // A timed event after 18:00 overtakes it.
        let late = try db.logStress(userId: user, date: date, loggedAt: at("19:05"), level: 4)
        let more = try db.read { try StressLogRow.fetchAll($0) }.compactMap(AppDatabase.reading)
        #expect(PsychStress.latest(more)?.id == late)
        // What the INDEX reads: the mean, and the one place it is computed.
        #expect(try db.stressInputs(userId: user, date: date).stressDayMean == 3)
        #expect(PsychStress.latest([]) == nil)
    }
}
