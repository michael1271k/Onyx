import SwiftUI
import Charts
import OnyxUI
import OnyxCore
import OnyxData

/// The Nutrition tab — one day's intake against the target in force that day.
///
/// ── WHAT WAVE 2.6 DELETED, AND WHY ──────────────────────────────────────────
/// The screen was five stacked cards and about 1,400 pt of scroll for four
/// numbers. Three of the five said the same thing three times: "Logged" listed
/// one HealthKit row whose figures were already the hero above it, "Day target"
/// restated the denominator printed inside every gauge, and "Context" was a
/// full-height card holding one picker and one toggle. A box that only repeats
/// the box above it is the §3.6 test a screen fails silently, because each card
/// looks reasonable on its own.
///
/// What is left is the day itself: what was eaten against what was asked, the
/// three macros, water, and the week the day sits in — each at the height of its
/// own content. Everything the deleted cards could DO is still reachable: the
/// day's shape and its flags through the context chips, a macro correction
/// through a long press on the figures it corrects.
struct NutritionTabView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Supplied only by previews and the screenshot harness. The app never
    /// passes one.
    var seeded: NutritionModel?

    @State private var resolved: NutritionModel?

    var body: some View {
        Group {
            if let resolved {
                NutritionScreen(model: resolved)
            } else {
                ProgressView().controlSize(.large)
            }
        }
        // Keyed on the resolver's presence: `.task` is not an observation
        // scope, so a resolver that arrives after the first run must re-run it.
        .task(id: environment.targets == nil) {
            if resolved == nil, let targets = seeded?.targets ?? environment.targets {
                resolved = seeded ?? NutritionModel(database: environment.database, userId: environment.userIdString, targets: targets)
            }
            await resolved?.observe()
        }
        // Midnight (§6.4): the rung is resolved against `today`, so the day
        // that just ended must stop counting as today.
        .onChange(of: environment.today) { _, _ in resolved?.refreshToday() }
    }
}

// MARK: - The screen

private struct NutritionScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    let model: NutritionModel

    @State private var sheet: Sheet?

    /// One presentation, four destinations. Two `.sheet` modifiers on one view
    /// is a documented way to get a second sheet that never presents.
    private enum Sheet: String, Identifiable {
        case macros, target, water, calendar
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: OnyxSpace.m) {
                if let failure = model.failure {
                    OnyxBanner(tone: .failure, title: "Not saved locally", message: failure)
                }
                CaloriesCard(model: model) { sheet = .macros }
                MacrosCard(model: model) { sheet = .macros }
                WaterRow(model: model) { sheet = .water }
                ContextChips(model: model) { sheet = .target }
                WeekStrip(model: model)
                NutrientsRow(model: model)
            }
            .padding(.horizontal, OnyxSpace.l)
            .padding(.top, OnyxSpace.s)
            .padding(.bottom, OnyxSpace.xl)
        }
        .onyxScreen(.fuel)
        .foregroundStyle(Color.onyx.textPrimary)
        .navigationTitle(NutritionFormat.dayTitle(model.date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                toolbarButton("chevron.left", "Previous day") { model.shift(-1) }
                toolbarButton("chevron.right", "Next day") { model.shift(1) }
                    .disabled(model.isToday)
                toolbarButton("calendar", "Choose a day") { sheet = .calendar }
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .macros: MacroEditSheet(model: model)
            case .target: DayTargetSheet(model: model)
            case .water: WaterSheet(model: model)
            case .calendar: DayPickerSheet(model: model)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshToday() }
        }
    }

    private func toolbarButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
    }
}

/// Which day the tab is showing — the fourth of its four sheets.
///
/// A named type and not the computed property it was (W11), for the reason the
/// harness states on `macro-edit`: a sheet nothing can present outside its own
/// screen is a sheet nothing photographs, and this one had never been in a
/// shot. Its three siblings — `MacroEditSheet`, `DayTargetSheet`, `WaterSheet`
/// — were already types; this is the one that was not.
struct DayPickerSheet: View {
    let model: NutritionModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            // A graphical picker at AX5 is taller than the sheet that holds it,
            // and a `frame(maxHeight:)` with nothing to scroll simply clipped
            // the last fortnight of the month off the bottom.
            //
            // ── ONE SCROLLER, NOT A `ViewThatFits` PAIR (W11) ───────────────
            // This was `ViewThatFits(in: .vertical) { self; ScrollView { self } }`,
            // guarding against "the picker's own scroll view inside the
            // sheet's". The sheet has no scroll view — nothing between here and
            // the presentation scrolls — so the state it guarded against cannot
            // arise, and the branch it guarded is the one it picks anyway: the
            // month grid is ~340 pt and a medium detent leaves ~380 pt under the
            // bar, so on an accessibility size it already lost the first branch
            // and on a shipping one it never needed the second. All the pair
            // bought was a second graphical picker built on every layout pass.
            ScrollView {
                DatePicker(
                    "Day",
                    selection: Binding(
                        get: { LogicalDay.date(fromISO: model.date) ?? Date() },
                        set: { model.select(date: LogicalDay.iso($0)) }
                    ),
                    in: ...(LogicalDay.date(fromISO: model.today) ?? Date()),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(Color.onyx.accent(.fuel))
                .padding(.horizontal, OnyxSpace.l)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .onyxScreen(.fuel)
            .navigationTitle("Choose a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }
}

// MARK: - Calories

/// The one hero on the tab: eaten, asked for, and what is left, on one line —
/// then the bar that says the same thing without being read.
private struct CaloriesCard: View {
    let model: NutritionModel
    let onEdit: () -> Void

    private var eaten: Double? { model.eaten?.kcal }
    private var target: Double? { model.targetKcal }

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            figures
            TargetBar(value: eaten, target: target, tint: Color.onyx.calories, over: OnyxDomain.fuel.end)
            HStack(spacing: OnyxSpace.s) {
                AdherenceDots(days: model.week)
                if model.isMacrosManual {
                    Spacer(minLength: OnyxSpace.s)
                    NutritionBadge("Manual")
                }
            }
        }
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.tile)
        .contentShape(.rect)
        .onLongPressGesture(minimumDuration: 0.45, perform: onEdit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories")
        .accessibilityValue(spoken)
        .accessibilityAction(named: "Correct the day's macros", onEdit)
    }

    /// `1,420` · `/ 1,955 kcal` · `535 left`. One line while one line holds all
    /// three, then two, and at the accessibility sizes one fact per line.
    ///
    /// The last candidate has NO `lineLimit` and NO `fixedSize`: `ViewThatFits`
    /// falls back to its final child whether or not that one fits either, so a
    /// last resort that refuses to wrap does not overflow its tile — it
    /// overflows the SCREEN, and takes the whole scroll view's width with it.
    private var figures: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                hero(oneLine: true)
                Spacer(minLength: OnyxSpace.s)
                remaining(oneLine: true)
            }
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                hero(oneLine: true)
                remaining(oneLine: true)
            }
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                hero(oneLine: false)
                remaining(oneLine: false)
            }
        }
    }

    @ViewBuilder
    private func hero(oneLine: Bool) -> some View {
        let against = target.map { "/ \(NutritionFormat.whole($0)) kcal" } ?? "kcal · no target"
        if oneLine {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.xs) {
                Text(eaten.map(NutritionFormat.whole) ?? "—").onyxHero()
                Text(against)
                    .onyxType(.secondary)
                    .onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
            }
            .lineLimit(1)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(eaten.map(NutritionFormat.whole) ?? "—").onyxHero()
                Text(against)
                    .onyxType(.secondary)
                    .onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func remaining(oneLine: Bool) -> some View {
        if let left = model.remaining(eaten, target) {
            Text(NutritionFormat.remaining(left, unit: "kcal"))
                .onyxType(.secondary)
                .onyxNumeral()
                .foregroundStyle(left >= 0 ? Color.onyx.textSecondary : OnyxDomain.fuel.end)
                .lineLimit(oneLine ? 1 : nil)
        }
    }

    /// The dots live inside this element, which is `.ignore`, so their own
    /// label never reaches VoiceOver — the week has to be said here or not at
    /// all. It is also the only text equivalent for a strip that is otherwise
    /// pure colour.
    private var spoken: String {
        let week = AdherenceDots.spoken(model.week)
        let manual = model.isMacrosManual ? ", entered by hand" : ""
        guard let eaten else { return "nothing logged\(manual). \(week)" }
        guard let target else { return "\(NutritionFormat.whole(eaten)) kilocalories, no target\(manual). \(week)" }
        let left = target - eaten
        let side = left >= 0 ? "\(NutritionFormat.whole(left)) left" : "\(NutritionFormat.whole(-left)) over"
        return "\(NutritionFormat.whole(eaten)) of \(NutritionFormat.whole(target)) kilocalories, \(side)\(manual). \(week)"
    }
}

/// A capacity bar whose scale is `max(target, eaten)`, so the target is a MARK
/// on it rather than its end.
///
/// ── WHY NOT `Gauge(.accessoryLinearCapacity)` ───────────────────────────────
/// That is what this was, and it is the right LOOK — the geometry below matches
/// it deliberately. It cannot carry the reading, twice over: a capacity gauge
/// clamps at full, so 1,955 kcal and 2,600 kcal draw the same full bar, and the
/// one number on this screen that must be unmistakable is the one it cannot
/// show; and `.tint(Gradient)` is ignored by that style, so the coral overshoot
/// segment never rendered at all — it drew a flat honey bar with a tick in it,
/// which says "on target" for a day that is 350 kcal over.
///
/// Three capsules and a hairline say it exactly: the scale runs to whichever of
/// target and intake is larger, the fill is Solar to the target and coral past
/// it, and the tick sits where the target is.
private struct TargetBar: View {
    let value: Double?
    let target: Double?
    let tint: Color
    let over: Color

    /// The height of `accessoryLinearCapacity`, and it scales with the type for
    /// the same reason that style does.
    @ScaledMetric(relativeTo: .footnote) private var thickness: CGFloat = 6

    private var scale: Double { max(target ?? 0, value ?? 0, 1) }
    private var targetFraction: Double { min(max((target ?? 0) / scale, 0), 1) }
    private var valueFraction: Double { min(max((value ?? 0) / scale, 0), 1) }
    private var isOver: Bool {
        guard let value, let target, target > 0 else { return false }
        return value > target
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                // The rail is NEUTRAL, not a dim wash of the fill. A tinted
                // track on a day with nothing logged draws a full brown bar
                // where the reading should be an empty one, and "no data" and
                // "at target" are the two states that must never look alike.
                Capsule().fill(Color.onyx.textTertiary.opacity(0.35))
                Capsule()
                    .fill(tint)
                    .frame(width: width * min(valueFraction, targetFraction))
                if isOver {
                    Capsule()
                        .fill(over)
                        .frame(width: width * max(0, valueFraction - targetFraction))
                        .offset(x: width * targetFraction)
                    // 1 pt of the ground, cut through the bar where the target
                    // is. Only when something is past it — a tick at the end of
                    // a bar that is not full is the bar's own edge said twice.
                    Rectangle()
                        .fill(Color.onyx.base)
                        .frame(width: 1)
                        .offset(x: width * targetFraction)
                }
            }
        }
        .frame(height: thickness)
        .accessibilityHidden(true)
    }
}

/// The week as seven dots: what each day was, not how much of it there was.
///
/// Colour carries the KIND of day (declared exception, estimated figures,
/// tracked, nothing logged) rather than adherence to a number — a day at 92 %
/// of target and a day at 104 % are both days that were tracked, and the strip
/// below already draws how close each one came.
private struct AdherenceDots: View {
    let days: [NutritionDay]

    /// Six points at the shipping size, and it grows: a dot strip frozen at
    /// 6 pt beside type three times its usual height stops being legible as a
    /// row of anything.
    @ScaledMetric(relativeTo: .footnote) private var dot: CGFloat = 6

    var body: some View {
        HStack(spacing: OnyxSpace.xs) {
            ForEach(days) { day in
                Circle()
                    .fill(colour(day))
                    .frame(width: dot, height: dot)
            }
        }
        .frame(minHeight: dot * 2)
        // Spoken by the card that contains it — an `.ignore` parent discards
        // this element entirely, so a label here would go nowhere.
        .accessibilityHidden(true)
    }

    private func colour(_ day: NutritionDay) -> Color {
        if ExceptionDay.isException(day.exception) { return OnyxDomain.recover.accent }
        if day.estimated { return Color.onyx.calories }
        return day.isTracked ? Color.onyx.good : Color.onyx.textTertiary
    }

    static func spoken(_ days: [NutritionDay]) -> String {
        guard !days.isEmpty else { return "The week is still loading" }
        let tracked = days.filter(\.isTracked).count
        let exceptions = days.filter { ExceptionDay.isException($0.exception) }.count
        let base = "\(tracked) of \(days.count) days tracked"
        return exceptions > 0 ? "\(base), \(exceptions) an exception" : base
    }
}

// MARK: - Macros

/// Three rows, one tile. Protein first because it is the figure the whole plan
/// is built on, and the two that follow are the ones a lever moves.
private struct MacrosCard: View {
    let model: NutritionModel
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MacroRow(label: "Protein", eaten: model.eaten?.protein, target: model.target.protein,
                     tint: Color.onyx.protein, model: model, onEdit: onEdit)
            divider
            MacroRow(label: "Carbs", eaten: model.eaten?.carbs, target: model.target.carbs,
                     tint: Color.onyx.carbs, tracked: model.tracksCarbs, model: model, onEdit: onEdit)
            divider
            MacroRow(label: "Fat", eaten: model.eaten?.fat, target: model.target.fat,
                     tint: Color.onyx.fat, tracked: model.tracksFat, model: model, onEdit: onEdit)
        }
        .padding(.horizontal, OnyxSpace.m)
        .onyxGlass(.tile)
        .contentShape(.rect)
        .onLongPressGesture(minimumDuration: 0.45, perform: onEdit)
    }

    private var divider: some View { Divider().overlay(Color.onyx.hairline) }
}

/// One macro on one line: name · bar · `128 / 170 g` · what is left.
///
/// 36 pt at the default text size, which is what lets three of them and a header
/// occupy the space one of the old gauges did. The 44 pt rule is about TARGETS,
/// and nothing in this row is tappable on its own — the whole tile carries the
/// long press.
private struct MacroRow: View {
    let label: String
    let eaten: Double?
    let target: Double?
    let tint: Color
    var tracked = true
    let model: NutritionModel
    let onEdit: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            // ── WHY THE ACCESSIBILITY SIZES ARE A SWITCH, NOT A CANDIDATE ───
            // `ViewThatFits` decides per ROW, and the three macro names are
            // different lengths — at AX5 "Fat" still fit on one line while
            // "Protein" and "Carbs" had wrapped, so the card drew two layouts
            // at once. Three rows of one thing must agree, and the only thing
            // that can make them agree is the text size they all share.
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: OnyxSpace.s) {
                        name
                        bar
                        figures(oneLine: true)
                        remaining
                    }
                    HStack(spacing: OnyxSpace.s) {
                        name
                        bar
                        figures(oneLine: true)
                    }
                    stacked
                }
            }
        }
        .frame(minHeight: 36)
        .opacity(tracked ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
        // On the ROW, not on the card. A custom action needs an accessibility
        // element to host it, and the card is a plain container whose children
        // are these three rows — an action declared up there has no host.
        .accessibilityAction(named: "Correct the day's macros", onEdit)
    }

    /// The last resort, and the whole layout at the accessibility sizes. It
    /// wraps: `ViewThatFits` uses its final child even when that child does not
    /// fit either, so a row of `fixedSize` numerals here would push the tile
    /// past the screen edge and drag every other tile's width with it.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            name
            HStack(spacing: OnyxSpace.s) {
                figures(oneLine: false)
                Spacer(minLength: OnyxSpace.s)
                remaining
            }
            bar
        }
    }

    private var name: some View {
        Text(label)
            .onyxType(.secondary)
            .foregroundStyle(Color.onyx.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var bar: some View {
        if tracked {
            TargetBar(value: eaten, target: target, tint: tint, over: Color.onyx.danger)
                .frame(minWidth: 40)
        } else {
            Spacer(minLength: OnyxSpace.s)
        }
    }

    /// `128 / 170 g`, or an em dash for a macro this day does not grade — the
    /// figure exists in Health either way, and a greyed number with no target
    /// beside it reads as a target of zero.
    private func figures(oneLine: Bool) -> some View {
        Group {
            if !tracked {
                Text("—")
            } else if let eaten {
                Text(target.map { "\(NutritionFormat.whole(eaten)) / \(NutritionFormat.whole($0)) g" }
                     ?? "\(NutritionFormat.whole(eaten)) g")
            } else {
                Text(target.map { "— / \(NutritionFormat.whole($0)) g" } ?? "—")
            }
        }
        .onyxType(.secondary)
        .onyxNumeral()
        .foregroundStyle(Color.onyx.textPrimary)
        .lineLimit(oneLine ? 1 : nil)
        // The numbers keep their width against the bar rather than the other
        // way round; a truncated "128 / 17…" is worse than a shorter gauge.
        .layoutPriority(1)
    }

    @ViewBuilder
    private var remaining: some View {
        if tracked, let left = model.remaining(eaten, target) {
            Text(NutritionFormat.remaining(left, unit: "g"))
                .onyxType(.caption)
                .onyxNumeral()
                .foregroundStyle(left >= 0 ? Color.onyx.textTertiary : Color.onyx.danger)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var spoken: String {
        guard tracked else { return "not graded today" }
        guard let eaten else { return "nothing logged" }
        guard let target, target > 0 else { return "\(NutritionFormat.whole(eaten)) grams, no target" }
        let left = target - eaten
        let side = left >= 0 ? "\(NutritionFormat.whole(left)) grams left" : "\(NutritionFormat.whole(-left)) grams over"
        return "\(NutritionFormat.whole(eaten)) of \(NutritionFormat.whole(target)) grams, \(side)"
    }
}

// MARK: - Water

/// One row, one tap. Water is the most repeated write on the tab and the least
/// interesting to read, so it costs a glass per tap and holds the sheet behind
/// a long press.
///
/// ── WHY THIS IS NOT A `Button` ──────────────────────────────────────────────
/// It was, with `.onLongPressGesture` on the outside — and a Button and a
/// parent long press contend for the same touch sequence: either the press
/// never fires (and `WaterSheet`, the only way to undo a mistaken tap, is
/// unreachable) or both fire and every long press logs a phantom glass on the
/// way to the sheet. Neither shows up in a screenshot. One surface, two
/// gestures that cannot both win, and the button TRAITS added back by hand so
/// VoiceOver still gets a default action.
private struct WaterRow: View {
    let model: NutritionModel
    let onEdit: () -> Void

    @State private var glasses = 0

    var body: some View {
        HStack(spacing: OnyxSpace.s) {
            Image(systemName: "drop.fill")
                .foregroundStyle(Color.onyx.water)
                .accessibilityHidden(true)
            Text(figures)
                .onyxType(model.isAwaitingHealthWater ? .caption : .secondary)
                .onyxNumeral()
                .foregroundStyle(model.isAwaitingHealthWater
                                 ? Color.onyx.textSecondary : Color.onyx.textPrimary)
                .layoutPriority(1)
            TargetBar(value: model.waterMl, target: model.waterGoalMl,
                      tint: Color.onyx.water, over: Color.onyx.water)
                .frame(minWidth: 40)
            if model.isWaterManual {
                NutritionBadge("Manual")
            }
        }
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OnyxSpace.m)
        .contentShape(.rect)
        .onyxGlass(.tile)
        .onTapGesture { add() }
        .onLongPressGesture(minimumDuration: 0.45, perform: onEdit)
        .sensoryFeedback(.selection, trigger: glasses)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Water")
        .accessibilityValue(spoken)
        .accessibilityHint("Adds \(NutritionFormat.whole(NutritionModel.glassMl)) millilitres")
        // `.ignore` discards the child Button's own activation, so the default
        // action is put back explicitly — without it VoiceOver reads a hint
        // promising a glass of water and has nothing to activate.
        .accessibilityAction { add() }
        .accessibilityAction(named: "Set the day's water", onEdit)
    }

    /// ── NO "HAS THE DAY LOADED YET" GUARD ──────────────────────────────────
    /// There was one — `guard model.dailyLog != nil` — and it is the whole of
    /// the "today's water stays 0" bug. `dailyLogStream` yields nil for a date
    /// with no `daily_logs` row, and a day has no row until something writes
    /// one: `ingest` returns at `guard !payload.isEmpty` when HealthKit has
    /// nothing yet, which is every morning before the first foreground sync and
    /// every day on a phone where the read was denied. So the tap on the tab's
    /// most-repeated control did nothing at all, silently, on exactly the days
    /// you would most want to log a glass — and the guard was self-locking,
    /// because the write it blocked is the one that would have minted the row.
    ///
    /// The guard was protecting against `setWaterOverride` reading a stale
    /// `waterMl` and replacing the day with 250 ml. `addWater` stopped calling
    /// that in `0a12e99`: `addWaterGlass` appends its own ledger row and
    /// re-reads the SUM inside its own transaction, so there is no stale read
    /// left to protect, and it mints the day's row itself
    /// (`patchDailyLog` → `existingDailyLog`, the same minting HealthKit uses).
    /// The comment outlived the call it was about.
    private func add() {
        model.addWater()
        glasses += 1
    }

    private var figures: String { model.waterFigures }

    private var spoken: String {
        guard let ml = model.waterMl else {
            return model.isAwaitingHealthWater ? "waiting for Apple Health" : "nothing logged"
        }
        guard let goal = model.waterGoalMl else { return "\(NutritionFormat.litres(ml)) litres, no goal" }
        return "\(NutritionFormat.litres(ml)) of \(NutritionFormat.litres(goal)) litres"
    }
}

// MARK: - Context

/// What is shaping the day, in one 32 pt row.
///
/// This is what the "Context" card became. The card was 200 pt tall to hold a
/// menu, a toggle and a paragraph explaining both; the chips state the same
/// facts in the space of a line and open the sheet that changes them. A
/// paragraph nobody re-reads after the first week is not documentation, it is
/// furniture.
private struct ContextChips: View {
    let model: NutritionModel
    let onEdit: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: OnyxSpace.s) {
                NutritionChip(model.leverLabel, icon: "dial.medium", style: .plain)
                Button(action: onEdit) {
                    NutritionChip(model.dayShapeLabel, icon: "target", style: model.hasOverride ? .accent : .plain)
                }
                .buttonStyle(.plain)
                if let reason = model.exceptionReason {
                    Button(action: onEdit) {
                        NutritionChip(reason, icon: "calendar.badge.exclamationmark", style: .accent)
                    }
                    .buttonStyle(.plain)
                }
                if model.isEstimated {
                    Button(action: onEdit) {
                        NutritionChip("Estimated", icon: "questionmark.circle", style: .accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(minHeight: 32)
    }
}

/// A small labelled state. `plain` states a fact; `accent` states one the user
/// declared, which is the only kind worth colouring.
struct NutritionChip: View {
    enum Style { case plain, accent }

    let text: String
    let icon: String
    var style: Style = .plain

    init(_ text: String, icon: String, style: Style = .plain) {
        self.text = text
        self.icon = icon
        self.style = style
    }

    var body: some View {
        Label(text, systemImage: icon)
            .onyxType(.caption)
            .lineLimit(1)
            .foregroundStyle(style == .accent ? Color.onyx.accent(.fuel) : Color.onyx.textSecondary)
            .padding(.horizontal, OnyxSpace.s)
            .frame(minHeight: 28)
            .background(Capsule().fill(Color.onyx.hairline))
            // The capsule stays 28 pt because §5.6 asks for a 32 pt row; the
            // TARGET is 44, which is not the same measurement and is the one
            // the HIG is about. The extra 8 pt above and below is transparent.
            .padding(.vertical, OnyxSpace.s)
            .contentShape(.rect)
    }
}

// MARK: - The week

/// Seven days, four bars each, every bar as a share of what that day asked for.
///
/// ── WHY EVERY BAR IS NORMALISED ─────────────────────────────────────────────
/// Grams and kilocalories share no axis: 1,955 kcal beside 170 g of protein
/// makes the protein invisible. Dividing each figure by its own goal puts all
/// four on one scale where 1.0 means "did what the day asked", which is the only
/// comparison worth making across a week — and the dashed line at 1.0 is the
/// whole reading.
private struct WeekStrip: View {
    let model: NutritionModel

    @ScaledMetric(relativeTo: .body) private var plot: CGFloat = 72

    private struct Bar: Identifiable {
        let id: String
        let date: String
        let macro: String
        let ratio: Double
        let colour: Color
    }

    /// The goals are the SELECTED day's, not each day's own.
    ///
    /// A per-day resolution would need seven passes of `Levers.goalsForDate` and
    /// seven `daily_targets` rows, and it would make the dashed line mean a
    /// different number in each column — which is exactly what a comparison
    /// across a week must not do. One denominator, stated in the caption.
    private var bars: [Bar] {
        let goals: [(String, Double?, (NutritionDay) -> Double?, Color)] = [
            ("Kcal", model.targetKcal, { $0.kcal }, Color.onyx.calories),
            ("P", model.target.protein, { $0.proteinG }, Color.onyx.protein),
            ("C", model.tracksCarbs ? model.target.carbs : nil, { $0.carbsG }, Color.onyx.carbs),
            ("F", model.tracksFat ? model.target.fat : nil, { $0.fatG }, Color.onyx.fat),
        ]
        return model.week.flatMap { day in
            goals.compactMap { name, goal, read, colour in
                guard let goal, goal > 0, let value = read(day) else { return nil }
                return Bar(id: "\(day.date)-\(name)", date: day.date, macro: name,
                           ratio: min(value / goal, 1.6), colour: colour)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            Text("Last seven days")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
            if model.week.isEmpty {
                // `week` is emptied on every day change, so an empty ARRAY is
                // the loading state; the real empty week is seven untracked
                // days and draws the axis with no bars.
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else if bars.isEmpty {
                Text("Nothing logged this week.")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                chart
            }
        }
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last seven days against the day's goals")
        .accessibilityValue(spoken)
    }

    private var chart: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Day", bar.date),
                    y: .value("Of goal", bar.ratio),
                    width: .fixed(4)
                )
                .position(by: .value("Macro", bar.macro))
                .foregroundStyle(bar.colour)
                .cornerRadius(2)
            }
            RuleMark(y: .value("Goal", 1))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.onyx.textTertiary)
        }
        // The axis is the SEVEN DAYS, not the days that happen to have bars. A
        // categorical scale inferred from the marks drops an untracked day
        // silently, and the strip then reads as six days with the gap closed up.
        .chartXScale(domain: model.week.map(\.date))
        .chartYScale(domain: 0...1.6)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(preset: .aligned) { value in
                AxisValueLabel {
                    if let date = value.as(String.self) {
                        Text(NutritionFormat.weekdayNarrow(date))
                    }
                }
                .font(OnyxChart.axisFont)
                .foregroundStyle(Color.onyx.textTertiary)
            }
        }
        .chartLegend(.hidden)
        .onyxChart(.fuel)
        .frame(height: plot)
    }

    /// What the picture says, not a different statistic about the same days.
    /// Each bar is a share of its goal, so the reading is how many of the
    /// twenty-eight came in at or under the dashed line.
    private var spoken: String {
        guard !model.week.isEmpty else { return "loading" }
        let all = bars
        guard !all.isEmpty else { return "nothing logged this week" }
        let met = all.filter { $0.ratio >= 1 }.count
        return "\(met) of \(all.count) figures at or over their goal across seven days"
    }
}

// MARK: - Nutrients

private struct NutrientsRow: View {
    let model: NutritionModel

    var body: some View {
        NavigationLink {
            NutrientsView(model: model)
        } label: {
            HStack(spacing: OnyxSpace.s) {
                Text("Nutrients")
                    .onyxType(.body)
                    .foregroundStyle(Color.onyx.textPrimary)
                Spacer(minLength: OnyxSpace.s)
                Text("Electrolytes, vitamins, stack")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OnyxSpace.m)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onyxGlass(.tile)
    }
}

// MARK: - Shared furniture

/// `Manual` / `Override` — a state, not a control.
struct NutritionBadge: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .onyxType(.micro)
            .foregroundStyle(Color.onyx.accent(.fuel))
            .padding(.horizontal, OnyxSpace.xs)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.onyx.accent(.fuel).opacity(0.16)))
    }
}
