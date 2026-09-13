import Foundation

// The coach headline — the web app's `lib/coach/scheduleReadiness.ts`.
//
// The base readiness is the scored one (`Readiness.compute`). This makes it
// aware of the plan: never "Rest Today" on a scheduled training day, and on a
// scheduled rest day it says so unless a session was logged anyway.

public struct ScheduleReadinessContext: Codable, Sendable, Equatable {
    /// Today's scheduled day label, nil on a rest day.
    public var dayLabel: String?
    public var workoutToday: Bool
    public var contextMode: String
    public var reentry: Bool

    public init(dayLabel: String?, workoutToday: Bool, contextMode: String, reentry: Bool) {
        self.dayLabel = dayLabel
        self.workoutToday = workoutToday
        self.contextMode = contextMode
        self.reentry = reentry
    }
}

public enum ScheduleReadiness {
    /// `isReentryWeek` in `programs.ts` — the fortnight after the July break.
    public static func isReentryWeek(_ iso: String) -> Bool {
        iso >= "2026-07-19" && iso <= "2026-08-01"
    }

    public static func apply(_ base: ReadinessResult?, _ ctx: ScheduleReadinessContext) -> ReadinessResult? {
        if ctx.contextMode == "travel" {
            return ReadinessResult(
                level: .trainLight, label: "Travel Mode 🌴", color: "#8E9AAC",
                reason: "Vacation protocol — 2–3 short maintenance sessions this week is plenty. Prioritize rest, sun, and enjoying the trip.")
        }
        if ctx.dayLabel == nil && !ctx.workoutToday {
            return ReadinessResult(
                level: .rest, label: "Zone-2 / Rest", color: "#79808C",
                reason: "Scheduled rest in Onyx-5 — Zone-2 cardio (150–250 kcal) or full recovery.")
        }
        if let name = ctx.dayLabel {
            if ctx.reentry {
                return ReadinessResult(
                    level: .trainLight, label: "\(name) · Re-Entry", color: "#3D7AB8",
                    reason: "Re-entry week: ~90% loads, RPE cap 7–8. No PRs — groove the movements.")
            }
            guard let base, base.level != .trainHard else {
                return ReadinessResult(
                    level: .trainHard, label: name, color: "#3E9E7A",
                    reason: "Scheduled \(name) — recovery looks strong, train hard.")
            }
            if base.level == .rest {
                return ReadinessResult(
                    level: .trainLight, label: "\(name) · Go Light", color: "#D4AF37",
                    reason: "Scheduled \(name), but recovery is low — keep it light and technical.")
            }
            var copy = base
            copy.label = name
            return copy
        }
        return base
    }
}
