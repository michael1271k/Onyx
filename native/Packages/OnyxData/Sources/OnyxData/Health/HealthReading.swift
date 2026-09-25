import Foundation
import OnyxCore

/// The device's Health database, as the ingest needs it.
///
/// A protocol for the same reason `SyncRemote` is one: every interesting case —
/// a metric this device does not record, a night split across two sources, a
/// permission that was never granted — is a case about the store's behaviour,
/// and none of them are reproducible against a real `HKHealthStore` in a test.
public protocol HealthReading: Sendable {
    /// True when Health data exists on this device at all (false on a Mac and
    /// in every test).
    var isAvailable: Bool { get }

    /// Ask once, for `HealthCatalogue.readTypes`.
    ///
    /// HealthKit never reports WHICH types were granted — by design, so an app
    /// cannot infer a diagnosis from a refusal. So this answers only whether the
    /// sheet completed, and a denied type is indistinguishable from a metric the
    /// device does not record: both read as absent.
    func requestAuthorization(read: [String]) async throws -> Bool

    /// One already-reduced value for a quantity type over `[start, end)`.
    ///
    /// Reduced by HealthKit rather than in Swift, deliberately: a statistics
    /// query deduplicates overlapping iPhone and Watch samples the way Apple's
    /// own Health app does. Summing the raw samples here would double-count
    /// every minute both devices recorded.
    func quantity(
        _ identifier: String, reduce: HealthReduce, start: Date, end: Date
    ) async throws -> Double?

    /// The same sum, BROKEN DOWN BY THE APP THAT WROTE IT.
    ///
    /// ── WHY THIS EXISTS ─────────────────────────────────────────────────────
    /// `nutrition_entries.micros` stores a daily AGGREGATE with no item
    /// breakdown, so when calcium arrived at 3,074 mg on seventeen days — about
    /// ten times the other days, with calories and sodium normal throughout —
    /// nothing downstream could say which app had written it. The export could
    /// only doubt the number; it could not help anyone fix it.
    ///
    /// `HKStatisticsOptions.separateBySource` answers it in the SAME query the
    /// total already runs, at no extra cost: one pass, and `sumQuantity(for:)`
    /// per source.
    ///
    /// DECLARED HERE, not only in an extension. A method that exists solely in
    /// a protocol extension is dispatched STATICALLY, so a call through
    /// `any HealthReading` would run the default and never reach the conformer
    /// that overrode it — silently, with a green build. That trap has cost this
    /// codebase a wave already (`SyncRemote.upsertSetEvents`).
    func quantityBySource(
        _ identifier: String, start: Date, end: Date
    ) async throws -> [String: Double]

    /// Raw sleep-category samples in a window. Not reduced: the stage union in
    /// `Sleep.aggregate` needs the individual intervals.
    func sleepSamples(start: Date, end: Date) async throws -> [SleepSample]

    /// Workouts OVERLAPPING `[start, end]` — the watch's own record of a
    /// session, whose interval is where a measured heart rate and energy come
    /// from. Overlap, not containment: the watch is started a minute after the
    /// first set and stopped a minute before the last.
    func workouts(start: Date, end: Date) async throws -> [WorkoutSample]

    /// Heart-rate readings in `[start, end]`, oldest first, from sources the
    /// app may cite: its own workouts and Apple's sensors. A foreign app's
    /// samples (a Hevy that writes its own bpm) are left out — the same rule
    /// `workouts` applies through `WorkoutProvenance`, one level down.
    /// Expansion W5. Declared here, not only in an extension, for the reason
    /// `quantityBySource` gives.
    func heartRateSeries(start: Date, end: Date) async throws -> [HRSample]

    /// Fires once per change to the heart-rate store until `until`, then
    /// finishes. The late-sample window after a finish: the watch's samples
    /// reach the phone's store minutes after the workout ends, and a view
    /// that read too early would otherwise stay empty until the next open.
    func heartRateChanges(until: Date) -> AsyncStream<Void>
}

public extension HealthReading {
    /// No breakdown. The honest default for a test double and for any reader
    /// that predates the question — an empty map means "not attributed", which
    /// is what the callers already handle.
    func quantityBySource(
        _ identifier: String, start: Date, end: Date
    ) async throws -> [String: Double] { [:] }

    /// A store that records no workouts — every test double, and any device
    /// without a watch.
    func workouts(start: Date, end: Date) async throws -> [WorkoutSample] { [] }

    /// No series — every test double, and any device without a sensor.
    func heartRateSeries(start: Date, end: Date) async throws -> [HRSample] { [] }

    /// Nothing ever changes; the stream finishes at once.
    func heartRateChanges(until: Date) -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    /// The lifting workout that overlaps a session, classified.
    ///
    /// ONE read for three callers — `SessionMetrics`, the Hevy compare card
    /// and the phone's `WorkoutWriter` guard — so they cannot disagree about
    /// which workout is the session's. The window carries
    /// `WorkoutProvenance.overlapSlack` on both ends, and `pick` applies the
    /// same slack again, so a workout the query returns is one the rule
    /// accepts. An extension-only method on purpose: it composes `workouts`
    /// and nothing overrides it.
    func liftingOverlap(start: Date, end: Date, ownBundleId: String) async -> WorkoutOverlap {
        let slack = WorkoutProvenance.overlapSlack
        let found = (try? await workouts(
            start: start.addingTimeInterval(-slack), end: end.addingTimeInterval(slack)
        )) ?? []
        let candidates = found.map {
            WorkoutProvenance.Candidate(
                origin: $0.origin(ownBundleId: ownBundleId), isLifting: $0.isLifting, start: $0.start, end: $0.end
            )
        }
        switch WorkoutProvenance.pick(candidates, sessionStart: start, sessionEnd: end) {
        case .own(let i): return .own(found[i])
        case .foreign(let i): return .foreign(found[i])
        case .none: return .none
        }
    }

}

/// One `HKWorkout`, reduced to what `SessionMetrics` and the cardio import need.
///
/// ── WHY THIS GREW RATHER THAN THE PROTOCOL ──────────────────────────────────
/// The cardio import wants a bout's distance, energy, heart rate and ascent.
/// A second protocol method would have been the obvious place and would have
/// had to be written five times — `HealthKitReader`, `NoHealth`, and three test
/// doubles that care about none of it. Widening the VALUE the one existing
/// method already returns costs those five nothing: every field is optional,
/// the initialiser defaults them, and a double that constructs a sample the old
/// way still compiles and still means what it meant.
public struct WorkoutSample: Sendable, Equatable {
    /// `HKWorkout.uuid` — Apple's own identity for this bout.
    ///
    /// The one stable key this feature ever had and did not read. Without it
    /// the ingest asks "is this the walk you already have" of a table with no
    /// start column, and answers with a five-minute window over `created_at` —
    /// which misses whenever `created_at` did not survive the round trip, and
    /// re-inserts. `WeeklyExportBuilder` documents the cost in its own header:
    /// twenty-three copies of one walk.
    ///
    /// Defaulted in the initialiser so the five constructors that predate it —
    /// `NoHealth` and the test doubles — still compile and still mean what they
    /// meant. A fresh uuid per constructed sample is the right default for a
    /// double: two samples built separately are two bouts.
    public var uuid: UUID
    public var start: Date
    public var end: Date
    /// Traditional or functional strength training. Decided by the reader,
    /// which is the only place that can name an `HKWorkoutActivityType`.
    public var isLifting: Bool
    /// The `cardio_logs.kind` this bout would be filed under, or nil when it is
    /// an activity the app does not offer. Also decided by the reader, for the
    /// same reason `isLifting` is: `HKWorkoutActivityType` cannot be named
    /// anywhere else.
    public var cardioKind: String?
    public var distanceM: Double?
    public var activeKcal: Double?
    public var avgHr: Double?
    /// Metres climbed, from the workout's metadata
    /// (`HKMetadataKeyElevationAscended`) rather than a sample type.
    ///
    /// It used to say here that this was display-only because `cardio_logs` had
    /// no column. W2 added `elevation_m` and W5 writes it: an ascent is most of
    /// what separates a hard walk from an easy one, and throwing it away meant
    /// the ledger could not tell them apart a month later.
    public var elevationM: Double?
    /// `HKSource.bundleIdentifier` of the app that wrote it (Expansion W5).
    ///
    /// The provenance filter: `WorkoutProvenance.origin` reads this against the
    /// app's own bundle id, and a workout whose source is not ours is never
    /// adopted as the session's measurement. Nil only from a double that did
    /// not fill it in — and nil classifies as FOREIGN, never own.
    public var sourceBundleId: String?
    /// `HKSource.name` — what Health shows for the writer ("Hevy").
    public var sourceName: String?
    /// A set count the WRITER stamped in the workout's metadata, if any. Only
    /// a foreign app would (Onyx keeps its sets in `workout_sets`); best
    /// effort, for the compare card's fourth row, and nil is the usual answer.
    public var sets: Int?
    /// The workout's energy was stamped `app.onyx.estimated` by the phone's
    /// own writer — `Estimates`' number, put in Health so the rings have
    /// something. `SessionMetrics` must not read it back as a measurement,
    /// or an estimate launders itself into the sample that justifies the
    /// next one.
    public var energyEstimated: Bool

    public init(
        uuid: UUID = UUID(),
        start: Date,
        end: Date,
        isLifting: Bool,
        cardioKind: String? = nil,
        distanceM: Double? = nil,
        activeKcal: Double? = nil,
        avgHr: Double? = nil,
        elevationM: Double? = nil,
        sourceBundleId: String? = nil,
        sourceName: String? = nil,
        sets: Int? = nil,
        energyEstimated: Bool = false
    ) {
        self.uuid = uuid
        self.start = start
        self.end = end
        self.isLifting = isLifting
        self.cardioKind = cardioKind
        self.distanceM = distanceM
        self.activeKcal = activeKcal
        self.avgHr = avgHr
        self.elevationM = elevationM
        self.sourceBundleId = sourceBundleId
        self.sourceName = sourceName
        self.sets = sets
        self.energyEstimated = energyEstimated
    }

    /// Whose it is, against this app's bundle id.
    public func origin(ownBundleId: String) -> WorkoutOrigin {
        WorkoutProvenance.origin(sourceBundleId: sourceBundleId, sourceName: sourceName, ownBundleId: ownBundleId)
    }

    /// Wall-clock minutes. The bout's own duration, not its active time — the
    /// figure a person recognises when they compare it to what their watch said.
    public var durationMin: Double { end.timeIntervalSince(start) / 60 }
}

/// `HealthReading.liftingOverlap`'s answer.
public enum WorkoutOverlap: Sendable, Equatable {
    /// Our own record of the session — measured figures.
    case own(WorkoutSample)
    /// Somebody else's (Hevy). Offered on a card; never adopted silently.
    case foreign(WorkoutSample)
    case none

    public var own: WorkoutSample? { if case .own(let w) = self { w } else { nil } }
    public var foreign: WorkoutSample? { if case .foreign(let w) = self { w } else { nil } }
}

/// The four body figures Apple Health can offer a weigh-in form, as of now.
///
/// One value rather than four calls because the sheet wants them together: a
/// prefill that filled weight and left body fat blank reads as "Health has no
/// body fat" when it means "that half of the read failed". Each field is
/// independently optional INSIDE the answer, which is the honest shape.
public struct HealthBodyReading: Sendable, Equatable {
    public var weightKg: Double?
    public var bmi: Double?
    /// Whole percent, already scaled — HealthKit's own unit is a 0–1 fraction.
    public var bodyFatPct: Double?
    /// FAT-FREE mass, which is what HealthKit's `leanBodyMass` actually is.
    /// It is NOT skeletal muscle mass and must never be written as it.
    public var fatFreeMassKg: Double?

    public init(
        weightKg: Double? = nil, bmi: Double? = nil,
        bodyFatPct: Double? = nil, fatFreeMassKg: Double? = nil
    ) {
        self.weightKg = weightKg; self.bmi = bmi
        self.bodyFatPct = bodyFatPct; self.fatFreeMassKg = fatFreeMassKg
    }

    /// Nothing to offer. The sheet hides its Health row rather than showing a
    /// button that fills four dashes.
    public var isEmpty: Bool { self == HealthBodyReading() }
}
