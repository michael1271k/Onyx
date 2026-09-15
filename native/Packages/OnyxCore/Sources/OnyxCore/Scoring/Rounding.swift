import Foundation

/// JavaScript's `Math.round`, which is **not** Swift's `rounded()`.
///
/// ── THE DIFFERENCE, AND WHY IT IS NOT ACADEMIC ──────────────────────────────
/// `Math.round` rounds a half **towards positive infinity**: `Math.round(2.5)`
/// is 3 and `Math.round(-2.5)` is -2. Swift's default `rounded()` rule is
/// `.toNearestOrAwayFromZero`, so `(-2.5).rounded()` is -3. Every function in
/// this package that mirrors a `Math.round` call must therefore use this, not
/// `rounded()`, or the port silently disagrees with its source on exactly the
/// inputs a test grid is least likely to contain.
///
/// The rest of the arithmetic needs no such treatment: JavaScript numbers and
/// Swift `Double` are both IEEE-754 binary64, so `+`, `-`, `*`, `/` and `cos`
/// agree bit for bit. Rounding is the one place the two languages made
/// different choices, so it is the one place that needs a shim.
@inlinable
public func jsRound(_ x: Double) -> Double {
    // `floor(x + 0.5)` is the specification of Math.round, verbatim.
    (x + 0.5).rounded(.down)
}

/// `Math.round(x * 10) / 10` — one decimal place, JavaScript's rounding rule.
@inlinable
public func jsRound1(_ x: Double) -> Double {
    jsRound(x * 10) / 10
}

/// How JavaScript prints an integral number inside a template string: `70`,
/// never `70.0`. For a value that is not integral this falls back to Swift's
/// shortest round-trip description, which matches JavaScript's for every value
/// the scorer can produce (both are shortest-round-trip algorithms).
public func jsIntegerString(_ x: Double) -> String {
    if x == x.rounded(.towardZero), abs(x) < 1e15 {
        return String(Int64(x))
    }
    return String(x)
}

/// `Number.prototype.toFixed(1)`, which is **not** `String(format: "%.1f")`.
///
/// ── THE DIFFERENCE ───────────────────────────────────────────────────────────
/// Both work from the exact binary value of the double, so `4.05` — really
/// 4.04999999999999982… — prints `4.0` in both. They part on an exact tie:
/// `5.25` is exactly representable, and `toFixed` picks the LARGER candidate
/// (`5.3`) while printf rounds half to even (`5.2`). A sleep alert reading
/// "5.2h" on a night the web app called "5.3h" is the kind of drift the golden
/// vectors exist to catch, so the tie is decided here the ECMAScript way.
///
/// The exact expansion is read off `%.30f`. Thirty places is more than enough:
/// a double near any sleep duration cannot sit within 1e-20 of a tenth-tie
/// without being exactly on it, so the digits after the first decimal are either
/// `5000…` (a tie, round up) or unambiguous.
public func jsToFixed1(_ x: Double) -> String { jsToFixed(x, 1) }

/// `Number.prototype.toFixed(digits)` for any small `digits` — the same rule
/// as `jsToFixed1`: the exact decimal expansion decides, and an exact tie goes
/// to the LARGER candidate. `(-0.001).toFixed(2)` is `"-0.00"` in JavaScript
/// and here. Loads over 1e15 are not a thing this app prints; they fall back to
/// the shortest round-trip form rather than overflow.
public func jsToFixed(_ x: Double, _ digits: Int) -> String {
    guard x.isFinite, abs(x) < 1e15 else { return String(x) }
    let negative = x < 0
    let expanded = String(format: "%.40f", abs(x))
    let parts = expanded.split(separator: ".", maxSplits: 1)
    var integer = Int(parts[0])!
    let frac = Array(parts[1]).map { Int(String($0))! }
    var kept = Array(frac[0..<digits])
    if frac[digits] >= 5 {
        var i = digits - 1
        var carry = true
        while carry && i >= 0 {
            kept[i] += 1
            if kept[i] == 10 { kept[i] = 0; i -= 1 } else { carry = false }
        }
        if carry { integer += 1 }
    }
    let sign = negative ? "-" : ""
    let fraction = kept.map(String.init).joined()
    return digits == 0 ? "\(sign)\(integer)" : "\(sign)\(integer).\(fraction)"
}

/// `Math.round(x * 100) / 100` — two decimal places, JavaScript's rounding rule.
///
/// One caller, and it earns its own helper: `OneRepMax.estimate` is the only
/// figure in this app that is compared against another app's screen. Brzycki
/// puts 24 kg × 9 at 30.857…, which is `30.9` at one decimal and `30.86`
/// everywhere the athlete can check it.
@inlinable
public func jsRound2(_ x: Double) -> Double {
    jsRound(x * 100) / 100
}
