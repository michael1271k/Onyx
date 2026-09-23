import SwiftUI
import OnyxUI
import OnyxCore

/// What a set's trophy actually means — the sheet the web has had since
/// `PrRecordSheet.tsx`, and the deck has not.
///
/// ── WHY A BADGE WAS NOT ENOUGH ──────────────────────────────────────────────
/// The trophy said "this beat something" and stopped. By how much, and over
/// what, existed nowhere on the phone: `personal_records` is upsert-on-conflict,
/// so the value being beaten is destroyed by the write that beats it, and the
/// only place the pair survives is `PrEngine`'s own `AxisRecord` — captured
/// BEFORE the winner is folded into the index. `livePrs` has carried both
/// numbers since E4 and the deck was printing neither.
///
/// ── AND WHY IT IS THIS SMALL ────────────────────────────────────────────────
/// It answers one question, so it is sized to one answer: a row per axis won,
/// the new figure, and the gap. No chart, no history, nothing to scroll — the
/// web's version says the same and for the same reason. A record is read in the
/// four seconds between a set and the rest timer.
///
/// ── AND WHY THE LIFT'S NAME IS THE TITLE ────────────────────────────────────
/// The sheet used to open (on the web) with "Personal record" as its largest
/// type, over the name of the movement — restating the one thing you already
/// knew from the trophy you tapped. The name of the lift is the news.
struct PrRecordSheet: View {
    let exerciseName: String
    /// "Set 3" — the SET's ordinal, which on a pair is one number for two rows.
    let setLabel: String
    /// Newest first, as `livePrs` holds them.
    let records: [LivePrRecord]
    /// A hold rather than a lift: its "reps" axis is seconds.
    var timed = false

    @Environment(\.dismiss) private var dismiss

    /// Heaviest claim first, so the headline record leads — the same order the
    /// web prints, because two clients answering in two orders is two answers.
    private static let axisOrder: [PrAxis] = [.weight, .e1rm, .volume, .reps]

    private var ordered: [LivePrRecord] {
        records.sorted { a, b in
            let ia = Self.axisOrder.firstIndex(of: a.axis) ?? Self.axisOrder.count
            let ib = Self.axisOrder.firstIndex(of: b.axis) ?? Self.axisOrder.count
            return ia < ib
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OnyxSpace.s) {
                    // Which set earned them. One muted line under a title that
                    // is already the exercise — the pair reads as "this lift,
                    // this set" without a second heading between them.
                    Text(setLabel)
                        .onyxType(.micro)
                        .foregroundStyle(Color.onyx.textSecondary)
                    ForEach(ordered) { record in
                        axisRow(record)
                    }
                    if ordered.isEmpty {
                        // Reachable: a record can be withdrawn between the tap
                        // and the presentation (an untick, a set edited into a
                        // warm-up). An empty panel with a drag indicator for an
                        // exit is worse than a sentence.
                        Text("This set no longer holds a record.")
                            .onyxType(.secondary)
                            .foregroundStyle(Color.onyx.textSecondary)
                    }
                }
                .padding(OnyxSpace.l)
            }
            .onyxScreen(.train)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("New record")
                            .onyxMicro()
                            .foregroundStyle(Color.onyx.record)
                        Text(exerciseName)
                            .onyxType(.body).fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        // Tall enough for four axes and no taller. A set can win all four at
        // once (a first-ever bodyweight movement does), and a detent that had
        // to be scrolled for the fourth would hide the one the reader came for
        // half the time.
        .presentationDetents([.height(320), .large])
        .presentationDragIndicator(.visible)
    }

    /// ── ONE ROW, LEFT TO RIGHT, IN READING ORDER ────────────────────────────
    /// Trophy · what kind of record · the number · how much it beat. The web
    /// tried a stacked column with the gap floated right and three records read
    /// as three two-line blocks the eye had to travel down and back up for.
    private func axisRow(_ record: LivePrRecord) -> some View {
        HStack(spacing: OnyxSpace.m) {
            Image(systemName: "trophy.fill")
                .imageScale(.small)
                .foregroundStyle(Color.onyx.record)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.onyx.record.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(record.axis.displayName)
                    .onyxMicro()
                    .foregroundStyle(Color.onyx.record)
                Text(value(record.axis, record.mark.value))
                    .onyxType(.body).fontWeight(.bold).onyxNumeral()
                    .foregroundStyle(Color.onyx.textPrimary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                // A record only ever moves up, so the sign is the direction —
                // no arrow, and the theme's accent rather than green (overhaul
                // Q14: deltas are tinted numerals).
                Text("+" + value(record.axis, max(0, record.mark.value - record.mark.previous)))
                    .onyxType(.caption).fontWeight(.bold).onyxNumeral()
                    .foregroundStyle(OnyxInk.Themed.accent)
                Text("was \(value(record.axis, record.mark.previous))")
                    .onyxType(.micro)
                    .foregroundStyle(Color.onyx.textTertiary)
            }
        }
        .padding(OnyxSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .fill(Color.onyx.record.opacity(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: OnyxCorner.row, style: .continuous)
                .strokeBorder(Color.onyx.record.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.axis.displayName) record")
        .accessibilityValue(
            "\(value(record.axis, record.mark.value)), beating \(value(record.axis, record.mark.previous))"
        )
    }

    /// How a value is written for its axis.
    ///
    /// Weight, tonnage and e1RM are LOADS and take kilograms; reps are a count
    /// and take none — and on a timed hold they are seconds. Getting that wrong
    /// is how a rep count ends up reading "12 kg", which is the kind of detail
    /// that makes a number stop being believed.
    private func value(_ axis: PrAxis, _ value: Double) -> String {
        switch axis {
        case .reps:
            return timed ? "\(Int(value.rounded())) sec" : "\(Int(value.rounded()))"
        case .weight, .volume, .e1rm:
            return "\(OnyxFormat.kg(value)) kg"
        }
    }
}

#if DEBUG
#Preview("Records") {
    Color.clear.sheet(isPresented: .constant(true)) {
        PrRecordSheet(
            exerciseName: "Neutral-Grip Lat Pulldown",
            setLabel: "Set 3",
            records: [
                LivePrRecord(
                    id: "a|3|weight", exercise: "Neutral-Grip Lat Pulldown", setLabel: "Set 3",
                    axis: .weight, mark: AxisRecord(value: 62.5, previous: 60)
                ),
                LivePrRecord(
                    id: "a|3|e1rm", exercise: "Neutral-Grip Lat Pulldown", setLabel: "Set 3",
                    axis: .e1rm, mark: AxisRecord(value: 83.33, previous: 80)
                )
            ]
        )
    }
}
#endif
