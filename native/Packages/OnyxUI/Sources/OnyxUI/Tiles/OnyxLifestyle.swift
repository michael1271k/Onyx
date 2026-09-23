// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import WidgetKit
import SwiftUI
import OnyxCore

// MARK: - Fuel and Body
//
// Two of the four families. The layout LANGUAGE changes with the size, and the
// focus changes what leads — not merely which number is bold.
//
//   Small   C6 Focus       one idea, said once
//   Medium  C1 Ledger      a hero plus four supporting facts, no boxes
//           C7 Macros      the calorie bar with its three parts underneath
//           C2 Depth Bars  for sleep — a stacked bar is the shape of a night,
//                          and a row of numbers is not
//           C3 Trendline   for weight — a fortnight against last week's mean,
//                          so the comparison is seen rather than read
//   Large   C5 Split       today in the context of the week
//           C8 Wellbeing   the score, its five parts, and today's verdict
//
// ── WHAT WAS DELETED FROM THIS FILE, AND WHY ─────────────────────────────────
// There used to be a second enum here — `FaceFocus { calories, steps, sleep,
// weight }` — invented so Fuel and Body could share one set of faces without a
// face knowing which widget it was inside. It had FOUR cases against the pickers'
// SIX, and every dispatcher bridged the gap with a ternary:
//
//     FocusFace(focus: focus == .water ? .steps : .calories)   // Water → Steps
//     FocusFace(focus: focus == .sleep ? .sleep : .weight)     // Well-being → Weight
//
// So picking "Water" drew steps and picking "Well-being" drew the scale, and
// nothing failed to compile because the ternary always had an answer. The shared
// faces survive; the enum does not. They now take a `FocusSpec` — plain data —
// so there is no second list of cases that can fall behind the first, and every
// dispatcher below switches on `(focus, OnyxSize)` with NO `default:`. A focus
// added to a picker without a face is now a build error.

// MARK: - Focus specification
//
// What a Small face draws, as data rather than as an enum case. One builder per
// metric: adding a metric means adding a function, and the exhaustive switch in
// the dispatcher is what forces you to.
//
// ── AND ONE BUILDER PER METRIC THAT STILL HAS A FACE (W6) ────────────────────
// It is down to two. `water`, `sleep`, `weight` and `wellbeing` all grew faces
// of their own — the glass arc, the depth strip, the trendline, the charge arc
// — and their builders sat here unreferenced. An unreferenced case beside a
// live one is exactly what this type replaced an enum to avoid: the header
// below records a release in which picking "Water" drew steps, and it drew
// steps through a spec nobody had noticed was orphaned.

struct FocusSpec {
  let caption: String
  let hero: String?
  var sub: String?
  var progress: Double?
  let accent: Color

  static func calories(_ s: OnyxSnapshot?) -> FocusSpec {
    FocusSpec(
      caption: "KCAL LEFT",
      hero: s?.caloriesRemaining.map { "\($0)" },
      // What is LEFT of the protein, not what has been eaten of it (W6). The
      // whole tile is framed on the remainder — "128 g protein" beside a
      // headline of 715 kcal left is two different questions on one face, and
      // only one of them is the one you act on.
      sub: MacroRemainder.text(s?.macros.proteinG, s?.macros.proteinGoalG).map { "protein \($0)" },
      progress: OnyxSnapshot.progress(s?.macros.kcal, s?.macros.kcalGoal),
      accent: OnyxDomain.fuel.accent)
  }

  static func steps(_ s: OnyxSnapshot?) -> FocusSpec {
    FocusSpec(
      caption: "STEPS",
      hero: s?.steps.count.map { "\($0)" },
      sub: s?.steps.distanceM.map { String(format: "%.1f km", $0 / 1000) },
      progress: OnyxSnapshot.progress(
        s?.steps.count.map(Double.init), s?.steps.goal.map(Double.init)),
      accent: OnyxDomain.body.accent)
  }
}

// MARK: - Onyx Fuel

public struct FuelView: View {
  let entry: OnyxTileEntry
  let focus: FuelFocus
  @Environment(\.widgetFamily) private var hostFamily
  @Environment(\.onyxTileFamily) private var tileFamily
  /// `widgetFamily` is get-only outside WidgetKit, so the app's grid says which
  /// size it wants through `onyxTileFamily`; on the Home Screen it is unset.
  private var family: WidgetFamily { tileFamily ?? hostFamily }

  public init(entry: OnyxTileEntry, focus: FuelFocus) {
    self.entry = entry
    self.focus = focus
  }
  @Environment(\.widgetRenderingMode) private var mode

  private var mono: Bool { mode == .accented }
  private var s: OnyxSnapshot? { entry.snapshot }

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
    // ── EXACTLY ONE widgetURL, AT THE ROOT ────────────────────────────────────
    // `widgetURL` is a per-widget property, not a per-view one: declaring it on
    // an inner stack as well makes the effective target ambiguous, and on a
    // Small — where `Link` is inert and the whole face is one tap target — the
    // inner one silently wins nothing at all. Sub-regions of the Medium and
    // Large faces use `Link`, which IS per-view, and everything they do not
    // cover falls through to this.
    .widgetURL(focus.link(entry.snapshot?.date))
  }

  /// Nine combinations, nine cases, no `default:`. This is the ratchet.
  @ViewBuilder private var face: some View {
    switch (focus, OnyxSize(family)) {
    case (.calories, .small):  FocusFace(spec: .calories(s), stale: entry.isStale, age: entry.age, mono: mono)
    case (.calories, .medium): CalorieLedgerFace(entry: entry, mono: mono)
    case (.calories, .large):  CalorieDayFace(entry: entry, mono: mono)

    case (.macros, .small):    MacroFocusFace(entry: entry, mono: mono)
    case (.macros, .medium):   MacroFace(entry: entry, mono: mono)
    case (.macros, .large):    MacroLargeFace(entry: entry, mono: mono)

    case (.water, .small):     WaterGlassFace(entry: entry, mono: mono)
    case (.water, .medium):    WaterLedgerFace(entry: entry, mono: mono)
    case (.water, .large):     WaterLargeFace(entry: entry, mono: mono)
    }
  }

}

/// Sleep, as a duration, or nil. Shared because five faces need the same two
/// lines of guarding and `formatSleep` returns an em dash rather than nil.
func sleepDuration(_ s: OnyxSnapshot?) -> String? {
  guard let m = s?.sleep.minutes, m > 0 else { return nil }
  return OnyxSnapshot.formatSleep(m)
}

/// What today's session is, in the fewest words that still identify it.
func nextSessionText(_ s: OnyxSnapshot?) -> String? {
  guard let label = s?.workout.label, !label.isEmpty else { return nil }
  if s?.workout.isRestDay == true { return "Rest" }
  return s?.today != nil ? "\(label) ✓" : label
}

// MARK: - Onyx Body

public struct BodyView: View {
  let entry: OnyxTileEntry
  let focus: BodyFocus
  @Environment(\.widgetFamily) private var hostFamily
  @Environment(\.onyxTileFamily) private var tileFamily
  /// `widgetFamily` is get-only outside WidgetKit, so the app's grid says which
  /// size it wants through `onyxTileFamily`; on the Home Screen it is unset.
  private var family: WidgetFamily { tileFamily ?? hostFamily }

  public init(entry: OnyxTileEntry, focus: BodyFocus) {
    self.entry = entry
    self.focus = focus
  }
  @Environment(\.widgetRenderingMode) private var mode

  private var mono: Bool { mode == .accented }
  private var s: OnyxSnapshot? { entry.snapshot }

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

  @ViewBuilder private var face: some View {
    switch (focus, OnyxSize(family)) {
    case (.weight, .small):     WeightFocusFace(entry: entry, mono: mono)
    case (.weight, .medium):    WeightTrendFace(entry: entry, mono: mono)
    case (.weight, .large):     WeightLargeFace(entry: entry, mono: mono)

    case (.sleep, .small):      SleepArcFace(entry: entry, mono: mono)
    case (.sleep, .medium):     SleepDepthFace(entry: entry, mono: mono)
    case (.sleep, .large):      SleepLargeFace(entry: entry, mono: mono)

    // Was `focus == .sleep ? .sleep : .weight` — which is why asking for the
    // daily score got you the bathroom scale.
    case (.wellbeing, .small):  RecoveryChargeFace(entry: entry, mono: mono)
    case (.wellbeing, .medium): WellbeingLedgerFace(entry: entry, mono: mono)
    case (.wellbeing, .large):  WellbeingFace(entry: entry, mono: mono)

    case (.composition, .small):  CompositionFocusFace(entry: entry, mono: mono)
    case (.composition, .medium): CompositionFace(entry: entry, mono: mono, large: false)
    case (.composition, .large):  CompositionFace(entry: entry, mono: mono, large: true)
    }
  }
}

// MARK: - C6 · Focus (Small)
//
// A Small holds exactly one idea: caption, one big number, one supporting line,
// one rail. This is the shape the original static Fuel and Battery tiles had —
// the only thing they got right, and the reason it survived them.

struct FocusFace: View {
  let spec: FocusSpec
  var stale = false
  /// The payload's age, so the tag can say it. Passed alongside `stale` rather
  /// than replacing it: this face is handed a boolean by callers that have
  /// already decided, and an age of nil is "undatable", not "fresh".
  var age: TimeInterval?
  let mono: Bool

  private var accent: Color { mono ? .white : spec.accent }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption(spec.caption, color: accent)
        Spacer(minLength: 0)
        if stale { StaleTag(age: age) }
      }
      BigValue(value: spec.hero, size: 30, color: Color.onyx.textPrimary)
      if let sub = spec.sub {
        Text(sub).font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary).lineLimit(1)
      }
      Spacer(minLength: 0)
      Rail(progress: spec.progress, color: accent)
    }
  }
}

// MARK: - C1 · Ledger (Medium)
//
// Left: one hero with a rail beneath it. Right, hairline-separated: the four
// facts it is read alongside. One focal point, four supporting facts, zero boxes
// — which is the whole reason the previous Medium faces looked like wide Smalls.
//
// Two concrete faces rather than one parameterised one. The generic version took
// a hero spec and a list of rows, which made it possible — and it happened — for
// the Water face to be handed a STEPS hero and a nutrition ledger. What each
// half contains is a design decision about that focus, not a parameter.

/// Calories Medium · exactly the ask: calories with their macros directly
/// underneath on the left, and the rest of the day on the right.
struct CalorieLedgerFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private func tint(_ c: Color) -> Color { mono ? .white : c }

  var body: some View {
    HStack(spacing: 12) {
      Link(destination: OnyxLink.nutrition ?? OnyxLink.home!) { heroColumn }
      Hairline(vertical: true)
      Link(destination: OnyxLink.home ?? OnyxLink.nutrition!) { ledgerColumn }
    }
  }

  private var heroColumn: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Caption("KCAL LEFT", color: tint(OnyxDomain.fuel.accent))
        if entry.isStale { StaleTag(age: entry.age) }
      }
      BigValue(value: s?.caloriesRemaining.map { "\($0)" }, size: 30, color: Color.onyx.textPrimary)
      Rail(progress: OnyxSnapshot.progress(s?.macros.kcal, s?.macros.kcalGoal),
           color: tint(OnyxDomain.fuel.accent), height: 5)

      Spacer(minLength: 2)

      // The macros sit UNDER the calories they add up to, which is the mapping
      // principle: they are a decomposition of the bar above them, not four
      // unrelated meters that happen to share a column.
      MacroRail(label: "P", value: s?.macros.proteinG, goal: s?.macros.proteinGoalG,
                color: tint(Color.onyx.protein))
      MacroRail(label: "C", value: s?.macros.carbsG, goal: s?.macros.carbsGoalG,
                color: tint(Color.onyx.carbs))
      MacroRail(label: "F", value: s?.macros.fatG, goal: s?.macros.fatGoalG,
                color: tint(Color.onyx.fat))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var ledgerColumn: some View {
    VStack(spacing: 0) {
      LedgerRow(label: "SLEEP", value: sleepDuration(s), color: tint(OnyxDomain.recover.accent))
      Hairline().padding(.vertical, 4)
      LedgerRow(label: "WATER", value: s?.water.ml.map { String(format: "%.1f", $0 / 1000) },
                color: tint(Color.onyx.water), trailing: "L")
      Hairline().padding(.vertical, 4)
      LedgerRow(label: "BATTERY", value: s?.battery.map { "\($0)" },
                color: mono ? .white : Color.onyx.battery(s?.battery), trailing: "%")
      Hairline().padding(.vertical, 4)
      // The day's session, in the day's own colour. Four rows of numbers and
      // then the one thing that is not a number.
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("TODAY")
          .font(OnyxWidgetType.face(10, weight: .semibold)).tracking(0.6)
          .foregroundStyle(Color.onyx.textSecondary)
        Spacer(minLength: 4)
        Text(nextSessionText(s) ?? "—")
          .font(OnyxWidgetType.face(12, weight: .bold))
          .foregroundStyle(mono ? .white : Color.onyx.dayLabel(s?.workout.dayKey))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
    }
    .frame(maxWidth: .infinity)
  }
}

// MARK: - Water · the glasses
//
// ── WHAT THE RAIL COULD NOT SAY ──────────────────────────────────────────────
// Every water face led with `1.9` over a progress rail: a litre figure to three
// significant figures and a proportion, neither of which is the question. The
// question is how many more glasses, and the answer was a subtraction, a
// division and a rounding away.
//
// `GlassArc` is the figure now — `goal ÷ 250 ml` segments, as many of them full
// as there are glasses in the day — and on the Home Screen the button beside it
// adds the next one without opening anything. See `EnvironmentValues
// .onyxWaterButton` for why the button is handed in rather than written here.

/// Small · the glasses, the count, and the tap.
struct WaterGlassFace: View {
  let entry: OnyxTileEntry
  let mono: Bool
  @Environment(\.onyxWaterButton) private var button

  private var s: OnyxSnapshot? { entry.snapshot }
  private var counts: (total: Int, filled: Int)? {
    GlassArc.segments(ml: s?.water.ml, goalMl: s?.water.goalMl)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Caption("WATER", color: mono ? .white : Color.onyx.water)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }
      ZStack {
        GlassArc(ml: s?.water.ml, goalMl: s?.water.goalMl,
                 tint: Color.onyx.water, lineWidth: 9, monochrome: mono)
        VStack(spacing: 0) {
          BigValue(value: counts.map { "\($0.filled)" }, size: 26, color: Color.onyx.textPrimary)
          Text(counts.map { "of \($0.total)" } ?? "glasses")
            .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      HStack(spacing: 4) {
        Text(litresText(s) ?? "—")
          .font(OnyxWidgetType.face(9, weight: .semibold))
          .foregroundStyle(Color.onyx.textSecondary)
          .lineLimit(1)
        Spacer(minLength: 0)
        if let button { button.make() }
      }
    }
  }
}

/// "1.9 of 3.0 L", or the litres alone with no goal to be a fraction of.
func litresText(_ s: OnyxSnapshot?) -> String? {
  guard let ml = s?.water.ml else { return nil }
  guard let goal = s?.water.goalMl, goal > 0 else { return String(format: "%.1f L", ml / 1000) }
  return String(format: "%.1f of %.1f L", ml / 1000, goal / 1000)
}

/// Water Medium · hydration led by hydration.
///
/// The old one put a STEPS hero beside protein, water, sleep and battery — three
/// subjects, none of them the one on the label. This is water, its week, and the
/// two figures that belong to the same question of how much the day moved.
struct WaterLedgerFace: View {
  let entry: OnyxTileEntry
  let mono: Bool
  @Environment(\.onyxWaterButton) private var button

  private var s: OnyxSnapshot? { entry.snapshot }
  private func tint(_ c: Color) -> Color { mono ? .white : c }

  var body: some View {
    HStack(spacing: 12) {
      // Not a `Link` any more: the hero column holds the +250 ml button on the
      // Home Screen, and a `Button` inside a `Link` is a tap with two owners —
      // WidgetKit resolves it to the link and the button never fires. The
      // face's root `widgetURL` still covers this half.
      heroColumn
      Hairline(vertical: true)
      Link(destination: OnyxLink.progress ?? OnyxLink.home!) { weekColumn }
    }
  }

  private var counts: (total: Int, filled: Int)? {
    GlassArc.segments(ml: s?.water.ml, goalMl: s?.water.goalMl)
  }

  private var heroColumn: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Caption("WATER", color: tint(Color.onyx.water))
        if entry.isStale { StaleTag(age: entry.age) }
      }
      ZStack {
        GlassArc(ml: s?.water.ml, goalMl: s?.water.goalMl,
                 tint: Color.onyx.water, lineWidth: 9, monochrome: mono)
        VStack(spacing: 0) {
          BigValue(value: counts.map { "\($0.filled)" }, size: 24, color: Color.onyx.textPrimary)
          Text(counts.map { "of \($0.total) glasses" } ?? "glasses")
            .font(OnyxWidgetType.face(8)).foregroundStyle(Color.onyx.textSecondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      HStack(spacing: 4) {
        Text(litresLeft ?? litresText(s) ?? "—")
          .font(OnyxWidgetType.face(9, weight: .semibold)).foregroundStyle(Color.onyx.textSecondary)
          .lineLimit(1)
        Spacer(minLength: 0)
        if let button { button.make() }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var weekColumn: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 4) {
        Caption("7 DAYS", color: Color.onyx.textSecondary)
        Spacer(minLength: 0)
        if let mean = weeklyMean {
          Text(String(format: "avg %.1f L", mean / 1000))
            .font(OnyxWidgetType.face(8)).foregroundStyle(Color.onyx.textSecondary)
        }
      }
      BarChart(points: s?.water.trend ?? [], goal: s?.water.goalMl,
               color: tint(Color.onyx.water),
               label: { OnyxSnapshot.weekdayInitial($0.d) })
        .frame(maxHeight: .infinity)
      Hairline()
      HStack(spacing: 0) {
        Stat(value: s?.steps.count.map { "\($0)" }, label: "STEPS", color: Color.onyx.textPrimary)
        Stat(value: s?.steps.activeKcal.map { "\(Int($0.rounded()))" }, label: "MOVE KCAL",
             color: tint(OnyxDomain.body.accent))
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var weeklyMean: Double? {
    let points = s?.water.trend ?? []
    guard !points.isEmpty else { return nil }
    return points.reduce(0) { $0 + $1.v } / Double(points.count)
  }

  /// "0.6 L to go", or "goal met". Never a negative litre count.
  private var litresLeft: String? {
    guard let ml = s?.water.ml, let goal = s?.water.goalMl, goal > 0 else { return nil }
    let gap = goal - ml
    return gap <= 0 ? "goal met" : String(format: "%.1f L to go", gap / 1000)
  }
}

// MARK: - Sleep · the depth strip at three sizes
//
// ── WHY THE GAUGE GAVE WAY TO THE STRIP (W6) ─────────────────────────────────
// `DepthArc` answers two questions at once — was it long enough, and what was
// it made of — and that is exactly what made it hard to read: a semicircle
// whose SWEEP means duration and whose FILL means composition asks the eye to
// hold two scales on one shape. The composition is the interesting half (the
// duration is a number, and the number is right there), so it gets the figure
// to itself and the goal becomes a rail under it.
//
// `DepthStrip` is that figure. It is NOT a hypnogram and its own header says
// why at length: the builder reads `sleep_sessions`, which carries four stage
// TOTALS and no instant, so the axis is share of night and the layout is by
// depth. Sample-level stages are the stated ceiling.
//
//   Small   the strip    what the night was made of, and how long it was
//   Medium  + seven      is this a normal night for you
//   Large   + rows       how much of each stage, in minutes and in share

/// The stages, as `DepthBar` and `DepthArc` both want them. A stage with no
/// reading is ABSENT, not zero — the difference between "you had no deep sleep"
/// and "the watch did not report deep sleep".
public func sleepSegments(_ s: OnyxSnapshot?) -> [(OnyxSleepStage, Int)] {
  guard let sleep = s?.sleep else { return [] }
  return [
    (OnyxSleepStage.deep, sleep.deepMin),
    (OnyxSleepStage.core, sleep.coreMin),
    (OnyxSleepStage.rem, sleep.remMin),
    (OnyxSleepStage.awake, sleep.awakeMin),
  ].compactMap { stage, minutes in minutes.map { (stage, $0) } }
}

/// "21:48 → 07:03". Both ends or neither — half a window is a riddle.
public func sleepWindowText(_ s: OnyxSnapshot?) -> String? {
  guard let from = OnyxSnapshot.clockTime(s?.sleep.startTime),
        let to = OnyxSnapshot.clockTime(s?.sleep.endTime) else { return nil }
  return "\(from) → \(to)"
}

/// Small · the duration, the strip, and how much of the goal it covered.
struct SleepArcFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Caption("SLEEP", color: mono ? .white : OnyxDomain.recover.accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        BigValue(value: sleepDuration(s), size: 26, color: Color.onyx.textPrimary)
        if let score = s?.sleep.score {
          Text("· \(score)").font(OnyxWidgetType.face(10, weight: .semibold)).foregroundStyle(Color.onyx.textSecondary)
        }
      }

      DepthStrip(segments: sleepSegments(s), monochrome: mono)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      SleepStripAxis(s: s, mono: mono, compact: true)

      // The goal is the rail the arc's sweep used to be. A proportion belongs
      // on a bar; the composition belongs on the strip; neither has to carry
      // the other's scale now.
      Rail(progress: OnyxSnapshot.progress(
             s?.sleep.minutes.map(Double.init),
             s?.sleep.goalMin.map(Double.init) ?? 480),
           color: mono ? .white : OnyxDomain.recover.accent, height: 4)
    }
  }
}

/// The strip's caption: what the axis means, and the window it covers.
///
/// The words "share of night" are the whole reason the strip is allowed to look
/// like a hypnogram — see `DepthStrip`. They are not decoration and must not be
/// dropped to save a line.
struct SleepStripAxis: View {
  let s: OnyxSnapshot?
  let mono: Bool
  var compact = false
  /// The Medium prints the window in its own header and must not print it
  /// twice — the axis's job is the WORDS, and the window is a passenger on a
  /// line that would otherwise be half empty.
  var showsWindow = true

  var body: some View {
    HStack(spacing: 4) {
      Text("share of night")
        .font(OnyxWidgetType.face(compact ? 7 : 8))
        .foregroundStyle(Color.onyx.textTertiary)
      Spacer(minLength: 0)
      if showsWindow, let window = sleepWindowText(s) {
        Text(window)
          .font(OnyxWidgetType.face(compact ? 8 : 9))
          .foregroundStyle(Color.onyx.textSecondary)
          .lineLimit(1)
      }
    }
  }
}

/// Medium · the strip, and the week it sits in.
///
/// ── WHY THE SEVEN NIGHTS MOVED DOWN FROM THE LARGE (W6) ──────────────────────
/// The Medium used to be the arc plus four stage rows — the same composition
/// the strip now draws, said again in minutes and percentages. The register a
/// Medium was missing is the one that makes last night MEAN anything: 6h14m is
/// a bad night or an ordinary one depending entirely on the six before it, and
/// `BarChart` over `sleep.trend` has been in the payload the whole time. The
/// stage rows are what a Large is for, and they are still there.
struct SleepDepthFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var segments: [(OnyxSleepStage, Int)] { sleepSegments(s) }
  private var total: Int { segments.reduce(0) { $0 + $1.1 } }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Caption("SLEEP", color: mono ? .white : OnyxDomain.recover.accent)
        Spacer(minLength: 0)
        if let window = sleepWindowText(s) {
          Text(window).font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
        }
        if let score = s?.sleep.score {
          Text("score \(score)").font(OnyxWidgetType.face(9, weight: .semibold)).foregroundStyle(Color.onyx.textPrimary)
        }
        if entry.isStale { StaleTag(age: entry.age) }
      }
      // The corner belongs to the mark; this row's content runs to the edge.
      .padding(.trailing, OnyxMark.faceInset)

      HStack(alignment: .firstTextBaseline, spacing: 6) {
        BigValue(value: sleepDuration(s), size: 24, color: Color.onyx.textPrimary)
        if let goal = s?.sleep.goalMin {
          Text("of \(OnyxSnapshot.formatSleep(goal))")
            .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
        }
        Spacer(minLength: 0)
        StageKey(segments: segments, total: total, mono: mono)
      }

      DepthStrip(segments: segments, monochrome: mono)
        .frame(maxHeight: .infinity)
      SleepStripAxis(s: s, mono: mono, showsWindow: false)

      Hairline()

      // The week behind last night. Labelled so a short Wednesday is legible
      // as a Wednesday and not as "the fifth bar".
      BarChart(points: s?.sleep.trend ?? [],
               goal: s?.sleep.goalMin.map(Double.init) ?? 480,
               color: mono ? .white : OnyxDomain.recover.accent,
               label: { OnyxSnapshot.weekdayInitial($0.d) })
        .frame(maxHeight: .infinity)
    }
  }
}

/// The four stages as four dots and their share — the legend the strip needs
/// and the space a Medium has for.
///
/// Shares, not minutes: "68m deep" and "16% deep" answer different questions,
/// and the percentage is the one that travels between nights of different
/// length — which is the comparison the seven-night chart underneath invites.
private struct StageKey: View {
  let segments: [(OnyxSleepStage, Int)]
  let total: Int
  let mono: Bool

  var body: some View {
    HStack(spacing: 6) {
      ForEach(OnyxSleepStage.allCases, id: \.self) { stage in
        if let minutes = segments.first(where: { $0.0 == stage })?.1, minutes > 0, total > 0 {
          HStack(spacing: 2) {
            Circle()
              .fill(mono ? Color.white.opacity(DepthStrip.opacity(stage)) : stage.color)
              .frame(width: 5, height: 5)
            Text("\(Int((Double(minutes) / Double(total) * 100).rounded()))%")
              .font(OnyxWidgetType.face(8, weight: .semibold)).monospacedDigit()
              .foregroundStyle(Color.onyx.textSecondary)
          }
        }
      }
    }
    .lineLimit(1)
  }
}

/// One stage: its colour, its name, its minutes, and its share of the night.
private struct StageRow: View {
  let stage: OnyxSleepStage
  let minutes: Int?
  let total: Int
  let mono: Bool

  var body: some View {
    // Each fixed column is sized to the longest string it can actually hold —
    // "AWAKE", "251m", "57%" — rather than to a round number. The fourteen
    // points that frees go to the gauge beside it, which had none.
    HStack(spacing: 5) {
      Circle()
        .fill(mono ? Color.white : stage.color)
        .frame(width: 6, height: 6)
      Text(stage.label)
        .font(OnyxWidgetType.face(9, weight: .bold))
        .foregroundStyle(Color.onyx.textSecondary)
        // 38, which is what "AWAKE" measures — and then pinned to one line
        // anyway. A stage name that wraps takes the row's height with it and
        // pushes the fourth row out of the tile, which is a worse failure than
        // the two points it was saving.
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .frame(width: 38, alignment: .leading)
      Rail(progress: share, color: mono ? .white : stage.color, height: 4)
      Text(minutes.map { "\($0)m" } ?? "—")
        .font(OnyxWidgetType.face(10, weight: .semibold, design: .monospaced))
        .foregroundStyle(Color.onyx.textPrimary)
        .frame(width: 30, alignment: .trailing)
      Text(share.map { "\(Int(($0 * 100).rounded()))%" } ?? "")
        .font(OnyxWidgetType.face(9))
        .foregroundStyle(Color.onyx.textSecondary)
        .frame(width: 22, alignment: .trailing)
    }
  }

  /// Share of the STAGED total, not of the goal — this is a composition, and a
  /// composition that does not add to 100% is not one.
  private var share: Double? {
    guard let minutes, total > 0 else { return nil }
    return Double(minutes) / Double(total)
  }
}

/// Large · three registers, where it used to be the Medium and a hand's width of
/// obsidian. The seven-night register is what fills it, and it is the register
/// that makes last night mean anything: 6h14m is a bad night or an ordinary one
/// depending entirely on the six before it.
struct SleepLargeFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private func tint(_ c: Color) -> Color { mono ? .white : c }
  private var segments: [(OnyxSleepStage, Int)] { sleepSegments(s) }
  private var total: Int { segments.reduce(0) { $0 + $1.1 } }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Register(title: "LAST NIGHT", accent: tint(OnyxDomain.recover.accent)) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          BigValue(value: sleepDuration(s), size: 30, color: Color.onyx.textPrimary)
          if let score = s?.sleep.score {
            Text("score \(score)").font(OnyxWidgetType.face(10, weight: .semibold))
              .foregroundStyle(Color.onyx.textSecondary)
          }
          Spacer(minLength: 0)
          if let debt = debtText {
            Text(debt).font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
          }
          if entry.isStale { StaleTag(age: entry.age) }
        }
        DepthStrip(segments: segments, monochrome: mono)
          .frame(height: 56)
        SleepStripAxis(s: s, mono: mono)
      }

      Hairline()

      Register(title: "STAGES", accent: tint(OnyxDomain.recover.end)) {
        VStack(spacing: 5) {
          ForEach(OnyxSleepStage.allCases, id: \.self) { stage in
            StageRow(stage: stage,
                     minutes: segments.first(where: { $0.0 == stage })?.1,
                     total: total, mono: mono)
          }
        }
      }
      .frame(maxHeight: .infinity)

      Hairline()

      Register(title: "SEVEN NIGHTS", accent: tint(OnyxDomain.recover.accent)) {
        BarChart(points: s?.sleep.trend ?? [],
                 goal: s?.sleep.goalMin.map(Double.init) ?? 480,
                 color: tint(OnyxDomain.recover.accent),
                 label: { OnyxSnapshot.weekdayInitial($0.d) })
          .frame(maxHeight: .infinity)
      }
      .frame(maxHeight: .infinity)
    }
  }

  /// How far under the goal the night fell. Silent when it met it — "0m short"
  /// is a sentence about nothing.
  private var debtText: String? {
    guard let minutes = s?.sleep.minutes, minutes > 0 else { return nil }
    let goal = s?.sleep.goalMin ?? 480
    let gap = goal - minutes
    return gap > 5 ? "\(OnyxSnapshot.formatSleep(gap)) short of goal" : "goal met"
  }
}

// MARK: - Weight · the scale, and what the scale is made of
//
// ── THREE MEASUREMENTS, NEVER INTERCHANGEABLE ────────────────────────────────
// `smmKg` is SKELETAL MUSCLE (~27 kg, entered by hand off the InBody — never
// derived from anything). `muscleKg` is LEAN SOFT TISSUE (~50 kg) and is labelled
// as such, because calling it "muscle" next to a 27 puts two numbers for the same
// word on one face, twenty kilos apart. `ffmKg` is FAT-FREE MASS (~53 kg).
// Whichever of the three a face shows, it shows under its own name.

/// A composition figure and its movement since the last DIFFERENT reading.
///
/// Internal rather than private since the Composition focus exists: the rows it
/// draws are these rows, and a second copy would be a second place for the
/// "down is good for fat, bad for lean tissue" rule to be got wrong.
struct CompositionRow: View {
  let label: String
  let value: Double?
  let delta: Double?
  let unit: String
  let color: Color
  let mono: Bool
  /// Down is good for body fat and bad for lean tissue — the metric decides,
  /// never the sign.
  var upIsGood = true
  var compact = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(label)
        .font(OnyxWidgetType.face(compact ? 8 : 9, weight: .bold))
        .foregroundStyle(Color.onyx.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      Spacer(minLength: 4)
      BigValue(value: value.map { String(format: "%.1f", $0) }, size: compact ? 12 : 14, color: color)
      Text(unit).font(OnyxWidgetType.face(8)).foregroundStyle(Color.onyx.textSecondary)
      DeltaChip(delta: delta, decimals: 1, upIsGood: upIsGood, monochrome: mono)
    }
  }
}

/// Small · the ask: a trendline and the composition packed under it, where there
/// used to be a number, a delta and a flat progress rail.
struct WeightFocusFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var accent: Color { mono ? .white : OnyxDomain.body.accent }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Caption("WEIGHT", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        BigValue(value: s?.weight.kg.map { String(format: "%.1f", $0) }, size: 27, color: Color.onyx.textPrimary)
        Text("kg").font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
        DeltaChip(delta: s?.weight.deltaKg, decimals: 1, upIsGood: false, monochrome: mono)
      }

      Sparkline(points: (s?.weight.trend ?? []).map(\.v),
                baseline: s?.weight.prevWeekMeanKg, color: accent)
        .frame(maxHeight: .infinity)

      Hairline()

      CompositionRow(label: "FAT", value: s?.body?.fatPct, delta: s?.body?.fatPctDelta,
                     unit: "%", color: mono ? .white : OnyxDomain.body.at(0.5), mono: mono,
                     upIsGood: false, compact: true)
      CompositionRow(label: "LEAN", value: s?.body?.muscleKg, delta: s?.body?.muscleKgDelta,
                     unit: "kg", color: mono ? .white : OnyxDomain.body.end, mono: mono, compact: true)
    }
  }
}

/// Medium · the fortnight, and the composition beside it.
struct WeightTrendFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var points: [Double] { (s?.weight.trend ?? []).map(\.v) }

  var body: some View {
    HStack(spacing: 12) {
      trendColumn
      Hairline(vertical: true)
      compositionColumn
    }
  }

  private var trendColumn: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Caption("WEIGHT", color: mono ? .white : OnyxDomain.body.accent)
        Spacer(minLength: 0)
        if let measured = OnyxSnapshot.relativeDay(s?.weight.measuredOn) {
          Text(measured).font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
        }
        if entry.isStale { StaleTag(age: entry.age) }
      }
      // The corner belongs to the mark; this row's content runs to the edge.
      .padding(.trailing, OnyxMark.faceInset)

      HStack(alignment: .firstTextBaseline, spacing: 6) {
        BigValue(value: s?.weight.kg.map { String(format: "%.1f", $0) }, size: 28, color: Color.onyx.textPrimary)
        Text("kg").font(OnyxWidgetType.face(11)).foregroundStyle(Color.onyx.textSecondary)
        // Down is the good direction here, and only here. `deltaVerdict.ts`
        // makes the same point on the web: the sign does not decide the verdict,
        // the phase does.
        DeltaChip(delta: s?.weight.deltaKg, decimals: 1, upIsGood: false, monochrome: mono)
      }

      // Never zero-based: a fortnight between 78.2 and 79.6 read against zero is
      // a flat line, and the whole point of the face is the 1.4 kg.
      Sparkline(points: points, baseline: s?.weight.prevWeekMeanKg,
                color: mono ? .white : OnyxDomain.body.accent)
        .frame(maxHeight: .infinity)

      HStack(spacing: 6) {
        if let baseline = s?.weight.prevWeekMeanKg {
          Label {
            Text(String(format: "last wk %.1f", baseline))
              .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
          } icon: {
            Rectangle().fill(Color.onyx.textSecondary).frame(width: 8, height: 1)
          }
        }
        Spacer(minLength: 0)
        if let togo {
          Text(togo).font(OnyxWidgetType.face(9, weight: .semibold)).foregroundStyle(Color.onyx.textSecondary)
            .lineLimit(1)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var compositionColumn: some View {
    VStack(spacing: 0) {
      CompositionRow(label: "BODY FAT", value: s?.body?.fatPct, delta: s?.body?.fatPctDelta,
                     unit: "%", color: mono ? .white : OnyxDomain.body.at(0.5), mono: mono, upIsGood: false)
      Hairline().padding(.vertical, 4)
      CompositionRow(label: "LEAN SOFT TISSUE", value: s?.body?.muscleKg, delta: s?.body?.muscleKgDelta,
                     unit: "kg", color: mono ? .white : OnyxDomain.body.end, mono: mono)
      Hairline().padding(.vertical, 4)
      CompositionRow(label: "SKELETAL MUSCLE", value: s?.body?.smmKg, delta: s?.body?.smmKgDelta,
                     unit: "kg", color: mono ? .white : OnyxDomain.body.at(0.25), mono: mono)
      Hairline().padding(.vertical, 4)
      CompositionRow(label: "FAT-FREE MASS", value: s?.body?.ffmKg, delta: s?.body?.ffmKgDelta,
                     unit: "kg", color: Color.onyx.textPrimary, mono: mono)
    }
    .frame(maxWidth: .infinity)
  }

  /// "1.8 kg to target", or nothing. Never "0.0 kg to target" from a missing goal.
  private var togo: String? {
    guard let now = s?.weight.kg, let target = s?.weight.targetKg else { return nil }
    let gap = abs(now - target)
    return gap < 0.05 ? "at target" : String(format: "%.1f kg to go", gap)
  }
}

/// Large · the scale, what it is made of, and where both have been.
struct WeightLargeFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private func tint(_ c: Color) -> Color { mono ? .white : c }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Register(title: "THE SCALE", accent: tint(OnyxDomain.body.accent)) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          BigValue(value: s?.weight.kg.map { String(format: "%.1f", $0) }, size: 36, color: Color.onyx.textPrimary)
          Text("kg").font(OnyxWidgetType.face(12)).foregroundStyle(Color.onyx.textSecondary)
          DeltaChip(delta: s?.weight.deltaKg, decimals: 1, upIsGood: false, monochrome: mono)
          Spacer(minLength: 0)
          if entry.isStale { StaleTag(age: entry.age) }
          if let measured = OnyxSnapshot.relativeDay(s?.weight.measuredOn) {
            Text(measured).font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
          }
        }
        if let target = s?.weight.targetKg, let now = s?.weight.kg {
          let gap = abs(now - target)
          Text(gap < 0.05
               ? String(format: "at target %.1f kg", target)
               : String(format: "%.1f kg to target %.1f", gap, target))
            .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
        }
      }

      Hairline()

      Register(title: "COMPOSITION", accent: tint(OnyxDomain.body.end)) {
        VStack(spacing: 0) {
          CompositionRow(label: "BODY FAT", value: s?.body?.fatPct, delta: s?.body?.fatPctDelta,
                         unit: "%", color: tint(OnyxDomain.body.at(0.5)), mono: mono, upIsGood: false)
          Hairline().padding(.vertical, 4)
          CompositionRow(label: "LEAN SOFT TISSUE", value: s?.body?.muscleKg,
                         delta: s?.body?.muscleKgDelta, unit: "kg",
                         color: tint(OnyxDomain.body.end), mono: mono)
          Hairline().padding(.vertical, 4)
          CompositionRow(label: "SKELETAL MUSCLE", value: s?.body?.smmKg, delta: s?.body?.smmKgDelta,
                         unit: "kg", color: tint(OnyxDomain.body.at(0.25)), mono: mono)
          Hairline().padding(.vertical, 4)
          CompositionRow(label: "FAT-FREE MASS", value: s?.body?.ffmKg, delta: s?.body?.ffmKgDelta,
                         unit: "kg", color: Color.onyx.textPrimary, mono: mono)
        }
      }
      .frame(maxHeight: .infinity)

      Hairline()

      // Two traces, two subjects, two scales — so they are stacked rather than
      // overlaid. A body-fat percentage and a bodyweight share no axis, and
      // drawing them on one would make the crossing point look like an event.
      Register(title: "THE FORTNIGHT", accent: tint(Color.onyx.textSecondary)) {
        VStack(alignment: .leading, spacing: 4) {
          TraceRow(title: "WEIGHT", unit: "kg",
                   points: (s?.weight.trend ?? []).map(\.v),
                   color: tint(OnyxDomain.body.accent))
          TraceRow(title: "BODY FAT", unit: "%",
                   points: (s?.body?.fatTrend ?? []).map(\.v),
                   color: tint(OnyxDomain.body.at(0.5)))
        }
      }
      .frame(maxHeight: .infinity)
    }
  }
}

/// A labelled sparkline with its own first and last readings called out.
private struct TraceRow: View {
  let title: String
  let unit: String
  let points: [Double]
  let color: Color

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(OnyxWidgetType.face(8, weight: .bold)).foregroundStyle(Color.onyx.textSecondary)
        Text(points.last.map { String(format: "%.1f \(unit)", $0) } ?? "—")
          .font(OnyxWidgetType.face(12, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(color)
      }
      .frame(width: 62, alignment: .leading)
      Sparkline(points: points, color: color)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxHeight: .infinity)
  }
}

// MARK: - Calories (Large)
//
// ── WHAT THE MISSING HIERARCHY ACTUALLY WAS ──────────────────────────────────
// The data on this face was right; it was a flat wall of it. Four rails, seven
// columns and three footers, all the same weight, with nothing saying which
// question any group answered — so reading it meant recognising each number
// rather than being told what you were looking at.
//
// Three named registers fix that, and they are named for the QUESTION rather
// than the table: what is left to eat, how the rest of the day is going, and
// whether this is a normal day for you. That last one is what the seven-day
// register earns its height with — a 612 kcal deficit is unremarkable or alarming
// depending entirely on the six days behind it, and nothing on the old face said.

struct CalorieDayFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private func tint(_ c: Color) -> Color { mono ? .white : c }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Register(title: "LEFT TO EAT", accent: tint(OnyxDomain.fuel.accent)) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          BigValue(value: s?.caloriesRemaining.map { "\($0)" }, size: 34, color: Color.onyx.textPrimary)
          Text("kcal").font(OnyxWidgetType.face(11)).foregroundStyle(Color.onyx.textSecondary)
          if let goal = s?.macros.kcalGoal {
            Text("of \(Int(goal.rounded()))")
              .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
          }
          Spacer(minLength: 0)
          if entry.isStale { StaleTag(age: entry.age) }
          BatteryRing(pct: s?.battery, size: 38, lineWidth: 5, monochrome: mono)
        }
        Rail(progress: OnyxSnapshot.progress(s?.macros.kcal, s?.macros.kcalGoal),
             color: tint(OnyxDomain.fuel.accent), height: 5)
        HStack(spacing: 5) {
          MacroChip(label: "P", value: s?.macros.proteinG, goal: s?.macros.proteinGoalG,
                    color: tint(Color.onyx.protein))
          MacroChip(label: "C", value: s?.macros.carbsG, goal: s?.macros.carbsGoalG,
                    color: tint(Color.onyx.carbs))
          MacroChip(label: "F", value: s?.macros.fatG, goal: s?.macros.fatGoalG,
                    color: tint(Color.onyx.fat))
        }
      }

      Hairline()

      Register(title: "THE REST OF THE DAY", accent: tint(OnyxDomain.body.accent)) {
        VStack(spacing: 7) {
          Gauge(label: "WATER", value: s?.water.ml.map { String(format: "%.1f", $0 / 1000) }, unit: "L",
                progress: OnyxSnapshot.progress(s?.water.ml, s?.water.goalMl), color: tint(Color.onyx.water))
          Gauge(label: "STEPS", value: s?.steps.count.map { "\($0)" }, unit: "",
                progress: OnyxSnapshot.progress(
                  s?.steps.count.map(Double.init), s?.steps.goal.map(Double.init)), color: tint(OnyxDomain.body.accent))
          Gauge(label: "SLEEP", value: sleepDuration(s), unit: "",
                progress: OnyxSnapshot.progress(
                  s?.sleep.minutes.map(Double.init),
                  s?.sleep.goalMin.map(Double.init) ?? 480), color: tint(OnyxDomain.recover.accent))
        }
      }
      .frame(maxHeight: .infinity)

      Hairline()

      Register(title: "SEVEN DAYS", accent: tint(OnyxDomain.fuel.accent)) {
        BarChart(points: s?.macros.kcalTrend ?? [], goal: s?.macros.kcalGoal,
                 color: tint(OnyxDomain.fuel.accent),
                 label: { OnyxSnapshot.weekdayInitial($0.d) })
          .frame(maxHeight: .infinity)
      }
      .frame(maxHeight: .infinity)

      Hairline()

      HStack(spacing: 0) {
        Foot(label: "TODAY", value: nextSessionText(s),
             color: mono ? .white : Color.onyx.day(s?.workout.dayKey))
        Foot(label: "WEIGHT", value: s?.weight.kg.map { String(format: "%.1f kg", $0) },
             color: tint(OnyxDomain.body.accent))
        Foot(label: "SCORE", value: s?.score.map { "\($0)" }, color: Color.onyx.textPrimary)
      }
    }
  }
}

/// A macro as one inline chip — letter, figure, target. For a register that has
/// already spent its vertical budget on the headline rail above it.
private struct MacroChip: View {
  let label: String
  let value: Double?
  let goal: Double?
  let color: Color

  var body: some View {
    HStack(spacing: 3) {
      Text(label)
        .font(OnyxWidgetType.face(8, weight: .bold, design: .rounded))
        .foregroundStyle(color)
      Text(figures)
        .font(OnyxWidgetType.face(9, weight: .medium, design: .monospaced))
        .foregroundStyle(Color.onyx.textSecondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The remainder, in the same words the rails use — see `MacroRemainder`.
  private var figures: String { MacroRemainder.text(value, goal) ?? "—" }
}

private struct Gauge: View {
  let label: String
  let value: String?
  let unit: String
  let progress: Double?
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(label).font(OnyxWidgetType.face(9, weight: .heavy)).tracking(0.8).foregroundStyle(Color.onyx.textSecondary)
        Spacer(minLength: 4)
        BigValue(value: value, size: 15, color: color)
        if !unit.isEmpty {
          Text(unit).font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
        }
      }
      Rail(progress: progress, color: color, height: 3)
    }
  }
}

private struct Foot: View {
  let label: String
  let value: String?
  let color: Color
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(OnyxWidgetType.face(8, weight: .heavy)).tracking(0.8).foregroundStyle(Color.onyx.textSecondary)
      BigValue(value: value, size: 14, color: color)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Seven days of steps as columns, today brightened.
///
/// Steps rather than a four-metric stack: it is the only lifestyle series the
/// payload carries a full week of. A column built from one real number and three
/// repeats of today's would LOOK like a week of four metrics and be a week of
/// one — which is the exact class of thing the em-dash rule exists to prevent.
private struct WeekColumns: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var trend: [OnyxSnapshot.Point] { entry.snapshot?.steps.trend ?? [] }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Caption("7 DAYS", color: Color.onyx.textSecondary)
        Spacer(minLength: 0)
        if let goal = entry.snapshot?.steps.goal {
          Text("goal \(goal / 1000)k").font(OnyxWidgetType.face(8)).foregroundStyle(Color.onyx.textSecondary)
        }
      }
      if trend.count >= 2 {
        let peak = max(trend.map(\.v).max() ?? 1, Double(entry.snapshot?.steps.goal ?? 0))
        HStack(alignment: .bottom, spacing: 4) {
          ForEach(trend) { point in
            VStack(spacing: 3) {
              DayColumn(
                segments: [(peak > 0 ? point.v / peak : 0, mono ? .white : OnyxDomain.body.accent)],
                highlighted: point.d == entry.snapshot?.date
              )
              Text(OnyxSnapshot.weekdayInitial(point.d))
                .font(OnyxWidgetType.face(7, weight: .bold))
                .foregroundStyle(Color.onyx.textSecondary)
            }
          }
        }
      } else {
        Text("a week of steps appears here\nonce there are two days of them")
          .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
  }
}

// MARK: - C7 · Macros
//
// ── THE FACE THIS FAMILY WAS REBUILT FOR ─────────────────────────────────────
// `carbsG`, `carbsGoalG`, `fatG` and `fatGoalG` have shipped in the payload
// since the first version and were drawn nowhere. On a cut those are two of the
// three numbers that decide the day, and the only widget that could show them
// showed protein alone.

/// Small · the three macros, and nothing else. Calories are the caption, not the
/// hero: you picked "Macros".
struct MacroFocusFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private func tint(_ c: Color) -> Color { mono ? .white : c }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption("MACROS", color: tint(OnyxDomain.fuel.accent))
        // A declared day changes what the number MEANS — the app has already
        // forgiven the grade, and a face showing the overshoot with no mark on
        // it reports a failure the rest of the system does not think happened.
        ContextChip(context: s?.context, monochrome: mono)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        BigValue(value: s?.caloriesRemaining.map { "\($0)" }, size: 22, color: Color.onyx.textPrimary)
        Text("kcal left").font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
      }
      Spacer(minLength: 0)
      MacroRail(label: "P", value: s?.macros.proteinG, goal: s?.macros.proteinGoalG,
                color: tint(Color.onyx.protein))
      MacroRail(label: "C", value: s?.macros.carbsG, goal: s?.macros.carbsGoalG,
                color: tint(Color.onyx.carbs))
      MacroRail(label: "F", value: s?.macros.fatG, goal: s?.macros.fatGoalG,
                color: tint(Color.onyx.fat))
    }
  }
}

/// Medium · left 60% the calorie headline over a full-width rail, then the three
/// macros as 3pt rails with their own figures — one bar per thing being filled,
/// which is the same grammar as the app's Fuel card. Right 40%, hairline-
/// separated: the four facts that are NOT macros, so the two halves never argue
/// about what they are for.
struct MacroFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private func tint(_ c: Color) -> Color { mono ? .white : c }

  var body: some View {
    // Full width, not two columns. The two-column version spent 40% of a Medium
    // on battery, sleep, water and steps — a ledger of four things that are not
    // macros, on the face you chose BECAUSE you wanted macros. The width goes to
    // the bars instead.
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Caption("MACROS", color: tint(OnyxDomain.fuel.accent))
        Spacer(minLength: 0)
        BigValue(value: s?.caloriesRemaining.map { "\($0)" }, size: 20, color: Color.onyx.textPrimary)
        Text("kcal left").font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
        if entry.isStale { StaleTag(age: entry.age) }
      }
      // The corner belongs to the mark; this row's content runs to the edge.
      .padding(.trailing, OnyxMark.faceInset)

      Rail(progress: OnyxSnapshot.progress(s?.macros.kcal, s?.macros.kcalGoal),
           color: tint(OnyxDomain.fuel.accent), height: 4)

      VStack(spacing: 6) {
        MacroLine(name: "PROTEIN", value: s?.macros.proteinG, goal: s?.macros.proteinGoalG,
                  color: tint(Color.onyx.protein), mono: mono)
        MacroLine(name: "CARBS", value: s?.macros.carbsG, goal: s?.macros.carbsGoalG,
                  color: tint(Color.onyx.carbs), mono: mono)
        MacroLine(name: "FAT", value: s?.macros.fatG, goal: s?.macros.fatGoalG,
                  color: tint(Color.onyx.fat), mono: mono)
      }
      .frame(maxHeight: .infinity)
    }
  }
}

/// One macro, inline: name, figures, a short bar, and what is LEFT of it.
///
/// ── WHY THE REMAINDER IS A SEPARATE NUMBER ───────────────────────────────────
/// "128 / 165 g" requires the reader to do the subtraction, and the subtraction
/// is the only part they were going to act on — nobody eats a ratio. So the
/// remainder is stated, signed, and coloured by whether it is a shortfall or an
/// overshoot. Protein over target is a good day and fat over target is not, but
/// that judgement belongs to the app's own grading, so the chip stays neutral in
/// wording ("+12 g over") and lets the colour carry only the DIRECTION.
private struct MacroLine: View {
  let name: String
  let value: Double?
  let goal: Double?
  let color: Color
  let mono: Bool

  var body: some View {
    HStack(spacing: 8) {
      Text(name)
        .font(OnyxWidgetType.face(9, weight: .bold))
        .foregroundStyle(color)
        .frame(width: 52, alignment: .leading)

      Rail(progress: OnyxSnapshot.progress(value, goal), color: color, height: 5)

      // ── ONE FIGURE, NOT TWO (W6) ──────────────────────────────────────────
      // This row used to print `128/165g` AND `37g` side by side, which is the
      // same fact said twice with a subtraction between them — and it left the
      // remainder 46 pt to say "37 g left" in. The rail carries the proportion
      // and always did; the digits carry the remainder alone, and the column
      // they had to share is now wide enough for the sentence.
      Text(remainder)
        .font(OnyxWidgetType.face(10, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(remainderColor)
        .frame(width: 74, alignment: .trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
  }

  /// Nothing to be left OF without a goal — an em dash, never a bare intake
  /// figure dressed up as a remainder. `MacroRemainder` since W6, so this face
  /// and the four that gained the same framing cannot word "met" differently.
  private var remainder: String {
    guard value != nil, goal != nil else { return "—" }
    return MacroRemainder.text(value, goal) ?? "—"
  }

  /// `good` only when the target is MET — and never in `.accented` rendering,
  /// where a green figure on a one-tint tile reads as a rendering fault rather
  /// than as a verdict (the `mono ? .white` rule). This line was the one
  /// ungated verdict colour left in a face W6 touched.
  private var remainderColor: Color {
    if mono { return .white }
    guard let value, let goal else { return Color.onyx.textSecondary }
    return abs(goal - value) < 0.5 ? Color.onyx.good : Color.onyx.textPrimary
  }
}

/// Large · three registers, not the Medium stretched.
///
/// The old Macros Large was `CalorieDayFace` — byte for byte the Calories Large,
/// because the Large branch never read the focus at all. This one answers the
/// macro question at three resolutions: how much is left, what the day was MADE
/// of, and what else is going on.
struct MacroLargeFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private func tint(_ c: Color) -> Color { mono ? .white : c }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Register(title: "TODAY'S FUEL", accent: tint(OnyxDomain.fuel.accent)) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          BigValue(value: s?.caloriesRemaining.map { "\($0)" }, size: 32, color: Color.onyx.textPrimary)
          Text("kcal left").font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
          Spacer(minLength: 0)
          if entry.isStale { StaleTag(age: entry.age) }
          BatteryRing(pct: s?.battery, size: 38, lineWidth: 5, monochrome: mono)
        }
        Rail(progress: OnyxSnapshot.progress(s?.macros.kcal, s?.macros.kcalGoal),
             color: tint(OnyxDomain.fuel.accent))
      }

      Hairline()

      Register(title: "MACRONUTRIENTS", accent: tint(OnyxDomain.fuel.accent)) {
        VStack(spacing: 6) {
          MacroRail(label: "P", value: s?.macros.proteinG, goal: s?.macros.proteinGoalG,
                    color: tint(Color.onyx.protein))
          MacroRail(label: "C", value: s?.macros.carbsG, goal: s?.macros.carbsGoalG,
                    color: tint(Color.onyx.carbs))
          MacroRail(label: "F", value: s?.macros.fatG, goal: s?.macros.fatGoalG,
                    color: tint(Color.onyx.fat))
        }
      }

      Hairline()

      // ── WHY AN ENERGY SPLIT AND NOT A SECOND SET OF BARS ────────────────────
      // The rails above answer "how close to each target". This answers a
      // different question — what the day was actually BUILT from — using the
      // Atwater factors the app already assumes: 4 kcal a gram for protein and
      // carbohydrate, 9 for fat. Same numbers, genuinely different reading, which
      // is what a third register has to earn its height with.
      Register(title: "WHERE THE ENERGY CAME FROM", accent: tint(OnyxDomain.fuel.end)) {
        EnergySplit(entry: entry, mono: mono)
      }

      Spacer(minLength: 0)

      Hairline()

      HStack(spacing: 0) {
        Foot(label: "WATER", value: s?.water.ml.map { String(format: "%.1f L", $0 / 1000) },
             color: tint(Color.onyx.water))
        Foot(label: "STEPS", value: s?.steps.count.map { "\($0)" }, color: tint(OnyxDomain.body.accent))
        Foot(label: "SLEEP", value: sleepText, color: Color.onyx.textPrimary)
      }
    }
  }

  private var sleepText: String? {
    guard let m = s?.sleep.minutes, m > 0 else { return nil }
    return OnyxSnapshot.formatSleep(m)
  }
}

/// The day's calories, split by which macro supplied them.
///
/// Absent when any of the three is missing: a "split" computed from two of three
/// macros would show carbohydrate at 100% of a day that also had fat in it, and
/// a share that adds to less than the whole is the most confidently wrong shape
/// a chart can take.
private struct EnergySplit: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }

  private var parts: [(String, Double, Color)]? {
    guard let p = s?.macros.proteinG, let c = s?.macros.carbsG, let f = s?.macros.fatG else { return nil }
    let kcal = [p * 4, c * 4, f * 9]
    guard kcal.reduce(0, +) > 0 else { return nil }
    return [
      ("PROTEIN", kcal[0], mono ? .white : Color.onyx.protein),
      ("CARBS", kcal[1], mono ? .white : Color.onyx.carbs),
      ("FAT", kcal[2], mono ? .white : Color.onyx.fat),
    ]
  }

  var body: some View {
    if let parts {
      let total = parts.reduce(0) { $0 + $1.1 }
      VStack(alignment: .leading, spacing: 5) {
        GeometryReader { geo in
          HStack(spacing: 1) {
            ForEach(parts, id: \.0) { _, kcal, color in
              Rectangle().fill(color)
                .frame(width: max(1, geo.size.width * CGFloat(kcal / total)))
            }
          }
          .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .frame(height: 10)

        HStack(spacing: 0) {
          ForEach(parts, id: \.0) { name, kcal, color in
            HStack(spacing: 3) {
              Circle().fill(color).frame(width: 5, height: 5)
              Text("\(name) \(Int((kcal / total * 100).rounded()))%")
                .font(OnyxWidgetType.face(8, weight: .bold)).foregroundStyle(Color.onyx.textSecondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    } else {
      Text("logged protein, carbs and fat all three\nand the split appears here")
        .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
    }
  }
}

/// One macro: an initial, a 3pt rail, and `128 / 165 g` in a tabular face.
///
/// The figures are the point — a rail alone says "most of the way" for anything
/// between 70 and 95 percent, and the difference between those two is a meal.
private struct MacroRail: View {
  let label: String
  let value: Double?
  let goal: Double?
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Text(label)
          .font(OnyxWidgetType.face(8, weight: .bold, design: .rounded))
          .foregroundStyle(color)
        Spacer(minLength: 0)
        Text(figures)
          .font(OnyxWidgetType.face(9, weight: .medium, design: .monospaced))
          .foregroundStyle(Color.onyx.textSecondary)
          .lineLimit(1)
      }
      Rail(progress: OnyxSnapshot.progress(value, goal), color: color, height: 3)
    }
  }

  /// "37 g left", "met", "+12 g over" — the remainder, which is the only part
  /// of "128 / 165 g" anybody was going to act on (W6). Nobody eats a ratio.
  ///
  /// The rail still carries the proportion, so the fraction is not lost; what
  /// changes is which of the two is spelled in digits.
  private var figures: String { MacroRemainder.text(value, goal) ?? "—" }
}

/// The one place the "what is left" wording is decided.
///
/// ── WHY IT IS A FREE FUNCTION AND NOT THREE COPIES ───────────────────────────
/// Four faces print a macro remainder — the Fuel Small's sub-line, the Ledger's
/// three rails, the Large's three chips and the Macros Medium's own column —
/// and before W6 three of them printed `128 / 165 g` instead, which is the
/// subtraction handed back to the reader. One rule means the Small and the
/// Large cannot come to disagree about what "met" means.
enum MacroRemainder {
  /// Nil when there is no goal: there is nothing to be left OF, and a bare
  /// intake figure dressed as a remainder is the worst of both.
  static func text(_ value: Double?, _ goal: Double?) -> String? {
    guard let goal else { return nil }
    guard let value else { return "\(Int(goal.rounded())) g left" }
    let gap = goal - value
    if abs(gap) < 0.5 { return "met" }
    return gap > 0 ? "\(Int(gap.rounded())) g left" : "+\(Int((-gap).rounded())) g over"
  }
}

// MARK: - Water (Large)
//
// Was `CalorieDayFace` — the Calories Large again, under a "Water" label. Hydration
// leads here, and the registers under it are the rest of the MOVEMENT day, not
// the nutrition one: picking Water and being shown protein was the complaint.

struct WaterLargeFace: View {
  let entry: OnyxTileEntry
  let mono: Bool
  @Environment(\.onyxWaterButton) private var button

  private var s: OnyxSnapshot? { entry.snapshot }
  private func tint(_ c: Color) -> Color { mono ? .white : c }
  private var counts: (total: Int, filled: Int)? {
    GlassArc.segments(ml: s?.water.ml, goalMl: s?.water.goalMl)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Register(title: "HYDRATION", accent: tint(Color.onyx.water)) {
        HStack(spacing: 12) {
          ZStack {
            GlassArc(ml: s?.water.ml, goalMl: s?.water.goalMl,
                     tint: Color.onyx.water, lineWidth: 10, monochrome: mono)
            VStack(spacing: 0) {
              BigValue(value: counts.map { "\($0.filled)" }, size: 28, color: Color.onyx.textPrimary)
              Text(counts.map { "of \($0.total)" } ?? "glasses")
                .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
            }
          }
          .frame(width: 92, height: 92)

          VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
              Text(litresText(s) ?? "—")
                .font(OnyxWidgetType.face(16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.onyx.textPrimary)
                .lineLimit(1)
              Spacer(minLength: 0)
              if entry.isStale { StaleTag(age: entry.age) }
            }
            if let left = litresLeft {
              Text(left).font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
            }
            Spacer(minLength: 0)
            if let button { button.make() }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      Hairline()

      Register(title: "THE DAY", accent: tint(OnyxDomain.body.accent)) {
        VStack(spacing: 8) {
          Gauge(label: "STEPS", value: s?.steps.count.map { "\($0)" }, unit: "",
                progress: OnyxSnapshot.progress(
                  s?.steps.count.map(Double.init), s?.steps.goal.map(Double.init)),
                color: tint(OnyxDomain.body.accent))
          Gauge(label: "MOVE", value: s?.steps.activeKcal.map { "\(Int($0.rounded()))" }, unit: "kcal",
                progress: nil, color: Color.onyx.textPrimary)
          Gauge(label: "SLEEP", value: sleepText, unit: "",
                progress: OnyxSnapshot.progress(
                  s?.sleep.minutes.map(Double.init),
                  s?.sleep.goalMin.map(Double.init) ?? 480),
                color: tint(OnyxDomain.recover.accent))
        }
      }

      Hairline()

      WeekColumns(entry: entry, mono: mono)
        .frame(maxHeight: .infinity)
    }
  }

  /// "0.6 L to go", or "goal met". Never a negative litre count.
  private var litresLeft: String? {
    guard let ml = s?.water.ml, let goal = s?.water.goalMl, goal > 0 else { return nil }
    let gap = goal - ml
    return gap <= 0 ? "goal met" : String(format: "%.1f L to go", gap / 1000)
  }

  private var sleepText: String? {
    guard let m = s?.sleep.minutes, m > 0 else { return nil }
    return OnyxSnapshot.formatSleep(m)
  }
}

// MARK: - Recovery · the charge
//
// ── WHY THE SCORE NEEDED A FIGURE AT ALL ─────────────────────────────────────
// The Recovery tile printed a numeral, a rail, and "recovery lowest · 71" — a
// number, a proportion of it, and a diagnosis, three claims of equal weight
// with nothing saying which one to read first. And the diagnosis was the
// weakest of the five sub-scores, which on a good day names a part that is
// perfectly fine.
//
// `ChargeArc` carries the number and one more fact the tile already had and
// never drew: WHEN the charge went on. The state word under it is the app's own
// verdict (`readiness.label`, resolved server-side and carried whole), not a
// second grading of the same five components.

/// The state word, and only the state word.
///
/// `readiness.label` when the payload has one — the same sentence the app
/// prints, so two surfaces cannot disagree about what a 71 means. Nil rather
/// than a word invented from the score: "Ready to train" is a verdict with a
/// rule behind it, and a face guessing one from a numeral is a second rule.
func recoveryWord(_ s: OnyxSnapshot?) -> String? {
  guard let label = s?.readiness?.label, !label.isEmpty else { return nil }
  return label
}

/// "charged from 23:41", or nothing at all. A charge with no start is still a
/// charge; it is the caption that must not claim one.
func chargeCaption(_ s: OnyxSnapshot?) -> String? {
  OnyxSnapshot.clockTime(s?.sleep.startTime).map { "charged from \($0)" }
}

/// The watch was off the wrist and readiness lost a signal to it (App Store
/// W6). Every readiness face either shows the reading or says this — a verdict
/// built from four signals must not look like one built from five.
func offWristNote(_ s: OnyxSnapshot?) -> OffWristNote? { s?.readiness?.offWrist }

/// A watch with a slash, beside the caption, on the face too small for words.
struct OffWristMark: View {
  let note: OffWristNote
  var body: some View {
    Image(systemName: "applewatch.slash")
      .font(OnyxWidgetType.face(9, weight: .semibold))
      .foregroundStyle(Color.onyx.textSecondary)
      .accessibilityLabel(note.sentence)
  }
}

/// Small · the ring, the numeral, the word.
struct RecoveryChargeFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var accent: Color { mono ? .white : OnyxDomain.recover.accent }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Caption("RECOVERY", color: accent)
        // Beside the caption, not in the trailing corner: the corner is the
        // Onyx mark's, and the first shot drew the two on top of each other.
        if let note = offWristNote(s) { OffWristMark(note: note) }
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }
      ZStack {
        ChargeArc(fraction: s?.score.map { min(1, max(0, Double($0) / 100)) },
                  startClock: OnyxSnapshot.clockTime(s?.sleep.startTime),
                  tint: OnyxDomain.recover.accent, lineWidth: 10, monochrome: mono)
        BigValue(value: s?.score.map { "\($0)" }, size: 30, color: Color.onyx.textPrimary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      Text(recoveryWord(s) ?? "no verdict yet")
        .font(OnyxWidgetType.face(11, weight: .bold))
        .foregroundStyle(recoveryWord(s) == nil ? Color.onyx.textSecondary : accent)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
  }
}

// MARK: - C8 · Wellbeing
//
// The composite score is one number standing on five, and the five are what you
// can actually act on — a 62 tells you nothing about whether to sleep earlier or
// eat more. The readiness verdict underneath is `computeReadiness`'s own words,
// carried through the payload rather than re-derived here: two implementations
// of one grade is how they come to disagree.

/// The five sub-scores, in the order the app lists them.
private func wellbeingParts(_ s: OnyxSnapshot?, mono: Bool) -> [(String, Double?, Color)] {
  func tint(_ c: Color) -> Color { mono ? .white : c }
  let sc = s?.scores
  return [
    ("SLEEP", sc?.sleep, tint(OnyxDomain.recover.at(0))),
    ("NUTRITION", sc?.nutrition, tint(OnyxDomain.fuel.accent)),
    ("ACTIVITY", sc?.activity, tint(OnyxDomain.body.accent)),
    ("WORKOUT", sc?.workout, tint(OnyxDomain.train.accent)),
    ("RECOVERY", sc?.recovery, tint(OnyxDomain.recover.at(0.6))),
  ]
}

/// Medium · its own layout, not the Large shrunk.
///
/// ── WHY THE BARS RAN OFF THE EDGE ────────────────────────────────────────────
/// The Large's rows are a 62pt label frame, then a rail, then a 22pt value —
/// about 100pt of fixed width before the bar gets any. In a Large that leaves
/// plenty; in a Medium it leaves the rail almost nothing and pushed the battery
/// ring past the trailing edge. So the Medium puts the score and the ring in a
/// fixed left column and gives the rails the whole of what remains, with the
/// labels shortened to fit rather than the bars shortened to make room.
struct WellbeingLedgerFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }

  var body: some View {
    HStack(spacing: 12) {
      // ── ONE GAUGE, NOT TWO (W6) ──────────────────────────────────────────
      // This column held a 34 pt numeral AND a battery ring, which is two
      // circles' worth of claim about the same morning: the score is what the
      // day graded and the battery is what is left of it, and a reader at a
      // glance cannot tell which of the two the tile is about. The arc is the
      // score, and the battery moves into the rails beside it where it is one
      // reading among five rather than a second hero.
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 4) {
          Caption("RECOVERY", color: mono ? .white : OnyxDomain.recover.accent)
          if entry.isStale { StaleTag(age: entry.age) }
        }
        ZStack {
          ChargeArc(fraction: s?.score.map { min(1, max(0, Double($0) / 100)) },
                    startClock: OnyxSnapshot.clockTime(s?.sleep.startTime),
                    tint: OnyxDomain.recover.accent, lineWidth: 9, monochrome: mono)
          BigValue(value: s?.score.map { "\($0)" }, size: 26, color: Color.onyx.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // W6: the off-wrist line takes the charge caption's place — a
        // bedtime the watch never saw is the one caption this face cannot
        // truthfully print.
        Text(offWristNote(s)?.short ?? chargeCaption(s) ?? "no bedtime logged")
          .font(OnyxWidgetType.face(8)).foregroundStyle(Color.onyx.textSecondary)
          .lineLimit(1).minimumScaleFactor(0.7)
          .accessibilityLabel(offWristNote(s)?.sentence ?? chargeCaption(s) ?? "no bedtime logged")
      }
      .frame(width: 92, alignment: .leading)

      Hairline(vertical: true)

      VStack(spacing: 6) {
        ForEach(wellbeingParts(s, mono: mono), id: \.0) { name, value, color in
          HStack(spacing: 6) {
            // ── THE WORD, NOT THE FIRST FOUR LETTERS ──────────────────────
            // This was `name.prefix(4)` in a 30 pt column, which rendered the
            // five sub-scores as SLEE · NUTR · ACTI · WORK · RECO. A truncated
            // label is not a shorter label, it is a different word: "ACTI" and
            // "RECO" are not readable as activity and recovery at a glance, and
            // a glance is the entire budget a widget gets.
            //
            // So the label column is sized for the longest word in the set
            // (NUTRITION) and the RAIL gives the width up — it is the one
            // elastic thing in the row and the only one that loses nothing by
            // being shorter, because a proportion reads the same at any length.
            // Fixed, not intrinsic: every rail must start on the same line, and
            // five labels sized to themselves is five different start points.
            //
            // `minimumScaleFactor` rather than a wider column, for the word
            // that eventually will not fit: shrinking is legible and truncation
            // is not, and the column keeps its width either way.
            Text(name)
              .font(OnyxWidgetType.face(8, weight: .bold))
              .foregroundStyle(Color.onyx.textSecondary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .frame(width: 52, alignment: .leading)
            Rail(progress: value.map { min(1, max(0, $0 / 100)) }, color: color, height: 4)
            Text(value.map { "\(Int($0.rounded()))" } ?? "—")
              .font(OnyxWidgetType.face(9, weight: .semibold, design: .monospaced))
              .foregroundStyle(Color.onyx.textPrimary)
              .frame(width: 20, alignment: .trailing)
          }
        }
        HStack(spacing: 6) {
          Text(recoveryWord(s) ?? "no verdict yet")
            .font(OnyxWidgetType.face(10, weight: .bold))
            .foregroundStyle(recoveryWord(s) == nil ? Color.onyx.textSecondary : (mono ? .white : OnyxDomain.recover.accent))
            .lineLimit(1).minimumScaleFactor(0.8)
          Spacer(minLength: 0)
          if let battery = s?.battery {
            Text("\(battery)%")
              .font(OnyxWidgetType.figure(10))
              .foregroundStyle(mono ? .white : Color.onyx.battery(battery))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity)
    }
  }
}

struct WellbeingFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private func tint(_ c: Color) -> Color { mono ? .white : c }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Caption("RECOVERY", color: tint(OnyxDomain.recover.accent))
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }
      // The corner belongs to the mark; this row's content runs to the edge.
      .padding(.trailing, OnyxMark.faceInset)

      // One gauge, for the reason the Medium gives above. The battery keeps its
      // reading — as a figure beside the word, where it does not compete with
      // the arc for the eye.
      HStack(spacing: 14) {
        ZStack {
          ChargeArc(fraction: s?.score.map { min(1, max(0, Double($0) / 100)) },
                    startClock: OnyxSnapshot.clockTime(s?.sleep.startTime),
                    tint: OnyxDomain.recover.accent, lineWidth: 11, monochrome: mono)
          BigValue(value: s?.score.map { "\($0)" }, size: 30, color: Color.onyx.textPrimary)
        }
        .frame(width: 86, height: 86)

        VStack(alignment: .leading, spacing: 4) {
          Text(recoveryWord(s) ?? "no verdict yet")
            .font(OnyxWidgetType.face(15, weight: .bold))
            .foregroundStyle(recoveryWord(s) == nil ? Color.onyx.textSecondary : tint(OnyxDomain.recover.accent))
            .lineLimit(2).minimumScaleFactor(0.8)
          if let caption = chargeCaption(s) {
            Text(caption).font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
          }
          if let battery = s?.battery {
            HStack(spacing: 4) {
              Text("\(battery)")
                .font(OnyxWidgetType.figure(13))
                .foregroundStyle(mono ? .white : Color.onyx.battery(battery))
              Text("% battery").font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
            }
          }
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      // The row is the height of its gauge and no more. Without this the text
      // column's trailing `Spacer` collects every point the rails below it did
      // not want, and the hero sat over an inch of obsidian.
      .frame(height: 86)

      Hairline()

      // The rails take the slack instead of a trailing Spacer collecting it all
      // at the bottom, which is what left this face with an inch of air under a
      // three-line verdict.
      VStack(spacing: 7) {
        ForEach(wellbeingParts(s, mono: mono), id: \.0) { name, value, color in
          HStack(spacing: 8) {
            Text(name)
              .font(OnyxWidgetType.face(8, weight: .bold))
              .foregroundStyle(Color.onyx.textSecondary)
              // Same rule as the Medium: one alignment line for every rail,
              // and a word that outgrows the column shrinks rather than losing
              // its ending.
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .frame(width: 62, alignment: .leading)
            Rail(progress: value.map { min(1, max(0, $0 / 100)) }, color: color, height: 4)
            Text(value.map { "\(Int($0.rounded()))" } ?? "—")
              .font(OnyxWidgetType.face(10, weight: .semibold, design: .monospaced))
              .foregroundStyle(Color.onyx.textPrimary)
              .frame(width: 22, alignment: .trailing)
          }
          .frame(maxHeight: .infinity)
        }
      }
      .frame(maxHeight: .infinity)

      Hairline()

      if let readiness = s?.readiness {
        // The label is the hero's own word now; repeating it here would be the
        // same verdict twice on one face. What a Large owes over a Medium is
        // the REASON, which nothing else on the tile says — and when the watch
        // was off the wrist (W6), the reason is that it was built from fewer
        // signals than it would have been.
        Text(readiness.offWrist?.sentence ?? readiness.reason)
          .font(OnyxWidgetType.face(10))
          .foregroundStyle(Color.onyx.textSecondary)
          .lineLimit(2)
          .minimumScaleFactor(0.85)
      } else {
        // The verdict needs a battery to weigh against, so its absence is a real
        // state rather than an error — and saying so is better than a gap where
        // a sentence was yesterday.
        Text("today's verdict appears once the battery has a reading")
          .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
      }
    }
  }
}

#endif
