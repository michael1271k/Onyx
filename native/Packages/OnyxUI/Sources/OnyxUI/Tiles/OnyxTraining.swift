// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import WidgetKit
import SwiftUI
import OnyxCore

// MARK: - Onyx Training
//
// Six focuses over three sizes, and — since this file was written — eighteen
// distinct faces rather than eleven faces and seven fallbacks.
//
//   today     what is due, or what you finished
//   calendar  scheduled against logged, tinted by the day's own colour
//   volume    this week's tonnage against last, over eight weeks
//   streak    consecutive SCHEDULED days trained
//   records   the standing record ledger
//   oneRepMax where the main lifts are trending
//
// ── THE THREE THINGS THAT WERE WRONG HERE ────────────────────────────────────
// 1. `case .volume: if family == .systemSmall { StreakFace(…) }` — asking for
//    Volume at Small drew the streak. Not a fallback, not a near-miss: a literal
//    branch to a different focus's face.
// 2. `.records` and `.oneRepMax` both routed Large to `RecordGridFace`, so the
//    1RM Large WAS the Records Large.
// 3. `PerfLedgerFace` took a focus and used it only to pick a LINK, so the
//    Records Medium and the 1RM Medium drew identical content too.
//
// The dispatcher below switches on `(focus, OnyxSize)` and is exhaustive with
// no `default:`. Adding a focus without a face is now a build error.

public struct TrainingView: View {
  let entry: OnyxTileEntry
  let focus: TrainingFocus
  @Environment(\.widgetFamily) private var hostFamily
  @Environment(\.onyxTileFamily) private var tileFamily
  /// `widgetFamily` is get-only outside WidgetKit, so the app's grid says which
  /// size it wants through `onyxTileFamily`; on the Home Screen it is unset.
  private var family: WidgetFamily { tileFamily ?? hostFamily }

  public init(entry: OnyxTileEntry, focus: TrainingFocus) {
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

  @ViewBuilder private var face: some View {
    switch (focus, OnyxSize(family)) {
    case (.today, .small):      TodayFace(entry: entry, mono: mono, compact: true)
    case (.today, .medium):     TodayFace(entry: entry, mono: mono, compact: false)
    case (.today, .large):      TodayLargeFace(entry: entry, mono: mono)

    case (.calendar, .small):   CalendarFace(entry: entry, mono: mono, weeks: 6, compact: true)
    case (.calendar, .medium):  CalendarFace(entry: entry, mono: mono, weeks: 4)
    case (.calendar, .large):   CalendarFace(entry: entry, mono: mono, weeks: 6)

    // Was `StreakFace`, literally.
    case (.volume, .small):     VolumeFocusFace(entry: entry, mono: mono)
    case (.volume, .medium):    VolumeFace(entry: entry, mono: mono)
    case (.volume, .large):     VolumeLargeFace(entry: entry, mono: mono)

    case (.streak, .small):     StreakFace(entry: entry, mono: mono)
    case (.streak, .medium):    ConsistencyFace(entry: entry, mono: mono, large: false)
    case (.streak, .large):     ConsistencyFace(entry: entry, mono: mono, large: true)

    case (.records, .small):    RecordFocusFace(entry: entry, mono: mono)
    case (.records, .medium):   RecordLedgerFace(entry: entry, mono: mono)
    case (.records, .large):    RecordGridFace(entry: entry, mono: mono)

    case (.oneRepMax, .small):  OneRepMaxFocusFace(entry: entry, mono: mono)
    case (.oneRepMax, .medium): OneRepMaxLedgerFace(entry: entry, mono: mono, large: false)
    case (.oneRepMax, .large):  OneRepMaxLedgerFace(entry: entry, mono: mono, large: true)

    case (.cardio, .small):     CardioFocusFace(entry: entry, mono: mono)
    case (.cardio, .medium):    CardioLedgerFace(entry: entry, mono: mono)
    case (.cardio, .large):     CardioLargeFace(entry: entry, mono: mono)
    }
  }
}

// MARK: - Today
//
// ── THREE STATES, ONE LAYOUT ─────────────────────────────────────────────────
// Rest, due, done. They are the same shape deliberately: a widget whose height
// and layout change with the day is one you have to re-read every morning to
// find out where the number went.
//
// The DONE state is the one that earned this face. `today` — duration, RPE,
// tonnage, sets, records — used to be thrown away by the route after the week
// aggregates were computed, so the widget could say a session existed and
// nothing whatsoever about it.

/// The Pulse tab's muscle wash, on a tile.
///
/// ── ONE GRADIENT, TWO SURFACES ───────────────────────────────────────────────
/// `PulseTabView.muscleWash` washes the top of the day's list with the first two
/// distinct muscles the day's sessions train. This is the same drawing on the
/// same rule, which is why it is here rather than re-invented per face: two
/// gradients built from one idea drift the first time either is nudged, and the
/// Today tile and the Pulse tab are the two surfaces a user sees a session on.
///
/// Two hues and not all of them: a gradient of six is a smear, and the first two
/// are the ones the deck leads with. Nil hues — a rest day, or a deck of
/// movements the map has never seen — draw NOTHING, not a grey band. "Nothing is
/// planned" is a real answer and it has no colour.
struct MuscleWash: View {
  let muscles: [LandmarkMuscle]
  var mono: Bool = false
  /// The tile is small and the wash is behind type, so it sits well under the
  /// Pulse tab's own 0.18 — that one has a whole screen to fade across.
  var opacity: Double = 0.18
  /// How far the wash bleeds past the face's own bounds, so it reaches the
  /// TILE's edges rather than the content inset's.
  ///
  /// ── WHY A NUMBER AND NOT THE INSET ─────────────────────────────────────
  /// The two hosts inset differently — `TileFrame` pads 12 and WidgetKit's
  /// `containerBackground` uses the system's own content margin — and a wash
  /// that stopped at either one drew a hard-edged rectangle floating inside the
  /// tile, which is what the first shot of this face showed. Both hosts CLIP to
  /// the tile's rounded rect (`onyxGlass` ends in `clipShape`;
  /// `containerBackground` clips to the widget shape), so over-reaching is free
  /// and the exact inset never has to be known here.
  var bleed: CGFloat = 24

  var body: some View {
    let hues = muscles.prefix(2).map { Color.onyx.muscle($0) }
    if !hues.isEmpty, !mono {
      LinearGradient(
        stops: hues.enumerated().map { index, hue in
          .init(
            color: hue.opacity(opacity),
            location: hues.count > 1 ? Double(index) / Double(hues.count - 1) : 0
          )
        },
        startPoint: .topLeading, endPoint: .topTrailing
      )
      .mask { LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom) }
      .padding(.horizontal, -bleed)
      .padding(.top, -bleed)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
}

struct TodayFace: View {
  let entry: OnyxTileEntry
  let mono: Bool
  /// Small drops the metadata row; there is no room for four figures under a
  /// headline, and a Small that tries becomes an unreadable Medium.
  let compact: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var accent: Color {
    mono ? .white : Color.onyx.day(s?.workout.dayKey)
  }
  private var isRest: Bool { s?.workout.isRestDay == true }
  private var done: OnyxSnapshot.Today? { s?.today }

  var body: some View {
    stack
      // The wash is the deck's own two hues, behind everything, fading out
      // before the figures start. Top-aligned and height-bounded: a gradient
      // that ran the whole tile would tint the stat grid too, and the grid is
      // the one part of this face that is a table.
      .background(alignment: .top) {
        MuscleWash(muscles: s?.workout.landmarks ?? [], mono: mono)
          .frame(height: compact ? 88 : 100)
      }
  }

  private var stack: some View {
    VStack(alignment: .leading, spacing: compact ? 6 : 8) {
      TodayHeader(entry: entry, mono: mono, branded: !compact)

      // ── THE HEADLINE IS THE TAP TARGET (W6) ─────────────────────────────
      // The face's root `widgetURL` already points at the deck, so the whole
      // Small has always started a session. On a Medium and a Large it shares
      // the face with a stat grid and a week strip, and a tap landing on the
      // deck from any of those is a surprise — so the START is named, and the
      // `Link` around it is the one region that means it.
      if compact {
        headline
      } else {
        Link(destination: OnyxLink.workout ?? OnyxLink.home!) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            headline
            Spacer(minLength: 4)
            if !isRest, done == nil { StartChip(accent: accent) }
          }
        }
      }

      if let sub {
        Text(sub).font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary).lineLimit(1)
      }

      Spacer(minLength: 0)

      // ── THE ROW IS PRESENT IN BOTH STATES ───────────────────────────────────
      // It used to render only `if let done`, so an unlogged training day — the
      // state you actually look at a widget in — was a title, one grey line and
      // two-thirds of a Spacer. The file's own header says the three states are
      // one layout deliberately, "a widget whose height and layout change with
      // the day is one you have to re-read every morning", and then the layout
      // changed with the day.
      //
      // Rest is the one state that genuinely has no figures, and says so above.
      if !compact, let done {
        Hairline()
        TodayStats(done: done, mono: mono)
      } else if !compact, !isRest, let s {
        Hairline()
        TodayPlanned(workout: s.workout, week: s.week, mono: mono)
      }

      if !compact {
        // ── CONTEXT, NOT A COUNT ────────────────────────────────────────────
        // This used to be "3/5 this week" over a rail, which is a number you
        // cannot act on: it says how many sessions happened and nothing about
        // WHICH, so a week of three leg days and a week of a proper rotation
        // rendered identically. The chips name the sessions in their own
        // `DAY_COLOR`, so the shape of the week is visible rather than counted.
        Hairline()
        HStack(spacing: 5) {
          Text(weekText)
            .font(OnyxWidgetType.face(9, weight: .semibold)).foregroundStyle(Color.onyx.textSecondary)
            .lineLimit(1)
          Spacer(minLength: 4)
          SessionChips(entry: entry, mono: mono)
        }
      }
    }
  }

  private var headline: some View {
    Text(s?.workout.label ?? "—")
      // 20 on the Medium, up from 18: the stat grid below it grew to two rows
      // and a headline that stayed put would have read as the smaller half of
      // its own tile. `lineLimit(2)` and the scale factor are what keep "Legs
      // & Core B" inside 338 pt at the larger size.
      .font(OnyxWidgetType.label(compact ? 15 : 20, weight: .bold))
      .foregroundStyle(Color.onyx.textPrimary)
      .lineLimit(2)
      .minimumScaleFactor(0.8)
  }

  /// Rest says what it is for; due says how much work it is; done says nothing
  /// here, because the metadata row below is already saying it.
  ///
  /// ── THE SMALL'S ONLY LINE ────────────────────────────────────────────────
  /// A Small never renders the stat row (there is no room for four figures under
  /// a headline), so this sentence is the entire content of a Small below its
  /// title. "not logged yet" was true and said nothing you could act on. The
  /// prescription is the thing worth a glance: how much work today is.
  private var sub: String? {
    if isRest { return "recovery is the session" }
    if let done {
      // On a Small, where the stat row is absent, the two figures that matter.
      guard compact else { return nil }
      let time = done.durationMin.map { "\($0)′" }
      let volume = OnyxSnapshot.tonnes(done.volumeKg)
      let parts = [time, volume].compactMap { $0 }
      return parts.isEmpty ? "logged" : parts.joined(separator: " · ")
    }
    if let exercises = s?.workout.plannedExercises, let sets = s?.workout.plannedSets {
      return "\(exercises) exercises · \(sets) sets"
    }
    // No prescription resolved — an unknown plan is not a zero one.
    return "not logged yet"
  }

  /// The same "3/5" every other training face prints, with the period named.
  /// It used to spell the target branch out a second time, which is one place
  /// too many for a rule about whether a denominator exists.
  private var weekText: String {
    guard let count = sessionsText(s) else { return "—" }
    return "\(count) this week"
  }

  private var sessionProgress: Double? {
    guard let week = s?.week, let target = week.sessionTarget, target > 0 else { return nil }
    return min(1, Double(week.sessions) / Double(target))
  }
}

/// "START" — the one word that says the tap does something rather than opens
/// something. Drawn only on a training day that has not been logged: a chip on
/// a rest day would be an invitation the plan did not make, and one on a
/// finished session would ask you to do it twice.
private struct StartChip: View {
  let accent: Color

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: "play.fill").font(OnyxWidgetType.face(8))
      Text("START").font(OnyxWidgetType.face(9, weight: .heavy)).tracking(0.8)
    }
    .foregroundStyle(accent)
    .padding(.horizontal, 6)
    .padding(.vertical, 2.5)
    .background(
      Capsule().fill(accent.opacity(0.16))
    )
    .fixedSize()
  }
}

/// This week's sessions, newest last, each in its own day colour.
///
/// Filled = trained, hollow outline = a scheduled day that did not happen. Rest
/// days are absent entirely: they are not sessions, and including them as a
/// third state would make the row a calendar, which is a different focus.
///
/// The label comes from `CalendarDay.label` — the plan's own words, resolved
/// server-side and previously discarded. A colour identifies a session; it
/// cannot name one, so before the payload carried the label there was nothing
/// here but dots.
private struct SessionChips: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }

  /// The trailing week of the 42-day window, scheduled days only, oldest first.
  private var week: [OnyxSnapshot.CalendarDay] {
    let all = s?.calendar ?? []
    return (all.count > 7 ? Array(all.suffix(7)) : all).filter(\.scheduled)
  }

  var body: some View {
    if week.isEmpty {
      // The Fuel and Body scopes do not carry a calendar, and neither does a
      // fresh install. Silence beats an empty row of placeholder pills.
      EmptyView()
    } else {
      HStack(spacing: 3) {
        ForEach(week) { day in
          let color = mono ? Color.white : Color.onyx.day(day.dayKey)
          Text(shortLabel(day))
            .font(OnyxWidgetType.face(8, weight: .bold))
            .lineLimit(1)
            .foregroundStyle(day.logged ? Color.onyx.base : color)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(day.logged ? color : .clear)
                .strokeBorder(color.opacity(day.logged ? 0 : 0.55), lineWidth: 1)
            )
        }
      }
    }
  }

  /// "Legs & Core B" in a chip is a chip full of ellipsis. The initials of the
  /// significant words carry it — "LCB" — and the colour does the rest.
  private func shortLabel(_ day: OnyxSnapshot.CalendarDay) -> String {
    guard let label = day.label, !label.isEmpty else { return "·" }
    let initials = label
      .split(separator: " ")
      .filter { $0 != "&" }
      .compactMap { $0.first.map(String.init) }
      .joined()
      .uppercased()
    return initials.isEmpty ? "·" : String(initials.prefix(3))
  }
}

/// Glyph, state caption, stale tag. Shared so the Medium and the Large open the
/// same way — the state of the day is the first thing both have to say.
private struct TodayHeader: View {
  let entry: OnyxTileEntry
  let mono: Bool
  /// Whether to carry the Onyx mark. Medium and Large do; a Small is 150pt and
  /// cannot spare the corner, and nobody needs branding on a widget they chose
  /// to install.
  var branded = false

  private var s: OnyxSnapshot? { entry.snapshot }
  private var isRest: Bool { s?.workout.isRestDay == true }
  private var accent: Color { mono ? .white : Color.onyx.day(s?.workout.dayKey) }

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: glyph)
        .font(OnyxWidgetType.face(10, weight: .semibold))
        .foregroundStyle(isRest ? Color.onyx.textSecondary : accent)
      Caption(caption, color: isRest ? Color.onyx.textSecondary : accent)
      Spacer(minLength: 0)
      if entry.isStale { StaleTag(age: entry.age) }
      // Every size, sized to the room it has. It used to be Medium-and-up
      // only, so the Small Today face — the most-installed widget in the set —
      // was the one that never said whose it was.
    }
  }

  private var glyph: String {
    if isRest { return "moon.zzz.fill" }
    return s?.today != nil ? "checkmark.circle.fill" : "dumbbell.fill"
  }

  private var caption: String {
    if isRest { return "REST DAY" }
    return s?.today != nil ? "DONE" : "DUE TODAY"
  }
}

/// The DUE state's four figures — the row that used not to exist.
///
/// Same four columns, same heights, same `Stat` as the done state, so switching
/// between them is a change of contents rather than a change of layout. What the
/// plan asks, what it asked last time, and where the week stands.
private struct TodayPlanned: View {
  let workout: OnyxSnapshot.Workout
  let week: OnyxSnapshot.Week
  let mono: Bool

  var body: some View {
    HStack(spacing: 0) {
      Stat(value: workout.plannedExercises.map { "\($0)" }, label: "EXERCISES", color: Color.onyx.textPrimary)
      Stat(value: workout.plannedSets.map { "\($0)" }, label: "SETS", color: Color.onyx.textPrimary)
      // The number you are chasing. Nil — not zero — when this split has no
      // earlier session; "0.0 t last time" would be a target of nothing.
      Stat(value: OnyxSnapshot.tonnes(workout.lastVolumeKg), label: "LAST TIME",
           color: mono ? .white : Color.onyx.textSecondary)
      Stat(value: week.sessionTarget.map { "\(week.sessions)/\($0)" } ?? "\(week.sessions)",
           label: "THIS WEEK", color: Color.onyx.textPrimary)
    }
  }
}

/// What the session cost, in six figures over two rows.
///
/// ── WHY SIX AND NOT FOUR ─────────────────────────────────────────────────
/// Four figures across one row left the Medium with a band of obsidian above
/// them that the `Spacer` was collecting — a tile reporting a finished session
/// and using a third of itself to say nothing. The two readings that fill it
/// are ones `workout_sessions` has carried all along and no surface but the
/// session page ever showed: what the session cost in calories, and what the
/// heart did during it.
///
/// ── AND WHY THREE ACROSS RATHER THAN SIX ─────────────────────────────────
/// Six `Stat`s across a 338 pt Medium is ~56 pt a column, which is narrower
/// than "1.4 t" plus its label wants at a readable size. Three across is 112,
/// which is what pays for the type going up from 13 to 15 rather than down.
///
/// ── THE GRID IS FIXED, INCLUDING THE EMPTY CELLS ─────────────────────────
/// A session with no heart rate draws "—" and keeps its cell. This file's own
/// header is explicit that the three day-states are one layout on purpose —
/// "a widget whose height and layout change with the day is one you have to
/// re-read every morning" — and a row that collapses when a reading is
/// missing is the same defect one axis down.
private struct TodayStats: View {
  let done: OnyxSnapshot.Today
  let mono: Bool

  var body: some View {
    VStack(spacing: 6) {
      HStack(spacing: 0) {
        Stat(value: done.durationMin.map { "\($0)′" }, label: "TIME", color: Color.onyx.textPrimary, size: 15)
        Stat(value: OnyxSnapshot.tonnes(done.volumeKg), label: "VOLUME", color: Color.onyx.textPrimary, size: 15)
        Stat(value: done.prCount.map { "\($0)" }, label: "RECORDS",
             color: (done.prCount ?? 0) > 0 ? (mono ? .white : Color.onyx.record) : Color.onyx.textSecondary,
             size: 15)
      }
      HStack(spacing: 0) {
        Stat(value: done.sessionRpe.map { String(format: "%.0f/10", $0) },
             label: "EFFORT", color: mono ? .white : OnyxDomain.train.accent, size: 15)
        // No decimal and no thousands separator: it is a kilocalorie count in
        // a 112 pt column, and "612" is the whole of what it has to say.
        Stat(value: done.caloriesKcal.map { "\(Int($0.rounded()))" }, label: "CALORIES",
             color: mono ? .white : OnyxDomain.fuel.accent, size: 15)
        Stat(value: done.avgBpm.map { "\($0)" }, label: "AVG HR",
             color: mono ? .white : OnyxDomain.recover.accent, size: 15)
      }
    }
  }
}

/// Large · today in the context of the week it belongs to.
///
/// ── WHY THE OLD ONE WAS 70% AIR ──────────────────────────────────────────────
/// It was the Medium. A rest day has a two-word headline and a progress rail, so
/// rendering that at Large left "Rest · 5/5" floating over most of a screen's
/// worth of obsidian. The fix is not more padding — it is a second register of a
/// different kind. The week's sessions are already in the `calendar` slice, one
/// row each with the day's own colour and its tonnage, which is the thing a rest
/// day most wants to show you: what the rest is FOR.
struct TodayLargeFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var accent: Color { mono ? .white : Color.onyx.day(s?.workout.dayKey) }

  /// The seven days ending TODAY.
  ///
  /// ── WHY `suffix(7)` WAS THE WRONG SEVEN ─────────────────────────────────
  /// The docstring here claimed the payload window ends today. It does not:
  /// `WidgetSnapshotBuilder` runs it to `lastDayOfMonth`, because the same
  /// slice draws the month grid. So on the 8th the last seven entries were the
  /// 24th to the 30th — seven days that have not happened, every one of them
  /// scheduled, none of them logged, and `DayRow` therefore drawing all seven
  /// as "missed". A widget reporting a week of failures that are actually next
  /// week's sessions.
  ///
  /// Cutting at the snapshot's own date is the fix, and it is the fix for the
  /// month grid's neighbour too — nothing else reads this property.
  private var recent: [OnyxSnapshot.CalendarDay] {
    let all = s?.calendar ?? []
    // No date to cut on is the old behaviour, which is right for a payload
    // that genuinely ends today.
    guard let today = s?.date else { return Array(all.suffix(7)) }
    let upToToday = Array(all.prefix { $0.d <= today })
    return upToToday.count > 7 ? Array(upToToday.suffix(7)) : upToToday
  }

  var body: some View {
    stack
      // The deck's own hues, behind the first register only — see `MuscleWash`.
      .background(alignment: .top) {
        MuscleWash(muscles: s?.workout.landmarks ?? [], mono: mono)
          .frame(height: 120)
      }
  }

  private var stack: some View {
    VStack(alignment: .leading, spacing: 10) {
      Register(title: "TODAY", accent: mono ? .white : accent) {
        TodayHeader(entry: entry, mono: mono, branded: true)
        Link(destination: OnyxLink.workout ?? OnyxLink.home!) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(s?.workout.label ?? "—")
              .font(OnyxWidgetType.face(24, weight: .bold))
              .foregroundStyle(Color.onyx.textPrimary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if s?.workout.isRestDay != true, s?.today == nil { StartChip(accent: accent) }
          }
        }
        if let done = s?.today {
          TodayStats(done: done, mono: mono)
        } else if s?.workout.isRestDay == true {
          Text("recovery is the session")
            .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
        } else if let s {
          // Was "not logged yet" — true, and nothing you could act on, on the
          // largest surface in the gallery.
          TodayPlanned(workout: s.workout, week: s.week, mono: mono)
        }
      }

      Hairline()

      Register(title: "THE LAST SEVEN DAYS", accent: mono ? .white : OnyxDomain.train.accent) {
        if recent.isEmpty {
          Text("no scheduled days on record yet")
            .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
        } else {
          VStack(spacing: 0) {
            ForEach(Array(recent.enumerated()), id: \.element.id) { index, day in
              if index > 0 { Hairline().padding(.vertical, 3) }
              DayRow(day: day, today: s?.date, mono: mono)
            }
          }
          .frame(maxHeight: .infinity)
        }
      }
      .frame(maxHeight: .infinity)

      Hairline()

      HStack(spacing: 0) {
        Stat(value: s.map { "\($0.week.sessions)" }, label: "SESSIONS", color: Color.onyx.textPrimary)
        Stat(value: OnyxSnapshot.tonnes(s?.week.volumeKg), label: "VOLUME", color: Color.onyx.textPrimary)
        Stat(value: s.map { "\($0.week.sets)" }, label: "SETS", color: Color.onyx.textPrimary)
        Stat(value: s?.streak.map { "\($0.current)" }, label: "STREAK",
             color: mono ? .white : OnyxDomain.train.accent)
      }
    }
  }
}

/// One day of the week, as a row: colour, weekday, and what happened.
private struct DayRow: View {
  let day: OnyxSnapshot.CalendarDay
  let today: String?
  let mono: Bool

  private var color: Color { mono ? .white : Color.onyx.day(day.dayKey) }
  private var isToday: Bool { day.d == today }

  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(day.logged ? color : .clear)
        .strokeBorder(day.scheduled ? color.opacity(0.6) : Color.onyx.textSecondary.opacity(0.3), lineWidth: 1.5)
        .frame(width: 10, height: 10)
      Text(OnyxSnapshot.weekdayInitial(day.d) + (OnyxSnapshot.dayOfMonth(day.d).map { " \($0)" } ?? ""))
        .font(OnyxWidgetType.face(11, weight: isToday ? .bold : .semibold))
        .foregroundStyle(isToday ? Color.onyx.textPrimary : Color.onyx.textSecondary)
        .frame(width: 42, alignment: .leading)
      // The plan's own name for the session, which the payload now carries. A
      // week of rows reading "trained · trained · trained" said only that they
      // happened, never which ones — and which ones is the whole question a rest
      // day is asking.
      Text(day.label ?? state)
        .font(OnyxWidgetType.face(11, weight: .medium))
        .foregroundStyle(day.logged ? Color.onyx.textPrimary : Color.onyx.textSecondary)
        .lineLimit(1)
      Text(state)
        .font(OnyxWidgetType.face(9))
        .foregroundStyle(stateColor)
        .lineLimit(1)
      Spacer(minLength: 4)
      if let volume = OnyxSnapshot.tonnes(day.volumeKg) {
        Text(volume)
          .font(OnyxWidgetType.face(11, weight: .bold, design: .monospaced))
          .foregroundStyle(Color.onyx.textPrimary)
      }
    }
  }

  /// A rest day is not a failure and must never be worded like one. A scheduled
  /// day still ahead of the clock is not a miss either.
  private var state: String {
    if day.logged { return "done" }
    if !day.scheduled { return "rest" }
    if isToday { return "due" }
    return "missed"
  }

  private var stateColor: Color {
    if day.logged { return mono ? .white : Color.onyx.good }
    if day.scheduled && !isToday { return mono ? .white : Color.onyx.danger }
    return Color.onyx.textSecondary
  }
}

/// One figure in a footer row: value above, label under it.
///
/// `Metric` puts the two side by side, which is right for a VERTICAL list of
/// facts and wrong for a horizontal one — four side-by-side pairs across a
/// Medium wrap into an unreadable mess.
struct Stat: View {
  let value: String?
  let label: String
  var color: Color = Color.onyx.textPrimary
  /// 13 is what a row of FOUR can carry. A row of three has 112 pt a column
  /// instead of 84 and can afford 15, which is the difference between a
  /// figure you read and one you decode. Passed in rather than derived,
  /// because the view cannot see how many siblings it has.
  var size: CGFloat = 13

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value ?? "—")
        .font(OnyxWidgetType.face(size, weight: .bold, design: .monospaced))
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(label)
        .font(OnyxWidgetType.face(size >= 15 ? 8 : 7, weight: .bold))
        .foregroundStyle(Color.onyx.textSecondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Calendar
//
// ── WHY A RING AND NOT A HEAT MAP ────────────────────────────────────────────
// The interesting fact about a training month is not how much you did on each
// day — it is whether the day the plan asked for happened. So each scheduled day
// is a ring in its OWN colour (`Color.onyx.day`, mirroring `DAY_COLOR`): filled when
// a session landed, hollow when it did not, and a bare number on a rest day. A
// heat map would say "Tuesday was a big day" and leave "Tuesday was missed"
// looking identical to "Tuesday was a rest day".
//
// ── THE THREE THINGS THAT MADE IT UNREADABLE ─────────────────────────────────
// 1. No dates. `DayDot` drew a circle and nothing else, so the grid was a field
//    of identical rings with no way to find a day in it. `CalendarDay.d` carried
//    the date the whole time.
// 2. The columns were mislabelled. The payload window is 42 days ENDING TODAY,
//    and the grid chunked it seven at a time from index zero, then printed a
//    hardcoded "S M T W T F S" over the result. With today on a Friday the rows
//    began on a Saturday, so every column was off by one — and by a different
//    amount tomorrow. `MonthGrid` now PADS to the week boundary using the real
//    weekday of the first cell, which makes the header true by construction.
// 3. Fixed 13/16pt cells in a stack that could not grow, so a Medium filled
//    about half its height and a Large about a third. Cells are now sized from
//    the space actually available.

struct CalendarFace: View {
  let entry: OnyxTileEntry
  let mono: Bool
  /// How many weeks the grid may draw. Only the summary strip depends on it now.
  let weeks: Int
  /// The Small face: same month, less furniture around it.
  var compact = false

  private var s: OnyxSnapshot? { entry.snapshot }

  /// The days the grid draws — the calendar month containing today, at EVERY
  /// size.
  ///
  /// ── SMALL USED TO BE A ROLLING WEEK ────────────────────────────────────────
  /// It drew the trailing seven days and captioned them "THIS WEEK". Honest, and
  /// not what a calendar widget is for: a strip of the last seven days answers
  /// "what did I just do", which the Today face already answers, while the
  /// question you put a calendar on a home screen to answer is "where am I in
  /// the month". Seven cells also left most of a 150pt square empty to say it.
  ///
  /// A month fits: `MonthGrid` sizes its cells to whichever axis binds, so six
  /// rows in a Small land near 18pt a cell — comfortably above the 11pt floor,
  /// and the digits stay above 7pt.
  private var days: [OnyxSnapshot.CalendarDay] {
    let all = s?.calendar ?? []
    // The calendar month containing today. `d` is `YYYY-MM-DD`, so the month is
    // a string prefix — no date parsing, no timezone to get wrong.
    let month = String((s?.date ?? "").prefix(7))
    let inMonth = all.filter { $0.d.hasPrefix(month) }
    return inMonth.isEmpty ? all : inMonth
  }

  /// "AUGUST" — the month the grid is showing, at every size.
  private var caption: String {
    OnyxSnapshot.monthName(s?.date)?.uppercased() ?? "CALENDAR"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 5 : 7) {
      HStack(spacing: 5) {
        Caption(caption, color: mono ? .white : Color.onyx.textSecondary)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
        // The mark, at every size. Small pays for it by dropping the streak
        // flame below — of the two, the one that has to survive is the one that
        // says whose widget this is; the streak is on the Today face as well.
        if !compact, let streak = s?.streak, streak.current > 0 {
          HStack(spacing: 3) {
            Image(systemName: "flame.fill")
              .font(OnyxWidgetType.face(9))
              .foregroundStyle(mono ? .white : OnyxDomain.train.accent)
            Text("\(streak.current)")
              .font(OnyxWidgetType.face(10, weight: .bold, design: .monospaced))
              .foregroundStyle(Color.onyx.textPrimary)
          }
        }
      }

      if days.isEmpty {
        Text("no scheduled days yet")
          .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      } else {
        MonthGrid(days: days, today: s?.date, mono: mono, showHeader: !compact)
          .frame(maxHeight: .infinity)
      }

      if weeks >= 6 && !compact {
        Hairline()
        HStack(spacing: 0) {
          Stat(value: s.map { "\($0.week.sessions)" }, label: "THIS WEEK", color: Color.onyx.textPrimary)
          Stat(value: s?.streak.map { "\($0.current)" },
               label: "PROGRAM DAY", color: mono ? .white : OnyxDomain.train.accent)
          Stat(value: OnyxSnapshot.tonnes(s?.week.volumeKg), label: "VOLUME", color: Color.onyx.textPrimary)
        }
      }
    }
  }
}

/// A week-aligned month grid with dated cells.
///
/// The alignment is the whole reason this is a type rather than a `ForEach`: the
/// payload window starts on an arbitrary weekday, so the first row is PADDED
/// with empty cells until it does. Once column zero is genuinely Sunday, the
/// header is simply true — no derived letters, no offset arithmetic at the call
/// site, and no way for the two to drift apart again.
struct MonthGrid: View {
  let days: [OnyxSnapshot.CalendarDay]
  let today: String?
  let mono: Bool
  var showHeader = true

  /// Nil is a padding cell — a slot that exists so the column lines up, and
  /// which must draw nothing at all rather than an empty ring implying a day.
  private var rows: [[OnyxSnapshot.CalendarDay?]] {
    guard let first = days.first else { return [] }
    let lead = OnyxSnapshot.weekdayIndex(first.d) ?? 0
    var cells: [OnyxSnapshot.CalendarDay?] = Array(repeating: nil, count: lead)
    cells.append(contentsOf: days.map { Optional($0) })
    // Trailing pad, so the final row is a full week and the cell width matches
    // every row above it.
    while cells.count % 7 != 0 { cells.append(nil) }
    return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
  }

  var body: some View {
    GeometryReader { geo in
      let all = rows
      let headerHeight: CGFloat = showHeader ? 12 : 0
      let rowSpacing: CGFloat = 3
      let available = geo.size.height - headerHeight - rowSpacing * CGFloat(max(all.count - 1, 0))
      // Cells are square and fit BOTH axes, so the grid grows into a Large
      // instead of sitting at 16pt with a hand's width of obsidian under it.
      let cell = max(11, min(geo.size.width / 7, available / CGFloat(max(all.count, 1))))

      VStack(alignment: .leading, spacing: rowSpacing) {
        if showHeader {
          HStack(spacing: 0) {
            // True by construction: `rows` padded column zero to Sunday.
            ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, letter in
              Text(letter)
                .font(OnyxWidgetType.face(8, weight: .bold))
                .foregroundStyle(Color.onyx.textSecondary)
                .frame(maxWidth: .infinity)
            }
          }
          .frame(height: headerHeight)
        }
        ForEach(Array(all.enumerated()), id: \.offset) { _, week in
          HStack(spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
              Group {
                if let day {
                  // ── EACH CELL IS ITS OWN DESTINATION ───────────────────────
                  // Tapping a Sunday used to open the Progress tab and leave you
                  // to find Sunday. A `Link` inside a widget works at Medium and
                  // Large only — a Small gets exactly one tap target, which
                  // stays the face's `widgetURL` — so this is wrapped rather
                  // than replaced, and the Small keeps working as before.
                  if let url = OnyxLink.day(day.d) {
                    Link(destination: url) {
                      DayCell(day: day, isToday: day.d == today, mono: mono, size: cell,
                              outside: !OnyxSnapshot.sameMonth(day.d, as: today))
                    }
                  } else {
                    DayCell(day: day, isToday: day.d == today, mono: mono, size: cell,
                            outside: !OnyxSnapshot.sameMonth(day.d, as: today))
                  }
                } else {
                  Color.clear
                }
              }
              .frame(maxWidth: .infinity)
            }
          }
          .frame(height: cell)
        }
        Spacer(minLength: 0)
      }
    }
  }
}

/// One calendar cell: a date, and what the plan and the log say about it.
///
/// Filled ring = trained. Hollow ring = a scheduled day that did not happen.
/// Bare number = a rest day, which is not a failure and must not look like one.
/// The number is the part that was missing entirely — a grid of undated rings is
/// a texture, and the complaint that it showed "white circles with no dates" was
/// exactly right.
private struct DayCell: View {
  let day: OnyxSnapshot.CalendarDay
  let isToday: Bool
  let mono: Bool
  let size: CGFloat
  /// Days from the neighbouring month, dimmed rather than blanked so the month
  /// has edges without the grid having holes.
  var outside = false

  /// A rest day has no `dayKey`, and `Color.onyx.day(nil)` answers tertiary
  /// grey (§3.2). That is a RING colour and it is correct here — the calendar
  /// cell is a fill, not a word. A rest day's LABEL takes `dayLabel` instead.
  private var color: Color { mono ? .white : Color.onyx.day(day.dayKey) }

  /// ── A TRAINED DAY IS SOLID WHITE WITH A BLACK DATE ────────────────────────
  /// It was a 22%-alpha wash of the day colour under a white number — legible,
  /// and quiet: on a grid of thirty cells the trained days did not jump out,
  /// which is the entire job of a training calendar.
  ///
  /// White-on-black is the highest contrast this surface can produce, in both
  /// directions, so the fill reads at a glance AND the date survives on top of
  /// it. That is the difference from the version this replaces, which filled
  /// with the DAY COLOUR and printed near-black on top: at `size * 0.42` in a
  /// Small cell, roughly 4.6pt of obsidian on gold — not small text, a smudge.
  /// Gold is a mid-tone; white is not.
  ///
  /// The day colour does not disappear: it still draws the scheduled-but-missed
  /// ring, which is where it is carrying information rather than decoration.
  private var textColor: Color {
    if outside { return Color.onyx.textSecondary.opacity(0.55) }
    if day.logged { return Color.onyx.base }
    return day.scheduled ? Color.onyx.textPrimary : Color.onyx.textSecondary
  }

  var body: some View {
    ZStack {
      if day.logged {
        Circle().fill(Color.onyx.textPrimary)
      } else if day.scheduled {
        Circle().strokeBorder(color.opacity(0.5), lineWidth: 1.5)
      }

      Text(OnyxSnapshot.dayOfMonth(day.d).map { "\($0)" } ?? "")
        .font(OnyxWidgetType.figure(max(7, size * 0.42)))
        .fontWeight(day.logged ? .bold : .semibold)
        .foregroundStyle(textColor)
        // 0.6, not 0.7: a Small month is six rows, so the cell is smaller than
        // it was on any face that drew this before, and a two-digit date must
        // shrink rather than truncate.
        .minimumScaleFactor(0.6)

      // Today is a RING AROUND the cell, not a dot under the number.
      //
      // The dot sat inside the circle, which was fine over a 22% wash and is
      // invisible over a solid white one — and painting it dark instead would
      // put a second black mark inside a cell that already has a black date in
      // it. Outside the fill it cannot collide with either.
      if isToday {
        Circle()
          .strokeBorder(mono ? Color.white : OnyxDomain.train.accent, lineWidth: max(1, size * 0.075))
          .frame(width: size, height: size)
      }

      // A rest day inside the month gets a faint dot so the grid still reads as
      // a grid rather than as scattered rings over blank space. Suppressed on
      // today, which now carries its own ring.
      if !day.scheduled && !day.logged && !outside && !isToday {
        VStack(spacing: 0) {
          Spacer(minLength: 0)
          Circle()
            .fill(Color.onyx.textSecondary.opacity(0.4))
            .frame(width: max(2, size * 0.09), height: max(2, size * 0.09))
        }
        .frame(height: size)
      }
    }
    .frame(width: size, height: size)
    .opacity(outside ? 0.35 : 1)
  }
}

// MARK: - Volume
//
// This week's tonnage, its delta against last week, and the sixteen muscles the
// tonnage was spent on.
//
// ── WHY THE TREND GAVE WAY TO THE STRIP (W6) ─────────────────────────────────
// Every size of this tile drew the same eight-week series — a sparkline on the
// Small, a `BarChart` on the Medium, the `BarChart` again on the Large — which
// answers "is the block trending up". That is a real question and it is the
// Trajectory tile's; asked here it left "Tonnage" as a tile about a number's
// history rather than about the week. The reading the payload has carried per
// LANDMARK since W3 and no face has drawn is the one a Tuesday can act on:
// which muscle is behind.
//
// `HeatStrip` is that figure — sixteen cells ordered by how much of each
// muscle's target the week has covered, so the ladder runs out from left to
// right and the tail is the work that is missing. The eight weeks survive on
// the Large, where a second register has somewhere to go.
//
// Zero-based, unlike weight. Tonnage has a meaningful zero and weeks between
// 12.1 t and 14.2 t drawn on a 12.1–14.2 band look like a collapse and a
// recovery; drawn against zero they look like what they are.

struct VolumeFocusFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 4) {
        Caption("VOLUME", color: mono ? .white : OnyxDomain.train.accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }
      BigValue(value: OnyxSnapshot.tonnes(s?.week.volumeKg), size: 28, color: Color.onyx.textPrimary)
      HStack(spacing: 5) {
        Text("this week").font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
        DeltaChip(delta: volumeDeltaTonnes(s), decimals: 1, suffix: " t", monochrome: mono)
      }
      Spacer(minLength: 0)
      let strip = HeatStrip(muscles: s?.muscleFocus ?? [], monochrome: mono, height: 22)
      strip
      if let behind = strip.laggard {
        Text("\(behind.muscle) \(Int(behind.sets.rounded()))/\(behind.target)")
          .font(OnyxWidgetType.face(9, weight: .semibold))
          .foregroundStyle(Color.onyx.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
    }
  }
}

/// Medium · the figures on the left, the eight weeks on the right.
///
/// ── WHY BARS REPLACED THE LINE ───────────────────────────────────────────────
/// The old face drew a six-point line on a band of exactly min…max, so the
/// lightest week was always pinned to the floor and the heaviest to the ceiling
/// however small the real spread — twelve tonnes to fourteen drew the same cliff
/// as two to twenty. And a LINE claims the quantity existed between its points,
/// which for weekly tonnage is simply untrue: a week is a bucket, and the space
/// between two of them is not a slower Tuesday, it is nothing at all.
///
/// `BarChart` is zero-based, so the bars are in proportion to each other and to
/// nothing invented, with the trailing mean as a dotted rule to read them against.
struct VolumeFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var accent: Color { mono ? .white : OnyxDomain.train.accent }

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
          Caption("VOLUME", color: accent)
          if entry.isStale { StaleTag(age: entry.age) }
        }
        Spacer(minLength: 0)
        BigValue(value: OnyxSnapshot.tonnes(s?.week.volumeKg), size: 30, color: Color.onyx.textPrimary)
        Text("this week").font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
        DeltaChip(delta: volumeDeltaTonnes(s), decimals: 1, suffix: " t", monochrome: mono)
        Spacer(minLength: 0)
        Hairline()
        LedgerRow(label: "SESSIONS", value: sessionsText(s), color: Color.onyx.textPrimary)
        LedgerRow(label: "SETS", value: s.map { "\($0.week.sets)" }, color: Color.onyx.textSecondary)
      }
      .frame(width: 118, alignment: .leading)

      Hairline(vertical: true)

      VStack(alignment: .leading, spacing: 4) {
        let strip = HeatStrip(muscles: s?.muscleFocus ?? [], monochrome: mono, height: 44)
        // "SIXTEEN MUSCLES" plus a rubric is 215 pt of caption in a 160 pt
        // column: it wrapped to two lines AND ran under the Onyx mark. The
        // Large keeps the longer wording, where the register is full width.
        HStack(spacing: 4) {
          Caption("MUSCLES", color: Color.onyx.textSecondary)
          Spacer(minLength: 0)
        }
        // The corner belongs to the mark; this row's content runs to the edge.
        .padding(.trailing, OnyxMark.faceInset)
        strip.frame(maxHeight: .infinity)
        // The tail, named. The strip says WHICH end is short; only the word
        // says which muscle, and a sixteen-cell ladder has no room for labels.
        Text(strip.laggard.map { "\($0.muscle) is furthest behind — \(Int($0.sets.rounded())) of \($0.target)" }
             ?? "every muscle at or past its target")
          .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
          .lineLimit(1).minimumScaleFactor(0.8)
      }
      .frame(maxWidth: .infinity)
    }
  }
}

/// Large · the week, the eight weeks, and where the tonnage actually went.
struct VolumeLargeFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private func tint(_ c: Color) -> Color { mono ? .white : c }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Register(title: "THIS WEEK", accent: tint(OnyxDomain.train.accent)) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          BigValue(value: OnyxSnapshot.tonnes(s?.week.volumeKg), size: 34, color: Color.onyx.textPrimary)
          DeltaChip(delta: volumeDeltaTonnes(s), decimals: 1, suffix: " t", monochrome: mono)
          Spacer(minLength: 0)
          if entry.isStale { StaleTag(age: entry.age) }
        }
        HStack(spacing: 0) {
          Stat(value: sessionsText(s), label: "SESSIONS", color: Color.onyx.textPrimary)
          Stat(value: s.map { "\($0.week.sets)" }, label: "SETS", color: Color.onyx.textPrimary)
          Stat(value: s.map { "\($0.week.prs)" }, label: "RECORDS",
               color: (s?.week.prs ?? 0) > 0 ? tint(Color.onyx.record) : Color.onyx.textSecondary)
          Stat(value: OnyxSnapshot.tonnes(s?.weekPrev?.volumeKg), label: "LAST WEEK",
               color: Color.onyx.textSecondary)
        }
      }

      Hairline()

      Register(title: "SIXTEEN MUSCLES", accent: tint(OnyxDomain.train.accent)) {
        let strip = HeatStrip(muscles: s?.muscleFocus ?? [], monochrome: mono, height: 54)
        strip.frame(maxHeight: .infinity)
        Text(strip.laggard.map { "\($0.muscle) is furthest behind — \(Int($0.sets.rounded())) of \($0.target)" }
             ?? "every muscle at or past its target")
          .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
          .lineLimit(1)
      }
      .frame(maxHeight: .infinity)

      Hairline()

      // The eight weeks keep their register HERE and only here: a Large has
      // room for both the week's shape and the block's, and the Small and
      // Medium do not.
      Register(title: "EIGHT WEEKS", accent: tint(OnyxDomain.train.accent)) {
        BarChart(points: s?.volumeTrend ?? [], goal: trailingMean(s), color: tint(OnyxDomain.train.accent),
                 label: { weekLabel($0.d) })
          .frame(maxHeight: .infinity)
      }
      .frame(maxHeight: .infinity)
    }
  }
}

/// This week against last, in tonnes. Nil when either week is missing — a first
/// week compared against nothing is "new", not "+everything".
///
/// Module-wide, not file-private: the Volume faces here and the Performance
/// week strip were each carrying their own copy, and three tiles disagreeing
/// about what a missing previous week means is a bug waiting for a first week.
func volumeDeltaTonnes(_ s: OnyxSnapshot?) -> Double? {
  guard let now = s?.week.volumeKg, let then = s?.weekPrev?.volumeKg else { return nil }
  return (now - then) / 1000
}

/// "3/5" when the plan states a target, "3" when it does not. A session count
/// with no denominator is not a fact you can act on at a glance.
///
/// Module-wide, not file-private: the Performance week strip printed the same
/// rule from its own copy. One rule, so a target that appears mid-week appears
/// on every face at once.
func sessionsText(_ s: OnyxSnapshot?) -> String? {
  guard let week = s?.week else { return nil }
  if let target = week.sessionTarget, target > 0 { return "\(week.sessions)/\(target)" }
  return "\(week.sessions)"
}

/// The mean of the COMPLETED weeks — this one is excluded because it is still
/// being written, and a Monday would drag the rule down to a level no week has
/// ever finished at. Nil with fewer than two completed weeks to average.
private func trailingMean(_ s: OnyxSnapshot?) -> Double? {
  let trend = s?.volumeTrend ?? []
  let completed = trend.count > 1 ? Array(trend.dropLast()) : []
  guard completed.count >= 2 else { return nil }
  return completed.reduce(0) { $0 + $1.v } / Double(completed.count)
}

/// A week bucket's label: the day of its START date. Eight "W"s would be no
/// label at all, and a week number would need a programme epoch the payload
/// does not carry.
private func weekLabel(_ iso: String) -> String {
  OnyxSnapshot.dayOfMonth(iso).map { "\($0)" } ?? ""
}

// MARK: - Program day
//
// ── WHAT THE FLAME COUNTS NOW ────────────────────────────────────────────────
// Days elapsed since the cut opened on 2026-07-15, both ends counted. It is a
// monotonic figure and that is deliberate: a block's length is not something a
// missed Tuesday shortens, and the thing this face is asked at a glance is "how
// deep am I into this".
//
// It briefly counted consecutive SCHEDULED days trained instead. That number is
// still derived and still tested (`streakFrom`, the web app's `lib/training/streak.ts`) —
// it is the honest answer to a different question — but nothing renders it. The
// failure this whole area exists to prevent was never which number was chosen;
// it was TWO numbers under one flame, ten apart, on the same phone. There is one
// derivation (`programDayCount`), the payload route and `useStreak()` both read
// it, so if this face and the dashboard orb ever differ again the cause is
// staleness, not arithmetic.

struct StreakFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var current: Int? { s?.streak?.current }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption("PROGRAM DAY", color: mono ? .white : OnyxDomain.train.accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      Spacer(minLength: 0)

      HStack(alignment: .center, spacing: 8) {
        Image(systemName: "flame.fill")
          .font(OnyxWidgetType.face(26))
          .foregroundStyle(mono ? .white : (current ?? 0) > 0 ? OnyxDomain.train.accent : Color.onyx.textSecondary)
        BigValue(value: current.map { "\($0)" }, size: 34, color: Color.onyx.textPrimary)
      }

      Text(subtitle).font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary).lineLimit(1)

      Spacer(minLength: 0)
    }
  }

  /// ── WHY THERE IS NO LONGER A BAR ───────────────────────────────────────────
  /// A `Rail` used to draw `current / best` with a "best 27" caption under it.
  /// That is a progress bar toward your own record, and it reads as a target —
  /// so the better your best gets, the emptier a perfectly good streak looks.
  /// A streak has no denominator. The flame and the number are the whole idea,
  /// and `best` still lives on the Medium/Large face where it is a LEDGER ROW
  /// rather than a finish line.
  private var subtitle: String {
    guard let current else { return "no sessions on record" }
    if current == 0 { return "the cut has not opened yet" }
    return "days into the cut"
  }
}

/// Medium and Large · the streak, plus the thing it is a summary OF.
///
/// A streak on its own is one integer and a best, which is a Small's worth of
/// content — rendering it at Large was a flame the size of a fist over a hand's
/// width of nothing. Adherence is the honest way to fill the space: how many of
/// the days the plan asked for actually happened, which is the question the
/// streak is a lossy answer to. Every figure here comes off `calendar`, which
/// the training scope already ships.
struct ConsistencyFace: View {
  let entry: OnyxTileEntry
  let mono: Bool
  let large: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var accent: Color { mono ? .white : OnyxDomain.train.accent }

  /// Scheduled days that are OVER. Today counts only once it is logged, on the
  /// same principle as `streakFrom`: an unfinished day is not a missed one, and
  /// a widget that marks you down at breakfast is a widget that lies until dusk.
  private var judged: [OnyxSnapshot.CalendarDay] {
    let today = s?.date ?? ""
    return (s?.calendar ?? []).filter { day in
      guard day.scheduled, day.d <= today else { return false }
      return day.d != today || day.logged
    }
  }

  private var done: Int { judged.filter(\.logged).count }
  private var adherence: Double? {
    judged.isEmpty ? nil : Double(done) / Double(judged.count)
  }

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
          Caption("STREAK", color: accent)
          if entry.isStale { StaleTag(age: entry.age) }
        }
        Spacer(minLength: 0)
        HStack(alignment: .center, spacing: 6) {
          Image(systemName: "flame.fill")
            .font(OnyxWidgetType.face(large ? 30 : 22))
            .foregroundStyle((s?.streak?.current ?? 0) > 0 ? accent : Color.onyx.textSecondary)
          // `.map` on the STREAK, not on `current` — `streak` is the optional and
          // `current` is a plain Int, so `s?.streak?.current.map` asks an Int for
          // a `map` it does not have. Same trap as `week.volumeKg`.
          BigValue(value: s?.streak.map { "\($0.current)" }, size: large ? 40 : 30, color: Color.onyx.textPrimary)
        }
        Text("day streak")
          .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary).lineLimit(1)
        Spacer(minLength: 0)
      }
      .frame(width: large ? 130 : 104, alignment: .leading)

      Hairline(vertical: true)

      VStack(alignment: .leading, spacing: large ? 9 : 6) {
        LedgerRow(label: "ADHERENCE",
                  value: adherence.map { "\(Int(($0 * 100).rounded()))" },
                  color: Color.onyx.textPrimary, trailing: "%")
        Hairline()
        LedgerRow(label: "BEST", value: s?.streak.map { "\($0.best)" }, color: accent)
        Hairline()
        LedgerRow(label: "MISSED",
                  value: judged.isEmpty ? nil : "\(judged.count - done) of \(judged.count)",
                  color: judged.count == done ? Color.onyx.textSecondary : (mono ? .white : Color.onyx.danger))

        if large { Hairline() }

        // The strip is the evidence behind the percentage. Filled = trained,
        // hollow = a scheduled day that did not happen; rest days are simply not
        // here, because they were never being judged.
        AdherenceStrip(days: judged, mono: mono, dot: large ? 9 : 7)
          .frame(maxHeight: large ? .infinity : 22)
      }
      .frame(maxWidth: .infinity)
    }
  }
}

/// Every judged day as a dot, oldest first, wrapping.
private struct AdherenceStrip: View {
  let days: [OnyxSnapshot.CalendarDay]
  let mono: Bool
  let dot: CGFloat

  var body: some View {
    if days.isEmpty {
      Text("no scheduled days behind you yet")
        .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
    } else {
      // Ten a row keeps the dots legible at both sizes; a single row of thirty
      // shrinks each one to a speck on a Medium.
      let rows = stride(from: 0, to: days.count, by: 10).map {
        Array(days[$0..<min($0 + 10, days.count)])
      }
      VStack(alignment: .leading, spacing: 3) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          HStack(spacing: 3) {
            ForEach(row) { day in
              Circle()
                .fill(day.logged ? (mono ? .white : Color.onyx.day(day.dayKey)) : .clear)
                .strokeBorder(day.logged ? .clear : Color.onyx.textSecondary.opacity(0.5), lineWidth: 1)
                .frame(width: dot, height: dot)
            }
            Spacer(minLength: 0)
          }
        }
        Spacer(minLength: 0)
      }
    }
  }
}

#endif
