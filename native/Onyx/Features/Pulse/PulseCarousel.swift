import SwiftUI
import OnyxUI
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// THE SELF-REPORTS, SIDE BY SIDE (founder decision 7).
//
// Fatigue and the stress log were 44 pt rows in the section at the bottom of
// Pulse, each stating an answer and opening a sheet. They are the questions
// this screen ASKS — everything else on it is a measurement something else
// took — and they were the last thing on it, under a body map and five doors,
// because a row is what you make a thing when you have run out of screen.
//
// One page each, swiped between. A page is a card with room for the answer AND
// the verb, which is what turns a reading you look at into a reading you give.
// The peek on the right edge is the whole navigation affordance: a pager that
// looks like a single card is a pager nobody discovers.
//
// ── TWO PAGES SINCE W3, NOT THREE ───────────────────────────────────────────
// Soreness left. It was the one page whose verb was a DOOR rather than an
// answer — `SorenessCard` deliberately never drew the figure, because the atlas
// is a control and a control shrunk into a third of a pager is neither readable
// nor tappable — so a whole page was spent restating a list the square grid
// below now states in a quarter of the space. The rating itself never moved:
// the severity popover has always lived on the map (`DomsTile`), which is what
// `SorenessSheet` opens onto.
//
// ── WHY A NATIVE `viewAligned` SCROLL AND NOT A HAND-ROLLED PAGER ───────────
// `SmartStackView.swift:33-60` records what a hand-rolled pager costs on the
// dashboard, and that one only had to fight a vertical `ScrollView`. This one
// sits inside a vertical `List`: the axes are perpendicular, UIKit hit-tests
// perpendicular scroll views cleanly, and `.scrollTargetBehavior(.viewAligned)`
// is the system's own paging — which brings the rubber band, the deceleration
// curve and the VoiceOver page semantics for nothing.
// ─────────────────────────────────────────────────────────────────────────────

/// Which page is showing. Held by `DayScreen` rather than by the carousel, so
/// a `List` cell recycle cannot reset it — see `PulseCarousel`.
enum PulsePage: String, CaseIterable, Identifiable, Hashable {
    case fatigue, stress
    var id: String { rawValue }

    /// What VoiceOver calls the page, and what the dots announce.
    var title: String {
        switch self {
        case .fatigue: "Fatigue"
        case .stress:  "Stress log"
        }
    }
}

/// One page of the carousel: a header, an answer, and the verb that changes it.
///
/// ── WHY NOT `DayTile` ───────────────────────────────────────────────────────
/// `DayTile` has no height contract, which is correct for a tile that owns a
/// full-width row and wrong for one of two pages that have to agree. A page
/// shorter than its neighbour makes the carousel's row jump on every swipe,
/// and a `List` row that changes height while a scroll is in flight is a row
/// that fights the scroll. So: one floor, scaled with the type, and the content
/// is pinned to the top of it with the verb at the bottom.
struct PulseCard<Content: View>: View {
    let title: String
    let domain: OnyxDomain
    /// The unit this page is measured in — "3 today", "2 of 3". Nil draws
    /// nothing rather than an empty slot.
    var trailing: String?
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var typeSize

    /// ── HALVED IN W3 (MEASURED) ─────────────────────────────────────────────
    /// 196 was measured from the tallest of THREE pages, and it was a floor in
    /// name only: at shipping type the content of every page — a header, one
    /// capsule row and the 44 pt verb — comes to about 130 pt, so the other 66
    /// were empty glass on all three pages at once, in a carousel that is a
    /// `List` row on a screen budgeted at a screen and a half.
    ///
    /// 116 is the real floor: 18 pt header + 12 + a 32 pt capsule row + 12 +
    /// the 44 pt verb − the padding the frame adds back. The cards still agree
    /// with each other, because an eager `HStack` sizes every child to the
    /// tallest of them whatever their own floors say; what the floor stops is a
    /// page with ONE short line collapsing to 60 pt on the day nothing is
    /// logged. `@ScaledMetric` because every word inside grows with the type and
    /// a fixed floor would clip the verb at xxLarge — the one control the page
    /// exists for.
    @ScaledMetric(relativeTo: .body) private var floor: CGFloat = 116

    /// ── AND CAPPED ──────────────────────────────────────────────────────────
    /// At AX5 the metric scales to ~270 pt, which is taller than either page
    /// actually is there — so the pages went back to being mostly empty glass
    /// and the carousel became most of the screen again. 200 is where the
    /// stress card's two stacked rows, its wrapped header and its wrapped verb
    /// land at AX5; the cap keeps the two agreeing, which is all the floor was
    /// ever for.
    private var cardHeight: CGFloat { min(floor, 200) }

    init(_ title: String, _ domain: OnyxDomain, trailing: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.domain = domain
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.m) {
            // The same `ViewThatFits` escape `DayTile` takes: at AX5 the title
            // and its trailing word are each half a line wide and run into
            // each other.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    OnyxSectionHeader(title, domain)
                    Spacer(minLength: OnyxSpace.s)
                    trailingText
                }
                VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                    OnyxSectionHeader(title, domain)
                    trailingText
                }
            }
            content()
        }
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .topLeading)
        .onyxGlass(.tile)
        .foregroundStyle(Color.onyx.textPrimary)
    }

    @ViewBuilder
    private var trailingText: some View {
        if let trailing {
            Text(trailing)
                .onyxType(.caption).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
                .lineLimit(1)
        }
    }
}

/// The verb every page carries on its face.
///
/// A page in a pager cannot be a button — the whole surface is a pan target —
/// so the action is an explicit control rather than a tap anywhere, which is
/// also what makes the pages read as forms rather than as summaries.
struct PulseCardAction: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: OnyxSpace.s) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.onyx.accent(.recover))
                // ── TWO LINES, BECAUSE THIS IS THE CONTROL ──────────────
                // A page is ~340 pt wide and cannot grow, and at AX5 "Rate
                // fatigue" is wider than that on one line — the first shot read
                // "Rate fa…", which is the one thing on the card that must
                // never be a guess. It wraps rather than truncating.
                Text(title)
                    .onyxType(.body).fontWeight(.semibold)
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.98)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - The pager

/// Two pages and two dots.
///
/// ── WHY `page` IS A BINDING FROM `DayScreen` (MEASURED) ─────────────────────
/// This whole view is one `List` row, and a row scrolled out of the window and
/// back is re-hosted: `onAppear` fires again, `.task` re-runs. What is NOT
/// restored is the inner scroll view's contentOffset — it comes back at zero,
/// showing page one, and the obvious fix of keeping a `@State` selection here
/// does not help, because that state measurably SURVIVES the recycle. Keeping
/// the number was never the problem; restoring the scroll was.
///
/// `.scrollPosition(id:)` is a two-way binding: on the re-layout it applies the
/// binding's current value to the fresh scroll view. So the selection has to
/// outlive the row for the offset to be recoverable at all — which is what
/// holding it in `DayScreen` buys, and it is the only thing that does.
struct PulseCarousel: View {
    let model: DayModel
    @Binding var page: PulsePage?
    let onFatigue: () -> Void
    let onLogStress: () -> Void
    let onBrowseStress: () -> Void

    /// How much of the next page shows. Enough to read as a card edge rather
    /// than as a rendering artefact, and not so much that the page in focus
    /// stops being the page.
    ///
    /// ── THE PEEK IS NOT THE NUMBER YOU SET (MEASURED) ───────────────────────
    /// With gutter `g`, inter-card spacing `s` and a card of `W − 2g − peek`,
    /// the neighbour actually shows `g + peek − s`. So the peek reads as the
    /// number written here ONLY while the spacing equals the gutter — which is
    /// why the stack below is spaced `l` and not `m`, and why changing one
    /// without the other silently moves the edge. Measured at 375 pt: gutter
    /// 16, spacing 12, peek 32 rendered 36.
    private static let peek: CGFloat = 32

    /// The last page the scroll actually settled on.
    ///
    /// ── WHY THE DOTS DO NOT READ `page` DIRECTLY ────────────────────────────
    /// `.scrollPosition(id:)` writes nil back while a drag is between two
    /// pages, so dots drawn off `page ?? .fatigue` light the FIRST dot every
    /// time you swipe from Stress to Soreness — a page indicator that flashes
    /// back to page one on its way to page three. The binding has to stay
    /// Optional and has to stay in `DayScreen`; this is a sticky copy of it,
    /// and only the dots read it.
    @State private var settled: PulsePage = .fatigue

    var body: some View {
        VStack(spacing: OnyxSpace.s) {
            ScrollView(.horizontal) {
                // ── AN EAGER `HStack`, DELIBERATELY ─────────────────────────
                // A `LazyHStack` realises only the first child, which costs two
                // things that are both silent. The row is then sized to page
                // ONE — so the moment a card outgrows `PulseCard`'s floor the
                // List row is shorter than its content and changes height
                // mid-scroll, the exact failure the floor exists to prevent.
                // And an unrealised child is NOT in the accessibility tree, so
                // VoiceOver cannot swipe from page one to page two at all. Two
                // children: laziness buys nothing and costs the gate.
                HStack(spacing: OnyxSpace.l) {
                    ForEach(PulsePage.allCases) { which in
                        card(which)
                            // `containerRelativeFrame` measures the container
                            // AFTER `contentMargins` — 343 of a 375 pt phone,
                            // not 375 (measured; this is the whole reason
                            // `contentMargins` is a separate API from padding).
                            // So the width asked for here is already
                            // `screen − 2·gutter − peek` with no arithmetic.
                            .containerRelativeFrame(.horizontal) { width, _ in
                                max(0, width - Self.peek)
                            }
                            // `.scrollPosition(id:)` reports the id of the
                            // aligned child, so every child needs one. Without
                            // it the binding still reports a page and the
                            // scroll view never moves — the dots and the screen
                            // desync with no warning.
                            .id(which)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, OnyxSpace.l, for: .scrollContent)
            .scrollPosition(id: $page)
            .onChange(of: page) { _, next in
                if let next { settled = next }
            }
            dots
        }
    }

    @ViewBuilder
    private func card(_ which: PulsePage) -> some View {
        switch which {
        case .fatigue:
            FatigueCard(model: model, onRate: onFatigue)
        case .stress:
            StressLogCard(model: model, onLog: onLogStress, onBrowse: onBrowseStress)
        }
    }

    /// Where you are, and the only thing on screen that says there is more than
    /// one page when the peek is cut off by a narrow phone.
    ///
    /// Not a control: a 6 pt dot is a target nobody hits, and the page it would
    /// move to is one swipe away.
    ///
    /// ── AND HIDDEN FROM VOICEOVER ───────────────────────────────────────────
    /// The eager `HStack` above puts both cards in the accessibility tree, so a
    /// reader swipes through the pages directly and VoiceOver scrolls the
    /// carousel to follow. A third element announcing "Page, Stress log" would
    /// then be both redundant and STALE — it tracks the scroll position, not the
    /// focused card, so it names a different page from the one being read. It is
    /// decoration for the eye, and it says so.
    private var dots: some View {
        HStack(spacing: OnyxSpace.xs) {
            ForEach(PulsePage.allCases) { which in
                Circle()
                    .fill(which == settled ? Color.onyx.accent(.recover) : Color.onyx.hairline)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Fatigue

/// How tired you said you were, and the control that says it.
///
/// The row this replaces stated the answer and opened a sheet. The page states
/// the same answer and carries the sheet's door on its face — one page of a
/// pager has the height a 44 pt row never did.
struct FatigueCard: View {
    let model: DayModel
    let onRate: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var day: FatigueDay { model.fatigue }
    private var slots: [FatigueSlot] { model.fatigueSlots }
    private var latest: FatigueReading? { Fatigue.latest(day) }
    private var logged: Int { slots.filter { day[$0] != nil }.count }
    /// The slot the day is asking for now (W10) — before the session, after
    /// it, or the rest day's hour. The verb says it, and the empty dot for it
    /// is drawn in the accent, so the card asks one question at a time.
    private var ask: FatigueSlot { model.fatigueAsk }

    var body: some View {
        PulseCard("Fatigue", .recover, trailing: "\(logged) of \(slots.count)") {
            reading
            slotRow
            // The slack sits ABOVE the verb, not inside the reading: the three
            // pages share a height floor, and a gap between a word and the dots
            // that explain it reads as a missing row.
            Spacer(minLength: 0)
            PulseCardAction(symbol: "battery.50", title: "Rate \(ask.label.lowercased())", action: onRate)
        }
    }

    /// The latest word, and which slot it came from. The WORD is the reading —
    /// nothing on this card is a numeral, because the numeral on this screen
    /// belongs to the stress index and to nothing else.
    @ViewBuilder
    private var reading: some View {
        if let latest, let word = Fatigue.level(latest.level)?.label {
            // At AX5 "Okay" and "Before training" cannot share 340 pt — the
            // first shot read "Okay Before t…", which loses which slot the
            // answer came from. `ViewThatFits` rather than a type-size branch:
            // the deciding fact is whether two words fit, which is a
            // measurement (`FiveWordPicker` states the same rule).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                    Text(word)
                        .onyxType(.secondary).fontWeight(.semibold)
                        .foregroundStyle(Color.onyx.fatigue(latest.level))
                        .lineLimit(1)
                    Text(latest.slot.label)
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    cost
                }
                VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                    HStack(spacing: OnyxSpace.s) {
                        Text(word)
                            .onyxType(.secondary).fontWeight(.semibold)
                            .foregroundStyle(Color.onyx.fatigue(latest.level))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        cost
                    }
                    Text(latest.slot.label)
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(word), \(latest.slot.label)\(costSpoken)")
        } else {
            Text("Not rated")
                .onyxType(.secondary)
                .foregroundStyle(Color.onyx.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One dot per slot the day HAS — three on a training day, three on a rest
    /// day, and they are not the same three (`Fatigue.slotsForDay`). Named,
    /// because a page has the width for the words a 44 pt row did not.
    private var slotRow: some View {
        HStack(spacing: OnyxSpace.s) {
            ForEach(slots, id: \.self) { slot in
                HStack(spacing: OnyxSpace.xs) {
                    Circle()
                        .fill(day[slot] != nil ? Color.onyx.fatigue(day[slot]) : .clear)
                        .strokeBorder(
                            day[slot] != nil ? .clear : (slot == ask ? Color.onyx.accent(.recover) : Color.onyx.textTertiary),
                            lineWidth: slot == ask ? 1.5 : 1
                        )
                        .frame(width: 7, height: 7)
                    // ── THE WORDS GO FIRST AT AX5 ───────────────────────────
                    // Three named dots across 340 pt is 100 pt each, and
                    // "Waking" alone is wider than that at the accessibility
                    // sizes — the first shot read "Wak… Pre Post". The dots
                    // still say how many of the day's slots are answered, the
                    // card's own trailing word says "2 of 3", and the sheet
                    // this opens names every slot in full.
                    if !typeSize.isAccessibilitySize {
                        Text(slot.short)
                            .onyxType(.micro)
                            .foregroundStyle(Color.onyx.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                if slot != slots.last { Spacer(minLength: 0) }
            }
            if typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .accessibilityHidden(true)
    }

    /// What the session cost, `post` − `pre`. Absent on a rest day — a delta
    /// against an unrated slot looks like a measurement and is not one — and
    /// on a training day with ONE end logged it names the end that is missing
    /// instead (W10), so "no cost" and "no cost yet" are not the same blank.
    @ViewBuilder
    private var cost: some View {
        if let delta = Fatigue.delta(day) {
            Text("\(delta >= 0 ? "+" : "")\(delta)")
                .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                .foregroundStyle(delta > 1 ? Color.onyx.record : Color.onyx.textSecondary)
                .padding(.horizontal, OnyxSpace.s)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.onyx.hairline))
        } else if let missing = Fatigue.deltaMissing(day), slots.contains(missing), !typeSize.isAccessibilitySize {
            // Hidden at the accessibility sizes for the reason `slotRow` hides
            // its words: "Exhausted" and "Post not rated" cannot share the row
            // at AX5, and VoiceOver already reads it from `costSpoken`. The
            // `slots` guard: a modern `pre` row written before the day was
            // swapped to rest folds through unchanged, and naming "Post" on a
            // day that has no Post would ask for a slot the sheet cannot offer.
            Text("\(missing.short) not rated")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textTertiary)
                .lineLimit(1)
        }
    }

    private var costSpoken: String {
        if let delta = Fatigue.delta(day) { return ", session cost \(delta >= 0 ? "+" : "")\(delta)" }
        if let missing = Fatigue.deltaMissing(day), slots.contains(missing) { return ", \(missing.label.lowercased()) not rated" }
        return ""
    }
}
