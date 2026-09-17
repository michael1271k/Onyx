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
            startedAt: session.startedAt ?? Date()
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
        return SessionHeaderCard(
            header: SessionHeader(page: page, label: label),
            headline: page.headline(label)
        )
    }


    // MARK: - 2 · The metric grid

    /// Seven figures in two rows, each with a reserved line under it.
    ///
    /// ── WHY THE SECOND LINE IS ALWAYS THERE ─────────────────────────────────
    /// §3.6: "every number has a unit and a reserved delta line". A delta that
    /// appears only when there is one to show makes the whole grid change height
    /// between two sessions, and a cell that is silent about its comparison is
    /// indistinguishable from one that has none. So the line is always drawn:
    /// the change when there is a previous session of this split, and "first of
    /// this split" when there is not.
    private func metrics(_ page: SessionAnalysis.Page) -> some View {
        let report = page.report
        return VStack(spacing: OnyxSpace.grid) {
            LazyVGrid(columns: columns(3), spacing: OnyxSpace.grid) {
                // ── THE GLYPHS AND THE HUES ARE THE ONES THE APP ALREADY OWNS ──
                // `Color.onyx.danger` for a heart rate and `Color.onyx.calories`
                // for a burn is what the Live Stats card has drawn since U3, so
                // the screen you finish on and the screen you review say the
                // same two readings in the same two colours. Nothing new is
                // spent here: effort takes `Color.onyx.effort`, records take
                // the record gold, and the volume arrow takes the verdict —
                // every one of them a function that already exists because
                // something else asks it the same question.
                cell("Volume", OnyxFormat.volumeExact(report.tonnageKg), "kg",
                     sub: delta(page.tonnageDelta, unit: "kg", higherIsBetter: true),
                     tint: volumeTint(page), symbol: volumeSymbol(page))
                cell("Duration", report.session.durationMin.map { jsIntegerString(jsRound($0)) } ?? "—", "min",
                     sub: delta(page.durationDelta, unit: "min", higherIsBetter: nil))
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
                cell("Sets", "\(report.physicalSets)", nil, sub: composition(report) ?? delta(page.setsDelta.map(Double.init), unit: "", higherIsBetter: true))
            }
            LazyVGrid(columns: columns(4), spacing: OnyxSpace.grid) {
                cell("Difficulty", report.session.sessionRpe.map { "\(OnyxFormat.rpe($0))/10" } ?? "—", nil,
                     sub: .init(report.session.sessionRpe.map { Effort.rpeLabel($0) } ?? "not rated", Color.onyx.textTertiary),
                     // An unrated session takes no colour: `effort(_:)` starts
                     // at secondary ink and only leaves it when the work was
                     // genuinely hard, and a grey dash tinted amber would be a
                     // verdict on a reading nobody gave.
                     // No glyph: at four cells across, 84 pt each, the 11 pt
                     // symbol and its 4 pt gap were exactly what turned
                     // "Difficulty" into "Difficu…". The tint says the same
                     // thing here — `Color.onyx.effort` IS the effort ramp —
                     // and a label that cannot be read is worse than a cell
                     // with one mark instead of two.
                     tint: report.session.sessionRpe.map { Color.onyx.effort($0) })
                cell("Records", "\(report.prCount)", nil,
                     sub: recordsDelta(page),
                     tint: report.prCount > 0 ? Color.onyx.record : nil,
                     // Only when there is one. A permanent trophy over a zero is
                     // how gold stops meaning a personal record — the same rule
                     // the Lock Screen card's `N PR` already follows.
                     symbol: report.prCount > 0 ? "trophy.fill" : nil)
                cell("Avg HR", page.avgBpm.map { jsIntegerString($0) } ?? "—", page.avgBpm == nil ? nil : "bpm",
                     sub: .init(bpmBasis(page), Color.onyx.textTertiary),
                     tint: page.avgBpm == nil ? nil : Color.onyx.danger, symbol: "heart.fill")
                cell("Calories", page.calories.map { jsIntegerString($0) } ?? "—",
                     page.calories == nil ? nil : "kcal",
                     sub: .init(basis(page), Color.onyx.textTertiary),
                     tint: page.calories == nil ? nil : Color.onyx.calories, symbol: "flame.fill")
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

    private struct Sub {
        let text: String
        let color: Color
        init(_ text: String, _ color: Color) { self.text = text; self.color = color }
    }

    /// ── FOUR ACROSS ON A 375 pt PHONE IS 84 pt A CELL ───────────────────────
    /// Which is what the Calories cell broke on. `383` in `.display` beside
    /// `kcal` beside a raised `calc` needed ~110 pt; the value obeyed its
    /// `minimumScaleFactor` and stopped, and the two unconstrained `Text`es
    /// behind it did the only other thing they can — wrapped. `kcal` on its own
    /// line, `calc` on a third, and a tile two lines taller than the three
    /// beside it.
    ///
    /// Three changes, and the first is the one that matters:
    ///
    ///  · The `calc` superscript is GONE. The sub-line under the figure already
    ///    reads "estimated" or "measured" — it is the same fact, in a word
    ///    rather than an abbreviation, on the line that exists to carry it, in
    ///    the 24 pt the cell does not have to spare. Two marks for one claim,
    ///    and the one that cost the layout was the one nobody has to be taught.
    ///  · The unit is held to one line and allowed to scale, like the value it
    ///    sits beside. A unit that wraps is a unit that has left its number.
    ///  · The stack no longer lets the unit push the value: `layoutPriority`
    ///    gives the figure the width first, which is the right order — `38…`
    ///    beside `kcal` is worse than `383` beside a slightly smaller `kcal`.
    private func cell(
        _ label: String, _ value: String, _ unit: String?, sub: Sub,
        tint: Color? = nil, symbol: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // ── THE GLYPH SITS WITH THE LABEL, NOT WITH THE FIGURE ──────────
            // Four cells across is 84 pt each on a 375 pt phone (see below),
            // and a symbol beside the value takes that width from the one thing
            // in the cell that must not shrink. Beside the register label it
            // costs 14 pt of a line that is already short, and it is the half
            // of the cell the eye uses to FIND the reading rather than to read
            // it.
            //
            // `.hierarchical` rather than flat: the flame's inner lobe and the
            // trophy's base separate at 11 pt, which is what makes them read as
            // objects instead of as blobs, and it takes the tint the label is
            // already spending.
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .onyxType(.micro)
                        .foregroundStyle(tint ?? Color.onyx.textTertiary)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .onyxMicro()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .onyxType(.display).onyxNumeral()
                    .foregroundStyle(tint ?? Color.onyx.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .layoutPriority(1)
                if let unit {
                    Text(unit)
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Text(sub.text)
                .onyxType(.caption).onyxNumeral()
                .foregroundStyle(sub.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OnyxSpace.s)
        .onyxGlass(.row)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value) \(unit ?? ""), \(sub.text)")
    }

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

                    VStack(alignment: .leading, spacing: OnyxSpace.s) {
                        ramp(report.muscles, total: total)
                        legend(report.muscles)
                    }
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

    /// One bar, split by share. It is the legend's numbers as a length, which
    /// is the comparison the reader is actually making.
    private func ramp(_ rows: [(muscle: LandmarkMuscle, sets: Double)], total: Double) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(Array(rows.enumerated()), id: \.element.muscle) { i, row in
                    Rectangle()
                        .fill(Color.onyx.muscle(row.muscle))
                        .frame(width: total > 0 ? max(2, proxy.size.width * row.sets / total) : 0)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .accessibilityHidden(true)
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
                    layout: layout
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
    /// prescribed, how much of it landed on the ceiling, what it produced, and
    /// the trail of estimated 1RM behind it. The rows underneath are the
    /// evidence.
    ///
    /// Three lines, in the order the questions are asked: which movement, which
    /// muscles, what came out of it.
    private func ledgerHeader(_ ex: SessionAnalysis.ExerciseReport, family: Color) -> some View {
        let domain = MuscleGroup.forExercise(ex.canonical).domain
        let chips = movers(ex.canonical)
        let tags = headerTags(ex, domain: domain, family: family)
        return VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                // ── THE MOVEMENT'S OWN NAME, AT THE SIZE OF A TITLE ────────
                // It was 13 pt and uppercased by the `List`'s own header style
                // — the same treatment as the word "Cardio" two sections down,
                // which is a heading and not a subject. This section IS the
                // movement: the name is what the reader is looking for when
                // they scroll, and `SessionAnalysis.displayName` is what makes
                // it "Incline DB Press" rather than `helix5-incline-db-press`
                // on a session this phone logged.
                Text(ex.canonical)
                    .onyxType(.display)
                    .textCase(nil)
                    .foregroundStyle(Color.onyx.textPrimary)
                    // One line, until one line cannot hold it: at AX5 on a
                    // 375 pt phone "Incline DB Press" scaled to its floor and
                    // still came out "Incline DB Pr…", and a movement whose
                    // name is cut off is a card about nothing.
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                // ── WHAT WAS ASKED OF IT, BESIDE ITS NAME ──────────────────
                // The prescription used to be an arithmetic capsule two rows
                // down — `2/3 @ 10–12` — where the reader had to find the
                // window before they could judge the reps in the table. The
                // window is not a result, it is the movement's brief, so it
                // belongs beside the movement.
                //
                // Deliberately NOT set like the title: one step down, rounded,
                // medium weight and in the movement's own hue, so "@ 10–12"
                // reads as metadata attached to the name rather than as part
                // of it. `layoutPriority` above gives the name the width
                // first — "Incline DB Pr… @ 10–12" would be the wrong trade.
                //
                // `family`, not `domain.accent`, for the reason the sparkline
                // two lines down already gives: the domain fold collapses
                // sixteen landmarks onto four accents, so the brief on a CHEST
                // card came out violet beside a red rail, red chips and a red
                // trail. This is the sixth surface on the card answering "which
                // movement" and it takes the same answer as the other five.
                //
                // The `2/3` half stays a capsule: how much of the brief landed
                // IS a result, and it belongs with the other results.
                // Dropped at the accessibility sizes, on the same rule the
                // sparkline below takes: at AX5 the name alone needs three
                // lines, and what the window did with the width left over was
                // render as a lone red ellipsis. It is still said in full by
                // the `1/3 @ 8–12` capsule two rows down, which is the reading
                // that survives at every size.
                if let window = ex.window, !typeSize.isAccessibilitySize {
                    Text("@ \(window)")
                        .onyxType(.secondary).onyxNumeral()
                        .fontWeight(.medium)
                        .foregroundStyle(family)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel("Target \(window)")
                }
                Spacer(minLength: OnyxSpace.xs)
                // 40×16, no axis, no label: it is there to say "this has been
                // going up" in the space a number would take. Blank under two
                // sessions — `Sparkline`'s own empty caption is written for a
                // widget face and truncates to "not en…" at this width — and
                // blank at the accessibility sizes, where 40 pt of unlabelled
                // decoration is 40 pt the name needs.
                if ex.spark.count >= 2, !typeSize.isAccessibilitySize {
                    // `family`, not `domain.accent`: the domain fold collapses
                    // sixteen landmarks onto four hues, so a chest day and a
                    // shoulder day drew the same blue trail beside two
                    // differently-coloured cards. Fifth surface on this page to
                    // answer "which muscle" — it takes the same answer.
                    Sparkline(points: ex.spark, color: family, zeroBased: false)
                        .frame(width: 40, height: 16)
                        // A `Path` has no baseline of its own, so in a
                        // `.firstTextBaseline` row it was aligned by its own
                        // centre and floated above the type beside it. Its
                        // BOTTOM is the trail's zero line — sitting that on the
                        // text baseline is what makes the graphic read as part
                        // of the line rather than as a sticker on it.
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                        .accessibilityHidden(true)
                }
            }
            // ── ONE FLOW, NOT TWO STACKED ONES (W4 · A4) ──────────────────
            // `FlowRow` and no `Spacer` anywhere in it: a `Spacer` cannot wrap,
            // and one pushing the last item to the far edge is what made the
            // chips and the prescription divide a 375 pt line four ways at AX5.
            // The line simply becomes two when it has to, which is what a flow
            // layout is for.
            //
            // The chips were their own `FlowRow` and the readings were a
            // `MetaTagRow`, which is a `FlowRow` too, stacked underneath. Two
            // flow layouts cannot share a line even when the first one ends
            // with half a phone to spare, so a two-mover movement spent a whole
            // capsule line saying "Chest · Triceps" and the readings began
            // under it regardless. Three lines for a header whose content is
            // two, on every card, which is the height the founder called
            // terrible.
            //
            // One layout, and the wrap now happens where the CONTENT runs out
            // rather than where the type boundary is. Chips first — what the
            // movement IS, before what it produced.
            //
            // ── AND THE VERDICT MOVED TO THE END ───────────────────────────
            // `headerTags` used to lead with it, because on a row of its own it
            // was the only tinted item and, when five capsules wrapped, it was
            // the one that ended up orphaned at the far left of a second line.
            // On a row that OPENS with coloured chips it no longer needs the
            // first slot to be found — and a conclusion belongs after the
            // evidence it is drawn from.
            FlowRow(spacing: OnyxSpace.xs) {
                ForEach(chips, id: \.name) { mover in
                    muscleChip(mover, family: family)
                }
                ForEach(tags, id: \.text) { tag in
                    MetaTagRow.Capsule(tag)
                }
            }
            // One element, because it is one line: `MetaTagRow` combined its
            // own and the chips combined theirs, and merging the layouts
            // without merging the labels would have left VoiceOver reading two
            // groups off one row.
            .accessibilityElement(children: .combine)
            .accessibilityLabel((chips.map(\.name) + tags.map(\.spoken)).joined(separator: ", "))
        }
        .padding(.horizontal, OnyxSpace.l)
        .padding(.vertical, OnyxSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        // ── A WASH IN THE MUSCLE'S OWN HUE, NOT THE DOMAIN'S ───────────────
        // `MuscleGroup.domain` collapses sixteen landmarks onto four accents,
        // so a chest day and a shoulder day drew the identical bar. The atlas,
        // the ramp and the legend on this same page are all already keyed on
        // `Color.onyx.muscle`, and this is the fourth surface answering the
        // same question — it takes the same colour or it is decoration.
        //
        // ── THE BAND NO LONGER PAINTS ITSELF ───────────────────────────────
        // It used to carry a 28 %→4 % gradient left-to-right and a 3 pt rail of
        // its own, which is exactly what made it read as a coloured header
        // BOLTED TO a black list rather than as the top of one card. Both moved
        // up to `onyxMuscleWash` on the card, where one gradient covers the
        // header and the rows in a single run and the rail spans the whole
        // movement. Nothing is drawn here now: the colour arrives through the
        // card, which is the only way header and rows can agree on it.
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
        // At AX5 a chip is a line, so three of them is three lines of "also
        // worked" above the numbers the reader came for. The primaries are what
        // the movement IS; the assists are the first thing to go.
        let limit = typeSize.isAccessibilitySize ? 1 : 3
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

    private struct Mover {
        let name: String
        let primary: Bool
    }

    /// ── ONE HUE, TWO WEIGHTS ────────────────────────────────────────────────
    /// The primary chip wears the movement's own muscle colour — the same
    /// `Color.onyx.muscle` value the card's rule, wash, sparkline family and the
    /// atlas below all take. An assist is the SAME colour at less than full
    /// strength, not a second colour: a distinct hue for "also worked" would be
    /// a fifth accent nobody designed, and the difference the reader needs is
    /// how much this movement is about that muscle, which is a weight.
    private func muscleChip(_ mover: Mover, family: Color) -> some View {
        HStack(spacing: OnyxSpace.xs) {
            Circle()
                .fill(family.opacity(mover.primary ? 1 : 0.5))
                .frame(width: 6, height: 6)
            Text(mover.name)
                // `.onyxType(.micro)`, never `onyxMicro()`: this is a name, and
                // the register role would set "Upper back" as UPPER BACK.
                .onyxType(.micro)
                .textCase(nil)
                .foregroundStyle(mover.primary ? family : family.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, OnyxSpace.s)
        // 3 pt, not 2: the value line is two columns and two arrows now rather
        // than one string, and the row that was legible as `42kg × 10` reads as
        // a table when it holds four objects. The height floor below took the
        // same change, in the same commit, for the same reason — they are one
        // measurement in two places.
        .padding(.vertical, 3)
        .background(family.opacity(mover.primary ? 0.16 : 0.08), in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mover.primary ? "\(mover.name), primary" : "\(mover.name), assisting")
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
    private func headerTags(
        _ ex: SessionAnalysis.ExerciseReport, domain: OnyxDomain, family: Color
    ) -> [MetaTagRow.Tag] {
        // A BOUT'S OWN READINGS FIRST, where a lift's would be. See
        // `cardioTags` — on a treadmill every capsule below this line is
        // guarded off, and the row came out empty.
        var tags: [MetaTagRow.Tag] = Self.cardioTags(ex, bout: page?.bout)
        // "Top" is a claim about the WORKING sets, so an exercise that has none
        // does not get to make it. It used to print `Top 0 reps` — the same lie
        // as `0kg × 0` — on any all-warm-up movement, which the treadmill block
        // is by construction.
        if ex.stats.topKg > 0 || ex.stats.topReps > 0 {
            tags.append(.init(
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
            tags.append(.init(
                "\(OnyxFormat.volume(ex.detail.volumeKg)) kg",
                symbol: "scalemass.fill",
                tint: volumeTone(ex)
            ))
        }
        if let rpe = ex.stats.avgRpe {
            tags.append(.init("RPE \(jsToFixed1(rpe))", symbol: "bolt.fill", tint: Color.onyx.effort(rpe)))
        }
        // How much of the prescription landed inside its window. The window
        // itself has moved up beside the movement's name — this is the half
        // that is a RESULT, and results live here.
        if let window = ex.window {
            tags.append(.init(
                "\(ex.atCeiling)/\(Int(ex.detail.workingSets)) @ \(window)",
                symbol: "target",
                tint: Color.onyx.textSecondary
            ))
        }
        if let cue = ex.cue { tags.append(.init(cue.short, tint: domain.accent)) }
        // ── THE VERDICT GOES LAST, AND IT CARRIES ITS OWN MAGNITUDE ─────────
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
                tags.append(.init("level", tint: Color.onyx.textTertiary))
            } else {
                tags.append(.init(
                    "\(percent > 0 ? "+" : "−")\(jsIntegerString(jsRound(abs(percent))))%",
                    symbol: percent > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill",
                    tint: percent > 0 ? Color.onyx.good : Color.onyx.danger
                ))
            }
        }
        return tags
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

// MARK: - The session's fingerprint

/// How hard the session got, set by set — one bar, and no axis.
///
/// ── WHY A GRADIENT AND NOT A CHART ──────────────────────────────────────────
/// The question it answers is shape-shaped: did this session open easy and end
/// at the stop, or was it flat at eight the whole way through? A `Chart` with
/// an axis would invite the reader to look up individual values, which the
/// ledger below already prints exactly — and would cost a plot, a scale and a
/// legend on a page that already has three charts on it.
///
/// One stop per set, placed at the CENTRE of its slice rather than at its
/// edges, so adjacent efforts blend instead of banding. That is the difference
/// between a fingerprint and a bar chart lying on its side.
///
/// ── AND WHY IT COSTS NOTHING TO SCROLL PAST ─────────────────────────────────
/// `LinearGradient` with n stops is one layer and no offscreen pass. The stops
/// are computed once per value change (the array is a `let` on the report,
/// built off the main actor by `SessionAnalysis`), never per frame — which is
/// the rule the rest of this wave's additions are held to.
private struct IntensityBar: View {
    let values: [Double?]

    /// Two sets is not a shape. One rated set among twenty is not one either:
    /// a bar that is grey for 95 % of its length says nothing about effort and
    /// everything about rating discipline, which is not what it is for.
    private var rated: Int { values.compactMap { $0 }.count }

    private var stops: [Gradient.Stop] {
        guard values.count > 1 else {
            return values.first.map { [Gradient.Stop(color: colour($0), location: 0),
                                       Gradient.Stop(color: colour($0), location: 1)] } ?? []
        }
        return values.enumerated().map { index, value in
            Gradient.Stop(
                color: colour(value),
                location: (Double(index) + 0.5) / Double(values.count)
            )
        }
    }

    /// An unrated set is text-grey and not a zero — the same rule
    /// `Color.onyx.effort` follows at the bottom of its own ladder.
    private func colour(_ rpe: Double?) -> Color {
        rpe.map { Color.onyx.effort($0) } ?? Color.onyx.textTertiary
    }

    var body: some View {
        if values.count >= 3, rated >= 2 {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                HStack(spacing: OnyxSpace.xs) {
                    Text("Intensity")
                        .onyxMicro()
                    Spacer(minLength: 0)
                    Text("\(values.count) sets")
                        .onyxType(.micro).onyxNumeral()
                        .foregroundStyle(Color.onyx.textTertiary)
                }
                Capsule()
                    .fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8)
            }
            .padding(OnyxSpace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onyxGlass(.row)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Intensity across \(values.count) sets")
            .accessibilityValue(spoken)
        }
    }

    /// VoiceOver gets the three readings a sighted reader takes off the shape:
    /// where it started, where it peaked, where it ended.
    private var spoken: String {
        let rated = values.compactMap { $0 }
        guard let first = rated.first, let last = rated.last, let peak = rated.max() else {
            return "not rated"
        }
        return "opened at RPE \(OnyxFormat.rpe(first)), peaked at \(OnyxFormat.rpe(peak)), finished at \(OnyxFormat.rpe(last))"
    }
}

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
                    if layout == .pair { deltaLine(unitDelta, unit: "kg") }
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
            if layout.comparable { deltaLine(figure.delta, upIsGood: figure.upIsGood) }
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
        badge
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
        return parts.joined(separator: ", ")
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
