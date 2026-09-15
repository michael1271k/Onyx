import Foundation

/// The one implementation of "how many SETS are these rows".
///
/// ── WHY THIS IS SHARED AND NOT WRITTEN PER CALLER ───────────────────────────
/// "A pair is one set" is stated in five places and had been re-implemented in
/// three of them: `LoggerModel.groups` over `SetRow`, `SessionVolume`'s pair
/// collapse over `VolumeSet`, and `closeSession`'s
/// `count(distinct coalesce(pair_id, id))`. Every drift between them shipped as
/// the same symptom — a deck that says 6/3 — and `DeckRestore` needed the rule
/// too, which would have made four.
///
/// ── AND WHY IT TAKES A CLOSURE RATHER THAN A PROTOCOL ───────────────────────
/// The obvious shape is `protocol PairedSet { var pairKey: String? { get } }`,
/// and it does not compile where it is most needed: `LoggerModel.SetRow` is
/// `@MainActor @Observable`, so its stored `pairId` and `side` are isolated and
/// cannot satisfy a `nonisolated` protocol requirement. Marking the requirement
/// isolated would drag the isolation into OnyxCore, which is Foundation-only by
/// design. A non-escaping closure inherits the caller's isolation and costs
/// nothing, so the rule stays pure and the deck stays on the main actor.
public enum SetGrouping {

    /// The rows, grouped into the SETS they are — a pair together, every other
    /// row alone, in the order they first appear.
    ///
    /// Order is load-bearing: the deck numbers its badges off this, and a
    /// grouping that reordered would renumber a card under the reader's thumb.
    ///
    /// - Parameter pairKey: the pair this row folds onto, or nil when it is a
    ///   set on its own. A `pairId` with no `side` must answer **nil**:
    ///   `SessionVolume` says so explicitly and so does the deck — a row
    ///   carrying a pair id and no side is a half-written set, and folding it
    ///   onto its sibling would score one arm's load as the whole set's.
    public static func groups<T>(_ rows: [T], pairKey: (T) -> String?) -> [[T]] {
        var out: [[T]] = []
        var index: [String: Int] = [:]
        for row in rows {
            guard let key = pairKey(row) else {
                out.append([row])
                continue
            }
            if let at = index[key] {
                out[at].append(row)
            } else {
                index[key] = out.count
                out.append([row])
            }
        }
        return out
    }

    /// PHYSICAL sets — each pair once, every unpaired row once.
    public static func physical<T>(_ rows: [T], pairKey: (T) -> String?) -> Int {
        groups(rows, pairKey: pairKey).count
    }
}
