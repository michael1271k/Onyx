#if DEBUG
import SwiftUI
import GRDB
import OnyxCore
import OnyxData

/// Seeded history screens for `#Preview` and `scripts/native-shot.sh`.
///
/// Six weeks of a Chest & Back A day plus one leg day, written straight into
/// an in-memory store. The last session carries a real record — 42 kg on the
/// incline press clears the asserted 40 kg / 53.3 e1RM floor in `PrTruth` —
/// so the report has a trophy to draw without anyone hand-marking a row.
enum HistoryPreviews {
    static let userId = "00000000-0000-0000-0000-000000000001"
    static let lastSession = "s-2026-09-01"
    /// The four shapes a unilateral pair can take, in one card — the session
    /// `session-pairs-merged` is reviewed from.
    ///
    /// ── WHY IT IS A SESSION OF ITS OWN, AND WHY IT IS DATED 15 JULY ─────────
    /// Every pair already in this fixture is `(5, r)` against `(5, r - 1)`, so
    /// all of them are `valueSplit` and NONE of them carry a rating — the two
    /// cases W1's ledger rule is mostly about could not be photographed, and
    /// making one of them photographable by editing a rep would move a tonnage
    /// three other shots are pictures of.
    ///
    /// 15 July is the plan's own first day: before every other session here, so
    /// it changes no week that is photographed for its totals, and inside
    /// `Week 0 · Transition` — a PEAK block, which is the second phase colour
    /// the Library shot needs to show that its sections are grouped at all.
    static let pairShapes = "s-2026-07-15"
    /// A day that is ONLY a bout — the card W4 is reviewed from.
    ///
    /// The Sunday AFTER the photographed block, deliberately: every other
    /// screen in this harness is pinned inside 30 August – 5 September, so a
    /// session here cannot add a row to a week another shot is a picture of.
    static let treadmillOnly = "s-2026-09-06"
    static let incline = ExerciseCatalogEntry(id: "ex-incline", name: "Incline DB Press", setCount: 24, lastTrained: "2026-09-01")

    /// The same environment with some Train sections already put away, for the
    /// one shot that is about what the Customize sheet DOES.
    ///
    /// Written to the store rather than seeded on the view: `WorkoutWeek` reads
    /// the arrangement out of `dashboard_layouts` in the same detached pass as
    /// everything else, and a seed on the view would photograph a path the app
    /// does not take.
    @MainActor
    static func hidden<Content: View>(
        _ environment: AppEnvironment, _ sections: [TrainSection],
        @ViewBuilder content: (AppEnvironment) -> Content
    ) -> some View {
        let layout = sections.reduce(TrainLayout.default) { $0.setting($1, visible: false) }
        try? environment.database.saveTrainLayout(userId: environment.database.localUserId(), layout)
        return content(environment)
    }

    @MainActor
    static func environment() -> AppEnvironment {
        let database = try! AppDatabase.inMemory(deviceId: "shot")
        // The catalogue as rows (W2): decks, plans, phases, rungs.
        PreviewCatalogue.seed(database)
        try! database.seedRows(seed)
        return AppEnvironment(
            database: database,
            supabase: OnyxSupabase.makeClient(config: SupabaseConfig(url: URL(string: "https://preview.invalid")!, anonKey: "preview"))
        )
    }

    @MainActor @ViewBuilder
    static func view(_ screen: String) -> some View {
        switch screen {
        case "session":
            NavigationStack { SessionDetailView(sessionId: lastSession) }.environment(environment())
        case "session-ledger":
            // The same page, parked at the bottom. Half of §5.4 is the ledger,
            // and a shot of the top half reviews only the half that fits.
            NavigationStack { SessionDetailView(sessionId: lastSession, startAtLedger: true) }
                .environment(environment())
        // §U4.4's flip, opened. A sheet cannot be photographed by launching
        // the screen under it, so the harness presents it directly — the same
        // trick `day-swap` uses, and the reason `Presenting` exists.
        // ── W2 (refinement): row 2, swapped in place ────────────────────────
        // The twin of `session-ledger`, and the pair IS the review: tapping the
        // muscle chip replaces the readings with the assisting muscles, and the
        // claim is that nothing else on the card moves. Two shots at the same
        // scroll position is the only way to see a height that did not change.
        case "session-ledger-assists":
            NavigationStack {
                SessionDetailView(sessionId: lastSession, startAtLedger: true, startWithAssists: true)
            }
            .environment(environment())
        // ── THE TWO SECONDS `session-ledger` CANNOT PHOTOGRAPH (W10) ───────
        // The record row's margin is shown on arrival and taken away again,
        // and the shot script sleeps eight seconds before it presses the
        // shutter. Same page, same scroll position, margins held — the pair is
        // the review, exactly as `session-ledger-assists` is for row 2.
        case "session-margin":
            NavigationStack {
                SessionDetailView(sessionId: lastSession, startAtLedger: true, holdMargins: true)
            }
            .environment(environment())
        case "session-atlas":
            NavigationStack { SessionDetailView(sessionId: lastSession, startAtAtlas: true) }
                .environment(environment())
        // The trophy's sheet, opened from the summary page. Same sheet the live
        // deck shows (`set-row-records`) and deliberately so — but reached
        // through `SessionAnalysis.report`, which is the half this shot exists
        // to review: the beaten baselines are recomputed from the ledger here,
        // not read back out of `personal_records`, which no longer holds them.
        case "session-records":
            NavigationStack { SessionDetailView(sessionId: lastSession, startAtRecord: true) }
                .environment(environment())
        // ── W4: the pair table, with something to compare against ───────────
        // 2 September rather than 1 September, parked at the ledger. Single Arm
        // Lateral Raise is the only unilateral movement in this seed, and this
        // is the session where it moved most — 5 kg × 21/22 against the
        // previous week's 16/15 — so `.pair`'s shared delta has something to
        // say on both of its rows instead of reserving a blank twice.
        case "session-pairs":
            NavigationStack { SessionDetailView(sessionId: "s-2026-09-02", startAtLedger: true) }
                .environment(environment())
        // ── W1 (refinement): all four pair shapes on one card ───────────────
        // See `pairShapes` for what each of the four sets is for. `session-pairs`
        // is the twin and the pair IS the review: that one still splits every
        // value line, because its two sides genuinely lifted different numbers,
        // and nothing about a merge may make two unequal sides look equal.
        case "session-pairs-merged":
            NavigationStack { SessionDetailView(sessionId: pairShapes, startAtLedger: true) }
                .environment(environment())
        // ── W4: the card the treadmill brief is actually about ──────────────
        // A day with no lift on it: nothing to give the page a rail, a family
        // hue or a muscle chip, and all five of `headerTags`' strength capsules
        // guarded off. The whole session fits one screen, so it is shot from
        // the top rather than parked at the ledger.
        case "session-cardio":
            NavigationStack { SessionDetailView(sessionId: treadmillOnly) }
                .environment(environment())
        // §U4.5's edit mode, re-opened on the logger's own deck. It is the ONLY
        // way to see the edit hero — a shot script can launch a screen and
        // cannot press a toolbar button.
        //
        // The LEG day, not `lastSession`, and now only by habit: `canEdit` used
        // to refuse any session holding L/R pairs, which every Chest & Back
        // session in this fixture does, so the Upper A shot photographed a
        // disabled button. That gate is gone (the logger carries `side` and
        // `pairId` and has for some time — see `SessionDetailView.canEdit`), so
        // either day shoots now. Left on the leg day so the shot is comparable
        // with the ones already in `docs/shots`.
        case "session-edit", "logger-edit":
            NavigationStack { SessionDetailView(sessionId: "s-2026-08-30", startAtEditor: true) }
                .environment(environment())
        case "exercise-history":
            // The HISTORY segment — the two-column set grid §W7 rebuilt. The
            // Summary segment is `exercise`.
            NavigationStack {
                ExerciseDetailView(entry: incline, siblings: PreviewHarness.sampleExercises, startOnHistory: true)
            }
            .environment(environment())
        case "train":
            // ── WHY THE DATE IS PINNED ──────────────────────────────────────
            // The This-week panel is a picture of a WEEK, so a shot taken on a
            // Monday and a shot taken on a Friday differ in six cells and the
            // visual diff becomes a diff of the calendar. `2026-09-03` is the
            // Thursday of the seeded week: three sessions behind it, Upper B
            // ahead, and a cardio bout on the Tuesday.
            // ── AND WHY THE DAY IS `cb_a` AND NOT `cb_b` ────────────────────
            // Every session this fixture seeds carries `day_key = "cb_a"` (see
            // the `chestBack` loop below). The plan card now prints the top set
            // from the last session of the SAME split, so a card seeded as
            // `cb_b` had no history to draw on and photographed a column of
            // exercise names with nothing beside them — the empty state, in the
            // one shot the feature is reviewed from.
            //
            // Seeding the split the fixture actually holds is the smaller fix
            // than teaching the fixture a second one, and the shot loses
            // nothing: the week strip, the doors and the footer are the same
            // either way.
            NavigationStack {
                WorkoutTabView(seededDay: PlanTemplates.program("onyx5")?.day(key: "cb_a"), seededToday: "2026-09-03")
            }
            .environment(environment())
        case "train-done":
            // The day AFTER it was logged — `2026-09-02` is the Wednesday the
            // `train` shot's plan card offers to reopen. It is the only state
            // the Train tab draws `SessionHeaderCard` in, and the state a tab
            // spends the rest of every training day in.
            NavigationStack {
                WorkoutTabView(seededDay: PlanTemplates.program("onyx5")?.day(key: "cb_a"), seededToday: "2026-09-02")
            }
            .environment(environment())
        // ── W5: the cardio card, reachable ──────────────────────────────────
        // The card is the last thing on a REST day — `progressionCard` is
        // keyed on today's split and a rest day has none — so at AX5 it is
        // three screens below the fold and `train-empty`'s shot is a picture of
        // a rest card. On a training day the progression box sits under it and
        // this anchor would park on that instead.
        // `.defaultScrollAnchor` rides the ENVIRONMENT down to the tab's own
        // `ScrollView`, so the harness can park it at the bottom without the
        // screen growing a seed for it — which is the whole reason the bout's
        // capsules and the Zone-2 caption have never been reviewed at an
        // accessibility size.
        case "train-cardio":
            NavigationStack { WorkoutTabView(seededToday: "2026-09-05") }
                .defaultScrollAnchor(.bottom)
                .environment(environment())
        // ── W5: the same Wednesday, caught before the masthead lands ────────
        // `SessionAnalysis.headers` is a career-wide walk, and on this fixture
        // it finishes faster than the screenshot — so the stand-in is a state
        // no shot has ever photographed, which is how it stayed a grey box
        // through four waves. `seededHeaderPending` holds it there. Everything
        // else on the screen is `train-done`'s, so the pair IS the review: the
        // two cards have to differ in what they say and in nothing else.
        case "train-pending":
            NavigationStack {
                WorkoutTabView(
                    seededDay: PlanTemplates.program("onyx5")?.day(key: "cb_a"),
                    seededToday: "2026-09-02",
                    seededHeaderPending: true
                )
            }
            .environment(environment())
        case "train-empty":
            // A REST day: no session card, no footer CTA, and the cardio card
            // sits where the deck would be — which is the only way to
            // photograph it in full, and the state a Wednesday actually is.
            // `2026-09-05` is the seeded block's Saturday.
            NavigationStack {
                WorkoutTabView(seededToday: "2026-09-05")
            }
            .environment(environment())
        // ── W6 (next-gen): the morning the old delta lied ───────────────────
        // Monday 7 September: the first weekday of a week with NOTHING in it,
        // standing behind the fixture's fullest one. This is the exact state
        // the Trends door used to print a full week as a loss in — the old rule
        // subtracted all of 30 Aug–5 Sep from a week two days old and reported
        // −13.0 t. What it now prints is one day against one day.
        //
        // Not 31 August, which is the Monday the first cut of this shot used
        // and is the wrong picture: that week already holds a Sunday session,
        // so the tab was photographed mid-week with a full panel above it.
        case "train-monday":
            NavigationStack { WorkoutTabView(seededToday: "2026-09-07") }
                .environment(environment())
        // ── W1 (refinement): the shelf of closed weeks ──────────────────────
        // `train-past` and `train-past-open` were here and are gone with the
        // section they photographed — a harness screen for deleted code is a
        // picture of nothing that still takes a shot to review.
        //
        // Presented as a REAL sheet, the trick `train-wrap` and `train-week`
        // use: a shot script cannot press a toolbar button, and the whole of
        // what this wave moved is what the sheet looks like when it opens.
        case "train-library":
            PresentingWeek(today: "2026-09-03") { week in
                PastWeeksLibrary(week: week, program: week.snapshot.program)
            }
            .environment(environment())
        // One banner tapped — the wrap-up over the shelf, which is the state
        // the old expanding row was drawn INSIDE the tab for. 16 August is the
        // one week in this seed that closed complete, so it has a progression,
        // a regression and a PR in it: the same week `train-wrap` photographs
        // from the This-week tile, which makes the pair the review — two routes
        // to one sheet, drawing the same figures.
        case "train-library-open":
            PresentingWeek(today: "2026-09-03") { week in
                PastWeeksLibrary(
                    week: week, program: week.snapshot.program, seededOpen: "2026-08-16"
                )
            }
            .environment(environment())
        // ── W6 (next-gen): the tab with three sections put away ─────────────
        // Two things at once, and the second is why it is bottom-anchored.
        //
        // The FEATURE: a Customize sheet is a picture of switches; this is a
        // picture of what they do. Cardio, Ready to Progress and Past Weeks are
        // off, and the page is the four things left.
        //
        // The LAYOUT: the Trends door carries a sentence now and the sentence
        // is the half of the wave that most needs eyes — and on the full tab it
        // sits under a seven-exercise plan card, below the fold, behind the
        // footer, in every anchor a shot can ask for. With the sections below
        // it gone it IS the bottom of the page, so the caption is finally in a
        // frame.
        case "train-customized":
            hidden(environment(), [.cardio, .progression, .pastWeeks]) { environment in
                NavigationStack {
                    WorkoutTabView(seededDay: PlanTemplates.program("onyx5")?.day(key: "cb_a"), seededToday: "2026-09-03")
                }
                .defaultScrollAnchor(.bottom)
                .environment(environment)
            }
        // ── W6 (next-gen): the long press, said in words ────────────────────
        // A sheet cannot be photographed by launching the screen under it and a
        // shot script cannot hold a finger down, so the harness presents it
        // directly — the same trick `train-week` uses. The writes are swallowed:
        // the shot is of the SWITCHES, and a preview that mutated a store would
        // photograph a different arrangement on the second run.
        case "train-customize":
            PresentingWeek(today: "2026-09-03") { _ in
                CustomizeTrainSheet(layout: .default, set: { _, _ in })
            }
            .environment(environment())
        // ── W6: the week sheet, opened ──────────────────────────────────────
        // A sheet cannot be photographed by launching the screen under it, so
        // the harness presents it directly — the same trick `day-swap` and
        // `session-atlas` use. Pinned to the same Thursday as `train`, so the
        // seven rows in the shot are the seven cells in that one.
        case "train-week":
            PresentingWeek(today: "2026-09-03") { WeekOverrideSheet(week: $0) }
                .environment(environment())
        // ── W6: the wrap-up. W4: the REPORT it became ───────────────────────
        // The summary is seeded rather than read: the shot's job is the LAYOUT
        // — a week with a progression, a regression and a PR in it — and the
        // engine behind it has its own unit suite. Building a fixture whose
        // four planned days all happen to be logged would make this shot
        // hostage to the seed.
        //
        // Pushed rather than presented since W4, which is also why it is no
        // longer wrapped in `PresentingWeek`: there is no sheet to photograph
        // the 560 pt fold of, and a `NavigationStack` around the page is what
        // every one of the four doors now puts it in.
        //
        // The page BELOW the band is read for real, off the preview store —
        // see `WeekReportView.task`. `train-report` is the seeded twin, for
        // the blocks a preview store may answer nothing for.
        case "train-wrap":
            NavigationStack { WeekReportView(summary: wrapSummary, program: wrapProgram) }
                .environment(environment())
        // The half below the fold. It was the `.large` detent and it is the
        // bottom of a scroll view now — a shot cannot scroll any more than it
        // could drag, and `defaultScrollAnchor` is the same trick
        // `train-customized` already uses to photograph the end of a page.
        case "train-wrap-large":
            NavigationStack { WeekReportView(summary: wrapSummary, program: wrapProgram) }
                .defaultScrollAnchor(.bottom)
                .environment(environment())
        case "train-wrap-deload":
            NavigationStack { WeekReportView(summary: deloadSummary, program: wrapProgram) }
                .environment(environment())
        // ── W4: the report with its lower half GUARANTEED ───────────────────
        // `train-wrap` reads the export payload out of the preview store, which
        // is the honest end-to-end shot and is also why it cannot be the only
        // one: a store that answers with no graded day, no record and no
        // working set photographs four empty sections and looks exactly like a
        // page whose builder is broken. This one hands `WeekReport` over
        // directly, so the rails, the dots, the trophies and the roles are in
        // frame whatever the seed does.
        case "train-report":
            NavigationStack {
                WeekReportView(
                    summary: wrapSummary, program: wrapProgram, seeded: previewReport
                )
            }
            .environment(environment())
        // The seeded report's LOWER half — the two charts, the macro table and
        // the flagged micronutrients. `train-wrap-large` is the same anchor
        // over the real store, which answers "nothing tracked" for this week
        // and so photographs the empty notes rather than the instruments.
        case "train-report-large":
            NavigationStack {
                WeekReportView(
                    summary: wrapSummary, program: wrapProgram, seeded: previewReport
                )
            }
            .defaultScrollAnchor(.bottom)
            .environment(environment())
        case "share-card":
            // The 9:16 composition on its own, so the thing that leaves the
            // phone is reviewed as a whole rather than as a thumbnail inside a
            // share sheet.
            //
            // SCALED TO FIT, and that is the point: the card is a fixed 540×960
            // and a 402 pt screen is not, so drawing it at its own size
            // photographs the middle third of it. The first run of this shot
            // came out with the headline sheared off the left edge and read as
            // a layout bug in the card, which it was not.
            GeometryReader { proxy in
                WeeklyShareCard(
                    summary: wrapSummary,
                    program: PlanTemplates.program("onyx5") ?? Program(id: "", label: "Onyx 5", days: []),
                    showBodyweight: true
                )
                .scaleEffect(min(proxy.size.width / 540, proxy.size.height / 960))
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()
            .background(Color.black)
        case "library":
            NavigationStack { ExerciseLibraryView(seeded: PreviewHarness.sampleExercises) }
                .environment(environment())
        case "history-week":
            // The seeded block's last full week — the one holding both the
            // Tuesday cardio and the Wednesday swap, so the day rows show a
            // logged day, a swapped day and a rest day in one photograph.
            NavigationStack {
                WeekDaysView(window: WeekWindow(containing: "2026-09-02", startDay: 0))
            }
            .environment(environment())
        case "history-week-wrapped":
            // A week that CLOSED as a wrap — 16–22 August, every planned day
            // logged (`wrappedWeek`). The only week in this seed that satisfies
            // `WeeklyWrap.isWrapped`, and therefore the only one whose chip row
            // carries the wrap door. Three weeks behind the photographed week,
            // which is the point of decision 8: the wrap stops being news that
            // expires.
            NavigationStack {
                WeekDaysView(window: WeekWindow(containing: "2026-08-18", startDay: 0))
            }
            .environment(environment())
        case "history-week-wrap-open":
            // Decision 8, photographed: a week that closed three weeks ago,
            // opening the same report the Train tab opens on a Sunday night.
            PresentingWrap(weekStart: "2026-08-16").environment(environment())
        case "history-week-live":
            // ── THE LOCKED EXPORT NEEDS A WEEK THAT HAS NOT CLOSED ──────────
            // `weekIsComplete` reads `environment.today`, which is the app's
            // one answer to what day it is and has no harness override — so the
            // only way to photograph the disabled chip is to ask for the week
            // the machine is actually standing in. The date inside the chip
            // therefore moves from week to week in this shot, which is what a
            // live week is; nothing else in the frame does.
            NavigationStack {
                WeekDaysView(window: WeekWindow(containing: LogicalDay.today(), startDay: 0))
            }
            .environment(environment())
        default:
            NavigationStack { HistoryView() }.environment(environment())
        }
    }

    // MARK: - Seed

    private static let exercises: [(id: String, name: String)] = [
        ("ex-incline", "Incline DB Press"),
        ("ex-pulldown", "Lat Pulldown"),
        ("ex-row", "Seated Cable Row (Wide Grip)"),
        ("ex-raise", "Single Arm Lateral Raise"),
        ("ex-hkr", "Hanging Knee Raise"),
        ("ex-hack", "Hack Squat"),
        ("ex-treadmill", "Treadmill"),
    ]

    /// (weight, reps) per working set, per session, oldest first.
    private static let chestBack: [(date: String, incline: [(Double, Int)], pulldown: [(Double, Int)], row: [(Double, Int)], raise: [(Double, Int)])] = [
        ("2026-07-28", [(36, 10), (36, 9), (36, 8)],   [(55, 12), (55, 11), (55, 10)], [(45, 12), (45, 12), (45, 11)], [(5, 12), (5, 12)]),
        ("2026-08-04", [(36, 12), (36, 11), (36, 10)], [(55, 12), (55, 12), (55, 11)], [(45, 13), (45, 12), (45, 12)], [(5, 13), (5, 12)]),
        ("2026-08-11", [(38, 10), (38, 9), (38, 9)],   [(60, 10), (60, 10), (60, 9)],  [(47.5, 12), (47.5, 11), (47.5, 10)], [(5, 14), (5, 13)]),
        ("2026-08-18", [(38, 12), (38, 11), (38, 10)], [(60, 12), (60, 11), (60, 10)], [(47.5, 13), (47.5, 12), (47.5, 12)], [(5, 15), (5, 14)]),
        ("2026-08-25", [(40, 10), (40, 10), (40, 9)],  [(60, 12), (60, 12), (60, 12)], [(50, 12), (50, 11), (50, 10)], [(5, 15), (5, 15)]),
        ("2026-09-01", [(42, 10), (42, 9), (40, 12)],  [(65, 10), (65, 10), (65, 9)],  [(50, 13), (50, 12), (50, 12)], [(5, 16), (5, 15)]),
        // Swapped onto the Wednesday rest slot — which is also what makes the
        // Workout tab's Ready-to-progress box non-empty: the wide-grip row has
        // now cleared its 10–12 window at 50 kg TWICE, and the lateral raise has
        // cleared its 15–20 window once. One green row, one gold.
        ("2026-09-02", [(42, 11), (42, 10), (42, 10)],  [(65, 11), (65, 10), (65, 10)], [(50, 12), (50, 13), (50, 12)], [(5, 21), (5, 22)]),
    ]

    /// The scale, most mornings of the photographed week and the one before it.
    ///
    /// ── WHY THE SEED GREW A SCALE (W1b) ─────────────────────────────────────
    /// `WeekVitalsRow` has drawn eight cells since §5.9 and six of them have
    /// always photographed as `—`, because nothing here ever wrote a
    /// `body_composition` row. That was survivable while the cells were small.
    /// The week hero prints the weekly MEAN weight and the fat delta at 20 pt,
    /// and a hero of two dashes is a hero that cannot be reviewed.
    ///
    /// Four readings in the week and two before it: enough for a mean that is
    /// not just the last reading, and enough for the delta's own `>= 2` gate on
    /// both sides. A gap on the Thursday is deliberate — the mean must be over
    /// the readings that exist, not over seven days.
    private static let weighIns: [(date: String, kg: Double, fat: Double)] = [
        ("2026-08-16", 84.6, 19.8),
        ("2026-08-19", 84.3, 19.7),
        ("2026-08-21", 84.1, 19.6),
        ("2026-08-24", 83.9, 19.4),
        ("2026-08-27", 83.6, 19.3),
        ("2026-08-30", 83.4, 19.2),
        ("2026-08-31", 83.1, 19.0),
        ("2026-09-02", 82.9, 18.9),
        ("2026-09-04", 82.6, 18.7),
    ]

    /// A week that WRAPPED, so the wrap chip has a door to open (W1b).
    ///
    /// `WeeklyWrap.isWrapped` asks that every planned DAY of the week hold a
    /// finished session, and no other week in this seed satisfies it — least of
    /// all the photographed week of 30 August, which deliberately misses two,
    /// because a week with a hole in it is the state a history screen exists to
    /// show. Onyx-5 plans Sunday, Monday, Tuesday, Thursday and Friday; the
    /// Tuesday of 16–22 August is already here in `chestBack`, and these are
    /// the other four.
    ///
    /// No incline press and no load above what the later sessions reach, so the
    /// record book and the e1RM trend the other previews photograph are
    /// untouched. The two hack squats are first-of-their-kind and file a PR
    /// each, which is what gives the wrap a trophy to count.
    private static let wrappedWeek: [(date: String, key: String, sets: [(String, Double, Int)])] = [
        ("2026-08-16", "cb_a",   [("ex-pulldown", 55, 10), ("ex-row", 45, 10)]),
        ("2026-08-17", "legs_a", [("ex-hack", 50, 10)]),
        ("2026-08-20", "cb_b",   [("ex-raise", 5, 12), ("ex-row", 42.5, 10)]),
        ("2026-08-21", "legs_b", [("ex-hack", 52, 10)]),
    ]

    @Sendable
    private static func seed(_ db: Database) throws {
        for e in exercises { try Exercise(id: e.id, name: e.name).insert(db) }

        for w in weighIns {
            let at = LogicalDay.date(fromISO: w.date)!.addingTimeInterval(7 * 3600)
            try BodyCompositionRow(
                id: "bc-\(w.date)", userId: userId, measuredAt: at, date: w.date,
                weightKg: w.kg, bodyFatPct: w.fat, createdAt: at
            ).insert(db)
        }

        for day in wrappedWeek {
            let id = "s-\(day.date)"
            let start = LogicalDay.date(fromISO: day.date)!.addingTimeInterval(17 * 3600)
            try WorkoutSession(
                id: id, userId: userId, dayKey: day.key, date: day.date, startedAt: start,
                endedAt: start.addingTimeInterval(55 * 60), durationMin: 55, sessionRpe: 7
            ).insert(db)
            for (i, set) in day.sets.enumerated() {
                try WorkoutSet(
                    id: "\(id)-\(set.0)-\(i)", sessionId: id, exerciseId: set.0, setIndex: i + 1,
                    weightKg: set.1, reps: set.2,
                    est1rmKg: OneRepMax.estimate(weight: set.1, reps: Double(set.2)), rpe: 7, foldOrder: i
                ).insert(db)
            }
        }


        // ── THE FOUR PAIR SHAPES (§W1 E) ────────────────────────────────
        // One movement, four sets, one of each case `SetPairLayout` can hand
        // the ledger — read top to bottom:
        //
        //   1 · same load, same reps, same rating   → ONE line, one word
        //   2 · same load, same reps, ratings differ → one line, `L 8 · R 9`
        //   3 · reps differ, one side never rated    → two lines, `L 8 · R —`
        //   4 · reps differ, ratings agree           → two lines, one word
        //
        // Set 3 is the state 10 September's pushdown is permanently in: the
        // right side was skipped at the moment of rating and `SetPatch` cannot
        // write a null back, so it stays unrated until that session is edited
        // by hand. The ledger's job is to SAY so, in tertiary ink.
        do {
            let id = pairShapes
            let start = LogicalDay.date(fromISO: "2026-07-15")!.addingTimeInterval(17 * 3600)
            try WorkoutSession(
                id: id, userId: userId, dayKey: "cb_a", date: "2026-07-15", startedAt: start,
                endedAt: start.addingTimeInterval(38 * 60), durationMin: 38, sessionRpe: 7
            ).insert(db)
            let shapes: [(left: Int, right: Int, leftRpe: Double?, rightRpe: Double?)] = [
                (12, 12, 8, 8), (12, 12, 8, 9), (12, 11, 8, nil), (12, 10, 8, 8),
            ]
            for (i, shape) in shapes.enumerated() {
                let pair = "\(id)-raise-\(i)"
                for (side, reps, rpe) in [("left", shape.left, shape.leftRpe),
                                          ("right", shape.right, shape.rightRpe)] {
                    try WorkoutSet(
                        id: "\(id)-raise-\(i)-\(side)", sessionId: id, exerciseId: "ex-raise",
                        setIndex: i + 1, weightKg: 5, reps: reps, side: side, pairId: pair,
                        est1rmKg: OneRepMax.estimate(weight: 5, reps: Double(reps)), rpe: rpe,
                        exerciseOrder: 1, foldOrder: i * 2 + (side == "left" ? 0 : 1)
                    ).insert(db)
                }
            }
        }

        for (n, s) in chestBack.enumerated() {
            let id = "s-\(s.date)"
            let start = LogicalDay.date(fromISO: s.date)!.addingTimeInterval(17 * 3600)
            // ── HEART RATE AND CALORIES, MEASURED ON THE LAST SESSION ───
            // The metric grid has four provenance states and could photograph
            // only one: `SessionPage` hard-coded `avgBpm: nil` and always
            // estimated the calories, so every shot showed "—" and "no weight"
            // and the measured case — the one the watch actually produces, and
            // the one the Calories cell overflowed in — was unreviewable.
            //
            // On the LAST session only, so the grid's own "first of this split"
            // and no-data lines are still reachable on the six behind it.
            let watched = id == lastSession
            try WorkoutSession(id: id, userId: userId, dayKey: "cb_a", date: s.date, startedAt: start,
                               endedAt: start.addingTimeInterval(64 * 60), durationMin: 64, sessionRpe: 7 + Double(n % 2) * 0.5,
                               avgBpm: watched ? 122 : nil, caloriesBurned: watched ? 383 : nil,
                               avgBpmEstimated: false, caloriesEstimated: false).insert(db)
            var order = 0
            // The MOVEMENT's own position, as `LoggerModel.deckOrder` writes it
            // and as the real 7 September rows carry it. The treadmill is 0 and
            // is inserted LAST, so its card being first in the report is the
            // `exercise_order` sort doing its job rather than fold order
            // agreeing with it by accident — which is the whole of what a
            // reorder has to survive.
            let placed = ["ex-treadmill": 0, "ex-incline": 1, "ex-pulldown": 2,
                          "ex-row": 3, "ex-raise": 4, "ex-hkr": 5]
            func set(_ ex: String, _ i: Int, _ w: Double, _ r: Int, type: String = "normal", side: String? = nil, pair: String? = nil, rpe: Double? = nil, rest: Int? = nil) throws {
                try WorkoutSet(id: "\(id)-\(ex)-\(i)\(side ?? "")", sessionId: id, exerciseId: ex, setIndex: i, weightKg: w, reps: r,
                               setType: type, side: side, pairId: pair, est1rmKg: OneRepMax.estimate(weight: w, reps: Double(r)), rpe: rpe,
                               exerciseOrder: placed[ex], actualRestSec: rest, foldOrder: order).insert(db)
                order += 1
            }
            try set("ex-incline", 0, 20, 12, type: "warmup")
            // ── ONE SESSION WHERE IT FELT HARDER (W4) ───────────────────
            // Every RPE in this fixture was `7 + i × 0.5` on every session, so
            // set 2 was rated 7.5 in July and 7.5 in September and the effort
            // column's delta was zero on all six sessions and all three sets.
            // W4's headline claim is that a RISE in RPE renders red, and a
            // fixture that cannot produce a rise cannot photograph it — the
            // same argument the failure set two loops down was added on.
            //
            // The last session is half a rung harder across the board, which
            // is what the reps say happened: 11/10/10 against 10/9/12 at the
            // same load. `session-pairs` is the shot that reviews it.
            let harder = s.date == "2026-09-02"
            // ── THE REST BETWEEN SETS, ON THE LAST SESSION ONLY (W10) ───
            // `actual_rest_sec` is written by the APPEND path alone, so most
            // rows in a real store carry none and the ledger draws nothing at
            // all — which is what the six sessions behind this one photograph.
            // The last one carries three, and they carry the three STATES:
            // set 1 has nothing before it to have rested from (the warm-up
            // above it is unmeasured), set 2 is +35 s and set 3 is +45 s, so
            // both arrows and the no-arrow case are in one card.
            let rests: [Int?] = id == lastSession ? [95, 130, 175] : []
            for (i, (w, r)) in s.incline.enumerated() {
                try set("ex-incline", i + 1, w, r,
                        rpe: (harder ? 7.5 : 7) + Double(i) * 0.5,
                        rest: i < rests.count ? rests[i] : nil)
            }
            // The last set of the pulldown on the session the shot loop opens
            // is taken to FAILURE, which is the only way any screenshot of this
            // app shows the state: nothing else in six weeks of this fixture
            // sits on the top rung of `RpeLadder`, so the `F` badge and the red
            // effort word were unreviewable — and an unreviewable state is one
            // that breaks silently.
            for (i, (w, r)) in s.pulldown.enumerated() {
                let failed = id == lastSession && i == s.pulldown.count - 1
                // Two equal rests, so the SECOND row prints its clock with no
                // arrow — the case a fixture of only-moving rests would hide,
                // and the one that proves the fifteen-second floor is doing
                // something.
                try set("ex-pulldown", i + 1, w, r, rpe: failed ? 10 : 7.5,
                        rest: id == lastSession ? 120 : nil)
            }
            for (i, (w, r)) in s.row.enumerated() { try set("ex-row", i + 1, w, r, rpe: 8) }
            for (i, (w, r)) in s.raise.enumerated() {
                let pair = "\(id)-raise-\(i)"
                try set("ex-raise", i + 1, w, r, side: "left", pair: pair)
                try set("ex-raise", i + 1, w, r - 1, side: "right", pair: pair)
            }
            for i in 0..<2 { try set("ex-hkr", i + 1, 0, 12 + i + n / 2, rpe: 6) }
            // ── THE SET THAT IS NOT REPS AND KILOGRAMS ──────────────────
            // 2026-09-07 opens with one, and it is the only row in the live
            // database using `duration_sec` / `incline` / `distance_km` /
            // `elevation_m`. A fixture without one photographs the fix as an
            // unchanged screen: the ledger's job here is to render
            // `5:00 · 0.37 km · 2% · 7 m` where it used to render `0kg × 0`,
            // and nothing else in six weeks of this seed carries a cardio
            // axis.
            //
            // On the LAST session only, and as a warm-up — the same shape the
            // real row has, so it earns no tonnage, no ordinal and no record,
            // and the other six sessions' arithmetic is untouched.
            //
            // LOGGED LAST, PLACED FIRST. `exercise_order` 0 against a fold
            // order behind every lift, so the report putting its card at the
            // top is `SessionAnalysis.grouped` reading the column rather than
            // first appearance agreeing with it — the one state that tells a
            // reorder apart from a coincidence.
            if id == lastSession {
                try WorkoutSet(
                    id: "\(id)-treadmill", sessionId: id, exerciseId: "ex-treadmill", setIndex: 1,
                    weightKg: 0, reps: 0, setType: "warmup",
                    exerciseOrder: placed["ex-treadmill"],
                    // 7 m of ascent. 0.37 km at 2 % is 7.4 — close, and NOT
                    // where this comes from: the column is measured, and a
                    // fixture that used the product would photograph the one
                    // thing the column exists to disprove.
                    durationSec: 300, incline: 2, distanceKm: 0.37, elevationM: 7,
                    foldOrder: order
                ).insert(db)
                order += 1
            }
        }

        // ── ONE PPL-ERA SESSION ─────────────────────────────────────────────
        // 8 July 2026 is inside the Thailand deload, which `Phases` tags `.ppl`
        // — so History has two eras in it and the era filter is a control with
        // something to do rather than one that can only empty the list. Its day
        // key is not one of Onyx-5's, which is the point: the schedule cannot
        // speak for a week before Week 0, and this week must therefore draw no
        // missed days at all.
        let ppl = "s-2026-07-08"
        let pplStart = LogicalDay.date(fromISO: "2026-07-08")!.addingTimeInterval(17 * 3600)
        try WorkoutSession(id: ppl, userId: userId, dayKey: "push", date: "2026-07-08", startedAt: pplStart,
                           endedAt: pplStart.addingTimeInterval(52 * 60), durationMin: 52, sessionRpe: 7).insert(db)
        for (i, (w, r)) in [(32.0, 12), (32.0, 11), (32.0, 10)].enumerated() {
            try WorkoutSet(id: "\(ppl)-incline-\(i)", sessionId: ppl, exerciseId: "ex-incline", setIndex: i + 1,
                           weightKg: w, reps: r, est1rmKg: OneRepMax.estimate(weight: w, reps: Double(r)), rpe: 7, foldOrder: i).insert(db)
        }

        // One leg day, so the list has a second colour and Hack Squat a ledger.
        let legs = "s-2026-08-30"
        let start = LogicalDay.date(fromISO: "2026-08-30")!.addingTimeInterval(17 * 3600)
        try WorkoutSession(id: legs, userId: userId, dayKey: "legs_a", date: "2026-08-30", startedAt: start,
                           endedAt: start.addingTimeInterval(58 * 60), durationMin: 58, sessionRpe: 8).insert(db)
        for (i, (w, r)) in [(60.0, 12), (60.0, 11), (60.0, 10)].enumerated() {
            try WorkoutSet(id: "\(legs)-hack-\(i)", sessionId: legs, exerciseId: "ex-hack", setIndex: i + 1, weightKg: w, reps: r,
                           est1rmKg: OneRepMax.estimate(weight: w, reps: Double(r)), rpe: 8, foldOrder: i).insert(db)
        }

        // ── A DAY THAT IS ONLY A BOUT (W4) ──────────────────────────────────
        // Every treadmill row in this seed until now rode along on a full chest
        // day, which is the one shape that HIDES what F6 found: the card's
        // family hue, its muscle chips and its tag row all look fine when four
        // lifts either side of it are supplying the page's colour. Alone on a
        // page they are the page.
        //
        // No `day_key`: a walk is not one of Onyx-5's five days, and inventing
        // one would put this session on a split's progression line.
        let walkStart = LogicalDay.date(fromISO: "2026-09-06")!.addingTimeInterval(8 * 3600)
        try WorkoutSession(
            id: treadmillOnly, userId: userId, date: "2026-09-06",
            startedAt: walkStart, endedAt: walkStart.addingTimeInterval(38 * 60),
            durationMin: 38, avgBpm: 118, caloriesBurned: 214,
            avgBpmEstimated: false, caloriesEstimated: false
        ).insert(db)
        try WorkoutSet(
            id: "\(treadmillOnly)-treadmill", sessionId: treadmillOnly,
            exerciseId: "ex-treadmill", setIndex: 1,
            // A warm-up, exactly as the 7 September row is: that is what keeps
            // a walk out of tonnage and out of the PR engine, and it is why
            // `Top` and `Volume` are absent from the header rather than zero.
            weightKg: 0, reps: 0, setType: "warmup",
            exerciseOrder: 0,
            durationSec: 2280, incline: 1, distanceKm: 3.6, elevationM: 24,
            foldOrder: 0
        ).insert(db)
        // The bout Apple Health filed against it — the ONLY place this card's
        // heart rate and its "Automatically logged" badge can come from, since
        // `workout_sets` carries neither. See `SessionAnalysis.Page.bout`.
        try CardioLogRow(
            id: "c-walk", userId: userId, date: "2026-09-06", kind: "walk",
            distanceM: 3600, durationMin: 38,
            fromHealthkit: true, createdAt: walkStart,
            avgHr: 118, sessionId: treadmillOnly, inclinePct: 1, elevationM: 24
        ).insert(db)

        // The record book as the save path would have filed it.
        for (axis, value, w, r) in [("weight", 42.0, 42.0, 10), ("e1rm", 56.0, 42.0, 10), ("volume", 480.0, 40.0, 12)] {
            try PersonalRecordRow(userId: userId, exerciseKey: "Incline DB Press", axis: axis, value: value, reps: r, weightKg: w,
                                  sessionId: lastSession, achievedOn: "2026-09-01", updatedAt: Date()).insert(db)
        }

        // Five bouts, so the Workout tab's cardio trail has something to draw
        // and the last one carries every figure the card can print. Two of them
        // clear `Zone2.minMinutes`, which is what makes the rail read 2/2 on a
        // week that earned it.
        let bouts: [(String, String, Double, Double, Double, Double)] = [
            ("c-5", "2026-08-22", 3200, 32, 121, 6),
            ("c-4", "2026-08-25", 2400, 22, 118, 8),
            ("c-3", "2026-08-28", 1600, 14, 124, 10),
            ("c-2", "2026-08-31", 4100, 38, 126, 4),
            ("c-1", "2026-09-01", 1800, 15, 131, 10),
        ]
        for (id, date, distance, minutes, hr, incline) in bouts {
            try CardioLogRow(
                id: id, userId: userId, date: date, kind: "treadmill",
                distanceM: distance, durationMin: minutes,
                fromHealthkit: false, createdAt: Date(),
                avgHr: hr,
                sessionId: id == "c-1" ? lastSession : nil,
                inclinePct: incline
            ).insert(db)
        }
    }
}

/// A week with one of everything in it: a progression, a regression, a PR, a
/// movement that held, and an unloaded movement with no estimate at all.
@MainActor
private var wrapSummary: WeeklyWrap.Summary {
    WeeklyWrap.Summary(
        weekStart: "2026-08-30", sessions: 5, tonnageKg: 42_180, tonnageDeltaKg: 1_240,
        prCount: 2, isDeload: false,
        movements: [
            .init(name: "Incline DB Press", dayKey: "cb_a", weightKg: 42, reps: 11, e1rm: 57.4, previousE1rm: 53.3),
            .init(name: "Lat Pulldown", dayKey: "cb_a", weightKg: 80, reps: 4, e1rm: 90.7, previousE1rm: 88),
            .init(name: "Leg Press", dayKey: "legs_a", weightKg: 70, reps: 15, e1rm: 105, previousE1rm: 110),
            .init(name: "Seated Cable Row", dayKey: "cb_a", weightKg: 40, reps: 12, e1rm: 56, previousE1rm: 52),
            .init(name: "Side Plank", dayKey: "legs_a", weightKg: 0, reps: 61),
        ],
        bodyweightKg: 64.2, bodyweightDeltaKg: -0.4,
        muscle: wrapMuscle,
        topSession: .init(dayKey: "legs_a", date: "2026-09-04", volumeKg: 12_480),
        // `Week.label(ofWeekStart: "2026-08-30", anchor: "2026-07-12", …)` — the
        // number the BUILDER would have answered for this week (§W3). A hand-
        // built summary is the one shape that can carry no label, and this shot
        // would otherwise photograph the date fallback on a fixture standing in
        // for a real week.
        label: "Week 7"
    )
}

/// The report's lower half as a fixture — the eight sections `WeekReportView`
/// reads out of `WeeklyExportBuilder`, handed over directly.
///
/// The numbers are the same week `wrapSummary` describes and are consistent
/// with it on purpose: 5 sessions of 5 planned, and the four hits of six graded
/// days are the 67 % adherence capsule. A fixture whose capsule disagreed with
/// its own strip would make every shot of this screen a puzzle about which half
/// to believe.
///
/// ── AND WHY IT CARRIES A CASE OF EVERY SHAPE (W8) ───────────────────────────
/// `train-wrap` reads a real store and photographs whatever the seed holds.
/// This one exists so that the shapes a section can only draw ONCE — a micro
/// over its ceiling, a scan with a body-fat reading, a week with more records
/// than the cap — are in frame on purpose rather than by luck.
@MainActor
private var previewReport: WeekReport {
    let days = ["2026-08-30", "2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05"]
    let verdicts: [AdherenceVerdict] = [.hit, .hit, .miss, .hit, .exception, .hit, .miss]
    let kcal: [Double] = [2_010, 1_980, 2_460, 1_950, 2_720, 2_005, 2_310]
    let sleepHours: [Double] = [7.4, 7.9, 6.2, 8.1, 7.0, 6.6, 7.7]
    let volume: [(LandmarkMuscle, Double, Int)] = [
        (.chest, 11, 10), (.lats, 9, 10), (.upperBack, 8, 8), (.lowerBack, 4, 4),
        (.frontDelts, 5, 6), (.sideDelts, 9, 8), (.rearDelts, 4.5, 6),
        (.biceps, 7, 8), (.triceps, 8, 8), (.forearms, 2, 4),
        (.quads, 12, 12), (.hamstrings, 7, 8), (.glutes, 6, 8),
        (.adductors, 0, 0), (.calves, 2, 6), (.absCore, 3, 6),
    ]
    return WeekReport(
        phaseKind: .cut,
        eraTag: "Onyx Cut",
        rangeLabel: "30 Aug – 5 Sep",
        sleepScoreAvg: 71,
        batteryAvg: 74,
        nutritionAdherencePct: 66.7,
        sessions: 5,
        plannedSessions: 5,
        tonnageKg: 42_180,
        tonnageDeltaKg: 1_240,
        prCount: 4,
        tonnageSpark: [38_400, 39_900, 40_100, 39_200, 40_940, 42_180],
        bodyweightKg: 82.4,
        bodyweightDeltaKg: -0.4,
        bodyFatPct: 17.2,
        muscleMassKg: 36.8,
        scanDate: "2026-09-01",
        volumeByMuscle: volume.map {
            OnyxSnapshot.MuscleVolume(muscle: $0.0.rawValue, sets: $0.1, target: $0.2)
        },
        topMuscles: [.quads, .chest, .sideDelts, .lats],
        strongest: TopLifts.group(
            [
                .init(exercise: "Leg Press", kg: 170, reps: 10, rpe: 9),
                .init(exercise: "Incline DB Press", kg: 42, reps: 11, rpe: 8),
            ],
            previous: [:]
        ),
        adherence: zip(days, verdicts).map { date, verdict in
            AdherenceDay(date: date, verdict: verdict, kcalPct: 98, proteinPct: 104, estimated: false)
        },
        kcalByDay: zip(days, kcal).map { OnyxSnapshot.Point(d: $0, v: $1) },
        kcalTarget: 2_050,
        macroTable: [
            .init(label: "Calories", mean: 2_205, target: 2_050, unit: "kcal"),
            .init(label: "Protein", mean: 176, target: 170, unit: "g"),
            .init(label: "Carbs", mean: 191, target: 206, unit: "g"),
            .init(label: "Fat", mean: 62, target: 55, unit: "g"),
        ],
        flaggedMicros: [
            .init(label: "Sodium", value: 4_120, target: 3_000, unit: "mg",
                  kind: .ceiling, pct: 137, doubted: false),
            .init(label: "Magnesium", value: 268, target: 400, unit: "mg",
                  kind: .floor, pct: 67, doubted: false),
            .init(label: "Calcium", value: 741, target: 1_000, unit: "mg",
                  kind: .floor, pct: 74, doubted: true),
        ],
        waterMlPerDay: 2_640,
        waterGoalMl: 3_000,
        sleepByDay: zip(days, sleepHours).map { OnyxSnapshot.Point(d: $0, v: $1) },
        sleepGoalHours: 8,
        batterySpark: [68, 72, 61, 79, 74, 70, 81],
        stressMean: 2.6,
        domsPeak: .init(muscle: "Quads", severity: 4, date: "2026-09-02"),
        cardio: .init(bouts: 3, minutes: 96, km: 9.4, kcal: 640, kinds: ["Walk", "Run"]),
        // FOUR, one past the cap: the disclosure is in frame, which is the one
        // thing a three-record fixture could never photograph.
        records: [
            ExportPr(name: "Incline DB Press", weightKg: 42, reps: 11, axes: [.weight, .e1rm]),
            ExportPr(name: "Leg Press", weightKg: 170, reps: 10, axes: [.volume]),
            ExportPr(name: "Seated Cable Row", weightKg: 40, reps: 12, axes: [.volume]),
            ExportPr(name: "Standing Calf Raise", weightKg: 90, reps: 15, axes: [.reps]),
        ]
    )
}

private var wrapProgram: Program {
    PlanTemplates.program("onyx5") ?? Program(id: "", label: "Onyx 5", days: [])
}

/// A week with every case the ring has to survive in it: a dominant family, a
/// family at half a set that has to be floored to stay visible, and two
/// landmarks at zero whose family therefore draws no arc at all and has to be
/// named in words instead.
private var wrapMuscle: MuscleFocusSummary {
    let week: [(LandmarkMuscle, Double, Int)] = [
        (.chest, 5, 10), (.lats, 4, 8), (.upperBack, 3, 6), (.lowerBack, 1, 4),
        (.frontDelts, 2, 6), (.sideDelts, 4, 8), (.rearDelts, 1.5, 6),
        (.biceps, 3, 8), (.triceps, 4, 8), (.forearms, 0.5, 4),
        (.quads, 6, 10), (.hamstrings, 4, 8), (.glutes, 3, 8),
        (.adductors, 0, 0), (.calves, 0, 6), (.absCore, 0, 6),
    ]
    return MuscleFocusSummary(
        weekStart: "2026-08-30",
        rows: week.map { MuscleFocusRow(muscle: $0.0, sets: $0.1, target: $0.2) }
    )
}

/// The same week, declared a deload — every drop relabelled, nothing in red.
@MainActor
private var deloadSummary: WeeklyWrap.Summary {
    var out = wrapSummary
    out.isDeload = true
    out.tonnageDeltaKg = -6_400
    out.prCount = 0
    return out
}

/// The week detail with its wrap door already open (W1b).
///
/// The `Summary` comes from `WorkoutWeek.wrap(_:userId:weekStart:)` — the exact
/// call the chip makes — rather than from the hand-written `wrapSummary` the
/// Train tab's shots use. That is the point of this one: it photographs the
/// door end to end, from a month-old week's rows to the report, and a shot
/// script cannot tap a chip.
///
/// W4: a PUSH. The destination is driven by `item:` and the item lands when the
/// replay does, which is also what makes it correct rather than convenient — a
/// `isPresented: true` declared up front would push an empty page for however
/// long the PR replay takes and photograph whichever of the two won.
private struct PresentingWrap: View {
    @Environment(AppEnvironment.self) private var environment
    let weekStart: String

    private struct Door: Hashable {
        let summary: WeeklyWrap.Summary
        let program: Program
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.summary.weekStart == rhs.summary.weekStart }
        func hash(into hasher: inout Hasher) { hasher.combine(summary.weekStart) }
    }

    @State private var door: Door?

    var body: some View {
        NavigationStack {
            WeekDaysView(window: WeekWindow(containing: weekStart, startDay: 0))
                .navigationDestination(item: $door) { door in
                    WeekReportView(summary: door.summary, program: door.program)
                }
        }
        .task {
            let database = environment.database
            let userId = database.localUserId()
            guard let summary = WorkoutWeek.wrap(database, userId: userId, weekStart: weekStart)
            else { return }
            door = Door(
                summary: summary,
                program: (try? database.scheduleContext(userId: userId, today: weekStart))?
                    .activeProgram ?? Program(id: "", label: "", days: [])
            )
        }
    }
}

/// The Workout tab with a sheet already up.
///
/// `WorkoutWeek` is built by `WorkoutTabView`'s own `.task` and is not reachable
/// from outside it, so this builds a second one against the same seeded store
/// and hands it to the sheet. Two instances read the same rows and neither
/// writes here, which is the whole cost of photographing a modal.
private struct PresentingWeek<Sheet: View>: View {
    @Environment(AppEnvironment.self) private var environment
    let today: String
    @ViewBuilder let sheet: (WorkoutWeek) -> Sheet

    @State private var week: WorkoutWeek?
    @State private var shown = true

    var body: some View {
        NavigationStack {
            WorkoutTabView(seededDay: PlanTemplates.program("onyx5")?.day(key: "cb_a"), seededToday: today)
        }
        .sheet(isPresented: $shown) {
            if let week, week.loaded { sheet(week) }
        }
        .task {
            if week == nil {
                week = WorkoutWeek(
                    database: environment.database, userId: environment.userIdString,
                    phase: .cut, seededToday: today, seededDayKey: "cb_a"
                )
            }
            await week?.refresh()
        }
    }
}

#Preview("History") { HistoryPreviews.view("history") }
#Preview("Session") { HistoryPreviews.view("session") }
#endif
