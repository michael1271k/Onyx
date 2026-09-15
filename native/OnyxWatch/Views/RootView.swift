import OnyxCore
import OnyxData
import OnyxUI
import SwiftUI

/// What the app opens on.
///
/// ── IT IS THE SET, NOT A DASHBOARD ──────────────────────────────────────────
/// The first design made a dashboard the root, and that is the phone's
/// information architecture rotated onto a wrist. Nobody raises a wrist mid-gym
/// to read "week so far", and every screen that is not the set in front of you
/// is a tap on the way to the set in front of you. So: a live session opens
/// straight into `SetView`; no live session opens a card that starts today's
/// split in one tap.
///
/// The dashboard is still here — it is one swipe away, in `DashboardView` —
/// because a glance at readiness before you start is a real thing to want. It
/// simply does not stand between you and a barbell.
struct RootView: View {

    @Environment(WatchModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.storeError != nil {
                    StoreErrorView()
                } else if model.sessionId != nil {
                    SetView()
                } else {
                    StartView()
                }
            }
        }
        // ── REST IS A STATE, NOT A PAGE ─────────────────────────────────────
        // A cover rather than a tab, because rest is not somewhere you can
        // usefully navigate TO — it is a thing that is happening to you, and it
        // ends on its own. Presenting it this way is also what lets it dismiss
        // itself at zero, which is what makes "not rated" the outcome of doing
        // nothing.
        .fullScreenCover(item: Binding(get: { model.rest }, set: { if $0 == nil { model.stopRest() } })) { pulse in
            // ── THE COVER NEEDS ITS OWN STACK, AND THAT IS NOT DECORATION ────
            // The `NavigationStack` above wraps the ROOT, not the cover, so a
            // `.toolbar` inside `RestView` had nothing to attach to and drew
            // nothing at all — no warning, no diagnostic, just a missing timer.
            // The rest screen carries the session clock in the same corner
            // `SetView` does, and it has to be the same corner on both or the
            // reading appears and disappears as rest starts and ends, which
            // reads as a glitch rather than as a state.
            NavigationStack { RestView(pulse: pulse) }
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// How long this session has been running, for the top-right of both screens.
///
/// ── WHY IT IS `h:mm` AND NOT A COUNTDOWN TEXT ───────────────────────────────
/// `Text(_:style:.timer)` and `Text(timerInterval:)` are ticked by the system,
/// which is exactly what a wrist wants — but both print seconds and neither can
/// be told not to. The 40 mm bar is 162 pt and `SetView` has already spent it:
/// "Set 1 of 4" takes ~62 and the deck link ~20, leaving about 50. "44:32" fits
/// that; "1:04:32" does not, and a six-hour session is a real reading in this
/// app's own history. A bar that re-lays itself out at the hour mark, mid-set,
/// is the layout this device punishes hardest.
///
/// So: hours and minutes, four characters, one redraw a minute — which is what
/// the always-on state wants anyway. The seconds are on the phone's hero at
/// 34 pt for anyone who wants them.
///
/// ── AND WHY IT DIMS ITSELF ──────────────────────────────────────────────────
/// A toolbar item is not inside the content that `.dimmedWhenLuminanceReduced`
/// is applied to, so without its own call this is a small, static, tinted
/// string held in one fixed corner at full brightness for an hour — the
/// textbook burn-in case on an OLED panel.
struct WatchSessionTimer: View {

    @Environment(WatchModel.self) private var model

    var body: some View {
        if let startedAt = model.sessionStartedAt {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(
                    Duration.seconds(max(0, context.date.timeIntervalSince(startedAt)))
                        .formatted(.time(pattern: .hourMinute))
                )
                .font(WatchType.label)
                // Required, and not for the usual reason: a proportional string
                // in a toolbar re-measures the bar on every tick, which re-lays
                // the title beside it, forever.
                .monospacedDigit()
                // 36 and not 44: `h:mm` is four characters and monospaced, so
                // the box only grows at ten hours. The 44 it started at was
                // enough of the 40 mm bar to truncate `SetView`'s title.
                .frame(minWidth: 36, alignment: .trailing)
                .foregroundStyle(WatchInk.day(model.day?.key))
                .dimmedWhenLuminanceReduced()
                .accessibilityLabel("Total workout time")
            }
        }
    }
}

/// No session yet.
///
/// One tap starts today's split. The "Change" row exists because a swap is
/// real — the plan moves days — but it is deliberately the second thing on the
/// screen and not a picker you have to get through first.
struct StartView: View {

    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                if let day = model.day {
                    Text(day.label)
                        .font(WatchType.value)
                        .foregroundStyle(WatchInk.primary)
                        .lineLimit(2)
                    Text("\(day.exercises(for: model.phase).count) movements")
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.secondary)
                } else if model.context == nil {
                    // The honest empty state. The watch cannot sign in — by
                    // design, Wave 10 — so the only way it learns who you are
                    // and what today is, is the phone's application context.
                    Text("Open Onyx on your iPhone")
                        .font(WatchType.name)
                        .foregroundStyle(WatchInk.primary)
                        .lineLimit(3)
                    Text("It sends this watch your plan.")
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.secondary)
                        .lineLimit(2)
                } else {
                    Text("Rest day")
                        .font(WatchType.value)
                        .foregroundStyle(WatchInk.primary)
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            if model.day != nil {
                Button {
                    model.beginSession()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(WatchType.value)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchInk.commit)
                .foregroundStyle(WatchInk.onCommit)
                .handGestureShortcut(.primaryAction)
            }
        }
        .containerBackground(WatchInk.ground, for: .navigation)
        .navigationTitle("Onyx")
        // ── THE DASHBOARD IS A TOOLBAR ITEM, NOT A SECOND BUTTON ────────────
        // It was a filled `NavigationLink` under the copy, and the first 40 mm
        // screenshot showed exactly why that was wrong: the pinned Start button
        // sits in the bottom safe-area inset and drew straight over it. Even
        // scrolled clear it was a second capsule competing with the one action
        // this screen exists for.
        //
        // Same treatment as the deck list on `SetView`: a reference lives in the
        // toolbar, and the screen keeps one button.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { DashboardView() } label: { Image(systemName: "chart.bar.fill") }
                    .tint(WatchInk.secondary)
            }
        }
    }
}

/// The phone holds the pencil.
///
/// ── ONE WRITER, AND THE OTHER ONE WATCHES ───────────────────────────────────
/// The event log tolerates two devices writing at once — `SetEventFold` is why
/// nothing can be lost — so this is not a correctness mechanism. It is a user
/// experience one: without it you log set 4 on the watch, glance at a phone
/// showing a stale list, log set 4 again, and spend the middle of your workout
/// cleaning up. With it exactly one device offers a keyboard.
///
/// The button is the whole escape hatch, and it always works: `claimPencil(force:
/// true)` is the deliberate takeover that `ingestOwnership` lets through even
/// when the other device is mid-set, because somebody pressed it.
struct MirrorView: View {

    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Text("iPhone is logging")
                    .font(WatchType.name)
                    .foregroundStyle(WatchInk.primary)
                    .lineLimit(2)
                Text("\(model.sets.count) sets so far")
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Log here") { model.takePencil() }
                .font(WatchType.value)
                .buttonStyle(.borderedProminent)
                .tint(WatchInk.commit)
                .foregroundStyle(WatchInk.onCommit)
        }
    }
}

/// Every planned set is in. The tick becomes a finish button.
struct FinishView: View {

    @Environment(WatchModel.self) private var model
    @State private var isFinishing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Text("Deck complete")
                    .font(WatchType.value)
                    .foregroundStyle(WatchInk.primary)
                Text("\(model.sets.count) sets")
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.secondary)
                if let bpm = model.workout.averageHeartRate {
                    Text("\(bpm) bpm average")
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                isFinishing = true
                Task {
                    await model.finish()
                    isFinishing = false
                }
            } label: {
                Label("Finish", systemImage: "flag.checkered")
                    .font(WatchType.value)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchInk.commit)
            .foregroundStyle(WatchInk.onCommit)
            .disabled(isFinishing)
        }
    }
}

/// The store would not open. Rare, and not something a person under a bar can
/// act on — so it says what happened and nothing else.
struct StoreErrorView: View {

    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Text("Store unavailable")
                    .font(WatchType.name)
                    .foregroundStyle(WatchInk.danger)
                Text(model.storeError ?? "")
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
