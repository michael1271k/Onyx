import Foundation
import Testing
import OnyxCore
@testable import OnyxData

/// The local↔Postgres translation, case by case.
///
/// Every expectation here was read off the LIVE database on 2026-09-03, not off
/// the web app's `lib/supabase/types.ts`. Where a test asserts a string — `upper`, `L` —
/// that string is one Postgres already holds.
@Suite("Sync translation")
struct SyncTranslationTests {

    private func session(
        dayKey: String? = "legs_a",
        date: String = "2026-09-02",
        startedAt: Date? = Date(timeIntervalSince1970: 1_788_000_000),
        endedAt: Date? = nil,
        durationMin: Double? = nil,
        sessionRpe: Double? = nil,
        notes: String? = nil
    ) -> WorkoutSession {
        WorkoutSession(
            id: "s1", userId: "u1", dayKey: dayKey, date: date,
            startedAt: startedAt, endedAt: endedAt, durationMin: durationMin,
            sessionRpe: sessionRpe, notes: notes
        )
    }

    // MARK: The rename

    @Test("set_index becomes set_number — the whole reason this layer exists")
    func setIndexBecomesSetNumber() throws {
        let set = WorkoutSet(
            id: "set-1", sessionId: "s1", exerciseId: "helix5-hack-squat",
            setIndex: 3, weightKg: 100, reps: 8
        )
        let row = try SyncTranslation.setRow(set, userId: "u1", exerciseId: "uuid-1")
        #expect(row.setNumber == 3)

        // And on the wire it is spelled `set_number`. There is no `set_index`
        // column on the server at all, so a mis-spelled key is a 400 on the
        // whole batch, not a dropped field.
        let json = try JSONSerialization.jsonObject(
            with: OnyxJSON.encoder.encode(row)
        ) as? [String: Any]
        #expect(json?["set_number"] as? Int == 3)
        #expect(json?["set_index"] == nil)
    }

    // MARK: date ↔ started_at

    @Test("the session's `date` never reaches the wire — `started_at` carries it")
    func dateIsNotAColumn() throws {
        let row = try SyncTranslation.sessionRow(session(), now: Date())
        let json = try JSONSerialization.jsonObject(
            with: OnyxJSON.encoder.encode(row)
        ) as? [String: Any]
        #expect(json?["date"] == nil, "workout_sessions has no `date` column")
        #expect(json?["started_at"] != nil)
        // And the server owns `updated_at`: a client-stamped one from a slow
        // phone lands in a range the delta pull has already passed.
        #expect(json?["updated_at"] == nil)
    }

    @Test("`date` is derived back out of `started_at`, in the DEVICE's calendar")
    func dateIsDerivedFromStartedAt() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        // 2026-09-02 21:30 UTC is already 2026-09-03 in Jerusalem. The local
        // day is the device's, never the server's — deriving this in UTC is how
        // a Wednesday session files itself under Tuesday.
        let instant = Date(timeIntervalSince1970: 1_788_557_400)
        #expect(SyncTranslation.sessionDate(for: instant, calendar: calendar)
                == LogicalDay.iso(instant, calendar: calendar))
    }

    @Test("a session with no started_at falls back to NOON on its date")
    func startedAtFallsBackToNoon() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        let row = try SyncTranslation.sessionRow(
            session(startedAt: nil, endedAt: nil), now: Date(), calendar: calendar
        )
        // Round-trips to the same logical day. Midnight would not: formatted in
        // any timezone west of the calendar's it shows the day before.
        #expect(SyncTranslation.sessionDate(for: row.startedAt, calendar: calendar) == "2026-09-02")
        #expect(calendar.component(.hour, from: row.startedAt) == 12)
    }

    // MARK: split_day

    @Test("every ONYX-5 day key maps to a split_day the CHECK accepts")
    func splitDayCoversTheProgram() throws {
        let allowed: Set<String> = ["push", "pull", "legs", "upper", "lower"]
        for day in SampleDeck.onyx5.days {
            let split = try SyncTranslation.splitDay(forDayKey: day.key)
            #expect(allowed.contains(split), "\(day.key) → \(split) violates workout_sessions_split_day_check")
        }
        // The pairs the live database already holds.
        #expect(try SyncTranslation.splitDay(forDayKey: "cb_a") == "upper")
        #expect(try SyncTranslation.splitDay(forDayKey: "arms") == "upper")
        #expect(try SyncTranslation.splitDay(forDayKey: "legs_b") == "legs")
    }

    @Test("an unknown or missing day key throws rather than guessing")
    func unmappedDayKeyThrows() {
        // `split_day` is NOT NULL. A default of `upper` would file a leg day
        // under the wrong split forever, and silently — a rejected upload is
        // the visible failure and therefore the right one.
        #expect(throws: SyncError.unmappedDayKey(nil)) {
            _ = try SyncTranslation.splitDay(forDayKey: nil)
        }
        #expect(throws: SyncError.unmappedDayKey("legs_c")) {
            _ = try SyncTranslation.splitDay(forDayKey: "legs_c")
        }
    }

    // MARK: side

    @Test("side is L/R on the wire, never left/right")
    func sideIsAbbreviated() throws {
        #expect(try SyncTranslation.side("left") == "L")
        #expect(try SyncTranslation.side("right") == "R")
        // Idempotent: a row that has been to the server and back must not throw.
        #expect(try SyncTranslation.side("L") == "L")
        #expect(try SyncTranslation.side("R") == "R")
        #expect(try SyncTranslation.side(nil) == nil)
        #expect(try SyncTranslation.side("") == nil)
    }

    @Test("an unrecognised side throws — the PR engine compares these strings")
    func unmappedSideThrows() {
        #expect(throws: SyncError.unmappedSide("both")) {
            _ = try SyncTranslation.side("both")
        }
    }

    // MARK: rpe

    @Test("an out-of-range rating is dropped, not clamped — and never costs the workout")
    func rpeRespectsTheCheck() {
        // `rpe_range` is `rpe IS NULL OR (rpe >= 1 AND rpe <= 10)` and PostgREST
        // rejects the WHOLE statement on one bad row. Dropping the field loses
        // one number; keeping it loses the session, repeatedly.
        #expect(SyncTranslation.rpe(8.5) == 8.5)
        #expect(SyncTranslation.rpe(1) == 1)
        #expect(SyncTranslation.rpe(10) == 10)
        #expect(SyncTranslation.rpe(0) == nil)
        #expect(SyncTranslation.rpe(10.5) == nil)
        #expect(SyncTranslation.rpe(nil) == nil)
        // Clamping would invent a rating nobody gave.
        #expect(SyncTranslation.rpe(11) != 10)
    }

    // MARK: duration

    @Test("duration_min is an integer, rounded JavaScript's way")
    func durationUsesJsRound() throws {
        // The column is `integer` and the web app writes `Math.round` into it.
        // `rounded()` disagrees with `Math.round` on negative halves, and the
        // shim is the whole reason `jsRound` exists.
        let row = try SyncTranslation.sessionRow(session(durationMin: 46.5), now: Date())
        #expect(row.durationMin == 47)
        #expect(try SyncTranslation.sessionRow(session(durationMin: nil), now: Date()).durationMin == nil)
    }

    // MARK: The PostgREST key-set trap

    @Test("nil fields encode as null, so a bulk upsert's objects all match")
    func nilsAreEncodedNotOmitted() throws {
        // PostgREST builds ONE column list for a bulk upsert and rejects a body
        // whose objects have different key sets. Swift's synthesised Codable
        // omits a nil Optional, so a batch of two sets — one with a side, one
        // without — would fail as a whole. Hence the explicit `encode(to:)`.
        let bare = try SyncTranslation.setRow(
            WorkoutSet(id: "a", sessionId: "s1", exerciseId: "helix5-pec-deck",
                       setIndex: 1, weightKg: 40, reps: 12),
            userId: "u1", exerciseId: "uuid-1"
        )
        let full = try SyncTranslation.setRow(
            WorkoutSet(id: "b", sessionId: "s1", exerciseId: "helix5-pec-deck",
                       setIndex: 2, weightKg: 40, reps: 12, side: "left",
                       pairId: "p1", est1rmKg: 55, rpe: 8, exerciseOrder: 3,
                       durationSec: 300, incline: 2, distanceKm: 0.37, elevationM: 7.4),
            userId: "u1", exerciseId: "uuid-1"
        )

        func keys(_ row: RemoteSetRow) throws -> Set<String> {
            let object = try JSONSerialization.jsonObject(
                with: OnyxJSON.encoder.encode(row)
            ) as? [String: Any]
            return Set(object?.keys ?? [:].keys)
        }
        #expect(try keys(bare) == keys(full))
        #expect(try keys(bare).contains("side"))
        // Pinned to the CodingKeys count. Comparing two rows to each other
        // cannot catch a key added to `CodingKeys` and forgotten in the
        // hand-written `encode(to:)` — both rows would be wrong together, and
        // the missing column would silently stop being written.
        // 13 since `v16.exerciseOrder`, and the bump is the point: a set with no
        // order still writes the key as null, or a session logged half before
        // the upgrade and half after would send two shapes in one batch.
        // 16 since `v18.cardioSetFields`, for exactly the same reason: a
        // barbell row and a treadmill walk go up in ONE batch, so the barbell
        // row has to write `duration_sec`, `incline` and `distance_km` as null
        // rather than omit them.
        // 17 since `v19.cardioElevation`. The bump is deliberate and this
        // assertion is what forces it to be: `elevation_m` is a column
        // `cardio-elevation.sql (git history)` adds BY HAND, so a body naming it
        // fails the whole batch until the founder has run that file. Pinning
        // the count is what makes the dependency between the two impossible to
        // add by accident.
        #expect(try keys(bare).count == 17, "every RemoteSetRow CodingKey is encoded")
        for column in ["duration_sec", "incline", "distance_km", "elevation_m"] {
            #expect(try keys(bare).contains(column), "\(column) is on the wire")
        }

        // Same for the session row.
        let quiet = try SyncTranslation.sessionRow(session(), now: Date())
        let loud = try SyncTranslation.sessionRow(
            session(endedAt: Date(), durationMin: 47, sessionRpe: 8, notes: "hard"), now: Date()
        )
        func sessionKeys(_ row: RemoteSessionRow) throws -> Set<String> {
            let object = try JSONSerialization.jsonObject(
                with: OnyxJSON.encoder.encode(row)
            ) as? [String: Any]
            return Set(object?.keys ?? [:].keys)
        }
        #expect(try sessionKeys(quiet) == sessionKeys(loud))
        #expect(try sessionKeys(quiet).count == 13, "every encoded RemoteSessionRow key, and updated_at is not one")
    }

    @Test("an uncomputed aggregate is absent, not zeroed")
    func unportedColumnsAreOmitted() throws {
        let sessionJSON = try JSONSerialization.jsonObject(
            with: OnyxJSON.encoder.encode(
                try SyncTranslation.sessionRow(session(), now: Date())
            )
        ) as? [String: Any]
        // `nil` is not `0`. A zero volume is a claim about a workout; an absent
        // column is a gap in one. `status` is never sent at all — see the
        // builder's header.
        for column in ["total_volume_kg", "set_count", "pr_count", "status"] {
            #expect(sessionJSON?[column] == nil, "\(column) must not be written when unknown")
        }
    }

    @Test("a computed aggregate IS written, so the web reads the edited figures")
    func computedAggregatesAreWritten() throws {
        var row = session()
        row.totalVolumeKg = 1_160.5
        row.setCount = 18
        row.prCount = 2
        let json = try JSONSerialization.jsonObject(
            with: OnyxJSON.encoder.encode(try SyncTranslation.sessionRow(row, now: Date()))
        ) as? [String: Any]
        #expect(json?["total_volume_kg"] as? Double == 1_160.5)
        #expect(json?["set_count"] as? Int == 18)
        #expect(json?["pr_count"] as? Int == 2)
        // Still never sent, computed or not.
        #expect(json?["status"] == nil)

        let setJSON = try JSONSerialization.jsonObject(
            with: OnyxJSON.encoder.encode(try SyncTranslation.setRow(
                WorkoutSet(id: "a", sessionId: "s1", exerciseId: "helix5-pec-deck",
                           setIndex: 1, weightKg: 40, reps: 12),
                userId: "u1", exerciseId: "uuid-1"
            ))
        ) as? [String: Any]
        // An omitted column is left untouched by an upsert; `is_pr: false` would
        // overwrite a record the web app flagged.
        //
        // `exercise_order` LEFT this list in `v16` — see `ExerciseOrderTests`.
        // It is the one column here the phone has a real opinion about for
        // every set it logs, because the opinion is the deck on screen.
        for column in ["is_pr", "quality", "created_at"] {
            #expect(setJSON?[column] == nil, "\(column) must not be written yet")
        }
    }

    @Test("an empty note is not a note")
    func emptyNotesBecomeNull() throws {
        #expect(try SyncTranslation.sessionRow(session(notes: ""), now: Date()).notes == nil)
        #expect(try SyncTranslation.sessionRow(session(notes: "hard"), now: Date()).notes == "hard")
    }
}

@Suite("Sync backoff")
struct SyncBackoffTests {

    @Test("it doubles from the base and stops at the cap")
    func doublesAndCaps() {
        #expect(SyncBackoff.delay(attempts: 0) == 0)
        #expect(SyncBackoff.delay(attempts: 1) == SyncBackoff.base)
        #expect(SyncBackoff.delay(attempts: 2) == SyncBackoff.base * 2)
        #expect(SyncBackoff.delay(attempts: 5) == SyncBackoff.base * 16)
        // A write the server will never accept must not cost radio time
        // forever — but it is never dropped either, so the wait is capped and
        // not infinite.
        #expect(SyncBackoff.delay(attempts: 40) == SyncBackoff.cap)
        #expect(SyncBackoff.delay(attempts: 400) == SyncBackoff.cap)
        // Jitter stretches a step by up to a quarter and never past the cap:
        // two devices that failed together must not knock again together.
        #expect(SyncBackoff.delay(attempts: 1, jitter: 1) == SyncBackoff.base * 1.25)
        #expect(SyncBackoff.delay(attempts: 2, jitter: 0.5) == SyncBackoff.base * 2 * 1.125)
        #expect(SyncBackoff.delay(attempts: 40, jitter: 1) == SyncBackoff.cap)
        #expect(SyncBackoff.delay(attempts: 0, jitter: 1) == 0)
    }
}
