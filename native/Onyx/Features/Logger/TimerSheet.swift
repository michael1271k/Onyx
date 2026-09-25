import SwiftUI
import OnyxUI
import OnyxCore

/// When the session started — the one correction the clock still needs a
/// sheet for (Precision A4, Q7 A).
///
/// ── WHY A CLOCK NEEDS AN EDITOR AT ALL ──────────────────────────────────────
/// `duration_min` is not decoration: it multiplies session RPE into the training
/// load that feeds ACWR, monotony and strain, and readiness reads 49 days of it
/// — so a session opened at set three, or left open through lunch, moves
/// `battery_pct` for weeks. The Sept 6 Upper A recorded **385 minutes** for a
/// 60-minute workout.
///
/// ── AND WHY IT IS ONE ROW NOW ───────────────────────────────────────────────
/// It was a 560 pt sheet: a 34 pt reading, pause, the set stopwatch with laps,
/// a wheel for the start and a ±60 s stepper for the elapsed time. Pause and
/// the stopwatch live on the `TimerRail` under the deck now, where they are
/// always one tap away; the reading is on the rail and in the hero; the
/// elapsed stepper was the same correction as the start, done backwards. What
/// is left is the START, in the system's compact picker — the "Started 18:42"
/// the founder asked the hero's clock to open, and nothing else.
struct TimerSheet: View {
    let clock: any PauseControlling
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var startBinding: Binding<Date> {
        Binding(get: { clock.startedAt }, set: { clock.setStart($0) })
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: OnyxSpace.s) {
                // Label and picker side by side until the type says otherwise;
                // at AX sizes the compact picker's own chip is wider than half
                // a phone and the label goes above it.
                ViewThatFits(in: .horizontal) {
                    HStack {
                        label
                        Spacer(minLength: OnyxSpace.s)
                        picker
                    }
                    VStack(alignment: .leading, spacing: OnyxSpace.xs) {
                        label
                        picker
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OnyxSpace.m)
                .frame(minHeight: 44)
                .onyxGlass(.tile)
                Text("Moving the start moves the clock the session is saved with.")
                    .onyxType(.caption)
                    .foregroundStyle(Color.onyx.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, OnyxSpace.l)
            .frame(maxHeight: .infinity, alignment: .top)
            .onyxScreen(.train)
            .foregroundStyle(Color.onyx.textPrimary)
            .navigationTitle("Session clock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(220)])
        .presentationDragIndicator(.visible)
    }

    private var label: some View {
        Text("Started").onyxType(.body)
    }

    private var picker: some View {
        DatePicker("Started", selection: startBinding, in: ...Date(), displayedComponents: [.hourAndMinute])
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(accent)
    }
}

#if DEBUG
#Preview("Timer sheet") {
    TimerSheet(
        clock: LoggerClock(startedAt: Date().addingTimeInterval(-22 * 60)),
        accent: Color.onyx.day("cb_b")
    )
    .preferredColorScheme(.dark)
}
#endif
