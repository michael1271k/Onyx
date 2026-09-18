import Foundation
import GRDB
import OnyxCore

public extension AppDatabase {

    /// What this day type usually COSTS: the tonnage-weighted mean per-set
    /// rating of the last few sessions of the same split, newest first.
    ///
    /// ── WHY THE SUGGESTION NEEDS IT ─────────────────────────────────────────
    /// `Effort.suggestEffortWord` is deliberately RELATIVE. Rating working sets
    /// at 8.5–9 is what a hypertrophy block looks like, so an absolute map
    /// calls every ordinary Tuesday "Everything" and leaves no word for the day
    /// that earned it. Measured against your own recent sessions of the same
    /// day, a typical one sits at delta ≈ 0 and reads "Hard".
    ///
    /// Below `Effort.minHistory` entries the function ignores this and uses its
    /// cold baseline, so a short answer is not a wrong one — which is why this
    /// returns whatever it finds rather than nil.
    ///
    /// `deriveSessionRpe`, not a plain mean: an unrated set is not a zero, a
    /// warm-up is not a working set, and a heavy set weighs more than a light
    /// one. `SessionDetail.avgRpe` is a different number for a different
    /// question and must not be substituted here.
    func effortHistory(
        userId: String, dayKey: String?, before date: String, limit: Int = 6
    ) throws -> [Double] {
        guard let dayKey else { return [] }
        return try writer.read { db in
            let sessions = try WorkoutSession
                .filter(
                    Column("user_id") == userId
                        && Column("day_key") == dayKey
                        && Column("date") < date
                )
                .order(Column("date").desc, Column("started_at").desc)
                .limit(limit)
                .fetchAll(db)
            guard !sessions.isEmpty else { return [] }

            var byId: [String: [RatedSet]] = [:]
            for set in try WorkoutSet
                .filter(sessions.map(\.id).contains(Column("session_id")))
                .fetchAll(db) {
                byId[set.sessionId, default: []].append(
                    RatedSet(
                        weightKg: set.weightKg, reps: Double(set.reps),
                        rpe: set.rpe, setType: set.setType
                    )
                )
            }
            // An unrated session contributes nothing rather than a zero — the
            // median it feeds is about how hard this day HAS been, and a
            // session nobody rated is not a session that was easy.
            return sessions.compactMap { RpeMemory.deriveSessionRpe(byId[$0.id] ?? []) }
        }
    }

    /// What the last few sessions of the same split WEIGHED — stored tonnage,
    /// OLDEST FIRST, finished sessions only (W10).
    ///
    /// ── WHY THE FINISH SHEET WANTS IT ───────────────────────────────────────
    /// The sheet already prints this session's tonnage as a figure, and a
    /// figure is the one shape that cannot answer the question anybody actually
    /// has at that moment: 13,242 kg is a lot or a little entirely depending on
    /// what the last four Tuesdays came to. Six points behind the number is the
    /// cheapest possible answer and it needs no new column — `total_volume_kg`
    /// has been on the row since the aggregates landed.
    ///
    /// ── AND WHY IT IS THE SAME QUERY AS `effortHistory` ─────────────────────
    /// Same split, strictly before this date, most recent first, capped. A Push
    /// day's tonnage says nothing about a Legs day's, which is the rule stated
    /// one function up and the reason both are scoped by `day_key` rather than
    /// by weekday. `ended_at != nil` is the one addition: a session still being
    /// logged has an aggregate that is true of however much of it has happened,
    /// and plotting it as a completed week would draw every live workout as a
    /// collapse.
    ///
    /// Reversed on the way out because a trail reads left to right in time and
    /// the caller should not have to know this query sorts the other way.
    /// `compactMap`, so a session whose aggregates were never computed is
    /// absent rather than a zero — nil is missing, never zero.
    func splitTonnage(
        userId: String, dayKey: String?, before date: String, limit: Int = 6
    ) throws -> [Double] {
        guard let dayKey else { return [] }
        return try writer.read { db in
            try WorkoutSession
                .filter(
                    Column("user_id") == userId
                        && Column("day_key") == dayKey
                        && Column("date") < date
                        && Column("ended_at") != nil
                )
                .order(Column("date").desc, Column("started_at").desc)
                .limit(limit)
                .fetchAll(db)
                .compactMap(\.totalVolumeKg)
                .filter { $0 > 0 }
                .reversed()
        }
    }
}
