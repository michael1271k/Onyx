import Foundation

/// The waypoints on the steps tile's track — `stepMarks` from
/// the web app's `components/dashboard/widgets/DailyWidgets.tsx`.
///
/// Derived from the goal rather than hardcoded at 2/4/6/8/10k: the goal is a
/// user setting, and a fixed ladder would put five marks under a 6,000-step
/// goal with three of them already past the end of the track. The step is a
/// fifth of the goal snapped to 500 (`Math.round`, so `jsRound`), never below
/// 500; the goal itself is always the last mark.
public enum StepMarks {
    public static func marks(goal: Int) -> [Int] {
        let step = max(500, Int(jsRound(Double(goal) / 5 / 500)) * 500)
        return [step, step * 2, step * 3, step * 4].filter { $0 < goal } + [goal]
    }
}
