import Foundation

// The coach headline — the web app's `lib/coach/scheduleReadiness.ts`.
//
// The base readiness is the scored one (`Readiness.compute`). This makes it
// aware of the plan: never "Rest Today" on a scheduled training day, and on a
// scheduled rest day it says so unless a session was logged anyway.
//
// ── EVERY INPUT IS THE CALLER'S (W-SPRINT) ───────────────────────────────────
// This file used to answer two questions out of constants of its own:
//
//   · `isReentryWeek(iso)` — true between 2026-07-19 and 2026-08-01, the
//     fortnight after ONE athlete's July break. Anybody else training in that
//     window was told to cap RPE and attempt no PRs for a reason that did not
//     exist for them, and no user could ever mark their own re-entry.
//   · the rest-day line named "Onyx-5" and prescribed "150–250 kcal" of Zone-2
//     — his plan, and his calorie band, printed to whoever was reading.
//
// Both are now passed in: `reentry` comes off `schedule_overrides`
// (`Schedule.isReentry`, the `reentry` sentinel in `day_key`) and `programLabel`
// off the `plans` row that owns the date (`Schedule.planLabel(owning:in:)`).
// Nothing in here knows a date, a plan or a calorie target any more.

public struct ScheduleReadinessContext: Codable, Sendable, Equatable {
    /// Today's scheduled day label, nil on a rest day.
    public var dayLabel: String?
    public var workoutToday: Bool
    public var contextMode: String
    public var reentry: Bool
    /// The plan that owns today, for the rest-day line. nil when the caller has
    /// no plan row to name — the line then simply does not name one, which is
    /// the honest version of what a hardcoded name was pretending to be.
    public var programLabel: String?

    public init(
        dayLabel: String?, workoutToday: Bool, contextMode: String, reentry: Bool,
        programLabel: String? = nil
    ) {
        self.dayLabel = dayLabel
        self.workoutToday = workoutToday
        self.contextMode = contextMode
        self.reentry = reentry
        self.programLabel = programLabel
    }
}

public enum ScheduleReadiness {

    public static func apply(_ base: ReadinessResult?, _ ctx: ScheduleReadinessContext) -> ReadinessResult? {
        if ctx.contextMode == "travel" {
            return ReadinessResult(
                level: .trainLight, label: "Travel Mode 🌴", color: "#8E9AAC",
                reason: "Vacation protocol — 2–3 short maintenance sessions this week is plenty. Prioritize rest, sun, and enjoying the trip.")
        }
        if ctx.dayLabel == nil && !ctx.workoutToday {
            // The plan's name when the caller knows it, and no name at all when
            // it does not. No dose: how much Zone-2 a rest day is worth is a
            // function of the athlete's own targets, not of this sentence.
            let scheduled = ctx.programLabel.map { "Scheduled rest in \($0)" } ?? "Scheduled rest"
            return ReadinessResult(
                level: .rest, label: "Zone-2 / Rest", color: "#79808C",
                reason: "\(scheduled) — Zone-2 cardio or full recovery.")
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
