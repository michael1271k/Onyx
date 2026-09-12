import Foundation

/// Time-based movements record a HOLD in seconds, not reps. Matched by name —
/// a port of the web app's `lib/exercises/timed.ts`, regex for regex.
public enum TimedExercise {
    private static let pattern = try! NSRegularExpression(
        pattern: #"\b(plank|hollow\s*hold|hold|dead\s*hang|wall\s*sit|l-?sit|carry)\b"#,
        options: .caseInsensitive
    )

    public static func isTimed(_ name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        return pattern.firstMatch(in: name, range: NSRange(location: 0, length: (name as NSString).length)) != nil
    }
}

// MARK: - Name matching, shared by the sibling predicates

/// The catalogue is a NAME TABLE — no equipment column, no laterality column,
/// no timed flag — so `isTimed`, `Bodyweight.isBodyweight` and
/// `Unilateral.isUnilateral` all answer by matching the name against a list of
/// regexes. This is that match, in one place, so the three siblings cannot
/// drift on case-sensitivity or on what "any of them" means.
///
/// The patterns stay `String` rather than pre-compiled `NSRegularExpression`
/// values because a `[String]` is `Sendable` by construction and the lists are
/// a dozen entries matched a handful of times per render. If a profiler ever
/// says otherwise, pre-compile them — nothing else has to change.
extension String {
    func matchesAnyPattern(_ patterns: [String]) -> Bool {
        patterns.contains { range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }
}
