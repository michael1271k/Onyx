import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// What a movement IS, as a short row of chips. A port of
// the web app's `lib/exercises/tags.ts`; vector `exercise-tags.json`.
//
// The five facts already exist — `is_compound`, `ExerciseIcon.label`,
// `UnilateralExercise`, `BodyweightExercise`, `TimedExercise` — and every
// surface that wanted them assembled its own list, in its own order, with its
// own idea of which ones cancel out. Two of them do: the equipment rules can
// answer "Bodyweight" and "Timed hold", which are the same claims the last two
// tags make, so a naive concatenation prints `Bodyweight · Bodyweight` on a
// push-up and `Timed hold · Timed` on a plank. That collision is the reason
// this is a function.
//
// THE ORDER IS GENERAL → SPECIFIC AND FIXED: load class, equipment, then the
// three qualifiers. A chip row that reorders itself per exercise is a chip row
// nobody can scan down a deck.
//
// COMPOUND IS AN INPUT, NOT A GUESS. `exercises.is_compound` is a real column
// and `ProgramExercise.isCompound` is a real field; nothing about "Chest Press
// (Machine)" says which it is. A caller that knows passes it; one that does not
// gets no load-class chip. Inventing one from the name is how "Face Pull" ends
// up labelled a compound for having two words in it.
// ─────────────────────────────────────────────────────────────────────────────

public struct ExerciseTag: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case load, equipment, laterality, unloaded, timed
    }

    /// Stable identity for a chip. Lowercase, never localised.
    public var key: String
    /// What the chip says.
    public var label: String
    public var kind: Kind
}

public enum ExerciseTags {

    /// The equipment labels that are the same claim as a qualifier below.
    static let equipmentAliases: [String: ExerciseTag.Kind] = [
        "Bodyweight": .unloaded,
        "Timed hold": .timed,
    ]

    /// Label → chip key. Keys are stable across a rename of the label.
    static let equipmentKeys: [String: String] = [
        "Treadmill": "treadmill",
        "Timed hold": "timed",
        "Loaded carry": "carry",
        "Hanging": "hanging",
        "Cable": "cable",
        "Dumbbell": "dumbbell",
        "Barbell": "barbell",
        "Machine": "machine",
        "Bodyweight": "bodyweight",
    ]

    /// - Parameter compound: `exercises.is_compound`. Nil means the caller does
    ///   not know, and no load-class chip is produced — never a guess.
    public static func tags(for name: String?, compound: Bool? = nil) -> [ExerciseTag] {
        var out: [ExerciseTag] = []

        if compound == true {
            out.append(ExerciseTag(key: "compound", label: "Compound", kind: .load))
        } else if compound == false {
            out.append(ExerciseTag(key: "isolation", label: "Isolation", kind: .load))
        }

        let bodyweight = BodyweightExercise.isBodyweight(name)
        let timed = TimedExercise.isTimed(name)

        let equipment = ExerciseIcon.label(for: name)
        // The fallback is not a claim, so it is not a chip: "Exercise" beside a
        // lift is a row of one word saying nothing.
        if equipment != ExerciseIcon.fallback {
            let aliased = equipmentAliases[equipment]
            // ...and an equipment label that IS one of the qualifiers below is
            // dropped here rather than deduped after, so the qualifier keeps its
            // own place in the fixed order instead of being pulled forward.
            let collides = (aliased == .unloaded && bodyweight) || (aliased == .timed && timed)
            if !collides {
                out.append(ExerciseTag(
                    key: equipmentKeys[equipment] ?? equipment.lowercased(),
                    label: equipment,
                    kind: .equipment
                ))
            }
        }

        if UnilateralExercise.isUnilateral(name) {
            out.append(ExerciseTag(key: "unilateral", label: "Per side", kind: .laterality))
        }
        if bodyweight { out.append(ExerciseTag(key: "bodyweight", label: "Bodyweight", kind: .unloaded)) }
        if timed { out.append(ExerciseTag(key: "timed", label: "Timed", kind: .timed)) }

        return out
    }

    /// Just the labels, in order — the export's form.
    public static func labels(for name: String?, compound: Bool? = nil) -> [String] {
        tags(for: name, compound: compound).map(\.label)
    }
}
