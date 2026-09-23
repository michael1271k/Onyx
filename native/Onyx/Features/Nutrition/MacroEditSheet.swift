import SwiftUI
import OnyxUI
import OnyxCore

/// Correct the whole day's macros, with the arithmetic done for you.
///
/// ── WHY STEPPERS AND NOT FOUR NUMBER FIELDS ─────────────────────────────────
/// The sheet this replaces was a `Form` of four keyboards. Every one of them
/// could be left blank, none of them agreed with the others, and the calorie
/// field was a fifth number the user had to compute — so the commonest edit
/// (200 kcal out on a day that was otherwise right) meant retyping all four and
/// doing Atwater by hand to make them add up.
///
/// Here the four figures are one figure said four ways: move any of them and
/// `MacroMath` moves the rest, so the sheet can only ever produce a day that is
/// internally true. The calorie reading rolls its digits (`numericText`) as the
/// macros move, which is what makes the relationship legible without a sentence
/// explaining it.
struct MacroEditSheet: View {
    let model: NutritionModel
    @Environment(\.dismiss) private var dismiss

    @State private var macros = MacroMath.Macros()
    /// Every stepper tick, so one `.selection` trigger serves the whole sheet.
    @State private var ticks = 0
    /// Whether anything has been moved yet. Until it has, the sheet keeps
    /// following the day.
    @State private var touched = false
    @State private var detent: PresentationDetent = .medium
    /// What the day held when the sheet opened, if the two disagreed.
    @State private var recorded: Double?

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The day has arrived from GRDB. Until it has, the figures on screen are
    /// placeholder zeros and NOTHING may be written from them.
    private var loaded: Bool { model.entries != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OnyxSpace.m) {
                    reading
                    VStack(spacing: 0) {
                        // The floor is protein's own energy: protein is pinned
                        // through a calorie edit, so below that the minus can
                        // only buzz at a number that will not move.
                        StepperRow(label: "Calories", value: macros.kcal, unit: "kcal", step: 25,
                                   floor: (macros.protein ?? 0) * 4,
                                   tint: Color.onyx.calories) { edit(.calories($0)) }
                        divider
                        StepperRow(label: "Protein", value: macros.protein ?? 0, unit: "g", step: 5,
                                   tint: Color.onyx.protein) { edit(.protein($0)) }
                        divider
                        StepperRow(label: "Carbs", value: macros.carbs ?? 0, unit: "g", step: 5,
                                   tint: Color.onyx.carbs) { edit(.carbs($0)) }
                        divider
                        StepperRow(label: "Fat", value: macros.fat ?? 0, unit: "g", step: 5,
                                   tint: Color.onyx.fat) { edit(.fat($0)) }
                    }
                    .padding(.horizontal, OnyxSpace.m)
                    .onyxGlass(.tile)

                    Text("Apple Health owns the day's calories, so the figure above is its own even when the macros come to something else. Move a macro and the calories become the macro sum — 4 · protein, 4 · carbohydrate, 9 · fat; move the calories and carbohydrate and fat follow, in the proportion they already sit at, with protein staying put. Saving replaces the day's figures by hand, and Apple Health stops filling this date in — including its fibre and micronutrients.")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(OnyxSpace.l)
            }
            .onyxScreen(.fuel)
            .navigationTitle("Correct the day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    // ── WHY SAVE IS NOT ALWAYS AVAILABLE ────────────────────
                    // `setManualMacros` is a one-way door: the row it writes
                    // carries a sentinel that makes every future HealthKit
                    // sync skip this date. Saving a sheet nobody touched — or
                    // one opened before the day arrived — would freeze the day
                    // at zeros with no way back, which is the worst outcome
                    // this screen is capable of.
                    Button("Save") {
                        model.setManualMacros(
                            kcal: macros.kcal,
                            protein: macros.protein ?? 0,
                            carbs: macros.carbs ?? 0,
                            fat: macros.fat ?? 0
                        )
                        dismiss()
                    }
                    .disabled(!touched || !loaded)
                }
            }
            .sensoryFeedback(.selection, trigger: ticks)
            .onAppear { seed() }
            // ── WHY THIS FOLLOWS THE MODEL UNTIL IT IS TOUCHED ──────────────
            // The day arrives from a GRDB observation, and a sheet opened
            // before that first yield lands on four zeros. Saving from there
            // writes a hand-entered row of nothing over the day HealthKit had
            // — silently, because zeros look like a day nobody logged. So
            // until a stepper moves, the sheet is a VIEW of the day; after it
            // moves, it is the edit and the model stops overwriting it.
            .onChange(of: model.macrosForEditing) { _, _ in
                if !touched { seed() }
            }
        }
        // Half the sheet holds the dial-and-four-rows at the shipping text
        // size; at the accessibility sizes the same content is twice as tall,
        // so it opens on the detent that can actually show it.
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onAppear { if typeSize.isAccessibilitySize { detent = .large } }
    }

    private var divider: some View { Divider().overlay(Color.onyx.hairline) }

    /// The figure the whole sheet is about, and what it does to the day.
    private var reading: some View {
        VStack(spacing: OnyxSpace.xs) {
            Text(NutritionFormat.whole(macros.kcal))
                .onyxHero()
                .foregroundStyle(Color.onyx.textPrimary)
            Text(against)
                .onyxType(.caption)
                .onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
            // Only while the figure on screen still IS Health's. The first
            // stepper tick makes the reading the macros' own sum, and a caption
            // calling that "Health's figure" would be a lie one tap old.
            if recorded != nil, !touched {
                Text("Health's figure. The macros below come to \(NutritionFormat.whole(macros.atwater)) kcal.")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories for the day")
        .accessibilityValue("\(NutritionFormat.whole(macros.kcal)) kilocalories")
    }

    private var against: String {
        guard let target = model.targetKcal else { return "kcal for \(NutritionFormat.dayTitle(model.date))" }
        return "of \(NutritionFormat.whole(target)) kcal · \(NutritionFormat.remaining(target - macros.kcal, unit: "kcal"))"
    }

    /// Take the day as it is recorded.
    ///
    /// ── APPLE HEALTH IS THE TRUTH FOR TOTAL CALORIES ────────────────────────
    /// HealthKit records calories and macros separately and they disagree
    /// routinely — the seeded day is 1,420 kcal against macros that come to
    /// 1,450, because MyFitnessPal's entries carry a rounded energy figure per
    /// food and the gram columns are rounded independently.
    ///
    /// This sheet used to open on the Atwater sum, so 1,420 became 1,450 the
    /// moment you looked at it and Save wrote the corrected figure back over the
    /// day HealthKit had — silently, and every downstream deficit with it. A
    /// 30 kcal disagreement between two independent measurements is not an
    /// error to fix; the app's job is to REPORT the day, and Health owns the
    /// day's energy. So the recorded figure stands, the caveat line names the
    /// difference, and nothing moves unless a stepper is touched.
    private func seed() {
        let day = model.macrosForEditing
        let sum = day.atwater
        recorded = abs(sum - day.kcal) >= 1 && day.kcal > 0 ? day.kcal : nil
        macros = day
    }

    private func edit(_ change: MacroMath.Edit) {
        macros = MacroMath.adjust(macros, edited: change)
        touched = true
        ticks += 1
    }
}

/// One figure, with a minus and a plus either side of it.
///
/// Hold-to-repeat (`buttonRepeatBehavior`) because the real edit is rarely one
/// step — a day that is 200 kcal out is eight taps or one hold, and the second
/// is what a native stepper does.
private struct StepperRow: View {
    let label: String
    let value: Double
    let unit: String
    let step: Double
    /// Below this the minus cannot move the figure, so it stops offering to.
    var floor: Double = 0
    let tint: Color
    let onChange: (Double) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The glyph grows with the text, so its target has to as well.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 34

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // At the accessibility sizes the name and the figure cannot
                // share a line with two 44 pt targets — the label truncated to
                // "Pr…" and the steppers ran together. The name takes its own
                // line and the controls keep their size, which is the trade
                // the whole scale exists to make.
                VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                    name
                    HStack(spacing: OnyxSpace.s) {
                        figure
                        Spacer(minLength: OnyxSpace.s)
                        controls
                    }
                }
            } else {
                HStack(spacing: OnyxSpace.s) {
                    name
                    Spacer(minLength: OnyxSpace.s)
                    figure
                    controls
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(NutritionFormat.whole(value)) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(value + step)
            case .decrement: if value - step >= floor { onChange(value - step) }
            default: break
            }
        }
    }

    private var name: some View {
        HStack(spacing: OnyxSpace.s) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(label)
                .onyxType(.body)
                .foregroundStyle(Color.onyx.textPrimary)
        }
    }

    private var figure: some View {
        Text("\(NutritionFormat.whole(value)) \(unit)")
            .onyxType(.body)
            .onyxNumeral()
            .foregroundStyle(Color.onyx.textPrimary)
            .lineLimit(1)
            // The one number the sheet exists to set must never truncate: at
            // AX5 "1,955 kcal" is wider than the row that holds it and its two
            // 44 pt targets.
            .minimumScaleFactor(0.6)
            .layoutPriority(1)
    }

    private var controls: some View {
        // Spaced and given their own ground: butted together at the default
        // size they read as one control, and at AX5 the two symbols grew until
        // the minus and the plus overlapped into a single ✚.
        HStack(spacing: OnyxSpace.s) {
            button("minus", enabled: value - step >= floor) { onChange(value - step) }
            button("plus", enabled: true) { onChange(value + step) }
        }
    }

    private func button(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .onyxType(.body)
                .foregroundStyle(enabled ? Color.onyx.accent(.fuel) : Color.onyx.textTertiary)
                .frame(width: side, height: side)
                .background(Circle().fill(Color.onyx.hairline))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Correct the day") {
    MacroEditSheet(model: NutritionPreviews.model("fuel")!)
        .environment(AppEnvironment.preview)
}
#endif
