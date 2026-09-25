import Foundation
import Observation
import OnyxCore
import OnyxData
import OnyxUI

/// The live session, as the logger sees it.
///
/// ── WHY THERE IS A MODEL AT ALL AND NOT JUST A `ValueObservation` ───────────
/// Half of what the logger draws is not in the database and never will be. A
/// planned-but-unlogged set is a row in the PROGRAM: it has a rep window, a
/// rest target and a seed load, and it exists so you know what to walk up to
/// the machine and do. `workout_sets` only ever holds work that HAPPENED.
///
/// So the screen is the deck (a `routines` row, via `ScheduleContext`) with the log folded onto
/// it. Ticking a set appends an event; untickng voids it; editing a ticked set
/// amends it. Nothing here awaits the network to draw, which is the property
/// the whole data layer exists to provide.
///
/// ── AND WHY THE STORE IS OPTIONAL ───────────────────────────────────────────
/// `store == nil` is the previews' mode: the same model, the same state
/// machine, no database. That is deliberate — a preview that runs different
/// code from the device is a preview that lies, and the alternative (a protocol
/// with one real implementation) is an abstraction bought for nothing.
@MainActor
@Observable
final class LoggerModel: Identifiable, PauseControlling, LivePrProviding {

    /// Identity, for `fullScreenCover(item:)`.
    ///
    /// ── WHY THE COVER IS PRESENTED BY ITEM AND NOT BY A BOOLEAN ─────────────
    /// `fullScreenCover(isPresented:)` evaluates its content builder against
    /// whatever state exists at that instant, and the tab's builder read
    /// `if let session` — so a flag flipped in the same runloop turn as the
    /// model being assigned presented a cover with nothing in it. That is the
    /// black screen. Presenting by item makes the model's existence the
    /// PRECONDITION of the cover rather than a second fact that has to agree
    /// with a flag, and the empty case stops being representable.
    ///
    /// `nonisolated let` of a `Sendable` type: `Identifiable` is not isolated,
    /// so a main-actor-isolated `id` would make the conformance itself a data
    /// race the compiler refuses.
    nonisolated let id = newOnyxID()

    // MARK: - Rows

    /// How a set counts. `ghost` is work you marked as NOT done and it counts
    /// for nothing, anywhere — which is the one thing that separates it from a
    /// warm-up, which counts everywhere the body is asked about.
    enum SetKind: String, CaseIterable, Identifiable, Sendable {
        case normal, warmup, failure, dropset, ghost

        var id: String { rawValue }

        /// The single character the row wears in place of its ordinal.
        ///
        /// A letter, not a word: "Warmup" is eight characters on the one row
        /// that has no spare width, and "Dropset" and "Failure" are seven each.
        /// The full word lives in the options sheet and in the weekly export,
        /// which is what a coach actually reads.
        ///
        /// Ghost is `G`, matching the web's badge and its export. It used to be
        /// an em dash here — a glyph that reads as "nothing" in a column where
        /// every other value is an identity, and which said something different
        /// in the sheet that sets it from what the row then drew.
        var badge: String? {
            switch self {
            case .normal:  nil
            case .warmup:  "W"
            case .failure: "F"
            case .dropset: "D"
            case .ghost:   "G"
            }
        }

        /// ── THE WORDS LIVE IN `SetTags` SINCE W3 ───────────────────────────
        /// They were two `switch`es here, byte for byte the vocabulary the
        /// watch's Set Quality panel now has to draw as well — and the watch
        /// cannot see the app target. Two hand-maintained copies of one
        /// vocabulary both look right, so there is one, in OnyxCore, and this
        /// is the typed view over it. The same move `Effort` made when the
        /// finish sheet started needing the suggestion.
        var label: String { SetTags.word(for: self == .normal ? nil : rawValue) }

        /// What choosing it MEANS, in four words. The sheet keeps one of these
        /// on screen at all times: five hints stacked under five chips would put
        /// the height straight back, and a tooltip is not reachable by thumb.
        var hint: String { SetTags.hint(for: self == .normal ? nil : rawValue) }
    }

    @MainActor
    @Observable
    final class SetRow: Identifiable {
        /// SwiftUI's identity. Stable for the life of the row, because a
        /// `ForEach` that re-identifies a row mid-gesture tears down the field
        /// the finger is in.
        let id: String

        /// The id this row is written to the STORE under, which is a different
        /// thing and does not survive a void.
        ///
        /// ── WHY A TOMBSTONED ID CAN NEVER COME BACK ─────────────────────────
        /// `SetEventFold` is explicit: `voided` membership "outranks everything,
        /// forever", and an `.append` for a voided set id is skipped before any
        /// other rule. So untick-then-retick — which is the single most ordinary
        /// gesture on this deck, and the entire point of the edit screen —
        /// re-appended the same id, the fold dropped it, and the set was GONE
        /// while the row on screen stayed ticked. `refreshLivePrs` counted it,
        /// the header counted it, and `reproject` did not.
        ///
        /// In edit mode it is worse than a display lie: the same transaction
        /// runs `recount`, writes the shrunken `total_volume_kg` and `set_count`
        /// onto the session row, and queues that for upload.
        ///
        /// So a void re-mints this. `id` stays put for the view; the next append
        /// is a genuinely new set, which is what un-ticking and re-ticking
        /// actually means.
        var storeId: String
        var weightKg: Double?
        var reps: Int?
        /// CR-10. `nil` is UNRATED, which the progression rule has to be able to
        /// tell apart from "rated easy".
        var rpe: Double?
        var kind: SetKind
        /// HOW the set went, as opposed to how hard — the second axis the set
        /// options sheet asks about. EMPTY is "not reported", never "clean":
        /// see `SetQuality`.
        ///
        /// ── WHY IT IS A LIST NOW ────────────────────────────────────────────
        /// "Swung the last few AND cut the range short" is one set, and the
        /// sheet used to make you pick which half to record. The column did not
        /// change shape to allow it — see `SetQuality.join`.
        var qualities: [SetQuality]

        /// The first tag, in canonical order. Every reader that only wants to
        /// know WHETHER the set was marked, or wants one word for a badge, goes
        /// through here rather than indexing the array.
        var quality: SetQuality? { qualities.first }

        /// Which limb this row logged: `"left"` / `"right"`, or nil on an
        /// ordinary two-sided set.
        ///
        /// ── THE LOCAL SPELLING, NOT THE WIRE'S ──────────────────────────────
        /// `workout_sets.side` is `L`/`R` in Postgres and `left`/`right` in the
        /// local mirror, and `SyncTranslation.side` is the one bridge between
        /// them. Storing the wire's spelling here would push `L` into a column
        /// whose reader (`SessionHistoryStore.lr`) maps only `left` — the pair
        /// would then reach `SessionVolume` as two unsided rows and the session
        /// would weigh nearly twice what it did.
        var side: String?

        /// The two sides of ONE physical set share this. A `pairId` without a
        /// `side` (or the other way round) is not a pair to anything that
        /// counts — see `SessionVolume.sessionVolumeKg`.
        var pairId: String?

        /// `L` / `R` for the badge and for VoiceOver, or nil.
        ///
        /// Both vocabularies, deliberately. Ingestion normalises to the local
        /// spelling (`restoreLoggedSets`), and this is the second guard rather
        /// than the first: a future writer that puts the wire's `L` in here
        /// should draw a pair badge, not silently split one set into two.
        var sideLabel: String? {
            switch side?.lowercased() {
            case "left", "l":  "L"
            case "right", "r": "R"
            default:           nil
            }
        }
        var isDone: Bool
        /// What this set number was last time, pre-formatted: `"47kg × 12"`.
        /// Empty when the movement is new — a Lock Screen has no room to say
        /// "no data" politely and neither does a set row.
        var previous: String?
        /// A record claimed on this set — the REAL engine since P3 E4.
        ///
        /// `PrEngine.detectSessionPrs` against baselines built by
        /// `PrRecorder.baselines`, which is the same function `closeSession`
        /// uses to write `personal_records`. That identity is the point: a live
        /// badge computed from a different bar is a badge that fires on a set
        /// the close then refuses to file, and gold means "never beaten"
        /// everywhere else in the app.
        var isRecord: Bool

        /// The remembered rating was DROPPED because this row's work is harder
        /// than the set it was seeded from. Distinct from `rpe == nil`, which
        /// is simply an unrated set.
        ///
        /// Drawn by the set row's "rate this" pip since wave U2 —
        /// `ExerciseCardView.effort`.
        var rpeStale: Bool

        /// This row opens on a progression bump: `.ready` pre-filled the
        /// suggested load at the rep floor.
        ///
        /// Drawn since wave U2 by the card's progression chip and by the
        /// bumped load's own ink — `ExerciseCardView.progression`.
        var progressed: Bool

        /// A set that is not reps and kilograms: seconds under load, incline
        /// percent, kilometres. All three nil on a lifted set.
        ///
        /// ── CARRIED, NOT EDITABLE, AND THAT IS THE POINT ────────────────────
        /// The deck has no control for any of them and this wave does not add
        /// one. What it adds is the ability to CARRY them, because a row that
        /// cannot hold a fact destroys it: `snapshot` builds the payload for
        /// every append and amend the deck writes, so a restored treadmill row
        /// re-appended without these went back into the log as `0kg × 0` with
        /// the five minutes, the 0.37 km and the 2 % gone — and then pushed
        /// that over the server's copy.
        ///
        /// Worse, `toggleDone` refuses to tick a row with no reps. So the
        /// treadmill row could be UN-ticked (which voids it, permanently — see
        /// `storeId`) and then could not be put back. One tap on the only set
        /// in the session that carries no reps deleted it from the phone, from
        /// the projection and from Postgres, with no way back on this screen.
        /// `isCardio` is what both halves of that now test.
        var durationSec: Int?
        var incline: Double?
        var distanceKm: Double?
        /// Total ascent in metres — carried on exactly the same terms as the
        /// three above, and for the same reason: a row that cannot hold a fact
        /// destroys it on the next append.
        var elevationM: Double?

        /// This row's content is time and distance rather than reps.
        ///
        /// Ascent is deliberately NOT one of the tests. A bout that measured
        /// ascent measured something else too — there is no walk with an
        /// elevation and no duration — so adding it here would only widen the
        /// door for a row where all it can mean is a stray value.
        var isCardio: Bool { durationSec != nil || distanceKm != nil || incline != nil }

        init(
            id: String = newOnyxID(),
            storeId: String? = nil,
            weightKg: Double? = nil, reps: Int? = nil, rpe: Double? = nil,
            kind: SetKind = .normal, quality: SetQuality? = nil,
            qualities: [SetQuality]? = nil, isDone: Bool = false,
            previous: String? = nil, isRecord: Bool = false,
            rpeStale: Bool = false, progressed: Bool = false,
            side: String? = nil, pairId: String? = nil,
            durationSec: Int? = nil, incline: Double? = nil, distanceKm: Double? = nil,
            elevationM: Double? = nil
        ) {
            self.id = id
            self.storeId = storeId ?? id
            self.weightKg = weightKg
            self.reps = reps
            self.rpe = rpe
            self.kind = kind
            // `quality:` is kept as the one-tag convenience every existing call
            // site (and every preview) uses; `qualities:` wins when both are
            // given, which is what the restore path passes.
            self.qualities = qualities ?? [quality].compactMap { $0 }
            self.side = side
            self.pairId = pairId
            self.isDone = isDone
            self.previous = previous
            self.isRecord = isRecord
            self.rpeStale = rpeStale
            self.progressed = progressed
            self.durationSec = durationSec
            self.incline = incline
            self.distanceKm = distanceKm
            self.elevationM = elevationM
        }

        /// Tonnage this row contributes ON ITS OWN. A ghost contributes
        /// nothing; a warm-up does, because the weight was still moved.
        ///
        /// ⚠️ Not the answer for a row that is half of a unilateral pair — two
        /// sides summed is a set counted twice. `ExerciseState.volumeKg` routes
        /// every row through `SessionVolume.sessionVolumeKg`, which is the one
        /// implementation of the weaker-side rule, and this stays for the
        /// unpaired case it is still exactly right for.
        var volumeKg: Double {
            guard kind != .ghost, isDone, let weightKg, let reps else { return 0 }
            return weightKg * Double(reps)
        }

        /// This row as the shared volume rule sees it, in the wire's spelling of
        /// `side` — which is the spelling `SessionVolume` matches on.
        var volumeSet: VolumeSet {
            VolumeSet(
                weightKg: weightKg ?? 0, reps: Double(reps ?? 0),
                side: sideLabel, pairId: pairId, setType: kind.rawValue
            )
        }

        /// What `SetGrouping` folds this row onto — the deck's answer to "which
        /// set is this row part of".
        ///
        /// Both fields tested, which is the protocol's own rule: a `pairId`
        /// with no side is a half-written set, and folding it onto its sibling
        /// would score one arm's load as the whole set's.
        ///
        /// `sideLabel` rather than `side`, so the wire's `L`/`R` counts as a
        /// side here exactly as it does in the badge. A row that reaches this
        /// object in the wrong vocabulary draws a pair badge; it does not
        /// silently become two sets.
        var pairKey: String? {
            guard let pairId, !pairId.isEmpty, sideLabel != nil else { return nil }
            return pairId
        }

        var estimated1RM: Double? {
            guard let weightKg, let reps else { return nil }
            // `Epley` returns nil for an unloaded set rather than 0 — reading it
            // back with `??` instead of a nil check is how "1RM 0" printed for
            // months in the web app.
            return OneRepMax.estimate(weight: weightKg, reps: Double(reps))
        }
    }

    @MainActor
    @Observable
    final class ExerciseState: Identifiable {
        let plan: ProgramExercise
        var rows: [SetRow]
        var note: String

        /// The `exercise_id` the SESSION's existing rows carry, when there are
        /// any (§U4.5).
        ///
        /// ── WHY IT IS NOT ALWAYS `ExerciseSlug.id` ──────────────────────────
        /// A set logged on this phone carries `"onyx-<slug>"`; one logged on
        /// the web carries the catalogue's uuid. Appending a forgotten set to a
        /// web-logged session with the slug would put two ids on one movement
        /// in one session, and `SessionAnalysis.grouped` keys on the id — so
        /// the summary would draw "Incline DB Press" twice, once with three
        /// sets and once with one, and `PrRecorder.record` (which also keys on
        /// the id) would measure the new set against an empty baseline.
        ///
        /// Nil for a live session and for a movement this session has no rows
        /// of, where the slug is correct and is what `closeSession` expects.
        var storedExerciseId: String?

        /// SwiftUI's identity — MINTED, not the movement's name.
        ///
        /// ── WHY A NAME IS NOT AN IDENTITY ───────────────────────────────────
        /// It was `plan.id`, which for a synthetic card is the movement's name
        /// (the opener's card is named after the bout it repeats). A deck that
        /// managed to carry two cards for one movement — `withWarmupCardio`
        /// prepending a bout the edit deck already held — therefore carried two
        /// cards with ONE id, and that is not a cosmetic duplicate:
        ///
        ///   · `ForEach(model.exercises)` over duplicate ids is undefined by
        ///     SwiftUI's own documentation, and inside a `LazyVStack` under
        ///     scroll it is fatal.
        ///   · `rebuildForPhase` built `Dictionary(uniqueKeysWithValues:)` from
        ///     them, which TRAPS on a duplicate key — so a phase switch on such
        ///     a deck crashed outright.
        ///   · `deckOrder(of:)` is `firstIndex { $0.id == exercise.id }`, so
        ///     both cards resolved to ONE `exercise_order`, and the second
        ///     card's appends were filed as the first card's.
        ///
        /// A minted id makes every one of those impossible rather than
        /// unlikely. The duplicate is still a defect and is still fixed at its
        /// source (`withWarmupCardio`, `DeckRestore.fold`); this is the layer
        /// that stops it ever being fatal again.
        ///
        /// `nonisolated let` because `Identifiable` is not isolated: `ForEach`
        /// reads `id` while diffing, outside any actor, and a main-actor
        /// `id` makes the conformance itself a data race the compiler refuses.
        nonisolated let id = newOnyxID()
        nonisolated var name: String { plan.name }

        init(plan: ProgramExercise, rows: [SetRow], note: String = "") {
            self.plan = plan
            self.rows = rows
            self.note = note
        }

        /// PHYSICAL sets performed — warm-ups INCLUDED, ghosts excluded.
        ///
        /// Warm-ups count here and essentially nowhere else, because the
        /// question the muscle sheet asks is different: two warm-up sets of leg
        /// press are two sets of leg press as far as the quads are concerned.
        /// It is also the number Hevy prints, and Hevy counts them.
        ///
        /// Precision seam 1: `SessionCounts.total` (OnyxCore, Lane C) becomes
        /// the one rule for this figure and for `workingSets` below — warm-ups
        /// and cardio bouts in, pairs once, ghosts out. The names stay; the
        /// close-out wave points both bodies at it.
        var physicalSets: Int {
            LoggerModel.physical(rows.filter { $0.isDone && $0.kind != .ghost })
        }

        /// WORKING sets — what the program prescribed and what the header counts.
        var workingSets: Int {
            LoggerModel.physical(rows.filter { $0.isDone && $0.kind != .ghost && $0.kind != .warmup })
        }

        /// Σ tonnage, with a genuine L/R pair scored ONCE at its weaker side.
        ///
        /// Routed through `SessionVolume` rather than summed here: that
        /// function is the rule, it is vector-equal with the web's
        /// `sessionVolumeKg`, and it is what `closeSession` writes to
        /// `total_volume_kg`. A second summation in the deck is a header that
        /// disagrees with the row it wrote.
        var volumeKg: Double {
            SessionVolume.sessionVolumeKg(rows.filter(\.isDone).map(\.volumeSet))
        }

        /// Done when every set the PROGRAM asked for is ticked.
        ///
        /// ── WHY WARM-UPS AND GHOSTS ARE NOT PART OF THE TEST ────────────────
        /// This was `rows.allSatisfy(\.isDone)`, over every row — and the deck
        /// seeds a warm-up row on the leg days (`Leg Press` is `cutSets: 3` plus
        /// the note "1 warm-up @40kg"). So the card counted 3/3 working sets,
        /// which is what `workingSets` and `plannedSets` both mean, and STILL
        /// refused to say Done, because the warm-up nobody performed was
        /// outstanding. The header said finished and the card said not, over the
        /// one row the program never counted in the first place.
        ///
        /// Ghosts go the same way for the same reason: a ghost is a row the
        /// projection knows about and the program never prescribed.
        ///
        /// A movement that is ALL warm-up — nothing in this deck, but reachable
        /// by deleting every working row — falls back to the old test rather
        /// than reporting an exercise with rows in it as permanently unfinished.
        var isComplete: Bool {
            let prescribed = rows.filter { $0.kind != .warmup && $0.kind != .ghost }
            guard !prescribed.isEmpty else { return !rows.isEmpty && rows.allSatisfy(\.isDone) }
            // Both sides, or the set is not done. Ticking only the left arm of a
            // split set is a set half performed, and the card saying Done over
            // it is the card lying about the one thing it is for.
            return prescribed.allSatisfy(\.isDone)
        }
    }

    // MARK: - State

    private(set) var day: ProgramDay
    /// `day` as it was handed in — before any movement was added to it. The
    /// seed is built from this and nothing else (see `phase`).
    private let programDay: ProgramDay
    var phase: ProgramPhase {
        didSet {
            guard phase != oldValue else { return }
            // ── THE SEED IS PHASE-SCOPED, SO IT IS REBUILT TOO ──────────────
            // `SessionSeedBuilder.build` walks `day.exercises(for: phase)`, so
            // a lift the OTHER phase drops has no seed entry at all. Switching
            // cut → bulk brings the wrist curl and the hip adduction back, and
            // without this they would open on `wk1Kg` with a blank Previous —
            // the July-number problem this wave exists to remove, for exactly
            // the subset of lifts a phase switch introduces.
            // From the PROGRAM's day, not `day`: `appendCard` grows `day` with
            // movements added mid-session, and a seed rebuilt over it would
            // give each one a cold-start entry — which switches off the
            // narrow "last time" the card opened on (`seeded == nil` is its
            // gate) at the first phase switch.
            let opened = Self.loadSeed(store: store, day: programDay, phase: phase, userId: userId)
            seed = opened.seed
            progressionAlerts = opened.alerts
            rebuildForPhase()
        }
    }
    private(set) var exercises: [ExerciseState] = []
    /// The movement names in the order this split was last LEFT in, from
    /// `routine_templates` — see `AppDatabase.deckOrder(dayKey:userId:)`.
    /// Empty until a session has been finished on this day.
    private let storedDeckOrder: [String]

    /// This deck is being built to CORRECT a finished session, not to run one.
    ///
    /// Known at construction, which is the point. Two rules turn on it and both
    /// used to be applied — or undone — after the fact:
    ///
    ///   * `storedDeckOrder` is not read. See `init` for what ranking an edit
    ///     deck against another session's running order did to the treadmill.
    ///   * The warm-up bout is not prepended. `withWarmupCardio` ran at `init`,
    ///     before anything knew this was an edit, and `attach(editing:)` then
    ///     deleted the card again if nobody had ticked it — a card minted and
    ///     destroyed in the same breath, and a real one on any session that DID
    ///     walk, because the delete could not tell the two apart without
    ///     inspecting rows that had not been restored yet.
    ///
    /// `attach(editing:)` is the only caller that needs it and `openEditor` is
    /// the only construction site that passes it, so the two cannot drift.
    private let openingForEdit: Bool
    /// The bout this deck opens with, or nil when it opens with none.
    ///
    /// It is the athlete's OWN last `cardio_logs` row, cut to warm-up length
    /// (`WarmupCardio.seed(from:)`). nil for anybody who has never logged
    /// cardio — which is every account on its first session — and nil for a
    /// storeless model unless the caller hands one in.
    private let warmupBout: WarmupCardio.Bout?
    /// When the session began.
    ///
    /// `var`, because the timer sheet can correct it (`setStart`, `setElapsed`)
    /// — a deck opened twenty minutes before the first set otherwise reports
    /// twenty minutes of training that did not happen. Never rebased around a
    /// pause: `Era.forDate`, the PR date and every "when did you train" reader
    /// take this field.
    private(set) var startedAt: Date

    /// The caller named `startedAt` rather than letting `init` stamp now.
    /// See `init` and `LiveSessionStart`.
    private let startedAtWasGiven: Bool

    /// When the current rest period ends. `nil` means no timer is running —
    /// which is not the same as a timer at zero, and the bar renders the two
    /// differently.
    private(set) var restEndsAt: Date?
    private(set) var restDuration: TimeInterval = 0
    /// Which exercise started the rest, so the bar can name it.
    private(set) var restingExercise: String?

    // ── MEASURED REST ───────────────────────────────────────────────────────
    //
    /// When each exercise last had a set COMMITTED, keyed by deck identity.
    ///
    /// ── WHY THE COMMIT AND NOT THE TIMER ────────────────────────────────────
    /// `restEndsAt` is a countdown: you can skip it, ignore it, or leave it
    /// running through a phone call. It measures the PRESCRIPTION. The gap
    /// between committing one set and committing the next is what actually
    /// happened, which is the only thing worth writing down.
    ///
    /// In memory, and deliberately dying with the session. A set logged after
    /// the app was killed and relaunched has no measurable predecessor — the
    /// elapsed time would include however long the phone was in a pocket — and
    /// nil is the honest answer there.
    private var lastCommitAt: [String: Date] = [:]

    /// The longest gap still counted as rest, in seconds.
    ///
    /// Fifteen minutes is deliberately generous: a heavy compound double can
    /// legitimately take five, and a threshold tight enough to catch a slow
    /// superset would discard real data. What it excludes is the phone call,
    /// the commute and the overnight suspension — and it has to exclude them,
    /// because one 40-minute outlier moves a six-set mean further than the
    /// other five sets combined.
    static let restGapCeilingSec: TimeInterval = 900

    /// The measured gap since this exercise's last commit, or nil.
    ///
    /// Nil on the first set of a movement (nothing to rest from), on a gap past
    /// the ceiling, and in edit mode — where "now" is days after the session
    /// and the elapsed time measures the editing, not the training.
    private func restGapSec(for exercise: ExerciseState, at now: Date) -> Int? {
        guard !isEditing, let last = lastCommitAt[exercise.name] else { return nil }
        let gap = now.timeIntervalSince(last)
        guard gap > 0, gap <= Self.restGapCeilingSec else { return nil }
        return Int(gap.rounded())
    }

    // ── The seed ────────────────────────────────────────────────────────────
    //
    // What the deck OPENS with, and where each number came from. Built once —
    // in `init`, from the store when there is one — because a deck that
    // re-derives its own proposal on every phase switch would move numbers the
    // user has already read. `SessionSeedBuilder` with an empty history is the
    // program's cold start, which is exactly the preview's behaviour, so there
    // is one path rather than two.
    private(set) var seed: SessionSeed

    /// "Last time" for the movements the DAY's seed does not cover — the ones
    /// added mid-session (W3), keyed by `canonicalKey`.
    ///
    /// ── A SECOND, NARROW LOOKUP, NOT A WIDER SEED ───────────────────────────
    /// `seed` is scoped to this routine day on purpose (`SessionSeedBuilder
    /// .sessionsForSeed` says why), so a movement today's program does not name
    /// has no entry in it and its card opened on blanks. This holds the answer
    /// to that card's one question — the last working set of it anywhere
    /// (`AppDatabase.lastWorkingSet`) — and it is only ever filled by
    /// `appendCard`, only for a movement the seed has no entry for. Every card
    /// the day opened with reads the seed exactly as before.
    private(set) var lastTimes: [String: LastWorkingSet] = [:]

    /// What the card of a movement added mid-session was last lifted at, or nil.
    func lastTime(for exercise: ExerciseState) -> LastWorkingSet? {
        lastTimes[canonicalKey(exercise.name)]
    }

    /// Lifts that have earned a load bump today, and those one session away.
    /// Published to `AppEnvironment.progressionAlerts` by whoever opens the
    /// logger (decision 10 — in-app only).
    ///
    /// ── WHAT READS IT, AND WHAT DELIBERATELY DOES NOT (W10) ─────────────────
    /// `ExerciseCardView.oneMore` reads the `.oneMore` verdicts and draws the
    /// card's cue chip. The `.ready` verdicts are NOT read from here: they have
    /// already pre-filled the deck's rows (`SeedRow.progressed`), and the row
    /// is the better evidence — a rebuild that drops the bump drops the chip
    /// with it, which an alert-backed chip would not. `.oneMore` changes no
    /// number in the deck, so this list is the only place it exists.
    private(set) var progressionAlerts: [ProgressionQueue.Alert] = []

    // ── The live PR bar ─────────────────────────────────────────────────────
    //
    // Built from the same function that writes the ledger on close. The bar a
    // set is measured against is the history that existed before this workout
    // started — folding this session's own sets into it as they land is how
    // every set becomes a record against itself — and `excluding: sessionId`
    // is what enforces that, not the fact that the bar is never rebuilt.
    //
    // ── WHY IT IS REBUILT, WHICH IT USED TO NOT BE (W2) ─────────────────────
    // It was built once, at `attach`, and the comment here said so. That made
    // the bar a snapshot of the deck's identities at the instant the screen
    // opened — and those identities MOVE. `storedIdCreatingCatalogueRow` mints
    // a catalogue row at the first commit of a movement the catalogue has never
    // heard of and rewrites `idByCanonicalName`, so the key `refreshLivePrs`
    // hands the engine flipped slug → uuid on the first tick while the bar was
    // still keyed on the slug. `PrEngine.detectSetPrs` requires an EXISTING
    // index entry for every axis, so it awarded nothing at all: the deck showed
    // no trophy on a set whose own session page, one screen later, showed two.
    //
    // Widening the id set handed to `livePrBaselines` does NOT fix it, and
    // that is the part worth being explicit about. `PrRecorder.baselines`
    // re-keys every row it gathers to `keyByName[name(id)]`, and `keyByName`
    // uniques on FIRST over a `Set` — whose iteration order is a hash. Hand it
    // both the slug and the uuid for one movement and the bar lands under
    // whichever the hash happened to visit first, which is why the symptom came
    // and went between launches.
    //
    // So: ONE resolved id per card goes in (`PrRecorder.baselines` gathers the
    // movement's other ids by canonical NAME itself — that is what `siblings`
    // is for), and the bar is rebuilt whenever that set of ids moves. Rebuilding
    // is safe precisely because `excluding` is what bounds the history, and it
    // can only ever raise a bar or fill an empty one.
    private var baselines: PrBaselines = .empty

    /// The ids `baselines` was built from — the deck's resolved identities as
    /// they stood at the last build.
    ///
    /// The comparison `refreshLivePrs` makes before every pass. A mint, a phase
    /// switch that replaces `exercises`, and a restore that learns a session's
    /// stored ids all move this set, and all three used to leave the bar keyed
    /// on identities the candidates no longer carry.
    private var baselineKeys: Set<String> = []

    /// Distinct axis-records claimed so far — the Live Activity's count.
    private(set) var prsThisSession = 0

    /// The records themselves, newest first — `LivePrProviding`, which the Live
    /// Stats "Records" card draws. Filled by the same pass that lights the
    /// badges, so the card and the badge can never disagree.
    private(set) var livePrs: [LivePrRecord] = []

    // ── The session clock ───────────────────────────────────────────────────

    /// When the CURRENT pause began, or nil while running.
    ///
    /// A pause is an EVENT in the log, not just a flag on this object: it has
    /// to survive the app being killed mid-workout and it has to merge with the
    /// watch's. This is the in-memory read of it — `PauseControlling.isPaused`
    /// is `pausedAt != nil`, and the timer reads `elapsed(at:)` rather than
    /// asking the store per tick.
    private(set) var pausedAt: Date?

    /// Seconds banked by pauses that have CLOSED.
    private(set) var pausedTotal: TimeInterval = 0

    private let store: AppDatabase?
    /// The `workout_sessions` row this device is writing into, once one exists.
    /// Readable because the finish sheet's "View summary" pushes
    /// `SessionDetailView(sessionId:)` at it — and `nil` is the honest answer
    /// while nothing has been logged, which is what hides that button.
    private(set) var sessionId: String?

    /// Set when the deck was opened on a session that is already history.
    ///
    /// ── WHAT EDIT MODE ACTUALLY CHANGES (§U4.5) ─────────────────────────────
    /// Three things, and deliberately nothing else — the deck, the set row, the
    /// options sheet, the effort picker and the records card are the same code
    /// looking at the same model:
    ///
    ///  1. **Where the writes go.** `EventStore`'s `appendSet` / `amendSet` /
    ///     `voidSet` claim the pencil, do not seed a log, do not replay the PR
    ///     ledger and do not recount the session's aggregates — all four of
    ///     which a finished session needs. `SessionEditing` does all of them in
    ///     one transaction, and it is the only path that can RETRACT a record.
    ///  2. **What finishing means.** `closeSession` stamps `ended_at` and
    ///     derives `duration_min` from a clock that stopped weeks ago. Editing
    ///     finishes with `updateMetrics` — the three figures and the effort —
    ///     and then the caller runs the cascade.
    ///  3. **The clock.** There is no elapsed time to count. The hero shows the
    ///     session's own date and its stored duration.
    private(set) var editing: EditContext?

    /// What the view needs to know about the session under the deck.
    struct EditContext: Equatable, Sendable {
        /// The session's logical day, ISO — the cascade's anchor.
        let date: String
        /// When it began, for the hero's date line.
        let startedAt: Date?
        /// `duration_min` as stored, which the hero draws where the live deck
        /// draws a running timer.
        let durationMin: Double?
    }

    var isEditing: Bool { editing != nil }


    /// Whether `attach(editing:)` managed to stamp the revert watermark.
    ///
    /// The Cancel button reads it: a deck that could not be marked cannot be
    /// reverted, and a button that looks live and does nothing is worse than no
    /// button. See `cancelEdit`.
    private(set) var editWatermarked = false
    /// Cards appended while EDITING (overhaul C2), by card id, with whether
    /// their plan was appended to `day` too. Discard takes them back out: once
    /// the revert has voided their sets they describe nothing.
    /// Keyed by `canonicalKey`, recorded by `addExercise` alone: `attach
    /// (editing:)` also appends cards (the session's own off-plan movements)
    /// and those are not the sitting's to take away.
    private var addedWhileEditing: [(key: String, appendedPlan: Bool)] = []

    private let userId: String

    // MARK: - Derived

    var totalVolumeKg: Double { exercises.reduce(0) { $0 + $1.volumeKg } }
    /// Working sets still unticked — never stored, and kept in the plan
    /// (`RoutineOrder.merge`). The finish sheet says so (Precision A6). A bout
    /// and a warm-up are not planned working sets and are not counted.
    var untickedSets: Int {
        exercises.reduce(0) { total, exercise in
            total + Self.physical(exercise.rows.filter {
                !$0.isDone && $0.kind != .warmup && $0.kind != .ghost && !$0.isCardio
            })
        }
    }
    /// A live bpm reached the phone during this session — one of the three
    /// signals that a watch was on the wrist (`FinishSheet`, Precision A5).
    /// In memory, and latched: a watch that went quiet at the end still saw it.
    var wristBpmSeen = false
    /// Whether the store holds wrist evidence for this session — see
    /// `AppDatabase.hasWristEvidence`.
    func wristEvidence() -> Bool {
        guard let store, let session = sessionRow else { return false }
        return (try? store.hasWristEvidence(sessionId: session.id, userId: userId, date: session.date)) ?? false
    }
    var completedSets: Int { exercises.reduce(0) { $0 + $1.workingSets } }
    var plannedSets: Int { day.plannedSets(for: phase) }
    /// Records claimed so far — AXES, not rows.
    ///
    /// ── WHY NOT `rows.filter(\.isRecord).count`, WHICH IS WHAT IT WAS ───────
    /// One set can win two axes at once (a heaviest load that is also a best
    /// e1RM), and two sets can win one axis between them. `pr_count` on the
    /// session, the trophy chips and the web all count DISTINCT axis-records —
    /// `PrEngine.detectSessionPrs(…).prCount` — so counting rows here made the
    /// finish sheet, the Live Activity and the ledger disagree about the same
    /// workout by one or two the moment a set won on two axes.
    var recordCount: Int { prsThisSession }
    var physicalSets: Int { exercises.reduce(0) { $0 + $1.physicalSets } }

    /// What the Live Stats timeline draws for one exercise: dots done over dots
    /// planned.
    ///
    /// Lifting: today's rule — working sets over the larger of the plan's sets
    /// and the prescribed physical rows, so a set you added yourself grows the
    /// denominator instead of overflowing it.
    ///
    /// ── WHY A CARDIO BOUT NEEDS ITS OWN BRANCH ──────────────────────────────
    /// The opening bout is minted `kind: .warmup` on purpose: that is what
    /// keeps it out of `workingSets`, out of tonnage and out of the PR engine.
    /// The lifting numerator is `workingSets`, so a bout you HAVE done read 0
    /// done out of 1 planned forever — the one row on the timeline that could
    /// never be filled. An exercise whose every non-ghost row is cardio is
    /// therefore counted in ROWS TICKED, which changes nothing anybody else
    /// reads.
    func dotProgress(for exercise: ExerciseState) -> (done: Int, planned: Int) {
        let live = exercise.rows.filter { $0.kind != .ghost }
        if !live.isEmpty, live.allSatisfy(\.isCardio) {
            return (live.filter(\.isDone).count, max(1, live.count))
        }
        let prescribed = live.filter { $0.kind != .warmup }
        return (
            exercise.workingSets,
            max(exercise.plan.sets(for: phase), Self.physical(prescribed))
        )
    }

    /// The token a movement's muscle chip resolves, or nil when it has no mover
    /// this app can name.
    ///
    /// Read from `plan.movers`, which is where the deck's own rail reads it, so
    /// the Lock Screen, the Live Stats timeline and the card in your hand
    /// cannot call the same set three different things. A movement whose rows
    /// are all cardio has no landmark at all and answers `"cardio"`, which the
    /// callers draw in `Color.onyx.cardio`.
    ///
    /// Static and read-only: this reads a plan and nothing else, so it is
    /// callable off a state the caller already holds without touching the deck.
    static func primaryMuscle(of exercise: ExerciseState?) -> String? {
        guard let exercise else { return nil }
        if let token = exercise.plan.movers.primary.first,
           LandmarkMuscle.from(token: token) != nil {
            return token
        }
        return exercise.rows.contains(where: \.isCardio) ? "cardio" : nil
    }

    /// How many SETS a list of rows is, once a set can be two rows.
    ///
    /// Each `pairId` once, every unpaired row once — the same rule as
    /// `countCommittedSets` on the web and as the `count(distinct coalesce(
    /// pair_id, id))` that `closeSession` writes to `set_count`. Three
    /// implementations of one rule is how a deck says 6/3.
    static func physical(_ rows: [SetRow]) -> Int { groups(rows).count }

    /// The same rows, grouped into the SETS they are — a pair together, every
    /// other row alone, in the order they appear.
    ///
    /// Anything that keeps or drops sets has to work on these and not on rows,
    /// or it keeps half a pair: a lone side is not a set to `SessionVolume`, to
    /// `physical`, or to the arm that did not get trained.
    /// ── THE RULE MOVED, THE MEANING DID NOT ────────────────────────────────
    /// This was the third copy of "a pair is one set" in the codebase and the
    /// deck's own. It is now `SetGrouping` in OnyxCore, where `DeckRestore`
    /// reaches it too — the restore has to count blanks in SETS, and a second
    /// implementation of the fold inside it would be the fourth. This stays as
    /// the deck's spelling of the call, because forty call sites say
    /// `LoggerModel.groups`.
    static func groups(_ rows: [SetRow]) -> [[SetRow]] { SetGrouping.groups(rows, pairKey: \.pairKey) }

    /// Weighted set counts per landmark, for the distribution sheet.
    var muscleSets: [LandmarkMuscle: Double] {
        MuscleCredit.weightedSets(
            exercises.map { .init(physicalSets: $0.physicalSets, movers: $0.plan.movers) }
        )
    }

    /// The set you are standing in front of: the first one not yet ticked.
    /// ── COUNTED IN SETS, NOT IN ROWS ────────────────────────────────────────
    /// `ordinal` and `total` are what the Lock Screen renders as "Set 3 of 4".
    /// A unilateral movement is two rows per set, so counting rows made the card
    /// say "Set 7 of 10" for the fourth set of five — a sentence about a
    /// prescription nobody wrote.
    var currentSet: (exercise: ExerciseState, row: SetRow, ordinal: Int, total: Int)? {
        for exercise in exercises {
            let groups = Self.groups(exercise.rows)
            guard let at = groups.firstIndex(where: { $0.contains { !$0.isDone } }),
                  let row = groups[at].first(where: { !$0.isDone })
            else { continue }
            return (exercise, row, at + 1, groups.count)
        }
        return nil
    }

    /// The movement AFTER the one you are standing in front of, in deck order,
    /// skipping anything already finished. Nil on the last movement.
    ///
    /// ── WHY THE CARD USED TO NAME THE LIFT YOU WERE ALREADY DOING ───────────
    /// `LiveActivityController` sent `currentSet`'s own exercise as BOTH
    /// `exercise` and `nextExercise`, on the reasoning that the cursor is the
    /// first unticked row and so is already what you are walking back to. That
    /// is true of the set and false of the movement: resting between set 2 and
    /// set 3 of a press, "NEXT" said press. Named off `currentSet` here too, so
    /// the two fields can never disagree about which one is current.
    var nextExercise: ExerciseState? {
        guard let current = currentSet?.exercise,
              let at = exercises.firstIndex(where: { $0.id == current.id })
        else { return nil }
        return exercises[(at + 1)...].first { exercise in
            exercise.rows.contains { !$0.isDone && $0.kind != .ghost }
        }
    }

    /// The movement to HEADLINE while resting, and only at a movement boundary:
    /// the lift you are about to start, when the rest you are in is the last
    /// one of the previous lift. Nil mid-exercise and nil when not resting.
    ///
    /// ── WHY THE CARD CANNOT JUST DRAW `nextExercise` ────────────────────────
    /// The Live Activity's load, `lastTime` and `lastRpe` all come from
    /// `currentSet.row` — the set you are about to perform. `nextExercise` is
    /// the movement AFTER that set's movement, so resting between set 2 and set
    /// 3 of a squat the card would headline "NEXT · Bench" above the squat's
    /// weight and the squat's "Set 3 of 4": one card, two different lifts. The
    /// subject only changes when the SET does, which is exactly when the
    /// movement being rested from (`restingExercise`, stamped by `startRest`)
    /// is no longer the movement the cursor is on.
    var restBoundaryExercise: ExerciseState? {
        guard restEndsAt != nil,
              let resting = restingExercise,
              let current = currentSet?.exercise,
              current.name != resting
        else { return nil }
        return current
    }

    // MARK: - Init

    init(
        day: ProgramDay,
        phase: ProgramPhase,
        store: AppDatabase? = nil,
        userId: String = "preview",
        startedAt: Date? = nil,
        openingForEdit: Bool = false,
        warmupBout: WarmupCardio.Bout? = nil
    ) {
        self.day = day
        self.programDay = day
        self.phase = phase
        self.store = store
        self.userId = userId
        self.openingForEdit = openingForEdit
        self.startedAt = startedAt ?? Date()
        // ── WHETHER THE CALLER HAD AN OPINION ABOUT THE CLOCK ───────────────
        // `attach` may adopt a start banked before the first set created a
        // session row (`LiveSessionStart`), and it must only do that for a deck
        // that has no start of its own. A caller that named one — the edit path
        // hands over the session's own `started_at` — has the better answer,
        // and adopting something OLDER than a deliberately chosen instant is
        // the failure `attachWithoutALiveSessionKeepsTheOpeningClock` exists to
        // catch.
        self.startedAtWasGiven = startedAt != nil
        let opened = Self.loadSeed(store: store, day: day, phase: phase, userId: userId)
        self.seed = opened.seed
        self.progressionAlerts = opened.alerts
        // Read ONCE, at init. The stored order is last week's answer and the
        // live deck is this week's; re-reading it on a phase switch would let a
        // week-old template argue with a card the athlete has just dragged.
        //
        // ── AND AN EDIT DECK HAS NO USE FOR IT AT ALL (W2) ──────────────────
        // `deckOrder(dayKey:)` answers with the MOST RECENT session on this day
        // key, which on an edit is almost never the session being edited. So
        // `inDeckOrder` ranked a three-week-old workout against last Tuesday's
        // running order, and any movement last Tuesday did not contain got no
        // rank at all — `placed ?? (count + index)` — and sorted to the BOTTOM.
        // The treadmill is the movement that happens to, every time, because it
        // is the one the opener prepends rather than the program naming it: the
        // "treadmill drops to the bottom on edit" report, whose cause is not
        // `exercise_order` (the phone has written that for every cardio row
        // since `v16.exerciseOrder`; the live table has no null among them).
        //
        // `SessionDetailView.editorDay` already builds the deck in the session's
        // own performed order. That IS the stored answer for a finished session,
        // and nothing else gets a vote.
        self.storedDeckOrder = openingForEdit
            ? []
            : ((try? store?.deckOrder(dayKey: day.key, userId: userId)) ?? [])
        // Read once, like the deck order above, and for the same reason: it
        // cannot change mid-session and a per-rebuild query would be a
        // catalogue read on every phase switch.
        self.warmupBout = warmupBout ?? WarmupCardio.seed(from: Self.lastBout(store, userId: userId))
        rebuildForPhase()
    }

    /// The seed, or the program's cold start when there is no store.
    ///
    /// Synchronous, like `attach`'s own reads: it is one query over one day
    /// key's sessions and their sets, and a deck that draws the plan first and
    /// the real loads a frame later is a deck that moves under the reader's
    /// thumb. A store failure falls back to the cold start rather than taking
    /// the screen down — the same trade `attach` makes.
    private static func loadSeed(
        store: AppDatabase?, day: ProgramDay, phase: ProgramPhase, userId: String
    ) -> SeededDeck {
        // The deck IS this day: the seed only needs `program.day(key:)`, and a
        // one-day program is exactly what the caller handed in.
        let program = Program(id: "", label: "", days: [day])
        let cold = SeededDeck(
            seed: SessionSeedBuilder.build(
                dayKey: day.key, today: LogicalDay.today(), phase: phase, sessions: [], sets: [],
                program: program, planOwning: { _ in "" }
            ),
            alerts: []
        )
        guard let store else { return cold }
        return (try? store.sessionSeed(dayKey: day.key, userId: userId, phase: phase, program: program)) ?? cold
    }

    // MARK: - Deck

    /// Build (or rebuild) the deck for the active phase.
    ///
    /// Rows already logged are PRESERVED across a phase switch. Cutting removes
    /// prescribed sets, and silently deleting work you have already done to
    /// honour a prescription would be the store losing a set to enforce a UI
    /// rule — the same mistake `ingest` is explicitly written not to make.
    private func rebuildForPhase() {
        // ── KEYED ON THE PLAN, AND TOLERANT OF A DUPLICATE ──────────────────
        // `ExerciseState.id` is minted now, so it is no longer the key a plan
        // is found under — `day.exercises` below is walked by `plan.id`.
        //
        // `uniquingKeysWith` and not `uniqueKeysWithValues`: the latter TRAPS
        // on a duplicate key, and a deck carrying two cards for one movement
        // (the duplicated treadmill) crashed here on the next phase switch
        // rather than drawing wrong. First one wins, matching `DeckRestore`'s
        // own rule — and the duplicate cannot be built any more anyway.
        let existing = Dictionary(exercises.map { ($0.plan.id, $0) }, uniquingKeysWith: { first, _ in first })
        // The order the deck is in RIGHT NOW, captured before it is rebuilt —
        // `existing.keys` is a Dictionary's, which has none. See `inDeckOrder`.
        let liveOrder = exercises.map(\.id)
        // Iterating the FULL deck rather than `day.exercises(for: phase)` is
        // what lets a dropped lift survive below — the filtered list does not
        // contain it to be rescued.
        exercises = day.exercises.compactMap { plan in
            let prescribed = plan.sets(for: phase)
            guard let previous = existing[plan.id] else {
                guard prescribed > 0 else { return nil }
                return ExerciseState(plan: plan, rows: seedRows(plan, count: prescribed))
            }

            // ── WARM-UPS ARE NOT PART OF THE PRESCRIPTION ───────────────
            // `prescribed` counts WORKING sets, and since P3 E4 the deck also
            // carries last session's warm-ups. Measuring against a `logged`
            // that includes them makes a phase switch DELETE working rows you
            // have not done yet: two ticked warm-ups and one working set read
            // as three against a prescription of two, so the branch below
            // collapses the deck to the ticked rows and the two sets still to
            // do are gone with no way back but `addSet`.
            let working = previous.rows.filter { $0.kind != .warmup }
            let logged = working.filter(\.isDone)
            // A lift this phase DROPS (`cutSets: 0` — the wrist curl, the hip
            // adduction) keeps its place if it already carries work. Switching
            // to a cut mid-session must not take sets you have done off the
            // screen to satisfy a prescription: the events are still in the log
            // and a screen that disagrees with the log is worse than a screen
            // showing a lift the plan no longer asks for. A ticked WARM-UP is
            // work done too, which is why the guard reads every row.
            guard prescribed > 0 || previous.rows.contains(where: \.isDone) else { return nil }

            // ── COUNTED IN SETS, AND TRIMMED IN SETS ────────────────────────
            // `prescribed` is a number of SETS, and on a unilateral movement a
            // set is two rows. Counting rows here made a cut that asks for four
            // sets keep four ROWS — two sets, one arm each of the two it kept —
            // and `prefix` could cut a pair in half, leaving a left side with
            // no right that nothing downstream counts as a set at all.
            let loggedSets = Self.physical(logged)
            if loggedSets >= prescribed {
                previous.rows = previous.rows.filter(\.isDone)
            } else {
                // Trim the SURPLUS blanks, keeping the rows where they are.
                // Rebuilding as `logged + blanks` sorts the ticked rows to the
                // top, so a session where set 2 was skipped and set 3 logged
                // reorders itself under the reader on a phase switch.
                let blanks = Self.groups(working.filter { !$0.isDone })
                let wanted = prescribed - loggedSets
                let keep = Set(blanks.prefix(wanted).flatMap { $0.map(\.id) })
                // A warm-up row survives whatever the prescription says — it
                // was never counted against it.
                previous.rows = previous.rows.filter { $0.isDone || $0.kind == .warmup || keep.contains($0.id) }
                    + seedRows(plan, count: max(0, wanted - blanks.count), warmups: false)
            }
            return previous
        }
        exercises = Self.inDeckOrder(exercises, stored: storedDeckOrder, current: liveOrder.isEmpty ? nil : liveOrder)
        if let warmupBout, !openingForEdit {
            exercises = Self.withWarmupCardio(exercises, existing: existing, bout: warmupBout)
        }
        // ── A REBUILT DECK IS A MOVED DECK ──────────────────────────────────
        // This replaces `exercises` wholesale, so every identity the bar was
        // built on is potentially gone and `prsThisSession` still holds the
        // count from the deck that no longer exists. Neither was recomputed: a
        // phase switch mid-session dropped the trophies off the rows it had
        // already awarded them to, and the Live Activity's count went with them.
        // `refreshLivePrs` rebuilds the bar first when the ids moved, so this is
        // the whole of the fix.
        refreshLivePrs()
    }

    /// Put the deck in the order the athlete last left it.
    ///
    /// ── WHY THE PROGRAM'S ARRAY IS NOT THE ANSWER ───────────────────────────
    /// `day.exercises` is a constant, so building the deck by walking it puts
    /// every session back in the shipped order — which is what made a drag
    /// survive into the session report (`exercise_order` on the rows) and into
    /// nothing else. `SessionSeedBuilder` now orders its own list from
    /// `routine_templates`, so the seed is the stored answer and this follows
    /// it.
    ///
    /// `current` is the LIVE deck, and it wins where it has an opinion: a
    /// phase switch happens mid-session, and re-sorting the cards under a
    /// thumb that has just dragged one — to an order from last week, before the
    /// close that would have stored today's — is the screen arguing with the
    /// person using it.
    ///
    /// A movement neither knows keeps its program position, after the ones they
    /// place. `enumerated` is load-bearing: `sorted(by:)` is not stable, and two
    /// unplaced lifts must not swap between two builds of the same day.
    /// Put the treadmill at the top, unless the deck already opens with cardio.
    ///
    /// ── WHY IT IS PREPENDED HERE AND NOT LISTED IN THE PROGRAM ──────────────
    /// See `WarmupCardio` for why the program type cannot express it. This is
    /// the phone's half of `withWarmupCardio` in `templateDraft.ts`, and it runs
    /// on the same terms: once, at the top, only when nothing cardio is there
    /// already — and never for a session being EDITED, where the deck is a
    /// record of what happened and a movement the projection does not carry has
    /// no business appearing in it.
    ///
    /// ── AND WHY THE ROW SURVIVES A REBUILD ──────────────────────────────────
    /// `rebuildForPhase` runs on every phase switch and keys `existing` on
    /// `plan.id`. The synthetic plan's id is its name, so a treadmill already on
    /// the deck — ticked, with its five minutes logged — is found there and
    /// handed back untouched. Minting a fresh one would replace a row that has
    /// an id in `set_events` with one that does not, and the tick would be lost
    /// with the log still holding it.
    /// Does this athlete's catalogue know the movement the warm-up prescribes?
    ///
    /// ── WHY THIS IS A READ AND NOT A RULE (W5, REWRITTEN THIS WAVE) ────────
    /// The opener used to be a FOUNDER HARDCODE: a named movement, a distance,
    /// an incline and a pace note, prepended to every session of every account.
    /// A person who had never owned a treadmill opened their first session to
    /// five minutes of one.
    ///
    /// W5 put a gate in front of it — prescribe the movement only to an athlete
    /// whose CATALOGUE holds it — which kept it off a new account and left it
    /// just as arbitrary for the accounts it did reach. A catalogue row says
    /// the movement exists, never that this athlete warms up on it.
    ///
    /// The question the opener actually asks is "what did you last do", and
    /// `cardio_logs` is where that is written — by hand on the Day screen, or
    /// by the HealthKit ingest. So: the last bout, cut to warm-up length. A
    /// walker gets their walk back, a cyclist gets their ride, and somebody who
    /// has logged nothing gets no card, because there is nothing to repeat.
    ///
    /// nil for a storeless model. That is a PREVIEW, not an athlete, and a
    /// fixture that wants the card hands one in (`warmupBout:`) rather than
    /// being given somebody's numbers by default.
    ///
    /// ── THE LAST TREADMILL, FROM EITHER PLACE ONE LIVES (Precision A2) ──────
    /// Any kind used to answer, and the founder's any-kind answer was an
    /// outdoor walk — cut to ten minutes, proposed as "1 km / 10 min" on a
    /// treadmill. Now: the newest `treadmill` row in `cardio_logs` (Health's
    /// indoor walks, Quick Log, and every deck bout filed at close since
    /// `recordSessionCardio`) against the newest treadmill set logged inside a
    /// deck (every bout before that). Newest DAY wins, then the later start; a
    /// tie is one bout seen twice, and the deck's row is the one an edit
    /// would have corrected.
    private static func lastBout(_ store: AppDatabase?, userId: String) -> WarmupCardio.Bout? {
        guard let store else { return nil }
        let filed = (try? store.lastCardioBout(userId: userId, kind: CardioImport.treadmill)) ?? nil
        let logged = (try? store.lastLoggedBout(named: WarmupCardio.name, userId: userId)) ?? nil
        if let logged, filed.map({ ($0.date, $0.createdAt ?? .distantPast) <= (logged.date, logged.start ?? .distantPast) }) ?? true {
            return WarmupCardio.Bout(
                name: WarmupCardio.name, durationSec: logged.durationSec,
                distanceKm: logged.distanceKm, inclinePct: logged.inclinePct
            )
        }
        guard let row = filed else { return nil }
        return WarmupCardio.Bout(
            name: CardioKind(row.kind).label,
            durationSec: Int(((row.durationMin ?? 0) * 60).rounded()),
            distanceKm: row.distanceM.map { $0 / 1000 },
            inclinePct: row.inclinePct
        )
    }

    private static func withWarmupCardio(
        _ exercises: [ExerciseState], existing: [String: ExerciseState], bout: WarmupCardio.Bout
    ) -> [ExerciseState] {
        // ── TWO TESTS, BECAUSE ONE OF THEM WAS BLIND ────────────────────────
        // The row test alone let the treadmill be prepended on top of a deck
        // that ALREADY held a treadmill card, and that is how a session came
        // back with the bout at the top and again at the bottom:
        //
        //   `SessionDetailView.editorDay` builds the edit deck in performed
        //   order, so a session that walked opens with a `Treadmill` card. At
        //   `init` that card held SEEDED rows, and `Self.setRow(SeedRow)`
        //   carried no `durationSec`, no `distanceKm` and no `incline` —
        //   `SeedRow` had no such fields. So the card did not look like cardio,
        //   this guard passed, and a second card was minted beside it.
        //
        // W2 gave `SeedSet` and `SeedRow` the three fields and `setRow` forwards
        // them, so the row test can see a seeded bout now. BOTH TESTS STAY. The
        // name test is what the row test cannot see (a card whose rows the seed
        // could not fill — the history tier refuses a movement with no working
        // sets, which every treadmill-only movement is), and the row test is
        // what the name test cannot see (a bike or a rower somebody put at the
        // top is cardio under another name). Neither is redundant; the bug was
        // having only one of them.
        let warmupKey = ExerciseAliases.canonicalName(bout.name)
        let alreadyThere = exercises.contains { card in
            card.rows.contains(where: \.isCardio)
                || ExerciseAliases.canonicalName(card.plan.name) == warmupKey
        }
        guard !alreadyThere else { return exercises }
        if let already = existing[bout.name] { return [already] + exercises }
        let plan = ProgramExercise(
            bout.name,
            sets: 1,
            wk1Kg: 0,
            // The window this bout is judged in, in the register the card's
            // prescription line already prints for a timed movement.
            reps: "\(bout.durationSec / 60) min",
            restSec: 0
        )
        let row = SetRow(
            weightKg: 0, reps: 0,
            // A warm-up, which is what the 7 September backfill wrote and what
            // keeps it out of tonnage, `workingSets` and the PR engine.
            kind: .warmup,
            durationSec: bout.durationSec,
            incline: bout.inclinePct,
            distanceKm: bout.distanceKm
        )
        return [ExerciseState(plan: plan, rows: [row])] + exercises
    }

    private static func inDeckOrder(
        _ exercises: [ExerciseState], stored: [String], current: [String]?
    ) -> [ExerciseState] {
        var rank: [String: Int] = [:]
        for (i, name) in stored.enumerated() {
            rank[ExerciseAliases.canonicalName(name)] = i
        }
        let live = current.map { ids in Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) }) }
        let count = exercises.count
        return exercises.enumerated()
            .map { index, exercise -> (Int, Int, ExerciseState) in
                let key = ExerciseAliases.canonicalName(exercise.plan.name)
                let placed = live?[exercise.id] ?? rank[key]
                return (placed ?? (count + index), index, exercise)
            }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
            .map(\.2)
    }

    /// The seeded rows for one movement.
    ///
    /// ── THIS USED TO BE `wk1Kg`, AND THAT WAS THE BUG ───────────────────────
    /// Every row opened on the program's week-1 load with the literal string
    /// `"<wk1Kg>kg × <floor>"` in the Previous column. After six months of
    /// training that is not a seed and it is not a previous set; it is a number
    /// with the shape of one, and it read as arbitrary data because it was.
    /// `SessionSeed` answers with the last session logged on this routine day —
    /// matched by NAME, so a web-logged session counts — the stored template, or
    /// the cold start, and it says which.
    ///
    /// `count` is the number of WORKING rows wanted, which is the prescription
    /// for the phase. Warm-ups carried from last time ride on top of it and are
    /// requested only when the whole deck is being built: a phase switch that
    /// asks for two more rows is asking for two more working sets.
    private func seedRows(_ plan: ProgramExercise, count: Int, warmups: Bool = true) -> [SetRow] {
        let seeded = seed.exercises.first { ExerciseAliases.canonicalName($0.name) == ExerciseAliases.canonicalName(plan.name) }
        // ── A MOVEMENT ADDED MID-SESSION (W3) ───────────────────────────────
        // No HISTORY entry, and the narrow lookup found it lifted somewhere:
        // every row opens on that set, the way the history tier repeats a set
        // it has one of. `lastTimes` is only ever filled by `appendCard`, so a
        // card the day opened with never reads this.
        if seeded?.source != .history, let last = lastTimes[canonicalKey(plan.name)] {
            let rows = (0..<max(0, count)).map { _ in
                SetRow(weightKg: last.weightKg, reps: last.reps, previous: last.label)
            }
            return Unilateral.isUnilateral(plan.name) ? Self.presplit(rows) : rows
        }
        let rows = seeded?.rows ?? []
        let working = rows.filter { $0.kind == .normal }
        var out: [SetRow] = warmups ? rows.filter { $0.kind == .warmup }.map(Self.setRow) : []
        for i in 0..<max(0, count) {
            // A count above what the seed produced (a phase switch to bulk)
            // repeats its last row rather than falling back to `wk1Kg`: the
            // load you are handling is a better proposal than the one from July.
            if i < working.count {
                out.append(Self.setRow(working[i]))
            } else if let last = working.last {
                // Past what the seed produced: the last known LOAD at the rep
                // FLOOR, which is what `SessionSeedBuilder.workingRows` does for
                // the same case. Copying the last row verbatim would carry its
                // reps too, and the two sides would answer differently.
                let carried = Self.setRow(last)
                carried.reps = plan.repWindow?.floor ?? carried.reps
                out.append(carried)
            } else {
                out.append(SetRow(weightKg: plan.wk1Kg))
            }
        }
        // ── A LUNGE OPENS AS TWO SIDES ──────────────────────────────────────
        // Only for the movements `Unilateral` names, and only on rows the deck
        // is proposing — a restored session is what it was, and re-splitting it
        // here would invent rows the projection does not hold.
        return Unilateral.isUnilateral(plan.name) ? Self.presplit(out) : out
    }

    /// Every row as an L/R pair, sharing a fresh `pairId`.
    private static func presplit(_ rows: [SetRow]) -> [SetRow] {
        rows.flatMap { row -> [SetRow] in
            guard row.pairId == nil else { return [row] }
            let pairId = newOnyxID()
            return ["left", "right"].map { side in
                SetRow(
                    weightKg: row.weightKg, reps: row.reps, rpe: row.rpe,
                    kind: row.kind, qualities: row.qualities,
                    previous: row.previous, rpeStale: row.rpeStale,
                    progressed: row.progressed, side: side, pairId: pairId
                )
            }
        }
    }

    /// One seeded row, as the deck holds it.
    ///
    /// ── AND IT CARRIES THE BOUT, WHICH IT USED NOT TO ───────────────────────
    /// `SeedRow` had no `durationSec`, `incline` or `distanceKm`, so a seeded
    /// treadmill card came back as a lift of nothing: `SetRow.isCardio` false,
    /// no Cardio tag, `primaryMuscle`'s row test with nothing to find, and
    /// `withWarmupCardio` unable to see that the deck already held a bout — it
    /// needed a second, name-based test to cover for this one. W2 gave the seed
    /// the three fields; this forwards them.
    private static func setRow(_ row: SeedRow) -> SetRow {
        SetRow(
            weightKg: row.weightKg,
            reps: row.reps,
            rpe: row.rpe,
            kind: row.kind == .warmup ? .warmup : .normal,
            previous: row.previous,
            rpeStale: row.rpeStale,
            progressed: row.progressed,
            durationSec: row.durationSec,
            incline: row.incline,
            distanceKm: row.distanceKm
        )
    }

    /// What this exercise's rows are seeded FROM, for the deck's own label.
    /// Nil when nothing was logged — the cold start says nothing rather than
    /// naming a date that does not exist.
    func seededFrom(_ exercise: ExerciseState) -> String? {
        seed.exercises
            .first { ExerciseAliases.canonicalName($0.name) == ExerciseAliases.canonicalName(exercise.name) }?
            .seededFrom
    }

    // MARK: - Editing

    func addSet(to exercise: ExerciseState) {
        // The new row inherits the last one's load, which is what the next set
        // almost always is. Reps are NOT inherited: on double progression the
        // rep count is the thing you are trying to change.
        let last = exercise.rows.last
        let weightKg = last?.weightKg ?? exercise.plan.wk1Kg
        let kind: SetKind = last?.kind == .warmup ? .normal : (last?.kind ?? .normal)
        // The set beyond the prescription has no seeded previous — history
        // does not contain a set number that has never been programmed.
        let previous = seededPrevious(
            exercise.plan, workingIndex: Self.physical(exercise.rows.filter { $0.kind != .warmup })
        )
        // ── A SET ADDED TO A UNILATERAL MOVEMENT IS A PAIR ──────────────────
        // The deck pre-splits every SEEDED row of a lunge (see `presplit`) and
        // this added one plain, so the fourth set of a movement logged one arm
        // at a time was the only bilateral set on the card — scored twice by
        // `SessionVolume` where its neighbours are scored at the weaker side,
        // and drawn as a single line under three split ones. It has to be the
        // same shape as the sets it sits with.
        guard canSplit(exercise) else {
            exercise.rows.append(SetRow(weightKg: weightKg, kind: kind, previous: previous))
            return
        }
        let pairId = newOnyxID()
        exercise.rows.append(contentsOf: ["left", "right"].map { side in
            SetRow(weightKg: weightKg, kind: kind, previous: previous, side: side, pairId: pairId)
        })
    }

    // MARK: - Adding a movement mid-session (W3)

    /// What the Muscle Shelf opens on (Precision A1): the catalogue minus the
    /// archived rows, the two pinned shelves, and every row's last time.
    ///
    /// Four reads when the sheet opens and none per row — `lastWorkingSets`
    /// is ONE pass over the ledger for the whole catalogue. The fifteen
    /// starter movements are created here first, once, so a new account's
    /// library has them without the SQL (`StarterMovements`).
    ///
    /// Empty for a storeless preview, where the picker still offers to create.
    func library() -> ExerciseLibrary {
        let span = Perf.begin("library.open")
        defer { Perf.end(span) }
        guard let store else { return ExerciseLibrary(catalogue: []) }
        var catalogue = (try? store.libraryExercises()) ?? []
        if StarterMovements.ensure(in: store, userId: userId, catalogue: catalogue) > 0 {
            catalogue = (try? store.libraryExercises()) ?? catalogue
        }
        // The deck is excluded from both pinned shelves: a movement already
        // on it is one tap away, and picking it only scrolls to its card.
        let onDeck = Set(exercises.map { canonicalKey($0.name) })
        let recent = ((try? store.recentMovements(userId: userId, limit: 10 + onDeck.count)) ?? [])
            .filter { !onDeck.contains(canonicalKey($0)) }
            .prefix(10)
        let onThisDay = day.exercises.map(\.name).filter { !onDeck.contains(canonicalKey($0)) }
        let lastSets = (try? store.lastWorkingSets(
            names: catalogue.map(\.name) + onThisDay, userId: userId, excludingSession: sessionId
        )) ?? [:]
        return ExerciseLibrary(
            catalogue: catalogue, recent: Array(recent), onThisDay: onThisDay, lastSets: lastSets
        )
    }

    /// Put a movement on the deck that today's program does not name.
    ///
    /// Returns the card — the NEW one, or the one already on the deck for this
    /// movement. Two cards for one movement is the defect `DeckRestore.fold`
    /// and `ExerciseState.id` both exist to survive (the duplicated treadmill);
    /// asking for a movement you are already doing takes you to it instead.
    ///
    /// `exerciseId` is the catalogue row the picker chose, when it chose one:
    /// the card's sets are then filed under it rather than re-resolved by name,
    /// which for a name two rows answer to would fall to the slug.
    @discardableResult
    func addExercise(named name: String, exerciseId: String? = nil) -> ExerciseState? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = canonicalKey(trimmed)
        if let already = exercises.first(where: { canonicalKey($0.name) == key }) { return already }
        let planned = day.exercises.contains { canonicalKey($0.name) == key }
        let card = appendCard(named: trimmed, exerciseId: exerciseId)
        if isEditing { addedWhileEditing.append((key, !planned)) }
        return card
    }

    /// One card, appended at the bottom of the deck.
    ///
    /// ── IT JOINS THE DAY, NOT JUST THE DECK ─────────────────────────────────
    /// `rebuildForPhase` rebuilds `exercises` by walking `day.exercises`, so a
    /// card that lived only in the array was gone at the next phase switch,
    /// ticked sets and all. Appended to `day` it is rebuilt like any other,
    /// and `plannedSets` counts it — you added it to do it.
    ///
    /// ── AND IT TAKES THE NEXT `exercise_order`, NOTHING RESTAMPS ────────────
    /// `deckOrder(of:)` is the card's index, dense from 0, so the last card's
    /// sets are written under `count − 1` and no other card's position moved.
    ///
    /// A plan the day already holds — a lift this phase drops, which is on no
    /// card — is reused rather than listed twice: two plans with one `id` is
    /// two cards for one movement on the next rebuild.
    @discardableResult
    private func appendCard(named name: String, exerciseId: String? = nil) -> ExerciseState {
        let key = canonicalKey(name)
        let plan: ProgramExercise
        if let known = day.exercises.first(where: { canonicalKey($0.name) == key }) {
            plan = known
        } else {
            var starting = RoutineExercise.starting(name)
            starting.exerciseId = exerciseId
            plan = starting.programExercise
            day.exercises.append(plan)
        }
        // The narrow lookup, and only where the day's seed has no HISTORY to
        // say. A program- or template-tier entry is a plan, not a memory, and
        // it no longer suppresses the athlete's own last set (Precision A1).
        // Never on an edit deck: `lastWorkingSet` has no date bound, so on a
        // three-week-old session it would answer with a workout that happened
        // AFTER it — the reason `restoreLoggedSets` blanks every Previous there.
        if !isEditing, !seed.exercises.contains(where: { canonicalKey($0.name) == key && $0.source == .history }),
           let last = try? store?.lastWorkingSet(named: plan.name, userId: userId, excludingSession: sessionId) {
            lastTimes[key] = last
        }
        let prescribed = plan.sets(for: phase)
        let card = ExerciseState(plan: plan, rows: seedRows(plan, count: prescribed > 0 ? prescribed : plan.sets))
        exercises.append(card)
        return card
    }

    /// Discard's other half: the cards this sitting added leave the deck, and
    /// a plan they brought leaves `day` with them.
    private func dropCardsAddedWhileEditing() {
        // By KEY, and the plan goes whether or not a card is still on the
        // deck: a phase switch can drop the card and mint another.
        for added in addedWhileEditing {
            exercises.removeAll { canonicalKey($0.name) == added.key }
            if added.appendedPlan { day.exercises.removeAll { canonicalKey($0.name) == added.key } }
        }
        addedWhileEditing = []
    }

    // MARK: - Warm-up rungs (W6)

    /// The weight a warm-up ladder on this card is built from, or nil when the
    /// movement has nothing to ramp to — bodyweight, timed, or the cardio card.
    func warmupTarget(_ exercise: ExerciseState) -> Double? {
        guard !BodyweightExercise.isUnloaded(exercise.name),
              !exercise.rows.contains(where: \.isCardio)
        else { return nil }
        return Warmup.target(workingKg: exercise.rows.filter { $0.kind != .warmup }.compactMap(\.weightKg))
    }

    /// Add one rung.
    ///
    /// ── WHY IT IS INSERTED, NOT APPENDED ────────────────────────────────────
    /// A warm-up belongs before the work, and within the warm-ups it belongs in
    /// load order. Appending would put a 40% rung under a 75% one whenever they
    /// were tapped out of order, and the deck would draw a ladder that descends
    /// — which reads as a mistake even though every row in it is right.
    ///
    /// ── AND WHY NOTHING STOPS A DUPLICATE ───────────────────────────────────
    /// Two sets at 50% is a legitimate ramp, and refusing the second tap would
    /// make the chip row a set of switches rather than a set of buttons. The
    /// undo is the row's own delete, which is where every other unwanted set on
    /// this card is removed.
    func addWarmup(percent: Int, to exercise: ExerciseState) {
        guard let target = warmupTarget(exercise) else { return }
        let weightKg = Warmup.load(percent: percent, of: target)
        let reps = Warmup.reps(percent: percent)

        // The first row that is not a warm-up — the top of the working block.
        let insertAt = exercise.rows.firstIndex { $0.kind != .warmup } ?? exercise.rows.count
        // A warm-up with no weight yet (one the user blanked) sorts to the top
        // rather than swallowing the comparison: `nil > 20` is not false, it is
        // not expressible, and defaulting it to 0 is the honest reading.
        let ordered = exercise.rows[..<insertAt].firstIndex { ($0.weightKg ?? 0) > weightKg } ?? insertAt

        // Same shape as the sets it sits with: a lunge warms up one side at a
        // time, exactly as `addSet` splits a working set (see `presplit`).
        guard canSplit(exercise) else {
            exercise.rows.insert(SetRow(weightKg: weightKg, reps: reps, kind: .warmup), at: ordered)
            restampFrom(ordered, in: exercise)
            return
        }
        let pairId = newOnyxID()
        exercise.rows.insert(
            contentsOf: ["left", "right"].map { side in
                SetRow(weightKg: weightKg, reps: reps, kind: .warmup, side: side, pairId: pairId)
            },
            at: ordered
        )
        // ── A MID-ARRAY INSERT MUST RESTAMP WHAT IT PUSHED DOWN ─────────────
        // `snapshot(_:in:)` derives the stored `set_index` from array POSITION,
        // and seeding matches a row on `(exercise_id, set_index)`. A rung added
        // after a working set was ticked shifts every logged row below it by
        // one (two on a pair) and leaves their stored indices behind — which
        // collides two rows on one key and mis-orders the session report and
        // the sync payload. `removeSet` and `mergeSet` repair it for the same
        // reason; this insert is the third mid-array mutation and needs it too.
        restampFrom(ordered, in: exercise)
    }

    /// Re-write the stored `set_index` of every logged row from `index` down.
    private func restampFrom(_ index: Int, in exercise: ExerciseState) {
        guard store != nil, sessionId != nil else { return }
        for row in exercise.rows[min(index, exercise.rows.count)...] where row.isDone {
            amendInStore(row, in: exercise)
        }
    }

    /// Move a movement in the deck, and carry the new order into the store.
    ///
    /// ── A REORDER THAT DOES NOT PERSIST LOOKS LIKE ONE YOU DID NOT MAKE ─────
    /// The array is what the deck draws, and the array alone survives exactly
    /// as long as this object does. `exercise_order` on the rows is what the
    /// session report reads back, on this device and on the web, so the two
    /// have to move together or the drag is a piece of theatre.
    ///
    /// Only the movements BETWEEN the two positions shift, so only their logged
    /// rows are re-amended — every other card's stored order is still correct,
    /// and an amend that restates a row is permanent noise in a log that is
    /// never compacted. In edit mode it is more than noise: each one is a seed,
    /// a PR replay, a recount and an outbox upsert.
    ///
    /// `to` is a destination INDEX, not a `List.onMove` insertion offset. The
    /// deck is a `LazyVStack`, there is no `onMove` here, and the off-by-one
    /// between the two conventions is the kind that only shows up when you drag
    /// downwards.
    ///
    /// ── THE ARITHMETIC MOVED TO `DeckOrder` IN W3 ───────────────────────────
    /// The wrist's "Do next" writes the same `exercise_order` onto the same
    /// rows, and the two clients agreeing about WHICH rows moved is what keeps
    /// a session grouped the way it was performed on whichever device reads it
    /// back. Shared rather than reimplemented, with a golden vector under it
    /// (`deck-order-move.json`) and a test that this call site's old inline
    /// version and the extracted one answer identically on every deck size.
    func moveExercise(from: Int, to: Int) {
        let move = DeckOrder.move(count: exercises.count, from: from, to: to)
        guard let restamp = move.restamp else { return }
        exercises = move.applied(to: exercises)
        guard store != nil, sessionId != nil else { return }
        for exercise in exercises[restamp] {
            for row in exercise.rows where row.isDone { amendInStore(row, in: exercise) }
        }
    }

    func removeSet(_ row: SetRow, from exercise: ExerciseState) {
        guard let index = exercise.rows.firstIndex(where: { $0.id == row.id }) else { return }
        let wasDone = row.isDone
        if wasDone { voidInStore(row) }
        exercise.rows.remove(at: index)
        restampFrom(index, in: exercise)
        // Deleting a ticked set can PROMOTE a later one: a record is judged
        // against everything before it in the session, so removing the set that
        // was superseding it hands the axis back.
        if wasDone { refreshLivePrs() }
    }

    func setKind(_ kind: SetKind, on row: SetRow, in exercise: ExerciseState) {
        row.kind = kind
        if row.isDone {
            amendInStore(row, in: exercise)
            // A warm-up and a ghost set no bar and win no record, so the badge
            // has to clear — and the set that was standing behind this one may
            // now win the axis it was losing.
            refreshLivePrs()
        }
    }

    /// Passing a value the set already carries WITHDRAWS it — the same rule
    /// the RPE ladder follows, and for the same reason: a claim about your form
    /// that you cannot take back is a claim you stop making.
    ///
    /// `nil` clears the lot, which is what the sheet's own "clear" path wants
    /// and what the old one-value signature meant by it.
    func setQuality(_ quality: SetQuality?, on row: SetRow, in exercise: ExerciseState) {
        guard let quality else {
            row.qualities = []
            if row.isDone { amendInStore(row, in: exercise) }
            return
        }
        var next = Set(row.qualities)
        if next.contains(quality) { next.remove(quality) } else { next.insert(quality) }
        // Canonical order, always. The stored string is compared to decide
        // whether an amend is worth appending, and a list that reordered itself
        // would seed the event log on every tap.
        row.qualities = SetQuality.allCases.filter(next.contains)
        if row.isDone { amendInStore(row, in: exercise) }
    }

    // MARK: - Unilateral

    /// Split one set into an independent Left and Right.
    ///
    /// ── WHAT A PAIR IS, AND WHY IT IS NOT TWO SETS ──────────────────────────
    /// Two rows sharing a `pairId`, one `side` each, are ONE set of work
    /// everywhere it is counted: `SessionVolume` scores them at the weaker side
    /// (`min(weight) × min(reps)`), `physical` counts the pairId once, and the
    /// PR engine judges the pair rather than the arms. That is the whole reason
    /// splitting is offered only on movements `Unilateral.isUnilateral` names —
    /// a barbell press split in half is a session logged at half its size.
    ///
    /// The two sides open on the SAME numbers, and on the same `kind`: a warm-up
    /// split into two `normal` sides is work the PR engine then judges, which is
    /// the bug the web fixed in its own `splitSet` and left a comment on.
    func splitSet(_ row: SetRow, in exercise: ExerciseState) {
        guard let index = exercise.rows.firstIndex(where: { $0.id == row.id }) else { return }
        guard row.pairId == nil else { return }
        // A ticked set is voided first: the pair is genuinely two new rows in
        // the log, and re-using the id of the set they replace would put an
        // append behind a tombstone (`SetEventFold` rule 3) and lose both.
        let wasDone = row.isDone
        if wasDone { voidInStore(row) }

        let pairId = newOnyxID()
        func half(_ side: String) -> SetRow {
            SetRow(
                weightKg: row.weightKg, reps: row.reps, rpe: row.rpe,
                kind: row.kind, qualities: row.qualities, isDone: false,
                previous: row.previous, rpeStale: row.rpeStale,
                progressed: row.progressed, side: side, pairId: pairId,
                // ── THE MEASURED AXES COME ACROSS TOO ───────────────────────
                // They did not, and the omission was invisible on everything
                // the deck had ever been asked to split: a hold carries its
                // SECONDS in `reps` (`TimedExercise`'s convention, the same one
                // `PrEngine` scores the duration axis on), so a Side Plank
                // survived by luck. Anything actually carrying `durationSec` —
                // a bout, a restored cardio row — split into two halves with
                // the measurement erased, which is a set the deck would then
                // refuse to tick at all (`canLog` tests reps OR cardio).
                durationSec: row.durationSec, incline: row.incline,
                distanceKm: row.distanceKm, elevationM: row.elevationM
            )
        }
        let sides = [half("left"), half("right")]
        exercise.rows.replaceSubrange(index...index, with: sides)
        // Re-ticked rather than carried: `toggleDone` is the only path that
        // appends, and going through it is what keeps the rest timer, the live
        // PR pass and the store in step with a row that says it is logged.
        if wasDone { for side in sides { toggleDone(side, in: exercise) } }
        restampFrom(index, in: exercise)
        refreshLivePrs()
    }

    /// Collapse a pair back into one two-sided set.
    ///
    /// ── THE WEAKER SIDE SURVIVES ────────────────────────────────────────────
    /// The web keeps LEFT's numbers, which is arbitrary and generous. The
    /// founder's call here is the weaker side — `min` on each of load and reps,
    /// which is exactly what `SessionVolume` already scored the pair at. So a
    /// pair merged weighs what it weighed split, and un-splitting can never
    /// invent tonnage that was not performed.
    func mergeSet(pairId: String, in exercise: ExerciseState) {
        let members = exercise.rows.filter { $0.pairId == pairId }
        guard members.count > 1, let index = exercise.rows.firstIndex(where: { $0.pairId == pairId }) else { return }
        let wasDone = members.contains(where: \.isDone)
        for row in members where row.isDone { voidInStore(row) }

        let merged = SetRow(
            weightKg: members.compactMap(\.weightKg).min(),
            reps: members.compactMap(\.reps).min(),
            // The rating is the HARDER of the two: an arm that went to failure
            // is what the set cost, and averaging two efforts describes neither.
            rpe: members.compactMap(\.rpe).max(),
            kind: members.first?.kind ?? .normal,
            qualities: SetQuality.allCases.filter { q in members.contains { $0.qualities.contains(q) } },
            isDone: false,
            previous: members.first?.previous,
            // The weaker side on every measured axis too, for the reason the
            // load and the reps take it: a merge must never invent work. The
            // symmetric half of `splitSet`'s copy — without it, merging a pair
            // that carried a measurement erased it.
            durationSec: members.compactMap(\.durationSec).min(),
            incline: members.compactMap(\.incline).min(),
            distanceKm: members.compactMap(\.distanceKm).min(),
            elevationM: members.compactMap(\.elevationM).min()
        )
        exercise.rows.removeAll { $0.pairId == pairId }
        exercise.rows.insert(merged, at: min(index, exercise.rows.count))
        if wasDone { toggleDone(merged, in: exercise) }
        restampFrom(index, in: exercise)
        refreshLivePrs()
    }

    /// Whether this movement may be split at all. One question, one answer —
    /// `Unilateral` is the ported catalogue rule and it is vector-equal with
    /// `isUnilateralExercise` on the web.
    func canSplit(_ exercise: ExerciseState) -> Bool {
        Unilateral.isUnilateral(exercise.name)
    }

    /// Tick or untick a set.
    ///
    /// Ticking is the moment the set becomes a fact, so it is the moment the
    /// event is appended, the rest timer starts and the Live Activity updates.
    /// Unticking appends a tombstone rather than deleting anything.
    @discardableResult
    func toggleDone(_ row: SetRow, in exercise: ExerciseState) -> Bool {
        let tick = Perf.begin("set.tick")
        defer { Perf.end(tick) }
        if row.isDone {
            row.isDone = false
            row.isRecord = false
            voidInStore(row)
            refreshLivePrs()
            // ── AN UNTICK CANCELS THE REST IT STARTED ───────────────────────
            // Ticking a set starts the countdown; unticking it — which is what
            // you do the instant you realise you ticked the wrong row — left
            // the clock running, the bar on the deck counting down and the
            // watch showing a full-screen rest cover for a set that no longer
            // exists. The only way out was `Skip rest`, which reads as a
            // decision about your training rather than as an undo.
            //
            // Unconditional, and not "only when this row started it": the deck
            // has ONE rest clock, `startRest` overwrites it on every tick, and
            // nothing records which set it belongs to. A guard would therefore
            // have to guess, and the guess is wrong exactly when two sets are
            // ticked in quick succession — the case this is for.
            stopRest()
            return false
        }
        // A set with no reps has not happened. Ticking it would put a zero into
        // the tonnage and a zero into the history.
        //
        // ── UNLESS ITS CONTENT IS NOT REPS ──────────────────────────────────
        // A treadmill bout is five minutes at incline 2 for 0.37 km and zero of
        // everything this guard measures. Untick-then-retick is the single most
        // ordinary gesture on the edit deck; refusing the SECOND half of it on
        // that row made the first half a deletion with no undo — the void is
        // terminal in the log and gets pushed. The row still has to have
        // happened, which for a cardio set is `isCardio`.
        guard (row.reps ?? 0) > 0 || row.isCardio else { return false }
        // The wrist's Crown rated the LAST set during the rest this tick ends
        // (overhaul A3): the tick is the commit (decision Q2).
        commitProvisionals()
        row.isDone = true
        appendInStore(row, in: exercise)
        refreshLivePrs()
        // A rest timer on a session that ended three weeks ago is a countdown
        // for nobody. Every other live affordance on this screen is already
        // guarded in the view; this one is in the model because that is where
        // the tick happens.
        if !isEditing { startRest(for: exercise) }
        return true
    }

    /// Tick or untick a whole SET — both arms of a pair, one badge.
    ///
    /// ── WHY THE VIEW CANNOT JUST CALL `toggleDone` TWICE ────────────────────
    /// It can, and that is what this does — but only on the rows that are not
    /// already in the state the box is moving to. A pair with one side ticked
    /// (a restored session, a watch sync that landed mid-set) would otherwise
    /// flip BOTH and end up exactly as split as it started, with the tick
    /// having moved to the other arm.
    ///
    /// The rest timer takes care of itself: `startRest` overwrites one clock,
    /// so ticking two rows in the same gesture sets the same deadline twice.
    @discardableResult
    func toggleGroup(_ rows: [SetRow], in exercise: ExerciseState) -> Bool {
        let done = rows.allSatisfy(\.isDone)
        var became = false
        for row in rows where row.isDone == done {
            became = toggleDone(row, in: exercise) || became
        }
        return became
    }

    func commitEdit(_ row: SetRow, in exercise: ExerciseState) {
        guard row.isDone else { return }
        amendInStore(row, in: exercise)
        refreshLivePrs()
    }

    // MARK: - The wrist's Crown RPE (overhaul A3, decision Q2)

    /// A rating the watch's Crown is scrubbing for a set, not yet written.
    struct ProvisionalEffort: Equatable {
        let rpe: Double
        let band: EffortBand
        let at: Date
    }

    /// Provisional ratings by `SetRow.storeId`. Drawn as tinted ink with a
    /// band capsule on the deck card; NEVER persisted — nothing here reaches
    /// `set_events` until `commitProvisional` writes it through the ordinary
    /// `commitEdit`, and only onto a ticked set (an unticked set's RPE is not
    /// a fact yet — the same rule `commitEdit` enforces).
    private(set) var provisionalEffort: [String: ProvisionalEffort] = [:]

    /// How long a provisional rating is worth showing. A scrub is seconds;
    /// ten minutes is the rest after it and then some.
    static let provisionalLifetime: TimeInterval = 10 * 60

    /// Take a Crown pulse. The set is the pulse's own id when this deck holds
    /// it, else the last ticked set of the movement resting now — a W0 sender,
    /// or a wrist that never folded the session.
    func receiveEffort(_ pulse: EffortPulse, now: Date = Date()) {
        guard pulse.sessionId == sessionId else { return }
        let rows = exercises.flatMap(\.rows)
        // The fallback is for a pulse that names NO set. One that names a set
        // this deck does not hold yet (a wrist-logged set still in the queue)
        // is dropped, not re-aimed at the previous set (after review).
        let target = pulse.setId.map { id in rows.first { $0.storeId == id } }
            ?? exercises.first { $0.name == restingExercise }?.rows.last { $0.isDone }
        guard let target else { return }
        provisionalEffort = provisionalEffort.filter { now.timeIntervalSince($0.value.at) < Self.provisionalLifetime }
        provisionalEffort[target.storeId] = ProvisionalEffort(rpe: pulse.rpe, band: pulse.band, at: now)
    }

    /// The provisional rating to draw for a row: fresh, and different from
    /// what the row already holds. A stale one clears itself here.
    func provisional(for row: SetRow, now: Date = Date()) -> ProvisionalEffort? {
        guard let p = provisionalEffort[row.storeId] else { return nil }
        guard now.timeIntervalSince(p.at) < Self.provisionalLifetime, p.rpe != row.rpe else { return nil }
        return p
    }

    /// Write a provisional rating — a tap on its capsule, or the next tick.
    /// A ticked set only; an unticked one keeps it provisional.
    func commitProvisional(_ row: SetRow, in exercise: ExerciseState) {
        guard let p = provisional(for: row), row.isDone else { return }
        row.rpe = p.rpe
        row.rpeStale = false
        provisionalEffort[row.storeId] = nil
        commitEdit(row, in: exercise)
    }

    #if DEBUG
    /// The `logger-effort` shot: a provisional rating on a row, as a Crown
    /// pulse would leave it — the preview deck has no session id to match.
    func seedProvisionalForPreview(_ row: SetRow, rpe: Double) {
        provisionalEffort[row.storeId] = ProvisionalEffort(rpe: rpe, band: EffortBand(rpe: rpe), at: Date())
    }
    #endif

    /// Every provisional rating on a ticked set, committed — the tick of the
    /// NEXT set is the moment the rest it was scrubbed during is over.
    private func commitProvisionals() {
        guard !provisionalEffort.isEmpty else { return }
        for exercise in exercises {
            for row in exercise.rows where provisionalEffort[row.storeId] != nil {
                commitProvisional(row, in: exercise)
            }
        }
        provisionalEffort = provisionalEffort.filter { Date().timeIntervalSince($0.value.at) < Self.provisionalLifetime }
    }

    /// Every record these rows hold, for the sheet the trophy opens.
    ///
    /// Keyed exactly as `refreshLivePrs` writes the ids — `<exercise key>|<set
    /// number>|<axis>` — because that is the only place the scheme is decided.
    /// A second spelling of it in a view is a sheet that is empty for a reason
    /// nobody can see.
    ///
    /// A PAIR asks for both sides: the two arms are two candidates with two set
    /// numbers, and "what did this set beat" is the union of what they beat.
    func records(for rows: [SetRow], in exercise: ExerciseState) -> [LivePrRecord] {
        let key = storedId(for: exercise)
        let prefixes = rows.compactMap { row -> String? in
            guard let index = exercise.rows.firstIndex(where: { $0.id == row.id }) else { return nil }
            return "\(key)|\(index + 1)|"
        }
        guard !prefixes.isEmpty else { return [] }
        return livePrs.filter { record in prefixes.contains { record.id.hasPrefix($0) } }
    }

    /// The Previous column for one WORKING set of a movement.
    ///
    /// ── THE ORDINAL IS AMONG WORKING SETS, NOT AMONG ROWS ───────────────────
    /// The seed's working rows are numbered 0…n by working ordinal, and the
    /// deck's rows are not: since the seed carries last session's warm-ups, a
    /// row index counts them too. Passing one for the other shifts every label
    /// by the warm-up count — a warm-up row claiming working set 1's history,
    /// and working set 1 showing set 3's.
    ///
    /// Past the prescription there is nothing to show: history does not contain
    /// a set number that has never been programmed.
    ///
    /// A movement the day's seed does not name at all — added mid-session —
    /// answers with its one narrow "last time" on every set (see `lastTimes`).
    private func seededPrevious(_ plan: ProgramExercise, workingIndex: Int) -> String? {
        guard let entry = seed.exercises
            .first(where: { ExerciseAliases.canonicalName($0.name) == ExerciseAliases.canonicalName(plan.name) })
        else { return lastTimes[canonicalKey(plan.name)]?.label }
        let working = entry.rows.filter { $0.kind == .normal }
        guard workingIndex >= 0, workingIndex < working.count else { return nil }
        return working[workingIndex].previous
    }

    // MARK: - Live records

    /// Re-detect every record claimed by the sets ticked so far.
    ///
    /// ── WHY THE WHOLE SESSION, ON EVERY TICK ────────────────────────────────
    /// A record is not a property of one set. Two sets at 62.5 × 12 are one
    /// record, and the SECOND does not claim it — `PrEngine.detectSessionPrs`
    /// decides that by walking the session in order and folding each winner
    /// into the index as it goes. Asking "does this row beat the bar" one row
    /// at a time cannot answer it, and would light both. A session is a few
    /// dozen sets; running the engine over all of them is cheaper than the
    /// haptic it triggers.
    ///
    /// The candidates are keyed exactly as `snapshot` writes them, so the live
    /// answer and the ledger written by `closeSession` are the same engine over
    /// the same keys against the same bar.
    private func refreshLivePrs() {
        var candidates: [PrCandidateSet] = []
        var origin: [SetRow] = []
        for exercise in exercises {
            let name = ExerciseAliases.canonicalName(exercise.name)
            // The same key `snapshot` writes and `buildLiveBaselines` built the
            // bar from — `baselineIds` calls this very function, so the two
            // cannot disagree by construction. They used to, and the header on
            // `baselines` describes what that cost.
            let key = storedId(for: exercise)
            // ── THERE IS NO REP FLOOR ON A CANDIDATE, AND THAT IS RIGHT ─────
            // A `floor` was computed here from `Ceilings.repWindow` and then
            // dropped on the ground — `PrCandidateSet` has no field to put it
            // in, so nothing downstream could ever have read it. Deleted rather
            // than plumbed through, because plumbing it is the bug it looks like
            // the fix for: `PrRecorder.baselines` and `PrRecorder.record` both
            // take `repWindow`'s `.cut` default, so gating the e1RM axis here by
            // THIS deck's phase would light a trophy the close path then refuses
            // to file. Leg Press is 8–12 on a bulk and 12–15 on a cut, and a
            // bulk set of 140 × 10 is exactly that disagreement. Matching
            // `record` means asking it nothing extra.
            for (i, row) in exercise.rows.enumerated() where row.isDone {
                candidates.append(PrCandidateSet(
                    key: key,
                    weightKg: row.weightKg ?? 0,
                    reps: Double(row.reps ?? 0),
                    setType: row.kind.rawValue,
                    timed: TimedExercise.isTimed(name),
                    // ── THE PAIR, WHICH THIS USED TO DROP ───────────────────
                    // Neither field was passed, so the live pass judged each
                    // side of a split set as a set of its own: two volume
                    // credits for one physical set, each at its own tonnage,
                    // where `PrRecorder.record` — once it is handed the domain
                    // spelling — collapses them to the weaker side and scores
                    // ONE. A trophy that lights on a set the close refuses to
                    // file is the exact failure `PrRecorder.baselines`'s header
                    // forbids, and it can only happen on a lift that has been
                    // split, which is why it went unnoticed.
                    pairId: row.pairId,
                    side: SyncTranslation.domainSide(row.side),
                    // The session's own day when there is one: a record is
                    // dated by the session it was earned in, and today's date
                    // on a three-week-old set would file it under the wrong day.
                    date: editing?.date ?? LogicalDay.today(),
                    exerciseName: name,
                    setNumber: i + 1
                ))
                origin.append(row)
            }
        }
        guard !candidates.isEmpty else {
            prsThisSession = 0
            livePrs = []
            return
        }
        // ── THE BAR, AFTER THE EARLY RETURN AND NOT BEFORE IT ───────────────
        // The keys above come from `storedId(for:)`, never from `baselines`, so
        // the ordering is free — and both reasons to take it are real. `init`
        // ends in `rebuildForPhase`, which now ends here, and at that moment
        // nothing is ticked: a rebuild above this guard paid for a full store
        // read (`PersonalRecordRow.fetchAll`, plus every set row for the deck's
        // ids) on the main actor for a pass that returns without ever reading
        // it — and then `attach` built the same bar again a moment later.
        //
        // Worse on the edit path: at `init` both `sessionId` and `editing` are
        // still nil, so that discarded bar was built with NO exclusion and NO
        // date bound — the edited session's own sets folded into the bar it is
        // judged against. Unreadable, because candidates were empty, and
        // overwritten by `attach(editing:)` — but a loaded gun inside the one
        // function whose invariant is that a rebuild can never do that.
        rebuildBaselinesIfDeckMoved()
        let result = PrEngine.detectSessionPrs(candidates, baselines)
        var records: [LivePrRecord] = []
        for (i, detected) in result.perSet.enumerated() where i < origin.count {
            origin[i].isRecord = !detected.axes.isEmpty
            // ONE ENTRY PER AXIS, not per set: a single set can take the weight
            // record and the e1RM record at once, and a card that collapsed
            // them would say "1 PR" where the ledger written at close says two.
            for axis in detected.axes {
                guard let mark = detected.records[axis] else { continue }
                records.append(LivePrRecord(
                    id: "\(candidates[i].key)|\(candidates[i].setNumber ?? i + 1)|\(axis.rawValue)",
                    exercise: candidates[i].exerciseName ?? candidates[i].key,
                    setLabel: "Set \(candidates[i].setNumber ?? i + 1)",
                    axis: axis,
                    mark: mark
                ))
            }
        }
        // Newest first — the deck is walked in session order.
        livePrs = records.reversed()
        prsThisSession = result.prCount
    }

    // MARK: - Rest

    func startRest(for exercise: ExerciseState) {
        guard let seconds = exercise.plan.restSec else { return }
        restDuration = TimeInterval(seconds)
        restEndsAt = Date().addingTimeInterval(restDuration)
        restingExercise = exercise.name
    }

    func adjustRest(by seconds: TimeInterval) {
        guard let end = restEndsAt else { return }
        let next = end.addingTimeInterval(seconds)
        // Pulling the timer below now ENDS it rather than showing a negative
        // countdown that keeps counting.
        restEndsAt = next > Date() ? next : nil
        restDuration = max(0, restDuration + seconds)
        if restEndsAt == nil { restingExercise = nil }
    }

    func stopRest() {
        restEndsAt = nil
        restingExercise = nil
    }

    // MARK: - The session clock

    /// Stop the clock.
    ///
    /// ── WHY THIS APPENDS AN EVENT RATHER THAN SETTING A FLAG ────────────────
    /// A pause has to survive the app being killed mid-workout — iOS jetsams a
    /// backgrounded app without warning, and a flag in memory is gone with it
    /// while the wall clock keeps running. It also has to merge with the
    /// watch's, which is the whole argument `SetEvent` makes for the set log.
    /// So it is the same log, with its own two kinds, and `pausedSeconds` folds
    /// them. Nothing leaves the device: what the server gets is `duration_min`.
    ///
    /// `startedAt` is never rewritten. The session still began when it began;
    /// what changes is how much of the clock since then counts. Rebasing the
    /// start would be the shorter patch and it would lie to `Era.forDate`, to
    /// the PR date and to every reader of "when did you train".
    /// ── THE LOG IS WRITTEN FIRST, AND THE STATE FOLLOWS IT ─────────────────
    /// Both of these used to flip the flag and then try to write, which is two
    /// failures in one shape. `record` claims the pencil and REFUSES when the
    /// watch holds it (`EventStore.claimPencil`), so a refused pause left the
    /// screen stopped and the log running — and a refused RESUME left an open
    /// pause in the log forever, so the session came back paused and
    /// `closeSession` subtracted the whole interval. The visible state is now
    /// whatever the log accepted.
    ///
    /// And it needs a SESSION. `attach` only looks one up, and until App Store
    /// W4 the row was created by the first append — so pausing during your
    /// warm-up wrote no event at all and the minutes went straight back into
    /// `duration_min`. `begin` opens the row at Start now; `ensureSession`
    /// here is the fallback for a deck whose `begin` could not.
    func pause() { pause(at: Date()) }

    func pause(at now: Date) {
        guard pausedAt == nil else { return }
        guard let store else { pausedAt = now; return }
        do {
            guard let sessionId = try ensureSession() else { return }
            try store.pauseSession(sessionId)
            pausedAt = now
            storeError = nil
        } catch {
            storeError = String(describing: error)
        }
    }

    func resume() { resume(at: Date()) }

    func resume(at now: Date) {
        guard let since = pausedAt else { return }
        func bank() {
            // Banked from the local stamp rather than re-read: the store's own
            // answer is the same arithmetic over the two events this pair just
            // wrote, and a read per tap is a read for nothing.
            pausedTotal += max(0, now.timeIntervalSince(since))
            pausedAt = nil
        }
        guard let store, let sessionId else { bank(); return }
        do {
            try store.resumeSession(sessionId)
            bank()
            storeError = nil
        } catch {
            storeError = String(describing: error)
        }
    }

    /// Correct the start instant. `PauseControlling`.
    ///
    /// Clamped exactly as `LoggerClock` clamps it — a start that would put the
    /// clock in the future reads as "just started" rather than counting down —
    /// and against `pausedAt ?? now`, the same instant `elapsed` anchors on, so
    /// correcting the start DURING a pause cannot produce a negative elapsed
    /// that `max(0, …)` then renders as a confident 0:00.
    ///
    /// It reaches the store, which is the difference between this and the stub:
    /// `closeSession` derives `duration_min` from `started_at`, so a correction
    /// that lived only in memory would leave the timer saying 62 minutes and
    /// the stored session 82.
    func setStart(_ date: Date) {
        startedAt = min(date, (pausedAt ?? Date()).addingTimeInterval(-pausedTotal))
        persistStart()
    }

    /// Move `startedAt` so that `elapsed` reads `seconds`. The pause ledger is
    /// deliberately untouched — banking the difference there would make "edit
    /// elapsed" also edit how long you had rested, and `duration_min` would
    /// come out right for a reason nobody could find.
    func setElapsed(_ seconds: TimeInterval) {
        let anchor = pausedAt ?? Date()
        startedAt = anchor.addingTimeInterval(-(max(0, seconds) + pausedTotal))
        persistStart()
    }

    private func persistStart() {
        // The durable fallback first, and unconditionally: it is the only copy
        // that exists before the first append creates a row, which is exactly
        // the window a correction made during the warm-up lives in.
        if !isEditing { LiveSessionStart.write(startedAt, dayKey: day.key, date: LogicalDay.today()) }
        guard let store, let sessionId else { return }
        do {
            try store.setSessionStart(id: sessionId, startedAt: startedAt, userId: userId)
            storeError = nil
        } catch {
            storeError = String(describing: error)
        }
    }

    // MARK: - Finishing

    /// Stamp the session finished.
    ///
    /// Returns `false` when there was nothing to finish — no store, or not a
    /// single set logged. The caller uses that to avoid claiming a workout
    /// happened because a screen was opened.
    @discardableResult
    func finish(sessionRpe: Double? = nil) -> Bool {
        let span = Perf.begin("session.finish")
        defer { Perf.end(span) }
        // The last set's Crown rating has no next tick to commit it: Finish is
        // that tick (overhaul A3, after review).
        commitProvisionals()
        guard let store, let sessionId, completedSets > 0 else {
            // Not an error when there is no store (previews) — but a session
            // with nothing in it, or one whose row was never created, must not
            // be reported as finished. The caller keeps the sheet up and this
            // is what it shows.
            if store != nil, completedSets == 0 {
                storeError = "Nothing logged yet — tick a working set before finishing."
            }
            return false
        }
        do {
            // The rest the LAST movement worked prescribes — the long-idle
            // guard's credit for the gap between the last set and the button.
            let restTarget = exercises
                .last { $0.rows.contains(where: \.isDone) }?
                .plan.restSec
                .map(Double.init)
            try store.closeSession(id: sessionId, sessionRpe: sessionRpe, restTargetSec: restTarget)
            // The deck's treadmill becomes next session's opener only once it
            // is in `cardio_logs` (Precision A2). `try?`: the workout is
            // closed and safe either way, and a bout that failed to file is a
            // warm-up card one session stale, not a lost set.
            _ = try? store.recordSessionCardio(sessionId: sessionId, userId: userId)
            // The workout is history; the durable start belongs to nothing now.
            // Left standing it would be adopted by the NEXT deck opened on this
            // split today — a two-a-day starting its evening session on the
            // morning one's clock.
            LiveSessionStart.clear(dayKey: day.key, date: LogicalDay.today())
            storeError = nil
            return true
        } catch {
            storeError = String(describing: error)
            return false
        }
    }

    /// Finish an EDIT: write the four figures the athlete knows and report the
    /// date the cascade has to start from (§U4.5).
    ///
    /// ── WHY IT DOES NOT RESCORE ─────────────────────────────────────────────
    /// Nothing does, by name, since W2: `updateMetrics` commits the session
    /// row and the rescore door reports its date. Every set edit already
    /// rewrote this session's aggregates and replayed its ledger inside its
    /// own transaction, and each of those commits was reported the same way.
    @discardableResult
    func finishEdit(sessionRpe: Double? = nil) -> String? {
        guard let store, let sessionId, let editing else { return nil }
        do {
            try store.updateMetrics(sessionId: sessionId, userId: userId, sessionRpe: sessionRpe)
            // ── SAVING IS WHAT MAKES THE EDIT UNREVERTABLE ──────────────────
            // The watermark is the one thing that makes `cancelEdit` possible,
            // so Save is where it stops being true: these changes are now the
            // session, and a mark left behind would let a LATER editor revert
            // them as if they had been made in that sitting. Failing to clear it
            // must not fail the save — the edits themselves already landed, one
            // transaction each, as they were made.
            try? store.clearEditMark(sessionId: sessionId)
            editWatermarked = false
            storeError = nil
            return editing.date
        } catch {
            storeError = String(describing: error)
            return nil
        }
    }

    /// Put the session back the way the editor found it (§W2).
    ///
    /// ── WHY THIS CAN EXIST NOW, WHEN IT COULD NOT BEFORE ────────────────────
    /// `LiveLoggerView`'s own comment used to explain the refusal: every set
    /// edit commits to `set_events`, the projection and the outbox as it is
    /// made, so by the time a Cancel button could be pressed there was nothing
    /// left to not-do. That is still true. What changed is that the log is now
    /// WATERMARKED — `attach(editing:)` records where this device's log stood
    /// when the editor opened — so "the way the editor found it" is a state the
    /// store can still name, and `revertSessionEdits` writes the events that
    /// get back to it. Nothing is deleted; the undo is itself history.
    ///
    /// Returns false when the store refused, with the reason in `storeError`,
    /// which the header banner is already rendering. The caller keeps the screen
    /// up in that case — dismissing onto a half-done revert is the failure
    /// `cancel()` and `finish` both avoid.
    ///
    /// The revert commits through `SessionEditing`, and the rescore door
    /// reports the session's date on that commit (W2).
    @discardableResult
    func cancelEdit() -> Bool {
        guard let store, let sessionId, isEditing, editWatermarked else { return false }
        do {
            // ── NIL IS "NOTHING TO UNDO", AND THE SCREEN STILL CLOSES (C2) ──
            // `revertSessionEdits` answers nil for a sitting that changed
            // nothing, and its contract says so in as many words: "Nil is not
            // a failure, and the caller should still close the screen on it".
            // This returned false there, so Discard on an untouched editor did
            // nothing at all — no banner, no dismissal, the mark still up. The
            // store has already cleared the mark on that path.
            guard try store.revertSessionEdits(sessionId: sessionId, userId: userId) != nil else {
                editWatermarked = false
                dropCardsAddedWhileEditing()
                storeError = nil
                return true
            }
            // The mark is NOT cleared here. `revertSessionEdits` re-writes it at
            // the clock as it now stands, deliberately — see its own note —
            // because this screen stays open and whatever is edited next has to
            // be cancellable too. Clearing it deleted that one line later and
            // left the second sitting silently un-revertable.
            //
            // ── THE DECK IS BLANKED BEFORE IT IS REBUILT ────────────────────
            // `restoreLoggedSets` folds the projection ONTO the deck and skips a
            // card the session holds nothing of (`guard !mine.isEmpty`). Right
            // for an attach, wrong here: a movement ADDED during the sitting
            // owns no rows once the revert has voided them, so its card would
            // keep ticked rows describing sets that no longer exist — and a tick
            // on one would append behind a terminal tombstone and be dropped in
            // silence (`SetEventFold` rule 3). Setting the flags writes no
            // events; only `toggleDone` appends.
            for exercise in exercises {
                for row in exercise.rows where row.isDone {
                    row.isDone = false
                    row.isRecord = false
                }
            }
            // Rebuilt from the projection the revert just wrote, not from what
            // was on screen. Reversing the rows in place would be a second
            // implementation of the fold — the failure `reproject`'s own header
            // argues against — and it would be wrong the moment a compensating
            // event did anything the deck could not predict.
            try restoreLoggedSets()
            dropCardsAddedWhileEditing()
            refreshLivePrs()
            storeError = nil
            return true
        } catch {
            storeError = String(describing: error)
            return false
        }
    }

    /// Throw the session away — this workout did not happen.
    ///
    /// Since App Store W4 Start opens the row (`begin`), so even a deck
    /// cancelled before its first set has one — with no events and nothing
    /// pushed, so the discard is cheap. `sessionId == nil` is left only for a
    /// deck whose `begin` failed, and cancelling out of it is just leaving.
    ///
    /// Either way the session is discarded rather than closed — see `AppDatabase.discardSession` for why
    /// an empty-but-finished session row is the worse outcome.
    @discardableResult
    func cancel() -> Bool {
        guard let store, let sessionId else {
            following = nil
            return true
        }
        do {
            try store.discardSession(id: sessionId, userId: userId)
            self.sessionId = nil
            // The tab keeps this model for the next Start, and a deck still
            // marked as following would never `begin` a row of its own.
            following = nil
            // The deck goes back to its prescription. Leaving the ticks on
            // screen after the events behind them are gone is the projection
            // and the log disagreeing, which is the one thing this layer exists
            // to prevent.
            for exercise in exercises {
                for row in exercise.rows {
                    row.isDone = false
                    row.isRecord = false
                }
            }
            // `recordCount` is `prsThisSession` now, not a scan of the rows, so
            // clearing the badges is not enough — the header and the Lock
            // Screen would keep reporting records on an empty deck.
            prsThisSession = 0
            livePrs = []
            // The clock too: a discarded session's pause belongs to nothing.
            pausedAt = nil
            pausedTotal = 0
            LiveSessionStart.clear(dayKey: day.key, date: LogicalDay.today())
            storeError = nil
            return true
        } catch {
            storeError = String(describing: error)
            return false
        }
    }

    // MARK: - Session metadata

    /// What the store holds about this session, re-read rather than cached.
    ///
    /// Average heart rate and active energy are filled by `syncSessionMetrics`
    /// from the watch's own `HKWorkout` — which can arrive a day late — so the
    /// honest thing for the finish sheet to show is whatever is on disk at the
    /// moment it is drawn, and "—" when nothing is yet.
    var sessionRow: WorkoutSession? {
        guard let store, let sessionId else { return nil }
        return try? store.session(id: sessionId, userId: userId)
    }

    /// The three figures you can supply when the watch did not.
    ///
    /// Stamped MEASURED rather than estimated, so the next Health sync does not
    /// replace what you typed with what the phone inferred. A typed DURATION
    /// goes further and sets `duration_edited`, which forbids `closeSession`
    /// from re-deriving it from the clock — see `AppDatabase.updateMetrics`.
    func setMetrics(
        durationMin: Double? = nil, avgBpm: Int? = nil, calories: Int? = nil, measured: Bool = true
    ) {
        guard let store, let sessionId else { return }
        do {
            try store.setSessionMetrics(
                id: sessionId, userId: userId, durationMin: durationMin, avgBpm: avgBpm, caloriesBurned: calories,
                measured: measured
            )
            storeError = nil
        } catch {
            storeError = String(describing: error)
        }
    }

    /// What the last session of this split came to — the finish sheet's default
    /// for the two figures the watch has usually not delivered yet.
    ///
    /// Empty in a preview and on a cold store, which is the correct answer:
    /// nothing is a better default than a made-up one, and "—" is what the tile
    /// already draws.
    func previousMetrics() -> (durationMin: Double?, avgBpm: Int?, calories: Int?) {
        guard let store else { return (nil, nil, nil) }
        return (try? store.previousSessionMetrics(
            userId: userId, dayKey: day.key, before: LogicalDay.today()
        )) ?? (nil, nil, nil)
    }

    #if DEBUG
    /// Harness only: put the queue's verdicts on the deck without a store.
    ///
    /// The alerts are a STORE read (`AppDatabase.sessionSeed`) and the shot
    /// fixtures that carry one seed a single previous session — which is a
    /// chain of one, and a chain of one has no verdict. Seeding them directly
    /// is what makes the `1 more @ 12` chip photographable at all; the
    /// alternative is a fixture that has to satisfy the whole progression
    /// engine, plan resolution and era included, to draw one capsule.
    ///
    /// Same shape and same reason as `WatchModel.seedDebugRest`.
    func seedDebugProgression(_ alerts: [ProgressionQueue.Alert]) {
        progressionAlerts = alerts
    }
    #endif

    /// The last few sessions of this split by tonnage, oldest first, with THIS
    /// session's tonnage appended (W10).
    ///
    /// ── WHY THIS SESSION IS ON THE END AND NOT LEFT OFF ─────────────────────
    /// The sheet's Tonnage tile prints today's figure two points above the
    /// trail, and a trail that stopped at last week would be the one line on
    /// the sheet not about the session being finished. `splitTonnage` excludes
    /// it by construction (`date < today` and `ended_at != nil`), which is
    /// exactly right for the BAR and wrong for the picture — so the bar is read
    /// from the store and the point is appended here, from the same
    /// `totalVolumeKg` the tile draws. The two cannot disagree.
    ///
    /// Empty when there is nothing to plot: `Sparkline` refuses fewer than two
    /// points and the sheet draws nothing at all rather than a flat line, which
    /// is the same call `WeekSections` makes.
    func tonnageTrail() -> [Double] {
        guard let store else { return [] }
        let previous = (try? store.splitTonnage(
            userId: userId, dayKey: day.key, before: editing?.date ?? LogicalDay.today()
        )) ?? []
        guard !previous.isEmpty, totalVolumeKg > 0 else { return [] }
        return previous + [totalVolumeKg]
    }

    /// Every performed set's effort, in the order the session performed them —
    /// what `IntensityBar` draws (W10).
    ///
    /// ── THE SAME SHAPE THE SESSION PAGE BUILDS, FROM THE DECK ───────────────
    /// `SessionAnalysis.report` derives `Report.intensity` by walking the
    /// ledger's rows and taking the MAX rpe across a row's sides. This is the
    /// same walk over the deck, and the max is the same rule: a unilateral pair
    /// is one set and the harder arm is what it cost. Ghosts never happened;
    /// warm-ups did, and a ramp-up set rated 5 is part of the shape of how the
    /// session got hard.
    ///
    /// `nil` for an unrated set and NOT a zero — the bar paints those grey, and
    /// its own guard refuses to draw at all when fewer than two sets carry a
    /// rating.
    func intensityTrace() -> [Double?] {
        exercises.flatMap { exercise in
            exercise.rows
                .filter { $0.isDone && $0.kind != .ghost }
                .map(\.rpe)
        }
    }

    /// The word the finish sheet opens on, or nil when nothing was rated.
    ///
    /// ── WHY IT IS COMPUTED HERE AND NOT IN THE SHEET ────────────────────────
    /// It needs two things the sheet cannot reach: the deck's own per-set
    /// ratings, and what this DAY TYPE has cost recently. The suggestion is
    /// relative — see `Effort.suggestEffortWord` — so without the second the
    /// answer is graded against a cold constant and every ordinary session
    /// reads as easy.
    ///
    /// Warm-ups and ghosts are excluded by `deriveSessionRpe` itself
    /// (`SetTags.isWorkingSet`), so the rows go in whole.
    func suggestedEffort() -> EffortWord? {
        let rated = exercises.flatMap { exercise in
            exercise.rows.filter(\.isDone).map {
                RatedSet(
                    weightKg: $0.weightKg ?? 0, reps: Double($0.reps ?? 0),
                    rpe: $0.rpe, setType: $0.kind.rawValue
                )
            }
        }
        guard let mean = RpeMemory.deriveSessionRpe(rated) else { return nil }
        let history = (try? store?.effortHistory(
            userId: userId, dayKey: day.key, before: LogicalDay.today()
        )) ?? []
        return Effort.suggestEffortWord(mean: mean, history: history)
    }

    // MARK: - The store

    /// Make sure a session row exists, and remember its id.
    ///
    /// `set_events.session_id` has a foreign key to `workout_sessions`, so the
    /// row has to exist before the first append — and it is looked up by day
    /// key rather than created blindly, so relaunching mid-workout rejoins the
    /// session instead of starting a second one beside it.
    /// The bar the deck's ticked sets are measured against, built from every id
    /// this movement's history can be filed under.
    ///
    /// Extracted because the live path and the edit path must build it the SAME
    /// way: two copies of this union is how they came to disagree about whether
    /// a set was a record (see the note in `attach`).
    ///
    /// `before` is the edit path's date bound and nothing else: a live session
    /// has nothing after it to exclude.
    /// The deck's identities, as the bar and the candidates both have to see
    /// them: exactly one id per card, which is the id `storedId` answers with
    /// and therefore the id `refreshLivePrs` will key a candidate on.
    ///
    /// ── ONE ID PER CARD, NOT EVERY ID THE MOVEMENT HAS ──────────────────────
    /// This used to hand over the union of `storedId`, a slug of the name and
    /// whatever `restoreLoggedSets` had learned. That reads as "widen the bar",
    /// and it is not what happens: `PrRecorder.baselines` re-keys every row it
    /// gathers to `keyByName[name(id)]`, and `keyByName` is built by uniquing
    /// on FIRST over the `Set` it is handed. Two ids for one canonical name
    /// therefore put the bar under whichever of them the hash visited first,
    /// with no way for a caller to say which it wanted.
    ///
    /// Passing one is not a narrowing. `baselines` gathers the movement's OTHER
    /// ids itself — `siblings`, every `exercise_id` in `workout_sets` that
    /// resolves to the same canonical name — and re-keys them onto the id given
    /// here. So the history is as wide as it ever was, and the key it lands
    /// under is now chosen rather than drawn.
    private func baselineIds() -> Set<String> {
        Set(exercises.map { storedId(for: $0) })
    }

    /// Rebuild the bar from the deck's identities as they stand NOW.
    ///
    /// `excluding` and `before` are read off the model rather than passed: they
    /// were the same two expressions at both original call sites, and a rebuild
    /// that reached for a stale `session.id` would fold this session's own sets
    /// into the bar it is judged against. `sessionId` is nil on a fresh deck and
    /// becomes the session at the first append, which is the correct bound at
    /// every instant; `editing?.date` is nil on a live deck, which is exactly
    /// the unbounded behaviour the live path wants.
    private func buildLiveBaselines(store: AppDatabase) throws {
        let ids = baselineIds()
        baselines = try store.livePrBaselines(
            userId: userId,
            exerciseIds: Array(ids),
            excluding: sessionId,
            before: editing?.date,
            dayKey: day.key,
            program: Program(id: "", label: "", days: [day])
        )
        baselineKeys = ids
    }

    /// Rebuild the bar if the deck's identities moved since it was built.
    ///
    /// ── THE ONE GUARD, IN THE ONE PLACE EVERY TICK PASSES THROUGH ───────────
    /// `refreshLivePrs` has eight callers. A guard in each would be eight
    /// chances to add a ninth and forget — and the fault this exists for is
    /// silent, so a missed caller costs a trophy nobody can prove was owed.
    /// The set comparison is a handful of strings; the store read happens only
    /// on the tick where an identity actually changed, which is once per
    /// movement per session.
    ///
    /// A failed rebuild is said out loud rather than swallowed: the bar it
    /// leaves standing is the one from before, which is a bar the candidates may
    /// no longer be keyed on, and the visible result is a Records tile reading
    /// "—" for a reason nothing else would name.
    private func rebuildBaselinesIfDeckMoved() {
        guard let store, baselineIds() != baselineKeys else { return }
        do { try buildLiveBaselines(store: store) }
        catch { storeError = String(describing: error) }
    }

    func attach() {
        guard let store, sessionId == nil else { return }
        do {
            // LOOK UP ONLY. This runs for every presentation of the cover —
            // a resume, a return from the Mini Player — and creating here
            // would mint rows for appearances. The row is created by the
            // deliberate Start instead (`begin`, App Store W4), with
            // `ensureSession` as the fallback at the first append.
            // ── `sessionId` IS ASSIGNED LAST, AND THAT IS THE POINT ─────────
            // `attach`'s own guard is `sessionId == nil`, so a read that threw
            // AFTER the id was assigned left the model owning a session with an
            // empty deck and no second chance to restore it — and re-ticking
            // set 1 would then append a FRESH set id at an index the log
            // already holds, which is a duplicated set in the projection and in
            // the upload. Everything is read into locals first.
            let today = LogicalDay.today()
            let session = try store.liveSession(dayKey: day.key, date: today, userId: userId)
            let live = session?.id
            // Rejoining a session that was paused when the app was killed: the
            // log knows, and the wall clock has kept running. SPLIT rather than
            // summed — see `SessionRun` for what an open pause is worth.
            let ledger = try live.map { try store.pauseLedger(sessionId: $0) }

            sessionId = live
            // ── THE CLOCK SURVIVES THE KILL, LIKE THE PAUSE LEDGER BELOW ────
            // `init` defaults `startedAt` to NOW, which is the right answer for
            // a deck being opened and the wrong one for a deck being REJOINED.
            // iOS suspending and then terminating a session mid-workout built a
            // fresh model on relaunch, and this method restored the session id,
            // the pause ledger and every logged set — but left the clock at the
            // instant of resumption. The deck came back correct and claimed the
            // workout had just started.
            //
            // `started_at` was never the missing fact: `ensureSession` writes
            // the model's own `startedAt` into the row at the first append, and
            // `setStart`/`setElapsed` push corrections through
            // `setSessionStart`, so the stored instant is already the corrected
            // one. `liveSession` returns the whole row and this read was
            // throwing away everything but the id.
            //
            // Suspended time is deliberately NOT pause time: a workout the
            // phone slept through still happened, and `elapsed` is
            // `(pausedAt ?? now) − (startedAt + pausedTotal)`. Only an explicit
            // pause is banked, which is the same arithmetic the watch and
            // `SessionElapsed.activeSec` use.
            //
            // The fallback ladder matches `attach(editing:)`'s exactly. Last
            // rung is the value `init` already set rather than a new `Date()`:
            // a session row with a null `started_at` is a row this deck opened
            // moments ago, and the deck's own instant is the older, honester of
            // the two.
            if let session {
                startedAt = session.startedAt ?? LogicalDay.date(fromISO: session.date) ?? startedAt
            } else if !startedAtWasGiven,
                      let pending = LiveSessionStart.read(dayKey: day.key, date: today) {
                // ── THE WINDOW BEFORE THE FIRST SET ─────────────────────────
                // `started_at` reached disk only at `openSession`, which until
                // App Store W4 ran on the FIRST APPEND (`begin` runs it at
                // Start now, so this rung is a fallback). So a deck opened
                // at 18:00 and terminated at 18:11 with the warm-up done and
                // nothing ticked had NO row to restore from, and the relaunch
                // minted a model that believed the workout began at 18:20.
                // Eleven minutes, gone, with no record they ever existed —
                // which is the half of "the timer must survive any termination"
                // that restoring the row could never reach.
                //
                // So the instant is durable from the moment the deck opens, in
                // the one store that costs nothing and needs no session row.
                // The session row still WINS where there is one: it carries the
                // corrections `setStart`/`setElapsed` pushed and it is what
                // uploads.
                startedAt = pending
            }
            // Written on every attach, not only when it was read: a correction
            // made in the timer sheet has to reach the fallback too, or a
            // termination after it would restore the number that was corrected.
            LiveSessionStart.write(startedAt, dayKey: day.key, date: today)

            if let ledger {
                // ── THE LEDGER IS RESOLVED AGAINST THE WALL CLOCK ───────────
                // It used to be imported whole: `pausedTotal = <the store's
                // total>`, which for an OPEN pause is `now − pauseOpenedAt`
                // with nothing bounding it. Terminate a paused session at 18:40
                // and reopen it at 07:00 and the ledger claimed thirteen hours
                // of rest on a ninety-minute workout — `timerOrigin` landed in
                // the future and `elapsed`'s `max(0, …)` printed `0:00` on a
                // session whose sets had all restored correctly. That is the
                // "timer reset to 0:00 again" report, and restoring
                // `started_at` harder could never have fixed it.
                //
                // `SessionRun` bounds both halves and says when it had to.
                let run = SessionRun.resolve(
                    startedAt: startedAt,
                    banked: ledger.banked,
                    pauseOpenedAt: ledger.openedAt,
                    now: Date()
                )
                pausedAt = run.pausedAt
                pausedTotal = run.pausedTotal
                // Said out loud, in the channel the header already draws. A
                // clock that had to be repaired is the only evidence anybody
                // gets that the log went inconsistent, and swallowing it is
                // what made the last two of these invisible for a week.
                if run.abandonedPause {
                    storeError = "The clock was left paused. Resumed — \(Int(SessionRun.openPauseCeilingSec / 60)) min credited as rest."
                } else if run.clamped {
                    storeError = "The pause ledger outran the session clock and was trimmed to fit."
                }
            }
            try restoreLoggedSets()
            // ── THE BAR IS BUILT AFTER THE RESTORE, LIKE THE EDIT PATH'S ────
            // It used to be built before anything was assigned, from the deck's
            // ids alone — `storedId` plus a slug of the name. That is every id
            // the PLAN knows, and it is not every id the movement's history is
            // filed under: `storedExerciseId` is learned by `restoreLoggedSets`
            // from the rows already in the session, and a movement whose
            // catalogue row this deck could not resolve fell back to a slug
            // that matches nothing in `workout_sets`. The bar then came back
            // empty, and `PrEngine` awards no axis against an empty index — so
            // the deck showed no trophy on a set whose own session page, one
            // screen later, showed two. `attach(editing:)` hit this in U4 and
            // fixed it by restoring first; the LIVE path never got the same
            // treatment.
            //
            // ── IT IS THE ORDER THAT MATTERS, NOT A UNION (W2) ──────────────
            // This used to end "and taking the union … widening an id set can
            // only raise a bar or fill an empty one". Do NOT restore that.
            // `baselineIds` hands over exactly ONE id per card, and its header
            // sets out why widening is the bug rather than the fix:
            // `PrRecorder.baselines` re-keys on `keyByName`, which uniques on
            // FIRST over a `Set`, so two ids for one movement put the bar under
            // whichever the hash happened to visit. The history is as wide as it
            // ever was — `baselines` gathers the movement's other ids by
            // canonical name itself. What this ordering buys is that
            // `storedExerciseId` is known before the id is resolved.
            //
            // In its own `do`, for the reason the ordering above exists: a bar
            // that cannot be built costs the record badges and nothing else,
            // and must not unwind a deck that is already restored and usable.
            // The edit path has said the same since U4.
            do {
                try buildLiveBaselines(store: store)
                refreshLivePrs()
            } catch {
                storeError = String(describing: error)
            }
        } catch {
            // A store failure must not take the screen down with it: the deck
            // is still correct and still usable, and the events it could not
            // write are the ones the outbox exists to retry. Surfacing it as a
            // crash would lose the workout to protect the database.
            storeError = String(describing: error)
        }
    }

    /// Re-open a FINISHED session on the deck (§U4.5).
    ///
    /// The live `attach` looks for `ended_at IS NULL` on TODAY's day key, which
    /// is exactly the predicate a past session fails. This one is handed the
    /// row, so it needs no lookup — and it refuses a live one, because a deck
    /// bound to a running session through the editing API would race the one
    /// the Workout tab is holding.
    ///
    /// No pause state is restored: a session that ended is not paused, and the
    /// pause ledger it carries is already inside its stored `duration_min`.
    func attach(editing session: WorkoutSession) {
        guard let store, sessionId == nil, session.endedAt != nil else { return }
        do {
            sessionId = session.id
            editing = EditContext(
                date: session.date,
                startedAt: session.startedAt,
                durationMin: session.durationMin
            )
            startedAt = session.startedAt ?? LogicalDay.date(fromISO: session.date) ?? Date()
            // ── RESTORE FIRST, THEN THE BAR ─────────────────────────────────
            // The live `attach` builds the baselines before it assigns
            // anything, and is right to: it knows the deck's ids up front
            // because a live session's rows are this device's. A re-opened one
            // may carry the WEB's catalogue uuids, and `livePrBaselines`
            // filters `workout_sets` by `exercise_id` — so the deck's slugs
            // matched nothing, every baseline came back empty, and
            // `PrEngine.detectSessionPrs` awards no axis against an empty index
            // ("a delta against nothing is not a delta"). The visible symptom
            // was an edit deck showing ONE trophy on a session whose own
            // summary page showed three records.
            //
            // `restoreLoggedSets` is what learns those ids, so it runs first
            // and `baselineIds` then resolves each card to the id its rows
            // actually carry — NOT to a union of that id and the deck's slug;
            // see `baselineIds` and the note in `attach()` for why two ids for
            // one movement is how the bar landed under a hash-chosen key.
            // A throw here leaves a restored, usable deck with
            // no live records rather than no deck at all.
            try restoreLoggedSets()
            // ── WHERE THE LOG STOOD WHEN THIS SCREEN OPENED ─────────────────
            // The mark `cancelEdit` reverts to. Stamped here, and PERSISTED by
            // the store rather than held on the model, because the deck can die
            // between opening and cancelling — iOS terminating a suspended app
            // mid-edit is the ordinary case, not the exotic one — and a
            // watermark that lives in memory is one that is gone exactly when
            // the athlete comes back wanting their session returned.
            //
            // Its own `try`, inside the restore's `do`: a session that cannot be
            // marked must not open an editor whose Cancel button would silently
            // do nothing.
            editWatermarked = (try? store.markEditStart(sessionId: session.id)) != nil
            // There used to be a `removeAll` here, deleting the treadmill card
            // again when nothing on it was ticked. It was undoing a decision
            // taken one method earlier: `rebuildForPhase` prepended the bout at
            // `init`, before anything knew this deck was a re-opened session.
            //
            // `openingForEdit` moves that decision to where it is actually
            // known, so the card is never minted and there is nothing to delete
            // — and the delete-after's own failure mode goes with it. It ran
            // BEFORE `restoreLoggedSets` had folded the projection onto the
            // deck on the path that builds `editorDay` from a session with no
            // program entry for the bout, so a treadmill that WAS walked looked
            // untouched and was removed with the phantom.
        } catch {
            // ── THE ONE THROW THAT MUST UNWIND ──────────────────────────────
            // `openEditor`'s guard is `sessionId != nil`, so a failed restore
            // with the id already assigned opens the editor on a REAL finished
            // session with every row blank. The first tick then appends beside
            // the rows `seedEventLog` is about to seed from `workout_sets` —
            // the whole workout, twice, with the aggregates to match. A deck
            // that refuses to open is the only safe answer.
            sessionId = nil
            editing = nil
            storeError = String(describing: error)
            return
        }
        do {
            // ── THE BAR IS WHAT CAME BEFORE THIS SESSION ────────────────────
            // `baselines` has no date bound of its own: `save.ts` never needed
            // one because it builds the bar at close, when there IS nothing
            // after. Editing a three-week-old session is the first caller for
            // which "every other session" and "every EARLIER session" are
            // different sets — without this the deck measures an August set
            // against a September one and shows no records at all on a session
            // whose own summary page, one screen back, shows three.
            try buildLiveBaselines(store: store)
            refreshLivePrs()
            storeError = nil
        } catch {
            // A bar that could not be built costs the live record badges and
            // nothing else. The deck is restored and usable.
            storeError = String(describing: error)
        }
    }

    /// Non-fatal store trouble, shown in the header rather than thrown.
    private(set) var storeError: String?

    /// Fold what is already logged back onto the deck.
    ///
    /// Matching is by `(exercise_id, set_index)`. Sets past the prescription
    /// become extra rows, which is exactly what they are.
    private func restoreLoggedSets() throws {
        guard let store, let sessionId else { return }
        let logged = try store.sets(sessionId: sessionId, userId: userId)
        guard !logged.isEmpty else { return }

        // ── MATCHED BY NAME, NOT BY ID ──────────────────────────────────────
        // A session re-opened here can hold rows from any client and any era:
        // a catalogue uuid, or the legacy slug a pre-W6 build of this app wrote.
        // Matching on the id alone would find nothing in half of them, and the
        // failure is silent — the deck comes up blank and looks like a session
        // with nothing in it.
        //
        // `PrRecorder.nameResolver`'s rule, over rows the caller already holds:
        // the local catalogue, then `ExerciseSlug.nameBySlug`, then the alias
        // table. The same two sources the PR ledger keys on, so a set restores
        // onto the movement it files its records under.
        let rows = (try? store.exercises()) ?? []
        let catalogue = Dictionary(rows.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        // The slug half is the catalogue's `slug` column since W2 (D3), with
        // the computed tier under it since W6 — see `ExerciseSlug.nameBySlug`.
        let bySlug = ExerciseSlug.nameBySlug(rows)
        func canonical(_ id: String) -> String {
            ExerciseAliases.canonicalName(catalogue[id] ?? bySlug[id] ?? id)
        }
        // ── AND THE REVERSE, FOR A MOVEMENT THIS SESSION DOES NOT HOLD ──────
        // `storedId` resolves a movement with no rows of its own through this
        // index, so a forgotten set added to an old session joins the catalogue
        // row the rest of its history is already filed under instead of opening
        // a second identity beside it.
        refreshCatalogueIndex()

        // ── THE MATCHING AND THE ARITHMETIC ARE `DeckRestore.fold` NOW ──────
        // What is left here is building `SetRow`s, which is the only part that
        // needs the model. The fold decides two things this method got wrong
        // twice, and its header says why at length:
        //
        //   · WHICH card owns which rows. It PARTITIONS — the first card
        //     answering to a name consumes the bucket — where this used to
        //     `filter` the whole log per card and consume nothing, so two cards
        //     for one movement each got every row. That is the treadmill drawn
        //     twice, ticked twice, and two writers on one set id.
        //   · HOW MANY blanks to seed after them, counted in SETS. This used to
        //     subtract ROWS (`exercise.rows.count - rows.count`) and spend the
        //     answer on `seedRows(count:)`, whose parameter is working SETS and
        //     which PRE-SPLITS a unilateral movement. On a Single Arm Lateral
        //     Raise that squared the shortfall: four prescribed with two logged
        //     reopened with SIX, and sets 5 and 6 were tickable rows the
        //     program never asked for.
        //
        // Lowercased on BOTH sides. `SessionDetailView.editorDay` compares
        // case-insensitively when it decides whether the program already names
        // a movement; a case-sensitive match here would reuse the program's
        // card and then fail to find its rows — a blank card, and a fresh
        // `onyx-` id on the first tick.
        let loggedSets = logged.map {
            DeckRestore.LoggedSet(
                id: $0.id,
                key: canonical($0.exerciseId).lowercased(),
                pairId: $0.pairId,
                // The LOCAL spelling, for the reason the row below restores
                // in it: `L` reaching the fold would make one physical set
                // count as two and seed a phantom blank to make up the
                // difference.
                side: SyncTranslation.localSide($0.side)
            )
        }
        func fold() -> DeckRestore.Plan {
            DeckRestore.fold(
                cards: exercises.map {
                    DeckRestore.Card(
                        key: ExerciseAliases.canonicalName($0.name).lowercased(),
                        // SETS, which is the unit `blankSets` comes back in and the
                        // unit `seedRows(count:)` has always taken. `rows.count` is
                        // the number that was wrong.
                        shownSets: Self.physical($0.rows)
                    )
                },
                logged: loggedSets
            )
        }
        var restore = fold()
        let loggedById = Dictionary(logged.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // ── A MOVEMENT ADDED MID-SESSION COMES BACK AS ITS CARD (W3) ────────
        // The deck is rebuilt from the day's PROGRAM on a relaunch, and a
        // movement added in the session is not in it — so its logged rows came
        // back as `unmatched`, which this used to leave undrawn: sets in the
        // log and in `closeSession`'s counts, and not on the screen. Each such
        // movement gets its card back, the way it got it the first time, and
        // the fold runs again over a deck that now has somewhere to put them.
        if !restore.unmatched.isEmpty {
            var seen = Set<String>()
            for set in restore.unmatched where seen.insert(set.key).inserted {
                // Only a movement the catalogue can NAME. An id it cannot
                // resolve yet (a relaunch before the pull lands) would title
                // the card with a raw slug or uuid; those rows stay off the
                // deck, as they always did, until the catalogue can name them.
                guard let row = loggedById[set.id],
                      catalogue[row.exerciseId] != nil || bySlug[row.exerciseId] != nil
                else { continue }
                let card = appendCard(named: canonical(row.exerciseId))
                // A bout the opener no longer names (the last `cardio_logs`
                // row changed kind in between) comes back as the bout it was,
                // with no lifting blanks proposed under it.
                if WarmupCardio.isCardio(durationSec: row.durationSec, distanceKm: row.distanceKm, inclinePct: row.incline) {
                    card.rows = []
                }
            }
            restore = fold()
        }

        for (exercise, owned) in zip(exercises, restore.cards) {
            let mine = owned.loggedIds.compactMap { loggedById[$0] }
            // A card the session holds nothing of keeps the deck it was built
            // with — blanks the athlete may already have typed into, and rows a
            // phase switch placed. Rebuilding it from the seed here would throw
            // that away to say the same thing.
            guard !mine.isEmpty else { continue }
            // Whatever id these rows already carry is the id a set appended
            // beside them must carry — see `ExerciseState.storedExerciseId`.
            exercise.storedExerciseId = mine[0].exerciseId
            var rows: [SetRow] = mine.map { set in
                SetRow(
                    id: set.id,
                    storeId: set.id,
                    weightKg: set.weightKg,
                    reps: set.reps,
                    rpe: set.rpe,
                    kind: SetKind(rawValue: set.setType) ?? .normal,
                    qualities: SetQuality.parse(set.quality),
                    isDone: true,
                    // A logged set's Previous is the same seed the blank row
                    // would have shown — what this set number was LAST time,
                    // not what it is now.
                    // A restored warm-up shows nothing: `seededPrevious` is
                    // about working sets, and a warm-up wearing set 1's history
                    // is worse than a blank column.
                    previous: set.setType == "warmup" ? nil : seededPrevious(
                        exercise.plan,
                        workingIndex: mine.prefix(while: { $0.id != set.id })
                            .filter { $0.setType != "warmup" }.count
                    ),
                    isRecord: false,
                    // A split set restores split. Dropped here, the pair would
                    // come back as two unsided rows the moment anything on the
                    // card was amended — and `SessionVolume` would then score
                    // the two arms separately, very nearly doubling the session.
                    //
                    // ── AND IT RESTORES IN THE LOCAL SPELLING ───────────────
                    // Not `set.side` verbatim. The column can hold either
                    // vocabulary — `left`/`right` is what this deck writes, and
                    // `L`/`R` is what the wire carries — and every rule that
                    // folds a pair downstream of here tests for the first one:
                    // `sideLabel` (the badge), `groups(_:)` (which set the row
                    // belongs to) and `SessionVolume`'s pair collapse. A
                    // restored `L` therefore drew ONE physical set as two rows,
                    // numbered them 3 and 4, and weighed the arm twice — the
                    // "sets jump by 2 on some exercises" report, on exactly the
                    // exercises that are unilateral, and only after the session
                    // had been closed and reopened.
                    side: SyncTranslation.localSide(set.side),
                    pairId: set.pairId,
                    // A treadmill bout restores as a treadmill bout. Dropped
                    // here, the first amend of the session wrote them back as
                    // null — see `SetRow.durationSec`.
                    durationSec: set.durationSec,
                    incline: set.incline,
                    distanceKm: set.distanceKm,
                    elevationM: set.elevationM
                )
            }
            // Keep whatever blanks the prescription still asks for beyond what
            // was logged — in SETS, from the fold. Warm-ups are not re-offered:
            // a restored session already holds the ones that were performed.
            rows.append(contentsOf: seedRows(exercise.plan, count: owned.blankSets, warmups: false))
            // ── AND ON AN EDIT, NO "PREVIOUS" AT ALL ────────────────────────
            // The seed is built by `sessionSeed(dayKey:)`, which takes no date
            // and answers with the most recent session on this day key. On a
            // three-week-old session that is a workout which happened AFTER the
            // one being corrected, printed under each set as what it was "last
            // time". A blank column is the honest reading; the summary page one
            // screen back carries the real comparison.
            if isEditing { for row in rows { row.previous = nil } }
            exercise.rows = rows
        }
    }

    /// Canonical name → the local catalogue's id.
    ///
    /// A name TWO rows answer to is absent from this map, not resolved to one
    /// of them. That is the question `ExerciseIndex.id(forSlug:)` answers by
    /// throwing `ambiguousExercise`, and for the same reason: `Crunch Machine`
    /// and `Crunch (Machine)` are separate rows with different `is_bodyweight`,
    /// and picking one files half a history under the wrong ladder.
    private var idByCanonicalName: [String: String] = [:]

    /// Whether the local catalogue has been read at all, and whether it had
    /// anything in it. An EMPTY catalogue means "not pulled yet", not "this
    /// movement does not exist" — see `storedIdCreatingCatalogueRow`.
    private var catalogueLoaded = false
    private var catalogueIsEmpty = true

    /// Rebuild `idByCanonicalName` from the local catalogue.
    private func refreshCatalogueIndex() {
        guard let store, let rows = try? store.exercises() else { return }
        catalogueLoaded = true
        catalogueIsEmpty = rows.isEmpty
        idByCanonicalName = AppDatabase.exerciseIds(byCanonicalNameIn: rows)
    }

    private func catalogueIndex() -> [String: String] {
        if !catalogueLoaded { refreshCatalogueIndex() }
        return idByCanonicalName
    }

    private func canonicalKey(_ name: String) -> String {
        ExerciseAliases.canonicalName(name).lowercased()
    }

    /// `actualRestSec` is passed only by the APPEND path. An amend rebuilds the
    /// snapshot to diff it, and a measurement re-derived at edit time would be
    /// the time since the last commit of whatever the athlete is editing now.
    private func snapshot(
        _ row: SetRow, in exercise: ExerciseState, actualRestSec: Int? = nil
    ) -> SetSnapshot {
        SetSnapshot(
            exerciseId: storedIdCreatingCatalogueRow(for: exercise),
            setIndex: (exercise.rows.firstIndex { $0.id == row.id } ?? 0) + 1,
            // A missing load is 0 kg — a real bodyweight set — and a missing rep
            // count cannot reach here, because `toggleDone` refuses to tick one.
            weightKg: row.weightKg ?? 0,
            reps: row.reps ?? 0,
            setType: row.kind.rawValue,
            // The local spelling — see `SetRow.side`. `SyncTranslation.side` is
            // the only thing that turns it into the wire's `L`/`R`.
            side: row.side,
            pairId: row.pairId,
            est1rmKg: row.estimated1RM,
            rpe: row.rpe,
            quality: SetQuality.join(row.qualities),
            exerciseOrder: deckOrder(of: exercise),
            // Nil on every lifted row, which is what they are on a lifted set.
            // On a restored cardio bout they are the only content the set has.
            durationSec: row.durationSec,
            incline: row.incline,
            distanceKm: row.distanceKm,
            elevationM: row.elevationM,
            actualRestSec: actualRestSec
        )
    }

    /// Where a movement sits in the deck — the number every set of it is
    /// written under, and the only place it is computed.
    ///
    /// ── ONE HELPER, BECAUSE FOUR CALL SITES WOULD DRIFT ─────────────────────
    /// `appendInStore`, `amendInStore`, `restampFrom` and `moveExercise` all
    /// need it, and all four reach it through `snapshot`. A value recomputed at
    /// each would be four chances for a card to claim a position it is not in —
    /// the same failure `storedId` exists to prevent one column over.
    ///
    /// Dense from 0, matching `buildCommitPayload` on the web: `exercise_order`
    /// is one column read by both clients and two numbering schemes for it
    /// would interleave a session logged half on each.
    ///
    /// The DECK's index and not the store's, in edit mode too, and that is
    /// right there: `SessionDetailView.editorDay` builds the editing deck in
    /// the session's own performed order, so the index already IS what the rows
    /// carry — and where it is not (a movement the session never held), the
    /// deck is the only thing that has an opinion at all.
    private func deckOrder(of exercise: ExerciseState) -> Int? {
        exercises.firstIndex { $0.id == exercise.id }
    }

    /// Which `exercise_id` this movement's sets are written under.
    ///
    /// The session's own, when it already holds rows of this movement; then the
    /// local catalogue, so a set ADDED to a web-logged session joins the same
    /// row every other client resolves; then the slug, which is what a live
    /// session writes and what `ExerciseIndex.id(forSlug:)` resolves on push.
    ///
    /// The id this movement's sets are filed under. READ ONLY — creates
    /// nothing. Four callers reach here before a set exists (the two attaches,
    /// the live-PR tick, and the records view), and a screen opening is not a
    /// reason to invent a row anybody else has to live with.
    private func storedId(for exercise: ExerciseState) -> String {
        if let stored = exercise.storedExerciseId { return stored }
        if let catalogued = exercise.plan.exerciseId { return catalogued }
        return catalogueIndex()[canonicalKey(exercise.name)] ?? ExerciseSlug.id(exercise.name)
    }

    /// ── THE UUID, AT COMMIT (W6) ────────────────────────────────────────────
    /// `storedId`, plus the one thing it will not do: give a movement the
    /// catalogue has never heard of a row of its own. Called from `snapshot`
    /// and nowhere else, so a row appears exactly when a logged fact needs
    /// something to point at.
    ///
    /// Until W6 this wrote a slug of the name, and the set landed under a
    /// second identity — the SPLIT `ExerciseIndex`'s header describes. On a
    /// generic account, where a template names movements no catalogue row
    /// answers for, that is the common case rather than the edge one.
    ///
    /// `createExercise` is idempotent on the name and writes LOCALLY first,
    /// queueing the row through the ordinary outbox, so this is correct with no
    /// network. Two refusals keep it safe:
    ///
    ///   * An EMPTY catalogue is not evidence the movement is new. A reinstall,
    ///     a second device, or a deck opened before `TrainingPuller` finishes
    ///     all look identical to one, and minting there would queue a row the
    ///     server already holds under another id — which `UNIQUE (user_id,
    ///     name)` rejects on every retry, stranding the sets behind it.
    ///   * An AMBIGUOUS name is absent from the index by construction, so it
    ///     falls to the slug and `ExerciseIndex` refuses it out loud at push
    ///     time, rather than being guessed at silently here.
    ///
    /// Both fall back to the slug, which has resolved at push since W2. A
    /// logged rep is never worth losing to a catalogue write.
    private func storedIdCreatingCatalogueRow(for exercise: ExerciseState) -> String {
        if let stored = exercise.storedExerciseId { return stored }
        if let catalogued = exercise.plan.exerciseId { return catalogued }
        let key = canonicalKey(exercise.name)
        if let known = catalogueIndex()[key] { return known }
        guard let store, !catalogueIsEmpty,
              let created = try? store.createExercise(userId: userId, name: exercise.name)
        else { return ExerciseSlug.id(exercise.name) }
        idByCanonicalName[key] = created
        return created
    }

    /// Open the session deliberately — the logger was presented by Start.
    ///
    /// ── WHY THE ROW NOW EXISTS BEFORE THE FIRST SET (App Store W4) ──────────
    /// `attach` stays look-up-only, and `ensureSession` still covers the
    /// append. But a session that exists only once a set does is a session the
    /// wrist cannot follow: the watch adopts a ROW (`SessionPulse`), and
    /// "start on the phone, raise your wrist" has to work during the warm-up,
    /// when nothing has been ticked. The watch's own Start has created its row
    /// on the tap since Wave 10 for the same reason — a tap on Start is not an
    /// appearance. The logger is only ever presented by one (`WorkoutTabView`
    /// says so in its header), and the Live Activity already treats the same
    /// moment as the start of the workout.
    ///
    /// An open row with nothing in it loses to a finished session in the
    /// Train footer (`WorkoutWeek`), is never pushed until it holds a set or
    /// closes, and `cancel` discards it.
    ///
    /// Not for a deck that is `following` the wrist: that one attaches to the
    /// wrist's row or to nothing, never to a second row of its own.
    func begin() {
        guard sessionId == nil, following == nil else { return }
        do {
            _ = try openRow()
        } catch {
            storeError = String(describing: error)
        }
    }

    /// The session the WRIST opened that this deck was presented for, if it
    /// was (App Store W4). Set by `WorkoutTabView` before the cover appears.
    ///
    /// If the wrist's finish lands between the tab deciding to follow and the
    /// cover's `attach`, `attach` finds no live row — and a `begin` then would
    /// open a brand-new session, announce it, and put an `HKWorkoutSession`
    /// on the wrist for a workout that never happened. So a following deck
    /// never begins, and the tab uses this id to let it go.
    var following: String?

    /// Called with the row the moment THIS deck creates one — from `begin`,
    /// or from `ensureSession` if `begin` could not. The view tells the wrist.
    /// A closure rather than transport in the model, for the reason
    /// `mirrorRestToWatch` gives; and in `openRow`, because that is the one
    /// place both roads to a new row pass through.
    @ObservationIgnored var onOpened: ((WorkoutSession) -> Void)?

    /// The session row this device is writing into, created on demand.
    ///
    /// Called from the append path, so a session exists whenever a set does —
    /// and from `begin`, so it exists from Start.
    private func ensureSession() throws -> String? {
        if let sessionId { return sessionId }
        return try openRow()?.id
    }

    private func openRow() throws -> WorkoutSession? {
        guard let store else { return nil }
        // Edit mode is handed its session and never creates one. Reaching here
        // with `editing` set would mean `attach(editing:)` failed and the deck
        // then opened a BRAND NEW session dated today for a workout three weeks
        // old — the one failure in this file that writes a fact rather than
        // losing one.
        guard editing == nil else { return nil }
        let session = try store.openSession(
            userId: userId,
            dayKey: day.key,
            // The logical calendar day is the DEVICE's, never the server's —
            // `/api/today` takes the date as a parameter for exactly this reason.
            date: LogicalDay.today(),
            startedAt: startedAt
        )
        sessionId = session.id
        onOpened?(session)
        return session
    }

    private func appendInStore(_ row: SetRow, in exercise: ExerciseState) {
        guard let store else { return }
        do {
            guard let sessionId = try ensureSession() else { return }
            if isEditing {
                // ── THE OUTCOME IS THE ANSWER TO "DID ANYTHING CHANGE" ──
                // `SessionEditing` returns nil for a write it declined — an
                // amend whose patch restates the row it describes, which is
                // what a tap into a field and a tap away produces. Flagging the
                // edit dirty on one of those schedules a forty-nine-day cascade
                // for a session nobody touched.
                _ = try store.addSet(sessionId: sessionId, userId: userId, snapshot(row, in: exercise), setId: row.storeId)
            } else {
                // ── THE MEASUREMENT, TAKEN ONCE, HERE ───────────────────────
                // Read BEFORE the stamp is updated — `restGapSec` is the gap
                // since the PREVIOUS commit, and writing `lastCommitAt` first
                // would measure every set as zero.
                let now = Date()
                let rest = restGapSec(for: exercise, at: now)
                try store.appendSet(
                    sessionId: sessionId, setId: row.storeId,
                    snapshot(row, in: exercise, actualRestSec: rest)
                )
                // Stamped only on a write that SUCCEEDED. A throw above leaves
                // the previous stamp standing, so the next set measures from
                // the last set actually recorded rather than from one that
                // never reached the store.
                lastCommitAt[exercise.name] = now
            }
            storeError = nil
        } catch {
            storeError = String(describing: error)
        }
    }

    private func amendInStore(_ row: SetRow, in exercise: ExerciseState) {
        guard let store, let sessionId else { return }
        let next = snapshot(row, in: exercise)
        do {
            if isEditing {
                // `SessionEditing.amendSet`, which seeds the log, replays the
                // ledger for this movement — the only path that can take a
                // record BACK when a mistyped 100 becomes 60 — and recounts the
                // session's stored tonnage. `EventStore.amendSet` does none of
                // the three and claims a pencil nothing is holding.
                _ = try store.amendSet(
                    sessionId: sessionId, userId: userId, setId: row.storeId,
                    weightKg: next.weightKg, reps: next.reps, rpe: next.rpe,
                    setType: next.setType,
                    quality: next.quality ?? SetPatch.clearedQuality,
                    side: next.side, pairId: next.pairId,
                    est1rmKg: next.est1rmKg, setIndex: next.setIndex,
                    exerciseOrder: next.exerciseOrder
                )
                storeError = nil
                return
            }
            try store.amendSet(sessionId: sessionId, setId: row.storeId, SetPatch(
                setIndex: next.setIndex, weightKg: next.weightKg, reps: next.reps,
                setType: next.setType, side: next.side, pairId: next.pairId,
                est1rmKg: next.est1rmKg, rpe: next.rpe,
                // The sentinel, not nil: `nil` in a patch means UNCHANGED, so
                // withdrawing a quality would otherwise be the one edit the
                // amend could not express. See `SetPatch.clearedQuality`.
                quality: next.quality ?? SetPatch.clearedQuality,
                exerciseOrder: next.exerciseOrder
            ))
            storeError = nil
        } catch EventStoreError.emptyPatch {
            // Nothing actually changed. Not an error, and not worth a row in a
            // log that is never compacted.
        } catch {
            storeError = String(describing: error)
        }
    }

    private func voidInStore(_ row: SetRow) {
        guard let store, let sessionId else { return }
        do {
            if isEditing {
                _ = try store.deleteSet(sessionId: sessionId, userId: userId, setId: row.storeId)
            } else {
                try store.voidSet(sessionId: sessionId, setId: row.storeId)
            }
            // The tombstone is permanent (`SetEventFold`'s rule 3), so this row
            // must never write under that id again. Re-minted HERE rather than
            // in `toggleDone` so every path that voids gets it — there is only
            // one, and there being only one is not a rule anybody wrote down.
            row.storeId = newOnyxID()
            storeError = nil
        } catch {
            storeError = String(describing: error)
        }
    }
}

// MARK: - The start instant, before there is a row to keep it in

/// Where a live deck's `startedAt` lives until the first set creates a session.
///
/// ── WHY THIS IS NOT THE SESSION ROW ─────────────────────────────────────────
/// Because until App Store W4 there wasn't one before the first APPEND. `begin`
/// now opens the row at Start, so this covers only a deck whose `begin`
/// failed — and it is cleared on finish, on cancel, and when the WRIST ends
/// the session (`PhoneWatchBridge`), or a later Start on the same split would
/// adopt a dead session's clock.
///
/// Which leaves a real window with no durable clock in it — open the deck,
/// warm up for eleven minutes, get jetsammed, and the relaunch believes the
/// workout began when you reopened it. `UserDefaults.standard` is the sanctioned
/// per-device store for exactly this (the `onyx.phase` idiom; the App Group
/// suite is unsigned dead code on the free team), it needs no session, no
/// schema and no migration, and the value is a per-device draft rather than an
/// account fact — the session row is what syncs.
///
/// Keyed by `(date, dayKey)` so a two-a-day and a swap cannot collide, and read
/// through the same six-hour bound `SessionElapsed` applies: a key older than
/// any real workout is not a clock, it is litter.
///
/// ponytail: keys are cleared on finish and on cancel, and a stale one is
/// refused on read, so the litter is bounded by "days you opened a deck and
/// never finished it" — a handful of 8-byte values. Sweep them on launch if
/// that ever stops being true.
enum LiveSessionStart {
    private static func key(dayKey: String, date: String) -> String {
        "onyx.live.start.\(date).\(dayKey)"
    }

    /// How old a banked start may be and still be believed.
    ///
    /// ── WHY IT IS NOT THE SIX-HOUR SESSION BOUND ────────────────────────────
    /// This value only ever covers the window between opening a deck and
    /// logging the first set — after that there is a session row and the row
    /// wins. A deck that has gone three quarters of an hour without a single
    /// set is not mid-warm-up; it was opened and walked away from, and adopting
    /// its instant would start the next session two hours in the past. Forty
    /// five minutes is longer than any warm-up and far shorter than an
    /// abandoned afternoon.
    static let maxAgeSec: TimeInterval = 45 * 60

    /// The stored instant, or nil when there is none worth believing.
    static func read(dayKey: String, date: String, now: Date = Date()) -> Date? {
        let raw = UserDefaults.standard.double(forKey: key(dayKey: dayKey, date: date))
        // `double(forKey:)` answers 0 for a key that is not there, which is
        // also 1970 — so the absent case and the corrupt case are one test.
        guard raw > 0 else { return nil }
        let at = Date(timeIntervalSince1970: raw)
        let age = now.timeIntervalSince(at)
        guard age >= 0, age <= maxAgeSec else { return nil }
        return at
    }

    static func write(_ at: Date, dayKey: String, date: String) {
        UserDefaults.standard.set(at.timeIntervalSince1970, forKey: key(dayKey: dayKey, date: date))
    }

    static func clear(dayKey: String, date: String) {
        UserDefaults.standard.removeObject(forKey: key(dayKey: dayKey, date: date))
    }
}
