// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import WidgetKit
import SwiftUI
import OnyxCore

// MARK: - Onyx Lock
//
// The accessory families: Lock Screen and Smart Stack. Previously one static
// kind that could only ever show the battery — so the surface with the least
// room was the only one with no choice about what went in it, which is exactly
// backwards.
//
// ── WHY THESE FACES ARE NOT SMALL WIDGETS SHRUNK ─────────────────────────────
// An accessory has no background and renders in `.accented` or `.vibrant`: the
// system flattens everything to one tint, so colour carries NO information here
// and any face that leans on it loses its meaning. What survives is shape (the
// gauge), one glyph, and one number — which is why each focus is a single fact
// and none of them is a ledger.

public struct LockView: View {
  let entry: OnyxTileEntry
  let focus: LockFocus
  @Environment(\.widgetFamily) private var hostFamily
  @Environment(\.onyxTileFamily) private var tileFamily
  /// `widgetFamily` is get-only outside WidgetKit, so the app's grid says which
  /// size it wants through `onyxTileFamily`; on the Home Screen it is unset.
  private var family: WidgetFamily { tileFamily ?? hostFamily }

  public init(entry: OnyxTileEntry, focus: LockFocus) {
    self.entry = entry
    self.focus = focus
  }
  @Environment(\.widgetRenderingMode) private var mode

  private var s: OnyxSnapshot? { entry.snapshot }

  public var body: some View {
    Group {
      switch family {
      case .accessoryInline: inlineFace
      case .accessoryRectangular: rectangularFace
      default: circularFace
      }
    }
    // `.clear`, not the widget background: an accessory sits on the wallpaper
    // and painting obsidian behind it draws a black rectangle on the Lock Screen.
    .containerBackground(.clear, for: .widget)
    .widgetURL(focus.link(entry.snapshot?.date))
  }

  // MARK: Circular

  /// A gauge for anything with a goal; a glyph and a number for anything without.
  @ViewBuilder private var circularFace: some View {
    switch focus {
    case .battery:
      Gauge(value: Double(s?.battery ?? 0), in: 0...100) {
        Image(systemName: "bolt.fill")
      } currentValueLabel: {
        // Still an em dash when unknown — the gauge sits at zero because it has
        // to sit somewhere, but the NUMBER never lies about it.
        Text(s?.battery.map { "\($0)" } ?? "—")
      }
      .gaugeStyle(.accessoryCircular)
      .tint(mode == .fullColor ? Color.onyx.battery(s?.battery) : nil)

    case .calories:
      Gauge(value: OnyxSnapshot.progress(s?.macros.kcal, s?.macros.kcalGoal) ?? 0, in: 0...1) {
        Image(systemName: "flame.fill")
      } currentValueLabel: {
        Text(s?.caloriesRemaining.map { "\($0)" } ?? "—")
          .minimumScaleFactor(0.6)
      }
      .gaugeStyle(.accessoryCircular)
      .tint(mode == .fullColor ? OnyxDomain.fuel.accent : nil)

    case .steps:
      Gauge(value: OnyxSnapshot.progress(
        s?.steps.count.map(Double.init), s?.steps.goal.map(Double.init)) ?? 0, in: 0...1) {
        Image(systemName: "figure.walk")
      } currentValueLabel: {
        // Thousands, because five digits inside a 40pt ring is a smudge.
        Text(s?.steps.count.map { "\($0 / 1000)k" } ?? "—")
          .minimumScaleFactor(0.6)
      }
      .gaugeStyle(.accessoryCircular)
      .tint(mode == .fullColor ? OnyxDomain.body.accent : nil)

    case .workout:
      // No goal to fill, so no gauge — a ring at an arbitrary fraction would be
      // decoration claiming to be a measurement.
      VStack(spacing: 1) {
        Image(systemName: workoutGlyph).font(OnyxWidgetType.face(15, weight: .semibold))
        Text(shortLabel).font(OnyxWidgetType.face(9, weight: .semibold)).lineLimit(1)
      }

    case .bedtime:
      // A clock time has no goal either. The glyph and the time, like Workout.
      VStack(spacing: 1) {
        Image(systemName: "bed.double.fill").font(OnyxWidgetType.face(14, weight: .semibold))
        Text(bedtime).font(OnyxWidgetType.figure(10)).lineLimit(1).minimumScaleFactor(0.7)
      }
    }
  }

  // MARK: Rectangular

  /// Two lines and a glyph. The one accessory family with room for a sentence,
  /// so it is the one that says what today actually is.
  private var rectangularFace: some View {
    HStack(spacing: 6) {
      Image(systemName: workoutGlyph)
        .font(OnyxWidgetType.face(14, weight: .semibold))
      VStack(alignment: .leading, spacing: 1) {
        Text(s?.workout.label ?? "—")
          .font(OnyxWidgetType.face(13, weight: .semibold))
          .lineLimit(1)
        Text(rectangularSub)
          .font(OnyxWidgetType.face(11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
  }

  /// The session's state, then the fact the FOCUS asked for.
  ///
  /// ── WHY THIS READS `focus` AT ALL ───────────────────────────────────────
  /// It did not, and this was the only family that ignored it: all four gallery
  /// options — Battery, Calories, Steps, Workout — drew the identical
  /// "Delts & Arms / due · battery 72%", so choosing Calories silently gave you
  /// the battery. The circular and inline faces both branch on `focus`; this
  /// one had a fixed fallback chain that happened to end at the battery.
  ///
  /// The headline stays the session (that is this family's whole reason to
  /// exist — it is the one accessory with room for a sentence), so it is the
  /// SUB-line that carries the chosen number.
  private var rectangularSub: String {
    let state: String
    if s?.workout.isRestDay == true {
      state = "rest day"
    } else if let today = s?.today {
      state = "done · \(OnyxSnapshot.tonnes(today.volumeKg) ?? "—")"
    } else {
      state = "due"
    }
    switch focus {
    case .workout:
      return state
    case .battery:
      guard let battery = s?.battery else { return state }
      return "\(state) · battery \(battery)%"
    case .calories:
      guard let kcal = s?.caloriesRemaining else { return state }
      return "\(state) · \(kcal) kcal left"
    case .steps:
      guard let steps = s?.steps.count else { return state }
      return "\(state) · \(steps) steps"
    case .bedtime:
      guard let bed = OnyxSnapshot.clockTime(s?.sleep.startTime) else { return state }
      return "\(state) · bed \(bed)"
    }
  }

  // MARK: Inline

  /// One line beside the clock. Whatever the focus is, said in four words.
  private var inlineFace: some View {
    switch focus {
    case .battery:
      return Text("Battery \(s?.battery.map { "\($0)%" } ?? "—")")
    case .calories:
      return Text("\(s?.caloriesRemaining.map { "\($0)" } ?? "—") kcal left")
    case .steps:
      return Text("\(s?.steps.count.map { "\($0)" } ?? "—") steps")
    case .workout:
      return Text(s?.workout.label ?? "—")
    case .bedtime:
      return Text("Bed \(bedtime)")
    }
  }

  // MARK: Shared

  /// Last night's bedtime in the DEVICE's zone (`clockTime`), or the dash.
  private var bedtime: String { OnyxSnapshot.clockTime(s?.sleep.startTime) ?? "—" }

  private var workoutGlyph: String {
    if s?.workout.isRestDay == true { return "moon.zzz.fill" }
    return s?.today != nil ? "checkmark.circle.fill" : "dumbbell.fill"
  }

  /// The day label trimmed to something that fits a 40pt ring — "Legs & Core B"
  /// becomes "Legs", because a truncated word reads as a bug and a first word
  /// reads as a category.
  private var shortLabel: String {
    guard let label = s?.workout.label, !label.isEmpty else { return "—" }
    if s?.workout.isRestDay == true { return "Rest" }
    return String(label.split(separator: " ").first ?? "—")
  }
}

#endif
