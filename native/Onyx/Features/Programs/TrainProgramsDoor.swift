import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// The one card Train shows for programs: which one is running, what it deals
/// next, and the door to all of them (Precision E2, seam 6).
///
/// ── SELF-CONTAINED ON PURPOSE ───────────────────────────────────────────────
/// `WorkoutTabView` is Lane B's file and takes exactly ONE line for this — so
/// the door reads everything it needs itself: the live catalogue from the
/// environment's target resolver (the same snapshot every gauge reads) and the
/// logical day. No parameter to thread, nothing for the tab to compute.
///
/// ── THE TRENDS DOOR'S SHAPE, NOT A HERO ─────────────────────────────────────
/// A full-width tile like Train's Trends door: glyph, the program's name in
/// body semibold, one caption line, and "Programs ›" in the accent. The plan
/// card above owns the tab's display type; this is furniture pointing at a
/// screen.
struct TrainProgramsDoor: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The store's own catalogue and user, read once in `.task` — for an
    /// environment with no target resolver (a harness store; the app has one
    /// whenever this tab is reachable). Never read in `body`.
    @State private var fallback: (schedule: ScheduleContext, userId: String)?

    private var accent: Color { OnyxDomain.train.accent }

    var body: some View {
        let schedule = environment.targets?.schedule ?? fallback?.schedule
        let program = schedule?.activeProgram
        let next = schedule.flatMap { Self.next(in: $0, after: environment.today) }
        NavigationLink {
            ProgramsView(model: ProgramsModel(
                database: environment.database,
                userId: environment.targets?.userId ?? fallback?.userId ?? environment.userIdString
            ))
        } label: {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: OnyxSpace.s))
                : AnyLayout(HStackLayout(alignment: .center, spacing: OnyxSpace.m))
            layout {
                HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .onyxType(.caption)
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(program))
                            .onyxType(.body).fontWeight(.semibold)
                            .foregroundStyle(Color.onyx.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(caption(program, next: next))
                            .onyxType(.caption)
                            .foregroundStyle(Color.onyx.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: OnyxSpace.s) }
                HStack(spacing: OnyxSpace.xs) {
                    Text("Programs")
                        .onyxType(.caption).fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .onyxType(.micro)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(accent)
                .layoutPriority(1)
            }
            .padding(OnyxSpace.m)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .onyxGlass(.tile)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onyxPress(scale: 0.98)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Programs. \(title(program)). \(caption(program, next: next))")
        .accessibilityAddTraits(.isButton)
        .task {
            guard environment.targets == nil else { return }
            let database = environment.database
            let user = environment.userIdString.isEmpty ? database.localUserId() : environment.userIdString
            if let schedule = try? database.scheduleContext(userId: user) { fallback = (schedule, user) }
        }
    }

    private func title(_ program: Program?) -> String {
        guard let program, !program.id.isEmpty else { return "No program yet" }
        return program.label
    }

    private func caption(_ program: Program?, next: (label: String, date: String)?) -> String {
        guard let program, !program.id.isEmpty else { return "Build one or start from a template" }
        if program.days.isEmpty { return "No days yet" }
        guard let next else { return "\(program.days.count) days a week" }
        return "Next · \(next.label) · \(Self.when(next.date, today: environment.today))"
    }

    /// The first scheduled session AFTER today — today's is the plan card
    /// right above this one. Two weeks is the horizon: a plan with nothing
    /// scheduled for a fortnight has no "next" worth naming.
    static func next(in schedule: ScheduleContext, after today: String) -> (label: String, date: String)? {
        for offset in 1...14 {
            guard let date = ISODate.addDays(today, offset) else { continue }
            if let day = Schedule.scheduleDayIn(schedule, date) { return (day.label, date) }
        }
        return nil
    }

    /// "tomorrow", else the weekday — "Thu".
    static func when(_ date: String, today: String) -> String {
        if ISODate.addDays(today, 1) == date { return "tomorrow" }
        return LogicalDay.date(fromISO: date)?.formatted(.dateTime.weekday(.abbreviated)) ?? date
    }
}
