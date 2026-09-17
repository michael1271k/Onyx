import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// The week, once the work in it is done.
///
/// ── WHY THIS IS NOT A SUNDAY MODAL ──────────────────────────────────────────
/// The obvious build is a sheet that appears on its own when the week closes.
/// It is also the build nobody reads: a modal between you and the screen you
/// opened gets dismissed by reflex, and once dismissed it is gone — a summary
/// of the week you just trained, shown exactly once, at a moment you did not
/// choose.
///
/// So the This-week tile TRANSFORMS instead. The same panel, in the same place,
/// now saying "Week wrapped" with a chevron. Nothing interrupts, the door is
/// permanent, and a week from March is reachable by the same route as this one.
///
/// ── WHY IT IS NOW A SHEET, WHICH IS NOT A CONTRADICTION (W1a) ───────────────
/// That argument is against a modal that arrives UNINVITED. It says nothing
/// about what happens after the tile is tapped, and a push turns out to be the
/// wrong answer there: the wrap-up is a thing you glance at and put down, and a
/// push replaces the Train tab, costs a back tap to leave, and buries the
/// screen the reader came to use. A detent sheet says what this is — the reel
/// at 560 pt, the breakdown if you drag for it, and the tab visible behind it
/// the whole time. The door is still permanent and still the reader's to open.
///
/// ── AND WHY THE WEEK CLOSES ON FRIDAY ───────────────────────────────────────
/// `WeeklyWrap.isWrapped`, not the calendar: on a plan that rests Saturday the
/// training week ends on Friday evening, and a summary that waits for Sunday
/// arrives after you have stopped thinking about the week it describes. Cardio
/// does not gate it — a walk is not something the training week waits for.
///
/// ── WHAT THE 560 DETENT IS FOR ──────────────────────────────────────────────
/// It used to render three uncapped lists: every movement of the week, one
/// 48 pt row each, thirty rows on a full week. That is a document, and nobody
/// reads a document on the evening they finished the work it describes. The
/// reel above the fold answers "how did the week go" in five seconds; the
/// document is still there, one drag and one disclosure away, unabridged.
struct WeeklyWrapView: View {
    let summary: WeeklyWrap.Summary
    let program: Program
    /// What to call this week, when the caller already knows.
    ///
    /// ── WHY THE SHEET CANNOT ALWAYS WORK IT OUT ─────────────────────────────
    /// `WeeklyWrap.Summary` carries no phase table and no week-0 anchor, so the
    /// default below is the only name it can derive on its own — the date. That
    /// was fine while every door into this sheet called a week by its date too.
    /// The Past Weeks shelf calls it `Week 5` (`Week.label(ofWeekStart:…)`, the
    /// one counter History and the export also use), and a banner that opened
    /// into a sheet with a different name for the same week is the disagreement
    /// `PastWeek.label` has always existed to prevent.
    ///
    /// Optional rather than required: every other call site passes the summary
    /// and nothing else, and threading a phase table through four of them to
    /// re-derive a string one of them already holds is the wrong direction.
    var title: String?

    /// The reel's height. One constant used by both the detent SET and the
    /// initial selection — `PresentationDetent.height` is value-equal, so two
    /// literals would compile and then drift apart at the first tweak.
    private static let reel = PresentationDetent.height(560)

    @State private var detent: PresentationDetent

    /// `detent` is settable only so the screenshot harness can photograph the
    /// `.large` state, which has no other route in a shot — the same reason
    /// `WorkoutTabView` takes a seeded day. Every app call site takes the
    /// default and opens on the reel.
    init(
        summary: WeeklyWrap.Summary, program: Program, title: String? = nil,
        detent: PresentationDetent = WeeklyWrapView.reel
    ) {
        self.summary = summary
        self.program = program
        self.title = title
        _detent = State(initialValue: detent)
    }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                WeeklyWrapContent(
                    summary: summary, program: program, title: title,
                    // The legend is the half of the ring that only fits once
                    // the sheet has been dragged up, so it follows the detent.
                    showsLegend: detent == .large,
                    // Both the ring and the breakdown disclosure ask for room.
                    // Raising here and not inside the content is what lets the
                    // same content sit inline on the Train tab, where there is
                    // no sheet and nothing to raise.
                    onNeedsHeight: { withAnimation(OnyxMotion.move) { detent = .large } }
                )
                .padding(.horizontal, OnyxSpace.l)
                .padding(.bottom, OnyxSpace.xl)
            }
            .onyxScreen(.train)
            .navigationTitle(title ?? WeeklyWrapContent.title(summary))
            .navigationBarTitleDisplayMode(.inline)
            // Without this the inline bar draws its own material band over the
            // mesh the moment content scrolls under it.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([Self.reel, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.onyx.base)
        // The OPPOSITE of `MuscleDistributionSheet` and `DomainSheet`, on
        // purpose. Those two are lists meant to be READ at the small detent, so
        // they suppress resizing and let a drag scroll. This one is a reel whose
        // breakdown is meant to be dragged up into, which is the behaviour they
        // were suppressing.
        .presentationContentInteraction(.resizes)
        .preferredColorScheme(.dark)
    }
}

/// The wrap-up's CONTENT, with no chrome of its own (W6).
///
/// ── WHY IT WAS SPLIT OUT OF THE SHEET ───────────────────────────────────────
/// The Train tab grew a list of closed weeks, each row expanding IN PLACE into
/// the same banner. "In place" rules out the sheet: it carries a
/// `NavigationStack`, a `ScrollView` and two detents, and a scroll view inside
/// the tab's own scroll view is the one arrangement SwiftUI will not lay out.
/// So the chrome stayed on `WeeklyWrapView` and everything that draws a figure
/// moved here, unchanged — the reel is a `LazyVStack` either way and neither
/// container had an opinion about it.
///
/// The two hooks are what the chrome used to do for itself. A sheet answers
/// `showsLegend` from its detent and grows on `onNeedsHeight`; the tab passes
/// `true` and `{}`, because inline content is already at its full height.
struct WeeklyWrapContent: View {
    let summary: WeeklyWrap.Summary
    let program: Program
    /// The week's name when the caller knows it — see `WeeklyWrapView.title`.
    /// Read here only by the share preview, so the card that leaves the phone
    /// and the bar above it cannot call one week two things.
    var title: String?
    var showsLegend = true
    var onNeedsHeight: () -> Void = {}

    /// Every movement of the week. Closed by default; opening it raises the sheet.
    @State private var breakdownOpen = false

    /// Off by default. A share card is the one surface in this app that leaves
    /// the phone, and the figures on it are the user's to choose — so the
    /// private ones are absent until asked for, which is the only default that
    /// cannot leak something by being forgotten.
    @State private var showBodyweight = false
    /// The rendered card, re-made whenever the toggle changes.
    ///
    /// Held rather than computed in `body`: `ShareLink` needs its item up front,
    /// and rendering a 540×960 composition on every layout pass to supply one
    /// would re-rasterise the card every time the screen scrolls.
    @State private var card: Image?
    /// Which toggle state `card` was rendered for. A sheet is opened and closed
    /// far more casually than a screen is pushed, and without this every open
    /// pays the 18 MB rasterise again for a card nothing asked to change.
    @State private var renderedFor: Bool?

    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `Week of 23 Aug` — the banner's own name for the week, and the one the
    /// collapsed row that expands into it wears.
    static func title(_ summary: WeeklyWrap.Summary) -> String {
        "Week of \(Swap.shortDayLabel(summary.weekStart))"
    }

    var body: some View {
        // LAZY, and it is load-bearing rather than an optimisation: a
        // plain VStack builds every subview on presentation, which
        // fires `shareSection`'s render task in the same turn that lays
        // the sheet out. The share control is below the 560 fold by
        // construction, so lazily is the only way it is honestly last.
        LazyVStack(alignment: .leading, spacing: OnyxSpace.l) {
            headline
            bestsCard
            ringCard
            topThree
            breakdown
            shareSection
        }
        .onChange(of: breakdownOpen) { _, open in
            // Expanding raises the sheet, so the rows arrive in the same
            // gesture that asked for them rather than one drag later.
            // Collapsing does NOT lower it: shrinking the sheet out from under
            // a thumb that just tapped "hide" is a second thing nobody asked
            // for.
            if open { onNeedsHeight() }
        }
    }

    // MARK: - The reel

    private var headline: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.m) {
            // A deload says so at the top, before any figure is read. The same
            // tonnage means two different things in the two kinds of week, and
            // a reader who learns which one this was AFTER seeing the drops has
            // already had the wrong reaction.
            if summary.isDeload {
                Label("Deload week — lighter by design", systemImage: "moon.zzz")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textSecondary)
            }
            // ── ONE COLUMN AT AN ACCESSIBILITY SIZE (W1a) ───────────────────
            // Three cells across a 375 pt card is 117 pt each, and at AX5 that
            // broke "SESSIONS" into SES / SIO / NS and printed the week's
            // tonnage as "42,…". The same collapse `WeekVitalsRow` already
            // makes, for the reason it states: a figure shown as an ellipsis is
            // worse than one not shown.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OnyxSpace.m) { stats }
            } else {
                HStack(spacing: OnyxSpace.m) { stats }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OnyxSpace.l)
        .onyxGlass(.tile)
    }

    @ViewBuilder
    private var stats: some View {
        stat("SESSIONS", "\(summary.sessions)", delta: nil)
        // "TONNAGE KG" and not a bare "TONNAGE": the delta beneath it carries
        // its unit, and a figure whose unit is stated one line down but not on
        // itself reads as two different quantities.
        stat("TONNAGE KG", OnyxFormat.volume(summary.tonnageKg), delta: summary.tonnageDeltaKg)
        stat("PRs", "\(summary.prCount)", delta: nil, tint: summary.prCount > 0 ? Color.onyx.record : nil)
    }

    /// ── THE SQUARE MOVED TO `OnyxUI` (§W2 C) ────────────────────────────────
    /// This and `SessionDetailView.cell(_:_:_:sub:…)` were the same object —
    /// micro label, `.display` numeral, a small line under it — drawn twice in
    /// two files, differing in two decisions and two accidents. `OnyxStatCell`
    /// is the one drawing; the two decisions are the parameters below.
    ///
    /// `glass: false` because the reel's card already wears a tile and material
    /// over material reads as a third surface that is not there.
    /// `reserves: false` because there is no second rendering of this card for
    /// its height to stay the same as — §3.6's reservation is about a GRID
    /// redrawn for a different session, which this is not.
    private func stat(_ label: String, _ value: String, delta: Double?, tint: Color? = nil) -> some View {
        OnyxStatCell(
            label, value,
            // Signed, always: "+1,240 kg" and "1,240 kg" are different claims
            // and only one of them is a comparison.
            sub: (delta.map { $0 == 0 ? nil : $0 } ?? nil).map {
                .init("\($0 > 0 ? "+" : "−")\(OnyxFormat.volume(abs($0))) kg",
                      $0 > 0 ? Color.onyx.good : Color.onyx.textSecondary)
            },
            reserves: false, tint: tint, glass: false
        )
    }

    /// The two best lifts of the week, side by side and labelled differently.
    ///
    /// ── WHY BOTH, AND WHY IN ONE CARD ───────────────────────────────────────
    /// `topSet` is the heaviest thing picked up — a fact. `bestE1rm` is the best
    /// estimated max — an inference off a rep count. They disagree constantly:
    /// 100 kg × 3 is the heaviest set of a week whose best estimate came from
    /// 85 kg × 10. Showing one of them under a label that could mean either is
    /// how "my heaviest lift" comes to name a set nobody performed.
    ///
    /// One card and not two, because at 375 pt two full-width hero cards put the
    /// ring below the fold — and the ring is the half of the reel that cannot be
    /// read anywhere else in the app.
    @ViewBuilder
    private var bestsCard: some View {
        if summary.topSet != nil || summary.bestE1rm != nil {
            // ── NOT `ViewThatFits`, WHICH COULD NEVER HAVE STACKED ──────────
            // It was one until W1b measured it. `bestCell` ends in
            // `.frame(maxWidth: .infinity)`, which makes the HStack's ideal
            // width flexible — so `ViewThatFits` is told the row fits any width
            // and takes the first candidate at every size, leaving the VStack
            // branch dead. The two cells never stacked at AX5 and no screenshot
            // could show it, because the container reported success.
            //
            // This is the same trap W4 hit, and the fix is the same one every
            // other collapse in this app already uses: ask the TYPE SIZE, which
            // is the actual question, rather than asking a layout container to
            // infer it from a width its children have declared elastic.
            let cells = Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: OnyxSpace.m) { bestCells }
                } else {
                    HStack(alignment: .top, spacing: OnyxSpace.m) { bestCells }
                }
            }
            cells
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OnyxSpace.l)
                .background(alignment: .top) {
                    // The heaviest set's split colours the card, as it did when
                    // this was the heaviest set's own card.
                    LinearGradient(
                        colors: [Color.onyx.day(summary.topSet?.dayKey ?? "").opacity(0.22), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 72)
                }
                .onyxGlass(.tile)
        }
    }

    @ViewBuilder
    private var bestCells: some View {
        if let top = summary.topSet {
            bestCell(
                "HEAVIEST SET", top.name,
                "\(OnyxFormat.kg(top.weightKg)) kg × \(jsIntegerString(top.reps))",
                change: nil
            )
        }
        if let best = summary.bestE1rm, let e1rm = best.e1rm {
            bestCell(
                "BEST e1RM", best.name,
                "\(OnyxFormat.kg(jsRound1(e1rm))) kg est.",
                change: best.change
            )
        }
    }

    private func bestCell(
        _ label: String, _ name: String, _ detail: String, change: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            Text(label).onyxMicro()
            Text(name)
                .onyxType(.secondary).fontWeight(.semibold)
                .foregroundStyle(Color.onyx.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.8)
            Text(detail)
                .onyxType(.body).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let change, abs(change) > WeeklyWrap.regressionThreshold {
                Text("\(change > 0 ? "+" : "−")\(jsIntegerString(jsRound(abs(change) * 100)))% vs last week")
                    .onyxType(.micro).onyxNumeral()
                    .foregroundStyle(change > 0 ? Color.onyx.good : Color.onyx.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Where the week's work landed, and which day carried most of it.
    @ViewBuilder
    private var ringCard: some View {
        if let muscle = summary.muscle, muscle.doneSets > 0 {
            VStack(alignment: .leading, spacing: OnyxSpace.m) {
                Text("WHERE THE WORK WENT").onyxMicro()
                WeeklyMuscleRing(summary: muscle, showLegend: showsLegend) {
                    onNeedsHeight()
                }
                if let session = summary.topSession, session.volumeKg > 0 {
                    Label(
                        "Biggest session · \(sessionLabel(session)) · \(OnyxFormat.volume(session.volumeKg)) kg",
                        systemImage: "flame"
                    )
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
                    .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OnyxSpace.l)
            .onyxGlass(.tile)
        }
    }

    /// The athlete's own word for the split — resolved here rather than stored,
    /// precisely so a renamed programme renames this too.
    ///
    /// `SessionAnalysis.dayLabel` and not `program.day(key:)?.label ?? key`: the
    /// helper refuses an empty key and tidies one the program does not know
    /// (a Onyx-4 or PPL session) into "Legs A" rather than leaking `legs_a`.
    /// A finished session CAN carry a null `day_key`, and the naive version
    /// rendered that as "Biggest session ·  · 9,715 kg". The date is the
    /// fallback, because a day with no name still happened on a Tuesday.
    private func sessionLabel(_ session: WeeklyWrap.TopSession) -> String {
        SessionAnalysis.dayLabel(session.dayKey, in: program)
            ?? Swap.shortDayLabel(session.date)
    }

    // MARK: - The lists

    /// Three rows, and a count of what is not being shown.
    ///
    /// Three and not five: the reel above has already answered how the week
    /// went, and this is the follow-up question — which lifts moved. A reader
    /// who wants the fourth wants all of them, and that is what the disclosure
    /// under it is for.
    @ViewBuilder
    private var topThree: some View {
        let progressions = summary.progressions
        if !progressions.isEmpty {
            movementList(
                "Progressed", Array(progressions.prefix(3)),
                tone: .good, symbol: "arrow.up.right"
            )
        }
    }

    /// Everything, unabridged — the screen this one replaced, demoted.
    ///
    /// Nothing was cut and one thing was added. The three lists that used to be
    /// the whole screen are the same `movementList` calls in the same order,
    /// simply no longer the first thing the reader meets — and a fourth joins
    /// them, the movements that HELD, which the old screen filed nowhere and
    /// therefore never showed at all.
    @ViewBuilder
    private var breakdown: some View {
        let hidden = summary.movements.count - min(3, summary.progressions.count)
        if hidden > 0 {
            DisclosureGroup(isExpanded: $breakdownOpen) {
                VStack(alignment: .leading, spacing: OnyxSpace.l) {
                    movementList("Progressed", summary.progressions, tone: .good, symbol: "arrow.up.right")
                    movementList("Eased off", summary.deloaded, tone: .textSecondary, symbol: "moon.zzz")
                    movementList("Regressed", summary.regressions, tone: .danger, symbol: "arrow.down.right")
                    movementList("Held", summary.movements(.held), tone: .textSecondary, symbol: "equal")
                }
                .padding(.top, OnyxSpace.m)
            } label: {
                // "+3 more" only reads as more when something is shown above
                // it. A week where nothing progressed shows no rows at all, and
                // there the honest word is "all".
                Label(breakdownLabel, systemImage: "list.bullet")
                .onyxType(.caption).fontWeight(.semibold)
                .foregroundStyle(OnyxDomain.train.accent)
                .frame(minHeight: 44)
            }
            .tint(OnyxDomain.train.accent)
            .accessibilityHint("Shows every movement of the week, with its change")
        }
    }

    private var breakdownLabel: String {
        if breakdownOpen { return "Hide the full week" }
        let shown = min(3, summary.progressions.count)
        let total = summary.movements.count
        if shown == 0 { return "See all \(total) movement\(total == 1 ? "" : "s")" }
        let hidden = total - shown
        return "+\(hidden) more movement\(hidden == 1 ? "" : "s")"
    }

    /// An empty list draws nothing. A "Regressed — none" heading is a heading
    /// that makes the reader check a thing that did not happen.
    @ViewBuilder
    private func movementList(
        _ title: String, _ movements: [WeeklyWrap.Movement], tone: OnyxTone, symbol: String
    ) -> some View {
        if !movements.isEmpty {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                Label(title.uppercased(), systemImage: symbol)
                    .onyxMicro()
                    .foregroundStyle(tone.color)
                ForEach(movements) { movement in
                    HStack(spacing: OnyxSpace.s) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(movement.name)
                                .onyxType(.secondary)
                                .foregroundStyle(Color.onyx.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Text("\(OnyxFormat.kg(movement.weightKg)) kg × \(jsIntegerString(movement.reps))")
                                .onyxType(.micro).onyxNumeral()
                                .foregroundStyle(Color.onyx.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let change = movement.change {
                            Text("\(change > 0 ? "+" : "−")\(jsIntegerString(jsRound(abs(change) * 100)))%")
                                .onyxType(.caption).onyxNumeral()
                                .foregroundStyle(tone.color)
                        }
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

    /// The four tones this screen uses, named rather than passed as colours, so
    /// a list cannot be drawn in a hue the token table does not sanction — gold
    /// in particular, which §3.2 reserves for a personal record.
    enum OnyxTone {
        case good, danger, textSecondary

        var color: Color {
            switch self {
            case .good: Color.onyx.good
            case .danger: Color.onyx.danger
            case .textSecondary: Color.onyx.textSecondary
            }
        }
    }

    // MARK: - Sharing

    private var shareSection: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            Toggle(isOn: $showBodyweight) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Include bodyweight").onyxType(.secondary)
                    Text("Off by default. The card is going somewhere this app cannot see.")
                        .onyxType(.micro)
                        .foregroundStyle(Color.onyx.textTertiary)
                }
            }
            .tint(OnyxDomain.train.accent)

            if let card {
                ShareLink(
                    item: card,
                    preview: SharePreview(title ?? Self.title(summary), image: card)
                ) {
                    Label("Share this week", systemImage: "square.and.arrow.up")
                        .onyxType(.secondary).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .onyxGlass(.row)
                }
                .onyxPress(scale: 0.98)
            }
        }
        .padding(OnyxSpace.l)
        .onyxGlass(.tile)
        // On the SECTION and not on the ScrollView, which is what makes the
        // `LazyVStack` above worth having: the render happens when the reader
        // scrolls to the control, not in the turn that presents the sheet.
        //
        // `task(id:)` and not `onChange`: it also fires on appear, so the card
        // exists before the first tap rather than one render after it.
        .task(id: showBodyweight) {
            guard renderedFor != showBodyweight else { return }
            // Yield first. `render()` is synchronous and lays out and
            // rasterises a 540 × 960 view at `displayScale` — roughly 18 MB —
            // on the main actor, and without this it does so in the same turn
            // as the scroll that revealed it.
            await Task.yield()
            guard !Task.isCancelled else { return }
            card = render()
            renderedFor = showBodyweight
        }
    }

    /// The 9:16 card, rendered off-screen.
    ///
    /// `ImageRenderer` and not a screenshot: this one IS a flat composition —
    /// no material, no blur, nothing the render server has to composite — so
    /// the off-screen pass is the truth here, unlike the review loop, where it
    /// would photograph the layout and lie about the look.
    ///
    /// A SwiftUI `Image` and not a `UIImage`: `Image` is `Transferable`, which
    /// is what `ShareLink` wants. Wrapping a `UIImage` in a
    /// `UIViewControllerRepresentable` around `UIActivityViewController` also
    /// works and does not survive strict concurrency — `[Any]` is not
    /// `Sendable`, and a conformance written to get one call site past the
    /// compiler is the wrong half of this trade.
    @MainActor
    private func render() -> Image? {
        let renderer = ImageRenderer(
            content: WeeklyShareCard(summary: summary, program: program, showBodyweight: showBodyweight)
        )
        renderer.scale = displayScale
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}
