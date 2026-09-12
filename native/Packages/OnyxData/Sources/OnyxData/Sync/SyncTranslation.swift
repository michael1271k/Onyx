import Foundation
import OnyxCore

/// How a local fact becomes a Postgres row.
///
/// ── THE GAP THIS FILE CLOSES ────────────────────────────────────────────────
/// The header of `Models.swift` said, correctly, that the local schema does not
/// match Supabase and that a translation layer had to exist before anything
/// could be uploaded. This is that layer. Every difference it bridges was
/// introspected from the LIVE database on 2026-09-03 — never from
/// the web app's `lib/supabase/types.ts`, which is known to have drifted:
///
///   · `workout_sets.set_index` → **`set_number`**. There is no `set_index`
///     column server-side at all.
///   · `workout_sessions.date` has **no server column**. `started_at` is the
///     only date signal there is, so `date` is derived from it locally
///     (`LogicalDay.iso`) and never sent. Adding a server column was considered
///     and rejected: the web app has committed 110 sessions without one.
///   · `workout_sessions.split_day` is **NOT NULL with a CHECK** and is absent
///     locally. It is derived from `day_key` (§`splitDay`).
///   · `workout_sets.user_id` is **NOT NULL** and absent from the local set
///     row. It comes from the parent session.
///   · `workout_sets.side` is `'L'`/`'R'` server-side, `left`/`right` locally.
///   · `workout_sets.exercise_id` is a **uuid with a live foreign key**, while
///     the local id is a slug of the movement's name. See `ExerciseIndex`.
///
/// Everything here is pure. It takes local rows and returns wire rows; it does
/// no I/O, holds no client and reads no clock it was not handed — which is what
/// lets the awkward cases be tested exhaustively without a network.
public enum SyncTranslation {}

// MARK: - Kinds

/// The `outbox.kind` strings this package produces.
///
/// Strings rather than an enum for the reason `OutboxItem.kind` gives: a queued
/// item written by an older build must still decode after a new kind is added,
/// and a queue that fails to decode is a queue that loses the workout.
public enum SyncKind {
    public static let sessionUpsert = "session.upsert"
    public static let setEventPrefix = "set_event."
    /// Any mirrored row, by table name and id. See `RowPush`.
    public static let rowUpsert = "row.upsert"
    /// A mirrored row to delete, by table name and key columns. See `RowPush`.
    public static let rowDelete = "row.delete"
}

/// The payload of a `session.upsert` item: an id, and deliberately nothing else.
///
/// The drainer reads the session row when it runs, so a queued item can never
/// carry a stale copy of a session that was rated or corrected after queuing.
public struct SessionRef: Codable, Sendable, Equatable {
    public var sessionId: String

    public enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

// MARK: - Backoff

/// How long a failed outbox item waits before it may be tried again.
///
/// ── WHY IT IS CAPPED AND NEVER GIVES UP ─────────────────────────────────────
/// `outboxFailed`'s own comment is the rule: an item is never dropped, because
/// a workout that cannot sync is a workout you still did. But a write the
/// server will never accept — a CHECK violation, an exercise that cannot be
/// resolved — must not be retried at full speed forever either. Doubling from
/// ten seconds to an hour spends almost nothing on a permanent failure and
/// still recovers a transient one within a minute.
///
/// A quarter-step of jitter. Two devices is not a fleet, but the two of them
/// DO fail together — a PostgREST restart, a schema-cache reload — and then
/// they knock again together, on the same second, against a server that is
/// still coming up. The caller passes a random fraction; the tests pass zero.
public enum SyncBackoff {
    public static let base: TimeInterval = 10
    public static let cap: TimeInterval = 3600
    /// The most a step may stretch: `jitter == 1` is a step and a quarter.
    public static let jitterFraction: Double = 0.25

    /// `attempts` is the count AFTER the failure being recorded, so the first
    /// failure waits `base`. `jitter` is a fraction in `0...1`.
    public static func delay(attempts: Int, jitter: Double = 0) -> TimeInterval {
        guard attempts > 0 else { return 0 }
        // Shifting rather than `pow`: the exponent is bounded below the cap
        // check anyway, and 2^63 is not a number this should ever compute.
        let steps = min(attempts - 1, 32)
        let stretch = 1 + jitterFraction * min(max(jitter, 0), 1)
        return min(base * TimeInterval(1 << steps) * stretch, cap)
    }
}

// MARK: - Errors

public enum SyncError: Error, Equatable, Sendable {
    /// The outbox payload would not decode. The row is kept and counted; it is
    /// never silently discarded.
    case undecodablePayload(kind: String, detail: String)
    /// The item names a session this store no longer has.
    case unknownSession(String)
    /// A session with no `day_key`, or one outside ONYX-5. `split_day` is NOT
    /// NULL server-side and there is nothing honest to put in it.
    case unmappedDayKey(String?)
    /// A session carrying neither `started_at` nor a parseable `date`.
    /// `started_at` is NOT NULL server-side.
    case sessionHasNoStart(String)
    /// A local `side` value that is neither left nor right. Guessing would
    /// break the L/R pair collapse the PR engine depends on.
    case unmappedSide(String)
    /// A set whose exercise could not be matched to a row in the server
    /// catalogue. See `ExerciseIndex` for why this fails rather than creating.
    case unknownExercise(slug: String, name: String?)
    /// Two catalogue rows are equally good matches for one movement. Picking
    /// one at random is how a movement's history silently splits in half.
    case ambiguousExercise(name: String, candidates: [String])
    /// A `row.upsert` item naming a table the generated catalogue does not
    /// have. Only reachable by downgrading to a build that predates the table,
    /// which is why the item is kept rather than dropped.
    case unmirroredTable(String)
    /// The row a queued upsert names is no longer in the local store.
    case unknownRow(table: String, id: String)
}

// MARK: - Split day

public extension SyncTranslation {

    /// `workout_sessions.split_day` for a ONYX-5 day key.
    ///
    /// ── THE MAP IS READ OFF THE LIVE DATABASE, NOT INVENTED ──────────────────
    /// `split_day` is `NOT NULL` and CHECK-constrained to
    /// `('push','pull','legs','upper','lower')`, and the local store has no such
    /// column — it carries `day_key`, which is the finer program label. The two
    /// are deliberately different vocabularies, so this is a lookup and not a
    /// transformation of the string.
    ///
    /// Every pair below is one the database already contains
    /// (`SELECT day_key, split_day, count(*) … GROUP BY 1,2`, 2026-09-03):
    /// `cb_a`, `cb_b` and `arms` are all `upper`; `legs_a` and `legs_b` are
    /// `legs`. The 75 rows with a NULL `day_key` are the pre-ONYX-5 push/pull/
    /// legs era and have no bearing here — the native logger always writes a
    /// `day_key`, because it takes it from `ProgramDay.key`.
    ///
    /// An unknown key throws. A default of `upper` would file a leg day under
    /// the wrong split forever, and unlike a rejected upload that is invisible.
    static let splitDayByDayKey: [String: String] = [
        "cb_a": "upper",
        "cb_b": "upper",
        "arms": "upper",
        "legs_a": "legs",
        "legs_b": "legs",
    ]

    static func splitDay(forDayKey dayKey: String?) throws -> String {
        guard let dayKey, let split = splitDayByDayKey[dayKey] else {
            throw SyncError.unmappedDayKey(dayKey)
        }
        return split
    }
}

// MARK: - Side

public extension SyncTranslation {

    /// `left`/`right` (local) → `L`/`R` (Postgres).
    ///
    /// The live column holds exactly `'L'`, `'R'` or NULL across 2,249 rows.
    /// Writing `left` into it would not fail — there is no CHECK — it would
    /// just quietly create a second vocabulary in one column, and the PR
    /// engine's unilateral pair collapse compares these strings.
    ///
    /// Already-abbreviated input is accepted so this is idempotent: a row that
    /// came back from the server and is pushed again must not throw.
    static func side(_ local: String?) throws -> String? {
        guard let local, !local.isEmpty else { return nil }
        switch local.lowercased() {
        case "left", "l": return "L"
        case "right", "r": return "R"
        default: throw SyncError.unmappedSide(local)
        }
    }
}

// MARK: - The session wire row

/// `workout_sessions`, as PostgREST wants it.
///
/// Separate from `WorkoutSession` on purpose, and for the reason `NutritionSync`
/// already gives for its own wire rows: this type mirrors POSTGRES — its column
/// names, its nullability, its NOT NULLs — while `WorkoutSession` mirrors the
/// local store. Collapsing them produces a model that is a bad fit for both,
/// which is exactly the mistake the "these columns match Supabase exactly"
/// comment recorded.
public struct RemoteSessionRow: Codable, Sendable, Equatable {
    public var id: String
    public var userId: String
    public var startedAt: Date
    public var splitDay: String
    public var endedAt: Date?
    public var dayKey: String?
    public var notes: String?
    public var durationMin: Int?
    public var sessionRpe: Double?
    /// Set on every push. `workout_sessions.updated_at` is `NOT NULL DEFAULT
    /// now()` with **no trigger** behind it, so the default only ever fires on
    /// INSERT — a client that does not write it leaves the column frozen at the
    /// moment the row was created, and the delta pull that Wave 2 builds on top
    /// of it would never see the edit.
    ///
    /// ── IT IS READ, AND NEVER WRITTEN ───────────────────────────────────────
    /// This field is decoded on the way IN, where it is the mirror's delta
    /// cursor, and deliberately absent from `encode(to:)` on the way out.
    ///
    /// The device must not write it. A delta pull filters `updated_at >= cursor`
    /// against a cursor that came from the server, so a phone running three
    /// minutes slow would stamp an edit in the past — into a range the next pull
    /// has already been through — and that edit would never be seen again.
    /// Server-side, `updated_at` is `DEFAULT now()` on INSERT and a
    /// `BEFORE UPDATE` trigger on UPDATE; both are the server's clock, which is
    /// the only clock a cursor can be compared against.
    public var updatedAt: Date?
    /// Session metrics. `integer` server-side; the two flags are `NOT NULL
    /// DEFAULT false` there, so a row from an older fixture or client decodes
    /// them as false rather than failing.
    public var avgBpm: Int?
    public var caloriesBurned: Int?
    public var avgBpmEstimated: Bool
    public var caloriesEstimated: Bool
    /// The session's own aggregates. `numeric` / `integer` server-side, all
    /// three nullable — a session nothing has computed for carries NULL, and
    /// `nil` is not `0` here any more than anywhere else in this app.
    public var totalVolumeKg: Double?
    public var setCount: Int?
    public var prCount: Int?

    public enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startedAt = "started_at"
        case splitDay = "split_day"
        case endedAt = "ended_at"
        case dayKey = "day_key"
        case notes
        case durationMin = "duration_min"
        case sessionRpe = "session_rpe"
        case updatedAt = "updated_at"
        case avgBpm = "avg_bpm"
        case caloriesBurned = "calories_burned"
        case avgBpmEstimated = "avg_bpm_estimated"
        case caloriesEstimated = "calories_estimated"
        case totalVolumeKg = "total_volume_kg"
        case setCount = "set_count"
        case prCount = "pr_count"
    }

    public init(
        id: String, userId: String, startedAt: Date, splitDay: String, endedAt: Date? = nil,
        dayKey: String? = nil, notes: String? = nil, durationMin: Int? = nil, sessionRpe: Double? = nil,
        updatedAt: Date? = nil, avgBpm: Int? = nil, caloriesBurned: Int? = nil,
        avgBpmEstimated: Bool = false, caloriesEstimated: Bool = false,
        totalVolumeKg: Double? = nil, setCount: Int? = nil, prCount: Int? = nil
    ) {
        self.id = id
        self.userId = userId
        self.startedAt = startedAt
        self.splitDay = splitDay
        self.endedAt = endedAt
        self.dayKey = dayKey
        self.notes = notes
        self.durationMin = durationMin
        self.sessionRpe = sessionRpe
        self.updatedAt = updatedAt
        self.avgBpm = avgBpm
        self.caloriesBurned = caloriesBurned
        self.avgBpmEstimated = avgBpmEstimated
        self.caloriesEstimated = caloriesEstimated
        self.totalVolumeKg = totalVolumeKg
        self.setCount = setCount
        self.prCount = prCount
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userId = try c.decode(String.self, forKey: .userId)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        splitDay = try c.decode(String.self, forKey: .splitDay)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        dayKey = try c.decodeIfPresent(String.self, forKey: .dayKey)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        durationMin = try c.decodeIfPresent(Int.self, forKey: .durationMin)
        sessionRpe = try c.decodeIfPresent(Double.self, forKey: .sessionRpe)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        avgBpm = try c.decodeIfPresent(Int.self, forKey: .avgBpm)
        caloriesBurned = try c.decodeIfPresent(Int.self, forKey: .caloriesBurned)
        avgBpmEstimated = try c.decodeIfPresent(Bool.self, forKey: .avgBpmEstimated) ?? false
        caloriesEstimated = try c.decodeIfPresent(Bool.self, forKey: .caloriesEstimated) ?? false
        totalVolumeKg = try c.decodeIfPresent(Double.self, forKey: .totalVolumeKg)
        setCount = try c.decodeIfPresent(Int.self, forKey: .setCount)
        prCount = try c.decodeIfPresent(Int.self, forKey: .prCount)
    }

    /// ── EVERY KEY, EVERY TIME, INCLUDING THE NULLS ──────────────────────────
    /// Swift synthesises `encodeIfPresent` for an Optional, which OMITS a nil
    /// rather than writing `null`. That matters because an omitted key is not
    /// updated on conflict: deleting the notes off a session would leave the
    /// old text on the server forever, and the only way to say "this field is
    /// now empty" over PostgREST is to send `null`.
    ///
    /// It also keeps every object in a bulk body the same shape. supabase-swift
    /// happens to send `?columns=<union of keys>`, which is PostgREST's own
    /// escape hatch for a heterogeneous body — so that half is belt and braces
    /// through THIS client, and would not be through a hand-rolled request.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(splitDay, forKey: .splitDay)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(dayKey, forKey: .dayKey)
        try c.encode(notes, forKey: .notes)
        try c.encode(durationMin, forKey: .durationMin)
        try c.encode(sessionRpe, forKey: .sessionRpe)
        try c.encode(avgBpm, forKey: .avgBpm)
        try c.encode(caloriesBurned, forKey: .caloriesBurned)
        try c.encode(avgBpmEstimated, forKey: .avgBpmEstimated)
        try c.encode(caloriesEstimated, forKey: .caloriesEstimated)
        // ── THE THREE AGGREGATES ARE THE ONE EXCEPTION TO "EVERY KEY" ───────
        // `encodeIfPresent`, deliberately, against the rule three paragraphs
        // up. Those keys are nulled on purpose because a cleared note must
        // reach the server; these must NOT be, because the web computes them
        // on save and this device only computes them for a session it has the
        // sets for. A phone that has never pulled a 2024 session would
        // otherwise upsert `total_volume_kg: null` over a figure the web
        // wrote — erasing history to say "I don't know", which is exactly the
        // trade `SyncEngine` refused when it left them out entirely.
        try c.encodeIfPresent(totalVolumeKg, forKey: .totalVolumeKg)
        try c.encodeIfPresent(setCount, forKey: .setCount)
        try c.encodeIfPresent(prCount, forKey: .prCount)
        // `updated_at` is NOT encoded — see the field. The server owns it.
    }
}

// MARK: - The set wire row

/// `workout_sets`, as PostgREST wants it.
public struct RemoteSetRow: Codable, Sendable, Equatable {
    public var id: String
    public var sessionId: String
    public var exerciseId: String
    public var userId: String
    /// **`set_index` locally.** The rename is the whole reason this type exists.
    public var setNumber: Int
    public var weightKg: Double
    public var reps: Int
    public var setType: String
    public var side: String?
    public var pairId: String?
    public var est1rmKg: Double?
    public var rpe: Double?
    /// Which movement this set belongs to, by deck position — dense from 0, the
    /// same number `buildCommitPayload` writes on the web.
    ///
    /// Tracked locally since `v16.exerciseOrder` and SENT, which every phone
    /// session before it was not: `useSessionDetail` orders on this column
    /// before `set_number`, so a workout that uploads nulls comes back in
    /// whatever order the set numbers imply — the incline press interleaved
    /// with the flye because both start at 1.
    public var exerciseOrder: Int?
    /// A set that is not reps and kilograms: seconds under load, treadmill
    /// incline as a percent, kilometres covered.
    ///
    /// Added to Postgres on 2026-09-07 and populated on exactly one row — the
    /// treadmill that opens `b6a936a8`, `weight_kg 0, reps 0, duration_sec 300,
    /// incline 2.0, distance_km 0.370`. Pulled AND sent: a session this device
    /// adopts carries them into the local fold, and the next push has to write
    /// them back or the first edit blanks the only row in the database that
    /// uses the columns.
    ///
    /// `nil` on every lifted set, which is all but one of them.
    public var durationSec: Int?
    public var incline: Double?
    public var distanceKm: Double?
    /// Total ascent for the bout, in metres — `docs/sql/cardio-elevation.sql`.
    ///
    /// Pulled and SENT, on the same terms as the three axes above: the puller
    /// asks for `select=*`, so a server without the column simply answers
    /// without the key and this decodes nil, and the push writes the key on
    /// every row so one batch never carries two shapes.
    ///
    /// ── AND THE PUSH IS WHY THE SQL COMES FIRST ─────────────────────────────
    /// `docs/sql/cardio-elevation.sql` is applied BY HAND, and until it is,
    /// PostgREST rejects a body naming a column it does not have — the whole
    /// session, not one field. Sending it conditionally is the alternative and
    /// it is worse: the condition would have to be a schema probe on every
    /// drain, and a batch that sometimes carries the key and sometimes does not
    /// is the two-shapes bug this type's `encode(to:)` exists to prevent.
    public var elevationM: Double?
    /// The set-quality tag — `Cheated`, `Short ROM`, and the rest of the CHECK
    /// on `workout_sets.quality`. `nil` means the phone has NOTHING to say
    /// about this set, and a nil is never encoded: see `encode(to:)`.
    public var quality: String?
    /// `created_at` — the server's clock for the row's arrival. READ ONLY:
    /// decoded from a pull so `seedEventLog` can stamp the seed with the time
    /// the set was actually logged, never encoded (`NOT NULL DEFAULT now()`,
    /// and the server's clock is the better one). The local `workout_sets`
    /// has no column for it; the seed's `created_at` is where it lives.
    public var createdAt: Date?

    public enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case sessionId = "session_id"
        case exerciseId = "exercise_id"
        case userId = "user_id"
        case setNumber = "set_number"
        case weightKg = "weight_kg"
        case reps
        case setType = "set_type"
        case side
        case pairId = "pair_id"
        case est1rmKg = "est_1rm_kg"
        case rpe
        case exerciseOrder = "exercise_order"
        case durationSec = "duration_sec"
        case incline
        case distanceKm = "distance_km"
        case elevationM = "elevation_m"
        case quality
    }

    /// Same reason as `RemoteSessionRow`: nulls are written, never omitted, so
    /// every object in a bulk upsert carries an identical key set.
    ///
    /// ── `exercise_order` IS WRITTEN, NULLS AND ALL, AND WHY THAT IS SAFE ─────
    /// The phone has a real opinion about it for every set it logs, because the
    /// opinion IS the deck the athlete is looking at. Omitting it per-row is not on the
    /// table — a batch is one session's sets and PostgREST rejects a body whose
    /// objects disagree about keys, which fails the whole session rather than
    /// one column of one row.
    ///
    /// The residue: a session PULLED before `v16` carries a local null over a
    /// populated server value, and editing it here would write that null back.
    /// Narrow — `applyPulledSets` has carried the column since the same wave,
    /// so it only affects rows that landed on this device before the upgrade
    /// AND are then edited on it — and one re-save on either client repairs it.
    /// The alternative costs the whole batch.
    ///
    /// What is still absent from this list is absent on purpose:
    ///
    ///   · `is_pr` — the PR engine is ported now (`PrEngine`, `PrRecorder`) and
    ///     this is still not sent, because a record is not a property of the set
    ///     at the moment it is logged. A later set in the same session
    ///     supersedes it, deleting one hands the axis back, and `PrRecorder`
    ///     can RETRACT — so a flag frozen into the `.append` payload is a claim
    ///     that goes stale inside the same workout, and `reproject` would keep
    ///     replaying the stale one. It wants stamping over the whole session at
    ///     close, which is a different write from this one. Sending `false`
    ///     meanwhile would overwrite a record the web app flagged.
    ///   · `created_at` — `NOT NULL DEFAULT now()`, and the server's clock is
    ///     the better one for a row's arrival time.
    ///
    /// ── AND `quality` IS SENT NOW, BUT ONLY WHERE THERE IS ONE ──────────────
    /// It used to sit with `is_pr`, for a real reason: PostgREST wants an
    /// identical key set across every object of a bulk upsert (`PGRST102`), so
    /// unconditionally encoding it means sending NULL for every set nobody was
    /// asked about — which wipes the quality the web app recorded on any set
    /// the phone later corrects.
    ///
    /// The fix is not to omit the column, it is to stop mixing the two kinds
    /// of row in one body. `nil` is not encoded here, and `SyncEngine` splits
    /// the batch on exactly that line: the rows carrying a tag go up as one
    /// homogeneous body WITH the key, the rest as another WITHOUT it. Neither
    /// body has two shapes, and no set is nulled by a device that was never
    /// asked about it.
    ///
    /// What this still does not do is CLEAR a tag the web app set. Locally the
    /// fold collapses "never asked" and "tag removed" onto the same `nil`
    /// (`SetEvent.clearedQuality` survives only as far as the fold), so the
    /// phone cannot tell the server which one it means. Distinguishing them
    /// wants a third state in the local column, not a fourth branch here.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(userId, forKey: .userId)
        try c.encode(setNumber, forKey: .setNumber)
        try c.encode(weightKg, forKey: .weightKg)
        try c.encode(reps, forKey: .reps)
        try c.encode(setType, forKey: .setType)
        try c.encode(side, forKey: .side)
        try c.encode(pairId, forKey: .pairId)
        try c.encode(est1rmKg, forKey: .est1rmKg)
        try c.encode(rpe, forKey: .rpe)
        try c.encode(exerciseOrder, forKey: .exerciseOrder)
        // ── AND WHY THESE THREE SIT WITH `exercise_order`, NOT WITH `quality` ─
        // The argument for omitting `quality` is that the web writes it and the
        // phone would null it. Nothing writes these but the pull that put them
        // there: the columns are three days old, one row in the database has a
        // value in any of them, and that row reaches this device through
        // `applyPulledSets` — which now carries all three. So a null here is
        // this device saying "this set has no duration", which for a barbell
        // row is the truth, and for the treadmill it never says, because the
        // treadmill's own values came down and go back up.
        try c.encode(durationSec, forKey: .durationSec)
        try c.encode(incline, forKey: .incline)
        try c.encode(distanceKm, forKey: .distanceKm)
        // A FOURTH, for the same reason and with the same null. Ascent is
        // measured, so this device's nil is "nobody measured it", which for a
        // barbell row is the truth and for the treadmill is what came down.
        try c.encode(elevationM, forKey: .elevationM)
        // ── THE ONE CONDITIONAL KEY, AND THE ONE RULE IT IMPOSES ────────────
        // `encodeIfPresent`, not `encode`: a nil must leave no key at all, or
        // the split `SyncEngine.upsertSets` performs is pointless. That split
        // is what keeps every body one shape — see the type's doc comment.
        try c.encodeIfPresent(quality, forKey: .quality)
    }
}

// MARK: - Building the wire rows

public extension SyncTranslation {

    /// The local session row, as Postgres wants it.
    ///
    /// - `date` is not sent: there is no such column. It is a local derivation
    ///   of `started_at` and `sessionDate(for:)` is its inverse.
    /// - `status` is not sent either. It is `NOT NULL DEFAULT 'complete'` and
    ///   every one of the 110 live rows says `complete`, including the one that
    ///   is still open — an unfinished session is marked by a NULL `ended_at`,
    ///   not by a status. Inventing `in_progress` would put a value in that
    ///   column that no reader in either app knows.
    /// - `total_volume_kg`, `set_count` and `pr_count` ARE sent now, and only
    ///   when this device has computed them (E1). All three engines are ported
    ///   — `SessionVolume`, `Draft.totals`, `PrEngine` — and `SessionEditing`
    ///   is what made it necessary: a phone that rewrites a closed session's
    ///   sets without rewriting its tonnage leaves the web reading a figure
    ///   for a workout that no longer exists. A nil is still OMITTED rather
    ///   than nulled, so a session this device holds no sets for keeps
    ///   whatever the web wrote.
    static func sessionRow(
        _ session: WorkoutSession,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> RemoteSessionRow {
        // `started_at` is NOT NULL server-side and Optional locally. A session
        // row always has a `date`, so fall back to local noon on that day —
        // noon and not midnight, for the reason `LogicalDay.date(fromISO:)`
        // gives: a midnight timestamp formatted in any timezone west of the
        // calendar's shows the previous day.
        guard let startedAt = session.startedAt
                ?? LogicalDay.date(fromISO: session.date, calendar: calendar)
        else { throw SyncError.sessionHasNoStart(session.id) }

        return RemoteSessionRow(
            id: session.id,
            userId: session.userId,
            startedAt: startedAt,
            splitDay: try splitDay(forDayKey: session.dayKey),
            endedAt: session.endedAt,
            dayKey: session.dayKey,
            // An empty note is not a note. The web app sends `notes || null` for
            // the same reason: an empty string renders as a note that is there
            // and says nothing.
            notes: (session.notes?.isEmpty ?? true) ? nil : session.notes,
            // `duration_min` is `integer` server-side and a Double locally.
            // `jsRound`, not `rounded()` — the web app writes `Math.round` here
            // and the two disagree on exactly the halves a test grid is least
            // likely to contain.
            // `Int(exactly:)`, not `Int(_:)` — the latter TRAPS on a NaN or an
            // out-of-range Double, and a crash inside the drainer takes the
            // whole batch down in the one way nothing recovers from.
            durationMin: session.durationMin.flatMap { Int(exactly: jsRound($0)) },
            sessionRpe: rpe(session.sessionRpe),
            // Never sent. Present only so a PULLED row can carry the cursor.
            updatedAt: nil,
            avgBpm: session.avgBpm,
            caloriesBurned: session.caloriesBurned,
            avgBpmEstimated: session.avgBpmEstimated,
            caloriesEstimated: session.caloriesEstimated,
            totalVolumeKg: session.totalVolumeKg,
            setCount: session.setCount,
            prCount: session.prCount
        )
    }

    /// The local set row, as Postgres wants it.
    ///
    /// `exerciseId` is passed in already resolved: the local value is a slug and
    /// the column is a uuid with a live foreign key, so the lookup needs the
    /// server catalogue and cannot be done from the set alone.
    static func setRow(
        _ set: WorkoutSet,
        userId: String,
        exerciseId: String
    ) throws -> RemoteSetRow {
        RemoteSetRow(
            id: set.id,
            sessionId: set.sessionId,
            exerciseId: exerciseId,
            userId: userId,
            // The rename, in one line. `set_index` does not exist server-side.
            setNumber: set.setIndex,
            weightKg: set.weightKg,
            reps: set.reps,
            setType: set.setType,
            side: try side(set.side),
            pairId: set.pairId,
            est1rmKg: set.est1rmKg,
            rpe: rpe(set.rpe),
            exerciseOrder: set.exerciseOrder,
            durationSec: set.durationSec,
            incline: set.incline,
            distanceKm: set.distanceKm,
            elevationM: set.elevationM,
            // Straight through. `WorkoutSet.quality` is already the folded
            // truth — `SetEventFold` has applied every `.clearedQuality`
            // sentinel by the time a row reaches the projection — so a nil
            // here is genuinely "no tag", and nils are not encoded.
            quality: set.quality
        )
    }

    /// `workout_sessions.date`, derived rather than stored.
    ///
    /// The server has no `date` column and is not getting one. This is the
    /// direction the pull side needs (Wave 2 item 2): a row arrives carrying
    /// `started_at`, and the local store's NOT NULL `date` is the logical day
    /// that instant falls in — **the device's** calendar day, never the
    /// server's, which is why `/api/today` took the date as a parameter.
    static func sessionDate(for startedAt: Date, calendar: Calendar = .current) -> String {
        LogicalDay.iso(startedAt, calendar: calendar)
    }

    /// `L`/`R` (Postgres) → `left`/`right` (local). The inverse of `side`.
    ///
    /// Unlike its outbound twin this one does NOT throw. A value nobody
    /// recognises is a row already on the server, and refusing to store it would
    /// hide a set that exists; dropping the side shows the set with one field
    /// missing, which is visible and fixable. Outbound, a bad value would have
    /// written a second vocabulary into the column, which is neither.
    static func localSide(_ remote: String?) -> String? {
        switch remote?.uppercased() {
        case "L", "LEFT": return "left"
        case "R", "RIGHT": return "right"
        default: return nil
        }
    }

    /// `left`/`right` (local) → `L`/`R` — the spelling every OnyxCore rule that
    /// folds a unilateral pair tests for.
    ///
    /// ── WHY THIS IS NOT `side(_:)`, THE OUTBOUND ONE ────────────────────────
    /// That one THROWS on a value it does not recognise, because an unmapped
    /// side reaching Postgres would write a second vocabulary into a column two
    /// clients read. This one is for handing local rows to the DOMAIN — the PR
    /// engine, the volume rule — where the honest answer to "what side is
    /// this" for an unrecognised value is "none", exactly as `localSide`
    /// decided inbound. A throw here would cost a record; a nil costs a pair
    /// its collapse, which is the same thing the row already says.
    ///
    /// `public` because the LIVE deck needs it too: `LoggerModel.refreshLivePrs`
    /// builds its candidates from rows holding the local spelling, and a live
    /// trophy computed on uncollapsed pairs is a badge the close then refuses
    /// to file — the exact failure `PrRecorder.baselines`'s header forbids.
    static func domainSide(_ local: String?) -> String? {
        switch local?.uppercased() {
        case "L", "LEFT": return "L"
        case "R", "RIGHT": return "R"
        default: return nil
        }
    }

    /// A rating the `rpe_range` CHECK will accept, or nothing.
    ///
    /// The constraint is `rpe IS NULL OR (rpe >= 1 AND rpe <= 10)`, and
    /// PostgREST rejects the WHOLE statement on one bad row — so a single
    /// out-of-range value would cost the entire session its upload, repeatedly,
    /// forever. Dropping the rating loses one field; keeping it loses the
    /// workout. An out-of-range CR-10 is not a rating anyone typed anyway: the
    /// ladder cannot produce one.
    ///
    /// Note this is NOT a clamp. Clamping an 11 to a 10 would invent a rating.
    static func rpe(_ value: Double?) -> Double? {
        guard let value, value >= 1, value <= 10 else { return nil }
        return value
    }
}
