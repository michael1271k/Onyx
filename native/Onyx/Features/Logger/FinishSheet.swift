import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

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
/// it opens, the rating alone by dragging down, and the same interruptible grab
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
    /// Screenshot harness only: a foreign workout handed in instead of read
    /// from Health. A Hevy-tagged `HKWorkout` cannot be seeded on a simulator
    /// — the writer IS the source — so the compare card is proven with a
    /// fixture here and the predicate with its golden vector.
    #if DEBUG
    var foreignFixture: WorkoutSample? = nil
    #endif

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppEnvironment.self) private var environment

    /// ── WHY IT OPENS LARGE ─────────────────────────────────────────────────
    /// The rating is the first thing in the sheet (it was a 168 pt dial), so at
    /// the `.medium` detent it and its caption ARE the sheet — the six readings
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
    /// A FOREIGN strength workout overlapping this session — Hevy's record of
    /// it (W5, decision 7). Nil once answered, or when there is none.
    @State private var foreign: WorkoutSample?
    @FocusState private var editing: Metric?
    /// The heart-rate chart's panel is up, and whether there is a series for
    /// it to draw — see `heartRatePanel` (W3).
    @State private var heartOpen = false
    @State private var heartSeries = false
    /// Whose figures the heart rate and calories are once Hevy's were adopted
    /// — the source's name, so the provenance line stops crediting the watch.
    @State private var adoptedFrom: String?
    /// A watch was on the wrist for this session (Precision A5) — read once
    /// at open; see `showsWristMetrics`.
    @State private var wristEvidence = false
    /// The athlete asked for last session's heart rate and calories. The ONLY
    /// door through which an estimated HR/kcal reaches this session now.
    @State private var carriedWrist = false

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
                    if let foreign { hevy(foreign) }
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
                    // Out of the way while the heart-rate panel is up: the
                    // inset draws above an overlay on this SDK, so the panel
                    // and the button were drawn through each other — and
                    // Finish is not the action while a chart is being read.
                    .opacity(heartOpen ? 0 : 1)
                    .allowsHitTesting(!heartOpen)
                    .animation(OnyxMotion.fade, value: heartOpen)
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
                await loadForeign()
            }
        }
        // The chart the Avg HR reading opens (W3). On the STACK, not the scroll
        // view: the pinned Finish button is the scroll view's inset, and a panel
        // inside it was drawn through the button rather than over it.
        .heartRatePanel(
            isPresented: $heartOpen, available: $heartSeries,
            sessionId: model.isEditing ? nil : model.sessionId,
            storedAvgBpm: bpmMeasured ? avgBpm : nil, kcal: calories,
            onEdit: { open = .bpm }
        )
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
            EffortSlab(word: $word)
            caption
        }
    }

    @ViewBuilder
    private var caption: some View {
        if let word {
            Text(word.hint)
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            // One line under the hint: whose answer this is, and the way to
            // take it back. A word already on the slab when the sheet opens
            // reads as one the athlete gave, and a suggestion mistaken for an
            // answer is a rating nobody actually made.
            HStack(spacing: OnyxSpace.s) {
                if word == suggested {
                    Text("Suggested from your recent \(model.day.label) sessions")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Clear") { self.word = nil }
                    .onyxType(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Clear rating")
            }
        } else {
            Text("How hard was the whole session?")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
                .multilineTextAlignment(.center)
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
                // Duration alone spans the row: one cell at a third of the
                // width reads as two cells missing.
                columns: Array(repeating: GridItem(.flexible(), spacing: OnyxSpace.s),
                               count: showsWristMetrics ? editableColumns : 1),
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
                if showsWristMetrics {
                    metricCell(
                        // The trace glyph once there is a trace behind the tap.
                        "Avg HR", heartSeries ? "waveform.path.ecg" : "heart", value: $avgBpm, unit: "bpm", step: 1,
                        field: .bpm, provenance: provenance(avgBpm, measured: bpmMeasured)
                    )
                    metricCell(
                        "Calories", "flame", value: $calories, unit: "kcal", step: 10,
                        field: .calories, provenance: provenance(calories, measured: caloriesMeasured)
                    )
                }
            }
            if !showsWristMetrics, lastTimeWrist != nil { addFromLastTime }
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
            if !model.isEditing, model.untickedSets > 0 { untickedLine }
        }
    }

    // MARK: - The wrist guard (Precision A5)

    /// Heart rate and calories are asked only where a watch was: a coverage
    /// row or a cached sample (`wristEvidence`), a live bpm during the session,
    /// a figure already MEASURED on the row (a watch workout, or Hevy's) — or
    /// because the athlete asked for last time's. See `WristMetrics.shown`.
    private var showsWristMetrics: Bool {
        WristMetrics.shown(
            evidence: wristEvidence, liveBpmSeen: model.wristBpmSeen,
            measured: bpmMeasured || caloriesMeasured, carried: carriedWrist
        )
    }

    /// Last session's heart rate and calories, if it had any.
    private var lastTimeWrist: (avgBpm: Int?, calories: Int?)? {
        let previous = model.previousMetrics()
        guard previous.avgBpm != nil || previous.calories != nil else { return nil }
        return (previous.avgBpm, previous.calories)
    }

    /// The explicit door to an estimate. Filled as before — stamped ESTIMATED
    /// and marked `prefilled`, so the watch's own workout still replaces it.
    private var addFromLastTime: some View {
        Button {
            guard let last = lastTimeWrist else { return }
            if avgBpm == nil, let bpm = last.avgBpm { avgBpm = bpm; prefilled.insert(.bpm) }
            if calories == nil, let kcal = last.calories { calories = kcal; prefilled.insert(.calories) }
            carriedWrist = true
        } label: {
            Label("Add heart rate and calories from last time", systemImage: "arrow.uturn.backward.circle")
                .onyxType(.caption).fontWeight(.semibold)
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Unticked sets were never stored, and the routine keeps them (Q9).
    private var untickedLine: some View {
        let n = model.untickedSets
        return Text("\(n) set\(n == 1 ? "" : "s") left unticked · kept in your plan")
            .onyxType(.caption)
            .foregroundStyle(Color.onyx.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hevy logged this too (W5)

    /// Read once the sheet is up, after the store's own figures. Hevy's
    /// figures already adopted for this session (here on a previous open, or
    /// on the summary page) keep the line down — it would restate them. Any
    /// other decision is a legacy `.skip`, from when the line was a question.
    private func loadForeign() async {
        guard let session = model.sessionRow, !model.isEditing else { return }
        if await environment.telemetry.hevyDecision(sessionId: session.id) == .use { return }
        #if DEBUG
        if let foreignFixture { foreign = foreignFixture; return }
        #endif
        foreign = await environment.foreignWorkout(for: session)
    }

    private func hevy(_ workout: WorkoutSample) -> some View {
        HevyCompareCard(
            onyx: .init(
                avgBpm: avgBpm, kcal: calories, durationMin: durationMin, sets: model.completedSets,
                bpmMeasured: bpmMeasured, kcalMeasured: caloriesMeasured
            ),
            hevy: workout,
            onUse: {
                // The two figures the phone could not measure, adopted as the
                // athlete's answer: `setMetrics` stamps them measured, the
                // same way a typed correction is, so a later Health sync
                // cannot replace them with an estimate. Health itself is not
                // touched; Hevy's workout stays Hevy's.
                // Only the figures the phone could NOT measure: a typed
                // answer, or the watch's own reading, is never replaced.
                let bpm = bpmMeasured ? nil : workout.avgHr.map { Int(jsRound($0)) }
                let kcal = caloriesMeasured ? nil : workout.activeKcal.map { Int(jsRound($0)) }
                model.setMetrics(avgBpm: bpm, calories: kcal)
                if let bpm { avgBpm = bpm; bpmMeasured = true; prefilled.remove(.bpm) }
                if let kcal { calories = kcal; caloriesMeasured = true; prefilled.remove(.calories) }
                if bpm != nil || kcal != nil { adoptedFrom = workout.sourceName ?? "another app" }
                if let id = model.sessionId {
                    Task { await environment.telemetry.setHevyDecision(sessionId: id, .use) }
                }
                withAnimation(OnyxMotion.fade) { foreign = nil }
            }
        )
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

    /// Plus, once the Avg HR tap opens a trace rather than a stepper (W3), a
    /// line that says so — "tap to set them" would otherwise be a promise the
    /// heart rate's own tap no longer keeps directly.
    private var provenanceText: String {
        heartSeries ? provenanceBase + " Avg HR opens the session's heart-rate trace." : provenanceBase
    }

    private var provenanceBase: String {
        if !showsWristMetrics {
            return "No watch recorded this session, so heart rate and calories stay empty."
        }
        if !prefilled.isEmpty {
            // Say whose number it is. A figure carried from the last session
            // reads exactly like one this session produced, and a default
            // mistaken for a reading is a reading nobody took.
            return "Carried over from your last \(model.day.label) session — tap to correct, or let the watch fill it in."
        }
        if avgBpm == nil || calories == nil {
            return "Heart rate and calories fill in from Apple Health once the watch has synced — or tap to set them."
        }
        if let adoptedFrom {
            return "Heart rate and calories from \(adoptedFrom)'s workout — tap either to correct it."
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
        let face = VStack(alignment: .leading, spacing: OnyxSpace.xs) {
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
        return Group {
            if field == .bpm, heartSeries, !isOpen {
                // ── THE AVERAGE OPENS ITS OWN TRACE (W3) ────────────────────
                // With a series behind it, the reading's tap is the chart —
                // the only way to it, since it left the page. A Button, not
                // the tap gesture below: `OnyxPressStyle` answers on touch-
                // DOWN, and the panel is a thing that should feel grabbed.
                // The stepper is one tap on, as the panel's "Edit the average".
                // Nothing is committed on the way: opening a chart answers
                // nothing, and `commitMetrics` would stamp the clock's running
                // duration "edited". Only a stepper already open is closed
                // (and committed) — the same as tapping to another cell.
                //
                // And to `.large`: the panel is taller than the sheet at its
                // `.medium` detent on a small phone, and its title — the
                // average being opened — would be the part cut off.
                Button {
                    if open != nil { closeCell() }
                    detent = .large
                    heartOpen = true
                } label: { face }
                .onyxPress(scale: 0.97)
                .accessibilityHint("Opens the heart-rate chart")
            } else {
                // The TARGET is the cell, not the text inside it. A field you
                // have to hit exactly is a field nobody corrects — and the whole
                // box being live is also the only affordance saying which three
                // of the six you answer.
                face
                    .contentShape(.rect)
                    .onTapGesture {
                        if isOpen { closeCell() } else {
                            commitMetrics()
                            open = field
                        }
                    }
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
        // ── BUT NOT THE WRIST'S TWO (Precision A5) ─────────────────────────
        // Heart rate and calories used to be carried over here too, and on a
        // session no watch saw they sat on the sheet looking like a reading,
        // stamped estimated and saved. They wait for the explicit "Add from
        // last time" now; the duration above is the phone's own clock's
        // question and keeps its floor.
        wristEvidence = model.wristEvidence()
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

#if DEBUG
#Preview("Finish") {
    FinishSheet(model: .previewUpperB(logged: true), onFinish: { _ in true })
        .environment(AppEnvironment.preview)
}
#endif

/// Whether the finish sheet asks for heart rate and calories (Precision A5).
///
/// Any one signal that a watch saw the session is enough, and so is the
/// athlete's explicit "Add from last time". None of them, and the two cells
/// are not drawn at all — an empty cell still invites a guess.
enum WristMetrics {
    static func shown(evidence: Bool, liveBpmSeen: Bool, measured: Bool, carried: Bool) -> Bool {
        evidence || liveBpmSeen || measured || carried
    }
}
