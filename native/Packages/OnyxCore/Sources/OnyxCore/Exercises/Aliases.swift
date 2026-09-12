import Foundation

/// Exercise alias map — a port of the web app's `lib/exercises/aliases.ts`.
///
/// Historical and variant names → canonical catalogue names. Keys are
/// lower-case + trimmed. Every entry is a rename or a merge that was performed
/// deliberately; the web module's header explains why a *speculative* alias is
/// now a data-loss bug rather than a display bug (the archive that made a wrong
/// alias reversible is gone). Add a key only for a rename or merge you are
/// performing on purpose — and add it on BOTH sides, because the golden vector
/// `exercise-aliases.json` requires this table to equal the TypeScript one.
///
/// The PR ledger (`personal_records.exercise_key`) is keyed on the canonical
/// name, so a port that does not resolve `Cable Lateral Raise` to `Single Arm
/// Lateral Raise (Cable)` files that lift's records under two keys.
public enum ExerciseAliases {
    public static let table: [String: String] = [
        // Hevy has no neutral-grip lat pulldown — close grip is the stand-in.
        "lat pulldown - close grip (cable)": "Neutral-Grip Lat Pulldown",
        "lat pulldown close grip (cable)": "Neutral-Grip Lat Pulldown",
        "close grip lat pulldown (cable)": "Neutral-Grip Lat Pulldown",
        // Renamed 2026-08-01.
        "hack/smith squat": "Hack Squat",
        "smith squat": "Hack Squat",
        // One machine, one row (merged 2026-08-01).
        "chest press machine": "Chest Press",
        "machine chest press": "Chest Press",
        "leg press horizontal": "Leg Press",
        "leg press horizontal (machine)": "Leg Press",
        // Seated Cable Row is the one exception — the grips are different
        // lifts on different days, so the aliases RESOLVE the variant rather
        // than erase it (2026-08-06).
        "seated cable row (v grip)": "Seated Cable Row (V-Grip)",
        "seated cable row v-grip": "Seated Cable Row (V-Grip)",
        "seated cable row - v-bar": "Seated Cable Row (V-Grip)",
        "seated cable row - bar wide grip": "Seated Cable Row (Wide Grip)",
        "seated cable row (wide bar)": "Seated Cable Row (Wide Grip)",
        "wide-grip cable row": "Seated Cable Row (Wide Grip)",
        // Same station, two names (merged 2026-08-02).
        "cable lateral raise": "Single Arm Lateral Raise",
        "single arm cable lateral raise": "Single Arm Lateral Raise",
        "sa lateral raise (cable)": "Single Arm Lateral Raise",
        "sa lateral raise": "Single Arm Lateral Raise",
        // Empty duplicate, deleted 2026-08-03.
        "incline db bench press": "Incline DB Press",
        "incline dumbbell bench press": "Incline DB Press",
        "incline dumbbell press": "Incline DB Press",
              // ── THE 2026-09-07 MERGE-AND-STRIP ──────────────────────────────────────────
              // Fifteen catalogue rows were merged and thirteen titles lost their equipment
              // to the new `exercises.equipment` column, so the kit is a TAG and the name is
              // the movement. Every absorbed and every pre-rename name is keyed here for the
              // usual reason `merge-exercise.mjs` prints on every run: without it the next
              // draft recreates the row that was just deleted, under a name whose PR
              // baseline has never seen a rep.
              //
              // Two of the merges were not cosmetic. `DB Hammer Curl` (20 sets, from 21 Jul)
              // and `Hammer Curl (DB)` (76 sets, to 19 Jun) were the same movement either
              // side of a July rename, and so were the two shoulder presses — so the first
              // set logged under each new name in July was graded against a baseline that
              // had never seen one. Same failure the machine merges above document.
              //
              // `Crunch Machine` is NOT renamed to `Crunch`: that matches
              // `BodyweightExercise.patterns`' `^crunch(es)?$` and would hide the load
              // column on a 57.5 kg machine. See docs/sql/hotfix-polish.sql.
        "pec deck (butterfly)": "Pec Deck",
        "butterfly pec deck": "Pec Deck",
        "lat pulldown (cable)": "Lat Pulldown",
        "straight arm pulldown (rope)": "Straight-Arm Pulldown",
        "straight arm pulldown": "Straight-Arm Pulldown",
        "cable overhead extension": "Overhead Triceps Extension",
        "overhead triceps extension (cable)": "Overhead Triceps Extension",
        "triceps rope pushdown": "Rope Triceps Pushdown",
        "calf press (machine)": "Calf Press",
        "calf press machine": "Calf Press",
        "leg extension (machine)": "Leg Extension",
        "leg extension machine": "Leg Extension",
        "seated leg curl (machine)": "Seated Leg Curl",
        "seated leg curl machine": "Seated Leg Curl",
        "crunch (machine)": "Crunch Machine",
        "db hammer curl": "Hammer Curl",
        "hammer curl (db)": "Hammer Curl",
        "db shoulder press": "Shoulder Press",
        "shoulder press (db)": "Shoulder Press",
        "hip adduction (machine)": "Hip Adduction",
        "machine hip thrust": "Hip Thrust",
        "hip thrust (machine)": "Hip Thrust",
        "machine preacher curl": "Preacher Curl",
        "preacher curl (machine)": "Preacher Curl",
        "db rdl": "Romanian Deadlift",
        "rdl db": "Romanian Deadlift",
        "romanian deadlift (db)": "Romanian Deadlift",
        "romanian deadlift (dumbbell)": "Romanian Deadlift",
        "chest press (machine)": "Chest Press",
        "bicep curl (db)": "Bicep Curl",
        "bicep curl db": "Bicep Curl",
        "seated lateral raise (db)": "Seated Lateral Raise",
        "lateral raise db": "Seated Lateral Raise",
        "machine lateral raise": "Lateral Raise",
        "single arm lateral raise (cable)": "Single Arm Lateral Raise",
        "single arm triceps pushdown (cable)": "Single Arm Triceps Pushdown",
    ]

    /// Lower-case + trim, look up, else hand the RAW name back unchanged —
    /// case and padding included. `canonicalExerciseName` in the TypeScript.
    public static func canonicalName(_ raw: String) -> String {
        table[raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)] ?? raw
    }
}
