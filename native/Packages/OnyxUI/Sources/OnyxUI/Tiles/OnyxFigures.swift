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

// MARK: - Glass arc

/// The day's water as `goal ÷ 250 ml` discrete segments around an arc.
///
/// ── WHY SEGMENTS AND NOT A RAIL ──────────────────────────────────────────────
/// Water is the one lifestyle reading that is LOGGED in units. Nobody drinks
/// 63 % of a goal; they drink a glass, and then another one. A continuous rail
/// makes the reader convert their own action into a proportion and back again,
/// and it cannot answer the only question the tile is ever asked, which is how
/// many more.
///
/// The segment count follows the GOAL rather than being a fixed eight, because
/// eight segments against a 2.5 L goal would make each one 312 ml and the
/// button beside it adds 250. Clamped to sixteen: past that the gaps are wider
/// than the segments and the arc reads as a dashed line.
struct GlassArc: View {
  /// Millilitres drunk. Nil draws the empty track.
  let ml: Double?
  /// Millilitres targeted. Nil means no goal, and no goal means no segments to
  /// be a fraction of — the arc then draws one continuous sweep of nothing,
  /// which is the same refusal `Rail` makes.
  let goalMl: Double?
  let tint: Color
  var lineWidth: CGFloat = 12
  var monochrome = false

  /// One glass. The same 250 `PendingWater.glassMl` queues and the Pulse tab's
  /// water row adds — a face that segmented at 200 would show a tap filling
  /// four fifths of a segment.
  static let glassMl: Double = 250
  static let maxSegments = 16

  /// How many segments the goal is worth, and how many of them are full.
  ///
  /// Internal so a test can state it: a 3 L goal is twelve glasses, 1 900 ml is
  /// seven of them full and the eighth part-drunk — which this reports as seven,
  /// because a segment is a glass and three quarters of a glass is not one.
  static func segments(ml: Double?, goalMl: Double?) -> (total: Int, filled: Int)? {
    guard let goalMl, goalMl > 0 else { return nil }
    let total = min(maxSegments, max(1, Int((goalMl / glassMl).rounded())))
    let filled = min(total, max(0, Int(((ml ?? 0) / glassMl).rounded(.down))))
    return (total, filled)
  }

  private var ink: Color { monochrome ? .white : tint }

  var body: some View {
    GeometryReader { geo in
      let d = min(geo.size.width, geo.size.height) - lineWidth
      if let counts = Self.segments(ml: ml, goalMl: goalMl) {
        // A 280° sweep with the gap at the bottom: a full circle has no start
        // and no end, so a viewer cannot tell a full arc from an empty one at
        // a glance. The opening is where the counting begins.
        let sweep = 0.78
        let slice = sweep / Double(counts.total)
        // A tenth of a slice of air between segments — enough to separate
        // twelve of them, small enough that four still read as one gauge.
        let gap = slice * 0.16
        ZStack {
          ForEach(0..<counts.total, id: \.self) { index in
            let from = Double(index) * slice
            Circle()
              .trim(from: from, to: from + slice - gap)
              .stroke(
                index < counts.filled ? ink : Color.onyx.hairline,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
              )
          }
        }
        // The gap is centred at the bottom: rotate so the run starts one half
        // of the missing arc past nine o'clock.
        .rotationEffect(.degrees(90 + (1 - sweep) * 180))
        .frame(width: d, height: d)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.35), value: counts.filled)
      } else {
        Circle()
          .stroke(Color.onyx.hairline, lineWidth: lineWidth)
          .frame(width: d, height: d)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
}

// MARK: - Depth strip

/// The night's four stages as blocks at their own depth.
///
/// ── WHAT THIS IS, AND WHAT IT REFUSES TO BE ──────────────────────────────────
/// It is NOT a hypnogram. A hypnogram plots stage against the CLOCK, and the
/// ordering that implies is not in this data: the builder reads `sleep_sessions`
/// and nothing else, so what exists is four totals — `deepMin`, `coreMin`,
/// `remMin`, `awakeMin` — and no instant belongs to any of them. Drawing those
/// four totals along a time axis would invent a night.
///
/// So the axis is SHARE OF NIGHT and the blocks are laid out by DEPTH, deepest
/// at the floor and awake on the roof, in the ramp's own order — which makes
/// the silhouette a strictly rising staircase. That is what makes the
/// composition readable at 30 pt, and it is also what stops the drawing from
/// claiming anything: no real night rises monotonically, so this cannot be
/// mistaken for a timeline. The widths are proportions and the caption under it
/// says so.
///
/// ponytail: sample-level stages are the stated ceiling. A true hypnogram needs
/// per-sample rows (a `sleep_samples` table HealthKit can fill and this app has
/// never written); the fix is that table, never an assumed ordering here.
struct DepthStrip: View {
  /// `(stage, minutes)` — a stage with no reading is absent, not zero.
  let segments: [(OnyxSleepStage, Int)]
  var monochrome = false
  /// A one-pixel rule at each lane, so an eye can see which depth a block sits
  /// at rather than inferring it from the block's own height.
  var showsLanes = true

  private var total: Int { segments.reduce(0) { $0 + $1.1 } }

  /// The four lanes, TOP first: awake, REM, core, deep. `allCases` runs deep →
  /// awake — the ramp's order and the order lightness runs in — so the lane a
  /// stage sits in is its index counted from the other end.
  private func laneFromTop(_ stage: OnyxSleepStage) -> Int {
    let all = OnyxSleepStage.allCases
    return all.count - 1 - (all.firstIndex(of: stage) ?? 0)
  }

  var body: some View {
    GeometryReader { geo in
      if total > 0 {
        let lanes = OnyxSleepStage.allCases
        let laneHeight = geo.size.height / CGFloat(lanes.count)
        let blockHeight = max(3, laneHeight * 0.7)
        ZStack(alignment: .topLeading) {
          if showsLanes {
            VStack(spacing: 0) {
              ForEach(lanes, id: \.self) { _ in
                ZStack(alignment: .bottom) {
                  Color.clear
                  Rectangle().fill(Color.onyx.hairline.opacity(0.5)).frame(height: 1)
                }
                .frame(height: laneHeight)
              }
            }
          }
          // ── A STAIRCASE, AND DELIBERATELY A MONOTONIC ONE ─────────────────
          // Left to right the blocks run deep → core → REM → awake, which is
          // the ramp's order and produces a strictly rising silhouette. That is
          // the point: no real night rises monotonically, so the shape cannot
          // be misread as a timeline the way a zig-zag would be. What it does
          // carry is the composition — each block's WIDTH is that stage's share
          // — and its depth, which is the lane it sits in.
          HStack(spacing: 2) {
            ForEach(lanes, id: \.self) { stage in
              if let minutes = segments.first(where: { $0.0 == stage })?.1, minutes > 0 {
                VStack(spacing: 0) {
                  Spacer(minLength: 0)
                    .frame(height: CGFloat(laneFromTop(stage)) * laneHeight + (laneHeight - blockHeight) / 2)
                  RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(monochrome ? Color.white.opacity(Self.opacity(stage)) : stage.color)
                    .frame(height: blockHeight)
                  Spacer(minLength: 0)
                }
                .frame(width: max(2, geo.size.width * CGFloat(minutes) / CGFloat(total)))
              }
            }
          }
        }
      } else {
        // A night synced as a duration with no stages at all is a real state.
        // An empty track says so; four zero-width blocks do not.
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(Color.onyx.hairline)
          .frame(maxHeight: .infinity)
      }
    }
  }

  /// In tinted mode the ramp survives as opacity, so depth is still legible —
  /// the same table `DepthBar` uses, for the same reason.
  static func opacity(_ stage: OnyxSleepStage) -> Double {
    switch stage {
    case .deep: return 1.0
    case .core: return 0.75
    case .rem: return 0.5
    case .awake: return 0.3
    }
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

struct HeatStrip: View {
  let muscles: [OnyxSnapshot.MuscleVolume]
  var monochrome = false
  var height: CGFloat = 26

  var rows: [OnyxSnapshot.MuscleVolume] { MuscleLadder.rows(muscles) }
  var laggard: OnyxSnapshot.MuscleVolume? { MuscleLadder.laggard(muscles) }

  var body: some View {
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
