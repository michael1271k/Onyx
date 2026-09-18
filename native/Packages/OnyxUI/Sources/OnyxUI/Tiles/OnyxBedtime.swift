// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import SwiftUI
import WidgetKit
import OnyxCore

// MARK: - Bedtime (D3)
//
// When you went to bed, when you got up, and when you usually go.
//
// ── WHAT THIS TILE IS FOR ───────────────────────────────────────────────────
// Sleep v2 grades REGULARITY — fifteen of the hundred, against the median of
// the fortnight before tonight — and until this face existed that baseline was
// a number the athlete was marked on and could not see. One clock time under
// the night's own is the whole of it: the reading is the gap between them, and
// a reader does that subtraction faster than any phrase we could write for it.
//
// ── AND WHY NO "+46 m LATER" CHIP ───────────────────────────────────────────
// Signing that delta means subtracting two clock times across midnight, which
// is exactly the arithmetic `bedtimeOffsets` exists so that nothing has to do
// (23:30 and 00:16 are forty-six minutes apart and look like twenty-three
// hours). The offsets are minutes past a UTC noon and the payload carries only
// the rendered string, so a face computing the delta would be re-deriving it
// from the one form that cannot be subtracted. If the chip is ever wanted, the
// signed delta belongs in the payload beside `medianBedtime`, computed where
// the offsets still are.
//
// One size, and it is the Small: two clock times and a caption is a Small's
// worth of content at every size, and a Medium of it is a Small with a hole.

public struct BedtimeView: View {
  let entry: OnyxTileEntry
  @Environment(\.widgetRenderingMode) private var mode
  private var mono: Bool { mode == .accented }

  public init(entry: OnyxTileEntry) { self.entry = entry }

  private var sleep: OnyxSnapshot.Sleep? { entry.snapshot?.sleep }
  private var accent: Color { mono ? .white : OnyxDomain.recover.accent }

  public var body: some View {
    Group {
      if entry.isEmpty { Unavailable() } else { face }
    }
    .onyxMarked(monochrome: mono, hidden: entry.isStale)
  }

  private var face: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption("BEDTIME", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      Spacer(minLength: 0)

      // `clockTime` renders in the DEVICE's zone. A bedtime read in UTC on a
      // phone in Jerusalem is three hours wrong, every night.
      BigValue(value: OnyxSnapshot.clockTime(sleep?.startTime), size: 34, color: Color.onyx.textPrimary)

      if let wake = OnyxSnapshot.clockTime(sleep?.endTime) {
        HStack(spacing: 3) {
          Image(systemName: "sunrise.fill")
            .font(OnyxWidgetType.face(9))
            .foregroundStyle(accent)
          Text(wake)
            .font(OnyxWidgetType.figure(12))
            .foregroundStyle(Color.onyx.textSecondary)
        }
      }

      Spacer(minLength: 0)
      Hairline()

      // "Usually 23:30", or the honest absence of it: the median refuses a
      // baseline under five nights, and a first week that invented one would
      // be marking a regularity the athlete has not had time to have.
      Text(sleep?.medianBedtime.map { "Usually \($0)" } ?? "No usual bedtime yet")
        .font(OnyxWidgetType.face(10, weight: .semibold))
        .foregroundStyle(Color.onyx.textSecondary)
        .lineLimit(1).minimumScaleFactor(0.8)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Bedtime")
    .accessibilityValue(speech)
  }

  private var speech: String {
    var parts: [String] = []
    parts.append(OnyxSnapshot.clockTime(sleep?.startTime).map { "in bed at \($0)" } ?? "no bedtime recorded")
    if let wake = OnyxSnapshot.clockTime(sleep?.endTime) { parts.append("up at \(wake)") }
    if let usual = sleep?.medianBedtime { parts.append("usually \(usual)") }
    return parts.joined(separator: ", ")
  }
}

#endif
