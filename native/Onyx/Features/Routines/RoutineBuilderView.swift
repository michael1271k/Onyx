import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// The days of one program, and the door into each of them.
///
/// ── WHY IT IS A LIST AND NOT A WEEK GRID ────────────────────────────────────
/// A routine is an ORDERED set of sessions that happen to be assigned weekdays,
/// not a calendar. Hevy, Strong and every paper programme are written the same
/// way — Day 1, Day 2, Day 3 — and the weekday is a property of a day rather
/// than its identity. A grid would also have to answer what two sessions on one
/// weekday look like, which is a real thing people write and a layout problem
/// with no good answer.
///
/// `WorkoutWeek` already draws the week. This screen writes what it draws.
struct RoutineBuilderView: View {
    @Bindable var model: RoutinesModel
    @State private var pendingDelete: RoutineDay?

    var body: some View {
        List {
            if let failure = model.failure {
                Section { Text(failure).onyxType(.caption).foregroundStyle(Color.onyx.danger) }
            }

            // ── THE MOVEMENTS NOTHING ANSWERS FOR ───────────────────────────
            // Once, at the top, rather than as a badge on every day. A movement
            // the catalogue cannot place still logs — it falls back to the
            // legacy slug (D3) — but its sets will not resolve to a catalogue
            // row on upload, and that is worth saying out loud rather than
            // discovering as a red badge on a finished session three days later.
            if !model.unresolved.isEmpty {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(unresolvedTitle)
                                .onyxType(.body).fontWeight(.semibold)
                                .foregroundStyle(Color.onyx.textPrimary)
                            Text(unresolvedDetail)
                                .onyxType(.caption)
                                .foregroundStyle(Color.onyx.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "questionmark.circle").foregroundStyle(Color.onyx.record)
                    }
                }
            }

            Section {
                ForEach(model.days, id: \.dayKey) { day in
                    NavigationLink {
                        RoutineDayEditor(model: model, dayKey: day.dayKey)
                    } label: {
                        dayRow(day)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { pendingDelete = day } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { model.duplicate(day) } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(OnyxDomain.train.accent)
                    }
                }
                .onMove { model.move(from: $0, to: $1) }
            } header: {
                OnyxSectionHeader("Days", .train)
            } footer: {
                Text(model.days.isEmpty
                     ? "No days yet. Add one and put your movements in it."
                     : "Drag to reorder. Swipe a day to duplicate or delete it.")
            }

            Section {
                Button {
                    model.addDay()
                } label: {
                    Label("Add a day", systemImage: "plus")
                }
            }
        }
        .onyxFormBackground(.train)
        .navigationTitle(model.programLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .task { await model.reload() }
        // A day carries every session ever logged against it through
        // `workout_sessions.day_key`; deleting it does not delete those, but it
        // does take them out of the schedule, so it asks.
        .confirmationDialog(
            "Delete \(pendingDelete?.label ?? "this day")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let day = pendingDelete { model.delete(day) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Sessions you have already logged on this day are kept. The day stops appearing in your week.")
        }
    }

    /// ── A LIST OF THIRTY-THREE NAMES IS NOT A WARNING ──────────────────────
    /// The first shot of this screen was a wall of text: an account with an
    /// empty catalogue has EVERY movement unresolved, and naming all of them
    /// buried the days underneath. That state is not "some movements are
    /// missing", it is "you have no exercise list yet", and it has a different
    /// fix — the importer — so it gets different words.
    private var unresolvedTitle: String {
        model.unresolved.count >= model.movementCount && model.movementCount > 0
            ? "Your exercise list is empty"
            : "Not in your exercise list"
    }

    private var unresolvedDetail: String {
        if model.unresolved.count >= model.movementCount && model.movementCount > 0 {
            return "These days still work — every set logs. Settings → Import exercises fills your list so sets count towards the right muscles."
        }
        // Four names and a count. Enough to recognise a typo, short enough to
        // stay a warning rather than become the screen.
        let shown = model.unresolved.prefix(4).joined(separator: ", ")
        let rest = model.unresolved.count - 4
        return rest > 0 ? "\(shown) and \(rest) more" : shown
    }

    private func dayRow(_ day: RoutineDay) -> some View {
        HStack(spacing: OnyxSpace.m) {
            Capsule()
                .fill(Color.onyx.routineAccent(day.accent))
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.label)
                    .onyxType(.body).fontWeight(.semibold)
                    .foregroundStyle(Color.onyx.textPrimary)
                Text(subtitle(day))
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ day: RoutineDay) -> String {
        let count = day.payload.exercises.count
        let movements = count == 1 ? "1 movement" : "\(count) movements"
        let sets = day.payload.exercises.reduce(0) { $0 + $1.sets }
        let weekday = Self.weekdayNames[min(max(day.weekday, 0), 6)]
        // The sub is the day's own subtitle ("Chest + Back") and beats a set
        // count when it is there — it is what the person wrote.
        if let sub = day.sub, !sub.isEmpty { return "\(weekday) · \(sub) · \(movements)" }
        return count == 0 ? "\(weekday) · empty" : "\(weekday) · \(movements), \(sets) sets"
    }

    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
}
