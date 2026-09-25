import Foundation

/// The two set figures (founder decision Q10, Precision Lane C).
///
/// **"Sets"** (`total`) is everything the athlete performed: working sets of
/// every kind, warm-ups, and cardio bouts (a bout is stored as one warm-up row
/// carrying duration/distance, so it is one set). A unilateral L/R pair is ONE
/// set. A ghost is a pencil mark and is never a set. This is what
/// `workout_sessions.set_count`, the widget and the export headline.
///
/// **"Working"** (`working`) is the rule every screen already read —
/// `SetTags.isWorkingSet`: no warm-up (so no bout), no ghost, a pair once — and
/// stays the secondary figure (`working_set_count`).
///
/// Seam 1: `LoggerModel.physicalSets` / `workingSets` point here after W-final.
public enum SessionCounts {

    /// Working + warm-up + bouts, a pair once, ghosts excluded.
    public static func total(_ sets: [VolumeSet]) -> Int {
        count(sets) { $0.setType != "ghost" }
    }

    /// Today's working rule: `SetTags.isWorkingSet`, a pair once.
    public static func working(_ sets: [VolumeSet]) -> Int {
        count(sets) { SetTags.isWorkingSet($0.setType) }
    }

    /// Distinct non-empty `pairId`s once, every other row once.
    ///
    /// ── NO SIDE CHECK, ON PURPOSE ───────────────────────────────────────────
    /// `SetGrouping` and `SessionVolume` fold a pair only when both rows carry
    /// a side, because folding a half-written pair would score one arm's load
    /// as the whole set's. A COUNT has no load to misstate, and it is a stored
    /// figure: `set_count` is `count(DISTINCT COALESCE(NULLIF(pair_id, ''),
    /// id))` on the server (`docs/sql/precision-c-backfill-sets.sql`) and was
    /// the same at close before this type existed. Matching that SQL is what
    /// lets the phone's recount and the server's backfill agree row for row;
    /// a sideless pair is malformed data either way.
    private static func count(_ sets: [VolumeSet], _ counts: (VolumeSet) -> Bool) -> Int {
        var pairs = Set<String>()
        var solo = 0
        for s in sets where counts(s) {
            if let p = s.pairId, !p.isEmpty { pairs.insert(p) } else { solo += 1 }
        }
        return solo + pairs.count
    }
}
