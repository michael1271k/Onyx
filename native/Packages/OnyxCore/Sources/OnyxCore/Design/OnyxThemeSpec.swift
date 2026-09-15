import Foundation

/// A theme is two hues: the train accent and the fuel accent. Everything else
/// the app colours is derived from those two by `OnyxTheme` in OnyxUI, which
/// keeps each other stop at its measured offset from the one it follows.
///
/// Two `UInt32`s rather than two `Color`s so the value is Codable, comparable
/// and readable from OnyxCore, where no view framework is allowed.
public struct OnyxThemeSpec: Codable, Equatable, Sendable {
    /// The train accent — Ion, `0x6B78F0`, by default.
    public var primary: UInt32
    /// The fuel accent — Solar, `0xE3A650`, by default.
    public var secondary: UInt32

    public init(primary: UInt32, secondary: UInt32) {
        self.primary = primary
        self.secondary = secondary
    }

    public static let `default` = OnyxThemeSpec(primary: 0x6B78F0, secondary: 0xE3A650)

    /// The contrast guard.
    ///
    /// L ≥ 0.60 keeps an accent at ≥ 4.5:1 as foreground on black (the muscle
    /// palette's own floor is 4.99:1, at Calves); L ≤ 0.78 keeps white text
    /// legible on a ramp button; C ≤ 0.20 keeps a chosen hue in the same
    /// register as the sixteen data colours rather than shouting over them.
    /// A hue already inside the box passes through with its bits untouched.
    public func normalised() -> OnyxThemeSpec {
        OnyxThemeSpec(primary: Self.clamp(primary), secondary: Self.clamp(secondary))
    }

    static let lightness = 0.60...0.78
    static let maxChroma = 0.20

    static func clamp(_ hex: UInt32) -> UInt32 {
        var colour = OKLCHConvert.oklch(fromHex: hex)
        guard !lightness.contains(colour.l) || colour.c > maxChroma else { return hex }
        colour.l = min(max(colour.l, lightness.lowerBound), lightness.upperBound)
        colour.c = min(colour.c, maxChroma)
        return OKLCHConvert.hex(from: colour)
    }
}
