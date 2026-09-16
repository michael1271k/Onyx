// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import SwiftUI
import OnyxCore

// MARK: - The atlas, drawn
//
// `OnyxAtlas.swift` is GENERATED from the web app's `lib/body/atlas.ts` and holds only
// geometry. This is the view that draws it, and it is hand-written because how
// a body is TINTED is a design decision, not a translation of an SVG.
//
// ── ONE FIGURE, TWO PRODUCTS ─────────────────────────────────────────────────
// The app draws the same paths in SVG. Keeping the geometry generated and the
// styling separate is what lets the widget make its own choices — a 40pt figure
// on a Home Screen cannot use the app's 1.1pt strokes and survive — without the
// two anatomies ever diverging.

struct OnyxAtlasFigure: View {
  /// Which side of the body. `both` draws them side by side, sharing a scale.
  enum Side { case front, back, both }

  var side: Side = .front
  /// Muscle name → 0…1. Names are the atlas's own (`"Side delts"`, `"Abs/core"`).
  var worked: [String: Double] = [:]
  var color: Color = OnyxDomain.body.accent
  var monochrome = false

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
    Canvas { context, size in
      let rect = CGRect(origin: .zero, size: size)

      // The silhouette first, and never tinted: it carries no data, and a
      // glowing head would read as a muscle nobody can train.
      //
      // A vertical gradient stands in for the app's 145-degree one. `Canvas`
      // shading is per-fill, and a linear gradient across a 40pt widget cell
      // costs a gradient evaluation per pixel per body — at this size the top-to-
      // bottom falloff carries the same "this has mass" reading for a fraction
      // of the work, which is the trade the widget has to make everywhere.
      for build in OnyxAtlas.base {
        var path = Path()
        build(rect, &path)
        context.fill(path, with: .linearGradient(
          Gradient(colors: [Color.onyx.ink(0.13), Color.onyx.ink(0.05)]),
          startPoint: CGPoint(x: rect.minX, y: rect.minY),
          endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        context.stroke(path, with: .color(Color.onyx.ink(0.12)), lineWidth: 0.5)
      }

      for entry in OnyxAtlas.muscles where entry.view == view {
        var path = Path()
        entry.build(rect, &path)
        let intensity = min(max(worked[entry.muscle] ?? 0, 0), 1)
        if intensity > 0 {
          // Alpha, not a colour ramp. One hue at several strengths says "more
          // of the same"; a green-to-red ramp would read as a verdict, and this
          // figure passes no verdicts.
          let tint = monochrome ? Color.white : color
          context.fill(path, with: .color(tint.opacity(0.18 + intensity * 0.55)))
          context.stroke(path, with: .color(tint.opacity(0.9)), lineWidth: 0.6)
        } else {
          context.fill(path, with: .color(Color.onyx.ink(0.09)))
          context.stroke(path, with: .color(Color.onyx.ink(0.13)), lineWidth: 0.4)
        }
      }

      // Definition last, over everything, and STROKED ONLY — several of these
      // are open paths, and SwiftUI closes an open path when it fills one, so a
      // filled brow would be a wedge across the forehead.
      for entry in OnyxAtlas.detail where entry.view == view {
        var path = Path()
        entry.build(rect, &path)
        context.stroke(path, with: .color(Color.onyx.ink(0.20)), lineWidth: 0.35)
      }
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
