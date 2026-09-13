import Foundation

/// Movements whose record is a REP COUNT, because there is no load to progress
/// — a port of the web app's `lib/exercises/bodyweight.ts`.
///
/// Sibling of `TimedExercise`, and matched the same way: by NAME, because the
/// exercise catalogue has no equipment column and the deck's `wk1Kg: nil`
/// carries two different meanings (Hack Squat is nil because nobody has
/// recorded a start load, not because it is bodyweight).
///
/// ── WHAT THIS IS FOR ────────────────────────────────────────────────────────
/// Not formatting: a zero-load set already renders as "15 reps" rather than
/// "0kg × 15", and that test is the weight itself. This flag answers the other
/// half — whether to show a load CONTROL at all. The deck was offering a
/// Hanging Knee Raise a weight field, a 0–60 kg slider and four ±kg chips, none
/// of which mean anything for that movement, and the summary line dutifully
/// read "0kg × 15 reps" because a control existed to feed it.
///
/// Timed holds are NOT in this list. They are unloaded too, but `reps` carries
/// SECONDS for them and `TimedExercise` owns that distinction; `isUnloaded` is
/// the union for a caller that needs both.
public enum Bodyweight {

    /// Reps-only movements, anchored where a loaded machine variant shares the
    /// word: `Reverse Crunch` and `Crunch` are bodyweight, `Crunch Machine`
    /// carries a stack, so the pattern requires the name to END at the
    /// movement.
    static let bodyweightPatterns: [String] = [
        #"\b(hanging\s+)?(knee|leg)\s+raises?$"#,
        #"\breverse\s+crunch(es)?$"#,
        #"^crunch(es)?$"#,
        // `[-\s]?` because the catalogue spells these three ways — "Push-Up",
        // "Push Up", "Pushups" — and a name typed in the logger uses whichever.
        #"\bsit[-\s]?ups?$"#,
        #"\bpush[-\s]?ups?$"#,
        #"\b(pull|chin)[-\s]?ups?$"#,
        #"\bdips?$"#,
        #"\bback\s+extensions?$"#,
        #"\bglute\s+bridges?$"#,
        #"\bmountain\s+climbers?$"#,
        #"\bbicycle\s+crunch(es)?$"#,
        #"\bflutter\s+kicks?$"#,
        #"\bair\s+squats?$"#,
    ]

    /// A machine / cable / smith qualifier means a stack is attached whatever
    /// the root movement is called ("Assisted Pull-Up (Machine)", "Crunch
    /// Machine").
    ///
    /// `assisted` is in the list on its own: on an assisted dip or pull-up the
    /// assistance stack IS the load, and it is the number that progresses
    /// (downwards). Free-typed as "Assisted Dip", with no machine qualifier, it
    /// would otherwise land in the bodyweight set and lose its weight field.
    static let loadedQualifier = #"\b(machine|cable|smith|barbell|dumbbell|db|plate|assisted)\b"#

    /// The subset of bodyweight movements that take EXTERNAL LOAD.
    ///
    /// ── WHY THE SET IS NOT "ALL OF THEM" ────────────────────────────────────
    /// The deck offered a full-width "+ Add load" button on every bodyweight
    /// set, which put it on Reverse Crunch, Hanging Knee Raise and the rest of
    /// the floor work — movements with no loaded variant to reach. It was the
    /// largest control in the tuner, on the exercises with the least to
    /// configure, and every tap led to a weight field nobody was going to fill.
    ///
    /// These four have a real weighted form: a dip belt, a plate on the back, a
    /// vest, a plate held at the chest. Everything else in
    /// `bodyweightPatterns` is reps and nothing else — and where a loaded
    /// variant does exist it is a DIFFERENT catalogue entry carrying its own
    /// qualifier ("Barbell Glute Bridge", "Crunch Machine"), which
    /// `isBodyweight` has already excluded before this is asked.
    ///
    /// A timed hold is never loadable whatever its name: `reps` carries SECONDS
    /// on those and session tonnage has no timed concept, so one tap plus a
    /// 60 s plank would inject phantom kilograms into the week.
    static let loadablePatterns: [String] = [
        #"\b(pull|chin)[-\s]?ups?$"#,
        #"\bdips?$"#,
        #"\bpush[-\s]?ups?$"#,
        #"\bback\s+extensions?$"#,
    ]

    /// True when the movement carries no external load by default — reps are
    /// the record.
    public static func isBodyweight(_ exerciseName: String?) -> Bool {
        guard let name = exerciseName, !name.isEmpty else { return false }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.matchesAnyPattern([loadedQualifier]) { return false }
        return n.matchesAnyPattern(bodyweightPatterns)
    }

    /// True when the movement is bodyweight AND has a genuine weighted variant
    /// — `isLoadableBodyweightExercise` in the TypeScript.
    public static func isLoadable(_ exerciseName: String?) -> Bool {
        guard isBodyweight(exerciseName), let name = exerciseName else { return false }
        return name.trimmingCharacters(in: .whitespacesAndNewlines).matchesAnyPattern(loadablePatterns)
    }

    /// True when the movement has no load to show, for EITHER reason — a
    /// rep-only bodyweight movement or a timed hold. What the deck actually
    /// asks before it renders a weight column.
    ///
    /// `isTimed` deliberately sees the RAW name and `isBodyweight` the trimmed
    /// one, exactly as the TypeScript does.
    public static func isUnloaded(_ exerciseName: String?) -> Bool {
        TimedExercise.isTimed(exerciseName) || isBodyweight(exerciseName)
    }
}
