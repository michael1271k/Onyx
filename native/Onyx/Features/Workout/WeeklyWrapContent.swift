import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// The reel — the middle of the weekly report.
///
/// ── IT WAS A SHEET'S CONTENT AND THE SHEET IS GONE (W4) ─────────────────────
/// W6 split this out of `WeeklyWrapView` so a Train-tab row could expand into
/// it inline: the chrome — a `NavigationStack`, a `ScrollView`, two detents —
/// stayed on the sheet and everything that draws a figure moved here. W4 took
/// the argument to its conclusion and deleted the sheet. A week is a PLACE now,
/// pushed by `WeeklyReportView`, and this is the block of it that reports how
/// the training went.
///
/// Three things went with the sheet, and all three were the sheet's:
///
///  · `showsLegend` — the ring's legend only fitted at `.large`, so it was
///    answered from a detent. There is no ring (the founder's words: "destroy
///    the ugly Where-the-work-went ring") and no detent.
///  · `onNeedsHeight` — a page is already at its full height. Opening the
///    breakdown grows the scroll view, which is what a scroll view is for.
///  · `ringCard` — deleted with `WeeklyMuscleRing`. Where the week's work went
///    is the Recovery and Training rails at the head of the page and the
///    movement breakdown below; a part-to-whole donut of sixteen landmarks was
///    a third answer to a question the page now asks twice.
struct WeeklyWrapContent: View {
    let summary: WeeklyWrap.Summary
    let program: Program

    /// Every movement of the week. Closed by default; opening it grows the
    /// page, which is what a scroll view does on its own — the `onNeedsHeight`
    /// hook that raised a sheet went with the sheet (W4).
    @State private var breakdownOpen = false

    @Environment(\.dynamicTypeSize) private var typeSize

    /// `Week 5` — the PROGRAMME's own counter, answered by the builder.
    ///
    /// ── AND WHY THE DATE IS STILL THE FALLBACK (§W3) ────────────────────────
    /// It was the only name this view could derive, because a `Summary` carried
    /// no phase table and no anchor — so the This-week tile, History, the Today
    /// tab and the Past Weeks shelf all opened one week under `Week of Sun 16
    /// Aug` while every OTHER surface in the app called it `Week 5`. The
    /// builder names it now (`Summary.label`); this line is what a summary
    /// assembled by hand in a preview or a test still gets.
    static func title(_ summary: WeeklyWrap.Summary) -> String {
        summary.label ?? "Week of \(Swap.shortDayLabel(summary.weekStart))"
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
            topThree
            breakdown
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
}


/// The card that leaves the phone — the LAST thing on the report.
///
/// ── WHY IT IS ITS OWN VIEW NOW (W4) ─────────────────────────────────────────
/// It was the final block of `WeeklyWrapContent`, which was the whole of the
/// sheet. The report puts four more sections under the reel, so leaving it
/// there would have put "Share this week" in the MIDDLE of the page, above the
/// macros and the weigh-in — a terminal action with a document after it, which
/// reads as the end of one screen and the start of another.
///
/// Nothing inside it changed. The render is still lazy, still keyed on the
/// toggle, and still the reason the page's stack is a `LazyVStack`: the control
/// is below the fold by construction, so the 540 × 960 rasterise happens when a
/// reader scrolls to it and not in the turn that pushes the screen.
struct WeeklyShareSection: View {
    let summary: WeeklyWrap.Summary
    let program: Program

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
    /// Which toggle state `card` was rendered for. Without this every visit
    /// pays the 18 MB rasterise again for a card nothing asked to change.
    @State private var renderedFor: Bool?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
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
                    preview: SharePreview(WeeklyWrapContent.title(summary), image: card)
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
