import Foundation

/// Why a day carries no weigh-in — a port of the web app's `lib/body/weighIn.ts`.
///
/// THE DEFAULT IS "As Planned", NOT "no reason recorded". The protocol is to skip
/// the scale on any morning the bathroom has not happened yet, so skipping is the
/// normal case; absence of a stated reason means the routine was followed.
public enum WeighIn {
    public static let defaultSkipReason = "As Planned"
    /// The offered reasons, in rough order of frequency.
    public static let skipReasons = [defaultSkipReason, "No BM", "Travel", "Forgot", "Fasted", "Sick"]

    /// The reason to DISPLAY for a weightless day: what was stored (trimmed), or the default.
    public static func skipReason(_ stored: String?) -> String {
        let t = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? defaultSkipReason : t
    }

    public static func isDefaultSkipReason(_ stored: String?) -> Bool {
        skipReason(stored) == defaultSkipReason
    }
}
