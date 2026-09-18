// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import Foundation
import OnyxCore

// MARK: - The entry model
//
// What every tile is handed: a payload, the moment it is being drawn, and which
// face the family was asked to lead with. This used to be `OnyxEntry:
// TimelineEntry` in the widget extension, stamped by the provider; it is a plain
// value here so the SAME tile draws on the Home Screen (the extension wraps it
// in a `TimelineEntry`) and in the app's Today grid (which has no timeline).
//
// ── WHAT LEFT WITH THE NETWORK ───────────────────────────────────────────────
// The old entry carried `status: OnyxSnapshotClient.Status` — whether the last
// FETCH had failed — and `isStale` was `status != .ok || age > 45 min`. There is
// no fetch any more: the provider reads the App Group database and builds the
// snapshot locally, so "the fetch failed" is not a state that exists. Age is the
// whole of staleness now, which is the half that always mattered (see `age`).

/// Which face a configurable widget was asked to lead with.
///
/// Nil on a placeholder entry, which has no configuration at all and still has
/// to render something.
public enum OnyxFocus: Sendable, Equatable {
  case fuel(FuelFocus)
  case training(TrainingFocus)
  case body(BodyFocus)
  case vitals(VitalsFocus)
  case lock(LockFocus)
  case progress(ProgressFocus)
}

public struct OnyxTileEntry: Sendable {
  public let date: Date
  public let snapshot: OnyxSnapshot?
  public var focus: OnyxFocus?
  /// The generic kind's pick (W5): which dashboard tile this entry draws. Nil
  /// on every family kind and on a placeholder, which has no configuration.
  public var tileId: WidgetId?

  public init(date: Date = Date(), snapshot: OnyxSnapshot?, focus: OnyxFocus? = nil) {
    self.date = date
    self.snapshot = snapshot
    self.focus = focus
  }

  /// How old the payload on screen actually is, from its own `generatedAt`.
  ///
  /// ── WHY THIS WAS MISSING AND WHY IT MATTERS ────────────────────────────────
  /// `generatedAt` has been in the payload since the first version and no Swift
  /// line ever read it. Staleness was `status != .ok` — purely "the last fetch
  /// failed" — so a payload fetched perfectly at 06:00 and still on screen at
  /// 14:00 carried no tag at all. That is the case that matters: a widget whose
  /// numbers are eight hours old and look confident is worse than one that
  /// admits it, because it is the confident one you act on.
  ///
  /// Nil when unparseable. An unknown age must never render as a fresh one.
  public var age: TimeInterval? {
    guard let iso = snapshot?.generatedAt,
          let then = OnyxSnapshot.timestamp(iso) else { return nil }
    return max(0, date.timeIntervalSince(then))
  }

  /// A snapshot that has simply been on screen too long. "Do not trust this to
  /// the minute"; the tag says how long.
  ///
  /// 45 minutes is chosen against the cadence table: longer than the densest
  /// band (20) so an ordinary refresh never trips it, shorter than the sparsest
  /// daytime one (45) so a skipped refresh does. A tag that appears during
  /// normal operation is a tag that gets ignored.
  public var isStale: Bool { snapshot != nil && (age ?? 0) > 45 * 60 }
  /// Nothing to draw at all — the diagnostic face takes over.
  public var isEmpty: Bool { snapshot == nil }

  /// The configured focus, or the family's default.
  public var fuelFocus: FuelFocus {
    if case .fuel(let f) = focus { return f }
    return .calories
  }
  public var trainingFocus: TrainingFocus {
    if case .training(let f) = focus { return f }
    return .today
  }
  public var bodyFocus: BodyFocus {
    if case .body(let f) = focus { return f }
    return .weight
  }
  public var vitalsFocus: VitalsFocus {
    if case .vitals(let f) = focus { return f }
    return .panel
  }
  public var lockFocus: LockFocus {
    if case .lock(let f) = focus { return f }
    return .battery
  }
  public var progressFocus: ProgressFocus {
    if case .progress(let f) = focus { return f }
    return .trajectory
  }

  public static func placeholder(_ date: Date = Date()) -> OnyxTileEntry {
    OnyxTileEntry(date: date, snapshot: nil, focus: nil)
  }
}

// MARK: - Focus enums
//
// ── WHAT THIS REPLACES ───────────────────────────────────────────────────────
// Seven widget kinds: five `StaticConfiguration` tiles (Fuel, Battery, Today,
// This Week, Battery-Lock) and two configurable composites (Lifestyle,
// Performance). The five statics each answered one question and largely
// duplicated a face that already existed inside a composite — "Today" was the
// Lifestyle ledger with a fixed focus, "This Week" was the Performance week
// with a fixed focus — so the gallery listed the same content three times and
// none of the copies could be reconfigured.
//
// Four families now, split by WHAT YOU ARE ASKING rather than by which screen
// the number came from:
//
//   Fuel      what is left to eat, and what it is made of
//   Training  what today is, how the month went, whether the streak holds
//   Body      the scale, the night, and how ready the whole thing is
//   Lock      the same facts at accessory size
//
// Plain enums here. The widget extension adds `AppEnum` conformance (the
// picker titles) in its own `OnyxIntents.swift` — a tile drawn inside the app
// must not drag AppIntents in with it.

public enum FuelFocus: String, CaseIterable, Sendable {
  case calories, macros, water

  /// ── WHY THESE TAKE A DATE NOW ──────────────────────────────────────────────
  /// A focus used to name a tab root, so the water face opened Nutrition and
  /// left you to find hydration — a shortcut that costs a navigation instead of
  /// saving one. The precise destinations live on the DAY page, which needs a
  /// date, and the only correct date is the payload's (`snapshot.date`): it is
  /// the user's logical day resolved server-side in their own timezone, where an
  /// extension calling `Date()` would open the wrong day for anyone whose
  /// logical day and calendar day differ.
  ///
  /// Nil date falls back to the tab root — a placeholder entry has no payload
  /// and still has to be tappable.
  public func link(_ date: String?) -> URL? {
    switch self {
    // Calories and macros belong to the Nutrition page, which is where they are
    // actually edited. Only water has a drawer on the day page.
    case .calories, .macros: return OnyxLink.nutrition
    case .water:             return date.flatMap { OnyxLink.day($0, section: "water") } ?? OnyxLink.nutrition
    }
  }
}

public enum TrainingFocus: String, CaseIterable, Sendable {
  case today, calendar, volume, streak, records, oneRepMax, cardio

  /// The scope follows the FOCUS, not the widget, so a calendar never pays to
  /// decode a ledger it does not draw.
  ///
  /// Volume sits with records and 1RM because its Large register is the
  /// per-muscle-family split, and `volumeByFamily` needs a `workout_sets` read
  /// that only the performance slice does. The eight-week tonnage trend it also
  /// needs is derived from sessions the route fetches in EVERY scope, so the
  /// server ships `volumeTrend` under both — which is what makes moving this
  /// focus lossless rather than a trade.
  public var scope: OnyxScope {
    switch self {
    case .records, .oneRepMax, .volume:       return .performance
    // Cardio rides with the training slice because that is where the route
    // builds it — one extra `cardio_logs` read beside the calendar, rather than
    // a fifth scope for a block this small.
    case .today, .calendar, .streak, .cardio: return .training
    }
  }

  /// See `FuelFocus.link(_:)` for why this takes the payload's date.
  public func link(_ date: String?) -> URL? {
    switch self {
    case .today:               return OnyxLink.workout
    case .calendar, .streak:   return OnyxLink.progress
    case .volume:              return OnyxLink.workout
    case .records, .oneRepMax: return OnyxLink.exercises
    // Cardio is logged ON the day, not in the workout deck.
    case .cardio:              return date.flatMap { OnyxLink.day($0) } ?? OnyxLink.progress
    }
  }
}

public enum BodyFocus: String, CaseIterable, Sendable {
  case weight, sleep, wellbeing, composition

  /// See `FuelFocus.link(_:)` for why this takes the payload's date.
  public func link(_ date: String?) -> URL? {
    switch self {
    // The night is a drawer on the day, not a section of Progress.
    case .sleep:                    return date.flatMap { OnyxLink.day($0, section: "sleep") } ?? OnyxLink.progress
    // The InBody form is where composition is entered, and the drawer the
    // dashboard's Body card already deep-links to.
    case .weight, .composition:     return date.flatMap { OnyxLink.day($0, section: "inbody") } ?? OnyxLink.progress
    // Well-being is a whole-of-Progress question; there is no one drawer for it.
    case .wellbeing:                return OnyxLink.progress
    }
  }
}

/// The Vitals panel's four cuts of the same seven readings.
///
/// Not one focus per reading. Five near-identical entries in a picker is a
/// menu you scroll rather than choose from, and the readings genuinely group:
/// HRV and resting heart rate are the same question about recovery, blood
/// oxygen and respiratory rate the same question about breathing.
public enum VitalsFocus: String, CaseIterable, Sendable {
  case panel, recovery, respiration, temperature

  /// See `FuelFocus.link(_:)` for why this takes the payload's date.
  ///
  /// All four land on the DAY, not on Progress: these are readings taken on one
  /// night, and the day drawer is where that night's numbers live. Progress is
  /// where trends live, which is a different question from "what happened".
  public func link(_ date: String?) -> URL? {
    date.flatMap { OnyxLink.day($0) } ?? OnyxLink.progress
  }
}

/// The block, at four angles — W12's family.
///
/// ── WHY A FIFTH FAMILY AND NOT FOUR MORE FOCUSES ────────────────────────────
/// Fuel, Training, Body and Lock each answer one QUESTION at several
/// granularities, and none of them asks this one. "Am I arriving", "am I
/// showing up", "does the ledger match the scale", "where did the battery go"
/// are four angles on a single question — is the block working — which is
/// exactly the shape a family is. Bolting them onto the existing four would
/// have put a weekly reconciliation behind a picker labelled "Fuel".
public enum ProgressFocus: String, CaseIterable, Sendable {
  case trajectory, consistency, deficit, fatigue

  /// The payload slice each face needs. An extension pays for every field it
  /// decodes in time and in resident memory, against a hard cap.
  public var scope: OnyxScope {
    switch self {
    case .trajectory, .fatigue: .body
    case .consistency:          .training
    case .deficit:              .lifestyle
    }
  }

  /// See `FuelFocus.link(_:)` for why this takes the payload's date.
  public func link(_ date: String?) -> URL? {
    switch self {
    // The trajectory and the ledger are the Goal Board's two numbers, and the
    // Goal Board is on Today.
    case .trajectory, .deficit: return OnyxLink.home
    case .consistency:          return OnyxLink.progress
    // Where the battery went is a recovery question, and it is asked about a
    // DAY — the fatigue and soreness rows that feed it live there.
    case .fatigue:              return date.flatMap { OnyxLink.day($0) } ?? OnyxLink.progress
    }
  }
}

public enum LockFocus: String, CaseIterable, Sendable {
  case battery, calories, steps, workout
  /// W5: last night's bedtime beside the clock — the one reading the Lock
  /// Screen is actually looked at for, at the hour it is decided.
  case bedtime

  /// See `FuelFocus.link(_:)` for why this takes the payload's date.
  ///
  /// The accessory faces stay on tab roots deliberately — a Lock Screen tap is
  /// made in a hurry, and landing inside a drawer you then have to dismiss is
  /// worse there than the extra navigation.
  public func link(_ date: String?) -> URL? {
    switch self {
    case .battery:  return OnyxLink.home
    case .calories: return OnyxLink.nutrition
    case .steps:    return OnyxLink.progress
    case .workout:  return OnyxLink.workout
    // The night lives on Progress with the rest of the sleep readings, and
    // the tab-root rule above holds for it.
    case .bedtime:  return OnyxLink.progress
    }
  }
}

// MARK: - Deep links
//
// ── WHY A WIDGET THAT OPENS THE HOME SCREEN IS A BROKEN WIDGET ───────────────
// A widget is a shortcut with a preview attached. Tapping the calorie ring and
// landing on the dashboard means the tap cost you a navigation instead of saving
// you one, and the surface stops being worth its slot. Every face below names a
// destination, and sub-regions of the Medium and Large faces name their own.
//
// The scheme is registered in the app's Info.plist (`CFBundleURLTypes`) and
// received by `.onOpenURL` in RootView through `DeepLink.safePath`.

public enum OnyxLink {
  /// The destination is a PATH, carried as a query parameter rather than a
  /// host — `onyx://nutrition` would make "nutrition" a host and lose
  /// everything after the first slash.
  public static func path(_ path: String) -> URL? {
    var c = URLComponents()
    c.scheme = "onyx"
    c.host = "open"
    c.queryItems = [URLQueryItem(name: "path", value: path)]
    return c.url
  }

  public static let home      = path("/")
  public static let nutrition = path("/nutrition")
  public static let micros    = path("/nutrition/micros")
  /// "Progress" — vitals, sleep, weight and the body trends all live here.
  public static let progress  = path("/pathfinder")
  public static let workout   = path("/workout")
  public static let exercises = path("/workout/exercises")
  public static let reports   = path("/reports")

  /// One day, optionally with a drawer already open.
  ///
  /// ── WHY THE TAP HAS TO LAND ON THE THING YOU TAPPED ──────────────────────
  /// Every face used to point at a tab root: the sleep face opened Progress and
  /// left you to find last night, the water face opened Nutrition and left you
  /// to find hydration. That is a shortcut that costs a navigation instead of
  /// saving one. `section` names the drawer, and the day page validates it
  /// against `DAY_SECTIONS` — an unknown one opens the day with nothing open
  /// rather than guessing.
  ///
  /// ── AND WHY THE DATE IS PASSED IN ────────────────────────────────────────
  /// Always from `snapshot.date`, never from `Date()` in the extension. The
  /// payload's date is the user's LOGICAL day, resolved server-side in their own
  /// timezone; an extension deciding for itself would open the wrong day for
  /// anyone whose logical day and calendar day differ — which is most people,
  /// for part of every day.
  public static func day(_ iso: String, section: String? = nil) -> URL? {
    guard !iso.isEmpty else { return nil }
    return path(section.map { "/day/\(iso)?section=\($0)" } ?? "/day/\(iso)")
  }
}

#endif
