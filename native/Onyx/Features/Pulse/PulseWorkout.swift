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
/// ── AND WHY IT IS NOW THE SAME CARD THE OTHER TWO SCREENS DRAW (A6) ─────────
/// This was `WorkoutSummaryCard`: a header row, a muscle wash and three
/// capsules, which was the third independent rendering of one finished session
/// — the Train tab's done card and the session page's own band being the other
/// two. They stated the same facts, disagreed about which mattered, and drifted
/// one edit at a time. `SessionHeaderCard` is the one that survives, so the
/// door and the room are now literally the same view, and the push is the page
/// arriving under a masthead that never moved.
///
/// What this file keeps is the part `SessionHeaderCard` does not know: the
/// day's own three numbers, which come off `DayModel.WorkoutSummary` (already
/// folded for this date) rather than from a second career-wide walk.
struct PulseSessionCard: View {
    let session: DayModel.WorkoutSummary
    /// Nil until `SessionAnalysis.headers` lands — see `DayScreen.sessionHeaders`.
    let header: SessionHeader?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Group {
                if let header, header.id == session.id {
                    SessionHeaderCard(header: header, totals: totals)
                } else {
                    placeholder
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.99)
        // ── THE CALLER DECIDES THE GROUPING ─────────────────────────────────
        // `SessionHeaderCard` deliberately carries no
        // `.accessibilityElement(children:)` of its own: inside a `List` row on
        // the session page it is static content, and inside a button it has to
        // be ONE element or a reader hears four labels where they expect one
        // target. This is the button case.
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the session.")
        .accessibilityAddTraits(.isButton)
    }

    /// `3,108 kg · 12 sets · 2 PR · 48 min` — the same four, in the same order
    /// and with the same separator, that the Train tab's done card passes. Two
    /// callers of one card saying a session's numbers two ways is exactly the
    /// drift A6 exists to end.
    ///
    /// ── AND WHY `OnyxFormat` RATHER THAN `Format` ───────────────────────────
    /// `Format.volume` (OnyxCore) always keeps a tenth, which is right for the
    /// three surfaces that state a session's weight as a CLAIM checked against
    /// `workout_sessions.total_volume_kg`. This card is a reading, and the
    /// card it now shares with the Train tab has always printed the reading
    /// form — so the old Pulse card said "13,005.0 kg" for the session the
    /// Train tab called "13,005 kg", which is the drift, one decimal wide.
    ///
    /// The PR count is the HEADER's, not the day window's: a record is only
    /// knowable by replaying the whole ledger in order, which is the walk
    /// `SessionAnalysis.headers` already made. `DayModel.WorkoutSummary` has
    /// never carried one and still does not.
    private var totals: String {
        var parts = ["\(OnyxFormat.volume(session.tonnageKg)) kg", "\(session.sets) sets"]
        if let count = header?.prCount, count > 0 { parts.append("\(count) PR") }
        if let minutes = session.durationMin, minutes > 0 {
            parts.append("\(Int(minutes.rounded())) min")
        }
        return parts.joined(separator: " · ")
    }

    /// The header is a career-wide read. These two facts are already in the
    /// day's window, so the card states them immediately rather than blinking
    /// an empty box in on every open of the tab — the same stand-in the Train
    /// tab draws for the same read.
    private var placeholder: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.xs) {
            HStack(spacing: OnyxSpace.s) {
                Circle()
                    .fill(Color.onyx.day(session.dayKey))
                    .frame(width: 8, height: 8)
                Text(session.label ?? "Session")
                    .onyxDisplay()
                    .foregroundStyle(Color.onyx.dayLabel(session.dayKey))
                    .lineLimit(1)
                Spacer(minLength: OnyxSpace.s)
            }
            Text(totals)
                .onyxType(.secondary).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
        }
        .padding(OnyxSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onyxGlass(.tile)
    }
}
