// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import SwiftUI
import WidgetKit
import OnyxCore

// MARK: - The W6 figures
//
// ── ONE FIGURE PER FACE ──────────────────────────────────────────────────────
// Every tile in the catalogue could already say its number. What most of them
// could not do was be READ at a glance: a caption, a numeral, a rail and four
// supporting figures is six things of the same weight, and a glance resolves
// one. So each face now has exactly one shape that carries the reading, and
// everything else on the tile supports it or is deleted.
//
// The figures live together in one file rather than beside their faces because
// four of the six are drawn by two surfaces each — the Home Screen tile and the
// app's own sheet — and a figure that exists twice drifts the first time either
// copy is nudged. That is the same rule `DepthArc` and `Sparkline` are public
// for, one layer down.
//
// ── AND WHY NONE OF THEM IS A MATERIAL ───────────────────────────────────────
// The hierarchy here is ink, not glass. A widget face is composited by
// WidgetKit against `containerBackground`, which is a flat colour — there is
// nothing behind a tile for `ultraThinMaterial` to sample, so a blurred surface
// on one of these renders as a grey rectangle that looks like a loading state.
// Depth comes from the token ramps and from `Color.onyx.ink(_:)`, which is what
// every face in `Tiles/` already uses.

// MARK: - Charge arc

/// A ring gauge whose fill BEGINS where the night did.
///
/// ── WHY THE START ANGLE IS NOT THE TOP ───────────────────────────────────────
/// Recovery is a charge: it is put on overnight and spent through the day. A
/// gauge that always starts at twelve o'clock draws the same picture for a
/// battery charged from 22:00 and one charged from 03:00, and those are the two
/// nights the reading is actually about. Setting the origin to the bedtime makes
/// the arc a statement with a WHEN in it — the ring reads as the night, in the
/// position on the dial the night occupied.
///
/// The dial is 24 hours, not 12: an 07:00 start and a 19:00 start are opposite
/// halves of the day, and a twelve-hour dial would draw them on top of each
/// other.
///
/// No bedtime is not an error. The arc falls back to the top, which is what
/// every other gauge in the app does, and the face's caption stops claiming a
/// start time it does not have.
struct ChargeArc: View {
  /// 0…1. Nil draws the empty track — the honest picture of an unscored day.
  let fraction: Double?
  /// The bedtime as a local `HH:mm`, from `OnyxSnapshot.clockTime`. The clock
  /// string and not the instant: the conversion to the device's zone is made in
  /// exactly one place, and a second one is how a bedtime reads three hours
  /// wrong on a phone in Jerusalem.
  let startClock: String?
  let tint: Color
  var lineWidth: CGFloat = 12
  var monochrome = false

  /// Where on the dial the fill starts, in turns clockwise from twelve.
  ///
  /// Internal rather than private so a test can state the arithmetic without
  /// rendering anything: 23:41 is 0.987 of the way round, and off-by-one-hour
  /// is invisible in a screenshot.
  static func turn(_ clock: String?) -> Double {
    guard let clock else { return 0 }
    let parts = clock.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
          (0...23).contains(h), (0...59).contains(m) else { return 0 }
    return Double(h * 60 + m) / 1440
  }

  private var ink: Color { monochrome ? .white : tint }

  var body: some View {
    GeometryReader { geo in
      // The stroke is centred ON the path, so half of it sits outside the
      // circle: the drawn ring, not its construction circle, is what gets
      // centred in the space — the same reservation `DepthArc` makes.
      let d = min(geo.size.width, geo.size.height) - lineWidth
      let start = Self.turn(startClock)
      ZStack {
        Circle().stroke(Color.onyx.hairline, lineWidth: lineWidth)
        if let fraction, fraction > 0 {
          Circle()
            .trim(from: 0, to: min(1, max(0, fraction)))
            .stroke(ink, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            // −90° puts zero at twelve; the bedtime turn rotates the whole
            // fill round to where the night began.
            .rotationEffect(.degrees(-90 + start * 360))
            .shadow(color: ink.opacity(monochrome ? 0 : 0.45), radius: 5)
        }
        // A pip at the origin, so the arc's start is legible as a POSITION
        // rather than as wherever the ink happens to begin. Drawn even with no
        // fill: it is the thing the gauge is measured from.
        if startClock != nil {
          Circle()
            .fill(Color.onyx.textTertiary)
            .frame(width: max(2, lineWidth * 0.28), height: max(2, lineWidth * 0.28))
            .offset(y: -d / 2)
            .rotationEffect(.degrees(start * 360))
        }
      }
      .frame(width: d, height: d)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // The app's grid redraws this view as the day is scored; the widget host
      // cross-fades whole entries and ignores it. Either way the sweep grows
      // from where it was rather than snapping.
      .animation(.easeOut(duration: 0.45), value: fraction ?? -1)
    }
  }
}

// MARK: - Pitcher

/// Counting glasses — the arithmetic the water faces share. It outlived the
/// segmented arc it was written for (`GlassArc`, W6), which the pitcher
/// replaced in B2.
enum Glasses {
  /// One glass — `PendingWater.glassMl`, the amount the +250 ml button adds.
  static let glassMl: Double = PendingWater.glassMl
  static let maxSegments = 16

  /// How many glasses the goal is worth, and how many of them are full.
  /// A 3 L goal is twelve glasses; 1 900 ml is seven of them, because three
  /// quarters of a glass is not one.
  static func segments(ml: Double?, goalMl: Double?) -> (total: Int, filled: Int)? {
    guard let goalMl, goalMl > 0 else { return nil }
    let total = min(maxSegments, max(1, Int((goalMl / glassMl).rounded())))
    let filled = min(total, max(0, Int(((ml ?? 0) / glassMl).rounded(.down))))
    return (total, filled)
  }

  /// The day's fill, 0…1. Nil with no goal — a level of nothing.
  static func level(ml: Double?, goalMl: Double?) -> Double? {
    guard let goalMl, goalMl > 0 else { return nil }
    return min(1, max(0, (ml ?? 0) / goalMl))
  }
}

/// The pitcher's body: a rounded trapezoid, wider at the foot, with a spout
/// lifted off its top-left corner. One closed path, so the same shape is the
/// outline AND the clip the water is poured into.
struct PitcherBody: Shape {
  /// Where the rim sits, as a fraction of the height. The level is measured
  /// from the foot to here.
  static let rim: CGFloat = 0.14

  func path(in r: CGRect) -> Path {
    let w = r.width, h = r.height
    let top = r.minY + h * Self.rim, bottom = r.maxY
    let tl = CGPoint(x: r.minX + w * 0.20, y: top)
    let tr = CGPoint(x: r.minX + w * 0.74, y: top)
    let br = CGPoint(x: r.minX + w * 0.80, y: bottom)
    let bl = CGPoint(x: r.minX + w * 0.14, y: bottom)
    let radius = w * 0.08
    return Path { p in
      // The spout: out and up from the rim's left end, then back down into
      // the wall a little below it.
      p.move(to: CGPoint(x: tl.x - w * 0.01, y: tl.y + h * 0.12))
      p.addLine(to: CGPoint(x: r.minX + w * 0.02, y: r.minY))
      p.addQuadCurve(to: CGPoint(x: tl.x + w * 0.10, y: top),
                     control: CGPoint(x: r.minX + w * 0.16, y: top))
      p.addLine(to: tr)
      // The right wall, and a rounded foot at both corners.
      p.addLine(to: CGPoint(x: br.x, y: bottom - radius))
      p.addQuadCurve(to: CGPoint(x: br.x - radius, y: bottom), control: br)
      p.addLine(to: CGPoint(x: bl.x + radius, y: bottom))
      p.addQuadCurve(to: CGPoint(x: bl.x, y: bottom - radius), control: bl)
      p.closeSubpath()
    }
  }
}

/// The handle: an open C on the right wall. Stroked, never filled.
struct PitcherHandle: Shape {
  func path(in r: CGRect) -> Path {
    let w = r.width, h = r.height
    return Path { p in
      p.move(to: CGPoint(x: r.minX + w * 0.755, y: r.minY + h * 0.26))
      p.addCurve(
        to: CGPoint(x: r.minX + w * 0.785, y: r.minY + h * 0.66),
        control1: CGPoint(x: r.minX + w * 1.0, y: r.minY + h * 0.24),
        control2: CGPoint(x: r.minX + w * 1.0, y: r.minY + h * 0.68)
      )
    }
  }
}

/// The day's water as a pitcher filling (decision Q8).
///
/// Water is fixed blue (`OnyxInk.Fixed.water`) in every theme. The level is
/// the day against its goal; the meniscus is a 2 pt lighter band on the
/// surface so a quarter-full pitcher reads as water and not as a shaded foot.
public struct PitcherFigure: View {
  let ml: Double?
  let goalMl: Double?
  var monochrome = false

  public init(ml: Double?, goalMl: Double?, monochrome: Bool = false) {
    self.ml = ml
    self.goalMl = goalMl
    self.monochrome = monochrome
  }

  private var ink: Color { monochrome ? .white : Color.onyx.water }

  public var body: some View {
    GeometryReader { geo in
      // The figure keeps its own proportion (4:5) inside whatever it is given.
      let h = min(geo.size.height, geo.size.width * 1.25)
      let w = h * 0.8
      let level = CGFloat(Glasses.level(ml: ml, goalMl: goalMl) ?? 0)
      let fillTop = h * (PitcherBody.rim + (1 - PitcherBody.rim) * (1 - level))
      ZStack(alignment: .topLeading) {
        PitcherBody().fill(Color.onyx.hairline.opacity(0.35))
        if level > 0 {
          ZStack(alignment: .topLeading) {
            Rectangle().fill(ink.opacity(monochrome ? 0.8 : 1))
              .frame(height: h - fillTop)
              .offset(y: fillTop)
            Rectangle().fill(Color.white.opacity(0.45))
              .frame(height: 2)
              .offset(y: fillTop)
          }
          .frame(width: w, height: h, alignment: .topLeading)
          .clipShape(PitcherBody())
          .animation(.easeOut(duration: 0.35), value: level)
        }
        PitcherBody().stroke(Color.onyx.textSecondary, lineWidth: 1.5)
        PitcherHandle().stroke(Color.onyx.textSecondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
      }
      .frame(width: w, height: h)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .accessibilityHidden(true)
  }
}

// MARK: - Heat strip

/// The sixteen landmark muscles as one ladder of cells, ordered by how much of
/// each one's target the week has actually covered.
///
/// ── WHY SIXTEEN CELLS AND NOT EIGHT BARS ─────────────────────────────────────
/// The eight family bars answer "how is the week going" and answer it well —
/// `MuscleView` draws them. What they cannot do is find the ONE muscle that is
/// behind, because a family is a sum: Delts at 14 of 23 is a family two thirds
/// covered, and it is also side delts at 3 of 9 while the front head is over its
/// target. That reading is exactly the one the payload has carried per landmark
/// since W3 and no face has ever shown.
///
/// Ordered by coverage DESCENDING, so the ladder runs out from left to right and
/// the tail — the end an eye stops at — is the work that is missing.
///
/// ── WHY ONE HUE AND NOT SIXTEEN ──────────────────────────────────────────────
/// The first draft tinted each cell with `Color.onyx.muscle(_:)`, which is the
/// app's own vocabulary for a muscle and is what the atlas figure paints with.
/// At sixteen cells across a 158 pt tile it is a rainbow: every cell a different
/// hue, no two adjacent ones comparable, and the one thing the strip is FOR —
/// which end is short — buried under the colour. The palette earns its keep on
/// the figure, where a hue sits on a body part and is therefore a label. Here
/// there are no labels and no room for any, so the colour carries the READING
/// instead: one domain hue, lit by how much of the target is covered. The
/// muscle that matters is named in words underneath.
/// Which muscle is ahead and which is behind — the rule the heat strip draws.
///
/// ── WHY IT IS NOT ON THE VIEW ───────────────────────────────────────────────
/// It was, as `static func`s on `HeatStrip`, and a test that called them hung
/// the OnyxUITests host until the harness timed it out and restarted — twice,
/// finally reporting three tests that never ran as the failures. A `View`
/// carries main-actor isolation, and reaching into one from a nonisolated test
/// is not something to litigate per call site. This is a sort over payload
/// rows: it is data, it has nothing to do with drawing, and out here it is
/// reachable from a test, from the app's own sheets and from the watch.
enum MuscleLadder {

  /// A cell per landmark that has a target OR any sets, most covered first. A
  /// muscle the plan asks nothing of and the week never touched is not a gap;
  /// it is not in the plan.
  static func rows(_ muscles: [OnyxSnapshot.MuscleVolume]) -> [OnyxSnapshot.MuscleVolume] {
    muscles.filter { $0.target > 0 || $0.sets > 0 }
      .enumerated()
      .sorted { a, b in
        let cover = (coverage(a.element), coverage(b.element))
        if cover.0 != cover.1 { return cover.0 > cover.1 }
        return a.offset < b.offset
      }
      .map(\.element)
  }

  /// Sets over target, uncapped. A muscle that went PAST its target is a
  /// different fact from one that met it, and clamping to 1 would file the two
  /// together at the head of the ladder where the difference is invisible.
  static func coverage(_ row: OnyxSnapshot.MuscleVolume) -> Double {
    row.target > 0 ? row.sets / Double(row.target) : (row.sets > 0 ? 1 : 0)
  }

  /// The muscle the ladder ends on — the one furthest from what the plan asked.
  /// Nil when nothing is behind, which is a week worth saying nothing about.
  static func laggard(_ muscles: [OnyxSnapshot.MuscleVolume]) -> OnyxSnapshot.MuscleVolume? {
    rows(muscles).last.flatMap { coverage($0) < 1 ? $0 : nil }
  }
}

/// ── PUBLIC SINCE W8 ─────────────────────────────────────────────────────────
/// The weekly report's Training section draws the same sixteen cells against
/// the same `plan_phase_volume` targets the Muscle tile does. A second strip in
/// the app target would be a second answer to "how covered was this week", and
/// the first thing to drift would be the pip rule — the one mark on the strip
/// that is not a proportion.
public struct HeatStrip: View {
  let muscles: [OnyxSnapshot.MuscleVolume]
  var monochrome = false
  var height: CGFloat = 26

  public init(muscles: [OnyxSnapshot.MuscleVolume], monochrome: Bool = false, height: CGFloat = 26) {
    self.muscles = muscles
    self.monochrome = monochrome
    self.height = height
  }

  public var rows: [OnyxSnapshot.MuscleVolume] { MuscleLadder.rows(muscles) }
  public var laggard: OnyxSnapshot.MuscleVolume? { MuscleLadder.laggard(muscles) }

  public var body: some View {
    let cells = rows
    if cells.isEmpty {
      OnyxChartEmpty("No plan to measure the week against.", compact: true)
    } else {
      HStack(spacing: 2) {
        ForEach(cells) { row in
          let cover = MuscleLadder.coverage(row)
          // Height AND lightness both carry the coverage. Height alone is hard
          // to read at 16 cells of 6 pt; lightness alone loses the ladder.
          let tint = monochrome
            ? Color.white.opacity(0.35 + 0.65 * min(1, cover))
            : OnyxDomain.train.at(0.15 + 0.85 * min(1, cover))
          VStack(spacing: 0) {
            GeometryReader { geo in
              ZStack(alignment: .bottom) {
                Rectangle().fill(Color.onyx.hairline)
                Rectangle()
                  .fill(tint)
                  // Past target is drawn AT target: the cell is a fill, and a
                  // fill that overflows its own cell is a rendering fault. The
                  // overshoot is carried by the pip below instead.
                  .frame(height: max(1, geo.size.height * CGFloat(min(1, cover))))
              }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            // One pip under a muscle that is over its target — the only mark
            // on the strip that is not a proportion.
            Rectangle()
              .fill(cover > 1 ? (monochrome ? Color.white : Color.onyx.good) : Color.clear)
              .frame(height: 2)
              .padding(.top, 2)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Weekly sets against target, sixteen muscles")
      .accessibilityValue(
        laggard.map { "\($0.muscle) is furthest behind, \(Int($0.sets.rounded())) of \($0.target)" }
          ?? "every muscle at or past its target"
      )
    }
  }
}

#endif
