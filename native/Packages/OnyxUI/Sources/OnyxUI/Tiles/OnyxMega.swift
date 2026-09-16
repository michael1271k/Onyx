// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import SwiftUI
import WidgetKit
import OnyxCore

// MARK: - The Mega Widget (W7, A8)
//
// Three concentric arcs — the night, the movement, the food — a battery in the
// hole, and one sentence underneath.
//
// ── WHY THIS IS NOT A FOURTH `DailyView` ────────────────────────────────────
// `OnyxDaily` answers the same question at a different altitude: four
// quadrants, four figures, four destinations. It is a LEDGER — what the day
// holds. This is a VERDICT — how far through the day's three goals you are,
// as one shape, plus what to do about it. A ledger you read; a verdict you
// glance at. The dashboard has room for both and the Home Screen has the
// ledger already.
//
// This face is a dashboard tile only: it is a twentieth `WidgetId`, not a
// sixth widget KIND. Adding a kind costs a gallery entry, an intent and a
// scope decision (see `OnyxDaily`'s header), and nothing here needs one —
// `WidgetSnapshotBuilder` already resolves every field at `.full`.
//
// ── THE STROKE GEOMETRY IS `WeeklyMuscleRing`'S, AND SO IS THE REASON ───────
// `.butt` caps and a 2° gap out of `MuscleRingArcs`, not a second set of
// numbers. A round cap extends tangentially by half the stroke: at this
// radius that is about 5.7° per end, so trimming 2° with round caps would
// make an arc OVERLAP its own tail by nine degrees rather than leave a notch.
// `OnyxMark` and `WeeklyMuscleRing` both document the same trap on their own
// cuts; this is the third surface to meet it and the first to inherit the
// constant instead of restating it.
//
// The WIDTH is the one number that could not be inherited. `WeeklyMuscleRing`
// strokes 22 pt on a single 170 pt ring; three concentric rings inside a Large
// tile have about 132 pt of diameter to share, so 22 pt each would leave no
// hole for the battery and no daylight between the tracks. 12 pt with a 16 pt
// pitch is what fits, and it is a WIDTH, not a rule — the rules (the cap and
// the gap) are the ones that are shared.

public struct MegaView: View {
  let entry: OnyxTileEntry
  @Environment(\.widgetRenderingMode) private var mode

  public init(entry: OnyxTileEntry) { self.entry = entry }

  private var mono: Bool { mode == .accented }
  private var s: OnyxSnapshot? { entry.snapshot }

  // ── The rings ──────────────────────────────────────────────────────────────
  //
  // ── HOW THE THREE NUMBERS WERE CHOSEN ──────────────────────────────────────
  // A Large tile is 338 × 354 in the grid's own units and about 361 × 378 on a
  // 393 pt phone, less 12 pt of padding each way. The budget is therefore ~337
  // wide and ~354 tall, minus a 14 pt header and a two-line sentence with its
  // hairline (~44). That leaves ~290 for the rings and their legend.
  //
  // WIDTH is the binding constraint, not height: the legend beside the rings
  // has to hold "7,412 / 10k" at a readable size, which measures ~120. So the
  // rings get 176 and the gutter 14, and the remaining 147 is the legend's.
  //
  // The HOLE is what the stroke and the pitch are then solved for. The
  // innermost ring's outer diameter is `outer − 4 × pitch`; its hole is one
  // stroke narrower again, so 176 − 80 − 14 = 82 pt. "BATTERY" at 7 pt with
  // 0.8 tracking measures ~41, and a three-digit percentage at 22 pt measures
  // ~46 — both inside 82 with room for the descender. The first cut of this
  // face used 132 / 16 / 12, which solved to a 56 pt hole, and the shot showed
  // the per-cent sign and the caption both cut off by the inner track.
  /// Outer diameter, and the step inwards to the next ring.
  static let outer: CGFloat = 176
  static let pitch: CGFloat = 20
  static let stroke: CGFloat = 14

  /// One ring: what it measures, how far round it is, and the hue it wears.
  struct Ring: Identifiable {
    let id: String
    let label: String
    let progress: Double?
    let color: Color
    /// 0 outermost.
    let depth: Int
  }

  private var rings: [Ring] {
    [
      Ring(
        id: "sleep", label: "SLEEP",
        progress: OnyxSnapshot.progress(s?.sleep.minutes.map(Double.init), s?.sleep.goalMin.map(Double.init)),
        color: mono ? .white : OnyxDomain.recover.accent, depth: 0
      ),
      Ring(
        id: "move", label: "MOVE",
        progress: OnyxSnapshot.progress(s?.steps.count.map(Double.init), s?.steps.goal.map(Double.init)),
        color: mono ? .white : OnyxDomain.body.accent, depth: 1
      ),
      Ring(
        id: "fuel", label: "FUEL",
        progress: OnyxSnapshot.progress(s?.macros.kcal, s?.macros.kcalGoal),
        color: mono ? .white : OnyxDomain.fuel.accent, depth: 2
      ),
    ]
  }

  public var body: some View {
    Group {
      if entry.isEmpty { Unavailable() } else { face }
    }
    .onyxMarked(monochrome: mono, hidden: entry.isStale)
  }

  private var face: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 5) {
        Caption("TODAY", color: mono ? .white : OnyxDomain.recover.accent)
        ContextChip(context: s?.context, monochrome: mono)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      // The rings take the height the sentence does not. Centred rather than
      // top-aligned: a Large tile is taller than this block needs even at 176,
      // and a shape pinned to the top of 120 pt of nothing reads as a tile that
      // failed to load the rest of itself.
      HStack(alignment: .center, spacing: 14) {
        arcs
        legend
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      // ── THE SENTENCE ──────────────────────────────────────────────────────
      // Drawn only when the payload carries one. A blank line held open for a
      // string that may never arrive is 16 pt of nothing under the shape this
      // tile exists to show; an em dash there would be the tile claiming it
      // had an opinion and declining to say it.
      if let coach = s?.coach {
        Hairline()
        Text(coach)
          .font(OnyxWidgetType.face(11))
          .foregroundStyle(Color.onyx.textSecondary)
          .lineLimit(2)
          .minimumScaleFactor(0.85)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  // MARK: - The arcs

  private var arcs: some View {
    ZStack {
      ForEach(rings) { ring in
        let d = Self.outer - CGFloat(ring.depth) * Self.pitch * 2
        ZStack {
          Circle()
            .trim(from: 0, to: Self.full)
            .stroke(Color.onyx.hairline, style: Self.style)
          if let p = ring.progress {
            Circle()
              .trim(from: 0, to: Self.full * p)
              .stroke(ring.color, style: Self.style)
          }
        }
        // Trim starts at 3 o'clock; a day that reads clockwise from the top is
        // the only arrangement anybody expects — `WeeklyMuscleRing` turns its
        // ring the same quarter for the same reason.
        .rotationEffect(.degrees(-90))
        .frame(width: d - Self.stroke, height: d - Self.stroke)
      }
      battery
    }
    .frame(width: Self.outer, height: Self.outer)
  }

  /// `.butt`, never `.round` — see the header.
  static let style = StrokeStyle(lineWidth: stroke, lineCap: .butt)

  /// How much of the circle a FULL ring covers.
  ///
  /// Not 1.0. The 2° that `MuscleRingArcs.gap` keeps between two arcs is kept
  /// here between an arc and its own tail: with `.butt` caps a ring at 100 %
  /// closes seamlessly and stops looking like a ring with a beginning, so a
  /// day at goal and a track drawn at full opacity become the same picture.
  /// The notch at twelve o'clock is what says "this one went all the way
  /// round".
  static let full = (360 - MuscleRingArcs.gap) / 360

  private var battery: some View {
    VStack(spacing: 0) {
      BigValue(
        value: s?.battery.map { "\($0)%" }, size: 22,
        color: mono ? .white : Color.onyx.battery(s?.battery)
      )
      Text("BATTERY")
        .font(OnyxWidgetType.face(7, weight: .bold)).tracking(0.8)
        .foregroundStyle(Color.onyx.textSecondary)
    }
    // The innermost ring's outer diameter is `outer − 4 × pitch`; its hole is
    // one stroke narrower again. Spelling the frame keeps a three-digit
    // battery from pushing the innermost track outwards.
    .frame(width: Self.outer - 4 * Self.pitch - Self.stroke)
    .accessibilityHidden(true)
  }

  // MARK: - The legend
  //
  // Three rows, one per ring, each the reading and its goal. The arcs say the
  // SHAPE of the day; without this nothing says which arc is which, and a
  // colour key the user has to learn is not a key.

  private var legend: some View {
    VStack(alignment: .leading, spacing: 7) {
      row(rings[0], value: OnyxSnapshot.formatSleep(s?.sleep.minutes),
          goal: s?.sleep.goalMin.map { OnyxSnapshot.formatSleep($0) })
      row(rings[1], value: s?.steps.count.map { $0.formatted(.number.grouping(.automatic)) },
          goal: s?.steps.goal.map { "\($0 / 1000)k" })
      row(rings[2], value: s?.macros.kcal.map { "\(Int($0.rounded()))" },
          goal: s?.macros.kcalGoal.map { "\(Int($0.rounded()))" })
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func row(_ ring: Ring, value: String?, goal: String?) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 4) {
        Circle().fill(ring.color).frame(width: 6, height: 6)
        Text(ring.label)
          .font(OnyxWidgetType.face(8, weight: .heavy)).tracking(1)
          .foregroundStyle(Color.onyx.textSecondary)
      }
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(value ?? "—")
          .font(OnyxWidgetType.figure(15))
          .foregroundStyle(Color.onyx.textPrimary)
          .lineLimit(1).minimumScaleFactor(0.7)
        if let goal {
          Text("/ \(goal)")
            .font(OnyxWidgetType.face(9))
            .foregroundStyle(Color.onyx.textTertiary)
            .lineLimit(1)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(ring.label.capitalized)
    .accessibilityValue(speech(value: value, goal: goal, progress: ring.progress))
  }

  private func speech(value: String?, goal: String?, progress: Double?) -> String {
    guard let value else { return "no reading" }
    var parts = [value]
    if let goal { parts.append("of \(goal)") }
    if let progress { parts.append("\(Int((progress * 100).rounded())) percent of goal") }
    return parts.joined(separator: ", ")
  }
}

#endif
