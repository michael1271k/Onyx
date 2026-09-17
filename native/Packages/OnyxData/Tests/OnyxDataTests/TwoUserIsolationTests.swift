import Testing
import Foundation
import GRDB
import OnyxCore
@testable import OnyxData

/// The artefact that proves W11: two users seeded into ONE store, and every
/// scoped reader asked for each, with the two result sets required to be
/// disjoint.
///
/// ── WHY ONE STORE AND NOT TWO ───────────────────────────────────────────────
/// The device holds one store, and the isolation claim is not "each account
/// gets its own file" — it is "a reader handed account A's id can never see
/// account B's row, even when both rows sit in the same tables". The only way
/// to test that is to put both users in one store and prove the filter, not the
/// filing. Every reader here takes an explicit `userId`; none uses the
/// single-user shim in `ScopedReads+Tests`, which would defeat the point.
///
/// The account-switch erase (`prepareForUser`) means a real device never holds
/// two users at once — but the erase can only be trusted BECAUSE the reads are
/// scoped underneath it. Both locks, tested where each lives.
struct TwoUserIsolationTests {
    let A = "00000000-0000-0000-0000-0000000000aa"
    let B = "00000000-0000-0000-0000-0000000000bb"

    /// One store holding a complete, parallel account for A and for B.
    private func twoUsers() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "iso")
        try db.seedRows { g in
            // The catalogue is shared (no user_id) — both accounts log the same movement.
            try Exercise(id: "x", name: "Back Squat", primaryMuscle: "quads").insert(g)

            for (u, sid, date) in [(A, "A-s1", "2026-09-02"), (B, "B-s1", "2026-09-02")] {
                // A finished session apiece, same day.
                try WorkoutSession(
                    id: sid, userId: u, dayKey: "legs_a", date: date,
                    startedAt: ISO8601DateFormatter().date(from: "\(date)T18:00:00Z"),
                    endedAt: ISO8601DateFormatter().date(from: "\(date)T19:00:00Z")
                ).insert(g)
                try WorkoutSet(id: "\(sid)-set", sessionId: sid, exerciseId: "x",
                               setIndex: 1, weightKg: u == A ? 100 : 60, reps: 5).insert(g)
                // A live (unfinished) session apiece on a later day.
                try WorkoutSession(id: "\(sid)-live", userId: u, dayKey: "legs_a", date: "2026-09-04").insert(g)
                try WorkoutSet(id: "\(sid)-live-set", sessionId: "\(sid)-live", exerciseId: "x",
                               setIndex: 1, weightKg: u == A ? 40 : 41, reps: 8).insert(g)
                // A standing record, a body reading, a cardio bout, a report.
                try PersonalRecordRow(userId: u, exerciseKey: "Back Squat", axis: "weight",
                                      value: u == A ? 100 : 60, sessionId: sid, achievedOn: date).insert(g)
                try BodyCompositionRow(id: "\(u)-b", userId: u, measuredAt: Date(), date: "2026-09-01",
                                       weightKg: u == A ? 82 : 61, createdAt: Date()).insert(g)
                try CardioLogRow(id: "\(u)-c", userId: u, date: date, kind: CardioImport.walk,
                                 durationMin: 20, createdAt: Date()).insert(g)
                try ReportRow(id: "\(u)-r", userId: u, type: "sentinel7",
                              periodStart: "2026-08-31", periodEnd: "2026-09-06",
                              contentMd: "report for \(u)", createdAt: Date()).insert(g)
                try DailyLogRow(id: "\(u)-d", userId: u, date: date,
                                createdAt: Date(), updatedAt: Date(),
                                nutritionEstimated: false, sleepOnsetTrouble: false).insert(g)
            }
        }
        return db
    }

    /// The two ids a reader must never confuse.
    private func ids(_ u: String) -> (session: String, live: String, set: String, body: String, cardio: String, report: String) {
        let p = u == A ? "A" : "B"
        return ("\(p)-s1", "\(p)-s1-live", "\(p)-s1-set", "\(u)-b", "\(u)-c", "\(u)-r")
    }

    @Test("every scoped reader returns A's rows to A and B's to B, and never crosses")
    func disjoint() throws {
        let db = try twoUsers()

        for me in [A, B] {
            let other = me == A ? B : A
            let mine = ids(me), theirs = ids(other)

            // sessions(on:) — same day, one session each.
            let day = try db.sessions(on: "2026-09-02", userId: me)
            #expect(day.map(\.id) == [mine.session])

            // session(id:) — mine resolves, theirs does not exist from here.
            #expect(try db.session(id: mine.session, userId: me)?.id == mine.session)
            #expect(try db.session(id: theirs.session, userId: me) == nil,
                    "\(me) resolved \(other)'s session")

            // sets(sessionId:) — mine has a set, theirs is invisible.
            #expect(try db.sets(sessionId: mine.session, userId: me).count == 1)
            #expect(try db.sets(sessionId: theirs.session, userId: me).isEmpty,
                    "\(me) read \(other)'s sets through the session join")

            // observeSets(sessionId:) — the observation reads the same request.
            let observed = try db.writer.read { conn in
                try AppDatabase.ownedSets(sessionId: theirs.session, userId: me).fetchAll(conn)
            }
            #expect(observed.isEmpty, "the observation crossed accounts")

            // liveSession / liveWorkoutInProgress — the unfinished one is mine.
            #expect(try db.liveSession(dayKey: "legs_a", date: "2026-09-04", userId: me)?.id == mine.live)
            #expect(try db.liveWorkoutInProgress(date: "2026-09-04", userId: me) == true)

            // sessionHistory / historySets — the whole ledger, and none of it theirs.
            let history = try db.sessionHistory(userId: me)
            #expect(Set(history.map(\.id)) == [mine.session, mine.live])
            #expect(!history.contains { $0.id == theirs.session })

            let allSets = try db.historySets(userId: me)
            #expect(Set(allSets.map(\.sessionId)) == [mine.session, mine.live])

            #expect(try db.historySets(sessionId: theirs.session, userId: me).isEmpty)
            let byExercise = try db.historySets(exerciseIds: ["x"], userId: me)
            #expect(Set(byExercise.map(\.sessionId)) == [mine.session, mine.live],
                    "the exercise ledger leaked the other account's sets")

            // personalRecords — the record book, keyed by name, scoped by user.
            let prs = try db.personalRecords(exerciseKey: "Back Squat", userId: me)
            #expect(prs.count == 1)
            #expect(prs.first?.value == (me == A ? 100 : 60))

            // cardio — filed against the session or logged on its day.
            let bouts = try db.cardio(sessionId: mine.session, date: "2026-09-02", userId: me)
            #expect(bouts.map(\.id) == [mine.cardio])
            #expect(!bouts.contains { $0.id == theirs.cardio })

            // bodyweight — the most recent scale reading.
            #expect(try db.bodyweight(onOrBefore: "2026-09-02", userId: me) == (me == A ? 82 : 61))

            // prFloors — the asserted-floor read PrRecorder.baselines uses.
            let floors = try db.prFloors(userId: me)
            #expect(floors["Back Squat"] != nil)

            // reportBody — mine reads, theirs is nil even by exact id.
            #expect(try db.reportBody(id: mine.report, userId: me) == "report for \(me)")
            #expect(try db.reportBody(id: theirs.report, userId: me) == nil)

            // WeeklyExportBuilder — the top-level history read; its sessions are mine.
            let export = try WeeklyExportBuilder(database: db, userId: me, timeZone: TimeZone(identifier: "UTC")!)
                .input(weekStart: "2026-08-31", today: "2026-09-06")
            // ExportSession has no id; the finished session's volume identifies it.
            let mineVol = Double(me == A ? 500 : 300), theirsVol = Double(other == A ? 500 : 300)
            let exportVols = Set(export.sessions.compactMap(\.volumeKg))
            #expect(exportVols.contains(mineVol))
            #expect(!exportVols.contains(theirsVol), "the weekly export carried \(other)'s session")

            // ScoringInputsBuilder.sets — the day's sets, scoped by the session's owner.
            let daySets = try db.writer.read { conn in
                try AppDatabase.sets(conn, sessionIds: [mine.session, theirs.session], userId: me)
            }
            #expect(Set(daySets.map(\.sessionId)) == [mine.session],
                    "the scorer summed the other account's sets into this day")

            // WidgetSnapshotBuilder — the whole payload, built for one user.
            let snapshot = try WidgetSnapshotBuilder(database: db, userId: me, timeZone: TimeZone(identifier: "UTC")!)
                .build(scope: .full, now: ISO8601DateFormatter().date(from: "2026-09-04T12:00:00Z")!)
            // The weight tile reads the latest scale row; it must be this user's.
            if let tileKg = snapshot.weight.kg {
                #expect(tileKg == (me == A ? 82 : 61), "the widget drew the other account's weight")
            }
        }
    }

    /// A write cannot file a row against the other account's session either —
    /// the edit doors resolve the session through `ownedSession`, so B's
    /// finished session simply "does not exist" from A.
    @Test("an edit to the other account's session is refused, not misattributed")
    func writesAreScoped() throws {
        let db = try twoUsers()
        #expect(throws: SessionEditing.EditError.self) {
            _ = try db.amendSet(sessionId: "B-s1", userId: A, setId: "B-s1-set", reps: 99)
        }
        // B's set is untouched.
        #expect(try db.sets(sessionId: "B-s1", userId: B).first?.reps == 5)

        // discardSession refuses across accounts (returns false, deletes nothing).
        #expect(try db.discardSession(id: "B-s1", userId: A) == false)
        #expect(try db.session(id: "B-s1", userId: B) != nil)

        // updateMetrics on the other account's session is a no-op.
        #expect(try db.updateMetrics(sessionId: "B-s1", userId: A, sessionRpe: 9) == nil)
    }
}
