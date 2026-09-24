#if DEBUG
import SwiftUI
import GRDB
import OnyxCore
import OnyxData
import OnyxUI

/// Seeded logger screens for `scripts/native-shot.sh`.
///
/// Both shots are of a session MID-FLIGHT, because that is the only state worth
/// reviewing: an empty deck shows the layout and none of the density, and a
/// finished one shows neither. The loads are the real Upper B in
/// `LoggerPreviewData` — 49.5 kg, 42.5 kg, 13.75 kg, an RPE of 9.5 — which is
/// what exposes a four-character load beside a two-character rep count.
enum LoggerPreviews {

    /// An environment over a fixture's own store — the harness needs one
    /// because `LiveStatsView` reads the previous session through it, and
    /// `AppEnvironment.preview` holds a different (shared) database.
    ///
    /// The client points at a URL that does not resolve, exactly as the preview
    /// environment's does: a shot must never reach the network.
    @MainActor
    static func environment(over store: AppDatabase) -> AppEnvironment {
        AppEnvironment(
            database: store,
            supabase: OnyxSupabase.makeClient(config: SupabaseConfig(
                url: URL(string: "https://preview.invalid")!,
                anonKey: "preview"
            ))
        )
    }

    /// A synthetic heart-rate series in the session's telemetry CACHE row —
    /// the row `SessionTelemetry.reading` answers from before it asks Health
    /// (overhaul C1). So `session-hr` photographs the inline strip with no
    /// HealthKit, no signing and no permission sheet. The movements are cut
    /// from the fixture's own set events, exactly as a real read is.
    static func seedHeartRate(_ store: AppDatabase, sessionId: String) {
        // The window `previewTelemetry(closed:)` stamps: started 46 min ago,
        // ended 43 min after that.
        let start = Date().addingTimeInterval(-46 * 60)
        let end = start.addingTimeInterval(43 * 60)
        try? store.seedRows { db in
            let samples = stride(from: 0.0, to: end.timeIntervalSince(start), by: 15).map { t -> [String: Any] in
                let bpm = 118 + 22 * sin(t / 240) + 9 * sin(t / 37)
                return ["at": start.addingTimeInterval(t).timeIntervalSince1970, "bpm": Int(bpm.rounded())]
            }
            let json = try JSONSerialization.data(withJSONObject: samples)
            try db.execute(
                sql: "INSERT OR REPLACE INTO session_telemetry (session_id, samples_json, segments_json, source, fetched_at) VALUES (?, ?, ?, 'health', ?)",
                arguments: [sessionId, json, Data("[]".utf8), Date()]
            )
        }
    }

    @MainActor @ViewBuilder
    static func view(_ screen: String) -> some View {
        switch screen {
        // ── OVERHAUL C1: the summary's inline heart-rate strip, fixture-backed ─
        case "session-hr":
            let closed = LoggerModel.previewTelemetry(closed: true)
            let _ = PreviewCatalogue.seed(closed.store)
            let sessionId = closed.model.sessionId ?? ""
            let _ = seedHeartRate(closed.store, sessionId: sessionId)
            NavigationStack { SessionDetailView(sessionId: sessionId) }
                .environment(LoggerPreviews.environment(over: closed.store))
                .preferredColorScheme(.dark)
        case "set-row":
            // The ROW, in every state it has — because the states are the
            // design and a card of four identical unlogged rows photographs
            // none of them. Top to bottom: a warm-up, a logged working set, a
            // logged set that took a record, a set the seed bumped whose
            // remembered rating no longer fits, and a skipped one.
            //
            // Shot as a bare card on the train screen rather than inside the
            // deck: this is the shot the column widths are reviewed on, and a
            // hero, a chip row and a rest capsule above it are three things
            // between the reviewer and the thing being reviewed.
            let model = LoggerModel.previewUpperB(logged: true)
            // The first LIFT, not `exercises[0]`. The deck opens with the
            // treadmill now (`withWarmupCardio`), and this shot is where the
            // load, rep and effort column widths are reviewed — a cardio card
            // has no loads to measure them against.
            let exercise = model.exercises.first { !$0.rows.contains(where: \.isCardio) }!
            let _ = {
                while exercise.rows.count < 5 { model.addSet(to: exercise) }
                exercise.rows[0].kind = .warmup
                // ── TWO, FOUR AND FIVE GLYPHS, ON THREE ADJACENT ROWS ───────
                // W1's defect, kept photographable. A `monospacedDigit` load
                // advances at ~0.6 em and its decimal point at ~0.26, so the
                // three strings below are ~2.0, ~2.7 and ~3.3 em wide — and a
                // load column whose floor does not scale with the type runs out
                // of room between the fourth glyph and the fifth. `18.75` then
                // came out visibly smaller than `17.5` and `20` on the same
                // card. They are the founder's own three numbers, and they must
                // render at ONE size at every text setting.
                exercise.rows[0].weightKg = 20
                exercise.rows[1].weightKg = 17.5
                exercise.rows[2].weightKg = 18.75
                exercise.rows[2].isRecord = true
                exercise.rows[3].weightKg = 42.5
                exercise.rows[3].reps = 8
                exercise.rows[3].rpe = 8.5
                exercise.rows[3].progressed = true
                exercise.rows[3].rpeStale = true
                exercise.rows[3].previous = "40kg × 11"
                exercise.rows[4].kind = .ghost
                exercise.rows[4].reps = 12
            }()
            ScrollView {
                ExerciseCardView(exercise: exercise, model: model, position: (0, model.exercises.count))
                    .padding(.horizontal, OnyxSpace.m)
            }
            .onyxScreen(.train)
            .environment(AppEnvironment.preview)
            .preferredColorScheme(.dark)
        case "logger-effort":
            // ── THE WRIST'S CROWN ON THE DECK CARD (overhaul A3) ────────────
            // Three ticked sets, each holding a provisional rating from a
            // different band — hard, very hard, failure — so one shot reviews
            // the three fixed inks; the fourth row is ticked and rated to show
            // the plain word beside them.
            let model = LoggerModel.previewUpperB(logged: true)
            let exercise = model.exercises.first { !$0.rows.contains(where: \.isCardio) }!
            let _ = {
                while exercise.rows.count < 4 { model.addSet(to: exercise) }
                for (i, row) in exercise.rows.prefix(4).enumerated() {
                    row.weightKg = 42.5; row.reps = 10 - i
                    if !row.isDone { model.toggleDone(row, in: exercise) }
                }
                exercise.rows[3].rpe = 7.5
                model.stopRest()
                for (row, rpe) in zip(exercise.rows, [8.5, 9.5, 10]) { model.seedProvisionalForPreview(row, rpe: rpe) }
            }()
            ScrollView {
                ExerciseCardView(exercise: exercise, model: model, position: (0, model.exercises.count))
                    .padding(.horizontal, OnyxSpace.m)
            }
            .onyxScreen(.train)
            .environment(AppEnvironment.preview)
            .preferredColorScheme(.dark)
        case "set-row-split":
            // ── THE PAIR, IN ALL THREE OF ITS LAYOUTS ──────────────────────
            // A unilateral movement's set box is one box whatever the two
            // sides say, and how much of it splits depends on how much they
            // disagree (`SetPairLayout`). All three states have to be in one
            // photograph or the shot reviews a rule by showing one third of
            // it: set 1 agrees and draws as an ordinary row, set 2 differs
            // only in effort and splits the rating alone, set 3 differs in
            // load and reps and draws two sub-lines under one badge.
            //
            // The card is a real deck card driven by the real model, so the
            // ordinals in the photograph are the ordinals `LoggerModel.groups`
            // produces — which is the whole thing being reviewed.
            let split = LoggerModel.previewUpperB(logged: true)
            let arm = split.exercises.first { split.canSplit($0) }!
            let _ = {
                while LoggerModel.physical(arm.rows) < 3 { split.addSet(to: arm) }
                let sets = LoggerModel.groups(arm.rows)
                // 1 · both arms the same, and both logged.
                for row in sets[0] {
                    row.weightKg = 7.5; row.reps = 15; row.rpe = 8
                    if !row.isDone { split.toggleDone(row, in: arm) }
                }
                // 2 · same numbers, and the left one was harder.
                for (i, row) in sets[1].enumerated() {
                    row.weightKg = 10; row.reps = 12; row.rpe = i == 0 ? 9.5 : 8.5
                    if !row.isDone { split.toggleDone(row, in: arm) }
                }
                // 3 · the weaker side, unlogged: two lines, two loads.
                for (i, row) in sets[2].enumerated() {
                    row.weightKg = i == 0 ? 12.5 : 10
                    row.reps = i == 0 ? 10 : 8
                }
                split.stopRest()
            }()
            ScrollView {
                ExerciseCardView(exercise: arm, model: split, position: (0, split.exercises.count))
                    .padding(.horizontal, OnyxSpace.m)
            }
            .onyxScreen(.train)
            .environment(AppEnvironment.preview)
            .preferredColorScheme(.dark)
        case "logger-rest":
            // ── THE TWO THINGS ON A CARD THAT ONLY EXIST BETWEEN SETS (W10) ─
            // The rest bar draining across the header's bottom edge, and the
            // `1 more @ 12` cue. Its own screen because the `logger` shot
            // photographs the TOP of the deck and the movement that is resting
            // is whichever one you just logged — three cards down, below the
            // fold, on every fixture this harness has.
            //
            // TWO cards and not one, because the two things are mutually
            // exclusive on a single header and that is the design: the rest
            // control is ~130 pt and the instruction line is already full at
            // 375 pt, so `prescription` drops the chips — the progression one
            // included — for as long as the clock is running. A one-card shot
            // can photograph the bar or the cue and never both.
            //
            // So the resting movement is on top and a second, idle one is
            // under it wearing the cue. Which is also the state a real deck is
            // in: you are resting from the movement you just logged, and the
            // one below it is telling you what it wants next.
            //
            // The countdown in the middle of the control is a live
            // `Text(timerInterval:)` and will read differently on every run.
            // That is the state, not a defect — `logger-timer` photographs its
            // stopwatch stopped because a STOPPED face says the same thing; a
            // rest bar at rest says nothing at all.
            let resting = LoggerModel.previewUpperB(logged: true)
            let card = resting.exercises.first { $0.name == "Chest Press" }!
            let next = resting.exercises.first { $0.name == "Seated Cable Row (Wide Grip)" }!
            let _ = {
                resting.startRest(for: card)
                // `.oneMore` and not `.ready`: a `.ready` verdict has already
                // pre-filled a row (`SeedRow.progressed`) and the card draws
                // the `↗ 42.5 kg` chip off the ROW, which `set-row` already
                // photographs. This is the verdict that has no row to be read
                // off and drew nowhere until this wave.
                resting.seedDebugProgression([
                    ProgressionQueue.Alert(
                        exerciseId: "pv-cable-row", name: next.name,
                        dayKey: resting.day.key, dayLabel: resting.day.label, dayColor: nil,
                        suggestKg: 45, currentKg: 42.5, timed: false, ceiling: 12,
                        state: .oneMore
                    )
                ])
            }()
            ScrollView {
                VStack(spacing: OnyxSpace.m) {
                    ExerciseCardView(exercise: card, model: resting, position: (1, resting.exercises.count))
                    ExerciseCardView(exercise: next, model: resting, position: (3, resting.exercises.count))
                }
                .padding(.horizontal, OnyxSpace.m)
            }
            .onyxScreen(.train)
            .environment(AppEnvironment.preview)
            .preferredColorScheme(.dark)
        case "logger-timer":
            // Both clocks in one sheet: the session's own reading and pause at
            // the top, the SET stopwatch under it. Presented by the harness for
            // the reason every other sheet here is — the button that opens it
            // is the hero's elapsed reading, and a shot script cannot tap one.
            //
            // The stopwatch is photographed STOPPED at zero. Running, it draws
            // `Text(_:style: .timer)`, whose rendering is the system's and
            // changes between any two frames — so a shot of it would fail a
            // pixel comparison every run while telling a reviewer nothing the
            // stopped face does not.
            let ticking = LoggerModel.previewUpperB(logged: true)
            NavigationStack {
                LiveLoggerView(model: ticking)
                    .sheet(isPresented: .constant(true)) {
                        TimerSheet(clock: ticking, accent: Color.onyx.day(ticking.day.key))
                    }
            }
            .environment(AppEnvironment.preview)
            .preferredColorScheme(.dark)
        case "set-row-records":
            // The sheet the trophy opens — what the record actually was and
            // what it beat. Presented by the harness for the same reason the
            // finish sheet is: a screen that ships its own way to open a sheet
            // for a screenshot is a state nobody can reach and nobody
            // maintains. The records are the LIVE ones: the pulldown's second
            // set takes two axes through `toggleDone` in the preview data, so
            // this is the real engine's answer and not a fixture.
            let won = LoggerModel.previewUpperB(logged: true)
            let lift = won.exercises.first { $0.name == "Neutral-Grip Lat Pulldown" }!
            let best = LoggerModel.groups(lift.rows).first { group in
                group.contains(where: \.isRecord)
            } ?? []
            NavigationStack {
                LiveLoggerView(model: won)
                    .sheet(isPresented: .constant(true)) {
                        PrRecordSheet(
                            exerciseName: lift.name,
                            setLabel: "Set 2",
                            records: won.records(for: best, in: lift)
                        )
                    }
            }
            .environment(AppEnvironment.preview)
            .preferredColorScheme(.dark)
        case "set-row-cardio":
            // The treadmill block, which asked for kilograms and reps until
            // this wave and now asks for the two numbers a walk actually has.
            // Its own screen because the deck's first page is the only place
            // it appears and a paged deck photographs one page.
            let cardio = LoggerModel.previewUpperB(logged: true)
            let bout = cardio.exercises.first { $0.rows.contains(where: \.isCardio) }!
            ScrollView {
                ExerciseCardView(exercise: bout, model: cardio, position: (0, cardio.exercises.count))
                    .padding(.horizontal, OnyxSpace.m)
            }
            .onyxScreen(.train)
            .environment(AppEnvironment.preview)
            .preferredColorScheme(.dark)
        case "effort-picker":
            // Over a set that was SEEDED and then out-grown — the pip state the
            // sheet exists to explain. A picker shot with nothing chosen
            // photographs the empty state and calls it the control.
            let model = LoggerModel.previewUpperB(logged: true)
            let exercise = model.exercises[1]
            let row = exercise.rows[0]
            let _ = { row.rpeStale = true }()
            NavigationStack {
                LiveLoggerView(model: model)
                    .sheet(isPresented: .constant(true)) {
                        EffortPickerSheet(
                            ordinal: 1, exerciseName: exercise.name, row: row,
                            wasStale: true,
                            onPick: { row.rpe = $0; row.rpeStale = false }
                        )
                    }
            }
            .environment(AppEnvironment.preview)
            .preferredColorScheme(.dark)
        case "set-options", "logger-options":
            // The set options sheet, over the card it belongs to. Presented by
            // the harness for the same reason the finish sheet is: a screen
            // that ships a way to open one of its own sheets for a screenshot
            // is a screen with a state nobody can reach and nobody maintains.
            //
            // Over the second set of a UNILATERAL movement, and that set is a
            // warm-up carrying two qualities — the sheet's whole job is to show
            // two axes at once, and a shot of it with both unset would
            // photograph the empty state and call it the control.
            //
            // Unilateral so that `Split L / R` is IN the picture. It is absent
            // on a bilateral movement by design (see `SetOptionsSheet.split`),
            // and a control that only exists on some cards is a control no shot
            // of the others can review.
            let model = LoggerModel.previewUpperB(logged: true)
            let exercise = model.exercises.first { model.canSplit($0) } ?? model.exercises[1]
            let row = exercise.rows[min(1, exercise.rows.count - 1)]
            // Seeded HERE and not in a `.task`. This builder runs again on
            // every re-render and makes a fresh model each time, so a task that
            // mutates the model it captured is describing an object the next
            // frame has already replaced — which photographed as the empty
            // state, twice.
            let _ = { row.kind = .warmup; row.qualities = [.formBreakdown, .momentum] }()
            NavigationStack {
                LiveLoggerView(model: model)
                    .sheet(isPresented: .constant(true)) {
                        SetOptionsSheet(
                            ordinal: 2, exerciseName: exercise.name, row: row,
                            onKind: { model.setKind($0, on: row, in: exercise) },
                            onQuality: { model.setQuality($0, on: row, in: exercise) },
                            onSplit: model.canSplit(exercise) ? {} : nil,
                            onDelete: {}
                        )
                    }
            }
            .environment(AppEnvironment.preview)
            .preferredColorScheme(.dark)
        case "logger-finish":
            // The finish sheet is presented BY the harness rather than by a
            // debug flag inside the view: a screen that ships a way to open one
            // of its sheets for a screenshot is a screen with a state nobody
            // can reach and nobody maintains.
            //
            // ── AND IT NEEDS THE STORE NOW (W10) ───────────────────────────
            // The sheet's tonnage trail is `splitTonnage`, a read of the last
            // few FINISHED sessions of this split. Over `previewUpperB`'s
            // storeless model it answers empty, the spark draws nothing, and
            // the shot photographs the sheet exactly as it looked before this
            // wave while claiming to review it.
            let finishing = LoggerModel.previewUpperBWithHistory()
            NavigationStack {
                LiveLoggerView(model: finishing.model)
                    .sheet(isPresented: .constant(true)) {
                        FinishSheet(model: finishing.model, onFinish: { _ in true })
                    }
            }
            .environment(LoggerPreviews.environment(over: finishing.store))
            .preferredColorScheme(.dark)
        // ── W5: the heart-rate chart and the Hevy card ──────────────────────
        // `telemetry-*` run the DEBUG seed first (`TelemetrySeedGate`), so
        // the chart is a real read of the simulator's Health store and not a
        // fixture drawn to look like one. `hevy-card` is the one screen that
        // IS a fixture, for the reason `FinishSheet.foreignFixture` gives.
        case "telemetry-finish":
            let finishing = LoggerModel.previewTelemetry(closed: false)
            // The catalogue rows, so "View summary" from this sheet opens on
            // the page rather than on "Session not found" — the same seed
            // `telemetry-detail` needs, for the same reason.
            let _ = PreviewCatalogue.seed(finishing.store)
            TelemetrySeedGate {
                NavigationStack {
                    LiveLoggerView(model: finishing.model)
                        .sheet(isPresented: .constant(true)) {
                            FinishSheet(model: finishing.model, onFinish: { _ in true })
                        }
                }
            }
            .environment(LoggerPreviews.environment(over: finishing.store))
            .preferredColorScheme(.dark)
        case "telemetry-detail":
            let closed = LoggerModel.previewTelemetry(closed: true)
            // `SessionAnalysis.page` resolves the store's owner from the
            // catalogue rows (`localUserId`), which the logger fixture does
            // not seed — without them the page answers "Session not found".
            let _ = PreviewCatalogue.seed(closed.store)
            let environment = LoggerPreviews.environment(over: closed.store)
            let sessionId = closed.model.sessionId ?? ""
            // The production path: a finish PREFETCHES the series into the
            // cache (`AppEnvironment.sessionFinished`), and the page then
            // opens on the cache row — which is what this screen photographs
            // and what the log line "telemetry cache hit" proves.
            TelemetrySeedGate(then: { await environment.telemetry.prefetch(sessionId: sessionId) }) {
                NavigationStack {
                    SessionDetailView(sessionId: sessionId)
                }
            }
            .environment(environment)
            .preferredColorScheme(.dark)
        // ── W3: the mid-session add, driven by hand on the simulator ────────
        // A live Upper B deck over a store that holds a Face Pull session on
        // Upper A. Nothing is pre-added: the shot is taken after tapping "Add
        // a movement" and picking it, which is the path being reviewed.
        case "logger-add":
            let adding = LoggerModel.previewAddExercise()
            NavigationStack {
                LiveLoggerView(model: adding.model)
            }
            .environment(LoggerPreviews.environment(over: adding.store))
            .preferredColorScheme(.dark)
        case "hevy-card":
            let compared = LoggerModel.previewUpperBWithHistory()
            NavigationStack {
                LiveLoggerView(model: compared.model)
                    .sheet(isPresented: .constant(true)) {
                        FinishSheet(
                            model: compared.model, onFinish: { _ in true },
                            foreignFixture: .previewHevy(over: compared.model.sessionRow?.startedAt ?? Date())
                        )
                    }
            }
            .environment(LoggerPreviews.environment(over: compared.store))
            .preferredColorScheme(.dark)
        case "logger-stats":
            // The second face. Shot with a session mid-flight for the same
            // reason the first is: an empty Live Stats page is five cards of
            // empty states, which photographs the fallbacks and calls it the
            // design.
            let stats = LoggerModel.previewUpperBWithHistory()
            NavigationStack {
                LiveLoggerView(model: stats.model, face: .stats)
            }
            .environment(LoggerPreviews.environment(over: stats.store))
            .preferredColorScheme(.dark)
        case "logger-lifts":
            // The Top Lifts card and the timeline under it, which are two
            // screens below the fold on the stats face — the one shot that can
            // review a lift GROUP, its arrows and its flame, and a cardio bout
            // whose dot is filled. `LiveStatsView` directly rather than through
            // the logger: the flag is the view's, and the hero and the face
            // switcher are two hundred points between a reviewer and the card.
            let lifting = LoggerModel.previewUpperBWithHistory()
            LiveStatsView(
                model: lifting.model, clock: lifting.model, prs: lifting.model,
                onMuscleFocus: {}, startAtLifts: true
            )
            .onyxScreen(.train)
            .environment(LoggerPreviews.environment(over: lifting.store))
            .preferredColorScheme(.dark)
        case "logger-paused":
            // A stopped clock — the one state on this screen where the hero's
            // timer is a string rather than a system timer, and the state the
            // Lock Screen has to agree with. Built here rather than reached by a
            // debug flag inside the view, for the same reason the finish sheet
            // is presented by the harness.
            NavigationStack {
                LiveLoggerView(model: .previewUpperB(logged: true, resting: true), paused: true)
            }
            .environment(AppEnvironment.preview)
            .preferredColorScheme(.dark)
        default:
            // Resting, so the shot carries the rest capsule and the contextual
            // "Skip rest" chip — the two pieces of this screen that only exist
            // between sets.
            NavigationStack {
                LiveLoggerView(model: .previewUpperB(logged: true, resting: true))
            }
            .environment(AppEnvironment.preview)
            .preferredColorScheme(.dark)
        }
    }
}

/// Runs `TelemetrySeed` before its content appears, when the launch asked for
/// it — so the first Health read the content makes finds the series there.
/// Without the argument it is the content and nothing else.
private struct TelemetrySeedGate<Content: View>: View {
    /// Runs after the seed and before the content — the finish's prefetch.
    var then: (@Sendable () async -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @State private var ready = !TelemetrySeed.requested

    var body: some View {
        if ready {
            content()
        } else {
            ProgressView("Seeding Health…")
                .task {
                    await TelemetrySeed.run()
                    await then?()
                    ready = true
                }
        }
    }
}
#endif
