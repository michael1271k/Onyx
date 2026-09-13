// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import SwiftUI
import OnyxCore
import WidgetKit

// MARK: - Primitives
//
// ── THE ONE RULE THESE EXIST TO ENFORCE ──────────────────────────────────────
// Every one of these takes an OPTIONAL and renders an em dash for nil. The
// original versions wrote `entry.snapshot?.week.sessions ?? 0`, which is not a
// blank widget — it is a widget confidently reporting zero sessions, zero
// volume, zero PRs and a 0% battery on a week you trained five times. That is
// the "widgets show empty data" symptom, and it is a bug independent of whether
// the network works: the web app's `lib/widget/snapshot.ts` states the contract in its
// header — a widget showing "—" is correct, one showing an invented number is
// not — and the Swift side was the half that ignored it.
//
// They were all `private`, which is why the whole extension was one 482-line
// file: a second file could not use any of them. They are internal now.

/// The size a tile is asked to draw at when it is NOT on the Home Screen.
///
/// `EnvironmentValues.widgetFamily` has no setter, so the app's Today grid
/// cannot pretend to be a Medium slot the honest way. Every tile reads this
/// first and falls back to `widgetFamily`, which is what WidgetKit sets.
private struct OnyxTileFamilyKey: EnvironmentKey {
  static let defaultValue: WidgetFamily? = nil
}

public extension EnvironmentValues {
  var onyxTileFamily: WidgetFamily? {
    get { self[OnyxTileFamilyKey.self] }
    set { self[OnyxTileFamilyKey.self] = newValue }
  }
}

/// The three Home Screen sizes, collapsed out of `WidgetFamily`.
///
/// ── WHY THIS EXISTS AND WHY IT IS NOT AN OPTIONAL ────────────────────────────
/// Face dispatchers switch on `(focus, size)` and are exhaustive with NO
/// `default:`. `WidgetFamily` carries a dozen cases including every accessory
/// one, so switching on it directly FORCES a `default:` — and a `default:` in a
/// dispatcher is exactly how six focuses came to draw another focus's face
/// without anything failing to compile. Three cases means a missing combination
/// is a build error.
enum OnyxSize {
  case small, medium, large

  init(_ family: WidgetFamily) {
    switch family {
    case .systemSmall:                    self = .small
    case .systemLarge, .systemExtraLarge: self = .large
    default:                              self = .medium
    }
  }
}

struct Dash: View {
  var size: CGFloat = 20
  var body: some View {
    Text("—")
      .font(OnyxWidgetType.face(size, weight: .bold))
      .foregroundStyle(Color.onyx.textSecondary)
  }
}

/// A big number, or an em dash. Never a zero standing in for "unknown".
struct BigValue: View {
  let value: String?
  var size: CGFloat = 30
  var color: Color = .white
  var body: some View {
    if let value {
      Text(value)
        .font(OnyxWidgetType.face(size, weight: .bold, design: .rounded))
        .foregroundStyle(color)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    } else {
      Dash(size: size)
    }
  }
}

/// A progress rail. `nil` draws the empty track only — an unfilled bar reads as
/// "no reading", where a zero-width fill on a coloured track reads as "zero".
struct Rail: View {
  let progress: Double?
  let color: Color
  var height: CGFloat = 4
  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.onyx.hairline)
        if let progress {
          Capsule().fill(color)
            .frame(width: max(0, CGFloat(progress) * geo.size.width))
        }
      }
    }
    .frame(height: height)
  }
}

/// The battery ring. A nil battery draws the track dimmed and an em dash in the
/// middle, rather than a full circle of "0%".
struct BatteryRing: View {
  let pct: Int?
  var size: CGFloat = 74
  var lineWidth: CGFloat = 8
  /// Tinted mode flattens everything to one accent; a coloured ring there reads
  /// as a rendering bug rather than a status.
  var monochrome = false

  private var color: Color { monochrome ? .white : Color.onyx.battery(pct) }

  var body: some View {
    ZStack {
      Circle().stroke(Color.onyx.hairline, lineWidth: lineWidth)
      if let pct {
        Circle().trim(from: 0, to: Double(pct) / 100)
          .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .shadow(color: color.opacity(monochrome ? 0 : 0.5), radius: 4)
      }
      VStack(spacing: 0) {
        BigValue(value: pct.map { "\($0)" }, size: size * 0.27, color: .white)
        Text("BATT")
          .font(OnyxWidgetType.face(size * 0.11, weight: .bold))
          .foregroundStyle(Color.onyx.textSecondary)
      }
    }
    .frame(width: size, height: size)
  }
}

struct Caption: View {
  let text: String
  var color: Color = OnyxDomain.train.accent
  init(_ text: String, color: Color = OnyxDomain.train.accent) {
    self.text = text
    self.color = color
  }
  var body: some View {
    Text(text)
      .font(OnyxWidgetType.face(10, weight: .heavy)).tracking(1.5)
      .foregroundStyle(color)
  }
}

struct Metric: View {
  let value: String?
  let label: String
  var color: Color = .white
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      BigValue(value: value, size: 19, color: color)
      Text(label).font(.caption2).foregroundStyle(Color.onyx.textSecondary)
    }
  }
}

/// How old the numbers on screen are. A number you cannot date is worse than no
/// number.
///
/// ── WHY THIS TOOK AN ARGUMENT ────────────────────────────────────────────────
/// It used to render the fixed string "last known" and appear only when a fetch
/// had FAILED. That covers the case where the phone has no signal and misses the
/// one that actually bites: a payload fetched perfectly at 06:00 and still on
/// screen at 14:00, wearing no tag, looking exactly as confident as a fresh one.
/// `generatedAt` had been in the payload the whole time and nothing read it.
struct StaleTag: View {
  /// Seconds since the payload was generated. Nil when it cannot be dated, which
  /// falls back to the honest, vaguer wording rather than inventing an age.
  var age: TimeInterval?

  var body: some View {
    Text(OnyxSnapshot.shortAge(age).map { "\($0) ago" } ?? "last known")
      .font(OnyxWidgetType.face(8, weight: .semibold))
      .foregroundStyle(Color.onyx.textSecondary)
  }
}

/// The day's declared context — Illness, Travel, Refeed — or nothing at all.
///
/// ── WHY A WIDGET NEEDS THIS AT ALL ───────────────────────────────────────────
/// The widget is the surface you glance at without opening anything, which makes
/// it the one most likely to be believed and the one least able to explain
/// itself. On a declared day the app has already forgiven the grade; a face that
/// shows the low number with no mark on it reports a failure that the rest of
/// the system does not think happened.
///
/// Amethyst, not a warning colour, and for the reason the app uses it
/// everywhere else: a declared day is not a failure.
struct ContextChip: View {
  let context: OnyxSnapshot.DayContext?
  var monochrome = false

  var body: some View {
    if let context {
      Text(context.label.uppercased())
        .font(OnyxWidgetType.face(8, weight: .bold))
        .tracking(0.4)
        .padding(.horizontal, 4)
        .padding(.vertical, 1.5)
        .foregroundStyle(monochrome ? Color.white : OnyxDomain.recover.accent)
        .background(
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill((monochrome ? Color.white : OnyxDomain.recover.accent).opacity(0.16))
        )
    } else {
      EmptyView()
    }
  }
}

/// What to do about it, not just that something is wrong.
///
/// One state now. The old version diagnosed three network failures (no token,
/// token rejected, unreachable); there is no network — the provider reads the
/// App Group database — so the only way to have nothing is that the app has
/// never written it.
struct Unavailable: View {
  var compact = false

  private let symbol = "tray"
  private let title = "Nothing to show yet"
  private let detail = "Open Onyx once and the tiles fill from its database."

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Image(systemName: symbol).font(OnyxWidgetType.face(14)).foregroundStyle(Color.onyx.textSecondary)
      Text(title).font(OnyxWidgetType.face(12, weight: .bold)).foregroundStyle(.white)
      if !compact {
        Text(detail)
          .font(OnyxWidgetType.face(9))
          .foregroundStyle(Color.onyx.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Composite primitives (new in the Lifestyle / Performance faces)

/// A hairline. Used instead of a box wherever two things need separating —
/// ten bordered tiles is ten frames around twelve characters of data.
struct Hairline: View {
  var vertical = false
  var body: some View {
    Rectangle()
      .fill(Color.onyx.hairline)
      .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
  }
}

/// One labelled row of the Ledger's right column: label left, value right,
/// separated by nothing but alignment.
struct LedgerRow: View {
  let label: String
  let value: String?
  var color: Color = .white
  var trailing: String?
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(label)
        .font(OnyxWidgetType.face(10, weight: .semibold)).tracking(0.6)
        .foregroundStyle(Color.onyx.textSecondary)
        .lineLimit(1)
      Spacer(minLength: 4)
      BigValue(value: value, size: 14, color: color)
      if let trailing {
        Text(trailing).font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
      }
    }
  }
}

/// The Sleep Rainbow: one stacked bar of stage TOTALS.
///
/// Honest by construction. `SleepStages.tsx` insists on the same point: these
/// are durations, not a timeline, and drawing them as a hypnogram would claim an
/// ordering within the night that HealthKit's aggregate simply does not carry.
/// Segments are sorted deep → awake because the RAMP orders, not the night.
struct DepthBar: View {
  /// `(stage, minutes)` — a stage with no reading is absent, not zero.
  let segments: [(OnyxSleepStage, Int)]
  var height: CGFloat = 12
  var monochrome = false

  private var total: Int { segments.reduce(0) { $0 + $1.1 } }

  var body: some View {
    GeometryReader { geo in
      if total > 0 {
        HStack(spacing: 1) {
          ForEach(OnyxSleepStage.allCases, id: \.self) { stage in
            if let minutes = segments.first(where: { $0.0 == stage })?.1, minutes > 0 {
              Rectangle()
                .fill(monochrome ? Color.white.opacity(stageOpacity(stage)) : stage.color)
                .frame(width: max(1, geo.size.width * CGFloat(minutes) / CGFloat(total)))
            }
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
      } else {
        // No stage breakdown is a real state — a night synced as a duration with
        // no stages at all. An empty track says so; four zero-width bars do not.
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
          .fill(Color.onyx.hairline)
      }
    }
    .frame(height: height)
  }

  /// In tinted mode the ramp survives as opacity, so depth is still legible.
  private func stageOpacity(_ stage: OnyxSleepStage) -> Double {
    switch stage {
    case .deep: return 1.0
    case .core: return 0.75
    case .rem: return 0.5
    case .awake: return 0.3
    }
  }
}

/// A sparkline with an optional dotted baseline.
///
/// The baseline is what makes "compared to last week" a thing you SEE rather
/// than a number you read and then have to hold in your head against a curve.
public struct Sparkline: View {
  let points: [Double]
  let baseline: Double?
  // No default here: the public init below supplies it, so a default on the
  // property would be unreachable and the two could silently disagree.
  let color: Color
  /// Read against zero. True for quantities that HAVE a meaningful zero —
  /// tonnage, water, calories — and false for bodyweight, where zero-basing an
  /// 78-to-80 kg fortnight flattens the only signal in it.
  let zeroBased: Bool
  /// Nil draws nothing at all rather than a flat line at zero.
  private var usable: [Double]? { points.count >= 2 ? points : nil }

  /// Public because the app's sheets draw the same 40×16 micro-graph beside a
  /// metric row (§3.5) and a second implementation of it would be a second
  /// answer to "what does this fortnight look like".
  public init(points: [Double], baseline: Double? = nil, color: Color = OnyxDomain.train.accent, zeroBased: Bool = false) {
    self.points = points
    self.baseline = baseline
    self.color = color
    self.zeroBased = zeroBased
  }

  /// ── WHY THE BAND IS NEVER EXACTLY min…max ──────────────────────────────────
  /// A band of exactly the series' own range pins the lowest reading to the
  /// floor and the highest to the ceiling on EVERY chart, whatever the real
  /// variation. Eight weeks between 12.1 t and 14.2 t then draws the same cliff
  /// as eight weeks between 2 t and 20 t: the line always starts at the bottom
  /// and ends at the top, and its SHAPE stops carrying information.
  ///
  /// A flat series is the other end of the same problem — a zero span divides by
  /// nothing — so it gets an arbitrary band and sits in the middle of it, which
  /// is the honest picture of "this did not move".
  static func band(lo: Double, hi: Double, zeroBased: Bool) -> (lo: Double, hi: Double) {
    let floor = zeroBased ? Swift.min(0, lo) : lo
    let span = hi - floor
    guard span > 0.0001 else { return (floor - 1, hi + 1) }
    let pad = span * 0.12
    // No pad BELOW a zero base: a bar dipping under its own axis is a bar
    // claiming a negative quantity.
    return (zeroBased ? floor : floor - pad, hi + pad)
  }

  /// The trace, as a curve rather than as a polyline.
  ///
  /// ── WHY CATMULL-ROM AND NOT `addLine` ───────────────────────────────────
  /// A 40 pt sparkline of eight sessions is seven segments in forty points, so
  /// every direction change is a hard corner at 5 pt intervals — which at a
  /// glance reads as jitter in the DATA rather than as the sampling rate of the
  /// series. A Catmull-Rom spline passes through every point (it interpolates,
  /// it does not approximate: the readings stay exactly where they are, which
  /// a Bézier through control points would not guarantee) and rounds only the
  /// joins between them.
  ///
  /// ── AND WHY IT IS SAFE ON A MONOTONIC SERIES ────────────────────────────
  /// The classic objection to a spline on data is overshoot — a curve that
  /// dips below a minimum invents a reading nobody logged. The tension here is
  /// the standard 1/6 and the tangents are clamped to the neighbouring points
  /// rather than extrapolated past the ends, so the curve stays inside the
  /// series' own band; and the band itself is padded 12 % (see `band`), so even
  /// an extreme join cannot leave the drawn area.
  ///
  /// Built once per data change inside the `Path` closure — never per frame.
  static func curve(_ points: [CGPoint]) -> Path {
    Path { p in
      guard let first = points.first else { return }
      p.move(to: first)
      guard points.count > 2 else {
        for point in points.dropFirst() { p.addLine(to: point) }
        return
      }
      for i in 0..<(points.count - 1) {
        // The two points either side of the segment, with the ends repeated —
        // which is what stops the first and last joins from being aimed at a
        // point that does not exist.
        let p0 = points[Swift.max(i - 1, 0)]
        let p1 = points[i]
        let p2 = points[i + 1]
        let p3 = points[Swift.min(i + 2, points.count - 1)]
        let control1 = CGPoint(
          x: p1.x + (p2.x - p0.x) / 6,
          y: p1.y + (p2.y - p0.y) / 6
        )
        let control2 = CGPoint(
          x: p2.x - (p3.x - p1.x) / 6,
          y: p2.y - (p3.y - p1.y) / 6
        )
        p.addCurve(to: p2, control1: control1, control2: control2)
      }
    }
  }

  public var body: some View {
    GeometryReader { geo in
      if let values = usable {
        // The band includes the baseline so the dotted line can never fall
        // outside the drawn area — which is exactly when it matters most.
        let rawLo = min(values.min() ?? 0, baseline ?? .greatestFiniteMagnitude)
        let rawHi = max(values.max() ?? 1, baseline ?? -.greatestFiniteMagnitude)
        let (lo, hi) = Self.band(lo: rawLo, hi: rawHi, zeroBased: zeroBased)
        let span = max(hi - lo, 0.0001)
        let y = { (v: Double) in geo.size.height * (1 - CGFloat((v - lo) / span)) }
        let x = { (i: Int) in geo.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)) }

        ZStack {
          if let baseline {
            Path { p in
              p.move(to: CGPoint(x: 0, y: y(baseline)))
              p.addLine(to: CGPoint(x: geo.size.width, y: y(baseline)))
            }
            .stroke(Color.onyx.textSecondary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
          }
          Self.curve((0..<values.count).map { CGPoint(x: x($0), y: y(values[$0])) })
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
          // The latest reading, marked. A trace without a "you are here" makes
          // the reader find the right-hand end for themselves every glance.
          Circle()
            .fill(color)
            .frame(width: 4, height: 4)
            .position(x: x(values.count - 1), y: y(values[values.count - 1]))
        }
      } else {
        Text("not enough readings")
          .font(OnyxWidgetType.face(9))
          .foregroundStyle(Color.onyx.textSecondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      }
    }
  }
}

/// The Sleep Rainbow as a semicircular gauge.
///
/// ── WHY AN ARC RATHER THAN A SECOND BAR ──────────────────────────────────────
/// `DepthBar` answers "what was the night made of" and answers it well, but it
/// cannot answer "was it enough" — a stacked bar is always full width, so a
/// five-hour night and a nine-hour one draw the identical rectangle. The Small
/// sleep face therefore had nothing to show but text.
///
/// The arc carries BOTH. Its sweep is duration against the goal, so a short night
/// is visibly a short arc; the fill is then sub-divided by stage, so the same
/// shape still says how much of it was deep. One gauge, two questions, and the
/// stage ramp survives intact.
///
/// Over-sleeping caps the sweep at full rather than wrapping. A gauge that laps
/// itself reads as a short night.
public struct DepthArc: View {
  /// `(stage, minutes)` — a stage with no reading is absent, not zero.
  let segments: [(OnyxSleepStage, Int)]
  let minutes: Int?
  let goalMin: Int?
  let lineWidth: CGFloat
  let monochrome: Bool
  /// Draw "goal 8h 0m" under the duration inside the bowl.
  ///
  /// The label is set at `d * 0.075` with a 7 pt floor, which is legible on the
  /// 180–300 pt gauges every other caller draws and is a grey smudge on the
  /// 96 pt one the compacted Pulse tile draws (§U5.1). The GOAL still reaches
  /// `fill` — the arc is still a fraction of it — so turning the label off
  /// changes what is written, never what is drawn.
  let showsGoal: Bool

  /// Public because the Sleep SHEET draws this arc (§5.1) and the widget face
  /// draws it too. One gauge, one implementation: the sheet and the Lock Screen
  /// can never disagree about how long a night was.
  public init(segments: [(OnyxSleepStage, Int)], minutes: Int?, goalMin: Int?, lineWidth: CGFloat = 10, monochrome: Bool = false, showsGoal: Bool = true) {
    self.segments = segments
    self.minutes = minutes
    self.goalMin = goalMin
    self.lineWidth = lineWidth
    self.monochrome = monochrome
    self.showsGoal = showsGoal
  }

  private var staged: Int { segments.reduce(0) { $0 + $1.1 } }
  /// How much of the semicircle is filled. Nil draws the empty track only —
  /// which is the honest picture of a night with no reading at all.
  private var fill: Double? {
    guard let minutes, minutes > 0 else { return nil }
    let goal = Double(goalMin ?? 480)
    guard goal > 0 else { return nil }
    return min(1, Double(minutes) / goal)
  }

  public var body: some View {
    GeometryReader { geo in
      // The drawn circle is a square whose TOP HALF is the arc; the label sits in
      // the bowl beneath it. Height is 0.72 of that square because nothing is
      // ever drawn in the bottom quarter, and reserving it is how a gauge ends up
      // with an inch of nothing under it.
      //
      // ── THE STROKE IS NOT INSIDE THE CIRCLE ─────────────────────────────
      // A `lineWidth` stroke is centred ON the path, so the two ends of the
      // semicircle — which sit exactly on the horizontal diameter, at x = 0 and
      // x = d — put half a line width of ink OUTSIDE the square either side.
      // Sizing the square to the full available width therefore clipped the
      // first stage's cap against the leading edge and pushed the last one into
      // whatever sat to the right of the gauge. Reserving the line width is what
      // makes the drawn gauge, rather than its construction circle, the thing
      // that is centred in the space it was given.
      let d = min(max(0, geo.size.width - lineWidth), geo.size.height / 0.72)
      ZStack {
        Circle()
          .trim(from: 0, to: 0.5)
          .stroke(Color.onyx.hairline, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          .rotationEffect(.degrees(180))

        if let fill {
          // Each stage takes its SHARE OF THE FILL, so the segments always add up
          // to exactly the arc that was drawn — never to more of it than the night
          // actually earned.
          ForEach(Array(arcSpans(fill: fill).enumerated()), id: \.offset) { _, span in
            Circle()
              .trim(from: 0.5 * span.from, to: 0.5 * span.to)
              .stroke(span.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
              .rotationEffect(.degrees(180))
          }
        }

        VStack(spacing: 1) {
          BigValue(value: OnyxSnapshot.formatSleep(minutes) == "—" ? nil
                   : OnyxSnapshot.formatSleep(minutes), size: d * 0.17, color: .white)
          if let goalMin, showsGoal {
            Text("goal \(OnyxSnapshot.formatSleep(goalMin))")
              .font(OnyxWidgetType.face(max(7, d * 0.075)))
              .foregroundStyle(Color.onyx.textSecondary)
          }
        }
        .offset(y: d * 0.12)
      }
      .frame(width: d, height: d)
      // ── THE GAUGE IS CENTRED ON WHAT IT DRAWS, NOT ON ITS CIRCLE ────────
      // The construction square is `d × d` and the ink — the semicircle and
      // the duration in its bowl — occupies the top ~0.72 of it. Pinning that
      // whole square to `.top` therefore put the DRAWN gauge in the top 72 %
      // of the top of the box, so every caller with height to spare drew an
      // arc riding high with a band of nothing under it. That is what made
      // the Sleep tile look like a gauge that had slipped its frame.
      //
      // Cropping to the drawn height first, THEN centring, is what makes the
      // visible gauge the thing that is centred. `.top` on the inner frame is
      // what keeps the crop off the arc: the quarter being cut is the empty
      // one below the bowl, exactly as the `0.72` above already assumes.
      //
      // A caller that sizes its box to 0.72 of the width — the Sleep sheet —
      // is unaffected: `d` is already the whole box there, so the centring
      // has nothing to move.
      .frame(width: d, height: d * 0.72, alignment: .top)
      .frame(width: geo.size.width, height: geo.size.height)
    }
  }

  /// Fractions of the semicircle, one span per reported stage.
  ///
  /// With no stage breakdown at all — a night synced as a duration and nothing
  /// else — the whole fill is drawn in one colour rather than vanishing. The
  /// duration is real even when the composition is not.
  private func arcSpans(fill: Double) -> [(from: Double, to: Double, color: Color)] {
    guard staged > 0 else {
      return [(0, fill, monochrome ? .white : OnyxDomain.recover.accent)]
    }
    var cursor = 0.0
    var out: [(Double, Double, Color)] = []
    for stage in OnyxSleepStage.allCases {
      guard let m = segments.first(where: { $0.0 == stage })?.1, m > 0 else { continue }
      let width = fill * Double(m) / Double(staged)
      out.append((cursor, cursor + width, monochrome ? Color.white.opacity(stageOpacity(stage)) : stage.color))
      cursor += width
    }
    return out
  }

  private func stageOpacity(_ stage: OnyxSleepStage) -> Double {
    switch stage {
    case .deep:  return 1.0
    case .core:  return 0.75
    case .rem:   return 0.5
    case .awake: return 0.3
    }
  }
}

/// Zero-based bars over a short window, with an optional dotted rule.
///
/// ── WHY BARS AND NOT THE SPARKLINE ───────────────────────────────────────────
/// A line implies that the value existed between its points. For a WEEK of
/// tonnage or a DAY of water that is false — each reading is a bucket, and the
/// space between two of them is not a slower Tuesday, it is nothing at all. Bars
/// say "these are the eight quantities" where a line says "this is how it
/// moved", and only one of those is true here.
///
/// Zero-based for the same reason `Sparkline.band` exists: eight weeks between
/// 12.1 t and 14.2 t auto-scaled to their own range draw a cliff. Against zero
/// they draw eight bars of nearly equal height, which is what happened.
struct BarChart: View {
  let points: [OnyxSnapshot.Point]
  /// Drawn as a dotted rule AND included in the scale, so a goal you are miles
  /// short of still appears on the chart.
  var goal: Double?
  var color: Color
  /// The most recent bar is the one you are still able to change.
  var highlightLast = true
  /// A caption under each bar — a weekday initial, a week number. Nil draws none.
  var label: ((OnyxSnapshot.Point) -> String)?

  private var peak: Double {
    max(points.map(\.v).max() ?? 0, goal ?? 0, 0.0001)
  }

  var body: some View {
    if points.isEmpty {
      Text("no readings in this window")
        .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      VStack(spacing: 3) {
        GeometryReader { geo in
          ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: max(2, geo.size.width / CGFloat(points.count) * 0.22)) {
              ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                let isLast = index == points.count - 1
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                  .fill(color.opacity(highlightLast && !isLast ? 0.45 : 1))
                  // A floor of 1pt, so a genuinely tiny day is a hairline rather
                  // than an absence — absence is what an omitted point means.
                  .frame(height: max(1, geo.size.height * CGFloat(point.v / peak)))
                  .frame(maxWidth: .infinity)
              }
            }
            if let goal, goal > 0 {
              Path { p in
                let y = geo.size.height * (1 - CGFloat(goal / peak))
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: geo.size.width, y: y))
              }
              .stroke(Color.onyx.textSecondary.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
          }
        }
        if let label {
          HStack(spacing: max(2, 4)) {
            ForEach(points) { point in
              Text(label(point))
                .font(OnyxWidgetType.face(7, weight: .bold))
                .foregroundStyle(Color.onyx.textSecondary)
                .frame(maxWidth: .infinity)
            }
          }
        }
      }
    }
  }
}

/// A ▲/▼ chip against a comparison. Neutral — not green — when nothing moved.
struct DeltaChip: View {
  let delta: Double?
  var decimals: Int = 1
  var suffix: String = ""
  /// Set false where DOWN is the good direction (bodyweight on a cut). The
  /// verdict belongs to the metric, never to the sign.
  var upIsGood = true
  var monochrome = false

  var body: some View {
    if let delta, let text = OnyxSnapshot.signed(delta, decimals: decimals) {
      let moved = abs(delta) > 0.0001
      let good = upIsGood ? delta > 0 : delta < 0
      let color: Color = monochrome ? .white : (!moved ? Color.onyx.textSecondary : good ? Color.onyx.good : Color.onyx.danger)
      HStack(spacing: 2) {
        if moved {
          Image(systemName: delta > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(OnyxWidgetType.face(7))
        }
        Text(text + suffix).font(OnyxWidgetType.face(10, weight: .bold)).monospacedDigit()
      }
      .foregroundStyle(color)
    } else {
      // No comparison is not "no change". Saying so costs four characters.
      Text("new").font(OnyxWidgetType.face(9, weight: .semibold)).foregroundStyle(Color.onyx.textSecondary)
    }
  }
}

/// A titled band with a leading accent rule — the Large faces' register
/// separator. A rule instead of a card: three bordered boxes on a Large widget
/// is three frames competing with the numbers inside them.
struct Register<Content: View>: View {
  let title: String
  var accent: Color = OnyxDomain.train.accent
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Caption(title, color: accent)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A vertical, four-segment day column for the week strip. Segments are stacked
/// bottom-up so the column reads as a filling glass.
struct DayColumn: View {
  /// `(fraction 0…1, colour)`, bottom first. An absent reading is simply absent.
  let segments: [(Double, Color)]
  var highlighted = false

  var body: some View {
    GeometryReader { geo in
      VStack(spacing: 1) {
        Spacer(minLength: 0)
        ForEach(Array(segments.enumerated().reversed()), id: \.offset) { _, seg in
          RoundedRectangle(cornerRadius: 1.5)
            .fill(seg.1.opacity(highlighted ? 1 : 0.45))
            .frame(height: max(2, geo.size.height * CGFloat(min(1, max(0, seg.0))) / CGFloat(max(segments.count, 1))))
        }
      }
    }
  }
}

// MARK: - Type
//
// ── THE WIDGET SCALE IS NOT THE APP SCALE ────────────────────────────────────
// `OnyxType` (in `DesignSystem/`) is six named roles on Apple's own text
// styles, and its floor is 11pt because nothing in an app should be smaller
// than that under any text setting. None of that applies here.
//
// A widget face is not an app screen. WidgetKit does not deliver Dynamic Type
// to it, a Lock Screen accessory family is 40pt tall in total, and a systemSmall
// has to fit a label, a figure and a unit inside 150pt. So these faces are typed
// in POINTS, deliberately, and they go down to 7 — which is exactly why they get
// their own scale with its own name instead of quietly widening the app's.
//
// ── ONE SCALE, THREE JOBS ────────────────────────────────────────────────────
// The rule was already half-observed and never written down: a headline value is
// `.rounded` and a changing figure is `.monospaced`, because a figure that
// changes between refreshes must not reflow its row when a 1 becomes a 7.
// Everywhere else the faces reached for `.system(size:weight:)` directly and got
// whichever they happened to type.
//
// Naming it means the next face gets it right by default rather than by memory,
// and it gives the token-discipline test one thing to grep for: a bare
// `.font(.system(size:` under `Tiles/` is now a failure.

// ── AND WHY IT IS `public` ───────────────────────────────────────────────────
// The Live Activity is a widget surface that does not live in `Tiles/` — it is
// declared in the extension, beside the `ActivityConfiguration` that draws it.
// Leaving the scale internal is what let that one surface type itself in raw
// `.system(size:)` for a year while every tile beside it used the scale, so the
// Lock Screen card drifted a half-point at a time from the faces it sits next
// to. One door means one door from outside the package too.
public enum OnyxWidgetType {
  /// A headline value. Rounded, because it is the one thing being read.
  public static func hero(_ size: CGFloat) -> Font {
    .system(size: size, weight: .bold, design: .rounded)
  }

  /// Anything that CHANGES between refreshes — counts, tonnages, times. Monospaced
  /// digits keep the column still while the number moves.
  public static func figure(_ size: CGFloat) -> Font {
    .system(size: size, weight: .bold, design: .monospaced)
  }

  /// A name, a label, a session title. Prose, not data.
  public static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight)
  }

  /// The small-caps register caption. Paired with `.tracking(1.5)` in `Caption`.
  public static let caption = Font.system(size: 10, weight: .heavy)

  /// A face's own size, weight and design, spelled out.
  ///
  /// The escape hatch, and the one the faces mostly use: thirty-odd distinct
  /// size/weight pairs across sixty faces are not a scale, they are a layout
  /// each. What this buys is not fewer numbers — it is that the numbers are all
  /// spelled the same way, so `Tiles/` can be swept for a font decision in one
  /// grep and the app's own scale can ban `.system(size:` outright.
  public static func face(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
    .system(size: size, weight: weight, design: design)
  }
}

#endif
