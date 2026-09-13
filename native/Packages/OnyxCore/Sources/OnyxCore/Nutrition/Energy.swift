import Foundation

/// The canonical energy-expenditure arithmetic — a port of
/// the web app's `lib/nutrition/energy.ts`. One definition of TDEE, so no two surfaces can
/// disagree about what a day cost.
///
/// `TDEE = BMR + active energy + TEF`.
public enum Energy {
    /// TEF as a fraction of intake.
    ///
    /// Mixed diets land at 10–12%; protein alone runs 20–30%, carbohydrate
    /// 5–10%, fat 0–3%. 10.5% is the mid-point for a mixed, protein-forward
    /// intake and is the figure this programme has adopted.
    ///
    /// Deliberately a flat fraction of total kcal rather than a per-macro sum: a
    /// macro-weighted TEF is more precise in principle, but the macro splits it
    /// would run on are themselves device estimates.
    public static let tefFactor: Double = 0.105

    /// Thermic effect of a day's intake. Nil intake gives nil — never 0.
    public static func tef(intakeKcal: Double?) -> Double? {
        guard let intake = intakeKcal, intake.isFinite else { return nil }
        return intake * tefFactor
    }

    /// Total daily energy expenditure. Nil unless BMR, active energy **and**
    /// intake are all present.
    ///
    /// ── ALL-OR-NOTHING ON PURPOSE ───────────────────────────────────────────
    /// A missing component treated as zero does not make the estimate slightly
    /// wrong, it makes it wrong in a way that reads as a finding: a day with no
    /// active-energy sync would report a 400 kcal larger deficit than it earned.
    /// A nil propagates; a zero lies.
    ///
    /// Digestion is not free, and leaving TEF out understates expenditure by the
    /// same amount every single day — on a ~1900 kcal intake that is ~200
    /// kcal/day, ~1400 kcal/week. A deficit that is systematically too small in
    /// the same direction every day is worse than a noisy one, because it never
    /// averages out.
    public static func tdee(bmr: Double?, active: Double?, intakeKcal: Double?) -> Double? {
        guard let tefValue = tef(intakeKcal: intakeKcal) else { return nil }
        guard let bmr, bmr.isFinite else { return nil }
        guard let active, active.isFinite else { return nil }
        return bmr + active + tefValue
    }

    /// `BMR 1500 + active 890 + TEF 210` — one shared phrasing for the
    /// breakdown. Digits are deliberately unseparated: its main consumer prints
    /// every other figure on the line plain, and a lone `1,500` beside a plain
    /// `2600` reads as two different kinds of number.
    public static func tdeeBreakdown(bmr: Double, active: Double, tef: Double) -> String {
        func r(_ v: Double) -> String { String(Int(jsRound(v))) }
        return "BMR \(r(bmr)) + active \(r(active)) + TEF \(r(tef))"
    }
}
