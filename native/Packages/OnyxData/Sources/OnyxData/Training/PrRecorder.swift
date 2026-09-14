import Foundation
import GRDB
import OnyxCore

/// The PR ledger, written by the phone.
///
/// ── WHAT THIS CLOSES ────────────────────────────────────────────────────────
/// `PrEngine` has been fully ported since Track D, and `SessionAnalysis` has
/// replayed it at READ time since Wave 7 — so the app could always *show* you a
/// record. It just never wrote one down. `personal_records` was pull-only: a
/// session logged on the phone produced no ledger rows at all, and the desktop,
/// the trophy chips and every "since when" answer stayed on whatever the web
/// last recorded. Finish a workout on the phone and the record simply did not
/// exist anywhere.
///
/// This is `save.ts`'s PR block, translated. Same engine, same inputs, same
/// conflict target — because the two clients write the SAME three columns of
/// the same table and any difference between them is a record filed where the
/// other side will never look for it.
///
/// ── THE THREE THINGS THAT MAKE IT THE SAME FUNCTION ─────────────────────────
/// 1. **Baselines exclude this session.** `save.ts` builds them before the sets
///    are inserted, so "every set for these exercises" is naturally the prior
///    history. Here the sets are already in the store — `closeSession` runs
///    after the last append — so the exclusion has to be explicit. Without it
///    every set is measured against itself and nothing is ever a record.
/// 2. **`exercise_key` is a canonical display NAME, never an id.** The web
///    learned this the hard way: a set logged under an alias filed its record
///    under a key nothing would match and the trophy rendered with no chips.
///    The engine is keyed on `exercise_id` throughout (as `save.ts` keys it)
///    and the name is applied only at the last step, where the row is built.
/// 3. **`prFloorFor`, not the raw record book.** Four months of Notion-era
///    sessions have no sets, so a return to an old load would read as a new
///    record. The floor is a bar the logged rows cannot account for, folded in
///    as one more contender — see `PrTruth`.
public enum PrRecorder {

    /// Detect and file one session's records, inside the caller's transaction.
    ///
    /// Returns the rows written, which is the count the caller can report. The
    /// write is idempotent: the natural key `(user_id, exercise_key, axis)` is
    /// what both clients upsert on, and re-running over the same session
    /// recomputes the same baselines and lands the same values.
    /// What one `record` pass did. `written` is the ledger rows upserted;
    /// `prCount` is the session's own `pr_count` — distinct axis-PRs across
    /// every exercise, which is a DIFFERENT number and the one the session row
    /// stores.
    public struct Result: Sendable, Equatable {
        public var written: Int
        public var prCount: Int
        public static let none = Result(written: 0, prCount: 0)
    }

    @discardableResult
    public static func record(
        _ db: Database, sessionId: String, userId: String, dayKey: String?, date: String
    ) throws -> Result {
        let sets = try WorkoutSet
            .filter(Column("session_id") == sessionId)
            .order(Column("set_index"), Column("rowid"))
            .fetchAll(db)
        guard !sets.isEmpty else { return .none }

        let name = try nameResolver(db)
        let exerciseIds = Set(sets.map(\.exerciseId))
        let program = try programOwning(db, userId: userId, date: date)

        let baselines = try baselines(
            db, exerciseIds: exerciseIds, excluding: sessionId, dayKey: dayKey, program: program, name: name
        )
        let candidates = Self.candidates(sets, dayKey: dayKey, date: date, program: program, name: name)
        let result = PrEngine.detectSessionPrs(candidates, baselines)
        var written = 0
        for exercise in PrEngine.recordSets(candidates, result) {
            let key = name(exercise.key)
            for record in exercise.records {
                var row = PersonalRecordRow(
                    userId: userId,
                    exerciseKey: key,
                    axis: record.axis.rawValue,
                    // Two decimals, as `save.ts` rounds it. A ledger value that
                    // disagrees with the other client's in the fifteenth place
                    // is a diff nobody can act on.
                    value: (record.set.value * 100).rounded() / 100,
                    // EVERY axis carries the winning set's load and reps, volume
                    // and e1RM included. They stored null until 2026-08-03, and
                    // the session ledger — which matches a record to the set
                    // that earned it by (weight, reps) — hung the chip on
                    // whichever set happened to come last.
                    reps: Int(record.set.reps),
                    weightKg: record.set.weightKg,
                    sessionId: sessionId,
                    achievedOn: date,
                    // The delta cursor is the server's to move.
                    updatedAt: AppDatabase.localWriteTimestamp
                )
                try carryFloor(db, into: &row)
                try row.save(db)
                try AppDatabase.enqueueRowUpsert(
                    table: PersonalRecordRow.databaseTableName,
                    id: AppDatabase.rowID([userId, key, record.axis.rawValue]),
                    in: db
                )
                written += 1
            }
        }
        return Result(written: written, prCount: result.prCount)
    }

    /// One session's sets, as the engine takes them.
    ///
    /// Keyed on `exercise_id` — as `save.ts` keys it — with the canonical name
    /// applied only where a name is genuinely wanted. Two callers share it so
    /// the ledger written on close and the count stored on the session row can
    /// never be built from differently-shaped inputs.
    static func candidates(
        _ sets: [WorkoutSet], dayKey: String?, date: String, program: Program, name: (String) -> String
    ) -> [PrCandidateSet] {
        sets.enumerated().map { i, s in
            let canonical = name(s.exerciseId)
            return PrCandidateSet(
                key: s.exerciseId, weightKg: s.weightKg, reps: Double(s.reps), setType: s.setType,
                timed: TimedExercise.isTimed(canonical),
                repFloor: Ceilings.repWindow(for: canonical, dayKey: dayKey, program: program)?.floor,
                // ── THE DOMAIN SPELLING, NOT THE LOCAL ONE ──────────────────
                // `workout_sets.side` is `left`/`right` on this device
                // (`SyncTranslation.localSide`) and `L`/`R` on the wire, and
                // every OnyxCore rule that folds a pair tests the one-letter
                // form — `PrEngine.volumeCredits` included. Handed the local
                // spelling it recognised no pair at all, so a unilateral set
                // was scored for the VOLUME axis twice, once per side at its
                // own tonnage, against a baseline built the same broken way.
                // `save.ts` gets `L`/`R` for free because it reads the server's
                // column, which is why the two clients could disagree about a
                // split set's volume record and nothing here ever said so.
                pairId: s.pairId, side: SyncTranslation.domainSide(s.side), date: date,
                exerciseName: canonical, setNumber: s.setIndex > 0 ? s.setIndex : i + 1
            )
        }
    }

    /// `workout_sessions.pr_count` for a set of rows, WITHOUT writing anything.
    ///
    /// The session row stores a count and the ledger stores the records, and
    /// they are two different numbers over the same detection — so this runs
    /// the detection and throws the ledger half away. An edit needs the count
    /// recomputed on every save; it must not re-file a record for an exercise
    /// nobody touched, which is what calling `record` again would do.
    static func prCount(
        _ db: Database, sets: [WorkoutSet], dayKey: String?, date: String
    ) throws -> Int {
        guard let sessionId = sets.first?.sessionId else { return 0 }
        let name = try nameResolver(db)
        let userId = try WorkoutSession.fetchOne(db, key: sessionId)?.userId ?? ""
        let program = try programOwning(db, userId: userId, date: date)
        let baselines = try baselines(
            db, exerciseIds: Set(sets.map(\.exerciseId)), excluding: sessionId,
            dayKey: dayKey, program: program, name: name
        )
        return PrEngine.detectSessionPrs(
            candidates(sets, dayKey: dayKey, date: date, program: program, name: name), baselines
        ).prCount
    }

    /// The bar every candidate is measured against.
    ///
    /// ── ONE BUILDER, TWO CALLERS, AND THAT IS THE POINT ─────────────────────
    /// `record` uses it at close to write the ledger; the live logger uses it at
    /// `attach` to light the trophy mid-set. A live badge computed from
    /// different baselines than the ledger is a badge that fires on a set the
    /// close then refuses to file — gold that means "this has never been beaten"
    /// everywhere else in the app, appearing on a set that has.
    ///
    /// `excluding` is the session being judged. `save.ts` gets the exclusion for
    /// free (it builds baselines before inserting), and both callers here have
    /// the sets already in the store, so it has to be explicit: without it every
    /// set is measured against itself and nothing is ever a record.
    /// ── `before` IS FOR A SESSION THAT IS ALREADY HISTORY ───────────────────
    /// `save.ts` never needed it: it builds the bar at close, when there is by
    /// definition nothing after. Re-opening a three-week-old session to correct
    /// it (§U4.5) is the first caller for which "every other session" and
    /// "every EARLIER session" are different sets — measured against the whole
    /// ledger an August set is beaten by a September one and the deck shows no
    /// records at all, on a session whose own summary page shows three. The
    /// date lives on `workout_sessions`, so the bound is a subquery; nil keeps
    /// the old behaviour exactly, which is what the live logger wants.
    static func baselines(
        _ db: Database, exerciseIds: Set<String>, excluding sessionId: String?,
        before: String? = nil,
        dayKey: String?, program: Program, name: @escaping (String) -> String,
        standingRecordFloors: Bool = false
    ) throws -> PrBaselines {
        guard !exerciseIds.isEmpty else { return .empty }
        // Off for every rebuild path; the live deck is the one caller that
        // passes true. `floors`' header says why.
        let floors = try floors(db, standingRecords: standingRecordFloors)
        // ── EVERY ID THAT IS THIS MOVEMENT, NOT JUST THE ONE IN HAND ────────
        //
        // This filtered on `exerciseIds` alone — the ids the session's OWN rows
        // carry. A lift logged on both clients has its history under two of
        // them (a catalogue uuid from the web, a `helix5-` slug from a deck the
        // payload could not resolve; `nameResolver`'s header calls that
        // routine), and the bar was then built from whichever half this session
        // happened to use. Half a history is a low bar — and an id appearing
        // for the first time has NO history, which is worse than a low bar:
        // `detectSetPrs` awards nothing at all against an empty index ("a delta
        // against nothing is not a delta"), so every axis of that movement goes
        // quietly unrecorded for the whole session.
        //
        // `attach(editing:)` hit exactly this and fixed it one layer up by
        // taking the UNION of the deck's ids and the session's rows. The CLOSE
        // path never got the same treatment, and 2026-09-11 is what that cost:
        // five records detected by a replay over the full ledger, ONE filed by
        // the phone at close.
        //
        // So the rows are gathered under every id that resolves to the same
        // canonical NAME, and each is re-keyed to the id this session will be
        // judged under. Two consequences worth being explicit about:
        //
        //   · The FILING key does not move. `record` still writes
        //     `personal_records` under `name(exercise.key)` exactly as before —
        //     this widens the BAR, not the ledger, so it is not the F16
        //     decision about keying `record` on the name.
        //   · It can only ever RAISE a bar or fill an empty one, never lower
        //     one. So it removes false positives and cannot invent a record,
        //     which is the direction a change to detection has to run in.
        //
        // It also makes `record` agree with `replay`, which has always resolved
        // ids by name — the asymmetry that let a close file a record a later
        // replay would silently retract.
        let keyByName = Dictionary(
            exerciseIds.map { (name($0), $0) }, uniquingKeysWith: { first, _ in first }
        )
        let siblings = try String.fetchAll(db, sql: "SELECT DISTINCT exercise_id FROM workout_sets")
            .filter { keyByName[name($0)] != nil }
        let lookup = Set(exerciseIds).union(siblings)

        var query = WorkoutSet.filter(lookup.contains(Column("exercise_id")))
        if let sessionId { query = query.filter(Column("session_id") != sessionId) }
        if let before {
            query = query.filter(
                sql: "session_id IN (SELECT id FROM workout_sessions WHERE date < ?)",
                arguments: [before]
            )
        }
        let prior = try query.fetchAll(db)
        return PrEngine.buildBaselines(
            prior.map {
                BaselineSetRow(
                    // Re-keyed to the id the CANDIDATES carry — see above.
                    key: keyByName[name($0.exerciseId)] ?? $0.exerciseId,
                    weightKg: $0.weightKg, reps: Double($0.reps),
                    est1rm: $0.est1rmKg, setType: $0.setType,
                    repFloor: Ceilings.repWindow(for: name($0.exerciseId), dayKey: dayKey, program: program)?.floor,
                    pairId: $0.pairId, side: SyncTranslation.domainSide($0.side)
                )
            },
            isTimed: { TimedExercise.isTimed(name($0)) },
            floorFor: { floors[name($0)] }
        )
    }

    /// The asserted floors — every `personal_records` row with NO session,
    /// folded per exercise key (W2; `PrTruth.swift` says why). Read once per
    /// baseline build: the table is a few dozen rows.
    ///
    /// ── `standingRecords` IS THE LIVE DECK'S TIER, AND ONLY ITS ─────────────
    /// A session-backed row's own `value` is normally NOT a floor: the set that
    /// achieved it is in `workout_sets`, so the bar already stands there and
    /// folding it in again would say the same thing twice.
    ///
    /// That holds while this device can SEE the set. It cannot always: a
    /// movement's history is filed under every id it has ever been logged
    /// under, `baselines` gathers those ids by resolving each to a canonical
    /// NAME, and `nameResolver` can only resolve an id the local `exercises`
    /// table claims. An id whose catalogue row has not been pulled yet resolves
    /// to itself, matches no deck name, and its rows drop silently out of the
    /// bar. The bar is then built from HALF a history — which is not an empty
    /// index that awards nothing, but a LOW one that awards a record the full
    /// history would have refused. 2026-09-14: a 47.5 × 13 seated leg curl lit
    /// as 617.5 kg "was 550" mid-session and was gone after the next launch,
    /// because the catalogue row landed in between and the replay could then
    /// see what the live bar could not.
    ///
    /// The ledger already knew. `personal_records` holds the standing record
    /// for the movement whether or not this device holds the set behind it, so
    /// reading it as a floor makes the deck's bar agree with the ledger by
    /// construction rather than by both happening to read the same rows.
    ///
    /// ── WHY IT IS OFF FOR `record`, `replay` AND `recomputeAll` ─────────────
    /// Those three REBUILD the ledger, and `recomputeAll` does it by upserting
    /// session by session over a table that still holds the previous answer. A
    /// floor taken from the standing record would measure session 1 against the
    /// all-time best, award nothing, and leave the stale rows exactly where
    /// they were — a recompute that silently does nothing. They keep the
    /// original two tiers; the flag defaults off so they get it by saying
    /// nothing.
    ///
    /// It can only ever RAISE the live bar, so it removes false trophies and
    /// cannot invent one — the direction `baselines`' own header requires of
    /// any change to detection. The deck can now light FEWER records than the
    /// close path files, which is the trade being made on purpose: a trophy
    /// withheld is corrected by the summary one screen later, and a false one
    /// is a number the athlete has already believed.
    static func floors(_ db: Database, standingRecords: Bool = false) throws -> [String: PrFloor] {
        var out: [String: PrFloor] = [:]
        for row in try PersonalRecordRow.fetchAll(db) {
            // A floor is a session-less row's value, or the `floor_value` a
            // session's record carries from the floor row it replaced —
            // the natural key holds ONE row per axis, so a beaten floor
            // lives on inside the row that beat it (`carryFloor`).
            guard let axis = PrAxis(rawValue: row.axis) else { continue }
            let timed = TimedExercise.isTimed(row.exerciseKey)
            var floor = out[row.exerciseKey] ?? PrFloor()
            if let value = row.sessionId == nil ? row.value : row.floorValue {
                floor.absorb(axis: axis, value: value, timed: timed)
            }
            // `absorb` keeps whichever side is the better mark for the axis, so
            // this is a max (a min on a timed lift) and never a downgrade.
            if standingRecords, row.sessionId != nil {
                floor.absorb(axis: axis, value: row.value, timed: timed)
            }
            out[row.exerciseKey] = floor
        }
        return out
    }

    /// The floor the row about to be saved stands on: the value of the
    /// floor row it replaces, or the floor the previous record on this axis
    /// was already carrying. Nothing to carry when the axis has no row.
    private static func carryFloor(_ db: Database, into row: inout PersonalRecordRow) throws {
        guard let existing = try PersonalRecordRow
            .filter(Column("user_id") == row.userId && Column("exercise_key") == row.exerciseKey && Column("axis") == row.axis)
            .fetchOne(db)
        else { return }
        row.floorValue = existing.sessionId == nil ? existing.value : existing.floorValue
    }

    /// The deck the session's date belongs to, for the rep window that gates
    /// the e1RM axis. An account with no routines gets an empty program and
    /// no gate — which is what "no prescription" means.
    static func programOwning(_ db: Database, userId: String, date: String) throws -> Program {
        let ctx = try AppDatabase.scheduleContext(db, userId: userId)
        return Schedule.programForContext(ctx, date).program
    }

    /// Replay every session this device holds, oldest first.
    ///
    /// The one-off for sessions logged on the phone before this existed, and
    /// the repair for any session whose ledger write was lost. Chronological on
    /// purpose: a record is only a record against what came before it, so
    /// replaying out of order would file the wrong set.
    ///
    /// Idempotent — every write is an upsert on the natural key — so it is safe
    /// to run whenever, and safe to run twice.
    @discardableResult
    public static func recomputeAll(_ db: Database, userId: String) throws -> Int {
        let sessions = try WorkoutSession
            .order(Column("date"), Column("started_at"), Column("rowid"))
            .fetchAll(db)
        var total = 0
        for session in sessions {
            total += try record(
                db, sessionId: session.id, userId: userId, dayKey: session.dayKey, date: session.date
            ).written
        }
        return total
    }

    /// Rebuild ONE exercise's ledger from scratch, chronologically.
    ///
    /// ── WHY THE RECORDER ALONE CANNOT RETRACT ───────────────────────────────
    /// `record` upserts. That is exactly right for finishing a workout — a
    /// record is only ever beaten — and exactly wrong the moment a set can be
    /// LOWERED after the fact. Correct a mistyped 100 kg to 60 and the 100 kg
    /// row is still the best-ever bench, filed against a set that no longer
    /// exists, and no amount of re-running `record` will ever take it out.
    ///
    /// So the ledger for this exercise is deleted and replayed: every session
    /// this device holds, oldest first, each judged only against what came
    /// BEFORE it. That is `backfill-prs.mjs`'s rule, and it is the only one
    /// that produces the same answer whichever direction the edit went.
    ///
    /// ── AND WHY IT IS KEYED ON THE NAME, NOT THE ID ─────────────────────────
    /// `record` keys the engine on `exercise_id` (as `save.ts` does) and applies
    /// the name at the last step. Here the CALLER has a ledger key — a canonical
    /// display name — and every id that resolves to it is the same movement as
    /// far as `personal_records` is concerned. Keying on the name is what makes
    /// a lift logged on the web under a catalogue uuid and on the phone under a
    /// `helix5-` slug replay as one history rather than two.
    ///
    /// ── WHICH MEANS THE TWO CAN DISAGREE, AND `record` IS THE NARROW ONE ────
    /// A lift logged on both clients has its history under two `exercise_id`s
    /// in this table — `nameResolver`'s own header calls that routine, not
    /// rare. `record` builds its baseline from ONE of them, so closing a phone
    /// session can file a record the full history would have refused; a replay
    /// of that key then quietly retracts it. The narrow side is `record`, and
    /// widening it moves stored records for every lift with an alias, which is
    /// a recompute and a founder decision (F16, decision 12) rather than a
    /// side effect of an edit. Filed, not fixed here.
    ///
    /// ── THE ONE THING THAT MUST NOT BE FORGOTTEN ────────────────────────────
    /// An axis that had a row before and has none after — every set that ever
    /// reached the floor is now deleted — needs the SERVER told. An upsert
    /// cannot say "there is no record here any more"; only a delete can, and
    /// the local row going quiet would otherwise leave the web showing a
    /// record for a lift with no qualifying set left in the history.
    ///
    /// Returns the ledger rows written.
    @discardableResult
    public static func replay(
        _ db: Database, userId: String, exerciseKey: String
    ) throws -> Int {
        let name = try nameResolver(db)
        let everySet = try WorkoutSet.fetchAll(db)
        let ids = Set(everySet.map(\.exerciseId).filter { name($0) == exerciseKey })
        guard !ids.isEmpty else {
            // Every set for this lift is gone. The ledger goes with it.
            try retract(db, userId: userId, exerciseKey: exerciseKey)
            return 0
        }

        // ── FINISHED SESSIONS ONLY ──────────────────────────────────────────
        // `record` has only ever run at close, so the ledger has only ever
        // held closed sessions' records. A replay that walked the live one too
        // would file — and push — a record for a set that is still being
        // logged; void that set a minute later and nothing re-runs the replay,
        // because `record` at close only ever raises. The result is a standing
        // record for a set that no longer exists, which is the exact failure
        // this function was written to prevent, arriving through another door.
        let sessions = try WorkoutSession
            .filter(Column("ended_at") != nil)
            .order(Column("date"), Column("started_at"), Column("rowid"))
            .fetchAll(db)
        var bySession: [String: [WorkoutSet]] = [:]
        for set in everySet where ids.contains(set.exerciseId) {
            bySession[set.sessionId, default: []].append(set)
        }

        /// Every set judged so far — the baseline the NEXT session is measured
        /// against. `record` gets this for free by excluding one session from a
        /// whole-table read; a replay has to accumulate it, because a session in
        /// the middle of the history must not be judged against its own future.
        var seen: [BaselineSetRow] = []
        var written = 0
        let timed = TimedExercise.isTimed(exerciseKey)
        // Read BEFORE the retract below: the floor rows live in the same
        // table, and `retract` leaves them alone precisely so this can.
        let floor = try floors(db)[exerciseKey]
        let ctx = try AppDatabase.scheduleContext(db, userId: userId)

        // Clear the slate — locally AND on the wire. Every axis is queued for
        // deletion up front; each one the replay wins back drops its own
        // pending delete on the way in (`enqueueRowUpsert` removes it), so what
        // survives in the queue is exactly the axes that no longer have a
        // qualifying set. There is no third state to reconcile afterwards.
        try retract(db, userId: userId, exerciseKey: exerciseKey)

        for session in sessions {
            guard let rows = bySession[session.id]?
                .sorted(by: { ($0.setIndex, $0.foldOrder) < ($1.setIndex, $1.foldOrder) }),
                  !rows.isEmpty
            else { continue }

            // The rep window is resolved per SESSION, because it depends on the
            // day key — the same lift has a different floor on a leg day and an
            // upper day. `Ceilings.repWindow`'s phase default is untouched, so
            // this gates the e1RM axis exactly as `record` does.
            let repFloor = Ceilings.repWindow(
                for: exerciseKey, dayKey: session.dayKey, program: Schedule.programForContext(ctx, session.date).program
            )?.floor
            let baselines = PrEngine.buildBaselines(
                seen, isTimed: { _ in timed }, floorFor: { _ in floor }
            )
            let candidates = rows.enumerated().map { i, s in
                PrCandidateSet(
                    key: exerciseKey, weightKg: s.weightKg, reps: Double(s.reps), setType: s.setType,
                    timed: timed, repFloor: repFloor,
                    // The domain spelling, exactly as `candidates` does it —
                    // `replay` is `record`'s twin and a pair it failed to
                    // collapse would retract a record `record` filed correctly.
                    pairId: s.pairId, side: SyncTranslation.domainSide(s.side), date: session.date,
                    exerciseName: exerciseKey, setNumber: s.setIndex > 0 ? s.setIndex : i + 1
                )
            }
            let result = PrEngine.detectSessionPrs(candidates, baselines)
            for exercise in PrEngine.recordSets(candidates, result) {
                for record in exercise.records {
                    var row = PersonalRecordRow(
                        userId: userId,
                        exerciseKey: exerciseKey,
                        axis: record.axis.rawValue,
                        value: (record.set.value * 100).rounded() / 100,
                        reps: Int(record.set.reps),
                        weightKg: record.set.weightKg,
                        sessionId: session.id,
                        achievedOn: session.date,
                        updatedAt: AppDatabase.localWriteTimestamp
                    )
                    try carryFloor(db, into: &row)
                    try row.save(db)
                    try AppDatabase.enqueueRowUpsert(
                        table: PersonalRecordRow.databaseTableName,
                        id: AppDatabase.rowID([userId, exerciseKey, record.axis.rawValue]),
                        in: db
                    )
                    written += 1
                }
            }
            seen.append(contentsOf: rows.map {
                BaselineSetRow(
                    key: exerciseKey, weightKg: $0.weightKg, reps: Double($0.reps),
                    est1rm: $0.est1rmKg, setType: $0.setType, repFloor: repFloor,
                    pairId: $0.pairId, side: SyncTranslation.domainSide($0.side)
                )
            })
        }

        return written
    }

    /// Delete every ledger row for one key, locally and on the wire.
    ///
    /// An upsert cannot say "there is no record here any more" — only a delete
    /// can, and a local row going quiet would leave the web showing a record
    /// for a lift with no qualifying set left in the history.
    ///
    /// Rows with NO session are the asserted floors (W2): they were never
    /// written by a set and no replay can win them back, so they stay — and
    /// the replay reads them first (`floors`) as the bar every session is
    /// judged against.
    private static func retract(
        _ db: Database, userId: String, exerciseKey: String
    ) throws {
        let rows = try PersonalRecordRow
            .filter(Column("user_id") == userId && Column("exercise_key") == exerciseKey && Column("session_id") != nil)
            .fetchAll(db)
        for row in rows {
            // A record that stood on a floor hands the axis BACK to the
            // floor rather than emptying it: the bar the book asserted is
            // still true when the set that beat it is gone. The set's own
            // load and reps go with the set.
            if let floor = row.floorValue {
                var back = row
                back.value = floor
                back.sessionId = nil
                back.reps = nil
                back.weightKg = nil
                back.floorValue = nil
                back.updatedAt = AppDatabase.localWriteTimestamp
                try back.save(db)
                try AppDatabase.enqueueRowUpsert(
                    table: PersonalRecordRow.databaseTableName,
                    id: AppDatabase.rowID([userId, exerciseKey, row.axis]),
                    nulls: ["session_id", "reps", "weight_kg", "floor_value"],
                    in: db
                )
                continue
            }
            try row.delete(db)
            try AppDatabase.enqueueRowDelete(
                table: PersonalRecordRow.databaseTableName,
                key: ["user_id": userId, "exercise_key": exerciseKey, "axis": row.axis],
                in: db
            )
        }
    }

    /// `exercise_id` → the canonical display name the ledger is keyed on.
    ///
    /// Two sources, because a set can carry either kind of id. A set pulled
    /// from the server carries the catalogue's uuid, which the local
    /// `exercises` table resolves. A set logged HERE and not yet synced carries
    /// `ExerciseSlug.id`'s slug, which no catalogue row claims until the push
    /// lands — `nameBySlug` is what stops those sets filing their records under
    /// a raw slug for the minutes in between.
    static func nameResolver(_ db: Database) throws -> (String) -> String {
        let exercises = try Exercise.fetchAll(db)
        let catalogue = Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let bySlug = ExerciseSlug.nameBySlug(exercises)
        var memo: [String: String] = [:]
        return { id in
            if let hit = memo[id] { return hit }
            let raw = catalogue[id] ?? bySlug[id] ?? id
            let canonical = ExerciseAliases.canonicalName(raw)
            memo[id] = canonical
            return canonical
        }
    }
}

extension AppDatabase {
    /// The live logger's baselines: the bar the deck's ticked sets are measured
    /// against, built by the same function that writes the ledger on close.
    ///
    /// `exerciseIds` are the deck's own ids (`ExerciseSlug.id`), which is what
    /// the logger writes into `workout_sets` and therefore what the close path
    /// will key on. A set logged on the WEB carries a catalogue uuid instead, so
    /// its history is not in this bar — `PrTruth.floor`, folded in by
    /// `buildBaselines`, is what keeps a return to an old load from reading as a
    /// record anyway. Matching `record` exactly is the requirement; being
    /// cleverer than it would light a trophy the close then refuses to file.
    public func livePrBaselines(
        exerciseIds: [String], excluding sessionId: String?, before: String? = nil, dayKey: String?,
        program: Program
    ) throws -> PrBaselines {
        try writer.read { db in
            let name = try PrRecorder.nameResolver(db)
            return try PrRecorder.baselines(
                db, exerciseIds: Set(exerciseIds), excluding: sessionId,
                before: before, dayKey: dayKey, program: program, name: name,
                // The ONE place this is on — see `PrRecorder.floors`. The deck
                // is the surface that shows a record the instant it happens,
                // with no chance to take it back before it is read.
                standingRecordFloors: true
            )
        }
    }

    /// Replay the PR ledger over every session this device holds.
    ///
    /// The one-off for sessions logged before the recorder existed, and the
    /// repair for any whose ledger write was lost. Idempotent, so the only cost
    /// of running it again is the time.
    @discardableResult
    public func recomputeAllPrs(userId: String) throws -> Int {
        try writer.write { db in try PrRecorder.recomputeAll(db, userId: userId) }
    }
}
