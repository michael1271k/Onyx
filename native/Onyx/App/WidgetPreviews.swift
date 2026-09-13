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
                // The lift you are resting BEFORE, and what it cost last time.
                // Both are seeded so the resting card's NEXT state is
                // photographable — `WorkoutCurrentSet` draws them only while
                // `restEndsAt` is set, so the working and paused cards below
                // are unaffected by carrying them.
                nextExercise: "Seated Cable Row (Wide Grip)",
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
        ]
    }()

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

    /// `widgets` → everything, scrolling. `widgets-3` → page 3 at 1:1.
    /// `widgets-activity` → the running workout's own surfaces.
    @ViewBuilder
    static func view(_ screen: String) -> some View {
        if screen == "widgets-activity" {
            activityPage
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
#endif
