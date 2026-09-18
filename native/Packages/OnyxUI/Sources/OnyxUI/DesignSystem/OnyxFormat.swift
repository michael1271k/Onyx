import Foundation

/// The number formats this app repeats, in one place.
///
/// ── WHY IT LIVES IN THE DESIGN SYSTEM AND NOT BESIDE THE LOGGER (W10) ───────
/// It was `enum OnyxFormat` at the bottom of `LoggerModel.swift`, described as
/// "the two number formats this screen repeats" — which stopped being true
/// around the fourth caller and was false in thirty files by the time anything
/// noticed. Every one of these is a DISPLAY rule (grouping, decimal places,
/// when a tenth is signal and when it is noise); none of them is arithmetic,
/// none is stored, and no domain type depends on one.
///
/// The move is what lets a view in OnyxUI print a number the app's way. The
/// first that needed to is `IntensityBar`, lifted out of `SessionDetailView` so
/// the finish sheet and the session page draw one bar rather than two — and a
/// package view cannot see the app target, so the choice was this move or a
/// second `rpe` formatter inside OnyxUI. A second formatter is how "the next
/// change to how ONYX prints a load silently changes how it prints an effort
/// rating" (`rpe`'s own header) happens across a module boundary instead of
/// inside one file.
///
/// Every call site is unchanged: the app already imports OnyxUI wherever it
/// draws.

public enum OnyxFormat {
    /// `47`, `49.5`, `13.75` — never `49.50`, never `13.8`.
    ///
    /// Loads on cable stacks and micro-plates are genuinely 13.75 kg, and
    /// rounding one to a single decimal in the UI while storing the true value
    /// is how a load you can read stops matching the load you can search for.
    public static func kg(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }

    /// `1 074` — grouped, because a five-digit tonnage is unreadable without it.
    public static func volume(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value < 100 ? 1 : 0
        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }

    /// `13,242.5` — the same grouping, and ALWAYS one decimal.
    ///
    /// ── WHY THIS IS A SIBLING AND NOT A CHANGE TO `volume` ──────────────────
    /// `volume` drops the decimal above 100 and it is right to nearly
    /// everywhere it is called: a per-exercise pill, a chart callout, a week's
    /// total, a delta and a Lock Screen face are all readings where the tenth
    /// of a kilogram is noise competing for width that is genuinely scarce.
    ///
    /// Three surfaces are not readings — they are the CLAIM about one session's
    /// weight, and they are checked against each other and against
    /// `workout_sessions.total_volume_kg`: the finish sheet's Tonnage tile, the
    /// logger's Live Stats face and the summary's Volume cell. A half kilogram
    /// rounded away there makes the app say 13,243 for a session the database
    /// records as 13,242.5, and a figure that does not match the one the sheet
    /// showed thirty seconds earlier is a figure nobody trusts again.
    ///
    /// `minimum` as well as `maximum`, so a whole number prints `9,000.0`
    /// rather than `9,000` — a column of tonnages that gains and loses a
    /// decimal place between sessions is harder to read than one that never
    /// does.
    public static func volumeExact(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }

    /// `8`, `8.5`, `10`. CR-10, and its own function.
    ///
    /// It used to call `kg(_:)`, which produced the right characters for the
    /// wrong reason: an RPE is a point on a ten-point scale in half steps, and a
    /// load is a mass with two decimals of micro-plate precision. Sharing one
    /// formatter means the next change to how ONYX prints a load — grouping,
    /// a third decimal — silently changes how it prints an effort rating.
    public static func rpe(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Weighted set counts print at most one decimal: assistance is credited in
    /// halves, so `1.5` is a real value and `1.50` is noise.
    public static func sets(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
