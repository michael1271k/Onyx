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
        ScrollViewReader { proxy in
            list(scroller: proxy)
        }
    }

    private func list(scroller: ScrollViewProxy) -> some View {
        List {
            if let page {
                band(page).plainRow(edgeToEdge: true)
                metrics(page).plainRow(edgeToEdge: true)
                progression(page).plainRow(edgeToEdge: true)
                if !page.report.muscles.isEmpty { muscles(page.report).plainRow(edgeToEdge: true) }
                ForEach(page.report.exercises) { exercise in
                    ledger(exercise)
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
        }
        .listRowBackground(Rectangle().fill(.ultraThinMaterial))
        .listSectionSpacing(OnyxSpace.m)
        .scrollContentBackground(.hidden)
        .onyxScreen(.train)
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
        .fullScreenCover(item: $editing, onDismiss: { editing = nil }) { model in
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
        .sheet(item: $prSheet) { target in
            PrRecordSheet(
                exerciseName: target.exercise,
                setLabel: target.setLabel,
                records: target.records,
                timed: target.timed
            )
        }
        // ── THE SPARKLINE'S OWN SHEET (W10) ────────────────────────────────
        // The same chart the exercise's own page draws, from the same type
        // (`E1rmTrendChart`, second caller after `ExerciseDetailView:159`) —
        // not a second plot of one history. The header's 56×16 trail says
        // "this moved"; the question it provokes is "by how much, and when",
        // and that needs an axis, which is the one thing a sparkline refuses
        // to have. `.medium` because a line chart with a date axis is a
        // half-screen object and the ledger under it stays visible.
        .sheet(item: $trailSheet) { target in
            trailSheet(target)
        }
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
            // `defaultScrollAnchor` is decided at first layout, when the list
            // is still empty — so the harness's ledger shot has to scroll after
            // the page lands.
            if startAtLedger, let first = page?.report.exercises.first {
                try? await Task.sleep(for: .milliseconds(400))
                scroller.scrollTo(first.id, anchor: .top)
            }
        }
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

    // MARK: - 1 · The title band

    /// The masthead — `SessionHeaderCard`, which the Train tab draws from the
    /// same value (A6).
    ///
    /// ── WHY IT LEFT THIS FILE ───────────────────────────────────────────────
    /// It was 250 lines here, and the Train tab and the Pulse day each drew
    /// their own summary of the same finished session: three cards stating the
    /// same facts in three layouts, disagreeing about which ones mattered and
    /// drifting apart one edit at a time. `SessionHeader` is the value they
    /// share; everything in it is already on the page, so this is a field copy
    /// rather than a second derivation.
    ///
    /// The headline stays a parameter rather than a field: it introduces the
    /// metric grid directly below it, and there is no grid on a tab card.
    private func band(_ page: SessionAnalysis.Page) -> some View {
        // `page.program` — the deck that OWNED the session's date — and not the
        // environment's ACTIVE program, which is whichever plan is selected
        // now. They are the same deck for a session logged this block and they
        // are not for an older one, and the shot proved it: the Train tab
        // (which resolves through the loader, on the session's own date) read
        // `Upper A` while this page read `Cb A` — the tidied day KEY, which is
        // what `dayLabel` falls back to when the program handed to it does not
        // know the day. One session, two names, on two screens the reader moves
        // between with a tap.
        let label = SessionAnalysis.dayLabel(page.report.session.dayKey, in: page.program) ?? "Session"
        let verdict = delta(page.tonnageDelta, unit: "kg", higherIsBetter: true)
        return SessionHeaderCard(
            header: SessionHeader(page: page, label: label),
            headline: page.headline(label),
            // Volume left the metric grid for the masthead (§W2 A): it was the
            // first of seven equal `.display` figures under this card, which is
            // seven answers to "how did that go" and no hero.
            //
            // ── AND A SESSION THAT LIFTED NOTHING HAS NO HERO ───────────────
            // `0.0 kg` at 28 pt over a treadmill-only day is the same category
            // error `headerTags` already refuses for the tonnage capsule: the
            // work carried no load, so there is no tonnage to be zero of. With
            // no hero the split's own name takes the role back — one hero per
            // screen, and on that screen the subject is the bout.
            hero: page.report.tonnageKg > 0 ? .init(
                value: OnyxFormat.volumeExact(page.report.tonnageKg), unit: "kg",
                sub: verdict.text, subTint: verdict.color, symbol: volumeSymbol(page)
            ) : nil
        )
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
                // `Color.onyx.danger` for a heart rate and `Color.onyx.calories`
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
                OnyxStatCell(
                    "Avg HR", page.avgBpm.map { jsIntegerString($0) } ?? "—",
                    unit: page.avgBpm == nil ? nil : "bpm",
                    tint: page.avgBpm == nil ? nil : Color.onyx.danger, symbol: "heart.fill",
                    spark: page.trail { $0.avgBpm }, detail: bpmBasis(page)
                )
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

    /// Up, down, or nothing at all — the session's tonnage against the previous
    /// session of the same split.
    ///
    /// The arrow is on the LABEL rather than in the sub-line because the
    /// sub-line already prints the figure: two marks for one claim is what the
    /// `calc` superscript was, and this is the one that costs no width. Below
    /// half a kilogram there is no arrow: `delta` calls that "level", and an
    /// arrow that points at half a plate is noise with a direction.
    private func volumeSymbol(_ page: SessionAnalysis.Page) -> String? {
        guard let value = page.tonnageDelta, abs(value) >= 0.5 else { return nil }
        return value > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
    }

    /// More tonnage is good news and less is not a verdict — the same asymmetry
    /// `delta(higherIsBetter:)` draws, through the same tokens.
    private func volumeTint(_ page: SessionAnalysis.Page) -> Color? {
        guard let value = page.tonnageDelta, abs(value) >= 0.5 else { return nil }
        return value > 0 ? Color.onyx.good : Color.onyx.textSecondary
    }

    /// A signed change, in the colour of what it means — or the honest absence.
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
        return Sub(text, (value > 0) == higherIsBetter ? Color.onyx.good : Color.onyx.textSecondary)
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
                   change > 0 ? Color.onyx.record : Color.onyx.textSecondary)
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

    // MARK: - 4 · Muscle focus

    /// ── THE WHOLE CARD OPENS THE ATLAS, NOT JUST THE 96 pt FIGURE ───────────
    /// The figure was the only tap target on it, which made the one control on
    /// the card the smallest thing on it — and left the ranked list beside it,
    /// which is the part the reader is actually looking at, inert. A tile whose
    /// content is a summary of a bigger view should open the bigger view from
    /// anywhere on it; the figure keeps its own press animation because it is
    /// what the sheet zooms out of.
    ///
    /// Nested buttons is the trap here: a `Button` inside a `Button` gets a
    /// touch neither of them handles cleanly, so the inner one is gone and the
    /// figure is now just a picture inside the card's own control.
    private func muscles(_ report: SessionAnalysis.Report) -> some View {
        let total = report.muscles.reduce(0) { $0 + $1.sets }
        return Button {
            showAtlas = true
        } label: {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Muscle focus").onyxMicro()
                    Spacer(minLength: OnyxSpace.s)
                    Text("\(OnyxFormat.sets(total)) weighted sets")
                        .onyxType(.caption).onyxNumeral()
                        .foregroundStyle(Color.onyx.textSecondary)
                    Image(systemName: "chevron.right")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textTertiary)
                }
                HStack(alignment: .center, spacing: OnyxSpace.m) {
                    AtlasFigure(side: .front, worked: MuscleCredit.worked(
                        from: Dictionary(uniqueKeysWithValues: report.muscles.map { ($0.muscle, $0.sets) })
                    ))
                    .frame(height: 96)

                    // ── ONE FACT, TWO DRAWINGS, NOT THREE (§W2 D) ───────
                    // The card encoded the same distribution three ways: the
                    // atlas figure paints it on a body, the legend names the
                    // top four with their shares, and a 100 % ramp sat between
                    // them saying the legend's numbers again as lengths — in
                    // 6 pt of stacked capsule where a 4.5 and a 4.0 are one
                    // pixel apart and the sixteenth muscle is a `max(2, …)`
                    // sliver that is wider than its share. A bar that cannot
                    // be measured is not a comparison, it is a decoration of
                    // the numbers beside it.
                    //
                    // The figure is the shape and the legend is the reading.
                    legend(report.muscles)
                }
            }
            .padding(OnyxSpace.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onyxGlass(.tile)
            // AFTER the glass, so the whole tile is hit-testable and not just
            // the text inside it — and `onyxPress` scales the label, so the
            // shape follows the scale rather than the finger losing the target
            // at the moment it lands.
            .contentShape(RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .onyxPress()
        // `.combine` and NO `accessibilityLabel`: the label it builds is the
        // legend — "Muscle focus, 27 weighted sets, Lats 4.5, Upper back
        // 4.5…" — and a hand-written one would silence the ranking that used
        // to be readable when the card was not a control.
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the body you can turn over")
    }

    /// The four biggest, named. The rest are one row, because a legend of
    /// sixteen entries is a table nobody reads standing up — the sheet behind
    /// the figure is where the full ranking lives.
    private func legend(_ rows: [(muscle: LandmarkMuscle, sets: Double)]) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            ForEach(Array(rows.prefix(4).enumerated()), id: \.element.muscle) { i, row in
                HStack(spacing: OnyxSpace.xs) {
                    Circle()
                        .fill(Color.onyx.muscle(row.muscle))
                        .frame(width: 6, height: 6)
                    Text(row.muscle.displayName)
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: OnyxSpace.xs)
                    Text(OnyxFormat.sets(row.sets))
                        .onyxType(.caption).onyxNumeral()
                        .foregroundStyle(Color.onyx.textPrimary)
                }
                .accessibilityElement(children: .combine)
            }
            if rows.count > 4 {
                Text("+\(rows.count - 4) more")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
        }
    }

    // MARK: - 5 · The ledger

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
        .id(ex.id)
        .plainRow(edgeToEdge: true)
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
                    symbol: percent > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill",
                    tint: percent > 0 ? Color.onyx.good : Color.onyx.danger
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
                              symbol: "heart.fill", tint: Color.onyx.cardio))
        }
        // The app's own glyph for "this came from Apple Health" — the same one
        // the weigh-in sheet's fill button wears.
        if bout?.fromHealthkit == true {
            tags.append(.init("Automatically logged",
                              symbol: "heart.text.square", tint: Color.onyx.textSecondary))
        }
        return tags
    }

    /// Green up, red down, plain when there is nothing to compare against —
    /// the tonnage capsule's own colour, computed from the same two numbers the
    /// verdict capsule beside it is.
    private func volumeTone(_ ex: SessionAnalysis.ExerciseReport) -> Color {
        guard let previous = previousVolume(ex) else { return Color.onyx.textSecondary }
        let delta = ex.detail.volumeKg - previous
        if abs(delta) < 0.5 { return Color.onyx.textSecondary }
        return delta > 0 ? Color.onyx.good : Color.onyx.danger
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

// MARK: - One movement's masthead

/// The floor both header rows stand on — `MetaTagRow.Capsule`'s own
/// `minHeight`, spelled once.
///
/// It is what makes the swap honest. Row 2 holds readings in one state and
/// muscle names in the other, and a row whose height is set by its CONTENT
/// would move the card — and everything under it — every time the chip is
/// tapped. It is also what keeps a movement with no readings at all (an
/// unrated bodyweight hold, a bout with no `cardio_logs` row behind it) from
/// drawing a row of zero height and collapsing the card by a line.
enum OnyxLedgerRowFloor {
    static let height: CGFloat = 24
}

private extension View {
    func rowFloor() -> some View {
        frame(maxWidth: .infinity, minHeight: OnyxLedgerRowFloor.height, alignment: .leading)
            .accessibilityElement(children: .contain)
    }
}


/// Primary or assisting, by name — `MuscleMap`'s answer for one movement.
struct Mover {
    let name: String
    let primary: Bool
}

/// A ledger card's heading: the movement, and two rows that never move.
///
/// ── WHY IT IS TWO FIXED ROWS AND NOT ONE FLOW (§W2 E) ───────────────────────
/// It was a single `FlowRow` holding the muscle chips and every reading, so the
/// wrap point was wherever the text size put it: `RPE 8.0` opened line two on
/// one card and closed line one on the next, three rows of chips on a
/// three-mover movement, and ~74 pt of wrapped capsules above ~36 pt per set —
/// a screen of scrolling per movement.
///
/// Now the register decides the row and the row never changes:
///
///   row 1 · the primary muscle · how it went · what was asked · the cue
///   row 2 · what it produced — tonnage, top set, effort
///
/// ── AND WHY ROW 2 IS A SWAP RATHER THAN A DISCLOSURE ────────────────────────
/// The assisting muscles are worth having and are not worth a row: they were
/// two more chips on the line the readings needed, and on a three-mover
/// movement they took the line on their own. A disclosure that ADDS a row makes
/// the card grow under the thumb that opened it and pushes the sets out of
/// frame — which is the shape this whole wave exists to end. So tapping the
/// primary chip replaces row 2 IN PLACE: the assists arrive where the readings
/// were, the card's height does not move, and tapping again puts them back.
/// `+2` on the chip is the affordance and the count at once.
private struct LedgerHeader: View {
    let name: String
    let window: String?
    let spark: [Double]
    let family: Color
    let primary: [Mover]
    let secondary: [Mover]
    let brief: [MetaTagRow.Tag]
    let results: [MetaTagRow.Tag]
    /// See `SessionDetailView.startWithAssists`.
    var seededOpen = false
    /// Opens the movement's est-1RM chart. Nil where there is not enough
    /// history for a chart to say more than the sparkline does — the header
    /// then draws the trail as it always did, with no gesture on it, because an
    /// affordance that does nothing is worse than no affordance.
    var onTrail: (() -> Void)?

    /// Whether row 2 is showing the assists instead of the readings. Per CARD,
    /// which is why this view exists at all: the header used to be a function
    /// on the page, and a page-level dictionary keyed by movement would be the
    /// same state with a lookup in front of it.
    @State private var showingSecondaries = false
    @Environment(\.dynamicTypeSize) private var typeSize


    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            title
            // ── THE TRAIL EARNS ITS WIDTH ON THE ROW BELOW THE NAME (§W2 G) ─
            // It was 40×16 on the TITLE line, competing with the movement's
            // own name for a 375 pt line — so the name lost 44 pt to a graphic
            // with no label. On the brief's row it is beside four capsules that
            // are none of them the subject, and 56 pt is where eight sessions
            // stop reading as one wobble. The height never moves: 16 pt inside
            // a 24 pt row costs nothing, which is why it never cost anything.
            //
            // `HStack` outside the flow and not an item inside it: a `FlowRow`
            // places subviews in order and would wrap the trail to a second
            // line the moment the brief filled the first, which is a sparkline
            // alone under four capsules.
            HStack(alignment: .center, spacing: OnyxSpace.s) {
                briefRow
                if spark.count >= 2, !typeSize.isAccessibilitySize {
                    // `family`, not the domain accent: the domain fold
                    // collapses sixteen landmarks onto four hues, so a chest
                    // day and a shoulder day drew the same blue trail beside
                    // two differently-coloured cards.
                    trail
                }
            }
            resultsRow
                .animation(OnyxMotion.move, value: showingSecondaries)
                .task { if seededOpen { showingSecondaries = true } }
        }
        .padding(.horizontal, OnyxSpace.l)
        .padding(.vertical, OnyxSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        // ── A WASH IN THE MUSCLE'S OWN HUE, NOT THE DOMAIN'S ───────────────
        // Nothing is drawn here: `onyxMuscleWash` on the CARD covers the header
        // and the rows in a single run and carries the rail the whole length of
        // the movement, which is the only way header and rows can agree on a
        // colour. The band used to paint its own 28 %→4 % gradient and its own
        // 3 pt rail, which is exactly what made it read as a coloured header
        // bolted to a black list rather than as the top of one card.
    }

    /// The 56×16 est-1RM trail, and — since W10 — the way into the chart of it.
    ///
    /// ── WHY IT IS A `Button` AND NOT AN `onTapGesture` ──────────────────────
    /// The sparkline is 56×16 and the target has to be 44 pt tall to be hit at
    /// all, so the gesture needs a shape bigger than the ink. A `Button` gets
    /// `.contentShape` and the press feedback for free, publishes itself to
    /// VoiceOver as a button with a label rather than staying
    /// `accessibilityHidden`, and takes the app's own `.onyxPress`. A bare tap
    /// gesture would need all four spelled out and would still be invisible to
    /// the rotor.
    ///
    /// The graphic itself does not change and neither does the row's height:
    /// the 44 pt target is a `.frame` on the button, and the row it sits in is
    /// already 24 pt of capsules inside a header taller than both.
    @ViewBuilder
    private var trail: some View {
        if let onTrail {
            Button(action: onTrail) {
                sparkline
                    .frame(height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onyxPress()
            .accessibilityLabel("Estimated one rep max trail")
            .accessibilityHint("Opens the chart.")
        } else {
            sparkline.accessibilityHidden(true)
        }
    }

    private var sparkline: some View {
        Sparkline(points: spark, color: family, zeroBased: false)
            .frame(width: 56, height: 16)
    }

    // MARK: - Line 0 · which movement

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
            // ── THE MOVEMENT'S OWN NAME, AT THE SIZE OF A TITLE ────────────
            // It was 13 pt and uppercased by the `List`'s own header style —
            // the same treatment as the word "Cardio" two sections down, which
            // is a heading and not a subject. This card IS the movement.
            Text(name)
                .onyxType(.display)
                .textCase(nil)
                .foregroundStyle(Color.onyx.textPrimary)
                // One line, until one line cannot hold it: at AX5 on a 375 pt
                // phone "Incline DB Press" scaled to its floor and still came
                // out "Incline DB Pr…", and a movement whose name is cut off is
                // a card about nothing.
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            // ── WHAT WAS ASKED OF IT, BESIDE ITS NAME ──────────────────────
            // The window is not a result, it is the movement's brief, so it
            // belongs beside the movement. Deliberately NOT set like the title:
            // one step down, medium weight, in the movement's own hue, so
            // "@ 10–12" reads as metadata attached to the name rather than as
            // part of it. Dropped at the accessibility sizes, where the name
            // alone needs three lines and what the window did with the width
            // left over was render as a lone red ellipsis — it is still said in
            // full by the ceiling capsule on row 1.
            if let window, !typeSize.isAccessibilitySize {
                Text("@ \(window)")
                    .onyxType(.secondary).onyxNumeral()
                    .fontWeight(.medium)
                    .foregroundStyle(family)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("Target \(window)")
            }
            Spacer(minLength: OnyxSpace.xs)
        }
    }

    // MARK: - The two rows

    /// Row 1 · which muscle, and how the movement went against last time.
    private var briefRow: some View {
        FlowRow(spacing: OnyxSpace.xs) {
            if let lead = primary.first { primaryChip(lead) }
            ForEach(brief, id: \.text) { MetaTagRow.Capsule($0) }
        }
        .rowFloor()
    }

    /// Row 2 · what the movement produced — or, once the chip is tapped, what
    /// else it worked.
    ///
    /// ── THE TWO STATES ARE THE SAME OBJECT ON PURPOSE ───────────────────────
    /// A flow of `MetaTagRow.Capsule`s either way, on the same floor. The
    /// assists could have been drawn as CHIPS, in the primary's own shape, and
    /// that is exactly what would have broken the swap: a chip is 17 pt and a
    /// capsule is 24, so the card would have jumped 7 pt every time the muscle
    /// was tapped. The dot is what marks the primary out as the control, and
    /// there is exactly one of those.
    private var resultsRow: some View {
        // ── BOTH STATES, ALWAYS LAID OUT; ONE OF THEM DRAWN ─────────────────
        // A `ZStack` and not an `if`, and this is the whole of the height
        // guarantee. At the default sizes both states are one line and a branch
        // would have been enough. At AX5 every capsule takes a line of its own,
        // so three readings are three lines and two assists are two — and a
        // branch made the card, and everything under it, jump by a line every
        // time the chip was tapped, at exactly the text size where the reader
        // can least afford the page to move.
        //
        // Stacked, the row is as tall as the TALLER state in both of them, so
        // the swap is free at every size and costs a line only where a line was
        // going to be needed anyway. The inactive state is faded rather than
        // removed, which is also what gives `OnyxMotion.move` something to
        // cross-fade; it is taken out of the hit-testing and out of VoiceOver
        // so it is invisible to everything except the layout.
        ZStack(alignment: .topLeading) {
            capsules(results.map { ($0.text, $0) })
                .opacity(showingSecondaries ? 0 : 1)
                .allowsHitTesting(!showingSecondaries)
                .accessibilityHidden(showingSecondaries)
            capsules(secondary.map {
                ($0.name, MetaTagRow.Tag($0.name, tint: family.opacity(0.7)))
            })
                .opacity(showingSecondaries ? 1 : 0)
                .allowsHitTesting(showingSecondaries)
                .accessibilityHidden(!showingSecondaries)
        }
        .rowFloor()
    }

    private func capsules(_ tags: [(id: String, tag: MetaTagRow.Tag)]) -> some View {
        FlowRow(spacing: OnyxSpace.xs) {
            ForEach(tags, id: \.id) { MetaTagRow.Capsule($0.tag) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The chip that is a control

    /// ── ONE HUE, TWO WEIGHTS ────────────────────────────────────────────────
    /// The primary chip wears the movement's own muscle colour — the same
    /// `Color.onyx.muscle` value the card's rule, wash, sparkline family and the
    /// atlas below all take. An assist is the SAME colour at less than full
    /// strength, not a second colour: a distinct hue for "also worked" would be
    /// a fifth accent nobody designed, and the difference the reader needs is
    /// how much this movement is about that muscle, which is a weight.
    private func primaryChip(_ mover: Mover) -> some View {
        Button {
            withAnimation(OnyxMotion.move) { showingSecondaries.toggle() }
        } label: {
            HStack(spacing: OnyxSpace.xs) {
                Circle()
                    .fill(family)
                    .frame(width: 6, height: 6)
                Text(mover.name)
                    // `.onyxType(.micro)`, never `onyxMicro()`: this is a name,
                    // and the register role would set "Upper back" as UPPER BACK.
                    .onyxType(.micro)
                    .textCase(nil)
                    .foregroundStyle(family)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !secondary.isEmpty {
                    // `.caption` and not `.micro`, and this is the token's own
                    // rule rather than a taste: `micro` is "a register label —
                    // uppercase, tracked out, NEVER carrying a number". `+2` is
                    // a number, so it takes the next role up and sits a step
                    // larger than the name beside it, which is also what makes
                    // the affordance findable.
                    Text(showingSecondaries ? "×" : "+\(secondary.count)")
                        .onyxType(.caption).onyxNumeral()
                        .foregroundStyle(family.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, OnyxSpace.s)
            .padding(.vertical, OnyxSpace.xs)
            .frame(minHeight: OnyxLedgerRowFloor.height)
            .background(family.opacity(0.16), in: SwiftUI.Capsule())
            // ── 24 pt DRAWN, 44 pt TAPPED ──────────────────────────────────
            // The target floor is 44 and the row is 24, and growing the row to
            // meet it would put 20 pt back on every card this wave just took
            // 20 pt off. So the padding that makes the target is added, the
            // hit shape is taken from it, and the layout is given its height
            // back — the chip draws 24 pt tall inside a 44 pt touch area.
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .padding(.vertical, -10)
        }
        .buttonStyle(.plain)
        // NOT `.disabled()`. A movement with nothing assisting has nothing to
        // swap to, and disabling the button greys its label — so the one chip
        // that says which muscle this card is about came out dimmed, reading as
        // "unavailable" on a fact that is neither missing nor uncertain. The
        // gesture simply does nothing instead, and the chip keeps its ink.
        .allowsHitTesting(!secondary.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mover.name), primary")
        .accessibilityValue(secondary.isEmpty ? "" : "\(secondary.count) assisting")
        .accessibilityHint(secondary.isEmpty ? "" :
            (showingSecondaries ? "Shows this movement's readings" : "Shows the assisting muscles"))
        .accessibilityAddTraits(secondary.isEmpty ? [] : .isButton)
    }
}

// MARK: - The session's fingerprint

// ── `IntensityBar` LIVES IN OnyxUI NOW (W10) ────────────────────────────────
// `OnyxUI/Charts/IntensityBar.swift`, public. It was private to this file and
// the finish sheet wanted the same bar: the shape of how hard a session got is
// the one reading that answers "what was that like" in a glance, and the finish
// sheet is where that question is actually asked — thirty seconds after the
// last set, not on a page you navigate to. Two implementations of one gradient
// is two answers to one question, so it moved rather than being copied.
//
// Nothing about the drawing changed. It took `OnyxFormat` with it, which is why
// that enum is in OnyxUI too — see its own header.

// MARK: - The progression chart

/// Session tonnage across every session of one split, with records in gold.
///
/// ── WHY TONNAGE AND NOT ESTIMATED 1RM ───────────────────────────────────────
/// A session's est-1RM is a per-EXERCISE reading and the ledger already draws
/// it, one sparkline per movement. What a split's line answers is a different
/// question — is the day as a whole carrying more work than it did — and the
/// only figure that survives an exercise being swapped in or out is the
/// session's own tonnage.
private struct SplitVolumeChart: View {
    let points: [SessionAnalysis.SplitPoint]
    let current: String
    let tint: Color

    @State private var selected: Date?

    private var dated: [(date: Date, point: SessionAnalysis.SplitPoint)] {
        points.compactMap { p in OnyxChart.date(p.date).map { (date: $0, point: p) } }
    }

    private var yDomain: ClosedRange<Double> {
        let (lo, hi) = ChartScale.niceDomain(points.map { Optional($0.tonnageKg) })
        return lo...hi
    }

    var body: some View {
        Chart {
            ForEach(dated, id: \.point.id) { entry in
                AreaMark(x: .value("Date", entry.date), y: .value("kg", entry.point.tonnageKg))
                    .foregroundStyle(
                        LinearGradient(colors: [tint.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)
                    )
                LineMark(x: .value("Date", entry.date), y: .value("kg", entry.point.tonnageKg))
                    .foregroundStyle(tint)
                    .interpolationMethod(.monotone)
                // Gold is a record and nothing else, so a point wears it only
                // when that session actually set one. The session being read
                // gets the accent ring instead — "you are here" is not a verdict.
                //
                // ── AND A MAINTENANCE WEEK IS DRAWN HOLLOW ──────────────────
                // The line DROPS on these weeks by design; that is what a
                // maintenance week is. Filled like every other point, the dip
                // reads as a session that went badly, and the chart's own
                // verdict sentence then argues with the plan. Hollow says "this
                // was meant to be lighter" without adding a colour — status
                // hues stay reserved, and gold still means only one thing.
                PointMark(x: .value("Date", entry.date), y: .value("kg", entry.point.tonnageKg))
                    .foregroundStyle(pointColor(entry.point))
                    .symbolSize(entry.point.sessionId == current ? 90 : 28)
                    .symbol {
                        let side: CGFloat = entry.point.sessionId == current ? 11 : 7
                        if entry.point.isMaintenance {
                            Circle()
                                .strokeBorder(pointColor(entry.point), lineWidth: 1.5)
                                .frame(width: side, height: side)
                        } else {
                            Circle()
                                .fill(pointColor(entry.point))
                                .frame(width: side, height: side)
                        }
                    }
            }
            if let picked = nearest(selected), let entry = dated.first(where: { $0.date == picked }) {
                RuleMark(x: .value("Selected", picked))
                    .foregroundStyle(Color.onyx.textTertiary)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        OnyxCallout(
                            OnyxChart.shortDate(picked),
                            lines: callout(entry.point),
                            footnote: entry.point.isMaintenance ? "Maintenance week" : nil
                        )
                    }
            }
        }
        .chartYScale(domain: yDomain)
        // Both bounds labelled (§3.5): a tight domain with only the middle
        // ticks named lets a 2 % rise read as a doubling.
        .chartYAxis {
            AxisMarks(position: .trailing, values: [yDomain.lowerBound, yDomain.upperBound]) { _ in
                AxisGridLine().foregroundStyle(Color.onyx.hairline)
                AxisValueLabel()
                    .font(OnyxChart.axisFont)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
        }
        .chartXSelection(value: $selected)
        .onyxChart(.train)
        .accessibilityLabel("Session volume across this split")
    }

    private func nearest(_ date: Date?) -> Date? {
        guard let date else { return nil }
        return dated.map(\.date).min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }
    }

    private func callout(_ point: SessionAnalysis.SplitPoint) -> [OnyxCallout.Line] {
        var lines = [OnyxCallout.Line("", "\(OnyxFormat.volume(point.tonnageKg)) kg")]
        if point.prCount > 0 {
            lines.append(OnyxCallout.Line("", "\(point.prCount) PR", color: Color.onyx.record))
        }
        return lines
    }

    private func pointColor(_ point: SessionAnalysis.SplitPoint) -> Color {
        point.prCount > 0 ? Color.onyx.record : tint
    }
}

// MARK: - The set row

/// One ledger row: the set as performed, the records it won, and the RPE. A
/// unilateral pair is one row.
///
/// ── AND NOTHING FROM ANY OTHER DAY ──────────────────────────────────────────
/// The row used to end with `prev 5kg × 15` — the positionally-matched set from
/// the last time this movement was trained. See `ExerciseReport.rows` for why
/// it is gone: this is the page you land on when you finish a workout, and
/// every row on it is now a set you actually performed today.
struct SetRow: View {
    let row: DetailRow
    let timed: Bool
    /// The movement's muscle hue — what a record row is washed in. Defaulted so
    /// the row keeps working anywhere it is dropped without a family to take.
    var tint: Color = Color.onyx.record
    /// The records this row's set(s) won, with the values they beat. Empty on
    /// an ordinary row, and empty on a record row whose axes had no numeric
    /// bar — the badge still turns gold, and the long press then has nothing
    /// to open, which is why `onInspect` is only armed when this is not.
    var records: [LivePrRecord] = []
    /// Long press on a record row. Nil wherever the row is drawn without a
    /// presenter — the previews, the screenshot harness.
    var onInspect: (([LivePrRecord]) -> Void)?
    /// The same set NUMBER, the last time this movement was trained.
    ///
    /// ── WHY POSITIONAL, AND WHY ONLY HERE ───────────────────────────────────
    /// `SessionDetail.rowsWithPrev` exists and is deliberately not used: it
    /// drops previous sets past this session's count, which makes it wrong for
    /// the movement's totals (`ExerciseReport.rows`' own header). Set-to-set is
    /// the one comparison where position IS the question — "was set 3 heavier
    /// than set 3 last time" — and where having no counterpart is an honest
    /// answer rather than a dropped number: a fourth set added this week simply
    /// carries no arrow.
    ///
    /// Nil on a warm-up (no working ordinal), on a pair (two rows per set, so
    /// the previous session's list does not index by ordinal) and wherever the
    /// movement is new.
    var prev: HistorySet?
    /// What the same ROW was worth last time, in kilograms — a pair folded to
    /// one unit on both sides of the comparison.
    ///
    /// Separate from `prev` and not derived from it: `prev` is one
    /// `HistorySet`, and a pair's counterpart is two. `SessionDetailView`
    /// computes it, because folding the previous session is the card's job and
    /// not the row's. See `SessionDetailView.previousUnitVolume`.
    var prevUnitKg: Double?
    /// This row's 1-based place in its card. Only ever read for a BOUT, which
    /// is stored as a warm-up (that is what keeps five minutes of walking out
    /// of tonnage and out of the PR engine) and therefore carries no working
    /// ordinal to print — see `ordinal`.
    var position: Int = 1
    /// Which columns this movement's card puts its sets in — decided ONCE for
    /// the whole card and handed down. See `SetLayout`.
    var layout: SetLayout = .whole
    /// Whether this CARD has anything to compare against — decided once, the
    /// same way `layout` is, and for the same reason: a first-ever movement
    /// reserving a delta line on every column of every row is a card of
    /// guaranteed blanks. Defaulted true, which is the behaviour every caller
    /// that does not know had before.
    var cardComparable: Bool = true
    /// MEASURED rest before this set, in seconds (`actual_rest_sec`), or nil
    /// where nothing clocked it — which is most rows. See `ExerciseReport.rest`.
    var restSec: Int?
    /// This rest against the one before it on the same card, in seconds. Nil on
    /// the first row of a card, and nil wherever either side was not measured:
    /// a delta against an unknown is not a delta.
    var restDeltaSec: Int?
    /// Screenshot harness only — see `SessionDetailView.holdMargins`.
    var marginHeld = false

    /// The badge's side in the ledger, named because two things depend on it
    /// being the same number: the row's own gutter and the column heads' empty
    /// leading track. A header that measured the badge separately is a header
    /// that drifts off its columns by a point on the next edit.
    static let badgeSide: CGFloat = 28

    /// The `L` / `R` tag's track on a pair sub-line — one bold `micro` glyph.
    ///
    /// The value is `SetColumn.side`'s, and the number is spelled again rather
    /// than imported: that type is `private` to the logger's own card, and this
    /// page is not the place to widen it. What the two share is the reason —
    /// a FIXED track is what makes the two sides' numbers start at the same x,
    /// where an intrinsic one would step the `R` line in by however much wider
    /// the glyph is than the `L`.
    static let sideTrack: CGFloat = 14

    /// The columns one movement's card puts its sets in.
    ///
    /// ── WHY THIS IS A CARD'S DECISION AND NOT A ROW'S ───────────────────────
    /// Columns that each row chose for itself are not columns. A bodyweight
    /// movement has no load to print and would drop its first track, so a card
    /// holding one loaded warm-up and four unloaded working sets would draw two
    /// different tables under one heading. The card asks once, every row
    /// obeys, and the heading is built from the same answer — which is what
    /// makes them line up by construction rather than by two functions
    /// agreeing.
    enum SetLayout: Equatable {
        /// `KG · REPS · RPE` — a plain lifted set.
        case loaded
        /// `REPS · RPE`. The deck drops the `KG` track on a Reverse Crunch for
        /// the same reason: a `0kg` that cannot be anything else is a column
        /// that cannot say anything.
        case unloaded
        /// `MIN · KM · PACE`.
        case cardio
        /// `L 22 × 10` over `R 22 × 9` under one badge, and ONE delta line
        /// under the pair.
        ///
        /// ── WHY A UNILATERAL CARD IS NOT `.whole` ANY MORE ──────────────
        /// It was, and `.whole.comparable` is false, so a movement trained one
        /// arm at a time was the only kind on this page carrying no comparison
        /// at all (F5) — on a card where the reader most wants one, because a
        /// split set is where the two sides drift apart.
        ///
        /// It cannot be three tracks: a pair is SIX numbers, and `KG · REPS ·
        /// RPE` would have to choose which arm each column is about. Two
        /// sub-lines is the shape the logger's own deck already draws a split
        /// set in, down to the `L` / `R` tag in its own fixed track — so a set
        /// looks the same ten seconds after it is logged as it does here.
        ///
        /// A card reaches this layout when ANY of its rows is a pair, and the
        /// rows that are not simply draw their own whole string with the same
        /// reserved line under them. Both shapes are one string and one
        /// verdict, which is what lets them share a card — see `layout(_:)`.
        case pair
        /// One string across the row — a timed hold, or a card whose rows
        /// disagree about their own shape.
        case whole

        /// Whether a set in this table has a counterpart to be measured
        /// against — which is what decides whether the reserved delta line
        /// under each reading is drawn at all.
        ///
        /// A bout never does: it is stored as a warm-up (that is what keeps
        /// five minutes of walking out of tonnage and out of the PR engine), so
        /// it carries no working ordinal to index the previous session by.
        /// Three reserved lines under three readings that can never move is
        /// 36 pt of empty glass on every row of the card — which is why this is
        /// false here rather than merely blank, and why the row centres against
        /// the badge when it is (see `body`).
        ///
        /// `.pair` DOES compare, on the pair's own volume rather than on a
        /// column — see `SetRow.unitDelta` for why six numbers cannot be
        /// summarised by any one of them.
        var comparable: Bool { self != .cardio && self != .whole }

        /// What the heading says over each track. Empty for the two layouts
        /// that draw a string rather than a table, which is how the card knows
        /// not to draw one.
        var heads: [String] {
            switch self {
            case .loaded:   ["KG", "REPS", "RPE"]
            case .unloaded: ["REPS", "RPE"]
            case .cardio:   ["MIN", "KM", "PACE"]
            // A pair is a string and not a table, so there is nothing to head
            // — and `spoken` names its delta by hand for the same reason.
            case .pair:     []
            case .whole:    []
            }
        }
    }

    /// One track of the table: the reading, and the ground it gained under it.
    struct Figure {
        let text: String
        /// Signed change against the same set NUMBER last time. Nil where there
        /// is no counterpart — a fourth set added this week carries no arrow
        /// rather than a fabricated one — and nil on every cardio column, where
        /// a bout is stored as a warm-up and so has no working ordinal to index
        /// the previous session by.
        var delta: Double?
        /// Primary ink for a load or a rep count. The effort ramp for an RPE
        /// and the cardio token for a bout: those are the two columns whose
        /// VALUE carries something beyond itself.
        var tint: Color?
        /// Whether a RISE in this reading is the good news.
        ///
        /// ── THE ONE COLUMN WHERE IT IS NOT ──────────────────────────────
        /// True for a load and for a rep count, and false for an RPE: the same
        /// three sets that felt like an 8 last week and a 9.5 this week are the
        /// textbook picture of accumulated fatigue, and the ledger painted that
        /// arrow GREEN. `delta(_:unit:higherIsBetter:)` in the metric grid at
        /// the top of this same page has taken this flag since it was written,
        /// and `VitalSpec` carries it for every vital — this column was the
        /// last reading in the app asserting a direction it had not been asked
        /// about.
        var upIsGood: Bool = true
    }

    /// Which table this exercise's card draws, asked once by `ledger(_:)`.
    ///
    /// Anything it cannot answer confidently falls to `.whole`, which is the
    /// behaviour this page had before columns existed — a mixed card is drawn
    /// the old way rather than drawn wrongly.
    static func layout(_ ex: SessionAnalysis.ExerciseReport) -> SetLayout {
        guard !ex.timed else { return .whole }
        let leads = ex.rows.compactMap { $0.set ?? $0.left ?? $0.right }
        guard !leads.isEmpty else { return .whole }
        if leads.allSatisfy(isCardio) { return .cardio }
        if leads.contains(where: isCardio) { return .whole }
        // ── ONE PAIR MAKES IT A PAIR CARD ───────────────────────────────────
        // Not "every row is a pair". A movement trained one arm at a time
        // routinely opens with a bilateral warm-up, and demanding a pure card
        // would leave the commonest real shape on `.whole` — which is the
        // behaviour this branch exists to end. `.pair` draws a single row as
        // its own whole string and reserves the same one-verdict line under
        // it, so the two shapes genuinely share a table.
        if ex.rows.contains(where: { $0.kind == "pair" }) { return .pair }
        return leads.allSatisfy { SetFormat.isUnloaded($0.weightKg) } ? .unloaded : .loaded
    }

    /// Minutes and kilometres rather than plates and reps.
    static func isCardio(_ set: DetailSet) -> Bool {
        SetFormat.cardio(
            durationSec: set.durationSec, distanceKm: set.distanceKm,
            incline: set.incline, elevationM: set.elevationM
        ) != nil
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    /// Bumped by the long press, so the haptic goes through the app's own
    /// trigger rather than a bare `UIImpactFeedbackGenerator`.
    @State private var inspects = 0
    /// Whether the PR margin is still showing. True until two seconds after the
    /// row first lands — see `marginText(_:)`.
    @State private var showingMargin = true

    /// ── WHY THE ROW HAS TWO SHAPES ──────────────────────────────────────────
    /// Three things compete for one line: the badge, `42kg × 10` and an effort
    /// word. At AX5 "Very hard" alone claimed ~40 % of the width, the value was
    /// squeezed to nothing and character-wrapped one glyph per line — `4` /
    /// `2k` / `g` / `×` / `1` / `0` — because a `Text` given less than one
    /// glyph of width still draws at its intrinsic size. One set took 500 pt
    /// and said nothing.
    ///
    /// `minimumScaleFactor` cannot fix it: the row does not need smaller type,
    /// it needs a second line. So at the accessibility sizes the effort word
    /// gets its own, and the value never wraps. (The prev column was the
    /// fourth competitor here and is gone — see the type's own header.)
    ///
    /// ── AND WHY IT IS 30 pt TALL AND NOT 44 ─────────────────────────────────
    /// 44 is the tap target, and on THIS screen nothing in the row is tappable:
    /// the ledger is read, not operated (the Edit button in the bar is how a
    /// set is corrected). Four sets at 44 plus a two-line stack pushed one
    /// movement past a phone's height, so the reader scrolled a screen per
    /// exercise. The vertical padding is `xs` and the height floor is the
    /// badge's — which is what "compact" means when the row is a list of
    /// numbers rather than a row of controls.
    var body: some View {
        // ── THE ALIGNMENT IS A DECISION, NOT A DEFAULT ──────────────────────
        // `.top` is right for a table: the badge and the readings share a first
        // line and the reserved delta hangs under the numbers. A card that
        // reserves NO delta — a bout, a timed hold — has ONE line of content
        // beside a 28 pt badge inside a 36 pt row, so top-aligning it parked
        // the whole row against its ceiling with the slack underneath. That was
        // the treadmill card's second visible defect after the empty tag row,
        // and `badgeSide` is the measurement both halves centre against.
        HStack(alignment: layout.comparable ? .top : .center, spacing: OnyxSpace.s) {
            badgeGroup
            if let figures, !typeSize.isAccessibilitySize {
                // Equal tracks, and no measurement anywhere: each column asks
                // for all the width and they divide it between them, which is
                // what makes the numbers line up down the card without a
                // `Grid` — whose cell machinery is the thing that stutters on a
                // long scrolling list.
                ForEach(Array(figures.enumerated()), id: \.offset) { _, figure in
                    column(figure)
                }
            } else {
                // ── THE SHAPES A COLUMN CANNOT HOLD ────────────────────────
                // A unilateral PAIR is two sides in one row and a timed hold is
                // one reading with no second number; splitting either would
                // mean choosing which half of a set to print in a track with
                // room for one. And at the accessibility sizes there are no
                // three columns at all: a third of 375 pt at AX5 holds "4…", so
                // the row keeps the one string it can set whole and gives the
                // effort word its own line underneath.
                VStack(alignment: .leading, spacing: 2) {
                    if splitsValues {
                        // ── ONE EFFORT, CENTRED AGAINST TWO LINES ──────────
                        // The effort is the row's trailing column everywhere
                        // else and inherits the row's `.top`, which parked a
                        // single reading against the LEFT side's line — as if
                        // it were the left side's rating. Against a pair it
                        // belongs to both, so it sits between them, and the
                        // only way to centre one child of a top-aligned row is
                        // to give it a row of its own.
                        HStack(alignment: .center, spacing: OnyxSpace.s) {
                            pairLines
                            if !typeSize.isAccessibilitySize, let effort {
                                Spacer(minLength: OnyxSpace.xs)
                                effort
                            }
                        }
                    } else {
                        value
                    }
                    if typeSize.isAccessibilitySize, let effort { effort }
                    // ONLY `.pair` reserves a line here. `.loaded` and
                    // `.unloaded` reach this branch at the accessibility sizes
                    // alone, where the row has already stopped being a table
                    // and its arrows are carried by `spoken` — a fourth line on
                    // an AX5 row that is already two is not a comparison, it is
                    // a scroll.
                    if layout == .pair, cardComparable { deltaLine(unitDelta, unit: "kg") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // A split pair has already drawn its one effort, centred
                // between the two lines it belongs to.
                if !typeSize.isAccessibilitySize, !splitsValues, let effort { effort }
            }
        }
        .padding(.horizontal, OnyxSpace.l)
        // ── TALLER ROW, TIGHTER PADDING ────────────────────────────────────
        // Two changes that pull in opposite directions and are meant to: the
        // row grows 30 → 33 pt so a record's wash has room to read as a band
        // rather than a line, and its own vertical padding drops from `xs` to
        // 2 pt so the extra height goes to the AIR AROUND THE NUMBERS and not
        // to the numbers' own margins. Net effect on a four-set card is +12 pt
        // and a denser-looking row, which is the combination the review asked
        // for and the reason neither value moved alone.
        .padding(.vertical, 2)
        // The frame BEFORE the wash. A `.background` applied first sizes itself
        // to the CONTENT, so a record row's tint stopped short of the row's own
        // height and drew as a pale stripe with a dark margin under it.
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        // ── A RECORD ROW IS WASHED IN THE MOVEMENT'S OWN COLOUR ─────────────
        // It was a 2 pt gold inset on the leading edge, which is invisible on a
        // scrolled page and says nothing about WHICH lift set the record. The
        // trophy beside the badge is the gold — the one place it appears in the
        // ledger, so scanning for it still finds records and nothing else — and
        // the row behind it takes the same hue as the card's rail and wash, so
        // a record reads as this movement's record.
        //
        // 0.10 and not the 0.14 it was: the card underneath is no longer black.
        // `onyxMuscleWash` now carries 6 %→2 % of this same hue across every
        // row, so a record's own tint is read as a STEP above its neighbours
        // rather than against nothing, and the old value stepped far enough to
        // reintroduce the banding the wash exists to remove.
        .background(isRecord ? tint.opacity(0.10) : Color.clear)
        // ── THE WHOLE ROW, NOT THE 22 pt DISC ───────────────────────────────
        // The trophy is the affordance and the disc is 22 pt — under the 44 pt
        // floor, and a long press that has to be landed accurately is a gesture
        // people stop trying. The row is 33 pt tall and full width, nothing
        // else on this page is interactive, and a press on an ordinary row
        // does nothing at all rather than opening an empty sheet.
        //
        // `.contentShape` first: the row's content is a badge and two `Text`s,
        // so without it the gesture only exists where ink was drawn.
        .contentShape(Rectangle())
        // NOT guarded on `records` being non-empty. The badge turns gold on
        // `isRecord` alone, and a record whose axes had no numeric bar carries
        // no `AxisRecord` — so that guard made a gold row advertise a gesture
        // that did nothing at all. `PrRecordSheet` already ships the sentence
        // for the empty case ("This set no longer holds a record."), which is
        // an answer; silence is not.
        .onLongPressGesture(minimumDuration: 0.4) {
            guard isRecord, let onInspect else { return }
            inspects += 1
            onInspect(records)
        }
        // The app's own haptic, not `UIImpactFeedbackGenerator` directly: every
        // other surface here goes through the trigger, and a generator with no
        // `prepare()` spends the first press spinning up the taptic engine.
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: inspects)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        // VoiceOver cannot long-press, and the rotor is where it looks for what
        // a row can do. Named for the RESULT, which is what a custom action's
        // label is read as ("What it beat" → "activate What it beat").
        //
        // The builder form, because it can be CONDITIONAL: the `named:` overload
        // is unconditional, so the rotor offered "What it beat" on all twenty
        // rows of a session and did nothing on the eighteen holding no record.
        .accessibilityActions {
            if isRecord, let onInspect {
                Button("What it beat") { onInspect(records) }
            }
        }
    }

    /// The set, as the two or three independent readings it actually is.
    ///
    /// ── COLUMNS WHERE THERE WERE TWO STRINGS ────────────────────────────────
    /// `42kg × 10` was one string, so the load and the rep count could not be
    /// read down a card and neither could carry a verdict of its own. Then they
    /// became two intrinsically-sized views side by side, which is better and
    /// still not a table: every row divided the line at a different point, so
    /// the eye had to re-find the rep count on each one.
    ///
    /// Three equal tracks, `KG · REPS · RPE`, named once by the card's heading
    /// and never again by a row. The unit left the numbers with the heading,
    /// which is where the width for the third column came from.
    ///
    /// Nil for the shapes a column cannot hold — see `SetLayout.whole`.
    private var figures: [Figure]? {
        guard let lead else { return nil }
        switch layout {
        case .whole:
            return nil
        // A pair is six numbers and three tracks hold three, so this table
        // draws no columns at all — `body` takes the sub-line branch instead.
        // See `SetLayout.pair`.
        case .pair:
            return nil
        case .cardio:
            // All three in the cardio token. `MuscleMap` has no entry for a
            // bout by design, so this is the one hue that names it — and the
            // ledger used to fall through to `.recover` lavender, the same
            // colour Abs/core wears.
            //
            // Incline and ascent are not drawn. They were the two components
            // `SetFormat.cardio` already dropped off the end at AX5, they
            // describe the BOUT rather than the set, and three tracks is what
            // makes this table the same object as the strength one beside it.
            // `spoken` still carries the value in full, ascent included.
            let minutes = lead.durationSec.map { $0 / 60 }
            return [
                Figure(text: lead.durationSec.map(SetFormat.clock) ?? "—",
                       tint: Color.onyx.cardio),
                Figure(text: lead.distanceKm.map { jsIntegerString($0) } ?? "—",
                       tint: Color.onyx.cardio),
                // Derived, never stored — distance and duration are the facts.
                Figure(text: CardioMetrics.formatPace(CardioMetrics.paceMinPerKm(
                            distanceM: lead.distanceKm.map { $0 * 1000 },
                            durationMin: minutes)),
                       tint: Color.onyx.cardio)
            ]
        case .unloaded:
            return [reps(lead), effortFigure]
        case .loaded:
            return [
                Figure(text: jsIntegerString(lead.weightKg),
                       delta: prev.map { lead.weightKg - $0.weightKg }),
                reps(lead), effortFigure
            ]
        }
    }

    private func reps(_ set: DetailSet) -> Figure {
        Figure(text: jsIntegerString(set.reps), delta: prev.map { set.reps - $0.reps })
    }

    /// The effort as a NUMBER, in the ramp's own colour.
    ///
    /// ── WHY THE WORD LOST THIS COLUMN ───────────────────────────────────────
    /// "Very hard" claimed roughly 40 % of the row's width at the default type
    /// size and the whole of it at AX5, which is why the row had to shed it to
    /// a second line. A track is a number's width. What the word carried that
    /// the figure does not is the FAILURE case — and `Color.onyx.effort` is
    /// already red at the top of its ramp, so the fact survives the change of
    /// register. The word itself comes back at the accessibility sizes, where
    /// the row stops being a table.
    /// Internal rather than private since W4: "a rise in RPE is red" is this
    /// wave's whole claim about this column, and a `private` computed property
    /// can only be checked by photographing it. `SessionTableTests` reads the
    /// flag; nothing else outside this file does.
    var effortFigure: Figure {
        guard let rpe else { return Figure(text: "—", tint: Color.onyx.textTertiary) }
        return Figure(text: OnyxFormat.rpe(rpe),
                      delta: prev?.rpe.map { rpe - $0 },
                      tint: Color.onyx.effort(rpe),
                      // The whole point of the flag. Up is harder, harder is
                      // not better, and the arrow that says so is red.
                      upIsGood: false)
    }

    /// One track: the reading, and the ground it gained under it.
    ///
    /// ── THE DELTA LINE IS ALWAYS DRAWN ──────────────────────────────────────
    /// §3.6's rule, the one the metric grid at the top of this page already
    /// obeys: a line that appears only when there is a change makes the row
    /// change height between two sessions, and a row silent about its
    /// comparison is indistinguishable from one that has none. So the line is
    /// reserved, and carries an em-dash when there is nothing to say.
    ///
    /// ── AND WHY IT IS SMALLER AND QUIETER THAN THE NUMBER ───────────────────
    /// `micro` against the number's `body`. The reading is what the reader came
    /// for; the delta is the context it sits in. Same size would make a card of
    /// five sets read as ten numbers.
    ///
    /// ── THE RESERVATION SURVIVED; THE GLYPH DID NOT (W4 · A2) ───────────────
    /// The line carried an em-dash when there was nothing to say, which on a
    /// three-track card with no previous session is FIFTEEN dashes — a page of
    /// punctuation saying "no comparison" fifteen times. The reason the line is
    /// reserved is unchanged and is not about the glyph: it stops the row
    /// changing height between two sessions. So the space stays and the ink
    /// goes. See `deltaLine`.
    private func column(_ figure: Figure) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(figure.text)
                .onyxType(.body).onyxNumeral()
                .foregroundStyle(figure.tint ?? Color.onyx.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if layout.comparable, cardComparable {
                deltaLine(figure.delta, upIsGood: figure.upIsGood)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The app's own pair of triangles — the two glyphs `MetaTagRow` treats as
    /// the only direction marks — and the amount beside them, in the verdict
    /// colours and nothing else.
    /// - Parameters:
    ///   - unit: named only where the line has no column head above it to name
    ///     it — which is `.pair`, whose verdict is in kilograms and whose row
    ///     is a string rather than a table.
    ///   - upIsGood: which direction earns the good token. See `Figure`.
    @ViewBuilder
    private func deltaLine(_ delta: Double?, unit: String? = nil, upIsGood: Bool = true) -> some View {
        if let delta, abs(delta) > 0.001 {
            HStack(spacing: 2) {
                Image(systemName: delta > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .symbolRenderingMode(.hierarchical)
                Text(signed(delta) + (unit.map { " \($0)" } ?? ""))
            }
            .onyxType(.micro).onyxNumeral()
            // ── THE ARROW POINTS AT THE SIGN; THE COLOUR JUDGES IT ──────────
            // Both used to be the sign. An RPE that climbed from 8 to 9.5
            // therefore drew an up arrow in the GOOD token — the ledger
            // congratulating a lifter for being more tired. The arrow still
            // points where the number went, because that is a fact; the ink is
            // the verdict, and only the verdict inverts.
            .foregroundStyle((delta > 0) == upIsGood ? Color.onyx.good : Color.onyx.danger)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            // ── A RESERVED LINE, DRAWN IN NOTHING ───────────────────────────
            // It was an em-dash, covering both silences — no set to compare
            // with, and a number that did not move. Both readings survive: the
            // line is still there, so the row cannot change height between two
            // sessions, and there is still no arrow claiming a verdict nothing
            // earned. What is gone is the fifteen glyphs per card that said so
            // out loud.
            //
            // Measured BY the micro line rather than by a number: the same
            // `Text`, in the same role, hidden. `.hidden()` is documented as
            // "hides this view without changing its layout", so the reservation
            // is the old height by construction and at every text size — a
            // `frame(height:)` would hold at default type and drift at AX5.
            Text("—")
                .onyxType(.micro)
                .hidden()
                .accessibilityHidden(true)
        }
    }

    /// How this row's two sides are drawn — nil on anything that is not a pair.
    ///
    /// ── THE LEDGER HONOURS ALL THREE CASES; THE LOGGER STILL DOES NOT ───────
    /// `SetPairLayout.resolve` has implemented exactly the three shapes this
    /// page needs since it was written, and only the LOGGER consumed it — where
    /// `.unified` was deliberately killed for a completed pair on 2026-09-11,
    /// because a merged row left no control that could make the two sides
    /// differ. That dead end is an EDITING dead end (the rule's own header says
    /// so: "there was no way out, because the only control that could have made
    /// the sides differ was the one writing to both of them"), and this page is
    /// read-only — the Edit button in the bar is how a set is corrected here.
    /// So the ledger merges and the deck does not, and founder decision 4 is
    /// the reason the two surfaces are allowed to differ about one drawing.
    ///
    /// A group of ONE is `.unified` by the rule's own definition, which is what
    /// makes a pair row with a side missing render as an ordinary set.
    ///
    /// `reps` is rounded because the rule counts them as `Int` and a set is a
    /// whole number of reps everywhere it is entered; `DetailSet.reps` is a
    /// `Double` because every numeric column in this schema is.
    /// Internal rather than private, on the precedent `effortFigure` sets one
    /// screen down: the three cases are this wave's whole claim about this row,
    /// and a `private` computed property can only be checked by photographing
    /// it. `UnilateralAndQualityTests` reads all three; nothing else outside
    /// this file does.
    var pairLayout: SetPairLayout? {
        guard row.kind == "pair" else { return nil }
        let sides = [row.left, row.right].compactMap { $0 }
        return SetPairLayout.resolve(
            weights: sides.map { $0.weightKg },
            reps: sides.map { Int($0.reps.rounded()) },
            rpes: sides.map { $0.rpe }
        )
    }

    /// Whether the two sides get a line each, or share one.
    ///
    /// `.valueSplit` is the rule's answer and the second test is the case the
    /// rule cannot see: it reads load, reps and effort, and a CARDIO pair is
    /// told apart by `duration_sec` / `distance_km`, which are not among them.
    /// Two bouts of different lengths would resolve as `effortSplit` — equal
    /// weights, equal reps, both zero — and merge into one line that printed
    /// one of them. So a merge also asks the thing that is actually about to be
    /// drawn: if the two sides do not render the same string, they are not one
    /// line, whatever the three axes say.
    var splitsValues: Bool {
        guard layout == .pair, row.kind == "pair",
              let left = row.left, let right = row.right
        else { return false }
        return pairLayout == .valueSplit || fmt(left) != fmt(right)
    }

    /// The two ratings when they disagree — `L 8 · R 9`, and `L 8 · R —` when
    /// one side was never rated.
    ///
    /// Nil when they AGREE, which includes both being unrated: that is one
    /// reading about one set, and printing `L 8 · R 8` to say it is the
    /// repetition the three cases exist to avoid.
    ///
    /// ── AND WHY A NIL SIDE IS AN EM-DASH AND NEVER A BLANK ──────────────────
    /// `workout_sets.rpe` is nullable by design — "an unrated set must stay
    /// distinguishable from a set rated zero" (`AppDatabase`) — and until §W1 F
    /// the logger could leave one side null permanently. A ledger that printed
    /// the rated side alone would show `L 8` and read as a rating for the set,
    /// which is the one thing that row does not have.
    var splitEfforts: (Double?, Double?)? {
        guard row.kind == "pair", let left = row.left, let right = row.right,
              left.rpe != right.rpe
        else { return nil }
        return (left.rpe, right.rpe)
    }

    /// The two sides, one under the other, under one badge.
    ///
    /// ── WHY THE VALUE IS `secondary` AND NOT `body` ─────────────────────────
    /// Two `body` lines make a pair row 58 pt against a single row's 36, which
    /// is a card that scrolls for the one movement on it trained an arm at a
    /// time. The plan named `micro`, and `micro` is the one role this scale
    /// forbids for a value in as many words — "a register label … never
    /// carrying a number" (`OnyxType`). `secondary` is the legal step down,
    /// named for exactly this ("the line under a value"), and it is what makes
    /// a sub-line read as HALF of a set rather than as a set of its own.
    private var pairLines: some View {
        VStack(alignment: .leading, spacing: 1) {
            pairLine("L", row.left)
            pairLine("R", row.right)
        }
    }

    @ViewBuilder
    private func pairLine(_ tag: String, _ set: DetailSet?) -> some View {
        if let set {
            HStack(spacing: OnyxSpace.xs) {
                Text(tag)
                    .onyxType(.micro).fontWeight(.bold)
                    .foregroundStyle(Color.onyx.textTertiary)
                    // ── AND THE TRACK GOES AT THE ACCESSIBILITY SIZES ───────
                    // The logger's own split row records this trap: a scaled
                    // `micro` glyph is several times 14 pt, so a fixed frame at
                    // AX5 overflows and the letter prints straight through
                    // whatever is beside it — an `R` that comes out looking
                    // like an `F`, with nothing clipped for a layout gate to
                    // catch. A fixed track is what aligns two sides' numbers,
                    // and at a size where there is only one column to align it
                    // buys nothing.
                    .frame(width: typeSize.isAccessibilitySize ? nil : Self.sideTrack,
                           alignment: .leading)
                Text(fmt(set))
                    .onyxType(.secondary).onyxNumeral()
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    /// This row's work against the same row last time, in kilograms.
    ///
    /// ── WHY A VOLUME AND NOT A LOAD OR A REP COUNT ──────────────────────────
    /// A `.pair` row prints its set as a STRING, so there is one line under it
    /// to carry one verdict, and no one of six numbers can be it: 22 × 10 /
    /// 22 × 9 against 20 × 12 / 20 × 11 is heavier and shorter at once.
    ///
    /// ── AND WHY `SessionVolume` AND NOT `w × r + w × r` ─────────────────────
    /// "The pair's combined load × reps" has exactly one definition in this app
    /// and it is not the sum. `SessionVolume.sessionVolumeKg` scores a genuine
    /// L/R pair ONCE, at the weaker side, so a set logged split weighs what the
    /// same set weighs logged whole — the rule its own header says must
    /// survive. The card's tonnage capsule is that function and the session's
    /// tonnage is that function; a second pair arithmetic on the row beneath
    /// them would put two numbers on one card that disagree about what a pair
    /// is worth.
    private var unitDelta: Double? {
        guard let previous = prevUnitKg else { return nil }
        return volumeKg - previous
    }

    /// What this row is worth, by the one rule. A single row on a `.pair` card
    /// goes through the same function and comes out as `w × r`.
    private var volumeKg: Double {
        SessionVolume.sessionVolumeKg([row.set, row.left, row.right].compactMap { $0 }.map {
            VolumeSet(weightKg: $0.weightKg, reps: $0.reps,
                      side: $0.side, pairId: $0.pairId, setType: $0.setType)
        })
    }

    /// `+2.5`, `−1`. `jsIntegerString` and not a fixed decimal count: a real
    /// plate change is 2.5 and a real rep change is 2, and "+2.0 reps" is a
    /// precision the number does not have.
    private func signed(_ delta: Double) -> String {
        (delta > 0 ? "+" : "−") + jsIntegerString(abs(delta))
    }

    /// The ordinal, and the trophy beside it when the set set a record.
    ///
    /// ── WHY THE TROPHY MOVED, AND WHY THE NUMBER STAYED ─────────────────────
    /// The mark used to sit beside the VALUE, at the other end of the row from
    /// the number. Scanning a session for its records therefore meant reading
    /// down a ragged column whose x-position moved with the width of
    /// `42kg × 10` — and the two facts a reader pairs ("which set" and "was it
    /// a record") were 200 pt apart.
    ///
    /// Putting the trophy IN the badge, replacing the number, was tried and
    /// reverted for a reason that still holds: every set on this page is
    /// logged, so a card's rows read `W · 🏆 · 2 · 🏆` and the two rows most
    /// worth placing were the two with no number left on them. Beside the
    /// badge is the third answer, and it costs nothing either side gives up —
    /// the ordinal column stays a column, and the mark is now the first thing
    /// on the row instead of the last.
    ///
    /// FAILURE DOES NOT GET THIS SLOT. It keeps the effort column's own word,
    /// where it has always been said, because a red glyph at the head of the
    /// row would compete with the gold for the same glance and there is only
    /// one fact here worth interrupting a scan for.
    /// ── THE TROPHY IS NOW THE BADGE, BY REQUEST (2026-09-11) ────────────────
    /// Everything above describes why the mark sat BESIDE the ordinal, and the
    /// argument was real: every set on this page is logged, so replacing the
    /// number costs the reader the one column that places a set in its card.
    ///
    /// The founder asked for the swap anyway, and the cost is bought back
    /// rather than ignored: the ordinal is still spoken in full by `spoken`
    /// ("Set 3, 72.5 kg × 15, Volume record"), the rows either side of a record
    /// still number continuously so the position is readable by counting, and
    /// the trophy is now a CONTROL — long-press it and the sheet names the set
    /// as its subtitle. A gold disc at the head of the row is also the only
    /// thing on this page worth interrupting a scroll for, which is the reading
    /// the original layout was trying to buy with a second glyph.
    private var badgeGroup: some View {
        VStack(spacing: 1) {
            badge
            restGutter
        }
    }

    /// The rest taken BEFORE this set, in the badge's own column.
    ///
    /// ── WHY THE GUTTER AND NOT A FOURTH TRACK ───────────────────────────────
    /// The card's table is `KG · REPS · RPE` and all three tracks are already
    /// at their floor on a 375 pt phone — `set-row-u2` is the wave that got the
    /// row to stop being wider than the screen, and a fourth column would undo
    /// it. The badge's column is 28 pt wide, is the same 28 pt the heading
    /// leaves empty, and has nothing under the ordinal at all.
    ///
    /// ── AND WHY IT COSTS NO HEIGHT ON A CARD THAT COMPARES ──────────────────
    /// A comparable card already reserves a delta line under every reading
    /// (`SetLayout.comparable` and `deltaLine`), and the badge is 28 pt inside
    /// a row that is therefore already taller than it. The rest lands in slack
    /// that was there anyway. On a card that reserves NO delta — a bout, a
    /// timed hold — the line WOULD add height, so it is not drawn: those are
    /// also the two shapes where the number says least (a treadmill block is
    /// one set, and there is nothing before it to have rested from).
    ///
    /// ── THE DELTA IS A DIRECTION, NOT A VERDICT ─────────────────────────────
    /// An arrow and no colour. Resting longer than the set before is neither
    /// good nor bad — it is what the session did, and this app paints `good`
    /// only on facts it is prepared to call improvements. Under 15 seconds no
    /// arrow at all: `restSec` is wall-clock, it moves by whatever a rack queue
    /// and a phone unlock cost, and an arrow on every row would be noise
    /// wearing the shape of a signal. Fifteen is the same grid `adjustRest`
    /// nudges on.
    @ViewBuilder
    private var restGutter: some View {
        if layout.comparable, cardComparable, !typeSize.isAccessibilitySize {
            // ── TWO TENANTS, ONE LINE, AND THE MARGIN HAS THE LEASE ────────
            // See `marginText`. The margin is shown for two seconds and the
            // rest takes the line back; on a row with no record — which is
            // most of them — the rest has it from the first frame.
            if let margin, showingMargin {
                marginText(margin.short)
            } else if let restSec {
                Text(restLabel(restSec))
                    .onyxType(.micro).onyxNumeral()
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: SetRow.badgeSide, alignment: .center)
                    // Spoken by `spoken`, which says it in words — "rested 2
                    // minutes 15 seconds" rather than "up 2 colon 15".
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
    }

    /// What the trophy was worth, in the badge's own column, for two seconds.
    ///
    /// ── WHY IT SHARES THE GUTTER RATHER THAN TAKING A PLACE IN THE TABLE ────
    /// The row is a three-track table at its width floor on a 375 pt phone
    /// (`set-row-u2`), so a fourth reading would push one of the three out —
    /// and a reading that appears for two seconds and then leaves would push it
    /// out and pull it back, twenty rows of a page re-laying themselves under a
    /// thumb. An overlay over the table was the other draft and it landed on
    /// the KG column's own delta arrow, which is a collision rather than a
    /// layout.
    ///
    /// Under the badge is directly under the TROPHY — which is what the margin
    /// is about — it is the one column with slack, and it is a slot that
    /// already exists. Nothing moves when the two swap, because the line is the
    /// same height either way.
    ///
    /// ── AND WHY IT IS TRANSIENT AT ALL ──────────────────────────────────────
    /// The page is the one you land on when you finish a workout, and the
    /// question it answers on arrival is "what did I just do". A record's
    /// MARGIN is the best two seconds of that and a poor permanent column: it
    /// is true of a handful of rows out of twenty, it is a different unit on
    /// each of them, and a week later it is a figure already destroyed in the
    /// store (`ExerciseReport.records`' own header — `personal_records` is
    /// upsert-on-conflict and keeps no history). So it is shown, and then it
    /// gets out of the way; the long press still opens `PrRecordSheet` with
    /// both numbers, for ever.
    ///
    /// Reduce Motion gets no cross-fade, only the same two-second life: what is
    /// animated is opacity on one micro line, and removing it outright would
    /// take the fact away rather than the movement.
    private func marginText(_ margin: String) -> some View {
        Text(margin)
            .onyxType(.micro).fontWeight(.bold).onyxNumeral()
            .foregroundStyle(Color.onyx.record)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: SetRow.badgeSide, alignment: .center)
            .transition(.opacity)
            // Said by `spoken`, which is the row's one label — a line that
            // published itself would interrupt the sentence the row is in the
            // middle of.
            .accessibilityHidden(true)
            .task {
                guard !marginHeld else { return }
                try? await Task.sleep(for: .seconds(2))
                withAnimation(OnyxMotion.move) { showingMargin = false }
            }
    }

    /// `2:15`, with a bare arrow in front when it moved by a quarter-minute or
    /// more against the set before.
    private func restLabel(_ seconds: Int) -> String {
        let clock = Clock.format(Double(seconds))
        guard let delta = restDeltaSec, abs(delta) >= 15 else { return clock }
        return "\(delta > 0 ? "↑" : "↓")\(clock)"
    }

    /// Never wrapped, and never scaled below legibility: it is the row.
    ///
    /// A FOUR-component cardio value — `5:00 · 0.37 km · 2% · 7 m` — is whole
    /// at 375 pt (verified on an SE 3rd gen) and TRUNCATES at AX5, where the
    /// incline and the ascent both drop off the end. That is the row's own rule
    /// and not an accident: it sheds the effort column at the same sizes, and
    /// `spoken` carries the value in full to VoiceOver, ascent included. If a
    /// sighted AX5 reader ever needs the tail, this line is the one to change —
    /// `lineLimit(typeSize.isAccessibilitySize ? 2 : 1)`.
    ///
    /// The components are ordered longest-lived first, so what AX5 sheds is
    /// what was added last: duration and distance are the two facts a walk
    /// always has, and ascent is the one the column was added for.
    private var value: some View {
        Text(current)
            .onyxType(.body).onyxNumeral()
            .foregroundStyle(Color.onyx.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The set's number, in the box the logger's own deck draws it in — `W` for
    /// a warm-up, the ordinal for everything else, the trophy for a record.
    ///
    /// ── IT IS THE DECK'S BADGE NOW, NOT A SECOND DRAWING OF ONE ─────────────
    /// This was a 22 pt grey `Circle`. The deck, ten seconds earlier in the same
    /// workout, draws the same set as a rounded rectangle in the movement's own
    /// hue — so one object had two shapes and two colour languages depending on
    /// which screen you were standing on. `SetBadge` is the single answer; what
    /// this call keeps is the ledger's own SIZE (28 rather than 32, in a 33 pt
    /// row that is read and not operated) and the ledger's own rule about the
    /// ordinal: every set on this page is logged, so a tick on each of them
    /// would lose the one column that places a set inside its card.
    ///
    /// The trophy still replaces the number on a record, by the founder's 11
    /// September call — see the note above `badgeGroup` for what that costs and
    /// how it is bought back.
    private var badge: some View {
        SetBadge(
            label: ordinal,
            tint: tint,
            kind: badgeKind,
            // Never the solid fill: on the deck a filled box means "logged",
            // and on a page where EVERY set is logged that reading carries no
            // information and would paint the whole ledger in the rail.
            filled: false,
            isRecord: isRecord,
            side: Self.badgeSide
        )
        // The box is the row's left margin and its height floor; it must not
        // grow with the type size or it takes the width from the value beside
        // it — and `minimumScaleFactor` alone does not hold at AX5, where a
        // scaled 13 pt caption is still half again the size of the box and drew
        // straight over the value. What is written here is spoken by the row
        // (see `spoken`), so capping the badge's own type costs nothing.
        .dynamicTypeSize(...DynamicTypeSize.large)
        // An unlabelled glyph over a `Shape` is not an accessibility element.
        .accessibilityHidden(true)
    }

    /// What VoiceOver hears, built by hand rather than combined: the row's
    /// visible text no longer names the record axes, and "65 kg × 10" alone
    /// would make the session's best set sound like every other one.
    private var spoken: String {
        var parts = [row.num.map { "Set \($0)" } ?? "Warm-up set", current]
        if !axes.isEmpty { parts.append("\(axes.joined(separator: ", ")) record") }
        // Two ratings are spoken as two. `rpe` is the MAX of the row's sides,
        // which is the right single number for a set that agreed with itself
        // and, on a pair that did not, is the harder arm announced as though it
        // were the set — the exact reading the split column exists to end.
        if let sides = splitEfforts {
            parts.append("left \(readout(sides.0)), right \(readout(sides.1))")
        } else if let rpe {
            parts.append(Effort.rpeLabel(rpe))
        }
        // ── THE ARROWS ARE SPOKEN, BECAUSE THEY ARE THE ONLY PLACE THIS IS
        // SAID ──────────────────────────────────────────────────────────────
        // The row is `children: .ignore`, so every column's delta is invisible
        // to VoiceOver unless it is named here — and the previous session's
        // set is nowhere else on this page. Zipped against the card's own
        // heads, so a column and its spoken name cannot drift apart.
        for (head, figure) in zip(layout.heads, figures ?? []) {
            guard let delta = figure.delta, abs(delta) > 0.001 else { continue }
            parts.append("\(head.lowercased()) \(delta > 0 ? "up" : "down") \(jsIntegerString(abs(delta)))")
        }
        // A pair has no heads to zip against — its one line is about the SET
        // and not about a column — so it is named by hand. Without this the
        // only comparison a unilateral card carries would be invisible to
        // VoiceOver, which is the state this whole layout exists to end.
        if layout == .pair, let delta = unitDelta, abs(delta) > 0.001 {
            parts.append("volume \(delta > 0 ? "up" : "down") \(jsIntegerString(abs(delta))) kilograms")
        }
        // The gutter is `accessibilityHidden` and says `↑2:15`, which is not a
        // sentence. Said here in words, and said whatever the type size is —
        // the gutter itself is dropped at the accessibility sizes, where the
        // row has stopped being a table, and dropping the fact with the glyph
        // would make this the one reading a VoiceOver user cannot reach.
        if let restSec {
            var sentence = "rested \(Clock.format(Double(restSec)))"
            if let delta = restDeltaSec, abs(delta) >= 15 {
                sentence += ", \(abs(delta)) seconds \(delta > 0 ? "longer" : "shorter") than the set before"
            }
            parts.append(sentence)
        }
        // The margin the overlay shows for two seconds and then takes away. A
        // transient graphic is no graphic at all to a reader who cannot see it,
        // and this is the only other place the number is said.
        if let margin { parts.append("beat it by \(margin.spoken)") }
        return parts.joined(separator: ", ")
    }

    /// What the record on this row BEAT, as one short signed figure — or nil.
    ///
    /// ── ONE AXIS, CHOSEN, NOT THE LIST ──────────────────────────────────────
    /// A set can take four axes at once and `PrRecordSheet` prints all of them,
    /// which is what the long press is for. A two-second glance holds one
    /// number, so the ladder is fixed rather than "whichever came first": the
    /// heaviest load is the claim a lifter reads first, the estimated 1RM is
    /// the one that survives a rep change, reps come next, and set tonnage last
    /// — it is the axis most likely to move for a reason that is not strength.
    ///
    /// Nil when the row holds a record with no numeric bar behind it, which is
    /// a real state (`SetRow.records`' own header): the badge still turns gold
    /// and there is simply no margin to print.
    private var margin: (short: String, spoken: String)? {
        let ladder: [PrAxis] = [.weight, .e1rm, .reps, .volume]
        guard let record = ladder.lazy.compactMap({ axis in
            records.first { $0.axis == axis }
        }).first else { return nil }
        let gain = record.mark.value - record.mark.previous
        guard gain > 0.001 else { return nil }
        let figure = record.axis == .reps ? OnyxFormat.sets(gain) : OnyxFormat.kg(gain)
        let unit = record.axis.unit
        // ── THE DRAWN FORM CARRIES NO UNIT, AND THE SPOKEN ONE DOES ────────
        // The gutter is 28 pt of monospaced digits. `+1.6 kg` renders as
        // `+1.6…` at the scale floor — a margin with its own number cut off,
        // which is worse than no margin — and `+12.5kg` would still have to
        // overflow onto the load column's own delta arrow. `+12.5` is five
        // glyphs and always whole.
        //
        // Nothing is lost by dropping it: the KG column is the very next
        // thing on the row, under a heading that says KG, and a reps record
        // has no unit to print in the first place. VoiceOver gets the long
        // form, where there is no width at all to be short about.
        return (
            short: "+\(figure)",
            spoken: unit.isEmpty ? "+\(figure)" : "+\(figure) \(unit)"
        )
    }

    @ViewBuilder
    private var effort: (some View)? {
        if rpe != nil || splitEfforts != nil { effortInk }
    }

    /// Reached only when there is something to say — see `effort`.
    ///
    /// Two readings print as NUMBERS and one prints as a WORD, which is the
    /// same call the logger's own split row makes (`ExerciseCardView.effort`):
    /// the row is already telling you this is the left arm and the right arm,
    /// so the question has narrowed from "how hard was that" to "which of the
    /// two was harder" — and two numbers answer a comparison better than two
    /// words, in a column sized for one of them.
    @ViewBuilder
    private var effortInk: some View {
        if let sides = splitEfforts {
            HStack(spacing: 3) {
                sideEffort("L", sides.0)
                Text("·")
                    .onyxType(.micro)
                    .foregroundStyle(Color.onyx.textTertiary)
                sideEffort("R", sides.1)
            }
            .lineLimit(1)
            .fixedSize()
        } else if let rpe {
            Text(Effort.rpeLabel(rpe))
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.effort(rpe))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func sideEffort(_ tag: String, _ value: Double?) -> some View {
        HStack(spacing: 2) {
            Text(tag)
                .onyxType(.micro).fontWeight(.bold)
                .foregroundStyle(Color.onyx.textTertiary)
            Text(value.map(OnyxFormat.rpe) ?? "—")
                .onyxType(.caption).fontWeight(.bold).onyxNumeral()
                .foregroundStyle(value.map(Color.onyx.effort) ?? Color.onyx.textTertiary)
        }
    }

    /// A bout is drawn as an ordinary set for the same reason the deck draws
    /// it as one: `W` is a claim about a LIFT — the ramp-up sets before the
    /// working ones — and a treadmill block has no working set to be a ramp
    /// for. The KIND is untouched; only the drawing changes.
    private var ordinal: String { row.num.map(String.init) ?? (isCardio ? "\(position)" : "W") }

    /// Drawn as a normal set, whatever it is stored as.
    private var badgeKind: LoggerModel.SetKind {
        isCardio ? .normal : (LoggerModel.SetKind(rawValue: row.kind) ?? .normal)
    }

    /// Whether THIS row is a bout. Asked by `ordinal` and `badgeKind`, which
    /// are about one row; the card's `layout` is the same test asked of every
    /// row at once.
    private var isCardio: Bool { lead.map(Self.isCardio) ?? false }

    private var lead: DetailSet? { row.set ?? row.left ?? row.right }

    private var isRecord: Bool { !axes.isEmpty }

    // A failed set is named ONCE on this row, by the effort column's own word
    // ("Failure", in `Color.onyx.danger`). It had a second `f.circle.fill`
    // beside the value; that glyph is gone with the slot it shared with the
    // trophy, which has moved to the badge. Saying it twice was affordable
    // while the mark column existed and is not worth reintroducing one.

    private var current: String {
        // Only a pair whose sides actually DIFFER is two readings. One that
        // agrees is one set, drawn and spoken as one — see `splitsValues`.
        if row.kind == "pair", splitsValues {
            return [row.left.map { "L " + fmt($0) }, row.right.map { "R " + fmt($0) }]
                .compactMap { $0 }.joined(separator: " · ")
        }
        return lead.map(fmt) ?? "—"
    }

    private var axes: [String] {
        var out: [String] = []
        for a in [row.set, row.left, row.right].compactMap({ $0?.prAxes }).flatMap({ $0 }) {
            let label = PrAxis(rawValue: a).map { PrEngine.axisLabel($0, timed: timed) } ?? a
            if !out.contains(label) { out.append(label) }
        }
        return out
    }

    private var rpe: Double? {
        [row.set, row.left, row.right].compactMap { $0?.rpe }.max()
    }

    /// One side's rating in words, or the fact that it has none. Never a
    /// silence: VoiceOver reading "left hard" and stopping cannot be told from
    /// a row with one side.
    private func readout(_ value: Double?) -> String {
        value.map(Effort.rpeLabel) ?? "not rated"
    }

    private func fmt(_ kg: Double, _ reps: Double) -> String {
        SetFormat.format(weightKg: kg, reps: reps, timed: timed)
    }

    /// The set as ITS OWN axes — `5:00 · 0.37 km · 2% · 7 m` for the treadmill,
    /// `42kg × 10` for everything else.
    ///
    /// `SetFormat.cardio` answers nil unless the set carries one of the three
    /// columns `hotfix-polish.sql (git history)` added, so the fallback is the whole
    /// of the previous behaviour and every lifted row renders byte for byte as
    /// it did. Without it the treadmill that opens 2026-09-07 reads `0 reps` —
    /// `weight_kg 0, reps 0` is exactly what that session stores.
    ///
    private func fmt(_ s: DetailSet) -> String {
        SetFormat.cardio(
            durationSec: s.durationSec, distanceKm: s.distanceKm,
            incline: s.incline, elevationM: s.elevationM
        ) ?? fmt(s.weightKg, s.reps)
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
