import Foundation

/// How one logged set reads, everywhere — a port of the web app's `lib/utils/setFormat.ts`.
///
/// An unloaded set's record IS its rep count or its duration, so that is what
/// gets rendered: `60kg × 12` · `17 reps` · `58 sec`. Never "0kg × 17".
public enum SetFormat {
    /// True when the set carries no external load.
    public static func isUnloaded(_ weightKg: Double?) -> Bool {
        guard let w = weightKg, w.isFinite else { return true }
        return w <= 0
    }

    /// One set as text. `timed` means `reps` carries SECONDS; `bare` drops the
    /// unit words for a column that already names them.
    /// `toDisplay` is the unit conversion the caller injects (kg → lb); a nil result prints as JS does, "null".
    public static func format(weightKg: Double?, reps: Double?, timed: Bool = false, unit: String = "kg", bare: Bool = false, toDisplay: ((Double) -> Double?)? = nil) -> String {
        let n = reps ?? 0
        let ns = jsIntegerString(n)
        if timed { return bare ? "\(ns)s" : "\(ns) sec" }
        if isUnloaded(weightKg) { return bare ? ns : "\(ns) rep\(n == 1 ? "" : "s")" }
        let w: Double? = toDisplay.map { $0(weightKg!) } ?? weightKg
        return "\(w.map(jsIntegerString) ?? "null")\(unit) × \(ns)"
    }

    /// A set that is not reps and kilograms — `5:00 · 0.37 km · 2% · 7 m`.
    ///
    /// A SIBLING of `format`, not a branch inside it: `format` is parity-locked
    /// by a golden vector and its contract is that a set has a load and a rep
    /// count. A treadmill has neither (`weight_kg 0, reps 0`), so it would need
    /// a third shape behind a fourth argument and every existing caller's
    /// output would start depending on fields it does not pass.
    ///
    /// `nil` when the set carries no cardio axis at all — which is what hands
    /// the row back to `format`, and is the ordinary case.
    ///
    /// A component is dropped when absent, non-finite or zero. Incline reads
    /// `!= 0` rather than `> 0`: a DECLINE is a real treadmill setting and an
    /// unstated one is not.
    ///
    /// Ascent is LAST and takes the `> 0` rule, not incline's. Total ascent is
    /// non-negative by definition — a descent is not negative ascent, it is a
    /// different measurement nothing here holds — so a zero and an absence say
    /// the same thing, exactly as they do for distance.
    ///
    /// It is rendered rather than computed from the two components before it:
    /// they agree only while the incline never moved, and when they disagree
    /// this is the measured one. See `cardio-elevation.sql (git history)`.
    public static func cardio(durationSec: Double?, distanceKm: Double?, incline: Double?, elevationM: Double?) -> String? {
        func ok(_ v: Double?) -> Double? { v.flatMap { $0.isFinite ? $0 : nil } }
        var parts: [String] = []
        if let d = ok(durationSec), d > 0 { parts.append(clock(d)) }
        if let km = ok(distanceKm), km > 0 { parts.append("\(jsIntegerString(km)) km") }
        if let i = ok(incline), i != 0 { parts.append("\(jsIntegerString(i))%") }
        if let e = ok(elevationM), e > 0 { parts.append("\(jsIntegerString(e)) m") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Seconds as `5:00`.
    ///
    /// Rounded to the nearest second and split afterwards, for the reason
    /// `CardioMetrics.formatPace` gives: flooring twice loses a second to
    /// binary error.
    ///
    /// Public because the session ledger draws a bout's duration in a column of
    /// its own now, beside the distance and the pace, rather than inside the
    /// joined string `cardio(…)` returns. One formatter, two callers — the
    /// alternative was six lines of the same arithmetic in a view, allowed to
    /// disagree with this one about a rounding.
    public static func clock(_ seconds: Double) -> String {
        let total = jsRound(seconds)
        let mins = (total / 60).rounded(.down)
        var ss = jsIntegerString(total.truncatingRemainder(dividingBy: 60))
        while ss.count < 2 { ss = "0" + ss }
        return "\(jsIntegerString(mins)):\(ss)"
    }
}
