import Foundation
import GRDB
import Testing
import OnyxCore
@testable import OnyxData

/// A Health store that answers from a script.
private struct ScriptedHealth: HealthReading {
    var isAvailable = true
    var quantities: [String: Double] = [:]
    var samples: [SleepSample] = []
    /// Answers by WINDOW when set — the overnight HRV read asks for the same
    /// identifier as the daily one, over the night instead of the day.
    var windowed: (@Sendable (String, Date, Date) -> Double?)? = nil

    func requestAuthorization(read: [String]) async throws -> Bool { true }

    func quantity(
        _ identifier: String, reduce: HealthReduce, start: Date, end: Date
    ) async throws -> Double? {
        if let windowed, let v = windowed(identifier, start, end) { return v }
        return quantities[identifier]
    }

    func sleepSamples(start: Date, end: Date) async throws -> [SleepSample] { samples }
}

@Suite("Ingest")
struct IngestTests {

    private let user = "u1"
    private let day = "2026-09-03"

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    private func payload(_ values: [HealthKey: Double], sleep: SleepNight? = nil) -> HealthPayload {
        HealthPayload(date: day, values: values, sleep: sleep)
    }

    private func dailyLog(_ db: AppDatabase) throws -> DailyLogRow? {
        try db.writer.read { conn in
            try DailyLogRow.filter(Column("user_id") == user && Column("date") == day).fetchOne(conn)
        }
    }

    // MARK: Validity

    @Test("a sub-50kg weight is reported, not stored")
    func weightFloor() throws {
        let db = try store()
        let report = try db.ingest(payload([.weight: 4.2, .steps: 900]), userId: user)

        #expect(try dailyLog(db)?.weightKg == nil, "a scale artifact is not a body weight")
        #expect(report.declined.contains { $0.contains("weight") })
        // And it costs the metric, not the push: steps still landed.
        #expect(try dailyLog(db)?.steps == 900)
    }

    @Test("an empty reading writes nothing at all")
    func emptyIsNoOp() throws {
        let db = try store()
        let report = try db.ingest(HealthPayload(date: day), userId: user)
        #expect(report.isEmpty)
        #expect(try dailyLog(db) == nil, "an empty upsert would bump every device's cursor")
        #expect(try db.pendingOutbox().isEmpty)
    }

    // MARK: The mapped keys

    @Test("training and standing minutes reach BOTH their columns")
    func mappedKeysDualWrite() throws {
        let db = try store()
        try db.ingest(payload([.trainingMinutes: 47, .standingMinutes: 278]), userId: user)
        let row = try #require(try dailyLog(db))

        #expect(row.trainingMinutes == 47)
        #expect(row.exerciseMinutes == 47, "the newer column is what the app reads")
        #expect(row.standingMinutes == 278)
        // Apple's stand metric is a HOURS ring count despite the payload name.
        #expect(row.standHours == 5)
    }

    // MARK: Merge

    @Test("a second sync of the same day merges rather than replacing")
    func mergeKeepsWhatItDoesNotKnow() throws {
        let db = try store()
        try db.ingest(payload([.steps: 8000, .weight: 82.4]), userId: user)
        let first = try #require(try dailyLog(db))

        // A macro-only sync arrives later. It must not blank the weight — the
        // web's contract was "only provided keys, preserving fields this source
        // knows nothing about", and a hand-entered InBody reading lives there.
        try db.ingest(payload([.protein: 180]), userId: user)
        let second = try #require(try dailyLog(db))

        #expect(second.id == first.id, "one row per day; a new uuid is a duplicate")
        #expect(second.weightKg == 82.4)
        #expect(second.proteinG == 180)
    }

    // MARK: Manual overrides

    @Test("a hand-corrected day's water is skipped in BOTH places")
    func manualWaterWins() throws {
        let db = try store()
        try db.writer.write { conn in
            try WaterIntakeRow(
                id: "w-manual", userId: user, hkUuid: ManualEntry.waterSentinel(day),
                loggedAt: Date(), date: day, amountMl: 3200, createdAt: Date()
            ).insert(conn)
        }

        let report = try db.ingest(payload([.water: 1100, .steps: 100]), userId: user)

        // ONE probe, TWO skips. The UI renders `daily_logs.water_ml` and the
        // score sums `water_intake`; suppressing only one lets the litres shown
        // and the litres graded drift apart with nothing able to say so.
        #expect(try dailyLog(db)?.waterMl == nil)
        let rows = try db.writer.read { conn in try WaterIntakeRow.fetchAll(conn) }
        #expect(rows.count == 1)
        #expect(rows[0].amountMl == 3200)
        #expect(report.declined.contains { $0.contains("water") })
    }

    @Test("a tapped glass ADDS to Apple's water instead of vetoing it")
    func glassesAddRatherThanOverride() throws {
        let db = try store()
        // What the tab's water row does now: two taps, two glasses.
        try db.addWaterGlass(userId: user, date: day, ml: 250)
        try db.addWaterGlass(userId: user, date: day, ml: 250)
        #expect(try dailyLog(db)?.waterMl == 500)

        let report = try db.ingest(payload([.water: 1100, .steps: 100]), userId: user)

        // The whole of the bug: this used to read nil forever after the first
        // tap, because a glass wrote the manual sentinel and the ingest then
        // declined the day in BOTH stores without saying so anywhere on screen.
        #expect(try dailyLog(db)?.waterMl == 1600)
        #expect(!report.declined.contains { $0.contains("water") })

        // The ledger keeps the two sources apart — Apple's row is the one with
        // no `hk_uuid`, so a re-sync corrects it without touching the glasses —
        // and the score, which sums the ledger, sees the same 1,600.
        let rows = try db.writer.read { conn in try WaterIntakeRow.fetchAll(conn) }
        #expect(rows.count == 3)
        #expect(rows.filter { ManualEntry.isGlass($0.hkUuid) }.count == 2)
        #expect(rows.reduce(0) { $0 + $1.amountMl } == 1600)

        // A second sync corrects Apple's row alone; the glasses are not doubled.
        try db.ingest(payload([.water: 1500]), userId: user)
        #expect(try dailyLog(db)?.waterMl == 2000)
    }

    /// ── THE DAY THAT HAS NO ROW YET ────────────────────────────────────────
    /// The "today's water stays 0" bug (P3 E4, decision 8) lived in the view —
    /// `WaterRow.add()` opened with `guard model.dailyLog != nil`, and
    /// `dailyLogStream` yields nil for a date nothing has written. `ingest`
    /// returns at `guard !payload.isEmpty` when HealthKit has nothing yet, so
    /// every morning before the first foreground sync, and every day on a phone
    /// where the read is denied, the tap was a silent no-op.
    ///
    /// The guard is gone, and this is the contract that makes deleting it safe:
    /// `addWaterGlass` mints the day's row itself and re-reads the ledger sum
    /// inside its own transaction, so it needs nothing to have run before it.
    @Test("a glass lands on a day HealthKit has never written")
    func glassMintsTheDay() throws {
        let db = try store()
        #expect(try dailyLog(db) == nil, "precondition: nothing has written this day")

        try db.addWaterGlass(userId: user, date: day, ml: 250)

        #expect(try dailyLog(db)?.waterMl == 250)
        let rows = try db.writer.read { conn in try WaterIntakeRow.fetchAll(conn) }
        #expect(rows.count == 1)
        #expect(ManualEntry.isGlass(rows[0].hkUuid))

        // And Apple still lands on top of it when the day finally reports.
        let report = try db.ingest(payload([.water: 1100, .steps: 100]), userId: user)
        #expect(try dailyLog(db)?.waterMl == 1350)
        #expect(!report.declined.contains { $0.contains("water") })
    }

    @Test("the sheet's override still wins, glasses included")
    func overrideStillReplacesTheDay() throws {
        let db = try store()
        try db.addWaterGlass(userId: user, date: day, ml: 250)
        // The sheet says "the day was this much" and means it: one row, the
        // manual sentinel, and Apple locked out from here on. That verb still
        // works — it is the TAP that had no business borrowing it.
        try db.setWaterOverride(userId: user, date: day, ml: 3200)

        let report = try db.ingest(payload([.water: 1100]), userId: user)

        #expect(try dailyLog(db)?.waterMl == 3200)
        #expect(report.declined.contains { $0.contains("water") })
        let rows = try db.writer.read { conn in try WaterIntakeRow.fetchAll(conn) }
        #expect(rows.count == 1)
    }

    @Test("re-syncing water reuses the day's row instead of stacking another")
    func waterIsNotDoubled() throws {
        let db = try store()
        try db.ingest(payload([.water: 1100]), userId: user)
        try db.ingest(payload([.water: 2500]), userId: user)

        // The reuse hangs on an `hk_uuid IS NULL` filter. If that ever rendered
        // as `= NULL` — always false — every sync would insert a fresh row and
        // the hydration the SCORE sums would climb all day while the litres on
        // screen stayed right. Silent, and in the flattering direction.
        let rows = try db.writer.read { conn in try WaterIntakeRow.fetchAll(conn) }
        #expect(rows.count == 1)
        #expect(rows[0].amountMl == 2500)
    }

    @Test("a hand-entered macro day is not overwritten by a re-sync")
    func manualMacrosWin() throws {
        let db = try store()
        try db.writer.write { conn in
            try NutritionEntryRow(
                id: "n-manual", userId: user, hkUuid: ManualEntry.macroSentinel(day),
                loggedAt: Date(), date: day, mealType: "daily",
                calories: 2100, proteinG: 190, carbsG: 180, fatG: 60, createdAt: Date()
            ).insert(conn)
        }

        let report = try db.ingest(payload([.calories: 1500, .protein: 90]), userId: user)

        let row = try #require(try db.writer.read { conn in
            try NutritionEntryRow.fetchOne(conn)
        })
        #expect(row.calories == 2100)
        #expect(report.declined.contains { $0.contains("macros") })
    }

    @Test("the water sentinel does not satisfy the macro predicate, or the reverse")
    func sentinelsAreDistinct() {
        // A value that satisfied both would let a macro override silently
        // suppress a water sync. They are checked at different call sites.
        #expect(ManualEntry.isManualMacro(ManualEntry.macroSentinel(day)))
        #expect(!ManualEntry.isManualWater(ManualEntry.macroSentinel(day)))
        #expect(ManualEntry.isManualWater(ManualEntry.waterSentinel(day)))
        // The legacy bare literal is still honoured.
        #expect(ManualEntry.isManualMacro("manual"))
        #expect(!ManualEntry.isManualMacro(nil))
    }

    // MARK: Nutrition

    @Test("calories are never derived from the macros")
    func macrosWithoutCaloriesWriteNoSummaryRow() throws {
        let db = try store()
        try db.ingest(payload([.protein: 180, .carbs: 200, .fats: 60]), userId: user)

        // 4·C + 4·P + 9·F would be a fabricated number that drifts from the app
        // the food was logged in — and `calories` is NOT NULL.
        #expect(try db.writer.read { conn in try NutritionEntryRow.fetchCount(conn) } == 0)
        // The macros still land on the flat row.
        #expect(try dailyLog(db)?.proteinG == 180)
    }

    @Test("vitamin D is converted to IU and the micros arrive as a bundle")
    func microsBundle() throws {
        let db = try store()
        try db.ingest(payload([.calories: 2100, .vitaminD: 15, .sodium: 2400]), userId: user)
        let row = try #require(try db.writer.read { conn in try NutritionEntryRow.fetchOne(conn) })
        let micros = try #require(row.micros)

        // HealthKit reports mcg; every target in the app is in IU. 1 mcg = 40 IU.
        #expect(micros.raw.contains("\"vitaminD\":600"))
        #expect(micros.raw.contains("\"sodium\":2400"))
        #expect(!micros.raw.contains("fiber"), "fibre keeps its own column")
    }

    @Test("a declared day keeps its block's phase instead of being re-banded")
    func declaredDayKeepsThePhase() throws {
        let db = try store()
        try db.writer.write { conn in
            try DailyLogRow(
                id: "d1", userId: user, date: day, createdAt: Date(), updatedAt: Date(),
                nutritionException: "Social", nutritionEstimated: false, sleepOnsetTrouble: false
            ).insert(conn)
            try UserGoalRow(
                id: "g1", userId: user, contextMode: "normal", goalPreset: "cut",
                createdAt: Date(), updatedAt: Date(),
                autoLogSupplements: false, activeProgram: "onyx5", dayCutoffHour: 0,
                unitSystem: "metric", reduceMotion: false, timezone: "Asia/Jerusalem",
                trackRpe: true
            ).insert(conn)
        }

        // 2,150 kcal in week four of a strict cut. The calorie band alone says
        // maintenance; the flag says the block did not change.
        try db.ingest(payload([.calories: 2150]), userId: user)
        let row = try #require(try db.writer.read { conn in try NutritionEntryRow.fetchOne(conn) })
        #expect(row.phase == "cut")
    }

    // MARK: Body and sleep

    @Test("body composition needs a valid weight, and never invents a mass")
    func bodyCompositionNeedsWeight() throws {
        let db = try store()
        let report = try db.ingest(payload([.bodyFat: 18.2, .fatFreeMass: 63.1]), userId: user)
        #expect(try db.writer.read { conn in try BodyCompositionRow.fetchCount(conn) } == 0)
        #expect(report.declined.contains { $0.contains("body composition") })

        try db.ingest(payload([.weight: 77.0, .bodyFat: 18.2, .fatFreeMass: 63.1]), userId: user)
        let row = try #require(try db.writer.read { conn in try BodyCompositionRow.fetchOne(conn) })
        #expect(row.weightKg == 77.0)
        #expect(row.fatFreeMassKg == 63.1)
        // `muscle_mass_kg` is MUSCLE mass and HealthKit has no such type. Handing
        // it LeanBodyMass is what put two quantities ~2.6 kg apart in one column.
        #expect(row.muscleMassKg == nil)
    }

    @Test("an HRV reading far outside the athlete's own 42-day band is declined, not stored")
    func hrvArtifactIsDeclined() throws {
        let db = try store()
        // A fortnight of nights around 60 ms, before the day.
        try db.writer.write { conn in
            for (i, hrv) in ([58, 61, 55, 64, 60, 57, 63, 59, 66, 54, 62, 60, 58, 65] as [Double]).enumerated() {
                try DailyLogRow(id: "h\(i)", userId: user, date: ISODate.addDays(day, -(i + 1))!, createdAt: Date(), updatedAt: Date(),
                                hrvMs: hrv, nutritionEstimated: false, sleepOnsetTrouble: false).insert(conn)
            }
        }
        let report = try db.ingest(payload([.hrv: 182.0, .steps: 4000]), userId: user)
        #expect(try dailyLog(db)?.hrvMs == nil, "the artifact never lands")
        #expect(try dailyLog(db)?.steps == 4000, "the rest of the day does")
        #expect(report.declined.contains { $0.contains("hrv") })
        #expect(!report.hrvOvernight)

        // A plausible reading on the same day stores.
        try db.ingest(payload([.hrv: 44.0]), userId: user)
        #expect(try dailyLog(db)?.hrvMs == 44.0)
    }

    @Test("a body-fat percentage no body has is declined on both rows")
    func bodyFatBoundsOnIngest() throws {
        let db = try store()
        let report = try db.ingest(payload([.weight: 77.0, .bodyFat: 0.9]), userId: user)
        #expect(try dailyLog(db)?.weightKg == 77.0)
        #expect(try dailyLog(db)?.bodyFatPct == nil)
        let ledger = try #require(try db.writer.read { conn in try BodyCompositionRow.fetchOne(conn) })
        #expect(ledger.bodyFatPct == nil)
        #expect(report.declined.contains { $0.contains("body fat") })
    }

    @Test("the night lands inside its own window, not on the calendar day")
    func sleepLandsInTheWindow() throws {
        let db = try store()
        let window = try #require(NightWindow.range(day))
        let night = SleepNight(
            sleepMinutes: 431, deepMin: 74, remMin: 96, coreMin: 261, awakeMin: 18,
            bedStart: nil, bedEnd: nil
        )
        try db.ingest(payload([:], sleep: night), userId: user)

        let row = try #require(try db.writer.read { conn in try SleepSessionRow.fetchOne(conn) })
        #expect(row.startTime >= window.from && row.startTime < window.to)
        #expect(row.durationMin == 431)
        #expect(row.coreMin == 261)
    }

    @Test("re-syncing a night replaces it rather than stacking a second row")
    func sleepIsReplaced() throws {
        let db = try store()
        func night(_ minutes: Int) -> SleepNight {
            SleepNight(sleepMinutes: minutes, deepMin: 60, remMin: 60, coreMin: minutes - 120,
                       awakeMin: 0, bedStart: nil, bedEnd: nil)
        }
        try db.ingest(payload([:], sleep: night(400)), userId: user)
        try db.ingest(payload([:], sleep: night(431)), userId: user)

        let rows = try db.writer.read { conn in try SleepSessionRow.fetchAll(conn) }
        #expect(rows.count == 1)
        #expect(rows[0].durationMin == 431)
    }

    // MARK: The queue

    @Test("every table written is queued, exactly once per row")
    func everyWriteIsQueued() throws {
        let db = try store()
        try db.ingest(
            payload([.steps: 8000, .activeEnergy: 600, .calories: 2100, .water: 2500, .weight: 77]),
            userId: user
        )

        let kinds = try db.pendingOutbox().map(\.kind)
        #expect(kinds.allSatisfy { $0 == SyncKind.rowUpsert })
        let tables = try db.pendingOutbox()
            .compactMap { try? SyncEngine.rowRef(of: $0).table }
        #expect(Set(tables) == [
            "daily_logs", "daily_metrics", "nutrition_entries", "water_intake", "body_composition",
        ])

        // A second sync of the same day must not queue a second copy: the
        // drainer reads the row when it runs, so five edits are one upload.
        try db.ingest(payload([.steps: 9000]), userId: user)
        let after = try db.pendingOutbox().filter {
            (try? SyncEngine.rowRef(of: $0).table) == "daily_logs"
        }
        #expect(after.count == 1)
    }

    // MARK: The reader

    @Test("a day is read with the metric map applied end to end")
    func syncReadsADay() async throws {
        let db = try store()
        let reader = ScriptedHealth(quantities: [
            "HKQuantityTypeIdentifierStepCount": 8421.6,
            "HKQuantityTypeIdentifierOxygenSaturation": 0.982,
            "HKQuantityTypeIdentifierBodyMass": 77.35,
        ])
        let sync = HealthSync(database: db, reader: reader, userId: user)
        _ = try await sync.sync(day: day, isToday: false)

        let row = try #require(try dailyLog(db))
        #expect(row.steps == 8422, "a count is rounded to a count")
        #expect(row.bloodOxygen == 98.2, "scaled before rounding, or it reads 1%")
        #expect(row.weightKg == 77.35)
    }

    @Test("v9: the night's SDNN mean replaces the day's, and is flagged as the night's")
    func overnightHrvWins() async throws {
        let db = try store()
        let bed = Date(timeIntervalSince1970: 1_788_638_400)          // 2026-09-05T20:00Z, in the night of the 6th
        let wake = bed.addingTimeInterval(8 * 3600)
        let night = "2026-09-06"
        let reader = ScriptedHealth(
            quantities: ["HKQuantityTypeIdentifierHeartRateVariabilitySDNN": 58.3, "HKQuantityTypeIdentifierStepCount": 100],
            samples: [SleepSample(value: 3, start: bed, end: wake)],
            windowed: { id, start, end in
                // The night's window is the bed window exactly; the day's is not.
                id == "HKQuantityTypeIdentifierHeartRateVariabilitySDNN" && start == bed && end == wake ? 71.26 : nil
            }
        )
        let sync = HealthSync(database: db, reader: reader, userId: user)
        let report = try await sync.sync(day: night, isToday: false)
        #expect(report.hrvOvernight)
        let row = try #require(try await db.writer.read { conn in
            try DailyLogRow.filter(Column("date") == night).fetchOne(conn)
        })
        #expect(row.hrvMs == 71.26, "the night's mean, not the day's 58.3")

        // No night → the day's mean stands, unflagged.
        let dayOnly = ScriptedHealth(quantities: ["HKQuantityTypeIdentifierHeartRateVariabilitySDNN": 58.3])
        let fallback = try await HealthSync(database: try store(), reader: dayOnly, userId: user).sync(day: night, isToday: false)
        #expect(!fallback.hrvOvernight)
    }

    @Test("a store with no Health data writes nothing")
    func unavailableStoreIsSilent() async throws {
        let db = try store()
        let sync = HealthSync(
            database: db, reader: ScriptedHealth(isAvailable: false), userId: user
        )
        let report = try await sync.sync(day: day, isToday: true)
        #expect(report.isEmpty)
    }
}
