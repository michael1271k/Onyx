#if DEBUG
import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// Seeded Today screens for `scripts/native-shot.sh`.
///
/// The feed is `OnyxSnapshot.sample` — the same fixture the widget contact
/// sheet renders — so the grid and the Home Screen shots show the same numbers.
enum TodayPreviews {
    static let userId = "00000000-0000-0000-0000-000000000001"

    @MainActor
    static func model(
        editing: Bool = false, sheet: TodaySheet? = nil,
        /// W7. The Mega Widget is appended LAST by `reconcile`, which on a
        /// twenty-slot grid is three screens below the fold — so the shot that
        /// reviews it has to bring it up. Nothing else moves, so the tiles
        /// around it are the ones every other Today shot photographs.
        megaFirst: Bool = false,
        /// W7. A connected stack, for the sheet that says so.
        linked: Bool = false,
        /// W6. The clock the relevance order is resolved against, in minutes
        /// from local midnight — 420 is 07:00, 1200 is 20:00.
        ///
        /// Passed rather than read, because a seeded model never subscribes to
        /// the layout stream and so never reaches `TodayModel.ranked`. The
        /// same function is applied here, to the same layout, so the shot is
        /// of `Dashboard.relevanceOrdered`'s real output and not of a
        /// hand-written order that happens to look like it.
        clockMinute: Int? = nil
    ) -> TodayModel {
        let database = try! AppDatabase.inMemory(deviceId: "shot")
        // The catalogue as rows (W2): decks, plans, phases, rungs.
        PreviewCatalogue.seed(database)
        var layout = Dashboard.defaultLayout(.phone)
        // One stack, so the shot shows the page dots: Sleep over Vitals.
        layout = Dashboard.stackSlots(layout, fromId: "sl-vitals", ontoId: "sl-sleep")
        layout = Dashboard.resizeSlot(layout, slotId: "sl-sleep")
        // Two tiles in the tray, so the gallery has something to offer.
        layout = Dashboard.removeFace(layout, slotId: "sl-consistency", index: 0)
        layout = Dashboard.removeFace(layout, slotId: "sl-cardio", index: 0)
        // Edit mode is photographed with the hero at Medium, so the smalls, the
        // stack and the gallery all fit on one screen.
        if editing { layout = Dashboard.resizeSlot(layout, slotId: "sl-recovery") }
        if linked { layout = Dashboard.setLinked(layout, slotId: "sl-sleep", true) }
        if megaFirst { layout = Dashboard.moveSlot(layout, fromId: "sl-daily", toId: "sl-recovery") }
        // ── THE EDITS ABOVE ARE NOT THIS READER'S EDITS ─────────────────────
        // Every arrangement op ends in `Dashboard.touch`, which stamps
        // `updatedAt` — and a stamped layout is one the reader arranged, which
        // `relevanceOrdered` refuses to touch. That rule is right in the app
        // and wrong here: the stack and the tray above are the shot's fixture,
        // not a choice somebody made. Reset the stamp to what a fresh install
        // carries, then rank. The first attempt did not, and photographed the
        // stored order under both filenames.
        if let clockMinute {
            layout.updatedAt = 0
            layout = Dashboard.relevanceOrdered(layout, minuteOfDay: clockMinute)
            // ── AND THEN PINNED ─────────────────────────────────────────────
            // `TodayModel.observe()` subscribes to the layout stream even for
            // a seeded model, re-reads the row this function just wrote and
            // re-ranks it against the WALL CLOCK — which on the machine taking
            // the screenshot is whatever time it is, not 07:00. The first
            // evening shot came back in the morning order for exactly that
            // reason. Stamping `updatedAt` makes the order read as one
            // somebody arranged, which `relevanceOrdered` then refuses to
            // touch: the shot is of the clock's output, held still.
            layout.updatedAt = Double(clockMinute)
        }
        try? database.saveDashboardLayout(userId: userId, layout)

        let snapshot = OnyxSnapshot.sample
        let readiness = ScheduleReadiness.apply(
            ReadinessResult(level: .trainHard, label: "Train Hard", color: "#3E9E7A", reason: "Sleep, battery, and recovery are all strong today."),
            ScheduleReadinessContext(
                dayLabel: snapshot.workout.isRestDay ? nil : snapshot.workout.label,
                workoutToday: snapshot.workout.logged, contextMode: "normal",
                reentry: false, programLabel: "Onyx-5"
            )
        )
        let feed = TodayFeed(
            snapshot: snapshot,
            readiness: readiness,
            goalBoard: GoalBoard(
                ratePerWeekKg: -0.46, trendWeightKg: 68.4,
                targetRateMinKgWk: -0.50, targetRateMaxKgWk: -0.40,
                targetWeightKg: 62, weeksToTarget: 9.6, etaISO: "2026-11-08",
                weekBalanceKcal: -2_310, weekDaysCounted: 4, pace: .onTrack
            ),
            weekSoFar: WeekSoFarSummary(
                weekStart: "2026-08-30", weekNumber: 7, dayOfWeek: 5,
                current: WeekTotals(volumeKg: 24_120, sessions: 3, sleepMin: 442, score: 78),
                previous: WeekTotals(volumeKg: 22_800, sessions: 3, sleepMin: 431, score: 74),
                change: WeekChange(label: "Tonnage", text: "+6%", direction: .up, good: true),
                sessionTarget: 5
            ),
            weeklySummaryReady: false,
            lastWeekStart: "2026-08-23",
            // A mid-week body: the pushing muscles are done, the pulling ones
            // are half done, and the legs have not been trained yet. That shape
            // is the point of the shot — a week that is uniformly 60 % complete
            // photographs as sixteen identical bars and reviews as nothing.
            muscleFocus: MuscleFocusSummary(weekStart: "2026-08-30", rows: [
                MuscleFocusRow(muscle: .chest, sets: 11, target: 11),
                MuscleFocusRow(muscle: .lats, sets: 3.5, target: 6),
                MuscleFocusRow(muscle: .upperBack, sets: 2, target: 4),
                MuscleFocusRow(muscle: .lowerBack, sets: 1, target: 1),
                MuscleFocusRow(muscle: .frontDelts, sets: 5.5, target: 4),
                MuscleFocusRow(muscle: .sideDelts, sets: 4, target: 7),
                MuscleFocusRow(muscle: .rearDelts, sets: 0.5, target: 2),
                MuscleFocusRow(muscle: .biceps, sets: 6, target: 8),
                MuscleFocusRow(muscle: .triceps, sets: 6.5, target: 6),
                MuscleFocusRow(muscle: .forearms, sets: 1.5, target: 4),
                MuscleFocusRow(muscle: .quads, sets: 0, target: 10),
                MuscleFocusRow(muscle: .hamstrings, sets: 0, target: 8),
                MuscleFocusRow(muscle: .glutes, sets: 0, target: 6),
                // Zero of zero: on a cut the plan asks for none. The row has to
                // read as "not asked for" and not as "behind".
                MuscleFocusRow(muscle: .adductors, sets: 0, target: 0),
                MuscleFocusRow(muscle: .calves, sets: 2, target: 6),
                MuscleFocusRow(muscle: .absCore, sets: 7, target: 10),
            ])
        )
        let model = TodayModel(database: database, userId: userId, feed: feed, layout: layout)
        model.editing = editing
        model.sheet = sheet
        return model
    }

    @MainActor
    private static var weighInEnvironment: AppEnvironment {
        let environment = AppEnvironment.preview
        environment.seedWeighInPendingForPreview()
        return environment
    }

    @MainActor @ViewBuilder
    static func view(_ screen: String) -> some View {
        switch screen {
        case "today-edit":
            NavigationStack { TodayTabView(seeded: model(editing: true)) }.environment(AppEnvironment.preview)
        // ── THE SAME GRID, TWICE, AT TWO HOURS (§W6-B.3) ────────────────────
        // Nothing is added, removed or resized between these two shots — the
        // only difference is which card you land on. That is the whole claim
        // relevance ordering makes, and it is not provable from one frame.
        case "today-morning":
            NavigationStack { TodayTabView(seeded: model(clockMinute: 7 * 60)) }
                .environment(AppEnvironment.preview)
        case "today-evening":
            NavigationStack { TodayTabView(seeded: model(clockMinute: 20 * 60)) }
                .environment(AppEnvironment.preview)
        // ── W7 ──────────────────────────────────────────────────────────────
        // The Mega Widget at the top of the grid: three arcs, the battery in
        // the hole and the rule table's sentence under it. The AX5 twin is the
        // one that matters — the sentence is the only prose on the dashboard
        // and it has two lines to fit in.
        case "today-mega":
            NavigationStack { TodayTabView(seeded: model(megaFirst: true)) }.environment(AppEnvironment.preview)
        // A connected stack. The connection is invisible on a tile by design —
        // it changes WHEN the tile turns over, not what it draws — so the shot
        // that reviews it is the sheet that sets it.
        case "today-stack-linked":
            NavigationStack { TodayTabView(seeded: model(sheet: .stack("sl-sleep"), linked: true)) }
                .environment(AppEnvironment.preview)
        // Edit mode for a reader who has asked the system not to move things.
        // The wiggle is gone and every tile wears its accent hairline instead,
        // which is the substitution and not the removal.
        case "today-edit-still":
            NavigationStack { TodayTabView(seeded: model(editing: true)) }
                .environment(AppEnvironment.preview)
                .environment(\.onyxForcesReducedMotion, true)
        // The two sheets §5.1 rewrote. Both are photographed because both were
        // the same bug — a sheet repeating its own content — and a regression in
        // either is invisible in a diff and obvious in a PNG.
        case "today-sheet":
            NavigationStack { TodayTabView(seeded: model(sheet: .tile(.sleep))) }.environment(AppEnvironment.preview)
        case "today-sheet-vitals":
            NavigationStack { TodayTabView(seeded: model(sheet: .tile(.vitals))) }.environment(AppEnvironment.preview)
        // The three the dashboard-polish wave gave purpose-built bodies. Each is
        // photographed for the reason the two above are: the defect they fix —
        // a sheet answering a question the tile did not ask — is invisible in a
        // diff and obvious in a PNG.
        case "today-sheet-steps":
            NavigationStack { TodayTabView(seeded: model(sheet: .tile(.steps))) }.environment(AppEnvironment.preview)
        case "today-sheet-muscle":
            NavigationStack { TodayTabView(seeded: model(sheet: .tile(.muscle))) }.environment(AppEnvironment.preview)
        case "today-sheet-records":
            NavigationStack { TodayTabView(seeded: model(sheet: .tile(.pr))) }.environment(AppEnvironment.preview)
        // The weigh-in banner (§W5.4): Health landed a weight and the InBody
        // numbers it cannot know are still blank.
        // The Goal Board's three states. It lives under the grid on Today, which
        // is below the fold in a screenshot, so it gets a contact sheet of its
        // own — the states are the point and one of them is always wrong.
        case "today-board":
            VStack(spacing: OnyxSpace.m) {
                GoalBoardRow(board: GoalBoard(
                    ratePerWeekKg: -0.46, trendWeightKg: 68.4,
                    targetRateMinKgWk: -0.50, targetRateMaxKgWk: -0.40,
                    targetWeightKg: 62, weeksToTarget: 9.6, etaISO: "2026-11-08",
                    weekBalanceKcal: -2_310, weekDaysCounted: 4, pace: .onTrack
                ))
                GoalBoardRow(board: GoalBoard(
                    ratePerWeekKg: 0.12, trendWeightKg: 68.4,
                    targetRateMinKgWk: -0.50, targetRateMaxKgWk: -0.40,
                    targetWeightKg: 62,
                    weekBalanceKcal: 1_140, weekDaysCounted: 6, pace: .reversed
                ))
                GoalBoardRow(board: GoalBoard(
                    targetRateMinKgWk: -0.50, targetRateMaxKgWk: -0.40, targetWeightKg: 62
                ))
                Spacer(minLength: 0)
            }
            .padding(OnyxSpace.l)
            .onyxScreen(.recover)
        case "today-weighin":
            NavigationStack { TodayTabView(seeded: model()) }.environment(weighInEnvironment)
        default:
            NavigationStack { TodayTabView(seeded: model()) }.environment(AppEnvironment.preview)
        }
    }
}
#endif
