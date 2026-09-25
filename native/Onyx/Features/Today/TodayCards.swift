import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

// MARK: - Now strip
//
// ── ONE ROW, THREE FACTS, NO SECOND OPINION ──────────────────────────────────
// This replaces a 104 pt orb that drew the battery as a ring AND as a numeral
// AND spelled the readiness verdict out beside it — three renderings of two
// numbers, in the most valuable 160 pt on the screen, above a coach card that
// then said the verdict again in the same words.
//
// What survives is what could not be read anywhere else on this screen: the
// day's score as a numeral, the battery as a ring (different question, so a
// different shape), and what today's training actually is. The verdict lost its
// home when the coach card went (§W5.3) and gets a breakdown tile of its own in
// Wave 10; the Recovery tile carries it meanwhile. The sync caption rides here because it
// is the answer to "is what I am looking at current", which is a question about
// this whole screen and not about any one tile in it.

struct NowStrip: View {
    let score: Int?
    let battery: Int?
    let workout: OnyxSnapshot.Workout?
    let status: SyncStatus
    /// Tap goes to Pulse — the tab that owns every number in this row.
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var batteryColor: Color { Color.onyx.battery(battery) }

    /// 36 pt, no numeral inside it. A ring this size cannot hold a legible
    /// number at any type size, and the one it would hold is already the
    /// numeral beside it.
    private var ring: some View {
        ZStack {
            Circle().stroke(Color.onyx.hairline, lineWidth: 4)
            Circle()
                .trim(from: 0, to: Double(battery ?? 0) / 100)
                .stroke(batteryColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : OnyxMotion.counter, value: battery)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(score.map { "\($0)" } ?? "—")
                .onyxDisplay().onyxNumeral()
                .foregroundStyle(Color.onyx.textPrimary)
            Text("SCORE")
                .onyxMicro()
        }
        // Capped (W6 polish): uncapped, the strip's 81 grew to ~100 pt at AX5
        // and out-shouted the Recovery ring's 81 below it — two heroes on one
        // screen. The ring is Today's hero; this is its one-line summary.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// Today's training, in the fewest words that are still true. A rest day is
    /// a real answer and gets the same chip rather than an empty space.
    private var sessionChip: some View {
        let label = workout.map { $0.isRestDay ? "Rest day" : $0.label } ?? "No plan"
        let tint = workout?.isRestDay == false ? OnyxDomain.train.accent : Color.onyx.textSecondary
        return HStack(spacing: OnyxSpace.xs) {
            if workout?.logged == true {
                Image(systemName: "checkmark").onyxType(.caption).fontWeight(.bold)
            }
            Text(label).onyxType(.caption).fontWeight(.semibold)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, OnyxSpace.s)
        .padding(.vertical, OnyxSpace.xs)
        .background(Capsule().fill(tint.opacity(0.14)))
    }

    var body: some View {
        Button(action: onOpen) {
            Group {
                if typeSize.isAccessibilitySize {
                    // At accessibility sizes the chip and the caption cannot
                    // share a line with a numeral. Stacking is the only honest
                    // answer; truncating the split name is not.
                    VStack(alignment: .leading, spacing: OnyxSpace.s) {
                        HStack(spacing: OnyxSpace.m) { ring; reading; Spacer(minLength: 0) }
                        sessionChip
                        caption
                    }
                } else {
                    HStack(spacing: OnyxSpace.m) {
                        ring
                        reading
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: OnyxSpace.xs) {
                            sessionChip
                            caption
                        }
                    }
                }
            }
            .padding(OnyxSpace.m)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .onyxGlass(.tile)
        }
        .buttonStyle(OnyxPressStyle())
        // An explicit label REPLACES the children, so the caption has to be
        // said here or it is said nowhere — and "Sync failed" is the one thing
        // on this screen a VoiceOver user cannot afford to miss (the hairline
        // is decorative and hidden).
        .accessibilityLabel("Score \(score.map { "\($0)" } ?? "unknown"), battery \(battery.map { "\($0) percent" } ?? "unknown"). \(workout.map { $0.isRestDay ? "Rest day" : $0.label } ?? ""). \(status.caption(at: .now) ?? "")")
        .accessibilityHint("Opens Pulse.")
    }

    /// A `TimelineView` around the one `Text` that ages, rather than a timer on
    /// the model: SwiftUI stops a timeline that is off screen or backgrounded,
    /// and the redraw is scoped to the caption instead of the whole card.
    @ViewBuilder
    private var caption: some View {
        // The `if` is OUTSIDE the timeline: a `TimelineView` whose body renders
        // nothing still occupies a slot in the stack, which is a 4 pt gap under
        // the chip on a device that has never synced.
        if status.lastSync != nil || status.phase != .idle {
            TimelineView(.periodic(from: status.lastSync ?? .now, by: 1)) { context in
                if let text = status.caption(at: context.date) {
                    // §3.3 reserves `micro` for LABELS; this is a reading.
                    Text(text)
                        .onyxType(.caption)
                        .foregroundStyle(status.phase == .idle ? Color.onyx.textTertiary : Color.onyx.textSecondary)
                }
            }
        }
    }
}

/// The readiness verdict's colour, from tokens rather than the hex the result
/// carries — the hex is the web's and the fixture's, not a view's.
enum ReadinessColor {
    static func of(_ r: ReadinessResult) -> Color {
        switch r.level {
        case .trainHard: Color.onyx.good
        case .trainLight: OnyxDomain.fuel.accent
        case .rest: Color.onyx.textSecondary
        }
    }
}

// MARK: - Weekly summary CTA

struct WeeklySummaryCTA: View {
    @Environment(AppEnvironment.self) private var environment
    let weekStart: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .onyxType(.body)
                    // A glyph in a fixed disc: the row's own copy scales, this
                    // does not, or the disc stops being a disc.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(Color.onyx.record)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.onyx.record.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Week \(Int(Week.number(ofWeekStart: weekStart, anchor: environment.targets?.schedule.weekZeroStart))) is complete")
                        .onyxType(.secondary).fontWeight(.semibold)
                        .foregroundStyle(Color.onyx.textPrimary)
                    Text("Every session logged. Review the week.")
                        .onyxType(.caption)
                        .foregroundStyle(Color.onyx.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").onyxType(.caption).fontWeight(.semibold).foregroundStyle(Color.onyx.textTertiary)
            }
            .padding(OnyxSpace.m)
            .onyxGlass(.tile)
        }
        .buttonStyle(OnyxPressStyle())
    }
}

// MARK: - Goal Board

/// The phase, as three numbers.
///
/// ── WHY THIS REPLACED THE INSIGHT COACH ─────────────────────────────────────
/// The coach drew correlations — "nights over 7 h precede your three heaviest
/// sessions (r = 0.71)" — and nothing about the day changed on the strength of
/// one. It also said the readiness verdict a second time, in the same words the
/// strip above it had already used.
///
/// A phase asks exactly one question: is the scale moving at the rate the phase
/// asked for, when does it arrive, and what has the week's ledger actually
/// been. Those three are on the row, and each of them can be wrong in a way you
/// would act on.
struct GoalBoardRow: View {
    let board: GoalBoard

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            HStack(alignment: .top, spacing: OnyxSpace.m) {
                cell("RATE", rateText, sub: bandText, ink: paceInk)
                cell("ARRIVES", etaText, sub: weeksText, ink: Color.onyx.textPrimary)
                cell("THIS WEEK", balanceText, sub: daysText, ink: balanceInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 64 pt at the default size — a label, a figure and one line under it.
        // It grows with the type scale rather than clipping, because a fixed
        // height is a promise a Dynamic Type setting can break.
        .frame(minHeight: 64)
        .padding(OnyxSpace.m)
        .onyxGlass(.tile)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }

    private func cell(_ label: String, _ value: String, sub: String, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .onyxType(.micro)
                .foregroundStyle(Color.onyx.textTertiary)
            Text(value)
                .onyxType(.secondary).fontWeight(.semibold).onyxNumeral()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .onyxType(.caption).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The three figures

    private var rateText: String {
        guard let rate = board.ratePerWeekKg else { return "—" }
        return "\(signed(rate, fraction: 2)) kg"
    }

    private var bandText: String {
        guard let lo = board.targetRateMinKgWk, let hi = board.targetRateMaxKgWk else { return "per week" }
        let low = min(lo, hi), high = max(lo, hi)
        return "want \(signed(low, fraction: 2)) to \(signed(high, fraction: 2))"
    }

    private var etaText: String {
        guard let eta = board.etaISO else { return "—" }
        return Self.short.string(from: eta) ?? "—"
    }

    private var weeksText: String {
        guard let weeks = board.weeksToTarget else {
            // Not "never": the rate is either unknown or pointing the other
            // way, and those are different facts to be told.
            return board.ratePerWeekKg == nil ? "no trend yet" : "wrong way"
        }
        guard let target = board.targetWeightKg else { return "\(OnyxFormat.rpe(weeks)) wks" }
        return "\(OnyxFormat.rpe(weeks)) wks to \(OnyxFormat.kg(target))"
    }

    private var balanceText: String {
        guard let kcal = board.weekBalanceKcal else { return "—" }
        return "\(signed(kcal, fraction: 0)) kcal"
    }

    private var daysText: String {
        board.weekDaysCounted == 0 ? "no full days yet" : "over \(board.weekDaysCounted) days"
    }

    // MARK: Ink

    /// The pace decides the rate's colour, and only the rate's: a deficit is
    /// not good or bad on its own, it is the rate's cause.
    private var paceInk: Color {
        switch board.pace {
        case .onTrack: Color.onyx.good
        case .under, .over: OnyxDomain.fuel.accent
        case .reversed: Color.onyx.danger
        case .unknown: Color.onyx.textPrimary
        }
    }

    private var balanceInk: Color {
        guard let kcal = board.weekBalanceKcal, board.weekDaysCounted > 0 else { return Color.onyx.textPrimary }
        // Signed against the phase, not against zero: a deficit is the point on
        // a cut and the failure on a bulk.
        let wantsDeficit = (board.targetRateMinKgWk ?? 0) + (board.targetRateMaxKgWk ?? 0) < 0
        return (kcal < 0) == wantsDeficit ? Color.onyx.textPrimary : OnyxDomain.fuel.accent
    }

    private var spoken: String {
        "Goal board. Rate \(rateText) per week, \(bandText). Arrives \(etaText), \(weeksText). This week \(balanceText), \(daysText)."
    }

    /// A rate of `-0.46` reads `−0.46`; `+0.22` keeps its plus, because the
    /// sign is the whole message on a bulk.
    private func signed(_ value: Double, fraction: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = fraction
        formatter.minimumFractionDigits = fraction
        formatter.positivePrefix = "+"
        formatter.negativePrefix = "−"
        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }

    /// `12 Nov`. One formatter, because building a `DateFormatter` per row is
    /// the classic way to make a list scroll badly.
    private static let short: ISOShortDate = ISOShortDate()
}

/// ISO in, `12 Nov` out.
struct ISOShortDate {
    private let parser: DateFormatter
    private let printer: DateFormatter

    init() {
        parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        printer = DateFormatter()
        printer.setLocalizedDateFormatFromTemplate("d MMM")
    }

    func string(from iso: String) -> String? {
        parser.date(from: iso).map { printer.string(from: $0) }
    }
}

// MARK: - Week so far

struct WeekSoFarView: View {
    let week: WeekSoFarSummary

    /// ── WHY THIS IS A ROW AND NOT A CARD ────────────────────────────────────
    /// It was a tile: a 52 pt ring beside three stacked lines — the week and the
    /// day, the change against last week, and a tonnage-and-sleep line that the
    /// Trends door already draws properly. Three lines to say "you are on
    /// schedule", above the grid that is what Today is actually for.
    ///
    /// §3.1 gives the rule and §5.1 applied it here: rows are 44 pt and never
    /// taller unless there are genuinely two lines of content. The week's shape
    /// is one line — where you are, and whether it is up or down — and the
    /// numbers behind it live one tap away.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: OnyxSpace.m) {
                ring
                Text(position)
                    .onyxType(.secondary)
                    .foregroundStyle(Color.onyx.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: OnyxSpace.s)
                change
            }
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                HStack(spacing: OnyxSpace.s) {
                    ring
                    Text(position)
                        .onyxType(.secondary)
                        .foregroundStyle(Color.onyx.textSecondary)
                        .lineLimit(1)
                }
                change
            }
            .padding(.vertical, OnyxSpace.s)
        }
        .padding(.horizontal, OnyxSpace.m)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(position). \(spokenChange)")
    }

    private var position: String {
        "Week \(week.weekNumber) · \(week.current.sessions) of \(max(1, week.sessionTarget)) sessions"
    }

    private var spokenChange: String {
        guard let change = week.change else { return "Level with last week so far." }
        return "\(change.label) \(change.text) versus last week."
    }

    /// The change, or the absence of one — never a blank space where a verdict
    /// would go. A row that shows nothing when nothing moved reads as a row
    /// that failed to load.
    @ViewBuilder
    private var change: some View {
        if let change = week.change {
            HStack(spacing: OnyxSpace.xs) {
                Image(systemName: change.direction == .up ? "arrow.up.right" : "arrow.down.right")
                Text(change.label)
                    .foregroundStyle(Color.onyx.textSecondary)
                Text(change.text).onyxNumeral()
            }
            .onyxType(.caption).fontWeight(.semibold)
            .foregroundStyle(change.good ? Color.onyx.good : Color.onyx.danger)
            .lineLimit(1)
        } else {
            Text("Level")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textTertiary)
        }
    }

    /// Decorative: the reading is spoken by the row's own label. Small enough
    /// that type inside it would be unreadable, so there is none — the count is
    /// in the line beside it, where it can grow with Dynamic Type.
    private var ring: some View {
        let target = max(1, week.sessionTarget)
        return ZStack {
            Circle().stroke(Color.onyx.hairline, lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1, Double(week.current.sessions) / Double(target)))
                .stroke(OnyxDomain.train.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}
