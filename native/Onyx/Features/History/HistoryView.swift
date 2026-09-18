import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// History — the door from Today (§5.9, decision 1).
///
/// ── WHY THIS REPLACED TWO SCREENS ───────────────────────────────────────────
/// It replaces `SessionHistoryView`, a flat reverse-chronological list of every
/// session, and Pathfinder, a week-by-week table on the Settings tab. Both were
/// answering the same question badly. The flat list could not show a day you
/// MISSED — a day with no session has no row — and the block is judged on
/// exactly that: five sessions against a target of five. Pathfinder could, and
/// was buried two navigations deep inside settings, where nobody looks for last
/// week.
///
/// One door, one unit: a week. Capsule → days → day. Every number on every one
/// of those three levels comes from the same `WeekWindow`, so changing "Week
/// starts on" in Settings re-cuts the whole list rather than re-cutting the
/// list and leaving the labels behind.
struct HistoryView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Supplied only by the screenshot harness.
    var seeded: [HistoryWeeks.Capsule]?

    @State private var capsules: [HistoryWeeks.Capsule]?
    /// The generation this screen's data was read at.
    ///
    /// `.task(id:)` fires on appear too, and this screen deliberately reads its
    /// whole ledger once. Keying the guard on the generation preserves that and
    /// re-reads exactly when a rescore cascade has finished rewriting what is
    /// under it — see `AppEnvironment.rescoreGeneration`.
    @State private var loadedAt = -1

    @State private var segment: Segment = .weeks
    @State private var window: EraWindow = .default
    @State private var input: EraWindowInput?
    @State private var jumping = false
    @State private var jumpTo: JumpDate?

    enum Segment: String, CaseIterable, Identifiable {
        case weeks = "Weeks"
        case body = "Body"
        var id: Self { self }
    }

    /// `navigationDestination(item:)` needs an `Identifiable`, and a bare date
    /// string is not one.
    struct JumpDate: Identifiable, Hashable { let id: String }

    var body: some View {
        List {
            Section {
                Picker("View", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("History view")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(.init(top: 0, leading: OnyxSpace.l, bottom: OnyxSpace.s, trailing: OnyxSpace.l))

            switch segment {
            case .weeks: weeks
            case .body: bodySegment
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(OnyxSpace.m)
        .scrollContentBackground(.hidden)
        .onyxScreen(.train)
        .tint(OnyxDomain.train.accent)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { jumping = true } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Jump to a date")
                .disabled(segment == .body)
            }
        }
        .sheet(isPresented: $jumping) {
            CalendarJumpSheet(capsules: capsules ?? []) { date in
                jumping = false
                jumpTo = JumpDate(id: date)
            }
        }
        .navigationDestination(item: $jumpTo) { jump in
            DayScreen(model: DayModel(
                database: environment.database, userId: environment.userIdString, date: jump.id,
                environment: environment
            ))
        }
        .overlay { emptyState }
        .task(id: environment.rescoreGeneration) {
            guard loadedAt != environment.rescoreGeneration else { return }
            loadedAt = environment.rescoreGeneration
            if let seeded {
                capsules = seeded
                input = EraWindowSource.input(
                    database: environment.database,
                    firstDataISO: seeded.map(\.window.start).min()
                )
                return
            }
            let database = environment.database
            let built = await Task.detached(priority: .userInitiated) {
                HistoryWeeks.capsules(database: database)
            }.value
            capsules = built
            // "All" is this list's own oldest week — the capsules are already
            // built from the first day anything was recorded.
            input = EraWindowSource.input(
                database: environment.database,
                firstDataISO: built.map(\.window.start).min()
            )
        }
    }

    // MARK: - Weeks

    @ViewBuilder
    private var weeks: some View {
        // The window scrolls WITH the list rather than pinning under the nav
        // bar: two stacked controls in fixed chrome leave a 96 pt band above
        // the first row, and at AX5 the second one wraps into three lines of
        // it.
        if let input, (capsules?.count ?? 0) > 0 {
            Section {
                EraWindowPicker(selection: $window, input: input)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(.init(top: 0, leading: OnyxSpace.l, bottom: OnyxSpace.s, trailing: OnyxSpace.l))
        }

        ForEach(filtered) { capsule in
            Section {
                NavigationLink {
                    WeekDaysView(window: capsule.window)
                } label: {
                    WeekCapsuleRow(capsule: capsule)
                }
                .listRowInsets(.init(top: OnyxSpace.m, leading: OnyxSpace.l,
                                     bottom: OnyxSpace.m, trailing: OnyxSpace.l))
            }
        }
    }

    /// The window's own bounds, or nil before the goals row has been read.
    private var resolved: ResolvedEraWindow? { input.map { window.resolve($0) } }

    /// Every capsule the window TOUCHES, not only the ones inside it.
    ///
    /// A week is seven days and a window has two ends; a "30 d" window opening
    /// on a Wednesday would otherwise drop the week it starts in — five days of
    /// which are in the window — and the list would begin mid-block with no
    /// explanation. Overlap is the honest test for a range against a range.
    private var filtered: [HistoryWeeks.Capsule] {
        guard let resolved else { return capsules ?? [] }
        return (capsules ?? []).filter {
            $0.window.end >= resolved.startISO && $0.window.start <= resolved.endISO
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var bodySegment: some View {
        Section {
            BodyTrendsView(embedded: true)
                .frame(minHeight: 480)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    // MARK: - Empty

    @ViewBuilder
    private var emptyState: some View {
        if capsules == nil {
            ProgressView()
        } else if segment == .weeks, capsules?.isEmpty == true {
            ContentUnavailableView(
                "No history yet",
                systemImage: "calendar",
                description: Text("Finish a workout or step on the scale and the week lands here.")
            )
        } else if segment == .weeks, filtered.isEmpty {
            ContentUnavailableView(
                "No weeks in \(resolved?.label ?? "this window")",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Nothing was logged in that timeframe. Widen it and the weeks come back.")
            )
        }
    }
}

// MARK: - The capsule

/// `Week 7 · Cut W7 · 30 Aug – 5 Sep`, its numbers, and seven dots.
struct WeekCapsuleRow: View {
    @Environment(AppEnvironment.self) private var environment
    let capsule: HistoryWeeks.Capsule

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            // ── WHY THE HEADER STACKS ───────────────────────────────────────
            // Three columns — "Week 7", the phase pill and "30 Aug – 5 Sep" —
            // share one line comfortably at every ordinary size and shatter at
            // AX5 into "We / ek / 7" beside a two-line pill that draws as an
            // ellipse. At accessibility sizes the same three run down the page,
            // which is the shape they were always going to take.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                    title
                    tags
                    range
                }
            } else {
                // Up to three pills now share the line with a title and a date
                // range, and "Maintenance" beside "Active" is 130 pt of it.
                // `ViewThatFits` asks the layout system rather than guessing:
                // one line while one fits, tags on their own line when not.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                        title
                        tags
                        Spacer(minLength: OnyxSpace.xs)
                        range
                    }
                    VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                            title
                            Spacer(minLength: OnyxSpace.xs)
                            range
                        }
                        tags
                    }
                }
            }

            DayStrip(cells: capsule.cells)

            Text(meta)
                .onyxType(.caption)
                .onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, OnyxSpace.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(capsule.window.label(in: environment.targets?.schedule)), \(capsule.window.rangeLabel).\(spokenTags) \(meta)")
    }

    /// What the week WAS, in at most three pills: which phase, whether the food
    /// was at maintenance, and whether it is the week you are standing in.
    private var tags: some View {
        HStack(spacing: OnyxSpace.xs) {
            if let phase = capsule.phaseLabel {
                pill(phase, OnyxDomain.train.accent, ink: Color.onyx.textSecondary)
            }
            // A nutrition rung, so it wears the food domain — the training
            // programme did not change and the pill should not claim it did.
            if capsule.isMaintenance {
                pill("Maintenance", OnyxDomain.fuel.accent)
            }
            // Not "This week": the list is scanned, and the reader wants to
            // know which row is live, not to be told the definition of one.
            if capsule.window.isCurrent {
                pill("Active", Color.onyx.good)
            }
        }
    }

    private var spokenTags: String {
        var parts: [String] = []
        if let phase = capsule.phaseLabel { parts.append(phase) }
        if capsule.isMaintenance { parts.append("maintenance week") }
        if capsule.window.isCurrent { parts.append("the current week") }
        return parts.isEmpty ? "" : " \(parts.joined(separator: ", "))."
    }

    private var title: some View {
        Text(capsule.window.label(in: environment.targets?.schedule))
            .onyxType(.display)
            .foregroundStyle(Color.onyx.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// One line, always. Wrapped over two, the `Capsule` behind it stops being
    /// a pill and becomes an ellipse the width of the longest word.
    private func pill(_ text: String, _ tint: Color, ink: Color? = nil) -> some View {
        Text(text)
            .onyxType(.micro)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(ink ?? tint)
            .padding(.horizontal, OnyxSpace.s)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
    }

    private var range: some View {
        Text(capsule.window.rangeLabel)
            .onyxType(.caption)
            .foregroundStyle(Color.onyx.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Only what happened. A week with no sessions says so in one word instead
    /// of printing `0 sessions · 0 kg · 0 sets`, which reads as a bug.
    private var meta: String {
        guard capsule.sessions > 0 || capsule.weightDeltaKg != nil else { return "Nothing logged" }
        var parts: [String] = []
        if capsule.sessions > 0 {
            parts.append("\(capsule.sessions) session\(capsule.sessions == 1 ? "" : "s")")
            parts.append("\(Format.volume(capsule.tonnageKg)) kg")
            parts.append("\(capsule.sets) sets")
        }
        if capsule.prCount > 0 { parts.append("\(capsule.prCount) PR") }
        if let delta = capsule.weightDeltaKg {
            let sign = delta > 0 ? "+" : ""
            parts.append("\(sign)\(delta.formatted(.number.precision(.fractionLength(1)))) kg")
        }
        return parts.joined(separator: " · ")
    }
}

/// Seven dots — logged in the split's own colour, planned-and-missed as a
/// hollow ring, rest as a tertiary speck.
///
/// The ring is the point of the whole screen: a missed day has no session row
/// anywhere in the database, so the only way to draw it is to ask the SCHEDULE
/// what the day was for and find nothing against it.
struct DayStrip: View {
    let cells: [HistoryWeeks.DayCell]

    var body: some View {
        HStack(spacing: OnyxSpace.xs) {
            ForEach(cells) { cell in
                VStack(spacing: 3) {
                    Text(cell.initial)
                        .onyxType(.micro)
                        .foregroundStyle(Color.onyx.textTertiary)
                    dot(cell)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func dot(_ cell: HistoryWeeks.DayCell) -> some View {
        if cell.isLogged {
            Circle()
                .fill(Color.onyx.day(cell.dayKey))
                .frame(width: 10, height: 10)
        } else if cell.isRest {
            Circle()
                .fill(Color.onyx.textTertiary.opacity(0.5))
                .frame(width: 4, height: 4)
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .strokeBorder(
                    Color.onyx.day(cell.dayKey).opacity(cell.isFuture ? 0.35 : 0.8),
                    lineWidth: 1.5
                )
                .frame(width: 10, height: 10)
        }
    }
}

#if DEBUG
#Preview("History") { HistoryPreviews.view("history") }
#endif
