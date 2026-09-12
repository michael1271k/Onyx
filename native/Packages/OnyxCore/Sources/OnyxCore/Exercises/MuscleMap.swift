import Foundation

/// The authoritative primary + secondary muscle tags per exercise — a port of
/// the web app's `lib/exercises/muscleMap.ts`.
///
/// This is the source of truth for the Freshness Map, Muscle Analytics, the
/// weekly MEV/MAV accumulator, the per-muscle tonnage breakdown and the
/// markdown export. A `routines` row resolves its movers through it too, so
/// the deck and the analytics cannot disagree about anatomy.
///
/// ── PRIMARY vs SECONDARY IS A DISTINCTION, NOT A RANKING ────────────────────
/// A primary mover is the muscle the movement is CHOSEN to train. A secondary
/// genuinely contributes force, but under a shorter range, a worse leverage or
/// a lighter relative load. Both earn credit — `MuscleCredit.secondarySetCredit`
/// in `Training/Landmarks.swift` says how much, and why it is not 100%.
///
/// ── EVERY LINE HERE WAS BOUGHT, SO DO NOT TIDY IT ───────────────────────────
/// The table looks like it could be derived from anatomy. It cannot. Each of
/// the surprising entries was settled by reconciling a real training week
/// against Hevy's own per-muscle breakdown, and the comments below are the
/// record of what that cost: the fly that is not a triceps movement *and not a
/// front-delt movement*, the row that is not rear-delt work, the press that
/// pays the triceps and not the side delt. A merge of two entries is a loud
/// bug; a SPLIT is a silent one — `Seated Cable Row` is deliberately two
/// entries by grip and must never be re-merged (see `exercise-catalog-merges`).
///
/// ── THIS MODULE DOES NOT CANONICALISE, AND THAT IS DELIBERATE ───────────────
/// It matches the name it is handed, exactly as the TypeScript does.
/// `ExerciseAliases.canonicalName` runs at the BOUNDARY — where a session is
/// resolved, saved, or the catalogue is read — so by the time a name reaches
/// this table it is already a name the app chose. Folding the alias lookup in
/// here would make the two implementations disagree on the very first vector.
public enum MuscleMap {

    /// One dictionary line: a canonical keyword phrase and what it trains.
    ///
    /// ALL tokens must appear in the name, in any order, and the longest
    /// matching phrase wins.
    public struct Entry: Sendable, Equatable, Codable {
        public let tokens: [String]
        public let muscles: MoverTokens

        init(_ tokens: [String], primary: [String], secondary: [String] = []) {
            self.tokens = tokens
            self.muscles = MoverTokens(primary: primary, secondary: secondary)
        }
    }

    /// ORDER IS PART OF THE DATA. `movers(_:)` only replaces its best match on a
    /// STRICTLY longer token list, so of two entries with the same specificity
    /// the FIRST one written wins — `["overhead", "extension"]` beats
    /// `["cable", "extension"]` for "Overhead Triceps Extension" because it sits
    /// above it. The golden vector `muscle-map-dict.json` holds this array to
    /// the TypeScript one entry for entry, in this order.
    public static let dict: [Entry] = [

        // ── Quads ───────────────────────────────────────────────────────────
        // ── THE ADDUCTORS ARE THE HIP THRUST'S, NOT THE LEG PRESS'S ─────────
        // They were briefly the leg press's, on the reasoning that the stance
        // spreads wide enough to load them, and one session's arithmetic
        // agreed — three leg-press sets produced Hevy's Adductors 1.5 exactly.
        // It was a coincidence of set counts. Across a whole week the same
        // rule pays 3.5 against Hevy's 1.5, and a machine leg press fixes the
        // feet: there is no adduction moment to resist.
        Entry(["leg", "press", "horizontal"], primary: ["quadriceps"], secondary: ["glutes", "hamstrings"]),
        Entry(["leg", "press"], primary: ["quadriceps"], secondary: ["glutes", "hamstrings"]),
        Entry(["hack", "squat"], primary: ["quadriceps"], secondary: ["glutes", "hamstrings"]),
        Entry(["leg", "extension"], primary: ["quadriceps"]),

        // ── Posterior chain ─────────────────────────────────────────────────
        // The calf is a secondary on a leg curl through the gastrocnemius,
        // which crosses the knee — a real contributor, not a courtesy tag.
        Entry(["seated", "leg", "curl"], primary: ["hamstrings"], secondary: ["calves"]),
        Entry(["leg", "curl"], primary: ["hamstrings"], secondary: ["calves"]),
        // The RDL's `upper back` was removed once, in error: dropping it only
        // appeared to fix the weekly Upper back total because the straight-arm
        // pulldown was over-counting there by the same 1.5. Two wrongs summing
        // to the right answer is the worst kind of green.
        //
        // `forearms` stays despite not appearing in Hevy's displayed "other
        // muscles" list, because Hevy's own NUMBERS say it is there: the
        // 2026-08-21 session has exactly one grip-loaded movement, this one,
        // and Hevy reported Forearms 1.5 — which is 0.5 × 3 sets of dumbbell
        // RDL and cannot be anything else. The displayed list is abbreviated;
        // the arithmetic is not.
        Entry(["romanian", "deadlift"], primary: ["hamstrings"], secondary: ["glutes", "lower back", "upper back", "lats", "forearms"]),
        Entry(["rdl"], primary: ["hamstrings"], secondary: ["glutes", "lower back", "upper back", "lats", "forearms"]),
        // The adductor credit belongs HERE: 0.5 × 3 sets is Hevy's 1.5 to the
        // decimal. The adductor magnus is a primary hip extensor, doing the
        // same job as the glute in a thrust — exactly what a secondary is for.
        Entry(["hip", "thrust"], primary: ["glutes"], secondary: ["hamstrings", "quadriceps", "adductors"]),
        // Hip adduction was invisible to the accumulator TWICE OVER: no
        // dictionary entry, and the DB tagged the machine variant
        // `inner_thigh`, a token the landmark fold did not know. The Adductors
        // target could never be met because nothing on earth credited it.
        Entry(["hip", "adduction"], primary: ["adductors"]),
        Entry(["adductor"], primary: ["adductors"]),

        // ── Calves ──────────────────────────────────────────────────────────
        Entry(["calf", "press"], primary: ["calves"]),
        Entry(["calf", "raise"], primary: ["calves"]),

        // ── Abs / core ──────────────────────────────────────────────────────
        Entry(["crunch"], primary: ["abdominals"]),
        Entry(["reverse", "crunch"], primary: ["abdominals"]),
        Entry(["bicycle", "crunch"], primary: ["abdominals"], secondary: ["obliques"]),
        Entry(["hanging", "knee", "raise"], primary: ["abdominals"]),
        Entry(["leg", "raise"], primary: ["abdominals"]),
        Entry(["hollow", "rock"], primary: ["abdominals"]),
        Entry(["russian", "twist"], primary: ["obliques"], secondary: ["abdominals"]),
        Entry(["side", "plank"], primary: ["obliques"], secondary: ["abdominals"]),

        // ── Chest ───────────────────────────────────────────────────────────
        Entry(["incline", "bench", "press", "dumbbell"], primary: ["chest"], secondary: ["triceps", "front_delts"]),
        Entry(["incline", "db", "press"], primary: ["chest"], secondary: ["triceps", "front_delts"]),
        Entry(["chest", "press"], primary: ["chest"], secondary: ["triceps", "front_delts"]),
        // ── THE FLAT BENCH, ADDED IN W5 ─────────────────────────────────────
        // The most common barbell lift in the world resolved to NOTHING here
        // until a generic-user test asked it to. This table grew around the
        // founder's own deck, which presses on an incline and on machines and
        // never once wrote the words "Bench Press" — so the gap was invisible
        // for as long as his was the only account.
        //
        // Two tokens, so the four-token incline-dumbbell entry above still
        // wins on specificity for its own spelling, and "Decline Bench Press"
        // lands here rather than nowhere. It cannot move an existing number:
        // no row in the live catalogue is named this, which is exactly why it
        // was missing.
        Entry(["bench", "press"], primary: ["chest"], secondary: ["triceps", "front_delts"]),
        // ── A FLY IS NOT A TRICEPS MOVEMENT ─────────────────────────────────
        // The elbow angle is fixed, so the triceps never shorten under load.
        // Tagging pec deck and crossovers `triceps` — as this file and the DB
        // both once did — credited an isolation movement to a muscle that does
        // no work in it.
        //
        // ── AND IT IS NOT A FRONT-DELT MOVEMENT EITHER ──────────────────────
        // The same argument one joint over, and it took a second pass to see.
        // A fly IS single-joint about the shoulder, so the anterior deltoid
        // genuinely shortens, which is why this secondary survived the pass
        // that removed the triceps. What settled it was a full week rather
        // than one session: Upper A (23 Aug) paid Shoulders 6.5 to Hevy's 5.5,
        // the excess being 0.5 × 2 pec-deck sets; Upper B (20 Aug) paid 6.5 to
        // Hevy's 4.5, of which 1.0 was 0.5 × 2 crossover sets. The same gap on
        // two fly variants in two sessions, at exactly this line's credit, is
        // the line being wrong.
        //
        // The rule is not "does the muscle shorten" but "is it under a load
        // chosen to train it". On a fly the cable is set for the pec, at a
        // length where the anterior delt has no leverage: the delt holds a
        // position, it does not produce the working moment.
        Entry(["pec", "deck"], primary: ["chest"]),
        Entry(["butterfly"], primary: ["chest"]),
        Entry(["cable", "crossover"], primary: ["chest"]),
        Entry(["cable", "fly"], primary: ["chest"]),

        // ── Back ────────────────────────────────────────────────────────────
        Entry(["lat", "pulldown"], primary: ["lats"], secondary: ["upper back", "biceps", "forearms"]),
        Entry(["lat", "pulldown", "neutral"], primary: ["lats"], secondary: ["upper back", "biceps", "forearms"]),
        Entry(["lat", "pulldown", "close"], primary: ["lats"], secondary: ["upper back", "biceps", "forearms"]),
        // ── THE ROW'S REAR DELT WAS A GRIP DISTINCTION THAT DID NOT SURVIVE ─
        // This table used to hold that a wide-grip row trains the rear delt
        // (real horizontal abduction against the cable) while a V-grip row
        // does not (elbows tucked, pure retraction). That mechanic is sound
        // and it is why `Seated Cable Row` is TWO entries and not one — the
        // grips are different movements and must not be re-merged.
        //
        // The CREDIT is what changed, not the split. Upper B (20 Aug) paid
        // Shoulders 6.5 against Hevy's 4.5, and 1.0 of that gap is 0.5 × 2
        // wide-grip row sets landing on the rear delt. The rear delt's
        // contribution to a row is real but it is not what the row is FOR: the
        // load is chosen for the mid-back, and crediting it on every row makes
        // the rear-delt line a function of how much BACK work the week held.
        // Face pulls and reverse flies are where that muscle is trained, and
        // they carry it as a PRIMARY.
        //
        // Both grips keep `traps`, which folds to Upper back — where the row's
        // own primary already dominates it under the max-per-set rule.
        Entry(["cable", "row"], primary: ["upper back"], secondary: ["lats", "traps", "biceps", "forearms"]),
        Entry(["seated", "cable", "row", "wide"], primary: ["upper back"], secondary: ["lats", "traps", "biceps", "forearms"]),
        Entry(["seated", "cable", "row", "v"], primary: ["upper back"], secondary: ["lats", "biceps", "forearms"]),
        // Elbows locked, shoulder extension only — the long head of the
        // triceps does cross the shoulder, so it earns a secondary here where
        // a fly does not. The upper back does NOT: the scapulae depress rather
        // than retract. This was the real source of the weekly Upper back
        // over-count the RDL was wrongly blamed for.
        Entry(["straight", "arm", "pulldown"], primary: ["lats"], secondary: ["triceps"]),

        // ── Delts ───────────────────────────────────────────────────────────
        // Deltoid work is NOT interchangeable for volume accounting. A bare
        // `shoulders` primary folds to SIDE delts, so press + face pull +
        // lateral raise all landed on one line and overhead pressing inflated
        // the side-delt count. Each head is routed to its real primary instead.
        //
        // A FACE PULL IS NOT UPPER-BACK WORK. It reads like it — the scapulae
        // retract — but the load is chosen for the rear delt and the rhomboids
        // never shorten against anything like it; that secondary was 1.5 of
        // the 3.0 by which Onyx over-counted Upper back. It DOES pay the
        // biceps, which was the last line still short of Hevy: exactly 1.5,
        // being 0.5 × three sets. A rope face pull is elbow FLEXION under load
        // as much as horizontal abduction — the hands finish beside the ears,
        // which they cannot do without the elbow closing.
        Entry(["face", "pull"], primary: ["rear_delts"], secondary: ["biceps"]),
        // One bare `["shoulder", "press"]` catches every spelling, including
        // `Shoulder Press (DB)` — which used to resolve to NOTHING, because
        // parentheses were stripped with their contents and the fallback was a
        // bare `shoulders` folding to SIDE delts.
        //
        // ── AND IT PAYS THE TRICEPS, NOT THE SIDE DELT ──────────────────────
        // `side_delts` was a secondary here on the anatomy: the lateral head
        // does abduct and does stabilise a dumbbell press throughout. But
        // Delts & Arms (18 Aug) paid Shoulders 8.5 against Hevy's 7.0, and the
        // gap is 0.5 × 3 press sets to the decimal — this line and nothing
        // else. It is also the honest reading of what the three-head split is
        // FOR: a press that credits the side delt on every set puts back the
        // one indistinguishable "shoulders" number the split exists to
        // abolish, and the side-delt line would rise on a day with no lateral
        // raise in it.
        Entry(["shoulder", "press"], primary: ["front_delts"], secondary: ["triceps"]),
        Entry(["lateral", "raise"], primary: ["side_delts"]),

        // ── Triceps ─────────────────────────────────────────────────────────
        Entry(["triceps", "pushdown"], primary: ["triceps"]),
        Entry(["triceps", "extension"], primary: ["triceps"]),
        Entry(["overhead", "extension"], primary: ["triceps"]),
        Entry(["overhead", "triceps"], primary: ["triceps"]),
        Entry(["cable", "extension"], primary: ["triceps"]),

        // ── Biceps / forearms ───────────────────────────────────────────────
        Entry(["hammer", "curl"], primary: ["biceps"], secondary: ["forearms"]),
        Entry(["neutral", "grip", "curl"], primary: ["biceps"], secondary: ["forearms"]),
        // Reverse (pronated) curl: BICEPS primary, forearms secondary. This
        // has now been had both ways round. The brachioradialis argument is
        // real — pronation does shift load onto it — but the movement is still
        // elbow flexion against a load chosen for the elbow flexors, and the
        // biceps brachii shortens through the whole range whichever way the
        // hand faces. Flipping it back is what puts the weekly Forearms line
        // on 8.5 instead of 9.5.
        Entry(["reverse", "curl"], primary: ["biceps"], secondary: ["forearms"]),
        Entry(["wrist", "curl"], primary: ["forearms"]),
        Entry(["preacher", "curl"], primary: ["biceps"]),
        Entry(["incline", "curl"], primary: ["biceps"]),
        Entry(["bicep", "curl"], primary: ["biceps"]),
        Entry(["biceps", "curl"], primary: ["biceps"]),
    ]

    // MARK: - Matching

    /// Split a name into match tokens.
    ///
    /// ── PARENTHESES ARE SEPARATORS, NOT DELETIONS ───────────────────────────
    /// They used to be stripped along with their contents, which silently
    /// voided every entry whose distinguishing word lived inside one:
    /// `Seated Cable Row (V-Grip)` and `(Wide Grip)` both fell through to the
    /// generic row entry, `Shoulder Press (DB)` matched nothing at all, and
    /// `Crunch (Machine)` behaved differently from `Crunch Machine`. The grip,
    /// the implement and the machine are exactly the words that distinguish two
    /// movements sharing a stem.
    static func tokenize(_ name: String) -> Set<String> {
        let flattened = name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return Set(flattened.split(separator: " ").map(String.init))
    }

    /// Resolve a name → its muscle tags, using the most specific entry whose
    /// tokens are ALL present. `nil` means this map has never seen the
    /// movement — it is never an empty entry, because "trains nothing" and
    /// "unknown" are different facts and only one of them is a bug.
    ///
    /// `lookupMuscles` in the TypeScript.
    public static func movers(_ exerciseName: String) -> MoverTokens? {
        let nameTokens = tokenize(exerciseName)
        var best: (muscles: MoverTokens, specificity: Int)?
        for entry in dict where entry.tokens.allSatisfy(nameTokens.contains) {
            // STRICTLY greater: a tie keeps the entry written first.
            if best == nil || entry.tokens.count > best!.specificity {
                best = (entry.muscles, entry.tokens.count)
            }
        }
        return best?.muscles
    }

    /// Flat muscle tags, primary first — the shape of the `exercises`
    /// `muscle_groups` column, which this file seeded. `nil` for an unknown
    /// movement. `muscleGroupsFor` in the TypeScript.
    public static func muscleGroups(_ exerciseName: String) -> [String]? {
        guard let e = movers(exerciseName) else { return nil }
        return e.primary + e.secondary
    }

    /// Movers resolved by NAME first, falling back to the stored
    /// `muscle_groups` column. The one place every aggregator should go.
    ///
    /// The fallback splits `[0]` = primary, rest = secondary, which is how
    /// `muscleGroups(_:)` writes the column — but it is only ever reached for a
    /// row this dictionary has never seen. Every exercise in the live catalogue
    /// has an entry, and the column has drifted since it was seeded (Face Pull
    /// was still tagged `shoulders, biceps` there, which folds to SIDE delts
    /// and biceps — neither of which a face pull trains). The name is the key;
    /// the column is a stale cache.
    public static func resolveMovers(_ exerciseName: String, stored: [String]? = nil) -> MoverTokens {
        if let entry = movers(exerciseName) { return entry }
        let tags = stored ?? []
        return MoverTokens(primary: Array(tags.prefix(1)), secondary: Array(tags.dropFirst()))
    }

    // MARK: - The landmark fold

    /// Fold a token list to landmark muscles, keeping the first spelling of
    /// each.
    ///
    /// Deduped because a movement can name the same landmark twice: a cable row
    /// is `upper back` primary and `traps` secondary, and both fold to Upper
    /// back. The answer is a set of MUSCLES, not a set of tokens. (The credit
    /// arithmetic already handles the primary/secondary overlap separately —
    /// see `MuscleCredit.weightedSets`, which takes the max rather than the
    /// sum.)
    /// Public since v4.1: the weekly export folds the movers it ALREADY has —
    /// `resolveMovers(name, stored:)`, which honours `exercises.muscle_groups`
    /// — rather than re-resolving from the name, so it needs the token fold on
    /// its own. `primaryLandmarks(_:)` below cannot serve: it discards the
    /// stored override by starting from the name again.
    public static func landmarks(_ tokens: [String]) -> [LandmarkMuscle] {
        var out: [LandmarkMuscle] = []
        for token in tokens {
            guard let muscle = LandmarkMuscle.from(token: token), !out.contains(muscle) else { continue }
            out.append(muscle)
        }
        return out
    }

    /// The landmark muscles this movement is CHOSEN to train. Empty for a
    /// movement the map has never seen — the caller that needs to tell that
    /// apart from "trains nothing tracked" should ask `movers(_:)` for the nil.
    public static func primaryLandmarks(_ exerciseName: String) -> [LandmarkMuscle] {
        landmarks(movers(exerciseName)?.primary ?? [])
    }

    /// The landmark muscles that assist it, at `secondarySetCredit`.
    public static func secondaryLandmarks(_ exerciseName: String) -> [LandmarkMuscle] {
        landmarks(movers(exerciseName)?.secondary ?? [])
    }
}
