// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import WidgetKit
import SwiftUI
import Charts
import OnyxCore

// MARK: - The W12 faces
//
// Four tiles that draw a SERIES rather than a reading, and one shared rule:
// none of them derives anything. Every number here comes out of an
// `OnyxCore/Charts` builder that a golden vector pins, arrives on the snapshot
// whole, and is drawn. A face that computed its own weekly sum would be a
// second answer to a question the Goal Board row already prints — which is the
// split this project has paid for once already, with the streak.
//
// ── WHY THESE ARE A FIFTH FAMILY AND NOT FOUR MORE FOCUSES ──────────────────
// Fuel, Training, Body and Lock each answer one QUESTION at several
// granularities. These four answer a question none of them asks — is the block
// working — at four angles: am I arriving, am I showing up, does the ledger
// match the scale, where did the battery go. Bolting them onto the existing
// families would have put a weekly reconciliation behind a picker labelled
// "Fuel"; they get their own (`ProgressFocus`).

/// The family's dispatcher. Named `ProgressTileView` because `ProgressView` is
/// SwiftUI's, and a shadow of a stock control is a trap for whoever writes the
/// next face here.
public struct ProgressTileView: View {
  let entry: OnyxTileEntry
  let focus: ProgressFocus
  @Environment(\.widgetRenderingMode) private var mode

  public init(entry: OnyxTileEntry, focus: ProgressFocus) {
    self.entry = entry
    self.focus = focus
  }

  public var body: some View {
    Group {
      switch focus {
      case .trajectory:  TrajectoryView(entry: entry)
      case .consistency: ConsistencyView(entry: entry)
      case .deficit:     DeficitLedgerView(entry: entry)
      case .fatigue:     FatigueStackView(entry: entry)
      }
    }
    .containerBackground(Color.onyx.base, for: .widget)
    .widgetURL(focus.link(entry.snapshot?.date))
  }
}

// MARK: - Cut / Bulk trajectory

/// The scale over time, the corridor it was asked to stay in, and the date it
/// arrives.
///
/// ── THE BAND IS A CORRIDOR, NOT A PAIR OF NUMBERS ───────────────────────────
/// A phase asks for a RATE — "−0.50 to −0.40 kg a week" — which is a statement
/// about a slope and is unreadable as two numbers beside a line. Projected from
/// the window's first smoothed point it becomes a widening corridor on the same
/// axis as the weight, and then "am I on pace" is a question about whether the
/// line is inside the shape, which is answerable at a glance and at tile size.
public struct TrajectoryView: View {
  let entry: OnyxTileEntry
  @Environment(\.widgetFamily) private var hostFamily
  @Environment(\.onyxTileFamily) private var tileFamily
  @Environment(\.widgetRenderingMode) private var mode
  private var size: OnyxSize { OnyxSize(tileFamily ?? hostFamily) }
  private var mono: Bool { mode == .accented }

  public init(entry: OnyxTileEntry) { self.entry = entry }

  private var trajectory: Trajectory? { entry.snapshot?.trajectory }
  private var board: GoalBoard? { trajectory?.board }
  private var accent: Color { mono ? .white : OnyxDomain.body.accent }

  /// The title flips with the phase, because "on pace" means opposite things
  /// either side of it. Between phases it says neither.
  private var caption: String {
    switch trajectory?.phaseKind {
    case .cut:    "CUT TRAJECTORY"
    case .bulk:   "BULK TRAJECTORY"
    case .deload: "DELOAD TRAJECTORY"
    case .peak:   "PEAK TRAJECTORY"
    case nil:     "TRAJECTORY"
    }
  }

  /// The pace decides the rate's ink, and only the rate's.
  private var paceInk: Color {
    guard !mono else { return .white }
    switch board?.pace {
    case .onTrack:      return Color.onyx.good
    case .under, .over: return OnyxDomain.fuel.accent
    case .reversed:     return Color.onyx.danger
    default:            return Color.onyx.textPrimary
    }
  }

  public var body: some View {
    face.onyxMarked(monochrome: mono, hidden: entry.isStale)
  }

  @ViewBuilder private var face: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption(caption, color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      if let board, board.ratePerWeekKg != nil || trajectory?.points.isEmpty == false {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          BigValue(value: board.ratePerWeekKg.map { OnyxSeriesFormat.signed($0, decimals: 2) },
                   size: size == .small ? 26 : 30, color: paceInk)
          Text("kg/wk").font(OnyxWidgetType.face(11)).foregroundStyle(Color.onyx.textSecondary)
          Spacer(minLength: 0)
          etaChip(board)
        }
        if size == .small {
          bandLine
          Spacer(minLength: 0)
          if let points = trajectory?.points, points.count > 1 {
            Sparkline(points: points.map(\.ewma), color: accent).frame(height: 26)
          }
        } else {
          corridor
          bandLine
        }
      } else {
        OnyxChartEmpty("Three weigh-ins and the line starts.", compact: true)
      }
    }
  }

  /// "want −0.50 to −0.40" — the band as words, under a chart that draws it as
  /// a shape. Both, because the shape says whether and the words say what.
  @ViewBuilder private var bandLine: some View {
    if let lo = board?.targetRateMinKgWk, let hi = board?.targetRateMaxKgWk {
      Text("want \(OnyxSeriesFormat.signed(min(lo, hi), decimals: 2)) to \(OnyxSeriesFormat.signed(max(lo, hi), decimals: 2))")
        .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary).lineLimit(1)
    } else if let target = board?.targetWeightKg {
      Text("target \(String(format: "%.1f", target)) kg")
        .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary).lineLimit(1)
    }
  }

  @ViewBuilder private func etaChip(_ board: GoalBoard) -> some View {
    if let eta = board.etaISO, let weeks = board.weeksToTarget {
      Text("\(OnyxChart.date(eta).map(OnyxChart.shortDate) ?? eta) · \(OnyxSeriesFormat.trim(weeks)) wk")
        .font(OnyxWidgetType.face(10, weight: .semibold))
        .foregroundStyle(mono ? .white : accent)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill((mono ? Color.white : accent).opacity(0.16)))
        .lineLimit(1)
    }
  }

  /// The smoothed line inside the corridor the phase asked for.
  @ViewBuilder private var corridor: some View {
    let points = trajectory?.points ?? []
    if points.count > 1, let first = points.first, let start = OnyxSeriesFormat.day(first.d) {
      let lo = board?.targetRateMinKgWk
      let hi = board?.targetRateMaxKgWk
      let span = Double((OnyxSeriesFormat.day(points[points.count - 1].d) ?? start) - start) / 7
      // ── WHY THIS SETS ITS OWN Y DOMAIN ───────────────────────────────────
      // An `AreaMark` makes Swift Charts default the y-axis to ZERO-based, and
      // a bodyweight axis running 0…66 draws two kilos of movement as a
      // horizontal line pinned to the top of the plot. It did exactly that on
      // the first build. `tightDomain` is the same scaling every chart in the
      // app uses, fed the band's own bounds so the corridor cannot fall
      // outside the drawn area — which is precisely when it matters most.
      let bounds: [Double?] = points.map(\.ewma) + points.map(\.raw) + [
        lo.map { first.ewma + $0 * span }, hi.map { first.ewma + $0 * span },
        first.ewma,
      ]
      let domain = ChartScale.tightDomain(bounds)
      Chart {
        // The corridor, only when the phase has a band. Projected from the
        // window's first SMOOTHED point rather than its first raw reading: the
        // raw one is a morning, and anchoring a month of corridor to one
        // morning's water is how a band ends up 0.8 kg off from day one.
        if let lo, let hi {
          ForEach(points) { p in
            let weeks = Double((OnyxSeriesFormat.day(p.d) ?? start) - start) / 7
            AreaMark(
              x: .value("Day", OnyxChart.date(p.d) ?? Date()),
              yStart: .value("Low", first.ewma + min(lo, hi) * weeks),
              yEnd: .value("High", first.ewma + max(lo, hi) * weeks)
            )
            .foregroundStyle((mono ? Color.white : accent).opacity(0.16))
            .interpolationMethod(.linear)
          }
        }
        // ── THE RAW MORNINGS, AND WHY THEY HAVE TO BE HERE ─────────────
        // An EWMA LAGS. On a cut it sits above the true weight by roughly a
        // rate times a half-life, so a line drawn alone against a corridor
        // anchored to its own first point reads as "behind the band" on a
        // block that is exactly on pace. The dots are the measurements, they
        // sit inside the corridor when the phase is working, and the line is
        // what the eye follows through them.
        ForEach(points) { p in
          PointMark(
            x: .value("Day", OnyxChart.date(p.d) ?? Date()),
            y: .value("Reading", p.raw)
          )
          .symbolSize(9)
          .foregroundStyle((mono ? Color.white : accent).opacity(0.45))
        }
        ForEach(points) { p in
          LineMark(
            x: .value("Day", OnyxChart.date(p.d) ?? Date()),
            y: .value("Weight", p.ewma)
          )
          .foregroundStyle(mono ? .white : accent)
          .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
          .interpolationMethod(.monotone)
        }
      }
      .chartYScale(domain: domain.0...domain.1)
      .chartXAxis(.hidden)
      .chartYAxis(.hidden)
      .chartLegend(.hidden)
      .frame(maxHeight: .infinity)
    } else {
      Spacer(minLength: 0)
    }
  }
}

// MARK: - Consistency

/// Eight weeks of showing up, and the day count that only ever rises.
///
/// ── WHY THE GRID DRAWS FOUR STATES AND NOT TWO ──────────────────────────────
/// "Trained / did not" cannot tell a rest day from a missed one, and the whole
/// value of a consistency surface is that distinction: a fortnight of five-day
/// weeks and a fortnight of three-day weeks look identical in a heat map that
/// only knows about sessions. `ConsistencySeries` asks the SCHEDULE what each
/// day was for, so a scheduled day nothing landed on draws as a hollow ring —
/// the one mark on the tile a session list could never produce.
public struct ConsistencyView: View {
  let entry: OnyxTileEntry
  @Environment(\.widgetFamily) private var hostFamily
  @Environment(\.onyxTileFamily) private var tileFamily
  @Environment(\.widgetRenderingMode) private var mode
  private var size: OnyxSize { OnyxSize(tileFamily ?? hostFamily) }
  private var mono: Bool { mode == .accented }

  public init(entry: OnyxTileEntry) { self.entry = entry }

  private var model: Consistency? { entry.snapshot?.consistency }
  private var accent: Color { mono ? .white : OnyxDomain.train.accent }

  public var body: some View {
    face.onyxMarked(monochrome: mono, hidden: entry.isStale)
  }

  @ViewBuilder private var face: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption(size == .small ? "WEEK" : "CONSISTENCY", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) } else { flame }
      }
      // The corner belongs to the mark; this row's content runs to the edge.
      // Without it the flame sat under the Onyx mark on a Small.
      .padding(.trailing, OnyxMark.faceInset)

      if let model, model.planned > 0 {
        // ── THIS WEEK, NOT EIGHT (W6) ────────────────────────────────────
        // The hero was an eight-week adherence percentage — a figure that
        // moves by one point when you train and by one point when you do not,
        // and which on a Tuesday says nothing about Tuesday. The week is the
        // unit the plan is written in and the unit a missed session is felt
        // in, so the week leads and the eight-week rate becomes its caption.
        // ── THE SMALL SAYS THE RATIO AND NOTHING ELSE ──────────────────────
        // "2 of 3 planned · 89.5% over 8 wk" is 210 pt of sentence in a 134 pt
        // face, and the first shot of it truncated both halves. The Small folds
        // the denominator into the figure and drops the eight-week rate, which
        // the grid underneath is a picture of anyway.
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          BigValue(
            value: thisWeek.map { size == .small ? "\($0.done)/\($0.planned)" : "\($0.done)" },
            size: size == .small ? 24 : 30, color: Color.onyx.textPrimary)
          // The DENOMINATOR is the week's own planned count, not a literal 7.
          // A five-day plan graded out of seven is the "0/0 reads as a
          // failure" defect one axis over — `MuscleView.bar` states the same
          // rule about a family the plan asks nothing of.
          Text(size == .small ? "planned" : (thisWeek.map { "of \($0.planned) planned" } ?? "planned"))
            .font(OnyxWidgetType.face(size == .small ? 10 : 11))
            .foregroundStyle(Color.onyx.textSecondary)
            .lineLimit(1)
          Spacer(minLength: 0)
          if size != .small, let rate = model.adherencePct {
            Text("\(OnyxSeriesFormat.trim(rate))% over 8 wk")
              .font(OnyxWidgetType.face(9))
              .foregroundStyle(Color.onyx.textSecondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 0)
        grid(model)
      } else {
        OnyxChartEmpty("No plan to measure against yet.", compact: true)
      }
    }
  }

  /// The week the snapshot is in — the LAST of the eight, which
  /// `ConsistencySeries.build` runs up to `endingOn`.
  private var thisWeek: ConsistencyWeek? { model?.weeks.last }

  /// The programme day, which counts up and never resets — `Streak.current` is
  /// days since the cut opened, not a consecutive run (see `Snapshot.Streak`).
  @ViewBuilder private var flame: some View {
    if let day = entry.snapshot?.streak?.current, day > 0 {
      HStack(spacing: 2) {
        Image(systemName: "flame.fill").font(OnyxWidgetType.face(9))
        Text("\(day)").font(OnyxWidgetType.figure(10))
      }
      .foregroundStyle(mono ? .white : Color.onyx.record)
    }
  }

  /// Four columns of seven. A column is a week and a row is a weekday, so a
  /// Tuesday that keeps going missing is a horizontal gap rather than a
  /// scattering.
  ///
  /// ── WHY FOUR WEEKS AND NOT EIGHT (W6) ──────────────────────────────────
  /// Eight columns at a Small's width put the dots 3 pt apart with 3 pt of air
  /// between them, which is a texture — a reader could see that SOMETHING was
  /// missing and not which day. Four columns is the same fifty-six-pixel budget
  /// spent on twenty-eight marks instead of fifty-six, so a hollow ring is
  /// legible as a hollow ring. The eight-week rate is still on the face, as the
  /// caption above; it is the GRID that stops claiming to be readable at eight.
  ///
  /// The series is still built over eight weeks (`ConsistencySeries.build`) —
  /// nothing about the arithmetic changed, only how much of it is drawn.
  static let gridWeeks = 4

  private func grid(_ model: Consistency) -> some View {
    let dot: CGFloat = size == .small ? 7 : 9
    return HStack(spacing: size == .small ? 4 : 6) {
      ForEach(model.weeks.suffix(Self.gridWeeks)) { week in
        VStack(spacing: size == .small ? 4 : 5) {
          ForEach(week.cells) { cell in
            Self.mark(cell, size: dot, mono: mono)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("The last four weeks, one column each")
    .accessibilityValue(
      thisWeek.map { "this week, \($0.done) of \($0.planned) planned" } ?? "no plan"
    )
  }

  @ViewBuilder
  static func mark(_ cell: ConsistencyCell, size: CGFloat, mono: Bool) -> some View {
    let tint = mono ? Color.white : Color.onyx.day(cell.dayKey)
    switch cell.state {
    case .done:
      Circle().fill(tint).frame(width: size, height: size)
    case .extra:
      // A session nobody asked for is still a session. Ringed rather than
      // filled so the grid's filled dots stay a count of the PLAN.
      Circle().strokeBorder(mono ? .white : Color.onyx.good, lineWidth: 1.5).frame(width: size, height: size)
    case .missed:
      Circle().strokeBorder(tint.opacity(0.8), lineWidth: 1).frame(width: size, height: size)
    case .planned:
      Circle().strokeBorder(tint.opacity(0.3), lineWidth: 1).frame(width: size, height: size)
    case .rest:
      Circle().fill(Color.onyx.textTertiary.opacity(0.35))
        .frame(width: max(2, size - 3), height: max(2, size - 3))
        .frame(width: size, height: size)
    }
  }
}

// MARK: - Deficit ledger

/// What the ledger predicted, what the scale did, and the gap between them.
///
/// ── THE GAP IS THE POINT ────────────────────────────────────────────────────
/// Either number alone is a story that flatters or frightens. Together they are
/// a measurement of the MODEL: a ledger claiming −2.9 kg over eight weeks
/// against a scale that moved −1.0 is not a failed cut, it is an intake that is
/// under-counted or an active-energy estimate that is too generous, and it is
/// the only reading on the dashboard that can say so.
public struct DeficitLedgerView: View {
  let entry: OnyxTileEntry
  @Environment(\.widgetFamily) private var hostFamily
  @Environment(\.onyxTileFamily) private var tileFamily
  @Environment(\.widgetRenderingMode) private var mode
  private var size: OnyxSize { OnyxSize(tileFamily ?? hostFamily) }
  private var mono: Bool { mode == .accented }

  public init(entry: OnyxTileEntry) { self.entry = entry }

  private var model: DeficitLedger? { entry.snapshot?.deficit }
  private var accent: Color { mono ? .white : OnyxDomain.fuel.accent }

  public var body: some View {
    face.onyxMarked(monochrome: mono, hidden: entry.isStale)
  }

  /// The seven days behind today. Nil on a payload built before W6, which is
  /// the state the empty fixture photographs.
  private var days: [OnyxSnapshot.DayBalance] { entry.snapshot?.deficitDays ?? [] }

  @ViewBuilder private var face: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption("DEFICIT LEDGER", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }
      // The corner belongs to the mark; this row's content runs to the edge.
      .padding(.trailing, OnyxMark.faceInset)

      if let model, model.daysCounted > 0 {
        // ── THE MEDIUM IS TWO COLUMNS, AND HAD TO BE ──────────────────────
        // Seven rows stacked under a hero and over a reconciliation is about
        // 160 pt of content in a Medium's 134, and SwiftUI answers that by
        // clipping both ends — the first two shots of this face had no caption
        // at the top and half a label row off the bottom. Making the rows
        // compressible was not enough: a row's floor is its own TYPE, not its
        // bar. Side by side, the seven days get the full height and the
        // figures get a column of their own, which is the grammar every other
        // Medium in this package already uses.
        if size == .medium {
          HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
              hero
              Spacer(minLength: 0)
              reconciliation(model)
            }
            .frame(width: 128, alignment: .leading)
            Hairline(vertical: true)
            dayBars
          }
          .frame(maxHeight: .infinity)
        } else {
          hero
          dayBars
          reconciliation(model)
        }
      } else {
        OnyxChartEmpty("A day needs intake AND expenditure to count.", compact: true)
      }
    }
  }

  /// The week's balance. The reconciliation underneath says what the scale did
  /// about it; the seven bars say what the week was made of.
  @ViewBuilder private var hero: some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      BigValue(value: model?.weeks.last?.balanceKcal.map { OnyxSeriesFormat.signed($0, decimals: 0) },
               size: size == .large ? 28 : 22, color: Color.onyx.textPrimary)
      Text(size == .large ? "kcal this week" : "kcal")
        .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
        .lineLimit(1)
      Spacer(minLength: 0)
      if size == .large, let model {
        Text("\(model.daysCounted) d counted")
          .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary).lineLimit(1)
      }
    }
  }

  /// Seven days, each a bar hanging off ONE zero line.
  ///
  /// ── WHY DAYS REPLACED THE EIGHT WEEKS (W6) ──────────────────────────────
  /// The bars used to be the same eight weeks the reconciliation underneath
  /// already summarises — a chart of the row below it, on a tile whose hero is
  /// also one of those weeks. Three registers, one window. The days are the
  /// window nothing else on the face covers, and they are the one a reader can
  /// act on: a single 900 kcal Saturday is invisible in a weekly bar and is
  /// exactly what the week's number is made of.
  ///
  /// `DivergingBar` is shared with the stress breakdown (it moved into OnyxUI
  /// for this face); horizontal rather than vertical columns because a day
  /// needs its weekday beside it and seven initials under seven columns at a
  /// Small's width is 18 pt a letter.
  ///
  /// A day with a HOLE draws no bar at all — nil is not zero, and a day that
  /// broke even and a day that never synced must not look the same.
  @ViewBuilder private var dayBars: some View {
    if days.isEmpty {
      // A payload from before the field existed. The weekly reconciliation
      // below still reads, so this register simply stands down.
      EmptyView()
    } else {
      let extent = max(400, days.compactMap { $0.kcal.map(abs) }.max() ?? 400)
      let bar: CGFloat = size == .small ? 3 : 4
      // ── THE ROWS SHARE THE HEIGHT; THEY DO NOT CLAIM IT ───────────────────
      // Seven rows at their intrinsic height plus a hero and a reconciliation
      // is taller than a Medium, and SwiftUI resolves that by clipping BOTH
      // ends — the first shot of this face had no caption at the top and half a
      // reconciliation row off the bottom. `maxHeight: .infinity` on each row
      // makes the stack compressible, so the register gives way before the
      // things around it do.
      VStack(spacing: 1) {
        ForEach(days) { day in
          HStack(spacing: 6) {
            Text(OnyxSnapshot.weekdayInitial(day.d))
              .font(OnyxWidgetType.face(8, weight: .bold))
              .foregroundStyle(Color.onyx.textSecondary)
              .frame(width: 10, alignment: .leading)
            if let kcal = day.kcal {
              DivergingBar(value: kcal, extent: extent,
                           tint: kcal > 0 ? surplusInk : deficitInk)
                .frame(height: bar)
            } else {
              // The track alone: the day exists, the reading does not.
              Capsule().fill(Color.onyx.hairline).frame(height: bar)
            }
            if size != .small {
              Text(day.kcal.map { OnyxSeriesFormat.signed($0, decimals: 0) } ?? "—")
                .font(OnyxWidgetType.figure(9))
                .foregroundStyle(day.kcal == nil ? Color.onyx.textTertiary : Color.onyx.textSecondary)
                .frame(width: 40, alignment: .trailing)
            }
          }
          .frame(maxHeight: .infinity)
        }
      }
      .frame(maxHeight: .infinity)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Seven days of energy balance")
    }
  }

  /// A deficit is the point on a cut, so it wears the domain rather than a
  /// verdict colour; a surplus is the one that wants noticing.
  private var deficitInk: Color { mono ? .white : accent }
  private var surplusInk: Color { mono ? .white : OnyxDomain.fuel.end }

  /// "−2.88 predicted · −1.00 measured · 1.88 short" in the space a tile has.
  @ViewBuilder private func reconciliation(_ model: DeficitLedger) -> some View {
    HStack(spacing: 6) {
      Stat(value: model.expectedKg.map { OnyxSeriesFormat.signed($0, decimals: 2) },
           label: "PREDICTED", color: mono ? .white : accent)
      Stat(value: model.measuredKg.map { OnyxSeriesFormat.signed($0, decimals: 2) },
           label: "SCALE", color: Color.onyx.textPrimary)
      if size == .large {
        Stat(value: model.gapKg.map { OnyxSeriesFormat.signed($0, decimals: 2) },
             label: "GAP", color: Color.onyx.textSecondary)
      }
    }
  }
}

// MARK: - Fatigue / stress stack

/// A fortnight of battery, and how long each of those days was.
///
/// ── WHY THE STACK GAVE WAY TO A LINE (W6) ───────────────────────────────────
/// The five-band stack is the right drawing for one question — where did today's
/// battery GO — and it was answering it fourteen times at once. Fourteen columns
/// of five bands is seventy rectangles on a 158 pt tile, and the legend under
/// them needed five words to be read at all. What a tile called "Fatigue" is
/// looked at for is the shape of the fortnight: is the battery recovering or is
/// it grinding down.
///
/// So the reading is a line, and one band is kept behind it.
///
/// ── THE BAND IS THE DRAIN, AND THE BRIEF ASKED FOR AWAKE HOURS ──────────────
/// W6's brief said "shaded by awake hours", and awake hours cannot be drawn
/// from this payload: `WidgetSnapshotBuilder.batteryStackSlice` scores every
/// FINISHED day with `hoursAwake` pinned to `Battery.defaults.maxAwake`, on
/// purpose — "so a fortnight of bands does not shift under the wall clock" — so
/// the `time` drain is the SAME NUMBER on thirteen of the fourteen days. Shading
/// by it draws a flat grey rectangle that means nothing, which is what the first
/// shot of this face showed.
///
/// `totalDrain` is what actually moves, and it is the same question one step
/// up: how much the day took out of you. The five bands the stack used to draw
/// are its parts, and the worst of them is still named beside the figure.
/// Getting the brief's version needs a stored per-day awake figure, not a
/// different drain here.
///
/// ── THE FORTNIGHT HAS HOLES AND THE LINE CANNOT LIFT THE PEN ────────────────
/// `Sparkline` takes `[Double]`, so an unscored day is DROPPED rather than
/// drawn as a zero, and the caption says how many of the fourteen the line
/// actually covers — the same treatment, for the same reason, that the stress
/// sparkline's "13 of 14 d" gets.
public struct FatigueStackView: View {
  let entry: OnyxTileEntry
  @Environment(\.widgetFamily) private var hostFamily
  @Environment(\.onyxTileFamily) private var tileFamily
  @Environment(\.widgetRenderingMode) private var mode
  private var size: OnyxSize { OnyxSize(tileFamily ?? hostFamily) }
  private var mono: Bool { mode == .accented }

  public init(entry: OnyxTileEntry) { self.entry = entry }

  private var days: [BatteryStackDay] { entry.snapshot?.batteryStack ?? [] }
  private var accent: Color { mono ? .white : OnyxDomain.recover.accent }
  private var today: BatteryStackDay? { days.last(where: { !$0.empty }) }

  /// Each drain in its own domain: the clock is nobody's decision, movement is
  /// the body's, the session and the week's load are training's, and how you
  /// said you felt is recovery's.
  static func ink(_ drain: BatteryDrain, mono: Bool) -> Color {
    if mono { return .white }
    switch drain {
    case .time:     return Color.onyx.textTertiary
    case .activity: return OnyxDomain.body.accent
    case .workout:  return OnyxDomain.train.accent
    case .load:     return OnyxDomain.train.end
    case .wellness: return OnyxDomain.recover.accent
    }
  }

  public var body: some View {
    face.onyxMarked(monochrome: mono, hidden: entry.isStale)
  }

  @ViewBuilder private var face: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption("FATIGUE STACK", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      if let today {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          BigValue(value: today.batteryPct.map { OnyxSeriesFormat.trim($0) },
                   size: size == .small ? 26 : 30,
                   color: mono ? .white : Color.onyx.battery(today.batteryPct.map { Int($0.rounded()) }))
          Text("%").font(OnyxWidgetType.face(12)).foregroundStyle(Color.onyx.textSecondary)
          Spacer(minLength: 0)
          worst(today)
        }
        Spacer(minLength: 0)
        trace
        if size != .small { footnote }
      } else {
        OnyxChartEmpty("Nothing scored in the last fortnight.", compact: true)
      }
    }
  }

  /// The days the line can actually draw — every one that was scored. An
  /// unscored day is absent from the series, not a zero in it.
  private var scored: [BatteryStackDay] { days.filter { !$0.empty && $0.batteryPct != nil } }

  /// The battery line, with the awake hours shaded behind it.
  ///
  /// The shading is per scored day, in the line's own order, so band N sits
  /// under point N — which is why the empties are dropped from BOTH and not
  /// just from the line. Opacity is the day's time drain against the fortnight's
  /// largest, floored at a visible minimum: the bands vary, and a day with the
  /// least of them still happened.
  @ViewBuilder private var trace: some View {
    let points = scored
    if points.count >= 2 {
      // ── THE SHADING IS A SPREAD, NOT AN ABSOLUTE ──────────────────────────
      // Against zero, a fortnight of ordinary days is fourteen bands of nearly
      // identical opacity — a flat grey rectangle behind the line, which reads
      // as a loading state rather than as information (the first shot of this
      // face was exactly that). Normalised against the fortnight's OWN range,
      // the long days are dark and the short ones are not.
      //
      // And when there is no range — every day the same length, or one day
      // scored — there is nothing to shade, so nothing is drawn. A uniform
      // wash that means nothing is worse than no wash.
      let drains = points.map { $0.totalDrain ?? 0 }
      let lo = drains.min() ?? 0, hi = drains.max() ?? 0
      let spread = hi - lo
      ZStack {
        if spread > 0.5 {
          HStack(spacing: 0) {
            ForEach(points) { day in
              Rectangle()
                .fill(Self.ink(.workout, mono: mono)
                  .opacity(0.06 + 0.26 * (((day.totalDrain ?? 0) - lo) / spread)))
                .frame(maxWidth: .infinity)
            }
          }
        }
        Sparkline(points: points.map { $0.batteryPct ?? 0 },
                  color: mono ? .white : accent, zeroBased: true)
      }
      .frame(maxHeight: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Battery over the last fortnight, shaded by how much each day drained")
    } else {
      OnyxChartEmpty("Two scored days draw a line.", compact: true)
    }
  }

  /// What the shading means, and how much of the fortnight the line covers. Both
  /// halves are load-bearing: a gradient nobody explained is decoration, and a
  /// line with four days missing that does not say so is a lie of omission.
  private var footnote: some View {
    let drains = scored.map { $0.totalDrain ?? 0 }
    let shaded = (drains.max() ?? 0) - (drains.min() ?? 0) > 0.5
    return HStack(spacing: 6) {
      // The key appears only when there is shading to key — see `trace`.
      if shaded {
        HStack(spacing: 3) {
          Rectangle()
            .fill(Self.ink(.workout, mono: mono).opacity(0.32))
            .frame(width: 10, height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 1.5))
          Text("day's drain").font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
        }
      }
      Spacer(minLength: 0)
      Text("\(scored.count) of \(days.count) d")
        .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
    }
    .lineLimit(1)
  }

  /// The biggest single drain that is NOT the clock, named.
  ///
  /// ── WHY `.time` IS EXCLUDED ────────────────────────────────────────────
  /// Being awake costs the same every day by construction (see `trace`), so
  /// `time` is the largest drain on almost every day and the chip said "time
  /// −35" for a fortnight — true, constant, and useless. What the chip is for
  /// is the one to do something about, and there is nothing to do about having
  /// been awake.
  @ViewBuilder private func worst(_ day: BatteryStackDay) -> some View {
    let top = BatteryDrain.allCases.filter { $0 != .time }.max { day.drain($0) < day.drain($1) }
    if let top, day.drain(top) > 0 {
      Text("\(top.rawValue) −\(OnyxSeriesFormat.trim(day.drain(top)))")
        .font(OnyxWidgetType.face(10, weight: .semibold))
        .foregroundStyle(Self.ink(top, mono: mono))
        .lineLimit(1)
    }
  }

}

// MARK: - Formatting

/// The three shapes these faces need that `OnyxSnapshot` does not already own.
enum OnyxSeriesFormat {
  /// `+0.22` / `−0.46`. The sign IS the reading, and a minus that is a hyphen
  /// reads as a hyphen at 10 pt.
  static func signed(_ value: Double, decimals: Int) -> String {
    let body = String(format: "%.\(decimals)f", abs(value))
    if value > 0 { return "+\(body)" }
    if value < 0 { return "−\(body)" }
    return body
  }

  /// `13.2` → "13.2", `13.0` → "13". A trailing `.0` on a tile is a digit spent
  /// saying nothing.
  static func trim(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value.rounded())) : String(format: "%.1f", value)
  }

  /// The epoch day number, for projecting a rate across a window. `OnyxChart`
  /// owns the ISO → `Date` conversion the charts plot on; this is the integer
  /// arithmetic underneath it, which is what a slope wants.
  static func day(_ iso: String) -> Int? { ISODate.dayNumber(iso) }
}

#endif
