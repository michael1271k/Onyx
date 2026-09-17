import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// The stack, edited on the phone, reaching the server.
///
/// ── WHY THIS SUITE IS THE WHOLE POINT OF W6's DATA HALF ─────────────────────
/// `custom_supplements` carried a push closure from Wave 4 and nothing that
/// could fire it: the phone had no way to add, edit or retire a supplement, so
/// "the push path is wired" was a statement about a closure nobody had called.
/// Every test here writes through the app's own API and then drains, which is
/// the only way to tell the difference.
@Suite("The stack pushes")
struct StackPushTests {

    private let user = "u1"

    private actor RecordingPush: MirrorPushRemote {
        var sent: [(table: String, conflict: String, json: String, nulls: [String])] = []
        var deleted: [(table: String, key: [String: String])] = []

        func upsertRow<T: Encodable & Sendable>(_ row: T, table: String, conflict: String, nulls: [String]) async throws {
            let data = try OnyxJSON.encoder.encode(row)
            sent.append((table, conflict, String(decoding: data, as: UTF8.self), nulls))
        }

        func deleteRow(table: String, key: [String: String]) async throws {
            deleted.append((table, key))
        }
    }

    private struct IdleSyncRemote: SyncRemote {
        func exerciseCatalogue() async throws -> [RemoteExercise] { [] }
        func upsertSessions(_ rows: [RemoteSessionRow], ignoreDuplicates: Bool) async throws {}
        func upsertSets(_ rows: [RemoteSetRow]) async throws {}
        func deleteSets(ids: [String]) async throws {}
    }

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    @discardableResult
    private func drain(_ db: AppDatabase, _ push: RecordingPush) async throws -> (pushed: Int, failed: Int) {
        let report = try await SyncEngine(database: db, remote: IdleSyncRemote(), rows: push).drain()
        return (report.pushed, report.failed)
    }

    @Test("adding a supplement uploads the row, with a log key of its own")
    func addPushes() async throws {
        let db = try store()
        let id = try db.addCustomSupplement(
            userId: user, name: "Zinc", dose: "15 mg", color: "#8E9AAC", form: "tablet", time: "22:00",
            schedule: CustomSchedule(days: [1, 5], slot: "Before Bed"),
            micros: ["zinc": 15]
        )

        let push = RecordingPush()
        let report = try await drain(db, push)
        #expect(report.pushed == 1)
        #expect(report.failed == 0)

        let sent = await push.sent
        #expect(sent.count == 1)
        #expect(sent[0].table == "custom_supplements")
        #expect(sent[0].conflict == "id")
        #expect(sent[0].json.contains("\"name\":\"Zinc\""))
        // The key is written at insert rather than left to the read-time
        // fallback, so an edit to the schedule can never move it.
        #expect(sent[0].json.contains("custom:\(id)"))
    }

    @Test("archiving uploads a date; un-archiving says the column's name out loud")
    func archivePushes() async throws {
        let db = try store()
        let id = try db.addCustomSupplement(userId: user, name: "Zinc", dose: "15 mg")
        _ = try await drain(db, RecordingPush())

        try db.setCustomSupplementArchived(id: id, userId: user, archived: true, at: Date(timeIntervalSince1970: 1_780_000_000))
        let archive = RecordingPush()
        #expect(try await self.drain(db, archive).pushed == 1)
        let archived = await archive.sent
        #expect(archived[0].json.contains("\"archived_at\""))
        // The row carries a date now, so `archived_at` is NOT among the columns
        // being cleared — the others are nil on this row and always were.
        #expect(!archived[0].nulls.contains("archived_at"))

        // A merge upsert drops a nil rather than writing one, so the row would
        // stay archived on the server for ever without the explicit null.
        try db.setCustomSupplementArchived(id: id, userId: user, archived: false)
        let restore = RecordingPush()
        #expect(try await self.drain(db, restore).pushed == 1)
        let restored = await restore.sent
        #expect(restored[0].nulls.contains("archived_at"))
    }

    @Test("clearing a supplement's time reaches the server as a null")
    func clearedColumnsAreNamed() async throws {
        let db = try store()
        let id = try db.addCustomSupplement(
            userId: user, name: "Zinc", dose: "15 mg", color: "#8E9AAC", form: "tablet", time: "22:00",
            schedule: CustomSchedule(key: "zinc"), micros: ["zinc": 15]
        )
        let created = RecordingPush()
        try await drain(db, created)
        // An INSERT has nothing to clear: there is no server row yet holding a
        // stale value, so naming columns would be noise.
        let onCreate = await created.sent
        #expect(onCreate[0].nulls.isEmpty)

        try db.editCustomSupplement(id: id, userId: user) { row in
            row.time = nil
            row.color = nil
        }
        let edited = RecordingPush()
        #expect(try await self.drain(db, edited).pushed == 1)
        let sentOnEdit = await edited.sent
        let nulls = sentOnEdit[0].nulls
        // A merge upsert omits a nil, so an unnamed cleared column would keep
        // its old value on the server and come back on the next pull.
        #expect(nulls.contains("time"))
        #expect(nulls.contains("color"))
        #expect(!nulls.contains("form"))
        #expect(!nulls.contains("micros"))
    }

    @Test("deleting uploads a delete keyed on the id")
    func deletePushes() async throws {
        let db = try store()
        let id = try db.addCustomSupplement(userId: user, name: "Mistake", dose: "1")
        _ = try await drain(db, RecordingPush())

        try db.deleteCustomSupplement(id: id, userId: user)
        let push = RecordingPush()
        #expect(try await self.drain(db, push).pushed == 1)
        let deleted = await push.deleted
        #expect(deleted.count == 1)
        #expect(deleted[0].table == "custom_supplements")
        #expect(deleted[0].key == ["id": id])
        let remaining: Int = try await db.writer.read { conn in
            try CustomSupplementRow.fetchCount(conn)
        }
        #expect(remaining == 0)
    }

    @Test("an explicit tick is a row, and clearing it is a delete")
    func markPushes() async throws {
        let db = try store()
        let due = Date(timeIntervalSince1970: 1_780_000_000)
        try db.markSupplement(userId: user, date: "2026-09-05", itemKey: "magnesium", mark: .taken, dueAt: due)

        let push = RecordingPush()
        #expect(try await self.drain(db, push).pushed == 1)
        let sent = await push.sent
        #expect(sent[0].table == "supplement_log")
        #expect(sent[0].conflict == "user_id,date,item_key")
        #expect(sent[0].json.contains("\"taken\":true"))

        try db.markSupplement(userId: user, date: "2026-09-05", itemKey: "magnesium", mark: .cleared)
        let clear = RecordingPush()
        #expect(try await self.drain(db, clear).pushed == 1)
        let deleted = await clear.deleted
        #expect(deleted[0].table == "supplement_log")
        #expect(deleted[0].key["item_key"] == "magnesium")
    }

    @Test("freezing tomorrow writes tomorrow's skip, and leaves today alone")
    func freezeWritesTomorrow() throws {
        let db = try store()
        try db.markSupplement(userId: user, date: "2026-09-06", itemKey: "caffeine", mark: .skipped)
        let rows = try db.writer.read { try SupplementLogRow.fetchAll($0) }
        #expect(rows.count == 1)
        #expect(rows[0].date == "2026-09-06")
        #expect(rows[0].taken == false)
    }

    // MARK: - The reader both tabs ask

    /// The night slot as rows. There is no compiled seed since W2: a stack
    /// is `custom_supplements` rows or it is empty, so the reader tests seed
    /// the two items they assert on.
    private func seedNightStack(_ db: AppDatabase) throws {
        _ = try db.addCustomSupplement(
            userId: user, name: "Magnesium Glycinate", dose: "300 mg", color: "#8A6FA8", form: nil, time: "22:00",
            schedule: CustomSchedule(key: "magnesium", slot: "Before Bed"), micros: ["magnesium": 300]
        )
        _ = try db.addCustomSupplement(
            userId: user, name: "Creatine Monohydrate", dose: "5 g", color: "#3D7AB8", form: nil, time: "15:00",
            schedule: CustomSchedule(key: "creatine", slot: "Lunch / Post-Workout"), micros: ["creatine": 5000]
        )
    }

    @Test("a past day has had every slot; today's late slots have not come")
    func readerHonoursTheClock() throws {
        let db = try store()
        try seedNightStack(db)
        try db.editUserGoals(userId: user) { $0.activePlan = "onyx5"; $0.activePhase = ProgramPhase.cut.rawValue }
        // 08:00 on the selected day.
        let morning = Date(timeIntervalSince1970: 1_756_368_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // Rows, never a seed (W2): the stack is what `custom_supplements` says.
        let past = try db.stackCredit(userId: user, date: "2026-09-01", today: "2026-09-05", now: morning, calendar: calendar)
        #expect(past.doses.allSatisfy { $0.state == .due })
        #expect((past.nutrients["magnesium"] ?? 0) > 0)

        let today = try db.stackCredit(userId: user, date: "2026-09-05", today: "2026-09-05", now: morning, calendar: calendar)
        #expect(today.doses.contains { $0.key == "magnesium" && $0.state == .later })
        #expect(today.nutrients["magnesium"] == nil)
    }

    @Test("a skip at 21:00 takes that dose's micros out of the day")
    func readerHonoursASkip() throws {
        let db = try store()
        try seedNightStack(db)
        try db.editUserGoals(userId: user) { $0.activePlan = "onyx5"; $0.activePhase = ProgramPhase.cut.rawValue }
        let before = try db.stackCredit(userId: user, date: "2026-09-01", today: "2026-09-05")
        #expect((before.nutrients["magnesium"] ?? 0) == 300)

        try db.markSupplement(userId: user, date: "2026-09-01", itemKey: "magnesium", mark: .skipped)
        let after = try db.stackCredit(userId: user, date: "2026-09-01", today: "2026-09-05")
        #expect(after.nutrients["magnesium"] == nil)
        // Everything else on the day is untouched.
        #expect(after.nutrients["vitaminD"] == before.nutrients["vitaminD"])
    }

    // MARK: - W1: a powder is food

    /// The founder's psyllium row: 5 g of a 9 g serving, stored per dose in the
    /// same `micros` jsonb that already carries the potassium.
    @discardableResult
    private func seedPsyllium(_ db: AppDatabase) throws -> String {
        try db.addCustomSupplement(
            userId: user, name: "Psyllium Husk Powder", dose: "5 g", color: "#8E9AAC", form: "powder",
            time: "18:30", schedule: CustomSchedule(key: "psyllium", slot: "Evening"),
            micros: [
                "kcal": 16.7, "carbs": 4.4, "fiber": 3.9, "protein": 0, "fat": 0,
                "sodium": 5.6, "iron": 0.83, "potassium": 50,
            ]
        )
    }

    /// The whole of W1's nutrition half, end to end: the row's macros reach the
    /// day's ring while its fibre reaches the grid, off ONE resolution of the
    /// day's doses.
    @Test("a credited powder delivers macros to the ring and fibre to the grid")
    func stackCreditCarriesMacros() throws {
        let db = try store()
        try seedPsyllium(db)
        try db.editUserGoals(userId: user) { $0.activePlan = "onyx5"; $0.activePhase = ProgramPhase.cut.rawValue }

        let credit = try db.stackCredit(userId: user, date: "2026-09-01", today: "2026-09-05")
        #expect(credit.doses.contains { $0.key == "psyllium" && $0.state == .due })
        #expect(abs(credit.macros.kcal - 16.7) < 0.001)
        #expect(abs(credit.macros.carbs - 4.4) < 0.001)
        #expect(credit.macros.protein == 0)
        #expect(credit.macros.fat == 0)
        // The grid's half of the same scoop.
        #expect(abs((credit.nutrients["fiber"] ?? 0) - 3.9) < 0.001)
        #expect(abs((credit.nutrients["potassium"] ?? 0) - 50) < 0.001)
    }

    /// The rule the ring and the grid share. A skip must take the CALORIES out
    /// too — the day the two diverged, the nutrient row would drop the
    /// potassium while the ring kept charging for the carbohydrate.
    @Test("a skipped powder leaves the ring as well as the grid")
    func skippedPowderLeavesBothTotals() throws {
        let db = try store()
        try seedPsyllium(db)
        try db.editUserGoals(userId: user) { $0.activePlan = "onyx5"; $0.activePhase = ProgramPhase.cut.rawValue }

        try db.markSupplement(userId: user, date: "2026-09-01", itemKey: "psyllium", mark: .skipped)
        let after = try db.stackCredit(userId: user, date: "2026-09-01", today: "2026-09-05")
        #expect(after.macros.isZero)
        #expect(after.nutrients["fiber"] == nil)
    }

    /// A stack that predates this wave carries no macro keys, so the ring must
    /// not move for it — the regression that would turn every existing user's
    /// calorie total into a different number on upgrade.
    @Test("a micronutrient-only stack leaves the ring at zero")
    func legacyStackDoesNotMoveTheRing() throws {
        let db = try store()
        try seedNightStack(db)
        try db.editUserGoals(userId: user) { $0.activePlan = "onyx5"; $0.activePhase = ProgramPhase.cut.rawValue }

        let credit = try db.stackCredit(userId: user, date: "2026-09-01", today: "2026-09-05")
        #expect((credit.nutrients["magnesium"] ?? 0) > 0)
        #expect(credit.macros.isZero)
    }

    /// The exact call the new time wheel's toggle makes — the editor hands an
    /// EMPTY STRING, not a nil, and the row has to land in the "—" bucket.
    /// `editCustomSupplement`'s own null test (above) covers the nil; this one
    /// covers the spelling the UI actually uses.
    @Test("the editor's empty time clears the column and moves the slot")
    func emptyTimeFromTheEditorClears() throws {
        let db = try store()
        let id = try seedPsyllium(db)
        try db.editUserGoals(userId: user) { $0.activePlan = "onyx5"; $0.activePhase = ProgramPhase.cut.rawValue }

        let before = try db.stackCredit(userId: user, date: "2026-09-01", today: "2026-09-05")
        #expect(before.doses.first?.slotTime == "18:30")

        try db.updateCustomSupplement(
            id: id, userId: user, name: "Psyllium Husk Powder", dose: "5 g",
            doseAmount: 5, doseUnit: "g", form: "powder", time: "", days: [], trainingOnly: false
        )

        let after = try db.stackCredit(userId: user, date: "2026-09-01", today: "2026-09-05")
        #expect(after.doses.first?.slotTime == "—")
        // And the schedule's key survived the merge, so the history still joins.
        #expect(after.doses.first?.key == "psyllium")
    }

    @Test("the archived row still reads back through the core's own type")
    func archivedRowDecodes() throws {
        let db = try store()
        let id = try db.addCustomSupplement(
            userId: user, name: "Zinc", dose: "15 mg", time: "22:00",
            schedule: CustomSchedule(key: "zinc"), micros: ["zinc": 15]
        )
        try db.setCustomSupplementArchived(id: id, userId: user, archived: true, at: Date(timeIntervalSince1970: 1_757_000_000))

        let row = try db.writer.read { try CustomSupplementRow.fetchOne($0)! }
        let custom = AppDatabase.custom(row)
        #expect(custom.micros == ["zinc": 15])
        #expect(custom.schedule?.key == "zinc")
        #expect(Supplements.isArchived(custom, on: "2026-09-05"))
        #expect(!Supplements.isArchived(custom, on: "2020-01-01"))
    }
}
