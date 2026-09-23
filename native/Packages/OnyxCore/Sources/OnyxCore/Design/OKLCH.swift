import Foundation

/// A colour in OKLCH — perceptual lightness, chroma and a hue in degrees.
///
/// Björn Ottosson's Oklab (2020), in polar form. Rotating `h` at fixed `l` and
/// `c` is what lets a theme swap one accent hue for another without the
/// swapped colour reading lighter, darker or louder than the one it replaced —
/// which HSL rotation, the obvious alternative, cannot promise.
public struct OKLCH: Equatable, Sendable {
    public var l: Double
    public var c: Double
    /// Degrees, [0, 360).
    public var h: Double

    public init(l: Double, c: Double, h: Double) {
        self.l = l
        self.c = c
        self.h = h
    }
}

/// sRGB 8-bit ↔ OKLCH, plus the one operation a theme needs: rotate a hue.
///
/// Pure `Double` arithmetic on `UInt32` hexes so OnyxCore stays Foundation-only
/// and the same numbers reach the app, the widgets and the watch.
public enum OKLCHConvert {

    // MARK: - sRGB 8-bit → OKLCH

    public static func oklch(fromHex hex: UInt32) -> OKLCH {
        let r = toLinear(Double((hex >> 16) & 0xFF) / 255)
        let g = toLinear(Double((hex >> 8) & 0xFF) / 255)
        let b = toLinear(Double(hex & 0xFF) / 255)

        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)

        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

        return OKLCH(l: L, c: (a * a + bb * bb).squareRoot(), h: wrap(atan2(bb, a) * 180 / .pi))
    }

    public static func hue(ofHex hex: UInt32) -> Double {
        oklch(fromHex: hex).h
    }

    // MARK: - OKLCH → sRGB 8-bit

    /// The inverse path with a gamut fit: a chroma sRGB cannot carry comes down
    /// in steps of 0.01 at fixed `l` and `h` until every linear channel is
    /// inside [0, 1], then the result is clamped and quantised.
    public static func hex(from colour: OKLCH) -> UInt32 {
        let fitted = fit(colour)
        let rgb = linear(l: fitted.l, c: fitted.c, h: fitted.h)
        let r = quantise(rgb.r), g = quantise(rgb.g), b = quantise(rgb.b)
        return (r << 16) | (g << 8) | b
    }

    /// The gamut fit on its own: the same colour with its chroma reduced until
    /// sRGB can carry it. Separate from `hex(from:)` so a test can see that the
    /// fit ran, not merely that some bytes came back.
    static func fit(_ colour: OKLCH) -> OKLCH {
        var fitted = colour
        // ponytail: linear C-reduction, ≤30 steps; binary search if a profiler ever sees this
        var steps = 0
        while !inGamut(linear(l: fitted.l, c: fitted.c, h: fitted.h)), steps < 30, fitted.c > 0 {
            fitted.c = max(0, fitted.c - 0.01)
            steps += 1
        }
        return fitted
    }

    /// Rotate a hex's hue by `delta` degrees at fixed L and C.
    ///
    /// A delta of (numerically) zero returns the SAME bits: the default theme's
    /// deltas are differences of equal hue reads, and this guard is what makes
    /// "default theme" mean "today's palette, exactly" rather than "today's
    /// palette after a trip through a cube root and back".
    public static func rotate(_ hex: UInt32, byDegrees delta: Double) -> UInt32 {
        guard abs(delta) >= 1e-9 else { return hex }
        var colour = oklch(fromHex: hex)
        colour.h = wrap(colour.h + delta)
        return self.hex(from: colour)
    }

    /// Scale a hex's chroma and offset its lightness, at fixed HUE.
    ///
    /// The second operation a theme needs, and the mood knob's whole
    /// implementation: `rotate` says WHICH colour, this says how deep and how
    /// loud. Hue is untouched, so a palette moved by this keeps every measured
    /// offset between its stops — the same promise rotation makes.
    ///
    /// A neutral knob (scale 1, offset 0) returns the SAME bits, for exactly
    /// the reason `rotate` short-circuits a zero delta: the default spec must
    /// mean "today's palette" and not "today's palette after a trip through a
    /// cube root and back".
    ///
    /// There is no contrast guard HERE. A colour that carries text goes back
    /// through `OnyxThemeSpec.guarded` afterwards — one guard, in the file that
    /// documents the measurements — and a gradient stop that is allowed to go
    /// dark skips it. Scaling is clamped to ≤ 1 rather than trusted from the
    /// caller: this is the only place a chroma could grow, and it must not.
    public static func mood(_ hex: UInt32, chroma scale: Double, lift: Double) -> UInt32 {
        guard abs(scale - 1) >= 1e-9 || abs(lift) >= 1e-9 else { return hex }
        var colour = oklch(fromHex: hex)
        colour.c *= min(max(scale, 0), 1)
        colour.l = min(max(colour.l + lift, 0), 1)
        return self.hex(from: colour)
    }

    /// Move a hex `weight` of the way toward itself turned by `degrees`, at
    /// FIXED lightness, with its chroma capped at `maxChroma`.
    ///
    /// The nutrition inks' whole derivation (overhaul decision Q19): a theme
    /// moves protein, carbs, fat, calories and micros "a little", not all the
    /// way round the wheel. The step is taken in Oklab — along the CHORD from
    /// the colour to its fully-turned self — and not as `weight × degrees` of
    /// hue rotation, for a measured reason: scaling a hue angle has a seam at
    /// ±180° from the default, where two themes 40° apart on the wheel land
    /// 112° apart after scaling (ΔE 19 at C 0.115, past "still recognisable").
    /// The chord has no seam: ΔE between any two themes is exactly `weight`
    /// times their full-rotation ΔE, so the dampening is linear and bounded.
    ///
    /// Weight 0 under the cap returns the SAME bits, for `rotate`'s reason.
    public static func toward(_ hex: UInt32, turnedBy degrees: Double, weight: Double, maxChroma: Double) -> UInt32 {
        let w = min(max(weight, 0), 1)
        var colour = oklch(fromHex: hex)
        guard abs(w * degrees) >= 1e-9 || colour.c > maxChroma else { return hex }
        let from = colour.h * .pi / 180, to = (colour.h + degrees) * .pi / 180
        let a = colour.c * (cos(from) + (cos(to) - cos(from)) * w)
        let b = colour.c * (sin(from) + (sin(to) - sin(from)) * w)
        colour.c = min((a * a + b * b).squareRoot(), maxChroma)
        colour.h = wrap(atan2(b, a) * 180 / .pi)
        return self.hex(from: colour)
    }

    // MARK: - Pieces

    @inlinable static func wrap(_ degrees: Double) -> Double {
        let h = degrees.truncatingRemainder(dividingBy: 360)
        return h < 0 ? h + 360 : h
    }

    @inlinable static func toLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    @inlinable static func fromLinear(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    static func linear(l L: Double, c: Double, h: Double) -> (r: Double, g: Double, b: Double) {
        let rad = h * .pi / 180
        let a = c * cos(rad), b = c * sin(rad)

        let l3 = L + 0.3963377774 * a + 0.2158037573 * b
        let m3 = L - 0.1055613458 * a - 0.0638541728 * b
        let s3 = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l3 * l3 * l3, m = m3 * m3 * m3, s = s3 * s3 * s3

        return (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    /// A hair of slack so a colour that is IN gamut does not lose a chroma
    /// step to the round-trip's own floating-point dust.
    static func inGamut(_ rgb: (r: Double, g: Double, b: Double)) -> Bool {
        let lo = -1e-6, hi = 1 + 1e-6
        return rgb.r >= lo && rgb.r <= hi && rgb.g >= lo && rgb.g <= hi && rgb.b >= lo && rgb.b <= hi
    }

    static func quantise(_ linear: Double) -> UInt32 {
        UInt32((fromLinear(min(max(linear, 0), 1)) * 255).rounded())
    }
}
