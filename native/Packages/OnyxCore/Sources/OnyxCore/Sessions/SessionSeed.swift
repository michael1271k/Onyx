import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The session seed — what a day's deck opens with, and where every number in it
// came from. A port of the web app's `lib/sessions/sessionSeed.ts`; vectors
// `session-seed.json` and `sessions-for-seed.json`.
//
// This replaces `LoggerModel.seedRows`, which seeded every row from
// `ProgramExercise.wk1Kg` — a load chosen in July — and printed
// `"<wk1Kg>kg × <floor>"` as the Previous column. After six months of training
// that is not a seed, it is a number with the shape of one.
//
// THE TIERS, HIGHEST FIRST:
//   1. HISTORY — the newest qualifying session that logged this movement (see
//      `sessionsForSeed`), reproduced set for set.
//   2. TEMPLATE — `routine_templates.payload`, the shape of the last deck
//      committed for this day. It carries no date, so it is a shape and not a
//      memory: consulted only when history has nothing.
//   3. PROGRAM — `wk1Kg` at the rep floor. The cold start.
//
// AND WHY HISTORY IS MATCHED BY NAME, NEVER BY `exercise_id`: web-logged sets
// carry the catalogue's uuid; this phone writes `"onyx-<slug>"`
// (`ExerciseSlug.id`). The Sept 6 Upper A session was logged on the web, so any
// seed that indexes history by id finds zero rows for it and falls through to
// the cold start — which looks exactly like "this movement is new" and is not.
// The id is resolved to a display name by the caller
// (`PrRecorder.nameResolver`) and canonicalised in here.
// ─────────────────────────────────────────────────────────────────────────────

/// A candidate previous session. One row of `workout_sessions`, narrowed.
public struct SeedSession: Codable, Sendable, Equatable {
    public var id: String
    public var dayKey: String?
    /// The session's logical day, ISO.
    public var date: String
    /// Any string that sorts chronologically — `started_at` does.
    public var startedAt: String
    /// Was this session logged under the maintenance lever?
    ///
    /// Resolved by the CALLER (`Levers.leverForDate` / `Maintenance`), not in
    /// here: the answer depends on `user_goals.active_lever` and
    /// `maintenance_until`, which are rows, and a pure rule that reads rows is
    /// a rule that cannot be put in a vector.
    public var maintenance: Bool

    public init(id: String, dayKey: String?, date: String, startedAt: String, maintenance: Bool) {
        self.id = id
        self.dayKey = dayKey
        self.date = date
        self.startedAt = startedAt
        self.maintenance = maintenance
    }
}

/// One logged set of a candidate session, already name-resolved.
public struct SeedSet: Codable, Sendable, Equatable {
    public var sessionId: String
    /// The stored display name — canonicalised in here. NEVER an id.
    public var exerciseName: String
    /// Performed order within the session (`set_number` / `set_index`).
    public var order: Int
    public var weightKg: Double
    public var reps: Int
    public var rpe: Double?
    public var setType: String?
    public var side: String?
    public var pairId: String?
    /// ── THE CONTENT OF A BOUT, WHICH IS NOT WEIGHT AND REPS (W2) ────────────
    /// A treadmill set's entire content is `duration_sec`, `incline` and
    /// `distance_km`; its `weight_kg` and `reps` are the non-nil ZEROS
    /// `withWarmupCardio` mints. Carried nowhere, a seeded bout came back to the
    /// deck as a lift of nothing — `SetRow.isCardio` false, so the card drew no
    /// Cardio tag, `primaryMuscle`'s row test found nothing to fall back to, and
    /// `withWarmupCardio` could not see that the deck already held a treadmill.
    /// The note in `withWarmupCardio` named "SeedRow has no such fields" as the
    /// cause; these are the fields.
    public var durationSec: Int?
    public var incline: Double?
    public var distanceKm: Double?

    public init(
        sessionId: String, exerciseName: String, order: Int,
        weightKg: Double, reps: Int, rpe: Double? = nil,
        setType: String? = nil, side: String? = nil, pairId: String? = nil,
        durationSec: Int? = nil, incline: Double? = nil, distanceKm: Double? = nil
    ) {
        self.sessionId = sessionId
        self.exerciseName = exerciseName
        self.order = order
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.setType = setType
        self.side = side
        self.pairId = pairId
        self.durationSec = durationSec
        self.incline = incline
        self.distanceKm = distanceKm
    }
}

/// A `.ready` progression verdict for one movement on this day.
public struct SeedProgression: Codable, Sendable, Equatable {
    public var name: String
    /// The load the verdict recommends. Nil (a bodyweight `ready`) does nothing.
    public var suggestKg: Double?

    public init(name: String, suggestKg: Double?) {
        self.name = name
        self.suggestKg = suggestKg
    }
}

/// The seed's view of one `routine_templates` exercise — the fields it reads,
/// nothing more. `RoutineTemplateRow.payload` decodes into this.
public struct SeedTemplateSet: Codable, Sendable, Equatable {
    public var weightKg: Double
    public var reps: Int
    public var rpe: Double?
    public var setType: String?

    public enum CodingKeys: String, CodingKey { case weightKg, reps, rpe, setType }

    public init(weightKg: Double, reps: Int, rpe: Double? = nil, setType: String? = nil) {
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.setType = setType
    }
}

public struct SeedTemplateExercise: Codable, Sendable, Equatable {
    public var name: String
    public var order: Int
    public var sets: [SeedTemplateSet]

    public init(name: String, order: Int, sets: [SeedTemplateSet]) {
        self.name = name
        self.order = order
        self.sets = sets
    }
}

public struct SeedTemplate: Codable, Sendable, Equatable {
    public var exercises: [SeedTemplateExercise]
    public init(exercises: [SeedTemplateExercise]) { self.exercises = exercises }
}

public enum SeedSource: String, Codable, Sendable {
    case history, template, program
}

public struct SeedRow: Codable, Sendable, Equatable {
    /// The only two kinds a seed can produce. A failure or a drop set is
    /// something you decide in the moment, never something proposed for you.
    public enum Kind: String, Codable, Sendable { case normal, warmup }

    public var kind: Kind
    public var weightKg: Double?
    public var reps: Int?
    /// The remembered rating, or nil when there is none to carry.
    public var rpe: Double?
    /// True when a rating was DROPPED because the seeded work is harder — the
    /// "rate this" pip. See `RpeMemory.resolveSeededRpe`.
    public var rpeStale: Bool
    /// The set this row is seeded from, pre-formatted: `"47kg × 12"`. Nil when
    /// nothing was logged, which is the only honest answer for a cold start.
    public var previous: String?
    /// This row carries a progression bump — the chip.
    public var progressed: Bool
    /// What a BOUT is made of. Nil on every lifted row, which is what they are
    /// on a lifted set — `SeedSet`'s own note says why they have to travel.
    public var durationSec: Int?
    public var incline: Double?
    public var distanceKm: Double?
}

public struct SeedExercise: Codable, Sendable, Equatable {
    /// Canonical name, as the program spells it.
    public var name: String
    public var source: SeedSource
    /// The date the rows came from; nil for the template and program tiers.
    public var seededFrom: String?
    public var rows: [SeedRow]
}

public struct SessionSeed: Codable, Sendable, Equatable {
    public var dayKey: String
    public var exercises: [SeedExercise]
}

/// The bout a deck may open with — the athlete's OWN warm-up, repeated.
///
/// ── WHY IT IS NOT A PROGRAM ENTRY ───────────────────────────────────────────
/// `ProgramExercise` describes sets, reps and a load. A five-minute walk at 2 %
/// has none of those and all of its content — `durationSec`, `distanceKm`,
/// `inclinePct` — is in fields the program type does not have. Putting it in a
/// deck would also make it count: `plannedSets` is the program's own sum, so
/// the header would read `0/13` on a twelve-set day and the progression engine
/// would start grading a walk.
///
/// It is logged as a WARM-UP, which keeps it out of tonnage, out of
/// `workingSets` and out of the PR engine.
///
/// ── AND IT IS NOT TICKED FOR YOU ────────────────────────────────────────────
/// The deck proposes; the athlete confirms. Every other row in the session
/// works that way, and a session that recorded five minutes of walking nobody
/// did would be a worse bug than the missing row this replaces.
///
/// ── WHAT USED TO BE HERE, AND WHY IT IS GONE ────────────────────────────────
/// Three constants: `durationSec = 300`, `distanceKm = 0.37`, `inclinePct = 2`.
/// They were ONE athlete's treadmill warm-up, prepended to the first session of
/// every account that ever opened the app — five minutes of a machine the
/// reader may not own, at a gradient nobody chose, under a movement name that
/// was not theirs. (A fourth, a note reading "Pace rising 4.3 to 5.0", died
/// earlier for the same reason.) The gate in front of them was a catalogue
/// test: prescribe the walk only to somebody whose exercise list already held
/// a Treadmill. That kept the numbers off a new account and left them exactly
/// as arbitrary for the account they did reach.
///
/// The opener is now `seed(from:)` over the athlete's last logged `cardio_logs`
/// row. No bout, no opener; a bout, and the deck proposes THAT one back.
public enum WarmupCardio {

    /// The LEGACY catalogue row's name — the slug `onyx-treadmill` resolves
    /// off it, and the founder's uploaded treadmill sets are filed under it.
    ///
    /// It is NOT the opener's name any more. That comes from the bout being
    /// repeated, so a person who cycles gets a card that says so.
    public static let name = "Treadmill"

    /// How long an opener may be: three hours — a SANITY ceiling, not a
    /// warm-up length (Precision A2, Q5).
    ///
    /// It was ten minutes, on the argument that the opener is a warm-up and a
    /// forty-minute run is a different workout. What it actually did was
    /// pro-rate the founder's last OUTDOOR walk — 24 min, 2.69 km — into a
    /// "1 km / 10 min" treadmill bout nobody had ever done. The source is now
    /// the last TREADMILL bout (`LoggerModel.lastBout`), and a treadmill bout
    /// is proposed back exactly as it was performed. Only a duration no
    /// warm-up could have — a watch left recording — is cut, its distance with
    /// it, so the pace the card prints stays the pace that was actually walked.
    public static let maxSeconds = 10_800

    /// One bout, in the units a deck prescribes in.
    public struct Bout: Sendable, Equatable {
        /// What to call the card. The athlete's own kind, not a movement name
        /// from somebody else's gym.
        public var name: String
        public var durationSec: Int
        public var distanceKm: Double?
        public var inclinePct: Double?

        public init(name: String, durationSec: Int, distanceKm: Double? = nil, inclinePct: Double? = nil) {
            self.name = name
            self.durationSec = durationSec
            self.distanceKm = distanceKm
            self.inclinePct = inclinePct
        }
    }

    /// The opener a deck proposes, from the athlete's last logged bout.
    ///
    /// nil for nil, and nil for a bout with no duration on it — a `cardio_logs`
    /// row can carry energy and nothing else (a HealthKit import with no
    /// distance and no time), and a prescription of zero minutes is not a
    /// prescription. A first session then opens with no warm-up at all, which
    /// is the correct answer for somebody who has never logged one.
    public static func seed(from lastBout: Bout?) -> Bout? {
        guard let bout = lastBout, bout.durationSec > 0 else { return nil }
        guard bout.durationSec > maxSeconds else { return bout }
        let scale = Double(maxSeconds) / Double(bout.durationSec)
        return Bout(
            name: bout.name,
            durationSec: maxSeconds,
            // Two decimals, because the card prints kilometres and a scaled
            // 1.6666666 is not a distance anybody walked.
            distanceKm: bout.distanceKm.map { ($0 * scale * 100).rounded() / 100 },
            inclinePct: bout.inclinePct
        )
    }

    /// Whether a deck already opens with cardio, by the same test the row
    /// itself uses (`SetRow.isCardio`): time, distance or gradient rather than
    /// reps and kilograms. Matching on the NAME would miss a bike or a rower
    /// somebody put at the top, and then prepend a second warm-up above it.
    public static func isCardio(durationSec: Int?, distanceKm: Double?, inclinePct: Double?) -> Bool {
        durationSec != nil || distanceKm != nil || inclinePct != nil
    }
}

public enum SessionSeedBuilder {

    /// The sessions a seed — and the progression verdict — may look at, newest
    /// first.
    ///
    /// ── THE THREE FILTERS ───────────────────────────────────────────────────
    /// `day_key` — the rep ceiling and the set count come from the ROUTINE DAY,
    /// not from the movement: Leg Press is 8–12 on Legs A and 12–15 on Legs B.
    /// A session with no day key cannot be attributed to a routine and is
    /// dropped, never pooled.
    ///
    /// `era` — a session from the previous program is not comparable, and a new
    /// block must not inherit the old one's loads.
    ///
    /// `maintenance` — decision 6. A maintenance week is deliberately lighter,
    /// so seeding the week after one from it hands you a target below what you
    /// were lifting a fortnight ago and calls it Previous.
    ///
    /// `AppDatabase.progressionQueue` reads the same list, so the verdict and
    /// the number it pre-fills can never be about different sessions.
    ///
    /// `planOwning` names the plan a date belongs to (`Schedule.planId(owning:)`):
    /// only sessions from TODAY's plan qualify, so a PPL-era Push never seeds
    /// an Onyx Upper A. It replaces the compiled era boundary (`Era.forDate`).
    public static func sessionsForSeed(
        _ sessions: [SeedSession], dayKey: String, today: String, planOwning: (String) -> String
    ) -> [SeedSession] {
        let plan = planOwning(today)
        return sessions
            .filter { $0.dayKey == dayKey && !$0.maintenance && planOwning($0.date) == plan }
            .sorted { a, b in
                if a.date != b.date { return a.date > b.date }
                if a.startedAt != b.startedAt { return a.startedAt > b.startedAt }
                return a.id < b.id
            }
    }

    /// `"47kg × 12"` — the previous column, as the row prints it.
    public static func previousLabel(weightKg: Double, reps: Int) -> String {
        "\(formatKg(weightKg))kg × \(reps)"
    }

    /// `47`, `49.5`, `13.75` — never `49.50`, never `13.8`. `String(v)` in
    /// JavaScript, which is what the twin builds this label with.
    static func formatKg(_ value: Double) -> String {
        jsIntegerString(jsRound(value * 100) / 100)
    }

    /// One session's rows for one movement, pairs collapsed, in performed order.
    ///
    /// A genuine L/R pair is TWO rows sharing a `pair_id`, and it is ONE set of
    /// work at the weaker side — `min(weight) × min(reps)`, the rule
    /// `SessionVolume.sessionVolumeKg` already scores it by, so a set logged
    /// split seeds exactly what the same set seeds logged unsided. A lone side,
    /// or a bucket that is not exactly one L and one R, is left as the rows it
    /// is: inventing a partner for it would be inventing work.
    ///
    /// ── ONE DIVERGENCE FROM `sessionVolumeKg`, AND IT IS DELIBERATE ────────
    /// That function's comment says a malformed 3+ bucket is scored "each row
    /// as logged", and its code does not: `if let left, let right` takes the
    /// fold branch for two Ls and an R and silently drops the third row's
    /// tonnage. This requires a bucket of exactly two, so it does what that
    /// comment describes. The two agree on every well-formed pair — all the
    /// live data has — and differ only on the malformed case both warn about.
    /// Fixing it there would move stored tonnage and needs its own recompute.
    ///
    /// `ghost` rows are dropped — a set deliberately not performed is not
    /// evidence.
    public static func collapsePairs(_ sets: [SeedSet]) -> [SeedSet] {
        let sorted = sets.filter { $0.setType != "ghost" }.sorted { $0.order < $1.order }

        var buckets: [String: [SeedSet]] = [:]
        for s in sorted { if let id = pairKey(s) { buckets[id, default: []].append(s) } }

        var done: Set<String> = []
        var out: [SeedSet] = []
        for s in sorted {
            guard let id = pairKey(s) else { out.append(s); continue }
            let bucket = buckets[id] ?? []
            let left = bucket.first { $0.side == "L" }
            let right = bucket.first { $0.side == "R" }
            guard bucket.count == 2, let left, let right else { out.append(s); continue }
            if done.contains(id) { continue }
            done.insert(id)
            var folded = s
            folded.weightKg = Swift.min(left.weightKg, right.weightKg)
            folded.reps = Swift.min(left.reps, right.reps)
            // The collapsed row is one set, not half of two.
            folded.side = nil
            folded.pairId = nil
            // The set is graded at the weaker side, so that is the rating that
            // describes it.
            folded.rpe = weakerSide(left, right).rpe
            out.append(folded)
        }
        return out
    }

    /// The pair id of a genuine two-sided row — a `pair_id` with no side, or a
    /// side with no `pair_id`, is an ordinary set.
    private static func pairKey(_ s: SeedSet) -> String? {
        guard let id = s.pairId, !id.isEmpty, s.side == "L" || s.side == "R" else { return nil }
        return id
    }

    private static func weakerSide(_ left: SeedSet, _ right: SeedSet) -> SeedSet {
        if left.weightKg != right.weightKg { return left.weightKg < right.weightKg ? left : right }
        return left.reps <= right.reps ? left : right
    }

    /// Build one day's seed.
    ///
    /// The DECK is the program's — its exercises, in its order, at its
    /// working-set count for the phase. History supplies the numbers, never the
    /// shape: a session where you did four sets instead of three does not
    /// silently reprogram the day.
    public static func build(
        dayKey: String,
        today: String,
        phase: ProgramPhase,
        sessions: [SeedSession],
        sets: [SeedSet],
        template: SeedTemplate? = nil,
        ready: [SeedProgression] = [],
        program: Program,
        planOwning: (String) -> String
    ) -> SessionSeed {
        guard let day = program.day(key: dayKey) else { return SessionSeed(dayKey: dayKey, exercises: []) }

        let ordered = sessionsForSeed(sessions, dayKey: dayKey, today: today, planOwning: planOwning)
        let known = Set(ordered.map(\.id))

        // (session, canonical name) → its rows. Only sessions that qualified.
        var bySession: [String: [String: [SeedSet]]] = [:]
        for s in sets where known.contains(s.sessionId) {
            bySession[s.sessionId, default: [:]][canon(s.exerciseName), default: []].append(s)
        }

        var templateByName: [String: SeedTemplateExercise] = [:]
        for e in template?.exercises ?? [] { templateByName[canon(e.name)] = e }
        var readyByName: [String: SeedProgression] = [:]
        for r in ready { readyByName[canon(r.name)] = r }

        // ── THE ORDER IS DELIBERATELY NOT APPLIED HERE ──────────────────────
        // `SeedTemplateExercise` carries `order` and this walks the program's
        // list instead, which looks like an oversight and is not: the seed's
        // shape is a SHARED contract with the web (`sessionSeed.ts`, vectors in
        // `session-seed.json`), and the template covers only the movements a
        // past session logged. Ranking a two-entry template against a
        // seven-movement day puts those two at the top of a deck neither client
        // asked to reorder.
        //
        // The stored order is applied where the DECK is assembled — see
        // `LoggerModel.inDeckOrder` and `AppDatabase.deckOrder(dayKey:userId:)`
        // — which is also the only place that knows the live deck, the one
        // thing that outranks a template mid-session.
        let exercises = day.exercises(for: phase).map { plan in
            seed(
                plan, phase: phase, ordered: ordered, bySession: bySession,
                templateByName: templateByName, readyByName: readyByName, program: program
            )
        }
        return SessionSeed(dayKey: dayKey, exercises: exercises)
    }

    // MARK: - One movement

    private static func seed(
        _ plan: ProgramExercise,
        phase: ProgramPhase,
        ordered: [SeedSession],
        bySession: [String: [String: [SeedSet]]],
        templateByName: [String: SeedTemplateExercise],
        readyByName: [String: SeedProgression],
        program: Program
    ) -> SeedExercise {
        let name = ExerciseAliases.canonicalName(plan.name)
        let key = canon(plan.name)
        let prescribed = plan.sets(for: phase)
        let floor = Ceilings.parseRepWindow(plan.reps).map { Int($0.floor) }
        let bump = readyByName[key]?.suggestKg

        // ── TIER 1: the newest qualifying session that logged THIS movement ──
        // Newest-first over the whole qualifying list rather than "the last
        // session" alone: a lift you skipped last week has not become a new
        // movement, and falling back to `wk1Kg` for it would say that it had.
        for session in ordered {
            guard let raw = bySession[session.id]?[key], !raw.isEmpty else { continue }
            let rows = collapsePairs(raw)
            let warmups = rows.filter { $0.setType == "warmup" }
            let working = rows.filter { SetTags.isWorkingSet($0.setType) }
            // ── A SESSION WITH NO WORKING SETS IS NOT EVIDENCE ─────────────
            // You warmed up and stopped. Committing to the history tier on
            // that would return the warm-up and NOTHING else — `workingRows`
            // has no row to repeat, so it produces none — and the day would
            // open with zero of the sets the program prescribes, having
            // silently refused to fall through to the template or the cold
            // start. Walk back to a session that actually lifted.
            guard !working.isEmpty else { continue }
            return SeedExercise(
                name: name, source: .history, seededFrom: session.date,
                // Warm-ups are carried, in the order they were performed. A
                // warm-up you did last time is a warm-up you will do again, and
                // it is not one of the sets the program counts — `prescribed`
                // is working sets only.
                rows: warmups.map {
                    row(.warmup, $0.weightKg, $0.reps, nil, previousLabel(weightKg: $0.weightKg, reps: $0.reps), false, $0)
                } + workingRows(working, prescribed: prescribed, floor: floor, bump: bump)
            )
        }

        // ── TIER 2: the stored template ──────────────────────────────────────
        let tplRows = (templateByName[key]?.sets ?? [])
            .filter { $0.setType != "ghost" }
            .map { s -> SeedRow in
                let working = SetTags.isWorkingSet(s.setType)
                let bumped = bump != nil && working
                return row(
                    s.setType == "warmup" ? .warmup : .normal,
                    bumped ? bump : s.weightKg,
                    bumped ? (floor ?? s.reps) : s.reps,
                    seedOf(weightKg: s.weightKg, reps: s.reps, rpe: s.rpe, setType: s.setType),
                    // A template is a shape, not a memory — it carries no date,
                    // so there is no session for a Previous column to be about.
                    nil,
                    bumped
                )
            }
        if !tplRows.isEmpty {
            return SeedExercise(name: name, source: .template, seededFrom: nil, rows: tplRows)
        }

        // ── TIER 3: the program's cold start ─────────────────────────────────
        _ = program
        return SeedExercise(
            name: name, source: .program, seededFrom: nil,
            rows: (0..<Swift.max(0, prescribed)).map { _ in
                // ── A MISSING SEED LOAD IS NIL, NOT ZERO ────────────────────
                // `wk1Kg` is nil for a bodyweight or timed movement, and nil
                // there means "the program prescribes no load" — not "0 kg".
                // The deck renders the two differently, and `Epley`, double
                // progression and every "0 kg × 17" label turn on the same
                // distinction. Each client coerces at its own boundary.
                row(.normal, bump ?? plan.wk1Kg, floor, nil, nil, bump != nil)
            }
        )
    }

    /// The working rows, filled by INDEX against the program's count.
    ///
    /// Short history (you did two sets, the program asks for three) repeats the
    /// last known LOAD at the rep FLOOR — the honest proposal for a set with no
    /// precedent, and what `addSet` already does in the logger. Long history is
    /// truncated: the deck is the plan, and a fourth set is added in the moment,
    /// not proposed.
    ///
    /// A `ready` verdict rewrites every working row to the suggested load at the
    /// floor, which is what makes the rating go stale and the chip appear.
    private static func workingRows(
        _ history: [SeedSet], prescribed: Int, floor: Int?, bump: Double?
    ) -> [SeedRow] {
        var out: [SeedRow] = []
        for i in 0..<Swift.max(0, prescribed) {
            guard let src = i < history.count ? history[i] : history.last else { break }
            let carried = i >= history.count
            out.append(row(
                .normal,
                bump ?? src.weightKg,
                // A timed hold has no rep floor to fall back to; repeat what
                // was held.
                bump != nil || carried ? (floor ?? src.reps) : src.reps,
                seedOf(weightKg: src.weightKg, reps: src.reps, rpe: src.rpe, setType: src.setType),
                previousLabel(weightKg: src.weightKg, reps: src.reps),
                bump != nil,
                src
            ))
        }
        return out
    }

    /// The RPE seed a source row leaves behind. Warm-ups are never rated.
    private static func seedOf(weightKg: Double, reps: Int, rpe: Double?, setType: String?) -> RpeSeed? {
        guard let rpe, rpe.isFinite, SetTags.isWorkingSet(setType) else { return nil }
        return RpeSeed(rpe: rpe, weightKg: weightKg, reps: Double(reps))
    }

    /// A seeded row, with the rating resolved against the numbers it opens on.
    private static func row(
        _ kind: SeedRow.Kind, _ weightKg: Double?, _ reps: Int?,
        _ seed: RpeSeed?, _ previous: String?, _ progressed: Bool,
        _ bout: SeedSet? = nil
    ) -> SeedRow {
        let resolved = RpeMemory.resolveSeededRpe(seed, weightKg: weightKg ?? 0, reps: Double(reps ?? 0))
        return SeedRow(
            kind: kind, weightKg: weightKg, reps: reps,
            rpe: resolved.rpe, rpeStale: resolved.stale,
            previous: previous, progressed: progressed,
            // Only the HISTORY tier can carry these: a template row and the
            // program's cold start describe sets and reps and have no bout in
            // them to copy. Nil there is the honest answer, not a gap.
            durationSec: bout?.durationSec, incline: bout?.incline, distanceKm: bout?.distanceKm
        )
    }

    private static func canon(_ name: String) -> String {
        ExerciseAliases.canonicalName(name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
