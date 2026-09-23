import Foundation
import GRDB
import OnyxCore

/// What one ingest wrote.
public struct IngestReport: Sendable, Equatable {
    /// Tables that gained or changed a row.
    public var tables: Set<String> = []
    /// Metrics the source sent that were deliberately NOT stored, and why. A
    /// declined metric is reported rather than dropped in silence — a manual
    /// correction that quietly stops being honoured is invisible otherwise.
    public var declined: [String] = []
    /// The stored `hrv_ms` is the night's mean (the watch was worn to sleep)
    /// rather than the calendar day's. Stored in `daily_logs.hrv_overnight`
    /// since v33 — see `hrvHistory`, whose band depends on it — and reported
    /// here as well so a caller can see what one pass decided.
    public var hrvOvernight: Bool = false

    public var isEmpty: Bool { tables.isEmpty }
}

/// HealthKit → the local store → the outbox.
///
/// ── WHAT THIS REPLACES ──────────────────────────────────────────────────────
/// `POST /api/ingest` (59 loc) and `ingestDailyLog` (468). The route is gone
/// entirely — there is no hop to make — and roughly half of `ingestDailyLog`
/// went with it: the per-field HTTP error contract, the `strippedV51` retry that
/// dropped newly-added columns when a database had not been migrated, and the
/// three-tier `DL_COLUMN_SETS` fallback. All of that existed because a server
/// was writing into a schema it could not see. This writes into a schema that is
/// generated from that database and checked by `npm run check:mirror`.
///
/// What survives is every RULE, because every one of them was bought:
/// the 50 kg weight floor, the adaptive stand-hours conversion, the two mapped
/// keys, the manual-override sentinels for macros and water, the vitamin-D unit
/// fix, and the night window.
///
/// ── ONE TRANSACTION, THEN THE QUEUE ─────────────────────────────────────────
/// Every row and every outbox item lands in a single write. A row written
/// outside the transaction that queues it is a row that exists on the phone and
/// will never reach the server if the process dies in between, which is the one
/// failure the outbox exists to make impossible.
public extension AppDatabase {

    @discardableResult
    func ingest(_ payload: HealthPayload, userId: String, now: Date = Date()) throws -> IngestReport {
        var report = IngestReport()
        guard !payload.isEmpty else { return report }
        let date = payload.date

        // Global weight-validity rule: a sub-50 kg reading is a scale or sync
        // artifact, not a person. Reported, never stored.
        var weight = payload[.weight]
        if let w = weight, w < HealthUnits.minValidWeightKg {
            report.declined.append("weight \(w)kg — below the \(Int(HealthUnits.minValidWeightKg))kg validity minimum")
            weight = nil
        }

        try writer.write { db in
            // ── ARTIFACT GATES, ONE PER VITAL ───────────────────────────────
            // Same shape as the weight floor: declined and reported, never
            // stored. HRV is judged against the athlete's own band —
            // `Readiness.constants.baselineDays` of prior nights, median and MAD — so a
            // strap that slipped cannot move the z-score for six weeks.
            var payload = payload
            /* ── THE BAND IS BUILT FROM THE SAME KIND OF NIGHT ───────────
               `daily_logs.hrv_ms` holds TWO different measurements. When the
               night's bed window resolves, `HealthSync` writes the mean of the
               SDNN samples inside it; when it does not, the calendar day's mean
               stands. Overnight SDNN runs far above the waking figure — on this
               athlete around 100 ms against 60 — so judging an overnight
               reading against a median of daytime ones made the good night the
               outlier. Three Friday mornings running read 102, 93.9 and 119.8
               and were declined, and the readings were never wrong.

               `hrv_overnight` is what tells the two apart. It has existed in
               Postgres since readiness v9 and was missing from
               `native/schema/supabase.json`, so nothing on this device could
               read or write it — the fact was computed every sync and thrown
               away. It is stored now, and the history is filtered to match. */
            if let hrv = payload[.hrv], let why = VitalsGate.hrvArtifact(
                hrv, history: try Self.hrvHistory(
                    db, userId: userId, before: date, overnight: payload.hrvOvernight)) {
                report.declined.append("hrv \(hrv)ms — \(why)")
                payload[.hrv] = nil
            }
            if let bf = payload[.bodyFat], let why = VitalsGate.bodyFatArtifact(bf) {
                report.declined.append("body fat \(bf)% — \(why)")
                payload[.bodyFat] = nil
            }
            report.hrvOvernight = payload.hrvOvernight && payload[.hrv] != nil

            // ── A HAND-CORRECTED DAY WINS ───────────────────────────────────
            // ONE probe, TWO skips: `daily_logs.water_ml` and the `water_intake`
            // fan-out. They are read by different consumers — the UI renders the
            // first, the score sums the second — and suppressing only one lets
            // the litres shown and the litres graded drift apart with nothing on
            // screen able to say so.
            let manualWater = try payload[.water] != nil
                && Self.hasManualWater(db, userId: userId, date: date)
            if manualWater { report.declined.append("water — manual override present") }

            // ── A GLASS IS NOT AN OVERRIDE ──────────────────────────────────
            // Glasses tapped on the Nutrition tab live in the same ledger under
            // their own prefix, and they ADD to whatever Apple reports rather
            // than replacing it — see `ManualEntry.glassSentinel` for the
            // one-way door that made them a replacement, and what that cost.
            // `writeWater` owns the row holding HealthKit's own total, so the
            // two never collide in `water_intake`; the flat row has to carry
            // their SUM, because it is the one figure every surface renders.
            let glassesMl = manualWater ? 0 : try Self.glassTotal(db, userId: userId, date: date)

            try Self.writeDailyLog(
                db, payload: payload, userId: userId, weight: weight,
                manualWater: manualWater, glassesMl: glassesMl, now: now, report: &report
            )
            try Self.writeDailyMetrics(db, payload: payload, userId: userId, now: now, report: &report)
            try Self.writeNutrition(db, payload: payload, userId: userId, now: now, report: &report)
            try Self.writeBodyComposition(
                db, payload: payload, userId: userId, weight: weight, now: now, report: &report
            )
            if !manualWater {
                try Self.writeWater(db, payload: payload, userId: userId, now: now, report: &report)
            }
            try Self.writeSleep(db, payload: payload, userId: userId, now: now, report: &report)
        }
        return report
    }
}

// MARK: - The flat row

// Internal rather than private: `DayEditing` patches the same row by hand and
// must mint the day exactly the way HealthKit does, or the two paths create two
// rows for one date.
extension AppDatabase {

    /// `daily_logs` — one row per day, merged.
    ///
    /// Only keys the source actually sent are touched. That is the same contract
    /// the web had ("preserving AI-completed advanced fields") and it matters
    /// more here: a HealthKit sync must never blank a hand-entered InBody
    /// reading it knows nothing about.
    static func writeDailyLog(
        _ db: Database, payload: HealthPayload, userId: String, weight: Double?,
        manualWater: Bool, glassesMl: Double = 0, now: Date, report: inout IngestReport
    ) throws {
        var row = try existingDailyLog(db, userId: userId, date: payload.date, now: now)
        var touched = false
        // `touched` only when the value MOVED: a re-read that restates the row
        // must not save it, or the rescore door hears an edit on every
        // foreground (W2).
        func set<T: Equatable>(_ path: WritableKeyPath<DailyLogRow, T?>, _ value: T?) {
            guard let value, row[keyPath: path] != value else { return }
            row[keyPath: path] = value
            touched = true
        }
        func setInt(_ path: WritableKeyPath<DailyLogRow, Int?>, _ value: Double?) {
            guard let value, row[keyPath: path] != Int(value.rounded()) else { return }
            row[keyPath: path] = Int(value.rounded())
            touched = true
        }

        setInt(\.steps, payload[.steps])
        set(\.distanceM, payload[.distanceM])
        // Apple's total PLUS the glasses tapped on the tab. Adding them here
        // and not in `writeWater` is deliberate: the ledger keeps the two
        // sources as separate rows (which is what lets either be corrected on
        // its own), and only the flat row — the one every surface renders —
        // holds the sum.
        if !manualWater { set(\.waterMl, payload[.water].map { $0 + glassesMl }) }
        set(\.carbsG, payload[.carbs])
        set(\.proteinG, payload[.protein])
        set(\.fatsG, payload[.fats])
        set(\.weightKg, weight)
        set(\.bmi, payload[.bmi])
        setInt(\.trainingMinutes, payload[.trainingMinutes])
        set(\.activeEnergy, payload[.activeEnergy])
        set(\.bodyFatPct, payload[.bodyFat])
        setInt(\.standingMinutes, payload[.standingMinutes])
        setInt(\.avgHeartRate, payload[.avgHeartRate])
        setInt(\.avgRestHeartRate, payload[.avgRestHeartRate])
        set(\.respiratoryRate, payload[.respiratoryRate])
        set(\.bloodOxygen, payload[.bloodOxygen])
        set(\.hrvMs, payload[.hrv])
        /* WHICH READING IT IS, stored beside it. Written only when there IS an
           HRV: a `false` on a day that measured none would claim a calendar-day
           mean nobody took, and the export reads the absence as "provenance
           unknown" rather than as a claim. */
        if payload[.hrv] != nil {
            row.hrvOvernight = payload.hrvOvernight
            touched = true
        }
        set(\.vo2max, payload[.vo2max])
        // `wrist_temp_delta` stores the raw value the source sends — since
        // 2026-07 that is the night's AVERAGE wrist temperature in °C, not a
        // delta. The column keeps its name; the Vitals UI labels it °C.
        set(\.wristTempDelta, payload[.wristTemp])
        setInt(\.timeInDaylightMin, payload[.timeInDaylight])

        // ── THE TWO MAPPED KEYS ─────────────────────────────────────────────
        // HealthKit's exercise-ring minutes arrive as `training_minutes`, and
        // its `standing_minutes` is Apple's stand-HOURS ring count despite the
        // name (Apple has no standing-minutes metric; typical value 8–14). Both
        // feed the newer columns, and the legacy ones stay dual-written above so
        // nothing that still reads them breaks.
        setInt(\.exerciseMinutes, payload[.trainingMinutes])
        if let hours = HealthUnits.standToHours(payload[.standingMinutes]) {
            row.standHours = hours
            touched = true
        }

        // ── BODY MASSES ARE DELIBERATELY NOT DERIVED HERE ───────────────────
        // The web ran `deriveBodyComp` and stored fat / lean / water / bone
        // masses from the percentages. That function lives in `lib/body/
        // composition.ts` and is Track D's to port (§2.3 item 8); re-deriving it
        // in the sync layer would make two implementations of an arithmetic that
        // has ALREADY split once in this app — `lean_mass_kg` held both muscle
        // mass and fat-free mass for months, ~2.6 kg apart, and the chart picked
        // between them per day.
        //
        // So the masses are left NULL rather than guessed. An explicit fat-free
        // reading is not a derivation and lands as itself; the percentages land
        // raw. When `body/composition` ports, this is three lines.
        set(\.fatFreeMassKg, payload[.fatFreeMass])

        guard touched else { return }
        try row.save(db)
        try Self.enqueueRowUpsert(table: DailyLogRow.databaseTableName, id: row.id, in: db)
        report.tables.insert(DailyLogRow.databaseTableName)
    }

    /// The athlete's prior HRV readings inside the readiness baseline window,
    /// the day itself excluded — the band `VitalsGate.hrvArtifact` judges by.
    ///
    /// ── ONLY THE NIGHTS OF THE SAME KIND ────────────────────────────────────
    /// An overnight mean is judged against overnight means and a calendar-day
    /// mean against calendar-day means, because the two are different
    /// measurements of different things and a band built from one cannot
    /// contain the other.
    ///
    /// A row with NO provenance is one written before `hrv_overnight` reached
    /// this device, and it is admitted to BOTH bands: an unknown reading is
    /// still the athlete's own history, and excluding it would leave the gate
    /// with nothing to judge by until eight new nights had accumulated — which
    /// is a gate that cannot fire, not a gate that is careful.
    ///
    /// ponytail: the mixed band is a transitional cost and it shrinks every
    /// night. Drop the `IS NULL` clause once the history behind this window is
    /// entirely post-v33 — but note what the filter costs an athlete whose bed
    /// window resolves unevenly: the rarer KIND may never reach
    /// `hrvMinHistory` inside the 42-day window, and `hrvArtifact` then returns
    /// nil and only the flat 5–300 ms physiologic bound applies. That is a gate
    /// that declines to judge rather than one that judges wrongly, which is the
    /// right way round — but it is a gate that is not working, and if it
    /// persists the answer is to make the bed window resolve, not to widen the
    /// band back.
    ///
    /// ponytail: THE SCORE STILL MIXES. `ScoringWindow.hrvBaseline` and
    /// `ReadinessHistoryBuilder` average `hrv_ms` over their trailing window
    /// with no regard for provenance, exactly as this function did before v33,
    /// so `inputs.hrvZ` — and through it the battery's `hrvQ` and the stress
    /// term — still compare an overnight reading against a band that may be
    /// half daytime. Filtering them is the same one-line change and a
    /// completely different blast radius: it moves every stored daily score and
    /// needs a history rescore and new golden vectors. Its own wave.
    static func hrvHistory(
        _ db: Database, userId: String, before date: String, overnight: Bool
    ) throws -> [Double] {
        let from = ISODate.addDays(date, -Readiness.constants.baselineDays) ?? date
        return try Double.fetchAll(
            db, sql: """
                SELECT hrv_ms FROM daily_logs
                WHERE user_id = ? AND date >= ? AND date < ? AND hrv_ms IS NOT NULL
                  AND (hrv_overnight IS NULL OR hrv_overnight = ?)
                """,
            arguments: [userId, from, date, overnight]
        )
    }

    /// The day's row, or a fresh one.
    ///
    /// Reusing the existing id — whether this device minted it or the mirror
    /// pulled it from the server — is what keeps `id` stable across devices. A
    /// new uuid per sync would be a second row for a day the server already
    /// holds, and `daily_logs_user_id_date_key` would reject it forever.
    static func existingDailyLog(
        _ db: Database, userId: String, date: String, now: Date
    ) throws -> DailyLogRow {
        if let row = try DailyLogRow
            .filter(Column("user_id") == userId && Column("date") == date)
            .fetchOne(db) { return row }
        // `updated_at` is the delta cursor and only the server may set it —
        // see `AppDatabase.localWriteTimestamp`.
        return DailyLogRow(
            id: newOnyxID(), userId: userId, date: date,
            createdAt: now, updatedAt: Self.localWriteTimestamp,
            nutritionEstimated: false, sleepOnsetTrouble: false
        )
    }
}

// MARK: - Fan-out

private extension AppDatabase {

    /// `daily_metrics` — the three numbers scoring reads for activity.
    static func writeDailyMetrics(
        _ db: Database, payload: HealthPayload, userId: String, now: Date, report: inout IngestReport
    ) throws {
        // Resting HR falls back to the day's average, exactly as the web did:
        // a device that reports one and not the other should still move the
        // recovery component.
        let restHr = payload[.avgRestHeartRate] ?? payload[.avgHeartRate]
        guard payload[.steps] != nil || payload[.activeEnergy] != nil || restHr != nil else { return }

        let existing = try DailyMetricRow
            .filter(Column("user_id") == userId && Column("date") == payload.date)
            .fetchOne(db)
        var row = existing ?? DailyMetricRow(
            id: newOnyxID(), userId: userId, date: payload.date,
            createdAt: now, updatedAt: Self.localWriteTimestamp
        )
        if let steps = payload[.steps] { row.steps = Int(steps.rounded()) }
        if let cal = payload[.activeEnergy] { row.activeCal = Int(cal.rounded()) }
        if let hr = restHr { row.restHr = Int(hr.rounded()) }
        // ── NOTHING CHANGED, NOTHING WRITTEN (W2) ───────────────────────────
        // Every foreground re-reads yesterday, and a byte-identical `save`
        // still fires the rescore door's trigger — a cascade and a generation
        // bump on every launch for a day that did not move.
        if let existing, existing == row { return }
        try row.save(db)
        try Self.enqueueRowUpsert(table: DailyMetricRow.databaseTableName, id: row.id, in: db)
        report.tables.insert(DailyMetricRow.databaseTableName)
    }

    /// `nutrition_entries` — the day's summary row.
    ///
    /// ── CALORIES ARE NEVER DERIVED ──────────────────────────────────────────
    /// The source's own dietary-energy total is stored (HealthKit's, which is
    /// MyFitnessPal's Atwater+fibre value). Synthesising 4·C + 4·P + 9·F would
    /// produce a number that silently drifts from the app the food was logged
    /// in — and `calories` is NOT NULL, so a macro-only reading correctly leaves
    /// its macros in `daily_logs` and writes no summary row at all.
    static func writeNutrition(
        _ db: Database, payload: HealthPayload, userId: String, now: Date, report: inout IngestReport
    ) throws {
        guard let calories = payload[.calories] else { return }

        let existing = try NutritionEntryRow
            .filter(
                Column("user_id") == userId && Column("date") == payload.date
                    && Column("meal_type") == "daily"
            )
            .fetchOne(db)
        // A hand-entered day wins. Never let a HealthKit re-sync overwrite a
        // manual macro correction.
        if ManualEntry.isManualMacro(existing?.hkUuid) {
            report.declined.append("macros — manual override present")
            return
        }

        // A DECLARED day keeps the block's phase rather than being re-banded by
        // its calorie total. The declaration lives on `daily_logs` and the
        // active phase on `user_goals`; either being absent falls back to the
        // calorie-derived value.
        let flags = try DailyLogRow
            .filter(Column("user_id") == userId && Column("date") == payload.date)
            .fetchOne(db)
        let goals = try UserGoalRow.filter(Column("user_id") == userId).fetchOne(db)
        let phase = NutritionPhase.resolve(.init(
            calories: calories,
            exception: flags?.nutritionException,
            estimated: flags?.nutritionEstimated,
            activePhase: goals?.goalPreset.flatMap(NutritionPhase.init(rawValue:))
        ))

        var row = existing ?? NutritionEntryRow(
            id: newOnyxID(), userId: userId,
            loggedAt: NightWindow.midnight(payload.date) ?? now,
            date: payload.date, mealType: "daily",
            calories: 0, proteinG: 0, carbsG: 0, fatG: 0, createdAt: now
        )
        row.calories = calories
        row.proteinG = payload[.protein] ?? 0
        row.carbsG = payload[.carbs] ?? 0
        row.fatG = payload[.fats] ?? 0
        row.fiberG = payload[.fiber]
        row.phase = phase?.rawValue
        if let micros = Self.microsBundle(payload) { row.micros = micros }
        try row.save(db)
        try Self.enqueueRowUpsert(table: NutritionEntryRow.databaseTableName, id: row.id, in: db)
        report.tables.insert(NutritionEntryRow.databaseTableName)
    }

    /// The dietary micros, as the `jsonb` bundle the nutrients grid reads.
    /// Fibre keeps its own column and is not in here.
    static func microsBundle(_ payload: HealthPayload) -> JSONText? {
        let keys: [HealthKey] = [
            .sugar, .sodium, .potassium, .calcium, .iron, .magnesium, .vitaminC, .vitaminD, .satFat,
            .zinc, .iodine, .vitaminA, .vitaminB6, .vitaminB12, .vitaminE, .vitaminK, .biotin, .cholesterol,
        ]
        var micros: [String: Double] = [:]
        for key in keys {
            guard let v = payload[key] else { continue }
            micros[key.rawValue] = key == .vitaminD ? HealthUnits.vitaminDToIU(v) : v
            /* ── WHO WROTE IT, ALONGSIDE WHAT IT SAID ────────────────────────
               `calcium@MyFitnessPal` beside `calcium`, in the SAME bundle.

               A separate column would need DDL nobody can run from this
               machine, and a separate table would need a migration; this
               column is a free-form `jsonb` and every reader of it looks up
               nutrients by EXACT key (`NUTRIENT_TARGETS`), so a key carrying an
               `@` is invisible to all of them. The weekly export is the one
               reader that goes looking, and only for a figure it already
               doubts.

               Written for every micro rather than only the implausible ones:
               the ingest does not hold the targets, and the breakdown rides
               along in the statistics query either way. */
            for (source, amount) in payload.microSources[key] ?? [:] {
                guard amount > 0 else { continue }
                micros["\(key.rawValue)@\(source)"] =
                    key == .vitaminD ? HealthUnits.vitaminDToIU(amount) : amount
            }
        }
        guard !micros.isEmpty else { return nil }
        // Sorted keys so the same reading produces the same bytes and an
        // unchanged day does not look like a change to the row comparison.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(micros) else { return nil }
        return JSONText(raw: String(decoding: data, as: UTF8.self))
    }

    /// `body_composition` — only ever with a VALID weight.
    static func writeBodyComposition(
        _ db: Database, payload: HealthPayload, userId: String, weight: Double?,
        now: Date, report: inout IngestReport
    ) throws {
        let hasSomething = weight != nil || payload[.fatFreeMass] != nil || payload[.bodyFat] != nil
        guard hasSomething else { return }
        guard let weight else {
            report.declined.append("body composition — no valid weight (row requires ≥ 50 kg)")
            return
        }

        // The web DELETED the day's rows and re-inserted. Reusing the day's row
        // instead is the same outcome with none of the race: the delete could
        // land after a concurrent insert and destroy the reading it had just
        // written. `id` is stable, so the upsert is idempotent by construction.
        //
        // ── AND IT IS THE LATEST ROW, BECAUSE EVERYONE ELSE READS THAT ONE ──
        // This was an UNORDERED `fetchOne`, which on a day with one row is the
        // same row and on a day with several is whichever one SQLite reached
        // first. `bodyCompositionStream`, `saveBodyMetrics` and `VitalsStore`
        // all take the newest `measured_at`. So on a day that ended up with two
        // rows — a web-era row pulled back beside a local one — this could
        // stamp the weight onto the row NOBODY reads, while the row everyone
        // reads kept whatever it had. The InBody columns a person had just
        // typed would appear to vanish, and the weigh-in banner watching them
        // would come straight back. One writer picking a different row than
        // every reader is not a tie-break, it is two stores.
        var row = try BodyCompositionRow
            .filter(Column("user_id") == userId && Column("date") == payload.date)
            .order(Column("measured_at").desc)
            .fetchOne(db)
            ?? BodyCompositionRow(
                id: newOnyxID(), userId: userId,
                measuredAt: NightWindow.midnight(payload.date) ?? now,
                date: payload.date, weightKg: weight, createdAt: now
            )
        row.weightKg = weight
        row.bodyFatPct = payload[.bodyFat]
        row.bmi = payload[.bmi]
        // `muscle_mass_kg` carries MUSCLE mass only and HealthKit has no such
        // type — it is left alone here rather than handed LeanBodyMass, which
        // is what put two different quantities in one column for months.
        row.fatFreeMassKg = payload[.fatFreeMass]
        try row.save(db)
        try Self.enqueueRowUpsert(table: BodyCompositionRow.databaseTableName, id: row.id, in: db)
        report.tables.insert(BodyCompositionRow.databaseTableName)
    }

    /// `water_intake` — the score's hydration source.
    static func writeWater(
        _ db: Database, payload: HealthPayload, userId: String, now: Date, report: inout IngestReport
    ) throws {
        guard let ml = payload[.water] else { return }
        // Scoped to rows with no `hk_uuid`, which is what a synced row always
        // has. The manual guard upstream already means we cannot reach a manual
        // row — but a write that CAN reach it is one race away from destroying
        // the correction it exists to protect, and the filter costs nothing.
        let existingWater = try WaterIntakeRow
            .filter(
                Column("user_id") == userId && Column("date") == payload.date
                    && Column("hk_uuid") == nil
            )
            .fetchOne(db)
        var row = existingWater ?? WaterIntakeRow(
            id: newOnyxID(), userId: userId,
            loggedAt: NightWindow.midnight(payload.date) ?? now,
            date: payload.date, amountMl: ml, createdAt: now
        )
        row.amountMl = ml
        // Unchanged is unwritten (W2): see `writeDailyMetrics`.
        if let existingWater, existingWater == row { return }
        try row.save(db)
        try Self.enqueueRowUpsert(table: WaterIntakeRow.databaseTableName, id: row.id, in: db)
        report.tables.insert(WaterIntakeRow.databaseTableName)
    }

    /// `sleep_sessions` — one row per night, in the night's own window.
    static func writeSleep(
        _ db: Database, payload: HealthPayload, userId: String, now: Date, report: inout IngestReport
    ) throws {
        guard let sleep = payload.sleep, sleep.sleepMinutes > 0,
              let window = NightWindow.range(payload.date) else { return }

        // The night is found by its WINDOW, not by a date column — the table has
        // no date column, and `start_time` is the previous evening. Any row
        // already in this half-open range is this same night from an earlier
        // sync, whoever wrote it.
        let inWindow = try SleepSessionRow
            .filter(
                Column("user_id") == userId
                    && Column("start_time") >= window.from && Column("start_time") < window.to
            )
            .order(Column("duration_min").desc)
            .fetchAll(db)
        // ── A HAND-EDITED NIGHT WINS ────────────────────────────────────────
        // The same rule as water: a window the user trimmed must not be
        // re-widened by the next sync, silently and forever. Declined and
        // REPORTED, so a correction that stops being honoured is visible.
        if inWindow.contains(where: { ManualEntry.isManualSleep($0.hkUuid) }) {
            report.declined.append("sleep — manual window present")
            return
        }
        let existingNight = inWindow.first
        var row = existingNight
            ?? SleepSessionRow(
                id: newOnyxID(), userId: userId,
                startTime: sleep.bedStart ?? NightWindow.fallbackBedTime(payload.date) ?? window.from,
                endTime: sleep.bedEnd ?? window.to,
                durationMin: sleep.sleepMinutes, createdAt: now
            )
        // No reported bedtime → stamp INSIDE the window, never past its end. The
        // old fallback was an hour beyond it, so the row was written and then
        // invisible to every reader.
        let start = sleep.bedStart ?? NightWindow.fallbackBedTime(payload.date) ?? window.from
        row.startTime = start
        row.endTime = sleep.bedEnd ?? start
        row.durationMin = sleep.sleepMinutes
        row.deepMin = sleep.deepMin
        row.remMin = sleep.remMin
        row.coreMin = sleep.storedCoreMin
        row.awakeMin = sleep.awakeMin
        row.onsetTime = sleep.onset
        row.awakenings = sleep.awakenings
        // Unchanged is unwritten (W2): yesterday's night is re-read on every
        // foreground, and a byte-identical save would cascade each launch.
        if let existingNight, existingNight == row { return }
        try row.save(db)
        try Self.enqueueRowUpsert(table: SleepSessionRow.databaseTableName, id: row.id, in: db)
        report.tables.insert(SleepSessionRow.databaseTableName)
    }

    /// Has this day's hydration been corrected by hand?
    static func hasManualWater(_ db: Database, userId: String, date: String) throws -> Bool {
        try WaterIntakeRow
            .filter(Column("user_id") == userId && Column("date") == date)
            .fetchAll(db)
            .contains { ManualEntry.isManualWater($0.hkUuid) }
    }

    /// What the glasses tapped on the tab add up to on this day.
    static func glassTotal(_ db: Database, userId: String, date: String) throws -> Double {
        try WaterIntakeRow
            .filter(Column("user_id") == userId && Column("date") == date)
            .fetchAll(db)
            .filter { ManualEntry.isGlass($0.hkUuid) }
            .reduce(0) { $0 + $1.amountMl }
    }
}
