import Foundation
import GRDB
import OnyxCore

/// The stack, edited from the phone.
///
/// ── WHY THIS FILE EXISTS AT ALL ─────────────────────────────────────────────
/// `custom_supplements` has been a PULL-ONLY table since the mirror was built:
/// the phone drew the stack and the web owned it. Wave 4 wired the table's push
/// closure and then had nothing to push, because there was no way to change a
/// supplement without a laptop. Wave 6 gives the phone the Stack screen, and
/// these are the writes behind it — every one of them local-first, and every
/// one of them enqueued so the row reaches the server on the next drain.
///
/// ── AND WHY ARCHIVING IS NOT DELETING ───────────────────────────────────────
/// The web deletes a supplement outright. That takes the row's `schedule.key`
/// with it, and the key is the join to every `supplement_log` row the item ever
/// wrote — so deleting something you stopped taking in June silently rewrites
/// June's credit. `archived_at` stops the item being scheduled from that date
/// forward and leaves the history alone. Delete stays available for a row added
/// by mistake, which is the only case where there is no history to protect.
public extension AppDatabase {

    /// What the day's log says about one dose.
    enum SupplementMark: Sendable, Equatable {
        /// An explicit tick. Counts the moment it is written, whatever the clock.
        case taken
        /// A refusal. Never counts.
        case skipped
        /// Back to the protocol: the row is deleted, and absence means the dose
        /// counts once its slot time has passed.
        case cleared
    }

    // MARK: - The log

    /// Mark a dose taken, skipped, or back to the protocol.
    ///
    /// `dueAt` is the slot's own time, never `now()`. The stamp says when the
    /// dose was DUE — half the timestamps in this table were auto-log writes
    /// already stamped with the slot's clock, so mixing in the moment of the
    /// tap would leave the column meaning two different things per row.
    func markSupplement(
        userId: String, date: String, itemKey: String, mark: SupplementMark, dueAt: Date? = nil
    ) throws {
        try writer.write { db in
            let key = ["user_id": userId, "date": date, "item_key": itemKey]
            let scope = SupplementLogRow
                .filter(Column("user_id") == userId && Column("date") == date && Column("item_key") == itemKey)
            guard mark != .cleared else {
                _ = try scope.deleteAll(db)
                try Self.enqueueRowDelete(table: SupplementLogRow.databaseTableName, key: key, in: db)
                return
            }
            var row = try scope.fetchOne(db) ?? SupplementLogRow(
                userId: userId, date: date, itemKey: itemKey, taken: mark == .taken,
                takenAt: dueAt, updatedAt: Self.localWriteTimestamp
            )
            row.taken = mark == .taken
            row.takenAt = dueAt
            try row.save(db)
            try Self.enqueueRowUpsert(
                table: SupplementLogRow.databaseTableName,
                id: try Self.rowID(table: SupplementLogRow.databaseTableName, key: key, in: db),
                in: db
            )
        }
    }

    /// The Wave 2 spelling, kept because the swap cascade and its tests speak it.
    func setSupplementSkipped(
        userId: String, date: String, itemKey: String, skipped: Bool, dueAt: Date? = nil
    ) throws {
        try markSupplement(userId: userId, date: date, itemKey: itemKey, mark: skipped ? .skipped : .cleared, dueAt: dueAt)
    }

    // MARK: - The stack itself

    /// Add a supplement. Returns the new row's id.
    ///
    /// The row gets a `schedule.key` of its own id from the start. The web's
    /// insert leaves it unset and falls back to `custom:<id>` at read time,
    /// which works until someone edits the schedule and the fallback moves —
    /// writing it once means the log key is fixed the moment the item exists.
    @discardableResult
    func addCustomSupplement(
        userId: String, name: String, dose: String,
        color: String? = nil, form: String? = nil, time: String? = nil,
        schedule: CustomSchedule? = nil, micros: [String: Double]? = nil,
        doseAmount: Double? = nil, doseUnit: String? = nil,
        otherIngredients: [String]? = nil,
        now: Date = Date()
    ) throws -> String {
        let id = newOnyxID()
        var resolved = schedule ?? CustomSchedule()
        if (resolved.key ?? "").isEmpty { resolved.key = "custom:\(id)" }
        let row = CustomSupplementRow(
            id: id, userId: userId, name: name, dose: dose,
            color: color, form: form, time: time,
            schedule: try Self.json(resolved), micros: try Self.json(micros),
            createdAt: now, archivedAt: nil,
            doseAmount: doseAmount, doseUnit: doseUnit, sortOrder: 0,
            // Nil, never `[]`, for a row with nothing to keep: a nil stays out
            // of the push body until the founder's DDL adds the column.
            otherIngredients: (otherIngredients ?? []).isEmpty ? nil : try Self.json(otherIngredients)
        )
        try writer.write { db in
            try row.insert(db)
            try Self.enqueueRowUpsert(table: CustomSupplementRow.databaseTableName, id: id, in: db)
        }
        return id
    }

    /// Edit one row in place. The block sees the stored row and mutates it.
    func editCustomSupplement(id: String, userId: String, _ mutate: (inout CustomSupplementRow) -> Void) throws {
        try writer.write { db in
            guard var row = try CustomSupplementRow
                .filter(Column("id") == id && Column("user_id") == userId)
                .fetchOne(db)
            else { return }
            mutate(&row)
            try row.save(db)
            // ── EVERY CLEARED COLUMN HAS TO SAY ITS OWN NAME ────────────────
            // A merge upsert OMITS a nil rather than writing one, so a column
            // the user just blanked keeps its old server value and the next
            // pull hands it straight back. Un-archiving was the obvious case;
            // clearing a supplement's TIME is the one that would have gone
            // unnoticed — the item drops into the "—" bucket locally and is
            // back at 22:00 tomorrow.
            //
            // The table is pulled WHOLE (`strategy: .full`), so the local row
            // is the truth about every one of these: naming each nil one makes
            // the server match it exactly.
            //
            // THREE columns are deliberately NOT in the list. `created_at`,
            // because nothing clears it and a null there would be a lie. And
            // `sort_order`, because it is nullable in the local mirror only —
            // Postgres has it NOT NULL DEFAULT 0 (the W2 rule: a pull before
            // the paste must still decode), so naming it would push a null into
            // a column that refuses one. `dose_periods` is the third, for the
            // reason `clearedColumns` gives.
            try Self.enqueueRowUpsert(
                table: CustomSupplementRow.databaseTableName, id: id,
                nulls: Self.clearedColumns(of: row), in: db
            )
        }
    }

    /// Edit everything a phone has any business changing, in one write.
    ///
    /// ── WHY THE SCHEDULE IS MERGED AND NEVER REPLACED ───────────────────────
    /// `custom_supplements.schedule` is a jsonb that carries FIVE facts the
    /// editor has no field for — `key`, `slot`, `notes`, `trainingDose`,
    /// `restDose` — and `key` is the join to every `supplement_log` row the
    /// item ever wrote. Handing this a freshly built `CustomSchedule(days:
    /// trainingOnly:)` would drop all five, and the day the key goes is the day
    /// months of ticked history stops resolving — silently, because the item
    /// keeps rendering under a `custom:<id>` fallback that matches nothing.
    /// So the stored value is decoded, the two fields the form owns are set,
    /// and the rest is written back exactly as it was found.
    ///
    /// The editor could not reach `days` or `trainingOnly` at all before this:
    /// the only way to change an item's schedule was to delete it and add it
    /// again, which is that same silent loss with an extra step.
    ///
    /// ── A NEW DOSE STARTS `today`; THE OLD ONE IS KEPT ──────────────────────
    /// Changing 300 mg to 200 mg used to rewrite every day the item had ever
    /// been taken. The dose being replaced is now closed at `today` and
    /// appended to `dose_periods` (`Supplements.dosePeriods`), so a day before
    /// the change still reads 300 mg through `Supplements.doseAt`. `today` is
    /// the logical day the edit was made on, whichever day the screen showed.
    func updateCustomSupplement(
        id: String, userId: String,
        name: String, dose: String, doseAmount: Double?, doseUnit: String?,
        form: String?, time: String?, days: [Int], trainingOnly: Bool,
        today: String = LogicalDay.today()
    ) throws {
        try editCustomSupplement(id: id, userId: userId) { row in
            let before = Self.custom(row)
            row.name = name
            row.dose = dose
            row.doseAmount = doseAmount
            row.doseUnit = doseUnit
            row.form = (form ?? "").isEmpty ? nil : form
            row.time = (time ?? "").isEmpty ? nil : time

            var schedule = row.schedule
                .flatMap { try? OnyxJSON.decoder.decode(CustomSchedule.self, from: Data($0.raw.utf8)) }
                ?? CustomSchedule()
            // An empty selection is "every day" and is stored as the ABSENCE of
            // the key, which is what `customSlotsForDate` reads — an empty
            // array would be a row scheduled on no day at all.
            schedule.days = days.isEmpty ? nil : days.sorted()
            schedule.trainingOnly = trainingOnly ? true : nil
            // The key is fixed the moment the item exists; a row the web wrote
            // may still have none, and this is the last safe moment to pin the
            // `custom:<id>` fallback it has been resolving to all along.
            if (schedule.key ?? "").isEmpty { schedule.key = "custom:\(id)" }
            row.schedule = (try? Self.json(schedule)) ?? row.schedule

            // Last, against the row as saved, so a dose that only LOOKS edited
            // (the same string written back) closes nothing. A stored history
            // this build cannot read is left exactly as it is: rewriting it
            // from nothing would erase every period it holds.
            let unreadable = row.dosePeriods != nil && before.dosePeriods == nil
            let periods = Supplements.dosePeriods(changing: before, to: Self.custom(row), today: today)
            if !unreadable, periods != before.dosePeriods { row.dosePeriods = (try? Self.json(periods)) ?? row.dosePeriods }
        }
    }

    /// Take an item out of the protocol, or put it back.
    func setCustomSupplementArchived(id: String, userId: String, archived: Bool, at: Date = Date()) throws {
        try editCustomSupplement(id: id, userId: userId) { row in
            row.archivedAt = archived ? at : nil
        }
    }

    /// Remove a row outright. For something added by mistake — see the header
    /// for why archiving is the right verb everywhere else.
    func deleteCustomSupplement(id: String, userId: String) throws {
        try writer.write { db in
            _ = try CustomSupplementRow
                .filter(Column("id") == id && Column("user_id") == userId)
                .deleteAll(db)
            try Self.enqueueRowDelete(table: CustomSupplementRow.databaseTableName, key: ["id": id], in: db)
        }
    }

    // MARK: - Reading the stack as the core wants it

    /// `custom_supplements` rows as `OnyxCore.CustomSupplement`.
    static func custom(_ row: CustomSupplementRow) -> CustomSupplement {
        CustomSupplement(
            id: row.id, name: row.name, dose: row.dose, color: row.color, form: row.form, time: row.time,
            schedule: row.schedule.flatMap { try? OnyxJSON.decoder.decode(CustomSchedule.self, from: Data($0.raw.utf8)) },
            micros: row.micros.flatMap { try? OnyxJSON.decoder.decode([String: Double].self, from: Data($0.raw.utf8)) },
            archivedAt: row.archivedAt.map(ISO8601.string),
            doseAmount: row.doseAmount, doseUnit: row.doseUnit,
            dosePeriods: row.dosePeriods.flatMap { try? OnyxJSON.decoder.decode([DosePeriod].self, from: Data($0.raw.utf8)) },
            otherIngredients: row.otherIngredients.flatMap { try? OnyxJSON.decoder.decode([String].self, from: Data($0.raw.utf8)) }
        )
    }

    /// The nullable columns that are nil on this row — the ones a merge upsert
    /// would otherwise leave standing on the server.
    private static func clearedColumns(of row: CustomSupplementRow) -> [String] {
        var out: [String] = []
        if row.color == nil { out.append("color") }
        if row.form == nil { out.append("form") }
        if row.time == nil { out.append("time") }
        if row.schedule == nil { out.append("schedule") }
        if row.micros == nil { out.append("micros") }
        if row.archivedAt == nil { out.append("archived_at") }
        // W4's pair. A user who blanks a unit and gets it handed back on the
        // next pull is the same defect the `time` case above already records.
        if row.doseAmount == nil { out.append("dose_amount") }
        if row.doseUnit == nil { out.append("dose_unit") }
        // `dose_periods` is deliberately NOT here. History only grows — an
        // undone change leaves `[]`, never nil — so a nil row has nothing to
        // clear, and naming it would push a null into a column the server may
        // not have yet on every edit of every row.
        return out
    }

    private static func json<T: Encodable>(_ value: T?) throws -> JSONText? {
        guard let value else { return nil }
        let data = try OnyxJSON.encoder.encode(value)
        return JSONText(raw: String(decoding: data, as: UTF8.self))
    }
}
