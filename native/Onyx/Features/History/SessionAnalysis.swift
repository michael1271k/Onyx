import Foundation
import OnyxCore
import OnyxData
import OnyxUI

/// Rows in, OnyxCore results out — the glue between the ledger and the
/// Workout Analysis screens. NO arithmetic lives here: every number is
/// `SessionVolume`, `PrEngine`, `SessionDetail`, `Ceilings`, `MuscleCredit` or
/// `Epley`, each of which is held to the TypeScript by golden vectors. What
/// this file decides is which rows go in and in what order, which is the part
/// the web app's `lib/sessions/save.ts` and `useSessionDetail.ts` get right and a
/// re-implementation would get wrong.
///
/// ── HOW PR DETECTION SELECTS ROWS (mirrors `save.ts`) ───────────────────────
/// The KEY is the exercise id. Baselines are every earlier set of the session's
/// own exercises, carrying `set_type`, `side`, `pair_id` and the stored
/// `est_1rm_kg`; the rep floor is the programmed window for THIS session's
/// day key; `floorFor` is the session-less `personal_records` floor through
/// the canonical name; `isTimed` is `TimedExercise.isTimed` through the same
/// name. Candidates are the session's sets in performed order with `date`,
/// `exerciseName` and `setNumber`. Sides are mapped
/// `left`/`right` → `L`/`R` at the boundary (`HistorySetRow.lr`).
enum SessionAnalysis {

    // MARK: - Shapes

    struct Summary: Identifiable, Sendable {
        let id: String
        let date: String
        let dayKey: String?
        let durationMin: Double?
        /// Working sets, a unilateral pair counted once.
        let sets: Int
        let tonnageKg: Double
        let prCount: Int
        /// ── THE THREE COLUMNS THIS SUMMARY ONLY NOW CARRIES (§W2 B) ─────
        /// Every cell of the session page's metric grid draws eight weeks of
        /// itself behind its figure, and `summaries` is the one walk that has
        /// every session of the split in hand. These three are columns already
        /// on the `WorkoutSession` row it is iterating, so carrying them costs
        /// no query at all — and deriving them anywhere else would mean a
        /// second walk of the ledger with its own idea of which sessions count.
        ///
        /// `calories` is the STORED figure only. The page falls back to a MET
        /// estimate for the cell's own value; a trail mixing measured burns
        /// with estimated ones would be a curve of two different quantities.
        /// Defaulted, unlike the six above: these three are drawn behind a
        /// figure and nothing is computed FROM them, so a caller assembling a
        /// summary by hand (a test, a fixture) should not have to supply three
        /// readings to ask a question about a seventh.
        var sessionRpe: Double? = nil
        var avgBpm: Double? = nil
        var calories: Double? = nil

        /// `durationMin`, but only when the clock can be believed.
        ///
        /// ── WHY A STORED DURATION NEEDS A SANITY TEST AT ALL ────────────────
        /// `duration_min` is derived at close from `ended_at − started_at −
        /// paused`, and a close that ran against a clock that had already been
        /// stopped writes a number with no relationship to the workout. The
        /// 2026-09-03 Upper B session is the case: twelve sets and 3,108 kg,
        /// stored as TWO MINUTES, with `ended_at` 120 s after `started_at` — so
        /// cross-checking the timestamps does not catch it either, they are
        /// corrupt together.
        ///
        /// What that cost was not a wrong duration on its own page (which is at
        /// least visibly absurd) but a wrong DELTA on the next one: 2026-09-10
        /// read "74 min, +72", and a reader has no way to tell that the +72 is
        /// an artefact of the session before rather than a claim about this
        /// one. A number that is silently wrong somewhere else is worse than a
        /// reserved blank line, which is what the page draws for a nil.
        ///
        /// The test is the one physical constraint available from data already
        /// on the row: a recorded set takes time. Sessions on record run
        /// 46–76 minutes over 12–22 sets — 150 s per set at the tightest — so
        /// a floor of 20 s clears every real session by a factor of seven and
        /// still rejects twelve sets in two minutes.
        ///
        /// ponytail: one constant, chosen against the whole ledger. If a
        /// genuinely fast session ever trips it, raise the seconds-per-set
        /// here — do not add a second rule beside it.
        var credibleDurationMin: Double? {
            guard let durationMin, durationMin > 0 else { return nil }
            guard durationMin * 60 >= Double(sets) * Self.minSecondsPerSet else { return nil }
            return durationMin
        }

        /// The tightest seconds-per-set any real session has come to, divided
        /// by seven. See `credibleDurationMin`.
        static let minSecondsPerSet: Double = 20
    }

    struct ExerciseReport: Identifiable {
        var id: String { detail.exerciseId }
        let detail: DetailExercise
        let canonical: String
        let timed: Bool
        /// This session's sets, and ONLY this session's.
        ///
        /// ── WHY THIS IS NO LONGER `[RowWithPrev]` ───────────────────────────
        /// Each row used to carry the positionally-matched set from the last
        /// time this movement was trained, and `SetRow` printed it inline as
        /// `prev 5kg × 15`. On the post-workout page that is the wrong fact in
        /// the wrong place: the reader has just finished the workout and is
        /// looking at what they did, and half of every row was about a
        /// different day. It also read as a set that had been performed today
        /// — most visibly on Single Arm Lateral Raise, where a four-set
        /// movement showed eight numbers.
        ///
        /// The comparison itself is not lost, it moves to where it was always
        /// the point: the header's `vs 30 Aug` capsule, which is computed from
        /// `previousSets` — the previous session's WHOLE list, so a cut set
        /// changes the verdict. That is the honest comparison; the positional
        /// one never was (`rowsWithPrev` drops any previous set past this
        /// session's count).
        ///
        /// `SessionDetail.rowsWithPrev` stays in OnyxCore: the web ledger is
        /// still built on it and the golden vectors still hold the two to each
        /// other. This screen simply no longer calls it.
        let rows: [DetailRow]
        let prevDate: String?
        /// The previous session's WORKING sets, whole.
        ///
        /// `rows` carries them too, but positionally — one beside each of this
        /// session's numbered rows, and any past that count is dropped. A
        /// comparison built from those is wrong in exactly the case it matters
        /// (a set was cut), so the honest list travels separately.
        let previousSets: [HistorySet]
        let cue: ProgressionCue?
        let stats: ExerciseStats
        /// "10–12" / "55s", or nil when the program does not prescribe it.
        let window: String?
        /// Working sets that reached the programmed ceiling, and how many there
        /// were. `2/3 @ ceiling` on the ledger header — the reading the
        /// double-progression rule is actually about.
        let atCeiling: Int
        /// Session-mean estimated 1RM across every session of this movement,
        /// oldest first, DATED.
        ///
        /// ── THE DATES ARE BACK, AND FOR A CHART RATHER THAN A LABEL (W10) ───
        /// This was `[Double]` and the header said so: "a sparkline has no
        /// axis, so carrying the dates would invite a label". The sparkline
        /// still has no axis and still takes `spark` below. What changed is
        /// that the trail is now a DOOR — tapping it opens `E1rmTrendChart`,
        /// the same plotted, scrubbable chart the exercise's own page draws
        /// (`ExerciseDetailView:159`) — and a chart without dates is a chart
        /// with nothing to put on its x axis.
        ///
        /// `sessionMeanE1rm` has always returned the pairs and this line always
        /// threw half of them away; the sheet is the reader they were computed
        /// for. Nothing about the 56×16 graphic moves.
        let trail: [(date: String, kg: Double)]
        /// The trail's values alone — the 56×16 sparkline in the header.
        ///
        /// Computed, not stored, so the graphic and the chart behind it cannot
        /// come to be built from two different reads of the same history.
        var spark: [Double] { trail.map(\.kg) }
        /// What each record-setting set actually BEAT, keyed by the set's own
        /// `set_index` (`DetailSet.setNumber`).
        ///
        /// ── WHY THIS CANNOT BE READ BACK OUT OF `personal_records` ──────────
        /// The ledger is upsert-on-conflict: the write that files a record
        /// destroys the value it beat, and a record beaten again next month is
        /// filed against a different session entirely. The only place the PAIR
        /// survives is `PrEngine`'s `AxisRecord`, captured BEFORE the winner is
        /// folded into the index — which `detect` already computes here and
        /// used to throw away, keeping only the axis NAMES for the trophy.
        ///
        /// So the summary could draw gold and could not say what the gold was
        /// worth, while the live deck (`LivePrEngine` → `PrRecordSheet`) has
        /// printed both numbers since E4. Same engine, same sheet, one set of
        /// numbers: this is the field that lets the post-workout page open it.
        ///
        /// Keyed on the SET rather than the row because a unilateral pair is
        /// two `DetailSet`s under one `DetailRow`, and the record belongs to
        /// whichever side completed it.
        let records: [Int: [LivePrRecord]]
        /// MEASURED rest before each set, in seconds, keyed by the set's own
        /// `set_index` — `WorkoutSet.actual_rest_sec`, as the logger clocked it.
        ///
        /// ── WHY IT IS A SIDE TABLE AND NOT A FIELD ON `DetailSet` ───────────
        /// `DetailSet` lives in OnyxCore and is the shape the golden vectors
        /// are written in (`GoldenVector.swift:20-26` — never regenerated). A
        /// new key on it is a new key in every one of them, for a number the
        /// domain does not compute with: rest reaches no score, no PR axis and
        /// no tonnage. `records` one field up made the same call for the same
        /// reason and this joins it, keyed the same way.
        ///
        /// Sparse and usually EMPTY. Only the append path measures a rest
        /// (`LoggerModel.snapshot(_:in:actualRestSec:)`); an amend rebuilds the
        /// row and does not, a set logged on the watch carries none, and every
        /// row written before the column existed has none. Absent is "not
        /// measured", which is what the ledger draws as nothing at all.
        let rest: [Int: Int]
    }

    struct TrailSeries: Identifiable {
        let id: String
        let points: [(date: String, kg: Double)]
    }

    struct Report {
        let session: WorkoutSession
        let exercises: [ExerciseReport]
        /// Weighted sets per landmark, descending, untrained muscles absent.
        let muscles: [(muscle: LandmarkMuscle, sets: Double)]
        /// Every performed set's effort, in the order the session performed
        /// them — the shape of how hard it got.
        ///
        /// ── WHY SETS AND NOT MINUTES ────────────────────────────────────────
        /// `workout_sets` carries no timestamp this page can read
        /// (`HistorySetRow` selects what the ledger draws, and `created_at` is
        /// not in it), so a true clock axis would mean widening the store's
        /// select for one decoration. The session's own ORDER is already here
        /// and is the axis that answers the question anyway: an eight-set
        /// opener at RPE 6 followed by four at 9.5 is the same fingerprint
        /// whether it took fifty minutes or seventy.
        ///
        /// Nil is an unrated set, which is a real state and not a zero.
        let intensity: [Double?]
        /// The muscles some movement in this session names as a PRIMARY mover,
        /// heaviest-worked first.
        ///
        /// ── WHY THE HEADER NEEDS THE DISTINCTION AND THE CHART DOES NOT ─────
        /// `muscles` is what the session TRAINED, assistance included at half
        /// credit — which is the honest input to the Muscle focus card and to
        /// the atlas figure, where a share is drawn and a small one reads as
        /// small. In the header it is a flat list of capsules with no share on
        /// them, so a chest day printed `Chest · Triceps · Front delts · Abs ·
        /// Side delts · Upper back` and the two muscles the session was FOR
        /// looked exactly like the four that came along. The header takes the
        /// primaries; the card keeps the whole truth.
        ///
        /// ── AND WHY IT IS ORDERED ON RAW SETS, NOT ON `muscles`' ORDER ──────
        /// `muscles` ranks on WEIGHTED sets, where an assisting mover earns
        /// partial credit — correct for a share, wrong for a headline. The
        /// header answers "what did I train today", and the honest ranking for
        /// that is the count of working sets whose movement names the muscle as
        /// the point: twelve leg sets put Quads above four core sets, and a
        /// muscle can never climb the list on work it merely helped with.
        ///
        /// Equal counts break on the TONNAGE behind them rather than
        /// alphabetically, which is what the old sort fell back to — three leg
        /// muscles at eight sets each were ordered G, H, Q by the letter.
        ///
        /// Built here, in the loader, and off the main actor with everything
        /// else on this type: the view receives an array and sorts nothing.
        let primaryOrder: [LandmarkMuscle]
        let prCount: Int
        /// Every set that was performed, ghosts excluded, a unilateral pair
        /// counted once — the denominator the muscle sheet's weighted total is
        /// read against. NOT `sets`, which is working sets only: warm-ups earn
        /// muscle credit and would otherwise make the two figures disagree.
        let physicalSets: Int
        /// Σ of the movements' own tonnage, to the two decimals a real plate
        /// can reach.
        ///
        /// It used to be `jsRound(…)` — a whole number — over per-exercise
        /// figures that were themselves `jsRound`ed. Two roundings, and the
        /// second one is why a session the database records as 13,242.5 kg
        /// could not be printed as anything but 13,243 no matter what the
        /// formatter did. `SessionVolume.sessionVolumeKg` already ends at two
        /// decimals; this only clears the float dust of adding eight of them.
        var tonnageKg: Double { jsRound(exercises.reduce(0) { $0 + $1.detail.volumeKg } * 100) / 100 }
        var sets: Int { exercises.reduce(0) { $0 + Int($1.detail.workingSets) } }
    }

    // MARK: - The list

    /// One summary per session, newest first. PR counts come from replaying
    /// the ledger in order, so a record beaten last month still shows on the
    /// session that set it — `personal_records` is a current-best table and
    /// would not.
    // ponytail: baselines are rebuilt per session from that session's
    // exercises' history — O(sessions × their history). Fine at a few thousand
    // rows; an incremental index if the ledger ever reaches six figures.
    static func summaries(_ sessions: [WorkoutSession], ledger: [HistorySetRow], in ctx: Context) -> [Summary] {
        let bySession = Dictionary(grouping: ledger, by: \.sessionId)
        var history: [String: [HistorySetRow]] = [:]
        var out: [Summary] = []
        for session in sessions.reversed() {   // oldest first
            let rows = bySession[session.id] ?? []
            let groups = grouped(rows)
            let prior = groups.flatMap { history[$0.exerciseId] ?? [] }
            let pr = detect(groups: groups, prior: prior, dayKey: session.dayKey, date: session.date, in: ctx)
            for g in groups { history[g.exerciseId, default: []] += g.sets }
            let working = rows.filter { SetTags.isWorkingSet($0.setType) }
            out.append(Summary(
                id: session.id, date: session.date, dayKey: session.dayKey, durationMin: session.durationMin,
                sets: SessionDetail.toRows(working.map(detailSet)).filter { $0.num != nil }.count,
                // WORKING for the count, EVERY non-ghost row for the tonnage —
                // see `report`'s `volumeKg`. A history row and the session page
                // it opens disagreeing about the same workout's weight is the
                // same divergence, one screen earlier.
                tonnageKg: SessionVolume.sessionVolumeKg(rows.map(volumeSet)),
                prCount: pr.prCount,
                sessionRpe: session.sessionRpe,
                avgBpm: session.avgBpm.map(Double.init),
                calories: session.caloriesBurned.map(Double.init)
            ))
        }
        return out.reversed()
    }

    // MARK: - The report

    /// `cardio_logs` is deliberately NOT an input. It was, and the page drew a
    /// banner from it under the ledger — a second list, in a different shape,
    /// of rows that are not part of this workout (`AppDatabase.cardio` matches
    /// the session id OR the date, so any bout logged that day appeared). A
    /// treadmill bout that IS part of the session is a `workout_sets` row and
    /// comes through `rows` like every other movement.
    static func report(_ session: WorkoutSession, rows: [HistorySetRow], history: [HistorySetRow], in ctx: Context) -> Report {
        let groups = grouped(rows)
        // The ledger is in performed order, so "prior" is everything before
        // this session's first row — a same-day session is ordered by start.
        let cut = history.firstIndex { $0.sessionId == session.id } ?? history.endIndex
        let prior = Array(history[..<cut])
        let priorByEx = Dictionary(grouping: prior, by: \.exerciseId)
        let pr = detect(groups: groups, prior: prior, dayKey: session.dayKey, date: session.date, in: ctx)

        var exercises: [ExerciseReport] = []
        var i = 0   // index into pr.perSet, which is in `groups` order
        for (order, g) in groups.enumerated() {
            let canonical = displayName(id: g.exerciseId, stored: g.name)
            let timed = TimedExercise.isTimed(canonical)
            var sets: [DetailSet] = []
            var records: [Int: [LivePrRecord]] = [:]
            var rest: [Int: Int] = [:]
            for r in g.sets {
                let d = pr.perSet[i]; i += 1
                // Zero is not a measurement. `actual_rest_sec` is written from
                // the gap the logger clocked, and a 0 on the row is the first
                // set of a movement — nothing preceded it to rest from.
                if let seconds = r.actualRestSec, seconds > 0 { rest[r.setIndex] = seconds }
                var s = detailSet(r)
                s.isPr = !d.axes.isEmpty
                s.est1rmKg = d.est1rm
                s.prAxes = d.axes.map(\.rawValue)
                // The beaten baselines, in the shape `PrRecordSheet` already
                // takes. `d.records` holds only the axes that had a bar to
                // beat, which is the same omission the live deck makes: an
                // asserted record with no arithmetic behind it is a claim
                // without a delta, and the sheet prints deltas.
                let won = d.axes.compactMap { axis -> LivePrRecord? in
                    guard let mark = d.records[axis] else { return nil }
                    return LivePrRecord(
                        id: "\(g.exerciseId)|\(Int(s.setNumber))|\(axis.rawValue)",
                        exercise: canonical,
                        setLabel: "Set \(Int(s.setNumber))",
                        axis: axis, mark: mark
                    )
                }
                if !won.isEmpty { records[Int(s.setNumber), default: []] += won }
                sets.append(s)
            }
            let working = sets.filter { SetTags.isWorkingSet($0.setType) }
            let detail = CoreBridge.detailExercise(
                exerciseId: g.exerciseId, name: canonical, order: Double(order), sets: sets,
                workingSets: Double(SessionDetail.toRows(working).count),
                topKg: working.map(\.weightKg).max() ?? 0,
                // ── EVERY SET, NOT THE WORKING ONES ────────────────────
                // `SessionVolume`'s header states the rule and the header is
                // right: "A ghost weighs nothing; a warm-up still counts." It
                // already drops the ghosts, so pre-filtering to working sets
                // here was the caller overruling the rule — and `Report.
                // tonnageKg` sums these, so the session page reported 12,343 kg
                // for a workout `SessionEditing.totals`, `closeSession` and
                // `workout_sessions.total_volume_kg` all put at 13,242.5. The
                // gap was one 60 × 15 warm-up on the leg press.
                //
                // `topKg`, `bestEst1rm` and `workingSets` stay on `working`:
                // "Top" is a claim about the working sets and a warm-up must
                // not be allowed to win it.
                volumeKg: SessionVolume.sessionVolumeKg(sets.map { VolumeSet(weightKg: $0.weightKg, reps: $0.reps, side: $0.side, pairId: $0.pairId, setType: $0.setType) }),
                bestEst1rm: working.compactMap(\.est1rmKg).max(),
                prAxes: pr.axesByKey.first { $0.key == g.exerciseId }?.axes.map(\.rawValue)
            )

            // The previous time this movement was trained: its working sets,
            // one entry per PHYSICAL set (a pair is two entries), which is what
            // `rowsWithPrev` consumes.
            let prevSession = priorByEx[g.exerciseId]?.last?.sessionId
            let prevRows = (priorByEx[g.exerciseId] ?? []).filter { $0.sessionId == prevSession && SetTags.isWorkingSet($0.setType) }
            let prev = prevRows.map { HistorySet(weightKg: $0.weightKg, reps: Double($0.reps), rpe: $0.rpe, setType: $0.setType, side: $0.lr, pairId: $0.pairId) }

            // Double progression over the last two sessions, newest LAST.
            let ladder = [prevRows, g.sets.filter { SetTags.isWorkingSet($0.setType) }]
                .filter { !$0.isEmpty }
                .map { $0.map { WorkingSet(weightKg: $0.weightKg, reps: Double($0.reps)) } }
            let verdict: ProgressionVerdict
            let window: String?
            if timed {
                let target = Ceilings.holdTarget(for: canonical, dayKey: session.dayKey, program: ctx.program(on: session.date))
                verdict = Ceilings.timedProgressionVerdict(ladder, targetSec: target)
                window = target.map { "\(jsIntegerString($0))s" }
            } else {
                let w = Ceilings.repWindow(for: canonical, dayKey: session.dayKey, program: ctx.program(on: session.date))
                verdict = Ceilings.progressionVerdict(ladder, ceiling: w?.ceiling)
                window = w.map { "\(jsIntegerString($0.floor))–\(jsIntegerString($0.ceiling))" }
            }
            let cue = SessionDetail.progressionCue(
                CoreBridge.cueProgression(state: verdict.state.rawValue, ceiling: verdict.ceiling, suggestKg: verdict.suggestKg),
                timed: timed, unit: "kg", toDisplay: { $0 }
            )

            // The ceiling this session's sets were judged against — the same
            // number `verdict` used, so the header and the cue cannot disagree.
            let program = ctx.program(on: session.date)
            let ceiling: Double? = timed
                ? Ceilings.holdTarget(for: canonical, dayKey: session.dayKey, program: program)
                : Ceilings.repWindow(for: canonical, dayKey: session.dayKey, program: program)?.ceiling
            let workingRows = g.sets.filter { SetTags.isWorkingSet($0.setType) }
            let atCeiling = ceiling.map { c in workingRows.filter { Double($0.reps) >= c }.count } ?? 0

            exercises.append(ExerciseReport(
                detail: detail, canonical: canonical, timed: timed,
                rows: SessionDetail.toRows(sets),
                prevDate: prevRows.first?.date,
                previousSets: prev,
                cue: cue, stats: SessionDetail.exerciseStats(detail), window: window,
                atCeiling: atCeiling,
                trail: sessionMeanE1rm((priorByEx[g.exerciseId] ?? []) + g.sets),
                records: records,
                rest: rest
            ))
        }

        // Muscle focus: warm-ups count, ghosts do not, a pair is one set.
        let credit = MuscleCredit.weightedSets(groups.map { g in
            MuscleCredit.Contribution(physicalSets: physicalSets(g.sets), movers: MuscleMap.resolveMovers(g.name))
        })
        var muscles: [(muscle: LandmarkMuscle, sets: Double)] = []
        for (muscle, value) in credit {
            let sets = jsRound(value * 10) / 10
            if sets > 0 { muscles.append((muscle: muscle, sets: sets)) }
        }
        muscles.sort { a, b in a.sets != b.sets ? a.sets > b.sets : a.muscle.rawValue < b.muscle.rawValue }
        // Read from the same resolver the credit is: name first, the stored
        // column as a fallback (`MuscleMap.resolveMovers`), so the header and
        // the chart cannot disagree about what a movement is for.
        //
        // Two tallies per landmark, both over the movements this session
        // actually logged: the working sets it was the point of, and the
        // tonnage behind them. See `Report.primaryOrder` for why the count is
        // raw and why the tie-break is load.
        let primaryOrder = primaryLandmarks(groups)

        // ── NO MULTI-SERIES TRAIL, AND NO HIGHLIGHTS LIST ───────────────────
        // Wave 7 drew a six-series est-1RM chart at the bottom of this report
        // and a "Records" list above it. §5.4 deletes both: the per-exercise
        // trail is now a 40×16 sparkline in each ledger header (`spark`, above),
        // where it sits beside the sets it describes instead of asking the
        // reader to match six colours to six names; and a record is a gold row
        // in the ledger with the previous set printed under it, which answers
        // "what did it beat" in place rather than in a second list.
        // Ghosts never happened and a warm-up is not a performance, so neither
        // is in the shape. The rows are already in the session's own order
        // (`fold_order` through `toRows`), which is what makes this a sequence
        // rather than a bag of numbers.
        let intensity: [Double?] = exercises.flatMap { report in
            report.rows
                .filter { $0.kind != "ghost" && $0.num != nil }
                .map { row in [row.set, row.left, row.right].compactMap { $0?.rpe }.max() }
        }

        return Report(
            session: session, exercises: exercises,
            muscles: muscles, intensity: intensity,
            primaryOrder: primaryOrder, prCount: pr.prCount,
            physicalSets: groups.reduce(0) { $0 + physicalSets($1.sets) }
        )
    }

    // MARK: - Names

    /// The movement's display name, from an `exercise_id` and whatever the
    /// ledger stored beside it.
    ///
    /// ── WHY THE STORED NAME IS NOT ENOUGH ───────────────────────────────────
    /// `SessionHistoryStore`'s query is `COALESCE(e.name, s.exercise_id)`, and
    /// a set logged on this phone carries `"helix5-<slug>"` in `exercise_id`
    /// until the catalogue resolves it — so the fallback IS the slug, and the
    /// ledger header, the muscle map, the rep window and the PR key all took
    /// `helix5-incline-db-press` as a movement's name. Visible as a title; a
    /// silent miss everywhere else, because `Ceilings.repWindow` and
    /// `MuscleMap` have no entry under a slug and answer nil rather than
    /// wrongly.
    ///
    /// `ExerciseSlug.nameBySlug` is the second source `PrRecorder.nameResolver`
    /// already consults for exactly this case; this is that lookup without a
    /// database handle, because the caller has the rows already.
    /// Precedence is `nameResolver`'s: the CATALOGUE first (which is what
    /// `stored` already is — the query is `COALESCE(e.name, s.exercise_id)`),
    /// and the slug table only when the coalesce fell through to the id. The
    /// two must agree, because `restoreLoggedSets` resolves catalogue-first and
    /// `editorDay` builds its cards from this: name a movement differently in
    /// the two places and the card is built under one name while the rows fail
    /// to match it, so the sets never restore and the first tick writes a
    /// second exercise id.
    ///
    /// Since W2 the slug half is DATA: `historySets` coalesces the catalogue
    /// name through `exercises.slug` as well as `exercises.id`, so a phone-
    /// logged set arrives named and the compiled slug table is gone.
    static func displayName(id: String, stored: String) -> String {
        ExerciseAliases.canonicalName(stored)
    }

    // MARK: - Exercise history

    /// Session-MEAN estimated 1RM per day, oldest first, over WORKING sets.
    ///
    /// ── WHY THE MEAN AND NOT THE SESSION'S BEST ─────────────────────────────
    /// This was `sessionBestE1rm`, a max over the day. Under double progression
    /// the top set reaches the rep ceiling first and then sits there for weeks
    /// while the later sets climb toward it, so the max freezes and every curve
    /// in the app goes flat through a block of genuine progress. The web hit
    /// exactly this and moved to a day mean; §W7 brings the phone with it, and
    /// `E1rmSeries` — which collapses L/R pairs before averaging — is the one
    /// builder both now use. The max survives where a max belongs:
    /// `ExerciseSummary.bestE1rmKg`, a record.
    ///
    /// A stored 0 is "missing" (`||`) and falls through to Epley; unloaded work
    /// is scored on reps, which is the same shape and draws on the same chart.
    static func sessionMeanE1rm(_ rows: [HistorySetRow], timed: Bool = false) -> [(date: String, kg: Double)] {
        let working = rows.filter { SetTags.isWorkingSet($0.setType) }
        let unloaded = !timed && working.allSatisfy { $0.weightKg <= 0 }
        let byDate = Dictionary(grouping: working, by: \.date)
        return byDate.keys.sorted().compactMap { date in
            let sets = (byDate[date] ?? []).map {
                TrendSetRow(weightKg: $0.weightKg, reps: Double($0.reps), est: $0.est1rmKg,
                            side: $0.side, pairId: $0.pairId)
            }
            guard let trend = E1rmSeries.build([sets], timed: timed || unloaded, ceiling: nil),
                  let mean = trend.points.first, mean > 0
            else { return nil }
            return (date: date, kg: mean)
        }
    }

    // MARK: - Row selection

    struct Group {
        let exerciseId: String
        let name: String
        let sets: [HistorySetRow]
    }

    /// One session's rows by exercise, exercises in the order they were
    /// PERFORMED IN, sets in performed order within each.
    ///
    /// ── `exercise_order` FIRST, FIRST-SEEN AS THE FALLBACK ──────────────────
    /// This grouped by first appearance alone, and `fold_order` — which is what
    /// decides first appearance — is `reproject`'s enumeration of the fold, and
    /// the fold sorts by `set_index` across the whole session. So the order a
    /// session's movements come back in is the order their FIRST SETS were
    /// logged in, and nothing a reader does can change it.
    ///
    /// Dragging a card in the edit deck (§U4.5) writes `exercise_order` onto
    /// every set of every movement the drag shifted — `LoggerModel.deckOrder`,
    /// through `SetPatch` and `SetEventFold` — and the column reached Postgres
    /// correctly. It simply had no reader: the summary, the history list and
    /// the ledger all grouped by first appearance, so a reorder was a gesture
    /// with a database write behind it and no visible effect on either client.
    ///
    /// A movement's position is the MINIMUM its rows carry: an amend can miss a
    /// row (a warm-up added after the drag), and one straggler must not split a
    /// movement in two or send it to the end. Nil is not zero — a row nobody
    /// ever placed sorts by where it was seen, after everything that has been
    /// placed, which is the honest reading of "unknown".
    static func grouped(_ rows: [HistorySetRow]) -> [Group] {
        var order: [String] = []
        var by: [String: [HistorySetRow]] = [:]
        for r in rows {
            if by[r.exerciseId] == nil { order.append(r.exerciseId) }
            by[r.exerciseId, default: []].append(r)
        }
        let groups = order.enumerated().map { seen, id -> (seen: Int, placed: Int?, group: Group) in
            let sets = by[id]!.sorted { ($0.setIndex, $0.foldOrder) < ($1.setIndex, $1.foldOrder) }
            return (seen, sets.compactMap(\.exerciseOrder).min(), Group(exerciseId: id, name: sets[0].exerciseName, sets: sets))
        }
        return groups
            .sorted { a, b in
                switch (a.placed, b.placed) {
                case let (x?, y?): return x != y ? x < y : a.seen < b.seen
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return a.seen < b.seen
                }
            }
            .map(\.group)
    }

    /// `buildBaselines` over the prior rows + `detectSessionPrs` over the
    /// session, exactly as `save.ts` feeds them. `perSet` comes back in
    /// `groups`-flattened order.
    /// What the analysis needs from the store that is not a set row: the
    /// catalogue (for the deck that owns a session's date, whose rep windows
    /// gate the e1RM axis) and the asserted floors (session-less
    /// `personal_records` rows). One value, read once per screen
    /// (`context(database:)`), so a list of forty sessions does not read the
    /// catalogue forty times.
    struct Context: Sendable {
        var schedule: ScheduleContext
        var floors: [String: PrFloor]

        static let empty = Context(schedule: ScheduleContext(programId: "", phase: .cut), floors: [:])

        /// The deck for a date — the plan that owned it, not the one selected.
        func program(on date: String) -> Program { Schedule.programForContext(schedule, date).program }
    }

    /// The context off the store. Nothing filters on `user_id` beyond the goals
    /// row's own: the local store is ONE user's mirror (see `HistoryWeeks`).
    nonisolated static func context(database: AppDatabase) -> Context {
        let userId = database.localUserId()
        return Context(
            schedule: (try? database.scheduleContext(userId: userId)) ?? Context.empty.schedule,
            floors: (try? database.prFloors(userId: userId)) ?? [:]
        )
    }

    static func detect(groups: [Group], prior: [HistorySetRow], dayKey: String?, date: String, in ctx: Context) -> SessionPrResult {
        var nameByEx: [String: String] = [:]
        for g in groups { nameByEx[g.exerciseId] = displayName(id: g.exerciseId, stored: g.name) }
        func name(_ key: String) -> String { nameByEx[key] ?? "" }
        let program = ctx.program(on: date)
        func floor(_ key: String) -> Double? { Ceilings.repWindow(for: name(key), dayKey: dayKey, program: program)?.floor }

        let baselines = PrEngine.buildBaselines(
            prior.map {
                BaselineSetRow(
                    key: $0.exerciseId, weightKg: $0.weightKg, reps: Double($0.reps), est1rm: $0.est1rmKg,
                    setType: $0.setType, pairId: $0.pairId, side: $0.lr
                )
            },
            isTimed: { TimedExercise.isTimed(name($0)) },
            floorFor: { ctx.floors[name($0)] }
        )
        let candidates = groups.flatMap { g in
            g.sets.map { s in
                PrCandidateSet(
                    key: s.exerciseId, weightKg: s.weightKg, reps: Double(s.reps), setType: s.setType,
                    timed: TimedExercise.isTimed(name(s.exerciseId)),
                    pairId: s.pairId, side: s.lr, date: date, exerciseName: name(s.exerciseId), setNumber: s.setIndex
                )
            }
        }
        return PrEngine.detectSessionPrs(candidates, baselines)
    }

    /// Ghosts excluded, a pair once.
    static func physicalSets(_ sets: [HistorySetRow]) -> Int {
        var seen = Set<String>()
        var n = 0
        for s in sets where s.setType != "ghost" {
            if let p = s.pairId, !p.isEmpty {
                if !seen.insert(p).inserted { continue }
            }
            n += 1
        }
        return n
    }

    /// The landmarks a session was FOR, ranked — raw working sets, tonnage
    /// breaking the ties, the muscle's own name breaking those.
    ///
    /// ── WHY IT IS NOT `muscles`, WHICH IS RIGHT ABOVE IT ────────────────────
    /// `Report.muscles` is `MuscleCredit.weightedSets`: a share, where an
    /// assistance role earns a fraction of a set. That is the right question
    /// for the distribution chart and the wrong one for a capsule row, which
    /// carries no number — printed flat, a 0.5-set assistance credit looks
    /// exactly like the muscle the session was built around. This counts whole
    /// working sets per PRIMARY mover, which is the ranking a reader means by
    /// "what did that session train".
    ///
    /// One implementation, two callers: the session page's report and the
    /// batched `headers` loader. A second fold is how the Train card and the
    /// session page would come to rank the same workout differently.
    static func primaryLandmarks(_ groups: [Group]) -> [LandmarkMuscle] {
        var rawSets: [LandmarkMuscle: Double] = [:]
        var rawLoad: [LandmarkMuscle: Double] = [:]
        for g in groups {
            let canonical = displayName(id: g.exerciseId, stored: g.name)
            let working = g.sets.filter { SetTags.isWorkingSet($0.setType) }
            // Both figures exactly as `report` builds them: the set count folds
            // a unilateral pair once (`SessionDetail.toRows`), and the tonnage
            // is every non-ghost row including warm-ups (`SessionVolume`'s own
            // rule — "a ghost weighs nothing; a warm-up still counts").
            let sets = Double(SessionDetail.toRows(working.map(detailSet)).count)
            let load = SessionVolume.sessionVolumeKg(g.sets.map(volumeSet))
            for muscle in MuscleMap.landmarks(MuscleMap.resolveMovers(canonical).primary) {
                rawSets[muscle, default: 0] += sets
                rawLoad[muscle, default: 0] += load
            }
        }
        return rawSets.keys.sorted { a, b in
            let (setsA, setsB) = (rawSets[a] ?? 0, rawSets[b] ?? 0)
            if setsA != setsB { return setsA > setsB }
            let (loadA, loadB) = (rawLoad[a] ?? 0, rawLoad[b] ?? 0)
            if loadA != loadB { return loadA > loadB }
            return a.rawValue < b.rawValue
        }
    }

    /// When the session happened — `Sat 13 Sep · 18:20`.
    ///
    /// The career ordinal used to lead this string. It is a fact about WHICH
    /// session, not about when, so it sits at the end of the title row beside
    /// the name it belongs to; what is left here is the clock.
    static func stamp(date: String, startedAt: Date?) -> String {
        var parts: [String] = []
        if let day = LogicalDay.date(fromISO: date) {
            parts.append(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        }
        if let startedAt {
            parts.append(startedAt.formatted(date: .omitted, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }

    static func detailSet(_ r: HistorySetRow) -> DetailSet {
        CoreBridge.detailSet(
            setNumber: Double(r.setIndex), weightKg: r.weightKg, reps: Double(r.reps), rpe: r.rpe,
            est1rmKg: r.est1rmKg, setType: r.setType, side: r.lr, pairId: r.pairId,
            durationSec: r.durationSec.map(Double.init), incline: r.incline, distanceKm: r.distanceKm,
            elevationM: r.elevationM
        )
    }

    static func volumeSet(_ r: HistorySetRow) -> VolumeSet {
        VolumeSet(weightKg: r.weightKg, reps: Double(r.reps), side: r.lr, pairId: r.pairId, setType: r.setType)
    }

    /// "Legs A" for a day key, the key itself tidied when the program does not
    /// know it (a Onyx-4 or PPL session).
    ///
    /// `program` is the deck that owns the session — the caller's context
    /// knows which; nil (a preview with no catalogue) tidies the key.
    static func dayLabel(_ dayKey: String?, in program: Program?) -> String? {
        guard let dayKey, !dayKey.isEmpty else { return nil }
        return program?.day(key: dayKey)?.label
            ?? dayKey.split(separator: "_").map(\.capitalized).joined(separator: " ")
    }
}
