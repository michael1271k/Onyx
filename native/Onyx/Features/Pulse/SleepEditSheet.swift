import SwiftUI
import OnyxUI
import OnyxCore
import OnyxData

/// Re-window a night, and say the two things about it the watch cannot (§U5.2).
///
/// ── WHY ONE SHEET HOLDS THREE UNRELATED-LOOKING CONTROLS ────────────────────
/// The window, "trouble falling asleep" and "the watch got this wrong" are the
/// only three facts about a night that come from YOU. Everything else on the
/// Sleep tile is a measurement. Splitting them across a tile and a sheet is
/// what made the tile 330 pt tall in the first place; keeping them together
/// behind one tap is what lets the tile be a gauge and four readings.
///
/// ── THE PREVIEW IS STRATEGY B, AND IT SAYS SO ───────────────────────────────
/// `SleepTrim.trimStages` over the STORED minutes is exactly the branch
/// `AppDatabase.editSleepWindow` takes when the phone has no HealthKit samples
/// inside the new window — awake minutes go first, the asleep stages follow in
/// proportion, an extension is all core. When the store DOES have samples the
/// save re-aggregates them instead (strategy A) and the answer is better than
/// this one, never worse. So the preview is honest about being an estimate
/// rather than promising a number the save may improve on.
///
/// ── AND WHY THE WHEELS CARRY A DATE ─────────────────────────────────────────
/// A night straddles midnight, so an hour-and-minute wheel would need this
/// screen to guess which calendar day 01:20 meant — and the guess is wrong
/// exactly on the nights someone is editing (a nap folded in, a phone left on
/// the bed). `[.date, .hourAndMinute]` bounded to the night's own window makes
/// the wheel itself incapable of producing a bedtime the store would refuse,
/// which is the same guard `SleepEditError.outsideNight` enforces underneath.
struct SleepEditSheet: View {
    let model: DayModel

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The same gauge the tile draws, at the same size and by the same rule —
    /// `DepthArc` sets its own type off its diameter, so a FIXED 96 pt frame
    /// makes "7h 00m" the smallest text on the screen at AX5.
    @ScaledMetric(relativeTo: .title) private var arcSize: CGFloat = 96
    private var arcWidth: CGFloat { min(arcSize, 300) }

    /// A gauge with a stage list beside it needs ~190 pt for the list, and past
    /// xxLarge the names and their minutes both ellipsise — the first AX5 shot
    /// of this card was four rows of "… … 18%". (The rule was shared with the
    /// Sleep tile until W4; this sheet is the only surface drawing the night
    /// now, so the threshold lives here.)
    private var stacked: Bool { typeSize >= .xxLarge }

    @State private var start = Date()
    @State private var end = Date()
    /// What the last seed wrote into the wheels.
    ///
    /// `night` arrives on a stream, so a sheet opened before its first yield
    /// would otherwise keep the placeholder window forever — and re-seeding
    /// unconditionally would reset a wheel under the finger the moment a
    /// rescore landed. The wheels count as untouched while they still hold
    /// exactly what was written here, which is true until the user spins one.
    @State private var seeded: (start: Date, end: Date)?
    @State private var saving = false
    @State private var failure: String?

    private let accent = Color.onyx.accent(.recover)

    private var night: SleepSessionRow? { model.night }

    /// The row already carries the sleep sentinel — this night has been
    /// re-windowed before, and the pencil on the tile is why it looks the way
    /// it does.
    private var edited: Bool { ManualEntry.isManualSleep(night?.hkUuid) }

    /// `[prevDay 12:00Z, D 12:00Z)`. Qualified because `OnyxCore` publishes a
    /// `NightWindow` of its own (the ISO-string form the scorer speaks) and the
    /// app imports both modules.
    private var window: (from: Date, to: Date)? { OnyxData.NightWindow.range(model.date) }

    // MARK: - The arithmetic

    private var minutes: Int { max(0, Int((end.timeIntervalSince(start) / 60).rounded())) }

    private var goalMin: Int { Int((model.sleepGoalHours * 60).rounded()) }

    /// Strategy B over the stored row — the same call, with the same
    /// zero-length default for a night nobody has written yet, that
    /// `AppDatabase.editSleepWindow` makes.
    private var preview: TrimmedNight {
        let stages = NightStages(
            asleepMin: Double(night?.durationMin ?? 0),
            deepMin: Double(night?.deepMin ?? 0),
            remMin: Double(night?.remMin ?? 0),
            coreMin: Double(night?.coreMin ?? 0),
            awakeMin: Double(night?.awakeMin ?? 0)
        )
        return SleepTrim.trimStages(
            stages,
            oldSpanMin: night.map { $0.endTime.timeIntervalSince($0.startTime) / 60 } ?? 0,
            newSpanMin: end.timeIntervalSince(start) / 60
        )
    }

    /// The previewed stages, in the arc's own shape. A stage the trim leaves at
    /// zero draws no segment, which is what the tile does with an absent one.
    private var previewSegments: [(OnyxSleepStage, Int)] {
        let trimmed = preview
        return [
            (OnyxSleepStage.deep, Int(trimmed.deepMin)),
            (.rem, Int(trimmed.remMin)),
            (.core, Int(trimmed.coreMin)),
            (.awake, Int(trimmed.awakeMin)),
        ].filter { $0.1 > 0 }
    }

    private var canSave: Bool {
        guard !saving, end > start, let window else { return false }
        return start >= window.from && start < window.to
    }

    var body: some View {
        DaySheet(
            "Sleep window", domain: .recover, glass: false, detents: [.large],
            primary: ("Save", canSave, { save() })
        ) {
            Form {
                readingSection
                windowSection
                flagSection
            }
        }
        .task(id: night?.id) { seed() }
    }

    private func seed() {
        if let seeded, seeded.start != start || seeded.end != end { return }
        let bed = night?.startTime ?? defaultBed
        let wake = night?.endTime ?? bed.addingTimeInterval(model.sleepGoalHours * 3600)
        start = bed
        end = wake
        seeded = (bed, wake)
    }

    /// 23:00 on the previous LOCAL evening, clamped into the night's own UTC
    /// window. The window is a UTC tile and the sleeper is not, so far enough
    /// east the local evening falls before the tile opens — clamping is what
    /// keeps the first tap on a fresh night from opening on a bedtime the store
    /// would refuse.
    private var defaultBed: Date {
        let local = ISODate.addDays(model.date, -1).flatMap { DayModel.localInstant($0, hhmm: "23:00") }
        guard let window else { return local ?? Date() }
        let wanted = local ?? OnyxData.NightWindow.fallbackBedTime(model.date) ?? window.from
        return min(max(wanted, window.from), window.to.addingTimeInterval(-60))
    }

    // MARK: - A. What the night becomes

    /// The arc the tile will draw, drawn here first.
    ///
    /// One gauge, one implementation — the reason `DepthArc` is public. A
    /// preview rendered as its own bar chart would be a second answer to "what
    /// was this night made of", and the two would drift the first time either
    /// moved.
    private var readingSection: some View {
        Section {
            Group {
                if stacked {
                    VStack(alignment: .leading, spacing: OnyxSpace.m) {
                        arc
                        SleepStageList(segments: previewSegments)
                    }
                } else {
                    HStack(alignment: .top, spacing: OnyxSpace.m) {
                        arc.frame(width: arcWidth)
                        SleepStageList(segments: previewSegments)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, OnyxSpace.xs)
        } header: {
            OnyxSectionHeader("This night", .recover)
        } footer: {
            Text(previewNote)
        }
    }

    private var arc: some View {
        VStack(spacing: OnyxSpace.xs) {
            DepthArc(
                segments: previewSegments,
                minutes: minutes > 0 ? minutes : nil,
                goalMin: goalMin,
                lineWidth: 8,
                showsGoal: false
            )
            .frame(width: arcWidth, height: arcWidth * 0.72)
            Text(goalText)
                .onyxType(.caption).fontWeight(.semibold).onyxNumeral()
                .foregroundStyle(minutes >= goalMin - 5 ? Color.onyx.good : Color.onyx.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slept \(DayFormat.minutes(minutes))")
        .accessibilityValue(goalText)
    }

    private var goalText: String {
        guard minutes > 0 else { return "no window" }
        let gap = minutes - goalMin
        if abs(gap) <= 5 { return "goal met" }
        return "\(gap > 0 ? "+" : "−")\(DayFormat.minutes(abs(gap))) vs goal"
    }

    /// What the save will do to the stages, in one line. Short on purpose: it
    /// is a footer under a card that has already drawn the answer, and every
    /// extra line here is a line the two flags below fall past.
    private var previewNote: String {
        let trimmed = preview
        if night == nil { return "No night stored yet — the whole window is filed as core sleep." }
        if trimmed.cutMin > 0 {
            return "Estimated: \(DayFormat.minutes(Int(trimmed.cutMin))) off, awake first. Apple Health's own samples win where it has them."
        }
        if trimmed.addedMin > 0 {
            return "Estimated: \(DayFormat.minutes(Int(trimmed.addedMin))) added as core. Apple Health's own samples win where it has them."
        }
        return "Same span moved — the stages are unchanged."
    }

    // MARK: - B. The window

    private var windowSection: some View {
        Section {
            if let window {
                wheel(
                    "Asleep at", selection: $start,
                    in: window.from...window.to.addingTimeInterval(-60)
                )
                // The wake wheel reaches past the window's own close: the guard
                // the store enforces is on the BEDTIME, and a night that ran to
                // one in the afternoon is a real night, not a bad edit.
                wheel(
                    "Awake at", selection: $end,
                    in: window.from...window.to.addingTimeInterval(6 * 3600)
                )
            }
            // ── NO "DURATION" ROW ───────────────────────────────────────
            // The live duration is the numeral in the arc's own bowl, two
            // sections up, and it moves with the wheels. A 44 pt row repeating
            // it is the "no box that only repeats the box above it" rule
            // (§3.6) — and it was 44 pt of the reason the two flags below fell
            // off the first screen. An INVALID window still needs saying,
            // because the arc's answer for one is a silent em dash.
            if end <= start {
                Text("Awake has to come after asleep.")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.danger)
            }
            if let failure {
                Text(failure)
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.danger)
            }
        } header: {
            OnyxSectionHeader("Window", .recover)
        } footer: {
            Text(edited
                 ? "Edited before — Apple Health no longer overwrites this night."
                 : "Saved by hand: Apple Health stops overwriting this night.")
        }
    }

    /// ── 128 PT, NOT THE WHEEL'S OWN 216 ─────────────────────────────────────
    /// Two wheels at their intrinsic height plus the card above them is the
    /// whole sheet, and the two flags — the other half of what this screen is
    /// for — never come into view. A wheel drawn short shows three rows either
    /// side of the selection instead of five, which is still every row a thumb
    /// can reach, and it is what puts the toggles on the first screen.
    private func wheel(_ title: String, selection: Binding<Date>, in range: ClosedRange<Date>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).onyxMicro()
            DatePicker(title, selection: selection, in: range, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 128)
                .clipped()
        }
        .padding(.vertical, OnyxSpace.xs)
        .accessibilityLabel(title)
    }

    // MARK: - C. The two flags

    /// The pair that used to sit on the tile (§U5.1). Plain `Toggle` rows: in a
    /// `Form` the system switch IS the house style, and the reason they were
    /// drawn as bordered buttons on the tile — a 31 pt switch beside a 22 pt
    /// stage row — does not apply on a sheet with room.
    private var flagSection: some View {
        Section {
            Toggle("Trouble falling asleep", isOn: Binding(
                get: { model.log?.sleepOnsetTrouble ?? false },
                set: { model.setSleepOnsetTrouble($0) }
            ))
            Toggle("Watch data inaccurate", isOn: Binding(
                get: { model.log?.sleepInaccurate == true },
                set: { model.setSleepInaccurate($0) }
            ))
        } header: {
            OnyxSectionHeader("The night as you saw it", .recover)
        } footer: {
            // Two flags, two different consequences, and saying so is the only
            // way a reader can tell them apart: one is a stress input, the
            // other is a footnote that travels with the night.
            Text("Trouble falling asleep is a stress input. Marking the watch inaccurate changes no number — it travels with the night into the weekly export, so the reading can be discounted.")
        }
        .tint(accent)
    }

    // MARK: - Saving

    /// Both flags write on every tap already (they are `daily_logs` edits, not
    /// form state), so Save is about the WINDOW — and it is the only part of
    /// this sheet that can fail.
    private func save() {
        guard canSave else { return }
        saving = true
        failure = nil
        let start = start, end = end
        Task {
            do {
                let accepted = try await environment.editSleepWindow(date: model.date, start: start, end: end)
                saving = false
                if accepted {
                    dismiss()
                } else {
                    failure = "Signed out — the night was not saved."
                }
            } catch let error as SleepEditError {
                saving = false
                failure = switch error {
                case .emptyWindow:     "Awake has to come after asleep."
                case .badDate:         "This day cannot hold a night."
                case .outsideNight:    "That bedtime belongs to a different night."
                case .impossibleNight: "That is too long to be one night."
                }
            } catch {
                saving = false
                failure = error.localizedDescription
            }
        }
    }
}
