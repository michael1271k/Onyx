// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import WidgetKit
import SwiftUI
import OnyxCore

// MARK: - Onyx Daily
//
// The one genuinely new KIND in this wave, and the only ask that earned one.
//
// ── WHY CARDIO AND COMPOSITION ARE FOCUSES AND THIS IS NOT ───────────────────
// A kind costs a gallery entry, a provider generic, an intent and a scope
// decision. Cardio is training and composition is body, so both belong in a
// picker a user is already going to open. This one is not any family's
// question — it is "how is the whole day going", spanning fuel, hydration,
// movement and training at once, and there is no existing picker it fits into.
//
// ⚠️ ADDING a kind is safe. It is REMOVING one that wipes every placed instance
// off the Home Screen (see the warning in OnyxWidgets.swift) — which is why
// the six family kinds spent a full release as shells before W12 deleted them,
// and why there is exactly one Home Screen kind now.
//
// ── LARGE ONLY, DELIBERATELY ─────────────────────────────────────────────────
// Four registers in a 2×2 is four quadrants. At Medium each would be about 70pt
// wide and 30pt tall — a caption and a truncated number, four times over, which
// is worse at answering any one of the four questions than the single-focus
// widget that already exists for it. A composite that cannot hold its parts
// legibly is not a composite, it is a cluttered Small.

// This face reached the Home Screen through its own kind ("OnyxDailyFamily",
// `.systemLarge` only) until W12 deleted the six family shells. It is drawn by
// `OnyxTileWidget` now, like every other tile, through `OnyxTile.face` —
// `WidgetId.daily`, which is why that id is last in the catalogue.

public struct DailyView: View {
  let entry: OnyxTileEntry
  @Environment(\.widgetRenderingMode) private var mode

  public init(entry: OnyxTileEntry) { self.entry = entry }

  private var mono: Bool { mode == .accented }
  private var s: OnyxSnapshot? { entry.snapshot }

  public var body: some View {
    Group {
      if entry.isEmpty {
        Unavailable()
      } else {
        face
      }
    }
    .onyxMarked(monochrome: mono, hidden: entry.isStale)
    .containerBackground(Color.onyx.base, for: .widget)
    // The whole-face URL is the home screen: this widget is about the day, and
    // the day's overview is the dashboard. Each quadrant then names its own
    // destination below, which is what makes the four taps worth having.
    .widgetURL(OnyxLink.home)
  }

  private var face: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 5) {
        Caption("TODAY", color: mono ? .white : OnyxDomain.train.accent)
        // Before the spacer: a declared day is a fact ABOUT today, so it reads
        // as part of the title rather than as another badge on the right.
        ContextChip(context: s?.context, monochrome: mono)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      // 2×2. Each cell is a Link, so a tap lands on the thing tapped rather
      // than on the dashboard — the whole reason this is four registers and not
      // one list.
      VStack(spacing: 8) {
        HStack(alignment: .top, spacing: 10) {
          quadrant(OnyxLink.nutrition) { FuelQuadrant(snapshot: s, mono: mono) }
          // `s?.date` is NOT an optional chain onto an optional `date` — the
          // chain belongs to `s`, and `OnyxSnapshot.date` is a plain `String`.
          // Writing `s?.date.flatMap { … }` therefore calls SEQUENCE's flatMap
          // over the string's Characters and yields `[URL]?`. `OnyxLink.day`
          // already treats an empty ISO as no destination, so the coalesce
          // happens on the argument and the optionality stays where it belongs.
          quadrant(OnyxLink.day(s?.date ?? "", section: "water") ?? OnyxLink.nutrition) {
            WaterQuadrant(snapshot: s, mono: mono)
          }
        }
        Hairline()
        HStack(alignment: .top, spacing: 10) {
          quadrant(OnyxLink.progress) { StepsQuadrant(snapshot: s, mono: mono) }
          quadrant(OnyxLink.workout) { TrainingQuadrant(snapshot: s, mono: mono) }
        }
      }
      .frame(maxHeight: .infinity)

      Hairline()

      HStack(spacing: 0) {
        Stat(value: s?.score.map { "\($0)" }, label: "SCORE", color: Color.onyx.textPrimary)
        Stat(value: s?.battery.map { "\($0)%" }, label: "BATTERY",
             color: mono ? .white : Color.onyx.battery(s?.battery))
        Stat(value: s?.streak.map { "\($0.current)" }, label: "PROGRAM DAY",
             color: mono ? .white : OnyxDomain.train.accent)
      }
    }
  }

  /// A cell, linked if the destination resolved. A nil URL must still render —
  /// a placeholder entry has no date and the widget still has to draw.
  @ViewBuilder
  private func quadrant<Content: View>(_ url: URL?, @ViewBuilder content: @escaping () -> Content) -> some View {
    FaceLink(url) { content().frame(maxWidth: .infinity, alignment: .leading) }
  }
}

// MARK: - Quadrants
//
// Every one of these is built from primitives that already existed. The Daily
// widget adds no new drawing — it is an arrangement, which is the whole reason
// it was cheap enough to be worth adding as a kind.

private struct FuelQuadrant: View {
  let snapshot: OnyxSnapshot?
  let mono: Bool

  private var accent: Color { mono ? .white : Color.onyx.calories }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Caption("FUEL", color: accent)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        BigValue(value: snapshot?.macros.kcal.map { "\(Int($0.rounded()))" }, size: 20, color: Color.onyx.textPrimary)
        Text(snapshot?.macros.kcalGoal.map { "/ \(Int($0.rounded()))" } ?? "kcal")
          .onyxWidgetFont { OnyxWidgetType.face(9 * $0) }.foregroundStyle(Color.onyx.textSecondary)
      }
      // Three micro-rails rather than three numbers: at this size the SHAPE of
      // the macro split is readable where the figures are not.
      HStack(spacing: 3) {
        MacroPip(value: snapshot?.macros.proteinG, goal: snapshot?.macros.proteinGoalG,
                 letter: "P", color: mono ? .white : Color.onyx.protein)
        MacroPip(value: snapshot?.macros.carbsG, goal: snapshot?.macros.carbsGoalG,
                 letter: "C", color: mono ? .white : Color.onyx.carbs)
        MacroPip(value: snapshot?.macros.fatG, goal: snapshot?.macros.fatGoalG,
                 letter: "F", color: mono ? .white : Color.onyx.fat)
      }
    }
  }
}

private struct MacroPip: View {
  let value: Double?
  let goal: Double?
  let letter: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(letter).onyxWidgetFont { OnyxWidgetType.face(7 * $0, weight: .bold) }.foregroundStyle(Color.onyx.textSecondary)
      Rail(progress: OnyxSnapshot.progress(value, goal), color: color, height: 3)
    }
  }
}

private struct WaterQuadrant: View {
  let snapshot: OnyxSnapshot?
  let mono: Bool

  private var accent: Color { mono ? .white : Color.onyx.water }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Caption("WATER", color: accent)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        BigValue(value: snapshot?.water.ml.map { String(format: "%.1f", $0 / 1000) },
                 size: 20, color: Color.onyx.textPrimary)
        Text(snapshot?.water.goalMl.map { "/ \(String(format: "%.1f", $0 / 1000)) L" } ?? "L")
          .onyxWidgetFont { OnyxWidgetType.face(9 * $0) }.foregroundStyle(Color.onyx.textSecondary)
      }
      Rail(progress: OnyxSnapshot.progress(snapshot?.water.ml, snapshot?.water.goalMl),
           color: accent, height: 4)
      Spacer(minLength: 0)
    }
  }
}

private struct StepsQuadrant: View {
  let snapshot: OnyxSnapshot?
  let mono: Bool

  private var accent: Color { mono ? .white : OnyxDomain.body.accent }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Caption("STEPS", color: accent)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        BigValue(value: snapshot?.steps.count.map { $0.formatted(.number.grouping(.automatic)) },
                 size: 20, color: Color.onyx.textPrimary)
        Text(snapshot?.steps.goal.map { "/ \($0 / 1000)k" } ?? "")
          .onyxWidgetFont { OnyxWidgetType.face(9 * $0) }.foregroundStyle(Color.onyx.textSecondary)
      }
      Rail(progress: OnyxSnapshot.progress(snapshot?.steps.count.map(Double.init),
                                            snapshot?.steps.goal.map(Double.init)),
           color: accent, height: 4)
      Spacer(minLength: 0)
    }
  }
}

private struct TrainingQuadrant: View {
  let snapshot: OnyxSnapshot?
  let mono: Bool

  private var accent: Color { mono ? .white : Color.onyx.day(snapshot?.workout.dayKey) }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Caption("TRAINING", color: accent)
      Text(snapshot?.workout.label ?? "—")
        .onyxWidgetFont { OnyxWidgetType.label(13 * $0, weight: .bold) }
        .foregroundStyle(Color.onyx.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(state)
        .onyxWidgetFont { OnyxWidgetType.face(9 * $0) }.foregroundStyle(Color.onyx.textSecondary).lineLimit(1)
      Spacer(minLength: 0)
    }
  }

  /// Done says what was done; due says how much there is; rest says what it is
  /// for. Never "not logged yet", which is the sentence this wave removed from
  /// every other face for saying nothing you can act on.
  private var state: String {
    guard let s = snapshot else { return "—" }
    if s.workout.isRestDay { return "recovery" }
    if let done = s.today {
      let volume = OnyxSnapshot.tonnes(done.volumeKg)
      return volume.map { "done · \($0)" } ?? "done"
    }
    if let exercises = s.workout.plannedExercises, let sets = s.workout.plannedSets {
      return "due · \(exercises) ex · \(sets) sets"
    }
    return "due"
  }
}

#endif
