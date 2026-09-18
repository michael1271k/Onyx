#if DEBUG
import SwiftUI
import WidgetKit
import OnyxCore
import OnyxUI

/// Every tile × every focus × every family, from `OnyxSnapshot.sample`.
///
/// The render gate for Wave 5's "move + re-skin": no network, no database, one
/// fixture. `widgets` is the whole contact sheet in a scroll view; `widgets-N`
/// is page N of it at 1:1, which is what the shot loop photographs — a scroll
/// view screenshots its first screen only, and sixty-seven tiles do not fit on
/// one.
@MainActor
enum WidgetPreviews {

    struct Cell: Identifiable {
        let id: String
        let family: WidgetFamily
        let content: AnyView

        var size: CGSize {
            switch family {
            case .systemSmall:          CGSize(width: 158, height: 158)
            case .systemMedium:         CGSize(width: 338, height: 158)
            case .systemLarge:          CGSize(width: 338, height: 354)
            case .accessoryCircular:    CGSize(width: 72, height: 72)
            case .accessoryRectangular: CGSize(width: 160, height: 72)
            default:                    CGSize(width: 160, height: 24)
            }
        }
    }

    static let entry = OnyxTileEntry(date: OnyxSnapshot.sampleDate, snapshot: .sample)
    /// The same date with every W12 series absent — the first-week state.
    static let emptyEntry = OnyxTileEntry(date: OnyxSnapshot.sampleDate, snapshot: .sampleEmptySeries)
    /// The same date with today's session finished — the state `TodayStats`
    /// draws and the shipped fixture never reaches.
    static let loggedEntry = OnyxTileEntry(date: OnyxSnapshot.sampleDate, snapshot: .sampleLogged)

    static let cells: [Cell] = {
        let home: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        var out: [Cell] = []
        func add<V: View>(_ id: String, _ family: WidgetFamily, _ view: V) {
            out.append(Cell(id: "\(id)-\(family)", family: family, content: AnyView(view)))
        }
        // Size-major within a family, so two Smalls share a row and two Larges
        // share a page — focus-major would put every Large on a page of its own.
        for fam in home { for f in FuelFocus.allCases { add("fuel-\(f.rawValue)", fam, FuelView(entry: entry, focus: f)) } }
        for fam in home { for f in TrainingFocus.allCases { add("training-\(f.rawValue)", fam, TrainingView(entry: entry, focus: f)) } }
        for fam in home { for f in BodyFocus.allCases { add("body-\(f.rawValue)", fam, BodyView(entry: entry, focus: f)) } }
        for fam in home { for f in VitalsFocus.allCases { add("vitals-\(f.rawValue)", fam, VitalsView(entry: entry, focus: f)) } }
        // ── The W12 tiles ────────────────────────────────────────────────
        // Not focuses of a family, so they are enumerated by hand — and each
        // one twice: populated, then with its series gone. §W12's gate asks for
        // both, because the empty state is the one that ships unreviewed.
        let grid: [WidgetFamily] = [.systemSmall, .systemMedium]
        for fam in grid {
            add("trajectory", fam, TrajectoryView(entry: entry))
            add("consistency", fam, ConsistencyView(entry: entry))
            add("deficit", fam, DeficitLedgerView(entry: entry))
            add("fatigue", fam, FatigueStackView(entry: entry))
            add("muscle", fam, MuscleView(entry: entry))
        }
        // ── The sprint's W4 tiles ────────────────────────────────────────
        // Each at the sizes `Dashboard.widgetSizes` gives it and no others: a
        // cell photographed at a family the catalogue does not offer reviews a
        // layout nothing can reach. `soreness` is the only one of the four
        // with a Large, and `bedtime` is a Small everywhere.
        for fam in grid {
            add("weekrings", fam, WeekRingsView(entry: entry))
            add("soreness", fam, SorenessView(entry: entry))
            add("stress", fam, StressView(entry: entry))
        }
        add("soreness", .systemLarge, SorenessView(entry: entry))
        add("bedtime", .systemSmall, BedtimeView(entry: entry))
        for fam in grid {
            add("weekrings-empty", fam, WeekRingsView(entry: emptyEntry))
            add("soreness-empty", fam, SorenessView(entry: emptyEntry))
            add("stress-empty", fam, StressView(entry: emptyEntry))
        }
        add("bedtime-empty", .systemSmall, BedtimeView(entry: emptyEntry))
        for fam in grid {
            add("trajectory-empty", fam, TrajectoryView(entry: emptyEntry))
            add("consistency-empty", fam, ConsistencyView(entry: emptyEntry))
            add("deficit-empty", fam, DeficitLedgerView(entry: emptyEntry))
            add("fatigue-empty", fam, FatigueStackView(entry: emptyEntry))
            add("muscle-empty", fam, MuscleView(entry: emptyEntry))
            add("body-empty", fam, BodyView(entry: emptyEntry, focus: .composition))
        }
        // The Today face's DONE state. Two cells and not six: the Small drops
        // the stat row by design ("no room for four figures under a headline"),
        // so a logged Small is the same PNG as a due one.
        for fam in [WidgetFamily.systemMedium, .systemLarge] {
            add("training-today-logged", fam, TrainingView(entry: loggedEntry, focus: .today))
        }
        // Large only — the widget declares `.systemLarge` alone (see OnyxDaily).
        add("daily", .systemLarge, DailyView(entry: entry))
        for f in LockFocus.allCases {
            for fam in [WidgetFamily.accessoryCircular, .accessoryRectangular, .accessoryInline] {
                add("lock-\(f.rawValue)", fam, LockView(entry: entry, focus: f))
            }
        }
        return out
    }()

    /// Rows that fit the width, then pages that fit the height — so page N is
    /// the same N cells every run, whatever the order they were declared in.
    static let pages: [[[Cell]]] = {
        let maxWidth: CGFloat = 372, maxHeight: CGFloat = 760, gap: CGFloat = 6, caption: CGFloat = 12
        var rows: [[Cell]] = [[]]
        var width: CGFloat = 0
        for cell in cells {
            if width > 0, width + gap + cell.size.width > maxWidth { rows.append([]); width = 0 }
            rows[rows.count - 1].append(cell)
            width += (width > 0 ? gap : 0) + cell.size.width
        }
        var pages: [[[Cell]]] = [[]]
        var height: CGFloat = 0
        for row in rows {
            let h = (row.map(\.size.height).max() ?? 0) + caption + gap
            if height > 0, height + h > maxHeight { pages.append([]); height = 0 }
            pages[pages.count - 1].append(row)
            height += h
        }
        return pages
    }()

    // MARK: - The running workout

    // ── WHY THE LIVE ACTIVITY IS ON THE CONTACT SHEET AT ALL ─────────────────
    // It is the only widget surface that was never photographed, because an
    // `ActivityViewContext` can only be made by ActivityKit — so the card was
    // reviewed by reading it, and it kept a `Text("ONYX")` and its own private
    // type scale through a whole rename. `Shared/WorkoutActivityCard.swift`
    // takes the state as a plain value for exactly this reason.
    //
    // Four states, because they are four different layouts and the second one
    // is what the card looks like for most of a session: mid-set, resting (the
    // skip button appears), a set that just took a record, and paused — the one
    // state where the clock is a string rather than a system timer, and the only
    // way to see that the phone and the Lock Screen agree about it.
    static let activityStates: [(String, OnyxWorkoutAttributes.ContentState)] = {
        func state(
            rest: Date? = nil, prs: Int = 0, rpe: String = "", setLabel: String = "Set 3 of 4",
            paused: Bool = false
        ) -> OnyxWorkoutAttributes.ContentState {
            .init(
                exercise: "Seated Cable Row (Wide Grip)",
                setLabel: setLabel,
                load: "42.5 kg × 12",
                rpe: rpe,
                lastTime: "40 kg × 12",
                volume: "1 074 kg",
                setsDone: 9,
                setsPlanned: 22,
                prsThisSession: prs,
                // ── A DIFFERENT LIFT FROM `exercise`, AND THAT IS THE POINT ──
                // This used to be the same string as `exercise` above, because
                // that is what the producer sent: "NEXT" was a chip in front of
                // the movement you were already doing (F3). The wire carries a
                // real next-in-deck now, and a fixture that still echoed the
                // current lift would photograph a card that looked correct
                // while proving nothing — the one state this whole change
                // exists to make true would be invisible in the shot.
                //
                // Seeded on every state because `WorkoutCurrentSet` only draws
                // it while `restEndsAt` is set, so the working and paused cards
                // below are unaffected by carrying it.
                nextExercise: "Single Arm Cable Crossover",
                lastRpe: "RPE 8.5",
                restEndsAt: rest,
                // 45 minutes in, which is what a session looks like. Off
                // `Date()` for the same reason `resting` is: an origin two days
                // in the past renders "48:52:29" — a real reading of a wrong
                // number, which is the hardest kind to notice.
                timerOrigin: Date().addingTimeInterval(-45 * 60),
                isPaused: paused,
                elapsed: paused ? "45:00" : "",
                primaryMuscle: "upper_back",
                // The prescription the countdown is running through — the
                // denominator the bar was missing. Without it every shot of
                // this page photographs the fallback (`now...endsAt`) and
                // reviews the bug rather than the fix. 97 s left of 150.
                restTotalSec: rest == nil ? nil : 150,
                dayKey: "arms"
            )
        }
        // Off `Date()` and NOT off `sampleDate`, which is the fixture's own
        // 2026-09-03 and therefore in the past: a rest that has already ended
        // is exactly the state `restCountdown` now returns nil for, so the page
        // would have photographed the fallback and called it the timer. (Before
        // that guard existed it did something worse — see its header.)
        let resting = Date().addingTimeInterval(97)
        return [
            ("working", state(rpe: "RPE 8")),
            ("resting", state(rest: resting, rpe: "RPE 8")),
            ("record", state(rest: resting, prs: 2, rpe: "RPE 9", setLabel: "Set 4 of 4")),
            ("paused", state(rpe: "RPE 8", paused: true)),
            // ── THE BOUT, WHICH THIS PAGE COULD NOT PHOTOGRAPH (W2) ─────────
            // Every fixture above is a lift, so the cardio branch W2 added to
            // `WorkoutCurrentSet` and to the compact island had no shot on this
            // page at all — the screenshot round reviewed four cards that could
            // not exercise it and would have reported the wave verified.
            //
            // `load` is EMPTY on purpose. That is what `LiveActivityController`
            // sends for a bout now: the old producer read `if let kg, let reps`,
            // the treadmill row carries non-nil ZEROS, and the card said
            // "0 kg × 0". The two numbers are the wire's whole content and the
            // view derives the pace, so a fixture that pre-formatted the string
            // would photograph a card the producer can never send.
            ("cardio", .init(
                exercise: "Treadmill",
                setLabel: "Bout 1 of 1",
                load: "",
                rpe: "",
                lastTime: "12 min · 2.15 km",
                volume: "1 074 kg",
                setsDone: 9,
                setsPlanned: 22,
                prsThisSession: 0,
                nextExercise: "Seated Cable Row (Wide Grip)",
                lastRpe: "",
                restEndsAt: nil,
                timerOrigin: Date().addingTimeInterval(-45 * 60),
                isPaused: false,
                elapsed: "",
                // What `LoggerModel.primaryMuscle` actually sends for a bout: it
                // tests the rows and answers `"cardio"`, and `WorkoutActivityCard`
                // resolves that token to the cardio chip. "quadriceps" here would
                // photograph a chip the producer cannot produce — which it did,
                // for one round, while `ProgramExercise` was resolving cardio
                // movers it had no business resolving.
                primaryMuscle: "cardio",
                restTotalSec: nil,
                // A REAL bout, and the arithmetic has to close. The brief's
                // example line — "12:30 · 0.37 km · 5:42/km" — does not: 750 s
                // over 0.37 km is 33:47/km, and a fixture carrying it would
                // photograph a correct formatter reading out an impossible walk
                // for anyone to check against. 750 s over 2.19 km IS 5:42/km.
                cardioElapsedSec: 750,
                cardioDistanceKm: 2.19,
                dayKey: "arms"
            )),
        ]
    }()

    /// The expanded island's four regions, laid out as its configuration lays
    /// them: mark and elapsed leading, sets trailing, and the whole set plus
    /// the rest controls across the bottom.
    ///
    /// 340 pt is the expanded region's usable width on a Pro — the number that
    /// matters, because the trailing column of `WorkoutCurrentSet` and the four
    /// controls of `WorkoutRestBand` are competing for it.
    private static func islandExpanded(_ state: OnyxWorkoutAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                OnyxMark(size: 12, tint: Color.onyx.day(state.dayKey), opacity: 1)
                WorkoutElapsed(state: state, startedAt: Date().addingTimeInterval(-45 * 60))
                Spacer(minLength: 8)
                // Mirrors the real `.trailing` region, which carries the muscle
                // tag since W2 — it used to print `9/22` twelve points above
                // `WorkoutTotals`' own "9/22 sets".
                WorkoutMuscleTag(token: state.primaryMuscle)
            }
            WorkoutTotals(state: state)
            WorkoutCurrentSet(state: state)
            if let countdown = restCountdown(state.restEndsAt, total: state.restTotalSec) {
                WorkoutRestBand(countdown: countdown, state: state, showsSkip: false)
            }
        }
        .padding(10)
        .frame(width: 340, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22).fill(Color.black)
        }
    }

    /// The compact pair, at the width the system actually gives them.
    private static func islandCompact(_ state: OnyxWorkoutAttributes.ContentState) -> some View {
        HStack(spacing: 4) {
            OnyxMark(size: 14, tint: Color.onyx.day(state.dayKey), opacity: 1)
            Spacer(minLength: 12)
            Group {
                if let countdown = restCountdown(state.restEndsAt, total: state.restTotalSec) {
                    Text(timerInterval: countdown, countsDown: true)
                        .monospacedDigit()
                        .frame(minWidth: 44, maxWidth: 44, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(
                            WorkoutMuscleTag.tint(state.primaryMuscle)
                                ?? Color.onyx.day(state.dayKey)
                        )
                } else {
                    Text(state.load.replacingOccurrences(of: " kg ", with: ""))
                        .foregroundStyle(Color.onyx.day(state.dayKey))
                }
            }
            .font(OnyxWidgetType.figure(12))
        }
        .padding(.horizontal, 10)
        .frame(width: 170, height: 36)
        .background { Capsule().fill(Color.black) }
    }

    /// The island's two expanded states, its compact pair, and the wrist card.
    private static var islandPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── THE ISLAND, STOOD IN FOR ─────────────────────────────────────
            // `DynamicIslandExpandedRegion` can only be built inside a
            // `DynamicIsland` builder inside an `ActivityConfiguration`, so the
            // real regions cannot be instantiated here any more than an
            // `ActivityViewContext` can. What CAN be: the pieces they are made
            // of, which are the same `Shared/` views taking the same plain
            // state — `WorkoutElapsed`, `WorkoutTotals`, `WorkoutCurrentSet`,
            // `WorkoutRestBand`, arranged as `OnyxWidgets.swift` arranges them.
            //
            // A stand-in and not the thing, so it can drift from the real
            // configuration — but it is the only way this surface's LAYOUT gets
            // reviewed as a picture at all, and the alternative was reviewing
            // it by reading it, which is how the card kept a `Text("ONYX")`
            // through a rename.
            ForEach(["resting", "working"], id: \.self) { name in
                if let state = activityStates.first(where: { $0.0 == name })?.1 {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("activity-island-expanded-\(name)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.onyx.textTertiary)
                        islandExpanded(state)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("activity-island-compact")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.onyx.textTertiary)
                HStack(spacing: 6) {
                    islandCompact(activityStates[1].1)
                    islandCompact(activityStates[0].1)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("activity-watch")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.onyx.textTertiary)
                WorkoutWatchCard(title: "Delts & Arms", state: activityStates[1].1)
                    .frame(width: 176, alignment: .leading)
                    .padding(8)
                    .background {
                        RoundedRectangle(cornerRadius: OnyxCorner.tile)
                            .fill(Color.onyx.textPrimary.opacity(0.08))
                    }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.onyx.base)
    }

    private static var activityPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(activityStates, id: \.0) { name, state in
                VStack(alignment: .leading, spacing: 0) {
                    Text("activity-lock-\(name)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.onyx.textTertiary)
                    // The elapsed origin travels in the state now, so that the
                    // card can be paused; see `ContentState.timerOrigin`. The
                    // attribute stays as the fallback for a card encoded before
                    // that field existed.
                    WorkoutLockCard(
                        title: "Delts & Arms",
                        startedAt: Date().addingTimeInterval(-45 * 60),
                        state: state
                    )
                    // The Lock Screen's own width, over a stand-in for a
                    // wallpaper: the real card is `.activityBackgroundTint`
                    // composited on whatever is behind it, and on this page's
                    // own black that tint is invisible — the card looked like
                    // loose text floating on the screen.
                    .frame(width: 360, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: OnyxCorner.tile)
                            .fill(LinearGradient(
                                colors: [Color.onyx.textPrimary.opacity(0.10),
                                         Color.onyx.textPrimary.opacity(0.04)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.onyx.base)
    }

    /// `widgets` → everything, scrolling. `widgets-3` → page 3 at 1:1.
    /// `widgets-activity` → the running workout's own surfaces.
    @ViewBuilder
    static func view(_ screen: String) -> some View {
        if screen == "widgets-activity" {
            activityPage
        // ── TWO PAGES, BECAUSE ONE SCROLLED OFF THE TOP ─────────────────────
        // Adding the island's two expanded states and its compact pair took the
        // activity sheet past a screen, and a page taller than the display
        // photographs its middle: the first Lock Screen card was cut by the
        // status bar and the watch card fell off the bottom. Three lock cards
        // on one page, the island and the wrist on the other.
        } else if screen == "widgets-island" {
            islandPage
        } else if screen == "widgets-nudge" {
            ActivityNudgeHarness()
        } else {
        let page = Int(screen.dropFirst("widgets-".count))
        if let page, pages.indices.contains(page) {
            VStack(spacing: 6) {
                ForEach(Array(pages[page].enumerated()), id: \.offset) { _, row in rowView(row) }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.onyx.base)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(pages.joined().enumerated()), id: \.offset) { _, row in rowView(row) }
                }
                .padding(.vertical, 8)
            }
            .background(Color.onyx.base)
        }
        }
    }

    private static func rowView(_ row: [Cell]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(row) { cell in
                VStack(alignment: .leading, spacing: 0) {
                    Text(cell.id)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.onyx.textTertiary)
                        .lineLimit(1)
                    cell.content
                        .environment(\.onyxTileFamily, cell.family)
                        .padding(cell.family.isAccessory ? 4 : 14)
                        .frame(width: cell.size.width, height: cell.size.height)
                        .onyxGlass(cell.family.isAccessory ? .row : .tile)
                }
            }
        }
    }
}

private extension WidgetFamily {
    var isAccessory: Bool {
        self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline
    }
}

/// The +15 s gate, as something a camera can watch.
///
/// ── WHY THE CARD'S OWN BUTTON CANNOT BE FILMED ──────────────────────────────
/// `WorkoutRestBand`'s nudges are `Button(intent: RestNudgeIntent(…))`, and a
/// `LiveActivityIntent` is performed by the system against a running activity —
/// there is no activity in the screenshot harness, so the buttons are inert
/// there. That is correct for the card and useless for a recording.
///
/// So this screen holds the state itself and applies the SAME two lines the
/// intent's own fallback applies (`RestSkipIntent.swift`): the deadline moves,
/// and the total moves with it. That pairing is the entire fix — the bar's
/// origin is `endsAt − total`, so moving both leaves the origin still and the
/// fill drops to `elapsed / (total + 15)` instead of snapping back to full.
///
/// The reading under the bar is the fill as a percentage, computed the way
/// `ProgressView(timerInterval:)` computes it, so the recording shows a NUMBER
/// falling rather than asking a reviewer to judge a gradient.
struct ActivityNudgeHarness: View {

    @State private var endsAt = Date().addingTimeInterval(75)
    @State private var totalSec = 150

    private var state: OnyxWorkoutAttributes.ContentState {
        var next = WidgetPreviews.activityStates[1].1
        next.restEndsAt = endsAt
        next.restTotalSec = totalSec
        return next
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.m) {
            Text("activity-nudge — press +15 s and watch the fill FALL")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.onyx.textTertiary)

            WorkoutLockCard(
                title: "Delts & Arms",
                startedAt: Date().addingTimeInterval(-45 * 60),
                state: state
            )
            .frame(width: 360, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: OnyxCorner.tile)
                    .fill(Color.onyx.textPrimary.opacity(0.08))
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let range = restCountdown(endsAt, total: totalSec)
                let fill = range.map { r -> Double in
                    let span = r.upperBound.timeIntervalSince(r.lowerBound)
                    return span > 0 ? context.date.timeIntervalSince(r.lowerBound) / span : 0
                } ?? 0
                Text("fill \(Int((fill * 100).rounded())) %  ·  total \(totalSec) s")
                    .onyxType(.display).onyxNumeral()
                    .foregroundStyle(Color.onyx.textPrimary)
            }

            HStack(spacing: OnyxSpace.m) {
                nudge(-15)
                nudge(15)
            }
        }
        .padding(OnyxSpace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onyxScreen(.train)
        // ── IT PRESSES ITS OWN BUTTON, BECAUSE A RECORDING NEEDS IT TO ──────
        // `simctl` can install, launch and film a simulator; it cannot tap one.
        // So the screen performs the same two nudges a reviewer would, five
        // seconds apart, and the fill reading underneath is what the camera is
        // actually there for: 54 % → 49 % → 45 %, falling each time. The bug
        // this replaces made it read 0 % on every press, because the bar's
        // origin was `now` and pressing restarted the span.
        .task {
            for _ in 0..<2 {
                try? await Task.sleep(for: .seconds(5))
                apply(15)
            }
        }
    }

    /// The intent's fallback, verbatim: deadline and total, together. Moving
    /// BOTH is the fix — the bar's origin is `endsAt − total`, so a nudge that
    /// moved only the deadline slid the origin forward and reset the fill.
    private func apply(_ seconds: Int) {
        let next = endsAt.addingTimeInterval(TimeInterval(seconds))
        guard next > Date() else { return }
        endsAt = next
        totalSec = max(0, totalSec + seconds)
    }

    private func nudge(_ seconds: Int) -> some View {
        Button("\(seconds > 0 ? "+" : "")\(seconds) s") { apply(seconds) }
        .onyxType(.body).fontWeight(.semibold)
        .foregroundStyle(Color.onyx.textPrimary)
        .padding(.horizontal, OnyxSpace.l)
        .frame(minHeight: 44)
        .background(OnyxDomain.train.ramp, in: Capsule())
    }
}
#endif
