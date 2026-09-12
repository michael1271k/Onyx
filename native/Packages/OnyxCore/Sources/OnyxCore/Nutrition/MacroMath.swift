import Foundation

/// The arithmetic behind a macro edit: change one figure, and the other three
/// stay a set of numbers that can be true at the same time. A port of
/// the web app's `lib/nutrition/macroMath.ts`, which is the golden source.
///
/// ── THE ONE RULE ────────────────────────────────────────────────────────────
/// Calories are ALWAYS the Atwater sum of the macros on screen — 4 · protein +
/// 4 · carbohydrate + 9 · fat. A sheet that shows 1,955 kcal beside macros that
/// add to 1,880 is asking which number is a lie, and the answer would be
/// "both".
///
/// So editing a MACRO recomputes the calories, and editing the CALORIES moves
/// the macros until they add up. Protein is pinned through a calorie edit
/// because protein is the one figure this athlete's targets are built on;
/// carbohydrate and fat absorb the difference in proportion to the energy they
/// already carry (`c·4 : f·9`), which keeps the shape of the day rather than
/// dumping a deficit into one macro.
public enum MacroMath {

    /// The four figures a day is edited as. A `nil` macro is UNTRACKED — a day
    /// that does not grade carbohydrate has no carbohydrate figure, and it must
    /// not be handed one by arithmetic.
    public struct Macros: Codable, Equatable, Sendable {
        public var kcal: Double
        public var protein: Double?
        public var carbs: Double?
        public var fat: Double?

        public init(kcal: Double = 0, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil) {
            self.kcal = kcal
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
        }

        /// What the macros on screen actually come to.
        public var atwater: Double {
            Levers.atwaterKcal(proteinG: protein ?? 0, carbsG: carbs ?? 0, fatG: fat ?? 0)
        }
    }

    /// Which stepper moved, and to what.
    public enum Edit: Equatable, Sendable {
        case calories(Double)
        case protein(Double)
        case carbs(Double)
        case fat(Double)
    }

    /// Grams are whole numbers here. A scale reads to the gram, HealthKit
    /// stores to the gram, and a stepper that lands on 42.3333 g is arithmetic
    /// leaking into the interface. `jsRound`, so a half rounds the way the
    /// TypeScript rounds it.
    static func grams(_ value: Double) -> Double { max(0, jsRound(value)) }

    public static func adjust(_ current: Macros, edited: Edit) -> Macros {
        var next = current
        switch edited {
        case let .protein(value): next.protein = grams(value)
        case let .carbs(value):   next.carbs = grams(value)
        case let .fat(value):     next.fat = grams(value)
        case let .calories(value):
            let target = max(0, jsRound(value))
            next = absorb(current, into: target)
            // Nothing tracked can move, so the macros cannot restate the
            // figure. Keep the figure rather than answering with a zero.
            if current.carbs == nil, current.fat == nil {
                next.kcal = target
                return next
            }
        }
        // Every other path ends here: the calories are the macros, restated.
        next.kcal = next.atwater
        return next
    }

    /// Move carbohydrate and fat until the day comes to `target` kcal.
    ///
    /// The split is by the ENERGY each macro currently carries (`c·4 : f·9`), so
    /// a 60/40 day stays roughly 60/40. A macro that is untracked takes none of
    /// it; when neither is tracked there is nowhere for the difference to go
    /// and the target stands as asked.
    ///
    /// ── WHY THIS IS A LOOP AND NOT TWO PASSES ───────────────────────────────
    /// Whole grams cannot always restate a figure in one pass — a carbohydrate
    /// gram is 4 kcal and a fat gram 9 — so the residual is fed back in, at
    /// most four rounds. A two-pass version took a macro's whole share or none
    /// of it, so asking for 327 kcal landed on 324 while 326 landed on 328: the
    /// same request had two answers and raising the ask could lower the
    /// reading. The loop is idempotent and monotonic (`MacroMathTests` sweeps
    /// both), which is what a stepper under a finger needs.
    static func absorb(_ current: Macros, into target: Double) -> Macros {
        var next = current
        guard current.carbs != nil || current.fat != nil else { return next }
        guard target != current.atwater else { return next }

        for _ in 0..<4 {
            let delta = target - next.atwater
            guard abs(delta) >= 1 else { break }

            let carbEnergy = (next.carbs ?? 0) * 4
            let fatEnergy = (next.fat ?? 0) * 9
            let pool = carbEnergy + fatEnergy
            // A macro sitting at zero has no share of a ratio, so a pool built
            // from the current grams would freeze it there forever.
            // Carbohydrate is this athlete's buffer — the macro a lever moves
            // first — so it takes the whole difference whenever the ratio
            // cannot speak.
            let carbShare: Double
            if pool > 0 && (next.carbs ?? 0) > 0 && (next.fat ?? 0) > 0 {
                carbShare = carbEnergy / pool
            } else if next.carbs != nil {
                carbShare = 1
            } else {
                carbShare = 0
            }

            let before = next
            if next.carbs != nil {
                next.carbs = grams((next.carbs ?? 0) + delta * carbShare / 4)
            }
            if next.fat != nil {
                next.fat = grams((next.fat ?? 0) + delta * (1 - carbShare) / 9)
            }
            // Clamped at the floor with nowhere left to go: protein alone is
            // already more than the figure asked for.
            if next == before { break }
        }
        return next
    }
}
