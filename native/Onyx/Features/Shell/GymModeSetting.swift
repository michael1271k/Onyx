import Foundation

/// The one name the gym-mode switch is stored under (§W6-B, decision 26).
///
/// A type and not a literal in two files: the shell reads it to decide whether
/// to hide the tab bar and the You tab writes it, and a `@AppStorage` key that
/// is spelled twice is a setting that silently stops working the day one of
/// the spellings is edited.
///
/// Default ON, and deliberately: the whole point is that the phone knows when
/// it is in a gym, and a feature that has to be discovered in Settings before
/// it ever happens is a feature nobody has. The switch is for the person who
/// tries it and does not want it.
enum GymModeSetting {
    static let key = "onyx.gymMode.enabled"
}
