import SwiftUI
import OnyxUI
import OnyxCore

/// The day's micronutrients, against the targets this athlete actually holds.
///
/// ── TWENTY ROWS WERE TWO AND A HALF SCREENS ─────────────────────────────────
/// Every nutrient had a 44 pt row to itself: a name on the left, a figure on
/// the right, a bar under both and — after §W6 — a third line saying how much
/// of it came from the stack. Twenty of those is a scroll with no shape to it,
/// and the thing you actually come here to ask ("what am I short of?") took
/// three swipes to answer.
///
/// Two per row halves the height, and the pair reads as a comparison rather
/// than as two more entries in a list. §3.6 allows exactly this: a `List` for
/// tables, "unless it is a grid" — and this is a grid, of cells, inside the
/// sections a `List` gives for free.
///
/// ── FOUR SECTIONS THAT NAME WHAT THEY HOLD ──────────────────────────────────
/// The old groups were Fuel · Electrolytes · Vitamins & minerals · Performance
/// stack, which put iron under "Vitamins" and sorted by where a nutrient comes
/// from rather than what it is. Macros · Vitamins · Minerals · Other is the
/// taxonomy a label uses, and it is now declared once in `NutrientTargets` so
/// this screen and the web page cannot disagree about it.
///
/// ── FLOOR AND CEILING ARE NOT THE SAME BAR ──────────────────────────────────
/// A floor (fibre, potassium) is met by going UP and past the tick is good; a
/// ceiling (sodium, added sugar) is met by staying DOWN and past the tick is
/// the warning. Same geometry, opposite verdict, so the tick marks WHERE the
/// target is and the colour says which side of it you want to be on.
struct NutrientsView: View {
    let model: NutritionModel

    /// `NutrientTargets` hardcodes protein at 170 g, which is the rung's figure
    /// and not necessarily the DAY's — an override or a lever moves it, and
    /// this screen sat one tap from a tab reading "175 / 150 g" while it said
    /// "175 / 170 g" about the same nutrient on the same day.
    private func resolved(_ target: NutrientTarget) -> NutrientTarget {
        guard target.key == "protein", let protein = model.target.protein, protein > 0 else { return target }
        var resolved = target
        resolved.target = protein
        return resolved
    }

    var body: some View {
        // Hoisted: `nutrients` walks the day's rows and runs a `JSONDecoder`
        // over the micros bundle on every access, and reading it inside the
        // `ForEach` did that a dozen times per body pass, on every scroll.
        let day = model.nutrients
        let fromStack = model.stack.nutrients
        // Resolved ONCE, and everything on the screen reads this array. The
        // toolbar used to score `NutrientTargets.all` — the raw table — while
        // the section headers scored the resolved copy, so on a day whose
        // protein target is not 170 g the two counts could disagree about
        // whether protein was met. That is the same bug `resolved` exists to
        // fix, reintroduced one line above the fix.
        let targets = NutrientTargets.all.map(resolved)
        let reading: (NutrientTarget) -> Double? = { target in
            let food = day[target.key], stack = fromStack[target.key]
            guard food != nil || stack != nil else { return nil }
            return (food ?? 0) + (stack ?? 0)
        }

        List {
            ForEach(NutrientTargets.groups, id: \.self) { group in
                let section = targets.filter { $0.group == group }
                Section {
                    grid(section, day: day, stack: fromStack)
                } header: {
                    header(group, section, reading: reading)
                } footer: {
                    if group == NutrientTargets.groups.last {
                        Text("A pill glyph marks what only the stack delivers: Apple Health measures none of those, so the reading is the protocol — a dose counts once its slot has passed, unless it was skipped.")
                    }
                }
            }
        }
        // §3.1's section gap, not the platform default — which is 34 pt here and
        // put a third of a screen of black between four cards.
        .listSectionSpacing(OnyxSpace.l)
        .onyxFormBackground(.fuel)
        .navigationTitle("Nutrients")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The screen's own score, in the one place iOS puts a screen-level
            // summary. A row of its own would have been a box that repeats the
            // sections under it (§3.6), and it would have cost 44 pt to say
            // eight characters.
            ToolbarItem(placement: .topBarTrailing) { total(targets, reading: reading) }
        }
    }

    // MARK: - The grid

    /// Two across, one at an accessibility size — where a name and a figure
    /// cannot share a cell, let alone two cells share a row.
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.m, alignment: .topLeading),
              count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    private func grid(
        _ targets: [NutrientTarget], day: [String: Double], stack: [String: Double]
    ) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: OnyxSpace.m) {
            ForEach(targets, id: \.key) { target in
                NutrientCell(target: target, amount: day[target.key], stack: stack[target.key])
            }
        }
        // The grid IS the row: the section's own inset is the card's padding,
        // and a second one inside it would be a box inside a box.
        .padding(.vertical, OnyxSpace.xs)
    }

    // MARK: - The counts

    private func header(
        _ group: String, _ targets: [NutrientTarget], reading: (NutrientTarget) -> Double?
    ) -> some View {
        let score = NutrientTargets.completion(targets, reading: reading)
        return HStack(alignment: .firstTextBaseline) {
            OnyxSectionHeader(group, .fuel)
            Spacer(minLength: OnyxSpace.s)
            if score.measured > 0 {
                Text("\(score.met)/\(score.measured)")
                    .onyxType(.micro).onyxNumeral()
                    .foregroundStyle(Color.onyx.textTertiary)
                    .accessibilityLabel("\(score.met) of \(score.measured) met")
            }
        }
    }

    private func total(_ targets: [NutrientTarget], reading: (NutrientTarget) -> Double?) -> some View {
        let score = NutrientTargets.completion(targets, reading: reading)
        return Text("\(score.met)/\(score.measured) met")
            .onyxType(.caption).onyxNumeral()
            .foregroundStyle(score.met == score.measured && score.measured > 0
                             ? Color.onyx.good : Color.onyx.textSecondary)
            .accessibilityLabel(
                "\(score.met) of \(score.measured) measured targets met. "
                + "Nutrients nothing measured are not counted."
            )
    }
}

// MARK: - One nutrient

/// Name, figure, and a bullet bar with the target marked on it.
private struct NutrientCell: View {
    let target: NutrientTarget
    /// What FOOD delivered. `nil` when nothing measured it — an em dash, never
    /// a zero.
    let amount: Double?
    /// What the STACK delivered, credited by `StackCredit`.
    var stack: Double?

    private var total: Double? {
        guard amount != nil || stack != nil else { return nil }
        return (amount ?? 0) + (stack ?? 0)
    }

    /// A floor fills toward good; a ceiling fills toward danger, and only turns
    /// once it is genuinely past.
    private var tint: Color {
        guard NutrientTargets.isMet(target, total: total) != nil else { return Color.onyx.textTertiary }
        switch target.kind {
        case .floor:   return NutrientTargets.isMet(target, total: total) == true ? Color.onyx.good : OnyxDomain.fuel.accent
        case .ceiling: return NutrientTargets.isMet(target, total: total) == true ? Color.onyx.good : Color.onyx.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            name
            figure
            bar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(target.label)
        .accessibilityValue(spoken)
    }

    private var name: some View {
        HStack(spacing: 3) {
            Text(target.label)
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if target.fromStack {
                // A glyph, not a colour: the one fact that changes how the
                // reading was arrived at has to survive a colour-blind reader
                // and a greyscale screenshot.
                Image(systemName: "pills.fill")
                    .onyxType(.micro)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
    }

    private var figure: some View {
        Text(figures)
            .onyxType(.secondary).onyxNumeral()
            .foregroundStyle(Color.onyx.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// ── A BULLET BAR, NOT A PROGRESS BAR ────────────────────────────────────
    /// Scaled to the READING as well as the target, so the tick sits where the
    /// target actually is and an overshoot is visible as an overshoot. A bar
    /// normalised to the target caps at full and then says nothing more —
    /// which on a ceiling is precisely the case worth seeing.
    ///
    /// Two fills: what food delivered, and what the stack put on top of it. A
    /// single total would hide the one fact worth knowing here — that a target
    /// is being met by a tablet.
    private var bar: some View {
        let scale = max(total ?? 0, target.target) * 1.15
        return GeometryReader { geometry in
            let width = geometry.size.width
            let x = { (value: Double) in scale > 0 ? width * min(max(value / scale, 0), 1) : 0 }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.onyx.hairline).frame(height: 3)
                Capsule().fill(tint.opacity(0.45)).frame(width: x(total ?? 0), height: 3)
                Capsule().fill(tint).frame(width: x(amount ?? 0), height: 3)
                // The target, marked. 1 pt of ink and the only thing on this
                // bar that does not move with the reading.
                Rectangle()
                    .fill(Color.onyx.textSecondary)
                    .frame(width: 1, height: 5)
                    .offset(x: x(target.target) - 0.5)
            }
            .frame(height: 5, alignment: .center)
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private var figures: String {
        let goal = "\(NutritionFormat.amount(target.target)) \(target.unit)"
        guard let total else { return target.kind == .floor ? "aim \(goal)" : "under \(goal)" }
        return "\(NutritionFormat.amount(total)) / \(goal)"
    }

    private var spoken: String {
        let direction = target.kind == .floor ? "at least" : "at most"
        let goal = "\(direction) \(NutritionFormat.amount(target.target)) \(target.unit)"
        guard let total else {
            return target.fromStack
                ? "not measured — the stack has not delivered it yet, \(goal)"
                : "not measured, \(goal)"
        }
        var parts = ["\(NutritionFormat.amount(total)) \(target.unit)"]
        if let stack, stack > 0, (amount ?? 0) > 0 {
            parts.append("\(NutritionFormat.amount(stack)) of it from the stack")
        } else if target.fromStack {
            parts.append("from the stack")
        }
        parts.append(goal)
        parts.append(NutrientTargets.isMet(target, total: total) == true ? "met" : "not met")
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Nutrients") {
    NavigationStack {
        NutrientsView(model: NutritionPreviews.model("fuel")!)
    }
    .environment(AppEnvironment.preview)
}
#endif
