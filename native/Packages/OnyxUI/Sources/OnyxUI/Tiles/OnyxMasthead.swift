import SwiftUI
import OnyxCore

// MARK: - The session masthead (overhaul B3, decision Q3 · concepts 5 + 8)
//
// ── ONE FACE FOR EVERY "THE SESSION, IN ONE LINE" ────────────────────────────
// A session's headline used to be spelled five ways: "DONE" in the Today
// widget's caption, "done" in the Lock Screen accessory, "done · 12.4 t" in the
// Daily quadrant, "Legs & Core B ✓" in the Fuel ledger, and a bespoke header in
// the Live Activity. Each clipped a different way, and all of them by the same
// mechanism — `lineLimit(1)` on a name that was sometimes "Legs & Core B".
//
// This is the one face: name · duration · tonnage · heart rate · records. It
// measures itself (`ViewThatFits`, three tiers) and the NAME NEVER TRUNCATES:
// it wraps to two lines first, then the figures shrink under it.
//
//   wide     the name, then the four figures on one row
//   medium   the name, then the figures as a 2 × 2
//   narrow   the name, then the figures as a 2 × 2 in caption type
//
// Consumers: the Today widget's post-workout Medium/Large and Small, the Live
// Activity's expanded state and the Dynamic Island's expanded region. Lane C's
// `SessionHeaderCard` and Lane A's watch banner take it through the
// `SessionMasthead` initialiser. Heart is `OnyxInk.Fixed.heart` in every theme;
// the trophy is `record` gold.
//
// Cross-platform on purpose (no `OnyxWidgetType`, which is iOS-only): the watch
// banner is the same face at 40 mm.

public struct OnyxMasthead: View {
  /// A finished session's length, or a running clock (the Live Activity).
  public enum Clock: Hashable, Sendable {
    case elapsed(seconds: Int)
    case running(since: Date)
    /// A paused live session: the time as the producer froze it.
    case frozen(String)
  }

  let name: String
  let clock: Clock?
  let tonnage: String?
  let bpm: Int?
  let prCount: Int
  /// The session's own colour — the day's ink — for the name's leading bar.
  let accent: Color
  /// "avg" under a finished session, the live reading under a running one.
  let bpmIsAverage: Bool

  public init(
    name: String, clock: Clock?, tonnage: String?, bpm: Int?, prCount: Int,
    accent: Color, bpmIsAverage: Bool = true
  ) {
    self.name = name
    self.clock = clock
    self.tonnage = tonnage
    self.bpm = bpm
    self.prCount = prCount
    self.accent = accent
    self.bpmIsAverage = bpmIsAverage
  }

  /// The wire model (OnyxCore) — what Lane A's banner and Lane C's summary
  /// header already hold.
  public init(_ m: SessionMasthead, accent: Color) {
    self.init(
      name: m.name, clock: .elapsed(seconds: m.durationSec),
      tonnage: OnyxSnapshot.tonnes(m.tonnageKg > 0 ? m.tonnageKg : nil),
      bpm: m.avgBpm, prCount: m.prCount, accent: accent
    )
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      title
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 14) {
          ForEach(Array(figures(.subheadline).enumerated()), id: \.offset) { $0.element }
        }
        grid(.subheadline)
        grid(.caption)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spoken)
  }

  /// Wraps to two lines, never truncates — then gives up size, not letters.
  private var title: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        .fill(accent)
        .frame(width: 3, height: 14)
        .accessibilityHidden(true)
      Text(name.isEmpty ? "Session" : name)
        .font(.headline)
        .foregroundStyle(Color.onyx.textPrimary)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func grid(_ style: Font.TextStyle) -> some View {
    let cells = Array(figures(style).enumerated())
    return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
      ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { i in
        GridRow {
          cells[i].element
          if i + 1 < cells.count { cells[i + 1].element } else { Color.clear.frame(width: 0, height: 0) }
        }
      }
    }
  }

  /// The figures that exist — a session with no heart rate or no record
  /// simply has fewer, rather than a "—" holding a cell.
  private func figures(_ style: Font.TextStyle) -> [AnyView] {
    var out: [AnyView] = []
    if let clock {
      out.append(AnyView(Figure(symbol: "clock", tint: Color.onyx.textSecondary, style: style) {
        switch clock {
        case .elapsed(let seconds): Text(Self.duration(seconds))
        case .running(let since): Text(since, style: .timer)
        case .frozen(let text): Text(text)
        }
      }))
    }
    if let tonnage {
      out.append(AnyView(Figure(symbol: "scalemass", tint: Color.onyx.textSecondary, style: style) { Text(tonnage) }))
    }
    if let bpm {
      out.append(AnyView(Figure(symbol: "heart.fill", tint: OnyxInk.Fixed.heart, style: style) {
        Text("\(bpm)") + Text(bpmIsAverage ? " avg" : " bpm").foregroundStyle(Color.onyx.textSecondary)
      }))
    }
    if prCount > 0 {
      out.append(AnyView(Figure(symbol: "trophy.fill", tint: OnyxInk.Fixed.record, style: style) {
        Text(prCount == 1 ? "PR" : "\(prCount) PRs")
      }))
    }
    return out
  }

  /// "52 min", "1 h 04".
  static func duration(_ seconds: Int) -> String {
    let m = max(0, seconds) / 60
    return m < 60 ? "\(m) min" : String(format: "%d h %02d", m / 60, m % 60)
  }

  private var spoken: String {
    var parts = [name.isEmpty ? "Session" : name]
    if case .elapsed(let s)? = clock { parts.append("\(max(0, s) / 60) minutes") }
    if let tonnage { parts.append(tonnage) }
    if let bpm { parts.append(bpmIsAverage ? "average heart rate \(bpm)" : "heart rate \(bpm)") }
    if prCount > 0 { parts.append(prCount == 1 ? "1 record" : "\(prCount) records") }
    return parts.joined(separator: ", ")
  }
}

/// One figure: a glyph in its ink, a value in monospaced digits.
private struct Figure<Value: View>: View {
  let symbol: String
  let tint: Color
  let style: Font.TextStyle
  @ViewBuilder let value: () -> Value

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: symbol)
        .font(.system(style, weight: .semibold))
        .imageScale(.small)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      value()
        .font(.system(style, weight: .semibold).monospacedDigit())
        .foregroundStyle(Color.onyx.textPrimary)
        .lineLimit(1)
    }
    .fixedSize()
  }
}
