import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// The ledger the phone never used to write.
///
/// `PrEngine` itself is pinned by golden vectors against the TypeScript, so
/// nothing here re-tests what counts as a record. What is unproven is the three
/// things the TRANSLATION can get wrong, each of which fails silently: the
/// baseline window, the key the row is filed under, and whether the outbox
/// hears about it at all.
@Suite("The PR ledger, written from the phone")
struct PrRecorderTests {

    private let user = "u1"
    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    /// `onyx-hack-squat` is the slug the logger mints, so every case here is
    /// also the not-yet-synced path — the one where the catalogue row claims
    /// the id through its `slug` column (W2), never through a compiled deck.
    private func log(
        _ db: AppDatabase, id: String, date: String, weights: [Double], reps: Int = 8,
        exercise: String = "onyx-hack-squat", dayKey: String = "legs_a"
    ) throws {
        try db.writer.write { conn in
            try Exercise(id: "ex-hack", name: "Hack Squat", slug: "onyx-hack-squat").save(conn)
            try WorkoutSession(id: id, userId: user, dayKey: dayKey, date: date, startedAt: Date()).insert(conn)
            for (i, w) in weights.enumerated() {
                try WorkoutSet(
                    id: "\(id)-\(i)", sessionId: id, exerciseId: exercise,
                    setIndex: i + 1, weightKg: w, reps: reps
                ).insert(conn)
            }
        }
    }

    private func records(_ db: AppDatabase) throws -> [PersonalRecordRow] {
        try db.writer.read { conn in
            try PersonalRecordRow.order(Column("exercise_key"), Column("axis")).fetchAll(conn)
        }
    }

    /// A first-ever log is a data point, not a PR — `detectSetPrs` says so in
    /// as many words, and every case below is built on it. Two sets here, so
    /// the second has the first to beat.
    @Test("finishing a session files its records under the canonical NAME")
    func writesLedger() throws {
        let db = try store()
        try log(db, id: "s1", date: "2026-09-04", weights: [100, 110])
        _ = try db.closeSession(id: "s1")

        let rows = try records(db)
        #expect(!rows.isEmpty)
        // The key is what `useSessionDetail` looks a record up by, and it looks
        // it up by `exercises.name`. A raw `onyx-hack-squat` here renders a
        // trophy with no chips and nothing ever notices.
        #expect(Set(rows.map(\.exerciseKey)) == ["Hack Squat"])
        #expect(rows.allSatisfy { $0.sessionId == "s1" && $0.achievedOn == "2026-09-04" })
        // Every axis carries the winning set's load and reps — volume and e1RM
        // included, which stored null until 2026-08-03 and hung the chip on
        // whichever set happened to come last.
        #expect(rows.allSatisfy { $0.weightKg != nil && $0.reps != nil })
        let weight = try #require(rows.first { $0.axis == "weight" })
        #expect(weight.value == 110, "the set that BEAT the bar, not the one that set it")
    }

    @Test("every filed record is queued for the server under its natural key")
    func queuesForPush() throws {
        let db = try store()
        try log(db, id: "s1", date: "2026-09-04", weights: [100, 110])
        _ = try db.closeSession(id: "s1")

        let queued = try db.writer.read { conn in
            try OutboxItem.fetchAll(conn, sql: "SELECT * FROM outbox WHERE idempotency_key LIKE 'row:personal_records:%'")
        }
        #expect(!queued.isEmpty, "a record that never leaves the phone is not a record")
        // Composite key, ASCII-31 joined. A single-value id crashed the drainer
        // once already — see `rowID`.
        let refs = try queued.map { try OnyxJSON.decoder.decode(RowRef.self, from: $0.payload) }
        #expect(refs.allSatisfy { $0.id.split(separator: "\u{1f}").count == 3 })
        #expect(refs.allSatisfy { $0.table == "personal_records" })
    }

    /// The rule the whole ledger rests on, through the recorder.
    ///
    /// A first log has nothing to beat, so it files nothing and simply becomes
    /// the bar. Get this wrong — by letting an empty baseline count as a zero
    /// to clear — and every first session in the app's history reads as a clean
    /// sweep of records that never happened.
    @Test("a first-ever log sets the bar; it does not clear it")
    func firstLogIsNotARecord() throws {
        let db = try store()
        try log(db, id: "s1", date: "2026-09-04", weights: [100])
        _ = try db.closeSession(id: "s1")
        #expect(try records(db).isEmpty)

        try log(db, id: "s2", date: "2026-09-05", weights: [110])
        _ = try db.closeSession(id: "s2")
        #expect(try #require(try records(db).first { $0.axis == "weight" }).value == 110)
    }

    @Test("the baseline is the history WITHOUT this session, or nothing is ever a record")
    func baselineExcludesItself() throws {
        let db = try store()
        try log(db, id: "s1", date: "2026-09-01", weights: [100])
        _ = try db.closeSession(id: "s1")

        try log(db, id: "s2", date: "2026-09-04", weights: [120])
        _ = try db.closeSession(id: "s2")
        let after = try #require(try records(db).first { $0.axis == "weight" })
        #expect(after.value == 120 && after.sessionId == "s2")

        // Lighter than the standing record: NOT a weight record. If the session
        // sat in its own baseline this set would be measured against itself and
        // the heavier day's row would be overwritten by whichever session ran
        // last.
        try log(db, id: "s3", date: "2026-09-07", weights: [90])
        _ = try db.closeSession(id: "s3")
        let unchanged = try #require(try records(db).first { $0.axis == "weight" })
        #expect(unchanged.value == 120 && unchanged.sessionId == "s2", "a lighter day must not overwrite the record")
    }

    /// The natural key holds one row per axis, so a session's record REPLACES
    /// the floor row it beats. Without `floor_value` the floor died with that
    /// row, and deleting the session dropped the bar to whatever the remaining
    /// sets could account for — 100 here, below the 110 the book asserts.
    @Test("a beaten floor survives the deletion of the session that beat it")
    func floorSurvivesRetract() throws {
        let db = try store()
        try db.writer.write { conn in
            try PersonalRecordRow(userId: user, exerciseKey: "Hack Squat", axis: "weight", value: 110, achievedOn: "2026-08-10").insert(conn)
        }
        try log(db, id: "s1", date: "2026-09-01", weights: [100])
        try log(db, id: "s2", date: "2026-09-04", weights: [120])
        try db.writer.write { conn in _ = try PrRecorder.recomputeAll(conn, userId: user) }

        let beaten = try #require(try records(db).first { $0.axis == "weight" })
        #expect(beaten.value == 120 && beaten.sessionId == "s2", "120 beats the 110 floor")
        #expect(beaten.floorValue == 110, "the record carries the floor it replaced")

        try db.writer.write { conn in
            _ = try WorkoutSet.filter(Column("session_id") == "s2").deleteAll(conn)
            _ = try WorkoutSession.filter(Column("id") == "s2").deleteAll(conn)
            _ = try PrRecorder.replay(conn, userId: user, exerciseKey: "Hack Squat")
        }
        let floor = try #require(try records(db).first { $0.axis == "weight" })
        #expect(floor.value == 110 && floor.sessionId == nil && floor.floorValue == nil, "the floor is the bar again")
    }

    @Test("replaying every session lands the same ledger, twice over")
    func recomputeIsIdempotent() throws {
        let db = try store()
        try log(db, id: "s1", date: "2026-09-01", weights: [100])
        try log(db, id: "s2", date: "2026-09-04", weights: [120])
        try log(db, id: "s3", date: "2026-09-07", weights: [90])

        // No `closeSession` above: this is the one-off for sessions logged
        // before the recorder existed.
        try db.writer.write { conn in _ = try PrRecorder.recomputeAll(conn, userId: user) }
        let first = try records(db)
        #expect(!first.isEmpty)
        #expect(try #require(first.first { $0.axis == "weight" }).value == 120)

        try db.writer.write { conn in _ = try PrRecorder.recomputeAll(conn, userId: user) }
        #expect(try records(db) == first, "a second replay must change nothing")
    }

    /// ── THE 2026-09-11 FAILURE, IN ONE TEST ─────────────────────────────────
    ///
    /// One movement, its history under the CATALOGUE UUID (pulled from the web)
    /// and today's session under the SLUG (logged on this phone). That is not a
    /// contrived pairing — `nameResolver`'s own header calls it routine, and
    /// `LoggerModel.storedId` produces the slug for any movement the routine
    /// payload could not resolve.
    ///
    /// `baselines` filtered on the session's own ids, so the bar came back
    /// EMPTY, and an empty index awards no axis at all ("a delta against
    /// nothing is not a delta"). The visible result was a Legs & Core B session
    /// that stored `pr_count = 1` where a replay over the full ledger finds
    /// five — three movements' records lost in silence, with no error anywhere.
    ///
    /// The bar is now gathered under every id that resolves to the same
    /// canonical name and re-keyed to the one in hand, so this session is
    /// judged against the history that actually exists.
    @Test("a lift logged under two ids is judged against BOTH")
    func baselineSpansAliasedIds() throws {
        let db = try store()
        // The history, under the catalogue uuid the web writes: 100 kg.
        try log(db, id: "s1", date: "2026-09-04", weights: [100], exercise: "ex-hack")
        // Today, under the slug this phone mints for the same movement. TWO
        // sets, and that is the point — the first has nothing to beat under
        // either rule, so it is the SECOND that separates them: against the
        // session's own first set 90 is a new best, against the movement's
        // actual history it is 10 kg short.
        try log(db, id: "s2", date: "2026-09-11", weights: [80, 90], exercise: "onyx-hack-squat")
        _ = try db.closeSession(id: "s2")

        #expect(try records(db).first { $0.axis == "weight" } == nil,
                "90 kg does not beat a 100 kg history just because today's id is new")
        #expect(try db.writer.read { try WorkoutSession.fetchOne($0, key: "s2")?.prCount } == 0)

        // And the other direction: a set that DOES beat the aliased history is
        // filed, which is what makes this a widened bar rather than a mute one.
        try log(db, id: "s3", date: "2026-09-12", weights: [120], exercise: "onyx-hack-squat")
        _ = try db.closeSession(id: "s3")
        let beaten = try #require(try records(db).first { $0.axis == "weight" })
        #expect(beaten.value == 120 && beaten.sessionId == "s3")
    }

    /// A pair is ONE set of work, scored at its weaker side — and the local
    /// store spells the sides `left`/`right` while every OnyxCore rule that
    /// folds them tests `L`/`R`. Handed the local spelling, `volumeCredits`
    /// sees no pair and credits each row its own tonnage, so a split set could
    /// take a volume record that the same work logged unsided never would.
    @Test("a split set is scored at its weaker side, not once per arm")
    func pairCollapsesForTheVolumeAxis() throws {
        let db = try store()
        // The bar: one unsided set at 20 × 9 = 180 kg. Through `log`, so the
        // catalogue row, the session shape and the slug are the ones every
        // other case here is built on and `replay` is known to resolve.
        try log(db, id: "p1", date: "2026-09-04", weights: [20], reps: 9)
        try db.writer.write { conn in
            // Today: an ASYMMETRIC pair — the left arm pressed 20, the right
            // managed 16. One set of work at the weaker side: 16 × 10 = 160,
            // which is short of the 180 bar. Scored per-arm instead, the left
            // alone reads 200 and takes a volume record for a set that, as one
            // physical set, was the weakest of the three.
            try WorkoutSession(id: "p2", userId: user, dayKey: "legs_a", date: "2026-09-11", startedAt: Date()).insert(conn)
            try WorkoutSet(id: "p2-0", sessionId: "p2", exerciseId: "onyx-hack-squat",
                           setIndex: 1, weightKg: 20, reps: 10, side: "left", pairId: "pair-1").insert(conn)
            try WorkoutSet(id: "p2-1", sessionId: "p2", exerciseId: "onyx-hack-squat",
                           setIndex: 2, weightKg: 16, reps: 10, side: "right", pairId: "pair-1").insert(conn)
        }
        _ = try db.closeSession(id: "p2")

        #expect(try records(db).first { $0.axis == "volume" } == nil,
                "splitting a set must not invent tonnage the same work did not produce")
        // The e1RM axis DOES fire here and should: ten reps at 20 kg beats nine
        // at 20 kg, and that is a per-side claim about a load, not a claim
        // about how much work the set was. Only the VOLUME axis folds a pair.

        // ── `replay` TAKES THE SAME FIX AND IS NOT COVERED HERE ─────────────
        // `SessionEditing` runs `PrRecorder.replay` on every edit to a finished
        // session, and it builds its own candidates and its own baselines — so
        // it needs `SyncTranslation.domainSide` exactly as `record` does, and
        // it now has it at both of its call sites (the candidate builder and
        // the `seen` accumulator). It is NOT asserted here: a replay over this
        // two-session fixture files nothing at all, so every assertion about it
        // passes whether or not the pair collapsed, which is a test that proves
        // nothing. Covering it needs a fixture whose replay produces a record,
        // and that is a test worth writing on its own rather than smuggling
        // into this one.
    }

    // ── THE PHANTOM, AND THE LEDGER THAT KNEW BETTER (W7) ───────────────────

    /// A live bar must never sit below the record the ledger already holds.
    ///
    /// 2026-09-14: a 47.5 kg x 13 seated leg curl lit mid-session as 617.5 kg
    /// "was 550" on a movement the athlete had beaten before, and was gone
    /// after the next launch. The history was filed under a catalogue id this
    /// device had not pulled, so `nameResolver` could not name it, `baselines`
    /// could not gather its rows, and the bar was built from half a history —
    /// low rather than empty, which awards rather than declines.
    ///
    /// `personal_records` held the true mark the whole time. The live bar now
    /// reads it as a floor, so the deck and the ledger cannot disagree about
    /// what has already been done.
    @Test("the live bar cannot sit below the ledger's standing record")
    func liveBarHonoursTheLedger() throws {
        let db = try store()
        try db.writer.write { conn in
            try Exercise(id: "ex-curl", name: "Seated Leg Curl", slug: "onyx-seated-leg-curl").save(conn)
            try WorkoutSession(
                id: "s-old", userId: user, dayKey: "legs_a", date: "2026-08-01",
                startedAt: Date(), endedAt: Date()
            ).insert(conn)
            // What this device CAN see: 50 x 11, 550 kg of tonnage. This is the
            // "was 550" the phantom was measured against.
            try WorkoutSet(
                id: "old-1", sessionId: "s-old", exerciseId: "onyx-seated-leg-curl",
                setIndex: 1, weightKg: 50, reps: 11
            ).insert(conn)
            // The heavier set that holds the REAL best, filed under a catalogue
            // id no `exercises` row claims — the not-yet-pulled uuid.
            // `nameResolver` cannot name it, so `baselines` cannot gather it and
            // the bar stops at 550. A partial history, not an empty one: an
            // empty index awards nothing, a low one awards a phantom.
            try WorkoutSet(
                id: "old-2", sessionId: "s-old", exerciseId: "catalogue-uuid-not-pulled",
                setIndex: 2, weightKg: 50, reps: 14
            ).insert(conn)
            // What the ledger recorded when a client that COULD name that id
            // closed the session: 700 kg of single-set tonnage.
            try PersonalRecordRow(
                userId: user, exerciseKey: "Seated Leg Curl", axis: "volume",
                value: 700, sessionId: "s-old", achievedOn: "2026-08-01"
            ).insert(conn)
        }

        let bar = try db.livePrBaselines(
            exerciseIds: ["onyx-seated-leg-curl"], excluding: nil, dayKey: "legs_a",
            program: Program(id: "", label: "", days: [])
        )
        // 700, not the 550 the visible half of the history stops at — so a
        // 47.5 x 13 = 617.5 candidate is not a record.
        #expect(bar.bestSetVolume.first { $0.key == "onyx-seated-leg-curl" }?.value == 700,
                "617.5 must not read as a record against a ledger that already holds 700")
    }

    /// And the rebuild paths do NOT get that floor.
    ///
    /// `recomputeAll` upserts session by session over a table that still holds
    /// the previous answer. A floor taken from the standing record would judge
    /// the FIRST session against the all-time best, award nothing, and leave
    /// every stale row in place — a recompute that silently does nothing. The
    /// flag defaults off so the three rebuild paths keep the original tiers.
    @Test("a rebuild does not read standing records as floors")
    func rebuildIgnoresStandingRecords() throws {
        let db = try store()
        try log(db, id: "s1", date: "2026-09-04", weights: [100, 110])
        _ = try db.closeSession(id: "s1")
        let before = try records(db)
        #expect(!before.isEmpty)

        // Replaying over a populated ledger still reproduces it rather than
        // measuring the history against its own result.
        _ = try db.recomputeAllPrs(userId: user)
        #expect(try records(db).map(\.value) == before.map(\.value))
    }


    // MARK: - A set logged late (W2, decision 13)

    /// The interim record is filed at close, then a heavier set arrives for a
    /// date BEFORE it. Only a replay from the ledger can take the interim back:
    /// `record` upserts and would leave 105 standing beside a 110 it never saw.
    @Test("a heavier set logged a week late removes the interim PR and files the right one")
    func lateSetCorrectsTheLedger() throws {
        let db = try store()
        let noon = Date(timeIntervalSince1970: 1_789_128_000) // 2026-09-11 12:00 UTC
        func closed(_ id: String, _ date: String, _ kg: Double) throws {
            try log(db, id: id, date: date, weights: [kg - 10, kg])
            try db.closeSession(id: id, endedAt: noon)
        }
        try closed("s-old", "2026-08-28", 100)
        try closed("s-interim", "2026-09-04", 105)
        let interim = try #require(try records(db).first { $0.axis == "weight" })
        #expect(interim.value == 105 && interim.achievedOn == "2026-09-04")

        // A week later, the athlete remembers a 110 on 2026-08-31 — a retro
        // session, born closed, edited through `SessionEditing`.
        let retro = try db.createRetroSession(userId: user, dayKey: "legs_a", date: "2026-08-31")
        try db.writer.write { conn in try conn.execute(sql: "DELETE FROM outbox") }
        let outcome = try db.addSet(
            sessionId: retro.id, userId: user,
            SetSnapshot(exerciseId: "onyx-hack-squat", setIndex: 1, weightKg: 110, reps: 8)
        )
        #expect(outcome?.replayed == ["Hack Squat"])

        let corrected = try #require(try records(db).first { $0.axis == "weight" })
        #expect(corrected.value == 110)
        #expect(corrected.achievedOn == "2026-08-31")
        #expect(corrected.sessionId == retro.id, "the interim row is gone; the retro set holds the axis")
        #expect(try records(db).filter { $0.sessionId == "s-interim" }.isEmpty)

        // The server hears both halves: the axes the retro set did not win
        // back are queued as deletes, the ones it did as upserts, and no axis
        // carries both — `enqueueRowUpsert` drops the pending delete it
        // supersedes.
        let items = try db.pendingOutbox(limit: 100)
        let upserts = items.filter { $0.kind == SyncKind.rowUpsert }
        let deletes = items.filter { $0.kind == SyncKind.rowDelete }
        #expect(!upserts.isEmpty, "the corrected record is queued")
        #expect(
            Set(upserts.map(\.idempotencyKey)).isDisjoint(with: deletes.map(\.idempotencyKey)),
            "an axis is either re-filed or retracted, never both"
        )
    }

    @Test("lowering the only qualifying set retracts the record — a delete reaches the outbox")
    func loweringRetractsWithADelete() throws {
        let db = try store()
        let noon = Date(timeIntervalSince1970: 1_789_128_000)
        // One set is a data point, not a record; the 120 a week later is one.
        try log(db, id: "s1", date: "2026-08-28", weights: [100])
        try db.closeSession(id: "s1", endedAt: noon)
        try log(db, id: "s2", date: "2026-09-04", weights: [120])
        try db.closeSession(id: "s2", endedAt: noon)
        #expect(try records(db).first { $0.axis == "weight" }?.value == 120)
        try db.writer.write { conn in try conn.execute(sql: "DELETE FROM outbox") }

        // The 120 was a typo for 60: nothing beats the 100 any more, so there
        // is no record at all — and the server has to be TOLD, with a delete.
        _ = try db.amendSet(sessionId: "s2", userId: user, setId: "s2-0", weightKg: 60)
        #expect(try records(db).isEmpty)
        let deletes = try db.pendingOutbox(limit: 100).filter { $0.kind == SyncKind.rowDelete }
        #expect(deletes.contains { $0.idempotencyKey.contains("personal_records") }, "\(deletes.map(\.idempotencyKey))")
    }
}
