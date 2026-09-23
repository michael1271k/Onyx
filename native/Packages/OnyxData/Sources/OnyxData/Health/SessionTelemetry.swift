import Foundation
import GRDB
import OnyxCore
import os

/// A finished session's heart-rate series, cut into its movements.
/// Expansion W5, founder decision 10.
///
/// ── READ FROM HEALTH AT VIEW TIME, CACHED LOCALLY, NEVER SYNCED ─────────────
/// The series is Health's — the watch's samples reach the phone through
/// Apple's own sync and nothing here re-uploads them. What this actor adds is
/// (1) the cut: `HRSegments` over the session's `set_events`, so the line is
/// labelled with the movement it was under, honouring pause/resume; (2) the
/// cache: `session_telemetry`, written after the first NON-EMPTY read so the
/// second open of a session never asks Health again; (3) the late window: a
/// finish on the watch lands its samples on the phone minutes later, so
/// `prefetch` watches the heart-rate store for ten minutes after a finish and
/// re-reads once when something arrives.
///
/// ── IT NEVER BLOCKS A VIEW ──────────────────────────────────────────────────
/// Every entry point is `async` and returns nil for "nothing yet"; the card
/// draws a skeleton until the reading lands and draws nothing at all when
/// the session has no samples. `onLateArrival` is the one push: the app
/// bumps a generation the views key their `.task` on.
public actor SessionTelemetry {

    /// One session's telemetry, as the view draws it.
    public struct Reading: Sendable, Equatable {
        public var samples: [HRSample]
        public var segments: [HRSegment]
        /// Where the series came from — `"health"` today; the cache row keeps
        /// it so a later source (a workout-scoped read) can be told apart.
        public var source: String
        public var fetchedAt: Date
        /// True when this came off the cache row rather than from Health.
        public var cached: Bool
        /// The session's own two numbers over the live samples.
        public var avgBpm: Int?
        public var maxBpm: Int?

        public var isEmpty: Bool { samples.isEmpty }
    }

    /// What the athlete said to the Hevy card.
    public enum HevyDecision: String, Sendable {
        case skip, use
    }

    /// The late-sample window after a finish (decision 10: "ten minutes").
    public static let lateWindow: TimeInterval = 600
    public static let source = "health"

    private let database: AppDatabase
    private let reader: any HealthReading
    private let ownBundleId: String
    private let log = Logger(subsystem: "app.onyx.health", category: "telemetry")

    /// Called after a late refetch fills a cache that was empty at finish.
    /// Set once by the app; the argument is the session id.
    private var onLateArrival: (@Sendable (String) -> Void)?

    public init(database: AppDatabase, reader: any HealthReading, ownBundleId: String = Bundle.main.bundleIdentifier ?? "") {
        self.database = database
        self.reader = reader
        self.ownBundleId = ownBundleId
    }

    public func setOnLateArrival(_ handler: @escaping @Sendable (String) -> Void) {
        onLateArrival = handler
    }

    // MARK: - Reading

    /// The series and its segments, from the cache when there is one.
    ///
    /// Nil when the session is unknown or has no interval. An EMPTY reading
    /// (Health holds nothing for the interval) is returned but never cached,
    /// so the next open asks again — the watch's samples may simply not have
    /// arrived yet.
    public func reading(sessionId: String) async -> Reading? {
        if let hit = try? database.telemetryCache(sessionId: sessionId), let samples = hit.samples {
            log.notice("telemetry cache hit for session \(sessionId, privacy: .public): \(samples.count) samples")
            // The SAMPLES are the cache; the cut is re-made against the log
            // as it stands, so a set voided or a movement added on the
            // summary page moves the washes and the labels with it.
            let cut = recut(samples: samples, sessionId: sessionId)
            return Reading(
                samples: samples, segments: cut.segments, source: hit.source ?? Self.source,
                fetchedAt: hit.fetchedAt ?? Date(), cached: true, avgBpm: cut.avgBpm, maxBpm: cut.maxBpm
            )
        }
        return await fetch(sessionId: sessionId)
    }

    /// Straight from Health, then into the cache if there was anything.
    private func fetch(sessionId: String) async -> Reading? {
        // ── A LIVE SESSION READS TO NOW AND IS NEVER CACHED ─────────────────
        // The finish sheet draws the chart BEFORE `closeSession` writes
        // `ended_at`, so an open session is read up to this moment. Nothing
        // about it is final — the next set moves the last segment — so the
        // cache row waits for the finish; `sessionFinished`'s prefetch is
        // what writes it, over the real interval.
        guard let session = sessionRow(sessionId), let start = session.startedAt else { return nil }
        let live = session.endedAt == nil
        let end = session.endedAt ?? Date()
        guard end > start else { return nil }
        guard reader.isAvailable else {
            return Reading(samples: [], segments: [], source: Self.source, fetchedAt: Date(), cached: false, avgBpm: nil, maxBpm: nil)
        }
        let samples = (try? await reader.heartRateSeries(start: start, end: end)) ?? []
        let markers = Self.markers((try? database.setEvents(sessionId: sessionId)) ?? [])
        let segments = HRSegments.build(markers: markers, samples: samples, sessionStart: start, sessionEnd: end)
        let numbers = HRSegments.summary(markers: markers, samples: samples, sessionStart: start, sessionEnd: end)
        let now = Date()
        if !samples.isEmpty, !live {
            try? database.writeTelemetryCache(
                sessionId: sessionId, samples: samples, segments: segments, source: Self.source, fetchedAt: now
            )
            log.notice("telemetry cached for session \(sessionId, privacy: .public): \(samples.count) samples, \(segments.count) segments")
            // ── THE ROW LEARNS THE AVERAGE THE CHART SHOWS ──────────────────
            // A phone-only session has no own `HKWorkout`, so `SessionMetrics`
            // could only estimate its heart rate — while this card drew the
            // mean of the watch's own passive samples over the same minutes.
            // Two answers for one number on one screen. The series IS a
            // measurement of this session, so the row takes its mean, stamped
            // measured — and only over an estimate or a blank: a measured
            // figure (the watch's workout, or typed) is never overwritten.
            if let avg = numbers.avgBpm, session.avgBpm == nil || session.avgBpmEstimated {
                _ = try? database.setSessionMetrics(id: sessionId, userId: session.userId, avgBpm: avg)
            }
        }
        return Reading(
            samples: samples, segments: segments, source: Self.source, fetchedAt: now, cached: false,
            avgBpm: numbers.avgBpm, maxBpm: numbers.maxBpm
        )
    }

    /// The window Apple's recovery sample must START in to belong to this
    /// session: from two minutes before the finish (the two devices' clocks)
    /// to ten after. Tight on purpose — a run ended twenty minutes later
    /// writes its own recovery, and it is not this session's.
    static let recoveryWindow: (before: TimeInterval, after: TimeInterval) = (120, 600)

    /// Apple's one-minute heart-rate recovery after a FINISHED session, in bpm
    /// dropped (App Store W6). Its own read, beside `reading`, not inside it:
    /// Apple writes the sample a minute or more after the finish, so it is
    /// never cached — and a cached series must not wait on Health for it.
    /// Nil for no sample (the ordinary answer for a phone-only session) and
    /// for a session still open.
    public func recoveryBpm(sessionId: String) async -> Int? {
        guard let end = sessionRow(sessionId)?.endedAt, reader.isAvailable,
              let bpm = try? await reader.quantity(
                HealthCatalogue.heartRateRecoveryIdentifier, reduce: .latest,
                start: end.addingTimeInterval(-Self.recoveryWindow.before),
                end: end.addingTimeInterval(Self.recoveryWindow.after)),
              bpm.isFinite, bpm > 0
        else { return nil }
        return Int(bpm.rounded())
    }

    /// A CACHED series, cut against the session's current markers.
    private func recut(samples: [HRSample], sessionId: String) -> (segments: [HRSegment], avgBpm: Int?, maxBpm: Int?) {
        guard let session = sessionRow(sessionId),
              let start = session.startedAt, let end = session.endedAt
        else { return ([], nil, nil) }
        let markers = Self.markers((try? database.setEvents(sessionId: sessionId)) ?? [])
        let numbers = HRSegments.summary(markers: markers, samples: samples, sessionStart: start, sessionEnd: end)
        let segments = HRSegments.build(markers: markers, samples: samples, sessionStart: start, sessionEnd: end)
        return (segments, numbers.avgBpm, numbers.maxBpm)
    }

    /// By id alone: the store holds ONE account's rows (README, "One store,
    /// one user"), and the cache row this feeds is local to the same store.
    private func sessionRow(_ sessionId: String) -> WorkoutSession? {
        (try? database.writer.read { db in try WorkoutSession.fetchOne(db, key: sessionId) }) ?? nil
    }

    /// The log, reduced to what segmenting reads. Fold order is the store's
    /// (`setEvents` sorts by `(seq, deviceId, id)`); a voided set still marks
    /// the time its movement was under the bar, so tombstones are ignored
    /// rather than subtracted.
    static func markers(_ events: [SetEvent]) -> [HRSegments.Marker] {
        events.compactMap { event in
            switch event.body {
            case .append(let snapshot): .set(exerciseId: snapshot.exerciseId, at: event.createdAt)
            case .pause: .pause(at: event.createdAt)
            case .resume: .resume(at: event.createdAt)
            case .amend, .void: nil
            }
        }
    }

    // MARK: - Prefetch

    /// Warm the cache right after a finish, and keep listening for the
    /// watch's samples for `lateWindow` if the first read came back empty.
    ///
    /// Returns when the cache holds a series or the window closes. Callers
    /// run it in a detached task; nothing awaits it on a screen.
    public func prefetch(sessionId: String, finishedAt: Date = Date()) async {
        if let first = await reading(sessionId: sessionId), !first.isEmpty { return }
        let deadline = finishedAt.addingTimeInterval(Self.lateWindow)
        for await _ in reader.heartRateChanges(until: deadline) {
            if let late = await fetch(sessionId: sessionId), !late.isEmpty {
                log.notice("late heart-rate samples landed for session \(sessionId, privacy: .public)")
                onLateArrival?(sessionId)
                return
            }
        }
    }

    // MARK: - The Hevy card's answer

    public func hevyDecision(sessionId: String) -> HevyDecision? {
        ((try? database.telemetryCache(sessionId: sessionId))?.hevyDecision).flatMap(HevyDecision.init(rawValue:))
    }

    public func setHevyDecision(sessionId: String, _ decision: HevyDecision) {
        try? database.writeHevyDecision(sessionId: sessionId, decision.rawValue)
    }
}

// MARK: - The store's half

extension AppDatabase {

    struct TelemetryCacheRow: Sendable {
        var samples: [HRSample]?
        var segments: [HRSegment]?
        var source: String?
        var fetchedAt: Date?
        var hevyDecision: String?
    }

    private static let telemetryEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private static let telemetryDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    func telemetryCache(sessionId: String) throws -> TelemetryCacheRow? {
        try writer.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT samples_json, segments_json, source, fetched_at, hevy_decision FROM session_telemetry WHERE session_id = ?",
                arguments: [sessionId]
            ) else { return nil }
            let samples = (row["samples_json"] as Data?).flatMap { try? Self.telemetryDecoder.decode([HRSample].self, from: $0) }
            let segments = (row["segments_json"] as Data?).flatMap { try? Self.telemetryDecoder.decode([HRSegment].self, from: $0) }
            return TelemetryCacheRow(
                samples: samples, segments: segments, source: row["source"],
                fetchedAt: row["fetched_at"], hevyDecision: row["hevy_decision"]
            )
        }
    }

    func writeTelemetryCache(
        sessionId: String, samples: [HRSample], segments: [HRSegment], source: String, fetchedAt: Date
    ) throws {
        let samplesJSON = try Self.telemetryEncoder.encode(samples)
        let segmentsJSON = try Self.telemetryEncoder.encode(segments)
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO session_telemetry (session_id, samples_json, segments_json, source, fetched_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(session_id) DO UPDATE SET
                        samples_json = excluded.samples_json,
                        segments_json = excluded.segments_json,
                        source = excluded.source,
                        fetched_at = excluded.fetched_at
                    """,
                arguments: [sessionId, samplesJSON, segmentsJSON, source, fetchedAt]
            )
        }
    }

    func writeHevyDecision(sessionId: String, _ decision: String) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO session_telemetry (session_id, hevy_decision) VALUES (?, ?)
                    ON CONFLICT(session_id) DO UPDATE SET hevy_decision = excluded.hevy_decision
                    """,
                arguments: [sessionId, decision]
            )
        }
    }
}
