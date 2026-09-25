import Foundation
import GRDB
import OnyxCore

/// The deck order, kept — so a movement dragged up mid-session is still there
/// next week.
///
/// ── WHAT WAS ALREADY TRUE, AND WHAT WAS MISSING ─────────────────────────────
/// `LoggerModel.moveExercise` already wrote the new order to
/// `workout_sets.exercise_order` on every ticked row, and `SessionAnalysis`
/// already read it back — so a reorder survived into the session REPORT on both
/// clients. It did not survive into the next session, because the next
/// session's deck was built from a compiled constant (a `routines` row since
/// W2), which had never heard of it.
///
/// The web solved this in `save.ts`: every commit upserts `routine_templates`,
/// whose payload carries an `order` per exercise, and `templateDraft.ts` reads
/// the deck straight off it. The table is already mirrored to the device
/// (`RoutineTemplateRow`), already pulled, already push-wired through
/// `SyncKind.rowUpsert`, and `SessionHistoryStore.seedTemplate` already hands
/// it to the seed builder. Two things were missing and both are here: the phone
/// never WROTE the row, and `SessionSeedBuilder` decoded `order` and ignored it.
///
/// ── WHY THIS PATCHES JSON RATHER THAN REBUILDING THE PAYLOAD ────────────────
/// `SeedTemplate` — the phone's view of the payload — decodes a strict subset
/// of what the web stores: no `kind`, no `distanceKm`/`durationSec`/`inclinePct`
/// for a cardio block, no `side`/`pairId` for a unilateral pair, no `note`.
/// Re-deriving the whole payload from the phone's own sets and writing it back
/// would therefore DELETE the treadmill block and flatten every L/R pair the
/// web put there, on the next workout finished on the phone — a data loss with
/// no error and no symptom until the following week's deck came up wrong.
///
/// So a template that already exists is edited in place, as JSON, by name:
/// every key this file does not know about is copied through untouched because
/// it is never decoded in the first place. Only when there is no row at all is
/// one minted, and then from the session, which is the same thing
/// `payloadToTemplate` does on the web.
enum RoutineOrder {

    /// `routine_templates.payload`, as the web's `RoutineTemplate` version 1.
    static let version = 1

    /// Write this session's deck order into the day's routine template.
    ///
    /// Runs inside the caller's transaction — `closeSession`'s — for the same
    /// reason the PR ledger does: a session that is finished locally and whose
    /// order did not persist is a reorder that silently did not happen.
    ///
    /// Ghosted rows are skipped, matching `payloadToTemplate`. A ghost is a
    /// deliberate record of work NOT done, and the template is what you intend
    /// to do next time.
    ///
    /// ── AND THE LOADS NOW, NOT ONLY THE ORDER (Precision A6, Q9) ────────────
    /// An unticked set is never stored, so a session that did two of four
    /// working sets holds two rows. The template is the ROUTINE's memory and it
    /// must not learn "two" from that: the patch merges the logged rows into
    /// the stored ones by set index and keeps every planned row past them at
    /// its last known load — see `merge`.
    static func save(_ db: Database, session: WorkoutSession) throws {
        guard let dayKey = session.dayKey else { return }
        let rows = try WorkoutSet
            .filter(Column("session_id") == session.id)
            .order(Column("fold_order"), Column("set_index"))
            .fetchAll(db)
            .filter { $0.setType != "ghost" }
        guard !rows.isEmpty else { return }

        // `exercise_order` is the number the deck emits and the number both
        // clients sort by. A row that predates the column falls back to the
        // order it was logged in, which is the deck order at the time.
        var orderByName: [String: Int] = [:]
        var names: [String] = []
        let byId = try Dictionary(
            Exercise.filter(rows.map(\.exerciseId).contains(Column("id"))).fetchAll(db)
                .map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in rows {
            guard let name = byId[row.exerciseId] else { continue }
            if orderByName[name] == nil {
                orderByName[name] = row.exerciseOrder ?? orderByName.count
                names.append(name)
            }
        }
        guard !names.isEmpty else { return }
        names.sort { (orderByName[$0] ?? 0, $0) < (orderByName[$1] ?? 0, $1) }

        let existing = try RoutineTemplateRow.fetchOne(
            db, key: ["user_id": session.userId, "day_key": dayKey]
        )
        var logged: [String: [WorkoutSet]] = [:]
        for row in rows {
            guard let name = byId[row.exerciseId] else { continue }
            logged[canon(name), default: []].append(row)
        }
        let payload: String
        if let existing, let patched = patch(existing.payload.raw, order: names, sets: logged) {
            payload = patched
        } else {
            guard let minted = mint(rows, names: names, byId: byId) else { return }
            payload = minted
        }
        guard payload != existing?.payload.raw else { return }

        let row = RoutineTemplateRow(
            userId: session.userId,
            dayKey: dayKey,
            payload: JSONText(raw: payload),
            sourceSessionId: session.id,
            // A row this device invented must never drag the delta cursor
            // forward — see `AppDatabase.localWriteTimestamp`. The server
            // stamps the real `updated_at` when the push lands.
            updatedAt: AppDatabase.localWriteTimestamp
        )
        try row.save(db)
        try AppDatabase.enqueueRowUpsert(
            table: RoutineTemplateRow.databaseTableName,
            id: AppDatabase.rowID([session.userId, dayKey]),
            in: db
        )
    }

    // MARK: - The payload

    /// Reorder an existing payload's exercises by name, preserving every other
    /// key — including the ones this target has no type for.
    ///
    /// A name the template does not carry is IGNORED rather than inserted: the
    /// template's own membership is the web's to decide (it is what carries the
    /// cardio opener and the sets), and a session logged with an extra movement
    /// should move what is there, not rewrite the routine. Names the session did
    /// not touch keep their relative position at the end.
    ///
    /// Returns nil when the payload is not a template this can reorder, which
    /// leaves the row alone — a garbled payload is treated as absent, never
    /// thrown, the same rule `parseTemplate` follows on the web.
    ///
    /// `sets` — the session's own rows by canonical name — are merged into the
    /// matching entry's `sets` (`merge`). Empty leaves every entry's sets as
    /// they were, which is all this did before Precision A6.
    static func patch(_ raw: String, order names: [String], sets logged: [String: [WorkoutSet]] = [:]) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
            var exercises = object["exercises"] as? [[String: Any]],
            !exercises.isEmpty
        else { return nil }

        var rank: [String: Int] = [:]
        for (i, name) in names.enumerated() { rank[canon(name)] = i }
        // A movement the session did not log sorts after every one it did, in
        // the order the template already had it. `enumerated` is what keeps
        // that stable: `sorted(by:)` is not a stable sort in Swift.
        let ranked = exercises.enumerated().map { index, exercise -> (Int, Int, [String: Any]) in
            let name = (exercise["name"] as? String).map(canon) ?? ""
            return (rank[name] ?? (names.count + index), index, exercise)
        }
        exercises = ranked
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
            .enumerated()
            .map { position, entry in
                var exercise = entry.2
                // Dense from 0 regardless of what the deck emitted — a movement
                // removed from the session leaves a hole in `exercise_order`,
                // and the web re-indexes for exactly this reason.
                exercise["order"] = position
                if let rows = (exercise["name"] as? String).flatMap({ logged[canon($0)] }),
                   let stored = exercise["sets"] as? [[String: Any]] {
                    exercise["sets"] = merge(stored, rows)
                }
                return exercise
            }

        var next = object
        next["exercises"] = exercises
        next["version"] = object["version"] ?? version
        return canonicalJSON(next)
    }

    /// A session's rows folded into a template entry's sets.
    ///
    /// Warm-ups against warm-ups and working rows against working rows, each
    /// by index: logged row `i` rewrites stored set `i`'s load, reps, type,
    /// rating and side; a stored set with no logged row at its index — an
    /// UNTICKED set — stays exactly as it was, at its last known load; a logged
    /// row past the stored count is appended. So the entry can grow and can
    /// never shrink, and every key the phone does not model survives on the
    /// sets it touches.
    ///
    /// A bout is left alone (its sets carry duration, not load — the entry is
    /// the web's shape and nothing here can write it back correctly).
    static func merge(_ stored: [[String: Any]], _ logged: [WorkoutSet]) -> [[String: Any]] {
        guard !logged.contains(where: { $0.durationSec != nil }) else { return stored }
        func isWarmup(_ set: [String: Any]) -> Bool { set["setType"] as? String == "warmup" }
        func fold(_ sets: [[String: Any]], _ rows: [WorkoutSet]) -> [[String: Any]] {
            var out = sets
            for (i, row) in rows.enumerated() {
                var set = i < out.count ? out[i] : [:]
                set["weightKg"] = row.weightKg
                set["reps"] = row.reps
                // The web's rules, as `mint` writes them: 'normal' is the
                // absence of a modifier, and a warm-up is never rated.
                set["setType"] = ["warmup", "failure", "dropset"].contains(row.setType) ? row.setType : nil
                if let rpe = row.rpe, rpe.isFinite, row.setType != "warmup" { set["rpe"] = rpe } else { set["rpe"] = nil }
                if let pairId = row.pairId, !pairId.isEmpty, let side = row.side {
                    set["side"] = side.hasPrefix("l") || side.hasPrefix("L") ? "L" : "R"
                    set["pairId"] = pairId
                } else {
                    set["side"] = nil
                    set["pairId"] = nil
                }
                if i < out.count { out[i] = set } else { out.append(set) }
            }
            return out
        }
        return fold(stored.filter(isWarmup), logged.filter { $0.setType == "warmup" })
            + fold(stored.filter { !isWarmup($0) }, logged.filter { $0.setType != "warmup" })
    }

    /// The first template for a day, from the session that just finished — the
    /// Swift half of `payloadToTemplate`, minus the cardio splice.
    ///
    /// `ponytail:` strength only. A cardio block logged inside the deck lives in
    /// `cardio_logs` on this device and carries `deckOrder` nowhere the phone
    /// reads, so minting cannot place it. The web mints the richer payload on
    /// its next save and `patch` preserves it from then on; the case this misses
    /// is a day whose FIRST ever commit was on the phone AND which opens with
    /// cardio. Splice it here when the phone learns to log a cardio block into
    /// the deck.
    static func mint(
        _ rows: [WorkoutSet], names: [String], byId: [String: String]
    ) -> String? {
        var sets: [String: [[String: Any]]] = [:]
        for row in rows {
            guard let name = byId[row.exerciseId] else { continue }
            var set: [String: Any] = ["weightKg": row.weightKg, "reps": row.reps]
            // 'normal' is the absence of a modifier, and a warm-up is never
            // rated — both rules are the web's, and a template that disagreed
            // would seed a different deck on each client.
            if ["warmup", "failure", "dropset"].contains(row.setType) { set["setType"] = row.setType }
            if let rpe = row.rpe, rpe.isFinite, row.setType != "warmup" { set["rpe"] = rpe }
            if let pairId = row.pairId, !pairId.isEmpty, let side = row.side,
               side == "L" || side == "R" || side == "left" || side == "right" {
                set["side"] = side.hasPrefix("l") || side.hasPrefix("L") ? "L" : "R"
                set["pairId"] = pairId
            }
            sets[name, default: []].append(set)
        }
        let exercises: [[String: Any]] = names.enumerated().compactMap { position, name in
            guard let rows = sets[name], !rows.isEmpty else { return nil }
            return ["name": name, "order": position, "sets": rows]
        }
        guard !exercises.isEmpty else { return nil }
        return canonicalJSON(["version": version, "exercises": exercises])
    }

    /// Sorted keys, so the same deck always produces the same bytes — which is
    /// what lets the `payload != existing` check above skip a pointless upload.
    /// `JSONText` makes the same promise about what comes off the wire.
    private static func canonicalJSON(_ object: [String: Any]) -> String? {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
            )
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The same key `SessionSeedBuilder` matches template entries by, so a
    /// template written under one spelling still finds its movement.
    private static func canon(_ name: String) -> String {
        ExerciseAliases.canonicalName(name).lowercased()
    }
}
