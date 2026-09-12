import Foundation

/// A training program — the SHAPE of a deck. The decks themselves are rows.
///
/// ── WHY THERE IS NO `Program.onyx5` ANY MORE (W2, 2026-09-10) ───────────────
/// Until W2 the founder's three decks were compiled into this package, and a
/// second account inherited all of them. They live in `routines` now — one
/// row per program day, the exercises in a jsonb payload — and `Routines.swift`
/// turns those rows into these values. Everything downstream still reads one
/// `Program`, so the logger, the muscle sheet and the phase toggle agree the
/// way they always did; what changed is where the value comes from.
///
/// ── AND WHY THE MOVERS ARE NO LONGER SPELLED OUT HERE ───────────────────────
/// Every lift used to carry its own resolved `primary:` / `secondary:` answer,
/// hand-copied out of the web app's `lib/exercises/muscleMap.ts` because that dictionary
/// had not been ported yet. Two hand-maintained copies of the same anatomy both
/// look right, so the copies are gone: `ProgramExercise.init` now asks
/// `MuscleMap` for the movers, keyed on the lift's own name, and there is one
/// answer to the question "what does a face pull train".
///
/// All 37 movements were checked against their copied literals before the
/// literals were deleted, and all 37 agreed — see the parity test in
/// `TrainingTests`, which now asserts the weaker but permanent version of that
/// claim: every lift in this deck RESOLVES in the map. A lift that does not is
/// a lift with no anatomy, and it would otherwise vanish from the muscle sheet
/// in silence.
///
/// `movers:` stays as an override for a lift the map genuinely cannot answer —
/// and if one ever disagrees with the map, spell it out here with the conflict
/// named rather than quietly adopting either side.
///
/// See `exercise-catalog-merges`: `Seated Cable Row` is TWO exercises split by
/// grip, and they must never be re-merged.

// MARK: - Phase

/// A variation INSIDE a plan. Two values, and `maintenance` was never a third:
/// it resolved to the bulk deck, changing no exercise, no set count and no rep
/// window. A maintenance week is a NUTRITION lever, applied on top of whichever
/// direction the block is running — so offering it here would be offering a
/// training decision that does not train anything.
public enum ProgramPhase: String, CaseIterable, Codable, Sendable {
    case cut
    case bulk

    public var label: String {
        switch self {
        case .cut:  "Cut"
        case .bulk: "Bulk"
        }
    }

    public var blurb: String {
        switch self {
        case .cut:  "MEV+ — defend muscle in the deficit. Fewer sets on the assistance work."
        case .bulk: "MAV — the productive ceiling. Full volume on every lift."
        }
    }
}

// MARK: - Exercise

public struct ProgramExercise: Identifiable, Sendable, Equatable, Codable {
    public var name: String
    /// The catalogue row (`exercises.id`) this prescription names, when the
    /// routine payload carries one. The logger stamps it on every set it logs
    /// (D3); nil is a template movement the catalogue has not resolved yet,
    /// and the set falls back to the legacy slug.
    public var exerciseId: String?
    /// BULK (base) working-set count.
    public var sets: Int
    /// CUT working-set count. `nil` → same as `sets`; `0` → dropped entirely on
    /// a cut. It may legitimately EXCEED `sets` when a lift is prioritised
    /// while cutting.
    public var cutSets: Int?
    /// Starting load, in kilograms. `nil` is not `0`: a hack squat with no
    /// seed load is a lift nobody has recorded yet, and a bodyweight movement
    /// is a lift performed at zero. Both exist in this deck and they are not
    /// the same fact.
    public var wk1Kg: Double?
    /// The double-progression window, as written: `"8–12"`, `"55s"`.
    public var reps: String
    /// TARGET rest between working sets, in seconds — PRESCRIBED, never
    /// measured. ONYX used to answer "how long should I rest" by timing the
    /// gap between two set ticks, which is a different question with a
    /// different answer.
    public var restSec: Int?
    /// Resolved from `MuscleMap` by name at construction — see the type header.
    public var movers: MoverTokens
    public var isCompound: Bool
    public var note: String?

    /// Stable within a day, which is all the logger needs — the same movement
    /// appears in two different days (Chest Press is in both Upper A and Upper
    /// B) and those are two different rows with two different set counts.
    public var id: String { name }

    public init(
        _ name: String,
        exerciseId: String? = nil,
        sets: Int,
        cutSets: Int? = nil,
        wk1Kg: Double?,
        reps: String,
        restSec: Int? = nil,
        movers: MoverTokens? = nil,
        compound: Bool = false,
        note: String? = nil
    ) {
        self.name = name
        self.exerciseId = exerciseId
        self.sets = sets
        self.cutSets = cutSets
        self.wk1Kg = wk1Kg
        self.reps = reps
        self.restSec = restSec
        // The map answers for every lift in this deck, and the parity test
        // holds it to that. The empty fallback exists so a typo in a NEW lift's
        // name is a failing test rather than a compile error nobody can fix
        // without inventing anatomy.
        self.movers = movers ?? MuscleMap.movers(name) ?? MoverTokens(primary: [])
        self.isCompound = compound
        self.note = note
    }

    /// The working-set count for a phase. A lift with `cutSets == 0` is dropped
    /// entirely on a cut.
    public func sets(for phase: ProgramPhase) -> Int {
        phase == .cut ? (cutSets ?? sets) : sets
    }

    /// The rep window's floor and ceiling, or `nil` when the prescription is
    /// not a rep count at all (`"55s"` is a duration).
    ///
    /// The separator is an EN DASH in the source data, not a hyphen. Splitting
    /// on `"-"` returns the whole string and the ceiling silently becomes the
    /// floor, which is how a double-progression ceiling stops being reachable.
    public var repWindow: (floor: Int, ceiling: Int)? {
        // One parser — `Ceilings.parseRepWindow` is the port of the web's, and
        // the golden vectors hold it to every string in the deck.
        guard let w = Ceilings.parseRepWindow(reps) else { return nil }
        return (Int(w.floor), Int(w.ceiling))
    }
}

// MARK: - Day

public struct ProgramDay: Identifiable, Sendable, Equatable, Codable {
    public var key: String
    public var label: String
    /// The split sub-type shown under the name, e.g. "Quad Focus".
    public var sub: String?
    /// The day's own colour as `0xRRGGBB` — `DAY_COLOR[key]` in
    /// the web app's `lib/theme/palette.ts`. Carried as a number rather than as a
    /// `Color` because `OnyxCore` imports Foundation and nothing else; the
    /// view turns it into a colour, and there is still only one source for what
    /// "Upper B" looks like.
    public var accent: UInt32
    /// 0 = Sunday … 6 = Saturday. **Never infer the split from the weekday when
    /// reading a logged session** — a swap moves a workout to another date and
    /// a Wednesday "Delts & Arms" landed in the Upper A curve exactly that way.
    /// This field is for laying out the PLAN, not for classifying history.
    public var weekday: Int
    public var exercises: [ProgramExercise]

    /// Public because the app target builds one.
    ///
    /// `SessionDetailView.editorDay` folds a logged session onto its program
    /// day so it can be corrected on the logger's own deck. A session the
    /// program cannot name — no `day_key` at all (the 74 Notion-era sessions
    /// have none), or a key from a program that has since been retired — had
    /// no day to fold onto and was therefore UNEDITABLE, which is a record the
    /// app will show you and refuse to let you fix. The deck it needs is the
    /// session's own movements, and that is a `ProgramDay` with an empty
    /// `exercises` list for `editorDay` to fill.
    public init(
        key: String, label: String, sub: String? = nil,
        accent: UInt32, weekday: Int, exercises: [ProgramExercise]
    ) {
        self.key = key
        self.label = label
        self.sub = sub
        self.accent = accent
        self.weekday = weekday
        self.exercises = exercises
    }

    public var id: String { key }

    /// The deck as this phase actually trains it: dropped lifts removed, set
    /// counts resolved.
    public func exercises(for phase: ProgramPhase) -> [ProgramExercise] {
        exercises.filter { $0.sets(for: phase) > 0 }
    }

    /// Total prescribed working sets for a phase — the number the header's
    /// "sets" tile counts up to.
    public func plannedSets(for phase: ProgramPhase) -> Int {
        exercises.reduce(0) { $0 + $1.sets(for: phase) }
    }
}

// MARK: - Program

public struct Program: Sendable, Equatable, Codable {
    public var id: String
    public var label: String
    public var blurb: String
    public var days: [ProgramDay]

    public init(id: String, label: String, blurb: String = "", days: [ProgramDay]) {
        self.id = id; self.label = label; self.blurb = blurb; self.days = days
    }

    public func day(key: String) -> ProgramDay? {
        days.first { $0.key == key }
    }

    public func day(weekday: Int) -> ProgramDay? {
        days.first { $0.weekday == weekday }
    }
}
