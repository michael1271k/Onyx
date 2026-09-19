import Foundation
import GRDB
import OnyxCore

/// The Day and Fuel screens' read and write path — one logical day, eleven
/// tables.
///
/// ── THE SAME RULE AS `GoalsEditing`, TWELVE TIMES ───────────────────────────
/// Every writer here reads the row, changes it, saves it and queues it inside
/// ONE transaction. A row that is written locally and not queued never leaves
/// the phone; a row that is queued and not written is a queue item for nothing.
/// The outbox exists to make both impossible, and it can only do that if no
/// screen ever holds a transaction of its own — which is why `AppDatabase.writer`
/// stays internal and this file is the API a screen gets.
///
/// ── WHAT THE WEB APP DID THAT THIS DOES NOT ─────────────────────────────────
/// Each of these tables had its own react-query hook, its own optimistic
/// update, its own invalidation list, and — for `daily_logs` — a split into
/// "core" and "extended" columns with a retry that swallowed `PGRST204` because
/// the column might not have been migrated yet. None of that is ported. Every
/// column is live (see memory: `aug31-pending-sql`), the local store is
/// reactive, and a failed write is reported to the caller as an error rather
/// than to a cache as a rollback.
///
/// ── DELETES AND CLEARS ──────────────────────────────────────────────────────
/// This is the first wave that DELETES a mirrored row (a skipped dose undone, a
/// water override handed back to HealthKit, a day target dropped, a swap
/// undone) and the first that CLEARS a column (an exception day un-marked). Both
/// go through `enqueueRowDelete` and `RowRef.nulls` in `RowPush`; a delete
/// written here without its queue item would be a row that comes back on the
/// next pull.
public extension AppDatabase {

    // MARK: - daily_logs

    /// The day's flat row — flags, scale readings, water, sleep minutes. `nil`
    /// until something writes the day.
    func dailyLogStream(userId: String, date: String) -> AsyncThrowingStream<DailyLogRow?, any Error> {
        stream(ValueObservation.tracking { db in
            try DailyLogRow.filter(Column("user_id") == userId && Column("date") == date).fetchOne(db)
        })
    }

    /// Patch the day's row, creating it if absent, and queue it.
    ///
    /// `clearing` names the columns the patch sets to `nil`, so the clear reaches
    /// the server (see `RowRef.nulls`). Forgetting it is not a crash but a silent
    /// disagreement: the phone says "no exception today", the server keeps "Event".
    @discardableResult
    func editDailyLog(
        userId: String, date: String, now: Date = Date(), clearing: [String] = [],
        _ change: @Sendable (inout DailyLogRow) -> Void
    ) throws -> DailyLogRow {
        try writer.write { db in
            try Self.patchDailyLog(db, userId: userId, date: date, now: now, clearing: clearing, change)
        }
    }

    static func patchDailyLog(
        _ db: Database, userId: String, date: String, now: Date, clearing: [String],
        _ change: (inout DailyLogRow) -> Void
    ) throws -> DailyLogRow {
        // The same minting HealthKit uses, so a hand-entered flag and a synced
        // step count land on ONE row for the day rather than racing to create it.
        var row = try existingDailyLog(db, userId: userId, date: date, now: now)
        change(&row)
        try row.save(db)
        try enqueueRowUpsert(table: DailyLogRow.databaseTableName, id: row.id, nulls: clearing, in: db)
        return row
    }

    // MARK: - Scale readings → body_composition

    /// Save the scale's numbers for a day.
    ///
    /// `daily_logs` first — it is the row every surface reads — then the
    /// `body_composition` ledger the charts and the Pathfinder deltas read,
    /// mirrored column for column the way the web's `BODY_MIRROR` does. The
    /// ledger row is created only once a weight exists: `body_composition.weight_kg`
    /// is `NOT NULL` server-side, so a weightless day genuinely cannot open one
    /// and stays in `daily_logs` until a weight lands.
    ///
    /// ONE tape measurement. This said "there is no waist or hip column here and
    /// there will not be one" until 2026-09-17 (W3); `daily_logs.waist_cm` now
    /// exists. No HIP column, though, so the W:H ratio is still one float the
    /// scale reports and is never recomputed from the waist.
    ///
    /// The waist rides the day row only. The `body_composition` ledger below is
    /// the HealthKit twin and HealthKit has no waist type, so mirroring it there
    /// would invent a column the other writer could never fill.
    func saveBodyMetrics(
        userId: String, date: String, now: Date = Date(),
        _ change: @Sendable (inout DailyLogRow) -> Void
    ) throws {
        try writer.write { db in
            // The store is the trust boundary, not the form: a percentage no
            // body has is refused before either row is touched, so the reading
            // the athlete DID take stays exactly as it was.
            var probe = try Self.existingDailyLog(db, userId: userId, date: date, now: now)
            change(&probe)
            if let v = probe.bodyFatPct, let why = VitalsGate.bodyFatArtifact(v) { throw BodyMetricError.outOfRange("body fat", v, why) }
            if let v = probe.musclePercent, let why = VitalsGate.musclePercentArtifact(v) { throw BodyMetricError.outOfRange("muscle", v, why) }
            if let v = probe.visceralFat, let why = VitalsGate.visceralFatArtifact(v) { throw BodyMetricError.outOfRange("visceral fat", v, why) }

            let day = try Self.patchDailyLog(db, userId: userId, date: date, now: now, clearing: [], change)

            let scope = BodyCompositionRow.filter(Column("user_id") == userId && Column("date") == date)
            var ledger: BodyCompositionRow
            if let existing = try scope.order(Column("measured_at").desc).fetchOne(db) {
                ledger = existing
            } else {
                guard let weight = day.weightKg else { return }
                ledger = BodyCompositionRow(
                    id: newOnyxID(), userId: userId,
                    // 07:00Z — a morning weigh-in, and the same stamp the web
                    // writes so the two never create a second row for one day.
                    measuredAt: Self.utcInstant(date, hour: 7) ?? now,
                    date: date, weightKg: weight, createdAt: now
                )
            }
            // Only what the day HAS: a mirror must not blank a ledger column the
            // scale did not report this morning.
            if let v = day.weightKg { ledger.weightKg = v }
            if let v = day.bodyFatPct { ledger.bodyFatPct = v }
            if let v = day.muscleMassKg { ledger.muscleMassKg = v }
            if let v = day.fatFreeMassKg { ledger.fatFreeMassKg = v }
            if let v = day.fatMassKg { ledger.fatMassKg = v }
            if let v = day.waterPercent { ledger.waterPct = v }
            if let v = day.musclePercent { ledger.musclePct = v }
            if let v = day.boneMineral { ledger.boneMineralPct = v }
            if let v = day.visceralFat { ledger.visceralFat = v }
            if let v = day.bmr { ledger.bmr = v }
            if let v = day.bmi { ledger.bmi = v }
            if let v = day.skeletalMuscleMassKg { ledger.skeletalMuscleMassKg = v }
            if let v = day.estimatedWaistToHipRatio { ledger.estimatedWaistToHipRatio = v }
            try ledger.save(db)
            try Self.enqueueRowUpsert(table: BodyCompositionRow.databaseTableName, id: ledger.id, in: db)
        }
    }

    /// The day's ledger row, if the scale has reported one.
    func bodyCompositionStream(userId: String, date: String) -> AsyncThrowingStream<BodyCompositionRow?, any Error> {
        stream(ValueObservation.tracking { db in
            try BodyCompositionRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .order(Column("measured_at").desc)
                .fetchOne(db)
        })
    }

    /// The most recent day BEFORE `date` with any scale reading.
    ///
    /// The InBody form shows it as placeholders — muscle %, water %, protein %
    /// and bone mineral have no HealthKit type and are only ever typed, and a
    /// blank field with nothing saying what it was last time is how 78.3 gets
    /// recalled from memory wrong. It is context, not a measurement: the form
    /// fills the edit buffer from it and writes nothing until Save.
    func latestBodyReading(userId: String, before date: String) throws -> DailyLogRow? {
        try writer.read { db in
            try DailyLogRow
                .filter(Column("user_id") == userId && Column("date") < date)
                .filter(sql: """
                    weight_kg IS NOT NULL OR body_fat_pct IS NOT NULL OR muscle_percent IS NOT NULL
                    OR water_percent IS NOT NULL OR protein_percent IS NOT NULL OR bone_mineral IS NOT NULL
                    OR visceral_fat IS NOT NULL OR bmr IS NOT NULL OR bmi IS NOT NULL
                    OR skeletal_muscle_mass_kg IS NOT NULL OR estimated_waist_to_hip_ratio IS NOT NULL
                    OR waist_cm IS NOT NULL
                    """)
                .order(Column("date").desc)
                .fetchOne(db)
        }
    }

    // MARK: - fatigue_logs

    /// Every reading logged on the day, legacy keys included — the caller folds
    /// them with `Fatigue.foldRows`, which knows what `noon` meant on a leg day.
    func fatigueStream(userId: String, date: String) -> AsyncThrowingStream<[FatigueLogRow], any Error> {
        stream(ValueObservation.tracking { db in
            try FatigueLogRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .order(Column("created_at"))
                .fetchAll(db)
        })
    }

    /// Set one slot's level, or clear it with `nil`.
    ///
    /// `superseding` lists the LEGACY keys this slot stands in for (`noon` on a
    /// training day is `pre`). They are deleted whatever the new value: a fold
    /// that reads both would keep showing the old key's reading after the user
    /// changed it under the new one.
    func setFatigue(
        userId: String, date: String, slot: String, level: Int?,
        superseding legacyKeys: [String] = [], now: Date = Date()
    ) throws {
        try writer.write { db in
            let scope = FatigueLogRow.filter(Column("user_id") == userId && Column("date") == date)
            var doomed: [FatigueLogRow] = []
            if !legacyKeys.isEmpty {
                doomed += try scope.filter(legacyKeys.contains(Column("slot"))).fetchAll(db)
            }
            let existing = try scope.filter(Column("slot") == slot).order(Column("created_at")).fetchAll(db)

            if let level {
                var row = existing.first
                    ?? FatigueLogRow(id: newOnyxID(), userId: userId, date: date, slot: slot, level: level, createdAt: now)
                row.level = level
                try row.save(db)
                try Self.enqueueRowUpsert(table: FatigueLogRow.databaseTableName, id: row.id, in: db)
                // A second row for the same slot should not exist; if the web
                // left one, it goes rather than shadowing the edit.
                doomed += existing.dropFirst()
            } else {
                doomed += existing
            }
            for row in doomed {
                try row.delete(db)
                try Self.enqueueRowDelete(table: FatigueLogRow.databaseTableName, key: ["id": row.id], in: db)
            }
        }
    }

    // MARK: - stress_logs

    /// The day's psych-stress events. Ordered by the stored slot string,
    /// which is alphabetical rather than chronological — `stressReadings` on
    /// the model is what puts them in the order the day happens
    /// (`PsychStress.sorted`).
    ///
    /// A whole-day read rather than a latest-row one: `StressInputsBuilder`
    /// takes the MEAN of the rows for the index's `self` term (D6) and the
    /// sheet has to show the reader the same set the term is built from.
    func stressStream(userId: String, date: String) -> AsyncThrowingStream<[StressLogRow], any Error> {
        stream(ValueObservation.tracking { db in
            try StressLogRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .order(Column("slot"))
                .fetchAll(db)
        })
    }

    /// Log one stress EVENT. Returns the new row's id.
    ///
    /// `date` is the logical day the caller passes (the Pulse day); `loggedAt`
    /// is when it was felt, and backdating keeps the day and moves the time.
    /// The slot is DERIVED from `loggedAt` in the local calendar
    /// (`StressSlot.forMinutes`), never typed. There is no same-slot replace
    /// or shadow delete any more: two events in one bucket are two answers,
    /// and the index's mean weighs both.
    ///
    /// `tags` is stored as a JSON ARRAY of the raw tag strings. The column is a
    /// Postgres `text[]`, not jsonb — a JSON array is what PostgREST coerces
    /// into one, and an object written there would not coerce at all. The
    /// reader (`PsychStress.tags`) drops anything it does not know, so a tag
    /// added in a later version costs a chip and never a reading.
    @discardableResult
    func logStress(
        userId: String, date: String, loggedAt: Date, level: Int,
        tags: [StressTag] = [], note: String? = nil, now: Date = Date()
    ) throws -> String {
        let trimmed = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let row = StressLogRow(
            id: newOnyxID(), userId: userId, date: date,
            slot: StressSlot.forMinutes(PsychStress.minuteOfDay(loggedAt)).rawValue,
            level: level, tags: Self.tagsJSON(tags), note: trimmed.isEmpty ? nil : trimmed,
            createdAt: now, updatedAt: now, loggedAt: loggedAt
        )
        try writer.write { db in
            try row.insert(db)
            // `note` is the one nullable column here, and a note the user just
            // cleared has to say its own name or the merge upsert leaves the
            // old text standing on the server (`editCustomSupplement`'s note).
            try Self.enqueueRowUpsert(
                table: StressLogRow.databaseTableName, id: row.id,
                nulls: row.note == nil ? ["note"] : [], in: db
            )
        }
        return row.id
    }

    /// Delete one stress event, locally and on the server.
    func deleteStress(userId: String, id: String) throws {
        try writer.write { db in
            guard let row = try StressLogRow
                .filter(Column("id") == id && Column("user_id") == userId)
                .fetchOne(db) else { return }
            try row.delete(db)
            try Self.enqueueRowDelete(table: StressLogRow.databaseTableName, key: ["id": row.id], in: db)
        }
    }

    /// `["work","money"]` — stored order, never `Set` order.
    private static func tagsJSON(_ tags: [StressTag]) -> JSONText {
        let items = StressTag.sorted(tags).map { "\"\($0.rawValue)\"" }
        return JSONText(raw: "[\(items.joined(separator: ","))]")
    }

    /// One `stress_logs` row as a screen reads it.
    static func reading(_ row: StressLogRow) -> StressReading? {
        guard let slot = StressSlot(rawValue: row.slot) else { return nil }
        let raw = (try? JSONDecoder().decode([String].self, from: Data(row.tags.raw.utf8))) ?? []
        return StressReading(
            id: row.id, slot: slot, loggedAt: row.loggedAt,
            level: row.level, tags: PsychStress.tags(raw), note: row.note
        )
    }

    // MARK: - doms_logs

    func domsStream(userId: String, date: String) -> AsyncThrowingStream<[DomsLogRow], any Error> {
        stream(ValueObservation.tracking { db in
            try DomsLogRow.filter(Column("user_id") == userId && Column("date") == date).fetchAll(db)
        })
    }

    /// Rate (or re-rate) a muscle, optionally one side of it and one part of
    /// it. One row per (day, muscle, side, sub-region), so tapping a different
    /// level replaces that rating rather than stacking rows. `0` is a stored
    /// rating — "None" — not an absence, exactly as the web wrote it.
    ///
    /// ── ABSENCE IS THE SPELLING OF "BOTH" (W9) ──────────────────────────────
    /// `side: .both` stores NULL and `subRegion: nil` stores NULL, which is the
    /// meaning every row written before these columns existed already carried.
    /// Three things follow, and all three are the point:
    ///
    ///   · A bilateral whole-muscle rating is byte-identical to a v1 row, on
    ///     the wire (`encodeIfPresent` omits a nil) and in the export document
    ///     (`BodySide.both.mark` is the empty string).
    ///   · A legacy row is found by this lookup without a backfill, because
    ///     GRDB turns `Column("side") == nil` into `side IS NULL`.
    ///   · Re-rating a whole muscle updates that row rather than minting a
    ///     second one beside it.
    ///
    /// The left and the right row coexist because they differ in the key. The
    /// scoring fold takes the MAX within a muscle, so a pair cannot move the
    /// battery that a single whole-muscle row at the same peak would not have
    /// moved — which is why this migration needs no rescore.
    ///
    /// `source` ties the rating to the session that caused it, when the caller
    /// knows one. Left alone when it does not, so a re-rating never erases the
    /// attribution an earlier one carried.
    func setDoms(
        userId: String, date: String, muscleGroup: String, severity: Int,
        side: BodySide = .both, subRegion: String? = nil,
        source: (sessionId: String, dayKey: String?)? = nil, now: Date = Date()
    ) throws {
        let storedSide = side.stored
        let storedSubRegion = DomsLogRow.canonical(subRegion: subRegion)
        try writer.write { db in
            // The match is spelling-tolerant, the WRITE is canonical: a row an
            // earlier build spelled `(nil, nil)` is found and updated in place,
            // and a row this app mints always says `'both'` / `''` — which is
            // what the server's NOT NULL columns require. See `DomsRow.swift`.
            var row = try DomsLogRow
                .filter(Column("user_id") == userId && Column("date") == date
                        && Column("muscle_group") == muscleGroup
                        && DomsLogRow.sideMatch(side)
                        && DomsLogRow.subRegionMatch(storedSubRegion))
                .fetchOne(db)
                ?? DomsLogRow(
                    id: newOnyxID(), userId: userId, date: date, muscleGroup: muscleGroup,
                    severity: severity, createdAt: now, side: storedSide, subRegion: storedSubRegion
                )
            row.severity = severity
            if let source {
                row.sourceSessionId = source.sessionId
                row.sourceDayKey = source.dayKey
            }
            try row.save(db)
            try Self.enqueueRowUpsert(table: DomsLogRow.databaseTableName, id: row.id, in: db)
        }
    }

    // MARK: - supplement_log / custom_supplements

    /// The day's EXCEPTIONS. Absence means taken — the stack is a protocol and
    /// the row states the one thing that departed from it (`taken = false`).
    func supplementLogStream(userId: String, date: String) -> AsyncThrowingStream<[SupplementLogRow], any Error> {
        stream(ValueObservation.tracking { db in
            try SupplementLogRow.filter(Column("user_id") == userId && Column("date") == date).fetchAll(db)
        })
    }

    /// The user's whole stack, in slot-time order. Empty means unseeded, and
    /// the caller falls back to the seed protocol.
    func customSupplementsStream(userId: String) -> AsyncThrowingStream<[CustomSupplementRow], any Error> {
        stream(ValueObservation.tracking { db in
            try CustomSupplementRow.filter(Column("user_id") == userId).order(Column("time")).fetchAll(db)
        })
    }

    // `setSupplementSkipped` moved to `SupplementEditing.swift`, where the
    // log grew its third state (an explicit `taken = true`).


    // MARK: - cardio_logs

    func cardioStream(userId: String, date: String) -> AsyncThrowingStream<[CardioLogRow], any Error> {
        stream(ValueObservation.tracking { db in
            try CardioLogRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .order(Column("created_at"))
                .fetchAll(db)
        })
    }

    /// One date's bouts, oldest first — the same order and filter the stream
    /// gives, without an observation behind it.
    ///
    /// The automatic ingest needs the day's rows ONCE, inside an actor, to
    /// decide what is already there; subscribing to a stream for a question
    /// asked once per launch would leave an observation open for the life of
    /// the sync.
    func cardioRows(userId: String, date: String) throws -> [CardioLogRow] {
        try writer.read { db in
            try CardioLogRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .order(Column("created_at"))
                .fetchAll(db)
        }
    }

    /// This user's most recent bout, by date then insertion, or nil when they
    /// have never logged one.
    ///
    /// Date-ordered and not `created_at`-ordered: an import backfills a bout
    /// that happened days ago with a `created_at` of NOW, and "the last cardio
    /// I did" is a question about when it was DONE. `created_at` breaks the tie
    /// inside a day, which is the same order `cardioRows` hands a day back in.
    ///
    /// The one reader is the logger's opener (`WarmupCardio.seed(from:)`).
    func lastCardioBout(userId: String) throws -> CardioLogRow? {
        try writer.read { db in
            try CardioLogRow
                .filter(Column("user_id") == userId)
                .order(Column("date").desc, Column("created_at").desc)
                .fetchOne(db)
        }
    }

    /// Log a cardio bout. `kcal` is written alongside `active_kcal` on purpose:
    /// historical readers and the weekly export's pre-migration fallback still
    /// read the old column for the active figure.
    func addCardio(_ row: CardioLogRow) throws {
        try writer.write { db in
            var row = row
            if row.kcal == nil { row.kcal = row.activeKcal }
            try row.save(db)
            try Self.enqueueRowUpsert(table: CardioLogRow.databaseTableName, id: row.id, in: db)
        }
    }

    /// Date-free: the id is enough, and a deletion can move a record, so every
    /// cardio reader re-derives rather than patching a cache.
    func deleteCardio(id: String, userId: String) throws {
        try writer.write { db in
            // Only a row that is this user's goes, locally and on the wire (W11).
            guard try CardioLogRow.filter(Column("id") == id && Column("user_id") == userId).deleteAll(db) > 0
            else { return }
            try Self.enqueueRowDelete(table: CardioLogRow.databaseTableName, key: ["id": id], in: db)
        }
    }

    // MARK: - sleep

    /// The night that ENDED on the morning of `date` — the `[prev 12:00Z, D
    /// 12:00Z)` window every reader and writer shares. The longest session in
    /// the window when there are several; a nap is not the night.
    func sleepNightStream(userId: String, date: String) -> AsyncThrowingStream<SleepSessionRow?, any Error> {
        guard let window = NightWindow.range(date) else {
            return AsyncThrowingStream { continuation in
                continuation.yield(nil)
                continuation.finish()
            }
        }
        return stream(ValueObservation.tracking { db in
            try SleepSessionRow
                .filter(Column("user_id") == userId
                        && Column("start_time") >= window.from
                        && Column("start_time") < window.to)
                .order(Column("duration_min").desc)
                .fetchOne(db)
        })
    }

    /// The stored window of a night the user has edited, or nil. `HealthSync`
    /// reads overnight HRV over it instead of HealthKit's bed window.
    func manualNightWindow(userId: String, date: String) throws -> (start: Date, end: Date)? {
        guard let window = NightWindow.range(date) else { return nil }
        return try writer.read { db in
            try SleepSessionRow
                .filter(Column("user_id") == userId
                        && Column("start_time") >= window.from
                        && Column("start_time") < window.to)
                .fetchAll(db)
                .first { ManualEntry.isManualSleep($0.hkUuid) }
                .map { ($0.startTime, $0.endTime) }
        }
    }

    /// Re-window the night that ended on the morning of `date` (E2).
    ///
    /// ── WRITTEN BY `id`, UNDER THE SENTINEL ─────────────────────────────────
    /// The row is found by its WINDOW (longest wins, the scorer's rule) and
    /// then saved by primary key — the trim CHANGES `start_time`, so a natural-
    /// key upsert would insert a second night beside the first. The outbox
    /// already pushes `sleep_sessions` on `id`. `hk_uuid` becomes
    /// `manual-sleep-<date>`, which is what makes `writeSleep` decline the
    /// night from then on and `HealthSync` read HRV over this window.
    ///
    /// `night` is strategy A's answer (the samples inside the new window,
    /// re-aggregated) when the caller has one; nil is strategy B — `SleepTrim`
    /// over the stored minutes. A night nobody has written yet under B is all
    /// core: no samples, no stage claim. `hrvMs` lands on `daily_logs.hrv_ms`
    /// when the caller read one; nil leaves the stored figure alone.
    ///
    /// `onset` is the third wheel (W3). Given, it wins under both strategies
    /// and must sit in `[start, end)` — the store is the trust boundary, and
    /// an onset before the bedtime is a negative latency the scorer would
    /// clamp into full credit. Absent, strategy A takes the re-aggregated
    /// onset and strategy B keeps the stored one only while the new window
    /// still contains it.
    ///
    /// Does NOT rescore by name. The commit is the request — see `RescoreDoor`.
    @discardableResult
    func editSleepWindow(
        userId: String, date: String, start: Date, end: Date,
        night: SleepNight? = nil, hrvMs: Double? = nil, onset: Date? = nil, now: Date = Date()
    ) throws -> SleepSessionRow {
        guard end > start else { throw SleepEditError.emptyWindow }
        if let onset, onset < start || onset >= end { throw SleepEditError.onsetOutsideWindow(date) }
        guard let window = NightWindow.range(date) else { throw SleepEditError.badDate(date) }
        // The store is the trust boundary, not the picker: a bedtime outside
        // the night's own window would be written under THIS night's sentinel
        // and found by NOBODY reading this night — and by the next night's
        // reader, whose real HealthKit row it would then block forever.
        guard start >= window.from, start < window.to else { throw SleepEditError.outsideNight(date) }
        // ── AND THE OTHER END, WHICH NOTHING BOUNDED ────────────────────────
        // Only the bedtime was checked, so `end` was free: the wake wheel
        // reaches `window.to + 6h` on purpose (a night that ran to one in the
        // afternoon is real), and a bedtime at the window's own opening noon
        // made a THIRTY-hour "night" the store accepted and wrote as
        // `duration_min = 1800`. Nothing downstream questions it — it feeds the
        // sleep score, the debt gauge, and the stress fragmentation
        // denominator, where a 30-hour asleep figure reads as an unusually calm
        // night. Both halves of the picker's own stated range are enforced
        // here, because the store is the trust boundary and the picker is not.
        //
        // ponytail: 24 h is the WINDOW's length, not a physiological claim —
        // the cap only has to make an impossible night unrepresentable. A
        // tighter figure is a founder decision, not a defensive one.
        guard end <= window.to.addingTimeInterval(6 * 3600),
              end.timeIntervalSince(start) <= 24 * 3600
        else { throw SleepEditError.impossibleNight(date) }
        return try writer.write { db in
            let inWindow = try SleepSessionRow
                .filter(Column("user_id") == userId
                        && Column("start_time") >= window.from
                        && Column("start_time") < window.to)
                .order(Column("duration_min").desc)
                .fetchAll(db)
            // A night nobody has written yet starts as a ZERO-LENGTH window
            // holding nothing, so strategy B reads the edit as an extension
            // from nothing — all core — rather than as a shift of nothing.
            var row = inWindow.first ?? SleepSessionRow(
                id: newOnyxID(), userId: userId, startTime: start, endTime: start, durationMin: 0,
                deepMin: 0, remMin: 0, coreMin: 0, awakeMin: 0, createdAt: now
            )

            if let night {
                row.durationMin = night.sleepMinutes
                row.deepMin = night.deepMin
                row.remMin = night.remMin
                row.coreMin = night.storedCoreMin
                row.awakeMin = night.awakeMin
                row.onsetTime = onset ?? night.onset
                row.awakenings = night.awakenings
            } else {
                let stages = NightStages(
                    asleepMin: Double(row.durationMin), deepMin: Double(row.deepMin ?? 0), remMin: Double(row.remMin ?? 0),
                    coreMin: Double(row.coreMin ?? 0), awakeMin: Double(row.awakeMin ?? 0)
                )
                let trimmed = SleepTrim.trimStages(
                    stages,
                    oldSpanMin: row.endTime.timeIntervalSince(row.startTime) / 60,
                    newSpanMin: end.timeIntervalSince(start) / 60
                )
                row.durationMin = Int(trimmed.asleepMin)
                row.deepMin = Int(trimmed.deepMin)
                row.remMin = Int(trimmed.remMin)
                row.coreMin = Int(trimmed.coreMin)
                row.awakeMin = Int(trimmed.awakeMin)
                // Proportional stages know nothing about WHEN — a stored onset
                // survives only if the new window still holds it.
                row.onsetTime = onset ?? row.onsetTime.flatMap { $0 >= start && $0 < end ? $0 : nil }
            }
            row.startTime = start
            row.endTime = end
            row.hkUuid = ManualEntry.sleepSentinel(date)
            try row.save(db)
            try Self.enqueueRowUpsert(table: SleepSessionRow.databaseTableName, id: row.id, in: db)

            // A second row in the same window is the duplicate the unique
            // index exists to forbid; it goes, and its delete is queued.
            for extra in inWindow.dropFirst() {
                try extra.delete(db)
                try Self.enqueueRowDelete(table: SleepSessionRow.databaseTableName, key: ["id": extra.id], in: db)
            }

            let minutes = row.durationMin
            // The same artifact gate the ingest runs; a re-read that finds a
            // strap artifact leaves the stored figure alone.
            let accepted = try hrvMs.flatMap { v in
                try VitalsGate.hrvArtifact(v, history: Self.hrvHistory(db, userId: userId, before: date)) == nil ? v : nil
            }
            _ = try Self.patchDailyLog(db, userId: userId, date: date, now: now, clearing: []) {
                $0.sleepMinutes = minutes
                if let accepted { $0.hrvMs = accepted }
            }
            return row
        }
    }

    /// `(date, sleep_minutes)` for every day in `from...to`, oldest first — the
    /// input to `SleepDebt.compute`. Two columns of a fifty-column row, on
    /// purpose: the gauge redraws when a night changes, not when a step count does.
    func nightMinutesStream(userId: String, from: String, to: String) -> AsyncThrowingStream<[NightMinutes], any Error> {
        stream(ValueObservation.tracking { db in
            try Row.fetchAll(
                db,
                sql: "SELECT date, sleep_minutes FROM daily_logs WHERE user_id = ? AND date >= ? AND date <= ? ORDER BY date",
                arguments: [userId, from, to]
            ).map { NightMinutes(date: $0["date"], sleepMinutes: $0["sleep_minutes"]) }
        })
    }

    // MARK: - nutrition_entries

    func nutritionEntriesStream(userId: String, date: String) -> AsyncThrowingStream<[NutritionEntryRow], any Error> {
        stream(ValueObservation.tracking { db in
            try NutritionEntryRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .order(Column("logged_at"))
                .fetchAll(db)
        })
    }

    /// Hand-corrected macros for the whole day: ONE `daily` row with the
    /// per-day manual sentinel in `hk_uuid`, so HealthKit's ingest skips the
    /// day and a re-save upserts the same row rather than colliding on the
    /// unique index (the `'manual'` literal could only ever exist on one date).
    func setManualMacros(
        userId: String, date: String,
        calories: Double, proteinG: Double, carbsG: Double, fatG: Double, phase: String?,
        now: Date = Date()
    ) throws {
        try writer.write { db in
            var row = try NutritionEntryRow
                .filter(Column("user_id") == userId && Column("date") == date && Column("meal_type") == "daily")
                .fetchOne(db)
                ?? NutritionEntryRow(
                    id: newOnyxID(), userId: userId, loggedAt: Self.utcInstant(date, hour: 12) ?? now,
                    date: date, mealType: "daily", calories: 0, proteinG: 0, carbsG: 0, fatG: 0, createdAt: now
                )
            row.hkUuid = "manual-\(date)"
            row.calories = max(0, calories.rounded())
            row.proteinG = max(0, proteinG)
            row.carbsG = max(0, carbsG)
            row.fatG = max(0, fatG)
            row.phase = phase
            try row.save(db)
            try Self.enqueueRowUpsert(table: NutritionEntryRow.databaseTableName, id: row.id, in: db)
        }
    }

    // MARK: - water_intake

    func waterIntakeStream(userId: String, date: String) -> AsyncThrowingStream<[WaterIntakeRow], any Error> {
        stream(ValueObservation.tracking { db in
            try WaterIntakeRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .order(Column("logged_at"))
                .fetchAll(db)
        })
    }

    /// Replace the day's water with one hand-entered figure.
    ///
    /// Two stores, kept in step: `daily_logs.water_ml` is what every surface
    /// renders, `water_intake` is what the scorer sums. The whole day's ledger
    /// is replaced — HealthKit's rows included — so it lands on exactly one row,
    /// and the row carries the water sentinel that tells the ingest to leave the
    /// day alone from now on.
    func setWaterOverride(userId: String, date: String, ml: Double, now: Date = Date()) throws {
        try writer.write { db in
            let amount = max(0, ml.rounded())
            _ = try Self.patchDailyLog(db, userId: userId, date: date, now: now, clearing: []) { $0.waterMl = amount }
            try Self.deleteWater(db, userId: userId, date: date)
            let row = WaterIntakeRow(
                id: newOnyxID(), userId: userId, hkUuid: "manual-water-\(date)",
                loggedAt: Self.utcInstant(date, hour: 12) ?? now, date: date, amountMl: amount, createdAt: now
            )
            try row.save(db)
            try Self.enqueueRowUpsert(table: WaterIntakeRow.databaseTableName, id: row.id, in: db)
        }
    }

    /// One glass, added to the day.
    ///
    /// ── WHY THIS IS NOT `setWaterOverride` WITH ARITHMETIC IN THE CALLER ────
    /// It was, and that is the whole of the "Apple Health water never reaches
    /// the Nutrition page" bug. Tapping the water row read the day's figure,
    /// added 250, and called `setWaterOverride` — which REPLACES the ledger
    /// with one row carrying `manual-water-<date>`, the sentinel that makes
    /// `ingest` decline that date's water in both stores, silently, forever.
    /// One stray tap on the tab's most-tapped control disconnected the day from
    /// Apple Health, and the only way back was a long press into a sheet whose
    /// escape hatch is only drawn once you are already locked out.
    ///
    /// A glass is an ADDITION to a day Apple is still measuring, so it is its
    /// own row under its own prefix. `ingest` adds the glasses to HealthKit's
    /// reading rather than choosing between them, the ledger the scorer sums
    /// stays the sum of both, and the sheet keeps its override — which is a
    /// different verb and still says so in its own footer.
    func addWaterGlass(userId: String, date: String, ml: Double, now: Date = Date()) throws {
        try writer.write { db in
            let amount = max(0, ml.rounded())
            guard amount > 0 else { return }
            let row = WaterIntakeRow(
                id: newOnyxID(), userId: userId, hkUuid: ManualEntry.glassSentinel(date),
                loggedAt: now, date: date, amountMl: amount, createdAt: now
            )
            try row.save(db)
            try Self.enqueueRowUpsert(table: WaterIntakeRow.databaseTableName, id: row.id, in: db)
            // The flat row carries the LEDGER's sum — Apple's row, the glasses,
            // and an override if one is standing. Re-read rather than
            // incremented: `daily_logs.water_ml` is a projection of the ledger
            // and a second running total is a second thing to keep in step.
            let total = try WaterIntakeRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .fetchAll(db)
                .reduce(0) { $0 + $1.amountMl }
            _ = try Self.patchDailyLog(db, userId: userId, date: date, now: now, clearing: []) {
                $0.waterMl = total
            }
        }
    }

    /// Hand the day back to Apple Health.
    ///
    /// ── IT CLEARS THE OVERRIDE, NOT THE DAY (W1) ────────────────────────────
    /// It used to delete the WHOLE ledger and nil `daily_logs.water_ml`, and
    /// that is half of the `— / 3.0 L` the founder reported. The other half is
    /// that `DailyLogIngest` returns at `guard !payload.isEmpty` when HealthKit
    /// has nothing to say, so it never mints the row back: on a phone where the
    /// water read is denied, "until the next sync" is forever.
    ///
    /// The one-way door this button exists to open is the `manual-water-<date>`
    /// sentinel — that, and only that, is what makes `ingest` decline the date.
    /// So that is what is deleted. HealthKit's own row and the glasses tapped on
    /// the tab are measurements of the same day and survive; the flat column is
    /// re-derived from whatever is left, by the same rule `WaterTruth` reads it
    /// back with, so the projection and the ledger cannot disagree.
    ///
    /// `water_ml` is named in `clearing` only when nothing is left, so the
    /// server's copy is cleared rather than merged over.
    func clearWaterOverride(userId: String, date: String, now: Date = Date()) throws {
        try writer.write { db in
            try Self.deleteWater(db, userId: userId, date: date, onlyOverride: true)
            let remaining = try WaterIntakeRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .fetchAll(db)
            let total: Double? = remaining.isEmpty
                ? nil
                : remaining.reduce(0) { $0 + $1.amountMl }
            _ = try Self.patchDailyLog(
                db, userId: userId, date: date, now: now,
                clearing: total == nil ? ["water_ml"] : []
            ) { $0.waterMl = total }
        }
    }

    /// - Parameter onlyOverride: keep HealthKit's row and the tapped glasses,
    ///   removing just the hand-entered figure. `setWaterOverride` passes false
    ///   — replacing the day IS its verb, and it says so in its own footer.
    private static func deleteWater(
        _ db: Database, userId: String, date: String, onlyOverride: Bool = false
    ) throws {
        let rows = try WaterIntakeRow
            .filter(Column("user_id") == userId && Column("date") == date)
            .fetchAll(db)
        for row in rows where !onlyOverride || ManualEntry.isManualWater(row.hkUuid) {
            try row.delete(db)
            try enqueueRowDelete(table: WaterIntakeRow.databaseTableName, key: ["id": row.id], in: db)
        }
    }

    // MARK: - daily_targets / target_profiles

    /// The day's override, or `nil` — the rung in force applies.
    func dailyTargetStream(userId: String, date: String) -> AsyncThrowingStream<DailyTargetRow?, any Error> {
        stream(ValueObservation.tracking { db in
            try DailyTargetRow.filter(Column("user_id") == userId && Column("date") == date).fetchOne(db)
        })
    }

    func targetProfilesStream(userId: String) -> AsyncThrowingStream<[TargetProfileRow], any Error> {
        stream(ValueObservation.tracking { db in
            try TargetProfileRow.filter(Column("user_id") == userId).order(Column("sort")).fetchAll(db)
        })
    }

    /// Set (or re-set) the day's target. A fresh row tracks carbs and fat, as
    /// the web's does; the caller flips those for a day whose fat should not be
    /// graded. Keyed on `(user_id, date)` — no `id` on either side.
    func setDailyTarget(
        userId: String, date: String, now: Date = Date(),
        _ change: @Sendable (inout DailyTargetRow) -> Void
    ) throws {
        try writer.write { db in
            var row = try DailyTargetRow
                .filter(Column("user_id") == userId && Column("date") == date)
                .fetchOne(db)
                ?? DailyTargetRow(userId: userId, date: date, updatedAt: Self.localWriteTimestamp, trackCarbs: true, trackFat: true)
            change(&row)
            try row.save(db)
            try Self.enqueueRowUpsert(
                table: DailyTargetRow.databaseTableName,
                id: try Self.rowID(table: DailyTargetRow.databaseTableName, key: ["user_id": userId, "date": date], in: db),
                in: db
            )
        }
    }

    /// Drop the override — the day goes back to whatever rung is in force.
    func clearDailyTarget(userId: String, date: String) throws {
        try writer.write { db in
            _ = try DailyTargetRow.filter(Column("user_id") == userId && Column("date") == date).deleteAll(db)
            try Self.enqueueRowDelete(
                table: DailyTargetRow.databaseTableName, key: ["user_id": userId, "date": date], in: db
            )
        }
    }

    // MARK: - schedule_overrides / program_day_layout

    /// Every per-date swap, date → day key (or `"rest"`). The whole table: it
    /// is a few dozen rows and the schedule rule needs any of them.
    func scheduleOverridesStream(userId: String) -> AsyncThrowingStream<[String: String], any Error> {
        stream(ValueObservation.tracking { db in
            let rows = try ScheduleOverrideRow.filter(Column("user_id") == userId).fetchAll(db)
            return Dictionary(rows.map { ($0.date, $0.dayKey) }, uniquingKeysWith: { _, last in last })
        })
    }

    /// The permanent weekday layout of one plan, if the user has remapped it.
    func programDayLayoutStream(userId: String, programId: String) -> AsyncThrowingStream<ProgramDayLayoutRow?, any Error> {
        stream(ValueObservation.tracking { db in
            try ProgramDayLayoutRow
                .filter(Column("user_id") == userId && Column("program_id") == programId)
                .fetchOne(db)
        })
    }

    /// Apply a swap plan's writes — a rest-day swap is TWO rows — and queue them.
    ///
    /// ── THE SUPPLEMENT CASCADE ──────────────────────────────────────────────
    /// A training-only stimulant is not part of a rest day, and absence in
    /// `supplement_log` means taken. So whichever direction a date moves, the
    /// right state for its training-only rows is GONE: Train→Rest removes a
    /// skip for a dose that stopped being asked for, Rest→Train removes nothing
    /// that needs to exist. One writer, both directions, shared with the undo.
    func applyScheduleWrites(
        userId: String, _ writes: [(date: String, dayKey: String)],
        trainingOnlySupplementKeys: [String] = [], now: Date = Date()
    ) throws {
        guard !writes.isEmpty else { return }
        try writer.write { db in
            for write in writes {
                var row = try ScheduleOverrideRow
                    .filter(Column("user_id") == userId && Column("date") == write.date)
                    .fetchOne(db)
                    ?? ScheduleOverrideRow(userId: userId, date: write.date, dayKey: write.dayKey, updatedAt: Self.localWriteTimestamp)
                row.dayKey = write.dayKey
                try row.save(db)
                try Self.enqueueRowUpsert(
                    table: ScheduleOverrideRow.databaseTableName,
                    id: try Self.rowID(table: ScheduleOverrideRow.databaseTableName, key: ["user_id": userId, "date": write.date], in: db),
                    in: db
                )
                try Self.dropTrainingOnlySupplements(db, userId: userId, date: write.date, keys: trainingOnlySupplementKeys)
            }
        }
    }

    /// A whole week's edit: the overrides to write and the ones to delete, in
    /// ONE transaction.
    ///
    /// ── WHY NOT JUST CALL THE TWO ───────────────────────────────────────────
    /// Because they are one change. `applyScheduleWrites` and
    /// `clearScheduleOverrides` each open their own `write`, so calling them in
    /// sequence lets the first commit and enqueue while the second throws —
    /// leaving a week half rearranged and half pinned, which is the state the
    /// undo path takes a LIST of dates to prevent one tier down. The week sheet
    /// also tells the user "Nothing was altered" on failure, and that sentence
    /// has to be true.
    func applyWeekOverrides(
        userId: String,
        writes: [(date: String, dayKey: String)],
        clears: [String],
        trainingOnlySupplementKeys: [String] = []
    ) throws {
        guard !writes.isEmpty || !clears.isEmpty else { return }
        try writer.write { db in
            for write in writes {
                var row = try ScheduleOverrideRow
                    .filter(Column("user_id") == userId && Column("date") == write.date)
                    .fetchOne(db)
                    ?? ScheduleOverrideRow(userId: userId, date: write.date, dayKey: write.dayKey, updatedAt: Self.localWriteTimestamp)
                row.dayKey = write.dayKey
                try row.save(db)
                try Self.enqueueRowUpsert(
                    table: ScheduleOverrideRow.databaseTableName,
                    id: try Self.rowID(table: ScheduleOverrideRow.databaseTableName, key: ["user_id": userId, "date": write.date], in: db),
                    in: db
                )
                try Self.dropTrainingOnlySupplements(db, userId: userId, date: write.date, keys: trainingOnlySupplementKeys)
            }
            for date in clears {
                _ = try ScheduleOverrideRow.filter(Column("user_id") == userId && Column("date") == date).deleteAll(db)
                try Self.enqueueRowDelete(
                    table: ScheduleOverrideRow.databaseTableName, key: ["user_id": userId, "date": date], in: db
                )
                try Self.dropTrainingOnlySupplements(db, userId: userId, date: date, keys: trainingOnlySupplementKeys)
            }
        }
    }

    /// Undo. Takes a LIST because a rest-day swap touches two dates, and undoing
    /// one leaves the week half-rearranged — worse than either state.
    func clearScheduleOverrides(
        userId: String, dates: [String], trainingOnlySupplementKeys: [String] = []
    ) throws {
        guard !dates.isEmpty else { return }
        try writer.write { db in
            for date in dates {
                _ = try ScheduleOverrideRow.filter(Column("user_id") == userId && Column("date") == date).deleteAll(db)
                try Self.enqueueRowDelete(
                    table: ScheduleOverrideRow.databaseTableName, key: ["user_id": userId, "date": date], in: db
                )
                try Self.dropTrainingOnlySupplements(db, userId: userId, date: date, keys: trainingOnlySupplementKeys)
            }
        }
    }

    private static func dropTrainingOnlySupplements(_ db: Database, userId: String, date: String, keys: [String]) throws {
        guard !keys.isEmpty else { return }
        let rows = try SupplementLogRow
            .filter(Column("user_id") == userId && Column("date") == date && keys.contains(Column("item_key")))
            .fetchAll(db)
        for row in rows {
            try row.delete(db)
            try enqueueRowDelete(
                table: SupplementLogRow.databaseTableName,
                key: ["user_id": userId, "date": date, "item_key": row.itemKey], in: db
            )
        }
    }

    /// Committed sessions on the given dates, as the swap rule needs to see
    /// them: a date that holds a finished session cannot have its plan changed
    /// under it (`Swap.blockForPlacement`). A session still open is not yet a
    /// fact about the day.
    func loggedDays(userId: String, dates: [String]) throws -> [LoggedSessionDay] {
        guard !dates.isEmpty else { return [] }
        return try writer.read { db in
            try WorkoutSession
                .filter(Column("user_id") == userId && dates.contains(Column("date")) && Column("ended_at") != nil)
                .order(Column("date"))
                .fetchAll(db)
                .map { LoggedSessionDay(date: $0.date, dayKey: $0.dayKey) }
        }
    }


    /// Whether the date carries a session at all — the UI half of the ONE day
    /// rule (`AppDatabase.isTrainingDay`).
    ///
    /// ── WHY IT IS NOT `loggedDays` ──────────────────────────────────────────
    /// That one filters `ended_at IS NOT NULL`, because a swap may not move a
    /// day whose session is a FACT. This question is different: the fatigue
    /// slots and the day's stack have to switch to the training shape the
    /// moment a session starts, not when it is closed — the slot being asked
    /// for is "Before training", and it is asked for mid-session. So this
    /// counts sessions exactly as `ScheduleResolution.isTrainingDay` counts
    /// them, and the screen and the scorer cannot disagree about the day's kind.
    ///
    /// A stream and not a read: `isTraining` is read from a view body on every
    /// render, and a synchronous query there is a query per frame.
    func sessionLoggedStream(userId: String, date: String) -> AsyncThrowingStream<Bool, any Error> {
        stream(ValueObservation.tracking { db in
            try WorkoutSession
                .filter(Column("user_id") == userId && Column("date") == date)
                .fetchCount(db) > 0
        })
    }

    /// When the date's LAST session ended — nil while none has, and nil while
    /// ANY is still running. The fatigue card's question flips on it
    /// (`Fatigue.askingSlot`). A running session has `ended_at` NULL, and
    /// SQL's MAX skips NULLs across rows, so a bare MAX on a two-a-day would
    /// answer the morning's finish while the afternoon is mid-set; the COUNT
    /// guard makes an open session win over any closed one.
    func sessionEndedStream(userId: String, date: String) -> AsyncThrowingStream<Date?, any Error> {
        stream(ValueObservation.tracking { db in
            try Date.fetchOne(
                db,
                sql: """
                SELECT CASE WHEN COUNT(*) > COUNT(ended_at) THEN NULL ELSE MAX(ended_at) END
                FROM workout_sessions WHERE user_id = ? AND date = ?
                """,
                arguments: [userId, date]
            )
        })
    }

    // MARK: - Helpers

    /// `<date>T<hour>:00:00Z` — the fixed UTC stamps the web writes for a manual
    /// row, so a re-save from either app lands on the same instant.
    static func utcInstant(_ date: String, hour: Int) -> Date? {
        NightWindow.midnight(date)?.addingTimeInterval(TimeInterval(hour) * 3600)
    }
}

/// Why a sleep edit was refused before it touched the store.
public enum BodyMetricError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A typed scale reading outside what a body can report — field, value, why.
    case outOfRange(String, Double, String)
    public var description: String {
        switch self { case .outOfRange(let field, let v, let why): "\(field) \(v) is \(why)" }
    }
}

public enum SleepEditError: Error, Equatable, Sendable {
    /// `end` was not after `start`.
    case emptyWindow
    case badDate(String)
    /// `start` was not inside `NightWindow.range(date)` — the row would belong
    /// to no night, or to the wrong one.
    case outsideNight(String)
    /// The "fell asleep" wheel was outside `[start, end)` (W3).
    case onsetOutsideWindow(String)
    /// `end` reached past the wake wheel's own close, or the two together
    /// described a span no night can have.
    case impossibleNight(String)
}

/// One night's minutes, for the sleep-debt gauge.
public struct NightMinutes: Sendable, Equatable {
    public let date: String
    public let sleepMinutes: Int?

    public init(date: String, sleepMinutes: Int?) {
        self.date = date
        self.sleepMinutes = sleepMinutes
    }
}

/// A committed session, as the scheduler needs to see it.
public struct LoggedSessionDay: Sendable, Equatable {
    public let date: String
    public let dayKey: String?

    public init(date: String, dayKey: String?) {
        self.date = date
        self.dayKey = dayKey
    }
}
