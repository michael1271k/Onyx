import Foundation
import GRDB
import OnyxCore

/// Reading a `doms_logs` row's laterality, whichever era wrote it.
///
/// ── TWO SPELLINGS, AND THE DATABASE PICKED ONE ──────────────────────────────
/// `'both'` and `''` are canonical: the live `doms_logs` declares both columns
/// NOT NULL and the retired web app filled them that way
/// (`scripts/src/subRegions.ts`: *"`''` is that answer's stored sub-region"*).
/// W9 first shipped the opposite — NULL for both — and the table rejected it.
/// The app now writes the words.
///
/// READS stay tolerant anyway, because a local store written by 3.18.0 or
/// 3.18.1 holds NULLs that no migration reaches: those builds are on a phone,
/// not on the server. A lookup that compared the raw column would miss such a
/// row and mint a SECOND rating for a muscle that already had one. So every
/// read goes through here and every write goes through `canonical`, and every
/// era answers the same question the same way.
public extension DomsLogRow {
    /// The side this row is about. `nil`, `'both'` and anything unreadable are
    /// all `.both` — the rule `BodySide(stored:)` states.
    var bodySide: BodySide { BodySide(stored: side) }

    /// The part of the muscle, or nil for the whole of it. `''`, whitespace and
    /// a missing column all read as the whole muscle.
    var subRegionName: String? { DomsLogRow.normalise(subRegion) }

    /// What to WRITE for a sub-region: the trimmed name, or `''` for the whole
    /// muscle. Never nil — the column is NOT NULL on the server.
    static func canonical(subRegion: String?) -> String { normalise(subRegion) ?? "" }

    /// `""` and whitespace collapse to nil; anything else is itself, trimmed.
    static func normalise(_ subRegion: String?) -> String? {
        guard let trimmed = subRegion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// Does this row rate exactly this side and this part?
    func matches(side: BodySide, subRegion: String?) -> Bool {
        bodySide == side && subRegionName == DomsLogRow.normalise(subRegion)
    }

    /// The same question as SQL, for the store's own lookup.
    ///
    /// `Column("side") == nil` is `side IS NULL` in GRDB, and the `or` is what
    /// makes a row written by 3.18.0 or 3.18.1 findable — those builds stored a
    /// bilateral rating as NULL locally. A one-sided rating needs no such
    /// branch: `'left'` was only ever spelled one way.
    static func sideMatch(_ side: BodySide) -> SQLExpression {
        side == .both
            ? (Column("side") == nil || Column("side") == BodySide.both.rawValue)
            : Column("side") == side.rawValue
    }

    static func subRegionMatch(_ subRegion: String?) -> SQLExpression {
        guard let name = normalise(subRegion) else {
            return Column("sub_region") == nil || Column("sub_region") == ""
        }
        return Column("sub_region") == name
    }
}
