// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import WidgetKit
import SwiftUI
import OnyxCore

// MARK: - Cardio
//
// A seventh `TrainingFocus` rather than a fifth widget KIND, and the reason is
// where a user would look for it: cardio is training. A kind costs a gallery
// entry, a provider generic, an intent and a scope decision; a focus costs a
// switch case, and the picker is already the place this app answers "which of
// these do you want".
//
// ── ZONE 2 IS A COUNT OF SESSIONS, NOT A PILE OF MINUTES ─────────────────────
// `ZONE2_WEEKLY_TARGET` is 2 and `ZONE2_MIN_MINUTES` is 20: two steady blocks a
// week, on the plan's rest days. The CardioLogger draws one pip per session and
// so does this. Minutes appear too, clearly labelled as minutes, because they
// are useful context — but they are never the thing measured against the target.
// A widget and an app disagreeing about what a word means is how the streak came
// to read 22 on one surface and 32 on the other.

struct CardioFocusFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var c: OnyxSnapshot.Cardio? { s?.cardio }
  private var accent: Color { mono ? .white : OnyxDomain.body.accent }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption("CARDIO", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      if let last = c?.last {
        BigValue(value: CardioFormat.distance(last.distanceM), size: 28, color: Color.onyx.textPrimary)
        Text(CardioFormat.subtitle(last))
          .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary).lineLimit(1)
      } else {
        // Nothing logged is a real state, not an error. It gets a sentence, not
        // a row of em dashes pretending to be a reading.
        BigValue(value: nil, size: 28)
        Text("no cardio logged yet")
          .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary).lineLimit(1)
      }

      Spacer(minLength: 0)
      ZonePips(cardio: c, mono: mono)
    }
  }
}

/// Medium · the week against the target, with the last session under it.
struct CardioLedgerFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var c: OnyxSnapshot.Cardio? { s?.cardio }
  private var accent: Color { mono ? .white : OnyxDomain.body.accent }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 5) {
        Caption("CARDIO", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      HStack(alignment: .firstTextBaseline, spacing: 8) {
        BigValue(
          value: c.map { "\($0.weekSessions)" },
          size: 30,
          color: mono ? .white : zoneColor)
        Text(c.map { "/ \($0.weekTarget) zone 2" } ?? "zone 2")
          .font(OnyxWidgetType.face(11)).foregroundStyle(Color.onyx.textSecondary)
        Spacer(minLength: 0)
        ZonePips(cardio: c, mono: mono)
      }

      Spacer(minLength: 0)
      Hairline()

      HStack(spacing: 0) {
        Stat(value: c.map { "\($0.weekMinutes)′" }, label: "WEEK MINUTES", color: Color.onyx.textPrimary)
        Stat(value: c?.last.flatMap { CardioFormat.distance($0.distanceM) },
             label: "LAST DISTANCE", color: Color.onyx.textPrimary)
        Stat(value: c?.last.flatMap { CardioFormat.pace($0.paceMinPerKm) },
             label: "LAST PACE", color: mono ? .white : Color.onyx.textSecondary)
      }
    }
  }

  /// Green once the week's target is met, gold on the way, muted at nothing.
  /// The same banding the battery uses, for the same reason: this genuinely is
  /// a "how far through" number.
  private var zoneColor: Color {
    guard let c, c.weekTarget > 0 else { return Color.onyx.textSecondary }
    if c.weekSessions >= c.weekTarget { return Color.onyx.good }
    return c.weekSessions > 0 ? OnyxDomain.fuel.accent : Color.onyx.textSecondary
  }
}

/// Large · the week, seven days of it as bars, and the last session named.
struct CardioLargeFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var c: OnyxSnapshot.Cardio? { s?.cardio }
  private var accent: Color { mono ? .white : OnyxDomain.body.accent }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 5) {
        Caption("CARDIO", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      Register(title: "THIS WEEK", accent: mono ? .white : accent) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          BigValue(value: c.map { "\($0.weekSessions)" }, size: 34, color: Color.onyx.textPrimary)
          Text(c.map { "/ \($0.weekTarget) zone 2 sessions" } ?? "zone 2 sessions")
            .font(OnyxWidgetType.face(11)).foregroundStyle(Color.onyx.textSecondary)
          Spacer(minLength: 0)
          ZonePips(cardio: c, mono: mono)
        }
      }

      Hairline()

      Register(title: "SEVEN DAYS · MINUTES", accent: mono ? .white : Color.onyx.textSecondary) {
        if let trend = c?.trend, !trend.isEmpty {
          // Weekday initials read off the DATE, never assumed from position —
          // the series omits days with no cardio, so index N is not "N days ago".
          BarChart(points: trend, color: mono ? .white : accent,
                   label: { OnyxSnapshot.weekdayInitial($0.d) })
            .frame(maxHeight: .infinity)
        } else {
          Text("no cardio in the last week")
            .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
        }
      }
      .frame(maxHeight: .infinity)

      Hairline()

      if let last = c?.last {
        HStack(spacing: 0) {
          Stat(value: last.kind.capitalized, label: "LAST SESSION", color: Color.onyx.textPrimary)
          Stat(value: CardioFormat.distance(last.distanceM), label: "DISTANCE", color: Color.onyx.textPrimary)
          Stat(value: last.durationMin.map { "\(Int($0.rounded()))′" }, label: "TIME", color: Color.onyx.textPrimary)
          Stat(value: CardioFormat.pace(last.paceMinPerKm), label: "PACE",
               color: mono ? .white : Color.onyx.textSecondary)
        }
      } else {
        Text("no cardio logged yet")
          .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
      }
    }
  }
}

/// One pip per Zone-2 session the week asks for, filled as they land.
///
/// The same grammar as the CardioLogger's inline pips, deliberately: two
/// surfaces showing the same fact should not invent two ways to show it. The
/// count comes off the payload, so the widget never hardcodes a target of 2.
private struct ZonePips: View {
  let cardio: OnyxSnapshot.Cardio?
  let mono: Bool

  var body: some View {
    if let cardio, cardio.weekTarget > 0 {
      HStack(spacing: 3) {
        ForEach(0..<max(0, min(cardio.weekTarget, 6)), id: \.self) { i in
          Circle()
            .fill(i < cardio.weekSessions
                  ? (mono ? Color.white : Color.onyx.good)
                  : Color.onyx.hairline)
            .frame(width: 7, height: 7)
        }
        // Sessions BEYOND the target still count as done work. Dropping them
        // would render a strong week identically to an exactly-met one.
        if cardio.weekSessions > cardio.weekTarget {
          Text("+\(cardio.weekSessions - cardio.weekTarget)")
            .font(OnyxWidgetType.figure(9))
            .foregroundStyle(mono ? .white : Color.onyx.good)
        }
      }
    } else {
      EmptyView()
    }
  }
}

/// Formatting that must match the app's, and therefore never invents a rule.
enum CardioFormat {
  /// "5.2 km", or nil. Metres are the storage unit and nobody thinks in them.
  static func distance(_ metres: Double?) -> String? {
    guard let metres, metres > 0 else { return nil }
    return String(format: "%.1f km", metres / 1000)
  }

  /// "5:42 /km", or nil.
  ///
  /// The VALUE is computed server-side by `lib/cardio/metrics.ts` — pace there
  /// is a minimum with a 1 km floor, and re-deriving it from distance and time
  /// here would quietly disagree with every pace the app shows. This only turns
  /// the number into characters.
  static func pace(_ minPerKm: Double?) -> String? {
    guard let minPerKm, minPerKm > 0, minPerKm.isFinite else { return nil }
    let whole = Int(minPerKm)
    let seconds = Int((minPerKm - Double(whole)) * 60).clampedToSecond
    return String(format: "%d:%02d /km", whole, seconds)
  }

  /// "walk · 32′ · 5:42 /km" — whatever of it exists.
  static func subtitle(_ session: OnyxSnapshot.Cardio.Session) -> String {
    var parts: [String] = [session.kind]
    if let minutes = session.durationMin { parts.append("\(Int(minutes.rounded()))′") }
    if let pace = pace(session.paceMinPerKm) { parts.append(pace) }
    return parts.joined(separator: " · ")
  }
}

private extension Int {
  /// Rounding can land on 60, which would render "5:60 /km".
  ///
  /// `Swift.max` in full, because inside an extension on `Int` the bare name
  /// `max` finds the type's own static `Int.max` first and the call fails to
  /// compile — a shadowing that only exists here, inside the extended type.
  var clampedToSecond: Int { self >= 60 ? 59 : Swift.max(0, self) }
}

#endif
