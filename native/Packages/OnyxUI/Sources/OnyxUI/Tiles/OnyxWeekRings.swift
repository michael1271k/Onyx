// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import SwiftUI
import WidgetKit
import OnyxCore

// MARK: - Week Rings
//
// Twenty-one marks: three rows of seven. Did you train, did you eat to target,
// did you sleep to goal — for each of the last seven days.
//
// ── WHY THIS IS NOT DAY RINGS OVER SEVEN DAYS ───────────────────────────────
// `MegaView` draws today's three goals as three ARCS, because today has a
// fraction: you are 74 % of the way through the step goal and the shape says
// so. A week has seven of those, and seven columns of three part-filled arcs
// inside 130 pt is twenty-one greys. The week's question is a different one —
// how MANY of the seven — and the answer to a counting question is a count of
// marks, not twenty-one small gauges nobody can read.
//
// ── AND WHY THE ROWS ARE DOMAINS AND NOT A LEGEND ───────────────────────────
// Train indigo, Fuel solar, Sleep lunar: the same three ramps the tiles for
// each already wear, so the row you are looking at is named by its colour
// before the label is read. At Small there is no room for the labels and the
// colour is the whole of the key — which is why the three rows are always in
// this order, top to bottom, on every size.
//
// The tile is also the DOOR to the weekly report (the sprint's W8). Nothing
// here knows that; a tap is `TodayTabView`'s business.

public struct WeekRingsView: View {
  let entry: OnyxTileEntry
  @Environment(\.widgetFamily) private var hostFamily
  @Environment(\.onyxTileFamily) private var tileFamily
  @Environment(\.widgetRenderingMode) private var mode
  private var size: OnyxSize { OnyxSize(tileFamily ?? hostFamily) }
  private var mono: Bool { mode == .accented }

  public init(entry: OnyxTileEntry) { self.entry = entry }

  private var days: [OnyxSnapshot.WeekRingDay] { entry.snapshot?.weekRings ?? [] }

  /// The three rows, top to bottom, and the ramp each wears.
  private enum Row: CaseIterable {
    case train, fuel, sleep
    var label: String {
      switch self {
      case .train: "TRAIN"
      case .fuel: "FUEL"
      case .sleep: "SLEEP"
      }
    }
    var domain: OnyxDomain {
      switch self {
      case .train: .train
      case .fuel: .fuel
      case .sleep: .recover
      }
    }
    func hit(_ day: OnyxSnapshot.WeekRingDay) -> Bool {
      switch self {
      case .train: day.trained
      case .fuel: day.fuelHit
      case .sleep: day.sleepHit
      }
    }
  }

  public var body: some View {
    Group {
      if entry.isEmpty { Unavailable() } else { face }
    }
    .onyxMarked(monochrome: mono, hidden: entry.isStale)
  }

  @ViewBuilder private var face: some View {
    VStack(alignment: .leading, spacing: size == .small ? 5 : 7) {
      HStack(spacing: 4) {
        Caption("WEEK", color: mono ? .white : OnyxDomain.train.accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      if days.isEmpty {
        OnyxChartEmpty("No week to draw yet.", compact: true)
        Spacer(minLength: 0)
      } else {
        Spacer(minLength: 0)
        VStack(alignment: .leading, spacing: size == .small ? 5 : 7) {
          ForEach(Row.allCases, id: \.self) { row in marks(row) }
        }
        weekdays
        Spacer(minLength: 0)
      }
    }
  }

  // MARK: - One row

  /// A ring per day: filled when the goal was met, an open track when it was
  /// not. Never a half-filled one — see the header.
  ///
  /// The label is the Medium's, and the tally is on BOTH sizes: "3" beside a
  /// row of marks is the reading a glance actually takes, and it survives the
  /// marks being 10 pt across.
  @ViewBuilder private func marks(_ row: Row) -> some View {
    let tint = mono ? Color.white : row.domain.accent
    let dot: CGFloat = size == .small ? 11 : 13
    HStack(spacing: size == .small ? 4 : 6) {
      if size != .small {
        Text(row.label)
          .onyxWidgetFont { OnyxWidgetType.face(8 * $0, weight: .heavy) }.tracking(1)
          .foregroundStyle(Color.onyx.textSecondary)
          .frame(width: 38, alignment: .leading)
      }
      ForEach(days) { day in
        if row.hit(day) {
          Circle().fill(tint).frame(width: dot, height: dot)
        } else {
          Circle().strokeBorder(tint.opacity(0.28), lineWidth: 1.5)
            .frame(width: dot, height: dot)
        }
      }
      Spacer(minLength: 0)
      Text(size == .small ? "\(count(row))" : "\(count(row))/\(days.count)")
        .onyxWidgetFont { OnyxWidgetType.figure((size == .small ? 10 : 12) * $0) }
        .foregroundStyle(Color.onyx.textPrimary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(row.label.capitalized)
    .accessibilityValue("\(count(row)) of \(days.count) days")
  }

  private func count(_ row: Row) -> Int { days.filter(row.hit).count }

  /// The weekday under each column, read out of the DATE and never assumed —
  /// the window ends today, so its first cell is whatever today happens to be
  /// minus six (`OnyxSnapshot.weekdayInitial`).
  private var weekdays: some View {
    HStack(spacing: size == .small ? 4 : 6) {
      if size != .small { Color.clear.frame(width: 38, height: 1) }
      ForEach(days) { day in
        Text(OnyxSnapshot.weekdayInitial(day.date))
          .onyxWidgetFont { OnyxWidgetType.face(9 * $0, weight: day.date == entry.snapshot?.date ? .heavy : .regular) }
          .foregroundStyle(day.date == entry.snapshot?.date ? Color.onyx.textPrimary : Color.onyx.textTertiary)
          .frame(width: size == .small ? 11 : 13)
      }
      Spacer(minLength: 0)
    }
    .accessibilityHidden(true)
  }
}

#endif
