import AppIntents
import os
import WidgetKit
import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

// MARK: - The store

/// The extension's one door onto the App Group database.
///
/// ── READ-ONLY, AND WHY THAT IS NOT A LIMITATION ──────────────────────────────
/// The app writes `onyx.sqlite` in the shared container; the extension opens
/// the same file with `readonly = true` and never runs a migration — two
/// processes migrating one schema is a race with no winner. There is no cache
/// layer here on purpose: the database IS the cache. The old extension fetched
/// `/api/widget/snapshot` and kept the last good JSON on disk for when the
/// network failed; a local file has no network to fail.
///
/// Opened once per extension process. WidgetKit spins the process up, asks for
/// a timeline or two, and tears it down; a pool held for that lifetime costs
/// nothing and saves a file open per widget kind.
enum WidgetStore {
  /// A lock, not a `static let`: WidgetKit asks every kind for its timeline at
  /// once, on whatever executor it likes, and a `static let` would also cache a
  /// FAILURE (no database yet, before the first sign-in) for the life of the
  /// process. Only a successful open is kept.
  private static let cached = OSAllocatedUnfairLock<(db: AppDatabase, userId: String)?>(initialState: nil)

  /// The snapshot for a scope, or nil when there is nothing to read yet — a
  /// fresh install before the first sign-in, or a free-team build with no App
  /// Group container. Nil renders as the empty face, never as zeros.
  static func snapshot(scope: OnyxScope, now: Date = Date()) -> OnyxSnapshot? {
    do {
      let (db, userId) = try open()
      return try WidgetSnapshotBuilder(database: db, userId: userId).build(scope: scope, now: now)
    } catch {
      return nil
    }
  }

  private static func open() throws -> (AppDatabase, String) {
    try cached.withLock { slot in
      if let slot { return slot }
      let db = try AppDatabase.readOnly(folderURL: AppDatabase.sharedFolder())
      guard let userId = try db.knownUserId() else { throw WidgetStoreError.noUser }
      slot = (db, userId)
      return (db, userId)
    }
  }

  enum WidgetStoreError: Error { case noUser }
}

// MARK: - Timeline

/// One tile's entry. `OnyxTileEntry` (OnyxUI) is what the views draw from;
/// this is the same thing with WidgetKit's `TimelineEntry` stamped on it, kept
/// out of the package so OnyxUI stays a library of views rather than a widget.
struct OnyxEntry: TimelineEntry {
  let tile: OnyxTileEntry
  var date: Date { tile.date }

  static func placeholder(_ date: Date = Date()) -> OnyxEntry {
    OnyxEntry(tile: OnyxTileEntry(date: date, snapshot: nil, focus: nil))
  }
}

/// The one provider. `AppIntentTimelineProvider` receives the configuration
/// alongside the context, which plain `TimelineProvider` does not.
///
/// The generic carries the intent AND the scope it implies, so a Fuel widget
/// never builds the Training slice.
struct OnyxIntentProvider<Configuration: WidgetConfigurationIntent & OnyxScoped>: AppIntentTimelineProvider {
  // `TimelineProviderContext` is spelled out because OnyxCore exports a
  // `Context` (the nutrition one) that shadows `Self.Context` here — and the
  // compiler's only word on that is "does not conform", naming no shadow.
  typealias Intent = Configuration
  typealias Entry = OnyxEntry

  func placeholder(in context: TimelineProviderContext) -> OnyxEntry { .placeholder() }

  func snapshot(for configuration: Configuration, in context: TimelineProviderContext) async -> OnyxEntry {
    await Self.theme()
    return entry(for: configuration)
  }

  /// Re-read the theme the app persisted to the App Group.
  ///
  /// The bundle's `init` cannot be relied on for this: `reloadAllTimelines()`
  /// re-runs the provider, and WidgetKit may serve it from an extension process
  /// that is already running — one whose `OnyxTheme.current` is the palette
  /// from before the user picked a new one. Nearly free in that case; see the
  /// note on `OnyxWidgets.init`.
  private static func theme() async {
    await MainActor.run {
      OnyxTheme.load(AppDatabase.appGroupDefaults())
    }
  }

  /// ── THE TIMELINE IS A SAFETY NET, NOT THE REFRESH ──────────────────────────
  /// The app calls `WidgetCenter.reloadAllTimelines()` after every local write
  /// (`AppDatabase.onCommit` in `AppEnvironment`), so a tile is fresh the moment
  /// a set is logged or a meal is saved. The cadence below only exists for what
  /// changes WITHOUT a write — the battery decaying with hours awake — and it
  /// spends the 40–70 daily refresh grant where the day is (`WidgetCadence`).
  func timeline(for configuration: Configuration, in context: TimelineProviderContext) async -> Timeline<OnyxEntry> {
    await Self.theme()
    let entry = entry(for: configuration)
    return Timeline(entries: [entry], policy: .after(WidgetCadence.nextRefresh(ok: entry.tile.snapshot != nil)))
  }

  private func entry(for configuration: Configuration) -> OnyxEntry {
    let now = Date()
    let snap = WidgetStore.snapshot(scope: configuration.scope, now: now)
    return OnyxEntry(tile: OnyxTileEntry(date: now, snapshot: snap, focus: configuration.onyxFocus))
  }

  /// One gallery tile per focus.
  ///
  /// Without this the gallery shows a single generic preview per KIND, so a
  /// family's focuses are invisible until after you have placed one and gone
  /// looking for "Edit Widget" — the choice is hidden at exactly the moment it
  /// is being made.
  func recommendations() -> [AppIntentRecommendation<Configuration>] {
    Configuration.galleryOptions.map { AppIntentRecommendation(intent: $0.intent, description: $0.title) }
  }
}

/// An intent that knows which slice of the payload its widget reads, which face
/// it was configured to lead with, and what to offer in the gallery.
protocol OnyxScoped {
  var scope: OnyxScope { get }
  var onyxFocus: OnyxFocus { get }
  /// One entry per focus, in the order the gallery should list them.
  static var galleryOptions: [(intent: Self, title: LocalizedStringResource)] { get }
}
