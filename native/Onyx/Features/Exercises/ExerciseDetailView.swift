import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// One movement: what it trains, how far it has come, and every set of it.
///
/// ── TWO SEGMENTS, BECAUSE THEY ARE TWO QUESTIONS ────────────────────────────
/// Wave 7 had this as one scroll: badges, muscles, counts, the record book, a
/// chart, then forty set rows. Everything was present and nothing was
/// findable — "what is my best" and "what did I do last Tuesday" were forty
/// rows apart in a screen with no landmarks.
///
/// §5.5 splits it. **Summary** is the movement's own page: three figures, the
/// caveat that makes them honest, and the est-1RM curve. **History** is the
/// ledger, newest session first, as a compact grid of sets rather than a row
/// each — a session is a shape you recognise, and thirty rows hide the shape.
///
/// ── AND WHY THE FIGURES ARE DERIVED, NOT READ FROM `personal_records` ───────
/// That table is a CURRENT-BEST book keyed by canonical name, and its `volume`
/// axis is a per-SET tonnage record, not a session's. Reading "best session
/// volume" out of it would print a set's number under a session's label. Every
/// figure here comes from the ledger this page is already holding, so the strip
/// and the chart under it cannot disagree.
struct ExerciseDetailView: View {
    let entry: ExerciseCatalogEntry
    /// The library's own order, for the prev/next chevrons. Empty when the page
    /// was reached from somewhere with no list behind it.
    var siblings: [ExerciseCatalogEntry] = []
    #if DEBUG
    /// The shot loop opens the page on the segment it is photographing.
    var startOnHistory = false
    #endif

    @Environment(AppEnvironment.self) private var environment

    @State private var current: ExerciseCatalogEntry?
    @State private var segment = Segment.summary
    @State private var ledger: [HistorySetRow] = []
    @State private var loaded = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Segment: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case history = "History"
        var id: String { rawValue }
    }

    private var shown: ExerciseCatalogEntry { current ?? entry }
    private var canonical: String { ExerciseAliases.canonicalName(shown.name) }
    private var group: MuscleGroup { MuscleGroup.forExercise(shown.name) }
    private var timed: Bool { TimedExercise.isTimed(canonical) }
    /// Unloaded work has no 1RM to estimate: the reading is the rep count.
    private var unloaded: Bool { working.allSatisfy { $0.weightKg <= 0 } }
    private var working: [HistorySetRow] { ledger.filter { SetTags.isWorkingSet($0.setType) } }

    var body: some View {
        List {
            Section {
                Picker("View", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: OnyxSpace.l, bottom: OnyxSpace.xs, trailing: OnyxSpace.l))
            }

            if segment == .summary {
                summary
            } else {
                history
            }
        }
        .listRowBackground(Rectangle().fill(.ultraThinMaterial))
        .scrollContentBackground(.hidden)
        .onyxScreen(group.domain)
        .tint(group.domain.accent)
        .navigationTitle(canonical)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { chevrons }
        .sensoryFeedback(.selection, trigger: shown.id)
        .task(id: shown.id) {
            #if DEBUG
            if startOnHistory { segment = .history }
            #endif
            let database = environment.database, id = shown.id
            ledger = await Task.detached(priority: .userInitiated) {
                (try? database.historySets(exerciseIds: [id])) ?? []
            }.value
            loaded = true
        }
    }

    // MARK: - Prev / next

    /// Walk the library without going back to it.
    ///
    /// The chevrons move THROUGH the list as it was ordered on screen — grouped
    /// by muscle, alphabetical inside a group — so "next" is the row that was
    /// under your finger, not the next id in the table.
    @ToolbarContentBuilder
    private var chevrons: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { step(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == nil || index == 0)
                .accessibilityLabel("Previous exercise")
            Button { step(1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == nil || index == siblings.count - 1)
                .accessibilityLabel("Next exercise")
        }
    }

    private var index: Int? { siblings.firstIndex { $0.id == shown.id } }

    private func step(_ by: Int) {
        guard let index, siblings.indices.contains(index + by) else { return }
        loaded = false
        ledger = []
        current = siblings[index + by]
    }

    // MARK: - Summary

    @ViewBuilder
    private var summary: some View {
        Section {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                HStack(spacing: OnyxSpace.grid) {
                    stat("Heaviest", stats.heaviestKg.map { "\(OnyxFormat.kg($0)) kg" } ?? "—")
                    stat(timed ? "Longest hold" : "Best 1RM", bestReading)
                    stat("Best session", stats.bestSessionVolumeKg.map { "\(OnyxFormat.volume($0)) kg" } ?? "—")
                }
                // The caveat is the difference between a headline and a lie.
                // "Heaviest" is ONE set, not a session; the total reps beside it
                // is the volume the heaviest number says nothing about.
                Text(caveat)
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textTertiary)
                    // ONE line (§W7). At an accessibility size it may wrap —
                    // clipping a caveat is worse than a second line there.
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.vertical, OnyxSpace.xs)
            .accessibilityElement(children: .contain)
        } header: {
            OnyxSectionHeader("Best", group.domain)
        }

        Section {
            OnyxChartCard(
                unloaded ? "Reps per session" : "Estimated 1RM",
                domain: group.domain,
                headline: headline
            ) {
                if !loaded {
                    OnyxChartEmpty("Reading the ledger…")
                } else if series.count >= 2 {
                    E1rmTrendChart(series: [SessionAnalysis.TrailSeries(id: canonical, points: series)],
                                   scrollDays: spanDays > 90 ? 90 : nil)
                } else {
                    OnyxChartEmpty("Two sessions and the line starts.")
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        Section {
            musclesRow("Directly", primary)
            musclesRow("Assisting", secondary)
            if !badges.isEmpty {
                // Wrapping rather than a single line: at AX5 three chips in an
                // `HStack` would each be two characters wide.
                FlowRow(spacing: OnyxSpace.xs) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .onyxType(.micro)
                            .textCase(nil)
                            .padding(.horizontal, OnyxSpace.s)
                            .padding(.vertical, 3)
                            .background(group.domain.accent.opacity(0.18), in: .capsule)
                            .foregroundStyle(group.domain.accent)
                    }
                }
                .frame(minHeight: 44)
            }
        } header: {
            OnyxSectionHeader("Muscles", group.domain)
        } footer: {
            // The credit rule, stated where the numbers it produces are read.
            // It is why a set of rows pays the lats fully and the biceps at
            // half, and it is the thing most often assumed to be a bug in the
            // weekly totals.
            Text("A set counts fully for what it trains directly and at half for what assists. Overlaps take the larger credit, never the sum.")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).onyxMicro()
            Text(value)
                .onyxType(.display).onyxNumeral()
                .foregroundStyle(Color.onyx.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The three numbers, through the shared definition (§W7 decision 4).
    ///
    /// It used to be three derivations written here, and the web had three more
    /// computed by an RPC; `ExerciseSummary` is the one implementation both
    /// clients call, with a golden vector between them.
    private var stats: ExerciseSummary {
        ExerciseSummary.summarize(
            ledger.map {
                ExerciseSummarySet(
                    sessionId: $0.sessionId, weightKg: $0.weightKg, reps: Double($0.reps),
                    est: $0.est1rmKg, setType: $0.setType, side: $0.side, pairId: $0.pairId
                )
            },
            timed: timed
        )
    }

    private var bestReading: String {
        if timed { return stats.bestReps.map { "\(jsIntegerString($0)) s" } ?? "—" }
        if unloaded { return stats.bestReps.map { "\(jsIntegerString($0)) reps" } ?? "—" }
        return stats.bestE1rmKg.map { "\(jsIntegerString(jsRound1($0))) kg" } ?? "—"
    }

    /// ── ONE LINE, NOT TWO ───────────────────────────────────────────────────
    /// The caveat is the difference between a headline and a lie — "Heaviest"
    /// is one SET, and the rep count is what that number says nothing about.
    /// It was two clauses joined by a separator and wrapped to two lines on
    /// every phone, under a strip that is three lines tall. It says the same
    /// two facts in one line now, and the accessibility label carries the long
    /// form for anyone who cannot see the strip above it.
    private var caveat: String {
        guard stats.workingSets > 0 else { return "No working sets logged yet." }
        let top = stats.heaviestKg.map {
            SetFormat.format(weightKg: $0, reps: stats.heaviestSetReps ?? 0, timed: timed)
        }
        let work = "\(jsIntegerString(stats.totalReps)) reps · \(stats.workingSets) sets"
        return top.map { "Top \($0) · \(work)" } ?? work.capitalizedFirst
    }

    private var headline: String? {
        guard let last = series.last else { return nil }
        return unloaded ? "\(jsIntegerString(last.kg)) reps" : "\(jsIntegerString(jsRound1(last.kg))) kg"
    }

    /// The session MEAN est-1RM — or, for unloaded work, the session's mean rep
    /// count. Same shape, so one chart draws both. `SessionAnalysis` owns the
    /// rule and says why the mean beats the max.
    private var series: [(date: String, kg: Double)] {
        SessionAnalysis.sessionMeanE1rm(ledger, timed: timed)
    }

    /// Days between the first and last plotted point; past 90 the chart pans.
    private var spanDays: Int {
        guard let first = series.first, let last = series.last,
              let a = ISODate.dayNumber(first.date), let b = ISODate.dayNumber(last.date) else { return 0 }
        return b - a
    }

    private var primary: [LandmarkMuscle] { MuscleMap.primaryLandmarks(shown.name).uniqued() }

    /// The assisting muscles, MINUS anything already trained directly.
    ///
    /// Several map tokens fold onto one landmark — a wide-grip row lists `traps`
    /// as an assist and `upper back` as a primary, and both are `upperBack` here
    /// because sixteen landmarks is the resolution the app scores in. Printed
    /// raw, "Upper back" appears on both rows and reads as 1.5 sets of credit
    /// for one muscle. `MuscleCredit` takes the LARGER credit on an overlap and
    /// never the sum, so direct work wins and the assist is not shown twice.
    private var secondary: [LandmarkMuscle] {
        let direct = Set(primary)
        return MuscleMap.secondaryLandmarks(shown.name).uniqued().filter { !direct.contains($0) }
    }

    /// ── ONE LINE OF CHIPS, NOT A WRAPPED SENTENCE ──────────────────────────
    /// "Lats, Upper back, Rear delts, Biceps, Forearms" as trailing text wrapped
    /// to three lines and pushed the whole Muscles section past the fold. Chips
    /// name the same muscles in a third of the height, they read as a SET
    /// rather than as prose, and the row scrolls sideways when there are more
    /// than fit — which is a gesture, where a truncated sentence is a loss.
    ///
    /// At an accessibility size the chips are the wrong shape entirely, so the
    /// row falls back to the sentence it used to be.
    @ViewBuilder
    private func musclesRow(_ label: String, _ muscles: [LandmarkMuscle]) -> some View {
        if !muscles.isEmpty {
            let spoken = muscles.map(\.displayName).joined(separator: ", ")
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                Text(label).onyxMicro()
                if typeSize.isAccessibilitySize {
                    Text(spoken).foregroundStyle(Color.onyx.textPrimary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: OnyxSpace.xs) {
                            ForEach(muscles, id: \.self) { muscle in
                                Text(muscle.displayName)
                                    .onyxType(.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, OnyxSpace.s)
                                    .padding(.vertical, 3)
                                    .background(group.domain.accent.opacity(0.14), in: .capsule)
                                    .foregroundStyle(Color.onyx.textPrimary)
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            }
            .frame(minHeight: 40)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(spoken)
        }
    }

    /// How the movement is LOGGED — the three facts that change which controls
    /// the deck offers, so they belong on the page about the movement.
    private var badges: [String] {
        var out: [String] = []
        if Unilateral.isUnilateral(shown.name) { out.append("One side at a time") }
        if Bodyweight.isBodyweight(shown.name) {
            out.append(Bodyweight.isLoadable(shown.name) ? "Bodyweight · loadable" : "Bodyweight")
        }
        if TimedExercise.isTimed(shown.name) { out.append("Held for time") }
        return out
    }

    // MARK: - History

    /// Newest session first, its sets as a two-column grid.
    ///
    /// ── WHY A GRID AND NOT A ROW PER SET ────────────────────────────────────
    /// A row per set is forty rows for six sessions, and every one of them
    /// repeats the date. A session is a handful of chips — you read
    /// `42×10 42×9 40×12` as a shape and see the fade without parsing three
    /// rows. Warm-ups are drawn in tertiary ink rather than hidden, because a
    /// session that opened at 20 kg is part of what the session was.
    ///
    /// ── AND WHY A FIXED TWO COLUMNS RATHER THAN A FLOW ──────────────────────
    /// `FlowRow` sized each chip to its own content and packed them left, so a
    /// three-set session left a third of the row empty on the right and every
    /// session had a different ragged edge — the eye had nothing to scan down.
    /// Two flexible columns give every chip the same width and every session
    /// the same shape, and a short session is centred in a full row rather than
    /// stranded against the left margin.
    @ViewBuilder
    private var history: some View {
        if loaded, sessions.isEmpty {
            Section {
                ContentUnavailableView("No sets logged", systemImage: "clock",
                                       description: Text("This movement is in the catalogue but has no history."))
            }
            .listRowBackground(Color.clear)
        }
        ForEach(sessions, id: \.id) { session in
            Section {
                LazyVGrid(columns: setColumns, spacing: OnyxSpace.xs) {
                    ForEach(session.sets, id: \.id) { set in
                        chip(set)
                    }
                }
                .frame(minHeight: 40)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(session.spoken(timed: timed))
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    OnyxSectionHeader(session.title, group.domain)
                    Spacer()
                    Text(session.meta)
                        .onyxType(.micro).onyxNumeral()
                        .foregroundStyle(Color.onyx.textTertiary)
                }
            }
        }
    }

    /// Two across, one at an accessibility size — the same rule the session
    /// page's metric grid follows.
    private var setColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.xs),
              count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    private func chip(_ set: HistorySetRow) -> some View {
        let work = SetTags.isWorkingSet(set.setType)
        return Text(SetFormat.format(weightKg: set.weightKg, reps: Double(set.reps), timed: timed))
            .onyxType(.caption).onyxNumeral()
            .foregroundStyle(work ? Color.onyx.textPrimary : Color.onyx.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OnyxSpace.s)
            .padding(.vertical, OnyxSpace.xs)
            .background(
                work ? group.domain.accent.opacity(0.14) : Color.onyx.hairline,
                in: RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
            )
    }

    private struct SessionBlock {
        let id: String
        let title: String
        let meta: String
        let sets: [HistorySetRow]

        func spoken(timed: Bool) -> String {
            "\(title), " + sets.map { SetFormat.format(weightKg: $0.weightKg, reps: Double($0.reps), timed: timed) }
                .joined(separator: ", ")
        }
    }

    private var sessions: [SessionBlock] {
        var order: [String] = []
        var by: [String: [HistorySetRow]] = [:]
        for row in ledger {
            if by[row.sessionId] == nil { order.append(row.sessionId) }
            by[row.sessionId, default: []].append(row)
        }
        return order.reversed().map { id in
            let rows = by[id]!
            let date = LogicalDay.date(fromISO: rows[0].date)
                .map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? rows[0].date
            let work = rows.filter { SetTags.isWorkingSet($0.setType) }
            let volume = jsRound(SessionVolume.sessionVolumeKg(work.map(SessionAnalysis.volumeSet)))
            var meta = "\(work.count) sets"
            if volume > 0 { meta += " · \(OnyxFormat.volume(volume)) kg" }
            return SessionBlock(id: id, title: date, meta: meta, sets: rows)
        }
    }
}

/// Chips that wrap.
///
/// `Layout` rather than a `LazyVGrid`: a grid gives every chip the widest chip's
/// width, so "Bodyweight" and "One side at a time" would sit in two columns the
/// width of the longer one. This is the smallest correct flow layout — measure
/// each subview, break when the line is full.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = measure(view, within: width)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = measure(view, within: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    /// A chip's own ideal size — unless its ideal is wider than the whole row,
    /// in which case the row's width is offered instead.
    ///
    /// ── WHY THE CLAMP (W5) ──────────────────────────────────────────────────
    /// This layout wraps BETWEEN subviews and never inside one, so `.unspecified`
    /// alone is the right question for every chip that fits: it is what keeps
    /// "Bodyweight" one line rather than letting it break on its own. But a chip
    /// whose ideal exceeds the container has no line to be moved to — it was
    /// placed at that ideal width and drawn straight off the edge of the card,
    /// with `lineLimit` and `minimumScaleFactor` never consulted because nothing
    /// ever told the text it was short of room.
    ///
    /// It went unseen because every chip in this app is two or three words. The
    /// first one that is not — the bout's "Automatically logged", on the ledger
    /// since W4 and on the Train tab since W5 — reads "Automatically lo" at AX5,
    /// clipped mid-word with a capsule running past the glass.
    ///
    /// Re-proposing the row's width is what lets the chip's OWN rules run: two
    /// lines first, then down to 60 %, and only then a truncation. Nothing that
    /// already fitted changes, because for those the branch is never taken.
    private func measure(_ view: LayoutSubviews.Element, within width: CGFloat) -> CGSize {
        let ideal = view.sizeThatFits(.unspecified)
        guard ideal.width > width else { return ideal }
        return view.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }
}

#if DEBUG
#Preview("Exercise") {
    HistoryPreviews.view("exercise-history")
}
#endif

private extension Array where Element: Hashable {
    /// Order-preserving dedupe. Several map tokens fold onto one landmark.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
    /// Sentence case for a caption stitched from clauses, without touching the
    /// rest of the string — `.capitalized` would turn "42 kg" into "42 Kg".
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
