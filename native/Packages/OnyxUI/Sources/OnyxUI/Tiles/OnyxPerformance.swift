// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import WidgetKit
import SwiftUI
import OnyxCore

// MARK: - Performance faces
//
// The Training family's `records` and `oneRepMax` focuses. They kept their own
// file and their own payload slice — records and estimated 1RM are the only
// faces that need the performance scope, and a calendar should not pay to decode
// a ledger it never draws (see `TrainingFocus.scope`).
//
// ── WHY THESE TWO FOCUSES USED TO BE ONE ─────────────────────────────────────
// There was a `PerfFace` enum here too, and `PerfLedgerFace` took it — then read
// it only to choose a deep LINK, never to choose content. So the Records Medium
// and the 1RM Medium rendered the same four rows of week totals, and at Large
// both routed to `RecordGridFace`. Picking "Estimated 1RM" got you the record
// book at every size above Small.
//
// The enum is gone. Each focus has its own face at each size, and the numbers
// they draw are different numbers: records are a LEDGER of things that happened
// on a date, 1RM is a CURRENT ESTIMATE per lift with a direction of travel.

// MARK: - Axis vocabulary
//
// ── WHY A 440 kg ROMANIAN DEADLIFT APPEARED IN THE RECORD BOOK ───────────────
// `personal_records` carries four axes and the newest rows are usually `volume`
// and `e1rm`, not `weight`. The formatter had cases for `reps` and `seconds` and
// sent everything else to `String(format: "%.1f kg")` — so a 440 kg per-SET
// VOLUME record and a 54.7 kg ESTIMATED 1RM both printed as bare loads. One of
// those is a number nobody has ever lifted.
//
// The fix is not a longer value string; it is a second line. The value keeps its
// unit and the AXIS gets named underneath, so the reader is told which of the
// four kinds of record they are looking at.

// Public since the dashboard's Records SHEET draws the same rows: a record
// must read identically on the Home Screen and on the page listing the whole
// book, and two formatters is how "440 kg" becomes "440.0 kg" on one of them.
extension OnyxSnapshot.Record {
  /// The figure with the unit its axis implies — and nothing else, so it stays
  /// legible at 28pt.
  public var display: String {
    switch axis {
    case "reps":    return "\(Int(value.rounded()))"
    case "seconds": return "\(Int(value.rounded()))s"
    case "volume":  return "\(Int(value.rounded())) kg"
    default:        return String(format: "%.1f kg", value)
    }
  }

  /// Which KIND of record this is, in two words. This is the half that was
  /// missing, and the half that stops a set volume reading as a load.
  public var axisLabel: String {
    switch axis {
    case "weight":  return "heaviest load"
    case "e1rm":    return "est. 1RM"
    case "volume":  return "set volume"
    case "reps":    return "most reps"
    case "seconds": return "longest hold"
    default:        return axis
    }
  }

  /// "+5.0 kg" — how far past the bar it cleared this record stands, in the
  /// axis's own units (W6).
  ///
  /// ── WHY THE MARGIN AND NOT THE DATE ──────────────────────────────────────
  /// "yesterday" says the record is fresh and says nothing about it. The margin
  /// is what makes a PR a result rather than a notification: 32.5 kg is a
  /// number, and 32.5 kg where 30 stood is a sentence.
  ///
  /// The bar is `Record.previous` — the standing mark the book held, not "last
  /// time". `OnyxSnapshot.Record.previous` says why the second thing does not
  /// exist in the schema; `marginCaption` is the wording that keeps this
  /// honest wherever there is room for it.
  ///
  /// Nil when nothing stood before it, and nil when the record did not clear
  /// its own floor — the face prints "first on the board" rather than a
  /// manufactured or a negative gain. Sub-unit margins still print: a record
  /// taken by half a kilo is still a record, and rounding it to "+0" would say
  /// the opposite.
  public var marginText: String? {
    guard let margin, margin > 0 else { return nil }
    switch axis {
    case "reps":    return "+\(Int(margin.rounded())) reps"
    case "seconds": return "+\(Int(margin.rounded()))s"
    case "volume":  return "+\(Int(margin.rounded())) kg"
    default:        return "+" + String(format: "%.1f kg", margin)
    }
  }

  /// "past 100.0 kg on the book", for a face with a line to spare. What the
  /// margin is measured FROM, so the number above it cannot be read as a
  /// delta against the last session.
  public var marginCaption: String? {
    guard margin != nil, let previous else { return nil }
    switch axis {
    case "reps":    return "past \(Int(previous.rounded())) reps on the book"
    case "seconds": return "past \(Int(previous.rounded()))s on the book"
    case "volume":  return "past \(Int(previous.rounded())) kg on the book"
    default:        return String(format: "past %.1f kg on the book", previous)
    }
  }

  /// The axis as a glyph. Four axes and four shapes, so a ROW says which kind of
  /// record it is without spending a word of its width on the label.
  public var axisSymbol: String {
    switch axis {
    case "weight": return "scalemass.fill"
    case "reps":   return "repeat"
    case "volume": return "square.stack.3d.up.fill"
    case "e1rm":   return "chart.line.uptrend.xyaxis"
    default:       return "trophy.fill"
    }
  }
}

// MARK: - Records · one trophy
//
// ── WHAT A RECORD TILE IS FOR ────────────────────────────────────────────────
// The Small printed a figure, an axis label, a lift name, a date and a weekly
// count — five lines about one event, none of them saying what the event was
// worth. The Medium led with the weekly COUNT and put the records themselves in
// a column beside it, so the tile called "Latest PR" led with an integer that
// was usually 0, 1 or 2.
//
// One trophy now: the lift, the figure, and the margin it beat. `Record.previous`
// (W6) is what makes the margin possible, and the margin is the whole reading —
// see `marginText`.

/// One record, as a trophy. The shared face: the Small draws one and the Medium
/// stacks three, so a record reads identically wherever it appears.
struct TrophyFace: View {
  let record: OnyxSnapshot.Record
  let mono: Bool
  /// The Medium's three stacked rows. The Small draws ONE trophy with the whole
  /// face to itself and gets the taller, roomier arrangement.
  var compact = false

  private var gold: Color { mono ? .white : Color.onyx.record }
  /// A margin is a gain, so it wears `good` — except in `.accented` rendering,
  /// where every tile is one tint and a green figure reads as a rendering fault
  /// rather than as a verdict (the `mono ? .white` rule).
  private var marginInk: Color {
    if mono { return .white }
    return record.marginText == nil ? Color.onyx.textSecondary : Color.onyx.good
  }

  var body: some View {
    if compact { row } else { column }
  }

  /// Medium · a row. Icon, name, and the figure with its margin beside it.
  private var row: some View {
    HStack(alignment: .center, spacing: 8) {
      Image(systemName: "trophy.fill")
        .font(OnyxWidgetType.face(13))
        .foregroundStyle(gold)
        .frame(width: 16)
      VStack(alignment: .leading, spacing: 0) {
        Text(record.exercise)
          .font(OnyxWidgetType.face(10, weight: .semibold))
          .foregroundStyle(Color.onyx.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Text(record.axisLabel)
          .font(OnyxWidgetType.face(8))
          .foregroundStyle(Color.onyx.textSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      Text(record.display)
        .font(OnyxWidgetType.hero(15))
        .foregroundStyle(gold)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(record.marginText ?? "1st")
        .font(OnyxWidgetType.face(9, weight: .bold))
        .foregroundStyle(marginInk)
        .frame(width: 52, alignment: .trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
  }

  /// Small · a column.
  ///
  /// ── WHY NOT THE ROW, BIGGER ───────────────────────────────────────────────
  /// It WAS the row, bigger, and it did not fit: a Small's content is about
  /// 134 pt wide, and "32.5 kg" at 24 pt plus "+2.5 kg" beside it is 130 before
  /// the trophy has been drawn. The first shot of this face read "32…". The
  /// figure gets its own line, which is also what one-figure-per-face means.
  private var column: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Image(systemName: "trophy.fill")
          .font(OnyxWidgetType.face(12))
          .foregroundStyle(gold)
        Text(record.exercise)
          .font(OnyxWidgetType.face(11, weight: .semibold))
          .foregroundStyle(Color.onyx.textPrimary)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
      }
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(record.display)
          .font(OnyxWidgetType.hero(20))
          .foregroundStyle(gold)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        // The margin, or the honest absence of one. Never a date in its place:
        // `relativeDay` says the record is fresh and nothing about how much of
        // a record it is.
        Text(record.marginText ?? "first on the board")
          .font(OnyxWidgetType.face(10, weight: .bold))
          .foregroundStyle(marginInk)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      Text([record.axisLabel, OnyxSnapshot.relativeDay(record.achievedOn)]
             .compactMap { $0 }.joined(separator: " · "))
        .font(OnyxWidgetType.face(9))
        .foregroundStyle(Color.onyx.textSecondary)
        .lineLimit(1)
      // What the margin is measured FROM, so the number above it cannot be read
      // as a delta against the last session. Only here: the Medium's three rows
      // have no line to spare and drop it rather than truncate it.
      if let caption = record.marginCaption {
        Text(caption)
          .font(OnyxWidgetType.face(8))
          .foregroundStyle(Color.onyx.textTertiary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
    }
  }
}

/// Small · one trophy.
struct RecordFocusFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var top: OnyxSnapshot.Record? { s?.records?.first }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption("LATEST PR", color: mono ? .white : Color.onyx.record)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      if let top {
        Spacer(minLength: 0)
        TrophyFace(record: top, mono: mono)
        Spacer(minLength: 0)
        if let prs = s?.week.prs, prs > 0 {
          Text("\(prs) this week")
            .font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
        }
      } else {
        // A week without a record is an ordinary week, not a failure.
        Text("no records in the book yet")
          .font(OnyxWidgetType.face(11)).foregroundStyle(Color.onyx.textSecondary)
        Spacer(minLength: 0)
      }
    }
  }
}

// MARK: - Records · Medium
//
// Three trophies, stacked. The old Medium led with `week.prs` against
// `weekPrev.prs` — a count, with a delta of a count — and put the records
// themselves in a 40 % column beside it. The count is still there, as a caption
// on the header where a count belongs; the width goes to the records.

struct RecordLedgerFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var accent: Color { mono ? .white : Color.onyx.record }
  private var records: [OnyxSnapshot.Record] { s?.records ?? [] }

  private var prDelta: Double? {
    guard let now = s?.week.prs, let then = s?.weekPrev?.prs else { return nil }
    return Double(now - then)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Caption("RECORDS", color: accent)
        Spacer(minLength: 0)
        // The week's count, as a caption. It is context for the trophies below
        // and not a reading of its own, so it is typed as one.
        if let week = s?.week {
          Text("\(week.prs) this week")
            .font(OnyxWidgetType.face(9, weight: .semibold))
            .foregroundStyle(Color.onyx.textSecondary)
          DeltaChip(delta: prDelta, decimals: 0, monochrome: mono)
        }
        if entry.isStale { StaleTag(age: entry.age) }
      }
      // The corner belongs to the mark; this row's content runs to the edge.
      .padding(.trailing, OnyxMark.faceInset)

      if records.isEmpty {
        Text("no records in the book yet")
          .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        // Three, not "up to six": a fourth trophy at this height is a row of
        // 9 pt type, which is a ledger again.
        VStack(spacing: 4) {
          ForEach(Array(records.prefix(3).enumerated()), id: \.element.id) { index, record in
            if index > 0 { Hairline() }
            Link(destination: OnyxLink.exercises ?? OnyxLink.home!) {
              TrophyFace(record: record, mono: mono, compact: true)
            }
          }
        }
        .frame(maxHeight: .infinity)
      }
    }
  }
}

// MARK: - Records · Large
//
// Three registers of different kinds, which is what a Large owes over a Medium:
// the week in figures, the records themselves, and where the tonnage went.

struct RecordGridFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private func tint(_ c: Color) -> Color { mono ? .white : c }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      weekStrip
      Hairline()
      recordRegister
      Hairline()
      familyRegister
    }
  }

  // ── Register 1: the week, each figure against last week ───────────────────
  private var weekStrip: some View {
    Register(title: "THIS WEEK", accent: tint(OnyxDomain.train.accent)) {
      HStack(spacing: 0) {
        WeekCell(label: "SESSIONS", value: sessions,
                 delta: delta(s?.week.sessions, s?.weekPrev?.sessions), decimals: 0, mono: mono)
        WeekCell(label: "VOLUME", value: OnyxSnapshot.tonnes(s?.week.volumeKg),
                 delta: delta(tonnesThisWeek, tonnesLastWeek), decimals: 1, mono: mono)
        WeekCell(label: "SETS", value: s.map { "\($0.week.sets)" },
                 delta: delta(s?.week.sets, s?.weekPrev?.sets), decimals: 0, mono: mono)
        WeekCell(label: "RECORDS", value: s.map { "\($0.week.prs)" },
                 delta: delta(s?.week.prs, s?.weekPrev?.prs), decimals: 0, mono: mono,
                 color: (s?.week.prs ?? 0) > 0 ? tint(Color.onyx.record) : nil)
      }
    }
  }

  // ── Register 2: the records themselves. The only gold on the widget ───────
  @ViewBuilder private var recordRegister: some View {
    Register(title: "RECENT RECORDS", accent: mono ? .white : Color.onyx.record) {
      let records = s?.records ?? []
      if records.isEmpty {
        // A week without a record is an ordinary week, not a failure — and
        // certainly not an empty gold row implying one was missed. Given real
        // height so the register keeps its share of the face instead of
        // collapsing and dumping its space on whatever sits below.
        Text("no new records in the book yet")
          .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        VStack(spacing: 5) {
          ForEach(records) { record in
            Link(destination: OnyxLink.exercises ?? OnyxLink.home!) {
              RecordRow(record: record, mono: mono)
            }
          }
        }
        .frame(maxHeight: .infinity)
      }
    }
    .frame(maxHeight: .infinity)
  }

  // ── Register 3: where the tonnage actually went ───────────────────────────
  @ViewBuilder private var familyRegister: some View {
    Register(title: "MUSCLE SPLIT", accent: tint(OnyxDomain.train.accent)) {
      FamilySplit(families: s?.volumeByFamily ?? [], mono: mono, height: 26)
    }
  }

  private var sessions: String? {
    guard let week = s?.week else { return nil }
    if let target = week.sessionTarget, target > 0 { return "\(week.sessions)/\(target)" }
    return "\(week.sessions)"
  }

  private var tonnesThisWeek: Double? { s?.week.volumeKg.map { $0 / 1000 } }
  private var tonnesLastWeek: Double? { s?.weekPrev?.volumeKg.map { $0 / 1000 } }

  /// A delta only exists when BOTH weeks do. A first week compared against
  /// nothing is "new", not "+everything".
  private func delta(_ now: Int?, _ then: Int?) -> Double? {
    guard let now, let then else { return nil }
    return Double(now - then)
  }
  private func delta(_ now: Double?, _ then: Double?) -> Double? {
    guard let now, let then else { return nil }
    return now - then
  }
}

// MARK: - Estimated 1RM
//
// A different question from records, and now a different face. `e1rmTrends`
// reports where each main lift's estimate stands TODAY and how far it has moved
// over the trailing window — a current position with a direction, where a record
// is a dated event. Drawing the ledger for both is what made the two focuses
// indistinguishable.

struct OneRepMaxFocusFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var top: OnyxSnapshot.E1rm? { s?.e1rm?.first }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 4) {
        Caption("EST 1RM", color: mono ? .white : OnyxDomain.train.accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      if let top {
        BigValue(value: String(format: "%.1f", top.kg), size: 28, color: Color.onyx.textPrimary)
        Text("kg").font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
        Text(top.exercise)
          .font(OnyxWidgetType.face(11, weight: .semibold))
          .foregroundStyle(Color.onyx.textPrimary)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
        Spacer(minLength: 0)
        DeltaChip(delta: top.deltaKg, decimals: 1, suffix: " kg", monochrome: mono)
      } else {
        Text("log a few working sets and an\nestimate appears here")
          .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
        Spacer(minLength: 0)
      }
    }
  }
}

/// Medium and Large · every tracked lift as a row, with its movement.
///
/// The bar is RELATIVE — each lift against the heaviest of them — because there
/// is no target 1RM in the payload to grade against, and a bar drawn against an
/// invented ceiling would be a verdict rather than a comparison.
struct OneRepMaxLedgerFace: View {
  let entry: OnyxTileEntry
  let mono: Bool
  let large: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var accent: Color { mono ? .white : OnyxDomain.train.accent }
  private var lifts: [OnyxSnapshot.E1rm] { s?.e1rm ?? [] }

  var body: some View {
    VStack(alignment: .leading, spacing: large ? 10 : 7) {
      HStack(spacing: 5) {
        Caption("ESTIMATED 1RM", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
        Text("since 28 days").font(OnyxWidgetType.face(8)).foregroundStyle(Color.onyx.textSecondary)
      }
      // The corner belongs to the mark; this row's content runs to the edge.
      .padding(.trailing, OnyxMark.faceInset)

      if lifts.isEmpty {
        Text("log a few working sets and the main lifts appear here")
          .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        let peak = lifts.map(\.kg).max() ?? 1
        VStack(spacing: large ? 9 : 6) {
          ForEach(lifts) { lift in
            LiftRow(lift: lift, peak: peak, color: accent, mono: mono, large: large)
          }
        }
        .frame(maxHeight: .infinity)
      }

      if large {
        Hairline()
        HStack(spacing: 0) {
          Stat(value: OnyxSnapshot.tonnes(s?.week.volumeKg), label: "WEEK VOLUME", color: Color.onyx.textPrimary)
          Stat(value: s.map { "\($0.week.sets)" }, label: "SETS", color: Color.onyx.textPrimary)
          Stat(value: s.map { "\($0.week.prs)" }, label: "RECORDS",
               color: (s?.week.prs ?? 0) > 0 ? (mono ? .white : Color.onyx.record) : Color.onyx.textSecondary)
        }
      }
    }
  }
}

private struct LiftRow: View {
  let lift: OnyxSnapshot.E1rm
  let peak: Double
  let color: Color
  let mono: Bool
  let large: Bool

  private var points: [Double] { (lift.trend ?? []).map(\.v) }

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(lift.exercise)
            .font(OnyxWidgetType.face(large ? 12 : 11, weight: .semibold))
            .foregroundStyle(Color.onyx.textPrimary)
            .lineLimit(1)
          Spacer(minLength: 4)
          Text(String(format: "%.1f", lift.kg))
            .font(OnyxWidgetType.face(large ? 14 : 12, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
          Text("kg").font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
          DeltaChip(delta: lift.deltaKg, decimals: 1, suffix: " kg", monochrome: mono)
        }
        // Against the heaviest of the tracked lifts, because there is no target
        // 1RM in the payload — a bar drawn against an invented ceiling would be
        // a verdict where this is only a comparison.
        Rail(progress: peak > 0 ? min(1, lift.kg / peak) : nil, color: color, height: 3)
      }

      // ── WHY THE LARGE GETS A TRACE PER LIFT ──────────────────────────────
      // A chip says the estimate moved. It cannot say whether it climbed over
      // four sessions or spiked once and gave it back, and those two lifts want
      // opposite decisions next time. Never zero-based: a 52-to-55 kg month read
      // against zero is a flat line, which is the one reading it is not.
      if large, points.count >= 2 {
        Sparkline(points: points, color: color)
          .frame(width: 76, height: 24)
      }
    }
  }
}

/// Where the week's work went, as one bar per muscle family.
///
/// ── WHY THE BAR IS SETS AND NOT TONNAGE, SINCE W3 ──────────────────────────
/// It used to scale by kg and label itself with sets, which is two currencies in
/// one 26 pt bar: a heavy leg day and a long arm day drew the same picture for
/// opposite reasons. The programme is written in sets, the targets are in sets,
/// and the sheet this register echoes is in sets — so the bar is sets, scaled
/// against the week's own busiest family, and the tint carries the verdict the
/// scale cannot: Good once the phase's target is met.
///
/// Shared by the Records Large and the Volume Large: it is the same register
/// answering the same question, and two copies of it would drift.
struct FamilySplit: View {
  let families: [OnyxSnapshot.FamilyVolume]
  let mono: Bool
  var height: CGFloat = 26

  var body: some View {
    if families.allSatisfy({ $0.sets == 0 }) {
      Text("no sets logged this week")
        .font(OnyxWidgetType.face(10)).foregroundStyle(Color.onyx.textSecondary)
    } else {
      let peak = families.map(\.sets).max() ?? 1
      HStack(alignment: .bottom, spacing: 6) {
        ForEach(families) { family in
          VStack(spacing: 3) {
            GeometryReader { geo in
              VStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 2)
                  // The family's own colour in every state — see `MuscleView.bar`.
                  .fill(mono ? .white : Color.onyx.muscleFamily(family.family))
                  .frame(height: max(2, geo.size.height * CGFloat(peak > 0 ? family.sets / peak : 0)))
              }
            }
            .frame(height: height)
            Text(family.family.rawValue.prefix(4).uppercased())
              .font(OnyxWidgetType.face(7, weight: .bold)).foregroundStyle(Color.onyx.textSecondary)
            // Fractional by design — a secondary mover earns half a set.
            Text(String(format: "%.0f", family.sets))
              .font(OnyxWidgetType.face(8, weight: .semibold)).monospacedDigit()
              .foregroundStyle(Color.onyx.textPrimary)
          }
          .frame(maxWidth: .infinity)
        }
      }
    }
  }
}

private struct WeekCell: View {
  let label: String
  let value: String?
  let delta: Double?
  let decimals: Int
  let mono: Bool
  var color: Color?

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(OnyxWidgetType.face(8, weight: .heavy)).tracking(0.7).foregroundStyle(Color.onyx.textSecondary)
      BigValue(value: value, size: 17, color: color ?? Color.onyx.textPrimary)
      DeltaChip(delta: delta, decimals: decimals, monochrome: mono)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct RecordRow: View {
  let record: OnyxSnapshot.Record
  let mono: Bool
  var showDate = true

  /// See `TrophyFace.marginInk`.
  private var marginInk: Color {
    if mono { return .white }
    return record.marginText == nil ? Color.onyx.textSecondary : Color.onyx.good
  }

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: record.axisSymbol)
        .font(OnyxWidgetType.face(9))
        .foregroundStyle(mono ? .white : Color.onyx.record)
        .frame(width: 12)
      VStack(alignment: .leading, spacing: 0) {
        Text(record.exercise)
          .font(OnyxWidgetType.face(11, weight: .semibold)).foregroundStyle(Color.onyx.textPrimary)
          .lineLimit(1)
        // The axis, named. Without it a 440 kg per-set VOLUME record and a 105 kg
        // heaviest LOAD are the same sentence.
        Text(record.axisLabel)
          .font(OnyxWidgetType.face(8)).foregroundStyle(Color.onyx.textSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      Text(record.display)
        .font(OnyxWidgetType.face(12, weight: .bold, design: .rounded)).monospacedDigit()
        .foregroundStyle(mono ? .white : Color.onyx.record)
      // The margin travels with the record everywhere it is drawn (W6), so the
      // ledger and the trophy report the same thing about the same row.
      Text(record.marginText ?? "1st")
        .font(OnyxWidgetType.face(9, weight: .bold))
        .foregroundStyle(marginInk)
        .frame(width: 48, alignment: .trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      if showDate, let when = OnyxSnapshot.relativeDay(record.achievedOn) {
        Text(when).font(OnyxWidgetType.face(9)).foregroundStyle(Color.onyx.textSecondary)
          .frame(width: 52, alignment: .trailing)
      }
    }
  }
}

#endif
