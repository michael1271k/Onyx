import Foundation
import OnyxCore
import Testing
@testable import OnyxData

/// The wire format between two devices running two different builds.
///
/// ── WHY THIS IS WORTH A TEST AND THE TRANSPORT IS NOT ───────────────────────
/// `WatchLink` is a delegate that hands dictionaries to `ingest`; every rule it
/// could get wrong belongs to `ingest`, and `WatchConvergenceTests` covers those
/// against a real store. What it CANNOT cover is the encoding, because the
/// framework only exists on iOS and watchOS and `swift test` runs on macOS.
///
/// The encoding is also the half that fails silently. A watch routinely runs an
/// older build than the phone it is paired to, so a renamed key does not throw
/// anywhere — the context simply stops arriving, the watch shows "Open Onyx on
/// your iPhone" forever, and nothing in either app says why.
@Suite("Watch payloads")
struct WatchPayloadTests {

    private let schedule = ScheduleContext(
        programId: "onyx5",
        phase: .cut,
        overrides: ["2026-09-09": "legs_a", "2026-09-10": Schedule.restOverride],
        layout: ["cb_a": 1, "legs_a": 2]
    )

    @Test("a context survives the round trip with its overrides and layout intact")
    func contextRoundTrips() throws {
        let sent = WatchContext(userId: "u-1", today: "2026-09-08", schedule: schedule)
        let data = try OnyxJSON.encoder.encode(sent)
        let back = try OnyxJSON.decoder.decode(WatchContext.self, from: data)
        #expect(back == sent)
        // The two fields a schedule cannot answer, and the reason this type
        // exists rather than sending a bare `ScheduleContext`.
        #expect(back.userId == "u-1")
        #expect(back.today == "2026-09-08")
    }

    /// The context is what lets the watch name today's split with no network at
    /// all: `Program.onyx5` is compiled into `OnyxCore`, so a decoded context is
    /// a whole deck.
    @Test("a decoded context still resolves the day, offline")
    func contextResolvesADay() throws {
        let sent = WatchContext(userId: "u-1", today: "2026-09-08", schedule: schedule)
        let back = try OnyxJSON.decoder.decode(
            WatchContext.self, from: try OnyxJSON.encoder.encode(sent)
        )
        let here = Schedule.scheduleDayIn(back.schedule, back.today)
        let there = Schedule.scheduleDayIn(sent.schedule, sent.today)
        #expect(here?.dayKey == there?.dayKey)
    }

    /// ── AN INSTANT, NEVER A DURATION ────────────────────────────────────────
    /// A remaining-seconds payload decays in transit and again while the
    /// receiving app is suspended, so it arrives already wrong and drifts
    /// further every time the watch sleeps. An end instant is correct whenever
    /// it is read, which is what lets `Text(timerInterval:)` be counted by the
    /// system rather than by a timer in the view tree.
    @Test("a rest pulse carries an end instant that survives the encoder")
    func restPulseRoundTrips() throws {
        // Whole seconds: ISO-8601 does not carry sub-second precision, and a
        // test that asserted it would fail for a reason that does not matter.
        let endsAt = Date(timeIntervalSince1970: 1_790_000_000)
        let sent = RestPulse(sessionId: "s-1", endsAt: endsAt, duration: 120, exercise: "Hack Squat")
        let back = try OnyxJSON.decoder.decode(
            RestPulse.self, from: try OnyxJSON.encoder.encode(sent)
        )
        #expect(back == sent)
        #expect(back.endsAt == endsAt)
    }

    /// `.fullScreenCover(item:)` re-presents when the identity changes, and
    /// adding 15 seconds has to restart the countdown task rather than leave the
    /// old one running against a moved target.
    @Test("adjusting a rest pulse gives it a new identity")
    func restPulseIdentityFollowsTheClock() {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        let first = RestPulse(sessionId: "s-1", endsAt: base, duration: 120)
        let extended = RestPulse(sessionId: "s-1", endsAt: base.addingTimeInterval(15), duration: 120)
        #expect(first.id != extended.id)
    }

    /// The event array is what `transferUserInfo` carries, and it crosses the
    /// same `OnyxJSON` pair. `SetEvent.Body`'s hand-written coding is the reason
    /// this holds — the synthesised one keys on declaration order, and a
    /// reordered case would make every queued transfer undecodable on the other
    /// wrist.
    @Test("a batch of events survives the transfer encoding")
    func eventsRoundTrip() throws {
        let events = [
            SetEvent(
                sessionId: "s-1", setId: "set-1", deviceId: "watch", seq: 7,
                body: .append(SetSnapshot(exerciseId: "onyx-hack-squat", setIndex: 1, weightKg: 102.5, reps: 8))
            ),
            SetEvent(
                sessionId: "s-1", setId: "set-1", deviceId: "watch", seq: 8,
                body: .amend(SetPatch(rpe: 8.5))
            ),
            SetEvent(sessionId: "s-1", setId: "set-2", deviceId: "watch", seq: 9, body: .void),
            SetEvent(sessionId: "s-1", setId: "s-1", deviceId: "watch", seq: 10, body: .pause),
        ]
        let back = try OnyxJSON.decoder.decode(
            [SetEvent].self, from: try OnyxJSON.encoder.encode(events)
        )
        #expect(back.map(\.id) == events.map(\.id))
        #expect(back.map(\.kind) == [.append, .amend, .void, .pause])
        guard case .append(let snapshot) = back[0].body else { return #expect(Bool(false)) }
        #expect(snapshot.weightKg == 102.5)
        guard case .amend(let patch) = back[1].body else { return #expect(Bool(false)) }
        #expect(patch.rpe == 8.5)
    }

    /// The payload-versioning story, in one test.
    ///
    /// `theme` is optional and last, so the synthesised `Codable` uses
    /// `decodeIfPresent`: an OLD phone's context (no `theme` key) decodes on a
    /// NEW watch as nil — which `WatchModel` reads as the default theme — and a
    /// NEW phone's context decodes on an OLD watch because an unknown key is
    /// ignored. That is why the field was added optional rather than with a
    /// non-optional default, which would have been the same wire but a decode
    /// that throws the day someone makes it non-optional.
    @Test("a context from a build that had no theme decodes with theme nil")
    func contextWithoutThemeDecodes() throws {
        let sent = WatchContext(userId: "u-1", today: "2026-09-08", schedule: schedule)
        var object = try #require(
            try JSONSerialization.jsonObject(
                with: try OnyxJSON.encoder.encode(sent)
            ) as? [String: Any]
        )
        #expect(object["theme"] == nil, "a nil theme must not be encoded at all")
        object.removeValue(forKey: "theme")

        let back = try OnyxJSON.decoder.decode(
            WatchContext.self, from: try JSONSerialization.data(withJSONObject: object)
        )
        #expect(back.theme == nil)
        #expect(back == sent)

        // And the other direction: a themed context round-trips its spec.
        var themed = sent
        themed.theme = OnyxThemeSpec(primary: 0xE07A5F, secondary: 0x5FB0E0)
        let there = try OnyxJSON.decoder.decode(
            WatchContext.self, from: try OnyxJSON.encoder.encode(themed)
        )
        #expect(there.theme == themed.theme)
    }

    /// The same story one field down (W7): `tiles` rides beside `theme`, and a
    /// phone from before the complications existed sends neither key.
    @Test("a context from a build that had no tiles decodes with tiles nil, and one with them round-trips")
    func contextWithoutTilesDecodes() throws {
        let sent = WatchContext(userId: "u-1", today: "2026-09-08", schedule: schedule)
        var object = try #require(
            try JSONSerialization.jsonObject(
                with: try OnyxJSON.encoder.encode(sent)
            ) as? [String: Any]
        )
        #expect(object["tiles"] == nil, "nil tiles must not be encoded at all")
        object.removeValue(forKey: "tiles")
        let back = try OnyxJSON.decoder.decode(
            WatchContext.self, from: try JSONSerialization.data(withJSONObject: object)
        )
        #expect(back.tiles == nil)
        #expect(back == sent)

        var tiled = sent
        tiled.tiles = WatchTiles(
            date: "2026-09-08", battery: 72, sleepMin: 445, waterMl: 1_750, waterGoalMl: 3_000,
            todayLabel: "Delts & Arms", todayLogged: false, restDay: false,
            week: [WatchTiles.WeekDay(trained: true, fuelHit: false, sleepHit: true)]
        )
        let there = try OnyxJSON.decoder.decode(
            WatchContext.self, from: try OnyxJSON.encoder.encode(tiled)
        )
        #expect(there.tiles == tiled.tiles)
        #expect(there == tiled)
    }

    /// The same story one payload down: `RestPulse` gained the set that earned
    /// the rest, the session's clock origin and the wrist's heart rate, and a
    /// phone that predates them sends none of the five keys.
    ///
    /// ── AND THIS ONE FAILS WORSE THAN THE CONTEXT ───────────────────────────
    /// A context that stops decoding leaves the watch saying "Open Onyx on your
    /// iPhone", which is at least a visible state. A rest pulse that stops
    /// decoding is dropped by `WatchLink.receive`'s `try?` and the rest cover
    /// simply never appears — no clock, no ladder, no haptic at zero, and the
    /// rating for every set goes unasked. Nothing anywhere says why.
    @Test("a rest pulse from a build with none of the five keys decodes with them nil")
    func restPulseWithoutTheSetDecodes() throws {
        let endsAt = Date(timeIntervalSince1970: 1_790_000_000)
        let full = RestPulse(
            sessionId: "s-1", endsAt: endsAt, duration: 150, exercise: "Hack Squat",
            loadKg: 102.5, reps: 8, rpe: 8.5, timerOrigin: endsAt.addingTimeInterval(-3_600),
            bpm: 141
        )
        var object = try #require(
            try JSONSerialization.jsonObject(
                with: try OnyxJSON.encoder.encode(full)
            ) as? [String: Any]
        )
        for key in ["loadKg", "reps", "rpe", "timerOrigin", "bpm"] { object.removeValue(forKey: key) }

        let back = try OnyxJSON.decoder.decode(
            RestPulse.self, from: try JSONSerialization.data(withJSONObject: object)
        )
        // What an old phone still says, intact.
        #expect(back.sessionId == "s-1")
        #expect(back.endsAt == endsAt)
        #expect(back.duration == 150)
        #expect(back.exercise == "Hack Squat")
        // And what it does not. Nil rather than zero: `loadKg` of 0 is a real
        // bodyweight set, and the rest screen has to tell the two apart.
        #expect(back.loadKg == nil)
        #expect(back.reps == nil)
        #expect(back.rpe == nil)
        #expect(back.timerOrigin == nil)
        // Nil rather than zero for the same reason, one reading further: a
        // `bpm` of 0 is a stopped heart and the deck would print it.
        #expect(back.bpm == nil)
        // Identity is still the clock, so `.fullScreenCover(item:)` behaves
        // exactly as it did before the four fields existed.
        #expect(back.id == endsAt)
    }

    /// The encode half, and the direction nobody thinks to check: a NEW phone
    /// with nothing to say must put the OLD payload on the wire, so an OLD
    /// watch is not asked for a key it has never heard of.
    @Test("a rest pulse with the five fields nil encodes exactly the old keys")
    func restPulseNilFieldsAreNotEncoded() throws {
        let sent = RestPulse(
            sessionId: "s-1", endsAt: Date(timeIntervalSince1970: 1_790_000_000),
            duration: 120, exercise: "Hack Squat"
        )
        let object = try #require(
            try JSONSerialization.jsonObject(
                with: try OnyxJSON.encoder.encode(sent)
            ) as? [String: Any]
        )
        #expect(
            object.keys.sorted() == ["duration", "endsAt", "exercise", "sessionId"],
            "a nil field must not be encoded at all — not as null, and not as a zero"
        )

        // And a full pulse round-trips every one of them, half rungs included:
        // 8.5 is a rung on `Effort.ladder` and 8 is a different one.
        var full = sent
        full.loadKg = 102.5
        full.reps = 8
        full.rpe = 8.5
        full.timerOrigin = sent.endsAt.addingTimeInterval(-3_600)
        full.bpm = 141
        let back = try OnyxJSON.decoder.decode(
            RestPulse.self, from: try OnyxJSON.encoder.encode(full)
        )
        #expect(back == full)
        #expect(back.rpe == 8.5)
        #expect(back.bpm == 141)
    }

    /// The direction `bpm` alone travels, and the one an old build must survive.
    ///
    /// ── WHY THIS IS NOT THE SAME TEST AS THE TWO ABOVE ──────────────────────
    /// The four fields before it are phone→watch and the watch reads them. The
    /// heart rate goes the other way: the WATCH puts it on the phone's own
    /// pulse and sends it straight back (`WatchModel.answerWithHeartRate`), and
    /// the phone takes the rate and ignores every other field on it
    /// (`PhoneWatchBridge.receive`). So the echo has to round-trip with the
    /// clock it was sent with UNCHANGED — if `endsAt` or `duration` moved in
    /// transit, a future phone that did read them would have its own countdown
    /// rewritten by the wrist's copy of it.
    @Test("the watch's heart-rate echo returns the phone's clock untouched")
    func heartRateEchoPreservesTheClock() throws {
        let endsAt = Date(timeIntervalSince1970: 1_790_000_000)
        let fromPhone = RestPulse(
            sessionId: "s-1", endsAt: endsAt, duration: 150, exercise: "Hack Squat",
            loadKg: 102.5, reps: 8, rpe: 8.5, timerOrigin: endsAt.addingTimeInterval(-3_600)
        )
        // What `answerWithHeartRate` does, exactly: the pulse it was handed,
        // with one field written.
        var echo = try OnyxJSON.decoder.decode(
            RestPulse.self, from: try OnyxJSON.encoder.encode(fromPhone)
        )
        echo.bpm = 141

        let back = try OnyxJSON.decoder.decode(
            RestPulse.self, from: try OnyxJSON.encoder.encode(echo)
        )
        #expect(back.bpm == 141)
        #expect(back.endsAt == fromPhone.endsAt)
        #expect(back.duration == fromPhone.duration)
        #expect(back.timerOrigin == fromPhone.timerOrigin)
        #expect(back.sessionId == fromPhone.sessionId)
        // Identity is still the clock, so an echo cannot re-present a cover.
        #expect(back.id == fromPhone.id)
    }

    // MARK: - Overhaul W0 contract: lifecycle, masthead, effort

    /// Whole seconds, per the project rule: `.iso8601` drops sub-seconds, so a
    /// fractional date would not round-trip equal.
    private static let start = Date(timeIntervalSince1970: 1_790_000_000)
    private static let masthead = SessionMasthead(
        name: "Upper A", durationSec: 3_120, tonnageKg: 8_450, avgBpm: 131, prCount: 2,
        hrSpark: [118, 126, 139, 144, 137, 122], startedAt: start
    )

    private func json<T: Encodable>(_ value: T) throws -> String {
        try #require(String(data: OnyxJSON.encoder.encode(value), encoding: .utf8))
    }

    @Test("SessionMasthead: golden JSON, and it round-trips")
    func mastheadGolden() throws {
        let golden = #"{"avgBpm":131,"durationSec":3120,"hrSpark":[118,126,139,144,137,122],"name":"Upper A","prCount":2,"startedAt":"2026-09-21T14:13:20Z","tonnageKg":8450}"#
        #expect(try json(Self.masthead) == golden)
        #expect(try OnyxJSON.decoder.decode(SessionMasthead.self, from: Data(golden.utf8)) == Self.masthead)
        // No HR: the key is absent, not null — and the spark is empty.
        var quiet = Self.masthead
        quiet.avgBpm = nil
        quiet.hrSpark = []
        #expect(try json(quiet) == #"{"durationSec":3120,"hrSpark":[],"name":"Upper A","prCount":2,"startedAt":"2026-09-21T14:13:20Z","tonnageKg":8450}"#)
    }

    @Test("SessionLifecycle: golden JSON for an open and a finish, and both round-trip")
    func lifecycleGolden() throws {
        let open = SessionLifecycle(sessionId: "s-1", phase: .open, startedAt: Self.start)
        #expect(try json(open) == #"{"phase":"open","sessionId":"s-1","startedAt":"2026-09-21T14:13:20Z"}"#)
        #expect(try OnyxJSON.decoder.decode(SessionLifecycle.self, from: OnyxJSON.encoder.encode(open)) == open)

        let finished = SessionLifecycle(sessionId: "s-1", phase: .finished, startedAt: Self.start,
                                        endedAt: Self.start.addingTimeInterval(3_120), summary: Self.masthead)
        let golden = #"{"endedAt":"2026-09-21T15:05:20Z","phase":"finished","sessionId":"s-1","startedAt":"2026-09-21T14:13:20Z","summary":{"avgBpm":131,"durationSec":3120,"hrSpark":[118,126,139,144,137,122],"name":"Upper A","prCount":2,"startedAt":"2026-09-21T14:13:20Z","tonnageKg":8450}}"#
        #expect(try json(finished) == golden)
        #expect(try OnyxJSON.decoder.decode(SessionLifecycle.self, from: Data(golden.utf8)) == finished)
        #expect(SessionLifecycle.Phase.allCases.map(\.rawValue) == ["open", "finished", "discarded"])
    }

    @Test("EffortPulse: golden JSON with its band, and it round-trips")
    func effortGolden() throws {
        let pulse = EffortPulse(sessionId: "s-1", exerciseId: "hack-squat", setIndex: 2, rpe: 9.5)
        #expect(pulse.band == .veryHard, "the band is derived from the rpe when not given")
        let golden = #"{"band":"veryHard","exerciseId":"hack-squat","rpe":9.5,"sessionId":"s-1","setIndex":2}"#
        #expect(try json(pulse) == golden)
        #expect(try OnyxJSON.decoder.decode(EffortPulse.self, from: Data(golden.utf8)) == pulse)
    }

    @Test("a context from a build with no session key decodes with session nil; one with it round-trips")
    func contextWithoutSessionDecodes() throws {
        let sent = WatchContext(userId: "u-1", today: "2026-09-08", schedule: schedule)
        var object = try #require(
            try JSONSerialization.jsonObject(with: try OnyxJSON.encoder.encode(sent)) as? [String: Any]
        )
        #expect(object["session"] == nil, "a nil session must not be encoded at all")
        object.removeValue(forKey: "session")
        let back = try OnyxJSON.decoder.decode(
            WatchContext.self, from: try JSONSerialization.data(withJSONObject: object)
        )
        #expect(back.session == nil)
        #expect(back == sent)

        var live = sent
        live.session = SessionLifecycle(sessionId: "s-1", phase: .finished, startedAt: Self.start,
                                        endedAt: Self.start.addingTimeInterval(3_120), summary: Self.masthead)
        let there = try OnyxJSON.decoder.decode(WatchContext.self, from: try OnyxJSON.encoder.encode(live))
        #expect(there.session == live.session)
        #expect(there == live)
    }

    // MARK: - Overhaul Lane A: the wire decode, the messaged finish, the front door

    /// A WatchConnectivity dictionary, spelled the way `WatchLink` builds one.
    private func wire(_ kind: String, _ value: some Encodable) throws -> [String: Any] {
        ["k": kind, "p": try OnyxJSON.encoder.encode(value)]
    }

    @Test("WatchLink's decode hands an effort pulse through intact (W0 open call 6)")
    func wireDecodesEffort() throws {
        let pulse = EffortPulse(sessionId: "s-1", exerciseId: "hack-squat", setIndex: 2, rpe: 8.5)
        #expect(WatchWire.decode(try wire("effort", pulse)) == .effort(pulse))
        // A malformed payload, an unknown kind and no kind at all are quiet
        // drops — a newer build may send what this one has never heard of.
        #expect(WatchWire.decode(["k": "effort", "p": Data("{}".utf8)]) == nil)
        #expect(WatchWire.decode(try wire("flourish", pulse)) == nil)
        #expect(WatchWire.decode(["p": Data()]) == nil)
        // A rest message with no payload IS the message: the clock stopped.
        #expect(WatchWire.decode(["k": "rest"]) == .rest(nil))
    }

    @Test("a finish carries its event count; a pulse from an older build decodes with none")
    func finishCarriesItsCount() throws {
        let row = WorkoutSession(id: "s-1", userId: "u-1", dayKey: "legs_a", date: "2026-09-21",
                                 startedAt: Self.start, endedAt: Self.start.addingTimeInterval(3_120))
        let finish = SessionPulse(row, phase: .finished, expectedEventCount: 14)
        #expect(WatchWire.decode(try wire("session", finish)) == .session(finish))
        #expect(SessionPulse(row, phase: .open, expectedEventCount: 14).expectedEventCount == nil,
                "only a finish waits for a count")

        var object = try #require(
            try JSONSerialization.jsonObject(with: try OnyxJSON.encoder.encode(finish)) as? [String: Any]
        )
        #expect(object["expectedEventCount"] as? Int == 14)
        object.removeValue(forKey: "expectedEventCount")
        let old = try OnyxJSON.decoder.decode(SessionPulse.self, from: try JSONSerialization.data(withJSONObject: object))
        #expect(old.expectedEventCount == nil)
    }

    @Test("the front door: open → Join, finished today → banner, discard or nothing → Start")
    func frontDoorTable() {
        var context = WatchContext(userId: "u-1", today: "2026-09-21", schedule: schedule)
        #expect(WatchFrontDoor.resolve(nil) == .start)
        #expect(WatchFrontDoor.resolve(context) == .start)

        let open = SessionLifecycle(sessionId: "s-1", phase: .open, startedAt: Self.start, date: "2026-09-21")
        context.session = open
        #expect(WatchFrontDoor.resolve(context) == .join(open))

        context.session = SessionLifecycle(sessionId: "s-1", phase: .finished, startedAt: Self.start,
                                           summary: Self.masthead, date: "2026-09-21")
        #expect(WatchFrontDoor.resolve(context) == .banner(Self.masthead))

        // Yesterday's finish is not today's banner.
        context.session?.date = "2026-09-20"
        #expect(WatchFrontDoor.resolve(context) == .start)

        // A discard says nothing happened — unless the tiles say something did.
        context.session = SessionLifecycle(sessionId: "s-2", phase: .discarded, startedAt: Self.start, date: "2026-09-21")
        #expect(WatchFrontDoor.resolve(context) == .start)
        context.tiles = WatchTiles(date: "2026-09-21", todayLabel: "Upper A", todayLogged: true, restDay: false)
        #expect(WatchFrontDoor.resolve(context) == .banner(nil))
    }

    @Test("a masthead off a closed row: stored totals, the row's HR, a six-point spark")
    func mastheadFromRow() throws {
        var row = WorkoutSession(id: "s-1", userId: "u-1", dayKey: "legs_a", date: "2026-09-21",
                                 startedAt: Self.start, totalVolumeKg: 8_450, prCount: 2)
        #expect(SessionMasthead(session: row, name: "Legs A", samples: []) == nil, "an open row has no masthead")
        row.endedAt = Self.start.addingTimeInterval(3_150)
        row.durationMin = 52
        let samples = (0..<12).map { HRSample(at: Self.start.addingTimeInterval(Double($0) * 60), bpm: 120 + $0) }
        let head = try #require(SessionMasthead(session: row, name: "Legs A", samples: samples))
        #expect(head.durationSec == 3_120, "duration_min wins over the wall interval")
        #expect(head.tonnageKg == 8_450)
        #expect(head.prCount == 2)
        #expect(head.avgBpm == 126, "no stored avg_bpm: the samples' mean")
        #expect(head.hrSpark == [120.5, 122.5, 124.5, 126.5, 128.5, 130.5])
        row.avgBpm = 131
        #expect(SessionMasthead(session: row, name: "Legs A", samples: samples)?.avgBpm == 131)
    }
}
