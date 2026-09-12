import Foundation

/// Which query keys a Supabase table change invalidates — a port of
/// the web app's `lib/query/realtimeKeys.ts` and `query/workoutKeys.ts`. OnyxData owns
/// the invalidation; this pins the fan-out so the two sides cannot drift.
public enum RealtimeKeys {
    public static let workoutQueryKeys: [[String]] = [
        ["workout_sessions"], ["workout_sets"], ["exercises"], ["routine_template"], ["continuum"], ["day_vault"],
        ["readiness_today"], ["weekly_volume"], ["session_trends"], ["weekly_export"], ["muscle_analytics"],
        ["exercise_history"], ["session_intel"], ["session_detail"], ["gym_reports"], ["month_activity"], ["trends"],
        ["weekly_review"], ["coach"], ["session_global_number"], ["week_recovery"],
        ["week_so_far"], ["effort_baseline"], ["session_pr_records"], ["session_metrics_seed"], ["doms_sources"],
        ["personal_records"], ["progression_queue"], ["doms_logs"],
    ]

    /// Table → keys, in the TS object's order.
    public static let tableKeys: [(String, [[String]])] = [
        ("daily_logs", [["daily_logs"], ["today"], ["readiness_today"], ["coach"], ["trends"], ["continuum"], ["day_vault"], ["sleep_debt"]]),
        ("daily_metrics", [["daily_logs"], ["today"], ["readiness_today"], ["day_vault"]]),
        ("nutrition_entries", [["nutrition_entries"], ["daily_logs"], ["today"], ["coach"], ["continuum"], ["day_vault"]]),
        ("body_composition", [["body_composition"], ["trends"], ["coach"]]),
        ("sleep_sessions", [["sleep_sessions"], ["today"], ["readiness_today"], ["trends"], ["weekly_review"], ["sleep_debt"]]),
        ("workout_sessions", workoutQueryKeys),
        ("workout_sets", workoutQueryKeys),
        ("daily_scores", [["today"], ["readiness_today"], ["daily_logs"], ["weekly_review"], ["trends"], ["coach"], ["continuum"], ["day_vault"], ["month_activity"], ["week_recovery"]]),
        ("supplement_log", [["supplement_log"], ["day_vault"]]),
        ("water_intake", [["water_intake"], ["today"], ["day_vault"], ["continuum"], ["weekly_review"]]),
        ("reports", [["reports"], ["weekly_review"]]),
        ("user_goals", [["user_goals"], ["today"], ["readiness_today"], ["coach"], ["day_vault"], ["nutrition_entries"]]),
        ("schedule_overrides", [["schedule_overrides"], ["day_vault"], ["daily_logs"], ["workout_sessions"], ["supplement_log"]]),
        // ── W4: the sixteen tables the socket was blind to ─────────────────
        // Each list is the one the table's OWN mutation cascades, copied rather
        // than invented, so the socket and the local write refresh the same
        // surfaces. the web app's `tests/query-key-coverage.test.ts` fails on any prefix
        // here with no registered `useQuery`.
        ("cardio_logs", [["cardio_logs"]]),
        ("fatigue_logs", [["fatigue_logs"]]),
        ("doms_logs", [["doms_logs"], ["doms_sources"], ["weekly_export"]]),
        ("custom_supplements", [["custom_supplements"], ["weekly_export"], ["supplement_log"]]),
        ("daily_targets", [["daily_targets"], ["weekly_export"], ["today"], ["day_vault"]]),
        ("target_profiles", [["target_profiles"], ["daily_targets"]]),
        ("routine_templates", [["routine_template"]]),
        ("program_day_layout", [["program_day_layout"]]),
        ("plan_phase_goals", [["plan_phase_goals"], ["user_goals"], ["today"], ["readiness_today"], ["coach"], ["day_vault"], ["nutrition_entries"]]),
        ("plan_phase_volume", [["plan_phase_goals"], ["weekly_volume"], ["muscle_analytics"]]),
        ("personal_records", [["personal_records"], ["session_pr_records"], ["session_detail"], ["weekly_review"]]),
        ("exercises", [["exercises"], ["exercise_history"]]),
        ("profiles", [["my-profile"]]),
    ]

    public static var tables: [String] { tableKeys.map(\.0) }

    public static func keys(for table: String) -> [[String]]? { tableKeys.first { $0.0 == table }?.1 }
}
