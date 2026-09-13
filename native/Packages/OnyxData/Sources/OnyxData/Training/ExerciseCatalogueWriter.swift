import Foundation
import GRDB
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Creating an `exercises` row — the half of the catalogue that never existed.
//
// Until W5 the only writer of this table was the PULLER (`TrainingPuller`
// `applyPulledExercises`): rows arrived from the server, created by the web app,
// and the phone could read them and nothing else. That was survivable while the
// web app existed and one person used it. A generic account has neither.
//
// ── WHY THIS IS NOT A `MirrorTable` IN `supabase.json` ──────────────────────
// `exercises` is marked `"bespoke": true` in the schema, and the reason is that
// the local table and the Postgres table are DIFFERENT TABLES that happen to
// share a name. Locally we invent `primary_muscle`, `is_unilateral` and
// `is_bodyweight`; Postgres has `user_id`, `split_day`, `muscle_groups` and
// `is_compound`, none of which exist here. The mirror generator emits one struct
// per table and saves it to SQLite by its own column names, so a generated
// `ExerciseRow` would be unsaveable locally — and adding the table to the
// catalogue would also break `MirrorTests.catalogueIsComplete`, which counts it.
//
// So the QUEUE is reused and only the wire shape is hand-written. An exercise
// enqueues an ordinary `row.upsert`, drains through the ordinary backoff, and
// shows up in the Sync Doctor like everything else; the only bespoke part is the
// six lines that turn a local row into the shape Postgres wants.
//
// ── THE OUTBOX ID CARRIES THE USER ──────────────────────────────────────────
// The local table has no `user_id` column — it never needed one, because a
// device holds one account's mirror. Postgres does, and it is NOT NULL. Rather
// than add a column to a table four files read with raw SQL, the queued id is
// `rowID([userId, exerciseId])`, exactly as every composite-key table already
// does it, and the push splits it back apart.
// ─────────────────────────────────────────────────────────────────────────────

public extension AppDatabase {

    /// Create one catalogue row and queue it for the server.
    ///
    /// Returns the id written. An existing row with the same NAME is left
    /// alone and its id returned instead — creating a second row for a name the
    /// catalogue already holds is the SPLIT that `ExerciseIndex`'s header exists
    /// to prevent, and an importer is precisely where it would happen.
    @discardableResult
    func createExercise(
        userId: String,
        name: String,
        primaryMuscle: String? = nil,
        secondaryMuscles: [String] = [],
        equipment: String? = nil,
        id: String? = nil
    ) throws -> String {
        try writer.write { db in
            try Self.createExercise(
                db, userId: userId, name: name, primaryMuscle: primaryMuscle,
                secondaryMuscles: secondaryMuscles, equipment: equipment, id: id
            )
        }
    }

    /// Many at once, in ONE transaction.
    ///
    /// A CSV import is sixty rows, and sixty transactions is sixty fsyncs and a
    /// visibly janky screen. It is also sixty chances to half-finish: an import
    /// that dies after row forty leaves a catalogue nobody asked for. One
    /// transaction is all-or-nothing.
    ///
    /// Returns the ids in the order the names were given, with a nil for any
    /// name that was blank.
    @discardableResult
    func createExercises(userId: String, _ rows: [ExerciseDraft]) throws -> [String?] {
        try writer.write { db in
            try rows.map { row in
                guard !row.name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return try Self.createExercise(
                    db, userId: userId, name: row.name, primaryMuscle: row.primaryMuscle,
                    secondaryMuscles: row.secondaryMuscles, equipment: row.equipment, id: nil
                )
            }
        }
    }

    static func createExercise(
        _ db: Database, userId: String, name: String, primaryMuscle: String?,
        secondaryMuscles: [String], equipment: String?, id: String?
    ) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        // The same key `ExerciseIndex.exactKey` resolves a name on, so "already
        // in the catalogue" cannot mean one thing here and another at push time.
        if let existing = try Exercise.fetchAll(db).first(where: {
            $0.name.lowercased().trimmingCharacters(in: .whitespaces) == trimmed.lowercased()
        }) {
            return existing.id
        }

        let rowId = id ?? newOnyxID()
        let row = Exercise(
            id: rowId,
            name: trimmed,
            primaryMuscle: primaryMuscle,
            // Stored as a JSON array in a text column — the shape
            // `WeeklyExportBuilder` already decodes.
            secondaryMuscles: secondaryMuscles.isEmpty ? nil : Self.jsonArray(secondaryMuscles),
            equipment: equipment,
            isUnilateral: Unilateral.isUnilateral(trimmed),
            isBodyweight: Bodyweight.isBodyweight(trimmed),
            // ── NO SLUG ON A NEW ROW (W6) ───────────────────────────────────
            // The column is an alias for the legacy id a pre-W6 build wrote
            // into `workout_sets.exercise_id`, and it is answered for by rows
            // that already existed when that build ran. A row created now has
            // no such history and never will: the logger resolves this id
            // before it writes. Stamping one would put the retired prefix into
            // new server data for a lookup nothing will ever perform.
            slug: nil
        )
        try row.insert(db)
        try Self.enqueueRowUpsert(
            table: "exercises", id: Self.rowID([userId, rowId]), in: db
        )
        return rowId
    }

    static func jsonArray(_ values: [String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(values)) ?? Data("[]".utf8), as: UTF8.self)
    }
}

/// One row an importer or the routine builder wants created.
public struct ExerciseDraft: Equatable, Sendable {
    public var name: String
    public var primaryMuscle: String?
    public var secondaryMuscles: [String]
    public var equipment: String?

    public init(
        name: String, primaryMuscle: String? = nil,
        secondaryMuscles: [String] = [], equipment: String? = nil
    ) {
        self.name = name; self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles; self.equipment = equipment
    }
}

// MARK: - The wire

/// A local `exercises` row in the shape Postgres holds it.
///
/// Written by hand because the two tables share only `id` and `name`. Every
/// optional is `encodeIfPresent` by Swift's synthesis, so a nil column is
/// omitted and the upsert MERGES — the same contract every mirrored row has.
struct ExerciseWire: Encodable, Sendable {
    var id: String
    var userId: String
    var name: String
    /// Primary first, then the assistance — the shape `MuscleMap.muscleGroups`
    /// writes and `MuscleMap.resolveMovers(_:stored:)` reads back.
    var muscleGroups: [String]?
    var secondaryMuscles: [String]?
    /// NOT NULL in Postgres, and a catalogue row belongs to no particular day.
    /// `custom` rather than `""` so the value reads as what it is in a table
    /// whose other rows name a programme day.
    var splitDay: String
    /// NOT NULL in Postgres. A movement with no equipment recorded is an empty
    /// list, which is a fact; null would be a missing one, and the column
    /// forbids it.
    var equipment: [String]
    var isCompound: Bool?
    var slug: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case muscleGroups = "muscle_groups"
        case secondaryMuscles = "secondary_muscles"
        case splitDay = "split_day"
        case equipment
        case isCompound = "is_compound"
        case slug
    }

    init(_ row: Exercise, userId: String) {
        id = row.id
        self.userId = userId
        name = row.name
        let secondary = ExerciseWire.decodeArray(row.secondaryMuscles)
        // Resolved the same way every reader resolves it: the name first, the
        // stored column only for a movement `MuscleMap` has never seen. A row
        // imported with its own tags carries them; a row whose name the
        // dictionary knows carries the dictionary's answer, so the server and
        // the phone cannot disagree about what a lat pulldown trains.
        let movers = MuscleMap.resolveMovers(
            row.name, stored: [row.primaryMuscle].compactMap { $0 } + secondary
        )
        muscleGroups = movers.primary.isEmpty && movers.secondary.isEmpty
            ? nil : movers.primary + movers.secondary
        secondaryMuscles = secondary.isEmpty ? nil : secondary
        splitDay = "custom"
        equipment = row.equipment.map { [$0] } ?? []
        isCompound = movers.secondary.isEmpty ? false : true
        slug = row.slug
    }

    static func decodeArray(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

public extension MirrorCatalogue {

    /// The generated catalogue plus the tables whose wire shape is hand-written.
    ///
    /// `SyncEngine` takes this rather than `byName`, so a bespoke table gets the
    /// queue, the backoff and the Sync Doctor for free. `tables` itself is
    /// untouched — the PULL side of `exercises` is `TrainingPuller`'s and
    /// listing it here as well would fetch it twice.
    static let pushable: [String: MirrorTable] = {
        var out = byName
        out["exercises"] = MirrorTable(
            name: "exercises",
            group: .training,
            strategy: .full,
            conflict: "id",
            order: ["id"],
            // Never pulled through the generic puller — `TrainingPuller` owns
            // the read, because the local shape is not the remote shape.
            pull: { _, _ in 0 },
            push: { database, remote, ref in
                let parts = ref.id.components(separatedBy: AppDatabase.rowKeySeparator)
                guard parts.count == 2 else {
                    throw SyncError.undecodablePayload(
                        kind: SyncKind.rowUpsert, detail: "exercises id is not user␟exercise"
                    )
                }
                guard let row = try database.exercise(id: parts[1]) else { return false }
                try await remote.upsertRow(
                    ExerciseWire(row, userId: parts[0]),
                    table: "exercises", conflict: "id", nulls: ref.nulls
                )
                return true
            }
        )
        return out
    }()
}

public extension AppDatabase {
    /// One catalogue row by id. The push needs it; so does the routine builder.
    ///
    /// The whole-catalogue read is `exercises()` (`AppDatabase.swift`), which
    /// already returns every row name-sorted. Note it is NOT
    /// `exerciseCatalogStream`: that one hides a movement until a set has been
    /// logged against it (`HAVING COUNT(s.id) > 0`), which is right for a
    /// history screen, wrong for a picker, and actively misleading on the
    /// screen that has just imported sixty rows nobody has trained yet.
    func exercise(id: String) throws -> Exercise? {
        try writer.read { db in try Exercise.filter(Column("id") == id).fetchOne(db) }
    }
}
