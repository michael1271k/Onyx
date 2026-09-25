import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// The logger's second face: what the session has become, while it is happening.
///
/// ── WHY THIS IS A FACE AND NOT A SHEET ──────────────────────────────────────
/// Everything here used to be somewhere else and worse. Tonnage, sets and
/// records were a 44 pt strip above the deck — three numbers you read once a set
/// occupying the space of a set row for the whole workout. Muscle distribution
/// was two taps down a three-dot menu. Heart rate and calories only existed
/// after you had already finished. None of it was worth its space on the logging
/// face, and all of it is worth a screen you can flick to between sets.
///
/// ── AND WHY IT BINDS THE SAME MODEL ─────────────────────────────────────────
/// One `LoggerModel`, two faces. A second model fed by the first is a second
/// answer allowed to disagree with it, and the disagreement would show up as the
/// tonnage here differing from the tonnage on the Lock Screen by one set.
///
/// The cards are stat tiles rather than charts, deliberately: none of these
/// questions is "how did this change over time" — that is what the session
/// summary is for — and a sparkline of nine points drawn mid-workout is a
/// decoration with a legend.
struct LiveStatsView: View {
    let model: LoggerModel
    let clock: any PauseControlling
    let prs: any LivePrProviding
    /// Opens the full distribution sheet, which the atlas card is a preview of.
    let onMuscleFocus: () -> Void

    private var accent: Color { Color.onyx.day(model.day.key) }

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Heart rate and calories arrive from the watch's own `HKWorkout`, which
    /// can be a day late — so this is whatever is on disk, re-read when a set
    /// lands rather than on every redraw. `LoggerModel.sessionRow` is a database
    /// query; calling it from a `body` would run it once per frame.
    @State private var session: WorkoutSession?

    /// What each movement did the last time this day was trained, one figure
    /// per role — the bar the arrows are drawn against. Empty until the read
    /// lands, and an empty bar simply draws no arrows.
    @State private var previousBests: [String: TopLifts.Best] = [:]

    /// Optional, and read only inside a `.task`: the logger is presented as a
    /// cover from the Workout tab and reached by the shot harness directly, and
    /// a non-optional `@Environment(AppEnvironment.self)` traps the moment it is
    /// read without one — the same declaration `LiveLoggerView` carries.
    @Environment(AppEnvironment.self) private var environment: AppEnvironment?

    #if DEBUG
    /// Harness only: park the page on the Top Lifts card. The two cards above
    /// it are a screen and a half tall on a 375 pt phone, so the shot that
    /// reviews the lift groups cannot be a shot of the top of the page.
    var startAtLifts = false
    #endif

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                VStack(spacing: OnyxSpace.m) {
                    volumeCard
                    // ── WHY PRs SIT SECOND, AND ONLY WHEN THERE ARE ANY ─────
                    // They were fourth, which put the one card worth flicking
                    // over for two screens below the fold: a PR lit on the deck
                    // and then had to be hunted for. The other cards answer "how
                    // is this session going", which is a question you scroll to;
                    // this one announces something that just happened, and an
                    // announcement below the fold is not one.
                    //
                    // And it is ABSENT rather than empty. Most of a session has
                    // no records in it, so the empty state WAS the state — a tile
                    // of prose in the second slot, above three cards that always
                    // have something to say, for most of every workout.
                    if !prs.livePrs.isEmpty { recordsCard }
                    muscleCard
                    // Superlatives before the per-movement list: "what was the
                    // hardest thing I did" is three lines, and the list under it
                    // is as long as the day.
                    topLiftsCard.id(Self.liftsAnchor)
                    exercisesCard
                    effortCard
                }
                .padding(.horizontal, OnyxSpace.l)
                .padding(.bottom, OnyxSpace.xl)
            }
            .scrollIndicators(.hidden)
            // Keyed on PHYSICAL sets: a warm-up leaves `completedSets` alone and
            // still changes the session row this card draws.
            .task(id: model.physicalSets) { session = model.sessionRow }
        // The bar for the arrows. One read, off the main actor, keyed on the
        // day: a session does not change which deck it is halfway through.
        .task(id: model.day.key) {
            guard let database = environment?.database else { return }
            let dayKey = model.day.key, userId = environment?.userIdString
            // ── THE SESSION YOU ARE IN IS NOT THE ONE YOU ARE BEATING ───────
            // The deck writes its own row the moment the first set is ticked,
            // with this day key and today's date, so it is the NEWEST
            // qualifying session by the time this card has anything to draw.
            // Left in, the bar becomes today's own numbers: every delta reads
            // `flat` and the card draws no arrows at all — which is exactly
            // what the first shot of it photographed.
            let live = model.sessionId
            previousBests = await Task.detached(priority: .utility) {
                guard let history = try? database.sessionsForSeed(dayKey: dayKey, userId: userId)
                else { return [:] }
                return TopLifts.previousBests(
                    sessions: history.sessions.filter { $0.id != live }, sets: history.sets
                )
            }.value
        }
            #if DEBUG
            // After the page lands, for the reason the session page's own ledger
            // shot gives: the anchor is decided at first layout, when the stack is
            // still empty.
            .task {
                guard startAtLifts else { return }
                try? await Task.sleep(for: .milliseconds(400))
                scroller.scrollTo(Self.liftsAnchor, anchor: .top)
            }
            #endif
        }
    }

    private static let liftsAnchor = "onyx.livestats.toplifts"

    // MARK: - Volume

    /// The tonnage, the count, and the clocks as one track.
    ///
    /// ── WHY VOLUME IS THE HEADLINE ──────────────────────────────────────────
    /// The card led with the set count and was called "Now", which is the name
    /// of a moment rather than of a measure. What this face is for is how much
    /// work the session has become, and tonnage is that number — the count and
    /// the clocks qualify it. Elapsed is also already the largest thing in the
    /// hero, 230 pt up and visible at the same moment, so a card that opened
    /// with it spent its best line saying nothing new.
    private var volumeCard: some View {
        card("Volume") {
            VStack(alignment: .leading, spacing: OnyxSpace.m) {
                tonnage
                setsProgress
                clockBar
            }
        }
    }

    /// The clocks, over the track that is the one of them with a denominator.
    ///
    /// ── WHY A BAR AND NOT TWO FIGURES ───────────────────────────────────────
    /// ELAPSED and REST were two bare numerals side by side, which reads as a
    /// pair of readings with no relationship — and one of them was already in
    /// the hero. Rest is a countdown against a length the timer sheet SET
    /// (`restDuration`), so it has a fraction; elapsed does not, and inventing
    /// a denominator for it would be the card making up a target. So the track
    /// belongs to rest and the row above it is labelled at both ends: a filling
    /// bar under a live countdown, an empty hairline when nothing is resting.
    private var clockBar: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            // Two clocks share a row until they cannot. At AX5 the labels
            // broke to "ELA / PSE / D" — a register caption spelled down the
            // page in three-letter pieces — so the row becomes a column,
            // the same trade the totals strip made before it.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OnyxSpace.s) { clocks }
            } else {
                HStack(alignment: .top, spacing: OnyxSpace.m) { clocks }
            }
            restTrack
        }
    }

    /// `ProgressView(timerInterval:)`, which the SYSTEM counts — the same trade
    /// `Text(_:style:.timer)` makes, and the reason a bar that moves every
    /// second costs this card no redraws at all. A hand-rolled fraction would
    /// need a per-second `TimelineView` to be anything but frozen.
    @ViewBuilder
    private var restTrack: some View {
        if let countdown = restCountdown(model.restEndsAt, total: Int(model.restDuration)) {
            ProgressView(timerInterval: countdown, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(accent)
            // The countdown is spoken by the cell above it; a bar that
            // announced itself as well would say the same thing twice.
            .accessibilityHidden(true)
        } else {
            // Not a `Capsule()` and not an `EmptyView()`: the first has no
            // intrinsic height and grows to fill the card, the second makes the
            // row jump by 4 pt every time a set is ticked.
            OnyxProgressBar(fraction: 0, tint: accent)
        }
    }

    @ViewBuilder
    private var clocks: some View {
        timeCell(
            "Elapsed",
            running: !clock.isPaused,
            origin: clock.timerOrigin,
            frozen: clock.elapsed(),
            tint: clock.isPaused ? Color.onyx.textTertiary : Color.onyx.textPrimary
        )
        // Only once there is a pause to report. Most sessions have none, and a
        // permanent 0:00 is a third of this row spent on a number that is zero.
        if clock.isPaused || clock.pausedTotal >= 1 {
            timeCell(
                "Paused",
                running: clock.isPaused,
                // Shifted back by what is already banked, the same trick
                // `timerOrigin` plays. Counting from `pausedAt` alone dropped
                // every earlier pause while this one ran and handed them back
                // on resume, so the cell jumped backwards and then forwards.
                origin: clock.pausedAt?.addingTimeInterval(-clock.pausedTotal),
                frozen: clock.pausedTotal,
                tint: Color.onyx.textSecondary
            )
        }
        restCell
    }

    /// A clock cell that counts itself when it is the one running.
    ///
    /// `Text(_:style:.timer)` costs this view nothing per second; a frozen
    /// reading is plain text. Which of the two a cell is depends on the state,
    /// so both are here and only one is ever drawn.
    private func timeCell(
        _ label: String, running: Bool, origin: Date?, frozen: TimeInterval, tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if running, let origin {
                    Text(origin, style: .timer)
                } else {
                    Text(Clock.format(frozen))
                }
            }
            .onyxType(.display).onyxNumeral()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Text(label).onyxMicro()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(Clock.format(running ? (origin.map { -$0.timeIntervalSinceNow } ?? frozen) : frozen))
    }

    /// Rest is the one clock that counts DOWN, and it is absent rather than zero
    /// when nothing is resting — a 0:00 in a cell reads as a timer that has
    /// finished, which is a different fact from no timer.
    @ViewBuilder
    private var restCell: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if let countdown = restCountdown(model.restEndsAt, total: Int(model.restDuration)) {
                    Text(timerInterval: countdown, countsDown: true)
                } else {
                    Text("—")
                }
            }
            .onyxType(.display).onyxNumeral()
            .foregroundStyle(model.restEndsAt == nil ? Color.onyx.textSecondary : accent)
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Text("Rest").onyxMicro()
        }
        // The LABEL dims with the value, not just the value. A live figure over
        // a live caption beside a dash over a live caption reads as missing
        // data; a whole column at half strength reads as switched off, which is
        // what "not resting" is.
        .opacity(model.restEndsAt == nil ? 0.45 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var setsProgress: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.xs) {
                Text("\(model.completedSets)")
                    .onyxType(.body).fontWeight(.semibold).onyxNumeral()
                    .foregroundStyle(accent)
                Text("of \(model.plannedSets) sets")
                    .onyxType(.body)
                    .foregroundStyle(Color.onyx.textSecondary)
                Spacer(minLength: 0)
                if model.physicalSets > model.completedSets {
                    // Warm-ups. They are real work and they are not the count
                    // the programme prescribed, so they are stated beside it
                    // rather than folded into it.
                    Text("+\(model.physicalSets - model.completedSets) warm-up")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textTertiary)
                        .lineLimit(1)
                }
            }
            OnyxProgressBar(fraction: setsFraction, tint: accent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sets")
        .accessibilityValue("\(model.completedSets) of \(model.plannedSets)")
    }

    private var setsFraction: Double {
        guard model.plannedSets > 0 else { return 0 }
        return min(1, Double(model.completedSets) / Double(model.plannedSets))
    }

    @ViewBuilder
    private var tonnage: some View {
        let figure = HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
            // `volumeExact`, not `volume`: this face, the finish sheet's
            // Tonnage tile and the summary's Volume cell are the same claim
            // about the same session, and the one that rounds is the one that
            // gets called wrong.
            Text(OnyxFormat.volumeExact(model.totalVolumeKg))
                .onyxType(.hero).onyxNumeral()
                .foregroundStyle(Color.onyx.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("kg").onyxMicro()
        }
        // The delta is a sentence, and at an accessibility size a sentence does
        // not share a line with a hero figure — it sets the card's MINIMUM
        // width instead, and a card wider than the page overflows it in both
        // directions because a vertical scroll view will not scroll sideways to
        // rescue it. Under the figure at those sizes; beside it otherwise.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                figure
                tonnageDelta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tonnage")
        } else {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                figure
                Spacer(minLength: OnyxSpace.s)
                tonnageDelta
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tonnage")
        }
    }

    /// Against what the seed says this session was last time.
    ///
    /// ── AND WHY BEHIND IS NOT RED ───────────────────────────────────────────
    /// You are behind the seed for the whole workout and level with it on the
    /// last set, by construction. A danger colour on a number that is red 95 %
    /// of the time is a colour that means nothing by the third session.
    @ViewBuilder
    private var tonnageDelta: some View {
        let seed = seedTonnage
        if seed > 0 {
            let delta = model.totalVolumeKg - seed
            let ahead = delta >= 0
            // Two different sentences rather than one signed number. "−306 kg"
            // is true and reads as a verdict; "306 kg to last" is the same fact
            // as a distance, which is what it is for the whole session.
            Text(ahead
                 ? "▲ \(OnyxFormat.volume(delta)) kg over last \(model.day.label)"
                 : "\(OnyxFormat.volume(-delta)) kg to last \(model.day.label)")
                .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                .foregroundStyle(ahead ? Color.onyx.good : Color.onyx.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, OnyxSpace.s)
                .padding(.vertical, OnyxSpace.xs)
                .onyxGlass(.row)
        }
    }

    /// What the deck was SEEDED with, as tonnage.
    ///
    /// Today the seed is `plan.wk1Kg × repWindow.floor` per prescribed set —
    /// `LoggerModel.seedRows` and `previousLabel` are the same two numbers, so
    /// this genuinely is "what the previous column says". Wave E4's `SessionSeed`
    /// replaces that seed with the last real non-maintenance session of this day,
    /// matched by canonical name; when it lands, THIS is the property that
    /// re-points at it, and the chip starts comparing against a session that
    /// happened.
    ///
    /// A bodyweight movement has no `wk1Kg`; it is seeded at the athlete's
    /// weigh-in, the same credit `totalVolumeKg` gives it (Q13), or the chip
    /// would read high by body weight × reps on every pull-up day.
    private var seedTonnage: Double {
        let bodyWeightKg = model.bodyWeightKg
        return model.exercises.reduce(0) { total, exercise in
            guard let kg = exercise.plan.wk1Kg ?? (Bodyweight.isBodyweight(exercise.name) ? bodyWeightKg : nil),
                  let window = exercise.plan.repWindow
            else { return total }
            return total + kg * Double(window.floor) * Double(exercise.plan.sets(for: model.phase))
        }
    }

    // MARK: - Exercises

    private var exercisesCard: some View {
        // "Exercises" left the second line unexplained — top set, last set, or
        // working weight? The card's own register label is the cheapest place
        // to answer it once for every row.
        card("Top set by exercise") {
            VStack(spacing: 0) {
                ForEach(model.exercises) { exercise in
                    exerciseRow(exercise)
                    if exercise.id != model.exercises.last?.id {
                        Divider().overlay(Color.onyx.hairline)
                    }
                }
            }
        }
    }

    private func exerciseRow(_ exercise: LoggerModel.ExerciseState) -> some View {
        HStack(alignment: .center, spacing: OnyxSpace.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.name)
                    .onyxType(.body)
                    .foregroundStyle(exercise.isComplete ? Color.onyx.textSecondary : Color.onyx.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(topSetLabel(exercise))
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: OnyxSpace.s)
            progressionChip(exercise)
            setDots(exercise)
        }
        .frame(minHeight: 40)
        .padding(.vertical, OnyxSpace.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(exercise.name)
        .accessibilityValue("\(exercise.workingSets) of \(exercise.plan.sets(for: model.phase)) sets. \(topSetLabel(exercise))")
    }

    /// The biggest set ticked so far BY VOLUME — the one number that says how
    /// the movement is going without reading four rows of it.
    ///
    /// ── WHY VOLUME AND NOT (WEIGHT, REPS) ───────────────────────────────────
    /// It used to sort on the pair, which is "heaviest, then longest at that
    /// weight" — so a back-off set of 40 kg × 12 (480 kg) lost to a single at
    /// 42.5 × 4 (170 kg), and the row reported the smaller piece of work as the
    /// movement's top set. `Heaviest` is already its own row on the Top Lifts
    /// card above; this card's question is which set did the most.
    ///
    /// `SetRow.volumeKg` is the same product `totalVolumeKg` sums, so the row
    /// and the card's headline cannot disagree about what a set was worth.
    private func topSetLabel(_ exercise: LoggerModel.ExerciseState) -> String {
        let done = exercise.rows.filter { $0.isDone && $0.kind != .ghost }
        guard let top = done.max(by: { $0.volumeKg < $1.volumeKg }),
              top.volumeKg > 0, let kg = top.weightKg, let reps = top.reps else {
            // Nothing ticked yet. The question a row like that is actually
            // asking is "what am I meant to do", so it answers with the
            // prescription rather than with a dash — and a rep window carries
            // no kilograms, so it can never be misread as a set you logged.
            if let window = exercise.plan.repWindow {
                return "@ \(window.floor)–\(window.ceiling)"
            }
            return exercise.plan.reps
        }
        return "\(OnyxFormat.kg(kg)) kg × \(reps)"
    }

    /// Done against prescribed, as marks rather than a fraction.
    ///
    /// Four dots are read at a glance and "3/4" is read as arithmetic. Above
    /// eight the dots stop being countable and the fraction is the better
    /// answer, so the row falls back to it rather than drawing a bar code.
    @ViewBuilder
    private func setDots(_ exercise: LoggerModel.ExerciseState) -> some View {
        // ── ONE FOLD, AND IT LIVES IN THE MODEL ────────────────────────────
        // This counted SETS rather than rows — `workingSets` folds each
        // `pairId` once, so a three-set lunge with all three ticked drew three
        // filled dots out of SIX — and it counted them HERE, in a view, which
        // is the second copy of a rule the deck already owns.
        //
        // `LoggerModel.dotProgress` is that rule plus the one case a lifting
        // numerator cannot express: the opening treadmill bout is minted
        // `kind: .warmup` on purpose, to keep it out of tonnage, out of
        // `workingSets` and out of the PR engine — so a bout you HAD done read
        // 0 of 1 planned forever, the one row on this timeline that could never
        // be filled.
        let (done, planned) = model.dotProgress(for: exercise)
        let tint = dotTint(exercise)
        if planned > 8 {
            Text("\(done)/\(planned)")
                .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
                .fixedSize()
        } else {
            HStack(spacing: 4) {
                ForEach(0..<planned, id: \.self) { index in
                    // A ring at 7 pt in an 8 % hairline is invisible on this
                    // ground; an unfilled dot is a FILLED one in tertiary ink,
                    // which is legible and still unmistakably not done.
                    Circle()
                        .fill(index < done ? tint : Color.onyx.textTertiary.opacity(0.35))
                        .frame(width: 8, height: 8)
                }
            }
            .animation(OnyxMotion.move, value: done)
            .accessibilityHidden(true)
        }
    }

    /// The colour a movement's dots are filled in: the muscle the movement is
    /// FOR, not the day it happens to sit in.
    ///
    /// ── WHY THE DAY ACCENT WAS THE WRONG ANSWER ─────────────────────────────
    /// Every row on this timeline drew the same hue, so the only thing colour
    /// said was "this is a Legs day" — which the title two cards up has already
    /// said, and which does not change between rows. The muscle palette is
    /// sixteen colours with a measured separation (`OnyxTokens` §W3), and the
    /// Lock Screen, the deck's own rail and the atlas figure all call one
    /// muscle by one colour: `LoggerModel.primaryMuscle(of:)` is the single
    /// resolver they share, so a row here and the chip on your Lock Screen
    /// cannot name the same set two different colours.
    ///
    /// A cardio bout takes `Color.onyx.cardio` — it has no landmark and the
    /// body domain is what every other cardio mark in the app is drawn in.
    private func dotTint(_ exercise: LoggerModel.ExerciseState) -> Color {
        guard let token = LoggerModel.primaryMuscle(of: exercise) else { return accent }
        if let muscle = LandmarkMuscle.from(token: token) { return Color.onyx.muscle(muscle) }
        return Color.onyx.cardio
    }

    /// `▲ +2.5` when the ladder says raise it, `1 more` when one more session at
    /// the ceiling would.
    ///
    /// ── WHAT IT CAN SEE TODAY ───────────────────────────────────────────────
    /// `Ceilings.progressionVerdict` grades the last TWO sessions and only this
    /// one is in memory, so the reachable verdicts are `one-more` and `no`.
    /// Wave E4's `SessionSeed` puts the previous non-maintenance session in front
    /// of it, and `.ready` — the `▲ +2.5` — starts firing without this view
    /// changing: it is the ARRAY that gains an element.
    @ViewBuilder
    private func progressionChip(_ exercise: LoggerModel.ExerciseState) -> some View {
        let sets = exercise.rows
            .filter { $0.isDone && $0.kind == .normal }
            .compactMap { row -> WorkingSet? in
                guard let kg = row.weightKg, let reps = row.reps else { return nil }
                return WorkingSet(weightKg: kg, reps: Double(reps))
            }
        let verdict = Ceilings.progressionVerdict(
            [sets], ceiling: exercise.plan.repWindow.map { Double($0.ceiling) }
        )
        switch verdict.state {
        case .ready:
            chip(
                verdict.suggestKg.map { "▲ \(OnyxFormat.kg($0)) kg" } ?? "▲ Ready",
                Color.onyx.good
            )
        case .oneMore:
            chip("1 more", accent)
        case .no:
            EmptyView()
        }
    }

    private func chip(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, OnyxSpace.s)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
    }

    // MARK: - Muscle focus

    /// The body, filled in as the session lands on it.
    ///
    /// It replaces "Muscle distribution" in the three-dot menu, and it is a
    /// PREVIEW: the ranked legend and the two totals still live in the sheet,
    /// which this card opens. What the card has to answer on its own is the
    /// question the menu item was buried under — "is all of this on one side of
    /// me" — and a body answers that without being read.
    private var muscleCard: some View {
        card("Muscle focus", accessory: "Distribution", action: onMuscleFocus) {
            let sets = model.muscleSets
            VStack(spacing: OnyxSpace.s) {
                if sets.isEmpty {
                    Text("Tick a set and the body fills in.")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, OnyxSpace.m)
                } else {
                    AtlasFigure(worked: MuscleCredit.worked(from: sets))
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)
                        .accessibilityHidden(true)
                    topMuscles(sets)
                }
            }
        }
    }

    /// The three that carried it, in words — the figure says WHERE and this says
    /// how much, which is the half a shape cannot carry.
    private func topMuscles(_ sets: [LandmarkMuscle: Double]) -> some View {
        let ranked = LandmarkMuscle.allCases
            .compactMap { muscle -> (LandmarkMuscle, Double)? in
                guard let value = sets[muscle], value > 0 else { return nil }
                return (muscle, value)
            }
            // Ties break on the landmark's own order, so the row cannot
            // reshuffle under the reader between two ticks.
            .sorted { $0.1 > $1.1 }
            .prefix(3)
        return HStack(spacing: OnyxSpace.m) {
            ForEach(Array(ranked), id: \.0) { muscle, value in
                HStack(spacing: OnyxSpace.xs) {
                    Circle()
                        .fill(Color.onyx.muscle(muscle))
                        .frame(width: 7, height: 7)
                    Text(muscle.displayName)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                    Text(OnyxFormat.sets(value))
                        .fontWeight(.semibold).onyxNumeral()
                        .foregroundStyle(Color.onyx.textPrimary)
                }
                .onyxType(.caption)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Heaviest muscles")
    }

    // MARK: - Top lifts

    /// The session's three superlatives — the hardest set, the heaviest thing
    /// moved, the best estimated single — under the MOVEMENT that won them.
    ///
    /// ── WHY THREE, AND WHY NOT A LEADERBOARD ────────────────────────────────
    /// "Top set by exercise" below answers PER MOVEMENT and is as long as the
    /// day's list. These three are about the SESSION, and they are three
    /// different orderings of the same ticked rows rather than three questions
    /// — which is why none of them is a store query: every number here is
    /// already in `model.exercises`, the same rows the deck is drawing.
    ///
    /// ── AND WHY THE ARITHMETIC LEFT THIS FILE ───────────────────────────────
    /// The three maxima were computed here, keyed by ROLE, so a session carried
    /// by one lift printed that lift's name three times — the name set at body
    /// weight on all three rows and the one thing the reader already knew from
    /// the row above. `TopLifts.group` (OnyxCore, golden-tested) owns the
    /// maxima, the tie rule, the delta against the last session and the record
    /// test now; this view asks it once and draws what comes back.
    private var topLiftsCard: some View {
        card("Top lifts") {
            let groups = topLiftGroups
            if groups.isEmpty {
                Text("Tick a set and the session's best three land here.")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: OnyxSpace.s) {
                    ForEach(groups, id: \.exercise) { group in
                        topLiftGroup(group)
                    }
                }
            }
        }
    }

    /// The ticked rows, as the engine takes them.
    ///
    /// ── THE RECORD AXES ARE MATCHED PER MOVEMENT, NOT PER SET ───────────────
    /// `livePrs` carries the movement and the axis; linking one to an
    /// individual row would need a set number plumbed out of `LoggerModel`'s PR
    /// pass. It does not need one: the set that takes an exercise's WEIGHT
    /// record is that exercise's heaviest set, and the set that takes its e1RM
    /// record is its best estimated single — which are exactly the sets the
    /// Heaviest and 1RM roles pick. Hardest has no axis and never flames.
    private var topLiftGroups: [TopLifts.Group] {
        // ── ONE KEY, CANONICAL, ON ALL THREE SIDES ──────────────────────────
        // `ExerciseState.name` is the PLAN's spelling; `LivePrRecord.exercise`
        // and the previous-session bar are both canonical
        // (`ExerciseAliases.canonicalName`). A program that spells a movement
        // as an alias — `Lat Pulldown (Cable)` is a live key in the table —
        // would then match neither, so that lift would carry no flame and no
        // arrow, ever, and its heading here would read differently from the
        // PRs card's heading for the same lift one card up.
        let axes = Dictionary(grouping: prs.livePrs, by: { ExerciseAliases.canonicalName($0.exercise) })
            .mapValues { Swift.Set($0.map(\.axis)) }
        let sets = model.exercises.flatMap { exercise in
            let key = ExerciseAliases.canonicalName(exercise.name)
            // ── WARM-UPS ARE NOT CANDIDATES ─────────────────────────────────
            // "Top" is a claim about the working sets — `SessionAnalysis`'s own
            // `topKg` says so, and `workingSets` is the same filter. A warm-up
            // could not usually win one of these, but the bar it is measured
            // against is working sets only, so leaving it in made the two sides
            // of the comparison two different questions.
            return exercise.rows
                .filter { $0.isDone && $0.kind != .ghost && $0.kind != .warmup }
                .compactMap { row -> TopLifts.Set? in
                    guard let kg = row.weightKg, let reps = row.reps else { return nil }
                    return TopLifts.Set(
                        exercise: key, kg: kg, reps: reps, rpe: row.rpe,
                        recordAxes: axes[key] ?? []
                    )
                }
        }
        return TopLifts.group(sets, previous: previousBests)
    }

    /// One movement's superlatives: the name once as a heading, then a row per
    /// role it won.
    ///
    /// The same fold the PRs card directly below makes, minus the gold — two
    /// cards that group the same way read as one list of movements rather than
    /// as two different kinds of table. No wash and no border here: the record
    /// card's tint MEANS record, and a neutral copy of it would be decoration.
    private func topLiftGroup(_ group: TopLifts.Group) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            Text(group.exercise)
                .onyxType(.body).fontWeight(.semibold)
                .foregroundStyle(Color.onyx.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 0) {
                ForEach(group.lifts, id: \.role) { lift in
                    topLiftRow(lift, in: group.exercise)
                    if lift.role != group.lifts.last?.role {
                        Divider().overlay(Color.onyx.hairline)
                    }
                }
            }
        }
    }

    /// A role's row. The movement's name is the group's heading, so the row
    /// leads with the thing that varies between rows.
    ///
    /// ── AND WHY IT IS A COLUMN AT AX5 ───────────────────────────────────────
    /// "Hardest" beside "RPE 9.5 · 49.5 kg" is two strings sharing 346 pt of
    /// card. At an accessibility size both hit their scale floor and truncate,
    /// and the half that gets cut is the figure — the answer, not the
    /// qualifier. Under it instead, which is the same trade `tonnage` makes
    /// with its delta chip two cards up.
    @ViewBuilder
    private func topLiftRow(_ lift: TopLifts.Lift, in exercise: String) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let label = Text(roleLabel(lift.role))
            .onyxType(.body)
            .foregroundStyle(Color.onyx.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        // No `layoutPriority`, for the reason the records row spells out: both
        // columns carry a scale factor, so they divide and both shrink rather
        // than one taking its ideal width and truncating the other.
        let figure = HStack(spacing: 6) {
            Text(figureText(lift))
                .onyxType(.body).fontWeight(.semibold).onyxNumeral()
                .foregroundStyle(lift.isRecord ? Color.onyx.record : Color.onyx.textPrimary)
                // Two lines at AX5, one everywhere else. `RPE 9.5 · 49.5 kg`
                // hits its scale floor beside the trend glyph and truncated to
                // `RPE 9.5 · 49.5…` — the kilograms, which is the half of the
                // reading the row is about. Wrapping is the same trade the
                // movement's name above it makes.
                .lineLimit(stacked ? 2 : 1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: stacked)
            trend(lift)
        }

        Group {
            if stacked {
                // No `Spacer` here: in a column it is a VERTICAL one and it
                // expands, which pushes the rows apart until the card is a
                // screen tall.
                VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                    label
                    figure
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: OnyxSpace.m) {
                    label
                    Spacer(minLength: OnyxSpace.s)
                    figure
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(roleLabel(lift.role)), \(exercise)")
        .accessibilityValue(spokenFigure(lift))
    }

    /// `▲` / `▼` against the same movement's last session, and the flame when
    /// this set took the role's record.
    ///
    /// ── A FALL IS SECONDARY INK, NEVER `danger` ─────────────────────────────
    /// One lighter session is information — a deload, a bad night, a movement
    /// swapped in after a heavy one — and the app has no colour for "you did
    /// worse". `danger` means a reading outside a safe range and is spent on
    /// heart rate; spending it here would make a normal Tuesday look like an
    /// alarm. Up is `good` because a rise IS the thing the block is for.
    @ViewBuilder
    private func trend(_ lift: TopLifts.Lift) -> some View {
        if lift.isRecord {
            Image(systemName: "flame.fill")
                .imageScale(.small)
                .foregroundStyle(Color.onyx.record)
        }
        switch lift.delta {
        case .up:
            Image(systemName: "arrow.up")
                .imageScale(.small)
                .foregroundStyle(Color.onyx.good)
        case .down:
            Image(systemName: "arrow.down")
                .imageScale(.small)
                .foregroundStyle(Color.onyx.textSecondary)
        case .flat, nil:
            // Level with last time draws nothing. A third glyph for "no change"
            // is a mark the reader has to learn in order to ignore.
            EmptyView()
        }
    }

    private func roleLabel(_ role: TopLifts.Role) -> String {
        switch role {
        case .hardest: "Hardest"
        case .heaviest: "Heaviest"
        case .oneRM: "1RM"
        }
    }

    /// The product `hardest` is scored on is a number with no unit and no
    /// meaning to anyone; the two figures it was made of are the reading.
    private func figureText(_ lift: TopLifts.Lift) -> String {
        switch lift.role {
        case .hardest:
            guard let rpe = lift.set.rpe else { return "\(OnyxFormat.kg(lift.set.kg)) kg" }
            return "RPE \(OnyxFormat.rpe(rpe)) · \(OnyxFormat.kg(lift.set.kg)) kg"
        case .heaviest, .oneRM:
            return "\(OnyxFormat.kg(lift.figure)) kg"
        }
    }

    private func spokenFigure(_ lift: TopLifts.Lift) -> String {
        var parts = [figureText(lift)]
        if lift.isRecord { parts.append("record") }
        switch lift.delta {
        case .up: parts.append("up on last time")
        case .down: parts.append("down on last time")
        case .flat: parts.append("level with last time")
        case nil: break
        }
        return parts.joined(separator: ", ")
    }


    // MARK: - Records

    /// Drawn only when there is one — the deck gates it, so this never has an
    /// empty state to draw.
    /// ── GROUPED BY THE LIFT, BECAUSE THE LIFT IS WHAT REPEATS ──────────────
    /// One good set wins two axes and one good movement wins on three sets, so
    /// a session with two strong lifts in it drew a flat list of six rows —
    /// with the same exercise name set at body weight on four of them. The
    /// name was the largest thing on the card and it was the one thing the
    /// reader already knew from the row above.
    ///
    /// Now: a sub-card per movement, its name once at the top, and the axes it
    /// won underneath. The name is a heading rather than a repeated label, the
    /// axes lose the name they were carrying and get the width back, and the
    /// card's height falls by a line per duplicate.
    ///
    /// Order is preserved — `livePrs` is newest first, and a group takes the
    /// position of its newest record, so the lift you have just beaten stays at
    /// the top where the announcement belongs.
    private var recordsCard: some View {
        card("PRs") {
            let groups = groupedRecords
            VStack(spacing: OnyxSpace.s) {
                ForEach(groups, id: \.exercise) { group in
                    recordGroup(group)
                }
            }
        }
    }

    /// `livePrs` folded onto the movement, newest group first.
    private var groupedRecords: [(exercise: String, records: [LivePrRecord])] {
        var order: [String] = []
        var byExercise: [String: [LivePrRecord]] = [:]
        for record in prs.livePrs {
            if byExercise[record.exercise] == nil { order.append(record.exercise) }
            byExercise[record.exercise, default: []].append(record)
        }
        return order.map { (exercise: $0, records: byExercise[$0] ?? []) }
    }

    /// One movement's records: the name once, then a row per axis it won.
    private func recordGroup(_ group: (exercise: String, records: [LivePrRecord])) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            HStack(spacing: OnyxSpace.s) {
                Image(systemName: "trophy.fill")
                    .imageScale(.small)
                    .foregroundStyle(Color.onyx.record)
                Text(group.exercise)
                    .onyxType(.body).fontWeight(.semibold)
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                // How many claims this lift is carrying. A movement with three
                // is the headline of the session and the card should not make
                // you count rows to notice.
                Text("\(group.records.count)")
                    .onyxType(.caption).fontWeight(.bold).onyxNumeral()
                    .foregroundStyle(Color.onyx.record)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.onyx.record.opacity(0.14)))
            }
            VStack(spacing: 0) {
                ForEach(group.records) { record in
                    recordRow(record)
                    if record.id != group.records.last?.id {
                        Divider().overlay(Color.onyx.hairline)
                    }
                }
            }
        }
        .padding(OnyxSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .fill(Color.onyx.record.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .strokeBorder(Color.onyx.record.opacity(0.16), lineWidth: 1)
        }
    }

    private func recordRow(_ record: LivePrRecord) -> some View {
        HStack(spacing: OnyxSpace.m) {
            VStack(alignment: .leading, spacing: 1) {
                // The exercise name is the GROUP's heading now, so the row
                // leads with the thing that actually varies between rows.
                Text(record.axis.displayName)
                    .onyxType(.body)
                    .foregroundStyle(Color.onyx.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(record.setLabel)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: OnyxSpace.s)
            VStack(alignment: .trailing, spacing: 1) {
                Text(mark(record.mark.value, record.axis))
                    .onyxType(.body).fontWeight(.semibold).onyxNumeral()
                    .foregroundStyle(Color.onyx.record)
                // The mark it beat. A trophy without the old number is a
                // congratulation; with it, it is a measurement.
                Text("was \(mark(record.mark.previous, record.axis))")
                    .onyxType(.caption).onyxNumeral()
                    .foregroundStyle(Color.onyx.textTertiary)
            }
            // No `layoutPriority`: a priority-1 column takes its ideal width
            // first and the name gets the remainder, which at AX5 is an
            // ellipsis where the lift should be. Both columns carry
            // `lineLimit(1)` and a scale factor, so they divide and both shrink.
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        // The lift's name is a visual heading over the group now, and a
        // heading is not read with the row under it. Every row still says
        // which movement it belongs to.
        .accessibilityLabel("\(record.exercise), \(record.axis.displayName)")
    }

    private func mark(_ value: Double, _ axis: PrAxis) -> String {
        let unit = axis.unit
        let number = axis == .reps ? OnyxFormat.sets(value) : OnyxFormat.kg(value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    // MARK: - Effort

    /// Heart rate and calories, and where they came from.
    ///
    /// Calories are POST-HOC: the watch writes its own `HKWorkout` and the sync
    /// folds it in, which can be a day later. So this card's honest job is to
    /// say whether a number is measured, estimated, or not there yet — and to
    /// never present an estimate as a reading.
    ///
    /// ── THE HEART RATE IS NO LONGER ONE OF THEM (W10, decision 3) ───────────
    /// It was, and this comment said "live wrist heart rate is Phase 4". The
    /// consequence was that the cell read "—" for the whole of every session
    /// and filled in the next morning, on the one card called Effort. The wrist
    /// now sends its rate on the rest pulse (`RestPulse.bpm`), so while a watch
    /// is talking this cell is a LIVE reading and says so; when it goes quiet
    /// it falls back to the session's stored average, which is the number it
    /// always drew. `PhoneWatchBridge.liveBpm` has already aged the reading
    /// out, so there is no window in which a stale rate outranks a real one.
    private var liveBpm: Int? { environment?.watchBridge.liveBpm }

    private var effortCard: some View {
        card("Effort") {
            VStack(alignment: .leading, spacing: OnyxSpace.m) {
                HStack(spacing: OnyxSpace.m) {
                    effortCell(
                        // The label is the provenance. "Avg HR" over a reading
                        // taken four seconds ago is the card mislabelling the
                        // only number on it that is not an average.
                        liveBpm != nil ? "Heart rate" : "Avg HR", "heart.fill",
                        value: (liveBpm ?? session?.avgBpm).map { "\($0)" },
                        unit: "bpm",
                        tint: OnyxInk.Fixed.heart
                    )
                    effortCell(
                        "Calories", "flame.fill",
                        value: session?.caloriesBurned.map { "\($0)" },
                        unit: "kcal",
                        tint: Color.onyx.calories
                    )
                }
                Text(provenance)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func effortCell(
        _ label: String, _ symbol: String, value: String?, unit: String, tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.xs) {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .foregroundStyle(value == nil ? Color.onyx.textTertiary : tint)
                Text(value ?? "—")
                    .onyxType(.display).fontWeight(.semibold).onyxNumeral()
                    .foregroundStyle(value == nil ? Color.onyx.textTertiary : Color.onyx.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit).onyxMicro()
            }
            Text(label).onyxMicro()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value.map { "\($0) \(unit)" } ?? "Not recorded yet")
    }

    private var provenance: String {
        // Said first, because it is the one line here about a number that is
        // true RIGHT NOW rather than one the sync will correct later.
        if liveBpm != nil {
            return session?.caloriesBurned == nil
                ? "Heart rate live from your watch. Calories fill in from Apple Health once it has synced this workout."
                : "Heart rate live from your watch."
        }
        guard let session, session.avgBpm != nil || session.caloriesBurned != nil else {
            return "Fills in from Apple Health once the watch has synced this workout."
        }
        let measured = !session.avgBpmEstimated && !session.caloriesEstimated
        return measured
            ? "Measured from the watch's own workout."
            : "Estimated from your recent sessions. The finish sheet lets you correct either."
    }

    // MARK: - Card chrome

    /// One tile, with a register label and an optional way in.
    private func card<Content: View>(
        _ title: String,
        accessory: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            HStack {
                Text(title).onyxMicro()
                Spacer(minLength: OnyxSpace.s)
                if let accessory, let action {
                    Button(action: action) {
                        HStack(spacing: 2) {
                            Text(accessory)
                            Image(systemName: "chevron.right").imageScale(.small)
                        }
                        .onyxType(.caption).fontWeight(.semibold)
                        .foregroundStyle(accent)
                        .contentShape(Rectangle())
                    }
                    .onyxPress()
                }
            }
            content()
        }
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.tile)
    }
}


#if DEBUG
#Preview("Live Stats") {
    let model = LoggerModel.previewUpperB(logged: true)
    return LiveStatsView(
        model: model,
        clock: LoggerClock(startedAt: Date().addingTimeInterval(-22 * 60)),
        prs: SeedPrProvider(model: model),
        onMuscleFocus: {}
    )
    .onyxScreen(.train)
    .foregroundStyle(Color.onyx.textPrimary)
    .preferredColorScheme(.dark)
}
#endif
