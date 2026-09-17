import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// Every week the plan has closed, as a shelf of banners.
///
/// ── WHY IT LEFT THE TAB (§W1 C) ─────────────────────────────────────────────
/// Past Weeks was the last section of the Train tab: a caption, then up to
/// eight collapsed rows, each expanding IN PLACE into the whole wrap-up — the
/// reel, the ring and the movement breakdown. Three things were wrong with that
/// and only the third is a layout complaint.
///
///  1. It cost the tab a week-query and a `historySets` read per session inside
///     eight weeks on EVERY refresh, to fill a list at the bottom of a page
///     nobody scrolls to unless they came for it.
///  2. Eight was the cap that cost bought, so the record ENDED at eight weeks —
///     a block that ran longer simply was not browsable.
///  3. Expanding a row in place put most of a metre of content under the plan
///     you were standing in front of, which is why only one could be open.
///
/// Behind a button, the walk runs when it is asked for, the cap is gone
/// (`WorkoutWeek.pastWeekCeiling`), and a week opens into the wrap-up sheet the
/// rest of the app already opens it into — from History, from the This-week
/// tile, and now from here. This screen adds no summary of its own.
///
/// ── AND WHY IT IS A SHEET AND NOT A PUSHED SCREEN ───────────────────────────
/// `WeeklyWrapView`'s own header makes the argument and it holds one level up:
/// this is a thing you open, glance through and put down, and the Train tab is
/// the screen you came to use. A push would cost a back tap to leave and bury
/// the tab; a `.large` sheet leaves it visible behind the drag indicator.
struct PastWeeksLibrary: View {
    let week: WorkoutWeek
    /// The programme's own deck, for the wrap-up a banner opens.
    let program: Program
    /// Opens one week's wrap-up on appear — the harness only.
    ///
    /// A shot script cannot tap a banner, and the sheet-over-a-sheet is the
    /// largest thing this wave draws. The same seed `WorkoutTabView` took for
    /// the expanded row it replaces, at the one screen that can still use it.
    var seededOpen: String?

    @Environment(\.dismiss) private var dismiss

    /// The weeks and the blocks that group them. Nil until the read lands,
    /// which is a spinner rather than an empty state — a shelf that drew "no
    /// closed weeks" for the half-second before its own query answered would
    /// be lying about the one thing it is for.
    @State private var library: WorkoutWeek.Library?
    @State private var opened: Door?
    /// The week whose summary is being built, if any. One at a time: the
    /// summary is a PR replay per session, and two in flight would put two
    /// sheets in the queue.
    @State private var loading: String?

    /// The weeks as read, flat — what the wrap-up sheet is named from.
    private var weeks: [WorkoutWeek.PastWeek] { library?.weeks ?? [] }

    /// A summary the wrap-up sheet can be presented BY — the same box, for the
    /// same reason, as `WorkoutTabView.WrapDoor`: `WeeklyWrap.Summary` is an
    /// OnyxCore value and making it `Identifiable` to present one sheet would
    /// reach every caller of that type.
    struct Door: Identifiable {
        let summary: WeeklyWrap.Summary
        var id: String { summary.weekStart }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OnyxSpace.xl) {
                    if let library {
                        if library.weeks.isEmpty {
                            empty
                        } else {
                            ForEach(blocks(library)) { block in
                                section(block)
                            }
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OnyxSpace.xl)
                    }
                }
                .padding(.horizontal, OnyxSpace.l)
                .padding(.top, OnyxSpace.s)
                .padding(.bottom, OnyxSpace.xl)
            }
            .onyxScreen(.train)
            // ── "PAST WEEKS", NOT "LIBRARY" ────────────────────────────
            // The doors row one screen up already has a door called Library
            // and it is the EXERCISE catalogue (`ExerciseLibraryView`). Two
            // Librarys on one tab, holding different things, is the collision
            // the type is named for and the title must not repeat: the file is
            // a library of weeks, the screen is the section it replaced.
            .navigationTitle("Past Weeks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // The wrap-up owns its own stack and its own detents (see
        // `WeeklyWrapView`), so this is the whole of the presentation — the
        // same call `WorkoutTabView` makes from the This-week tile.
        .sheet(item: $opened) { door in
            // Named by the BANNER that opened it. The sheet's own default is
            // the week's date, and a shelf of `Week 5` opening a sheet headed
            // `Week of Sun 16 Aug` is one week with two names, a drag apart.
            WeeklyWrapView(
                summary: door.summary, program: program,
                title: weeks.first { $0.weekStart == door.summary.weekStart }?.label
            )
        }
        .task {
            if library == nil { library = await week.library() }
            guard let seededOpen, opened == nil,
                  let past = library?.weeks.first(where: { $0.weekStart == seededOpen })
            else { return }
            open(past)
        }
    }

    private var empty: some View {
        ContentUnavailableView(
            "No closed weeks yet",
            systemImage: "books.vertical",
            description: Text("A week appears here once it has ended and something was logged in it.")
        )
        .padding(.top, OnyxSpace.xl)
    }

    // MARK: - One block of the plan

    /// A `plan_phases` block and the weeks of it that were trained.
    ///
    /// `kind` is optional for the one bucket that has no block — see
    /// `blocks(_:)`.
    private struct Block: Identifiable {
        let id: String
        let eraTag: String
        let name: String
        let range: String
        let kind: PhaseKind?
        var weeks: [WorkoutWeek.PastWeek]
    }

    /// The weeks grouped under the block that owns each one, newest first.
    ///
    /// ── WHY IT WALKS `enumerateWeeks` AND NOT THE WEEKS ─────────────────────
    /// `Phases.enumerateWeeks` is the one function that expands a phase table
    /// into weeks, newest first, and it already answers which block a week
    /// belongs to by the order it emits them in. Grouping the logged weeks by
    /// hand would mean re-deriving that — a second walk over the same table,
    /// with its own idea of which Sunday opens a block.
    ///
    /// The join is the other way round from the obvious one: the enumeration
    /// is the spine and a logged week is looked up in it, so a week the plan
    /// PRESCRIBED but nothing was logged in draws no banner. A shelf of empty
    /// banners is a calendar, and the app has one.
    private func blocks(_ library: WorkoutWeek.Library) -> [Block] {
        let logged = Dictionary(library.weeks.map { ($0.weekStart, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Block] = []
        var at: [String: Int] = [:]
        var placed = Set<String>()

        for program in Phases.enumerateWeeks(PhaseKind.allCases, in: library.phases) {
            guard let past = logged[program.weekStart],
                  let def = Phases.span(for: program.weekStart, in: library.phases)?.def
            else { continue }
            placed.insert(program.weekStart)
            if let index = at[def.start] {
                out[index].weeks.append(past)
            } else {
                at[def.start] = out.count
                out.append(Block(
                    id: def.start,
                    eraTag: def.eraTag ?? def.name,
                    name: def.name,
                    range: range(def.start, def.endISO),
                    kind: def.kind,
                    weeks: [past]
                ))
            }
        }

        // ── THE WEEKS NO BLOCK CLAIMS ───────────────────────────────────────
        // `plan_phases` can have a gap in it — a fortnight between two blocks,
        // a week logged before the table was written — and `isPlannable` lets
        // those through because the plan itself covers them. Dropping them
        // would make a shelf that is missing training the reader did, silently,
        // which is worse than a section with no phase name to give.
        let orphans = library.weeks.filter { !placed.contains($0.weekStart) }
        if !orphans.isEmpty {
            out.append(Block(
                id: "unblocked",
                eraTag: "Between blocks",
                name: "No phase covers these weeks",
                range: range(orphans.last?.weekStart, orphans.first?.weekStart),
                kind: nil,
                weeks: orphans
            ))
        }
        return out
    }

    private func section(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.grid) {
            header(block)
            ForEach(block.weeks) { banner($0, kind: block.kind) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The block's own name, its phase, and the dates it ran.
    ///
    /// `eraTag` is the title because it is the name that distinguishes two
    /// blocks of the same KIND across two programmes — `Onyx Cut` against
    /// `PPL Cut` — and it defaults to the phase's name, so the second line is
    /// dropped when the two would say the same word twice.
    private func header(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            // `Shoulders`, not an `HStack` with a `Spacer`: at AX5 a block name
            // and a three-month date range cannot share a line, and a `Spacer`
            // cannot wrap — so the first cut of this header printed `ONYX /
            // CUT` over two lines beside a truncated `19 Jul –…`. The shared
            // primitive already makes the break a BRANCH rather than a measure.
            Shoulders(.firstTextBaseline) {
                HStack(spacing: OnyxSpace.xs) {
                    Circle()
                        .fill(tint(block.kind))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(block.eraTag.uppercased())
                        .onyxMicro()
                }
            } trailing: {
                Text(block.range)
                    .onyxType(.micro).onyxNumeral()
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineLimit(1)
            }
            // ── AND NOT "ONYX CUT / CUT" ───────────────────────────────
            // `eraTag` defaults to the phase's own name and is usually built
            // out of it — `Onyx Cut` over `Cut`, `PPL Bulk` over `Bulk` — so
            // an inequality test printed the same word twice on every real
            // block. The second line is for the block that says something the
            // tag does not ("Thailand Vacation" under "Thailand").
            if !block.eraTag.localizedCaseInsensitiveContains(block.name) {
                Text(block.name)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - One week

    /// A week as the session masthead draws a session (`SessionHeaderCard`):
    /// the hero label with its dates on the far shoulder, the capsules for what
    /// it trained, the totals under them, and a wash at the head of the tile.
    ///
    /// The wash takes the PHASE's colour rather than a split's day hue, which
    /// is the whole reason `Color.onyx.phase(_ kind:)` exists — a block reads
    /// as one stretch of the plan because eight banners in it share an ink.
    private func banner(_ past: WorkoutWeek.PastWeek, kind: PhaseKind?) -> some View {
        let hue = tint(kind)
        return Button { open(past) } label: {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Shoulders(.firstTextBaseline) {
                    Text(past.label)
                        .onyxType(.hero)
                        .foregroundStyle(hue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } trailing: {
                    Text(past.range)
                        .onyxType(.caption).onyxNumeral()
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                MuscleTagRow(muscles: past.muscles)
                // The banner's own two figures in the banner's own units —
                // `OnyxFormat.volume` and kilograms, not tonnes. A shelf that
                // rounded to `18.2 t` over a wrap-up saying `18,240 kg` is two
                // numbers for one week.
                Text(totals(past))
                    .onyxType(.secondary).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
                    // Two lines, the same allowance `SessionHeaderCard` gives
                    // its own totals: at AX5 `1 session · 5,350 kg` does not
                    // fit one line at any scale factor a number may be read at,
                    // and it truncated to `5,350…` — a tonnage with its last
                    // digits missing, which is worse than a second line.
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(OnyxSpace.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            // INSIDE the glass, always: the tile clips the wash to its own
            // corner radius, and a wash applied outside that clip paints a
            // square-cornered rectangle behind a rounded card.
            .onyxTopWash(hue)
            .onyxGlass(.tile)
            .overlay(alignment: .topTrailing) {
                // The summary is a PR replay per session. On a warm store it
                // lands inside a frame; on a long week it does not, and a
                // banner that did nothing visible when tapped reads as a dead
                // control.
                if loading == past.weekStart {
                    ProgressView().padding(OnyxSpace.m)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.98)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(past.label), \(past.range)")
        .accessibilityValue(spoken(past))
        .accessibilityHint("Opens this week's wrap-up")
        .accessibilityAddTraits(.isButton)
    }

    private func open(_ past: WorkoutWeek.PastWeek) {
        guard loading == nil else { return }
        loading = past.weekStart
        Task {
            let summary = await week.pastSummary(weekStart: past.weekStart)
            loading = nil
            guard let summary else { return }
            opened = Door(summary: summary)
        }
    }

    // MARK: - Words

    private func tint(_ kind: PhaseKind?) -> Color {
        kind.map { Color.onyx.phase($0) } ?? Color.onyx.textTertiary
    }

    private func totals(_ past: WorkoutWeek.PastWeek) -> String {
        "\(past.sessions) session\(past.sessions == 1 ? "" : "s") · \(OnyxFormat.volume(past.tonnageKg)) kg"
    }

    private func spoken(_ past: WorkoutWeek.PastWeek) -> String {
        var parts = ["\(past.sessions) sessions", "\(OnyxFormat.volume(past.tonnageKg)) kilograms"]
        if !past.muscles.isEmpty {
            parts.append(past.muscles.map(\.displayName).joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }

    /// `19 Jul – 17 Oct`. Both ends carry their month: a block runs for weeks
    /// and almost always crosses one, so the abbreviation `WeekWindow` drops
    /// inside a single week would be wrong here more often than not.
    private func range(_ from: String?, _ to: String?) -> String {
        let ends = [from, to].compactMap { iso -> String? in
            guard let iso, let date = LogicalDay.date(fromISO: iso) else { return nil }
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return ends.joined(separator: " – ")
    }
}

#if DEBUG
#Preview("Library") { HistoryPreviews.view("train-library") }
#endif
