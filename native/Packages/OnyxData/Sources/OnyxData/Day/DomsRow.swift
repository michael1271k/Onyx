import Foundation
import GRDB
import OnyxCore

/// Reading a `doms_logs` row's laterality, whichever era wrote it.
///
/// ── TWO SPELLINGS OF "THE WHOLE MUSCLE, BOTH SIDES" ─────────────────────────
/// The native app writes NULL in both columns, because a nil is what
/// `encodeIfPresent` leaves OUT of a push body — which is what keeps a bilateral
/// rating byte-identical on the wire and in the export to what shipped before
/// laterality existed.
///
/// The retired web app wrote the same fact as `side = 'both'` and
/// `sub_region = ''` (`scripts/src/subRegions.ts`: *"`''` is that answer's
/// stored sub-region"*), and those rows are still in Supabase until
/// `docs/sql/w9-doms-laterality.sql` normalises them.
///
/// Between this build landing on a phone and that SQL being pasted, the mirror
/// can therefore pull a row spelled the web's way into a store whose writer
/// spells it the app's way — and a lookup that compared the raw column would
/// miss it and mint a SECOND row for a muscle that already had one. So every
/// read goes through here and every write goes through the predicates below,
/// and the two eras answer the same question the same way.
public extension DomsLogRow {
    /// The side this row is about. `nil`, `'both'` and anything unreadable are
    /// all `.both` — the rule `BodySide(stored:)` states.
    var bodySide: BodySide { BodySide(stored: side) }

    /// The part of the muscle, or nil for the whole of it. `''` and whitespace
    /// are the whole muscle, exactly as a missing column is.
    var subRegionName: String? { DomsLogRow.normalise(subRegion) }

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
    /// makes a web-era row findable. A one-sided rating needs no such branch:
    /// `'left'` was only ever spelled one way.
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
