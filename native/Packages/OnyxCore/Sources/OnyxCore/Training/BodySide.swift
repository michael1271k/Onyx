import Foundation

/// Which side of the body a rating, a tap or an atlas path is about.
///
/// ── ONE VOCABULARY, NOT THREE ───────────────────────────────────────────────
/// Three names for one idea were available here and all three were already in
/// the tree: the storage column says `"both" | "left" | "right"`
/// (`DomsMuscles.sides`, generated from `scripts/src/subRegions.ts`), the atlas
/// would naturally call a path that straddles the spine "centre", and the
/// export writes `@L` / `@R` with nothing at all for a bilateral rating.
///
/// They collapse, because a CENTRE path is a muscle with no side, and a muscle
/// with no side is rated for both of them. So `both` is the atlas's centre, the
/// `doms_logs` column's default, the reading of an absent or unreadable value,
/// and the case the export spells with no marker — one enum, and `rawValue` IS
/// the stored string, which is what keeps a round trip through `doms_logs` from
/// needing a translation table.
///
/// `SorenessSideParityTests` pins `allCases.map(\.rawValue)` against
/// `DomsMuscles.sides`, so the generated vocabulary and this enum cannot drift.
public enum BodySide: String, CaseIterable, Codable, Sendable, Hashable {
    case both, left, right

    /// The export's marker — `""`, `"L"` or `"R"`.
    ///
    /// A 1:1 port of `SIDE_MARK` in `scripts/src/subRegions.ts`. `both` carries
    /// NO marker, which is the whole reason a bilateral whole-muscle token is
    /// byte-identical to the one v1 wrote before this column existed.
    public var mark: String {
        switch self {
        case .both:  return ""
        case .left:  return "L"
        case .right: return "R"
        }
    }

    /// What the popover's segment and VoiceOver call it.
    public var label: String {
        switch self {
        case .both:  return "Both"
        case .left:  return "Left"
        case .right: return "Right"
        }
    }

    /// A stored `side` column read back. `nil` is `both` — the pre-v2 meaning
    /// of an absent column, and the reason a legacy row needs no backfill to be
    /// readable.
    ///
    /// An UNRECOGNISED string is also `both`, for the same reason
    /// `DomsMuscles.recognised` exists: a row nobody can read must not be able
    /// to invent a side, and "the whole muscle" is the only answer that cannot
    /// be wrong about which half hurts.
    public init(stored: String?) {
        guard let stored, let side = BodySide(rawValue: stored) else { self = .both; return }
        self = side
    }

    /// What to WRITE for this side. Always the word, never an absence.
    ///
    /// ── W9 SHIPPED THE OPPOSITE OF THIS, AND THE DATABASE DISAGREED ─────────
    /// The first design made `both` store NULL, on the reasoning that a nil is
    /// omitted from a push body (`encodeIfPresent`) and so a bilateral rating
    /// would be byte-identical on the wire to what shipped before laterality
    /// existed. The live `doms_logs` had already settled the question the other
    /// way: the retired web app added both columns as **NOT NULL** and wrote
    /// `'both'` / `''` for a whole-muscle rating, so a NULL was not merely a
    /// different spelling — it was a value the table rejects outright.
    ///
    /// One spelling everywhere is worth more than the wire property, which
    /// nobody asked for. The requirement was that the EXPORT TOKEN for a
    /// bilateral rating stay byte-identical to v1, and it does: `mark` is the
    /// empty string for `both`, whatever the column holds.
    public var stored: String { rawValue }

    /// What the EXPORT carries — `nil` for `both`.
    ///
    /// NOT the same question as `stored`, though the two were briefly the same
    /// answer. The database column holds a word because it is NOT NULL;
    /// `ExportDoms.side` holds an absence because the document's grammar spells
    /// a bilateral rating with no marker at all, and `weekly-export.json`'s v1
    /// cases pin that. Collapsing the two is what broke the golden document the
    /// first time this convention changed.
    public var exported: String? { self == .both ? nil : rawValue }
}

/// A landmark and the side of it — the key everything that DRAWS laterality is
/// keyed on.
///
/// `worked` is deliberately NOT keyed on this. Modelled fatigue is bilateral
/// and always was: the ledger records that a set of squats happened, not which
/// leg did more of it, and splitting the fill would be inventing a number.
/// Soreness is the opposite — it is reported, and a lifter who is sore in one
/// glute knows it — so `colors`, `values` and `outlined` key here.
public struct MuscleSide: Hashable, Sendable, Codable {
    public let muscle: LandmarkMuscle
    public let side: BodySide

    public init(_ muscle: LandmarkMuscle, _ side: BodySide = .both) {
        self.muscle = muscle
        self.side = side
    }

    /// "Glutes" · "Glutes, right" — the accessibility label and the popover's
    /// title. `both` says nothing extra, because "Glutes, both" is a sentence
    /// nobody says about a body.
    public var label: String {
        side == .both ? muscle.rawValue : "\(muscle.rawValue), \(side.label.lowercased())"
    }
}
