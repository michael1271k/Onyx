import Foundation
import OnyxCore

/// A row of the server's `exercises` catalogue, reduced to what matching needs.
public struct RemoteExercise: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// `exercises.slug` — the legacy local id this row answers for (D3).
    public var slug: String?

    public init(id: String, name: String, slug: String? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
    }
}

/// Turns the local slug on a set into the uuid `workout_sets.exercise_id` needs.
///
/// ── WHY THIS IS THE MOST DANGEROUS FILE IN THE SYNC ─────────────────────────
/// `workout_sets.exercise_id` is a uuid with a live foreign key into a
/// 60-row `exercises` table. The local id is `LoggerModel.exerciseId` — a slug
/// of the movement's name — because the v4 migration deliberately removed the
/// local foreign key so a set logged against an unsynced exercise could not be
/// rejected by its own projection. Something has to bridge the two, and getting
/// it wrong has two failure modes with very different costs:
///
///   · A **merge** — two movements resolving to one row — is loud. Loads from a
///     wide-grip row start appearing in the V-grip ladder and it is obvious.
///   · A **split** — one movement resolving to a new row — is silent. The
///     history simply starts again from zero, the PR baselines with it, and the
///     first return to an old load reads as a new record.
///
/// The catalogue is full of near-duplicates that are deliberately distinct:
/// `Seated Cable Row` / `(V-Grip)` / `(Wide Grip)` were carved apart on
/// 2026-08-06 because sharing one row cost a real record; `Crunch (Machine)`
/// and `Crunch Machine` are two rows on two different splits. So:
///
/// 1. **Exact name wins.** Case-insensitive and trimmed, nothing else. This is
///    what resolves 31 of ONYX-5's 32 movements, and it cannot merge a variant
///    into its parent because both names are in the catalogue verbatim.
/// 2. **Then an UNAMBIGUOUS normalised match.** The same normalisation
///    `resolveExercises.ts` uses — strip parenthesised text, then punctuation —
///    which is what maps the program's `Romanian Deadlift (Dumbbell)` onto the
///    catalogue's `Romanian Deadlift (DB)`. It is accepted **only** when
///    exactly one catalogue row normalises to that key; the web app takes
///    whichever row Postgres happened to return first, which is a coin flip
///    among the three cable rows.
/// 3. **Otherwise it throws.** It does not create the row.
///
/// Point 3 is the deliberate difference from the web app, which creates on a
/// miss. Creating is right for a paste importer taking names from a foreign
/// vocabulary; it is wrong here, where the only names that can arrive are the
/// ones in the user's `routines` rows, and every one of them names a catalogue
/// row. A miss therefore means a routine was edited or the slug function drifted —
/// and in both cases a failed upload that names the movement is worth far more
/// than a 61st row nobody asked for. The exercise library lands in Wave 3 and
/// owns creation from then on.
public struct ExerciseIndex: Sendable {

    private let byExactName: [String: String]
    /// Normalised key → every catalogue row that normalises to it. The VALUES
    /// are what makes ambiguity detectable; a plain `[String: String]` would
    /// silently keep one and discard the rest.
    private let byNormalised: [String: [RemoteExercise]]
    /// `exercises.slug` → id. The legacy `onyx-…` ids, answered by DATA
    /// since W2 (D3): the column is backfilled from the catalogue name with
    /// the same expression `ExerciseSlug.id` uses, and the seed corrected the
    /// founder's where a deck spelled a movement differently.
    private let bySlug: [String: String]
    /// Every uuid the catalogue holds — a set that already carries one passes
    /// through `id(forSlug:)` untouched.
    private let ids: Set<String>
    /// `ExerciseSlug.id(row.name)` → every row whose NAME slugs to it, for a
    /// catalogue with no slug column. Grouped, like `byNormalised`, so a
    /// collision (`Crunch Machine` / `Crunch (Machine)`) is detectable and
    /// refused rather than resolved to whichever row came first — a MERGE.
    private let byComputedSlug: [String: [RemoteExercise]]

    public init(_ catalogue: [RemoteExercise]) {
        byExactName = Dictionary(
            catalogue.map { (Self.exactKey($0.name), $0.id) },
            // Two rows with the same name are impossible: `exercises` has a
            // UNIQUE (user_id, name). Keeping the first is arbitrary and
            // unreachable rather than a decision.
            uniquingKeysWith: { first, _ in first }
        )
        byNormalised = Dictionary(grouping: catalogue, by: { Self.normalisedKey($0.name) })
        bySlug = Dictionary(
            catalogue.compactMap { row in row.slug.map { ($0, row.id) } },
            uniquingKeysWith: { first, _ in first }
        )
        ids = Set(catalogue.map(\.id))
        byComputedSlug = Dictionary(grouping: catalogue, by: { ExerciseSlug.id($0.name) })
    }

    /// Resolve one local exercise id to a catalogue uuid.
    ///
    /// Three shapes arrive here: a uuid the logger stamped from the routine
    /// payload (W2 onward — passes through), a legacy `onyx-…` slug the
    /// catalogue's `slug` column claims, or a slug nothing claims — which
    /// throws, exactly as before, because creating a row is not this file's job.
    public func id(forSlug slug: String) throws -> String {
        if ids.contains(slug) { return slug }
        // ── A STRAGGLER UNDER THE PREDECESSOR'S STAMP IS RE-STAMPED FIRST ───
        // `v32.onyxWire` rewrote every id the store held, but it is a
        // MIGRATION: it runs once, and nothing re-runs it on a row that
        // arrives afterwards. Two things still produce one — a pull that
        // lands before the founder's server UPDATE has run, and a watch still
        // on 6.8.1, which updates independently of the phone and stamps with
        // whatever build is on the wrist.
        //
        // Re-stamping here rather than in each tier below is what keeps the
        // four lookups agreeing: an old-stamped id resolves to exactly the
        // row its migrated siblings resolve to. Without it the slug matches
        // nothing, this throws `unknownExercise`, the set never syncs, and
        // the error names a movement that does not exist.
        let slug = ExerciseSlug.restamped(slug) ?? slug
        if ids.contains(slug) { return slug }
        if let id = bySlug[slug] { return id }
        // ── THE COLUMN'S OWN RULE, COMPUTED ─────────────────────────────────
        // `exercises.slug` is backfilled server-side from the catalogue name
        // with the same expression `ExerciseSlug.id` uses. A catalogue pulled
        // before that DDL ran (or a test remote) has no column, so the same
        // rule runs here: the row whose NAME slugs to this slug. First wins on
        // a collision, as the backfill's rank does.
        if let computed = byComputedSlug[slug] {
            if computed.count == 1 { return computed[0].id }
            throw SyncError.ambiguousExercise(
                name: Self.humanised(Self.slugKey(slug)), candidates: computed.map(\.name).sorted()
            )
        }
        // ── THEN THE NORMALISED TIER ────────────────────────────────────────
        // A slug is the movement's name with the parenthesised text and
        // punctuation collapsed — which is what `normalisedKey` does to a
        // catalogue name. So `onyx-romanian-deadlift` matches the one row
        // that normalises to "romanian deadlift", and refuses when two do:
        // picking one would split a movement's history down the middle.
        let key = Self.slugKey(slug)
        let candidates = byNormalised[key] ?? []
        switch candidates.count {
        case 1: return candidates[0].id
        case 0: throw SyncError.unknownExercise(slug: slug, name: Self.humanised(key))
        default:
            throw SyncError.ambiguousExercise(
                name: Self.humanised(key),
                candidates: candidates.map(\.name).sorted()
            )
        }
    }

    /// `romanian deadlift` → `Romanian Deadlift`, for an error a person reads.
    static func humanised(_ key: String) -> String {
        key.split(separator: " ").map(\.capitalized).joined(separator: " ")
    }

    /// `onyx-romanian-deadlift` → `romanian deadlift`: the slug body with
    /// its hyphens back as spaces, which is `normalisedKey` of the name minus
    /// anything in parentheses.
    ///
    static func slugKey(_ slug: String) -> String {
        var body = slug
        if body.hasPrefix(ExerciseSlug.prefix) { body = String(body.dropFirst(ExerciseSlug.prefix.count)) }
        return body.replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Resolve a movement's NAME to a catalogue uuid — rules 1–3 of the type
    /// header. The slug path above is this with the name looked up first; a
    /// routine payload (W2) carries the name itself and calls this directly.
    public func id(forName name: String, slug: String? = nil) throws -> String {
        if let exact = byExactName[Self.exactKey(name)] { return exact }

        let candidates = byNormalised[Self.normalisedKey(name)] ?? []
        switch candidates.count {
        case 1: return candidates[0].id
        case 0: throw SyncError.unknownExercise(slug: slug ?? ExerciseSlug.id(name), name: name)
        default:
            throw SyncError.ambiguousExercise(
                name: name,
                candidates: candidates.map(\.name).sorted()
            )
        }
    }

    static func exactKey(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// `resolveExercises.ts`'s `normalize`, verbatim: drop parenthesised text,
    /// then collapse everything that is not a letter or a digit into single
    /// spaces. Ported rather than improved — a different normalisation here
    /// would resolve a name onto a different row than the web app does, and the
    /// two writing to different rows for one movement IS the split.
    static func normalisedKey(_ name: String) -> String {
        let withoutParens = name.replacingOccurrences(
            of: "\\([^)]*\\)", with: " ", options: .regularExpression
        )
        return withoutParens
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - The slug

/// The slug the logger stamps on a set, and the way back from it.
///
/// ── THERE ARE TWO COPIES OF THIS FUNCTION AND THAT IS A KNOWN DEBT ──────────
/// `LoggerModel.exerciseId` in the app target has the other one. This package
/// cannot import the app target, and the app target is Track U's to edit, so
/// the copies stay for now — but they are pinned: `ExerciseSlugTests` asserts
/// the exact slug string for every movement in the seeded templates, so a
/// drift in either copy fails a test rather than quietly failing to resolve.
/// When W5 next touches `LoggerModel`, that function should become a call to
/// this one.
///
/// The reverse map is built from `Program.onyx5` rather than by un-slugging,
/// because un-slugging is lossy: `onyx-seated-cable-row-v-grip` cannot be
/// turned back into `Seated Cable Row (V-Grip)` — the parentheses and the
/// capitals are gone — and guessing at it is how a variant gets filed under its
/// parent.
public enum ExerciseSlug {

    /// ── THE PREFIX WAS RENAMED, AND WHY THAT TOOK A MIGRATION ───────────────
    /// It carried the predecessor web app's name until 7.0.0. This slug is not
    /// a brand, it is a KEY: it is written into local `workout_sets.exercise_id`
    /// the moment a set is logged, and it stays there until the next pull
    /// replaces the row with the server's uuid version. Renaming it on its own
    /// would file any set logged-but-not-yet-synced under a second identity —
    /// and a SPLIT is the silent failure this whole file exists to prevent: the
    /// history starts again from zero, PR baselines with it, and the first
    /// return to an old load reads as a new record.
    ///
    /// So it was never renamed on its own. `v32.onyxWire` rewrites every stored
    /// id — the projection, the event log, the catalogue's alias column and the
    /// shadow rows whose `id` IS a slug — in the release that changed this
    /// line, and the founder ran the matching server UPDATE
    /// (`docs/sql/w1-onyx-wire.sql`) for the rows that had already reached
    /// Postgres. Change this string again and you owe the same four rewrites.
    ///
    /// NOT `personal_records`: its `exercise_key` is a canonical display name,
    /// never an id (`PrRecorder.nameResolver`), and renaming keys there would
    /// invent a second history for every lift.
    ///
    /// Must stay byte-identical to the stamping path in `LoggerModel`
    /// (`storedExerciseId`), which calls this function.
    public static let prefix = "onyx-"

    public static func id(_ name: String) -> String {
        prefix + name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// One id stamped by the predecessor, re-stamped with this app's prefix —
    /// or `nil` for anything that is not one.
    ///
    /// The single answer to "is this a predecessor stamp?", used by the
    /// `v32.onyxWire` migration that rewrote the store, and by
    /// `ExerciseIndex.id(forSlug:)` for the stragglers that arrive after it.
    ///
    /// The legacy form was `<brand><digit>-<kebab-name>`, so the BODY is
    /// everything after the first hyphen and it is never touched: the movement
    /// keeps its identity, only the stamp in front of it changes. That is what
    /// makes the rewrite safe to apply to four tables independently — the same
    /// input always yields the same output, so a row missed and caught on a
    /// later run lands on the same id as its neighbours.
    ///
    /// Three shapes are refused, and each refusal matters:
    ///   · a catalogue **uuid** — the id a synced set already carries;
    ///   · an id **already** carrying this prefix — so a second run is a no-op;
    ///   · anything whose first segment is not `<lowercase letters><one digit>`
    ///     — the version number is what distinguishes the predecessor's stamp
    ///     from an ordinary hyphenated id (`ex-treadmill` is left alone, and a
    ///     slug with no hyphen at all has no prefix to replace).
    ///
    /// ── THIS PREDICATE IS SHARED WITH POSTGRES AND MUST STAY SHARED ────────
    /// `docs/sql/w1-onyx-wire.sql` decides the same question with the regex
    /// `^[a-z]+[0-9]-`, and the two run against the SAME movement on two
    /// machines. An earlier draft tested only "the character before the first
    /// hyphen is a digit", which is LOOSER: `5-bench-press`, `xx55-bench-press`
    /// and `Xx5-bench-press` would have been renamed here and left alone by
    /// Postgres, filing one movement under two ids across the sync. The rule
    /// below is that regex, character for character. Change one, change both,
    /// and re-run `matchesThePostgresPredicate`.
    public static func restamped(_ id: String) -> String? {
        guard !id.hasPrefix(prefix),
              UUID(uuidString: id) == nil,
              let dash = id.firstIndex(of: "-")
        else { return nil }
        let stamp = id[id.startIndex..<dash]
        guard let version = stamp.last, version.isASCII, version.isNumber,
              stamp.count > 1,
              stamp.dropLast().allSatisfy({ $0.isASCII && $0.isLetter && $0.isLowercase })
        else { return nil }
        return prefix + id[id.index(after: dash)...]
    }

    /// Slug → name, off the catalogue rows that claim a slug.
    ///
    /// ── THE REVERSE MAP IS DATA NOW (W2) ────────────────────────────────────
    /// It used to be built from `Program.onyx5` — the deck's 32 names plus the
    /// treadmill — because un-slugging is lossy (`onyx-seated-cable-row-v-grip`
    /// cannot be turned back into `Seated Cable Row (V-Grip)`). `exercises.slug`
    /// is that map as a column, backfilled by the W2 DDL and corrected by the
    /// seed, so it answers for every account and every movement the catalogue
    /// holds, not just the founder's deck.
    /// ── AND BELOW THE COLUMN, THE SAME SLUG COMPUTED (W6) ──────────────────
    /// A row created since W6 carries no `slug`: the column is an alias for a
    /// legacy id, and a row with no history has none to alias. But a WATCH
    /// still writes the legacy spelling for a movement the routine payload
    /// could not name, so a set can name a slug no column claims. Without this
    /// tier the reader falls through to the literal key, the deck counts none
    /// of those sets, and the next one is appended under a second identity —
    /// which is the split this file exists to prevent, arriving from the other
    /// direction. `id(forSlug:)` has had the tier since W2 as `byComputedSlug`;
    /// this is the same rule for the name lookup.
    ///
    /// The column still wins. It is what the server actually claims.
    public static func nameBySlug(_ exercises: [Exercise]) -> [String: String] {
        Dictionary(
            exercises.compactMap { e in e.slug.map { ($0, e.name) } },
            uniquingKeysWith: { first, _ in first }
        ).merging(
            Dictionary(exercises.map { (id($0.name), $0.name) }, uniquingKeysWith: { first, _ in first }),
            uniquingKeysWith: { claimed, _ in claimed }
        )
    }
}
