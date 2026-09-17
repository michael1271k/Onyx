import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// THE WEEK, AS A PAGE (W4)
//
// ── WHY THE SHEET HAD TO GO ──────────────────────────────────────────────────
// `WeeklyWrapView` opened at a 560 pt detent with `.large` behind a drag, and
// the argument for it — "a wrap-up is a thing you glance at and put down" — was
// true of the REEL and false of everything the founder then asked the week to
// answer. A week that reports its macros, its water, its records, its strongest
// lifts and its weight is a document, and a document behind a drag indicator is
// a document most readers never see the second half of. Three of the four doors
// into it were already in a `NavigationStack`; the fourth is too. So it is a
// place you go, with a back button, a title, and no fold.
//
// Nothing was re-queried to build it. `WeeklyWrap.Summary` is what the four
// doors already carry and `WeeklyExportBuilder.input(weekStart:today:)` is the
// ONE call behind the rest — the same payload the weekly export renders, which
// is the only reader in this app that has ever had the whole week in one value.
// ─────────────────────────────────────────────────────────────────────────────

struct WeeklyReportView: View {
    let summary: WeeklyWrap.Summary
    /// The programme as it stood in the week being read — for the reel's day
    /// labels, and nothing else.
    let program: Program
    /// The harness's. A shot cannot wait for a detached read and a preview
    /// store has no export to build; see `PreviewHarness`.
    var seeded: WeekReport?

    @Environment(AppEnvironment.self) private var environment
    /// Asked directly rather than inferred from a container (W1b). Two things
    /// below branch on it and both are the same decision: a figure is allowed
    /// to take as many lines as it needs before it is allowed to truncate.
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var report: WeekReport?

    var body: some View {
        ScrollView {
            // `VStack(spacing: 0)` and not the padded stack below it: the band
            // is FULL-BLEED and a side gutter applied to it would draw a
            // gradient with two black margins, which is a card, not a band.
            VStack(alignment: .leading, spacing: 0) {
                PhaseBand(summary: summary, report: report)
                LazyVStack(alignment: .leading, spacing: OnyxSpace.l) {
                    rails
                    // Reused, not rewritten: the reel is the same `LazyVStack`
                    // of headline / bests / progressed / breakdown / share it
                    // has been since W6, minus the ring.
                    WeeklyWrapContent(summary: summary, program: program)
                    if let report {
                        nutrition(report)
                        records(report)
                        strongest(report)
                        weight(report)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OnyxSpace.xl)
                    }
                    // LAST, and it left the reel to get here: a share control
                    // with a week's macros and a weigh-in under it reads as the
                    // end of one screen and the start of another.
                    WeeklyShareSection(summary: summary, program: program)
                }
                .padding(.horizontal, OnyxSpace.l)
                .padding(.top, OnyxSpace.l)
                .padding(.bottom, OnyxSpace.xl)
            }
        }
        .onyxScreen(.train)
        .navigationTitle(WeeklyWrapContent.title(summary))
        .navigationBarTitleDisplayMode(.inline)
        // Without this the inline bar draws its own material band over the mesh
        // the moment content scrolls under it — and this screen opens on a
        // full-bleed gradient, which is exactly what that band would cover.
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            guard report == nil else { return }
            if let seeded { report = seeded; return }
            let database = environment.database
            let userId = environment.userIdString
            let today = environment.today
            let week = summary
            let days = program.days.count
            // Detached, for the reason `WorkoutWeek.library()` is: this is the
            // whole export payload for a week — every set, every log, every
            // scan — and it must not run on the actor drawing the page.
            report = await Task.detached(priority: .userInitiated) {
                WeekReport.build(
                    database: database, userId: userId, summary: week,
                    plannedSessions: days, today: today
                )
            }.value
        }
    }

    // MARK: - The three rails

    /// Training · Nutrition · Recovery, as three fractions on a common
    /// baseline.
    ///
    /// ── WHY RAILS AND NOT A FOURTH SCORE ────────────────────────────────────
    /// The obvious build is one number for the week. It is also the build that
    /// invents an engine: three quantities measured in sessions, in graded days
    /// and in percent of a battery do not average into anything, and the
    /// weighting that made them would be this screen's private opinion about
    /// what a good week is. Three bars answer the same question honestly —
    /// which of the three went well — and each one is a figure some other
    /// surface of this app already prints.
    ///
    /// A donut would not: it is part-to-whole, and these three are not parts of
    /// one whole. Bars on a common baseline are the encoding for comparing
    /// magnitudes, which is the one thing a reader does here.
    private var rails: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.m) {
            rail(
                "TRAINING", report?.trainingPct, report?.trainingDetail,
                tint: OnyxDomain.train.accent
            )
            rail(
                "NUTRITION", report?.nutritionPct, report?.nutritionDetail,
                tint: OnyxDomain.fuel.accent
            )
            rail(
                "RECOVERY", report?.recoveryPct, report?.recoveryDetail,
                tint: OnyxDomain.recover.accent
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OnyxSpace.l)
        .onyxGlass(.tile)
    }

    private func rail(_ label: String, _ pct: Double?, _ detail: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            Shoulders(.firstTextBaseline) {
                Text(label).onyxMicro()
            } trailing: {
                // Em dash and not "0%": a week with no graded day and a week
                // that missed every one of them are different weeks, and a bar
                // at zero says the second about both.
                Text(pct.map { "\(jsIntegerString(jsRound($0)))%" } ?? "—")
                    .onyxType(.body).onyxNumeral()
                    .foregroundStyle(pct == nil ? Color.onyx.textTertiary : tint)
            }
            OnyxProgressBar(fraction: (pct ?? 0) / 100, tint: tint)
            if let detail {
                Text(detail)
                    .onyxType(.micro).onyxNumeral()
                    .foregroundStyle(Color.onyx.textTertiary)
                    // Two lines at a readable size and AS MANY AS IT TAKES at
                    // an accessibility one, where `5 of 5 sessions · 42,180 kg
                    // · +1,240 kg vs last week` came out as `… 42,180 kg · …`.
                    // A tonnage with its comparison replaced by an ellipsis is
                    // the one thing this line is for.
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.capitalized)
        .accessibilityValue(
            [pct.map { "\(jsIntegerString(jsRound($0))) percent" } ?? "no reading", detail]
                .compactMap { $0 }.joined(separator: ", ")
        )
    }

    // MARK: - Nutrition

    /// The seven days as the strip already draws them, and the water rule.
    private func nutrition(_ report: WeekReport) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.m) {
            Text("NUTRITION").onyxMicro()
            // A week nobody logged draws seven grey dots over seven weekday
            // initials — a picture of a broken card rather than of an untracked
            // week, and a strip with no colour in it carries no information to
            // pay for the room. One or the other, never both.
            if report.adherence.allSatisfy({ $0.verdict == .untracked }) {
                Text("No day of this week was tracked.")
                    .onyxType(.secondary)
                    .foregroundStyle(Color.onyx.textSecondary)
            } else {
                // `FlowRow` rather than an `HStack`: seven dots with a weekday
                // under each is 40 pt a cell at AX5, wider than the card.
                FlowRow(spacing: OnyxSpace.xs) {
                    ForEach(report.adherence, id: \.date) { day in
                        VStack(spacing: 2) {
                            Circle()
                                .fill(Self.verdictTint(day.verdict))
                                .frame(width: 10, height: 10)
                            Text(Self.weekdayInitial(day.date))
                                .onyxType(.micro)
                                .foregroundStyle(Color.onyx.textTertiary)
                        }
                        .frame(minWidth: 28)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.date), \(day.verdict.rawValue)")
                    }
                }
            }
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OnyxSpace.l)
        .onyxGlass(.tile)
    }

    // MARK: - New records

    /// Every record the week set, BY EXERCISE.
    ///
    /// By exercise and not by date, because a record is a fact about a movement
    /// and the question a reader brings here is "what moved" — a list ordered
    /// by Tuesday answers a question about Tuesday.
    @ViewBuilder
    private func records(_ report: WeekReport) -> some View {
        if !report.records.isEmpty {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Label("NEW RECORDS", systemImage: "trophy.fill")
                    .onyxMicro()
                    .foregroundStyle(Color.onyx.record)
                ForEach(Array(report.records.enumerated()), id: \.offset) { _, pr in
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
        }
    }

    // MARK: - Strongest

    /// Hardest, Heaviest and best estimated 1RM of the whole week — the three
    /// roles `TopLifts` already resolves for a single session, over seven days.
    @ViewBuilder
    private func strongest(_ report: WeekReport) -> some View {
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

    // MARK: - Weight

    @ViewBuilder
    private func weight(_ report: WeekReport) -> some View {
        if summary.bodyweightKg != nil || summary.bodyweightDeltaKg != nil {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Text("WEIGHT").onyxMicro()
                Shoulders(.firstTextBaseline) {
                    Text(summary.bodyweightKg.map { "\(OnyxFormat.kg($0)) kg" } ?? "—")
                        .onyxType(.display).onyxNumeral()
                        .foregroundStyle(Color.onyx.textPrimary)
                } trailing: {
                    // Signed, always — the same rule the reel's tonnage delta
                    // states: "−0.4 kg" and "0.4 kg" are different claims and
                    // only one of them is a comparison.
                    if let delta = summary.bodyweightDeltaKg, delta != 0 {
                        Text("\(delta > 0 ? "+" : "−")\(OnyxFormat.kg(abs(delta))) kg across the week")
                            .onyxType(.caption).onyxNumeral()
                            .foregroundStyle(Color.onyx.textSecondary)
                            .lineLimit(2).minimumScaleFactor(0.8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OnyxSpace.l)
            .onyxGlass(.tile)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Words

    private static func verdictTint(_ verdict: AdherenceVerdict) -> Color {
        switch verdict {
        case .hit: Color.onyx.good
        case .miss: Color.onyx.danger
        case .exception: OnyxDomain.fuel.accent
        case .ungraded, .untracked: Color.onyx.hairline
        }
    }

    /// `S M T W T F S` — the initial, never the name. Seven three-letter
    /// weekday labels under seven 10 pt dots is 30 pt a cell on a 370 pt card.
    private static func weekdayInitial(_ dateISO: String) -> String {
        guard let day = ISODate.weekday(dateISO) else { return "·" }
        return ["S", "M", "T", "W", "T", "F", "S"][day]
    }

    private static func litres(_ ml: Double, goal: Double?) -> String {
        let litres = "\(OnyxFormat.kg(jsRound(ml / 100) / 10)) L"
        guard let goal, goal > 0 else { return litres }
        return "\(litres) / \(OnyxFormat.kg(jsRound(goal / 100) / 10)) L"
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

// MARK: - The band

/// The week's numeral, its block and its dates, over a full-bleed wash in the
/// phase's own hue.
///
/// ── WHY A BAND AND NOT A TILE ───────────────────────────────────────────────
/// Every other card on this page is glass on a mesh, which is what makes them
/// read as things ON a screen. The band is the screen's own head: it runs edge
/// to edge, it carries no material, and it is the one place the phase's colour
/// is stated rather than hinted at. `Color.onyx.phase(_ kind:)` gives cut, bulk,
/// peak and deload four inks, and the same four tint the shelf's banners — so a
/// reader arrives on a page whose colour they have already seen.
///
/// The numeral is the page's ONE hero (W2's rule). Nothing else on the screen
/// is set at `.clock`, which is what makes that rule checkable rather than a
/// sentiment.
private struct PhaseBand: View {
    let summary: WeeklyWrap.Summary
    let report: WeekReport?

    @Environment(\.dynamicTypeSize) private var typeSize

    private var hue: Color {
        report?.phaseKind.map { Color.onyx.phase($0) } ?? OnyxDomain.train.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            Text(kicker).onyxMicro()
            Text(numeral)
                .onyxType(.clock).onyxNumeral()
                .foregroundStyle(hue)
                .lineLimit(1).minimumScaleFactor(0.6)
            // ── A BRANCH, NOT `ViewThatFits` (W1b) ──────────────────────────
            // The capsule and the date range both end in flexible frames, so a
            // `ViewThatFits` is told the row fits every width and takes the
            // first candidate at every size — the stacked branch would be dead
            // code. Ask the type size, which is the actual question.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OnyxSpace.xs) { shoulder }
            } else {
                HStack(spacing: OnyxSpace.s) { shoulder }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OnyxSpace.l)
        .padding(.top, OnyxSpace.s)
        .padding(.bottom, OnyxSpace.l)
        .background(alignment: .top) {
            // 28 %→0 over the band's own height, and NOT clipped to a corner:
            // this one is meant to have square edges, because it has no edges —
            // it is the top of the page.
            LinearGradient(
                colors: [hue.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom
            )
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var shoulder: some View {
        if let tag = report?.eraTag {
            Text(tag)
                .onyxType(.micro)
                .foregroundStyle(hue)
                .padding(.horizontal, OnyxSpace.s)
                .padding(.vertical, 3)
                .background(hue.opacity(0.16), in: .capsule)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        Text(report?.rangeLabel ?? Swap.shortDayLabel(summary.weekStart))
            .onyxType(.caption).onyxNumeral()
            .foregroundStyle(Color.onyx.textSecondary)
            .lineLimit(1).minimumScaleFactor(0.8)
    }

    /// `WEEK` over `7`. The summary's label is the one counter the app numbers
    /// a week with (`Week.label`), and splitting it is how the numeral gets to
    /// be large without the word beside it being large too. A label that is not
    /// `Week n` — a block before the plan's own Week 0 draws its phase name —
    /// is printed whole, at the smaller of the two sizes.
    private var kicker: String {
        label.hasPrefix("Week ") ? "WEEK" : "BLOCK"
    }

    private var numeral: String {
        label.hasPrefix("Week ") ? String(label.dropFirst(5)) : label
    }

    private var label: String { WeeklyWrapContent.title(summary) }
}

// MARK: - The read

/// Everything the report page draws that the summary does not carry.
///
/// ── ONE CALL, NOT SIX ───────────────────────────────────────────────────────
/// Macros, water, records, the week's strongest sets and the phase it fell in
/// are five different tables, and a page that read them itself would be five
/// queries that can disagree with the weekly export about the same week.
/// `WeeklyExportBuilder.input(weekStart:today:)` is the reader that already
/// answers all five — it is what `## NUTRITION` and `## RECORDS` are rendered
/// out of — so this is a FOLD over that payload and not a second reader.
///
/// `Sendable` and built off the actor: see `WeeklyReportView.task`.
struct WeekReport: Sendable, Equatable {
    var phaseKind: PhaseKind?
    var eraTag: String?
    var rangeLabel: String

    /// Sessions logged ÷ sessions the plan schedules, as a percentage. Nil for
    /// a plan with no training days, where the fraction has no denominator.
    var trainingPct: Double?
    var trainingDetail: String
    /// Days graded HIT ÷ days graded at all. Nil for a week where nothing was
    /// tracked — which is not the same week as one where nothing was hit.
    var nutritionPct: Double?
    var nutritionDetail: String
    /// The mean stored `battery_pct` of the days that have one — READINESS_MODEL
    /// §7's own output, not a fourth score.
    var recoveryPct: Double?
    var recoveryDetail: String

    var adherence: [AdherenceDay]
    var waterMlPerDay: Double?
    var waterGoalMl: Double?
    /// Sorted by exercise name.
    var records: [ExportPr]
    var strongest: [TopLifts.Group]
}

extension WeekReport {

    /// The store read. Two calls and both of them already exist: the export
    /// payload, and the schedule context every other week-shaped reader takes.
    nonisolated static func build(
        database: AppDatabase, userId: String, summary: WeeklyWrap.Summary,
        plannedSessions: Int, today: String
    ) -> WeekReport? {
        // ── THE SAME FALLBACK EVERY OTHER READER MAKES ──────────────────────
        // Nothing is signed in inside the shot harness or a preview, so
        // `AppEnvironment.userIdString` is the empty string there — and an
        // export built for "" comes back with seven empty days, which draws a
        // page that says "no day was graded" over a store holding a full week.
        // `localUserId()` is what `WorkoutWeek.library()` and every preview
        // reader already fall back to: the one user the rows belong to.
        let user = userId.isEmpty ? database.localUserId() : userId
        guard let input = try? WeeklyExportBuilder(database: database, userId: user)
            .input(weekStart: summary.weekStart, today: today)
        else { return nil }
        // The phase table, for the band's hue and its era tag. `weekPhase` is
        // how every other surface asks a week what block it is in.
        let phases = (try? database.scheduleContext(userId: user, today: summary.weekStart))?.phases ?? []
        return build(
            input, summary: summary, plannedSessions: plannedSessions,
            phase: Phases.weekPhase(weekStart: summary.weekStart, in: phases)
        )
    }

    /// PURE from here down — no store, no clock, no locale beyond the range
    /// label the payload already carries. Which is what lets the three rails be
    /// asserted against the sources they claim to summarise.
    nonisolated static func build(
        _ input: WeeklyExportInput, summary: WeeklyWrap.Summary,
        plannedSessions: Int, phase: WeekPhase?
    ) -> WeekReport {

        // ── TRAINING ────────────────────────────────────────────────────────
        // Sessions against the plan's own count, which is what
        // `Schedule.sessionTargetIn` answers and what the footer's "3/5"
        // already prints. NOT tonnage: a week's kilograms have no ceiling to be
        // a fraction of, and the delta beside them is the comparison that
        // reads — it is on the reel, one card down.
        let trainingPct = plannedSessions > 0
            ? Double(summary.sessions) / Double(plannedSessions) * 100
            : nil
        var trainingDetail = "\(summary.sessions) of \(plannedSessions) session\(plannedSessions == 1 ? "" : "s") · \(OnyxFormat.volume(summary.tonnageKg)) kg"
        if let delta = summary.tonnageDeltaKg, delta != 0 {
            trainingDetail += " · \(delta > 0 ? "+" : "−")\(OnyxFormat.volume(abs(delta))) kg vs last week"
        }

        // ── NUTRITION ───────────────────────────────────────────────────────
        // `MacroAdherenceSeries.build` and its ±10 % tolerance, graded against
        // the rung that was in force ON EACH DATE — `targetPeriods` — and not
        // against today's. A week spent on Lever 1 that was then read after a
        // step back to Baseline would otherwise be graded against numbers it
        // was never eating to.
        var targets: [String: AdherenceTargets] = [:]
        for period in input.targetPeriods ?? [] {
            for date in period.dates {
                targets[date] = AdherenceTargets(
                    kcal: period.goals.calorie, protein: period.goals.protein,
                    carbs: period.goals.carbs, fat: period.goals.fat
                )
            }
        }
        // The week-level goal is the fallback for a payload with no periods on
        // it — a store whose ladder has never been written.
        if targets.isEmpty, let kcal = input.calorieGoal {
            for day in input.days {
                targets[day.date] = AdherenceTargets(kcal: kcal, protein: input.proteinGoalG)
            }
        }
        let adherence = MacroAdherenceSeries.build(
            input.days.map {
                AdherenceDayIn(
                    date: $0.date, kcal: $0.calories, proteinG: $0.proteinG,
                    carbsG: $0.carbsG, fatG: $0.fatG,
                    exception: $0.nutritionException, estimated: $0.nutritionEstimated
                )
            },
            targets: targets, endingOn: input.weekEnd, limit: 7
        )
        // GRADED days only. An exception day is declared, an untracked day was
        // never logged, and counting either as a miss punishes the athlete for
        // a Saturday they told the app about in advance.
        let graded = adherence.filter { $0.verdict == .hit || $0.verdict == .miss }
        let hits = adherence.filter { $0.verdict == .hit }.count
        let nutritionPct = graded.isEmpty
            ? nil
            : Double(hits) / Double(graded.count) * 100
        var nutritionDetail = graded.isEmpty
            ? "no day was graded"
            : "\(hits) of \(graded.count) graded day\(graded.count == 1 ? "" : "s") on target"
        let exceptions = adherence.filter { $0.verdict == .exception }.count
        if exceptions > 0 {
            nutritionDetail += " · \(exceptions) exception\(exceptions == 1 ? "" : "s")"
        }

        // ── WATER ───────────────────────────────────────────────────────────
        // `WaterTruth` is the one rule, and the payload has already applied the
        // half of it that needs two stores: `ExportDay.waterMl` is the ledger's
        // sum where the ledger has rows and `daily_logs.water_ml` where it does
        // not. What is left is the rule's other half — a stored zero is a day
        // nobody measured, not a day nobody drank on — and passing an empty
        // ledger is how that half is applied without a second copy of it here.
        let water = input.days.compactMap { WaterTruth.ml(log: $0.waterMl, ledger: []) }
        let waterMlPerDay = water.isEmpty ? nil : water.reduce(0, +) / Double(water.count)

        // ── RECOVERY ────────────────────────────────────────────────────────
        // The stored battery, averaged over the nights that have one. Not
        // rebuilt and not re-scored: READINESS_MODEL §7 says `battery_pct` is
        // the output, and a page that recomputed it would be a second formula
        // one refactor away from disagreeing with the tile that shows it daily.
        let battery = input.days.compactMap(\.batteryPct)
        let recoveryPct = battery.isEmpty ? nil : battery.reduce(0, +) / Double(battery.count)
        let recoveryDetail = battery.isEmpty
            ? "no night was scored"
            : "battery, mean of \(battery.count) night\(battery.count == 1 ? "" : "s")"

        // ── RECORDS ─────────────────────────────────────────────────────────
        // Off `ExportSession.prs`, which the builder reconstructs from the
        // `personal_records` rows achieved inside the week. Sorted by EXERCISE,
        // and a movement that set two axes on two days prints twice — the axes
        // differ, so the rows are different facts.
        let records = input.sessions.flatMap(\.prs).sorted {
            ($0.name, $0.weightKg) < ($1.name, $1.weightKg)
        }

        // ── STRONGEST ───────────────────────────────────────────────────────
        // `TopLifts.group` over the WEEK's working sets rather than a session's.
        // Warm-ups and ghosts are excluded here exactly as the engine excludes
        // them from a session: they win no role because they set no bar.
        // `previous: [:]` — the arrow is a SESSION-to-session comparison and
        // there is no "last week's hardest set of the week" to point it at.
        let sets: [TopLifts.Set] = input.sessions.flatMap { session in
            session.exercises.flatMap { exercise in
                exercise.sets
                    .filter { $0.warmup != true && $0.ghost != true }
                    .map {
                        TopLifts.Set(
                            exercise: exercise.name, kg: $0.weightKg,
                            reps: Int($0.reps), rpe: $0.rpe
                        )
                    }
            }
        }

        return WeekReport(
            phaseKind: phase?.kind,
            eraTag: phase?.eraTag,
            rangeLabel: WeekWindow(
                containing: input.weekStart,
                startDay: ISODate.weekday(input.weekStart) ?? 0,
                today: input.weekEnd
            ).rangeLabel,
            trainingPct: trainingPct,
            trainingDetail: trainingDetail,
            nutritionPct: nutritionPct,
            nutritionDetail: nutritionDetail,
            recoveryPct: recoveryPct,
            recoveryDetail: recoveryDetail,
            adherence: adherence,
            waterMlPerDay: waterMlPerDay,
            waterGoalMl: input.waterGoalMl,
            records: records,
            strongest: TopLifts.group(sets, previous: [:])
        )
    }
}
