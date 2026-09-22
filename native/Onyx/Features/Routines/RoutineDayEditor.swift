import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// One day's movements and their prescriptions.
///
/// ── IT HOLDS A KEY, NOT A COPY ──────────────────────────────────────────────
/// The day is looked up from the model on every draw. A `@State` copy would go
/// stale the moment any write reloaded the list — which every write here does —
/// and the screen would then save an older version of the day over a newer one.
/// The cost is a dictionary lookup per frame; the alternative is a lost edit.
struct RoutineDayEditor: View {
    @Bindable var model: RoutinesModel
    let dayKey: String

    @State private var picking = false
    /// ── THE TEXT FIELDS KEEP THEIR OWN COPY ────────────────────────────────
    /// They used to bind straight through to `rename`/`setSub`, which trim,
    /// write, and reload `days` — so the binding's `get` handed back the
    /// TRIMMED string on the very next frame and the field reset. Typing
    /// "Upper" then a space gave back "Upper": a day could not be called
    /// "Upper A" and a focus could not be "Chest + Back".
    ///
    /// It also wrote a row, queued an outbox item and re-indexed the catalogue
    /// on every keystroke. Local state, committed on focus loss, fixes both.
    @State private var label = ""
    @State private var sub = ""
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case label, sub
        case sets(Int), cutSets(Int), rest(Int), load(Int)
    }

    private var day: RoutineDay? { model.day(dayKey) }

    var body: some View {
        Group {
            if let day {
                editor(day)
            } else {
                // The day was deleted from under this screen — a swipe on the
                // list behind it, or a pull that removed it. A blank screen is
                // better than a crash and better than resurrecting the row.
                ContentUnavailableView("This day is gone", systemImage: "calendar.badge.minus")
            }
        }
        .navigationTitle(day?.label ?? "Day")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            label = day?.label ?? ""
            sub = day?.sub ?? ""
        }
        // Committed on focus loss as well as on Done, exactly as every numeric
        // field in this app commits (`OnyxNumberField`) — a decimal pad has no
        // return key and a name field can be left by tapping elsewhere.
        .onChange(of: focus) { old, _ in
            if old == .label { model.rename(dayKey, to: label) }
            if old == .sub { model.setSub(dayKey, sub) }
        }
        .onDisappear {
            model.rename(dayKey, to: label)
            model.setSub(dayKey, sub)
        }
        .toolbar {
            if day != nil { EditButton() }
        }
        .toolbar { OnyxKeyboardDone { focus = nil } }
        .sheet(isPresented: $picking) {
            ExercisePickerSheet(
                catalogue: model.catalogue,
                createNote: "Creates it in your exercise list and puts it in this day."
            ) { name, picked in
                if picked == nil { model.createAndAdd(name, to: dayKey) } else { model.addExercise(name, to: dayKey) }
            }
        }
    }

    private func editor(_ day: RoutineDay) -> some View {
        List {
            Section {
                LabeledContent("Name") {
                    TextField("Upper A", text: $label)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Color.onyx.textPrimary)
                        .focused($focus, equals: .label)
                        .submitLabel(.done)
                        .onSubmit { model.rename(dayKey, to: label) }
                }
                LabeledContent("Focus") {
                    TextField("Chest + Back", text: $sub)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Color.onyx.textPrimary)
                        .focused($focus, equals: .sub)
                        .submitLabel(.done)
                        .onSubmit { model.setSub(dayKey, sub) }
                }
                Picker("Weekday", selection: Binding(
                    get: { day.weekday },
                    set: { model.setWeekday(dayKey, $0) }
                )) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(RoutineBuilderView.weekdayNames[index]).tag(index)
                    }
                }
            } header: {
                OnyxSectionHeader("The day", .train)
            } footer: {
                // The key is the identity every logged session references. It is
                // deliberately not editable and worth saying so once.
                Text("Renaming is safe — sessions you have already logged stay attached to this day.")
            }

            Section {
                ForEach(Array(day.payload.exercises.enumerated()), id: \.offset) { index, exercise in
                    row(exercise, at: index)
                }
                .onDelete { model.removeExercises(at: $0, in: dayKey) }
                .onMove { model.moveExercises(from: $0, to: $1, in: dayKey) }
            } header: {
                OnyxSectionHeader("Movements", .train)
            } footer: {
                Text(day.payload.exercises.isEmpty
                     ? "Nothing here yet. The logger opens this day empty."
                     : "Drag to reorder — this is the order the logger deals them in. Swipe to remove.")
            }

            Section {
                Button {
                    picking = true
                } label: {
                    Label("Add a movement", systemImage: "plus")
                }
            }
        }
        .onyxFormBackground(.train)
    }

    /// One movement, opened out.
    ///
    /// ── EVERYTHING ON ONE ROW, NOT BEHIND A PUSH ────────────────────────────
    /// Four numbers per movement and eight movements per day. A detail screen
    /// per movement would be thirty-two pushes to write one session, and the
    /// whole reason people abandon routine builders. The fields are small and
    /// wrap, so AX5 stacks them rather than truncating.
    private func row(_ exercise: RoutineExercise, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            Text(exercise.name)
                .onyxType(.body).fontWeight(.semibold)
                .foregroundStyle(Color.onyx.textPrimary)

            FlowRow(spacing: OnyxSpace.m) {
                field("Sets", exercise.sets, .sets(index), 1...12) { value in
                    var updated = exercise
                    updated.sets = value
                    model.updateExercise(updated, at: index, in: dayKey)
                }
                // A cut drops assistance volume, and a deck that cannot say so
                // is a deck that has to be rewritten every phase change. `nil`
                // means "same as sets", which is the common case and the reason
                // this is a separate optional rather than a second required
                // number.
                optionalField("On a cut", exercise.cutSets, .cutSets(index), 0...12) { value in
                    var updated = exercise
                    updated.cutSets = value
                    model.updateExercise(updated, at: index, in: dayKey)
                }
                optionalField("Rest", exercise.restSec, .rest(index), 0...600, unit: "s") { value in
                    var updated = exercise
                    updated.restSec = value
                    model.updateExercise(updated, at: index, in: dayKey)
                }
            }

            HStack(spacing: OnyxSpace.m) {
                LabeledContent("Reps") {
                    TextField("8–12", text: Binding(
                        get: { exercise.reps },
                        set: { new in
                            var updated = exercise
                            updated.reps = new
                            model.updateExercise(updated, at: index, in: dayKey)
                        }
                    ))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Color.onyx.textPrimary)
                }
            }

            OnyxNumberRow(
                label: "Starting load",
                value: Binding(
                    get: { exercise.wk1Kg },
                    set: { new in
                        var updated = exercise
                        updated.wk1Kg = new
                        model.updateExercise(updated, at: index, in: dayKey)
                    }
                ),
                field: Field.load(index), focus: $focus,
                unit: "kg", range: 0...500, fractionLength: 2
            )
        }
        .padding(.vertical, OnyxSpace.xs)
    }

    private func field(
        _ label: String, _ value: Int, _ field: Field, _ range: ClosedRange<Int>,
        _ set: @escaping (Int) -> Void
    ) -> some View {
        Stepper(value: Binding(get: { value }, set: set), in: range) {
            LabeledContent(label) {
                Text(value.formatted(.number))
                    .onyxNumeral()
                    .foregroundStyle(Color.onyx.textPrimary)
            }
        }
        .accessibilityValue("\(value)")
    }

    /// A stepper over an OPTIONAL count, where the bottom of the range means
    /// "not set" rather than zero.
    private func optionalField(
        _ label: String, _ value: Int?, _ field: Field, _ range: ClosedRange<Int>,
        unit: String = "", _ set: @escaping (Int?) -> Void
    ) -> some View {
        let shown = value ?? range.lowerBound
        return Stepper(
            value: Binding(
                get: { value ?? (range.lowerBound - 1) },
                // Below the range is the "not set" rung: stepping down off the
                // bottom clears the field rather than clamping to it, which is
                // the only way to get back to nil without a second control.
                set: { set($0 < range.lowerBound ? nil : $0) }
            ),
            in: (range.lowerBound - 1)...range.upperBound
        ) {
            LabeledContent(label) {
                Text(value == nil ? "—" : "\(shown.formatted(.number))\(unit)")
                    .onyxNumeral()
                    .foregroundStyle(value == nil ? Color.onyx.textSecondary : Color.onyx.textPrimary)
            }
        }
        .accessibilityValue(value == nil ? "Not set" : "\(shown)")
    }
}
