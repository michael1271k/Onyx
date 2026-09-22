import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI

/// One sheet for the three things you log about a day (§W6-B.4).
///
/// ── WHY THEY WERE THREE, AND WHY THAT WAS THE PROBLEM ───────────────────────
/// Stress, soreness and water are three answers about the same day, and they
/// were three sheets with three different ways in: stress from a Pulse square
/// and a Quick Log spoke, soreness from a Pulse square and a VoiceOver rotor
/// action and NOWHERE else, water from a LONG-PRESS on a row whose tap does
/// something different. `docs/COMPACTION_AUDIT.md` §4 has the table. Three
/// conventions for one gesture is not three features; it is one feature
/// nobody can find two thirds of.
///
/// ── WHAT THIS IS AND WHAT IT DELIBERATELY IS NOT ────────────────────────────
/// It is a segmented control over the three sheets that already exist, each
/// keeping its own chrome, its own Save and its own write. It is NOT a merged
/// form: a stress reading is an EVENT (every save is a new row), a soreness
/// rating is an upsert per muscle written on each tap with no Save at all, and
/// a water figure REPLACES the day. Those are three different facts with three
/// different shapes, and one Save button over all of them would have to lie
/// about at least two.
///
/// The picker sits at the BOTTOM, under the thumb and under each segment's own
/// navigation bar, for the reason the rest bar does: the control that switches
/// what you are doing should not sit where the control that finishes it does.
struct LogDaySheet: View {

    enum Segment: String, CaseIterable, Identifiable {
        case stress, soreness, water
        var id: String { rawValue }
        var title: String {
            switch self {
            case .stress: "Stress"
            case .soreness: "Soreness"
            case .water: "Water"
            }
        }
    }

    let model: DayModel
    @State var segment: Segment

    @Environment(AppEnvironment.self) private var environment
    /// Water is the one of the three that is not a `DayModel` fact.
    ///
    /// Its writes go through `NutritionModel`, which the Fuel tab owns and
    /// this tab has never held. One is built here rather than threading the
    /// Fuel tab's instance across two tabs: the store is the source of truth,
    /// both models observe it, and a glass logged here reaches the Fuel tab
    /// through the same observation as one logged on the watch.
    @State private var nutrition: NutritionModel?

    /// `.task(id:)` takes one value; this is the two things that decide
    /// whether the water segment can be built.
    private struct Ready: Equatable {
        var segment: Segment
        var hasTargets: Bool
    }

    var body: some View {
        Group {
            switch segment {
            case .stress: StressLogSheet(model: model)
            case .soreness: SorenessSheet(model: model)
            case .water:
                if let nutrition {
                    WaterSheet(model: nutrition)
                } else {
                    // `targets` is nil while signed out and for the moment
                    // between a sign-in and the resolver starting. Say so
                    // rather than spinning: the `.task` below is keyed on the
                    // segment AND on the resolver, so this corrects itself the
                    // instant there is something to correct it with.
                    ContentUnavailableView(
                        "Water needs your targets",
                        systemImage: "drop",
                        description: Text("They arrive with the first sync.")
                    )
                    .onyxScreen(.fuel)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Picker("What to log", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, OnyxSpace.l)
            .padding(.vertical, OnyxSpace.s)
            .background(.bar)
            .accessibilityLabel("What to log")
        }
        // ── BUILT FOR THE WATER SEGMENT AND FOR NO OTHER ────────────────────
        // A `NutritionModel` is an observation, and this wave exists to have
        // fewer of those. Opening this sheet on Stress must not start one;
        // `.task(id:)` on the segment builds it the first time Water is
        // chosen and tears it down with the sheet. Keyed on the resolver too,
        // so a sheet opened before the first sync recovers when it lands.
        .task(id: Ready(segment: segment, hasTargets: environment.targets != nil)) {
            guard segment == .water, nutrition == nil, let targets = environment.targets else { return }
            let built = NutritionModel(
                database: environment.database, userId: environment.userIdString,
                targets: targets, date: model.date
            )
            nutrition = built
            await built.observe()
        }
    }
}
