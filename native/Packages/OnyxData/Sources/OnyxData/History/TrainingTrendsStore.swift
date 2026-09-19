import Foundation
import GRDB
import OnyxCore

/// One logged session with its sets and the name each set was logged under —
/// the row the Training Trends charts slice.
///
/// ── WHY ONE READ FEEDS FOUR CHARTS ──────────────────────────────────────────
/// The volume stream, the intensity calendar, the strength trends and the
/// muscle focus all walk the same sessions. Four queries would be four chances
/// to disagree about which rows are "the range"; one read, shaped once, cannot.
/// `volumeKg` is `sessionVolumeKg` over the sets (a unilateral pair is ONE set
/// at the weaker side, a ghost is nothing) because the local row stores no
/// tonnage of its own.
public struct TrendSession: Sendable, Equatable, Identifiable {
    public var id: String { session.id }
    public let session: WorkoutSession
    /// In fold order.
    public let sets: [TrendSet]
    public let volumeKg: Double

    public var date: String { session.date }
}

/// A set and the exercise it belongs to. The name — not the id — is what
/// `MuscleMap` keys on, so it travels with the row.
public struct TrendSet: Sendable, Equatable {
    public let set: WorkoutSet
    public let exerciseName: String
}

public extension AppDatabase {
    /// Sessions dated `from...to` (ISO, inclusive), oldest first, with their
    /// sets. Query-only; the charts do the arithmetic through OnyxCore.
    func trainingTrendSessions(userId: String, from: String, to: String) throws -> [TrendSession] {
        try read { db in
            let sessions = try WorkoutSession
                .filter(Column("user_id") == userId && Column("date") >= from && Column("date") <= to)
                .order(Column("date").asc, Column("started_at").asc)
                .fetchAll(db)
            guard !sessions.isEmpty else { return [] }
            // ── THE CATALOGUE, PLUS THE SLUGS THE PHONE WRITES ──────────────
            // `exercises` holds server uuids only. A set logged on the phone is
            // stamped `onyx-<slug>` and keeps that id for as long as the
            // session has local events. Naming only the catalogue dropped every
            // phone-logged set from muscle credit — "Side delts 0/7" after an
            // Upper B was exactly this (F2), fixed in W1 at the widget's reader
            // and at `LoggerModel.restoreLoggedSets`, and MISSED here because
            // nothing keyed on muscle read this table until W3's atlas card.
            let exercises = try Exercise.fetchAll(db)
            let names = Dictionary(
                exercises.map { ($0.id, $0.name) } + ExerciseSlug.nameBySlug(exercises).map { ($0.key, $0.value) },
                uniquingKeysWith: { a, _ in a }
            )
            let sets = try WorkoutSet
                .filter(sessions.map(\.id).contains(Column("session_id")))
                .order(Column("fold_order").asc, Column("set_index").asc)
                .fetchAll(db)
            let bySession = Dictionary(grouping: sets, by: \.sessionId)
            return sessions.map { session in
                let own = bySession[session.id] ?? []
                return TrendSession(
                    session: session,
                    sets: own.map { TrendSet(set: $0, exerciseName: names[$0.exerciseId] ?? $0.exerciseId) },
                    volumeKg: WidgetSnapshotBuilder.volume(own)
                )
            }
        }
    }
}
