import Foundation

/// One SF Symbol per movement PATTERN (overhaul C1, decision Q13).
///
/// The symbol names what the body does — a press, a hinge, a row, a bout on a
/// treadmill — not the kit it is done on, which `ExerciseIcon.label` already
/// says in words. Resolution is by name first (the catalogue is a name table,
/// the same reason `Flags.swift` is regexes) and by the movement's first
/// primary mover second, so a movement nobody wrote a rule for still lands on
/// its pattern when `MuscleMap` knows it.
///
/// ORDER IS PART OF THE DATA: `Leg Press` and `Calf Press` are legs before they
/// are presses, `Seated Leg Curl` is a hinge before it is a curl, and a
/// `Hanging Knee Raise` is core before it is a raise.
///
/// The symbol strings are plain data here (OnyxCore is Foundation-only);
/// `OnyxTests` checks that every one exists in the SF Symbols the app ships.
public enum ExerciseGlyph {

    public enum Pattern: String, CaseIterable, Sendable {
        case treadmill, walk, run, stairs, elliptical, cycle, rowErg, intervals
        case stretch, hold, core
        case calf, squat, hinge
        case fly, verticalPull, horizontalPull, press, arms

        public var symbol: String {
            switch self {
            case .treadmill:      "figure.walk.treadmill"
            case .walk:           "figure.walk"
            case .run:            "figure.run"
            case .stairs:         "figure.stair.stepper"
            case .elliptical:     "figure.elliptical"
            case .cycle:          "figure.indoor.cycle"
            case .rowErg:         "figure.rower"
            case .intervals:      "figure.highintensity.intervaltraining"
            case .stretch:        "figure.flexibility"
            case .hold:           "figure.pilates"
            case .core:           "figure.core.training"
            case .calf:           "figure.step.training"
            case .squat:          "figure.strengthtraining.functional"
            case .hinge:          "figure.cross.training"
            case .fly:            "figure.arms.open"
            case .verticalPull:   "figure.climbing"
            // A cable row is the rowing motion; it shares the ergometer's figure.
            case .horizontalPull: "figure.rower"
            case .press:          "figure.strengthtraining.traditional"
            case .arms:           "dumbbell"
            }
        }
    }

    /// The one answer for a movement no rule and no mover places: a plain
    /// standing figure — "a movement", claiming no pattern.
    public static let fallback = "figure"

    /// Name rules, most specific first. Lowercased input, word-bounded.
    static let rules: [(String, Pattern)] = [
        (#"\btreadmill\b"#, .treadmill),
        (#"\b(stair|stepper)"#, .stairs),
        (#"\belliptical\b"#, .elliptical),
        (#"\b(cycl\w*|bike|spin)\b"#, .cycle),
        (#"\b(rowing|rower|erg)\b"#, .rowErg),
        (#"\b(hiit|intervals?)\b"#, .intervals),
        (#"\b(run|running|jog|jogging|sprints?)\b"#, .run),
        (#"\b(walk|walking|hike|hiking)\b"#, .walk),
        (#"\b(stretch\w*|mobility|yoga)\b"#, .stretch),
        (#"\b(plank|dead\s*hang|wall\s*sit|l-?sit|hold)\b"#, .hold),
        (#"\b(crunch\w*|sit-?ups?|twist|hollow|(knee|leg)\s+raises?|ab\s+wheel|rollouts?)\b"#, .core),
        (#"\bcalf\b|\bcalves\b"#, .calf),
        (#"\b(squat|leg\s+press|leg\s+extension|lunges?|step-?ups?|adduction|abduction)\b"#, .squat),
        (#"\b(deadlift|rdl|hip\s+thrust|leg\s+curl|good\s+morning|back\s+extension|glute\s+bridge)\b"#, .hinge),
        (#"\b(fly|flye|flyes|flies|pec\s+deck|crossover|butterfly|lateral\s+raise|rear\s+delt)\b"#, .fly),
        (#"\b(pulldown|pull-?ups?|chin-?ups?)\b"#, .verticalPull),
        (#"\b(row|face\s+pull|pull-?over)\b"#, .horizontalPull),
        (#"\b(press|push-?ups?|dips?)\b"#, .press),
        (#"\b(curl|pushdown|triceps|extension|skull\s*crusher|kickback)\b"#, .arms),
    ]

    /// The pattern a movement is FOR, or nil when neither a rule nor its
    /// primary mover places it.
    public static func pattern(for name: String) -> Pattern? {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return nil }
        if let hit = rules.first(where: { matches($0.0, lower, caseInsensitive: false) }) { return hit.1 }
        switch MuscleMap.primaryLandmarks(name).first {
        case .chest?, .frontDelts?, .sideDelts?: return .press
        case .lats?: return .verticalPull
        case .upperBack?, .rearDelts?: return .horizontalPull
        case .biceps?, .triceps?, .forearms?: return .arms
        case .quads?, .adductors?: return .squat
        case .hamstrings?, .glutes?, .lowerBack?: return .hinge
        case .calves?: return .calf
        case .absCore?: return .core
        case nil: return nil
        }
    }

    /// The SF Symbol to draw beside the movement's name. Never empty.
    public static func symbol(for name: String) -> String {
        pattern(for: name)?.symbol ?? fallback
    }
}
