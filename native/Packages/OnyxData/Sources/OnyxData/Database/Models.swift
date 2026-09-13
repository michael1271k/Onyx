import Foundation
import GRDB

/// The Wave 1 local schema — only what the Live Logger needs.
///
/// ── THESE DO NOT MATCH SUPABASE, AND THAT IS HANDLED NOW ────────────────────
/// An earlier version of this comment claimed the columns matched Postgres
/// exactly and that a PostgREST row could be inserted here with no translation.
/// That was never true. The differences, introspected against the live database
/// (2026-09-02, re-confirmed 2026-09-03):
///
///   · `workout_sets` — ours says `set_index`, Postgres says **`set_number`**.
///     Postgres also has `user_id` (NOT NULL), `created_at` (NOT NULL) and
///     `is_pr`, none of which is here. (`rpe` WAS in that list; `v7.setRpe`
///     added it. `quality` was too; `v14.setQuality` added it — locally only,
///     see `SyncTranslation.RemoteSetRow`. `exercise_order` was too;
///     `v16.exerciseOrder` added it, and it IS sent. `duration_sec`, `incline`
///     and `distance_km` were too; `v18.cardioSetFields` added them, and they
///     are sent.) Its `exercise_id` is a uuid with a live foreign key; ours is
///     a slug.
///   · `workout_sessions` — our `date` column **does not exist** server-side
///     (there is `started_at` and `day_key`). Postgres requires `split_day`
///     (NOT NULL, CHECK-constrained); `status` and `migrated_from_notion` are
///     NOT NULL but carry defaults.
///   · `exercises` — shares only `id` and `name`. Ours invents
///     `primary_muscle`, `secondary_muscles`, `equipment`, `is_unilateral` and
///     `is_bodyweight`; Postgres has `user_id`, `split_day`, `muscle_groups`
///     (a text array) and `is_compound`.
///   · `set_events`, `live_sessions`, `device_state` and `outbox` are **local
///     only** and have no server-side counterpart. Confirmed, not assumed —
///     which is why the drainer reconciles rows rather than shipping events.
///
/// **`Sync/SyncTranslation.swift` is where every one of those is bridged.** Do
/// not add a translation here: these types mirror the local store, the
/// `Remote*Row` types mirror Postgres, and the whole reason there are two sets
/// is that one type trying to be both is a bad fit for either.
///
/// Supabase remains the schema-of-record. Where a name here does match, it
/// matches deliberately and must not drift.
///
/// Every field that is nullable in Postgres is `Optional` here. Nothing is
/// defaulted to zero on the way in: the domain distinguishes "absent" from
/// "zero" in at least three places that have caused real bugs, and the store is
/// not the layer that gets to erase that distinction.

// MARK: - Exercise

public struct Exercise: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "exercises"

    public var id: String
    public var name: String
    public var primaryMuscle: String?
    public var secondaryMuscles: String?     // JSON array, stored as text
    public var equipment: String?
    public var isUnilateral: Bool?
    public var isBodyweight: Bool?
    /// The legacy `helix5-…` id this row answers for (`exercises.slug`, W2).
    /// A set logged before W2 carries it in `workout_sets.exercise_id`.
    public var slug: String?

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case primaryMuscle = "primary_muscle"
        case secondaryMuscles = "secondary_muscles"
        case equipment
        case isUnilateral = "is_unilateral"
        case isBodyweight = "is_bodyweight"
        case slug
    }

    public init(
        id: String, name: String, primaryMuscle: String? = nil,
        secondaryMuscles: String? = nil, equipment: String? = nil,
        isUnilateral: Bool? = nil, isBodyweight: Bool? = nil, slug: String? = nil
    ) {
        self.id = id
        self.name = name
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.isUnilateral = isUnilateral
        self.isBodyweight = isBodyweight
        self.slug = slug
    }
}

// MARK: - Workout session

public struct WorkoutSession: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "workout_sessions"

    public var id: String
    public var userId: String
    /// The logical calendar day this session is attributed to.
    ///
    /// NEVER infer the split from the weekday. A swap moves a workout to another
    /// date and the weekday stops meaning anything — a Wednesday "Delts & Arms"
    /// landed in the Upper A curve exactly this way.
    public var dayKey: String?
    public var date: String                  // ISO yyyy-MM-dd
    public var startedAt: Date?
    public var endedAt: Date?
    public var durationMin: Double?
    /// CR-10. Nil means "not rated", which is not the same as 0 — the battery
    /// falls back to its own default rather than treating it as an easy session.
    public var sessionRpe: Double?
    public var notes: String?
    /// Average heart rate and active energy for the session. Measured from an
    /// `HKWorkout` that overlaps it, or estimated — and a derived number must
    /// announce itself, so each carries its own `*Estimated` flag. A measured
    /// value is never overwritten by an estimate.
    public var avgBpm: Int?
    public var caloriesBurned: Int?
    public var avgBpmEstimated: Bool
    public var caloriesEstimated: Bool
    /// The session's own aggregates, as both clients store them: tonnage under
    /// `SessionVolume.sessionVolumeKg`'s rules (a unilateral pair scored once,
    /// at the weaker side), the committed-set count that collapses the same
    /// pairs, and the distinct axis-PRs the ledger filed. Nil until something
    /// has computed them — a zero tonnage is a claim about a workout, an absent
    /// one is a gap in what is known about it.
    public var totalVolumeKg: Double?
    public var setCount: Int?
    public var prCount: Int?
    /// A human set `duration_min` and it is not the clock's to re-derive.
    ///
    /// LOCAL ONLY — Postgres has no such column and wants none. It is not a
    /// fact about the workout but about who last wrote a number, and its only
    /// reader is `closeSession` deciding whether it may overwrite. Same rule as
    /// `WorkoutSet.foldOrder`.
    public var durationEdited: Bool
    /// Set locally the moment a session is committed; cleared when the outbox
    /// confirms the server accepted it.
    public var isPendingSync: Bool

    public enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case dayKey = "day_key"
        case date
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationMin = "duration_min"
        case sessionRpe = "session_rpe"
        case notes
        case avgBpm = "avg_bpm"
        case caloriesBurned = "calories_burned"
        case avgBpmEstimated = "avg_bpm_estimated"
        case caloriesEstimated = "calories_estimated"
        case totalVolumeKg = "total_volume_kg"
        case setCount = "set_count"
        case prCount = "pr_count"
        case durationEdited = "duration_edited"
        case isPendingSync = "is_pending_sync"
    }

    public init(
        id: String, userId: String, dayKey: String? = nil, date: String,
        startedAt: Date? = nil, endedAt: Date? = nil, durationMin: Double? = nil,
        sessionRpe: Double? = nil, notes: String? = nil,
        avgBpm: Int? = nil, caloriesBurned: Int? = nil,
        avgBpmEstimated: Bool = false, caloriesEstimated: Bool = false,
        totalVolumeKg: Double? = nil, setCount: Int? = nil, prCount: Int? = nil,
        durationEdited: Bool = false,
        isPendingSync: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.dayKey = dayKey
        self.date = date
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMin = durationMin
        self.sessionRpe = sessionRpe
        self.notes = notes
        self.avgBpm = avgBpm
        self.caloriesBurned = caloriesBurned
        self.avgBpmEstimated = avgBpmEstimated
        self.caloriesEstimated = caloriesEstimated
        self.totalVolumeKg = totalVolumeKg
        self.setCount = setCount
        self.prCount = prCount
        self.durationEdited = durationEdited
        self.isPendingSync = isPendingSync
    }
}

// MARK: - Workout set

public struct WorkoutSet: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "workout_sets"

    public var id: String
    public var sessionId: String
    public var exerciseId: String
    public var setIndex: Int
    /// Kilograms. **Zero is a real, valid load** — a bodyweight set. It must
    /// never be coerced to nil or filtered out; `Epley.oneRepMax` is the thing
    /// that decides an unloaded set has no 1RM, and it decides that by returning
    /// nil, not by the set being absent.
    public var weightKg: Double
    public var reps: Int
    /// `normal` | `warmup` | `failure` | `dropset` | `ghost`.
    /// A ghost set counts for nothing, anywhere.
    public var setType: String
    /// `left` | `right` for a unilateral movement, else nil. Carried alongside
    /// `pairId` because the PR engine collapses an L/R pair into one per-set
    /// tonnage record and cannot do that without both.
    public var side: String?
    public var pairId: String?
    /// Stored rather than recomputed. The web app learned this the hard way:
    /// read the stored value with `||`, not `??`, because a stored 0 on an
    /// unloaded set is a legacy artefact and not an estimate.
    public var est1rmKg: Double?
    /// CR-10, half-point steps. `nil` is UNRATED, never "easy" — see the same
    /// note on `SetSnapshot.rpe`.
    public var rpe: Double?
    /// HOW the set went, as opposed to how hard: one of the six keys the
    /// Postgres CHECK holds (`momentum`, `partial_rom`, `form_breakdown`,
    /// `needed_warmup`, `assisted`, `cut_short`). `nil` is "the question was
    /// never asked", which is what every set logged before this column meant —
    /// storing a default would make 2,190 historical rows assert a cleanliness
    /// nobody claimed. Added locally in `v14`; Postgres has carried it all
    /// along. See `SetQuality` in the app target for the vocabulary.
    public var quality: String?
    /// Where this set's MOVEMENT sat in the session — the deck position, dense
    /// from 0, the same number `buildCommitPayload` writes on the web.
    ///
    /// A fact about the exercise, repeated on each of its sets, because that is
    /// the shape Postgres has always had and the shape every reader on both
    /// sides orders by (`useSessionDetail` sorts on it before `set_number`).
    ///
    /// **`nil` is "nobody said".** Every set this phone logged before
    /// `v16.exerciseOrder` means exactly that, and so does every row of a
    /// session the mirror pulled from a client that never wrote the column.
    /// Defaulting it to 0 would claim every one of those movements opened the
    /// workout, which is a claim about eleven cards at once.
    public var exerciseOrder: Int?
    /// A set that is not reps and kilograms.
    ///
    /// Seconds under load, treadmill incline as a percent, kilometres covered.
    /// Postgres grew all three on 2026-09-07 (`hotfix-polish.sql (git history)`) for
    /// the treadmill warm-up, which `workout_sets` had nowhere to put: it is
    /// `weight_kg 0, reps 0`, and a reader with only those two columns renders
    /// it as `0kg × 0` — a claim that five minutes of walking was nothing.
    ///
    /// **All three are `nil` on a lifted set and that is the normal case.** Nil
    /// is "this axis does not apply", never zero: a `duration_sec` of 0 would
    /// say the set took no time. `SetFormat.cardio` returns nil when all three
    /// are absent, which is what hands the row back to `format`.
    ///
    /// These do NOT replace the reps-as-seconds convention Side Plank's
    /// historical rows still use — nothing rewrites those, and `TimedExercise`
    /// remains how a hold is read.
    public var durationSec: Int?
    public var incline: Double?
    public var distanceKm: Double?
    /// Total ascent for the bout, in METRES — the fourth cardio axis
    /// (`cardio-elevation.sql (git history)`, `v19.cardioElevation`).
    ///
    /// **Measured, never derived.** `incline × distanceKm` looks like the same
    /// number and is only equal while the incline never moved; a real walk is
    /// 2 % then 4 % then flat, and `incline` holds one of those three. So a
    /// stored value here can legitimately disagree with the product of the two
    /// columns beside it, and when it does, this one is right.
    ///
    /// `nil` is the normal state — the Postgres column is applied by hand and
    /// nothing writes it yet.
    public var elevationM: Double?
    /// MEASURED rest before this set, in seconds — `actual-rest.sql (git history)`,
    /// `v22.actualRest`.
    ///
    /// The elapsed gap between committing the previous set of the same exercise
    /// and committing this one, taken on the device that logged it. NOT the
    /// rest TIMER: the timer is a countdown you can skip, ignore, or leave
    /// running through a phone call, so it measures the prescription rather
    /// than the behaviour.
    ///
    /// **Distinct from the dead `rest_sec`**, which held the web deck's client
    /// stopwatch until 2026-08-19 and never carried a value anywhere in the
    /// database. Reusing that name would make nil ambiguous between "never
    /// measured" and "measured by a tool that was deleted".
    ///
    /// `nil` is the normal state and means not measured: every row logged
    /// before the column, every first set of an exercise, every web-committed
    /// set, and any gap past the logger's outlier ceiling.
    public var actualRestSec: Int?
    public var isPendingSync: Bool
    /// The fold's arrival position, so a read can reproduce the fold's order
    /// even when two devices claim the same `setIndex`. Local only — derived
    /// data, never sent to Postgres.
    public var foldOrder: Int

    public enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case exerciseId = "exercise_id"
        case setIndex = "set_index"
        case weightKg = "weight_kg"
        case reps
        case setType = "set_type"
        case side
        case pairId = "pair_id"
        case est1rmKg = "est_1rm_kg"
        case rpe
        case quality
        case exerciseOrder = "exercise_order"
        case durationSec = "duration_sec"
        case incline
        case distanceKm = "distance_km"
        case elevationM = "elevation_m"
        case actualRestSec = "actual_rest_sec"
        case isPendingSync = "is_pending_sync"
        case foldOrder = "fold_order"
    }

    public init(
        id: String, sessionId: String, exerciseId: String, setIndex: Int,
        weightKg: Double, reps: Int, setType: String = "normal",
        side: String? = nil, pairId: String? = nil, est1rmKg: Double? = nil,
        rpe: Double? = nil, quality: String? = nil, exerciseOrder: Int? = nil,
        durationSec: Int? = nil, incline: Double? = nil, distanceKm: Double? = nil,
        elevationM: Double? = nil, actualRestSec: Int? = nil,
        isPendingSync: Bool = false, foldOrder: Int = 0
    ) {
        self.id = id
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.setIndex = setIndex
        self.weightKg = weightKg
        self.reps = reps
        self.setType = setType
        self.side = side
        self.pairId = pairId
        self.est1rmKg = est1rmKg
        self.rpe = rpe
        self.quality = quality
        self.exerciseOrder = exerciseOrder
        self.durationSec = durationSec
        self.incline = incline
        self.distanceKm = distanceKm
        self.elevationM = elevationM
        self.actualRestSec = actualRestSec
        self.isPendingSync = isPendingSync
        self.foldOrder = foldOrder
    }
}

// MARK: - Outbox

/// A write that must reach Supabase, durably queued until it does.
///
/// ── WHY AN OUTBOX AND NOT A RETRY IN THE VIEW MODEL ─────────────────────────
/// Finishing a workout is the one action in this app that must never be lost.
/// The web app arrived at the same shape — its react-query persister dehydrates
/// exactly one mutation, the session commit, keyed by an idempotent
/// `clientSessionId` — and it got there after the naive version failed on a
/// train. A queue in a table survives the process being killed; a retry loop in
/// memory does not, and iOS kills backgrounded apps routinely.
///
/// `idempotencyKey` is what makes a retry safe: the server may already have
/// applied a request whose response never arrived.
public struct OutboxItem: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "outbox"

    public enum Status: String, Codable, Sendable {
        case pending
        case inFlight = "in_flight"
        case failed
    }

    public var id: String
    /// What this write is, e.g. `session.commit`. A string rather than an enum so
    /// an old queued item from a previous build still decodes after a new kind is
    /// added — a queue that fails to decode is a queue that loses the workout.
    public var kind: String
    public var payload: Data
    public var idempotencyKey: String
    public var createdAt: Date
    public var attempts: Int
    public var lastError: String?
    public var status: Status
    /// The earliest moment this item may be tried again. `nil` means now.
    ///
    /// Written by `outboxFailed` from `SyncBackoff`, read by `claimOutbox`. It
    /// is what stops a write the server will never accept from being retried at
    /// full speed on every drain for the life of the install.
    public var nextAttemptAt: Date?

    /// Snake_case like every other table here. The outbox is local-only, so the
    /// names are a free choice — but a store where some tables are snake_case
    /// and one is not is a store where you check before writing a query.
    public enum CodingKeys: String, CodingKey {
        case id
        case kind
        case payload
        case idempotencyKey = "idempotency_key"
        case createdAt = "created_at"
        case attempts
        case lastError = "last_error"
        case status
        case nextAttemptAt = "next_attempt_at"
    }

    public init(
        id: String = newOnyxID(),
        kind: String,
        payload: Data,
        idempotencyKey: String,
        createdAt: Date = Date(),
        attempts: Int = 0,
        lastError: String? = nil,
        status: Status = .pending,
        nextAttemptAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
        self.attempts = attempts
        self.lastError = lastError
        self.status = status
        self.nextAttemptAt = nextAttemptAt
    }
}
