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
/// storage default, the pre-v2 meaning of an absent column and the case the
/// export spells with no marker — one enum, and `rawValue` IS the stored
/// string, which is what keeps a round trip through `doms_logs` from needing a
/// translation table.
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

    /// What to WRITE for this side — `nil` for `both`.
    ///
    /// Absence is the storage spelling of "both", so a bilateral rating pushes
    /// a body with no `side` key at all (`encodeIfPresent`) and is byte-identical
    /// on the wire to what every build before this one sent.
    public var stored: String? { self == .both ? nil : rawValue }
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
