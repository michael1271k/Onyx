import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Calories and heart rate for a session that carries neither. A port of
// the web app's `lib/sessions/estimates.ts`.
//
// Every number here is an ESTIMATE and is stamped as one by the caller. It only
// ever fills a gap. Calories: your OWN median kcal/min for this split first
// (median, so one watch-left-on-through-lunch session cannot drag it), the ACSM
// compendium figure (MET 6.0) scaled on bodyweight second. Heart rate: the last
// comparable session's, carried forward — there is no formula for it.
// ─────────────────────────────────────────────────────────────────────────────

public struct KcalSample: Codable, Equatable, Sendable {
    public var kcal: Double
    public var durationMin: Double
    public init(kcal: Double, durationMin: Double) { self.kcal = kcal; self.durationMin = durationMin }
}

public struct CalorieEstimate: Codable, Equatable, Sendable {
    public enum Basis: String, Codable, Sendable { case personalMedian = "personal-median", metFormula = "met-formula" }
    public var kcal: Double
    public var basis: Basis
}

public enum Estimates {
    /// ACSM Compendium: resistance training, vigorous effort.
    public static let liftingMet = 6.0
    /// Below this many measured sessions, the compendium is the better guess.
    public static let minKcalSamples = 5
    /// How far back a sample may come from and still describe you.
    public static let kcalSampleWindowDays = 90

    /// `MET × 3.5 × kg / 200`. Nil without a positive bodyweight.
    public static func metKcalPerMin(bodyweightKg: Double?) -> Double? {
        guard let bw = bodyweightKg, bw.isFinite, bw > 0 else { return nil }
        return (liftingMet * 3.5 * bw) / 200
    }

    /// Median kcal/min across usable samples, or nil below the floor.
    public static func medianKcalPerMin(_ samples: [KcalSample]) -> Double? {
        let rates = samples
            .filter { $0.kcal.isFinite && $0.durationMin.isFinite && $0.kcal > 0 && $0.durationMin > 0 }
            .map { $0.kcal / $0.durationMin }
            .sorted()
        if rates.count < minKcalSamples { return nil }
        let mid = rates.count / 2
        return rates.count % 2 == 1 ? rates[mid] : (rates[mid - 1] + rates[mid]) / 2
    }

    /// Personal median first, the MET formula second, nil when neither can fire.
    public static func estimateCalories(durationMin: Double?, samples: [KcalSample], bodyweightKg: Double?) -> CalorieEstimate? {
        guard let durationMin, durationMin.isFinite, durationMin > 0 else { return nil }
        if let personal = medianKcalPerMin(samples) {
            return CalorieEstimate(kcal: jsRound(personal * durationMin), basis: .personalMedian)
        }
        if let met = metKcalPerMin(bodyweightKg: bodyweightKg) {
            return CalorieEstimate(kcal: jsRound(met * durationMin), basis: .metFormula)
        }
        return nil
    }

    /// The previous comparable session's average, carried forward and rounded.
    public static func estimateAvgBpm(previousBpm: Double?) -> Double? {
        guard let bpm = previousBpm, bpm.isFinite, bpm > 0 else { return nil }
        return jsRound(bpm)
    }
}
