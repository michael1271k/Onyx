import Foundation
import GRDB
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// `prescriptions` — the CURRENT instruction per movement, appended and never
// overwritten.
//
// A prescription is an instruction with a date on it, and its history is the
// argument a progression review is made of: "the top set went 34 → 36 on the
// 14th" cannot be said by a table that UPDATEs. So every ingest INSERTS, the
// version is one past whatever that movement already had, and the only read
// that resolves "what is in force today" is `Prescriptions.current`.
// ─────────────────────────────────────────────────────────────────────────────

public extension AppDatabase {

    /// Every prescription this user has ever been given, oldest first.
    func prescriptions(userId: String) throws -> [Prescription] {
        try read { db in
            try PrescriptionRow
                .filter(Column("user_id") == userId)
                .order(Column("effective_from"), Column("version"))
                .fetchAll(db)
                .map(Prescription.init)
        }
    }

    /// The version in force on `date`, per canonical exercise name.
    func currentPrescriptions(userId: String, on date: String) throws -> [String: Prescription] {
        Prescriptions.current(try prescriptions(userId: userId), on: date)
    }

    /// Append one version per drafted movement, and say what landed.
    ///
    /// ── THE VERSION IS ASSIGNED HERE, NOT BY THE PARSER ─────────────────────
    /// The parser reads a block of text and has no idea what the ledger already
    /// holds; the next ordinal is a fact about the STORE. A draft's own
    /// `version` is therefore ignored, which is also what stops a second paste
    /// of the same block from writing `v1` twice.
    ///
    /// Two versions of one movement in a single paste keep their order: the
    /// later line is the later version, which is what a coach editing a table
    /// in place means by writing two rows.
    @discardableResult
    func appendPrescriptions(
        _ drafts: [Prescription], userId: String, now: Date = Date()
    ) throws -> [Prescription] {
        guard !drafts.isEmpty else { return [] }
        return try writer.write { db in
            var nextVersion: [String: Int] = [:]
            var landed: [Prescription] = []
            for draft in drafts {
                let key = ExerciseAliases.canonicalName(draft.exercise)
                let version: Int
                if let n = nextVersion[key] {
                    version = n
                } else {
                    let highest = try Int.fetchOne(db, sql: """
                        SELECT MAX(version) FROM prescriptions WHERE user_id = ? AND exercise_key = ?
                        """, arguments: [userId, key]) ?? 0
                    version = highest + 1
                }
                nextVersion[key] = version + 1
                var stored = draft
                stored.exercise = key
                stored.version = version
                let row = PrescriptionRow(stored, id: newOnyxID(), userId: userId, createdAt: now)
                try row.save(db)
                try Self.enqueueRowUpsert(table: PrescriptionRow.databaseTableName, id: row.id, in: db)
                landed.append(stored)
            }
            return landed
        }
    }
}

// MARK: - Row ↔ domain

extension Prescription {
    init(_ row: PrescriptionRow) {
        self.init(
            exercise: row.exerciseKey,
            loadKg: row.loadKg,
            sets: row.sets,
            repRange: row.repRange,
            rpeCap: row.rpeCap,
            structure: Structure(rawValue: row.structure) ?? .straight,
            setLoads: PrescriptionRow.decodeLoads(row.setLoads),
            leadRule: LeadRule(rawValue: row.leadRule) ?? Prescription.LeadRule.none,
            notes: row.notes,
            effectiveFrom: row.effectiveFrom,
            version: row.version
        )
    }
}

extension PrescriptionRow {
    init(_ p: Prescription, id: String, userId: String, createdAt: Date) {
        self.init(
            id: id, userId: userId, exerciseKey: p.exercise, version: p.version,
            effectiveFrom: p.effectiveFrom, loadKg: p.loadKg, sets: p.sets,
            repRange: p.repRange, rpeCap: p.rpeCap, structure: p.structure.rawValue,
            setLoads: Self.encodeLoads(p.setLoads), leadRule: p.leadRule.rawValue,
            notes: p.notes, createdAt: createdAt
        )
    }

    /// `set_loads` is a Postgres `numeric[]`, which PostgREST serialises as a
    /// JSON array — so the column is the raw JSON, decoded only here.
    static func decodeLoads(_ text: JSONText?) -> [Double]? {
        guard let raw = text?.raw, !raw.isEmpty,
              let out = try? JSONDecoder().decode([Double].self, from: Data(raw.utf8)),
              !out.isEmpty
        else { return nil }
        return out
    }

    static func encodeLoads(_ loads: [Double]?) -> JSONText? {
        guard let loads, !loads.isEmpty,
              let data = try? JSONEncoder().encode(loads),
              let raw = String(data: data, encoding: .utf8)
        else { return nil }
        return JSONText(raw: raw)
    }
}
