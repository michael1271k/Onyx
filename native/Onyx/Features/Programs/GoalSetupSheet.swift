import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// Three screens: what the program is for, where you are and where you are
/// heading, and the daily targets that follow (Precision E3).
///
/// ── ONBOARDING'S CHROME, ON PURPOSE ─────────────────────────────────────────
/// The same kind of task a person met on their first launch — a progress rail,
/// a heading, one primary button that says what it does — so it is drawn the
/// same way (`OnboardingFlow`). One container with its middle swapped, not a
/// stack of pushes: a back-swipe into a half-answered step two would carry a
/// pace computed from a weight the user has since changed.
///
/// ── ONE HERO PER STEP ───────────────────────────────────────────────────────
/// Step two's figure is the implied weekly rate, with the safe band drawn under
/// it as a bar and the rate as a tick on it — the one number the goal turns on.
/// Step three's is the day's calories, and it is the field itself. Everything
/// typed is an underlined cell (`OnyxFieldCell`, the InBody form's grammar),
/// so a figure you can change looks like one.
struct GoalSetupSheet: View {
    @State private var model: GoalSetupModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focus: Field?
    /// The cells' column width grows with the type, so AX sizes fall to one
    /// column rather than squeezing a five-digit BMR into a two-digit box.
    @ScaledMetric(relativeTo: .body) private var cellMinimum: CGFloat = 120
    @ScaledMetric(relativeTo: .title) private var heroFieldWidth: CGFloat = 112

    enum Field: Hashable {
        case weight, bodyFat, muscle, bmr, target, kcal, protein, carbs, fat
    }

    init(model: GoalSetupModel) {
        _model = State(initialValue: model)
    }

    private var accent: Color { OnyxDomain.train.accent }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                rail
                ScrollView {
                    VStack(alignment: .leading, spacing: OnyxSpace.xl) {
                        heading
                        content
                    }
                    .padding(OnyxSpace.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                footer
            }
            .onyxScreen(.train)
            .tint(accent)
            .navigationTitle(model.programLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .toolbar { OnyxKeyboardDone { focus = nil } }
        }
        .presentationDetents([.large])
        // Two screens of answers are worth one "are you sure": a stray swipe
        // would lose them. Cancel is right there.
        .interactiveDismissDisabled(model.step != .goal)
    }

    // MARK: - Chrome

    private var rail: some View {
        HStack(spacing: 3) {
            ForEach(GoalSetupModel.Step.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= model.step.rawValue ? accent : Color.onyx.textSecondary.opacity(0.25))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, OnyxSpace.xl)
        .padding(.top, OnyxSpace.m)
        .animation(.snappy(duration: 0.2), value: model.step)
        .accessibilityHidden(true)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .onyxType(.display)
                .foregroundStyle(Color.onyx.textPrimary)
                .accessibilityAddTraits(.isHeader)
            // Not at the accessibility sizes: there the line alone filled the
            // first screen, and the heading already says what the step is.
            if !typeSize.isAccessibilitySize {
                Text(subtitle)
                    .onyxType(.secondary)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Chrome, not content: at AX5 the heading and its line took the whole
        // first screen and pushed the step's fields below the fold. Capped
        // under AX5 — still the largest type in the sheet.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var title: String {
        switch model.step {
        case .goal:    "What is this program for?"
        case .now:     "Where you are, where you're going"
        case .targets: "Your daily targets"
        }
    }

    private var subtitle: String {
        switch model.step {
        case .goal:
            "Sets your daily calories and how many sets you train."
        case .now:
            "Your latest weigh-in and a target. The pace is checked against a safe weekly band."
        case .targets:
            "Worked out from your bodyweight and your goal. Tap any figure to change it."
        }
    }

    private var footer: some View {
        VStack(spacing: OnyxSpace.s) {
            if let failure = model.failure {
                Text(failure)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            AnyLayout(
                typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: OnyxSpace.s))
                    : AnyLayout(HStackLayout(spacing: OnyxSpace.m))
            ) {
                if model.step != .goal {
                    Button { focus = nil; model.back() } label: {
                        Text("Back").frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    // Ink, not the accent: accent text on an accent-tinted
                    // capsule over the material footer read near 3:1.
                    .tint(Color.onyx.textPrimary)
                }
                Button(action: primary) {
                    Text(primaryTitle).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Color.onyx.base)
                .disabled(!model.canAdvance || model.isSaving)
            }
        }
        .padding(OnyxSpace.xl)
        .background(.ultraThinMaterial)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var primaryTitle: String {
        switch model.step {
        case .goal, .now: "Continue"
        case .targets:    model.running ? "Save and apply" : "Save goal"
        }
    }

    private func primary() {
        focus = nil
        guard model.step == .targets else { return model.advance() }
        if model.save() { dismiss() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .goal:    goalStep
        case .now:     nowStep
        case .targets: targetsStep
        }
    }

    // MARK: - Step 1 · the goal

    private var goalStep: some View {
        VStack(spacing: OnyxSpace.m) {
            ForEach(ProgramGoal.allCases, id: \.rawValue) { goal in
                let selected = model.goal == goal
                Button { model.goal = goal } label: {
                    HStack(alignment: .top, spacing: OnyxSpace.m) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected ? accent : Color.onyx.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.label)
                                .onyxType(.body).fontWeight(.semibold)
                                .foregroundStyle(Color.onyx.textPrimary)
                            Text(goal.blurb)
                                .onyxType(.caption)
                                .foregroundStyle(Color.onyx.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(OnyxSpace.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onyxGlass(.row)
                    // The chosen card is outlined, not only its glyph: a
                    // pre-selected goal must be seen before Continue is tapped.
                    .overlay {
                        RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                            .strokeBorder(accent, lineWidth: selected ? 1.5 : 0)
                    }
                }
                .buttonStyle(.plain)
                .onyxPress(scale: 0.98)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    // MARK: - Step 2 · now and target

    private var nowStep: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.l) {
            PaceReading(plan: model.pace, goal: model.goal)

            card {
                VStack(alignment: .leading, spacing: OnyxSpace.s) {
                    cells {
                        targetCell
                    }
                    if let plan = model.pace, model.goal == .bodyFat || model.goal == .muscleMass {
                        // The conversion beside the number it converts.
                        Text("About \(GoalSetupModel.kg(plan.targetWeightKg))\u{00A0}kg on the scale\(model.goal == .muscleMass ? " — the muscle alone; a lean bulk adds a little fat and water" : "")")
                            .onyxType(.caption).onyxNumeral()
                            .foregroundStyle(Color.onyx.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Stepper(value: $model.horizonWeeks, in: GoalSetupModel.horizonRange) {
                        LabeledContent("Over") {
                            Text("\(model.horizonWeeks) weeks")
                                .onyxNumeral()
                                .foregroundStyle(Color.onyx.textPrimary)
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityValue("\(model.horizonWeeks) weeks")
                }
            }

            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                card {
                    cells {
                        cell("Weight", \.weightKg, .weight, "kg", StartingTargetsBuilder.weightRange, 1)
                        cell("Body fat", \.bodyFatPct, .bodyFat, "%", 2...70, 1)
                        cell("Muscle mass", \.muscleMassKg, .muscle, "kg", 5...120, 1)
                        cell("BMR", \.bmr, .bmr, "kcal", 500...5000, 0)
                    }
                }
                Text(readingCaption)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var targetCell: some View {
        switch model.goal {
        case .bulk, .cut:
            cell("Target weight", \.targetWeightKg, .target, "kg", StartingTargetsBuilder.weightRange, 1, marks: .target)
        case .recomp:
            cell("Hold at", \.targetWeightKg, .target, "kg", StartingTargetsBuilder.weightRange, 1, marks: .target)
        case .bodyFat:
            cell("Target body fat", \.targetBodyFatPct, .target, "%", 2...70, 1, marks: .target)
        case .muscleMass:
            cell("Target muscle", \.targetMuscleMassKg, .target, "kg", 5...120, 1, marks: .target)
        }
    }

    private var readingCaption: String {
        guard let date = model.readingDate else {
            return "No weigh-in yet — type your numbers. Only weight is needed."
        }
        return "From your weigh-in on \(ProgramsModel.shortDate(date) ?? date)."
    }

    // MARK: - Step 3 · targets

    private var targetsStep: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.l) {
            // The day's calories are the step's hero — and the field itself.
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                    OnyxNumberField(
                        label: "Calories", value: macroBinding(\.kcal), field: Field.kcal, focus: $focus,
                        range: 0...8000, alignment: .leading, width: heroFieldWidth, fixedWidth: true
                    )
                    .onyxType(.hero)
                    .foregroundStyle(Color.onyx.textPrimary)
                    .fixedSize()
                    .padding(.bottom, 3)
                    .overlay(alignment: .bottom) { underline(.kcal) }
                    Text("kcal a day")
                        .onyxType(.secondary)
                        .foregroundStyle(Color.onyx.textSecondary)
                }
                .contentShape(.rect)
                .onTapGesture { focus = .kcal }
                if let bmr = model.bmr, bmr > 0, let kcal = model.kcal, kcal > 0 {
                    Text("\((kcal / bmr).formatted(.number.precision(.fractionLength(1)))) × the BMR your scale measured (\(Int(bmr).formatted())\u{00A0}kcal)")
                        .onyxType(.caption).onyxNumeral()
                        .foregroundStyle(Color.onyx.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            card {
                cells {
                    cell("Protein", \.proteinG, .protein, "g", 0...500, 0, marks: .macros)
                    cell("Carbohydrate", \.carbsG, .carbs, "g", 0...900, 0, marks: .macros)
                    cell("Fat", \.fatG, .fat, "g", 0...300, 0, marks: .macros)
                }
            }
            if abs(model.atwaterGap) >= 20 {
                Text("The macros add up to \(model.targets.atwaterKcal.formatted()) kcal, \(abs(model.atwaterGap)) \(model.atwaterGap > 0 ? "above" : "below") the calories. Fine if it's deliberate.")
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.matchesFormula {
                Button("Recalculate from my bodyweight") { model.recomputeTargets() }
                    .buttonStyle(.bordered)
                    .tint(Color.onyx.textPrimary)
                    .frame(minHeight: 44)
            }
            if let template = model.recommended {
                recommendation(template)
            }
        }
    }

    private func recommendation(_ template: PlanTemplates.TemplatePlan) -> some View {
        card {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(template.label) suits this goal")
                            .onyxType(.body).fontWeight(.semibold)
                            .foregroundStyle(Color.onyx.textPrimary)
                        Text(ProgramsView.templateDetail(template))
                            .onyxType(.caption)
                            .foregroundStyle(Color.onyx.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "doc.on.doc").foregroundStyle(Color.onyx.textSecondary)
                }
                Toggle(isOn: $model.acceptTemplate) {
                    Text(model.hasDays
                         ? "Add it as a new program with this goal"
                         : "Fill \(model.programLabel) with its days")
                        .onyxType(.secondary)
                        .foregroundStyle(Color.onyx.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 44)
            }
        }
    }

    // MARK: - Pieces

    /// Cells two or three across, one at the accessibility sizes.
    private func cells<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: cellMinimum), spacing: OnyxSpace.m, alignment: .topLeading)],
            alignment: .leading, spacing: OnyxSpace.m
        ) {
            content()
        }
    }

    /// What an edit to a cell claims as the user's own: the target (no more
    /// re-proposing it) or the macros (no more recomputing them) — marked on
    /// the VALUE, not on commit, onboarding's rule: Back without dismissing
    /// the keyboard must not lose the edit.
    enum Marks { case none, target, macros }

    private func cell(
        _ label: String, _ key: ReferenceWritableKeyPath<GoalSetupModel, Double?>, _ field: Field,
        _ unit: String, _ range: ClosedRange<Double>, _ fraction: Int, marks: Marks = .none
    ) -> some View {
        OnyxFieldCell(
            label: label,
            value: Binding(
                get: { model[keyPath: key] },
                set: { new in
                    if new != model[keyPath: key] {
                        switch marks {
                        case .target: model.markTargetTouched()
                        case .macros: model.markTargetsTouched()
                        case .none: break
                        }
                    }
                    model[keyPath: key] = new
                }
            ),
            field: field, focus: $focus, unit: unit, range: range, fractionLength: fraction
        )
        .frame(minHeight: 44)
    }

    private func macroBinding(_ key: ReferenceWritableKeyPath<GoalSetupModel, Double?>) -> Binding<Double?> {
        Binding(
            get: { model[keyPath: key] },
            set: { new in
                if new != model[keyPath: key] { model.markTargetsTouched() }
                model[keyPath: key] = new
            }
        )
    }

    private func underline(_ field: Field) -> some View {
        Rectangle()
            .fill(focus == field ? Color.onyx.accent(.train) : Color.onyx.hairline)
            .frame(height: focus == field ? 1.5 : 1)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(OnyxSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onyxGlass(.row)
    }
}

/// The implied weekly rate — step two's hero — with the safe band as a bar
/// and the rate as a tick on it.
///
/// ── WHY A BAR AND NOT A SENTENCE ────────────────────────────────────────────
/// "−0.50 kg a week, inside −0.56 to −0.32" is three numbers to compare in
/// your head. A band with a tick is one glance: in or out, and which side.
/// The numbers stay, as the caption under the bar, for the reader who wants
/// them.
struct PaceReading: View {
    let plan: GoalPlan?
    let goal: ProgramGoal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            if let plan {
                // The unit under the figure at the accessibility sizes, where
                // beside it "kg a week" broke over two lines.
                AnyLayout(typeSize.isAccessibilitySize
                          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                          : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: OnyxSpace.xs))) {
                    Text(Self.signed(plan.weeklyRateKg))
                        .onyxType(.hero).onyxNumeral()
                        .foregroundStyle(Color.onyx.textPrimary)
                    Text("kg a week")
                        .onyxType(.secondary)
                        .foregroundStyle(Color.onyx.textSecondary)
                }
                Text(verdict(plan))
                    .onyxType(.secondary).fontWeight(.semibold)
                    .foregroundStyle(plan.verdict == .inside ? Color.onyx.good : Color.onyx.record)
                    .fixedSize(horizontal: false, vertical: true)
                PaceBand(plan: plan)
                    .frame(height: 24)
                    .animation(reduceMotion ? nil : OnyxMotion.move, value: plan.weeklyRateKg)
                Text("Safe pace: \(Self.signed(plan.bandMin)) to \(Self.signed(plan.bandMax))\u{00A0}kg a week")
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
            } else {
                Text(goal == .bodyFat
                     ? "Add your body fat and a target to see the pace."
                     : goal == .muscleMass
                        ? "Add your muscle mass and a target to see the pace."
                        : "Add your weight and a target to see the pace.")
                    .onyxType(.secondary)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func verdict(_ plan: GoalPlan) -> String {
        switch plan.verdict {
        case .inside: "Inside the safe pace."
        case .fast:   "Faster than is safe. Give it more weeks."
        case .slow:   "Slower than this goal needs. Move the target further or shorten the weeks."
        }
    }

    /// "−0.50", "+0.25", "0.00" — a rate always says which way.
    static func signed(_ value: Double) -> String {
        let text = abs(value).formatted(.number.precision(.fractionLength(2)))
        if value > 0 { return "+" + text }
        if value < 0 { return "−" + text }
        return text
    }
}

/// The band and the tick. The scale spans the band plus a margin either side
/// wide enough to show a rate twice the band's far end, so "fast" lands
/// visibly outside rather than pinned to the edge.
struct PaceBand: View {
    let plan: GoalPlan

    var body: some View {
        GeometryReader { geo in
            let span = max(abs(plan.bandMin), abs(plan.bandMax), 0.05) * 2
            let lo = -span, hi = span
            let x: (Double) -> CGFloat = { v in
                CGFloat((min(max(v, lo), hi) - lo) / (hi - lo)) * geo.size.width
            }
            let mid = geo.size.height / 2
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.onyx.hairline)
                    .frame(height: 6)
                    .offset(y: mid - 3)
                Capsule()
                    .fill(Color.onyx.good.opacity(0.55))
                    .frame(width: max(4, x(plan.bandMax) - x(plan.bandMin)), height: 6)
                    .offset(x: x(plan.bandMin), y: mid - 3)
                // Zero: the scale standing still.
                Rectangle()
                    .fill(Color.onyx.textSecondary)
                    .frame(width: 2, height: 16)
                    .offset(x: x(0) - 1, y: mid - 8)
                Capsule()
                    .fill(plan.verdict == .inside ? Color.onyx.good : Color.onyx.record)
                    .frame(width: 4, height: geo.size.height)
                    .offset(x: x(plan.weeklyRateKg) - 2)
            }
        }
        .accessibilityHidden(true)
    }
}
