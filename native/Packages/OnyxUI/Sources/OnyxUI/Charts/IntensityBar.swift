// ── iOS ONLY, LIKE EVERY OTHER FILE IN Charts/ ──────────────────────────────
// `onyxGlass` is the phone's material stack and the watch draws on `WatchInk`
// (law 6). A 40 mm wrist has no room for a twenty-set gradient anyway — the
// complication that would want one says a number.
#if os(iOS)

import SwiftUI

/// How hard the session got, set by set — one bar, and no axis.
///
/// ── TWO CALLERS, ONE BAR (W10) ──────────────────────────────────────────────
/// The session page draws it under the metric grid, and the finish sheet draws
/// it thirty seconds after the last set. The second is where the question is
/// actually asked — "did I fade" — and the first is where it is studied. Both
/// take the session's per-set ratings in performed order; everything below is
/// written about the page because that is where it was born, and none of it
/// changes for the sheet.
///
/// ── WHY A GRADIENT AND NOT A CHART ──────────────────────────────────────────
/// The question it answers is shape-shaped: did this session open easy and end
/// at the stop, or was it flat at eight the whole way through? A `Chart` with
/// an axis would invite the reader to look up individual values, which the
/// ledger below already prints exactly — and would cost a plot, a scale and a
/// legend on a page that already has three charts on it.
///
/// One stop per set, placed at the CENTRE of its slice rather than at its
/// edges, so adjacent efforts blend instead of banding. That is the difference
/// between a fingerprint and a bar chart lying on its side.
///
/// ── AND WHY IT COSTS NOTHING TO SCROLL PAST ─────────────────────────────────
/// `LinearGradient` with n stops is one layer and no offscreen pass. The stops
/// are computed once per value change (the array is a `let` on the report,
/// built off the main actor by `SessionAnalysis`), never per frame — which is
/// the rule the rest of this wave's additions are held to.
public struct IntensityBar: View {
    public let values: [Double?]

    /// Every set's effort, in the order they were performed, `nil` for the
    /// unrated ones. Public so the finish sheet can hand over the deck's own
    /// rows without the page's `SessionAnalysis` in between.
    public init(values: [Double?]) { self.values = values }

    /// Two sets is not a shape. One rated set among twenty is not one either:
    /// a bar that is grey for 95 % of its length says nothing about effort and
    /// everything about rating discipline, which is not what it is for.
    private var rated: Int { values.compactMap { $0 }.count }

    private var stops: [Gradient.Stop] {
        guard values.count > 1 else {
            return values.first.map { [Gradient.Stop(color: colour($0), location: 0),
                                       Gradient.Stop(color: colour($0), location: 1)] } ?? []
        }
        return values.enumerated().map { index, value in
            Gradient.Stop(
                color: colour(value),
                location: (Double(index) + 0.5) / Double(values.count)
            )
        }
    }

    /// An unrated set is text-grey and not a zero — the same rule
    /// `Color.onyx.effort` follows at the bottom of its own ladder.
    private func colour(_ rpe: Double?) -> Color {
        rpe.map { Color.onyx.effort($0) } ?? Color.onyx.textTertiary
    }

    public var body: some View {
        if values.count >= 3, rated >= 2 {
            VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                HStack(spacing: OnyxSpace.xs) {
                    Text("Intensity")
                        .onyxMicro()
                    Spacer(minLength: 0)
                    Text("\(values.count) sets")
                        .onyxType(.micro).onyxNumeral()
                        .foregroundStyle(Color.onyx.textTertiary)
                }
                Capsule()
                    .fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8)
            }
            .padding(OnyxSpace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onyxGlass(.row)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Intensity across \(values.count) sets")
            .accessibilityValue(spoken)
        }
    }

    /// VoiceOver gets the three readings a sighted reader takes off the shape:
    /// where it started, where it peaked, where it ended.
    private var spoken: String {
        let rated = values.compactMap { $0 }
        guard let first = rated.first, let last = rated.last, let peak = rated.max() else {
            return "not rated"
        }
        return "opened at RPE \(OnyxFormat.rpe(first)), peaked at \(OnyxFormat.rpe(peak)), finished at \(OnyxFormat.rpe(last))"
    }
}
#endif
