import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// What a finished session's own figures MEAN, and what an edit is allowed to
/// do to its rows.
///
/// ── WHY THESE THREE, AND WHY HERE ───────────────────────────────────────────
/// The 2026-09-07 leg session is the fixture, in miniature. It broke three
/// different readers in three different ways on the same afternoon:
///
///   · its tonnage read 12,343 kg on the summary page and 13,242.5 kg in
///     `workout_sessions.total_volume_kg`, because the summary's callers
///     pre-filtered the warm-ups out of a rule whose own header says warm-ups
///     count;
///   · its Sets tile read 20 for 22 rows, for the same reason plus the cardio
///     bout;
///   · and reordering its movements in the edit deck was written to
///     `exercise_order` and read by nobody.
///
/// The first two are arithmetic that `SessionEditing.totals` — the function the
/// stored columns come from — has always had right, and the page now agrees
/// with. This suite pins that arithmetic, so the next reader that "fixes" it by
/// filtering fails here rather than in Postgres.
@Suite("A session's own figures")
struct SessionTruthTests {

    private let user = "u1"
    private let session = "s-legs"
    private let date = "2026-09-07"

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    /// 2026-09-07 in miniature: a treadmill bout that carries no load at all,
    /// a leg-press warm-up, three working sets, two hack squats and a calf
    /// press whose load is a half kilogram — so the total cannot be reached by
    /// anything that rounds.
    ///
    /// Written straight to the tables, no `set_events`: the shape a session
    /// logged on the web and pulled down here has, and the shape the real one
    /// was in when it was opened for editing.
    @discardableResult
    private func seed(_ db: AppDatabase) throws -> AppDatabase {
        try db.writer.write { conn in
            for (id, name) in [("ex-tread", "Treadmill"), ("ex-press", "Leg Press"),
                               ("ex-hack", "Hack Squat"), ("ex-calf", "Calf Press")] {
                try Exercise(id: id, name: name).insert(conn)
            }
            let start = LogicalDay.date(fromISO: date)!
            try WorkoutSession(
                id: session, userId: user, dayKey: "legs_a", date: date,
                startedAt: start, endedAt: start.addingTimeInterval(72 * 60), durationMin: 72,
                avgBpm: 122, caloriesBurned: 383
            ).insert(conn)

            var rows: [(String, Int, Int, Double, Int, String)] = []
            rows.append(("ex-tread", 0, 1, 0, 0, "warmup"))
            rows.append(("ex-press", 1, 1, 60, 15, "warmup"))      // 900
            for i in 0..<2 { rows.append(("ex-press", 1, i + 2, 100, 10, "normal")) }  // 2000
            rows.append(("ex-press", 1, 4, 100, 9, "normal"))      // 900
            rows.append(("ex-hack", 2, 1, 65, 10, "normal"))       // 650
            rows.append(("ex-hack", 2, 2, 60, 12, "normal"))       // 720
            rows.append(("ex-calf", 3, 1, 62.5, 9, "normal"))      // 562.5

            for (n, row) in rows.enumerated() {
                let (exercise, order, index, weight, reps, type) = row
                var set = WorkoutSet(
                    id: "set-\(n)", sessionId: session, exerciseId: exercise, setIndex: index,
                    weightKg: weight, reps: reps, setType: type, foldOrder: n
                )
                set.exerciseOrder = order
                if exercise == "ex-tread" {
                    set.durationSec = 300
                    set.incline = 2
                    set.distanceKm = 0.37
                }
                try set.insert(conn)
            }
        }
        return db
    }

    private func sets(_ db: AppDatabase) throws -> [WorkoutSet] {
        try db.sets(sessionId: session)
    }

    // MARK: - The volume rule

    @Test("a warm-up is a set that weighs nothing, and the cardio bout is a set")
    func totalsCountEverythingPerformed() throws {
        let db = try seed(try store())
        let totals = SessionEditing.totals(try sets(db))

        // 900 kg of leg-press warm-up is OUT since Precision Lane C (founder
        // decision Q13, the Hevy basis): 5,732.5 was the web's rule and the
        // 12,343-vs-13,242.5 gap the founder once reported ran the other way.
        #expect(totals.volumeKg == 4832.5, "a warm-up weighs nothing; 5732.5 means the web's rule is back")
        // The .5 survives: `sessionVolumeKg` ends at two decimals and nothing
        // downstream may round it away.
        #expect(totals.volumeKg != 4833)
        // Eight rows performed, of which six are working. "Sets" headlines the
        // eight; "Working" is the six (Q10).
        #expect(totals.count == 8, "the treadmill bout and the warm-up are sets that happened")
        #expect(totals.working == 6, "the bout and the warm-up are not working sets")
    }

    // MARK: - What an edit may not destroy

    @Test("editing one set does not erase the cardio bout beside it")
    func editKeepsTheCardioRow() throws {
        let db = try seed(try store())

        // The commonest gesture on the edit deck: correct a load. It seeds the
        // event log from the projection on the way in — a ONE-WAY door — and
        // then rebuilds every row of the session from the fold.
        let outcome = try db.amendSet(
            sessionId: session, setId: "set-4", weightKg: 105, est1rmKg: 140
        )
        #expect(outcome != nil)

        let after = try sets(db)
        #expect(after.count == 8, "a re-fold that loses rows is how a session loses a set")

        // The bout is still a bout. `SetSnapshot` carries the three axes and
        // `seedEventLog` writes them, or the first edit of any session holding
        // one re-renders it as `0kg × 0` and pushes that over the server.
        let bout = try #require(after.first { $0.exerciseId == "ex-tread" })
        #expect(bout.durationSec == 300)
        #expect(bout.incline == 2)
        #expect(bout.distanceKm == 0.37)
    }

    // MARK: - The reorder

    @Test("a movement's new position reaches the ledger every reader uses")
    func reorderSurvivesTheSave() throws {
        let db = try seed(try store())

        // The deck drags Hack Squat above Leg Press. `LoggerModel.moveExercise`
        // re-amends every logged row of every movement the drag shifted, and the
        // only thing that changes on those rows is `exercise_order`.
        for (setId, order) in [("set-5", 1), ("set-6", 1), ("set-1", 2),
                               ("set-2", 2), ("set-3", 2), ("set-4", 2)] {
            let outcome = try db.amendSet(sessionId: session, setId: setId, exerciseOrder: order)
            // ── AND IT MUST NOT BE READ AS A NO-OP ──────────────────────────
            // `amendSet` compares the patch against the row and declines an
            // amend that restates it. An order-only change restates every other
            // column, so a comparison that ignored `exercise_order` would
            // silently drop the whole reorder here.
            #expect(outcome != nil, "an order-only amend is a real edit")
        }

        // The projection has it…
        let placed = Dictionary(
            try sets(db).map { ($0.id, $0.exerciseOrder) }, uniquingKeysWith: { first, _ in first }
        )
        #expect(placed["set-5"] == 1)
        #expect(placed["set-1"] == 2)

        // …and so does the query the session page, the history list and the
        // ledger all read. It was absent from the SELECT, which is why the
        // reorder was invisible on a phone that had written it correctly.
        let ledger = try db.historySets(sessionId: session)
        #expect(ledger.first { $0.id == "set-5" }?.exerciseOrder == 1)
        #expect(ledger.first { $0.id == "set-0" }?.exerciseOrder == 0, "the treadmill did not move")
    }
}
