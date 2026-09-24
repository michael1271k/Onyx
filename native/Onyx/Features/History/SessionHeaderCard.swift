import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// Everything three screens say about ONE finished session, as a value.
///
/// ── WHY A VALUE AND NOT A `Page` ────────────────────────────────────────────
/// The session page builds a whole `SessionAnalysis.Page` — the ledger, the PR
/// pass, the split's own line, the session before it — because it draws all of
/// it. The Train tab's done card and the Pulse day want the masthead and
/// nothing else, and a card that took a `Page` would make either screen pay for
/// a full report per session in order to print a date and four capsules.
/// `SessionAnalysis.headers` fills these in one pass for a batch of ids.
struct SessionHeader: Identifiable, Sendable, Equatable {
    let id: String
    /// The programme's own name for the day — "Legs & Core B".
    let label: String
    let dayKey: String?
    /// Position in the whole CAREER, oldest first. Nil for a session that
    /// recorded no work: numbering it would put a gap in every number after it.
    let careerIndex: Int?
    let prCount: Int
    let planLabel: String
    let week: WeekPhase?
    let lever: NutritionLever?
    let maintenance: Bool
    /// `Sat 13 Sep · 18:20`.
    let stamp: String
    /// What the session was FOR, biggest share of the work first.
    let muscles: [LandmarkMuscle]
    /// The six-point heart-rate spark off the telemetry cache (overhaul
    /// W5.3) — empty until the finish prefetch has filled it.
    var hrSpark: [Double] = []
}

extension SessionHeader {
    /// The session page already holds every one of these; this is a field copy,
    /// not a second derivation.
    init(page: SessionAnalysis.Page, label: String) {
        let session = page.report.session
        self.init(
            id: session.id,
            label: label,
            dayKey: session.dayKey,
            careerIndex: page.careerIndex,
            prCount: page.report.prCount,
            planLabel: page.planLabel,
            week: page.week,
            lever: page.lever,
            maintenance: page.maintenance,
            stamp: SessionAnalysis.stamp(date: session.date, startedAt: session.startedAt),
            muscles: page.report.primaryOrder
        )
    }
}

/// The masthead of a finished session: what it was, which one it is, when it
/// happened and what it trained.
///
/// ── ONE HEADER, THREE SCREENS ───────────────────────────────────────────────
/// This was 250 lines of `SessionDetailView`, and the Train tab and the Pulse
/// day each drew a summary of the same session in their own layout — three
/// cards that stated the same facts and disagreed about which ones mattered.
/// A finished session reads the same everywhere now, and a change to the
/// masthead is one edit rather than three that drift.
///
/// The day hue arrives as a wash rather than as a tinted panel — see
/// `sessionDayWash(_:)` at the bottom of this file, which `SessionFallbackCard`
/// also wears so the stand-in and the card differ in content, not in character.
struct SessionHeaderCard: View {
    let header: SessionHeader
    /// The session page's one sentence of opinion. Absent everywhere else: it
    /// introduces the metric grid below it, and there is no grid on a tab card.
    var headline: String?
    /// The Train tab's four numbers — `12 sets · 3,108 kg · 48 min · 2 PRs`.
    /// Nil on the session page, whose metric grid is the next thing down and
    /// says all four with units and deltas.
    var totals: String?
    /// The one figure this screen is about (§W2 A).
    ///
    /// ── AND WHY THE TITLE STEPS DOWN WHEN IT IS HERE ────────────────────────
    /// `OnyxType.hero` says it in as many words: "at most one per screen — a
    /// second hero is two screens in a trench coat". The session page's subject
    /// is the TONNAGE, so on that page the tonnage is the hero and the split's
    /// name is a `display` title over it. On the Train tab there is no hero
    /// figure — the card is one of four things on a page about today — so the
    /// name keeps the role. One card, two screens, one hero each.
    var hero: Hero?
    /// The shared face (overhaul, Lane B's `OnyxMasthead`): when present it
    /// replaces the title row, the hero and `totals` — name · duration ·
    /// tonnage · bpm · records, measured by the face itself.
    var masthead: SessionMasthead? = nil

    /// A labelled figure with its comparison, at the top of the card.
    struct Hero {
        let value: String
        let unit: String
        /// `+1,240 kg`, `level`, `first of this split` — the same sentence the
        /// metric grid's cells carry, in the colour it already means.
        let sub: String
        let subTint: Color
        /// The verdict's own direction mark. Nil below half a kilogram, where
        /// `delta` calls it level and a triangle over a rounding error is noise
        /// with a direction.
        let symbol: String?
    }

    var body: some View {
        if let masthead {
            faced(masthead)
        } else {
            classic
        }
    }

    private func faced(_ masthead: SessionMasthead) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            OnyxMasthead(masthead, accent: Color.onyx.day(header.dayKey))
            // The watch banner's line, under the same face (Lane A request).
            if masthead.hrSpark.count > 1 {
                Sparkline(points: masthead.hrSpark, color: OnyxInk.Fixed.heart)
                    .frame(height: 22)
                    .accessibilityHidden(true)
            }
            planTags
            muscleRow
        }
        .padding(OnyxSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sessionDayWash(header.dayKey)
        .onyxGlass(.tile)
    }

    private var classic: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            // ── ROW 1 · WHICH SESSION THIS IS ──────────────────────────────
            // The name, and the ordinal it holds in the whole career. They are
            // the two halves of one fact and they take the two ends of one
            // line, which is what makes the band read as a masthead rather
            // than as a stack of captions.
            Shoulders(.firstTextBaseline) {
                Text(header.label)
                    .onyxType(hero == nil ? .hero : .display)
                    .foregroundStyle(Color.onyx.dayLabel(header.dayKey))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            } trailing: {
                // A session that recorded nothing carries no number rather
                // than a zero — see `Page.careerIndex`.
                if let index = header.careerIndex {
                    careerNumber(index)
                }
            }
            // ── ROW 1½ · WHAT THE SESSION WEIGHED ──────────────────────────
            // It was the first cell of a 3-up grid under this card, in
            // `.display`, indistinguishable from Duration and Sets beside it —
            // seven equal figures, none of them the answer to "how did that
            // go". It is the answer, so it is the figure.
            if let hero { heroLine(hero) }
            // ── ROW 2 · WHICH PLAN, AND WHEN ───────────────────────────────
            // Calendar facts, both sides: what the programme called this day on
            // the left, what the clock called it on the right.
            Shoulders(.top) {
                planTags
            } trailing: {
                Text(header.stamp)
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // ── ROW 3 · WHAT IT TRAINED ────────────────────────────────────
            muscleRow
            // ── ROW 4 · WHAT IT PRODUCED, OR WHAT IT MEANT ─────────────────
            if let totals {
                Text(totals)
                    .onyxType(.secondary).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            // Under the three rows rather than under the title: those three are
            // the session's IDENTITY and they read as a block, and this is the
            // first line that expresses an opinion. It closes the band
            // immediately above the metric grid it introduces.
            //
            // Set as an aside rather than as a heading: italic, one step down,
            // secondary ink, so it reads as a quiet remark beside the numbers
            // rather than as another label competing with them.
            if let headline {
                Text(headline)
                    .onyxType(.secondary)
                    .italic()
                    .foregroundStyle(Color.onyx.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(OnyxSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sessionDayWash(header.dayKey)
        .onyxGlass(.tile)
    }

    /// The tonnage, its unit and its verdict on one baseline.
    ///
    /// The unit sits BESIDE the number rather than under it, the rule every
    /// `OnyxStatCell` on this page follows: a unit on its own line has left its
    /// number. The verdict trails both, in the ink a delta already means —
    /// `good` for more work, secondary for less, tertiary for no comparison.
    private func heroLine(_ hero: Hero) -> some View {
        // `Shoulders` and not a bare `HStack`: at AX5 a 28 pt figure, its unit
        // and a signed comparison cannot share a line at any scale factor, and
        // the first cut of this row proved it — `▲ 5,398.0 ..  ...`, with the
        // unit and the whole verdict truncated to ellipses. The shared
        // primitive already makes that break a BRANCH rather than a measure,
        // for exactly this failure (see its own header).
        Shoulders(.firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.xs) {
                if let symbol = hero.symbol {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .onyxType(.caption)
                        .foregroundStyle(hero.subTint)
                        .accessibilityHidden(true)
                }
                Text(hero.value)
                    // `.onyxNumeral()` carries `contentTransition(.numericText())`,
                    // so the figure counts up as the page arrives rather than
                    // snapping into place.
                    .onyxType(.hero).onyxNumeral()
                    // ── THE FIGURE IS NEVER THE VERDICT'S COLOUR ────────
                    // Tinting it `good` on a heavier session and
                    // `textSecondary` on a lighter one would grey out the one
                    // number the page is about on exactly the sessions worth
                    // reading twice. The direction is the arrow's job and the
                    // magnitude is the line's; the subject keeps primary ink.
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
                Text(hero.unit)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineLimit(1)
            }
        } trailing: {
            Text(hero.sub)
                .onyxType(.caption).onyxNumeral()
                .foregroundStyle(hero.subTint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Volume, \(hero.value) \(hero.unit), \(hero.sub)")
    }

    /// The session's place in the whole career — `#45` — and, when it produced
    /// a record, the one colour in this app that says so.
    ///
    /// ── WHY GOLD HERE DOES NOT SPEND GOLD ───────────────────────────────────
    /// `Color.onyx.record` means "personal record" app-wide and is the only
    /// fifth hue §3.2 allows, so it is never decoration. This is not
    /// decoration: the number turns gold on exactly the condition the trophy
    /// turns gold on one screen down — `prCount > 0` — so the masthead states
    /// the same fact the ledger proves, and a session with no records keeps the
    /// split's own colour and says nothing.
    ///
    /// ── AND WHY THE GLOW IS AFFORDABLE HERE AND NOWHERE ELSE ────────────────
    /// A `.shadow` is an offscreen pass per frame, which is why the gold on a
    /// set badge is on the GLYPH and never on the row: the ledger recycles its
    /// rows under a scrolling thumb at 120 Hz. This band is drawn once, at the
    /// top of a page or a tab, and never inside a recycling list — so the one
    /// place a soft bloom costs nothing is the one place a whole session's
    /// achievement is being named.
    private func careerNumber(_ index: Int) -> some View {
        let earned = header.prCount > 0
        let tint = earned ? Color.onyx.record : Color.onyx.dayLabel(header.dayKey)
        return Text("#\(index)")
            .onyxType(.display).onyxNumeral().fontWeight(.semibold)
            .foregroundStyle(tint)
            .lineLimit(1)
            .shadow(color: earned ? Color.onyx.record.opacity(0.5) : .clear,
                    radius: earned ? 7 : 0)
            .accessibilityLabel(earned ? "Session \(index), set records" : "Session \(index)")
    }

    /// The programme's own words for this day — plan, phase week, lever — each
    /// resolved for the session's OWN date.
    ///
    /// ── ROW 2 IS CALENDAR, ROW 3 IS ANATOMY ─────────────────────────────────
    /// These used to share one stack with the muscle capsules, which put two
    /// unrelated vocabularies in one block: `Hypertrophy · Cut W7 · Lever 2` is
    /// what the plan CALLED this day, and `Quads · Glutes` is what the body
    /// DID. A reader scanning for either had to read both. They are two rows
    /// now, and each has a right-hand shoulder of its own.
    private var planTags: some View {
        // Wrapping, not an `HStack`: at AX5 three capsules on one line become
        // three vertical blobs one letter wide.
        FlowRow(spacing: OnyxSpace.xs) {
            tag(header.planLabel, .train)
            if let week = header.week {
                // `.short` is already "Cut W7" — the number is in it.
                tag(week.short, .fuel)
            }
            if header.maintenance {
                tag("Maintenance", .recover)
            } else if let lever = header.lever {
                tag(lever.label, .fuel)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// What the session was FOR, biggest share of the work first.
    ///
    /// ── PRIMARIES ONLY, AND WHY THE CAP WAS THE WRONG TOOL ──────────────────
    /// A "top four" here is how the Abs/core tag went missing: core work is
    /// genuine and is almost always the SMALLEST share of a session, so any cap
    /// drops exactly the tag that fixes. The fix is not a bigger cap, it is
    /// asking a different question — a flat capsule row carries no share, so
    /// assistance printed here looked exactly like the muscles the session was
    /// FOR, and an upper day read `Chest · Lats · Triceps · Biceps · Front
    /// delts · Rear delts · Abs`, seven capsules over two lines, of which two
    /// were the point. The Muscle focus card on the session page still draws
    /// every one of them, with its share, where a small number can say "this
    /// came along".
    ///
    /// ── AND WHY NOTHING IS SORTED HERE ──────────────────────────────────────
    /// `muscles` arrives ranked by raw working sets with tonnage breaking the
    /// ties, built in the loader off the main actor. A `body` that sorted would
    /// be re-sorting on every redraw of a row a scroll view recycles.
    private var muscleRow: some View {
        MuscleTagRow(muscles: header.muscles)
    }

    private func tag(_ text: String, _ domain: OnyxDomain) -> some View {
        Text(text)
            .onyxType(.micro)
            .foregroundStyle(domain.accent)
            .padding(.horizontal, OnyxSpace.s)
            .padding(.vertical, 3)
            .background(domain.accent.opacity(0.16), in: .capsule)
    }
}

// MARK: - The three things the stand-in and the cardio card borrow (W5)

/// Two things at the two ends of one line — until the type size says a line
/// cannot hold two of anything.
///
/// ── WHY THE BREAK IS A BRANCH AND NOT A `ViewThatFits` ──────────────────────
/// `ViewThatFits` cannot stack a flexible child (memory: `w1b-week-detail`) and
/// a `Spacer` cannot wrap — which is how the ledger header once had its chips
/// and its prescription dividing a 375 pt line four ways. At the accessibility
/// sizes there is no arrangement of two long strings that fits across, so the
/// second one takes its own line and nothing is measured at all.
///
/// Shared since W5: the cardio card's bout puts its kind on one shoulder and
/// its stamp on the other, which is the same line with the same failure at AX5.
struct Shoulders<Leading: View, Trailing: View>: View {
    let alignment: VerticalAlignment
    let leading: () -> Leading
    let trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    init(
        _ alignment: VerticalAlignment = .firstTextBaseline,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.alignment = alignment
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                leading()
                trailing()
            }
        } else {
            HStack(alignment: alignment, spacing: OnyxSpace.s) {
                leading()
                Spacer(minLength: OnyxSpace.xs)
                trailing()
            }
        }
    }
}

/// What a session was FOR, as capsules — the muscle's OWN hue (W3): sixteen
/// muscles, one colour each, so the band, the ramp, the legend and the atlas
/// figure all call one muscle by one colour, and a tag keeps its colour when
/// the session's ranking changes underneath it.
///
/// Named rather than numbered: the share is the Muscle focus card's job, and a
/// capsule carrying "Quads 6.5" would put the session's longest number in its
/// smallest type.
///
/// ── WHY IT LEFT THE CARD (W5) ───────────────────────────────────────────────
/// `SessionFallbackCard` draws the same capsules while this card's career-wide
/// read is in flight, and a second drawing of a muscle capsule is how a hue or
/// a padding comes to differ between the card and the card that stands in for
/// it — for the half-second a reader is looking at exactly that difference.
/// One row, two callers.
struct MuscleTagRow: View {
    let muscles: [LandmarkMuscle]

    var body: some View {
        // Wrapping, not an `HStack`: at AX5 a row of capsules on one line
        // becomes a row of vertical blobs one letter wide.
        FlowRow(spacing: OnyxSpace.xs) {
            ForEach(muscles, id: \.self) { muscle in
                let tint = Color.onyx.muscle(muscle)
                Text(muscle.displayName)
                    .onyxType(.micro)
                    .foregroundStyle(tint)
                    .padding(.horizontal, OnyxSpace.s)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.16), in: .capsule)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The masthead's day wash: 22 %→0 of the split's hue over the top 72 pt.
    ///
    /// ── WHY A WASH AND NOT A COLOURED CARD ──────────────────────────────────
    /// A tinted panel makes the glass under it read as a different material and
    /// puts a hard edge across the top of the screen — the "gradient header"
    /// look the whole mandate exists to avoid. A 22 %→0 wash behind transparent
    /// content says the same thing (this is a leg day) and leaves the surface
    /// alone. The title carries the same hue at full strength, which is where
    /// the colour is actually legible.
    ///
    /// Applied INSIDE `onyxGlass(.tile)`, always: the glass clips it to the
    /// card's own corner, and a wash outside that clip paints a rectangle with
    /// square corners behind a rounded card.
    ///
    /// Not `onyxMuscleWash` (OnyxUI), which is a different fact: that one is
    /// 6 %→2 % of a MOVEMENT's family over a whole card, plus a 3 pt rail. This
    /// is a session's DAY, at the head of the card and nowhere else.
    func sessionDayWash(_ dayKey: String?) -> some View {
        onyxTopWash(Color.onyx.day(dayKey))
    }

    /// The masthead wash with the hue named by the caller — the same 22 %→0
    /// over the same 72 pt, and deliberately not a second gradient.
    ///
    /// A week banner in the Library is the same object as a session masthead
    /// (hero label, tags, totals, a wash at the head of a tile) wearing a
    /// PHASE's colour instead of a split's, and a copied `LinearGradient` is
    /// how the two come to differ by two points or four percent for the half
    /// second a reader is looking at exactly that difference. One wash, two
    /// callers, one number to change.
    func onyxTopWash(_ tint: Color) -> some View {
        background(alignment: .top) {
            LinearGradient(
                colors: [tint.opacity(0.22), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 72)
        }
    }
}
