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

  // ── ONE FACE, BOTH DEVICES (W7) ────────────────────────────────────────────
  // The drawing moved to `Accessory/OnyxAccessory.swift`, which is unfenced
  // and is also the watch's complication. This view is the phone's adapter:
  // it maps the Lock Screen kind's focus onto the `WidgetId` the face draws,
  // cuts the snapshot down to `WatchTiles` — the same projection the phone
  // sends the wrist — and keeps the deep link, which only a phone can open.
  public var body: some View {
    OnyxTile.accessory(focus.widgetId, family: family, tiles: entry.snapshot.map(WatchTiles.init))
      .widgetURL(focus.link(entry.snapshot?.date))
  }
}

extension LockFocus {
  /// The tile each Lock Screen focus has always been a face of.
  var widgetId: WidgetId {
    switch self {
    case .battery: .recovery
    case .calories: .fuel
    case .steps: .steps
    case .workout: .train
    case .bedtime: .bedtime
    }
  }
}

#endif
