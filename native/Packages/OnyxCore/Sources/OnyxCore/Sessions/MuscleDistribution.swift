import Foundation

/// Where the session you are logging is actually going — a port of
/// the web app's `lib/sessions/muscleDistribution.ts`. WARM-UPS COUNT here and only here;
/// a ghost is the one exclusion; a unilateral pair is ONE set.
public enum MuscleDistribution {
    /// Weighted set counts per landmark muscle: primary 1.0, secondary 0.5, an
    /// overlap keeps FULL credit; resolved by name then the stored column.
    public static func weightedSets(_ draft: SessionDraft?) -> [LandmarkMuscle: Double] {
        var out: [LandmarkMuscle: Double] = [:]
        guard let draft = draft else { return out }
        for ex in draft.exercises where !ex.isCardio {
            let sets = ex.sets.filter { $0.isCommitted && $0.setType != "ghost" }
            if sets.isEmpty { continue }
            var seen = Set<String>()
            var count = 0
            for s in sets {
                let key = s.pairId ?? "\(count)-\(s.side ?? "")-\(seen.count)"
                if let p = s.pairId, !p.isEmpty, seen.contains(key) { continue }
                seen.insert(key)
                count += 1
            }
            let movers = MuscleMap.resolveMovers(ex.name, stored: ex.muscleGroups)
            var credit: [LandmarkMuscle: Double] = [:]
            func add(_ tokens: [String], _ weight: Double) {
                for t in tokens {
                    guard let m = LandmarkMuscle.from(token: t) else { continue }
                    credit[m] = max(credit[m] ?? 0, weight)
                }
            }
            add(movers.secondary, MuscleCredit.secondarySetCredit)
            add(movers.primary, 1)
            for (m, w) in credit { out[m] = (out[m] ?? 0) + Double(count) * w }
        }
        return out
    }

    /// PHYSICAL committed sets — ghosts and warm-ups included, a pair once.
    public static func physicalSets(_ draft: SessionDraft?) -> Int {
        guard let draft = draft else { return 0 }
        var total = 0
        for ex in draft.exercises where !ex.isCardio {
            var seen = Set<String>()
            for s in ex.sets where s.isCommitted {
                if let p = s.pairId, !p.isEmpty {
                    if seen.contains(p) { continue }
                    seen.insert(p)
                }
                total += 1
            }
        }
        return total
    }
}

/// Narrow a plan-wide progression queue to one training day — a port of
/// the web app's `lib/training/scopeToDay.ts`. A falsy key keeps EVERYTHING (the PPL era).
public enum ProgressionScope {
    public static func toDay<T>(_ alerts: [T], dayKey: String?, key: (T) -> String?) -> [T] {
        guard let k = dayKey, !k.isEmpty else { return alerts }
        return alerts.filter { key($0) == k }
    }
}
