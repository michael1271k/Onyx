import SwiftUI
import Charts
import OnyxUI
import OnyxCore
import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// THE WEEK'S SECTIONS (W8)
//
// Eight blocks, in the order a week is read: how it went, what was done, what
// the body did with it, then the four domains, then the records. Every one of
// them is a fold over `WeekReport` and holds no state and no store — the page
// reads once (`WeekReportView.task`) and these draw what came back.
//
// ── THE TWO RULES THEY ALL KEEP ──────────────────────────────────────────────
// · ONE CHART A SECTION, through `onyxChart(_:)`. A section with two plots is
//   two sections that have not been split yet.
// · A SECTION WITH NOTHING TO SAY DRAWS NOTHING. Not a heading over an empty
//   card — a heading is a promise that there is something under it, and a week
//   with no cardio in it should cost the reader no scroll at all.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - The verdict capsules

/// Sleep · Battery · Adherence, as three readings in the colour of their own
/// verdict.
///
/// ── WHY CAPSULES AND NOT THE THREE RAILS ────────────────────────────────────
/// W4 drew Training, Nutrition and Recovery as three progress bars on a common
/// baseline, and the argument for bars — magnitudes compared on one scale — was
/// right about the encoding and wrong about the quantities. A session count
/// against a plan, a share of graded days and a mean battery are three
/// percentages of three different things, and putting them on one baseline
/// invited exactly the comparison that is meaningless ("recovery beat
/// nutrition").
///
/// A capsule makes no cross-claim. It states one reading and colours it by
/// whether that reading is good, and the three sit in a row because they are
/// the three questions a week is opened for — not because they are comparable.
/// The session count moved down to the figures, where it is a count and not a
/// percentage.
struct WeekVerdictRow: View {
    let report: WeekReport

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            // `FlowRow` and not an `HStack`: three capsules with a word and a
            // figure in each is wider than a 375 pt card at AX3 and wrap there.
            //
            // At an ACCESSIBILITY size it is a `VStack` instead, and the reason
            // is that `FlowRow` proposes each child its own ideal width — so a
            // `frame(maxWidth: .infinity)` inside one does nothing and the
            // three blocks came out ragged, each as wide as its own longest
            // word. A stack proposes the full width, which is what makes them
            // read as three rows of one card.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OnyxSpace.s) { capsules }
            } else {
                FlowRow(spacing: OnyxSpace.s) { capsules }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OnyxSpace.l)
        .onyxGlass(.tile)
    }

    @ViewBuilder
    private var capsules: some View {
        capsule("Sleep", report.sleepScoreAvg, unit: "", verdict: Self.band(report.sleepScoreAvg, good: 80, fair: 60))
        capsule("Battery", report.batteryAvg, unit: "%", verdict: Self.band(report.batteryAvg, good: 70, fair: 50))
        capsule("Adherence", report.nutritionAdherencePct, unit: "%", verdict: Self.band(report.nutritionAdherencePct, good: 80, fair: 50))
    }

    private func capsule(_ label: String, _ value: Double?, unit: String, verdict: Color) -> some View {
        // ── THE WORD SITS OVER THE FIGURE AT AN ACCESSIBILITY SIZE ──────────
        // "ADHERENCE 67%" is wider than a 375 pt card at AX5, and a capsule is
        // a shape with no wrapping opinion — so the word broke as "ADHER-" /
        // "ENCE" with the figure floating beside the pair. Stacked, the label
        // gets the whole width it needs and the figure keeps its own line.
        // A branch and not `ViewThatFits`: both candidates end in flexible
        // frames, so the container reports that the row fits at every size and
        // the stacked branch would be dead code (the W1b trap).
        //
        // The SHAPE goes with the layout. A capsule's radius is half its
        // height, so a two-line stack inside one is a lozenge the width of its
        // own text — the Sleep capsule came out as a circle with the word
        // hanging over both ends of it. Stacked, it wears the row corner and
        // takes the card's whole width, like every other AX5 fallback here.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: OnyxSpace.xs))
        return layout {
            Text(label.uppercased())
                .onyxType(.micro)
                .foregroundStyle(Color.onyx.textSecondary)
            // Em dash and not "0": a week with no reading and a week that
            // scored zero are different weeks, and a 0 says the second about
            // both.
            Text(value.map { "\(jsIntegerString(jsRound($0)))\(unit)" } ?? "—")
                .onyxType(.body).onyxNumeral()
                .foregroundStyle(verdict)
        }
        .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
        .padding(.horizontal, OnyxSpace.s)
        .padding(.vertical, stacked ? OnyxSpace.s : 5)
        .background(
            verdict.opacity(0.14),
            in: stacked
                ? AnyShape(RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous))
                : AnyShape(Capsule())
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.map { "\(jsIntegerString(jsRound($0)))\(unit.isEmpty ? "" : " percent")" } ?? "no reading")
    }

    /// Three bands and one absence. The thresholds are the app's own: the
    /// Battery tile is amber under 70 and the coach speaks under 50; a sleep
    /// score of 80 is the night v2 calls good; adherence is graded days, where
    /// four of five is the week working.
    static func band(_ value: Double?, good: Double, fair: Double) -> Color {
        guard let value else { return Color.onyx.textTertiary }
        if value >= good { return Color.onyx.good }
        if value >= fair { return OnyxDomain.fuel.accent }
        return Color.onyx.danger
    }
}

// MARK: - The three figures

/// Sessions · Tonnage · PRs — what the week DID, as three cells with the
/// week's trail behind the one figure that has a history.
///
/// ── WHY ONLY TONNAGE CARRIES A SPARK ────────────────────────────────────────
/// `WeeklyExportInput.ledger` is a per-week series running from the plan's
/// Week 0, and tonnage is the one quantity on it. Sessions and PRs have no such
/// series anywhere in the payload, and inventing one — seven 0/1 days behind a
/// session count — would be a trail that says nothing while looking exactly
/// like the one beside it that does. `Sparkline` declines to draw under two
/// points, so an empty `spark:` is the honest picture and costs no layout.
struct WeekFiguresRow: View {
    let report: WeekReport

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // ── A GRID AND NOT AN `HStack` (W8) ─────────────────────────────────
        // Three flexible cells in an `HStack` are sized from their IDEAL widths
        // first, so "42,180" took twice the room of "5" and the tonnage's trail
        // — which is drawn across its own cell — stretched into the space
        // beside the PR count and read as a stray rule. `GridItem(.flexible())`
        // is the three-up layout `SessionDetailView` already uses, equal
        // columns by construction, and it is what makes the trail end where the
        // figure it belongs to does.
        //
        // One column at an accessibility size, for the reason that grid states:
        // 117 pt a cell at AX5 broke "SESSIONS" into SES / SIO / NS.
        LazyVGrid(columns: columns, spacing: OnyxSpace.grid) { cells }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OnyxSpace.l)
            .onyxGlass(.tile)
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: OnyxSpace.grid),
            count: typeSize.isAccessibilitySize ? 1 : 3
        )
    }

    @ViewBuilder
    private var cells: some View {
        OnyxStatCell(
            "SESSIONS", "\(report.sessions)",
            sub: report.plannedSessions > 0
                ? .init("of \(report.plannedSessions) planned", Color.onyx.textSecondary)
                : nil,
            glass: false
        )
        // "TONNAGE KG" and not a bare "TONNAGE": the delta beneath it carries
        // its unit, and a figure whose unit is stated one line down but not on
        // itself reads as two different quantities.
        OnyxStatCell(
            "TONNAGE KG", OnyxFormat.volume(report.tonnageKg),
            // Signed, always: "+1,240 kg" and "1,240 kg" are different claims
            // and only one of them is a comparison.
            sub: (report.tonnageDeltaKg.map { $0 == 0 ? nil : $0 } ?? nil).map {
                .init("\($0 > 0 ? "+" : "−")\(OnyxFormat.volume(abs($0))) kg",
                      $0 > 0 ? Color.onyx.good : Color.onyx.textSecondary)
            },
            spark: report.tonnageSpark, glass: false
        )
        OnyxStatCell(
            "PRs", "\(report.prCount)",
            tint: report.prCount > 0 ? Color.onyx.record : nil, glass: false
        )
    }
}

// MARK: - Body

/// The weigh-in and the week's last believed scan.
struct WeekBodySection: View {
    let report: WeekReport

    var body: some View {
        if report.bodyweightKg != nil || report.bodyFatPct != nil || report.muscleMassKg != nil {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Text("BODY").onyxMicro()
                Shoulders(.firstTextBaseline) {
                    Text(report.bodyweightKg.map { "\(OnyxFormat.kg($0)) kg" } ?? "—")
                        .onyxType(.display).onyxNumeral()
                        .foregroundStyle(Color.onyx.textPrimary)
                } trailing: {
                    // Signed, always — the same rule the tonnage delta states.
                    if let delta = report.bodyweightDeltaKg, delta != 0 {
                        Text("\(delta > 0 ? "+" : "−")\(OnyxFormat.kg(abs(delta))) kg across the week")
                            .onyxType(.caption).onyxNumeral()
                            .foregroundStyle(Color.onyx.textSecondary)
                            .lineLimit(2).minimumScaleFactor(0.8)
                    }
                }
                if report.bodyFatPct != nil || report.muscleMassKg != nil {
                    FlowRow(spacing: OnyxSpace.m) {
                        if let fat = report.bodyFatPct {
                            figure("BODY FAT", "\(OnyxFormat.kg(jsRound1(fat)))%")
                        }
                        if let muscle = report.muscleMassKg {
                            figure("MUSCLE", "\(OnyxFormat.kg(jsRound1(muscle))) kg")
                        }
                    }
                    if let date = report.scanDate {
                        // The scan is DATED, because a composition reading is a
                        // moment and not a week — and the moment may be the
                        // Monday of a week the reader is looking at on Sunday.
                        Text("Scanned \(Swap.shortDayLabel(date))")
                            .onyxType(.micro)
                            .foregroundStyle(Color.onyx.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OnyxSpace.l)
            .onyxGlass(.tile)
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).onyxType(.micro).foregroundStyle(Color.onyx.textTertiary)
            Text(value)
                .onyxType(.body).onyxNumeral()
                .foregroundStyle(Color.onyx.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Training

/// Where the week's work landed, then what moved.
///
/// The muscle capsules and the heat strip are the section's one picture: the
/// capsules name the four muscles the week went into and the strip is all
/// sixteen against their `plan_phase_volume` targets. `MuscleTagRow` is the
/// session masthead's own row (`SessionHeaderCard`) — a muscle keeps one colour
/// across the app, and a second drawing of a muscle capsule is how a hue comes
/// to differ between two screens.
struct WeekTrainingSection: View {
    let report: WeekReport
    let summary: WeeklyWrap.Summary
    let program: Program

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.l) {
            if !report.topMuscles.isEmpty || !report.volumeByMuscle.isEmpty {
                VStack(alignment: .leading, spacing: OnyxSpace.m) {
                    Text("TRAINING").onyxMicro()
                    if !report.topMuscles.isEmpty {
                        MuscleTagRow(muscles: report.topMuscles)
                    }
                    if !report.volumeByMuscle.isEmpty {
                        HeatStrip(muscles: report.volumeByMuscle)
                        Text("Weekly sets against the plan's target, sixteen muscles. A pip marks one past its target.")
                            .onyxType(.micro)
                            .foregroundStyle(Color.onyx.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OnyxSpace.l)
                .onyxGlass(.tile)
            }
            // The reel, minus the headline the figures row above now carries:
            // the week's two best lifts, what progressed, and every movement
            // behind a disclosure.
            WeeklyWrapContent(summary: summary, program: program)
            strongest
        }
    }

    /// Hardest, Heaviest and best estimated 1RM of the whole week — the three
    /// roles `TopLifts` already resolves for a single session, over seven days.
    @ViewBuilder
    private var strongest: some View {
        if !report.strongest.isEmpty {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Text("STRONGEST").onyxMicro()
                ForEach(Array(report.strongest.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.exercise)
                            .onyxType(.secondary).fontWeight(.semibold)
                            .foregroundStyle(Color.onyx.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        ForEach(group.lifts, id: \.role) { lift in
                            Shoulders(.firstTextBaseline) {
                                Text(Self.roleName(lift.role))
                                    .onyxType(.micro)
                                    .foregroundStyle(Color.onyx.textTertiary)
                            } trailing: {
                                Text(Self.liftFigure(lift))
                                    .onyxType(.caption).onyxNumeral()
                                    .foregroundStyle(Color.onyx.textSecondary)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }
                    }
                    .padding(OnyxSpace.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onyxGlass(.row)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private static func roleName(_ role: TopLifts.Role) -> String {
        switch role {
        case .hardest: "HARDEST"
        case .heaviest: "HEAVIEST"
        case .oneRM: "BEST e1RM"
        }
    }

    private static func liftFigure(_ lift: TopLifts.Lift) -> String {
        switch lift.role {
        case .oneRM: "\(OnyxFormat.kg(jsRound1(lift.figure))) kg est."
        default: "\(OnyxFormat.kg(lift.set.kg)) kg × \(jsIntegerString(Double(lift.set.reps)))"
        }
    }
}

// MARK: - Nutrition

/// Calories against the rung the week was on, the four macros as a table, and
/// only the micronutrients that need acting on.
struct WeekNutritionSection: View {
    let report: WeekReport

    /// Nothing was logged at all — no calories, no macros, no water, and not
    /// one graded day.
    private var isEmpty: Bool {
        report.kcalByDay.isEmpty
            && report.waterMlPerDay == nil
            && report.macroTable.allSatisfy { $0.mean == nil }
            && report.adherence.allSatisfy { $0.verdict == .untracked }
    }

    var body: some View {
        // ── AN EMPTY WEEK IS A SENTENCE, NOT A 400 pt CARD ──────────────────
        // `OnyxChartEmpty` reserves `plotHeight` for the plot it is standing in
        // for, which is right inside a card that has other readings and wrong
        // as a whole section: an untracked week drew a full chart card headed
        // "Nutrition" with a glyph in the middle of it, then the same again for
        // Recovery, and the reader scrolled two screens to learn nothing twice.
        if isEmpty {
            WeekEmptyNote(title: "NUTRITION", message: "No day of this week was tracked.")
        } else {
            tracked
        }
    }

    private var tracked: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.m) {
            if !report.kcalByDay.isEmpty {
                OnyxChartCard(
                    "Nutrition", domain: .fuel,
                    headline: mean.map { "\(OnyxFormat.volume($0)) kcal" },
                    caption: report.kcalTarget.map {
                        "Daily mean against a \(OnyxFormat.volume($0)) kcal target."
                    }
                ) {
                    Chart {
                        ForEach(report.kcalByDay) { point in
                            BarMark(
                                x: .value("Day", OnyxChart.date(point.d) ?? .now, unit: .day),
                                y: .value("kcal", point.v)
                            )
                            .foregroundStyle(OnyxDomain.fuel.accent)
                            .cornerRadius(3)
                        }
                        if let target = report.kcalTarget, target > 0 {
                            RuleMark(y: .value("Target", target))
                                .foregroundStyle(Color.onyx.textSecondary.opacity(0.8))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartXAxis { Self.weekdayAxis }
                    .onyxChart(.fuel)
                }
            }
            verdictStrip
            macroTable
            micros
            water
        }
    }

    private var mean: Double? {
        guard !report.kcalByDay.isEmpty else { return nil }
        return jsRound(report.kcalByDay.map(\.v).reduce(0, +) / Double(report.kcalByDay.count))
    }

    /// The seven verdicts, as dots.
    ///
    /// A week nobody logged draws seven grey dots over seven weekday initials —
    /// a picture of a broken card rather than of an untracked week. One or the
    /// other, never both; the chart above has already said "no day was
    /// tracked".
    @ViewBuilder
    private var verdictStrip: some View {
        if !report.adherence.allSatisfy({ $0.verdict == .untracked }) {
            // `FlowRow` rather than an `HStack`: seven dots with a weekday under
            // each is 40 pt a cell at AX5, wider than the card.
            FlowRow(spacing: OnyxSpace.xs) {
                ForEach(report.adherence, id: \.date) { day in
                    VStack(spacing: 2) {
                        Circle()
                            .fill(Self.verdictTint(day.verdict))
                            .frame(width: 10, height: 10)
                        Text(WeekWindow.initial(day.date))
                            .onyxType(.micro)
                            .foregroundStyle(Color.onyx.textTertiary)
                    }
                    .frame(minWidth: 28)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.date), \(day.verdict.rawValue)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OnyxSpace.l)
            .onyxGlass(.tile)
        }
    }

    @ViewBuilder
    private var macroTable: some View {
        let rows = report.macroTable.filter { $0.mean != nil }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Text("MACROS, DAILY MEAN").onyxMicro()
                ForEach(rows) { row in
                    Shoulders(.firstTextBaseline) {
                        Text(row.label)
                            .onyxType(.secondary)
                            .foregroundStyle(Color.onyx.textPrimary)
                    } trailing: {
                        Text(Self.macroFigure(row))
                            .onyxType(.caption).onyxNumeral()
                            // Only the row that is OFF is coloured. Tinting the
                            // ones on target put three greens above one grey
                            // and sent the eye to the three macros that needed
                            // nothing — the same rule the micronutrient list
                            // below keeps, where a row exists only because it
                            // breached.
                            .foregroundStyle(Self.macroTint(row.pct))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, OnyxSpace.m)
                    .frame(minHeight: 36)
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OnyxSpace.l)
            .onyxGlass(.tile)
        }
    }

    @ViewBuilder
    private var micros: some View {
        if !report.flaggedMicros.isEmpty {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Label("MICRONUTRIENTS TO WATCH", systemImage: "exclamationmark.triangle")
                    .onyxMicro(OnyxDomain.fuel.accent)
                ForEach(report.flaggedMicros) { row in
                    Shoulders(.firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label)
                                .onyxType(.secondary)
                                .foregroundStyle(Color.onyx.textPrimary)
                            Text(row.doubted
                                 ? "\(row.kind == .floor ? "floor" : "ceiling") · some days not believed"
                                 : (row.kind == .floor ? "floor" : "ceiling"))
                                .onyxType(.micro)
                                .foregroundStyle(Color.onyx.textTertiary)
                        }
                    } trailing: {
                        Text("\(OnyxFormat.kg(row.value))/\(OnyxFormat.kg(row.target)) \(row.unit)")
                            .onyxType(.caption).onyxNumeral()
                            .foregroundStyle(row.isBreach ? Color.onyx.danger : Color.onyx.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, OnyxSpace.m)
                    .frame(minHeight: 44)
                    .onyxGlass(.row)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var water: some View {
        if let ml = report.waterMlPerDay {
            Shoulders(.firstTextBaseline) {
                Text("Water, daily mean")
                    .onyxType(.secondary)
                    .foregroundStyle(Color.onyx.textSecondary)
            } trailing: {
                Text(Self.litres(ml, goal: report.waterGoalMl))
                    .onyxType(.body).onyxNumeral()
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(OnyxSpace.l)
            .onyxGlass(.tile)
            .accessibilityElement(children: .combine)
        }
    }

    /// Weekday initials under seven daily bars — the label a seven-point dated
    /// axis wants, and the one `WeekWindow.initial` already draws in History.
    static var weekdayAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day)) { _ in
            AxisGridLine().foregroundStyle(Color.onyx.hairline)
            AxisValueLabel(format: .dateTime.weekday(.narrow))
                .font(OnyxChart.axisFont)
                .foregroundStyle(Color.onyx.textTertiary)
        }
    }

    static func macroFigure(_ row: WeekReport.MacroRow) -> String {
        let mean = OnyxFormat.volume(row.mean ?? 0)
        guard let target = row.target, target > 0 else { return "\(mean) \(row.unit)" }
        return "\(mean) / \(OnyxFormat.volume(target)) \(row.unit) · \(jsIntegerString(jsRound(row.pct ?? 0)))%"
    }

    /// Within ±10 % is the same tolerance `MacroAdherenceSeries` grades a day
    /// on, and using a second number here would put two definitions of "on
    /// target" on one screen.
    ///
    /// Off target is the FUEL accent and not `danger`: a weekly mean 13 % over
    /// its fat target is a thing to notice, and red is the app's word for a
    /// thing that went wrong.
    static func macroTint(_ pct: Double?) -> Color {
        guard let pct else { return Color.onyx.textSecondary }
        return abs(pct - 100) <= 10 ? Color.onyx.textSecondary : OnyxDomain.fuel.accent
    }

    static func verdictTint(_ verdict: AdherenceVerdict) -> Color {
        switch verdict {
        case .hit: Color.onyx.good
        case .miss: Color.onyx.danger
        case .exception: OnyxDomain.fuel.accent
        case .ungraded, .untracked: Color.onyx.hairline
        }
    }

    static func litres(_ ml: Double, goal: Double?) -> String {
        let litres = "\(OnyxFormat.kg(jsRound(ml / 100) / 10)) L"
        guard let goal, goal > 0 else { return litres }
        return "\(litres) / \(OnyxFormat.kg(jsRound(goal / 100) / 10)) L"
    }
}

// MARK: - Recovery

/// Sleep as seven bars against the goal, the battery as the trail under them,
/// and the two readings that are neither: stress and the week's worst soreness.
struct WeekRecoverySection: View {
    let report: WeekReport

    /// Not a night measured, no battery, no stress reading and no rating.
    private var isEmpty: Bool {
        report.sleepByDay.isEmpty && report.batterySpark.count < 2
            && report.stressMean == nil && report.domsPeak == nil
    }

    var body: some View {
        // The same rule the Nutrition section states: an unmeasured week is a
        // sentence, not a chart card with a glyph where the plot goes.
        if isEmpty {
            WeekEmptyNote(title: "RECOVERY", message: "No night of this week was measured.")
        } else {
            measured
        }
    }

    private var measured: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.m) {
            if !report.sleepByDay.isEmpty {
                OnyxChartCard(
                    "Recovery", domain: .recover,
                    headline: report.sleepScoreAvg.map { "\(jsIntegerString(jsRound($0)))" },
                    caption: "Hours asleep a night. The mean sleep score is the figure."
                ) {
                    Chart {
                        ForEach(report.sleepByDay) { point in
                            BarMark(
                                x: .value("Day", OnyxChart.date(point.d) ?? .now, unit: .day),
                                y: .value("Hours", point.v)
                            )
                            .foregroundStyle(OnyxDomain.recover.accent)
                            .cornerRadius(3)
                        }
                        if let goal = report.sleepGoalHours, goal > 0 {
                            RuleMark(y: .value("Goal", goal))
                                .foregroundStyle(Color.onyx.textSecondary.opacity(0.8))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartXAxis { WeekNutritionSection.weekdayAxis }
                    .onyxChart(.recover)
                }
            }
            battery
            readings
        }
    }

    /// The week's battery as a trail rather than a second plot — the section
    /// already spent its chart on sleep, and a battery is a level that moves
    /// rather than seven buckets.
    @ViewBuilder
    private var battery: some View {
        if report.batterySpark.count >= 2 {
            // ── AN `HStack`, NOT `Shoulders` ────────────────────────────────
            // `Shoulders(.firstTextBaseline)` aligns its two sides on a TEXT
            // baseline, and a sparkline has none — so the trail was pinned to
            // the top of the card while the label it belongs to sat at the
            // bottom, reading as two unrelated things. Centred is the alignment
            // for a label beside a figure that is not text.
            HStack(alignment: .center, spacing: OnyxSpace.m) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("BATTERY").onyxMicro()
                    Text(report.batteryAvg.map { "mean \(jsIntegerString(jsRound($0)))%" } ?? "—")
                        .onyxType(.caption).onyxNumeral()
                        .foregroundStyle(Color.onyx.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Sparkline(
                    points: report.batterySpark, color: OnyxDomain.recover.accent, zeroBased: true
                )
                .frame(width: 88, height: 26)
                .accessibilityHidden(true)
            }
            .padding(OnyxSpace.l)
            .onyxGlass(.tile)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Battery")
            .accessibilityValue(report.batteryAvg.map { "mean \(jsIntegerString(jsRound($0))) percent" } ?? "no reading")
        }
    }

    @ViewBuilder
    private var readings: some View {
        if report.stressMean != nil || report.domsPeak != nil {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                if let stress = report.stressMean {
                    Shoulders(.firstTextBaseline) {
                        Text("Stress, mean of the week's readings")
                            .onyxType(.secondary)
                            .foregroundStyle(Color.onyx.textSecondary)
                    } trailing: {
                        // The mean is rounded to name a rung — `PsychStress`
                        // has five words and no word for 3.4 — and the exact
                        // mean is printed beside it, so the word qualifies the
                        // figure rather than replacing it.
                        Text("\(OnyxFormat.kg(stress))\(PsychStress.level(Int(jsRound(stress))).map { " · \($0.label)" } ?? "")")
                            .onyxType(.caption).onyxNumeral()
                            .foregroundStyle(Color.onyx.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let peak = report.domsPeak {
                    Shoulders(.firstTextBaseline) {
                        Text("Worst soreness")
                            .onyxType(.secondary)
                            .foregroundStyle(Color.onyx.textSecondary)
                    } trailing: {
                        Text("\(peak.muscle) \(OnyxFormat.kg(peak.severity)) · \(Swap.shortDayLabel(peak.date))")
                            .onyxType(.caption).onyxNumeral()
                            .foregroundStyle(Color.onyx.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OnyxSpace.l)
            .onyxGlass(.tile)
        }
    }
}

// MARK: - Cardio

/// The week's bouts as one row. No chart: a week holds two or three bouts of
/// two kinds, and three bars is a picture of nothing.
struct WeekCardioSection: View {
    let report: WeekReport

    var body: some View {
        if let cardio = report.cardio {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Text("CARDIO").onyxMicro()
                Shoulders(.firstTextBaseline) {
                    Text("\(jsIntegerString(cardio.minutes)) min")
                        .onyxType(.display).onyxNumeral()
                        .foregroundStyle(Color.onyx.textPrimary)
                } trailing: {
                    Text("\(cardio.bouts) bout\(cardio.bouts == 1 ? "" : "s") · \(cardio.kinds.joined(separator: " · "))")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
                if cardio.km != nil || cardio.kcal != nil {
                    Text(
                        [
                            cardio.km.map { "\(OnyxFormat.kg($0)) km" },
                            cardio.kcal.map { "\(OnyxFormat.volume($0)) kcal" },
                        ].compactMap { $0 }.joined(separator: " · ")
                    )
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OnyxSpace.l)
            .onyxGlass(.tile)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Records

/// Three records, and the rest behind a disclosure.
///
/// ── WHY IT IS CAPPED ────────────────────────────────────────────────────────
/// `records` is the one uncapped list on this page and a good week sets eleven.
/// Eleven trophy rows push everything under them — the share control, and on a
/// phone the whole Records heading itself — below a second fold. Three is the
/// `topThree` precedent one card up: enough to answer "what moved", with the
/// full list one tap away for the reader who wants all of them.
struct WeekRecordsSection: View {
    let report: WeekReport

    @State private var expanded = false

    var body: some View {
        if !report.records.isEmpty {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Label("NEW RECORDS", systemImage: "trophy.fill")
                    .onyxMicro(Color.onyx.record)
                ForEach(Array(report.topRecords.enumerated()), id: \.offset) { _, pr in
                    row(pr)
                }
                if report.hasMoreRecords {
                    DisclosureGroup(isExpanded: $expanded) {
                        VStack(alignment: .leading, spacing: OnyxSpace.s) {
                            ForEach(
                                Array(report.records.dropFirst(WeekReport.recordCap).enumerated()),
                                id: \.offset
                            ) { _, pr in
                                row(pr)
                            }
                        }
                        .padding(.top, OnyxSpace.s)
                    } label: {
                        Label(label, systemImage: "list.bullet")
                            .onyxType(.caption).fontWeight(.semibold)
                            .foregroundStyle(Color.onyx.record)
                            .frame(minHeight: 44)
                    }
                    .tint(Color.onyx.record)
                    .accessibilityHint("Shows every record the week set")
                }
            }
        }
    }

    private var label: String {
        if expanded { return "Hide the rest" }
        let hidden = report.records.count - WeekReport.recordCap
        return "+\(hidden) more record\(hidden == 1 ? "" : "s")"
    }

    private func row(_ pr: ExportPr) -> some View {
        HStack(spacing: OnyxSpace.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(pr.name)
                    .onyxType(.secondary)
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(pr.axes.map(\.rawValue).joined(separator: " · "))
                    .onyxType(.micro)
                    .foregroundStyle(Color.onyx.record)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(OnyxFormat.kg(pr.weightKg)) kg × \(jsIntegerString(pr.reps))")
                .onyxType(.caption).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
        }
        .padding(.horizontal, OnyxSpace.m)
        .frame(minHeight: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.row)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The empty note

/// One line where a whole section has nothing in it.
///
/// Titled, because the alternative — drawing nothing at all — makes an
/// untracked week and a missing section look the same, and only one of those is
/// something the reader can act on.
struct WeekEmptyNote: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            Text(title).onyxMicro()
            Text(message)
                .onyxType(.secondary)
                .foregroundStyle(Color.onyx.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OnyxSpace.l)
        .onyxGlass(.tile)
        .accessibilityElement(children: .combine)
    }
}
