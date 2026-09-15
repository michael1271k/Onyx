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
    static let incline = ExerciseCatalogEntry(id: "ex-incline", name: "Incline DB Press", setCount: 24, lastTrained: "2026-09-01")

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
        case "session-edit":
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
        case "train-empty":
            // A REST day: no session card, no footer CTA, and the cardio card
            // sits where the deck would be — which is the only way to
            // photograph it in full, and the state a Wednesday actually is.
            // `2026-09-05` is the seeded block's Saturday.
            NavigationStack {
                WorkoutTabView(seededToday: "2026-09-05")
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
        // ── W6: the wrap-up, and the card it shares ─────────────────────────
        // Seeded rather than read: the shot's job is the LAYOUT — a week with a
        // progression, a regression and a PR in it — and the engine behind it
        // has its own unit suite. Building a fixture whose four planned days
        // all happen to be logged would make this shot hostage to the seed.
        //
        // Presented as a REAL sheet since W1a, the same trick `train-week`
        // uses. The wrap is a detent sheet now, and a shot of the view on its
        // own photographs neither the 560 height it opens at nor the drag
        // indicator that is the only cue there is more below — which is most of
        // what this wave changed.
        case "train-wrap":
            PresentingWeek(today: "2026-09-03") { _ in
                WeeklyWrapView(summary: wrapSummary, program: wrapProgram)
            }
            .environment(environment())
        // The dragged-up state. Not a sheet: a shot cannot perform the drag,
        // and the harness's own detent override is the only way to reach the
        // legend. What it photographs is the CONTENT at `.large`, which is the
        // half that needed reviewing.
        case "train-wrap-large":
            WeeklyWrapView(summary: wrapSummary, program: wrapProgram, detent: .large)
                .environment(environment())
        case "train-wrap-deload":
            PresentingWeek(today: "2026-09-03") { _ in
                WeeklyWrapView(summary: deloadSummary, program: wrapProgram)
            }
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
            // opening the same reel the Train tab opens on a Sunday night.
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
                    est1rmKg: Epley.oneRepMax(weight: set.1, reps: Double(set.2)), rpe: 7, foldOrder: i
                ).insert(db)
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
            func set(_ ex: String, _ i: Int, _ w: Double, _ r: Int, type: String = "normal", side: String? = nil, pair: String? = nil, rpe: Double? = nil) throws {
                try WorkoutSet(id: "\(id)-\(ex)-\(i)\(side ?? "")", sessionId: id, exerciseId: ex, setIndex: i, weightKg: w, reps: r,
                               setType: type, side: side, pairId: pair, est1rmKg: Epley.oneRepMax(weight: w, reps: Double(r)), rpe: rpe,
                               exerciseOrder: placed[ex], foldOrder: order).insert(db)
                order += 1
            }
            try set("ex-incline", 0, 20, 12, type: "warmup")
            for (i, (w, r)) in s.incline.enumerated() { try set("ex-incline", i + 1, w, r, rpe: 7 + Double(i) * 0.5) }
            // The last set of the pulldown on the session the shot loop opens
            // is taken to FAILURE, which is the only way any screenshot of this
            // app shows the state: nothing else in six weeks of this fixture
            // sits on the top rung of `RpeLadder`, so the `F` badge and the red
            // effort word were unreviewable — and an unreviewable state is one
            // that breaks silently.
            for (i, (w, r)) in s.pulldown.enumerated() {
                let failed = id == lastSession && i == s.pulldown.count - 1
                try set("ex-pulldown", i + 1, w, r, rpe: failed ? 10 : 7.5)
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
                           weightKg: w, reps: r, est1rmKg: Epley.oneRepMax(weight: w, reps: Double(r)), rpe: 7, foldOrder: i).insert(db)
        }

        // One leg day, so the list has a second colour and Hack Squat a ledger.
        let legs = "s-2026-08-30"
        let start = LogicalDay.date(fromISO: "2026-08-30")!.addingTimeInterval(17 * 3600)
        try WorkoutSession(id: legs, userId: userId, dayKey: "legs_a", date: "2026-08-30", startedAt: start,
                           endedAt: start.addingTimeInterval(58 * 60), durationMin: 58, sessionRpe: 8).insert(db)
        for (i, (w, r)) in [(60.0, 12), (60.0, 11), (60.0, 10)].enumerated() {
            try WorkoutSet(id: "\(legs)-hack-\(i)", sessionId: legs, exerciseId: "ex-hack", setIndex: i + 1, weightKg: w, reps: r,
                           est1rmKg: Epley.oneRepMax(weight: w, reps: Double(r)), rpe: 8, foldOrder: i).insert(db)
        }

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
        topSession: .init(dayKey: "legs_a", date: "2026-09-04", volumeKg: 12_480)
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
/// door end to end, from a month-old week's rows to the reel, and a shot script
/// cannot tap a chip.
private struct PresentingWrap: View {
    @Environment(AppEnvironment.self) private var environment
    let weekStart: String

    @State private var summary: WeeklyWrap.Summary?
    @State private var program = Program(id: "", label: "", days: [])
    @State private var shown = true

    var body: some View {
        NavigationStack {
            WeekDaysView(window: WeekWindow(containing: weekStart, startDay: 0))
        }
        .sheet(isPresented: $shown) {
            if let summary { WeeklyWrapView(summary: summary, program: program) }
        }
        .task {
            let database = environment.database
            let userId = database.localUserId()
            summary = WorkoutWeek.wrap(database, userId: userId, weekStart: weekStart)
            program = (try? database.scheduleContext(userId: userId, today: weekStart))?
                .activeProgram ?? program
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
