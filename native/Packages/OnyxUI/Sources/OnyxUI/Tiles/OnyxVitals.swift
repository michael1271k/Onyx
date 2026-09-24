// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import WidgetKit
import SwiftUI
import OnyxCore

// MARK: - Vitals
//
// ── WHAT THIS FAMILY IS FOR ──────────────────────────────────────────────────
// Seven overnight readings — HRV, resting heart rate, wrist temperature, blood
// oxygen, respiratory rate, steps and sleep — none of which mean anything as a
// bare number. 42 ms of HRV is neither good nor bad; 42 against your own 51 is
// a sentence. So every face here draws the reading AGAINST ITS BASELINE and
// never on an absolute scale.
//
// ── AND WHY THE BASELINE IS NOT COMPUTED HERE ────────────────────────────────
// `WidgetVitals` ships `baseline` per reading, a fortnight wide and excluding
// today, computed server-side. The alternative — averaging the seven-point
// trend in this file — would be a SECOND definition of "normal", and it would
// disagree with the app's the first time the two windows differed by a day.
// That is the exact split the streak taught this project once already.
//
// ── ACTIVITY BARS, NOT RINGS ─────────────────────────────────────────────────
// The design brief said "Activity Rings / Bars". Rings encode progress toward a
// goal — a closed ring means done. Five of these seven readings HAVE no goal:
// there is no target HRV to close, and a full ring of respiratory rate would be
// meaningless. What they have is a normal and a deviation from it, which is a
// centred bar: the tick in the middle is you, and the fill runs left or right.
// Steps is the exception and keeps a real goal rail, because it genuinely has
// one. Using the same shape for both would have made a goal out of a baseline.

public struct VitalsView: View {
  let entry: OnyxTileEntry
  let focus: VitalsFocus
  @Environment(\.widgetFamily) private var hostFamily
  @Environment(\.onyxTileFamily) private var tileFamily
  /// `widgetFamily` is get-only outside WidgetKit, so the app's grid says which
  /// size it wants through `onyxTileFamily`; on the Home Screen it is unset.
  private var family: WidgetFamily { tileFamily ?? hostFamily }

  public init(entry: OnyxTileEntry, focus: VitalsFocus) {
    self.entry = entry
    self.focus = focus
  }
  @Environment(\.widgetRenderingMode) private var mode

  private var mono: Bool { mode == .accented }

  public var body: some View {
    Group {
      if entry.isEmpty {
        Unavailable(compact: family == .systemSmall)
      } else {
        face
      }
    }
    .onyxMarked(monochrome: mono, hidden: entry.isStale)
    .containerBackground(Color.onyx.base, for: .widget)
    .widgetURL(focus.link(entry.snapshot?.date))
  }

  /// ── WHICH FOCUSES GET THE LEAD RULE, AND WHICH DO NOT (W6) ────────────────
  /// `panel` and `recovery` are the two that never named a reading — they said
  /// "show me the overnight readings" and the dispatcher answered HRV. Those
  /// take the lead rule.
  ///
  /// `respiration` and `temperature` named one. A user who picked Temperature
  /// and got a resting heart rate because the heart moved more would have a
  /// picker that does not pick, which is the exact defect this file's header
  /// says the focus enum was rebuilt to end. They stay pinned, and the chips
  /// beside them are the ranked rest.
  @ViewBuilder private var face: some View {
    let vitals = entry.snapshot?.vitals
    switch (focus, OnyxSize(family)) {
    // The Vitals tile (overhaul B2, decision Q7): a week per reading.
    case (.panel, .small):         VitalSparkFace(entry: entry, mono: mono, count: 2)
    case (.panel, .medium):        VitalSparkFace(entry: entry, mono: mono, count: 3)
    case (.panel, .large):         VitalSparkFace(entry: entry, mono: mono, count: 5)

    case (.recovery, .small):      VitalLeadFace(entry: entry, mono: mono, spec: VitalSpec.lead(vitals))
    case (.recovery, .medium):     VitalsPanelFace(entry: entry, mono: mono, large: false, spec: VitalSpec.lead(vitals))
    case (.recovery, .large):      VitalsPanelFace(entry: entry, mono: mono, large: true, spec: VitalSpec.lead(vitals))

    case (.respiration, .small):   VitalLeadFace(entry: entry, mono: mono, spec: .bloodOxygen)
    case (.respiration, .medium):  VitalsPanelFace(entry: entry, mono: mono, large: false, spec: .bloodOxygen)
    case (.respiration, .large):   VitalsPanelFace(entry: entry, mono: mono, large: true, spec: .bloodOxygen)

    case (.temperature, .small):   VitalLeadFace(entry: entry, mono: mono, spec: .wristTemp)
    case (.temperature, .medium):  VitalsPanelFace(entry: entry, mono: mono, large: false, spec: .wristTemp)
    case (.temperature, .large):   VitalsPanelFace(entry: entry, mono: mono, large: true, spec: .wristTemp)
    }
  }
}

// MARK: - One reading, described

/// Everything that differs between the five readings, in one value.
///
/// The alternative was a switch per face over `VitalsFocus`, repeated for the
/// label, the unit, the colour, the decimals and the direction — five parallel
/// switches that must agree, which is five chances for the SpO₂ face to render
/// a heart-rate colour. This is the shape `DeltaChip.upIsGood` already implies:
/// the verdict belongs to the metric.
public struct VitalSpec: Sendable {
  /// The widget label: short, upper-case, drawn at 8 pt.
  let label: String
  /// The same reading in a sentence, for the app's own rows — where 8 pt
  /// upper-case is not an option (§3.3) and "Resting Hr" is what capitalising
  /// the widget label would produce.
  public let name: String
  public let unit: String
  public let color: Color
  public let decimals: Int
  /// False where DOWN is the good direction — a resting heart rate below your
  /// own normal is a good night, and a respiratory rate above it is not.
  public let upIsGood: Bool
  /// The deviation, in the reading's own units, that fills the bar completely.
  /// Beyond it the bar simply saturates: a bar that keeps growing turns a bad
  /// night into a broken layout.
  let fullScale: Double
  public let read: @Sendable (OnyxSnapshot.Vitals?) -> OnyxSnapshot.Vital?

  public static let hrv = VitalSpec(
    label: "HRV", name: "HRV", unit: "ms", color: OnyxDomain.recover.at(0), decimals: 0,
    upIsGood: true, fullScale: 20, read: { $0?.hrvMs })
  public static let restingBpm = VitalSpec(
    label: "RESTING HR", name: "Resting HR", unit: "bpm", color: OnyxDomain.recover.at(0.25), decimals: 0,
    upIsGood: false, fullScale: 8, read: { $0?.restingBpm })
  public static let wristTemp = VitalSpec(
    // The stored value is ALREADY a deviation from Apple's own baseline, so this
    // bar is a deviation of a deviation — which is the useful one: "you have run
    // warm all fortnight" and "you are warm tonight" are different facts.
    label: "WRIST TEMP", name: "Wrist temp", unit: "°C", color: OnyxDomain.recover.at(0.5), decimals: 2,
    upIsGood: false, fullScale: 0.5, read: { $0?.wristTempDeltaC })
  public static let bloodOxygen = VitalSpec(
    label: "BLOOD O₂", name: "Blood O₂", unit: "%", color: OnyxDomain.recover.at(0.75), decimals: 1,
    upIsGood: true, fullScale: 2, read: { $0?.bloodOxygenPct })
  public static let respiratoryRate = VitalSpec(
    label: "RESPIRATORY", name: "Respiratory", unit: "br/min", color: OnyxDomain.recover.at(1), decimals: 1,
    upIsGood: false, fullScale: 2, read: { $0?.respiratoryRate })

  /// The five overnight readings, in the order every face and the Vitals sheet
  /// lists them. One order, defined once — a sheet that sorted them differently
  /// from the widget would make the same five numbers look like ten.
  public static let all: [VitalSpec] = [hrv, restingBpm, wristTemp, bloodOxygen, respiratoryRate]

  // MARK: - The lead-vital rule (W6)
  //
  // ── WHY HRV STOPPED BEING THE HEADLINE ──────────────────────────────────────
  // Every Vitals face led with HRV because the dispatcher named `.hrv`. On the
  // morning the interesting reading is a resting heart rate eight beats over
  // its own normal, the tile still spent its whole hero on an HRV sitting one
  // millisecond off baseline — the one number that had nothing to say.
  //
  // The lead is the reading FURTHEST FROM ITS OWN NORMAL, in units of that
  // reading's own full scale. That last part is what makes the five
  // comparable: 0.3 °C of wrist temperature and 12 ms of HRV are both "most of
  // the way across the bar", and comparing the raw deltas would put the metric
  // with the biggest numbers on top every single day.
  //
  // Direction is deliberately NOT part of it. The reading worth leading with is
  // the one that moved, and an HRV twelve milliseconds UP is as much a fact
  // about the night as one twelve down; the colour already says which it is.

  /// How far this reading is from its own normal, as a fraction of its full
  /// scale. Nil when there is no reading or no baseline to be far FROM — a
  /// first week has neither, and zero would file it as perfectly ordinary.
  static func deviation(_ spec: VitalSpec, _ vitals: OnyxSnapshot.Vitals?) -> Double? {
    guard let delta = spec.read(vitals)?.delta, spec.fullScale > 0 else { return nil }
    return abs(delta) / spec.fullScale
  }

  /// The five, most deviant first; readings with no deviation to speak of keep
  /// `all`'s order behind them, so a night with nothing to report draws the
  /// list it has always drawn.
  public static func ranked(_ vitals: OnyxSnapshot.Vitals?) -> [VitalSpec] {
    all.enumerated().sorted { a, b in
      let d = (deviation(a.element, vitals) ?? -1, deviation(b.element, vitals) ?? -1)
      if d.0 != d.1 { return d.0 > d.1 }
      return a.offset < b.offset
    }.map(\.element)
  }

  /// The one that leads. HRV when nothing has a baseline yet — a fallback and
  /// not a verdict, and the face's "no baseline yet" line says so.
  public static func lead(_ vitals: OnyxSnapshot.Vitals?) -> VitalSpec {
    ranked(vitals).first ?? hrv
  }
}

/// One supporting reading: its name, its figure, its movement. No bar.
///
/// ── WHY A CHIP AND NOT A ROW ────────────────────────────────────────────────
/// `VitalRow` gives every reading a label, a value, a delta AND a deviation
/// bar, which is right when the face is a panel of equals and wrong the moment
/// one of them leads: five bars of the same weight is what made the panel a
/// texture. The chips are the other four saying what they are without competing
/// with the figure above them.
struct VitalChip: View {
  let spec: VitalSpec
  let vitals: OnyxSnapshot.Vitals?
  let mono: Bool
  /// Drop the delta chip. A Small gives each of three chips about 44 pt, and a
  /// label, a figure AND a ▲ chip in 44 pt is three truncations — the first
  /// shot of this face read "0.…  ▲ …". The lead above already carries the
  /// deviation story; down here the reading itself is what was missing.
  var dense = false

  private var vital: OnyxSnapshot.Vital? { spec.read(vitals) }

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(spec.label)
        .onyxWidgetFont { OnyxWidgetType.face(7 * $0, weight: .bold) }
        .foregroundStyle(mono ? .white : spec.color)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      HStack(spacing: 3) {
        Text(OnyxSnapshot.fixed(vital?.value, decimals: spec.decimals) ?? "—")
          .onyxWidgetFont { OnyxWidgetType.figure((dense ? 11 : 12) * $0) }
          .foregroundStyle(Color.onyx.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        if !dense {
          DeltaChip(delta: vital?.delta, decimals: spec.decimals,
                    upIsGood: spec.upIsGood, monochrome: mono)
        }
      }
      .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The lead's three understudies, side by side.
struct VitalChipRow: View {
  let specs: [VitalSpec]
  let vitals: OnyxSnapshot.Vitals?
  let mono: Bool
  var dense = false

  var body: some View {
    HStack(alignment: .top, spacing: dense ? 5 : 8) {
      ForEach(Array(specs.enumerated()), id: \.offset) { _, spec in
        VitalChip(spec: spec, vitals: vitals, mono: mono, dense: dense)
      }
    }
  }
}

/// A reading against its own normal: a centred tick, and a fill running out
/// from it in the direction the night actually went.
///
/// Green and oxide are assigned by the METRIC's direction, never by the sign —
/// a resting heart rate five beats under your normal is the good case and would
/// read as a loss on a naive up-is-good bar.
struct VitalBar: View {
  let spec: VitalSpec
  let vital: OnyxSnapshot.Vital?
  let mono: Bool

  private var delta: Double? { vital?.delta }

  var body: some View {
    GeometryReader { geo in
      let mid = geo.size.width / 2
      let frac = delta.map { min(1, abs($0) / spec.fullScale) } ?? 0
      let width = mid * CGFloat(frac)
      ZStack(alignment: .leading) {
        Capsule().fill(Color.onyx.hairline)
        if let delta, abs(delta) > 0.0001 {
          let good = spec.upIsGood ? delta > 0 : delta < 0
          Capsule()
            .fill(mono ? Color.white : (good ? Color.onyx.good : Color.onyx.danger))
            .frame(width: max(2, width))
            // Rightward for a raised reading, leftward for a lowered one —
            // the direction is the reading's, not the verdict's, or a good
            // night and a bad one would point the same way.
            .offset(x: delta > 0 ? mid : mid - max(2, width))
        }
        // The baseline tick. Always drawn, including when there is no reading:
        // it is the thing the bar is measured from, and a bar with no origin is
        // a bar with no meaning.
        Rectangle()
          .fill(Color.onyx.ink(0.30))
          .frame(width: 1)
          .offset(x: mid)
      }
    }
    .frame(height: 5)
  }
}

/// Label · value · delta · bar. The row every Vitals face is built from.
struct VitalRow: View {
  let spec: VitalSpec
  let vitals: OnyxSnapshot.Vitals?
  let mono: Bool

  private var vital: OnyxSnapshot.Vital? { spec.read(vitals) }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Text(spec.label)
          .onyxWidgetFont { OnyxWidgetType.face(8 * $0, weight: .bold) }
          .foregroundStyle(mono ? .white : spec.color)
          .lineLimit(1)
        Spacer(minLength: 0)
        Text(OnyxSnapshot.fixed(vital?.value, decimals: spec.decimals) ?? "—")
          .onyxWidgetFont { OnyxWidgetType.face(12 * $0, weight: .bold, design: .monospaced) }
          .foregroundStyle(Color.onyx.textPrimary)
        Text(spec.unit)
          .onyxWidgetFont { OnyxWidgetType.face(8 * $0) }
          .foregroundStyle(Color.onyx.textSecondary)
        DeltaChip(delta: vital?.delta, decimals: spec.decimals,
                  upIsGood: spec.upIsGood, monochrome: mono)
      }
      VitalBar(spec: spec, vital: vital, mono: mono)
    }
  }
}

// MARK: - Faces

/// Small · one reading, its deviation, and the week behind it.
struct VitalLeadFace: View {
  let entry: OnyxTileEntry
  let mono: Bool
  let spec: VitalSpec

  private var s: OnyxSnapshot? { entry.snapshot }
  private var vital: OnyxSnapshot.Vital? { spec.read(s?.vitals) }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption(spec.label, color: mono ? .white : spec.color)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      BigValue(value: OnyxSnapshot.fixed(vital?.value, decimals: spec.decimals), size: 28, color: Color.onyx.textPrimary)

      HStack(spacing: 4) {
        DeltaChip(delta: vital?.delta, decimals: spec.decimals,
                  upIsGood: spec.upIsGood, monochrome: mono)
        Text(baselineLine)
          .onyxWidgetFont { OnyxWidgetType.face(9 * $0) }.foregroundStyle(Color.onyx.textSecondary).lineLimit(1)
      }

      Spacer(minLength: 0)

      VitalBar(spec: spec, vital: vital, mono: mono)

      Hairline()

      // The other three, ranked behind the lead. No bars: five deviation bars
      // of equal weight is the texture the lead rule exists to break up. And
      // no deltas either at this width — see `VitalChip.dense`.
      VitalChipRow(specs: others, vitals: s?.vitals, mono: mono, dense: true)
    }
  }

  /// The next three by deviation, the lead removed. Keyed on the label because
  /// `VitalSpec` is a value type with a closure in it and cannot be Equatable.
  private var others: [VitalSpec] {
    VitalSpec.ranked(s?.vitals).filter { $0.label != spec.label }.prefix(3).map { $0 }
  }

  /// "vs 51 ms usual", or the honest absence. A reading with no normal behind it
  /// is not a deviation of zero.
  private var baselineLine: String {
    guard let b = OnyxSnapshot.fixed(vital?.baseline, decimals: spec.decimals) else {
      return "no baseline yet"
    }
    return "vs \(b) \(spec.unit) usual"
  }
}

/// Medium/Large · the lead reading, then the rest.
///
/// ── WHAT THIS REPLACED, AND WHY BOTH WENT ────────────────────────────────────
/// There were two faces here: `VitalPairFace` (two `VitalRow`s and the day's
/// steps and sleep) and `VitalsPanelFace` (three or five of them). Both drew
/// rows of equal weight, and a row is a label, a figure, a delta and a bar —
/// five of those is twenty things on a 338 pt tile, which is a texture.
///
/// One face now: the lead gets the figure and the bar, three chips carry the
/// readings behind it, and the Large — which owes more than a Medium — keeps
/// the full five-row panel underneath so no reading disappears at any size.
struct VitalsPanelFace: View {
  let entry: OnyxTileEntry
  let mono: Bool
  let large: Bool
  /// Which reading leads. Chosen by `VitalSpec.lead` for the two unnamed
  /// focuses and pinned for the two that named one — see `VitalsView.face`.
  let spec: VitalSpec

  private var s: OnyxSnapshot? { entry.snapshot }
  private var vital: OnyxSnapshot.Vital? { spec.read(s?.vitals) }

  private var others: [VitalSpec] {
    VitalSpec.ranked(s?.vitals).filter { $0.label != spec.label }.prefix(3).map { $0 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: large ? 9 : 7) {
      HStack(spacing: 5) {
        Caption(spec.label, color: mono ? .white : spec.color)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }
      // The corner belongs to the mark; this row's content runs to the edge.
      .padding(.trailing, OnyxMark.faceInset)

      if s?.vitals != nil {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          BigValue(value: OnyxSnapshot.fixed(vital?.value, decimals: spec.decimals),
                   size: large ? 38 : 30, color: Color.onyx.textPrimary)
          Text(spec.unit).onyxWidgetFont { OnyxWidgetType.face(10 * $0) }.foregroundStyle(Color.onyx.textSecondary)
          DeltaChip(delta: vital?.delta, decimals: spec.decimals,
                    upIsGood: spec.upIsGood, monochrome: mono)
          Spacer(minLength: 0)
          Text(baselineLine)
            .onyxWidgetFont { OnyxWidgetType.face(9 * $0) }.foregroundStyle(Color.onyx.textSecondary).lineLimit(1)
        }
        VitalBar(spec: spec, vital: vital, mono: mono)

        // ── THE CHIPS AND THE PANEL ARE ALTERNATIVES, NOT A PAIR ────────
        // A Large that draws both says every reading twice: the three chips
        // are three of the five rows underneath them, with the same figure and
        // the same delta. The Medium has no room for five rows and takes the
        // chips; the Large has room and takes the rows, where each reading
        // also gets its deviation bar.
        if large {
          // ── ONE THING COLLECTS THE SLACK, NOT THREE ────────────────────
          // The rows, the outer `Spacer` and this stack's own centring were
          // all claiming the leftover height, so a Large drew a band of
          // obsidian above the first row AND below the last. The rows sit at
          // the top of a flexible stack and the stack takes everything; the
          // outer Spacer is gone.
          VStack(spacing: 7) {
            ForEach(Array(VitalSpec.all.enumerated()), id: \.offset) { _, row in
              // The lead is drawn above in full; a second appearance of it
              // here would be the same reading twice on one face.
              if row.label != spec.label {
                VitalRow(spec: row, vitals: s?.vitals, mono: mono)
              }
            }
            Spacer(minLength: 0)
          }
          .frame(maxHeight: .infinity)
        } else {
          VitalChipRow(specs: others, vitals: s?.vitals, mono: mono)
          Spacer(minLength: 0)
        }
      } else {
        // A build talking to a deployment without the vitals block, or a night
        // with nothing on the wrist. Both are absence, and absence gets a
        // sentence rather than five rows of em dashes.
        Text("no overnight readings yet")
          .onyxWidgetFont { OnyxWidgetType.face(10 * $0) }.foregroundStyle(Color.onyx.textSecondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      }

      Hairline()
      DayFloorRow(snapshot: s, mono: mono)
    }
  }

  /// "vs 51 ms usual", or the honest absence — the same sentence the Small
  /// prints, for the same reason.
  private var baselineLine: String {
    guard let b = OnyxSnapshot.fixed(vital?.baseline, decimals: spec.decimals) else {
      return "no baseline yet"
    }
    return "vs \(b) \(spec.unit) usual"
  }
}

/// Steps and sleep — the two readings on this panel that DO have goals.
///
/// They keep a goal rail rather than a deviation bar, because "8,412 of 10,000"
/// is a genuinely different claim from "312 above your usual", and drawing them
/// with the same shape as HRV would quietly turn a baseline into a target.
struct DayFloorRow: View {
  let snapshot: OnyxSnapshot?
  let mono: Bool

  var body: some View {
    HStack(spacing: 10) {
      GoalStat(
        label: "STEPS",
        value: snapshot?.steps.count.map { "\($0)" },
        progress: progress(snapshot?.steps.count.map(Double.init),
                           snapshot?.steps.goal.map(Double.init)),
        color: mono ? .white : OnyxDomain.body.accent)
      GoalStat(
        label: "SLEEP",
        value: snapshot?.sleep.minutes.map { OnyxSnapshot.formatSleep($0) },
        progress: progress(snapshot?.sleep.minutes.map(Double.init),
                           snapshot?.sleep.goalMin.map(Double.init)),
        color: mono ? .white : OnyxDomain.recover.accent)
    }
  }

  /// Nil rather than 0 when there is no goal: an empty rail says "none of it
  /// done", and "we do not know what you were aiming for" is a different state.
  private func progress(_ value: Double?, _ goal: Double?) -> Double? {
    guard let value, let goal, goal > 0 else { return nil }
    return min(1, value / goal)
  }
}

/// One goal-bearing figure with its rail.
struct GoalStat: View {
  let label: String
  let value: String?
  let progress: Double?
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Text(label).onyxWidgetFont { OnyxWidgetType.face(7 * $0, weight: .bold) }.foregroundStyle(Color.onyx.textSecondary)
        Spacer(minLength: 0)
        Text(value ?? "—")
          .onyxWidgetFont { OnyxWidgetType.face(11 * $0, weight: .bold, design: .monospaced) }
          .foregroundStyle(Color.onyx.textPrimary)
          .lineLimit(1)
      }
      Rail(progress: progress, color: color, height: 3)
    }
  }
}


// MARK: - Vital sparks (overhaul B2, decision Q7)

/// One seven-day sparkline per reading: the reading's name, the week as a
/// line with today's dot, and tonight's figure in its unit. Small shows the
/// two most deviant readings, Medium three, Large all five — the same
/// `VitalSpec.ranked` order every other Vitals face uses, so the reading that
/// moved is always on screen.
///
/// The week is laid on the CALENDAR (`week(_:endingOn:)`): a night the watch
/// missed is a gap the pen lifts over, never a line joined across it — the
/// stress sparkline's "joins across an unanswered day" caveat is exactly what
/// `Sparkline(gapped:)` exists to stop.
struct VitalSparkFace: View {
  let entry: OnyxTileEntry
  let mono: Bool
  /// How many readings: 2 (Small), 3 (Medium), 5 (Large).
  let count: Int

  private var s: OnyxSnapshot? { entry.snapshot }
  private var specs: [VitalSpec] { Array(VitalSpec.ranked(s?.vitals).prefix(count)) }

  var body: some View {
    VStack(alignment: .leading, spacing: count > 3 ? 6 : 8) {
      HStack(spacing: 4) {
        Caption("VITALS", color: mono ? .white : OnyxDomain.recover.accent)
        Spacer(minLength: 0)
        Text("7 nights")
          .onyxWidgetFont { OnyxWidgetType.face(8 * $0) }
          .foregroundStyle(Color.onyx.textSecondary)
        if entry.isStale { StaleTag(age: entry.age) }
      }
      ForEach(Array(specs.enumerated()), id: \.element.label) { index, spec in
        if index > 0 { Hairline() }
        VitalSparkRow(spec: spec, vitals: s?.vitals, date: s?.date, mono: mono, stacked: count <= 2)
          .frame(maxHeight: .infinity)
      }
    }
  }

  /// A reading's trend laid onto the seven calendar days ending on `endingOn`,
  /// oldest first, nil where no reading landed. Empty without a date.
  nonisolated static func week(_ trend: [OnyxSnapshot.Point]?, endingOn date: String?) -> [Double?] {
    guard let date, let end = ISODate.dayNumber(date) else { return [] }
    let byDay = Dictionary((trend ?? []).map { ($0.d, $0.v) }, uniquingKeysWith: { _, last in last })
    return ((end - 6)...end).map { byDay[ISODate.iso(dayNumber: $0)] }
  }
}

/// One reading's row. `stacked` (the Small) puts the line under the name and
/// figure; wider tiles put it between them.
struct VitalSparkRow: View {
  let spec: VitalSpec
  let vitals: OnyxSnapshot.Vitals?
  let date: String?
  let mono: Bool
  var stacked = false

  private var vital: OnyxSnapshot.Vital? { spec.read(vitals) }
  private var ink: Color { mono ? .white : spec.color }

  var body: some View {
    if stacked {
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          name
          Spacer(minLength: 0)
          figure
        }
        spark
      }
    } else {
      HStack(alignment: .center, spacing: 10) {
        name.frame(width: 64, alignment: .leading)
        spark
        figure.frame(minWidth: 58, alignment: .trailing)
      }
    }
  }

  private var name: some View {
    Text(spec.label)
      .onyxWidgetFont { OnyxWidgetType.face(8 * $0, weight: .bold) }
      .foregroundStyle(ink)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
  }

  private var figure: some View {
    HStack(alignment: .firstTextBaseline, spacing: 2) {
      Text(OnyxSnapshot.fixed(vital?.value, decimals: spec.decimals) ?? "—")
        .onyxWidgetFont { OnyxWidgetType.face(13 * $0, weight: .bold, design: .monospaced) }
        .foregroundStyle(Color.onyx.textPrimary)
      Text(spec.unit)
        .onyxWidgetFont { OnyxWidgetType.face(8 * $0) }
        .foregroundStyle(Color.onyx.textSecondary)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.8)
  }

  private var spark: some View {
    Sparkline(gapped: VitalSparkFace.week(vital?.trend, endingOn: date), baseline: vital?.baseline, color: ink)
      .frame(maxWidth: .infinity, minHeight: 14, maxHeight: .infinity)
  }
}

#endif
