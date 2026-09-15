import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

// ─────────────────────────────────────────────────────────────────────────────
// THE FOUR SQUARES (founder decision 5).
//
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

/// Stress index · Soreness · Scale · Stack.
///
/// Every door is a closure: this whole grid is one `List` row, and a `.sheet`
/// declared on a recyclable cell is torn down with the cell — the same rule
/// `StressLogCard` states and the reason `DayScreen` owns every presentation on
/// this screen.
struct PulseSquareGrid: View {
    let model: DayModel
    let onStress: () -> Void
    let onSoreness: () -> Void
    let onScale: () -> Void
    let onStack: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// `OnyxSpace.l` between the cells, as decision 5 asks — and the same 16 pt
    /// the list already insets this row by, so the trench between two squares
    /// is the trench at the screen's edge and the grid reads as a grid rather
    /// than as four tiles that drifted together.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.l), count: 2)
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            StressIndexRow(model: model, onOpen: onStress)
            SorenessRow(model: model, onOpen: onSoreness)
            ScaleRow(model: model, onEnter: onScale)
            StackRow(model: model, onOpen: onStack)
        } else {
            LazyVGrid(columns: columns, spacing: OnyxSpace.l) {
                StressSquare(model: model, action: onStress)
                SorenessSquare(model: model, action: onSoreness)
                ScaleSquare(model: model, action: onScale)
                StackSquare(model: model, action: onStack)
            }
        }
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
private struct PulseSquare<Content: View>: View {
    let title: String
    /// The unit that names the square's axis — "14 days" against the log card's
    /// "3 today". Nil draws nothing rather than an empty slot.
    var trailing: String?
    /// What a reader who cannot see the square is told, after its title.
    let spoken: String
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    init(_ title: String, trailing: String? = nil, spoken: String,
         action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.spoken = spoken
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                header
                Spacer(minLength: 0)
                content()
            }
            .padding(OnyxSpace.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.98)
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
        PulseSquare("Stress index", trailing: "14 days", spoken: spoken, action: action) {
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
/// ── THE FIGURE IS NOT DRAWN HERE, AND NEVER WAS ─────────────────────────────
/// The atlas is 280–360 pt before its caption and it is a CONTROL: a quad has to
/// be a target a thumb can hit. Shrunk into a 163 pt square it is neither
/// readable nor tappable, which is the failure `DomsTile`'s own header records
/// from the tile before it. So this square states the answer the map would give
/// and hands the reader to `SorenessSheet`, where the figure is at the size it
/// is a control at and the severity popover already lives.
private struct SorenessSquare: View {
    let model: DayModel
    let action: () -> Void

    private var sore: [(group: String, level: Int)] { Soreness.worstFirst(model.domsSeverity) }

    var body: some View {
        PulseSquare("Soreness", spoken: spoken, action: action) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
        return hidden > 0 ? "\(shown) +\(hidden)" : shown
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

    var body: some View {
        PulseSquare("Scale", spoken: spoken, action: action) {
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
        // The reason is a SECOND control on a surface that has room for one, so
        // it is a long press — the same affordance, and the same dialog, the row
        // this square replaces carried.
        .contextMenu {
            Button("Enter InBody reading", systemImage: "square.and.pencil", action: action)
            if log?.weightKg == nil {
                Button("Why no weigh-in…", systemImage: "questionmark.circle") { choosingReason = true }
            }
        }
        .confirmationDialog("Why no weigh-in?", isPresented: $choosingReason, titleVisibility: .visible) {
            ForEach(WeighIn.skipReasons, id: \.self) { reason in
                Button(reason) { model.setWeighInSkipReason(reason) }
            }
        } message: {
            Text("Currently \(WeighIn.skipReason(log?.weighinSkipReason)). \"\(WeighIn.skipReason(nil))\" is the protocol and is not stored.")
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

// MARK: - Stack

/// How much of the protocol has counted today, and one dot per dose.
///
/// ── ABSENCE IS THE PROTOCOL ─────────────────────────────────────────────────
/// The stack is what happens by default and `supplement_log` holds only the
/// exceptions, so what counts is a question about the CLOCK as much as about the
/// log: a dose with no row counts once its slot has passed. The numerator is
/// therefore `credited`, which is what the day's micronutrients are actually
/// built from — not "not skipped".
private struct StackSquare: View {
    let model: DayModel
    let action: () -> Void

    private var doses: [SupplementDose] { model.doses }
    private var credited: Int { doses.filter(\.credited).count }

    var body: some View {
        PulseSquare("Stack", spoken: spoken, action: action) {
            if doses.isEmpty {
                SquareBlank(text: "Nothing scheduled")
            } else {
                SquareReading(value: "\(credited)/\(doses.count)", unit: "counted")
                dots
            }
        }
    }

    /// One dot per scheduled dose, in the day's own time order.
    ///
    /// Filled for what has counted, hollow for what is still ahead, and the
    /// hairline fill for a dose said no to — the same filled-versus-stroked
    /// vocabulary `FatigueCard`'s slot row uses two rows above this one, so the
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
