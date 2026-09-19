import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// The cascade, and the queue in front of it.
@Suite("The rescore cascade")
struct RescoreTests {

    private let user = "u1"
    /// The day the clock is pinned to for every test here.
    private let today = "2026-09-04"

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    /// 2026-09-04 14:00 UTC.
    private var now: Date { Date(timeIntervalSince1970: 1_788_530_400) }

    private func store() throws -> AppDatabase { try AppDatabase.inMemory(deviceId: "device-a") }

    private func goals(_ conn: Database) throws {
        try UserGoalRow(
            id: "g1", userId: user, sleepGoalHours: 8, calorieGoal: 1955,
            proteinGoalG: 190, carbsGoalG: 150, fatGoalG: 60, stepsGoal: 10_000,
            waterGoalMl: 3000, contextMode: "normal", createdAt: Date(), updatedAt: Date(),
            autoLogSupplements: false, activeProgram: "onyx5", dayCutoffHour: 0,
            unitSystem: "metric", reduceMotion: false, timezone: "Asia/Jerusalem", trackRpe: true
        ).insert(conn)
    }

    /// Goals plus `count` days of steps, written synchronously.
    ///
    /// Inside an `async` test `db.writer.write { }` resolves to GRDB's async
    /// overload, which wants an `await` the seeding does not need. A plain
    /// throwing helper keeps both kinds of test on one setup.
    private func seed(_ db: AppDatabase, from: String, count: Int) throws {
        try db.writer.write { conn in
            try goals(conn)
            try days(conn, from: from, count: count)
        }
    }

    /// A day with something on it, so `refreshDailyScore` has a row to write.
    private func days(_ conn: Database, from: String, count: Int) throws {
        for i in 0..<count {
            let d = ISODate.addDays(from, i)!
            try DailyMetricRow(
                id: "m\(i)", userId: user, date: d, steps: 2_000, createdAt: now, updatedAt: now
            ).insert(conn)
        }
    }

    // MARK: - The range

    @Test("the horizon is the readiness window, not a number typed beside it")
    func horizonFollowsReadiness() {
        #expect(Rescore.horizonDays == Readiness.constants.historyDays - 1)
        #expect(Rescore.horizonDays == 48, "if this moved, the web route's cap moved with it")
    }

    @Test("an edit reaches 48 days forward, and stops at today")
    func rangeIsBounded() {
        // Deep in the past: the full window, inclusive of the edited day.
        let full = Rescore.days(from: "2026-01-01", today: today)
        #expect(full.count == 49)
        #expect(full.first == "2026-01-01" && full.last == "2026-02-18")

        // Three days ago: clamped to today, not run out to the horizon.
        let recent = Rescore.days(from: "2026-09-01", today: today)
        #expect(recent == ["2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04"])

        // A session dated tomorrow is a swap, not an error, and there are no
        // stored scores after today to rewrite.
        #expect(Rescore.days(from: "2026-09-05", today: today).isEmpty)
    }

    // MARK: - The run

    @Test("every day from the edit forward is rewritten, sealed ones included")
    func cascadeForcesThroughTheFreeze() throws {
        let db = try store()
        try db.writer.write { conn in
            try goals(conn)
            try days(conn, from: "2026-08-30", count: 6)
        }
        // Seal the past days the way an ordinary sync would.
        for i in 0..<6 {
            _ = try db.refreshDailyScore(
                userId: user, date: ISODate.addDays("2026-08-30", i)!, now: now, calendar: calendar
            )
        }
        let sealed = try #require(try db.dailyScore(userId: user, date: "2026-08-31"))
        #expect(sealed.finalized, "a past day is sealed on first compute")

        // The edit: yesterday's steps were wrong.
        try db.writer.write { conn in
            try conn.execute(
                sql: "UPDATE daily_metrics SET steps = 11000 WHERE user_id = ? AND date = ?",
                arguments: [user, "2026-08-31"]
            )
        }
        let before = try #require(try db.dailyScore(userId: user, date: "2026-08-31")).activityScore

        let run = try db.rescore(
            userId: user, from: "2026-08-31", reason: .dayEdit, now: now, calendar: calendar
        )
        #expect(run.from == "2026-08-31")
        #expect(run.through == today, "clamped to today, five days on")
        #expect(run.written == 5)

        let after = try #require(try db.dailyScore(userId: user, date: "2026-08-31")).activityScore
        #expect(after != before, "the sealed day was rewritten — that is what force is for")
        // And the day BEFORE the edit is untouched: the cascade runs forward.
        let earlier = try #require(try db.dailyScore(userId: user, date: "2026-08-30"))
        #expect(earlier.finalized)
    }

    @Test("a rescored day equals a fresh compute of the same day")
    func idempotentAgainstAFreshStore() throws {
        func seeded() throws -> AppDatabase {
            let db = try store()
            try db.writer.write { conn in
                try goals(conn)
                try days(conn, from: "2026-09-01", count: 4)
                try WorkoutSession(
                    id: "s1", userId: user, dayKey: "legs_a", date: "2026-09-02",
                    startedAt: now, endedAt: now, durationMin: 62, sessionRpe: 8
                ).insert(conn)
            }
            return db
        }
        // One store scores the day once; the other scores it, then cascades
        // over it. The stored numbers must be identical — a cascade that
        // disagrees with a fresh compute is a second scoring rule.
        let fresh = try seeded()
        _ = try fresh.refreshDailyScore(userId: user, date: today, now: now, calendar: calendar)

        let cascaded = try seeded()
        _ = try cascaded.refreshDailyScore(userId: user, date: today, now: now, calendar: calendar)
        _ = try cascaded.rescore(userId: user, from: "2026-09-01", now: now, calendar: calendar)

        let a = try #require(try fresh.dailyScore(userId: user, date: today))
        let b = try #require(try cascaded.dailyScore(userId: user, date: today))
        #expect(a.score == b.score)
        #expect(a.batteryPct == b.batteryPct)
        #expect(a.sleepScore == b.sleepScore && a.workoutScore == b.workoutScore)
        #expect(a.recoveryScore == b.recoveryScore && a.activityScore == b.activityScore)
    }

    @Test("the outbox carries one row per date, however many times it was rescored")
    func outboxCollapsesPerDate() throws {
        let db = try store()
        try db.writer.write { conn in
            try goals(conn)
            try days(conn, from: "2026-09-01", count: 4)
        }
        _ = try db.rescore(userId: user, from: "2026-09-01", now: now, calendar: calendar)
        _ = try db.rescore(userId: user, from: "2026-09-01", now: now, calendar: calendar)
        _ = try db.rescore(userId: user, from: "2026-09-02", now: now, calendar: calendar)

        let keys = try db.pendingOutbox(limit: 200).map(\.idempotencyKey)
        #expect(keys.count == Set(keys).count, "no duplicates — `enqueueRowUpsert` replaces")
        #expect(keys.count == 4, "four dates, three cascades")
    }

    // MARK: - The queue

    @Test("three edits in a row are one cascade, from the earliest of them")
    func queueCoalesces() async throws {
        let db = try store()
        try seed(db, from: "2026-08-25", count: 11)
        let runs = RunLog()
        let queue = RescoreQueue(database: db, userId: user, calendar: calendar, now: { self.now }) { run in
            await runs.append(run)
        }
        // The order matters: the LAST request is the earliest date, which a
        // naive queue would drop because a run was already going.
        await queue.request(from: "2026-09-01", reason: .sessionEdit)
        await queue.request(from: "2026-08-29", reason: .sessionEdit)
        await queue.request(from: "2026-08-25", reason: .dayEdit)
        await queue.settle()

        let seen = await runs.all
        #expect(!seen.isEmpty)
        #expect(seen.allSatisfy { $0.through == today }, "every completed run reaches today")
        #expect(seen.map(\.from).min() == "2026-08-25", "the earliest edit is covered")
        // Whatever the interleaving, every day from the earliest edit forward
        // has a score — nothing is dropped by a run giving way.
        for i in 0..<11 {
            let d = ISODate.addDays("2026-08-25", i)!
            #expect(try db.dailyScore(userId: user, date: d) != nil, "\(d) was skipped")
        }
    }

    @Test("an old edit and a recent one cover BOTH ranges, not just the older one")
    func queueUnionsTheHorizons() async throws {
        let db = try store()
        // Two months of days, so the older edit's 49-day window stops well
        // short of today.
        try seed(db, from: "2026-07-20", count: 47)
        let runs = RunLog()
        let queue = RescoreQueue(database: db, userId: user, calendar: calendar, now: { self.now }) { run in
            await runs.append(run)
        }
        // 20 July + 48 = 6 September, which is BEFORE today. Folding the two
        // requests to the earlier date alone would stop there and leave the
        // days after it holding a score for data that changed.
        await queue.request(from: "2026-07-20", reason: .sessionEdit)
        await queue.request(from: "2026-09-02", reason: .sessionEdit)
        await queue.settle()

        let seen = await runs.all
        // A run that gives way reports the range it RESTARTED from, so the
        // earliest `from` here is 07-20 or the day after it depending on where
        // the second request landed. What must hold is the coverage below.
        #expect(seen.map(\.through).max() == today, "the later request's own end is reached")
        for i in 0..<47 {
            let d = ISODate.addDays("2026-07-20", i)!
            #expect(try db.dailyScore(userId: user, date: d) != nil, "\(d) was skipped")
        }
    }

    @Test("a future date is not work — a session dated tomorrow is a swap")
    func futureRequestsAreDropped() async throws {
        let db = try store()
        try seed(db, from: "2026-09-03", count: 2)
        let runs = RunLog()
        let queue = RescoreQueue(database: db, userId: user, calendar: calendar, now: { self.now }) { run in
            await runs.append(run)
        }
        await queue.request(from: "2026-09-20", reason: .dayEdit)
        await queue.settle()
        #expect(await runs.all.isEmpty)
    }

    @Test("a request while idle starts exactly one run")
    func queuePublishesOnce() async throws {
        let db = try store()
        try seed(db, from: "2026-09-03", count: 2)
        let runs = RunLog()
        let queue = RescoreQueue(database: db, userId: user, calendar: calendar, now: { self.now }) { run in
            await runs.append(run)
        }
        await queue.request(from: "2026-09-03", reason: .manual)
        await queue.settle()
        let seen = await runs.all
        #expect(seen.count == 1)
        #expect(seen.first?.from == "2026-09-03" && seen.first?.through == today)
        #expect(seen.first?.written == 2)
    }
}

/// Completed runs, in order. An actor because the queue reports from its own.
private actor RunLog {
    private(set) var all: [Rescore.Run] = []
    func append(_ run: Rescore.Run) { all.append(run) }
}
