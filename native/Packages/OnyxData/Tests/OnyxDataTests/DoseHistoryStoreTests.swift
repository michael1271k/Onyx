import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// A dose change, through the app's own editor, read back by every reader that
/// looks at a past day.
///
/// ── THE CLAIM, PROVED END TO END ────────────────────────────────────────────
/// `custom_supplements` held one dose and no date, so changing it rewrote every
/// day the item had ever been taken. Here the dose is changed on the 17th and
/// the 16th is read back three ways — the day's stack (`stackCredit`, what the
/// Stack screen, the Nutrition tab and the reminders resolve), the export's
/// JSON, and the export's Markdown — and every one says the OLD dose before the
/// change and the NEW dose from it.
@Suite("Dose history — the store, the day's stack and the export")
struct DoseHistoryStoreTests {

    private let user = "u1"
    private let changedOn = "2026-09-17"

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    /// Magnesium 300 mg (a mass) and zinc 2 caps (a count, so its micros
    /// scale), both at 22:00; then each changed on the 17th.
    private func seeded() throws -> (db: AppDatabase, magnesium: String, zinc: String) {
        let db = try store()
        let magnesium = try db.addCustomSupplement(
            userId: user, name: "Magnesium", dose: "300 mg", time: "22:00",
            schedule: CustomSchedule(key: "magnesium"), micros: ["magnesium": 300],
            doseAmount: 300, doseUnit: "mg", now: Date(timeIntervalSince1970: 1_757_000_000))
        let zinc = try db.addCustomSupplement(
            userId: user, name: "Zinc", dose: "2 caps", time: "22:00",
            schedule: CustomSchedule(key: "zinc"), micros: ["zinc": 15],
            doseAmount: 2, doseUnit: "cap", now: Date(timeIntervalSince1970: 1_757_000_060))
        try db.updateCustomSupplement(
            id: magnesium, userId: user, name: "Magnesium", dose: "200 mg", doseAmount: 200, doseUnit: "mg",
            form: nil, time: "22:00", days: [], trainingOnly: false, today: changedOn)
        try db.updateCustomSupplement(
            id: zinc, userId: user, name: "Zinc", dose: "1 cap", doseAmount: 1, doseUnit: "cap",
            form: nil, time: "22:00", days: [], trainingOnly: false, today: changedOn)
        return (db, magnesium, zinc)
    }

    private func dose(_ credit: StackCredit, _ key: String) -> String? {
        credit.doses.first { $0.key == key }?.dose
    }

    @Test("the day's stack reads the old dose before the change and the new one from it")
    func dayReaderHonoursHistory() throws {
        let (db, _, _) = try seeded()
        let before = try db.stackCredit(userId: user, date: "2026-09-16", today: "2026-09-20")
        let on = try db.stackCredit(userId: user, date: changedOn, today: "2026-09-20")
        #expect(dose(before, "magnesium") == "300 mg")
        #expect(dose(on, "magnesium") == "200 mg")
        #expect(dose(before, "zinc") == "2 caps")
        #expect(dose(on, "zinc") == "1 cap")
        // The micronutrient credit follows the dose of the day, not today's.
        #expect(before.nutrients["zinc"] == 30)
        #expect(on.nutrients["zinc"] == 15)
    }

    @Test("the export prints each day's own dose, and names the day it changed")
    func exportHonoursHistory() throws {
        let (db, _, _) = try seeded()
        let input = try WeeklyExportBuilder(database: db, userId: user, timeZone: TimeZone(identifier: "UTC")!)
            .input(span: ExportSpan(start: "2026-09-14", end: "2026-09-20"), today: "2026-09-20")
        func day(_ date: String) throws -> ExportDay { try #require(input.days.first { $0.date == date }) }
        func logged(_ date: String, _ key: String) throws -> String? {
            try day(date).supplementsLog?.first { $0.key == key }?.dose
        }

        #expect(try logged("2026-09-16", "magnesium") == "300 mg")
        #expect(try logged(changedOn, "magnesium") == "200 mg")
        #expect(try logged("2026-09-20", "magnesium") == "200 mg")
        #expect(try day("2026-09-16").nutrientsStack?["zinc"] == 30)
        #expect(try day(changedOn).nutrientsStack?["zinc"] == 15)

        #expect(try day(changedOn).supplementDoseChanges == [
            ExportDoseChange(name: "Magnesium", from: "300 mg", to: "200 mg"),
            ExportDoseChange(name: "Zinc", from: "2 caps", to: "1 cap"),
        ])
        #expect(try day("2026-09-16").supplementDoseChanges == nil)
        #expect(try day("2026-09-18").supplementDoseChanges == nil)

        let markdown = WeeklyExport.build(input)
        let row = try #require(markdown.split(separator: "\n").first { $0.hasPrefix(changedOn) })
        #expect(row.contains("dose change Magnesium 300 mg → 200 mg, Zinc 2 caps → 1 cap"))
        #expect(!markdown.split(separator: "\n").contains { $0.hasPrefix("2026-09-16") && $0.contains("dose change") })
    }

    @Test("an edit that leaves the dose alone writes no history")
    func nonDoseEditWritesNothing() throws {
        let db = try store()
        let id = try db.addCustomSupplement(userId: user, name: "Zinc", dose: "15 mg", time: "22:00")
        try db.updateCustomSupplement(
            id: id, userId: user, name: "Zinc picolinate", dose: "15 mg", doseAmount: 15, doseUnit: "mg",
            form: "capsule", time: "21:00", days: [], trainingOnly: false, today: changedOn)
        let row = try db.writer.read { try CustomSupplementRow.fetchOne($0)! }
        #expect(row.dosePeriods == nil)
    }

    @Test("the push carries the history, and a row that never changed carries no key for it")
    func pushCarriesHistoryOnlyWhenThereIsSome() async throws {
        let (db, magnesium, _) = try seeded()
        let untouched = try db.addCustomSupplement(userId: user, name: "D3", dose: "5000 IU", time: "08:00")

        let push = RecordingPush()
        _ = try await SyncEngine(database: db, remote: IdleSyncRemote(), rows: push).drain()
        let sent = await push.sent
        let changed = try #require(sent.first { $0.json.contains(magnesium) })
        #expect(changed.json.contains("dose_periods"))
        #expect(changed.json.contains("2026-09-17"))
        #expect(changed.json.contains("300 mg"))
        let plain = try #require(sent.first { $0.json.contains(untouched) })
        // The `sleep_inaccurate` rule: nil is omitted, so this row's push is
        // accepted by a server that has not grown the column yet.
        #expect(!plain.json.contains("dose_periods"))
        #expect(!plain.nulls.contains("dose_periods"))
    }

    /// The export used to map rows through a second mapper that dropped
    /// `archived_at`, so `Supplements.active(_:on:)` never saw an item leave.
    @Test("an item archived mid-week leaves the export from its archive date")
    func exportSeesArchive() throws {
        let db = try store()
        let id = try db.addCustomSupplement(
            userId: user, name: "Zinc", dose: "15 mg", time: "22:00", schedule: CustomSchedule(key: "zinc"))
        let archivedAt = try #require(ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z"))
        try db.setCustomSupplementArchived(id: id, userId: user, archived: true, at: archivedAt)
        let input = try WeeklyExportBuilder(database: db, userId: user, timeZone: TimeZone(identifier: "UTC")!)
            .input(span: ExportSpan(start: "2026-09-14", end: "2026-09-20"), today: "2026-09-20")
        let logged = { (date: String) in input.days.first { $0.date == date }?.supplementsLog?.map(\.key) ?? [] }
        #expect(logged("2026-09-17") == ["zinc"])
        #expect(logged("2026-09-18") == [])
    }

    /// A fresh store gets the column from the regenerated V1 create, so
    /// `v35` always returns early there. This is the store that already
    /// exists on the phone: built before the column, then migrated.
    @Test("v35 adds the column to a store built before it, and keeps its rows")
    func migrationAltersAnExistingStore() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v34.sessionTelemetry")
        try queue.write { db in
            try db.execute(sql: "ALTER TABLE custom_supplements DROP COLUMN dose_periods")
            try db.execute(sql: "INSERT INTO custom_supplements (id, user_id, name, dose) VALUES ('c1', 'u1', 'Zinc', '15 mg')")
        }
        try AppDatabase.migrator.migrate(queue)
        let row = try queue.read { try CustomSupplementRow.fetchOne($0, key: "c1") }
        #expect(row?.dose == "15 mg")
        #expect(row?.dosePeriods == nil)
        #expect(try queue.read { try $0.columns(in: "custom_supplements").map(\.name) }.contains("dose_periods"))
    }

    private actor RecordingPush: MirrorPushRemote {
        var sent: [(json: String, nulls: [String])] = []

        func upsertRow<T: Encodable & Sendable>(_ row: T, table: String, conflict: String, nulls: [String]) async throws {
            sent.append((String(decoding: try OnyxJSON.encoder.encode(row), as: UTF8.self), nulls))
        }

        func deleteRow(table: String, key: [String: String]) async throws {}
    }

    private struct IdleSyncRemote: SyncRemote {
        func exerciseCatalogue() async throws -> [RemoteExercise] { [] }
        func upsertSessions(_ rows: [RemoteSessionRow], ignoreDuplicates: Bool) async throws {}
        func upsertSets(_ rows: [RemoteSetRow]) async throws {}
        func deleteSets(ids: [String]) async throws {}
    }
}
