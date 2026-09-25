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
    private static func count(_ sets: [VolumeSet], _ counts: (VolumeSet) -> Bool) -> Int {
        var pairs = Set<String>()
        var solo = 0
        for s in sets where counts(s) {
            if let p = s.pairId, !p.isEmpty { pairs.insert(p) } else { solo += 1 }
        }
        return solo + pairs.count
    }
}
