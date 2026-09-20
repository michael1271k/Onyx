import OnyxCore
import OnyxData
import OnyxUI
import SwiftUI
import WatchKit

/// The rest of the session, as a list.
///
/// ── WHY A LIST AND NOT A PAGER ──────────────────────────────────────────────
/// This is the one place a pager would have been defensible, and a `List` still
/// wins: the deck is up to a dozen movements, the Crown scrolls a list natively
/// with no focus contest, and "where am I in the workout" is a question you
/// answer by scanning rather than by paging.
///
/// It is reached from the toolbar rather than from a swipe, because it is a
/// reference and not a step.
///
/// ── AND IT IS NO LONGER A READ-ONLY REFERENCE (W3, DECISION 1) ──────────────
/// It used to say, in this comment, that nothing here is tappable because
/// reordering a deck is a phone gesture and "inventing a second, smaller way to
/// do it on a wrist is how two clients start disagreeing about what a session
/// is". The founder's answer is the one that resolves that: the wrist does not
/// get a DRAG — drag stays phone-only — it gets swipe actions, which is a
/// different gesture for the same two decisions. What crosses to the phone is
/// `exercise_order` on the logged rows, written by the arithmetic both clients
/// now share (`DeckOrder.move`), so the two cannot disagree about the session.
/// Everything else here — the arrangement, the skips — is a view of today and
/// stays on this wrist deliberately: a workout rearranged at the rack is not an
/// edit to next week's routine.
///
///   · tap      — jump the cursor here
///   · leading  — Do next (after the movement you are on), and Add set
///   · trailing — Skip (sinks to the bottom, undone by tapping the row), and
///                Swap, on a movement with nothing logged against it yet
struct DeckView: View {

    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// The movement whose replacement list is open, by id.
    ///
    /// The ID and not the value: `navigationDestination(item:)` wants
    /// `Hashable`, and a `Movement` carries its logged rows — making the whole
    /// projection hashable to name one row is the tail wagging the dog. It is
    /// also the safer identity, for the reason `SetTarget` gives on the phone:
    /// the deck can be rebuilt under the presenter by a sync, and a held value
    /// would go on describing a movement the session no longer contains.
    @State private var swapping: String?

    var body: some View {
        List {
            // ── A FAILED WRITE IS A ROW, NOT A SCREEN ───────────────────────
            // It used to be `storeError`, which nothing clears and which
            // replaces the whole app with "Store unavailable" — so one
            // refused write (the phone holding the pencil is enough) ended
            // the workout UI until a force-quit. This is where there is room
            // to say it: a list, on the screen you reach when something did
            // not take.
            if let problem = model.writeError {
                Text(problem)
                    .font(WatchType.label)
                    .foregroundStyle(WatchInk.danger)
                    .lineLimit(3)
                    .listRowBackground(Color.clear)
            }
            ForEach(model.movements) { movement in
                row(movement)
            }
        }
        .containerBackground(WatchInk.ground, for: .navigation)
        .navigationTitle("Deck")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $swapping) { id in
            if let movement = model.movements.first(where: { $0.id == id }) {
                SwapList(movement: movement)
            }
        }
    }

    @ViewBuilder
    private func row(_ movement: WatchModel.Movement) -> some View {
        let isCursor = model.cursor?.movement.id == movement.id

        Button {
            // A skipped row's tap takes it back rather than jumping to it:
            // the row you are looking at is the one you changed your mind
            // about, and needing two gestures to undo one is the kind of
            // thing a wrist punishes.
            if movement.isSkipped {
                model.toggleSkip(movement)
            } else if !movement.isDone {
                model.jump(to: movement)
                dismiss()
            }
        } label: {
            HStack(spacing: OnyxSpace.s) {
                // Done, skipped, current, or still owed. One glyph — a
                // progress bar per row would spend width on a fraction that
                // "2/4" already says exactly.
                Image(systemName: glyph(movement, isCursor: isCursor))
                    .foregroundStyle(tint(movement, isCursor: isCursor))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(movement.plan.name)
                        .font(WatchType.label)
                        .foregroundStyle(movement.isSkipped ? WatchInk.secondary : WatchInk.primary)
                        .strikethrough(movement.isSkipped)
                        .lineLimit(2)
                        .allowsTightening(true)
                    Text("\(movement.logged.count)/\(movement.plannedSets) · \(movement.plan.reps)")
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .fill(isCursor ? WatchInk.fillActive : WatchInk.fill)
        )
        // ── LEADING IS THE CONSTRUCTIVE ONE ─────────────────────────────────
        // The side a right-handed wrist reaches first, and the same side the
        // rest of the platform puts its affirmative action on. `Skip` is the
        // destructive-shaped one and takes the trailing edge — though it is
        // not destructive at all: it writes no event and is undone by tapping
        // the row.
        // ── FOUR ACTIONS, TWO EDGES, AND NO CONTEXT MENU ────────────────────
        // `contextMenu` was the obvious home for "Swap…" and "one more set",
        // and it has been deprecated on watchOS since 7.0 — the compiler says
        // so, and a long press on a list row competes with the system's own
        // back gesture anyway. Swipe actions take all four, which also makes
        // them ONE gesture family to learn instead of two.
        //
        // Leading is the constructive edge — the side a right-handed wrist
        // reaches first, and the side the rest of the platform puts its
        // affirmative action on. Trailing holds the two that take something
        // away or change what the card IS.
        .swipeActions(edge: .leading) {
            Button {
                model.doNext(movement)
                WKInterfaceDevice.current().play(.click)
            } label: {
                // ── `arrow.up.to.line`, AND NOT THE COMMIT GREEN ────────────
                // `arrow.turn.up.right` is the platform's forward/redo mark,
                // and "Skip" is a real action on the other edge of this row —
                // so the guess an unlabelled glyph invites is the opposite of
                // what it does. And green means COMMIT everywhere else in
                // this app; spending it on a list action makes the reorder
                // read as the one that saves.
                Label("Do next", systemImage: "arrow.up.to.line")
            }
            .tint(WatchInk.fillActive)
            Button {
                // The TARGET, not "jump then add": `jump` refuses a movement
                // that is finished or skipped, and the no-argument add then
                // fell through to the cursor — so this gesture on the set you
                // had just finished added it to a different movement.
                model.addSet(to: movement)
                WKInterfaceDevice.current().play(.click)
            } label: {
                Label("Add set", systemImage: "plus")
            }
            .tint(WatchInk.fillActive)
        }
        .swipeActions(edge: .trailing) {
            Button {
                model.toggleSkip(movement)
                WKInterfaceDevice.current().play(.click)
            } label: {
                Label(
                    movement.isSkipped ? "Restore" : "Skip",
                    systemImage: movement.isSkipped ? "arrow.uturn.backward" : "slash.circle"
                )
            }
            .tint(WatchInk.fillActive)
            // Swapping a movement with rows already against it would orphan
            // them under an id the deck no longer names, so the action is
            // ABSENT rather than disabled — the same call the phone's options
            // sheet makes about its Split button.
            // A BOOLEAN: this runs inside a row's `swipeActions` builder, on
            // every render of a `List` inside a running `HKWorkoutSession`,
            // and the full candidate list walks every program × day ×
            // exercise and sorts the result.
            if model.hasSwapCandidate(for: movement) {
                Button {
                    swapping = movement.id
                } label: {
                    Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(WatchInk.fillActive)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(movement.plan.name), \(movement.logged.count) of \(movement.plannedSets) sets\(movement.isSkipped ? ", skipped" : "")")
        .accessibilityHint(movement.isSkipped ? "Tap to restore" : "Tap to jump here")
    }

    private func glyph(_ movement: WatchModel.Movement, isCursor: Bool) -> String {
        if movement.isSkipped { return "slash.circle" }
        if movement.isDone { return "checkmark.circle.fill" }
        return isCursor ? "circle.inset.filled" : "circle"
    }

    private func tint(_ movement: WatchModel.Movement, isCursor: Bool) -> Color {
        if movement.isSkipped { return WatchInk.secondary }
        if movement.isDone { return WatchInk.commit }
        return isCursor ? WatchInk.day(model.day?.key) : WatchInk.secondary
    }
}

/// The movements this card can become.
///
/// ── EVERY NAME HERE CAME FROM THE PHONE ─────────────────────────────────────
/// The candidates are `ProgramExercise` values out of `WatchContext.schedule`,
/// so each one arrives carrying the catalogue id the phone already resolved.
/// The watch resolves and never mints (`WatchModel.exerciseId(of:)`): a row
/// created on this wrist would carry a uuid no other client has seen, and the
/// movement would exist twice the moment the two logs met. A free-text picker
/// here would be exactly that, which is why there is no search field.
private struct SwapList: View {

    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let movement: WatchModel.Movement

    var body: some View {
        List(model.swapCandidates(for: movement)) { candidate in
            Button {
                model.swap(movement, for: candidate)
                WKInterfaceDevice.current().play(.success)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.name)
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.primary)
                        .lineLimit(2)
                        .allowsTightening(true)
                    Text(candidate.reps)
                        .font(WatchType.label)
                        .foregroundStyle(WatchInk.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .listRowBackground(
                RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                    .fill(WatchInk.fill)
            )
        }
        .containerBackground(WatchInk.ground, for: .navigation)
        .navigationTitle("Swap")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The Control Center — readiness, the week, and what today costs.
///
/// ── IT IS ONE SWIPE FROM THE START CARD, NOT THE ROOT ───────────────────────
/// A dashboard that opens the app puts a screen between you and the set you
/// came to log. This one is reached deliberately, before a session, which is
/// the only moment its numbers change a decision.
///
/// ── AND IT DRAWS NONE OF THE PHONE'S TILES ──────────────────────────────────
/// `OnyxUI`'s tiles are fenced `#if os(iOS)` — they switch on `WidgetFamily`
/// cases that do not exist on watchOS. That fence is also the right design call:
/// a tile is a Home Screen face with a tile's information density, and at 40 mm
/// the honest version of a dashboard is four rows of text.
struct DashboardView: View {

    @Environment(WatchModel.self) private var model

    var body: some View {
        List {
            if let day = model.day {
                row("Today", day.label)
                row("Movements", "\(day.exercises(for: model.phase).count)")
                row("Phase", model.phase.label)
            } else {
                row("Today", "Rest")
            }
            if model.sessionId != nil {
                row("Logged", "\(model.sets.count) sets")
            }
            if let bpm = model.workout.heartRate {
                row("Heart", "\(bpm) bpm")
            }
        }
        .containerBackground(WatchInk.ground, for: .navigation)
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(WatchType.label)
                .foregroundStyle(WatchInk.secondary)
            Spacer(minLength: OnyxSpace.s)
            Text(value)
                .font(WatchType.label)
                .foregroundStyle(WatchInk.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .fill(WatchInk.fill)
        )
        .accessibilityElement(children: .combine)
    }
}
