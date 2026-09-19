import AppIntents
import WidgetKit
import OnyxCore
import OnyxUI

// MARK: - The Lock Screen accessory's picker
//
// ── WHAT USED TO BE HERE, AND WHY IT IS NOT (W12) ───────────────────────────
// Six Home Screen family kinds — Fuel, Training, Body, Progress, Daily and
// Vitals — each with its own `WidgetConfigurationIntent` and its own `AppEnum`
// focus picker. W5 replaced all six with ONE kind whose picker is the tile
// itself (`TileConfiguration`, below), because the dashboard tiles ARE the
// widget faces (`OnyxTile.face`) and a gallery that lists the same face under
// six different family names is a gallery that lists it six times.
//
// They stayed one full release as shells so a widget placed on 6.1.0 kept
// drawing on 6.2.0; this is the release after, and the founder has confirmed
// the cycle. The FACES are untouched and live where they always did, in
// `OnyxUI/Tiles/` — only the six gallery entries and their pickers are gone.
//
// ⚠️ Deleting a kind removes any already-placed instance of it from the Home
// Screen. Anything still on one of the six has to be added again, once, from
// the single "Onyx" entry.
//
// These are `AppEnum`, not `AppEntity`. An entity is for a queryable collection
// with identity; these are fixed choices and the picker should be a plain list,
// which is what an enum gets you for free.

// ── WHY THIS IS NOT THE OnyxUI ENUM ────────────────────────────────────────
// The tiles' focus enums (`LockFocus` …) live in OnyxUI so a view can name its
// face without importing AppIntents. `AppEnum` cannot be added to them from
// here: the AppIntents metadata extractor that runs at build time refuses an
// enum "implemented in an imported framework or library". So the picker has
// its own one-line enum, same raw values, and `focus` bridges. The display
// strings are the only thing that lives here.

enum LockFocusOption: String, AppEnum {
  case battery, calories, steps, workout, bedtime

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
  static let caseDisplayRepresentations: [LockFocusOption: DisplayRepresentation] = [
    .battery:  DisplayRepresentation(title: "Battery", subtitle: "Recovery battery as a gauge"),
    .calories: DisplayRepresentation(title: "Calories", subtitle: "Calories left today"),
    .steps:    DisplayRepresentation(title: "Steps", subtitle: "Steps against the goal"),
    .workout:  DisplayRepresentation(title: "Workout", subtitle: "Today's session, or rest"),
    .bedtime:  DisplayRepresentation(title: "Bedtime", subtitle: "When you went to bed last night"),
  ]

  /// The tile's own enum. Same raw values by construction; a case added on one
  /// side without the other is a crash here, on the first render, loudly.
  var focus: LockFocus { LockFocus(rawValue: rawValue)! }
}

// MARK: - Configurations

struct LockConfiguration: WidgetConfigurationIntent, OnyxScoped {
  static var title: LocalizedStringResource { "Onyx Lock" }
  static var description: IntentDescription {
    IntentDescription("One fact on the Lock Screen: battery, calories, steps or today's session.")
  }

  @Parameter(title: "Show", default: .battery)
  var focus: LockFocusOption

  /// The lifestyle slice covers all four accessory faces — none of them needs a
  /// calendar, a ledger or a trend.
  var scope: OnyxScope { .lifestyle }
  var onyxFocus: OnyxFocus { .lock(focus.focus) }

  static var galleryOptions: [(intent: LockConfiguration, title: LocalizedStringResource)] {
    [(recommendation(.battery), "Battery"),
     (recommendation(.calories), "Calories"),
     (recommendation(.steps), "Steps"),
     (recommendation(.workout), "Workout"),
     (recommendation(.bedtime), "Bedtime")]
  }

  static func recommendation(_ focus: LockFocusOption) -> LockConfiguration {
    let intent = LockConfiguration()
    intent.focus = focus
    return intent
  }
}


// MARK: - The generic kind (W5)
//
// ── ONE KIND, EVERY TILE ─────────────────────────────────────────────────────
// Six Home Screen families were the gallery's answer before the dashboard
// tiles WERE the widget faces. Now that they are (`OnyxTile.face`), the only
// honest gallery entry is "a tile", with the tile as its picker: every
// `WidgetId` the phone can draw, in catalogue order, under the name the Today
// grid gives it. The families were shells for one release and are gone as of
// W12; the Lock Screen accessory above is a different shape and stays.

/// `WidgetId`, for the picker.
///
/// The AppIntents extractor refuses an enum "implemented in an imported
/// framework or library", so — like every focus option above — this is the
/// same raw values spelled again here, and `id` bridges. Every NATIVE id
/// (`OnyxTile.native`) and nothing else: `bar`, `micros` and `stack` have no
/// face, and an option that draws "No face for this one yet" is not an option.
/// `weekRings` keeps its camelCase because the raw value is the bridge.
enum TileOption: String, AppEnum {
  case recovery, sleep, vitals, fuel, water, deficit, train
  case body, trajectory, muscle, volume, pr, consistency, steps, cardio, fatigue
  case weekRings, soreness, stress, bedtime
  case daily

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tile"

  /// Display names = `WidgetId.title`, the Today grid's own captions, so the
  /// picker and the dashboard call one tile one thing.
  ///
  /// Spelled out rather than derived: the AppIntents metadata extractor reads
  /// this dictionary at BUILD time and halts on anything but a literal
  /// ("Value of 'caseDisplayRepresentations' must be a dictionary"). A title
  /// changed in `OnyxTile.swift` has to be changed here too.
  static let caseDisplayRepresentations: [TileOption: DisplayRepresentation] = [
    .recovery:    "Recovery",
    .sleep:       "Sleep",
    .vitals:      "Vitals",
    .fuel:        "Fuel",
    .water:       "Water",
    .deficit:     "Deficit Ledger",
    .train:       "Workout",
    .body:        "Body",
    .trajectory:  "Trajectory",
    .muscle:      "Muscle Focus",
    .volume:      "Tonnage",
    .pr:          "Latest PR",
    .consistency: "Consistency",
    .steps:       "Steps",
    .cardio:      "Cardio",
    .fatigue:     "Fatigue",
    .weekRings:   "Week Rings",
    .soreness:    "Soreness",
    .stress:      "Stress",
    .bedtime:     "Bedtime",
    .daily:       "Day Rings",
  ]

  /// The catalogue's own id. Same raw values by construction; a native id
  /// missing here is invisible in the picker, and a case here that the
  /// catalogue lacks is a crash on the first render, loudly.
  var id: WidgetId { WidgetId(rawValue: rawValue)! }
}

struct TileConfiguration: WidgetConfigurationIntent, OnyxScoped {
  static var title: LocalizedStringResource { "Onyx" }
  static var description: IntentDescription {
    IntentDescription("Any tile from the Today dashboard, on the Home Screen.")
  }

  @Parameter(title: "Tile", default: .train)
  var tile: TileOption

  /// ponytail: `.full` for every tile — the whole payload per timeline. A
  /// per-id scope map (`recovery`→`.body`, `pr`→`.performance` …) is the
  /// upgrade if timelines get slow; `stressSeries` and `batteryStackSlice`
  /// are the two reads that would show it first (W4's record).
  var scope: OnyxScope { .full }
  /// `OnyxScoped` wants a focus; the face is chosen by `tile`, not by this.
  var onyxFocus: OnyxFocus { .training(.today) }

  /// One gallery tile per native id, in catalogue order.
  static var galleryOptions: [(intent: TileConfiguration, title: LocalizedStringResource)] {
    OnyxTile.native.map { id in
      (recommendation(TileOption(rawValue: id.rawValue)!), "\(id.title)")
    }
  }

  static func recommendation(_ tile: TileOption) -> TileConfiguration {
    let intent = TileConfiguration()
    intent.tile = tile
    return intent
  }
}
