import Foundation
import Testing
@testable import OnyxCore

/// The colour-space arithmetic under the runtime theme.
///
/// The one property everything else leans on is the SECOND test: a zero
/// rotation must return the same bits, not a colour one step away. That is
/// what makes the default theme reproduce today's palette exactly rather than
/// "to within a rounding error" — which, over 1243 call sites, is a different
/// app.
@Suite("OKLCH")
struct OKLCHTests {

    /// The 24 default hexes — 8 domain stops and 16 muscles — copied here on
    /// purpose. OnyxCore cannot see OnyxTokens, and a test that reads its
    /// expectations from the code under test is not a test.
    static let defaults: [UInt32] = [
        // train, fuel, body, recover — start then end
        0x6B78F0, 0x4FB6E8, 0xE3A650, 0xE07A7A, 0x46B39D, 0x2E9AA6, 0xA79FD6, 0xC9D3EE,
        // the sixteen landmarks in declaration order
        0xF66D64, 0x00D4CE, 0x00B6B0, 0x009894, 0xFF9F46, 0xE68100, 0xC26C00, 0x998BFF,
        0x0EA6FF, 0xB49F00, 0x8AE171, 0x76CC5C, 0x61B647, 0x4DA230, 0x388D15, 0xE66DB6,
    ]

    private func channels(_ hex: UInt32) -> [Int] {
        [Int((hex >> 16) & 0xFF), Int((hex >> 8) & 0xFF), Int(hex & 0xFF)]
    }

    @Test("hex → OKLCH → hex round-trips bit-exact for every default hex")
    func roundTrip() {
        for hex in Self.defaults {
            let back = OKLCHConvert.hex(from: OKLCHConvert.oklch(fromHex: hex))
            #expect(back == hex, "\(String(hex, radix: 16)) → \(String(back, radix: 16))")
        }
    }

    @Test("a zero rotation is the identity, bit for bit")
    func zeroRotationIsIdentity() {
        for hex in Self.defaults {
            #expect(OKLCHConvert.rotate(hex, byDegrees: 0) == hex)
            // Δ is a DIFFERENCE of two hue reads in the theme; the guard has to
            // swallow the noise a subtraction of equal doubles could leave.
            #expect(OKLCHConvert.rotate(hex, byDegrees: 1e-12) == hex)
            #expect(OKLCHConvert.rotate(hex, byDegrees: -1e-12) == hex)
        }
    }

    @Test("a full turn lands on the same bits")
    func fullTurn() {
        for hex in Self.defaults {
            let back = OKLCHConvert.rotate(hex, byDegrees: 360)
            #expect(back == hex, "\(String(hex, radix: 16)) → \(String(back, radix: 16))")
        }
    }

    @Test("rotation moves hue only — L and C survive within 1e-3")
    func rotationKeepsLightnessAndChroma() {
        let before = OKLCHConvert.oklch(fromHex: 0x6B78F0)
        let after = OKLCHConvert.oklch(fromHex: OKLCHConvert.rotate(0x6B78F0, byDegrees: 90))
        #expect(abs(before.l - after.l) < 1e-3)
        #expect(abs(before.c - after.c) < 1e-3)
        var dh = (after.h - before.h - 90).truncatingRemainder(dividingBy: 360)
        if dh > 180 { dh -= 360 }
        if dh < -180 { dh += 360 }
        #expect(abs(dh) < 1)
    }

    @Test("a rotation that leaves the gamut is fitted, not trapped")
    func gamutFit() {
        // Pure red at 90° is a chroma no sRGB green can carry.
        let red = OKLCHConvert.oklch(fromHex: 0xFF0000)
        var turned = red
        turned.h = OKLCHConvert.wrap(red.h + 90)
        let before = OKLCHConvert.linear(l: turned.l, c: turned.c, h: turned.h)
        #expect(!OKLCHConvert.inGamut(before), "the unfitted colour must actually be out of gamut")

        let fittedColour = OKLCHConvert.fit(turned)
        let after = OKLCHConvert.linear(l: fittedColour.l, c: fittedColour.c, h: fittedColour.h)
        for channel in [after.r, after.g, after.b] {
            #expect(channel >= -1e-6 && channel <= 1 + 1e-6)
        }
        #expect(fittedColour.c < red.c)
        #expect(fittedColour.l == red.l && fittedColour.h == turned.h)

        let fitted = OKLCHConvert.rotate(0xFF0000, byDegrees: 90)
        let got = OKLCHConvert.oklch(fromHex: fitted)
        // L and h are what the fit was told to keep, through quantisation.
        #expect(abs(got.l - red.l) < 0.02)
        var dh = (got.h - red.h - 90).truncatingRemainder(dividingBy: 360)
        if dh > 180 { dh -= 360 }
        if dh < -180 { dh += 360 }
        #expect(abs(dh) < 3)
    }

    @Test("hue reads in degrees on [0, 360)")
    func hueRange() {
        for hex in Self.defaults {
            let h = OKLCHConvert.hue(ofHex: hex)
            #expect(h >= 0 && h < 360)
        }
        #expect(OKLCHConvert.hue(ofHex: 0x6B78F0) == OKLCHConvert.oklch(fromHex: 0x6B78F0).h)
    }
}

@Suite("OnyxThemeSpec")
struct OnyxThemeSpecTests {

    @Test("an in-range spec normalises to itself, bit-exact")
    func inRangePassesThrough() {
        #expect(OnyxThemeSpec.default.normalised() == .default)
    }

    @Test("a very dark primary is lifted to the contrast floor and keeps its hue")
    func darkPrimaryIsLifted() {
        let spec = OnyxThemeSpec(primary: 0x101020, secondary: 0xE3A650).normalised()
        let got = OKLCHConvert.oklch(fromHex: spec.primary)
        // 8-bit quantisation can shave a thousandth off the clamp.
        #expect(got.l >= 0.60 - 1e-3)
        var dh = (got.h - OKLCHConvert.hue(ofHex: 0x101020)).truncatingRemainder(dividingBy: 360)
        if dh > 180 { dh -= 360 }
        if dh < -180 { dh += 360 }
        #expect(abs(dh) < 1)
        // The untouched half is untouched.
        #expect(spec.secondary == 0xE3A650)
    }

    @Test("a very saturated primary is pulled back to the chroma ceiling")
    func saturatedPrimaryIsPulledBack() {
        let spec = OnyxThemeSpec(primary: 0xFF0000, secondary: 0xE3A650).normalised()
        #expect(OKLCHConvert.oklch(fromHex: spec.primary).c <= 0.20 + 1e-3)
    }

    @Test("a very light secondary comes down to the ceiling")
    func lightSecondaryIsLowered() {
        let spec = OnyxThemeSpec(primary: 0x6B78F0, secondary: 0xFFF7E0).normalised()
        #expect(OKLCHConvert.oklch(fromHex: spec.secondary).l <= 0.78 + 1e-3)
    }

    @Test("the spec round-trips through JSON as two integers")
    func json() throws {
        let data = try JSONEncoder().encode(OnyxThemeSpec.default)
        #expect(try JSONDecoder().decode(OnyxThemeSpec.self, from: data) == .default)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"primary\""))
        #expect(text.contains("\"secondary\""))
    }
}
