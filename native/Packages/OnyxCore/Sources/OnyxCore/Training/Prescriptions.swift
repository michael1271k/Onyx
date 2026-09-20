import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// THE CURRENT PRESCRIPTION — what the coach is asking for RIGHT NOW.
//
// ── WHY THIS IS NOT THE PLAN ROW ────────────────────────────────────────────
// `ProgramExercise.wk1Kg` is the BLUEPRINT load: the number the program was
// compiled with in July and never touched since. The export printed it as
// `prescribed` for two months while the coach moved Incline DB Press from 32 kg
// to 34, Lat Pulldown from 45 to 50 and the RDL from 30 to 40 — so every
// `load Δ` the document drew was measured against a number nobody was working
// to. A blueprint is a starting point; a prescription is an instruction with a
// date on it, and the two are different facts that need different storage.
//
// ── NEVER OVERWRITTEN ───────────────────────────────────────────────────────
// Each ingest APPENDS a version. A prescription that changed is a fact about
// the block — "the top set went 34 → 36 on the 14th" is the whole argument a
// progression review is made of — and an UPDATE would destroy it. `current`
// resolves the version in force on a given day; nothing deletes.
// ─────────────────────────────────────────────────────────────────────────────

public struct Prescription: Codable, Equatable, Sendable {

    /// How the working sets are loaded.
    ///
    /// `STRAIGHT` is one load across every set. `TOPSET_BACKOFF` carries its own
    /// per-set loads in `setLoads`, because "40 then two at 32.5" cannot be
    /// said with a single number and rounding it to an average would describe a
    /// session nobody performed.
    public enum Structure: String, Codable, Sendable, CaseIterable {
        case straight = "STRAIGHT"
        case topsetBackoff = "TOPSET_BACKOFF"
    }

    /// Which limb leads a unilateral movement. `NONE` is a bilateral lift —
    /// the absence of the question, not an answer to it.
    public enum LeadRule: String, Codable, Sendable, CaseIterable {
        case alternate = "ALTERNATE"
        case left = "LEFT"
        case right = "RIGHT"
        case none = "NONE"
    }

    /// The movement, by the canonical DISPLAY NAME — the same key
    /// `personal_records.exercise_key` uses, so a prescription and a record
    /// speak about the same lift without a second dictionary between them.
    public var exercise: String
    public var loadKg: Double?
    public var sets: Int?
    /// The window as the coach writes it: `"8–12"`, `"6"`, `"55s"`. Stored as
    /// TEXT and never parsed into a pair on the way in — `repBounds` reads it
    /// where a comparison needs numbers, and a spelling this app cannot parse
    /// still reaches the document intact.
    public var repRange: String?
    public var rpeCap: Double?
    public var structure: Structure
    /// Per-set loads, top set first. Nil on a `STRAIGHT` prescription.
    public var setLoads: [Double]?
    public var leadRule: LeadRule
    public var notes: String?
    /// The first day this version is in force, `yyyy-MM-dd`.
    public var effectiveFrom: String
    /// 1-based, per exercise. Version 1 is the first prescription ever written
    /// for the movement, not the blueprint.
    public var version: Int

    public init(
        exercise: String, loadKg: Double? = nil, sets: Int? = nil, repRange: String? = nil,
        rpeCap: Double? = nil, structure: Structure = .straight, setLoads: [Double]? = nil,
        leadRule: LeadRule = .none, notes: String? = nil, effectiveFrom: String, version: Int = 1
    ) {
        self.exercise = exercise
        self.loadKg = loadKg
        self.sets = sets
        self.repRange = repRange
        self.rpeCap = rpeCap
        self.structure = structure
        self.setLoads = setLoads
        self.leadRule = leadRule
        self.notes = notes
        self.effectiveFrom = effectiveFrom
        self.version = version
    }

    /// The load a comparison is drawn against. On a top set / back-off that is
    /// the TOP SET: it is the load the session is built around and the one the
    /// athlete is being asked to move, and comparing the day's heaviest set to
    /// a back-off would report progress for doing less.
    public var referenceLoadKg: Double? {
        if structure == .topsetBackoff, let first = setLoads?.first { return first }
        return loadKg
    }
}

public enum Prescriptions {

    /// The version in force on `date`, per exercise.
    ///
    /// Latest `effectiveFrom` at or before the day; a tie goes to the higher
    /// version, which is the one written later. A prescription dated AFTER the
    /// day is not yet an instruction and is ignored rather than back-applied.
    public static func current(_ all: [Prescription], on date: String) -> [String: Prescription] {
        var out: [String: Prescription] = [:]
        for p in all where p.effectiveFrom <= date {
            let key = ExerciseAliases.canonicalName(p.exercise)
            guard let cur = out[key] else { out[key] = p; continue }
            if (p.effectiveFrom, p.version) > (cur.effectiveFrom, cur.version) { out[key] = p }
        }
        return out
    }

    /// `"8–12"` → (8, 12); `"6"` → (6, 6). Nil for a window with no number in
    /// it at all, and for a TIMED window (`"55s"`), whose unit is not a rep.
    public static func repBounds(_ raw: String?) -> (floor: Double, ceiling: Double)? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.last?.lowercased() != "s" else { return nil }
        // En dash, em dash, hyphen and "to" all spell the same window.
        let parts = trimmed
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: " to ", with: "-")
            .split(separator: "-")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces).filter { "0123456789.".contains($0) }) }
        guard let first = parts.first else { return nil }
        return (first, parts.count > 1 ? parts[1] : first)
    }

    /// How far a performed rep count sits outside the window — 0 inside it,
    /// negative below the floor, positive above the ceiling.
    ///
    /// A window and not a point: the whole purpose of `8–12` is that any of
    /// those five answers is the prescription met, and a `reps Δ` measured
    /// against one end would report a miss for hitting the other.
    public static func repDelta(_ reps: Double, window: (floor: Double, ceiling: Double)) -> Double {
        if reps < window.floor { return reps - window.floor }
        if reps > window.ceiling { return reps - window.ceiling }
        return 0
    }
}
