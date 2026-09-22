import Foundation
import GRDB
import OnyxCore

/// One logged set with the two things a set row does not carry itself: the
/// exercise's NAME and the session's DATE. Every history screen wants both.
///
/// ── WHY ONE ROW SHAPE FOR THREE SCREENS ─────────────────────────────────────
/// The session list, the session report and an exercise's history all read the
/// same ledger and differ only in the WHERE clause. Three row types would be
/// three ways to forget `set_type`, `side` and `pair_id` — the columns the PR
/// engine cannot do without (a baseline built without `set_type` summed
/// warm-ups into the bar; one built without `side`/`pair_id` judged a pair
/// against a per-side history). They are selected here, once, and carried by
/// every reader whether it needs them or not.
public struct HistorySetRow: Codable, FetchableRecord, Sendable, Equatable, Identifiable {
    public var id: String
    public var sessionId: String
    public var exerciseId: String
    /// The stored name; `ExerciseAliases.canonicalName` is the reader's job.
    /// Falls back to the id for a set whose exercise the catalogue never pulled.
    public var exerciseName: String
    public var setIndex: Int
    public var foldOrder: Int
    public var weightKg: Double
    public var reps: Int
    public var setType: String
    /// `left` / `right` as the local store spells it. See `lr`.
    public var side: String?
    public var pairId: String?
    /// Stored, and a stored 0 on an unloaded set is a legacy artefact — read it
    /// with `||`, never `??`. `PrEngine.buildBaselines` already does.
    public var est1rmKg: Double?
    public var rpe: Double?
    /// HOW THE SET WENT — `workout_sets.quality`, the `+`-joined grammar
    /// `SetTags.parseQuality` owns. Nil is a clean set: "the question was
    /// never asked" is the same value as "nothing to report", which is why the
    /// column is read and never defaulted.
    ///
    /// Selected since the weekly export needed it. Postgres has carried the
    /// column all along and `v14.setQuality` added it locally; the only thing
    /// between a logged "Cold" and the document was this SELECT.
    public var quality: String?
    /// The cardio axes — see `WorkoutSet.durationSec`. All three nil on a
    /// lifted set, which is what `SetFormat.cardio` reads as "not a cardio set".
    public var durationSec: Int?
    public var incline: Double?
    public var distanceKm: Double?
    /// Total ascent in metres — see `WorkoutSet.elevationM`. Selected because
    /// the Session Report's `DetailSet` is built from this row and nothing
    /// else; a column absent from `setSelect` is a column the ledger cannot
    /// draw, however faithfully the rest of the path carried it.
    public var elevationM: Double?
    /// The MOVEMENT's position in the session, dense from 0 — the column a
    /// reorder writes (`WorkoutSet.exerciseOrder`). Nil on a row logged before
    /// it existed, and on any row nobody has ever placed.
    ///
    /// It is selected here because the alternative is what §U4.5 shipped: a
    /// drag rewrote `exercise_order` on every set it moved, and every reader
    /// grouped the session by FIRST APPEARANCE in `fold_order` instead — so
    /// the reorder was written correctly, pushed correctly, and invisible on
    /// both clients. `SessionAnalysis.grouped` is the one place it is read.
    public var exerciseOrder: Int?
    /// MEASURED rest before this set, in seconds — `WorkoutSet.actualRestSec`.
    /// Nil is the normal case and means not measured.
    public var actualRestSec: Int?
    /// The session's logical day, ISO.
    public var date: String
    public var dayKey: String?

    public enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case exerciseId = "exercise_id"
        case exerciseName = "exercise_name"
        case setIndex = "set_index"
        case foldOrder = "fold_order"
        case weightKg = "weight_kg"
        case reps
        case setType = "set_type"
        case side
        case pairId = "pair_id"
        case est1rmKg = "est_1rm_kg"
        case rpe
        case quality
        case durationSec = "duration_sec"
        case incline
        case distanceKm = "distance_km"
        case elevationM = "elevation_m"
        case exerciseOrder = "exercise_order"
        case actualRestSec = "actual_rest_sec"
        case date
        case dayKey = "day_key"
    }

    /// The side as the DOMAIN spells it: `L` / `R`. The local store writes
    /// `left` / `right` (`SyncTranslation.localSide`), and every OnyxCore rule
    /// that folds a pair — `SessionVolume`, `PrEngine.volumeCredits`,
    /// `SessionDetail.toRows` — tests for the one-letter form. A pair handed
    /// over unmapped is scored as two lone sides, silently and everywhere.
    public var lr: String? {
        switch side {
        case "left": return "L"
        case "right": return "R"
        default: return side
        }
    }
}

/// Range reads over the training ledger. Query-only: no tables, no migrations,
/// no arithmetic — the domain shapes what comes back.
public extension AppDatabase {
    private static let setSelect = """
        SELECT s.id, s.session_id, s.exercise_id,
               COALESCE(e.name, es.name, s.exercise_id) AS exercise_name,
               s.set_index, s.fold_order, s.weight_kg, s.reps, s.set_type,
               s.side, s.pair_id, s.est_1rm_kg, s.rpe, s.quality,
               s.duration_sec, s.incline, s.distance_km, s.elevation_m, s.exercise_order,
               s.actual_rest_sec,
               sess.date, sess.day_key
        FROM workout_sets s
        JOIN workout_sessions sess ON sess.id = s.session_id
        LEFT JOIN exercises e ON e.id = s.exercise_id
            LEFT JOIN exercises es ON es.slug = s.exercise_id
        WHERE sess.user_id = ?
        """

    /// Ledger order: by day, then by session start, then as the fold arrived.
    /// `fold_order` before `set_index` because the puller numbers folds by the
    /// server's `set_number`, and the logger appends in performed order.
    private static let setOrder = " ORDER BY sess.date, sess.started_at, s.session_id, s.fold_order, s.set_index"

    /// Every session of one user, newest first.
    ///
    /// ── WHY EVERY READER HERE TAKES A `userId` (W11) ────────────────────────
    /// The local store holds one user's mirror, and that used to be the whole
    /// argument for reading it unfiltered. It is still one user's mirror — the
    /// account-switch erase (`prepareForUser`) is what makes it so — but the
    /// filter is the second lock: a row that outlives its owner, however it
    /// got there, is never handed to the next account. `setSelect` carries
    /// the clause, so no reader below can forget it.
    func sessionHistory(userId: String) throws -> [WorkoutSession] {
        try read { db in
            try WorkoutSession.fetchAll(
                db,
                sql: "SELECT * FROM workout_sessions WHERE user_id = ? ORDER BY date DESC, started_at DESC",
                arguments: [userId]
            )
        }
    }

    /// One session's sets in performed order.
    func historySets(sessionId: String, userId: String) throws -> [HistorySetRow] {
        try read { db in
            try HistorySetRow.fetchAll(
                db, sql: Self.setSelect + " AND s.session_id = ?" + Self.setOrder, arguments: [userId, sessionId]
            )
        }
    }

    /// The whole ledger in performed order. The session list needs it all (a
    /// PR count per session is a chronological replay) and it is a few thousand
    /// rows at most.
    func historySets(userId: String) throws -> [HistorySetRow] {
        try read { db in try HistorySetRow.fetchAll(db, sql: Self.setSelect + Self.setOrder, arguments: [userId]) }
    }

    /// Every set of the given exercises, performed order, oldest first.
    func historySets(exerciseIds: [String], userId: String) throws -> [HistorySetRow] {
        guard !exerciseIds.isEmpty else { return [] }
        let marks = Array(repeating: "?", count: exerciseIds.count).joined(separator: ",")
        return try read { db in
            try HistorySetRow.fetchAll(
                db,
                sql: Self.setSelect + " AND s.exercise_id IN (\(marks))" + Self.setOrder,
                arguments: StatementArguments([userId] + exerciseIds)
            )
        }
    }

    /// The record book for one exercise, keyed as `personal_records` keys it:
    /// by canonical display NAME, not id.
    func personalRecords(exerciseKey: String, userId: String) throws -> [PersonalRecordRow] {
        try read { db in
            try PersonalRecordRow.fetchAll(
                db,
                sql: "SELECT * FROM personal_records WHERE user_id = ? AND exercise_key = ? ORDER BY axis",
                arguments: [userId, exerciseKey]
            )
        }
    }

    /// Cardio that belongs to a session: filed against it, or logged on its day.
    func cardio(sessionId: String, date: String, userId: String) throws -> [CardioLogRow] {
        try read { db in
            try CardioLogRow.fetchAll(
                db,
                sql: "SELECT * FROM cardio_logs WHERE user_id = ? AND (session_id = ? OR date = ?) ORDER BY created_at",
                arguments: [userId, sessionId, date]
            )
        }
    }
}

// MARK: - The session seed

/// The history one day's seed is allowed to read: the qualifying sessions and
/// their sets, name-resolved. `SessionSeedBuilder` turns it into a deck.
/// A day's opening deck and the queue that shaped it.
public struct SeededDeck: Sendable, Equatable {
    public var seed: SessionSeed
    /// `ready` AND `one-more` — the banner shows both (decision 10); only
    /// `ready` pre-fills a load.
    public var alerts: [ProgressionQueue.Alert]

    public init(seed: SessionSeed, alerts: [ProgressionQueue.Alert]) {
        self.seed = seed
        self.alerts = alerts
    }
}

/// What a movement added mid-session was last lifted at — see
/// `AppDatabase.lastWorkingSet(named:userId:excludingSession:)`.
public struct LastWorkingSet: Sendable, Equatable {
    public var weightKg: Double
    public var reps: Int
    /// The session's logical day, ISO.
    public var date: String

    public init(weightKg: Double, reps: Int, date: String) {
        self.weightKg = weightKg
        self.reps = reps
        self.date = date
    }

    /// `"47kg × 12"` — the Previous column's own spelling, from the one
    /// function that spells it.
    public var label: String { SessionSeedBuilder.previousLabel(weightKg: weightKg, reps: reps) }
}

public struct SeedHistory: Sendable, Equatable {
    public var sessions: [SeedSession]
    public var sets: [SeedSet]

    public init(sessions: [SeedSession], sets: [SeedSet]) {
        self.sessions = sessions
        self.sets = sets
    }

    public static let empty = SeedHistory(sessions: [], sets: [])
}

public extension AppDatabase {

    /// Every session this device holds for one routine day, with the maintenance
    /// flag resolved, and the sets of the ones that qualify.
    ///
    /// ── THE NAME IS RESOLVED HERE, AND ONLY HERE ────────────────────────────
    /// `workout_sets.exercise_id` holds a catalogue uuid for a set the web
    /// logged and `"onyx-<slug>"` for one this phone logged, so a seed that
    /// matched on the id would find nothing for a web-logged session and fall
    /// through to the cold start — which is exactly what the Sept 6 Upper A
    /// session would have done. `PrRecorder.nameResolver` is the same two-source
    /// lookup the PR ledger keys on (catalogue, then `ExerciseSlug.nameBySlug`,
    /// then `ExerciseAliases`), so a set files its record and seeds its next
    /// session under one name or under neither.
    ///
    /// `maintenance` is decided per session by the LEVER (decision 6), not by
    /// `Maintenance.isMaintenanceDate`: the phase axis adds the historical
    /// deloads, and those are all in the previous era, which the era filter has
    /// already dropped.
    /// `userId` scopes the goals lookup only. Nil reads whichever goals row
    /// this store holds, which is the convention every other read in this
    /// package follows: the local store is ONE user's mirror, and filtering on
    /// a user id the puller already guaranteed is a way to return nothing when
    /// the casing drifts (`UserIdCasingTests`).
    func sessionsForSeed(dayKey: String, userId: String? = nil, today: String = LogicalDay.today()) throws -> SeedHistory {
        try read { db in
            let goals = try userId
                .map { try UserGoalRow.filter(Column("user_id") == $0).fetchOne(db) }
                ?? UserGoalRow.fetchOne(db)
            let owner = goals?.userId ?? userId ?? ""
            let ladder = try Self.leverLadder(db, userId: owner, goals: .some(goals))
            let ctx = try Self.scheduleContext(db, userId: owner, goals: .some(goals))
            let instant = Self.instantFormatter()
            // The OWNER's sessions only (W11): a seed is a proposal built from
            // history, and the one history it may read is this account's.
            let all = try WorkoutSession
                .filter(Column("user_id") == owner && Column("day_key") == dayKey)
                .fetchAll(db)
                .map { s in
                    SeedSession(
                        id: s.id, dayKey: s.dayKey, date: s.date,
                        // Any string that sorts chronologically. A session with
                        // no `started_at` sorts to the top of its own day, which
                        // is where a row that never recorded one belongs.
                        startedAt: s.startedAt.map(instant) ?? "",
                        maintenance: Maintenance.leverOn(s.date, today: today, ladder: ladder)
                    )
                }

            let qualifying = SessionSeedBuilder.sessionsForSeed(all, dayKey: dayKey, today: today) { Schedule.planId(owning: $0, in: ctx) }
            guard !qualifying.isEmpty else { return SeedHistory.empty }

            let name = try PrRecorder.nameResolver(db)
            let ids = qualifying.map(\.id)
            let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let rows = try WorkoutSet.fetchAll(
                db,
                sql: "SELECT * FROM workout_sets WHERE session_id IN (\(marks)) ORDER BY session_id, fold_order, set_index, rowid",
                arguments: StatementArguments(ids)
            )
            return SeedHistory(
                sessions: qualifying,
                sets: rows.enumerated().map { index, r in
                    SeedSet(
                        sessionId: r.sessionId, exerciseName: name(r.exerciseId),
                        // `set_index` is the performed number, but the puller
                        // numbers folds by the server's `set_number` and a
                        // legacy row can carry 0 — the read order is the
                        // tiebreak that makes this total.
                        order: r.setIndex > 0 ? r.setIndex : index + 1,
                        weightKg: r.weightKg, reps: r.reps, rpe: r.rpe,
                        setType: r.setType,
                        // The local store spells the side `left` / `right`;
                        // every OnyxCore rule that folds a pair tests for the
                        // one-letter form. A pair handed over unmapped is scored
                        // as two lone sides, silently.
                        side: Self.domainSide(r.side), pairId: r.pairId,
                        // A bout's whole content, which `weightKg`/`reps` above
                        // are the non-nil zeros of. Dropped here, a seeded
                        // treadmill came back to the deck as a lift of nothing
                        // — `SeedSet.durationSec` says what that cost.
                        durationSec: r.durationSec, incline: r.incline, distanceKm: r.distanceKm
                    )
                }
            )
        }
    }

    /// One day's deck, seeded — and the queue that seeded it.
    ///
    /// Both, from one call, because they are one read: the `.ready` verdicts
    /// ARE what pre-fills the rows, so a caller that asked for them separately
    /// would grade the same sessions twice and could get two answers if a set
    /// landed in between.
    func sessionSeed(
        dayKey: String, userId: String, phase: ProgramPhase,
        program: Program, today: String = LogicalDay.today()
    ) throws -> SeededDeck {
        let history = try sessionsForSeed(dayKey: dayKey, userId: userId, today: today)
        let ctx = try scheduleContext(userId: userId)
        // The qualifying ids are handed over rather than re-derived: without
        // this, `progressionQueue` folds the same sessions and re-reads all of
        // their sets a second time, on the main actor, inside `LoggerModel
        // .init`. That read grows with the season.
        let alerts = (try? progressionQueue(
            dayKey: dayKey, program: program, phase: phase, today: today,
            qualifying: Set(history.sessions.map(\.id))
        )) ?? []
        let seed = SessionSeedBuilder.build(
            dayKey: dayKey, today: today, phase: phase,
            sessions: history.sessions, sets: history.sets,
            template: try? seedTemplate(dayKey: dayKey, userId: userId),
            ready: alerts
                .filter { $0.state == .ready }
                .map { SeedProgression(name: $0.name, suggestKg: $0.suggestKg) },
            program: program,
            planOwning: { Schedule.planId(owning: $0, in: ctx) }
        )
        return SeededDeck(seed: seed, alerts: alerts)
    }

    /// The most recent WORKING set of one movement — any session, any day key.
    ///
    /// ── WHY THIS IS NOT THE SEED, AND MUST NOT BECOME IT (W3) ───────────────
    /// `sessionSeed` is scoped to one routine day on purpose: the rep window
    /// and the set count belong to the DAY, and Leg Press is 8–12 on Legs A and
    /// 12–15 on Legs B. So a movement added mid-session that today's program
    /// does not name has no seed entry at all, and its card opened blank. This
    /// answers only that card's question — "what did I last do on this?" — and
    /// widening `sessionsForSeed` to answer it instead would move the numbers
    /// on every card the day already has.
    ///
    /// Matched by canonical NAME over every id the movement has been logged
    /// under, exactly as `PrRecorder.baselines` gathers its `siblings`: a lift
    /// logged on the web carries the catalogue uuid, one logged here may carry
    /// the slug, and an id match alone finds half a history.
    ///
    /// Newest session first; within it the LAST working set performed that
    /// was not a drop set, a genuine L/R pair folded at its weaker side by the
    /// seed's own `collapsePairs`. A session holding only warm-ups of it is not evidence,
    /// the same rule `SessionSeedBuilder.seed` walks back past.
    ///
    /// `excludingSession` is the session being logged: once a set of this
    /// movement is ticked, a relaunch must not find it as its own "last time".
    func lastWorkingSet(named name: String, userId: String, excludingSession sessionId: String? = nil) throws -> LastWorkingSet? {
        let target = ExerciseAliases.canonicalName(name).lowercased()
        let ids = try read { db in
            let resolve = try PrRecorder.nameResolver(db)
            return try String.fetchAll(
                db,
                sql: "SELECT DISTINCT exercise_id FROM workout_sets WHERE session_id IN (SELECT id FROM workout_sessions WHERE user_id = ?)",
                arguments: [userId]
            ).filter { resolve($0).lowercased() == target }
        }
        // `setSelect`'s reader, so the columns a pair fold needs cannot be the
        // ones this forgot. Ledger order is oldest first; walk it backwards.
        let rows = try historySets(exerciseIds: ids, userId: userId).filter { $0.sessionId != sessionId }
        var order: [String] = []
        var bySession: [String: [HistorySetRow]] = [:]
        for row in rows {
            if bySession[row.sessionId] == nil { order.append(row.sessionId) }
            bySession[row.sessionId, default: []].append(row)
        }
        for id in order.reversed() {
            let sets = bySession[id] ?? []
            let working = SessionSeedBuilder.collapsePairs(sets.enumerated().map { index, r in
                SeedSet(
                    sessionId: id, exerciseName: name,
                    // The read order is the tiebreak for a legacy 0, as in
                    // `sessionsForSeed`.
                    order: r.setIndex > 0 ? r.setIndex : index + 1,
                    weightKg: r.weightKg, reps: r.reps, rpe: r.rpe, setType: r.setType,
                    side: r.lr, pairId: r.pairId
                )
            }).filter { SetTags.isWorkingSet($0.setType) }
            // The last set that was not a DROP: a back-off at half the load
            // closing out the session is not what you walk up to next time.
            // A session of nothing but drops still answers with its last.
            if let last = working.last(where: { $0.setType != "dropset" }) ?? working.last {
                return LastWorkingSet(weightKg: last.weightKg, reps: last.reps, date: sets[0].date)
            }
        }
        return nil
    }

    /// The stored `routine_templates` payload, as much of it as the seed reads.
    /// An unreadable payload is ABSENT, never a throw — the tier below it is a
    /// perfectly good answer.
    func seedTemplate(dayKey: String, userId: String) throws -> SeedTemplate? {
        let row = try read { db in
            try RoutineTemplateRow
                .filter(Column("user_id") == userId && Column("day_key") == dayKey)
                .fetchOne(db)
        }
        guard let row, let data = row.payload.raw.data(using: .utf8) else { return nil }
        return try? OnyxJSON.decoder.decode(SeedTemplate.self, from: data)
    }

    /// The day's stored deck order — movement names, first to last.
    ///
    /// ── WHY THIS IS SEPARATE FROM THE SEED ──────────────────────────────────
    /// `SessionSeedBuilder` walks the PROGRAM's list on purpose: its output is a
    /// shared contract with the web, checked by golden vectors, and a template
    /// covering two of a day's seven movements cannot rank the other five. So it
    /// reads the template for its numbers and never for its `order`.
    ///
    /// The deck is a different question, asked by one client, and this is the
    /// answer to it: which movements the athlete put where, last time they
    /// finished this split. `LoggerModel.inDeckOrder` applies it to the cards it
    /// has, leaves anything unnamed in program position, and lets the live deck
    /// outrank it mid-session.
    ///
    /// Empty when nothing has been stored, which is the cold start — and the
    /// program's own order is the right answer there.
    func deckOrder(dayKey: String, userId: String) throws -> [String] {
        guard let template = try seedTemplate(dayKey: dayKey, userId: userId) else { return [] }
        return template.exercises.sorted { $0.order < $1.order }.map(\.name)
    }

    /// `left` / `right` → `L` / `R`. See `HistorySetRow.lr`.
    private static func domainSide(_ side: String?) -> String? {
        switch side {
        case "left": return "L"
        case "right": return "R"
        default: return side
        }
    }

    /// A sortable instant.
    ///
    /// `ISO8601DateFormatter` is not `Sendable`, so it cannot be a shared
    /// static — but building one PER ROW is a formatter per session on a read
    /// that runs on the main actor while the logger opens. One per call,
    /// captured by the closure the caller maps with.
    private static func instantFormatter() -> (Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return { f.string(from: $0) }
    }
}
