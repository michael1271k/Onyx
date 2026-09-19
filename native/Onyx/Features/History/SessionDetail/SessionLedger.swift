import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// THE LEDGER — one movement's masthead, and one performed set.
//
// Cut out of `SessionDetailView.swift` in W11 with nothing changed but the two
// access levels the cut itself forced (`LedgerHeader` was `private`, which in
// Swift means file-scoped, and the page is no longer in this file). The page
// that presents these two views is `SessionDetailView.swift` beside this one;
// the split's chart is `SessionCharts.swift`.
//
// ── WHY THESE TWO SHARE A FILE AND THE PAGE DOES NOT ────────────────────────
// They are one table. `LedgerHeader` decides the columns for a card
// (`SetRow.SetLayout`) and every row under it obeys — that agreement is by
// construction rather than by two functions arriving at the same answer, and
// it is the sort of agreement that only survives while the two are read
// together. `OnyxLedgerRowFloor` is the height both header rows stand on and
// `Mover` is what the primary chip prints, so both come with them.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - One movement's masthead

/// The floor both header rows stand on — `MetaTagRow.Capsule`'s own
/// `minHeight`, spelled once.
///
/// It is what makes the swap honest. Row 2 holds readings in one state and
/// muscle names in the other, and a row whose height is set by its CONTENT
/// would move the card — and everything under it — every time the chip is
/// tapped. It is also what keeps a movement with no readings at all (an
/// unrated bodyweight hold, a bout with no `cardio_logs` row behind it) from
/// drawing a row of zero height and collapsing the card by a line.
enum OnyxLedgerRowFloor {
    static let height: CGFloat = 24
}

private extension View {
    func rowFloor() -> some View {
        frame(maxWidth: .infinity, minHeight: OnyxLedgerRowFloor.height, alignment: .leading)
            .accessibilityElement(children: .contain)
    }
}


/// Primary or assisting, by name — `MuscleMap`'s answer for one movement.
struct Mover {
    let name: String
    let primary: Bool
}

/// A ledger card's heading: the movement, and two rows that never move.
///
/// ── WHY IT IS TWO FIXED ROWS AND NOT ONE FLOW (§W2 E) ───────────────────────
/// It was a single `FlowRow` holding the muscle chips and every reading, so the
/// wrap point was wherever the text size put it: `RPE 8.0` opened line two on
/// one card and closed line one on the next, three rows of chips on a
/// three-mover movement, and ~74 pt of wrapped capsules above ~36 pt per set —
/// a screen of scrolling per movement.
///
/// Now the register decides the row and the row never changes:
///
///   row 1 · the primary muscle · how it went · what was asked · the cue
///   row 2 · what it produced — tonnage, top set, effort
///
/// ── AND WHY ROW 2 IS A SWAP RATHER THAN A DISCLOSURE ────────────────────────
/// The assisting muscles are worth having and are not worth a row: they were
/// two more chips on the line the readings needed, and on a three-mover
/// movement they took the line on their own. A disclosure that ADDS a row makes
/// the card grow under the thumb that opened it and pushes the sets out of
/// frame — which is the shape this whole wave exists to end. So tapping the
/// primary chip replaces row 2 IN PLACE: the assists arrive where the readings
/// were, the card's height does not move, and tapping again puts them back.
/// `+2` on the chip is the affordance and the count at once.
struct LedgerHeader: View {
    let name: String
    let window: String?
    let spark: [Double]
    let family: Color
    let primary: [Mover]
    let secondary: [Mover]
    let brief: [MetaTagRow.Tag]
    let results: [MetaTagRow.Tag]
    /// See `SessionDetailView.startWithAssists`.
    var seededOpen = false
    /// Opens the movement's est-1RM chart. Nil where there is not enough
    /// history for a chart to say more than the sparkline does — the header
    /// then draws the trail as it always did, with no gesture on it, because an
    /// affordance that does nothing is worse than no affordance.
    var onTrail: (() -> Void)?

    /// Whether row 2 is showing the assists instead of the readings. Per CARD,
    /// which is why this view exists at all: the header used to be a function
    /// on the page, and a page-level dictionary keyed by movement would be the
    /// same state with a lookup in front of it.
    @State private var showingSecondaries = false
    @Environment(\.dynamicTypeSize) private var typeSize


    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            title
            // ── THE TRAIL EARNS ITS WIDTH ON THE ROW BELOW THE NAME (§W2 G) ─
            // It was 40×16 on the TITLE line, competing with the movement's
            // own name for a 375 pt line — so the name lost 44 pt to a graphic
            // with no label. On the brief's row it is beside four capsules that
            // are none of them the subject, and 56 pt is where eight sessions
            // stop reading as one wobble. The height never moves: 16 pt inside
            // a 24 pt row costs nothing, which is why it never cost anything.
            //
            // `HStack` outside the flow and not an item inside it: a `FlowRow`
            // places subviews in order and would wrap the trail to a second
            // line the moment the brief filled the first, which is a sparkline
            // alone under four capsules.
            HStack(alignment: .center, spacing: OnyxSpace.s) {
                briefRow
                if spark.count >= 2, !typeSize.isAccessibilitySize {
                    // `family`, not the domain accent: the domain fold
                    // collapses sixteen landmarks onto four hues, so a chest
                    // day and a shoulder day drew the same blue trail beside
                    // two differently-coloured cards.
                    trail
                }
            }
            resultsRow
                .animation(OnyxMotion.move, value: showingSecondaries)
                .task { if seededOpen { showingSecondaries = true } }
        }
        .padding(.horizontal, OnyxSpace.l)
        .padding(.vertical, OnyxSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        // ── A WASH IN THE MUSCLE'S OWN HUE, NOT THE DOMAIN'S ───────────────
        // Nothing is drawn here: `onyxMuscleWash` on the CARD covers the header
        // and the rows in a single run and carries the rail the whole length of
        // the movement, which is the only way header and rows can agree on a
        // colour. The band used to paint its own 28 %→4 % gradient and its own
        // 3 pt rail, which is exactly what made it read as a coloured header
        // bolted to a black list rather than as the top of one card.
    }

    /// The 56×16 est-1RM trail, and — since W10 — the way into the chart of it.
    ///
    /// ── WHY IT IS A `Button` AND NOT AN `onTapGesture` ──────────────────────
    /// The sparkline is 56×16 and the target has to be 44 pt tall to be hit at
    /// all, so the gesture needs a shape bigger than the ink. A `Button` gets
    /// `.contentShape` and the press feedback for free, publishes itself to
    /// VoiceOver as a button with a label rather than staying
    /// `accessibilityHidden`, and takes the app's own `.onyxPress`. A bare tap
    /// gesture would need all four spelled out and would still be invisible to
    /// the rotor.
    ///
    /// The graphic itself does not change and neither does the row's height:
    /// the 44 pt target is a `.frame` on the button, and the row it sits in is
    /// already 24 pt of capsules inside a header taller than both.
    @ViewBuilder
    private var trail: some View {
        if let onTrail {
            Button(action: onTrail) {
                sparkline
                    .frame(height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onyxPress()
            .accessibilityLabel("Estimated one rep max trail")
            .accessibilityHint("Opens the chart.")
        } else {
            sparkline.accessibilityHidden(true)
        }
    }

    private var sparkline: some View {
        Sparkline(points: spark, color: family, zeroBased: false)
            .frame(width: 56, height: 16)
    }

    // MARK: - Line 0 · which movement

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
            // ── THE MOVEMENT'S OWN NAME, AT THE SIZE OF A TITLE ────────────
            // It was 13 pt and uppercased by the `List`'s own header style —
            // the same treatment as the word "Cardio" two sections down, which
            // is a heading and not a subject. This card IS the movement.
            Text(name)
                .onyxType(.display)
                .textCase(nil)
                .foregroundStyle(Color.onyx.textPrimary)
                // One line, until one line cannot hold it: at AX5 on a 375 pt
                // phone "Incline DB Press" scaled to its floor and still came
                // out "Incline DB Pr…", and a movement whose name is cut off is
                // a card about nothing.
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            // ── WHAT WAS ASKED OF IT, BESIDE ITS NAME ──────────────────────
            // The window is not a result, it is the movement's brief, so it
            // belongs beside the movement. Deliberately NOT set like the title:
            // one step down, medium weight, in the movement's own hue, so
            // "@ 10–12" reads as metadata attached to the name rather than as
            // part of it. Dropped at the accessibility sizes, where the name
            // alone needs three lines and what the window did with the width
            // left over was render as a lone red ellipsis — it is still said in
            // full by the ceiling capsule on row 1.
            if let window, !typeSize.isAccessibilitySize {
                Text("@ \(window)")
                    .onyxType(.secondary).onyxNumeral()
                    .fontWeight(.medium)
                    .foregroundStyle(family)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("Target \(window)")
            }
            Spacer(minLength: OnyxSpace.xs)
        }
    }

    // MARK: - The two rows

    /// Row 1 · which muscle, and how the movement went against last time.
    private var briefRow: some View {
        FlowRow(spacing: OnyxSpace.xs) {
            if let lead = primary.first { primaryChip(lead) }
            ForEach(brief, id: \.text) { MetaTagRow.Capsule($0) }
        }
        .rowFloor()
    }

    /// Row 2 · what the movement produced — or, once the chip is tapped, what
    /// else it worked.
    ///
    /// ── THE TWO STATES ARE THE SAME OBJECT ON PURPOSE ───────────────────────
    /// A flow of `MetaTagRow.Capsule`s either way, on the same floor. The
    /// assists could have been drawn as CHIPS, in the primary's own shape, and
    /// that is exactly what would have broken the swap: a chip is 17 pt and a
    /// capsule is 24, so the card would have jumped 7 pt every time the muscle
    /// was tapped. The dot is what marks the primary out as the control, and
    /// there is exactly one of those.
    private var resultsRow: some View {
        // ── BOTH STATES, ALWAYS LAID OUT; ONE OF THEM DRAWN ─────────────────
        // A `ZStack` and not an `if`, and this is the whole of the height
        // guarantee. At the default sizes both states are one line and a branch
        // would have been enough. At AX5 every capsule takes a line of its own,
        // so three readings are three lines and two assists are two — and a
        // branch made the card, and everything under it, jump by a line every
        // time the chip was tapped, at exactly the text size where the reader
        // can least afford the page to move.
        //
        // Stacked, the row is as tall as the TALLER state in both of them, so
        // the swap is free at every size and costs a line only where a line was
        // going to be needed anyway. The inactive state is faded rather than
        // removed, which is also what gives `OnyxMotion.move` something to
        // cross-fade; it is taken out of the hit-testing and out of VoiceOver
        // so it is invisible to everything except the layout.
        ZStack(alignment: .topLeading) {
            capsules(results.map { ($0.text, $0) })
                .opacity(showingSecondaries ? 0 : 1)
                .allowsHitTesting(!showingSecondaries)
                .accessibilityHidden(showingSecondaries)
            capsules(secondary.map {
                ($0.name, MetaTagRow.Tag($0.name, tint: family.opacity(0.7)))
            })
                .opacity(showingSecondaries ? 1 : 0)
                .allowsHitTesting(showingSecondaries)
                .accessibilityHidden(!showingSecondaries)
        }
        .rowFloor()
    }

    private func capsules(_ tags: [(id: String, tag: MetaTagRow.Tag)]) -> some View {
        FlowRow(spacing: OnyxSpace.xs) {
            ForEach(tags, id: \.id) { MetaTagRow.Capsule($0.tag) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The chip that is a control

    /// ── ONE HUE, TWO WEIGHTS ────────────────────────────────────────────────
    /// The primary chip wears the movement's own muscle colour — the same
    /// `Color.onyx.muscle` value the card's rule, wash, sparkline family and the
    /// atlas below all take. An assist is the SAME colour at less than full
    /// strength, not a second colour: a distinct hue for "also worked" would be
    /// a fifth accent nobody designed, and the difference the reader needs is
    /// how much this movement is about that muscle, which is a weight.
    private func primaryChip(_ mover: Mover) -> some View {
        Button {
            withAnimation(OnyxMotion.move) { showingSecondaries.toggle() }
        } label: {
            HStack(spacing: OnyxSpace.xs) {
                Circle()
                    .fill(family)
                    .frame(width: 6, height: 6)
                Text(mover.name)
                    // `.onyxType(.micro)`, never `onyxMicro()`: this is a name,
                    // and the register role would set "Upper back" as UPPER BACK.
                    .onyxType(.micro)
                    .textCase(nil)
                    .foregroundStyle(family)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !secondary.isEmpty {
                    // `.caption` and not `.micro`, and this is the token's own
                    // rule rather than a taste: `micro` is "a register label —
                    // uppercase, tracked out, NEVER carrying a number". `+2` is
                    // a number, so it takes the next role up and sits a step
                    // larger than the name beside it, which is also what makes
                    // the affordance findable.
                    Text(showingSecondaries ? "×" : "+\(secondary.count)")
                        .onyxType(.caption).onyxNumeral()
                        .foregroundStyle(family.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, OnyxSpace.s)
            .padding(.vertical, OnyxSpace.xs)
            .frame(minHeight: OnyxLedgerRowFloor.height)
            .background(family.opacity(0.16), in: SwiftUI.Capsule())
            // ── 24 pt DRAWN, 44 pt TAPPED ──────────────────────────────────
            // The target floor is 44 and the row is 24, and growing the row to
            // meet it would put 20 pt back on every card this wave just took
            // 20 pt off. So the padding that makes the target is added, the
            // hit shape is taken from it, and the layout is given its height
            // back — the chip draws 24 pt tall inside a 44 pt touch area.
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .padding(.vertical, -10)
        }
        .buttonStyle(.plain)
        // NOT `.disabled()`. A movement with nothing assisting has nothing to
        // swap to, and disabling the button greys its label — so the one chip
        // that says which muscle this card is about came out dimmed, reading as
        // "unavailable" on a fact that is neither missing nor uncertain. The
        // gesture simply does nothing instead, and the chip keeps its ink.
        .allowsHitTesting(!secondary.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mover.name), primary")
        .accessibilityValue(secondary.isEmpty ? "" : "\(secondary.count) assisting")
        .accessibilityHint(secondary.isEmpty ? "" :
            (showingSecondaries ? "Shows this movement's readings" : "Shows the assisting muscles"))
        .accessibilityAddTraits(secondary.isEmpty ? [] : .isButton)
    }
}

// MARK: - The set row

/// One ledger row: the set as performed, the records it won, and the RPE. A
/// unilateral pair is one row.
///
/// ── AND NOTHING FROM ANY OTHER DAY ──────────────────────────────────────────
/// The row used to end with `prev 5kg × 15` — the positionally-matched set from
/// the last time this movement was trained. See `ExerciseReport.rows` for why
/// it is gone: this is the page you land on when you finish a workout, and
/// every row on it is now a set you actually performed today.
struct SetRow: View {
    let row: DetailRow
    let timed: Bool
    /// The movement's muscle hue — what a record row is washed in. Defaulted so
    /// the row keeps working anywhere it is dropped without a family to take.
    var tint: Color = Color.onyx.record
    /// The records this row's set(s) won, with the values they beat. Empty on
    /// an ordinary row, and empty on a record row whose axes had no numeric
    /// bar — the badge still turns gold, and the long press then has nothing
    /// to open, which is why `onInspect` is only armed when this is not.
    var records: [LivePrRecord] = []
    /// Long press on a record row. Nil wherever the row is drawn without a
    /// presenter — the previews, the screenshot harness.
    var onInspect: (([LivePrRecord]) -> Void)?
    /// The same set NUMBER, the last time this movement was trained.
    ///
    /// ── WHY POSITIONAL, AND WHY ONLY HERE ───────────────────────────────────
    /// `SessionDetail.rowsWithPrev` exists and is deliberately not used: it
    /// drops previous sets past this session's count, which makes it wrong for
    /// the movement's totals (`ExerciseReport.rows`' own header). Set-to-set is
    /// the one comparison where position IS the question — "was set 3 heavier
    /// than set 3 last time" — and where having no counterpart is an honest
    /// answer rather than a dropped number: a fourth set added this week simply
    /// carries no arrow.
    ///
    /// Nil on a warm-up (no working ordinal), on a pair (two rows per set, so
    /// the previous session's list does not index by ordinal) and wherever the
    /// movement is new.
    var prev: HistorySet?
    /// What the same ROW was worth last time, in kilograms — a pair folded to
    /// one unit on both sides of the comparison.
    ///
    /// Separate from `prev` and not derived from it: `prev` is one
    /// `HistorySet`, and a pair's counterpart is two. `SessionDetailView`
    /// computes it, because folding the previous session is the card's job and
    /// not the row's. See `SessionDetailView.previousUnitVolume`.
    var prevUnitKg: Double?
    /// This row's 1-based place in its card. Only ever read for a BOUT, which
    /// is stored as a warm-up (that is what keeps five minutes of walking out
    /// of tonnage and out of the PR engine) and therefore carries no working
    /// ordinal to print — see `ordinal`.
    var position: Int = 1
    /// Which columns this movement's card puts its sets in — decided ONCE for
    /// the whole card and handed down. See `SetLayout`.
    var layout: SetLayout = .whole
    /// Whether this CARD has anything to compare against — decided once, the
    /// same way `layout` is, and for the same reason: a first-ever movement
    /// reserving a delta line on every column of every row is a card of
    /// guaranteed blanks. Defaulted true, which is the behaviour every caller
    /// that does not know had before.
    var cardComparable: Bool = true
    /// MEASURED rest before this set, in seconds (`actual_rest_sec`), or nil
    /// where nothing clocked it — which is most rows. See `ExerciseReport.rest`.
    var restSec: Int?
    /// This rest against the one before it on the same card, in seconds. Nil on
    /// the first row of a card, and nil wherever either side was not measured:
    /// a delta against an unknown is not a delta.
    var restDeltaSec: Int?
    /// Screenshot harness only — see `SessionDetailView.holdMargins`.
    var marginHeld = false

    /// The badge's side in the ledger, named because two things depend on it
    /// being the same number: the row's own gutter and the column heads' empty
    /// leading track. A header that measured the badge separately is a header
    /// that drifts off its columns by a point on the next edit.
    static let badgeSide: CGFloat = 28

    /// The `L` / `R` tag's track on a pair sub-line — one bold `micro` glyph.
    ///
    /// The value is `SetColumn.side`'s, and the number is spelled again rather
    /// than imported: that type is `private` to the logger's own card, and this
    /// page is not the place to widen it. What the two share is the reason —
    /// a FIXED track is what makes the two sides' numbers start at the same x,
    /// where an intrinsic one would step the `R` line in by however much wider
    /// the glyph is than the `L`.
    static let sideTrack: CGFloat = 14

    /// The columns one movement's card puts its sets in.
    ///
    /// ── WHY THIS IS A CARD'S DECISION AND NOT A ROW'S ───────────────────────
    /// Columns that each row chose for itself are not columns. A bodyweight
    /// movement has no load to print and would drop its first track, so a card
    /// holding one loaded warm-up and four unloaded working sets would draw two
    /// different tables under one heading. The card asks once, every row
    /// obeys, and the heading is built from the same answer — which is what
    /// makes them line up by construction rather than by two functions
    /// agreeing.
    enum SetLayout: Equatable {
        /// `KG · REPS · RPE` — a plain lifted set.
        case loaded
        /// `REPS · RPE`. The deck drops the `KG` track on a Reverse Crunch for
        /// the same reason: a `0kg` that cannot be anything else is a column
        /// that cannot say anything.
        case unloaded
        /// `MIN · KM · PACE`.
        case cardio
        /// `L 22 × 10` over `R 22 × 9` under one badge, and ONE delta line
        /// under the pair.
        ///
        /// ── WHY A UNILATERAL CARD IS NOT `.whole` ANY MORE ──────────────
        /// It was, and `.whole.comparable` is false, so a movement trained one
        /// arm at a time was the only kind on this page carrying no comparison
        /// at all (F5) — on a card where the reader most wants one, because a
        /// split set is where the two sides drift apart.
        ///
        /// It cannot be three tracks: a pair is SIX numbers, and `KG · REPS ·
        /// RPE` would have to choose which arm each column is about. Two
        /// sub-lines is the shape the logger's own deck already draws a split
        /// set in, down to the `L` / `R` tag in its own fixed track — so a set
        /// looks the same ten seconds after it is logged as it does here.
        ///
        /// A card reaches this layout when ANY of its rows is a pair, and the
        /// rows that are not simply draw their own whole string with the same
        /// reserved line under them. Both shapes are one string and one
        /// verdict, which is what lets them share a card — see `layout(_:)`.
        case pair
        /// One string across the row — a timed hold, or a card whose rows
        /// disagree about their own shape.
        case whole

        /// Whether a set in this table has a counterpart to be measured
        /// against — which is what decides whether the reserved delta line
        /// under each reading is drawn at all.
        ///
        /// A bout never does: it is stored as a warm-up (that is what keeps
        /// five minutes of walking out of tonnage and out of the PR engine), so
        /// it carries no working ordinal to index the previous session by.
        /// Three reserved lines under three readings that can never move is
        /// 36 pt of empty glass on every row of the card — which is why this is
        /// false here rather than merely blank, and why the row centres against
        /// the badge when it is (see `body`).
        ///
        /// `.pair` DOES compare, on the pair's own volume rather than on a
        /// column — see `SetRow.unitDelta` for why six numbers cannot be
        /// summarised by any one of them.
        var comparable: Bool { self != .cardio && self != .whole }

        /// What the heading says over each track. Empty for the two layouts
        /// that draw a string rather than a table, which is how the card knows
        /// not to draw one.
        var heads: [String] {
            switch self {
            case .loaded:   ["KG", "REPS", "RPE"]
            case .unloaded: ["REPS", "RPE"]
            case .cardio:   ["MIN", "KM", "PACE"]
            // A pair is a string and not a table, so there is nothing to head
            // — and `spoken` names its delta by hand for the same reason.
            case .pair:     []
            case .whole:    []
            }
        }
    }

    /// One track of the table: the reading, and the ground it gained under it.
    struct Figure {
        let text: String
        /// Signed change against the same set NUMBER last time. Nil where there
        /// is no counterpart — a fourth set added this week carries no arrow
        /// rather than a fabricated one — and nil on every cardio column, where
        /// a bout is stored as a warm-up and so has no working ordinal to index
        /// the previous session by.
        var delta: Double?
        /// Primary ink for a load or a rep count. The effort ramp for an RPE
        /// and the cardio token for a bout: those are the two columns whose
        /// VALUE carries something beyond itself.
        var tint: Color?
        /// Whether a RISE in this reading is the good news.
        ///
        /// ── THE ONE COLUMN WHERE IT IS NOT ──────────────────────────────
        /// True for a load and for a rep count, and false for an RPE: the same
        /// three sets that felt like an 8 last week and a 9.5 this week are the
        /// textbook picture of accumulated fatigue, and the ledger painted that
        /// arrow GREEN. `delta(_:unit:higherIsBetter:)` in the metric grid at
        /// the top of this same page has taken this flag since it was written,
        /// and `VitalSpec` carries it for every vital — this column was the
        /// last reading in the app asserting a direction it had not been asked
        /// about.
        var upIsGood: Bool = true
    }

    /// Which table this exercise's card draws, asked once by `ledger(_:)`.
    ///
    /// Anything it cannot answer confidently falls to `.whole`, which is the
    /// behaviour this page had before columns existed — a mixed card is drawn
    /// the old way rather than drawn wrongly.
    static func layout(_ ex: SessionAnalysis.ExerciseReport) -> SetLayout {
        guard !ex.timed else { return .whole }
        let leads = ex.rows.compactMap { $0.set ?? $0.left ?? $0.right }
        guard !leads.isEmpty else { return .whole }
        if leads.allSatisfy(isCardio) { return .cardio }
        if leads.contains(where: isCardio) { return .whole }
        // ── ONE PAIR MAKES IT A PAIR CARD ───────────────────────────────────
        // Not "every row is a pair". A movement trained one arm at a time
        // routinely opens with a bilateral warm-up, and demanding a pure card
        // would leave the commonest real shape on `.whole` — which is the
        // behaviour this branch exists to end. `.pair` draws a single row as
        // its own whole string and reserves the same one-verdict line under
        // it, so the two shapes genuinely share a table.
        if ex.rows.contains(where: { $0.kind == "pair" }) { return .pair }
        return leads.allSatisfy { SetFormat.isUnloaded($0.weightKg) } ? .unloaded : .loaded
    }

    /// Minutes and kilometres rather than plates and reps.
    static func isCardio(_ set: DetailSet) -> Bool {
        SetFormat.cardio(
            durationSec: set.durationSec, distanceKm: set.distanceKm,
            incline: set.incline, elevationM: set.elevationM
        ) != nil
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    /// Bumped by the long press, so the haptic goes through the app's own
    /// trigger rather than a bare `UIImpactFeedbackGenerator`.
    @State private var inspects = 0
    /// Whether the PR margin is still showing. True until two seconds after the
    /// row first lands — see `marginText(_:)`.
    @State private var showingMargin = true

    /// ── WHY THE ROW HAS TWO SHAPES ──────────────────────────────────────────
    /// Three things compete for one line: the badge, `42kg × 10` and an effort
    /// word. At AX5 "Very hard" alone claimed ~40 % of the width, the value was
    /// squeezed to nothing and character-wrapped one glyph per line — `4` /
    /// `2k` / `g` / `×` / `1` / `0` — because a `Text` given less than one
    /// glyph of width still draws at its intrinsic size. One set took 500 pt
    /// and said nothing.
    ///
    /// `minimumScaleFactor` cannot fix it: the row does not need smaller type,
    /// it needs a second line. So at the accessibility sizes the effort word
    /// gets its own, and the value never wraps. (The prev column was the
    /// fourth competitor here and is gone — see the type's own header.)
    ///
    /// ── AND WHY IT IS 30 pt TALL AND NOT 44 ─────────────────────────────────
    /// 44 is the tap target, and on THIS screen nothing in the row is tappable:
    /// the ledger is read, not operated (the Edit button in the bar is how a
    /// set is corrected). Four sets at 44 plus a two-line stack pushed one
    /// movement past a phone's height, so the reader scrolled a screen per
    /// exercise. The vertical padding is `xs` and the height floor is the
    /// badge's — which is what "compact" means when the row is a list of
    /// numbers rather than a row of controls.
    var body: some View {
        // ── THE ALIGNMENT IS A DECISION, NOT A DEFAULT ──────────────────────
        // `.top` is right for a table: the badge and the readings share a first
        // line and the reserved delta hangs under the numbers. A card that
        // reserves NO delta — a bout, a timed hold — has ONE line of content
        // beside a 28 pt badge inside a 36 pt row, so top-aligning it parked
        // the whole row against its ceiling with the slack underneath. That was
        // the treadmill card's second visible defect after the empty tag row,
        // and `badgeSide` is the measurement both halves centre against.
        HStack(alignment: layout.comparable ? .top : .center, spacing: OnyxSpace.s) {
            badgeGroup
            if let figures, !typeSize.isAccessibilitySize {
                // Equal tracks, and no measurement anywhere: each column asks
                // for all the width and they divide it between them, which is
                // what makes the numbers line up down the card without a
                // `Grid` — whose cell machinery is the thing that stutters on a
                // long scrolling list.
                ForEach(Array(figures.enumerated()), id: \.offset) { _, figure in
                    column(figure)
                }
            } else {
                // ── THE SHAPES A COLUMN CANNOT HOLD ────────────────────────
                // A unilateral PAIR is two sides in one row and a timed hold is
                // one reading with no second number; splitting either would
                // mean choosing which half of a set to print in a track with
                // room for one. And at the accessibility sizes there are no
                // three columns at all: a third of 375 pt at AX5 holds "4…", so
                // the row keeps the one string it can set whole and gives the
                // effort word its own line underneath.
                VStack(alignment: .leading, spacing: 2) {
                    if splitsValues {
                        // ── ONE EFFORT, CENTRED AGAINST TWO LINES ──────────
                        // The effort is the row's trailing column everywhere
                        // else and inherits the row's `.top`, which parked a
                        // single reading against the LEFT side's line — as if
                        // it were the left side's rating. Against a pair it
                        // belongs to both, so it sits between them, and the
                        // only way to centre one child of a top-aligned row is
                        // to give it a row of its own.
                        HStack(alignment: .center, spacing: OnyxSpace.s) {
                            pairLines
                            if !typeSize.isAccessibilitySize, let effort {
                                Spacer(minLength: OnyxSpace.xs)
                                effort
                            }
                        }
                    } else {
                        value
                    }
                    if typeSize.isAccessibilitySize, let effort { effort }
                    // ONLY `.pair` reserves a line here. `.loaded` and
                    // `.unloaded` reach this branch at the accessibility sizes
                    // alone, where the row has already stopped being a table
                    // and its arrows are carried by `spoken` — a fourth line on
                    // an AX5 row that is already two is not a comparison, it is
                    // a scroll.
                    if layout == .pair, cardComparable { deltaLine(unitDelta, unit: "kg") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // A split pair has already drawn its one effort, centred
                // between the two lines it belongs to.
                if !typeSize.isAccessibilitySize, !splitsValues, let effort { effort }
            }
        }
        .padding(.horizontal, OnyxSpace.l)
        // ── TALLER ROW, TIGHTER PADDING ────────────────────────────────────
        // Two changes that pull in opposite directions and are meant to: the
        // row grows 30 → 33 pt so a record's wash has room to read as a band
        // rather than a line, and its own vertical padding drops from `xs` to
        // 2 pt so the extra height goes to the AIR AROUND THE NUMBERS and not
        // to the numbers' own margins. Net effect on a four-set card is +12 pt
        // and a denser-looking row, which is the combination the review asked
        // for and the reason neither value moved alone.
        .padding(.vertical, 2)
        // The frame BEFORE the wash. A `.background` applied first sizes itself
        // to the CONTENT, so a record row's tint stopped short of the row's own
        // height and drew as a pale stripe with a dark margin under it.
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        // ── A RECORD ROW IS WASHED IN THE MOVEMENT'S OWN COLOUR ─────────────
        // It was a 2 pt gold inset on the leading edge, which is invisible on a
        // scrolled page and says nothing about WHICH lift set the record. The
        // trophy beside the badge is the gold — the one place it appears in the
        // ledger, so scanning for it still finds records and nothing else — and
        // the row behind it takes the same hue as the card's rail and wash, so
        // a record reads as this movement's record.
        //
        // 0.10 and not the 0.14 it was: the card underneath is no longer black.
        // `onyxMuscleWash` now carries 6 %→2 % of this same hue across every
        // row, so a record's own tint is read as a STEP above its neighbours
        // rather than against nothing, and the old value stepped far enough to
        // reintroduce the banding the wash exists to remove.
        .background(isRecord ? tint.opacity(0.10) : Color.clear)
        // ── THE WHOLE ROW, NOT THE 22 pt DISC ───────────────────────────────
        // The trophy is the affordance and the disc is 22 pt — under the 44 pt
        // floor, and a long press that has to be landed accurately is a gesture
        // people stop trying. The row is 33 pt tall and full width, nothing
        // else on this page is interactive, and a press on an ordinary row
        // does nothing at all rather than opening an empty sheet.
        //
        // `.contentShape` first: the row's content is a badge and two `Text`s,
        // so without it the gesture only exists where ink was drawn.
        .contentShape(Rectangle())
        // NOT guarded on `records` being non-empty. The badge turns gold on
        // `isRecord` alone, and a record whose axes had no numeric bar carries
        // no `AxisRecord` — so that guard made a gold row advertise a gesture
        // that did nothing at all. `PrRecordSheet` already ships the sentence
        // for the empty case ("This set no longer holds a record."), which is
        // an answer; silence is not.
        .onLongPressGesture(minimumDuration: 0.4) {
            guard isRecord, let onInspect else { return }
            inspects += 1
            onInspect(records)
        }
        // The app's own haptic, not `UIImpactFeedbackGenerator` directly: every
        // other surface here goes through the trigger, and a generator with no
        // `prepare()` spends the first press spinning up the taptic engine.
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: inspects)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        // VoiceOver cannot long-press, and the rotor is where it looks for what
        // a row can do. Named for the RESULT, which is what a custom action's
        // label is read as ("What it beat" → "activate What it beat").
        //
        // The builder form, because it can be CONDITIONAL: the `named:` overload
        // is unconditional, so the rotor offered "What it beat" on all twenty
        // rows of a session and did nothing on the eighteen holding no record.
        .accessibilityActions {
            if isRecord, let onInspect {
                Button("What it beat") { onInspect(records) }
            }
        }
    }

    /// The set, as the two or three independent readings it actually is.
    ///
    /// ── COLUMNS WHERE THERE WERE TWO STRINGS ────────────────────────────────
    /// `42kg × 10` was one string, so the load and the rep count could not be
    /// read down a card and neither could carry a verdict of its own. Then they
    /// became two intrinsically-sized views side by side, which is better and
    /// still not a table: every row divided the line at a different point, so
    /// the eye had to re-find the rep count on each one.
    ///
    /// Three equal tracks, `KG · REPS · RPE`, named once by the card's heading
    /// and never again by a row. The unit left the numbers with the heading,
    /// which is where the width for the third column came from.
    ///
    /// Nil for the shapes a column cannot hold — see `SetLayout.whole`.
    private var figures: [Figure]? {
        guard let lead else { return nil }
        switch layout {
        case .whole:
            return nil
        // A pair is six numbers and three tracks hold three, so this table
        // draws no columns at all — `body` takes the sub-line branch instead.
        // See `SetLayout.pair`.
        case .pair:
            return nil
        case .cardio:
            // All three in the cardio token. `MuscleMap` has no entry for a
            // bout by design, so this is the one hue that names it — and the
            // ledger used to fall through to `.recover` lavender, the same
            // colour Abs/core wears.
            //
            // Incline and ascent are not drawn. They were the two components
            // `SetFormat.cardio` already dropped off the end at AX5, they
            // describe the BOUT rather than the set, and three tracks is what
            // makes this table the same object as the strength one beside it.
            // `spoken` still carries the value in full, ascent included.
            let minutes = lead.durationSec.map { $0 / 60 }
            return [
                Figure(text: lead.durationSec.map(SetFormat.clock) ?? "—",
                       tint: Color.onyx.cardio),
                Figure(text: lead.distanceKm.map { jsIntegerString($0) } ?? "—",
                       tint: Color.onyx.cardio),
                // Derived, never stored — distance and duration are the facts.
                Figure(text: CardioMetrics.formatPace(CardioMetrics.paceMinPerKm(
                            distanceM: lead.distanceKm.map { $0 * 1000 },
                            durationMin: minutes)),
                       tint: Color.onyx.cardio)
            ]
        case .unloaded:
            return [reps(lead), effortFigure]
        case .loaded:
            return [
                Figure(text: jsIntegerString(lead.weightKg),
                       delta: prev.map { lead.weightKg - $0.weightKg }),
                reps(lead), effortFigure
            ]
        }
    }

    private func reps(_ set: DetailSet) -> Figure {
        Figure(text: jsIntegerString(set.reps), delta: prev.map { set.reps - $0.reps })
    }

    /// The effort as a NUMBER, in the ramp's own colour.
    ///
    /// ── WHY THE WORD LOST THIS COLUMN ───────────────────────────────────────
    /// "Very hard" claimed roughly 40 % of the row's width at the default type
    /// size and the whole of it at AX5, which is why the row had to shed it to
    /// a second line. A track is a number's width. What the word carried that
    /// the figure does not is the FAILURE case — and `Color.onyx.effort` is
    /// already red at the top of its ramp, so the fact survives the change of
    /// register. The word itself comes back at the accessibility sizes, where
    /// the row stops being a table.
    /// Internal rather than private since W4: "a rise in RPE is red" is this
    /// wave's whole claim about this column, and a `private` computed property
    /// can only be checked by photographing it. `SessionTableTests` reads the
    /// flag; nothing else outside this file does.
    var effortFigure: Figure {
        guard let rpe else { return Figure(text: "—", tint: Color.onyx.textTertiary) }
        return Figure(text: OnyxFormat.rpe(rpe),
                      delta: prev?.rpe.map { rpe - $0 },
                      tint: Color.onyx.effort(rpe),
                      // The whole point of the flag. Up is harder, harder is
                      // not better, and the arrow that says so is red.
                      upIsGood: false)
    }

    /// One track: the reading, and the ground it gained under it.
    ///
    /// ── THE DELTA LINE IS ALWAYS DRAWN ──────────────────────────────────────
    /// §3.6's rule, the one the metric grid at the top of this page already
    /// obeys: a line that appears only when there is a change makes the row
    /// change height between two sessions, and a row silent about its
    /// comparison is indistinguishable from one that has none. So the line is
    /// reserved, and carries an em-dash when there is nothing to say.
    ///
    /// ── AND WHY IT IS SMALLER AND QUIETER THAN THE NUMBER ───────────────────
    /// `micro` against the number's `body`. The reading is what the reader came
    /// for; the delta is the context it sits in. Same size would make a card of
    /// five sets read as ten numbers.
    ///
    /// ── THE RESERVATION SURVIVED; THE GLYPH DID NOT (W4 · A2) ───────────────
    /// The line carried an em-dash when there was nothing to say, which on a
    /// three-track card with no previous session is FIFTEEN dashes — a page of
    /// punctuation saying "no comparison" fifteen times. The reason the line is
    /// reserved is unchanged and is not about the glyph: it stops the row
    /// changing height between two sessions. So the space stays and the ink
    /// goes. See `deltaLine`.
    private func column(_ figure: Figure) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(figure.text)
                .onyxType(.body).onyxNumeral()
                .foregroundStyle(figure.tint ?? Color.onyx.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if layout.comparable, cardComparable {
                deltaLine(figure.delta, upIsGood: figure.upIsGood)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The app's own pair of triangles — the two glyphs `MetaTagRow` treats as
    /// the only direction marks — and the amount beside them, in the verdict
    /// colours and nothing else.
    /// - Parameters:
    ///   - unit: named only where the line has no column head above it to name
    ///     it — which is `.pair`, whose verdict is in kilograms and whose row
    ///     is a string rather than a table.
    ///   - upIsGood: which direction earns the good token. See `Figure`.
    @ViewBuilder
    private func deltaLine(_ delta: Double?, unit: String? = nil, upIsGood: Bool = true) -> some View {
        if let delta, abs(delta) > 0.001 {
            HStack(spacing: 2) {
                Image(systemName: delta > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .symbolRenderingMode(.hierarchical)
                Text(signed(delta) + (unit.map { " \($0)" } ?? ""))
            }
            .onyxType(.micro).onyxNumeral()
            // ── THE ARROW POINTS AT THE SIGN; THE COLOUR JUDGES IT ──────────
            // Both used to be the sign. An RPE that climbed from 8 to 9.5
            // therefore drew an up arrow in the GOOD token — the ledger
            // congratulating a lifter for being more tired. The arrow still
            // points where the number went, because that is a fact; the ink is
            // the verdict, and only the verdict inverts.
            .foregroundStyle((delta > 0) == upIsGood ? Color.onyx.good : Color.onyx.danger)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            // ── A RESERVED LINE, DRAWN IN NOTHING ───────────────────────────
            // It was an em-dash, covering both silences — no set to compare
            // with, and a number that did not move. Both readings survive: the
            // line is still there, so the row cannot change height between two
            // sessions, and there is still no arrow claiming a verdict nothing
            // earned. What is gone is the fifteen glyphs per card that said so
            // out loud.
            //
            // Measured BY the micro line rather than by a number: the same
            // `Text`, in the same role, hidden. `.hidden()` is documented as
            // "hides this view without changing its layout", so the reservation
            // is the old height by construction and at every text size — a
            // `frame(height:)` would hold at default type and drift at AX5.
            Text("—")
                .onyxType(.micro)
                .hidden()
                .accessibilityHidden(true)
        }
    }

    /// How this row's two sides are drawn — nil on anything that is not a pair.
    ///
    /// ── THE LEDGER HONOURS ALL THREE CASES; THE LOGGER STILL DOES NOT ───────
    /// `SetPairLayout.resolve` has implemented exactly the three shapes this
    /// page needs since it was written, and only the LOGGER consumed it — where
    /// `.unified` was deliberately killed for a completed pair on 2026-09-11,
    /// because a merged row left no control that could make the two sides
    /// differ. That dead end is an EDITING dead end (the rule's own header says
    /// so: "there was no way out, because the only control that could have made
    /// the sides differ was the one writing to both of them"), and this page is
    /// read-only — the Edit button in the bar is how a set is corrected here.
    /// So the ledger merges and the deck does not, and founder decision 4 is
    /// the reason the two surfaces are allowed to differ about one drawing.
    ///
    /// A group of ONE is `.unified` by the rule's own definition, which is what
    /// makes a pair row with a side missing render as an ordinary set.
    ///
    /// `reps` is rounded because the rule counts them as `Int` and a set is a
    /// whole number of reps everywhere it is entered; `DetailSet.reps` is a
    /// `Double` because every numeric column in this schema is.
    /// Internal rather than private, on the precedent `effortFigure` sets one
    /// screen down: the three cases are this wave's whole claim about this row,
    /// and a `private` computed property can only be checked by photographing
    /// it. `UnilateralAndQualityTests` reads all three; nothing else outside
    /// this file does.
    var pairLayout: SetPairLayout? {
        guard row.kind == "pair" else { return nil }
        let sides = [row.left, row.right].compactMap { $0 }
        return SetPairLayout.resolve(
            weights: sides.map { $0.weightKg },
            reps: sides.map { Int($0.reps.rounded()) },
            rpes: sides.map { $0.rpe }
        )
    }

    /// Whether the two sides get a line each, or share one.
    ///
    /// `.valueSplit` is the rule's answer and the second test is the case the
    /// rule cannot see: it reads load, reps and effort, and a CARDIO pair is
    /// told apart by `duration_sec` / `distance_km`, which are not among them.
    /// Two bouts of different lengths would resolve as `effortSplit` — equal
    /// weights, equal reps, both zero — and merge into one line that printed
    /// one of them. So a merge also asks the thing that is actually about to be
    /// drawn: if the two sides do not render the same string, they are not one
    /// line, whatever the three axes say.
    var splitsValues: Bool {
        guard layout == .pair, row.kind == "pair",
              let left = row.left, let right = row.right
        else { return false }
        return pairLayout == .valueSplit || fmt(left) != fmt(right)
    }

    /// The two ratings when they disagree — `L 8 · R 9`, and `L 8 · R —` when
    /// one side was never rated.
    ///
    /// Nil when they AGREE, which includes both being unrated: that is one
    /// reading about one set, and printing `L 8 · R 8` to say it is the
    /// repetition the three cases exist to avoid.
    ///
    /// ── AND WHY A NIL SIDE IS AN EM-DASH AND NEVER A BLANK ──────────────────
    /// `workout_sets.rpe` is nullable by design — "an unrated set must stay
    /// distinguishable from a set rated zero" (`AppDatabase`) — and until §W1 F
    /// the logger could leave one side null permanently. A ledger that printed
    /// the rated side alone would show `L 8` and read as a rating for the set,
    /// which is the one thing that row does not have.
    var splitEfforts: (Double?, Double?)? {
        guard row.kind == "pair", let left = row.left, let right = row.right,
              left.rpe != right.rpe
        else { return nil }
        return (left.rpe, right.rpe)
    }

    /// The two sides, one under the other, under one badge.
    ///
    /// ── WHY THE VALUE IS `secondary` AND NOT `body` ─────────────────────────
    /// Two `body` lines make a pair row 58 pt against a single row's 36, which
    /// is a card that scrolls for the one movement on it trained an arm at a
    /// time. The plan named `micro`, and `micro` is the one role this scale
    /// forbids for a value in as many words — "a register label … never
    /// carrying a number" (`OnyxType`). `secondary` is the legal step down,
    /// named for exactly this ("the line under a value"), and it is what makes
    /// a sub-line read as HALF of a set rather than as a set of its own.
    private var pairLines: some View {
        VStack(alignment: .leading, spacing: 1) {
            pairLine("L", row.left)
            pairLine("R", row.right)
        }
    }

    @ViewBuilder
    private func pairLine(_ tag: String, _ set: DetailSet?) -> some View {
        if let set {
            HStack(spacing: OnyxSpace.xs) {
                Text(tag)
                    .onyxType(.micro).fontWeight(.bold)
                    .foregroundStyle(Color.onyx.textTertiary)
                    // ── AND THE TRACK GOES AT THE ACCESSIBILITY SIZES ───────
                    // The logger's own split row records this trap: a scaled
                    // `micro` glyph is several times 14 pt, so a fixed frame at
                    // AX5 overflows and the letter prints straight through
                    // whatever is beside it — an `R` that comes out looking
                    // like an `F`, with nothing clipped for a layout gate to
                    // catch. A fixed track is what aligns two sides' numbers,
                    // and at a size where there is only one column to align it
                    // buys nothing.
                    .frame(width: typeSize.isAccessibilitySize ? nil : Self.sideTrack,
                           alignment: .leading)
                Text(fmt(set))
                    .onyxType(.secondary).onyxNumeral()
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    /// This row's work against the same row last time, in kilograms.
    ///
    /// ── WHY A VOLUME AND NOT A LOAD OR A REP COUNT ──────────────────────────
    /// A `.pair` row prints its set as a STRING, so there is one line under it
    /// to carry one verdict, and no one of six numbers can be it: 22 × 10 /
    /// 22 × 9 against 20 × 12 / 20 × 11 is heavier and shorter at once.
    ///
    /// ── AND WHY `SessionVolume` AND NOT `w × r + w × r` ─────────────────────
    /// "The pair's combined load × reps" has exactly one definition in this app
    /// and it is not the sum. `SessionVolume.sessionVolumeKg` scores a genuine
    /// L/R pair ONCE, at the weaker side, so a set logged split weighs what the
    /// same set weighs logged whole — the rule its own header says must
    /// survive. The card's tonnage capsule is that function and the session's
    /// tonnage is that function; a second pair arithmetic on the row beneath
    /// them would put two numbers on one card that disagree about what a pair
    /// is worth.
    private var unitDelta: Double? {
        guard let previous = prevUnitKg else { return nil }
        return volumeKg - previous
    }

    /// What this row is worth, by the one rule. A single row on a `.pair` card
    /// goes through the same function and comes out as `w × r`.
    private var volumeKg: Double {
        SessionVolume.sessionVolumeKg([row.set, row.left, row.right].compactMap { $0 }.map {
            VolumeSet(weightKg: $0.weightKg, reps: $0.reps,
                      side: $0.side, pairId: $0.pairId, setType: $0.setType)
        })
    }

    /// `+2.5`, `−1`. `jsIntegerString` and not a fixed decimal count: a real
    /// plate change is 2.5 and a real rep change is 2, and "+2.0 reps" is a
    /// precision the number does not have.
    private func signed(_ delta: Double) -> String {
        (delta > 0 ? "+" : "−") + jsIntegerString(abs(delta))
    }

    /// The ordinal, and the trophy beside it when the set set a record.
    ///
    /// ── WHY THE TROPHY MOVED, AND WHY THE NUMBER STAYED ─────────────────────
    /// The mark used to sit beside the VALUE, at the other end of the row from
    /// the number. Scanning a session for its records therefore meant reading
    /// down a ragged column whose x-position moved with the width of
    /// `42kg × 10` — and the two facts a reader pairs ("which set" and "was it
    /// a record") were 200 pt apart.
    ///
    /// Putting the trophy IN the badge, replacing the number, was tried and
    /// reverted for a reason that still holds: every set on this page is
    /// logged, so a card's rows read `W · 🏆 · 2 · 🏆` and the two rows most
    /// worth placing were the two with no number left on them. Beside the
    /// badge is the third answer, and it costs nothing either side gives up —
    /// the ordinal column stays a column, and the mark is now the first thing
    /// on the row instead of the last.
    ///
    /// FAILURE DOES NOT GET THIS SLOT. It keeps the effort column's own word,
    /// where it has always been said, because a red glyph at the head of the
    /// row would compete with the gold for the same glance and there is only
    /// one fact here worth interrupting a scan for.
    /// ── THE TROPHY IS NOW THE BADGE, BY REQUEST (2026-09-11) ────────────────
    /// Everything above describes why the mark sat BESIDE the ordinal, and the
    /// argument was real: every set on this page is logged, so replacing the
    /// number costs the reader the one column that places a set in its card.
    ///
    /// The founder asked for the swap anyway, and the cost is bought back
    /// rather than ignored: the ordinal is still spoken in full by `spoken`
    /// ("Set 3, 72.5 kg × 15, Volume record"), the rows either side of a record
    /// still number continuously so the position is readable by counting, and
    /// the trophy is now a CONTROL — long-press it and the sheet names the set
    /// as its subtitle. A gold disc at the head of the row is also the only
    /// thing on this page worth interrupting a scroll for, which is the reading
    /// the original layout was trying to buy with a second glyph.
    private var badgeGroup: some View {
        VStack(spacing: 1) {
            badge
            restGutter
        }
    }

    /// The rest taken BEFORE this set, in the badge's own column.
    ///
    /// ── WHY THE GUTTER AND NOT A FOURTH TRACK ───────────────────────────────
    /// The card's table is `KG · REPS · RPE` and all three tracks are already
    /// at their floor on a 375 pt phone — `set-row-u2` is the wave that got the
    /// row to stop being wider than the screen, and a fourth column would undo
    /// it. The badge's column is 28 pt wide, is the same 28 pt the heading
    /// leaves empty, and has nothing under the ordinal at all.
    ///
    /// ── AND WHY IT COSTS NO HEIGHT ON A CARD THAT COMPARES ──────────────────
    /// A comparable card already reserves a delta line under every reading
    /// (`SetLayout.comparable` and `deltaLine`), and the badge is 28 pt inside
    /// a row that is therefore already taller than it. The rest lands in slack
    /// that was there anyway. On a card that reserves NO delta — a bout, a
    /// timed hold — the line WOULD add height, so it is not drawn: those are
    /// also the two shapes where the number says least (a treadmill block is
    /// one set, and there is nothing before it to have rested from).
    ///
    /// ── THE DELTA IS A DIRECTION, NOT A VERDICT ─────────────────────────────
    /// An arrow and no colour. Resting longer than the set before is neither
    /// good nor bad — it is what the session did, and this app paints `good`
    /// only on facts it is prepared to call improvements. Under 15 seconds no
    /// arrow at all: `restSec` is wall-clock, it moves by whatever a rack queue
    /// and a phone unlock cost, and an arrow on every row would be noise
    /// wearing the shape of a signal. Fifteen is the same grid `adjustRest`
    /// nudges on.
    @ViewBuilder
    private var restGutter: some View {
        if layout.comparable, cardComparable, !typeSize.isAccessibilitySize {
            // ── TWO TENANTS, ONE LINE, AND THE MARGIN HAS THE LEASE ────────
            // See `marginText`. The margin is shown for two seconds and the
            // rest takes the line back; on a row with no record — which is
            // most of them — the rest has it from the first frame.
            if let margin, showingMargin {
                marginText(margin.short)
            } else if let restSec {
                Text(restLabel(restSec))
                    .onyxType(.micro).onyxNumeral()
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: SetRow.badgeSide, alignment: .center)
                    // Spoken by `spoken`, which says it in words — "rested 2
                    // minutes 15 seconds" rather than "up 2 colon 15".
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
    }

    /// What the trophy was worth, in the badge's own column, for two seconds.
    ///
    /// ── WHY IT SHARES THE GUTTER RATHER THAN TAKING A PLACE IN THE TABLE ────
    /// The row is a three-track table at its width floor on a 375 pt phone
    /// (`set-row-u2`), so a fourth reading would push one of the three out —
    /// and a reading that appears for two seconds and then leaves would push it
    /// out and pull it back, twenty rows of a page re-laying themselves under a
    /// thumb. An overlay over the table was the other draft and it landed on
    /// the KG column's own delta arrow, which is a collision rather than a
    /// layout.
    ///
    /// Under the badge is directly under the TROPHY — which is what the margin
    /// is about — it is the one column with slack, and it is a slot that
    /// already exists. Nothing moves when the two swap, because the line is the
    /// same height either way.
    ///
    /// ── AND WHY IT IS TRANSIENT AT ALL ──────────────────────────────────────
    /// The page is the one you land on when you finish a workout, and the
    /// question it answers on arrival is "what did I just do". A record's
    /// MARGIN is the best two seconds of that and a poor permanent column: it
    /// is true of a handful of rows out of twenty, it is a different unit on
    /// each of them, and a week later it is a figure already destroyed in the
    /// store (`ExerciseReport.records`' own header — `personal_records` is
    /// upsert-on-conflict and keeps no history). So it is shown, and then it
    /// gets out of the way; the long press still opens `PrRecordSheet` with
    /// both numbers, for ever.
    ///
    /// Reduce Motion gets no cross-fade, only the same two-second life: what is
    /// animated is opacity on one micro line, and removing it outright would
    /// take the fact away rather than the movement.
    private func marginText(_ margin: String) -> some View {
        Text(margin)
            .onyxType(.micro).fontWeight(.bold).onyxNumeral()
            .foregroundStyle(Color.onyx.record)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: SetRow.badgeSide, alignment: .center)
            .transition(.opacity)
            // Said by `spoken`, which is the row's one label — a line that
            // published itself would interrupt the sentence the row is in the
            // middle of.
            .accessibilityHidden(true)
            .task {
                guard !marginHeld else { return }
                try? await Task.sleep(for: .seconds(2))
                withAnimation(OnyxMotion.move) { showingMargin = false }
            }
    }

    /// `2:15`, with a bare arrow in front when it moved by a quarter-minute or
    /// more against the set before.
    private func restLabel(_ seconds: Int) -> String {
        let clock = Clock.format(Double(seconds))
        guard let delta = restDeltaSec, abs(delta) >= 15 else { return clock }
        return "\(delta > 0 ? "↑" : "↓")\(clock)"
    }

    /// Never wrapped, and never scaled below legibility: it is the row.
    ///
    /// A FOUR-component cardio value — `5:00 · 0.37 km · 2% · 7 m` — is whole
    /// at 375 pt (verified on an SE 3rd gen) and TRUNCATES at AX5, where the
    /// incline and the ascent both drop off the end. That is the row's own rule
    /// and not an accident: it sheds the effort column at the same sizes, and
    /// `spoken` carries the value in full to VoiceOver, ascent included. If a
    /// sighted AX5 reader ever needs the tail, this line is the one to change —
    /// `lineLimit(typeSize.isAccessibilitySize ? 2 : 1)`.
    ///
    /// The components are ordered longest-lived first, so what AX5 sheds is
    /// what was added last: duration and distance are the two facts a walk
    /// always has, and ascent is the one the column was added for.
    private var value: some View {
        Text(current)
            .onyxType(.body).onyxNumeral()
            .foregroundStyle(Color.onyx.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The set's number, in the box the logger's own deck draws it in — `W` for
    /// a warm-up, the ordinal for everything else, the trophy for a record.
    ///
    /// ── IT IS THE DECK'S BADGE NOW, NOT A SECOND DRAWING OF ONE ─────────────
    /// This was a 22 pt grey `Circle`. The deck, ten seconds earlier in the same
    /// workout, draws the same set as a rounded rectangle in the movement's own
    /// hue — so one object had two shapes and two colour languages depending on
    /// which screen you were standing on. `SetBadge` is the single answer; what
    /// this call keeps is the ledger's own SIZE (28 rather than 32, in a 33 pt
    /// row that is read and not operated) and the ledger's own rule about the
    /// ordinal: every set on this page is logged, so a tick on each of them
    /// would lose the one column that places a set inside its card.
    ///
    /// The trophy still replaces the number on a record, by the founder's 11
    /// September call — see the note above `badgeGroup` for what that costs and
    /// how it is bought back.
    private var badge: some View {
        SetBadge(
            label: ordinal,
            tint: tint,
            kind: badgeKind,
            // Never the solid fill: on the deck a filled box means "logged",
            // and on a page where EVERY set is logged that reading carries no
            // information and would paint the whole ledger in the rail.
            filled: false,
            isRecord: isRecord,
            side: Self.badgeSide
        )
        // The box is the row's left margin and its height floor; it must not
        // grow with the type size or it takes the width from the value beside
        // it — and `minimumScaleFactor` alone does not hold at AX5, where a
        // scaled 13 pt caption is still half again the size of the box and drew
        // straight over the value. What is written here is spoken by the row
        // (see `spoken`), so capping the badge's own type costs nothing.
        .dynamicTypeSize(...DynamicTypeSize.large)
        // An unlabelled glyph over a `Shape` is not an accessibility element.
        .accessibilityHidden(true)
    }

    /// What VoiceOver hears, built by hand rather than combined: the row's
    /// visible text no longer names the record axes, and "65 kg × 10" alone
    /// would make the session's best set sound like every other one.
    private var spoken: String {
        var parts = [row.num.map { "Set \($0)" } ?? "Warm-up set", current]
        if !axes.isEmpty { parts.append("\(axes.joined(separator: ", ")) record") }
        // Two ratings are spoken as two. `rpe` is the MAX of the row's sides,
        // which is the right single number for a set that agreed with itself
        // and, on a pair that did not, is the harder arm announced as though it
        // were the set — the exact reading the split column exists to end.
        if let sides = splitEfforts {
            parts.append("left \(readout(sides.0)), right \(readout(sides.1))")
        } else if let rpe {
            parts.append(Effort.rpeLabel(rpe))
        }
        // ── THE ARROWS ARE SPOKEN, BECAUSE THEY ARE THE ONLY PLACE THIS IS
        // SAID ──────────────────────────────────────────────────────────────
        // The row is `children: .ignore`, so every column's delta is invisible
        // to VoiceOver unless it is named here — and the previous session's
        // set is nowhere else on this page. Zipped against the card's own
        // heads, so a column and its spoken name cannot drift apart.
        for (head, figure) in zip(layout.heads, figures ?? []) {
            guard let delta = figure.delta, abs(delta) > 0.001 else { continue }
            parts.append("\(head.lowercased()) \(delta > 0 ? "up" : "down") \(jsIntegerString(abs(delta)))")
        }
        // A pair has no heads to zip against — its one line is about the SET
        // and not about a column — so it is named by hand. Without this the
        // only comparison a unilateral card carries would be invisible to
        // VoiceOver, which is the state this whole layout exists to end.
        if layout == .pair, let delta = unitDelta, abs(delta) > 0.001 {
            parts.append("volume \(delta > 0 ? "up" : "down") \(jsIntegerString(abs(delta))) kilograms")
        }
        // The gutter is `accessibilityHidden` and says `↑2:15`, which is not a
        // sentence. Said here in words, and said whatever the type size is —
        // the gutter itself is dropped at the accessibility sizes, where the
        // row has stopped being a table, and dropping the fact with the glyph
        // would make this the one reading a VoiceOver user cannot reach.
        if let restSec {
            var sentence = "rested \(Clock.format(Double(restSec)))"
            if let delta = restDeltaSec, abs(delta) >= 15 {
                sentence += ", \(abs(delta)) seconds \(delta > 0 ? "longer" : "shorter") than the set before"
            }
            parts.append(sentence)
        }
        // The margin the overlay shows for two seconds and then takes away. A
        // transient graphic is no graphic at all to a reader who cannot see it,
        // and this is the only other place the number is said.
        if let margin { parts.append("beat it by \(margin.spoken)") }
        return parts.joined(separator: ", ")
    }

    /// What the record on this row BEAT, as one short signed figure — or nil.
    ///
    /// ── ONE AXIS, CHOSEN, NOT THE LIST ──────────────────────────────────────
    /// A set can take four axes at once and `PrRecordSheet` prints all of them,
    /// which is what the long press is for. A two-second glance holds one
    /// number, so the ladder is fixed rather than "whichever came first": the
    /// heaviest load is the claim a lifter reads first, the estimated 1RM is
    /// the one that survives a rep change, reps come next, and set tonnage last
    /// — it is the axis most likely to move for a reason that is not strength.
    ///
    /// Nil when the row holds a record with no numeric bar behind it, which is
    /// a real state (`SetRow.records`' own header): the badge still turns gold
    /// and there is simply no margin to print.
    private var margin: (short: String, spoken: String)? {
        let ladder: [PrAxis] = [.weight, .e1rm, .reps, .volume]
        guard let record = ladder.lazy.compactMap({ axis in
            records.first { $0.axis == axis }
        }).first else { return nil }
        let gain = record.mark.value - record.mark.previous
        guard gain > 0.001 else { return nil }
        let figure = record.axis == .reps ? OnyxFormat.sets(gain) : OnyxFormat.kg(gain)
        let unit = record.axis.unit
        // ── THE DRAWN FORM CARRIES NO UNIT, AND THE SPOKEN ONE DOES ────────
        // The gutter is 28 pt of monospaced digits. `+1.6 kg` renders as
        // `+1.6…` at the scale floor — a margin with its own number cut off,
        // which is worse than no margin — and `+12.5kg` would still have to
        // overflow onto the load column's own delta arrow. `+12.5` is five
        // glyphs and always whole.
        //
        // Nothing is lost by dropping it: the KG column is the very next
        // thing on the row, under a heading that says KG, and a reps record
        // has no unit to print in the first place. VoiceOver gets the long
        // form, where there is no width at all to be short about.
        return (
            short: "+\(figure)",
            spoken: unit.isEmpty ? "+\(figure)" : "+\(figure) \(unit)"
        )
    }

    @ViewBuilder
    private var effort: (some View)? {
        if rpe != nil || splitEfforts != nil { effortInk }
    }

    /// Reached only when there is something to say — see `effort`.
    ///
    /// Two readings print as NUMBERS and one prints as a WORD, which is the
    /// same call the logger's own split row makes (`ExerciseCardView.effort`):
    /// the row is already telling you this is the left arm and the right arm,
    /// so the question has narrowed from "how hard was that" to "which of the
    /// two was harder" — and two numbers answer a comparison better than two
    /// words, in a column sized for one of them.
    @ViewBuilder
    private var effortInk: some View {
        if let sides = splitEfforts {
            HStack(spacing: 3) {
                sideEffort("L", sides.0)
                Text("·")
                    .onyxType(.micro)
                    .foregroundStyle(Color.onyx.textTertiary)
                sideEffort("R", sides.1)
            }
            .lineLimit(1)
            .fixedSize()
        } else if let rpe {
            Text(Effort.rpeLabel(rpe))
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.effort(rpe))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func sideEffort(_ tag: String, _ value: Double?) -> some View {
        HStack(spacing: 2) {
            Text(tag)
                .onyxType(.micro).fontWeight(.bold)
                .foregroundStyle(Color.onyx.textTertiary)
            Text(value.map(OnyxFormat.rpe) ?? "—")
                .onyxType(.caption).fontWeight(.bold).onyxNumeral()
                .foregroundStyle(value.map(Color.onyx.effort) ?? Color.onyx.textTertiary)
        }
    }

    /// A bout is drawn as an ordinary set for the same reason the deck draws
    /// it as one: `W` is a claim about a LIFT — the ramp-up sets before the
    /// working ones — and a treadmill block has no working set to be a ramp
    /// for. The KIND is untouched; only the drawing changes.
    private var ordinal: String { row.num.map(String.init) ?? (isCardio ? "\(position)" : "W") }

    /// Drawn as a normal set, whatever it is stored as.
    private var badgeKind: LoggerModel.SetKind {
        isCardio ? .normal : (LoggerModel.SetKind(rawValue: row.kind) ?? .normal)
    }

    /// Whether THIS row is a bout. Asked by `ordinal` and `badgeKind`, which
    /// are about one row; the card's `layout` is the same test asked of every
    /// row at once.
    private var isCardio: Bool { lead.map(Self.isCardio) ?? false }

    private var lead: DetailSet? { row.set ?? row.left ?? row.right }

    private var isRecord: Bool { !axes.isEmpty }

    // A failed set is named ONCE on this row, by the effort column's own word
    // ("Failure", in `Color.onyx.danger`). It had a second `f.circle.fill`
    // beside the value; that glyph is gone with the slot it shared with the
    // trophy, which has moved to the badge. Saying it twice was affordable
    // while the mark column existed and is not worth reintroducing one.

    private var current: String {
        // Only a pair whose sides actually DIFFER is two readings. One that
        // agrees is one set, drawn and spoken as one — see `splitsValues`.
        if row.kind == "pair", splitsValues {
            return [row.left.map { "L " + fmt($0) }, row.right.map { "R " + fmt($0) }]
                .compactMap { $0 }.joined(separator: " · ")
        }
        return lead.map(fmt) ?? "—"
    }

    private var axes: [String] {
        var out: [String] = []
        for a in [row.set, row.left, row.right].compactMap({ $0?.prAxes }).flatMap({ $0 }) {
            let label = PrAxis(rawValue: a).map { PrEngine.axisLabel($0, timed: timed) } ?? a
            if !out.contains(label) { out.append(label) }
        }
        return out
    }

    private var rpe: Double? {
        [row.set, row.left, row.right].compactMap { $0?.rpe }.max()
    }

    /// One side's rating in words, or the fact that it has none. Never a
    /// silence: VoiceOver reading "left hard" and stopping cannot be told from
    /// a row with one side.
    private func readout(_ value: Double?) -> String {
        value.map(Effort.rpeLabel) ?? "not rated"
    }

    private func fmt(_ kg: Double, _ reps: Double) -> String {
        SetFormat.format(weightKg: kg, reps: reps, timed: timed)
    }

    /// The set as ITS OWN axes — `5:00 · 0.37 km · 2% · 7 m` for the treadmill,
    /// `42kg × 10` for everything else.
    ///
    /// `SetFormat.cardio` answers nil unless the set carries one of the three
    /// columns `hotfix-polish.sql (git history)` added, so the fallback is the whole
    /// of the previous behaviour and every lifted row renders byte for byte as
    /// it did. Without it the treadmill that opens 2026-09-07 reads `0 reps` —
    /// `weight_kg 0, reps 0` is exactly what that session stores.
    ///
    private func fmt(_ s: DetailSet) -> String {
        SetFormat.cardio(
            durationSec: s.durationSec, distanceKm: s.distanceKm,
            incline: s.incline, elevationM: s.elevationM
        ) ?? fmt(s.weightKg, s.reps)
    }
}
