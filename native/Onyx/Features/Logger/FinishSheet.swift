import SwiftUI
import OnyxUI
import OnyxCore

/// How the session ends.
///
/// ── WHY A SHEET AND NOT A CONFIRMATION DIALOG ───────────────────────────────
/// Wave 1 ended a workout with `confirmationDialog("Finish this session?")` —
/// two buttons and a sentence of totals. That is the right control for a
/// destructive action and finishing is not one: it is the moment the session
/// becomes history, the only moment a session RPE can be asked for, and the
/// last thing you see before putting the phone away. A dialog can hold none of
/// that, and a dialog is also the wrong shape for a decision you might want to
/// look at first — you cannot scroll it, and you cannot leave it half open.
///
/// `.presentationDetents([.medium, .large])` gives both: the whole summary as
/// it opens, the dial alone by dragging down, and the same interruptible grab
/// every other sheet in the app has. Which one it ARRIVES at is `detent`.
///
/// ── AND WHAT THE SUMMARY BECAME ─────────────────────────────────────────────
/// It was five label-and-value rows in one glass box — a settings screen wearing
/// a workout's numbers, where the tonnage of a session read with exactly the
/// weight of a preference. A session's figures are not a list; they are a set of
/// readings, each glanceable on its own, which is a grid of tiles.
///
/// The grid also has room for what the rows never carried. `duration`, `avg hr`
/// and `calories` were three editable badges at the TOP of the web deck, asked
/// for throughout a session that had not happened yet; here they are answered at
/// the only moment anyone can answer them — and two of the three are usually not
/// questions at all, because the watch already knows. See `metricTile`.
struct FinishSheet: View {
    let model: LoggerModel
    /// Returns false when there was nothing to finish; the sheet stays up.
    let onFinish: (Double?) -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppEnvironment.self) private var environment

    /// ── WHY IT OPENS LARGE ─────────────────────────────────────────────────
    /// The dial is 168 pt and it is the first thing in the sheet, so at the
    /// `.medium` detent it and its caption ARE the sheet — the six readings
    /// below it sat entirely under the pinned Finish button, on the one screen
    /// whose job is to show you what the session came to. Both detents still
    /// exist and the grab handle still works; this only decides which one it
    /// arrives at, and the answer is the one where the summary is a summary.
    @State private var detent: PresentationDetent = .large
    /// The WORD, which is the answer. `nil` is an unrated session and stays
    /// one: `session_rpe` is nullable in the store precisely so "I did not say"
    /// survives, and a dial that arrives on a value would write that value for
    /// everyone who never touched it.
    ///
    /// It arrives PRE-SELECTED from `Effort.suggestEffortWord` — a proposal,
    /// not an answer, which is why `suggested` is tracked separately and the
    /// caption says where the word came from.
    @State private var word: EffortWord?
    @State private var suggested: EffortWord?

    /// The three figures as they stand on disk when the sheet opens.
    ///
    /// Held in `@State` rather than re-read on every draw because they are also
    /// EDITABLE, and a field bound to a store read fights the person typing into
    /// it — the same reason `NumericField` keeps its own string.
    @State private var durationMin: Int?
    @State private var avgBpm: Int?
    @State private var calories: Int?
    @State private var durationEdited = false
    @State private var bpmMeasured = false
    @State private var caloriesMeasured = false
    /// Which of the three are still showing the PREVIOUS session's figure
    /// rather than this one's. They are written as estimates, not as answers,
    /// and they say so on the tile — see `loadMetrics` and `commitMetrics`.
    /// Touching a cell takes it out of the set, because a carried-over number
    /// that a person then corrected is a person's number.
    @State private var prefilled: Set<Metric> = []
    /// Which cell is open as a stepper. One at a time: three steppers side by
    /// side on a phone is three two-point targets.
    @State private var open: Metric?
    /// The last few sessions of this split by tonnage, with this one on the end
    /// (W10). `@State` for the reason the three figures above are: it is a
    /// store read, and a read in `body` runs once per frame.
    @State private var trail: [Double] = []
    @FocusState private var editing: Metric?

    private enum Metric: Hashable { case duration, bpm, calories }

    private var accent: Color { Color.onyx.day(model.day.key) }

    /// Three across, until the type size says otherwise. Six tiles is two clean
    /// rows of three on a phone; at an accessibility size three of them is three
    /// truncated numbers, which is the one thing a reading must never be.
    private var columns: Int {
        if typeSize.isAccessibilitySize { return 1 }
        return typeSize >= .xxLarge ? 2 : 3
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OnyxSpace.l) {
                    dial
                    summary
                    shape
                    if !topMovement.isEmpty { heaviest }
                    if let sessionId = model.sessionId { summaryLink(sessionId) }
                }
                .padding(OnyxSpace.l)
            }
            // ── WHY THE BUTTON IS PINNED ────────────────────────────────────
            // It was the last view in the scroll view, and at the `.medium`
            // detent the dial and the caption fill the sheet — so the screen
            // called "Finish" had no visible way to finish, at both type
            // sizes. A primary action never scrolls out of its own sheet.
            .safeAreaInset(edge: .bottom) {
                finishButton
                    .padding(.horizontal, OnyxSpace.l)
                    .padding(.vertical, OnyxSpace.m)
                    .background(.ultraThinMaterial)
            }
            .onyxScreen(.train)
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep logging") { dismiss() }
                }
                if editing != nil {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { editing = nil }
                    }
                }
            }
            .task {
                loadMetrics()
                loadSuggestion()
                trail = model.tonnageTrail()
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    // MARK: - Effort

    /// The dial, and the WORD it is really asking for.
    ///
    /// ── WHY THE NUMBER STOPPED BEING THE ANSWER ─────────────────────────────
    /// The dial reported `8.5` and nothing else, and a point on a ten-point
    /// ratio scale is not something anyone can calibrate from memory between
    /// sessions — "was last Tuesday an 8 or an 8.5" has no honest answer, which
    /// is how a rating given by feel ends up being given by habit.
    ///
    /// Borg's scale has always carried verbal anchors and they are the part
    /// that makes it reproducible. So the dial now has FIVE detents and they
    /// are the five words (`Effort.words`, the same list the web writes): the
    /// word is the largest thing on the sheet, the CR-10 it stores sits small
    /// beneath it, and the ring carries a tick at each stop so the control's
    /// resolution is visible before it is touched. Nothing about what is stored
    /// changed — `session_rpe` still takes the half-point value, which is what
    /// the battery, the score and the weekly export all read.
    ///
    /// ── AND WHY IT OPENS ON A SUGGESTION ────────────────────────────────────
    /// `Effort.suggestEffortWord` grades this session's mean per-set rating
    /// against what this DAY TYPE has recently cost (`effortHistory`), so a
    /// typical session lands on "Hard" rather than on an absolute ladder the
    /// athlete was never calibrated to. It is a proposal: the caption says so,
    /// and clearing it returns the session to unrated.
    private var dial: some View {
        VStack(spacing: OnyxSpace.s) {
            EffortDial(word: $word, accent: accent)
            caption
        }
    }

    @ViewBuilder
    private var caption: some View {
        if let word {
            Text(word.hint)
                .onyxType(.body)
                .foregroundStyle(Color.onyx.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
                .accessibilityHidden(true)
            if word == suggested {
                // Say whose answer this is. A word already on the dial when the
                // sheet opens reads as one the athlete gave, and a suggestion
                // mistaken for an answer is a rating nobody actually made.
                Text("Suggested from your recent \(model.day.label) sessions")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Clear rating") { self.word = nil }
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
                .frame(minHeight: 44)
        } else {
            Text("How hard was the whole session?")
                .onyxType(.body)
                .foregroundStyle(Color.onyx.textSecondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
        }
    }

    // MARK: - The session, as readings

    /// Two rows, and the difference between them is the whole point.
    ///
    /// ── WHAT YOU CAN ANSWER, AND WHAT THE SESSION ANSWERS ───────────────────
    /// The grid used to be six identical tiles in which two were secretly
    /// editable, and the only tell was a tinted border you had to already know
    /// about. Duration, heart rate and calories are the three the athlete may
    /// know better than the phone — the web asked for all three at the TOP of a
    /// deck, before the session had happened — so they are one row of their
    /// own, each with a stepper and a provenance dot. Tonnage, sets and records
    /// are not questions at all; they are what the session came to, and they sit
    /// under it as readings.
    private var summary: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            OnyxSectionHeader("The session", .train)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.s), count: editableColumns),
                spacing: OnyxSpace.s
            ) {
                metricCell(
                    "Duration", "timer", value: $durationMin, unit: "min", step: 5,
                    field: .duration,
                    // A duration carried over from the last session is not the
                    // clock's reading of THIS one, and a green "measured" dot on
                    // it would be the sheet vouching for a number it guessed.
                    provenance: prefilled.contains(.duration) ? .estimated
                        : (durationEdited ? .edited : .measured)
                )
                metricCell(
                    "Avg HR", "heart", value: $avgBpm, unit: "bpm", step: 1,
                    field: .bpm, provenance: provenance(avgBpm, measured: bpmMeasured)
                )
                metricCell(
                    "Calories", "flame", value: $calories, unit: "kcal", step: 10,
                    field: .calories, provenance: provenance(calories, measured: caloriesMeasured)
                )
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.s), count: readingColumns),
                spacing: OnyxSpace.s
            ) {
                tile("Tonnage", "scalemass", OnyxFormat.volumeExact(model.totalVolumeKg), "kg",
                     tint: Color.onyx.textPrimary)
                // ── A FINISHED SESSION HAS NO DENOMINATOR ───────────────────
                // `plannedSets` is `day.plannedSets(for:)`, and on an edit deck
                // `day` is `SessionDetailView.editorDay`'s synthetic day, which
                // appends EVERY unperformed plan movement so a lift you forgot
                // can still be added. So a complete workout read "18/19" — the
                // 19th being a set nobody was ever going to do, on a session
                // that ended three weeks ago.
                //
                // Fixed HERE and not at the day: that appending is deliberate
                // and the deck needs it. What is wrong is a tile printing a
                // target at a session that has no target left to hit.
                tile("Sets", "square.stack.3d.up",
                     model.isEditing
                        ? "\(model.completedSets)"
                        : "\(model.completedSets)/\(model.plannedSets)",
                     model.isEditing ? "sets" : nil,
                     tint: Color.onyx.textPrimary)
                tile("Records", "trophy", model.recordCount > 0 ? "\(model.recordCount)" : "—", nil,
                     tint: model.recordCount > 0 ? Color.onyx.record : Color.onyx.textTertiary)
            }
            provenanceLine
        }
    }

    // MARK: - The shape of it

    /// The two readings that are about the session's SHAPE rather than its
    /// totals: how this one compares with the last few of its split, and how
    /// hard it got as it went (W10).
    ///
    /// ── WHY THEY BELONG HERE AND NOT ON THE SUMMARY PAGE ────────────────────
    /// They are on the summary page too, and that is not a duplicate: the page
    /// is where a session is STUDIED and this sheet is where it is put down.
    /// The two questions anybody asks in the thirty seconds between the last
    /// set and the locker are "was that a lot" and "did I fade", and neither is
    /// answerable from a tonnage figure and a set count. `View summary` is two
    /// taps and a navigation away, which is two taps more than the moment has.
    ///
    /// ── AND WHY THERE IS ONLY ONE SPARK ─────────────────────────────────────
    /// Decision 10: essentials only. Tonnage is the one figure that survives an
    /// exercise being swapped in or out of a split (`SplitVolumeChart`'s own
    /// header), so it is the one trail worth six points here; the per-movement
    /// trails live on the page, beside the sets they describe.
    ///
    /// Both draw nothing when they have nothing: `Sparkline` refuses under two
    /// points, `IntensityBar` refuses under three sets or two ratings, and an
    /// empty `VStack` of two absent children takes no height. A first session
    /// on a new split therefore sees exactly what it saw before this wave.
    @ViewBuilder
    private var shape: some View {
        if trail.count >= 2 || intensity.count >= 3 {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                if trail.count >= 2 { tonnageTrail }
                IntensityBar(values: intensity)
            }
        }
    }

    /// This session's tonnage against the last few of its own split.
    ///
    /// ── NOT ZERO-BASED, THOUGH TONNAGE HAS A ZERO ───────────────────────────
    /// `Sparkline`'s own header names tonnage as the example of a quantity with
    /// a meaningful zero, and that is right for a tile drawing one number's
    /// history against nothing. It is wrong here. Six sessions of one split sit
    /// inside a few per cent of each other, so a 0…max band puts all six in the
    /// top fifth of the graphic and the line comes out flat — the shape stops
    /// carrying information, which is the failure `band` is written to avoid at
    /// the other end.
    ///
    /// The absolute claim is not lost: it is the per-cent beside the line,
    /// which is a number and does not need a baseline to be read. The line's
    /// job is the SHAPE — steady, climbing, or a deload week — and the shape
    /// needs the range.
    private var tonnageTrail: some View {
        HStack(spacing: OnyxSpace.s) {
            Text("vs last \(trail.count - 1)")
                .onyxMicro()
                .fixedSize()
            Sparkline(points: trail, color: accent, zeroBased: false)
                .frame(height: 18)
            Text(deltaLabel)
                .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
                .fixedSize()
        }
        .padding(.horizontal, OnyxSpace.m)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tonnage against your last \(trail.count - 1) \(model.day.label) sessions")
        .accessibilityValue(spokenDelta)
    }

    /// `+8%` against the MEAN of the sessions behind it, not against the last
    /// one.
    ///
    /// One session is a sample of one and every split has a light week in it;
    /// measured against the last session alone, the same workout reads +12 %
    /// one week and −11 % the next while nothing about it changed. The mean of
    /// the trail is what the trail is a picture of.
    private var deltaLabel: String {
        guard let pct = deltaPct else { return "" }
        return "\(pct > 0 ? "+" : "")\(jsIntegerString(pct))%"
    }

    private var spokenDelta: String {
        guard let pct = deltaPct else { return "no comparison" }
        if pct == 0 { return "the same as usual" }
        return "\(jsIntegerString(abs(pct))) per cent \(pct > 0 ? "above" : "below") usual"
    }

    private var deltaPct: Double? {
        let previous = trail.dropLast()
        guard !previous.isEmpty, let current = trail.last else { return nil }
        let mean = previous.reduce(0, +) / Double(previous.count)
        guard mean > 0 else { return nil }
        return jsRound((current - mean) / mean * 100)
    }

    /// Every performed set's rating, in order. Computed rather than stored: it
    /// is a walk over the deck already in memory, and it must move when a set
    /// is rated from the sheet's own dial being dragged.
    private var intensity: [Double?] { model.intensityTrace() }

    /// Where a figure came from. It matters which: a MEASURED average heart
    /// rate is the watch's record of this session, an estimated one is
    /// arithmetic on your own recent history, and an EDITED one is what you
    /// said — which outranks both and is why `setSessionMetrics` stamps it
    /// measured in the store.
    private enum Provenance {
        case measured, estimated, edited, unknown

        var color: Color {
            switch self {
            case .measured:  Color.onyx.good
            case .edited:    Color.onyx.accent(.train)
            case .estimated: Color.onyx.textTertiary
            case .unknown:   .clear
            }
        }

        var word: String? {
            switch self {
            case .measured:  "measured"
            case .edited:    "edited"
            case .estimated: "estimated"
            case .unknown:   nil
            }
        }
    }

    private func provenance(_ value: Int?, measured: Bool) -> Provenance {
        guard value != nil else { return .unknown }
        return measured ? .measured : .estimated
    }

    /// Three across on a phone, one at an accessibility size. Three truncated
    /// numbers is the one thing a reading must never be.
    private var editableColumns: Int { typeSize.isAccessibilitySize ? 1 : 3 }
    private var readingColumns: Int {
        if typeSize.isAccessibilitySize { return 1 }
        return typeSize >= .xxLarge ? 2 : 3
    }

    private var provenanceLine: some View {
        Text(provenanceText)
            .onyxType(.caption)
            .foregroundStyle(Color.onyx.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var provenanceText: String {
        if !prefilled.isEmpty {
            // Say whose number it is. A figure carried from the last session
            // reads exactly like one this session produced, and a default
            // mistaken for a reading is a reading nobody took.
            return "Carried over from your last \(model.day.label) session — tap to correct, or let the watch fill it in."
        }
        if avgBpm == nil || calories == nil {
            return "Heart rate and calories fill in from Apple Health once the watch has synced — or tap to set them."
        }
        return bpmMeasured && caloriesMeasured
            ? "Heart rate and calories measured from the watch's own workout."
            : "Estimated from your recent sessions — tap either to correct it."
    }

    /// The movement that moved the most weight, named. One line, because the
    /// full breakdown is what "View summary" is for and repeating it here would
    /// be the sheet arguing with the screen it links to.
    private var heaviest: some View {
        HStack(spacing: OnyxSpace.s) {
            Image(systemName: "medal")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textTertiary)
            Text(topMovement)
                .onyxType(.secondary)
                .foregroundStyle(Color.onyx.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OnyxSpace.m)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.row)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Heaviest lift, \(topMovement)")
    }

    private var topMovement: String {
        guard let best = model.exercises.max(by: { $0.volumeKg < $1.volumeKg }), best.volumeKg > 0
        else { return "" }
        return "\(best.name) · \(OnyxFormat.volume(best.volumeKg)) kg"
    }

    private func summaryLink(_ sessionId: String) -> some View {
        NavigationLink {
            SessionDetailView(sessionId: sessionId)
        } label: {
            HStack {
                Text("View summary")
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
            .onyxType(.body)
            .foregroundStyle(Color.onyx.textPrimary)
            .padding(.horizontal, OnyxSpace.m)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .onyxGlass(.row)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tiles

    /// One reading. A tinted wash and a tinted hairline rather than a plain
    /// glass box, so the six read as one family and the eye can find any of
    /// them without reading the labels.
    private func tile(
        _ label: String, _ symbol: String, _ value: String, _ unit: String?, tint: Color
    ) -> some View {
        tileShell(label, symbol, tint: tint) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .onyxType(.body).fontWeight(.semibold).onyxNumeral()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .onyxType(.micro)
                        .foregroundStyle(Color.onyx.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(unit.map { "\(value) \($0)" } ?? value)
    }

    /// A reading you can answer, with a stepper and a provenance dot.
    ///
    /// ── WHY A STEPPER AND NOT ONLY A KEYBOARD ───────────────────────────────
    /// Every correction these three get is small and known: the duration is out
    /// by five minutes because the deck sat open in the car, the calories are
    /// out by fifty. A number pad for that is a keyboard covering the sheet, a
    /// field to select, a Done to find — for a change a thumb could have made
    /// twice. So the cell opens INTO ± around the value, and the value itself is
    /// still a field for the rare case where the answer is nothing like what is
    /// there.
    ///
    /// One cell is open at a time: three steppers side by side on a phone is
    /// three two-point targets.
    ///
    /// What you set is stamped MEASURED — see `AppDatabase.updateMetrics` — so
    /// a later sync cannot quietly replace your answer with an estimate. A
    /// DURATION goes further and sets `duration_edited`, which is what stops
    /// `closeSession` re-deriving it from the clock a moment later.
    private func metricCell(
        _ label: String, _ symbol: String,
        value: Binding<Int?>, unit: String, step: Int,
        field: Metric, provenance: Provenance
    ) -> some View {
        let isOpen = open == field
        // Every write to this cell — a stepper end, the keypad, a VoiceOver
        // adjust — goes through here, so this is the one place that has to know
        // the carried-over figure has been answered. A `Binding` wrapper rather
        // than three call sites, because a fourth would be added without it.
        let answered = Binding<Int?>(
            get: { value.wrappedValue },
            set: { next in
                if next != value.wrappedValue { prefilled.remove(field) }
                value.wrappedValue = next
            }
        )
        return VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            HStack(spacing: OnyxSpace.xs) {
                Label(label, systemImage: symbol)
                    .onyxMicro()
                    .lineLimit(1)
                    // Three tiles across a phone leaves ~116 pt, and a glyph
                    // plus "DURATION" tracked out at micro does not fit it —
                    // the shot read "DURATI…". Scaling the label is right where
                    // truncating a value would not be: the word is a name the
                    // reader already knows, and the number beside it is not.
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if provenance.word != nil {
                    Circle()
                        .fill(provenance.color)
                        .frame(width: 6, height: 6)
                }
            }
            if isOpen {
                stepperRow(value: answered, unit: unit, step: step, field: field)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value.wrappedValue.map(String.init) ?? "—")
                        .onyxType(.body).fontWeight(.semibold).onyxNumeral()
                        .foregroundStyle(value.wrappedValue == nil
                                         ? Color.onyx.textTertiary : Color.onyx.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .onyxType(.micro)
                        .foregroundStyle(Color.onyx.textTertiary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, OnyxSpace.m)
        .padding(.vertical, OnyxSpace.s)
        // ── THE FRAME BEFORE THE BACKGROUND ─────────────────────────────────
        // A `.background` applied first is proposed the CONTENT's height, not
        // the frame's, so the wash would end above the floor the minimum sets.
        // Two points apart at the default size and obvious at AX5.
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .fill(cellTint(provenance).opacity(isOpen ? 0.16 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .strokeBorder(cellTint(provenance).opacity(isOpen ? 0.45 : 0.20), lineWidth: 0.5)
        )
        // The TARGET is the cell, not the text inside it. A field you have to
        // hit exactly is a field nobody corrects — and the whole box being live
        // is also the only affordance saying which three of the six you answer.
        .contentShape(.rect)
        .onTapGesture {
            if isOpen { closeCell() } else {
                commitMetrics()
                open = field
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(
            value.wrappedValue.map { "\($0) \(unit)\(provenance.word.map { ", \($0)" } ?? "")" }
                ?? "Not set"
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: bump(answered, by: step)
            case .decrement: bump(answered, by: -step)
            default: break
            }
        }
    }

    private func cellTint(_ provenance: Provenance) -> Color {
        switch provenance {
        case .measured: Color.onyx.good
        case .edited:   Color.onyx.accent(.train)
        default:        Color.onyx.textPrimary
        }
    }

    private func stepperRow(
        value: Binding<Int?>, unit: String, step: Int, field: Metric
    ) -> some View {
        HStack(spacing: OnyxSpace.xs) {
            stepButton("minus", enabled: (value.wrappedValue ?? 0) > 0) {
                bump(value, by: -step)
            }
            // `fixedSize` on a NUMBER, never on a sentence: three digits and a
            // unit have a bounded width, and the field would otherwise take
            // every point offered and push the unit to the far edge.
            WholeNumberField(value: value, placeholder: "—")
                .frame(minWidth: 34)
                .focused($editing, equals: field)
            Text(unit)
                .onyxType(.micro)
                .foregroundStyle(Color.onyx.textTertiary)
            Spacer(minLength: 0)
            stepButton("plus", enabled: true) { bump(value, by: step) }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .onyxType(.caption).fontWeight(.semibold)
                .foregroundStyle(enabled ? Color.onyx.textPrimary : Color.onyx.textTertiary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.onyx.textPrimary.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityHidden(true)
    }

    /// Step and clamp. A negative duration is an ACWR input and a negative
    /// heart rate is nothing at all, so the floor is zero on every one of them.
    private func bump(_ value: Binding<Int?>, by step: Int) {
        value.wrappedValue = max(0, (value.wrappedValue ?? 0) + step)
    }

    private func closeCell() {
        editing = nil
        open = nil
        commitMetrics()
    }

    private func tileShell<Content: View>(
        _ label: String, _ symbol: String, tint: Color, @ViewBuilder value: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            Label(label, systemImage: symbol)
                .onyxMicro()
                .lineLimit(1)
            value()
        }
        .padding(.horizontal, OnyxSpace.m)
        .padding(.vertical, OnyxSpace.s)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .strokeBorder(tint.opacity(0.20), lineWidth: 0.5)
        )
    }

    // MARK: - The store

    private func loadMetrics() {
        // The clock's own answer, PAUSE-AWARE. This tile used to read
        // `Date() − startedAt`, which is the same arithmetic that recorded the
        // 6 September session as 385 minutes: it counts the twenty minutes you
        // spent on the phone between sets as training. `elapsed()` is the
        // hero's number and `SessionDuration` is what the close then stores.
        let live = Int(model.elapsed() / 60)
        guard let session = model.sessionRow else {
            durationMin = max(0, live)
            return
        }
        // A stored duration wins: the session may have been finished and
        // reopened, and an edited one certainly wins — see `duration_edited`.
        durationMin = session.durationMin.map { max(0, Int(jsRound($0))) } ?? max(0, live)
        durationEdited = session.durationEdited
        avgBpm = session.avgBpm
        calories = session.caloriesBurned
        bpmMeasured = session.avgBpm != nil && !session.avgBpmEstimated
        caloriesMeasured = session.caloriesBurned != nil && !session.caloriesEstimated

        // ── AND WHAT THE LAST ONE OF THESE CAME TO ──────────────────────────
        // Heart rate and calories arrive from the watch's own `HKWorkout`,
        // which can be a day late — so the screen that asks for them is
        // routinely the one screen in the app with nothing to show, and a
        // stepper that starts at zero is not a way to answer. The previous
        // session of the same split is: same movements, same rest, same person.
        //
        // It fills only what is EMPTY. A measured figure, an estimate the
        // Health sync already wrote, and anything typed all outrank it — this
        // is the floor under "—", not a proposal that argues with a reading.
        //
        // Tracked in `prefilled` because provenance is the whole point: these
        // go to the store stamped ESTIMATED (`measured: false`), which keeps
        // the session inside `sessionsNeedingMetrics` so the watch can still
        // correct them. Stamping a carried-over number measured would make it
        // permanent, which is the failure the `avg_bpm` clamp exists for.
        let previous = model.previousMetrics()
        if durationMin == nil || durationMin == 0, let minutes = previous.durationMin {
            durationMin = max(0, Int(jsRound(minutes)))
            prefilled.insert(.duration)
        }
        if avgBpm == nil, let bpm = previous.avgBpm {
            avgBpm = bpm
            prefilled.insert(.bpm)
        }
        if calories == nil, let kcal = previous.calories {
            calories = kcal
            prefilled.insert(.calories)
        }
    }

    /// The word the sheet opens on. A PROPOSAL — `word` starts nil and this is
    /// the only thing that ever sets it without a gesture.
    private func loadSuggestion() {
        guard word == nil else { return }
        suggested = model.suggestedEffort()
        word = suggested
    }

    /// Write what the three cells hold. Only a figure that actually MOVED is
    /// sent: `updateMetrics` stamps whatever it receives as the athlete's
    /// answer, and re-sending an untouched estimate would promote it to
    /// measured for nothing.
    private func commitMetrics() {
        guard let session = model.sessionRow else { return }
        let storedDuration = session.durationMin.map { Int(jsRound($0)) }
        let duration = durationMin != storedDuration ? durationMin.map(Double.init) : nil
        let bpm = avgBpm != session.avgBpm ? avgBpm : nil
        let kcal = calories != session.caloriesBurned ? calories : nil
        guard duration != nil || bpm != nil || kcal != nil else { return }
        // ── TWO WRITES, BECAUSE THEY MEAN DIFFERENT THINGS ──────────────────
        // A figure the athlete moved is their answer and is stamped MEASURED,
        // which takes the session out of `sessionsNeedingMetrics` so a later
        // Health sync cannot replace it. A figure still sitting where the
        // pre-fill put it is a carried-over default and is stamped ESTIMATED,
        // so the watch's own workout still overwrites it when it lands.
        //
        // `prefilled` is cleared per field the moment the value moves off what
        // was carried over — see `bump` and the field's own binding.
        let carried: (Double?, Int?, Int?) = (
            prefilled.contains(.duration) ? duration : nil,
            prefilled.contains(.bpm) ? bpm : nil,
            prefilled.contains(.calories) ? kcal : nil
        )
        model.setMetrics(
            durationMin: prefilled.contains(.duration) ? nil : duration,
            avgBpm: prefilled.contains(.bpm) ? nil : bpm,
            calories: prefilled.contains(.calories) ? nil : kcal
        )
        model.setMetrics(
            durationMin: carried.0, avgBpm: carried.1, calories: carried.2, measured: false
        )
        if duration != nil { durationEdited = !prefilled.contains(.duration) }
        if bpm != nil { bpmMeasured = !prefilled.contains(.bpm) }
        if kcal != nil { caloriesMeasured = !prefilled.contains(.calories) }
        // ── THE CASCADE IS THE DOOR'S (W2) ──────────────────────────────────
        // A duration is an ACWR input and moves forty-nine days of battery;
        // `updateMetrics` commits the session row, and the rescore door
        // reports its date on that commit. Nothing to ask for here.
    }

    private var finishButton: some View {
        Button {
            // A field is still focused when the button is tapped, so its value
            // has not been committed. Dropping focus first is what makes a
            // typed heart rate part of the session being closed rather than of
            // the next sync.
            closeCell()
            // Closing writes `duration_min` and `session_rpe` — the two load
            // inputs — and `closeSession`'s commit is what the rescore door
            // reports (W2). A session finished after midnight is dated
            // yesterday and cascades; one finished today is scored live and
            // stored by the next sync.
            guard onFinish(word?.cr10) else { return }
        } label: {
            Text("Finish session")
                .onyxType(.body).fontWeight(.semibold)
                .foregroundStyle(Color.onyx.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    OnyxDomain.train.ramp,
                    in: RoundedRectangle(cornerRadius: OnyxCorner.tile, style: .continuous)
                )
        }
        .onyxPress(scale: 0.98)
    }
}

// MARK: - Numeric entry

/// A whole number, typed — and published on every keystroke.
///
/// ── WHY THIS EXISTS INSTEAD OF `TextField(value:format:)` ───────────────────
/// A formatted `TextField` parses its text back through the binding when focus
/// LEAVES, and that write lands on the next update pass — not synchronously
/// inside whatever dropped the focus. The finish button dropped focus and then
/// read the three `@State` values in the same turn, so a heart rate still under
/// the cursor when Finish was tapped was read at its PREVIOUS value and the
/// typed one was silently discarded. Exactly the shape of the stepper's
/// press/release race one file over, and with the same consequence: the number
/// on screen and the number committed disagreed, with nothing to see.
///
/// Owning the text removes the flush entirely — there is no pending write to
/// lose, because the value is already correct before the button is tapped.
///
/// The clamp is `NumericField`'s and for the same reason: `.numberPad` has no
/// length limit, `Double("99999999999999999999")` is 1e20, and an `Int` cast of
/// that TRAPS. Holding a finger on the `9` key must not crash the app.
private struct WholeNumberField: View {
    @Binding var value: Int?
    let placeholder: String

    @State private var text: String = ""

    private static let limit = 100_000.0

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numberPad)
            .onyxType(.body).fontWeight(.semibold).onyxNumeral()
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.onyx.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize()
            .onAppear { text = Self.render(value) }
            // Guarded on inequality: `onAppear` seeds `text` and fires this on
            // the same cycle, which would otherwise write every cell back into
            // the model — and `commitMetrics` compares against the store to
            // decide what to send, so a write-back is a spurious upload that
            // stamps an untouched estimate as measured.
            .onChange(of: text) { _, next in
                let parsed = Self.parse(next)
                if parsed != value { value = parsed }
            }
            // A value changed from outside the field — the ± steppers, the
            // pre-fill landing after the store read — has to reach the text, or
            // the field goes on showing what it was seeded with.
            .onChange(of: value) { _, next in
                let rendered = Self.render(next)
                if Self.parse(text) != next { text = rendered }
            }
    }

    private static func render(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    private static func parse(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        guard !digits.isEmpty, let value = Double(digits), value.isFinite else { return nil }
        return Int(min(max(value, 0), limit))
    }
}

// MARK: - The dial

/// Session effort, on a dial with five detents and a word in the middle.
///
/// ── WHY A DIAL AND NOT A SLIDER ─────────────────────────────────────────────
/// A slider is the same gesture as the swipe that logs a set and the drag that
/// scrolls the deck, and this is the one control on the screen that should not
/// feel like those — it is a considered answer, not a quick one. A dial also
/// puts the value in the MIDDLE of the control it is set by, which is what lets
/// the word be the largest thing in the ring without a label pointing at it.
///
/// ── WHY FIVE STOPS AND NOT A CONTINUOUS SWEEP ───────────────────────────────
/// Because the question is verbal. `Effort.words` is the same five-rung ladder
/// the web writes (`EFFORT_WORDS`), each carrying the CR-10 that lands in
/// `session_rpe`, and a control with a stop per rung cannot produce a value
/// that has no word. The half-point sweep it replaces could — and every
/// half-point between two anchors was a number given by habit, which is exactly
/// what the words exist to stop.
///
/// The stops are drawn ON the ring as ticks, so the resolution is visible
/// before the dial is touched, and named in the scale underneath it, which is
/// also a control: the ring is a thumb gesture, the scale is a tap target and
/// the only one that works at an accessibility size.
///
/// It is adjustable from VoiceOver as well: `accessibilityAdjustableAction`
/// maps swipe-up and swipe-down to the neighbouring word, and speaks the word
/// and the number together.
private struct EffortDial: View {
    @Binding var word: EffortWord?
    let accent: Color

    @Environment(\.dynamicTypeSize) private var typeSize

    private var words: [EffortWord] { Effort.words }

    /// A three-quarter sweep, opening at the bottom — the shape of every dial
    /// Apple ships, and the gap is where the finger starts and stops rather
    /// than a place the value can hide.
    private static let sweep = 270.0
    private static let start = 135.0

    /// The dial scales with Dynamic Type: the word inside it does, and a fixed
    /// frame around growing type is how a gauge ends up with its own reading
    /// spilling over the rim.
    @ScaledMetric(relativeTo: .title) private var diameter: CGFloat = 168

    private var index: Int? { word.flatMap { w in words.firstIndex { $0.key == w.key } } }
    /// Where the selected stop sits along the sweep, 0…1.
    private var fraction: Double? {
        index.map { Double($0) / Double(words.count - 1) }
    }

    var body: some View {
        VStack(spacing: OnyxSpace.s) {
            ZStack {
                track
                ticks
                // Nothing is filled until something has been RATED. A dial that
                // arrives showing half a sweep has answered the question for
                // you — even when a suggestion put the word in the middle,
                // clearing it must leave the ring empty.
                if fraction != nil { fill }
                reading
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { pick(at: $0.location) })
            .sensoryFeedback(.selection, trigger: word?.key)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Session effort")
            .accessibilityValue(
                word.map { "\($0.label), \(OnyxFormat.rpe($0.cr10))" } ?? "Not rated"
            )
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(1)
                case .decrement: step(-1)
                default: break
                }
            }
            scale
        }
    }

    private var side: CGFloat { min(diameter, 260) }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: 12, lineCap: .round) }

    /// ── WHY `trim` AND A ROTATION, NOT `Path.addArc` ────────────────────────
    /// `addArc` takes its angles in the layer's coordinate space, where Y points
    /// DOWN and `clockwise` therefore means the opposite of what it reads as.
    /// The first version of this dial drew its gap on the right and filled
    /// anticlockwise from twelve o'clock — geometry that is correct in the
    /// textbook and wrong on the screen. `Circle().trim` starts at three
    /// o'clock and runs clockwise, always, and a rotation puts the start where
    /// the design wants it: 135° is the bottom-left, so the gap lands at the
    /// bottom where the finger rests.
    private var track: some View {
        Circle()
            .trim(from: 0, to: Self.sweep / 360)
            .stroke(Color.onyx.hairline, style: stroke)
            .rotationEffect(.degrees(Self.start))
            .padding(6)
    }

    /// One tick per stop, sitting in the track. The selected one is the accent
    /// and the rest are the surface, so the ring reads as five places to be
    /// rather than a continuum with a mark on it.
    private var ticks: some View {
        ForEach(Array(words.enumerated()), id: \.element.key) { i, stop in
            let selected = stop.key == word?.key
            Capsule()
                .fill(selected ? Color.onyx.textPrimary : Color.onyx.textTertiary.opacity(0.5))
                .frame(width: 2, height: 8)
                .offset(y: -(side / 2 - 12))
                .rotationEffect(
                    .degrees(Self.start + 90 + Self.sweep * Double(i) / Double(words.count - 1))
                )
        }
    }

    private var fill: some View {
        Circle()
            // A floor, not a fraction: the first word is the bottom of the
            // ladder and `trim(0, 0)` draws nothing, which is what UNRATED
            // looks like — and "Easy" is an answer, not an absence.
            .trim(from: 0, to: Self.sweep / 360 * max(0.04, min(1, fraction ?? 0)))
            .stroke(Color.onyx.effort(word?.cr10 ?? Effort.cr10Min), style: stroke)
            .rotationEffect(.degrees(Self.start))
            .padding(6)
    }

    /// The WORD, and the number it stores under it.
    ///
    /// The word is what the sheet is asking for, so it is the reading in the
    /// middle of the control that sets it; the CR-10 is what the battery, the
    /// score and the export all read, so it is present and small. A gauge has
    /// room for one reading and a footnote, which is exactly these two.
    private var reading: some View {
        VStack(spacing: 2) {
            Text(word?.label ?? "—")
                .onyxDisplay()
                .foregroundStyle(word.map { Color.onyx.effort($0.cr10) } ?? Color.onyx.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .animation(OnyxMotion.fade, value: word?.key)
            if let word {
                Text("CR-10 \(OnyxFormat.rpe(word.cr10))")
                    .onyxType(.micro)
                    .onyxNumeral()
                    .foregroundStyle(Color.onyx.textTertiary)
            }
        }
        // Inside a 168 pt ring with a 12 pt stroke: the hole is ~120 pt across,
        // and a word set in the display face needs every point of it.
        .frame(maxWidth: side * 0.62)
    }

    /// The five words, named and tappable.
    ///
    /// The ring is a thumb gesture and this is the keyboard-and-VoiceOver half
    /// of the same control — and the only half that survives an accessibility
    /// type size, where five words orbiting a circle would each be three lines
    /// tall and overlap the stroke.
    private var scale: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            ForEach(words, id: \.key) { stop in
                Button { word = stop } label: {
                    Text(stop.label)
                        .onyxType(.caption)
                        .fontWeight(stop.key == word?.key ? .semibold : .regular)
                        .foregroundStyle(
                            stop.key == word?.key ? Color.onyx.effort(stop.cr10) : Color.onyx.textTertiary
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Where the finger is, as a stop.
    ///
    /// Screen angles run clockwise from east, so the arc's own parameter is the
    /// touch angle rotated back to the opening at the bottom-left. A touch in
    /// the GAP has no value on the dial, so it snaps to whichever end it is
    /// nearer — which is what a physical dial with a stop does, and is better
    /// than the value jumping across the whole range.
    private func pick(at point: CGPoint) {
        let dx = point.x - side / 2
        let dy = point.y - side / 2
        // A touch near the middle has no angle worth reading — `atan2` of two
        // numbers close to zero swings wildly, so tapping the word itself would
        // set a value at random. The hole is the reading's own space.
        guard (dx * dx + dy * dy).squareRoot() > side * 0.28 else { return }
        let degrees = atan2(dy, dx) * 180 / .pi
        var swept = degrees - Self.start
        while swept < 0 { swept += 360 }
        let clamped: Double
        if swept <= Self.sweep {
            clamped = swept / Self.sweep
        } else {
            clamped = swept < (360 + Self.sweep) / 2 ? 1 : 0
        }
        let i = Int((clamped * Double(words.count - 1)).rounded())
        word = words[Swift.min(words.count - 1, Swift.max(0, i))]
    }

    private func step(_ delta: Int) {
        // From unrated, either direction lands on the middle rung: a swipe on
        // an unanswered dial should not have to travel the whole ladder.
        let next = (index ?? words.count / 2 - (delta > 0 ? 1 : -1)) + delta
        word = words[Swift.min(words.count - 1, Swift.max(0, next))]
    }
}

#if DEBUG
#Preview("Finish") {
    FinishSheet(model: .previewUpperB(logged: true), onFinish: { _ in true })
        .environment(AppEnvironment.preview)
}
#endif
