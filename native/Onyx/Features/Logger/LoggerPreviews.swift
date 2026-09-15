#if DEBUG
import SwiftUI
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

    @MainActor @ViewBuilder
    static func view(_ screen: String) -> some View {
        switch screen {
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
            let model = LoggerModel.previewUpperB(logged: true)
            NavigationStack {
                LiveLoggerView(model: model)
                    .sheet(isPresented: .constant(true)) {
                        FinishSheet(model: model, onFinish: { _ in true })
                    }
            }
            .environment(AppEnvironment.preview)
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
#endif
