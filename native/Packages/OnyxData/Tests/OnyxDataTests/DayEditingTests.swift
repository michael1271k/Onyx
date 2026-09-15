import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// The Day and Fuel write path: every write lands locally AND queues, and every
/// delete or clear reaches the queue as the thing it is.
@Suite("Editing a day")
struct DayEditingTests {

    private let user = "u1"
    private let date = "2026-09-03"

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    private func kinds(_ db: AppDatabase) throws -> [String] {
        try db.pendingOutbox().map(\.kind).sorted()
    }

    private func deleteRefs(_ db: AppDatabase) throws -> [RowDeleteRef] {
        try db.pendingOutbox()
            .filter { $0.kind == SyncKind.rowDelete }
            .map { try OnyxJSON.decoder.decode(RowDeleteRef.self, from: $0.payload) }
    }

    @Test("a flag on a day nobody has written yet mints the row and queues it")
    func flagOnFreshDay() throws {
        let db = try store()
        let row = try db.editDailyLog(userId: user, date: date) { $0.sleepOnsetTrouble = true }
        #expect(row.sleepOnsetTrouble)
        #expect(row.updatedAt == AppDatabase.localWriteTimestamp)
        #expect(try kinds(db) == [SyncKind.rowUpsert])
        // The same row HealthKit will find — one per day.
        let again = try db.editDailyLog(userId: user, date: date) { $0.steps = 8000 }
        #expect(again.id == row.id)
        #expect(try db.pendingOutbox().count == 1)
    }

    @Test("un-marking an exception day carries the clear to the queue")
    func clearingReachesTheQueue() throws {
        let db = try store()
        try db.editDailyLog(userId: user, date: date) { $0.nutritionException = "Event" }
        try db.editDailyLog(userId: user, date: date, clearing: ["nutrition_exception"]) { $0.nutritionException = nil }
        let ref = try OnyxJSON.decoder.decode(RowRef.self, from: try db.pendingOutbox()[0].payload)
        #expect(ref.nulls == ["nutrition_exception"])
    }

    @Test("a water override leaves exactly one ledger row, and queues the others' deletes")
    func waterOverride() throws {
        let db = try store()
        try db.writer.write { conn in
            var synced = WaterIntakeRow(
                id: "hk-1", userId: user, hkUuid: "hk-uuid-1", loggedAt: Date(), date: date, amountMl: 500, createdAt: Date()
            )
            try synced.save(conn)
        }
        try db.setWaterOverride(userId: user, date: date, ml: 2750.4)

        let rows = try db.writer.read { try WaterIntakeRow.fetchAll($0) }
        #expect(rows.count == 1)
        #expect(rows[0].hkUuid == "manual-water-\(date)")
        #expect(rows[0].amountMl == 2750)
        let day = try db.writer.read { try DailyLogRow.fetchOne($0) }
        #expect(day?.waterMl == 2750)
        #expect(try deleteRefs(db) == [RowDeleteRef(table: "water_intake", key: ["id": "hk-1"])])

        try db.clearWaterOverride(userId: user, date: date)
        #expect(try db.writer.read { try WaterIntakeRow.fetchCount($0) } == 0)
        #expect(try db.writer.read { try DailyLogRow.fetchOne($0) }?.waterMl == nil)
        let dayRef = try db.pendingOutbox()
            .filter { $0.kind == SyncKind.rowUpsert }
            .map { try OnyxJSON.decoder.decode(RowRef.self, from: $0.payload) }
            .first { $0.table == "daily_logs" }
        #expect(dayRef?.nulls == ["water_ml"])
    }

    @Test("clearing the override keeps the glasses and Apple's own row")
    func clearingKeepsWhatWasMeasured() throws {
        // ── THE OTHER HALF OF `— / 3.0 L` (W1) ──────────────────────────────
        // This used to delete the WHOLE ledger and nil `daily_logs.water_ml`,
        // so a day handed back to Apple Health read as untracked until the next
        // successful ingest — and `DailyLogIngest` returns at
        // `guard !payload.isEmpty` when HealthKit has nothing to say, so on a
        // phone where the water read is denied "until then" is never.
        //
        // The one-way door is the `manual-water-` sentinel. That is all this
        // button has to open.
        let db = try store()
        try db.writer.write { conn in
            var synced = WaterIntakeRow(
                id: "hk-1", userId: user, hkUuid: "hk-uuid-1", loggedAt: Date(),
                date: date, amountMl: 500, createdAt: Date()
            )
            try synced.save(conn)
        }
        try db.addWaterGlass(userId: user, date: date, ml: 250)
        try db.writer.write { conn in
            var manual = WaterIntakeRow(
                id: "man-1", userId: user, hkUuid: ManualEntry.waterSentinel(date),
                loggedAt: Date(), date: date, amountMl: 2000, createdAt: Date()
            )
            try manual.save(conn)
        }

        try db.clearWaterOverride(userId: user, date: date)

        let left = try db.writer.read { try WaterIntakeRow.order(Column("id")).fetchAll($0) }
        #expect(left.map(\.id) == ["hk-1"] || left.map(\.amountMl).reduce(0, +) == 750,
                "Apple's row and the glass survive: \(left.map(\.id))")
        #expect(left.count == 2)
        // And the projection is re-derived from what is left, by the rule
        // `WaterTruth` reads it back with — so the two stores cannot disagree.
        let day = try db.writer.read { try DailyLogRow.fetchOne($0) }
        #expect(day?.waterMl == 750)
        #expect(WaterTruth.ml(log: day?.waterMl, ledger: left.map(\.amountMl)) == 750)
    }

    @Test("clearing the last thing on the day still clears the column, on both sides")
    func clearingAnEmptyDayStillNils() throws {
        // The override was the only water there was, so nil IS the answer — and
        // `water_ml` has to be NAMED in `clearing` or the server's copy is
        // merged over rather than cleared.
        let db = try store()
        try db.setWaterOverride(userId: user, date: date, ml: 2000)
        try db.clearWaterOverride(userId: user, date: date)
        #expect(try db.writer.read { try WaterIntakeRow.fetchCount($0) } == 0)
        #expect(try db.writer.read { try DailyLogRow.fetchOne($0) }?.waterMl == nil)
        let dayRef = try db.pendingOutbox()
            .filter { $0.kind == SyncKind.rowUpsert }
            .map { try OnyxJSON.decoder.decode(RowRef.self, from: $0.payload) }
            .first { $0.table == "daily_logs" }
        #expect(dayRef?.nulls == ["water_ml"])
    }

    @Test("skipping a dose is one row; undoing it deletes the row rather than writing taken")
    func supplementSkip() throws {
        let db = try store()
        try db.setSupplementSkipped(userId: user, date: date, itemKey: "creatine", skipped: true)
        let skipped = try db.writer.read { try SupplementLogRow.fetchAll($0) }
        #expect(skipped.count == 1)
        #expect(skipped[0].taken == false)

        try db.setSupplementSkipped(userId: user, date: date, itemKey: "creatine", skipped: false)
        #expect(try db.writer.read { try SupplementLogRow.fetchCount($0) } == 0)
        // The skip's upsert was superseded: the queue holds the delete and nothing else.
        #expect(try kinds(db) == [SyncKind.rowDelete])
        #expect(try deleteRefs(db)[0].key == ["user_id": user, "date": date, "item_key": "creatine"])
    }

    @Test("a fatigue reading supersedes the legacy key it stands in for")
    func fatigueSupersedesLegacy() throws {
        let db = try store()
        try db.writer.write { conn in
            var legacy = FatigueLogRow(id: "old", userId: user, date: date, slot: "noon", level: 3, createdAt: Date())
            try legacy.save(conn)
        }
        try db.setFatigue(userId: user, date: date, slot: "pre", level: 2, superseding: ["noon"])
        let rows = try db.writer.read { try FatigueLogRow.fetchAll($0) }
        #expect(rows.map(\.slot) == ["pre"])
        #expect(try deleteRefs(db) == [RowDeleteRef(table: "fatigue_logs", key: ["id": "old"])])

        try db.setFatigue(userId: user, date: date, slot: "pre", level: nil)
        #expect(try db.writer.read { try FatigueLogRow.fetchCount($0) } == 0)
    }

    @Test("a swap writes both dates, and undoing it clears both — plus the stimulant rows")
    func swapAndUndo() throws {
        let db = try store()
        try db.setSupplementSkipped(userId: user, date: "2026-09-05", itemKey: "caffeine", skipped: true)
        try db.applyScheduleWrites(
            userId: user,
            [(date: "2026-09-03", dayKey: "rest"), (date: "2026-09-05", dayKey: "legs_a")],
            trainingOnlySupplementKeys: ["caffeine", "citrulline"]
        )
        #expect(try db.writer.read { try ScheduleOverrideRow.fetchCount($0) } == 2)
        // The skipped stimulant on the swapped date is gone: absence means taken,
        // and a rest→train move must not carry a skip for a dose never asked about.
        #expect(try db.writer.read { try SupplementLogRow.fetchCount($0) } == 0)

        try db.clearScheduleOverrides(userId: user, dates: ["2026-09-03", "2026-09-05"])
        #expect(try db.writer.read { try ScheduleOverrideRow.fetchCount($0) } == 0)
        let deleted = try deleteRefs(db).filter { $0.table == "schedule_overrides" }.map { $0.key["date"] }
        #expect(Set(deleted.compactMap { $0 }) == ["2026-09-03", "2026-09-05"])
    }

    @Test("a day target is keyed the way the server keys it")
    func dailyTargetKey() throws {
        let db = try store()
        try db.setDailyTarget(userId: user, date: date) { $0.kcal = 2650; $0.trackFat = false }
        let ref = try OnyxJSON.decoder.decode(RowRef.self, from: try db.pendingOutbox()[0].payload)
        #expect(ref.id == AppDatabase.rowID([user, date]))
        try db.clearDailyTarget(userId: user, date: date)
        #expect(try kinds(db) == [SyncKind.rowDelete])
    }

    @Test("a typed scale reading outside the physiologic bounds is refused, and nothing lands")
    func bodyMetricsAreBounded() throws {
        let db = try store()
        try db.saveBodyMetrics(userId: user, date: date) { $0.weightKg = 64.8; $0.bodyFatPct = 14.1 }
        #expect(throws: BodyMetricError.self) {
            try db.saveBodyMetrics(userId: user, date: date) { $0.bodyFatPct = 141 }
        }
        #expect(throws: BodyMetricError.self) {
            try db.saveBodyMetrics(userId: user, date: date) { $0.musclePercent = 4 }
        }
        #expect(throws: BodyMetricError.self) {
            try db.saveBodyMetrics(userId: user, date: date) { $0.visceralFat = 55 }
        }
        // The refused write touched neither row.
        let log = try db.writer.read { try DailyLogRow.fetchOne($0) }
        #expect(log?.bodyFatPct == 14.1 && log?.musclePercent == nil && log?.visceralFat == nil)

        // ...but a lean InBody muscle reading is NOT an artifact and lands.
        try db.saveBodyMetrics(userId: user, date: date) { $0.musclePercent = 80.2 }
        #expect(try db.writer.read { try DailyLogRow.fetchOne($0) }?.musclePercent == 80.2)
        #expect(try db.writer.read { try BodyCompositionRow.fetchOne($0) }?.bodyFatPct == 14.1)
    }

    @Test("scale readings open the ledger only once a weight exists")
    func bodyMetricsMirror() throws {
        let db = try store()
        try db.saveBodyMetrics(userId: user, date: date) { $0.musclePercent = 41.2 }
        #expect(try db.writer.read { try BodyCompositionRow.fetchCount($0) } == 0)

        try db.saveBodyMetrics(userId: user, date: date) { $0.weightKg = 64.8; $0.bodyFatPct = 14.1 }
        let ledger = try db.writer.read { try BodyCompositionRow.fetchOne($0) }
        #expect(ledger?.weightKg == 64.8)
        #expect(ledger?.bodyFatPct == 14.1)
        #expect(ledger?.musclePct == 41.2)
        #expect(ledger?.measuredAt == AppDatabase.utcInstant(date, hour: 7))
    }
}
