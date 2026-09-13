import SwiftUI
import OnyxUI
import OnyxCore

/// What was trained on this date, and the door to the page that reads it
/// properly (§W11).
///
/// ── WHY THE DAY PAGE HAD NOTHING ABOUT TRAINING ON IT ───────────────────────
/// Pulse is the recovery screen and the session lives in the Workout tab, which
/// was a clean split until History started pushing this same screen for a past
/// day (§5.9). Standing on 30 August you could see the night, the vitals, the
/// scale and the soreness — and no way at all to reach the session that caused
/// every one of them. Getting there meant leaving, opening History, finding the
/// week, finding the day, and arriving back at the same date.
///
/// One card and a chevron. It states the three figures that say what kind of
/// session it was and hands the reader to `SessionDetailView`, which replays
/// the record book and draws the rest.
///
/// ── AND WHY IT IS NOT A `PulseRow` ──────────────────────────────────────────
/// Every other door on this screen opens a SHEET about the day you are already
/// on. This one pushes a different screen, and it carries three numbers rather
/// than one sentence. A row shaped like the other four that behaves unlike all
/// of them is the more expensive kind of consistency.
struct WorkoutSummaryCard: View {
    let session: DayModel.WorkoutSummary
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The split's own colour, as the calendar ring and the session chip draw
    /// it — a leg day is the same teal everywhere or it is decoration.
    private var tint: Color { Color.onyx.day(session.dayKey) }

    /// The session's OWN colours — its top muscles, heaviest share first.
    ///
    /// ── WHY THE WASH STOPPED BEING THE SPLIT'S ──────────────────────────────
    /// The dot, the label and the chips still carry the split: that is what
    /// says which day of the programme this was, and it has to stay stable.
    /// The WASH is the one part of this card that was saying the same thing a
    /// second time — every Upper B the same indigo — while the thing the
    /// reader cannot get from the label is what the session actually trained.
    /// Two hues, blended, is a chest-and-triceps day looking different from a
    /// back-and-biceps day at a glance, with no new vocabulary to learn: they
    /// are the same sixteen muscle hues the session page, the atlas and the
    /// legend use.
    ///
    /// Falls back to the split when the session trained nothing the map knows
    /// — a cardio-only day, or a movement nobody has classified.
    private var wash: [Color] {
        let hues = session.muscles.prefix(2).map { Color.onyx.muscle($0) }
        return hues.isEmpty ? [tint] : Array(hues)
    }

    /// ── WHY A BUTTON AND NOT A `NavigationLink` ─────────────────────────────
    /// A `NavigationLink` inside a `List` row draws the system disclosure at
    /// the ROW's trailing edge — outside this card's glass, because `plainRow()`
    /// insets the row and the card fills what is left. The first build had two
    /// chevrons: one in the card's header where it belongs, and one floating in
    /// the gutter beside it. The push moves to `DayScreen`, which owns the
    /// destination for the same reason it owns every other sheet on the page.
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                header
                MetaTagRow(tags: tags)
            }
            .padding(OnyxSpace.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The same wash the session page's ledger headers wear (§U4.6), in
            // the split's own colour. It is the SAME card in two places — this
            // one is the door and that one is the room — and two treatments of
            // one object is the drift the tint tokens exist to stop.
            .background(alignment: .top) {
                // Two stops of the session's own muscles across the top, then
                // out — the same 22 %→0 over 64 pt the session page's band
                // wears, so the door and the room are painted in one language.
                LinearGradient(
                    stops: wash.enumerated().map { index, hue in
                        .init(
                            color: hue.opacity(0.22),
                            location: wash.count > 1 ? Double(index) / Double(wash.count - 1) : 0
                        )
                    },
                    startPoint: .topLeading, endPoint: .topTrailing
                )
                .mask {
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                }
                .frame(height: 64)
            }
            .onyxGlass(.tile)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.99)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout summary. \(session.label ?? "Session"), \(spoken)")
        .accessibilityHint("Opens the session.")
        .accessibilityAddTraits(.isButton)
    }

    private var header: some View {
        HStack(spacing: OnyxSpace.s) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(session.label ?? "Session")
                .onyxType(.body).fontWeight(.semibold)
                .foregroundStyle(Color.onyx.textPrimary)
                .lineLimit(1)
            Spacer(minLength: OnyxSpace.s)
            Text("Workout summary")
                .onyxMicro()
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .onyxType(.caption).fontWeight(.bold)
                .foregroundStyle(Color.onyx.textTertiary)
                .accessibilityHidden(true)
        }
    }

    /// Three figures, and never a fourth: PRs are a whole-ledger replay and
    /// belong to the page this card opens (`DayModel.WorkoutSummary`).
    ///
    /// ── WHY CAPSULES REPLACED THE THREE-COLUMN GRID (§U4.6) ─────────────────
    /// It was `TONNAGE / SETS / TIME` as three labelled columns, which needed
    /// an `AnyLayout` swap at the accessibility sizes because three columns of
    /// a caption over a numeral is three ellipses on a 375 pt phone. A capsule
    /// carries its unit INSIDE it — "1,160 kg" needs no register label above it
    /// — so the row wraps instead of truncating and `FlowRow` handles the
    /// accessibility sizes without a second layout to keep in step.
    ///
    /// It is also the same object the session page's ledger footers are now
    /// made of, which is the point: the door and the room say a session's
    /// numbers the same way.
    private var tags: [MetaTagRow.Tag] {
        var out: [MetaTagRow.Tag] = [
            .init("\(Format.volume(session.tonnageKg)) kg"),
            .init("\(session.sets) sets"),
        ]
        if let minutes = session.durationMin, minutes > 0 {
            out.append(.init(DayFormat.minutes(Int(minutes.rounded()))))
        }
        return out
    }

    private var spoken: String {
        var parts = ["\(Format.volume(session.tonnageKg)) kilograms", "\(session.sets) sets"]
        if let minutes = session.durationMin, minutes > 0 {
            parts.append("\(Int(minutes.rounded())) minutes")
        }
        return parts.joined(separator: ", ")
    }
}
