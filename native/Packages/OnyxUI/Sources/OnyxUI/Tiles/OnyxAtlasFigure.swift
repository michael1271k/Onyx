// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import SwiftUI
import WidgetKit
import OnyxCore

// MARK: - The atlas, drawn
//
// `OnyxAtlas.swift` is GENERATED from `scripts/src/atlas.ts` and holds only
// geometry. This view decides WHAT a tile lights — one accent at the worked
// share — and hands the HOW to `AtlasPainter`, the painter the app's
// `AtlasFigure` uses too (Precision F1), so the Home Screen and the phone draw
// one anatomy in one material.
//
// ── THE WIDGET'S CUT OF THE ÉCORCHÉ ──────────────────────────────────────────
// Always LITE: no specular band and no glow — each is a gradient or an
// offscreen pass per muscle, and the extension's memory ceiling is the one
// budget a widget cannot overrun. Flat (the old alpha figure) when the tile
// cannot show colour — `monochrome`, an accented or vibrant rendering mode —
// and in a rectangular Lock Screen accessory (`AtlasMaterial.widget`).

struct OnyxAtlasFigure: View {
  /// Which side of the body. `both` draws them side by side, sharing a scale.
  enum Side { case front, back, both }

  var side: Side = .front
  /// Muscle name → 0…1. Names are the atlas's own (`"Side delts"`, `"Abs/core"`).
  var worked: [String: Double] = [:]
  var color: Color = OnyxDomain.body.accent
  var monochrome = false

  @Environment(\.widgetFamily) private var family
  @Environment(\.widgetRenderingMode) private var renderingMode

  var body: some View {
    switch side {
    case .both:
      HStack(spacing: 2) {
        figure(.front)
        figure(.back)
      }
    case .front: figure(.front)
    case .back: figure(.back)
    }
  }

  private func figure(_ view: OnyxAtlasView) -> some View {
    let painter = AtlasPainter(
      material: .widget(
        monochrome: monochrome,
        fullColor: renderingMode == .fullColor,
        rectangularAccessory: family == .accessoryRectangular),
      isLite: true)
    // Alpha (flat) or the flesh taken toward it (écorché) — one hue at several
    // strengths either way. A green-to-red ramp would read as a verdict, and
    // this figure passes no verdicts.
    let tint = monochrome ? Color.white : color
    return Canvas { context, size in
      painter.paint(&context, in: CGRect(origin: .zero, size: size), view: view, mark: { entry in
        let share = min(max(worked[entry.muscle] ?? 0, 0), 1)
        return share > 0 ? AtlasPainter.Mark(ink: tint, share: share) : nil
      })
    }
    .accessibilityHidden(true)
  }
}

extension OnyxAtlasFigure {
  /// Every muscle at one intensity — a WHOLE-BODY reading, drawn on a body.
  ///
  /// The scale reports composition for the body, not per muscle, and there is
  /// no way to derive one from the other. So a composition figure fills evenly:
  /// it says "this much of you is lean tissue", which is exactly what the
  /// reading means. Tinting individual bellies from a single percentage would
  /// invent a distribution nobody measured.
  static func uniform(_ intensity: Double) -> [String: Double] {
    var out: [String: Double] = [:]
    for entry in OnyxAtlas.muscles { out[entry.muscle] = intensity }
    return out
  }
}

#endif
