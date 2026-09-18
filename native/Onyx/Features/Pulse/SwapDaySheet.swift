import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// The swap sheet, with a model of its own.
///
/// ── WHY THE DOOR OWNS THE MODEL ─────────────────────────────────────────────
/// Wave 2.9 deletes the Schedule tile from Pulse: a swap is a change to the
/// TRAINING WEEK and belongs beside the session it moves (§5.2 item 3 puts it
/// on the Workout tab's session card, in a `contextMenu`). But the Workout tab
/// has no `DayModel` — it reads a week through `WorkoutWeek` — and `SwapDaySheet`
/// needs the whole schedule context: the plan, the overrides, the layout, and
/// the logged days a placement could collide with.
///
/// So the door builds one and observes it only while the sheet is up. Eleven
/// streams for the life of a sheet is the honest cost of a screen that plans
/// two writes and refuses them when a committed session is in the way; keeping
/// them open on a tab that shows none of it is not.
struct SwapSheetDoor: View {
    @Environment(AppEnvironment.self) private var environment
    let date: String
    /// Supplied by previews and the screenshot harness.
    var seeded: DayModel?

    @State private var model: DayModel?

    var body: some View {
        Group {
            if let model {
                SwapDaySheet(model: model)
            } else {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if model == nil {
                model = seeded ?? DayModel(
                    database: environment.database, userId: environment.userIdString, date: date,
                    environment: environment
                )
            }
            await model?.observe()
        }
    }
}

/// Two ways to change a date, each previewed before it is confirmed.
///
/// ── A REST DAY IS A REARRANGEMENT, NOT A DELETION ───────────────────────────
/// Taking a rest day moves the displaced workout to the plan's next rest slot;
/// placing a workout is an exchange with wherever it was. Both are two rows,
/// both are refused when a committed session stands in the way, and the
/// sentence saying what will happen is shown BEFORE the button — an action that
/// rearranges your week silently is one you stop trusting.
struct SwapDaySheet: View {
    let model: DayModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKey: String?
    @State private var logged: [LoggedDay] = []

    private let accent = Color.onyx.accent(.train)

    var body: some View {
        DaySheet("Change \(Swap.shortDayLabel(model.date))", domain: .train) {
            VStack(alignment: .leading, spacing: OnyxSpace.l) {
                if model.isOverridden { undoSection }
                restSection
                Divider().overlay(Color.onyx.hairline)
                placeSection
            }
        }
        .onAppear {
            // One read, on appear: the dates a swap can touch are this week and
            // the 13-day horizon a displaced workout may be re-homed within.
            let ahead = (1...Swap.horizonDays).compactMap { ISODate.addDays(model.date, $0) }
            logged = model.loggedDays(Array(Set(Swap.weekDatesOf(model.date) + ahead)).sorted())
        }
    }

    // MARK: Undo

    /// Offered only on a date the plan did not choose. Undoing clears BOTH
    /// dates of the swap — a swap is two rows and undoing one half leaves the
    /// week rearranged in a way nothing on screen explains.
    @ViewBuilder
    private var undoSection: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            Label("This day was swapped", systemImage: "arrow.triangle.swap")
                .onyxType(.body).fontWeight(.semibold)
            if let note = model.swapNote {
                Text(note).onyxType(.caption).foregroundStyle(Color.onyx.textSecondary)
            }
            Button {
                withAnimation(OnyxMotion.move) { model.undoSwap() }
                dismiss()
            } label: {
                Text("Undo swap")
                    .onyxType(.secondary).fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .onyxPress(scale: 0.98)
            .onyxGlass(.row)
            .accessibilityHint("Clears both dates of the swap")
        }
    }

    private func labelFor(_ key: String?) -> String {
        key.flatMap { model.program.day(key: $0)?.label } ?? "a session"
    }

    // MARK: Rest

    @ViewBuilder
    private var restSection: some View {
        let plan = Swap.planRestDay(model.date, resolve: model.resolver())
        let block: SwapBlock? = {
            guard let to = plan.movedTo, let key = plan.moved?.dayKey else { return nil }
            return Swap.blockForPlacement(to, dayKey: key, logged: logged, sourceDate: model.date)
        }()
        let sentence = block.map { Swap.describeBlock($0, labelFor: labelFor) } ?? Swap.describeRestPlan(plan)

        VStack(alignment: .leading, spacing: 8) {
            Label("Take a rest day", systemImage: "moon.zzz")
                .font(.headline)
            Text(sentence)
                .font(.footnote)
                .foregroundStyle(Color.onyx.textSecondary)
            Button {
                if model.applySwap(plan.writes, note: Swap.describeRestPlan(plan)) { dismiss() }
            } label: {
                Text("Confirm rest day")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(block != nil || plan.outcome == .alreadyRest || plan.writes.isEmpty)
            .onyxPress(scale: 0.98)
            .onyxGlass(.row)
        }
    }

    // MARK: Place

    @ViewBuilder
    private var placeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Place a workout here", systemImage: "arrow.triangle.swap")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(model.program.days) { day in
                    dayChoice(day)
                }
            }
            if let key = selectedKey, let day = model.program.day(key: key) {
                placement(day)
            }
        }
    }

    private func dayChoice(_ day: ProgramDay) -> some View {
        let selected = selectedKey == day.key
        return Button {
            withAnimation(OnyxMotion.move) { selectedKey = day.key }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.label).font(.subheadline.weight(.semibold))
                    if let sub = day.sub {
                        Text(sub).font(.caption).foregroundStyle(Color.onyx.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .onyxPress(scale: 0.98)
        .onyxGlass(.row)
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                    .strokeBorder(accent.opacity(0.7), lineWidth: 1)
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func placement(_ day: ProgramDay) -> some View {
        let writes = Swap.planDaySwap(model.date, dayKey: day.key, resolve: model.resolver(), naturalDate: model.naturalDate(of: day))
        let source = writes.count > 1 ? writes[1].date : nil
        let block = Swap.blockForPlacement(model.date, dayKey: day.key, logged: logged, sourceDate: source)
        let alreadyHere = model.scheduled?.dayKey == day.key
        let sentence: String = {
            if let block { return Swap.describeBlock(block, labelFor: labelFor) }
            if alreadyHere { return "\(day.label) is already scheduled here." }
            guard let source else { return "\(day.label) placed on \(Swap.shortDayLabel(model.date))." }
            return "\(day.label) moves here; \(model.scheduled?.label ?? "Rest") moves to \(Swap.shortDayLabel(source))."
        }()

        VStack(alignment: .leading, spacing: 8) {
            Text(sentence)
                .font(.footnote)
                .foregroundStyle(Color.onyx.textSecondary)
            Button {
                if model.applySwap(writes, note: sentence) { dismiss() }
            } label: {
                Text("Confirm swap")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(block != nil || alreadyHere)
            .onyxPress(scale: 0.98)
            .onyxGlass(.row)
        }
    }
}
