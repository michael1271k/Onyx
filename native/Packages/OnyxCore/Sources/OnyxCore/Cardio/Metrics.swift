import Foundation

/// Derived cardio metrics — a port of the web app's `lib/cardio/metrics.ts`. Pace is
/// DERIVED, never stored: distance and duration are the facts, pace is a view.
public enum CardioMetrics {
    /// Minutes per kilometre, or nil when either input cannot support the ratio.
    public static func paceMinPerKm(distanceM: Double?, durationMin: Double?) -> Double? {
        guard let d = distanceM, let m = durationMin, d.isFinite, m.isFinite, d > 0, m > 0 else { return nil }
        return m / (d / 1000)
    }

    /// `6:24 /km` — rounded to the nearest SECOND first, then split, so 5.05
    /// min/km is 5:03 and not 5:02. A pace of 100 min/km or more is a typo.
    public static func formatPace(_ minPerKm: Double?) -> String {
        guard let p = minPerKm, p.isFinite, p > 0, p < 100 else { return "—" }
        let totalSec = jsRound(p * 60)
        let mins = (totalSec / 60).rounded(.down)
        let secs = totalSec.truncatingRemainder(dividingBy: 60)
        var ss = jsIntegerString(secs)
        while ss.count < 2 { ss = "0" + ss }
        return "\(jsIntegerString(mins)):\(ss) /km"
    }
}
