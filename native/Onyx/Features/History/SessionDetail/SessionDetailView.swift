import SwiftUI
import Charts
import OnyxUI
import OnyxCore
import OnyxData

/// The post-workout page: what one session was, and what it means.
///
/// ── NOT THE WEB REPORT, AND NO LONGER A BARE LEDGER ─────────────────────────
/// `session/[id]/page.tsx` is three bordered bands with a six-cell metric table.
/// Wave 7's native answer was the opposite mistake: a `List` that opened
/// straight into set rows, so the screen you land on after finishing a workout
/// began with "Set 1, 42 kg × 10" and you had to scroll to learn anything.
///
/// §5.4 gives it a shape that answers questions in the order they are asked:
///
///   1. WHICH session — a title band washed in the split's own colour, with the
///      plan, the phase week and the lever resolved FOR THAT DATE.
///   2. WHAT it produced — seven figures, each with a reserved line under it for
///      the change against the previous session of the same split.
///   3. WHETHER it was progress — the split's tonnage as a line, this session's
///      point selected, records marked in gold.
///   4. WHERE it landed — the body, hit-testable, with weighted set counts.
///   5. THE LEDGER — every set, grouped by movement, with the previous session's
///      set beside each and a 40×16 trail of estimated 1RM in the header.
///
/// ── A BENTO SINCE THE OVERHAUL (C1, decisions Q12–Q15) ───────────────────
/// The five questions above made five panels and a ledger card per movement:
/// four screens of scroll on a six-movement day. The first screen is now the
/// answer and the rest is one tap away — masthead, the heart-rate strip
/// (inline, segments only), a 2-column grid of exercise chips (each opens its
/// ledger card in a sheet), the focus pills (open the atlas) and one
/// Progression button (the split's chart and the full metric grid, in a
/// sheet). Target ≤ 1.1 screens at default type on a 393 pt phone.
///
/// Records are DETECTED here, not read: `personal_records` is a current-best
/// table, so an old session's trophies would vanish the day they were beaten.
/// `SessionAnalysis` replays the engine against the sets that came before,
/// which is the same question the save path asked on the day.
struct SessionDetailView: View {
    let sessionId: String
    /// Screenshot harness only: open parked on the ledger. Half of this page is
    /// the ledger and a shot of the first screen reviews only the half that
    /// fits, so the shot loop takes two pictures of one screen.
    var startAtLedger = false
    /// Screenshot harness only: open with the atlas sheet already presented. A
    /// shot script can launch a screen and cannot tap a tile.
    var startAtAtlas = false
    /// Screenshot harness only: open straight into the edit deck (§U4.5), for
    /// the same reason — the button that opens it is in a toolbar.
    var startAtEditor = false
    /// Screenshot harness only: open with the trophy's record sheet already up.
    /// The gesture that opens it is a long press, which a shot script cannot
    /// perform.
    var startAtRecord = false
    /// Opens every ledger card on its assisting muscles — the harness only.
    ///
    /// Row 2 swaps IN PLACE and the claim this wave makes about it is that the
    /// card does not move when it does. A shot script cannot tap a chip, so the
    /// two states are photographed as two screens and the review is that they
    /// are the same height — the same trick `seededExpandedWeek` used for the
    /// row W1 deleted.
    var startWithAssists = false
    /// Holds every record row's margin open instead of taking it away after
    /// two seconds — the harness only.
    ///
    /// The shot script sleeps eight seconds before it asks the OS for a
    /// picture, so the callout this wave adds is always already gone by the
    /// time anything photographs it. Two shots of one screen, as
    /// `startWithAssists` takes for row 2: `session-ledger` is the page at
    /// rest, `session-margin` is the two seconds it opens on.
    var holdMargins = false
    /// Set by the tab that PUSHED this page after a finish (overhaul C2):
    /// when the edit cover closes, the summary pops too and the athlete lands
    /// on Train — the workout is done. Nil from History and every other
    /// caller, where closing the editor returns to this page as it always did.
    var dismissToTrain: (() -> Void)? = nil

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var page: SessionAnalysis.Page?
    @State private var missing = false
    /// Which cascade this page's numbers were read after — see
    /// `AppEnvironment.rescoreGeneration`. `-1` so the first `.task` always runs.
    @State private var loadedAt = -1
    @State private var showAtlas = false
    /// The session being edited, presented as a full-screen logger deck.
    @State private var editing: LoggerModel?
    /// The trophy the reader long-pressed, if any.
    ///
    /// Held by the PAGE and not by the row, for the reason
    /// [[set-row-u2]] records: a sheet presented by a row is destroyed with its
    /// presenter the moment the list rebuilds under it — and this list rebuilds
    /// on every rescore generation. The target carries everything the sheet
    /// needs, so nothing is re-read at presentation time either.
    @State private var prSheet: PrTarget?
    /// Hevy's record of this session, if Health holds one and the athlete has
    /// not answered the card yet (W5, decision 7).
    @State private var foreign: WorkoutSample?
    /// The movement whose ledger card is up in a sheet (row 3's chips).
    @State private var ledgerFor: SessionAnalysis.ExerciseReport?
    /// The Progression sheet — the split's chart and the metric grid (row 5).
    @State private var showProgression = false
    /// Row 2's series and the names its movements are drawn under.
    @State private var heart: SessionTelemetry.Reading?
    @State private var heartNames: [String: String] = [:]

    /// One long-pressed trophy, frozen at the moment of the press.
    struct PrTarget: Identifiable {
        let exercise: String
        let timed: Bool
        let setLabel: String
        let records: [LivePrRecord]
        var id: String { (records.first?.id ?? exercise) + setLabel }
    }

    /// One tapped sparkline, frozen the same way and for the same reason (W10).
    @State private var trailSheet: TrailTarget?

    /// The movement's whole est-1RM history, as `E1rmTrendChart` takes it.
    struct TrailTarget: Identifiable {
        let exercise: String
        let points: [(date: String, kg: Double)]
        var id: String { exercise }
    }

    /// The split's own colour — the tint of the tonnage line, and the wash
    /// `SessionHeaderCard` bleeds behind the title.
    private var split: Color { Color.onyx.day(report?.session.dayKey) }

    private var report: SessionAnalysis.Report? { page?.report }

    var body: some View {
        ScrollView {
            VStack(spacing: OnyxSpace.m) {
                if let page {
                    // 1 · which session, and what it weighed
                    masthead(page)
                    // 2 · the heart rate, inline — nothing when there is none
                    if let heart, !heart.isEmpty {
                        HeartStrip(reading: heart, names: heartNames)
                    }
                    if let foreign { hevy(page, foreign) }
                    // 3 · every movement, one chip each
                    exerciseGrid(page.report)
                    // 4 · what it trained
                    if !page.report.muscles.isEmpty {
                        FocusPills(muscles: page.report.muscles) { showAtlas = true }
                    }
                    // 5 · the one door to the chart and every figure
                    ProgressionButton(caption: page.verdict) { showProgression = true }
                }
                // ── NO CARDIO BANNER HERE ───────────────────────────────────
                // `cardio_logs` is the MAIN TAB's subject — a bout is planned,
                // counted against the Zone 2 rail and read on the day it
                // happened. On a finished session it was a second list under
                // the ledger, in a different shape from every movement above
                // it, describing rows that are not part of the workout the page
                // is about (`AppDatabase.cardio` matches on the DATE as well as
                // the session, so a morning walk appeared under an evening leg
                // day). A treadmill bout that IS part of the session is a
                // `workout_sets` row and gets an exercise card like any other
                // movement — see the seed's Treadmill, first in this list.
            }
            .padding(.horizontal, OnyxSpace.l)
            .padding(.vertical, OnyxSpace.s)
        }
        .onyxScreen(.train)
        // Keyed on the telemetry generation, like the finish sheet's card: a
        // strip that opened empty fills in when the watch's late samples land.
        .task(id: environment.telemetryGeneration) { await loadHeart() }
        .tint(OnyxDomain.train.accent)
        .navigationTitle(report.map { SessionRow.date($0.session.date) } ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        // ── THE BAR NEEDS A MATERIAL NOW THAT THE LEDGER HAS TITLES ─────────
        // A scrolled `List` passes under a transparent bar, which was tolerable
        // when an exercise header was 13 pt uppercase grey and is not now that
        // it is a 20 pt name on a tinted gradient: the first shot had "Incline
        // DB Press" legible THROUGH the bar, crossing the date. The material is
        // the same one every other floating surface in the app uses, so the
        // bar still reads as glass over the mesh rather than as a solid strip.
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar { editItem }
        // ── WHY A FULL-SCREEN COVER AND NOT A PUSH ──────────────────────────
        // The same reason `WorkoutTabView` presents the live deck this way: the
        // logger is a mode, not a destination. It owns the whole screen, it has
        // its own two ways out, and a navigation bar over it would offer a
        // third that means something different from both. `item:` rather than
        // `isPresented:` for the reason that file spends a paragraph on — a
        // cover whose content builder reads `if let model` comes up empty when
        // the flag and the model are set in the same runloop turn.
        .fullScreenCover(item: $editing, onDismiss: {
            editing = nil
            dismissToTrain?()
        }) { model in
            NavigationStack {
                LiveLoggerView(model: model)
            }
            .environment(environment)
            .preferredColorScheme(.dark)
        }
        .overlay {
            if missing {
                ContentUnavailableView("Session not found", systemImage: "questionmark.circle")
            } else if page == nil {
                ProgressView()
            }
        }
        // ── WHY THE ATLAS REPLACED `MuscleDistributionSheet` HERE ───────────
        // §U4.4. The flat sheet draws the front and the back as two half-width
        // figures, which is the right answer inside the LOGGER, where it is a
        // glance between sets. On a finished session it is the page's only
        // picture, and half of a leg day is on a body nobody can hit-test at
        // 150 pt. The logger keeps the flat sheet; this one turns over.
        .sheet(isPresented: $showAtlas) {
            if let report {
                AtlasSheet(
                    sets: Dictionary(uniqueKeysWithValues: report.muscles.map { ($0.muscle, $0.sets) }),
                    physicalSets: report.physicalSets,
                    sessionLabel: shareLabel(report)
                )
            }
        }
        // The deck's own record sheet, on the deck's own gesture. `PrRecordSheet`
        // is not re-implemented for this page and must not be: a record read
        // mid-workout and the same record read afterwards are one fact, and two
        // sheets is how they start rounding differently.
        .sheet(item: ledgerFor == nil ? $prSheet : .constant(nil)) { target in
            prRecordSheet(target)
        }
        // Row 3's door: one movement's ledger card. The record and trail
        // sheets it can open are presented FROM it — a page already presenting
        // a sheet cannot present a second.
        .sheet(item: $ledgerFor) { ex in
            ledgerSheet(ex)
        }
        .sheet(isPresented: $showProgression) {
            if let page { progressionSheet(page) }
        }
        // ── THE SPARKLINE'S OWN SHEET (W10) ────────────────────────────────
        // The same chart the exercise's own page draws, from the same type
        // (`E1rmTrendChart`, second caller after `ExerciseDetailView:159`) —
        // not a second plot of one history. The header's 56×16 trail says
        // "this moved"; the question it provokes is "by how much, and when",
        // and that needs an axis, which is the one thing a sparkline refuses
        // to have. `.medium` because a line chart with a date axis is a
        // half-screen object and the ledger under it stays visible.
        // ── WHY THIS IS `id:`-KEYED AND NOT A ONE-SHOT `.task` ──────────────
        // §U4.5 makes this page's own Edit button rewrite the session it is
        // drawing, and §E1's cascade then rewrites every daily score behind it.
        // A `.task` that ran once left the reader looking at the tonnage they
        // had just corrected. `rescoreGeneration` moves ONCE per cascade — when
        // every day the edit touched agrees — so keying on it reloads at the
        // one instant a reload gives a consistent answer. The guard is
        // `HistoryView`'s: a `.task(id:)` re-runs on any re-identification of
        // the view, not only on the id changing.
        .task(id: environment.rescoreGeneration) {
            guard loadedAt != environment.rescoreGeneration else { return }
            let first = loadedAt < 0
            loadedAt = environment.rescoreGeneration
            let database = environment.database, id = sessionId
            page = await Task.detached(priority: .userInitiated) {
                SessionAnalysis.page(database: database, sessionId: id)
            }.value
            missing = page == nil
            if first, let session = page?.report.session {
                // Once, on the first load: a cascade re-running the task must
                // not bring back a line whose figures were adopted on this very
                // screen. Down only once they are (`.use`) — the line is a fact,
                // not a question, so a legacy `.skip` no longer hides it.
                if await environment.telemetry.hevyDecision(sessionId: id) != .use {
                    foreign = await environment.foreignWorkout(for: session)
                }
            }
            #if DEBUG
            // `else if`, and only on the FIRST load: two modals from one source
            // view drops the second with an "already presenting" warning, and
            // this `.task` re-runs on every cascade — so saving from the editor
            // re-presented the editor over the page the shot was meant to take.
            if first, page != nil {
                if startAtAtlas { showAtlas = true }
                else if startAtEditor { openEditor() }
                // The trophy's own sheet, from the first record this session
                // actually holds. Seeded from the REAL report rather than a
                // fixture, for the reason `set-row-records` gives one screen
                // over: a shot of a hand-built sheet reviews the sheet and not
                // the path that fills it, and the path is the new half.
                else if startAtRecord { openFirstRecord() }
            }
            #endif
            // The ledger lives in a sheet now: the harness opens the card
            // worth photographing — a pair card when the session has one, a
            // record card next, the first movement otherwise.
            if first, startAtLedger, let exercises = page?.report.exercises {
                try? await Task.sleep(for: .milliseconds(400))
                ledgerFor = exercises.first { $0.rows.contains { $0.kind == "pair" } }
                    ?? exercises.first { !$0.records.isEmpty }
                    ?? exercises.first
            }
        }
    }

    /// Row 2's read: the series, then the catalogue names its movements carry.
    private func loadHeart() async {
        let telemetry = environment.telemetry, database = environment.database
        let next = await telemetry.reading(sessionId: sessionId)
        if heartNames.isEmpty, next?.isEmpty == false {
            heartNames = await Task.detached(priority: .userInitiated) {
                Dictionary(((try? database.exercises()) ?? []).map { ($0.id, $0.name) },
                           uniquingKeysWith: { first, _ in first })
            }.value
        }
        heart = next
    }

    /// Harness only: present the sheet for the first record the page holds.
    private func openFirstRecord() {
        guard let page else { return }
        for exercise in page.report.exercises {
            for row in exercise.rows {
                let won = [row.set, row.left, row.right]
                    .compactMap { $0 }
                    .flatMap { exercise.records[Int($0.setNumber)] ?? [] }
                guard !won.isEmpty else { continue }
                prSheet = PrTarget(
                    exercise: exercise.canonical, timed: exercise.timed,
                    setLabel: row.num.map { "Set \($0)" } ?? "Warm-up set",
                    records: won
                )
                return
            }
        }
    }

    // MARK: - Editing

    /// Re-open this session on the logger's own deck (§U4.5).
    ///
    /// ── WHY THE DECK AND NOT A FORM ─────────────────────────────────────────
    /// Correcting a set is the same act as logging one: the same rep window,
    /// the same steppers, the same options sheet, the same effort ladder, and
    /// the same live record detection that says whether the corrected number
    /// still stands. A second editor would be a second opinion about all of it
    /// — and would be the surface that gets left behind the next time the set
    /// row changes.
    @ToolbarContentBuilder
    private var editItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                openEditor()
            } label: {
                Label("Edit session", systemImage: "square.and.pencil")
            }
            .disabled(!canEdit)
            .accessibilityHint(canEdit
                ? "Opens this workout on the logger, where its sets can be corrected."
                : "This session recorded no sets, so there is nothing to correct.")
        }
    }

    /// The program day this session was, PLUS whatever it actually contains.
    ///
    /// ── A SESSION THE PROGRAM CANNOT NAME IS STILL EDITABLE ─────────────────
    /// This used to answer nil for a session with no `day_key`, or one whose
    /// key the program no longer has, on the reasoning that its sets "would
    /// come up on a blank screen". They would not: the loop below appends
    /// EVERY movement the report holds as a one-off prescription, so a day the
    /// program does not know contributes nothing to the deck and takes nothing
    /// away from it. What the nil actually did was disable the Edit button on
    /// the 74 Notion-era sessions (which carry no `day_key` at all) and on
    /// every Onyx-4 and PPL session — a record the app will show you and
    /// refuse to let you correct.
    ///
    /// So an unknown key gets an EMPTY day instead of no day. The label is the
    /// one the rest of the page already prints for that key, and the accent is
    /// unread on this path (the deck tints from `Color.onyx.day`, which has its
    /// own answer for a key it does not know). A session with no movements at
    /// all is still nil — there is nothing to correct, and `openEditor` would
    /// put an empty deck on screen.
    ///
    /// ── WHY THE DECK IS EXTENDED AND NOT JUST LOOKED UP ─────────────────────
    /// The deck is the PROGRAM's list of movements and a session is what was
    /// actually done. Those disagree whenever a machine was taken, a lift was
    /// swapped, or the workout was logged on the web (whose picker is the whole
    /// 60-row catalogue, not the day's six). `restoreLoggedSets` folds a
    /// session's rows onto the deck by name, so a movement the deck does not
    /// carry simply does not appear — the rows are safe, and they are
    /// invisible, which on an EDIT screen means uncorrectable and looks like
    /// the editor lost half the workout.
    ///
    /// So every movement in the report that the day does not already name is
    /// appended as a one-off prescription: its own working-set count, its top
    /// load as the seed, and its rep window when `Ceilings` has one. `movers`
    /// resolves from `MuscleMap` by name in `ProgramExercise.init`, so the card
    /// still gets its muscle bar and the session still gets its muscle credit.
    private func editorDay(_ report: SessionAnalysis.Report) -> ProgramDay? {
        guard !report.exercises.isEmpty else { return nil }
        let key = report.session.dayKey ?? ""
        // The deck that owned the session's date — its plan's `routines` rows.
        let program = (environment.targets?.schedule).map { Schedule.programForContext($0, report.session.date).program }
        var day = program?.day(key: key) ?? ProgramDay(
            key: key,
            label: SessionAnalysis.dayLabel(report.session.dayKey, in: program) ?? "Session",
            accent: 0x8A8A8E, weekday: 0, exercises: []
        )
        func normalised(_ name: String) -> String {
            ExerciseAliases.canonicalName(name).lowercased()
        }
        let planned = Dictionary(
            day.exercises.map { (normalised($0.name), $0) }, uniquingKeysWith: { first, _ in first }
        )

        // ── PERFORMED ORDER FIRST, THE REST OF THE PLAN AFTER ───────────────
        // The deck opens on `currentSet` — the first movement with an unticked
        // row — and on an edit that is whichever PROGRAMMED lift the session
        // skipped. So a person who tapped Edit to fix set 3 of the incline
        // press landed on a blank chest-press card and had to scroll past every
        // lift they did not do. A session's own order is the order it happened
        // in, which is the order its reader remembers it in.
        var ordered: [ProgramExercise] = []
        for exercise in report.exercises {
            if let existing = planned[normalised(exercise.canonical)] {
                ordered.append(existing)
                continue
            }
            let sets = max(1, Int(exercise.detail.workingSets))
            ordered.append(ProgramExercise(
                exercise.canonical,
                sets: sets,
                // Never nil and never 0: `cutSets == 0` drops the lift from the
                // deck on a cut, which is exactly the disappearance this whole
                // function exists to prevent.
                cutSets: sets,
                wk1Kg: exercise.stats.topKg > 0 ? exercise.stats.topKg : nil,
                // Already the programmed string when the ceilings table knows
                // this lift, and "" when it does not — `repWindow` reads "" as
                // no prescription, which is the truth about an off-plan lift.
                reps: exercise.window ?? "",
                restSec: 90
            ))
        }
        let covered = Set(ordered.map { normalised($0.name) })
        ordered += day.exercises.filter { !covered.contains(normalised($0.name)) }
        day.exercises = ordered
        return day
    }

    /// Whether the button is live.
    ///
    /// ── THE UNILATERAL GATE IS GONE, BECAUSE ITS REASON IS ──────────────────
    /// This refused any session holding an L/R pair, and said why: "the logger
    /// has no split concept — `LoggerModel.SetRow` carries no `side` and no
    /// `pairId`, and `snapshot` writes neither". Every clause of that has since
    /// stopped being true and the gate was never lifted with them:
    ///
    ///   · `SetRow` carries `side` and `pairId` (and `sideLabel` bridges the
    ///     mirror's `left`/`right` to the wire's `L`/`R`).
    ///   · `restoreLoggedSets` restores both — "a split set restores split".
    ///   · `snapshot` writes both back.
    ///   · `ExerciseState.volumeKg` routes every row through
    ///     `SessionVolume.sessionVolumeKg`, so the deck scores a pair at its
    ///     weaker side exactly as the save path does. The doubling this gate
    ///     was protecting against cannot happen.
    ///   · `LoggerModel.physical`/`groups` count a `pairId` once, and
    ///     `splitSet`/`mergeSet` are the deck's own controls for the pair.
    ///
    /// What the stale gate cost is the thing the user actually hit: every
    /// Delts & Arms session is a Single Arm Lateral Raise session, so the whole
    /// split was permanently uneditable — and the button gave a date-shaped
    /// symptom ("I cannot edit Tuesday's workout") for a laterality-shaped
    /// cause. There is no date restriction here and there never was one.
    ///
    /// What is left is the honest test: there has to be a deck to fold onto.
    /// `editorDay` now builds one for any session with movements in it, so this
    /// is nil only for a session that recorded no work at all.
    private var canEdit: Bool {
        guard let report else { return false }
        return editorDay(report) != nil
    }

    /// The phase this session was logged IN, not the one selected today.
    ///
    /// It decides which exercises the deck carries, and a cut deck opened on a
    /// bulk session simply would not contain the wrist curl the session holds —
    /// the rows are safe (nothing deletes what it cannot see) but they would be
    /// invisible and therefore uncorrectable. `PhaseKind` has four cases and
    /// `ProgramPhase` two: a peak and a deload are both run on the cut deck,
    /// which is what those weeks are.
    private var editorPhase: ProgramPhase {
        page?.week?.kind == .bulk ? .bulk : .cut
    }

    private func openEditor() {
        guard canEdit, let report, let day = editorDay(report) else { return }
        let session = report.session
        let model = LoggerModel(
            day: day,
            phase: editorPhase,
            store: environment.database,
            userId: environment.userIdString,
            startedAt: session.startedAt ?? Date(),
            // `day` above IS `editorDay`: the session's own performed order,
            // plus the plan movements it skipped. Saying so at construction is
            // what stops `LoggerModel` re-ranking it against another session's
            // deck order and prepending a warm-up nobody walked — see
            // `LoggerModel.openingForEdit`.
            openingForEdit: true
        )
        model.attach(editing: session)
        // A failed attach leaves no session on the model, and a deck with no
        // session would silently open a NEW one dated today on the first tick.
        // `ensureSession` refuses that, so the worst case is a deck that logs
        // nothing — but putting it on screen at all would be a lie.
        guard model.sessionId != nil else { return }
        editing = model
    }

    // MARK: - Hevy logged this too (W5; one line since W3)

    private func hevy(_ current: SessionAnalysis.Page, _ workout: WorkoutSample) -> some View {
        let session = current.report.session
        return HevyCompareCard(
            onyx: .init(
                avgBpm: current.avgBpm.map { Int(jsRound($0)) },
                kcal: current.calories.map { Int(jsRound($0)) },
                durationMin: session.durationMin.map { Int(jsRound($0)) },
                sets: current.report.physicalSets,
                bpmMeasured: current.avgBpm != nil && !current.avgBpmEstimated,
                kcalMeasured: current.calories != nil && !current.caloriesEstimated
            ),
            hevy: workout,
            onUse: { useHevy(current, workout) }
        )
    }

    /// The same write the finish sheet makes: adopted as the athlete's answer,
    /// stamped measured, Health untouched. Only what is not already measured —
    /// see the finish sheet.
    ///
    /// A method rather than the closure's body: `check:body` reads a store call
    /// lexically inside a `some View` builder as a read in `body`, and this was
    /// only ever let through by the `Task {` of the Skip closure above it,
    /// which went with the button (W3).
    private func useHevy(_ current: SessionAnalysis.Page, _ workout: WorkoutSample) {
        let bpmMeasured = current.avgBpm != nil && !current.avgBpmEstimated
        let kcalMeasured = current.calories != nil && !current.caloriesEstimated
        let bpm = bpmMeasured ? nil : workout.avgHr.map { Int(jsRound($0)) }
        let kcal = kcalMeasured ? nil : workout.activeKcal.map { Int(jsRound($0)) }
        _ = try? environment.database.setSessionMetrics(
            id: sessionId, userId: current.report.session.userId, avgBpm: bpm, caloriesBurned: kcal
        )
        Task { await environment.telemetry.setHevyDecision(sessionId: sessionId, .use) }
        withAnimation(OnyxMotion.fade) { foreign = nil }
        // `avg_bpm` is outside the door's WHEN clause (W2), so no
        // cascade will re-run the task: reload the page by hand.
        let database = environment.database, id = sessionId
        Task {
            page = await Task.detached(priority: .userInitiated) {
                SessionAnalysis.page(database: database, sessionId: id)
            }.value
        }
    }

    // MARK: - 1 · The masthead

    /// Row 1 — `SessionMasthead` through Lane B's shared `OnyxMasthead` face
    /// (the name wraps, never truncates; the figures shrink under it), on the
    /// split's day wash in a Stone slab.
    ///
    /// `page.program` — the deck that OWNED the session's date — names it, not
    /// the environment's active program: one session, one name, on every
    /// screen the reader moves between with a tap.
    private func masthead(_ page: SessionAnalysis.Page) -> some View {
        let label = SessionAnalysis.dayLabel(page.report.session.dayKey, in: page.program) ?? "Session"
        let session = page.report.session
        return OnyxMasthead(SessionMasthead(page: page, label: label), accent: Color.onyx.day(session.dayKey))
            .padding(OnyxSpace.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sessionDayWash(session.dayKey)
            .onyxGlass(.tile)
    }

    // MARK: - 3 · The exercise grid

    /// Two columns of chips until the type says otherwise, then one — the
    /// metric grid's own rule (`columns`) for the same reason.
    ///
    /// A `Grid`, not a `LazyVGrid`: a lazy grid sizes every cell to its own
    /// content, so a two-line name beside a one-line name drew two chips of
    /// different heights on one row (shot round 1). A `GridRow` gives both
    /// cells the row's height. Six movements is not a list worth lazing.
    private func exerciseGrid(_ report: SessionAnalysis.Report) -> some View {
        let perRow = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: report.exercises.count, by: perRow).map {
            Array(report.exercises[$0..<min($0 + perRow, report.exercises.count)])
        }
        return Grid(horizontalSpacing: OnyxSpace.s, verticalSpacing: OnyxSpace.s) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { ex in
                        ExerciseChip(exercise: ex, tint: Self.family(ex)) { ledgerFor = ex }
                    }
                    if row.count < perRow { Color.clear.gridCellUnsizedAxes(.vertical) }
                }
            }
        }
    }

    /// One movement's ledger card, in a sheet. The card is the one the page
    /// used to scroll through, unchanged; its record and trail sheets are
    /// presented from here.
    private func ledgerSheet(_ ex: SessionAnalysis.ExerciseReport) -> some View {
        NavigationStack {
            ScrollView {
                ledger(ex)
                    .padding(OnyxSpace.l)
            }
            .onyxScreen(.train)
            // No title: the card's own header names the movement, and a bar
            // title said it a second time 20 pt above it (shot round 1).
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { ledgerFor = nil }
                }
            }
            .sheet(item: $prSheet) { target in prRecordSheet(target) }
            .sheet(item: $trailSheet) { target in trailSheet(target) }
        }
        // At the accessibility sizes a half-height sheet holds the header and
        // not one set, so it opens full height.
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }

    private func prRecordSheet(_ target: PrTarget) -> some View {
        PrRecordSheet(
            exerciseName: target.exercise,
            setLabel: target.setLabel,
            records: target.records,
            timed: target.timed
        )
    }

    // MARK: - 5 · Progression

    /// Row 5's sheet: the split's tonnage line, then every figure of the
    /// session with its comparison — the metric grid that used to sit under
    /// the masthead. Deltas live here and in the ledger's tinted numerals,
    /// not on the first screen (concept 6).
    private func progressionSheet(_ page: SessionAnalysis.Page) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OnyxSpace.m) {
                    progression(page)
                    metrics(page)
                }
                .padding(OnyxSpace.l)
            }
            .onyxScreen(.train)
            .navigationTitle("Progression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showProgression = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 2 · The metric grid

    /// Six figures in one 3×2 grid, each with a reserved line under it and
    /// eight weeks of itself behind it.
    ///
    /// ── IT WAS A 3-UP OVER A 4-UP, AND THE SEAM WAS VISIBLE ─────────────────
    /// Seven readings split across two grids of different column counts, so the
    /// cells in the top row were 117 pt and the ones under them 84 pt — two
    /// tables about one session, with the four narrow cells breaking their own
    /// labels ("Difficu…") at exactly the width the split created. Volume was
    /// the first of the seven and is now the masthead's hero figure, which
    /// leaves SIX: one grid, one column width, one table.
    ///
    /// ── WHY THE SECOND LINE IS STILL ALWAYS THERE ───────────────────────────
    /// §3.6: "every number has a unit and a reserved delta line". A delta that
    /// appears only when there is one to show makes the whole grid change
    /// height between two sessions, and a cell that is silent about its
    /// comparison is indistinguishable from one that has none. `OnyxStatCell`
    /// reserves it; what changed is that the two cells whose line said
    /// "measured" or "estimated" — a restatement of provenance, not a
    /// comparison — now say it to VoiceOver only, and their trail says the
    /// thing the line was taking up room to not say.
    private func metrics(_ page: SessionAnalysis.Page) -> some View {
        let report = page.report
        return VStack(spacing: OnyxSpace.grid) {
            LazyVGrid(columns: columns(3), spacing: OnyxSpace.grid) {
                // ── THE GLYPHS AND THE HUES ARE THE ONES THE APP ALREADY OWNS ──
                // `OnyxInk.Fixed.heart` for a heart rate and `Color.onyx.calories`
                // for a burn is what the Live Stats card has drawn since U3, so
                // the screen you finish on and the screen you review say the
                // same two readings in the same two colours. Nothing new is
                // spent here: effort takes `Color.onyx.effort` and records take
                // the record gold — every one of them a function that already
                // exists because something else asks it the same question.
                OnyxStatCell(
                    "Duration", report.session.durationMin.map { jsIntegerString(jsRound($0)) } ?? "—",
                    unit: "min", sub: delta(page.durationDelta, unit: "min", higherIsBetter: nil),
                    spark: page.trail { $0.durationMin }
                )
                // ── EVERY SET PERFORMED, NOT THE WORKING ONES ──────────────
                // `Report.sets` sums `workingSets`, so a session that opened
                // with a treadmill bout and a leg-press warm-up headlined 20
                // for 22 rows — while the muscle card one screen down read the
                // same session as 22 (`physicalSets`, which is what weighted
                // sets are counted against). Two set counts on one page.
                //
                // `physicalSets` is the honest headline: its own doc comment is
                // "every set that was performed, ghosts excluded, a unilateral
                // pair counted once", which is what the word Sets means to
                // somebody who has just done them. The composition line under
                // it — `3 warm-up · 1 drop` — is what says how many were which,
                // and it is why the bigger number does not mislead.
                //
                // The TRAIL behind it is `Summary.sets`, which counts working
                // sets — one scale below the figure it sits under. That is the
                // right trade and not an oversight: the curve is a shape, not a
                // reading, and the alternative is replaying every session of
                // the split through `physicalSets` to draw eight points.
                OnyxStatCell(
                    "Sets", "\(report.physicalSets)",
                    sub: composition(report) ?? delta(page.setsDelta.map(Double.init), unit: "", higherIsBetter: true),
                    spark: page.trail { Double($0.sets) }
                )
                OnyxStatCell(
                    "Difficulty", report.session.sessionRpe.map { "\(OnyxFormat.rpe($0))/10" } ?? "—",
                    sub: .init(report.session.sessionRpe.map { Effort.rpeLabel($0) } ?? "not rated", Color.onyx.textTertiary),
                    // An unrated session takes no colour: `effort(_:)` starts
                    // at secondary ink and only leaves it when the work was
                    // genuinely hard, and a grey dash tinted amber would be a
                    // verdict on a reading nobody gave.
                    tint: report.session.sessionRpe.map { Color.onyx.effort($0) },
                    spark: page.trail { $0.sessionRpe }
                )
                OnyxStatCell(
                    "Records", "\(report.prCount)", sub: recordsDelta(page),
                    tint: report.prCount > 0 ? Color.onyx.record : nil,
                    // Only when there is one. A permanent trophy over a zero is
                    // how gold stops meaning a personal record — the same rule
                    // the Lock Screen card's `N PR` already follows.
                    symbol: report.prCount > 0 ? "trophy.fill" : nil,
                    spark: page.trail { Double($0.prCount) }
                )
                // `sub: nil` on both of these, and the provenance moved into
                // `detail` — see the type header. "measured" is not a
                // comparison, and it was taking the line a comparison lives on.
                avgHr(page)
                OnyxStatCell(
                    "Calories", page.calories.map { jsIntegerString($0) } ?? "—",
                    unit: page.calories == nil ? nil : "kcal",
                    tint: page.calories == nil ? nil : Color.onyx.calories, symbol: "flame.fill",
                    spark: page.trail { $0.calories }, detail: basis(page)
                )
            }
            IntensityBar(values: report.intensity)
        }
    }

    /// The Avg HR reading, in the fixed heart red (overhaul Q19). It used to
    /// open the chart panel; the chart is the page's inline strip now.
    private func avgHr(_ page: SessionAnalysis.Page) -> some View {
        OnyxStatCell(
            "Avg HR", page.avgBpm.map { jsIntegerString($0) } ?? "—",
            unit: page.avgBpm == nil ? nil : "bpm",
            tint: page.avgBpm == nil ? nil : OnyxInk.Fixed.heart,
            symbol: "heart.fill",
            spark: page.trail { $0.avgBpm }, detail: bpmBasis(page)
        )
    }

    /// Three or four across until the type says otherwise, then ONE.
    ///
    /// Two columns at AX5 was tried and is worse than one: a half-width cell at
    /// that size holds "5,1…" and "DURAT…", so the grid keeps its shape and
    /// loses every value in it. A tall column of seven legible cells is what the
    /// setting was turned on for.
    private func columns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.grid),
              count: typeSize.isAccessibilitySize ? 1 : count)
    }

    /// The sub-line, now `OnyxUI`'s (§W2 C). A typealias rather than a rename
    /// at forty call sites: the shape is identical and always was, which is the
    /// whole reason the two squares merged.
    private typealias Sub = OnyxStatCell.Sub

    /// A signed change, in the ink of what it means — or the honest absence.
    ///
    /// Overhaul Q14: better is the theme's accent and worse is quiet ink, the
    /// ledger's own rule (`SetRow.deltaInk`) — no green, no red.
    ///
    /// `higherIsBetter: nil` for duration: a session that took twelve minutes
    /// less is not worse and not better, it is shorter, and painting it red
    /// would be the app inventing a verdict it does not hold.
    private func delta(_ value: Double?, unit: String, higherIsBetter: Bool?) -> Sub {
        guard let value else { return Sub("first of this split", Color.onyx.textTertiary) }
        guard abs(value) >= 0.5 else { return Sub("level", Color.onyx.textTertiary) }
        let sign = value > 0 ? "+" : "−"
        let text = "\(sign)\(OnyxFormat.volume(abs(value)))\(unit.isEmpty ? "" : " \(unit)")"
        guard let higherIsBetter else { return Sub(text, Color.onyx.textSecondary) }
        return Sub(text, SetRow.deltaInk(value, upIsGood: higherIsBetter) ?? Color.onyx.textSecondary)
    }

    /// `3 warm-up · 1 drop` — what the set count is made of.
    ///
    /// It takes the sub-line from the delta when there is anything to say,
    /// because a total of 17 that includes three warm-ups and a drop set is a
    /// number the reader will otherwise mistrust, and mistrust costs more than
    /// a comparison does.
    private func composition(_ report: SessionAnalysis.Report) -> Sub? {
        var counts: [String: Int] = [:]
        for exercise in report.exercises {
            for set in exercise.detail.sets where !SetTags.isWorkingSet(set.setType) {
                counts[set.setType, default: 0] += 1
            }
        }
        let entries = SetTags.composition(counts)
        guard !entries.isEmpty else { return nil }
        return Sub(entries.map { "\($0.count) \($0.full.lowercased())" }.joined(separator: " · "), Color.onyx.textTertiary)
    }

    /// Where the calorie figure came from — and it is the sub-line, not a
    /// superscript, that carries it now (see `cell`).
    ///
    /// "measured" is a word this cell could not say before: `Page.calories` was
    /// always an estimate, so the mark over it was always `calc`, including on
    /// the sessions the watch had actually measured.
    private func basis(_ page: SessionAnalysis.Page) -> String {
        guard page.calories != nil else { return "no data" }
        guard page.caloriesEstimated else { return "measured" }
        switch page.calorieBasis {
        case .personalMedian: return "your median"
        case .metFormula, nil: return "estimated"
        }
    }

    private func bpmBasis(_ page: SessionAnalysis.Page) -> String {
        guard page.avgBpm != nil else { return "no data" }
        return page.avgBpmEstimated ? "estimated" : "measured"
    }

    /// Records against the previous session of this split. It is the reserved
    /// delta line doing its job: "9" alone is a number, "9, +2" is a session.
    private func recordsDelta(_ page: SessionAnalysis.Page) -> Sub {
        guard let previous = page.previous else { return Sub("first of split", Color.onyx.textTertiary) }
        let change = page.report.prCount - previous.prCount
        if change == 0 { return Sub("same as last", Color.onyx.textTertiary) }
        return Sub(change > 0 ? "+\(change)" : "−\(-change)",
                   SetRow.deltaInk(Double(change), upIsGood: true) ?? Color.onyx.textSecondary)
    }

    // MARK: - 3 · Progression

    private func progression(_ page: SessionAnalysis.Page) -> some View {
        OnyxChartCard(
            "Progression", domain: .train,
            headline: "\(OnyxFormat.volumeExact(page.report.tonnageKg)) kg",
            caption: page.verdict,
            // Only when the window holds one. A legend for a state nothing is
            // in is a line of chrome explaining nothing.
            legend: page.split.contains(where: \.isMaintenance)
                ? AnyView(MaintenanceLegend(symbol: .point)) : nil
        ) {
            if page.split.count >= 2 {
                SplitVolumeChart(points: page.split, current: page.report.session.id, tint: split)
            } else {
                OnyxChartEmpty("One session on this split so far. The line starts at two.")
            }
        }
    }

    // MARK: - The ledger card (row 3's sheet)

    /// ── ONE CARD PER MOVEMENT, NOT THREE STACKED SURFACES ───────────────────
    /// This was a `Section`: a tinted header row, a separate dark card of sets,
    /// and a loose row of capsules floating under it. Three surfaces for one
    /// subject — and the capsules, which are the movement's OWN totals, sat
    /// below its sets, where they read as belonging to whatever came next.
    ///
    /// The header, the readings and the evidence are now one card: the tinted
    /// band says what the movement was and what it produced, the rows under it
    /// are the sets it produced it with. Which also gives the page the one
    /// thing the `Section` shape could not — a single edge per movement to
    /// scroll past, rather than a header, a gap, a card, a gap and a tag row.
    private func ledger(_ ex: SessionAnalysis.ExerciseReport) -> some View {
        let family = Self.family(ex)
        let assist = Self.assisting(ex.canonical)
        // Asked ONCE, here, and handed to the heading and to every row — see
        // `SetRow.SetLayout` for why this is not a per-row decision.
        let layout = SetRow.layout(ex)
        // ── THE RESERVATION IS A CARD'S DECISION, NOT A ROW'S (§W2 F) ───────
        // §3.6 reserves the delta line so a row cannot change height between
        // two sessions — which is the right rule and says nothing about a
        // movement that has NEVER been trained before. On a first-ever card
        // every one of three columns on every row reserved a line for a
        // comparison that cannot exist: 11 pt × N sets of guaranteed blank,
        // on the one card where there is nothing to compare and never was.
        //
        // Asked ONCE per card, like `layout`: within a card the reservation is
        // unchanged, so the height still cannot move between two sessions of a
        // movement that HAS a history — which is the property the rule is for.
        let comparable = ex.rows.contains {
            Self.previousSet(ex, row: $0) != nil || Self.previousUnitVolume(ex, row: $0) != nil
        }
        // ── THE RESTS, IN ROW ORDER, SO THE DELTA IS THE CARD'S TO COMPUTE ──
        // The same division of labour `prevUnitKg` already states: the row
        // draws a reading, the CARD decides what that reading is measured
        // against. A row cannot know what the row above it rested, and passing
        // it the whole card so it could look would be handing every row the
        // card's own job.
        //
        // Keyed off the row's LEAD set (`set ?? left`), because a unilateral
        // pair is two sets under one row and both sides are performed inside
        // one rest — the left side's `set_index` is the one the gap was
        // clocked before.
        let rests: [Int?] = ex.rows.map { row in
            (row.set ?? row.left ?? row.right).flatMap { ex.rest[Int($0.setNumber)] }
        }
        return VStack(alignment: .leading, spacing: 0) {
            ledgerHeader(ex, family: family)
            if !layout.heads.isEmpty, !typeSize.isAccessibilitySize {
                columnHeads(layout)
            }
            ForEach(Array(ex.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider()
                        .overlay(Color.onyx.hairline)
                        // Inset to the value column, the way a `List` insets a
                        // separator: a rule that runs under the badge column
                        // cuts the ordinals off from their own sets.
                        .padding(.leading, OnyxSpace.l)
                }
                SetRow(
                    row: row, timed: ex.timed, tint: family,
                    // The records this row's set(s) won. A pair is two sets
                    // under one row and either side can be the one that
                    // completed it, so both are asked and the answers join.
                    records: [row.set, row.left, row.right]
                        .compactMap { $0 }
                        .flatMap { ex.records[Int($0.setNumber)] ?? [] },
                    onInspect: { records in
                        prSheet = PrTarget(exercise: ex.canonical, timed: ex.timed,
                                           setLabel: row.num.map { "Set \($0)" } ?? "Warm-up set",
                                           records: records)
                    },
                    // Set 3 against set 3, and nothing at all when there is no
                    // set 3 to compare with — see `SetRow.prev`.
                    prev: Self.previousSet(ex, row: row),
                    // The same row's worth last time, pairs folded — the one
                    // comparison a unilateral set can honestly carry.
                    prevUnitKg: Self.previousUnitVolume(ex, row: row),
                    position: index + 1,
                    layout: layout,
                    // Whether ANY row on this card has a counterpart — see
                    // `comparable` above.
                    cardComparable: comparable,
                    restSec: rests[index],
                    // Against the row ABOVE on this card, and nothing else. Not
                    // against the plan: `plan.restSec` is a prescription this
                    // page has no business grading a finished session by, and
                    // not against the previous session either — rests are not
                    // positionally comparable the way loads are, because a
                    // movement's set count moves between weeks.
                    restDeltaSec: index > 0
                        ? rests[index].flatMap { current in rests[index - 1].map { current - $0 } }
                        : nil,
                    marginHeld: holdMargins
                )
            }
        }
        .onyxGlass(.tile)
        // AFTER the glass: the wash is the card's own material showing through,
        // not a panel floating on it. Header and rows are inside one modified
        // view here, which is the whole point — see `OnyxMuscleWash`.
        .onyxMuscleWash(family, secondary: assist)
    }

    /// The table's column heads — `KG · REPS · RPE`, or `MIN · KM · PACE`.
    ///
    /// ── WHY THE UNITS MOVED OUT OF THE ROWS ─────────────────────────────────
    /// Every row used to carry its own: `42.5kg × 10`. Said once at the top of
    /// the card it costs one 11 pt line and buys back a unit's width on every
    /// row beneath it — which is where the width for a third column came from.
    ///
    /// Built from the same `SetLayout` the rows are, with the same gutter and
    /// the same `.frame(maxWidth: .infinity)` tracks, so a heading cannot come
    /// to sit off the numbers it names. `Color.clear` rather than a `Spacer`
    /// for the badge's gutter: a `Spacer` in a row of flexible children takes a
    /// share of the width instead of a fixed 28 pt.
    ///
    /// Absent at the accessibility sizes, where the rows are not a table.
    private func columnHeads(_ layout: SetRow.SetLayout) -> some View {
        HStack(spacing: OnyxSpace.s) {
            Color.clear.frame(width: SetRow.badgeSide, height: 0)
            ForEach(layout.heads, id: \.self) { head in
                Text(head)
                    .onyxMicro()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, OnyxSpace.l)
        .padding(.bottom, OnyxSpace.xs)
        // The row it heads speaks its own columns by name (`SetRow.spoken`),
        // so reading these aloud first would name every column twice.
        .accessibilityHidden(true)
    }

    /// The same set number, the last time this movement was trained.
    ///
    /// `previousSets` is that session's WORKING sets, and `row.num` is this
    /// row's working ordinal — so the two index each other directly and a
    /// warm-up (no ordinal) has nothing to be compared with, which is correct:
    /// a ramp-up set is not a performance.
    ///
    /// A pair is refused rather than guessed at. Two rows per set means the
    /// previous session's list holds two entries per ordinal, and picking one
    /// of them would compare this week's whole set against one of last week's
    /// arms.
    private static func previousSet(
        _ ex: SessionAnalysis.ExerciseReport, row: DetailRow
    ) -> HistorySet? {
        guard row.kind != "pair", let num = row.num, num > 0,
              ex.previousSets.count >= num
        else { return nil }
        return ex.previousSets[num - 1]
    }

    /// What the same row was worth the last time this movement was trained, in
    /// kilograms — a pair folded to one unit.
    ///
    /// ── A PAIR IS ONE UNIT ON BOTH SIDES OF THE COMPARISON ──────────────────
    /// `previousSet(_:row:)` one function up refuses a pair and says why: for a
    /// split movement the previous session's flat list holds TWO entries per
    /// ordinal, so indexing it by `row.num` compares this week's whole set
    /// against one of last week's arms. The answer is not to give up on the
    /// comparison, it is to fold the previous session the way
    /// `SessionDetail.toRows` folds this one — a `pairId` is one unit — and
    /// then index by ordinal, which is what the two lists have always had in
    /// common.
    ///
    /// Warm-ups have no ordinal on either side and are skipped by the same
    /// guard, which is correct: a ramp-up set is not a performance.
    /// Internal since W4 — this fold IS the pair comparison, and it is the
    /// half of it that can be wrong without anything failing to build.
    static func previousUnitVolume(
        _ ex: SessionAnalysis.ExerciseReport, row: DetailRow
    ) -> Double? {
        guard let num = row.num, num > 0 else { return nil }
        var units: [[HistorySet]] = []
        var byPair: [String: Int] = [:]
        for set in ex.previousSets {
            // A pairId with no side, or a side with no pairId, is an ordinary
            // set — the same test `SessionVolume` makes before it collapses
            // anything, so the two cannot come to disagree about what a pair is.
            if let pairId = set.pairId, !pairId.isEmpty {
                if let index = byPair[pairId] {
                    units[index].append(set)
                    continue
                }
                byPair[pairId] = units.count
            }
            units.append([set])
        }
        guard units.count >= num else { return nil }
        return SessionVolume.sessionVolumeKg(units[num - 1].map {
            VolumeSet(weightKg: $0.weightKg, reps: $0.reps,
                      side: $0.side, pairId: $0.pairId, setType: $0.setType)
        })
    }

    /// The header IS the exercise's report: what the movement is FOR, what was
    /// prescribed, how much of it landed on the ceiling, and what it produced.
    /// The rows underneath are the evidence.
    ///
    /// The DRAWING is `LedgerHeader`, below, because it now holds state — the
    /// muscle chip is a control. This is the derivation, which is the half that
    /// needs the page.
    private func ledgerHeader(_ ex: SessionAnalysis.ExerciseReport, family: Color) -> some View {
        let domain = MuscleGroup.forExercise(ex.canonical).domain
        let all = movers(ex.canonical)
        let tags = headerTags(ex, domain: domain, family: family)
        return LedgerHeader(
            name: ex.canonical,
            window: ex.window,
            spark: ex.spark,
            family: family,
            primary: all.filter(\.primary),
            secondary: all.filter { !$0.primary },
            brief: tags.brief,
            results: tags.results,
            seededOpen: startWithAssists,
            // Nil when there is nothing a chart could say that the sparkline
            // has not. `E1rmTrendChart` plots points and a `LineMark` between
            // two of them is the sparkline again with an axis bolted on, so the
            // door only exists from three sessions up — which is also where
            // `Sparkline` itself stops being a wobble.
            onTrail: ex.trail.count >= 3
                ? { trailSheet = TrailTarget(exercise: ex.canonical, points: ex.trail) }
                : nil
        )
    }

    /// The trail, plotted. Named `trailSheet(_:)` rather than built inline so
    /// the `.sheet` above stays a line.
    private func trailSheet(_ target: TrailTarget) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OnyxSpace.m) {
                    E1rmTrendChart(
                        series: [SessionAnalysis.TrailSeries(id: target.exercise, points: target.points)]
                    )
                    .frame(height: 220)
                    Text("Each point is that session's mean estimated one-rep max for this movement — the same figure the sparkline draws, with the dates it was measured on.")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(OnyxSpace.l)
            }
            .onyxScreen(.train)
            .navigationTitle(target.exercise)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { trailSheet = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Primary and assisting movers, deduped, capped at what a 375 pt line
    /// holds. `MuscleMap` is the same source the atlas, the ramp and the legend
    /// on this page read, so a lift's chips and its share of the body cannot
    /// disagree.
    ///
    /// The secondaries exclude anything already trained DIRECTLY, for the
    /// reason `ExerciseDetailView` states: several map tokens fold onto one
    /// landmark, so a wide-grip row would otherwise print "Upper back" twice —
    /// once as a primary and once as an assist — and read as double credit that
    /// `MuscleCredit` never gives.
    private func movers(_ canonical: String) -> [Mover] {
        // ── THE AX5 CAP IS GONE (§W2 E) ─────────────────────────────────────
        // It was 1 at the accessibility sizes and 3 otherwise, because a chip
        // was a LINE there: three of them meant three lines of "also worked"
        // above the numbers the reader came for. The assists do not share a row
        // with anything any more — they are row 2's other state, behind the
        // chip's own `+N` — so at AX5 the cap was no longer buying a line, it
        // was removing the feature from exactly the readers who most need a
        // card that is not three screens tall.
        //
        // Three stays, at every size, and it is the same three the READINGS row
        // holds (tonnage, top set, effort). That is what keeps the swap free:
        // two states with the same number of capsules wrap to the same number
        // of lines, so the card cannot change height when it is tapped.
        let limit = 3
        // ── AND A BOUT NAMES MUSCLES TOO (W4 · F6) ──────────────────────────
        // `MuscleMap.dict` holds no cardio entry and must not: it is the input
        // to `MuscleCredit.weightedSets`, and therefore to the weekly MEV/MAV
        // accumulator, the Freshness Map and — through the battery — the
        // readiness score. A treadmill that started paying muscle credit would
        // move five numbers nobody asked to move, and break two golden
        // fixtures on the way. So the chips fall back to `cardioMovers`, a
        // DISPLAY table that reaches nothing else; its own header states the
        // separation. A movement the lift table already knows can never reach
        // it, which is what makes the fallback safe to ask unconditionally.
        let primary = MuscleMap.primaryLandmarks(canonical)
        let secondary = MuscleMap.secondaryLandmarks(canonical)
        let leads = primary.isEmpty && secondary.isEmpty
            ? MuscleMap.cardioPrimaryLandmarks(canonical) : primary
        let assists = primary.isEmpty && secondary.isEmpty
            ? MuscleMap.cardioSecondaryLandmarks(canonical) : secondary
        var seen = Set<LandmarkMuscle>()
        var out: [Mover] = []
        for muscle in leads where seen.insert(muscle).inserted {
            out.append(Mover(name: muscle.displayName, primary: true))
        }
        for muscle in assists where seen.insert(muscle).inserted {
            guard out.count < limit else { break }
            out.append(Mover(name: muscle.displayName, primary: false))
        }
        return out
    }


    /// The hue of the movement's FIRST primary mover — the same key
    /// `Color.onyx.muscle` uses everywhere else on this page. Falls back to the
    /// six-group accent when the map has no answer, which is honest: an
    /// unmapped movement has no family to be tinted by.
    private static func family(_ canonical: String) -> Color {
        guard let landmark = MuscleMap.primaryLandmarks(canonical).first else {
            return MuscleGroup.forExercise(canonical).domain.accent
        }
        return Color.onyx.muscle(landmark)
    }

    /// The same question, asked of a movement whose ROWS are known.
    ///
    /// A bout has no primary mover — `MuscleMap` holds no cardio entry, because
    /// a treadmill is not a lift — so the name-only answer above fell through
    /// to `MuscleGroup.other`, whose domain is `.recover`: the exact lavender
    /// Abs/core wears. A treadmill and a crunch drew the same rail. The rows
    /// are what say it is a bout (`SetFormat.cardio`, the same test the deck's
    /// `SetRow.isCardio` makes), and `Color.onyx.cardio` is the answer the deck
    /// and the cardio sheet already give.
    /// Internal since W4 — `SessionTableTests` holds the cardio fallback.
    static func family(_ ex: SessionAnalysis.ExerciseReport) -> Color {
        let cardio = ex.rows.contains { row in
            [row.set, row.left, row.right].compactMap { $0 }.contains { set in
                SetFormat.cardio(
                    durationSec: set.durationSec, distanceKm: set.distanceKm,
                    incline: set.incline, elevationM: set.elevationM
                ) != nil
            }
        }
        if cardio, MuscleMap.primaryLandmarks(ex.canonical).first == nil {
            return Color.onyx.cardio
        }
        return family(ex.canonical)
    }

    /// The assisting hue — the bottom half of the card's rail.
    ///
    /// Nil rather than a fallback when a movement has no secondary mover: the
    /// rail then draws solid, and a gradient into an invented colour would be
    /// the rail asserting a muscle the movement does not train.
    private static func assisting(_ canonical: String) -> Color? {
        MuscleMap.secondaryLandmarks(canonical).first.map { Color.onyx.muscle($0) }
    }

    /// The readings that used to be one grey sentence (§U4.3), and since W4 the
    /// second half of the ONE flow row the header now has — the muscle chips
    /// lead it, these follow (A4).
    ///
    /// Two carry colour and the rest are facts. The COMPARISON — this
    /// movement's tonnage against the last time it was trained — is the one
    /// reading here that holds a verdict; `higherIsBetter` is unambiguous in a
    /// way it is not for duration, because more work on the same lift is more
    /// work. It is LAST since W4, after the evidence it is computed from. The
    /// CUE is the other tinted item, and it is an instruction rather than a
    /// reading, which is why it sits immediately before the verdict and in the
    /// domain's own accent.
    /// Everything this movement PRODUCED, in one row of capsules — and every
    /// one of them in a colour that means something.
    ///
    /// ── THE ROW WAS GREY, AND GREY IS A COLOUR WITH NO ARGUMENT ─────────────
    /// Five readings in identical hairline capsules: the reader had to parse
    /// all five to find any one, and the row looked the same on a session that
    /// went up as on one that went down. Each capsule now takes the token that
    /// already MEANS its reading somewhere else in the app, so nothing new is
    /// spent and nothing is decoration:
    ///
    ///  · the verdict    → `good` / `danger`, the two colours a delta has
    ///  · Top            → the movement's own muscle hue, the same one the
    ///                     card's rail, wash, chips and sparkline take
    ///  · Volume         → the verdict again, because tonnage IS what the
    ///                     verdict is computed from — one claim, stated where
    ///                     it is made and again where it is measured
    ///  · RPE            → `Color.onyx.effort`, the ramp the effort picker and
    ///                     the intensity bar already draw
    ///  · the ceiling    → secondary ink; it is a count, not a judgement
    ///
    /// ── AND WHY THE READINGS STILL READ AS A GROUP ──────────────────────────
    /// They shared a `VStack` with the chips until W4 and now share a line with
    /// them, which sounds like the hierarchy collapsing and is not: a chip is a
    /// dot and a name in the movement's hue, a reading is a capsule with a
    /// glyph and a number in its own. The two are told apart by SHAPE, which
    /// survives being adjacent; they were told apart by POSITION, which cost a
    /// line of the card to say.
    /// ── TWO ROWS, AND WHICH READING BELONGS ON WHICH (§W2 E) ────────────────
    /// They were one `FlowRow` of everything, so the wrap point moved with the
    /// text size and no reading had a place — `RPE 8.0` was on line one on one
    /// card and line two on the next. The split is by REGISTER and not by
    /// width:
    ///
    ///  · `brief`   — what was asked of this movement and how it went against
    ///                the last time: the progression percentage, how much of
    ///                the prescription landed inside its window, and the cue.
    ///  · `results` — what it produced today: tonnage, top set, effort. On a
    ///                BOUT every one of those is guarded off (a treadmill
    ///                carries no load and an imported walk is unrated), so the
    ///                bout's own readings take the row instead — which is why
    ///                `cardioTags` leads the results and not the brief.
    ///
    /// The row each one lands on is therefore the same on every card, at every
    /// text size, which is what "two deterministic rows" means.
    private func headerTags(
        _ ex: SessionAnalysis.ExerciseReport, domain: OnyxDomain, family: Color
    ) -> (brief: [MetaTagRow.Tag], results: [MetaTagRow.Tag]) {
        // A BOUT'S OWN READINGS FIRST, where a lift's would be. See
        // `cardioTags` — on a treadmill every capsule below this line is
        // guarded off, and the row came out empty.
        var results: [MetaTagRow.Tag] = Self.cardioTags(ex, bout: page?.bout)
        var brief: [MetaTagRow.Tag] = []
        // "Top" is a claim about the WORKING sets, so an exercise that has none
        // does not get to make it. It used to print `Top 0 reps` — the same lie
        // as `0kg × 0` — on any all-warm-up movement, which the treadmill block
        // is by construction.
        if ex.stats.topKg > 0 || ex.stats.topReps > 0 {
            results.append(.init(
                "Top " + SetFormat.format(weightKg: ex.stats.topKg, reps: ex.stats.topReps, timed: ex.timed),
                symbol: "arrow.up.to.line",
                tint: family
            ))
        }
        // And tonnage is the same kind of claim. `0 kg` beside a treadmill — or
        // beside a reverse crunch, which has been printing it far longer — is
        // not a small number, it is a category error: the movement carries no
        // load, so there is no tonnage to be zero of. The pill is absent rather
        // than zero, exactly as "Top" is one line above.
        if ex.detail.volumeKg > 0 {
            results.append(.init(
                "\(OnyxFormat.volume(ex.detail.volumeKg)) kg",
                symbol: "scalemass.fill",
                tint: volumeTone(ex)
            ))
        }
        if let rpe = ex.stats.avgRpe {
            results.append(.init("RPE \(jsToFixed1(rpe))", symbol: "bolt.fill", tint: Color.onyx.effort(rpe)))
        }
        // How much of the prescription landed inside its window. The window
        // itself has moved up beside the movement's name — this is the half
        // that is a RESULT, and results live here.
        if let window = ex.window {
            brief.append(.init(
                "\(ex.atCeiling)/\(Int(ex.detail.workingSets)) @ \(window)",
                symbol: "target",
                tint: Color.onyx.textSecondary
            ))
        }
        if let cue = ex.cue { brief.append(.init(cue.short, tint: domain.accent)) }
        // ── THE VERDICT LEADS THE BRIEF, AND CARRIES ITS OWN MAGNITUDE ─────
        // It led this list until W4, for a reason that was true of the row it
        // used to live on: five capsules do not fit 402 pt, so one wrapped, and
        // it was this one — alone on a second line at the far left, the only
        // tinted item on the row, reading as an orphan rather than as the
        // conclusion.
        //
        // The row it lives on now OPENS with the movement's muscle chips in
        // the movement's own colour (A4), so being tinted no longer makes it
        // the odd one out and it no longer needs the first slot to be found.
        // A conclusion belongs after the evidence it is drawn from, and this
        // capsule is computed from the tonnage capsule two along.
        //
        // It used to read `vs 30 Aug`, which spent the capsule on a DATE — the
        // half of the fact the reader could not use, thirty seconds after
        // finishing the session. The arrow says the direction and the
        // percentage says how far; the date lives on the session it names.
        if let previous = previousVolume(ex), previous > 0 {
            let percent = (ex.detail.volumeKg - previous) / previous * 100
            // Under half a percent there is no arrow: a triangle over a
            // rounding error is noise with a direction.
            if abs(percent) < 0.5 {
                brief.insert(.init("level", tint: Color.onyx.textTertiary), at: 0)
            } else {
                brief.insert(.init(
                    "\(percent > 0 ? "+" : "−")\(jsIntegerString(jsRound(abs(percent))))%",
                    tint: SetRow.deltaInk(percent, upIsGood: true) ?? Color.onyx.textSecondary
                ), at: 0)
            }
        }
        // The verdict LEADS the brief (it is inserted at 0 above): the row now
        // opens with the movement's own muscle chip, so a tinted capsule beside
        // it is no longer the odd one out, and "how did this go" is the first
        // thing asked of a card you are scrolling past.
        return (brief, results)
    }

    /// A bout's own readings — distance, pace, heart rate, and where the row
    /// came from.
    ///
    /// ── THE TREADMILL CARD WAS NEVER A VIEW; IT WAS SIX ABSENCES (F6) ───────
    /// There is no cardio branch anywhere in `ledger(_:)` and there never was.
    /// What made the card look broken is that all five capsules below it are
    /// guarded off on a bout — Top and Volume because a treadmill carries no
    /// load, RPE because an imported bout is unrated, the ceiling because
    /// nothing prescribes a walk, and the verdict because the previous volume
    /// is zero — so `MetaTagRow(tags: [])` drew an empty row and the card said
    /// nothing at all about the only thing on it.
    ///
    /// ── WHERE EACH FIGURE COMES FROM, AND WHY ───────────────────────────────
    /// Distance and pace are summed from the card's OWN rows — the same
    /// `duration_sec` and `distance_km` columns the `MIN · KM · PACE` table
    /// underneath reads, through the same `CardioMetrics` call — so the header
    /// and the rows cannot come to disagree about the bout they both describe.
    ///
    /// Heart rate and provenance cannot: `workout_sets` has no heart-rate
    /// column and no "where did this come from" column, and it is not growing
    /// one for a caption. They come from the `cardio_logs` row FILED AGAINST
    /// this session (`Page.bout`), which is the only place either fact is
    /// stored — and which is nil for a bout typed straight into the deck, in
    /// which case the two capsules are simply absent rather than guessed.
    static func cardioTags(
        _ ex: SessionAnalysis.ExerciseReport, bout: CardioLogRow?
    ) -> [MetaTagRow.Tag] {
        let sets = ex.rows.flatMap { [$0.set, $0.left, $0.right].compactMap { $0 } }
        guard sets.contains(where: SetRow.isCardio) else { return [] }
        var tags: [MetaTagRow.Tag] = []
        let km = sets.compactMap(\.distanceKm).reduce(0, +)
        let minutes = sets.compactMap(\.durationSec).reduce(0, +) / 60
        if km > 0 {
            tags.append(.init("\(jsIntegerString(km)) km",
                              symbol: "figure.run", tint: Color.onyx.cardio))
        }
        let pace = CardioMetrics.formatPace(CardioMetrics.paceMinPerKm(
            distanceM: km > 0 ? km * 1000 : nil,
            durationMin: minutes > 0 ? minutes : nil
        ))
        // `formatPace` answers the em-dash for anything it cannot divide, and a
        // capsule holding an em-dash is the empty row again in one object.
        if pace != "—" {
            tags.append(.init(pace, symbol: "speedometer", tint: Color.onyx.cardio))
        }
        if let bpm = bout?.avgHr, bpm > 0 {
            tags.append(.init("\(jsIntegerString(jsRound(bpm))) bpm",
                              symbol: "heart.fill", tint: OnyxInk.Fixed.heart))
        }
        // The app's own glyph for "this came from Apple Health" — the same one
        // the weigh-in sheet's fill button wears.
        if bout?.fromHealthkit == true {
            tags.append(.init("Automatically logged",
                              symbol: "heart.text.square", tint: Color.onyx.textSecondary))
        }
        return tags
    }

    /// Accent up, quiet down, plain when there is nothing to compare against
    /// (overhaul Q14) — the tonnage capsule's own colour, computed from the
    /// same two numbers the verdict capsule beside it is.
    private func volumeTone(_ ex: SessionAnalysis.ExerciseReport) -> Color {
        guard let previous = previousVolume(ex) else { return Color.onyx.textSecondary }
        let delta = ex.detail.volumeKg - previous
        if abs(delta) < 0.5 { return Color.onyx.textSecondary }
        return SetRow.deltaInk(delta, upIsGood: true) ?? Color.onyx.textSecondary
    }

    /// This movement's tonnage on the session before this one.
    ///
    /// ── FROM `previousSets`, NOT FROM THE `prev` COLUMNS ────────────────────
    /// It was rebuilt from `RowWithPrev.prev`, and `SessionDetail.rowsWithPrev`
    /// attaches those POSITIONALLY — indexed by this session's numbered rows.
    /// Any previous set past that count is never attached and was silently
    /// dropped. Four sets of 100 × 10 last time and three this time summed to
    /// 3000 against 3000, so the one capsule on the row that carries a verdict
    /// said "equal" on a lift whose tonnage had fallen a quarter — and cutting
    /// a set is exactly when the reader wants the arrow.
    ///
    /// `sessionVolumeKg`, not a sum of w × r: it collapses a unilateral pair to
    /// its weaker side and skips a ghost, and `ex.detail.volumeKg` — the figure
    /// this is compared AGAINST — is that same function.
    private func previousVolume(_ ex: SessionAnalysis.ExerciseReport) -> Double? {
        guard !ex.previousSets.isEmpty else { return nil }
        return SessionVolume.sessionVolumeKg(ex.previousSets.map {
            VolumeSet(weightKg: $0.weightKg, reps: $0.reps, side: $0.side, pairId: $0.pairId, setType: $0.setType)
        })
    }

    /// What the atlas's share sheet calls this session.
    private func shareLabel(_ report: SessionAnalysis.Report) -> String {
        let day = SessionAnalysis.dayLabel(report.session.dayKey, in: environment.targets?.schedule.activeProgram) ?? "Session"
        guard let date = LogicalDay.date(fromISO: report.session.date) else { return day }
        return "\(day) · \(date.formatted(.dateTime.day().month(.abbreviated)))"
    }

}

// MARK: - Cards inside a List

extension View {
    /// A card that happens to live in a `List`: no inset, no row material, no
    /// separator. The `List` is here for the LEDGER — a real list of sets with
    /// real section headers — and these four panels ride above it rather than
    /// forcing the whole page into a `ScrollView` of hand-drawn rows.
    ///
    /// Internal rather than private since Wave 2.9: Pulse is the same shape —
    /// a real `List` of vitals with tiles riding above and below it.
    /// `edgeToEdge` drops the side gutter, which §U4.1 asks of the session
    /// page: the 16 pt inset plus the tile's own 12 pt of padding put 28 pt
    /// between the screen edge and a number, and the metric grid is three
    /// columns wide on a 375 pt phone. Flush to the edge with 16 pt inside is
    /// the same 16 pt of breathing room around the content and 24 pt more of it
    /// per row. Pulse draws the same tiles and keeps its gutter — the default
    /// is the old behaviour, so this is one screen's decision rather than the
    /// design system's.
    func plainRow(edgeToEdge: Bool = false) -> some View {
        let gutter = edgeToEdge ? 0 : OnyxSpace.l
        return Section {
            self
                .listRowInsets(EdgeInsets(top: 0, leading: gutter, bottom: 0, trailing: gutter))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
}

#if DEBUG
#Preview("Session") { HistoryPreviews.view("session") }
#endif
