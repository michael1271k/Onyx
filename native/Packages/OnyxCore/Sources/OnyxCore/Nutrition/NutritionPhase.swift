import Foundation

/// Daily nutrition phase, derived from the day's calories.
///
///     CUT DAY      ≤ 2,050 kcal
///     MAINTENANCE  2,051 – 2,449 kcal
///     BULK         ≥ 2,450 kcal
///
/// (Re-derive the bands by hand after any bodyweight change over 2 kg.)
///
/// Computed at write time and stored on `nutrition_entries.phase` — the database
/// is the source of truth — with `derive` as a client-side fallback for old rows.
public enum NutritionPhase: String, Codable, Sendable, CaseIterable {
    case cut
    case maintenance
    case bulk

    /// The chip label. `Cut` / `Maint` / `Bulk`.
    ///
    /// The TypeScript reaches this through `phaseDisplay(phase, dateISO)`, which
    /// special-cases a cut on or after the founder's cut-start constant to label it "Cut" — the
    /// same string `PHASE_META.cut` already carries. The branch has been a no-op
    /// since the era rename, so it is not ported; the date parameter went with
    /// it. If the two labels ever need to differ again, that is a real change
    /// and it should arrive with a case that proves it.
    public var label: String {
        switch self {
        case .cut: "Cut"
        case .maintenance: "Maint"
        case .bulk: "Bulk"
        }
    }

    /// The phase a day's calorie total implies, on its own.
    ///
    /// Nil for an untracked day. Zero and negative are untracked too, not a cut:
    /// a row with no intake recorded says nothing about the block you are in.
    public static func derive(calories: Double?) -> NutritionPhase? {
        guard let calories, calories.isFinite, calories > 0 else { return nil }
        if calories <= 2050 { return .cut }
        if calories < 2450 { return .maintenance }
        return .bulk
    }

    /// What a day needs to know about itself before it can name its phase.
    public struct DayInput: Sendable {
        public var calories: Double?
        /// `daily_logs.nutrition_exception` — a reason string, or nil.
        public var exception: String?
        /// `daily_logs.nutrition_estimated`.
        public var estimated: Bool?
        /// The phase the era is actually IN — `user_goals.goal_preset`.
        public var activePhase: NutritionPhase?
        /// The value already on `nutrition_entries.phase`, when there is one.
        ///
        /// Readers pass it; writers do not. It is a CACHE of this function's own
        /// answer from write time, so it wins for an ordinary day — cheap, and it
        /// preserves historical banding — but never for a flagged one: rows
        /// written before this rule existed carry exactly the misclassification
        /// being corrected.
        public var stored: NutritionPhase?

        public init(
            calories: Double?, exception: String? = nil, estimated: Bool? = nil,
            activePhase: NutritionPhase? = nil, stored: NutritionPhase? = nil
        ) {
            self.calories = calories
            self.exception = exception
            self.estimated = estimated
            self.activePhase = activePhase
            self.stored = stored
        }
    }

    /// The day's phase, WITHOUT letting one meal rewrite the block you are in.
    ///
    /// `derive` reads a phase off the calorie total alone, which is right for an
    /// ordinary day and wrong for a declared one. 2026-08-11 was a date night:
    /// 2,150 kcal, flagged `Social` and `Estimated`, in week four of a strict
    /// cut. The threshold saw 2,050 < 2,150 < 2,450 and stamped `maintenance`,
    /// so the history page filed a cut day under a phase that had not started
    /// and will not start for months. The phase is a property of the BLOCK, not
    /// of one evening's intake.
    ///
    /// So a flagged day — Exception or Estimated, either one — keeps the active
    /// phase. Both qualify: an Exception says the deviation was allowed, an
    /// Estimated says the number is a guess, and neither is evidence that the
    /// programme changed. Reclassifying on a guess is the worse of the two.
    ///
    /// NOTHING NUMERIC CHANGES here. This is a label, not a term in any score.
    public static func resolve(_ input: DayInput) -> NutritionPhase? {
        let fallback = input.stored ?? derive(calories: input.calories)
        let flagged = ExceptionDay.isException(input.exception) || input.estimated == true
        guard flagged else { return fallback }
        return input.activePhase ?? fallback
    }
}
