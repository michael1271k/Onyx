import Foundation

// The Train tab's arrangement — which of its sections the reader has put away.
//
// ── WHY IT LIVES IN THE DASHBOARD'S ROW AND NOT A TABLE OF ITS OWN ───────────
// `dashboard_layouts` is already one row per user, already mirrored, already
// pushed through the outbox by `saveDashboardLayout`, and already two-sided —
// it carries a `phone` arrangement and a `desktop` one that neither surface
// parses. A third sibling key costs a migration nobody has to run, a policy
// nobody has to write, and a puller that already works. A `train_layouts` table
// would cost all three to store five booleans.
//
// ── AND WHY IT IS NOT A DASHBOARD ───────────────────────────────────────────
// Sharing a row is not sharing a model. The dashboard is an ARRANGEABLE grid:
// slots, sizes, stacking, drag and drop. Train is not and is deliberately not
// (W6 §4) — it has one live state and a plan card that has to be the first
// thing seen, so the only verb it offers is show/hide. Modelling that as a
// `DashboardLayout` would mean inventing slots for sections that cannot move.
//
// ── THE PAYLOAD `v` IS NOT BUMPED, AND THAT IS ON PURPOSE ───────────────────
// `Dashboard.version` is not a label on the payload — it is the GATE that
// decides whether a stored object has `phone`/`desktop` sides at all
// (`fromStored`). Raising it to 5 without widening that gate reads every
// existing v4 row as "no sides" and hands every user the default dashboard, and
// widening the gate rewrites two golden fixtures that were exported from the
// retired web app and cannot be regenerated. So `train` is read and written
// INDEPENDENTLY of `v`: absent means "everything visible", which is the correct
// answer for every payload ever written, of any version. W7 owns the v5 bump
// (A9's `StackSlot.linked`) and will find this key already sitting beside the
// sides, needing nothing from it.

/// One hideable section of the Train tab.
///
/// `trends` is the Trends DOOR, not the doors row — the row is its own case, so
/// a reader who wants the Library and History counts without a week delta can
/// have them, and one who wants none of the three can put the whole strip away.
///
/// Declaration order is the order the Customize sheet lists them in, which is
/// top-to-bottom screen order.
public enum TrainSection: String, Codable, Sendable, CaseIterable {
    case doors, trends, cardio, progression, pastWeeks
}

/// The sections the reader has put away, and when they last said so.
///
/// HIDDEN, not shown — the same choice `DashboardLayout.hidden` makes and for
/// the same reason it states: a section added by a later wave must arrive
/// VISIBLE for everyone who has already saved an arrangement, and a stored list
/// of what to show cannot express "and anything you add later".
public struct TrainLayout: Codable, Sendable, Equatable {
    public var hidden: [TrainSection]
    /// Epoch ms of the last edit; 0 for an arrangement never written.
    public var updatedAt: Double

    public init(hidden: [TrainSection] = [], updatedAt: Double = 0) {
        self.hidden = hidden
        self.updatedAt = updatedAt
    }

    public static let `default` = TrainLayout()

    public func shows(_ section: TrainSection) -> Bool { !hidden.contains(section) }

    /// The same layout with one section shown or hidden, stamped.
    ///
    /// Stamped HERE rather than by the caller, for the reason
    /// `Dashboard.touch` gives: every mutation goes through one door, so
    /// `updatedAt` cannot lie about an edit that skipped it.
    public func setting(_ section: TrainSection, visible: Bool) -> TrainLayout {
        var out = hidden.filter { $0 != section }
        if !visible { out.append(section) }
        // Sorted into declaration order so two devices that hid the same two
        // sections in a different order store the same bytes — a diff in the
        // mirror is a sync round trip, and this one would carry no meaning.
        let rank = Dictionary(uniqueKeysWithValues: TrainSection.allCases.enumerated().map { ($1, $0) })
        return TrainLayout(
            hidden: out.sorted { rank[$0, default: 0] < rank[$1, default: 0] },
            updatedAt: (Date().timeIntervalSince1970 * 1000).rounded(.down)
        )
    }
}

public extension Dashboard {
    /// The sibling key on `dashboard_layouts.layout` that holds the above.
    static let trainKey = "train"

    /// The Train arrangement inside a stored payload. Never throws; every shape
    /// that is not a readable `train` object is the default, which is the state
    /// the tab shipped in and the one a corrupt row should fall back to.
    static func trainLayout(from stored: Any?) -> TrainLayout {
        guard let dict = stored as? [String: Any],
              let side = dict[trainKey] as? [String: Any]
        else { return .default }
        let hidden = (side["hidden"] as? [Any])?
            .compactMap { ($0 as? String).flatMap(TrainSection.init(rawValue:)) } ?? []
        let updatedAt: Double = {
            if let n = jsNumber(side["updatedAt"]), n.isFinite { return n }
            return 0
        }()
        // Deduplicated: a hand-edited row naming the same section twice would
        // otherwise round-trip as a growing list.
        var seen = Set<TrainSection>()
        return TrainLayout(hidden: hidden.filter { seen.insert($0).inserted }, updatedAt: updatedAt)
    }

    /// The stored payload with the Train arrangement replaced and EVERYTHING
    /// ELSE — both surfaces, the version, anything a later wave adds — carried
    /// through byte for byte.
    ///
    /// The mirror image of `serializeLayout`'s `other`, and it has to exist for
    /// the same reason: the phone writes one key of a row it shares, and a
    /// writer that rebuilt the object would silently drop the half it does not
    /// understand.
    static func withTrain(_ layout: TrainLayout, in stored: Any?) -> [String: Any] {
        var out = (stored as? [String: Any]) ?? [:]
        out[trainKey] = [
            "hidden": layout.hidden.map(\.rawValue),
            "updatedAt": layout.updatedAt,
        ] as [String: Any]
        return out
    }
}
