import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// THE WEEK, AS A PAGE (W8)
//
// ── WHY IT LEFT `Features/Workout/` ──────────────────────────────────────────
// The report is not a Train-tab screen. Four doors open it — the Dashboard's
// Week Rings tile, History's week chip, the Past Weeks shelf and the Train tab
// — and while it lived under `Features/Workout/` three of those four were
// importing a Workout feature file to draw a page about sleep, food and body
// composition. `Features/Week/` is the neutral module the founder asked for
// (decision D8): the week is a place, and the tab you arrived from is not part
// of what it is.
//
// ── WHY THE SHEET HAD TO GO (W4, kept) ───────────────────────────────────────
// `WeeklyWrapView` opened at a 560 pt detent with `.large` behind a drag, and
// the argument for it — "a wrap-up is a thing you glance at and put down" — was
// true of the REEL and false of everything the founder then asked the week to
// answer. A week that reports its macros, its micronutrients, its muscle
// coverage, its sleep, its battery, its records and its weight is a document,
// and a document behind a drag indicator is a document most readers never see
// the second half of. So it is a place you go, with a back button, a title, and
// no fold.
//
// ── ONE CHART A SECTION ──────────────────────────────────────────────────────
// Every section answers one question and draws at most one plot to answer it.
// The rule is what keeps a nine-section page readable: a reader scrolling for
// "how did I sleep" passes one bar chart per heading rather than a wall of
// instruments, and a section with nothing to show draws nothing at all.
// ─────────────────────────────────────────────────────────────────────────────

struct WeekReportView: View {
    let summary: WeeklyWrap.Summary
    /// The programme as it stood in the week being read — for the reel's day
    /// labels, and nothing else.
    let program: Program
    /// The harness's. A shot cannot wait for a detached read and a preview
    /// store has no export to build; see `PreviewHarness`.
    var seeded: WeekReport?

    @Environment(AppEnvironment.self) private var environment
    @State private var report: WeekReport?

    var body: some View {
        ScrollView {
            // `VStack(spacing: 0)` and not the padded stack below it: the band
            // is FULL-BLEED and a side gutter applied to it would draw a
            // gradient with two black margins, which is a card, not a band.
            VStack(alignment: .leading, spacing: 0) {
                PhaseBand(summary: summary, report: report)
                LazyVStack(alignment: .leading, spacing: OnyxSpace.l) {
                    if let report {
                        WeekVerdictRow(report: report)
                        WeekFiguresRow(report: report)
                        WeekBodySection(report: report)
                        WeekTrainingSection(report: report, summary: summary, program: program)
                        WeekNutritionSection(report: report)
                        WeekRecoverySection(report: report)
                        WeekCardioSection(report: report)
                        WeekRecordsSection(report: report)
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
/// The numeral is the page's ONE hero (the cross-wave rule). Nothing else on
/// this screen is set at `.clock`, which is what makes that rule checkable
/// rather than a sentiment.
struct PhaseBand: View {
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
