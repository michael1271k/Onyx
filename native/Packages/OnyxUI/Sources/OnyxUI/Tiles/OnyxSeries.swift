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
        Caption("CONSISTENCY", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) } else { flame }
      }

      if let model, model.planned > 0 {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          BigValue(value: model.adherencePct.map { OnyxSeriesFormat.trim($0) },
                   size: size == .small ? 26 : 30, color: Color.onyx.textPrimary)
          Text("%").font(OnyxWidgetType.face(12)).foregroundStyle(Color.onyx.textSecondary)
          Spacer(minLength: 0)
          Text("\(model.done) of \(model.planned)")
            .font(OnyxWidgetType.face(11, weight: .semibold))
            .foregroundStyle(Color.onyx.textSecondary)
        }
        Spacer(minLength: 0)
        grid(model)
      } else {
        OnyxChartEmpty("No plan to measure against yet.", compact: true)
      }
    }
  }

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

  /// Eight columns of seven. A column is a week and a row is a weekday, so a
  /// Tuesday that keeps going missing is a horizontal gap rather than a
  /// scattering.
  private func grid(_ model: Consistency) -> some View {
    let dot: CGFloat = size == .small ? 5 : 7
    return HStack(spacing: size == .small ? 3 : 4) {
      ForEach(model.weeks) { week in
        VStack(spacing: size == .small ? 3 : 4) {
          ForEach(week.cells) { cell in
            Self.mark(cell, size: dot, mono: mono)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .accessibilityHidden(true)
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

  @ViewBuilder private var face: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption("DEFICIT LEDGER", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      if let model, model.daysCounted > 0 {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          BigValue(value: model.weeks.last?.balanceKcal.map { OnyxSeriesFormat.signed($0, decimals: 0) },
                   size: size == .small ? 24 : 28, color: Color.onyx.textPrimary)
          Text("kcal").font(OnyxWidgetType.face(11)).foregroundStyle(Color.onyx.textSecondary)
          Spacer(minLength: 0)
          Text("\(model.daysCounted) d counted")
            .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary).lineLimit(1)
        }
        if size != .small { bars(model) }
        reconciliation(model)
      } else {
        OnyxChartEmpty("A day needs intake AND expenditure to count.", compact: true)
      }
    }
  }

  /// One bar per week, hanging off ONE zero line: a deficit below it and a
  /// surplus above, so a week that went the other way is a shape rather than a
  /// minus sign to read.
  ///
  /// The line is drawn once, across the whole plot. Eight bars each drawing
  /// their own one-pixel rule is eight rules that never quite align, which
  /// reads as a broken axis rather than as an axis.
  private func bars(_ model: DeficitLedger) -> some View {
    let peak = max(1, model.weeks.compactMap { $0.balanceKcal.map(abs) }.max() ?? 1)
    return GeometryReader { geo in
      let mid = geo.size.height / 2
      ZStack(alignment: .top) {
        HStack(alignment: .center, spacing: 3) {
          ForEach(model.weeks) { week in
            let value = week.balanceKcal ?? 0
            let height = max(1, CGFloat(abs(value) / peak) * mid)
            VStack(spacing: 0) {
              // The surplus half and the deficit half are separate stacks
              // pinned to the middle, so a bar never crosses the axis.
              VStack { Spacer(minLength: 0); if value > 0 { Capsule().fill(surplusInk).frame(height: height) } }
                .frame(height: mid)
              VStack { if value <= 0 { Capsule().fill(deficitInk).frame(height: height) }; Spacer(minLength: 0) }
                .frame(height: mid)
            }
            .frame(maxWidth: .infinity)
            .opacity(week.balanceKcal == nil ? 0.25 : 1)
          }
        }
        Rectangle()
          .fill(Color.onyx.hairline)
          .frame(height: 1)
          .offset(y: mid)
      }
    }
    .frame(maxHeight: .infinity)
    .accessibilityHidden(true)
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
      if size != .small {
        Stat(value: model.gapKg.map { OnyxSeriesFormat.signed($0, decimals: 2) },
             label: "GAP", color: Color.onyx.textSecondary)
      }
    }
  }
}

// MARK: - Fatigue / stress stack

/// Where the battery went, day by day.
///
/// ── WHY THE SUM DOES NOT ALWAYS CLOSE ───────────────────────────────────────
/// The reading is `clamp(charge − Σdrains, floor, 100)`, so on a heavy day the
/// stack is taller than the gap it explains and the column runs past the charge
/// line. That overflow is the day saying the model ran out of room, and it is
/// drawn rather than scaled away — a stack normalised to always fit would erase
/// the only days worth looking at.
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
        columns
        if size != .small { legend }
      } else {
        OnyxChartEmpty("Nothing scored in the last fortnight.", compact: true)
      }
    }
  }

  /// The biggest single drain, named. A stack says where it all went; this says
  /// which one to do something about.
  @ViewBuilder private func worst(_ day: BatteryStackDay) -> some View {
    let top = BatteryDrain.allCases.max { day.drain($0) < day.drain($1) }
    if let top, day.drain(top) > 0 {
      Text("\(top.rawValue) −\(OnyxSeriesFormat.trim(day.drain(top)))")
        .font(OnyxWidgetType.face(10, weight: .semibold))
        .foregroundStyle(Self.ink(top, mono: mono))
        .lineLimit(1)
    }
  }

  /// One column a day: the drains stacked down from the charge line, and what
  /// was left of the charge underneath them.
  private var columns: some View {
    GeometryReader { geo in
      HStack(alignment: .bottom, spacing: 2) {
        ForEach(days) { day in
          let charge = day.charge ?? 0
          let unit = geo.size.height / 100
          VStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(BatteryDrain.allCases, id: \.self) { drain in
              let h = CGFloat(day.drain(drain)) * unit
              if h > 0.5 {
                Rectangle().fill(Self.ink(drain, mono: mono)).frame(height: h)
              }
            }
            Rectangle()
              .fill(mono ? Color.white.opacity(0.35)
                         : Color.onyx.battery(day.batteryPct.map { Int($0.rounded()) }).opacity(0.85))
              .frame(height: max(0, CGFloat(charge - (day.totalDrain ?? 0)) * unit))
          }
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
          .opacity(day.empty ? 0.15 : 1)
        }
      }
    }
    .frame(maxHeight: .infinity)
    .accessibilityHidden(true)
  }

  private var legend: some View {
    HStack(spacing: 6) {
      ForEach(BatteryDrain.allCases, id: \.self) { drain in
        HStack(spacing: 3) {
          Circle().fill(Self.ink(drain, mono: mono)).frame(width: 5, height: 5)
          Text(drain.rawValue).font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
        }
      }
      Spacer(minLength: 0)
    }
    .lineLimit(1)
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
