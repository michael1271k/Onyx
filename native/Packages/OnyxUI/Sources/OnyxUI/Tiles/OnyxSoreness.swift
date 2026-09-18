// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import SwiftUI
import WidgetKit
import OnyxCore

// MARK: - Soreness
//
// Today's DOMS, on the body.
//
// ── THE SAME FIGURE AS MUSCLE FOCUS, AND THAT IS THE POINT ──────────────────
// `MuscleView` paints `OnyxAtlasFigure` with the week's WORK; this paints the
// same figure with the day's SORENESS. One anatomy, two readings, and they can
// be held side by side on the grid because the shapes are identical — "I
// trained this and it hurts" and "I trained this and it does not" are the two
// answers the pair exists to tell apart.
//
// The tint is Lunar, not Tide: soreness is a recovery reading (`OnyxDomain`'s
// own list puts DOMS there) and the Muscle Focus figure wears Body. The rows
// beside the figure are the rating in words — `DomsMuscles.levels`, the
// vocabulary the user tapped, never a re-grading of it into a verdict of ours.
//
// ── AND WHY NOTHING HERE IS RED ─────────────────────────────────────────────
// `OnyxAtlasFigure` fills at one hue and several alphas, deliberately: a
// green-to-red ramp would read as a verdict, and a severe quad the day after a
// leg session is the programme working. Amount, not judgement — the figure's
// own header states the rule and this face inherits it rather than restating
// it in colour.

public struct SorenessView: View {
  let entry: OnyxTileEntry
  @Environment(\.widgetFamily) private var hostFamily
  @Environment(\.onyxTileFamily) private var tileFamily
  @Environment(\.widgetRenderingMode) private var mode
  private var size: OnyxSize { OnyxSize(tileFamily ?? hostFamily) }
  private var mono: Bool { mode == .accented }

  public init(entry: OnyxTileEntry) { self.entry = entry }

  private var regions: [OnyxSnapshot.SorenessRegion]? { entry.snapshot?.soreness }
  private var accent: Color { mono ? .white : OnyxDomain.recover.accent }

  /// Worst first, then alphabetically — a list whose first row is the thing to
  /// think about, and whose order does not change between two refreshes that
  /// rated the same muscles the same.
  private var ranked: [OnyxSnapshot.SorenessRegion] {
    (regions ?? []).sorted { a, b in
      a.level == b.level ? a.landmark < b.landmark : a.level > b.level
    }
  }

  public var body: some View {
    Group {
      if entry.isEmpty { Unavailable() } else { face }
    }
    .onyxMarked(monochrome: mono, hidden: entry.isStale)
  }

  @ViewBuilder private var face: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption("SORENESS", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      switch size {
      case .small: small
      case .medium: medium
      case .large: large
      }
    }
  }

  // ── Small ────────────────────────────────────────────────────────────────
  //
  // The figure and one line. 56 pt is `MuscleView`'s own figure width and the
  // reason is the same: the body is a KEY at this size, not the reading, and a
  // silhouette that fills the tile spends every point on "roughly here".

  private var small: some View {
    VStack(alignment: .leading, spacing: 4) {
      Spacer(minLength: 0)
      HStack(alignment: .center, spacing: 6) {
        figure(width: 56)
        // ── A NIL PAYLOAD COUNTS NOTHING, NOT ZERO ─────────────────────────
        // The first cut interpolated the count unconditionally and a payload
        // that had not asked printed "0 regions" — this file's own rule,
        // broken by a string that cannot tell nil from empty. The second cut
        // drew an em dash, which is right for a READING and wrong for a
        // count: "— regions" is a label with nothing to label. The block is
        // simply absent, and the line underneath says why.
        if regions != nil {
          VStack(alignment: .leading, spacing: 2) {
            BigValue(value: "\(ranked.count)", size: 26, color: Color.onyx.textPrimary)
            Text(ranked.count == 1 ? "region" : "regions")
              .font(OnyxWidgetType.face(9))
              .foregroundStyle(Color.onyx.textSecondary)
          }
        }
      }
      Spacer(minLength: 0)
      headline
    }
  }

  // ── Medium ───────────────────────────────────────────────────────────────

  private var medium: some View {
    HStack(alignment: .center, spacing: 10) {
      figure(width: 84)
      VStack(alignment: .leading, spacing: 4) {
        if ranked.isEmpty {
          headline
        } else {
          ForEach(ranked.prefix(4)) { row($0) }
          if ranked.count > 4 {
            Text("+\(ranked.count - 4) more")
              .font(OnyxWidgetType.face(9))
              .foregroundStyle(Color.onyx.textTertiary)
          }
        }
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }

  // ── Large ────────────────────────────────────────────────────────────────
  //
  // The one size where the figure IS the reading: 150 pt of body is big enough
  // to point at, which is what a sore athlete does with it.

  private var large: some View {
    VStack(alignment: .leading, spacing: 8) {
      figure(width: 150)
        .frame(maxWidth: .infinity)
      Hairline()
      if ranked.isEmpty {
        headline
        Spacer(minLength: 0)
      } else {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(ranked.prefix(7)) { row($0) }
        }
        Spacer(minLength: 0)
      }
    }
  }

  // MARK: - Parts

  /// Front and back, sharing a scale. `soreWorked` is severity over the
  /// vocabulary's own maximum — the identical 0…1 the Pulse figure takes.
  private func figure(width: CGFloat) -> some View {
    OnyxAtlasFigure(
      side: .both,
      worked: entry.snapshot?.soreWorked ?? [:],
      color: accent,
      monochrome: mono
    )
    .frame(width: width)
    .frame(maxHeight: .infinity)
    .accessibilityHidden(true)
  }

  /// The day in a sentence: the worst thing, or that there is nothing.
  @ViewBuilder private var headline: some View {
    if regions == nil {
      Text("Nothing rated today.")
        .font(OnyxWidgetType.face(10))
        .foregroundStyle(Color.onyx.textSecondary)
        .lineLimit(1)
    } else if let worst = ranked.first {
      Text("\(worst.landmark) \(Self.word(worst.level).lowercased())")
        .font(OnyxWidgetType.face(10, weight: .semibold))
        .foregroundStyle(Color.onyx.textSecondary)
        .lineLimit(1).minimumScaleFactor(0.8)
    } else {
      Text("Nothing sore.")
        .font(OnyxWidgetType.face(10, weight: .semibold))
        .foregroundStyle(mono ? .white : Color.onyx.good)
        .lineLimit(1)
    }
  }

  private func row(_ region: OnyxSnapshot.SorenessRegion) -> some View {
    HStack(spacing: 6) {
      // A pip per point of severity, so the rating is legible without reading
      // the word — and the word is there for the reading that needs it.
      HStack(spacing: 2) {
        ForEach(0..<DomsMuscles.maxSeverity, id: \.self) { i in
          Circle()
            .fill(accent.opacity(i < region.level ? 0.95 : 0.18))
            .frame(width: 4, height: 4)
        }
      }
      Text(region.landmark)
        .font(OnyxWidgetType.face(11, weight: .semibold))
        .foregroundStyle(Color.onyx.textPrimary)
        .lineLimit(1).minimumScaleFactor(0.8)
      Spacer(minLength: 0)
      Text(Self.word(region.level))
        .font(OnyxWidgetType.face(9))
        .foregroundStyle(Color.onyx.textTertiary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(region.landmark)
    .accessibilityValue(Self.word(region.level))
  }

  /// "Mild" / "Moderate" / "Severe" — the vocabulary the user tapped, indexed
  /// by the stored severity exactly as `DomsMuscles` states it. Out of range
  /// falls back to the number rather than crashing a widget.
  static func word(_ level: Int) -> String {
    DomsMuscles.levels.indices.contains(level) ? DomsMuscles.levels[level] : "\(level)"
  }
}

#endif
