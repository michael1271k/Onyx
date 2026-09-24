import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// THE SIX SQUARES (founder decision 5; six and reorderable since W9, D9).
//
// ── W9: THE CAROUSEL IS GONE ────────────────────────────────────────────────
// Fatigue and the stress log were a two-page horizontal pager above this grid
// — the one side-scroll on Pulse, and the row that needed three
// `scrollPosition` mitigations to survive a `List` recycle. They are squares
// now, in the same grid, and the grid is 2 × 3 in an order the reader sets:
// the toolbar's Edit puts the squares in the Today tab's jiggle, a drag moves
// one onto another's place, and the order rides in `dashboard_layouts` under
// `pulse` (`PulseLayout`). Every sheet is still presented by `DayScreen`.
//
// ── WHAT THE FOUR WERE (W3) ─────────────────────────────────────────────────
// What these four were: the stress index as a full-width tile with a 96 pt
// trace beside a 28 pt numeral; the scale and the stack as two 44 pt rows in a
// section of their own; and soreness as a third of the carousel, spending a
// whole page to say "two things are sore" and hand the reader to a sheet. Four
// readings, four pieces of chrome, about 560 pt of a screen budgeted at a
// screen and a half.
//
// What they are now: one 2 × 2 grid, about 340 pt. A square is the smallest
// shape that still holds a figure, its unit and a trace, and four of them read
// as one block of "what the day measured" rather than as four unrelated
// surfaces that happen to be adjacent.
//
// NOTHING WAS CUT. The index keeps its 50-baseline fortnight; the scale keeps
// its fat percentage and GAINS the trace a 44 pt row never had room for; the
// stack keeps its dose dots; and soreness keeps every rating it ever had,
// because the rating verb was never on the card — the popover has always lived
// on the map itself (`DomsTile`), and the card was only ever a door.
//
// ── WHY THE INDEX IS HERE AND NOT IN THE NOW STRIP ──────────────────────────
// `Stress.Terms` weights a `self` term built from the fatigue slots and the
// stress log — the two cards in the carousel directly above this grid. A number
// placed above the readings it is partly made of asks to be read as their
// cause. It stays below them, which is the rule the tile it replaces followed
// and the whole reason this grid is not the first thing on the screen.
//
// ── AND WHY IT BECOMES ROWS AT AX5 ──────────────────────────────────────────
// Half a phone is 171 pt wide, so a square of it is 171 pt TALL. At the
// accessibility sizes a 53 pt numeral and its unit already fill that, and four
// full-width squares would be ~1,370 pt of screen to say what four rows say in
// 200 — the compaction inverts. The four fall back to rows, which is the escape
// `VitalsGrid` takes one row above them, and two of those rows (`ScaleRow`,
// `StackRow`) are the originals this grid replaced, unchanged.
// ─────────────────────────────────────────────────────────────────────────────

/// Stress index · Stress log · Soreness · Fatigue · Scale · Stack, in the
/// stored order.
///
/// Every door is a closure: this whole grid is one `List` row, and a `.sheet`
/// declared on a recyclable cell is torn down with the cell — the reason
/// `DayScreen` owns every presentation on this screen.
struct PulseSquareGrid: View {
    let model: DayModel
    let onStress: () -> Void
    let onLogStress: () -> Void
    let onBrowseStress: () -> Void
    let onSoreness: () -> Void
    let onFatigue: () -> Void
    let onScale: () -> Void
    let onStack: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drops = 0

    private var editing: Bool { model.editingSquares }
    private var order: [PulseSquare] { model.pulseLayout.order }

    /// `OnyxSpace.l` between the cells, as decision 5 asks — and the same 16 pt
    /// the list already insets this row by, so the trench between two squares
    /// is the trench at the screen's edge and the grid reads as a grid rather
    /// than as four tiles that drifted together.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.l), count: 2)
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            // The rows reorder too — same drag, same jiggle — or Edit would
            // be a button that does nothing at the sizes that need it most.
            ForEach(order, id: \.self) { which in
                row(which)
                    .modifier(Jiggle(on: editing, seed: which.rawValue))
                    .modifier(arrangeable(which))
            }
        } else {
            LazyVGrid(columns: columns, spacing: OnyxSpace.l) {
                ForEach(order, id: \.self) { which in
                    square(which)
                        .modifier(Jiggle(on: editing, seed: which.rawValue))
                        .modifier(arrangeable(which))
                }
            }
            .environment(\.pulseEditing, editing)
            .animation(reduceMotion ? OnyxMotion.fade : OnyxMotion.move, value: order)
            .sensoryFeedback(.selection, trigger: drops)
        }
    }

    /// Drop `dragged` here: it takes this square's place, the rest close up.
    private func arrangeable(_ target: PulseSquare) -> Arrangeable {
        Arrangeable(enabled: editing, id: target.rawValue) { dragged in
            guard let from = PulseSquare(rawValue: dragged) else { return }
            drops += 1
            model.moveSquare(from, to: target)
        }
    }

    @ViewBuilder
    private func square(_ which: PulseSquare) -> some View {
        switch which {
        case .stress:    StressSquare(model: model, action: onStress)
        case .stressLog: StressLogSquare(model: model, action: onLogStress, onBrowse: onBrowseStress)
        case .soreness:  SorenessSquare(model: model, action: onSoreness)
        case .fatigue:   FatigueSquare(model: model, action: onFatigue)
        case .scale:     ScaleSquare(model: model, action: onScale)
        case .stack:     StackSquare(model: model, action: onStack)
        }
    }

    /// The rows stay buttons while editing (`PulseRow` is shared chrome), so
    /// their doors are shut here instead — a tap mid-arrangement opens nothing.
    private func gated(_ open: @escaping () -> Void) -> () -> Void { editing ? {} : open }

    @ViewBuilder
    private func row(_ which: PulseSquare) -> some View {
        switch which {
        case .stress:    StressIndexRow(model: model, onOpen: gated(onStress))
        case .stressLog: StressLogRow(model: model, onLog: gated(onLogStress), onBrowse: gated(onBrowseStress))
        case .soreness:  SorenessRow(model: model, onOpen: gated(onSoreness))
        case .fatigue:   FatigueRow(model: model, onOpen: gated(onFatigue))
        case .scale:     ScaleRow(model: model, onEnter: gated(onScale))
        case .stack:     StackRow(model: model, onOpen: gated(onStack))
        }
    }
}

/// Whether the grid is in jiggle mode, read by every square. An environment
/// value rather than a parameter threaded through six inits: the squares do
/// one thing with it — stop being buttons — and the one place that sets it is
/// the grid.
private struct PulseEditingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var pulseEditing: Bool {
        get { self[PulseEditingKey.self] }
        set { self[PulseEditingKey.self] = newValue }
    }
}

// MARK: - The shape

/// One square: a caption header, then a reading pinned to the bottom of it.
///
/// ── WHY THE READING IS AT THE BOTTOM AND NOT CENTRED ────────────────────────
/// Four squares with centred contents put four numerals at four different
/// heights, because each one's content is a different number of lines. Pinned
/// to the floor with the slack above, the figures in a row sit on one line and
/// the eye reads across them — which is the only reason to put four readings
/// side by side rather than one under another.
///
/// The whole square is the target. A chevron would be 12 pt of glyph in a 139 pt
/// box saying what `.onyxPress` already says by moving.
private struct SquareShell<Content: View>: View {
    let title: String
    /// The unit that names the square's axis — "14 days" against the log card's
    /// "3 today". Nil draws nothing rather than an empty slot.
    var trailing: String?
    /// What a reader who cannot see the square is told, after its title.
    let spoken: String
    let action: () -> Void
    /// A second verb the face carries as a nested control — the stress log's
    /// "earlier" — named for VoiceOver, which cannot reach a child of an
    /// `.ignore` element.
    var secondary: (title: String, action: () -> Void)?
    @ViewBuilder var content: () -> Content

    @Environment(\.pulseEditing) private var editing

    init(_ title: String, trailing: String? = nil, spoken: String,
         action: @escaping () -> Void, secondary: (title: String, action: () -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.spoken = spoken
        self.action = action
        self.secondary = secondary
        self.content = content
    }

    var body: some View {
        Group {
            // ── NOT A BUTTON WHILE EDITING (W9) ─────────────────────────────
            // `Arrangeable`'s `.draggable` wants the long press, and a button's
            // own recogniser would race it. The face is the same view either
            // way; only the chrome that makes it a control comes and goes —
            // which is also what stops a tap opening a sheet mid-arrangement.
            if editing {
                face.transition(.identity)
            } else {
                Button(action: action) { face }
                    .buttonStyle(.plain)
                    .onyxPress(scale: 0.98)
                    .transition(.identity)
            }
        }
        // ── SQUARE BY RATIO, NOT BY A HEIGHT ────────────────────────────────
        // A fixed height would be wrong on every phone but the one it was
        // measured on, and would stop being square the moment the list's
        // gutter changed. `.fit` inside a flexible grid column takes the width
        // the grid gives and makes the height match it.
        .aspectRatio(1, contentMode: .fit)
        .onyxGlass(.tile)
        .foregroundStyle(Color.onyx.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(spoken)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(editing ? "Editing. Double-tap and hold to drag." : "")
        .accessibilityActions {
            if let secondary { Button(secondary.title, action: secondary.action) }
        }
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            header
            Spacer(minLength: 0)
            content()
        }
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(.rect)
    }

    /// The same `ViewThatFits` escape `DayTile` and `PulseCard` take: half a
    /// phone is 139 pt of content, and at xxxLarge "Stress index" and "14 days"
    /// are each most of that.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.xs) {
                OnyxSectionHeader(title, .recover)
                Spacer(minLength: 0)
                trailingText
            }
            VStack(alignment: .leading, spacing: 0) {
                OnyxSectionHeader(title, .recover)
                trailingText
            }
        }
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

/// A figure and the word for its unit, on one baseline.
///
/// `.display` and not `.hero`: `OnyxType.hero` allows one per screen and the Now
/// strip's Score has it (W2). A 28 pt numeral in a 139 pt box would also leave
/// the trace under it no room, which is the other half of why the tile this
/// replaces could not be a square.
private struct SquareReading: View {
    let value: String
    let unit: String?
    var tint: Color = Color.onyx.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.xs) {
            Text(value)
                .onyxType(.display).onyxNumeral()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let unit {
                Text(unit)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// The line a square falls back to when the day has no reading — never a zero,
/// which is a different fact (`DayFormat.number`).
private struct SquareBlank: View {
    let text: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .onyxType(.secondary)
                .foregroundStyle(Color.onyx.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let detail {
                Text(detail)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The verb a square that ASKS carries on its face — "Rate after training",
/// "Log stress". The square is the control; this line says what it does.
private struct SquareVerb: View {
    let title: String

    var body: some View {
        Text(title)
            .onyxType(.caption).fontWeight(.semibold)
            .foregroundStyle(Color.onyx.accent(.recover))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Stress index

/// One number, its band word and the fortnight behind it (§U5.3).
///
/// The trace keeps its dotted 50 — YOUR own normal — and is NOT zero-based: the
/// reachable range is 10–90 and the interesting variation is a handful of points
/// either side of the rule, which a zero base flattens into a line at four
/// fifths height.
private struct StressSquare: View {
    let model: DayModel
    let action: () -> Void

    private var today: StressDay? { model.stress }
    private var band: StressBand? { today?.band }
    private var tint: Color { band?.tint ?? Color.onyx.textSecondary }

    /// A day nobody answered is DROPPED rather than plotted: `Sparkline` is a
    /// curve with no notion of a hole, and a zero there draws a cliff to the
    /// floor of a scale whose floor is 10.
    private var trace: [Double] { model.stressSeries.compactMap(\.index) }

    var body: some View {
        // "Stress index", not "Stress": the stress LOG card is one row above
        // this grid, and one word on two features is a screen where neither can
        // be read. See `PulseStressLog.swift`'s header.
        SquareShell("Stress index", trailing: "14 days", spoken: spoken, action: action) {
            if let index = today?.index {
                SquareReading(value: "\(Int(index))", unit: band?.word, tint: tint)
            } else {
                SquareBlank(text: "No reading")
            }
            sparkline
        }
    }

    @ViewBuilder
    private var sparkline: some View {
        if trace.count >= 2 {
            Sparkline(points: trace, baseline: 50, color: tint)
                .frame(maxWidth: .infinity, minHeight: 28)
                .accessibilityHidden(true)
        } else {
            Text("not enough days")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var spoken: String {
        guard let today, let index = today.index else { return "no reading for this day" }
        return "\(Int(index)), \(today.band?.word ?? "unbanded"). 50 is your normal."
    }
}

// MARK: - Soreness

/// How much of you is sore, and the worst of it — the door to the body it hurts
/// on.
///
/// ── THE FIGURE IS NOT THE CONTROL HERE, BUT IT IS THE SUBJECT ───────────────
/// The atlas is 280–360 pt on `DomsTile` and it is a CONTROL there: a quad has
/// to be a target a thumb can hit. That is still true, and it is still why the
/// rating verb lives in the sheet and not on this square.
///
/// What was wrong was the EMPTY state. A square reading "Nothing sore / Tap to
/// rate" over an otherwise blank 163 pt box is indistinguishable from a square
/// that failed to load — which is the report: it "looks completely empty and
/// broken". Every other square in this grid keeps its shape when it has nothing
/// to say, because a trace with no data is still a trace and a numeral slot is
/// still a numeral slot. This one had nothing to keep.
///
/// So the body is always drawn, at 96 pt on the trailing edge, as the square's
/// own MARK rather than as a control — the same thing the Stack square's dots
/// and the Scale square's trace are. It is `isThumbnail`, so it costs no
/// offscreen shadow pass, and it is inert: the tap target is the whole square,
/// exactly as it was, and it still opens the sheet where the figure is big
/// enough to aim at.
///
/// When there IS soreness the same figure paints it, on the side that carries
/// it. That is the second half of why the placeholder is the body and not a
/// glyph: an empty state that turns into the reading is one shape a reader
/// learns once, where an icon that is REPLACED by a number is two.
private struct SorenessSquare: View {
    let model: DayModel
    let action: () -> Void

    /// 96 pt, and capped: the atlas is 120 × 260, so height is what buys width,
    /// and a figure taller than the square's own 139 pt of content would push
    /// the reading off its floor.
    @ScaledMetric(relativeTo: .body) private var figureHeight: CGFloat = 96

    private var sore: [(group: String, level: Int)] { Soreness.worstFirst(model.domsSeverity) }

    var body: some View {
        SquareShell("Soreness", spoken: spoken, action: action) {
            HStack(alignment: .bottom, spacing: OnyxSpace.s) {
                VStack(alignment: .leading, spacing: 2) {
                    if sore.isEmpty {
                        SquareBlank(text: "Nothing sore", detail: "Tap to rate")
                    } else {
                        SquareReading(
                            value: "\(sore.count)",
                            unit: "sore",
                            tint: Color.onyx.severity(sore[0].level)
                        )
                        Text(Soreness.line(sore))
                            .onyxType(.caption)
                            .foregroundStyle(Color.onyx.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                figure
            }
        }
    }

    /// The mark. `allowsHitTesting(false)` because the SQUARE is the button and
    /// a figure that swallowed the tap would make the one corner of the card
    /// that looks most tappable the one corner that does nothing.
    private var figure: some View {
        let painted = painting
        return AtlasFigure(
            side: painted.side,
            worked: painted.worked,
            monochromeTint: Color.onyx.textTertiary,
            isThumbnail: true,
            colors: painted.colors
        )
        .frame(height: min(figureHeight, 120))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Which body to draw, and what to paint on it.
    ///
    /// ── THE SIDE FOLLOWS THE SORENESS, AND DEFAULTS TO THE FRONT ────────────
    /// One body, not two: at this width a front-and-back pair is two 44 pt
    /// figures and neither is legible. So the square shows the side that
    /// actually carries something — hamstrings and lats are back-only, and a
    /// front figure would have drawn a blank body over the words "2 sore",
    /// which is worse than the empty state this replaces.
    ///
    /// Front when the soreness is on the front, or when there is none at all:
    /// a placeholder has no side to follow and the front is the body a reader
    /// recognises fastest.
    ///
    /// `worked` is 1 for every sore landmark because `AtlasFigure` gates its
    /// tint on the WORKED amount — that channel is modelled fatigue on
    /// `DomsTile` and this square does not draw it, so the amount here is only
    /// the switch that lets the colour through. The colour is the whole signal.
    ///
    /// Severities are max-merged and THEN coloured, the same rule `DomsTile`
    /// follows and for the same reason: two `Color`s have no order.
    private var painting: (side: AtlasFigure.Side, worked: [LandmarkMuscle: Double], colors: [MuscleSide: Color]) {
        var levels: [MuscleSide: Int] = [:]
        var worked: [LandmarkMuscle: Double] = [:]
        for row in model.doms where row.severity > 0 {
            for landmark in DomsMap.landmarks[row.muscleGroup] ?? [] {
                worked[landmark] = 1
                let key = MuscleSide(landmark, row.bodySide)
                levels[key] = max(levels[key] ?? 0, row.severity)
            }
        }
        let front = Set(OnyxAtlas.muscles.filter { $0.view == .front }.map(\.muscle))
        let showsFront = worked.isEmpty || worked.keys.contains { front.contains($0.rawValue) }
        return (
            side: showsFront ? .front : .back,
            worked: worked,
            colors: levels.mapValues { Color.onyx.severity($0) }
        )
    }

    private var spoken: String {
        sore.isEmpty ? "nothing sore" : Soreness.spoken(sore)
    }
}

/// The soreness fold, shared by the square and its AX5 row.
///
/// `DomsMap.muscles` order is the tie-break rather than the dictionary's, so
/// the list is stable between ratings — a dictionary order reshuffles the words
/// on every tap.
enum Soreness {
    static func worstFirst(_ severity: [String: Int]) -> [(group: String, level: Int)] {
        DomsMap.muscles
            .compactMap { group -> (group: String, level: Int)? in
                guard let level = severity[group], level > 0 else { return nil }
                return (group, level)
            }
            .enumerated()
            .sorted { a, b in
                a.element.level != b.element.level ? a.element.level > b.element.level : a.offset < b.offset
            }
            .map(\.element)
    }

    /// The worst two, named. Two rather than three: a square is 139 pt of
    /// content and "Hamstrings, Quads, Glutes" is three lines of it.
    static func line(_ sore: [(group: String, level: Int)]) -> String {
        let shown = sore.prefix(2).map(\.group).joined(separator: ", ")
        let hidden = sore.count - min(2, sore.count)
        return hidden > 0 ? "\(shown)\u{00A0}+\(hidden)" : shown
    }

    static func spoken(_ sore: [(group: String, level: Int)]) -> String {
        sore
            .map { "\($0.group) \(DomsMap.levels[min($0.level, DomsMap.maxSeverity)].lowercased())" }
            .joined(separator: ", ")
    }
}

// MARK: - Scale

/// What the scale said, and the weeks behind it.
///
/// The row this replaces printed weight, fat and skeletal muscle on one line and
/// had no room for a trend at all — which is the one thing a bodyweight reading
/// is for. The square keeps the two figures a recovery screen reads (`weight`
/// and `fat %`; the seven metrics live in the form and in Body trends) and puts
/// the fortnight under them.
private struct ScaleSquare: View {
    let model: DayModel
    let action: () -> Void

    @State private var choosingReason = false

    private var log: DailyLogRow? { model.log }

    @Environment(\.pulseEditing) private var editing

    var body: some View {
        Group {
            // Never in edit mode: a context menu eats the long press the drag
            // needs (`DashboardGrid` states the same rule for `TileMenu`).
            if editing { square.transition(.identity) } else { square.contextMenu { menu }.transition(.identity) }
        }
        .confirmationDialog("Why no weigh-in?", isPresented: $choosingReason, titleVisibility: .visible) {
            ForEach(WeighIn.skipReasons, id: \.self) { reason in
                Button(reason) { model.setWeighInSkipReason(reason) }
            }
        } message: {
            Text("Currently \(WeighIn.skipReason(log?.weighinSkipReason)). \"\(WeighIn.skipReason(nil))\" is the protocol and is not stored.")
        }
    }

    private var square: some View {
        SquareShell("Scale", spoken: spoken, action: action) {
            if let weight = log?.weightKg {
                SquareReading(value: DayFormat.number(weight), unit: "kg")
                if let fat = log?.bodyFatPct {
                    Text("\(DayFormat.number(fat)) % fat")
                        .onyxType(.caption).onyxNumeral()
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                }
                trace
            } else {
                SquareBlank(text: "No weigh-in", detail: WeighIn.skipReason(log?.weighinSkipReason))
                trace
            }
        }
    }

    /// The reason is a SECOND control on a surface that has room for one, so
    /// it is a long press — the same affordance, and the same dialog, the row
    /// this square replaces carried.
    @ViewBuilder
    private var menu: some View {
        Button("Enter InBody reading", systemImage: "square.and.pencil", action: action)
        if log?.weightKg == nil {
            Button("Why no weigh-in…", systemImage: "questionmark.circle") { choosingReason = true }
        }
    }

    /// NOT zero-based, and the `Sparkline` header says why in as many words:
    /// zero-basing a 78-to-80 kg fortnight flattens the only signal in it.
    ///
    /// Sparse on purpose — a weigh-in happens twice a week, so the 49 days the
    /// window reads yield a dozen or so points and the curve is the shape of
    /// the weigh-ins rather than of the calendar.
    @ViewBuilder
    private var trace: some View {
        let points = model.weightTrace
        if points.count >= 2 {
            Sparkline(points: points, color: Color.onyx.accent(.body))
                .frame(maxWidth: .infinity, minHeight: 24)
                .accessibilityHidden(true)
        }
    }

    private var spoken: String {
        guard let weight = log?.weightKg else {
            return "no weigh-in, \(WeighIn.skipReason(log?.weighinSkipReason))"
        }
        var parts = ["\(DayFormat.number(weight)) kilos"]
        if let fat = log?.bodyFatPct { parts.append("\(DayFormat.number(fat)) percent fat") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Fatigue

/// How tired you said you were, and the slot the day is asking about.
///
/// The carousel page this replaces (W3–W8) carried the sheet's door as a 44 pt
/// verb on its face. A square IS the door, so the verb is one accent line —
/// and it still names the slot, because "Rate after training" and "Rate
/// waking" are different questions. The WORD is the reading: nothing here is a
/// numeral, which belongs to the stress index and to nothing else.
private struct FatigueSquare: View {
    let model: DayModel
    let action: () -> Void

    private var day: FatigueDay { model.fatigue }
    private var slots: [FatigueSlot] { model.fatigueSlots }
    private var latest: FatigueReading? { Fatigue.latest(day) }
    private var logged: Int { slots.filter { day[$0] != nil }.count }
    /// The slot the day is asking for now (W10) — before the session, after
    /// it, or the rest day's hour. The empty dot for it is drawn in the accent.
    private var ask: FatigueSlot { model.fatigueAsk }

    var body: some View {
        SquareShell("Fatigue", trailing: "\(logged) of \(slots.count)", spoken: spoken, action: action) {
            reading
            slotRow
            SquareVerb(title: "Rate \(ask.label.lowercased())")
        }
    }

    @ViewBuilder
    private var reading: some View {
        if let latest, let word = Fatigue.level(latest.level)?.label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                    Text(word)
                        .onyxType(.secondary).fontWeight(.semibold)
                        .foregroundStyle(Color.onyx.fatigue(latest.level))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    cost
                }
                Text(latest.slot.label)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .lineLimit(1)
            }
        } else {
            SquareBlank(text: "Not rated")
        }
    }

    /// One dot per slot the day HAS (`Fatigue.slotsForDay`), named short —
    /// the same filled-versus-stroked vocabulary the Stack square's dots use.
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
                    Text(slot.short)
                        .onyxType(.micro)
                        // A legend label, not a unit: secondary (W6 polish).
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    /// What the session cost, `post` − `pre`. Absent on a rest day and while
    /// one end is unrated; `costSpoken` names the missing end for VoiceOver.
    @ViewBuilder
    private var cost: some View {
        if let delta = Fatigue.delta(day) {
            Text("\(delta >= 0 ? "+" : "")\(delta)")
                .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                .foregroundStyle(delta > 1 ? Color.onyx.record : Color.onyx.textSecondary)
                .padding(.horizontal, OnyxSpace.s)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.onyx.hairline))
        }
    }

    private var spoken: String {
        let verb = "Rate \(ask.label.lowercased())"
        guard let latest, let word = Fatigue.level(latest.level)?.label else { return "not rated. \(verb)" }
        return "\(word), \(latest.slot.label)\(costSpoken). \(verb)"
    }

    private var costSpoken: String {
        if let delta = Fatigue.delta(day) { return ", session cost \(delta >= 0 ? "+" : "")\(delta)" }
        if let missing = Fatigue.deltaMissing(day), slots.contains(missing) { return ", \(missing.label.lowercased()) not rated" }
        return ""
    }
}

// MARK: - Stress log

/// What you typed, when you typed it — the day's readings as stamps, and the
/// door that adds one.
///
/// ── TWO THINGS CALLED STRESS, TWO SQUARES APART ─────────────────────────────
/// `StressSquare` is the INDEX: 0–100, computed, against your own fortnight.
/// This is the LOG: any number of 1–5 readings a day, each stamped, and an
/// input to the index. Four rules keep them apart on one grid:
///   • the numeral is the index's and only the index's — nothing here is
///     above `.secondary`, and the only figures are clock stamps;
///   • the axis differs — "14 days" against "N today";
///   • the ink differs — `StressBand.tint` there, `Color.onyx.fatigue(level)`
///     here, the shared severity ramp the Fatigue square also wears;
///   • the posture differs — that square opens a read-only breakdown, this
///     one carries its verb.
///
/// The last two readings, newest at the bottom as the day happened, and the
/// ones before them behind a marker standing where they would have been —
/// leading, because a marker on the trailing edge would claim the hidden ones
/// came last. Two, because a square is 139 pt of content and a stamp is a
/// line of it. Delete lives in the full log (`StressLogListSheet`), whose
/// rows have a swipe to give; a context menu here would eat the drag.
private struct StressLogSquare: View {
    let model: DayModel
    let action: () -> Void
    let onBrowse: () -> Void

    private var readings: [StressReading] { model.stressReadings }
    private var shown: [StressReading] { Array(readings.suffix(2)) }
    private var hidden: Int { max(0, readings.count - shown.count) }

    var body: some View {
        SquareShell(
            "Stress log",
            // "today" only on today: `DayScreen` draws past dates too.
            trailing: readings.isEmpty ? nil : "\(readings.count) \(model.isToday ? "today" : "logged")",
            spoken: spoken, action: action,
            secondary: hidden > 0 ? ("Browse the whole day's log", onBrowse) : nil
        ) {
            if readings.isEmpty {
                // Not "0": a day nobody answered is a different fact from a
                // calm one (`DayFormat.number`'s rule).
                SquareBlank(text: "Not reported")
            } else {
                VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                    earlier
                    ForEach(shown) { reading in capsule(reading) }
                }
            }
            SquareVerb(title: "Log stress")
        }
    }

    @ViewBuilder
    private var earlier: some View {
        if hidden > 0 {
            Button(action: onBrowse) {
                Text("+\(hidden) earlier")
                    .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                    .foregroundStyle(Color.onyx.textSecondary)
                    .padding(.horizontal, OnyxSpace.s)
                    .frame(minHeight: 24)
                    .background(Capsule().fill(Color.onyx.hairline))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func capsule(_ reading: StressReading) -> some View {
        Text(StressStamp.label(reading))
            .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
            .foregroundStyle(Color.onyx.fatigue(reading.level))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, OnyxSpace.s)
            .frame(minHeight: 24)
            .background(Capsule().fill(Color.onyx.fatigue(reading.level).opacity(0.16)))
    }

    private var spoken: String {
        guard !readings.isEmpty else { return "not reported. Log stress" }
        let latest = shown.map(StressStamp.spoken).joined(separator: "; ")
        return latest + (hidden > 0 ? "; \(hidden) earlier" : "") + ". Log stress"
    }
}

// MARK: - Stack

/// How much of the protocol has counted today, and one dot per dose.
///
/// ── ABSENCE IS THE PROTOCOL ─────────────────────────────────────────────────
/// The stack is what happens by default and `supplement_log` holds only the
/// exceptions, so what counts is a question about the CLOCK as much as about the
/// log: a dose with no row counts once its slot has passed. The numerator is
/// therefore `credited`, which is what the day's micronutrients are actually
/// built from — not "not skipped".
///
/// ── AND AT THE END OF THE DAY THE DOTS HAVE NOTHING LEFT TO SAY ─────────────
/// The dot row is a row of ANSWERED-versus-AHEAD, and its whole job is to say
/// how much of the day is still in front of you. Once nothing is ahead it is
/// eight identical filled dots — a shape carrying one bit of information that
/// the numeral two lines above it already carried, drawn eight times.
///
/// So when the day is done the dots give way to the doses themselves: up to
/// five overlapping discs in each supplement's own colour, newest first, and
/// the time the last one was due. The square stops reporting progress, which is
/// finished, and starts reporting what the evening actually contained.
private struct StackSquare: View {
    let model: DayModel
    let action: () -> Void

    private var doses: [SupplementDose] { model.doses }
    private var credited: Int { doses.filter(\.credited).count }

    var body: some View {
        SquareShell("Stack", spoken: spoken, action: action) {
            if doses.isEmpty {
                SquareBlank(text: "Nothing scheduled")
            } else {
                SquareReading(value: "\(credited)/\(doses.count)", unit: "counted")
                if dayIsDone, !recent.isEmpty {
                    capsules
                    Text(lastLine)
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    dots
                }
            }
        }
    }

    // MARK: The end of the day

    /// Nothing is still ahead.
    ///
    /// ── THE CLOCK IS ALREADY IN THE DATA ────────────────────────────────────
    /// `DoseState.later` means "no row, and the slot is still ahead", which is
    /// resolved against `DayClock` before a dose ever reaches this view. So
    /// "the day is over" is `no dose is still later` and needs no second clock
    /// here — and it is right for a PAST day too, where every slot has passed,
    /// which a `now`-based test would have had to special-case.
    private var dayIsDone: Bool { !doses.contains { $0.state == .later } }

    /// What was actually taken, newest first, at most five.
    ///
    /// Credited rather than `taken`: absence IS the protocol (see the header),
    /// so a dose nobody said anything about counts once its slot has passed and
    /// belongs in the pile. A `skipped` dose does not — it is the one thing on
    /// this square that did not happen.
    private var recent: [SupplementDose] {
        doses.filter(\.credited)
            .sorted { Self.minutes($0.slotTime) > Self.minutes($1.slotTime) }
    }

    /// Five, because five 16 pt discs overlapped by six fit the square's 139 pt
    /// of content with room for the `+N` and nothing wider does.
    private var shown: [SupplementDose] { Array(recent.prefix(5)) }
    private var hidden: Int { recent.count - shown.count }

    /// The pile. Newest on the LEADING edge and on top, which is the order the
    /// eye reads and the opposite of what an `HStack` stacks by default — hence
    /// the explicit `zIndex`.
    ///
    /// A dark rim rather than a gap: overlapping is what says "these happened
    /// together, recently", and six points of overlap with no rim is one wide
    /// blob. The rim belongs to the disc ABOVE, so it draws over the one below
    /// and cuts the crescent that makes the pile legible.
    private var capsules: some View {
        HStack(spacing: -6) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, dose in
                Circle()
                    .fill(Color.onyx.supplement(model.custom(for: dose)?.color))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 1.5))
                    .zIndex(Double(shown.count - index))
            }
            if hidden > 0 {
                Text("+\(hidden)")
                    .onyxMicro()
                    .padding(.leading, OnyxSpace.xs + 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// `21:30 · Magnesium` on a short stack, `last 21:30` on a long one.
    ///
    /// The founder's rule, and the reason for it is width: the caption shares
    /// one line with nothing, but at four or five discs the name of the last
    /// dose is what gets scaled down to illegibility. A stack of three or fewer
    /// has the room, and on a stack that small the NAME is the interesting half
    /// — "Magnesium" says the evening happened in a way "last 21:30" does not.
    private var lastLine: String {
        guard let last = shown.first else { return "" }
        return doses.count <= 3 ? "\(last.slotTime) · \(last.name)" : "last \(last.slotTime)"
    }

    /// `"21:30"` → 1290. The same parse `Supplements.slotTimePassed` makes, for
    /// ordering rather than for comparison against a clock. A slot time this
    /// cannot read sorts last rather than crashing — a malformed row must not
    /// take the square down with it.
    private static func minutes(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let m = Int(parts[1].trimmingCharacters(in: .whitespaces))
        else { return -1 }
        return h * 60 + m
    }

    /// One dot per scheduled dose, in the day's own time order.
    ///
    /// Filled for what has counted, hollow for what is still ahead, and the
    /// hairline fill for a dose said no to — the same filled-versus-stroked
    /// vocabulary `FatigueSquare`'s slot row uses in the same grid, so the
    /// screen has one language for "answered" rather than two.
    ///
    /// `FlowRow` because a nine-item stack is wider than 139 pt and a square
    /// cannot grow sideways; it wraps between dots and never inside one.
    private var dots: some View {
        FlowRow(spacing: OnyxSpace.xs) {
            ForEach(doses) { dose in
                Group {
                    switch dose.state {
                    case .taken, .due:
                        Circle().fill(Color.onyx.accent(.fuel))
                    case .later:
                        Circle().strokeBorder(Color.onyx.textTertiary, lineWidth: 1)
                    case .skipped:
                        Circle().fill(Color.onyx.hairline)
                    }
                }
                .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    private var spoken: String {
        guard !doses.isEmpty else { return "nothing scheduled" }
        let later = doses.filter { $0.state == .later }.count
        let skipped = doses.filter { $0.state == .skipped }.count
        return "\(credited) of \(doses.count) counted, \(later) still ahead, \(skipped) skipped"
    }
}

// MARK: - The AX5 rows

/// The index as a row. `ScaleRow` and `StackRow` already exist and are used
/// unchanged; these two are the squares that had no row before.
private struct StressIndexRow: View {
    let model: DayModel
    let onOpen: () -> Void

    private var today: StressDay? { model.stress }
    private var index: Int? { today?.index.map { Int($0) } }
    private var word: String { today?.band?.word ?? "unbanded" }

    var body: some View {
        PulseRow(
            symbol: "waveform.path.ecg",
            title: "Stress index",
            detail: index.map { "\($0) · \(word)" } ?? "No reading",
            tint: Color.onyx.accent(.recover),
            spoken: index.map { "\($0), \(word). 50 is your normal." } ?? "no reading for this day",
            action: onOpen
        )
    }
}

private struct FatigueRow: View {
    let model: DayModel
    let onOpen: () -> Void

    private var latest: FatigueReading? { Fatigue.latest(model.fatigue) }

    var body: some View {
        let word = latest.flatMap { Fatigue.level($0.level)?.label }
        PulseRow(
            symbol: "battery.50",
            title: "Fatigue",
            detail: word.map { "\($0) · \(latest!.slot.label)" } ?? "Not rated",
            tint: Color.onyx.accent(.recover),
            spoken: (word.map { "\($0), \(latest!.slot.label)" } ?? "not rated") + ". Rate \(model.fatigueAsk.label.lowercased())",
            action: onOpen
        )
    }
}

private struct StressLogRow: View {
    let model: DayModel
    let onLog: () -> Void
    let onBrowse: () -> Void

    private var readings: [StressReading] { model.stressReadings }

    var body: some View {
        PulseRow(
            symbol: "plus.circle.fill",
            title: "Stress log",
            detail: readings.last.map { "\(readings.count) \(model.isToday ? "today" : "logged")\u{00A0}· \(StressStamp.label($0))" } ?? "Not reported",
            tint: Color.onyx.accent(.recover),
            spoken: (readings.last.map { "\(readings.count) logged, latest \(StressStamp.spoken($0))" } ?? "not reported") + ". Log stress",
            action: onLog
        ) {
            // The whole day's log, which the square reaches through "earlier".
            if readings.count > 1 {
                Button("All", action: onBrowse)
                    .onyxType(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color.onyx.accent(.recover))
                    .accessibilityLabel("Browse the whole day's log")
            }
        }
    }
}

private struct SorenessRow: View {
    let model: DayModel
    let onOpen: () -> Void

    private var sore: [(group: String, level: Int)] { Soreness.worstFirst(model.domsSeverity) }

    var body: some View {
        PulseRow(
            symbol: "figure.arms.open",
            title: "Soreness",
            detail: sore.isEmpty ? "Nothing sore" : "\(sore.count) sore · \(Soreness.line(sore))",
            tint: Color.onyx.accent(.recover),
            spoken: sore.isEmpty ? "nothing sore" : Soreness.spoken(sore),
            action: onOpen
        )
    }
}
