import Foundation

/// What a date is graded against, in one value. A port of
/// the web app's `lib/nutrition/targets.ts`.
///
/// ── THE CHAIN, STATED ONCE ──────────────────────────────────────────────────
/// Your own numbers → the rung in force ON THAT DATE (`Levers.goalsForDate`:
/// the schedule for the past, the stored selection for today and after, a
/// release that expires) → the day's own `daily_targets` row on top
/// (`DailyTargets.apply`: field by field, untracked to nil). Water and sleep
/// have no rung and no day override; they pass straight through from the row.
///
/// The chain used to be copied into the scorer, the widget snapshot, the
/// Nutrition tab and the Pulse strip — four readers, four places for a date
/// rule to drift. `ResolvedTargets` is what all of them read now.
public struct ResolvedTargets: Codable, Equatable, Sendable {
    /// Zero is an unset row, not a fast. Readers treat `> 0` as a target.
    public var kcal: Double
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public var steps: Double?
    public var waterMl: Double?
    public var sleepHours: Double?
    /// The rung in force on the date (a `target_profiles` key), or nil.
    public var leverId: String?
    /// The profile the day's figures MATCH — not the stamp — or nil.
    public var profileKey: String?

    public init(
        kcal: Double, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil, steps: Double? = nil,
        waterMl: Double? = nil, sleepHours: Double? = nil, leverId: String? = nil, profileKey: String? = nil
    ) {
        self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat; self.steps = steps
        self.waterMl = waterMl; self.sleepHours = sleepHours; self.leverId = leverId; self.profileKey = profileKey
    }

    /// The five rung-shaped figures, for readers that still speak `LeverGoals`.
    public var goals: LeverGoals {
        LeverGoals(calorie: kcal, protein: protein, carbs: carbs, fat: fat, steps: steps)
    }
}

/// Everything `Targets.resolve` reads. Rows, translated, with no date in them:
/// the same sources answer for every date.
public struct TargetSources: Codable, Equatable, Sendable {
    /// The user's own five numbers, before any rung.
    public var own: LeverGoals
    public var waterMl: Double?
    public var sleepHours: Double?
    /// `user_goals.active_lever` / `maintenance_until`, as stored.
    public var activeLever: String?
    public var maintenanceUntil: String?
    /// The date's `daily_targets` row, or nil.
    public var dayTarget: DailyTarget?
    /// The user's stored profiles, EVERY kind: the day shapes and the rungs.
    public var profiles: [TargetProfile]
    /// `lever_periods` — when each rung came into force.
    public var periods: [LeverPeriod]

    public init(
        own: LeverGoals, waterMl: Double? = nil, sleepHours: Double? = nil,
        activeLever: String? = nil, maintenanceUntil: String? = nil,
        dayTarget: DailyTarget? = nil, profiles: [TargetProfile] = [], periods: [LeverPeriod] = []
    ) {
        self.own = own; self.waterMl = waterMl; self.sleepHours = sleepHours
        self.activeLever = activeLever; self.maintenanceUntil = maintenanceUntil
        self.dayTarget = dayTarget; self.profiles = profiles; self.periods = periods
    }

    /// The rungs, the schedule and the selection, as `Levers` reads them.
    public var ladder: LeverLadder {
        LeverLadder(profiles: profiles, periods: periods, stored: activeLever, releaseEndsOn: maintenanceUntil)
    }
}

public enum Targets {
    /// The day shapes the picker offers — stored rows only (W2: no built-ins).
    public static func profiles(stored: [TargetProfile]) -> [TargetProfile] {
        TargetProfiles.days(stored)
    }

    public static func resolve(_ s: TargetSources, date: String, today: String) -> ResolvedTargets {
        let ladder = s.ladder
        let goals = DailyTargets.apply(
            Levers.goalsForDate(date, today: today, fallback: s.own, in: ladder),
            s.dayTarget
        )
        return ResolvedTargets(
            kcal: goals.calorie, protein: goals.protein, carbs: goals.carbs, fat: goals.fat, steps: goals.steps,
            waterMl: s.waterMl, sleepHours: s.sleepHours,
            leverId: Levers.leverForDate(date, today: today, in: ladder),
            profileKey: profiles(stored: s.profiles).first { TargetProfiles.matches(s.dayTarget, $0) }?.key
        )
    }
}
