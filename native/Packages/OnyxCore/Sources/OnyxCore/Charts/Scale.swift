import Foundation

/// Axis scaling — a port of the web app's `lib/charts/scale.ts`. A "nice" domain fitted to
/// the DATA, not to zero; a tight domain that zooms with a floor on the span.
public enum ChartScale {
    /// Round `x` up to the next 1/2/5 × 10ⁿ.
    static func niceStep(_ x: Double) -> Double {
        guard x.isFinite, x > 0 else { return 1 }
        let mag = pow(10.0, floor(log10(x)))
        let norm = x / mag
        let step: Double = norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10
        return step * mag
    }

    static func round6(_ n: Double) -> Double { jsRound(n * 1e6) / 1e6 }

    static func finite(_ values: [Double?]) -> [Double] { values.compactMap { $0 }.filter(\.isFinite) }

    /// A readable [min, max]. Empty → [0, 1]; a flat series gets breathing room.
    public static func niceDomain(_ values: [Double?], padPct: Double = 0.1, zeroBased: Bool = false, hardMin: Double? = nil) -> (Double, Double) {
        let nums = finite(values)
        guard !nums.isEmpty else { return (0, 1) }
        var lo = nums.min()!, hi = nums.max()!
        if lo == hi {
            var pad = abs(lo) * 0.1
            if pad == 0 { pad = 1 }
            lo -= pad; hi += pad
        } else {
            let pad = (hi - lo) * padPct
            lo -= pad; hi += pad
        }
        if zeroBased { lo = min(0, lo) }
        if let h = hardMin { lo = max(h, lo) }
        let step = niceStep((hi - lo) / 4)
        let flooredLo = floor(lo / step) * step
        let ceiledHi = ceil(hi / step) * step
        return (round6(flooredLo), round6(ceiledHi))
    }

    /// Compact axis label for a mass in kg — one decimal below 10 t.
    public static func compactKg(_ v: Double?) -> String {
        guard let v = v, v.isFinite else { return "—" }
        let a = abs(v)
        if a >= 10_000 { return "\(jsIntegerString(jsRound(v / 1000)))k" }
        if a >= 1_000 { return "\(jsToFixed(v / 1000, 1))k" }
        return jsIntegerString(jsRound(v))
    }

    /// A domain that ZOOMS, never narrower than `minSpanPct` of the midpoint.
    public static func tightDomain(_ values: [Double?], padPct: Double = 0.06, hardMin: Double? = nil, minSpanPct: Double = 0.005) -> (Double, Double) {
        let nums = finite(values)
        guard !nums.isEmpty else { return (0, 1) }
        var lo = nums.min()!, hi = nums.max()!
        let mid = (lo + hi) / 2
        var floorSpan = abs(mid) * minSpanPct
        if floorSpan == 0 { floorSpan = 1 }
        if hi - lo < floorSpan {
            let half = floorSpan / 2
            lo = mid - half; hi = mid + half
        }
        let pad = (hi - lo) * padPct
        lo -= pad; hi += pad
        if let h = hardMin { lo = max(h, lo) }
        let rLo = round6(lo), rHi = round6(hi)
        if rHi > rLo { return (rLo, rHi) }
        var reopen = abs(rLo) * minSpanPct
        if reopen == 0 { reopen = 1 }
        return (rLo, rLo + reopen)
    }

    /// An axis bound at the precision the axis actually has.
    public static func axisBound(_ value: Double?, span: Double) -> String {
        guard let value = value, value.isFinite else { return "—" }
        let rounding: Double = abs(value) >= 10_000 ? 1000 : abs(value) >= 1_000 ? 100 : 1
        if span >= rounding * 2 { return compactKg(value) }
        return jsLocaleString(jsRound(value))
    }
}
