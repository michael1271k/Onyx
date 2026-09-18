// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import SwiftUI
import WidgetKit
import OnyxCore

// MARK: - Stress index
//
// One number between 10 and 90, and the fortnight behind it.
//
// ── WHY THE BASELINE IS 50 AND NOT THE SERIES' OWN MEAN ─────────────────────
// `StressConstants.center` is 50: the index is built so that an ordinary day
// for YOU lands there, because every term is a personal z-score. A sparkline
// baselined on its own fortnight would redraw the middle every night and a
// fortnight of high stress would look like an ordinary one — which is the
// reading this tile exists to catch. The dotted line is the scale's own
// centre, so a curve sitting above it is a fortnight above your normal.
//
// ── AND WHY A GAP IS DRAWN AS A JOIN ────────────────────────────────────────
// `StressSeries` returns exactly fourteen days with an unanswered one present
// and EMPTY, and `Sparkline` takes `[Double]` — it has no way to lift the pen.
// The empty days are dropped, so the line joins across them rather than diving
// to the floor, which is the lesser of the two lies available: a day nobody
// answered is not a calm day. The `daysCounted` figure beside the band says
// how many of the fourteen are actually in the line.

public struct StressView: View {
  let entry: OnyxTileEntry
  @Environment(\.widgetFamily) private var hostFamily
  @Environment(\.onyxTileFamily) private var tileFamily
  @Environment(\.widgetRenderingMode) private var mode
  private var size: OnyxSize { OnyxSize(tileFamily ?? hostFamily) }
  private var mono: Bool { mode == .accented }

  public init(entry: OnyxTileEntry) { self.entry = entry }

  private var model: OnyxSnapshot.StressFace? { entry.snapshot?.stress }
  private var accent: Color { mono ? .white : OnyxDomain.recover.accent }
  /// The days that have a reading, oldest first — see the header.
  private var line: [Double] { (model?.series14 ?? []).compactMap(\.index) }

  public var body: some View {
    Group {
      if entry.isEmpty { Unavailable() } else { face }
    }
    .onyxMarked(monochrome: mono, hidden: entry.isStale)
  }

  @ViewBuilder private var face: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption("STRESS", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      if model?.index == nil && line.isEmpty {
        OnyxChartEmpty("Nothing answered yet.", compact: true)
        Spacer(minLength: 0)
      } else {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
          BigValue(
            value: model?.index.map { "\(Int($0.rounded()))" },
            size: size == .small ? 30 : 34,
            color: Color.onyx.textPrimary
          )
          if let band = model?.band, let label = Stress.bandLabel(band) {
            Text(label)
              .font(OnyxWidgetType.face(11, weight: .semibold))
              .foregroundStyle(accent)
              .lineLimit(1).minimumScaleFactor(0.8)
          }
          Spacer(minLength: 0)
          if size != .small, line.count >= 2 {
            Text("\(line.count) of \(model?.series14.count ?? 0) d")
              .font(OnyxWidgetType.face(9))
              .foregroundStyle(Color.onyx.textTertiary)
          }
        }
        // The scale is 10…90 and the fortnight is read against its centre, so
        // the band is the series' own with the 50 inside it — `zeroBased`
        // would pin every reading to the top of a 0…90 plot and flatten the
        // only variation there is.
        Sparkline(points: line, baseline: Stress.constants.center, color: accent)
          .frame(maxHeight: .infinity)
          .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .contain)
  }
}

#endif
