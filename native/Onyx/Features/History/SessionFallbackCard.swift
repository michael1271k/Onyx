import SwiftUI
import OnyxCore
import OnyxUI

/// The stand-in `SessionHeaderCard` leaves behind while its career-wide read is
/// in flight — on the Train tab and on the Pulse day, the two screens that draw
/// a finished session out of a window they are already holding.
///
/// ── WHY IT STOPPED BEING A GREY BOX (W5) ────────────────────────────────────
/// Both screens drew their own: a title, a dot or a checkmark, and a line of
/// numbers on plain glass. So the moment before the header landed was the one
/// moment a finished session looked like nothing in particular — and on a cold
/// launch, a slow disk or a long ledger, that moment is the whole first
/// impression of the tab. The card and its stand-in now differ in CONTENT —
/// no career number, no plan tags, no headline, and three muscles rather than
/// every primary — and not in CHARACTER: the same day wash behind it, the same
/// title in the same day ink at the same size, the same muscle capsules in the
/// same hues. Nothing moves when the read lands except what arrives.
///
/// ── AND WHY THE CAPSULES ARE THE TOP THREE ──────────────────────────────────
/// `SessionHeader.muscles` is the report's full primary order, which costs the
/// ledger walk this card exists to not wait for. These are `DayModel.focus`,
/// which is the SAME function truncated to three — so this list is a prefix of
/// the real one by construction and the read can only ever make it longer. A
/// capsule never moves and never disappears. Both callers already hold what it
/// needs: Pulse folds it for its own window, `WorkoutWeek` folds it off the
/// rows it has already read to count the session's sets. A fold, not a query.
///
/// It was `MuscleCredit.weightedSets` until W5, which pays an assistor half a
/// set and counts warm-ups — so a muscle the session was not FOR could take a
/// capsule and then lose it the moment the header arrived.
struct SessionFallbackCard: View {
    let dayKey: String?
    /// The programme's own name for the day — "Legs & Core B".
    let label: String
    /// The same four numbers, in the same order and with the same separator,
    /// that this session's real masthead is passed.
    let totals: String
    let muscles: [LandmarkMuscle]

    var body: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            // `.hero` and the same two guards the masthead's title carries, not
            // a step down: a stand-in that sets the title 8 pt smaller makes the
            // read landing a lurch rather than an arrival, and this exact
            // treatment is already proven at AX5 in both of these containers.
            Text(label)
                .onyxType(.hero)
                .foregroundStyle(Color.onyx.dayLabel(dayKey))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Absent rather than reserved: a session that recorded no
            // recognised movement has no muscles to name, and an empty
            // `FlowRow` is a blank line in the middle of a card.
            if !muscles.isEmpty {
                MuscleTagRow(muscles: muscles)
            }
            Text(totals)
                .onyxType(.secondary).onyxNumeral()
                .foregroundStyle(Color.onyx.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(OnyxSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sessionDayWash(dayKey)
        .onyxGlass(.tile)
    }
}
