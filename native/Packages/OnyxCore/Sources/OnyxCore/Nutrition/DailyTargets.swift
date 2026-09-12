import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Per-day target overrides — the layer above every rung. A port of
// the web app's `lib/nutrition/dailyTargets.ts`.
//
// It overrides FIELD BY FIELD: every column is nullable and nil means "no
// opinion, ask the layer below". And it reaches backwards, which nothing else
// in the resolution chain does — a per-day row IS a statement about one specific
// day, made deliberately.
//
// THE THIRD STATE. A macro used to be a number (the target) or nil (ask the
// rung). A restaurant day needs "there is no target for this, do not grade it",
// and a sentinel zero cannot say it — a stored zero is a broken row here on
// purpose. So tracking is its own flag: `false` means untracked, and nil / true
// both mean tracked, which is what every row written before the flag existed
// meant. An untracked macro RESOLVES TO NIL — not zero, and not the rung's
// figure — and the scorer skips a goal that is not > 0 without any change.
// ─────────────────────────────────────────────────────────────────────────────

/// One row of `daily_targets`. Column names match Postgres on the wire.
public struct DailyTarget: Codable, Equatable, Sendable {
    public var date: String
    public var kcal: Double?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    public var stepsGoal: Double?
    public var note: String?
    /// Which named profile this day was given — a LABEL, not a foreign key.
    /// The figures beside it are a snapshot taken when the profile was applied.
    public var profileKey: String?
    public var trackCarbs: Bool?
    public var trackFat: Bool?

    enum CodingKeys: String, CodingKey {
        case date, kcal, note
        case proteinG = "protein_g", carbsG = "carbs_g", fatG = "fat_g", stepsGoal = "steps_goal"
        case profileKey = "profile_key", trackCarbs = "track_carbs", trackFat = "track_fat"
    }

    public init(
        date: String, kcal: Double? = nil, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil,
        stepsGoal: Double? = nil, note: String? = nil, profileKey: String? = nil, trackCarbs: Bool? = nil, trackFat: Bool? = nil
    ) {
        self.date = date; self.kcal = kcal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
        self.stepsGoal = stepsGoal; self.note = note; self.profileKey = profileKey; self.trackCarbs = trackCarbs; self.trackFat = trackFat
    }
}

public enum DailyTargets {
    /// Is this macro graded on this day? Absent flag and `true` both mean yes.
    public static func tracksCarbs(_ t: DailyTarget?) -> Bool { t?.trackCarbs != false }
    public static func tracksFat(_ t: DailyTarget?) -> Bool { t?.trackFat != false }

    /// Is there anything in this row at all? An all-nil row is not an override;
    /// an untrack flag alone IS — "stop grading fat" is a deliberate statement.
    public static func hasTarget(_ t: DailyTarget?) -> Bool {
        guard let t else { return false }
        if t.trackCarbs == false || t.trackFat == false { return true }
        return [t.kcal, t.proteinG, t.carbsG, t.fatG, t.stepsGoal].contains { v in
            if let v, v.isFinite, v > 0 { return true }
            return false
        }
    }

    /// Lay a day's overrides over already-resolved goals. `> 0` throughout: a
    /// stored zero is a broken row, not a fast.
    public static func apply(_ goals: LeverGoals, _ t: DailyTarget?) -> LeverGoals {
        guard let t, hasTarget(t) else { return goals }
        func pick(_ v: Double?, _ fallback: Double?) -> Double? {
            if let v, v.isFinite, v > 0 { return v }
            return fallback
        }
        return LeverGoals(
            calorie: pick(t.kcal, goals.calorie) ?? goals.calorie,
            protein: pick(t.proteinG, goals.protein),
            // UNTRACKED RESOLVES TO NIL, AND THAT IS THE WHOLE MECHANISM.
            carbs: tracksCarbs(t) ? pick(t.carbsG, goals.carbs) : nil,
            fat: tracksFat(t) ? pick(t.fatG, goals.fat) : nil,
            steps: pick(t.stepsGoal, goals.steps)
        )
    }
}
