import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Sessions — the draft's pure functions, RPE memory, next set, previous-set
// alignment, live PRs, estimates, elapsed time and the rest clock — replayed
// from `npm run golden`.
// ─────────────────────────────────────────────────────────────────────────────

/// The exporter's `PatchSpec`: `rpe: null` / `setType: null` mean present-and-undefined.
struct PatchSpec: Decodable {
    let patch: SetPatch
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        patch = SetPatch(
            weightKg: try c.decodeIfPresent(Double.self, forKey: .weightKg),
            reps: try c.decodeIfPresent(Double.self, forKey: .reps),
            rpe: c.contains(.rpe) ? .some(try c.decodeIfPresent(Double.self, forKey: .rpe)) : nil,
            setType: c.contains(.setType) ? .some(try c.decodeIfPresent(String.self, forKey: .setType)) : nil,
            done: try c.decodeIfPresent(Bool.self, forKey: .done),
            quality: try c.decodeIfPresent(String.self, forKey: .quality)
        )
    }
    enum Keys: CodingKey { case weightKg, reps, rpe, setType, done, quality }
}

@Suite("RPE memory")
struct RpeMemoryGoldenTests {
    struct SeedIn: Decodable { let seed: RpeSeed?; let weightKg: Double; let reps: Double }
    struct SeedOut: Decodable { let rpe: Double?; let stale: Bool }

    @Test("resolveSeededRpe matches")
    func seedMatches() throws {
        for c in try GoldenFixture<SeedIn, SeedOut>.load("rpe-seed").cases {
            let r = RpeMemory.resolveSeededRpe(c.input.seed, weightKg: c.input.weightKg, reps: c.input.reps)
            expectClose(r.rpe, c.expected.rpe, "rpe — \(c.name)")
            #expect(r.stale == c.expected.stale, "stale — \(c.name)")
        }
    }

    struct SetsIn: Decodable { let sets: [RatedSet] }

    @Test("deriveSessionRpe matches")
    func sessionRpeMatches() throws {
        for c in try GoldenFixture<SetsIn, Double?>.load("session-rpe").cases {
            expectClose(RpeMemory.deriveSessionRpe(c.input.sets), c.expected, "deriveSessionRpe — \(c.name)")
        }
    }
}

@Suite("Session draft — the pure functions")
struct DraftGoldenTests {
    struct PatchIn: Decodable { let set: DraftSet; let patch: PatchSpec }

    @Test("applySetPatch matches — seed release and the failure tag")
    func patchMatches() throws {
        for c in try GoldenFixture<PatchIn, DraftSet>.load("set-patch").cases {
            #expect(Draft.applySetPatch(c.input.set, c.input.patch.patch) == c.expected, "applySetPatch — \(c.name)")
        }
    }

    struct CascadeIn: Decodable { let sets: [DraftSet]; let setIdx: Int; let patch: PatchSpec }

    @Test("cascadeSetEdit matches — one step, then memory over the whole list")
    func cascadeMatches() throws {
        for c in try GoldenFixture<CascadeIn, [DraftSet]>.load("cascade-set-edit").cases {
            #expect(Draft.cascadeSetEdit(c.input.sets, setIdx: c.input.setIdx, patch: c.input.patch.patch) == c.expected, "cascadeSetEdit — \(c.name)")
        }
    }

    struct TotIn: Decodable { let draft: SessionDraft; let cap: Int }
    struct TotOut: Decodable { let volumeKg: Double; let sets: Int; let series: [Double] }

    @Test("draftTotals and draftVolumeSeries match")
    func totalsMatch() throws {
        for c in try GoldenFixture<TotIn, TotOut>.load("draft-totals").cases {
            let t = Draft.totals(c.input.draft)
            expectClose(t.volumeKg, c.expected.volumeKg, "volumeKg — \(c.name)")
            #expect(t.sets == c.expected.sets, "sets — \(c.name)")
            #expect(Draft.volumeSeries(c.input.draft, cap: c.input.cap) == c.expected.series, "series — \(c.name)")
        }
    }

    struct PairIn: Decodable { let l: DraftSet?; let r: DraftSet? }
    struct PairOut: Decodable { let compactable: Bool; let asymmetry: PairAsymmetry? }

    @Test("isPairCompactable and pairAsymmetry match")
    func pairMatches() throws {
        for c in try GoldenFixture<PairIn, PairOut>.load("pair-row").cases {
            #expect(Draft.isPairCompactable(c.input.l, c.input.r) == c.expected.compactable, "isPairCompactable — \(c.name)")
            #expect(Draft.pairAsymmetry(c.input.l, c.input.r) == c.expected.asymmetry, "pairAsymmetry — \(c.name)")
        }
    }

    struct ExIn: Decodable { let ex: DraftExercise }

    @Test("cardioSummary matches")
    func cardioMatches() throws {
        for c in try GoldenFixture<ExIn, String>.load("cardio-summary").cases {
            #expect(Draft.cardioSummary(c.input.ex) == c.expected, "cardioSummary — \(c.name)")
        }
    }

    struct TitleIn: Decodable { let title: String?; let dayKey: String?; let splitDay: String }

    @Test("cleanSessionTitle matches")
    func titleMatches() throws {
        for c in try GoldenFixture<TitleIn, String>.load("clean-title").cases {
            #expect(Draft.cleanTitle(title: c.input.title, dayKey: c.input.dayKey, splitDay: c.input.splitDay, program: FounderTables.deck) == c.expected, "cleanSessionTitle — \(c.name)")
        }
    }
}

@Suite("Next set and previous alignment")
struct NextSetGoldenTests {
    struct Named: Decodable { let name: String; let history: ExerciseHistory }
    struct NextIn: Decodable { let draft: SessionDraft?; let history: [Named]? }
    struct NextOut: Decodable { let next: NextSet?; let lastTime: String; let lastRpe: String; let load: String; let rpe: String }

    @Test("findNextSet and its strings match")
    func nextMatches() throws {
        for c in try GoldenFixture<NextIn, NextOut>.load("next-set").cases {
            let history = c.input.history.map { Dictionary($0.map { ($0.name, $0.history) }, uniquingKeysWith: { _, last in last }) }
            let next = NextSetFinder.find(c.input.draft, history: history)
            #expect(next == c.expected.next, "findNextSet — \(c.name)")
            #expect(NextSetFinder.formatLastTime(next) == c.expected.lastTime, "formatLastTime — \(c.name)")
            #expect(NextSetFinder.formatLastRpe(next) == c.expected.lastRpe, "formatLastRpe — \(c.name)")
            #expect(NextSetFinder.formatLoad(next) == c.expected.load, "formatLoad — \(c.name)")
            #expect(NextSetFinder.formatRpe(next) == c.expected.rpe, "formatRpe — \(c.name)")
        }
    }

    struct FmtIn: Decodable { let w: Double?; let r: Double?; let rpe: Double? }
    struct FmtOut: Decodable { let lastTime: String; let lastRpe: String; let load: String; let rpe: String }

    @Test("the four strings match on every load shape")
    func formatsMatch() throws {
        for c in try GoldenFixture<FmtIn, FmtOut>.load("next-set-format").cases {
            let n = NextSet(exercise: "X", setNumber: 1, setTotal: 1, lastWeightKg: c.input.w, lastReps: c.input.r, lastRpe: c.input.rpe, weightKg: c.input.w, reps: c.input.r, rpe: c.input.rpe)
            #expect(NextSetFinder.formatLastTime(n) == c.expected.lastTime, "formatLastTime — \(c.name)")
            #expect(NextSetFinder.formatLastRpe(n) == c.expected.lastRpe, "formatLastRpe — \(c.name)")
            #expect(NextSetFinder.formatLoad(n) == c.expected.load, "formatLoad — \(c.name)")
            #expect(NextSetFinder.formatRpe(n) == c.expected.rpe, "formatRpe — \(c.name)")
        }
    }

    struct AlignIn: Decodable { let todayWarmup: [Bool]; let previous: [HistorySet]? }
    struct AlignOut: Decodable { let rows: [HistorySet]; let aligned: [HistorySet?] }

    @Test("previousDisplayRows and alignPreviousSets match")
    func alignMatches() throws {
        for c in try GoldenFixture<AlignIn, AlignOut>.load("prev-align").cases {
            #expect(PrevAlign.previousDisplayRows(c.input.previous) == c.expected.rows, "previousDisplayRows — \(c.name)")
            #expect(PrevAlign.alignPreviousSets(todayWarmup: c.input.todayWarmup, previous: c.input.previous) == c.expected.aligned, "alignPreviousSets — \(c.name)")
        }
    }

    struct NameIn: Decodable { let name: String? }

    @Test("isTimedExercise matches")
    func timedMatches() throws {
        for c in try GoldenFixture<NameIn, Bool>.load("timed-exercise").cases {
            #expect(TimedExercise.isTimed(c.input.name) == c.expected, "isTimedExercise — \(c.name)")
        }
    }
}

@Suite("Live PRs")
struct LivePrsGoldenTests {
    struct In: Decodable { let draft: SessionDraft?; let baselines: PrBaselines? }
    struct Entry: Decodable { let key: String; let axes: [PrAxis] }
    struct Detail: Decodable { let key: String; let records: [String: AxisRecord] }
    struct Out: Decodable { let digest: String; let bySet: [Entry]; let detail: [Detail]; let count: Int }

    @Test("livePrDigest and computeLivePrs match")
    func liveMatches() throws {
        for c in try GoldenFixture<In, Out>.load("live-prs").cases {
            // The asserted record book (`PrSeed`) is rows now; see PrGoldenTests.
            if c.name.contains("asserted date") { continue }
            #expect(LivePrEngine.digest(c.input.draft) == c.expected.digest, "digest — \(c.name)")
            let r = LivePrEngine.compute(c.input.draft, baselines: c.input.baselines)
            #expect(r.count == c.expected.count, "count — \(c.name)")
            #expect(r.bySet.map(\.key) == c.expected.bySet.map(\.key), "bySet keys — \(c.name)")
            #expect(r.bySet.map(\.axes) == c.expected.bySet.map(\.axes), "bySet axes — \(c.name)")
            #expect(r.detailBySet.map(\.key) == c.expected.detail.map(\.key), "detail keys — \(c.name)")
            for (a, e) in zip(r.detailBySet, c.expected.detail) {
                // The e1RM record's VALUE moved with the formula (Brzycki,
                // 2026-09-15) and is exempt for the reason `PrGoldenTests`
                // gives at length. Which axes fire, and on which sets, is
                // asserted in full above — `bySet.axes` is not filtered.
                let records = Dictionary(uniqueKeysWithValues:
                    a.records.filter { $0.key != .e1rm }.map { ($0.key.rawValue, $0.value) })
                #expect(records == e.records.filter { $0.key != PrAxis.e1rm.rawValue }, "detail records — \(c.name)")
            }
        }
    }
}

@Suite("Estimates")
struct EstimatesGoldenTests {
    struct BwIn: Decodable { let bodyweightKg: Double? }
    struct SamplesIn: Decodable { let samples: [KcalSample] }
    struct EstIn: Decodable { let durationMin: Double?; let samples: [KcalSample]; let bodyweightKg: Double? }
    struct BpmIn: Decodable { let previousBpm: Double? }

    @Test("every estimate matches")
    func estimatesMatch() throws {
        for c in try GoldenFixture<BwIn, Double?>.load("met-kcal-per-min").cases {
            expectClose(Estimates.metKcalPerMin(bodyweightKg: c.input.bodyweightKg), c.expected, "metKcalPerMin — \(c.name)")
        }
        for c in try GoldenFixture<SamplesIn, Double?>.load("kcal-median").cases {
            expectClose(Estimates.medianKcalPerMin(c.input.samples), c.expected, "medianKcalPerMin — \(c.name)")
        }
        for c in try GoldenFixture<EstIn, CalorieEstimate?>.load("calorie-estimate").cases {
            #expect(Estimates.estimateCalories(durationMin: c.input.durationMin, samples: c.input.samples, bodyweightKg: c.input.bodyweightKg) == c.expected, "estimateCalories — \(c.name)")
        }
        for c in try GoldenFixture<BpmIn, Double?>.load("bpm-estimate").cases {
            expectClose(Estimates.estimateAvgBpm(previousBpm: c.input.previousBpm), c.expected, "estimateAvgBpm — \(c.name)")
        }
    }
}

@Suite("Session elapsed and the rest clock")
struct ClockGoldenTests {
    struct ElapsedIn: Decodable { let startedAt: String?; let now: Double; let pause: SessionPause? }
    struct ElapsedOut: Decodable { let elapsed: Double?; let active: Double?; let durationMin: Double?; let pausedMs: Double }

    @Test("elapsed, active, duration and paused arithmetic match")
    func elapsedMatches() throws {
        for c in try GoldenFixture<ElapsedIn, ElapsedOut>.load("session-elapsed").cases {
            let i = c.input
            let active = SessionElapsed.activeSec(startedAt: i.startedAt, now: i.now, pause: i.pause)
            expectClose(SessionElapsed.elapsedSec(startedAt: i.startedAt, now: i.now), c.expected.elapsed, "elapsed — \(c.name)")
            expectClose(active, c.expected.active, "active — \(c.name)")
            expectClose(SessionElapsed.durationMin(active), c.expected.durationMin, "durationMin — \(c.name)")
            expectClose(SessionElapsed.pausedMs(i.pause, now: i.now), c.expected.pausedMs, "pausedMs — \(c.name)")
        }
    }

    struct ParseIn: Decodable { let raw: String?; let now: Double }

    @Test("the stored row reads the same, staleness included")
    func parseMatches() throws {
        for c in try GoldenFixture<ParseIn, SessionClock>.load("session-clock-parse").cases {
            #expect(Clock.read(c.input.raw, now: c.input.now) == c.expected, "getSessionClock — \(c.name)")
        }
    }

    struct ReadIn: Decodable { let clock: SessionClock; let now: Double }
    struct ReadOut: Decodable { let elapsedMs: Double; let elapsedSec: Double; let remainingSec: Double; let done: Bool; let reading: Double; let live: Bool }

    @Test("every reading matches")
    func readingsMatch() throws {
        for c in try GoldenFixture<ReadIn, ReadOut>.load("session-clock-read").cases {
            let (k, now) = (c.input.clock, c.input.now)
            expectClose(Clock.elapsedMs(k, now: now), c.expected.elapsedMs, "elapsedMs — \(c.name)")
            expectClose(Clock.elapsedSec(k, now: now), c.expected.elapsedSec, "elapsedSec — \(c.name)")
            expectClose(Clock.remainingSec(k, now: now), c.expected.remainingSec, "remainingSec — \(c.name)")
            #expect(Clock.isTimerDone(k, now: now) == c.expected.done, "isTimerDone — \(c.name)")
            expectClose(Clock.readingSec(k, now: now), c.expected.reading, "clockReadingSec — \(c.name)")
            #expect(Clock.isLive(k) == c.expected.live, "clockIsLive — \(c.name)")
        }
    }

    struct Op: Decodable { let kind: String; let mode: ClockMode?; let sec: Double? }
    struct OpIn: Decodable { let clock: SessionClock; let op: Op; let now: Double }

    @Test("every transition matches the store, step for step")
    func opsMatch() throws {
        for c in try GoldenFixture<OpIn, SessionClock>.load("session-clock-ops").cases {
            let now = c.input.now
            let k = Clock.settle(c.input.clock, now: now)
            let out: SessionClock
            switch c.input.op.kind {
            case "setMode": out = Clock.setMode(k, c.input.op.mode!)
            case "start": out = Clock.start(k, mode: c.input.op.mode, now: now)
            case "pause": out = Clock.pause(k, now: now)
            case "reset": out = Clock.reset(k)
            case "restart": out = Clock.restart(k, now: now)
            case "setDuration": out = Clock.setDuration(k, c.input.op.sec!)
            default: Issue.record("unknown op \(c.input.op.kind)"); continue
            }
            #expect(Clock.settle(out, now: now) == c.expected, "\(c.input.op.kind) — \(c.name)")
        }
    }

    struct SecIn: Decodable { let sec: Double }
    struct FmtOut: Decodable { let formatted: String; let clamped: Double }

    @Test("formatClock and clampDuration match")
    func formatMatches() throws {
        for c in try GoldenFixture<SecIn, FmtOut>.load("clock-format").cases {
            #expect(Clock.format(c.input.sec) == c.expected.formatted, "formatClock — \(c.name)")
            expectClose(Clock.clampDuration(c.input.sec), c.expected.clamped, "clampDuration — \(c.name)")
        }
    }

    @Test("Date.parse parity — exact milliseconds, offsets, date-only, garbage")
    func parseMillis() {
        #expect(ISODate.parseMillis("2026-08-28T12:00:00.594Z") == 1787918400594)
        #expect(ISODate.parseMillis("2026-08-28T14:00:00.000+02:00") == 1787918400000)
        #expect(ISODate.parseMillis("2026-08-28T12:00:00Z") == 1787918400000)
        #expect(ISODate.parseMillis("2026-08-28") == 1787875200000)
        #expect(ISODate.parseMillis("not a date") == nil)
        #expect(ISODate.parseMillis("") == nil)
        #expect(jsToFixed(12.125, 2) == "12.13")
        #expect(jsToFixed(1e-7, 2) == "0.00")
        #expect(jsToFixed(3.333, 2) == "3.33")
        #expect(jsToFixed(60, 0) == "60")
        #expect(jsToFixed(-0.001, 2) == "-0.00")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The session seed (P3 E4) — the three tiers, and the session list they and
// `ProgressionQueue` share.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Session seed")
struct SessionSeedGoldenTests {
    struct SeedIn: Decodable {
        let dayKey: String
        let today: String
        let phase: ProgramPhase
        let sessions: [SeedSession]
        let sets: [SeedSet]
        let template: SeedTemplate?
        let ready: [SeedProgression]?
        let programId: String?
    }

    struct ListIn: Decodable { let sessions: [SeedSession]; let dayKey: String; let today: String }

    @Test("buildSessionSeed matches — every tier, every filter")
    func seedMatches() throws {
        let fixture = try GoldenFixture<SeedIn, SessionSeed>.load("session-seed")
        #expect(fixture.cases.count > 20)
        for c in fixture.cases {
            // The vector names the program by id; the deck is the founder's
            // Onyx-5 rows (`program-onyx5.json` holds them to the vector's shape).
            #expect(c.input.programId == nil || c.input.programId == FounderTables.deck.id, "program — \(c.name)")
            let seed = SessionSeedBuilder.build(
                dayKey: c.input.dayKey, today: c.input.today, phase: c.input.phase,
                sessions: c.input.sessions, sets: c.input.sets,
                template: c.input.template, ready: c.input.ready ?? [],
                program: FounderTables.deck, planOwning: FounderTables.planOwning
            )
            #expect(seed == c.expected, "sessionSeed — \(c.name)")
        }
    }

    @Test("sessionsForSeed matches — the list the verdict and the seed share")
    func listMatches() throws {
        for c in try GoldenFixture<ListIn, [SeedSession]>.load("sessions-for-seed").cases {
            let got = SessionSeedBuilder.sessionsForSeed(
                c.input.sessions, dayKey: c.input.dayKey, today: c.input.today, planOwning: FounderTables.planOwning
            )
            #expect(got == c.expected, "sessionsForSeed — \(c.name)")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session duration (P3 E4) — the rule the 385-minute session was missing.
// ─────────────────────────────────────────────────────────────────────────────

@Suite("Session duration")
struct SessionDurationGoldenTests {
    struct DurIn: Decodable {
        let startedAt: String
        let endedAt: String
        let pausedSec: Double
        let pausedBeforeLastSetSec: Double
        let lastSetAt: String?
        let restTargetSec: Double?
    }

    /// `Date.parse` in JavaScript, for the instants the vector carries. An
    /// unparseable string is nil on both sides.
    static func parse(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    @Test("sessionDuration matches — the pause comes off and a long idle is not training")
    func matches() throws {
        let fixture = try GoldenFixture<DurIn, SessionDurationResult>.load("session-duration")
        #expect(fixture.cases.count > 100)
        for c in fixture.cases {
            let got = SessionDuration.compute(
                startedAt: Self.parse(c.input.startedAt),
                endedAt: Self.parse(c.input.endedAt),
                pausedSec: c.input.pausedSec,
                pausedBeforeLastSetSec: c.input.pausedBeforeLastSetSec,
                lastSetAt: c.input.lastSetAt.flatMap(Self.parse),
                restTargetSec: c.input.restTargetSec
            )
            expectClose(got.minutes, c.expected.minutes, "minutes — \(c.name)")
            expectClose(got.pausedMin, c.expected.pausedMin, "pausedMin — \(c.name)")
            expectClose(got.idleMin, c.expected.idleMin, "idleMin — \(c.name)")
            #expect(got.capped == c.expected.capped, "capped — \(c.name)")
        }
    }
}
