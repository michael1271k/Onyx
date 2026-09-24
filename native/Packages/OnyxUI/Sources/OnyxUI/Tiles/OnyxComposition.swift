// ── iOS ONLY ────────────────────────────────────────────────────────────────
// A Home Screen tile, and `WidgetFamily.systemSmall/Medium/Large` do not
// exist on watchOS. The watch takes the tokens out of this package and draws
// its own two screens; a 67-cell body atlas on a 40 mm case is not a feature.
#if os(iOS)

import WidgetKit
import SwiftUI
import OnyxCore

// MARK: - Composition
//
// A fourth `BodyFocus` rather than a new widget kind: composition is a body
// question and the Body picker is where a user would look for it.
//
// ── WHAT THIS ADDS THAT THE WEIGHT FACES DID NOT ─────────────────────────────
// `WeightLargeFace` already lists composition — as rows UNDER the scale weight,
// which makes body fat a footnote to a number that moves for reasons that have
// nothing to do with it (water, salt, the hour of the day). This face leads with
// the fat percentage, because on a cut that is the figure the scale is a proxy
// FOR. Same data, opposite emphasis, which is exactly what a focus picker is for.
//
// ── THREE MEASUREMENTS, NEVER INTERCHANGEABLE ────────────────────────────────
// `smmKg` is SKELETAL MUSCLE (~27 kg, entered by hand off the InBody and never
// derived). `muscleKg` is LEAN SOFT TISSUE (~50 kg) and is LABELLED as such —
// calling it "muscle" beside a 27 puts two numbers for one word on a single
// face, twenty kilos apart. `ffmKg` is FAT-FREE MASS (~53 kg). Each appears
// under its own name or not at all.
//
// ── AND DOWN IS NOT ALWAYS GOOD ──────────────────────────────────────────────
// Falling body fat is progress; falling lean tissue is the thing a cut is trying
// to avoid. `upIsGood` is set per metric and never inferred from the sign, which
// is the rule `deltaVerdict` enforces on the web side.
//
// The muscle ATLAS figure is deliberately absent: the web app's `lib/body/atlas.ts` does
// not exist yet (it is Wave C), and the Swift generator reads from it. This face
// ships the numbers; the figure lands when the atlas does.
//
// ── THE DELTAS BECAME 30-DAY IN W12 ─────────────────────────────────────────
// `snapshot.body`'s deltas are "since the previous DIFFERENT reading", which is
// the right rule for a table that carries values forward and the wrong window
// for a body: two weigh-ins four days apart on a cut differ by water, and the
// chip reported that as the month's news. `BodyCompSeries` measures each metric
// against the oldest reading in a 30-day window and reports the span it
// actually covered, so a body weighed twice this month says "over 9 d" rather
// than implying a month it does not have. The old deltas remain the fallback
// for a payload written before the series existed.

/// Small · body fat, its movement, and the fortnight behind it.
struct CompositionFocusFace: View {
  let entry: OnyxTileEntry
  let mono: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var b: OnyxSnapshot.Body? { s?.body }
  private var accent: Color { mono ? .white : OnyxDomain.body.accent }
  private var fat: BodyCompMetric? { s?.metric(.fat) }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Caption("BODY FAT", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        BigValue(value: (fat?.latest ?? b?.fatPct).map { String(format: "%.1f", $0) }, size: 30, color: Color.onyx.textPrimary)
        Text("%").onyxWidgetFont { OnyxWidgetType.face(12 * $0) }.foregroundStyle(Color.onyx.textSecondary)
        Spacer(minLength: 0)
        // Down is good here, and only here on this face.
        //
        // `fat.map(\.delta)`, not `fat?.delta`: see the header. A metric that
        // exists but has one reading reports no delta, and must not borrow the
        // legacy one — that is a different window.
        DeltaChip(delta: fat.map(\.delta) ?? b?.fatPctDelta, decimals: 1, upIsGood: false, monochrome: mono)
      }

      // The span the delta above actually covers, when the series knows it —
      // "over 9 d" beside a chip is what stops the reader reading a month into
      // a fortnight's worth of readings.
      Text(OnyxSnapshot.spanCaption(fat) ?? OnyxSnapshot.relativeDay(s?.weight.measuredOn).map { "measured \($0)" } ?? "")
        .onyxWidgetFont { OnyxWidgetType.face(10 * $0) }.foregroundStyle(Color.onyx.textSecondary).lineLimit(1)

      Spacer(minLength: 0)

      if let trend = b?.fatTrend, trend.count > 1 {
        // Banded, not zero-based: body fat lives in a narrow range and a
        // zero-based axis draws a fortnight of real movement as a flat line.
        Sparkline(points: trend.map(\.v), color: accent)
          .frame(height: 26)
      }
    }
  }
}

/// Medium and Large · the fat percentage, then what the rest of the body is
/// made of, each figure under its own name.
struct CompositionFace: View {
  let entry: OnyxTileEntry
  let mono: Bool
  let large: Bool

  private var s: OnyxSnapshot? { entry.snapshot }
  private var b: OnyxSnapshot.Body? { s?.body }
  private var accent: Color { mono ? .white : OnyxDomain.body.accent }
  private var fat: BodyCompMetric? { s?.metric(.fat) }
  private var lst: BodyCompMetric? { s?.metric(.lst) }
  private var smm: BodyCompMetric? { s?.metric(.smm) }
  private var ffm: BodyCompMetric? { s?.metric(.ffm) }

  var body: some View {
    VStack(alignment: .leading, spacing: large ? 10 : 8) {
      HStack(spacing: 5) {
        Caption("COMPOSITION", color: accent)
        Spacer(minLength: 0)
        if entry.isStale { StaleTag(age: entry.age) }
      }

      HStack(alignment: .firstTextBaseline, spacing: 6) {
        BigValue(value: (fat?.latest ?? b?.fatPct).map { String(format: "%.1f", $0) },
                 size: large ? 38 : 30, color: Color.onyx.textPrimary)
        Text("% fat").onyxWidgetFont { OnyxWidgetType.face((large ? 13 : 11) * $0) }.foregroundStyle(Color.onyx.textSecondary)
        Spacer(minLength: 0)
        if let span = OnyxSnapshot.spanCaption(fat) {
          Text(span).onyxWidgetFont { OnyxWidgetType.face(10 * $0) }.foregroundStyle(Color.onyx.textSecondary).lineLimit(1)
        }
        DeltaChip(delta: fat.map(\.delta) ?? b?.fatPctDelta, decimals: 1, upIsGood: false, monochrome: mono)
      }

      Hairline()

      // ── THE FIGURE, ON THE LARGE FACE ──
      // Filled EVENLY, and that is the honest rendering: the scale measures
      // composition for the whole body and reports nothing per muscle, so a
      // figure with individually tinted bellies would be inventing a
      // distribution nobody measured. What it does carry is scale — 46% lean
      // tissue drawn on a body reads as a proportion in a way "46.2 kg" never
      // will on a 2×2 tile.
      HStack(alignment: .top, spacing: 10) {
        if large, let lean = s?.metric(.lst)?.latest ?? b?.muscleKg, let weight = s?.weight.kg, weight > 0 {
          OnyxAtlasFigure(
            side: .both,
            worked: OnyxAtlasFigure.uniform(min(max(lean / weight, 0), 1)),
            color: OnyxDomain.body.end,
            monochrome: mono)
            .frame(width: 78, height: 104)
        }

      VStack(spacing: large ? 7 : 5) {
        // "Lean Soft Tissue", never "muscle" — see the header. Up IS good for
        // all three of these, and that is a statement about the metric, not
        // about the sign of the number.
        CompositionRow(label: "LEAN SOFT TISSUE",
                       value: lst?.latest ?? b?.muscleKg,
                       delta: lst.map(\.delta) ?? b?.muscleKgDelta,
                       unit: "kg", color: mono ? .white : OnyxDomain.body.end, mono: mono,
                       upIsGood: true, compact: !large)
        CompositionRow(label: "SKELETAL MUSCLE",
                       value: smm?.latest ?? b?.smmKg,
                       delta: smm.map(\.delta) ?? b?.smmKgDelta,
                       unit: "kg", color: mono ? .white : OnyxDomain.body.at(0.25), mono: mono,
                       upIsGood: true, compact: !large)
        CompositionRow(label: "FAT-FREE MASS",
                       value: ffm?.latest ?? b?.ffmKg,
                       delta: ffm.map(\.delta) ?? b?.ffmKgDelta,
                       unit: "kg", color: mono ? .white : Color.onyx.textSecondary, mono: mono,
                       upIsGood: true, compact: !large)
      }
      }

      if large {
        Spacer(minLength: 0)
        Hairline()

        Register(title: "FOURTEEN DAYS", accent: mono ? .white : accent) {
          if let trend = b?.fatTrend, trend.count > 1 {
            Sparkline(points: trend.map(\.v), color: accent)
              .frame(maxHeight: .infinity)
          } else {
            // Two readings are the minimum for a line to mean anything. One is
            // a dot, and a dot drawn as a trend is a claim about a shape that
            // does not exist.
            Text("not enough readings for a trend")
              .onyxWidgetFont { OnyxWidgetType.face(10 * $0) }.foregroundStyle(Color.onyx.textSecondary)
          }
        }
        .frame(maxHeight: .infinity)

        Hairline()

        HStack(spacing: 0) {
          Stat(value: s?.weight.kg.map { String(format: "%.1f", $0) }, label: "WEIGHT", color: Color.onyx.textPrimary)
          Stat(value: s?.weight.targetKg.map { String(format: "%.1f", $0) }, label: "TARGET",
               color: mono ? .white : Color.onyx.textSecondary)
          Stat(value: OnyxSnapshot.relativeDay(s?.weight.measuredOn), label: "MEASURED",
               color: Color.onyx.textSecondary)
        }
      } else {
        Spacer(minLength: 0)
      }
    }
  }
}

#endif
