import Foundation

/// Where a week's set count sits relative to a muscle's target — the
/// `volumeZone` half of the web app's `lib/training/landmarks.ts`.
public enum VolumeZone: String, Codable, Sendable { case under, building, optimal, over, na }

public extension VolumeZone {
    /// TWO NUMBERS, DELIBERATELY. A muscle is UNDER only if even its TOTAL
    /// (direct + half-credited assistance) falls short; only DIRECT work can
    /// earn an OVER. `na` when there is no target.
    static func of(weeklySets: Double, target: Double, directSets: Double? = nil) -> VolumeZone {
        if target <= 0 { return .na }
        if (directSets ?? weeklySets) / target > 1.3 { return .over }
        let ratio = weeklySets / target
        if ratio < 0.5 { return .under }
        if ratio < 1.0 { return .building }
        return .optimal
    }
}
